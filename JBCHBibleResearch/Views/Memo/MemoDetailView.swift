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
#if os(iOS)
import UIKit
#endif

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

/// 말씀 노트 상세(개인 묵상·말씀 요약) 공용 구절 줄 — 책 아이콘 + "창세기 2장 1절" + [성경에서 보기 ›].
/// 버튼은 앱 공용 크로스탭 이동(`AppNavigationRequest` + `BibleVerseNavigationRequest`)으로 성경 조회의 그 절로 보낸다
/// (`PersonDetailView.handleBibleReferenceLink`와 같은 방식). 절이 없으면 1절로 보낸다(`BibleVerseNavigationTarget.verse`가 Int).
/// 새 파일을 만들지 않고 이 파일에 둔다(새 파일이 Xcode 대상에 잡히지 않아 빌드가 깨진 전례, `SidebarNavigationView.swift` 하단 주석 참고).
struct WordNoteVerseBar: View {
    let label: String
    let bookId: Int
    let chapter: Int
    let verse: Int?

    private var settings: UserSettingsStore { .shared }
    private var gold: Color { JBCHCategoryPalette.gold }

    private var buttonTitle: String {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone ? "성경 보기" : "성경에서 보기"
        #else
        "성경에서 보기"
        #endif
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "book")
                .font(.body.weight(.semibold))
                .foregroundStyle(gold)
                .frame(width: 34, height: 34)
                .background(gold.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(label)
                .font(.custom(SpecialPurposeFonts.titleSerif, size: 16, relativeTo: .headline))
                .fontWeight(.semibold)
                .foregroundStyle(settings.bibleTextColor ?? .primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button {
                AppNavigationRequest.shared.request(.bibleReading)
                BibleVerseNavigationRequest.shared.request(bookId: bookId, chapter: chapter, verse: verse ?? 1)
            } label: {
                HStack(spacing: 4) {
                    Text(buttonTitle)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold))
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(gold)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .overlay(Capsule().stroke(gold, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("이 구절을 성경 조회에서 열기")
            .accessibilityLabel("\(label) 성경에서 보기")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill((settings.bibleTextColor ?? Color.primary).opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke((settings.bibleTextColor ?? Color.primary).opacity(0.15), lineWidth: 1)
        )
    }
}

struct MemoDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.self) private var environment
    @Bindable var memo: UserMemo
    var presentationContext: MemoPresentationContext = .standalone

    /// 말씀 노트 목록에서 연 화면(`.wordNoteList`)인지 — 조회/편집 모드·구절 줄·테마 배경이 이 경우에만 달라진다.
    private var isWordNote: Bool { presentationContext == .wordNoteList }
    private var settings: UserSettingsStore { .shared }

    @State private var autosave: AutosaveController?
    /// 말씀 노트 목록에서 연 기존 묵상은 조회 모드로 시작하고(2026-10-03), 새로 만든 빈 묵상만 바로 편집 모드로 연다.
    /// 다른 맥락(`.standalone`/`.contextual`)은 기존처럼 편집으로 시작한다. `init`에서 정한다.
    @State private var isEditable: Bool
    @State private var hasLoadedMetadata = false
    @State private var memoTags: [Tag] = []
    @State private var tagInput: String = ""
    @State private var tagSuggestions: [Tag] = []

    @State private var allFolders: [MemoFolder] = []

    /// S10 드릴다운 시트(TagRelationsView와 공유하는 컴포넌트) — 태그 이름을
    /// 탭하면 채워진다.
    @State private var drilldownTag: Tag?

    init(memo: UserMemo, presentationContext: MemoPresentationContext = .standalone) {
        self._memo = Bindable(memo)
        self.presentationContext = presentationContext
        self._isEditable = State(initialValue: presentationContext != .wordNoteList || memo.contentText.isEmpty)
    }

    // 폴더 선택은 헤더 아래 한 줄로 압축하고, 에디터가 남은 세로 공간을 모두 차지한다.
    // 태그 영역은 에디터 아래 고정 높이로 둔다.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            // 말씀 노트: 폴더는 아래 태그 영역 위로 옮긴다(개인 묵상 화면 목업, 2026-10-03).
            if !isWordNote {
                folderSection
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                Divider()
            }

            // 순수 `TextEditor` + 글자수 제한(`MemoTextLimit`) — `PhraseNoteEditorPopover`와 같은 패턴.
            // 전체 화면 분할 뷰라 `.frame(maxHeight: .infinity)`로 남은 공간을 채운다.
            VStack(alignment: .trailing, spacing: 4) {
                if isWordNote && !isEditable {
                    // 말씀 노트 조회 모드: 비활성 `TextEditor`는 글자가 흐려지므로 읽기 전용 `Text`로 그린다(선택·복사 가능).
                    ScrollView {
                        Text(memo.contentText)
                            .font(.system(size: 17))
                            .lineSpacing(5)
                            .foregroundStyle(settings.bibleTextColor ?? Color.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                } else {
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
                // 말씀 노트 조회 모드는 읽기 좋게 17pt + 줄 간격, 편집 모드는 종이색 카드 + 금박 테두리(목업). 다른 맥락은 그대로.
                .font(isWordNote && !isEditable ? .system(size: 17) : .body)
                .lineSpacing(isWordNote && !isEditable ? 5 : 0)
                .scrollContentBackground(isWordNote ? .hidden : .automatic)
                .padding(isWordNote ? 10 : 0)
                .background(editorSurface)
                .disabled(!isEditable)
                }

                // 조회 모드(말씀 노트)에서는 글자 수를 숨긴다.
                if !(isWordNote && !isEditable) {
                    Text("\(memo.contentText.count)/\(MemoTextLimit.maxCharacters)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxHeight: .infinity)

            Divider().padding(.horizontal)

            tagSection
                .padding()
        }
        // 말씀 노트 화면만 테마 배경을 칠한다(`WordSummaryEditorView`와 같은 처리). 다른 맥락은 기존 그대로(투명).
        .background(isWordNote ? (settings.bibleBackgroundColor ?? Color.clear) : Color.clear)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    // 말씀 노트에서 "완료"를 누르면 디바운스 중인 저장을 바로 끝낸다.
                    if isWordNote && isEditable { autosave?.saveImmediately() }
                    isEditable.toggle()
                } label: {
                    if isWordNote {
                        Text(isEditable ? "완료" : "편집").fontWeight(.semibold)
                    } else {
                        Image(systemName: isEditable ? "eye" : "pencil")
                    }
                }
                .help(isEditable ? (isWordNote ? "편집 끝내고 조회로" : "읽기 전용으로 보기") : "편집하기")
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

        case .wordNoteList:
            wordNoteHeader

        case .contextual:
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

    /// 말씀 노트 헤더 — 종류 배지·날짜·동기화 상태, 구절 줄(+성경에서 보기), 조회 모드에서는 저장된 구절 본문 인용.
    private var wordNoteHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                let badgeColor = WordNoteCategory.personalMemo.spineColor(onDark: isDarkSurface)
                Text(WordNoteCategory.personalMemo.rawValue)
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(badgeColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(badgeColor)
                Text(isEditable ? "편집 중 · 자동 저장" : "\(WordNoteItem.memo(memo).dateLabel ?? "") 수정")
                    .font(.caption)
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.65) ?? Color.secondary)
                Spacer()
                syncStatusLabel
            }
            WordNoteVerseBar(label: contextualCoordinateLabel, bookId: memo.bookId, chapter: memo.chapter, verse: memo.verse)
            if !isEditable, let anchor = memo.anchorText, !anchor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // 묵상을 쓸 때 저장해 둔 구절 본문(번역본은 `annotationTranslationCode`).
                HStack(alignment: .top, spacing: 12) {
                    Rectangle().fill(JBCHCategoryPalette.gold).frame(width: 3)
                    Text(anchor)
                        .font(.custom(SpecialPurposeFonts.titleSerif, size: 15, relativeTo: .body))
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.7) ?? Color.secondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    /// 어두운 테마 배경이면 종류 배지 색을 밝은 변형으로 바꾼다(`WordNoteRowView.isDarkSurface`와 같은 공식).
    private var isDarkSurface: Bool {
        guard let background = settings.bibleBackgroundColor else { return false }
        let resolved = background.resolve(in: environment)
        return 0.2126 * Double(resolved.red) + 0.7152 * Double(resolved.green) + 0.0722 * Double(resolved.blue) < 0.5
    }

    /// 말씀 노트 편집기 바탕 — 편집 중이면 종이색 카드 + 금박 테두리, 조회 중이면 없음. 다른 맥락은 항상 없음.
    @ViewBuilder
    private var editorSurface: some View {
        if isWordNote && isEditable {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill((settings.bibleTextColor ?? Color.primary).opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(JBCHCategoryPalette.gold, lineWidth: 1.5)
                )
        } else {
            Color.clear
        }
    }

    /// 말씀 노트 조회 모드의 폴더 표시(칩). 편집 모드는 기존 `folderSection`(메뉴)을 쓴다.
    @ViewBuilder
    private var wordNoteFolderRow: some View {
        if isEditable {
            folderSection
        } else {
            HStack(spacing: 8) {
                Text("폴더").font(.caption).foregroundStyle(.secondary)
                Label(memo.folder?.name ?? "미분류", systemImage: "folder")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(JBCHCategoryPalette.wood.opacity(0.10), in: Capsule())
            }
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
            Label("기기에 저장됨", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .pending:
            Label("저장 대기 중", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .saving:
            Label("저장 중", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 태그

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isWordNote {
                wordNoteFolderRow
            }
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
