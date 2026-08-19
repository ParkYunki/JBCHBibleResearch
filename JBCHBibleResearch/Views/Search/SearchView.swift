//
//  SearchView.swift
//  JBCHBibleResearch
//
//  S11(통합 검색) 화면. 검색어 입력 + 성경구절/개요/연구문서/메모/개인 묵상/
//  말씀 요약 6분류 결과(원문 목업 그대로).
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
//  [2026-08-19 삭제] 사용자 요청 — "의미검색(AI) 기능 삭제, 관련 DB 삭제." 예전
//  [키워드 검색|의미검색(AI)] 세그먼트 토글과 그 상태 표시(모델 준비/성경 전체
//  색인 버튼)를 뺐다.
//
//  [2026-08-19 신설, 이후 전면 교체] 사용자 요청 — "오른쪽 상단 검색창 왼쪽 옆
//  AI 토글 추가" → (결과가 거의 안 나오는 문제 보고 후) "애플 인텔리전스로
//  텍스트를 정제하고, 방식 A — 임베딩 기반 의미검색을 한다면?" → "완전 대체".
//  검색창 툴바의 AI 토글(`aiToggleButton`)은 이제 `BibleSemanticSearchService`
//  (정제 → 임베딩 → 코사인 유사도)를 쓴다. 이 방식은 성경 전체를 미리
//  임베딩해 둔 로컬 색인 파일이 있어야 동작하므로, 색인이 없으면 "색인 만들기"
//  안내 행(`bibleIndexCallToAction`)을 보여준다 — 예전에 지웠던 "성경 전체
//  색인 버튼" UI가 완전히 다른 파이프라인으로 다시 돌아온 셈이다.
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
                            // [2026-08-19] `query` didSet은 더 이상 자동으로
                            // 검색하지 않는다(타이핑 프리징 방지) — 사이드바
                            // 검색창에서 이미 사용자가 검색을 "제출"한 것이므로
                            // 여기선 명시적으로 즉시 검색한다.
                            vm.searchImmediately()
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
            viewModel.searchImmediately()
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

                // [2026-08-19 신설] 사용자 요청 — "검색이 완벽하지 않음을
                // 설명하는 검색창 하단에 추가." AI 검색은 온디바이스 모델의
                // 지식 한계로 정답을 놓치거나 틀릴 수 있다는 점을 미리
                // 알려준다 — `.searchable` 검색창은 시스템 내비게이션
                // 영역이라 그 안에 직접 넣을 수 없어, 검색창 바로 아래에
                // 오는 이 List 맨 위 Section에 넣었다.
                if viewModel.isAIQueryEnabled {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                        Text("AI 검색은 완벽하지 않을 수 있습니다. 결과가 부정확하거나 부족하면 AI 검색을 끄고 다시 검색해보세요.")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)

                    // [2026-08-19 신설] 사용자 요청 — "애플인텔리전스를 끈것과
                    // 켠것을 비교하고 싶음." 시스템 설정을 건드리지 않고 앱
                    // 안에서 바로 켬/끔을 비교할 수 있게 하는 토글.
                    Toggle(isOn: Binding(
                        get: { viewModel.isQueryRefinementEnabled },
                        set: { viewModel.isQueryRefinementEnabled = $0 }
                    )) {
                        Text("Apple Intelligence로 검색어 정제")
                    }
                    .font(.caption)
                    .padding(.vertical, 2)

                    // [2026-08-19 신설] 사용자 요청 — "Reranker도 고민해볼것."
                    // 검색어 정제와는 독립적인 별도 토글(SearchViewModel.
                    // isRerankEnabled 상단 주석 참고) — 두 AI 단계를 따로
                    // 비교할 수 있어야 한다.
                    Toggle(isOn: Binding(
                        get: { viewModel.isRerankEnabled },
                        set: { viewModel.isRerankEnabled = $0 }
                    )) {
                        Text("Apple Intelligence로 결과 재순위화")
                    }
                    .font(.caption)
                    .padding(.vertical, 2)

                    // [2026-08-19 v3 신설] 사용자 지시 — "verse/context weight
                    // 최적화... 0.2/0.8 ... 0.8/0.2 이렇게만 해도 검색 결과가
                    // 상당히 달라질 수 있습니다." 재빌드 없이 직접 스윕
                    // 테스트할 수 있도록 슬라이더로 노출한다.
                    VStack(alignment: .leading, spacing: 2) {
                        Text("절 \(Int((1 - viewModel.contextWeight) * 100))% · 문맥 \(Int(viewModel.contextWeight * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { viewModel.contextWeight },
                                set: { viewModel.contextWeight = $0 }
                            ),
                            in: 0.2...0.8,
                            step: 0.1
                        )
                    }
                    .padding(.vertical, 2)

                    // [2026-08-19 신설] 정제 켬/끔에 따라 실제로 임베딩에 들어간
                    // 문장이 달라지는 걸 눈으로 비교할 수 있게 보여준다 — 켰을
                    // 때 원문과 달라졌으면("~인가?" 같은 어미가 빠지는 등) 바로
                    // 확인 가능하다.
                    if let usedQuery = viewModel.lastAIQueryUsed, !usedQuery.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "text.magnifyingglass")
                            Text("검색에 사용된 문장: \(usedQuery)")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                    }

                    // [2026-08-19 신설] 의미검색은 성경 전체를 미리 임베딩해 둔
                    // 로컬 색인이 있어야 동작한다 — 색인 상태에 따라 만들기
                    // 안내/진행률을 여기 보여준다.
                    bibleIndexStatusRow
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
        // [2026-08-19 추가] 사용자 요청 — "엔터를 치면 검색이 되도록." 기본은
        // 타이핑을 멈추고 350ms 지나야 자동으로 검색되는데, 엔터(또는 iOS
        // 키보드의 검색 버튼)를 누르면 그 대기 없이 바로 검색한다.
        .onSubmit(of: .search) {
            viewModel.searchImmediately()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                aiToggleButton
            }
        }
        .onDisappear { viewModel.onDisappear() }
    }

    /// [2026-08-19 신설] 사용자 요청 — "오른쪽 상단 검색창 왼쪽 옆 AI 토글
    /// 추가." `.searchable`이 만드는 시스템 검색창은 툴바 맨 끝(trailing)에
    /// 붙으므로, 이 항목을 그보다 먼저 선언해 검색창 왼쪽에 놓이게 한다.
    ///
    /// [2026-08-19 수정, 전면 교체와 함께] 예전엔 FoundationModels(Apple
    /// Intelligence) 가용 여부로 토글을 비활성화했다. 지금은 실제로 필요한
    /// 것이 `EmbeddingService`(NLContextualEmbedding, iOS 17/macOS 14+로
    /// Apple Intelligence보다 지원 범위가 넓다)라 가용성 판정 기준 자체가
    /// 달라졌는데, 그 판정은 비동기(자산 다운로드 확인 포함)라 툴바 버튼을
    /// 그리는 시점에 동기적으로 물어볼 수 없다. 그래서 이번엔 미리 비활성화
    /// 하지 않고 항상 켤 수 있게 두고, 실제로 안 되는 경우(색인 미생성/임베딩
    /// 미지원)는 켠 뒤 `bibleIndexStatusRow`/검색 결과 에러 메시지로
    /// 알려준다 — 판정이 틀렸을 때 "쓸 수 있는데 막혀 있음"보다 "일단 눌러보고
    /// 안내를 받음" 쪽이 덜 답답하다고 판단했다.
    private var aiToggleButton: some View {
        Toggle(isOn: Binding(
            get: { viewModel.isAIQueryEnabled },
            set: { viewModel.isAIQueryEnabled = $0 }
        )) {
            Label("AI 검색", systemImage: "sparkles")
        }
        .toggleStyle(.button)
        .help("켜면 검색어를 다듬은 뒤 성경 구절과 의미가 비슷한 순서로 찾아줍니다. 처음 한 번은 성경 전체 색인이 필요합니다.")
    }

    /// [2026-08-19 신설] `viewModel.bibleIndexStatus`에 따라 "색인 만들기"
    /// 버튼(미생성)/진행률 바(생성 중)/완료 안내(생성됨)/실패 안내를 보여준다.
    /// AI 검색이 실제로 결과를 내려면 이 색인이 반드시 있어야 하므로, 검색
    /// 결과 목록보다 먼저(상단 Section 안) 눈에 띄게 둔다.
    @ViewBuilder
    private var bibleIndexStatusRow: some View {
        switch viewModel.bibleIndexStatus {
        case .notBuilt:
            HStack(spacing: 8) {
                Image(systemName: "shippingbox")
                Text("AI 검색을 쓰려면 먼저 성경 전체 색인이 필요합니다.")
                Spacer()
                Button("색인 만들기") {
                    viewModel.startBibleEmbeddingIndexing()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .font(.caption)
            .padding(.vertical, 2)
        case .building(let progress):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("성경 전체 색인 만드는 중… \(Int(progress * 100))%")
                    Spacer()
                    Button("취소") {
                        viewModel.cancelBibleEmbeddingIndexing()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                .font(.caption)
                ProgressView(value: progress)
            }
            .padding(.vertical, 2)
        case .ready(let verseCount, _):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("\(verseCount)개 절 색인 완료")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 2)
        case .failed(let message):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                Spacer()
                Button("다시 시도") {
                    viewModel.startBibleEmbeddingIndexing()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .font(.caption)
            .padding(.vertical, 2)
        }
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

        Section {
            if viewModel.memoResults.isEmpty { emptyRow() }
            ForEach(viewModel.memoResults) { result in
                memoRow(result)
            }
        } header: {
            sectionHeader("개인 묵상", icon: "heart.text.square.fill", color: .pink, count: viewModel.memoResults.count)
        }

        Section {
            if viewModel.summaryResults.isEmpty { emptyRow() }
            ForEach(viewModel.summaryResults) { result in
                summaryRow(result)
            }
        } header: {
            sectionHeader("말씀 요약", icon: "text.quote", color: .purple, count: viewModel.summaryResults.count)
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

    /// [2026-08-19 신설] 6개 분류 행이 전부 "아이콘 배지 + 제목(+참조 배지) +
    /// 태그 뱃지 + (일치횟수)본문 발췌"라는 같은 뼈대를 공유해서, 그 뼈대를 한
    /// 곳에 모았다 — 글자 크기·행 간격·색상을 6곳에 따로 손대지 않고 여기
    /// 한 번에 조정할 수 있다. `occurrenceCount`가 nil이면(성경구절 본문
    /// 미리보기처럼 "몇 번 일치"가 의미 없는 경우) 칩 없이 발췌 텍스트만
    /// 보여준다.
    @ViewBuilder
    private func rowLabel(
        icon: String,
        iconColor: Color,
        title: String,
        isReferenceMatch: Bool = false,
        similarityScore: Double? = nil,
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
                    // [2026-08-19 신설] AI 검색(의미검색) 결과 전용 — 코사인
                    // 유사도를 퍼센트로 보여준다. "참조 일치"와 동시에 나올 일은
                    // 없다(AI 검색 결과는 `isReferenceMatch`를 아예 안 씀,
                    // `SearchViewModel.performAIQuerySearch` 참고).
                    if let similarityScore {
                        badge("유사도 \(Int(similarityScore * 100))%", color: .purple, systemImage: "sparkles")
                    }
                    Spacer(minLength: 4)
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
                similarityScore: result.similarityScore,
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
                tagNames: result.matchedTagNames,
                occurrenceCount: result.bodyExcerpt != nil ? result.bodyOccurrenceSum : nil,
                excerptText: result.bodyExcerpt, excerptKeywords: result.highlightKeywords
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
                    tagNames: result.matchedTagNames,
                    occurrenceCount: result.bodyExcerpt != nil ? result.bodyOccurrenceSum : nil,
                    excerptText: result.bodyExcerpt, excerptKeywords: result.highlightKeywords
                )
            }
        } else {
            Button {
                openWindow(id: "document-viewer", value: result.document.persistentModelID)
            } label: {
                rowLabel(
                    icon: "doc.text.fill", iconColor: .brown,
                    title: documentTitle(result),
                    tagNames: result.matchedTagNames,
                    occurrenceCount: result.bodyExcerpt != nil ? result.bodyOccurrenceSum : nil,
                    excerptText: result.bodyExcerpt, excerptKeywords: result.highlightKeywords
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

}
