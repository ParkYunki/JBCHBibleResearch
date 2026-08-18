//
//  OutlineBookBulkEditView.swift
//  JBCHBibleResearch
//
//  [2026-08-14 신설] `OutlineTreeView.swift` 상단 주석 참고 — 트리에서 "책"을
//  선택하면 이 화면이 책 개요 + 그 책의 모든 장 개요를 아코디언(장마다 개별
//  접기/펼치기)으로 함께 보여준다("일괄로 편집"). 트리에서 "장"을 선택하면
//  같은 화면이 뜨되 `focusedChapter`로 넘어온 그 장만 펼쳐진 채로 시작한다
//  ("그 특정장만 수정"). 두 요구를 같은 화면 하나로 만족시킨다 — 장을
//  나중에 언제든 펼치거나 접을 수 있으므로 굳이 화면을 분리할 이유가 없다.
//
//  자동저장은 책 개요 + 모든 장 개요가 같은 `AutosaveController` 하나를
//  공유한다 — 그 타입은 "지금 이 컨텍스트에 저장할 변경이 있는지"만 다뤄
//  어떤 객체가 바뀌었는지는 상관하지 않는다(그 타입 상단 주석 참고). 화면
//  하나에 에디터가 여러 개(최대 수십~150개, 예: 시편) 뜰 수 있어 컨트롤러를
//  객체마다 따로 두면 오히려 관리가 복잡해진다.
//
//  ⚠️ [성능, 명확히 플래그] "모두 펼치기"를 누르면 그 책의 장 수만큼(시편은
//  150개) 실제 `RichTextEditor`(내부적으로 진짜 UITextView/NSTextView)를
//  한꺼번에 마운트한다 — 사용자가 명시적으로 요청한 "일괄 편집" 기능이라
//  그대로 구현했지만, 실기기에서 큰 책을 전부 펼치면 스크롤이 버벅일 수
//  있다(컴파일/실기기 검증 불가 환경이라 확인은 못 했다). 접힌 장은
//  `RichTextEditor` 자체를 그리지 않아(아래 `chapterRow` 참고) 최소한 기본
//  상태(장 하나만 포커스, 또는 전부 접힌 채 시작)는 가볍다.
//

import SwiftUI
import SwiftData
import BibleResearchModels

struct OutlineBookBulkEditView: View {
    @Environment(\.modelContext) private var modelContext
    let book: Book
    var focusedChapter: Int? = nil
    var initialIsEditable: Bool = true

    @State private var bookOutline: BookOutline?
    @State private var chapterSummaries: [Int: ChapterSummary] = [:]
    @State private var expandedChapters: Set<Int> = []
    @State private var autosave: AutosaveController?
    @State private var isEditable: Bool
    @State private var hasLoaded = false

    init(book: Book, focusedChapter: Int? = nil, initialIsEditable: Bool = true) {
        self.book = book
        self.focusedChapter = focusedChapter
        self.initialIsEditable = initialIsEditable
        _isEditable = State(initialValue: initialIsEditable)
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            List {
                Section {
                    bookOutlineEditor
                        .padding(.vertical, 4)
                } header: {
                    // [2026-08-15 4차 변경] 사용자 요청 — "리치 텍스트 에디터 영역
                    // 상단 타이틀 'xxx 책 개요' ... 글자 스타일을 시스템 기본 폰트
                    // 일반 크기로." 기존 `.caption`(작은 보조 텍스트 크기)을
                    // `.body`(시스템 기본, "일반" 크기)로 바꿨다.
                    Text("\(book.nameKo) 책 개요").font(.body)
                }

                Section {
                    ForEach(1...max(book.chapterCount, 1), id: \.self) { chapter in
                        chapterRow(chapter)
                            .id(chapter)
                    }
                } header: {
                    HStack {
                        // [2026-08-15 4차 변경] 위 "책 개요" 타이틀과 같은 이유로
                        // `.caption` → `.body`. "모두 펼치기"/"모두 접기" 버튼은
                        // 보조 동작이라 요청 범위 밖으로 보고 `.caption`을 유지했다.
                        Text("장별 개요").font(.body)
                        Spacer()
                        // 사용자 요청 — "장 편집은 일괄 접기 일괄펼치기 ... 할 것."
                        Button("모두 펼치기") {
                            expandedChapters = Set(1...max(book.chapterCount, 1))
                        }
                        .font(.caption)
                        Button("모두 접기") {
                            expandedChapters = []
                        }
                        .font(.caption)
                    }
                }
            }
            .listStyle(.plain)
            .onAppear {
                setUpIfNeeded()
                if let focusedChapter {
                    DispatchQueue.main.async {
                        scrollProxy.scrollTo(focusedChapter, anchor: .top)
                    }
                }
            }
        }
        .navigationTitle(book.nameKo)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isEditable.toggle()
                } label: {
                    Image(systemName: isEditable ? "eye" : "pencil")
                }
                .help(isEditable ? "읽기 전용으로 보기" : "편집하기")
            }
        }
        .onDisappear {
            autosave?.flush()
        }
    }

    // MARK: - 책 개요

    @ViewBuilder
    private var bookOutlineEditor: some View {
        if let bookOutline {
            RichTextEditor(
                rtfText: Binding(
                    get: { bookOutline.contentHtml },
                    set: { newValue in
                        bookOutline.contentHtml = newValue
                        bookOutline.updatedAt = .now
                        autosave?.scheduleSave()
                    }
                ),
                plainText: Binding(
                    get: { bookOutline.contentText },
                    set: { bookOutline.contentText = $0 }
                ),
                isEditable: isEditable,
                typingFont: EditorDefaultStyle.typingFont,
                defaultTextColor: EditorDefaultStyle.textColor,
                lineHeightMultiple: EditorDefaultStyle.lineHeightMultiple,
                editingBackgroundColor: EditorDefaultStyle.backgroundColor,
                readOnlyBackgroundColor: EditorDefaultStyle.backgroundColor
            )
            .frame(minHeight: 160)
        } else {
            ProgressView().frame(minHeight: 160)
        }
    }

    // MARK: - 장별 개요 (아코디언)

    @ViewBuilder
    private func chapterRow(_ chapter: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: expandedChapters.contains(chapter) ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                Text("\(chapter)장").font(.body)
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { toggleChapter(chapter) }
            .padding(.vertical, 4)

            if expandedChapters.contains(chapter), let summary = chapterSummaries[chapter] {
                RichTextEditor(
                    rtfText: Binding(
                        get: { summary.contentHtml },
                        set: { newValue in
                            summary.contentHtml = newValue
                            summary.updatedAt = .now
                            autosave?.scheduleSave()
                        }
                    ),
                    plainText: Binding(
                        get: { summary.contentText },
                        set: { summary.contentText = $0 }
                    ),
                    isEditable: isEditable,
                    typingFont: EditorDefaultStyle.typingFont,
                    defaultTextColor: EditorDefaultStyle.textColor,
                    lineHeightMultiple: EditorDefaultStyle.lineHeightMultiple,
                    editingBackgroundColor: EditorDefaultStyle.backgroundColor,
                    readOnlyBackgroundColor: EditorDefaultStyle.backgroundColor
                )
                .frame(minHeight: 200)
                .padding(.bottom, 8)
            }
        }
    }

    private func toggleChapter(_ chapter: Int) {
        if expandedChapters.contains(chapter) {
            expandedChapters.remove(chapter)
        } else {
            expandedChapters.insert(chapter)
        }
    }

    // MARK: - 로드

    private func setUpIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true

        if let focusedChapter {
            expandedChapters = [focusedChapter]
        }

        do {
            bookOutline = try BookOutlineDeduplication.findOrCreateBookOutline(bookId: book.bookId, context: modelContext)
            var summaries: [Int: ChapterSummary] = [:]
            for chapter in 1...max(book.chapterCount, 1) {
                summaries[chapter] = try ChapterSummaryDeduplication.findOrCreateChapterSummary(
                    bookId: book.bookId, chapter: chapter, context: modelContext
                )
            }
            chapterSummaries = summaries
            try modelContext.save()
        } catch {
            print("[OutlineBookBulkEditView] 로드 실패: \(error)")
        }

        autosave = AutosaveController(modelContext: modelContext)
    }
}
