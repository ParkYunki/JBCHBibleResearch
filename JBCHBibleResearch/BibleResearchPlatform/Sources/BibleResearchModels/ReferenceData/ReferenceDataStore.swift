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
        // [2026-08-21 수정] description 컬럼 제거(아래 CREATE TABLE Persons/Places,
        // makeReferenceEntity 주석 참고) — 컬럼 목록에서 뺐다.
        let sql = """
            SELECT idx, word, remark, verses, 'person' FROM Persons
                WHERE length(word) >= 2 AND instr(?, word) > 0
            UNION ALL
            SELECT idx, word, remark, verses, 'place' FROM Places
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
            SELECT idx, word, remark, verses, 'person' FROM Persons WHERE word = ?
            UNION ALL
            SELECT idx, word, remark, verses, 'place' FROM Places WHERE word = ?
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

    /// [2026-08-21 수정] description 컬럼 제거에 맞춰 컬럼 인덱스가 하나씩
    /// 당겨졌다(idx=0, word=1, remark=2, verses=3, kind=4). 예전엔
    /// `remark.isEmpty ? description : remark`로 remark가 비었을 때
    /// description으로 대체했는데, 실측 결과(2026-08-21 검토) remark가 빈
    /// 194건은 description도 전부 빈 문자열이라 — 즉 이 대체가 실제로는 단
    /// 한 건도 다른 값을 만들어낸 적이 없었다("빈 문자열" 대체 결과가
    /// "빈 문자열"과 같으므로) — description을 지워도 동작 변화가 없다.
    private static func makeReferenceEntity(statement: OpaquePointer?) -> ReferenceEntity {
        let idx = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
        let word = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
        let remark = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
        let versesRaw = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
        let kindRaw = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? "person"
        return ReferenceEntity(
            idx: idx, word: word,
            entityRemark: remark,
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

    /// [2026-08-20 신설] 사용자 보고 — "골리앗의 아우" 검색이 잘 안 됨. 원인
    /// 조사 결과, `personRelations(forWord:)`(정방향, source_word 기준)만
    /// 있고 역방향이 없었다: PersonRelations엔 `('라흐미', 'younger_brother_of',
    /// '골리앗')` 행이 실제로 있지만(정규식 추출, 확정 데이터), "골리앗"은
    /// Persons 테이블에 행 자체가 없어(`personsAndPlaces(mentionedIn:)`가
    /// "골리앗"을 애초에 entity로 못 찾음 — `BibleStructuralRerankerService`의
    /// 기존 루프가 시작조차 못 함) 정방향 조회로는 이 관계에 절대 도달할 수
    /// 없다. 이 메서드는 `target_word` 쪽을 `personsAndPlaces(mentionedIn:)`와
    /// 같은 원칙(instr() 역방향 부분 문자열 검색, 2글자 미만 오탐 방지로 제외)
    /// 으로 직접 질의 문자열과 대조한다 — target_word가 Persons/Places에
    /// 없어도(바로 이 "골리앗" 케이스) 매칭된다는 점이 `personOrPlace(exactWord:)`
    /// 를 쓸 수 없는 이유이자 이 메서드가 필요한 이유다.
    public func personRelations(targetWordMentionedIn query: String) throws -> [PersonRelationRecord] {
        let sql = """
            SELECT source_word, relation_type, target_word, target_kind, raw_sentence
            FROM PersonRelations WHERE length(target_word) >= 2 AND instr(?, target_word) > 0
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        sqlite3_bind_text(statement, 1, query, -1, SQLITE_TRANSIENT)

        var results: [PersonRelationRecord] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw BibleReferenceError.stepFailed(code: step) }
            let sourceWord = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
            let relationType = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let targetWord = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            let targetKindRaw = sqlite3_column_text(statement, 3).map { String(cString: $0) }
            let rawSentence = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
            results.append(PersonRelationRecord(
                sourceWord: sourceWord, relationType: relationType, targetWord: targetWord,
                targetKind: targetKindRaw == "place" ? .place : (targetKindRaw == "person" ? .person : nil),
                rawSentence: rawSentence
            ))
        }
        return results
    }

    // MARK: - Themes / Prophecies / TimelineEvents (2026-08-20 신설, 스키마만)
    //
    // [2026-08-20 신설] `ReferenceEntity.swift`의 같은 이름 MARK 주석 참고 —
    // 질의 분류(QueryIntentClassifier)의 "예언/주제·속성/서사" 세 카테고리가
    // 조회할 테이블. `build_reference_data.py`가 스키마만 만들어 뒀고 아직
    // 데이터가 없으므로(사용자가 배포 전까지 항목 단위로 채우기로 확정),
    // 아래 세 메서드는 지금은 전부 빈 배열을 반환한다.
    //
    // `search_keywords`는 콤마로 여러 값을 담는 자유 텍스트 컬럼이라, SQL
    // `instr()` 하나로는 "질의 문자열 안에 이 키워드 중 하나라도 있는지"를
    // 걸러낼 수 없다(콤마로 쪼개는 표준 SQLite 함수가 마땅치 않음). 세 테이블
    // 모두 사람이 직접 큐레이션하는 작은 테이블(수십~수백 건 규모로 예상)이라,
    // 위 `personsAndPlaces(mentionedIn:)`·`instr()` 전체 스캔과 같은 논리로
    // — 테이블 전체를 읽어와 Swift 쪽에서 부분 문자열 비교한다.
    //
    // ⚠️ [미검증] 테이블이 비어 있어 이 세션에서 실제 매칭 동작을 실측할
    // 방법이 없었다 — SQL 자체는 이 파일의 기존 메서드들과 같은 SQLite3
    // C API 패턴을 그대로 따랐으니 구조적으로는 안전할 가능성이 높지만,
    // 데이터가 들어간 뒤 반드시 실제 질의로 재확인할 것.

    /// `title` 또는 `searchKeywords`(콤마 구분) 중 하나라도 `query` 문자열
    /// 안에 부분 문자열로 등장하면 true — `personsAndPlaces(mentionedIn:)`의
    /// `instr(query, word) > 0`과 같은 방향(항목 이름이 사용자 질의 "안에"
    /// 나타나는지)이다. 1글자짜리 오탐 방지로 2글자 미만은 제외한다(같은
    /// 이유로 위 `personsAndPlaces`도 `length(word) >= 2`를 건다).
    private static func matchesQuery(_ query: String, title: String, searchKeywords: String?) -> Bool {
        if title.count >= 2, query.contains(title) { return true }
        guard let searchKeywords, !searchKeywords.isEmpty else { return false }
        return searchKeywords.split(separator: ",").contains { raw in
            let keyword = raw.trimmingCharacters(in: .whitespaces)
            return keyword.count >= 2 && query.contains(keyword)
        }
    }

    /// `Themes` 중 `query` 문자열 안에 제목/검색어가 등장하는 항목만 추려
    /// 돌려준다(현재는 테이블이 비어 있어 항상 빈 배열).
    public func themes(matching query: String) throws -> [ThemeRecord] {
        let sql = "SELECT idx, category, title, search_keywords, verse_refs, tags, description FROM Themes"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }

        var results: [ThemeRecord] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw BibleReferenceError.stepFailed(code: step) }
            let idx = Int(sqlite3_column_int(statement, 0))
            let category = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let title = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            let searchKeywords = sqlite3_column_text(statement, 3).map { String(cString: $0) }
            let verseRefsRaw = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
            let tags = sqlite3_column_text(statement, 5).map { String(cString: $0) }
            let description = sqlite3_column_text(statement, 6).map { String(cString: $0) }
            guard !title.isEmpty, Self.matchesQuery(query, title: title, searchKeywords: searchKeywords) else { continue }
            results.append(ThemeRecord(
                idx: idx, category: category, title: title, searchKeywords: searchKeywords,
                verseRefs: Self.parseTargets(verseRefsRaw), tags: tags, themeDescription: description
            ))
        }
        return results
    }

    /// `Prophecies` 중 `query` 문자열 안에 제목/검색어가 등장하는 항목만
    /// 추려 돌려준다(현재는 테이블이 비어 있어 항상 빈 배열). 위
    /// `themes(matching:)`와 완전히 같은 패턴 — 차이는 컬럼 구성뿐이다.
    public func prophecies(matching query: String) throws -> [ProphecyRecord] {
        let sql = """
            SELECT idx, category, title, search_keywords, prophecy_refs, fulfillment_refs,
                   timeline_period, tags, description
            FROM Prophecies
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }

        var results: [ProphecyRecord] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw BibleReferenceError.stepFailed(code: step) }
            let idx = Int(sqlite3_column_int(statement, 0))
            let category = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let title = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            let searchKeywords = sqlite3_column_text(statement, 3).map { String(cString: $0) }
            let prophecyRefsRaw = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
            let fulfillmentRefsRaw = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? ""
            let timelinePeriod = sqlite3_column_text(statement, 6).map { String(cString: $0) }
            let tags = sqlite3_column_text(statement, 7).map { String(cString: $0) }
            let description = sqlite3_column_text(statement, 8).map { String(cString: $0) }
            guard !title.isEmpty, Self.matchesQuery(query, title: title, searchKeywords: searchKeywords) else { continue }
            results.append(ProphecyRecord(
                idx: idx, category: category, title: title, searchKeywords: searchKeywords,
                prophecyRefs: Self.parseTargets(prophecyRefsRaw),
                fulfillmentRefs: Self.parseTargets(fulfillmentRefsRaw),
                timelinePeriod: timelinePeriod, tags: tags, prophecyDescription: description
            ))
        }
        return results
    }

    /// `TimelineEvents` 중 서사 제목/검색어가 `query` 문자열 안에 등장하는
    /// 서사에 속한 행 전부를(그 서사에 속한 다른 행이 직접 매칭되지 않아도)
    /// `sequenceOrder` 순서로 돌려준다(현재는 테이블이 비어 있어 항상 빈
    /// 배열). 한 서사 안에서 일부 행만 반환하면 서사가 끊겨 보이므로, 매칭은
    /// 행 단위가 아니라 `narrativeKey` 단위로 판정한다.
    public func timelineEvents(narrativeMentionedIn query: String) throws -> [TimelineEventRecord] {
        let sql = """
            SELECT idx, narrative_key, narrative_title, sequence_order, event_title, verse_refs,
                   era, location, search_keywords, description
            FROM TimelineEvents ORDER BY narrative_key ASC, sequence_order ASC
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }

        var allEvents: [TimelineEventRecord] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw BibleReferenceError.stepFailed(code: step) }
            let idx = Int(sqlite3_column_int(statement, 0))
            let narrativeKey = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let narrativeTitle = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            let sequenceOrder = Int(sqlite3_column_int(statement, 3))
            let eventTitle = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
            let verseRefsRaw = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? ""
            let era = sqlite3_column_text(statement, 6).map { String(cString: $0) }
            let location = sqlite3_column_text(statement, 7).map { String(cString: $0) }
            let searchKeywords = sqlite3_column_text(statement, 8).map { String(cString: $0) }
            let description = sqlite3_column_text(statement, 9).map { String(cString: $0) }
            guard !narrativeKey.isEmpty else { continue }
            allEvents.append(TimelineEventRecord(
                idx: idx, narrativeKey: narrativeKey, narrativeTitle: narrativeTitle,
                sequenceOrder: sequenceOrder, eventTitle: eventTitle,
                verseRefs: Self.parseTargets(verseRefsRaw), era: era, location: location,
                searchKeywords: searchKeywords, eventDescription: description
            ))
        }

        var matchedKeys = Set<String>()
        for event in allEvents where Self.matchesQuery(query, title: event.narrativeTitle, searchKeywords: event.searchKeywords) {
            matchedKeys.insert(event.narrativeKey)
        }
        return allEvents.filter { matchedKeys.contains($0.narrativeKey) }
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
    // [2026-08-25 변경] 사용자 요청 — "① 검색결과가 실제로도 성경순서
    // tie-break를 지킬 것 ② limit 50을 해제할 수 있는 방법(더보기 버튼)도
    // 추가할 것." 기존엔 `ORDER BY rank LIMIT ?`(bm25 관련도 순으로 50개를
    // 먼저 자름) 방식이었는데, 이 함수의 두 호출부(`SearchViewModel.
    // searchVerses`, `BibleSemanticSearchService`) 어디서도 `rank` 값을
    // 실제로 읽지 않는다(둘 다 `KeywordMatchScorer`로 자체 재점수해 다시
    // 정렬) — 즉 bm25 순으로 50개를 자르는 기준 자체가 그 무엇과도
    // 연결되지 않는 근거 없는 컷이었다. 실측(953건 중 "다윗")으로 확인한
    // 증상: 진짜 첫 등장(룻 4:17)이 bm25 상위 50위 밖으로 밀려나 결과에서
    // 통째로 빠짐 — "검색어가 한 단어면 무조건 성경순+장절오름차순"이라는
    // 요구사항이 정렬 로직(`SearchViewModel`)은 맞아도 그 앞 후보수집
    // 단계에서 이미 깨져 있었다. 이제 SQL 자체를 (book_id, chapter, verse)
    // 오름차순으로 정렬해 `LIMIT`이 "성경순 앞쪽 N개"를 정확히 잘라내게
    // 했다. `limit`은 `Int?`로 바꿔 `nil`이면 아예 자르지 않는다(호출부가
    // "더보기"로 전체 결과를 원할 때 사용) — 이 인덱스가 담은 절 수(31,102,
    // 개역한글 전체)가 고정돼 있어 무제한 조회도 로컬 SQLite에서 비용이
    // 크지 않다(실측: "여호와" 5,916건 조회도 수 ms 수준).
    public func searchVersesFullText(matching query: String, limit: Int? = nil) throws -> [FullTextVerseMatch] {
        guard !query.isEmpty else { return [] }
        let escaped = query.replacingOccurrences(of: "\"", with: "\"\"")
        let matchQuery = "\"\(escaped)\"*"

        var sql = """
            SELECT book_id, chapter, verse, content, bm25(VerseSearchIndex) AS rank
            FROM VerseSearchIndex WHERE VerseSearchIndex MATCH ?
            ORDER BY book_id ASC, chapter ASC, verse ASC
            """
        if limit != nil { sql += " LIMIT ?" }

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        sqlite3_bind_text(statement, 1, matchQuery, -1, SQLITE_TRANSIENT)
        if let limit { sqlite3_bind_int(statement, 2, Int32(limit)) }

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
