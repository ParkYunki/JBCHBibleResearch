import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

// [2026-08-09 신설] `OriginalText.sqlite`(단일 테이블 `original_words`, 변환 스크립트는
// 앱 README 참고) 읽기 전용 접근. `BibleReferenceStore`와 같은 이유로 SwiftData가
// 아니라 raw SQLite3 C API를 직접 쓴다(정적 참조 데이터, 스레드 안전은 호출부 책임 —
// BibleReferenceStore.swift 상단 주석과 동일한 정책).
//
// 스키마(변환 스크립트가 만드는 그대로):
//   CREATE TABLE original_words (
//     book_id INTEGER, chapter INTEGER, verse INTEGER, word_order INTEGER,
//     original_text TEXT, transliteration TEXT, strong_code TEXT,
//     morph_code TEXT, gloss_en TEXT
//   )
//   CREATE INDEX idx_original_words_verse ON original_words(book_id, chapter, verse, word_order)

public final class OriginalTextStore {
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

    /// 절 하나에 속한 원어 단어를 원문 어순(`word_order`)대로 돌려준다. 데이터가
    /// 아예 없는 절(변환 과정에서 파싱되지 않은 절 — 예: 일부 시적 텍스트의 특수
    /// 표기)이면 빈 배열을 돌려준다(에러 아님 — "원문 정보 없음"은 정상 상태).
    public func words(bookId: Int, chapter: Int, verse: Int) throws -> [OriginalWordInfo] {
        let sql = """
            SELECT word_order, original_text, transliteration, strong_code, morph_code, gloss_en
            FROM original_words
            WHERE book_id = ? AND chapter = ? AND verse = ?
            ORDER BY word_order ASC
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        sqlite3_bind_int(statement, 1, Int32(bookId))
        sqlite3_bind_int(statement, 2, Int32(chapter))
        sqlite3_bind_int(statement, 3, Int32(verse))

        var results: [OriginalWordInfo] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw BibleReferenceError.stepFailed(code: step)
            }
            let wordOrder = Int(sqlite3_column_int(statement, 0))
            let originalText = String(cString: sqlite3_column_text(statement, 1))
            let transliteration = String(cString: sqlite3_column_text(statement, 2))
            let strongCode = String(cString: sqlite3_column_text(statement, 3))
            let morphCode = String(cString: sqlite3_column_text(statement, 4))
            let glossEn = String(cString: sqlite3_column_text(statement, 5))
            results.append(OriginalWordInfo(
                bookId: bookId, chapter: chapter, verse: verse, wordOrder: wordOrder,
                originalText: originalText, transliteration: transliteration,
                strongCode: strongCode, morphCode: morphCode, glossEn: glossEn
            ))
        }
        return results
    }
}
