//
//  MemoDetailView.swift
//  JBCHBibleResearch
//
//  S2/S3 상세(편집/뷰) 화면. 메모 본문(순수 텍스트, 글자수 제한)·태그·폴더를 편집한다.
//
//  자동저장: 메모리상의 `memo.contentText`/`contentHtml`은 매 입력마다 즉시 갱신하고,
//  디스크/CloudKit 커밋(ModelContext.save())만 디바운스한다(MemoAutosaveController 참고).
//  CloudKit 동기화 트래픽을 줄이면서 메모리 값은 항상 최신으로 유지하기 위함이다.
//
//  `presentationContext`로 세 사용처를 한 타입으로 유지한다: `standalone`("내 메모" 탭,
//  성경 좌표를 직접 변경 가능), `contextual`(성경 조회 팝업, 좌표는 읽기전용 라벨),
//  `wordNoteList`(말씀노트 목록에서 연 전체 화면 분할 뷰).

import SwiftUI
import SwiftData
import BibleResearchModels

/// 메모 상세 화면이 열리는 맥락 — 성경 좌표 선택 UI 노출 여부가 달라진다.
enum MemoPresentationContext {
    /// "내 메모" 탭(MemoHomeView) — 성경 좌표 선택 UI를 그대로 유지한다.
    case standalone
    /// 성경 조회 사이드바(ChapterRelatedContentPanel)나 절 확대보기(VerseZoomView)에서
    /// 열린 메모 — 이미 절이 정해져 있어 좌표는 읽기전용 라벨로만 보여준다.
    case contextual
    /// 말씀노트 목록(WordNoteHomeView)에서 연 메모 — 이미 목록에 있는 특정 메모라 좌표는
    /// `.contextual`처럼 읽기전용 라벨로만 보여준다. 팝업이 아닌 전체 화면 분할 뷰라
    /// `.contextual`을 재사용하지 않고 별도 케이스로 둔다.
    case wordNoteList
}

struct MemoDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var memo: UserMemo
    var presentationContext: MemoPresentationContext = .standalone

    @State private var autosave: AutosaveController?
    @State private var isEditable = true
    @State private var hasLoadedMetadata = false
    @State private var memoTags: [Tag] = []
    @State private var tagInput: String = ""
    @State private var tagSuggestions: [Tag] = []

    @State private var allFolders: [MemoFolder] = []

    /// S10 드릴다운 시트(TagRelationsView와 공유하는 컴포넌트) — 태그 이름을
    /// 탭하면 채워진다.
    @State private var drilldownTag: Tag?

    // 폴더 선택은 헤더 아래 한 줄로 압축하고, 에디터가 남은 세로 공간을 모두 차지한다.
    // 태그 영역은 에디터 아래 고정 높이로 둔다.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            folderSection
                .padding(.horizontal)
                .padding(.vertical, 6)
            Divider()

            // 순수 `TextEditor` + 글자수 제한(`MemoTextLimit`) — `PhraseNoteEditorPopover`와 같은 패턴.
            // 전체 화면 분할 뷰라 `.frame(maxHeight: .infinity)`로 남은 공간을 채운다.
            VStack(alignment: .trailing, spacing: 4) {
                TextEditor(text: Binding(
                    get: { memo.contentText },
                    set: { newValue in
                        let limited = newValue.count > MemoTextLimit.maxCharacters
                            ? String(newValue.prefix(MemoTextLimit.maxCharacters))
                            : newValue
                        memo.contentText = limited
                        // `contentHtml`은 더 이상 RTF를 담지 않으므로 `contentText`와 항상 같은 값으로 맞춘다.
                        // (읽는 코드는 이 화면뿐이고 나머지는 `contentText`만 읽는다. 예전 RTF 메모도
                        // `RichTextCodec.decode`가 평문으로 폴백하므로 다시 열어도 안전하다.)
                        memo.contentHtml = limited
                        memo.updatedAt = .now
                        // 본문이 바뀌어 인덱스가 낡았다는 표시 — 화면을 벗어날 때 재인덱싱한다(`UserMemo.pendingIndexRefresh` 참고).
                        memo.pendingIndexRefresh = true
                        autosave?.scheduleSave()
                    }
                ))
                .font(.body)
                .disabled(!isEditable)

                Text("\(memo.contentText.count)/\(MemoTextLimit.maxCharacters)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
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
            // 표준 공유 시트(`ShareLink`, AirDrop 포함). 파일 인코딩/쓰기는 실제 공유 시점에만
            // 일어나도록 미뤄(`TransferableSharedMemo`의 `FileRepresentation` 클로저) 항상 최신 내용이 담긴다.
            // 받는 쪽은 미리보기로 확인 후 개인 묵상에 추가한다(`ImportedMemoPreviewSheet`).
            ToolbarItem(placement: .secondaryAction) {
                ShareLink(
                    item: TransferableSharedMemo(payload: sharePayload, displayName: shareDisplayName),
                    preview: SharePreview("\(shareDisplayName) 묵상")
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("이 묵상 공유하기(에어드롭 포함)")
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

        case .contextual, .wordNoteList:
            // 이미 절이 정해진 채로 열리므로 좌표 변경 UI 없이 읽기전용 텍스트로만 보여준다.
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

    /// 공유 파일 이름/미리보기용 좌표 라벨. `contextualCoordinateLabel`과 달리 책을 못 찾으면
    /// "성경"으로 폴백한다.
    private var shareDisplayName: String {
        let bookName = BooksProvider.shared.book(id: memo.bookId)?.nameKo ?? "성경"
        if let verse = memo.verse {
            return "\(bookName)\(memo.chapter)장\(verse)절"
        }
        return "\(bookName)\(memo.chapter)장"
    }

    /// 현재 `memo`/`memoTags`로 매번 새로 만드는 전송용 스냅샷. 값만 계산하고,
    /// 파일 인코딩/쓰기는 공유 시점에 한다.
    private var sharePayload: SharedMemoPayload {
        SharedMemoPayload(
            bookId: memo.bookId,
            chapter: memo.chapter,
            verse: memo.verse,
            rangeStart: memo.rangeStart,
            rangeEnd: memo.rangeEnd,
            annotationTranslationCode: memo.annotationTranslationCode,
            anchorText: memo.anchorText,
            contentText: memo.contentText,
            tagNames: memoTags.map(\.name),
            originalCreatedAt: memo.createdAt
        )
    }


    @ViewBuilder
    private var syncStatusLabel: some View {
        // 로컬 저장 상태의 근사치일 뿐 실제 CloudKit 업로드 완료 추적은 아니다(MemoAutosaveController 참고).
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
                        // 삭제 버튼과 탭 영역이 겹치지 않도록 이름 부분만 탭하면 드릴다운이 열린다.
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
                    .background(Color("AccentColor").opacity(0.15))
                    .clipShape(Capsule())
                }
            }

            if isEditable {
                HStack {
                    TextField("태그 입력 후 Enter", text: $tagInput)
                        .textFieldStyle(.roundedBorder)
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
        // 재인덱싱은 자동저장마다가 아니라 화면을 벗어날 때(`handleDisappear()`) 한다
        // (트레이드오프는 `WordSummaryEditorView.loadIfNeeded()` 주석 참고).
        autosave = AutosaveController(modelContext: modelContext)
        hasLoadedMetadata = true
    }

    private func handleDisappear() {
        autosave?.flush()
        let isEmpty = memo.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && memoTags.isEmpty
        // 아무것도 입력하지 않은 빈 메모 정리. 남아 있을 수 있는 VerseMention 인덱스도
        // 방어적으로 함께 지운다.
        autosave?.deleteIfEmpty(memo, isEmpty: isEmpty) { [modelContext] in
            BibleReferenceIndexingService.removeMentions(
                sourceType: .memo, sourceId: memo.id.uuidString, context: modelContext
            )
            // 빈 메모가 지워질 때 FTS 보조 인덱스 항목도 함께 지운다.
            UserContentSearchIndexLocation.delete(category: .memo, sourceId: memo.id.uuidString)
        }
        // 지워지지 않은 메모 중 본문이 실제로 바뀐 경우(`pendingIndexRefresh`)에만 재인덱싱한다.
        if !isEmpty && memo.pendingIndexRefresh {
            BibleReferenceIndexingService.reindexMemo(memo, context: modelContext)
            // FTS 보조 인덱스도 같은 신호(`pendingIndexRefresh`)로 변경분만 반영한다.
            UserContentSearchIndexLocation.upsert(
                category: .memo, sourceId: memo.id.uuidString, content: memo.contentText
            )
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
            // 빈도순(`memoTags?.count`) 정렬, 같으면 이름순. `.prefix(8)`은 `ArraySlice`를 돌려주므로
            // `Array(...)`로 감싸 `[Tag]`로 되돌린다.
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

// `FlowLayoutHStack`은 `Views/Memo/FlowLayoutHStack.swift`에 있다(`WordSummaryEditorView`와 공유).
