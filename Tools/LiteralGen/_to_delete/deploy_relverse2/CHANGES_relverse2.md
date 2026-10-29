# relverse2 — 구절 지정 성경 보조 창에 [닫기]·[메인 창으로] (2026-10-29, 검토 반영)

정적 분석으로만 작성했다. 컨테이너에 Swift 툴체인이 없어 빌드와 실기기 확인은 하지 못했다.

- **기준:** Mac 작업 트리의 현재 파일(relverse1·wordnote1·versedoc1 반영 후).
  - 고친 기존 파일 10개의 md5가 Mac 파일과 같은지 확인했다.
  - 새 파일 `Views/Navigation/MainWindowNavigation.swift`는 Mac에 없다.
- **diff:** `/home/claude/integ/relverse2.diff`
  - 11 files, +558 −11, 새 파일 1개
  - 기준 파일에 대해 `git apply --check` 통과
- **안 건드린 파일:**
  - `OriginalTextInfoView.swift`
  - `BibleReadingView.swift`: 버튼은 환경값으로 전달해 이 파일은 고치지 않았다.
  - `project.pbxproj`: 동기화 폴더라 새 파일을 넣어도 수정이 필요 없다.

## 사용자 결정

1. 위치는 상단바 왼쪽이다. iPad 보조 창에서 원래 "사이드바 열기"가 있던 자리다. macOS 보조 창도 같은 기능을 둔다.
2. [메인 창으로]는 메인 창을 앞으로 가져온다. 메인 창 내용은 검색 결과·상세 화면 그대로 두고, 그다음 보조 창을 닫는다.
3. [닫기]는 보조 창만 닫는다.

## 1. 위치

**iPad: `BibleTopBar.padLeftGroup`**
- 보조 창(`isPrimaryWindow == false`)은 relverse1에서 이 묶음 전체를 뺐다. 이제 같은 자리에 [닫기 | 메인 창으로] 묶음을 둔다.
- 세 가지 배치(두 줄, 한 줄, "아이콘 아래줄")가 모두 `padLeftGroup`을 쓰므로 어느 배치에서도 같은 자리에 나온다.
- 말씀 요약 편집 중에는 메인 창의 왼쪽 묶음처럼 감춘다. 편집은 "말씀 요약 닫기"로 먼저 마친다.

**macOS: `BibleToolRail` 맨 위**
- macOS 성경 조회는 창 툴바 아이콘을 레일로 옮겼다(2026-10-02, `BibleReadingView` 주석 "macOS는 트레일링 아이콘이 본문 왼쪽 레일로 옮겨져 툴바 항목이 없다"). 창 단위 동작인 "성경 조회 새 창"도 이미 레일에 있다.
- 창 툴바에 새 항목을 넣으면 macOS만 다른 체계가 된다. 그래서 레일의 첫 칸에 두었다. iPad 상단바 왼쪽과 같은 "첫 자리"다.
- 버튼은 기존 `RailButton`(36pt)을 그대로 쓴다. 44pt 요구는 터치 기준이라 iPad에만 적용했다. 포인터 환경인 macOS는 레일의 다른 버튼과 크기를 맞췄다.
- 창 닫기 버튼(빨간 신호등)이 이미 있지만, 아이패드와 버튼 구성을 맞추려고 [닫기]도 둔다.

**버튼을 그리는 창**
- 두 버튼은 환경값 `bibleSecondaryWindowActions`가 있을 때만 그린다. 이 값은 구절 지정 보조 창(`BibleReadingWindowContent`, "bible-reading-at")만 넣는다.
- 메인 창, iPhone, macOS "성경 조회 새 창"("bible-reading")에는 값이 없으므로 화면이 바뀌지 않는다(질문 1).

## 2. 메인 창을 앞으로 가져오는 방법

**전제: 메인 창 그룹에는 `id`가 없다**
- 메인 창은 앱의 첫 `WindowGroup { ContentView() }`이고 `id`가 없다. 그래서 `openWindow(id:)`로 이 그룹을 지목할 수 없다.
- 지목할 수 있더라도, `id`만 주면 [OpenWindowAction](https://developer.apple.com/documentation/swiftui/openwindowaction.md) 문서대로 "the system creates a new window for the group"이 되어 메인 창이 하나 더 생긴다.
- 메인 그룹에 `id`를 새로 붙이지 않았다. 이미 있는 메인 창의 상태 복원 식별이 바뀌는지 문서로 확인하지 못했기 때문이다.

**요청 출처(어느 메인 창인지) 기억**
- 메인 창마다 `MainWindowRegistration`이 자기 식별자를 `MainWindowRegistry`에 등록한다. 이 수정자는 앱의 첫 `WindowGroup`의 `ContentView`에만 붙는다.
- 같은 식별자를 하위 화면에 환경값 `mainWindowID`로 넘긴다.
- `BibleVerseOpener`가 그 값을 출처로 토큰 저장소에 기록한다(`originWindowID`).
  - 같은 구절을 다른 메인 창에서 다시 누르면 출처가 그 창으로 바뀐다.
- 보조 창은 처음 나타날 때 출처를 `@SceneStorage("bibleReadingAt.originWindowID")`에 옮겨 둔다. 그래서 창 복원 뒤에 토큰 기록이 없어도 출처를 안다.
- 출처를 모르거나 그 창이 없어졌으면 가장 최근에 활성이었던 메인 창을 고른다.
  - iPad: 메인 창 씬이 `.active`가 될 때 기록한다.
  - macOS: `NSWindow.didBecomeKeyNotification`으로 기록한다.

**iPadOS**
- 식별자는 씬 세션의 `UISceneSession.persistentIdentifier`다. 문서: "A unique identifier that persists for the lifetime of the session."
- 얻는 방법은 relverse1의 `SceneSessionIdentifierReader`(`didMoveToWindow` → `window.windowScene.session`)를 같이 쓴다. 이 타입은 `private`을 뗐다.
- **[검토 B-1] 앞으로 가져오기 API:** `UIApplication.shared.activateSceneSession(for: UISceneSessionActivationRequest(session: session), errorHandler:)`를 쓴다.
  - Mac의 Xcode iOS SDK를 읽기 전용으로 열어 확인했다(UIKit `arm64e-apple-ios.swiftinterface`와 헤더).
    - `@available(iOS 17.0, tvOS 17.0, *) public struct UISceneSessionActivationRequest`
    - `public init(session: UISceneSession, userActivity: NSUserActivity? = nil, options: UIScene.ActivationRequestOptions? = nil)`
    - `public init(role: UISceneSession.Role = .windowApplication, userActivity: NSUserActivity? = nil, options: UIScene.ActivationRequestOptions? = nil)`
    - `@available(iOS 17.0, tvOS 17.0, *) extension UIApplication { @MainActor public func activateSceneSession(for request: UISceneSessionActivationRequest, errorHandler: ((any Error) -> Void)? = nil) }`
    - 헤더 `UISceneSessionActivationRequest.h`: `+requestWithSession:` "Creates a request for activating an existing scene session."
    - 헤더 `UIApplication.h`: `requestSceneSessionActivation:...`는 `API_DEPRECATED("Please use activateSceneSessionForRequest:errorHandler:", ios(13.0, API_TO_BE_DEPRECATED))`
  - 배포 대상이 iOS 18이라 iOS 17.0부터 있는 새 API로 바꿨다. 예전 API는 쓰지 않는다.
- **후보 고르는 순서:** 출처 → 최근 활성 순. 그중 연결된 장면(`connectedScenes`)이 우선이고, 보관만 된 세션(`openSessions`)은 그다음이다.
- **[검토 B-2] 대상 창이 실제로 활성이 된 뒤에만 보조 창을 닫는다** (`MainWindowActivationTracker`)
  - 대상 씬이 이미 `activationState == .foregroundActive`이면(예: Split View의 다른 쪽) 활성화 요청만 보내고 바로 확인으로 본다. 이미 활성인 씬에는 활성화 알림이 다시 오지 않을 수 있기 때문이다.
  - 그 밖에는 대상 세션 씬의 `UIScene.didActivateNotification`을 받았을 때만 닫는다.
  - 2초 안에 알림이 오지 않거나 errorHandler가 불리면 보조 창은 그대로 둔다. 그래서 활성화가 실패해도 화면이 하나도 남지 않는 일은 없다.
- **[재검토 B-1] 요청 세대:** `begin`이 세대 값을 돌려준다. `finish`와 errorHandler·활성 알림·만료 콜백은 그 세대가 현재 진행 중인 요청과 같을 때만 처리한다. 앞 요청의 늦은 콜백이 다음 요청의 잠금을 풀거나 보조 창을 닫지 못한다.
- **[재검토 B-3] 이미 활성인 경로에도 잠금:** 대상 씬이 이미 `foregroundActive`인 경로도 진행 중 잠금을 건다(만료 때 풀림). 보조 창이 닫히기 전에 연타해도 활성화 요청과 `dismissWindow`가 한 번만 나간다.
- **[검토 B-4] 연타 방지:** 요청이 진행 중이면 새 요청을 무시한다(`isInFlight`).
  - 진행 상태는 확인할 수 있는 사건으로 끝난다: 활성 알림, errorHandler.
  - 알림이 끝내 오지 않는 경우(이 앱이 설교 창에서 겪은 "요청이 조용히 버려짐")를 위해 2초 상한을 두었다. 시간만으로 막는 방식이 아니라, 진행 중 상태에 상한을 둔 것이다.
  - 메인 창이 없을 때의 새 장면 요청에도 같은 잠금을 적용했다. 다른 장면이 활성이 되거나, 실패하거나, 시간이 초과되면 풀린다. 그래서 연타해도 새 장면이 여러 개 생기지 않는다.

**macOS**
- 식별자는 메인 창 `NSWindow`를 약한 참조로 등록한 것이다. 얻는 방법은 `HostingWindowReader`(`NSView.viewDidMoveToWindow()`)다.
- 앞으로 가져오기는 다음 순서다.
  1. Dock에 내려가 있으면 `deminiaturize(_:)`로 올린다.
  2. `makeKeyAndOrderFront(_:)`를 부른다. 문서: "Moves the window to the front of the screen list, within its level, and makes it the key window."
- 그다음 보조 창을 닫는다. AppKit 호출이 동기라 바로 닫는다.
- **[검토 B-3] 등록 해제는 창이 실제로 닫힐 때만 한다(`NSWindow.willCloseNotification`).**
  - 문서: "Posted whenever an NSWindow object is about to close."
  - 루트 `onDisappear`로 해제하던 것을 없앴다. 그래서 탭 합치기, 전체 화면 전환, Dock으로 내리기에서는 등록이 유지된다.
  - 루트 뷰가 다른 `NSWindow`로 옮겨 붙으면 `viewDidMoveToWindow`가 다시 등록한다.
  - "열린 메인 창"은 등록돼 있고 아직 해제되지 않은 창으로 판정한다. 뒤쪽 탭은 `isVisible`이 false일 수 있어 판정 조건에서 뺐다.

**메인 창 내용은 바꾸지 않는다**
- 섹션 전환 요청(`AppNavigationRequest`)이나 이동 요청을 보내지 않는다. 이미 있는 창이나 세션을 앞으로 가져오기만 한다.
- 예외는 iPad의 보관 세션이다. 시스템이 씬을 해제한 상태에서 다시 연결되면, 화면은 SwiftUI 상태 복원 범위만큼만 돌아온다(`@SceneStorage` 등). 검색 결과처럼 메모리에만 있던 상태는 다시 만들어질 수 있다.

**메인 창이 하나도 없을 때**
- **iPad:** 새 장면(`UISceneSessionActivationRequest(role: .windowApplication)`)을 요청하고, 보조 창은 닫지 않는다.
  - 세션 없이 만든 새 장면에 SwiftUI가 어느 `WindowGroup`을 붙이는지는 문서로 확인하지 못했다. 앱 아이콘을 눌러 새로 열 때와 같은 경로라 첫 그룹(메인)일 것으로 보지만 실기기 확인이 필요하다.
  - 보조 창을 먼저 닫으면 새 창이 안 떴을 때 화면이 하나도 남지 않는다. 그래서 남겼다.
- **macOS:** [메인 창으로]를 비활성화한다(`MainWindowRegistry.hasLiveMainWindow`, 관찰 가능).
  - 메인 그룹에 `id`가 없어 SwiftUI로 새로 열 방법이 없다.
  - 사용자는 Dock 아이콘 클릭이나 파일 > 새 윈도우를 쓰면 된다.

## 3. 닫기

- `@Environment(\.dismissWindow)`의 `dismissWindow()`를 쓴다.
  - 이 앱에서 이미 검증된 방법이다. 진짜 `WindowGroup` 창은 `dismiss`가 효과가 없어 `dismissWindow()`로 닫는다(`SermonContentWindowContent`, `SermonMindMapView`, `OutlineQuickViewWindowContent`, `DocumentViewerView`).
  - iOS의 `requestSceneSessionDestruction`은 세션을 직접 다뤄야 하고, SwiftUI 창 관리와 따로 움직인다. 그래서 쓰지 않았다.
- **[메인 창으로]가 보조 창을 닫는 경우:** 같은 `dismissWindow()`를 쓰지만, 메인 창이 활성이 된 것을 확인한 다음에만 부른다(§2).
- **토큰 저장소의 "떠 있음" 기록 정리**
  - 창이 닫히면 `BibleReadingWindowContent.onDisappear` → `windowDidDisappear(token:)`로 지워진다.
  - iPad에서 `onDisappear`가 오지 않더라도, 다음에 같은 구절을 누를 때 `token(for:)`의 씬 연결 확인(relverse1 B-1)이 지운다.
  - 그래서 닫은 뒤 같은 구절을 다시 누르면 새 창이 열린다.

## 4. 접근성·현지화·터치 영역

- **접근성 라벨:**
  - [닫기]: 기존 키 "닫기"(17개 언어 번역이 이미 있음)
  - [메인 창으로]: 새 키 "메인 창으로"
  - macOS `help`도 같은 키를 쓴다. 새 키를 최소로 했다.
- **`Localizable.xcstrings`:** "메인 창으로"를 기존 형식으로 정렬 위치("메인과 동일" 앞)에 넣었다.
  - 절차 변경(사용자 승인)에 따라 ko와 en만 넣는다. ko는 원본 언어라 키 자체가 한국어 문구다. 이 파일은 순서 바꿈 서식이 있는 항목만 `ko`를 따로 적는다.
  - en: "Go to Main Window"(`state: needs_review`).
  - 나머지 언어 번역은 나중에 한꺼번에 처리한다.

- **iPad 터치 영역:** 두 칸만 `bibleBarSizing`의 높이를 44pt로 바꿨다(`secondaryWindowControlSizing`, 나머지 값은 `.touch`와 같다). 칸(`BibleTopBarItemBody`)과 묶음(`BibleBarSegmentGroup`)이 모두 이 환경값을 따르므로 44×44가 된다.
- **아이콘:**
  - [닫기]: `xmark`
  - [메인 창으로]: `macwindow`. "새 창"은 `macwindow.badge.plus`라 구분된다(질문 3).

## 5. 바뀌지 않는 것

- **메인 창(`isPrimaryWindow == true`):** 버튼 묶음 조건이 `!isPrimaryWindow`이고 환경값도 없어 그리지 않는다.
  - 메인 창에 추가되는 것은 식별자 등록(보이지 않는 배경 뷰 1개)과 환경값 1개뿐이다.
- **iPhone:** 보조 창이 없어 버튼을 그리지 않는다. 등록부에 세션 하나가 기록될 뿐 동작은 같다(`BibleVerseOpener`는 iPhone에서 섹션 전환이라 출처를 쓰지 않는다).

## 6. 수정 파일

| 파일 | 변경 |
|---|---|
| `Views/Navigation/MainWindowNavigation.swift` (새 파일) | 환경값 `mainWindowID`·`bibleSecondaryWindowActions`, `BibleSecondaryWindowActions`, `MainWindowRegistry`(@Observable), `MainWindowRegistration`(macOS는 `willClose` 해제), `HostingWindowReader`(macOS), `MainWindowActivationTracker`(iOS: 활성 확인·진행 중 잠금), `MainWindowActivator` |
| `Views/Navigation/BibleReadingTarget.swift` | 토큰 기록에 `originWindowID` 추가, `token(for:originWindowID:)`, `originWindowID(for:)`, `BibleVerseOpener.originWindowID`, `sessionID(for:)`. `BibleReadingWindowContent`에 `dismissWindow`, 출처 `@SceneStorage`, 동작 환경값 주입. `SceneSessionIdentifierReader`의 `private` 제거 |
| `JBCHBibleResearchApp.swift` | 메인 `WindowGroup`의 `ContentView()`에 `.modifier(MainWindowRegistration())` |
| `Views/Bible/BibleTopBar.swift` | 보조 창 `padLeftGroup` [닫기 \| 메인 창으로], 44pt 크기 |
| `Views/Bible/BibleToolRail.swift` | 보조 창 맨 위 묶음 |
| `Views/Search/PersonDetailView.swift`, `PlaceDetailView.swift`, `ThemeDetailView.swift`, `BibleVerseChipRow.swift`, `SearchView.swift` | `@Environment(\.mainWindowID)`를 `BibleVerseOpener(originWindowID:)`로 넘김 |
| `Localizable.xcstrings` | "메인 창으로" |

## 7. 확인 방법

**iPad, 메인 창 1개, 사이드바 열림**
1. 검색 → 상세 → 구절을 눌러 보조 창을 연다.
   - 상단바 왼쪽에 [닫기 | 메인 창으로]가 보이는지 본다.
   - VoiceOver로 "닫기", "메인 창으로"가 읽히는지 본다.
   - 칸 크기가 44pt인지 본다.
   - 세 가지 배치(가로·세로·분할)에서 모두 보이는지 본다.
2. [메인 창으로]를 누르면 메인 창이 앞으로 오고 검색 결과·상세 화면이 그대로인지, 보조 창이 닫히는지 본다.
3. [닫기]를 누르면 보조 창만 닫히는지 본다. 닫은 뒤 같은 구절을 누르면 새 창이 열려야 한다(토큰 기록 정리).
4. 보조 창에서 말씀 요약 편집을 시작하면 두 버튼이 숨고, "말씀 요약 닫기"를 누르면 다시 나오는지 본다.

**iPad, 메인 창 2개(Stage Manager)**
4-1. [메인 창으로]를 빠르게 여러 번 눌러도 한 번만 처리되는지 본다(B-4). `SceneDiag` 로그에 "진행 중이라 무시"가 나와야 한다.
5. 메인 A에서 보조 창을 열고 [메인 창으로]를 누르면 A가 앞으로 와야 한다. 메인 B에서 연 경우는 B가 와야 한다.
   - DEBUG 빌드에서는 `SceneDiag` 로그 "메인 창으로: 세션 활성화 요청"으로 판정한다.
6. 앱을 다시 실행해 창이 복원된 뒤 [메인 창으로]가 같은 메인 창을 고르는지 본다(씬 저장 출처).

**iPad, 메인 창을 닫은 상태**
7. 앱 전환기에서 메인 창만 밀어 닫은 뒤 보조 창에서 [메인 창으로]를 누른다.
   - 새 메인 창이 뜨는지, 어떤 창이 뜨는지 기록한다(⚠️ 문서 미확인 경로).
   - 보조 창은 남아야 한다.
   - 연타해도 새 창이 하나만 생겨야 한다.
7-2. **[재검토 B-2] 백그라운드 보조 창의 `dismissWindow`:** 메인 창이 앞으로 오면 보조 창은 뒤로 가거나 백그라운드가 된 상태에서 `dismissWindow()`가 불린다(활성 확인 뒤). Stage Manager 켬·끔, Split View, 전체 화면 각각에서 보조 창이 실제로 닫히는지, 앱 전환기에 남지 않는지, 다시 같은 구절을 누르면 새 창이 열리는지 확인한다. 닫히지 않으면 메인 창 활성화 전에 닫는 순서나 `requestSceneSessionDestruction`을 검토한다.
7-1. 활성화가 확인되지 않는 경우(로그 "활성 확인 시간 초과")에는 보조 창이 남는지 본다(B-2).

**macOS**
8. 레일 맨 위에 [닫기]·[메인 창으로]가 보이는지 본다.
9. [메인 창으로]를 누르면 메인 창이 앞으로 오고(Dock에 내려가 있었으면 올라오고) 보조 창이 닫히는지 본다.
10. 메인 창을 닫으면 [메인 창으로]가 비활성화되는지, 메인 창을 다시 열면 활성화되는지 본다.
10-1. 메인 창을 Dock에 내리거나, 전체 화면으로 바꾸거나, 보조 창과 탭으로 합친 뒤에도 [메인 창으로]가 활성이고 메인 창을 앞으로 가져오는지 본다(B-3).
11. 메뉴의 "성경 조회 새 창"("bible-reading")에는 두 버튼이 없는지 본다(기존과 같음).

**iPhone**
12. 모든 화면이 기존과 같은지 본다.

## 질문

1. (답을 기다리는 동안 기본값: 넣지 않음) macOS 메뉴·레일의 "성경 조회 새 창"("bible-reading")에도 두 버튼을 둘까요? 이번 요청 범위가 "bible-reading-at"이라 넣지 않았습니다. 넣는 것은 `App`에서 같은 환경값을 주입하면 되는 작은 변경이고, 이 창은 출처를 모르므로 가장 최근 메인 창으로 갑니다.
2. (해결됨) SDK에서 시그니처를 확인해 `activateSceneSession(for:errorHandler:)`로 바꿨다.
3. (답을 기다리는 동안 기본값: `macwindow`) [메인 창으로] 아이콘을 `macwindow`로 정했습니다. 다른 기호를 원하시면 알려 주세요.
4. iPad에서 메인 창이 없을 때 새 장면을 요청하고 보조 창을 남겨 두었습니다. 사용자 결정 "그 후 보조 창은 닫는다"와 다른 부분입니다. 실기기에서 새 메인 창이 확실히 뜨면 이 경우에도 닫도록 바꿀까요?
