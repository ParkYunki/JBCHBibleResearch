# interlin1 — 원문 정보 화면 개편 (단어별 칸 · 원어 카드 재구성 · 쓰인 구절) (2026-11-02)

- 사양: 작업 지시문(A~D)과 목업(artifact 3CJNVdvYxfU5c2Rt8srurZ: Main/iPad/Mac/MacSearch/Search.dc.html).
  ⚠️ `claude/original-text-interlinear-proposal-2026-10-31.md`는 이 세션에 Projects 도구(`project_read`)가 없어 읽지 못했다. 지시문에 적힌 내용만 사양으로 썼다.
- 패치: `/home/claude/integ/interlin1.diff` (git apply 형식, 저장소 루트 기준). 기준 사본 `interlin1_base/`에서 `git apply --check` 통과,
  적용 결과가 `interlin1/`과 바이트 단위로 같음을 확인했다.
- 기준 sha1 (Mac 저장소 HEAD 299cfe43 + 작업 트리, 2026-11-02/03 두 번 대조해 같음)

```
8a07e97421375d271cf0dce1750fa4df2c9f587b  JBCHBibleResearch/BibleResearchPlatform/Sources/BibleResearchModels/BibleReference/LiteralCommentaryStore.swift
a56b8689c5d9fabb0f270a5e335d6d8fac39ef48  JBCHBibleResearch/BibleResearchPlatform/Sources/BibleResearchModels/BibleReference/OriginalTextModels.swift
f79903f788785a1de2b69140b03b54f153eb5c12  JBCHBibleResearch/BibleResearchPlatform/Sources/BibleResearchModels/BibleReference/OriginalTextStore.swift
4d12f728172cb426eb37f6ea68c6a6561b144ccc  JBCHBibleResearch/Localizable.xcstrings
dc87c856533ee61ddcf4af894fbc302ed3232a98  JBCHBibleResearch/Services/LiteralCommentaryService.swift
b293903c07ca33c3a13e147338ce64b852644b9d  JBCHBibleResearch/Services/OriginalTextLookupService.swift
84d39e41b38189e53dde55ead8ba3f9f9c40f7fe  JBCHBibleResearch/Views/Bible/BibleReadingView.swift
0dc627ed1fd386aaaa5cf4ba5d47bda1569b3a4a  JBCHBibleResearch/Views/Bible/BibleReadingViewModel.swift
d4c3e9aa03617e567070998e793d7045a06d64d6  JBCHBibleResearch/Views/Bible/OriginalTextInfoView.swift
62670431d27b0411c224fdc8e15559cc7fccac92  JBCHBibleResearch/Views/Memo/FlowLayoutHStack.swift
(새 파일) JBCHBibleResearch/Views/Bible/OriginalWordOccurrencesView.swift
```

새 파일은 프로젝트가 동기화 폴더(PBXFileSystemSynchronizedRootGroup)라 pbxproj 수정 없이 들어간다.

## 바뀐 파일 (수정본 기준 줄)

| 파일 | 줄 | 내용 |
|---|---|---|
| Views/Bible/OriginalTextInfoView.swift | 20~32, 42~50, 63~71, 74~96 | 머리 주석, `OriginalTextVerseSource.databasePath`, `onOpenVerse`, 새 상태(`alignedPhrases`·`verseCounts`·강조·`occurrenceWord`·`loadedVerseKey`·`@AppStorage showsMorphology`), `isLiteralEnglishExpanded` 삭제 |
| 〃 | 118~167 | `mainScroll` — `ScrollViewReader`, 원어 카드 제목 줄 + 카드 `.id` |
| 〃 | 169~238 | `sheetRoot` — macOS 같은 시트 안 화면 교체, iOS `navigationDestination(item:)` |
| 〃 | 254~260 | `.task(id:)`에 `loadVerseCounts()` |
| 〃 | 363~826 | 직역 카드(단어별 칸, 원어 어순 삭제, LSV 항상 보임), 단어별 칸, 원어 카드 재구성, 아래 줄, 히트 영역 상수 |
| 〃 | 830~858, 957~968, 970~985, 1002~1041 | 원어 글꼴·색·카드 색 공용 정적 함수, `loadWords` 추가 처리, `loadVerseCounts`, `occurrencePreviewSource`, `occurrencesView` |
| Views/Bible/OriginalWordOccurrencesView.swift | 새 파일 1~346 | 쓰인 구절 화면 |
| Views/Bible/BibleReadingView.swift | 406~413, 499~508, 1443~1454, 1464~1474 | `pendingOriginalTextJump`, `databasePath` 전달, `onDismiss` 이동, `onOpenVerse` |
| Views/Bible/BibleReadingViewModel.swift | 288~293 | `verseTextFilePath(registry:)` |
| Views/Memo/FlowLayoutHStack.swift | 12~16, 23~31, 45~60 | `clampsItemsToRowWidth`(기본 false — 기존 호출부 동작 같음) |
| Services/LiteralCommentaryService.swift | 11~18, 43~77 | `alignedPhrases(bookId:chapter:verse:literal:)` |
| Services/OriginalTextLookupService.swift | 89~134 | `nonisolated static occurrences(strongCode:)`, `verseCounts(strongCodes:)` |
| BibleResearchModels/…/OriginalTextStore.swift | 3~10, 21~25, 149~238 | `occurrences(strongCode:)`, `verseCounts(strongCodes:)` |
| BibleResearchModels/…/OriginalTextModels.swift | 102~118 | `OriginalWordOccurrence` |
| BibleResearchModels/…/LiteralCommentaryStore.swift | 23~48, 113~154 | `WordAlignment` 스키마 주석, `LiteralWordAlignment`, `wordAlignments(...)` |
| Localizable.xcstrings | 새 키 13개 | 아래 다국어 절 |

## 결정과 근거

### A. 직역 카드
- **단어별 칸**: `FlowLayoutHStack` 재사용. 이 레이아웃은 항목을 이상 크기로만 놓아 줄보다 넓은 칸(긴 짝 말)이 카드 밖으로 넘칠 수 있었다.
  선택 옵션 `clampsItemsToRowWidth`(기본 false)를 더해 이 칸에서만 넓은 항목에 줄 폭을 제안한다(칸은 `lineLimit(1)` → 줄임표). 다른 호출부(메모·설교 태그 등)는 기본값이라 그대로다.
- 칸 순서는 원문 순서대로 왼쪽부터(`FlowLayoutHStack`은 레이아웃 방향과 무관하게 왼쪽부터 놓는다). 히브리어 글자는 `Text` 안에서 RTL 그대로.
- **위 줄과 가운데 줄이 같을 때(영어 앱)**: 대소문자·문장부호·보충어 괄호·공백을 무시하고 글자·숫자가 같으면 가운데 줄을 투명하게 둔다(자리는 유지).
  근거 ① 같은 말을 두 번 쓰지 않는다(영어 앱은 직역이 LSV 기반 영어라 "Word"와 STEPBible "Word,"가 거의 같다). ② 줄 자리를 남겨 모든 칸 높이가 같아
  흐름 배치 줄에서 원어 줄이 같은 높이에 온다(줄을 빼면 칸 높이가 들쭉날쭉). 접근성 이름에서도 중복을 뺀다.
  같음 판정은 `isSameGloss`(예: "Word" = "Word,", "In the" = "In [the]"). 글자·숫자가 없는 말은 같다고 보지 않는다.
- 칸을 누르면 `ScrollViewReader.scrollTo(…, anchor: .center)` + 카드 테두리 2pt 강조 1.6초. 연속으로 누르면 차례 번호(`highlightGeneration`)로 앞 예약을 무효화.
- "원어 어순" 섹션·`wordOrderGlosses` 삭제. `hasLiteralCardContent`는 "문맥 영어가 있는 단어" 대신 "원어 단어가 하나라도 있음"을 본다.
- **LSV**: `DisclosureGroup`·`isLiteralEnglishExpanded` 삭제, 제목·본문·출처 항상 표시. `" || "` 줄바꿈, `text != appLiteral`이면 숨김 규칙 유지.
- 번역과의 차이: 변경 없음.

### B. 원어 카드
- 순서: 원어(글꼴·색 그대로, 26pt) → 음역 · Strong → 품사 정보(펼침일 때만, `morphOrFallbackText` 그대로) → 사전 뜻(`headlineGloss`, 굵게, "번역 중…"/"-" 그대로) → "이 절에서: ○○"(짝이 있을 때만) → 아래 줄.
- **연필**: 오른쪽 위 구석(위·오른쪽 6pt). 한국어 앱만, `beginEditingKorean`·접근성 라벨·help 그대로. 히트 영역은 `WordCardHitArea`로 44×30pt
  (위·오른쪽은 카드 테두리까지, 왼쪽 22, 아래 8). 연필이 있는 카드는 내용 위 여백을 30(= 6 + 16 + 8)으로 늘려 원어 줄이 아무리 넓어도 히트 영역과 겹치지 않는다. 다른 언어는 예전 18.
- **아래 줄**: [돋보기 + "N절"] | 세로선 | 네이버 | biblehub. `naverDictionaryURL`·`bibleHubStrongURL`·접근성 라벨·help 그대로.
  N절 버튼 접근성 이름·help = "이 단어가 쓰인 구절 N절"(절 수를 아직 모르면 "이 단어가 쓰인 구절").
  **좁은 카드(약 160~170pt)**: `ViewThatFits`로 [돋보기 "N절"]이 안 들어가면 [돋보기 N](숫자만)으로 바꾼다 — 영어 "2041 verses" 등에서 넘침 방지. 접근성 이름은 그대로.
  링크 히트 영역은 줄 높이 28에 맞춰 위 6/아래 12, 네이버 왼쪽은 세로선까지(6), 두 링크 사이는 간격 절반씩.
- '문맥(영어)' 줄과 맨 아래 Strong 줄은 카드에서 뺐다(문맥 영어는 단어별 칸 가운데 줄, Strong은 음역 줄로).
- **품사 정보 펼치기/접기**: "원어 단어 (N)" 제목 오른쪽 버튼 하나(모든 카드 공통). 처음 닫힘. `@AppStorage("originalTextInfo.showsMorphology")`
  — 키 규칙은 기존 `기능.항목`(예: `bibleToolRail.collapsed`, `sermon.listSort`, `literalCommentary.externalTranslationRecognition`). 접근성 값 "펼침/접힘"(기존 키).

### C. 짝짓기 데이터
- `LiteralCommentaryStore.wordAlignments` — 기존 `hasTable` 캐시로 표 존재를 한 번만 확인, 없으면 빈 배열. `phrase`/`start` NULL·빈 phrase 행은 건너뜀.
- `LiteralCommentaryService.alignedPhrases` — 기존 메인 액터·언어별 연결 캐시(`store(forLanguage:)`)를 그대로 쓴다. 한국어는 `"ko"`(Literal_ko.sqlite), 그 밖은 `AppLanguage.baseCode`(직역과 같은 규칙).
  현재 직역 문장(`appLiteral`)의 Unicode scalar 배열에서 `start`부터 `phrase` scalar가 그대로 있을 때만 넣는다. 범위 비교는 뺄셈 형태(`start <= 전체 - 길이`)라 큰 `start`에도 넘치지 않는다.
  파일·표가 없으면 빈 결과 → "—"(현재 번들 기본 경로).

### D. 쓰인 구절
- **조회**: 지시된 `group_concat(distinct original_text)` 대신 같은 WHERE·GROUP을 (절, 형태) 행으로 받아 Swift에서 모은다.
  근거: 원어 표기에 쉼표가 든 행이 실제로 있다(마 11:17 G3738 `ὠρχήσασθε,¶¬`, Mac DB 확인). `group_concat`의 기본 구분자가 쉼표라 다시 나누면 형태가 쪼개지고,
  SQLite는 `DISTINCT`와 구분자 인자를 함께 못 쓴다. 정렬은 책·장·절, 형태는 그 절 첫 등장 순(`MIN(word_order)`). 인덱스 추가 없음(전체 스캔, Mac 측정 G3588 7,061절 26ms).
- **카드 절 수**: 절이 바뀔 때 그 절 Strong 번호를 모아 `COUNT(DISTINCT (book_id*1000+chapter)*1000+verse) … IN (…) GROUP BY strong_code` 한 번(Mac 측정 28ms, 5개 번호).
  장 최대 150·절 최대 176이라 키가 겹치지 않는다. 결과는 지시문 예시와 같다(G3056 318, G1722 2151, G1510 2041).
- **스레드**: 둘 다 `Task.detached` + `nonisolated static`(기존 `DocumentViewerViewModel` 패턴). 공유 커넥션(메인 액터)과 별개로 호출마다 읽기 전용 연결을 열고 닫는다
  (`OriginalTextStore`/`BibleReferenceStore`는 스레드 안전하지 않음 — 인스턴스를 스레드 사이에 넘기지 않음). `.task(id:)` 취소 뒤 늦은 결과는 버린다.
- **본문 미리보기**: 원문 정보 구절 카드와 같은 번역본(`currentSource` = 칩으로 고른 번역본, 기본은 차이 설명이 있는 첫 열 → 첫 열). 열 정보가 없으면 구절 카드처럼 KRV.
  파일 경로는 `BibleReadingViewModel.verseTextFilePath(registry:)` — 열 본문과 같은 `store(for:)` 규칙(번들/사용자 추가·materialize)과 캐시를 그대로 쓴다.
  `version_code` 열이 있으면 번역본 코드로 고르는 규칙도 같다.
  **비용 측정(Mac, 2,041절)**: 절마다 `verse()` — BibleDB.sqlite(KRV) **7.2초**(인덱스를 못 탐: `SCAN … USING INDEX`), Bible_BSB/AYT 0.2초. 전체 읽기(`allVerses`) — 어느 파일이든 0.02~0.03초.
  그래서 백그라운드에서 한 번 통째로 읽고 필요한 절만 남긴다(약 3만 1천 절 임시 메모리, 끝나면 해제). 목록이 먼저 보이고 미리보기가 이어서 채워진다.
- **많은 결과**: 목록은 `ScrollView` 바로 아래 `LazyVStack`(다른 스택 안에 넣지 않음). 단어 요약·책 칩은 스크롤 밖 위에 고정.
  책 칩은 가로 스크롤 한 줄(구약 39권까지 여러 줄로 쌓이지 않게; 목업의 "…" 칩 대신).
- **목록 줄**: 참조 = `Book.displayShortReference(chapter:)` + ":절"(`VerseZoomView` 관주와 같은 규칙, 앱 언어 약칭), 그 절의 원어 형태 칩, 본문 2줄(성경 본문 글꼴 설정 `bibleBodyFont`).
- **화면 전환**: iOS는 기존 `NavigationStack`에 `navigationDestination(item: $occurrenceWord)`로 push, 시스템 바는 숨기고 `VerseLayerHeader`에 "‹ 원문 정보" 버튼(책/장 선택 "‹ 책 목록"과 같은 방식).
  macOS `sheetRoot`는 `ZStack`으로 본 화면을 숨기고(계층 유지 → 돌아오면 스크롤 위치 그대로) 같은 머리 부품의 쓰인 구절 화면을 겹친다. 아래 버튼 줄(닫기 Esc·메모하기)은 그대로.
- **구절 이동**: 행을 누르면 `onOpenVerse(ref)` → `BibleReadingView`가 `pendingOriginalTextJump`에 담고 시트를 닫고, `onDismiss`에서 기존 관주 이동 `jumpToCrossReferenceTarget`
  (`selectBook` + `highlightVerseTemporarily`)을 부른다. 시트가 열린 채 `selectBook`을 부르면 절 선택이 비워져 시트 내용(`selectedVerses.first`)이 닫히는 도중 사라지므로 `pendingSwitchToVerseZoom`과 같은 방식으로 닫힌 뒤 옮긴다.
- **절 이동 시 초기화**: `loadWords`에서 책-장-절 키가 바뀌었을 때만 `occurrenceWord`·강조를 닫는다(번역본 열 목록만 바뀌어 다시 읽는 경우엔 유지). `verseCounts`는 매번 비우고 다시 센다.
  macOS 쓰인 구절 화면에서 ‹ › 화살표로 절을 옮기면 새 절의 원문 정보 본 화면으로 돌아간다.

### 공용으로 뺀 것(값 변경 없음)
`OriginalTextInfoView.originalTextFont(isHebrew:size:)`, `originalTextColor(colorScheme:)`, `cardBackground`, `cardBorderColor`(정적) — 쓰인 구절 화면이 같은 색·글꼴을 쓰도록. 기존 인스턴스 속성은 이 정적 값을 돌려준다.

## 다국어 (Localizable.xcstrings, ko/en만, comment 포함, state translated)
`/home/claude/integ/interlin1_i18n/add_keys.py`(i18nbatch2/apply.py의 `serialize`/`specs` 재사용, 원본 재직렬화 바이트 일치 확인 후 진행, 지정자 일치 검사).

| 키 | en |
|---|---|
| 단어별 | Word by Word |
| 위부터 직역 속 말 · 영어 · 원어 | Top to bottom: literal · English · original |
| 원어 카드로 이동 | Goes to the word card (단어별 칸 접근성 힌트) |
| 원어 단어 (%lld) | Original Words (%lld) |
| 품사 정보 | Grammar |
| 이 절에서: %@ | In this verse: %@ |
| 쓰인 구절 %lld절 | ko 값 "%lld절", en plural one "%lld verse" / other "%lld verses" |
| 이 단어가 쓰인 구절 %lld절 | Verses with this word: %lld |
| 이 단어가 쓰인 구절 | Verses with this word |
| 쓰인 구절 | Occurrences |
| 원문 정보로 돌아가기 | Back to Original Text |
| 모든 형태 포함 | all forms |
| 쓰인 구절을 불러오지 못했습니다. | Couldn't load the verses. |

- "쓰인 구절 %lld절": 기존 키 "%lld절"은 en "Verse %lld"(절 **번호**)라 절 **수**에 쓰면 "Verse 318"이 된다. 그래서 별도 키를 두고 ko 값을 "%lld절"로 지정했다
  (키 ≠ ko 값은 `detail.overview` 등 기존 선례). 영어 단수/복수는 기존 plural 형식.
- 재사용한 기존 키: 원문 정보, 전체, 결과 없음, 펼침, 접힘, 번역 중…, 영어 직역 (LSV), 한글 뜻풀이 수정, 네이버 사전에서 찾기, biblehub.com에서 찾기.
- **쓰이지 않게 된 키(삭제하지 않음)**: `원어 어순`, `문맥` — 저장소 전체에서 다른 사용처 없음(grep 확인).

## 기기 확인 항목
1. 한국어 앱 요 1:1 / 창 1:1: 단어별 칸 17/7개, 위 줄 모두 "—"(번들에 WordAlignment 없음), 히브리어 칸 순서 왼쪽부터·글자 RTL.
2. 칸 누름 → 해당 원어 카드로 스크롤 + 테두리 강조 1.6초. 빠르게 두 칸 연속 → 마지막 카드만 강조 유지. LazyVGrid 아래쪽 카드(긴 절, 예: 에 8:9)도 스크롤되는지.
3. 영어 앱: LSV 칸이 직역과 같으면 숨김, 다르면 항상 보임(접기 없음). " || " 시가서 줄바꿈(시 23:1).
4. 원어 카드: 연필(한국어만) 오른쪽 위, 누르기 쉬운지/원어 줄과 겹치지 않는지, 수정 저장 → 같은 Strong 다른 절 반영(회귀).
5. 품사 정보 버튼: 처음 접힘, 펼침 → 모든 카드, 앱 재실행 후 상태 유지. VoiceOver 값 "펼침/접힘".
6. 좁은 카드(아이폰 세로, 2열 ≈160~170pt): 아래 줄 넘침 없음. 영어 앱 "2041 verses"가 숫자만으로 바뀌는지. 접근성 이름 유지.
7. 절 수 숫자: 요 1:1 λόγος 318, ἀρχῇ 55, ἦν 2,041(표시는 2041). 다음 절로 이동 시 이전 숫자가 남지 않는지.
8. 쓰인 구절: iOS push/‹ 원문 정보 복귀, 아이폰에서 가장자리 스와이프 뒤로가기는 시스템 바를 숨겨 동작하지 않을 수 있음(버튼으로 복귀) — 확인 필요.
   macOS 같은 시트 안 전환, 돌아오면 스크롤 위치 유지, Esc는 시트 닫기(기존 단축키).
9. 큰 결과(G3588 ὁ 7,061절, H0853 6,748절): 첫 표시 지연, 스크롤 부드러움, 미리보기 채워짐, 책 칩 필터.
10. 미리보기 번역본: 구절 카드 칩으로 다른 번역본을 고른 뒤 열면 그 번역본 본문. 사용자 추가 번역본 열이 첫 열일 때도 표시되는지.
11. 구절 누름 → 시트 닫힘 → 그 장으로 이동 + 절 강조, 조회 이력 기록(관주 이동과 같음). macOS 보조 창에서도 그 창이 이동하는지.
12. 회귀: 기기 번역(영어 외 언어 뜻), 차이 설명 칩 전환, 절 이동 시 상태 초기화, macOS ‹ › 화살표(VerseNavArrowsModifier), 메모하기 전환(양방향).
13. 다크 모드·사용자 테마 글자색/배경색에서 단어별 칸·강조 테두리·쓰인 구절 칩/목록 색.

## 확인하지 못한 것
- 이 환경에 Swift가 없어 빌드하지 못했다. API는 저장소 소스와 기존 사용례로 확인했다(`navigationDestination(item:)`, `Task.detached` + `nonisolated static`, `ViewThatFits`, `@AppStorage`).
- 사양서 문서(`original-text-interlinear-proposal-2026-10-31.md`)를 읽지 못했다(Projects 도구 없음). 지시문과 다른 점이 있으면 알려 주세요.
