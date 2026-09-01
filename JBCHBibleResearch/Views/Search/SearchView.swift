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
#if os(macOS)
import AppKit
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

/// [2026-08-27 신설] 위 `SearchContentView`의 `.navigationDestination(for:
/// BibleVerseDestination.self)` 등록 위치 주석 참고 — 아이폰에서만 이 등록을
/// 끄기 위한 조건부 modifier. `CircularNavButtonModifier(isCircular:)`
/// (BibleReadingView.swift)와 같은 "isEnabled 플래그를 받는 ViewModifier" 패턴을
/// 그대로 따랐다.
private struct BibleVerseDestinationRegistration: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.navigationDestination(for: BibleVerseDestination.self) { destination in
                BibleReadingView(
                    initialBook: BooksProvider.shared.book(id: destination.bookId),
                    initialChapter: destination.chapter,
                    initialVerse: destination.verse
                )
            }
        } else {
            content
        }
    }
}

/// [2026-08-29 신설] `BibleReadingView`의 동명 타입(그 파일 참고)과 똑같은
/// 얇은 `Identifiable` 래퍼 — "세 번째 사용처가 생기기 전엔 공통 타입으로
/// 추출하지 않는다"는 이 프로젝트의 기존 원칙(`SearchViewModel.storeCache`
/// 상단 주석 참고)에 따라 이 파일 전용으로 따로 둔다. 한자 주석 필드는 여기서는
/// 두지 않았다(`VerseTextSelectionPopover.hanjaWords`가 기본값 `[]`을
/// 지원하므로 생략해도 정상 동작 — 그 파일 상단 주석 참고).
private struct PartialTextSelectionTarget: Identifiable {
    let id = UUID()
    let verseNumber: Int
    let translationDisplayName: String
    let text: String
}

private struct SearchContentView: View {
    let viewModel: SearchViewModel
    // [2026-08-07 추가] S6이 별도 창으로 바뀌면서(JBCHBibleResearchApp.swift
    // "document-viewer" WindowGroup 참고) 검색결과의 문서 진입점도 새 창을 연다.
    @Environment(\.openWindow) private var openWindow
    // [2026-08-27 추가] 사용자 보고 — "아이폰 통합검색: 검색결과중 성경구절을
    // 탭하면 성경조회로 이동해야 정상인데 이동을 안 하고, 대신 빈 통합검색
    // 화면(검색하기 전 상태)이 뜬다. 뒤로가기를 누르면 그제서야 아까 그
    // 성경구절이 성경조회 화면에 나온다." 검색을 제출하는 시점(`.onSubmit(of:
    // .search)`)에 이 액션을 호출해 검색 활성 상태를 종료시킨다(Apple 문서가
    // "탐색하기 전에 검색을 종료해야 할 때 호출" 용도로 명시).
    @Environment(\.dismissSearch) private var dismissSearch

    /// [2026-08-29 신설] "선택" 버튼(`verseRowActionButtons`)이 채우는 팝오버
    /// 대상 — `BibleReadingView.partialTextSelectionTarget`과 같은 역할.
    @State private var partialTextSelectionTarget: PartialTextSelectionTarget?

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

    /// [2026-08-27, 여러 차례 시도 끝에 최종 확정 — 사용자 결정 "개요→더보기,
    /// 검색→탭바"] 처음엔 이 화면 안에서 `NavigationLink(value:)`로 그 자리에서
    /// 바로 `BibleVerseDestination`을 push하려 했는데, 검색이 "활성" 상태인
    /// 채로 같은 화면에서 바로 push하는 조합 자체가 구조적으로 깨진다는 것을
    /// 세 번의 실기기 콘솔 로그로 확인했다(탭과 동시에 dismiss → 전환 충돌;
    /// dismiss 안 함 → 검색 활성 상태로 넘어감 경고; 이 화면을 pop한 뒤 push →
    /// 이 화면이 "더보기" 서브메뉴에 중첩돼 있던 탓에 탭 선택 상태 자체가
    /// 꼬여 엉뚱한 탭으로 튐). 근본 원인은 이 화면이 "더보기"라는 다른
    /// 화면 안에 중첩돼 있었다는 것 — `SearchView`가 `PhoneTabView`의 정식
    /// 탭(자기 자신만의 독립된 `NavigationStack`)으로 승격되면서 이 문제
    /// 자체가 성립하지 않게 됐다.
    ///
    /// 그래서 이제 아이폰에서는 이 6곳(성경구절/메모/인물·지명/예언/주제·속성/
    /// 서사)에서 이 화면 안에서 직접 push하지 않고, 사이드바 "최근 이력"
    /// 항목 탭(`BibleVerseNavigationRequest.swift` 상단 주석 참고)과 완전히
    /// 같은 방식 — "성경" 탭으로 전환(`AppNavigationRequest`)하고, 이미 그
    /// 자리에 떠 있는 `BibleReadingView`에게 목표 좌표를 전달
    /// (`BibleVerseNavigationRequest`)한다. 이 화면 자신은 pop되지도, 상태를
    /// 잃지도 않는다 — 다른 탭들과 똑같이 `TabView`가 계속 살려 둔다.
    ///
    /// macOS/iPadOS(`SidebarNavigationView`)는 이 문제가 보고되지 않았으므로
    /// 손대지 않고 그대로 `NavigationLink(value:)`를 쓴다. `Button`은 List
    /// 행에서 시스템 디스클로저 화살표(`>`)를 자동으로 그려주지 않으므로,
    /// `NavigationLink`와 같은 모양을 유지하기 위해 오른쪽 끝에 같은 스타일의
    /// 화살표를 직접 그린다.
    @ViewBuilder
    private func bibleVerseRow<RowLabel: View>(
        _ destination: BibleVerseDestination,
        @ViewBuilder label: () -> RowLabel
    ) -> some View {
        if isPhoneIdiom {
            Button {
                AppNavigationRequest.shared.request(.bibleReading)
                // [2026-08-27] `BibleVerseNavigationTarget.verse`는 옵셔널이
                // 아니다(사이드바 "최근 이력"은 항상 특정 절을 가리킨다) —
                // 이 화면의 메모(VersePhraseNote) 결과처럼 절이 없는 경우
                // (`BibleVerseDestination.verse == nil`)는 그 장의 1절로
                // 대체한다. `BibleReadingView`의 `initialVerse == nil` 기본
                // 동작(장의 시작 부분을 보여줌)과 사실상 같은 결과다.
                BibleVerseNavigationRequest.shared.request(
                    bookId: destination.bookId,
                    chapter: destination.chapter,
                    verse: destination.verse ?? 1
                )
            } label: {
                HStack(spacing: 8) {
                    label()
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: destination) {
                label()
            }
        }
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
            // 위 `dismissSearch` 선언부 주석 참고 — 검색 결과가 이미 화면에
            // 나오는 조건(`resultsSection`)은 `viewModel.query`(실제 검색어)
            // 텍스트에만 달려 있고 이 "검색 활성" 상태와는 무관해서, 여기서
            // 종료해도 결과 표시엔 영향이 없다.
            dismissSearch()
        }
        // [2026-08-26 신설, 2026-08-27 아이폰 전용 예외로 변경] `BibleVerseDestination.
        // swift` 상단 주석 참고 — 이 화면 안의 성경 조회 이동 링크 6곳(성경구절/
        // 메모/인물·지명/예언/주제·속성/서사)을 전부 값 기반 `NavigationLink(value:)`로
        // 바꾸면서, 그 값을 실제 화면으로 바꿔주는 목적지 등록이 필요해졌다. 원래는
        // 이 화면을 담는 `NavigationStack`이 macOS/iPadOS(`SidebarNavigationView`,
        // `path:` 바인딩 보유)와 iPhone(`PhoneTabView`의 "더보기" 탭) 둘로 갈려서,
        // 호스트 쪽에 각각 등록하는 대신 이 화면 자신에 등록해 두 플랫폼 모두에서
        // 동작하게 했었다.
        //
        // [2026-08-27 변경, 사용자 실기기 재현 중 Xcode 콘솔 로그로 원인 확정]
        // "아이폰 통합검색 결과를 탭해도 반응이 없거나, 아주 가끔 탭이 되도 검색
        // 화면이 다시 뜬다"는 신고를 재현하는 도중 콘솔에 "A navigationDestination
        // for 'BibleVerseDestination' was declared earlier on the stack. Only the
        // destination declared closest to the root view of the stack will be
        // used."가 반복 출력됐다 — 애플이 명시한 대로, 같은 스택 안에 이 타입의
        // `.navigationDestination`이 두 곳에 등록돼 있으면 "스택 루트에 더
        // 가까운 쪽"만 실제로 쓰이고 나머지는 조용히 무시된다. 이 화면
        // (`SearchContentView`)은 `.searchable`이 붙은 `List`라, 검색이 아직
        // 활성 상태인 채로 `NavigationLink(value:)`가 push되면 iOS가 검색
        // 결과를 별도 경로로 호스팅하면서 이 화면 자신의 modifier 체인이
        // 스택 안에 실질적으로 두 번(원본 인스턴스 + 검색 호스팅용 인스턴스)
        // 나타나는 것으로 보인다 — 아이패드/맥도 같은 `.searchable`을 쓰지만
        // 이 증상은 보고되지 않았고, 재현도 전부 아이폰(`PhoneTabView`)에서만
        // 됐다. 그래서 아이폰에서만 이 화면 자신에 등록하는 것을 껐다.
        //
        // [2026-08-27 재변경, 사용자 결정 — "개요→더보기, 검색→탭바"] 처음엔
        // 등록 위치를 `PhoneTabView`의 "더보기" 탭(`MorePlaceholderView`, 그
        // 당시 통합 검색이 그 안에 중첩돼 있었다)의 스택 루트로 옮기는
        // 방식으로 고쳤었다. 하지만 그 구조에서 검색 결과를 탭하면 이번엔
        // "A navigation item is losing its active search controller with
        // visible search bar..." 경고와 함께 엉뚱한 탭으로 튀는 증상이
        // 새로 발견됐고, 세 차례의 실기기 콘솔 로그로 "`.searchable`이 활성인
        // 화면에서 그 자리에 push하는 조합" 자체가 근본적으로 못 고치는
        // 구조적 결함임이 확인됐다. 그래서 등록 위치를 다시 옮기는 대신
        // "통합 검색"을 `PhoneTabView`의 독립된 최상위 탭으로 승격하고,
        // 아이폰에서는 `bibleVerseRow`(아래)가 `NavigationLink(value:)`/
        // `.navigationDestination`을 아예 쓰지 않고 `AppNavigationRequest`+
        // `BibleVerseNavigationRequest`로 "성경" 탭에 이미 떠 있는
        // `BibleReadingView`에 메시지만 보내는 방식으로 바꿨다 — push 자체가
        // 없으니 이 등록을 아이폰의 다른 어느 곳으로도 옮길 필요가 없어졌다.
        // macOS/iPadOS(`SidebarNavigationView`)는 여전히 `NavigationLink(value:)`를
        // 직접 쓰므로 기존 그대로 이 화면 자신의 등록을 계속 쓴다(그쪽은 이
        // 화면이 스택의 유일한 "루트에 가장 가까운" 목적지 등록이라 원래도
        // 문제가 없었다).
        .modifier(BibleVerseDestinationRegistration(isEnabled: !isPhoneIdiom))
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
        // [2026-08-29 신설] "선택" 버튼 — `TranslationColumnView`/`BibleReadingView`가
        // 성경조회 화면에서 쓰는 것과 정확히 같은 `VerseTextSelectionPopover`를
        // 그대로 띄운다(상단 `verseRowActionButtons` 주석 참고).
        .popover(item: $partialTextSelectionTarget) { target in
            VerseTextSelectionPopover(
                verseNumber: target.verseNumber,
                translationDisplayName: target.translationDisplayName,
                text: target.text,
                onCopy: { text in
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    #else
                    UIPasteboard.general.string = text
                    #endif
                }
            )
        }
        // [2026-08-26 신설] 사용자 요청 — "두 개 단어 이상 검색시 더보기를
        // 누르면 확인창 - 각 성경별로 추가 검색결과를 반영했으니 확인해보라는
        // 내용." AskUserQuestion으로 확정: 확인창은 검색 1회당 최초 1번만,
        // "확인"을 누르면 그냥 닫히고 더보기가 정상 진행된다 —
        // `SearchViewModel.confirmMoreResultsNotice()` 참고. `.alert(item:) ->
        // Alert`는 iOS 15/macOS 12부터 deprecated라(`Text + Text` 연산자를
        // deprecated로 피한 것과 같은 이유, `verseExcerptAttributedString`
        // 주석 참고) 대신 현재 권장되는
        // `.alert(_:isPresented:presenting:actions:message:)`를 쓴다.
        .alert(
            "추가 검색결과 안내",
            isPresented: Binding(
                get: { viewModel.pendingMoreResultsNotice != nil },
                set: { if !$0 { viewModel.dismissMoreResultsNotice() } }
            ),
            presenting: viewModel.pendingMoreResultsNotice
        ) { _ in
            Button("확인") {
                viewModel.confirmMoreResultsNotice()
            }
        } message: { notice in
            Text("구약·신약 성경책 \(notice.additionalBookCount)권에 걸쳐 추가 검색결과가 반영되었습니다. 확인해보세요.")
        }
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
                bibleVerseRow(BibleVerseDestination(
                    bookId: first.bookId, chapter: first.chapter, verse: first.verse
                )) {
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
                bibleVerseRow(BibleVerseDestination(
                    bookId: first.bookId, chapter: first.chapter, verse: first.verse
                )) {
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
                bibleVerseRow(BibleVerseDestination(
                    bookId: first.bookId, chapter: first.chapter, verse: first.verse
                )) {
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
                bibleVerseRow(BibleVerseDestination(
                    bookId: first.bookId, chapter: first.chapter, verse: first.verse
                )) {
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
            // [2026-08-26 수정] 사용자 요청 — "성경 검색 결과가 장별로
            // 그룹핑되고, 그 같은 장안에 절이 세부적으로 표시될 수 있도록."
            // 예전엔 `verseResults`(가중치 랭킹 순서)를 그대로 평평하게
            // 나열했다 — 이제 `SearchViewModel.groupedVerseResults`가 그
            // 순서는 건드리지 않은 채(랭킹/더보기 페이지네이션은 여전히
            // `verseResults` 기준) 화면 표시용으로만 장 단위 그룹(정경순 고정,
            // 사용자 확인 사항)을 만들어 준다.
            ForEach(viewModel.groupedVerseResults) { group in
                verseChapterGroupHeader(group)
                ForEach(group.verses) { result in
                    groupedVerseRow(result)
                }
            }
            // [2026-08-25 신설, 2026-08-26 100개로 확대] 사용자 요청 — "limit
            // 50을 해제할 수 있는 방법도 추가할 것 — 더보기 버튼." /
            // "검색결과를 100개 단위로 보여줄것." `SearchViewModel.searchVerses`가
            // 이제 매칭된 절 전체를 성경순으로 갖고 있다가 화면엔 100개씩만
            // 보여준다(`SearchViewModel.verseResultPageSize`) — 이 버튼을
            // 누르면 DB를 다시 조회하지 않고 이미 메모리에 있는 다음 100개를
            // 더 보여준다.
            if viewModel.hasMoreVerseResults {
                Button {
                    viewModel.loadMoreVerseResults()
                } label: {
                    HStack {
                        Spacer()
                        Label("더보기 (\(viewModel.allVerseResults.count - viewModel.verseResults.count)개 남음)", systemImage: "chevron.down.circle")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.indigo)
                .padding(.vertical, 6)
            }
        } header: {
            sectionHeader("성경구절", icon: "book.closed.fill", color: .indigo, count: viewModel.allVerseResults.count)
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

    /// [2026-08-26 신설, 같은 날 재작성] "성경구절" 섹션 안에서 장 단위
    /// 그룹을 나누는 헤더. 사용자 요청 — "수정하기 전에 아이콘의 크기와
    /// 성경 장절의 형태를 유지하되 성경장절 대신 성경장만 표시." "수정하기
    /// 전"이 가리키는 화면(스크린샷)은 실은 `rowLabel`(제목 줄 + `categoryIcon`
    /// 아이콘 칩, 개요/메모 등 다른 분류 행과 같은 스타일)로 그려지던 예전
    /// `verseRow`였다 — 그래서 아이콘은 그 함수가 쓰는 `categoryIcon`(34×34
    /// 원형 배지)을 그대로 재사용하고, 제목 폰트도 `rowLabel`의 제목과 같은
    /// `.body.weight(.semibold)`로 맞췄다. 내용만 "책 D:V"(절 번호 포함) 대신
    /// "책 D장"(장만)으로 바꿨다 — 이 헤더 하나가 그 장에 속한 여러 절
    /// (`groupedVerseRow`)을 대표하므로 특정 절 번호를 넣을 이유가 없다.
    private func verseChapterGroupHeader(_ group: SearchViewModel.VerseSearchResultGroup) -> some View {
        HStack(spacing: 10) {
            categoryIcon("book.closed.fill", color: .indigo)
            Text("\(group.bookNameKo) \(group.chapter)장")
                .font(.body.weight(.semibold))
                .lineLimit(1)
            Spacer()
            Text("\(group.verses.count)절")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
    }

    /// [2026-08-26 재작성] 사용자 요청 — "그 아래 절 표시된 내용에 1절) ....
    /// 3절) .... 이렇게 그루핑." 장 헤더(`verseChapterGroupHeader`)가 이미
    /// 책+장을 보여주므로, 이 행에서는 그걸 반복하지 않고 "N절)" 접두어 +
    /// 본문만 보여준다(예시 그대로 — "17절) 그 이웃 여인들이..."). 예전
    /// `verseRow`가 쓰던 `rowLabel`(제목 줄 + 아이콘 칩 + 왼쪽 정렬 발췌)은
    /// 이 배치와 맞지 않아 이 함수 전용으로 따로 그린다.
    private func groupedVerseRow(_ result: VerseSearchResult) -> some View {
        // [2026-08-19 추가] 사용자 요청 — "검색 결과중 - 성경구절을 클릭하면
        // 해당하는 절까지 스크롤 이동해서 잠시 하이라이트 표시해줄것."
        // [2026-08-26 변경] 클로저 기반 NavigationLink { BibleReadingView(...) }는
        // `SidebarNavigationView.detailNavigationPath`(NavigationPath)에
        // 전혀 기록되지 않아 "다시 검색해도 pop이 안 되는" 버그의 원인이었다
        // — `BibleVerseDestination.swift` 상단 주석 참고. 값 기반으로 교체.
        //
        // [2026-08-29 변경] 사용자 요청 — "각 행 오른쪽(단어 일치개수 뱃지
        // 왼쪽)에 이동/선택/복사 버튼 추가." 이 세 버튼이 생기면서 "행 전체를
        // 탭하면 이동"하던 기존 동작(`bibleVerseRow`)은 없앴다 — AskUserQuestion으로
        // 확인: 한 List 행 안에 여러 인터랙티브 컨트롤(행 전체 탭 + 버튼 3개)이
        // 공존하면 SwiftUI가 실제로 탭된 게 어느 것인지 안정적으로 구분하지
        // 못하는 문제가 `OutlineTreeView.swift`(장 칩 여러 개를 `List` 행
        // 하나에 몰아넣었을 때, 그 파일 상단 주석 참고)에서 이미 실제로
        // 재현된 적이 있어 같은 위험을 피했다. "이동"은 이제 아래 버튼이
        // 전담한다.
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verseExcerptAttributedString(result))
                .lineLimit(2)
            if result.isReferenceMatch {
                badge("참조 일치", color: .green, systemImage: "checkmark.seal.fill")
            }
            Spacer(minLength: 8)
            verseRowActionButtons(result)
            // [2026-08-26 추가] 사용자 요청 — "각 절마다 몇개 매칭되었는지
            // 오른쪽 끝에다 표시해줄것." 참조 매치는 `matchCount`가 항상
            // 0이라(`VerseSearchResult.matchCount` 상단 주석 참고) 배지
            // 자체를 숨긴다 — "0회"라고 보여주는 것보다 아예 안 보이는
            // 편이 "이건 단어 매칭이 아니라 정확한 참조로 찾아온 절"이라는
            // 뜻을 더 분명히 전달한다.
            if result.matchCount > 0 {
                verseMatchCountBadge(result.matchCount)
            }
        }
        .padding(.vertical, 4)
    }

    /// [2026-08-29 신설] 사용자 요청 — "검색결과 - 성경구절 각 행 오른쪽 옆
    /// (단어 일치개수 뱃지 왼쪽)에 버튼 추가 — 이동, 선택, 복사." 셋 다 이
    /// 앱에 이미 있는 기능을 그대로 재사용한다(새로 설계하지 않음):
    /// - 이동: `BibleReadingView`가 사이드바 "최근 이력" 등 다른 화면에서
    ///   넘어올 때 이미 쓰는 것과 정확히 같은 `AppNavigationRequest`(성경
    ///   섹션으로 전환) + `BibleVerseNavigationRequest`(그 절 하이라이트)
    ///   조합이다. 이 조합은 `SidebarNavigationView.swift`의
    ///   `.onChange(of: AppNavigationRequest.shared.requestedSection)`가
    ///   플랫폼(아이폰 탭 vs 아이패드·맥 사이드바) 구분 없이 처리하므로,
    ///   여기서도 분기 없이 버튼 하나로 만든다.
    /// - 선택: `TranslationColumnView`의 컨텍스트 메뉴("선택")와 똑같이
    ///   `VerseTextSelectionPopover`를 띄운다. 한자 주석(`hanjaWords`)은
    ///   그 팝오버 자체가 기본값 `[]`을 지원하도록 설계돼 있어(그 파일 상단
    ///   주석 참고) 생략한다 — 한자 조회에 필요한 `BibleReadingViewModel`
    ///   의존성 없이도 정상 동작한다.
    /// - 복사: `BibleReadingView.copySingleTranslation`과 정확히 같은
    ///   패턴 — `BibleVerseCopyFormatter.format`에 번역본을 이 절 하나만
    ///   담아 넘긴다("다른 번역본 제외, 검색에 나온 번역본만" 요청과 일치 —
    ///   포매터의 `showTranslationLabel = translations.count > 1` 로직이
    ///   1개일 땐 번역본 이름표도 자동으로 뺀다). 설정(`UserSettingsStore`의
    ///   복사 형식)은 `BibleVerseCopyFormatter`가 알아서 반영한다.
    private func verseRowActionButtons(_ result: VerseSearchResult) -> some View {
        HStack(spacing: 14) {
            Button {
                AppNavigationRequest.shared.request(.bibleReading)
                BibleVerseNavigationRequest.shared.request(
                    bookId: result.bookId, chapter: result.chapter, verse: result.verse
                )
            } label: {
                Image(systemName: "arrow.right.circle")
            }
            .help("이동")

            Button {
                partialTextSelectionTarget = PartialTextSelectionTarget(
                    verseNumber: result.verse,
                    translationDisplayName: result.translationDisplayName,
                    text: result.content
                )
            } label: {
                Image(systemName: "character.cursor.ibeam")
            }
            .help("선택")

            Button {
                copySearchResult(result)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("복사")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .font(.system(size: 14))
    }

    /// 위 `verseRowActionButtons`의 "복사" 버튼 — `BibleReadingView.
    /// copySingleTranslation`과 동일한 패턴(그 함수 참고), 번역본 하나만
    /// (`result.translationDisplayName`) 담아 포맷하고 클립보드에 쓴다.
    private func copySearchResult(_ result: VerseSearchResult) {
        guard let book = BooksProvider.shared.book(id: result.bookId) else { return }
        let verse = BibleVerse(
            uid: 0, versionCode: result.translationCode, bookId: result.bookId,
            chapter: result.chapter, verse: result.verse, content: result.content, paragraph: nil
        )
        guard let text = BibleVerseCopyFormatter.format(
            book: book, chapter: result.chapter, selectedVerses: [result.verse],
            translations: [BibleVerseCopyFormatter.TranslationSnapshot(
                displayName: result.translationDisplayName, verses: [verse]
            )]
        ) else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    /// "N절) 강조된 본문" 하나로 합친 `AttributedString` — `Text + Text`(별도
    /// 폰트 유지 목적)는 macOS 26에서 deprecated됐다(`VerseZoomView.
    /// hanjaGlossCell` fix와 같은 이유). 대신 접두어와 강조된 본문을 하나의
    /// `AttributedString`으로 합쳐(Foundation의 `+`, deprecated 아님) 단일
    /// `Text(_:)`로 감싼다.
    ///
    /// [2026-08-26 수정] 사용자 요청 — "그 밑에 절들이 수정하기 전 스타일대로
    /// 여러 절들이 나타나게." 본문(`body`) 색을 `.primary` → `.secondary`로
    /// 되돌렸다 — 예전 `verseRow`가 쓰던 `rowLabel`의 발췌 텍스트가
    /// `.subheadline` + `.secondary`였다(`rowLabel`의 `highlightedText(...)
    /// .foregroundStyle(.secondary)` 호출부 참고). "N절)" 접두어는 이번에
    /// 새로 추가된 요소라 "이전 스타일"의 대상이 아니므로 굵게(semibold) 그대로
    /// 두되, 장 헤더와 마찬가지로 기본(primary) 색을 명시해 톤을 분명히 했다.
    private func verseExcerptAttributedString(_ result: VerseSearchResult) -> AttributedString {
        var prefix = AttributedString("\(result.verse)절) ")
        prefix.font = .subheadline.weight(.semibold)
        prefix.foregroundColor = .primary
        var body = highlightedAttributedString(result.content, keywords: result.highlightKeywords)
        body.font = .subheadline
        body.foregroundColor = .secondary
        return prefix + body
    }

    /// "각 절마다 몇 개 매칭되었는지 오른쪽 끝" 배지 — `occurrenceChip`(다른
    /// 분류가 발췌 "왼쪽"에 쓰는 "N회 일치" 캡슐)과 비슷한 스타일이되, 이
    /// 행에서는 오른쪽 끝에 붙는 용도라 별도 함수로 뒀다.
    ///
    /// [2026-08-26 문구 정정] 사용자 요청 — "각 성경구절 표시 옆에 [단어가
    /// 일치된 숫자]가 아니라 중복제거된 매칭 검색어수를 나타낼 것." 값
    /// 자체는 이미 `VerseSearchResult.matchCount`가 `matchedWordCount`(중복
    /// 제거된 매칭 검색어 수)를 담도록 고쳤으므로(그 필드 상단 주석 참고),
    /// 여기 문구도 "N회"(등장 횟수처럼 읽힘) → "N단어"(몇 개의 서로 다른
    /// 단어가 일치했는지)로 바꿔 값의 의미와 라벨이 어긋나지 않게 했다.
    private func verseMatchCountBadge(_ count: Int) -> some View {
        let color = verseMatchCountBadgeColor(count)
        return Text("\(count)단어")
            .font(.caption2.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
            .fixedSize()
    }

    /// [2026-08-26 신설] 사용자 요청 — "뱃지 색상 디자인을 서로 다른 단어
    /// 수마다 다르게 할것. 1회 - 회색 / 2회 - 초록색 / 3회 - 파란색 / 4회 -
    /// 황금색 / 5회 - 주황색 / 6회이상 - 빨간색." 요청 문구의 "회"는 이
    /// 배지가 보여주는 "N단어"(중복 제거된 매칭 검색어 수, `matchCount` 상단
    /// 주석 참고)를 가리키는 것으로 해석했다 — 바로 이전 정정(11장)에서
    /// "회"라는 표현 자체가 등장 횟수로 오해받기 쉬워 라벨을 "N단어"로
    /// 바꿨었지만, 값 자체는 그대로이므로 색상 매핑 대상도 이 값이 맞다.
    /// SwiftUI 표준 `Color`엔 "황금색(gold)"이 따로 없어 근사 RGB로 정의했다.
    private func verseMatchCountBadgeColor(_ count: Int) -> Color {
        switch count {
        case 1: return .gray
        case 2: return .green
        case 3: return .blue
        case 4: return Color(red: 0.83, green: 0.69, blue: 0.22)   // 황금색(gold) 근사값
        case 5: return .orange
        default: return .red   // 6 이상 (0 이하는 호출부가 `matchCount > 0`일 때만 부르므로 실질적으로 발생하지 않음)
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
        bibleVerseRow(BibleVerseDestination(
            bookId: result.note.bookId, chapter: result.note.chapter, verse: nil
        )) {
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
            // [2026-08-27 변경] `WordNoteHomeView.destinationView`의 같은 변경과
            // 같은 이유 — 사용자가 보고한 "말씀노트 화면이 아이폰 가로폭보다
            // 커서 잘림" 버그가 `.standalone` 헤더(BookChapterPicker+Stepper를
            // 한 줄에 다 넣고 줄바꿈하지 않음) 자체에 있어, 이 검색 결과 진입
            // 경로도 같은 헤더를 그대로 쓰는 한 아이폰에서 똑같이 잘린다 —
            // 이미 검색으로 찾은 특정 요약이라 좌표를 바꿀 이유도 없어(위
            // `WordNoteHomeView`와 같은 논리) `.wordNoteList`로 바꾼다.
            WordSummaryEditorView(summary: result.summary, presentationContext: .wordNoteList)
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
        Text(highlightedAttributedString(text, keywords: keywords))
    }

    /// [2026-08-26 추출] 기존 `highlightedText`의 하이라이트 계산 로직을
    /// `AttributedString`을 반환하는 형태로 분리했다 — `groupedVerseRow`의
    /// `verseExcerptAttributedString(_:)`가 "N절)" 접두사와 하나의
    /// `AttributedString`으로 이어붙이려면(= 하나의 `Text(_:)`로 감싸려면)
    /// `Text`가 아닌 `AttributedString`이 필요하기 때문이다(SwiftUI의
    /// `Text + Text` 연산자는 deprecated — 상단 참고). 로직 자체는 옮기기만
    /// 했을 뿐 한 글자도 바꾸지 않았으므로 `highlightedText`의 기존 5곳
    /// 호출부 동작은 전부 그대로다.
    private func highlightedAttributedString(_ text: String, keywords: [String]) -> AttributedString {
        let trimmedKeywords = keywords.filter { !$0.isEmpty }
        var attributed = AttributedString(text)
        guard !trimmedKeywords.isEmpty else { return attributed }

        for keyword in trimmedKeywords {
            var searchRange = text.startIndex..<text.endIndex
            while let found = text.range(of: keyword, options: [.caseInsensitive], range: searchRange) {
                if let attrRange = Range(found, in: attributed) {
                    attributed[attrRange].backgroundColor = .yellow.opacity(0.5)
                }
                searchRange = found.upperBound..<text.endIndex
            }
        }
        return attributed
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
