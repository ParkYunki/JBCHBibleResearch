# versedoc1 — 연구문서·내 설교 언급 행: 1줄째 출처 제목, 그 아래 언급 내용 2줄

- 기준: Mac 작업 트리 현재 파일(커밋 cc2d58b + 로컬 수정). 고친 7개 파일 모두 Mac 파일을 그대로 받아 고쳤다(앞서 확인한 3개는 md5가 같고, mtime도 바뀌지 않았다).
- 고친 파일: `/home/claude/integ/versedoc1/JBCHBibleResearch/Views/Bible/` 아래 7개
  - `VerseRelatedSheet.swift`, `TranslationColumnView.swift`, `BibleReadingView.swift`, `BibleReadingViewModel.swift`,
    `VerseMentionListView.swift`, `VerseZoomView.swift`, `ChapterRelatedContentPanel.swift`
- diff: `/home/claude/integ/versedoc1.diff` (저장소 루트 기준 경로, Mac 현재 파일 기준 `git apply --check` 통과, 7 files +198 −14)
- 컨테이너에 Swift 툴체인이 없어 빌드는 하지 못했다. 정적 분석만 했다.
- relverse1(`Views/Search/*` 5개)과 겹치는 파일은 없다.

## 사용자 결정 (2026-10-29)

1. 한 출처의 여러 언급은 지금처럼 언급마다 한 행으로 둔다.
2. 절 번호 탭 화면, 확대보기 팝오버, 오른쪽 사이드 패널에 모두 같은 규칙을 적용한다.
3. 내 설교 행도 1줄째에 설교 제목을 넣는다. 제목이 비어 있으면 이름 줄을 뺀다.
4. 출처를 못 찾으면 내용 2줄만 보인다. "전체" 칩에서 4줄이 되는 것은 그대로 둔다.
5. (독립 검토 반영) B-1 렌더링 중 조회 제거, B-8 파일명은 가운데 말줄임, B-5 빈 설교 제목은 줄을 빼는 그대로 둔다. B-7은 변경 없음(스니펫은 언급 앞 30자·뒤 120자라 2줄이어도 언급 표현이 앞쪽에 보인다, `BibleReferenceExtractor.swift:277-283`).

## 1. 현재 구조 (변경 전)

| 화면 | 위치 | 연구문서 언급 행 | 내 설교 언급 행 | 이름 표시 |
|---|---|---|---|---|
| 절 번호 탭 → 절 관련 내용 (iPhone 시트, iPad·Mac 팝오버, 뷰 하나) | `VerseRelatedSheet` (`VerseRow`의 `.popover`) | ("전체"일 때 종류 라벨) + 내용 3줄 | 같음 | 없음 |
| 확대보기 → "관련 내용 N개" 팝오버 | `VerseMentionListView` (`VerseZoomView`만 사용) | 종류 라벨("연구 문서" + 아이콘) + 내용 3줄 | 같음 | 없음 |
| 오른쪽 사이드 패널(iPad 인스펙터, Mac 도구창) | `ChapterRelatedContentPanel.documentSection` / `sermonSection` | 배지 "본문에서 언급됨" (+ "N곳에서 언급됨") + 내용 2줄 | 같음 | 없음 (같은 섹션의 "이 장에 연결됨"/"말씀구절로 연결됨" 행에만 제목이 있다) |

- `VerseMention`에는 제목이 없고 `sourceId`(UUID 문자열)만 있다. 제목은 `resolveDocument(for:)`/`resolveSermon(for:)`로 출처를 찾아야 알 수 있다.
- 기존 표시 제목 규칙:
  - 연구문서: `SourceDocument.displayTitle` = 공백을 뺀 `customTitle`이 있으면 그것, 없으면 `originalFilename`
  - 설교: `sermon.title`. 비어 있으면 다른 화면은 "제목 없음"을 보이지만, 이번에는 사용자 결정에 따라 이름 줄을 뺀다.
- 세 화면 모두 언급 행에는 파일·설교 이름이 나오지 않아 중복은 없었다.

## 2. 변경

### 공통: 장 단위 제목 사전 (`BibleReadingViewModel`) — 검토 B-1 반영
- 새 저장 프로퍼티 `chapterMentionSourceTitles: [String: String]`(키 `sourceType|sourceId`)과 `rebuildMentionSourceTitles(documents:)`.
  `refreshRelatedContent()`에서 `rebuildVerseMentionsIndex()` 바로 다음에 채운다.
  - 연구문서: 같은 함수가 이미 전체 fetch한 `allDocuments`(`relatedDocuments` 계산용)에서 이 장 언급에 나온 문서만 골라 `displayTitle`을 넣는다. **추가 조회 0회.**
  - 설교: 이 장 언급에 나온 설교마다 기존 `resolveSermon(for:)`(id 조건 fetch)를 **한 번씩만** 부른다.
  - 공백을 지우고 빈 제목은 넣지 않는다(빈 설교 제목 → 이름 줄 없음, 검토 B-5는 사용자 결정대로 유지).
  - (2차 검토 B-2) 사전 키와 조회 키의 `sourceId`를 모두 `UUID(uuidString:)?.uuidString`으로 정규화해 대소문자 차이를 흡수한다. UUID로 읽히지 않는 문자열은 원래 값 그대로 쓴다.
  - (2차 검토 참고 4) 새 사전이 기존 사전과 같으면 대입하지 않는다. `@Observable` 때문에 불필요하게 다시 그려지는 것을 막는다.
- `mentionSourceTitle(for:)`는 이 사전을 **읽기만 한다**(조회 없음). 세 화면이 모두 이 함수 하나를 쓰므로 제목 원천이 같다.
- 시트·팝오버에 두었던 `@State` 캐시와 `onAppear` 로더는 지웠다. 그릴 때 사전을 바로 읽으므로 첫 프레임에 제목이 비는 일도 없다.

**택한 방법과 근거**
- 두 안(뷰모델 사전 / 패널 `@State` + `task(id:)`) 가운데 **뷰모델 사전**을 택했다.
  1. 렌더링 중 조회가 구조적으로 없다. 패널·시트·팝오버 모두 사전 조회(O(1))만 한다.
  2. 언급 목록 `chapterVerseMentions`와 같은 시점에 채운다. 그래서 "언급은 새것인데 제목은 옛것"인 어긋남이 없다.
     갱신 시점은 기존 신호를 그대로 쓴다: 진입(`onAppear`), 장·책 이동, 이력 이동, 원격 동기화(`remoteImportRevision`), 메모 시트 닫힘.
  3. 세 화면이 같은 원천을 써서 화면마다 제목이 다를 수 없다. 패널 `@State` 안이면 시트·팝오버에도 따로 캐시가 필요하다.
  4. 문서 쪽은 이미 하는 전체 fetch를 다시 써서 추가 비용이 없다.
- `#Predicate`의 `ids.contains(...)` 일괄 조회는 iOS 18에서 안전하다는 근거를 확인하지 못했다. 그래서 설교는 id별 개별 조회를 장 로드 때 한 번씩만 한다.
- 모델 객체(`SourceDocument`/`Sermon`)를 사전에 들고 그릴 때 속성을 읽는 방법도 생각했다. 하지만 삭제된 모델 인스턴스의 속성을 읽을 때 SwiftData가 어떻게 동작하는지 근거가 없어 문자열로 저장했다.
- 한계: 이 기기에서 성경 화면을 띄운 채 다른 창에서 문서·설교 이름을 바꾸면, 다음 갱신 신호(장 이동 등)까지 옛 이름이 보인다. 언급 목록 자체도 같은 갱신 시점을 따르므로 기존 동작과 같은 수준이다.

### 절 관련 내용 페이지 (`VerseRelatedSheet`)
- 새 인자 `mentionTitleProvider`. `TranslationColumnView` → `VerseRow` → 시트로 넘기고, `BibleReadingView` 두 곳(`phoneColumns`, `sideBySideColumns`)에서 `viewModel.mentionSourceTitle(for:)`를 넘긴다.
- 그릴 때 `mentionTitleProvider`(= 사전 조회)를 바로 부른다. 캐시·`onAppear` 로더는 없다.
- 연구문서·내 설교 행:
  - 1줄째: `Label(제목, "doc.text" 또는 "mic.fill")`, `.callout.weight(.semibold)`, 1줄. 말줄임은 **파일명 `.middle`, 설교 제목 `.tail`**(검토 B-8)
  - 그 아래: 내용 `.lineLimit(2)`
- 메모·말씀 요약 행은 그대로 3줄이다.
- VoiceOver 라벨은 "종류 제목 내용" 순서로 읽는다. 제목이 없으면 예전과 같다.

### 확대보기 팝오버 (`VerseMentionListView`, `VerseZoomView`)
- 새 인자 `titleProvider`(필수)를 받고, `VerseZoomView`가 `viewModel.mentionSourceTitle(for:)`를 넘긴다.
- 그릴 때 `titleProvider`를 바로 부른다(캐시 없음). 말줄임은 파일명 `.middle`, 설교 제목 `.tail`.
- 파일 머리 주석의 "사이드바도 공유한다"는 실제와 달라 고쳤다. 사이드 패널은 이 뷰를 쓰지 않는다.
- 연구문서·내 설교 행은 종류 라벨 줄(기존) 아래에 제목 1줄(아이콘 없음), 그 아래 내용 2줄이다.
  - 종류 라벨에 이미 같은 아이콘이 있어 제목 줄에는 아이콘을 붙이지 않았다.
  - 이 목록은 여러 종류가 섞여 나와서 종류 라벨이 꼭 필요하다. 절 관련 내용 페이지의 "전체" 칩과 같은 구성이다(4줄).
- 메모·말씀 요약 행은 그대로 3줄이다.

### 오른쪽 사이드 패널 (`ChapterRelatedContentPanel`)
- 언급 행에 배지 줄(기존) → 제목 1줄(새, `Label` + "doc.text"/"mic.fill", 파일명 `.middle`·설교 제목 `.tail`) → 내용 2줄(기존) 순서로 보인다.
- 아이콘은 같은 섹션의 "연결됨" 행이 쓰는 심볼과 같다.
- **"N곳에서 언급됨" 묶음 구조는 그대로 두었다.** 근거:
  - 사용자 결정 2번이 "구조는 유지하고 이름 줄만 맞춘다"이다.
  - 묶는 기준(`groupedByDisplayText`)은 지금 **화면 텍스트만** 본다. 출처는 보지 않는다. 그래서 서로 다른 문서가 글자까지 같은 내용으로 그 절을 언급하면 한 묶음이 된다.
  - 이때 대표 하나의 제목만 보이면 나머지 문서를 숨겨 잘못된 정보가 된다.
  - 그래서 묶음 기준은 바꾸지 않았다. 대신 `GroupedMention.isSingleSource`(묶인 언급이 모두 같은 `sourceId`인지)를 추가하고, **한 출처만 담은 묶음에만 제목 줄을 보인다.** 출처가 섞인 묶음은 예전처럼 제목 없이 보인다.
  - `sourceTitles(for:)`는 뷰모델 사전만 읽는다. 동기 스크롤로 자주 다시 그려도 SwiftData 조회가 없다(검토 B-1).

새 문자열이 없어 `Localizable.xcstrings`는 바꾸지 않았다.

## 3. 엣지 케이스

| 경우 | 결과 |
|---|---|
| 제목이 긺 | 1줄. 파일명은 가운데 말줄임(앞부분이 같은 파일명끼리 구분), 설교 제목은 끝 말줄임 (세 화면 공통) |
| 사용자 지정 제목 있음 / 없음 | 있으면 그 제목, 없으면 원본 파일명(확장자 포함) |
| 설교 제목이 비어 있거나 공백뿐 | 이름 줄 없이 내용 2줄 |
| 출처를 못 찾음(동기화 순서, 삭제 직후) | 이름 줄 없이 내용 2줄. 탭 동작은 예전과 같다 |
| 스니펫이 짧거나 비어 있음 | 짧으면 1줄로 끝나고, 비어 있으면 `searchText`를 보인다 |
| 한 출처가 여러 번 언급(시트·팝오버) | 언급마다 한 행이고 같은 제목이 반복된다. 조회는 출처당 1회 |
| 한 출처가 같은 텍스트로 여러 번 언급(사이드 패널) | 기존처럼 한 묶음 + "N곳에서 언급됨"이고, 제목이 보인다 |
| 다른 출처가 같은 텍스트로 언급(사이드 패널) | 기존처럼 한 묶음이고, 제목 줄은 없다 |
| 형식별 아이콘 | 앱에 없다. 기존 "doc.text"/"mic.fill"을 썼다 |
| VoiceOver | 시트는 명시 라벨에 제목을 넣었다. 확대보기 팝오버와 사이드 패널은 명시 라벨이 없어 화면 순서대로 읽힌다 |
| 다국어 | 제목은 사용자 데이터라 번역하지 않는다. `Label(String,…)`/`Text(String)`은 문자열표를 찾지 않는다 |
| 성경 화면을 띄운 채 이름을 바꿈 | 다음 `refreshRelatedContent`(장 이동, 진입, 원격 동기화, 메모 시트 닫힘) 때 반영된다. 언급 목록과 같은 갱신 시점이다 |
| 첫 프레임 | 사전을 바로 읽어 제목 줄이 처음부터 보인다 |
| 스니펫 길이 | 언급 앞 30자 + 뒤 120자라 2줄로 줄여도 언급 표현이 앞쪽에 보인다(검토 B-7, 변경 없음) |
| 장 로드 비용 | 문서는 추가 조회 0회, 설교는 이 장 언급에 나온 설교 수만큼 id 조회 1회씩(장 이동 때만) |

## 4. 확인 방법

1. iOS 18 시뮬레이터와 macOS 26으로 빌드한다.
   - 인자가 바뀐 곳: `VerseRelatedSheet` init, `VerseMentionListView` 멤버와이즈 init, `TranslationColumnView`/`VerseRow` 새 프로퍼티
2. 연구문서와 설교가 모두 언급하는 절을 연다.
   - 절 번호를 탭한다. "연구문서"·"내 설교" 칩은 3줄(제목 + 내용 2줄)이고, "전체" 칩은 종류 라벨이 붙어 4줄이다.
   - 확대보기에서 "관련 내용 N개"를 연다. 종류 라벨 + 제목 + 내용 2줄이 보여야 한다.
   - 그 절을 선택하고 사이드 패널(iPad 인스펙터, Mac 도구창)을 연다. 배지 + 제목 + 내용 2줄이 보여야 한다.
3. 문서에 사용자 지정 제목을 넣었다 지운다. 제목과 파일명이 바뀌어 보이는지 본다.
4. 제목 없는 설교가 이 절을 언급하게 한다. 세 화면 모두 이름 줄 없이 내용 2줄인지 본다.
5. 아주 긴 제목이 1줄 말줄임인지 본다(iPhone 세로 포함). 앞부분이 같은 두 파일(예: "2026 수련회 1강.pdf"/"2026 수련회 2강.pdf")이 가운데 말줄임으로 구분되는지, 긴 설교 제목은 끝 말줄임인지 본다.
6. 메모·말씀 요약 행이 예전 그대로인지 본다(시트·팝오버 3줄, 패널은 변경 없음).
7. 사이드 패널에서 한 문서가 같은 문장을 두 번 언급하면 "2곳에서 언급됨"과 제목이 보이는지 본다. 두 문서가 같은 문장을 언급하면 제목 없이 보이는지 본다.
8. VoiceOver로 시트의 연구문서·설교 행을 읽어 본다.
9. 다른 언어 화면에서 제목이 원문 그대로 나오는지 본다.
10. 행을 탭하면 예전처럼 문서 검색 창이나 설교 뷰어가 열리는지 본다.
11. 사이드 패널을 연 채로 성경 본문을 빠르게 스크롤한다. Instruments(SwiftData/Core Data fetch)에서 스크롤 중 `SourceDocument`·`Sermon` fetch가 생기지 않는지 본다.
12. 문서 화면에서 사용자 지정 제목을 바꾸고 성경 화면으로 돌아와 장을 옮긴다. 새 제목이 보이는지 본다.

## 5. 남은 일·확인 사항

- (B-1 한계, 이번에는 그대로 둠) 같은 기기에서 성경 화면을 띄운 채 문서·설교 이름을 바꾸면, 장 이동 등 다음 `refreshRelatedContent` 전까지 언급 행 제목에 반영되지 않는다. 고치려면 이름 저장 지점(`DocumentsViewModel.setCustomTitle`, `SermonEditorView` 저장)에서 성경 화면에 알릴 갱신 신호가 필요하다.

- 사이드 패널의 묶음 기준이 출처를 보지 않아, 서로 다른 문서가 한 행으로 합쳐지고 두 번째 문서로는 갈 수 없다. 이번에는 그대로 두었다. 묶음 키에 `sourceId`를 넣을지는 사용자가 결정할 일이다(코드 주석이 밝힌 의도는 "원본 문서가 같은 인용구를 반복하는 경우"다).
- 확대보기 팝오버를 종류 라벨 줄 없이 3줄로 맞출지(라벨 자리에 제목을 넣음)는 정하지 않았다. 지금은 시트의 "전체" 칩과 같은 4줄이다.
