import Foundation

// 근거: bible-research-platform-schema.md 1장 — "번역본 1개 = SQLite 파일 1개" 패턴이며
// 정적 참조 데이터이므로 CloudKit에 동기화하지 않는다. 그래서 이 영역은 SwiftData
// @Model이 아니라 순수 Swift 값 타입 + 별도 읽기 전용 SQLite 접근으로 구현한다
// (BibleReferenceStore.swift 참고).
//
// ⚠️ [2026-08-06 수정, 사용자 확인 반영] 처음엔 실제 `Resources/BibleDB.sqlite`에
// `version_code` 컬럼이 있는 걸 보고 "이 파일 하나에 여러 번역본이 섞여 있다"고
// 잘못 판단해 모든 쿼리에 versionCode를 필수로 넣었습니다. 실제 정책은 다릅니다:
//
//   - **번들 기본 테이블**(`Resources/BibleDB.sqlite`): 번역본 1개만 들어있음 →
//     version_code 불필요(schema.md 1장 원안 그대로).
//   - **사용자가 추가 등록하는 번역본**: 여러 개를 등록할 수 있고, 그 파일들에는
//     여러 번역본이 함께 들어있을 수 있음 → version_code 필요.
//
// 즉 "파일마다 스키마가 다를 수 있다"는 뜻이라, `BibleVerse.versionCode`를 옵셔널로
// 바꾸고 `BibleReferenceStore`가 매 파일을 열 때 `version_code` 컬럼 존재 여부를
// 런타임에 확인(`PRAGMA table_info`)해서 그에 맞는 SQL을 쓰도록 했습니다
// (BibleReferenceStore.swift 참고). 이렇게 하면 번들 파일이든 사용자 추가 파일이든
// 같은 코드 하나로 열 수 있고, 호출부가 미리 "이 파일이 어떤 종류인지" 알 필요가
// 없습니다.

/// 원본 `BibleVerses(uid, book_id, chapter, verse, content, paragraph)` 대응.
/// `versionCode`는 해당 파일에 `version_code` 컬럼이 있을 때만 채워진다(위 ⚠️ 참고).
public struct BibleVerse: Sendable, Hashable {
    public let uid: Int
    /// 이 절이 속한 번역본 코드. 해당 SQLite 파일에 `version_code` 컬럼이 없으면
    /// (번들 기본 테이블처럼 번역본이 하나뿐인 파일) nil입니다. 컬럼이 있을 때는
    /// `TranslationRegistry.code`와 매칭되는 값으로 추정되나, 두 값의 실제 표기
    /// 규칙이 서로 일치하는지는 아직 대조하지 못했습니다(예: 대소문자, "GAE"/"개역개정"
    /// 같은 표기 차이 가능성) — 앱 레이어에서 첫 사용 전 대조 필요.
    public let versionCode: String?
    public let bookId: Int
    public let chapter: Int
    public let verse: Int
    public let content: String
    /// 문단 단위 렌더링용 그룹 필드. nil 가능(원본 스키마가 NOT NULL을 명시하지 않음).
    public let paragraph: Int?

    public init(
        uid: Int, versionCode: String?, bookId: Int, chapter: Int, verse: Int,
        content: String, paragraph: Int?
    ) {
        self.uid = uid
        self.versionCode = versionCode
        self.bookId = bookId
        self.chapter = chapter
        self.verse = verse
        self.content = content
        self.paragraph = paragraph
    }
}

/// 원본 `Books(book_id, testament, order_index, name_ko, name_original, abbreviation)`.
/// 66권 규모라 SQLite 대신 앱 번들 내 정적 JSON으로 충분하다는 결정(schema.md 1장)에
/// 따라 Codable 구조체 + JSON 디코딩으로 구현한다.
public struct Book: Codable, Sendable, Hashable, Identifiable {
    public enum Testament: String, Codable, Sendable {
        case old, new
    }

    public var id: Int { bookId }
    public let bookId: Int
    public let testament: Testament
    public let orderIndex: Int
    public let nameKo: String
    public let nameOriginal: String
    public let abbreviation: [String]
    /// 이 책의 표준 장 수(예: 창세기 50, 시편 150). 화면 레이어(장 선택 피커)가
    /// "이 책이 몇 장까지 있는지"를 매번 BibleReferenceStore로 쿼리하지 않고 즉시
    /// 알 수 있도록 2026-08-06 추가.
    ///
    /// ⚠️ [출처] 이 값 자체는 books.json(앱 번들 리소스)에서 오며, 이 struct는 그
    /// 값을 그대로 실어 나를 뿐이다. books.json은 사용자가 이전에 실제로 만들어
    /// 배포했던 앱(BibleSeminarPresentationForIOS)의 KoreanUtil.swift에 있던
    /// BibleBook.all 데이터를 그대로 옮긴 것 — 표준 66권 장 수와 정확히 일치하는지
    /// 새로 검증한 게 아니라 실제 운영 이력이 있는 데이터를 신뢰한 것이다.
    public let chapterCount: Int

    public init(
        bookId: Int, testament: Testament, orderIndex: Int,
        nameKo: String, nameOriginal: String, abbreviation: [String], chapterCount: Int
    ) {
        self.bookId = bookId
        self.testament = testament
        self.orderIndex = orderIndex
        self.nameKo = nameKo
        self.nameOriginal = nameOriginal
        self.abbreviation = abbreviation
        self.chapterCount = chapterCount
    }
}

/// `books.json`(66권 고정 목록)을 로드한다.
/// ⚠️ 이 패키지는 아직 실제 `books.json` 리소스를 포함하지 않는다 — 66권의 한글/원어
/// 이름, 축약형 목록(14.4에서 "요/요한/요한복음" 같은 축약형까지 매칭 사전으로 쓸
/// 계획이라는 언급만 있고 실제 데이터는 이번 구현 범위 밖) 데이터를 별도로 채워
/// 넣어야 한다. 그래서 `Bundle.module`(리소스가 없으면 생성되지 않음)에 의존하지 않고,
/// 실제 리소스를 갖고 있는 앱 타겟이 자신의 Bundle을 넘기도록 설계했다.
public enum BooksCatalog {
    public static func load(from bundle: Bundle, resourceName: String = "books") throws -> [Book] {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw BibleReferenceError.resourceNotFound(resourceName)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([Book].self, from: data)
    }
}

/// [2026-08-07 수정] `LocalizedError`를 함께 채택한다 — 이전에는 `CustomStringConvertible`만
/// 채택해서, 호출부(`BibleReadingViewModel`/`SearchViewModel`)가 `error.localizedDescription`
/// (Swift 표준 프로퍼티)으로 이 에러를 표시하면 `.description`이 아니라 Foundation의
/// 일반 문구("작업을 완료할 수 없습니다")가 대신 나오는 문제가 있었다 — S12 README
/// 라운드에서 "범위 밖으로 남긴 기존 버그"로 기록해 뒀던 것을, 원본 문서(screens.md
/// 4.3/6.7)를 다시 읽고 "새 기기 동기화 중" 메시지가 실제로 사용자에게 정확히
/// 보여야 한다는 요구를 재확인한 김에 닫았다.
public enum BibleReferenceError: Error, LocalizedError, CustomStringConvertible {
    case resourceNotFound(String)
    case databaseOpenFailed(path: String, code: Int32)
    case statementPrepareFailed(code: Int32)
    case stepFailed(code: Int32)
    /// 이 파일에 `version_code` 컬럼이 있는데(= 번역본이 여러 개 섞여 있을 수 있는
    /// 파일) versionCode 없이 조회를 시도한 경우. 컬럼이 없으면 애초에 이 에러가
    /// 발생하지 않는다 — versionCode 없이 조회해도 안전한 파일이라는 뜻이므로.
    case versionCodeRequired
    /// 2026-08-07 추가 — `BibleVerses`(번들 스키마)도 `Bible`(사용자 추가 번역본
    /// 실제 확인된 스키마, BibleReferenceStore.swift 상단 주석 참고)도 없는 파일을
    /// 열었을 때. "SQLite 파일이긴 하지만 우리가 아는 두 스키마 중 어느 쪽도
    /// 아니다"라는 뜻 — `databaseOpenFailed`(파일 자체를 못 열었음)와는 다른 문제라
    /// 별도 케이스로 분리했다.
    case unrecognizedSchema(path: String)
    /// [2026-09-05 추가] `TranslationSearchIndex`(사용자 추가 번역본용 보조
    /// FTS5 인덱스) 파일을 열지 못했을 때. `databaseOpenFailed`와 별도 케이스로
    /// 둔 이유는 대상이 원본 번역본 파일이 아니라 앱이 로컬에 만든 보조 인덱스
    /// 파일이라 원인/조치가 다르기 때문(예: 캐시 디렉터리 접근 문제) — 호출부가
    /// 이 실패를 감지하면 기존 LIKE 검색으로 안전하게 폴백한다(SearchViewModel.
    /// searchVerses 참고).
    case indexOpenFailed(path: String, code: Int32)
    /// `TranslationSearchIndex` 빌드(가상 테이블 생성/데이터 삽입) 도중 실패.
    case indexBuildFailed(reason: String)

    public var description: String {
        switch self {
        case .resourceNotFound(let name):
            return "번들 리소스를 찾을 수 없습니다: \(name)"
        case .databaseOpenFailed(let path, let code):
            return "SQLite 파일을 열지 못했습니다(code \(code)): \(path)"
        case .statementPrepareFailed(let code):
            return "SQLite 쿼리 준비에 실패했습니다(code \(code))"
        case .stepFailed(let code):
            return "SQLite 쿼리 실행에 실패했습니다(code \(code))"
        case .versionCodeRequired:
            return "이 파일은 여러 번역본을 포함하고 있어 versionCode를 반드시 지정해야 합니다."
        case .unrecognizedSchema(let path):
            return "알 수 없는 성경 데이터베이스 형식입니다(BibleVerses/Bible 테이블을 찾을 수 없음): \(path)"
        case .indexOpenFailed(let path, let code):
            return "전문 검색 보조 인덱스를 열지 못했습니다(code \(code)): \(path)"
        case .indexBuildFailed(let reason):
            return "전문 검색 보조 인덱스 생성에 실패했습니다: \(reason)"
        }
    }

    public var errorDescription: String? { description }
}
