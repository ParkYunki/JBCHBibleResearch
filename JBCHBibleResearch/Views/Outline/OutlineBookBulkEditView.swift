//
//  OutlineBookBulkEditView.swift
//  JBCHBibleResearch
//
//  [2026-08-14 신설] `OutlineTreeView.swift` 상단 주석 참고 — 트리에서 "책"을
//  선택하면 이 화면이 책 개요를, "장"을 선택하면 그 장 개요를 오른쪽(또는
//  iPhone은 push 이동)에 보여준다.
//
//  [2026-08-27 재설계] 사용자 요청 — "[개요] 기능 공통 수정사항 ... 현재
//  모든 장이 접혀지고, 클릭(탭)한 장만 펼쳐져서 나오는데, 접혀진 장도 안
//  나오게 변경할 것. 클릭(탭)한 장만 나오도록 수정. 해당 장이 상단 타이틀로
//  나오고 에디터 영역을 크게해서 해당 장만 조회/수정할 수 있도록. 성경에
//  대한 개요를 입력하려고 해도 동일하게 -> 개요만 조회/수정할 수 있도록."
//
//  2026-08-14 최초 설계는 "책을 선택 → 책 개요 + 그 책의 모든 장을
//  아코디언으로 한 화면에서 일괄 편집"을 명시적으로 요청받아 구현했던
//  것이다(장마다 접기/펼치기, "모두 펼치기"/"모두 접기" 버튼, `focusedChapter`
//  로 넘어온 장만 처음에 펼쳐진 채 시작). 이번 요청은 그 설계를 뒤집는다 —
//  이제 이 화면은 딱 하나만 보여준다: 책을 선택했으면(`focusedChapter == nil`)
//  책 개요 하나만, 장을 선택했으면(`focusedChapter`가 있으면) 그 장 개요
//  하나만. 다른 장들의 "접힌 행"조차 더 이상 그리지 않는다 — 그 결과 "모두
//  펼치기/모두 접기"로 여러 장을 한 화면에서 훑어보던 일괄 편집 기능 자체가
//  없어진다는 점은 분명히 짚어 둔다(필요해지면 다시 요청 시 별도 진입점으로
//  되살릴 수 있다).
//
//  ⚠️ 이름("BulkEdit")이 이제 실제 동작과 맞지 않는 낡은 이름이 됐지만,
//  타입/파일 이름을 바꾸면 이 화면을 참조하는 여러 파일(`OutlineTreeView`,
//  `ChapterRelatedContentPanel`, `OutlineNavigationRequest`, `SettingsView`,
//  `OutlineSeedExporter`/`OutlineSeedImporter` 등)을 전부 건드리게 되어 이번
//  요청 범위를 넘어서는 변경이 된다고 판단해, 이름은 그대로 두고 동작만
//  바꿨다.
//
//  자동저장은 여전히 `AutosaveController`를 쓴다 — 이제 한 화면에 편집 대상이
//  하나(책 개요 또는 장 개요 중 하나)뿐이라 여러 객체를 함께 다룰 필요는
//  없어졌지만, 다른 에디터 화면들(`MemoDetailView`, `WordSummaryEditorView`)과
//  같은 컨트롤러 타입을 그대로 재사용하는 편이 일관적이다.
//
//  화면 구조(단일 큰 에디터 + `.frame(maxHeight: .infinity)`)는 `MemoDetailView`
//  가 2026-08-09에 같은 이유("에디터 영역을 크게")로 이미 `ScrollView`/`List`를
//  걷어내고 바꾼 전례를 그대로 따른다 — 새 레이아웃 기법을 만들지 않았다.
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
        // [2026-08-27 신설] 사용자 요청 — "해당 장이 상단 타이틀로 나오고."
        // 장을 선택했을 때는 "책이름 N장"을, 책 개요만 볼 때는 기존처럼 책
        // 이름만 타이틀로 쓴다(macOS는 창 제목 표시줄, iOS는 내비게이션
        // 타이틀로 나온다 — 이 화면이 이미 `.navigationTitle`을 쓰던 기존
        // 관례를 그대로 따른다).
        .navigationTitle(focusedChapter.map { "\(book.nameKo) \($0)장" } ?? book.nameKo)
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
        .onAppear {
            setUpIfNeeded()
        }
        .onDisappear {
            autosave?.flush()
            // [2026-09-05 추가] 사용자 요청 — "개요/메모/개인 묵상/말씀
            // 요약/연구문서 5개 카테고리 전체스캔 최적화 → FTS5 보조
            // 인덱스(unicode61)." `MemoDetailView.handleDisappear()`/
            // `WordSummaryEditorView.handleDisappear()`와 같은 지점(화면을
            // 벗어날 때) — 개요는 그 두 화면과 달리 `pendingIndexRefresh`
            // 같은 "본문이 실제로 바뀌었는지" 플래그가 없으므로(VerseMention
            // 재인덱싱 대상이 아니라 애초에 그런 플래그가 필요 없었다) 매번
            // 무조건 upsert한다 — delete+insert라 여러 번 불러도 결과는
            // 같고, 화면 하나 닫을 때 1회뿐이라 비용도 무시할 만하다.
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

    /// [2026-08-27 신설] 책을 선택했을 때(`focusedChapter == nil`) 이 화면
    /// 전체가 책 개요 에디터 하나만 보여준다. 예전엔 이 자리가 `List`의
    /// `Section` 하나였고, 그 아래 "장별 개요" 아코디언 섹션이 항상 같이
    /// 있었다 — 이제 아코디언 자체가 없어져 `List`를 쓸 이유도 없다.
    @ViewBuilder
    private var bookOutlineOnlyEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(book.nameKo) 책 개요")
                .font(.title3)
                .fontWeight(.semibold)
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
                    // [2026-08-27 되돌림] 2026-08-21에 "아이패드에서 macOS처럼
                    // 동일한 리치 에디터를 구현할 수 있는가?"라는 질문을 "macOS를
                    // iOS 커스텀 툴바 방식으로 바꿔달라"는 요청으로 잘못 해석해
                    // `showsToolbarOnMac: true`로 바꿨었다 — 사용자 확인: 그 질문은
                    // 기준(macOS)은 그대로 두고 iOS를 거기 맞출 수 있는지 물은
                    // 것이었지, macOS를 바꿔 달라는 요청이 아니었다. macOS 네이티브
                    // 서식 도구(`usesInspectorBar`/`usesFontPanel`/`usesRuler`)에는
                    // 이 커스텀 툴바에 없는 줄간격(문단 간격) 조절 등이 포함돼
                    // 있어, 그걸 끄면서 조용히 기능이 빠졌었다. 기본값 `false`로
                    // 되돌려 macOS는 다시 네이티브 방식을 쓴다.
                    showsToolbarOnMac: false
                )
                // [2026-08-27 신설] 사용자 요청 — "에디터 영역을 크게해서."
                // `MemoDetailView`가 같은 이유로 이미 쓰는 패턴 그대로 남은
                // 세로 공간을 전부 차지하게 한다.
                .frame(maxHeight: .infinity)
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
        }
        .padding()
    }

    // MARK: - 장 개요 전용 화면

    /// [2026-08-27 신설] 장을 선택했을 때(`focusedChapter`가 있음) 이 화면
    /// 전체가 그 장 하나의 개요 에디터만 보여준다 — 다른 장의 "접힌 행"조차
    /// 더 이상 그리지 않는다(위 파일 상단 주석 참고).
    @ViewBuilder
    private func chapterOnlyEditor(_ chapter: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(book.nameKo) \(chapter)장 개요")
                .font(.title3)
                .fontWeight(.semibold)
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
                    // [2026-08-27 되돌림] 위 `bookOutlineOnlyEditor`의
                    // `showsToolbarOnMac` 주석과 같은 이유로 장 개요 에디터도
                    // 함께 되돌린다 — macOS는 다시 네이티브 서식 도구를 쓴다.
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

    /// [2026-08-27 변경] 예전엔 책을 선택하든 장을 선택하든 항상 책 개요 +
    /// 그 책의 모든 장(시편은 150개) `ChapterSummary`를 한꺼번에
    /// find-or-create했다 — 화면이 그 전부를 아코디언으로 보여줬기 때문이다.
    /// 이제 화면이 "책 개요" 또는 "장 개요 하나"만 보여주므로, 실제로 화면에
    /// 필요한 객체 하나만 로드한다 — 예를 들어 시편 3장을 열 때 나머지 149개
    /// 장의 `ChapterSummary`를 미리 만들 이유가 없어졌다(예전엔 항상 책의
    /// 장 수만큼 반복 조회/생성했지만, 이제 O(1)).
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
