# versewrap1 — 확대보기(메모하기) 다국어 줄바꿈 + 메모하기 흐름 점검 (2026-10-29)

수정 파일 (`/home/claude/integ/versewrap1/` 아래, diff: `/home/claude/integ/versewrap1.diff`, Mac 현재 파일에 `git apply --check` 통과)
- `JBCHBibleResearch/Views/Bible/VerseAnnotationRenderer.swift`
- `JBCHBibleResearch/Views/Bible/VerseZoomView.swift` (변경 구간 132~310행. 1060~1080행은 건드리지 않음)

새 문구 없음. Localizable.xcstrings는 바꾸지 않았다.

## 1. 원인 (소스와 번들 DB 전수 조사로 확인)

`lineRanges`의 판정이 "라틴 문자·숫자가 없으면 한국어 경로"였다. 그래서 번들 번역본은 이렇게 갈렸다.

| 번역본 | 경로(수정 전) | 결과 |
|---|---|---|
| CUV1919/CUV1919S (중국어) | 한국어 경로 | 띄어쓰기가 없어 줄이 안 나뉜다(25자 넘는 절 21,153개). 한 줄짜리 `HStack`이 화면 전체 폭으로 저절로 줄바꿈되어 여백이 없다. 형광펜 등으로 조각이 여러 개면 조각끼리 폭을 나눠 가진다 |
| JPBUNGO (일본어) | 한국어 경로 | 위와 같다(20,496개) |
| THKJV (태국어) | 한국어 경로 | 띄어쓰기 대신 U+200B를 쓴다. UTF-16 글자 수(결합 모음 포함)로 끊겨 폭이 들쭉날쭉하다 |
| SYN (러시아어) | 한국어 경로 | 키릴 문자를 글자 수로 끊는다. 숫자가 있는 27절만 실측 경로로 간다 |
| 라틴 문자 번역본 | 실측 경로 | 폭이 `effectiveTextWidth` = "가" 23자 폭이다. 한글 줄(18/20자 목표)보다 약 30% 넓어 오른쪽 여백이 거의 없다 |

## 2. 한글 줄이 차지하는 폭 (실측)

기준: 기본 글꼴 Paperlogy-4Regular, hmtx로 잼. "가" = 0.88em이고, 19pt 고정이면 16.72pt다.
KRV 31,102절 전체를 `koreanLineRanges`와 같은 알고리즘으로 나눴다(마지막 줄 제외).
- 목표 18자(아이폰 세로): 줄 폭 중앙값 "가" 16.0자, p90 18.0자, 최대 23.25자
- 목표 20자(그 밖): 중앙값 17.5자, p90 19.25자, 최대 24.25자

화면별 계산. C = 스크롤 폭 − 52 = `availableContentWidth`이고, 텍스트 앞에 왼쪽 패딩 16pt가 있다.
- iPhone 393pt 세로: C = 341. 한글 중앙값 267pt로 C의 78%이고, 화면 오른쪽 여백은 약 28%다. 라틴(수정 전)은 341pt로 C를 꽉 채운다.
- iPhone Pro Max 440pt 세로: 한글 267pt로 C의 69%, 여백 약 36%다. 라틴(수정 전)은 385pt로 99%를 쓴다.
- Mac 최소 창 525pt: C = 473. 한글 293pt로 62%이고 오른쪽 여백이 약 1/3이다. 라틴(수정 전)은 385pt로 81%다.
- iPhone 가로·iPad: C가 "가" 23자 폭(385pt)보다 넓다. 그래서 라틴(수정 전)은 385pt 고정이고, 한글(약 293pt)의 1.31배다.

시트 실제 폭(특히 iPad page sheet와 iPhone 가로의 safe area)은 정적 분석으로 정확히 알 수 없다. 위 수치는 위에 적은 스크롤 폭을 가정한 것이다.

## 3. 결정과 근거

- 판정: `usesKoreanLineBreaking(text) = containsHangul && !containsLatinOrDigit`로 바꿨다. 이 조건에 해당하지 않는 절(CJK, 태국어, 키릴, 베트남어, 사용자 추가 번역본의 임의 언어)은 모두 TextKit 실측(`measuredLineRanges`)으로 보낸다. TextKit 1이 CJK 금칙 처리, 태국어 사전 기반 줄바꿈, U+200B 줄바꿈 기회를 처리한다.
- 폭: 실측 경로는 `lineBreakWidth = min(C, "가" 폭 × targetCharsPerLine)`이다. 한글과 같은 글자 수 예산을 한글 글자 폭 단위로 바꾼 값이다. "컨테이너의 2/3"는 쓰지 않았다. iPhone 세로에서는 2/3가 13.6자로 한글보다 좁고, 가로에서는 23자 상한을 넘어 한글과 맞지 않는다.
  - 시뮬레이션(Paperlogy 폭, 그리디 줄바꿈)
    - BSB 18/20자: 중앙값 16.7/18.7자, p90 17.9/19.9자
    - CUV 18/20자: 중앙값 17.7/19.7자
    - 한글 중앙값 16.0/17.5자, p90 18.0/19.25자와 비슷하다.
  - SYN은 Paperlogy에 키릴 문자가 없어 대체 글꼴로 그려지므로 시뮬레이션 수치를 믿을 수 없다. 실기기에서 확인해야 한다.
- 한글 경로의 폭은 지금 그대로 `effectiveTextWidth`(23자)다. 한글은 글자 수로 줄이 나뉘므로 이 폭은 선택 모드 텍스트뷰 폭에만 쓰인다. 폭을 줄이면 긴 줄(최대 24자)이 선택 모드에서 저절로 줄바꿈되어 회귀가 생긴다.

## 4. KRV 회귀 없음 (근거)

- BibleDB.sqlite(KRV) 31,102절 모두 한글이 있다(전수 확인). 따라서 판정 결과가 수정 전과 같다.
  - 31,088절은 한국어 경로, 폭 23자 그대로다.
  - 라틴/숫자가 있는 14절은 수정 전에도 실측 경로였다. "(18절에 포함됨)" 같은 짧은 문구라 한 줄이고, 폭만 23자에서 18/20자로 바뀐다. 보이는 차이는 없다.
- 시편 표제 `[다윗이 … 지은 시] …`는 한글이고 라틴 문자가 없어 한국어 경로다. 변화 없다.
- 한자 표시(굵게)는 KRV 전용이다. `hanjaWords`가 번들 코드에서만 값을 돌려주므로(`BibleReadingViewModel.hanjaWords`) 실측 경로와 섞이지 않는다.

## 5. 선택 모드와 표시 모드의 일치, 오프셋

- 실측 경로의 줄 범위는 빈틈없이 이어진다. 라틴은 줄 끝 공백이 앞 줄에 들어가고, CJK는 공백 없이 끊긴다. 그래서 `forcedBreakText`는 아무것도 치환하지 않는다(`nextStart > currentEnd`인 경우가 없다). 선택 모드 텍스트가 원문과 같으므로 `selectedRange`가 그대로 `verse.content` 오프셋이다.
- 선택 모드 `UITextView`/`NSTextView`는 다음 조건이 측정과 같다.
  - `.frame(width: lineBreakWidth)`, `widthTracksTextView`, `lineFragmentPadding = 0`, inset 0
  - 엔진이 같은 TextKit 1(`TightBackgroundLayoutManager`)
  - 선택 모드에만 붙는 속성은 줄 간격, 색, 배경, 밑줄이다. 줄 간격은 줄바꿈 위치에 영향이 없다. 나머지(색·배경·밑줄)도 글리프 폭을 바꾸지 않는다. 폭을 바꾸는 한자 굵게는 KRV 전용이다.
- CJK에서는 이제 U+2028이 끼지 않는다. 그래서 `TightBackgroundLayoutManager` 주석에 적힌 한글 깜박임 원인과도 관계가 없다.

## 6. 엣지 케이스

- 형광펜·메모가 줄 경계에 걸칠 때: `buildLines`가 줄 단위로 잘라 조각을 나눈다. 메모 박스는 시작 줄에만 붙고, 화살표는 첫 조각을 가리킨다(기존 로직 그대로). 실측 경로에는 줄 사이에서 빠지는 글자가 없어, 형광펜이 끊겨 보이는 곳이 없다.
- 매우 긴 단어(폭보다 넓은 단어): TextKit이 글자 단위로 나누고, 선택 모드도 같은 엔진이라 결과가 같다.
- 회전·폭 변경: `onGeometryChange`가 `scrollWidth`/`scrollHeight`를 갱신하면 `targetCharsPerLine`(18↔20)과 `lineBreakWidth`가 함께 다시 계산된다. 오프셋은 원문 기준이라 줄바꿈과 관계없다.
- 폰트 크기·다이나믹 타입: 확대보기 본문은 19pt 고정이라 영향이 없다. 폰트 종류가 바뀌면 "가" 폭을 다시 잰다. 한글이 없는 글꼴(Inter, Gentium 등)에서는 시스템 대체 글꼴의 "가" 폭이 단위가 된다. 한글 경로의 23자 폭도 같은 방식이라 일관된다.
- 첫 프레임(`scrollWidth` 기본값 320): `min(C, …)`로 제한된다. `measuredLineRanges`는 폭이 0 이하이면 한 줄로 처리한다. NaN이면 `effectiveTextWidth`로 물러난다.
- TGLULB의 "-" 8절, KRV 이외의 빈 절: 한 줄이라 경로가 바뀌어도 결과가 같다.
- 성능: 절 하나(약 200자)를 O(n)으로 한 번 더 훑을 뿐이다.

## 7. "메모하기" 흐름 점검 결과

메모하기를 누르면 `openVerseZoom()`이 호출되어 `VerseZoomView`가 열린다. 안의 메모 도구는 `PhraseNoteEditorPopover`, 개인 묵상 입력칸은 VerseZoomView 안의 `composingPersonalNoteCard`다.
- 문구: VerseZoomView, PhraseNoteEditorPopover, AnnotatedVerseFlowView, VerseSheetChrome와 하단 메뉴의 한국어 리터럴을 모두 대조했다. xcstrings에 키가 있고 점검한 14개 언어(en, ja, zh-Hans, zh-Hant, ru, th, vi, es, de, fr, it, pt-BR, id, fil)가 모두 채워져 있다.
  - 제목 `%@장 %lld절`의 en 값은 `%@:%lld`다. 책 이름은 번역본의 `bookNameTableID`를 따른다.
- 남은 문제: 관주 칩 라벨이 `BooksProvider.shared.book(id:)?.abbreviation.first`(VerseZoomView 약 1070행)라 다른 언어에서도 한국어 약칭이 나온다. 이 부분은 다른 작업(segment label)이 맡고 있어 손대지 않았다. 겹치는 곳은 이 한 곳이다.
- 띄어쓰기를 전제로 한 로직: 메모 범위는 어절 단위로 맞추지 않는다. `trimmedRange`는 앞뒤 공백만 뺀다. 그래서 CJK에서 망가질 곳이 없다.
  - 사소한 점: U+200B는 `whitespacesAndNewlines`에 들어 있지 않다. 태국어에서 선택 범위 앞뒤의 U+200B가 앵커에 남을 수 있다. 오프셋과 `anchorText` 검색이 함께 들어 있어 동작에는 지장이 없다. 고치지 않았다.
- 한자 기능: `hanjaWords`가 KRV 외에는 `[]`를 돌려준다. 그래서 "한자 뜻풀이" 섹션이 그려지지 않을 뿐, 빈 화면이나 오류는 생기지 않는다.
- 글자 수 카운터: 메모(199)와 개인 묵상(2000) 모두 `String.count`(그래핌)로 세고 `prefix`로 자른다. 태국어 결합 문자, CJK, 이모지에서도 카운터와 자르기가 일관된다.

## 8. 확인할 테스트

1. KRV(아이폰 세로·가로, iPad, Mac): 줄 위치가 수정 전과 같은지. 시편 3:1(표제), 신 6:19 "(18절에 포함됨)".
2. CUV·JPBUNGO 요 3:16: 줄이 "가" 18/20자 폭에서 나뉘는지, 행두에 `、。」`이 오지 않는지(금칙). 형광펜이 걸린 절에서 조각이 세로로 쌓이지 않는지.
3. THKJV 요 3:16: 단어 중간에서 끊기지 않는지.
4. SYN 시 3:1: 폭이 고른지(키릴 대체 글꼴).
5. BSB, VIE: 줄이 수정 전보다 짧아지고 오른쪽 여백이 생기는지.
6. 각 언어에서 편집(선택 모드)으로 바꿨을 때 줄 경계가 표시 모드와 같은지. 줄 경계에 걸치게 드래그해 형광펜과 메모를 저장한 뒤, 표시 모드에서 같은 글자에 붙는지. 특히 CJK에서.
7. 회전하면서 18/20자를 오가는 동안 선택 모드와 표시 모드가 계속 일치하는지.

## 9. 범위 밖 (보고만 함)

- 히브리어·아랍어 같은 RTL 사용자 번역본: 표시 모드가 줄마다 `HStack`에 조각을 왼쪽부터 놓는다. 그래서 조각이 여러 개인 RTL 줄은 순서가 뒤집힌다. 수정 전 한국어 경로에서도 같았다(회귀 아님).

## 10. 검토 반영 (B1, C2)

- B1: `VerseZoomView`에 `@Environment(\.displayScale)`를 추가했다. 실측 경로의 `lineBreakWidth`는 이제 `floor(w * scale) / scale`로 내림한 값이다. 표시 모드와 선택 모드(`containerWidth`, `.frame(width:)`)는 계속 같은 `lineBreakWidth`를 받는다. scale이 0 이하이거나 유한하지 않으면 내림하지 않는다. 한국어 경로(`effectiveTextWidth`)는 그대로다.
- C2: 주석만 고쳤다. 대상은 `SelectableVerseTextView.swift` 108–109행, `AnnotatedVerseFlowView.swift` 78–80행(79–80행 앞의 78행까지 같은 문단이라 함께 고쳤다), `VerseZoomView.swift`의 `targetCharsPerLine` 주석이다.
- diff에 `SelectableVerseTextView.swift`와 `AnnotatedVerseFlowView.swift`가 추가되어 이제 4개 파일이다. `VerseZoomView` 1060–1080행은 그대로이고, `git apply --check`는 통과했다.
