import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

// `SQLITE_TRANSIENT`는 C 매크로라 Swift로 임포트되지 않으므로 파일마다 따로 정의한다
// (`TranslationSearchIndex.swift`/`BibleReferenceStore.swift`와 같은 패턴).
// 코드베이스의 기존 패턴).
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// 개요/메모/개인 묵상/말씀 요약/연구문서 카테고리의 전체 스캔을 줄이기 위한 FTS5 보조 인덱스
// (후보 축소용). 6개 SwiftData 모델(BookOutline/ChapterSummary/UserMemo/VerseSummary/
// VersePhraseNote/SourceDocument)을 `category`/`source_id` 컬럼으로 구분해 하나의 공유 FTS5
// 테이블에 담는다 — 전부 사용자가 계속 편집하는 콘텐츠라 번역본(`TranslationSearchIndex`)처럼
// 파일을 나눌 이유가 없고, 호출부(`SearchViewModel`)도 DB 연결 하나만 열면 된다.
//
// 토크나이저는 `unicode61`(+prefix) — 번들 성경 FTS5(`ReferenceDataStore.searchVersesFullText`)와
// `TranslationSearchIndex`가 채택한 것과 같은, 한국어 조사 변화에 더 안정적인 방식이다.
//
// ⚠️ 알려진 한계: 토큰(어절) 단위 prefix 매치(`"검색어"*`)라 검색어로 "시작하는" 토큰만 후보가
// 된다. 예: "사랑"은 "사랑을"/"사랑하는"은 잡지만 "내사랑"은 후보에서 빠질 수 있다.
// `SearchViewModel`은 이 인덱스를 후보 좁히기에만 쓰고 최종 점수/발췌는 기존 부분 문자열 스캔
// (`computeWordMatchScore`)으로 계산하지만, 후보에 없는 항목은 그 스캔도 건너뛰므로 이 한계가
// 결과에 그대로 전파된다.
//
// 쓰기 동기화: 각 모델의 저장 지점에서 항목 하나만 delete+insert로 갱신한다. 삭제 훅은 두지
// 않았다 — 인덱스는 "후보"로만 쓰이고 최종 결과는 `modelContext.fetch` 결과와 join되어 삭제된
// 항목은 자연히 걸러지므로, 죽은 행은 정확성에 영향이 없고 SQLite 파일 크기만 늘린다.
//
// 백필: 인덱스 도입 이전 데이터는 `SearchViewModel`이 검색 시점에 "이미 인덱싱된 ID 집합"과 실제
// 데이터를 비교해 누락분만 채워 넣는 자가 치유 방식으로 처리한다(`SourceDocument.cachedCombinedText`
// 백필과 같은 패턴). 별도 마이그레이션 진입점은 없다.
public enum UserContentSearchIndex {
    private static func indexFileURL(indexDirectory: URL) -> URL {
        indexDirectory.appendingPathComponent("user-content-fts.sqlite")
    }

    /// 파일이 없으면 새로 만들고, 있으면 그대로 연다. 매 호출마다 열고 닫으므로 `CREATE VIRTUAL
    /// TABLE IF NOT EXISTS`로 멱등해야 한다(이 테이블은 계속 갱신되므로 "한 번만 빌드"하지 않는다).
    private static func openDatabase(indexDirectory: URL) throws -> OpaquePointer {
        try FileManager.default.createDirectory(at: indexDirectory, withIntermediateDirectories: true)
        let url = indexFileURL(indexDirectory: indexDirectory)
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK, let db else {
            let code = sqlite3_errcode(db)
            sqlite3_close(db)
            throw BibleReferenceError.indexOpenFailed(path: url.path, code: code)
        }
        guard sqlite3_exec(db, """
            CREATE VIRTUAL TABLE IF NOT EXISTS UserContentIndex USING fts5(
                category UNINDEXED, source_id UNINDEXED, content,
                tokenize = 'unicode61'
            )
            """, nil, nil, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            throw BibleReferenceError.indexBuildFailed(reason: message)
        }
        return db
    }

    /// 지금 이 카테고리에 인덱싱돼 있는 `source_id` 전체 — 호출부가 방금
    /// 조회한 실제 데이터와 비교해 "아직 인덱싱 안 된" 항목만 `upsert`로
    /// 채워 넣는 자가 치유 백필에 쓴다.
    public static func existingSourceIds(category: String, indexDirectory: URL) -> Set<String> {
        guard let db = try? openDatabase(indexDirectory: indexDirectory) else { return [] }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT source_id FROM UserContentIndex WHERE category = ?", -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        sqlite3_bind_text(statement, 1, category, -1, SQLITE_TRANSIENT)
        var result = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let cString = sqlite3_column_text(statement, 0) {
                result.insert(String(cString: cString))
            }
        }
        return result
    }

    /// 항목 하나를 인덱스에 새로 넣거나(신규) 갈아 끼운다(수정) — 항상
    /// 먼저 같은 (category, source_id) 행을 지운 뒤 다시 넣으므로 몇 번을
    /// 호출해도 같은 결과다. `content`가 비어 있으면(예: 방금 지운 메모)
    /// 삭제만 하고 새로 넣지 않는다.
    public static func upsert(category: String, sourceId: String, content: String, indexDirectory: URL) throws {
        let db = try openDatabase(indexDirectory: indexDirectory)
        defer { sqlite3_close(db) }
        try deleteRow(db: db, category: category, sourceId: sourceId)
        guard !content.isEmpty else { return }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(
            db, "INSERT INTO UserContentIndex (category, source_id, content) VALUES (?, ?, ?)", -1, &statement, nil
        ) == SQLITE_OK else {
            throw BibleReferenceError.indexBuildFailed(reason: String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_text(statement, 1, category, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, sourceId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, content, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw BibleReferenceError.indexBuildFailed(reason: String(cString: sqlite3_errmsg(db)))
        }
    }

    /// 항목이 완전히 삭제됐을 때의 정리용(선택적 — 호출하지 않아도 정확성엔 영향 없다).
    public static func delete(category: String, sourceId: String, indexDirectory: URL) throws {
        let db = try openDatabase(indexDirectory: indexDirectory)
        defer { sqlite3_close(db) }
        try deleteRow(db: db, category: category, sourceId: sourceId)
    }

    private static func deleteRow(db: OpaquePointer, category: String, sourceId: String) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(
            db, "DELETE FROM UserContentIndex WHERE category = ? AND source_id = ?", -1, &statement, nil
        ) == SQLITE_OK else {
            throw BibleReferenceError.indexBuildFailed(reason: String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_text(statement, 1, category, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, sourceId, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw BibleReferenceError.indexBuildFailed(reason: String(cString: sqlite3_errmsg(db)))
        }
    }

    /// 이 카테고리 안에서 `query`가 "토큰 접두어"로 매치되는 `source_id` 집합.
    /// 질의 형태(따옴표 리터럴 + prefix `*`)는 `TranslationSearchIndex.search`/
    /// `ReferenceDataStore.searchVersesFullText`와 동일하다.
    public static func matchingSourceIds(category: String, indexDirectory: URL, matching query: String) throws -> Set<String> {
        guard !query.isEmpty else { return [] }
        let db = try openDatabase(indexDirectory: indexDirectory)
        defer { sqlite3_close(db) }

        let escaped = query.replacingOccurrences(of: "\"", with: "\"\"")
        let matchQuery = "\"\(escaped)\"*"

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(
            db, "SELECT source_id FROM UserContentIndex WHERE category = ? AND UserContentIndex MATCH ?", -1, &statement, nil
        ) == SQLITE_OK else {
            throw BibleReferenceError.indexBuildFailed(reason: String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_text(statement, 1, category, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, matchQuery, -1, SQLITE_TRANSIENT)

        var result = Set<String>()
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw BibleReferenceError.indexBuildFailed(reason: String(cString: sqlite3_errmsg(db)))
            }
            if let cString = sqlite3_column_text(statement, 0) {
                result.insert(String(cString: cString))
            }
        }
        return result
    }
}
