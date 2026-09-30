import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

// `SQLITE_TRANSIENT`는 C 매크로라 Swift로 임포트되지 않으므로 파일마다 별도로
// 정의한다(`BibleReferenceStore.swift`와 동일).
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// 사용자 추가 번역본용 FTS5 보조 인덱스. LIKE '%…%' 풀 테이블 스캔
// (`BibleReferenceStore.searchVerses`)을 대체해 번들 번역본과 같은 속도를 낸다.
//
// 번역본 원본 파일에는 직접 `CREATE VIRTUAL TABLE`을 하지 않는다 — 그 파일은
// CloudKit에서 내려온 `sqliteData`를 그대로 써낸 읽기 전용 캐시본
// (`TranslationFileMaterializer`)이라, 수정하면 원본을 훼손하고 다음 동기화/재
// materialize 때 덮어써질 수 있다. 대신 번들 번역본과 같은 패턴
// (`ReferenceDataStore.searchVersesFullText`)으로 번역본마다 별도의 보조 SQLite
// 파일에 FTS5 인덱스를 둔다. 스키마는 빌드 스크립트의 `VerseSearchIndex`
// (book_id/chapter/verse UNINDEXED + content, tokenize='unicode61')와 동일하게 맞춰,
// 검색 결과 형태(`FullTextVerseMatch`)와 질의 방식(따옴표로 감싼 prefix 매치)을
// 번들 경로와 통일한다(unicode61+prefix가 trigram보다 한국어 조사 변화에 안정적).
//
// 인덱스는 번역본당 한 번만 만들어져 로컬 파일로 남는다(`ensureBuilt`가 파일
// 존재 여부를 먼저 확인).
//
// 스레딩: 내부적으로 동시성을 보장하지 않는다 — 호출부(`SearchViewModel`, 메인
// 액터에서 직렬 호출)가 같은 registryID를 여러 스레드에서 동시에 빌드/조회하지
// 않는다는 전제다.
public enum TranslationSearchIndex {
    /// `indexDirectory` 아래의 `<registryID>-fts.sqlite` 보조 인덱스 파일 경로.
    /// 호출부가 번역본 원본 파일이 있는 디렉터리를 넘기므로, 이 패키지
    /// (BibleResearchModels)가 앱 타겟의 디렉터리 정책을 몰라도 된다.
    private static func indexFileURL(indexDirectory: URL, registryID: UUID) -> URL {
        indexDirectory.appendingPathComponent("\(registryID.uuidString)-fts.sqlite")
    }

    /// 보조 인덱스가 이미 만들어져 있는지 확인한다. 검색 경로는 인덱스가 없으면
    /// 만들지 않고 LIKE로 폴백한다 — 빌드는 `TranslationFileMaterializer.writeLocalCopy`
    /// (번역본이 이 기기에 처음 써지는 시점)에서만 일어난다.
    public static func indexExists(registryID: UUID, indexDirectory: URL) -> Bool {
        FileManager.default.fileExists(atPath: indexFileURL(indexDirectory: indexDirectory, registryID: registryID).path)
    }

    /// 보조 인덱스 파일이 있으면 즉시 반환하고, 없으면 `sourceStore`의 절 전체를
    /// 읽어 새로 만든다. 실패 시 만들다 만 파일이 다음 시도를 오염시키지 않도록
    /// 삭제 후 에러를 던진다.
    @discardableResult
    public static func ensureBuilt(
        sourceStore: BibleReferenceStore, registryID: UUID, indexDirectory: URL, versionCode: String? = nil
    ) throws -> URL {
        let url = indexFileURL(indexDirectory: indexDirectory, registryID: registryID)
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        let rows = try sourceStore.allVerses(versionCode: versionCode)

        var db: OpaquePointer?
        let openFlags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        guard sqlite3_open_v2(url.path, &db, openFlags, nil) == SQLITE_OK, let db else {
            let code = sqlite3_errcode(db)
            sqlite3_close(db)
            try? FileManager.default.removeItem(at: url)
            throw BibleReferenceError.indexOpenFailed(path: url.path, code: code)
        }
        defer { sqlite3_close(db) }

        func fail(_ reason: String) -> BibleReferenceError {
            try? FileManager.default.removeItem(at: url)
            return BibleReferenceError.indexBuildFailed(reason: reason)
        }

        guard sqlite3_exec(db, """
            CREATE VIRTUAL TABLE VerseSearchIndex USING fts5(
                book_id UNINDEXED, chapter UNINDEXED, verse UNINDEXED, content,
                tokenize = 'unicode61'
            )
            """, nil, nil, nil) == SQLITE_OK else {
            throw fail(String(cString: sqlite3_errmsg(db)))
        }

        guard sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil) == SQLITE_OK else {
            throw fail(String(cString: sqlite3_errmsg(db)))
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            db, "INSERT INTO VerseSearchIndex (book_id, chapter, verse, content) VALUES (?, ?, ?, ?)", -1, &statement, nil
        ) == SQLITE_OK else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            throw fail(String(cString: sqlite3_errmsg(db)))
        }

        for row in rows {
            sqlite3_bind_int(statement, 1, Int32(row.bookId))
            sqlite3_bind_int(statement, 2, Int32(row.chapter))
            sqlite3_bind_int(statement, 3, Int32(row.verse))
            sqlite3_bind_text(statement, 4, row.content, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                let message = String(cString: sqlite3_errmsg(db))
                sqlite3_finalize(statement)
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                throw fail(message)
            }
            sqlite3_reset(statement)
        }
        sqlite3_finalize(statement)

        guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else {
            throw fail(String(cString: sqlite3_errmsg(db)))
        }
        return url
    }

    /// 보조 인덱스에서 FTS5 MATCH 검색. `ReferenceDataStore.searchVersesFullText`와
    /// 같은 질의 형태(따옴표로 감싼 리터럴 + prefix `*`, 정경순 tie-break)를 쓴다 —
    /// 두 경로의 결과가 같은 `KeywordMatchScorer` 재점수/정렬로 합쳐지므로
    /// 결과 형태가 같아야 한다.
    public static func search(
        registryID: UUID, indexDirectory: URL, matching query: String, limit: Int? = nil
    ) throws -> [FullTextVerseMatch] {
        guard !query.isEmpty else { return [] }
        let url = indexFileURL(indexDirectory: indexDirectory, registryID: registryID)

        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            let code = sqlite3_errcode(db)
            sqlite3_close(db)
            throw BibleReferenceError.indexOpenFailed(path: url.path, code: code)
        }
        defer { sqlite3_close(db) }

        let escaped = query.replacingOccurrences(of: "\"", with: "\"\"")
        let matchQuery = "\"\(escaped)\"*"

        var sql = """
            SELECT book_id, chapter, verse, content
            FROM VerseSearchIndex WHERE VerseSearchIndex MATCH ?
            ORDER BY book_id ASC, chapter ASC, verse ASC
            """
        if limit != nil { sql += " LIMIT ?" }

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.indexBuildFailed(reason: String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_text(statement, 1, matchQuery, -1, SQLITE_TRANSIENT)
        if let limit { sqlite3_bind_int(statement, 2, Int32(limit)) }

        var results: [FullTextVerseMatch] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw BibleReferenceError.indexBuildFailed(reason: String(cString: sqlite3_errmsg(db)))
            }
            let bookId = Int(sqlite3_column_int(statement, 0))
            let chapter = Int(sqlite3_column_int(statement, 1))
            let verse = Int(sqlite3_column_int(statement, 2))
            let content = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
            results.append(FullTextVerseMatch(bookId: bookId, chapter: chapter, verse: verse, content: content, rank: 0))
        }
        return results
    }
}
