# relverse1 — 통합검색에서 성경 구절 열기: 흰 배경, 눌러도 이동하지 않음, 창 간 간섭 (2026-10-29, 최종 + 독립 검토 2회 반영)

정적 분석 결과다. 컨테이너에 Swift 툴체인이 없어 빌드와 실기기 확인은 하지 못했다.

- **기준 파일:** Mac 작업 트리의 현재 파일이다. HEAD `cc2d58b`에 로컬 수정이 얹힌 상태이며, versedoc1·topbar·wordnote1 작업 결과가 들어 있다.
  - wordnote1이 바꾼 파일(`SidebarVisibilityRequest`, `SidebarNavigationView` 등)은 relverse1이 고치는 파일과 겹치지 않는다.
- **기준 확인:** 고친 기존 파일 9개의 md5가 Mac 파일과 같은지 비교해 같음을 확인했다.
- **diff:** `/home/claude/integ/relverse1.diff`
  - 10 files, +433 −133, 새 파일 1개(`Views/Navigation/BibleReadingTarget.swift`)
  - 기준 파일에 `git apply --check` 통과
- **빌드 설정 (Mac 프로젝트 확인):**
  - `Info.plist`의 `UIApplicationSupportsMultipleScenes`는 `true`다(`UIApplicationSceneManifest` 안).
  - Swift 설정은 `SWIFT_VERSION = 5.0`(Swift 5 언어 모드), `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES`다(Debug/Release 같음).
  - `SWIFT_STRICT_CONCURRENCY`는 따로 지정하지 않았다. 즉 Swift 5 모드 기본값(minimal)이고, Swift 6 엄격 동시성 모드가 아니다.
  - 새 타입은 기존 `SermonEditorTarget`·`SermonWindowTokenStore`와 같은 형태다(`Codable, Hashable, Sendable` 값 + `@MainActor final class` 싱글턴).
- **pbxproj:** 동기화 폴더(`PBXFileSystemSynchronizedRootGroup`, 단일 멀티플랫폼 타깃)라 새 파일을 추가해도 pbxproj를 고칠 필요가 없다.

## 사용자 결정 (누적)

1. Mac·iPad에서 구절을 누르면 그 구절이 열린 성경 새 창(`isPrimaryWindow: false`)을 연다. iPhone과 `supportsMultipleWindows == false`인 환경은 "성경 조회" 섹션으로 전환한다.
2. 같은 구절을 다시 누르면 이미 열린 창을 앞으로 가져온다.
3. 적용 대상과 동작:

   | 대상 | 동작 |
   |---|---|
   | 관련 성경구절, 관계 칩 | Mac·iPad 새 창 |
   | 검색 "성경구절" 탭의 절 행 | Mac·iPad 새 창 |
   | 인물·지명 본문 인용 링크 | Mac·iPad 새 창 |
   | 메모 행 | iPad 새 창, Mac은 기존 push |

4. 흰 배경을 고친다. RelationDetailView의 "원문" 섹션도 포함한다.
5. 보조 창이 메인 창의 사이드바·인스펙터를 바꾸지 않게 한다.

## 1. 원인 요약

**흰 배경 (확정)**
- Mac·iPad의 목록+상세 화면(`macSplitCardLayout`)에서 상세 `List`에는 바깥 `cardSectionWrapper`가 없다.
- 그래서 `.listRowBackground(Color.clear)`가 빠진 섹션이 시스템 기본 행 배경(흰색/검정)으로 보였다.

**눌러도 이동하지 않음**
- (A) 가장 유력한 원인이다. 장 카드 하나가 `List` 행 하나인데, 그 안에 `NavigationLink`가 여러 개 들어 있어 탭 대상이 불안정했다.
- (B) 확정된 문제다. iOS에서 push된 `BibleReadingView`가 `.toolbar(.hidden, for: .navigationBar)`로 바를 숨겨 뒤로 버튼이 없다. 10-22에 생긴 회귀다.
  - 메모·예언·서사 행이 push하는 화면도 같은 `BibleReadingView`다.

## 2. 같은 구절 → 기존 창 앞으로 (B-1, B-2)

**공식 동작** ([OpenWindowAction](https://developer.apple.com/documentation/swiftui/openwindowaction.md)):
> "If the interface already has a window from the group that's presenting the specified value, the system brings the window to the front. Otherwise, the system creates a new window."

**값만 같게 하면 안 되는 이유**
- 이 앱은 iPad에서 공식 문서와 다른 동작을 이미 겪었다(`SermonViewerTarget` 주석, 2026-10-03 `SceneDiag` 로그).
- 같은 값의 창을 정상적으로 닫은 뒤 같은 값으로 다시 열면 `openWindow`가 씬 이벤트 없이 버려졌다.
- 그래서 `SermonWindowTokenStore`와 같은 방식(`BibleReadingWindowTokenStore`)으로 미리 막았다.
  - `SermonWindowTokenStore`는 키가 `SermonContentTarget`과 `Kind`로 정해져 있어 그대로 재사용할 수 없다. 같은 규칙으로 새로 만들었다.

**토큰 규칙** (`BibleReadingWindowTokenStore.token(for:)`)
- 키는 처음 연 구절(`BibleReadingLocation`: 책·장·절)이다.
- 같은 구절의 창이 **떠 있으면**(`windowDidAppear` 이후) 같은 토큰을 준다. 값이 같으므로 그 창이 앞으로 온다.
- **방금 요청했고 3초가 안 지났으면** 같은 토큰을 준다. 빠르게 두 번 눌러도 창이 두 개 생기지 않는다(B-2).
- 3초가 지나도 창이 안 나타났으면 기록을 지우고 새 토큰을 준다. 요청이 버려진 경우를 위한 것이다.
- 창이 사라지면(`onDisappear` → `windowDidDisappear`) 기록을 지운다. 그 뒤 같은 구절을 누르면 새 토큰, 즉 새 창이다.
- **[2차 검토 B-1] 씬 연결 확인(iPad).** 재사용하기 직전에 그 토큰의 창이 실제로 살아 있는지 확인한다.
  - 각 창은 자기 씬 세션의 `persistentIdentifier`를 함께 등록한다(`SceneSessionIdentifierReader`).
  - `token(for:)`는 "떠 있음" 기록의 세션 식별자가 `UIApplication.shared.connectedScenes`의 세션 중에 없으면 그 기록을 지우고 새 토큰을 준다.
  - 앱 전환기에서 밀어 닫는 등 `onDisappear` 없이 창이 사라졌고 다른 창이 남아 있는(`openSessions` 2개 이상) 경우에도, 그 구절이 같은 값으로 계속 버려지지 않는다.
- **판정 기준을 `openSessions`가 아니라 `connectedScenes`로 정한 근거**
  - [`openSessions`](https://developer.apple.com/documentation/uikit/uiapplication/opensessions.md): "The sessions whose scenes are either currently active or archived by the system." 보관(archived)된 세션도 포함한다.
  - [개발자 포럼 보고](https://developer.apple.com/forums/thread/826572)(iPadOS 26.5 시뮬레이터, Apple 답변 없음, 작성자 본인의 미확인 추정): 앱 전환기에서 닫은 창이 `openSessions`에 남아 개수가 줄지 않았다. "최근 닫은 창 복원" 때문으로 보인다고 했다.
  - `openSessions`에 있는지로 판정하면 닫힌 창을 살아 있다고 보고 같은 토큰을 다시 줄 수 있다. 이 앱이 설교 창에서 겪은 "같은 값이 버려짐"이 되풀이된다.
  - [`connectedScenes`](https://developer.apple.com/documentation/uikit/uiapplication.md): "The app's currently connected scenes."
  - [`UISceneSession`](https://developer.apple.com/documentation/uikit/uiscenesession.md): "UIKit maintains the session information for the lifetime of the scene itself, destroying the session in response to the user closing the scene in the app switcher." 닫힌 창의 씬은 연결이 끊긴다.
  - 대가: 시스템이 백그라운드 창의 씬을 해제해 보관만 된 상태라면, 같은 구절을 눌렀을 때 그 창을 되살리지 않고 새 창이 하나 더 열린다. 누를 때 반응이 없는 것보다 낫다고 판단했다.
- **창에서 씬 세션을 얻는 방법:** SwiftUI에는 뷰에서 자기 `UIScene`을 얻는 공개 API가 없다. 그래서 보이지 않는 UIKit 뷰를 하나 끼우고, 아래 공개 API를 차례로 따라가 식별자를 얻는다.
  - `UIView.didMoveToWindow()`: "Tells the view that its window object changed."
  - `UIView.window` → `UIWindow.windowScene`: "The scene containing the window."
  - → `UIScene.session` → `UISceneSession.persistentIdentifier`: "A unique identifier that persists for the lifetime of the session."
  - 앱에도 같은 방식(`didMoveToWindow`)의 선례가 있다(`MindMapScrollTouchConfigurator`).
  - `onAppear`와 이 알림 중 어느 쪽이 먼저 와도 결과가 같도록 `windowDidAppear(location:token:sessionID:)` 하나로 합쳤다.
- 기존 안전망(`openSessions.count <= 1`이면 "떠 있음" 기록을 모두 지움)은 세션 식별자를 아직 못 받은 기록을 위해 남겼다.
- macOS 경로는 그대로다(씬 확인과 안전망 모두 `#if os(iOS)`).
- 창 복원: 복원된 창이 나타나면 `windowDidAppear`가 그 토큰을 "떠 있음"으로 등록한다(저장소에 없던 토큰이면 새로 추가). 그래서 같은 구절을 누르면 복원된 창이 앞으로 온다.

**"같은 구절 창" 판정**
- 바인딩 값이 판정 기준인데, 앱은 이 값에 쓰지 않는다. 그래서 처음 연 값이 그대로 남는다.
- 사용자가 그 창에서 다른 장으로 옮겨도, 처음 연 구절을 누르면 그 창이 옮긴 위치 그대로 앞으로 온다. 그 구절로 다시 스크롤하지는 않는다.

**남은 위험 (실기기 확인 필요)**
- 떠 있는 창을 같은 값으로 불러도 iPad가 앞으로 가져오지 않을 가능성이 있다. 공식 문서는 가져온다고 하고, 설교 창도 같은 방식을 쓰므로 가능성은 낮다.
- iPad에서 창이 백그라운드에 남아 `onDisappear`가 오지 않은 채 사용자가 그 창을 잊은 경우, 같은 구절을 누르면 그 백그라운드 창이 앞으로 온다.

## 3. 창 간 간섭 막기 (B-3)

**Mac에서 읽은 소스**
- `BibleToolRail`, `BibleReadingHistorySheet`, `BookmarkListPopover`, `SidebarVisibilityRequest`, `IPadSidebarInspectorCoordination`, `ChapterRelatedContentPanel`, `BibleTopBar`, `BibleReadingView`

| 기능 | 소스 확인 결과 | 결정 |
|---|---|---|
| 관련 콘텐츠 인스펙터 | 열고 닫을 때 `IPadSidebarInspectorCoordination.reportInspectorVisibility`를 부른다. 메인 창 `SidebarNavigationView`가 이 값을 받아 사이드바를 접는다. 인스펙터 안의 `ChapterRelatedContentPanel`에 있는 "개요 화면 열기"(`jumpToOutlineEditor`)는 `AppNavigationRequest(.outline)`로 메인 창 섹션을 바꾼다 | **숨김**: 상단바 "관련 콘텐츠" 버튼. **가드**: `isPrimaryWindow`일 때만 보고·반응. 이 패널을 여는 곳은 iOS 인스펙터와 macOS `RelatedContentPanelController`뿐이고 둘 다 이 버튼·레일로만 열린다. 그래서 보조 창에서는 "개요 화면 열기"에 닿을 수 없다. `ChapterRelatedContentPanel`은 고치지 않았다 |
| 메인 사이드바가 열릴 때 인스펙터 닫기 | `isSidebarVisible`은 메인 창 값이다 | **가드**: 보조 창은 반응하지 않는다(반대 방향 간섭) |
| "사이드바 열기" | 보조 창에는 `NavigationSplitView`가 없다. 버튼을 보일지 판단하는 값(`isSidebarVisible`)도, 누를 때 보내는 요청(`requestShowSidebar()`)도 메인 창 것이다 | **숨김**: 비활성으로 남길 이유가 없고, 메인 창에서도 사이드바가 열려 있으면 이미 숨기는 버튼이다 |
| 조회 이력 | `BibleReadingHistorySheet`는 자기 창 `viewModel.jumpToHistoryEntry`만 부른다. 메인 창을 움직이지 않는다 | **숨김**: macOS 보조 창 규칙(`BibleToolRail.showNavigationGroup = isPrimaryWindow && …`)과 맞춘다 |
| 책갈피 목록·토글 | `BookmarkListPopover`는 자기 창 `viewModel.navigateToBookmark`를 부르고, 토글은 데이터(SwiftData)만 바꾼다. 메인 창을 움직이지 않는다 | **숨김**: 위와 같이 macOS 규칙(책갈피·조회 이력·관련 콘텐츠를 뺀다)과 맞춘다 |
| 말씀 요약 편집 시작·끝 | `SidebarVisibilityRequest.requestHide()/requestRestore()`를 보낸다. 메인 창이 받아 사이드바를 접고 되돌린다 | **가드**: `isPrimaryWindow`일 때만 보낸다. 시작과 끝이 같은 상수 조건이라 짝이 맞는다. 보조 창에서도 하단 액션바 "말씀 요약"으로 편집기를 열 수 있으므로, 편집 중에는 "말씀 요약 닫기"(관련 콘텐츠 칸)를 남긴다 |

- iPad 상단바: `BibleTopBar.isPrimaryWindow`(기본 true)를 추가하고 `BibleReadingView`가 넘긴다. 보조 창에서는 다음과 같이 그린다.
  - 왼쪽 묶음 [사이드바 | 책갈피 이동 | 책갈피]: 그리지 않는다.
  - 오른쪽 묶음 [조회 이력 | 관련 콘텐츠]: 말씀 요약 편집 중에만 "말씀 요약 닫기"를 그리고, 그 밖에는 그리지 않는다.
  - 아이폰 배치(`phoneLayout`)는 보조 창이 없어 바꾸지 않았다.
- macOS는 이미 `BibleToolRail`이 보조 창에서 책갈피·이력·관련 콘텐츠를 뺀다. `requestHide/Restore` 가드는 macOS에도 적용된다. 그래서 기존 "성경 조회 새 창"에서 말씀 요약을 편집해도 메인 창 사이드바가 접히지 않게 된다.
- **고치지 않고 보고:** `LastBiblePositionTracker`(UserDefaults에 저장되는 "마지막으로 본 위치")
  - 보조 창의 `selectBook`/`goToChapter`도 이 값을 갱신한다.
  - 메인 창을 지금 움직이지는 않는다. 다만 메인 창 성경 화면이 새로 만들어질 때(예: iPad에서 다른 섹션에 갔다가 돌아올 때) 보조 창에서 마지막으로 본 위치로 열린다.
  - 기존 macOS 보조 창에도 있던 동작이다. 막으려면 `BibleReadingViewModel`에 창 구분을 넘겨야 해서 범위 밖으로 남긴다.

## 4. SidebarVisibilityRequest의 첫 기록 (B-4)

**소스 확인 결과: 첫 기록을 지키지 않는다.**
- `SidebarVisibilityRequest.recordVisibilityBeforeHide(_:)`는 조건 없이 덮어쓴다(`wasVisibleBeforeHide = visible`).
- `SidebarNavigationView`는 `.hide`를 받을 때마다 `recordVisibilityBeforeHide(columnVisibility != .detailOnly)`를 부른 뒤 사이드바를 접는다.
- `BibleReadingView.presentWordSummaryEditor`는 편집기가 이미 열린 채 다시 불려도 `requestHide()`를 또 보낸다. 예: 관련 콘텐츠에서 다른 말씀 요약을 연달아 고를 때. 번역본 저장값은 "이미 열려 있으면 덮어쓰지 않는다"로 막았지만 사이드바는 막지 않았다.
- 결과: 두 번째 `.hide`가 "열려 있었음"을 "닫혀 있었음"으로 덮어써, 편집을 마쳐도 사이드바가 돌아오지 않는다.

**이번 diff의 수정 (호출부)**
- 편집 세션 표시(`displayedTranslationIDsBeforeWordSummary`)를 기준으로 판단한다. 이 값은 시작할 때 채워지고 `closeWordSummaryEditor()`가 동기적으로 비운다.
- 세션의 첫 호출(`isFirstPresentation`)일 때만 `requestHide()`를 보낸다. `requestRestore()`는 세션당 한 번이라 짝이 맞는다.
- iOS에서 닫은 직후 0.3초 안에 다시 여는 경우: `wordSummaryBeingEdited`는 늦게 비워지지만 세션 표시는 즉시 nil이 된다. 그래서 다시 열면 첫 호출로 보고 숨김 요청을 보낸다.
- `SidebarVisibilityRequest.swift`는 지시대로 고치지 않았다. wordnote1이 그 파일에서 복원 값 덮어쓰기를 고치더라도 이 호출부 수정과 충돌하지 않는다. 같은 문제를 받는 쪽과 보내는 쪽에서 각각 막는 것이다.
  - wordnote1이 `BibleReadingView.swift`의 같은 함수를 고치면 텍스트 충돌이 날 수 있으니 순서를 맞춰야 한다.

## 5. 창 복원 때 조회 이력 중복 (질문 6)

- **원인:** 복원된 창은 `BibleReadingView`를 새로 만든다. 그러면 `initialVerse` 분기의 `recordVerseHistory`가 다시 불려 같은 장:절 이력이 또 남는다.
- **수정:** `BibleReadingWindowContent`에 `@SceneStorage("bibleReadingAt.didRecordInitialHistory")`를 둔다.
  - `@SceneStorage`는 씬마다 따로이고, 시스템이 창 복원 때 함께 되살린다.
  - `BibleReadingView`에 `shouldRecordInitialVerseHistory: () -> Bool`(기본 `{ true }`)을 추가했다. viewModel을 만드는 순간(첫 `onAppear`)에 이 클로저에 묻는다.
  - 창 내용은 처음 한 번만 true를 돌려주고 그 사실을 SceneStorage에 남긴다. 복원된 창은 false를 받아 이력을 남기지 않는다. 스크롤과 강조는 그대로 한다.
  - 같은 구절로 기존 창을 앞으로 가져올 때는 화면을 새로 만들지 않아 이력도 남지 않는다. 의도된 동작이다(사용자 확인).
- **[2차 검토 B-2] `.id(target)`은 없앴다(`SermonContentWindowContent`와 같다).**
  - nil에서 값으로 바뀌는 전환은 실제로 없다. 앱은 창 바인딩에 값을 쓰지 않는다.
  - `openWindow(id:value:)`는 "creates a new window and passes a binding to the specified value"(공식 문서)라서, 창은 첫 렌더부터 값을 갖는다.
  - nil은 값 없이 만들어진 창뿐이다(예: 복원 값을 읽지 못한 경우). 이런 창은 좌표 없이 연다.
  - 그래서 `onAppear`/`onDisappear`, `@SceneStorage` 판정, 씬 세션 등록이 바깥에 있어도 같은 뷰 하나에 대해서만 동작한다.
  - 값을 미리 넘기지 않고 클로저로 묻는 이유: 부모 `onAppear`와 자식 `onAppear` 중 어느 쪽이 먼저 실행되는지에 결과가 좌우되지 않게 하려는 것이다.
- **한계:** 시스템이 씬 저장소를 복원하지 않는 경우(예: 사용자가 창을 닫아 세션이 버려진 뒤 새로 연 창)는 새 창이므로 이력을 남기는 것이 맞다. 복원 여부는 시스템의 SceneStorage 복원에 달려 있다.

## 5-1. `WordSummaryPanelController.present`가 기존 `onClose`를 부르는지 (질문 2, macOS)

Mac 소스(`Views/WordSummary/WordSummaryPanelController.swift`)를 확인했다. **문제 없음, 수정하지 않음.**

- **다른 창이 패널을 갖고 있을 때**(`panel != nil`이고 `ownerToken`이 다름): 새 `onClose`를 저장하기 전에 이전 주인의 `onClose`를 먼저 한 번 부른다.
  - 그 `onClose`(이전 창의 `closeWordSummaryEditor`)는 `wordSummaryBeingEdited = nil`을 한 뒤 `hide()`를 부르고, `hide()`가 패널을 닫는다.
  - 패널이 닫히면 `windowWillClose`가 실행된다. 여기서 `onClose`가 다시 불리지만, 맨 위 `guard wordSummaryBeingEdited != nil`에 걸려 바로 돌아온다. 그래서 재진입해도 뒷정리는 한 번만 일어난다.
  - 이어서 `present`가 새 주인과 새 `onClose`를 저장한다. 이때 `panel`이 nil이므로 패널을 새로 만든다.
- **같은 창이 다시 부를 때:** 이전 `onClose`를 부르지 않고 같은 함수로 바꿔 끼운다. 나중에 닫을 때 한 번 불린다.
- **이번 가드와의 짝:** 창 A가 편집 중일 때 창 B가 열면, A의 뒷정리는 A가 메인 창일 때만 `requestRestore`를 보낸다. B는 B가 메인 창이고 첫 호출일 때만 `requestHide`를 보낸다. 어느 조합에서도 hide와 restore의 짝이 창별로 맞는다.

## 6. 그 밖의 반영

- **B-5:** Person/Place/Theme의 `verseReferenceRow` 라벨에 `.contentShape(Rectangle())`을 추가했다. plain 버튼은 그려진 글자만 탭을 받기 때문에 줄 끝 빈 공간까지 탭 영역을 넓혔다.
- **주석 수정**
  - `PlaceDetailView.handleBibleReferenceLink`: "앱 공용 크로스탭 이동"을 `verseOpener` 설명으로 바꿨다.
  - `BibleReadingView`의 `isPrimaryWindow` 주석: "macOS 성경 조회 새 창만 false"를, 실제로 false를 넘기는 두 창과 보조 창 규칙 설명으로 바꿨다.
  - `BibleReadingView`의 `initialVerse` 주석: 더는 없는 `SearchView.verseRow`를 실제로 값을 넘기는 곳으로 바꿨다.
  - `BibleReadingView`의 번역본 저장 주석도 실제 동작에 맞췄다.

## 7. 수정 파일

| 파일 | 변경 |
|---|---|
| `Views/Navigation/BibleReadingTarget.swift` (새 파일) | `BibleReadingLocation`, `BibleReadingTarget`(위치 + 토큰), `BibleReadingWindowTokenStore`(씬 연결 확인), `BibleReadingWindowContent`(SceneStorage, 창이 나타나고 사라질 때 알림, `.id` 없음), `SceneSessionIdentifierReader`(iOS), `BibleVerseOpener` |
| `JBCHBibleResearchApp.swift` | `WindowGroup(id: "bible-reading-at", for: BibleReadingTarget.self)` |
| `Views/Bible/BibleReadingView.swift` | 보조 창 가드 4곳, `isFirstPresentation`(B-4), `shouldRecordInitialVerseHistory`, `BibleTopBar(isPrimaryWindow:)` 전달, 주석 |
| `Views/Bible/BibleTopBar.swift` | `isPrimaryWindow`, 보조 창 아이콘 숨김 |
| `Views/Search/PersonDetailView.swift`, `PlaceDetailView.swift` | 구절 행 Button + `verseOpener` + `contentShape`, 본문 인용 링크 `verseOpener`, 행 배경 투명 |
| `Views/Search/ThemeDetailView.swift` | 구절 행 Button + `verseOpener` + `contentShape`, 행 배경 투명 |
| `Views/Search/BibleVerseChipRow.swift` | 칩 Button + `verseOpener` |
| `Views/Search/RelationDetailView.swift` | "원문"·"관련 성경구절" 행 배경 투명 |
| `Views/Search/SearchView.swift` | `openVerseInBibleReading`에 `BibleVerseOpener` 적용, `bibleVerseRow`는 iOS면 opener·macOS면 push |

## 8. 확인 방법

**iPad, 사이드바 열림**
1. "아브라함의 아내" → "사라는 아브라함의 아내"에서 관련 성경구절과 원문의 배경이 테마를 따르는지 본다. 라이트/다크와 색 테마를 모두 본다.
2. 구절 줄 끝 빈 곳을 눌러도 열리는지 본다(B-5).
3. 다른 절을 누를 때마다 새 창이 열리는지, 메인 창의 검색 결과와 사이드바가 그대로인지 본다.
4. 같은 절을 다시 누르면 기존 창이 앞으로 오는지 본다. 그 창에서 장을 옮긴 뒤 같은 절을 누르면 옮긴 위치 그대로 앞으로 오는지도 본다.
5. 같은 절을 빠르게 두 번 누르면 창이 하나만 열리는지 본다(B-2).
6. **핵심:** 창을 닫은 뒤 같은 절을 누르면 새 창이 열리는지 본다. 다른 보조 창이 하나 이상 떠 있는 상태(`openSessions` 2개 이상)에서도 확인한다(2차 B-1). 닫는 방법 세 가지를 각각 확인한다.
   - 창 닫기 버튼
   - Stage Manager에서 닫기
   - 앱 전환기에서 위로 밀어 닫기
   - DEBUG 빌드에서는 `SceneDiag` 로그 "성경 창 토큰 새로 발급/재사용"으로 판정할 수 있다.
7. 보조 창 상단바 확인:
   - 사이드바 열기, 책갈피 이동·설정, 조회 이력, 관련 콘텐츠 아이콘이 없어야 한다.
   - 하단 "말씀 요약"으로 편집기를 열면 "말씀 요약 닫기"가 나타나야 한다.
   - 편집기를 열고 닫는 동안 메인 창 사이드바가 그대로여야 한다.
8. 메인 창에서 사이드바가 열린 채 관련 콘텐츠 → 말씀 요약 A → 다른 말씀 요약 B를 연달아 연 뒤 닫는다. 사이드바가 다시 열려야 한다(B-4).
9. 새 창을 띄운 채 앱을 다시 실행한다.
   - 창이 복원되는지 본다.
   - 조회 이력에 그 절이 다시 쌓이지 않는지 본다.
   - 같은 절을 누르면 복원된 창이 앞으로 오는지 본다.
10. "성경구절" 탭 절 행, 인물·지명 본문 인용 링크(📖), 관계 칩, 메모 행(장만 열림)도 확인한다.

**iPhone**
11. 모든 경로가 이전처럼 "성경" 탭으로 전환되는지 본다.

**macOS**
12. 위 경로가 새 창으로 열리고, 같은 구절이면 앞으로 오는지 본다. 메모 행은 push이고 뒤로 버튼이 있어야 한다.
13. 메뉴의 "성경 조회 새 창"을 연다. 그 창에서 말씀 요약을 편집해도 메인 창 사이드바가 접히지 않아야 한다(동작 변화).
