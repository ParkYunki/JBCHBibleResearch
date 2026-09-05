import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

// SQLite3의 C 매크로 `SQLITE_TRANSIENT`는 매크로라서 ClangImporter가 Swift로
// 들여오지 못한다 — `TranslationSearchIndex.swift`/`BibleReferenceStore.swift`와
// 같은 이유로 이 파일에서도 별도로 정의한다(모듈 파일별로 반복 정의하는 게 이
// 코드베이스의 기존 패턴).
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// 근거: 사용자 요청(2026-09-05) — "개요/메모/개인 묵상/말씀 요약/연구문서 5개
// 카테고리의 전체 스캔에 대해서는 최적화/속도 개선 관점에서 다른 제안을 할 것"
// → "옵션 A(FTS5 보조 인덱스로 후보 축소), unicode61 사용(trigram 말고, 기본
// 성경 번역본 인덱스와 동일하게)"로 확정. `TranslationSearchIndex`(사용자 추가
// 번역본용, 번역본마다 별도 파일)와 목적은 같지만, 이 타입은 서로 다른 6개
// SwiftData 모델(BookOutline/ChapterSummary/UserMemo/VerseSummary/
// VersePhraseNote/SourceDocument)을 대상으로 하므로 파일을 6개로 쪼개지 않고
// `category`/`source_id` 컬럼으로 하나의 공유 FTS5 테이블 안에서 구분한다 —
// 이 6개는 전부 사용자가 계속 편집/추가하는 살아있는 콘텐츠라 번역본처럼
// "파일 하나 = 카테고리 하나"로 나눌 이유가 없고, 오히려 검색 쪽 호출부
// (`SearchViewModel`)가 매번 하나의 공유 DB 연결만 열면 되는 편이 단순하다.
//
// [설계 근거 — 왜 unicode61인가] 번들 성경 FTS5(`ReferenceDataStore.
// searchVersesFullText`)와 사용자 추가 번역본(`TranslationSearchIndex`)가 이미
// "trigram보다 unicode61+prefix가 한국어 조사 변화에 더 안정적"이라고 검증해
// 채택한 것과 동일한 토크나이저 — 사용자가 그 기존 결정과 일관되게 맞추도록
// 명시적으로 요청했다(2026-09-05, trigram 제안을 명시적으로 거절).
//
// ⚠️ [알려진 정확성 트레이드오프, 반드시 disclose] `unicode61`은 토큰(어절)
// 단위 매칭이라 이 인덱스는 "검색어로 시작하는 토큰"만 후보로 잡는다(질의는
// `"검색어"*` prefix 매치, 아래 `matchingSourceIds` 참고) — 예를 들어 "사랑"으로
// 검색하면 "사랑"/"사랑을"/"사랑하는" 토큰은 잡히지만, "내사랑"처럼 검색어가
// 토큰의 맨 앞이 아니라 중간/뒤에 오는 경우는 이 인덱스만으로는 후보에서
// 빠질 수 있다. 이건 이미 성경구절 전체 검색(번들 FTS5)이 갖고 있던 것과
// 정확히 같은 특성이고, 그 표준을 나머지 카테고리에도 그대로 맞추기로 한
// 것이 이번 요청의 취지다 — `SearchViewModel`이 이 인덱스를 "후보 좁히기"
// 용도로만 쓰고 최종 점수/발췌 계산 자체는 여전히 기존 `computeWordMatchScore`
// (순수 부분 문자열 스캔)를 그대로 쓰지만, 애초에 후보에 안 든 항목은 그
// 정밀 스캔 자체를 건너뛰므로 이 갭이 최종 결과에 그대로 전파된다.
//
// [쓰기 동기화] 이 인덱스는 각 모델의 저장 지점(자동저장 화면을 벗어날 때,
// 말씀메모 추가/수정 등)에서 그 항목 하나만 다시 채워 넣는(delete+insert)
// 방식으로 최신 상태를 유지한다 — 호출부 주석 참고. **삭제 훅은 두지 않았다**
// (근거: 항목이 실제로 삭제되면 검색 쪽이 매번 다시 하는 `modelContext.fetch`
// 결과에도 더 이상 나타나지 않으므로, 이 인덱스에 죽은 행이 남아 있어도
// "후보"로만 쓰이는 이 값이 실제 존재하지 않는 항목의 ID를 가리킬 뿐 최종
// 결과 join 단계에서 자연히 걸러진다 — 정확성에는 영향이 없고, SQLite 파일에
// 죽은 행이 누적되는 저장공간 문제만 남는다. 필요해지면 별도 정리 루틴을
// 추가할 수 있다).
//
// [백필] 이 기능 도입 이전부터 있던 기존 데이터(사용자당 카테고리별 최대
// ~2000건으로 확인됨, 2026-09-05)는 이 인덱스에 없다 — `SearchViewModel`이
// 검색 시점에 "이 카테고리에 이미 인덱싱된 ID 집합"과 방금 조회한 실제 데이터를
// 비교해, 누락된 항목만 그 자리에서 채워 넣는 자가 치유(self-healing) 방식으로
// 백필한다(`SourceDocument.cachedCombinedText` 백필과 같은 패턴) — 별도의
// 마이그레이션 진입점/플래그를 새로 만들지 않았다.
public enum UserContentSearchIndex {
    private static func indexFileURL(indexDirectory: URL) -> URL {
        indexDirectory.appendingPathComponent("user-content-fts.sqlite")
    }

    /// 파일이 없으면 새로 만들고, 있으면 그대로 연다. 테이블은 `CREATE VIRTUAL
    /// TABLE IF NOT EXISTS`라 이미 있어도 안전하다(매 호출마다 열고 닫는 구조라
    /// 반드시 멱등이어야 한다 — `TranslationSearchIndex.ensureBuilt`처럼 "파일
    /// 존재 여부로 한 번만 빌드"하는 대신, 이 테이블은 계속 갱신돼야 하므로
    /// 매번 연결한다).
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

    /// 항목이 완전히 삭제됐을 때 정리용(선택적 호출 — 위 상단 주석 "쓰기 동기화"
    /// 참고, 안 불러도 정확성엔 영향 없다).
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
    /// 질의 형태(따옴표로 감싼 리터럴 + prefix `*`)는 `TranslationSearchIndex.
    /// search`/`ReferenceDataStore.searchVersesFullText`와 완전히 동일하게
    /// 맞췄다 — 이 프로젝트가 이미 검증해 채택한 한국어 조사 대응 방식을 그대로
    /// 재사용한다. `category = ?` 조건과 `MATCH`를 같은 WHERE절에서 AND로
    /// 결합하는 방식은 SQLite 공식 문서(fts5.html, UNINDEXED 컬럼에 대한 일반
    /// SQL 비교 연산 + MATCH 병행 예시)로 확인했다.
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
