# copyfmt1 — 구절 복사 시 앱 언어의 책 이름 (2026-10-29)

정적 분석으로만 작성했다. 컨테이너에 Swift 툴체인이 없어 빌드와 실기기 확인은 하지 못했다.

- **기준:** Mac 작업 트리의 현재 파일. 고친 4개 파일의 md5가 Mac 파일과 같은지 확인했다.
- **diff:** `/home/claude/integ/copyfmt1.diff` (4 files, +55 −13). 기준 파일 사본에 대해 `git apply --check` 통과. xcstrings는 넣지 않았다.
- **수정본:** `/home/claude/integ/copyfmt1/JBCHBibleResearch/…` (원래 경로)
- **번역 값:** `/home/claude/integ/i18nbatch2/`의 `translations.json` replace 목록에 86항목을 더했다(34 → 120). `REPORT.md` 표 (C)(D)에도 넣었다.

## 사용자 결정
1. 구절을 복사할 때 앱 언어의 책 이름으로 복사한다.
2. zh-Hant `인식하지 못한 항목: %@`의 "專案"을 "項目"으로 바꾼다.

## 1. 코드

**`Services/Bible/BibleVerseCopyFormatter.swift`**
- `format(…)`에 `bookNames: BookNameSource = .appLanguage` 인자를 더했다.
  - `.appLanguage`: 전체 이름은 `book.displayName`, 약어 설정이면 `book.displayShortName`.
  - `.korean`: 기존 코드 그대로(`nameKo` / `abbreviation.first ?? nameKo`).
- 호출부 5곳 중 4곳은 인자를 넘기지 않아 `.appLanguage`가 된다: S1 복사(`formattedCopyText`), 컨텍스트 메뉴 단일 번역본 복사(`copySingleTranslation`), 검색 결과 복사(`SearchView.copySearchResult`), 설정 미리보기.
- **한국어 앱 출력은 같다.** `AppLanguage.bookNameTableID`가 ko에서 nil이다. 그래서 `displayName == nameKo`, `displayShortName == abbreviation.first ?? nameKo`이다(AppLanguage.swift 100–115행). 앱이 지원하는 18개 언어 중 ko가 아닌 17개는 모두 이름표가 있다(en-CA/es-MX/fr-CA/pt-BR은 baseCode, id는 영어 표).
- **th·vi·fil 폴백:** 세 이름표의 shortNames는 66개 모두 빈 문자열이다(BookNameTable.swift). fullNames는 66개 모두 있다. 그래서 `displayShortName`은 `displayName`으로 폴백하고, 약어 설정을 켜도 전체 이름이 나온다. 빈 문자열이나 한국어 이름이 나오는 경우는 없다. 이 동작이 맞다고 본다.
- **장·절 형식:** 포매터에는 "장/절" 접미사가 없다. 형식은 모든 언어에서 `책 장:절`(책과 장 사이 한 칸, `referenceText` 90행)이다. 그래서 바꿀 것이 없다. 비한국어는 "Genesis 1:1", ja·zh는 "創世記 1:1"이 된다. 화면 표시용 `AppLanguage.bookChapterSeparator`(ko·ja·zh 붙여 쓰기)는 쓰지 않았다. 한국어 복사도 원래 "창세기 1:1"처럼 띄어 쓰므로, 같은 규칙을 모든 언어에 그대로 둔다.

**`Views/Bible/BibleReadingViewModel.swift` — 말씀 요약 삽입은 한글 이름 유지 (`.korean`)**
- `formattedBaseTranslationText`는 클립보드가 아니다. 말씀 요약 에디터에 바로 삽입한다(`BibleReadingView.copySelectedVersesIntoWordSummary` → `wordSummaryProxy.insertTextAtCursor`).
- 말씀 요약은 저장 후 `BibleReferenceIndexingService.reindexWordSummary`가 `BibleReferenceExtractor`로 구절 언급을 색인한다. 이 추출기는 한글 이름(`abbreviation + nameKo`)만 인식한다(BibleReferenceExtractor.swift 54–58행).
- 앱 언어 이름을 넣으면 비한국어 앱에서 그 구절 언급이 색인되지 않는다. 이것은 결정 범위("복사") 밖의 부작용이다. 그래서 이 경로는 지금 동작을 유지했다. 바꿀지는 아래 질문 1.

**`Views/Settings/SettingsView.swift` — 복사 형식 미리보기**
- 책 이름: `BibleVerseCopyFormatter.format` 기본값을 그대로 쓴다. 실제 복사와 같은 경로다.
- 본문은 `private static let previewSampleVerses`로 바꿨다. 앱 언어는 프로세스 동안 바뀌지 않으므로 한 번만 만든다.
  - 한국어: 기존 두 문구 그대로(1:2는 기존처럼 앞부분만).
  - 그 밖: `TranslationBootstrap.resolvedCurrentLanguageBundledDatabaseURL()`(인물·지명 상세와 같은 경로)에서 창 1:1–2를 읽는다. 성경 조회 화면과 같은 번들 본문이다. 15개 번들 모두 `version_code` 열이 없어 `verses(bookId:chapter:)`가 예외를 던지지 않는다(Mac Resources에서 확인).
  - 1:2는 번역된 키가 없다. 번역된 키 "태초에 하나님이 천지를 창조하시니라"만으로는 2절 미리보기(범위 "1-2", 절 번호, 줄바꿈 옵션)를 보여줄 수 없다. 그래서 번들 DB를 읽기로 했다.
  - 번들을 열지 못하면 번역된 창 1:1 키 하나만 쓴다. `selectedVerses`를 표본의 절 번호로 만들므로 1절 미리보기가 된다.
- 비한국어 1:2는 전체 절이라 한국어 미리보기보다 길다.

**`Services/AppLanguage.swift`** — 머리 주석만 고쳤다(복사는 앱 언어, 말씀 요약 삽입은 한글).

## 2. 출력을 다른 곳에서 다시 읽는지

| 경로 | 포매터 사용 | 영향 |
|---|---|---|
| 클립보드 복사 3곳 | 예(`.appLanguage`) | 사용자 결정대로 바뀐다 |
| 말씀 요약 삽입 | 예(`.korean`) | 바뀌지 않는다 |
| 설교 시작(`startSermonFromSelectedVerses`) | 아니요(`nameKo` 직접 사용) | 바뀌지 않는다 |
| 공유(ShareLink 등) | 포매터 출력 사용처 없음(grep) | 해당 없음 |
| 저장 키 | 포매터 출력을 키로 쓰는 곳 없음 | 해당 없음 |

**붙여넣기 인식** — `matchBookPrefix`를 Swift 로직 그대로 옮긴 i18nbatch2 `sim.py`와 현재 이름표로 확인했다.
- 같은 언어 앱의 성경 탭 이동란(`submitFreeText`)과 관주 일괄 입력(`BulkCrossReferenceParser`) 대상이다.
- 17개 언어 × 66권 × 전체 이름·약칭으로 `"<이름> 3:16"`, `"<이름> 3:16-18"`을 넣었다. 모두 (책, 3, 16)으로 인식됐다. 실패는 0이다.
- 인식되지 않는 경우는 세 가지다.
  - 복사본 전체를 그대로 붙여 넣으면 앞의 `[` 또는 `(` 때문에 책 이름을 찾지 못한다. 한국어 앱의 "[창세기 1:1]"도 지금 똑같다(`hasPrefix`). 새로 생긴 문제가 아니다.
  - 다른 언어 앱(특히 한국어 앱)에 붙이면 인식되지 않는다. 한국어 앱은 이름표가 nil이라 앱 언어 이름 후보가 없다.
  - **메모·설교·문서·말씀 요약 본문에 붙인 비한국어 참조는 구절 언급으로 색인되지 않는다.** 원인은 `BibleReferenceExtractor`가 한글만 인식하기 때문이다. 전에는 비한국어 앱에서도 한글 이름이 복사돼 색인됐다. 사용자 결정에 따른 결과이므로 보고한다(질문 2).

## 3. 번역 값 (i18nbatch2 replace, 86항목)
- `[창세기 1:1]`, `(창세기 1:1)`: 17개 언어 모두 그 언어 fullNames[0]이다(예: `[Genesis 1:1]`, `[創世記 1:1]`, `[ปฐมกาล 1:1]`).
- `예: [NKJV 창세기 1:1]`, `예: [NKJV][창세기 1:1]`
  - NKJV 자리에 앱 언어 번들 번역본의 `displayName`을 넣었다(`BundledTranslationCatalog.current`, 등록 시 `registry.displayName`과 같다).
  - 예: en "e.g. [Berean Standard Bible Genesis 1:1]", ja "例: [文語訳聖書 創世記 1:1]". 기존 언어별 접두어는 그대로 뒀다.
- `성경 이름 약어 사용 (창세기 → 창)`
  - 약칭이 있는 14개 언어는 "(전체 → 약칭)"이다(예: "(Genesis → Gen)", fr "(Genèse → Gn)", ru "(Бытие → Быт)").
  - **th·vi·fil**은 토글을 켜도 출력이 같다. 그래서 괄호 예시를 빼고 문장만 남겼다(예: "Use…"에 해당하는 "ใช้ชื่อเล่มแบบย่อ").
- zh-Hant `인식하지 못한 항목: %@`: "無法識別的專案：%@" → "無法識別的項目：%@".
- 모든 항목의 이전값은 Mac 현재 값과 같다. ko 값은 건드리지 않았다.

**검증**
- 1차: 처음 stage한 사본(mtime 1793260684943)에서 sermonundo1 xcstrings hunk → fill(64) → replace(120) 순서로 돌렸다. 재실행은 0개다. JSON 비교에서 바뀐 것은 (키,언어) 120개의 value뿐이었다. state·키 순서는 같다. 텍스트 diff는 value 줄 240줄뿐이다.
- 음성 시험: zh-Hant 값을 바꾼 사본에서 replace는 중단됐다. md5도 그대로였다.
- ⚠️ 작업 중 Mac xcstrings가 바뀌었다(mtime 1793262060480).
  - 내용은 "처음 사본 + sermonundo1 xcstrings hunk"와 바이트 단위로 같다. 즉 Mac에는 그 hunk가 이미 들어가 있다.
  - 새 사본에서 fill → replace를 바로 돌렸다. 결과(md5 2e05282d…)는 1차 결과와 같다.
  - 이 hunk는 추가만 있다. 그래서 다시 적용해도 `patch`가 오프셋으로 "성공"하고 키가 중복된다. Mac에서는 sermonundo1 xcstrings 단계를 건너뛰어야 한다.
- 복사 형식 예시 85항목은 이 diff의 코드와 함께 들어가야 실제 출력과 맞는다.

## 질문
1. 말씀 요약 삽입도 앱 언어 이름으로 바꿀까요? 바꾸면 비한국어 앱에서 그 구절이 "구절 언급"으로 색인되지 않습니다. `BibleReferenceExtractor`를 앱 언어 이름까지 넓히면 해결되지만 별도 작업입니다.
2. 비한국어 복사본을 메모·설교에 붙여 넣으면 구절 언급이 색인되지 않습니다. 추출기 확장을 다음 작업으로 잡을까요?
