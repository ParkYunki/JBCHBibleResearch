# sermonkey1 — 설교 에디터 ⌘B 굵게 / ⌘I 기울임 (2026-10-29)

기준: Mac 현재 파일(sermonundo1 반영본). 변경 파일: `JBCHBibleResearch/Views/Sermon/SermonParagraphEditor.swift` 하나.
새 문구 없음(메뉴 항목을 추가하지 않음) → Localizable.xcstrings 변경 없음.

## 현재 상태 (소스 확인)
- iOS: 설교 에디터 `SermonEditorUITextView`는 편집 중 `allowsEditingTextAttributes = true`다(SermonParagraphEditor.swift
  `makeUIView`/`updateUIView`). 그래서 하드웨어 키보드 ⌘B/⌘I(iPadOS 메뉴 막대 Format)와 텍스트 선택 메뉴의 B/I가 시스템
  `toggleBoldface:`/`toggleItalics:` 기본 구현으로 처리되고 있었다. 이 경로는 툴바 버튼(`toggleTrait` → `togglingSermonTrait`, sermonundo1의
  실행 취소)과 별개다.
  - 굵게를 정하는 방식이 다를 수 있다. 앱은 글꼴 구간마다 trait를 뒤집는다. 시스템 방식은 공개 문서에 정의돼 있지 않다.
  - 실행 취소는 시스템 자체 항목으로 등록된다. 같은 굵게가 경로에 따라 다른 결과·다른 실행 취소 이름이 될 수 있었다.
- macOS: 앱 메뉴(AppCommands.swift)에 Format(서식) 메뉴가 없다. 파일 상단 ⚠️ "Format 메뉴 미구현"이 있고 `TextFormattingCommands`도 쓰지 않는다.
  그래서 NSTextView의 ⌘B/⌘I를 받을 `addFontTrait:` 메뉴 항목이 없어 ⌘B/⌘I는 지금 동작하지 않는다.
- 단축키 충돌: 앱 `Commands`의 ⌘ 단축키는 ⌘N, ⌘⇧N, ⌘O, ⌥⌘S, ⌘1~5, ⌘⇧T, ⌘⇧B(성경 조회 새 창), ⌘F, ⌘], ⌘[, ⌥⌘R이다.
  수정키 없는 ⌘B·⌘I는 쓰이지 않는다. 설교 에디터의 ⌃1~6(문단 스타일)과도 겹치지 않는다.

## 방식 선택과 근거
- **iOS: `toggleBoldface(_:)`/`toggleItalics(_:)` override**(`keyCommands` 대신).
  - 하드웨어 ⌘B/⌘I, iPadOS 메뉴 막대, 텍스트 선택 메뉴 B/I가 모두 이 두 표준 편집 동작(`UIResponderStandardEditActions`)으로 모인다.
    override 하나로 모든 입구가 같은 앱 경로를 탄다.
  - `keyCommands`로 ⌘B를 따로 잡으면 시스템 메뉴 경로(선택 메뉴 B/I)는 시스템 구현에 남는다. 결과가 갈리고, 같은 단축키가 두 곳에 정의돼 우선순위 문제가 생긴다.
  - override한 메서드는 시스템 구현(`super`)을 부르지 않으므로 실행 취소 등록은 앱 경로 한 번뿐이다.
  - 같은 override를 쓰는 공개 코드 사례: Tusker 프로젝트 커밋([git.shadowfacts.net](https://git.shadowfacts.net/Fahim/Tusker/commit/4bccbe254b60dd32549c25a8b17342b4b3015baa.patch)).
    UITextView 서브클래스에서 `override func toggleBoldface(_ sender: Any?)`로 앱 서식 경로로 보낸다.
  - 밑줄(`toggleUnderline:`)은 앱 경로가 없어 시스템 그대로 둔다(이번 요청 범위 밖).
- **macOS: `performKeyEquivalent(with:)` override**(이 텍스트뷰가 첫 응답자이고 수정키가 정확히 ⌘일 때만).
  - 처리할 메뉴 항목이 없으므로 `addFontTrait:`/`changeFont:`를 가로챌 대상이 없다. 메뉴를 새로 만들면 모든 텍스트 입력(메모 등)에 영향을 준다.
  - ⌘ 조합은 `performKeyEquivalent`로 먼저 전달된다. `performKeyEquivalent`는 창의 모든 뷰에 전달되므로 `window?.firstResponder === self`로 이 에디터만 받는다.
  - 처리하면 true를 돌려 다른 곳으로 전파되지 않는다. 처리하지 않으면 `super`로 넘겨 기존 동작이 그대로다.
  - 비라틴 입력 소스(한글 두벌식 등)에서는 `charactersIgnoringModifiers`가 "ㅠ"/"ㅑ" 같은 그 언어 글자를 돌려줄 수 있다.
    그래서 ASCII가 아니면 물리 키 코드(`kVK_ANSI_B` 0x0B, `kVK_ANSI_I` 0x22)로 판별한다. ASCII 글자가 오면(드보락 등) 글자로 판별한다.
  - 글꼴 패널(⌘T, `changeFont:`)은 건드리지 않는다. 임의 글꼴 지정이라 굵게 토글로 바꿀 수 없고, NSTextView 자체 실행 취소가 이미 된다(이중 등록 없음).
- 공통: 두 플랫폼 모두 텍스트뷰의 핸들러가 툴바 버튼과 같은 `SermonParagraphEditingProxy.toggleBold()/toggleItalic()`을 부른다.
  - 선택 범위 trait 토글, 굵게 변형이 없는 글꼴이면 원래 글꼴 유지(`togglingSermonTrait`), 캐럿만 있으면 타이핑 속성 토글, sermonundo1 실행 취소("굵게"/"기울임")가 버튼과 같다.
  - 프록시가 이 텍스트뷰를 가리키지 않으면 핸들러가 false를 돌려준다. 그때 iOS는 시스템 구현, macOS는 `super`로 넘긴다(안전한 대체).
  - 읽기 전용(`isEditable == false`)이면 처리하지 않는다.
  - 한글 조합 중이면 `unmarkText()`로 조합을 먼저 확정한 뒤 토글한다(조합 중인 글자 위 attribute 변경 방지).

## 검토 반영 (B1·B2)
- B1 (macOS): `performKeyEquivalent` 조건에 `window?.isKeyWindow == true`를 추가했다. 키 창이 아닌 창에 남은 첫 응답자는 처리하지 않는다.
- B2 (macOS): 조합 확정 방식은 지금대로 `unmarkText()`만 쓴다.
  - 문서 근거: `NSTextInputClient.unmarkText()`는 "The text view should accept the marked text as if it had been inserted normally"
    — 조합 글자를 확정한다.
  - `NSTextInputContext.discardMarkedText()`는 "Tells the Cocoa text input system to discard the current conversion session"이라고만 적혀 있다.
    입력기가 그 순간 남은 글자를 다시 보내 확정할지(중복 입력 위험), 버릴지(손실 위험)를 문서로 확정할 수 없다. 그래서 추가하지 않았다.
  - 대신 아래 실기 테스트 6번(★)으로 확인한다. 문제가 보이면 그 결과로 `discardMarkedText` 추가 여부를 정한다.

## 영향 범위
- 서브클래스 `SermonEditorUITextView`/`SermonEditorNSTextView`는 설교 편집기에서만 쓴다(뷰어는 일반 텍스트뷰). 메모 `RichTextEditor`, 검색창 등 다른 텍스트 입력은 영향 없다.
- 마인드맵은 별도 화면·별도 뷰라 영향 없다. 앱 메뉴(`AppCommands`) 변경도 없다.

## 실기기 테스트
iOS(iPad + 하드웨어 키보드) / macOS 각각:
1. 글자 선택 → ⌘B → 툴바 굵게 버튼과 결과가 같은지(Paperlogy·고운바탕·시스템 글꼴 각각). 다시 ⌘B로 해제.
2. 선택 → ⌘I / 다시 ⌘I. 고운바탕처럼 기울임 변형이 없는 글꼴에서 버튼과 같은 결과(변화 없음 등)인지.
3. 캐럿만 두고 ⌘B → 타이핑: 굵게 입력, 다시 ⌘B → 일반 입력. 실행 취소 메뉴에 항목이 생기지 않는지.
4. 선택 후 ⌘B → 실행 취소 1회로 복원, 메뉴 이름 "굵게"(en Bold). 다시 실행. 실행 취소 항목이 두 개 생기지 않는지.
5. 굵은 부분과 일반 부분이 섞인 선택에서 ⌘B와 툴바 버튼 결과가 같은지.
6. ★ **한글 조합 중 ⌘B 후 계속 입력** (iOS·macOS 모두, 반드시 확인): "한"까지 조합 중인 상태에서 ⌘B를 누르고 이어서 "글"을 입력한다.
   "한글"이 되어야 한다. 다음이 없는지 본다: 글자가 사라짐, "한"이 두 번 들어감("한한글"), 받침이 다음 글자로 넘어감("하ㄴ글"/"하날"),
   ⌘B 이후 글자에 굵게가 적용되지 않음. ⌘I도 같다. 한글 입력 소스 상태에서 ⌘B/⌘I가 동작하는지(macOS 키 코드 판별)도 확인한다.
   문제가 보이면 macOS는 `unmarkText()` 뒤 `inputContext?.discardMarkedText()` 추가를 검토한다.
7. iOS: 텍스트 선택 메뉴(서식 > B/I)가 같은 결과·같은 실행 취소인지. 밑줄(U)은 예전처럼 시스템 동작인지.
8. macOS: ⌘⇧B(성경 조회 새 창)·⌘1~5·⌘F 등 다른 단축키가 설교 에디터 포커스 중에도 그대로 동작하는지.
9. macOS: 글꼴 패널(⌘T)로 굵게 지정 → 실행 취소 1회로 복원(기존 동작 유지).
10. 메모 편집기·검색창에서 ⌘B/⌘I가 예전과 같은지(메모는 기존 시스템 동작). 마인드맵 화면에서 ⌘B/⌘I가 아무 영향이 없는지.
11. 읽기 전용(회차 사본 참조 등)에서 ⌘B/⌘I가 내용을 바꾸지 않는지.
12. macOS: 설교 에디터 창이 뒤에 있고 다른 창(성경 조회 등)이 키 창일 때 ⌘B/⌘I가 에디터를 바꾸지 않는지.
