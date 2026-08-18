//
//  MemoDetailView.swift
//  JBCHBibleResearch
//
//  S2/S3 상세(편집/뷰) 화면. screens.md 3장(S2/S3), 12장(자동저장), 13장(새 메모
//  생성→입력→저장 전체 프로세스) 근거.
//
//  ⚠️ [구현 방식 차이] 12장/13.3은 "디바운스가 끝나는 시점에" content_html/
//  content_text를 재계산한다고 적었지만, 이 구현은 매 변경마다(키 입력마다)
//  메모리상의 `memo.contentHtml`/`contentText`를 즉시 재계산해 항상 최신 상태로
//  유지하고, **디스크/CloudKit에 실제로 커밋하는(ModelContext.save()) 시점만**
//  디바운스한다(MemoAutosaveController 참고). 목적(과도한 CloudKit 동기화 트래픽
//  방지)은 스펙과 동일하고, "메모리 값은 항상 최신"이라는 성질이 더 단순해 이렇게
//  구현했다.
//
//  [2026-08-09 변경] 리치 텍스트 에디터를 문단(블록) 배열 방식(`MemoRichTextDocument`)
//  에서 연속 텍스트 방식(`RichTextEditor.swift`)으로 교체하면서, 이 화면이 직접
//  들고 있던 `document`/`hasLoadedDocument` 중간 상태를 없앴다 — 이제
//  `memo.contentHtml`/`contentText`에 곧바로 바인딩한다(자세한 이유는
//  RichTextEditor.swift 상단 주석 참고).
//
//  [2026-08-09 추가] 사용자 요청 — "[성경 조회] 오른쪽 사이드바의 메모, 절
//  클릭후 확대보기에서의 메모"는 (1) 성경/장 선택·텍스트 검색·절이동 UI를
//  없애고, (2) 편집모드 기본 서식(Paperlogy 3 Light 14pt, 줄간격 1.5, 배경
//  흰색)과 조회모드 배경(시스템 배경색)을 다르게 쓴다. 이 화면은 "내 메모" 탭
//  (MemoHomeView, 메모의 성경 좌표를 직접 바꾸는 게 정상적인 흐름 —
//  MemoHomeView.swift 상단 주석 13~14행 참고)에서도 그대로 재사용되는 공용
//  타입이라, 위 변경을 무조건 적용하면 "내 메모"의 좌표 이동 기능이 없어져
//  버린다. `presentationContext`로 두 모드를 구분해, `standalone`(내 메모
//  탭 — 기존 그대로)과 `contextual`(성경 조회에서 열린 팝업 — 좌표는 이미
//  정해진 채로 열리므로 읽기전용 라벨만 보여주고, 서식도 다르게 지정) 둘 다
//  한 타입으로 유지한다. 호출부(BibleReadingView)만 `.contextual`을 넘긴다.
//

import SwiftUI
import SwiftData
import BibleResearchModels
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// 위 파일 상단 주석 참고.
enum MemoPresentationContext {
    /// "내 메모" 탭(MemoHomeView) — 성경 좌표 선택 UI를 그대로 유지하고,
    /// 리치 텍스트 에디터도 기존 기본 서식(시스템 폰트 15pt, 배경 투명)을 쓴다.
    case standalone
    /// 성경 조회 화면의 오른쪽 사이드바(ChapterRelatedContentPanel)나 절
    /// 확대보기(VerseZoomView)에서 열린 메모 — 이미 어느 절의 메모인지 정해진
    /// 채로 열리므로 좌표 선택 UI 대신 읽기전용 라벨만 보여주고, 리치 텍스트
    /// 에디터도 전용 서식(Paperlogy 3 Light 14pt/줄간격 1.5/편집 중 흰
    /// 배경/조회 중 시스템 배경)을 쓴다.
    case contextual
}

struct MemoDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var memo: UserMemo
    var presentationContext: MemoPresentationContext = .standalone

    @State private var autosave: AutosaveController?
    @State private var isEditable = true
    @State private var hasLoadedMetadata = false
    /// [2026-08-11 추가] 사용자 요청 — "확대보기/사이드바 메모 팝업: 맨 위 글꼴
    /// 스타일 라인과 그 밑 성경장절정보-동기화정보 라인의 순서를 바꿀 것".
    /// `.contextual`에서만 이 프록시로 `RichTextEditorToolbar`를 `header`보다
    /// 먼저(=더 위에) 그린다 — `RichTextEditor`에는 `externalProxy`로 같은
    /// 인스턴스를 넘겨 내부 툴바는 끄고 이 프록시가 실제 텍스트뷰를 제어하게
    /// 한다(RichTextEditor.swift `showsToolbar`/`externalProxy` 상단 주석 참고).
    /// `.standalone`(내 메모 탭)은 기존 그대로(헤더가 먼저, 툴바는 에디터
    /// 안쪽에) 두므로 이 프록시를 쓰지 않는다.
    @State private var contextualToolbarProxy = RichTextEditingProxy()

    @State private var memoTags: [Tag] = []
    @State private var tagInput: String = ""
    @State private var tagSuggestions: [Tag] = []

    @State private var allFolders: [MemoFolder] = []

    /// S10 드릴다운 시트(TagRelationsView와 공유하는 컴포넌트) — 태그 이름을
    /// 탭하면 채워진다.
    @State private var drilldownTag: Tag?

    // [2026-08-09 변경] 사용자 요청 — "폴더 선택하는 영역은 한줄정도로 짧게,
    // 나머지는 모두 에디터 영역." 전체를 `ScrollView`로 감싸고 에디터에
    // 고정 최소 높이만 주던 이전 구조는, 태그/폴더가 길어지지 않는 한 에디터가
    // 딱 그 최소 높이(220pt)만큼만 차지하고 나머지 화면은 그냥 비어 있었다.
    // `ScrollView`를 걷어내고 폴더 선택 줄을 헤더 바로 아래 한 줄로 압축한 뒤,
    // 에디터에 `.frame(maxHeight: .infinity)`를 줘서 남은 세로 공간을 전부
    // 차지하게 했다 — `RichTextEditor`는 내부적으로 이미 자체 스크롤
    // (`NSScrollView`/`UITextView`)을 갖고 있어 내용이 길어져도 문제없다.
    // 태그 영역은 스크롤 없이 에디터 아래 고정 높이로 남긴다 — 대부분의 메모는
    // 태그가 몇 개 안 되므로 실제로 문제가 되는 경우는 드물다고 판단했다.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // [2026-08-11 추가] 사용자 요청 — "맨 위 글꼴 스타일 라인과 그 밑
            // 성경장절정보-동기화정보 라인의 순서를 바꿀 것". `.contextual`에서만
            // 이 툴바를 `header`보다 먼저 그린다 — macOS는 이 커스텀 툴바 자체가
            // 없어(텍스트 선택 시 뜨는 네이티브 서식 팝업을 쓴다, RichTextEditor.swift
            // 상단 주석 참고) 이 순서 변경이 실제로 보이는 건 iOS/iPadOS뿐이다.
            #if os(iOS)
            if presentationContext == .contextual && isEditable {
                RichTextEditorToolbar(proxy: contextualToolbarProxy)
                Divider()
            }
            #endif

            header
            Divider()

            folderSection
                .padding(.horizontal)
                .padding(.vertical, 6)
            Divider()

            RichTextEditor(
                rtfText: Binding(
                    get: { memo.contentHtml },
                    set: { newValue in
                        memo.contentHtml = newValue
                        memo.updatedAt = .now
                        // [2026-08-12 추가] 사용자 논의 — "화면을 벗어났을 때
                        // 트리거를 실행" 방식으로 바꾸면서 생긴 표시 —
                        // `WordSummaryEditorView`와 완전히 같은 이유
                        // (`UserMemo.pendingIndexRefresh` 상단 주석 참고).
                        memo.pendingIndexRefresh = true
                        autosave?.scheduleSave()
                    }
                ),
                plainText: Binding(
                    get: { memo.contentText },
                    set: { memo.contentText = $0 }
                ),
                isEditable: isEditable,
                typingFont: EditorDefaultStyle.typingFont,
                defaultTextColor: EditorDefaultStyle.textColor,
                lineHeightMultiple: EditorDefaultStyle.lineHeightMultiple,
                // [2026-08-14 변경] 사용자 요청 — "모든 에디터 창 기본 설정"(공통) +
                // "글을 클릭했을 때 에디터 배경은... 모드를 바꿨을 때 배경색과
                // 동일하게 맞출 것." 조회/편집 두 배경을 서로 다른 값으로 뒀던
                // 것이 바로 그 불일치의 원인이었다 — 이제 두 값을 완전히 같게
                // 고정해(`EditorDefaultStyle.backgroundColor`) 모드를 전환해도,
                // 처음 열었을 때와 전환한 뒤가 항상 같은 배경으로 보인다.
                editingBackgroundColor: EditorDefaultStyle.backgroundColor,
                readOnlyBackgroundColor: EditorDefaultStyle.backgroundColor,
                // [2026-08-11 추가] `.contextual`은 위에서 `RichTextEditorToolbar`를
                // 직접 그리므로 이 컴포넌트 내부 툴바는 끄고, 같은 프록시를
                // 공유해 그 외부 툴바가 이 텍스트뷰를 제어하게 한다.
                showsToolbar: presentationContext != .contextual,
                externalProxy: presentationContext == .contextual ? contextualToolbarProxy : nil
            )
            .padding()
            .frame(maxHeight: .infinity)

            Divider().padding(.horizontal)

            tagSection
                .padding()
        }
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
        .onAppear(perform: loadIfNeeded)
        .onDisappear(perform: handleDisappear)
        .sheet(item: $drilldownTag) { tag in
            TagDrilldownView(tag: tag)
        }
    }

    // MARK: - 상단 성경 좌표 + 동기화 상태

    @ViewBuilder
    private var header: some View {
        switch presentationContext {
        case .standalone:
            HStack {
                BookChapterPicker(
                    books: BooksProvider.shared.books,
                    selectedBook: BooksProvider.shared.book(id: memo.bookId)
                        ?? Book(bookId: 1, testament: .old, orderIndex: 1, nameKo: "창세기", nameOriginal: "Genesis", abbreviation: ["창"], chapterCount: 50),
                    selectedChapter: memo.chapter
                ) { book, chapter in
                    memo.bookId = book.bookId
                    memo.chapter = chapter
                    autosave?.saveImmediately()
                }
                .disabled(!isEditable)

                Stepper(value: Binding(
                    get: { memo.verse ?? 0 },
                    set: { newValue in
                        memo.verse = newValue == 0 ? nil : newValue
                        autosave?.saveImmediately()
                    }
                ), in: 0...176) {
                    // [2026-08-11 수정] 사용자 요청 — "[절] 영역 폰트는 시스템 기본
                    // 폰트에 일반 크기로." 기존 `.caption`은 이미 시스템 폰트였지만
                    // 크기가 작았다(작은 캡션 크기) — `.body`(일반 본문 크기)로
                    // 키웠다. CrossReferenceTargetPicker.swift의 같은 종류 "N절"
                    // Stepper 라벨과 동일하게 맞춘다.
                    Text(memo.verse.map { "\($0)절" } ?? "절 없음")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .disabled(!isEditable)
                .fixedSize()

                Spacer()

                syncStatusLabel
            }
            .padding()

        case .contextual:
            // [2026-08-09 추가] 사용자 요청 — "성경 및 장 선택, 텍스트로 성경검색,
            // 절이동 기능 제거". 이 메모는 이미 어느 절 것인지 정해진 채로 열리므로
            // (성경 조회 사이드바/확대보기에서 선택한 절), 좌표를 바꿀 수 있게
            // 하는 것 자체가 의미가 없다 — 대신 지금 좌표를 읽기전용 텍스트로만
            // 보여준다.
            HStack {
                Text(contextualCoordinateLabel)
                    .font(.callout.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                syncStatusLabel
            }
            .padding()
        }
    }

    private var contextualCoordinateLabel: String {
        let bookName = BooksProvider.shared.book(id: memo.bookId)?.nameKo ?? ""
        if let verse = memo.verse {
            return "\(bookName) \(memo.chapter)장 \(verse)절"
        }
        return "\(bookName) \(memo.chapter)장"
    }

    // [2026-08-14 삭제] `contextualTypingFont`(`.contextual`에서만 Paperlogy-3
    // Light 14pt를 쓰던 프로퍼티) — 이제 `.standalone`/`.contextual` 구분 없이
    // 모든 에디터가 `EditorDefaultStyle.typingFont`를 공유하므로 더 이상 필요
    // 없다(위 `RichTextEditor(...)` 호출부 참고).

    @ViewBuilder
    private var syncStatusLabel: some View {
        // 12장 "저장 상태 표시(선택)" — 로컬 저장 상태의 근사치일 뿐 실제 CloudKit
        // 업로드 완료 추적은 아니다(MemoAutosaveController.swift 상단 주석 참고).
        switch autosave?.status {
        case .saved, .none:
            Label("동기화됨", systemImage: "checkmark.icloud")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .pending:
            Label("대기 중", systemImage: "icloud")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .saving:
            Label("동기화 중", systemImage: "arrow.triangle.2.circlepath.icloud")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 태그

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("태그").font(.caption).foregroundStyle(.secondary)

            FlowLayoutHStack {
                ForEach(memoTags) { tag in
                    HStack(spacing: 4) {
                        // screens.md S10 — "메모·문서의 태그 클릭 → 관계 보기 버튼".
                        // 삭제 버튼과 탭 영역이 겹치지 않도록 이름 부분만 탭하면
                        // 드릴다운이 열린다.
                        Text(tag.name)
                            .onTapGesture { drilldownTag = tag }
                        if isEditable {
                            Button {
                                removeTag(tag)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
                }
            }

            if isEditable {
                HStack {
                    TextField("태그 입력 후 Enter", text: $tagInput)
                        .textFieldStyle(.roundedBorder)
                        // [2026-08-09 추가] 사용자 요청 — "태그 추가 입력 란: 글꼴
                        // 시스템 기본글꼴, 크기는 보통크기". 이 화면 전체에 별도
                        // 폰트 환경값을 지정해 두지 않아 원래도 시스템 기본
                        // 글꼴이었지만, 요청대로 명시적으로 고정한다(추후 이
                        // 화면에 다른 기본 폰트가 생기더라도 이 입력란만은 항상
                        // 시스템 기본을 쓰도록).
                        .font(.body)
                        .onSubmit { commitTagInput() }
                        .onChange(of: tagInput) { _, newValue in
                            updateTagSuggestions(for: newValue)
                        }
                    if !tagSuggestions.isEmpty {
                        Menu {
                            ForEach(tagSuggestions) { suggestion in
                                Button(suggestion.name) { addTag(suggestion) }
                            }
                        } label: {
                            Image(systemName: "chevron.down.circle")
                        }
                    }
                }
                .frame(maxWidth: 280)
            }
        }
    }

    // MARK: - 폴더

    private var folderSection: some View {
        HStack {
            Text("폴더").font(.caption).foregroundStyle(.secondary)
            Menu {
                Button("미분류") { setFolder(nil) }
                if !allFolders.isEmpty {
                    Divider()
                    ForEach(allFolders) { folder in
                        Button(folder.name) { setFolder(folder) }
                    }
                }
            } label: {
                Text(memo.folder?.name ?? "미분류")
            }
            .disabled(!isEditable)
        }
    }

    // MARK: - 로드/저장

    private func loadIfNeeded() {
        guard !hasLoadedMetadata else { return }
        memoTags = (memo.memoTags ?? []).compactMap(\.tag).filter { !$0.isMerged }
        do {
            allFolders = try modelContext.fetch(FetchDescriptor<MemoFolder>(sortBy: [SortDescriptor(\.name)]))
        } catch {
            print("[MemoDetailView] 폴더 목록 로드 실패: \(error)")
        }
        // [2026-08-11 신설, 2026-08-12 2차 수정] 사용자 요청 — "메모를 등록/수정할
        // 때마다 관련 성경구절 인덱스 재계산." → 사용자 논의 — "말씀 요약 화면을
        // 벗어났을 때 트리거를 실행 할 수 있는가?" 원래는 여기서 `didSave`
        // 클로저로 매 자동저장(디바운스)마다 재인덱싱했다 — 화면을 벗어날 때
        // (`handleDisappear()`)로 옮겼다(`WordSummaryEditorView.loadIfNeeded()`
        // 상단 주석에 트레이드오프까지 정리해 둠 — 개인 묵상도 같은 논리로
        // 통일했다: `.contextual`은 시트가 화면을 덮어 편집 중 "관련 내용" 패널을
        // 볼 수 없고, `.standalone`도 목록 화면이 뒤에 가려져 체감 차이가 없다).
        autosave = AutosaveController(modelContext: modelContext)
        hasLoadedMetadata = true
    }

    private func handleDisappear() {
        autosave?.flush()
        let isEmpty = memo.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && memoTags.isEmpty
        // 13.4 — "+ 새 메모"만 누르고 아무것도 하지 않은 빈 메모 정리.
        // [2026-08-11 추가] 빈 메모라 실제로 지워질 때도, 혹시 남아 있을 수 있는
        // 그 메모의 VerseMention 인덱스를 함께 정리한다(보통은 비어 있어 애초에
        // 인덱스도 없었겠지만, 방어적으로 항상 호출).
        autosave?.deleteIfEmpty(memo, isEmpty: isEmpty) { [modelContext] in
            BibleReferenceIndexingService.removeMentions(
                sourceType: .memo, sourceId: memo.id.uuidString, context: modelContext
            )
        }
        // [2026-08-12 추가] 사용자 논의 — "화면을 닫으면 인덱스를 생성." 지워지지
        // 않은 메모만, 그리고 지난 저장 이후로 본문이 실제로 바뀌어 인덱스가
        // 낡았을 때만(`pendingIndexRefresh`) 재인덱싱한다 — 열어만 보고 닫으면
        // 불필요한 재계산을 하지 않는다.
        if !isEmpty && memo.pendingIndexRefresh {
            BibleReferenceIndexingService.reindexMemo(memo, context: modelContext)
            memo.pendingIndexRefresh = false
            try? modelContext.save()
        }
    }

    // MARK: - 태그 조작 (13.3 — 이산적 액션, 디바운스 없이 즉시 저장)

    private func updateTagSuggestions(for input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else {
            tagSuggestions = []
            return
        }
        do {
            let all = try modelContext.fetch(FetchDescriptor<Tag>(
                predicate: #Predicate<Tag> { $0.mergedIntoId == nil }
            ))
            // [2026-08-07 수정, 원본 문서 재대조로 발견한 누락] screens.md S2/S3절
            // "기존 태그 자동완성 추천(**빈도순**)" — 지금까지 이름 알파벳순으로만
            // 정렬돼 있었다. `memoTags?.count`(이 태그가 몇 개의 메모에 붙어 있는지)를
            // 빈도로 쓰고, 빈도가 같으면 이름순으로 안정적인 2차 정렬을 한다.
            // [수정] `.sorted { ... }`는 배열(`[Tag]`)을 돌려주지만, 그 뒤에 붙인
            // `.prefix(8)`은 배열이 아니라 `ArraySlice<Tag>`를 돌려준다 —
            // `tagSuggestions`의 선언 타입이 `[Tag]`라 그대로 대입하면 타입이
            // 안 맞는다. `Array(...)`로 한 번 더 감싸 다시 배열로 되돌린다.
            tagSuggestions = Array(
                all
                    .filter { $0.normalizedForm.contains(trimmed) }
                    .filter { candidate in !memoTags.contains { $0.id == candidate.id } }
                    .sorted {
                        let lhsCount = $0.memoTags?.count ?? 0
                        let rhsCount = $1.memoTags?.count ?? 0
                        if lhsCount != rhsCount { return lhsCount > rhsCount }
                        return $0.name < $1.name
                    }
                    .prefix(8)
            )
        } catch {
            tagSuggestions = []
        }
    }

    private func commitTagInput() {
        let trimmed = tagInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            let tag = try TagDeduplication.findOrCreateTag(named: trimmed, context: modelContext)
            addTag(tag)
        } catch {
            print("[MemoDetailView] 태그 생성 실패: \(error)")
        }
        tagInput = ""
        tagSuggestions = []
    }

    private func addTag(_ tag: Tag) {
        guard !memoTags.contains(where: { $0.id == tag.id }) else { return }
        let join = MemoTag(memo: memo, tag: tag)
        modelContext.insert(join)
        memoTags.append(tag)
        tagInput = ""
        tagSuggestions = []
        autosave?.saveImmediately()
    }

    private func removeTag(_ tag: Tag) {
        if let join = (memo.memoTags ?? []).first(where: { $0.tag?.id == tag.id }) {
            modelContext.delete(join)
        }
        memoTags.removeAll { $0.id == tag.id }
        autosave?.saveImmediately()
    }

    private func setFolder(_ folder: MemoFolder?) {
        memo.folder = folder
        autosave?.saveImmediately()
    }
}

// `FlowLayoutHStack`은 `Views/Memo/FlowLayoutHStack.swift`로 옮겼다(2026-08-14 —
// `WordSummaryEditorView`도 태그 UI를 갖게 되면서 두 화면이 공유해야 했다).
