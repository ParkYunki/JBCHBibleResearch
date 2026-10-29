# sermonundo1 — 설교 에디터 서식 버튼 실행 취소/다시 실행 (2026-10-29)

기준: Mac 현재 파일(sermonstyle2 반영본). 변경 파일
- `JBCHBibleResearch/Views/Sermon/SermonParagraphEditor.swift`
- `JBCHBibleResearch/Localizable.xcstrings` (새 키 3개, ko/en만)

## 대상과 범위
| 버튼 | 바뀌는 범위 | 실행 취소 메뉴 이름(키) |
|---|---|---|
| 강조1~3 | 선택 범위 | `강조%lld`(기존, `SermonEmphasis.displayName`) |
| 강조 해제 | 선택 범위 | `강조 해제`(기존) |
| 굵게 / 기울임 | 선택 범위 | `굵게` / `기울임`(새 키) |
| 글자색 | 선택 범위 | `색상`(기존) |
| 글꼴 | 선택 범위 | `글꼴`(기존) |
| 크기 | 선택 범위 | `글자 크기`(기존) |
| 정렬 | `paragraphRange(for: 선택)` | `문단 정렬`(새 키 — 기존 `정렬`은 en "Sort"라 뜻이 달라 재사용하지 않음) |
| 줄간격 / 목록 | `setExtra`와 같은 문단 범위(`extraScope`) | `줄간격` / `목록`(기존) |

- 각 버튼이 실제로 고치는 범위를 소스로 확인했다. `SermonEmphasisEditor.apply/clear`는 문단 단위로 나눠도 선택 범위와의 교집합만 고친다.
  `setExtra`는 선택이 걸친 문단 전체를 고친다. 그래서 이 범위 계산을 `SermonParagraphStyleCodec.extraScope(for:in:)`로 빼서 `setExtra`와
  실행 취소 스냅샷이 같은 계산을 쓰게 했다(값은 전과 같고, 음수 방어 `max(0, …)`만 추가).
- **목록**: 기호는 글자가 아니다. `SermonLayoutManager.drawListMarkers`가 문단 attribute(`.sermonListKind`)를 보고 여백에 그린다
  (SermonTextLayout.swift `SermonListKind` 주석, `makeParagraphStyle`의 걸친 들여쓰기). 글자를 넣거나 빼지 않으므로 서식 복원 경로로 충분하다.
  글자 교체(`replace`/`replacementString`) 설계는 필요 없다.

## 구현 (sermonstyle2 공통 경로 재사용)
- iOS: `performUndoableAttributeEdit(on:range:actionName:_:)`를 새로 만들었다. 적용 전에 `attributedSubstring(range)`와 선택 범위를 저장하고,
  `edit`를 실행한 뒤 기존 `registerAttributeUndo`로 등록한다. 묶음 처리, 범위·글자 검증, 다시 실행 재등록은 기존 그대로다.
  - 타이핑 속성: 문단 스타일 변경은 기존처럼 `settings`를 넘겨, 되돌린 뒤 캐럿 문단의 프리셋으로 다시 맞춘다. 서식 버튼은 `settings: nil`을 넘긴다.
    선택 범위를 되돌리면 UITextView가 타이핑 속성을 비우고 그 위치 글자에서 다시 정한다. 그래서 굵게 같은 글자 서식을 프리셋으로 덮지 않는다.
    `refreshActiveStyle()`는 두 경우 모두 부른다(줄간격·목록 메뉴 체크 표시 갱신).
- macOS: 같은 이름의 헬퍼다. `breakUndoCoalescing()` → `shouldChangeText(in: range, replacementString: nil)` → `edit` → `didChangeText()` →
  `setActionName`을 차례로 부른다. `shouldChangeText`가 false(편집 불가)면 예전처럼 적용만 한다.
- 범위가 비어 있으면(캐럿만 있음, 문서 끝 빈 줄, 빈 문서) 등록하지 않는다. 기존 코드도 이때 `typingAttributes`만 바꾼다.

## 1차 검토 반영 (B1·B2)
- **B1 (iOS, 되돌린 뒤 타이핑 속성)**: UITextView는 선택 범위가 *실제로 바뀔 때만* 타이핑 속성을 비운다(`typingAttributes` 문서).
  같은 선택으로 되돌리면 정렬·줄간격·목록 버튼이 직접 넣은 `.paragraphStyle`·`.sermonLineHeight`·`.sermonListKind`가 남는다.
  글자 서식도 같은 이유로 남을 수 있다. 그래서 서식 버튼의 되돌리기·다시 실행 뒤에는 `SermonParagraphStyleCodec.typingAttributesAtCaret`로 직접 다시 맞춘다.
  - 문단 attribute(`paragraphLevelKeys`: 문단 모양·스타일·줄간격·목록·말씀구절 박스): 캐럿 문단 첫 글자에서 가져온다. 문서 끝의 빈 줄이면 바로 앞 글자에서 가져온다.
  - 글자 서식: 선택이 있으면 선택 첫 글자에서 가져온다. 캐럿이면 같은 문단의 바로 앞 글자에서, 문단 맨 앞이면 캐럿 위치 글자에서 가져온다.
  - 빈 문서면 nil이다. 되돌리기는 범위 길이 > 0일 때만 등록되므로 실제로는 생기지 않는다.
  - 문단 스타일 변경(sermonstyle2)은 기존대로 스타일 프리셋 경로(`applyTypingAttributes`)를 쓴다.
- **B2 (빈 실행 취소 항목)**: 바뀐 것이 없으면 등록하지 않는다.
  - iOS: 적용 전 `attributedSubstring(range)`와 적용 후 값을 `isEqual(to:)`로 비교해 같으면 등록하지 않는다.
  - macOS: 적용 뒤 마지막 항목을 지우는 방식은 안전하지 않다고 판단했다.
    - `UndoManager`에는 마지막 항목 하나만 지우는 공개 API가 없다.
    - `removeAllActions(withTarget:)`는 NSTextView가 내부 target으로 등록한 다른 항목(타이핑 등)까지 지울 수 있다.
    - `undo()`로 꺼내는 방식은 다시 실행 스택을 오염시킨다.
    → 그래서 사전 판정한다. 문서 사본 `NSTextStorage(attributedString:)`에 같은 편집을 먼저 적용해 보고, 범위 내용이 같으면 실제 적용과 등록을 모두 건너뛴다.
    결과가 같으므로 동작 차이는 없다. 편집 클로저는 이를 위해 대상 storage를 인자로 받게 바꿨다(사본과 실제에 같은 코드 적용).
  - 비용: iOS는 범위 길이에 비례하고(O(n), 적용 자체와 같은 차수), macOS는 사본 복사 때문에 문서 길이에 비례한다(O(N), 버튼 1회당 1번).
    설교문 크기(수십 KB 안팎)에서는 문서 전체를 선택해도 적용 비용과 같은 차수라 문제없다. 매우 큰 문서(수 MB)는 실기 확인을 권장한다.
  - 문단 스타일 변경 경로(sermonstyle2)는 헬퍼 밖이라 이번 비교 대상이 아니다(같은 스타일 재적용 시 빈 항목이 생길 수 있음 — 필요하면 다음 라운드).

## 캐럿만 있을 때 등록하지 않는 근거
- AppKit에서 실행 취소 등록은 `shouldChangeText(in:replacementString:)`/`didChangeText()` 같은 텍스트 저장소 변경 절차에 묶여 있다.
  `typingAttributes`는 문서 내용이 아니라 "다음에 입력될 글자"의 속성이다. 선택이 바뀌면 시스템이 저절로 다시 정한다
  (NSTextView·UITextView의 `typingAttributes` 문서 설명).
- 저장 대상(RTF/`paragraphStyles`)도 바뀌지 않으므로 되돌릴 문서 상태가 없다. 등록하면 실행 취소를 눌러도 화면에 변화가 없는 항목이 생긴다.
- ⚠️ macOS 텍스트 편집기의 실제 동작(예: TextEdit에서 캐럿만 두고 ⌘B를 누른 뒤 실행 취소)은 실기 확인 권장.

## 이중 등록·다른 화면과 섞임
- macOS 글꼴 패널(⌘T)·서식 메뉴는 NSTextView 내부 `changeFont:` 등이 직접 실행 취소를 등록한다. 우리 버튼은 그 경로를 부르지 않고
  자기 헬퍼에서 한 번만 등록하므로 겹치지 않는다. iOS 편집 메뉴의 BIU(`allowsEditingTextAttributes`)도 UIKit 자체 경로라 별개다.
- 서식 버튼은 모두 `SermonEditorView`의 툴바에서만 부른다(호출부 grep 확인).
- 마인드맵은 `MindMapUndoCoordinator`가 SwiftUI `\.undoManager`에 자기 객체를 target으로 등록한다. 에디터 항목은 iOS에서 텍스트뷰를 target으로,
  macOS에서 NSTextView 자체 방식으로 등록되므로 서로의 항목을 실행하지 않는다.
  iOS 에디터 항목은 `dismantleUIView`의 `removeAllActions(withTarget: uiView)`로 화면을 떠날 때 지워진다.
  macOS에서 같은 창의 undoManager를 공유하는 것은 타이핑 실행 취소와 같은 기존 구조이고, 이번 변경으로 새로 생긴 섞임은 없다.

## "말씀구절 + 추가"는 제외 (이유)
- `SermonEditorView.insertVerseQuote`는 글자를 삽입한 뒤 그 문단 순번으로 `SermonVerseReference`를 만들어 SwiftData에 `insert`하고 저장한다.
- 글자 삽입만 실행 취소하면 구절 연결 레코드가 남는다. 그러면 없는 문단이나 다른 문단을 가리키게 되고, 통합 검색 인덱스(`reindexSermon`)도 어긋난다.
- 함께 되돌리려면 텍스트 실행 취소와 모델 삭제·복원을 한 묶음으로 엮어야 한다. 저장 시점(`DispatchQueue.main.async { save() }`)과
  CloudKit 동기화까지 고려해야 하므로 이번 범위에서 뺐다. 기존처럼 실행 취소 기록 없이 동작하며,
  iOS 쪽은 sermonstyle2의 길이·글자 검증 덕분에 이전 서식 실행 취소가 잘못 적용되지 않는다.

## 새 문구 (ko/en만) — 다음 번역 일괄 처리 대상
- `"굵게"` — en "Bold"
- `"기울임"` — en "Italic"
- `"문단 정렬"` — en "Alignment"
- (sermonstyle2에서 이월) `"문단 스타일 변경"` — en "Change Paragraph Style"
- 모두 실행 취소/다시 실행 메뉴에 그대로 보이는 문구다. 나머지 언어는 다음 일괄 처리 때 넣는다.

## 한계
- iOS: UIKit 타이핑 묶음과 분리하는 공개 API가 없다(sermonstyle2와 같음). 직전 타이핑과 한 단계로 합쳐질 수 있으나 LIFO 복원이라 안전하다.
- macOS 표준 실행 취소가 커스텀 attribute(`.sermonLineHeight`·`.sermonListKind` 등)까지 되돌리는지는 실기 확인이 필요하다(sermonstyle2와 같은 전제).

## 실기기 테스트 (iOS·macOS 각각)
1. 글자 선택 → 강조1 → 실행 취소: 색·굵게 복원 / 다시 실행: 재적용. 강조2(배경)·강조3(색·밑줄)·강조 해제도 같다.
2. 같은 강조를 다시 눌러 해제 → 실행 취소: 강조가 돌아오는지.
3. 굵게·기울임 각각 → 실행 취소/다시 실행. 메뉴 이름이 "굵게"/"기울임"(en Bold/Italic)인지.
4. 글자색 → 실행 취소("색상"). "프리셋 색상으로" → 실행 취소.
5. 글꼴 변경·"프리셋 글꼴로"·"시스템 기본" → 실행 취소("글꼴"). 크기 → 실행 취소("글자 크기").
6. 캐럿만 두고 정렬(왼/가운데/오른/되돌리기) → 그 문단 정렬 복원("문단 정렬"). 여러 문단 선택 후 정렬 → 한 번에 복원.
7. 줄간격·목록: 여러 문단 선택 후 적용 → 실행 취소 한 번에 모든 문단의 줄간격/목록 기호와 들여쓰기가 복원되는지. 메뉴 체크 표시도 같이 바뀌는지.
8. 캐럿만 있을 때(선택 없음) 굵게·색·글꼴·크기 → 실행 취소 메뉴에 새 항목이 생기지 않는지. 다음 타이핑에는 바뀐 서식이 적용되는지.
9. 문서 끝 빈 줄에서 정렬·줄간격·목록 → 실행 취소 항목이 생기지 않는지.
10. 서식 변경 → 타이핑 → 실행 취소 2회: 타이핑 → 서식 순서로 되돌아가는지(iOS는 합쳐질 수 있음 — 한계 참고).
11. 서식 여러 번(굵게 → 색 → 정렬) → 실행 취소 3회 → 다시 실행 3회: 순서·상태가 정확한지.
12. 실행 취소 후 완료/뒤로 → 다시 열기, 다른 기기 동기화: 되돌린 상태가 저장되는지.
13. macOS 글꼴 패널(⌘T)로 글꼴 변경 → 실행 취소 한 번에 복원되는지(이중 등록 없음).
14. 에디터에서 서식 변경 후 마인드맵으로 이동 → 마인드맵에서 실행 취소: 에디터 서식이 바뀌지 않고 마인드맵 편집만 되돌아가는지(반대 방향도).
15. 말씀구절 + 추가 → 실행 취소: (이번 범위 밖) 기존과 같은지, 앱이 멈추지 않는지.
16. 문단 스타일 변경(sermonstyle2) 실행 취소가 계속 정상인지(회귀).
17. 이미 같은 색·같은 정렬·같은 줄간격을 다시 적용 → 실행 취소 메뉴에 새 항목이 생기지 않는지(iOS·macOS).
18. iOS: 캐럿만 둔 문단에서 정렬(또는 줄간격·목록) → 실행 취소 → 바로 타이핑: 새 글자가 되돌린 정렬·줄간격·목록을 따르는지. 다시 실행 후 타이핑도 확인.
19. iOS: 굵은 글자 선택 → 굵게 해제 → 실행 취소 → 선택을 지우지 않고 타이핑: 굵게로 입력되는지.
20. 문서 전체 선택 후 색·글꼴 변경과 실행 취소의 응답 속도(긴 설교문).
