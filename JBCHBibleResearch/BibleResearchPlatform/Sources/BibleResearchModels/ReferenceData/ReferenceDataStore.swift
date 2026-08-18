import Foundation
import SwiftData
#if canImport(SQLite3)
import SQLite3
#endif

// SQLite3의 C 매크로 `SQLITE_TRANSIENT`는 ClangImporter가 들여오지 못해 직접
// 정의해야 한다 — `BibleReferenceStore.swift`와 완전히 같은 이유(그 파일 상단
// 주석 참고). 파일 스코프 `private`라 이름이 겹쳐도 충돌하지 않는다.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// [2026-08-15 신설] 사용자 요청 — "성경관련 json seed 파일은 기본 제공 db에
// 넣을 것. 난외주/성경한자/한문사전/관주." 지금까지 이 네 데이터셋은
// "번들 JSON → SwiftData 1회성 시딩"(CrossReferenceSeedImporter/
// MarginalNoteSeedImporter/HanjaAnnotationSeedImporter, 전부 이번에 삭제)
// 방식이었는데, 정적 참조 데이터를 굳이 사용자 CloudKit 데이터베이스에
// 복사해 넣을 이유가 없다는 지적으로(`BibleReferenceStore.swift` 상단
// 주석의 원래 원칙 — "정적 참조 데이터는 SwiftData가 아니라 원시 SQLite로
// 직접 접근"과 정확히 같은 논리) 이 네 데이터셋도 `BibleDB.sqlite`와 같은
// "번들 읽기 전용 SQLite" 방식으로 옮긴다.
//
// `BibleReferenceStore`와 별도 파일(`ReferenceData.sqlite`)로 둔 이유는
// README "이어서 62" 설계 논의 참고 — 본문 텍스트(번역본별로 갈아 끼울 수
// 있는 데이터)와 그 위에 얹는 참고자료 레이어(번역본과 무관하게 존재하는
// 편집 데이터)를 개념적으로 분리해, `BibleReferenceStore`의 기존 스키마
// 판별 로직(BibleVerses/Bible 두 스키마 감지)을 전혀 건드리지 않기 위함이다.
//
// 스레딩 참고: `BibleReferenceStore`와 동일 — 이 타입 자체는 스레드 안전을
// 보장하지 않는다. 인스턴스당 단일 커넥션, 동시 접근 직렬화는 호출부 책임.
public final class ReferenceDataStore {
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

    /// 관주 — 이 책/장 전체를 한 번에 불러온다(`BibleReadingViewModel`이 장 단위로
    /// 미리 로드해 두는 기존 패턴과 맞춘다). `targets` 컬럼(`"1:2:3,4:5:6"` 형식,
    /// `ReferenceData.sqlite` 빌드 스크립트가 책약어 파싱을 미리 끝내 둔 결과)을
    /// `BibleVerseRef` 배열로 되돌린다.
    ///
    /// 반환 타입은 SwiftData `@Model`인 `VerseCrossReference`이지만, 여기서 만든
    /// 인스턴스는 어떤 `ModelContext`에도 `insert`하지 않는다 — SwiftData
    /// `@Model` 클래스는 컨텍스트에 넣지 않아도 평범한 Swift 객체로 값을 담고
    /// 쓸 수 있다(퍼시스턴스만 없을 뿐). 호출부(`BibleReadingViewModel`)가 이
    /// "미삽입 인메모리 인스턴스"를 사용자가 실제로 만든(SwiftData에 저장된)
    /// 것과 배열 하나로 섞어 두면, 화면 레이어(`TranslationColumnView` 등)는
    /// 두 출처를 구분할 필요 없이 기존 코드 그대로 쓸 수 있다.
    public func crossReferences(bookId: Int, chapter: Int, translationCode: String) throws -> [VerseCrossReference] {
        let sql = "SELECT verse, targets FROM CrossReferences WHERE book_id = ? AND chapter = ? ORDER BY verse ASC"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        sqlite3_bind_int(statement, 1, Int32(bookId))
        sqlite3_bind_int(statement, 2, Int32(chapter))

        var results: [VerseCrossReference] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw BibleReferenceError.stepFailed(code: step) }
            let verse = Int(sqlite3_column_int(statement, 0))
            let targetsRaw = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let targets = Self.parseTargets(targetsRaw)
            guard !targets.isEmpty else { continue }
            results.append(VerseCrossReference(
                translationCode: translationCode, bookId: bookId, chapter: chapter, verse: verse,
                source: .bundled, targets: targets
            ))
        }
        return results
    }

    /// `"1:2:3,4:5:6"` → `[BibleVerseRef(bookId:1,chapter:2,verse:3), ...]`.
    /// 형식이 어긋난 조각은 건너뛴다(빌드 스크립트가 만든 파일이라 정상적으로는
    /// 항상 맞지만, 방어적으로 처리한다 — `CrossReferenceSeedImporter`가 JSON
    /// 파싱 실패 항목을 건너뛰던 것과 같은 원칙).
    private static func parseTargets(_ raw: String) -> [BibleVerseRef] {
        guard !raw.isEmpty else { return [] }
        return raw.split(separator: ",").compactMap { token in
            let parts = token.split(separator: ":")
            guard parts.count == 3,
                  let bookId = Int(parts[0]), let chapter = Int(parts[1]), let verse = Int(parts[2]) else {
                return nil
            }
            return BibleVerseRef(bookId: bookId, chapter: chapter, verse: verse)
        }
    }

    /// 난외주 — 위 `crossReferences(bookId:chapter:translationCode:)`와 완전히
    /// 같은 원칙(장 전체 벌크 로드, 미삽입 인메모리 `VerseMarginalNote` 인스턴스).
    /// [2026-08-15 변경] 사용자 요청 — "난외주가 있으면 해당 단어 위첨자 숫자
    /// 추가." `anchor_offset` 컬럼(신설, `ReferenceDataSource/
    /// extract_marginal_note_anchors.py` 참고)을 함께 읽어
    /// `VerseMarginalNote.anchorOffset`에 채운다 — SQLite `NULL`은
    /// `sqlite3_column_type(...) == SQLITE_NULL`로 구분해야 한다(정수 0과
    /// 안 헷갈리게, `hanjaAnnotations`의 `sqlite3_column_int`처럼 무조건
    /// 정수로 읽으면 NULL이 0이 돼 버려 "0번째 글자 앞"과 "위치 정보 없음"이
    /// 뒤섞인다).
    /// [2026-08-15 재수정, 이어서 67] `marker_text` 컬럼(신설)도 함께 읽어
    /// `VerseMarginalNote.markerText`에 채운다 — 앱이 위첨자 번호를 새로
    /// 매기지 않고 원본 `<SUP>` 태그 글자를 그대로 쓰기로 했다(위 클래스
    /// 주석 참고). TEXT 컬럼이라 `sqlite3_column_text`가 nil을 그대로
    /// 돌려주므로 NULL 처리에 별도 분기가 필요 없다(`note_text`와 같은 패턴).
    public func marginalNotes(bookId: Int, chapter: Int, translationCode: String) throws -> [VerseMarginalNote] {
        let sql = """
            SELECT verse, note_text, anchor_offset, marker_text FROM MarginalNotes
            WHERE book_id = ? AND chapter = ? ORDER BY verse ASC, note_index ASC
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        sqlite3_bind_int(statement, 1, Int32(bookId))
        sqlite3_bind_int(statement, 2, Int32(chapter))

        var results: [VerseMarginalNote] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw BibleReferenceError.stepFailed(code: step) }
            let verse = Int(sqlite3_column_int(statement, 0))
            let noteText = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            guard !noteText.isEmpty else { continue }
            let anchorOffset: Int? = sqlite3_column_type(statement, 2) == SQLITE_NULL
                ? nil : Int(sqlite3_column_int(statement, 2))
            let markerText = sqlite3_column_text(statement, 3).map { String(cString: $0) }
            results.append(VerseMarginalNote(
                translationCode: translationCode, bookId: bookId, chapter: chapter, verse: verse,
                noteText: noteText, anchorOffset: anchorOffset, markerText: markerText, source: .bundled
            ))
        }
        return results
    }

    /// 한자 주석 — 절 번호를 키로 묶어서 돌려준다(`HanjaWordAnnotation` 자체는
    /// SwiftData `@Model`이 아니라 평범한 값 타입이라 그대로 반환하면 된다,
    /// `VerseAnnotations.swift`의 "삭제, 같은 날 되돌림" 주석 참고).
    public func hanjaAnnotations(bookId: Int, chapter: Int) throws -> [Int: [HanjaWordAnnotation]] {
        let sql = """
            SELECT verse, ko, hanja, range_start, range_end FROM HanjaAnnotations
            WHERE book_id = ? AND chapter = ? ORDER BY verse ASC, word_index ASC
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        sqlite3_bind_int(statement, 1, Int32(bookId))
        sqlite3_bind_int(statement, 2, Int32(chapter))

        var results: [Int: [HanjaWordAnnotation]] = [:]
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw BibleReferenceError.stepFailed(code: step) }
            let verse = Int(sqlite3_column_int(statement, 0))
            let ko = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let hanja = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            let rangeStart = Int(sqlite3_column_int(statement, 3))
            let rangeEnd = Int(sqlite3_column_int(statement, 4))
            guard !ko.isEmpty, !hanja.isEmpty else { continue }
            results[verse, default: []].append(
                HanjaWordAnnotation(ko: ko, hanja: hanja, rangeStart: rangeStart, rangeEnd: rangeEnd)
            )
        }
        return results
    }

    /// 한자 사전(2,002자) 전체를 한 번에 불러온다 — 앱 레이어(`HanjaDictionaryProvider`)가
    /// 시작 시 한 번만 호출해 메모리에 캐시해 두는 용도라, 장 단위가 아니라 전체
    /// 테이블을 그대로 반환한다.
    public func allHanjaDictionaryEntries() throws -> [HanjaCharacterInfo] {
        let sql = "SELECT char, eum, hun, count, confidence FROM HanjaDictionary"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }

        var results: [HanjaCharacterInfo] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw BibleReferenceError.stepFailed(code: step) }
            let char = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
            let eum = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let hun = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            let count = Int(sqlite3_column_int(statement, 3))
            let confidence = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
            guard !char.isEmpty else { continue }
            results.append(HanjaCharacterInfo(char: char, eum: eum, hun: hun, count: count, confidence: confidence))
        }
        return results
    }
}
