import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

// SQLite3의 C 매크로 `SQLITE_TRANSIENT`는 Swift로 import되지 않아 직접 정의한다.
// 바인딩 시점에 SQLite가 텍스트를 즉시 복사하므로 이후 Swift 문자열이 해제돼도 안전하다.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// 번역본 SQLite 파일(정적 참조 데이터, CloudKit 동기화 대상 아님)을 여는 읽기 전용 리더.
// 번들 기본 테이블(Resources/BibleDB.sqlite)과 TranslationRegistry.sqliteFileReference가
// 가리키는 사용자 추가 번역본 파일을 모두 이 타입으로 연다.
//
// 두 파일은 테이블/컬럼 이름이 다른 별개의 스키마다.
//   - 번들 기본: `BibleVerses(uid, book_id, chapter, verse, content, paragraph)`, `version_code` 없음.
//   - 사용자 추가(sqlite/bdb): `Bible(id, book, chapter, verse, btext)`, `paragraph`/`version_code` 없음.
//
// `init`에서 `sqlite_master`로 어느 테이블이 있는지 판별하고, 컬럼 이름 차이는 SELECT의
// `AS` 별칭(`uid`/`book_id`/`content`)으로 흡수한다. `version_code`/`paragraph`는 다른 파일이
// 갖고 있을 경우에 대비해 `PRAGMA table_info`로 존재 여부를 감지한다.
//
// 스레딩: 스레드 안전을 보장하지 않는다. 인스턴스당 sqlite3 커넥션 하나이며,
// 동시 사용 시 직렬화는 호출부 책임이다(또는 스레드별 인스턴스).
public final class BibleReferenceStore {
    private var handle: OpaquePointer?
    public let filePath: String

    /// 이 파일의 테이블에 `version_code` 컬럼이 있는지. `init`에서 한 번만 확인해 캐시한다.
    public let hasVersionCodeColumn: Bool

    /// 실제 테이블 이름(`BibleVerses` 또는 `Bible`). `init`의 `sqlite_master` 조회로 확정된다.
    private let tableName: String
    /// 절 고유 id 컬럼의 실제 이름(`uid` 또는 `id`) — SELECT 절에서 항상 `AS uid`로
    /// 별칭을 붙여 통일한다.
    private let uidColumn: String
    /// 책 번호 컬럼의 실제 이름(`book_id` 또는 `book`) — WHERE/ORDER BY에는 이
    /// 실제 이름을 써야 한다(별칭은 SELECT 목록에서만 유효).
    private let bookColumn: String
    /// 본문 컬럼의 실제 이름(`content` 또는 `btext`).
    private let contentColumn: String
    /// `paragraph` 컬럼 존재 여부. 사용자 추가 번역본(`Bible` 스키마)엔 원래 없다 —
    /// 없으면 `BibleVerse.paragraph`는 항상 nil이다.
    private let hasParagraphColumn: Bool

    public init(filePath: String) throws {
        self.filePath = filePath
        var db: OpaquePointer?
        // SQLITE_OPEN_READONLY — 정적 참조 데이터이므로 쓰기 접근을 허용하지 않는다.
        let flags = SQLITE_OPEN_READONLY
        let openResult = sqlite3_open_v2(filePath, &db, flags, nil)
        guard openResult == SQLITE_OK, let db else {
            sqlite3_close(db)
            throw BibleReferenceError.databaseOpenFailed(path: filePath, code: openResult)
        }

        if Self.tableExists(db: db, table: "BibleVerses") {
            tableName = "BibleVerses"
            uidColumn = "uid"
            bookColumn = "book_id"
            contentColumn = "content"
        } else if Self.tableExists(db: db, table: "Bible") {
            tableName = "Bible"
            uidColumn = "id"
            bookColumn = "book"
            contentColumn = "btext"
        } else {
            sqlite3_close(db)
            throw BibleReferenceError.unrecognizedSchema(path: filePath)
        }

        self.handle = db
        self.hasVersionCodeColumn = Self.columnExists(db: db, table: tableName, column: "version_code")
        self.hasParagraphColumn = Self.columnExists(db: db, table: tableName, column: "paragraph")
    }

    deinit {
        sqlite3_close(handle)
    }

    /// `sqlite_master`에서 테이블 존재 여부를 확인한다 — 스키마 판별(`BibleVerses`
    /// vs `Bible`)의 첫 단계.
    private static func tableExists(db: OpaquePointer, table: String) -> Bool {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?", -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        sqlite3_bind_text(statement, 1, table, -1, SQLITE_TRANSIENT)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    /// `PRAGMA table_info(table)`을 돌려 컬럼 이름 목록에서 찾는다. `table`은 이
    /// 파일 내부에서 스키마 판별로 이미 확정된 값(`BibleVerses`/`Bible`)만 들어오므로
    /// SQL 인젝션 위험 없이 문자열 보간으로 넣는다(PRAGMA는 테이블명에 파라미터
    /// 바인딩을 지원하지 않는다).
    private static func columnExists(db: OpaquePointer, table: String, column: String) -> Bool {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        while sqlite3_step(statement) == SQLITE_ROW {
            // table_info 결과의 컬럼 인덱스 1이 컬럼 이름(name).
            guard let namePointer = sqlite3_column_text(statement, 1) else { continue }
            if String(cString: namePointer) == column {
                return true
            }
        }
        return false
    }

    /// `(book_id, chapter, verse)` 조회. 파일에 `version_code` 컬럼이 있으면
    /// `versionCode`가 반드시 필요하다(없으면 `.versionCodeRequired` 에러 — 어느
    /// 번역본의 절인지 알 수 없는 상태로 임의의 행(LIMIT 1)을 반환하지 않기 위함).
    /// 컬럼이 없는 파일(번들 기본 테이블, 사용자 추가 번역본 등)에서는 `versionCode`를
    /// 무시한다.
    public func verse(bookId: Int, chapter: Int, verse: Int, versionCode: String? = nil) throws -> BibleVerse? {
        if hasVersionCodeColumn && versionCode == nil {
            throw BibleReferenceError.versionCodeRequired
        }
        var sql = "SELECT \(selectColumns) FROM \(tableName) WHERE \(bookColumn) = ? AND chapter = ? AND verse = ?"
        if hasVersionCodeColumn { sql += " AND version_code = ?" }
        sql += " LIMIT 1"

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        sqlite3_bind_int(statement, 1, Int32(bookId))
        sqlite3_bind_int(statement, 2, Int32(chapter))
        sqlite3_bind_int(statement, 3, Int32(verse))
        if hasVersionCodeColumn, let versionCode {
            sqlite3_bind_text(statement, 4, versionCode, -1, SQLITE_TRANSIENT)
        }

        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { return nil }
        guard step == SQLITE_ROW else {
            throw BibleReferenceError.stepFailed(code: step)
        }
        return Self.makeVerse(from: statement, hasVersionCode: hasVersionCodeColumn, hasParagraph: hasParagraphColumn)
    }

    /// 장 전체 조회(S1 다중 번역본 병렬 뷰의 기본 조회 단위). `verse(bookId:chapter:verse:versionCode:)`와
    /// 동일한 규칙: 파일에 version_code 컬럼이 있으면 필수.
    public func verses(bookId: Int, chapter: Int, versionCode: String? = nil) throws -> [BibleVerse] {
        if hasVersionCodeColumn && versionCode == nil {
            throw BibleReferenceError.versionCodeRequired
        }
        var sql = "SELECT \(selectColumns) FROM \(tableName) WHERE \(bookColumn) = ? AND chapter = ?"
        if hasVersionCodeColumn { sql += " AND version_code = ?" }
        sql += " ORDER BY verse ASC"

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        sqlite3_bind_int(statement, 1, Int32(bookId))
        sqlite3_bind_int(statement, 2, Int32(chapter))
        if hasVersionCodeColumn, let versionCode {
            sqlite3_bind_text(statement, 3, versionCode, -1, SQLITE_TRANSIENT)
        }

        var results: [BibleVerse] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw BibleReferenceError.stepFailed(code: step)
            }
            results.append(Self.makeVerse(from: statement, hasVersionCode: hasVersionCodeColumn, hasParagraph: hasParagraphColumn))
        }
        return results
    }

    /// 특정 책의 실제 최대 장 번호. 해당 book_id의 절이 하나도 없으면 nil.
    public func maxChapter(bookId: Int, versionCode: String? = nil) throws -> Int? {
        if hasVersionCodeColumn && versionCode == nil {
            throw BibleReferenceError.versionCodeRequired
        }
        var sql = "SELECT MAX(chapter) FROM \(tableName) WHERE \(bookColumn) = ?"
        if hasVersionCodeColumn { sql += " AND version_code = ?" }

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        sqlite3_bind_int(statement, 1, Int32(bookId))
        if hasVersionCodeColumn, let versionCode {
            sqlite3_bind_text(statement, 2, versionCode, -1, SQLITE_TRANSIENT)
        }

        let step = sqlite3_step(statement)
        guard step == SQLITE_ROW else {
            if step == SQLITE_DONE { return nil }
            throw BibleReferenceError.stepFailed(code: step)
        }
        if sqlite3_column_type(statement, 0) == SQLITE_NULL { return nil }
        return Int(sqlite3_column_int(statement, 0))
    }

    /// `content LIKE '%query%'` 키워드 검색(사용자 추가 번역본의 `btext`는 `contentColumn`으로 흡수).
    /// 성경순 정렬 후 `limit`으로 자르며, `limit`이 nil이면 자르지 않는다.
    /// `%`/`_`는 이스케이프하지 않아 입력하면 LIKE 패턴으로 해석된다.
    public func searchVerses(query: String, versionCode: String? = nil, limit: Int? = nil) throws -> [BibleVerse] {
        if hasVersionCodeColumn && versionCode == nil {
            throw BibleReferenceError.versionCodeRequired
        }
        guard !query.isEmpty else { return [] }
        var sql = "SELECT \(selectColumns) FROM \(tableName) WHERE \(contentColumn) LIKE ?"
        if hasVersionCodeColumn { sql += " AND version_code = ?" }
        sql += " ORDER BY \(bookColumn) ASC, chapter ASC, verse ASC"
        if limit != nil { sql += " LIMIT ?" }

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        let likePattern = "%\(query)%"
        sqlite3_bind_text(statement, 1, likePattern, -1, SQLITE_TRANSIENT)
        var nextIndex: Int32 = 2
        if hasVersionCodeColumn, let versionCode {
            sqlite3_bind_text(statement, nextIndex, versionCode, -1, SQLITE_TRANSIENT)
            nextIndex += 1
        }
        if let limit { sqlite3_bind_int(statement, nextIndex, Int32(limit)) }

        var results: [BibleVerse] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw BibleReferenceError.stepFailed(code: step)
            }
            results.append(Self.makeVerse(from: statement, hasVersionCode: hasVersionCodeColumn, hasParagraph: hasParagraphColumn))
        }
        return results
    }

    /// `TranslationSearchIndex`의 보조 FTS5 인덱스 빌드용 전체 절 조회. `version_code` 컬럼이
    /// 있으면 versionCode가 필수다. book_id/chapter/verse 오름차순으로 반환한다.
    public func allVerses(versionCode: String? = nil) throws -> [BibleVerse] {
        if hasVersionCodeColumn && versionCode == nil {
            throw BibleReferenceError.versionCodeRequired
        }
        var sql = "SELECT \(selectColumns) FROM \(tableName)"
        if hasVersionCodeColumn { sql += " WHERE version_code = ?" }
        sql += " ORDER BY \(bookColumn) ASC, chapter ASC, verse ASC"

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        if hasVersionCodeColumn, let versionCode {
            sqlite3_bind_text(statement, 1, versionCode, -1, SQLITE_TRANSIENT)
        }

        var results: [BibleVerse] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw BibleReferenceError.stepFailed(code: step)
            }
            results.append(Self.makeVerse(from: statement, hasVersionCode: hasVersionCodeColumn, hasParagraph: hasParagraphColumn))
        }
        return results
    }

    /// 이 파일에 들어있는 `version_code` 목록. 컬럼이 없는 파일은 여러 번역본을 구분할 필요가
    /// 없으므로 에러가 아니라 빈 배열을 반환한다.
    public func availableVersionCodes() throws -> [String] {
        guard hasVersionCodeColumn else { return [] }
        let sql = "SELECT DISTINCT version_code FROM \(tableName) ORDER BY version_code ASC"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        var codes: [String] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw BibleReferenceError.stepFailed(code: step)
            }
            codes.append(String(cString: sqlite3_column_text(statement, 0)))
        }
        return codes
    }

    /// 스키마별 컬럼 이름 차이(`uid`/`id`, `book_id`/`book`, `content`/`btext`)를 `AS`로 통일하고,
    /// 존재하는 선택 컬럼(`version_code`/`paragraph`)에 맞춰 목록·순서를 만든다.
    /// `makeVerse`는 이 순서에만 의존한다.
    private var selectColumns: String {
        var columns = ["\(uidColumn) AS uid"]
        if hasVersionCodeColumn { columns.append("version_code") }
        columns.append("\(bookColumn) AS book_id")
        columns.append("chapter")
        columns.append("verse")
        columns.append("\(contentColumn) AS content")
        if hasParagraphColumn { columns.append("paragraph") }
        return columns.joined(separator: ", ")
    }

    private static func makeVerse(from statement: OpaquePointer?, hasVersionCode: Bool, hasParagraph: Bool) -> BibleVerse {
        let uid = Int(sqlite3_column_int64(statement, 0))
        var index: Int32 = 1
        let versionCode: String?
        if hasVersionCode {
            versionCode = String(cString: sqlite3_column_text(statement, index))
            index += 1
        } else {
            versionCode = nil
        }
        let bookId = Int(sqlite3_column_int(statement, index)); index += 1
        let chapter = Int(sqlite3_column_int(statement, index)); index += 1
        let verse = Int(sqlite3_column_int(statement, index)); index += 1
        let content = String(cString: sqlite3_column_text(statement, index)); index += 1
        let paragraph: Int?
        if hasParagraph {
            paragraph = sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, index))
        } else {
            paragraph = nil
        }
        return BibleVerse(uid: uid, versionCode: versionCode, bookId: bookId, chapter: chapter,
                           verse: verse, content: content, paragraph: paragraph)
    }
}
