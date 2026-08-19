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

    // MARK: - Persons / Places / PersonRelations (2026-08-19 신설)
    //
    // [2026-08-19 신설] 사용자 요청 — "① 관주를 검색 파이프라인에 연결,
    // ④ 인물 관계 데이터를 체크포인트 파일에서 규칙/AI 기반으로 추출하는
    // 파이프라인을 만들 것." `ReferenceDataSource/build_reference_data.py`가
    // 새로 만드는 Persons/Places/PersonRelations 세 테이블을 읽는 계층 —
    // 위 crossReferences/marginalNotes/hanjaAnnotations와 완전히 같은 원칙
    // (정적 참조 데이터, 번들 읽기전용 SQLite, SwiftData/CloudKit에 넣지
    // 않음)을 따른다.
    //
    // ⚠️ [미검증] 이 파일의 나머지 부분과 달리 이 구간은 이 세션에서 새로
    // 작성했고 Xcode 컴파일 확인을 못 했다 — 위 기존 메서드들과 같은 SQLite3
    // C API 패턴을 그대로 따랐으니 구조적으로는 안전할 가능성이 높지만,
    // 빌드 확인 전까지는 "미검증"으로 취급할 것.
    //
    // `verses` 컬럼은 `CrossReferences.targets`와 완전히 같은 포맷
    // ("book:chapter:verse,book:chapter:verse")이라 기존 `parseTargets(_:)`를
    // 그대로 재사용한다 — 새 파싱 함수를 또 만들지 않기 위함.

    /// 질의 문자열 `query` 안에 실제로 등장하는 인물/지명 이름을 찾는다
    /// (`SELECT ... WHERE instr(query, word) > 0` — 역방향 부분 문자열
    /// 검색이라 인덱스를 타지 않지만, Persons+Places 합쳐 982건뿐이라
    /// 전체 스캔 비용이 무시할 만하다). 한 글자짜리 word는 오탐이 너무
    /// 많아(예: "그", "이") 제외한다.
    public func personsAndPlaces(mentionedIn query: String) throws -> [ReferenceEntity] {
        let sql = """
            SELECT idx, word, description, verses, 'person' FROM Persons
                WHERE length(word) >= 2 AND instr(?, word) > 0
            UNION ALL
            SELECT idx, word, description, verses, 'place' FROM Places
                WHERE length(word) >= 2 AND instr(?, word) > 0
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        sqlite3_bind_text(statement, 1, query, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, query, -1, SQLITE_TRANSIENT)

        var results: [ReferenceEntity] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw BibleReferenceError.stepFailed(code: step) }
            results.append(Self.makeReferenceEntity(statement: statement))
        }
        return results
    }

    /// 이름이 정확히 일치하는 인물/지명 하나를 찾는다(관계의 target 쪽을
    /// 해석할 때 사용 — `PersonRelations.target_word`는 이미 build 스크립트
    /// 단계에서 이 파일 안의 다른 항목과 정확히 일치하는 것만 `target_kind`가
    /// 채워져 있으므로, 여기서도 정확 일치로 충분하다).
    public func personOrPlace(exactWord word: String) throws -> ReferenceEntity? {
        let sql = """
            SELECT idx, word, description, verses, 'person' FROM Persons WHERE word = ?
            UNION ALL
            SELECT idx, word, description, verses, 'place' FROM Places WHERE word = ?
            LIMIT 1
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        sqlite3_bind_text(statement, 1, word, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, word, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Self.makeReferenceEntity(statement: statement)
    }

    private static func makeReferenceEntity(statement: OpaquePointer?) -> ReferenceEntity {
        let idx = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
        let word = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
        let description = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
        let versesRaw = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
        let kindRaw = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? "person"
        return ReferenceEntity(
            idx: idx, word: word, entityDescription: description,
            verseRefs: parseTargets(versesRaw),
            kind: kindRaw == "place" ? .place : .person
        )
    }

    /// `sourceWord`(인물/지명 이름, 정확 일치)가 갖는 관계 전부. 예:
    /// "골리앗" -> [(relation_type: "brother_of", target_word: "라흐미", ...)].
    /// `target_kind`가 nil이면 규칙 추출은 됐지만 대상 이름이 이 번들
    /// 데이터셋 안에서 확인되지 않은 경우다(build 스크립트 상단 주석의
    /// "미해결" 항목) — 호출부는 이 경우 verse 연결을 시도하지 않아야 한다.
    public func personRelations(forWord sourceWord: String) throws -> [PersonRelationRecord] {
        let sql = """
            SELECT relation_type, target_word, target_kind, raw_sentence
            FROM PersonRelations WHERE source_word = ?
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        sqlite3_bind_text(statement, 1, sourceWord, -1, SQLITE_TRANSIENT)

        var results: [PersonRelationRecord] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw BibleReferenceError.stepFailed(code: step) }
            let relationType = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
            let targetWord = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let targetKindRaw = sqlite3_column_text(statement, 2).map { String(cString: $0) }
            let rawSentence = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
            results.append(PersonRelationRecord(
                sourceWord: sourceWord, relationType: relationType, targetWord: targetWord,
                targetKind: targetKindRaw == "place" ? .place : (targetKindRaw == "person" ? .person : nil),
                rawSentence: rawSentence
            ))
        }
        return results
    }

    /// 절 하나(`bookId`/`chapter`/`verse`)의 관주(교차 참조) 대상만 필요할 때
    /// 쓰는 가벼운 버전 — 위 `crossReferences(bookId:chapter:translationCode:)`는
    /// 장 전체를 SwiftData `@Model`(`VerseCrossReference`)로 감싸 돌려주는
    /// UI 전용 API라, `translationCode`를 요구하고 굳이 컨텍스트에 안 넣을
    /// 인스턴스를 만드는 비용이 있다. 구조적 리랭커(`BibleStructuralRerankerService`)
    /// 처럼 좌표 목록만 필요한 내부 계산용으로는 이 메서드를 쓴다.
    public func crossReferenceTargets(bookId: Int, chapter: Int, verse: Int) throws -> [BibleVerseRef] {
        let sql = "SELECT targets FROM CrossReferences WHERE book_id = ? AND chapter = ? AND verse = ?"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        sqlite3_bind_int(statement, 1, Int32(bookId))
        sqlite3_bind_int(statement, 2, Int32(chapter))
        sqlite3_bind_int(statement, 3, Int32(verse))
        guard sqlite3_step(statement) == SQLITE_ROW else { return [] }
        let targetsRaw = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
        return Self.parseTargets(targetsRaw)
    }

    // MARK: - 전문 검색(FTS5 unicode61 + prefix, Layer 1, 2026-08-19 신설, 같은 날 재확장)
    //
    // [경위] 처음엔 `trigram` 토크나이저로 만들었다(한글 조사(을/를/이/가
    // 등)가 어절 끝에 붙어 기본 unicode61로는 "지혜를"/"지혜가"가 다른
    // 토큰이 되어 매칭이 안 될 거라는 이유). 그런데 실제 31,102절 전체로
    // `trigram`과 `unicode61`+prefix를 나란히 만들어 실측한 결과, 애초
    // 가정이 틀렸다는 게 드러나 `unicode61`로 교체했다:
    // - `trigram`은 검색어가 3글자 미만이면(믿음/사랑/은혜 등 흔한 2글자
    //   신학 용어) 3-gram을 아예 못 만들어 MATCH가 조용히 0건을 반환한다.
    // - `trigram`으로 "지혜를"을 검색해도 "지혜가"가 있는 절은 실제로는
    //   안 잡힌다(각각 62건/57건, 서로 다른 집합) — "trigram이 조사 변화에
    //   안정적으로 매칭된다"는 가정 자체가 실측으로 반증됨.
    // - 한국어는 조사/어미가 어근 뒤에만 붙는 교착어라, `unicode61`(공백
    //   기준 어절 토큰) + prefix 쿼리(`"지혜"*`)가 오히려 훨씬 잘 맞는다.
    //   "지혜*"로 검색하면 지혜를/지혜가/지혜의/지혜로운/지혜롭게 412건이
    //   전부 잡힌다(정확 문자열 매치는 41건뿐이었다). 2글자 검색어도
    //   trigram의 근본 한계 없이 그대로 매칭된다.
    // - 인덱스 크기도 실측 8.5MB(unicode61) vs 15.9MB(trigram)로 거의 절반.
    // - 단점: prefix 매칭이라 토큰 "맨 앞부터"만 잡힌다(단어 중간 부분
    //   문자열은 못 잡음) — 실사용에서 영향이 작다고 판단.
    //
    // 이제 3글자 미만 검색어도 그대로 지원되므로(trigram 때와 달리 길이
    // 가드가 필요 없다), 호출부가 짧은 검색어를 기존 LIKE 경로로 우회시킬
    // 필요가 없어졌다.
    //
    // 여러 단어를 공백 포함해 그대로 넘기는 경우는 여전히 검증하지 않았다
    // — 이 메서드는 (trigram 때와 동일하게) **호출부가 이미 단어로 쪼갠
    // 뒤(지금 `SearchViewModel`이 LIKE 경로에 이미 그렇게 하고 있는 것과
    // 동일) 단어 하나씩** 넘기는 용도로 설계했다.
    //
    // 검색어는 FTS5 쿼리 문법(AND/OR/NOT, 괄호, 콜론 등)으로 해석되지 않도록
    // 항상 큰따옴표로 감싼 리터럴 구문으로 바인딩하고, 그 바깥에 `*`를 붙여
    // prefix 검색으로 만든다(내부 큰따옴표는 두 번 써서 이스케이프) —
    // 사용자가 "삼상 17:4" 같은 콜론 포함 텍스트나 "AND"/"OR" 같은 단어를
    // 그대로 입력해도, 또는 검색어 안에 큰따옴표가 섞여 있어도 FTS5 문법
    // 에러 없이 안전하게 "그 글자로 시작하는 토큰"을 찾는다(Python sqlite3로
    // `"16:8"*`, `"(참고)"*`, `"AND"*`, `"큰따옴표""포함"*` 등 실제 검증 완료).
    public func searchVersesFullText(matching query: String, limit: Int = 50) throws -> [FullTextVerseMatch] {
        guard !query.isEmpty else { return [] }
        let escaped = query.replacingOccurrences(of: "\"", with: "\"\"")
        let matchQuery = "\"\(escaped)\"*"

        let sql = """
            SELECT book_id, chapter, verse, content, bm25(VerseSearchIndex) AS rank
            FROM VerseSearchIndex WHERE VerseSearchIndex MATCH ?
            ORDER BY rank LIMIT ?
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        sqlite3_bind_text(statement, 1, matchQuery, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 2, Int32(limit))

        var results: [FullTextVerseMatch] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw BibleReferenceError.stepFailed(code: step) }
            let bookId = Int(sqlite3_column_int(statement, 0))
            let chapter = Int(sqlite3_column_int(statement, 1))
            let verse = Int(sqlite3_column_int(statement, 2))
            let content = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
            let rank = sqlite3_column_double(statement, 4)
            results.append(FullTextVerseMatch(bookId: bookId, chapter: chapter, verse: verse, content: content, rank: rank))
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
