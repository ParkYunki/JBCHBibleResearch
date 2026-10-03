//
//  WordSummaryEditorView.swift
//  JBCHBibleResearch
//
//  `VerseSummary` 하나를 여는 리치 텍스트 에디터. `MemoDetailView`(개인 묵상)와 거의 같은 구조
//  (자동저장 컨트롤러, 성경 좌표 헤더, 표시 방식별 헤더, 태그)이다.
//  `.contextual`로 열릴 때는 `BibleReadingView`가 날짜/구절 문구를 채운 새 `VerseSummary`를 넘기며, 이 화면은 그대로 편집기에 띄운다.
//  빈 레코드 자동 정리는 본문이 진짜로 비었을 때만 한다. 열릴 때 스냅샷과 비교하는 방식은 뷰가 다시 만들어지면
//  사용자가 쓴 내용이 스냅샷으로 재캡처되어 지워질 수 있어 쓰지 않는다. 문구만 남은 레코드는 목록에서 직접 삭제한다.
//

import SwiftUI
import SwiftData
import BibleResearchModels
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum WordSummaryPresentationContext {
    /// "말씀 요약" 사이드바 탭(WordSummaryHomeView) — 성경 좌표를 직접 바꿀 수
    /// 있는 헤더를 쓴다.
    case standalone
    /// 성경 조회 화면의 [말씀 요약] 버튼으로 연 패널 — 이미 어느 절의 요약인지
    /// 정해진 채로 열리므로 읽기전용 좌표 라벨만 보여준다.
    case contextual
    /// 말씀노트 통합 목록에서 연 요약. `.standalone` 헤더는 아이폰 폭에서 가로로 잘리므로
    /// `.contextual`과 같은 읽기전용 좌표 라벨 헤더를 쓴다.
    case wordNoteList
}

struct WordSummaryEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.self) private var environment
    /// 화면 배경/보조 텍스트 색(테마)에 쓴다. `RichTextEditor` 자체 배경/글자색(`EditorDefaultStyle`)에는 쓰지 않는다.
    private var settings: UserSettingsStore { .shared }
    @Bindable var summary: VerseSummary
    var presentationContext: WordSummaryPresentationContext = .standalone
    /// 성경 조회 화면 하단의 [말씀 복사] 버튼이 이 안의 텍스트뷰에 접근하기 위한 프록시(`RichTextEditor.externalProxy`와 같은 원칙).
    /// 호출부가 만들어 넘기며, nil이면 내부에서 만든 프록시를 쓴다.
    var externalProxy: RichTextEditingProxy? = nil
    /// 닫기 동작. `.contextual`을 여는 `.inspector`는 아이폰(compact width)에서 시트로 전체 화면을 덮어 바깥 툴바의 닫기 버튼이 가려지므로
    /// 호출부(`BibleReadingView`)가 넘긴다. `NavigationLink` 푸시 호출부는 기본 뒤로가기가 있어 nil.
    var onRequestClose: (() -> Void)? = nil

    @State private var autosave: AutosaveController?
    /// 말씀 노트 목록에서 연 기존 요약(`.wordNoteList`)은 조회 모드로 시작하고(2026-10-03), 새로 만든 빈 요약만 바로 편집 모드로 연다.
    /// 다른 맥락은 기존처럼 편집으로 시작한다. `init`에서 정한다.
    @State private var isEditable: Bool
    @State private var hasLoadedMetadata = false

    /// 태그 상태(`MemoDetailView`와 동일). `SummaryTag`(이 화면 전용 조인)로 연결한다.
    @State private var summaryTags: [Tag] = []
    @State private var tagInput: String = ""
    @State private var tagSuggestions: [Tag] = []
    @State private var drilldownTag: Tag?

    init(
        summary: VerseSummary,
        presentationContext: WordSummaryPresentationContext = .standalone,
        externalProxy: RichTextEditingProxy? = nil,
        onRequestClose: (() -> Void)? = nil
    ) {
        self._summary = Bindable(summary)
        self.presentationContext = presentationContext
        self.externalProxy = externalProxy
        self.onRequestClose = onRequestClose
        self._isEditable = State(initialValue: presentationContext != .wordNoteList || summary.contentText.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            RichTextEditor(
                rtfText: Binding(
                    get: { summary.contentHtml },
                    set: { newValue in
                        summary.contentHtml = newValue
                        summary.updatedAt = .now
                        // 저장(디바운스)에 실려 나가는 표시. 정상 종료(`handleDisappear`) 전에 강제 종료되면 이 `true`만 남아
                        // 목록 화면이 "인덱스 갱신 필요" 배지를 보여준다.
                        summary.pendingIndexRefresh = true
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
                // 조회/편집 배경을 같은 값으로 고정해 모드 전환 시 배경이 바뀌어 보이지 않게 한다(`MemoDetailView`와 동일).
                editingBackgroundColor: EditorDefaultStyle.backgroundColor,
                readOnlyBackgroundColor: EditorDefaultStyle.backgroundColor,
                // macOS 에디터는 항상 네이티브 서식 툴바를 유지한다(`OutlineBookBulkEditView`와 동일).
                // 좁은 인스펙터에서 서식 팝업 위치가 어긋날 수 있는 것은 알려진 한계.
                showsToolbarOnMac: false,
                externalProxy: externalProxy
            )
            .padding()
            .frame(maxHeight: .infinity)

            Divider().padding(.horizontal)

            tagSection
                .padding()
        }
        // 화면 배경만 테마를 따르고 `RichTextEditor` 자체 배경은 그대로 둔다.
        .background(settings.bibleBackgroundColor ?? Color.clear)
        .sheet(item: $drilldownTag) { tag in
            TagDrilldownView(tag: tag)
        }
        .toolbar {
            // 읽기전용 토글은 새 항목을 바로 편집하는 `.contextual`에서는 의미가 적어 뺀다.
            if presentationContext == .standalone || presentationContext == .wordNoteList {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        // 말씀 노트에서 "완료"를 누르면 디바운스 중인 저장을 바로 끝낸다.
                        if presentationContext == .wordNoteList && isEditable { autosave?.saveImmediately() }
                        isEditable.toggle()
                    } label: {
                        if presentationContext == .wordNoteList {
                            Text(isEditable ? "완료" : "편집").fontWeight(.semibold)
                        } else {
                            Image(systemName: isEditable ? "eye" : "pencil")
                        }
                    }
                    .help(isEditable ? "읽기 전용으로 보기" : "편집하기")
                }
            }
            // 닫기 버튼은 여기 `ToolbarItem`이 아니라 `header`에 둔다: 아이폰에서 `.inspector`가 시트로 열리면
            // 이 뷰에 `NavigationStack`이 없어 툴바 버튼이 보이지 않는다.
        }
        .onAppear(perform: loadIfNeeded)
        .onDisappear(perform: handleDisappear)
    }

    // MARK: - 상단 성경 좌표 + 동기화 상태

    @ViewBuilder
    private var header: some View {
        switch presentationContext {
        case .standalone:
            HStack {
                BookChapterPicker(
                    books: BooksProvider.shared.books,
                    selectedBook: BooksProvider.shared.book(id: summary.bookId)
                        ?? Book(bookId: 1, testament: .old, orderIndex: 1, nameKo: "창세기", nameOriginal: "Genesis", abbreviation: ["창"], chapterCount: 50),
                    selectedChapter: summary.chapter
                ) { book, chapter in
                    summary.bookId = book.bookId
                    summary.chapter = chapter
                    autosave?.saveImmediately()
                }
                .disabled(!isEditable)

                Stepper(value: Binding(
                    get: { summary.verse ?? 0 },
                    set: { newValue in
                        summary.verse = newValue == 0 ? nil : newValue
                        autosave?.saveImmediately()
                    }
                ), in: 0...176) {
                    Text(summary.verse.map { "\($0)절" } ?? "절 없음")
                        .font(.body)
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
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
            // 읽기전용 좌표 표시.
            HStack {
                Text(contextualCoordinateLabel)
                    .font(.callout.bold())
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                Spacer()
                syncStatusLabel
                // 아이폰 전용 닫기 버튼. `.inspector`가 시트로 열리면 바깥 툴바 버튼이 가려지므로 `header` 안에 그린다.
                // 아이패드/맥은 바깥 "관련 콘텐츠" 툴바 버튼이 이미 닫기 역할을 한다.
                #if os(iOS)
                if let onRequestClose, UIDevice.current.userInterfaceIdiom == .phone {
                    Button {
                        onRequestClose()
                    } label: {
                        // 눈에 띄도록 큰 아이콘 + 빨강.
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 8)
                }
                #endif
            }
            .padding()
        }
    }

    /// 말씀 노트 헤더 — 종류 배지·날짜·동기화 상태 + 구절 줄(성경에서 보기). 개인 묵상 헤더(`MemoDetailView.wordNoteHeader`)와 같은 모양.
    private var wordNoteHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                let badgeColor = WordNoteCategory.verseSummary.spineColor(onDark: isDarkSurface)
                Text(WordNoteCategory.verseSummary.rawValue)
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(badgeColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(badgeColor)
                Text(isEditable ? "편집 중 · 자동 저장" : (WordNoteItem.summary(summary).dateLabel ?? ""))
                    .font(.caption)
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.65) ?? Color.secondary)
                Spacer()
                syncStatusLabel
            }
            WordNoteVerseBar(label: contextualCoordinateLabel, bookId: summary.bookId, chapter: summary.chapter, verse: summary.verse)
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

    private var contextualCoordinateLabel: String {
        let bookName = BooksProvider.shared.book(id: summary.bookId)?.nameKo ?? ""
        if let verse = summary.verse {
            return "\(bookName) \(summary.chapter)장 \(verse)절"
        }
        return "\(bookName) \(summary.chapter)장"
    }


    @ViewBuilder
    private var syncStatusLabel: some View {
        switch autosave?.status {
        case .saved, .none:
            Label("동기화됨", systemImage: "checkmark.icloud")
                .font(.caption)
                .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
        case .pending:
            Label("대기 중", systemImage: "icloud")
                .font(.caption)
                .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
        case .saving:
            Label("동기화 중", systemImage: "arrow.triangle.2.circlepath.icloud")
                .font(.caption)
                .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
        }
    }

    // MARK: - 태그 — `MemoDetailView.tagSection`/태그 조작 메서드와 완전히 같은
    // 구조(그 파일 참고), `UserMemo`/`MemoTag` 대신 `VerseSummary`/`SummaryTag`를 쓴다.

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("태그").font(.caption).foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)

            FlowLayoutHStack {
                ForEach(summaryTags) { tag in
                    HStack(spacing: 4) {
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
                    // 연구문서 검색란(`DocumentsHomeView.searchAndFilterBar`)과 같은 상자 스타일(.plain TextField + 테마색 채움/테두리). 아이콘은 뺐다.
                    TextField(
                        "태그 입력 후 Enter",
                        text: $tagInput,
                        prompt: Text("태그 입력 후 Enter")
                            .foregroundStyle(settings.bibleTextColor?.opacity(0.5) ?? Color.secondary)
                    )
                        .textFieldStyle(.plain)
                        .font(.body)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(settings.bibleTextColor?.opacity(0.08) ?? Color.secondary.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(settings.bibleTextColor?.opacity(0.2) ?? Color.secondary.opacity(0.2), lineWidth: 1))
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
            tagSuggestions = Array(
                all
                    .filter { $0.normalizedForm.contains(trimmed) }
                    .filter { candidate in !summaryTags.contains { $0.id == candidate.id } }
                    .sorted {
                        // 이 화면의 `Tag`는 개인 묵상/말씀 요약 양쪽에서 쓰이므로 빈도는 두 조인 타입의 합으로 계산한다.
                        let lhsCount = ($0.memoTags?.count ?? 0) + ($0.summaryTags?.count ?? 0)
                        let rhsCount = ($1.memoTags?.count ?? 0) + ($1.summaryTags?.count ?? 0)
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
            print("[WordSummaryEditorView] 태그 생성 실패: \(error)")
        }
        tagInput = ""
        tagSuggestions = []
    }

    private func addTag(_ tag: Tag) {
        guard !summaryTags.contains(where: { $0.id == tag.id }) else { return }
        let join = SummaryTag(summary: summary, tag: tag)
        modelContext.insert(join)
        summaryTags.append(tag)
        tagInput = ""
        tagSuggestions = []
        autosave?.saveImmediately()
    }

    private func removeTag(_ tag: Tag) {
        if let join = (summary.summaryTags ?? []).first(where: { $0.tag?.id == tag.id }) {
            modelContext.delete(join)
        }
        summaryTags.removeAll { $0.id == tag.id }
        autosave?.saveImmediately()
    }

    // MARK: - 로드/저장

    private func loadIfNeeded() {
        guard !hasLoadedMetadata else { return }
        summaryTags = (summary.summaryTags ?? []).compactMap(\.tag).filter { !$0.isMerged }
        // 재인덱싱은 자동저장마다가 아니라 화면을 벗어날 때(`handleDisappear`) 한 번만 한다.
        // 저장 시에는 `pendingIndexRefresh = true`만 함께 저장된다.
        autosave = AutosaveController(modelContext: modelContext)
        hasLoadedMetadata = true
    }

    private func handleDisappear() {
        autosave?.flush()
        // `.contextual` 레코드는 본문이 자동 채운 날짜 문구(`WordSummaryDefaultSeed`)와 정확히 같으면 사용자가 아무것도 안 쓴 것으로 본다.
        // `createdAt`으로 재계산해 비교하므로 뷰 재생성에 영향받는 스냅샷이 없다.
        let isUntouchedContextualSeed = presentationContext == .contextual
            && summary.contentText == WordSummaryDefaultSeed.text(for: summary.createdAt)
        // 본문이 비어도 태그가 붙어 있으면 지우지 않는다(`MemoDetailView`와 동일).
        let isEmpty = (summary.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || isUntouchedContextualSeed)
            && summaryTags.isEmpty
        // 빈 레코드로 지워질 때 남아 있을 수 있는 인덱스도 함께 정리한다.
        autosave?.deleteIfEmpty(summary, isEmpty: isEmpty) { [modelContext] in
            BibleReferenceIndexingService.removeMentions(
                sourceType: .wordSummary, sourceId: summary.id.uuidString, context: modelContext
            )
            // FTS 보조 인덱스 항목도 함께 지운다.
            UserContentSearchIndexLocation.delete(category: .wordSummary, sourceId: summary.id.uuidString)
        }
        // 지워지지 않고 남았고 본문이 실제로 바뀐(`pendingIndexRefresh`) 경우에만 재인덱싱한다.
        if !isEmpty && summary.pendingIndexRefresh {
            BibleReferenceIndexingService.reindexWordSummary(summary, context: modelContext)
            // FTS 인덱스도 같은 신호로 최신화한다.
            UserContentSearchIndexLocation.upsert(
                category: .wordSummary, sourceId: summary.id.uuidString, content: summary.contentText
            )
            summary.pendingIndexRefresh = false
            try? modelContext.save()
        }
    }
}
