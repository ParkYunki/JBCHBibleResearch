# sermonstyle2 — 설교 에디터: 스타일 변경 시 글자색 유지 + 스타일 변경 실행 취소 (2026-10-29)

기준: Mac 현재 파일(sermonstyle1 반영본). 변경 파일
- `JBCHBibleResearch/Views/Sermon/SermonParagraphEditor.swift`
- `JBCHBibleResearch/Localizable.xcstrings` (새 문구 1개: "문단 스타일 변경", ko/en)

## 1. 스타일을 바꿔도 사용자 글자색 유지

### 원인 (기존 동작)
pill/F1~F6 경로는 `applyStyle`에 `previousSnapshot`을 넘기지 않아 `isManualColor`가 항상 false → 모든 글자색이 새 프리셋 색으로 덮였다.
강조1(와인)·강조3(파랑)·직접 지정 색이 사라졌다.

### 변경
- `applyStyle`의 `dropsStyleBold` → `isStyleChange`로 이름 변경(이제 굵게+색 둘 다 다룬다). 호출부는 iOS·macOS `applyParagraphStyle` 둘뿐.
- 구간(이전 스타일 attribute 구간, 없으면 문단 첫 글자 스타일, 그것도 없으면 본문 — sermonstyle1 B와 같은 분할)마다 이전 스타일의
  프리셋 글자색을 구해 비교한다.
  - 색 없음 → 새 프리셋 색
  - 이전 프리셋 색과 같음 → 새 프리셋 색
  - 다름 → 그대로 둔다(사용자 색)
- 불러오기(`apply`, `isStyleChange == false`)는 기존 스냅샷 비교 그대로(변경 없음).

### 색 비교 방법과 근거
- `PlatformColor.sermonIsClose(to:)`(SermonTextLayout.swift, sRGB 성분 차 < 0.01)를 쓴다.
  - 강조 판정·해제(`SermonEmphasisEditor.isApplied/clear`), 옛 말씀구절 배경 제거가 이미 같은 함수를 쓴다 → 앱 안에서 "같은 색" 기준이 하나로 맞는다.
  - RTF 저장/복원은 색을 8비트 성분으로 저장한다(1/255 ≈ 0.0039 오차) → 0.01 허용오차면 다시 연 문서에서도 프리셋 색으로 인식된다.
    `isEqual`(정확 비교)은 색 공간·양자화 차이로 어긋날 수 있어 쓰지 않았다.
  - 0.01 안쪽으로 프리셋과 거의 같은 색을 사용자가 고른 경우는 프리셋 색으로 본다(구별 불가, 허용).
- 동적 색/다크 모드:
  - 설교 프리셋 색은 모두 hex에서 만든 고정 색(`Color(hex:)` → `PlatformColor`)이다. hex가 잘못된 경우에만 `.primary`(동적)로 대체된다.
  - 에디터는 라이트 외형 고정(iOS `overrideUserInterfaceStyle = .light`, macOS `.aqua`)이고 텍스트 스토리지에 테마 글자색(`settings.bibleTextColor`)을
    넣는 코드가 없다(그 값은 SwiftUI 화면 장식용). 따라서 비교 대상은 고정 색끼리다.
  - 붙여넣기 등으로 동적 색(`labelColor` 계열)이 들어온 경우: `sermonRGBA`가 그 시점 외형으로 해석한 값과 비교되며, 고정 프리셋 색과는
    보통 달라 "사용자 색"으로 남는다(보수적으로 보존).
- 굵게 판정과 같은 구조: 구간별 이전 스타일 → 그 프리셋 값과 비교 → 같으면 프리셋에서 온 것으로 보고 새 스타일 값으로 바꾼다.

### 강조1~3과의 일관성
- 강조1 = 와인색 + 굵게, 강조2 = 노란 배경, 강조3 = 파란색 + 밑줄.
- 기본 설정에서 **중주제 프리셋 색(#753B44)이 강조1 색과 같다**(UserSettingsStore 690행, SermonTextLayout `oneColor`).
- 규칙:
  - 이전 프리셋이 굵고 글자색이 강조1 색이며 강조1 색이 이전 프리셋 색과 다르면 → 강조1로 확정 → 굵게도 보존(색과 같이 남김).
    이 보완이 없으면 굵은 제목(대주제·소주제) 안의 강조1이 본문으로 바뀔 때 "와인색인데 굵지 않은" 반쪽 상태가 된다.
  - 이전 프리셋 색이 강조1 색과 같으면(기본 중주제) → 강조1을 구별할 수 없음 → 색은 새 프리셋 색, 굵게도 제거(둘 다 프리셋으로 봄).
  - 강조2(배경)·강조3 밑줄은 원래부터 건드리지 않는다. 강조3 색은 프리셋과 다르면 유지된다.
- 결과 표(기본 설정, → 본문):
  | 이전 | 강조1 | 강조3 | 직접 지정 색 |
  |---|---|---|---|
  | 대주제(굵음, #2B211D) | 색·굵게 유지 | 색·밑줄 유지 | 유지 |
  | 중주제(굵음, #753B44) | 색·굵게 모두 초기화(구별 불가) | 유지 | 유지(#753B44와 다르면) |
  | 본문/인용/말씀구절 | 색·굵게 유지 | 유지 | 유지 |

## 2. 스타일 변경 실행 취소/다시 실행

### 기존 체계 확인
- 타이핑: `UITextView`/`NSTextView` 자체 `undoManager`(macOS는 `allowsUndo = true`). 앱이 따로 관리하지 않는다.
- 에디터가 `textStorage`를 직접 고치는 기능은 **모두 실행 취소 미지원**이다(소스에 `registerUndo`·`shouldChangeText` 없음):
  강조1~3, 굵게/기울임 버튼, 글자색, 글꼴, 크기, 정렬, 줄간격, 목록, "말씀구절 + 추가"(글자 삽입까지 기록 없이 들어감).
  예외: macOS 글꼴 패널(⌘T)은 NSTextView가 직접 처리해 실행 취소된다. → 이번에 함께 할지는 판단 요청.
- 마인드맵만 앱 자체 `MindMapUndoCoordinator`(registerUndo + 역방향 재등록)를 쓴다.

### 변경
- macOS: NSTextView 표준 절차. `shouldChangeText(in: 문단범위, replacementString: nil)` → 스타일 적용 → `didChangeText()` →
  `setActionName("문단 스타일 변경")`. 그 범위의 원래 attributed 내용은 텍스트뷰가 저장하고 되돌리며, 다시 실행도 텍스트뷰가 처리한다.
  범위 길이 0(문서 끝 빈 줄)이면 등록하지 않는다. `shouldChangeText`가 false(편집 불가)면 예전처럼 적용만 한다.
- iOS: UITextView에는 서식만 바꾼 변경을 실행 취소에 등록하는 공개 API가 없어 `textView.undoManager`(타이핑과 같은 관리자)에 직접 등록한다.
  - 적용 전 `attributedSubstring(문단범위)`(문단 스타일·줄간격·목록·말씀구절 박스·글꼴·색 등 모든 attribute), 선택 범위, 문서 길이를 저장한다.
  - 되돌릴 때 `setAttributes`로 구간별 attribute를 그대로 덮는다(글자는 건드리지 않음). 선택 범위를 복원한다. 되돌리기 직전 상태를
    반대 방향으로 다시 등록해 다시 실행이 된다(`MindMapUndoCoordinator`와 같은 방식, `MainActor.assumeIsolated` 포함).
  - target을 텍스트뷰로 등록해 기존 `dismantleUIView`의 `removeAllActions(withTarget: uiView)`가 화면 전환 시 함께 지운다.
- 한 번 누름 = 실행 취소 한 단계: 여러 문단 선택도 범위 하나로 저장/등록한다.

### 안전성 검토
- 저장·동기화: 되돌리기는 `textStorage`의 attribute 편집이라 `didProcessEditing(.editedAttributes)` → 코디네이터가 RTF·plain·`paragraphStyles`를
  다시 내보내 바인딩 갱신 → 기존 저장 경로(`onDisappear`/완료 → `save()`)가 그대로 저장한다. `lastExportedRTF`를 먼저 갱신하므로
  `update*View`가 다시 불러오지 않는다. 툴바 pill 표시는 같은 경로의 `refreshActiveStyle()`로 맞춰진다.
- 문단 메타데이터: `.sermonParagraphStyle`·`.sermonLineHeight`·`.sermonListKind`·말씀구절 박스 attribute는 스냅샷 안에 있어 함께 되돌아가고,
  `paragraphStyles`는 이 attribute에서 다시 만들어진다. 말씀구절 연결(`SermonVerseReference.paragraphIndex`)은 스타일 적용이 바꾸지 않으므로
  되돌릴 것이 없다(문단 수·순서 불변).
- 그사이 텍스트가 바뀐 경우(iOS):
  - 실행 취소 기록이 있는 타이핑은 같은 관리자의 LIFO 순서로 먼저 되돌려지므로 우리 항목 차례에는 글자가 원래대로다.
  - 기록 없이 바뀐 경우(외부 동기화 `loadContent`, "말씀구절 + 추가" 등): 문서 길이와 범위 글자가 저장 때와 다르면 아무것도 하지 않는다
    (잘못된 위치에 서식을 입히거나 범위 초과로 크래시하지 않음). 그 항목은 소비되고 다시 실행 항목은 생기지 않는다.
  - 남는 위험: 길이를 바꾸지 않는 기록 없는 편집이 범위 글자까지 똑같이 만들면 그대로 적용된다(같은 글자 위 서식 복원이라 실해 없음).
- macOS는 텍스트뷰 자체 기록이라 타이핑 기록과 같은 체계로 순서가 유지된다. 단, 외부 동기화(`loadContent`의 `setAttributedString`)가
  실행 취소 스택을 비우지 않는 것은 기존 타이핑 실행 취소와 같은 기존 문제다(이번 범위 밖).

### 1차 검토 반영 (B1~B3)
- B1 (iOS 묶음): 등록 전에 `undoManager.groupingLevel == 0`이면 `beginUndoGrouping`/`endUndoGrouping`으로 직접 감싼다. 열린 묶음
  (UIKit의 이벤트 단위 자동 묶음 등)이 있으면 그 안에 넣는다. `setActionName`은 현재 열린 최상위 묶음의 이름을 정하므로 묶음을 닫기
  **전에** 부른다(직접 연 묶음이면 그 묶음, 열린 묶음이면 그 묶음의 이름). 되돌리는 중(undo/redo 실행 중)에는 UndoManager가 반대 방향
  묶음을 열어 두므로 `groupingLevel > 0`이라 직접 감싸지 않고, 그 안의 `setActionName`이 다시 실행 메뉴 이름이 된다.
- B1 (타이핑 묶음 분리): UIKit에는 `NSTextView.breakUndoCoalescing()`에 해당하는 공개 API가 없다(`UITextView`·`UITextInput`·
  `UIResponder` 모두 없음. `UndoManager`의 공개 API로는 UIKit 내부 타이핑 묶음을 끊을 수 없다). → **한계**: iOS에서 직전 타이핑과
  같은 묶음으로 합쳐지면 실행 취소 한 번에 타이핑과 스타일 변경이 함께 되돌아갈 수 있다. 이때도 LIFO로 스타일 attribute → 타이핑
  순서로 복원되어 안전하다(검토 확인).
- B2 (iOS 타이핑 속성): 실행 취소·다시 실행 모두 복원 뒤 선택 범위를 되돌리고, 그 캐럿 문단의 스타일(`currentParagraphStyle()`)로
  기존 `applyTypingAttributes` 경로를 다시 태운다(글꼴·문단 모양·줄간격/목록·스타일·말씀구절 박스). `refreshActiveStyle()`로 pill 표시도
  바로 맞춘다. 프록시는 약하게 잡고, 프록시가 없거나 다른 텍스트뷰를 가리키면 attribute 복원만 한다.
- B3 (macOS): `shouldChangeText` 전에 `textView.breakUndoCoalescing()`을 불러 직전 타이핑 묶음과 분리한다.

### 다음 번역 일괄 처리 대상
- `"문단 스타일 변경"` — 현재 ko·en만 있음(en "Change Paragraph Style"). 실행 취소/다시 실행 메뉴에 그대로 보이는 문구다.
  나머지 언어(de, en-CA, es, es-MX, fil, fr, fr-CA 등 기존 키와 같은 언어 집합)는 다음 일괄 처리 때 넣는다.

### 실기 확인 필요(정적 분석 한계)
- macOS: 서식만 바꿀 때 `shouldChangeText(..., nil)`의 실행 취소가 커스텀 attribute(`.sermonParagraphStyle` 등)까지 되돌리는지
  (AppKit은 범위의 attributed 내용을 저장하는 것으로 알려져 있으나 실기 확인 권장).
- iOS: 타이핑 직후 스타일 변경 시 UIKit 묶음과 합쳐져 실행 취소 한 번에 둘 다 되돌아가는지(위 한계).

## 새 문구
- "문단 스타일 변경" — en "Change Paragraph Style" (ko·en만, 실행 취소 메뉴의 동작 이름).

## 테스트 항목
1. 본문에 강조1·강조3·직접 색 → 대주제 → 본문: 색 유지, 강조1 굵게 유지, 나머지 글자는 각 프리셋 색.
2. 중주제(기본 #753B44) → 본문: 전체가 본문 색·Regular(강조1이 섞여 있어도 초기화 — 구별 불가).
3. 대주제 → 중주제 → 소주제 → 본문 연속: 매번 프리셋 색·굵기로 바뀌는지.
4. 여러 문단(대주제+본문) 선택 → 인용: 문단별 판정.
5. iOS·macOS: 스타일 버튼 1회 → 실행 취소 1회로 이전 스타일·색·굵기·줄간격·목록·말씀구절 박스 복원, 다시 실행으로 재적용.
   F1~F6도 같은지. 실행 취소 메뉴에 "문단 스타일 변경"이 보이는지(macOS 편집 메뉴, iPad ⌘Z/흔들기).
6. 스타일 변경 → 타이핑 → 실행 취소 2회: 타이핑, 스타일 순서로 되돌아가는지.
7. 실행 취소 후 화면 닫기/다시 열기·다른 기기 동기화: 되돌린 상태가 저장되는지.
8. 문서 끝 빈 줄에서 스타일 변경 → 실행 취소 항목이 생기지 않는지(타이핑 속성만 바뀜).
9. ru/th 언어에서 1~3 반복.
