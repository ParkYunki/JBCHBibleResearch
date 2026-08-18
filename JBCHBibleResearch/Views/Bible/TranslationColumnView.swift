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
    /// 관주 팝오버에서 대상 구절을 탭했을 때 — 그 책/장으로 이동한다(정확한 절
    /// 위치로 스크롤하는 것까지는 이번 구현 범위 밖, README 참고).
    var onSelectCrossReferenceTarget: (BibleVerseRef) -> Void = { _ in }
    /// 구간 메모 아이콘에서 메모를 골랐을 때 — 기존 "메모 작성" 시트를 그대로 연다.
    var onSelectPhraseMemo: (UserMemo) -> Void = { _ in }
    /// [2026-08-11 추가] "관련 내용" 목록에서 항목을 골랐을 때 — 메모는 편집기
    /// 시트로, 연구문서는 PDF 검색+이동 창으로 연다(호출부 BibleReadingView 책임).
    var onSelectVerseMention: (VerseMention) -> Void = { _ in }

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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(translationDisplayName)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                if let localizedBookChapterLabel, !localizedBookChapterLabel.isEmpty {
                    Text(localizedBookChapterLabel)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
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
    }

    private var columnScrollView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(verses, id: \.verse) { verse in
                    VerseRow(
                        verse: verse,
                        isHighlighted: verse.verse == highlightedVerse,
                        isSelected: selectedVerses.contains(verse.verse),
                        highlights: highlightsProvider(verse.verse),
                        crossReferences: crossReferencesProvider(verse.verse),
                        phraseMemos: phraseMemosProvider(verse.verse),
                        phraseNotes: phraseNotesProvider(verse.verse),
                        marginalNotes: marginalNotesProvider(verse.verse),
                        hanjaWords: hanjaWordsProvider(verse.verse),
                        verseMentions: verseMentionsProvider(verse.verse),
                        onSelectCrossReferenceTarget: onSelectCrossReferenceTarget,
                        onSelectPhraseMemo: onSelectPhraseMemo,
                        onSelectVerseMention: onSelectVerseMention
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
                            // iOS/iPadOS 터치에는 수식키 신호가 없으므로 항상
                            // "교체" 선택만 지원한다.
                            onSelectSingleVerse(verse.verse)
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
                        }
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
        .scrollPosition(id: $centerVerseID, anchor: .center)
        .onChange(of: centerVerseID) { _, newValue in
            reportCenterVerseIfNeeded(newValue)
        }
        .onChange(of: coordinator.latestEvent) { _, event in
            // [2026-08-08 추가] `respondsToSyncEvents == false`(아이폰)면 다른
            // 컬럼이 스크롤해도 이 컬럼은 실시간으로 따라가지 않는다 — 위
            // `respondsToSyncEvents` 프로퍼티 주석 참고.
            guard respondsToSyncEvents else { return }
            respondToSyncEvent(event)
        }
        // [2026-08-08 추가] 아이폰 스와이프 정렬 — 부모가 새 값을 넘기면
        // 애니메이션 없이 즉시 그 절로 맞춘다(탭 전환 자체가 이미 전환
        // 애니메이션이라 추가 애니메이션은 오히려 어색하다).
        .onChange(of: pendingCenterAlignment) { _, newValue in
            guard let newValue else { return }
            centerVerseID = newValue
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

    /// 리더 역할 — `.scrollPosition(id:)`가 스크롤에 맞춰 읽어 준 "지금 중앙 절"을
    /// 코디네이터에 보고한다. 프로그램적으로(팔로워로서) 스크롤하는 중에는 건너뛴다.
    private func reportCenterVerseIfNeeded(_ verse: Int?) {
        guard !isProgrammaticScroll, let verse else { return }
        coordinator.reportCenterVerse(verse, columnID: columnID)
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
        isProgrammaticScroll = false
        centerVerseID = nil
    }
}

private struct VerseRow: View {
    let verse: BibleVerse
    let isHighlighted: Bool
    /// [2026-08-08 추가] 클립보드 복사용으로 선택된 절인지 — `isHighlighted`(검색
    /// 결과 등에서 잠깐 스크롤 이동 대상이 됐다는 표시)와는 별개 개념이다.
    let isSelected: Bool
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
            // [2026-08-09 수정] 사용자 요청 — "메모 아이콘, 관주아이콘 위치를
            // 절 번호 밑에 세로로 배치하여 차지하는 영역을 줄일 수 있도록 할
            // 것." 이전엔 두 아이콘이 절 번호·본문과 나란히(가로로) 놓여
            // 줄바꿈된 본문 옆 가로 공간을 계속 차지했다(스크린샷 — 절 3처럼
            // 본문이 여러 줄로 감기면 아이콘이 중간 줄 옆에 끼어 어색하게
            // 보임). 절 번호 칸 자체를 세로 스택으로 바꿔 번호 아래에 아이콘을
            // 쌓아, 본문이 쓸 수 있는 가로 폭을 아이콘 너비만큼 돌려준다.
            VStack(alignment: .center, spacing: 3) {
                Text("\(verse.verse)")
                    .font(settings.bibleVerseNumberFont)
                    .foregroundStyle(.secondary)

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
                            .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
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

            // [2026-08-15 신설] 사용자 요청 — "성경구절 클릭했을 때 - 성경구절
            // 밑으로 난외주 숫자순서대로 뜻을 표시할 것." 절 선택 상태
            // (`isSelected`)를 그대로 트리거로 재사용한다 — 한자 "탭하면
            // 보기"와 같은 원칙(위 `shouldShowInlineHanja` 주석 참고): 이미
            // 있는 "절 탭 → 선택" 동작 하나가 이제 세 가지 의미(클립보드 복사
            // 대상 표시 / 탭하면 보기 모드에서 한자 인라인 / 난외주 목록
            // 펼치기)를 동시에 갖는다.
            if isSelected, !marginalNotes.isEmpty {
                marginalNoteFootnoteList
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
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

    /// [2026-08-15 신설] 절 선택 시 본문 아래 펼쳐지는 난외주 뜻풀이 목록 —
    /// 본문 안 위첨자와 같은 번호를 써서, 위첨자 숫자와 이 목록의 번호가
    /// 항상 대응하게 한다. `anchorOffset`이 없어(위치를 못 찾은 소수 사례)
    /// 위첨자가 안 붙은 각주도 여기 목록에는 그대로 나온다 — 번호와
    /// 뜻풀이는 여전히 유효한 정보이기 때문이다.
    /// [2026-08-15 재수정] 사용자 요청 — "난외주 설명을 2pt정도 더 키울 수
    /// 있도록." 기존 `.caption`(약 12pt)에서 14pt로 키웠다.
    /// [2026-08-15 재수정, 이어서 67] 앱이 절마다 새로 매기던 번호
    /// (`circledNumeral(index+1)`)를 버리고 원본 `<SUP>` 태그 글자
    /// (`note.markerText`)를 그대로 쓴다 — 사용자 질문("원본 번호를
    /// 유지했는가?")에 답하며 확인한 사실(원본은 절이 아니라 장 전체에
    /// 걸쳐 번호가 이어지고, 반복 단어는 번호를 재사용하기도 함)에 따라
    /// 앱이 임의로 재부여하지 않기로 했다(`VerseMarginalNote.markerText`
    /// 주석 참고). `markerText`가 nil인 경우(있을 수 없지만 방어적으로)는
    /// 빈 문자열로 대체한다.
    private var marginalNoteFootnoteList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(marginalNotes.enumerated()), id: \.offset) { _, note in
                Text("\(note.markerText ?? "") \(note.noteText)")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        // 절 번호 칸(`.frame(minWidth: 20)` + HStack spacing 8)만큼 들여써서
        // 본문 시작 위치와 대략 맞춘다.
        .padding(.leading, 28)
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
        if shouldShowInlineHanja || shouldShowMarginalNoteMarkers {
            let attributed = VerseAnnotationRenderer.attributedContentWithInlineAnnotations(
                text: verse.content, highlights: highlights, phraseNotes: phraseNotes,
                hanjaWords: shouldShowInlineHanja ? hanjaWords : [], marginalNotes: marginalNotes,
                font: platformBodyFont, textColor: platformTextColor
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
        } else if let attributed = VerseAnnotationRenderer.attributedContent(
            text: verse.content, highlights: highlights, phraseNotes: phraseNotes,
            font: platformBodyFont, textColor: platformTextColor
        ) {
            if verse.paragraph != nil {
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
        return PlatformFont(name: settings.bibleFontName, size: size) ?? .systemFont(ofSize: size)
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
