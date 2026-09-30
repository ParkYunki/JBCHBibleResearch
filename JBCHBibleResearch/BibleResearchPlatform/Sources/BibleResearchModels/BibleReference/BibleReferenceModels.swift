import Foundation

// 번역본 1개 = SQLite 파일 1개 패턴의 정적 참조 데이터라 CloudKit에 동기화하지 않는다.
// 그래서 SwiftData @Model이 아니라 순수 Swift 값 타입 + 읽기 전용 SQLite 접근
// (BibleReferenceStore.swift)으로 구현한다.
//
// 번들 기본 파일과 사용자 추가 번역본 파일은 스키마가 다를 수 있어 `BibleVerse.versionCode`는
// 옵셔널이며, `BibleReferenceStore`가 파일을 열 때 `version_code` 컬럼 존재 여부를
// 런타임에 확인(`PRAGMA table_info`)해 SQL을 맞춘다.

/// 원본 `BibleVerses(uid, book_id, chapter, verse, content, paragraph)` 대응.
/// `versionCode`는 해당 파일에 `version_code` 컬럼이 있을 때만 채워진다.
public struct BibleVerse: Sendable, Hashable {
    public let uid: Int
    /// 이 절이 속한 번역본 코드. SQLite 파일에 `version_code` 컬럼이 없으면 nil.
    /// `TranslationRegistry.code`와 표기 규칙(대소문자, "GAE"/"개역개정" 등)이 일치하는지는
    /// 대조되지 않았다.
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
    /// 이 책의 표준 장 수(예: 창세기 50, 시편 150). 화면 레이어가 매번 BibleReferenceStore를
    /// 쿼리하지 않고 알 수 있게 한다. 값은 books.json(번들 리소스)에서 그대로 온다.
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
/// 이 패키지는 `books.json` 리소스를 포함하지 않으므로 `Bundle.module`에 의존하지 않고,
/// 리소스를 가진 앱 타겟이 자신의 Bundle을 넘기도록 설계했다.
public enum BooksCatalog {
    public static func load(from bundle: Bundle, resourceName: String = "books") throws -> [Book] {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw BibleReferenceError.resourceNotFound(resourceName)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([Book].self, from: data)
    }
}

/// `LocalizedError`를 함께 채택해 `error.localizedDescription`도 `description`과 같은
/// 한국어 문구를 돌려준다.
public enum BibleReferenceError: Error, LocalizedError, CustomStringConvertible {
    case resourceNotFound(String)
    case databaseOpenFailed(path: String, code: Int32)
    case statementPrepareFailed(code: Int32)
    case stepFailed(code: Int32)
    /// 이 파일에 `version_code` 컬럼이 있는데(= 번역본이 여러 개 섞여 있을 수 있는
    /// 파일) versionCode 없이 조회를 시도한 경우. 컬럼이 없으면 애초에 이 에러가
    /// 발생하지 않는다 — versionCode 없이 조회해도 안전한 파일이라는 뜻이므로.
    case versionCodeRequired
    /// `BibleVerses`(번들 스키마)도 `Bible`(사용자 추가 번역본 스키마)도 없는 SQLite 파일.
    /// 파일 자체를 못 연 `databaseOpenFailed`와 구분된다.
    case unrecognizedSchema(path: String)
    /// `TranslationSearchIndex`(사용자 추가 번역본용 보조 FTS5 인덱스) 파일을 열지 못했을 때.
    /// 호출부는 LIKE 검색으로 폴백한다(SearchViewModel.searchVerses).
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
