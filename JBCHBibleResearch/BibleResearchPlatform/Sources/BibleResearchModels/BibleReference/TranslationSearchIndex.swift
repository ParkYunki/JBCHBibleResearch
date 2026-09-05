import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

// SQLite3의 C 매크로 `SQLITE_TRANSIENT`는 매크로라서 ClangImporter가 Swift로
// 들여오지 못한다 — `BibleReferenceStore.swift`와 동일한 이유로 이 파일에서도
// 별도로 정의한다(모듈 파일별로 반복 정의하는 게 이 코드베이스의 기존 패턴).
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// 근거: 사용자 요청(2026-09-05) — "검색이 느리다" 문제 진단 중, 사용자 추가
// 번역본이 `BibleReferenceStore.searchVerses`(LIKE '%…%', 인덱스 불가한 풀
// 테이블 스캔)만 쓰고 있어 번들 번역본(FTS5)보다 훨씬 느리다는 게 확인됨.
// "사용자 추가 번역본에 대해서도 FTS5를 할 수 있도록 수정할 것" 요청에 따른
// 신설 타입.
//
// [설계 근거] 왜 번역본 원본 파일에 직접 `CREATE VIRTUAL TABLE`을 안 하는가 —
// `BibleReferenceStore`가 사용자 추가 번역본 파일을 항상 `SQLITE_OPEN_READONLY`로
// 여는 이유(그 파일 상단 주석)는 "동기화된 원본 바이트를 그대로 보관하는 정적
// 참조 데이터"이기 때문이다. 그 파일에 손을 대면(쓰기 모드 재오픈, 스키마 변경)
// 원본을 훼손할 위험이 있고, 이 파일은 애초에 CloudKit에서 내려온 `sqliteData`를
// 로컬에 그대로 써낸 캐시본(`TranslationFileMaterializer`)이라 다음 동기화/재
// materialize 때 그대로 덮어써질 수도 있다. 대신 번들 번역본이 이미 쓰고 있는
// 것과 동일한 패턴(`ReferenceDataStore.searchVersesFullText` — 원본 BibleDB.sqlite와
// 별개의 파일에 FTS5 인덱스를 둔다, `ReferenceDataSource/build_reference_data.py`의
// `build_verse_search_index` 참고)을 따라, 번역본마다 별도의 보조 SQLite 파일에
// FTS5 인덱스를 만든다. 스키마도 그 빌드 스크립트가 만드는 `VerseSearchIndex`
// (book_id/chapter/verse UNINDEXED + content, tokenize='unicode61')와 완전히
// 동일하게 맞춰, 검색 결과 형태(`FullTextVerseMatch`)와 질의 방식(따옴표로 감싼
// prefix 매치)을 번들 경로와 통일한다 — `ReferenceDataStore.searchVersesFullText`
// 상단의 실측 근거(trigram보다 unicode61+prefix가 한국어 조사 변화에 더 안정적)가
// 사용자 추가 번역본에도 동일하게 적용되기 때문이다.
//
// 인덱스는 번역본당 한 번만 만들어지고 로컬 파일로 남는다(호출부가 매 검색마다
// 다시 만들지 않도록 `ensureBuilt`가 파일 존재 여부를 먼저 확인) — 번역본을 처음
// 추가한 뒤 첫 검색 1회에서만 빌드 비용이 발생하고, 그 다음부터는 이미 만들어진
// 인덱스를 그대로 연다.
//
// 스레딩: `BibleReferenceStore`와 동일하게 이 타입도 내부적으로 동시성을
// 보장하지 않는다 — 호출부(`SearchViewModel`, 메인 액터에서 직렬 호출)가 여러
// 스레드에서 동시에 같은 registryID를 빌드/조회하지 않는다는 전제다.
public enum TranslationSearchIndex {
    /// `indexDirectory` 아래에 `<registryID>-fts.sqlite`로 보조 인덱스 파일을 둔다.
    /// 호출부가 이미 번역본 원본 파일을 연 디렉터리(`BibleReferenceStore.filePath`의
    /// 상위 디렉터리 — 사용자 추가 번역본이면 `TranslationFileMaterializer`가 관리하는
    /// 로컬 캐시 디렉터리)를 그대로 넘겨주므로, 이 타입 자체는 앱 레이어의 디렉터리
    /// 정책(`TranslationFileMaterializer.translationsDirectory()`)을 몰라도 된다 —
    /// 이 패키지(BibleResearchModels)는 앱 타겟에 의존할 수 없기 때문에 필요한 설계다.
    private static func indexFileURL(indexDirectory: URL, registryID: UUID) -> URL {
        indexDirectory.appendingPathComponent("\(registryID.uuidString)-fts.sqlite")
    }

    /// [2026-09-05 추가] 사용자 요청 — "인덱스는 번역본 업로드 시점에만 만들고,
    /// 검색 시점엔 만들지 않는다(기존 번역본은 신경 쓰지 않는다)." 검색 경로
    /// (`SearchViewModel.searchVerses`)는 이제 이 함수로 "이미 만들어져 있는지"만
    /// 확인하고, 없으면 만들지 않고 그냥 LIKE로 폴백한다 — 빌드는 오직
    /// `TranslationFileMaterializer.writeLocalCopy`(번역본이 이 기기에 처음
    /// 로컬로 써지는 시점)에서만 일어난다.
    public static func indexExists(registryID: UUID, indexDirectory: URL) -> Bool {
        FileManager.default.fileExists(atPath: indexFileURL(indexDirectory: indexDirectory, registryID: registryID).path)
    }

    /// 보조 인덱스가 이미 있으면(파일 존재) 아무 것도 하지 않고 즉시 반환한다.
    /// 없으면 `sourceStore`(이미 열려 있는 해당 번역본의 `BibleReferenceStore`)의
    /// 절 전체를 읽어 새로 만든다 — 실패 시(디스크 문제, 빌드 도중 오류 등) 이미
    /// 만들다 만 파일이 남아 다음 시도를 오염시키지 않도록 삭제 후 에러를 던진다.
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

    /// 이미 만들어진 보조 인덱스에서 FTS5 MATCH 검색. `ReferenceDataStore.
    /// searchVersesFullText`와 완전히 동일한 질의 형태(따옴표로 감싼 리터럴 +
    /// prefix `*`, 정경순 tie-break)를 쓴다 — 두 경로의 결과가 이후 같은
    /// `KeywordMatchScorer` 재점수/정렬 로직으로 합쳐지므로, 결과의 "모양"이
    /// 같아야 한다(그 함수 상단 주석의 이스케이프/정렬 근거를 그대로 따름).
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
