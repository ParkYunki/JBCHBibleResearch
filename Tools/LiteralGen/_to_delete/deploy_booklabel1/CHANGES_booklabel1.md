# booklabel1 (2026-10-29) — 성경 탭 책·장 입력칸의 언어별 표시와 입력 해석

## 기준
- Mac 원본(`$HOME/mnt/JBCHBibleResearch`, git 4c7ed7e, 대상 파일 변경 없음)과 md5 일치 확인 후 작업.
  - AppLanguage 7f7e1a62 / BooksProvider 1a8fd001 / BookChapterPicker 73f48960 / VerseZoomView a7c034df / BulkCrossReferenceParser 235be578
  - /home/claude/integ 아래 다른 작업본의 최신본(topbar2, versedoc1, merge10)도 같은 md5여서 겹치는 작업 없음.
- 수정본: `/home/claude/integ/booklabel1/JBCHBibleResearch/...`, 원본 사본: `booklabel1_base/`
- diff: `/home/claude/integ/booklabel1.diff` (md5 5d7e3f1d…). Mac 저장소에서 `git apply --check` 통과(5개 파일).
- Localizable.xcstrings: 새 문구 없음 → 변경 없음.
- Swift 툴체인이 없어 빌드는 못 했다. 매칭 로직은 같은 규칙의 Python 모의 실행으로 검증했다(아래).

## 변경 파일
1. `Services/AppLanguage.swift`
   - `bookNameTable`: `fileprivate` → internal(`BooksProvider`가 씀).
   - `AppLanguage.bookChapterSeparator` 추가: ko/ja/zh는 "", 그 밖의 언어는 " ".
   - `Book.displayShortReference(chapter:)` 추가: `displayShortName + 구분 문자 + 장`. 한국어 결과는 기존 `abbreviation.first ?? nameKo` + 장과 같다.
   - 13행 주석 수정("자유 입력 파싱은 한국어 전용" 삭제).
2. `Services/BooksProvider.swift`
   - `matchBookPrefix`: 한국어 후보 다음, 초성 단계 전에 앱 언어 이름표 후보(fullNames/shortNames)를 추가했다. 가장 긴 일치를 쓰는 규칙(`>` 비교, 입력에서 소비한 글자 수 기준)은 그대로다. 한국어 앱은 이름표가 nil이라 코드 경로가 이전과 같다.
   - `localizedPrefixLength(of:in:)` 신설: 대소문자 무시, 후보·입력 양쪽 공백 무시, 끝 마침표 하나 소비, 일치 직후가 글자면 거절(단어 경계).
   - 54행 주석 수정.
3. `Views/Bible/BookChapterPicker.swift` (compact 모드만)
   - `syncFreeTextToCurrentPositionIfNeeded`, `submitFreeText`: `displayShortReference` 사용.
   - 고정 라벨 `Text("장")`은 한국어 앱에서만 보인다.
   - 칸 상한: 한국어 90(그대로), 그 밖의 언어 104.
4. `Views/Bible/VerseZoomView.swift`: 관주 칩 라벨에 `displayShortReference` 사용(표시 전용).
5. `Services/Bible/BulkCrossReferenceParser.swift`: 헤더 주석만 수정.

## 언어별 표시 예(포커스 없을 때)
| 언어 | 이전 | 이후 |
|---|---|---|
| ko | 창1 장 | 창1 장 (그대로) |
| en / id | 창1 Ch. / 창1 Psl. | Gen 1, 1Sam 3, 1Chr 12, Ps 119 |
| es | 창1 Cap. | Gén 1, 1 Sam 3 |
| de | 창1 Kap. | Gen 1, 1 Kön 3 |
| it | 창1 Cap. | Gen 1, 1 Re 3 |
| ja | 창1 章 | 創1, Ⅰサム3 |
| zh-Hans / zh-Hant | 창1 章 | 创世纪1 / 創世紀1 (약칭 데이터 없음 → 전체 이름) |
| ru | 창1 Гл. | Бытие 1, Псалтирь 118 (전체 이름) |
| th | 창1 บท | ปฐมกาล 50 (전체 이름) |
| fr / pt / vi / fil | 창1 Chap. 등 | Genèse 1 / Gênesis 1 / Sáng Thế Ký 1 / Genesis 1 (전체 이름) |

판단 근거:
- 공백: 띄어쓰기를 하는 문자(라틴·키릴·태국·베트남)는 "Gen 1"처럼 띄우는 것이 일반적인 참조 표기다. 이름표 약칭에 이미 공백이 든 언어(es/de/it "1 Sam")는 붙이면 "1 Sam3"처럼 들쭉날쭉해진다. CJK는 "創1", "约3:16"처럼 붙여 쓴다. 한국어는 그대로 둔다.
- "장" 라벨은 한국어에서만 보인다. 이유는 둘이다.
  - 번역 라벨("Ch.", "Cap.", "Kap.", "Гл.", "Psl.")은 원래 숫자 앞에 오는 말이라 "Gen 1 Ch."는 어순이 어색하다.
  - 폭이 모자란다. Inter·Noto CJK·Loma 20pt(= iOS `.title3`)로 재면 칸 104에 라벨까지 넣을 경우 영어 66권 중 43권, 스페인어 52권이 잘린다. 라벨을 빼면 en/id/es/de/it/ja는 0권이다.
  - 같은 측정에서 한국어 최대 "삼상18"류는 62pt이고 가용 폭은 64pt다. 기존 주석의 "90에서 안 잘림"과 맞아, 이 대체 글꼴이 SF와 크게 어긋나지 않는다고 봤다.
  - ja/zh의 "章"은 어순은 자연스럽지만 20pt를 더 쓴다. ja는 라벨이 있으면 104에서 4권, 90에서 24권이 잘린다. 그래서 같이 뺐다. 다시 넣으려면 조건 하나만 바꾸면 된다.
- 상한 104: 캡슐의 고정 폭은 버튼 6×40 + 구분선 6 + 좌우 8 = 254pt다. 254 + 104 = 358이 `BibleReadingView` 주석의 아이폰 세로 폭(358pt)을 넘지 않는 최대값이다. 더 좁은 기기(SE 343pt)에서는 기존처럼 최소 50까지 줄어든다. 측정상 가장 긴 약칭은 "2 Crón 36" 94pt, "2Thess 3" 88pt, "Ⅱサム24" 85pt이고 가용 폭은 96pt다(대체 글꼴로 잰 값이라 실기 확인 필요).

## 검토 반영(B1·B2)
- B1: `localizedPrefixLength`의 "직후가 글자면 거절" 규칙을 바꿨다. 이름표 후보(1-b)가 일치하고 마침표까지 소비한 뒤, 나머지를 공백 기준으로 잘라 비어 있거나 숫자(반각 0-9, 전각 ０-９)로 시작할 때만 인정한다. `Character.isNumber`는 쓰지 않았다. "一"이나 "Ⅰ"도 참이 되기 때문이다. 한국어 1)·2) 단계는 그대로다.
  - 모의 실행: 15개 이름표 × 66권 왕복 실패 0건. "Atti degli Apostoli 2"→행(짧은 "At" 대신 전체 이름), "Song of Solomon 2"→아, "John"→요(나머지 없음 허용).
  - 지금 영어 이름표에는 "Song of Songs"와 "Acts of the Apostles"가 없다(전체 이름이 "Song of Solomon", "Acts"). 그래서 이 두 입력은 이제 "일치 없음" 알림이 뜬다. 짧은 약칭으로 잘못 인식되지는 않는다. 이름표를 채우는 작업이 이 표기를 넣으면 전체 이름으로 인식된다.
- B2: `BookChapterPicker.submitFreeText`에서 책 이름을 떼어 낸 나머지를 장·절 파싱 직전에 `normalizedFullwidthDigits`로 바꾼다. ０-９ → 0-9, ： → ":". 반각만 쓰는 기존 입력(한국어 포함)은 결과가 같다. 전각 숫자는 이전에 `Int` 변환이 실패해 1장으로 갔다. 이제는 입력한 장으로 간다(예: "創３：１６" → 창 3:16).

## 남는 한계(데이터 문제 — 코드로 해결하지 않음)
- 이름표 15개 중 shortNames가 있는 것은 en, es, de, it, ja뿐이다. zh-Hans/zh-Hant, ru, th, fr, pt, vi, tl(fil)은 shortNames가 모두 빈 칸이라(`BookNameTable.swift` 주석: "공식 약어 체계를 확인하지 않아 비워 둔다") 전체 이름으로 폴백한다. 요청에 있던 "创1", "Пс118", "ปฐก50"은 데이터에 없어 나오지 않는다. 출처 없는 약칭을 지어 넣지 않았다.
- 그래서 104에서도 잘린다(추정). 잘리면 장 번호가 안 보인다.
  - zh 31/66: "出埃及记40", "撒母耳记上31" 등
  - ru 46/66, th 39/66, fr 36/66, vi 40/66, fil 39/66, pt 34/66
  - 해결하려면 검증된 약칭 데이터가 필요하다.
- 입력 해석도 이름표에 있는 표기만 받는다.
  - ja "サムエル記上3"은 인식하지 못한다(표에는 "サムエル記 第一").
  - ru "1 Царств"는 인식하지 못한다(표에는 "1-я Царств").
  - zh "约3:16"은 인식하지 못한다(약칭 없음).
  - 악센트를 빼고 입력한 es "Genesis"도 인식하지 못한다. 일본어 탁점(ガ↔カ)이 섞일 수 있어 악센트 무시 비교는 넣지 않았다.
  - 위 입력은 모두 "책 이름을 찾지 못했습니다" 알림이 뜬다(잘못된 곳으로 이동하지 않는다).
- B3(범위 밖): "創世記第1章"처럼 "第…章" 꼴은 인식하지 못한다. 나머지가 "第"로 시작해 B1 규칙에 따라 일치 없음 알림이 뜬다.
- BookNameTable.swift는 다른 작업이 채우고 있어 이번에 건드리지 않았다.
- 입력칸 placeholder("예:창세기1, 요3, 요3:16")가 모든 언어에서 한국어 예시다(xcstrings 번역도 한국어 예시를 그대로 둠). 이번 범위 밖이다.

## 3번 라벨 확인 결과
- `CrossReferenceTargetPicker.addSingleTarget()`의 `"\(abbr)\(ch):\(v)"`: `groups` → 저장 버튼 `onSave(..., groups.map(\.label), ...)` → `entryLabels`로 **저장**된다. 지시대로 바꾸지 않았다. 일괄 입력 `BulkCrossReferenceParser`의 label도 같은 경로로 저장되며 계속 한국어 약칭이다. 그래서 비한국어 화면의 "등록된 관주" 목록은 한국어 약칭으로 보인다(기존과 같음).
- `VerseZoomView.crossReferenceInlineSegments`: 매번 `targets`에서 계산해 `Text(segment.label)`로만 쓴다. `ForEach` id는 offset이다. 저장하지도 검색 키로 쓰지도 않아서 바꿨다. 한국어 결과는 같다(모든 책에 abbreviation이 있어 `?? nameKo` 폴백은 실제로 쓰이지 않는다. 책이 없으면 기존과 같은 "?장:절").

## BulkCrossReferenceParser 영향(새 함수로 분리하지 않은 이유)
- 한국어 앱: 이름표가 nil이라 변화 없다.
- 비한국어 앱: "John 3:16", "1 Sam 3:1" 같은 조각이 이전에는 인식 실패였는데 이제 인식된다. 장·절 정규식(`^\s*(\d{1,3})…`)이 앞 공백을 허용해 나머지 " 3:16"을 그대로 읽는다. 라벨은 한국어 약칭 그대로다.
- 오탐 검사: 책 이름 없는 조각("3", "5절", "6~8", "1-3", "1 3")은 이름표 후보와 일치하지 않는다. 숫자로 시작하는 후보는 뒤에 글자가 와야 해서 "1-3"은 "1-я Царств"에서 '3'≠'я'로 실패한다. 그래서 맨 숫자 문맥 승계는 이전과 같다.

## 검증(Python 모의 실행, Swift 로직과 같은 규칙)
- 15개 이름표 × 66권에 대해 아래 7가지 입력이 모두 원래 책으로 해석되는지 확인했다. 실패 0건.
  - 표시 문구(약칭 또는 이름 + 구분 문자 + 마지막 장)
  - 전체 이름 "1:1", 대문자, 소문자 붙여 쓰기
  - 약칭 + ".", 약칭 붙여 쓰기, 약칭 공백 제거
  - 같은 이름표 안에 공백·대소문자를 무시하면 같아지는 이름이 서로 다른 책에 있는 경우도 없었다.
- 충돌 사례:
  - en: "1 John 3:16"→요일, "John 3:16"→요, "1John 1"→요일, "Jonah 2"→욘, "Jon 1"→없음, "Phil 2"→빌, "Philemon 1"→몬, "Song of Solomon 2"→아, "1 Sam 3"/"1Sam 3"/"1 Samuel 3"→삼상, "Gen. 1"→창, "Johan 3"→없음(경계 거절), "요3:16"→요(한국어는 계속 인식)
  - es: "Jn 3:16"→요, "Jon 1"→욘, "Jonás 1"→욘, "Gén. 1"/"gén 1"→창
  - it: "Gio 1"→욜, "Gion 1"→욘, "Giovanni 3"→요, "Es 3"→출, "Est 2"→에, "Ab 1"→합, "Abd 1"→옵
  - de: "Joh 3:16"→요, "1 Joh 1"→요일
  - ja: "サムエル記第一3"/"サムエル記 第一 3"→삼상, "ヨハ3:16"→요, "ヨハネ3"→없음(경계 거절)
  - ru: "1-я Царств 3"→삼상

## 확인할 테스트(실기)
1. 한국어 앱:
   - 상단 칸이 "창1 장"이고 폭·동작이 이전과 같은지
   - "요3:16", "ㅇㅎㅂㅇ3", "삼상18" 이동
2. 영어 앱:
   - "Gen 1"이 보이고 라벨이 없는지
   - 그대로 이동 버튼을 누르면 같은 장이 유지되는지
   - "John 3:16" 입력 시 3장 16절로 가고 강조되는지
   - "1 john 1", "1Sam 3", "Ps 119" 이동
   - 이동 뒤 칸이 "John 3"으로 바뀌는지
3. 중국어 간체 앱:
   - "创世纪1" 표시, 이동 버튼으로 같은 장 유지
   - "约翰福音3:16" 입력
   - 긴 책("撒母耳记上31")에서 잘리는 정도
4. 아이폰 SE / 표준 / Pro Max 세로에서 캡슐이 화면을 넘지 않는지(비한국어는 칸이 최대 104)
5. 관주 칩: 비한국어에서 "Gen 1:1-2", 한국어에서 "고후1:1-2"
6. 관주 연결 시트(비한국어):
   - 일괄 입력 "John 3:16, 18"이 인식되는지
   - 저장 라벨이 "요3:16,18"(한국어)인지
