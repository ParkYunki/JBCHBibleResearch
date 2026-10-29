# 원문 정보 · 원어 카드 아이콘 터치 영역 / 한글 뜻 수정 아이콘 (origcard1, 2026-10-29, 검토 반영 v2)

대상 파일(1개): `JBCHBibleResearch/Views/Bible/OriginalTextInfoView.swift`
diff: `/home/claude/integ/origcard1.diff`
- Mac 현재 파일(md5 `11526cff…`, HEAD와 같음)의 사본에 `git apply --check`가 통과했다.
- 적용 결과가 수정본과 바이트 단위로 같다.

Localizable.xcstrings: 변경 없음(기존 키만 사용)

## 1. 현재 구조
- 성경 탭 → 절 → 원문 정보 시트는 `OriginalTextInfoView`다(`BibleReadingView.swift:1443`에서 생성).
- 하단 원어 카드는 `wordCard(_:)`다.
  - 배치: `LazyVGrid(.adaptive(minimum: 160, maximum: 220), spacing: 12)`
  - 카드 안 여백: 좌우 14, 상하 18
  - 줄 간격: VStack spacing 8
- 1행: 한글 뜻 헤드라인(16pt bold, 최대 2줄)과 수정 버튼이 `HStack(spacing: 6)`에 있다.
  - 수정 버튼은 `pencil.circle` 14pt, 글자색 60%이고 한국어 화면에서만 보인다.
- 2행(`.padding(.top, 2)`): 원어(26pt), 네이버 `Link`, biblehub `Link`가 `HStack(spacing: 5)`에 있다.
  - 네이버 링크는 16×16 "N" 배지, biblehub 링크는 `safari` 13pt다.
- 세 버튼의 히트 영역은 보이는 아이콘 크기(13~16pt)뿐이다. HIG iOS 최소값 28pt보다 작다.
- 세 버튼 모두 `accessibilityLabel`이 없었다. 링크 두 개에만 `.help`가 있었다.

## 2. 변경 내용
| 항목 | Before | After |
|---|---|---|
| 레이아웃 크기 | 아이콘 자연 크기 | 16×16 고정(N 배지와 같은 크기). 줄 높이와 카드 줄바꿈은 사실상 그대로 |
| 히트 영역 | 아이콘 크기 | `contentShape(WordCardHitArea(insets:))`로 아이콘 밖까지만 넓힘(레이아웃 크기는 바뀌지 않음) |
| N ↔ 나침반 간격 | 5 | 8 (+3pt) |
| 원어 ↔ N 간격, 헤드라인 ↔ 연필 간격 | 5 / 6 | 그대로 |
| 수정 아이콘 | `pencil.circle`, 글자색 60% | `pencil` 15pt medium, 포인트색(`linkTint`) |
| 접근성 | 라벨 없음 | `accessibilityLabel`과 `.help`: "한글 뜻풀이 수정", "네이버 사전에서 찾기", "biblehub.com에서 찾기" |
| 플랫폼 분기 | — | 없음. 레이아웃이 바뀌지 않으므로 macOS를 따로 나눌 필요가 없다 |

v1(`frame(minWidth: 44)` + `ViewThatFits`)은 폐기했다. 아이콘 간격이 29pt로 벌어지고, 아이폰 2열 카드 대부분이 링크를 아래 줄로 내렸다.

### 히트 영역 확장량(아이콘 경계 기준 바깥 거리, pt)
| 버튼 | 위 | 아래 | 앞 | 뒤 | 결과 |
|---|---|---|---|---|---|
| 연필 | 14 | 5 | 14 | 14 | 44 × 35 |
| 네이버 N | 5 | 14 | 14 | 4 | 34 × 35 |
| biblehub | 5 | 14 | 4 | 14 | 34 × 35 |

겹침 검토:
- N과 나침반: 맞닿는 쪽을 간격 8의 절반인 4씩만 넓혔다. 경계가 정확히 맞닿고 겹치지 않는다.
- 이웃 카드: 좌우 바깥쪽 확장 14는 카드 안쪽 여백 14와 같다.
  - 줄이 카드 폭을 꽉 채워도 카드 테두리까지만 닿는다.
  - 카드 사이 간격 12는 침범하지 않는다.
- 위아래:
  - 연필 위 14는 카드 위 여백 18 안에 들어간다.
  - 링크 아래 14는 아래 줄(음역·문맥·형태·Strong 번호) 쪽이다. 아래 줄에는 누르는 요소가 없다.
- 연필과 링크: 두 줄 사이 간격은 spacing 8에 padding.top 2를 더한 10이다.
  - 연필 아래 5와 링크 위 5를 더하면 10이다.
  - 두 줄 높이가 아이콘 높이 16까지 줄어드는 최악의 경우에도 겹치지 않는다. 실제로는 헤드라인(약 19pt)과 원어(26pt) 줄이 더 높아 여유가 더 있다.
- 비대화형 글자와 겹침: 연필의 앞쪽은 헤드라인 글자 위로, N의 앞쪽은 원어 글자 위로 14pt 넘어간다.
  - 두 글자는 누르는 동작이 없으므로 충돌은 없다.
  - 대신 원어 마지막 글자 근처를 누르면 네이버가 열릴 수 있다. 이는 의도한 확장이다.

HIG 충족 정도(Accessibility › Buttons and controls: iOS 기본 44×44, 최소 28×28):
- 세 버튼 모두 최소 28은 넘는다.
- 44는 연필의 가로만 채운다.
- 레이아웃을 그대로 두면서 44×44를 채우려면 다음 중 하나가 필요하다. 이번에는 하지 않았다.
  - N과 나침반 간격을 28로 벌린다(검토에서 지적된 문제).
  - 줄 간격을 넓혀 카드를 높인다.

### 근거
- 확장 방식: Apple Developer Forums thread 831676에 같은 질문이 있다(44×44 탭 영역, 레이아웃은 유지). Apple 엔지니어가 `.contentShape(Circle().inset(by: -8))`를 답으로 제시했다.
- 히트 테스트가 레이아웃 경계를 따르지 않는다는 점은 Ole Begemann "clipped() doesn't affect hit testing"(2022)이 보여 준다.
  - 그 글에서는 100×100 frame 밖의 내용이 탭을 받는다.
  - 히트 영역은 `contentShape`가 정한다.
- Apple 공식 문서에 "경계 밖 contentShape도 hit test된다"는 명시는 없다. 근거는 Apple 엔지니어 답변과 알려진 동작이다. 그래서 4절의 실기기 확인을 필수로 둔다.
- 변별 확장: `Rectangle().inset(by:)`는 네 변을 똑같이만 넓힌다. 그래서 `EdgeInsets`를 받는 private `Shape`(`WordCardHitArea`)를 추가했다.
  - 프로젝트에는 이미 같은 형태의 private `Shape`(`NoteConnectorArrow`, `ChapterBookmarkRibbonShape`)가 있다.
  - 이들은 같은 빌드 설정(Swift 5, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`)으로 컴파일되고 있다.
- 비교한 대안: `padding(+n)`에 `contentShape`를 쓰고 다시 `padding(-n)`으로 되돌리는 방법.
  - 위 포럼 질문자가 쓰던 우회책이고, 효과는 같다.
  - 다만 음수 padding이 레이아웃 계산에 끼어들어 의도가 덜 드러난다. Apple 엔지니어가 권한 `contentShape` 방식을 택했다.
- `pencil`은 SF Symbols 1.0부터 있다(iOS 13+, macOS 11+). 앱의 `VerseZoomView`도 "편집"에 `pencil`을 쓴다.
  - `square.and.pencil`은 "새로 쓰기" 의미가 강하다.
  - 텍스트 라벨("수정")은 헤드라인 폭을 줄여 한글 뜻이 더 일찍 잘리므로 넣지 않았다.

### B-1 헤드라인 치우침
- 원래 코드: `pencil.circle` 약 17pt에 간격 6이 붙어, 헤드라인이 가운데에서 약 11.5pt 왼쪽에 있었다.
- 변경 후: 아이콘 16에 간격 6이라 약 11pt다. 원래와 같은 수준이고 이번 수정이 키우지 않았다.
- 반대편에 같은 폭(22pt)의 투명 자리를 두면 가운데는 맞는다. 하지만 아이폰 2열 카드에서 헤드라인 폭이 약 114pt에서 92pt로 줄어 2줄 제한에서 더 잘린다.
- `lineLimit`이 사용자 답을 기다리는 중이므로 이번에는 손대지 않았다. lineLimit 결정과 함께 정하는 것을 권한다.

## 3. 엣지 케이스
- 좁은 아이폰(375pt, 2열, 카드 내용 폭 약 137pt):
  - 2행 폭이 원래보다 약 3~4pt만 늘었다(간격 +3, safari 자연 폭에서 16pt 고정).
  - 원어 줄바꿈과 카드 높이는 사실상 원래와 같다.
  - 헤드라인 폭도 원래와 같다.
- 다이나믹 타입: 카드 글꼴은 모두 `.system(size:)` 고정 크기다. 큰 글자 설정에도 바뀌지 않으므로 기존과 같다. 히트 영역도 고정값이다.
- 다크 모드·테마: 연필 색은 safari와 같은 `Color.accentColor`다. N 배지는 바꾸지 않았다.
- 비한국어 화면: 연필은 원래대로 숨는다. 링크만 해당한다.
- RTL: 지원 언어 17개에 RTL 언어가 없다. `WordCardHitArea`는 leading을 minX(왼쪽)로 계산하므로 RTL을 추가하면 다시 봐야 한다.
- macOS: 레이아웃이 그대로라 분기하지 않았다. 포인터 클릭 영역과 툴팁이 뜨는 영역이 아이콘보다 조금 넓어진다.
- Strong 코드가 H나 G가 아니면 링크가 없다. 안쪽 HStack이 비고, 바깥 간격 5만 남는다(기존과 같다).

## 4. 실기기 확인 방법(필수)
1. 아이폰(SE·mini급이면 좋음)에서 성경 탭 → 절 → 원문 정보 → 하단 원어 카드를 연다.
   - N 왼쪽 원어 쪽 약 10pt, N 아래 약 10pt를 눌러 네이버가 열리는지 확인한다.
   - 나침반 오른쪽 약 10pt를 눌러 biblehub가 열리는지 확인한다.
   - 두 아이콘 사이 정중앙을 기준으로 좌우가 각각 맞는 링크를 여는지 확인한다.
   - 연필 위·좌·우 약 10pt를 눌러 "한글 뜻풀이 수정" 알림창이 뜨는지 확인한다.
2. 디버그로 확인하려면 각 `contentShape` 뒤에 임시로 `.background(WordCardHitArea(insets: …).fill(.red.opacity(0.2)))`를 붙인다. 겹침과 카드 경계를 눈으로 본 뒤 제거한다.
3. 원래 빌드와 나란히 놓고 카드 높이와 원어 줄바꿈이 같은지 확인한다.
4. VoiceOver로 세 버튼이 "한글 뜻풀이 수정 버튼", "네이버 사전에서 찾기 링크", "biblehub.com에서 찾기 링크"로 읽히는지 확인한다.
5. 라이트·다크와 배경색 지정 테마에서 연필 대비를 확인한다.
6. 맥: 클릭 영역과 툴팁 3종을 확인한다.
7. Accessibility Inspector의 Audit에서 결과를 확인한다. 히트 영역이 44 미만이라 "Hit area is too small" 경고가 남을 수 있다. 이 경우 2절의 대안을 결정해야 한다.

## 5. 다른 작업과의 충돌
- 수정 파일은 `OriginalTextInfoView.swift` 하나다. Mac 작업 트리에서 HEAD 대비 변경이 없다.
- `BibleReadingView`, `BibleTopBar`, `BibleReadingTarget`, 공유 부품(`VerseSheetChrome`, `BibleBarControls`)은 건드리지 않았다.
- 생성자 시그니처를 바꾸지 않았으므로 `BibleReadingView.swift:1443` 호출부는 영향이 없다.
- `/home/claude/integ`의 다른 diff 가운데 이 파일을 포함한 것은 없다.
