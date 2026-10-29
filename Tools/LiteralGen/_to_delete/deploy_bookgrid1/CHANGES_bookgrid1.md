# bookgrid1 (2026-10-29)

기준: Mac 현재 파일(booklabel1·booklabel2 반영본). `bookgrid1.diff`는 저장소 루트에서 `git apply` (경로 `JBCHBibleResearch/...`).
수정본: `/home/claude/integ/bookgrid1/JBCHBibleResearch/...`

## 1. 책 그리드 검색이 앱 언어 이름을 찾게 함
- 증상: 앱 언어 중국어에서 책 선택 그리드 검색창에 "创"·"创世"·"约翰"을 치면 아무 책도 안 나옴.
- 원인: `BookGridPicker.matches(_:)`가 `Book.matches(query:)`(nameKo·한국어 약칭·초성)만 썼음.
  `BooksProvider.search(query:)`에는 이미 앱 언어 비교가 있었지만 어디서도 호출되지 않았음(그리드는 넘겨받은 `books`를 직접 거름).
- 수정
  - `Services/Book+Search.swift`: `Book.matchesGridSearch(query:)` 신설. `matches(query:)`를 먼저 보고, 한국어가 아닌 앱이면
    `displayName`/`displayShortName`을 `localizedCaseInsensitiveContains`로 비교. `matches(query:)`는 손대지 않음.
  - `Views/Bible/BookChapterPicker.swift`: `BookGridPicker.matches(_:)`가 `matchesGridSearch`를 씀.
  - `Services/BooksProvider.swift`: 호출처 없는 `search(query:)`도 같은 함수를 쓰게 함(동작 같음, 중복만 없앰).
- 한국어 앱: `matches(query:)` 결과 그대로(한국어에서는 추가 비교를 아예 하지 않음. `abbreviation.contains`는 원소 일치라
  `displayShortName` 부분 일치를 더하면 결과가 넓어지기 때문).
- Python 모의 실행: zh-Hans "创"/"创世" → 创世纪, "约翰" → 约翰福音·壹·贰·参书, zh-Hant "約翰" → 4권, en "gen" → Genesis,
  ja "ヨハネ" → 5권, ru "Иоанна" → 4권, ko "ㅇㅎ"/"요한" → 이전과 같음.

## 2. 입력칸 placeholder 예시를 각 언어 책 이름으로
- `Localizable.xcstrings`의 세 키 × 17개 언어 = 51개 `value` 줄(+ 3-1의 comment 1줄)만 바뀜(state `needs_review` 그대로, 서식·키 순서·파일 끝 개행 없음 유지).
- "예:창세기1, 요3, 요3:16"(표준·캡슐 입력칸)과 "예: 창세기1, 요3:16"(상단 막대)은 같은 값, "예: 요3:16"(좁은 칸)은 한 예시만.

| 언어 | 두 키(긴 예시) | "예: 요3:16" |
|---|---|---|
| de | z. B. Gen 1, Joh 3:16 | z. B. Joh 3:16 |
| en, en-CA | e.g. Gen 1, John 3:16 | e.g. John 3:16 |
| es, es-MX | p. ej. Gén 1, Jn 3:16 | p. ej. Jn 3:16 |
| fil | hal. Juan 3:16 | hal. Juan 3:16 |
| fr, fr-CA | ex. Gn 1, Jn 3:16 | ex. Jn 3:16 |
| id (영어 이름표) | mis. Gen 1, John 3:16 | mis. John 3:16 |
| it | es. Gen 1, Gv 3:16 | es. Gv 3:16 |
| ja | 例: 創1, ヨハ3:16 | 例: ヨハ3:16 |
| pt-BR | ex.: Gn 1, Jo 3:16 | ex.: Jo 3:16 |
| ru | напр. Быт 1, Ин 3:16 | напр. Ин 3:16 |
| th | เช่น ยอห์น 3:16 | เช่น ยอห์น 3:16 |
| vi | Ví dụ: Giăng 3:16 | VD: Giăng 3:16 |
| zh-Hans | 例：创1, 约3:16 | 例：约3:16 |
| zh-Hant | 例：創1, 約3:16 | 例：約3:16 |

- 모든 예시는 `BookNameTable` 실제 값. booklabel1 규칙(`matchBookPrefix` + `submitFreeText` 장·절 파싱)을 Python으로 모의 실행해
  51개 값의 예시 전부가 창세기 1장 / 요한복음 3:16으로 가는 것을 확인(실패 0).
- 폭: th/vi/fil은 전체 이름이라 한 예시만 넣음. th는 접두어를 "ตัวอย่าง:" → "เช่น"(=예), vi 좁은 칸은 "Ví dụ:" → "VD:"로 줄임.
  Inter/Noto/Loma 글꼴 추정 폭: 긴 예시는 15pt 104~149pt(상단 막대 글자 영역 약 152pt 이하), 좁은 칸은 15pt 74~119pt.
  th·vi 좁은 칸(약 119·104pt)은 좁은 칸 글자 영역(약 112pt)에 걸칠 수 있음 → 실기기 확인 항목.
  표준 입력칸(iOS 17pt, 글자 영역 약 133pt)은 기존 한국어(약 168pt)부터 이미 넘쳤고, 새 값은 대부분 그보다 짧음(최장 id 169pt).

## 3. iPad 책/장 팝오버 머리가 잘려 책 목록으로 못 돌아감
- 증상(iPad, 중국어): 상단바 제목 "创世纪 1章" → 팝오버가 오른쪽에 뜨고(화살표 왼쪽), 맨 위에 선 하나만 보이고 [‹ 책 목록] 머리가 없음.
- 원인(소스 근거): 장 그리드에 `.frame(minHeight: estimatedGridHeight)`(창세기 66+1+560 = 627pt), 바깥에 `.frame(minHeight: 460)`.
  SwiftUI `frame(min…)`은 부모가 준 높이가 최소값보다 작아도 뷰를 최소값으로 키움 → 팝오버가 627pt보다 작게 잡히면 내용이 가운데 정렬로
  위아래로 넘쳐 머리(66pt, 아래 1pt 선)부터 잘림. 증상의 "선 하나"가 머리 아래 선(`PickerHeaderBar` overlay)과 맞음.
  팝오버가 옆에 뜬 것은 요청 높이가 버튼 아래 공간에 안 들어가 시스템이 다른 방향을 고른 결과로 봄.
- 중국어 전용인가: 아님. `estimatedGridHeight`, 460, 팝오버 코드에는 언어 분기가 없음(장 수와 기기 종류만 봄). 같은 창 크기·방향·배치
  (가로 모드, 창이 작은 Stage Manager/Split View, 화상 키보드 등)에서는 한국어도 같음. 창세기·시편처럼 장이 많은 책일수록 잘 생김.
  언어가 영향을 줄 수 있는 것은 상단바 `ViewThatFits` 배치 선택(글자 폭)뿐인데, 제목 버튼은 두 줄 배치의 윗줄에 있어 아래 공간 차이가 작음.
  스크린샷의 기기·방향·키보드 여부를 모르므로 이 이상은 단정하지 않음.
- `initialBook`(장 그리드부터 시작)은 의도된 동작이며, 책 목록 복귀는 머리의 [‹ 책 목록]이 맡으므로 머리가 보이면 해결됨.
- 수정(`BookChapterPicker.swift`) — 검토 A1/B1 반영판
  - 이전 iPad 유효 요청 높이(제안 nil): 책 목록 = max(자식 이상 높이, 460), 장 그리드 = max(자식 이상 높이, 추정치(560 상한 적용값), 460).
    `frame(minHeight: M)`은 nil 제안에서 max(자식 이상 높이, M)을 내고, `frame(idealHeight: X)`는 자식과 관계없이 X를 낸다.
    따라서 첫 수정안(`idealHeight`)은 공간이 넉넉할 때 팝오버가 이전보다 작아질 수 있었다(B1). 그 주석 근거("둘이 같은 값")는 틀렸다(A1).
  - 새 `IdealHeightFloorLayout`(SwiftUI `Layout`, 자식 1개): 제안 높이가 nil일 때만 max(자식 높이, 하한)을 보고하고, 구체적 높이에는 자식 크기를
    그대로 보고·제안한다. 결과: 요청 높이는 위 이전 유효값과 같고, 받은 높이가 작으면 키우지 않아 머리는 남고 `ScrollView`만 줄어든다.
  - 하한: 책 목록 460, 장 그리드 max(추정치, 460). 추정치는 기존(560 상한 포함) 값 그대로 썼다 — 이전 최소값이 바로 그 값이고, 자식 이상 높이는
    레이아웃이 직접 재므로 상한을 뺀 계산값으로 바꿀 필요가 없다(바꾸면 이전보다 커질 수 있음). 장이 적은 책은 하한 460 아래로 내려가지 않는다.
  - 책 목록의 높이 프레임은 빼지 않았다: "ScrollView 이상 높이 = 내용 전체 높이"를 공식 문서로 확인하지 못했고(기존 `estimatedGridHeight` 주석은
    460으로 부족했다고 적고 있어 반대 정황도 있음), 하한 460을 두면 어느 쪽이든 이전 값과 같다.
  - 높이는 안쪽(`PickerContentHeight`)에서만 정한다. 바깥 `PickerPopoverSizing` iPad 분기는 `frame(minWidth: 360)`만 둔다(이중 계산 없음).
  - 맥·아이폰: 이전 그대로(맥: 바깥 360×460 최소 + 장 그리드 `minHeight: 추정치`, 아이폰: 장 그리드 `minHeight: 0`, 책 목록 지정 없음).
  - 근거: SwiftUI `frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)` 문서의 크기 규칙(최소값은 제안보다 작아지지 않음),
    `Layout.sizeThatFits`/`placeSubviews`(iOS 16+) 문서.
  - 쓰지 않은 것: `presentationCompactAdaptation`은 compact 크기 클래스(아이폰·좁은 창)에서의 변환만 정해서 이 증상(regular 폭 팝오버)과 관계없고
    아이폰 시트 동작을 바꿈. `arrowEdge`는 iOS에서 어느 방향을 지키는지 문서로 확인하지 못해 쓰지 않음. 가용 높이 측정은 팝오버를 띄우기 전에
    공식 API로 알 수 없어 쓰지 않음.
  - 요청 높이가 이전과 같으므로 팝오버가 옆에 뜨는 배치 자체는 그대로일 수 있다(머리는 보임).

## 3-1. xcstrings comment
- "예: 요3:16" 키의 comment에서 "예시 참조(요3:16)는 기존 키처럼 그대로 둔다"를 실제 번역 규칙(그 언어 이름표 약칭, 없으면 전체 이름 + 3:16)으로 고침.

## 4. 그 밖의 경로 점검 (수정 없음)
- 그리드 탭 → `pendingBook` → `ChapterGrid` → `onSelect`, 상단바 제목 팝오버(`BookChapterGridPopover`), 아이폰 시트(같은 팝오버의 시트 변환),
  이전/다음 장(`BooksProvider.book(after:/before:)`), 북마크·이력(`booksProvider.book(id:)`), 뒤로/앞으로 스택: 모두 `bookId`/`Book`(Hashable) 기준.
  앱 언어에 따라 바뀌는 값(`displayName`, `displayShortName`, `displayShortReference`)을 키로 비교하는 곳은 찾지 못함
  (`nameKo ==` 비교 2곳은 고정 데이터 비교라 언어와 무관).
- 그리드 검색은 앞뒤 공백을 자르지 않음(한국어도 원래 그럼). "创 "처럼 공백이 끝에 붙으면 안 나옴.

## 실기기 확인 항목
1. 중국어 그리드 검색 "创", "创世", "约翰"; 한국어 "ㅇㅎㅂㅇ", "요한", "창"이 이전과 같음.
2. iPad 가로/세로, 키보드 표시 상태에서 창세기·시편 팝오버: 머리와 [‹ 책 목록]이 보이고 장 그리드만 스크롤. 공간이 넉넉할 때 높이가 이전과 같음
   (유다서처럼 장이 적은 책도 460 이상).
3. 책 목록 단계 팝오버 높이(iPad)가 이전(460 이상)과 같음.
4. 맥 팝오버, 아이폰 시트: 변화 없음.
5. 각 언어 placeholder가 잘리지 않음(특히 th·vi 좁은 칸, id/en 표준 칸).

## 사용자 결정 (2026-10-29)
- 비한국어 앱에서도 책 이름 입력·그리드 검색은 앱 언어 이름표 + 한국어(이름·약칭·초성)를 함께 인식한다(현행 유지). 영어 등 다른 언어는 인식하지 않는다.
