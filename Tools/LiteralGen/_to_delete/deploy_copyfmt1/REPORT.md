# i18nbatch2 — Localizable.xcstrings 번역 일괄 처리 2차 (2026-10-29)

## 파일
- `apply.py` — 1차 스크립트 확장. 모드 `fill`(누락 채우기, 1차와 같은 규칙)과 `replace`(명시 목록만 교체)를 따로 실행한다. `--dry-run` 지원.
- `translations.json` — `fill`(4키×16언어=64), `replace`(120항목: key/lang/old/new/source. 34항목 + copyfmt1 86항목).
- `sim.py`, `tables.json` — 검증에 쓴 파서 시뮬레이션(아래 3·4절). 적용에는 필요 없다.

## 적용 순서 (Mac)
```
# 1) sermonundo1 먼저 적용 (굵게/기울임/문단 정렬 키가 여기서 생긴다)
# 2) 그 다음
python3 -I apply.py JBCHBibleResearch/Localizable.xcstrings fill
python3 -I apply.py JBCHBibleResearch/Localizable.xcstrings replace
```
- sermonundo1 없이 fill을 돌리면 3키는 "건너뜀: 파일에 키가 없습니다"로 나오고 `문단 스타일 변경` 16개만 들어간다. 그 뒤에 sermonundo1을 적용하고 fill을 다시 돌리면 나머지가 채워진다.
- ⚠️ copyfmt1 항목(복사 형식 예시 85개)은 `copyfmt1.diff` 코드 변경이 함께 들어가야 실제 출력과 맞는다. 코드 없이 replace만 돌리면 예시는 앱 언어 이름, 실제 복사는 한글 이름이 된다.
- 두 모드 모두 다시 실행해도 안전하다(fill은 기존 값 유지, replace는 현재 값이 이미 new면 "이미 반영됨").

## apply.py 안전 장치
- 공통: 원본 재직렬화 바이트 동일성 검사, 포맷 지정자 검사, 원자적 쓰기(임시 파일 + os.replace, 권한 유지), 실패 시 아무것도 쓰지 않음.
- fill: 기존 stringUnit/variations가 있는 언어는 덮어쓰지 않음. 새 키를 만들지 않음.
- replace: 목록의 (키, 언어)만 바꾼다. 키·언어 없음, stringUnit 단일 값이 아님, **현재 값 ≠ old**, 목록 중복 중 하나라도 있으면 전체 중단. `value`만 바꾸고 `state`는 그대로 둔다.

## 검증 (stage한 Mac 사본, mtime 1793260684943)
1. 사본에 `sermonundo1.diff`의 xcstrings hunk만 `patch -p1`로 적용 — 오프셋/퍼즈 없이 적용됨.
2. fill → "추가 64개", replace → "교체 34개". 재실행 시 0개, 파일 변경 없음.
   - [copyfmt1 재검증] 같은 사본(mtime 1793260684943, md5 be8bb937…)에 sermonundo1 xcstrings hunk → fill → replace 순서로 다시 돌렸다. fill "추가 64개", replace "교체 120개". 재실행은 둘 다 0개, 파일 변경 없음.
   - [copyfmt1, 2026-10-29 17:21 KST] 작업 중 Mac xcstrings가 바뀌었다(mtime 1793262060480, md5 d7cca5c1…). 내용은 위 사본 + sermonundo1 xcstrings hunk와 바이트 단위로 같다. 즉 **Mac에는 sermonundo1 xcstrings가 이미 들어가 있다.** 이 파일에 fill → replace를 바로 돌린 결과(md5 2e05282d…)는 위 검증 결과와 같다.
   - ⚠️ 이 hunk는 추가만 있어서, 이미 들어간 파일에도 `patch`가 오프셋(17/34/51줄)으로 "성공"한다. 다시 적용하면 키가 중복되니 Mac에서는 1) 단계를 건너뛴다.
3. 원본 재직렬화 동일성 통과(두 단계 모두).
4. JSON 수준 비교: 키 순서·최상위 필드 동일. 바뀐 것은 정확히 기대한 98개((키,언어))뿐(copyfmt1 추가 후: fill 64 + replace 120 = 184개, ko 값은 0개). fill 항목은 `{"stringUnit":{"state":"needs_review","value":…}}` 추가만, replace 항목은 `value` 외 필드 동일.
5. 텍스트 diff: fill은 추가 줄만(삭제 0줄), replace는 `"value" : …` 줄 34개만 바뀜(68줄). copyfmt1 추가 후에는 120개(240줄), value 줄 밖 변경 0줄.
6. 지정자: 대상 키에 지정자 없음. 새 값에도 없음(스크립트 검사 통과).
7. 음성 시험: 교체 대상 값 하나를 바꾼 사본에 replace → "현재 값이 old와 다릅니다"로 중단, 파일 md5 그대로. (copyfmt1: zh-Hant `인식하지 못한 항목: %@` 값을 바꾼 사본으로 다시 시험, 같은 결과.)

## 1. 누락 번역 채우기 (fill)
- `문단 스타일 변경`(SermonParagraphEditor 648·1175행 `setActionName`/actionName). 굵게/기울임/문단 정렬은 sermonundo1이 넣는 실행 취소 동작 이름이다.
- OS가 "실행 취소 <이름>"으로 앞에 붙이므로 각 언어는 명사구로 썼다. en-CA는 en과 같다.
- 용어는 기존 번역에 맞췄다: 문단 = Absatz/paragraphe/párrafo/paragrafo/段落/абзац/parágrafo/ย่อหน้า/đoạn văn/Talata/Paragraf(`문단 구성`), 스타일 = Stil/style/estilo/stile/スタイル/样式·樣式/стиль/estilo/สไตล์/kiểu/Istilo/Gaya(`선 스타일`, `번호 스타일` 등).
- `문단 정렬`은 en 값 "Alignment"에 맞춰 "정렬(Alignment)"만 썼다. 기존 키 `정렬`(=Sort)과는 뜻이 달라 그 번역을 쓰지 않았다.

## 2. 한국어 예시가 남은 키

### 복사 형식 4키 + 약어 토글 — 교체 (85개, copyfmt1)
- 처음에는 바꾸지 않았다(포매터가 `nameKo`만 썼음). 사용자 결정("구절 복사 시 앱 언어의 책 이름으로 복사")으로 copyfmt1이 `BibleVerseCopyFormatter`를 `Book.displayName` / 약어 설정 시 `Book.displayShortName`으로 바꿨다. 그래서 예시도 실제 출력에 맞춰 바꾼다.
- 책 이름: 앱 언어 → 이름표는 `AppLanguage.bookNameTableID`와 같다(en-CA→en, es-MX→es, fr-CA→fr, pt-BR→pt, id→영어 표, fil→타갈로그 표). 값은 `BookNameTable.swift`의 fullNames[0] / shortNames[0].
- 형식: 포매터는 모든 언어에서 `책 장:절`, 책과 장 사이 한 칸이다(`referenceText`). ja·zh도 `[創世記 1:1]`처럼 띄운다(화면 표시용 `bookChapterSeparator`는 복사에 쓰지 않는다).
- NKJV 자리: 이 문구는 번역본이 2개 이상 등록됐을 때만 보이고, 이름표는 `registry.displayName`이다. 앱 언어 번들 번역본(`BundledTranslationCatalog.current`)의 displayName을 그대로 넣었다(예: en "Berean Standard Bible", ja "文語訳聖書"). 기존 언어별 접두어("e.g. ", "例：" 등)는 그대로 뒀다.
- 약어 토글 th·vi·fil: 이름표 shortNames가 모두 비어 있어 `displayShortName`이 전체 이름으로 폴백한다. 토글을 켜도 출력이 바뀌지 않으므로 "(… → …)" 예시를 빼고 문장만 남겼다.
- 한국어 값(키 그대로)은 건드리지 않았다.

### zh-Hant `인식하지 못한 항목: %@` — 교체 (1개, copyfmt1)
- "無法識別的專案：%@" → "無法識別的項目：%@". 사용자 결정. "專案"은 대만어로 '프로젝트'다.

### `태초에 하나님이 천지를 창조하시니라` — 교체 (17개)
- 쓰이는 곳: `SettingsView.previewRow`(867행) 하나뿐이다. 성경 본문 글꼴·크기·줄간격·색 미리보기다. 같은 문장이 1074행에도 있지만 `BibleVerse(content:)`의 String이라 지역화되지 않는다. 따라서 이번 교체는 1074행에 영향을 주지 않는다.
- 비한국어 앱의 성경 조회에는 그 언어 번들 하나만 보인다(`BundledTranslationCatalog.current`). 그래서 미리보기도 그 번들의 창 1:1로 맞췄다. 그 언어 문자로 글꼴을 확인할 수 있다.
- 값은 Mac `Resources/Bible_<code>.sqlite`의 `BibleVerses(book_id=1, chapter=1, verse=1).content`를 그대로 썼다. es/es-MX의 "EN el principio"는 RV1909 원문 표기(첫 단어 대문자)다. 조회 화면과 같게 고치지 않았다.

### 관주 일괄 입력 안내 — 교체 (17개, 예시 부분만)
- `BulkCrossReferenceParser`는 `,`와 줄바꿈으로 조각을 나눈다. 책 이름은 `BooksProvider.matchBookPrefix`로 인식한다(앱 언어 이름표의 fullNames/shortNames, 대소문자·공백 무시, 이름 뒤 마침표 1개 허용, 이름 뒤가 숫자일 때만 인정). 장·절은 `^\s*(\d{1,3})\s*(?:장|편)?\s*(?:[:,]\s*)?(절지정)?\s*절?$`로 읽는다.
- 그래서 예시는 `책 장:절`, 범위는 `-`, "112:1,3,5"(뒤의 3, 5는 앞 책·장을 물려받음)로 썼다. "편/절"은 뺐다.
- 프랑스어식 `Gn 1.1`, `Gn 1,1`은 인식되지 않는다(시뮬레이션 확인). 그래서 fr/fr-CA도 콜론을 썼다.
- 약칭이 없는 th/vi/fil은 이름표 fullNames를 썼다. zh는 약칭(创/出/诗, 創/出/詩)만 썼다. ja는 원문처럼 약칭과 전체 이름을 섞었다(創 / 出エジプト記 / 詩).
- 17개 언어 모두 Swift 로직을 옮긴 `sim.py`로 돌렸다. 결과는 [창1:1, 출1:2, 출1:3, 시112:1, 시112:3, 시112:5], 인식 실패 0이다.

### 의도적 한국어 — 그대로 둠
- `한글 (가. 나. 다.)`, 개역한글·대한성서공회 고지 키들: 바꾸지 않았다.

## 3. 성경 탭 입력란 placeholder 확인 — 교체 없음
- `예:창세기1, 요3, 요3:16`, `예: 요3:16`, `예: 창세기1, 요3:16`: 17개 언어 모두 값이 있다. 예시를 `submitFreeText` 로직(접두 인식 + 장·`:`절)으로 돌렸다. 모두 창 1장 / 요 3:16으로 이동한다. fil/th/vi는 약칭이 없어 "Juan/ยอห์น/Giăng 3:16" 하나만 쓴다. 이 언어에서는 이것이 맞다. zh는 创1/约3:16, 創1/約3:16(약칭만)이다.
- `책 이름 검색 (예: 요한, ㅇㅎ)`: `matchesGridSearch`(displayName/displayShortName 부분 일치)로 확인했다. 17개 언어 모두 요한복음·요한1~3서(ja는 요한계시록도)가 나온다. zh "约翰/約翰"은 전체 이름이 아니라 부분 문자열이다. zhnames1 이후(约翰一书 등)에도 그대로 맞는다.
- Views/Bible의 다른 입력란: `본문에서 찾기`(BibleChapterFind), `책 이름 검색`(OutlineTreeView), `한글 뜻풀이`(한국어 뜻풀이 편집이라 맞음). 17개 언어 모두 있고 예시가 없어 문제없다.

## 보고만 하는 것 (이번 범위 밖)
- (copyfmt1 코드 변경으로 해결: 비한국어는 앱 언어 번들의 창 1:1-2) 설정 > 복사 형식 미리보기 본문(`SettingsView.swift` 1074·1075행)은 코드 안의 한국어 문자열("태초에…", "땅이 혼돈하고…")이다. 지역화 대상이 아니어서 비한국어 앱에서도 한국어 본문이 보인다. 책 이름(창세기)은 실제 출력과 같다. 본문까지 맞추려면 코드 변경이 필요하다.
- (copyfmt1에서 해결) zh-Hant `인식하지 못한 항목: %@`의 "專案" → "項目" 교체 목록에 넣었다.
- 관주 일괄 입력에서 한국어 책 이름("창1:1")은 앱 언어와 관계없이 계속 인식된다(matchBookPrefix 1단계). 안내 문구에는 쓰지 않았다.

### 채우기(fill) — 64개 (모두 기존 값 없음 → 추가, state needs_review)

| 언어 | 문단 스타일 변경 | 굵게 | 기울임 | 문단 정렬 |
|---|---|---|---|---|
| de | Änderung des Absatzstils | Fett | Kursiv | Ausrichtung |
| en-CA | Change Paragraph Style | Bold | Italic | Alignment |
| es | Cambio de estilo de párrafo | Negrita | Cursiva | Alineación |
| es-MX | Cambio de estilo de párrafo | Negrita | Cursiva | Alineación |
| fil | Pagbabago ng Istilo ng Talata | Bold | Italic | Pagkakahanay |
| fr | Modification du style de paragraphe | Gras | Italique | Alignement |
| fr-CA | Modification du style de paragraphe | Gras | Italique | Alignement |
| id | Perubahan Gaya Paragraf | Tebal | Miring | Perataan |
| it | Modifica stile paragrafo | Grassetto | Corsivo | Allineamento |
| ja | 段落スタイルの変更 | ボールド | イタリック | 行揃え |
| pt-BR | Alteração do estilo de parágrafo | Negrito | Itálico | Alinhamento |
| ru | Изменение стиля абзаца | Жирный | Курсив | Выравнивание |
| th | การเปลี่ยนสไตล์ย่อหน้า | ตัวหนา | ตัวเอียง | การจัดแนว |
| vi | Thay đổi kiểu đoạn văn | Đậm | Nghiêng | Căn chỉnh |
| zh-Hans | 段落样式更改 | 粗体 | 斜体 | 对齐 |
| zh-Hant | 段落樣式變更 | 粗體 | 斜體 | 對齊 |

#### (A) 키 `태초에 하나님이 천지를 창조하시니라` — 17개

| 언어 | 이전값 | 새값 | 근거 |
|---|---|---|---|
| de | 태초에 하나님이 천지를 창조하시니라 | Am Anfang schuf Gott Himmel und Erde. | Resources/Bible_LUT1912.sqlite 창 1:1 |
| en | 태초에 하나님이 천지를 창조하시니라 | In the beginning God created the heavens and the earth. | Resources/Bible_BSB.sqlite 창 1:1 |
| en-CA | 태초에 하나님이 천지를 창조하시니라 | In the beginning God created the heavens and the earth. | Resources/Bible_BSB.sqlite 창 1:1 |
| es | 태초에 하나님이 천지를 창조하시니라 | EN el principio crió Dios los cielos y la tierra. | Resources/Bible_RV1909.sqlite 창 1:1 |
| es-MX | 태초에 하나님이 천지를 창조하시니라 | EN el principio crió Dios los cielos y la tierra. | Resources/Bible_RV1909.sqlite 창 1:1 |
| fil | 태초에 하나님이 천지를 창조하시니라 | Noong simula nilikha ng Diyos ang langit at ang lupa. | Resources/Bible_TGLULB.sqlite 창 1:1 |
| fr | 태초에 하나님이 천지를 창조하시니라 | Au commencement, Dieu créa les cieux et la terre. | Resources/Bible_LSG1910.sqlite 창 1:1 |
| fr-CA | 태초에 하나님이 천지를 창조하시니라 | Au commencement, Dieu créa les cieux et la terre. | Resources/Bible_LSG1910.sqlite 창 1:1 |
| id | 태초에 하나님이 천지를 창조하시니라 | Pada mulanya, Allah menciptakan langit dan bumi. | Resources/Bible_AYT.sqlite 창 1:1 |
| it | 태초에 하나님이 천지를 창조하시니라 | Nel principio Iddio creò i cieli e la terra. | Resources/Bible_RIV1927.sqlite 창 1:1 |
| ja | 태초에 하나님이 천지를 창조하시니라 | 元始に神天地を創造たまへり | Resources/Bible_JPBUNGO.sqlite 창 1:1 |
| pt-BR | 태초에 하나님이 천지를 창조하시니라 | No princípio, Deus criou os céus e a terra. | Resources/Bible_BPM.sqlite 창 1:1 |
| ru | 태초에 하나님이 천지를 창조하시니라 | В начале сотворил Бог небо и землю. | Resources/Bible_SYN.sqlite 창 1:1 |
| th | 태초에 하나님이 천지를 창조하시니라 | ในเริ่มแรกนั้นพระเจ้าทรงเนรมิตสร้างฟ้าและแผ่นดินโลก | Resources/Bible_THKJV.sqlite 창 1:1 |
| vi | 태초에 하나님이 천지를 창조하시니라 | Ban đầu Đức Chúa Trời dựng nên trời đất. | Resources/Bible_VIE1934.sqlite 창 1:1 |
| zh-Hans | 태초에 하나님이 천지를 창조하시니라 | 起初上帝创造天地。 | Resources/Bible_CUV1919S.sqlite 창 1:1 |
| zh-Hant | 태초에 하나님이 천지를 창조하시니라 | 起初上帝創造天地。 | Resources/Bible_CUV1919.sqlite 창 1:1 |

#### (B) 키 `여러 구절을 콤마(,) 또는 줄바꿈으로 구분해 붙여넣으면 한 번에 추가합니다. 예: 창1:1, 출애굽기1:2~3, 시편112편1,3,5절` — 17개

| 언어 | 이전값 | 새값 | 근거 |
|---|---|---|---|
| de | Füge mehrere Stellen durch Kommas (,) oder Zeilenumbrüche getrennt ein, um sie auf einmal hinzuzufügen. Beispiel: 창1:1, 출애굽기1:2~3, 시편112편1,3,5절 | Füge mehrere Stellen durch Kommas (,) oder Zeilenumbrüche getrennt ein, um sie auf einmal hinzuzufügen. Beispiel: Gen 1:1, Exodus 1:2-3, Ps 112:1,3,5 | BulkCrossReferenceParser 시뮬레이션으로 6절 모두 인식 확인 |
| en | Paste multiple references separated by commas (,) or line breaks to add them all at once. Example: 창1:1, 출애굽기1:2~3, 시편112편1,3,5절 | Paste multiple references separated by commas (,) or line breaks to add them all at once. Example: Gen 1:1, Exodus 1:2-3, Ps 112:1,3,5 | BulkCrossReferenceParser 시뮬레이션으로 6절 모두 인식 확인 |
| en-CA | Paste multiple references separated by commas (,) or line breaks to add them all at once. Example: 창1:1, 출애굽기1:2~3, 시편112편1,3,5절 | Paste multiple references separated by commas (,) or line breaks to add them all at once. Example: Gen 1:1, Exodus 1:2-3, Ps 112:1,3,5 | BulkCrossReferenceParser 시뮬레이션으로 6절 모두 인식 확인 |
| es | Pega varias referencias separadas por comas (,) o saltos de línea para añadirlas todas a la vez. Ejemplo: 창1:1, 출애굽기1:2~3, 시편112편1,3,5절 | Pega varias referencias separadas por comas (,) o saltos de línea para añadirlas todas a la vez. Ejemplo: Gén 1:1, Éxodo 1:2-3, Sal 112:1,3,5 | BulkCrossReferenceParser 시뮬레이션으로 6절 모두 인식 확인 |
| es-MX | Pega varias referencias separadas por comas (,) o saltos de línea para agregarlas todas a la vez. Ejemplo: 창1:1, 출애굽기1:2~3, 시편112편1,3,5절 | Pega varias referencias separadas por comas (,) o saltos de línea para agregarlas todas a la vez. Ejemplo: Gén 1:1, Éxodo 1:2-3, Sal 112:1,3,5 | BulkCrossReferenceParser 시뮬레이션으로 6절 모두 인식 확인 |
| fil | I-paste ang maraming reference na pinaghihiwalay ng kuwit (,) o bagong linya para idagdag lahat nang sabay. Halimbawa: 창1:1, 출애굽기1:2~3, 시편112편1,3,5절 | I-paste ang maraming reference na pinaghihiwalay ng kuwit (,) o bagong linya para idagdag lahat nang sabay. Halimbawa: Genesis 1:1, Exodo 1:2-3, Mga Awit 112:1,3,5 | BulkCrossReferenceParser 시뮬레이션으로 6절 모두 인식 확인 |
| fr | Collez plusieurs références séparées par des virgules (,) ou des retours à la ligne pour les ajouter en une fois. Exemple : 창1:1, 출애굽기1:2~3, 시편112편1,3,5절 | Collez plusieurs références séparées par des virgules (,) ou des retours à la ligne pour les ajouter en une fois. Exemple : Gn 1:1, Exode 1:2-3, Ps 112:1,3,5 | BulkCrossReferenceParser 시뮬레이션으로 6절 모두 인식 확인 |
| fr-CA | Collez plusieurs références séparées par des virgules (,) ou des retours à la ligne pour les ajouter en une fois. Exemple : 창1:1, 출애굽기1:2~3, 시편112편1,3,5절 | Collez plusieurs références séparées par des virgules (,) ou des retours à la ligne pour les ajouter en une fois. Exemple : Gn 1:1, Exode 1:2-3, Ps 112:1,3,5 | BulkCrossReferenceParser 시뮬레이션으로 6절 모두 인식 확인 |
| id | Tempel beberapa referensi yang dipisahkan koma (,) atau baris baru untuk menambahkan semuanya sekaligus. Contoh: 창1:1, 출애굽기1:2~3, 시편112편1,3,5절 | Tempel beberapa referensi yang dipisahkan koma (,) atau baris baru untuk menambahkan semuanya sekaligus. Contoh: Gen 1:1, Exodus 1:2-3, Ps 112:1,3,5 | BulkCrossReferenceParser 시뮬레이션으로 6절 모두 인식 확인 |
| it | Incolla più riferimenti separati da virgole (,) o a capo per aggiungerli tutti insieme. Esempio: 창1:1, 출애굽기1:2~3, 시편112편1,3,5절 | Incolla più riferimenti separati da virgole (,) o a capo per aggiungerli tutti insieme. Esempio: Gen 1:1, Esodo 1:2-3, Sal 112:1,3,5 | BulkCrossReferenceParser 시뮬레이션으로 6절 모두 인식 확인 |
| ja | 複数の箇所をカンマ (,) または改行で区切って貼り付けると、まとめて追加できます。例: 창1:1, 출애굽기1:2~3, 시편112편1,3,5절 | 複数の箇所をカンマ (,) または改行で区切って貼り付けると、まとめて追加できます。例: 創1:1, 出エジプト記1:2-3, 詩112:1,3,5 | BulkCrossReferenceParser 시뮬레이션으로 6절 모두 인식 확인 |
| pt-BR | Cole várias referências separadas por vírgulas (,) ou quebras de linha para adicioná-las de uma vez. Exemplo: 창1:1, 출애굽기1:2~3, 시편112편1,3,5절 | Cole várias referências separadas por vírgulas (,) ou quebras de linha para adicioná-las de uma vez. Exemplo: Gn 1:1, Êxodo 1:2-3, Sl 112:1,3,5 | BulkCrossReferenceParser 시뮬레이션으로 6절 모두 인식 확인 |
| ru | Вставьте несколько ссылок, разделённых запятыми (,) или переводами строк, чтобы добавить их все сразу. Пример: 창1:1, 출애굽기1:2~3, 시편112편1,3,5절 | Вставьте несколько ссылок, разделённых запятыми (,) или переводами строк, чтобы добавить их все сразу. Пример: Быт 1:1, Исход 1:2-3, Пс 112:1,3,5 | BulkCrossReferenceParser 시뮬레이션으로 6절 모두 인식 확인 |
| th | วางข้ออ้างอิงหลายรายการที่คั่นด้วยจุลภาค (,) หรือขึ้นบรรทัดใหม่ เพื่อเพิ่มทั้งหมดในครั้งเดียว ตัวอย่าง: 창1:1, 출애굽기1:2~3, 시편112편1,3,5절 | วางข้ออ้างอิงหลายรายการที่คั่นด้วยจุลภาค (,) หรือขึ้นบรรทัดใหม่ เพื่อเพิ่มทั้งหมดในครั้งเดียว ตัวอย่าง: ปฐมกาล 1:1, อพยพ 1:2-3, สดุดี 112:1,3,5 | BulkCrossReferenceParser 시뮬레이션으로 6절 모두 인식 확인 |
| vi | Dán nhiều đoạn tham chiếu cách nhau bằng dấu phẩy (,) hoặc xuống dòng để thêm tất cả cùng lúc. Ví dụ: 창1:1, 출애굽기1:2~3, 시편112편1,3,5절 | Dán nhiều đoạn tham chiếu cách nhau bằng dấu phẩy (,) hoặc xuống dòng để thêm tất cả cùng lúc. Ví dụ: Sáng Thế Ký 1:1, Xuất Hành Ký 1:2-3, Thi-thiên 112:1,3,5 | BulkCrossReferenceParser 시뮬레이션으로 6절 모두 인식 확인 |
| zh-Hans | 粘贴以逗号 (,) 或换行分隔的多个经文出处，即可一次全部添加。例：창1:1, 출애굽기1:2~3, 시편112편1,3,5절 | 粘贴以逗号 (,) 或换行分隔的多个经文出处，即可一次全部添加。例：创1:1, 出1:2-3, 诗112:1,3,5 | BulkCrossReferenceParser 시뮬레이션으로 6절 모두 인식 확인 |
| zh-Hant | 貼上以逗號 (,) 或換行分隔的多個經文出處，即可一次全部新增。例：창1:1, 출애굽기1:2~3, 시편112편1,3,5절 | 貼上以逗號 (,) 或換行分隔的多個經文出處，即可一次全部新增。例：創1:1, 出1:2-3, 詩112:1,3,5 | BulkCrossReferenceParser 시뮬레이션으로 6절 모두 인식 확인 |

#### (C) 복사 형식 예시 5키 (copyfmt1) — 85개

| 키 | 언어 | 이전값 | 새값 |
|---|---|---|---|
| [창세기 1:1] | de | [창세기 1:1] | [Genesis 1:1] |
| (창세기 1:1) | de | (창세기 1:1) | (Genesis 1:1) |
| 예: [NKJV 창세기 1:1] | de | z. B. [NKJV 창세기 1:1] | z. B. [Lutherbibel 1912 Genesis 1:1] |
| 예: [NKJV][창세기 1:1] | de | z. B. [NKJV][창세기 1:1] | z. B. [Lutherbibel 1912][Genesis 1:1] |
| 성경 이름 약어 사용 (창세기 → 창) | de | Abgekürzte Buchnamen verwenden (창세기 → 창) | Abgekürzte Buchnamen verwenden (Genesis → Gen) |
| [창세기 1:1] | en | [창세기 1:1] | [Genesis 1:1] |
| (창세기 1:1) | en | (창세기 1:1) | (Genesis 1:1) |
| 예: [NKJV 창세기 1:1] | en | e.g. [NKJV 창세기 1:1] | e.g. [Berean Standard Bible Genesis 1:1] |
| 예: [NKJV][창세기 1:1] | en | e.g. [NKJV][창세기 1:1] | e.g. [Berean Standard Bible][Genesis 1:1] |
| 성경 이름 약어 사용 (창세기 → 창) | en | Use abbreviated book names (창세기 → 창) | Use abbreviated book names (Genesis → Gen) |
| [창세기 1:1] | en-CA | [창세기 1:1] | [Genesis 1:1] |
| (창세기 1:1) | en-CA | (창세기 1:1) | (Genesis 1:1) |
| 예: [NKJV 창세기 1:1] | en-CA | e.g. [NKJV 창세기 1:1] | e.g. [Berean Standard Bible Genesis 1:1] |
| 예: [NKJV][창세기 1:1] | en-CA | e.g. [NKJV][창세기 1:1] | e.g. [Berean Standard Bible][Genesis 1:1] |
| 성경 이름 약어 사용 (창세기 → 창) | en-CA | Use abbreviated book names (창세기 → 창) | Use abbreviated book names (Genesis → Gen) |
| [창세기 1:1] | es | [창세기 1:1] | [Génesis 1:1] |
| (창세기 1:1) | es | (창세기 1:1) | (Génesis 1:1) |
| 예: [NKJV 창세기 1:1] | es | p. ej. [NKJV 창세기 1:1] | p. ej. [Reina-Valera 1909 Génesis 1:1] |
| 예: [NKJV][창세기 1:1] | es | p. ej. [NKJV][창세기 1:1] | p. ej. [Reina-Valera 1909][Génesis 1:1] |
| 성경 이름 약어 사용 (창세기 → 창) | es | Usar nombres de libros abreviados (창세기 → 창) | Usar nombres de libros abreviados (Génesis → Gén) |
| [창세기 1:1] | es-MX | [창세기 1:1] | [Génesis 1:1] |
| (창세기 1:1) | es-MX | (창세기 1:1) | (Génesis 1:1) |
| 예: [NKJV 창세기 1:1] | es-MX | p. ej. [NKJV 창세기 1:1] | p. ej. [Reina-Valera 1909 Génesis 1:1] |
| 예: [NKJV][창세기 1:1] | es-MX | p. ej. [NKJV][창세기 1:1] | p. ej. [Reina-Valera 1909][Génesis 1:1] |
| 성경 이름 약어 사용 (창세기 → 창) | es-MX | Usar nombres de libros abreviados (창세기 → 창) | Usar nombres de libros abreviados (Génesis → Gén) |
| [창세기 1:1] | fil | [창세기 1:1] | [Genesis 1:1] |
| (창세기 1:1) | fil | (창세기 1:1) | (Genesis 1:1) |
| 예: [NKJV 창세기 1:1] | fil | hal. [NKJV 창세기 1:1] | hal. [Banal na Bibliya (ULB) Genesis 1:1] |
| 예: [NKJV][창세기 1:1] | fil | hal. [NKJV][창세기 1:1] | hal. [Banal na Bibliya (ULB)][Genesis 1:1] |
| 성경 이름 약어 사용 (창세기 → 창) | fil | Gumamit ng pinaikling pangalan ng aklat (창세기 → 창) | Gumamit ng pinaikling pangalan ng aklat |
| [창세기 1:1] | fr | [창세기 1:1] | [Genèse 1:1] |
| (창세기 1:1) | fr | (창세기 1:1) | (Genèse 1:1) |
| 예: [NKJV 창세기 1:1] | fr | ex. [NKJV 창세기 1:1] | ex. [Louis Segond 1910 Genèse 1:1] |
| 예: [NKJV][창세기 1:1] | fr | ex. [NKJV][창세기 1:1] | ex. [Louis Segond 1910][Genèse 1:1] |
| 성경 이름 약어 사용 (창세기 → 창) | fr | Utiliser les noms de livres abrégés (창세기 → 창) | Utiliser les noms de livres abrégés (Genèse → Gn) |
| [창세기 1:1] | fr-CA | [창세기 1:1] | [Genèse 1:1] |
| (창세기 1:1) | fr-CA | (창세기 1:1) | (Genèse 1:1) |
| 예: [NKJV 창세기 1:1] | fr-CA | ex. [NKJV 창세기 1:1] | ex. [Louis Segond 1910 Genèse 1:1] |
| 예: [NKJV][창세기 1:1] | fr-CA | ex. [NKJV][창세기 1:1] | ex. [Louis Segond 1910][Genèse 1:1] |
| 성경 이름 약어 사용 (창세기 → 창) | fr-CA | Utiliser les noms de livres abrégés (창세기 → 창) | Utiliser les noms de livres abrégés (Genèse → Gn) |
| [창세기 1:1] | id | [창세기 1:1] | [Genesis 1:1] |
| (창세기 1:1) | id | (창세기 1:1) | (Genesis 1:1) |
| 예: [NKJV 창세기 1:1] | id | mis. [NKJV 창세기 1:1] | mis. [Alkitab Yang Terbuka Genesis 1:1] |
| 예: [NKJV][창세기 1:1] | id | mis. [NKJV][창세기 1:1] | mis. [Alkitab Yang Terbuka][Genesis 1:1] |
| 성경 이름 약어 사용 (창세기 → 창) | id | Gunakan nama kitab singkat (창세기 → 창) | Gunakan nama kitab singkat (Genesis → Gen) |
| [창세기 1:1] | it | [창세기 1:1] | [Genesi 1:1] |
| (창세기 1:1) | it | (창세기 1:1) | (Genesi 1:1) |
| 예: [NKJV 창세기 1:1] | it | es. [NKJV 창세기 1:1] | es. [Riveduta 1927 Genesi 1:1] |
| 예: [NKJV][창세기 1:1] | it | es. [NKJV][창세기 1:1] | es. [Riveduta 1927][Genesi 1:1] |
| 성경 이름 약어 사용 (창세기 → 창) | it | Usa nomi abbreviati dei libri (창세기 → 창) | Usa nomi abbreviati dei libri (Genesi → Gen) |
| [창세기 1:1] | ja | [창세기 1:1] | [創世記 1:1] |
| (창세기 1:1) | ja | (창세기 1:1) | (創世記 1:1) |
| 예: [NKJV 창세기 1:1] | ja | 例: [NKJV 창세기 1:1] | 例: [文語訳聖書 創世記 1:1] |
| 예: [NKJV][창세기 1:1] | ja | 例: [NKJV][창세기 1:1] | 例: [文語訳聖書][創世記 1:1] |
| 성경 이름 약어 사용 (창세기 → 창) | ja | 書名の略称を使用 (창세기 → 창) | 書名の略称を使用 (創世記 → 創) |
| [창세기 1:1] | pt-BR | [창세기 1:1] | [Gênesis 1:1] |
| (창세기 1:1) | pt-BR | (창세기 1:1) | (Gênesis 1:1) |
| 예: [NKJV 창세기 1:1] | pt-BR | ex.: [NKJV 창세기 1:1] | ex.: [Bíblia Portuguesa Mundial Gênesis 1:1] |
| 예: [NKJV][창세기 1:1] | pt-BR | ex.: [NKJV][창세기 1:1] | ex.: [Bíblia Portuguesa Mundial][Gênesis 1:1] |
| 성경 이름 약어 사용 (창세기 → 창) | pt-BR | Usar nomes abreviados dos livros (창세기 → 창) | Usar nomes abreviados dos livros (Gênesis → Gn) |
| [창세기 1:1] | ru | [창세기 1:1] | [Бытие 1:1] |
| (창세기 1:1) | ru | (창세기 1:1) | (Бытие 1:1) |
| 예: [NKJV 창세기 1:1] | ru | напр. [NKJV 창세기 1:1] | напр. [Синодальный перевод Бытие 1:1] |
| 예: [NKJV][창세기 1:1] | ru | напр. [NKJV][창세기 1:1] | напр. [Синодальный перевод][Бытие 1:1] |
| 성경 이름 약어 사용 (창세기 → 창) | ru | Сокращённые названия книг (창세기 → 창) | Сокращённые названия книг (Бытие → Быт) |
| [창세기 1:1] | th | [창세기 1:1] | [ปฐมกาล 1:1] |
| (창세기 1:1) | th | (창세기 1:1) | (ปฐมกาล 1:1) |
| 예: [NKJV 창세기 1:1] | th | ตัวอย่าง: [NKJV 창세기 1:1] | ตัวอย่าง: [พระคัมภีร์ภาษาไทยฉบับ KJV ปฐมกาล 1:1] |
| 예: [NKJV][창세기 1:1] | th | ตัวอย่าง: [NKJV][창세기 1:1] | ตัวอย่าง: [พระคัมภีร์ภาษาไทยฉบับ KJV][ปฐมกาล 1:1] |
| 성경 이름 약어 사용 (창세기 → 창) | th | ใช้ชื่อเล่มแบบย่อ (창세기 → 창) | ใช้ชื่อเล่มแบบย่อ |
| [창세기 1:1] | vi | [창세기 1:1] | [Sáng Thế Ký 1:1] |
| (창세기 1:1) | vi | (창세기 1:1) | (Sáng Thế Ký 1:1) |
| 예: [NKJV 창세기 1:1] | vi | Ví dụ: [NKJV 창세기 1:1] | Ví dụ: [Kinh Thánh 1934 Sáng Thế Ký 1:1] |
| 예: [NKJV][창세기 1:1] | vi | Ví dụ: [NKJV][창세기 1:1] | Ví dụ: [Kinh Thánh 1934][Sáng Thế Ký 1:1] |
| 성경 이름 약어 사용 (창세기 → 창) | vi | Dùng tên sách viết tắt (창세기 → 창) | Dùng tên sách viết tắt |
| [창세기 1:1] | zh-Hans | [창세기 1:1] | [创世记 1:1] |
| (창세기 1:1) | zh-Hans | (창세기 1:1) | (创世记 1:1) |
| 예: [NKJV 창세기 1:1] | zh-Hans | 例：[NKJV 창세기 1:1] | 例：[官话和合译本（上帝版·简体） 创世记 1:1] |
| 예: [NKJV][창세기 1:1] | zh-Hans | 例：[NKJV][창세기 1:1] | 例：[官话和合译本（上帝版·简体）][创世记 1:1] |
| 성경 이름 약어 사용 (창세기 → 창) | zh-Hans | 使用书卷名缩写 (창세기 → 창) | 使用书卷名缩写 (创世记 → 创) |
| [창세기 1:1] | zh-Hant | [창세기 1:1] | [創世記 1:1] |
| (창세기 1:1) | zh-Hant | (창세기 1:1) | (創世記 1:1) |
| 예: [NKJV 창세기 1:1] | zh-Hant | 例：[NKJV 창세기 1:1] | 例：[官話和合譯本（上帝版） 創世記 1:1] |
| 예: [NKJV][창세기 1:1] | zh-Hant | 例：[NKJV][창세기 1:1] | 例：[官話和合譯本（上帝版）][創世記 1:1] |
| 성경 이름 약어 사용 (창세기 → 창) | zh-Hant | 使用書卷名縮寫 (창세기 → 창) | 使用書卷名縮寫 (創世記 → 創) |

#### (D) zh-Hant 項目 (copyfmt1) — 1개

| 키 | 언어 | 이전값 | 새값 |
|---|---|---|---|
| 인식하지 못한 항목: %@ | zh-Hant | 無法識別的專案：%@ | 無法識別的項目：%@ |
