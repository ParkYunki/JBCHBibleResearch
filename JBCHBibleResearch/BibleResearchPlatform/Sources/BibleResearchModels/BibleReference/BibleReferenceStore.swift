import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

// SQLite3의 C 매크로 `SQLITE_TRANSIENT`(`((sqlite3_destructor_type)-1)`)는 매크로라서
// ClangImporter가 Swift로 들여오지 못한다 — Swift+SQLite3를 쓸 때 흔히 겪는 지점이라
// 직접 정의해야 한다. 텍스트를 바인딩할 때 SQLite가 원본 버퍼를 참조만 하지 않고
// 즉시 복사하게 해서, 바인딩 이후 Swift 문자열이 해제돼도 안전하도록 만든다.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// 근거: bible-research-platform-schema.md 1장 — 번역본 SQLite 파일은 CloudKit 동기화
// 대상이 아닌 정적 참조 데이터이므로, SwiftData가 아니라 이 읽기 전용 리더로 직접 연다.
// 사용 위치: 번들 기본 테이블(Resources/BibleDB.sqlite)과, 6.7의
// TranslationRegistry.sqliteFileReference가 가리키는 사용자 추가 번역본 파일을
// 이 타입으로 열어 조회한다.
//
// ⚠️⚠️ [2026-08-07, 사용자가 실제 스키마 제공 — 이전 가정을 대체] 이전 라운드들은
// "번들 기본 테이블과 사용자 추가 번역본이 같은 테이블(`BibleVerses`)을 쓰고,
// 파일에 따라 `version_code` 컬럼 유무만 다르다"고 가정했다(2026-08-06 "정책
// 확정"). 사용자가 실제 사용자 추가 번역본 파일(sqlite/bdb)의 스키마를 직접
// 알려줘서 그 가정이 틀렸다는 게 확인됐다 — 실제로는 **테이블 이름과 컬럼 이름
// 자체가 다른, 완전히 별개의 스키마**다:
//
//   - **번들 기본 테이블**(`Resources/BibleDB.sqlite`): `BibleVerses(uid, book_id,
//     chapter, verse, content, paragraph)`, `version_code` 없음(1개 번역본만).
//   - **사용자 추가 번역본**(sqlite 또는 bdb 확장자): `Bible(id, book, chapter,
//     verse, btext)` — `paragraph`도 `version_code`도 없다. 즉 "한 파일 = 번역본
//     하나"이고, 이전에 추측했던 "한 파일에 여러 번역본이 version_code로 섞여
//     있을 수 있다"는 시나리오는 사용자가 알려준 실제 스키마에는 없다.
//
// 이 타입은 이제 `init` 시점에 `sqlite_master`에서 `BibleVerses`/`Bible` 중 어느
// 테이블이 있는지 확인해 스키마를 판별하고, 컬럼 이름 차이는 SELECT 절의 `AS`
// 별칭으로 흡수한다(`uid`/`book_id`/`content`로 통일) — 그래서 `makeVerse`를 포함한
// 나머지 로직은 스키마 종류를 몰라도 된다. `version_code`/`paragraph`는 여전히
// `PRAGMA table_info`로 존재 여부를 감지한다(사용자가 준 스키마엔 없지만, 혹시
// 다른 사용자 추가 파일이 이 컬럼을 추가로 갖고 있는 경우까지 방어하기 위해 —
// 하드코딩으로 완전히 배제하지 않았다).
//
// ⚠️ 이 동적 스키마 판별 로직 자체는 실제 사용자 추가 번역본 파일로 아직
// 재검증되지 않았다(스키마 텍스트만 받았고 실물 파일로 열어본 적은 없다).
//
// 스레딩 참고: 이 타입은 스레드 안전을 자체적으로 보장하지 않는다. sqlite3 커넥션
// 하나를 여러 스레드에서 동시에 쓰지 않아야 하며, 필요하면 호출부에서 직렬화하거나
// 스레드별로 별도 인스턴스를 만들어야 한다 — 원본 문서에 동시성 정책이 명시돼 있지
// 않아 가장 단순하고 안전한 "인스턴스당 단일 커넥션, 외부 직렬화 책임은 호출부" 원칙으로
// 구현했다.
public final class BibleReferenceStore {
    private var handle: OpaquePointer?
    public let filePath: String

    /// 이 파일의 실제 테이블에 `version_code` 컬럼이 있는지. `init` 시점에
    /// `PRAGMA table_info`로 한 번만 확인해 캐시한다. 사용자가 확인해 준 두 스키마
    /// (`BibleVerses`/`Bible`) 중 어느 쪽에도 원래는 없는 컬럼이지만, 방어적으로
    /// 계속 동적 감지한다.
    public let hasVersionCodeColumn: Bool

    /// 실제 테이블 이름(`BibleVerses` 또는 `Bible`) — 아래 세 컬럼 이름 매핑과 함께
    /// `init`에서 `sqlite_master` 조회로 확정된다.
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

    /// 특정 책의 실제 최대 장 번호. 화면 레이어(장 선택 피커)가 "이 책이 몇 장까지
    /// 있는지" 임의로 가정하지 않고 실제 데이터로 확인할 수 있도록 2026-08-06 추가.
    /// 해당 book_id의 절이 하나도 없으면 nil(책이 존재하지 않거나 아직 비어 있음).
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

    /// S11(통합 검색) 키워드 검색 — `content LIKE '%query%'`(사용자 추가 번역본은
    /// 실제 컬럼명이 `btext`이지만 `contentColumn`으로 흡수한다). sqlite-vec 같은
    /// 전문 검색 확장 없이 순수 LIKE만 쓴다(schema.md 4장이 의미검색만 vDSP
    /// brute-force로 확정했을 뿐, 키워드 검색 방식은 명시하지 않았다 — LIKE가 가장
    /// 단순하고 확실한 선택이라고 판단했다). `%`/`_` 같은 LIKE 와일드카드 문자를
    /// 사용자가 그대로 입력하면 의도치 않게 패턴으로 해석될 수 있으나, 검색 UI
    /// 특성상 큰 위험은 아니라고 보고 별도 이스케이프는 하지 않았다.
    // [2026-08-25 변경] 사용자 요청 — "limit 50을 해제할 수 있는 방법(더보기
    // 버튼)도 추가할 것." 이 경로는 이미 `ORDER BY ... LIMIT ?`(성경순 정렬 후
    // 자름)이라 순서 버그는 없었지만, `searchVersesFullText`(FTS5 경로, 번들
    // 개역한글 전용)와 짝을 맞춰 여기도 `limit`을 `Int?`로 바꿔 `nil`이면
    // 자르지 않게 한다 — 사용자 추가 번역본(NKJV/NASB 등, 이 LIKE 경로를
    // 쓴다)도 "더보기"로 50건을 넘는 전체 결과를 볼 수 있어야 하기 때문.
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

    /// [2026-09-05 추가] `TranslationSearchIndex`가 사용자 추가 번역본에 대한
    /// 보조 FTS5 인덱스를 빌드할 때 필요한, 이 파일에 들어있는 절 전체 조회.
    /// `verses(bookId:chapter:versionCode:)`와 동일한 규칙(파일에 version_code
    /// 컬럼이 있으면 필수)이되 WHERE 절이 없을 뿐이다 — 화면에 표시할 목적이
    /// 아니라 인덱스 빌드 한 번(번역본 추가 후 첫 검색 시점)에만 쓰이므로
    /// 정렬 기준은 중요하지 않지만, 다른 조회 메서드와의 일관성을 위해 book_id/
    /// chapter/verse 오름차순으로 반환한다.
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

    /// 이 파일에 실제로 들어있는 `version_code` 목록. `version_code` 컬럼이 없는
    /// 파일(번역본이 하나뿐인 파일 — 번들 기본 테이블, 그리고 사용자가 확인해 준
    /// 실제 스키마상 사용자 추가 번역본도 여기 해당한다)에서는 빈 배열을 반환한다 —
    /// 에러가 아니라 "이 파일은 애초에 여러 번역본을 구분할 필요가 없다"는 정상
    /// 상태다.
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

    /// `hasVersionCodeColumn`/`hasParagraphColumn` 여부에 따라 SELECT 절의 컬럼
    /// 목록·순서를 맞춘다. 실제 컬럼 이름이 스키마마다 달라도(`uid`/`id`,
    /// `book_id`/`book`, `content`/`btext`) `AS`로 항상 같은 이름(`uid`/`book_id`/
    /// `content`)으로 별칭을 붙이므로, `makeVerse(from:hasVersionCode:hasParagraph:)`는
    /// 이 순서만 알면 되고 실제 스키마 종류는 몰라도 된다.
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
