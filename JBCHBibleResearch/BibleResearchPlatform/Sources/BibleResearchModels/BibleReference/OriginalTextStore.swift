import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

// [2026-11-02 interlin1] `occurrences(strongCode:)`/`verseCounts(strongCodes:)`가 문자열을 바인딩한다.
// `BibleReferenceStore`와 같은 상수(SQLite가 바인딩 시점에 문자열을 복사).
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// `OriginalText.sqlite`(테이블 `original_words`) 읽기 전용 접근. `BibleReferenceStore`와
// 같은 이유로 SwiftData가 아니라 raw SQLite3 C API를 직접 쓴다(정적 참조 데이터,
// 스레드 안전은 호출부 책임).
//
// `original_words` 스키마:
//   CREATE TABLE original_words (
//     book_id INTEGER, chapter INTEGER, verse INTEGER, word_order INTEGER,
//     original_text TEXT, transliteration TEXT, strong_code TEXT,
//     morph_code TEXT, gloss_en TEXT,
//     translation_en TEXT NOT NULL DEFAULT ''   -- [2026-10-12] STEPBible 문맥 번역
//   )
//   CREATE TABLE LiteralEnglish (book_id, chapter, verse, text, source,
//     PRIMARY KEY(book_id, chapter, verse)) WITHOUT ROWID   -- [2026-10-12] 절 단위 영어 직역(LSV)
//   CREATE INDEX idx_original_words_verse ON original_words(book_id, chapter, verse, word_order)
//   (strong_code 인덱스는 없다 — [2026-11-02 interlin1] 쓰인 구절 조회는 전체 스캔, 아래 MARK 참고)

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

    /// 절 하나에 속한 원어 단어를 원문 어순(`word_order`)대로 돌려준다.
    /// 데이터가 없는 절이면 빈 배열(에러 아님 — "원문 정보 없음"은 정상 상태).
    public func words(bookId: Int, chapter: Int, verse: Int) throws -> [OriginalWordInfo] {
        let sql = """
            SELECT word_order, original_text, transliteration, strong_code, morph_code, gloss_en, translation_en
            FROM original_words
            WHERE book_id = ? AND chapter = ? AND verse = ?
            ORDER BY word_order ASC, rowid ASC
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
            let translationEn = String(cString: sqlite3_column_text(statement, 6))
            results.append(OriginalWordInfo(
                bookId: bookId, chapter: chapter, verse: verse, wordOrder: wordOrder,
                originalText: originalText, transliteration: transliteration,
                strongCode: strongCode, morphCode: morphCode, glossEn: glossEn,
                translationEn: translationEn
            ))
        }
        return results
    }

    /// 절의 직역(`LiteralTranslation` 테이블) 정보. 이 테이블은 `UNIQUE(book_id,
    /// chapter, verse)`라 절당 최대 한 행이다. 데이터가 없으면 nil
    /// (`words`와 같은 정책 — 에러가 아니라 "정보 없음" 정상 상태).
    public func literalTranslation(bookId: Int, chapter: Int, verse: Int) throws -> LiteralTranslationInfo? {
        let sql = """
            SELECT literal_translation, difference
            FROM LiteralTranslation
            WHERE book_id = ? AND chapter = ? AND verse = ?
            LIMIT 1
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        sqlite3_bind_int(statement, 1, Int32(bookId))
        sqlite3_bind_int(statement, 2, Int32(chapter))
        sqlite3_bind_int(statement, 3, Int32(verse))

        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { return nil }
        guard step == SQLITE_ROW else {
            throw BibleReferenceError.stepFailed(code: step)
        }
        let literal = String(cString: sqlite3_column_text(statement, 0))
        let difference: String?
        if sqlite3_column_type(statement, 1) == SQLITE_NULL {
            difference = nil
        } else {
            difference = String(cString: sqlite3_column_text(statement, 1))
        }
        return LiteralTranslationInfo(
            bookId: bookId, chapter: chapter, verse: verse,
            literalTranslation: literal, difference: difference
        )
    }

    /// [2026-10-12] 절 단위 영어 직역(`LiteralEnglish`). 데이터가 없으면 nil(정상 상태).
    public func literalEnglish(bookId: Int, chapter: Int, verse: Int) throws -> LiteralEnglishInfo? {
        let sql = """
            SELECT text, source
            FROM LiteralEnglish
            WHERE book_id = ? AND chapter = ? AND verse = ?
            LIMIT 1
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        sqlite3_bind_int(statement, 1, Int32(bookId))
        sqlite3_bind_int(statement, 2, Int32(chapter))
        sqlite3_bind_int(statement, 3, Int32(verse))

        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { return nil }
        guard step == SQLITE_ROW else {
            throw BibleReferenceError.stepFailed(code: step)
        }
        return LiteralEnglishInfo(
            bookId: bookId, chapter: chapter, verse: verse,
            text: String(cString: sqlite3_column_text(statement, 0)),
            source: String(cString: sqlite3_column_text(statement, 1))
        )
    }
    // MARK: - 쓰인 구절 [2026-11-02 interlin1]
    //
    // 원문 정보 화면의 "이 단어가 쓰인 구절". `strong_code`에는 인덱스가 없어 전체 스캔이다(약 45만 행, Mac 측정 20~40ms).
    // 인덱스를 더하면 번들 DB가 커지므로 더하지 않고, 호출부가 메인 스레드 밖에서 부른다(인스턴스를 스레드 사이에 나눠 쓰지 않는다).

    /// 이 Strong 번호가 쓰인 절과, 그 절에서 쓰인 원어 형태(그 절에 처음 나온 순서, 중복 없음). 성경 순서.
    /// 원어 형태는 `group_concat` 대신 (절, 형태) 행으로 받아 모은다 — 원어 표기에 쉼표가 든 행이 있어
    /// (마 11:17 G3738) 구분자로 다시 나누면 형태가 쪼개진다.
    public func occurrences(strongCode: String) throws -> [OriginalWordOccurrence] {
        let sql = """
            SELECT book_id, chapter, verse, original_text
            FROM original_words
            WHERE strong_code = ?
            GROUP BY book_id, chapter, verse, original_text
            ORDER BY book_id, chapter, verse, MIN(word_order)
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        sqlite3_bind_text(statement, 1, strongCode, -1, SQLITE_TRANSIENT)

        var results: [OriginalWordOccurrence] = []
        var currentKey: (bookId: Int, chapter: Int, verse: Int)?
        var currentForms: [String] = []
        func flush() {
            if let key = currentKey {
                results.append(OriginalWordOccurrence(bookId: key.bookId, chapter: key.chapter, verse: key.verse, forms: currentForms))
            }
        }
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw BibleReferenceError.stepFailed(code: step)
            }
            let bookId = Int(sqlite3_column_int(statement, 0))
            let chapter = Int(sqlite3_column_int(statement, 1))
            let verse = Int(sqlite3_column_int(statement, 2))
            let form = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
            if let key = currentKey, key.bookId == bookId, key.chapter == chapter, key.verse == verse {
                if !form.isEmpty { currentForms.append(form) }
            } else {
                flush()
                currentKey = (bookId, chapter, verse)
                currentForms = form.isEmpty ? [] : [form]
            }
        }
        flush()
        return results
    }

    /// Strong 번호별 쓰인 절 수(같은 절에 여러 번 나와도 1). 빈 번호는 뺀다. 데이터에 없는 번호는 결과에 없다.
    /// 한 절의 Strong 번호(수십 개)를 한 번에 센다 — 바인딩 수는 SQLite 기본 한도(32766)보다 훨씬 적다.
    /// 절 키는 (책 × 1000 + 장) × 1000 + 절이다(장 최대 150, 절 최대 176이라 겹치지 않는다).
    public func verseCounts(strongCodes: [String]) throws -> [String: Int] {
        let codes = Array(Set(strongCodes.filter { !$0.isEmpty })).sorted()
        guard !codes.isEmpty else { return [:] }
        let placeholders = Array(repeating: "?", count: codes.count).joined(separator: ", ")
        let sql = """
            SELECT strong_code, COUNT(DISTINCT (book_id * 1000 + chapter) * 1000 + verse)
            FROM original_words
            WHERE strong_code IN (\(placeholders))
            GROUP BY strong_code
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        for (offset, code) in codes.enumerated() {
            sqlite3_bind_text(statement, Int32(offset + 1), code, -1, SQLITE_TRANSIENT)
        }
        var counts: [String: Int] = [:]
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw BibleReferenceError.stepFailed(code: step)
            }
            guard let codePointer = sqlite3_column_text(statement, 0) else { continue }
            counts[String(cString: codePointer)] = Int(sqlite3_column_int64(statement, 1))
        }
        return counts
    }
}
