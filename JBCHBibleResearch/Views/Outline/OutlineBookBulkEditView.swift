//
//  OutlineBookBulkEditView.swift
//  JBCHBibleResearch
//
//  `OutlineTreeView.swift`에서 "책"을 선택하면 책 개요를, "장"을 선택하면 그 장 개요를
//  오른쪽(iPhone은 push 이동)에 보여주는 화면. 한 화면에 편집 대상은 하나뿐이다 —
//  `focusedChapter == nil`이면 책 개요만, 있으면 그 장 개요만 그리며 다른 장의 접힌 행도
//  그리지 않는다(여러 장을 아코디언으로 훑던 일괄 편집 기능은 없다).
//
//  ⚠️ "BulkEdit"라는 이름은 현재 동작과 맞지 않지만, 이름을 바꾸면 참조하는 여러 파일
//  (`OutlineTreeView`, `ChapterRelatedContentPanel`, `OutlineNavigationRequest`,
//  `SettingsView`, `OutlineSeedExporter`/`OutlineSeedImporter` 등)을 건드려야 해서
//  그대로 두었다.
//
//  자동저장은 다른 에디터 화면(`MemoDetailView`, `WordSummaryEditorView`)과 같은
//  `AutosaveController`를 쓴다. 단일 큰 에디터 + `.frame(maxHeight: .infinity)` 구조는
//  `MemoDetailView`와 같은 레이아웃이다.
//

import SwiftUI
import SwiftData
import BibleResearchModels

struct OutlineBookBulkEditView: View {
    @Environment(\.modelContext) private var modelContext
    /// 화면 배경/타이틀 글자색이 읽기 테마를 따르게 하기 위한 프로퍼티.
    /// ⚠️ 에디터(`RichTextEditor`) 자체의 배경/글자색에는 쓰지 않는다 — 에디터 창은
    /// 읽기 테마와 무관한 고정 기본값이다(`EditorDefaultStyle.swift` 참고).
    private var settings: UserSettingsStore { .shared }
    let book: Book
    var focusedChapter: Int? = nil
    var initialIsEditable: Bool = true

    @State private var bookOutline: BookOutline?
    @State private var chapterSummary: ChapterSummary?
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
        Group {
            if let focusedChapter {
                chapterOnlyEditor(focusedChapter)
            } else {
                bookOutlineOnlyEditor
            }
        }
        // 화면 바깥쪽 배경만 읽기 테마를 따른다(에디터 자체 배경은 고정).
        .background(settings.bibleBackgroundColor ?? Color.clear)
        // 장 선택 시 "책이름 N장", 책 개요만 볼 때는 책 이름을 타이틀로 쓴다.
        .navigationTitle(focusedChapter.map { "\(book.nameKo) \($0)장" } ?? book.nameKo)
        // 다른 화면과 같이 `.principal` 툴바 아이템 + `.inline` 타이틀 모드로 성곡 세리프
        // 20pt 타이틀을 중앙에 표시한다. 위 `.navigationTitle`은 시스템 내부용으로 두고
        // 같은 문자열 계산식을 재사용한다.
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .principal) {
                Text(focusedChapter.map { "\(book.nameKo) \($0)장" } ?? book.nameKo)
                    .font(.custom(SpecialPurposeFonts.titleSerif, size: 20, relativeTo: .title3))
                    .fontWeight(.semibold)
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isEditable.toggle()
                } label: {
                    Image(systemName: isEditable ? "eye" : "pencil")
                }
                .help(isEditable ? "읽기 전용으로 보기" : "편집하기")
            }
        }
        .onAppear {
            setUpIfNeeded()
        }
        .onDisappear {
            autosave?.flush()
            // 검색 인덱스(FTS5 보조 인덱스) 갱신 — 화면을 벗어날 때 한 번 한다. 개요엔
            // 본문 변경 여부 플래그가 없어 매번 upsert하지만(delete+insert라 멱등),
            // 화면당 1회뿐이라 비용은 무시할 만하다.
            if let bookOutline {
                UserContentSearchIndexLocation.upsert(
                    category: .outline, sourceId: bookOutline.id.uuidString, content: bookOutline.contentText
                )
            }
            if let chapterSummary {
                UserContentSearchIndexLocation.upsert(
                    category: .chapterSummary, sourceId: chapterSummary.id.uuidString, content: chapterSummary.contentText
                )
            }
        }
    }

    // MARK: - 책 개요 전용 화면

    /// 책을 선택했을 때(`focusedChapter == nil`) 책 개요 에디터 하나만 보여준다.
    @ViewBuilder
    private var bookOutlineOnlyEditor: some View {
        // 위 `.principal` 타이틀과 중복되므로 에디터 상단에 별도 제목 `Text`를 두지 않는다.
        VStack(alignment: .leading, spacing: 8) {
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
                    readOnlyBackgroundColor: EditorDefaultStyle.backgroundColor,
                    // macOS 네이티브 서식 도구(`usesInspectorBar`/`usesFontPanel`/`usesRuler`)엔
                    // 커스텀 툴바에 없는 줄간격(문단 간격) 조절 등이 있어, 끄면 기능이 빠진다.
                    // 그래서 macOS는 네이티브 방식(`false`)을 유지한다.
                    showsToolbarOnMac: false
                )
                // 남은 세로 공간을 전부 차지하게 한다(`MemoDetailView`와 같은 패턴).
                .frame(maxHeight: .infinity)
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
        }
        .padding()
    }

    // MARK: - 장 개요 전용 화면

    /// 장을 선택했을 때(`focusedChapter`가 있음) 그 장 개요 에디터 하나만 보여준다.
    @ViewBuilder
    private func chapterOnlyEditor(_ chapter: Int) -> some View {
        // 위 `.principal` 타이틀과 중복되므로 별도 제목 `Text`를 두지 않는다.
        VStack(alignment: .leading, spacing: 8) {
            if let chapterSummary {
                RichTextEditor(
                    rtfText: Binding(
                        get: { chapterSummary.contentHtml },
                        set: { newValue in
                            chapterSummary.contentHtml = newValue
                            chapterSummary.updatedAt = .now
                            autosave?.scheduleSave()
                        }
                    ),
                    plainText: Binding(
                        get: { chapterSummary.contentText },
                        set: { chapterSummary.contentText = $0 }
                    ),
                    isEditable: isEditable,
                    typingFont: EditorDefaultStyle.typingFont,
                    defaultTextColor: EditorDefaultStyle.textColor,
                    lineHeightMultiple: EditorDefaultStyle.lineHeightMultiple,
                    editingBackgroundColor: EditorDefaultStyle.backgroundColor,
                    readOnlyBackgroundColor: EditorDefaultStyle.backgroundColor,
                    // 위 `bookOutlineOnlyEditor`와 같은 이유로 macOS 네이티브 서식 도구를 유지한다.
                    showsToolbarOnMac: false
                )
                .frame(maxHeight: .infinity)
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
        }
        .padding()
    }

    // MARK: - 로드

    /// 화면에 필요한 객체 하나(책 개요 또는 선택한 장의 `ChapterSummary`)만
    /// find-or-create한다. 시편 3장을 열 때 나머지 149개 장을 만들지 않는다(O(1)).
    private func setUpIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true

        do {
            if let focusedChapter {
                chapterSummary = try ChapterSummaryDeduplication.findOrCreateChapterSummary(
                    bookId: book.bookId, chapter: focusedChapter, context: modelContext
                )
            } else {
                bookOutline = try BookOutlineDeduplication.findOrCreateBookOutline(bookId: book.bookId, context: modelContext)
            }
            try modelContext.save()
        } catch {
            print("[OutlineBookBulkEditView] 로드 실패: \(error)")
        }

        autosave = AutosaveController(modelContext: modelContext)
    }
}
