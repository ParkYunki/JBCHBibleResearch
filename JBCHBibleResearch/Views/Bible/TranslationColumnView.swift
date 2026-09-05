//
//  TranslationColumnView.swift
//  JBCHBibleResearch
//
//  S1(성경 조회)의 컬럼 하나(번역본 하나)를 그린다. 이 뷰가 리더 역할(사용자가 실제로
//  스크롤 중일 때 — 화면 중앙 절을 ScrollSyncCoordinator에 보고)과 팔로워 역할(다른
//  컬럼이 리더일 때 — 좌표를 받아 자신을 그 절로 스크롤)을 동시에 수행한다.
//
//  ⚙️ [스크롤 동기화 정의, 사용자 재확인] "성경 왼쪽 본문 화면 영역 정가운데에
//  눈에 보이지 않는 기준선이 있고, 그 선을 왼쪽 본문의 절이 지날 때, 다른
//  번역본도 각 본문 영역의 가운데로 같은 절이 위치하도록" — 즉 모든 컬럼이
//  자기 자신의 뷰포트 "정중앙"에 항상 같은 절 번호가 오도록 서로 맞추는 것.
//  아래 `centerVerseID`(anchor: .center)가 정확히 이 "가운데 기준선" 역할이다.
//
//  [2026-08-08 재작성] 사용자가 "왼쪽 성경을 스크롤할 때 나머지 성경 본문의 스크롤이
//  동기화 안 됨"이라고 다시 보고했다 — 바로 이전 라운드에서 디바운스→스로틀로
//  고친 뒤에도 증상이 남아 있다는 뜻으로 받아들였다. 근본적으로 다시 보니, 애초에
//  "각 절 행이 GeometryReader로 자기 좌표를 PreferenceKey에 보고하고, 이 뷰가 매번
//  '뷰포트 중앙과 가장 가까운 절'을 직접 계산"하는 방식 자체가 손으로 만든 근사치라
//  타이밍 버그(이번 세션에서만 크래시 1건 + 동기화 지연 1건)를 반복 생산하고 있었다.
//  SwiftUI가 iOS17/macOS14부터 정확히 이 용도로 제공하는 네이티브 API
//  `ScrollView.scrollPosition(id:anchor:)`(이 프로젝트의 최소 배포 버전과 일치)로
//  바꿨다 — 뷰포트 "중앙(anchor: .center)"에 있는 항목의 id를 자동으로 읽어주고,
//  그 바인딩에 값을 대입하면 그 항목이 중앙에 오도록 알아서 스크롤도 해 준다.
//  GeometryReader/PreferenceKey/좌표 공간/디바운스·스로틀 타이머가 전부 필요 없어져
//  코드가 줄고, 프레임마다 손으로 "가장 가까운 절"을 재계산하던 부동소수점 비교
//  로직(이전 크래시의 근본 원인)도 통째로 사라졌다.
//
//  ⚠️ [2026-08-08 추가 수정] 이 재작성 직후에도 사용자가 "여전히 안 됨"이라고
//  보고했다 — 원인은 `.scrollPosition(id:)`만 붙이고 `.scrollTargetLayout()`을
//  같이 붙이지 않은 것이었다. Apple 공식 사용 패턴은 항상 `LazyVStack { ForEach
//  { ... } }.scrollTargetLayout()`처럼 id를 매기는 레이아웃 컨테이너를 "스크롤
//  타깃 레이아웃"으로 명시적으로 표시해야 한다 — 이게 없으면 `.scrollPosition(id:)`
//  바인딩이 사실상 갱신되지 않는다. 아래 `columnScrollView`의 `LazyVStack`에
//  `.scrollTargetLayout()`을 추가해 고쳤다.
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
    /// 이 번역본 자신의 언어로 표시하는 "책 장" 레이블(예: "John 3"). 2026-08-06 추가 —
    /// TranslationInfo.swift(이전 앱)의 BookNameTable 이식분(BookNameTableProvider.swift)이
    /// 계산해 준 값을 그대로 받아 표시만 한다(이 뷰 자체는 이름표 조회 로직을 모른다).
    /// [2026-08-08 추가 용도] 책/장이 바뀔 때마다 이 문자열도 함께 바뀐다는 점을
    /// 이용해, 장이 바뀌었다는 신호로도 쓴다(`resetForChapterChange` 참고).
    var localizedBookChapterLabel: String? = nil
    let verses: [BibleVerse]
    let errorDescription: String?
    var highlightedVerse: Int?
    var onSelectVerse: (BibleVerse) -> Void = { _ in }
    /// screens.md 5장 — "절 클릭 → 컨텍스트 메뉴 → 메모 작성(S3, 정확한 좌표 미리
    /// 채워짐)". 2026-08-06 추가.
    var onCreateMemo: (BibleVerse) -> Void = { _ in }
    /// [2026-08-26 신설] 사용자 요청 — "iOS 성경 구절 길게 프레스/맥OS 마우스
    /// 오른쪽버튼 → [복사] 메뉴 추가 - 해당 번역본만 복사." 아래 `.contextMenu`가
    /// 넘기는 `verse`가 이미 "이 컬럼(번역본) 하나"의 절 내용이므로(이 뷰의
    /// `verses` 자체가 번역본별로 갈라져 상위에서 내려온다), 하단 액션바의
    /// 다중 절/다중 번역본 복사(`BibleReadingView.copySelectedVerses`)와 달리
    /// 이 클로저는 "절 하나 + 번역본 이름 하나"만 넘긴다 — 실제 포매팅
    /// (`BibleVerseCopyFormatter`)과 클립보드 접근, 토스트 표시는 book/chapter를
    /// 알고 있는 호출부(`BibleReadingView`)의 책임이다.
    var onCopySingleTranslation: (BibleVerse, String) -> Void = { _, _ in }
    /// [2026-08-26 신설] 사용자 요청 — "iOS 성경 구절 길게 프레스/맥OS 마우스
    /// 오른쪽버튼 → [선택] 메뉴 추가 - 일부 텍스트를 선택하여 복사할 수 있는
    /// 기능." 위 `onCopySingleTranslation`과 같은 원칙으로 "절 하나 + 번역본
    /// 이름 하나"만 넘기고, 실제 팝오버 표시는 호출부(`BibleReadingView`)의
    /// 책임이다(`VerseTextSelectionPopover` 참고).
    var onSelectPartialText: (BibleVerse, String) -> Void = { _, _ in }
    /// [2026-08-08 추가] 클립보드 복사용 다중 선택 — 절 번호 기준으로 컬럼(번역본)
    /// 여러 개에 걸쳐 공유되는 선택 상태다(같은 절 번호는 어느 컬럼에서도 같은
    /// "절"을 가리키므로). `BibleReadingViewModel.selectedVerses` 참고.
    var selectedVerses: Set<Int> = []
    /// [2026-08-15 추가] 사용자 요청 — "클릭하면 구절이 선택되고 다른 구절을
    /// 클릭하면 선택이 바뀌게" — 일반 클릭(수식키 없음)은 이제 이 클로저를
    /// 부른다. 기존 `onToggleVerseSelection`은 컨트롤 클릭(개별 다중 선택)
    /// 전용으로 의미가 좁혀졌다(아래 `columnScrollView`의 tap 핸들러 참고).
    var onSelectSingleVerse: (Int) -> Void = { _ in }
    var onToggleVerseSelection: (Int) -> Void = { _ in }
    /// [2026-08-15 추가] Shift/Cmd 클릭 — 마지막 기준 절부터 이 절까지 범위
    /// 선택. `BibleReadingViewModel.extendVerseSelection(to:)` 참고.
    var onExtendVerseSelection: (Int) -> Void = { _ in }

    let coordinator: ScrollSyncCoordinator
    /// [2026-08-08 추가] 사용자 요청 — "아이폰에서 스크롤 실시간 동기화는 하지
    /// 않아도 됨". 아이폰은 `TabView` 페이징이라 한 번에 컬럼 하나만 보이므로,
    /// 안 보이는 다른 컬럼들이 계속 백그라운드에서 애니메이션까지 하며 따라다닐
    /// 필요가 없다(리소스 낭비 + 화면에 보이지도 않는 스크롤 애니메이션). 그래서
    /// 아이폰(`BibleReadingView.phoneColumns`)에서만 이 값을 false로 넘겨
    /// 리더 보고(`reportCenterVerseIfNeeded`)는 그대로 두고 팔로워 응답
    /// (`respondToSyncEvent`)만 끈다 — 대신 페이지 전환 순간에 한 번만
    /// `pendingCenterAlignment`로 맞춘다.
    var respondsToSyncEvents: Bool = true
    /// [2026-08-08 추가] 아이폰 스와이프 정렬 전용 — 부모(`BibleReadingView.
    /// phoneColumns`)가 "지금 이 컬럼을 이 절로 맞춰라"라고 1회성으로 명령하는
    /// 값. nil이 아닌 새 값이 들어올 때마다 애니메이션 없이 즉시 반영한다(탭
    /// 전환 자체에 이미 스와이프 전환 효과가 있어 추가 애니메이션이 필요 없다).
    var pendingCenterAlignment: Int? = nil
    /// [2026-09-04 신설] 사용자 요청 — "만일 추가 번역본이 없거나, 번역본이
    /// 보여지고 있지 않다면 자동 절 이동은 하지 않아도 된다." 아이폰에서
    /// 번역본이 하나만 등록/표시돼 있으면 스와이프해서 넘어갈 다른 페이지
    /// 자체가 없어, 아래 `reportCenterVerseIfNeeded`가 보고해도 맞춰 줄
    /// 대상이 없다 — 그런데도 지금까지는 컬럼 개수와 무관하게 스크롤할
    /// 때마다 항상 보고해 왔다. `respondsToSyncEvents == false`(아이폰)일
    /// 때만 참조하는 값이라, macOS/iPadOS 기본값(true)에서는 영향이 없다.
    var hasAdditionalDisplayedColumns: Bool = true

    /// [2026-08-08 추가] 구간 주석(형광펜/표시/관주/구간메모) — README "이어서 16"
    /// 설계 논의. 이 뷰는 기존에도 "이미 걸러진 데이터를 그대로 그리기만 한다"는
    /// 원칙(`verses`/`selectedVerses`)을 따르고 있어, 번역본 코드 매칭 등 실제
    /// 필터링은 상위(`BibleReadingContentView`, `BibleReadingViewModel`을 들고
    /// 있다)에 맡기고 이 뷰는 절 번호를 넣으면 결과만 받는 클로저로만 접근한다.
    /// ⚠️ 구조체 프로퍼티 선언 순서 = 자동 생성 memberwise init의 인자 순서라
    /// 호출부(BibleReadingView.swift)와 반드시 같은 순서로 둬야 한다 — 처음엔
    /// `coordinator` 앞에 뒀다가 호출부는 뒤에 넘겨 "Argument must precede..."
    /// 컴파일 에러가 났다.
    var highlightsProvider: (Int) -> [VerseHighlight] = { _ in [] }
    var crossReferencesProvider: (Int) -> [VerseCrossReference] = { _ in [] }
    var phraseMemosProvider: (Int) -> [UserMemo] = { _ in [] }
    /// [2026-08-11 추가] "메모"(신규, 드래그 표현 부연설명) — 위 `phraseMemosProvider`와
    /// 같은 원칙.
    var phraseNotesProvider: (Int) -> [VersePhraseNote] = { _ in [] }
    /// [2026-08-14 추가] 난외주(단어 뜻풀이/구약 인용 출처) — 관주와 같은 자리에
    /// 아이콘으로 노출한다. `MarginalNoteSeedImporter.swift` 참고.
    var marginalNotesProvider: (Int) -> [VerseMarginalNote] = { _ in [] }
    /// [2026-08-14 추가] 절 단위 한자 주석 — 관주/난외주와 같은 원칙. 표시
    /// 방식(끄기/탭하면 보기/항상 보기)은 `UserSettingsStore.hanjaDisplayMode`를
    /// `VerseRow`가 직접 읽는다(다른 구간 주석과 달리 이건 사용자가 설정 화면에서
    /// 직접 켜고 끄는 "전역 표시 모드"라서, 상위에서 데이터 유무만 걸러 주는
    /// 다른 provider들과 다르게 이 프로퍼티 하나로는 최종 표시 여부를 못 정한다).
    var hanjaWordsProvider: (Int) -> [HanjaWordAnnotation] = { _ in [] }
    /// [2026-08-11 추가] "관련 내용" — 관주/메모와 같은 원칙으로, 이 절을 언급하는
    /// 메모/연구문서가 있으면 절 번호 아래에 세 번째 아이콘으로 노출한다.
    var verseMentionsProvider: (Int) -> [VerseMention] = { _ in [] }
    /// [2026-09-04 신설] 사용자 요청 — "책갈피를 설정하면 성경 본문 절번호
    /// 왼쪽에 길게 갈피실 색상으로 세로라인을 그어줄 수 있는가?" 위 다른
    /// Provider들과 같은 원칙 — `BibleReadingViewModel.isVerseBookmarked(_:)`가
    /// 실제 구현이다(호출부 `BibleReadingView.swift` 참고).
    var isBookmarkedProvider: (Int) -> Bool = { _ in false }
    /// [2026-09-04 신설] 사용자 요청 — "장을 책갈피 할때는 아무 표시가
    /// 없음. 스크롤영역 뒤 왼쪽 변에 백그라운드로 길게 이어진 세로 라인을
    /// 그어줄 수 있나?" 위 `isBookmarkedProvider`(절 단위)와 달리 이건
    /// "장 전체" 책갈피 하나에 대한 값이라 절마다 다시 물어볼 필요가 없어
    /// 클로저가 아니라 값 하나로 받는다 — `BibleReadingViewModel.
    /// isChapterBookmarked`가 실제 구현이다(호출부 `BibleReadingView.swift`
    /// 참고).
    var isChapterBookmarked: Bool = false
    /// 관주 팝오버에서 대상 구절을 탭했을 때 — 그 책/장으로 이동한다(정확한 절
    /// 위치로 스크롤하는 것까지는 이번 구현 범위 밖, README 참고).
    var onSelectCrossReferenceTarget: (BibleVerseRef) -> Void = { _ in }
    /// 구간 메모 아이콘에서 메모를 골랐을 때 — 기존 "메모 작성" 시트를 그대로 연다.
    var onSelectPhraseMemo: (UserMemo) -> Void = { _ in }
    /// [2026-08-11 추가] "관련 내용" 목록에서 항목을 골랐을 때 — 메모는 편집기
    /// 시트로, 연구문서는 PDF 검색+이동 창으로 연다(호출부 BibleReadingView 책임).
    var onSelectVerseMention: (VerseMention) -> Void = { _ in }
    /// [2026-09-02 신설] 사용자 보고 — "왼쪽 기본 성경 칸 스크롤 버벅임 —
    /// 한자/난외주 인라인 표시용 `AttributedString`을 절마다 다시 만드는
    /// 경로도 캐싱할 것." 위 다른 provider들과 같은 원칙으로, 실제 캐싱
    /// 로직(`BibleReadingViewModel.cachedInlineAnnotatedContent`)은 상위가
    /// 갖고 있고 이 뷰는 그 결과만 받는다. 기본값은 캐싱 없이 예전과 똑같이
    /// `VerseAnnotationRenderer.attributedContentWithInlineAnnotations`를 바로
    /// 부르는 경로라, 이 클로저를 안 넘기는 호출부(프리뷰 등)도 그대로 동작한다.
    var inlineAnnotatedContentProvider: (
        BibleVerse, [VerseHighlight], [VersePhraseNote], [HanjaWordAnnotation], [VerseMarginalNote],
        PlatformFont, PlatformColor, PlatformFont?
    ) -> AttributedString = { verse, highlights, phraseNotes, hanjaWords, marginalNotes, font, textColor, hanjaFont in
        VerseAnnotationRenderer.attributedContentWithInlineAnnotations(
            text: verse.content, highlights: highlights, phraseNotes: phraseNotes,
            hanjaWords: hanjaWords, marginalNotes: marginalNotes, font: font, textColor: textColor, hanjaFont: hanjaFont
        )
    }

    /// 지금 뷰포트 중앙(anchor: .center)에 있는 절 번호 — `.scrollPosition(id:)`가
    /// 스크롤에 맞춰 자동으로 읽어 주고(리더 역할), 반대로 이 값을 대입하면 그
    /// 절이 중앙에 오도록 알아서 스크롤도 해 준다(팔로워 역할). 이 하나의 상태로
    /// 리더/팔로워 양쪽을 다 처리한다 — 이전의 `verseMidYs`/`viewportHeight`
    /// 수동 계산이 통째로 필요 없어졌다.
    @State private var centerVerseID: Int?
    /// 이 컬럼 자신이 팔로워로서 프로그램적으로 스크롤하는 중인지 — 그 사이에는
    /// `centerVerseID` 변경을 리더 보고로 착각해 되돌려 보고하지 않는다(안 그러면
    /// 팔로워가 스스로를 리더로 착각해 무한 루프에 빠질 수 있다).
    @State private var isProgrammaticScroll = false
    /// [2026-08-07 수정] 아래 `respondToSyncEvent` 참고 — 예약해 둔 가드 해제 작업을
    /// 취소할 수 있도록 들고 있는다.
    @State private var guardReleaseWorkItem: DispatchWorkItem?

    /// addendum.md 3장이 명시한 "가드 해제 시각을 애니메이션 지속 시간과 정확히
    /// 맞춘다" 패턴의 그 지속 시간. `respondToSyncEvent`의 `withAnimation` duration과
    /// 반드시 같은 값을 써야 한다 — 상수 하나로 통일해 둘이 어긋나지 않게 한다.
    private static let scrollAnimationDuration: TimeInterval = 0.25

    /// [2026-09-04 신설] 사용자 보고 — "아이폰 성경 본문에서 빨리 스크롤하면
    /// 중간에 멈춤." 아이폰(`respondsToSyncEvents == false`)에서는 아래
    /// `reportCenterVerseIfNeeded`가 매 스크롤 프레임마다(빠르게 스크롤하면
    /// 초당 여러 번) `coordinator.reportCenterVerse`를 불러 `@Observable` 값을
    /// 즉시 갱신해 왔다 — 그런데 아이폰에서 이 보고를 실시간으로 구독하는
    /// 곳이 없다(`SyncEventSubscriptionModifier`가 그 구독 자체를 이미 꺼
    /// 둠, 위 주석 참고). 유일한 소비처는 `BibleReadingView.phoneColumns`의
    /// `.onChange(of: selectedPhoneColumnID)`로, 번역본 페이지를 스와이프해
    /// 넘기는 "그 순간"에만 마지막 값을 한 번 읽는다 — 즉 아이폰은 스크롤
    /// 도중 매 프레임 실시간으로 이 값이 필요하지 않다. 그런데도 매번 즉시
    /// 보고하다 보니, 빠른 스크롤 중 이 메인 스레드 작업(Observation 갱신)이
    /// 스크롤 렌더링과 겹쳐 프레임이 밀릴 여지가 있었다 — 아이폰 한정으로
    /// 짧게 디바운스해(스크롤이 잠시라도 멈출 때까지 기다렸다가 마지막 값
    /// 하나만 보고) 그 빈도를 크게 줄인다. macOS/iPadOS(`respondsToSyncEvents
    /// == true`)는 이 값을 실시간 시각적 동기화에 그대로 쓰므로 그대로 즉시
    /// 보고한다 — 손대지 않는다.
    private static let phoneReportDebounceInterval: TimeInterval = 0.15
    @State private var phoneReportWorkItem: DispatchWorkItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                // [2026-09-02 수정] 사용자 요청 — "테마색상/글자색 변경 시
                // 번역본이름·성경장 텍스트 색상도 함께 바뀌어야 함." 기존엔
                // `.secondary`/`.tertiary`(시스템 고정 톤)였다 — 사용자가 글자색을
                // 직접 골랐으면(`bibleTextColor` != nil) 그 색을 그대로 쓰고,
                // 안 골랐으면(nil) 기존 톤을 그대로 유지한다.
                Text(translationDisplayName)
                    .font(.headline)
                    .foregroundStyle(settings.bibleTextColor ?? .secondary)
                if let localizedBookChapterLabel, !localizedBookChapterLabel.isEmpty {
                    Text(localizedBookChapterLabel)
                        .font(.caption)
                        .foregroundStyle(settings.bibleTextColor ?? systemTertiaryTextColor)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if let errorDescription {
                ContentUnavailableMessage(errorDescription)
            } else if verses.isEmpty {
                ContentUnavailableMessage("이 장에 표시할 절이 없습니다.")
            } else {
                columnScrollView
            }
        }
        // [2026-09-04 수정] 사용자 요청 — "세로선을 번역본/성경 장이
        // 타이틀로 나오는 상단영역까지 표시를 할 것." 예전엔 이 세로선이
        // (아래 `columnScrollView`가 감싸는) `ScrollView` 자신의 배경으로만
        // 붙어 있어 제목 영역(바로 위 `Text(translationDisplayName)` 등)
        // 아래에서부터 시작했다 — 이 컬럼 전체(제목+본문)를 감싸는 이
        // 바깥 `VStack`으로 옮겨 컬럼 맨 위부터 끝까지 하나로 이어지게
        // 한다. `.overlay`가 아니라 `.background`를 쓴 이유는 그대로다 —
        // 본문/제목 위에 겹쳐 그려지지 않고 뒤에 깔린다.
        .background(alignment: .leading) {
            if isChapterBookmarked {
                // [2026-09-04 변경] 사용자 요청 — "장 북마크 세로선을 10pt로
                // 좀더 굵게 표현할 것." 8pt → 10pt. 상단이 이제 컬럼 맨
                // 위(제목 영역)까지 닿으므로 `ChapterBookmarkRibbonShape`의
                // 상단 모양도 둥근 캡 대신 각진 사각형으로 바꿨다(그 struct
                // 상단 주석 참고).
                ChapterBookmarkRibbonShape()
                    .fill(JBCHCategoryPalette.wine)
                    .frame(width: 10)
            }
        }
        // [2026-09-01 추가] 사용자 요청 — "설정 - 성경 - 모양에 배경색 테마
        // 추가." 이 컬럼 뷰는 지금까지 배경을 전혀 지정하지 않아 시스템 기본
        // (라이트/다크 모드 자동 대응)이었다 — `UserSettingsStore.
        // bibleBackgroundColor`가 nil(사용자가 아직 안 고름)이면 `Color.clear`로
        // 그 기존 동작을 그대로 유지하고, 값이 있으면 그 색을 컬럼 전체
        // (헤더+본문)에 칠한다.
        .background(settings.bibleBackgroundColor ?? Color.clear)
    }

    /// [2026-08-20 추가] 사용자 요청 — "절 간격 조절 기능추가". 아래
    /// `columnScrollView`의 `LazyVStack(spacing:)`이 예전엔 10으로 고정돼
    /// 있었다 — `UserSettingsStore.bibleVerseSpacing`(설정 - 모양 - 성경 조회
    /// 표시)을 그대로 전달한다. `VerseRow`가 쓰는 `settings`(아래)와 같은
    /// 패턴이지만, 그건 `private struct VerseRow` 안이라 이 struct에서 따로
    /// 하나 둔다.
    private var settings: UserSettingsStore { .shared }

    /// [2026-09-02 추가] 컴파일 에러 수정 — `Color`엔 `.secondary`는 있어도
    /// `.tertiary`는 없다(`.tertiary`는 `ShapeStyle`에만 있는 계층적 스타일이라
    /// `Color?` 값과 `??`로 합칠 수 없다: "Instance member 'tertiary' cannot be
    /// used on type 'Color'"). 이 파일 바로 아래 `platformTextColor`, 그리고
    /// `OriginalTextInfoView.swift`의 `cardBorderColor`/`cardBackground`가 이미
    /// 쓰고 있는 것과 같은 관례로, 시스템이 실제로 쓰는 3차 레이블 색(라이트/
    /// 다크 모드 자동 대응)을 `Color`로 직접 감싼다 — `.tertiary` ShapeStyle이
    /// 원래 나타내려던 것과 동일한 시각적 톤이다.
    private var systemTertiaryTextColor: Color {
        #if os(iOS)
        Color(uiColor: .tertiaryLabel)
        #else
        Color(nsColor: .tertiaryLabelColor)
        #endif
    }

    @ViewBuilder
    private var columnScrollView: some View {
        // ⚠️ [2026-09-04 신설, 아이폰 스크롤 버벅임 근본 수정] 사용자 실측 결과 —
        // (1) VerseRow 내용물(형광펜/관주/메모/아이콘 전부)을 Text 하나로 바꿔도
        // 스크롤은 여전히 버벅였고, (2) `.scrollPosition(id:anchor:)`/
        // `.scrollTargetLayout()`(뷰포트 "중앙" 절을 스크롤 프레임마다 실시간으로
        // 추적/보정하는 네이티브 메커니즘)만 잠깐 꺼 보니 그제서야 매끄러워졌다.
        // 즉 버벅임의 실제 원인은 절 내용이 아니라 이 실시간 중앙 추적 자체다.
        //
        // 이 메커니즘이 실제로 필요한 곳은 macOS/아이패드의 "여러 번역본 실시간
        // 스크롤 동기화"(`respondsToSyncEvents == true`, 사용자가 버벅임을 보고한
        // 적 없는 쪽) 하나뿐이다 — 아이폰(`respondsToSyncEvents == false`)은
        // 애초에 팔로워 실시간 동기화 자체를 안 쓰고(`SyncEventSubscriptionModifier`
        // 참고), "검색 이동/장 리셋/페이지 스와이프 정렬"은 전부 "이 절로
        // 스크롤해라"라는 1회성 지시일 뿐 실시간 추적이 필요 없다. 그래서
        // macOS/아이패드(`columnScrollViewSyncTracking`) 쪽은 기존 코드를 그대로
        // 두고, 아이폰(`columnScrollViewPhoneLightweight`) 쪽만 실시간 추적 없이
        // 새로 짰다 — 사용자 확인 후 적용, 실기기 빌드로는 아직 재검증 못 했다.
        if respondsToSyncEvents {
            columnScrollViewSyncTracking
        } else {
            columnScrollViewPhoneLightweight
        }
    }

    /// macOS/아이패드 전용 — 위 `columnScrollView` 상단 주석 참고. 리더/팔로워
    /// 실시간 스크롤 동기화가 실제로 필요한 유일한 경로라, `.scrollPosition(id:
    /// anchor:)` 기반 기존 구현을 그대로 옮겨왔다(행 하나하나 구성하는 부분만
    /// 아래 `verseRowView(for:)`로 뽑아 아이폰 쪽과 공유하고, 그 외 이 프로퍼티
    /// 안쪽 로직·순서·주석은 이번 수정으로 바꾸지 않았다).
    private var columnScrollViewSyncTracking: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: CGFloat(settings.bibleVerseSpacing)) {
                ForEach(verses, id: \.verse) { verse in
                    verseRowView(for: verse)
                }
            }
            // [2026-08-08 추가, 핵심 누락분] `.scrollPosition(id:anchor:)`가
            // "지금 anchor 지점(.center)에 있는 항목의 id"를 실제로 추적하려면,
            // 그 id들을 매기는 레이아웃 컨테이너(이 LazyVStack)를 "스크롤 타깃
            // 레이아웃"으로 표시해 줘야 한다 — Apple 공식 사용 패턴이 항상
            // `LazyVStack { ForEach { ... } }.scrollTargetLayout()` 형태다. 이걸
            // 빠뜨리면 바인딩 자체가 사실상 갱신되지 않거나 신뢰할 수 없게 동작한다
            // — 이전 재작성에서 이 한 줄을 빠뜨려서 "네이티브 API로 바꿨는데도
            // 여전히 동기화가 안 되는" 증상이 계속됐던 것으로 보인다.
            .scrollTargetLayout()
            .padding()
        }
        // [2026-09-04 수정] 장 북마크 세로선은 이제 이 컬럼(제목+본문) 전체
        // 배경에 한 곳에서만 그린다 — 아래 `body` 상단 주석 참고. 예전엔
        // 이 `ScrollView` 자신의 배경에 붙어 있었으나, "제목 영역까지
        // 연장" 요청으로 더 바깥(제목을 포함하는 컨테이너)으로 옮겼다.
        .scrollPosition(id: $centerVerseID, anchor: .center)
        // [2026-08-19 추가] 검색 결과 등에서 이 화면이 처음 만들어질 때부터
        // 이미 `highlightedVerse`가 채워져 있는 경우 — 예: 검색 결과를 탭하면
        // `BibleReadingView`가 새로 생기면서 `highlightedVerse`를 첫 렌더링
        // 시점부터 갖고 시작한다. `.onChange(of: highlightedVerse)`(아래)는
        // "그 이후의 변화"에만 반응하고 최초 값에는 반응하지 않으므로(SwiftUI
        // 기본 동작), 최초 진입 케이스는 `.onAppear`에서 애니메이션 없이
        // 바로 맞춰준다.
        .onAppear {
            if let highlightedVerse {
                centerVerseID = highlightedVerse
            }
        }
        .onChange(of: centerVerseID) { _, newValue in
            reportCenterVerseIfNeeded(newValue)
        }
        // [2026-09-03 변경] 사용자 보고 — "아이폰 성경에서 빨리 스크롤할 때
        // 중간에 멈춤." 원래는 이 `.onChange`를 항상 붙여 두고 안에서
        // `respondsToSyncEvents == false`(아이폰)면 그냥 return만 했다 — 그런데
        // `.onChange(of:)`가 관찰하는 `coordinator.latestEvent`는 이 컬럼이 아니라
        // "다른" 컬럼이 리더로 스크롤할 때도(`reportCenterVerseIfNeeded` 참고,
        // 이건 스와이프 정렬 기능에 쓰여 그대로 둬야 한다) 바뀐다 — 아이폰은
        // 번역본마다 페이지(`BibleReadingView.phoneColumns`의 `TabView(.page)`)가
        // 갈라져 있어 2~3개 번역본을 표시해 두면 지금 눈에 안 보이는 페이지의
        // `TranslationColumnView`도 이 화면에 함께 떠 있는데, `.onChange(of:)`가
        // 그 값을 계속 "관찰"하는 것 자체가(안에서 바로 return하더라도) 이
        // 뷰의 body를 다시 계산하게 만든다 — 결국 빠르게 스크롤하는 동안
        // 화면에 보이지 않는 다른 번역본 페이지들까지 매 절이 중앙을 지날
        // 때마다 다시 그려지는 낭비가 쌓인다. `respondsToSyncEvents == false`면
        // 애초에 `respondToSyncEvent`가 항상 조기 반환하던 것과 정확히 같은
        // 결과이므로, 아래처럼 이 구독 자체를 붙이지 않아도 동작은 전혀
        // 달라지지 않는다 — macOS/iPadOS(`respondsToSyncEvents == true`)는 이
        // 조건 분기의 다른 쪽이라 기존과 완전히 동일하게 계속 구독한다.
        .modifier(SyncEventSubscriptionModifier(
            isEnabled: respondsToSyncEvents,
            coordinator: coordinator,
            onEvent: respondToSyncEvent
        ))
        // [2026-08-08 추가] 아이폰 스와이프 정렬 — 부모가 새 값을 넘기면
        // 애니메이션 없이 즉시 그 절로 맞춘다(탭 전환 자체가 이미 전환
        // 애니메이션이라 추가 애니메이션은 오히려 어색하다).
        .onChange(of: pendingCenterAlignment) { _, newValue in
            guard let newValue else { return }
            centerVerseID = newValue
        }
        // [2026-08-19 추가] 사용자 요청 — "검색 결과중 - 성경구절을 클릭하면
        // 해당하는 절까지 스크롤 이동해서 잠시 하이라이트 표시해줄것."
        // `highlightedVerse`가 새로 설정되면(검색 결과 탭 등) 그 절로 부드럽게
        // 스크롤한다 — 실제 강조 표시(배경색)는 `VerseRow.isHighlighted`가
        // 맡고, 몇 초 뒤 자동으로 꺼지는 타이머는 `BibleReadingViewModel.
        // highlightVerseTemporarily`가 관리한다(여기선 스크롤만 담당).
        .onChange(of: highlightedVerse) { _, newValue in
            guard let newValue else { return }
            withAnimation(.easeInOut(duration: Self.scrollAnimationDuration)) {
                centerVerseID = newValue
            }
        }
        // [2026-08-08 추가] 책/장이 바뀌면(=이 레이블 문자열이 바뀌면) 이전 장의
        // 중앙 절 id를 그대로 들고 있지 않도록 리셋한다 — 안 그러면 새 장에
        // 우연히 같은 절 번호가 있을 때 `.scrollPosition(id:)`가 그 번호로
        // 다시 스크롤해 버려(예: 이전 장 15절을 보다가 다음 장으로 넘겼는데
        // 새 장도 15절이 있으면 그리로 스크롤), 새 장을 항상 맨 위부터 보여줘야
        // 하는 원래 동작과 어긋난다.
        .onChange(of: localizedBookChapterLabel) { _, _ in
            resetForChapterChange()
        }
    }

    /// [2026-09-04 신설] 아이폰 전용 — 위 `columnScrollView` 상단 주석 참고.
    /// `.scrollPosition(id:anchor:)`/`.scrollTargetLayout()` 없이 `ScrollViewReader.
    /// scrollTo(id:anchor:)`(호출 시점 1회만 이동, 스크롤 중 실시간 추적 없음)로
    /// "검색 이동/장 리셋/페이지 스와이프 정렬"을 그대로 구현한다. "지금 중앙에
    /// 가까운 절"이 필요한 유일한 소비처(페이지 전환 시 다음 페이지 정렬용
    /// 디바운스 보고, `reportCenterVerseIfNeeded` 참고)는 각 절이 뷰포트에
    /// "나타나는" 순간(`.onAppear` — 스크롤 중 매 프레임이 아니라 그 절이 화면에
    /// 들어오는 딱 그 순간에만 한 번)의 값으로 근사한다 — 정확히 "중앙"은
    /// 아니고 "마지막으로 화면에 들어온 절" 기준이라 근사치이지만, 페이지 전환
    /// 시 "대략 그 근처로" 맞추는 기존 목적엔 충분하고 스크롤 중 실시간 비용은
    /// 전혀 들지 않는다.
    private var columnScrollViewPhoneLightweight: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: CGFloat(settings.bibleVerseSpacing)) {
                    ForEach(verses, id: \.verse) { verse in
                        verseRowView(for: verse, onRowAppear: { reportCenterVerseIfNeeded($0) })
                    }
                }
                .padding()
            }
            // [2026-09-04 수정] 장 북마크 세로선은 이제 `body` 상단(제목+본문
            // 전체) 배경 한 곳에서만 그린다 — 위 `columnScrollViewSyncTracking`의
            // 같은 수정 참고.
            .onAppear {
                if let highlightedVerse {
                    // ⚠️ [2026-09-04 신설, 버그 수정] 사용자 실측 —
                    // "기본번역본 x절 -> 영어번역본 x-1절 -> 다시 기본번역본
                    // x-2절..."처럼 페이지를 스와이프할 때마다 한 절씩 밀렸다.
                    // 원인: `proxy.scrollTo`가 실행되는 동안에도 스크롤 경로에
                    // 있는 절들의 `.onAppear`(위 `verseRowView`의
                    // `onRowAppear`)가 연쇄로 fire되는데, 이걸 "사용자가 실제로
                    // 스크롤해서 지나간 절"로 착각해 `reportCenterVerseIfNeeded`가
                    // 그대로 코디네이터에 재보고해 버렸다 — 다음 페이지 전환 때
                    // 이 잘못된 값을 그대로 돌려받는 게 반복되며 누적됐다.
                    // `reportCenterVerseIfNeeded`엔 원래 `isProgrammaticScroll`
                    // 가드가 있었지만(macOS/아이패드 팔로워 전용으로만 켜졌다),
                    // 아이폰의 이 프로그램적 스크롤 경로들에서는 켠 적이 없어서
                    // 놓쳤다 — 아래 `beginProgrammaticScrollPhone()`으로
                    // 통일해서 켠다.
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

    /// [2026-09-04 신설] 위 `columnScrollViewSyncTracking`/`columnScrollViewPhoneLightweight`
    /// 상단 주석 참고 — 절 한 행을 실제로 구성하는 부분(VerseRow 생성 + 탭/컨텍스트
    /// 메뉴 + 난외주 목록)은 두 플랫폼이 완전히 같아 여기 하나로 모았다.
    /// `onRowAppear`는 아이폰 쪽(`columnScrollViewPhoneLightweight`)만 넘긴다 —
    /// macOS/아이패드(`columnScrollViewSyncTracking`)는 인자 없이 호출해 아래
    /// 조건문의 `else` 분기(추가 modifier 없음)를 타므로, 그 쪽 렌더링 결과는
    /// 이번 수정 전과 완전히 동일하다.
    @ViewBuilder
    private func verseRowView(for verse: BibleVerse, onRowAppear: ((Int) -> Void)? = nil) -> some View {
        // [2026-09-04 변경] 사용자 보고 — "구절을 탭해 선택/해제할
        // 때 절 텍스트 위치가 살짝 움직임." 원인: 아래 난외주
        // 목록(`marginalNoteFootnoteList`)이 예전엔 `VerseRow`
        // 자신의 카드 안에서 선택 시에만 펼쳐졌다 — 그 절 카드
        // 자체의 높이가 바뀌면서, `.scrollPosition(id:anchor:
        // .center)`가 그 높이 변화를 보정하는 과정에서 카드 상단
        // (=절 텍스트)이 위로 밀렸다. 한 번만 계산해 `VerseRow`와
        // 아래 별도 형제 항목이 같은 값을 공유한다(불필요한 중복
        // 조회 방지).
        let marginalNotes = marginalNotesProvider(verse.verse)
        let row = VerseRow(
            verse: verse,
            isHighlighted: verse.verse == highlightedVerse,
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
            // [2026-08-15 재작성, 이후 보조키 변경] 사용자 요청 3가지 —
            // ① 일반 클릭: 선택을 "추가"가 아니라 "교체"한다.
            // ② Shift/Cmd 클릭: 마지막 기준 절부터 이 절까지 범위 선택.
            // ③ Option 클릭: 이 절 하나만 선택 목록에 추가/제거(개별
            //   다중 선택), 나머지 선택은 그대로 유지.
            //
            // ⚠️ [변경 이력] 원래는 ③을 Control 클릭으로 구현했으나,
            // macOS에서 Control+클릭은 관례적으로 "두 번째 클릭"(컨텍스트
            // 메뉴 열기)으로 OS/AppKit이 먼저 가로챌 수 있어 — 바로 아래
            // `.contextMenu`와 충돌할 위험이 있었다. 사용자 요청으로
            // Option 키로 교체했다 — Option 클릭은 그런 시스템 예약
            // 의미가 없어 같은 문제가 없다.
            //
            // 수식키 감지는 `NSEvent.modifierFlags`(macOS 전용, 클래스
            // 프로퍼티를 그냥 읽기만 하는 표준 AppKit API)를 쓴다 —
            // 시스템 전역 이벤트를 감시하는 `NSEvent.
            // addGlobalMonitorForEvents`나 `CGEventTap`과 달리, 이 앱
            // 자신의 클릭 처리 도중 "지금 눌려 있는 수식키가 뭔지"만
            // 물어보는 것이라 손쉬운 사용(접근성) 권한이 전혀 필요
            // 없다 — 사용자가 요청 마지막에 건 조건("손쉬운 사용을
            // 활성화해야 하는 기능이면 구현하지 말 것")에 해당하지
            // 않는다.
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
                // [2026-08-21 수정] 사용자 요청("아이패드 수정사항") —
                // "한번 탭하면 선택, 탭한 구절을 탭하면 탭취소.
                // 여러구절 탭 = 여러구절 선택." 예전엔 iOS/iPadOS
                // 터치에 수식키 신호가 없다는 이유로 항상 "교체"
                // 선택(onSelectSingleVerse)만 지원했다 — 이제 macOS의
                // Option+클릭과 같은 의미인 onToggleVerseSelection
                // (선택 추가/제거, 다른 절 선택은 유지)을 기본 탭
                // 동작으로 쓴다. 이 요청은 "아이패드 수정사항" 목록
                // 안에 있고 "(맥OS, iOS 공통)" 표기가 없어, macOS 쪽
                // 분기(위, 2026-08-15 설계)는 그대로 둔다 — 기존
                // 수식키 기반 3단 구분(일반 클릭=교체/Shift·Cmd=범위/
                // Option=개별 토글)을 건드리지 않는다.
                onToggleVerseSelection(verse.verse)
                #endif
            }
            .contextMenu {
                Button {
                    onCreateMemo(verse)
                } label: {
                    // [2026-08-11 수정] 사용자 요청 — "메모의 이름을
                    // [개인 주석]으로 변경." 확대보기 액션바와 같은
                    // 절 전체 메모(UserMemo, rangeStart 없음)를 만드는
                    // 경로라 동일하게 이름을 맞춘다.
                    // [2026-08-12 변경] "개인 주석" → "개인 묵상".
                    Label("개인 묵상 작성", systemImage: "square.and.pencil")
                }
                // [2026-08-26 신설] 사용자 요청 — iOS 길게 프레스/
                // macOS 오른쪽버튼 메뉴에 [선택] 추가("일부 텍스트를
                // 선택하여 복사할 수 있는 기능"). [복사](바로 아래)가
                // "번역본 전체"라면, 이건 "그 안에서 일부만" —
                // `VerseTextSelectionPopover`(호출부가 여는 작은
                // 팝오버/시트)에서 실제 드래그 선택이 이뤄진다.
                Button {
                    onSelectPartialText(verse, translationDisplayName)
                } label: {
                    Label("선택", systemImage: "character.cursor.ibeam")
                }
                // [2026-08-26 신설] 사용자 요청 — iOS 길게 프레스/
                // macOS 오른쪽버튼 메뉴에 [복사] 추가("해당 번역본만
                // 복사 -> 클릭하면 toast 메세지"). 위 `onCopySingleTranslation`
                // 상단 주석 참고 — 이 컬럼의 `translationDisplayName`과
                // 지금 행의 `verse`(이 번역본만의 내용)를 그대로
                // 넘긴다.
                Button {
                    onCopySingleTranslation(verse, translationDisplayName)
                } label: {
                    Label("복사", systemImage: "doc.on.doc")
                }
            }

        // [2026-09-04 신설] 아이폰 전용 실시간 추적 대체 — 위
        // `columnScrollViewPhoneLightweight` 상단 주석 참고. `onRowAppear`가
        // 없으면(macOS/아이패드) 이 절이 추가 없이 그대로 그려져, 이번 수정
        // 전과 렌더링 결과가 완전히 같다.
        if let onRowAppear {
            row.onAppear { onRowAppear(verse.verse) }
        } else {
            row
        }

        // [2026-09-04 신설] 위 `marginalNotes` 지역 변수 상단 주석
        // 참고 — 난외주 목록을 `VerseRow`의 카드 밖, 별도 형제
        // 항목으로 뺐다. `VerseRow`(`.id(verse.verse)`)는 선택
        // 여부와 무관하게 항상 같은 높이를 유지하므로, 이 절이
        // 지금 화면 중앙 정렬 대상이어도 더 이상 위로 밀리지
        // 않는다 — 대신 이 목록은 자신만의 `.id`를 가진 완전히
        // 별도 항목이라, 절 카드와 같은 배경/모서리를 공유하지
        // 않고 살짝 떨어진 블록으로 보인다.
        if selectedVerses.contains(verse.verse), !marginalNotes.isEmpty {
            MarginalNoteFootnoteList(notes: marginalNotes)
                .id("\(verse.verse)-marginalNotes")
        }
    }

    /// 리더 역할 — `.scrollPosition(id:)`가 스크롤에 맞춰 읽어 준 "지금 중앙 절"을
    /// 코디네이터에 보고한다. 프로그램적으로(팔로워로서) 스크롤하는 중에는 건너뛴다.
    /// [2026-09-04 신설] macOS/아이패드(`columnScrollViewSyncTracking`)는 기존과
    /// 똑같이 `.onChange(of: centerVerseID)`에서 호출한다. 아이폰
    /// (`columnScrollViewPhoneLightweight`)은 더 이상 `centerVerseID`를 쓰지
    /// 않는 대신, 각 절이 뷰포트에 나타날 때(`verseRowView`의 `onRowAppear`)
    /// 이 함수를 그 절 번호로 직접 호출한다 — 함수 내부 로직(디바운스 등)은
    /// 손대지 않았다.
    private func reportCenterVerseIfNeeded(_ verse: Int?) {
        guard !isProgrammaticScroll, let verse else { return }
        // [2026-09-04 신설] 위 `phoneReportWorkItem` 상단 주석 참고 — 아이폰은
        // 실시간 구독자가 없으므로 즉시 보고 대신 짧게 디바운스한다.
        guard !respondsToSyncEvents else {
            coordinator.reportCenterVerse(verse, columnID: columnID)
            return
        }
        // [2026-09-04 신설] 위 `hasAdditionalDisplayedColumns` 상단 주석
        // 참고 — 맞춰 줄 다른 컬럼(페이지)이 없으면 디바운스 예약조차
        // 하지 않고 그냥 생략한다.
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

        // [2026-08-07 수정] addendum.md 3장이 명시한 패턴 — 이전에 예약해 둔 가드
        // 해제 작업이 아직 실행 전이면 취소하고 새로 예약한다. 동기화 이벤트가
        // 애니메이션 지속 시간보다 짧은 간격으로 연달아 들어오면(빠른 스크롤 등),
        // 먼저 예약된 타이머가 뒤이은 애니메이션이 진행 중인데도 가드를 풀어버려
        // 팔로워가 스스로를 리더로 착각하는 경합이 생길 수 있었다 — 매번 취소 후
        // 재예약하면 "가장 마지막 애니메이션이 끝난 뒤"에만 가드가 풀린다.
        guardReleaseWorkItem?.cancel()

        isProgrammaticScroll = true
        withAnimation(.easeInOut(duration: Self.scrollAnimationDuration)) {
            centerVerseID = target
        }
        let releaseWorkItem = DispatchWorkItem {
            isProgrammaticScroll = false
        }
        guardReleaseWorkItem = releaseWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scrollAnimationDuration, execute: releaseWorkItem)
    }

    private func resetForChapterChange() {
        guardReleaseWorkItem?.cancel()
        // [2026-09-04 신설] 위 `phoneReportWorkItem` 상단 주석 참고 — 장이
        // 바뀌는 순간 이전 장의 디바운스된 보고가 뒤늦게 나가 새 장의 첫
        // 스크롤 위치를 엉뚱하게 흔들지 않도록 예약된 작업을 취소한다.
        phoneReportWorkItem?.cancel()
        isProgrammaticScroll = false
        // [2026-08-19 추가] 관주/검색 결과로 "다른 장으로 이동 + 특정 절 강조"가
        // 동시에 일어나는 경우(`highlightedVerse`가 이미 새 값으로 설정된 채
        // 이 장 전환이 일어남) — 여기서 무조건 첫 절로 되돌리면, 곧이어 그 절로
        // 맞출 `centerVerseID`가 초기화되며 스크롤이 무효화될 수 있다. 이때는
        // 리셋을 건너뛴다 — 장이 바뀌었어도 `.onChange(of: highlightedVerse)`가
        // 올바른 절로 맞춰준다. `highlightedVerse`는 이미 최종값으로 설정된
        // 뒤에야 뷰가 다시 그려지므로(같은 뷰모델 메서드 안에서 순서대로
        // 대입), 이 두 onChange 중 어느 게 먼저 실행되는지와 무관하게 안전하다.
        guard highlightedVerse == nil else { return }
        // [2026-09-01 수정] 사용자 보고 — "이전장/다음장 버튼, 장 숫자만 입력한
        // 검색, 장 선택 버튼으로 장을 바꿨을 때 스크롤이 초기화되지 않고 이전
        // 위치를 유지함." 예전엔 여기서 `centerVerseID = nil`로만 되돌렸는데,
        // `.scrollPosition(id:)`는 "리더"(스크롤에 맞춰 값을 읽어만 줌) 겸
        // "팔로워"(값을 대입하면 그 절로 실제로 스크롤도 해 줌) 역할을 하는
        // 바인딩이라(위 `centerVerseID` 선언부 주석 참고), `nil`을 대입하는 것은
        // "추적을 잠깐 놓는 것"에 가깝고 "1절로 스크롤하라"는 팔로워 동작을
        // 명령하지 않는다 — 그 결과 화면은 이전 장의 스크롤 위치(픽셀 오프셋)에
        // 그대로 남아 있을 수 있다. `respondToSyncEvent`(바로 위)가 이미
        // 증명하듯, 팔로워로서 실제로 스크롤을 이동시키려면 구체적인 절 번호를
        // 대입해야 한다 — 그래서 새 장의 첫 절(`verses.first?.verse`, 정상적인
        // 성경 장은 항상 1절부터 시작하지만 하드코딩된 1 대신 실제 데이터를
        // 그대로 쓴다)을 대입해 화면이 확실히 맨 위(1절)로 스크롤되게 한다.
        centerVerseID = verses.first?.verse
    }

    /// [2026-09-04 신설] 아이폰 전용 — 위 `columnScrollViewPhoneLightweight`
    /// 상단 주석 참고. 기존 `resetForChapterChange()`(macOS/아이패드,
    /// `centerVerseID` 대입)와 같은 원칙이되, `.scrollPosition` 바인딩이 없어
    /// `proxy.scrollTo`로 직접 1절까지 이동한다.
    private func resetForChapterChangePhone(proxy: ScrollViewProxy) {
        guardReleaseWorkItem?.cancel()
        phoneReportWorkItem?.cancel()
        isProgrammaticScroll = false
        guard highlightedVerse == nil else { return }
        if let firstVerse = verses.first?.verse {
            // [2026-09-04 신설] 위 `columnScrollViewPhoneLightweight`의
            // `.onAppear` 상단 주석 참고 — 같은 이유로 여기도 재보고를 막는다.
            beginProgrammaticScrollPhone()
            proxy.scrollTo(firstVerse, anchor: .center)
        }
    }

    /// [2026-09-04 신설] 아이폰 전용 — 위 `columnScrollViewPhoneLightweight`의
    /// `.onAppear` 상단 주석 참고. `proxy.scrollTo`가 유발하는 연쇄
    /// `.onAppear`를 "사용자가 실제로 스크롤한 것"으로 잘못 보고하지 않도록,
    /// macOS/아이패드 팔로워(`respondToSyncEvent`)가 쓰던 것과 같은
    /// `isProgrammaticScroll` 가드를 프로그램적 스크롤 직전에 켠다(잠시 뒤
    /// 자동으로 풀림) — `reportCenterVerseIfNeeded` 맨 위의
    /// `guard !isProgrammaticScroll`이 이 가드를 그대로 활용한다.
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

/// [2026-09-04 신설] 사용자 요청 — "장을 북마크 설정할 때 왼쪽에 생기는 세로
/// 라인을 좀더 굵게, 그리고 스크롤 맨 아래(성경 화면 끝)에서 세로 라인의
/// 마무리를 바닥 가운데를 V자로 파낸 리본 모양으로 할 수 있는가?" 위
/// `TranslationColumnView.columnScrollViewSyncTracking`/
/// `columnScrollViewPhoneLightweight`가 이 도형을 `.background(alignment:
/// .leading)`로 이 화면(ScrollView) "자체"의 배경에 붙이므로, 여기서 받는
/// `rect`의 높이는 스크롤되는 내용 전체 길이가 아니라 화면에 실제로 보이는
/// 뷰포트 높이다 — 즉 아래 V자 노치는 스크롤 위치와 무관하게 항상 "성경
/// 화면 맨 아래"에서 그려진다(사용자 요청 그대로).
///
/// 상단은 기존과 같은 둥근 캡(반원, `rect.width / 2`)을 그대로 쓰고, 하단만
/// 가운데를 `notchDepth`만큼 위로 파고들게 잘라 좌우 두 갈래(리본 꼬리)로
/// 갈라지게 한다 — 리본/제비꼬리 깃발과 같은 원리다.
private struct ChapterBookmarkRibbonShape: Shape {
    /// 하단 V자 노치가 파고드는 깊이. 호출부의 막대 폭(10pt)에 맞춰 고른
    /// 값 — 폭이 나중에 바뀌면 이 값도 함께 조정해야 비율이 어색해지지
    /// 않는다.
    /// [2026-09-04 수정] 사용자 요청 — "제비꼬리 모양이 좀 덜 날카롭게, 각도가
    /// 덜 예리하도록." 값이 클수록 V자 노치가 더 깊이 파고들어(제비꼬리 자체는
    /// 그대로 바닥까지 닿는 채로) 꼭짓점 각도가 좁아진다 — 12 → 6으로 줄여
    /// 노치를 절반만큼 얕게 만들어 각도를 넓혔다(꼭짓점 각도 기준 약 29° →
    /// 약 55°).
    var notchDepth: CGFloat = 6

    /// [2026-09-04 수정] 사용자 요청 — "세로선을 번역본/성경 장이 타이틀로
    /// 나오는 상단영역까지 표시를 할 것 + 상단 모서리를 둥근 모서리가 아닌
    /// 각진 모서리로 할 것." 이 라인이 이제 컬럼 맨 위(제목 영역)부터
    /// 시작하므로, 예전의 둥근 캡(반원 `addArc` 두 번)은 더 이상 "책갈피
    /// 탭" 모양이 아니라 어색한 빈 공백처럼 보인다 — 상단은 단순 직선
    /// (사각형)으로 바꾸고, 하단 V자 노치는 그대로 둔다.
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        // 뷰 높이가 노치보다 작아지는 극단적인 경우(예: 레이아웃 계산 중
        // 순간적으로 아주 작은 높이가 배정될 때) 노치가 상단까지 파고들지
        // 않도록 안전 상한을 둔다.
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

/// [2026-09-03 신설] 위 `TranslationColumnView.columnScrollView`의 `.onChange`
/// 교체 주석 참고 — `isEnabled`가 false(아이폰)면 `.onChange(of:)` 자체를 붙이지
/// 않아, `coordinator.latestEvent`가 바뀔 때마다 이 뷰의 body가 재계산되는 것을
/// 원천적으로 막는다. `isEnabled`가 true(macOS/iPadOS)면 기존과 동일하게 매번
/// 구독해 `onEvent`를 그대로 부른다 — 동작 자체는 손대지 않았다.
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

/// [2026-09-04 신설] 사용자 보고 — "구절을 탭해 선택/해제할 때 절 텍스트
/// 위치가 살짝 움직임" 수정의 일부 — 원래 `VerseRow` 안의 계산 프로퍼티
/// (`marginalNoteFootnoteList`)였던 것을 별도 형제 뷰로 뺐다(`TranslationColumnView.
/// columnScrollView`의 `ForEach` 참고). `VerseRow` 자신의 카드 높이가 절
/// 선택 여부와 무관하게 항상 고정되게 하기 위함 — 본문 안 위첨자와 같은
/// 번호(`note.markerText`, 원본 `<SUP>` 태그 글자를 그대로 쓴다 — 앱이
/// 임의로 재부여하지 않는다, `VerseMarginalNote.markerText` 주석 참고)를
/// 그대로 나열한다.
private struct MarginalNoteFootnoteList: View {
    let notes: [VerseMarginalNote]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                Text("\(note.markerText ?? "") \(note.noteText)")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        // 절 번호 칸(`VerseRow`의 `.frame(minWidth: 20)` + HStack spacing 8)만큼
        // 들여써서 본문 시작 위치와 대략 맞춘다 — 별도 형제 항목이 됐어도
        // 시각적으로는 여전히 그 절에 속한 것처럼 보이게 한다.
        .padding(.leading, 28)
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
    }
}

private struct VerseRow: View {
    let verse: BibleVerse
    let isHighlighted: Bool
    /// [2026-08-08 추가] 클립보드 복사용으로 선택된 절인지 — `isHighlighted`(검색
    /// 결과 등에서 잠깐 스크롤 이동 대상이 됐다는 표시)와는 별개 개념이다.
    let isSelected: Bool
    /// [2026-09-04 신설] 사용자 요청 — "책갈피를 설정하면 성경 본문 절번호
    /// 왼쪽에 길게 갈피실 색상으로 세로라인을 그어줄 수 있는가?" 절 하나를
    /// 정확히 가리키는 책갈피가 있는지(위 `TranslationColumnView.
    /// isBookmarkedProvider` 참고) — 아래 `body`의 절 번호 칸 왼쪽에 세로선을
    /// 그릴지 결정한다.
    var isBookmarked: Bool = false
    /// [2026-08-08 추가] 이 절(이 컬럼의 번역본 기준)에 걸린 구간 주석 — 전부
    /// 이미 필터링된 상태로 들어온다(`TranslationColumnView.highlightsProvider`
    /// 등 상단 주석 참고).
    var highlights: [VerseHighlight] = []
    var crossReferences: [VerseCrossReference] = []
    var phraseMemos: [UserMemo] = []
    /// [2026-08-11 추가] "메모"(신규, 드래그 표현 부연설명) — 사용자 요청 —
    /// "메인창에서도 메모가 있는 구절의 특정표현은 확대보기에서처럼 글자색을
    /// 다르게 표현하도록." 형광펜과 같은 원칙으로 이미 필터링된 상태로 들어온다.
    var phraseNotes: [VersePhraseNote] = []
    /// [2026-08-14 추가] 난외주(단어 뜻풀이/구약 인용 출처) — 관주와 같은 원칙,
    /// 위 `TranslationColumnView.marginalNotesProvider` 상단 주석 참고.
    var marginalNotes: [VerseMarginalNote] = []
    /// [2026-08-14 추가] 절 단위 한자 주석 — 위 `TranslationColumnView.
    /// hanjaWordsProvider` 상단 주석 참고.
    var hanjaWords: [HanjaWordAnnotation] = []
    /// [2026-08-11 추가] "관련 내용" — 관주/메모와 같은 원칙, 위
    /// `TranslationColumnView.verseMentionsProvider` 상단 주석 참고.
    var verseMentions: [VerseMention] = []
    var onSelectCrossReferenceTarget: (BibleVerseRef) -> Void = { _ in }
    var onSelectPhraseMemo: (UserMemo) -> Void = { _ in }
    var onSelectVerseMention: (VerseMention) -> Void = { _ in }
    /// [2026-09-02 신설] 위 `TranslationColumnView.inlineAnnotatedContentProvider`
    /// 상단 주석 참고 — 그대로 전달받아 아래 `verseContentText`가 쓴다.
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

    // [2026-08-08 추가] 환경설정 "모양" 탭의 S1 표시 설정(본문 크기/색상/절 번호
    // 크기/줄간격/글꼴)을 그대로 반영한다 — 이전에는 `.font(.body)`/`.font(.caption)`
    // 고정값이었다. `@Observable`이라 이 값이 바뀌면(설정 화면에서 즉시) 이 행도
    // 자동으로 다시 그려진다.
    private var settings: UserSettingsStore { .shared }

    var body: some View {
        // [2026-08-15 추가] 사용자 요청 — "성경구절 클릭했을 때 - 성경구절
        // 밑으로 난외주 숫자순서대로 뜻을 표시할 것." 이 절 아래에 각주
        // 목록을 끼워 넣어야 해서, 기존엔 이 뷰의 최상위였던 `HStack`(절
        // 번호 칸 + 본문)을 `VStack`으로 한 겹 감쌌다 — 배경/테두리/선택
        // 표시줄은 전부 이 바깥 `VStack`으로 옮겨서, 각주 목록도 같은 카드
        // 안(같은 배경색·모서리)에 포함되게 한다.
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
            // [2026-09-04 신설] 사용자 요청 — "책갈피를 설정하면 성경 본문
            // 절번호 왼쪽에 길게 갈피실 색상으로 세로라인을 그어줄 수
            // 있는가?" 너비만 정하고 높이는 지정하지 않는다 — `RoundedRectangle`은
            // 기본적으로 남는 공간을 다 채우려 하므로, 이 `HStack`의 다른
            // 자식(절 번호/아이콘 칸, 본문) 중 더 큰 쪽 높이에 자동으로
            // 맞춰진다(여러 줄로 감기는 절일수록 선도 함께 길어진다). 절
            // 선택 시 왼쪽에 그리는 강조색 세로선(아래 `.overlay` 참고)과는
            // 서로 다른 자리(그건 카드 바깥쪽 가장자리)라 겹치지 않는다.
            if isBookmarked {
                RoundedRectangle(cornerRadius: 1.25)
                    .fill(JBCHCategoryPalette.wine)
                    .frame(width: 2.5)
            }
            // [2026-08-09 수정] 사용자 요청 — "메모 아이콘, 관주아이콘 위치를
            // 절 번호 밑에 세로로 배치하여 차지하는 영역을 줄일 수 있도록 할
            // 것." 이전엔 두 아이콘이 절 번호·본문과 나란히(가로로) 놓여
            // 줄바꿈된 본문 옆 가로 공간을 계속 차지했다(스크린샷 — 절 3처럼
            // 본문이 여러 줄로 감기면 아이콘이 중간 줄 옆에 끼어 어색하게
            // 보임). 절 번호 칸 자체를 세로 스택으로 바꿔 번호 아래에 아이콘을
            // 쌓아, 본문이 쓸 수 있는 가로 폭을 아이콘 너비만큼 돌려준다.
            VStack(alignment: .center, spacing: 3) {
                // [2026-09-02 수정] 사용자 요청 — "각 구절별 왼쪽 끝 절번호,
                // 아이콘 색상도 테마색상/글자색 변경에 맞춰 바뀌어야 함."
                Text("\(verse.verse)")
                    .font(settings.bibleVerseNumberFont)
                    .foregroundStyle(settings.bibleTextColor ?? .secondary)

                // [2026-08-08 추가] 관주 마커 — 인쇄본처럼 본문 글자 사이에
                // 정확히 끼워 넣지는 못한다(SwiftUI `Text(AttributedString)`은
                // 구간별로 탭 제스처를 따로 걸 수 없다, README "이어서 16"
                // 설계 논의에서 이미 확인한 제약). 대신 절 번호 아래에 작은
                // 아이콘을 붙여 같은 기능(연결된 구절 확인 + 이동)을 제공한다.
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

                // [2026-08-14 추가] 난외주 마커 — 관주 아이콘과 같은 이유(본문
                // 글자 사이에 정확히 끼워 넣지 못하는 제약)로 같은 자리에 아이콘을
                // 붙인다. `MarginalNoteSeedImporter.swift` 상단 주석 참고.
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

                // [2026-08-15 삭제, 절 선택 방식으로 교체] "탭하면 보기" 아이콘 +
                // 팝오버(단어 목록 + 훈음)가 여기 있었다 — 사용자 요청 "한자
                // 주석표시: 탭하면 보기 - 구절을 선택하면 해당 구절만 국한문
                // 혼용으로 표시"로 교체했다. 이제 이 절 번호 칸의 아이콘 대신,
                // 이미 있던 절 선택 상태(`isSelected`, 클립보드 복사용으로 절
                // 전체를 탭하면 켜지는 그 토글 — `TranslationColumnView.
                // columnScrollView`의 `.onTapGesture` 참고)를 그대로 재사용해
                // "탭하면 보기" 모드에서 선택된 절만 국한문 혼용으로 보이게
                // 한다(아래 `shouldShowInlineHanja`/`verseContentText` 참고).
                // 한자 뜻(훈음)은 더 이상 이 화면의 팝오버가 아니라 확대보기
                // (`VerseZoomView`)의 별도 "한자 뜻풀이" 영역에서 본다.

                // [2026-08-11 추가] "관련 내용" — 관주/메모 아이콘과 같은 자리에
                // 세 번째로 쌓는다(위 `verseMentionsProvider` 상단 주석 참고).
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
            // [2026-09-04 삭제, 이동] 난외주 목록(`marginalNoteFootnoteList`)이
            // 여기 있었다 — 절 선택(`isSelected`) 시 이 카드 안에서 펼쳐지며
            // 카드 높이를 바꿔, 이 절이 화면 중앙 정렬 대상일 때 절 텍스트가
            // 위로 밀리는 문제(사용자 보고)가 있었다. 카드 높이가 선택 여부와
            // 무관하게 항상 고정되도록, `TranslationColumnView.columnScrollView`의
            // `ForEach` 쪽에서 이 카드와 완전히 분리된 형제 항목
            // (`MarginalNoteFootnoteList`, 그 struct 상단 주석 참고)으로 뺐다.
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        // [2026-09-04 수정, 스크롤 성능] 사용자 요청 — Time Profiler로 확인된
        // Core Animation 커밋 비용 절감 시도. `.background(color)` 뒤에
        // `.clipShape(RoundedRectangle)`를 따로 거는 대신, 배경 채우기와
        // 모양을 한 번에 지정하는 `.background(_:in:)`로 합쳤다 — Apple
        // WWDC "Demystify SwiftUI performance" 권고: 이 조합은 별도 클립
        // (마스킹) 레이어 없이 배경을 그 모양으로 바로 그려서, 절 하나당
        // (그리고 스크롤 prefetch로 미리 만들어지는 절 수만큼) 레이어를
        // 하나씩 줄인다. ⚠️ 차이점: 기존 `.clipShape`는 배경뿐 아니라 이
        // 카드의 실제 내용(절 번호/아이콘/본문 텍스트)까지 둥근 모서리
        // 바깥으로 나가지 않게 잘라냈지만, 이 카드의 내용은 이미 위
        // `.padding`으로 안쪽에 들어와 있어 둥근 모서리 밖으로 나갈 일이
        // 없다 — 시각적으로 동일해야 한다.
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) {
            // 배경 틴트만으로는 라이트 모드에서 눈에 잘 안 띌 수 있어, 선택된
            // 절에는 왼쪽에 강조색 세로선을 하나 더 그어 명확히 한다.
            if isSelected {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 2)
            }
        }
    }

    /// [2026-08-15 신설] 사용자 요청 — "한자 주석표시: 탭하면 보기 - 구절을
    /// 선택하면 해당 구절만 국한문 혼용으로 표시." "항상 보기"는 절 선택과
    /// 무관하게 전부, "탭하면 보기"는 이 절이 지금 선택된 경우에만 켠다(선택
    /// 상태 자체는 새로 만들지 않고 기존 클립보드 복사용 `isSelected`를 그대로
    /// 재사용 — 위 아이콘 삭제 주석 참고). "끄기"는 항상 false.
    private var shouldShowInlineHanja: Bool {
        guard !hanjaWords.isEmpty else { return false }
        switch settings.hanjaDisplayMode {
        case .alwaysInline: return true
        case .tapToReveal: return isSelected
        case .off: return false
        }
    }

    /// [2026-08-15 신설] 사용자 요청 — "난외주가 있으면 해당 단어 위첨자 숫자
    /// 추가." 한자 인라인과 달리 표시 모드 설정과 무관하게, 이 절에 난외주가
    /// 하나라도 있으면 항상 위첨자를 보여준다(관주/난외주 아이콘이 "있으면
    /// 항상 보임" 원칙을 따르는 것과 같은 이유 — 사용자가 켜고 끄는 전역
    /// 설정이 아니다).
    private var shouldShowMarginalNoteMarkers: Bool {
        marginalNotes.contains { $0.anchorOffset != nil }
    }

    /// 형광펜/표시가 하나도 없으면(대다수 절) 기존과 똑같은 평범한 `Text`를
    /// 그대로 쓴다 — `VerseAnnotationRenderer`가 nil을 돌려주는 경로, AttributedString
    /// 변환 비용조차 들지 않는다.
    @ViewBuilder
    private var verseContentText: some View {
        // [2026-08-14 수정] 사용자 재요청 — "구절 번호 앞이 아니라, 절 텍스트 맨
        // 앞으로 하고, ¶가 아니라 ●." 처음엔 절 번호 뒤에 ¶를 붙였다가, 절 본문
        // 맨 앞에 ●로 바꿨다. `VerseAnnotationRenderer.attributedContent`에
        // 넘기는 `text`는 여전히 원본 `verse.content` 그대로 둔다 — 형광펜/구절별
        // 메모의 `rangeStart`/`rangeEnd`가 그 원본 문자열 기준 UTF-16 오프셋으로
        // DB에 저장돼 있어서, 앞에 문자를 끼워 넣으면 오프셋이 밀려 엉뚱한 위치에
        // 형광펜/메모가 표시되는 회귀가 생긴다. 그래서 문단표는 별도 `Text`로
        // 만들어 `+`로 앞에 이어 붙인다(SwiftUI `Text`끼리는 `+`로 합칠 수 있고,
        // 각자 스타일을 따로 유지한 채 한 줄에 흐른다) — 원본 문자열 자체는
        // 건드리지 않는다.
        // [2026-08-14 추가, 2026-08-15 조건 확장] 국한문 혼용(인라인 한자)과
        // 난외주 위첨자 표시 — 둘 중 하나라도 있으면 형광펜/메모 유무와
        // 무관하게 항상 AttributedString 경로를 탄다(단어 뒤/앞에 텍스트를
        // 끼워 넣어야 하므로). `VerseAnnotationRenderer.
        // attributedContentWithInlineAnnotations` 상단 주석 참고 — 원본
        // `verse.content` 자체는 여전히 손대지 않는다(표시 시점에만 조합).
        // 한자는 "항상 보기"면 모든 절, "탭하면 보기"면 `shouldShowInlineHanja`가
        // 이 절의 선택 여부(`isSelected`)까지 함께 본다(위 아이콘 삭제 주석
        // 참고) — 난외주 위첨자는 그런 전역 토글이 없어 있으면 항상 켠다
        // (`shouldShowMarginalNoteMarkers`). 한자 파라미터는 `shouldShowInlineHanja`
        // 가 false일 때 빈 배열을 넘겨, 위첨자만 필요한 경우에 한자 괄호까지
        // 끼어들지 않게 한다.
        // [2026-09-04 통합, 스크롤 성능 개선] 사용자 보고 — "스크롤이 뻑뻑한
        // 느낌이 있음." 원인 — 바로 위 분기(한자/난외주 있는 절)만
        // `inlineAnnotatedContentProvider`(캐시됨)를 타고, 형광펜/표시/구절
        // 메모만 있는 절(더 흔한 케이스)은 `VerseAnnotationRenderer.
        // attributedContent`를 캐시 없이 직접 호출했다 — 스크롤 중
        // `centerVerseID`가 바뀔 때마다 `TranslationColumnView.body`가
        // 재평가되며 화면에 보이는 `VerseRow`가 전부 다시 만들어지는데, 이
        // 형광펜 절들은 그때마다 구간 계산을 처음부터 다시 했다.
        // `attributedContentWithInlineAnnotations`는 내부적으로
        // `attributedContent`를 그대로 감싸 쓰고 한자/난외주 삽입 대상이
        // 없으면 삽입 루프가 그냥 통과되므로, 형광펜/메모만 있는 절도 같은
        // 결과를 낸다 — 두 조건을 하나로 합쳐 항상 캐시를 거치게 했다(기존
        // 두 분기의 `Text` 조립 로직이 완전히 같아 중복 코드도 사라진다).
        if shouldShowInlineHanja || shouldShowMarginalNoteMarkers || !highlights.isEmpty || !phraseNotes.isEmpty {
            let attributed = inlineAnnotatedContentProvider(
                verse, highlights, phraseNotes, shouldShowInlineHanja ? hanjaWords : [], marginalNotes,
                platformBodyFont, platformTextColor, platformHanjaFont
            )
            if verse.paragraph != nil {
                // [macOS 26 대응] `Text + Text`(`+` 연산자)가 macOS 26.0부터
                // deprecated로 표시된다 — Apple 권고대로 `Text` 문자열 보간으로
                // 바꿨다. `paragraphMarkText`/`Text(attributed)` 둘 다 이미
                // `Text` 타입이라 각자의 폰트/색 스타일은 그대로 유지된다
                // (`LocalizedStringKey.StringInterpolation`이 `Text` 보간을
                // 지원 — Image를 Text 안에 넣을 때와 같은 메커니즘).
                Text("\(paragraphMarkText)\(Text(attributed))")
            } else {
                Text(attributed)
            }
        } else {
            if verse.paragraph != nil {
                // [macOS 26 대응, 수정] 위 두 분기와 같은 이유로 `+` 대신 `Text`
                // 문자열 보간을 쓰되, 여기서는 스타일이 적용된 `Text`를 먼저
                // 지역 변수로 뽑아 둔다 — Swift는 일반(비-멀티라인) 문자열
                // 리터럴의 `\( ... )` 보간 구문 안에 실제 줄바꿈이 들어가는 것을
                // 허용하지 않는다("Unterminated string literal" 컴파일 에러의
                // 원인이었다). 보간 안에는 줄바꿈 없는 변수 참조 하나만 남긴다.
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

    /// 문단 시작 절의 본문 맨 앞에 붙는 마커(●) — 본문과 같은 폰트/색으로,
    /// 뒤에 오는 절 텍스트(원본 `verse.content`, 오프셋 보존)와는 별개의 `Text`라
    /// 형광펜/구절별 메모 좌표에 영향을 주지 않는다.
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

    /// [2026-08-19 추가] 사용자 요청 — "성경 조회에 표시되는 한자에 조선궁서체
    /// 적용." 인라인 "(한자)" 괄호 표기의 크기는 본문 글꼴과 맞춰야 자연스러워
    /// `platformBodyFont`와 같은 크기를 쓰되, 이름만 `settings.hanjaFontName`을
    /// 따른다 — `settings.hanjaFontName == "System"`이면 본문 글꼴 그대로.
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

    private var crossReferencePopoverContent: some View {
        List(crossReferences.flatMap(\.targets), id: \.self) { target in
            Button(crossReferenceTargetLabel(target)) {
                isCrossReferencePopoverPresented = false
                onSelectCrossReferenceTarget(target)
            }
        }
        .frame(minWidth: 220, minHeight: 160)
    }

    private func crossReferenceTargetLabel(_ target: BibleVerseRef) -> String {
        let name = BooksProvider.shared.book(id: target.bookId)?.nameKo ?? "책 \(target.bookId)"
        return "\(name) \(target.chapter):\(target.verse)"
    }

    /// [2026-08-14 추가] 난외주 팝오버 — 탭할 대상이 없어(단순 텍스트 목록)
    /// `crossReferencePopoverContent`처럼 `Button` 대신 `Text`만 나열한다.
    private var marginalNotePopoverContent: some View {
        List(marginalNotes) { note in
            Text(note.noteText)
        }
        .frame(minWidth: 220, minHeight: 120)
    }

    // [2026-08-15 삭제] 한자 주석 팝오버(단어 목록 + 훈음)가 여기 있었다 — 위
    // "탭하면 보기" 아이콘 삭제 주석 참고. 훈음 표시는 이제 확대보기
    // (`VerseZoomView.hanjaGlossSection`)로 옮겼다.

    private func phraseMemoLabel(_ memo: UserMemo) -> String {
        let trimmed = memo.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(내용 없음)" : trimmed
    }

    /// 선택(복사 대상)이 검색 하이라이트보다 시각적으로 더 뚜렷해야 한다고
    /// 판단했다 — 하이라이트는 "스크롤이 여기로 왔다"는 일시적 안내지만, 선택은
    /// 사용자가 직접 고른 상태라 실수로 놓치면 엉뚱한 절이 복사될 수 있다.
    private var backgroundColor: Color {
        if isSelected { return Color.accentColor.opacity(0.28) }
        if isHighlighted { return Color.accentColor.opacity(0.15) }
        return Color.clear
    }
}

/// macOS 13/iOS 16까지 지원해야 한다면 `ContentUnavailableView`(macOS 14+/iOS 17+
/// 전용)를 못 쓰지만, 이 프로젝트는 이미 SwiftData+CloudKit 스택 때문에 macOS 14+/iOS 17+
/// 이상을 전제하므로 표준 뷰 대신 이 경량 대체 뷰를 써도 무방하다. 다만 시스템 제공
/// `ContentUnavailableView`를 그대로 쓰지 않은 이유는 순전히 이 파일 하나로 텍스트만
/// 간단히 보여주면 충분해서다(불필요한 아이콘/버튼 파라미터를 다루고 싶지 않았음).
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
