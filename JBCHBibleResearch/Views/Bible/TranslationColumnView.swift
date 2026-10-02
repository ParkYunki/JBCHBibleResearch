//
//  TranslationColumnView.swift
//  JBCHBibleResearch
//
//  S1(성경 조회)의 컬럼 하나(번역본 하나)를 그린다. 이 뷰는 리더 역할(사용자가 실제로
//  스크롤 중일 때 화면 중앙 절을 ScrollSyncCoordinator에 보고)과 팔로워 역할(다른
//  컬럼이 리더일 때 좌표를 받아 자신을 그 절로 스크롤)을 동시에 수행한다.
//
//  스크롤 동기화 정의: 모든 컬럼의 뷰포트 정중앙에 항상 같은 절 번호가 오도록 맞춘다.
//  `centerVerseID`(anchor: .center)가 이 "가운데 기준선" 역할이다.
//  구현은 `ScrollView.scrollPosition(id:anchor:)`(iOS17/macOS14+)이며, id를 매기는
//  LazyVStack에 `.scrollTargetLayout()`을 반드시 붙여야 바인딩이 갱신된다.
//

import SwiftUI
import BibleResearchModels
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct TranslationColumnView: View {
    let columnID: UUID
    let translationDisplayName: String
    /// 이 번역본 자신의 언어로 표시하는 "책 장" 레이블(예: "John 3"). BookNameTableProvider가
    /// 계산한 값을 표시만 하며, 책/장이 바뀌면 문자열도 바뀌므로 장 변경 신호로도 쓴다
    /// (`resetForChapterChange` 참고).
    var localizedBookChapterLabel: String? = nil
    let verses: [BibleVerse]
    let errorDescription: String?
    var highlightedVerse: Int?
    var onSelectVerse: (BibleVerse) -> Void = { _ in }
    /// 절 클릭 → 컨텍스트 메뉴 → 메모 작성(S3, 정확한 좌표 미리 채워짐).
    var onCreateMemo: (BibleVerse) -> Void = { _ in }
    /// 컨텍스트 메뉴 [복사] — 이 컬럼(번역본) 하나의 절만 넘긴다. 포매팅·클립보드 접근·토스트는
    /// 호출부(`BibleReadingView`)의 책임이다(하단 액션바의 다중 절/다중 번역본 복사와 별개).
    var onCopySingleTranslation: (BibleVerse, String) -> Void = { _, _ in }
    /// 컨텍스트 메뉴 [선택] — 절 하나 + 번역본 이름만 넘기고, 부분 텍스트 선택 팝오버 표시는
    /// 호출부의 책임이다(`VerseTextSelectionPopover` 참고).
    var onSelectPartialText: (BibleVerse, String) -> Void = { _, _ in }
    /// 클립보드 복사용 다중 선택 — 같은 절 번호는 어느 컬럼에서도 같은 절이므로 절 번호 기준으로
    /// 모든 컬럼이 공유한다. `BibleReadingViewModel.selectedVerses` 참고.
    var selectedVerses: Set<Int> = []
    /// 일반 클릭(수식키 없음) — 선택을 교체한다. `onToggleVerseSelection`은 개별 다중 선택(토글) 전용.
    var onSelectSingleVerse: (Int) -> Void = { _ in }
    var onToggleVerseSelection: (Int) -> Void = { _ in }
    /// Shift/Cmd 클릭 — 마지막 기준 절부터 이 절까지 범위 선택. `BibleReadingViewModel.extendVerseSelection(to:)` 참고.
    var onExtendVerseSelection: (Int) -> Void = { _ in }

    let coordinator: ScrollSyncCoordinator
    /// false면 팔로워 응답(`respondToSyncEvent`)을 끈다. 아이폰은 `TabView` 페이징이라 한 번에 컬럼
    /// 하나만 보이므로 `BibleReadingView.phoneColumns`에서만 false로 넘긴다(리더 보고는 유지, 페이지
    /// 전환 시 `pendingCenterAlignment`로 한 번만 맞춘다).
    var respondsToSyncEvents: Bool = true
    /// 아이폰 스와이프 정렬 전용 — 부모가 "이 컬럼을 이 절로 맞춰라"라고 1회성으로 넘기는 값.
    /// nil이 아닌 새 값이 들어올 때마다 애니메이션 없이 즉시 반영한다.
    var pendingCenterAlignment: Int? = nil
    /// 아이폰에서 표시 중인 번역본이 하나뿐이면 맞춰 줄 페이지가 없으므로 `reportCenterVerseIfNeeded`가
    /// 보고를 생략하게 하는 값. `respondsToSyncEvents == false`(아이폰)일 때만 참조한다.
    var hasAdditionalDisplayedColumns: Bool = true

    /// 구간 주석(형광펜/표시/관주/구간메모) provider들. 이 뷰는 이미 걸러진 데이터를 그리기만 하고,
    /// 필터링은 상위(`BibleReadingContentView`)가 맡는다.
    /// ⚠️ 프로퍼티 선언 순서 = memberwise init 인자 순서이므로 호출부(BibleReadingView.swift)와
    /// 반드시 같은 순서로 둬야 한다.
    var highlightsProvider: (Int) -> [VerseHighlight] = { _ in [] }
    var crossReferencesProvider: (Int) -> [VerseCrossReference] = { _ in [] }
    var phraseMemosProvider: (Int) -> [UserMemo] = { _ in [] }
    /// 드래그 표현 부연설명 "메모" — `phraseMemosProvider`와 같은 원칙.
    var phraseNotesProvider: (Int) -> [VersePhraseNote] = { _ in [] }
    /// 난외주(단어 뜻풀이/구약 인용 출처) — 관주와 같은 자리에 아이콘으로 노출한다.
    var marginalNotesProvider: (Int) -> [VerseMarginalNote] = { _ in [] }
    /// 절 단위 한자 주석. 표시 방식(끄기/탭하면 보기/항상 보기)은 전역 설정이라
    /// `VerseRow`가 `UserSettingsStore.hanjaDisplayMode`를 직접 읽는다.
    var hanjaWordsProvider: (Int) -> [HanjaWordAnnotation] = { _ in [] }
    /// "관련 내용" — 이 절을 언급하는 메모/연구문서가 있으면 절 번호 아래에 세 번째 아이콘으로 노출한다.
    var verseMentionsProvider: (Int) -> [VerseMention] = { _ in [] }
    /// 절 단위 책갈피 여부. 실제 구현은 `BibleReadingViewModel.isVerseBookmarked(_:)`.
    var isBookmarkedProvider: (Int) -> Bool = { _ in false }
    /// 장 전체 책갈피 여부. 절마다 다시 물을 필요가 없어 클로저가 아니라 값 하나로 받는다
    /// (`BibleReadingViewModel.isChapterBookmarked`).
    var isChapterBookmarked: Bool = false
    /// 관주 팝오버에서 대상 구절을 탭했을 때 — 그 책/장으로 이동한다(정확한 절 위치 스크롤은 범위 밖).
    var onSelectCrossReferenceTarget: (BibleVerseRef) -> Void = { _ in }
    /// 구간 메모 아이콘에서 메모를 골랐을 때 — 기존 "메모 작성" 시트를 그대로 연다.
    var onSelectPhraseMemo: (UserMemo) -> Void = { _ in }
    /// "관련 내용" 목록에서 항목을 골랐을 때 — 메모는 편집기 시트, 연구문서는 PDF 검색+이동 창으로
    /// 연다(호출부 책임).
    var onSelectVerseMention: (VerseMention) -> Void = { _ in }
    /// 인라인 한자/난외주 `AttributedString` 생성. 캐싱(`BibleReadingViewModel.cachedInlineAnnotatedContent`)은
    /// 상위가 맡고 이 뷰는 결과만 받는다. 기본값은 캐싱 없이 `VerseAnnotationRenderer`를 바로 부른다.
    var inlineAnnotatedContentProvider: (
        BibleVerse, [VerseHighlight], [VersePhraseNote], [HanjaWordAnnotation], [VerseMarginalNote],
        PlatformFont, PlatformColor, PlatformFont?
    ) -> AttributedString = { verse, highlights, phraseNotes, hanjaWords, marginalNotes, font, textColor, hanjaFont in
        VerseAnnotationRenderer.attributedContentWithInlineAnnotations(
            text: verse.content, highlights: highlights, phraseNotes: phraseNotes,
            hanjaWords: hanjaWords, marginalNotes: marginalNotes, font: font, textColor: textColor, hanjaFont: hanjaFont
        )
    }
    /// 장 끝(마지막 절 아래)에 붙일 이전 장/다음 장 이동 + 장 개인 묵상 버튼. nil이면 붙이지 않는다.
    /// 여러 컬럼을 나란히 볼 때는 호출부가 첫 컬럼에만 넘긴다. ⚠️ 이 아래 두 값과 함께 마지막에 선언해야 호출부 인자 순서와 맞는다.
    var chapterEndActions: ChapterEndActions? = nil
    /// "본문에서 찾기"(⌘F)에서 이 컬럼에 일치한 절 번호와, 지금 보고 있는 일치 절. 비어 있으면 기존 모습 그대로다.
    var findMatchVerses: Set<Int> = []
    var currentFindVerse: Int? = nil

    /// 지금 뷰포트 중앙(anchor: .center)에 있는 절 번호 — `.scrollPosition(id:)`가 스크롤에 맞춰
    /// 읽어 주고(리더), 값을 대입하면 그 절이 중앙에 오도록 스크롤한다(팔로워).
    @State private var centerVerseID: Int?
    /// 이 컬럼 자신이 팔로워로서 프로그램적으로 스크롤하는 중인지 — 그 사이에는
    /// `centerVerseID` 변경을 리더 보고로 착각해 되돌려 보고하지 않는다(안 그러면
    /// 팔로워가 스스로를 리더로 착각해 무한 루프에 빠질 수 있다).
    @State private var isProgrammaticScroll = false
    /// `.scrollPosition(id:anchor:)`의 anchor를 `.center`로 강제하는 플래그. 평소엔 anchor를 nil로 둬
    /// 레이아웃 변화(절 선택/해제, 한자 표시 등)마다 재중앙정렬되며 화면이 튀는 것을 막고,
    /// `centerVerseID`에 대입해 특정 절로 스크롤시키는 순간(번역본 동기화, 검색 결과 이동, 최초 진입
    /// 하이라이트, 아이폰 스와이프 정렬, 장 변경 리셋)에만 켠다. anchor가 nil이면 대입만 되고
    /// 실제 스크롤은 정중앙까지 가지 않는다.
    @State private var forceCenterAnchorForProgrammaticScroll = false
    /// `respondToSyncEvent`가 예약한 가드 해제 작업을 취소할 수 있도록 보관한다.
    @State private var guardReleaseWorkItem: DispatchWorkItem?
    /// `forceCenterAnchorTemporarily()`가 예약한 플래그 해제 작업을 취소·재예약하기 위해 보관한다.
    /// `guardReleaseWorkItem`(팔로워 반복 응답 방지)과는 별개 목적이라 독립적으로 관리한다.
    @State private var centerAnchorReleaseWorkItem: DispatchWorkItem?
    /// `scrollToHighlightedVerseAfterLayout`의 지연 재시도를 최신 요청 하나만 유효하게 만드는 토큰.
    @State private var highlightScrollToken = 0

    /// 가드/플래그 해제 시각을 애니메이션 지속 시간과 맞추기 위한 상수. `respondToSyncEvent`의
    /// `withAnimation` duration과 반드시 같은 값을 써야 한다.
    private static let scrollAnimationDuration: TimeInterval = 0.25

    /// 절 목록 맨 아래의 추가 스크롤 여백(pt). 절을 선택하면 화면 하단에 뜨는 액션바가 마지막 절을 가리므로, 장 끝까지
    /// 스크롤했을 때 마지막 절을 액션바 위로 올려 볼 수 있게 한다. 선택 여부와 무관한 고정값이라 절을 선택/해제해도
    /// 스크롤 콘텐츠 높이가 변하지 않는다(높이가 변하면 재중앙정렬로 화면이 튄다).
    private static let bottomBufferPadding: CGFloat = 40

    /// 아이폰 전용 보고 디바운스 간격. 아이폰은 중앙 절 보고를 실시간 구독하는 곳이 없고(소비처는
    /// 페이지 스와이프 순간의 마지막 값 한 번뿐), 빠른 스크롤 중 매 프레임 보고하면 메인 스레드
    /// Observation 갱신이 렌더링과 겹치므로, 스크롤이 멈출 때까지 기다렸다 마지막 값만 보고한다.
    /// macOS/iPadOS(`respondsToSyncEvents == true`)는 실시간 동기화에 쓰이므로 즉시 보고한다.
    private static let phoneReportDebounceInterval: TimeInterval = 0.15
    @State private var phoneReportWorkItem: DispatchWorkItem?

    /// 아이폰은 시스템 내비게이션 바(`BibleReadingContentView.toolbarContent`의 `.principal`)가 이미
    /// 번역본/책/장을 보여주므로 컬럼 제목 영역을 숨긴다. 맥/아이패드는 여러 컬럼을 나란히 보여줘
    /// 번역본 구분용으로 필요하다. `BibleReadingContentView.isPhone`과 같은 패턴.
    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isPhone {
                // 책/장은 위 "성경 이동 툴"(`BookChapterPicker.standardBody`)이 이미 보여주므로 컬럼 제목에는
                // 번역본 이름만 그린다. `localizedBookChapterLabel`은 장 변경 감지에 쓰이므로 프로퍼티는 남긴다.
                VStack(alignment: .leading, spacing: 2) {
                    Text(translationDisplayName)
                        .font(.headline)
                        .foregroundStyle(settings.bibleTextColor ?? .secondary)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }

            if let errorDescription {
                ContentUnavailableMessage(errorDescription)
            } else if verses.isEmpty {
                ContentUnavailableMessage("이 장에 표시할 절이 없습니다.")
            } else {
                columnScrollView
            }
        }
        // 장 북마크 세로선은 컬럼 전체(제목+본문) 배경으로 그려 맨 위부터 끝까지 이어지게 한다.
        // `.overlay`가 아니라 `.background`라 본문/제목 뒤에 깔린다.
        .background(alignment: .leading) {
            if isChapterBookmarked {
                // 상단이 컬럼 맨 위까지 닿으므로 `ChapterBookmarkRibbonShape`의 상단은 각진 사각형이다.
                ChapterBookmarkRibbonShape()
                    .fill(JBCHCategoryPalette.wine)
                    .frame(width: 10)
            }
        }
        // 배경색 테마. `bibleBackgroundColor`가 nil이면 Color.clear로 시스템 기본(라이트/다크 자동)을
        // 유지하고, 값이 있으면 컬럼 전체(헤더+본문)에 칠한다.
        .background(settings.bibleBackgroundColor ?? Color.clear)
    }

    /// 설정 저장소 접근(절 간격 `bibleVerseSpacing` 등). `VerseRow`는 private struct라 자체 `settings`를
    /// 따로 갖고 있어 이 struct에도 하나 둔다.
    private var settings: UserSettingsStore { .shared }

    /// `Color`에는 `.tertiary`가 없어(`ShapeStyle`에만 있음) `Color?`와 `??`로 합칠 수 없으므로,
    /// 시스템 3차 레이블 색(라이트/다크 자동)을 `Color`로 직접 감싼다.
    private var systemTertiaryTextColor: Color {
        #if os(iOS)
        Color(uiColor: .tertiaryLabel)
        #else
        Color(nsColor: .tertiaryLabelColor)
        #endif
    }

    @ViewBuilder
    private var columnScrollView: some View {
        // ⚠️ 아이폰 스크롤 버벅임의 원인은 절 내용이 아니라 `.scrollPosition(id:anchor:)`/
        // `.scrollTargetLayout()`의 실시간 중앙 추적이었다(이 둘만 꺼도 매끄러워짐). 이 추적이 필요한 곳은
        // macOS/아이패드의 실시간 다중 번역본 동기화(`respondsToSyncEvents == true`)뿐이라 그쪽은
        // `columnScrollViewSyncTracking`, 아이폰은 실시간 추적 없이 1회성 이동만 하는
        // `columnScrollViewPhoneLightweight`를 쓴다.
        if respondsToSyncEvents {
            columnScrollViewSyncTracking
        } else {
            columnScrollViewPhoneLightweight
        }
    }

    /// macOS/아이패드 전용. 리더/팔로워 실시간 스크롤 동기화가 필요한 유일한 경로라
    /// `.scrollPosition(id:anchor:)` 기반이다. 행 구성은 `verseRowView(for:)`를 아이폰 쪽과 공유한다.
    private var columnScrollViewSyncTracking: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: CGFloat(settings.bibleVerseSpacing)) {
                ForEach(verses, id: \.verse) { verse in
                    verseRowView(for: verse)
                }
                // id가 없는 마지막 항목이라 `.scrollPosition(id:)` 추적 대상에는 들어가지 않는다.
                if let chapterEndActions {
                    ChapterEndFooterView(actions: chapterEndActions)
                }
            }
            // `.scrollPosition(id:anchor:)`가 anchor 지점 항목의 id를 추적하려면 id를 매기는 컨테이너
            // (이 LazyVStack)를 `.scrollTargetLayout()`으로 표시해야 한다. 빠뜨리면 바인딩이 갱신되지 않는다.
            .scrollTargetLayout()
            .padding()
            .padding(.bottom, Self.bottomBufferPadding)
        }
        // anchor는 `forceCenterAnchorForProgrammaticScroll`이 켜진 짧은 순간에만 `.center`, 그 외엔 nil이다.
        // 절 선택/해제 시 강제 재중앙정렬로 화면이 튀는 것을 막으면서, 프로그램적 스크롤은 정중앙까지
        // 가게 하기 위함이다(그 플래그 선언부 참고).
        .scrollPosition(id: $centerVerseID, anchor: forceCenterAnchorForProgrammaticScroll ? .center : nil)
        // 이 화면이 처음 만들어질 때 이미 `highlightedVerse`가 채워진 경우(예: 검색 결과 탭으로
        // `BibleReadingView`가 새로 생성). `.onChange(of: highlightedVerse)`는 최초 값에 반응하지 않으므로
        // `.onAppear`에서 애니메이션 없이 맞춘다.
        .onAppear {
            if let highlightedVerse {
                // ⚠️ 이 시점엔 LazyVStack이 아직 배치되기 전이라 `centerVerseID` 대입만으로는 macOS에서
                // 스크롤이 일어나지 않는다. 배치 이후 `proxy.scrollTo`를 지연 재시도한다.
                scrollToHighlightedVerseAfterLayout(highlightedVerse, proxy: proxy, animated: false)
            }
        }
        .onChange(of: centerVerseID) { _, newValue in
            reportCenterVerseIfNeeded(newValue)
        }
        // 아이폰(`respondsToSyncEvents == false`)에서는 이 구독 자체를 붙이지 않는다.
        // `coordinator.latestEvent`는 다른 컬럼이 리더일 때도 바뀌므로, 안에서 return만 해도 화면에 안 보이는
        // 다른 번역본 페이지(`TabView(.page)`)의 body까지 매번 재계산돼 빠른 스크롤 시 낭비가 쌓인다.
        .modifier(SyncEventSubscriptionModifier(
            isEnabled: respondsToSyncEvents,
            coordinator: coordinator,
            onEvent: respondToSyncEvent
        ))
        // 아이폰 스와이프 정렬 — 부모가 새 값을 넘기면 애니메이션 없이 즉시 그 절로 맞춘다
        // (탭 전환 자체가 전환 애니메이션).
        .onChange(of: pendingCenterAlignment) { _, newValue in
            guard let newValue else { return }
            forceCenterAnchorTemporarily()
            centerVerseID = newValue
        }
        // `highlightedVerse`가 설정되면(검색 결과 탭 등) 그 절로 스크롤한다. 강조 배경은
        // `VerseRow.isHighlighted`, 자동 해제 타이머는 `BibleReadingViewModel.highlightVerseTemporarily`가 맡는다.
        .onChange(of: highlightedVerse) { _, newValue in
            guard let newValue else { return }
            scrollToHighlightedVerseAfterLayout(newValue, proxy: proxy, animated: true)
        }
        // 책/장이 바뀌면 이전 장의 중앙 절 id를 그대로 들고 있지 않도록 리셋한다. 안 그러면 새 장에 같은
        // 절 번호가 있을 때 `.scrollPosition(id:)`가 그 번호로 다시 스크롤해 새 장을 맨 위부터 보여주는
        // 동작과 어긋난다.
        .onChange(of: localizedBookChapterLabel) { _, _ in
            resetForChapterChange()
        }
        } // ScrollViewReader
    }

    /// 아이폰 전용. `.scrollPosition`/`.scrollTargetLayout()` 없이 `ScrollViewReader.scrollTo`(호출 시점
    /// 1회 이동)로 검색 이동/장 리셋/페이지 스와이프 정렬을 구현한다. "현재 중앙 절"은 각 절이 뷰포트에
    /// 나타나는 순간(`.onAppear`)의 값으로 근사한다(정확한 중앙이 아니라 마지막으로 화면에 들어온 절).
    /// 페이지 전환 시 대략 그 근처로 맞추는 용도엔 충분하고 스크롤 중 실시간 비용이 없다.
    private var columnScrollViewPhoneLightweight: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: CGFloat(settings.bibleVerseSpacing)) {
                    ForEach(verses, id: \.verse) { verse in
                        verseRowView(for: verse, onRowAppear: { reportCenterVerseIfNeeded($0) })
                    }
                    if let chapterEndActions {
                        ChapterEndFooterView(actions: chapterEndActions)
                    }
                }
                .padding()
                .padding(.bottom, Self.bottomBufferPadding)
            }
            .onAppear {
                if let highlightedVerse {
                    // ⚠️ `proxy.scrollTo` 실행 중 스크롤 경로 절들의 `.onAppear`(`onRowAppear`)가 연쇄로 발생하는데,
                    // 이를 사용자가 스크롤한 것으로 오인해 `reportCenterVerseIfNeeded`가 재보고하면 페이지를 넘길 때마다
                    // 한 절씩 밀린다. 그래서 프로그램적 스크롤 직전에 `beginProgrammaticScrollPhone()`으로
                    // `isProgrammaticScroll` 가드를 켠다.
                    beginProgrammaticScrollPhone()
                    proxy.scrollTo(highlightedVerse, anchor: .center)
                }
            }
            .onChange(of: pendingCenterAlignment) { _, newValue in
                guard let newValue else { return }
                beginProgrammaticScrollPhone()
                proxy.scrollTo(newValue, anchor: .center)
            }
            .onChange(of: highlightedVerse) { _, newValue in
                guard let newValue else { return }
                beginProgrammaticScrollPhone()
                withAnimation(.easeInOut(duration: Self.scrollAnimationDuration)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
            .onChange(of: localizedBookChapterLabel) { _, _ in
                resetForChapterChangePhone(proxy: proxy)
            }
        }
    }

    /// 절 한 행 구성(VerseRow + 탭/컨텍스트 메뉴 + 난외주 목록) — 두 플랫폼 공통.
    /// `onRowAppear`는 아이폰 쪽(`columnScrollViewPhoneLightweight`)만 넘긴다.
    @ViewBuilder
    private func verseRowView(for verse: BibleVerse, onRowAppear: ((Int) -> Void)? = nil) -> some View {
        // 난외주 목록을 `VerseRow` 카드 안에서 선택 시에만 펼치면 카드 높이가 변해
        // `.scrollPosition(anchor: .center)` 보정으로 절 텍스트가 밀리므로 카드 밖 형제 항목으로 뺀다.
        // 한 번만 계산해 `VerseRow`와 그 형제 항목이 같은 값을 공유한다.
        let marginalNotes = marginalNotesProvider(verse.verse)
        let row = VerseRow(
            verse: verse,
            isHighlighted: verse.verse == highlightedVerse,
            isFindMatch: findMatchVerses.contains(verse.verse),
            isCurrentFindMatch: verse.verse == currentFindVerse && findMatchVerses.contains(verse.verse),
            isSelected: selectedVerses.contains(verse.verse),
            isBookmarked: isBookmarkedProvider(verse.verse),
            highlights: highlightsProvider(verse.verse),
            crossReferences: crossReferencesProvider(verse.verse),
            phraseMemos: phraseMemosProvider(verse.verse),
            phraseNotes: phraseNotesProvider(verse.verse),
            marginalNotes: marginalNotes,
            hanjaWords: hanjaWordsProvider(verse.verse),
            verseMentions: verseMentionsProvider(verse.verse),
            onSelectCrossReferenceTarget: onSelectCrossReferenceTarget,
            onSelectPhraseMemo: onSelectPhraseMemo,
            onSelectVerseMention: onSelectVerseMention,
            inlineAnnotatedContentProvider: inlineAnnotatedContentProvider
        )
            .id(verse.verse)
            // macOS 탭 동작: 일반 클릭 = 선택 교체, Shift/Cmd 클릭 = 범위 선택, Option 클릭 = 개별 토글.
            // Control 클릭은 macOS가 컨텍스트 메뉴(아래 `.contextMenu`)로 먼저 가로챌 수 있어 쓰지 않는다.
            // 수식키는 `NSEvent.modifierFlags`를 읽기만 하므로 손쉬운 사용(접근성) 권한이 필요 없다.
            .onTapGesture {
                onSelectVerse(verse)
                #if os(macOS)
                let flags = NSEvent.modifierFlags
                if flags.contains(.shift) || flags.contains(.command) {
                    onExtendVerseSelection(verse.verse)
                } else if flags.contains(.option) {
                    onToggleVerseSelection(verse.verse)
                } else {
                    onSelectSingleVerse(verse.verse)
                }
                #else
                // iOS/iPadOS는 수식키 신호가 없어 탭 한 번으로 선택/해제를 토글한다(macOS의 Option+클릭과 같은
                // 의미, 다른 절 선택은 유지). macOS 분기는 수식키 기반 3단 구분을 그대로 둔다.
                onToggleVerseSelection(verse.verse)
                #endif
            }
            .contextMenu {
                Button {
                    onCreateMemo(verse)
                } label: {
                    // 확대보기 액션바와 같은 절 전체 메모(UserMemo, rangeStart 없음)를 만드는 경로라 이름을 맞춘다.
                    Label("개인 묵상 작성", systemImage: "square.and.pencil")
                }
                // [선택] — 번역본 안에서 일부 텍스트만 골라 복사한다. 실제 드래그 선택은
                // `VerseTextSelectionPopover`(호출부가 여는 팝오버/시트)에서 이뤄진다.
                Button {
                    onSelectPartialText(verse, translationDisplayName)
                } label: {
                    Label("선택", systemImage: "character.cursor.ibeam")
                }
                // [복사] — 이 컬럼 번역본의 절만 복사한다(`onCopySingleTranslation` 참고).
                Button {
                    onCopySingleTranslation(verse, translationDisplayName)
                } label: {
                    Label("복사", systemImage: "doc.on.doc")
                }
            }

        // 아이폰 전용 절 등장 보고. `onRowAppear`가 없으면(macOS/아이패드) 추가 modifier 없이 그대로 그린다.
        if let onRowAppear {
            row.onAppear { onRowAppear(verse.verse) }
        } else {
            row
        }

        // 난외주 목록을 `VerseRow` 카드 밖 별도 형제 항목으로 둔다. `VerseRow`(`.id(verse.verse)`)는 선택
        // 여부와 무관하게 높이가 일정해 중앙 정렬 대상이어도 밀리지 않는다. 이 목록은 자신만의 `.id`를 가진다.
        if selectedVerses.contains(verse.verse), !marginalNotes.isEmpty {
            MarginalNoteFootnoteList(notes: marginalNotes)
                .id("\(verse.verse)-marginalNotes")
        }
    }

    /// 리더 역할 — 지금 중앙 절을 코디네이터에 보고한다. 프로그램적(팔로워) 스크롤 중에는 건너뛴다.
    /// macOS/아이패드는 `.onChange(of: centerVerseID)`에서, 아이폰은 각 절 등장 시(`onRowAppear`)
    /// 그 절 번호로 직접 호출한다.
    private func reportCenterVerseIfNeeded(_ verse: Int?) {
        guard !isProgrammaticScroll, let verse else { return }
        // macOS/아이패드는 즉시 보고하고, 아이폰은 아래에서 디바운스한다.
        guard !respondsToSyncEvents else {
            coordinator.reportCenterVerse(verse, columnID: columnID)
            return
        }
        // 맞춰 줄 다른 컬럼(페이지)이 없으면 디바운스 예약 없이 생략한다.
        guard hasAdditionalDisplayedColumns else { return }
        phoneReportWorkItem?.cancel()
        let workItem = DispatchWorkItem { [coordinator, columnID] in
            coordinator.reportCenterVerse(verse, columnID: columnID)
        }
        phoneReportWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.phoneReportDebounceInterval, execute: workItem)
    }

    /// 팔로워 역할 — 다른 컬럼(리더)이 보고한 절로 이 컬럼도 맞춰 스크롤한다.
    private func respondToSyncEvent(_ event: ScrollSyncCoordinator.SyncEvent?) {
        guard let event, event.sourceColumnID != columnID else { return }
        let available = verses.map(\.verse)
        guard let target = coordinator.resolveTargetVerse(for: event.verse, availableVerses: available) else { return }
        guard target != centerVerseID else { return }

        // 이전에 예약한 가드 해제 작업이 아직 실행 전이면 취소하고 재예약한다. 동기화 이벤트가 애니메이션
        // 지속 시간보다 짧은 간격으로 연달아 오면(빠른 스크롤 등) 먼저 예약된 타이머가 진행 중인 애니메이션
        // 도중에 가드를 풀어 팔로워가 스스로를 리더로 착각하는 경합이 생길 수 있어, 마지막 애니메이션이
        // 끝난 뒤에만 풀리게 한다.
        guardReleaseWorkItem?.cancel()

        isProgrammaticScroll = true
        forceCenterAnchorForProgrammaticScroll = true
        withAnimation(.easeInOut(duration: Self.scrollAnimationDuration)) {
            centerVerseID = target
        }
        let releaseWorkItem = DispatchWorkItem {
            isProgrammaticScroll = false
            forceCenterAnchorForProgrammaticScroll = false
        }
        guardReleaseWorkItem = releaseWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scrollAnimationDuration, execute: releaseWorkItem)
    }

    /// `centerVerseID`에 대입해 특정 절로 스크롤시키는 호출부(검색 결과 탭·최초 진입 하이라이트·
    /// 아이폰 스와이프 정렬·장 변경 리셋)의 공통 절차. 대입 직전에 `forceCenterAnchorForProgrammaticScroll`을
    /// 켜 anchor를 잠깐 `.center`로 만들고 `scrollAnimationDuration` 뒤 자동으로 끈다(계속 켜 두면
    /// 레이아웃 변경마다 재중앙정렬되어 화면이 튄다). `respondToSyncEvent`는 팔로워 반복 응답 방지
    /// 가드와 얽혀 있어 자체 타이머를 쓴다.
    private func forceCenterAnchorTemporarily() {
        forceCenterAnchorForProgrammaticScroll = true
        centerAnchorReleaseWorkItem?.cancel()
        let releaseWorkItem = DispatchWorkItem {
            forceCenterAnchorForProgrammaticScroll = false
        }
        centerAnchorReleaseWorkItem = releaseWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scrollAnimationDuration, execute: releaseWorkItem)
    }

    /// macOS/아이패드 전용. 검색 결과 이동 등으로 `highlightedVerse`가 채워질 때 그 절을 화면 중앙으로 스크롤한다.
    /// 장이 바뀌거나 화면이 새로 만들어진 직후에는 LazyVStack 배치가 끝나기 전이라 `.scrollPosition(id:)` 대입만으로는
    /// 스크롤이 무시되므로, (1) 즉시 대입 + (2) 배치 이후 `ScrollViewProxy.scrollTo`를 짧은 간격으로 재시도한다.
    /// `highlightScrollToken`으로 더 새로운 요청이 오면 이전 재시도를 무효화한다(`@State`는 참조 저장이라 클로저에서도 최신값).
    private func scrollToHighlightedVerseAfterLayout(_ verse: Int, proxy: ScrollViewProxy, animated: Bool) {
        highlightScrollToken += 1
        let token = highlightScrollToken
        forceCenterAnchorTemporarily()
        if animated {
            withAnimation(.easeInOut(duration: Self.scrollAnimationDuration)) {
                centerVerseID = verse
            }
        } else {
            centerVerseID = verse
        }
        for delay in [0.08, 0.3, 0.7] as [TimeInterval] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard highlightScrollToken == token else { return }
                forceCenterAnchorTemporarily()
                proxy.scrollTo(verse, anchor: .center)
            }
        }
    }

    private func resetForChapterChange() {
        guardReleaseWorkItem?.cancel()
        // 장이 바뀌는 순간 이전 장의 디바운스된 보고가 뒤늦게 나가 새 장의 첫 스크롤 위치를 흔들지
        // 않도록 예약된 작업을 취소한다.
        phoneReportWorkItem?.cancel()
        isProgrammaticScroll = false
        // 관주/검색 결과로 "장 이동 + 특정 절 강조"가 동시에 일어나면(`highlightedVerse`가 이미 최종값)
        // 여기서 첫 절로 되돌릴 경우 곧이어 맞출 스크롤이 무효화될 수 있어 리셋을 건너뛴다.
        // `.onChange(of: highlightedVerse)`가 올바른 절로 맞추며, 두 onChange의 실행 순서와 무관하게 안전하다.
        guard highlightedVerse == nil else { return }
        // `.scrollPosition(id:)`에 nil을 대입해서는 "1절로 스크롤"이 일어나지 않아 이전 장의 스크롤
        // 오프셋이 남을 수 있으므로 구체적인 절 번호를 대입한다. 하드코딩된 1 대신 실제 첫 절
        // (`verses.first?.verse`)을 쓰고, anchor가 nil이면 스크롤되지 않으므로 임시로 `.center`를 강제한다.
        forceCenterAnchorTemporarily()
        centerVerseID = verses.first?.verse
    }

    /// 아이폰 전용 `resetForChapterChange()` — `.scrollPosition` 바인딩이 없어 `proxy.scrollTo`로
    /// 직접 1절까지 이동한다.
    private func resetForChapterChangePhone(proxy: ScrollViewProxy) {
        guardReleaseWorkItem?.cancel()
        phoneReportWorkItem?.cancel()
        isProgrammaticScroll = false
        guard highlightedVerse == nil else { return }
        if let firstVerse = verses.first?.verse {
            // `proxy.scrollTo`가 유발하는 연쇄 `.onAppear`의 재보고를 막는다(`beginProgrammaticScrollPhone` 참고).
            beginProgrammaticScrollPhone()
            proxy.scrollTo(firstVerse, anchor: .center)
        }
    }

    /// 아이폰 전용. `proxy.scrollTo`가 유발하는 연쇄 `.onAppear`를 사용자 스크롤로 잘못 보고하지 않도록
    /// 프로그램적 스크롤 직전에 `isProgrammaticScroll` 가드를 켠다(`scrollAnimationDuration` 뒤 자동 해제).
    /// `reportCenterVerseIfNeeded` 맨 위의 `guard !isProgrammaticScroll`이 이 가드를 참조한다.
    private func beginProgrammaticScrollPhone() {
        guardReleaseWorkItem?.cancel()
        phoneReportWorkItem?.cancel()
        isProgrammaticScroll = true
        let releaseWorkItem = DispatchWorkItem {
            isProgrammaticScroll = false
        }
        guardReleaseWorkItem = releaseWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scrollAnimationDuration, execute: releaseWorkItem)
    }
}

/// 장 책갈피 세로선의 리본 도형. 배경으로 붙으므로 받는 `rect`의 높이는 스크롤 내용 전체가 아니라
/// 화면에 보이는 높이이며, 하단 V자 노치는 스크롤 위치와 무관하게 항상 화면 맨 아래에 그려진다.
/// 하단 가운데를 `notchDepth`만큼 위로 파고들게 잘라 좌우 두 갈래(리본 꼬리)로 가른다.
private struct ChapterBookmarkRibbonShape: Shape {
    /// 하단 V자 노치 깊이. 값이 클수록 노치가 깊어 꼭짓점 각도가 좁아진다. 막대 폭(10pt)에 맞춘
    /// 값이라 폭이 바뀌면 함께 조정해야 비율이 어색해지지 않는다.
    var notchDepth: CGFloat = 6

    /// 상단은 직선(사각형), 하단은 V자 노치 모양의 경로.
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        // 뷰 높이가 노치보다 작아지는 극단적인 경우(레이아웃 계산 중 순간적으로 작은 높이가 배정될 때)
        // 노치가 상단까지 파고들지 않도록 상한을 둔다.
        let notch = max(0, min(notchDepth, h))

        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: w, y: 0))
        path.addLine(to: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: w / 2, y: h - notch))
        path.addLine(to: CGPoint(x: 0, y: h))
        path.closeSubpath()
        return path
    }
}

/// `isEnabled`가 false(아이폰)면 `.onChange(of:)`를 붙이지 않아
/// `coordinator.latestEvent`가 바뀔 때마다 body가 재계산되는 것을 막는다.
/// true(macOS/iPadOS)면 매번 구독해 `onEvent`를 호출한다.
private struct SyncEventSubscriptionModifier: ViewModifier {
    let isEnabled: Bool
    let coordinator: ScrollSyncCoordinator
    let onEvent: (ScrollSyncCoordinator.SyncEvent?) -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.onChange(of: coordinator.latestEvent) { _, event in
                onEvent(event)
            }
        } else {
            content
        }
    }
}

/// 난외주 각주 목록 — 절 선택 여부와 무관하게 `VerseRow` 카드 높이가 고정되도록 별도 형제
/// 뷰로 분리했다. 본문 위첨자와 같은 번호(`note.markerText`, 원본 `<SUP>` 글자
/// 그대로)를 나열한다.
private struct MarginalNoteFootnoteList: View {
    let notes: [VerseMarginalNote]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                Text("\(note.markerText ?? "") \(note.noteText)")
                    .font(.system(size: 14))
                    // 같은 절 행의 다른 요소와 같은 `bibleTextColor` 폴백 체인을 따른다.
                    .foregroundStyle(UserSettingsStore.shared.bibleTextColor?.opacity(0.75) ?? Color.secondary)
            }
        }
        // 절 번호 칸(`VerseRow`의 `.frame(minWidth: 20)` + HStack
        // spacing 8)만큼 들여써 본문 시작 위치와 대략 맞춘다.
        .padding(.leading, 28)
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
    }
}

private struct VerseRow: View {
    let verse: BibleVerse
    let isHighlighted: Bool
    /// "본문에서 찾기" 일치 절 여부 / 그중 지금 보고 있는 절 — `isHighlighted`(이동 대상 임시 강조)와 별개다.
    var isFindMatch: Bool = false
    var isCurrentFindMatch: Bool = false
    /// 클립보드 복사용으로 선택된 절인지 — `isHighlighted`(검색 결과 이동 대상 표시)와는
    /// 별개 개념이다.
    let isSelected: Bool
    /// 이 절을 정확히 가리키는 책갈피가 있는지 — 있으면 절 번호 칸 아래에 책갈피 아이콘을 그린다.
    var isBookmarked: Bool = false
    /// 이 절(이 컬럼의 번역본 기준)에 걸린 구간 주석 — 이미 필터링된 상태로 들어온다.
    var highlights: [VerseHighlight] = []
    var crossReferences: [VerseCrossReference] = []
    var phraseMemos: [UserMemo] = []
    /// 드래그 표현 부연설명 메모 — 형광펜과 같은 원칙으로 이미 필터링된 상태로 들어온다.
    var phraseNotes: [VersePhraseNote] = []
    /// 난외주(단어 뜻풀이/구약 인용 출처) — 관주와 같은 원칙.
    var marginalNotes: [VerseMarginalNote] = []
    /// 절 단위 한자 주석.
    var hanjaWords: [HanjaWordAnnotation] = []
    /// "관련 내용" — 관주/메모와 같은 원칙.
    var verseMentions: [VerseMention] = []
    var onSelectCrossReferenceTarget: (BibleVerseRef) -> Void = { _ in }
    var onSelectPhraseMemo: (UserMemo) -> Void = { _ in }
    var onSelectVerseMention: (VerseMention) -> Void = { _ in }
    /// 캐시되는 인라인 주석 조립 클로저 — `verseContentText`가 사용한다.
    var inlineAnnotatedContentProvider: (
        BibleVerse, [VerseHighlight], [VersePhraseNote], [HanjaWordAnnotation], [VerseMarginalNote],
        PlatformFont, PlatformColor, PlatformFont?
    ) -> AttributedString = { verse, highlights, phraseNotes, hanjaWords, marginalNotes, font, textColor, hanjaFont in
        VerseAnnotationRenderer.attributedContentWithInlineAnnotations(
            text: verse.content, highlights: highlights, phraseNotes: phraseNotes,
            hanjaWords: hanjaWords, marginalNotes: marginalNotes, font: font, textColor: textColor, hanjaFont: hanjaFont
        )
    }

    @State private var isCrossReferencePopoverPresented = false
    @State private var isMarginalNotePopoverPresented = false
    @State private var isVerseMentionPopoverPresented = false

    // 환경설정 "모양" 탭의 본문 크기/색상/절 번호 크기/줄간격/글꼴을 반영한다.
    // `@Observable`이라 설정이 바뀌면 이 행도 다시 그려진다.
    private var settings: UserSettingsStore { .shared }

    var body: some View {
        // 배경/테두리/선택 표시줄은 이 바깥 `VStack`에 적용한다.
        VStack(alignment: .leading, spacing: 4) {
            // `.firstTextBaseline` 정렬 — `.top`은 두 뷰의 프레임 윗변만 맞춰, 작은
            // 폰트의 절 번호 뱃지와 큰 폰트 본문의 글자 시작 높이가 어긋난다. 베이스라인 정렬은 폰트 메트릭
            // 기준이라 글꼴 크기가 달라도 자연스럽게 맞는다.
            //
            // 절 번호 칸(아래 `VStack`)의 첫 자식이 뱃지 `Text`이므로 이 정렬 기준은 그
            // `Text`의 베이스라인을 따른다.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
            // 책갈피는 높이를 지정하지 않은 세로선이 행 높이 계산을 키워 다음 절과 겹치는 것으로 보여, 세로선
            // 대신 절 번호 아래 고정 크기 아이콘으로 표시한다. 메모/관주 아이콘도 절 번호 아래에 세로로 쌓아
            // 본문이 쓸 가로 폭을 확보한다.
            VStack(alignment: .center, spacing: 3) {
                // 절 번호 뱃지 — 현재 테마의 배경/글자색 쌍을 뒤집어 쓴다(뱃지 배경 =
                // `bibleTextColor`, 숫자 = `bibleBackgroundColor`). WCAG 대비
                // 비율은 두 색의 순서와 무관해 테마별로 검증된 대비가 유지되고, 별도 매핑이 필요 없다.
                //
                // 두 값 다 사용자가 고르지 않았을 때(시스템 기본)만 `JBCHCategoryPalette.navy`
                // + 흰 숫자로 대체한다.
                Text("\(verse.verse)")
                    .font(settings.bibleVerseNumberFont.weight(.semibold))
                    .foregroundStyle(settings.bibleBackgroundColor ?? .white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .frame(minWidth: 20)
                    .background(
                        settings.bibleTextColor ?? JBCHCategoryPalette.navy,
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )

                // 책갈피 아이콘 — 위 HStack 주석 참고. 절 번호 뱃지에 살짝 겹치도록 음수 top 패딩으로
                // 끌어올린다.
                if isBookmarked {
                    Image(systemName: "bookmark.fill")
                        .font(.caption2)
                        .foregroundStyle(JBCHCategoryPalette.wine)
                        .padding(.top, -4)
                }

                // 관주 마커 — `Text(AttributedString)`은 구간별 탭 제스처를 따로 걸 수 없어
                // 본문 글자 사이에 끼울 수 없다. 대신 절 번호 아래 아이콘으로 연결 구절 확인/이동을 제공한다.
                if !crossReferences.isEmpty {
                    Button {
                        isCrossReferencePopoverPresented = true
                    } label: {
                        Image(systemName: "link.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(settings.bibleTextColor ?? .secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $isCrossReferencePopoverPresented) {
                        crossReferencePopoverContent
                    }
                }

                // 난외주 마커 — 관주 아이콘과 같은 이유로 같은 자리에 아이콘을 둔다.
                if !marginalNotes.isEmpty {
                    Button {
                        isMarginalNotePopoverPresented = true
                    } label: {
                        Image(systemName: "asterisk.circle")
                            .font(.caption2)
                            .foregroundStyle(settings.bibleTextColor ?? .secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $isMarginalNotePopoverPresented) {
                        marginalNotePopoverContent
                    }
                }

                if !phraseMemos.isEmpty {
                    Menu {
                        ForEach(phraseMemos) { memo in
                            Button(phraseMemoLabel(memo)) { onSelectPhraseMemo(memo) }
                        }
                    } label: {
                        Image(systemName: "note.text")
                            .font(.caption2)
                            .foregroundStyle(settings.bibleTextColor ?? .secondary)
                    }
                    .buttonStyle(.plain)
                }

                // 한자 주석은 이 칸의 아이콘이 아니라 절 선택 상태(`isSelected`)로
                // 제어한다(`shouldShowInlineHanja`/`verseContentText` 참고). 한자
                // 뜻(훈음)은 확대보기(`VerseZoomView`)의 "한자 뜻풀이" 영역에서 본다.

                // "관련 내용" 아이콘 — 관주/메모 아이콘 아래에 쌓는다.
                if !verseMentions.isEmpty {
                    Button {
                        isVerseMentionPopoverPresented = true
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.caption2)
                            .foregroundStyle(settings.bibleTextColor ?? .secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $isVerseMentionPopoverPresented) {
                        VerseMentionListView(mentions: verseMentions) { mention in
                            isVerseMentionPopoverPresented = false
                            onSelectVerseMention(mention)
                        }
                    }
                }
            }
            .frame(minWidth: 20)

            verseContentText
                .lineSpacing(settings.bibleLineSpacing)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            // 난외주 목록은 절 선택 시 카드 높이를 바꿔 절 텍스트가 밀리는 문제가 있어, 이 카드 밖의 형제
            // 항목(`MarginalNoteFootnoteList`)으로
            // 분리했다(`TranslationColumnView.columnScrollView`의 `ForEach`
            // 참고).
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        // `.clipShape` 대신 `.background(_:in:)`으로 합쳐 별도 클립 레이어를
        // 줄인다(스크롤 성능). ⚠️ `.clipShape`는 내용까지 잘라냈지만 이 카드의 내용은 위
        // `.padding`으로 이미 안쪽에 있어 시각적으로 동일해야 한다.
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            // 지금 보고 있는 찾기 일치 절은 배경만으로는 여러 일치 사이에서 구분되기 어려워 테두리를 더한다.
            if isCurrentFindMatch {
                RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.9), lineWidth: 1.5)
            }
        }
        .overlay(alignment: .leading) {
            // 배경 틴트만으로는 라이트 모드에서 눈에 잘 안 띌 수 있어, 선택된
            // 절에는 왼쪽에 강조색 세로선을 하나 더 그어 명확히 한다.
            if isSelected {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color("AccentColor"))
                    .frame(width: 3)
                    .padding(.vertical, 2)
            }
        }
    }

    /// 한자 인라인 표시 여부 — "항상 보기"는 전부, "탭하면 보기"는 이 절이 선택된
    /// 경우(`isSelected` 재사용)만, "끄기"는 항상 false.
    private var shouldShowInlineHanja: Bool {
        guard !hanjaWords.isEmpty else { return false }
        switch settings.hanjaDisplayMode {
        case .alwaysInline: return true
        case .tapToReveal: return isSelected
        case .off: return false
        }
    }

    /// 난외주 위첨자는 표시 모드 설정과 무관하게, 앵커가 있는 난외주가 하나라도 있으면 항상
    /// 보인다(관주/난외주 아이콘과 같은 원칙).
    private var shouldShowMarginalNoteMarkers: Bool {
        marginalNotes.contains { $0.anchorOffset != nil }
    }

    /// 형광펜/표시가 하나도 없으면(대다수 절) 기존과 똑같은 평범한 `Text`를
    /// 그대로 쓴다 — `VerseAnnotationRenderer`가 nil을 돌려주는 경로, AttributedString
    /// 변환 비용조차 들지 않는다.
    @ViewBuilder
    private var verseContentText: some View {
        // 원본 `verse.content`를 그대로 렌더러에 넘긴다 — 형광펜/구절별 메모의
        // `rangeStart`/`rangeEnd`가 원본 문자열 기준 UTF-16 오프셋이라, 앞에 문자를
        // 끼우면 표시 위치가 밀린다. 문단 마커(●)는 별도 `Text`를 `+` 대신 보간으로 앞에 이어
        // 붙인다.
        //
        // 한자/난외주 위첨자/형광펜/메모 중 하나라도 있으면 항상 캐시되는
        // `inlineAnnotatedContentProvider` 경로를 탄다(스크롤 중
        // `VerseRow`가 재생성될 때 구간 계산 반복 방지). 한자는
        // `shouldShowInlineHanja`가 false면 빈 배열을 넘겨, 위첨자만 필요한 절에 한자
        // 괄호가 끼지 않게 한다.
        if shouldShowInlineHanja || shouldShowMarginalNoteMarkers || !highlights.isEmpty || !phraseNotes.isEmpty {
            let attributed = inlineAnnotatedContentProvider(
                verse, highlights, phraseNotes, shouldShowInlineHanja ? hanjaWords : [], marginalNotes,
                platformBodyFont, platformTextColor, platformHanjaFont
            )
            if verse.paragraph != nil {
                // `Text + Text`(`+` 연산자)는 macOS 26부터 deprecated라 `Text`
                // 문자열 보간을 쓴다. 각 `Text`의 폰트/색 스타일은 그대로 유지된다.
                Text("\(paragraphMarkText)\(Text(attributed))")
            } else {
                Text(attributed)
            }
        } else {
            if verse.paragraph != nil {
                // 일반 문자열 리터럴의 `\( )` 보간 안에는 줄바꿈을 넣을 수 없어, 스타일을 적용한 `Text`를
                // 지역 변수로 먼저 뽑는다.
                let plainVerseText = Text(verse.content)
                    .font(settings.bibleBodyFont)
                    .foregroundStyle(settings.bibleTextColor ?? Color.primary)
                Text("\(paragraphMarkText)\(plainVerseText)")
            } else {
                Text(verse.content)
                    .font(settings.bibleBodyFont)
                    .foregroundStyle(settings.bibleTextColor ?? Color.primary)
            }
        }
    }

    /// 문단 시작 절 본문 맨 앞의 마커(●) — 별도 `Text`라 형광펜/구절별 메모 오프셋에 영향을
    /// 주지 않는다.
    private var paragraphMarkText: Text {
        Text("● ")
            .font(settings.bibleBodyFont)
            .foregroundStyle(settings.bibleTextColor ?? Color.primary)
    }

    private var platformBodyFont: PlatformFont {
        let size = CGFloat(settings.bibleBodyFontSize)
        guard settings.bibleFontName != "System" else { return .systemFont(ofSize: size) }
        BundledFontRegistrar.ensureAvailable(settings.bibleFontName)
        return PlatformFont(name: settings.bibleFontName, size: size) ?? .systemFont(ofSize: size)
    }

    /// 인라인 "(한자)" 표기용 폰트 — 크기는 본문 글꼴과 같고 이름만
    /// `settings.hanjaFontName`을 따른다("System"이면 본문 글꼴 그대로).
    private var platformHanjaFont: PlatformFont {
        guard settings.hanjaFontName != "System" else { return platformBodyFont }
        BundledFontRegistrar.ensureAvailable(settings.hanjaFontName)
        return PlatformFont(name: settings.hanjaFontName, size: platformBodyFont.pointSize) ?? platformBodyFont
    }

    private var platformTextColor: PlatformColor {
        if !settings.bibleTextColorHex.isEmpty, let color = Color(hex: settings.bibleTextColorHex) {
            return PlatformColor(color)
        }
        #if os(iOS)
        return .label
        #else
        return .labelColor
        #endif
    }

    // 관주 팝업 —
    // `BibleReadingHistorySheet.header`/`BookmarkListPopover.header`와
    // 같은 "제목 + 개수 배지 + 원형 닫기" 헤더, 강조색 책 이름 + 옅은 장:절 + chevron
    // 행으로 그 화면들과 같은 시각 언어를 쓴다. 위쪽 여백, 장식 구분선, 행 왼쪽 색상바도 같은
    // 방식이다.
    //
    // 아이폰에서 `.popover`가 시트로 바뀔 때 카드 위아래에 테마색이 아닌 여백이 남는 문제를
    // `TranslationPickerPopover`와 같은 두 겹 처리(근사
    // `.presentationDetents` + `.frame(maxHeight:
    // .infinity)`)로 막는다. 난외주
    // 팝오버(`marginalNotePopoverContent`)에는 아직 적용하지 않았다.
    private var crossReferencePopoverContent: some View {
        let targets = crossReferences.flatMap(\.targets)
        return VStack(alignment: .leading, spacing: 0) {
            crossReferenceHeader(count: targets.count)
            crossReferenceContentOrnamentalDivider
            List(targets, id: \.self) { target in
                crossReferenceRow(for: target)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(settings.bibleBackgroundColor ?? Color.clear)
            .listRowSeparatorTint(JBCHCategoryPalette.wood.opacity(0.15))
            .frame(minWidth: 220, minHeight: 160)
        }
        // 아이폰(시트)에서만 이 VStack을 시트 전체 높이까지 늘려(`alignment: .top`으로
        // 내용은 위쪽에 유지) 아래 `.background()`가 시트 전체를 칠하게 한다 —
        // `sheetHeight` 근사치가 어긋나도 남는 여백이 항상 테마색이다. 아이패드/macOS(진짜
        // popover)는 `nil`이라 내용 크기에 맞춰진다.
        .frame(maxHeight: isPhone ? .infinity : nil, alignment: .top)
        .background(settings.bibleBackgroundColor ?? Color.clear)
        #if os(iOS)
        .modifier(CrossReferenceSheetSizingModifier(isPhone: isPhone, sheetHeight: crossReferenceSheetHeight(count: targets.count)))
        #endif
    }

    /// `BibleReadingHistorySheet.header`/`BookmarkListPopover.header`와
    /// 같은 구조의 헤더.
    private func crossReferenceHeader(count: Int) -> some View {
        HStack(spacing: 6) {
            Text("관주")
                .font(.headline)
                .foregroundStyle(settings.bibleTextColor ?? .primary)
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(settings.bibleTextColor?.opacity(0.12) ?? Color.secondary.opacity(0.15), in: Capsule())
            Spacer()
            Button {
                isCrossReferencePopoverPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("닫기")
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    /// `BibleReadingHistorySheet`/`SearchView`의 장식
    /// 구분선(가로선-`sparkle`-가로선, wood 톤)과 같은 모양 — 그쪽이 `private`라 이
    /// 파일에 옮겨 적었다.
    private var crossReferenceContentOrnamentalDivider: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(JBCHCategoryPalette.wood.opacity(0.3))
                .frame(height: 1)
            Image(systemName: "sparkle")
                .font(.system(size: 11))
                .foregroundStyle(settings.bibleTextColor?.opacity(0.45) ?? Color.secondary)
            Rectangle()
                .fill(JBCHCategoryPalette.wood.opacity(0.3))
                .frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    /// 책 이름은 `Color("AccentColor")` 굵게, 장:절은 옅게 두고, 이미
    /// `Button`인 행이 탭 가능함을 `chevron.right`로 드러낸다.
    private func crossReferenceRow(for target: BibleVerseRef) -> some View {
        Button {
            isCrossReferencePopoverPresented = false
            onSelectCrossReferenceTarget(target)
        } label: {
            HStack(spacing: 8) {
                Text(crossReferenceBookName(target))
                    .font(.body.weight(.bold))
                    .foregroundStyle(Color("AccentColor"))
                Text(crossReferenceVerseLabel(target))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.7) ?? Color.secondary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.4) ?? Color.secondary.opacity(0.6))
            }
            .padding(.leading, 10)
            // 행 왼쪽 강조선(`DocumentRowView.documentRowLabel`의 "책등" 패턴) —
            // 색은 책 이름과 같은 `AccentColor`.
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color("AccentColor"))
                    .frame(width: 3)
                    .padding(.vertical, 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        // 책 이름/장:절이 별도 `Text`라 VoiceOver가 따로 읽으므로, 접근성 레이블은 합친
        // 문장("창세기 4:22")으로 제공한다.
        .accessibilityLabel(crossReferenceTargetLabel(target))
    }

    private func crossReferenceBookName(_ target: BibleVerseRef) -> String {
        BooksProvider.shared.book(id: target.bookId)?.nameKo ?? "책 \(target.bookId)"
    }

    private func crossReferenceVerseLabel(_ target: BibleVerseRef) -> String {
        "\(target.chapter):\(target.verse)"
    }

    private func crossReferenceTargetLabel(_ target: BibleVerseRef) -> String {
        "\(crossReferenceBookName(target)) \(crossReferenceVerseLabel(target))"
    }

    /// `TranslationPickerPopover.isPhone`과 같은 판정(그쪽이 `private`라
    /// 로직만 옮겨 적었다).
    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    #if os(iOS)
    /// `TranslationPickerPopover.sheetHeight`와 같은 계산 — 헤더 + 구분선
    /// + 행당 44(HIG 최소 탭 영역). `max(count, 1)`은 시트 높이가 0이 되는 것을
    /// 막는 안전장치다(이 팝오버는 `!crossReferences.isEmpty`일 때만 열린다).
    private func crossReferenceSheetHeight(count: Int) -> CGFloat {
        // 헤더/장식 구분선 높이는 근사치다 — 어긋나도
        // `crossReferencePopoverContent`의 `.frame(maxHeight:
        // .infinity)`가 남는 여백을 테마색으로 채운다.
        let headerHeight: CGFloat = 52
        let dividerHeight: CGFloat = 20
        let rowHeight: CGFloat = 44
        return headerHeight + dividerHeight + CGFloat(max(count, 1)) * rowHeight
    }
    #endif

    /// 난외주 팝오버 — 탭할 대상이 없어 `Button` 없이 `Text`만 나열한다.
    private var marginalNotePopoverContent: some View {
        List(marginalNotes) { note in
            Text(note.noteText)
        }
        .frame(minWidth: 220, minHeight: 120)
    }


    private func phraseMemoLabel(_ memo: UserMemo) -> String {
        let trimmed = memo.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(내용 없음)" : trimmed
    }

    /// 선택(복사 대상)은 검색 하이라이트보다 더 뚜렷해야 한다 — 하이라이트는 일시적 안내지만 선택은
    /// 사용자가 직접 고른 상태라, 놓치면 엉뚱한 절이 복사될 수 있다.
    private var backgroundColor: Color {
        if isSelected { return Color("AccentColor").opacity(0.28) }
        // 찾기 일치는 절 전체 배경으로만 알린다(글자 단위 강조는 하지 않음 — `BibleChapterFind.swift` 참고).
        if isCurrentFindMatch { return Color.yellow.opacity(0.34) }
        if isFindMatch { return Color.yellow.opacity(0.18) }
        if isHighlighted { return Color("AccentColor").opacity(0.15) }
        return Color.clear
    }
}

#if os(iOS)
/// `VerseRow.crossReferencePopoverContent` 전용 시트 크기 모디파이어 —
/// 아이폰(시트)에서만 높이를 컨텐츠에 맞추고, 아이패드/macOS(팝오버)에서는 아무것도 하지 않는다.
/// 같은 구조가 다른 파일에 `private`로 있어 이 파일에 따로 둔다.
private struct CrossReferenceSheetSizingModifier: ViewModifier {
    let isPhone: Bool
    let sheetHeight: CGFloat
    func body(content: Content) -> some View {
        if isPhone {
            content
                .presentationDetents([.height(sheetHeight)])
                .presentationDragIndicator(.visible)
        } else {
            content
        }
    }
}
#endif

/// `ContentUnavailableView`(macOS 14+/iOS 17+) 대신 텍스트만 보여주는
/// 경량 대체 뷰 — 아이콘/버튼 파라미터가 필요 없어서다.
private struct ContentUnavailableMessage: View {
    let message: String
    init(_ message: String) { self.message = message }

    var body: some View {
        VStack {
            Spacer()
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}


// MARK: - 장 끝 버튼 (이전 장 / 다음 장 / 이 장의 개인 묵상)

/// 장 끝 버튼이 필요로 하는 값과 동작. 이동/저장은 호출부(`BibleReadingView`)가 맡고 이 뷰는 그리기만 한다.
struct ChapterEndActions {
    /// 이동 대상 장의 표시 이름(예: "요한복음 2장"). nil이면 그 방향으로 갈 장이 없어 버튼을 끈다(창세기 1장/계시록 마지막 장).
    var previousLabel: String?
    var nextLabel: String?
    var onPrevious: () -> Void
    var onNext: () -> Void
    /// 이 장에 이미 있는 장 단위 개인 묵상(최근순). 비어 있으면 버튼이 바로 새 묵상을 연다.
    var existingNotes: [ChapterNoteItem]
    var onNewNote: () -> Void
}

struct ChapterNoteItem: Identifiable {
    let id: UUID
    let preview: String
    let open: () -> Void
}

private struct ChapterEndFooterView: View {
    let actions: ChapterEndActions

    private var accent: Color { Color("AccentColor") }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                navButton(systemImage: "chevron.left", title: "이전 장", subtitle: actions.previousLabel, action: actions.onPrevious)
                navButton(systemImage: "chevron.right", title: "다음 장", subtitle: actions.nextLabel, action: actions.onNext, trailingIcon: true)
            }
            noteButton
        }
        .padding(.top, 12)
    }

    /// 배경은 본문색을 옅게 깐 중립 톤, 글자는 본문색 그대로, 강조색은 화살표 아이콘과 테두리에만 쓴다 —
    /// 강조색 글자를 강조색 옅은 배경 위에 얹으면 명도 차가 작아 읽기 어렵다.
    private func navButton(
        systemImage: String, title: String, subtitle: String?, action: @escaping () -> Void, trailingIcon: Bool = false
    ) -> some View {
        let textColor = UserSettingsStore.shared.bibleTextColor ?? Color.primary
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button(action: action) {
            HStack(spacing: 8) {
                if !trailingIcon {
                    Image(systemName: systemImage).font(.subheadline.weight(.bold)).foregroundStyle(accent)
                }
                VStack(spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(textColor)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(textColor.opacity(0.7))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                if trailingIcon {
                    Image(systemName: systemImage).font(.subheadline.weight(.bold)).foregroundStyle(accent)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(shape.fill(textColor.opacity(0.08)))
            .overlay(shape.strokeBorder(accent.opacity(0.45), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(subtitle == nil)
        .opacity(subtitle == nil ? 0.35 : 1)
    }

    @ViewBuilder
    private var noteButton: some View {
        if actions.existingNotes.isEmpty {
            Button(action: actions.onNewNote) { noteLabel }
                .buttonStyle(.plain)
        } else {
            Menu {
                Button("새 개인 묵상 작성", systemImage: "square.and.pencil", action: actions.onNewNote)
                Divider()
                ForEach(actions.existingNotes) { note in
                    Button(note.preview, action: note.open)
                }
            } label: {
                noteLabel
            }
            .buttonStyle(.plain)
        }
    }

    private var noteLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "note.text")
            Text(actions.existingNotes.isEmpty ? "이 장에 대한 개인 묵상" : "이 장에 대한 개인 묵상 (\(actions.existingNotes.count))")
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(accent))
        .foregroundStyle(Color.white)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
