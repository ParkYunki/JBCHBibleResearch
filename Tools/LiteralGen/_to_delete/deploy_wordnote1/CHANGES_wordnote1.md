# wordnote1 — 아이패드 세로: 사이드바가 열려 있으면 말씀 노트·개요의 내용 칸 숨기기

빌드 환경이 없어 정적 분석만 했다. 실기기 확인 전에는 "검증 완료"로 보지 말 것.
기준: Mac 작업 트리 현재 파일(2026-10-29, md5 대조). `git apply --check` 통과.

개정 이력
- v1: 말씀 노트(4개 파일).
- v2: 개요 화면 추가(사용자 결정 5).
- v3(현재): 독립 검토 2건의 지적 B-1·B-4/B1·B-5·B-6을 반영했다. 판정을 창 모양 기준으로 바꾸고, 복원 기록을 보존하고, 판정은 Bool만 저장하고, 시트 경계를 처리했다. 공통 수정자를 분리해 두 화면이 같은 코드를 쓴다. B-3은 확인만, B-2·B-7은 한계로 기록했다.

## 1. 현재 구조

- 앱 최상위(`Views/Navigation/SidebarNavigationView.swift`): **2열** `NavigationSplitView(columnVisibility:)`. `@State columnVisibility = .all`이고 스타일은 기본값이다. 사용자 확인 결과, 세로에서 사이드바를 열면 본문이 옆으로 밀려난다(나란히 배치).
- 말씀 노트(`WordNoteSplitContent`): detail 열 안의 `HStack [WordNoteListContent(분류 트리 200 + 목록, min 460/max 720) | Divider | 내용]`. 사이드바를 열면 [사이드바 | 분류 트리 | 목록 | 내용]으로 나뉘고, 11인치 세로에서 내용 칸은 약 119pt까지 줄어든다.
- 개요(`OutlineTreeSplitContent`): `HStack [OutlineTreeList(min 360/max 390) | Divider | 내용]`. 내용 칸은 11인치에서 약 219pt, mini에서 약 143pt다.
- 항목을 탭하면 사이드바가 닫히는 기존 코드: 두 화면 모두 `.onChange(of: 선택)`이다. 선택 없음 → 값일 때 `SidebarVisibilityRequest.requestHide()`를 보내고, 값 → 없음일 때와 `onDisappear`에서 `requestRestore()`를 보낸다. `SidebarNavigationView`는 `.hide`를 처리할 때 직전 상태를 `recordVisibilityBeforeHide`로 기록하고, `.restore`에서 그 값으로 되돌린다.
- 세로 판정: 앱의 다른 화면은 실제 뷰 크기의 폭 < 높이로 판정한다. `UIDevice.orientation`은 쓰지 않는다.

## 2. 방법 비교 (요약)

| 방법 | 판단 |
|---|---|
| 3열 `NavigationSplitView` | `NavigationSplitViewVisibility`(.all/.doubleColumn/.detailOnly/.automatic)에 "sidebar + content만" 상태가 없다(3열 `.doubleColumn`은 content + detail). 제외. |
| 내용 칸을 `if`로 트리에서 빼기 | 편집기 `.onDisappear`가 실행돼 말씀 노트의 빈 새 묵상/요약이 `deleteIfEmpty`로 삭제되는데 선택은 그 객체를 계속 가리킨다. 편집 모드·스크롤·커서도 초기화된다. 제외. |
| 사이드바가 열리면 선택 해제 | "닫으면 원래 노트 그대로" 요구를 어기고 restore 계약과 엉킨다. 제외. |
| **트리에 남긴 채 폭 0 + 투명 (채택)** | 상태가 보존된다. 툴바 항목, 키보드, 재선택은 별도로 처리한다. |
| 사이드바 오버레이(`.prominentDetail`) | 스타일이 정적이라 가로·모든 섹션에 적용된다. 앱 전체 UX 결정이 필요해 제안만 했다. |

## 3. 구현 (v3)

### 3.1 판정 — `SidebarNavigationView` 한 곳 (B-1, B-5)

- 판정 대상을 **창 전체 크기**로 바꿨다. v2까지는 사이드바를 뺀 본문 크기라, 960×800처럼 약간 가로로 긴 창도 사이드바를 열면 세로로 판정됐다.
- 측정: `NavigationSplitView`(창 루트)에 `.background { Color.clear.ignoresSafeArea().onGeometryChange(for: Bool.self, of: { $0.size.width < $0.size.height }) { isPortraitWindow = $0 } }`를 붙였다.
  - 근거 1: 이 뷰는 장면(scene) 루트의 `NavigationSplitView`라 그 크기가 창 콘텐츠 크기다. `ignoresSafeArea()`의 기본 regions `.all`은 container + keyboard다(Apple 문서 `ignoresSafeArea(_:edges:)`, `SafeAreaRegions`). 그래서 안전 영역과 **키보드 영역까지 무시한 창 크기**를 잰다.
  - 근거 2: `onGeometryChange(for:of:action:)`는 변환 결과가 바뀔 때만 action을 부른다(Apple 문서의 `onGeometryChange(for:of:action:)` 설명: 변환 값이 바뀔 때 action 호출. 실기기에서 첫 표시 시 호출 여부를 함께 확인할 것). 변환을 Bool로 해서 **판정이 바뀔 때만** `@State`를 쓴다. 크기를 계속 저장하지 않는다.
  - 처음 값: 앱의 `VerseZoomView`가 같은 API의 첫 호출에 기대어 초기 크기를 받는다. 첫 측정 전 기본값 false는 "숨기지 않음"(기존 배치)이라 안전한 쪽이다.
  - 대안이었던 `UIWindowScene` 크기(`effectiveGeometry` KVO 등)는 UIKit 브리징이 필요하고 SwiftUI 측정과 결과가 같아 택하지 않았다.
- 최종 판정 `concealsDetailBesideSidebar = isIPadIdiom && columnVisibility != .detailOnly && isPortraitWindow && horizontalSizeClass == .regular`(iOS). detail `NavigationStack`에 환경값 `EnvironmentValues.concealsDetailBesideSidebar`로 내려준다. 창마다 자기 상태를 내려주므로 다중 창에서도 섞이지 않는다. macOS는 설정하지 않아 기본값 false다.
- 말씀 노트·개요는 이 Bool 하나만 읽는다. v2에 있던 화면별 `containerSize` 상태와 측정은 없앴다. 크기 변화가 목록 뷰 재계산을 일으키지 않는다.

### 3.2 숨김 — 공통 수정자 `View.concealableDetailColumn(_:)` (새 파일 `Views/Navigation/ConcealableDetailColumn.swift`)

- 순서: `.frame(width: 숨김 ? 마지막 보인 폭 : nil)` → `.frame(width: 숨김 ? 0 : nil, alignment: .leading)` → `.opacity` → `.allowsHitTesting` → `.accessibilityHidden` → `.environment(\.isSplitDetailConcealed, 숨김)` → (iOS) 숨김 시작 시 `resignFirstResponder`.
- "마지막 보인 폭"은 수정자 내부 `@State`다. 보이는 동안의 폭을 기록하고, 숨긴 동안 그 폭을 그대로 제안해 다시 보일 때 줄바꿈이 바뀌지 않는다. 상태가 수정자 안에 있어 값이 바뀌어도 옆의 목록 뷰는 다시 계산되지 않는다. 한 번도 보인 적 없이 숨김으로 시작하면 320pt로 배치한다. 보이지 않는 배치에만 쓰이고, 보이는 순간 실제 폭으로 다시 배치된다.
- 호출부는 `#if os(iOS)`로만 붙인다. macOS에는 수정자 자체가 없다.
- 환경값 `EnvironmentValues.isSplitDetailConcealed`(기본 false)는 편집기들이 툴바 항목을 빼는 데 쓴다. v2의 화면별 키 두 개(`isWordNoteDetailConcealed`/`isOutlineDetailConcealed`)를 하나로 합쳤다.

### 3.3 재선택과 복원 기록 (B-4, 개요 B1)

- `SidebarVisibilityRequest.Request`에 `.hideKeepingRestoreState`와 `requestHideKeepingRestoreState()`를 추가했다. `SidebarNavigationView`는 이 요청에서 `columnVisibility = .detailOnly`만 하고 `wasVisibleBeforeHide`를 **기록하지 않는다**.
- 숨긴 상태에서 이미 선택이 있는데 다시 고르면 이 요청을 보낸다. 말씀 노트: 다른 항목, 같은 항목 재탭, `+` 새 항목, 사이드바 "최근" 진입. 개요: 다른 책·장, 같은 항목, "개요 화면 열기" 요청. 선택 없음 → 값은 기존 `.onChange`가 `.hide`를 보내므로 그대로다.
- 결과: 선택 해제나 화면 이탈 때의 `.restore`는 첫 선택 때 기록한 값을 쓴다. 기능 추가 전과 같은 상태로 돌아간다. 기능 추가 전에는 다시 고를 때 hide를 보내지 않았으므로 기록도 첫 선택 값 그대로였다.
- 기존 `requestHide()`/`requestRestore()`와 `.hide`/`.restore` 처리는 바꾸지 않았다. relverse1 등 기존 호출부는 영향이 없다. `Request`를 `switch`로 소비하는 곳은 `SidebarNavigationView` 하나뿐임을 확인했다.

### 3.4 선택 바인딩 최소화 (B-5)

- 말씀 노트 `listSelection`: 숨기지 않을 때(가로, 세로에서 사이드바가 닫혀 있을 때)와 macOS는 기존 `$selectedItem`을 그대로 넘긴다. 숨긴 동안에만 `Binding(get:set:)`을 만든다.
- 개요 `listSelection`: 같은 방식으로 `$selection` 또는 `applySelection`을 거치는 바인딩을 넘긴다. `applySelection`은 숨기지 않을 때와 macOS에서 단순 대입이다.

### 3.5 시트 경계 (B-6)

- Mac 현재 소스 확인: `MemoDetailView`/`WordSummaryEditorView`는 `.sheet(item: $drilldownTag) { TagDrilldownView(tag:) }`를 띄우고, `TagDrilldownView`(`Views/TagRelations/TagDrilldownView.swift:44`) 안에서 `MemoDetailView(memo:)`가 쓰인다. 숨김 상태(예: 시트가 열린 채 회전)가 시트로 이어지면 시트 안 편집기의 버튼이 빠질 수 있다. 그래서 두 편집기의 `TagDrilldownView` 시트 내용에 `.environment(\.isSplitDetailConcealed, false)`를 걸었다.
- 같은 편집기의 다른 시트(`WordNoteVersePickerSheet`)에는 편집기가 없어 손대지 않았다. `OutlineBookBulkEditView`에는 시트가 없다.
- 그 밖의 편집기 사용처(`BibleReadingView`, `SearchView`, `WordSummaryPanelController`)는 숨김 범위 밖이라 기본값 false다.

### 3.6 툴바 항목

- `MemoDetailView`: 숨김 중 "편집/완료"와 공유를 넣지 않는다.
- `WordSummaryEditorView`: 숨김 중 "편집/완료" 토글을 넣지 않는다.
- `OutlineBookBulkEditView`: 숨김 중 가운데 제목(iOS `.principal`)과 눈/연필 토글을 넣지 않는다. 그동안 트리 쪽 "개요" 제목이 보인다.

### 변경 파일 (8개, 1개 신규)

`Services/SidebarVisibilityRequest.swift`, `Views/Navigation/SidebarNavigationView.swift`, `Views/Navigation/ConcealableDetailColumn.swift`(신규), `Views/WordNote/WordNoteHomeView.swift`, `Views/Memo/MemoDetailView.swift`, `Views/WordSummary/WordSummaryEditorView.swift`, `Views/Outline/OutlineTreeView.swift`, `Views/Outline/OutlineBookBulkEditView.swift`.
프로젝트는 `PBXFileSystemSynchronizedRootGroup`이라 신규 파일은 폴더에 두면 타깃에 자동으로 포함된다(단일 앱 타깃).

## 4. 엣지 케이스

| 상황 | 기대 동작 |
|---|---|
| 세로, 노트/장 선택 후 사이드바 다시 열기 | 내용 칸이 사라지고 목록/트리가 넓어진다. 편집기 툴바 버튼이 없다. |
| 위 상태에서 사이드바 닫기(버튼·스와이프·⌥⌘S) | 같은 항목, 같은 모드, 같은 줄바꿈·스크롤로 다시 보인다. |
| 위 상태에서 항목 다시 고르기 | 사이드바가 닫히고 그 내용이 보인다. 복원 기록은 첫 선택 때 값 그대로다. |
| 사용자가 사이드바를 닫아 둔 채 A 선택 → 사이드바 열기 → B 선택 → 다른 섹션으로 이동 | `.restore`가 "A 선택 전 = 닫힘"으로 되돌린다. 기능 추가 전과 같다. |
| 선택 없이 사이드바가 열린 채 진입(세로) | 빈 내용 칸도 숨긴다(사용자 결정 4). 첫 탭은 기존 `.hide`로 처리한다. |
| 말씀 노트 빈 새 묵상 → 사이드바 열기 → 닫기 | 삭제되지 않고 그대로다. |
| 960×800 같은 약간 가로로 긴 Stage Manager 창 | 창 모양이 가로라 사이드바를 열어도 숨기지 않는다(v3 수정). |
| Split View·Stage Manager에서 세로로 긴 regular 창 | 숨긴다. compact로 접히면 적용하지 않는다. |
| 키보드 표시 중 | 판정에서 키보드 영역을 무시하므로 바뀌지 않는다. |
| 회전 | 창 모양 Bool이 바뀌는 순간 전환된다. 선택은 유지된다. |
| 숨김 중 `TagDrilldownView` 시트 | 시트 안 묵상 편집기의 버튼이 정상 표시된다(경계에서 false). |
| macOS / 아이폰 | 판정 환경값을 설정하지 않고(false), 수정자를 붙이지 않는다(macOS). 아이폰은 이 화면들의 split 분기를 쓰지 않는다. |

## 5. 한계 (현재대로 두기로 한 것)

- **키보드 내림 범위(B-2)**: 숨김이 시작될 때 `UIApplication.sendAction(resignFirstResponder)`로 앱 전체의 first responder를 내려놓는다. 그 순간 사이드바 검색창, 말씀 노트 목록 검색창, 개요 "책 이름 검색"에 입력 중이었다면 그 키보드도 내려간다. 회전 등 드문 경우다. 사용자 결정 3에 따라 유지한다.
- **Tab 포커스(B-7)**: `allowsHitTesting(false)`·`accessibilityHidden(true)`는 하드웨어 키보드 Tab/방향키 포커스 이동을 막지 않는다. 숨긴 편집기로 포커스가 갈 수 있는지 실기기 확인이 필요하다. 현재대로 둔다.
- **다중 창 전파(B-3)**: `SidebarVisibilityRequest.shared`는 앱 전역 싱글턴인 기존 구조다. 한 창의 hide/restore 요청을 다른 창의 `SidebarNavigationView`도 받을 수 있다. 이번에 추가한 `.hideKeepingRestoreState`도 같은 채널이라 같은 한계를 가진다. 판정 환경값은 창별이다. 기존 구조라 바꾸지 않았다.
- 숨긴 편집기의 `.navigationTitle`은 숨긴 동안에도 적용된다. Stage Manager 창 제목이나 앱 전환기 표시는 실기기 확인이 필요하다.
- 처음부터 숨김으로 시작한 편집기는 320pt로 보이지 않게 배치됐다가, 보일 때 실제 폭으로 다시 배치된다.

## 6. relverse1과의 관계 (B-3 확인)

- `/home/claude/integ/relverse1.diff`가 고치는 파일은 `JBCHBibleResearchApp.swift`, `Views/Bible/BibleReadingView.swift`, `Views/Bible/BibleTopBar.swift`, `Views/Navigation/BibleReadingTarget.swift`(신규), `Views/Search/*` 6개다. `SidebarNavigationView.swift`와 `SidebarVisibilityRequest.swift`는 **고치지 않는다**. `BibleReadingView`에서 기존 `requestHide()`/`requestRestore()` 호출을 조건문으로 감쌀 뿐이다.
- 두 diff는 겹치는 파일이 없다. 이 diff가 새로 쓰는 이름(`concealsDetailBesideSidebar`, `isSplitDetailConcealed`, `ConcealableDetailColumn*`, `hideKeepingRestoreState`, `isPortraitWindow`)도 relverse1에 없다. 그래서 Mac 현재 파일 기준으로 만들었고, 어느 순서로 적용해도 된다.

## 7. 확인 방법 (실기기·시뮬레이터)

1. Xcode 빌드: iOS·macOS 대상 모두. 특히 `ToolbarContentBuilder` 안의 `if` 블록(항목 2개, `#if` 포함), 새 파일 포함 여부를 본다.
2. iPad 11인치·13인치·mini 세로, 말씀 노트·개요 각각: 항목 선택 → 사이드바 열기 → 내용이 숨고 목록이 넓어지는지, 툴바 버튼이 없는지 본다.
3. 사이드바 닫기 → 같은 항목, 같은 모드, 같은 스크롤 위치인지 본다.
4. 숨김 상태에서 다른 항목, 같은 항목, `+`(말씀 노트), "개요 화면 열기"(개요) → 사이드바가 닫히고 내용이 보이는지 본다.
5. 복원 기록: 사이드바를 닫은 채 A 선택 → 사이드바 열기 → B 선택 → 선택 항목 삭제(말씀 노트) 또는 다른 섹션으로 이동 → 기능 추가 전 빌드와 사이드바 결과가 같은지 비교한다.
6. 말씀 노트 빈 새 묵상 → 사이드바 열기·닫기 → 메모가 유지되고 크래시가 없어야 한다.
7. Stage Manager에서 960×800 정도의 창: 사이드바를 열어도 숨기지 않아야 한다. 세로로 긴 창에서는 숨겨야 한다.
8. 키보드를 띄운 채(목록 검색창) 회전·사이드바 토글: 판정이 키보드에 흔들리지 않는지 본다.
9. 숨김 중 회전으로 `TagDrilldownView` 시트가 열린 상태 → 시트 안 묵상 편집기의 "편집"·공유 버튼이 보여야 한다.
10. 가로·macOS가 기존과 같은지 본다.
11. VoiceOver와 하드웨어 키보드 Tab 이동(한계 B-7)을 확인한다.

## 8. 사용자 결정 (2026-10-29)

1. 세로에서 사이드바를 열면 본문이 옆으로 밀려난다.
2. 세로 판정은 화면(창) 모양 기준 → v3에서 창 전체 크기로 측정한다.
3. 숨김 시작 시 키보드 내림은 현재대로 둔다.
4. 선택이 없을 때도 숨긴다.
5. 개요 화면도 같은 방식으로 고친다.
- 남은 결정: 오버레이 방식은 앱 전체에 영향을 주므로 원할 때 별도로 결정한다.
