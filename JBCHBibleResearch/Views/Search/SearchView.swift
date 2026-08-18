//
//  SearchView.swift
//  JBCHBibleResearch
//
//  S11(통합 검색/의미검색) 화면. 검색어 입력 + [키워드 검색|의미검색(AI)] 토글 +
//  성경구절/내 메모/연구문서 3분류 결과(원문 목업 그대로).
//
//  [2026-08-18 대폭 확장] 사용자 요청 — "성경 조회 / 개요 / 연구문서 / 메모 /
//  개인 묵상 / 말씀 요약 --> 모든 내용이 다 검색 되어야 함." + "검색 결과를
//  표현하는 것도 연구문서 리스트 검색 결과처럼 검색일치 횟수+ 태그 + 본문내용+
//  형광펜 강조." 6개 분류 전부 표시하고, 키워드 검색 결과는 `DocumentsHomeView`
//  검색 결과와 같은 표현(일치 횟수 접두어 + 태그 뱃지 + 형광펜 강조 발췌)을
//  쓴다 — `highlightedText`/`badge`는 그 화면의 것과 같은 원리로 이 파일 안에
//  따로 둔다(세 번째 사용처가 아직 없어 공통 헬퍼로 추출하지 않는다는 이
//  프로젝트의 기존 원칙, `SearchViewModel.storeCache` 상단 주석 참고).
//

import SwiftUI
import SwiftData
import BibleResearchModels
#if os(iOS)
import UIKit
#endif

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: SearchViewModel?

    var body: some View {
        Group {
            if let viewModel {
                SearchContentView(viewModel: viewModel)
            } else {
                ProgressView()
                    .onAppear {
                        let vm = SearchViewModel(modelContext: modelContext)
                        vm.onAppear()
                        // [2026-08-18 추가] 사이드바 상단 검색창이 넘긴 검색어가
                        // 있으면(SidebarSearchRequest.swift 상단 주석 참고) 이
                        // 화면이 처음 만들어지는 시점에 곧바로 반영한다 —
                        // 아래 `.onChange`는 이 화면이 이미 떠 있는 채로 사용자가
                        // 사이드바에서 다시 검색했을 때만 쓰인다.
                        if let pending = SidebarSearchRequest.shared.pendingQuery {
                            vm.query = pending
                            SidebarSearchRequest.shared.clear()
                        }
                        viewModel = vm
                    }
            }
        }
        .navigationTitle("통합 검색")
        // [2026-08-18 추가] `SidebarNavigationView`의 `.onChange(of:
        // AppNavigationRequest.shared.requestedSection)`과 같은 패턴 — 평범한
        // Equatable(String?) 싱글턴 프로퍼티라 안전하게 관찰할 수 있다.
        .onChange(of: SidebarSearchRequest.shared.pendingQuery) { _, newValue in
            guard let newValue, let viewModel else { return }
            viewModel.query = newValue
            SidebarSearchRequest.shared.clear()
        }
    }
}

private struct SearchContentView: View {
    let viewModel: SearchViewModel
    // [2026-08-07 추가] S6이 별도 창으로 바뀌면서(JBCHBibleResearchApp.swift
    // "document-viewer" WindowGroup 참고) 검색결과의 문서 진입점도 새 창을 연다.
    @Environment(\.openWindow) private var openWindow

    /// [2026-08-18 신설, 아이폰 실기기 크래시 fix] DocumentsHomeView.swift의
    /// `isPhoneIdiom`과 같은 패턴 — 아이폰은 다중 씬(멀티 윈도우)을 지원하지
    /// 않아 `openWindow`가 "Unable to open a window when the app does not
    /// support multiple scenes" 런타임 에러를 낸다. `UIDevice`는 iOS에서만
    /// 존재하므로 `#if os(iOS)`로 감싼다.
    private var isPhoneIdiom: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    var body: some View {
        List {
            Section {
                Picker("검색 방식", selection: Binding(
                    get: { viewModel.mode },
                    set: { viewModel.mode = $0 }
                )) {
                    ForEach(SearchViewModel.Mode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if viewModel.mode == .semantic {
                    semanticStatusRow
                }

                if viewModel.isSearching {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("검색 중...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                if let errorDescription = viewModel.errorDescription {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(errorDescription)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .padding(.vertical, 2)
                }
            }
            .padding(.vertical, 4)

            if !viewModel.query.trimmingCharacters(in: .whitespaces).isEmpty {
                resultsSection
            }
        }
        .searchable(text: Binding(
            get: { viewModel.query },
            set: { viewModel.query = $0 }
        ), prompt: "검색어 입력")
        .onDisappear { viewModel.onDisappear() }
    }

    // MARK: - 결과

    // [2026-08-19 추가] 사용자 요청 — "통합검색결과 스타일을 보완: 글자크기를
    // 키우고, 각 리스트 항목의 행단위간격을 여유롭게 할것. UI/UX 디자인전문가
    // 관점에서 검토하고, 심미성도 확보할것. 적절한 색상과 아이콘도 사용할 것."
    // 6개 분류마다 고유 색상 + SF Symbol 아이콘으로 시각적으로 구분되게 하고,
    // 커스텀 섹션 헤더(아이콘 + 굵은 제목 + 캡슐형 개수 배지)를 쓴다 —
    // `Section("문자열")`의 기본 헤더는 작은 대문자 스타일이라 아이콘을 넣을
    // 자리가 없다.
    @ViewBuilder
    private var resultsSection: some View {
        Section {
            if viewModel.verseResults.isEmpty { emptyRow() }
            ForEach(viewModel.verseResults) { result in
                verseRow(result)
            }
        } header: {
            sectionHeader("성경구절", icon: "book.closed.fill", color: .indigo, count: viewModel.verseResults.count)
        }

        // [2026-08-18 추가] 개요/메모는 키워드 검색 전용(SearchViewModel.swift
        // 상단 "범위 결정" 주석 참고) — 의미검색 모드에서는 항상 비어 있으니
        // 빈 섹션을 보여줘 혼란을 주지 않도록 아예 숨긴다.
        if viewModel.mode == .keyword {
            Section {
                if viewModel.outlineResults.isEmpty { emptyRow() }
                ForEach(viewModel.outlineResults) { result in
                    outlineRow(result)
                }
            } header: {
                sectionHeader("개요", icon: "list.bullet.rectangle.fill", color: .teal, count: viewModel.outlineResults.count)
            }

            Section {
                if viewModel.phraseNoteResults.isEmpty { emptyRow() }
                ForEach(viewModel.phraseNoteResults) { result in
                    phraseNoteRow(result)
                }
            } header: {
                sectionHeader("메모", icon: "note.text", color: .orange, count: viewModel.phraseNoteResults.count)
            }
        }

        Section {
            if viewModel.memoResults.isEmpty { emptyRow() }
            ForEach(viewModel.memoResults) { result in
                memoRow(result)
            }
        } header: {
            sectionHeader("개인 묵상", icon: "heart.text.square.fill", color: .pink, count: viewModel.memoResults.count)
        }

        if viewModel.mode == .keyword {
            Section {
                if viewModel.summaryResults.isEmpty { emptyRow() }
                ForEach(viewModel.summaryResults) { result in
                    summaryRow(result)
                }
            } header: {
                sectionHeader("말씀 요약", icon: "text.quote", color: .purple, count: viewModel.summaryResults.count)
            }
        }

        Section {
            if viewModel.documentResults.isEmpty { emptyRow() }
            ForEach(viewModel.documentResults) { result in
                documentRow(result)
            }
        } header: {
            sectionHeader("연구문서", icon: "doc.text.fill", color: .brown, count: viewModel.documentResults.count)
        }
    }

    /// 커스텀 섹션 헤더 — 아이콘 + 굵은 제목 + 캡슐형 개수 배지. `.textCase(nil)`로
    /// List 섹션 헤더 기본값(작은 대문자)을 끄지 않으면 우리가 지정한 `.headline`
    /// 스타일이 시스템 스타일에 덮인다.
    private func sectionHeader(_ title: String, icon: String, color: Color, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            Text("\(count)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15), in: Capsule())
        }
        .textCase(nil)
        .padding(.vertical, 4)
    }

    private func emptyRow(_ text: String = "결과 없음") -> some View {
        HStack(spacing: 6) {
            Image(systemName: "tray")
                .foregroundStyle(.tertiary)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .padding(.vertical, 6)
    }

    /// [2026-08-19 신설] 6개 분류 행이 전부 "아이콘 배지 + 제목(+참조/점수 배지) +
    /// 태그 뱃지 + (일치횟수)본문 발췌"라는 같은 뼈대를 공유해서, 그 뼈대를 한
    /// 곳에 모았다 — 글자 크기·행 간격·색상을 6곳에 따로 손대지 않고 여기
    /// 한 번에 조정할 수 있다. `occurrenceCount`가 nil이면(성경구절 본문 미리보기,
    /// 의미검색 스니펫처럼 "몇 번 일치"가 의미 없는 경우) 칩 없이 발췌 텍스트만
    /// 보여준다.
    @ViewBuilder
    private func rowLabel(
        icon: String,
        iconColor: Color,
        title: String,
        isReferenceMatch: Bool = false,
        score: Float? = nil,
        tagNames: [String] = [],
        occurrenceCount: Int? = nil,
        excerptText: String? = nil,
        excerptKeywords: [String] = []
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            categoryIcon(icon, color: iconColor)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if isReferenceMatch {
                        badge("참조 일치", color: .green, systemImage: "checkmark.seal.fill")
                    }
                    Spacer(minLength: 4)
                    scoreBadge(score)
                }
                if !tagNames.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(tagNames, id: \.self) { name in
                            badge(name, color: .blue, systemImage: "tag.fill")
                        }
                    }
                }
                if let excerptText {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if let occurrenceCount {
                            occurrenceChip(occurrenceCount)
                        }
                        highlightedText(excerptText, keywords: excerptKeywords)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    /// 분류별 색상 원형 아이콘 배지.
    private func categoryIcon(_ systemImage: String, color: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 34, height: 34)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    /// "(xx 회 일치)" 접두어 — 예전엔 그냥 캡션 텍스트였는데, 강조색 캡슐 배지로
    /// 바꿔 본문 발췌와 시각적으로 구분되게 한다.
    private func occurrenceChip(_ count: Int) -> some View {
        Text("\(count)회 일치")
            .font(.caption.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.14), in: Capsule())
            .foregroundStyle(Color.accentColor)
            .fixedSize()
    }

    // MARK: - 성경구절

    private func verseRow(_ result: VerseSearchResult) -> some View {
        NavigationLink {
            BibleReadingView(
                initialBook: BooksProvider.shared.book(id: result.bookId),
                initialChapter: result.chapter
            )
        } label: {
            rowLabel(
                icon: "book.closed.fill", iconColor: .indigo,
                title: "\(result.bookNameKo) \(result.chapter):\(result.verse)",
                isReferenceMatch: result.isReferenceMatch,
                score: result.score,
                excerptText: result.content, excerptKeywords: result.highlightKeywords
            )
        }
    }

    // MARK: - 개요(BookOutline/ChapterSummary)

    private func outlineRow(_ result: OutlineSearchResult) -> some View {
        Button {
            AppNavigationRequest.shared.request(.outline)
            if let chapter = result.chapter {
                OutlineNavigationRequest.shared.request(bookId: result.bookId, chapter: chapter)
            } else {
                OutlineNavigationRequest.shared.requestBook(bookId: result.bookId)
            }
        } label: {
            rowLabel(
                icon: "list.bullet.rectangle.fill", iconColor: .teal,
                title: outlineTitle(result),
                isReferenceMatch: result.isReferenceMatch,
                occurrenceCount: result.bodyExcerpt != nil ? result.bodyOccurrenceSum : nil,
                excerptText: result.bodyExcerpt, excerptKeywords: result.highlightKeywords
            )
        }
        // SidebarNavigationView의 "태그 관계" 별도 창 항목과 같은 원칙 — 새
        // 화면으로 전환하는 Button이 List 안에서 기존 NavigationLink 행과 같은
        // 텍스트 색으로 보이도록 `.plain`을 쓴다.
        .buttonStyle(.plain)
    }

    private func outlineTitle(_ result: OutlineSearchResult) -> String {
        let bookName = BooksProvider.shared.book(id: result.bookId)?.nameKo ?? "성경"
        if let chapter = result.chapter {
            return "\(bookName) \(chapter)장 개요"
        }
        return "\(bookName) 개요"
    }

    // MARK: - 메모(VersePhraseNote)

    private func phraseNoteRow(_ result: PhraseNoteSearchResult) -> some View {
        NavigationLink {
            BibleReadingView(
                initialBook: BooksProvider.shared.book(id: result.note.bookId),
                initialChapter: result.note.chapter
            )
        } label: {
            rowLabel(
                icon: "note.text", iconColor: .orange,
                title: phraseNoteTitle(result.note),
                isReferenceMatch: result.isReferenceMatch,
                occurrenceCount: result.bodyExcerpt != nil ? result.bodyOccurrenceSum : nil,
                excerptText: result.bodyExcerpt ?? result.note.noteText, excerptKeywords: result.highlightKeywords
            )
        }
    }

    private func phraseNoteTitle(_ note: VersePhraseNote) -> String {
        let bookName = BooksProvider.shared.book(id: note.bookId)?.nameKo ?? "성경"
        return "\(bookName) \(note.chapter):\(note.verse) 메모"
    }

    // MARK: - 개인 묵상(UserMemo)

    private func memoRow(_ result: MemoSearchResult) -> some View {
        NavigationLink {
            MemoDetailView(memo: result.memo)
        } label: {
            rowLabel(
                icon: "heart.text.square.fill", iconColor: .pink,
                title: memoTitle(result.memo),
                score: result.score,
                tagNames: viewModel.mode == .keyword ? result.matchedTagNames : [],
                occurrenceCount: (viewModel.mode == .keyword && result.bodyExcerpt != nil) ? result.bodyOccurrenceSum : nil,
                excerptText: viewModel.mode == .keyword ? result.bodyExcerpt : result.snippet,
                excerptKeywords: viewModel.mode == .keyword ? result.highlightKeywords : []
            )
        }
    }

    private func memoTitle(_ memo: UserMemo) -> String {
        let bookName = BooksProvider.shared.book(id: memo.bookId)?.nameKo ?? "성경"
        return "\(bookName) \(memo.chapter)장 메모"
    }

    // MARK: - 말씀 요약(VerseSummary)

    private func summaryRow(_ result: SummarySearchResult) -> some View {
        NavigationLink {
            WordSummaryEditorView(summary: result.summary, presentationContext: .standalone)
        } label: {
            rowLabel(
                icon: "text.quote", iconColor: .purple,
                title: summaryTitle(result.summary),
                tagNames: result.matchedTagNames,
                occurrenceCount: result.bodyExcerpt != nil ? result.bodyOccurrenceSum : nil,
                excerptText: result.bodyExcerpt, excerptKeywords: result.highlightKeywords
            )
        }
    }

    private func summaryTitle(_ summary: VerseSummary) -> String {
        let bookName = BooksProvider.shared.book(id: summary.bookId)?.nameKo ?? "성경"
        return "\(bookName) \(summary.chapter)장 말씀 요약"
    }

    // MARK: - 연구문서(SourceDocument)

    @ViewBuilder
    private func documentRow(_ result: DocumentSearchResult) -> some View {
        // [2026-08-18 수정, 아이폰 실기기 크래시 fix] 아이폰은 다중 씬을
        // 지원하지 않아 `openWindow`가 런타임 에러를 낸다(isPhoneIdiom 선언부
        // 참고) — 아이폰에서만 이 화면의 NavigationStack 안으로 직접 밀어
        // 넣는 destination 클로저 방식 `NavigationLink`를 쓴다(바로 위
        // `summaryRow`가 이미 쓰던 것과 같은 스타일이라 별도 `.navigationDestination`
        // 등록이 필요 없다).
        if isPhoneIdiom {
            NavigationLink {
                DocumentViewerWindowContent(documentID: result.document.persistentModelID)
            } label: {
                rowLabel(
                    icon: "doc.text.fill", iconColor: .brown,
                    title: documentTitle(result),
                    score: result.score,
                    tagNames: viewModel.mode == .keyword ? result.matchedTagNames : [],
                    occurrenceCount: (viewModel.mode == .keyword && result.bodyExcerpt != nil) ? result.bodyOccurrenceSum : nil,
                    excerptText: viewModel.mode == .keyword ? result.bodyExcerpt : result.snippet,
                    excerptKeywords: viewModel.mode == .keyword ? result.highlightKeywords : []
                )
            }
        } else {
            Button {
                openWindow(id: "document-viewer", value: result.document.persistentModelID)
            } label: {
                rowLabel(
                    icon: "doc.text.fill", iconColor: .brown,
                    title: documentTitle(result),
                    score: result.score,
                    tagNames: viewModel.mode == .keyword ? result.matchedTagNames : [],
                    occurrenceCount: (viewModel.mode == .keyword && result.bodyExcerpt != nil) ? result.bodyOccurrenceSum : nil,
                    excerptText: viewModel.mode == .keyword ? result.bodyExcerpt : result.snippet,
                    excerptKeywords: viewModel.mode == .keyword ? result.highlightKeywords : []
                )
            }
            // SidebarNavigationView의 "태그 관계" 별도 창 항목과 같은 원칙 —
            // 새 창을 여는 Button이 List 안에서 기존 NavigationLink 행과 같은
            // 텍스트 색으로 보이도록 `.plain`을 쓴다(버튼 기본 스타일은 강조색
            // 틴트를 입힌다).
            .buttonStyle(.plain)
        }
    }

    private func documentTitle(_ result: DocumentSearchResult) -> String {
        if let page = result.pageNumber {
            return "\(result.document.originalFilename) p.\(page + 1)"
        }
        return result.document.originalFilename
    }

    /// [2026-08-19 수정] 사용자 요청 — "적절한 색상과 아이콘도 사용할 것."
    /// 예전엔 회색 캡션 텍스트뿐이었다 — 점수 구간별 색(초록=강함/주황=보통/
    /// 회색=약함)을 채운 캡슐 배지로 바꿔 한눈에 관련도를 가늠할 수 있게 했다
    /// (의미검색 모드에서만 값이 있다 — 키워드 검색 결과는 nil이라 아무것도
    /// 안 그린다).
    @ViewBuilder
    private func scoreBadge(_ score: Float?) -> some View {
        if let score {
            Text("\(Int(score * 100))%")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(scoreColor(score), in: Capsule())
        }
    }

    private func scoreColor(_ score: Float) -> Color {
        switch score {
        case ..<0.4: return .gray
        case ..<0.6: return .orange
        default: return .green
        }
    }

    // MARK: - 형광펜 강조 / 태그 뱃지 (DocumentsHomeView.DocumentRowView와 같은 원리)

    /// `DocumentsHomeView.DocumentRowView.highlightedText`와 완전히 같은 구현 —
    /// 원본 문자열 위에서 바로 대소문자 무시 검색해 겹치는 범위에 배경색을 입힌다
    /// (lowercased()로 만든 별도 문자열의 인덱스를 재사용하지 않는 이유도 같다).
    private func highlightedText(_ text: String, keywords: [String]) -> Text {
        let trimmedKeywords = keywords.filter { !$0.isEmpty }
        guard !trimmedKeywords.isEmpty else { return Text(text) }

        var attributed = AttributedString(text)
        for keyword in trimmedKeywords {
            var searchRange = text.startIndex..<text.endIndex
            while let found = text.range(of: keyword, options: [.caseInsensitive], range: searchRange) {
                if let attrRange = Range(found, in: attributed) {
                    attributed[attrRange].backgroundColor = .yellow.opacity(0.5)
                }
                searchRange = found.upperBound..<text.endIndex
            }
        }
        return Text(attributed)
    }

    /// [2026-08-19 확장] 아이콘을 선택적으로 붙일 수 있게 했다("참조 일치" 배지는
    /// 체크마크, 태그 배지는 태그 아이콘) — 폰트도 `.caption2`→`.caption`으로
    /// 한 단계 키워 다른 확대된 본문 요소들과 균형을 맞췄다.
    private func badge(_ text: String, color: Color, systemImage: String? = nil) -> some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
            }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15), in: Capsule())
        .foregroundStyle(color)
    }

    // MARK: - 의미검색 상태

    @ViewBuilder
    private var semanticStatusRow: some View {
        switch viewModel.embeddingAvailability {
        case .unknown:
            HStack {
                ProgressView().controlSize(.small)
                Text("의미검색 모델을 준비하는 중입니다...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .available:
            VStack(alignment: .leading, spacing: 4) {
                if viewModel.isReindexingMemosAndDocuments {
                    Text("메모/연구문서 색인 갱신 중...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                bibleIndexControl
            }
        case .unsupportedLanguage:
            Text("이 기기에서 한국어 의미검색 모델을 지원하지 않아, 키워드 검색만 사용할 수 있습니다.")
                .font(.caption)
                .foregroundStyle(.orange)
        case .assetPreparationFailed(let reason):
            Text("의미검색 모델 준비 실패: \(reason)")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    /// ⚠️ 성경 전체(1,189장) 색인은 시간이 걸릴 수 있어 자동으로 실행하지 않는다
    /// (EmbeddingIndexingService.swift 상단 주석 참고) — 사용자가 직접 눌러야 시작된다.
    @ViewBuilder
    private var bibleIndexControl: some View {
        if viewModel.isReindexingBible {
            VStack(alignment: .leading, spacing: 2) {
                if let progress = viewModel.bibleIndexProgress {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    Text("성경 색인 중... \(progress.done)/\(progress.total)장")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
                Button("색인 중단", role: .destructive) { viewModel.cancelBibleReindex() }
                    .font(.caption)
            }
        } else {
            Button("성경 전체 장 단위 색인 만들기") { viewModel.startBibleReindex() }
                .font(.caption)
        }
    }
}
