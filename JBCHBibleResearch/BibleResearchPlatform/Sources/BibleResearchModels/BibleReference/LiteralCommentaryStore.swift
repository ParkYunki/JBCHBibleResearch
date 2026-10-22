import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// [2026-10-12] 언어별 직역·번역 차이 설명 DB(`Resources/Literal_<언어>.sqlite`) 읽기 전용 접근.
// `OriginalTextStore`와 같은 이유로 raw SQLite3 C API를 쓴다(정적 참조 데이터, 스레드 안전은 호출부 책임).
//
// 스키마(생성 스크립트가 만든다):
//   CREATE TABLE LiteralText (
//     book_id INTEGER NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL,
//     text TEXT NOT NULL,            -- 그 언어의 절 단위 직역(AI 생성)
//     basis TEXT, generator TEXT, generated_at TEXT, review_status TEXT,
//     PRIMARY KEY(book_id, chapter, verse)) WITHOUT ROWID
//   CREATE TABLE TranslationDifference (
//     translation_code TEXT NOT NULL,  -- `TranslationRegistry.code`(예: "LSG1910")
//     book_id INTEGER NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL,
//     explanation TEXT NOT NULL,       -- 그 번역본과 원어(직역)의 차이 설명(AI 생성, 번역본의 언어)
//     generator TEXT, generated_at TEXT, review_status TEXT,
//     PRIMARY KEY(translation_code, book_id, chapter, verse)) WITHOUT ROWID
//   CREATE TABLE TranslationVerseHash (   -- [2026-10-21] 사용자 추가 번역본(본문 미배포)의 절 본문 지문. 없을 수 있다.
//     translation_code TEXT NOT NULL, book_id INTEGER NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL,
//     hash INTEGER NOT NULL, PRIMARY KEY(translation_code, book_id, chapter, verse)) WITHOUT ROWID
//
// 한국어(KRV)는 기존 `OriginalText.sqlite`의 `LiteralTranslation` 표를 그대로 쓴다(앱 레이어 `LiteralCommentaryService`).

public final class LiteralCommentaryStore {
    private var handle: OpaquePointer?
    public let filePath: String

    public init(filePath: String) throws {
        self.filePath = filePath
        var db: OpaquePointer?
        let openResult = sqlite3_open_v2(filePath, &db, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let db else {
            sqlite3_close(db)
            throw BibleReferenceError.databaseOpenFailed(path: filePath, code: openResult)
        }
        self.handle = db
    }

    deinit {
        sqlite3_close(handle)
    }

    /// 그 언어의 절 직역. 없으면 nil(정상 상태).
    public func literalText(bookId: Int, chapter: Int, verse: Int) throws -> String? {
        try singleText(
            sql: "SELECT text FROM LiteralText WHERE book_id = ? AND chapter = ? AND verse = ? LIMIT 1",
            code: nil, bookId: bookId, chapter: chapter, verse: verse
        )
    }

    /// 번역본 하나와 원어의 차이 설명. 없으면 nil(정상 상태).
    public func difference(translationCode: String, bookId: Int, chapter: Int, verse: Int) throws -> String? {
        try singleText(
            sql: """
                SELECT explanation FROM TranslationDifference
                WHERE translation_code = ? AND book_id = ? AND chapter = ? AND verse = ? LIMIT 1
                """,
            code: translationCode, bookId: bookId, chapter: chapter, verse: verse
        )
    }

    /// [2026-10-21] 사용자 추가 번역본 인식용 — 이 절의 본문 지문(`TranslationVerseHash.hash`)이 같은 번역본 코드들.
    /// 지문 표가 없는 DB면 빈 배열(정상 상태). 지문 규칙은 앱의 `VerseTextFingerprint`와 생성 스크립트 `ext_hashes.py`가 같다.
    public func translationCodes(matchingVerseHash hash: Int64, bookId: Int, chapter: Int, verse: Int) throws -> [String] {
        guard try hasTable("TranslationVerseHash") else { return [] }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = """
            SELECT translation_code FROM TranslationVerseHash
            WHERE book_id = ? AND chapter = ? AND verse = ? AND hash = ?
            """
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        sqlite3_bind_int(statement, 1, Int32(bookId))
        sqlite3_bind_int(statement, 2, Int32(chapter))
        sqlite3_bind_int(statement, 3, Int32(verse))
        sqlite3_bind_int64(statement, 4, hash)
        var codes: [String] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw BibleReferenceError.stepFailed(code: step) }
            if let cString = sqlite3_column_text(statement, 0) {
                codes.append(String(cString: cString))
            }
        }
        return codes
    }

    /// 표 존재 여부(파일이 읽기 전용이라 열린 동안 바뀌지 않으므로 한 번만 묻는다).
    private var tableExists: [String: Bool] = [:]

    private func hasTable(_ name: String) throws -> Bool {
        if let known = tableExists[name] { return known }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1", -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        sqlite3_bind_text(statement, 1, name, -1, SQLITE_TRANSIENT)
        let step = sqlite3_step(statement)
        guard step == SQLITE_ROW || step == SQLITE_DONE else { throw BibleReferenceError.stepFailed(code: step) }
        let exists = (step == SQLITE_ROW)
        tableExists[name] = exists
        return exists
    }

    private func singleText(sql: String, code: String?, bookId: Int, chapter: Int, verse: Int) throws -> String? {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        var index: Int32 = 1
        if let code {
            // SQLITE_TRANSIENT(`BibleReferenceStore`와 같은 상수): SQLite가 문자열을 복사하게 한다.
            sqlite3_bind_text(statement, index, code, -1, SQLITE_TRANSIENT)
            index += 1
        }
        sqlite3_bind_int(statement, index, Int32(bookId))
        sqlite3_bind_int(statement, index + 1, Int32(chapter))
        sqlite3_bind_int(statement, index + 2, Int32(verse))

        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { return nil }
        guard step == SQLITE_ROW else {
            throw BibleReferenceError.stepFailed(code: step)
        }
        guard let cString = sqlite3_column_text(statement, 0) else { return nil }
        let text = String(cString: cString)
        return text.isEmpty ? nil : text
    }
}
