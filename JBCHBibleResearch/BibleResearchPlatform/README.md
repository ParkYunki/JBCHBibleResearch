# BibleResearchModels — 데이터 모델 레이어 구현 노트

> 근거 문서: `bible-research-platform-schema.md`(2026-08-04), `bible-research-platform-screens.md`
> (2026-08-05, 6장 스키마 보강 제안), `bible-research-platform-review-addendum.md`(리뷰 결과).
> 이 문서는 세 원본 문서를 종합해 실제 SwiftData `@Model` 코드로 옮기며 내린 결정과,
> 아직 검증되지 않은 부분을 addendum과 같은 톤으로 정리합니다.

## Xcode 프로젝트에 연결하는 방법 (필수 — 파일을 옮기는 것만으로는 빌드에 포함되지 않음)

이 폴더는 `JBCHBibleResearch.xcodeproj`가 있는 프로젝트 루트에 로컬 Swift Package로
그대로 복사됐습니다. 실제 앱 타겟(`JBCHBibleResearch`, 현재 Models/Views/Services/
Resources를 가진 단일 타겟 구조로 확인됨)에서 쓰려면 Xcode에서 한 번 더 작업이
필요합니다:

1. Xcode에서 프로젝트를 열고 File → Add Package Dependencies… → **Add Local…**
2. 이 `BibleResearchPlatform` 폴더를 선택.
3. `JBCHBibleResearch` 앱 타겟의 "Frameworks, Libraries, and Embedded Content"에
   `BibleResearchModels` 라이브러리를 추가.
4. 앱 코드에서 `import BibleResearchModels` 후 `BibleResearchSchema.makeSharedModelContainer()`
   호출(컨테이너 식별자 기본값이 이미 실제 entitlements 값과 일치하도록 넣어뒀습니다 —
   아래 "발견한 사실" 참고).

## 프로젝트 폴더를 직접 보고 확인한 사실 (README 원안 작성 후 추가)

- `JBCHBibleResearch.entitlements`에 iCloud 컨테이너 식별자가 이미
  `iCloud.com.jbch.JBCHBibleResearch`로 고정돼 있었습니다. `BibleResearchSchema
  .defaultCloudKitContainerIdentifier`를 이 값으로 맞춰뒀고, `makeSharedModelContainer()`가
  기본으로 이 값을 씁니다(원안의 자리표시자를 대체).
- **[`version_code` 정책 확정, 2026-08-06]** 처음엔 `Resources/BibleDB.sqlite`에
  `version_code` 컬럼이 있는 걸 보고 "파일 하나에 여러 번역본이 함께 들어있다"고
  잘못 판단했으나, 실제 정책은 **번들 기본 테이블(번역본 1개, schema.md 1장 원안
  그대로 `version_code` 없음) vs 사용자 추가 번역본(여러 개 등록 가능, 파일에 따라
  `version_code`로 구분되는 여러 번역본이 함께 들어있을 수 있음)**으로 다릅니다.
  `BibleReferenceStore`가 파일별로 `version_code` 컬럼 존재 여부를 런타임에 감지해
  쿼리를 다르게 구성하도록 다시 작성했습니다 — 자세한 내용은 아래
  "`Resources/BibleDB.sqlite` 스키마 대조 + `version_code` 정책 확정" 절 참고.
- **[결정 확정, 2026-08-06]** macOS/iPadOS/iOS를 각각 별도 Xcode 프로젝트나 별도
  타겟으로 나누지 않고, 지금처럼 **단일 멀티플랫폼 타겟**(`JBCHBibleResearch`) 하나로
  계속 간다고 사용자가 확정했습니다. 이에 따라 schema.md 6장의 "iPhone 뷰어 전용은
  편집 화면을 타겟 멤버십에서 제외"는 **더 이상 유효한 구현 방법이 아닙니다** — 타겟이
  하나뿐이라 멤버십으로 뺄 화면이 없습니다. 대신 화면 레이어에서
  `#if os(iOS)`/`UIDevice.current.userInterfaceIdiom` 같은 런타임·조건부 컴파일
  분기로 편집 UI를 숨기는 방식으로 대체해야 합니다 — **화면 레이어(S1~S12) 구현 시
  이 방식을 전제로 진행합니다.**
- 데이터 레이어(이 패키지) 자체는 원래부터 타겟 구성과 무관하게 동작하도록 만들어서
  이번 결정으로 바뀌는 부분이 없습니다.

## 구현 범위

6장(데이터 모델) 자체를 시작점으로 삼되, 6장의 변경 사항 다수가 원본 schema.md의
기존 엔티티를 전제로 하므로(예: ChapterSummary 필드 변경, KeywordOccurrence의
keyword_id→tag_id) **전체 데이터 모델 레이어**를 구현했습니다.

| 파일 | 내용 | 대응 문서 섹션 |
|---|---|---|
| `Models/Tags.swift` | `Tag`, `MemoTag`, `TagRelation` | screens.md 6.3, addendum 1.2/1.3 |
| `Support/TagDeduplication.swift` | 태그 생성 시점 중복 차단 + 동기화 후 병합 | addendum 1.2/1.3 |
| `Models/UserContent.swift` | `MemoFolder`, `UserMemo`, `BookOutline`, `ChapterSummary`, `LectureNote`, `Comparison` | screens.md 6.1/6.2/6.5/6.6, addendum 1.4 |
| `Support/BookOutlineDeduplication.swift` | BookOutline 중복 생성 정리 + 충돌 표시 | addendum 1.2/1.4 |
| `Models/Documents.swift` | `ImageCategory`, `SourceDocument`, `DocumentText`, `ConvertedPDF`, `OCRResult`, `DocumentMarkdown`, `DocumentAnchor` | schema.md 3장, screens.md 6.4/6.3, 14장 |
| `Models/ReferenceIndex.swift` | `ThemeIndex`, `ThemeLink`, `KeywordOccurrence`, `PersonIndex`, `PlaceIndex`, `TimelineEvent` | schema.md 2장 |
| `Models/Embedding.swift` | `EmbeddingChunk` | schema.md 4장, screens.md 13.5 |
| `Models/TranslationRegistry.swift` | `TranslationRegistry`(CKAsset 동기화) | screens.md 6.7 |
| `Models/BibleCoordinates.swift` | `BibleChapterRef`/`BibleVerseRef` 값 타입 | schema.md 2장(좌표를 관계 대신 값으로) |
| `BibleReference/*` | `BibleVerse`/`Book`/`BibleReferenceStore`(SwiftData 밖, 정적 SQLite 읽기) | schema.md 1장 |
| `Schema/BibleResearchSchema.swift` | 전체 `Schema` 조립 + `ModelContainer` 팩토리 | schema.md 0장/6장 |

의도적으로 **구현하지 않은 것**: SwiftUI 화면(3장), AI 백엔드 연동(7장/14.6), TextKit2 ↔
HTML 왕복 변환기(6.9), hwp 뷰어/FFI 브릿지(7장). 이번 요청은 "6장 데이터 모델부터"였고,
이 파일들은 그 다음 단계입니다.

## CloudKit 제약 적용 (schema.md 8장 5번 "다음 단계 후보"에서 남겨뒀던 항목)

addendum이 Tag/BookOutline에 대해서만 지적했던 "`@Attribute(.unique)` + CloudKit 조합
불가" 문제를, 전체 모델에 대해 **일관되게** 적용했습니다.

- `@Attribute(.unique)`를 어디에도 쓰지 않았습니다.
- 모든 non-optional 저장 프로퍼티에 리터럴 기본값을 부여했습니다.
- to-one 관계는 전부 `Optional` 타입(`Type?`)입니다.
- to-many 관계는 전부 `Optional` 배열 타입(`[Type]? = []`)입니다. ~~기본값 `[]`만
  있으면 충분~~ **이 판단은 틀렸었습니다** — 실제로는 타입 자체가 Optional이어야
  하고, 이 차이는 컴파일이 아니라 런타임(`ModelContainer` 로드 시점)에만 CoreData
  134060 에러로 드러납니다. 아래 "🛠️ 런타임 오류 수정 완료" 절 참고.
- 관계마다 `inverse:`는 정확히 한쪽에서만 선언했습니다(양쪽에서 선언하면 SwiftData가
  같은 관계를 두 개로 오인할 수 있어, 의도적으로 한쪽만 선언 + 다른 쪽은 평범한
  프로퍼티로 남겼습니다).

## 원본 문서에 없던 결정 (근거와 함께 이번 구현에서 확정)

이 항목들은 원본 세 문서 어디에도 답이 없어서, 프로젝트 원칙("근거 없이 확정하지
않는다")에 따라 최소한으로 판단하고 아래에 근거를 남깁니다. 사용자 확인 전까지는
"임시 확정"으로 취급해 주세요.

1. **`ConverterUsed.pdfkitNative` 추가** (`Documents.swift`) — screens.md 14.2가
   "converter_used enum에 pdf 경로를 표시할 값이 없다"고 명시적으로 확인을
   요청해 둔 지점입니다. 값이 없으면 pdf 업로드 흐름 자체를 모델로 표현할 수 없어
   추가했습니다. **명칭 최종 확정은 여전히 필요합니다.**
2. **`EmbeddingChunk.translationCode`(옵셔널) 추가** (`Embedding.swift`) — 원본
   스키마는 `source_type=verse`일 때 어느 번역본의 본문을 임베딩했는지 표시할 필드가
   없었습니다. 번역본마다 문장이 달라 임베딩 벡터도 달라지므로 이 필드 없이는 검색
   결과의 출처를 구분할 수 없다고 판단해 추가했습니다.
3. **`MemoTag`의 실제 프로퍼티명 확정** (`Tags.swift`) — addendum 1.3은
   `reassignRelationships` 예시 코드에서 `memoTag.memoId`(원시 UUID)를 가정하며
   "실제 모델 프로퍼티명에 맞춰 조정하라"고 명시했습니다. 이 구현은 원시 UUID 대신
   `memo: UserMemo?` 관계를 직접 쓰기로 확정했고, `TagDeduplication.swift`의
   `reassignRelationships`도 그에 맞춰 다시 작성했습니다.
4. **`PlaceIndex.coordinates`를 `latitude`/`longitude: Double?`로 구체화** — 원본
   스키마의 `coordinates?`가 어떤 타입인지 명시돼 있지 않아, 특정 프레임워크(CoreLocation
   등)에 종속시키지 않는 가장 중립적인 형태를 택했습니다.
5. **`books.json` 로더의 Bundle 파라미터를 필수로 둠** (`BibleReferenceModels.swift`) —
   이 패키지는 아직 실제 66권 데이터(`books.json`)를 포함하지 않습니다. 리소스를 가진
   앱 타겟이 자신의 Bundle을 넘기도록 설계했습니다.
6. **모든 모델 타입/프로퍼티/init을 `public`으로 명시** — schema.md 0장의 전제("3개
   타겟이 동일 데이터 레이어 사용")를 지키려면 이 패키지를 import하는 macOS/iPadOS/iOS
   앱 타겟에서 실제로 타입을 쓸 수 있어야 합니다. Swift 기본 접근제어(internal)로
   두면 패키지 밖에서 `Tag`, `UserMemo` 등에 전혀 접근할 수 없어 애초에 "공유
   Swift Package" 요구사항을 만족하지 못하므로, 처음 작성 시 누락됐던 부분을
   전체 파일에 일괄 적용해 바로잡았습니다.

## ✅ Xcode 빌드 검증 완료 (2026-08-06, 사용자 확인)

`BibleResearchPlatform`을 로컬 패키지로 추가한 뒤 **Xcode 빌드 성공**을 확인했습니다.
이걸로 아래 항목들은 "미검증"에서 벗어났습니다:

- `Support/*.swift`의 `#Predicate` 옵셔널 `Date`/`Int` 비교 문법이 이 SwiftData
  버전에서 컴파일됩니다.
- `@Relationship`의 `inverse:` 한쪽만 선언하는 패턴, `public` 접근제어 전체 적용,
  `@Attribute(.externalStorage)` 사용 모두 구문 오류 없이 통과합니다.
- `BibleReferenceStore`의 SQLite3 C API 사용 + `Package.swift`의
  `linkedLibrary("sqlite3")` 링크 설정이 정상 동작합니다.

**주의**: "빌드 성공"은 Swift 컴파일·링크가 통과했다는 뜻이지 CloudKit 스키마 제약까지
통과했다는 뜻은 아니었습니다 — 실제로 아래 항목에서 걸렸습니다.

## 🛠️ 런타임 오류 수정 완료 (2026-08-06) — to-many 관계도 Optional 타입이어야 함

앱을 처음 실행(⌘R)했을 때 콘솔에 CoreData 134060 에러가 떴습니다:

```
NSLocalizedFailureReason = "CloudKit integration requires that all relationships
be optional, the following are not:
ImageCategory: sourceDocuments / MemoFolder: memos / SourceDocument: anchors,
convertedPDFs, documentTexts, markdownRevisions, ocrResults / Tag: documentAnchors,
keywordOccurrences, memoTags, relationsAsA, relationsAsB / ThemeIndex: links /
UserMemo: memoTags"
```

**원인**: 이전 구현이 "to-many 관계는 기본값 `[]`만 있으면 CloudKit 요구사항을
만족한다"고 잘못 판단했습니다(README 위쪽 "CloudKit 제약 적용" 절 참고). 실제로는
to-one뿐 아니라 **to-many 관계도 타입 자체가 `Optional`**이어야 합니다 — `[T] = []`는
컴파일은 통과하지만 CloudKit이 요구하는 "관계는 optional"이라는 스키마 규칙을
만족하지 못해 `ModelContainer` 로드 시점(런타임)에만 발견됩니다. 이건 컴파일러가
잡아줄 수 없는 종류의 오류라 Xcode 빌드 성공만으로는 걸러지지 않았습니다.

**수정**: 에러 메시지에 나열된 13개 관계 전부를 `[T] = []` → `[T]? = []`로 바꿨습니다
(`Tags.swift`, `UserContent.swift`, `Documents.swift`, `ReferenceIndex.swift`).
`TagDeduplication.swift`에서 이 배열들을 순회하던 코드도 `?? []`로 옵셔널 처리하도록
같이 고쳤습니다.

**✅ 검증 완료(2026-08-06)**: 재실행 후 콘솔에 "모델 컨테이너 생성 성공 (CloudKit
컨테이너: iCloud.com.jbch.JBCHBibleResearch)" 로그 확인. `ModelContainer`가 실제
CloudKit 컨테이너로 정상 로드됩니다 — 데이터 모델 레이어(6장)의 핵심 목표였던
"ModelContainer 로드 성공"이 이걸로 실증됐습니다.

- 남은 것: 실제 iCloud 계정으로 CloudKit에 레코드 타입이 정상적으로 **푸시**되는지
  (로컬 로드 성공과 원격 동기화 성공은 별개 — 예: 다른 기기/시뮬레이터에서 같은
  iCloud 계정으로 데이터가 보이는지로 확인 가능, 필수는 아니고 여유 있을 때).
- `Tests/BibleResearchModelsTests/BibleResearchSchemaTests.swift` 세 테스트 실행
  (Test Navigator ⌘6 또는 ⌘U)은 아직 확인 전.

## ✅ `Resources/BibleDB.sqlite` 스키마 대조 + `version_code` 정책 확정 (2026-08-06, 사용자 확인)

번들 기본 테이블의 실제 정의를 확인했습니다:

```sql
CREATE TABLE "BibleVerses" (
    "uid"       INTEGER,
    "book_id"   INTEGER NOT NULL,
    "chapter"   INTEGER NOT NULL,
    "verse"     INTEGER NOT NULL,
    "content"   TEXT NOT NULL,
    "paragraph" INTEGER,
    PRIMARY KEY("uid")
) WITHOUT ROWID;
```

**`version_code` 정책 확정**: 번들 기본 테이블은 번역본이 1개뿐이라 `version_code`
컬럼이 필요 없습니다(위 CREATE TABLE 그대로). 반면 **사용자가 추가로 등록하는
번역본은 여러 개일 수 있고, 그 파일에는 `version_code`로 구분되는 여러 번역본이
함께 들어있을 수 있습니다** — 즉 파일 종류에 따라 스키마가 다릅니다. 이에 맞춰
`BibleReferenceStore`가 파일을 열 때 `PRAGMA table_info`로 `version_code` 컬럼
존재 여부를 런타임에 감지해서, 있으면 쿼리에 포함하고 없으면 무시하도록 다시
작성했습니다(`hasVersionCodeColumn`). `BibleVerse.versionCode`도 그에 맞춰
`String?`(컬럼이 없는 파일에서는 nil)로 바꿨습니다. 호출부는 어떤 파일을 열든
동일한 API를 쓰면 됩니다 — 다만 `version_code`가 있는 파일에서 `versionCode`
파라미터 없이 조회하면 `.versionCodeRequired` 에러가 던져집니다(임의의 번역본이
섞여 나오는 걸 막기 위함).

번들 기본 테이블의 컬럼명·타입은 `BibleReferenceStore`/`BibleVerse`
(`BibleReferenceModels.swift`)가 원래 가정한 것과 정확히 일치합니다
(`uid`/`book_id`/`chapter`/`verse`/`content`/`paragraph`, `paragraph`만 nullable).
사용자 추가 번역본 쪽 실제 파일(들)은 아직 실물로 대조하지 못했습니다 —
`version_code` 컬럼의 실제 존재 여부·표기값은 그런 파일이 생기면 재확인이 필요합니다.

## ⚠️ 남은 확인/검증 필요 사항 (addendum 6장 원칙 승계)

- `Package.swift`의 `.macOS(.v15)`/`.iOS(.v18)` 최소 배포 버전은 넉넉히 잡은 추정치이며,
  실제 제품 정책에 따라 낮출 수 있습니다(SwiftData+CloudKit 최소 요구사항은 대략
  macOS 14/iOS 17).
- `TagDeduplication.deduplicateTags`/`BookOutlineDeduplication.deduplicateBookOutlines`를
  **언제 호출할지**(원격 변경 알림 수신 시? 앱 유휴 시?)는 이 데이터 레이어의 책임
  범위 밖으로 남겨뒀습니다 — 앱 레이어에서 결정해야 합니다.
- `SourceDocument.fileBookmark`의 멀티 디바이스 해석 가능 여부는 addendum 3장이
  이미 미확정으로 남긴 리스크이며, 이 구현도 그대로 미해결 상태로 둡니다(모델
  필드 자체는 `Data?`로 준비만 해뒀습니다).
- ~~`Resources/BibleDB.sqlite`의 실제 테이블/컬럼명 대조~~ — 완료(위 "스키마 불일치
  발견 및 수정" 참고). 다만 `version_code` 컬럼의 **실제 값**이 `TranslationRegistry
  .code`와 맞는 규칙인지는 아직 미확인.
- 화면 기획서(3장)의 각 화면이 이 모델들을 실제로 어떻게 쿼리하는지(FetchDescriptor,
  정렬, 페이지네이션 등)는 이번 범위에 포함하지 않았습니다.

## 다음 단계 제안

1. `BibleResearchSchemaTests`를 Xcode에서 한 번 실행(⌘U)해 in-memory
   `ModelContainer` 생성과 태그 중복 차단 로직이 실제로 동작하는지 확인.
2. `BibleResearchSchema.makeSharedModelContainer()`를 앱 코드에서 실제로 호출해보고
   실기기/시뮬레이터에서 CloudKit 스키마가 정상 초기화되는지 확인.
3. `BibleReferenceStore(filePath:).availableVersionCodes()`를 한 번 호출해
   `version_code`에 실제로 어떤 값이 들어있는지 확인(예: "GAE" 하나뿐인지, 여러
   번역본이 이미 들어있는지).
4. 화면 레이어(S1~S12) 구현 착수 — 이 모델들을 소비하는 쪽.

## [2026-08-06] 화면 레이어 시작 — 내비게이션 뼈대 + S1(성경 조회)

`BibleReferenceStore`에 `maxChapter(bookId:versionCode:)`를 추가했습니다(장 선택
그리드가 각 책의 실제 최대 장 번호를 임의로 가정하지 않고 조회할 수 있도록).
그 외 이번 항목은 전부 데이터 레이어(`BibleResearchPlatform` 패키지) 밖,
앱 타겟(`JBCHBibleResearch/`) 안의 새 코드입니다:

- `Resources/books.json` — 66권 표준 목록(정경 순서, 한글명, 영문명, 약칭).
  ⚠️ `nameOriginal`은 히브리어/헬라어 원어가 아니라 영문 표준명(Genesis 등)으로
  채웠습니다 — 원본 문서가 이 필드의 의미를 명시하지 않아, 검증하기 가장 쉽고
  틀릴 위험이 가장 적은 선택으로 영문명을 골랐습니다. 실제로 원어 표기가
  필요하면 이 파일만 교체하면 됩니다.
- `Services/TranslationBootstrap.swift` — 앱 최초 실행 시 `TranslationRegistry`에
  번들 번역본 레코드를 심어 넣습니다. ⚠️ `code: "KRV"`는 schema.md 1장의 "번들 제공
  KRV 스키마"라는 표현이 유일한 근거이며, 번들 파일이 실제로 어떤 번역본인지
  (개역한글/개역개정 등) 확정된 적이 없습니다 — `displayName`만 바꾸면 되므로
  큰 위험은 아니지만, 확인 필요.
- `Services/BooksProvider.swift` — `books.json`을 로드해 캐싱하고, "요한복음 3장"
  같은 자유 입력에서 책 이름을 접두 매칭으로 찾는 헬퍼를 제공합니다.
- `Views/Navigation/` — `RootView`(macOS/iPadOS→사이드바, iPhone→탭바 분기),
  `SidebarNavigationView`(`NavigationSplitView`, 폭 200~280, "태그 관계"는
  `WindowGroup(id: "tag-relations")`로 별도 창), `PhoneTabView`(5탭:
  메모/성경/문서·OCR/개요/더보기), `PlaceholderScreens`(S1 외 나머지 화면은
  전부 "곧 제공됩니다" 자리표시자).
- `Views/Bible/` — S1 구현:
  - `BibleReadingView`/`BibleReadingViewModel`: 책/장 선택, 번역본별
    `BibleReferenceStore` 캐시, macOS/iPadOS는 최대 3열 동시 표시(`HStack`),
    iPhone은 1열 + 스와이프(`TabView(.page)`).
  - `ScrollSyncCoordinator`/`TranslationColumnView`: screens.md 3장의 "중앙 기준
    스크롤 동기화"를 구현. 각 절 행이 `PreferenceKey`로 자기 중심 좌표를 보고하고,
    뷰포트 중앙에 가장 가까운 절을 리더가 브로드캐스트하면 팔로워들이
    `scrollTo(anchor: .center)`로 맞춥니다. 팔로워에 그 절이 없으면 "이전 절로
    대체"(원문서 명시 규칙)합니다. ⚠️ 원문서가 언급한 "±1 증분 확인" 성능
    최적화는 하지 않고 매번 전체 재계산합니다 — 한 장 최대 176절 규모에서는
    문제없다고 판단했지만, 실제 성능은 아직 실기기로 확인 못 했습니다.
  - `BookChapterPicker`/`TranslationPickerPopover`: 그리드 피커 + 텍스트 자유
    입력, 번역본 4개 이상 등록 시의 칩 선택 팝오버. ⚠️ 팝오버는 번들 번역본
    1개짜리 상태로만 만들어봤고, 실제 다중 등록 상태(S12 구현 후)에서 재검증
    필요.
- `ContentView.swift`가 이제 `RootView()`를 띄우고, 최초 진입 시
  `TranslationBootstrap.ensureBundledTranslationRegistered`를 호출합니다.
  `JBCHBibleResearchApp.swift`에 태그 관계용 `WindowGroup(id: "tag-relations")`와
  macOS 최소 창 크기(1000×700)를 추가했습니다.

### ⚠️ 사용자가 직접 해야 하는 작업
이 세션에는 Xcode/`.xcodeproj` 접근 권한이 없어(`.pbxproj`를 찾을 수 없음, 이
iCloud 폴더는 프로젝트 소스 그룹까지만 마운트돼 있음), 새로 추가된 파일들
(`Views/Bible/*`, `Views/Navigation/*`, `Services/*`, `Resources/books.json`)이
Xcode 타겟의 "Compile Sources"/"Copy Bundle Resources"에 자동으로 포함되지
않았습니다. Xcode에서 프로젝트 내비게이터로 이 폴더들을 열어보면 파일이 디스크에는
있지만 프로젝트에는 안 잡혀 있을 수 있습니다 — 그 경우 폴더를 우클릭 →
"Add Files to..."로 추가(반드시 "Copy items if needed" 해제, 대상 타겟 체크)해야
빌드에 포함됩니다.

### 컴파일 검증 관련
이 환경에는 Swift 툴체인이 없어(`swift`/`swiftc` 미설치) 오늘 작성한 코드를 직접
빌드해보지 못했습니다. 괄호/중괄호 균형 등 정적 점검과 API 시그니처 대조는
했고, 작성 중 `List(AppSection.allCases, selection:)` 초기화 구문이 `.tag()`
기반 선택과 맞지 않는 오버로드였던 것을 발견해 `List(selection:) { ForEach { ... } }`
형태로 고쳤습니다(자세한 이유는 `SidebarNavigationView.swift` 주석 참고). 그래도
Xcode 빌드(⌘B)로 한 번 확인이 필요합니다 — 지금까지 이 프로젝트의 모든 새 코드는
실제로 사용자가 Xcode에서 빌드해 알려준 오류를 근거로 고쳐왔으므로, 이번에도
같은 방식의 확인을 기대합니다.

## [2026-08-06] KoreanUtil 이식 — 초성 검색 + 66권 chapterCount

사용자가 이전에 만들어 배포했던 앱(`BibleSeminarPresentationForIOS`)의
`KoreanUtil.swift`를 업로드받아 검토한 뒤 두 가지를 그대로/거의 그대로 가져왔습니다:

1. **`Book.chapterCount` 추가**(`BibleReferenceModels.swift`, `books.json`) — 원본
   파일의 `BibleBook.all`에 있던 66권 장 수 데이터를 books.json에 그대로 옮겼습니다
   (합계 1189장 — 개신교 66권 성경의 잘 알려진 총 장 수와 일치, 교차 확인함).
   이전에는 장 선택 그리드가 "몇 장까지 있는지" 몰라 `BibleReferenceStore`에 매번
   `MAX(chapter)` 쿼리를 날리거나(방금 전 세션에서 그렇게 구현), 최악의 경우
   임의의 상한을 가정해야 했는데, 이 정적 데이터 덕분에 DB를 열 필요 없이 즉시 알
   수 있게 됐습니다. `BibleReferenceStore.maxChapter(bookId:)`는 지우지 않고
   남겨뒀습니다 — 나중에 이 정적 데이터가 실제 DB 내용과 어긋나는지 교차 검증하고
   싶을 때 쓸 수 있습니다.
2. **초성 검색**(`Services/KoreanUtil.swift`, `Services/Book+Search.swift`) — 원본의
   `KoreanUtil.extractChoseong`/`isChoseongOnly`와, "요"/"여"가 둘 다 초성 "ㅇ"으로
   뭉개져 오검색되던 걸 고친 `BibleBook.matches(query:)`의 위치별 비교 로직을 그대로
   이식했습니다. 이 로직 자체는 새로 검증하지 않고 실제 운영 이력을 신뢰했습니다.
   - `BookChapterPicker`의 책 그리드에 검색창을 추가해 "ㅇㅎㅂㅇ" 같은 초성 입력으로
     66권 목록을 바로 필터링할 수 있게 했습니다(원래는 66개 버튼이 그냥 다 나열돼
     있었음).
   - "요한복음 3장" 자유 입력 필드(`BooksProvider.matchBookPrefix`)도 초성 입력
     ("ㅇㅎㅂㅇ3장")을 인식하도록 확장했습니다.

`BibleReadingViewModel.maxChapter(for:)`는 더 이상 필요 없어져 제거했고,
`BookChapterPicker`는 `maxChapterProvider` 클로저 없이 `Book.chapterCount`를 직접
씁니다 — 코드가 단순해졌습니다.

## [2026-08-06] TranslationInfo 이식 — 다국어 책이름표(BookNameTable)

사용자가 업로드한 `TranslationInfo.swift`(이전 앱 `BibleSeminarPresentationForIOS`,
원래는 macOS BibleAutofill 프로젝트에서 이식된 것)를 검토했습니다. 배경 설명:
사용자 추가 번역본(user-added translation) SQLite 파일은 대부분 책 이름이 안 들어있고
book_id(정수)만 있어서, 그 번역본이 어느 언어인지에 맞는 책 이름을 보여줄 방법이
없었는데, 이 파일이 그 문제를 "책이름표(BookNameTable)를 번역본에 연결"하는
방식으로 풀어 둔 것이었습니다. 두 가지를 가져왔습니다:

1. **`Services/BookNameTable.swift`** — 영어/태국어/몽골어/네팔어/필리핀어(타갈로그)/
   스페인어/독일어/이탈리아어/일본어, 9개 언어의 66권 이름(정식명 + 약어) 내장
   데이터를 그대로 이식했습니다. ⚠️ 태국어·몽골어·일본어 등 비라틴 문자 데이터는
   손으로 옮겨 적을 때 오탈자가 생길 위험이 커서, 옮긴 뒤 원본과 문자열 리터럴을
   전부(950개) 기계적으로 대조해 완전히 일치하는 것까지 확인했습니다(유일한 차이는
   원본의 `bookNameTableListKey`(UserDefaults 키) — 이건 의도적으로 안 옮겼습니다,
   아래 참고). `TranslationImportError`도 함께 옮겨 뒀습니다 — 지금 당장 어디서
   던지진 않지만 S12(번역본 관리/가져오기)에서 쓸 것이라 미리 준비만 해 둔 것입니다.
2. **`TranslationRegistry.bookNameTableID: String?`** 필드 추가(`TranslationRegistry.swift`)
   — 원본 `TranslationInfo.bookNameTableID`와 같은 역할. `nil`이면(번들 번역본은
   항상 nil) 한글 기본 이름으로 표시합니다.
3. **`Services/BookNameTableProvider.swift`**(신규, 원본에는 없던 타입) — "이
   번역본이 가리키는 이름표로 이 책 이름을 어떻게 표시할지" 조회하는 로직을
   `BooksProvider`와 대칭되게 별도로 분리했습니다. 이름표가 없거나 그 안에 이름이
   비어 있으면 한글 기본 이름으로 자동 폴백합니다.

**⚠️ [원본과 의도적으로 다르게 한 부분]**
- 원본의 `TranslationInfo`(번역본 값 타입)는 새로 만들지 않았습니다 — 이 프로젝트는
  이미 SwiftData `TranslationRegistry`가 그 역할을 하고 있어서, 새 필드
  하나만 얹었습니다.
- 원본의 `bookNameTableListKey`("bible.bookNameTables", UserDefaults 저장 키)는
  가져오지 않았습니다 — 그 앱은 UserDefaults에 커스텀 이름표를 저장했지만, 이
  프로젝트는 이미 CloudKit 동기화 아키텍처가 있어서 "사용자가 새 이름표를 만들거나
  수정"하는 기능을 나중에 추가한다면 UserDefaults보다 SwiftData 모델(동기화 대상)로
  가는 게 더 맞다고 판단했습니다. 다만 그 기능 자체는 S12 범위라 이번엔 만들지
  않았습니다 — 지금은 내장 9종 중에서 고르는 것만 가능하고, 그 UI 자체도 아직
  없습니다(TranslationRegistry.bookNameTableID는 항상 nil로 시작).
- `nonisolated` 표시(원본이 겪은 실제 액터 격리 버그에 대한 방어)는 그대로
  유지했습니다 — 이 프로젝트가 같은 Xcode 빌드 설정(기본 액터 격리 = MainActor)을
  쓰는지 확인하지 못했지만, 순수 Codable 값 타입이라 해가 없고 원본이 이미 실전
  검증한 해법이라 유지하는 쪽을 택했습니다.

**S1 화면에 반영한 부분**: 다중 번역본 컬럼 헤더에 번역본 표시 이름 아래로 그 번역본
자신의 언어로 된 "책 장" 레이블을 작게 보여주도록 했습니다
(`BibleReadingViewModel.ColumnState.localizedBookChapterLabel`,
`TranslationColumnView`). 지금은 번들 KRV 하나만 등록돼 있어(bookNameTableID = nil)
항상 한글로만 보이지만, S12에서 사용자가 예를 들어 영어 번역본을 추가하고
bookNameTableID를 "lang.en"으로 연결하면 그 컬럼에는 "John 3"처럼 보이게 됩니다.

## [2026-08-06] 화면 레이어 계속 — S2/S3 내 메모 (목록 + 편집 + 자동저장)

사용자가 "화면레이어 작업 계속할 것"이라고 지시했고, 다음 화면 후보(S2/S3 메모,
S12 번역본 관리, S8/S9 개요, S10 태그 관계) 중 **S2/S3 내 메모**를 골랐다. 근거:
screens.md 3장(S2/S3), 6.2(메모 폴더)/6.3(태그)/6.5(서식 저장)/6.8(리치텍스트
서식 사양)/6.9(에디터 구현 방식), 12장(자동저장), 13장(새 메모 생성→입력→저장
전체 프로세스).

### 새 파일

- `Services/RichText/` — `MemoParagraphStyle`(문단 스타일 6종), `MemoRichTextAttributes`
  (커스텀 AttributedStringKey 3개: colorHex/fontFamily/isQuote),
  `MemoRichTextDocument`(문단=블록 배열, HTML 파싱/직렬화, content_text 추출),
  `HTMLEntity`(최소 엔티티 인코딩/디코딩), `Color+Hex`.
- `Views/Memo/RichTextBlockEditor.swift` — 6.8/6.9 편집기 UI.
- `Views/Memo/MemoHomeView.swift`/`MemoRowView.swift`/`MemoDetailView.swift` — 목록 +
  상세.
- `Services/MemoAutosaveController.swift` — 12장 자동저장(디바운스+flush+빈 메모 정리).
- `Services/LastBiblePositionTracker.swift` — 13.1의 "이번 세션 마지막 성경 위치".

### ⚠️ [6.9 대비 구현 방식 차이 — 가장 중요한 편차]

기획서 6.9는 **NSTextView(macOS)/UITextView(iOS)를 NSViewRepresentable/
UIViewRepresentable로 감싼 진짜 TextKit2 에디터** + `NSParagraphStyle`/`NSTextList`
기반 왕복 변환기를 "확정"으로 채택했다. 이 세션은 Xcode 컴파일 검증이 불가능한
환경이라, 사용자에게 먼저 물어봤고(AskUserQuestion으로 "SwiftUI AttributedString
에디터(추천)" vs "6.9 그대로(NSTextView/UITextView 커스텀 래퍼)"를 제시했으나
응답 스트림이 끊겨 명시적 답을 받지 못했다 — 이미 "추천"으로 제시해 둔 첫 번째
방향으로 진행했다) 다음과 같이 대체했다:

- **에디터**: 플랫폼별 `NSViewRepresentable`/`UIViewRepresentable` 대신 SwiftUI
  표준 `TextEditor(text: Binding<AttributedString>)` + **문단(블록) 배열** 모델.
  코드 하나로 macOS/iPadOS/iPhone을 모두 커버하고, 컴파일 신뢰도가 높은 API만
  썼다. `TextEditor`가 내부적으로 TextKit2 기반이라 "한글 IME 안정성" 요구사항
  자체는 만족한다고 판단했다.
- **문단 스타일**: `NSParagraphStyle` 대신 각 블록에 `MemoParagraphStyle` 열거형을
  붙이는 방식. 목록도 `NSTextList` 대신 블록 스타일(`.bullet`/`.numbered`)로 표현.
- **부분 선택 서식 없음**: 인라인 서식(굵게/기울임/밑줄/색상/폰트/인용)은 **문단
  전체 단위로만** 토글된다 — 한 문단 안에서 일부 단어만 굵게 하는 것은 이번
  구현 범위 밖이다. 이유: 부분 선택 서식을 하려면 `TextEditor(text:selection:)`
  + `AttributedTextSelection`(iOS17+/macOS14+)이 필요한데, 이 세션에서 정확한
  시그니처를 검증할 방법이 없어 더 확실한 문단 단위 토글로 범위를 좁혔다.
- **Enter로 문단 자동 분리 없음**: 새 문단은 "+" 버튼으로 명시적으로 추가한다
  (같은 이유 — 선택 영역 인지형 API를 안 쓰기로 한 결정의 연장선).
- **색상/폰트 왕복**: SwiftUI `Color`/`Font`는 값을 넣을 수는 있어도 이미 만들어진
  값에서 원래 hex/폰트 이름을 다시 안전하게 읽어낼 공개 API가 없다(불투명 타입) —
  그래서 커스텀 `AttributedStringKey`(`colorHex`/`fontFamily`, 순수 문자열)를
  "진짜 원본"으로 저장하고, 화면 렌더링용으로만 `Color`/`Font`를 만들어 병행
  적용했다. 저장되는 `content_html`의 태그 종류(`<h1>~<h3>/<p>/<ul>/<ol>/<li>/
  <strong>/<em>/<u>/<span style="color:...">/<span style="font-family:...">/
  <blockquote>`)는 6.8 사양과 동일하다 — **저장 형식은 기획서와 같고, 편집기
  내부 구현 메커니즘만 다르다.**
- **HTML 파서 범위 제한**: `MemoRichTextDocument.parse(html:)`는 범용 HTML 파서가
  아니라 이 타입 자신이 만든 형식만 정확히 되읽는 전용 파서다(정규식 기반 블록
  분리 + 직접 작성한 인라인 태그 토크나이저). NSAttributedString의 HTML
  임포터(`NSAttributedString(data:options:...)`)를 안 쓴 이유: 그 경로는
  굵게/기울임 판정을 폰트 디스크립터 트레이트로 돌려주는데, macOS(NSFont)/
  iOS(UIFont)가 이 부분만 서로 다른 API라 플랫폼 분기가 필요해진다 — 우리가 쓰는
  태그 집합이 아주 작고 고정돼 있어 직접 토큰화하는 게 더 단순했다.

### ⚠️ [9.1 대비 레이아웃 단순화]

원문서 목업은 [폴더/성경 트리 사이드바] | [메모 목록] | [메모 상세] 3단이고,
9.1은 그 폴더 트리를 앱 바깥쪽 메인 사이드바의 "내 메모" 하위 항목(전체·폴더별)
으로 넣으라고 적었다. 이미 완성돼 동작 확인이 필요한 `SidebarNavigationView`
구조를 다시 건드리는 위험을 피하려고:

- 폴더 선택은 별도 사이드바 컬럼이 아니라 **메모 목록 상단의 필터 메뉴**(전체/
  폴더별)로 구현했다.
- **"성경 책 → 장 트리"는 만들지 않았다.** 대신 각 메모 상세에서
  `BookChapterPicker`로 성경 좌표를 바로 바꿀 수 있고, 목록 자체는 최근 수정순
  정렬 + 텍스트 검색으로 대체했다. 책/장별로 메모를 찾아 들어가는 흐름이 실제로
  필요해지면 그때 사이드바 트리를 추가하는 게 낫다고 판단했다(과도한 선제 구현
  방지, addendum 원칙).
- macOS/iPadOS는 목록/상세를 `NavigationSplitView`가 아니라 **수동 HStack 2단**으로
  직접 배치했다(선택 상태는 로컬 `@State`) — 이미 쓰고 있는 바깥쪽
  `NavigationSplitView` 안에 또 하나를 중첩시키는 대신, 불확실한 API 조합을 피해
  가장 단순하고 확실한 방식을 택했다.

### 그 외 구현 메모

- **13.1(새 메모 좌표 기본값)**: `LastBiblePositionTracker`가 세션 동안의 마지막
  성경 위치를 메모리에만 들고 있고(`BibleReadingViewModel.selectBook/goToChapter`가
  갱신), 없으면 창세기 1장. S1에서 절을 우클릭(또는 롱프레스)하면 "메모 작성"
  컨텍스트 메뉴가 뜨고 정확한 (책,장,절)로 채워진 메모가 시트로 열린다
  (`BibleReadingView.createMemo(for:)`).
- **12장 저장 상태 표시**: "동기화됨/대기 중/동기화 중" 아이콘을 상세 화면 상단에
  뒀지만, ⚠️ 이건 **로컬 저장(ModelContext.save()) 완료 여부의 근사치**일 뿐 실제
  CloudKit 업로드 완료 추적이 아니다 — 진짜 CloudKit 동기화 이벤트 구독은 더 깊은
  통합이 필요해 범위 밖으로 남겼다.
- **13.3 이산적 액션**: 태그 추가/삭제, 폴더 변경은 디바운스 없이
  `MemoAutosaveController.saveImmediately()`로 즉시 저장 — 본문 입력만 1.5초
  디바운스.
- **13.4 빈 메모 정리**: 화면을 벗어날 때(`onDisappear`) `content_text`가 비어
  있고 태그도 없으면 삭제. 성경 좌표가 기본값에서 안 바뀐 것 자체는 판단 기준에
  넣지 않았다(사용자가 좌표는 그대로 두고 싶을 수 있어서).
- **AI 태그 제안(14.6)**: `FoundationModels`(온디바이스 AI) 연동이 필요해 이번
  범위에 없다 — S9(장 요약 AI)와 같은 시점에 함께 다루는 게 자연스럽다고 본다.
- **문서 뷰어 연계 컨텍스트 메뉴("관련 문서 보기")**: S6(문서 뷰어)이 아직 없어
  S1 절 컨텍스트 메뉴에 "메모 작성"만 넣고 이 항목은 뺐다.

### 검증 필요 (Xcode 빌드 필수)

이 세션엔 Swift 툴체인이 없어 오늘 작성한 코드도 직접 빌드해보지 못했다. 특히
`RichTextBlockEditor`/`MemoRichTextDocument`가 쓰는 `AttributedString`의 커스텀
`AttributedStringKey`/`AttributeScope`/`AttributeDynamicLookup` 조합, `Layout`
프로토콜 기반 `FlowLayoutHStack`, `.contextMenu`/`.sheet(item:)`/`@Bindable` on
SwiftData 모델 같은 비교적 최신 API들은 문서화된 표준 패턴을 따랐지만 실제
컴파일로 확인된 적은 없다 — ⌘B 결과를 알려주면 그걸 근거로 고치겠다. 새 파일들
(`Services/RichText/*`, `Services/MemoAutosaveController.swift`,
`Services/LastBiblePositionTracker.swift`, `Views/Memo/*`)도 Xcode 타겟에 아직
추가되지 않았을 수 있다 — 프로젝트 내비게이터에 안 보이면 "Add Files to..."로
추가해야 한다.

## 🛠️ Xcode 빌드 오류 수정 (2026-08-06) — `BibleReadingViewModel.swift` 초기화 2건

사용자가 실제 ⌘B 결과로 아래 오류를 보고해 수정했다.

1. **`Main actor-isolated static property 'shared' can not be referenced from a
   nonisolated context; this is an error in the Swift 6 language mode`**
   (`BibleReadingViewModel.swift:60:70`)
   원인: `init(..., booksProvider: BooksProvider = .shared, ...)`처럼 기본 인자
   값에서 곧바로 `BooksProvider.shared`(`@MainActor` 격리 정적 프로퍼티)를
   참조했다. 기본 인자 표현식은 이 타입(`BibleReadingViewModel`)이 `@MainActor`여도
   자동으로 격리되지 않는다 — 초기화 **본문**과 달리 인자 기본값 표현식 자체는
   nonisolated 컨텍스트에서 평가되기 때문(Swift 6 엄격 동시성 규칙). 수정: 파라미터를
   `booksProvider: BooksProvider? = nil`로 바꾸고, `@MainActor` 본문 안에서
   `booksProvider ?? .shared`로 대체했다.
2. **컴파일 자체가 불가능한 Xcode 에디터 placeholder 토큰 잔존**
   (`chapterCount: <#Int#>`, 같은 파일 63행) — `Book` 구조체에 `chapterCount`
   필드를 나중에 추가하면서(KoreanUtil 이식 작업, 위 8번 항목) 이 파일의
   `fallbackBook` 생성 호출부를 갱신하지 않아 남아 있던 문제로 보인다. `chapterCount:
   50`(창세기 실제 장 수, `books.json` 데이터와 일치)로 교체했다.

⚠️ 같은 패턴(`@MainActor` 싱글턴 `.shared`를 기본 인자 값으로 직접 참조)이 다른
곳(`BookNameTableProvider.shared`, `LastBiblePositionTracker.shared` 사용처)에도
있는지 grep으로 확인했고, 다른 곳에는 없었다 — 이 파일 한 곳뿐이었다.

## [2026-08-06] 화면 레이어 계속 — S8/S9 개요(책 단위 + 장 단위 AI 초안)

모델 레이어(`UserContent.swift`의 `BookOutline`/`ChapterSummary`, `Support/
BookOutlineDeduplication.swift`, `BibleResearchSchema.modelTypes` 등록)는 이전
세션에서 이미 만들어져 있었다 — 이번엔 화면(Views) 레이어만 새로 만들었다.

### 새 파일
- `Services/AutosaveController.swift` — 기존 `Services/MemoAutosaveController.swift`를
  리네임/일반화했다. 원래 파일 상단 주석에 "실제 두 번째 사용처가 생기면 그때
  제네릭화하라"고 적어 뒀는데, S8/S9가 그 두 번째 사용처라 지금 제네릭화했다
  (`deleteIfEmpty<T: PersistentModel>`). `MemoDetailView.swift`의 참조도 함께
  갱신했다. 근거 없는 선제적 리팩토링이 아니라 addendum이 요구한 "두 번째
  사용처가 생긴 시점"에 맞춘 변경이다.
- `BibleResearchPlatform/Sources/BibleResearchModels/Support/
  ChapterSummaryDeduplication.swift` — `BookOutlineDeduplication`과 동일한
  find-or-create 패턴. ⚠️ **BookOutline과 의도적으로 다른 점**: BookOutline은
  addendum 1.4가 명시적으로 "오프라인 두 기기가 같은 책에 각자 개요를 만들 수
  있다"는 문제를 `conflictingOutlineId` 필드로 풀었지만, `ChapterSummary`는
  schema.md/addendum 어디에도 이 처리가 요구되지 않아 충돌 필드를 추가하지
  않았다(근거 없는 스키마 확장 금지). 즉 ChapterSummary는 같은 세션 내 중복
  생성만 막고, 오프라인 멀티기기 중복은 아직 보호되지 않는다 — 파일 상단
  ⚠️ 주석에 그대로 남겨 뒀다. BookOutline과 동일 수준으로 보호할지는 제품 결정
  필요.
- `Services/AI/ChapterOutlineDraftService.swift` — S9 "AI로 초안 제안" 백엔드.
  `FoundationModels`(`SystemLanguageModel`/`LanguageModelSession`, iOS/macOS
  26+) 래퍼. **⚠️⚠️ 이 파일이 이번 세션에서 가장 불확실성이 높다** — Xcode가
  없어 FoundationModels API를 한 번도 컴파일해 본 적이 없다. `LanguageModelSession.
  GenerationError.exceededContextWindowSize`만은 사용자가 준 screens.md 9.9절
  원문에 정확한 이름으로 나와 있어 신뢰도가 높지만, `SystemLanguageModel.default.
  availability`, `LanguageModelSession()`, `session.respond(to:)`,
  `response.content`의 정확한 시그니처는 2025 WWDC 지식 기반 추정이다. `#if
  canImport(FoundationModels)` + `@available(iOS 26.0, macOS 26.0, *)` 이중
  가드로 감싸서, 프레임워크 자체가 없는 환경(Package.swift 최소 배포 버전은
  macOS(.v15)/iOS(.v18)로 26보다 훨씬 낮다)에서도 컴파일은 되고 "사용 불가"로
  조용히 폴백하게 만들었다 — 실제 빌드에서 오류가 나면 정확한 오류 메시지를
  알려주면 바로 고치겠다.
  - 1단계(사전 휴리스틱)의 "글자당 토큰 비율"(2.0)은 스펙 9.9절이 스스로
    "한글 기준 검증 안 됨"이라고 밝힌 값이라 임의로 보수적 추정치를 넣었다 —
    실기기에서 시편 119편 등으로 실측 후 보정 필요.
- `Views/Outline/OutlineViewModel.swift` — 선택된 책/장, `BookOutline`/
  `ChapterSummary`(find-or-create로 로드), AI 초안 미리보기 상태 관리.
  `BibleReadingViewModel`과 동일하게 `booksProvider: BooksProvider? = nil` →
  본문에서 `?? .shared` 패턴을 처음부터 적용했다(바로 위 항목에서 고친 버그를
  반복하지 않기 위해).
- `Views/Outline/OutlineView.swift` — S8(책 개요)/S9(장 개요) 화면. 저장/취소
  버튼 없이 자동저장(12장 원칙 그대로), BookOutline 충돌 배너(addendum 1.4),
  AI 초안 미리보기 → "편집기에 적용" 흐름(9.9절)을 구현했다.
  ⚠️ **레이아웃 확인 필요**: 원문서에 S8/S9의 ASCII 목업이 없어(프로즈 설명만
  있음), MemoDetailView와 같은 "피커 + 에디터 세로 배치" 관례를 그대로
  따랐다. 실제 화면에서 스크롤이 너무 길면 접기/탭 분리로 바꿀 수 있다.

### 배선
- `SidebarNavigationView.swift`/`PhoneTabView.swift`의 `.outline` 케이스를
  `OutlinePlaceholderView()` → `OutlineView()`로 교체.
  `PlaceholderScreens.swift`에서 이제 안 쓰는 `OutlinePlaceholderView`는
  MemosPlaceholderView 때와 같은 이유로 제거했다.

### ⚠️ 남은 범위 밖 항목
- "장 개요 작성 시 AI 초안 제안 받기" 설정 토글(8.x)은 설정 화면 자체가 아직
  없어 반영하지 못했다 — 지금은 기기가 지원하면 항상 버튼이 보인다. 설정
  화면이 생기면 그 토글 값과 AND로 묶어야 한다.
- `RichTextBlockEditor`/`MemoRichTextDocument`를 그대로 재사용했으므로, 그
  타입들의 기존 ⚠️(부분 선택 서식 v1 범위 밖 등)이 S8/S9 에디터에도 동일하게
  적용된다.
- 새 파일(`Views/Outline/*`, `Services/AI/*`, `Support/
  ChapterSummaryDeduplication.swift`)이 Xcode 타겟에 아직 추가되지 않았을 수
  있다 — 프로젝트 내비게이터에 안 보이면 "Add Files to..."로 추가해야 한다.

## [2026-08-06] 화면 레이어 계속 — S5/S6/S7 연구문서 업로드/뷰어/OCR

모델 레이어(`Documents.swift`의 `SourceDocument`/`DocumentText`/`ConvertedPDF`/
`OCRResult`/`DocumentMarkdown`/`DocumentAnchor`/`ImageCategory`)는 이전 세션에서
이미 만들어져 있었다 — 이번에도 화면(Views)+서비스 레이어만 새로 만들었다.
S1/S2·S3/S8·S9보다 훨씬 큰 두 가지 외부 의존성 문제가 있어, 무엇을 실제로
만들고 무엇을 스텁으로 남겼는지 먼저 정리한다.

### ⚠️⚠️ [가장 중요] hwp 관련 기능은 전부 스텁이다 — 추측으로 만들지 않았다

schema.md 7장/8장이 스스로 명시한 대로, hwp 지원에는 두 외부 자산이 필요하다:
- **`rhwp-native-ffi`**(Rust 크레이트, 텍스트 추출용) — 이 세션엔 Rust 툴체인도
  실제 크레이트 소스도 없어 컴파일/링크가 불가능하다.
- **`rhwp-studio`**(오픈소스 `postmelee/alhangeul-macos`가 쓰는 정적 웹 자산
  번들, 뷰어용) — 이 세션엔 그 실제 HTML/JS/wasm 파일이 없다.

schema.md 8장 "다음 단계 후보"가 이미 "Rust 환경에서 컴파일 확인", "rhwp-studio
번들 폴더를 리소스로 복사"를 **사용자가 직접 해야 할 다음 단계**로 명시해 뒀다 —
그래서 이번 구현은 이 두 지점을 추측으로 채우지 않고 정직한 빈 자리로
남겼다:
- `DocumentTextExtractionService.markHWPUnsupported`가 hwp/hwpx 파일을 즉시
  `conversionStatus = .failedNeedsManual`로 떨어뜨린다(모델이 이미 갖고 있던
  상태값을 그대로 활용 — 새 상태를 만들지 않았다).
- `DocumentViewerView.HWPWebView`는 앱 번들 안에서
  `rhwp-studio/index.html`을 찾고, 없으면 "hwp 뷰어 자산이 아직 추가되지
  않았습니다" 안내 화면을 보여준다. **실제 자산을 Xcode 프로젝트에
  추가하면(schema.md 7.1 방식 그대로) 이 파일만 자동으로 로드되기 시작한다** —
  코드 수정이 필요 없다.
- "N페이지로 스크롤" postMessage 브릿지(schema.md 7.3)도 만들지 않았다 —
  schema.md 7.4가 스스로 "아직 코드로 작성되지 않음"이라고 밝힌 항목이다.

### 새 파일
- `Services/Documents/DocumentUploadService.swift` — 14.1(업로드 접수).
  security-scoped bookmark 생성(⚠️ macOS/iOS 옵션 차이, 실기기 멀티세션
  검증 안 됨), 형식 판별, `storage_location_kind` 추정(⚠️ 경로 문자열 기반
  휴리스틱). `OriginalFormat`에 `.pages` 케이스가 애초에 없다는 걸 확인했다 —
  14.2의 "pages는 v1 범위 제외, PDF/Word로 내보내 업로드 안내" 결정과 일치해서
  모델을 건드리지 않고 피커에서 그냥 제외했다.
- `Services/Documents/DocumentTextExtractionService.swift` — 14.2 형식별 분기.
  **PDF(PDFKit)**와 **이미지 OCR(Vision `VNRecognizeTextRequest`)**는 검증된
  Apple 프레임워크라 신뢰도 높게 구현했다. **doc(구 워드)**는 스펙 원문이
  스스로 "iOS 지원 여부 확인 안 됨"이라고 밝힌 대로, macOS는
  `NSAttributedString(url:options:[.documentType: .docFormat])`로 시도하고
  iOS/iPadOS는 `#if os(macOS)` 밖에서 바로 실패 처리한다(`.docFormat`이
  AppKit 전용 상수라 iOS엔 대응 API 자체가 없다는 걸 확인했다). **hwp/hwpx**는
  위 항목 그대로 스텁.
  - `ConverterUsed`에 doc 전용 값이 없어 `pdfkitNative`를 추가했을 때와 같은
    이유로 가장 가까운 기존 값(`userPreconverted`)으로 근사했다 — 정확한
    명칭이 필요하면 제품 결정 필요.
- `Views/Documents/DocumentsViewModel.swift` + `DocumentsHomeView.swift`(S5) —
  업로드 3가지 진입점(툴바 버튼/드래그앤드롭/드롭존 클릭)이 모두
  `upload(urls:)` 하나를 공유. 아이폰은 `UIDevice.current.userInterfaceIdiom`
  런타임 분기로 hwp 선택 자체를 막고(RootView.swift와 같은 패턴, 별도 타겟이
  아니므로), 드래그앤드롭도 아이폰에서만 비활성화했다. 상태 배지(14.5 시맨틱
  색상), 이미지 분류 메뉴(6.4), 실패 문서 재시도를 구현했다.
- `Views/Documents/OCRReviewViewModel.swift` + `OCRReviewView.swift`(S7) —
  원본 이미지 좌/추출 텍스트 우(좁은 화면은 `ViewThatFits`로 세로 전환),
  `[저장]/[재시도]/[폐기]`. 저장을 눌러야만 `OCRResult.status → user_reviewed`
  + `DocumentText` 반영 + `index_status = indexed`(14.3 "자동 저장 없음"
  원칙). ⚠️ 14.3의 "대기열 방식, 저장 후 다음"과 달리 이 구현은 S5 목록에서
  검수 대기 문서를 하나씩 탭해 들어가는 방식이다 — 전용 큐 브라우저는 만들지
  않았다(기능적으로 동등하지만 UX가 다름, 파일 상단 ⚠️ 참고).
- `Views/Documents/DocumentViewerViewModel.swift` + `DocumentViewerView.swift`
  (S6) — "원본 보기"/"추출 텍스트" 탭 전환(스펙의 "S6에 추출 텍스트 패널
  필요" 신규 발견 항목 반영). PDF는 PDFKit 뷰(`PDFView`를
  NSViewRepresentable/UIViewRepresentable로 래핑), 이미지는 `Image`, hwp는
  위에서 설명한 스텁 셸, doc는 원본 탭 자체를 숨기고 추출 텍스트만 제공.

### 배선
- `SidebarNavigationView.swift`/`PhoneTabView.swift`의 `.documents` 케이스를
  `DocumentsPlaceholderView()` → `DocumentsHomeView()`로 교체.
  `PlaceholderScreens.swift`에서 이제 안 쓰는 `DocumentsPlaceholderView`는
  이전 두 번과 같은 이유로 제거했다.

### ⚠️ 남은 범위 밖 항목(모두 스펙 원문이 스스로 "확인 필요"라고 남긴 것들)
- 14.4 "성경 장절 자동 인식"(`DocumentAnchor` 자동 생성) — 스펙 자신이 "실제
  문서로 검증 전까지 확신할 수 없다"고 남긴 항목이라 이번 구현에서 만들지
  않았다. 다음 단계 후보.
- 14.6 "AI로 주요 단어 제안"(FoundationModels Guided Generation,
  `@Generable`/`@Guide`) — S6/S2·S3 공통 기능이라 범위가 커서 이번 라운드엔
  포함하지 않았다. `ChapterOutlineDraftService`와 같은 방식(2단계 컨텍스트
  방어, `#if canImport(FoundationModels)`)으로 별도 서비스를 만들면 된다.
- "pages" 형식은 위에서 설명한 대로 업로드 자체를 받지 않는다(v1 범위 제외
  확정 사항).
- 새 파일(`Services/Documents/*`, `Views/Documents/*`)이 Xcode 타겟에 아직
  추가되지 않았을 수 있다 — 프로젝트 내비게이터에 안 보이면 "Add Files
  to..."로 추가해야 한다.

## [2026-08-06] 화면 레이어 계속 — S10 태그 관계 시각화(별도 창)

모델 레이어(`Tags.swift`의 `Tag`/`MemoTag`/`TagRelation`)는 이미 있었다 — 이번에도
화면 레이어만 새로 만들었다. `TagRelationsPlaceholderView`가 실제 화면으로
교체된 것은 이번이 처음이 아니라(메모/개요/문서와 같은 패턴), `JBCHBibleResearchApp.swift`가
이미 갖고 있던 `WindowGroup(id: "tag-relations")`을 그대로 재사용했다.

### 새 파일
- `Views/TagRelations/TagGraphViewModel.swift` — 그래프 데이터 계산 + 물리
  시뮬레이션. **자동 추론 엣지**는 (1) 같은 `UserMemo`에 동시 등장한
  `MemoTag`(6.3 원문 그대로), (2) 같은 `SourceDocument`에
  `DocumentAnchor(anchorType: .keyword)`로 동시 등장한 태그(⚠️ 확장 해석 — 원문은
  메모 채널만 명시) 두 채널을 합산한다. **수동 엣지**는 `TagRelation` 그대로.
  ⚠️⚠️ force-directed 레이아웃(반발력 1/거리² + 스프링 + 구심력 + 감쇠)은 SwiftUI/Apple
  표준 API가 아니라 이 파일이 직접 짠 단순 물리 모델이다 — 실제 컴파일/성능
  미검증, 노드 수가 아주 많아지면(태그 수백 개) 매 프레임 O(n²) 반발력 계산이
  느려질 수 있다는 점도 미리 남겨 둔다. `#Predicate`로 `persistentModelID`를
  직접 비교하는 대신 전체를 가져와 Swift `first(where:)`로 거르는 방식을
  또 한 번 썼다(위 S8/S9 섹션에서 이미 같은 이유로 한 번 회피한 패턴).
- `Views/TagRelations/TagDrilldownView.swift` — "태그 클릭 → 3분류 드릴다운"
  (관련 메모/연구문서/OCR 이미지). 스펙이 "S10뿐 아니라 메모·문서 태그 칩
  클릭에서도 재사용"하라고 명시한 대로 독립 시트 뷰로 분리했다 —
  `MemoDetailView.swift`의 태그 칩(이름 부분 탭)에도 연결했다. ⚠️ "OCR
  이미지를 하이라이트와 함께 오픈"은 문서 뷰어(S6)를 그냥 여는 것까지만
  구현했다 — `anchor.bboxOrOffset`을 실제 이미지 좌표 오버레이로 그리는
  하이라이트 렌더링은 범위 밖으로 남겼다.
- `Views/TagRelations/TagRelationsView.swift`(S10 본체) — `Canvas`로 엣지(점선
  얇음=자동/실선 굵음=수동), `TimelineView(.animation)` + `onChange(of:
  timeline.date)`로 매 프레임 물리 시뮬레이션 진행, 노드는 실제 SwiftUI 뷰로
  얹어 `DragGesture`로 재배치·연결 생성을 받는다(다른 노드 위에 놓으면 근접
  판정으로 `TagRelation` 생성). ⚠️ 원문의 "iOS는 롱프레스+드래그"를 일반
  드래그로 단순화했다(경합하는 다른 제스처가 없어서). ⚠️ 실선(수동 엣지) 탭으로
  삭제하는 UI는 만들지 않았다 — Canvas로 그린 선은 히트테스트 대상이 아니라
  탭-선분 거리 계산 코드가 별도로 필요한데, 이번 범위에서는 만들지 않았다
  (`TagGraphViewModel.deleteManualEdge`는 이미 있으니 나중에 연결만 하면 된다).

### 배선
- `JBCHBibleResearchApp.swift`의 `WindowGroup(id: "tag-relations")` 내용을
  `TagRelationsPlaceholderView()` → `TagRelationsView()`로 교체.
- `PlaceholderScreens.swift`에서 `TagRelationsPlaceholderView`를 제거했다.
  아이폰 "더보기" 탭의 진입점은 스펙 "iOS는 전체화면 모달로 대응"에 맞춰
  `NavigationLink`(하위 화면 push) 대신 `.fullScreenCover`로 바꿨다 — macOS/
  iPadOS의 "별도 창"과 대등한 iPhone식 대응이라고 판단했다.

### ⚠️ 남은 범위 밖 항목
- 실선(수동 엣지) 탭 → 삭제 UI(위에서 설명).
- 엣지 자동 채산 성능(태그가 아주 많아질 때의 O(n²) 반발력 계산) — 검증 필요.
- `TagDrilldownView`의 메모 라벨은 메모에 제목이 없어(6.5) 본문 앞부분
  발췌로 대체했다 — 스펙 목업과 형태만 비슷하게 흉내낸 것이다.

## 🛠️ Xcode 빌드 오류 수정 (2026-08-06) — `fullScreenCover`는 macOS에 없음

`PlaceholderScreens.swift:82:10 'fullScreenCover(isPresented:onDismiss:content:)'
is unavailable in macOS`. 원인: `fullScreenCover`는 iOS/iPadOS 전용 SwiftUI API라
macOS엔 심볼 자체가 없다. `MorePlaceholderView`는 실제로는 `PhoneTabView`를 통해
아이폰에서만 쓰이지만, 이 프로젝트가 별도 타겟이 아니라 멀티플랫폼 단일
타겟이라(RootView.swift 참고) macOS 빌드에서도 이 파일 전체가 컴파일 대상이 된다
— 그래서 `#if os(iOS)`로 해당 모디파이어만 감쌌다. 같은 문제가 다른 곳에도 있는지
`fullScreenCover` grep으로 확인했고, 이 한 곳뿐이었다.

## [2026-08-06] 화면 레이어 계속 — 설정 화면(8장) + macOS 메뉴 바(11장)

이번 라운드는 새 모델을 추가하지 않았다 — 설정은 애초에 SwiftData가 아니라
`UserDefaults`(기기별 앱 사용 설정, 동기화 대상 아님)에 저장하는 게 맞다고
판단했고, 메뉴 바는 순수 화면/제어 레이어라 모델과 무관하다.

### 새 파일
- `Services/UserSettingsStore.swift` — `@MainActor @Observable` 싱글턴,
  `UserDefaults` 백엔드. `openLastScreenOnLaunch`/`lastSelectedSectionRawValue`
  (8.1), `colorSchemePreference`(8.6, `.system`은 `colorScheme: ColorScheme?`이
  `nil`), `isAIChapterDraftEnabled`(8.4, S9 AI 초안 버튼과 실제로 AND 연결됨 —
  OutlineViewModel 섹션 참고), `defaultTranslationCode`(8.3, S1 번역본 컬럼
  순서에 실제로 반영됨 — 아래 참고). ⚠️ CloudKit/`NSUbiquitousKeyValueStore`로
  동기화하지 않았다 — "이 기기에서 앱을 어떻게 쓸지"는 연구 데이터가 아니라고
  판단해서다(근거 없는 동기화 확장 금지 원칙).
- `Views/Commands/AppFocusedValues.swift` — 메뉴 커맨드가 "지금 보이는 화면"에
  액션을 보내는 통로. ⚠️⚠️ **의도적으로 폐기한 설계**: 처음엔
  `BooksProvider`/`LastBiblePositionTracker`와 같은 패턴으로 전역
  `AppNavigationState` 싱글턴을 쓰려다가, 구현 전에 "이 앱의 `WindowGroup`은
  '새 창' 기능으로 동시에 여러 개 열릴 수 있는데, 전역 싱글턴을 쓰면 한 창에서
  메뉴로 화면을 바꾸면 다른 창의 사이드바 선택도 같이 바뀌어 버린다"는 문제를
  스스로 발견해 `FocusedValues`(창/씬 단위로 스코프됨)로 바꿨다 — 코드를 쓰기
  전에 잡은 설계 오류라 별도 빌드 오류 수정 절 없이 여기 기록한다.
- `Views/Commands/AppCommands.swift` — 11장 메뉴 바 실체. File(새 메모 ⌘N/새
  폴더 ⇧⌘N/연구문서 업로드 ⌘O), View(사이드바 토글 ⌥⌘S/화면전환 ⌘1-5/태그관계
  ⇧⌘T/스크롤동기화 토글), Bible 메뉴(다음·이전 장 ⌘]/⌘[). 포커스된 화면이 해당
  액션을 지원하지 않으면(`@FocusedValue`가 nil이면) 버튼이 자동으로
  회색 처리된다. ⚠️ 이번 범위에 넣지 않은 메뉴 항목과 각각의 이유는 파일 상단
  주석에 정리해 뒀다(번역본 추가 — S12 없음, 인쇄 — 범위 밖, Format 메뉴 —
  에디터 쪽 FocusedValue 추가 배선 필요, "구절로 이동..." — 팝오버 상태 노출
  필요, Edit/Window/Help — SwiftUI 기본 제공 그대로 사용).
- `Views/Settings/SettingsView.swift` — 8장 macOS 표준 `TabView` 기반 설정
  창(8개 탭: 일반/동기화/번역본/AI/저장공간/모양/단축키/정보) + `SettingsHostView`
  (iPadOS 시트용 NavigationStack 래퍼). **탭별로 "실제 동작 vs UI만 있음"을
  분리해 뒀다**:
  - 실제 동작: 일반(시작 시 마지막 화면·기본 번역본), 동기화(`CKContainer
    .default().accountStatus`로 실제 iCloud 계정 상태 조회, 콜백을 `Task {
    @MainActor in }`로 명시적으로 메인 스레드로 되돌림 — CloudKit 콜백 스레드
    보장이 없어서), 번역본(등록된 `TranslationRegistry` 목록·삭제), AI
    (`ChapterOutlineDraftService.appleIntelligenceStatus` 배지 + 토글), 모양
    (`colorSchemePreference` 세그먼트), 정보(`Bundle.main.infoDictionary`
    버전/빌드 번호).
  - **UI만 있고 실제 동작은 없음(정직하게 표시)**: 동기화 탭의 "지금 동기화"
    버튼(실제로는 `modelContext.save()`만 호출 — 진짜 CloudKit 강제 푸시
    트리거가 아니다)과 "동기화 일시중지" 토글(로컬 `@State`만 바뀔 뿐 아무
    것도 멈추지 않는다), 저장공간 탭 전체(백엔드 저장 경로 설정 자체가 없음),
    모양 탭의 글자 크기 조절(반영할 곳이 아직 없음), 단축키 탭(현재 고정된
    12개 단축키를 보여주기만 함 — 재지정 불가, "다음 단계 후보"로 명시).
- `Services/AI/ChapterOutlineDraftService.swift`(기존 파일에 추가) —
  `AppleIntelligenceStatus`(`.available`/`.deviceUnsupported`/
  `.disabledInSettings`) 계산 프로퍼티. ⚠️ `SystemLanguageModel.Availability`의
  정확한 `UnavailableReason` 케이스 이름을 알 수 없어(라이브러리 진화로 비고정
  enum일 가능성), `String(describing:).lowercased().contains("enabled")`
  휴리스틱으로 "설정에서 꺼짐"과 "기기 미지원"을 구분했다 — 실제 빌드에서
  케이스 이름이 다르게 나오면 이 휴리스틱을 정확한 스위치문으로 바꿀 수 있다.
  raw value가 없는 enum이라 `Equatable`이 자동 합성되지 않는다는 점도 미리
  잡아 `: Equatable`을 명시했다(SettingsView의 `status != .available` 비교에
  필요).

### 기존 화면에 배선한 부분
- `SidebarNavigationView.swift` — 시작 화면을 `UserSettingsStore
  .openLastScreenOnLaunch`/`lastSelectedSectionRawValue`로 복원(8.1),
  선택 변경 시 저장. `.focusedSceneValue(\.selectSection)`/
  `\.toggleSidebar)`로 메뉴 액션을 받는다. iPadOS 전용(⚠️ 스펙 밖 보완)
  툴바 톱니바퀴 버튼 + 시트로 `SettingsHostView` 진입 — macOS는 ⌘,만 쓰고
  사이드바엔 두지 않는다는 8장 원칙 그대로, iPadOS엔 그 메뉴 자체가 없어서
  대체 진입점을 하나 뒀다.
- `MemoHomeView.swift`/`DocumentsHomeView.swift`/`BibleReadingView.swift` —
  각각 `.focusedSceneValue(\.newMemoAction/\.newFolderAction)`,
  `\.uploadDocumentAction)`, `\.nextChapterAction/\.previousChapterAction/
  \.scrollSyncEnabled)`를 노출해 메뉴 커맨드가 실제로 그 화면의 기존 함수를
  호출하도록 연결했다 — 새 로직을 만들지 않고 이미 있던 함수(`createNewMemo()`,
  `viewModel.nextChapter()` 등)를 그대로 재사용했다.
- `BibleReadingViewModel.swift` — `loadAvailableTranslations()`가
  `UserSettingsStore.defaultTranslationCode`를 목록 맨 앞으로 재정렬한 뒤
  `prefix(maxColumns)`를 적용하도록 바뀌었다(8.3을 S1에 실제로 반영).
- `OutlineViewModel.swift` — `isAIDraftAvailable`이
  `ChapterOutlineDraftService.isDraftAvailable &&
  UserSettingsStore.isAIChapterDraftEnabled`로, S8/S9 섹션에 남겨 뒀던
  TODO("설정 화면이 생기면 그 토글 값과 AND로 묶어야 한다")를 닫았다.
- `RootView.swift` — `.preferredColorScheme(UserSettingsStore.shared
  .colorSchemePreference.colorScheme)`을 최상위에 추가(8.6). `@Observable`
  프로퍼티를 `body` 안에서 직접 읽기만 해도 자동 추적되는 패턴(이전 라운드에서
  이미 여러 번 쓴 것과 동일)이라 별도 `@State`/`@Bindable` 래핑이 필요 없었다.
- `PlaceholderScreens.swift` — `SettingsPlaceholderView` 제거,
  `MorePlaceholderView`의 설정 항목이 `SettingsView()`로 직접 연결.
- `JBCHBibleResearchApp.swift` — 메인 `WindowGroup`에 `.commands {
  AppCommands() }` 추가. macOS 전용(`#if os(macOS)`) `Settings { SettingsView()
  }` Scene을 새로 추가하고 `.windowResizability(.contentSize)`로 8장의
  "고정 크기, 리사이즈 불가" 요구를 반영했다. ⚠️ `Settings`는 iOS SDK에
  타입 자체가 없어(`canImport`가 아니라 `os(macOS)`로 가드해야 하는 이유) 이
  Scene은 macOS 빌드에서만 존재한다 — iPadOS/iPhone은 위에서 설명한 시트/
  NavigationLink 진입점으로 대체됐다.

### ⚠️ 남은 범위 밖 항목
- Format 메뉴/서식 단축키, Bible "구절로 이동...", 저장공간 탭 백엔드,
  모양 탭 글자 크기, 단축키 재지정 — 전부 위에서 이유와 함께 표시했다.
- 새 파일(`Services/UserSettingsStore.swift`, `Views/Commands/*`,
  `Views/Settings/*`)이 Xcode 타겟에 아직 추가되지 않았을 수 있다 — 프로젝트
  내비게이터에 안 보이면 "Add Files to..."로 추가해야 한다.
- 이번 라운드는 Swift 툴체인이 없어 직접 빌드해보지 못했다 — 괄호/중괄호
  균형 점검만 했다. ⌘B 결과를 알려주면 그걸 근거로 고치겠다.

## [2026-08-07] 화면 레이어 계속 — S11 통합 검색 / 의미검색(RAG)

`EmbeddingChunk`(schema.md 4장) 모델 자체는 이미 있었다 — 이번엔 그 벡터를 실제로
만들어 채우는 파이프라인과 검색 화면을 처음으로 구현했다. 이 라운드가 지금까지
중 가장 큰 미확정 지점을 갖고 있다: **임베딩 벡터를 무엇으로 생성할지가 원본
세 문서 어디에도 없다.**

### ⚠️⚠️ [가장 중요한 결정] 임베딩 생성 방식 — `NLContextualEmbedding` 선택 근거

schema.md 4장은 검색 단계만 "Swift + Accelerate(vDSP)로 brute-force 코사인
유사도"라고 확정했고, 벡터를 어떻게 만들지는 명시하지 않았다. 추측 대신 소거법으로
좁혔다: FoundationModels(S9가 이미 씀)는 텍스트 생성 전용이라 임베딩 API가 없고,
외부 네트워크 임베딩 API는 schema.md 0장의 "온디바이스" 전제와 어긋난다. 남는
유일한 Apple 온디바이스 문장 임베딩 API가 NaturalLanguage 프레임워크의
`NLContextualEmbedding`(WWDC23, iOS 17+/macOS 14+ — 이 프로젝트 최소 배포 버전보다
낮아 FoundationModels처럼 이중 `@available` 가드가 필요 없다)이라 이걸 택했다
(`Services/Search/EmbeddingService.swift`).

**⚠️⚠️ 가장 큰 미확인 리스크**: `NLContextualEmbedding`이 한국어를 실제로
지원하는지 이 세션은 확신할 수 없다 — 이 앱 콘텐츠(성경/메모/연구문서)는 거의
전부 한국어다. 추측하지 않고 `NLContextualEmbedding(language: .korean)`이 실제로
nil을 반환하는지 런타임에 직접 확인하도록 만들었다 — nil이면(또는 자산 다운로드
실패면) 의미검색만 "이 기기에서 사용할 수 없음"으로 정직하게 비활성화하고
키워드 검색은 그대로 동작한다(`EmbeddingService.Availability`,
FoundationModels 가용성 체크와 같은 패턴). **실제로 한국어를 지원하는지는 Xcode
실기기 테스트로만 확인 가능하다.**

### 새 파일
- `BibleReferenceStore.swift`(기존 파일에 추가) — `searchVerses(query:versionCode:limit:)`.
  `content LIKE '%query%'` 순수 SQL LIKE 검색(schema.md가 키워드 검색 방식 자체는
  명시하지 않아 가장 단순한 방법을 골랐다). LIKE 와일드카드(`%`/`_`) 이스케이프는
  하지 않았다 — 검색 UI 특성상 위험이 크지 않다고 판단.
- `Services/Search/VectorCoding.swift` — `EmbeddingChunk.embeddingVector`(Data)
  ↔ `[Float]` 변환. 패키지(BibleResearchModels)가 아니라 앱 레이어에 뒀다 —
  패키지는 "Float32 배열을 Data로 저장한다"는 스키마 규칙만 알면 되고, 실제
  생성/해석 알고리즘은 앱 레이어 책임으로 분리했다.
- `Services/Search/EmbeddingService.swift` — 위에서 설명한 임베딩 생성
  (`NLContextualEmbedding`, 토큰 벡터 평균 풀링) + Accelerate(vDSP) 코사인
  유사도(schema.md 4장 확정 방식 그대로).
- `Services/Search/EmbeddingIndexingService.swift` — `EmbeddingChunk` 실제
  생성/갱신(upsert) 로직. **⚠️ [13.5 대비 단순화]** 원문은 "메모 저장 시점엔
  재인덱싱 필요로 표시만 해두고 앱 유휴 시점에 백그라운드에서 재계산"을
  권장했지만, 이 구현은 더티 플래그·유휴 스케줄러 인프라를 새로 만드는 대신
  **S11 화면 진입 시마다 메모/문서 전체를 다시 스캔하되 실제로 바뀐 것만
  재계산**(chunkText 비교)하는 방식으로 단순화했다 — 메모/문서 규모(수백~수천
  건)에서는 이 정도로 충분하다고 판단했다(오버엔지니어링 방지 원칙). **성경
  전체는 규모가 달라**(66권 1,189장) 화면 진입 시 자동 실행하지 않고, 사용자가
  "성경 전체 장 단위 색인 만들기" 버튼을 눌러야만 시작되는 별도 함수로
  분리했다 — schema.md 4장이 스스로 경고한 "수만~10만 청크 규모 성능" 문제를
  1,189개(장 단위)로 줄이는 선택이기도 하다.
  - **⚠️ 청크 단위 결정(원본에 없던 구현 결정)**: `EmbeddingChunk.verseRef`는
    절 하나만 표현하지만, 절 단위로 성경 전체(약 31,000절)를 임베딩하면 이번
    세션에서 전혀 검증할 수 없는 규모다. 그래서 **장 단위**로 청크를 묶었다
    (한 장의 모든 절을 이어붙인 텍스트 = 청크 하나), `verseRef.verse`엔 실존하지
    않는 `0`을 "장 전체"를 뜻하는 센티널 값으로 넣었다. 검색 결과는 정확한 절이
    아니라 "그 내용을 포함할 가능성이 있는 장"을 가리킨다 — 절 단위 정밀도가
    필요해지면 청크 설계를 다시 해야 한다(다음 단계 후보).
  - 연구문서는 페이지 단위로 청크를 묶었다(`DocumentText`가 페이지·줄 단위로
    저장되므로, 같은 페이지의 줄을 이어붙여 청크 하나).
- `Views/Search/SearchViewModel.swift`/`SearchView.swift`(S11 본체) — 검색어
  350ms 디바운스, `[키워드 검색|의미검색(AI)]` 세그먼트 토글(원문 목업 그대로),
  성경구절/내 메모/연구문서 3분류 `Section`. 의미검색 결과에는 코사인 유사도를
  `%`로 표시했다. **⚠️ 유사도 임계값(0.3)은 스펙에 근거가 없는 임의 지정** —
  실측 후 조정 필요.

### 기존 화면에 배선한 부분
- `Views/Bible/BibleReadingView.swift` — `initialBook`/`initialChapter`(기본
  nil/1, 기존 호출부 동작 그대로 유지) 옵셔널 파라미터를 추가해, 검색 결과에서
  구절을 탭하면 그 책/장으로 바로 열리도록 했다.
- `SidebarNavigationView.swift`의 `.search` 케이스를 `UnifiedSearchPlaceholderView()`
  → `SearchView()`로 교체. `PlaceholderScreens.swift`에서 이제 안 쓰는
  `UnifiedSearchPlaceholderView`는 이전 다섯 번과 같은 이유로 제거했다.
- **⚠️ [IA 대비 보완]** screens.md 1장은 iPhone 탭바를 5개(메모/성경/문서·OCR/
  개요/더보기)로만 명시해 "통합 검색"이 탭 목록에 없다. 하지만 2장 화면
  총괄표는 S11의 iOS 접근 수준을 macOS/iPadOS와 "동일"로 명시했다 — 이미 같은
  모순을 가진 S12(번역본 관리)가 "더보기"에 들어가 있는 선례를 따라, 통합
  검색도 `MorePlaceholderView`(더보기)에 추가했다.

### ⚠️ 남은 범위 밖 항목
- 여러 번역본 동시 의미검색 색인 — 등록된 번역본 중 첫 번째(보통 번들 KRV)만
  색인한다. S12(번역본 관리) 구현 후 다중 등록 상태에서 정책을 다시 정해야 한다.
  키워드 검색(구절)은 등록된 모든 번역본을 검색해 좌표 기준으로 중복 제거한다 —
  키워드/의미검색의 번역본 범위가 서로 다르다는 점에 유의.
  - `.filter { $0.indexStatus == .indexed }`처럼 String rawValue enum 등호 비교를
  #Predicate 안에서 쓰는 대신 전체를 가져와 Swift에서 걸렀다(이 프로젝트가
  반복적으로 써 온 안전한 패턴).
- 검색 결과 하이라이팅(매치된 부분 강조) — 앞뒤 문맥만 잘라 보여줄 뿐 실제
  텍스트 강조는 하지 않았다.
- 새 파일(`Services/Search/*`, `Views/Search/*`)이 Xcode 타겟에 아직 추가되지
  않았을 수 있다 — 프로젝트 내비게이터에 안 보이면 "Add Files to..."로
  추가해야 한다.
- 이번 라운드도 Swift 툴체인이 없어 직접 빌드해보지 못했다 — 특히
  `NLContextualEmbedding`의 정확한 시그니처(`embeddingResult(for:language:)`,
  `enumerateTokenVectors(in:_:)`)는 문서화된 API 형태를 근거로 작성했지만 실제
  컴파일로 확인된 적이 없다. ⌘B 결과를 알려주면 그걸 근거로 고치겠다.

## [2026-08-07] 화면 레이어 계속 — S12 번역본 관리 (마지막 남은 플레이스홀더)

`PlaceholderScreens.swift`에 남아 있던 마지막 플레이스홀더(`TranslationManagementPlaceholderView`)를
실제 화면으로 교체했다 — 이걸로 스크린샷/내비게이션 뼈대 단계에서 자리만 잡아
뒀던 화면(S1~S12) 전체가 최소 한 번씩은 실제 구현으로 대체됐다.

### ⚠️⚠️ [가장 중요한 전제] screens.md S12 원문을 이 세션에서 볼 수 없었다

이전 라운드들과 달리 이번 세션에는 `bible-research-platform-screens.md` 원본
파일 자체가 없었다(작업폴더에 README.md만 있고, 프로젝트 지식에도 다른 두
문서가 없었다). 그래서 S12의 실제 레이아웃·필드·문구는 원문을 본 것이 아니라,
**이미 구현된 다른 파일들이 남겨 둔 단서를 근거로 역으로 추론**한 것이다:

- `TranslationRegistry`(모델, 6.7 근거 주석) — code/displayName/isBundled/
  isUserAdded/licenseType/sqliteFileReference/sqliteData(`.externalStorage`)/
  bookNameTableID 필드 구성.
- `Services/BookNameTable.swift`의 `TranslationImportError`(이전 앱에서 미리
  옮겨만 두고 "S12에서 쓸 것"이라고 적어 둔 대기 중 타입) — `fileNotReadable`/
  `invalidSchema`/`bookNumberingMismatch` 세 케이스가 이미 있다는 사실에서
  "파일 검증 → 장 수 대조" 흐름이 있어야 한다고 추론했다.
- `BibleReferenceStore.hasVersionCodeColumn`/`availableVersionCodes()` — 한
  파일에 여러 번역본이 섞여 있을 수 있다는 정책(README 위쪽 "`version_code`
  정책 확정" 절)에서 "가져오기 시 코드 선택 UI가 필요하다"고 추론했다.
- `Views/Settings/SettingsView.swift`의 `TranslationsSettingsTab`(8.3) — 이미
  목록+삭제는 동작했고 "번역본 추가..." 버튼만 "S12가 아직 구현되지 않아
  비활성화"로 남아 있었다.

**실제 S12 화면 목업(레이아웃, 정확한 문구, 버튼 배치)과 대조된 적은 없다** —
사용자가 원문을 갖고 있다면 이 라운드의 UI를 다시 검토해야 한다.

### 새 파일

- `Services/Translations/TranslationFileMaterializer.swift` — 6.7이 이미 요구해
  뒀지만 지금까지 아무도 실제로 필요하지 않았던 로직(번들 하나만 쓰던 동안은
  `sqliteData`가 항상 nil이라 문제가 드러나지 않았다). `TranslationRegistry
  .sqliteFileReference`가 이 기기에 실제로 존재하는 파일을 가리키는지 확인하고,
  아니면(다른 기기에서 CloudKit으로 막 동기화돼 `sqliteData`만 도착한 상태)
  Application Support/Translations에 로컬 사본을 써낸 뒤 필드를 갱신한다.
  ⚠️ 실제 다중 기기 CloudKit 동기화는 이 세션에서 검증 불가 — "로컬 파일이 없고
  sqliteData는 있다"는 조건만으로 판단하는 로직이 실기기에서도 맞는지 확인
  필요.
- `Services/Translations/TranslationImportService.swift` — `validate(fileURL:)`
  (파일이 열리는지, `BibleVerses` 스키마인지, 66권 장 수가 books.json
  `chapterCount`와 맞는지 대조) + `importTranslation(...)`(코드 중복 검사 →
  로컬 사본 작성 → `TranslationRegistry` 생성/저장). 장 수 불일치는 import를
  막지 않는다 — 표준과 다른 정경 순서를 쓰는 실제 번역본이 있을 수 있어
  최종 판단은 사용자에게 맡겼다(경고만 표시).
- `Views/Translations/TranslationImportSheet.swift` — "추가" 공용 시트.
  `.fileImporter`로 sqlite/sqlite3/db 확장자 선택(표준 UTType이 없어
  DocumentUploadService의 hwp/hwpx와 같은 방식으로 직접 선언) → 검증 결과
  표시(버전 코드 선택, 장 수 불일치 경고) → 코드/표시이름/라이선스/책이름표
  언어 입력 → 가져오기. `TranslationManagementView`와 설정(8.3) 탭이 이 시트
  하나를 공유한다.
- `Views/Translations/TranslationManagementViewModel.swift`/
  `TranslationManagementView.swift`(S12 본체) — 목록(번들+사용자 추가),
  materialize 실패 시 "동기화 대기 중" 경고 표시, 책이름표 언어 인라인 변경
  (Picker), 스와이프 삭제(번들 제외), 툴바 "추가" → 시트.

### 기존 파일에 반영한 부분

- `Services/BookNameTable.swift` — `TranslationImportError`에 `duplicateCode`/
  `missingRequiredField` 두 케이스 추가(원본에 없던 케이스, import 서비스가
  실제로 검사해야 하는 상황이 두 가지 더 있었다). CloudKit이
  `@Attribute(.unique)`를 지원하지 않아(README "CloudKit 제약 적용" 절) DB
  레벨 중복 방지가 안 되므로, `TranslationBootstrap.ensureBundledTranslationRegistered`와
  같은 방식(저장 전 직접 fetch로 검사)으로 막았다.
- `Views/Bible/BibleReadingViewModel.swift`/`Views/Search/SearchViewModel.swift`
  의 `store(for:)` — `registry.sqliteFileReference`를 곧바로 읽던 것을
  `TranslationFileMaterializer.ensureMaterialized(registry:context:)` 호출로
  바꿨다. S12 이전에는 번들 번역본 하나뿐이라 이 경로(사용자 추가 번역본의
  `isBundled == false` 분기)가 실제로 실행된 적이 없었다 — 이번에 처음으로
  사용자 추가 번역본이 생기므로, 방치하면 다른 기기에서 동기화된 번역본을
  S1/S11이 열지 못하는 채로 남을 뻔했다.
- `Views/Settings/SettingsView.swift`의 `TranslationsSettingsTab`(8.3) —
  비활성화돼 있던 "번역본 추가..." 버튼이 `TranslationImportSheet`를 열도록
  연결했다. 삭제 시에도 `TranslationFileMaterializer.removeLocalCopy`로 로컬
  캐시 파일을 함께 정리하도록 보완했다(기존 코드는 SwiftData 레코드만 지우고
  디스크 파일은 그대로 남기고 있었다).
- `Views/Navigation/PlaceholderScreens.swift` — `TranslationManagementPlaceholderView`
  제거, `MorePlaceholderView`의 "번역본 관리" 항목이 `TranslationManagementView()`로
  연결.

### ⚠️ 남은 범위 밖 항목

- macOS/iPadOS는 여전히 설정(8.3 탭)을 통해서만 번역본 관리에 닿는다 —
  `AppSection`(사이드바)에 별도 항목을 추가하지 않았다. iPhone만 "더보기"에서
  전체 화면(`TranslationManagementView`)으로 들어간다. 원문 IA가 이 비대칭을
  의도한 것인지는 S10/S11 때와 같은 이유로 확인이 안 된 상태다.
  (`Views/Navigation/AppSection.swift`에 케이스를 추가하지 않았다 — 근거
  없는 사이드바 확장을 피하기 위해서다.)
- `TranslationPickerPopover`(S1, 번역본 4개 이상 등록 시 칩 선택)는 이번에
  처음으로 실제 4개 이상 등록된 상태에서 검증할 수 있게 됐지만, 이 세션은
  Xcode 실행이 불가능해 직접 확인하지 못했다 — README 다른 곳에 이미 남아
  있던 "재검증 필요" 메모가 이걸로 닫히지 않았다.
- 파일이 실제로 CloudKit CKAsset으로 정상 업로드/다운로드되는지(로컬
  `sqliteData` 저장과 원격 동기화는 별개, README 위쪽 "남은 것" 항목과 동일한
  종류의 리스크)는 실기기 다중 계정 테스트로만 확인 가능하다.
- 검증(`validate`) 단계의 66권 순회 쿼리는 파일마다 최대 66번의 `SELECT
  MAX(chapter)` 호출이다 — import가 자주 일어나는 경로가 아니라 문제없다고
  판단했지만 실측은 안 했다.
- (발견했지만 이번 범위 밖으로 남긴 기존 버그) `BibleReferenceStore`가 던지는
  `BibleReferenceError`는 `CustomStringConvertible`만 채택하고
  `LocalizedError`는 채택하지 않는다 — `BibleReadingViewModel`/
  `SearchViewModel`이 이 에러를 `error.localizedDescription`으로 표시하는
  곳들은 실제로는 Swift 기본 "작업을 완료할 수 없습니다" 같은 일반 메시지만
  보여줄 가능성이 크다(description이 아니라 localizedDescription을 읽고
  있어서). 이번 S12 코드는 이 함정을 피해 `describe(_:)` 헬퍼로 두 종류
  프로토콜을 다 확인하지만, 기존 두 곳은 고치지 않았다 — S12 범위 밖의
  기존 코드라 근거 없이 손대지 않는 원칙을 따랐다.
- 새 파일(`Services/Translations/*`, `Views/Translations/*`)이 Xcode 타겟에
  아직 추가되지 않았을 수 있다 — 프로젝트 내비게이터에 안 보이면 "Add Files
  to..."로 추가해야 한다.
- 이번 라운드도 Swift 툴체인이 없어 직접 빌드해보지 못했다 — 괄호/중괄호
  균형 점검(스크립트로 전체 새/수정 파일 대조)과 API 시그니처 대조(기존
  파일들이 이미 쓰던 패턴과 동일한지)만 했다. ⌘B 결과를 알려주면 그걸
  근거로 고치겠다.

## ✅ [2026-08-07] 사용자 추가 번역본 실제 스키마 확정 — `version_code` 다중 번역본 가정 대체

바로 위 S12 라운드가 끝난 직후, 사용자가 **사용자 추가 번역본 파일(sqlite 또는
`.bdb` 확장자)의 실제 스키마**를 알려줬다:

```sql
CREATE TABLE "Bible" (
    "id"        INTEGER,
    "book"      INTEGER,
    "chapter"   INTEGER,
    "verse"     INTEGER,
    "btext"     TEXT,
    PRIMARY KEY("id")
);
```

이건 2026-08-06 "`version_code` 정책 확정" 절의 가정("사용자 추가 번역본은
`BibleVerses`와 같은 테이블을 쓰되 `version_code` 컬럼으로 여러 번역본을
구분한다")을 **대체**한다 — 실제로는 테이블 이름부터(`Bible`, `BibleVerses`
아님) 컬럼 이름까지(`id`/`book`/`btext`, `uid`/`book_id`/`content` 아님)
완전히 다른 별개 스키마이고, `paragraph`도 `version_code`도 없다. 즉 "한 파일 =
번역본 하나"가 맞는 모델이었다 — 이전 가정처럼 한 파일에 여러 번역본이 섞여
있는 시나리오는 이 스키마엔 없다.

### 반영한 코드

- **`BibleResearchPlatform/.../BibleReferenceStore.swift`(패키지, 전면 수정)** —
  `init` 시점에 `sqlite_master`를 조회해 `BibleVerses`(번들)와 `Bible`(사용자
  추가) 중 어느 테이블이 있는지 판별하고, 컬럼 이름 차이(`uid`/`id`,
  `book_id`/`book`, `content`/`btext`)는 SELECT 절 `AS` 별칭으로 흡수한다 —
  그래서 `verse`/`verses`/`maxChapter`/`searchVerses`/`availableVersionCodes`
  같은 나머지 로직은 스키마 종류를 몰라도 그대로 동작한다. `paragraph`
  컬럼도(`Bible` 스키마엔 없음) `version_code`와 같은 방식으로 동적 감지하도록
  바꿨다 — 둘 다 없으면 없는 대로, 있으면 있는 대로 안전하게 처리한다는 원칙.
  ⚠️ 두 스키마 중 어느 쪽 테이블도 없는 파일을 열면 이제
  `BibleReferenceError.unrecognizedSchema`로 명확하게 실패한다(이전에는
  `BibleVerses`가 없으면 쿼리 단계에서야 불투명한 `statementPrepareFailed`로
  실패했다).
- **`BibleReferenceModels.swift`** — `BibleReferenceError.unrecognizedSchema(path:)`
  케이스 추가.
- **`Services/Translations/TranslationImportService.swift`** — `validate(fileURL:)`가
  `unrecognizedSchema`를 별도로 잡아 `TranslationImportError.invalidSchema`로
  변환한다(파일을 못 연 것과 스키마가 다른 것을 구분해 더 정확한 메시지를 준다).
  나머지 검증 로직(장 수 대조 등)은 `BibleReferenceStore`의 공개 API만 쓰므로
  스키마 추상화 덕분에 손댈 필요가 없었다.
- **`Views/Translations/TranslationImportSheet.swift`** — 가져오기 파일 선택기의
  허용 확장자에 `bdb`를 추가했다(`sqlite`/`sqlite3`/`db`/`bdb`).

### ✅ 실기기 확인 완료(2026-08-07, 사용자 확인)

사용자가 실제 사용자 추가 번역본 파일로 S12 "가져오기"를 실행해 정상 작동을
확인했다. 이걸로 아래는 "미검증"에서 벗어났다:

- 스키마 판별 로직(`sqlite_master`에서 `Bible` 테이블 인식) + 컬럼 별칭
  흡수(`id`/`book`/`btext` → `uid`/`book_id`/`content`)가 실제 파일에서
  동작한다.
- `.bdb` 확장자 파일도 `sqlite3_open_v2`로 정상 열린다(내부 포맷이 SQLite라는
  전제가 맞았다).
- `TranslationImportSheet` → `TranslationImportService.validate/importTranslation`
  → `TranslationFileMaterializer` 전체 가져오기 경로가 끊김 없이 동작한다.

### ⚠️ 남은 확인 필요(사용자가 "세부적인 부분은 추후 수정"이라고 남긴 지점 — 구체적으로 무엇을 고칠지는 아직 지정되지 않음)

- `book_id`(번들)/`book`(사용자 추가) 두 컬럼이 같은 66권 정경 번호 체계를
  쓰는지는 여전히 가정이다 — S12의 장 수 대조 검증(`chapterMismatches`)이
  이 부분의 실질적인 방어선이다.
- 가져온 번역본이 S1(성경 조회)/S11(통합 검색)에서 실제로 정상 표시되는지는
  "가져오기 자체의 성공"과는 별개로 아직 사용자가 명시적으로 확인해 주지
  않았다 — TranslationColumnView/검색 결과에 `btext` 기반 본문이 깨짐 없이
  나오는지 등.
- 사용자가 "세부적인 부분"이라고만 언급하고 구체적인 항목을 짚지 않았다 —
  다음에 무엇을 고칠지 알려주면 그걸 근거로 진행한다(추측으로 먼저 손대지
  않는다).

## [2026-08-07] S10 태그 관계 — 수동 엣지(실선) 삭제 UI

S10 라운드가 "범위 밖"으로 남겼던 마지막 항목(`TagGraphViewModel
.deleteManualEdge`는 있었지만 화면에 진입점이 없었다)을 닫았다. 여러 개
남아 있던 후보(14.4 성경 장절 자동 인식, 14.6 AI 단어 제안, S11 다중 번역본
동시 색인, Settings 미배선 항목들) 중 "가장 작고 이미 백엔드 로직이 준비된
것"이라 사용자가 이걸 먼저 골랐다.

### 구현

- `Views/TagRelations/TagRelationsView.swift` — Canvas의 `.allowsHitTesting(false)`를
  제거하고 `SpatialTapGesture(coordinateSpace: .named("graph"))`를 붙였다.
  Canvas는 SwiftUI 표준 도형 뷰가 아니라 직접 그린 픽셀이라 개별 선분이
  히트테스트 대상이 되지 않는다 — 그래서 탭 좌표와 각 **수동 엣지**(점선인
  자동 추론 엣지는 제외) 선분 사이의 최단 거리를 직접 계산하는
  `distance(from:toSegment:)`(점을 선분에 투영, t를 0...1로 클램프하는 표준
  공식)로 히트테스트를 구현했다. 임계값(10pt) 안에서 가장 가까운 엣지를 찾는다.
- 탭 즉시 삭제하지 않고 `.alert`로 한 번 더 확인한다("A ↔ B 연결을
  삭제할까요?" — 연결된 두 태그 이름을 실제로 보여준다) — 오탭으로 관계가
  바로 지워지는 걸 막기 위해서다. 원문 목업에 이 확인 단계가 명시된 적은
  없다(⚠️ 이번에도 screens.md 원문이 이 세션에 없어 추론으로 결정, S12 라운드와
  같은 제약).
- 노드(원+이름표)는 여전히 자기 자신의 `.onTapGesture`/`DragGesture`를 갖고
  있어 Canvas의 새 제스처와 z-order로 자연스럽게 분리된다 — 노드를 탭하면
  드릴다운이, 빈 캔버스의 실선을 탭하면 삭제 확인이 뜬다(노드 위에 얹힌
  실선까지는 삭제 확인이 뜨지 않을 수 있다 — 노드의 히트 영역이 우선한다).
- 범례(legend) 문구를 "태그를 다른 태그 위로 드래그하면 연결됩니다" →
  "드래그로 연결 · 실선을 탭하면 삭제"로 갱신해 새 상호작용을 안내한다.

### ⚠️ 남은 확인 필요

- 이 세션은 Xcode 실행이 불가능해 실제 탭 히트테스트 정확도(임계값 10pt가
  손가락 탭에 적당한지, 트랙패드/마우스 클릭에 적당한지)를 검증하지 못했다 —
  실기기에서 너무 좁거나 넓으면 임계값만 조정하면 된다.
- 노드가 실선 위에 겹쳐 있을 때(짧은 엣지) 탭이 노드로 우선 소비되는 것이
  실제로 문제가 되는지(예: 짧은 연결은 삭제하기 더 어려움)는 실사용 후
  판단이 필요하다 — 문제가 되면 노드에 삭제 진입점(예: 길게 눌러 연결된
  엣지 목록 보기)을 별도로 추가하는 방안도 있다.
- README 이전 라운드가 나열했던 다른 후보(14.4/14.6/S11 다중 번역본 색인/
  Settings 미배선 항목)는 이번에 다루지 않았다 — 사용자가 명시적으로 이
  항목 하나만 골랐다.

## ✅ [2026-08-07] 프로젝트 원본 문서 재동기화 — screens.md/schema.md/addendum.md 실물 확보 + S12/S10 대조 보완

사용자가 "프로젝트 컨텍스트를 다시 로드할 것"이라고 지시했다. 확인해보니 Claude.ai
프로젝트 지식에 그동안 이 세션에서 볼 수 없었던 원본 세 문서(`bible-research-platform
-schema.md`, `-screens.md`, `-review-addendum.md`)가 실제로 동기화돼 있었다 — 지금까지
여러 라운드(특히 S12/S10)가 "원문이 없어 다른 파일의 단서로 역추론했다"고 반복해서
남긴 ⚠️들을 이번에 처음으로 진짜 원문과 대조할 수 있게 됐다.

### 대조 결과 — 크게 어긋난 것은 없었지만, 두 가지는 진짜 누락이었다

1. **✅ 확인됨(추측이 맞았음)**: S10의 삭제 확인 알림(`.alert`)은 스펙 10.2
   "파괴적 행동(삭제/폐기/**관계 삭제**)은... 확인 다이얼로그 동반"과 정확히
   일치한다 — 지난 라운드에 "원문 근거 없이 판단했다"고 적어 둔 게 실은 스펙
   그대로였다. `TagRelationsView.swift` 상단 주석을 정정했다.
2. **⚠️→✅ 발견 후 보완 1**: 8.3(환경설정 번역본 탭) 원문에 "설치된 번역본 목록
   표(이름 / 종류 / 라이선스 / **동기화 상태**)"와 "**성경 조회(S1) 기본 표시
   3개 체크박스 선택**" 두 항목이 있었는데, 지금까지 구현엔 둘 다 없었다(목록에
   번들/사용자추가/라이선스만 있었고, 체크박스 자체가 없었다 — 예전 커밋 메시지가
   "S1 기본표시 체크박스"를 언급만 하고 실체가 없던 게 바로 이 누락이었다).
3. **⚠️→✅ 발견 후 보완 2**: S12 원문 "번역본 추가(임포트), 목록에서 **삭제/편집**,
   라이선스 정보 표시"에서 "편집"이 실제로 빠져 있었다 — 지금까지는 책이름표
   언어만 바꿀 수 있고 표시 이름·라이선스는 가져오기 시점에 고정이었다.
4. **⚠️→✅ 발견 후 보완 3(파생 버그)**: 8.3/S12 상태 표시를 만들다가,
   `TranslationMaterializationError`가 `LocalizedError`를 채택하지 않아
   `error.localizedDescription`으로 표시하면 커스텀 메시지 대신 Foundation
   일반 문구가 나오는 문제를 발견했다 — README가 이미 `BibleReferenceError`에서
   같은 패턴을 "범위 밖 기존 버그"로 기록해 뒀던 것과 같은 함정을 새 코드에서
   반복한 것이었다. screens.md 4.3/6.7이 "새 기기 동기화 중" 메시지가 실제로
   보여야 한다고 명시하고 있어 이번엔 범위 밖으로 미루지 않고 `BibleReferenceError`/
   `TranslationMaterializationError` 둘 다 `LocalizedError`를 추가로 채택해 고쳤다.

### 반영한 코드

- `Services/Translations/TranslationFileMaterializer.swift` —
  `TranslationMaterializationError`에 `LocalizedError` 추가. `SyncStatus` enum(
  `.bundled`/`.available`/`.pendingMaterialization`/`.notYetSynced`) + `syncStatus(for:)`
  신설 — 파일을 쓰지 않는 순수 조회 함수라 목록을 그릴 때마다 안전하게 호출할 수
  있다(`ensureMaterialized`는 실제로 열 때만 쓰는 부작용 있는 함수로 그대로 유지).
- `BibleResearchPlatform/.../BibleReferenceModels.swift` — `BibleReferenceError`에
  `LocalizedError` 추가(`errorDescription` → 기존 `description` 재사용).
- `Services/UserSettingsStore.swift` — `defaultDisplayedTranslationCodes: [String]`
  신설(8.3의 "S1 기본 표시 3개 체크박스"용, UserDefaults `stringArray` 저장). 8.1의
  `defaultTranslationCode`(단일, "맨 앞으로 당기기")와는 별개 설정이라는 점을
  주석에 명시했다.
- `Views/Bible/BibleReadingViewModel.swift`의 `loadAvailableTranslations()` — 첫
  진입 시 `defaultDisplayedTranslationCodes`가 있으면 최우선 사용, 없으면 기존
  "등록 순 + defaultTranslationCode 맨 앞" 규칙으로 대체(하위 호환 유지).
- `Views/Settings/SettingsView.swift`의 `TranslationsSettingsTab` — 목록 행에
  동기화 상태 표시 추가(`TranslationFileMaterializer.syncStatus(for:).label`).
  "성경 조회(S1) 기본 표시" 섹션 신설 — 번역본별 체크박스(최대 3개, 넘으면 나머지
  비활성화) → `defaultDisplayedTranslationCodes` 갱신.
- `Views/Translations/TranslationManagementView.swift`/`TranslationManagementViewModel.swift` —
  표시 이름·라이선스를 인라인 `TextField`로 바로 편집 가능하게 추가(번들도
  포함 — 6.7이 막은 건 "번들 삭제"뿐이라 편집까지 막을 근거는 없었다). 타이핑마다
  `reload()`(66권 순회 + materialize 재시도 포함)를 다시 부르면 버벅일 수 있어,
  이 두 필드만은 `registry`를 직접 갱신하고 `reload()` 없이 저장하도록 분리했다.
  행 부제목에 동기화 상태도 추가(번들은 표시 안 함 — 중복 방지).

### ⚠️ 남은 확인 필요

- 이번 대조는 **S10/S12 두 화면과 그에 딸린 8.3 설정 탭만** 실제 원문과
  맞춰봤다 — 나머지 S1~S9, S11 및 8장의 다른 탭들(8.2/8.5/8.6/8.7)은 이번 범위에
  포함하지 않았다. 원문이 이제 있으니, 전체를 처음부터 한 번 더 대조하는
  전수 감사도 가능하지만 사용자가 요청하지 않아 하지 않았다(과도한 범위 확장
  방지).
- `DocumentUploadError`/`ChapterOutlineDraftService.DraftError`/
  `TranslationBootstrapError`도 `BibleReferenceError`/`TranslationMaterializationError`와
  같은 `Error, CustomStringConvertible`만 채택하는 패턴이다 — 같은 버그가 있을
  가능성이 있지만, 이번 라운드는 실제로 "동기화 중" 메시지가 필요하다고 스펙에
  명시된 두 곳만 고쳤다. 나머지 세 곳은 손대지 않았다(범위 밖, 필요시 같은
  패턴으로 고칠 수 있다).
- 8.3 체크박스/동기화 상태, S12 편집 필드 모두 이 세션은 Xcode 실행이 불가능해
  직접 빌드·실행 확인을 못 했다 — ⌘B 결과를 알려주면 그걸 근거로 고치겠다.

## [2026-08-07] "전체를 한 번 더 훑어볼것" — S1~S11 + 설정/메뉴/윈도우 전수 대조

바로 위 라운드는 S10/S12 두 화면만 원문과 대조했다. 이번 라운드는 나머지
S1~S9, S11, 설정 8장의 나머지 탭들(8.2/8.5/8.6/8.7/8.8), 9장(메뉴바), 10장
(색상/버튼 체계), 11장(창 구조)까지 원문 세 문서와 다시 맞춰봤다. 병렬로 6개
영역(① S1, ② S2~S4, ③ S5~S7, ④ S8~S9, ⑤ S11, ⑥ 설정/메뉴/윈도우)을 나눠 조사한
뒤, 실제로 고칠 만한 항목만 이번 라운드에서 바로 반영했다.

### 이번 라운드에서 고친 것

1. **`Views/Memo/MemoDetailView.swift`의 `updateTagSuggestions(for:)`** —
   screens.md의 "기존 태그 자동완성 추천(**빈도순**)" 요구와 달리 이름 알파벳순
   정렬이었다. `tag.memoTags?.count`(그 태그가 붙은 메모 수)를 빈도로 써서
   내림차순 정렬하고, 빈도가 같으면 이름순으로 안정적인 2차 정렬을 하도록
   고쳤다.
2. **`Views/Bible/TranslationPickerPopover.swift`** — 번역본을 이미 3개(최대치)
   고른 상태에서 나머지 칩이 비활성화되는 이유를 설명하는 문구가 없었다(카운터
   숫자만 있었음). "다른 번역본을 보려면 먼저 하나를 해제하세요" 안내문을
   최대치 도달 시에만 보이도록 추가했다.
3. **`Views/Bible/TranslationColumnView.swift`의 스크롤 동기화 가드** —
   addendum.md 3장이 지정한 "가드 해제 시각을 애니메이션 지속 시간과 정확히
   맞추고, `DispatchWorkItem`으로 이전 예약을 취소하는" 패턴 대신, 애니메이션은
   0.25초인데 가드는 임의로 0.4초 뒤에 풀리는 코드였다. 애니메이션 duration을
   상수(`scrollAnimationDuration`) 하나로 통일하고, 새 동기화 이벤트가 들어오면
   `DispatchWorkItem.cancel()`로 이전 가드 해제 예약을 취소한 뒤 재예약하도록
   고쳤다 — 빠른 연속 스크롤에서 가드가 예정보다 일찍 풀려 팔로워가 스스로를
   리더로 착각하는 경합을 막는다.
4. **`Views/Search/SearchViewModel.swift`의 `performSemanticSearch`** —
   screens.md S11이 명시한 성능 유의사항("청크가 많아지면 느려질 수 있다")에
   대해, 기존 주석은 "async 함수 안이라 UI가 안 멈춘다"고 적어 뒀지만 실제로는
   틀린 설명이었다 — 코사인 유사도 계산 for 루프 자체엔 await 지점이 하나도
   없어 MainActor에서 끝까지 동기 실행되고, 그동안 SwiftUI가 화면을 다시 그릴
   기회가 없다. 200개 청크마다 `await Task.yield()`를 넣어 렌더링에 제어를
   양보하도록 고쳤다.
5. **설정 8.2(동기화) "마지막 동기화 시각"** — 원문에 있는 항목인데 지금까지
   `SyncSettingsTab`에 아예 없었다. `UserSettingsStore.lastManualSyncAt: Date?`를
   새로 추가하고, "지금 동기화" 버튼을 누른 시각을 저장해 탭에 표시한다.
   ⚠️ SwiftData/CloudKit엔 "iCloud 업로드가 실제로 끝난 시각"을 알려주는 표준
   API가 없다(이 파일 기존 주석이 이미 밝힌 한계) — 그래서 정확히는 "마지막으로
   로컬 저장을 시도한 시각"이다. 문구도 그렇게 맞췄다.
6. **`Views/Memo/MemoHomeView.swift`의 툴바** — 이 화면만 네이티브 `.toolbar`가
   전혀 없고, 폴더 필터 메뉴와 "새 메모" 버튼이 목록 위 평범한 HStack 안에
   있었다. 이 프로젝트의 다른 화면(DocumentsHomeView 등)이 따르는 "진입점은
   툴바에 둔다"는 배선 관례에 맞춰 두 컨트롤을 `.toolbar`(`.navigation`/
   `.primaryAction`)로 옮겼다. 검색 필드는 목록 위 인라인 `TextField`로 남겨
   뒀다 — `.searchable`로 바꾸는 건 플랫폼별(macOS/iPadOS/iPhone) 동작 차이가
   커서 실기기 검증 없이 바꾸기엔 위험하다고 판단했다.

### 검토했지만 바꾸지 않은 것 (근거 있는 현상 유지)

- **`DocumentsHomeView.swift`의 업로드 버튼 배치(`.primaryAction`)** — screens.md
  목업이 중앙(`.principal`) 배치를 암시하는 것으로 읽힐 수 있는 대목이 있었지만,
  `.principal`은 플랫폼별로 검색 필드 등 특정 용도로 예약되는 경우가 많고
  실기기 검증 없이 바꾸면 레이아웃이 깨질 위험이 있다. 지금 배치는 이미 "13장
  새 메모 버튼과 동일 원칙"이라는 근거로 문서화돼 있어(파일 상단 주석), 추측성
  변경 대신 현행 유지 + 이유를 여기 기록해 둔다. 실기기에서 문제가 확인되면
  그때 바꾸는 게 맞다고 본다.

### ⚠️ 대형 항목 — 사용자 확인 후 진행 (이번 라운드에서 손대지 않음)

아래는 원문과 대조 중 발견했지만, 여러 파일에 걸친 구조 변경이거나 새 기능
전체를 새로 만들어야 하는 항목들이다. 스코프가 커서 이번엔 구현하지 않고
사용자에게 우선순위를 먼저 물어보기로 했다(지금까지 이 프로젝트에서 "다음
작업"을 고를 때 항상 확인받아 온 방식과 같음). **S6/S7 두 항목은 사용자가
"S6 별도 창 / S7 시트+큐"를 선택해 바로 이어서 구현했다 — 아래 새 절 참고.**

- **태그 색상 팔레트(10.1)** — `Tag` 모델에 색상 필드 자체가 없다. SwiftData
  필드 추가 + 팔레트 선택 UI + `TagRelationsView`/메모 태그 칩 등 렌더링 여러
  곳을 함께 고쳐야 한다.
- **"AI로 태그 제안"(메모, 14.6) / "AI로 주요 단어 제안"(문서 키워드, 14.6)** —
  둘 다 미구현. 기존 `ChapterOutlineDraftService`와 같은 FoundationModels
  Guided Generation(`@Generable`/`@Guide`) 서비스를 새로 만들어야 한다.
- **S6 문서 뷰어의 "드래그 선택 → 중요 단어로 표시"** — 지금은
  `.textSelection(.enabled)`만 있고 선택한 텍스트에 대한 액션이 없다.

### 대조는 했지만 실제 코드를 못 본 부분

이번 6갈래 조사는 각 영역을 읽기 전용으로 훑어본 결과라, 위에 적은 것 외에도
더 있을 수 있다. 특히 8.5/8.7/8.8(설정 나머지 탭)과 11장(창 구조) 세부는
"명백한 위반은 못 찾았다"는 수준의 확인이지 한 줄 한 줄 대조한 건 아니다 —
사용자가 특정 화면을 더 깊게 봐 달라고 하면 그 화면만 집중해서 다시 대조할 수
있다.

## [2026-08-07, 이어서] S6 별도 창 / S7 시트+큐 — 대형 항목 중 첫 번째 착수

바로 위 절에서 대형 항목 5개를 제시했고, 사용자가 "S6 별도 창 / S7 시트+큐"를
선택했다. 나머지 3개(태그 색상 팔레트, AI 태그/키워드 제안, 문서뷰어 단어선택)는
아직 손대지 않은 채로 남아 있다.

### S6 — 문서 뷰어를 별도 창으로

screens.md 3장 S6 절 "Preview.app 패턴, 문서마다 별도 창"을 반영했다. 지금까지는
`DocumentViewerView`를 여는 진입점 3곳(S5 문서 목록, S10 태그 드릴다운의 "관련
연구문서"/"관련 OCR 이미지" 두 섹션, S11 검색결과의 "연구문서" 섹션)이 전부
`NavigationLink` 푸시로 메인 창 안에 열었다. ⚠️ 원래 대형 항목 목록엔 "S1 관련문서
패널"도 진입점 중 하나로 적어 뒀는데, 실제 코드를 다시 보니 S1(성경 조회)엔 그런
패널 자체가 아직 없었다 — 그래서 이번엔 실재하는 3곳만 고쳤다.

- **`JBCHBibleResearchApp.swift`** — `WindowGroup(id: "document-viewer", for:
  PersistentIdentifier.self)` 신설("tag-relations" 창 바로 아래). SwiftUI의
  `WindowGroup(for:)`는 값이 `Codable & Hashable`이어야 해서 `SourceDocument`
  인스턴스를 직접 넘길 수 없다 — `PersistentIdentifier`(둘 다 만족)를 대신
  넘기고, 창 안에서 다시 모델을 찾는 게 Apple 공식 예제(SwiftData + 여러 창)와
  같은 방식이다.
- **`Views/Documents/DocumentViewerView.swift`** — `DocumentViewerWindowContent`
  신설. `modelContext.model(for: documentID) as? SourceDocument`로
  `PersistentIdentifier`를 다시 모델로 되찾는다. 그 사이 문서가 삭제됐거나 ID가
  `nil`이면(창을 값 없이 연 경우) 안내 문구만 보여준다.
- **`Views/Documents/DocumentsHomeView.swift`**, **`Views/TagRelations/
  TagDrilldownView.swift`**, **`Views/Search/SearchView.swift`** — 세 곳 모두
  `@Environment(\.openWindow)`를 받아 `NavigationLink { DocumentViewerView(...) }`를
  `Button { openWindow(id: "document-viewer", value: document.persistentModelID) }`로
  바꿨다. List 안 Button이 기본 강조색 틴트를 입지 않도록(기존 NavigationLink
  행과 같은 텍스트 색을 유지하려고) `.buttonStyle(.plain)`을 붙였다 —
  `SidebarNavigationView`가 "태그 관계" 별도 창 항목에 이미 쓰던 것과 같은
  원칙이다.
- ⚠️ **[플랫폼 검증 필요, 기존 패턴과 동일한 리스크]** macOS/iPadOS는
  `openWindow`가 실제로 새 창을 띄우지만, 아이폰은 다중 창을 지원하지 않아
  현재 화면이 이 WindowGroup 콘텐츠로 대체되는 형태로 동작할 것으로 예상된다.
  이건 새로운 위험이 아니다 — 기존 "tag-relations" 창도 똑같은 특성이고
  실기기 검증 없이 이미 그렇게 써 왔다(같은 패턴을 그대로 확장한 것).

### S7 — OCR 검수를 시트 + "저장 후 다음" 큐로

screens.md 14.3 "검수 화면 진입(대기열 방식 — '저장 후 다음'으로 순차 처리)"를
반영했다. 지금까지는 검수 대기 문서를 탭하면 `NavigationLink`로
`OCRReviewView` 하나만 열리고, 저장하면 목록으로 돌아가 사용자가 다음 대기
행을 직접 찾아 다시 탭해야 했다.

- **`Views/Documents/OCRReviewQueueView.swift`(신규 파일)** — 시트로 뜨는 얇은
  컨테이너. `DocumentsHomeView`가 건네주는 검수 대기 문서 배열(탭한 문서가
  맨 앞으로 오도록 회전된 상태)을 인덱스로 훑으며 `OCRReviewView`를 계속
  재사용한다. `.id(document.persistentModelID)`를 반드시 붙여야 하는데, 안
  붙이면 SwiftUI가 다음 문서로 넘어갈 때도 같은 뷰 정체성으로 보고
  `OCRReviewView` 내부 `@State`(viewModel, loadedImage)를 이전 문서 것 그대로
  들고 있을 위험이 있기 때문이다.
- **`Views/Documents/OCRReviewView.swift`** — `onAdvance: (() -> Void)?`와
  `queuePosition: (index: Int, count: Int)?` 두 파라미터를 추가했다(둘 다
  옵셔널이라 기존 "단독으로 연다"는 호출 방식과 하위 호환된다 — 지금은 실제로
  단독 호출부가 없지만, 화면 자체는 재사용 가능한 컴포넌트로 남겨 뒀다).
  저장이 성공하면(`didSave == true`) `onAdvance`가 있으면 그걸 호출해 다음
  문서로 넘어가고, 없으면 기존처럼 `dismiss()`. 큐 안에서 마지막이 아닌
  문서를 보고 있으면 저장 버튼 라벨이 "저장"에서 "저장 후 다음"으로,
  내비게이션 타이틀이 "OCR 검수 (2 / 5)"처럼 바뀌어 지금 큐 안에 있다는 걸
  분명히 알려준다.
- **`Views/Documents/DocumentsHomeView.swift`** — `ocrReviewQueue:
  [SourceDocument]` 상태 신설. 행을 탭하면(`DocumentRowView`의 `onOpenOCRReview`
  클로저) `presentOCRReviewQueue(startingAt:)`가 검수 대기 문서 전체를 탭한
  문서가 맨 앞에 오도록 회전시켜 큐를 만들고, 시트가 뜬다. 시트가 닫히면
  `viewModel?.loadDocuments()`로 목록을 새로고침한다(저장/폐기로 상태가 바뀐
  문서들을 반영하기 위해). `DocumentRowView`도 `NavigationLink` 대신 분기하는
  `Button`으로 바뀌었다 — 검수 대기 문서는 큐를, 그 외엔 위 S6 별도 창을 연다.
- ⚠️ **[큐 순서 규칙, 스펙에 명시 없음]** "탭한 문서부터 시작해서 나머지
  대기 문서를 목록 순서 그대로 이어서" 회전시키는 규칙은 이번에 임의로 정한
  것이다 — 원문은 "대기열 방식"이라고만 하고 정렬 기준을 명시하지 않았다.

### 정적 검증

Swift 컴파일러가 없는 세션이라 이번에도 중괄호/괄호 균형만 스크립트로
확인했다(전부 일치) — 실제 빌드 확인은 Xcode에서 필요하다. 특히
`WindowGroup(for:)`/`ModelContext.model(for:)` 조합은 이 프로젝트에서 처음 쓰는
API라 다른 곳보다 컴파일 확인의 우선순위가 높다 — ⌘B 결과를 알려주면 그걸
근거로 바로잡겠다.

### 이후 사용자 빌드 피드백으로 고친 것 (컴파일러 경고/에러)

- `OCRReviewQueueView.swift`: `queue[index].persistentModelID`를 쓰면서
  `import SwiftData`를 빠뜨렸다 — 추가했다.
- `TranslationImportService.swift`: `guard let foundOrNil = try? store
  .maxChapter(...)`가 SE-0230(옵셔널 평탄화) 때문에 `foundOrNil`을 이미
  `Int?`가 아닌 `Int`로 만들어, 뒤이은 `?? 0`이 컴파일러 경고대로 죽은 코드였다.
  더 심각한 건 이게 실제 버그였다는 점 — 쿼리가 성공했는데 책이 파일에 아예
  없어 `nil`이 나오면 원래 "0장으로 기록"하려던 의도와 달리 `guard`가 실패해
  그 책 자체가 대조에서 조용히 빠지고 있었다. `do`/`catch`로 "쿼리 실패"(건너뜀)와
  "쿼리 성공, 값은 nil"(0장으로 기록)을 구분해 고쳤다.
- `TranslationImportService.swift`/`TranslationManagementViewModel.swift`:
  `error as? CustomStringConvertible`이 Apple 플랫폼에서 모든 Error가 NSError로
  브리징 가능해 "항상 성공하는 캐스팅"이라는 경고가 떴다 — `String(describing:)`이
  이미 CustomStringConvertible 채택 타입엔 그 `.description`을 그대로 써주므로
  그 경로로 단순화했고, 뷰모델 쪽은 `TranslationMaterializationError`가 이미
  `LocalizedError`를 채택하고 있으니 그 경로를 먼저 쓰도록 고쳤다.
- `MemoDetailView.swift`: 태그 자동완성 빈도순 정렬 코드에서 `.sorted { ... }
  .prefix(8)`을 그대로 `[Tag]` 타입 프로퍼티에 대입하려 했다 — `.sorted`는
  배열을 돌려주지만 그 뒤의 `.prefix`는 `ArraySlice<Tag>`를 돌려줘 타입이
  안 맞았다. `Array(...)`로 한 번 더 감쌌다.

## [2026-08-07, 이어서] S1 열 개수 버그 조사 + 성경 조회 다중 창

사용자가 "S1 화면에 3개 열이 있는데 전부 같은 번역본이 출력된다"고 보고했고,
"업로드된 번역본이 1개면 1열, 2개면 2열, 3개면 3열, 4개 이상이면 3열+선택기"가
되어야 한다고 요구했다. 추가로 "성경 조회 창을 여러 개 띄울 수 있고, 각 창이
서로 다른 성경을 동시에 조회할 수 있어야 한다"는 기능도 요청했다.

### 열 개수 자체는 이미 요구사항대로였다

`BibleReadingViewModel.columns`는 이미 등록된 번역본 개수(최대 3개)만큼만
채워지고, `BibleReadingView`의 `ForEach(viewModel.columns)`도 하드코딩된 3이
아니라 그 배열 그대로를 그린다 — 코드만 보면 "1개면 1열, 4개 이상이면 선택기"
요구사항을 이미 만족하고 있었다. 즉 "3개 열 다 나온다"는 증상은 열 개수 로직의
버그가 아니라, **실제로 서로 다른 `TranslationRegistry` 행이 3개 존재했고, 그
행들의 내용(번역본)이 우연히 같았다**는 뜻이라고 판단했다.

### 근본 원인 — CloudKit 중복 등록

`TranslationBootstrapError`/`README`가 이미 여러 차례 기록해 둔 한계와 정확히
맞아떨어진다: CloudKit은 `@Attribute(.unique)`를 지원하지 않아
`TranslationRegistry.code`(예: 번들 번역본의 "KRV") 중복을 DB 레벨에서 막을 수
없다. `ensureBundledTranslationRegistered`는 같은 프로세스 안에서는 멱등(이미
있으면 건너뜀)이지만, 여러 기기(Mac/iPad/iPhone)에서 서로의 CloudKit 레코드를
아직 못 본 상태로 거의 동시에 처음 실행되면 기기마다 자기 몫의 "KRV" 행을 따로
만들어 버릴 수 있다 — 나중에 CloudKit이 병합하면 `code`가 같은 행이 여러 개
남는다. S1은 "등록된 행 개수만큼 열을 그린다"는 원칙을 정확히 지키고 있었을
뿐이라, 결과적으로 서로 다른 행이지만 내용이 완전히 같은 번역본이 여러 열에
나란히 보이는 것처럼 보였다.

### 반영한 코드

- **`Services/TranslationBootstrap.swift`** — `deduplicateRegistries(in:)` 신설.
  모든 `TranslationRegistry`를 `code`로 그룹핑해, 그룹 크기가 2 이상이면 번들
  항목을 우선 살리고(없으면 가장 먼저 추가된 것) 나머지는 지운다(사용자 추가
  중복이면 로컬 캐시 파일도 함께 정리). `TranslationImportService
  .importTranslation`이 애초에 "code는 앱 전체에서 유일해야 한다"는 규칙을
  가져오기 시점에 직접 검사해 왔으니, 여기서도 같은 규칙으로 정리하는 것이
  일관적이라고 판단했다.
- **`ContentView.swift`** — 부트스트랩 직후(`ensureBundledTranslationRegistered`
  바로 다음) `deduplicateRegistries`를 호출해, 앱을 열 때마다 정리되게 했다.
- ⚠️ **[진짜 원인인지 실기기 확인 필요]** 이 세션은 사용자의 실제 SwiftData
  저장소 내용을 볼 방법이 없어, "CloudKit 다중 기기 부트스트랩 경합"이 실제
  원인이라고 100% 확인하지는 못했다 — 다만 이 코드베이스 자체가 이미 여러 곳에서
  "CloudKit은 유니크 제약을 지원하지 않는다"는 위험을 명시적으로 경고해 왔고,
  이 수정은 그 시나리오뿐 아니라 다른 경위로 code가 중복된 경우에도 똑같이
  안전하게 정리해 주므로(부작용 없음, `code`가 유일해야 한다는 건 이미 확정된
  비즈니스 규칙) 원인이 다르더라도 무해하다고 판단해 바로 반영했다. 만약 정리
  후에도 같은 증상이 재현되면 원인이 다른 곳(예: 실제로 다른 파일을 똑같은
  내용으로 여러 번 가져온 경우 — 이건 버그가 아니라 사용자가 의도한 것일 수
  있음)에 있다는 뜻이니 알려달라.

### 성경 조회(S1) 다중 창

screens.md에 명시된 요구는 아니지만 사용자가 직접 요청한 기능이라 바로
구현했다. `JBCHBibleResearchApp.swift`에 `WindowGroup(id: "bible-reading")`을
새로 추가했다 — "tag-relations"/"document-viewer" 창과 같은 패턴이다.
`BibleReadingView()`는 자기 `@State private var viewModel:
BibleReadingViewModel?`을 뷰 인스턴스마다 새로 만들기 때문에(전역 싱글턴을 쓰지
않는다는 원칙은 `AppFocusedValues.swift` 상단 주석이 이미 근거로 남겨 뒀다),
추가로 여는 창마다 book/chapter/표시 번역본 상태가 완전히 독립적이다 — 여러
창을 열어 서로 다른 성경을 동시에 조회할 수 있다.

진입점 두 곳을 추가했다("메뉴, 아이콘" 요청 그대로):
- **`Views/Commands/AppCommands.swift`** — View 메뉴의 "별도 창" 구획(태그 관계
  보기 바로 아래)에 "성경 조회 새 창"(⇧⌘B) 추가. 태그 관계 보기와 같은 원칙으로
  FocusedValue 없이 항상 활성화.
- **`Views/Bible/BibleReadingView.swift`** — S1 자체 툴바에 "성경 조회 새 창"
  아이콘(`macwindow.badge.plus`) 추가.
- ⚠️ **[아이콘 이름 미검증]** `macwindow.badge.plus`는 SF Symbols 4(iOS 16/
  macOS 13)에 추가된 것으로 기억하고 썼다 — 이 프로젝트가 이미 macOS 14+/iOS
  17+를 전제하니 버전 자체는 문제 없을 것으로 보이지만, 정확한 심볼 이름은
  실기기/Xcode의 SF Symbols 앱에서 확인이 필요하다. 이름이 틀려도 빌드는 되고
  아이콘만 비어 보이는 정도라 심각하지 않다.
- ⚠️ **[플랫폼 특성, 기존 패턴과 동일]** macOS/iPadOS는 실제 별도 창으로 열리고,
  아이폰은 "tag-relations"/"document-viewer" 창과 같은 이유로 다중 창 자체를
  지원하지 않아 현재 화면이 새 콘텐츠로 대체되는 형태로 동작할 것으로 예상된다.

## [2026-08-08] S1 보완 — 표시 폰트 설정 + 성경 구절 클립보드 복사

사용자가 두 가지를 요청했다: (1) S1의 표시 스타일(본문크기/색상/절 크기/줄간격/
글꼴)을 환경설정에서 조정, (2) 성경 구절(단일/연속/비연속)을 클립보드에 복사하는
기능과 그 서식을 정하는 환경설정. 복사 서식 항목은 사용자가 참고 소스로
`FormatTabView.swift`(다른 프로젝트에서 이미 구현해 둔 것으로 보이는 코드)를
업로드해 줘서, 그 항목 이름과 의미를 최대한 그대로 옮겼다.

### 표시 폰트 설정

- **`Services/UserSettingsStore.swift`** — `bibleFontName`/`bibleBodyFontSize`/
  `bibleVerseNumberFontSize`/`bibleLineSpacing`/`bibleTextColorHex` 신설 +
  이를 SwiftUI `Font`/`Color`로 변환하는 `bibleBodyFont`/`bibleVerseNumberFont`/
  `bibleTextColor` 확장 프로퍼티. 색상은 자유 컬러피커 대신 팔레트에서만 고르게
  했다 — ⚠️ SwiftUI `Color`에서 hex를 다시 뽑아내는 안전한 공개 API가 없다는
  기존 `Color+Hex.swift`의 제약(메모 텍스트 색상에서 이미 같은 이유로
  `Color.memoTextPalette`를 쓰고 있었다) 때문에, 여기서도 그 팔레트를 그대로
  재사용했다.
- **`Views/Bible/TranslationColumnView.swift`**의 `VerseRow` — 고정값이던
  `.font(.body)`/`.font(.caption)`을 위 설정값으로 교체. `@Observable`이라
  설정 화면에서 바꾸면 S1이 열려 있어도 즉시 반영된다(별도 새로고침 불필요).
- **`Views/Settings/SettingsView.swift`**의 `AppearanceSettingsTab`(8.6 모양) —
  "⚠️ 아직 구현되지 않았습니다"였던 자리를 실제 글꼴/크기/색상/줄간격 컨트롤 +
  미리보기로 교체. 글꼴 목록은 macOS(`NSFontManager`)/iOS(`UIFont`)에서 각각
  다른 API로 구한다.

### 성경 구절 클립보드 복사

- **`Services/Bible/BibleVerseCopyFormatter.swift`(신규)** — 순수 포매팅 로직만
  담은 `@MainActor enum`. 핵심은 `formatVerseRange(_:)` — 정렬된 절 번호를
  연속 구간으로 묶어 "이어진 구절"은 "1-5", "떨어진 구절"은 "1,3,5", 섞여
  있으면 "1-3,5,7-9"처럼 표현한다. `format(book:chapter:selectedVerses:
  translations:settings:)`가 이 범위 문자열 + 환경설정(참조 위치/괄호 스타일/
  약어/번역본 이름 위치/줄바꿈/절 번호 스타일)을 합쳐 최종 문자열을 만든다.
  여러 번역본을 함께 복사하면(S1이 최대 3열까지 보여줄 수 있으므로) 번역본마다
  블록을 만들어 빈 줄로 이어 붙인다 — 번역본이 실제로 1개뿐이면 이름표 자체를
  안 붙인다("번역본이 한 개라면 비활성화" 요청 그대로).
- **`Services/UserSettingsStore.swift`** — `copyReferencePosition`/
  `copyReferenceBracketStyle`/`copyUseAbbreviatedBookName`/
  `copyTranslationLabelPosition`(원본 FormatTabView.swift에는 없던 항목 —
  다중 번역본 지원 때문에 새로 필요해졌다)/`copyNewlineBetweenVerses`/
  `copyRepeatReferenceForEachVerse`/`copyShowVerseNumbers`/
  `copyVerseNumberStyle`/`copyShowFirstVerseNumber` 신설.
- **`Views/Bible/BibleReadingViewModel.swift`** — `selectedVerses: Set<Int>`(모든
  컬럼이 공유하는 절 번호 선택 상태) + `toggleVerseSelection`/
  `clearVerseSelection`/`formattedCopyText()` 추가. 장을 이동하면 선택을
  비운다(이전 장 절 번호가 남아 있어도 의미 없음).
- **`Views/Bible/TranslationColumnView.swift`** — 절을 탭하면(기존에 아무 효과
  없던 `onSelectVerse` 콜백 자리) 선택이 토글된다. 선택된 절은 배경 틴트 +
  왼쪽 강조색 세로선으로 표시(검색 하이라이트보다 더 뚜렷하게 — 실수로 엉뚱한
  절을 복사하면 안 되므로).
- **`Views/Bible/BibleReadingView.swift`** — 선택이 있을 때만 하단에 "N개 절
  선택됨 / 선택 해제 / 복사" 액션바가 나타난다(OCRReviewView 하단 액션바와 같은
  배치 원칙). "복사" 버튼은 뷰모델이 만든 문자열을 `NSPasteboard`(macOS)/
  `UIPasteboard`(iOS)에 넣는다 — 플랫폼 분기는 뷰 레이어에만 둔다(이 프로젝트의
  기존 관례).
- **`Views/Settings/SettingsView.swift`**의 새 탭 `BibleCopyFormatSettingsTab`
  ("복사 형식") — FormatTabView.swift와 같은 두 그룹(기본 설정/상세 출력
  형식) + 미리보기. ⚠️ 미리보기는 `BibleVerseCopyFormatter.format(...)`을
  창세기 1:1-2 예시 데이터로 실제 호출해서 만든다 — 미리보기 로직을 따로 짜지
  않고 실제 서식 함수를 그대로 재사용해, 미리보기와 실제 복사 결과가 어긋날
  가능성 자체를 없앴다.

### ⚠️ 참고 소스와 의도적으로 다르게 만든 지점

- **책 이름 언어** — 항상 앱 기본 한글 이름(`Book.nameKo`/`abbreviation`)만
  쓴다. 사용자 요청 예시에 "[Gen 1:1]"/"[Genesis 1:1]"(영어)도 있었지만, 이는
  약어/전체 이름 구분을 보여주기 위한 예시로 판단했다 — 번역본 언어별로 다른
  책이름표(`BookNameTableProvider`가 이미 갖고 있음)를 따라가는 요구까지는
  아니라고 봤다. 필요하면 확장 가능하다.
- **"절마다 장:절 반복" 모드에서의 참조 위치** — 원본 FormatTabView.swift는 이
  모드에서 참조를 항상 절 앞에 고정하고(그래서 위치 Picker를 비활성화한다),
  이 구현은 `copyReferencePosition` 설정을 이 모드에서도 그대로 적용한다(더
  일관적이라고 판단) — 그래서 이 앱의 설정 화면은 이 모드에서도 위치 Picker를
  끄지 않는다. FormatTabView.swift를 정확히 재현하는 게 목적이 아니라 "참고"
  요청이었어서 이 차이는 의도적이다.

### 정적 검증

이번에도 Swift 컴파일러 없이 중괄호/괄호 균형 스크립트로만 확인했다. 문자열
리터럴 안에 일부러 짝이 안 맞는 괄호를 넣은 곳(`VerseNumberStyle`의 "1)" 스타일
등)이 있어 순수 문자 카운트로는 거짓 경고가 났다 — 코드만 따로 떼어 다시
확인해 실제로는 문제없음을 확인했다. `NSFontManager`/`UIFont.familyNames`,
`NSPasteboard`/`UIPasteboard` 같은 플랫폼 API는 이 세션에서 컴파일 검증이
불가능해 다른 곳보다 확인 우선순위가 높다 — ⌘B 결과를 알려주면 그걸 근거로
바로잡겠다.

## 2026-08-08 — S1 보완 후속: 성경장절 + 번역본 이름 "같은 쪽" 병합/분리 옵션

사용자 요청 원문: "성경장절과 번역본이 동일하게 본문 앞 또는 본문 뒤에 위치했을
때 성경장절과 번역본을 분리해서 보일건지, 합쳐서 보일건지 옵션도 있어야 할것.
ex) [NKJV Genesis 1:1] [NKJV][Genesis 1:1]"

바로 위 절("성경 구절 클립보드 복사")에서 만든 `copyReferencePosition`(성경
장절 위치)과 `copyTranslationLabelPosition`(번역본 이름 위치)은 서로 독립된
설정이라, 둘 다 "본문 앞" 또는 둘 다 "본문 뒤"로 우연히 같아지면 두 이름표가
바로 붙어 나온다. 지금까지는 이 경우에도 항상 번역본 이름을 별도 줄에 뒀는데
(예: "NKJV\n[Genesis 1:1] 본문"), 사용자는 그 대신 한 괄호로 합치거나
("[NKJV Genesis 1:1]") 괄호를 두 개로 나란히 붙이는("[NKJV][Genesis 1:1]")
선택지를 요청했다.

- **`Services/UserSettingsStore.swift`** — `copyCombineReferenceAndTranslationLabel: Bool`
  신설(기본값 `true` = 합침, 사용자 예시에서 먼저 나온 형태를 기본으로 잡았다).
  이 값은 `copyReferencePosition == copyTranslationLabelPosition`일 때만
  의미가 있고, 다르면 어떤 값이든 무시된다(아래 포매터 로직 참고).
- **`Services/Bible/BibleVerseCopyFormatter.swift`** — 새 private 헬퍼
  `referenceText(bookName:chapter:verseText:bracket:combinedLabel:settings:)`를
  추가해 참조 브라켓 생성을 한 곳으로 모았다. `combinedLabel`이 `nil`이면
  기존과 동일한 "[창세기 1:1]" 형태 그대로고, 위치가 같아 번역본 이름이 넘어오면
  설정에 따라 "[NKJV 창세기 1:1]"(합침) 또는 "[NKJV][창세기 1:1]"(분리, 같은
  괄호 스타일로 각자 감싼 뒤 이어 붙임)을 만든다. `format(...)`은 이제
  `sameSide = (copyReferencePosition == copyTranslationLabelPosition)`을 먼저
  계산해, 같은 쪽일 때만 `combinedLabel`을 참조 문자열 생성에 흘려보내고
  번역본 이름을 별도 줄로 붙이는 기존 분기(`showTranslationLabel && !sameSide`)는
  건너뛴다. "절마다 장:절 반복" 모드(`copyRepeatReferenceForEachVerse`)에서도
  절마다 만드는 참조 하나하나에 같은 헬퍼를 써서 동일하게 병합/분리가 적용된다.
- **`Views/Settings/SettingsView.swift`**의 `BibleCopyFormatSettingsTab` —
  "번역본 이름 위치" Picker 바로 아래에 토글을 추가했다. 두 위치가 다르거나
  등록된 번역본이 1개뿐이면(어차피 이름표 자체가 안 붙으므로) 아예 숨긴다 —
  비활성화만 하면 "왜 안 먹히지" 오해가 생길 수 있어 숨기는 쪽을 택했다.
  푸터 텍스트도 두 위치가 같을 때 현재 선택에 따른 실제 예시("[NKJV 창세기
  1:1]" / "[NKJV][창세기 1:1]")를 보여준다. 미리보기 섹션은 코드 변경 없이도
  그대로 정확하다 — 실제 `BibleVerseCopyFormatter.format(...)`을 그대로
  호출하기 때문.

### 정적 검증 (이번 라운드)

같은 방식(중괄호/괄호 균형, 주석·문자열 리터럴 제외 후 재확인)으로
`BibleVerseCopyFormatter.swift`/`UserSettingsStore.swift`/`SettingsView.swift`
세 파일을 확인했다. `UserSettingsStore.swift`에서 나온 괄호 불일치는 전부
기존에 이미 있던 `VerseNumberStyle`의 "(1)"/"1)" 스타일 문자열 리터럴 때문(이번
수정과 무관, 이전 라운드에서도 같은 원인으로 확인됨)이고, 나머지 두 파일과
이번에 새로 추가/수정한 코드 블록은 모두 균형이 맞았다. Swift 컴파일러 자체는
이 세션에서 쓸 수 없어 실제 빌드 확인은 못 했다 — Xcode에서 ⌘B 결과를 알려주면
그걸 근거로 바로잡겠다.

## [2026-08-08] S1 관련 콘텐츠 패널(개요/메모/연구문서) — screens.md 대형 항목 중
"S1 관련문서 패널" 최초 구현

사용자 질문: "성경 장을 읽을 때 이 성경의 개요와 메모, 연구문서가 있다는 것을
한번에 확인할 수 있는 화면이 있는가?" 조사해 보니 없었다 — 2026-08-07 라운드
("S6 별도 창 / S7 시트+큐 — 대형 항목 중 첫 번째 착수" 절)가 이미 "원래 대형
항목 목록엔 'S1 관련문서 패널'도 진입점 중 하나로 적어 뒀는데, 실제 코드를 다시
보니 S1(성경 조회)엔 그런 패널 자체가 아직 없었다"고 기록해 뒀던 항목이다. 이번에
처음 구현했다.

### 확인 과정에서 드러난 문제 — 연구문서는 장(chapter)에 연결할 방법이 없었다

개요(`BookOutline`/`ChapterSummary`)와 메모(`UserMemo`)는 이미 `bookId`/`chapter`를
모델에 직접 갖고 있어 바로 조회가 됐지만, 연구문서(`SourceDocument`)는 그렇지
않았다. 모델에 `DocumentAnchor(anchorType: .verseRef, linkedVerse:)`라는, 문서를
특정 성경 구절에 연결하는 필드가 이미 있었지만, 실제로 이 필드를 채우는 화면이
앱 어디에도 없었다(전수 검색 결과 이 값을 생성하는 코드가 한 곳도 없음을 확인) —
즉 그 경로 그대로 패널을 만들면 항상 "연결된 문서 없음"만 뜨는 상태였다. 사용자에게
확인한 결과 두 가지를 정하고 진행했다: (1) 이번 라운드는 개요+메모를 먼저 만들고,
(2) 연구문서는 "업로드할 때 관련 성경 장을 입력받는" 새 기능을 만들어 연결한다 —
`DocumentAnchor.linkedVerse`(절 단위, verse 값 필수)를 재사용하지 않고 새 필드를
추가했다(아래 참고).

### `SourceDocument.relatedChapterRef` 신설

- **`BibleResearchPlatform/.../Models/Documents.swift`** — `SourceDocument`에
  `relatedChapterRef: BibleChapterRef?` 추가(`BibleChapterRef`는 이미
  `LectureNote.chapterRefs`가 쓰던 책+장 전용 값 타입, 재사용). `DocumentAnchor.linkedVerse`
  (`BibleVerseRef`, verse 값 필수)를 대신 쓰지 않은 이유: `DocumentAnchor`는 "문서
  안의 특정 위치(페이지/줄)와 성경 구절/태그의 연결"(6.3, S6 "드래그 선택 → 중요
  단어 표시"용으로 남겨둔 미구현 기능)을 뜻하는 모델이라, "문서 전체가 이 장과
  관련 있다"는 문서 레벨 메타데이터와 의미가 다르다 — 없는 verse 값에 0 같은
  임의 값을 채우는 편법보다 필드 하나를 새로 추가하는 쪽이 더 명확하다고 판단했다.
- **`Services/Documents/DocumentUploadService.swift`** — `createSourceDocument(from:context:relatedChapterRef:)`로
  확장(기본값 nil, 기존 호출부는 전혀 안 바뀜).
- **`Views/Documents/DocumentsViewModel.swift`** — `upload(urls:relatedChapter:)`로
  확장 + `setRelatedChapter(_:for:)` 신설(업로드 후 재설정/해제용, `setCategory`와
  같은 "이산적 액션, 즉시 저장" 원칙).
- **`Views/Documents/DocumentsHomeView.swift`** — 업로드 3가지 진입점(툴바 버튼/
  드래그앤드롭/드롭존 클릭) 모두 이제 `beginUpload(urls:)`를 거친다 — 즉시
  업로드하는 대신 새 시트(`UploadChapterLinkSheet`)를 띄워 관련 장을 묻는다.
  "건너뛰기"(관련 장 없이 업로드)와 "이 장으로 업로드" 둘 다 있다 — 사용자 요청이
  "입력받을 수 있도록"이지 "반드시 입력해야"가 아니었기 때문. 시트의 책/장 기본값은
  `LastBiblePositionTracker`(S1이 매번 갱신하는 "마지막으로 보던 위치")로 맞춘다.
  여러 파일을 한꺼번에 올려도 이 배치 전체에 같은 장 하나만 적용된다(파일마다
  다른 장을 고르게 하면 매 파일 확인창이 떠 번거로워지므로). 업로드 후 재설정은
  `DocumentRowView` 컨텍스트 메뉴("관련 성경 장 설정…/변경…/해제", `categoryMenu`와
  같은 위치 원칙) + 새 시트(`ChapterLinkEditorSheet`)로 처리하고, 행에도 설정돼
  있으면 "· 창세기 1장"처럼 바로 보이게 캡션을 추가했다.

### S1 관련 콘텐츠 패널

- **`Views/Bible/BibleReadingViewModel.swift`** — `refreshRelatedContent()` 신설.
  책 개요/장 개요는 **읽기 전용 fetch만** 한다 — S8/S9(`OutlineViewModel`)가 쓰는
  "find-or-create"(`BookOutlineDeduplication`/`ChapterSummaryDeduplication`)를
  일부러 쓰지 않았다. 그 로직은 "편집하러 들어왔으니 없으면 빈 문서를 만들어
  둔다"는 의도인데, 이 패널은 순수 조회 목적이라 방문만 해도 빈 개요 레코드가
  생기는 부작용을 만들고 싶지 않았다. 내용이 비어 있으면(레코드는 있어도 실제로
  아무것도 안 쓴 경우) "없음"으로 취급한다. 메모는 `bookId`+`chapter`로 직접
  필터링. 연구문서는 `relatedChapterRef`가 SwiftData `#Predicate`로 안전하게
  필터링될지 확신이 없어(이 프로젝트가 이미 `TagGraphViewModel` 등에서 복잡한
  관계/구조체 조건은 전체 fetch 후 Swift 레벨에서 거르는 원칙을 따르고 있다) 같은
  방식을 택했다 — ⚠️ 문서가 아주 많아지면 매 장 이동마다 전체 스캔이 느려질 수
  있으나 지금 규모(v1)에서는 허용 가능하다고 판단했다. `selectBook`/`goToChapter`/
  `onAppear`가 자동으로 새로고침하고, 메모 시트를 닫을 때(`onDismiss`)도 다시
  불러 방금 만들거나 고친 메모가 곧바로 반영되게 했다.
- **`Views/Bible/ChapterRelatedContentPanel.swift`(신규)** — 개요/메모/연구문서
  세 섹션. 사용자가 고른 상호작용 깊이("짧은 미리보기 포함")를 개요·메모 두
  섹션에 적용했다(연구문서는 파일명만 — 문서 내용 미리보기까지 만들면 형식마다
  다른 추출 텍스트를 다시 다뤄야 해서 범위를 좁혔다). 개요 항목을 누르면
  `onJumpToOutline` 콜백(아래), 메모는 기존 "메모 작성" 시트 재사용, 문서는
  `openWindow(id: "document-viewer", value:)`(S6과 같은 별도 창 진입점)로 연다.
- **`Views/Bible/BibleReadingView.swift`** — 사용자가 고른 배치("보조 사이드
  패널")를 `.inspector(isPresented:)`(iOS17+/macOS14+)로 그대로 구현했다 — 창
  폭이 넓으면 오른쪽에 상시 노출, 좁으면 모달처럼 뜨는 게 이 API의 기본 동작이라
  별도 반응형 레이아웃 코드가 필요 없었다. 툴바에 토글 버튼(`sidebar.trailing`
  심벌) 추가. "개요 화면 열기"는 `@FocusedValue(\.selectSection)`으로 앱 전체
  내비게이션을 개요(S8/S9) 섹션으로 전환한다 — `LastBiblePositionTracker`가 이미
  이 책/장으로 맞춰져 있으므로(`BibleReadingViewModel`이 책/장을 바꿀 때마다
  갱신) `OutlineView`가 열리면 정확히 지금 이 책/장으로 뜬다.
- **`Views/Navigation/PhoneTabView.swift`/`AppSection.swift`** — ⚠️ [발견된
  기존 공백 보완] `@FocusedValue(\.selectSection)`은 지금까지 macOS/iPadOS의
  `SidebarNavigationView`만 노출하고 있었고, 아이폰 탭바(`PhoneTabView`)는 고정
  `TabView`라 이 값을 받을 방법이 없었다 — 아이폰엔 메뉴바가 없어
  `AppCommands.swift`의 "개요로 이동" 같은 커맨드가 노출될 자리가 없었기 때문에
  지금까지 이 공백이 드러나지 않았을 뿐이다. 이번 패널의 "개요 화면 열기"는 실제
  화면 버튼이라 아이폰에서도 눌리므로, `PhoneTabView`에 `selectedTab: AppSection`
  상태 + `.focusedSceneValue(\.selectSection)`을 새로 연결했다. `AppSection.phoneTabBarSections`
  (memos/bibleReading/documents/outline만 — 탭바에 실제 탭이 있는 것만)를 추가해
  탭이 없는 값(`.search`/`.tagRelations`, "더보기" 후보지만 아직 미확정)이 오면
  무시하게 했다 — 지금 이 패널이 실제로 넘기는 값은 `.outline` 하나뿐이라 당장은
  문제가 되지 않는다.

### 정적 검증

같은 방식으로 이번에 손댄 9개 파일(`Documents.swift`/`DocumentUploadService.swift`/
`DocumentsViewModel.swift`/`DocumentsHomeView.swift`/`BibleReadingViewModel.swift`/
`BibleReadingView.swift`/`ChapterRelatedContentPanel.swift`(신규)/`AppSection.swift`/
`PhoneTabView.swift`) 전부 괄호/중괄호 균형이 맞았다. `LastBiblePositionTracker.shared`
(`@MainActor` 싱글턴)를 View 구조체의 일반 메서드 안에서 직접 참조하는 패턴은
`OutlineView.swift`의 기존 `setUpIfNeeded()`가 이미 같은 방식으로 쓰고 있어
안전하다고 확인했다. Swift 컴파일러 자체는 이 세션에서 쓸 수 없어 실제 빌드
확인은 못 했다 — 특히 `.inspector` API 사용, `@FocusedValue(\.selectSection)`을
새 컨텍스트(PhoneTabView)에서 받는 부분, `#Predicate`로 `BookOutline`/`ChapterSummary`를
거르는 부분은 이 세션에서 실행 검증이 불가능한 영역이라 Xcode ⌘B 결과를 알려주면
그걸 근거로 바로잡겠다.

## [2026-08-08, 이어서] 실제 빌드/런타임 오류 3건 수정

사용자가 Xcode에서 실제로 빌드·실행해 아래 3건을 보고했다 — 이 세션 정적 검증이
잡아내지 못했던(컴파일러가 없어서, 또는 런타임에만 드러나는) 실제 문제들이다.

1. **`BibleReadingViewModel.swift:219`/`:229` — "Cannot convert value of type
   '@MainActor @Sendable (String, Int) -> String' to expected argument type
   '(String) -> String'"**: `refreshRelatedContent()`에서
   `.first.map(Self.makePreview)`처럼 함수를 값으로 참조했는데,
   `makePreview(_:limit:)`가 `limit: Int = 80` 기본값을 갖고 있다는 게 문제였다 —
   **함수를 값으로 참조(클로저가 아니라 이름 그대로)하면 기본 인자 값은 적용되지
   않고, 그 함수는 모든 매개변수를 다 받는 시그니처(`(String, Int) -> String`)로만
   존재한다.** `.map`이 기대하는 건 인자 하나짜리 클로저라 타입이 맞지 않았다.
   `.map { Self.makePreview($0) }`로 바꿔 클로저 안에서 호출하도록 고쳤다 — 이러면
   `limit`의 기본값 80이 정상적으로 적용된다.
2. **`DocumentsHomeView.swift:241` — 런타임 "Unable to open a window when the
   app does not support multiple scenes"**: 근본 원인은 이 파일이 아니라
   `Info.plist`였다. 이 프로젝트의 `Info.plist`가 지금까지 완전히 비어
   있었다(`<dict/>`) — `openWindow(id:)`/`WindowGroup(id:)`로 별도 창을 여는
   기능(S1 "성경 조회 새 창", S6 문서 뷰어, S10 태그 관계, 그리고 이번에 추가한
   관련 콘텐츠 패널의 문서 열기)이 여러 곳에 이미 있었지만, iOS/iPadOS는
   `UIApplicationSceneManifest`가 Info.plist에 아예 없으면 기기 종류와 무관하게
   "이 앱은 다중 씬을 지원하지 않는다"고 판단해 `openWindow` 호출 자체를 거부한다.
   README가 이전부터 "⚠️ [플랫폼 검증 필요, 실기기 검증 없이 써 왔다]"고 반복
   기록해 뒀던 리스크가 실제로 여기서 걸린 것이다. `Info.plist`에
   `UIApplicationSceneManifest` → `UIApplicationSupportsMultipleScenes: true`를
   추가해 고쳤다 — macOS는 AppKit 윈도우 체계라 이 키를 아예 쓰지 않으므로(무시됨)
   기존 macOS 동작에는 영향이 없다. ⚠️ **확인 필요**: 이 세션은 Xcode
   프로젝트(.xcodeproj/project.pbxproj)에는 접근 권한이 없어서, 만약 타겟 빌드
   설정이 "Generate Info.plist File"(자동 생성)로 돼 있다면 이 수동 편집 파일
   자체가 빌드에 반영되지 않을 수 있다 — 그 경우 Xcode의 타겟 설정 → Info 탭 →
   "Supports multiple windows" 체크박스(또는 Signing & Capabilities의 Scene
   Manifest 설정)를 직접 켜야 한다. 빌드 후에도 같은 오류가 나면 이 가능성부터
   확인해 달라.
3. **아이폰(하드웨어 자체가 다중 씬 미지원)에서의 잔여 리스크**: 위 수정으로
   "오류 자체"는 해결되지만, iPhone은 OS 차원에서 두 씬을 동시에 화면에 띄울 수
   없다는 사실은 그대로다 — `UIApplicationSupportsMultipleScenes`를 켠 뒤에는
   최소한 오류 없이 동작은 하겠지만, 정확히 어떻게 보일지(현재 화면이 대체되는지,
   다중작업 화면에 별도 인스턴스로 나타나는지)는 실기기 확인이 필요하다. 이번
   수정 범위 밖으로 남겨 둔다.

## [2026-08-08, 이어서 2] macOS 실기기 크래시 — AppKit "Update Constraints in
Window" 무한 루프

사용자가 실제 macOS 앱 실행 로그를 보고했다: `Bound preference
VerseMidYPreferenceKey tried to update multiple times per frame` 경고 두 번 직후
AppKit이 `FAULT: NSGenericException: The window has been marked as needing
another Update Constraints in Window pass, but it has already had more Update
Constraints in Window passes than there are views in the window`로 강제 종료됐다.

### 원인 추정

`VerseMidYPreferenceKey`는 S1의 스크롤 동기화(`ScrollSyncCoordinator.swift`)가
쓰는 기존 메커니즘이다 — 각 절 행이 `GeometryReader`로 자기 세로 중심(midY)을
`PreferenceKey`에 보고하고, `TranslationColumnView`가 뷰포트 중앙에 가장 가까운
절을 계산해 코디네이터에 "지금 중앙 절"로 보고하면, 다른 컬럼들이 그 절로 맞춰
스크롤한다. 이 자체는 이전 라운드(README "16. 스크롤 동기화 가드 타이밍 수정")에서
이미 한 번 다듬어진 기존 기능이다.

문제는 오늘 이 세션이 아니라 **바로 이전 라운드**(S1 절 선택 → 클립보드 복사
기능)에서 생겼다고 판단했다: `selectedVerses: Set<Int>`를 `TranslationColumnView`에
새로 넘기면서, 절 하나를 탭해 선택을 토글할 때마다 `viewModel.selectedVerses`가
바뀌고, 이게 화면에 보이는 모든 `TranslationColumnView`의 `body`를 다시 계산하게
만든다. 이때 `onToggleVerseSelection`/`onCreateMemo` 같은 클로저 프로퍼티는 값
비교가 안 되는 타입이라(함수는 `Equatable`이 아님) SwiftUI가 "이 행은 안
바뀌었으니 건너뛰자"고 안전하게 판단하지 못하고, 화면에 보이는 절 행 전체를 다시
레이아웃한다 — 그 과정에서 각 행의 `GeometryReader`가 부동소수점 미세 오차로 매번
살짝 다른 midY 값을 보고하면, 화면 중앙과 거의 같은 거리에 있는 두 절(예: 5절,
6절) 사이에서 "가장 가까운 절" 판정이 흔들려 실제 절 번호가 반복적으로 바뀐 것처럼
보고된다. 그때마다 다른 컬럼들이 서로 다른 목표 절로 번갈아 스크롤 애니메이션을
걸면서(`respondToSyncEvent`) 레이아웃 무효화가 겹겹이 쌓였고, 결국 AppKit이 같은
윈도우에 대해 "뷰 개수보다 많은 Update Constraints 패스"를 감지하고 안전 장치로
크래시시킨 것으로 보인다. 즉, 이 스크롤 동기화 파이프라인은 원래 "실제로 스크롤
중"일 때만 동작하도록 설계됐는데, 절 선택 기능이 "탭 한 번"으로도 같은 파이프라인을
반복 자극할 수 있는 새 경로를 만들어 버린 것이다.

⚠️ 이 인과관계는 이 세션이 Swift 컴파일러/Instruments 없이 로그와 코드만으로
추론한 것이라 100% 확정은 아니다 — 다만 정확히 이 조합(선택 토글 → 전체 재렌더 →
GeometryReader 지터 → 스크롤 동기화 폭주)이 관찰된 증상과 정확히 들어맞고, 이
경로 자체가 이전 라운드(절 선택 기능 추가) 전에는 존재하지 않았다는 점에서 가장
근거가 뚜렷한 설명이라고 판단했다.

### 수정

- **`Views/Bible/TranslationColumnView.swift`** — `reportCenterVerseIfNeeded()`가
  코디네이터에 보고하는 부분을 **50ms 디바운스**로 바꿨다(`guardReleaseWorkItem`과
  같은 `DispatchWorkItem` 취소·재예약 패턴). 실제 스크롤은 값이 연속적으로
  바뀌므로 50ms 지연이 체감되지 않지만, 탭 한 번으로 생기는 순간적인 지터는 이
  디바운스 창 안에서 계속 취소·재예약되다가 최종적으로 안정된 값 하나만
  코디네이터에 전달된다 — 그러면 다른 컬럼들이 짧은 시간 안에 여러 목표로 번갈아
  스크롤을 거는 상황 자체가 없어진다.
- ⚠️ **범위 밖으로 남긴 것**: 절 선택이 왜 전체 행을 다시 레이아웃하게 만드는지의
  근본 원인(클로저 프로퍼티 때문에 SwiftUI가 행 단위로 재렌더링을 건너뛰지
  못하는 것) 자체는 고치지 않았다 — 이 부분을 고치려면 각 행을 `.equatable()`로
  감싸거나 클로저 대신 값 타입 콜백 식별자를 쓰는 등 더 큰 구조 변경이 필요한데,
  이 세션은 컴파일 확인이 불가능해 검증 안 된 구조 변경보다는 실제 크래시
  경로(디바운스 없는 즉시 보고)를 직접 끊는 쪽이 더 안전하다고 판단했다.

### 정적 검증

`TranslationColumnView.swift` 괄호/중괄호 균형 확인, 이상 없음. 이 수정은
런타임 타이밍(디바운스, 애니메이션, 실기기 레이아웃 지터)에 관한 것이라 이
세션의 정적 검증(괄호 균형, 타입 추론)만으로는 실제 크래시가 재발하지 않는다는
것까지 확인할 수 없다 — 실기기에서 절 선택을 빠르게 여러 번 탭해 보고 크래시가
재발하는지 알려주면 그걸 근거로 다시 조정하겠다.

## [2026-08-08, 이어서 3] 같은 크래시가 앱 실행 직후(조작 전)에도 재현 — 진단
정정, `.inspector` → `.sheet`로 발표 방식 변경

사용자가 같은 크래시 로그를 다시 보고했는데, 이번엔 "앱 실행시 아이콘은 뜨지만
응답없음 상태에서 변하지 않음"이라고 명시했다 — **절을 탭하기도 전에, 앱을 켜자마자
발생한다.** 바로 위 절의 진단("절 선택 탭 → 전체 재렌더 → 스크롤 동기화 폭주")은
디바운스로 대응했지만 탭 자체를 전제로 한 설명이었다 — 조작 없이 재현된다는 건 그
진단이 틀렸거나 적어도 원인의 전부가 아니었다는 뜻이다.

### 진단 정정

이 세션에서 가장 최근에, 그리고 구조적으로 가장 크게 바뀐 지점을 다시 짚었다 —
S1 화면에 `.inspector(isPresented:)`를 새로 붙인 것("이 장의 관련 콘텐츠" 패널,
바로 위 라운드에서 신설). `NavigationSplitView`(사이드바) 안의 상세 화면에 또
다른 분할 패널(`.inspector`)을 얹는 구성은 macOS AppKit 쪽에서 레이아웃 제약
협상이 꼬이는 사례가 실제로 보고되는 조합이다 — 특히 `.inspector`는 **닫혀
있을 때도** 그 자리를 위한 레이아웃 협상을 계속 유지해야 해서, `NavigationSplitView`
+ `ScrollView`/`LazyVStack`(S1 본문, GeometryReader 기반 스크롤 동기화까지 겹침)와
동시에 있으면 초기 창 레이아웃이 안정되기 전에 서로 "더 필요하다"는 제약 갱신을
주고받으며 무한 루프에 빠질 수 있다. 앱을 켜자마자 재현된다는 것과 정확히 들어맞는
설명이다.

⚠️ 이 진단도 100% 확정은 아니다 — 이 세션은 Xcode를 실행할 수 없어 `.inspector`를
빼고 실제로 크래시가 사라지는지 직접 재현·검증하지 못했다. 다만 (1) 이 크래시가
이 기능을 추가한 라운드 이후 처음 보고됐고, (2) 조작 없이 앱 실행만으로 재현된다는
점에서, 지금까지 이 앱에서 문제없이 여러 번 검증된 `.sheet`(메모 편집, 설정,
번역본 가져오기 등) 대신 `.inspector`를 새로 도입한 게 가장 유력한 원인이라고
판단했다.

### 수정

- **`Views/Bible/BibleReadingView.swift`** — `.inspector(isPresented:)`를
  `.sheet(isPresented:)`로 교체했다. `ChapterRelatedContentPanel`을
  `NavigationStack`으로 감싸고 "닫기" 툴바 버튼을 추가했다(다른 시트들과 같은
  패턴). 툴바 아이콘도 "고정 패널"을 암시하던 `sidebar.trailing`에서
  `list.bullet.rectangle.portrait`로 바꿨다. **트레이드오프**: 사용자가 원래
  요청한 "창 폭이 넓으면 오른쪽에 상시 노출"이라는 배치는 포기했다 — 지금은
  아이폰이든 맥이든 항상 시트(모달)로 뜬다. 크래시 없이 동작하는 걸 우선했다.
- 관련 콘텐츠 시트 안에서 메모를 탭하면(`onSelectMemo`) 이 시트를 먼저 닫고
  (`isRelatedContentPresented = false`) 나서 메모 편집 시트를 연다 — 같은 뷰에
  달린 두 `.sheet` 모디파이어를 동시에 띄울 수는 없어서, SwiftUI가 순서대로
  (닫힘 애니메이션 후) 열게끔 순서를 맞췄다.
- 지난 라운드의 스크롤 동기화 디바운스(50ms)는 그대로 남겨 뒀다 — 원인이
  아니었더라도 손해는 없는 안전한 방어 코드이고, 실제로 탭이 잦은 상황에서의
  지터를 줄이는 효과는 여전히 유효하다.

### 정적 검증

`BibleReadingView.swift` 괄호/중괄호 균형 확인, 이상 없음. `.sheet`가 `.inspector`
보다 훨씬 많이 검증된 API라는 점(이 앱 안에서만도 6곳 이상에서 문제없이 쓰임)이
이 변경의 가장 큰 근거지만, 이 세션은 Xcode를 실행할 수 없어 "크래시가 실제로
사라지는지"는 확인하지 못했다 — 실기기에서 앱을 다시 실행해 정상적으로 뜨는지,
그리고 툴바의 "관련 콘텐츠" 버튼을 눌러 시트가 정상적으로 열리고 닫히는지 알려주면
그걸 근거로 다음 단계를 판단하겠다. 만약 이 변경 후에도 같은 크래시가 재현되면
`.inspector`는 원인이 아니었다는 뜻이므로, 그때는 스크롤 동기화(GeometryReader
기반 `VerseMidYPreferenceKey`) 자체를 더 근본적으로 다시 설계해야 할 가능성을
열어 둬야 한다.

## [2026-08-08, 이어서 4] `.inspector` 제거 후에도 동일 크래시 — 진짜 원인
발견: 툴바를 가진 뷰 안에서 읽은 `@FocusedValue`

사용자가 `.inspector` → `.sheet` 교체 후에도 **완전히 같은 증상**(앱 실행 직후
"응답없음"으로 멈췄다가 크래시)을 다시 보고했다. 이번 크래시 로그는 훨씬
결정적이었다 — 스택트레이스에 `ToolbarBridge.preferencesDidChange` →
`AppKitToolbarStrategy.willReturnUpdates` →
`Toolbar.LocationStorage.updatedVendedItems(newFocusedValues:)` →
`invalidateProperties(_:mayDeferUpdate:)` → `NSHostingView.requestUpdate` →
`setNeedsUpdateConstraints` 순서가 명시적으로 찍혀 있었다 — **포커스 값
(focused value)이 바뀔 때마다 툴바가 다시 계산되고, 그 재계산이 레이아웃 무효화를
또 일으키는 루프**라는 뜻이다. `.inspector`는 애초에 원인이 아니었다(제거해도
안 없어진 게 그 증거).

### 진짜 원인

이번 라운드가 S1의 관련 콘텐츠 패널에 "개요 화면 열기"를 만들면서
`@FocusedValue(\.selectSection)`(AppCommands.swift가 메뉴바 명령에 쓰던 것과
같은 메커니즘)를 그대로 재사용해 `BibleReadingContentView`(자체 `.toolbar`를
가진 뷰) 안에서 읽었다 — 이게 문제였다.

`SidebarNavigationView`는 `.focusedSceneValue(\.selectSection) { section in ... }`로
**클로저(함수 값)** 를 게시한다. 함수는 `Equatable`이 아니라서, `SidebarNavigationView.body`가
(다른 이유로, 예: `columnVisibility`/`isSettingsPresented` 변경) 다시 그려질
때마다 이 클로저가 매번 새 인스턴스로 만들어지고, SwiftUI는 이를 "포커스 값이
바뀌었다"고 판단한다. 이 값을 읽는 쪽이 **툴바가 없는** 곳(AppCommands.swift의
`Commands` 구조체)이면 문제가 없었다 — 메뉴바는 이 재계산 경로에 얽혀 있지
않기 때문이다. 그런데 이번에 새로 읽는 곳(`BibleReadingContentView`)이 **자체
툴바를 가진 뷰**였다 — "포커스 값이 바뀌었다"는 신호가 이 뷰의 툴바를
재계산하게 만들고, 툴바 재계산이 다시 레이아웃 무효화(`setNeedsUpdateConstraints`)를
일으키고, 그게 다시 포커스 값 재평가 경로를 자극하며 루프에 빠진 것으로 보인다.
앱을 켜자마자(사용자 조작 전에) 재현된 것도 설명된다 — `SidebarNavigationView`가
처음 렌더링되는 순간부터 이미 이 조건이 성립하기 때문이다.

⚠️ 이번에도 Xcode 없이 로그+코드만으로 추론한 것이지만, 크래시 로그 자체가
"Toolbar"와 "newFocusedValues"를 명시적으로 지목하고 있어 지난 두 번의 추정보다
훨씬 근거가 명확하다.

### 수정 — `AppNavigationRequest` 신설, `@FocusedValue` 대신 사용

- **`Services/AppNavigationRequest.swift`(신규)** — `LastBiblePositionTracker`와
  같은 원칙의 가벼운 `@MainActor @Observable` 싱글턴. `requestedSection: AppSection?`
  하나만 갖는다 — 평범한 `Equatable` 값이라 클로저 게시 특유의 "매번 바뀐 것으로
  보이는" 문제가 없다.
- **`Views/Bible/BibleReadingView.swift`** — `@FocusedValue(\.selectSection)`
  프로퍼티를 제거하고, `onJumpToOutline`에서 `AppNavigationRequest.shared.request(.outline)`을
  호출하도록 바꿨다.
- **`Views/Navigation/SidebarNavigationView.swift`** — `.onChange(of:
  AppNavigationRequest.shared.requestedSection)`을 추가해 `selection`을
  갱신하고 요청을 비운다(`clear()`). 기존 `.focusedSceneValue(\.selectSection)`
  게시는 그대로 남겨 뒀다 — AppCommands.swift의 메뉴바 명령("개요로 이동" 등)이
  여전히 그 경로를 쓰고, 그쪽은 툴바가 없는 `Commands` 구조체라 이 버그와
  무관하기 때문이다(원인이 확실치 않은 것까지 손대지 않는다는 원칙).
- **`Views/Navigation/PhoneTabView.swift`** — 지난 라운드에 추가했던
  `.focusedSceneValue(\.selectSection) { ... }`(이 파일이 값을 "게시"하는
  역할이었다)를 같은 이유로 `.onChange(of: AppNavigationRequest.shared.requestedSection)`로
  바꿨다. `AppSection.phoneTabBarSections` 필터링 로직은 그대로 유지.
- `.inspector`를 `.sheet`로 바꾼 이전 라운드의 변경은 그대로 남겨 뒀다 — 원인이
  아니었더라도 `.sheet`가 이 앱에서 훨씬 많이 검증된 API라 되돌릴 이유가 없다.

### 정적 검증

`AppNavigationRequest.swift`(신규)/`BibleReadingView.swift`/
`SidebarNavigationView.swift`/`PhoneTabView.swift` 전부 괄호/중괄호 균형 확인,
이상 없음. `@FocusedValue(\.selectSection)`을 더 이상 읽지 않는 곳
(`BibleReadingContentView`)에 관련 참조가 남아있지 않은지도 다시 검색해 확인했다.
이번에도 Xcode 실행이 불가능해 실제로 크래시가 사라지는지는 확인하지 못했다 —
이 진단이 크래시 로그의 "Toolbar"/"newFocusedValues" 문구와 정확히 들어맞는
가장 근거가 뚜렷한 설명이라고 판단했지만, 다시 실행해서 여전히 응답없음이
발생하면 그 로그를 그대로 알려달라 — 그땐 스크롤 동기화 자체(GeometryReader
기반 `VerseMidYPreferenceKey`)를 근본적으로 재설계하는 쪽을 검토해야 한다.

## [2026-08-08, 이어서 5] 원인이 확인됐으니 `.inspector`(보조 사이드 패널)로 복귀

사용자가 "인스펙터 보조패널로 바꿀 수는 있는가?"라고 물었다 — 바로 위 라운드에서
`.inspector`를 의심해 `.sheet`로 바꿨다가, 진짜 원인이 `@FocusedValue(\.selectSection)`였음이
드러났으므로(그 부분은 `AppNavigationRequest`로 이미 교체 완료) `.inspector`
자체는 다시 써도 안전하다고 판단했다.

- **`Views/Bible/BibleReadingView.swift`** — `.sheet(isPresented:)` +
  `NavigationStack` + "닫기" 툴바 버튼 조합을 걷어내고, 원래 요청대로
  `.inspector(isPresented:)`로 되돌렸다(사용자가 처음 고른 "보조 사이드 패널" —
  창 폭이 넓으면 오른쪽에 상시 노출, 좁으면 모달처럼 접힘). 툴바 버튼도
  `list.bullet.rectangle.portrait`(시트 방식에 맞춰 바꿨던 아이콘)에서
  `sidebar.trailing`으로, 동작도 `= true`(항상 열기)에서 `.toggle()`(열기/닫기
  겸용)로 되돌렸다. `onJumpToOutline`/`onSelectMemo`는 `AppNavigationRequest`
  기반 그대로 유지 — 이건 `.inspector`/`.sheet` 어느 쪽을 쓰든 필요한, 이번
  크래시의 실제 수정 사항이라 손대지 않았다. `.sheet`였을 때 필요했던 "메모
  시트를 열기 전에 관련 콘텐츠 시트부터 닫는다"는 처리(`isRelatedContentPresented = false`
  후 `memoBeingCreated = memo`)는 `.inspector`에선 두 개가 동시에 떠 있어도
  서로 다른 프레젠테이션 방식(고정 패널 vs 모달)이라 충돌하지 않으므로
  제거했다.

### 정적 검증

`BibleReadingView.swift` 괄호/중괄호 균형 확인, 이상 없음. `AppNavigationRequest`
관련 코드는 전혀 손대지 않았으므로 지난 라운드의 크래시 수정 효과는 그대로
유지된다는 전제다 — 다시 실행해서 정상적으로 뜨는지, 툴바의 "관련 콘텐츠"
버튼을 눌렀을 때 창 폭이 넓으면(맥/아이패드 가로) 오른쪽에 패널이 상시 노출되는
느낌으로 뜨는지 확인해 주면 좋겠다.

## [2026-08-08, 이어서 6] S1 위치 유지 / 장 이동 단축 / 조회 이력 / 내장 글꼴 4건

사용자 요청 4가지를 한 번에 반영했다.

### (1) S1 마지막 위치 유지

"[성경 조회]에서 다른 메뉴로 이동 후 돌아오면 직전 장을 유지"는 이미 존재하던
`LastBiblePositionTracker`(메모리 전용 싱글턴)를 `BibleReadingViewModel.init`이
전혀 참조하지 않아서 안 됐던 것 — `selectBook`/`goToChapter`는 갱신만 하고
있었다.

- **`Views/Bible/BibleReadingView.swift`** — `initialChapter: Int = 1` →
  `Int? = nil`로 변경. `Int = 1` 기본값으로는 "장을 안 정했다"와 "1장을 정했다"를
  구분할 수 없어 이 변경이 필요했다.
- **`Views/Bible/BibleReadingViewModel.swift`** — `init`의 분기를 3단계로:
  `initialBook`이 있으면(SearchView.swift의 검색 결과 탭 — 명확한 사용자 의도)
  그대로 열고, 없으면 `LastBiblePositionTracker.shared.bookId/chapter`로
  복원하고, 그마저도 없으면(앱 첫 실행) 기존처럼 첫 번째 책 1장. 사이드바/탭바가
  매개변수 없이 여는 `BibleReadingView()` 호출부(3곳)는 전부 이 로직을 타므로
  코드 변경이 필요 없었다.

### (2) 장 이동 단축

"장만 이동하려면 성경 버튼 클릭 후 같은 책을 다시 클릭해야 함"이 실제 버그였다 —
`BookGridPicker`가 항상 책 목록에서 시작했다.

- **`Views/Bible/BookChapterPicker.swift`** — `BookGridPicker`에
  `init(books:initialBook:onSelect:)`를 추가해 `_pendingBook = State(initialValue:
  initialBook)`으로 시작 상태를 정할 수 있게 하고, `BookChapterPicker.body`의
  `.popover`가 `selectedBook`을 넘기도록 바꿨다. "책 목록" 뒤로가기(`ChapterGrid.onBack`)는
  그대로 남아 있어 다른 책으로 바꾸는 경로는 그대로다.

### (3) 조회 이력(히스토리)

"년월일 시분초, 100개 캡" — 새 SwiftData 모델 + 서비스 + 시트를 추가했다.

- **`BibleResearchPlatform/Sources/BibleResearchModels/Models/BibleReadingHistory.swift`(신규)** —
  `BibleReadingHistoryEntry`(`id`/`bookId`/`chapter`/`viewedAt`). 정책 로직 없는
  순수 데이터 모델(`BookOutlineDeduplication`처럼 정책은 모델 밖에 둔다는 관례).
- **`BibleResearchSchema.swift`** — `modelTypes`에 `BibleReadingHistoryEntry.self`
  등록(빠뜨리면 CloudKit 동기화에서 조용히 제외되므로 필수).
- **`BibleResearchPlatform/Sources/BibleResearchModels/Support/BibleReadingHistoryService.swift`(신규)** —
  `record(bookId:chapter:context:)`(직전 항목과 완전히 같으면 중복 기록 안 함 +
  100개 초과분 자동 삭제)와 `trim(context:)`.
  `BibleReadingViewModel.init`이 `LastBiblePositionTracker`로 위치를 "복원"할
  때는 이 서비스를 호출하지 않는다 — `selectBook`/`goToChapter`(실제 사용자
  이동)에서만 기록해야, 다른 화면과 성경 조회를 오갈 때마다 같은 위치가 이력에
  중복으로 쌓이는 걸 막을 수 있다.
- **`Views/Bible/BibleReadingViewModel.swift`** — `selectBook`/`goToChapter`
  끝에 `BibleReadingHistoryService.record(...)` 호출 추가, `fetchHistory()`(최신순
  전체 조회)와 `jumpToHistoryEntry(_:)`(히스토리 탭 → `selectBook` 재사용, 이
  이동 자체도 새 이력으로 다시 기록됨 — 의도된 동작) 추가.
- **`Views/Bible/BibleReadingHistorySheet.swift`(신규)** — `yyyy-MM-dd HH:mm:ss`
  포맷(요청 그대로 "년월일 시분초")으로 목록을 보여주는 시트. 항목 탭 → 이동 +
  시트 닫힘.
- **`Views/Bible/BibleReadingView.swift`** — 툴바에 "조회 이력"(시계 아이콘)
  버튼과 `.sheet(isPresented: $isHistoryPresented)` 추가. `.inspector`(관련
  콘텐츠)와는 별개의 표시 방식(시트) — 이력은 "가끔 열어보는" 용도라 상시
  노출할 필요가 없다고 판단했다.

### (4) 내장 Paperlogy 폰트를 기본 글꼴로

`fonttools`로 9개 .ttf 파일의 name 테이블을 직접 확인한 결과, 9개 굵기가
"Paperlogy"라는 하나의 family 아래 배리에이션이 아니라 **굵기마다 완전히
독립된 family/PostScript 이름**을 가진다는 걸 확인했다(예: family="Paperlogy 4
Regular", PostScript="Paperlogy-4Regular"). 그래서 `Font.custom`에는 family
이름이 아니라 PostScript 이름을 쓴다(Apple 문서가 공식적으로 기대하는 값).

- **`Services/BundledFontRegistrar.swift`(신규)** — `BundledFonts`(9개
  PostScript 이름 + 사람이 읽기 좋은 표시 이름 + `defaultPostScriptName =
  "Paperlogy-4Regular"`)와 `BundledFontRegistrar`(앱 시작 시 1회
  `CTFontManagerRegisterFontsForURL`로 `.process` 스코프 등록, macOS/iOS
  공통 API라 플랫폼 분기 없음)를 담았다. `Fonts` 폴더가 "폴더 참조"든 "그룹"이든
  (번들 루트로 평탄화되든) 둘 다 찾아보도록 이중 조회한다. `View.appDefaultFont()`
  확장도 여기 함께 둠.
  - ⚠️ **[Xcode에서 직접 해야 하는 일]** 이 세션은 `.xcodeproj`를 열거나 수정할
    수 없다(사실 이 폴더에서 `.xcodeproj` 자체를 찾지 못했다 — 연결된 폴더
    범위 밖에 있는 것으로 보인다). **Fonts 폴더를 Xcode에서 File > "Add Files
    to \"JBCHBibleResearch\"..."로 앱 타겟에 추가하고 타겟 멤버십을 켜야
    실제로 폰트가 동작한다.** 추가하지 않아도 앱이 깨지지는 않는다 — 등록이
    조용히 스킵되고 `Font.custom(...)`이 시스템 기본 글꼴로 자동 대체된다.
- **`Services/UserSettingsStore.swift`** — `bibleFontName` 기본값을 "System"에서
  `BundledFonts.defaultPostScriptName`으로 변경. `bibleBodyFont`/
  `bibleVerseNumberFont`는 그대로 — "System" 비교 로직만 그대로 살아있고
  나머지 이름은 전부 `.custom(...)` 경로를 타므로 수정이 필요 없었다.
- **`Views/Settings/SettingsView.swift`** — "글꼴" Picker를 "내장 기본 글꼴"(9개,
  `BundledFonts.entries`)과 "시스템"(기존 `NSFontManager`/`UIFont` 목록,
  "Paperlogy"로 시작하는 항목은 중복 방지로 걸러냄) 두 섹션으로 나눠 내장
  글꼴이 항상 위에 오게 했다.
- **`Views/Navigation/RootView.swift`** — 메인 창에 `.appDefaultFont()` 적용.
- **`JBCHBibleResearchApp.swift`** — `init()` 맨 앞에서
  `BundledFontRegistrar.registerBundledFontsIfNeeded()` 호출. "성경 조회 새
  창"/"태그 관계"/"문서 뷰어"/(macOS)환경설정 WindowGroup에도 각각
  `.appDefaultFont()`를 붙였다(Scene마다 SwiftUI 환경이 독립적이라 RootView
  하나에만 붙이면 다른 창엔 적용되지 않는다).
  - ⚠️ **[범위]** "앱에서 쓰는 글꼴 전부"를 문자 그대로 달성한 건 아니다 —
    `.appDefaultFont()`는 SwiftUI 환경값이라 그 아래에서 `.font(...)`를
    명시적으로 다시 지정하지 않은 `Text`/`Label`에만 적용된다. 이 프로젝트
    곳곳에 이미 있는 `.font(.headline)`/`.font(.caption)` 같은 명시적 지정은
    이 환경값보다 우선해 계속 시스템 폰트로 보인다. 그 모든 명시적 지정을
    찾아 고치는 건 파일 수십 개를 건드리는 훨씬 큰 별도 작업이라 이번 범위엔
    포함하지 않았다 — 필요하면 별도로 요청해 달라.
  - S1(성경 조회) 본문/절 번호 글꼴은 `UserSettingsStore.bibleFontName`(환경설정
    "글꼴" 피커, 위 (4)) 설정을 그대로 따른다 — `.appDefaultFont()`(앱 전체
    기본값)와는 별개의, 우선순위가 더 높은 설정이다.

### 정적 검증

새/수정 파일 전부(`BibleReadingView.swift`/`BibleReadingViewModel.swift`/
`BookChapterPicker.swift`/`BibleReadingHistorySheet.swift`/
`BundledFontRegistrar.swift`/`UserSettingsStore.swift`/`SettingsView.swift`/
`RootView.swift`/`JBCHBibleResearchApp.swift`/`BibleReadingHistory.swift`/
`BibleReadingHistoryService.swift`/`BibleResearchSchema.swift`) 괄호/대괄호/중괄호
개수를 스크립트로 확인 — `UserSettingsStore.swift`만 소괄호가 119/122로 안
맞는데, 전부 한글 주석 안의 괄호(코드가 아님)에서 비롯된 기존부터 있던 차이라
실제 문법 문제는 아니다(수정 전 원본도 같은 패턴이었음을 확인했다). 이번에도
Xcode 실행이 불가능해 실제 빌드/실기기 동작은 확인하지 못했다 — 특히 Fonts
폴더의 타겟 멤버십은 위에 적은 대로 사용자가 Xcode에서 직접 확인해야 한다.

## [2026-08-08, 이어서 7] 번들 번역본 이름 변경 + 다중 번역본 스크롤 동기화 점검

### 번들 번역본 표시 이름 변경

사용자 요청 — "[기본 번역본(KRV)] 이름을 [개역한글]로 변경". `code`("KRV")는
바꾸지 않았다 — 다른 곳(`BibleReferenceStore`의 version_code 매칭 등)이 이
값을 참조할 수 있어 표시 이름만 바꾸는 것이 안전하다(이 파일 상단의 기존
⚠️ 주석과 같은 이유).

- **`Services/TranslationBootstrap.swift`** — `displayName: "개역 한글(KRV)"`를
  `bundledDisplayName = "개역한글"` 상수로 빼고 그 값을 쓰도록 변경. 이미 이전
  실행에서 레코드가 만들어진 사용자(기존 "개역 한글(KRV)"로 저장된 레코드가
  CloudKit에 이미 있는 경우)를 위해, `ensureBundledTranslationRegistered`의
  "이미 있으면 건너뛴다"는 기존 멱등 가드에 마이그레이션 분기를 추가했다 —
  기존 레코드가 있는데 `displayName`이 최신 값과 다르면 고쳐 쓰고 저장한다.
  이 분기가 없었다면 새로 설치한 사용자에게만 새 이름이 보이고, 이미 쓰던
  사용자에게는 옛 이름이 계속 남는 문제가 생겼을 것이다.

### 다중 번역본 스크롤 동기화 재점검

사용자 요청 — "두 개 이상 번역본을 조회할 때 왼쪽 성경을 스크롤하면 다른
성경도 이동할 수 있도록. 확인해서 적용할 것." 코드를 다시 훑어보니 이
기능(`ScrollSyncCoordinator`/`TranslationColumnView`의 중앙 기준 스크롤 동기화)
자체는 이미 온전히 구현돼 있었다 — 다만 "[2026-08-08, 이어서 2]" 라운드에서
크래시를 막으려고 넣은 **순수 디바운스**가, 정작 "실제로 스크롤하는 동안 계속
따라가야 한다"는 원래 요구사항을 깨뜨리고 있었다는 걸 이번에 다시 보고 확인했다.

- **문제**: `reportCenterVerseIfNeeded()`의 디바운스는 "50ms 안에 새 이벤트가
  또 들어오면 타이머를 취소하고 다시 예약"하는 방식이다. 실제 스크롤 중에는
  `verseMidYs`가 매 프레임(약 16ms)마다 갱신되어 50ms보다 훨씬 짧은 간격으로
  계속 새 이벤트가 들어오므로, 이 타이머는 스크롤이 완전히 멈출 때까지 단
  한 번도 발화하지 못한다 — 즉 다른 컬럼이 "스크롤하는 동안" 전혀 따라오지
  않고, 스크롤을 다 멈춘 뒤에야 한 번 점프하는 것처럼 보였다(원래 크래시
  수정 자체는 유효했지만, 사이드 이펙트로 이 회귀가 생겼다).
- **`Views/Bible/TranslationColumnView.swift`** — 디바운스를 **스로틀**로
  바꿨다. `lastCenterVerseReportedAt: Date?`를 새로 추가해, 마지막 실제 보고
  이후 `centerReportThrottleInterval`(50ms)이 지났으면 즉시 보고하고(리딩
  엣지 — 연속 스크롤 중엔 이 분기가 대략 50ms마다 반복 발화해 "따라가는"
  느낌을 준다), 아직 안 지났으면 남은 시간만큼만 미뤄서 예약한다(트레일링
  엣지 — 기존과 같은 취소·재예약 패턴이라 탭 한 번으로 생기는 순간적인 지터를
  흡수하는 원래 크래시 수정 효과는 그대로 유지된다).

### 정적 검증

`TranslationBootstrap.swift`/`TranslationColumnView.swift` 괄호/대괄호/중괄호
균형 확인, 이상 없음. 이번에도 Xcode 실행이 불가능해 실제로 스크롤 중 다른
컬럼이 실시간으로 따라오는지는 실기기에서 확인해 줘야 한다 — 여러 번역본을
등록한 상태(S12에서 2개 이상 추가)에서 왼쪽 컬럼을 천천히/빠르게 스크롤해
보고, 오른쪽 컬럼(들)이 스크롤 도중에 함께 움직이는지, 크래시 없이 안정적인지
알려주면 좋겠다.

## [2026-08-08, 이어서 8] 검색창 문구 / 아이패드 UI 누락 / 앱 재시작 위치 복원 /
스크롤 동기화 재작성

사용자가 4가지를 한 번에 요청했다. 마지막 항목(스크롤 동기화)은 바로 위
라운드에서 "고쳤다"고 보고한 지 얼마 안 돼 다시 "동기화 안 됨"으로 들어와서,
이번엔 땜질(디바운스→스로틀)이 아니라 메커니즘 자체를 다시 설계했다.

### (1) 검색창 placeholder 문구 변경

- **`Views/Bible/BookChapterPicker.swift`** — `TextField("예: 요한복음 3장,
  ㅇㅎㅂㅇ 3", ...)` → `TextField("예:창세기1, 요3", ...)`(요청 문구 그대로).
  겸사겸사 `frame(minWidth: 160)`을 `frame(minWidth: 120, maxWidth: 200)`으로
  줄였다 — 아래 (2)에서 이 텍스트필드가 툴바 밖(전체 너비 인셋)으로 옮겨지긴
  하지만, 고정폭을 줄여 두면 좁은 화면에서 유리하다.

### (2) 아이패드에서 성경검색/장이동 UI가 아예 안 보임

- **원인**: `chapterNavigationControls`(이전/다음 장 버튼 + 책/장 선택 버튼 +
  자유 텍스트 검색창 + "이동" 버튼)를 툴바 `.principal` 자리에 넣고 있었다.
  macOS는 툴바 폭이 넉넉해 문제없이 보였지만, 아이패드(특히 세로/Split View
  멀티태스킹)는 내비게이션 바의 principal 영역 폭이 훨씬 좁고 양옆에 다른
  툴바 버튼(관련 콘텐츠/조회 이력/새 창 등)도 있어, 이 HStack 전체가 들어갈
  자리가 없으면 iOS가 통째로 안 보이게 처리하는 것으로 보인다 — "기능이
  아예 없다"는 증상과 정확히 들어맞는다.
- **`Views/Bible/BibleReadingView.swift`** — 이 컨트롤을 툴바에서 빼고
  `.safeAreaInset(edge: .top)`로 옮겼다(하단 절 선택 액션바와 같은 원칙 —
  이 파일에 이미 있던 검증된 패턴). 화면 전체 너비를 그대로 쓸 수 있어 좁은
  화면에서도 잘리지 않는다. `chapterNavigationControls`에 `.frame(maxWidth:
  .infinity)`를 추가해 principal 자리에 있을 때와 같은 가운데 정렬을
  유지했다.

### (3) 앱을 완전히 종료했다 켜도 마지막 성경 위치 복원

- **`Services/LastBiblePositionTracker.swift`** — 원래 이 트래커는 "메모리
  전용, 영구 저장 불필요"(screens.md 13.1, 새 메모 기본 좌표용)로 설계됐다.
  지난 라운드에 이 트래커를 S1 "마지막 위치 복원"에도 재사용했는데,
  메모리 전용이라 실제 프로세스 재시작(앱 완전 종료 후 재실행)까지는 버티지
  못했다 — 이번 요청("앱을 종료했다 켜면...")은 명시적으로 이 지속성을
  요구한다. `UserSettingsStore`와 같은 패턴(`UserDefaults` 백업)으로 바꿔,
  `bookId`/`chapter`를 `update(...)` 호출 때마다 같이 저장하고 `init`에서
  읽어 온다. 공개 API(`bookId`/`chapter`/`update(bookId:chapter:)`)는
  그대로라 다른 호출부(`BibleReadingViewModel`/`OutlineViewModel` 등) 수정은
  필요 없었다.

### (4) 스크롤 동기화 — 디바운스/스로틀 땜질 대신 네이티브 API로 재작성

바로 이전 라운드에서 디바운스를 스로틀로 바꿔 "고쳤다"고 봤는데, 사용자가
다시 "동기화 안 됨"으로 보고했다. 같은 자리를 두 번째로 손대는 것이라, 이번엔
근본 설계를 다시 봤다: 애초에 "각 절 행이 `GeometryReader`로 자기 좌표를
`PreferenceKey`에 보고하고, 이 뷰가 매번 `verseMidYs` 중 뷰포트 중앙과 가장
가까운 절을 손으로 계산"하는 방식 자체가, 이번 세션에서만 크래시 1건(부동
소수점 지터)과 동기화 지연 1건(디바운스가 스크롤 중엔 절대 안 풀리는 문제)을
연달아 냈다 — 같은 뿌리에서 나온 반복되는 증상이라고 판단했다.

- **`Views/Bible/TranslationColumnView.swift`** — SwiftUI가 iOS17/macOS14
  (이 프로젝트의 최소 배포 버전과 정확히 일치)부터 제공하는 네이티브 API
  `ScrollView.scrollPosition(id:anchor:)`로 전체 메커니즘을 재작성했다:
  - `@State private var centerVerseID: Int?` 하나로 리더/팔로워 역할을 모두
    처리한다 — `.scrollPosition(id: $centerVerseID, anchor: .center)`가
    스크롤에 맞춰 "지금 뷰포트 중앙에 있는 절 번호"를 자동으로 읽어 주고
    (리더), 반대로 이 값에 대입하면 그 절이 중앙에 오도록 알아서 스크롤도
    해 준다(팔로워 — 기존 `ScrollViewReader.scrollTo` 대체).
  - `VerseMidYPreferenceKey`/`ViewportHeightPreferenceKey`(PreferenceKey 2개),
    `verseMidYs`/`viewportHeight` 상태, `coordinateSpaceName`/
    `.coordinateSpace(name:)`, 디바운스/스로틀 타이머
    (`centerReportWorkItem`/`lastCenterVerseReportedAt`)를 전부 제거했다 —
    프레임마다 부동소수점으로 "가장 가까운 절"을 재계산하던 로직 자체가
    없어졌으므로, 그 계산의 미세한 흔들림에서 비롯됐던 크래시 원인도
    구조적으로 사라졌다.
  - `respondToSyncEvent`(팔로워)는 `isProgrammaticScroll` 가드 +
    `guardReleaseWorkItem`(취소·재예약) 패턴은 그대로 유지했다 — 이건
    "내가 프로그램적으로 스크롤하는 동안 내 스크롤을 다시 리더 보고로
    착각하지 않는다"는, 위치 감지 방식과 무관하게 여전히 필요한 안전장치다.
  - **새로 추가한 안전장치**: `.scrollPosition(id:)`는 값을 계속 들고 있는
    바인딩이라, 장을 이동해도(예: 15절을 보다가 다음 장으로 이동) 새 장에
    우연히 같은 절 번호(15절)가 있으면 그리로 다시 스크롤해 버릴 수 있다
    (이전 `ScrollViewReader` 방식엔 이런 "기억"이 없어서 없던 문제). 그래서
    `localizedBookChapterLabel`(책/장이 바뀔 때마다 함께 바뀌는 문자열)의
    변화를 감지해 `centerVerseID`를 nil로 리셋하는 `resetForChapterChange()`를
    추가했다 — 장 이동 시 항상 맨 위부터 보여주는 기존 동작을 지킨다.

### 정적 검증

4개 파일(`BookChapterPicker.swift`/`BibleReadingView.swift`/
`LastBiblePositionTracker.swift`/`TranslationColumnView.swift`) 괄호/대괄호/
중괄호 균형 확인, 이상 없음. 제거한 `VerseMidYPreferenceKey`/
`ViewportHeightPreferenceKey`를 다른 파일에서 참조하는 곳이 없는지도 검색해
확인했다. `ScrollView.scrollPosition(id:anchor:)`는 이 프로젝트의 표명된
최소 배포 버전(macOS 14+/iOS 17+)에 정확히 맞는 정식 API이지만, 이 세션은
Xcode를 실행할 수 없어 실제 동작(특히 스크롤 중 실시간 추종, 장 이동 시
리셋이 의도대로 되는지)은 실기기에서 확인해 줘야 한다 — 이번에도 안 되면
그때는 이 방식 자체보다 `ScrollSyncCoordinator`의 이벤트 전파 경로(예:
`@Observable` 변경 감지 타이밍) 쪽을 의심해야 할 것 같다.

## [2026-08-08, 이어서 9] 스크롤 동기화 — `.scrollTargetLayout()` 누락 수정

바로 위 재작성(네이티브 `.scrollPosition(id:)`로 교체) 직후에도 사용자가
"안 됨"으로 다시 보고했다. 이번엔 사용자가 요구사항 자체를 다시 명확히
설명해 줬다 — "성경 왼쪽 본문 화면 영역 정가운데에 눈에 보이지 않는 기준선이
있고, 그 선을 왼쪽 본문의 절이 지날 때, 다른 번역본도 각 본문 영역의
가운데로 같은 절이 위치하도록" — 이건 원래 이해하고 구현한 것과 같은
요구사항이었다(오해는 아니었다). 그래서 "이해가 틀렸다"가 아니라 "구현에
빠진 게 있다"는 뜻으로 받아들이고 코드를 다시 봤다.

### 원인

`.scrollPosition(id: $centerVerseID, anchor: .center)`만 붙이고
`.scrollTargetLayout()`을 빠뜨렸다. Apple의 공식 사용 패턴은 항상 id를
매기는 레이아웃 컨테이너(여기선 `LazyVStack`)를 `.scrollTargetLayout()`으로
명시적으로 "스크롤 타깃 레이아웃"으로 표시하는 것을 전제로 한다 —
`ScrollView { LazyVStack { ForEach { ... } }.scrollTargetLayout() }
.scrollPosition(id: $id)` 형태. 이 표시가 없으면 `.scrollPosition(id:)`
바인딩 자체가 사실상 갱신되지 않거나 신뢰할 수 없게 동작한다 — "네이티브
API로 통째로 바꿨는데도 여전히 안 됐던" 이유가 이거였다.

### 수정

- **`Views/Bible/TranslationColumnView.swift`** — `columnScrollView`의
  `LazyVStack`에 `.scrollTargetLayout()`을 추가했다(`.padding()` 앞,
  `ForEach` 바로 다음). 파일 상단 주석에도 이 실수와 수정 내용을 기록해
  뒀다 — 같은 파일에서 짧은 기간에 크래시 수정 → 디바운스/스로틀 → 네이티브
  API 재작성 → 이번 수정까지 네 번째 변경이라, 다음에 이 파일을 다시 볼
  사람(나 자신 포함)이 전체 맥락을 한 번에 파악할 수 있게 해 두는 게
  중요하다고 판단했다.

### 정적 검증

`TranslationColumnView.swift` 괄호/대괄호/중괄호 균형 확인, 이상 없음.
`.scrollTargetLayout()`은 `.scrollPosition(id:)`와 마찬가지로 iOS17/macOS14
이상에서 쓸 수 있는 정식 API라 이 프로젝트의 최소 배포 버전과 맞다. 이
세션은 여전히 Xcode를 실행할 수 없어, 이번에는 정말 실기기에서 "왼쪽 컬럼을
스크롤하면 다른 컬럼도 같은 절이 가운데로 오는지" 확인해 주면 좋겠다 — 그
결과에 따라 다음 단계를 판단하겠다(된다면 종료, 안 된다면
`ScrollSyncCoordinator`의 이벤트 전파나 `@Observable` 감지 타이밍 쪽을
봐야 한다).

## [2026-08-08, 이어서 10] 아이패드 [성경 조회] 레이아웃 보완 2건

사용자가 스크롤 동기화 수정에 "OK"로 확인해 준 뒤, 아이패드 S1 화면에서
남은 두 가지를 추가로 보고했다.

### 상단의 알 수 없는 넓은 빈 영역

- **원인**: 바로 이전 라운드에서 S1에만 `.safeAreaInset(edge: .top)`로
  자체 상단 바(이전/다음 장 + 책/장 선택 + 검색창)를 새로 추가했는데,
  `.navigationTitle("성경 조회")`가 iOS 기본값인 "큰 제목(large title)"
  모드로 표시되고 있었다 — 큰 제목 영역(글자는 작아 보여도 위아래 여백이
  상당함) 위에 이 새 커스텀 바까지 얹히면서 헤더 전체가 비정상적으로
  커졌다. 다른 화면(내 메모/연구문서/개요 등)은 이런 추가 상단 바가 없어서
  같은 큰 제목 모드를 쓰고 있었어도 눈에 띄게 크지 않았다 — 그래서 이번에
  S1에서만 처음 두드러진 문제다.
- **`Views/Bible/BibleReadingView.swift`** — `#if os(iOS) /
  .navigationBarTitleDisplayMode(.inline) / #endif`를 추가해 S1만 컴팩트한
  제목 모드로 강제했다(macOS엔 이 모디파이어 자체가 없어 조건부 컴파일로
  감쌌다). 다른 화면들은 지금까지 이 문제로 보고된 적이 없어 건드리지
  않았다 — 범위를 S1로만 좁혀 불필요한 변경을 피했다.

### 사이드바를 닫으면 다시 열 방법이 없음

- **원인**: 사이드바를 닫아 화면을 넓히는 토글은 기존에도 있었지만
  (`AppCommands.swift`의 메뉴 커맨드 ⌥⌘S, macOS 전용), 아이패드는 메뉴
  바 자체가 없어 그 경로를 못 쓴다. 그리고 설정(톱니바퀴) 버튼이 있는
  사이드바 자체의 툴바는, 정작 사이드바가 닫혀 있으면 그 사이드바가 화면에서
  완전히 사라지므로 같이 사라진다 — "닫고 나면 다시 열 방법이 없다"는
  증상과 정확히 들어맞는다.
- **`Views/Navigation/SidebarNavigationView.swift`** — `detail:` 쪽(사이드바
  열림/닫힘과 무관하게 항상 화면에 남아 있는 영역)의 `NavigationStack`에
  `.toolbar { ToolbarItem(placement: .navigation) { ... } }`로 사이드바
  토글 버튼(`sidebar.leading` 아이콘)을 새로 추가했다 — `columnVisibility`를
  `.detailOnly` ↔ `.all`로 토글하는, 기존 메뉴 커맨드와 같은 동작이다.
  `#if os(iOS)`로 감싸 아이패드/아이폰에만 적용했다 — macOS는 시스템이
  사이드바 있는 창에 자동으로 툴바 토글 버튼을 제공하는 것으로 알려져
  있고, 사용자가 macOS에서는 이 문제를 보고한 적이 없어 기존 동작을
  건드리지 않기 위해서다(아이폰은 애초에 `NavigationSplitView`를 안 쓰므로
  이 코드 경로 자체를 안 타 실질적으로는 아이패드에만 영향).

### 정적 검증

`BibleReadingView.swift`/`SidebarNavigationView.swift` 괄호/대괄호/중괄호
균형 확인, 이상 없음. 이번에도 Xcode 실행이 불가능해 실기기 확인이
필요하다 — 아이패드에서 S1 상단 헤더 높이가 정상으로 보이는지, 사이드바를
닫은 뒤 detail 화면 좌상단의 새 아이콘으로 다시 열 수 있는지 확인해 주면
좋겠다.

## [2026-08-08, 이어서 11] S1 창/툴바 5건 — 새 창 크래시, 아이폰 스와이프 정렬,
플랫폼별 툴바 아이콘 정리

사용자가 5가지를 한 번에 요청했다. 마지막 4가지가 서로 얽혀 있어(같은 3개
아이콘을 플랫폼/창 종류별로 다르게 노출) `BibleReadingView.swift`의 툴바
로직을 한 번에 정리했다.

### (1) `BibleReadingView.swift:327 Unable to open a window when the app does
not support multiple scenes`

아이폰에서 "성경 조회 새 창" 버튼을 누르면 나는 크래시 — 아이폰은 멀티 씬(여러
창)을 지원하지 않는다. 근본 원인 조사(Info.plist 등) 대신, 사용자가 바로 아래
(4)에서 "아이폰에서는 이 아이콘 자체를 빼 달라"고 요청했으므로 **버튼을 아예
없애는 것**으로 원인과 요청을 동시에 해결했다 — 없는 버튼은 누를 수 없으니
크래시도 날 수 없다.

### (2) 아이폰 — 실시간 스크롤 동기화 대신 스와이프 시 1회 정렬

"아이폰에서 스크롤 실시간 동기화는 안 해도 됨. 단 스와이프해서 번역본을 넘길
때, 다음 번역본의 절 위치가 넘기기 전 화면 정가운데 절 위치가 되도록."

- **`Views/Bible/TranslationColumnView.swift`** — 새 파라미터 2개 추가:
  `respondsToSyncEvents: Bool = true`(false면 다른 컬럼이 보고해도 이 컬럼은
  실시간으로 안 따라간다 — 리더 보고(`reportCenterVerseIfNeeded`)는 그대로
  둔 채 팔로워 응답만 끈다), `pendingCenterAlignment: Int? = nil`(부모가
  "지금 이 절로 맞춰라"라고 1회성으로 명령하면 애니메이션 없이 즉시
  `centerVerseID`에 반영).
- **`Views/Bible/BibleReadingView.swift`** — `phoneColumns`의 `TabView`에
  `selection: $selectedPhoneColumnID`를 추가하고(각 페이지는 `column.id`로
  태그), `respondsToSyncEvents: false`를 넘긴다. 새 `PhoneAlignmentTarget`
  (파일 스코프 private 구조체, `columnID`+`verse`)로 `.onChange(of:
  selectedPhoneColumnID)`에서 "방금까지 보던 컬럼이 리더로서 마지막 보고한
  중앙 절"(`coordinator.latestEvent?.verse` — 아이폰은 한 번에 한 컬럼만
  스크롤 가능하므로 이 값이 곧 "방금 보던 페이지의 중앙 절"이다)을 새로
  보이는 컬럼에 그대로 넘긴다. 아직 아무도 스크롤한 적이 없으면
  (`latestEvent == nil`) 아무 것도 하지 않아 각 컬럼이 원래 위치(장 첫머리)를
  유지한다.

### (3)~(5) 플랫폼/창 종류별 툴바 아이콘 3개(관련 콘텐츠·조회 이력·새 창) 정리

세 요청을 종합하면 규칙은 이렇다: **관련 콘텐츠(인스펙터)/조회 이력은 "주
창"에서는 모든 플랫폼에 보이고, macOS에서 "새 창"으로 연 보조 창에서만
빠진다. "성경 조회 새 창"은 macOS에서만 보인다(아이폰/아이패드는 뺀다).**

- **`Views/Bible/BibleReadingView.swift`** — `BibleReadingView`에
  `isPrimaryWindow: Bool = true`를 추가(기본값 true라 기존 호출부는 전부
  그대로 "주 창"으로 동작), `BibleReadingContentView`까지 그대로 전달.
  `toolbarContent`를 `if isPrimaryWindow { 관련 콘텐츠 + 조회 이력 }` /
  `if isMac { 새 창 }`으로 재구성했다 — `isMac`은 `isPhone`과 같은 자리에
  새로 추가한 계산 프로퍼티(`#if os(macOS)`).
- **`JBCHBibleResearchApp.swift`** — `WindowGroup(id: "bible-reading")`(새
  창 전용 Scene)에서만 `BibleReadingView(isPrimaryWindow: false)`로 명시
  호출. 사이드바/탭바가 매개변수 없이 그냥 `BibleReadingView()`로 쓰는
  기존 호출부(주 창)는 전혀 안 바뀐다.
- 결과: **아이패드**는 `isPrimaryWindow`가 항상 true(이 플랫폼엔 "새 창"
  진입점 자체가 없어져 보조 창을 만들 방법이 없다)이고 `isMac`이 false라
  관련 콘텐츠+조회 이력만 남고 새 창은 빠진다 — 겸사겸사 툴바 아이콘 개수가
  줄어 지난 라운드에 의심했던 "좁은 화면에서 아이콘이 넘쳐 안 보이는" 문제도
  완화될 것으로 기대한다. **아이폰**도 `isMac`이 false라 새 창만 빠지고
  관련 콘텐츠+조회 이력은 그대로 남는다(요청에 이 둘을 빼 달라는 내용은
  없었다). **macOS 주 창**은 3개 다 그대로, **macOS 보조 창**(새 창으로 연
  것)은 관련 콘텐츠+조회 이력만 빠지고 새 창 아이콘은 남아(보조 창에서
  또 새 창을 열 수 있어야 하므로) `isMac` 조건에만 걸린다.

### 정적 검증

`TranslationColumnView.swift`/`BibleReadingView.swift`/
`JBCHBibleResearchApp.swift` 괄호/대괄호/중괄호 균형 확인, 이상 없음.
`BibleReadingContentView(...)` 호출부가 이 파일 안 한 곳(`BibleReadingView.body`)
뿐이라 새 필수 파라미터(`isPrimaryWindow`) 추가로 컴파일이 깨질 다른 호출부가
없는지도 확인했다. 이번에도 Xcode 실행이 불가능해 실기기 확인이 필요하다 —
아이폰에서 새 창 아이콘이 없어졌는지(크래시 재현 자체가 안 되는지), 번역본
2개 이상 등록한 상태에서 아이폰 스와이프 시 정렬이 되는지, 아이패드 툴바에
관련 콘텐츠·조회 이력 아이콘 2개만 보이는지, macOS에서 새 창으로 연 창에는
그 2개가 빠져 있는지 확인해 주면 좋겠다.

## [2026-08-08, 이어서 12] 아이패드 아이콘 정렬 3건

바로 이전 라운드로 아이패드 툴바를 관련 콘텐츠/조회 이력 2개로 줄였는데도,
사용자가 "아이콘이 여전히 (제대로) 안 보인다"는 취지로 다시 3가지를
요청했다. 이번 라운드에서 확실히 고칠 수 있는 것과, 여전히 실기기로만 확인
가능한 부분을 구분해서 진행했다.

### 사이드바 토글 아이콘 — 사이드바가 닫혀 있을 때만 보이도록

- **사용자 보고**(이전 라운드): "왼쪽 사이드바 바로 오른쪽에 왼쪽 사이드바
  아이콘이 또 있음" — 아이패드는 사이드바가 열려 있을 때 자체적으로/근처에
  이미 접기 동작을 제공하는 것으로 보이는데, 지난 라운드에 추가한 내
  버튼이 사이드바가 열려 있을 때도 항상 보여서 중복으로 보였다.
- **`Views/Navigation/SidebarNavigationView.swift`** — 이 버튼을
  `if columnVisibility == .detailOnly { ... }`로 감싸 사이드바가 실제로
  닫혀 있을 때만 나타나게 했다("다시 여는 용도"라는 원래 목적에 정확히
  맞춘 것). 버튼을 누르면 항상 `.all`로 여는 동작만 남기고, 토글(열림↔닫힘)
  동작은 뺐다 — 이제 이 버튼 자체가 "닫혀 있을 때만 등장하는 열기 버튼"이라
  토글할 필요가 없어졌다.

### 오른쪽 상단 아이콘(관련 콘텐츠·조회 이력)이 안 보임 — 배치를 더 명시적으로

- **진단**: 코드상으로는 `isPrimaryWindow`가 true면(아이패드는 항상 true)
  두 아이콘이 `toolbarContent`에 포함되도록 이미 짜여 있었다 — 그런데도
  "안 보인다"는 보고가 반복돼, 항목 개수 문제가 아니라 **배치(placement)
  자체의 문제**일 가능성을 봤다. `.primaryAction`은 iOS에서 "적응형" 배치라,
  툴바 폭이 빠듯하면 iOS가 항목을 자동으로 "···" 더 보기 메뉴 안에 접어
  버릴 수 있다 — 아이콘이 사라진 게 아니라 더 보기 메뉴 뒤에 숨어 있었을
  가능성이 있다.
- **`Views/Bible/BibleReadingView.swift`** — 새 계산 프로퍼티
  `trailingIconPlacement`를 추가해, iOS에서는 `.topBarTrailing`(더 명시적으로
  "항상 상단 바 오른쪽"을 요구하는 배치)을, macOS에서는 기존 `.primaryAction`을
  쓰도록 했다. 관련 콘텐츠/조회 이력/새 창/번역본 선택 4개 `ToolbarItem` 전부
  이 프로퍼티로 통일했다.
- ⚠️ [불확실성] 이 배치 변경이 실제 원인이 맞는지는 이 세션에서 확인할 수
  없다 — 여전히 아이콘이 안 보이면, 다음엔 화면을 스크린샷으로 보여주면
  훨씬 정확하게 진단할 수 있다(더 보기 메뉴 안에 있는지, 완전히 사라졌는지,
  다른 곳에 겹쳐 있는지 등은 코드만 보고는 구분하기 어렵다).

### 상단 공백 영역을 절반으로

- **`Views/Bible/BibleReadingView.swift`** — 상단 세이프에어리어 인셋 바
  (`chapterNavigationControls`)의 세로 패딩을 8pt→4pt로 줄였다. 다만 이
  값 하나만으로 사용자가 실제로 보는 "공백"이 정확히 절반이 될지는 확실치
  않다 — `.navigationBarTitleDisplayMode(.inline)`(지난 라운드에 이미 적용)
  이후에도 여전히 크게 느껴진다면, 원인이 이 커스텀 바의 패딩이 아니라 다른
  곳(예: `.inspector` modifier가 아이패드에서 차지하는 여백, 또는 시스템
  네비게이션 바 자체의 최소 높이)일 수 있다 — 이 역시 스크린샷이 있으면
  더 정확히 짚을 수 있다.

### 정적 검증

`SidebarNavigationView.swift`/`BibleReadingView.swift` 괄호/대괄호/중괄호
균형 확인, 이상 없음. 뒤 2건(아이콘 배치, 여백 절반)은 이 세션이 실제 화면을
볼 수 없어 "가장 가능성 높은 원인에 대한 조치"이지 확정 진단은 아니다 — 이번
수정 후에도 문제가 남아 있으면, 다음번엔 아이패드 S1 화면 스크린샷을 함께
보내주면 훨씬 빠르게 정확한 원인을 찾을 수 있다.

## [2026-08-08, 이어서 13] 아이콘 실종의 진짜 원인 — NavigationStack 컨테이너에 붙인 `.toolbar`

바로 이전 라운드(이어서 12)의 `.primaryAction`→`.topBarTrailing` 배치 변경
후에도 사용자가 "여전히 안 보임"이라고 재보고했다. 이번엔 코드만 보고
네 번째 추측을 하는 대신, 사용자에게 아이패드 화면 스크린샷을 요청했다.

### 스크린샷으로 확인된 사실

스크린샷 상단(사이드바 오른쪽, `chapterNavigationControls` 커스텀 바
윗부분)이 완전히 텅 비어 있었다 — 아이콘만 없는 게 아니라 **"성경 조회"
타이틀 텍스트 자체도 안 보였다.** 아이콘이 "···" 더 보기 메뉴에 접힌
것이었다면 최소한 타이틀은 남아 있어야 하는데, 타이틀까지 사라졌다는 건
`.primaryAction`의 적응형 축소(overflow) 문제가 아니라 **툴바/타이틀 선언
자체가 통째로 무효화되고 있었다**는 뜻이다.

### 근본 원인

`SidebarNavigationView.swift`의 `NavigationSplitView`의 `detail:` 클로저가
아래 구조였다:

```swift
detail: {
    NavigationStack {
        detailView(for: selection ?? .bibleReading)
    }
    .toolbar { ... 사이드바 재표시 버튼 ... }   // ← NavigationStack "컨테이너"에 형제로 붙임
}
```

"사이드바 재표시" 버튼용 `.toolbar`를 `NavigationStack` **컨테이너 자체**에
(그 안의 콘텐츠가 아니라) 형제 modifier로 붙여 놨다 — 이걸 지난 두 라운드
동안 놓쳤다. `detailView(for:)`가 반환하는 `BibleReadingView` →
`BibleReadingContentView`가 그보다 훨씬 안쪽에서 자기만의
`.navigationTitle`/`.toolbar`를 선언하는데, 바깥쪽 컨테이너 경계에 붙은
`.toolbar`(설령 조건이 `false`라 빈 내용을 반환할 때도)가 안쪽 콘텐츠가
선언한 타이틀/툴바 전체를 밀어내 버리는 것으로 보인다 — 스크린샷 당시
사이드바가 열려 있어(`columnVisibility == .all`) 이 조건이 `false`였고
버튼 자체는 안 보이는 게 맞았지만, 그 "빈 `.toolbar` 선언"의 존재만으로도
안쪽 콘텐츠의 타이틀·아이콘이 통째로 사라진 것이다.

이게 사실이라면 지난 라운드의 `.primaryAction`→`.topBarTrailing` 변경이
전혀 효과가 없었던 이유도 설명된다 — 애초에 배치가 문제가 아니라 아이콘이
툴바 시스템에 도달하지도 못하고 있었기 때문이다. 타임라인도 들어맞는다 —
이 "사이드바 재표시 버튼"이 추가된 바로 그 라운드부터 "아이패드에서 아이콘이
안 보인다"는 보고가 시작됐다(이어서 10/11).

### 수정

`.toolbar`를 `NavigationStack` 컨테이너가 아니라, 그 안의 루트 콘텐츠
(`detailView(for:)`가 반환하는 뷰) 자체에 붙이도록 옮겼다:

```swift
NavigationStack {
    detailView(for: selection ?? .bibleReading)
        #if os(iOS)
        .toolbar { if columnVisibility == .detailOnly { ... } }
        #endif
}
```

이러면 이 버튼과 `BibleReadingContentView`의 타이틀/툴바가 같은 콘텐츠
트리 안에서 정상적으로 합쳐질 것으로 기대한다.

### 정적 검증

`SidebarNavigationView.swift` 괄호/대괄호/중괄호 균형 확인 — 67/67, 5/5,
35/35, 이상 없음. 이 진단은 스크린샷이라는 실제 증거에 근거해 가능성이
높지만, 여전히 컴파일/실기기 실행으로 검증된 것은 아니다 — 이번에도
"성경 조회" 타이틀과 관련 콘텐츠/조회 이력 아이콘이 정상적으로 보이는지
실기기로 확인이 꼭 필요하다.

## [2026-08-08, 이어서 14] 증상 동일 — 범위를 "이 화면 전용 modifier"로 좁힘

이어서 13의 수정(`.toolbar`를 NavigationStack 컨테이너에서 콘텐츠 쪽으로
이동) 후에도 사용자가 "증상 동일함"이라고 재보고했다. 이번엔 원인 후보를
좁히기 위해 사용자에게 비교 대상을 요청했다 — "내 메모" 화면(같은
`SidebarNavigationView`의 detail 열에 똑같이 떠 있고, 그 안에서도 목록
콘텐츠가 `HStack` 안에 중첩돼 있어 구조가 비슷하다)도 타이틀/아이콘이
안 보이는지.

### 확인된 사실

"내 메모" 화면은 타이틀("내 메모")과 툴바 아이콘(새 메모 버튼)이 **정상
표시됨**. 이로써 이어서 13의 가설(“NavigationStack 컨테이너에 걸린
`.toolbar`가 detail 열 전체를 깨뜨린다”)은 틀렸다는 게 확인됐다 —
`SidebarNavigationView`의 detail 열 구조 자체는 정상이고, 문제는
"성경 조회" 화면(`BibleReadingView`/`BibleReadingContentView`)에만 있는
무언가로 범위가 좁혀졌다.

### 새 용의자 — `.inspector(isPresented:)`

"내 메모" 화면과 "성경 조회" 화면의 modifier 체인을 비교하면, 가장 눈에
띄는 차이는 `.inspector(isPresented:)`다 — 이 modifier는 이 프로젝트에서
성경 조회 화면에만 쓰이고(관련 콘텐츠 패널), 과거에도 이미 한 번 실기기
크래시의 (처음엔 잘못 의심됐다가 나중에 다른 원인으로 밝혀진) 용의자였을
만큼 이 화면에서 유독 까다로운 이력이 있다.

기존 코드는 `.navigationTitle`/`.toolbar`를 modifier 체인의 **앞쪽**(즉
`.inspector`보다 안쪽 레이어)에 선언하고 있었다:

```swift
VStack { ... }
    .navigationTitle("성경 조회")
    .toolbar { toolbarContent }
    .safeAreaInset(...) ... 여러 개
    .inspector(isPresented: $isRelatedContentPresented) { ... }   // ← 타이틀/툴바를 감싸버림
    .sheet(...) ...
    .focusedSceneValue(...) x3
```

SwiftUI에서 `.inspector`처럼 콘텐츠를 감싸 새로운 레이아웃 컨테이너를
만드는 modifier가 `.navigationTitle`/`.toolbar` **바깥쪽**에 적용되면,
안쪽에서 선언한 타이틀/툴바 프리퍼런스가 이 중간 레이어에 막혀 그 바깥의
진짜 `NavigationStack`까지 전달되지 못할 가능성이 있다 — "내 메모"
화면에는 이런 감싸는 modifier가 없어 문제가 드러나지 않았다는 가설과
들어맞는다.

### 수정

`.navigationTitle`/`.navigationBarTitleDisplayMode`/`.toolbar` 세 개를
modifier 체인의 **가장 뒤**(= `.inspector`/`.sheet`들을 포함해 전부를
감싸는 가장 바깥쪽 레이어)로 옮겼다. 이제 이 뷰가 최종적으로 만들어내는
전체 결과물에 타이틀/툴바가 씌워지므로, 중간의 `.inspector` 레이어와
무관하게 바깥쪽 `NavigationStack`에 곧바로 전달될 것으로 기대한다.

### 정적 검증

`BibleReadingView.swift` 괄호/대괄호/중괄호 균형 확인 — 199/199, 29/29,
80/80, 이상 없음. "내 메모" 화면과의 비교로 용의자를 좁혔다는 점에서
이전 두 라운드보다 근거는 탄탄해졌지만, `.inspector`가 정말 원인인지는
실기기 확인 전까지는 확정할 수 없다. 이번에도 안 되면, 다음 단계로는
`.inspector` 자체를 완전히 잠시 빼고(관련 콘텐츠 패널 기능을 잠깐
포기하고) 타이틀/툴바가 돌아오는지만 확인하는 이분 탐색이 필요하다 —
그러면 `.inspector`가 범인인지 100% 확정할 수 있다.

### ✅ 실기기 확인 완료

사용자가 아이패드 실기기에서 "아이콘과 타이틀이 보임"으로 확인해줬다.
`.navigationTitle`/`.toolbar`를 `.inspector`보다 뒤(바깥쪽 레이어)로
옮기는 게 정확한 근본 수정이었다는 게 실기기로 검증됐다 — 이어서
12(배치를 `.primaryAction`→`.topBarTrailing`으로 변경)와 이어서
13(`.toolbar`를 NavigationStack 컨테이너에서 콘텐츠로 이동)은 둘 다
틀린 가설에 근거한 수정이었고, 진짜 원인은 이어서 14에서 찾은
"`.inspector`가 감싸는 위치보다 안쪽에 `.navigationTitle`/`.toolbar`를
선언하면 그 프리퍼런스가 바깥쪽 NavigationStack까지 전달되지 못한다"였다.
이 화면에 `.inspector`처럼 콘텐츠를 감싸는 modifier를 새로 추가할 일이
생기면, 항상 `.navigationTitle`/`.toolbar`보다 안쪽(먼저)에 두어야 한다는
점을 기억해 둘 필요가 있다.

## [2026-08-08, 이어서 15] 타이틀 크게 볼드체로

사용자 요청 — "타이틀을 좀더 크게 볼드체로 할 수 있도록". iOS의 기본
inline 타이틀은 시스템이 고정된 폰트(17pt 안팎, semibold 정도)로 그려
앱이 직접 굵기/크기를 바꿀 수 없다.

### 구현

`toolbarContent`에 `.principal` 자리 `ToolbarItem`을 추가해, 실제로 눈에
보이는 타이틀을 커스텀 `Text("성경 조회").font(.title2).fontWeight(.bold)`로
덮어썼다 — iOS(아이폰/아이패드) 전용이다. `.navigationTitle("성경 조회")`
자체는 그대로 남겨뒀다(윈도우 전환기/음성 제어 등 시스템이 내부적으로
참조하는 제목 문자열은 계속 필요). macOS는 창 제목 표시줄이 이미
`.navigationTitle`을 그대로 보여주고 있고 그건 시스템 chrome이라 앱이
굵기를 바꿀 수 없다 — 같은 글자를 툴바에 또 하나 굵게 띄우면 창 제목이
중복돼 보일 수 있어 macOS는 건드리지 않았다.

### 정적 검증

`BibleReadingView.swift` 괄호/대괄호/중괄호 균형 확인 — 208/208, 30/30,
81/81, 이상 없음. `.principal` 자리는 과거 `chapterNavigationControls`
(이전/다음 장 + 책/장 선택 + 검색창 전체 HStack)를 넣었을 때 폭이 좁아
통째로 사라진 적이 있는 자리인데, 이번엔 짧은 텍스트 한 줄만 넣어 그
문제가 재현될 가능성은 낮다고 본다 — 그래도 실기기에서 크기가 잘리거나
겹치지 않는지 확인이 필요하다.

## [2026-08-08, 이어서 16] 구간 주석(형광펜/표시/메모/관주) 설계 논의 — 아직 구현 전, 설계만

사용자 요청 — "성경구절의 특정단어, 특정 표현에 관주를 넣거나, 표시를 하거나,
메모를 넣거나, 형광펜을 칠하고 싶음. 설계단계에서부터 논의를 했으면 함."
지금까지의 메모/복사 기능은 전부 "절 전체" 단위였는데, 이번 요청은 그보다
한 단계 더 세밀한 "절 안의 특정 구간" 단위 주석이라 완전히 새로운 층이다.
사용자가 명시적으로 "설계 단계부터 논의"를 요청했으므로, 이 라운드는 코드
작성 없이 설계만 정리하고 사용자 확인을 기다린다.

### 공통 뼈대 — "구간 주석"

관주/표시/메모/형광펜 네 가지 모두 "구절 텍스트의 특정 구간을 고르고, 거기에
무언가(색/기호/글/링크)를 붙인다"는 동일한 구조를 공유한다. 그래서 4개의
독립 기능이 아니라, 공통 앵커 필드를 가진 몇 개의 모델로 설계한다.

**공통 앵커 필드** (아래 각 모델이 전부 갖는다):
- `translationCode: String` — 번역본마다 단어/어순이 다르므로, 구간 앵커는
  구조적으로 번역본에 종속될 수밝에 없다(개역한글에서 칠한 형광펜이 NKJV에
  그대로 나타날 수 없다).
- `bookId: Int`, `chapter: Int`, `verse: Int`
- `rangeStart: Int`, `rangeEnd: Int` — 그 절 원문 텍스트 안의 문자 오프셋.
- `anchorText: String` — 주석을 만든 시점에 그 구간에 있던 실제 텍스트
  스냅샷. 나중에 번역본 데이터가 고쳐져 오프셋이 안 맞아도, 이 텍스트를
  본문에서 다시 찾아 자동으로 재정렬하는 "자가 치유" 용도(Kindle/애플
  북스 하이라이트가 쓰는 방식과 동일한 원리).

### 모델 3종

1. **`VerseHighlight`(신설)** — 형광펜 + 표시를 하나로 묶는다. 공통 앵커
   필드 + `style` (색상 태그를 가진 하이라이트 / 밑줄·박스 같은 표시 스타일
   — 표시의 정확한 시각적 형태는 실제 UI를 만들 때 다시 확인).
2. **`VerseCrossReference`(신설)** — 관주. 공통 앵커 필드(단, 번들 데이터는
   구간 정보가 없을 수 있어 `rangeStart`/`rangeEnd`/`anchorText`는 옵셔널로
   두고, nil이면 "절 전체에 대한 관주"로 처리) + `source: enum {user,
   bundled}` + `targets: [BibleChapterRef]`(기존 `LectureNote.chapterRefs`가
   쓰는 모델 재사용).
3. **`UserMemo`(기존 모델 확장)** — `rangeStart: Int?`, `rangeEnd: Int?`,
   `translationCode: String?`, `anchorText: String?`를 옵셔널로 추가한다.
   전부 옵셔널이라 기존 절 단위 메모(현재 데이터)는 전혀 영향받지 않는다 —
   nil이면 지금처럼 "절 전체" 메모, 채워지면 "그 표현"에 대한 메모.

### 구간 선택 UX — "구절 확대보기"

사용자가 직접 제안한 방식을 그대로 채택한다: 기존 "절 전체 탭 → 선택"
제스처(복사 기능이 쓰는 것)는 그대로 두고, 하단 액션바(`verseSelectionActionBar`)에
"구절 확대보기" 버튼을 추가한다(정확히 절 1개가 선택돼 있을 때만 활성화).
누르면 그 절 하나만 크게 보여주는 화면이 뜨고, 거기서 텍스트를 드래그해
구간을 고른다.

⚠️ [기술 메모] SwiftUI의 `Text(...).textSelection(.enabled)`는 드래그
선택 UI 자체는 시스템이 공짜로 제공하지만, "사용자가 정확히 몇 번째~몇
번째 글자를 골랐는지"를 코드로 읽어올 방법이 없다(애플이 그 API를 공개하지
않음) — 우리는 그 정확한 시작/끝 인덱스가 있어야 `rangeStart`/`rangeEnd`를
저장할 수 있으므로, 이 용도로는 못 쓴다. 대신 `UITextView`(iOS)/
`NSTextView`(macOS)를 `UIViewRepresentable`/`NSViewRepresentable`로 감싼
작은 컴포넌트를 새로 만들어 `selectedRange`를 직접 읽는 방식이 필요하다 —
이 프로젝트에 없던 새로운 조각이지만, 표준적이고 검증된 패턴이다. 구간을
다 고르면 그 위에 작은 액션 메뉴(형광펜 색상 / 표시 / 메모 작성 / 관주
연결)가 뜬다.

### 렌더링(읽기 모드)

확대보기는 "새로 만들 때"만 쓰고, 이미 만들어진 하이라이트/표시/관주
마커는 평소 읽기 화면(`TranslationColumnView`)에도 바로 보여야 한다.
`VerseRow`의 평범한 `Text(verse.text)`를 `Text(AttributedString(...))`로
바꿔, 해당 구간에 배경색/밑줄 등 span 스타일을 입히는 방식으로 구현한다 —
기존 "절 전체 탭으로 선택" 제스처는 그대로 유지되고(인터랙션 레이어는
안 건드림), 렌더링 방식만 바뀐다. 관주는 구간 끝에 작은 위첨자 기호를
붙이고, 탭하면 연결된 구절 목록 팝오버 + 이동 기능을 제공한다.

### 관주 데이터 — 사용자 작성 + 번들 내장, 둘 다 (사용자 선택)

사용자 작성 경로는 위 흐름(확대보기 → 관주 연결 → 성경 좌표 검색)으로
바로 설계 가능하다. 번들 데이터 내장은 기존 번역본 가져오기
(`TranslationImportService`)와 비슷한 패턴의 가져오기 기능은 만들 수
있지만, **실제 관주 데이터셋(파일/DB) 자체는 이 세션이 임의로 구할 수
없다** — 특히 특정 성경 판본에 딸린 관주 체계는 출판사 저작권 대상일
가능성이 있어(공개 도메인인 것도 있고 아닌 것도 있음), 사용자가 가진
데이터 소스와 그 출처/라이선스를 확인해야 다음 단계(가져오기 파서) 설계가
가능하다. 그 전까지는 사용자 작성 경로부터 먼저 구현하는 게 합리적이라
본다.

### 형광펜 색상

기본 팔레트로 시작 — 노랑/초록/파랑/분홍/보라 5색을 제안한다(필요하면
주황을 더해 6색). 정확한 색상값은 실제 UI 붙일 때 확정한다.

### 동기화

전부 SwiftData `@Model` + CloudKit이라 기존 프로젝트 관례(to-many
relationship은 옵셔널 배열 타입 필수 등, `MemoFolder.swift`/`Tags.swift`
상단 주석 참고)를 그대로 따른다.

### 현재 상태

⚠️ 이 라운드는 설계 논의만 진행했고 코드는 아직 한 줄도 작성하지 않았다.
사용자의 확인/피드백을 받은 뒤 실제 모델·UI 구현에 들어간다.

## [2026-08-08, 이어서 17] 구간 주석(형광펜/표시/메모/관주) 실제 구현

사용자가 목업(화면 디자인) 확인 후 "ok, 구현할 것"으로 승인해, "이어서 16"
설계 논의대로 실제 구현에 들어갔다.

### 신설 모델 — `VerseAnnotations.swift`

`VerseHighlight`(형광펜 `.highlight` + 표시 `.mark`를 하나로 묶음, 색상은
`colorTag` 문자열로 저장)와 `VerseCrossReference`(관주, `source: user|bundled`
로 사용자 작성/번들 데이터 구분, `targets: [BibleVerseRef]`로 연결된 구절
목록)를 신설했다. 둘 다 공통 앵커(translationCode/bookId/chapter/verse/
rangeStart/rangeEnd/anchorText)를 갖는다 — 설계 논의 그대로. `UserMemo`에도
같은 앵커 필드 4개(rangeStart/rangeEnd/annotationTranslationCode/anchorText)
를 전부 옵셔널로 추가했다 — nil이면 기존처럼 절 전체 메모, 채워지면 구간
메모. `BibleResearchSchema.modelTypes`에 두 신설 모델을 등록했다(빠뜨리면
CloudKit 동기화 대상에서 조용히 빠지므로 이 파일 상단 주석이 항상 강조하는
지점).

### 구간 선택 UX — `SelectableVerseTextView.swift` + `VerseZoomView.swift`

설계 논의에서 확인한 대로, SwiftUI `Text(...).textSelection(.enabled)`는
선택된 정확한 범위를 코드로 못 읽어와 이 용도로 쓸 수 없다 — `UITextView`
(iOS)/`NSTextView`(macOS)를 `UIViewRepresentable`/`NSViewRepresentable`로
감싸 `selectedRange`를 직접 읽는 `SelectableVerseTextView`를 새로 만들었다.
`sizeThatFits(_:uiView:context:)`/`sizeThatFits(_:nsView:context:)`(iOS16+/
macOS13+ 공식 지점)를 구현해, `isScrollEnabled = false`인 텍스트뷰가
SwiftUI 레이아웃에 실제 높이를 알려주도록 했다.

"구절 확대보기"(`VerseZoomView`)는 `BibleReadingView.verseSelectionActionBar`
에 새로 추가한 "확대보기" 버튼(정확히 절 1개 선택 시에만 보임)으로 연다.
여러 번역본이 동시 표시 중이면 상단 세그먼트 피커로 번역본을 바꿀 수 있고
(주석은 번역본에 종속되므로), 드래그로 구간을 고르면 하단 액션바(형광펜
5색 + 표시 + 메모 + 관주)가 활성화된다.

- **형광펜/표시**: `viewModel.addHighlight(...)`를 바로 호출, 선택을
  비우고 시트는 열어 둔다(한 절에 여러 개를 연달아 표시할 수 있게).
- **메모**: `viewModel.createPhraseMemo(...)`로 구간 메모를 만든 뒤,
  확대보기 시트를 `dismiss()`하고 — 그 `.sheet`의 `onDismiss`에서
  `pendingPhraseMemo`를 확인해 기존 "메모 작성" 편집기(`MemoDetailView`,
  `memoBeingCreated`)를 그대로 재사용해 연다. **새 편집 UI를 따로 만들지
  않고 기존 절 단위 메모 편집기를 그대로 재사용했다** — `MemoDetailView`가
  `@Bindable var memo: UserMemo`만 받아 좌표 필드를 직접 건드리지 않으므로,
  구간 필드가 이미 채워진 메모를 넘기기만 하면 그대로 동작한다.
- **관주**: `CrossReferenceTargetPicker.swift`(신설) 시트를 열어 책/장/절을
  골라 여러 개를 추가한 뒤 한 번에 저장 — 인쇄본 관주가 "삼하7:12-16,
  시89:3-4"처럼 한 단어에 여러 구절을 나열하는 것과 같은 이유로, 하나씩만
  연결하게 제한하지 않았다.

### 읽기 모드 렌더링 — `VerseAnnotationRenderer.swift` + `TranslationColumnView.swift`

`VerseAnnotationRenderer.attributedContent(...)`가 절 원문 + 형광펜/표시
목록을 받아 `AttributedString`을 만든다. 저장된 오프셋이 지금 본문과 안
맞으면(번역본 데이터가 나중에 고쳐진 경우) `anchorText`로 본문을 다시
검색해 자리를 재조정하는 "자가 치유"를 구현했고, 그마저 못 찾으면 그
주석은 조용히 건너뛴다(설계 논의 그대로). 형광펜이 하나도 없는 절(대다수)
은 이 함수가 nil을 돌려줘 기존과 똑같은 평범한 `Text`를 그대로 쓰므로,
AttributedString 변환 비용조차 안 든다.

⚠️ [설계 논의에서 이미 확인한 제약, 실제 구현에서도 그대로 적용] 관주
마커는 인쇄본처럼 본문 글자 사이에 정확히 끼워 넣지 못한다 — SwiftUI
`Text(AttributedString)`은 구간별로 탭 제스처를 따로 걸 수 없다. 대신
절 끝에 작은 아이콘(관주는 링크 아이콘 + 팝오버, 구간 메모는 노트 아이콘
+ 메뉴)을 붙여 같은 기능(연결된 구절 확인·이동, 메모 열기)을 제공한다 —
목업이 보여준 "본문 안 작은 원" 모양과는 다르지만, 기능은 동등하다.

관주 대상을 탭하면 그 책/장으로 이동한다(`BibleReadingView.
jumpToCrossReferenceTarget`) — **정확한 절 위치로 스크롤까지 맞추는 것은
이번 구현 범위 밖으로 남겨뒀다**: `TranslationColumnView.centerVerseID`가
private이라 밖에서 직접 지정할 방법이 없고, 아이폰 스와이프 정렬 때 만든
것과 같은 새 상태 전달 경로를 또 만들 만큼 필수적이지 않다고 판단했다.

### 번들 관주 데이터셋

설계 논의에서 이미 밝힌 대로, `VerseCrossReference.source`에 `.bundled`
케이스를 스키마 레벨에서 미리 열어 뒀을 뿐, 실제 가져오기 기능은 만들지
않았다 — 실제 데이터셋(파일/DB)과 그 라이선스 상태를 사용자가 확인해 줘야
다음 단계를 설계할 수 있다. 지금은 사용자 작성(`source: .user`) 경로만
동작한다.

### 정적 검증

이번 라운드에서 새로 만들거나 수정한 파일 11개(`VerseAnnotations.swift`,
`UserContent.swift`, `BibleResearchSchema.swift`, `HighlightColorTag.swift`,
`SelectableVerseTextView.swift`, `VerseAnnotationRenderer.swift`,
`CrossReferenceTargetPicker.swift`, `VerseZoomView.swift`,
`TranslationColumnView.swift`, `BibleReadingViewModel.swift`,
`BibleReadingView.swift`) 전부 괄호/대괄호/중괄호 균형 확인 — 이상 없음.

⚠️ 이번에도 실제 컴파일/실기기 실행은 검증하지 못했다 — 특히 다음 지점은
Xcode에서 직접 빌드해 확인이 필요하다: `UITextView`/`NSTextView` 래핑이
실제로 드래그 선택과 `sizeThatFits`를 통해 자연스러운 줄바꿈 높이로
렌더링되는지, `AttributedString`으로 바뀐 절이 형광펜 배경색/밑줄을
실제로 보여주는지, 확대보기→메모 시트 전환(sheet-after-sheet) 타이밍이
매끄러운지.

### 빌드 에러 수정 — 인자 순서

실기기가 아니라 Xcode 빌드 자체에서 바로 에러가 났다: `BibleReadingView.
swift:342:21 Argument 'highlightsProvider' must precede argument
'coordinator'`(사이드바이사이드 호출부도 동일). 원인 — `TranslationColumnView`는
커스텀 `init`이 없어 Swift가 프로퍼티 선언 순서 그대로 memberwise init을
만드는데, 새 프로퍼티(`highlightsProvider` 등)를 `coordinator` **앞**에
선언해 놓고 호출부(`BibleReadingView.swift`)에서는 `coordinator` **뒤**에
넘기고 있었다 — Swift는 라벨 붙은 인자라도 선언 순서와 다르게 넘기는 걸
허용하지 않는다. `TranslationColumnView.swift`에서 새 프로퍼티 5개
(`highlightsProvider`/`crossReferencesProvider`/`phraseMemosProvider`/
`onSelectCrossReferenceTarget`/`onSelectPhraseMemo`) 선언 위치를
`pendingCenterAlignment` 뒤로 옮겨 호출부 순서와 맞췄다. 앞으로 이 구조체에
프로퍼티를 추가할 때는 항상 선언 순서가 곧 호출 순서라는 점을 기억해야 한다.

괄호 균형 재확인 — `TranslationColumnView.swift` 195/195, 33/33, 79/79,
이상 없음.

## [2026-08-09, 이어서 18] 확대보기 화면에도 기존 주석 표시

사용자 요청 — "확대된 텍스트에도 형광펜 표시와, 메모, 관주여부가 동일하게
표시되도록." 이전 라운드까지는 "구절 확대보기"가 새 주석을 "만드는" 화면
역할만 했고, 그 절에 이미 걸려 있는 형광펜/표시/메모/관주는 확대해서 볼 때
안 보였다 — 평소 읽기 화면과 표시가 어긋나는 문제였다.

### `SelectableVerseTextView`를 `NSAttributedString` 기반으로 전환

기존엔 `text: String` + `font:`만 받아 매번 기본 속성으로만 그렸다.
형광펜/표시(배경색·밑줄)를 보여주려면 이미 스타일이 입혀진
`NSAttributedString`을 통째로 받아야 해서, 파라미터를
`attributedText: NSAttributedString`로 바꿨다.

⚠️ [주의해서 고친 부분] 매 렌더링마다 `.attributedText`를 무조건 다시
대입하면, 사용자가 드래그로 막 만든 선택 영역을 텍스트뷰가 스스로 지워버릴
위험이 있다(속성 재대입이 보통 선택 상태를 리셋시킨다) — `NSAttributedString.
isEqual(to:)`(단순 문자열 비교가 아니라 속성까지 포함한 진짜 동등 비교)로
실제 내용이 바뀔 때만 대입하도록 가드를 걸었다.

### `VerseAnnotationRenderer.nsAttributedContent(...)` 신설

기존 `attributedContent(...)`(하이라이트가 없으면 nil을 돌려주는 최적화
경로, `TranslationColumnView.VerseRow` 전용)와 스타일 계산 로직을 공유하되,
하이라이트가 없어도 항상 `NSMutableAttributedString`을 돌려주는 버전을
새로 뺐다 — `VerseZoomView`가 `SelectableVerseTextView`에 넘길 때는 nil
분기가 필요 없기 때문. `attributedContent`는 이제 이 함수를 감싸는 얇은
래퍼일 뿐이라, 스타일 계산 로직(자가 치유 앵커링 포함)은 한 곳에만 있다.

### `VerseZoomView`에 관주/구간메모 상태 바 추가

평소 읽기 화면(`TranslationColumnView.VerseRow`)과 완전히 같은 데이터
(`viewModel.crossReferences(...)`/`viewModel.phraseMemos(...)`)를 읽어,
관주가 있으면 "관주 N개" 버튼(팝오버로 대상 목록 + 탭하면 그 책/장으로
이동), 구간 메모가 있으면 "메모 N개" 메뉴(탭하면 그 메모를 편집기 시트로
연다)를 텍스트 아래에 보여준다 — 표시만 하는 게 아니라 탭했을 때의 동작도
읽기 화면과 동일하다. 형광펜/표시는 별도 UI 없이 `attributedVerseText`가
본문 자체에 이미 색/밑줄을 입혀서 보여준다.

`onCreatePhraseMemo` 콜백은 `onOpenPhraseMemo`로 이름을 바꿨다 — 이제 "새로
만든 메모를 연다"와 "기존 메모를 골라서 연다"라는 두 경우를 같은 콜백
하나로 겸하기 때문(둘 다 "이 메모를 편집기 시트로 열어라"라는 같은 의미).
새 콜백 `onJumpToCrossReference`도 추가해 `BibleReadingView.
jumpToCrossReferenceTarget`(기존에 이미 있던 함수)을 그대로 재사용했다.

### 정적 검증

수정한 파일 6개(`VerseAnnotationRenderer.swift`, `SelectableVerseTextView.swift`,
`VerseZoomView.swift`, `BibleReadingView.swift`, `TranslationColumnView.swift`,
`BibleReadingViewModel.swift`) 전부 괄호 균형 확인 — 이상 없음. `NSAttributedString.
isEqual(to:)` 가드가 실제로 드래그 선택을 안 지우는지, macOS의
`textStorage?.setAttributedString(...)` 경로가 실기기에서 잘 동작하는지는
Xcode 빌드·실기기 확인이 필요하다.

## [2026-08-09, 이어서 19] "표시"(밑줄)가 메인 읽기 화면에서 안 보이던 버그

사용자 보고 — "확대보기에서 메모 아이콘 왼쪽 '표시'는 성경 본문 메인창에서
표시가 되지 않음." 형광펜(배경색)은 정상 표시되는데 표시(밑줄)만 메인
읽기 화면에서 안 보인다는 매우 구체적인 증상이라, 원인 범위를 빠르게
좁힐 수 있었다.

### 원인

`VerseAnnotationRenderer.attributedContent(...)`는 `NSMutableAttributedString`
으로 배경색/밑줄 속성을 입힌 뒤 `AttributedString(_:)`으로 통째로 브리징해
왔다. `TranslationColumnView.VerseRow`는 이 `AttributedString`을
`Text(attributed)`로 그린다 — 그런데 SwiftUI `Text`가 `NSAttributedString`
에서 브리징된 밑줄 속성(`.underlineStyle`/`.underlineColor`, 특히
`.thick` 변형)을 신뢰성 있게 렌더링하지 않는 것으로 보인다. 배경색은 이
경로로도 잘 나타나 지금까지 문제가 드러나지 않았다.

반면 "구절 확대보기"의 `SelectableVerseTextView`(`UITextView`/`NSTextView`
래핑)는 같은 `NSAttributedString`을 UIKit/AppKit이 직접 그리므로 브리징
자체가 없어 밑줄이 정상적으로 보였다 — "확대보기에서는 보이는데 메인
화면에서만 안 보인다"는 사용자 관찰과 정확히 들어맞는다.

### 수정

`attributedContent(...)`를 `NSAttributedString`을 거치지 않는 방식으로
다시 짰다 — 절 텍스트를 주석 구간 기준으로 여러 조각(스타일 없는 일반
구간 / 형광펜 구간 / 표시 구간)으로 나눠, 각 조각을 `AttributedString`
고유 API(`.font`/`.foregroundColor`/`.backgroundColor`/`.underlineStyle`)로
직접 스타일링한 뒤 이어 붙인다. `NSRange`를 `AttributedString.Index`로
변환하는(다소 애매한) API를 아예 피할 수 있어 더 안전하다. `VerseZoomView`가
쓰는 `nsAttributedContent(...)`(UITextView/NSTextView 전용, `NSAttributedString`
그대로)는 그대로 뒀다 — 그쪽은 브리징이 없어 애초에 문제가 없었다.

겹치는 주석 구간에 대한 방어도 추가했다 — 구간 주석은 서로 안 겹치는 걸
전제로 설계했지만, 겹치는 경우가 생기면(사용자가 이미 표시된 부분과 일부
겹치게 또 새 구간을 만드는 경우) 뒤 구간을 앞 구간이 차지한 부분만큼
잘라내는 클램프를 넣었다 — 없으면 음수 길이 `NSRange`로 크래시할 수 있었다.

### 정적 검증

`VerseAnnotationRenderer.swift` 괄호 균형 확인 — 57/57, 9/9, 21/21, 이상
없음. `AttributedString.underlineStyle = .single`(색상 지정 없이 기본
밑줄)로 단순화했다 — 이전엔 주황색 밑줄을 의도했지만, `Text.LineStyle(pattern:
color:)` 조합까지 확신 없이 쓰는 것보다 확실히 렌더링되는 API로 좁히는 걸
우선했다. 실기기에서 형광펜과 표시가 둘 다 메인 읽기 화면에 보이는지
확인이 필요하다.

## [2026-08-09, 이어서 20] "Modifying state during view update" 경고 수정

사용자 보고 — `SelectableVerseTextView.swift:125 Modifying state during
view update, this will cause undefined behavior.`

### 원인

`SelectableVerseTextView.Coordinator.textViewDidChangeSelection`이
`parent.selectedRange = textView.selectedRange()`로 `@Binding` 값을 그
자리에서 바로 바꾸고 있었다. 문제는 이 델리게이트 콜백이 사용자가 직접
드래그할 때만 불리는 게 아니라, `updateUIView`/`updateNSView`가
`uiView.selectedRange = selectedRange`/`nsView.setSelectedRange(...)`로
"프로그램적으로" 선택 범위를 맞출 때도 UIKit/AppKit이 동기적으로 다시
호출할 수 있다는 점이다 — 그 시점이 SwiftUI가 아직 뷰를 그리는 도중이면,
그 안에서 곧바로 `@Binding`(SwiftUI 상태)을 바꾸는 게 "정의되지 않은
동작"이 된다.

### 수정

두 플랫폼의 `Coordinator.textViewDidChangeSelection` 모두, 값을 바로
대입하지 않고 `DispatchQueue.main.async`로 다음 런루프 틱으로 미루도록
바꿨다 — "뷰 업데이트가 완전히 끝난 뒤" 상태를 바꾸는, `UIViewRepresentable`/
`NSViewRepresentable` 델리게이트 콜백에서 상태를 갱신할 때 흔히 쓰는
표준적인 우회법이다.

### 정적 검증

`SelectableVerseTextView.swift` 괄호 균형 확인 — 43/43, 6/6, 26/26, 이상
없음. 실기기에서 드래그 선택이 여전히 즉각적으로 반응하는지(1프레임 지연이
체감되지 않는지) 확인이 필요하다 — `DispatchQueue.main.async`는 보통
다음 프레임 안에 실행돼 체감 지연은 없어야 하지만, 코드만 보고는 확정할
수 없다.

## [2026-08-09, 이어서 21] "원문 정보"(히브리어/그리스어) 기능 — 데이터셋 조사부터 구현까지

사용자 요청 — "각 절을 선택했을 때 확대보기 버튼 옆에 '원문 정보'라는 버튼이
있어 히브리어 그리스어 원문에 대한 정보를 넣고자 함. 오픈소스로서 고지만
하면 라이센스가 문제되지 않는 데이터가 있으면 제안할 것."

### 데이터셋 조사

- **STEPBible-Data**(github.com/STEPBible/STEPBible-Data) — CC BY 4.0(고지만
  하면 자유 사용). TAHOT(히브리어 구약)/TAGNT(그리스어 신약)에 원어 텍스트,
  Strong 번호, 형태소 분석, 영어 뜻풀이가 절/단어 단위로 이미 정렬돼 있어
  채택했다.
- 제외한 후보: Berean Interlinear Bible(저작권 있음, 부적합), MorphGNT/SBLGNT
  (형태소 주석은 CC BY-SA — 공유 시 동일조건 요구, 사용자가 원한 "고지만"
  요건과 다름), unfoldingWord UHB/UGNT(마찬가지로 CC BY-SA).
- ⚠️ **한글 뜻풀이는 오픈 라이선스 자료가 존재하지 않았다** — 서브에이전트로
  GitHub/CrossWire(SWORD 모듈)/awesome-bible-data를 조사했지만 한글 Strong
  사전은 전부 상업 라이선스(바이블렉스, 옥스퍼드 원어성경대전 등)였다. 사용자
  결정(AskUserQuestion) — "Apple 온디바이스 번역 사용하되, 최초 번역된 내용은
  DB에 저장될 수 있게 할 것. 그 이후부터는 DB내용을 조회할것." 아래 참고.

### 화면 설계(AskUserQuestion으로 사용자가 직접 결정)

1. 데이터셋: STEPBible-Data
2. 표시 정보: Strong번호 + 원어 + 음역 + 영어 + 한글 **네 가지 모두**(이후
   사용자가 "위 화면처럼 원어, 영어, 한글, 스트롱코드가 다 나올 수 있게
   구현할 것"이라고 재확인)
3. 화면 구조: **절 전체를 원어 단어 목록으로** — 구절 확대보기처럼 드래그로
   구간을 고르는 방식이 아니다. 이유: STEPBible 정렬 데이터는 KJV/ESV 같은
   영어 번역과의 단어 정렬이지 한국어 번역본과의 단어별 매핑이 아니라서,
   "한국어 구절의 특정 부분 → 원어 단어"를 정확히 짚어줄 방법이 없다. 대신
   원문은 book/chapter/verse에만 종속되고 어느 번역본을 보고 있는지와 무관
   하므로, `구절 확대보기`(VerseZoomView)와 달리 번역본 선택 UI 자체가
   필요 없다 — 이 점이 설계를 단순하게 만들어 준다.

### 데이터 변환 — STEPBible 원본 텍스트 → `Resources/OriginalText.sqlite`

- 사용자가 GitHub에서 6개 파일(TAGNT Mat-Jhn/Act-Rev, TAHOT Gen-Deu/Jos-Est/
  Job-Sng/Isa-Mal, 합계 약 100MB)을 직접 받아 `Resources/`에 넣어 줬다 — 내
  웹 조회 도구로는 깃허브 대용량 파일(15~24MB)을 통째로 가져올 수 없었기
  때문(대용량 파일 접근이 막혀 있음).
- `build_original_text_db.py`(임시 스크립트, 앱에는 포함되지 않음)로 두 포맷을
  파싱했다:
  - **TAGNT**(그리스어): 각 줄이 `Mat.1.1#01=NKO\t그리스어 (음역)\t영어 문맥역\tG0976=N-NSF\tβίβλος=book\t...` 형태 — "원어(음역)"·"dStrongs=Grammar"·"Dictionary form=Gloss" 세 칸만 있으면 원어/음역/Strong번호/형태소/영어 뜻풀이를 모두 뽑을 수 있다.
  - **TAHOT**(히브리어): 각 줄이 `Gen.1.1#01=L\t히브리어(접두/접미는 '/'로 구분)\t음역\t문맥역\tdStrongs\tGrammar\t...\tRoot dStrong+Instance\t...\tExpanded Strong tags` 형태. 영어 뜻풀이는 "Expanded Strong tags" 칸 안에 `{H0776G=אֶ֫רֶץ=: country;_planet»land:2_country;_planet}` 식으로 박혀 있는데, `»` 앞뒤 중 어느 쪽이 "사람이 읽을 뜻풀이"인지가 표기 방식마다 다르다(일반 단어는 `»` **뒤**가, 고유명사는 `»` **앞**이 뜻풀이) — `:`로 시작하는지로 두 경우를 구분해 처리했다.
  - ⚠️ **품질 한계**: 이 `»` 구분 규칙은 STEPBible 공식 문서가 아니라 실제 샘플(창세기 1장, 요한복음 3:16, 시편 23:1)을 보고 역추론한 것이다 — 정형적으로 다른 패턴(세 번째 유형)이 존재할 가능성을 배제할 수 없다. 뜻풀이가 이상하게 보이는 단어가 있으면 이 휴리스틱의 한계일 수 있다.
  - 파싱 결과: 총 425,441개 단어 레코드, 29,126개 절 커버(성경 전체 약 31,102절 중 대다수 — 나머지는 원본 데이터의 특수 표기 줄이 정규식에 안 걸린 경우, 정확한 누락 절 목록은 조사하지 않았다⚠️).
  - 관사/목적격 표지 등 순수 기능어는 영어 뜻풀이가 빈 문자열일 수 있다(예: 히브리어 목적격 표지 `אֵת`) — 정상이며, UI에서 "-"로 표시한다.
- 결과 SQLite(단일 테이블 `original_words(book_id, chapter, verse, word_order, original_text, transliteration, strong_code, morph_code, gloss_en)`, 인덱스 `(book_id, chapter, verse, word_order)`) 32MB를 `Resources/OriginalText.sqlite`로 앱 번들에 포함했다. 원본 STEPBible `.txt` 6개(약 100MB)는 변환 후 더 이상 필요 없어 `Resources/`에서 삭제했다 — 그대로 뒀으면 Xcode가 파일시스템 동기화 그룹으로 전부 번들에 얹어 앱 용량만 불필요하게 키웠을 것이다.

### 새 코드

- `BibleResearchPlatform/.../BibleReference/OriginalTextModels.swift` — `OriginalWordInfo`(순수 값 타입, `BibleVerse`/`Book`과 같은 이유로 SwiftData `@Model`이 아님 — 정적 참조 데이터).
- `.../OriginalTextStore.swift` — `BibleReferenceStore`와 같은 패턴(raw SQLite3 C API, 읽기 전용)으로 `original_words` 조회.
- `.../Models/StrongGlossTranslation.swift`(새 SwiftData `@Model`, `BibleResearchSchema.modelTypes`에 등록) — 한글 뜻풀이 캐시. 키는 **Strong 번호 단위**(절 단위가 아님) — 같은 Strong 번호는 성경 어디서나 같은 영어 뜻풀이를 쓰므로, 전체 성경에서 사실상 한 번씩만 번역하면 된다(구약+신약 합쳐 고유 Strong 번호는 1만 개 안팎). `sourceEnglishGloss` 스냅샷을 같이 저장해, 원문 데이터가 나중에 갱신돼 영어 뜻풀이가 바뀌면 캐시가 자동으로 무효화되게 했다.
- `Services/OriginalTextLookupService.swift`(앱 레이어, `@MainActor` 싱글턴) — 번들의 `OriginalText.sqlite` 경로를 찾아 `OriginalTextStore`를 한 번만 열고 재사용한다(`BibleReferenceStore`가 절 조회마다 파일을 여는 것과 달리, 이 데이터는 반복 조회가 훨씬 잦아 커넥션을 유지하는 편이 낫다고 판단).
- `Views/Bible/OriginalTextInfoView.swift` — 새 화면. 절의 원어 단어를 리스트로 보여주고, 각 단어에 원어/Strong번호/음역/영어/한글을 표시한다. 한글은 `Translation` 프레임워크(`import Translation`, `.translationTask` — iOS18/macOS15+ API, 이 프로젝트 최소 배포 타깃과 일치)로 그 자리에서 영어→한글 번역을 요청하고, 결과를 `StrongGlossTranslation`에 캐싱한다. 캐시에 이미 있고 `sourceEnglishGloss`가 지금 값과 같으면 번역을 아예 요청하지 않는다.
- `Views/Bible/BibleReadingView.swift` — `verseSelectionActionBar`의 "확대보기" 버튼 바로 옆에 "원문 정보" 버튼 추가, `isOriginalTextInfoPresented` 상태 + `.sheet`로 연결.

### ⚠️ 확인/후속 필요

- **아직 검증 못 한 것(Xcode 실기기)**: `Translation` 프레임워크의 실제 동작(특히 한국어 언어팩이 기기에 없을 때 시스템이 자동으로 다운로드 프롬프트를 띄우는지, macOS에서도 iOS와 동일하게 동작하는지), `#Predicate`의 `Array.contains` 캡처가 실제로 컴파일/동작하는지.
- **라이선스 고지 미구현**: STEPBible CC BY 4.0은 "고지"가 조건이다 — 앱 어딘가(정보/설정 화면)에 "원문 데이터: STEPBible-Data (STEPBible.org), CC BY 4.0" 문구가 필요하지만, 이번 라운드는 기능 구현까지만 진행했고 별도 라이선스 고지 화면 자체가 아직 이 앱에 없다(범위 밖으로 남김).
  - **[2026-08-13 해소]** 별도 화면을 새로 만드는 대신, 이미 있던 환경설정 "정보" 탭(맨 마지막 탭, `AboutSettingsTab`)의 "오픈소스 라이선스 고지" 섹션에 STEPBible-Data(TAHOT/TAGNT, CC BY 4.0) 크레딧 문구와 저장소 링크를 추가했다(`SettingsView.swift`). 문구는 STEPBible 라이선스 조건 그대로 "STEP Bible"을 www.STEPBible.org에 링크하는 형태로 작성 — README 상단 데이터셋 조사 절의 라이선스 요약과 동일한 근거. `OriginalTextLookupService.swift` 상단 주석도 함께 갱신했다. ⚠️ Xcode에서 실제 렌더링/링크 동작은 확인하지 못했다(이 세션은 Swift 컴파일 환경이 없어 괄호 균형 등 정적 검토만 수행).
- **번역 품질**: 한글 뜻풀이는 Apple 기계번역 그대로다 — 신학 용어의 표준 역어와 다를 수 있다.

## [2026-08-09, 이어서 22] 원문 정보 화면 스타일 + 확대보기 수정/삭제 4건

사용자 피드백 4건을 한 번에 반영했다.

### 1) 원문 정보 카드 스타일

이전 대화에서 목업(`mcp__visualize__show_widget`)으로 보여줬던 스타일을 실제
구현에 맞춰 재현했다. `OriginalTextInfoView`를 `List`에서 카드형
`ScrollView`+`LazyVStack`으로 바꾸고, 사용자가 지정한 순서 그대로 배치했다:
1번째 줄 — 원문(28pt bold) · Strong번호(캡슐 배지) · 한글(21pt bold, 오른쪽
정렬), 2번째 줄 — (음역, 16pt secondary) · 영어(16pt secondary, 오른쪽 정렬).
카드 배경은 `secondarySystemGroupedBackground`(iOS)/`controlBackgroundColor`
(macOS), 모서리 14pt.

### 2) 확대보기에서 형광펜/밑줄 취소

`SelectableVerseTextView`가 `highlights: [VerseHighlight]` +
`onRequestRemoveHighlight` 콜백을 받도록 확장했다. 우클릭(macOS)/텍스트 선택
시 뜨는 편집 메뉴(iOS, `UITextViewDelegate.textView(_:editMenuForTextIn:
suggestedActions:)` — iOS 16+ API)를 가로채, 클릭·선택 지점이
`VerseAnnotationRenderer.resolvedRange`(자가 치유 앵커링, 기존 렌더링과
정확히 같은 기준)로 계산한 기존 주석 범위와 겹치면 "형광펜 취소"/"밑줄 취소"
항목을 메뉴 맨 앞에 끼워 넣는다. macOS는 `NSTextViewDelegate.textView(_:
menu:for:at:)`로 같은 일을 한다 — `NSMenuItem`의 액션 셀렉터는 인자를 못
받아서, 어떤 주석을 지울지를 `Coordinator.pendingRemoveTarget`에 잠깐
저장해 뒀다가 액션이 실제로 실행될 때 읽는다. 실제 삭제는 기존
`BibleReadingViewModel.deleteHighlight(_:)`를 그대로 재사용한다(새 삭제
로직을 따로 만들지 않음).

⚠️ `updateUIView`/`updateNSView`에 `context.coordinator.parent = self`를
추가했다 — 이전엔 `Coordinator.init`에서 한 번만 `parent`를 잡고 그 뒤로는
안 바꿨는데, `highlights`/`onRequestRemoveHighlight`처럼 매 렌더링마다 값이
바뀔 수 있는 프로퍼티가 새로 생겨서, 우클릭 시점에 항상 최신 `highlights`를
보게 하려면 이 갱신이 필요하다(이전에는 `attributedText`/`selectedRange`만
썼고 둘 다 `updateUIView`/`updateNSView` 안에서 직접 비교하던 값이라 이
문제가 드러나지 않았다).

### 3) 관주 팝오버에 (x) 삭제

`crossReferencePopoverContent`가 `crossReferences.flatMap(\.targets)`로
평평하게 펼쳐서 보여주던 것을 `ForEach(reference) { ForEach(reference.
targets) { ... } }` 이중 순회로 바꿔, 각 대상 행이 자신의 부모
`VerseCrossReference`를 계속 들고 있게 했다(그래야 "이 대상만" 지울 때 어느
레코드에서 빼야 할지 알 수 있다). 새 뷰모델 메서드
`removeCrossReferenceTarget(_:from:)` — 대상을 배열에서 빼고, 그 결과
배열이 비면(마지막 대상이었던 경우) 레코드 자체를 `deleteCrossReference`로
지운다.

### 4) 확대보기 타이틀 "장" 누락

`localizedBookChapterLabel`(`BibleReadingViewModel.reloadVerses`)이
"책이름 장번호"까지만 담고 "장" 글자를 안 붙이는 걸 몰랐다가, 확대보기
타이틀이 `.navigationTitle("\(label) \(verseNumber)절 확대보기")`로 그대로
이어 붙이는 바람에 "요한복음 3 16절 확대보기"처럼 숫자 두 개가 붙어 보였다.
`"\(label)장 \(verseNumber)절 확대보기"`로 고쳐 "요한복음 3장 16절
확대보기"가 되게 했다. 메모: 이 라벨 조합 방식(`localizedBookChapterLabel`에
"장"이 없는 것)은 다른 화면(예: 메인 읽기 화면 타이틀)에서도 같은 패턴으로
쓰일 수 있으니, 비슷한 문제가 또 보이면 같은 원인일 가능성이 크다.

### 정적 검증

새/수정 파일 6개 모두 괄호·중괄호·대괄호 균형 확인 — 전부 일치.
`OriginalTextInfoView.swift`(103/103, 49/49, 19/19),
`VerseZoomView.swift`(124/124, 73/73, 6/6),
`SelectableVerseTextView.swift`(57/57, 41/41, 9/9),
`BibleReadingViewModel.swift`(146/146, 74/74, 44/44) — 이상 없음.

### 빌드 에러 수정 — `Cannot find 'highlights' in scope`

사용자 보고 — `VerseZoomView.swift:115:37 Cannot find 'highlights' in scope`.
원인: `highlights`가 `attributedVerseText` 계산 프로퍼티 안에서만 쓰던 지역
변수(`let highlights = viewModel.highlights(...)`)였는데, 형광펜/밑줄 취소
기능을 추가하며 `body`의 `SelectableVerseTextView(...)` 호출부에서도 같은
목록이 필요해졌다 — 지역 변수라 그 스코프 밖에서는 안 보이는 게 당연했다.
`crossReferences`/`phraseMemos`와 같은 패턴으로 `private var highlights:
[VerseHighlight]` 계산 프로퍼티로 승격해 두 곳(속성 렌더링 + 취소 히트테스트)
모두 재사용하도록 고쳤다.

## [2026-08-09, 이어서 23] 메인 화면 밑줄 색상을 확대보기와 통일

사용자 요청 — "확대보기의 밑줄 표시는 주황색 굵은 줄로 표시됨. 그와 동일하게
메인창에서도 밑줄에 대한 스타일이 동일하게 처리 될수 있도록 할것."

`VerseAnnotationRenderer.attributedContent`(메인 읽기 화면, SwiftUI `Text` +
네이티브 `AttributedString` 경로)의 `.mark` 케이스를 `styled.underlineStyle =
Text.LineStyle(pattern: .solid, color: .orange)`로 바꿔, 확대보기
(`nsAttributedContent`, `NSUnderlineStyle.thick`+`.systemOrange`)와 색상을
맞췄다.

⚠️ **두께는 못 맞춘다** — SwiftUI `Text.LineStyle`은 `pattern`(solid/dot/dash
등)과 `color`만 받고 두께(thickness) 파라미터 자체가 없다(공개 API 한계,
`NSUnderlineStyle.thick` 같은 옵션이 없음). 그래서 색상은 확대보기와 완전히
동일해지지만, 두께는 메인 화면 쪽이 더 가늘게 보일 수밖에 없다 — 이 프로젝트
초기 설계 노트("표시는 밑줄 하나로만 구현")와 같은 맥락의 플랫폼 제약이다.

### 정적 검증

`VerseAnnotationRenderer.swift` 괄호 균형 — 37/37, 21/21, 3/3, 이상 없음.

## [2026-08-09, 이어서 24] 원문 정보 한글 뜻풀이 직접 수정

사용자 요청 — "원문정보의 한글 번역을 수정할 수 있게 할 것."

각 단어 행의 한글 뜻풀이 옆에 연필 아이콘을 추가했다. 누르면 `.alert` +
`TextField`(iOS/macOS 공통 API, 별도 커스텀 시트 없이 가장 가벼운 방법)로
지금 값(자동번역 결과 또는 빈 문자열)을 채운 편집창이 뜨고, "저장"을 누르면
`StrongGlossTranslation` 캐시를 직접 덮어쓴다(`upsertCache` 재사용 — 자동
번역 결과를 저장할 때와 동일한 경로).

⚠️ **캐시가 Strong 번호 단위라는 점이 그대로 적용된다** — 한 절에서 고친
한글 뜻풀이는 같은 Strong 번호가 나오는 성경 전체의 다른 절에도 똑같이
적용된다(예: G3588 "ὁ"의 뜻풀이를 한 곳에서 고치면 그 관사가 나오는 모든
구절에 반영됨). 이건 애초에 "Strong 번호 단위로 한 번만 번역/캐싱"하기로
한 설계(이어서 21)의 자연스러운 결과이지 새로운 부작용이 아니지만, 사용자가
헷갈리지 않도록 알림창 문구에 "같은 Strong 번호가 나오는 다른 절에도 이
번역이 적용됩니다"라고 명시했다. 빈 문자열 저장은 막아 뒀다(실수로 지우고
저장하는 걸 방지).

### 정적 검증

`OriginalTextInfoView.swift` 괄호 균형 — 122/122, 65/65, 21/21, 이상 없음.

### 후속 수정 — 영어 뜻풀이 없는 단어도 편집 가능하게

사용자 요청 — "한글정보가 없는 것도 수정할 수 있게 할 것." 처음 구현에서는
한글 칸(연필 아이콘 포함) 자체가 `!word.glossEn.isEmpty`(STEPBible 영어
뜻풀이가 있을 때)에만 보였다 — 관사·목적격 표지 같은 순수 기능어(영어
뜻풀이가 원래 빈 문자열)는 편집할 방법이 없었다. 한글 칸을 항상 보이도록
바꾸고, `loadCachedGlosses`도 "영어 뜻풀이가 없으면 캐시 조회 자체를
건너뛰던" 조건을 없애 사용자가 그런 단어에 직접 입력해 저장한 한글이 다음에
열 때도 제대로 불러와지게 했다. 자동번역 대상은 여전히 영어 뜻풀이가 있는
단어로 제한한다(빈 문자열을 번역기에 보내는 건 의미가 없음) — 영어 뜻풀이가
없는 단어는 항상 사용자가 직접 입력해야 한글이 채워진다.

⚠️ **Xcode 실기기 확인 필요**: (a) iOS `editMenuForTextIn`이 실제로 롱프레스/
트랙패드 우클릭에서 우리 커스텀 액션을 보여주는지, (b) macOS
`textView(_:menu:for:at:)`가 실제 우클릭에서 호출되는지(이 메서드 자체가
`isSelectable=true`+`isEditable=false`인 텍스트뷰에서도 정상 호출되는지는
문서만으로 100% 확신할 수 없음), (c) `ForEach(crossReferences)`가
`VerseCrossReference`(SwiftData `@Model`)의 자동 `Identifiable` 합성으로
문제없이 컴파일되는지(같은 파일의 `ForEach(phraseMemos)` 선례를 보고
안전하다고 판단했지만 직접 컴파일 확인은 못 함).

## [2026-08-09, 이어서 25] 메인 화면 관주/메모 아이콘을 절 번호 밑으로 세로 배치

사용자가 스크린샷과 함께 요청 — "성경 본문 열 내에 메모 아이콘, 관주아이콘
위치를 절 번호 밑에 세로로 배치하여 차지하는 영역을 줄일 수 있도록 할 것."
스크린샷(출애굽기 2:3)을 보면 본문이 여러 줄로 감길 때 관주/메모 아이콘이
가로로 나란히 붙어 있어 줄바꿈된 본문 옆 가로 공간을 계속 차지하고 있었다.

`TranslationColumnView.VerseRow`의 `HStack(절번호, 본문, 관주아이콘,
메모아이콘)` 구조를, 절번호 칸 자체를 `VStack(alignment: .center)`으로 바꿔
번호 아래에 두 아이콘을 쌓는 구조로 바꿨다 — `HStack(절번호칸, 본문)` 두
요소만 남아 본문이 아이콘 너비만큼 더 넓게 쓸 수 있다. 아이콘 폰트도
`.caption`(가로 배치 때 본문과 나란히 보이던 크기)에서 `.caption2`(세로
배치에 맞춘 더 작은 크기)로 낮췄다 — 세로로 쌓으면 셋(번호+아이콘 2개)이
차지하는 세로 길이가 늘어나므로, 그만큼 각 아이콘을 작게 해 균형을 맞췄다.

### 정적 검증

`TranslationColumnView.swift` 괄호 균형 — 123/123, 76/76, 14/14, 이상 없음.

## [2026-08-09, 이어서 26] 앱 아이콘 이미지 교체

사용자 요청: "앱 아이콘을 첨부파일로 변경할 것." (JBCH 로고 — 어두운 그라디언트
배경에 금색 "JBCH" 텍스트와 성경 일러스트, 1994×1994 RGB, 알파 채널 없음).

`Assets.xcassets/AppIcon.appiconset/Contents.json`이 요구하는 13개 PNG
전부(`AppIcon-1024`/`-1024-dark`/`-1024-tinted`, mac 1x/2x 16~512)를 원본
이미지를 각 크기로 리사이즈(Pillow, LANCZOS)해 그대로 교체했다. 다크/틴트
변형은 사용자가 이미지 한 장만 제공했으므로 동일 이미지를 재사용했다 —
외형 모드별로 다른 톤을 원하면 별도 이미지가 필요하다.

⚠️ iOS 유니버설 1024 아이콘은 앱스토어 규정상 알파 채널이 없어야 하는데,
원본이 이미 RGB(알파 없음)라 별도 플래트닝 없이 그대로 사용 가능했다.

### 정적 검증

각 PNG 파일을 Pillow로 재오픈해 실제 크기(16~1024)와 모드(RGB, 알파 없음)를
확인 — 13개 전부 일치. Xcode 아이콘 프리뷰 확인은 실기기/Xcode에서 필요.

## [2026-08-09, 이어서 27] 리치 텍스트 에디터 전면 교체 — 블록/버튼 → 연속 텍스트

사용자 요청: "사이드바 [개요], [내 메모], [메모 팝업] 등.. 리치 텍스트 구성을
변경. 첨부파일(다른 프로젝트의 macOS 전용 `RichTextEditor.swift`, `NSTextView`
래퍼)을 면밀히 살펴보고, 최대한 첨부파일대로 구성할 수 있도록, 맥OS·iOS 모두
호환되어야 하며, 완벽하게 반영하지 않아도 되지만 호환성 유지한도 내에서 최대한.
새 문단을 작성할 때마다 버튼을 눌러 추가하는 게 아니라 메모장처럼 풀 텍스트를
작성하게 하고, 문단구분은 하지 않도록."

### 이전 구조와 무엇이 왜 바뀌었나

기존 `RichTextBlockEditor`(+`MemoRichTextDocument`)는 "문단(블록) 배열 + 문단
전체 단위 서식 토글 + '새 문단' 버튼"이었다(순수 SwiftUI `TextEditor` 여러 개로
구성 — 그 파일들 상단 주석에 적었듯, Xcode 컴파일 검증이 불가능한 환경에서
안전하게 구현하려던 의도적 단순화였다). 이번 요청은 정확히 그 구조를 없애 달라는
것이라 전면 교체했다.

참고 파일이 macOS 전용(`NSTextView`/AppKit)이라, 설계 원칙 3가지는 그대로
가져오고 iOS/iPadOS 대응만 대칭적으로 추가했다:
1. 편집기가 "서식 있는 문자열(RTF)"과 "순수 텍스트" 두 값을 항상 함께 부모에게
   돌려준다.
2. `NSTextStorageDelegate.didProcessEditing`에서 매 변경(문자/속성 모두)마다 그
   두 값을 재계산해 내보낸다.
3. 부모가 방금 내보낸 값과 같은 값을 다시 내려보내면(에디터 자신이 만든 변경의
   메아리) 뷰를 다시 그리지 않는다 — 무한 루프 방지("lastExportedText" 가드).

iOS 쪽은 `SelectableVerseTextView.swift`가 이미 쓰는 관례(`#if os(iOS)`
UIViewRepresentable / `#elseif os(macOS)` NSViewRepresentable를 같은 타입
이름으로 나란히 선언)를 그대로 따랐다.

### 새 파일: `Views/Memo/RichTextEditor.swift`

- `RichTextCodec` — 저장 문자열(RTF) ↔ `NSAttributedString` 왕복 변환. RTF로
  인식 안 되면(빈 문자열이거나 예전 HTML 레거시 데이터) 순수 텍스트로 취급해
  기본 폰트를 입힌다.
- `RichTextEditor: View` — 공개 타입. `rtfText`/`plainText` 두 바인딩과
  `isEditable`만 받는다. iOS에서만 커스텀 툴바(굵게/기울임/밑줄/색상/글꼴)를
  그린다.
- `RichTextEditorRepresentable` — `#if os(iOS)` UIViewRepresentable /
  `#elseif os(macOS)` NSViewRepresentable. 프로그램적 초기 로드가
  `didProcessEditing`을 다시 트리거해 "화면을 열기만 해도 매번 자동저장이
  예약되는" 부작용을 막기 위해 `isLoadingExternally` 가드를 추가했다(참고
  파일에는 없던, 이 프로젝트의 자동저장 체계 때문에 새로 필요해진 방어 코드).
- `RichTextEditingProxy` — 툴바가 지금 포커스된 텍스트 뷰의 선택 영역에 서식을
  적용하는 다리.

### ⚠️ 저장 형식 변경 — `contentHtml` 필드에 이제 RTF가 들어간다

`UserMemo`/`BookOutline`/`ChapterSummary`의 `contentHtml` 필드는 스키마상
이름은 그대로 두었다(스키마 변경/CloudKit 마이그레이션을 피하려는 목적 — 문자열
필드라 내부에 뭘 담든 스키마 자체는 안 바뀐다). 하지만 지금부터 그 안에는 HTML이
아니라 **RTF 문자열**이 저장된다. `contentText`(검색/미리보기/임베딩용 순수
텍스트) 쪽 계약은 전혀 바뀌지 않았다 — `MemoRowView`/`SearchViewModel`/
`EmbeddingIndexingService`/`TagDrilldownView` 등 `contentHtml`을 건드리지 않는
모든 화면은 전수 확인했고 영향이 없다.

**유일한 부작용**: 이전에 HTML로 저장돼 있던 기존 메모/개요를 다시 열면,
`{\rtf1`로 시작하지 않으니 일반 텍스트로 인식되어 `<p>...</p>` 같은 태그가 그대로
화면에 보인다 — 1회성 전환 비용이며 자동 마이그레이션은 범위 밖이다. 이 프로젝트가
아직 개발 중이라 실제로 저장된 메모/개요가 많지 않다면 영향은 제한적이다.

### 문단 스타일(H1~H3/목록/인용) 제거

참고 파일에는 그런 개념이 없고 "문단 구분 없음" 요청과도 배치되어 헤딩/목록/인용
토글을 들어냈다. 남는 서식은 굵게/기울임/밑줄/글자색/글꼴 다섯 가지이며, 이제는
문단 전체가 아니라 "선택한 부분"에만 적용된다(이전 구현이 범위 밖으로 남겨 뒀던
부분 선택 서식이, 참고 파일처럼 진짜 텍스트 뷰를 직접 감싸면서 자연스럽게
가능해졌다).

### 플랫폼별 UI 차이 (의도적)

macOS는 참고 파일 그대로 `usesInspectorBar/usesFontPanel/usesRuler = true`만
켠다 — 텍스트를 선택하면 애플이 직접 그리는 네이티브 서식 팝업(macOS 14+)이
자동으로 뜨므로 커스텀 SwiftUI 툴바를 만들지 않았다. iOS는 그런 팝업이 없어
`allowsEditingTextAttributes = true`(굵게/기울임/밑줄을 "aA" 메뉴 + 하드웨어
키보드 단축키로 지원)에 더해, 색상/글꼴까지 다루는 작은 커스텀 툴바를 따로 뒀다.
겉모습은 플랫폼마다 다르지만("완벽하게 반영하지 않아도 되지만 호환성 유지한도
내에서 최대한"이라는 요청 범위 안의 의도적 타협), 기능은 최대한 맞췄다.

### 배선 변경 — `MemoDetailView`/`OutlineView`

두 화면 모두 `document`/`hasLoadedDocument` 같은 중간 상태를 완전히 없애고,
`RichTextEditor`가 모델 프로퍼티(`memo.contentHtml`/`viewModel.bookOutline?.
contentHtml`/`chapterSummary?.contentHtml`)에 직접 바인딩하도록 바꿨다.
`OutlineView`의 "AI 초안 적용"(9.9절)도 블록 배열 조작 대신
`RichTextCodec.decode`/`.encode`로 기존 서식 있는 텍스트 뒤에 AI 텍스트를
이어 붙이는 방식으로 재작성했다.

### ⚠️ Xcode 확인 필요

`UIFontDescriptor.withSymbolicTraits(_:)`(iOS, 실패 시 nil 가능)와
`NSFontDescriptor.withSymbolicTraits(_:)`(macOS, 항상 성공하지만 그 디스크립터로
실제 `NSFont`를 만드는 `NSFont(descriptor:size:)`가 실패 가능) 둘 다 컴파일
검증 없이 기억에 의존해 작성했다 — 굵게/기울임 토글이 실기기에서 기대대로
동작하는지 확인이 필요하다. macOS `usesInspectorBar`가 실제로 서식 팝업을
띄우는지, iOS `allowsEditingTextAttributes`의 "aA" 메뉴가 기대대로 뜨는지도
마찬가지로 실기기 확인 대상이다.

### 삭제한 파일

`Views/Memo/RichTextBlockEditor.swift`, `Services/RichText/
MemoRichTextDocument.swift`, `Services/RichText/MemoParagraphStyle.swift`,
`Services/RichText/MemoRichTextAttributes.swift`, `Services/RichText/
HTMLEntity.swift` — 전부 새 `RichTextEditor.swift`로 대체되어 필요 없어졌다.
`Services/RichText/Color+Hex.swift`(색상 팔레트)는 그대로 재사용한다.

### 정적 검증

주석/문자열 리터럴을 제외하고 괄호/중괄호/대괄호를 세는 방식으로 확인(RTF 프리픽스
`` `{\rtf1` ``가 주석/문자열 안에 짝 없는 `{`를 남겨 단순 카운트는 거짓 양성이
났다 — 주석·문자열을 걷어낸 뒤 재확인함):
- `RichTextEditor.swift` — 205/205, 110/110, 25/25
- `MemoDetailView.swift` — 133/133, 83/83, 14/14
- `OutlineView.swift` — 149/149, 57/57, 1/1
- `OutlineViewModel.swift`/`AppCommands.swift`/`SettingsView.swift`/
  `Color+Hex.swift` — 전부 이상 없음.

옛 심볼(`RichTextBlockEditor`/`MemoRichTextDocument`/`MemoBlock`/
`MemoParagraphStyle`/`MemoColorHexAttribute`/`MemoFontFamilyAttribute`/
`MemoIsQuoteAttribute`/`HTMLEntity.`)을 전체 코드베이스에서 재검색해, 남아 있는
건 전부 설명용 주석뿐이고 실제 코드 참조는 없음을 확인했다.

## [2026-08-09, 이어서 28] 성경 조회 사이드바/확대보기 메모 — 좌표 UI 제거 + 전용 서식

사용자 요청: "[성경 조회] 오른쪽 사이드 바의 메모, 절 클릭후 확대보기에서의 메모
수정사항 — 성경 및 장 선택, 텍스트로 성경검색, 절이동 기능 제거. 편집모드의
기본 입력 스타일(글꼴: 페이퍼로지 3 Light, 크기: 14, 줄간격: 1.5, 배경: 흰색),
조회모드(배경: 시스템 배경색). + 메모/개요 입력 공통 — 태그 추가 입력란 글꼴:
시스템 기본글꼴, 보통크기."

### 진입점 확인 — 사실은 한 곳

"오른쪽 사이드바의 메모"(`ChapterRelatedContentPanel.onSelectMemo`)와 "확대보기의
메모"(`VerseZoomView.onOpenPhraseMemo`)는 둘 다 `BibleReadingView`의
`memoBeingCreated` 상태를 거쳐 **같은 `.sheet(item:)` 하나**(`MemoDetailView`를
표시)로 귀결된다는 걸 코드에서 확인했다 — 수정할 콜사이트는 하나뿐이다.

### `MemoPresentationContext` 도입

`MemoDetailView`는 이 팝업뿐 아니라 "내 메모" 탭(`MemoHomeView`)에서도 그대로
재사용되는 공용 타입이다. `MemoHomeView.swift` 상단 주석(13~14행)이 이미 명시한
대로, "내 메모" 탭에서는 `BookChapterPicker`로 메모의 성경 좌표를 직접 바꾸는 게
정상 흐름이라 그 UI를 없앨 수 없다. 그래서 좌표 UI를 무조건 지우는 대신
`MemoPresentationContext`(`.standalone`/`.contextual`) 열거형을 추가했다:
- `.standalone`(기본값, 내 메모 탭) — 기존 그대로 `BookChapterPicker` + 절
  `Stepper` 유지.
- `.contextual`(성경 조회 사이드바/확대보기 팝업) — 좌표 선택 UI 대신 읽기전용
  라벨("창세기 3장 5절")만 보여준다. `BibleReadingView`의 시트 콜사이트
  한 곳에서만 `.contextual`을 넘긴다.

### `RichTextEditor`에 서식 오버라이드 파라미터 추가

`typingFont`/`lineHeightMultiple`/`editingBackgroundColor`/
`readOnlyBackgroundColor` 네 파라미터를 새로 추가했다 — 전부 기본값이 "기존
동작 그대로"라 값을 넘기지 않는 다른 호출부(내 메모/개요)는 영향이 없다.
`.contextual`에서만 다음을 넘긴다:
- `typingFont`: `PlatformFont(name: "Paperlogy-3Light", size: 14)`
  (`BundledFontRegistrar.swift`에 등록된 실제 PostScript 이름). 폰트를 못 찾으면
  (아직 타겟에 안 들어갔을 때) 시스템 폰트 14pt로 조용히 대체한다.
- `lineHeightMultiple: 1.5` — ⚠️ [용어 해석] 애플 `NSParagraphStyle.lineSpacing`은
  "줄 사이에 추가하는 포인트 값"이지 배수가 아니다. 워드프로세서에서 흔히 쓰는
  "1.5줄 간격"(전체 줄 높이가 1.5배)으로 해석해 `lineSpacing = 폰트 한 줄 높이 ×
  0.5`로 환산했다.
- `editingBackgroundColor: .white`, `readOnlyBackgroundColor: .systemContentBackground`
  (iOS `.systemBackground`/macOS `.textBackgroundColor`를 하나로 묶은 새 확장) —
  편집 중엔 다크모드에서도 무조건 흰 종이 느낌, 조회 중엔 시스템 배경에 자연스럽게
  섞이도록.

이 값들은 "새로 입력하는 글자"에 적용되는 `typingAttributes`일 뿐, 이미 저장된
서식 있는 내용을 강제로 재포맷하지는 않는다 — 요청이 "편집모드의 **기본 입력**
스타일"이라고 명시했기 때문이다.

⚠️ [발견 및 수정한 버그] `editingBackgroundColor`/`readOnlyBackgroundColor`가 둘 다
nil일 때(대부분의 화면) macOS 쪽에서 실수로 `drawsBackground = false`를 강제해
버려서, 내 메모/개요 화면의 에디터가 투명해지는 회귀가 생겼었다 — `NSTextView`는
원래 기본값 자체가 `drawsBackground = true` + `.textBackgroundColor`라
(iOS `UITextView`의 기본값이 `.clear`가 아닌 것과 마찬가지로) 아무것도 안 건드리는
게 맞다. "색을 지정한 화면에서만 덮어쓴다"로 고쳤다.

### 공통 변경 — 태그 입력란 폰트

`MemoDetailView.tagSection`의 태그 입력 `TextField`에 `.font(.body)`를 명시했다
(요청: "시스템 기본글꼴, 보통크기"). 이 화면 전체에 별도 폰트 환경값을 지정해
두지 않아 원래도 시스템 기본 글꼴이었지만, 앞으로 이 화면에 다른 기본 폰트가
생기더라도 이 입력란만은 항상 시스템 기본을 쓰도록 명시적으로 고정했다.

### 정적 검증

주석/문자열을 걷어내고 괄호 균형 확인 — `RichTextEditor.swift` 218/218·119/119·
29/29, `MemoDetailView.swift` 146/146·90/90·14/14, `OutlineView.swift`
149/149·57/57·2/2, `BibleReadingView.swift` 134/134·103/103·0/0. 이상 없음.

⚠️ Xcode 확인 필요: `PlatformFont(name: "Paperlogy-3Light", size: 14)`가 실기기
에서 실제로 등록된 폰트를 찾는지(`BundledFontRegistrar`가 앱 시작 시 먼저
실행돼야 함), macOS `.textBackgroundColor`/iOS `.systemBackground`가 조회모드에서
기대한 대로 보이는지, 줄간격 1.5 환산이 실제로 "1.5줄 느낌"으로 보이는지 확인이
필요하다.

## [2026-08-09, 이어서 29] 메모/개요 레이아웃 압축 + 조회모드 도구 숨김 + 개요 별도 창

사용자 요청: "메모/개요 입력 공통 수정사항 — 메모: 폴더 선택 영역은 한줄정도로
짧게, 나머지는 모두 에디터 영역. 조회모드: 글 배경색 흰색, 스타일 도구 감추기.
개요: 두 에디터 영역이 꽉차게. + [성경 조회] 오른쪽 사이드바의 개요 — 개요화면
열기 버튼: 이동가능, 크기조절 가능한 창으로 조회모드로 열기."

### 메모 화면(`MemoDetailView`) — `ScrollView` 제거

기존엔 헤더→에디터(최소 220pt)→태그→폴더 순서를 통째로 `ScrollView`에 넣어,
태그/폴더가 짧으면 에디터가 딱 최소 높이만큼만 차지하고 화면 나머지는 그냥
비어 있었다. `ScrollView`를 걷어내고 폴더 선택 줄을 헤더 바로 아래 한 줄로
압축한 뒤, 에디터에 `.frame(maxHeight: .infinity)`를 줘 남은 세로 공간을
전부 차지하게 했다. `RichTextEditor`는 내부적으로 이미 자체 스크롤
(`NSScrollView`/`UITextView`)을 갖고 있어 내용이 길어져도 문제없다. 태그
영역은 에디터 아래 고정 높이로 남긴다.

### 개요 화면(`OutlineView`) — 두 에디터가 공간을 절반씩

같은 이유로 `ScrollView`를 걷어내고, 책 개요/장 개요 두 섹션 각각에
`.frame(maxHeight: .infinity)`를 줘서 남은 세로 공간을 절반씩 나눠 채우게
했다.

### 조회모드 배경/스타일 도구

`MemoDetailView`의 `readOnlyBackgroundColor`를 `.standalone`(내 메모 탭)에서
`.white`로 지정했다(`.contextual`은 이전 요청대로 시스템 배경색 유지). 또한
`RichTextEditor` 자체에 "조회모드에서는 서식 도구를 숨긴다" 로직을 추가했다 —
macOS는 `usesInspectorBar/usesFontPanel/usesRuler`를 `isEditable`에 연동해서
껐다 켰다 하고, iOS는 `allowsEditingTextAttributes`를 같은 방식으로 연동했다.
이건 특정 화면 전용이 아니라 `RichTextEditor`를 쓰는 모든 곳(메모/개요, 두
컨텍스트 전부)에 공통으로 적용된다 — 애초에 "보기 전용인데 서식 도구가 뜨는"
것 자체가 어색해서, 특정 화면만 골라 끄는 대신 컴포넌트 차원에서 고쳤다.

### 개요를 이동/크기조절 가능한 별도 창으로

`OutlineView`는 지금까지 편집 모드 고정이었다(`RichTextEditor(..., isEditable:
true)` 하드코딩). `MemoDetailView`와 같은 눈/연필 토글 버튼과 `isEditable`
상태, 그리고 `initialIsEditable`(기본값 `true`) 초기화 인자를 추가했다. 성경
조회 사이드바(`ChapterRelatedContentPanel`)의 "개요 화면 열기" 버튼은 이전엔
`AppNavigationRequest.shared.request(.outline)`으로 메인 내비게이션 자체를
개요 섹션으로 바꿨는데, 이제 `openWindow(id: "outline")`로 새
`WindowGroup(id: "outline")`(`OutlineView(initialIsEditable: false)`를
`NavigationStack`으로 감싼 것)을 조회모드로 연다 — "tag-relations"/
"bible-reading" 창과 같은 패턴이다. `WindowGroup`은 기본적으로 이동/크기조절이
자유로운 표준 창이라(Settings 창처럼 `.windowResizability`로 제한하지 않음)
별도 설정이 필요 없다. 새 창을 여는 것은 성경 조회 화면을 방해하지 않으므로,
사이드 패널을 닫던 기존 동작(`isRelatedContentPresented = false`)도 없앴다.
사이드바 진입/⌘4로 들어오는 기존 경로(`SidebarNavigationView`/`PhoneTabView`)는
인자를 안 넘기므로 기본값(`true`, 편집 가능)으로 기존과 동일하게 동작한다.

⚠️ 기존에 이 화면은 `.toolbar`가 아예 없었다 — 새로 추가한 토글 버튼의
`.toolbar`가 제대로 뜨려면 네비게이션 컨테이너가 필요해서, 새 창 쪽은
`NavigationStack`으로 직접 감쌌다(기존 사이드바 경로는 `SidebarNavigationView`
자체의 `NavigationStack`이 이미 있어 손대지 않았다).

### 정적 검증

주석/문자열을 걷어내고 괄호 균형 확인 — `RichTextEditor.swift` 224/224·121/121·
29/29, `MemoDetailView.swift` 147/147·89/89·14/14, `OutlineView.swift`
157/157·61/61·2/2, `BibleReadingView.swift` 134/134·103/103·0/0,
`JBCHBibleResearchApp.swift` 41/41·13/13·0/0. 이상 없음. `OutlineView()`(인자
없는 기존 호출부, SidebarNavigationView/PhoneTabView 2곳)도 재검색해 새
`init(initialIsEditable:)`의 기본값으로 여전히 컴파일된다는 걸 확인했다.

⚠️ Xcode 확인 필요: 새 "outline" 창이 macOS에서 실제로 자유롭게 이동/크기조절
되는지, iPadOS/아이폰에서 `openWindow(id: "outline")`가 기존 "tag-relations"/
"document-viewer" 창과 같은 방식으로 동작하는지(아이폰은 다중 창을 지원하지
않아 현재 화면이 이 창 콘텐츠로 대체될 것으로 예상 — 기존 창들과 같은 특성,
새로운 위험 아님), 개요 화면의 눈/연필 토글이 실제로 서식 도구를 감추는지.

## [2026-08-11, 이어서 30] 확대보기 버그 수정 2건 + "관련 내용"(메모/문서 →
성경구절 역색인) 신설

사용자 요청 4건 — "① 확대보기 성경 구절 폰트/줄간격을 메인창과 통일(2.3), ②
내 메모에서 좌표만 지정해 만든 메모의 아이콘이 메인/확대보기에 안 보이는 버그,
③ 확대보기 메모 팝업의 글꼴 스타일 라인/장절정보 라인 순서 교체, ④ 메모/연구
문서 안의 성경구절을 추출해 DB에 인덱싱하고, 성경 조회 쪽(관주/메모 아이콘
자리 + 사이드바)에서 '이 구절을 언급한 메모/문서'를 확인·이동할 수 있게."

### ① 확대보기 폰트/줄간격 (버그는 아니지만 함께 처리)

`VerseZoomView.attributedVerseText`가 `.systemFont(ofSize: 22)`로 고정돼 있어
환경설정(모양 탭, S1 표시 폰트)과 달랐다 — `TranslationColumnView.VerseRow`가
쓰는 `UserSettingsStore.bibleFontName`/`bibleBodyFontSize`를 그대로 재사용하는
`bibleFont` 계산 프로퍼티로 바꿨다. 줄간격 2.3은 `RichTextEditor.swift`가 이미
쓰는 "배수" 해석(전체 줄 높이 = 기본 줄 높이 × 배수)을 그대로 따라
`NSParagraphStyle.lineSpacing = font.typographicLineHeight × (2.3 - 1)`로
환산했다 — 이 세션에서 "줄 간격 N" 요청을 일관되게 배수로 다뤄 왔다.
`VerseAnnotationRenderer.nsAttributedContent(...)`에 `paragraphStyle:`
파라미터를 추가해 반영했다(기본값 nil, 기존 호출부 영향 없음).

### ② 버그 — 내 메모(좌표만 지정) 아이콘 미표시

원인: `BibleReadingViewModel.phraseMemos(translationCode:verse:)`가
`rangeStart != nil`(구간 메모)만 걸렀다. "내 메모" 탭(MemoHomeView)에서
성경 좌표만 지정해 만든 절 전체 메모는 `rangeStart`가 nil이라 이 필터에서
항상 빠졌고, 그 결과 메인 화면/확대보기 어디에도 메모 아이콘이 뜨지 않았다.
구간 메모(특정 번역본의 특정 표현에 종속)는 그대로 그 번역본 컬럼에서만,
절 전체 메모(`rangeStart == nil`, 번역본과 무관)는 그 절을 보여주는 모든
컬럼에 노출하도록 필터를 고쳤다.

### ③ 확대보기 메모 팝업 — 스타일 도구 라인 순서

`MemoDetailView`(.contextual)에서 iOS 서식 툴바(굵게/기울임/색상/폰트)가
`RichTextEditor` 내부에 고정돼 있어 항상 헤더(성경장절정보+동기화정보) 뒤에
나왔다. `RichTextEditor`에 `showsToolbar`/`externalProxy` 파라미터를 추가하고
툴바 UI 자체를 `RichTextEditorToolbar`(iOS 전용 공개 타입)로 분리했다 —
`MemoDetailView`가 `.contextual`일 때 이 툴바를 직접 `header`보다 먼저 그리고,
`RichTextEditor` 내부 툴바는 끈 뒤 같은 프록시 인스턴스를 공유시켜(그래야
외부 버튼이 실제 텍스트뷰에 작용한다) 최종 순서를 "스타일 도구 → 장절정보/
동기화정보 → 폴더 → 본문"으로 바꿨다. `.standalone`(내 메모 탭)과 macOS(이
커스텀 툴바 자체가 없음 — 텍스트 선택 시 뜨는 네이티브 서식 팝업을 씀)는
영향받지 않는다.

### ④ "관련 내용" — 메모/연구문서 → 성경구절 역색인

**추출**: `Services/Bible/BibleReferenceExtractor.swift` 신설. `BooksProvider`의
책 이름/약칭 전체(길이 내림차순 정렬 — "요한복음"이 "요"에 가로채이지 않도록)로
정규식 알터네이션을 만들어 "요한복음 3:16" / "요 3장 16절" / "창1:1" 같은
표현을 찾는다. ⚠️ [의도적 범위 제한] 장 번호가 없는 순수 책 이름 언급은
추출하지 않는다(정규식에서 장 번호 그룹이 필수) — 일부 약칭이 흔한 한글
낱말과 겹칠 수 있어 숫자 없이는 오탐이 너무 잦다고 판단했다. 그래도 "약칭+
숫자" 조합이 성경 인용이 아닌 문맥과 우연히 겹칠 가능성은 남아 있다(완벽한
자연어 이해 없이는 피할 수 없는 한계로 받아들였다).

**저장**: 새 모델 `VerseMention`(`VerseMentions.swift`, 스키마 등록 완료) —
사용자 요청대로 "검색어로 삼을 원문텍스트"(`searchText`, 매칭된 원문 그대로)와
"구조화된 seq 정보"(`bookId`/`chapter`/`verse`)를 별도 필드로 저장한다. 출처는
`EmbeddingChunk`와 같은 패턴으로 관계가 아니라 `sourceId`(UUID 문자열) +
`sourceType`(memo/document)로 다형적으로 가리킨다 — `DocumentAnchor`(기존
모델, 문서 안의 정확한 위치까지 표현하는 더 무거운 구조)도 검토했지만
`UserMemo`에는 붙일 수 없는 구조라 재사용하지 않았다.

**재계산 시점**: `EmbeddingIndexingService`가 이미 쓰는 원칙("더티 플래그/유휴
스케줄러 없이, 관련 화면 진입 시마다 전체 재스캔해 바뀐 것만 갱신")을 그대로
따른다 — `BibleReferenceIndexingService.reindexMemosAndDocuments(context:)`를
`BibleReadingViewModel.onAppear()`(S1 진입 시점)에서 호출한다. 임베딩과 달리
순수 정규식이라 비동기/진행률 콜백 없이 동기로 처리했다 — ML 임베딩 계산만큼
비싸지 않다고 판단했다. 문서는 `indexStatus == .indexed`(OCR 검수 완료)인
것만 대상으로 한다.

**UI — 관주/메모 아이콘 자리**: `TranslationColumnView.VerseRow`(메인 읽기
화면)와 `VerseZoomView`(확대보기) 양쪽에 세 번째 아이콘("관련 내용",
`doc.text.magnifyingglass`)을 추가했다 — 관주/메모와 같은 자리, 같은 방식
(팝오버/목록)이다. 공용 `VerseMentionListView`가 목록 UI를 담당한다.

**UI — 구절 선택 사이드바**: `ChapterRelatedContentPanel`(성경 조회 오른쪽
인스펙터)에 절 하나가 정확히 선택돼 있을 때만(`viewModel.selectedVerses.count
== 1`) "N절 관련 내용" 섹션을 추가했다 — 언급하는 메모/문서의 3줄 미리보기를
보여준다. 다중 선택/선택 없음일 때는 섹션 자체를 숨긴다(어느 절 기준인지
모호해지기 때문 — VerseZoomView를 여는 조건과 같은 원칙).

**선택 시 이동 — "PDF로 띄워 검색"**: 메모를 고르면 기존 "메모 작성" 시트
흐름을 그대로 재사용해 연다. 연구문서를 고르면 새 `WindowGroup(id:
"document-search", for: DocumentSearchRequest.self)`(문서 ID + 검색어)를 연다.
⚠️ [지원 범위] 원본이 실제 PDF(`originalFormat == .pdf`)인 문서만 PDFKit
검색(`PDFDocument.findString` + `PDFView.go(to:)`)으로 정확히 그 위치로
스크롤+하이라이트된다. hwp/이미지 등 다른 형식은 이 앱에 PDF 변환 결과
(`ConvertedPDF`)를 실제로 뷰어에 연결하는 기능이 아직 없어(기존부터 그랬음 —
`DocumentViewerViewModel.resolvedURL`은 원본 파일만 해석한다), "추출 텍스트"
탭으로 열어 일치하는 줄로 스크롤하고 노란색으로 강조하는 것으로 대신했다 —
완전한 PDF 검색은 아니지만 "그 위치로 이동"이라는 목적은 달성한다.

### 정적 검증

주석/문자열을 걷어내고 괄호 균형 확인 — 새/수정 파일 16개(`VerseMentions.swift`,
`BibleResearchSchema.swift`, `BibleReferenceExtractor.swift`,
`BibleReferenceIndexingService.swift`, `DocumentSearchRequest.swift`,
`BibleReadingViewModel.swift`, `BibleReadingView.swift`,
`TranslationColumnView.swift`, `VerseZoomView.swift`,
`VerseAnnotationRenderer.swift`, `VerseMentionListView.swift`,
`ChapterRelatedContentPanel.swift`, `DocumentViewerView.swift`,
`RichTextEditor.swift`, `MemoDetailView.swift`, `JBCHBibleResearchApp.swift`)
모두 괄호/중괄호/대괄호 균형 OK. `VerseRow`/`TranslationColumnView`/
`VerseZoomView` 호출부의 새 인자(`verseMentions`/`verseMentionsProvider`/
`onSelectVerseMention`)가 프로퍼티 선언 순서와 정확히 일치하는지(Swift
memberwise init은 라벨 순서를 재배열할 수 없다) 개별 재확인했다.

⚠️ Xcode 확인 필요: `NSRegularExpression` 알터네이션이 66권 책 이름/약칭
전체(대략 300개 안팎)를 넣었을 때 실제 컴파일·매칭 성능이 허용 범위인지,
정규식 자체가 유효한 패턴으로 컴파일되는지(모든 책 이름을
`escapedPattern(for:)`로 이스케이프했지만 실기기 검증은 못 함), PDFKit
`document.findString(_:withOptions:)`가 한글 검색어에 대해서도 기대대로
동작하는지, `WindowGroup(id: "document-search", for: DocumentSearchRequest.self)`
같은 커스텀 `Codable & Hashable` 구조체를 값으로 쓰는 `WindowGroup`이 실기기에서
정상적으로 열리는지(기존 `PersistentIdentifier.self`/`for:` 패턴과 달리 이번이
처음 쓰는 "커스텀 구조체 값" 조합이다).

## [2026-08-11, 이어서 31] 사이드바 재구성 + 검색창 폰트 통일 + 형광펜/관주 팝업 정리

사용자 요청 4건 — "① 오른쪽 사이드바: 절 미선택/다중선택은 개요만, 절 하나
선택은 개요+관련 메모+연구문서, ② 모든 검색창 placeholder를 기본 글꼴/보통
크기로, ③ 확대보기 형광펜이 줄간격까지 칠해지는 문제, ④ 관주 연결 팝업 스타일
정리."

### ① 오른쪽 사이드바 — 절 선택 상태에 따른 섹션 재구성

`ChapterRelatedContentPanel`이 이전엔 메모/연구문서 섹션을 절 선택 여부와
무관하게 "이 장 전체" 기준으로 항상 보여줬다. 이제 개요 섹션만 상시 노출하고,
메모/연구문서 섹션은 정확히 절 하나가 선택돼 있을 때만(`viewModel.
selectedVerses.count == 1`) 나타난다 — 미선택/다중선택이면 개요만 남는다.

"관련"의 기준은 기존 기능을 잃지 않으려고 두 가지를 합쳤다: ① 메모 자신의
좌표가 정확히 이 절인 것(기존 "메모 작성" 흐름, "이 절에 작성됨" 라벨) +
문서는 업로드 시 "관련 성경 장"으로 수동 지정된 것(기존 `relatedChapterRef`/
`relatedDocuments` 기능, 그대로 유지), ② 메모/문서 본문에서 이 절 참조가
자동 추출된 것(`VerseMention`, 지난 라운드 "관련 내용" 인덱스, "본문에서
언급됨" 라벨). 지난 라운드에 별도로 넣었던 "N절 관련 내용" 통합 섹션은 이
두 섹션에 흡수해 없앴다 — 같은 정보가 "메모"/"관련 내용" 두 군데 다른
이름으로 겹쳐 보이는 걸 피했다.

⚠️ [해석 확인 필요] "관련 메모/연구문서"를 자동 추출(`VerseMention`) 기준으로
해석했다 — 만약 원래 의도가 "장 전체 메모/문서를 절 선택 시에만 보여주기"
(자동 추출과 무관)였다면 알려달라, 그 경우 훨씬 단순한 형태로 다시 바꿀 수
있다.

### ② 모든 검색창 placeholder 폰트

앱 전체 `.font()`를 따로 지정하지 않은 화면은 `RootView`/각 창의
`.appDefaultFont()`(Paperlogy 커스텀 폰트, 2026-08-08 신설)가 기본값으로
적용된다 — 검색창도 예외가 아니었다. 실제 사용자 입력용 검색
TextField 3곳(`MemoHomeView`의 "검색", `BookChapterPicker`의 "책 이름 검색",
"예:창세기1, 요3" 장 이동 입력)에 `.font(.body)`를 명시해 시스템 기본
글꼴/보통 크기로 되돌렸다 — 태그 입력란에 이미 적용했던 것과 같은 조치.
`SearchView`(S11 통합검색)의 `.searchable(text:prompt:)`는 네이티브
검색창(UISearchBar/NSSearchField 계열 컴포넌트)이라 애초에 앱의 `.font()`
환경값 영향을 받지 않아 손댈 게 없었다.

### ③ 확대보기 형광펜 — 줄간격 침범 수정

원인: TextKit이 `.backgroundColor` 어트리뷰트를 칠할 때 기본으로 "줄 조각
(line fragment) 전체 높이"를 채우는데, 이 높이에는 지난 라운드에 추가한
줄간격(2.3배)까지 포함돼 있었다 — 그래서 형광펜이 줄과 줄 사이 빈 공간까지
칠해졌다. 메인 화면(SwiftUI `Text`+`AttributedString.backgroundColor`)은
글리프 메트릭에만 맞춰 칠해서 이 문제가 없다.

고친 방법: `SelectableVerseTextView`(확대보기 전용 `UITextView`/`NSTextView`
래퍼)가 기본 텍스트스토리지/레이아웃매니저 대신, `NSLayoutManager`를 서브
클래싱한 `TightHighlightLayoutManager`를 직접 만들어 쓰도록 바꿨다.
`fillBackgroundRectArray(_:count:forCharacterRange:color:)`를 오버라이드해
실제로 채우는 사각형 높이를 "폰트의 순수 글자 높이"(`ascender - descender`,
줄간격/leading 제외)로 줄인다 — 각 줄의 세로 중심(`rect.midY`)을 기준으로
그 높이만큼만 채운다. 기본 `UITextView()`/`NSTextView()`는 자기만의 스토리지/
레이아웃매니저를 내부에서 만들어 버려 커스텀 레이아웃매니저를 끼울 수 없어서,
`UITextView(frame:textContainer:)`/`NSTextView(frame:textContainer:)`로 직접
텍스트스토리지→레이아웃매니저→텍스트컨테이너 체인을 만들어 넘기는 방식으로
바꿨다(`updateUIView`/`updateNSView`의 나머지 로직은 그대로 — TextKit 체인이
바뀌어도 `.attributedText`/`.textStorage` 접근 방식은 동일하다).

### ④ 관주 연결 팝업 스타일 정리

사용자 보고 — "구성이 틀어져 있음." 짐작되는 원인: 기본 `List` 스타일(inset
그룹류)이 작은 팝오버에서 여백을 과하게 차지하고, 관주 레코드가 여러 개일 때
(절 전체 관주 vs 특정 표현 관주가 섞여 있을 수 있음) 대상들이 구분 없이 한
목록으로 이어 붙어 어느 표현에 연결된 것인지 안 보였다. `.listStyle(.plain)`로
여백을 없애고, 레코드마다 `Section`으로 묶어 그 레코드가 "절 전체"인지 특정
표현(`anchorText`)에 대한 것인지 작은 헤더로 표시했다. 각 행은 `link.circle`
아이콘 + 대상 라벨(전체 폭 사용, 누르면 이동) + 삭제 버튼을 일관된 간격
(`spacing: 8`, 세로 패딩 3pt)으로 정리했다. 팝오버 최소 크기도 220×160 →
260×200으로 살짝 키웠다.

⚠️ [화면을 직접 못 보고 추측으로 수정] "구성이 틀어져 있음"이라는 보고만으로는
정확히 어떤 부분이 어떻게 틀어져 보였는지 알 수 없어 위 추정을 근거로
정리했다 — 여전히 마음에 안 드는 부분이 있으면 스크린샷이나 더 구체적인
설명을 주면 정확히 맞춰 고칠 수 있다.

### 정적 검증

주석/문자열을 걷어내고 괄호 균형 확인 — `ChapterRelatedContentPanel.swift`
82/82·44/44·0/0, `VerseZoomView.swift` 145/145·86/86·9/9,
`SelectableVerseTextView.swift` 83/83·49/49·11/11, `MemoHomeView.swift`
95/95·66/66·8/8, `BookChapterPicker.swift` 66/66·41/41·6/6. 모두 이상 없음.
`memoSection`/`documentSection`(새 `verse:` 매개변수 버전)과 지난 라운드의
"N절 관련 내용" 섹션이 중복 정의되지 않았는지 재검색해 확인했다.

⚠️ Xcode 확인 필요: `NSLayoutManager.fillBackgroundRectArray(_:count:
forCharacterRange:color:)`가 실제로 오버라이드 가능한 공개 API로 호출되는지
(TextKit1의 비교적 오래된 내부 호출 지점이라, 최신 OS에서 TextKit2로
전환됐을 때도 이 경로가 여전히 쓰이는지 실기기 확인이 필요하다 — 만약
`UITextView`/`NSTextView`가 TextKit2를 쓰도록 기본 전환됐다면 이 오버라이드
자체가 호출되지 않을 수 있다), 형광펜이 실제로 "딱 글자 높이"로 그려지는지,
관주 팝업의 `Section` 헤더가 여러 레코드일 때 시각적으로 원하는 정리 방식이
맞는지.

## [2026-08-11, 이어서 32]

지난 라운드(31)에서 스크린샷으로 지적받은 두 가지 잔여 버그와, 관주 연결
생성 시트의 레이아웃, 인덱싱 프로세스 설명, 성경 구절 범위지정 파싱까지
5건을 처리했다.

### ① 확대보기 형광펜 — 첫 줄(마지막 줄이 아닌 줄) 위치 오차 수정

31라운드에서 "형광펜이 줄간격까지 칠해짐"을 고치며 `TightHighlightLayoutManager.
fillBackgroundRectArray`가 칠하는 사각형을 글자 높이만큼(`ascender - descender`)
줄였는데, 그 사각형을 줄 조각(line fragment) rect의 **세로 중앙**
(`rect.midY - tightHeight/2`)에 맞췄던 게 잘못이었다 — 사용자가 스크린샷으로
확인해 준 대로 두 줄 이상인 구절에서 첫 줄의 형광펜이 실제 글자보다 아래로
처져 보였다.

원인: `NSParagraphStyle.lineSpacing`(확대보기가 2.3배로 키운 값)을 TextKit이
줄 조각 rect의 **아래쪽**에 여백으로 붙인다 — 즉 글리프 자체는 항상 rect의
위쪽(`minY`)에서 시작하고, 그 밑에 lineSpacing만큼 빈 공간이 딸려 있다.
마지막 줄(구절 끝)은 대부분 rect 높이가 글자 높이에 가까워 중앙 정렬해도 눈에
띄게 어긋나지 않았지만, 그 앞 줄들은 lineSpacing 여백까지 rect에 포함되다
보니 중앙 정렬이 곧 "여백의 절반만큼 아래로 밀림"이 되어 글자와 어긋났다.

`y: rect.midY - tightHeight / 2` → `y: rect.minY`로 바꿔 위쪽 기준 고정으로
수정했다(iOS `UIColor`/`UIFont` 버전, macOS `NSColor`/`NSFont` 버전 둘 다 —
`Views/Bible/SelectableVerseTextView.swift`).

### ② "관주 연결" 생성 시트 정리 + "장" 누락 수정

사용자가 스크린샷으로 지적한 "출애굽기 2 4절와(과) 연결할 구절"에서 "장"이
빠진 문제 — `VerseZoomView.swift`의 `.navigationTitle`은 이미 이전 라운드에서
"장"을 넣도록 고쳤었는데, 같은 파일의 `crossReferenceSourceLabel`(관주 연결
시트에 넘기는 라벨)에는 그 수정이 반영되지 않고 있었다. 동일하게 "장"을
삽입했다.

"관주연결의 구성이 틀어져 있음... 성경 검색하는 텍스트 입력은 성경 조회
메인창 상단에 있는 것처럼 할 것"이라는 요청은 `CrossReferenceTargetPicker.
swift`를 다시 뜯어봤다 — `BookChapterPicker`(책/장 선택 버튼 + 자유 텍스트
이동창) 자체는 이미 메인 화면(`BibleReadingView.chapterNavigationControls`)과
같은 컴포넌트를 재사용하고 있었지만, 이 시트에서는 그걸 `Form` + `Section`
안에 끼워 넣고 있었다 — `Form`이 자식 뷰를 "라벨: 컨트롤" 행으로 자체
배치하다 보니, 메인 화면의 평범한 `HStack`(`.safeAreaInset(edge: .top)` +
`.background(.bar)`) 배치와 전혀 다르게 보였다. 이게 "구성이 틀어져 있다"는
체감의 실제 원인으로 보여, `Form`/`Section`을 걷어내고 메인 화면과 동일하게
`HStack` + `.background(.bar)`로 바꿨다. 긴 안내 문장("OO장 N절와(과) 연결할
구절")도 `Section` 제목 자리(원래 짧은 라벨 하나만 들어가야 자연스러운 자리)
대신 그 위에 별도 캡션 텍스트(`.font(.subheadline)`, `.secondary`)로 뺐다.

⚠️ [화면을 직접 못 보고 추측으로 수정] "어떻게 설명하면 좋은가..."라는
사용자 표현 자체가 정확한 원인을 짚기 어려웠다는 뜻이라, 위 진단(Form의
행 배치 방식)이 근거 있는 가장 유력한 원인이라고 판단해 그에 맞춰 고쳤다 —
여전히 마음에 안 드는 부분이 있으면 스크린샷을 다시 확인해 맞춰 고칠 수
있다.

### ③ VerseMention 인덱싱(성경구절 추출) 프로세스 확인

"모든 첨부파일의 성경구절이 추출되어 DB에 입력돼 있던데, 초기작업을 임의로
한 것인가, 메모를 등록할 때마다 재추출하는가?"라는 질문에 대한 답 — 코드
동작을 다시 읽어 확인했다(`Services/Bible/BibleReferenceIndexingService.swift`):

- **트리거 시점**: 메모를 저장할 때마다 도는 게 아니라, **성경 조회(S1) 화면에
  들어갈 때마다**(`BibleReadingViewModel.onAppear()`) 전체를 다시 훑는다 —
  S11(통합 검색)의 임베딩 인덱스가 S11 진입 시마다 재계산되는 것과 정확히
  같은 원칙.
- **재계산 범위**: 매번 **모든** `UserMemo`와 **인덱싱 완료**(검수 끝난)
  상태인 `SourceDocument`를 전부 다시 스캔한다 — "이번에 새로 추가/수정된
  것만" 훑는 부분 스캔이 아니다.
- **다만 실제로 다시 쓰는(DB에 delete+insert) 건 바뀐 소스뿐**: 소스(메모 1개
  /문서 1개)마다 지금 텍스트에서 다시 추출한 결과와 DB에 이미 있는 결과를
  "지문(fingerprint)" 집합으로 비교해서, 완전히 같으면 건드리지 않고
  건너뛴다. 그래서 사용자가 본 "모든 첨부파일의 성경구절이 이미 DB에 들어가
  있다"는 상태는 임의의 1회성 초기 작업이 아니라, **S1 화면에 처음
  들어갔을 때 이 재스캔이 자동으로 한 번 돈 결과**다(문서를 몇 개 올렸든
  상관없이).
- 소스가 삭제되면 그 소스의 기존 인덱스 레코드(고아 레코드)도 같은 재스캔
  과정에서 함께 정리된다.

코드 변경은 없음 — 확인 결과를 사용자에게 그대로 전달.

### ④ 성경 구절 범위지정 파싱 ("갈1:6-9", "갈1:24-2:1")

`Services/Bible/BibleReferenceExtractor.swift`의 정규식에 범위 꼬리를 추가
그룹으로 인식하게 했다 — 그룹1/2(시작 장/절)는 그대로, 그룹3(범위 끝 장,
"-2:1"처럼 장까지 다시 적었을 때만 존재)/그룹4(범위 끝 절)를 새로 뒀다.
그룹4가 있으면 "범위 표기가 있다"는 뜻이고, 그룹3 유무로 같은 장 안의
범위("6-9")인지 장을 넘어가는 범위("24-2:1")인지 가른다.

매칭 하나(정규식 매치 1회)가 범위 안 절 개수만큼 `Match`를 여러 개 만들어
내는 방식으로 구현했다 — `Match`는 원래부터 "책+장+절 하나"를 뜻하는
타입이라, `BibleReferenceIndexingService`(Match → VerseMention 변환) 쪽은
전혀 손대지 않아도 된다. 예: "갈1:6-9" 하나가 갈1:6/갈1:7/갈1:8/갈1:9,
총 4개의 `Match`로 펼쳐지고 각각 별도 `VerseMention` 레코드가 된다(모두
`searchText`는 원문 그대로 "갈1:6-9"를 공유 — 실제로 인용된 원문 표기는
그대로 남기고, 좌표만 절별로 나눈다).

장을 넘어가는 범위("갈1:24-2:1")를 분해하려면 "1장이 실제로 몇 절까지
있는지" 알아야 2장으로 넘어갈 위치를 정할 수 있는데, 이 프로젝트엔 그
정보를 담은 정적 데이터가 없었다 — 조사해보니 `BibleReferenceStore`(번역본
SQLite 파일 읽기 전용 리더)에 `verses(bookId:chapter:)`로 특정 장의 전체
절을 가져오는 기존 API가 있어서, 그 결과의 최대 절 번호를 "그 장의 끝"으로
썼다. 여는 파일은 `TranslationBootstrap.resolvedBundledDatabaseURL()`이
가리키는 번들 기본 번역본(BibleDB.sqlite, 사용자가 어떤 번역본을 보고
있었는지와 무관하게 항상 같은 파일)이며, 한 번 연 뒤 정적으로 캐싱해 재사용한다.

⚠️ [번역본 간 절 구분(versification) 차이 가능성] 번역본마다 장/절을 나누는
지점이 한두 절 다를 수 있다 — 이 프로젝트에 "번역본과 무관한 장별 절 개수"
정적 데이터가 따로 없어 가장 신뢰할 수 있는 실제 데이터 소스(번들 번역본)를
기준으로 삼았다. 조회 자체가 실패하면(번들 DB 접근 실패 등) 추측하지 않고
시작 절 하나만 남기도록 안전장치를 뒀다(`expandRange` 함수). 비정상적으로
큰 범위(같은 장 안 300절 이상, 30개 장 이상)도 오탐으로 보고 같은 방식으로
방어했다.

### 정적 검증

주석/문자열을 걷어내고 괄호 균형 확인 — `SelectableVerseTextView.swift`
83/83·49/49·11/11, `VerseZoomView.swift` 145/145·86/86·9/9,
`CrossReferenceTargetPicker.swift` 53/53·21/21·4/4,
`BibleReferenceExtractor.swift` 70/70·46/46·16/16,
`BibleReferenceIndexingService.swift`(변경 없음, 재확인) 39/39·24/24·5/5.
모두 이상 없음.

⚠️ Xcode 확인 필요: `TightHighlightLayoutManager`의 `rect.minY` 기준 수정이
실기기에서 실제로 첫 줄부터 마지막 줄까지 모두 글자와 정확히 겹치는지,
`CrossReferenceTargetPicker`의 새 레이아웃이 실제로 메인 화면 상단바와
비슷한 인상을 주는지, 성경 구절 범위지정 파싱이 실제 번들 DB(BibleDB.sqlite)
데이터로 정확한 장 경계에서 끊기는지(특히 "갈1:24-2:1" 같은 장 경계 예시).

## [2026-08-11, 이어서 33]

같은 날 두 번째 라운드(스크린샷 2장 첨부). 인덱싱 트리거 재설계, 절 선택
폰트, "개인 주석"/"메모" 두 기능으로의 분리, 메모 표시(글자색+점선 박스),
확대보기 줄바꿈/줄간격까지 6건을 처리했다 — 이번 라운드 중 가장 큰 것은
③~⑤(신규 "메모" 기능)로, 새 SwiftData 모델 하나(`VersePhraseNote`)와
그걸 그리는 커스텀 TextKit 오버레이가 새로 생겼다.

### ① 인덱싱 트리거 — 화면 진입 → 저장/삭제 이벤트로 전환

31~32라운드에서 "화면 진입마다 전체 재스캔"으로 구현했던 것을, 사용자가
"메모/연구문서를 등록·수정할 때마다, 삭제하면 관련 인덱스도 같이 지워지도록"
바꿔 달라고 요청해 트리거 자체를 다시 설계했다.

`BibleReferenceIndexingService.swift`에 소스 하나만 다시 계산하는
`reindexMemo(_:context:)`/`reindexDocument(_:context:)`(그 소스의 기존
레코드를 지우고 지금 텍스트로 다시 추출)와, 삭제 시 호출하는
`removeMentions(sourceType:sourceId:context:)`를 추가했다. 실제 호출 지점:

- 메모 생성: `MemoHomeView.createNewMemo`, `BibleReadingView.createMemo`,
  `BibleReadingViewModel.createPhraseMemo`/`openOrCreateVerseMemo`(아래 ③).
- 메모 저장(디바운스/즉시 저장 공통): `MemoDetailView`가
  `AutosaveController`에 새로 추가한 `didSave` 클로저로 연결 — 실제
  `modelContext.save()`가 성공한 직후에만 부른다.
- 메모 삭제: `MemoHomeView.delete`/`deleteMemos`, `MemoDetailView`의 "빈
  메모 자동 정리"(`AutosaveController.deleteIfEmpty`에 새로 추가한
  `beforeDelete` 클로저).
- 문서: `DocumentTextExtractionService`(PDF/doc 추출이 `indexStatus =
  .indexed`가 되는 시점 — extractPDF/extractDoc 둘 다), `OCRReviewViewModel.
  save()`(검수 확정), 삭제는 `DocumentsViewModel.delete`/
  `OCRReviewViewModel.discard`.

`BibleReadingViewModel.onAppear()`에서 전체 재스캔 호출은 제거했다.

⚠️ [백필 공백 가능성] 기존 `reindexMemosAndDocuments`(전체 재스캔) 함수
자체는 코드로 남겨 뒀지만 더 이상 자동으로 안 불린다 — 이 기능이 생기기
전부터 있었지만 그 뒤로 한 번도 저장/삭제되지 않은 메모/문서(또는 다른
기기에서 막 동기화돼 온 데이터)는 인덱스가 비어 있을 수 있다. 이번 세션에서
만든 데이터는 이미 이전 라운드들의 화면 진입 재스캔으로 인덱싱이 끝난
상태라 당장은 문제없지만, 새 기기 첫 실행 같은 시나리오까지 대비한 1회성
백필이 필요하면 알려달라 — `reindexMemosAndDocuments`를 앱 시작 시 한 번만
부르는 지점을 추가하면 된다.

### ② 절 선택(Stepper) 폰트

`CrossReferenceTargetPicker`의 "N절" Stepper 라벨에 `.font(.body)`를
명시(원래 지정이 없어 루트의 Paperlogy 기본 글꼴이 그대로 적용되고
있었다). `MemoDetailView`(내 메모 탭)의 같은 종류 Stepper 라벨은 이미
`.font(.caption)`(시스템 폰트지만 작은 크기)이 있었는데, "일반 크기"
요청에 맞춰 `.body`로 키웠다.

### ③ "메모" → "개인 주석" 개명 + 항상 활성화

확대보기 액션바의 기존 "메모" 버튼(드래그 선택이 있어야만 눌리고, 선택
구간에 종속된 구간 메모를 만들던 버튼)을 "관주"처럼 선택 여부와 무관하게
항상 눌리도록 바꾸고, 이제 드래그 상태를 아예 보지 않고 **절 전체**
메모(`UserMemo`, `rangeStart == nil`)를 열거나(있으면) 새로 만든다(없으면).
`BibleReadingViewModel.verseLevelMemo(verse:)`/`openOrCreateVerseMemo(verse:)`
를 새로 추가했다. 라벨은 "메모"→"개인 주석"으로 바꿨고, 확대보기 하단
목록 라벨("메모 N개"→"개인 주석 N개")과 메인 화면 절 우클릭 메뉴("메모
작성"→"개인 주석 작성")도 같은 개념이라 맞춰 바꿨다(`BibleReadingView.
createMemo`에 이벤트 기반 인덱싱 호출이 빠져 있던 것도 이번에 같이 채웠다
— ①에서 놓쳤던 세 번째 메모 생성 경로).

### ④ 신규 "메모" 기능 — 드래그한 표현에 짧은 텍스트 부연설명

새 SwiftData 모델 `VersePhraseNote`(`VerseAnnotations.swift`,
`BibleResearchSchema.modelTypes`에 등록)를 만들었다 — `VerseHighlight`와
똑같은 앵커 구조(번역본 코드 + 좌표 + 문자 오프셋 + 스냅샷 텍스트, 자가
치유 재정렬도 `VerseAnnotationRenderer.resolvedRange`를 그대로 재사용)에,
색상 태그 대신 `noteText: String`(한글 기준 199자 제한,
`NoteTextLimit.maxCharacters`)을 담는다.

확대보기 액션바에 새 "메모" 버튼(아이콘 `text.bubble`, 드래그 선택 있어야
활성화 — 예전 "메모" 버튼과 같은 조건, 이름만 이 기능이 이어받았다)을
추가했고, 누르면 새로 만든 `PhraseNoteEditorPopover.swift`(인용된 표현 +
`TextEditor` + 글자 수 카운터 + 저장/취소/삭제)가 뜬다.
`BibleReadingViewModel`에 `phraseNotes(translationCode:verse:)`/
`addPhraseNote`/`updatePhraseNote`/`deletePhraseNote`와 `chapterPhraseNotes`
캐시를 추가했다(형광펜/표시와 같은 패턴).

"마우스 오른쪽 버튼 -> 팝업창에 메모 수정, 삭제"는 `SelectableVerseTextView`
의 기존 형광펜/표시 취소 메커니즘을 확장해 구현했다 — `phraseNotes`/
`hitPhraseNote(at:)`를 추가하고, iOS 편집 메뉴(`editMenuForTextIn:`)와
macOS 우클릭 메뉴(`menu:for:at:`) 둘 다에 "메모 수정"/"메모 삭제" 두
항목을 끼워 넣는다(형광펜과 겹쳐도 함께 나타날 수 있다).

### ⑤ 메모 표시 — 글자색 + 확대보기 점선 박스

**글자색**: `VerseAnnotationRenderer`에 `phraseNoteTextColor`(SwiftUI
`.blue`)/`phraseNoteTextPlatformColor`(`.systemBlue`) 상수를 추가하고,
`attributedContent`(메인 화면, SwiftUI `AttributedString` 경로)와
`nsAttributedContent`(확대보기, `NSAttributedString` 경로) 둘 다
`phraseNotes` 파라미터를 받아 그 구간의 글자색을 바꾸도록 확장했다.
`attributedContent`는 형광펜(배경색)/표시(밑줄)와 메모(글자색)가 서로
독립적으로 겹칠 수 있어(예: 같은 표현에 형광펜 + 메모 둘 다), 기존의
"형광펜 구간 순서대로 이어 붙이기" 방식을 "모든 구간 경계점을 모아 겹치지
않는 최소 조각으로 나누고 조각마다 독립적으로 형광펜/메모 속성을 확인"하는
방식으로 다시 짰다(`nsAttributedContent`는 `NSMutableAttributedString`이
겹치는 범위에 속성을 독립적으로 더할 수 있어 이런 재작성이 필요 없었다).
`TranslationColumnView.VerseRow`/`TranslationColumnView`에
`phraseNotes`/`phraseNotesProvider`를 새로 꿰어 메인 화면에도 반영했다.

**점선 박스**(확대보기 전용): 표현이 있는 줄 바로 아래, 줄간격이 벌어진
빈 공간에 300×100px 점선 박스(회색 텍스트)를 정확히 겹쳐 그리려면 실제
텍스트 레이아웃(글리프 좌표)이 필요해, `SelectableVerseTextView`가
`NSLayoutManager`로 그 표현의 타이트한 바운딩 박스(`boundingRect(forGlyphRange:in:)`
— 줄간격이 아니라 순수 글자 높이 기준, 줄간격을 나중에 넓혀도 흔들리지
않는다)와 그 줄 전체의 문자 범위를 계산해 `PhraseNoteOverlayRect`(신설
타입)로 돌려준다. `VerseZoomView`가 이 결과를 `.overlay(alignment:
.topLeading)` + `.offset`으로 겹쳐 그린다(새 뷰 `PhraseNoteBoxView`,
연결선 + 점선 테두리 + 회색 텍스트, 탭하면 수정 팝오버).

### ⑥ 확대보기 줄바꿈 폭(17~25자) + 왼쪽 정렬 + 메모 줄 줄간격 확장

**폭 제한**: 한글 음절은 대부분 서체에서 거의 고정폭(전각)이라는 특성을
이용해, "가" 한 글자의 실측 폭(`bibleFont` 기준) × 목표 글자수(21, 17~25
중간값)로 텍스트 컨테이너 폭을 고정했다 — `SelectableVerseTextView`에
`preferredTextWidth` 파라미터를 추가해 `widthTracksTextView`(뷰 폭을
그대로 따라가던 기존 동작) 대신 이 고정폭을 쓰게 했다.

⚠️ [근사치, 확인 필요] 이 방식은 "정확히 몇 자"를 보장하지 못한다 — 라틴
문자/숫자/문장부호가 섞이면 실제 글자수가 더 늘어날 수 있다. 정확한
글자수 강제(실제 줄바꿈 문자 삽입)는 구간 주석(형광펜/표시/관주/메모)의
`rangeStart`/`rangeEnd`가 원본 절 텍스트 오프셋을 그대로 쓰고 있어, 텍스트에
줄바꿈을 끼워 넣으면 `SelectableVerseTextView.selectedRange`(수정된 텍스트
기준)와 `VerseZoomView.anchorText`(원본 `verseText` 기준)가 서로 다른
좌표계를 가리키게 돼 새로 만드는 주석의 위치가 틀어질 위험이 있었다 —
이번엔 그 위험을 피하는 안전한 근사치를 택했다. 실기기에서 범위를 벗어나는
사례가 잦으면 목표 글자수 상수(`VerseZoomView.preferredTextWidth`의
`targetCharsPerLine`)만 조정하면 된다.

**왼쪽 정렬**: `bibleParagraphStyle`/`wideBibleParagraphStyle`에
`.alignment = .left`, `.lineBreakMode = .byWordWrapping`(어절 단위
줄바꿈, 이미 기본값이지만 명시)을 추가했고, `SelectableVerseTextView`를
감싸는 `ScrollView` 콘텐츠에 `.frame(maxWidth: .infinity, alignment:
.leading)`를 붙여 고정폭 텍스트 블록이 화면 왼쪽에 붙게 했다.

**메모 줄만 줄간격 확장**: `nsAttributedContent`에
`wideParagraphStyle`/`wideSpacingRanges` 파라미터를 추가해, 특정 문자
범위에는 기본 2.3배 대신 더 넓은(고정 116pt — 점선 박스 100pt + 연결선
8pt + 여유) 줄간격을 덮어 적용할 수 있게 했다. "메모가 있는 줄"의 범위는
`SelectableVerseTextView`가 위 ⑤에서 계산해 준 `PhraseNoteOverlayRect.
lineCharacterRange`를 그대로 쓴다 — 최초 렌더링(레이아웃 결과가 아직 없을
때)엔 좁은 간격으로 한 번 그려졌다가, 레이아웃 결과가 돌아오면 그 줄만
다시 넓혀 그리는 2단계 수렴 방식이다(줄간격은 가로 줄바꿈 위치에 영향을
주지 않으므로 "어느 줄에 메모가 있는지" 자체는 패스가 바뀌어도 변하지
않아 무한 루프 없이 한 번에 안정된다).

### 정적 검증

주석/문자열을 걷어내고 괄호 균형 확인 — `BibleReadingViewModel.swift`
185/185·96/96·52/52, `BibleReferenceIndexingService.swift`
61/61·37/37·6/6, `AutosaveController.swift` 26/26·15/15·1/1,
`MemoDetailView.swift` 153/153·93/93·16/16, `MemoHomeView.swift`
98/98·66/66·8/8, `DocumentTextExtractionService.swift` 65/65·31/31·5/5,
`OCRReviewViewModel.swift` 24/24·12/12·1/1, `DocumentsViewModel.swift`
41/41·23/23·9/9, `VerseZoomView.swift` 162/162·102/102·15/15,
`BibleReadingView.swift` 144/144·111/111·0/0,
`TranslationColumnView.swift` 136/136·85/85·22/22,
`CrossReferenceTargetPicker.swift` 54/54·21/21·4/4,
`VerseAnnotations.swift` 11/11·15/15·4/4,
`BibleResearchSchema.swift` 5/5·3/3·3/3,
`SelectableVerseTextView.swift` 152/152·90/90·26/26,
`PhraseNoteEditorPopover.swift`(신규) 65/65·14/14·1/1,
`VerseAnnotationRenderer.swift` 45/45·32/32·16/16. 모두 이상 없음.

⚠️ Xcode 확인 필요(이번 라운드분): `VersePhraseNote`가 CloudKit 스키마에
정상 반영되는지(모델 추가 시 다른 신규 모델들처럼 최초 실행 시 컨테이너가
자동 반영해야 함), 점선 박스 위치 계산(`boundingRect`/`lineFragmentRect`
기반)이 실기기에서 표현 바로 아래에 정확히 맞는지, 줄간격 2단계 수렴이
실제로 첫 렌더링에서 눈에 띄는 "깜빡임"(좁았다가 넓어짐) 없이 매끄러운지,
`preferredTextWidth`가 실제로 17~25자 범위 안에 대체로 들어오는지(위 ⑥
⚠️ 참고), `AutosaveController.didSave`/`deleteIfEmpty(beforeDelete:)`
클로저 추가가 기존 다른 사용처(BookOutline/ChapterSummary 자동저장)에
부작용이 없는지(기본값 nil이라 이론상 안전하지만 미확인).

## [2026-08-11, 이어서 34]

같은 날 세 번째 라운드. "이어서 33"에서 만든 근사치 두 개(줄바꿈 폭, 메모
줄간격)를 사용자가 직접 지적해 더 정확한 방식으로 다시 구현했다.

### ① 확대보기 줄바꿈 — 컨테이너 폭 근사 → 정확한 23자 지점 강제 줄바꿈

이전 라운드는 "가" 한 글자 실측 폭 × 21(목표 글자수)로 텍스트 컨테이너
폭을 고정해 TextKit이 "대략" 17~25자에서 자연 줄바꿈하도록 유도하는
근사치였다. 사용자가 "성경 구절에는 라틴, 숫자가 포함되지 않음 — 그러니
23자 지점을 찾고 그 앞뒤로 가장 가까운 띄어쓰기에서 정확히 끊어라. 단
영문 성경 등은 기존 방식(근사폭) 그대로 두라"고 정정했다.

`VerseAnnotationRenderer.swift`에 `lineBreakPositions(in:targetCharsPerLine:)`
(줄 시작에서 23번째 글자 위치를 목표점으로 잡고 `nearestSpaceIndex`로 그
지점에서 가장 가까운 띄어쓰기를 앞뒤로 찾아 다음 줄 시작을 그 다음 글자로
이동 — 이 과정을 절 끝까지 반복. 남은 구간에 띄어쓰기가 아예 없으면
그 줄에서 멈춘다, 즉 글자 중간에서는 절대 안 끊는다)와
`containsLatinOrDigit(_:)`(라틴 A-Z/a-z, 숫자 0-9 유니코드 스칼라 포함
여부 검사 — 번역본에 "언어" 필드가 없어 텍스트 자체로 판정, 번들 한글
번역본은 항상 없고 KJV 등 영문 성경은 항상 있어 실질적으로 번역본 구분과
같은 효과)을 추가했다.

`nsAttributedContent(...)`에 `hardWrapAtSpaces`/`hardWrapTargetChars`
파라미터를 추가해, true일 때 위에서 찾은 각 지점의 띄어쓰기(U+0020)를 줄
구분자(U+2028, LINE SEPARATOR)로 **치환**한다 — 삽입이 아니라 길이가
그대로인 1:1 치환이라 형광펜/표시/메모/관주가 쓰는 문자 오프셋
(`rangeStart`/`rangeEnd`, 원본 DB 텍스트 기준)이 전혀 흔들리지 않는다.
`\n`(단락 구분자) 대신 `\u{2028}`(줄 구분자)을 쓴 이유는 문단 자체는
하나로 유지하면서 줄바꿈만 강제하기 위해서다 — 자연 줄바꿈 때 줄 끝
띄어쓰기가 안 보이는 것과 시각적으로 동일한 효과.

`VerseZoomView.attributedVerseText`가 `hardWrapAtSpaces:
!VerseAnnotationRenderer.containsLatinOrDigit(verseText)`를 넘기고,
`preferredTextWidth`(텍스트 컨테이너 고정폭)는 라틴/숫자가 있을 때만(영문
성경 등, "그대로 유지") 이전 근사폭 로직을 쓰고, 없을 때는 `nil`(컨테이너
폭 제한 없음)을 돌려준다 — 우리가 정확히 계산한 지점 말고 폭 기반 자동
줄바꿈이 추가로 끼어들지 않게 하기 위해서다.

⚠️ [영문 등 근사치는 여전함] 라틴 문자가 섞인 텍스트(영문 성경 등)는
"그대로 유지" 요청대로 이전 근사치 방식 그대로다 — 한글 절 쪽만 이번에
정확한 계산으로 바뀌었다.

### ② 메모 박스 — 고정 크기·고정 줄간격 → 내용에 맞는 가변 크기·간격

이전 라운드는 점선 박스를 항상 300×92pt로 고정(연결선 8pt 포함 대략
100pt)하고, 메모가 있는 줄의 줄간격도 항상 고정값 116을 썼다 — 메모가
짧아도 항상 큰 여백이 남았다. 사용자가 "박스는 내용 길이만큼 유연성을
갖되 최대 300×100으로, 그리고 박스를 텍스트에 좀 더 가깝게(연결선 간격
축소)"라고 정정했다.

`SelectableVerseTextView.swift`의 `PhraseNoteOverlayRect`에
`estimatedContentHeight: CGFloat` 필드와 정적 함수
`estimatedContentHeight(for:)`(캡션 크기(12pt) 시스템 폰트로
`NSString.boundingRect`를 박스 폭 302pt 기준으로 계산해 실제 필요한 높이를
추정, `PhraseNoteBoxView.minHeight`(24)~`maxHeight`(100) 사이로 클램프)를
추가했다 — iOS/macOS `Coordinator.updateNoteOverlays(in:)` 둘 다 이 값을
계산해 넣는다.

`PhraseNoteEditorPopover.swift`의 `PhraseNoteBoxView`: 연결선 높이를
8pt→4pt로 줄이고(요청한 "텍스트와 좀 더 가깝게"), 박스 자체는
`.fixedSize(horizontal: false, vertical: true)`로 실제 내용 높이를 먼저
구한 뒤 `.frame(maxHeight: overlay.estimatedContentHeight)` + `.clipped()`
로 상한(그 메모의 추정 높이, 최대 100)을 씌운다 — 폭은 줄바꿈 계산 기준
상한(300)으로 고정해 두고 높이만 내용에 따라 줄어들거나 커진다.

`VerseAnnotationRenderer.nsAttributedContent`의 줄간격 파라미터를
`wideParagraphStyle: NSParagraphStyle?`(모든 메모줄 공통 고정값) 하나에서
`wideSpacingRanges: [(range: NSRange, lineSpacing: CGFloat)]`(구간마다 다른
값)로 바꿨다. `VerseZoomView.noteWideSpacingRanges`가 각 메모의
`estimatedContentHeight + 연결선(4) + 여유(4)`와 "평소 줄(2.3배) 줄간격"
중 더 큰 값을 그 줄의 줄간격으로 쓴다(평소보다 좁아지지는 않게 하는
바닥값) — 짧은 메모는 딱 필요한 만큼만, 긴 메모는 최대 100pt까지 벌어진다.
한 줄에 메모가 여럿이면(드문 경우) 그중 최댓값을 쓴다.

⚠️ [SwiftUI-TextKit 측정 어긋남 가능] `estimatedContentHeight`는 TextKit
레이아웃 패스(줄간격 예약) 시점에 SwiftUI `Text`가 실제로 얼마나 높게
그릴지 미리 알 수 없어 다른 렌더링 엔진(NSString.boundingRect, 고정
12pt 캡션 근사 폰트)으로 근사한 값이다 — 실기기에서 SwiftUI가 그리는 실제
박스 높이와 몇 pt 어긋나면(특히 한글 자소 조합/커닝 차이) 박스가 다음
줄과 살짝 겹치거나 반대로 빈 공간이 남을 수 있다. 어긋남이 잦으면
`SelectableVerseTextView.PhraseNoteOverlayRect.estimatedContentHeight(for:)`
안의 여유값(`verticalPadding`)이나 `VerseZoomView.noteLineSpacingHints`의
`bottomMargin`을 늘리면 된다.

### 정적 검증

`VerseAnnotationRenderer.swift` 66/66·48/48·20/20,
`SelectableVerseTextView.swift` 161/161·91/91·28/28,
`PhraseNoteEditorPopover.swift` 67/67·14/14·1/1,
`VerseZoomView.swift` 171/171·106/106·19/19. 모두 이상 없음.

⚠️ Xcode 확인 필요(이번 라운드분): 실제 번들 한글 번역본 절 텍스트로
23자 지점 줄바꿈이 육안으로 자연스러운지(특히 문장부호가 붙은 경우 —
"." "," 등은 라틴/숫자 판정에 걸리지 않아 한글 경로를 그대로 타는데, 이
경로는 "라틴/숫자 없음"만 검사하지 문장부호 앞뒤 줄바꿈 적합성까지는
따지지 않는다), 영문 성경(KJV 등)이 이전과 동일하게 근사폭 방식으로
동작하는지, 메모 박스 실제 렌더링 높이와 예약된 줄간격이 실기기에서
어긋나지 않는지(위 ⚠️ 참고), 매우 짧은 메모(한두 글자)일 때 박스가 너무
작아져 점선 테두리·패딩이 어색해 보이지 않는지.

## [2026-08-11, 이어서 35]

같은 날 네 번째 라운드. 사용자가 실제 화면 스크린샷을 첨부해 "이어서 34"
구현 두 가지가 실기기에서 기대대로 동작하지 않는다고 지적했다 — 근본
원인을 다시 진단해 고쳤다.

### ① 메모줄 줄간격이 전혀 안 벌어지던 버그 — 원인: 잘못된 API 계층

스크린샷 확인 결과 메모가 있는 줄도 다른 줄과 똑같이 2.3배 줄간격 그대로
렌더링되고 있었다("나무 진을" 메모의 점선 박스가 바로 다음 줄 "거기 담아
하숫가"와 겹침). "이어서 34"의 구현은 `NSMutableAttributedString`에
`NSParagraphStyle`을 문자 범위별로 다르게 얹는 방식이었는데, 다시
따져보니 `NSParagraphStyle`은 원래 "문단"(단락 구분자 `\n`/`\r` 기준)
단위 속성이다 — 우리 절 텍스트는 실제 줄바꿈 문자가 없는 하나의 문단
(그 안에서 강제 줄바꿈은 `\u{2028}`로 대체 구현했다)이라, 그 안에서
문자 범위별로 다른 `NSParagraphStyle`을 얹어도 TextKit이 "줄마다" 그
값을 읽어 준다는 보장이 없다 — 실기기에서 확인해 보니 실제로 반영되지
않았다.

Apple이 정확히 이 용도(문단 안에서 줄마다 다른 줄간격)로 제공하는 공식
API가 따로 있다 — `NSLayoutManagerDelegate.layoutManager(_:
lineSpacingAfterGlyphAt:withProposedLineFragmentRect:)`. TextKit이 줄
하나의 레이아웃을 마칠 때마다 "다음 줄까지 얼마나 띄울지"를 델리게이트에
직접 물어보는 지점이라, "줄 단위로 각각 컨트롤"이 정확히 이 API의
설계 목적이다.

`SelectableVerseTextView`의 `Coordinator`(iOS/macOS 둘 다)가
`NSLayoutManagerDelegate`를 채택하고, `layoutManager.delegate =
context.coordinator`를 `makeUIView`/`makeNSView`에서 연결했다. 델리게이트
구현은 방금 완성된 줄의 문자 범위를(`lineFragmentRect(forGlyphAt:
effectiveRange:)` + `characterRange(forGlyphRange:)`, `updateNoteOverlays`가
이미 쓰던 것과 같은 API) 새로 추가한 `noteLineSpacingHints: [(range:
NSRange, lineSpacing: CGFloat)]`(구조체 새 파라미터)와 대조해 겹치면 그
줄간격을, 아니면 텍스트에 걸린 기본 `NSParagraphStyle.lineSpacing`(2.3배
값)을 그대로 돌려준다 — 이 델리게이트를 구현하면 TextKit이 문단
자체의 `lineSpacing`을 더 이상 자동으로 안 쓰기 때문에 기본값도 직접
챙겨 줘야 한다. `VerseAnnotationRenderer.nsAttributedContent`에서는 이제
줄간격 관련 파라미터(`wideSpacingRanges`)를 아예 없애고 원래대로 단일
`paragraphStyle` 하나만 받는다 — 가변 줄간격은 전부 이 델리게이트가
맡는다.

사용자 재확인 — "2.3은 메모가 없을 때 기본 간격, 메모가 있으면 2.3을
무시하고 최대 120px으로." `VerseZoomView.noteLineSpacingHints`(옛
`noteWideSpacingRanges`, 델리게이트가 참조하는 힌트 목록으로 역할이
바뀌어 이름도 바꿨다)의 계산식을 "평소 줄간격을 바닥값으로 쓰던" 방식
(`max(base, needed)`)에서 "메모가 있으면 평소 값 무시, 필요한 만큼만,
최대 120px로 클램프"(`min(needed, 120)`)로 바꿨다.

### ② "나무 진을" 메모 박스가 표현에서 멀리 떨어져 보이던 문제 — ①의 부작용

이건 별도 버그가 아니라 ①이 안 먹혀서 생긴 결과였다 — 박스 자체의
앵커 위치(그 표현의 타이트 글리프 바운딩 박스 바로 아래)는 원래도
정확했지만, 다음 줄이 밀려나지 않아 박스가 다음 줄 내용과 겹쳐
보였다. ①을 고치면서 같이 해결됐다.

### ③ 형광펜이 화면 오른쪽 끝까지 칠해지던 버그

"아이를" 뒤가 우리가 심은 강제 줄바꿈(U+2028) 지점이었는데, 그 위치에
칠해진 형광펜 배경이 그 줄 끝까지가 아니라 컨테이너 폭 전체(화면 끝)까지
칠해졌다. `TightHighlightLayoutManager.fillBackgroundRectArray`가 지금까지
Apple이 넘겨주는 `rectArray`의 x/width를 그대로 믿고 높이(y/height)만
조정했는데, Apple 기본 구현은 문자 범위가 강제 줄바꿈 바로 앞에서 끝날 때
"그 줄의 남은 폭 전체"를 칠하는 사각형을 준다 — "이어서 34"에서 확대보기
컨테이너 폭을 무제한(`preferredTextWidth: nil`)으로 바꾸면서 그 여백이
갑자기 화면 끝까지로 넓어져 눈에 띄게 드러났다(예전엔 컨테이너 자체가
좁아 무시할 만한 수준이었다).

Apple이 준 rect를 신뢰하는 대신, 그 문자 범위를 `enumerateLineFragments`로
줄 단위로 나누고 각 줄에서 실제 글리프가 차지하는 타이트한 폭을
`boundingRect(forGlyphRange:in:)`로 직접 다시 계산해 채우도록 두 플랫폼
모두 고쳤다 — 형광펜이 여러 줄에 걸치는 경우(사용자가 드래그로 강제
줄바꿈을 가로질러 선택한 경우)에도 각 줄마다 정확한 폭으로 칠해진다.

### 정적 검증

`VerseAnnotationRenderer.swift` 59/59·45/45·18/18,
`SelectableVerseTextView.swift` 185/185·103/103·32/32,
`PhraseNoteEditorPopover.swift` 67/67·14/14·1/1,
`VerseZoomView.swift` 170/170·106/106·19/19. 모두 이상 없음.

⚠️ Xcode 확인 필요(이번 라운드분): `NSLayoutManagerDelegate.
lineSpacingAfterGlyphAt(...)` 안에서 `layoutManager.lineFragmentRect(forGlyphAt:
effectiveRange:)`를 호출하는 게(레이아웃이 진행되는 도중 같은 레이아웃
매니저에 다시 질의하는 형태) 실기기에서 항상 안전한지(이론상 "이미 끝난
줄"에 대한 질의라 안전해야 하지만, TextKit 재진입 이슈는 실기기가 아니면
확신하기 어렵다) — 문제가 생기면(예: 레이아웃 무한루프, 크래시) 이
델리게이트 안에서 `lineFragmentRect` 재질의 대신 `Coordinator`가 직접
"방금까지 처리한 문자 위치"를 순번대로 누적하는 상태 기반 방식으로
바꿔야 한다. 그 외: 메모줄이 실제로 최대 120px까지 벌어지고 그 안에
박스가 잘 들어맞는지, 형광펜이 강제 줄바꿈을 가로질러 여러 줄에 걸칠 때도
정확히 칠해지는지, 이번 수정이 (형광펜 폭 계산을 매번 다시 하므로) 텍스트가
길 때 스크롤/리사이즈 성능에 체감되는 영향이 없는지.

## [2026-08-11, 이어서 36]

같은 날 다섯 번째 라운드. "이어서 35"에서 넣은 `NSLayoutManagerDelegate`가
실기기에서 확대보기 진입 즉시 스택 오버플로 크래시를 냈다 — 사용자가
크래시 로그(24000단 넘는 재귀 스택 트레이스)를 첨부해 알려줬다.

### 원인 — 델리게이트 안에서 레이아웃을 다시 질의한 재귀

크래시 로그를 보면 `layoutManager(_:lineSpacingAfterGlyphAt:...)` →
`lineFragmentRect(forGlyphAt:effectiveRange:)` → (그 글리프의 줄이 아직
안 만들어진 "레이아웃 구멍" 상태라) `_fillLayoutHoleForCharacterRange` →
다시 타이프세팅 → 다시 같은 델리게이트 호출... 이 패턴이 그대로 반복된다.
"이어서 35"에서 이 델리게이트 구현 시 "이미 완성된 줄을 조회하는 것이라
안전할 것"이라고 판단했는데, 실제로는 TextKit이 "지금 막 이 줄의 레이아웃을
끝냈다"고 델리게이트를 부르는 시점과 "그 줄의 지오메트리를
`lineFragmentRect`로 다시 안전하게 질의할 수 있는 시점"이 같지 않았다 —
같은 콜백 안에서 레이아웃 관련 질의(geometry query)를 다시 하는 것 자체가
TextKit1의 재진입 금지 구간을 건드린 것으로 보인다.

### 수정 — 레이아웃 질의 없이 순수 인덱스 추적으로 재작성

`layoutManager.lineFragmentRect(forGlyphAt:effectiveRange:)` 호출을
완전히 제거했다. 대신 TextKit이 이 델리게이트를 한 레이아웃 패스 안에서
글리프 인덱스 오름차순으로(줄 순서대로) 부른다는 점을 이용해,
`Coordinator`가 `lastLineEndCharIndex`(직전 줄의 끝 문자 위치)를 상태로
들고 있다가 "이번 줄의 범위 = (직전 줄 끝 + 1) ~ 이번 줄 끝"으로
재구성한다. "이번 줄 끝" 자체는 `characterIndexForGlyph(at:)`로 구하는데,
이건 글리프 생성 단계에서 이미 만들어진 매핑 배열을 읽는 것뿐이라
레이아웃을 트리거하지 않아 안전하다. 레이아웃이 처음부터 다시 시작되는
경우(패스 재시작, 텍스트 변경 등)는 새 `charIndex`가 직전 값보다 작거나
같아지는 것으로 감지해 카운터를 리셋한다.

메모줄 판정("이 힌트 구간이 이 줄과 겹치는가")과 기본 줄간격 조회(텍스트
스토리지의 `.paragraphStyle` 속성 읽기)는 원래 로직 그대로 유지했다 —
둘 다 레이아웃이 아니라 순수 데이터 조회라 재귀 위험이 없다.

### 정적 검증

`SelectableVerseTextView.swift` 181/181·105/105·32/32. 이상 없음(이번
라운드에서 수정한 파일은 이 하나뿐).

⚠️ Xcode 확인 필요(이번 라운드분): 실기기에서 확대보기가 이제 크래시 없이
열리는지가 최우선 확인 사항이다. 그 다음으로, 상태 기반 줄 추적
(`lastLineEndCharIndex`) 방식이 실제로 매 레이아웃 패스마다 글리프 인덱스
오름차순 호출을 보장받는지(문서화된 공식 보장은 아니고 관찰된 동작에
기반한 가정이다) — 스크롤/리사이즈/다른 절로 전환처럼 레이아웃이 여러
번 다시 도는 상황에서 줄간격이 이상해지는 사례가 있으면 이 가정부터
의심해야 한다.

## [2026-08-11, 이어서 37] 줄간격 "클린빌드 해도 그대로" 버그의 진짜 원인 + 형광펜 오버레이 방식 전환 + 메모 클라우드 동기화 확인

### 배경 — 사용자 재보고

"이어서 36"(크래시 수정) 이후, 사용자가 크래시 이전과 완전히 똑같은
스크린샷과 함께 세 가지 문제를 다시 보고했다: (1) 줄간격이 여전히 2.3
고정, (2) "나무 진을" 메모 박스가 텍스트에서 너무 멀다, (3) "아이를"
형광펜이 화면 끝까지 칠해짐. AI가 처음엔 "클린 빌드를 해봤는지"를
물었는데, 사용자가 단호하게 반박했다: "클린빌드 후에도 증상 동일함.
몇번을 클린 빌드 해도 동일함." — 이 반박이 맞았다. 실제 원인은 빌드
캐시가 아니라 순수한 로직 버그였다.

### 원인 1 — 줄간격이 안 바뀐 이유: `attributedText`가 재대입되지 않음

`SelectableVerseTextView.updateUIView`/`updateNSView`는 이렇게 되어
있었다:

```swift
if !uiView.attributedText.isEqual(to: attributedText) {
    uiView.attributedText = attributedText
}
```

"이어서 35"에서 줄간격 계산을 전부 `NSLayoutManagerDelegate.
lineSpacingAfterGlyphAt(...)`로 옮기면서, `attributedText`(NSAttributedString)
자체는 더 이상 줄간격 정보를 담지 않게 됐다 — 줄간격은 이제 오직
`noteLineSpacingHints`(그때그때 계산되는 배열, `Coordinator`가 매
`updateUIView` 호출마다 델리게이트에서 읽는 값)에만 있다. 그 결과 메모가
새로 생기든 말든 `attributedText`의 실제 바이트 내용은 그대로다 —
`isEqual(to:)`가 계속 `true`를 반환해 위 `if` 블록이 매번 건너뛰어지고,
`.attributedText`를 다시 대입하지 않으니 TextKit은 레이아웃을 다시 할
이유가 없다고 판단해 `NSLayoutManagerDelegate`를 다시 부르지 않는다 — 즉
갱신된 `noteLineSpacingHints`가 있어도 그걸 전달할 통로 자체가 막혀
있었다. 몇 번을 다시 빌드해도 이 코드 경로가 실행될 일이 없었으니 사용자의
"클린빌드 해도 동일함" 보고는 완전히 정확했던 것이다.

수정: `attributedText`가 바뀌었는지와 무관하게, 매 `updateUIView`/
`updateNSView` 호출마다 무조건 `layoutManager.invalidateLayout(forCharacterRange:
actualCharacterRange:)`를 호출해 TextKit이 레이아웃을 다시 하고 델리게이트를
최신 힌트로 다시 부르도록 강제했다.

### 원인 2 — 형광펜이 화면 끝까지 칠해지는 문제: `fillBackgroundRectArray` 오버라이드 포기

"이어서 35"에서 시도한 `TightHighlightLayoutManager.fillBackgroundRectArray`
오버라이드(Apple이 주는 `rectArray`를 무시하고 줄 단위로 타이트한 사각형을
직접 계산)가 실기기에서도 여전히 고쳐지지 않았다는 게 사용자의 두 번째
스크린샷으로 재확인됐다. TextKit1의 멀티라인 배경 채우기 내부 동작
(비공개 API 영역)을 기기 디버깅 없이 계속 추측으로 고치는 대신, 이미
효과가 검증된 "메모" 점선 박스와 완전히 같은 전략으로 바꿨다:

- TextKit의 `.backgroundColor` 어트리뷰트/배경칠 메커니즘 자체를
  `.highlight`(형광펜) 스타일에는 더 이상 쓰지 않는다
  (`VerseAnnotationRenderer.nsAttributedContent`에서 `.highlight` case는
  이제 아무 어트리뷰트도 추가하지 않는다 — `.mark`(표시/밑줄)는 이 문제가
  없어 `.underlineStyle`/`.underlineColor`를 그대로 쓴다).
- 대신 `SelectableVerseTextView.Coordinator.updateHighlightOverlays(in:)`
  (신설, iOS/macOS 양쪽)가 각 형광펜의 실제 글리프 좌표를
  `enumerateLineFragments` + `boundingRect(forGlyphRange:in:)`로 줄 단위로
  계산해 새 `HighlightOverlayRect`(`id`, `highlight`, 텍스트 컨테이너
  좌표계 `rect`) 배열로 돌려준다 — 하이라이트 하나가 여러 줄에 걸치면
  줄마다 하나씩 만든다.
- `VerseZoomView`는 이 배열을 `@State private var highlightOverlays`로
  받아 `SelectableVerseTextView(...)`에 `.background(alignment: .topLeading)`
  로 `Rectangle()`을 겹쳐 그린다 — `.mark` 취소/`.highlight` 취소를 우클릭
  메뉴로 하는 기존 로직(`hitHighlight`)은 여전히 어노테이션 배열
  (`highlights`)을 그대로 참조하므로 영향 없다.
- 배치 순서: `.background`(형광펜, 텍스트 뒤) → `.overlay`(메모 점선
  박스, 텍스트 앞) → `.padding()` — 형광펜이 텍스트를 가리지 않고, 메모
  박스는 기존처럼 맨 위에 보인다.

### 원인 3 — "나무 진을" 메모 박스가 멀어 보이는 문제

이건 원인 1(줄간격 미반영)의 직접적인 파생 증상이었다 — `noteLineSpacingHints`가
델리게이트에 전달된 적이 없었으니 애초에 그 줄에 여분 공간 자체가
생기지 않았고, 그런데도 메모 박스는 (여백이 없는) 다음 줄 위치를 기준으로
그려졌으니 시각적으로 "붕 떠서 멀어 보이는" 상태가 된 것이다. 원인 1을
고치면(줄간격이 실제로 벌어지면) 이 문제도 별도 코드 수정 없이 함께
해결될 것으로 예상한다 — 박스 앵커 좌표 계산(`updateNoteOverlays`) 자체는
이전 라운드에서 이미 올바르게 짜여 있었다.

### 신규 요청 확인 — "메모도 클라우드 동기화가 될 수 있어야 함"

`BibleResearchPlatform/Sources/BibleResearchModels/Models/VerseAnnotations.swift`의
`VersePhraseNote` `@Model`을 직접 확인한 결과, 이미 CloudKit 호환 조건을
전부 만족하고 있었다: 모든 저장 프로퍼티가 기본값을 가지고
(`id`/`translationCode = ""`/`bookId = 1`/.../`updatedAt = Date.now`),
`@Attribute(.unique)`는 하나도 없다 — `VerseHighlight`가 이미 문제없이
동기화되는 것과 정확히 같은 패턴이다. `BibleResearchSchema.swift`에서도
`VersePhraseNote.self`가 `modelTypes` 배열에 이미 등록되어 있고
(주석: `// 구간 주석 — 특정 표현 부연설명 "메모"(VerseAnnotations.swift) — 2026-08-11 신설`),
`makeSharedModelContainer`가 그 스키마 전체에 대해
`cloudKitDatabase: .private(cloudKitContainerIdentifier)`를 이미 설정해
두고 있었다. **결론: 코드 수정이 필요 없다 — 메모는 이미 형광펜/표시와
동일한 통로로 CloudKit에 동기화되도록 배선되어 있다.**

### 정적 검증

`SelectableVerseTextView.swift` 217/217·128/128·40/40,
`VerseAnnotationRenderer.swift` 55/55·45/45·18/18,
`VerseZoomView.swift` 178/178·108/108·21/21,
`PhraseNoteEditorPopover.swift`(이번 라운드 미수정, 참고용 재확인)
67/67·14/14·1/1. 이상 없음.

⚠️ Xcode 확인 필요(이번 라운드분): (1) 메모가 있는 줄의 간격이 이제
실제로 최대 120px까지 벌어지는지, 메모가 없는 줄은 여전히 기본 2.3배를
유지하는지. (2) 형광펜이 이제 정확히 그 표현의 글자 폭만큼만 칠해지고
화면 끝까지 번지지 않는지 — 특히 하나의 형광펜이 강제 줄바꿈(23자
단위)으로 여러 줄에 걸쳐 있을 때 줄마다 올바르게 끊겨 칠해지는지. (3)
"나무 진을" 메모 박스가 이제 실제로 그 표현 바로 아래(벌어진 줄간격
안)에 붙어 보이는지. (4) 메모를 새로 만든 뒤 CloudKit 동기화가 켜진
다른 기기에서 그 메모가 실제로 나타나는지(코드상으로는 이미 배선되어
있다고 판단했지만 실기기 확인은 아직 없음).

## [2026-08-11, 이어서 38] "이어서 37" 재검증 실패 재보고 — 4가지 문제 재수정 + 메모 다중 스택/화살표 신기능

### 배경

"이어서 37" 수정을 실기기에서 재확인한 사용자가 다시 문제를 보고했다:
(1) 줄간격 여전히 해결 안 됨, (2) 메모-텍스트 간격 여전히 해결 안 됨, (3)
기존 형광펜 위치가 이상해짐(새 오버레이 방식으로 바뀌면서 생긴 새 증상),
(4) 줄바꿈을 넘어 칠한 형광펜이 확대보기에서 아예 표시 안 됨(마찬가지로
새 증상). 여기에 신규 요청 — "메모가 한 줄에 두 개 이상 있을 때 겹치지
않도록, 세로로 쌓고 화살표로 원래 표현과 연결."

### 원인 재분석 4 — 줄바꿈 넘는 형광펜이 아예 안 보이는 이유 (신규 진단)

`VerseAnnotationRenderer.resolvedRange(start:end:anchorText:in:)`(자가
치유 앵커링)를 다시 읽어 보니, 정확히 이 버그를 설명하는 로직이 있었다:

```swift
let candidate = NSRange(location: start, length: max(0, end - start))
if ..., full.substring(with: candidate) == anchorText { return candidate }
guard !anchorText.isEmpty else { return nil }
let found = full.range(of: anchorText)
return found.location == NSNotFound ? nil : found
```

`anchorText`는 주석을 만든 시점에 저장해 둔 "원래 절 텍스트" 스냅샷이라
평범한 공백(U+0020)을 그대로 갖고 있다. 그런데 확대보기의 23자 강제
줄바꿈은 `full`(렌더링용 사본) 안의 특정 공백을 줄 구분자(U+2028)로
치환한다 — 그 치환 지점이 하필 어떤 형광펜의 범위 "내부"(두 단어를 잇는
공백이 줄바꿈 지점으로 골라진 경우)에 있으면, 위 두 시도(정확 오프셋
일치, 리터럴 검색) 둘 다 문자가 달라져 실패한다 — `anchorText`엔
U+0020이 있는데 `full`엔 U+2028이 있으니 절대 같아질 수 없다. 결국
`nil`을 돌려주고, 호출부(`updateHighlightOverlays` 등)는 그 형광펜을
조용히 건너뛴다 — "표현 안 됨" 증상과 정확히 일치한다.

수정: 앞 두 시도가 모두 실패하면, `full`에서 U+2028을 다시 공백으로
되돌린 정규화 사본을 만들어 그 안에서 `anchorText`를 한 번 더 찾는다.
치환이 항상 "공백 자리에만, 길이 보존"으로 이뤄진다는 보장이 있으므로
(하드랩 알고리즘 자체의 설계 불변식), 정규화 사본에서 찾은 위치(문자
인덱스)를 원본 `full`에 그대로 재사용해도 어긋나지 않는다.

### 원인 재분석 3 — 형광펜 위치가 이상해진 이유: `boundingRect`가 의심됨

"이어서 37"의 `updateHighlightOverlays`는 `enumerateLineFragments` +
`boundingRect(forGlyphRange:in:)`로 줄 단위 타이트 사각형을 계산했는데,
이건 사실 "이어서 35"에서 `fillBackgroundRectArray` 오버라이드에 썼던
것과 **완전히 같은 계산식**이었다 — 그리고 그 오버라이드는 사용자가
이미 두 차례에 걸쳐 "실기기에서 안 고쳐진다"고 확인해 준 것이었다. 즉
문제는 `fillBackgroundRectArray`라는 특정 API가 아니라
`boundingRect(forGlyphRange:in:)` 자체가 "줄의 끝(특히 줄바꿈 직전
공백/구분자 글리프)에 걸치는 범위를 받으면 그 줄의 나머지 폭까지 늘어난
사각형을 돌려준다"는 결함을 갖고 있을 가능성이 높다는 뜻이다(TextKit1의
멀티라인 텍스트 선택이 중간 줄은 "블록"처럼 줄 끝까지 넓게 칠하는 것과
같은 내부 동작을 공유하는 것으로 추정된다 — 비공개 구현이라 100%
확정은 어렵다).

수정: 이번엔 `boundingRect(forGlyphRange:in:)`를 가로(X·폭) 계산에는
아예 쓰지 않는다.
- 시작 x는 `layoutManager.location(forGlyphAt:)`(순수 점 좌표 — "늘어난
  사각형"을 만들어낼 개념 자체가 없다)로 구한다.
- 폭은 TextKit 지오메트리를 전혀 거치지 않고, 그 줄 구간의 실제 문자열을
  같은 폰트로 직접 측정(`NSString.size(withAttributes:)`)해 얻는다.
- 세로(Y)는 이 결함이 가로 폭에서만 관찰됐고(메모 박스 앵커도 같은
  `boundingRect`의 Y를 계속 써 왔는데 "위치가 이상하다"는 지적은 없었다)
  그대로 `boundingRect`의 Y만 재사용한다.

`SelectableVerseTextView.Coordinator.tightLineRects(...)`(신설, iOS·macOS
양쪽 동일 로직)로 이 계산을 옮겼다.

### 원인 재분석 1/2 — 줄간격이 "이어서 37" 수정 이후에도 안 바뀐 이유

`invalidateLayout(forCharacterRange:actualCharacterRange:)`를
`NSLayoutManager`에 직접 호출하는 방식이 여전히 효과가 없었다. TextKit1
문서를 다시 확인한 결과, 이 메서드는 "보통 직접 호출할 필요가 없다"고
명시되어 있다 — 정식 통로는 `NSTextStorage` 쪽에서 변경을 알리는
`edited(_:range:changeInLength:)`다(`NSMutableAttributedString`의 편집
메서드들이 내부적으로 자동 호출해 주는 바로 그 메서드) — 이게 첨부된
"모든" `NSLayoutManager`에 글리프/레이아웃 무효화를 정식 절차대로
전파한다. `NSLayoutManager.invalidateLayout(...)`을 우리가 직접 부르는
건 이 정식 통지 경로를 건너뛰고 레이아웃 매니저 내부의 일부 캐시만
건드리는 것이라, TextKit 내부의 다른 상태(예: "이 텍스트 스토리지가
편집 중/무효 범위가 있다"는 자체 플래그)와 어긋나 조용히 무시됐을
가능성이 있다.

수정: `updateUIView`/`updateNSView`에서 직접 `layoutManager.
invalidateLayout(...)`를 부르는 대신, `textStorage.beginEditing()` →
`textStorage.edited(.editedAttributes, range: 전체범위, changeInLength: 0)`
→ `textStorage.endEditing()`으로 바꿨다 — 실제 내용은 안 바뀌었어도(변경
길이 0) "속성이 바뀌었다"고 정식으로 통지해, 첨부된 레이아웃 매니저가
그 범위의 레이아웃을 다시 하도록 강제한다.

⚠️ [정직한 고지] 이 줄간격 버그는 이번이 세 번째 수정 시도다. 앞선 두
번(② `NSParagraphStyle` 문자범위별 적용 → ③ `NSLayoutManagerDelegate` +
`invalidateLayout`)이 이론적으로는 그럴듯했지만 실기기에서 확인되지
않았다. 이번 `NSTextStorage.edited(...)` 방식이 TextKit1의 공식 문서가
명시하는 정식 통로라 이전 시도보다 근거는 더 확실하지만, 그래도 만약
이번에도 안 바뀐다면 추측만으로 네 번째 시도를 하기보다 — Xcode에서
`SelectableVerseTextView.Coordinator.layoutManager(_:
lineSpacingAfterGlyphAt:...)`에 중단점을 걸어 실제로 몇 번 호출되는지,
`parent.noteLineSpacingHints`가 그 시점에 정말 비어있지 않은지를 직접
확인해 알려주시면 훨씬 더 정확하게 원인을 좁힐 수 있다.

### 신규 기능 — 한 줄에 메모 2개 이상: 세로 스택 + 화살표 연결

`VerseZoomView`에 `StackedNoteBox`(신설)와 `NoteConnectorArrow`(신설,
단순 직선+화살촉 `Shape`)를 추가했다.

- `stackedNoteBoxes`: `noteOverlays`를 같은 물리적 줄(`lineCharacterRange`
  가 정확히 같음)끼리 묶고, 그룹 안에서 표현의 왼쪽→오른쪽 순서로 정렬한
  뒤, 첫 번째 메모만 종전처럼 자기 표현 바로 아래(`anchorBottomLeft`)에
  두고, 두 번째부터는 옆이 아니라 "바로 앞 박스 아래"(세로 스택, 8pt
  간격)에 둔다.
- 박스 위치(`boxOrigin`)가 자기 표현 위치(`overlay.anchorBottomLeft`)와
  다른(= 쌓여서 밀려난) 박스에는 `NoteConnectorArrow`로 그 표현
  위치까지 화살표를 그어 준다 — 화살표를 박스보다 먼저 그려 박스가
  화살표 끝을 덮게 했다.
- `PhraseNoteBoxView`에 `showConnector: Bool = true` 파라미터를
  추가했다 — 자기 표현 바로 아래 있는(스택의 첫 번째) 박스만 기존의
  짧은 내장 연결선(4pt)을 보여주고, 화살표로 이미 연결을 표시하는
  밀려난 박스는 이 내장 연결선을 꺼서 중복을 피한다.
- `noteLineSpacingHints`도 함께 고쳤다 — 예전엔 한 줄에 메모가 여럿이면
  "가장 큰 값"(옆으로 나란히 놓인다는 가정) 하나만 썼는데, 이제 세로로
  쌓으므로 그 줄에 실제로 필요한 여유 공간은 쌓인 박스 높이의 "합"이다
  — 메모 하나짜리 줄에만 기존 120px 캡을 적용하고, 여럿이 쌓인 줄은
  합계 그대로 쓴다(개별 박스 높이 자체가 `estimatedContentHeight`로
  24~100px로 이미 클램프돼 있어 극단적으로 커질 걱정은 없다).

### 정적 검증

`SelectableVerseTextView.swift` 239/239·134/134·48/48,
`VerseAnnotationRenderer.swift` 58/58·48/48·18/18,
`VerseZoomView.swift` 211/211·125/125·30/30,
`PhraseNoteEditorPopover.swift` 67/67·15/15·1/1. 이상 없음.

⚠️ Xcode 확인 필요(이번 라운드분, 우선순위 순): (1) 줄간격이 이제
실제로 바뀌는지 — 안 바뀐다면 위에 적어 둔 대로 델리게이트 호출 여부를
직접 중단점으로 확인해 알려주시면 좋겠다. (2) 형광펜이 이제 정확한
폭으로만(줄 끝까지 안 늘어나고) 칠해지는지, 특히 여러 줄에 걸친
형광펜이 이제는 아예 안 보이던 것에서 벗어나 줄마다 올바르게 나뉘어
보이는지. (3) 한 줄에 메모가 2개 이상일 때 세로로 쌓이고 화살표가 각자
표현을 정확히 가리키는지, 화살표가 너무 길어지는 극단적인 경우(예: 표현이
줄 맨 앞인데 메모가 줄 훨씬 아래로 밀린 경우)의 시각적 느낌.

## [2026-08-11, 이어서 39] 근본 원인 확정 — `boundingRect(forGlyphRange:in:)`는 "타이트 박스"가 아니었다

### 줄간격 수정이 드러낸 진짜 버그

"이어서 38"의 `NSTextStorage.edited(...)` 통지 수정은 **성공했다** —
사용자 스크린샷에서 2번째 줄과 3번째 줄 사이가 실제로 크게 벌어진 것이
확인된다(그 전까지 세 라운드 동안 전혀 움직이지 않던 값이다). 그런데
줄간격이 커지는 순간, 지금까지 숨어 있던 좌표 버그가 한꺼번에 드러났다:
메모 점선 박스가 화면 맨 아래(관주 바 근처)까지 밀려나고, 형광펜도 텍스트와
어긋난 위치에 그려졌다.

원인은 하나였다 — **`boundingRect(forGlyphRange:in:)`를 "순수 글리프
타이트 박스"라고 믿고 써 온 가정 자체가 틀렸다.** 이 API는 실제로는 그
글리프 범위가 걸친 **줄 조각(line fragment) 사각형들의 합집합**을
돌려준다. 줄 조각 사각형에는 우리가 방금 크게 키운 줄간격이 통째로
포함되므로, `boundingRect.maxY`(메모 박스 앵커)는 "글자 아랫변"이 아니라
"벌어진 줄간격까지 다 지난 맨 아래"를 가리킨다 — 줄간격이 작았던 지난
라운드들에서는 오차가 몇 px라 눈에 띄지 않아 이 잘못된 가정이 여러 번
살아남았고, 줄간격이 실제로 커지자마자 "메모가 텍스트에서 멀다"와
"형광펜 위치가 이상하다"로 동시에 터진 것이다. 앞선 라운드들에서 이 두
증상을 서로 다른 원인으로 보고 따로 고치려 했던 게 계속 실패한 이유이기도
하다 — 사실은 하나의 원인이었다.

### 수정 — 베이스라인 + 폰트 메트릭 기준으로 전면 교체

`SelectableVerseTextView.Coordinator.tightLineRects(...)`(iOS·macOS 동일)를
다시 짰다. 좌표 정의가 문서상 명확한 값만 쓴다:

- **세로**: `enumerateLineFragments`의 `lineRect.minY` +
  `location(forGlyphAt:).y`(그 줄 조각 원점 기준 **베이스라인** 오프셋,
  Apple 문서가 명시하는 정의) = 이 줄 글자들의 베이스라인 y. 거기서
  `font.ascender`만큼 올리면 글자 윗변, 높이는 `ascender - descender`다.
  줄간격은 글자 "바깥"에 붙는 여백이라 베이스라인을 옮기지 않으므로,
  줄간격이 얼마든 이 값은 흔들리지 않는다.
- **가로**: Apple이 바로 이 용도로 문서화해 둔
  `enumerateEnclosingRects(forGlyphRange:withinSelectedGlyphRange:in:)`를
  쓰되 `withinSelectedGlyphRange`에 `NSNotFound`를 넘긴다 — 이 인자에
  실제 선택 범위를 넘기면 "선택 영역 스타일"(중간 줄이 줄 끝까지 늘어나는
  블록)이 나오고, `NSNotFound`를 넘기면 글리프를 딱 감싸는 사각형이
  나온다. 이 구분이 그동안 형광펜이 화면 끝까지 번지던 현상의 정체로
  보인다. 그래도 만일을 대비해 실제 문자열을 같은 폰트로 측정한 폭으로
  상한을 씌워(clamp) 번짐을 이중으로 차단했다.

메모 박스 앵커(`updateNoteOverlays`)도 형광펜과 **같은 이 함수**를 쓰도록
통일했다 — 두 기능이 같은 좌표 계산을 공유하므로 앞으로 한쪽만 어긋나는
일이 생기지 않는다.

### 화살표 위치 보정

사용자 요청("메모위치에 따른 화살표 위치를 보정")에 따라 화살표 방향과
끝점을 바꿨다. 예전엔 표현 → 박스 방향으로 그어 화살촉이 박스를
가리켰는데, "이 박스가 **어느 표현**을 설명하는가"가 핵심이므로 방향을
뒤집었다 — 박스 왼쪽 위에서 출발해 **그 표현의 아래 한가운데**를
화살촉이 가리킨다. 표현 한가운데 좌표를 구하려고
`PhraseNoteOverlayRect`에 `anchorWidth`(그 표현의 실제 가로 폭)를
추가했다.

### 정적 검증

`SelectableVerseTextView.swift` 253/253·142/142·48/48,
`VerseAnnotationRenderer.swift` 58/58·48/48·18/18,
`VerseZoomView.swift` 212/212·125/125·30/30,
`PhraseNoteEditorPopover.swift` 67/67·15/15·1/1. 이상 없음.
`PhraseNoteOverlayRect(` 생성자 호출부 2곳(iOS·macOS)이 모두 새
`anchorWidth` 인자를 넘기는지, `tightLineRects` 호출부 4곳이 모두 새
시그니처(`tightHeight` 인자 제거)를 쓰는지 grep으로 전수 확인했다.

⚠️ Xcode 확인 필요(이번 라운드분): (1) 메모 점선 박스가 이제 벌어진
줄간격 "안"에, 그 표현 바로 아래에 붙어 보이는지. (2) 형광펜이 텍스트와
정확히 겹치는지(가로 위치·폭·세로 위치 모두). (3) 한 줄에 메모가 여럿일
때 세로로 쌓인 박스에서 각 표현으로 화살표가 정확히 꽂히는지. (4)
`enumerateEnclosingRects`의 `NSNotFound` 동작이 기대대로인지 — 만약
형광펜 폭이 여전히 이상하면 실측 폭 clamp가 작동하고 있으므로 최소한
"화면 끝까지 번짐"은 없어야 한다(그 경우 남는 문제는 시작 x 위치뿐이라
원인 범위가 훨씬 좁아진다).

## [2026-08-11, 이어서 40] 확대보기 전면 재설계 — TextKit 표시 레이어 폐기, 순수 SwiftUI로 전환

### 배경 — 사용자가 제공한 설계 문서

사용자가 "SwiftUI 성경 본문 주석 UI 명세" 문서를 첨부하고, 코딩 전에
설계 검토부터 요청했다. 문서를 검토한 결과 — 지난 "이어서 34~39" 여섯
라운드 동안 반복된 버그들(줄간격 미반영, 메모 박스 거리 오차, 형광펜
위치 오차, 줄바꿈 넘는 형광펜 미표시)의 진단과 문서의 지적이 정확히
겹쳤다: 메모 박스 높이를 `NSString.boundingRect`로 추측하고, 그 추측치를
TextKit 줄간격에 강제로 주입하고, 형광펜/메모 좌표를 TextKit 글리프
좌표와 SwiftUI 좌표 사이에서 손으로 맞춰 온 것 — 전부 "SwiftUI가 원래
잘하는 일(텍스트 높이 자동 계산, 좌표 시스템 일관성)을 TextKit으로
재발명"한 것이었다.

다만 문서에는 사각지대가 하나 있었다 — `Annotation`이 이미
`startIndex`/`endIndex`를 가진 상태로 시작하고, 그 값을 "어떻게
만드는지"(사용자가 드래그로 정확한 문자 범위를 고르는 것)는 다루지
않는다. SwiftUI `Text(...).textSelection(.enabled)`는 그 정확한 범위를
코드로 읽어올 API가 없다(`SelectableVerseTextView.swift` 최초 도입
사유, "이어서 8" 참고) — 그래서 표시(display)와 선택(select)을
분리하기로 사용자와 합의했다: 평소엔 순수 SwiftUI로 보여주고, 새 주석을
만들려고 드래그할 때만 `UITextView`/`NSTextView` 기반의 최소 컴포넌트가
잠깐 뜬다.

### 구조

**`VerseAnnotationRenderer.swift`(확장)** — 절 텍스트를 시각적 "줄"
단위로 나누는 순수 함수들을 추가했다.
- `koreanLineRanges(for:targetCharsPerLine:)`: 기존에 검증된 23자
  최근접 띄어쓰기 알고리즘(`lineBreakPositions`)을 "지점 목록"이 아니라
  "줄 범위 목록"으로 바꿔 재사용한다.
- `measuredLineRanges(for:font:containerWidth:)`: 라틴/혼합 절(영문
  성경 등) 전용 — 화면에 올리지 않는 임시 `NSLayoutManager`로 실제 폭
  기준 줄바꿈 지점을 측정한다. 예전엔 "한글 전각 폭 추정 × 21자"라는
  근사치를 썼는데, 실제 TextKit 타이프세팅 결과를 그대로 읽어오는 이
  방식이 더 정확하다 — 그러면서도 아무것도 화면에 그리지 않으므로(이
  세션 내내 문제였던 "TextKit 표시 좌표"와 무관), 델리게이트 재진입이나
  좌표 브리징 문제가 원천적으로 생길 수 없다.
- `lineRanges(for:font:containerWidth:)`: 위 둘을 `containsLatinOrDigit`
  기준으로 분기하는 공용 진입점.
- `VerseTextSegment`/`VerseLine`/`buildLines(...)`: 절 텍스트 + 형광펜/
  메모를 표시 레이어가 바로 그릴 수 있는 구조로 조립한다. 기존
  `attributedContent`가 절 전체에 대해 하던 "경계점 분해"(겹치는 여러
  구간을 겹치지 않는 최소 조각으로 나누는 방식)를, 줄 범위로 미리 자른
  부분 문자열에 대해 반복한다.
- `nsAttributedContent(...)`(옛 확대보기 전용 렌더링 함수)는 삭제했다 —
  쓰는 곳이 없어졌고, 이미 사라진 타입(`HighlightOverlayRect` 등)을
  언급하는 주석만 남아 헷갈릴 수 있었다.

**`AnnotatedVerseFlowView.swift`(신설)** — 표시 모드 전용 뷰.
`VerseLine` 배열을 `VStack`으로, 각 줄을 `Text` 세그먼트의 `HStack`으로
그린다. 메모가 있는 줄은 바로 아래에 `PhraseNoteBoxView`를 실제
서브뷰로 끼워 넣는다 — SwiftUI `VStack`이 원래 하는 "다음 콘텐츠를
밀어낸다"를 그대로 쓰므로, 메모 박스 높이를 미리 추측해 TextKit
줄간격에 몰래 주입하는 코드가 전혀 필요 없어졌다. 메모 박스와 그 표현을
잇는 화살표는 `anchorPreference`/`overlayPreferenceValue`로 그린다 — 두
좌표(표현 세그먼트의 프레임, 박스의 프레임) 모두 SwiftUI 자신이
레이아웃한 결과를 그대로 읽는 것이라, 좌표 브리징 자체가 없다. 형광펜
취소·메모 수정/삭제는 각 세그먼트/박스에 붙인 SwiftUI 표준
`.contextMenu`(iOS는 길게 눌러서, macOS는 우클릭으로 — 플랫폼 분기 코드
없이 SwiftUI가 알아서 처리)로 옮겼다.

**`SelectableVerseTextView.swift`(대폭 축소)** — 선택 모드 전용으로
줄었다. `TightHighlightLayoutManager`(형광펜 배경 재계산),
`PhraseNoteOverlayRect`/`HighlightOverlayRect`(오버레이 좌표 계산),
`NSLayoutManagerDelegate`(줄간격 주입), 하드랩 U+2028 치환, 우클릭
UIMenu/NSMenu 구성까지 전부 제거했다 — 이 뷰는 이제 서식 없는 평범한
텍스트를 그리고 `selectedRange`를 정확히 읽어 오는 것 하나에만
집중한다. 재귀 위험이 있던 델리게이트도, 손으로 맞추던 좌표도 전혀
없다.

**`PhraseNoteBoxView`(`PhraseNoteEditorPopover.swift`)** — `PhraseNoteOverlayRect`
(TextKit이 계산해 준 좌표 + 높이 추정치) 대신 `VersePhraseNote` 원본을
직접 받는다. 높이는 SwiftUI 자신의 텍스트 레이아웃이 계산하게 두어(설계
문서의 "메모 내용에 따라 세로 높이만 자동으로 증가한다"를 그대로
따름), 예전의 `estimatedContentHeight`(NSString.boundingRect 근사치) +
`maxHeight: 100` + `clipped()`(실제 높이를 강제로 잘라내던 것)를 모두
없앴다.

**`VerseZoomView.swift`(배선 변경)** — `isSelecting` 상태로 표시/선택
모드를 전환한다. 형광펜/표시/메모 버튼은 선택이 없으면 "선택 모드로
들어가라"는 뜻으로 바뀌고(예전엔 비활성화), 선택 모드에서 다시 누르면
실제로 적용되며 자동으로 표시 모드로 돌아간다. "개인 주석"/관주(절
전체)는 선택과 무관하게 그대로 동작한다. 표시 영역의 실제 폭은
`onGeometryChange`(iOS 17+/macOS 14+ — 이 프로젝트는 이미 `@Observable`
매크로를 쓰고 있어 이 최소 버전이 이미 보장된다)로 관찰한다 —
`GeometryReader`로 콘텐츠를 직접 감싸면 그 콘텐츠의 높이까지 화면
전체로 강제로 늘어나 버리는 흔한 함정이 있어, "내 크기를 옆에서
관찰만" 하는 이 최신 API로 피했다.

### ⚠️ 알려진 트레이드오프 (사용자에게 확인 필요)

- **드래그 UX가 한 단계 늘었다.** 예전엔 화면 전체가 항상 드래그
  가능했다 — 이제 형광펜/표시/메모 버튼을 한 번 눌러 "선택 모드"로
  들어간 뒤 드래그해야 한다. 안정성을 위한 트레이드오프로 판단해
  진행했지만, 사용성 문제로 느껴지면 조정 가능하다(예: 텍스트를 길게
  누르면 자동으로 선택 모드로 들어가게 하는 등).
- **메모 박스의 가로(X) 위치는 근사치다.** `approximateLeadingOffset`가
  TextKit 없이 순수 문자열 폭 측정으로 계산한다 — 몇 pt 어긋날 수
  있지만, 화살표(`NoteConnectorArrow`)가 실제 SwiftUI 프레임 기준으로
  정확한 위치를 가리켜 주므로 "위치를 몰라 헷갈리는" 문제로는 이어지지
  않는다.
- **메모 박스 최대 높이 100px 캡을 없앴다.** 설계 문서의 "내용에 따라
  자동으로 증가"를 따르기 위한 의도적 변경이다 — 이전 요청("최대
  300x100")과 다르다는 점을 밝혀 둔다. 필요하면 다시 캡을 씌울 수
  있다.

### 정적 검증

`VerseAnnotationRenderer.swift` 97/97·70/70·38/38,
`SelectableVerseTextView.swift` 35/35·28/28·4/4(대폭 축소됨 — 이전
253/142/48에서),
`AnnotatedVerseFlowView.swift`(신설) 90/90·48/48·21/21,
`PhraseNoteEditorPopover.swift` 59/59·13/13·1/1,
`VerseZoomView.swift` 156/156·109/109·12/12,
`BibleReadingView.swift`(호출부, 시그니처 무변경 확인용 재검증)
144/144·111/111·0/0. 이상 없음. `PhraseNoteOverlayRect`/
`HighlightOverlayRect`/`TightHighlightLayoutManager`/`noteOverlays`/
`highlightOverlays`/`noteLineSpacingHints`/`nsAttributedContent(` 등
삭제된 타입·함수를 실제 코드(주석 제외)에서 참조하는 곳이 남아 있지
않은지 전체 grep으로 확인했다.

⚠️ Xcode 확인 필요(이번 라운드분, 사실상 전면 재작성이라 우선순위
높음): (1) 표시 모드에서 형광펜/표시/메모/줄바꿈이 모두 올바르게
보이는지(특히 이번엔 좌표 브리징이 아예 없어 이전 라운드들의 버그
카테고리 자체가 재발할 가능성은 낮다고 판단하지만 최초 검증은 반드시
필요하다). (2) 선택 모드 진입("선택 모드로 들어가라" 버튼 탭) → 드래그
→ 형광펜/표시/메모 적용 → 자동으로 표시 모드 복귀까지 전체 흐름. (3)
한 줄에 메모 2개 이상일 때 스택 + 화살표. (4) `.contextMenu`로 기존
형광펜 취소, 메모 수정/삭제가 iOS(길게 누르기)·macOS(우클릭) 양쪽에서
잘 뜨는지. (5) 관주("절 전체"로, 그리고 선택 후 특정 표현으로) 둘 다
여전히 정상 동작하는지 — 관련 코드는 손대지 않았지만 액션바 버튼 배선이
바뀌어 회귀 확인이 필요하다.

## [2026-08-11, 이어서 41] 메모 중복 방지 + 편집 정보 꼬임 수정 + 표시/선택 모드 아이콘 토글

### 배경

"이어서 40"의 표시/선택 모드 분리 이후 사용자가 실제 사용해 보고 세
가지를 보고했다:

1. **같은 표현에 메모를 2개 이상 등록하면, 메모 내용 자체는 맞게
   보이지만 "수정"을 눌렀을 때 관련 텍스트/메모 정보가 엉뚱하게 나옴.**
2. 그 근본 대책으로 — **같은 표현에 메모를 2개 이상 등록하지 못하게
   막고, 이미 메모가 있는 표현에 다시 메모를 걸려고 하면 새로 만들지
   말고 기존 메모를 불러와 수정하게 처리.**
3. **표시/선택 모드 전환을 예전처럼 눈동자/펜 아이콘으로.** 표시
   모드에서는 "닫기" 옆에 펜 아이콘(누르면 편집=선택 모드 진입), 선택
   모드에서는 눈동자 아이콘(누르면 표시 모드로 복귀) — 그리고 액션바
   (형광펜·표시·개인 주석·메모·관주)는 표시 모드에서 비활성화/숨김,
   선택 모드에서 활성화/노출.

### 원인 분석

1번 버그의 실제 원인은 두 가지가 겹쳐 있었다.

- `AnnotatedVerseFlowView`의 `.contextMenu`가 한 세그먼트에 메모가
  여럿이면 `ForEach(notesHere)`로 "메모 수정"/"메모 삭제" 버튼을 그
  개수만큼 **완전히 같은 이름으로** 나열했다 — 사용자 입장에서는 어느
  버튼이 어느 메모인지 구별할 방법이 없었다(메뉴 라벨링 문제).
- `PhraseNoteEditorPopover`의 `@State private var noteText`는 커스텀
  `init`에서 `_noteText = State(initialValue: initialNoteText)`로 한
  번만 채워진다 — SwiftUI에서 `@State`는 뷰의 "정체성(identity)"이
  유지되는 한 재초기화되지 않으므로, `editingPhraseNote`가 다른 메모로
  바뀌어도 팝오버가 이전과 같은 정체성으로 재사용되면 이전 메모의
  텍스트가 그대로 남아 있을 수 있었다. 이게 "수정을 눌렀을 때 정보가
  올바르지 않다"의 직접 원인이다.

이 둘은 근본적으로 "한 표현에 메모가 여럿일 수 있다"는 전제에서
비롯된 문제라, 사용자가 요청한 대로 그 전제 자체를 없애는(중복 등록
방지) 쪽으로 해결했다.

### 변경 내용

**`VerseZoomView.swift`**

- `existingPhraseNote(overlapping:)` 신설 — 대상 범위와 겹치는 기존
  메모를 찾는다. 각 메모의 저장된 `rangeStart`/`rangeEnd`/`anchorText`를
  `VerseAnnotationRenderer.resolvedRange`로 현재 텍스트 기준 범위로
  다시 계산한 뒤(하드랩 등으로 텍스트가 살짝 달라져도 안전하게
  찾도록, 기존 자가치유 로직 재사용) `NSIntersectionRange(...).length
  > 0`으로 겹침을 판정한다.
- "메모" 액션바 버튼: 기존엔 선택이 있으면 무조건
  `editingPhraseNote = nil`(새로 만들기)이었는데,
  `editingPhraseNote = existingPhraseNote(overlapping: selectedRange)`로
  바꿨다 — 겹치는 메모가 있으면 그 메모를 편집 모드로 열고, 없을
  때만(`nil`) 진짜로 새 메모를 만든다. `addPhraseNote` 자체에는 별도
  가드를 걸지 않았다 — 이 액션바 버튼이 메모를 만드는 유일한 진입점이라
  여기서 막는 것으로 충분하다.
- `.popover(isPresented: $isPhraseNoteEditorPresented)` 콘텐츠에
  `.id(editingPhraseNote?.id.uuidString ?? "new")`를 추가했다 — 편집
  대상 메모가 바뀔 때마다(또는 새로 만들기로 전환될 때) SwiftUI가 그
  뷰를 아예 새 정체성으로 취급해 `@State`를 처음부터 다시 초기화하게
  강제한다. `PhraseNoteEditorPopover.swift` 자체는 건드리지 않았다 —
  호출부에서 정체성만 명확히 구분해 주면 충분한 문제였다.
- 툴바: `if isSelecting { Button("선택 취소") {...} }`(선택 모드일
  때만 나타나던 텍스트 버튼)를 상시 아이콘 토글로 교체했다 — 표시
  모드일 땐 `"pencil"`(누르면 `isSelecting = true`), 선택 모드일 땐
  `"eye"`(누르면 `isSelecting = false`), 둘 다 `selectedRange`를
  초기화한다.
- `actionBar` 전체(형광펜 색상 스와치 + 표시 + 개인 주석 + 메모 + 관주,
  5개 모두)에 `.disabled(!isSelecting)` + `.opacity(isSelecting ? 1 :
  0.35)`를 적용했다.

### ⚠️ 확인 필요한 트레이드오프

사용자 요청 원문("형광펜 .. ..메모 관주 아이콘 비활성화/활성화")을
문자 그대로 읽으면 "개인 주석"과 "관주"도 포함된다고 해석했고 그렇게
반영했다. 다만 이 둘은 애초에("메모는 관주처럼 항상 활성화되도록",
"이어서 X" 라운드 참고) **드래그 선택과 무관하게 절 전체에 언제든 걸
수 있어야 한다**는 명시적 요청으로 만들어진 기능이다 — 이번 변경으로
표시 모드에서는 이 둘도 눌러도 반응하지 않게 되어, 예전 요청과 방향이
반대로 바뀌는 셈이다. 의도한 바가 맞는지 확인 부탁드린다 — 아니라면
"개인 주석"/"관주" 두 개만 `isSelecting`과 무관하게 항상 활성화로
되돌리는 건 간단한 되돌리기다.

### 정적 검증

`VerseZoomView.swift` 164/164(paren)·113/113(brace)·12/12(bracket) —
이상 없음(이전 156/109/12에서 이번 라운드 추가분만큼 증가). 이번
라운드에서 다른 파일(`AnnotatedVerseFlowView.swift`,
`PhraseNoteEditorPopover.swift`, `VerseAnnotationRenderer.swift`,
`SelectableVerseTextView.swift`)은 수정하지 않았다.

⚠️ Xcode 확인 필요: (1) 같은 표현에 메모를 만든 뒤 다시 그 표현을
선택해 "메모" 버튼을 누르면 새로 만들지 않고 기존 메모가 편집 모드로
열리는지. (2) 서로 다른 메모를 연달아 "수정"으로 열었을 때 매번 그
메모의 정확한 텍스트가 뜨는지(이전엔 이전 메모 내용이 남아 있는 채로
뜨는 버그였다). (3) 펜/눈동자 아이콘 탭으로 표시↔선택 모드가 정상
전환되는지. (4) 표시 모드에서 액션바 5개 버튼이 흐리게 비활성화되고,
선택 모드에서 다시 정상 활성화되는지 — 특히 "개인 주석"/"관주"가
표시 모드에서 눌리지 않는 게 실제로 원하는 동작인지(위 트레이드오프
참고).

## [2026-08-11, 이어서 42] 선택모드 줄바꿈을 표시모드와 일치 + 줄간격 2.3 + 형광펜/밑줄 미리보기 문의 답변

### 배경

사용자가 두 가지 수정사항과 한 가지 문의를 남겼다:

1. **선택 모드의 줄바꿈이 표시 모드와 다르다** — 한 라인에 들어가는
   텍스트를 표시 모드와 동일하게 일치시켜 달라(줄바꿈 지점까지).
2. **선택 모드 줄 간격을 2.3으로.**
3. (문의) 선택 모드에서 메모 내용은 안 보여줘도 되니, 형광펜/밑줄/메모가
   달린 텍스트(파란색)는 표시해 줄 수 있는지.

### 원인 분석 (1번)

`SelectableVerseTextView`는 서식 없는 평범한 `UITextView`/`NSTextView`라
자기 자신의 자동 줄바꿈(폭 기준)으로 줄을 나눈다. 반면 표시 모드
(`AnnotatedVerseFlowView`)는 `VerseAnnotationRenderer.lineRanges(...)`가
고른 경계를 그대로 쓰는데, 이 함수는 한글 절에 한해 픽셀 폭이 아니라
"23자 최근접 띄어쓰기"라는 완전히 다른(글자 수 기준) 알고리즘
(`koreanLineRanges`)을 쓴다 — 그래서 같은 폭을 줘도 두 모드가 우연히
다른 자리에서 줄을 바꿀 수 있었다. 라틴/혼합 절(`measuredLineRanges`)은
애초에 TextKit 실측 기반이라 이 문제가 없다.

### 변경 내용

**`VerseAnnotationRenderer.swift`** — `forcedBreakText(from:font:containerWidth:)`
신설. `lineRanges(...)`로 표시 모드와 동일한 줄 경계를 구한 뒤, 경계
사이에 "건너뛴 구분자"(`koreanLineRanges`가 스킵하는 그 공백 한 글자)가
있으면 그 자리를 U+2028(라인 구분자)로 **치환**한다(삽입이 아님) — 글자
수·인덱스가 그대로 유지되므로 이 문자열 기준 `selectedRange`가 원본
`text`에서도 정확히 같은 위치를 가리킨다. 라틴/혼합 절은 줄 사이에
건너뛴 구분자가 없어(줄 끝 공백이 이미 그 줄 범위 안에 포함) 손대지
않는다 — 같은 폰트·같은 폭의 `UITextView`가 어차피 같은 TextKit
엔진으로 이미 같은 자리에서 자연스럽게 줄을 바꾸기 때문이다.

**`SelectableVerseTextView.swift`(iOS + macOS 둘 다)** — `containerWidth:
CGFloat` 파라미터를 추가해 `forcedBreakText(...)` 계산에 쓴다.
`attributedText`에 `NSMutableParagraphStyle.lineSpacing = font.
typographicLineHeight * (2.3 - 1)`를 적용했다 — `RichTextEditor.swift`가
이미 쓰는 "배수 → 포인트" 환산 관용식과 동일해, 프로젝트 전체에서
"줄간격 N"이 뜻하는 바가 일관된다.

**`VerseZoomView.swift`** — `SelectableVerseTextView(...)` 호출부에
`containerWidth: effectiveTextWidth`를 추가했다 — 표시 모드
(`AnnotatedVerseFlowView`)에 넘기는 것과 정확히 같은 값이라, 두 모드가
같은 폭을 기준으로 같은 함수(`lineRanges`)로 줄을 나누게 된다.

### 문의 답변 (3번)

가능하다. 선택 모드가 이미 `UITextView`/`NSTextView` 기반
`NSAttributedString`을 그리고 있으므로, `VerseAnnotationRenderer.
buildLines(...)`가 표시 모드에서 이미 계산해 주는 세그먼트별
`highlight`/`noteIDs` 정보를 그대로 재사용해 형광펜 배경색·밑줄·메모
텍스트 파란색만 속성으로 입히고 메모 박스/화살표는 그리지 않으면 된다
— 별도의 좌표 계산이 필요 없다(이미 있는 `buildLines`의 세그먼트
분해를 `NSAttributedString` 속성으로 매핑하기만 하면 된다). 다만 이번
라운드엔 사용자가 문의로만 남겼으므로 코드에는 반영하지 않았다 —
원하면 다음 라운드에 바로 구현 가능하다.

### 정적 검증

`VerseAnnotationRenderer.swift` 103/103·74/74·41/41,
`SelectableVerseTextView.swift` 41/41·28/28·4/4,
`VerseZoomView.swift` 164/164·113/113·12/12. 이상 없음.
`SelectableVerseTextView(...)` 호출부는 `VerseZoomView.swift` 한 곳뿐임을
grep으로 재확인.

⚠️ Xcode 확인 필요: (1) 확대보기에서 펜 아이콘으로 선택 모드에 들어갔을
때, 표시 모드에서 보이던 줄바꿈 위치와 정확히 같은 자리에서 줄이
바뀌는지(특히 순한글 절). (2) 선택 모드의 줄 간격이 표시 모드와
시각적으로 비슷한 밀도로 보이는지(두 모드가 서로 다른 렌더링 방식이라
"2.3"이 완전히 동일한 시각적 결과를 보장하진 않는다 — TextKit
`lineSpacing`과 SwiftUI `VStack(spacing: 10)`은 다른 계산식이다). (3)
U+2028 강제 줄바꿈 지점에서 드래그 선택이 자연스러운지(줄이 바뀌는
지점을 가로질러 드래그해도 `selectedRange`가 올바른 원본 인덱스를
가리키는지).

## [2026-08-11, 이어서 43] 선택모드에도 형광펜/밑줄/메모 글자색 표시

### 배경

"이어서 42"에서 "메모 내용은 안 보여줘도 되니 형광펜/밑줄/메모 텍스트
파란색은 선택 모드에서도 보여줄 수 있는가"라는 문의에 "가능하다"고
답한 데 이어, 사용자가 실제로 적용해 달라고 요청했다.

### 변경 내용

**`VerseAnnotationRenderer.swift`**

- `phraseNoteTextPlatformColor: PlatformColor` 신설 — 기존
  `phraseNoteTextColor: Color`(SwiftUI 전용, 표시 모드가 씀)의
  `PlatformColor` 버전. `HighlightColorTag.platformColor`와 같은 방식
  (`PlatformColor(Color)`)으로 변환한다 — "이어서 40"에서 "미사용"으로
  지웠던 것과 사실상 같은 프로퍼티인데, 이번에 선택 모드가 실제로 쓰게
  되어 다시 필요해졌다.
- `selectionModeAttributedText(text:highlights:phraseNotes:font:
  textColor:containerWidth:)` 신설 — 선택 모드가 그릴
  `NSAttributedString`을 이 한 곳에서 만든다. `buildLines(...)`가 표시
  모드에서 이미 계산해 주는 세그먼트 분해(형광펜/메모 경계점 기준으로
  겹치지 않게 쪼갠 조각, 조각당 덮는 형광펜 하나 + 메모 id 목록)를 그대로
  재사용해, 세그먼트별로 배경색(형광펜)·밑줄(표시, 주황 단선)·글자색
  (메모 있음 → 파랑)을 `NSAttributedString` 속성으로 입힌다. 메모
  "내용"(박스/화살표)은 그리지 않는다 — 여전히 표시 모드 전용이고, 여기선
  "이 표현에 메모가 있다"는 신호로 글자색만 바꾼다. 줄바꿈(`forcedBreakText`)
  ·줄간격(2.3) 로직도 이 함수 하나로 통합했다 — "이어서 42"에서 두 뷰
  파일에 각각 흩어져 있던 것을 한 곳으로 모았다.
- 표시 모드와 판정 로직 자체(`buildLines`)를 공유하므로, "어느 표현에
  무엇이 붙어 있는지"가 두 모드 사이에서 어긋날 여지가 구조적으로 없다.

**`SelectableVerseTextView.swift`(iOS + macOS 둘 다)** — `highlights:
[VerseHighlight]`/`phraseNotes: [VersePhraseNote]` 파라미터를 추가하고,
`attributedText`를 `VerseAnnotationRenderer.selectionModeAttributedText(...)`
호출로 교체했다(두 플랫폼이 완전히 같은 로직을 쓰므로 중복 없이 한
함수 재사용). `import BibleResearchModels`를 추가했다(`VerseHighlight`/
`VersePhraseNote` 타입 참조에 필요).

**`VerseZoomView.swift`** — `SelectableVerseTextView(...)` 호출부에
`highlights: highlights, phraseNotes: phraseNotes`를 추가했다(표시 모드에
넘기는 것과 정확히 같은 프로퍼티).

### 정적 검증

`VerseAnnotationRenderer.swift` 116/116·82/82·44/44,
`SelectableVerseTextView.swift` 35/35·28/28·6/6,
`VerseZoomView.swift` 164/164·113/113·12/12. 이상 없음.
`SelectableVerseTextView(...)` 호출부는 여전히 `VerseZoomView.swift`
한 곳뿐임을 grep으로 재확인.

⚠️ Xcode 확인 필요: (1) 선택 모드 진입 시 기존 형광펜(5색 배경)·표시
(주황 밑줄)·메모 있는 텍스트(파란 글자)가 표시 모드와 같은 위치에
정확히 보이는지. (2) 형광펜 배경색이 `.withAlphaComponent(...)`로 옅게
칠해질 때 선택(드래그) 하이라이트와 시각적으로 헷갈리지 않는지 —
`UITextView`/`NSTextView`의 네이티브 드래그 선택 색상과 겹쳐 보일 수
있어 실기기 확인이 특히 필요하다. (3) 형광펜/메모가 걸친 표현을 다시
드래그로 겹쳐 선택할 때(예: 새 형광펜을 추가로 칠하려는 경우) 기존
스타일과 새 선택이 잘 구별되는지.

## [2026-08-11, 이어서 44] 메모 팝업 정보 유실 버그 + 형광펜 줄간격 침범 + 액션바 순서 + "개인 주석" 명칭 통일

### 배경

사용자가 5가지를 보고/요청했다:

1. **버그**: 확대보기 - 선택모드 - 처음 텍스트 선택 - 처음 메모 클릭 시,
   메모 팝업 상단에 선택된 텍스트 정보가 안 보임. 팝업을 닫고 다시 메모를
   누르면 보임. 선택 모드를 나갔다가 처음부터 다시 하면 또 재현됨.
2. **버그**: (바로 위 "이어서 43"에서 추가한) 선택 모드 형광펜 배경이 줄
   간격만큼 늘어나 텍스트 부분만 칠해지지 않음.
3. 액션바의 [개인 주석]과 [메모] 순서를 바꿀 것.
4. 왼쪽 사이드바 [내 메모] → [개인 주석]으로 이름 변경.
5. 오른쪽 사이드바(구절 선택 시)의 "x절 관련 메모" → "x절 관련 개인 주석".

### 1) 메모 팝업 정보 유실 버그

**원인 분석** — 가장 유력한 원인은 팝오버가 뜨는 순간
`SelectableVerseTextView`의 `UITextView`/`NSTextView`가 first responder를
잃으면서(팝오버가 포커스를 가져가므로) iOS/macOS가 드래그 선택을
자동으로 해제하고, 그 델리게이트 콜백(`Coordinator.
textViewDidChangeSelection`)이 `DispatchQueue.main.async`로 미뤄져 있어
팝오버가 "이미 열린 뒤"에 `selectedRange`를 `(0, 0)`으로 되돌려 버리는
것이다. 팝오버 상단의 `anchorText`(선택된 텍스트 인용)가 `selectedRange`를
실시간으로 읽는 계산 프로퍼티였던 게 문제 — 이 리셋이 팝오버가 열린
직후에 일어나면 방금까지 있던 텍스트 정보가 사라져 보인다("다시
누르면 보인다"는 것도, 이미 한 번 리셋된 뒤라 그 이후엔 별다른 변화가
없어서라고 설명된다). 이 설명은 확실한 실기기 검증 없이 나온 가장
유력한 가설이라는 점을 밝혀 둔다 — 다만 아래 수정은 정확한 메커니즘이
무엇이든 근본적으로 안전한 방향(라이브 상태 의존 자체를 없앰)이라
가설이 틀렸더라도 부작용은 없다.

**변경 내용** — `VerseZoomView.swift`에 `editingAnchorRange`/
`editingAnchorText` 상태를 신설해, 팝오버를 "열기로 결정하는 바로 그
순간"("메모" 버튼 탭 시점)에 `selectedRange`/`anchorText`를 스냅샷으로
떠 둔다. 팝오버의 표시(`anchorText:` 파라미터)와 저장
(`addPhraseNote(...)`) 둘 다 이제 이 스냅샷만 쓴다 — 그 이후
`selectedRange`가 어떻게 바뀌든(포커스 손실로 리셋되든 말든) 전혀
영향받지 않는다. 이 수정은 부수적으로 더 심각할 수 있었던 잠재
버그(팝오버가 열린 뒤 `selectedRange`가 리셋되면 "저장"을 눌러도
`hasSelection`이 거짓이 되어 메모가 조용히 저장되지 않는 데이터 유실
가능성)도 함께 막는다.

### 2) 선택 모드 형광펜 줄간격 침범 버그

**원인 분석** — 기본 `NSLayoutManager`는 `.backgroundColor` 속성이 걸린
구간을 그 줄의 "줄 프래그먼트 사용 영역" 기준으로 채우는데, 이 사각형의
높이는 `paragraphStyle.lineSpacing`(바로 전 라운드에서 2.3으로 추가한
값)으로 늘어난 줄 간격까지 포함한다 — 이 프로젝트가 "이어서 39"에서
표시 모드의 형광펜/메모 위치 버그의 근본 원인으로 이미 확인한 것과
근본적으로 같은 부류의 문제가, 이번엔 선택 모드에 새로 추가한 배경색
렌더링에서 재발했다.

**변경 내용** — `SelectableVerseTextView.swift`(iOS + macOS 둘 다)에
`TightBackgroundLayoutManager`(`NSLayoutManager` 서브클래스)를 신설했다.
`fillBackgroundRectArray(...)`를 오버라이드해, 기본 구현이 넘겨주는
"줄 간격 포함 사각형"을 무시하고 "이어서 39"에서 검증한 것과 같은 원리
(글리프의 베이스라인 위치 `location(forGlyphAt:).y` + 폰트 ascender/
descender)로 글자 자체의 타이트한 사각형을 직접 계산해 채운다. 오직
"그리기"만 가로채는 개입이라(레이아웃 자체를 바꾸는 예전의
`NSLayoutManagerDelegate` 방식과 달리) 무한 재귀 같은 위험이 없다.

이 커스텀 레이아웃 매니저를 쓰려면 `UITextView()`/`NSTextView()` 기본
생성자 대신 `NSTextStorage`/`NSTextContainer`를 직접 엮어
`UITextView(frame:textContainer:)`/`NSTextView(frame:textContainer:)`로
만들어야 한다 — `makeUIView`/`makeNSView`를 그렇게 바꿨다.
`textStorage`/`layoutManager`는 `Coordinator`(SwiftUI가 이 표현 뷰의
수명 내내 들고 있어 준다)가 강한 참조로 붙들도록 했다 — TextKit 내부
그래프의 정확한 강/약 참조 방향을 문서만으로 단정할 근거가 부족해서,
"로컬 변수로만 만들면 나중에 예기치 않게 해제될 수도 있다"는 위험 자체를
없애는 쪽을 택했다.

### 3~5) 순서/명칭 변경

- `VerseZoomView.swift`의 actionBar — [메모] 버튼을 [개인 주석] 버튼보다
  앞으로 옮겼다(기존: 개인 주석 → 메모, 변경: 메모 → 개인 주석).
- `AppSection.swift`의 `.memos.title`을 "내 메모" → "개인 주석"으로
  바꿨다 — 사이드바·아이폰 탭바가 공유하는 단일 출처라 여기 한 곳만
  고치면 전부 일관되게 바뀐다. 연쇄적으로 어색해지는 곳들도 함께
  맞췄다: `MemoHomeView.swift`의 `.navigationTitle`("내 메모" → "개인
  주석"), `AppCommands.swift`/`SettingsView.swift`의 단축키 메뉴 라벨
  ("내 메모로 이동" → "개인 주석으로 이동").
- `ChapterRelatedContentPanel.swift`의 구절 선택 시 오른쪽 사이드바
  섹션 제목 — "x절 관련 메모" → "x절 관련 개인 주석"(빈 목록 안내
  문구도 같이 맞췄다).

### 정적 검증

`SelectableVerseTextView.swift` 64/64·35/35·6/6,
`VerseZoomView.swift` 165/165·113/113·12/12,
`AppSection.swift` 0/0·8/8·1/1, `MemoHomeView.swift` 98/98·66/66·8/8,
`AppCommands.swift` 65/65·19/19·4/4, `SettingsView.swift`
288/288·152/152·19/19, `ChapterRelatedContentPanel.swift`
82/82·44/44·0/0. 이상 없음.

⚠️ Xcode 확인 필요(이번 라운드 우선순위 높음): (1) 선택 모드에서 텍스트를
처음 드래그 선택한 뒤 "메모"를 처음 눌렀을 때 팝업 상단에 선택 텍스트가
바로 보이는지, 반복해도 재현되지 않는지. (2) 선택 모드 형광펜 배경이
이제 줄 간격을 침범하지 않고 글자 높이에 딱 맞게 칠해지는지 —
`fillBackgroundRectArray` 오버라이드가 처음 실전 투입되는 것이라 가장
불확실한 부분이다. (3) 커스텀 `UITextView(frame:textContainer:)`/
`NSTextView(frame:textContainer:)` 초기화로 바뀐 뒤에도 드래그 선택,
`sizeThatFits`(콘텐츠 높이 보고) 기존 동작이 전부 그대로인지 — 특히
아이패드/맥 회전·창 크기 변경 시. (4) 액션바 순서(메모 → 개인 주석)와
사이드바/단축키 명칭("개인 주석")이 화면에 정확히 반영됐는지.

## [2026-08-11, 이어서 45] 메모 팝업 정보 유실 버그 — 로그 기반 재진단 + 메모 드래그 앞뒤 공백 trim

### 배경

"이어서 44"의 스냅샷 수정(팝오버를 열기로 결정하는 순간 `selectedRange`/
`anchorText`를 떠 두는 것) 이후에도 사용자가 스크린샷으로 같은 증상을
다시 보고했다 — 메모 편집 팝업 상단의 선택 텍스트 인용란이 여전히 비어
있음. 사용자가 명시적으로 "다시 확인할 것. 필요하면 로그를 찍어 정확한
원인을 분석하고 문제점 파악후 해결 할것"이라고 요청했다 — 실기기/Xcode
없이는 어떤 가설도 확정할 수 없는 상태에서 또 추측성 수정을 반복하는
대신, 정확히 어느 지점에서 값이 비는지 데이터로 확인할 수 있는 로그를
심는 쪽을 선택했다.

### 왜 스냅샷 수정만으로 불충분할 수 있는가

"이어서 44"의 수정은 "메모" 버튼을 누르는 그 순간 `selectedRange`/
`anchorText`를 스냅샷 뜨는 것이었다 — 이후 `selectedRange`가 어떻게
바뀌든 팝오버 표시/저장에 영향이 없어야 한다. 이게 여전히 재현된다면
가능한 설명은 두 가지다: (a) 스냅샷을 뜨는 **그 순간에 이미**
`selectedRange`가 비어 있었다(즉 탭 이전에 이미 리셋됐다 — 지금까지의
"팝오버가 열린 뒤 리셋된다"는 가설과는 다른 타이밍), 또는 (b) 스냅샷
자체는 정상인데 `PhraseNoteEditorPopover`로 전달되는 경로 어딘가에서
값이 유실된다(SwiftUI 뷰 전달 문제). 이 둘은 증상이 똑같아 보이지만
원인과 대책이 전혀 다르므로, 실측 없이는 더 진행할 수 없다고 판단했다.

### 추가한 진단 로그 (전부 `#if DEBUG`, `[메모진단]` 태그로 통일)

- `VerseZoomView.swift`의 "메모" 버튼 핸들러 — 탭 시점의 `selectedRange`,
  trim 후 범위, 최종 `anchorText`, 겹치는 기존 메모 유무를 찍는다.
- `PhraseNoteEditorPopover.init` — 실제로 "받은" `anchorText`를
  `.debugDescription`으로 찍는다(빈 문자열/공백/제어문자를 육안으로
  구분하기 위해 — 일반 출력으로는 빈 문자열과 공백 하나가 똑같이 보일 수
  있다).
- `SelectableVerseTextView.Coordinator.textViewDidChangeSelection`
  (iOS + macOS 둘 다) — 델리게이트가 실제로 언제, 어떤 값으로 불리는지,
  그리고 그 순간 `isFirstResponder`(macOS는 `window?.firstResponder ===
  textView`)가 무엇인지 찍는다 — "포커스를 잃으면서 선택이 리셋된다"는
  기존 가설을 직접 검증하기 위해서다.
- `updateUIView`/`updateNSView`가 SwiftUI 쪽 `selectedRange`를 텍스트뷰에
  강제로 되돌려 쓰는 시점도 로그로 남긴다 — 델리게이트 로그와 시간순으로
  대조하면 "포커스 손실 → 비동기 리셋 → 우리가 다시 덮어씀"의 핑퐁
  여부를 확인할 수 있다.

**사용자에게 요청** — Xcode에서 재현 시나리오(확대보기 → 선택모드 →
드래그로 새 텍스트 선택 → "메모" 버튼)를 다시 밟아 보고, 콘솔에 찍힌
`[메모진단]` 로그 전체(순서 그대로)를 다음 라운드에 붙여 달라. 그 로그를
보면 위 (a)/(b) 중 어느 쪽인지, 혹은 전혀 다른 제3의 원인인지 정확히
가려낼 수 있다.

### 메모 드래그 앞뒤 공백 trim (신규 요청)

사용자 요청 — "메모 드래그시 앞뒤 텍스트 trim 처리하여 메모등록할 수
있게 할 것. ex) '더 ', ' 더 ' = '더'." `VerseZoomView.swift`에
`trimmedRange(_:in:)`을 신설해, "메모" 버튼을 누르는 시점에 선택 범위의
앞뒤 공백(스페이스·탭·줄바꿈, `CharacterSet.whitespacesAndNewlines`
기준)을 잘라낸 뒤 그 축소된 범위/텍스트를 앵커로 쓴다. 문자를
치환하는 게 아니라 범위의 시작/끝만 안쪽으로 옮기는 것이라 인덱스가
어긋날 위험이 없다. 공백만 선택한 경우(trim 결과 길이 0)엔 메모를
만들지 않고 선택 모드로 되돌아간다. 이 trim은 사용자 요청 범위 그대로
"메모" 기능에만 적용했다 — 형광펜/표시/관주는 건드리지 않았다(같은
헬퍼를 재사용해 확장하는 건 간단하니, 필요하면 다음 라운드에 바로
가능하다).

### 정적 검증

`VerseZoomView.swift` 181/181·117/117·12/12,
`PhraseNoteEditorPopover.swift` 60/60·13/13·1/1,
`SelectableVerseTextView.swift` 70/70·35/35·6/6. 이상 없음.

⚠️ 이번 라운드는 "고침"이 아니라 "측정 준비"에 가깝다 — trim 기능은
바로 검증 가능하지만, 메모 팝업 정보 유실 버그 자체는 다음 라운드에
로그를 받아야 실제 원인 기반 수정이 가능하다. 재현 시 콘솔 로그
전체를 공유해 주시면 그걸 바탕으로 정확히 고치겠다.

## [2026-08-11, 이어서 46] 메모 팝업 정보 유실 버그 — 로그 분석 결과 및 근본 수정

### 사용자가 제공한 로그로 확인한 사실

`[메모진단]` 로그를 실제로 받아 분석했다. 핵심 대목:

```
[메모진단] 버튼 탭 — selectedRange={0, 2} trimmed={0, 1} verseText.length=68
[메모진단] anchorText="더" existingNote=nil
[메모진단] PhraseNoteEditorPopover.init 수신 anchorText="" isEditing=false
```

버튼 핸들러가 계산한 `anchorText`는 항상 "더"로 **정확했다** — 그런데
`PhraseNoteEditorPopover.init`이 실제로 **받은** 값은 빈 문자열이었다.
더 결정적인 증거는 세션 끝부분의 이 로그다:

```
[메모진단] 버튼 탭 — selectedRange={19, 3} trimmed={20, 1} verseText.length=68
[메모진단] anchorText="갈" existingNote=FFC3EBAC-064B-49E0-90A4-247768CEAA76
[메모진단] PhraseNoteEditorPopover.init 수신 anchorText="" isEditing=false
```

`existingNote`가 `nil`이 아닌데(기존 메모를 찾음) `isEditing`은
`false`로 찍혔다 — `editingPhraseNote`가 `let anchorText`/`isEditing`
**둘 다 아닌 `@State`도 아닌 plain `let` 파라미터**인데도 잘못된 값이
찍힌 것이다. 즉 이건 데이터 흐름(우리 코드의 계산 로직) 문제가
**아니다** — 계산된 값은 로그상 항상 맞았다. 대신 같은 값(같은 텍스트,
같은 노트)으로 **두 번째 시도하면 정상 동작**했다는 패턴이 반복해서
나타났다(예: "더"는 처음 3번 실패, 이후 "숨길 수"가 성공한 뒤로는 "더"도
성공).

### 원인

이 패턴은 데이터 문제가 아니라, **SwiftUI `.popover(isPresented:)`가 어떤
`.id(...)` 정체성을 이 세션에서 "처음" 준비하는 프레임에서, 그 콘텐츠
클로저를 데이터-상태 변경이 완전히 커밋되기 전 시점의 스냅샷으로 평가하는
것**으로 보인다 — 같은 종류의 문제가 여러 SwiftUI 개발자 커뮤니티에서
"팝오버/시트 첫 표시 시 낡은 데이터가 보인다"로 보고돼 있다. 우리
핸들러는 `editingPhraseNote`/`editingAnchorRange`/`editingAnchorText`를
설정하는 것과 `isPhraseNoteEditorPresented = true`(팝오버를 실제로 열라는
명령)를 **같은 동기 클로저**, 즉 같은 SwiftUI 트랜잭션 안에서 함께
실행했다 — 그 정체성이 이 세션에서 처음이면, 팝오버 프레젠테이션
파이프라인이 데이터 상태 커밋보다 먼저(또는 그와 경합하며) 콘텐츠를
준비해 버리는 것이다.

### 수정

`presentPhraseNoteEditor()` 헬퍼를 신설 — 데이터 상태
(`editingPhraseNote`/`editingAnchorRange`/`editingAnchorText`)는 그대로
동기적으로 설정하되, `isPhraseNoteEditorPresented = true`만
`DispatchQueue.main.async`로 다음 런루프 틱에 미룬다. 이러면 데이터
상태 변경이 담긴 트랜잭션이 완전히 커밋(렌더링 반영)된 뒤에야 팝오버
프레젠테이션 트랜잭션이 시작되므로, 팝오버가 "처음 준비되는" 프레임이
더 이상 "데이터가 아직 안 들어온" 프레임과 겹치지 않는다. "메모" 액션바
버튼과 표시 모드의 "메모 수정"(`onRequestEditPhraseNote`) 콜백 둘 다
이 헬퍼를 쓰도록 통일했다(둘 다 같은 종류의 동시 설정 패턴이었다).

### 정적 검증

`VerseZoomView.swift` 185/185·119/119·12/12. 이상 없음. 진단용
`[메모진단]` 로그는 이번 라운드에도 그대로 남겨 뒀다 — 수정이 실제로
효과가 있는지 같은 로그로 바로 확인할 수 있고, 혹시 또 재현되면 추가
단서가 되기 때문이다(안정화가 확인되면 다음 라운드에 정리해서 걷어낼
수 있다).

⚠️ Xcode 확인 필요(최우선): 같은 재현 시나리오(확대보기 → 선택모드 →
드래그로 새 텍스트 선택 → "메모" 클릭)를 **처음 시도부터** 밟아 보고,
팝업 상단에 선택 텍스트가 바로 보이는지 확인 부탁드린다. 이번에도
재현되면 콘솔의 `[메모진단]` 로그(특히 `presentPhraseNoteEditor 지연
실행` 로그가 실제로 찍히는지, 그 이후 `PhraseNoteEditorPopover.init
수신`이 몇 번째 줄에 찍히는지)를 다시 공유해 주시면 다음 단계로
넘어가겠다.

## [2026-08-11, 이어서 47] 메모 팝업 정보 유실 버그 — 2차 로그 분석 + Binding 기반 재설계

### 2차 로그로 확인한 것 — "이어서 46" 가설이 틀렸다

"이어서 46"의 수정(데이터 상태 설정과 `isPhraseNoteEditorPresented =
true`를 다른 런루프 틱으로 분리)을 적용한 뒤에도 사용자가 다시 로그를
보내 재현을 확인해 줬다. 결과는 가설을 정면으로 반박했다:

```
[메모진단] anchorText="더" existingNote=nil
[메모진단] presentPhraseNoteEditor 지연 실행 — isPhraseNoteEditorPresented = true
[메모진단] PhraseNoteEditorPopover.init 수신 anchorText="" isEditing=false   ← 실패
```
같은 `selectedRange={0,2}`("더")로 **3번 연속** 재시도해도 3번 다
실패했다 — "지연 실행" 로그가 매번 정상적으로 찍혔는데도. 반면:
```
[메모진단] anchorText="상자를" existingNote=nil
[메모진단] PhraseNoteEditorPopover.init 수신 anchorText="상자를" isEditing=false  ← 첫 시도부터 성공
```
"상자를"은 (같은 `.id("new")`를 공유하는데도) 첫 시도부터 성공했고,
"이에 두고"는 첫 시도 실패 후 재시도(같은 범위, 재선택 없이)에서
성공했다. `.id(...)`가 전혀 안 바뀌었는데도 성공/실패가 갈렸다는 건
"정체성이 처음 준비되는 프레임" 가설도, "프레젠테이션을 지연시키면
된다"는 가설도 둘 다 틀렸다는 뜻이다 — 지연이 있든 없든, 정체성이
새것이든 아니든 실패가 발생했다.

### 재해석 — "생성자 인자로 값을 한 번 받는 것" 자체가 문제

두 라운드의 로그를 종합하면 남는 설명은 하나다: `PhraseNoteEditorPopover`
가 `anchorText`/`isEditing`을 **생성자에서 `let`으로 한 번만 받는
설계** 자체가 SwiftUI `.popover` 콘텐츠 클로저의 내부 동작(정확한
메커니즘은 확인할 수 없었지만, 여러 번 값을 계산/전달하는 과정 어딘가에서
경합이 생기는 것으로 보인다)과 안정적으로 맞물리지 않는다 — "언제"
계산하고 "언제" 넘기느냐를 아무리 조정해도(스냅샷 시점 조정, 프레젠
테이션 지연) 해결되지 않았으므로, 값을 넘기는 **방식** 자체를 바꿔야
한다고 판단했다.

### 수정 — `let` 생성자 인자를 `@Binding`으로 교체

`PhraseNoteEditorPopover.swift`를 재설계했다:

- `anchorText: String`/`isEditing: Bool`(생성자에서만 채워지던 `let`)을
  없애고, 대신 `@Binding var editingPhraseNote: VersePhraseNote?`와
  `@Binding var pendingAnchorText: String`을 직접 받는다. `anchorText`/
  `isEditing`은 이제 이 바인딩들을 읽는 **계산 프로퍼티**다 —
  `editingPhraseNote?.anchorText ?? pendingAnchorText`,
  `editingPhraseNote != nil`. `@Binding`의 값은 SwiftUI가 그것을 참조할
  때마다(= `body`가 그려질 때마다) 다시 읽어 오는 것이라, 생성자 호출
  시점에 "얼려서" 들고 있는 `let`과 근본적으로 다르다 — `body`가 그려지는
  시점은 언제나 부모(`VerseZoomView`)의 상태 변경이 이미 반영된
  이후이므로, 이 값이 "아직 안 들어온 스냅샷"일 수가 없다.
- `noteText`의 초기값도 `init`이 아니라 `.onAppear`(뷰가 실제로 화면에
  붙은 뒤 — `init`보다 훨씬 늦은 시점)에서 `editingPhraseNote?.noteText
  ?? ""`로 시드하도록 옮겼다.
- `onDelete`도 `(() -> Void)?`(닫힌 클로저로 노트를 미리 캡처)에서
  `(VersePhraseNote) -> Void`(삭제 버튼 탭 시점에 `editingPhraseNote`를
  직접 읽어 넘김)로 바꿨다 — 같은 종류의 "미리 캡처" 위험을 없애는
  방향으로 일관되게 정리했다.
- `VerseZoomView.swift`의 `.popover(...)` 호출부를
  `PhraseNoteEditorPopover(editingPhraseNote: $editingPhraseNote,
  pendingAnchorText: $editingAnchorText, onSave:..., onDelete: { note in
  viewModel.deletePhraseNote(note) })`로 바꿨다. `.id(...)`는 혹시 몰라
  그대로 남겨 뒀다.
- 진단 로그(`[메모진단]`)는 `init`이 아니라 이제 `.onAppear`에서 찍는다
  — 이번 수정이 실제로 효과가 있는지 같은 태그로 바로 확인할 수 있다.

### 정적 검증

`PhraseNoteEditorPopover.swift` 54/54·16/16·1/1,
`VerseZoomView.swift` 185/185·118/118·12/12. 이상 없음.
`PhraseNoteEditorPopover(...)` 호출부가 `VerseZoomView.swift` 한 곳뿐임을
grep으로 재확인.

⚠️ Xcode 확인 필요(최우선, 이번엔 특히 "3번 연속 실패했던 것과 같은
패턴으로" — 같은 텍스트를 여러 번 반복 시도해도 매번 정상적으로
텍스트 정보가 보이는지 확인 부탁드린다): 여전히 재현되면 콘솔의
`[메모진단] PhraseNoteEditorPopover.onAppear` 로그를 공유해 주시면
된다 — 이번엔 `let` 자체를 없앴으므로, 만약 그래도 재현된다면 원인은
이 팝업 자체가 아니라 더 상위(예: `VerseZoomView`의 `@State` 저장소
자체, 또는 `NavigationStack`/윈도우 레벨의 다른 무언가)에 있다는 뜻이
되어 다음 단계 진단 방향이 완전히 달라진다.

**사용자 확인**: `@Binding` 재설계 이후 재현 시나리오를 다시 밟아 본
결과 "잘 됨" — 메모 팝업 정보 유실 버그는 해결된 것으로 확인됐다.

## [2026-08-11, 이어서 48] 확대보기 번역본 피커 라벨 텍스트 제거

사용자 요청 — "확대보기 상단 타이틀 밑 picker의 '번역본' 텍스트 제거."
`VerseZoomView.swift`의 `translationSwitcher`에 `.labelsHidden()`을
추가했다. iOS의 `.segmented` 피커 스타일은 애초에 라벨을 그리지 않지만,
macOS는 세그먼트 컨트롤 옆에 `Picker("번역본", ...)`의 라벨을 텍스트로
그대로 보여준다 — 사용자가 macOS에서 본 화면(직전 라운드 스크린샷도
macOS)이라 이 차이가 드러난 것으로 보인다. `.labelsHidden()`은 시각적
라벨만 숨기고 접근성 라벨("번역본")은 그대로 유지한다.

### 정적 검증

`VerseZoomView.swift` 186/186·118/118·12/12. 이상 없음.

⚠️ Xcode 확인 필요: macOS에서 "번역본" 텍스트가 사라지고 세그먼트
컨트롤만 남는지, iOS/iPadOS에서는(원래도 안 보였겠지만) 회귀가 없는지.

## [2026-08-11, 이어서 49] 진단용 [메모진단] 로그 정리

메모 팝업 정보 유실 버그가 해결된 것으로 확인됨에 따라, 사용자 요청으로
"이어서 45~47"에서 진단용으로 심었던 `#if DEBUG print("[메모진단]...")`
블록을 전부 제거했다 — `VerseZoomView.swift`(버튼 핸들러,
`presentPhraseNoteEditor`), `PhraseNoteEditorPopover.swift`
(`.onAppear`), `SelectableVerseTextView.swift`(iOS/macOS
`Coordinator.textViewDidChangeSelection`, `updateUIView`/`updateNSView`)
6곳. 로그를 심었던 이유와 분석 결과를 설명하던 주변 주석 중 로그
자체를 가리키던 문장들도 함께 정리했다 — 다만 "이어서 45~47"의 원인
분석 서술(왜 `@Binding` 재설계가 필요했는지) 자체는 나중에 비슷한
문제가 재발했을 때 참고할 가치가 있어 그대로 남겨 뒀다.

### 정적 검증

`VerseZoomView.swift` 182/182·118/118·12/12,
`PhraseNoteEditorPopover.swift` 53/53·16/16·1/1,
`SelectableVerseTextView.swift` 64/64·35/35·6/6. 이상 없음.
`grep -rn "메모진단"` 결과 실제 `print(...)` 호출은 전부 사라졌고,
"어떤 로그로 무엇을 확인했는지"를 설명하는 과거형 주석 3곳만 남았음을
확인했다(더 이상 존재하지 않는 로그를 지금 시점 지시문처럼 언급하지
않도록 문구도 과거형으로 되어 있는지 확인함).

## [2026-08-13, 이어서 50] 나훔 누락 절 채우기(파일럿) + 원문 정보 카드 그리드 UI

사용자 요청: "오픈 소스로 ... 데이터를 만들 수 있다면, 현재 DB에 추가하여
개선할 수 있는가?"에 이어, 창세기 1장/출애굽기 2장 스크래치패드 데이터로
검증했던 OSHB(CC BY 4.0) 기반 파이프라인을 실제 `OriginalText.sqlite`
데이터에 처음으로 적용한 파일럿. "일부로 먼저 시작해서 확인하고 싶음
완벽하지는 않더라도 되도록 첨부파일 모양처럼 표현하고 싶음" → 검증 후
"둘다 진행"(데이터 채우기 + UI 적용 둘 다) 지시로 마무리.

- **누락 절 재확인**: 이번에 다시 세어 보니 나훔은 2장 전체(13절)뿐 아니라
  1장 마지막 절(1:15)도 비어 있었다(원본 변환 스크립트가 이 두 군데를
  놓친 것으로 보임 — 정확한 원인은 조사하지 않음). 둘 다 채웠다.
- **버전 구분 주의**: OSHB 히브리어 장절 구분과 개역개정(KJV식) 장절 구분이
  나훔 1장 후반부터 한 칸씩 어긋난다 — OSHB `Nah.2.1`이 실제로는 개역개정
  `나훔 1:15`, OSHB `Nah.2.2`가 개역개정 `나훔 2:1` ... `Nah.2.14`가
  `나훔 2:13`이다. OSHB XML의 `<note>KJV:...</note>` 대응 주석을 그대로
  따라 개역개정 번호로 맞췄다(`BibleDB.sqlite`의 `BibleVerses`로 나훔
  1장=15절/2장=13절임을 먼저 확인).
  - `wlc/Nah.xml`(OSHB, CC BY 4.0)에서 직접 읽은 원문·lemma·형태소 코드를
    바탕으로, 영어 뜻풀이(`gloss_en`, 짧은 원형 대역)와 음역은 새로
    작성했다 — 스크래치패드 `nahum2_fill.py`에 소스로 남겨 둠.
  - Strong 번호는 실제 DB 컨벤션과 동일하게 `H`+4자리 zero-pad, 접미
    구분문자(a/b/c...) 제거로 변환(`insert_nahum.py`의
    `strong_code()`). 전치사+접미사만 있고 lemma에 숫자가 없는 딱 한
    단어(나훔 1:15 "בָּ֥/ךְ")는 전치사 בְּ의 표준 Strong 번호 H0904를
    수동으로 매겼다.
  - 총 172행 삽입(1:15 21행 + 2:1~2:13 151행). 삽입 전 실제
    `Resources/OriginalText.sqlite`를 복사해 작업하고, 해당 절이 이미
    있으면 중단하는 안전장치를 넣은 뒤 실행 → 검증 → 원본 파일에
    반영(425,441행 → 425,613행). ⚠️ 나머지 ~128개 누락 장은 이번 라운드
    범위 밖(사용자가 파일럿으로 먼저 확인하길 원함) — 계속하려면 같은
    절차(OSHB XML 조회 → KJV 노트로 장절 재매핑 → strong_code 변환 →
    삽입)를 반복하면 된다.
- **형태소→한글 설명 Swift 포팅**: 스크래치패드에서 만들고 검증했던
  `morph_parser.py`(OSHB 형태소 코드 → 한국어 문법 설명)를
  `HebrewMorphologyDescriber.swift`(신설,
  `BibleResearchPlatform/Sources/BibleResearchModels/BibleReference/`)로
  그대로 이식했다. `OriginalWordInfo`에 계산 프로퍼티
  `morphDescriptionKo`를 추가해 DB에 저장하지 않고 렌더링 시점에 계산한다
  (그리스어는 지원 안 해 빈 문자열 — README 앞부분에 남겨 둔 이유와 동일,
  Robinson 태그 체계를 신뢰할 만한 단일 출처로 확인 못 함).
- **원문 정보 화면 카드 그리드**: `OriginalTextInfoView.swift`의
  `LazyVStack`(세로 한 줄 카드)을 `LazyVGrid`(적응형 열)로 바꾸고, 카드
  내용도 사용자가 첨부한 목업 순서(한글 뜻 헤드라인 → 원어 파란 글씨 →
  음역 대괄호 → 형태소 문법 설명)로 다시 짰다. 기존에 문서화됐던 "Strong
  번호+원어+음역+영어+한글" 4항목 스펙에 형태소 설명이 새로 추가된 것 —
  Strong번호/영어 뜻풀이는 카드 하단 보조줄로 옮겼다(그리스어는 형태소
  설명이 비므로 그 자리에 영어 뜻풀이가 대신 나온다). 한글 뜻풀이 수정
  연필 아이콘 등 기존 기능은 그대로 유지.

### 정적 검증

`OriginalTextInfoView.swift` 66/66·153/153·37/37,
`HebrewMorphologyDescriber.swift` 39/39·98/98·60/60. 이상 없음.
`OriginalText.sqlite`는 파이썬으로 삽입 후 행 수(425,613)와 나훔 1:15·
2:1·2:13 샘플 행을 직접 조회해 확인했다.

⚠️ Xcode 확인 필요: 이번 세션도 컴파일 환경이 없어 괄호 균형과 로직 정독
검토만 했다 — `LazyVGrid` 실제 렌더링(카드 줄바꿈, 열 개수), 새 형태소
설명 문장이 실기기에서 어색하게 잘리지 않는지, 나훔 1:15/2장 카드가
실제로 표시되는지는 Xcode에서 직접 확인 필요.

## [2026-08-13, 이어서 51] 카드 UI 마무리 + 누락 원어 데이터 거의 전량 채우기

같은 날 이어서 사용자 요청 3건: "① 각 원어정보 섹션마다 파란색 라운드
사각형테두리 추가할 것 ② 타이틀 아래 원문 정보 가장 상단에 해당 구절
(개역한글 KRV) 텍스트를 보여줄것 ③ 나머지 원어 정보도 추가할 것."

### 1) UI 마무리 (①②)

`OriginalTextInfoView.swift`: `wordCard`에 `.overlay(RoundedRectangle(...)
.stroke(Color.blue, lineWidth: 1.5))` 추가. 시트 상단에 `krvVerseText`
상태를 새로 두고 `loadKRVVerseText()`(`TranslationBootstrap.
resolvedBundledDatabaseURL()` + `BibleReferenceStore.verse(...)`로 번들
KRV=개역한글 DB에서 직접 조회, 사용자가 화면에 켜 둔 다른 번역본과 무관하게
항상 KRV 고정)로 채운다. 원어 데이터가 없는 절(당시 기준 여전히 많이
남아있던 누락 장)에서도 이 텍스트만은 보이도록 `words.isEmpty` 분기 밖으로
뺐다 — 참고로 이 배치 판단 자체가 잠시 뒤 ③ 작업으로 거의 무의미해질
정도로 누락분이 채워졌다.

### 2) 나머지 누락 원어 데이터 채우기 (③) — 가장 큰 작업

**시행착오**: 처음엔 나훔처럼 OSHB(openscriptures/morphhb) 원문을 직접 받아
단어별로 번역하는 방식을 시도했으나, 나훔(3장, 다 짧음)과 달리 말라기(4장)
조차 원문 XML 파일이 `web_fetch` 응답 크기 한도(약 5만5천자)에 걸려 2장
중간에서 끊겼다. 같은 URL을 다시 요청해도 항상 같은 지점까지만 받아지고
"이어받기"가 안 돼(range 요청 불가), 구조적으로 긴 책은 이 경로로 완결할
수 없다는 걸 확인했다(사용자에게 보고 후 확인받음). STEPBible 웹사이트
인터랙티브 뷰(stepbible.org)도 시도했으나 원어+Strong+형태소가 함께 나오는
인터리니어 뷰는 JS로 그려져 정적 `web_fetch`로는 안 잡혔다.

**해결**: 사용자가 실제 GitHub STEPBible-Data 저장소에서 원본 6개 파일
(TAHOT Gen-Deu/Jos-Est/Job-Sng/Isa-Mal, TAGNT Mat-Jhn/Act-Rev — 2026-08-09
최초 변환 때와 정확히 같은 소스, 개당 15~24MB)을 직접 받아 프로젝트
`Resources/`에 넣어 줬다. `web_fetch`의 크기 제한은 원격 HTTP 요청에만
적용되고 로컬 파일 읽기(Python)는 그런 제한이 없어, 이 경로로 완전히
해결됐다.

- **컬럼 구조 역검증**: 이미 DB에 있는 절(Isa.1.1 — 창세기 1장/출애굽기
  2장과 함께 처음부터 검증에 써 온 절, Jhn.3.16 — README에 명시된 샘플)의
  기존 425,613행과 새로 파싱한 결과를 단어 단위로 대조해 컬럼 인덱스와
  추출 규칙을 확정했다:
  - TAHOT(히브리어) 한 줄 = `Book.C.V(hC.hV)#NN=Type\t원어\t음역\t문맥역\t결합Strong\t문법\t...\tdStrongs(단일)\t...\tExpanded Strong tags`.
    참조의 괄호 밖 장절이 **영어/개역 전통 번호**임을 확인(예: `Nam.2.13
    (2.14)` = 개역 나훔2:13 = 히브리 2:14) — 이번 세션 초반에 나훔을 채울 때
    직접 손으로 했던 KJV-노트 재매핑을, TAHOT는 애초에 필요 없게 이미 영어
    전통 번호를 기본 참조로 쓰고 있었다(뒤늦게 발견 — 나훔은 이미 삽입돼
    있어 다시 만들지 않고 그대로 뒀다). strong_code는 `dStrongs`(단일 값)
    칸에서, gloss_en은 `Expanded Strong tags`의 `{STRONG=원어=REST}` 중
    REST를 `»` 유무·앞부분이 `:`로 시작하는지로 분기해 추출(README 앞
    라운드에 이미 기록된 휴리스틱과 동일 — 이번에 Isa.1.1 15단어 중
    14개가 기존 DB와 정확히 일치함을 확인했고, 나머지 1개는 기존 425,613행
    쪽의 사소한 기존 불일치로 보여 억지로 재현하지 않았다).
  - Type은 `L`(레닌그라드 사본의 실제 읽는 본문, 케레 반영됨)만 채택,
    `K`/`Q` 단독 변형은 제외 — 단, 극히 드물게 특정 단어 자리에 `L` 줄
    자체가 없고 `Q(K)`류만 있는 경우(예: `Exo.22.5(22.4)#09`)가 있어, 그런
    자리는 대체로 받아들이되 같은 자리에 `L`이 있으면 그것으로 덮어쓰는
    우선순위 로직을 넣었다(처음엔 이걸 안 넣어서 91개 절에서 단어 하나씩
    빠지는 문제가 있었음 — word_order 연속성 검사로 발견해 수정).
  - TAGNT(그리스어)는 `Book.C.V#NN=Editions\t"원어 (음역)"\t문맥역\tStrong=문법\t사전형=영어뜻풀이\t...` —
    Jhn.3.16 26단어 전부 기존 DB와 정확히 일치 확인. 그리스어 형태소
    코드는 히브리어와 달리 언어 문자 접두가 없어 그대로 저장.
- **검증**: 삽입 전 (책,장,절,단어순서) 중복 0건·strong_code 형식(`[HG]\d{4}`)
  위반 0건·빈 원문 0건 확인. 이미 데이터가 있는 절은 통째로 건너뛰는
  안전장치도 그대로 유지(이번엔 대상 전부가 진짜 누락분이라 걸린 것 없음).
- **결과**: 1,963개 누락 절 중 **1,954개**(99.5%)를 21,230개 단어 행으로
  채웠다. `Resources/OriginalText.sqlite` 425,613행 → **446,843행**.
  시편(988절)이 압도적으로 많았고, 역대상(117절, 계보 반복 구간)·신명기
  (74절)·느헤미야(69절)·다니엘(66절)·출애굽기(63절) 순.
- **남은 9절**: 아가 6:14, 요한복음 7:53(간음한 여인 단락 경계), 로마서
  16:25-27(송영 — 사본별 위치가 다른 유명한 이문 구간), 고린도후서 13:13,
  빌립보서 1:16-17, 요한삼서 1:15 — 전부 그리스어 사본 전통 간 절 구분
  경계/이문 문제로 TAHOT/TAGNT의 표준 참조 하나로 안 잡히는 특수 사례다.
  ⚠️ 이번 라운드 범위 밖으로 남김 — 필요하면 해당 구간만 별도로 원문을
  대조해 수동으로 채워야 한다.
- 스크래치패드 산출물(재사용 가능, 실제 앱에는 포함 안 됨): `parse_stepbible.py`
  (파싱기, 컬럼 인덱스·추출 규칙에 대한 주석 포함), `insert_stepbible.py`
  (삽입+검증 스크립트).

### 정적 검증

`OriginalTextInfoView.swift` 70/70·186/186·42/42. `OriginalText.sqlite`는
삽입 스크립트가 전체 행수(446,843)·책별 채운 절 수·요나 2:1/말라기 4:6
샘플 행을 직접 조회해 출력한 걸로 확인했고, 프로젝트 폴더에 복사한 뒤
`md5sum`으로 원본과 바이트 단위까지 동일한지 재확인했다.

⚠️ 후속 필요: 원본 STEPBible `.txt` 6개(약 100MB)는 변환이 끝나 더 이상
필요 없다 — 2026-08-09 최초 변환 때와 마찬가지로 `Resources/`에서 삭제
권장(안 지우면 Xcode가 번들 리소스로 얹어 앱 용량만 키운다). 이 세션은
연결된 프로젝트 폴더의 파일을 지울 때 사용자 확인이 필요해 삭제 여부를
사용자에게 물어봐야 한다. 남은 9개 절, Greek 형태소 설명 미지원(기존
한계, 이번에도 안 건드림)도 후속 과제로 남아 있다.
- **[2026-08-13 후속]** 삭제 여부를 물었더니 사용자가 `allow_cowork_file_delete`
  승인을 거절 — 6개 원본 `.txt`는 `Resources/`에 그대로 남아 있다. Xcode
  타겟의 Copy Bundle Resources에 안 걸려 있는지는 직접 확인 필요.

## [2026-08-13, 이어서 52] 원문 정보 카드 스크린샷 핏셀 매칭 + biblehub.com 딥링크

사용자가 실제 카드 스크린샷(허리를 / מָתְנַיִם 파란 굵게 / [mot.Na.yim] /
명사 보통명사 남성 쌍수 절대형, 전부 가운데 정렬 + 옅은 회색 테두리)을 주며
"테두리 색상, 원문색상, 품사 글꼴 색상, 정렬 .. 맞출것 + 전문가 디자이너
관점에서 시각적으로 세련되게"를 요청 → 이어서 "연필 아이콘 위치/크기/색"
2차 조정 → 이어서 biblehub.com 딥링크 2건 추가, 마지막으로 아이콘을
`pencil.circle`(14pt)로 다시 조정. `OriginalTextInfoView.swift`가 이번
라운드에서 가장 많이 바뀐 파일.

### 1) 카드 스타일을 스크린샷에 맞춤

- `wordCard`를 좌측 정렬 `VStack(alignment: .leading)` + 진한 파란
  `.stroke(Color.blue, lineWidth: 1.5)`에서 → `VStack(spacing: 8)`(기본
  가운데 정렬) + `cardBorderColor`(iOS `.separator`/macOS `.separatorColor`,
  라이트·다크 모드 모두 옅은 회색)로 교체. 모든 `Text`에
  `.multilineTextAlignment(.center)` 추가.
- 원어 텍스트 색은 `Color.blue`(시스템 기본) 대신 스크린샷 채도에 맞춘
  커스텀 남색 `Color(red: 0.09, green: 0.25, blue: 0.78)`(`hebrewTextColor`)로.
- "전문가 디자이너 관점" 요청에 대한 판단: 카드에 `.shadow(color: .black
  .opacity(0.05), radius: 6, x: 0, y: 2)`(은은한 입체감), 테두리
  radius 14→18(더 둥글게), 세로 패딩을 늘려 여백에 숨 쉴 공간을 줬다.
- 상단 KRV 절 텍스트도 같은 `cardBorderColor`로 테두리를 맞추고, 카드
  radius를 16으로 통일.

### 2) 연필 아이콘 위치·크기 (2차례 조정)

1차: "한글 뜻 단어 오른쪽 옆에 배치, 조금더 진하고 크게" — 카드 우상단
구석(`ZStack` overlay, `.quaternary` 12pt)에서 한글 헤드라인과 같은
`HStack` 안으로 옮기고 `.secondary` 18pt `pencil.circle.fill`로.
2차: "사이즈를 14로, pencil.circle 로 변경" — 18pt 채움 아이콘을
14pt 테두리만 있는 `pencil.circle`로 축소.

### 3) biblehub.com 딥링크 2건

- **절 전체 인터리니어 링크**: 원문 정보 맨 위에 `Link(destination:) {
  Label("영문-원어성경", systemImage: "safari") }` — `https://biblehub.com/
  interlinear/{책슬러그}/{장}-{절}.htm`. `Link`가 시스템 기본 브라우저를
  직접 연다.
- **단어별 Strong 사전 링크**: 원어 텍스트 옆에 `safari` 아이콘 —
  `https://biblehub.com/hebrew|greek/{Strong숫자}.htm`(strong_code의
  "H"/"G" 접두와 0-padding을 뗀 순수 숫자).
- **책 슬러그 66개 하드코딩**: biblehub에 책/장/절을 조회하는 API가
  없어 URL 슬러그를 직접 확인해야 했다 — `web_fetch`로 `interlinear/
  genesis/1-1.htm`(일반), `interlinear/1_kings/1-1.htm`(숫자+밑줄
  패턴 확인), `interlinear/song_of_solomon/1-1.htm`(빈 응답 = 404로
  추정) → `interlinear/songs/1-1.htm`(아가서만 예외 슬러그, 성공)
  순서로 실제 요청해 규칙을 확정한 뒤 66권 표를 만들었다. Strong 링크
  형식도 `hebrew/430.htm`(창세기 1:1 "God")·`greek/2316.htm`(θεός)로
  직접 조회해 검증했다. ⚠️ 66권 중 실제로 fetch해 확인한 건 4권(창세기·
  열왕기상·아가서 정상/예외 패턴, 그리고 나머지는 동일 규칙 적용을
  신뢰)뿐이라, 혹시 또 다른 예외 슬러그가 있는 책이 있다면(가능성 낮음)
  그 책만 링크가 깨질 수 있다.

### 정적 검증

`OriginalTextInfoView.swift` 88/88·237/237·52/52. 이상 없음.

⚠️ Xcode 확인 필요: 이번에도 컴파일 환경이 없어 실제 렌더링(가운데 정렬이
의도대로 보이는지, 그림자·테두리가 라이트/다크 모드 둘 다 자연스러운지,
`Link`가 실제 기기에서 브라우저를 여는지)은 확인 못 했다.

## [2026-08-13, 이어서 53] "말씀 노트" 통합 메뉴 + "개요" 66권 리스트/기본값 시딩

사용자 요청 두 가지, 각각 별도 기능 라운드.

### 1. 왼쪽 사이드바 "개인 묵상" + "말씀 요약" → "말씀 노트" 통합

요청 문구: "왼쪽 사이드바 [개인 묵상], [말씀 요약] 통합할 것 : 메뉴명 - [말씀
노트] / 카테고리로 분류할 것 : [개인 묵상], [말씀 요약] / 리스트 항목 앞에
카테고리를 표시할 것 / 검색창 옆에 카테고리 picker."

`UserMemo`(개인 묵상)와 `VerseSummary`(말씀 요약)는 스키마가 다른(폴더/태그는
`UserMemo`에만 있음) 별개 모델이라 데이터 자체를 합치지 않았다. 대신:

- `Views/WordNote/WordNoteHomeView.swift`(신설) — `WordNoteItem`(`.memo`/
  `.summary` 케이스를 가진 얇은 열거형 래퍼)로 두 모델을 한 목록에 섞어
  보여준다. 정렬은 각 모델의 기존 규칙을 그대로 유지(개인 묵상=`updatedAt`
  내림차순, 말씀 요약=`createdAt` 내림차순 — 저널 성격)하고 병합 후 다시
  정렬한다. 검색창 옆에 `Picker(.menu)`로 "전체/개인 묵상/말씀 요약" 카테고리
  필터를 뒀다. 항목 실제 편집은 기존 `MemoDetailView`/`WordSummaryEditorView`를
  그대로 재사용(둘 다 성경 조회 화면의 "contextual" 진입 경로도 그대로 살아있다).
- `Views/WordNote/WordNoteRowView.swift`(신설) — 옛 `MemoRowView`/
  `WordSummaryHomeView.WordSummaryRowView`와 같은 원칙에 카테고리 배지(개인
  묵상=파란색, 말씀 요약=초록색)를 앞에 붙였다.
- 삭제: `Views/Memo/MemoHomeView.swift`, `Views/Memo/MemoRowView.swift`,
  `Views/WordSummary/WordSummaryHomeView.swift` — 전수 조사(Explore 서브에이전트)로
  이 세 파일을 참조하는 곳이 사이드바/탭바 4곳뿐임을 확인한 뒤 삭제했다(사용자가
  이 폴더의 파일 삭제 권한을 이번엔 승인 — 이전 라운드의 STEPBible 소스 파일
  삭제 거부와는 별개 건).
- `AppSection.swift` — `.memos`/`.wordSummary` 두 케이스를 `.wordNote`
  하나로 합쳤다(`title`="말씀 노트", `systemImage`="note.text").
  `phoneTabBarSections`도 갱신.
- `SidebarNavigationView.swift`/`PhoneTabView.swift` — 라우팅을
  `WordNoteHomeView()` 하나로 교체.
- `AppCommands.swift` — ⌘2("개인 묵상으로 이동")·⌘6("말씀 요약으로 이동") 두
  메뉴 항목을 ⌘2("말씀 노트로 이동") 하나로 합쳤다.
- ⚠️ [범위 축소, 명확히 플래그] 옛 `MemoHomeView`의 폴더별 목록 **필터** 메뉴는
  뺐다(요청이 카테고리 picker 하나만 명시). 폴더 배정 자체(`MemoDetailView`의
  폴더 메뉴)와 ⌘⇧N "새 폴더" 커맨드는 `WordNoteHomeView`가 그대로 이어받아
  계속 동작한다 — 새로 만든 폴더를 목록에서 필터링할 UI만 없어졌다.

### 2. "개요" 메뉴 — 66권 리스트 + 기본값(시드) 배포 구조

요청 세 가지 — (a) "[개요]를 클릭하면 성경 66권 총 1189장 리스트가 나오도록,"
(b) "내가 개요를 입력한 내용을 앱의 기본 DB에 넣되, 배포할 때는 사용자 DB로
복사해서 수정 가능하게," (c) "내가 개요를 입력할 수 있는 리치 에디터 페이지 —
배포할 때는 빼야 함."

**(a) 66권 리스트:** `Views/Outline/OutlineBookListView.swift`(신설, 66권 +
"N권 · 총 1189장" 헤더) → 탭하면 `OutlineChapterListView.swift`(신설, 그 책의
1~chapterCount장 리스트) → 장을 탭하면 기존 `OutlineView(initialBook:
initialChapter:)`(책/장 인자 새로 추가, nil이면 기존처럼 마지막 위치/창세기
1장으로 폴백)로 들어간다. `OutlineViewModel`은 이미 `initialBook`/
`initialChapter`를 받았어서 `OutlineView`만 그 값을 전달하도록 고쳤다.
`SidebarNavigationView`/`PhoneTabView`의 `.outline` 라우팅을
`OutlineBookListView()`로 교체 — `WindowGroup(id: "outline")`(성경 조회
사이드바 "개요 화면 열기" 버튼이 여는 별도 창)은 이 경로를 안 타서 영향 없음
(그 창은 여전히 `OutlineView(initialIsEditable: false)`로 곧장 연다).

**(b)+(c) 기본값 시딩:** `TranslationBootstrap.swift`(BibleDB.sqlite 번들
읽기전용 DB) 패턴을 `BookOutline`/`ChapterSummary`에 적용했다. 이 둘은 이미
메인 CloudKit 컨테이너 소속 `@Model`이라, "기본값 저장소"는 **같은 두 모델
타입을 쓰는 완전히 별개의 로컬 전용(비-CloudKit) `ModelContainer`**로
분리했다(SwiftData가 같은 모델을 여러 `ModelConfiguration`에 동시에 쓰는 걸
지원하는 공식 패턴 — `BookOutline`/`ChapterSummary`는 서로 관계가 없어 최소
스키마로 독립 가능).

- `Services/OutlineSeedStore.swift`(신설) — `makeAuthoringContainer()`(DEBUG
  전용, 앱 샌드박스 Application Support의 쓰기 가능 로컬 파일)와
  `makeBundledReadContainer()`(모든 빌드, 번들 `OutlineSeed.sqlite`를
  `allowsSave: false`로 읽기전용 오픈 — 웹 검색으로 `ModelConfiguration`의
  `allowsSave` 파라미터 실존을 확인한 뒤 사용).
- `Views/Outline/OutlineSeedEditorView.swift`(신설) — `OutlineView`와 같은
  UI(책/장 피커 + 리치 텍스트 에디터 2개)를 시드 컨테이너에 바인딩한 편집기.
  파일 전체를 `#if DEBUG`로 감쌌다 — 커스텀 컴파일 플래그를 새로 만드는 대신
  Xcode 표준 Debug/Release 구분(Release엔 `DEBUG`가 정의되지 않음)을 그대로
  써서 "배포 시 기능 제외"를 구현했다. 화면 하단에 저장 파일의 실제 경로를
  선택 가능한 텍스트로 보여주고(macOS는 "Finder에서 보기" 버튼도), 이 파일을
  Xcode Resources에 수동으로 복사+타겟 추가해야 한다고 명시했다(빌드
  파이프라인이 없어 이 한 단계는 불가피하게 수동).
- `Views/Settings/SettingsView.swift` — `#if DEBUG`로 감싼 "개발자" 탭
  (`DeveloperSettingsTab`) 하나 추가, 시트로 `OutlineSeedEditorView`를 연다.
  탭 자체가 조건부 컴파일이라 배포 빌드에는 탭 목록에도 나타나지 않는다.
- `Services/OutlineSeedImporter.swift`(신설) — 앱 시작 시(`ContentView.task`,
  `TranslationBootstrap.ensureBundledTranslationRegistered` 바로 다음)
  번들 `OutlineSeed.sqlite`가 있으면 그 안의 책/장 개요를 사용자 DB로
  복사한다. 사용자가 이미 채운(비어 있지 않은) 항목은 절대 덮어쓰지 않고,
  `UserSettingsStore.hasImportedOutlineSeed` 플래그로 딱 한 번만 실행한다.
  ⚠️ [정책 트레이드오프, 명확히 플래그] 이 플래그가 이미 true인 기존
  사용자는, 개발자가 나중에 번들에 시드 파일을 처음 추가하는 버전
  업데이트에서 시드를 받지 못한다 — 버전별 재실행이 필요해지면 플래그를
  앱 버전 문자열과 묶는 후속 작업이 필요하다(지금은 범위 밖).

### 정적 검증

새/수정 파일 전부 괄호(`()`) 개수를 스크립트로 셌다 — `WordNoteHomeView.swift`
154/154, `WordNoteRowView.swift` 54/54, `AppSection.swift` 11/11,
`SidebarNavigationView.swift` 75/75, `PhoneTabView.swift` 26/26,
`AppCommands.swift` 82/82, `OutlineSeedStore.swift` 31/31,
`OutlineSeedImporter.swift` 25/25, `OutlineSeedEditorView.swift` 85/85,
`OutlineBookListView.swift` 17/17, `OutlineChapterListView.swift` 10/10,
`OutlineView.swift` 193/193, `ContentView.swift` 21/21 — 전부 균형. 중괄호
(`{}`)도 전부 균형. `UserSettingsStore.swift`/`SettingsView.swift`는 파일
전체 괄호 카운트가 각각 3개 어긋나는데, 두 파일 다 수천 줄짜리 기존 파일이라
한글 서술 주석 안의 짝 없는 괄호(예시 표기 등) 때문으로 보이며, 내가 실제로
수정한 줄들은 전부 그 줄 안에서 괄호가 닫혀 있음을 개별 확인했다 — 내가
새로 깬 균형은 아니라고 판단한다(그래도 Xcode에서 최종 확인 필요).

⚠️ Xcode 확인 필요(이번에도 컴파일 환경 없음): `WordNoteHomeView`의 macOS/
iPadOS 분할 뷰·iPhone 목록 전환, 카테고리 picker 렌더링, `OutlineSeedEditorView`의
`ModelContainer(for:configurations:)` 독립 컨테이너 생성이 실제로 성공하는지
(문서상 지원되는 패턴이지만 실기기 검증은 못 했다), `allowsSave: false`
읽기전용 컨테이너가 실제 SwiftData 버전에서 기대대로 동작하는지, `#if DEBUG`가
프로젝트의 Release 빌드 설정에서 실제로 정의되지 않는지(표준 Xcode 기본값이지만
이 프로젝트가 커스텀 빌드 설정을 쓰고 있었다면 다를 수 있음).

## [2026-08-14, 이어서 54] 에디터 공통 스타일/태그, 개요 시딩 재설계(JSON), 개요 트리 전면 재구축

이어서 53에서 만든 것들에 대한 후속 피드백 라운드 — 상당수가 "설계 자체를
다시 짜라"는 요청이었다.

### 1. 모든 에디터 공통 기본 스타일

요청: "페이퍼로지 3라이트 14pt / 글자색 #2B2B2F / 배경색 #F5F1E8 / 줄간격
2.0. 모양 설정은 순수 성경조회 본문/성경구절에만 적용."

- `Services/EditorDefaultStyle.swift`(신설) — 위 네 값의 단일 출처.
  `RichTextEditor`에 없던 "새로 입력하는 글자의 기본 글자색" 파라미터
  (`defaultTextColor`)가 아예 없었다 — `typingFont`/`lineHeightMultiple`과
  같은 원칙으로 iOS/macOS 양쪽 `RichTextEditorRepresentable`의
  `typingAttributes`에 추가했다(`Views/Memo/RichTextEditor.swift`).
- `MemoDetailView`/`WordSummaryEditorView`/`OutlineSeedEditorView`(이후
  4절에서 삭제)의 모든 `RichTextEditor(...)` 호출부를 이 값으로 통일 —
  `.standalone`/`.contextual` 구분에 따라 서식이 달랐던 옛 로직(글꼴/줄간격/
  배경 전부)을 걷어냈다.
- **배경색 불일치 버그 수정**: 사용자 보고 — "글을 클릭했을 때 에디터 배경은
  흰색으로... 눈동자 버튼으로 조회/편집 모드를 바꾸면 그때부터 그 배경으로
  고정되는 것처럼, 처음 열었을 때부터 그 배경이어야." 원인은
  `editingBackgroundColor`/`readOnlyBackgroundColor` 두 값이 서로 달랐던
  것(`MemoDetailView` `.standalone`은 편집=nil/조회=흰색, `.contextual`은
  편집=흰색/조회=시스템 배경 — 조합이 화면마다 제각각이었다). 두 값을 완전히
  같은 상수(`EditorDefaultStyle.backgroundColor`)로 고정해 모드 전환 여부와
  무관하게 항상 같은 배경이 보이도록 구조적으로 해결했다.
- `UserSettingsStore`의 "모양" 탭 값(`bibleBodyFont` 등)은 `TranslationColumnView`
  (성경 본문)/`OriginalTextInfoView`(원문 정보 상단 KRV 구절)에서만 쓰이는지
  전체 재확인 — 이미 그 두 곳뿐이었다(추가 조치 불필요, 사용자 확인 요청에
  대한 답으로 그대로 유지).

### 2. UI 크롬 텍스트 시스템 기본 글꼴

`WordNoteHomeView`의 카테고리 `Picker` 라벨에 `.font(.body)` 명시(그 전엔
`RootView.appDefaultFont()`가 강제하는 내장 Paperlogy를 그대로 물려받고
있었다). 같은 원칙으로 이번에 새로 만든 `OutlineBookListView`/
`OutlineChapterListView`(4절에서 다시 트리로 교체됨)의 책/장 라벨,
`WordNoteHomeView`의 "새 항목" 메뉴 버튼에도 명시적으로 적용했다. 기존
화면들(`.headline`/`.caption` 등 이미 명시적 폰트가 있던 곳)은 원래도
시스템 폰트였다는 걸 재확인만 했다(`.font(_:)`를 명시하면 상위
`appDefaultFont()`보다 항상 우선한다).

### 3. 말씀 노트 — 개인 묵상 작성일자 + 말씀 요약 태그

- `WordNoteRowView.dateLabel` — 말씀 요약만 보여주던 날짜를 개인 묵상에도
  추가(개인 묵상은 `updatedAt`, 말씀 요약은 기존대로 `createdAt`).
- **`SummaryTag` 신설** — `VerseSummary`에 `MemoTag`와 동격인 새 조인 모델을
  추가했다(`Tags.swift`). `UserMemo`/`VerseSummary`가 서로 다른 모델이라
  `MemoTag`를 그대로 재사용할 수 없었다 — `Tag.summaryTags` 관계, `Tag`
  스키마 등록(`BibleResearchSchema.modelTypes`), `TagDeduplication.
  reassignRelationships`에 SummaryTag 병합 로직 추가까지 `MemoTag`와 완전히
  같은 패턴으로 맞췄다. `WordSummaryEditorView`에 `MemoDetailView.tagSection`과
  동일한 태그 입력/표시/자동완성 UI를 이식했다 — 공유 컴포넌트
  `FlowLayoutHStack`을 `MemoDetailView.swift`의 `private struct`에서
  `Views/Memo/FlowLayoutHStack.swift`(공개) 파일로 분리해 두 화면이 같이
  쓴다. 태그 추천 빈도수는 `memoTags`+`summaryTags` 합산으로 계산(한 태그가
  양쪽에서 쓰일 수 있으므로).

### 4. 개요 시딩 — SQLite 2중 컨테이너 → JSON으로 재설계

사용자 질문 — "번들 DB에 넣고 자동 복사되는 자동화가 안 되는 건가?" 재확인
결과, 자동 복사 자체(`OutlineSeedImporter`, 1회만 실행·이후 사용자가 채운
내용은 절대 덮어쓰지 않음)는 이미 정확히 요청대로 동작하고 있었다 — 혼동의
원인은 "Xcode에 리소스로 등록하는 것"이 정확히 뭘 뜻하는지였다.

재설계하며 원래 방식(로컬 전용 SwiftData 컨테이너 + DEBUG 전용 리치
에디터로 시드 콘텐츠를 작성)을 버리고 **평범한 JSON 배열**로 바꿨다:
- 이유: 이전 방식은 내가(Claude, Xcode 없이) 유효한 SwiftData/CoreData
  저장 파일을 직접 만들어 줄 수 없어 개발자가 반드시 앱을 한 번 실행해
  DEBUG 화면에서 타이핑해야 했다. JSON은 내가 이 대화에서 텍스트를 받으면
  그 자리에서 바로 `Resources/OutlineSeed.json`에 써 줄 수 있다 — 별도
  앱 편집 화면 자체가 필요 없어진다.
- 삭제: `Services/OutlineSeedStore.swift`, `Views/Outline/OutlineSeedEditorView.swift`,
  `SettingsView`의 "개발자" 탭(`#if DEBUG`).
- 재작성: `Services/OutlineSeedImporter.swift` — `OutlineSeedEntry
  { bookId, chapter: Int?, text: String }` 배열을 `Bundle.main`에서 JSON으로
  직접 디코딩한다. `chapter == nil`이면 `BookOutline`, 있으면
  `ChapterSummary`. `text`를 `contentHtml`/`contentText` 양쪽에 그대로
  넣는다 — `RichTextCodec.decode`가 "`{\rtf1`로 시작하지 않으면 평범한
  텍스트로 취급"하는 기존 규칙을 그대로 타서 문제없이 표시되고, 사용자가
  한 글자라도 고쳐 저장하면 자연스럽게 RTF로 승격된다.
- **남은 수동 단계는 정확히 하나**: `OutlineSeed.json` 파일을 Xcode
  프로젝트의 Copy Bundle Resources에 등록하는 것(BibleDB.sqlite/
  OriginalText.sqlite/books.json도 전부 거쳐야 했던 절차와 동일 — Xcode
  프로젝트라면 예외 없이 필요하다). 그 한 번만 하면, 그 다음부터는 사용자가
  요청한 그대로("자동 복사, 이후 절대 덮어쓰지 않음")가 전부 자동이다.
  이 파일은 아직 만들지 않았다 — 콘텐츠(어느 책/장에 어떤 기본 개요를 넣을지)
  를 받으면 바로 써 줄 수 있다.

### 5. 개요 — 폴더 트리 전면 재구축

요청: "구약 > 창세기 > 1장,2장.. / 신약 > 마태복음 > ... 폴더 구조, 펼침
상태 유지, 책 자체를 눌러 일괄편집(장별 접기/펼치기) 또는 특정 장만 수정,
에디터는 트리 오른쪽에."

이어서 53에서 만든 "66권 평면 리스트 → 장 리스트 → 편집기"(3단 push
내비게이션) 전체를 폐기하고 새로 짰다.

- 삭제: `OutlineView.swift`, `OutlineViewModel.swift`,
  `OutlineBookListView.swift`, `OutlineChapterListView.swift`.
- 신설 `Views/Outline/OutlineTreeView.swift` — 구약/신약 → 책 → 장 3단
  트리. `DisclosureGroup`의 "행 전체를 누르면 펼침/접힘" 기본 동작이 "책
  이름을 누르면 그 책을 선택"과 충돌해(둘 다 "행 탭"을 원함) 표준 컴포넌트
  대신, 펼침 상태에 따라 보여야 할 행을 매번 평면 배열로 계산해(`rows`)
  직접 그린다 — 화살표 아이콘 버튼(펼침/접힘 전용)과 이름 텍스트(선택 전용)
  탭 영역을 분리했다. macOS/iPadOS는 트리|편집기 분할 뷰, iPhone은
  트리 → push 내비게이션(다른 목록 화면들과 같은 관례).
- 펼침 상태 영구 저장: `UserSettingsStore.outlineExpandedTestaments`/
  `outlineExpandedBookIds`(UserDefaults) — 앱을 껐다 켜도 유지된다(사용자
  요청 그대로). 기본값은 구약만 펼친 채 시작.
- 신설 `Views/Outline/OutlineBookBulkEditView.swift` — 책을 선택하면
  `focusedChapter: nil`(전부 접힌 채 시작, "모두 펼치기" 버튼으로 일괄
  가능), 장을 선택하면 `focusedChapter: 그 장`(그 장만 펼쳐진 채 시작,
  `ScrollViewReader`로 그 위치까지 자동 스크롤) — 같은 화면 하나가 "일괄
  편집"과 "장 하나만 수정" 요구를 함께 만족한다. 장마다 개별 접기/펼치기
  가능(눌러서 토글). 접힌 장은 `RichTextEditor`(실제 UITextView/NSTextView)
  자체를 그리지 않아 기본 상태는 가볍다.
- `WindowGroup(id: "outline")`(성경 조회 사이드바 "개요 화면 열기" 별도 창)도
  `OutlineBookBulkEditView(book:focusedChapter:initialIsEditable:false)`로
  교체 — 기존처럼 마지막 위치의 책/장으로 곧바로(트리를 거치지 않고) 조회모드로 연다.

⚠️ [범위 축소, 명확히 플래그] 옛 `OutlineView`의 AI 초안 제안(9.9절,
`ChapterOutlineDraftService`)과 `BookOutline` 충돌 배너(다른 기기가 오프라인
중 같은 책 개요를 따로 만든 경우)는 이번 트리 재설계에 포함하지 않았다 —
이번 요청 범위에 없었고, 아코디언 구조에 자연스럽게 녹이려면 추가 설계가
필요해 별도 요청 없이 넣지 않았다. 필요해지면 다음 라운드에.

### 정적 검증

새/수정 파일 전부 괄호·중괄호 스크립트로 재확인 — 전부 균형. `RichTextEditor.swift`/
`OutlineSeedImporter.swift`(신설)에서 발견된 사소한 불일치는 전부 코드가
아니라 주석 안의 `` `{\rtf1` ``(RTF 포맷 시그니처를 설명하는 문구) 때문임을
`python3`으로 괄호 깊이를 직접 추적해 확인했다 — 실제 구조적 문제 없음.
`UserSettingsStore.swift`/`SettingsView.swift`의 괄호 3개 불일치는 이어서
53 때부터 있던 것과 같은 원인(한글 주석의 번호 매기기 "1)"/"2)" 표기가
짝 없는 닫는 괄호를 만든다)임을 `awk`로 라인별 추적해 확인했다.

⚠️ Xcode 확인 필요(여전히 컴파일 환경 없음): `OutlineTreeView`의 커스텀
탭 영역 분리(화살표 버튼 vs 이름 텍스트)가 실제로 서로 간섭 없이 동작하는지,
`OutlineBookBulkEditView`에서 큰 책(시편 150장)을 "모두 펼치기" 했을 때
실사용 성능, `ScrollViewReader.scrollTo`가 `List` 렌더링 타이밍과 실제로
잘 맞는지, `SummaryTag` 관계 CloudKit 스키마가 실기기에서 정상적으로
동기화되는지.

## [2026-08-14, 이어서 55] 개요 시딩 JSON — 사용자가 직접 편집할 수 있게 사람 친화적으로 2차 재설계

사용자 질문 — "개요 시딩을 내가 DB에 직접 수정할 수 있는 방법은 없는가?"

4절(이어서 54)의 JSON 설계는 이미 사람이 텍스트 편집기로 직접 열어 고칠 수
있는 형식이었지만, 두 가지가 "직접 편집"에 불편했다:
1. 항목을 숫자 `bookId`(예: 1=창세기)로 식별해야 했다 — 66권 번호를 외우지
   않는 한 직접 고치기 어렵다.
2. `JSONDecoder.decode([OutlineSeedEntry].self, ...)`로 배열 전체를 한 번에
   디코딩했다 — 사람이 손으로 고치다 항목 하나에 오타를 내면(따옴표 하나
   빠뜨리는 등) **배열 전체**가 통째로 실패해 시딩이 하나도 안 먹힌다.

`Services/OutlineSeedImporter.swift`를 다시 고쳤다:
- 식별자를 `bookId`(숫자) → `book`(한글 책 이름, `books.json`의 `nameKo`와
  정확히 같은 문자열, 예: "창세기")로 바꿨다. `resolveBook(named:)`가
  `BooksProvider`에서 정확한 이름을 먼저 찾고, 없으면 약칭 목록에서도
  찾는다 — 그래도 못 찾으면 그 항목만 건너뛰고 어떤 이름이 문제인지
  콘솔에 정확히 남긴다(다른 항목엔 영향 없음).
- 파싱 방식을 `JSONDecoder`(전체 아니면 전무) → `JSONSerialization`(항목별
  개별 파싱)으로 바꿨다 — 이제 항목 하나가 잘못돼도 그 항목만 건너뛰고
  (콘솔에 사유를 남기고) 나머지는 정상 적용된다. 사람이 직접 편집하는
  파일이라는 전제에 맞춘 변경이다.
- `Resources/OutlineSeed.json`을 실제로 만들었다(창세기 책 개요 + 창세기
  1장 개요, 두 항목 모두 "여기에 ~ 입력하세요" 플레이스홀더 텍스트) — 사용자가
  바로 열어서 이 두 항목을 지우거나 고치고, 같은 형식으로 항목을 계속
  추가하면 된다. 파일 상단(`OutlineSeedImporter.swift`)에 정확한 형식/예시/
  주의사항(테스트하려면 앱 삭제 후 재설치 필요 — 플래그가 기기당 1회이므로)을
  전부 문서화했다.
- 여전히 남는 유일한 수동 단계: 이 JSON 파일을 Xcode Copy Bundle Resources에
  최초 1회 등록하는 것(이어서 54 4절과 동일 — 파일 경로가 같은 한 다시 할
  필요 없다).

### 정적 검증

`OutlineSeed.json`을 `python3 -c "json.load(...)"`로 실제 파싱해 유효한
JSON임을 확인했다. `OutlineSeedImporter.swift`는 괄호/중괄호 균형 스크립트로
재확인 — 이상 없음(이전과 같이 `` `{\rtf1` `` 주석 문구로 인한 1개 중괄호
"불일치"는 실제 코드 문제가 아님을 재확인).

## 이어서 56 (2026-08-14)

### 사용자 지적 — "왜 개요 시딩을 마음대로 json 파일 방식으로 바꿨지?"

사용자: "왜 개요 시딩을 마음대로 json 파일 방식으로 바꿨지? 나는 리치 에디터
스타일을 먹이면서 개요를 작성하기를 원하는데, 그래서 내가 임시 별도페이지를
만들어달라고 하지 않았나?"

정확한 지적이다. "이어서 55"에서 "개요 시딩을 내가 DB에 직접 수정할 수 있는
방법은 없는가?"라는 질문을 "리치 에디터 없이 평문 텍스트 파일을 직접 고치고
싶다"로 잘못 해석해, 애초에 만들어 뒀던 리치 에디터 임시 페이지
(`OutlineSeedEditorView`, 개발자 탭)를 지우고 평문 JSON 방식으로 바꿔버렸다 —
서식(글꼴/색/줄간격)이 다 날아가는 잘못된 방향 전환이었다.

### 바로잡은 이해

다시 보니 `Views/Outline/OutlineBookBulkEditView.swift`(이어서 55에서 만든
폴더 트리 개편의 오른쪽 편집 화면)가 이미 `RichTextEditor` +
`EditorDefaultStyle`으로 완전한 서식 편집을 지원하는 **실제 프로덕션 화면**
이다 — 개발자(박윤기)가 DEBUG 빌드에서 사이드바 "개요" 메뉴로 들어가 평소
사용자가 쓸 그 화면 그대로 서식을 넣어 작성하면 된다. 새 에디터를 또 만들
필요가 없었다. 진짜 필요했던 건 그렇게 자신의 로컬 DB(`BookOutline`/
`ChapterSummary`, 내용은 이미 RTF)에 쌓인 결과를, 배포용 시드 파일로 뽑아내는
"내보내기" 한 가지뿐이었다.

### 변경 사항

- `Services/OutlineSeedExporter.swift`(신설, `#if DEBUG` 전체 감쌈) —
  `exportSeedJSON(context:)`가 내용이 있는 `BookOutline`/`ChapterSummary`를
  모아 `OutlineSeed.json`과 같은 배열 포맷(`book`/`chapter`/`text`)으로
  내보낸다. `text`에는 `contentHtml`(실제로는 RTF 문자열)을 그대로 옮긴다 —
  JSON 문자열은 원래 임의의 유니코드 텍스트를 담을 수 있어 RTF의 `{`/`}`/`\`
  제어 문자도 `JSONSerialization`이 자동으로 안전하게 이스케이프한다(별도
  base64 인코딩 불필요).
- `Views/Settings/SettingsView.swift` — "개발자" 탭을 `#if DEBUG`로 복원.
  `OutlineSeedExporter`를 호출해 `.fileExporter`(표준 저장 대화상자)로 JSON을
  내보내는 버튼 하나(+ 내보낸 책/장 개수 표시)만 넣었다 — 새 리치 에디터 UI를
  다시 만들지 않았다(위 "바로잡은 이해" 참고, 그럴 필요가 없다).
  `OutlineSeedJSONDocument`(최소 `FileDocument` 래퍼)도 같은 파일에 `#if
  DEBUG`로 추가했다.
- `Services/OutlineSeedImporter.swift` — 파일 상단 주석을 정정했다. "권장
  워크플로"를 리치 에디터(개요 화면) + 내보내기로 명시하고, 예전에 기본값처럼
  설명했던 "텍스트 편집기로 직접 JSON을 고치는 방법"은 서식이 필요 없는 짧은
  항목용 **보조 수단**으로 격하했다. 실제 파싱 로직(`importIfNeeded`)은 바꾸지
  않았다 — `RichTextCodec.decode`가 `{\rtf1` 접두사로 RTF/평문을 이미 자동
  판별하므로, 내보내기가 만든 RTF 항목과 사람이 손으로 쓴 평문 항목이 같은
  배열에 섞여 있어도 각각 올바르게 처리된다.

### 정적 검증

네 파일(`OutlineSeedExporter.swift`, `SettingsView.swift`,
`OutlineSeedImporter.swift`, `OutlineTreeView.swift`) 모두 괄호/중괄호 균형
스크립트(문자열·주석 인식 포함)로 재확인 — 전부 `final depth: 0`, 이상 없음.
`OutlineTreeView.swift`의 `Testament`(중첩 타입, 정확히는 `Book.Testament`)
관련 컴파일 에러 4건(사용자가 실제 Xcode 빌드에서 보고)도 같은 턴에 전부
`Book.Testament`로 고쳤다 — 코드베이스 전수 grep으로 다른 파일에는 같은
실수가 없음을 확인.

## 이어서 57 (2026-08-14)

### 사용자 요청 — "번들로 제공되는 개역한글에 문단정보를 추가"

사용자가 `BibleVerses.json`(31,102개 절, `book_id`/`chapter`/`paragraph`/`uid`/
`verse`)을 첨부하며 "첨부파일 내 paragraph 항목을 넣고, 개역한글 성경 조회
본문의 해당하는 절 앞에 문단 표시를 넣을 것"을 요청했다.

### 조사 결과 — DB 작업은 이미 끝나 있었다

`Resources/BibleDB.sqlite`(`BibleVerses` 테이블)를 열어 확인해보니, `paragraph`
컬럼이 이미 존재하고(스키마 자체는 전부터 있었다 — `BibleReferenceStore.swift`
상단 주석/`BibleVerse.paragraph: Int?` 참고) 값도 이미 채워져 있었다. 첨부
JSON과 uid 기준으로 31,102개 전부 1:1 대조한 결과 **완전히 일치**(같음
31,102 / 다름 0 / 누락 0) — 즉 DB에 문단 정보를 새로 넣는 작업 자체는 이미
완료된 상태였다(언제 채워졌는지는 이번 세션 기록에 없음, 아마 원본 sqlite
파일 자체에 처음부터 포함돼 있었던 것으로 보인다).

### 실제로 빠져 있던 것 — 화면 표시

DB에 데이터는 있었지만 `.paragraph` 필드를 실제로 읽어 쓰는 화면 코드가
어디에도 없었다(전수 grep 결과 0건) — 그래서 사용자에게 문단 구분이 안
보였던 것이다. `Views/Bible/TranslationColumnView.swift`의 `VerseRow`(성경
조회 S1 화면, 절 번호를 그리는 부분)를 고쳐, `verse.paragraph != nil`이면
절 번호 앞에 문단표(¶)를 붙이도록 했다 — 인쇄본 성경의 관례를 그대로
따름. 번호 칸과 같은 줄에 이어 붙여서(별도 줄로 쌓지 않음) 옆 본문
텍스트와의 세로 정렬(`HStack(alignment: .top)`)이 흐트러지지 않게 했다.
`paragraph` 컬럼이 없는 사용자 추가 번역본(`Bible` 스키마)은 항상 nil이라
자동으로 문단표가 안 보인다 — "개역한글에만" 적용하라는 요청 범위와 정확히
일치한다(번역본 파일 종류로 분기하는 별도 코드 없이, 컬럼 존재 여부라는
기존 메커니즘이 자연스럽게 그 범위를 만들어 준다).

화면상 절 목록을 그리는 다른 경로(BibleReadingView의 컬럼들)는 전부 이
`TranslationColumnView.VerseRow` 하나를 공유해서 그리므로 별도 수정이 필요
없었다. 확대보기(`VerseZoomView`/`AnnotatedVerseFlowView`)는 절 하나만
확대해서 보여주는 별개 화면이라 "여러 절 사이 문단 구분"이라는 이번 요청의
성격과 맞지 않아 범위에서 제외했다.

### 정적 검증

`TranslationColumnView.swift` 괄호/중괄호 균형 스크립트 재확인 — `final
depth: 0`, 이상 없음.

### 이어서 57 정정 — "구절 번호 앞이 아니라, 절 텍스트 맨 앞으로, ¶가 아니라 ●"

사용자 재요청으로 문단 표시 위치/기호를 바로잡았다: 절 번호 옆(¶) → 절 텍스트
맨 앞(●). `TranslationColumnView.VerseRow.verseContentText`를 고쳐 절 번호
쪽 변경은 되돌리고, 대신 `verse.paragraph != nil`이면 절 본문 맨 앞에 별도
`Text("● ")`를 `+`로 이어 붙였다. `VerseAnnotationRenderer.attributedContent`에
넘기는 원본 `verse.content` 문자열 자체는 건드리지 않았다 — 형광펜/구절별
메모의 `rangeStart`/`rangeEnd`가 그 원본 문자열의 UTF-16 오프셋 기준으로 DB에
저장돼 있어서, 문자열 앞에 마커를 끼워 넣으면 오프셋이 밀려 형광펜/메모가
엉뚱한 위치에 표시되는 회귀가 생기기 때문이다(`Text + Text` 연결로 오프셋을
전혀 건드리지 않고 시각적으로만 앞에 붙였다).

정적 검증: `TranslationColumnView.swift` 괄호 균형 재확인 — `final depth: 0`.

## 이어서 58 (2026-08-14)

### 사용자 요청 — "기본 관주 정보도 시딩하기를 원함"

사용자가 `output.json`(28,380건, `book_id`/`chapter`/`verse`/`content` — content는
"시 8:3, 시 33:6, ..." 형식의 콤마 구분 관주 목록)을 첨부하며 관주 시딩을
요청했고, 동시에 "이 관주정보도 저작권에 걸리는가?"를 물었다.

### 저작권 조사

대한성서공회 공식 사이트("성경의 저작권" 페이지, bskorea.or.kr)를 확인한
결과, 대한성서공회가 저작권을 소유한 한글 성경 목록에 「관주성경전서
개역한글판」(1962년 5월 10일 최초 발행)이 별도 항목으로 있고, "2012년 12월
31일 저작재산권 보호기간 소멸"로 명시돼 있었다 — 즉 그 판본이 맞다면 저작권료
없이 사용 가능하다(단 성명표시권/동일성유지권 등 인격권은 계속 준수 필요).
반면 「개정 관주성경전서 개역개정판」(2002)/「관주성경전서 국한문
개역개정판」(2009) 등은 소멸 날짜가 없어 아직 보호기간 안에 있다.

첨부 데이터가 정확히 어느 판본에서 왔는지는 사용자도 몰랐다("정확히
모르겠습니다"). 좌표 체계를 이 프로젝트의 개역한글 DB(`BibleDB.sqlite`)와
대조해보니 28,380건 중 28,352건(99.9%)이 일치했고, 개역개정에서 빠지는 대표
이문 구절(롬16:24, 행8:37, 마17:21/18:11/23:14, 요일5:7)이 전부 개역한글과
같은 좌표에 남아 있어 "개역개정이 아니라 개역한글 판본 체계"라는 정황
증거는 확보했다 — 하지만 이것만으로 1962년판 관주 출처임을 증명하지는
못한다. 사용자에게 이 사실을 전달하고 "지금 구현 vs 대한성서공회 확인 후
구현" 중 선택을 물었고, 처음엔 "확인 후 진행(권장)"을 골랐다가, 곧이어
"우선 넣어보고, 책을 보면서 확인을 하고자 함"으로 방향을 바꿨다 — 사용자의
최종 결정에 따라 지금 구현한다.

### 구현

- `Resources/CrossReferenceSeed.json`(신설) — 첨부 `output.json`을 그대로
  복사. 사전 검증: `content` 필드의 관주 토큰 184,705개 전부 "책약어 장:절"
  형식과 일치했고, 그 책약어 전부가 `books.json`의 `abbreviation` 목록과
  정확히 매칭됨을 확인(파싱 실패/미상 책약어 0건).
- `Services/CrossReferenceSeedImporter.swift`(신설) — `OutlineSeedImporter`와
  같은 1회성 "번들 → 사용자 DB 복사" 패턴. `content` 문자열을 정규식
  (`^([가-힣]+)\s*(\d+):(\d+)$`)으로 토큰화해 책약어 → `bookId`로 바꾸고,
  `VerseCrossReference(translationCode: "KRV", ..., source: .bundled, targets:)`
  로 저장한다. 항목/토큰 단위로 개별 파싱해 하나가 잘못돼도 나머지는 정상
  적용된다(`OutlineSeedImporter`와 동일 원칙). 1,000건마다 중간
  `context.save()`로 트랜잭션 크기를 줄였다 — 다만 CloudKit으로 나가는 총
  데이터양 자체는 줄지 않아, 오늘 이미 겪은 "Request Rate Limited" 문제가
  재발할 수 있음을 주석으로 남겼다.
- `Services/UserSettingsStore.swift` — `hasImportedCrossReferenceSeed` 플래그
  추가(`hasImportedOutlineSeed`와 동일 패턴).
- `ContentView.swift` — `.task` 블록에 `CrossReferenceSeedImporter.importIfNeeded`
  호출 추가.
- `Views/Settings/SettingsView.swift`(`AboutSettingsTab`) — "오픈소스 라이선스
  고지" 섹션에 관주 데이터 출처가 아직 확인 중이라는 문구를 추가해, 사용자
  본인 외의 최종 사용자에게도 투명하게 알리도록 했다.

⚠️ 이 시딩은 "우선 넣어보고 책과 대조 확인"하는 단계다 — 대한성서공회
확인(kbscopyright@bskorea.or.kr) 전까지는 배포용으로 확정된 상태가 아니다.

### 정적 검증

`CrossReferenceSeedImporter.swift`/`UserSettingsStore.swift`/`ContentView.swift`/
`SettingsView.swift` 괄호·중괄호 균형 스크립트 재확인 — 전부 `final depth: 0`,
이상 없음.

Sources:
- [성경의 저작권](https://www.bskorea.or.kr/bbs/content.php?co_id=subpage2_3_4_1)
- [『성경전서 개역한글판』은 저작권 사용허가없이 사용 가능한가요?](https://www.bskorea.or.kr/bbs/board.php?bo_table=copyright_faq&wr_id=5)

## 이어서 60 (2026-08-14)

**국한문 개별 한자 훈음(訓音) 사전 — 데이터만 구축, 화면 연동은 보류**

사용자 요청: 국한문/개역한글 통합 여부(별도 번들 번역본 유지 vs. 절별
인라인 한자 주석으로 전환)는 "아직 결정 보류". 대신 한자 훈음 사전은
"예, 함께 구축(권장)"으로 먼저 진행 승인받음. 원본(`BibleDB_Hanja.bdb`)에서
정규식으로 뽑아낸 고유 한자 2,002자 전체에 대해 음(音)·훈(訓)을 정리했다.
화면에 어떻게 붙일지는 위 아키텍처 결정이 나야 정해지므로, 이번 산출물은
`Resources/HanjaDictionary.json` 데이터 파일까지만 — 앱 코드에는 아직 연결
하지 않았다.

**음(音) — 기계적 추출**
- 파이썬 `hanja` 패키지의 내부 테이블(`hanja.table.hanja_table`, 27,497자
  수록)에서 2,002자 전량의 한국어 독음을 그대로 가져옴. 결측 0건.
- 과정에서 정규식 버그 발견 및 수정: 애초에 한자 범위를 `豈-﫿`(글리프
  기준으로 입력)로 썼는데, 실제 코드포인트는 U+8C48–U+FAFF라 한글 음절
  전체(U+AC00–D7A3)까지 실수로 포함하고 있었다. `豈-﫿`로 명시적
  코드포인트를 써서 재작성 — 그 결과 원래의 정상 고유 한자 수(2,002자)로
  복귀(잘못된 버전은 "성루" 안의 "루", "(셀라)" 안의 "셀"/"라" 같은 한글이
  한자로 잘못 집계되어 2,005자로 부풀어 있었음).

**훈(訓, 뜻) — 사용자 요청대로 Claude가 학습 지식으로 직접 정리**
- unicode.org 공식 Unihan 데이터를 이 샌드박스에서 받아보려 시도했으나
  실패(unicode.org, raw.githubusercontent.com 모두 차단, pypi.org만 허용).
  `pip download unihan-etl`로도 확인해봤지만 그 패키지가 번들한 데이터는
  실행 시점에 unicode.org에서 내려받는 라이브러리 코드일 뿐, 오프라인
  데이터가 아니었다(포함된 샘플은 176자짜리 테스트 픽스처). 이 사실을
  사용자에게 알리고 세 가지 선택지(① 사용자가 Unihan.zip 직접 업로드 ②
  Claude 학습 지식으로 전체 정리 ③ 상위 500자만 우선)를 물었고, 사용자가
  "②"를 선택.
- 빈도 분석: 전체 출현 기준 상위 500자가 88.1%, 800자가 95.3%, 2,002자
  전체가 100% 커버. 상위 800자(고빈도 상용한자 위주)는 `confidence: high`,
  나머지 1,202자는 `confidence: medium`으로 표시. 그중에서도 원저작·자전
  확인 없이는 정확도를 자신하기 어려운 희귀·특수 한자 15자(蓚·枋·簧·蔯·
  什·瀁·鞠·鮎·价·艀·祇·汾·瀋·芸·洸)는 `confidence: review`로 별도
  표시 — 사용자 검수를 권장.
- 음·훈 정합성 자동 검증(훈 문자열 끝 음절이 eum 필드와 일치하는지) 과정에서
  다음자(破音字) 불일치 3건 발견 → 실제 성경 본문 문맥을 직접 대조해 수정:
  - `怒`: `hanja` 패키지가 드문 이표 "로"를 반환했으나, 본문에서는 전부
    "노(怒)"·"분노(憤怒)"로 쓰여 "노"로 정정.
  - `更`: "다시 갱"으로 잘못 짝지었던 것을, 본문 용례("이경/삼경/경점" 등
    밤 시각 단위)에 맞는 음 "경"에 맞춰 훈을 "고칠 경"으로 정정.
  - `什`: 패키지 기본 음 "십" 대신, 유일한 용례인 "가장집물(家藏什物)"
    문맥에 맞는 음 "집"으로 정정(훈 "세간 집"은 원래도 맞았음).

**산출물**
- `Resources/HanjaDictionary.json`(신설) — `[{char, eum, hun, count,
  confidence}]` 2,002건. `count`는 전체 성경 본문에서의 출현 빈도(우선순위
  참고용).
- ⚠️ 앱 화면/모델에는 아직 연결하지 않음. 인라인 주석 렌더링(탭하면 상세
  팝오버) 방식으로 붙이는 안을 이전에 제안했었는데, 그 적용 여부는 국한문
  아키텍처 결정("보류" 상태)이 먼저 나야 진행 가능.

## 이어서 59 (2026-08-14)

### 사용자 요청 — "개역한글 국한문혼용과, 개역한글 난외주 정보가 있음. 저작권에
위배되는지 확인하고, 이를 현재 시스템에 보완할 수 있는 방법을 제안할 것."

사용자가 `02개역국한문.bdb`(한자 병기판)와 `02개역난외주.bdb`(소제목+각주,
HTML 색상 태그로 구분)를 첨부했다.

### 저작권 조사

- **국한문**: 앱에 이미 번들된 개역한글 DB와 6개 대표 이문 구절(롬16:24 등
  "(없음)" 표기, 요일5:7 실제 본문)까지 정확히 일치 — 새 번역이 아니라 지금
  쓰는 그 개역한글 텍스트에 한자만 병기한 것임을 확인. 대한성서공회 목록의
  「관주성경전서 간이국한문」(1964년 발행, 2014년 저작재산권 소멸)과 계열이
  같을 가능성이 높다.
- **난외주**: 내용을 열어보니 순수 각주가 아니라 소제목(2,422개, `<FONT
  COLOR="#996699">〔가인과 아벨〕</FONT>` 형태)과 단어 뜻풀이·구약 인용 출처
  각주(2,356개, `<SMALL><FONT COLOR="#FF6095">〔사 7:14〕</FONT></SMALL>`
  형태)가 섞여 있었다. 이 구성(관주+난외주+소제목을 함께 묶음)은 대한성서공회가
  「관주성경전서 개역한글판」(1962, 2012년 저작재산권 소멸)이라 부르는 판본의
  구성과 일치 — 이전에 검토한 관주(output.json) 데이터와 같은 출처일 가능성이
  있다.
- 두 파일 모두 이전 관주 때와 같은 결론: 정황 증거는 강하지만 출처를 100%
  증명하지는 못한다. 대한성서공회 확인 전까지는 배포용으로 확정된 상태가
  아님을 코드 곳곳에 명시했다.

### 사용자 결정

두 가지 질문에 답변받음:
1. 국한문 통합 방식 → "지금 바로 번들 기본 제공으로 등록" (권장안 선택)
2. 난외주 통합 수준 → "소제목 제외. 각주와 국한문만."

### 구현

**국한문(두 번째 번들 번역본)**
- `Resources/BibleDB_Hanja.bdb`(신설) — 첨부 파일 복사. 스키마가 이미 "사용자
  추가 번역본" 스키마(`Bible(id,book,chapter,verse,btext)`)와 같아
  `BibleReferenceStore`가 코드 변경 없이 그대로 읽는다.
- `Services/TranslationBootstrap.swift` — `hanjaTranslationCode`("KRV_HANJA")/
  `hanjaDisplayName`("개역한글(국한문)") 추가. `resolvedBundledDatabaseURL(for
  code:)`(코드→번들 파일 매핑 일원화)와 `ensureHanjaTranslationRegistered(in:)`
  신설. `TranslationRegistry.licenseType`에 "출처 확인 중"을 넣어 목록에서도
  KRV와 저작권 확정 상태가 다름을 드러낸다.
- `ContentView.swift` — 부트스트랩에 `ensureHanjaTranslationRegistered` 호출
  추가.
- ⚠️ [발견한 버그, 같이 고침] `BibleReadingViewModel.store(for:)`/
  `SearchViewModel.store(for:)`가 "번들이면 무조건 `resolvedBundledDatabaseURL()`
  (인자 없음, KRV 고정)"이었다 — 번들 번역본이 하나뿐일 때는 문제없었지만,
  국한문이 추가되면 그 컬럼도 항상 KRV 내용을 열어버리는 회귀가 생긴다. 두
  곳 다 `resolvedBundledDatabaseURL(for: registry.code)`로 고쳤다.

**난외주(각주만)**
- `Resources/MarginalNoteSeed.json`(신설) — `02개역난외주.bdb`에서 소제목은
  빼고 각주만 정규식으로 추출(`<SMALL><FONT COLOR="#FF6095">〔...〕</FONT>
  </SMALL>`), `{book_id, chapter, verse, notes: [...]}` 형식으로 정리(2,141개
  절, 각주 2,356개).
- `BibleResearchPlatform/.../VerseAnnotations.swift` — `VerseMarginalNote`
  `@Model` 신설(`VerseCrossReference.source`와 같은 `VerseCrossReferenceSource`
  재사용). 원본의 위 첨자 위치 앵커(①②③ 등)는 옮기지 않고 절 단위 목록으로
  단순화했다 — 사용자가 고른 통합 방식("관주처럼 아이콘 → 팝오버")엔 그
  정도면 충분하다고 판단.
- `BibleResearchSchema.swift` — `VerseMarginalNote.self` 등록.
- `Services/MarginalNoteSeedImporter.swift`(신설) — `OutlineSeedImporter`/
  `CrossReferenceSeedImporter`와 같은 1회성 시딩 패턴.
- `Services/UserSettingsStore.swift` — `hasImportedMarginalNoteSeed` 플래그.
- `ContentView.swift` — `MarginalNoteSeedImporter.importIfNeeded` 호출 추가.
- `Views/Bible/BibleReadingViewModel.swift` — `chapterMarginalNotes`(장 전체
  미리 로드) + `marginalNotes(translationCode:verse:)`(절 단위 필터, 기존
  `crossReferences`와 완전히 같은 패턴).
- `Views/Bible/TranslationColumnView.swift` — `marginalNotesProvider` prop
  추가, `VerseRow`에 관주 아이콘 바로 아래 각주 아이콘(`asterisk.circle`)
  추가 — 탭하면 팝오버로 각주 텍스트 목록(단순 `Text`, 관주와 달리 탭해서
  이동할 대상이 없음).
- `Views/Bible/BibleReadingView.swift` — 두 컬럼 렌더링 경로(아이폰 TabView/
  아이패드·맥 나란히 배치) 모두에 `marginalNotesProvider` 연결.
- ⚠️ [범위 축소, 명확히 플래그] 소제목(2,422개)은 이번에 넣지 않았다(사용자가
  명시적으로 제외). 확대보기(`VerseZoomView`)에는 각주 아이콘을 추가하지
  않았다 — 그 화면은 `TranslationColumnView.VerseRow`를 재사용하지 않고 별도
  주석 UI(액션바/선택 모드)를 직접 구현하고 있어, 이번 "각주와 국한문만"
  범위 밖의 추가 작업이 필요해 손대지 않았다.

### 정적 검증

새/수정 파일 10개(VerseAnnotations.swift, BibleResearchSchema.swift,
TranslationBootstrap.swift, UserSettingsStore.swift,
MarginalNoteSeedImporter.swift, ContentView.swift, BibleReadingViewModel.swift,
SearchViewModel.swift, TranslationColumnView.swift, BibleReadingView.swift)
전부 괄호·중괄호 균형 스크립트 재확인 — 전부 이상 없음.

Sources:
- [성경의 저작권](https://www.bskorea.or.kr/bbs/content.php?co_id=subpage2_3_4_1)

## 이어서 61 (2026-08-14)

**"아직 결정 보류"였던 국한문 아키텍처 — 사용자가 최종 확정, 절 단위 한자
주석으로 전면 구현**

사용자 답변: "두 번째 번역본(국한문 전체 중복 테이블)을 지우고 → 절 단위
한자 주석 모델 → Ok." 이어진 질문("개역한글 본문 인라인 병기가 정확히 뭘
뜻하는지")에 대한 설명 뒤, 표시 방식은 "둘 다 지원, 설정으로 전환"으로
확정. `KRV_HANJA` 두 번째 번들 번역본(이어서 59)을 완전히 걷어내고, 그
자리를 개역한글 본문 위에 얹는 "절 단위 한자 주석 + 표시 모드 3단 설정"으로
교체했다.

**데이터 모델**
- `BibleResearchPlatform/.../VerseAnnotations.swift` — `HanjaWordAnnotation`
  (Codable 값 타입: `ko`/`hanja`/`rangeStart`/`rangeEnd`, `VerseCrossReference.
  targets`의 `BibleVerseRef`와 같은 패턴) + `VerseHanjaAnnotation` `@Model`
  신설. 단어 하나당 레코드를 만들지 않고 절 하나당 레코드 하나(단어 배열)로
  묶었다 — 단어 단위면 122,730건이 되어 관주 시딩 때(이어서 58) 이미 겪은
  CloudKit 요청 제한 문제가 훨씬 커진다. 절 단위로 묶으면 29,288건.
- `BibleResearchSchema.swift` — `VerseHanjaAnnotation.self` 등록.

**시드 데이터 추출 (오프라인, Python)**
- `02개역국한문.bdb`(Bible 테이블)에서 한글단어(한자) 쌍을 절 순서대로
  정규식 추출한 뒤, 이 프로젝트가 실제 쓰는 개역한글 본문(`BibleDB.sqlite`
  `BibleVerses.content`)에서 그 단어를 순서대로(커서를 앞으로만 이동) 검색해
  UTF-16 오프셋을 미리 계산해 뒀다. 두 파일이 완전히 같은 디지털화 배치가
  아니라 그대로는 못 찾는 경우가 있었다("사냥군" vs "사냥꾼", "삼십세" vs
  "삼십 세") — 글자 사이 공백을 선택적으로 허용하는 퍼지 정규식 매칭까지
  더해 123,116쌍 중 122,730쌍(99.69%)을 맞췄다. 나머지 386쌍(옛 표기 차이,
  합성어 경계 등 실제 이문)은 조용히 건너뛰었다 — 그 단어들만 주석이 안
  붙을 뿐 나머지엔 영향 없다.
- `Resources/HanjaAnnotationSeed.json`(신설, 9.1MB) — `[{book_id, chapter,
  verse, words: [{ko, hanja, start, length}]}]`, 29,288개 절.

**시더 + 사전 로더**
- `Services/HanjaAnnotationSeedImporter.swift`(신설) — `CrossReferenceSeedImporter`
  와 같은 1회성 "번들 JSON → 사용자 DB" 패턴. `UserSettingsStore.
  hasImportedHanjaAnnotationSeed` 플래그.
- `Services/HanjaDictionaryProvider.swift`(신설) — 이어서 60에서 만든
  `Resources/HanjaDictionary.json`(2,002자 훈음)을 앱 번들에서 한 번만 읽어
  캐시하는 싱글턴(`BooksProvider`와 같은 패턴). `info(for: Character)`/
  `infoList(for: String)`로 글자 단위 조회.
- `ContentView.swift` — 부트스트랩에 `HanjaAnnotationSeedImporter.importIfNeeded`
  추가, `ensureHanjaTranslationRegistered` 호출은
  `TranslationBootstrap.removeHanjaTranslationIfPresent`로 교체(아래).

**두 번째 번들 번역본 제거**
- `Services/TranslationBootstrap.swift` — `ensureHanjaTranslationRegistered`/
  `resolvedHanjaBundledDatabaseURL`/`hanjaBundledDatabaseNotFound` 삭제.
  `removeHanjaTranslationIfPresent(in:)` 신설 — 오늘 하루 사이 이미
  `TranslationRegistry(code: "KRV_HANJA")`가 등록된 기기(있다면)에서 그 행을
  지운다. `resolvedBundledDatabaseURL(for:)`는 함수 형태를 유지해(이제
  `bundledTranslationCode` 하나만 처리) `BibleReadingViewModel`/
  `SearchViewModel`의 기존 호출부를 되돌리지 않아도 되게 했다.
- ⚠️ `BibleDB_Hanja.bdb`(7.3MB) 파일 자체는 Xcode 타겟에서 빼지 않았다 —
  더 이상 런타임에 쓰이진 않지만(이제 `HanjaAnnotationSeed.json`/
  `HanjaDictionary.json`을 뽑아내는 오프라인 원천 자료로만 쓰인다),
  `project.pbxproj`의 `PBXFileSystemSynchronizedRootGroup`(Xcode 16 폴더
  동기화 그룹, 이 프로젝트가 이미 이 방식이라 파일을 폴더에 두기만 하면
  자동으로 번들에 포함된다) 멤버십을 손으로 건드리는 건 이번 요청 범위 밖이라
  손대지 않았다. 앱 용량을 줄이고 싶으면 나중에 Xcode에서 직접 빼면 된다.

**표시 방식 3단 설정 + 렌더링**
- `Services/UserSettingsStore.swift` — `HanjaDisplayMode`(`.off`/`.tapToReveal`/
  `.alwaysInline`) enum + `hanjaDisplayMode` 저장 프로퍼티(기본값 `.off` —
  이 기능을 몰랐던 기존 사용자에게 갑자기 낯선 한자가 나타나지 않도록).
- `Views/Settings/SettingsView.swift` — "성경 조회 표시" 섹션에 3단 Picker
  추가.
- ⚠️ [설계 판단] "탭하면 보기"를 "본문 안의 그 단어를 직접 탭"으로 만들지
  못했다 — `SwiftUI Text(AttributedString)`은 구간별로 탭 제스처를 따로 걸
  수 없다는 제약을 관주 아이콘(이어서 16 설계 논의)에서 이미 확인했고, 이번
  것도 똑같은 벽에 부딪힌다. 그래서 관주/난외주와 완전히 같은 "절 번호 아래
  아이콘(`character.book.closed`) → 팝오버로 그 절의 한자 단어 전체 목록"
  패턴을 그대로 재사용했다 — 목록 각 줄이 "태초 太初 — 클 태 · 처음 초"
  형태로 이미 상세 정보라 더 파고들 필요가 없다.
- `Views/Bible/VerseAnnotationRenderer.swift` — `attributedContentWithHanja(...)`
  신설. 기존 `attributedContent`(형광펜/메모)가 만든 `AttributedString`(또는
  없으면 새로 만든 평범한 것) 위에, 한자 단어 뒤마다 "(한자)"를 끼워 넣는다.
  ⚠️ [삽입 순서 주의] `rangeEnd` 내림차순(뒤→앞)으로 삽입해야 한다 — 앞에서부터
  넣으면 뒤에 있는 저장된 오프셋이 전부 밀려 버린다. `Range(nsRange, in:
  attributedString)`(Foundation의 NSRange↔AttributedString.Index 브리징)로
  변환한 뒤 `insert(_:at:)`. 원본 `verse.content` 자체는 손대지 않는다 —
  표시 시점에만 조합.
- `Views/Bible/TranslationColumnView.swift` — `hanjaWordsProvider` prop,
  `VerseRow`에 아이콘(탭하면 보기 모드에서만) + 팝오버(`hanjaPopoverContent`,
  `HanjaDictionaryProvider`로 글자별 훈음 조회) 추가. `verseContentText`에
  "항상 보기" 분기 추가(`attributedContentWithHanja` 호출).
- `Views/Bible/BibleReadingViewModel.swift` — `chapterHanjaAnnotations`(장
  전체 미리 로드) + `hanjaWords(translationCode:verse:)`(절 단위 조회, 기존
  `marginalNotes`와 같은 패턴).
- `Views/Bible/BibleReadingView.swift` — 두 컬럼 렌더링 경로(아이폰 TabView/
  아이패드·맥 나란히 배치) 모두에 `hanjaWordsProvider` 연결.
- ⚠️ [범위 밖, 명확히 플래그] 확대보기(`VerseZoomView`)는 이번에도 손대지
  않았다 — 난외주(이어서 59) 때와 같은 이유(`TranslationColumnView.VerseRow`를
  재사용하지 않는 별도 구현).

### 정적 검증

새/수정 파일 12개 전부 괄호·중괄호·대괄호 균형 스크립트로 재확인(주석 안
한글 문장부호로 인한 오탐을 줄이려 `//` 줄 주석과 문자열 리터럴 내용을 먼저
제거하고 카운트) — 전부 이상 없음. `project.pbxproj`가
`PBXFileSystemSynchronizedRootGroup`(폴더 동기화 그룹)을 쓰고 있음을
확인해, 새 리소스 2개(`HanjaAnnotationSeed.json`/`HanjaDictionary.json`)가
별도 pbxproj 편집 없이도 자동으로 Copy Bundle Resources에 포함됨을
검증했다.

## 이어서 62 (2026-08-15)

**사용자 요청**
> "성경관련 json seed 파일은 기본 제공 db에 넣을 것.
> 난외주/성경한자/한문사전/관주"

이어 4개 시더(JSON→SwiftData 1회성 복사, 이어서 58/59/60/61) 중 어느 것 하나 사용자가
직접 편집하는 게 아니라는 점 — "관주/난외주/한자주석/한자사전 파일들을 하나로
합칠지, 합친다면 `BibleDB.sqlite`에 넣을지 별도 파일로 둘지" 질문에 사용자가
"통합하는 게 나음. 단, 별도 Database 파일이 나은가 BibleDB Database에
하나로 통합하는게 나은가?"라고 되물어, 장단점(별도 파일은 `BibleReferenceStore`의
기존 스키마 감지 로직에 위험이 없고, "번역 본문"과 "참조/주석 계층"을 개념적으로
분리하며, SQLite 파일이 여러 개라도 런타임 비용은 무시할 만함)을 설명했고 —
**"Ok 별도 파일(ReferenceData.sqlite)로 할것."** 로 확정했다.

**핵심 아키텍처 전환**

`BibleReferenceStore`(관주 원문 DB `BibleDB.sqlite`를 SwiftData가 아니라 원시
SQLite C API로 직접 읽는, 이 프로젝트에 이미 있던 패턴)를 그대로 따라
`ReferenceDataStore`를 신설 — "정적 참조 데이터는 SwiftData/CloudKit이 아니라
번들 SQLite에서 매번 직접 읽는다"는 원칙을 관주/난외주/한자주석/한자사전
4종에도 적용했다. 기존엔 앱 최초 실행 시 JSON을 SwiftData로 1회성 복사해
CloudKit으로 기기 간 동기화했는데 — 이 데이터는 애초에 사용자가 만들거나
고치는 게 아니라서 동기화할 이유가 없었고, 새 기기에서 매번 수만 건을
복사해 넣는 부트스트랩 비용도 불필요했다.

**`ReferenceData.sqlite`(신설, 8.2MB, `Resources/`에 번들)**
- `CrossReferences(book_id, chapter, verse, targets)` — 관주, 28,377행.
  `targets`는 `"66:1:1,66:1:2"`처럼 `책ID:장:절`을 콤마로 이어 붙인 문자열
  (기존 SwiftData 스키마의 `VerseCrossReference.targets` 저장 방식 그대로).
- `MarginalNotes(book_id, chapter, verse, note_index, note_text)` — 난외주,
  2,356행.
- `HanjaAnnotations(book_id, chapter, verse, word_index, ko, hanja,
  range_start, range_end)` — 절 단위 한자 주석, 122,730행.
- `HanjaDictionary(char PRIMARY KEY, eum, hun, count, confidence)` — 훈음
  사전, 2,002행.
- 4개 테이블 모두 `(book_id, chapter, verse)` 인덱스.

**`ReferenceDataStore.swift`(신설, 패키지)** — `BibleReferenceStore`와
똑같은 C API 패턴(`sqlite3_open_v2(..., SQLITE_OPEN_READONLY, ...)`,
`sqlite3_prepare_v2`/`sqlite3_bind_int`/`sqlite3_step` 루프, 파일 스코프
`private let SQLITE_TRANSIENT = unsafeBitCast(-1, to:
sqlite3_destructor_type.self)` — 두 파일 다 `private`라 충돌 안 함).
`crossReferences(bookId:chapter:translationCode:)`/`marginalNotes(...)`는
SwiftData `@Model`(`VerseCrossReference`/`VerseMarginalNote`)을
**`context.insert`를 호출하지 않고** 메모리상 객체로만 만들어 반환한다 —
SwiftData `@Model`은 삽입 없이 평범한 객체로 써도 되는 성질을 이용해,
뷰 레이어(`TranslationColumnView`/`VerseAnnotationRenderer`/팝오버 전부)를
**한 줄도 안 고치고** `BibleReadingViewModel`에서 사용자분(SwiftData 조회)과
번들분(SQLite 조회)을 그냥 배열로 이어 붙이기만 하면 되게 설계했다.
`hanjaAnnotations(bookId:chapter:)`는 `[Int: [HanjaWordAnnotation]]`(절
번호 → 단어 목록)을, `allHanjaDictionaryEntries()`는
`[HanjaCharacterInfo]` 전체를 반환한다.

**연쇄 수정**
- `Models/VerseAnnotations.swift` — `HanjaCharacterInfo` 구조체를 앱 레이어
  (`HanjaDictionaryProvider`)에서 패키지로 옮겨 공유. `VerseHanjaAnnotation`
  (`@Model`, 절 단위 한자 주석용으로 이어서 61에서 막 만들었던 것)을
  통째로 삭제 — 번들 전용 데이터라 사용자 작성 경로가 아예 없었고, 같은
  세션 안에서 만들어져 실사용자 배포 이력이 없어 마이그레이션 위험이
  낮다고 판단했다.
- `Schema/BibleResearchSchema.swift` — `modelTypes`에서
  `VerseHanjaAnnotation.self` 제거.
- `Services/ReferenceDataProvider.swift`(신설) — `Bundle.main`에서
  `ReferenceData.sqlite`를 찾아 `ReferenceDataStore`를 한 번만 여는
  `@MainActor` 싱글턴(`HanjaDictionaryProvider`/`BooksProvider`와 같은 패턴).
  파일이 없거나 열기 실패 시 `store`가 `nil` — 호출부는 옵셔널 체이닝으로
  조용히 빈 배열/딕셔너리로 처리된다(크래시 없음).
- `Services/ReferenceDataMigration.swift`(신설) — `OutlineSeedImporter`와
  같은 "1회 실행 후 플래그" 패턴. 옛 시더(`CrossReferenceSeedImporter`/
  `MarginalNoteSeedImporter`)가 이미 SwiftData에 복사해 넣은 적이 있는
  `source == .bundled` 레코드(있다면)를 정리한다. ⚠️ `VerseHanjaAnnotation`
  레코드는 타입 자체를 스키마에서 지웠기 때문에 `FetchDescriptor`를 만들
  수 없어 이 마이그레이션이 정리하지 못한다 — 테스트용 데이터라 위험 낮음
  으로 판단하고 넘어갔다(README 파일 내 주석에 명시).
- `Services/HanjaDictionaryProvider.swift` — `HanjaDictionary.json` 직접
  파싱 대신 `ReferenceDataProvider.shared.store?.allHanjaDictionaryEntries()`
  호출로 전환. 공개 API(`info(for:)`/`infoList(for:)`)는 그대로.
- `Services/UserSettingsStore.swift` — `hasCleanedUpLegacyBundledReferenceData`
  플래그 추가.
- `Services/TranslationBootstrap.swift` — `hanjaBundledDatabaseNotFound`
  에러 케이스 제거(더 이상 쓰이지 않는 죽은 코드).
- `ContentView.swift` — 옛 임포터 3개(`CrossReferenceSeedImporter`/
  `MarginalNoteSeedImporter`/`HanjaAnnotationSeedImporter`) 호출을 전부
  지우고 `ReferenceDataMigration.cleanupLegacyBundledRecords(in:)` 한 줄로
  교체. `OutlineSeedImporter` 호출은 무관한 기능이라 그대로 둠.
- `Views/Bible/BibleReadingViewModel.swift` — `chapterHanjaAnnotations`
  타입을 `[VerseHanjaAnnotation]`에서 `[Int: [HanjaWordAnnotation]]`으로
  변경. 관주/난외주 로딩 블록을 "SwiftData(사용자분, `sourceRaw !=
  bundledSourceRaw`로 필터) + `ReferenceDataProvider.shared.store`(번들분)
  병합"으로 재작성. `hanjaWords(translationCode:verse:)`는
  `chapterHanjaAnnotations[verse] ?? []` 조회로 단순화.

**삭제된 파일**
- `Services/CrossReferenceSeedImporter.swift`
- `Services/MarginalNoteSeedImporter.swift`
- `Services/HanjaAnnotationSeedImporter.swift`

**번들 밖으로 옮긴 원본 파일** — `JBCHBibleResearch.xcodeproj`와 나란한
새 폴더 `ReferenceDataSource/`(Xcode의 `PBXFileSystemSynchronizedRootGroup`
동기화 대상 밖이라 앱 번들에는 안 들어감, 앱 용량 절감)로 이동:
`CrossReferenceSeed.json`(4.79MB), `MarginalNoteSeed.json`(218KB),
`HanjaAnnotationSeed.json`(9.1MB), `HanjaDictionary.json`(204KB),
`BibleDB_Hanja.bdb`(7.36MB, 이 JSON들을 뽑아낸 원본 국한문 DB). `Resources/`
에는 이제 런타임에 실제로 쓰는 파일만 남았다: `BibleDB.sqlite`,
`OriginalText.sqlite`, `OutlineSeed.json`, `ReferenceData.sqlite`,
`books.json`.

`ReferenceDataSource/build_reference_data.py`(신설)도 같은 폴더에 저장—
위 4개 JSON(+`books.json`의 책 약어 인덱스)에서 `ReferenceData.sqlite`를
재생성하는 스크립트. 향후 관주/난외주/한자주석 데이터를 갱신할 일이 생기면
이 스크립트만 다시 돌리면 된다(그때그때 heredoc으로 즉석 작성했던 걸
재사용 가능한 형태로 남겨 둠).

### 검증

- `build_reference_data.py`를 실제로 재실행해 새로 만든
  `ReferenceData.sqlite`가 기존 파일과 4개 테이블 전부 행 집합 단위로
  완전히 동일함을 확인(개수뿐 아니라 내용까지 `SELECT` 결과를 집합으로
  비교) — 스크립트가 실제 배포된 파일과 정확히 같은 결과를 재현함을
  검증했다.
- 새/수정 파일 10개(`ReferenceDataStore.swift`,
  `ReferenceDataProvider.swift`, `ReferenceDataMigration.swift`,
  `HanjaDictionaryProvider.swift`, `UserSettingsStore.swift`,
  `TranslationBootstrap.swift`, `ContentView.swift`,
  `BibleReadingViewModel.swift`, `VerseAnnotations.swift`,
  `BibleResearchSchema.swift`) 전부 괄호·중괄호·대괄호 균형 스크립트로
  재확인 — 전부 이상 없음.
- ⚠️ Xcode 실제 빌드는 사용자 환경에서 직접 확인이 필요하다(이 세션에는
  Xcode 툴체인이 없음) — 특히 `ReferenceDataStore`가 새로 참조하는
  `SQLite3` import가 패키지 타겟 설정에서 기존 `BibleReferenceStore`와
  같은 조건으로 링크되는지 확인 권장.

## 이어서 63 (2026-08-15)

**사용자 요청**
> 기능수정
> - 한자 주석표시 : 탭하면 보기 - 구절을 선택하면 해당 구절만 국한문 혼용으로 표시
> - 구절 선택후 확대보기 조회모드 수정
>   - 관주 x개 라고 표시된 곳에 관주 개수가 아닌 관주 구절을 가로로 콤마로
>     구분+성경약어로 나열할 것. 나열할 때, 혹 인접한 구절끼리는 묶어서 표현할
>     것.(고후1:1, 고후1:2 -> 고후1:1-2) 글씨 크기를 조금만 더 키우기
>   - 관주 영역 위에 한문 단어 뜻풀이 영역을 따로 두어 구절에 포함된 한문을
>     한글단어+한자 + 음 훈 풀이를 같이 표시할 것.
> - 확대모드 편집모드 수정 - 관주 버튼을 누르면, 관주 연결 팝업에 입력된
>   관주들이 표시되게 할 것.

바로 앞 대화 턴에서 사용자가 "한문을 탭하면 본다는 게 어떻게 하면 보인다는
것이지? 그리고 한문뜻은 어떻게 볼수 있지?"라고 물었고, 당시 답변은 "절 번호
아래 아이콘 → 팝오버로 그 절의 한자 단어 전체 목록(뜻 포함)"이었다(이어서
61이 구현한 원래 방식). 이번 요청은 그 인터랙션 자체를 다시 설계해 달라는
것 — 아이콘 대신 "절 선택"을 트리거로 쓰고, 뜻풀이는 메인 화면이 아니라
확대보기로 옮긴다.

**1) 메인 읽기 화면 — "탭하면 보기" = 절 선택 시 그 절만 국한문 인라인**

`TranslationColumnView.swift`:
- `VerseRow`의 한자 아이콘(`character.book.closed`) + 팝오버(단어+훈음 목록)를
  삭제했다. 대신 이미 있던 절 선택 상태(`isSelected` — 클립보드 복사용으로
  절 전체를 탭하면 켜지는 그 토글, `TranslationColumnView.columnScrollView`의
  `.onTapGesture`)를 그대로 재사용한다.
- `verseContentText`가 쓰던 `settings.hanjaDisplayMode == .alwaysInline`
  단일 조건을 `shouldShowInlineHanja`(신설 computed property)로 바꿨다 —
  `.alwaysInline`이면 항상, `.tapToReveal`이면 `isSelected`일 때만, `.off`면
  항상 false. 실제 인라인 렌더링 로직(`VerseAnnotationRenderer.
  attributedContentWithHanja`)은 두 모드가 완전히 같아 분기 하나로 합쳤다.
- ⚠️ [설계 판단] 절 선택 상태는 클립보드 복사와 한자 인라인 표시가 같은
  `Set<Int>`(`selectedVerses`)를 공유한다 — 사용자가 여러 절을 동시에
  선택하면(복사용) "탭하면 보기" 모드에서는 선택된 절 전부가 동시에
  국한문으로 보인다. 두 기능이 개념적으로 다르지만 "절을 탭해서 고른다"는
  동작 자체는 동일해 상태를 분리할 이유가 없다고 판단했다 — 다른 번역본
  컬럼(개역한글이 아닌)은 애초에 `hanjaWords`가 항상 빈 배열이라(
  `BibleReadingViewModel.hanjaWords`가 번들 번역본 코드로 필터링) 영향이 없다.
- `HanjaDictionaryProvider`(글자별 훈음 조회)를 부르는 곳이 이제 이 파일에는
  없다 — 아래 확대보기로 옮겼다.

**2) 확대보기(`VerseZoomView.swift`) — 관주 영역을 실제 구절 나열로**

- `annotationStatusBar`의 관주 배지를 "관주 N개"(정제된 묶음 개수) 대신
  `crossReferenceInlineLabel`(신설)로 바꿨다 — 이 절에 걸린
  `VerseCrossReference` 전부에서 `targets`를 모아 중복 제거
  (`allCrossReferenceVerses`, `Set<BibleVerseRef>` 활용) 후, 정경 순서(책
  `orderIndex` → 장 → 절)로 정렬하고, 같은 책·같은 장에서 절 번호가 1씩
  연속인 구간을 "장:시작-끝" 하나로 합친다(예: "고후1:1, 고후1:2" →
  "고후1:1-2"). 책 표기는 `Book.abbreviation.first`(짧은 약어, 예: "고후").
  버튼 자체(탭하면 기존 이동/삭제 팝오버)는 그대로 유지 — 라벨만 바뀌었다.
- 글씨 크기 — `.caption`(상속)에서 관주 줄만 `.footnote`로 한 단계 키웠다
  ("조금만 더 키우기" 요청).
- ⚠️ [레이아웃 변경] 관주 라벨이 이제 구절 개수에 따라 길어질 수 있어(예:
  10개 관주면 "창1:1, 출2:3-5, 시19:1, ..." 식으로 매우 길어짐), 기존
  `annotationStatusBar` 한 줄 `HStack`(관주/개인 묵상/관련 내용 나란히)을
  `VStack`으로 바꿔 관주 줄은 단독으로 줄바꿈 가능하게(`.fixedSize(horizontal:
  false, vertical: true)`) 하고, 개인 묵상/관련 내용은 그 아래 별도
  `HStack`으로 유지했다. 사용자가 명시적으로 요청한 변경은 아니지만, 라벨을
  구절 나열로 바꾸는 순간 한 줄 배치가 깨질 것이 확실해 함께 조정했다.
- 더 이상 쓰이지 않게 된 `crossReferenceGroupCount`(정제된 묶음 개수 집계)는
  삭제했다.

**3) 확대보기 — 관주 영역 위 "한자 뜻풀이" 영역 신설**

- `hanjaGlossSection`(신설) — `viewModel.hanjaWords(translationCode:verse:)`로
  이 절의 한자 단어를 가져와 "한글단어 한자" + `HanjaDictionaryProvider.
  infoList(for:)`로 찾은 훈음을 한 줄씩 나열한다(메인 화면에서 삭제한 팝오버
  내용과 사실상 같은 정보, 위치만 확대보기로 옮김). `annotationStatusBar`보다
  먼저(위에) 그리고, 사이에 `Divider()`를 하나 더 넣었다.
- 관주/난외주와 달리 `hanjaDisplayMode` 설정값과 무관하게 한자 단어가 있으면
  항상 보인다 — 확대보기는 사용자가 명시적으로 연 상세 화면이라, 메인 화면의
  "끄기/탭하면 보기/항상 보기" 전역 토글에 종속시킬 이유가 없다고 판단했다.

**4) 확대모드 편집모드 — 관주 버튼이 항상 등록된 관주를 보여주도록**

- `actionBar`의 관주 버튼이 여는 `CrossReferenceTargetPicker` 시트에 넘기는
  `existingReferences`가, 텍스트 선택이 없을 때(`hasSelection == false`, 즉
  "절 전체" 대상) 이전엔 무조건 `[]`였다 — 이미 절 전체에 등록된 관주가
  있어도 시트에 안 보였다. `crossReferences`(이 절에 걸린 관주 전부)로
  바꿔, 선택이 없을 때도 기존에 입력된 관주가 "등록된 관주" 섹션에 보이게
  했다. 선택이 있을 때(`hasSelection == true`)는 기존 그대로 그 범위와
  겹치는 것만 보여준다(`overlappingCrossReferences`, 변경 없음).
- `CrossReferenceTargetPicker.existingDisplayEntries`는 애초에
  `reference.rangeStart`/`anchorText` 유무와 무관하게 동작하도록 짜여 있어
  (구간 관주든 절 전체 관주든 `groupedEntries` 또는 `targets` 기반 폴백으로
  처리), 이 변경에 그 파일 자체는 손댈 필요가 없었다.

### 정적 검증

수정한 3개 파일(`TranslationColumnView.swift`, `VerseZoomView.swift`,
`HanjaDictionaryProvider.swift`, 마지막은 주석만 수정) 전부 괄호·중괄호·
대괄호 균형 스크립트로 재확인 — 전부 이상 없음. `isHanjaPopoverPresented`/
`hanjaPopoverContent`(삭제한 메인 화면 팝오버)를 프로젝트 전체에서 재검색해
남은 참조가 없음을 확인했다(주석 한 줄만 있었고, 그 문구도 같이 정리했다).

⚠️ Xcode 실제 빌드는 사용자 환경에서 직접 확인이 필요하다(이 세션에는
Xcode 툴체인이 없음).

## 이어서 64 (2026-08-15)

**사용자 요청**
> 확대보기 한자 뜻풀이 수정
> - 영역을 2단으로 나누어서 표시
> - 중복된 단어는 제거할 것
> - 한글 + 한자 다음줄 음 훈 뜻풀이
> - 한글 + 한자 : 확대보기의 성경 구절 크기와 동일하게 키울것.
> - 음 훈 뜻 풀이 : 확대보기의 성경구절보다는 작게, 현재보다는 크게
>
> 확대보기 관주 수정
> - 클릭했을 때 팝업제거 (x) -> 관련 성경이동.
>
> 확대보기 성경구절 수정
> - 한자가 있는 단어는 색깔로 표현해 줄 것.

관주 팝업을 없애는 순간 그 팝업의 삭제(X) 기능도 함께 사라지는 트레이드오프가
있어, 먼저 AskUserQuestion으로 확인했다 — 사용자 답변: "삭제기능은 편집모드에
관주버튼 누르면 나오는 관주연결팝업에서의 리스트에 각 항목별로 (x)를 붙여
삭제기능을 옮길것."

**1) 한자 뜻풀이 영역 — 2단 그리드 + 중복 제거 + 크기 조정**

`VerseZoomView.hanjaGlossSection`:
- `LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], ...)`로
  2단 배치.
- `uniqueHanjaWords`(신설) — (한글, 한자) 조합 기준으로 중복 제거(같은 단어가
  절 안에 여러 번 나올 수 있어, 오프셋은 달라도 뜻풀이 표시 목적으론 같은
  항목으로 취급).
- 각 항목을 `VStack`(세로 2줄)으로: 1행 "한글단어 한자", 2행 음훈풀이.
- 1행 폰트 — `bibleSwiftUIFont`(신설) — 확대보기가 성경 본문에 쓰는
  `bibleFont`(PlatformFont, 17pt 고정 — `bibleBodyFontSize` 설정값과 무관하게
  확대보기 자체 레이아웃 계산 때문에 고정돼 있다)와 같은 글꼴 이름 + 17pt를
  SwiftUI `Font`로 재구성한 것 — `Text.font(...)`는 SwiftUI `Font`가
  필요해서 PlatformFont를 그대로 못 쓴다.
- 2행 폰트 — `.caption`(이전)에서 `.subheadline`으로 — "성경구절보다는 작게,
  현재보다는 크게" 요구를 만족하는 중간값으로 골랐다(caption ≈ 12pt <
  subheadline ≈ 15pt < 17pt 고정 성경 본문 크기).

**2) 확대보기 관주 — 팝업 제거, 클릭 시 바로 이동, 삭제는 편집모드로 이전**

- `annotationStatusBar`의 관주 부분을 통째로 재설계했다. 이전엔 라벨
  (실제 구절 나열, 이어서 63) 전체가 버튼 하나였고 탭하면 이동/삭제
  팝오버가 떴다 — 이제 팝오버가 없다. 병합된 구절 구간마다(예: "고후1:1-2")
  독립된 칩 버튼으로 그리고, 탭하면 그 구간의 첫 절로 바로
  `onJumpToCrossReference` + `dismiss()`(팝오버 열기 단계 없이 곧장 이동).
- `crossReferenceInlineLabel`(문자열 하나)을 `crossReferenceInlineSegments`
  (`[(label, verses)]` 배열)로 바꿨다 — 구간이 여러 개면 탭 대상도 구간별로
  달라야 하기 때문(문자열 하나로는 버튼도 하나뿐이라 "그 중 어디로 이동?"을
  구분할 수 없었다).
- 여러 구간을 한 줄에 다 못 담을 수 있어 자동 줄바꿈되는 `FlowLayout`(신설,
  파일 하단, SwiftUI `Layout` 프로토콜 표준 구현 — 서드파티 의존성 없이 최소
  구현)으로 감쌌다.
- 삭제(X) 기능 — 팝오버와 함께 없애는 대신 사용자 확인대로 편집모드로
  옮겼다. `CrossReferenceTargetPicker`에 `onDeleteExisting: (VerseCrossReference,
  [BibleVerseRef]) -> Void` 콜백을 신설하고, "등록된 관주" 목록의 각 행에
  X 버튼을 붙였다. `existingDisplayEntries`(내부 표시용 정제 목록)가 이제
  라벨/절목록뿐 아니라 그 항목이 속한 원본 `VerseCrossReference`까지 함께
  들고 있어야 해서(삭제하려면 어느 레코드에서 지울지 알아야 한다) 반환
  타입에 `reference`를 추가했다. `VerseZoomView`가 이 콜백을
  `viewModel.removeCrossReferenceGroup(verses, from: reference)`로 연결한다
  — 삭제 로직 자체(SwiftData 조작)는 하나도 새로 안 만들고 기존 함수를
  그대로 재사용했다.
- ⚠️ [편집모드 진입 경로 확인] "관주" 액션바 버튼을 눌러야 이 시트가 열린다
  — 조회 화면에서 팝업 없이 바로 이동하게 바뀌었으니, 관주를 지우고
  싶으면 이제 펜 아이콘(편집모드 진입) → "관주" 버튼 → "등록된 관주" 목록의
  X 순서로 한 단계 더 거쳐야 한다. 사용자가 명시적으로 선택한 위치라 별도
  확인 없이 반영했다.
- 이제 안 쓰는 `isCrossReferencePopoverPresented`/`crossReferencePopoverContent`/
  `displayGroups(for:)`/`CrossReferenceDisplayGroup`/`crossReferenceTargetLabel`
  (VerseZoomView 전용 버전 — `TranslationColumnView`의 동명 함수는 메인
  읽기 화면 자체 아이콘 팝오버용으로 완전히 별개이며 이번 변경과 무관해
  그대로 뒀다)을 삭제했다.

**3) 확대보기 성경구절 — 한자 있는 단어를 색으로 표시**

- `VerseAnnotationRenderer.VerseTextSegment`에 `hasHanja: Bool` 필드 추가 —
  `hasCrossReference`와 완전히 같은 원리(경계점 기반 조각 분해로 이 조각이
  어느 한자 단어 범위에 통째로 덮여 있는지 판정). `HanjaWordAnnotation`의
  `rangeStart`/`rangeEnd`는 이미 그 번역본 원문 기준 절대 UTF-16 오프셋이라
  (모델 자체 문서화 — "자가 치유 재탐색을 하지 않는다") 관주/형광펜과 달리
  `anchorText` 재탐색이 필요 없었다.
- `buildLines(...)`/`selectionModeAttributedText(...)` 둘 다
  `hanjaWords: [HanjaWordAnnotation] = []` 매개변수를 추가로 받는다 — 표시
  모드와 선택 모드(드래그로 새 구간 고를 때)가 시각적으로 어긋나지 않게
  둘 다 반영했다(이전 라운드들에서 이미 확립된 "두 모드 일관성" 원칙,
  README "이어서 11차/12차 수정" 등 참고).
- 새 색상 상수 `VerseAnnotationRenderer.hanjaWordTextColor = .brown` —
  형광펜 배경 5색(노랑/초록/파랑/분홍/보라), 밑줄(주황, 표시/관주), 메모
  글자색(파랑)과 겹치지 않는 색으로 새로 골랐다.
- 우선순위 — 메모 글자색이 있으면 그게 우선(기존 규칙 유지), 메모가 없고
  한자 단어면 갈색, 둘 다 아니면 기존 본문 색. `AnnotatedVerseFlowView.
  segmentView`와 `selectionModeAttributedText` 양쪽에 동일한 우선순위로
  구현했다.
- `AnnotatedVerseFlowView`/`SelectableVerseTextView`(iOS `UIViewRepresentable`
  / macOS `NSViewRepresentable` 두 변형 전부)에 `hanjaWords` 프로퍼티를
  추가하고, `VerseZoomView`의 두 호출부(표시 모드/선택 모드) 모두 이미 있던
  `hanjaWords` 계산 프로퍼티(이어서 63에서 한자 뜻풀이 영역용으로 신설한
  것)를 그대로 넘겼다 — 새 데이터 조회 경로를 추가하지 않고 기존 값을
  재사용했다.

### 정적 검증

수정한 5개 파일(`VerseZoomView.swift`, `VerseAnnotationRenderer.swift`,
`AnnotatedVerseFlowView.swift`, `SelectableVerseTextView.swift`,
`CrossReferenceTargetPicker.swift`) 전부 괄호·중괄호·대괄호 균형 스크립트로
재확인 — 전부 이상 없음. 삭제한 심볼(`isCrossReferencePopoverPresented`,
`crossReferencePopoverContent`, `CrossReferenceDisplayGroup`,
`crossReferenceTargetLabel`, `displayGroups(for:)`, VerseZoomView 전용
버전들)을 프로젝트 전체에서 재검색해 남은 참조가 없음을 확인했다(같은
이름의 `TranslationColumnView` 버전은 별개 기능이라 의도적으로 그대로 둠).
`AnnotatedVerseFlowView(`/`SelectableVerseTextView(` 생성 호출부가
`VerseZoomView.swift` 한 곳뿐임을 확인해, 새로 추가한 `hanjaWords` 매개변수
누락으로 다른 곳이 깨질 가능성이 없음을 확인했다.

⚠️ Xcode 실제 빌드는 사용자 환경에서 직접 확인이 필요하다(이 세션에는
Xcode 툴체인이 없음).

## 이어서 65 (2026-08-15)

**사용자 요청**
> 확대보기 수정사항
> - 한자 뜻풀이 영역
>   - 그리드간 구분선 추가
>   - 가운데 정렬
>   - 음 훈 뜻풀이 1~2pt 더크게
>   - 한자 옆에 구체적 설명을 하는 링크 아이콘 추가
>     (https://hanja.dict.naver.com/#/search?query=한자)
>
> 성경 조회 수정
> - 난외주가 있으면 난외주에 해당하는 단어 왼쪽 상단(윗첨자) 숫자 추가
> - 성경구절 클릭했을 때 - 성경구절 밑으로 난외주 숫자순서대로 뜻을 표시할 것.

관주처럼 팝업을 없애는 트레이드오프가 있었던 지난 라운드와 달리 이번엔
"관주 클릭 → 삭제(X) 이전" 같은 기능 손실 우려가 없어 바로 구현했다. 다만
"성경 조회" 쪽 요청은 착수 전에 데이터 가용성부터 확인해야 했다 — 아래 참고.

**1) 확대보기 한자 뜻풀이 — 그리드 구분선/가운데 정렬/폰트/네이버 링크**

`VerseZoomView.hanjaGlossSection`을 `LazyVGrid`에서 SwiftUI `Grid`/`GridRow`로
바꿨다(구분선이 필요해지면서 — `LazyVGrid`는 칸 사이에 실제 선을 그릴 방법이
마땅치 않다). `Divider()`를 `GridRow` "안"에 두면 세로 구분선(칸 사이),
`GridRow` "밖"에 `.gridCellColumns(3)`으로 전체 폭을 채워 넣으면 가로
구분선(행 사이) — Apple 공식 패턴 그대로다. 셀 내용은 `VStack(alignment:
.center)`로 가운데 정렬. 음훈풀이 폰트는 `.subheadline`(약 15pt)에서
`.system(size: 16)`으로 1pt 키웠다(성경 구절 크기 17pt보다는 작게, 이전보다는
크게 — 두 요구를 동시에 만족). 한자 옆에는 `Link(destination:)` + 화살표
아이콘을 붙여 네이버 한자사전으로 연결한다 — URL이
`https://hanja.dict.naver.com/#/search?query=한자`처럼 해시(`#`) 뒤가
클라이언트 라우팅 경로라, `URLComponents.queryItems`로 만들면 물음표가
해시 "앞"(진짜 URL 쿼리)으로 잘못 조립돼 리터럴 문자열에 한자만 퍼센트
인코딩해 끼워 넣었다.

**2) 원본 데이터 재확인 — 02개역난외주.bdb가 아직 남아 있음을 확인**

"위첨자 위치"는 이어서 59에서 "절 단위 목록이면 충분하다"고 판단해 일부러
빼뒀던 정보다 — 이번 요청으로 그 판단을 뒤집으려면 원본 위치 정보가 필요한데,
그 정보는 그때 이미 만든 `MarginalNoteSeed.json`(텍스트만 담음)에는 없다.
다행히 사용자가 이 세션보다 훨씬 전에 업로드했던 원본 파일
(`02개역난외주.bdb`, `02개역국한문.bdb`)이 세션 업로드 폴더에 그대로 남아
있음을 확인해 — 다시 열어 정확한 위 첨자 위치까지 재추출할 수 있었다.
`02개역난외주.bdb`를 `ReferenceDataSource/`(다른 원본 bdb들과 같은 자리)로
복사해 앞으로는 세션 업로드 폴더에 의존하지 않게 했다.

**3) `ReferenceDataSource/extract_marginal_note_anchors.py`(신설) — 위첨자
앵커 위치 추출**

원본 HTML(`<SMALL><FONT COLOR="#FF6095"><SUP>①</SUP></FONT></SMALL>` = 앵커
마커, `<SMALL><FONT COLOR="#FF6095">〔뜻풀이〕</FONT></SMALL>` = 정의, 소제목은
`<FONT COLOR="#996699">...</FONT>`로 감싸져 여전히 제외)을 다시 파싱해, 마커가
나온 "청소된 텍스트" 기준 오프셋을 이 프로젝트가 실제 쓰는 `BibleDB.sqlite`
본문의 UTF-16 오프셋으로 맞춘다(정확히 일치하면 그대로, 안 맞으면 마커 직후
단어를 커서 전진 방식으로 다시 찾는 폴백 — 이어서 61 한자 주석 추출 때와
같은 원리). 최종 1,801개 각주 중 1,762개(97.8%) 위치를 성공적으로 맞췄고
(옛 표기 "찌"/"지" 등 철자 자체가 달라 글자 매칭이 실패하는 39개는 위치
없이 목록에만 남는다), 한자 주석 작업 때(99.69%)와 비슷한 수준의 손실률로
받아들였다.

⚠️ [작업 중 발견해 고친 버그 3건, 전부 이 스크립트의 모듈 docstring에도
기록]
1. 소제목 안에 성경 참조가 중첩된 경우(`〔노아의 아들들의 후예〔대상
   1:5-23〕〕`) — non-greedy 정규식이 안쪽 `</FONT>`에서 멈춰버려 바깥쪽
   `〕</FONT>`가 텍스트에 그대로 남았다. 이 부작용으로 예전
   `MarginalNoteSeed.json`(2,356개)에는 이런 "대상 1:5-23" 류의 소제목 딸린
   평행 구절 인용 556개가 실제로는 특정 단어 뜻풀이가 아닌데도 "각주"로
   잘못 섞여 있었다 — 이번 추출은 소제목을 통째로 정확히 제거하므로 이
   556개는 사용자의 원래 결정("소제목 제외")대로 더 이상 각주로 나오지
   않는다(1,801개가 진짜 단어 단위 각주다).
2. 소제목이 절 "중간"에 나오는 경우(6건, 새 장이 이전 절 끝에 이어 붙는
   구조) — `^` 앵커 때문에 문자열 맨 앞에서만 지워지던 것을 고쳤다.
3. 각주 정의 자체에 또 `〔...〕`가 중첩된 경우(대상18:11 각주) — 안쪽
   첫 `〕`에서 멈추던 것을 한 겹까지 허용하도록 고쳤다.
   ⚠️ [알려진 손실, 그대로 둠] 사 1:2 각주 하나는 원본 자체의 태그 순서가
   깨져 있어(다른 색상 코드까지 섞임) 정규식으로 복구 불가 판단, 1개만
   건너뛴다.

**4) 데이터 파이프라인 갱신**

- `MarginalNoteSeed.json`(재생성) — `notes: [str]`에서 `notes:
  [{note_text, anchor_offset}]`로 형식 변경(`anchor_offset`은 위치를 못 찾은
  39건만 null).
- `build_reference_data.py` — `MarginalNotes` 테이블에 `anchor_offset
  INTEGER`(nullable) 컬럼 추가, 새 JSON 형식에 맞춰 삽입 로직 수정.
  `ReferenceData.sqlite` 재생성(관주/한자주석/한자사전 3개 테이블은 그대로,
  `MarginalNotes`만 2,356행 → 1,801행 + `anchor_offset` 컬럼).

**5) Swift 모델/저장소**

- `VerseAnnotations.swift` — `VerseMarginalNote`에 `anchorOffset: Int?`
  신설(`HanjaWordAnnotation`처럼 "자가 치유" 재탐색 없이, 미리 계산된 UTF-16
  절대 오프셋을 그대로 쓴다). 상단 "의도적으로 단순화" 주석을 이번 결정으로
  되돌린다는 내용으로 갱신.
- `ReferenceDataStore.marginalNotes(...)` — `anchor_offset` 컬럼을 함께
  읽는다. `sqlite3_column_type(...) == SQLITE_NULL`로 NULL을 명시적으로
  구분한다(`sqlite3_column_int`로 무조건 정수로 읽으면 NULL이 0이 돼
  "0번째 글자 앞"과 "위치 정보 없음"이 뒤섞인다).

**6) 본문 렌더링 — 위첨자 삽입 + 절 선택 시 하단 목록**

- `VerseAnnotationRenderer.attributedContentWithHanja`를
  `attributedContentWithInlineAnnotations`로 확장 개편 — 한자 괄호 병기와
  난외주 위첨자, 두 종류의 "삽입"을 하나의 목록으로 모아 오프셋 내림차순
  하나로 처리한다(둘 중 하나만 먼저 다 처리하면 나머지 종류의 저장된
  오프셋이 밀려서 안 맞게 된다 — 반드시 섞어서 한 번에 뒤에서부터). 위첨자는
  원본과 같은 동그라미 숫자 글리프(①②③..., `circledNumeral(_:)` 신설)를
  작은 크기로 삽입한다. 새 색상 상수 `marginalNoteMarkerColor = .purple`
  (형광펜/밑줄/메모색/한자색과 안 겹치는 색).
- `TranslationColumnView.VerseRow` — `shouldShowMarginalNoteMarkers`(위첨자가
  있는 각주가 하나라도 있으면 true, 한자와 달리 표시 모드 설정에 안 묶임)
  신설. `verseContentText`가 `shouldShowInlineHanja || shouldShowMarginalNoteMarkers`
  일 때 통합 렌더러를 타도록 조건을 넓혔다.
- "성경구절 클릭했을 때 밑으로 뜻을 표시" — 기존 절 선택 상태(`isSelected`,
  클립보드 복사용으로 절을 탭하면 켜지는 그 토글, 한자 "탭하면 보기"도 이미
  재사용 중)를 세 번째 용도로 재사용했다. `VerseRow.body`의 최상위를
  `HStack`에서 `VStack`으로 한 겹 감싸(배경/테두리/선택 표시줄도 이 바깥
  `VStack`으로 이동), 그 아래에 `isSelected && !marginalNotes.isEmpty`일 때
  `marginalNoteFootnoteList`(번호 + 뜻풀이 세로 목록, 본문 안 위첨자와 같은
  `circledNumeral` 번호 매기기)를 덧붙인다. 위치를 못 찾은 39건도(위첨자는
  없지만) 이 목록에는 그대로 나온다 — 번호와 뜻풀이 자체는 여전히 유효한
  정보라서다.

### 정적 검증

- 수정/신설 Swift 파일 5개(`VerseZoomView.swift`, `TranslationColumnView.swift`,
  `VerseAnnotationRenderer.swift`, `VerseAnnotations.swift`,
  `ReferenceDataStore.swift`) 전부 괄호·중괄호·대괄호 균형 스크립트로 재확인
  — 전부 이상 없음. 이 라운드 중 균형 스크립트 자체의 오탐 1건을 발견해
  고쳤다 — 문자열 리터럴에 `https://`가 들어 있으면(네이버 URL) `//` 줄
  주석 제거를 문자열 스트리핑보다 먼저 적용할 때 그 지점에서 줄이
  잘못 잘려 나가 거짓 불균형으로 보였다 — 이번부터는 항상 문자열
  스트리핑을 먼저 적용한다.
- `attributedContentWithHanja`(구 이름) 잔여 참조를 프로젝트 전체에서
  재검색해 남은 곳이 없음을 확인(단일 호출부만 있었고 그 자리에서 새
  이름으로 교체됨).
- `extract_marginal_note_anchors.py`/`build_reference_data.py` 둘 다
  `python3 -m py_compile`로 문법 오류 없음을 확인, 실제로 재실행해
  `ReferenceData.sqlite`가 정상적으로 재생성됨을 확인(MarginalNotes 1,801행,
  나머지 3개 테이블은 이전과 행 개수 동일).
- 표본 검증 — 창2:12("베델리엄"/〔진주〕, offset 18)과 창4:7("소원은"/
  〔사모가〕, offset 52 — 이 절은 뒷부분에 "다스릴찌니라"/"다스릴지니라"
  철자 불일치가 있는데도 앵커 자체는 정확히 찾음) 둘 다 실제
  `BibleDB.sqlite` 본문에서 해당 오프셋이 정확히 그 단어 시작 위치를
  가리키는지 직접 대조해 확인했다.

⚠️ [범위 밖, 명확히 플래그] 이번 위첨자/하단 목록 기능은 "성경 조회"
(메인 읽기 화면, `TranslationColumnView`)에만 적용했다 — 사용자 메시지가
"확대보기 수정사항"과 "성경 조회 수정"을 서로 다른 절로 나눠 요청해, 확대보기
(`VerseZoomView`)의 성경 구절 표시는 이번 범위에 포함하지 않았다(이어서 59가
같은 이유로 확대보기의 각주 아이콘 자체를 범위 밖으로 뒀던 것과 같은 판단).
필요하면 다음 라운드에서 `VerseAnnotationRenderer.buildLines(...)`에도 같은
`marginalNotes` 파라미터를 추가하면 된다.

⚠️ Xcode 실제 빌드는 사용자 환경에서 직접 확인이 필요하다(이 세션에는
Xcode 툴체인이 없음).

## 이어서 66 (2026-08-15)

**사용자 피드백(원문)**
> 확대보기 수정사항
> - 한자 뜻풀이 영역
>   - 그리드간 구분선 추가 -> 가로로 구분선? 그리드가 2개 열로 된거라면 열을
>     구분하는 가운데 세로 선을 구분선으로 넣는게 상식적이지 않나? 이런것까지
>     설명해야 하나? 모르면 물어보던가.
> - 난외주 설명을 2pt정도 더 키울 수 있도록.

이어서 65에서 구현한 "그리드간 구분선"에 대한 정정 요청이다.

**1) 세로 구분선이 행마다 끊어지던 문제**

이어서 65에서는 `Grid`/`GridRow`로 칸 사이 세로선 + 행 사이 가로선을 둘 다
넣었다고 기록했는데, 실제로는 `GridRow` 안의 `Divider()`가 그 행 하나의
높이만큼만 그려져 행이 여러 개(단어가 3쌍 이상)면 세로선이 행마다 끊어진
조각들로 보였다 — 사용자가 기대한 "가운데를 관통하는 연속된 세로 구분선"이
아니었다. `Grid`는 여러 `GridRow`에 걸쳐 이어지는 셀(행 병합)을 지원하지
않아 이 구조로는 근본적으로 고칠 수 없었다.

`VerseZoomView.hanjaGlossSection`을 `Grid`/`GridRow`에서 평범한
`VStack`(행)+`HStack`(칸) 구조로 다시 바꾸고, 전체 콘텐츠 위에
`.overlay { Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 1) }`를
얹어 폭 1pt짜리 세로선 하나가 모든 행의 높이를 그대로 관통하게 했다(overlay
콘텐츠는 너비만 고정하면 높이는 부모 뷰 크기를 그대로 받는다). 행 사이
가로 구분선은 그대로 평범한 `Divider()`(HStack 밖 VStack에 두면 자동으로
가로선이 된다)로 유지했다.

**2) 난외주 설명 폰트 크기**

`marginalNoteFootnoteList`(절 선택 시 성경 조회 화면 하단 목록, 유일하게
구현돼 있는 화면)의 `.caption`(약 12pt)을 14pt로 키웠다. 확대보기에는 아직
난외주 기능 자체가 없어(이어서 65에서 범위 밖으로 명시), 어느 화면 기준인지
사용자에게 직접 확인 후 진행했다.

### 정적 검증

수정한 2개 파일(`VerseZoomView.swift`, `TranslationColumnView.swift`) 괄호·
중괄호·대괄호 균형 스크립트로 재확인 — 전부 이상 없음. `Grid`/`GridRow`
잔여 참조를 파일 내 재검색해 코드 상에는 더 이상 없음을 확인(주석 설명
문구에만 옛 방식 언급으로 남아 있음).

⚠️ Xcode 실제 빌드는 사용자 환경에서 직접 확인이 필요하다(이 세션에는
Xcode 툴체인이 없음).

## 이어서 67 (2026-08-15)

**사용자 질의(원문)**
> 난외주 번호는 개역난외주의 태그안에 있는 번호를 유지했는가? 아님 그냥
> 너의 생각에 옳은 대로 넣었는가?

이어서 65에서 구현한 위첨자/각주 번호가 사실은 앱이 절마다 임의로 새로
매긴 번호였다는 점을 실측으로 확인하고, 사용자 선택에 따라 원본 태그 글자
그대로 쓰도록 바로잡았다.

**1) 검증 — 원본 번호를 유지하지 않았다**

`extract_marginal_note_anchors.py`(이어서 65)는 `<SUP>...</SUP>` 안의 실제
캡처 문자열(마커 글자, group(1))을 애초에 버리고 마커의 "위치"만 썼다.
`VerseAnnotationRenderer.circledNumeral(index+1)`이 절 안에서 항상 1번부터
①②③...으로 새로 번호를 매겼는데, 원본 `02개역난외주.bdb`를 다시 열어
실측한 결과:
- 원본 번호는 절 단위가 아니라 장(chapter) 전체에 걸쳐 이어진다(창4:1=①,
  창4:7=②, 창4:16=③ — 각각 그 절에 각주가 하나씩뿐인데도 절마다 1로
  리셋되지 않는다).
- 같은 단어가 한 절 안에 반복되면 같은 번호를 재사용하기도 한다(창10:25 —
  "나눔"이 두 번 나오는데 둘 다 원본에서 ①).
- 마커 글자가 항상 ①~⑩만은 아니다(`*` 275건, ⑪·⑫도 소수 등장).
- 전체 1,616개 각주 있는 절 중 929개(약 57%)가 "절마다 1부터"라는 앱의
  가정과 실제 원본 번호가 달랐다.

사용자에게 "지금처럼 절 안에서 1부터 순차 vs 원본 글자 그대로" 중 선택을
물었고, "원본 글자 그대로"를 선택했다.

**2) 파이프라인 — marker_text 추가**

- `extract_marginal_note_anchors.py` — `clean_and_extract`가 `SUP_RE.
  match(...).group(1)`(원본 마커 글자)을 `markers` 리스트로 함께 수집해
  반환하도록 변경(기존엔 오프셋만 기록하고 버렸음). `main()`이 앵커 매칭
  성공/실패 여부와 무관하게 각 노트에 `marker_text`를 채워 넣는다(위치를
  못 찾은 39건도 원본 글자는 그대로 있으므로 marker_text는 채워진다).
  재실행 결과는 이어서 65와 동일(절 1,615/각주 1,801/오프셋 매칭
  97.83%) — 이번 변경은 추출 결과 자체가 아니라 부가 필드만 늘렸다.
- `build_reference_data.py` — `MarginalNotes` 테이블에 `marker_text TEXT`
  (nullable) 컬럼 추가, 삽입 로직이 `note.get("marker_text")`를 함께 쓴다.
  `ReferenceData.sqlite` 재빌드(MarginalNotes 1,801행, 나머지 3개 테이블
  행 개수 동일).

**3) Swift 모델/저장소/렌더링**

- `VerseAnnotations.swift` — `VerseMarginalNote`에 `markerText: String?`
  신설.
- `ReferenceDataStore.marginalNotes(...)` — SQL에 `marker_text` 컬럼 추가,
  TEXT라 `note_text`와 같은 패턴으로 읽는다(별도 NULL 분기 불필요).
- `VerseAnnotationRenderer.attributedContentWithInlineAnnotations` — 위첨자
  삽입 시 `circledNumeral(index+1)` 대신 `note.markerText`를 그대로 쓴다
  (nil이거나 빈 문자열이면 그 각주는 위첨자를 안 붙인다 — 원본에 없던
  마커를 만들어 붙이지 않기 위해). 이제 위첨자 생성에 배열 인덱스가
  전혀 관여하지 않는다.
- `circledNumeral(_:)` 함수 자체를 삭제(더 이상 아무도 호출하지 않음,
  프로젝트 전체 재검색으로 코드상 잔여 호출 없음을 확인 — 주석 설명
  문구에만 옛 방식 언급으로 남아 있음).
- `TranslationColumnView.marginalNoteFootnoteList` — 목록 번호도
  `note.markerText ?? ""`로 바꿔, 본문 위첨자와 항상 같은 원본 번호를
  보여준다.

### 정적 검증

- 수정한 4개 파일(`VerseAnnotationRenderer.swift`, `TranslationColumnView.
  swift`, `VerseAnnotations.swift`, `ReferenceDataStore.swift`) 괄호·중괄호·
  대괄호 균형 스크립트로 재확인 — 전부 이상 없음.
- `circledNumeral` 잔여 호출을 프로젝트 전체에서 재검색해 코드상 없음을
  확인(주석 설명 문구에만 남음).
- `VerseMarginalNote(` 생성 호출부가 `ReferenceDataStore.swift` 한 곳뿐임을
  확인 — 라벨 인자라 새 `markerText` 파라미터 추가로 다른 곳이 깨질 가능성
  없음.
- `extract_marginal_note_anchors.py`/`build_reference_data.py` 둘 다
  `python3 -m py_compile` 통과, 실제로 재실행해 결과 수치(절/각주 개수,
  매칭률)가 이어서 65와 동일함을 확인(marker_text 필드만 추가됨).
- 표본 검증 — 창10:25("나눔" 두 각주, 둘 다 marker_text `①`), 창4:1/4:7/
  4:16(각각 ①/②/③, 절이 아니라 장 전체 이어짐)이 SQLite 재빌드 결과에
  그대로 반영됐는지 직접 조회해 확인했다.

⚠️ Xcode 실제 빌드는 사용자 환경에서 직접 확인이 필요하다(이 세션에는
Xcode 툴체인이 없음).
