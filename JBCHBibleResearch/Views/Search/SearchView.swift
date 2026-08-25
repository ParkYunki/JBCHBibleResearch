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
                    // 켠것을 비교하고 싶음." — [2026-08-20 제거] 사용자 요청으로
                    // 이 자리에 있던 두 토글(Apple Intelligence로 검색어 정제/
                    // 결과 재순위화)을 없앴다("결과가 너무 이상함"/"너무 느리고
                    // 결과가 큰 차이 안 남"). `SearchViewModel.
                    // isQueryRefinementEnabled`/`isRerankEnabled` 프로퍼티도
                    // 함께 제거했다 — 이제 정제는 항상 건너뛰고(결정론적 꼬리표
                    // 제거만 적용), 재순위화는 항상 결정론적
                    // `BibleStructuralRerankerService`만 쓴다(둘 다 Apple
                    // Intelligence가 아니라 사용자가 제거 대상으로 언급하지
                    // 않았다).

                    // [2026-08-19 v3 신설, 2026-08-20 제거, Phase 5] "절 x% ·
                    // 문맥 x%" 슬라이더가 여기 있었다 — 사용자가 재검토하며
                    // "의미가 있는가? 없으면 삭제할 것"이라고 물어서 없앴다.
                    // 내부 코사인 유사도 블렌드 비율을 바꾸는 튜닝 값일 뿐,
                    // 만들 때부터 "0.6은 출발점일 뿐 최적값 근거는 없다"고
                    // 밝혀둔 실험용 슬라이더였고, "절/문맥 가중치"라는 개념 자체가
                    // 최종 사용자에게 해석 가능한 정보가 아니다(어느 쪽이 "더
                    // 나은 결과"인지 검증된 기준도 없음) — `SearchViewModel.
                    // intentCard` 선언부 근처 주석 참고. 내부 파라미터 자체는
                    // 기본값(0.6)으로 그대로 남아 있다(동작 변화 없음, UI만 제거).

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

            // [2026-08-20 신설, 2026-08-20 재수정 Phase 5] 일반 검색 결과 목록
            // 보다 먼저 보여준다 — 관계/인물·지명 정보/예언/주제·속성/서사
            // 카드가 "정답에 더 가까운 안내"이므로 우선 노출한다.
            // `viewModel.intentCard`가 nil이면 이 Section 자체가 안 그려지는데,
            // Phase 5부터는 `.general`로 분류되거나 참고 DB를 못 연 경우뿐
            // 아니라 **AI 검색 토글이 꺼져 있을 때도 항상 nil**이다 — 사용자
            // 요청("단순 키워드 검색시엔 순수 키워드 검색결과만, 관계정보는
            // AI 토글을 켰을 때만")에 따라 `SearchViewModel.performSearch`가
            // 키워드 검색 모드에선 이 카드를 아예 계산하지 않는다.
            if let intentCard = viewModel.intentCard {
                intentCardSection(intentCard)
            }

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
            // [2026-08-21 추가] 사용자 요청 — "PersonPlaceSeed.json 데이터를 좀더
            // 고도화 정제 후에 다시 시도할 예정. 그전까지 AI 토글은 개발
            // 상태에서만 보여주고 배포할 때는 뺄 수 있도록 할 것." `#if DEBUG`로
            // 감싸 Release(배포용) 빌드에는 이 버튼 자체가 컴파일되지 않게
            // 했다 — `viewModel.isAIQueryEnabled`는 이 버튼으로만 켤 수
            // 있고(다른 진입점 없음, 영구 저장도 안 함 — SearchViewModel.swift
            // 175번째 줄 선언 참고) 기본값이 `false`라, 버튼이 없으면 Release
            // 빌드에서는 이 값이 구조적으로 항상 false로 남아 AI 검색 관련
            // 코드 경로(안내 배너/색인 상태 행/의미검색 호출) 전체가 저절로
            // 비활성 상태가 된다 — 아래 나머지 AI 관련 코드는 그대로 두고
            // 진입점만 뺀 것.
            #if DEBUG
            ToolbarItem(placement: .primaryAction) {
                aiToggleButton
            }
            #endif
        }
        .onDisappear { viewModel.onDisappear() }
    }

    // [2026-08-21 추가] 위 toolbar의 `#if DEBUG` 주석 참고 — Release 빌드에서는
    // 이 프로퍼티를 호출하는 곳이 아예 없어지므로(툴바에서만 참조됨), 선언
    // 자체도 함께 `#if DEBUG`로 감싼다(안 그러면 미사용 private 프로퍼티로
    // 남는다).
    #if DEBUG
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
    #endif

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

    // MARK: - 질의 의도 카드 (관계/인물·지명 정보/예언/주제·속성/서사, 2026-08-20 신설)
    //
    // [2026-08-20 신설] `QueryIntentClassifier`+`QueryIntentHandler`(Services/
    // Search) 결과를 아래 `resultsSection`(일반 검색) 위에 별도 Section으로
    // 보여준다. 데이터가 없으면(지금은 Prophecies/Themes/TimelineEvents가
    // 전부 스키마만 있고 0건) 안내 문구만 뜨고, 그 아래 일반 검색은 항상 그대로
    // 나온다 — 이 카드가 오분류되거나 데이터가 없어도 검색 자체가 막히지
    // 않는다는 3계층 구조의 안전장치를 그대로 반영한다.
    //
    // ⚠️ [미검증] 이 세션엔 Xcode가 없어 컴파일 확인을 못 했다 — 아이콘(SF
    // Symbol)도 실제 렌더링을 미리보기하지 못한 채 이름만으로 골랐다(전부
    // iOS 16 이전부터 있던 것으로 알고 있는 심볼만 썼다 — `scroll.fill`만
    // iOS 16 시점 추가로 알고 있으나, 이 앱이 이미 SwiftData(`@Model`, iOS
    // 17+ 요구)를 쓰고 있어 배포 대상이 그보다 낮을 수 없다고 판단했다).

    @ViewBuilder
    private func intentCardSection(_ card: QueryIntentCard) -> some View {
        let meta = intentSectionMeta(card.intent)
        Section {
            switch card.status {
            case .notReady(let message):
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                    Text(message)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            case .found(let content):
                intentContentRows(content)
            }
        } header: {
            sectionHeader(meta.title, icon: meta.icon, color: meta.color, count: card.foundCount)
        }
    }

    private func intentSectionMeta(_ intent: QueryIntentClassifier.Intent) -> (title: String, icon: String, color: Color) {
        switch intent {
        case .relation: return ("관계 정보", "person.2.fill", .cyan)
        case .personOrPlaceInfo: return ("인물·지명 정보", "person.crop.circle.fill", .mint)
        case .prophecy: return ("예언", "scroll.fill", .yellow)
        case .themeOrAttribute: return ("주제·속성", "lightbulb.fill", .green)
        case .narrative: return ("서사·흐름", "list.number", .gray)
        case .general: return ("", "questionmark", .gray)  // QueryIntentHandler.handle이 .general이면 nil을 돌려줘서 실제로는 안 쓰인다.
        }
    }

    @ViewBuilder
    private func intentContentRows(_ content: QueryIntentCard.Content) -> some View {
        switch content {
        case .relation(let items):
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                relationRow(item)
            }
        case .personOrPlace(let entities):
            ForEach(Array(entities.enumerated()), id: \.offset) { _, entity in
                personOrPlaceRow(entity)
            }
        case .prophecy(let prophecies):
            ForEach(Array(prophecies.enumerated()), id: \.offset) { _, prophecy in
                prophecyRow(prophecy)
            }
        case .theme(let themes):
            ForEach(Array(themes.enumerated()), id: \.offset) { _, theme in
                themeRow(theme)
            }
        case .narrative(let groups):
            ForEach(groups) { group in
                narrativeGroupRows(group)
            }
        }
    }

    // MARK: - 관계 행

    /// [2026-08-20 신설, Phase 4 — 2026-08-20 재수정, Phase 5] Phase 4에선 이
    /// 행이 `item.verseRefs.first`로 이동하는 `NavigationLink`였다("다윗의
    /// 아들들은?" 카드 아래 성경 구절이 관계와 무관하다는 리포트에 대한 수정,
    /// `RelationDisplayItem` 주석 참고). Phase 5에서 사용자가 실사용 후 요청을
    /// 바꿨다 — "클릭했을때 구절 이동 하지말고, 아래 성경구절로 표시될 수
    /// 있도록." 이제 이 관계 카드의 좌표들은 `QueryIntentCard.verseRefs`를
    /// 통해 "성경구절" 섹션 자체에 이미 나열되므로(`SearchViewModel.
    /// performAIQuerySearch` 참고), 관계 행은 그 목록을 다시 가리키는
    /// 내비게이션을 따로 둘 필요가 없다 — 텍스트 행으로 되돌렸다.
    private func relationRow(_ item: RelationDisplayItem) -> some View {
        relationLabel(item)
    }

    private func relationLabel(_ item: RelationDisplayItem) -> some View {
        rowLabel(
            icon: "person.2.fill", iconColor: .cyan,
            title: PersonRelationLabeling.sentence(for: item.relation),
            excerptText: item.relation.rawSentence
        )
    }

    // MARK: - 인물·지명 정보 행

    private func personOrPlaceRow(_ entity: ReferenceEntity) -> some View {
        Group {
            if let first = entity.verseRefs.first {
                NavigationLink {
                    BibleReadingView(
                        initialBook: BooksProvider.shared.book(id: first.bookId),
                        initialChapter: first.chapter, initialVerse: first.verse
                    )
                } label: {
                    personOrPlaceLabel(entity)
                }
            } else {
                personOrPlaceLabel(entity)
            }
        }
    }

    private func personOrPlaceLabel(_ entity: ReferenceEntity) -> some View {
        // [2026-08-20 갱신, 2026-08-21 주석만 갱신] 화면 표시는 데이터 분석
        // 전용이던 description(수기로 간결하게 다듬어짐, 2026-08-21에 이
        // 값 타입에서 아예 제거됨) 대신 `entityRemark`(화면 출력용, 수기
        // 편집 이전의 원문 서술)를 쓴다 — 사용자 요청, `ReferenceEntity.swift`
        // 주석 참고.
        rowLabel(
            icon: entity.kind == .person ? "person.crop.circle.fill" : "location.fill",
            iconColor: entity.kind == .person ? .mint : .teal,
            title: entity.word,
            excerptText: entity.entityRemark
        )
    }

    // MARK: - 예언 행

    private func prophecyRow(_ prophecy: ProphecyRecord) -> some View {
        Group {
            if let first = prophecy.prophecyRefs.first {
                NavigationLink {
                    BibleReadingView(
                        initialBook: BooksProvider.shared.book(id: first.bookId),
                        initialChapter: first.chapter, initialVerse: first.verse
                    )
                } label: {
                    prophecyLabel(prophecy)
                }
            } else {
                prophecyLabel(prophecy)
            }
        }
    }

    private func prophecyLabel(_ prophecy: ProphecyRecord) -> some View {
        var tags = [prophecy.category]
        if let period = prophecy.timelinePeriod, !period.isEmpty { tags.append(period) }
        return rowLabel(
            icon: "scroll.fill", iconColor: .yellow,
            title: prophecy.title,
            tagNames: tags.filter { !$0.isEmpty },
            excerptText: prophecy.prophecyDescription
        )
    }

    // MARK: - 주제·속성 행

    private func themeRow(_ theme: ThemeRecord) -> some View {
        Group {
            if let first = theme.verseRefs.first {
                NavigationLink {
                    BibleReadingView(
                        initialBook: BooksProvider.shared.book(id: first.bookId),
                        initialChapter: first.chapter, initialVerse: first.verse
                    )
                } label: {
                    themeLabel(theme)
                }
            } else {
                themeLabel(theme)
            }
        }
    }

    private func themeLabel(_ theme: ThemeRecord) -> some View {
        rowLabel(
            icon: "lightbulb.fill", iconColor: .green,
            title: theme.title,
            tagNames: [theme.category].filter { !$0.isEmpty },
            excerptText: theme.themeDescription
        )
    }

    // MARK: - 서사 행

    @ViewBuilder
    private func narrativeGroupRows(_ group: NarrativeGroup) -> some View {
        ForEach(Array(group.events.enumerated()), id: \.offset) { _, event in
            narrativeEventRow(group: group, event: event)
        }
    }

    private func narrativeEventRow(group: NarrativeGroup, event: TimelineEventRecord) -> some View {
        Group {
            if let first = event.verseRefs.first {
                NavigationLink {
                    BibleReadingView(
                        initialBook: BooksProvider.shared.book(id: first.bookId),
                        initialChapter: first.chapter, initialVerse: first.verse
                    )
                } label: {
                    narrativeEventLabel(group: group, event: event)
                }
            } else {
                narrativeEventLabel(group: group, event: event)
            }
        }
    }

    private func narrativeEventLabel(group: NarrativeGroup, event: TimelineEventRecord) -> some View {
        rowLabel(
            icon: "list.number", iconColor: .gray,
            title: "\(group.narrativeTitle) — \(event.eventTitle)",
            excerptText: event.eventDescription
        )
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
                    // [2026-08-19 신설, 2026-08-20 제거, Phase 5] AI 검색(의미
                    // 검색) 결과 전용 "유사도 xx%" 배지가 여기 있었다 — 사용자
                    // 재검토 후 삭제. 삭제 근거(추측 아님, 코드로 확인한 사실):
                    // `BibleSemanticSearchService.search`가 최종 반환 직전에
                    // `BibleStructuralRerankerService.rerank`로 순서를 다시
                    // 매기는데(인물/관계/관주 가산 신호 반영), 그 함수는 정렬만
                    // 다시 하고 각 결과에 붙은 `similarity` 값 자체는 갱신하지
                    // 않는다 — 그래서 화면에 최종적으로 보이는 "순서"와 배지에
                    // 찍히는 "%" 값의 우선순위가 서로 어긋날 수 있었다(구조적
                    // 신호로 끌어올려진 절이 자신보다 순위가 낮은 절보다 오히려
                    // 낮은 %를 보여주는 경우가 생김). 게다가 하이브리드 키워드
                    // 병합 후보는 전부 "1위 후보의 유사도"를 그대로 복사해 쓰고
                    // (`hybridSimilarity`), 관주로 끌려온 후보는 원본에서 임의로
                    // 0.05를 뺀 값이라 애초에 실제 유사도가 아니었다 — 표시된
                    // 숫자가 실제 순위 근거와 다르면 사용자에게 오히려 혼란만
                    // 준다고 판단해 배지 자체를 없앴다(내부 정렬 로직은 그대로
                    // 유지 — 표시만 뺐다).
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
                initialChapter: result.chapter,
                // [2026-08-19 추가] 사용자 요청 — "검색 결과중 - 성경구절을
                // 클릭하면 해당하는 절까지 스크롤 이동해서 잠시 하이라이트
                // 표시해줄것."
                initialVerse: result.verse
            )
        } label: {
            rowLabel(
                icon: "book.closed.fill", iconColor: .indigo,
                title: "\(result.bookNameKo) \(result.chapter):\(result.verse)",
                isReferenceMatch: result.isReferenceMatch,
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

    /// [2026-08-25 추가] 사용자 요청 — "연구문서 클릭하면 해당 검색어가 뷰어의
    /// 검색어로 입력되어 해당 부분으로 자동 하이라이트되게 할것. (성경구절
    /// 클릭할 때 오른쪽 인스펙터에서의 연구문서 클릭과 동일한 기능)."
    /// `BibleReadingView.handleVerseMentionSelected`(그 파일 참고 — "관련
    /// 콘텐츠" 패널에서 연구문서를 고르면 `document-search` 창을 검색어와 함께
    /// 연다)와 정확히 같은 메커니즘을 여기서도 그대로 쓴다. 개별 결과가 어떤
    /// 단어들로 일치했는지는 `result.highlightKeywords`(복수)로 갈려 있어
    /// `DocumentSearchRequest.searchText`(단수 String) 한 자리에 그대로 넣을 수
    /// 없으므로, "뷰어의 검색어로 입력"이라는 요청 문구 그대로 사용자가 입력한
    /// 검색창 문자열 자체(`viewModel.query`)를 넘긴다.
    private var documentSearchText: String {
        viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
                DocumentSearchWindowContent(
                    request: DocumentSearchRequest(documentID: result.document.persistentModelID, searchText: documentSearchText)
                )
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
                openWindow(
                    id: "document-search",
                    value: DocumentSearchRequest(documentID: result.document.persistentModelID, searchText: documentSearchText)
                )
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
