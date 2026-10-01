import Foundation
import SwiftData
#if canImport(SQLite3)
import SQLite3
#endif

// SQLite3의 C 매크로 `SQLITE_TRANSIENT`는 ClangImporter가 들여오지 못해 직접
// 정의한다(`BibleReferenceStore.swift`와 같은 이유). 파일 스코프 `private`라 이름이 겹쳐도 충돌하지
// 않는다.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// 번들 읽기 전용 SQLite(`ReferenceData.sqlite`)에서 정적 참조
// 데이터(관주/난외주/성경한자/한자사전/인물·지명/주제 등)를 읽는다. 정적 참조 데이터는 SwiftData/CloudKit이 아니라 원시
// SQLite로 직접 접근한다(`BibleReferenceStore`와 같은 원칙).
//
// `BibleReferenceStore`와 별도 파일로 둔 이유: 번역본별로 갈아 끼우는 본문과, 번역본과 무관한 편집 참고자료 레이어를
// 분리하고 `BibleReferenceStore`의 스키마 판별 로직(BibleVerses/Bible 두 스키마 감지)을 건드리지 않기
// 위함이다.
//
// 스레딩: 이 타입 자체는 스레드 안전하지 않다. 인스턴스당 단일 커넥션이며 동시 접근 직렬화는 호출부 책임.
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

    /// "이름#idx"(구분자 "#") 태그를 가족관계(`rel_*` 콤마 목록)에서 분리한다. 태그가 없으면 이름 전체가 그대로 온다.
    ///
    /// `build_reference_data.py`의 `parse_idx_tag`와 같은 규칙(끝이 "#숫자"인 경우만 인식)이다. 이 컬럼은
    /// 원본 텍스트를 그대로 옮기므로 태그 분리는 읽는 시점에 한다.
    private static func parseFamilyMember(_ raw: String) -> PersonFamilyMember {
        guard let hashRange = raw.range(of: "#", options: .backwards) else {
            return PersonFamilyMember(name: raw, idx: "")
        }
        let namePart = raw[..<hashRange.lowerBound]
        var idxPart = raw[hashRange.upperBound...]
        // "이름#idx(설명)" 형식(예: "야고보#4057(사도)")도 온다(`build_reference_data.py`의
        // `IDX_TAG_WITH_NOTE_RE`와 같은 이유). 끝의 "(...)"는 idx 검증을 위해 떼어내되 버리지 않고
        // `PersonFamilyMember.note`에 보존한다(표시는 PersonDetailView.familyRelationRows).
        var note = ""
        if idxPart.hasSuffix(")"), let parenStart = idxPart.firstIndex(of: "(") {
            let noteRange = idxPart.index(after: parenStart)..<idxPart.index(before: idxPart.endIndex)
            note = String(idxPart[noteRange])
            idxPart = idxPart[..<parenStart]
        }
        guard !namePart.isEmpty, !idxPart.isEmpty, idxPart.allSatisfy({ $0.isNumber }) else {
            return PersonFamilyMember(name: raw, idx: "")
        }
        return PersonFamilyMember(name: String(namePart), idx: String(idxPart), note: note)
    }

    /// 관주 — 이 책/장 전체를 한 번에 불러와 `targets` 컬럼(`"1:2:3,4:5:6"` 형식)을 `BibleVerseRef`
    /// 배열로 되돌린다.
    ///
    /// 반환하는 `@Model`인 `VerseCrossReference`는 어떤 `ModelContext`에도 insert하지 않는 인메모리
    /// 인스턴스다. 호출부가 사용자가 저장한 것과 한 배열로 섞어 쓰므로 화면 레이어는 출처를 구분할 필요가 없다.
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

    /// `"1:2:3,4:5:6"` → `[BibleVerseRef(bookId:1,chapter:2,verse:3), ...]`. 형식이
    /// 어긋난 조각은 방어적으로 건너뛴다.
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

    /// 난외주 — `crossReferences(bookId:chapter:translationCode:)`와 같은 원칙(장 전체 벌크 로드,
    /// 미삽입 인메모리 `VerseMarginalNote`).
    ///
    /// `anchor_offset`은 `sqlite3_column_type(...) == SQLITE_NULL`로 NULL을 구분해 nil로
    /// 채운다(정수 0 "0번째 글자 앞"과 "위치 정보 없음"이 섞이지 않게). `marker_text`는 원본 `<SUP>` 태그 글자이며,
    /// TEXT 컬럼이라 `sqlite3_column_text`가 NULL이면 nil을 그대로 돌려준다.
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

    /// 한자 주석 — 절 번호를 키로 묶어 돌려준다(`HanjaWordAnnotation`은 `@Model`이 아닌 값 타입).
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
    // 위 crossReferences/marginalNotes/hanjaAnnotations와 같은 원칙(정적 참조 데이터, 번들 읽기전용
    // SQLite, SwiftData/CloudKit에 넣지 않음)으로
    // `ReferenceDataSource/build_reference_data.py`가 만드는
    // Persons/Places/PersonRelations 테이블을 읽는다. `verses` 컬럼은
    // `CrossReferences.targets`와 같은 포맷이라 `parseTargets(_:)`를 재사용한다.

    /// 질의 문자열 `query` 안에 실제로 등장하는 인물/지명 이름을 찾는다
    /// (`SELECT ... WHERE instr(query, word) > 0` — 역방향 부분 문자열
    /// 검색이라 인덱스를 타지 않지만, Persons+Places 합쳐 982건뿐이라
    /// 전체 스캔 비용이 무시할 만하다). 한 글자짜리 word는 오탐이 너무
    /// 많아(예: "그", "이") 제외한다.
    public func personsAndPlaces(mentionedIn query: String) throws -> [ReferenceEntity] {
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

    /// SELECT 컬럼 인덱스: idx=0, word=1, remark=2, verses=3, kind=4.
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
            SELECT relation_type, target_word, target_kind, raw_sentence, target_idx
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
            let targetIdx = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
            results.append(PersonRelationRecord(
                sourceWord: sourceWord, relationType: relationType, targetWord: targetWord,
                targetKind: targetKindRaw == "place" ? .place : (targetKindRaw == "person" ? .person : nil),
                rawSentence: rawSentence, targetIdx: targetIdx
            ))
        }
        return results
    }

    /// `PersonContextNotes`(왕/총독/선지자 등 직함·역할성 참고 정보, `PersonRelations`와 별도 테이블) 중
    /// `sourceWord`(표제어) 자신의 목록만 가져온다.
    ///
    /// 이 정보는 "표제어 자신의 PersonSeed 기타관계 원문"이라 방향에 의미가 있어, 역방향(target으로 언급된 쪽) 조회는 만들지
    /// 않는다(build 스크립트도 만들지 않는다).
    ///
    /// 조회 기준은 이름이 아니라 `Persons.idx`(`source_idx`)다. 이름으로 찾으면 동명이인(예: "예수" 3명)이 서로의 참고 정보를
    /// 가져간다. `source_idx`가 빈 행은 이름이 `Persons`에서 유일할 때만 이름으로 이어 붙인다(`isUniquePersonName`).
    public func personContextNotes(forIdx sourceIdx: String, word sourceWord: String) throws -> [PersonContextNoteRecord] {
        let nameIsUnique = try isUniquePersonName(sourceWord)
        let sql = """
            SELECT label, target_word, target_kind, target_idx, raw_sentence
            FROM PersonContextNotes
            WHERE (source_idx <> '' AND source_idx = ?1)
               OR (source_idx = '' AND source_word = ?2 AND ?3 = 1)
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        sqlite3_bind_text(statement, 1, sourceIdx, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, sourceWord, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 3, nameIsUnique ? 1 : 0)

        var results: [PersonContextNoteRecord] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw BibleReferenceError.stepFailed(code: step) }
            let label = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
            let targetWord = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let targetKindRaw = sqlite3_column_text(statement, 2).map { String(cString: $0) }
            let targetIdx = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
            let rawSentence = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
            results.append(PersonContextNoteRecord(
                sourceWord: sourceWord, label: label, targetWord: targetWord,
                targetKind: targetKindRaw == "place" ? .place : (targetKindRaw == "person" ? .person : nil),
                targetIdx: targetIdx, rawSentence: rawSentence
            ))
        }
        return results
    }

    /// `word`가 속한 각 그룹의 "다른" 멤버들을 자기 조인(self join)으로 한 번에 가져온다. `m1`으로 이 사람의 그룹을
    /// 찾고, 같은 group_id의 `m2` 중 자기 자신의 행만 제외한다.
    ///
    /// 자기 행 판별은 word와 idx를 함께 비교한다(같은 word라도 idx가 다르면 다른 사람일 수 있어
    /// `PersonGroupMemberships.UNIQUE(group_id, person_word, person_idx)`와 같은 신원 기준).
    ///
    /// 이 사람(m1)을 찾는 기준은 이름이 아니라 `person_idx`다. 이름으로 찾으면 "야고보"/"유다"/"시몬"처럼 동명이인이
    /// 있는 이름이 열두 제자가 아닌 사람의 카드에도 열두 제자 그룹을 붙인다. `person_idx`가 빈 행은 이름이
    /// `Persons`에서 유일할 때만 이름으로 이어 붙인다(`isUniquePersonName`).
    public func personGroupMemberships(forIdx idx: String, word: String) throws -> [PersonGroupMembershipRow] {
        let nameIsUnique = try isUniquePersonName(word)
        let sql = """
            SELECT m2.group_id, m2.person_word, m2.person_idx
            FROM PersonGroupMemberships m1
            JOIN PersonGroupMemberships m2 ON m1.group_id = m2.group_id
            WHERE ((m1.person_idx <> '' AND m1.person_idx = ?1)
                   OR (m1.person_idx = '' AND m1.person_word = ?2 AND ?3 = 1))
              AND NOT (m2.person_word = m1.person_word AND m2.person_idx = m1.person_idx)
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        sqlite3_bind_text(statement, 1, idx, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, word, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 3, nameIsUnique ? 1 : 0)

        var results: [PersonGroupMembershipRow] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw BibleReferenceError.stepFailed(code: step) }
            let groupId = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
            let otherWord = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let otherIdx = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            results.append(PersonGroupMembershipRow(
                groupId: groupId, otherMemberWord: otherWord, otherMemberIdx: otherIdx
            ))
        }
        return results
    }

    // MARK: - Places (2026-10-01 PlaceSeed.json 반영)

    private static let placeColumns = "idx, word, remark, verses, introduce, biblecontents, geography, history"

    private static func makePlace(from statement: OpaquePointer?) -> PlaceEntity {
        func col(_ i: Int32) -> String { sqlite3_column_text(statement, i).map { String(cString: $0) } ?? "" }
        return PlaceEntity(
            idx: col(0), word: col(1), remark: col(2), verseRefs: parseTargets(col(3)),
            introduce: col(4), bibleContents: col(5), geography: col(6), history: col(7)
        )
    }

    /// 질의에 이름이 들어 있는 지명 전부. 공백은 양쪽 모두 뺀 뒤 비교한다("가드 림몬"이 "가드림몬" 질의에 걸리게).
    /// 2글자 미만 이름은 제외하고, 더 긴 매칭 이름 안에 완전히 포함되는 짧은 이름은 뺀다("가나안" 질의에서 "가나"가
    /// 같이 걸리는 것을 막는 `filterSwallowedNameMatches`와 같은 원칙). 같은 이름의 지명은 모두 돌려주며 idx 오름차순이다.
    public func places(mentionedIn query: String) throws -> [PlaceEntity] {
        let compactQuery = query.filter { !$0.isWhitespace }
        guard !compactQuery.isEmpty else { return [] }
        let sql = "SELECT \(Self.placeColumns) FROM Places"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        var matched: [(place: PlaceEntity, compactName: String)] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw BibleReferenceError.stepFailed(code: step) }
            let place = Self.makePlace(from: statement)
            let compactName = place.word.filter { !$0.isWhitespace }
            guard compactName.count >= 2, compactQuery.contains(compactName) else { continue }
            matched.append((place, compactName))
        }
        let names = matched.map(\.compactName)
        return matched
            .filter { candidate in
                !names.contains { other in other.count > candidate.compactName.count && other.contains(candidate.compactName) }
            }
            .map(\.place)
            .sorted { (Int($0.idx) ?? 0) < (Int($1.idx) ?? 0) }
    }

    /// `idx`(유일 식별자)로 지명 하나를 짚는다. 없으면 nil.
    public func place(idx: String) throws -> PlaceEntity? {
        guard !idx.isEmpty else { return nil }
        let sql = "SELECT \(Self.placeColumns) FROM Places WHERE idx = ?"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        sqlite3_bind_text(statement, 1, idx, -1, SQLITE_TRANSIENT)
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { return nil }
        guard step == SQLITE_ROW else { throw BibleReferenceError.stepFailed(code: step) }
        return Self.makePlace(from: statement)
    }

    /// 이름이 같은 다른 지명들(동명이인) — `excludingIdx` 자신은 뺀다. 이름 비교는 정확 일치이며 idx 오름차순이다.
    public func placesSharingName(word: String, excludingIdx idx: String) throws -> [PlaceEntity] {
        let sql = "SELECT \(Self.placeColumns) FROM Places WHERE word = ?1 AND idx <> ?2 ORDER BY CAST(idx AS INTEGER) ASC"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        sqlite3_bind_text(statement, 1, word, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, idx, -1, SQLITE_TRANSIENT)
        var results: [PlaceEntity] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw BibleReferenceError.stepFailed(code: step) }
            results.append(Self.makePlace(from: statement))
        }
        return results
    }

    /// 그룹(예: "열두 제자")의 멤버 전원을 `PersonGroupMemberships`의 등록 순서대로 돌려준다.
    ///
    /// 멤버는 이름이 아니라 `person_idx`로 `person(idx:)`를 불러 확정한다 — "야고보"/"유다"/"시몬"처럼 동명이인이
    /// 있는 이름이 엉뚱한 사람으로 붙지 않게 하기 위함이다. `person_idx`가 빈 행은 어느 사람인지 알 수 없어(이름만으로
    /// 추측하지 않는다) 건너뛰고, 같은 idx가 중복 등록돼 있어도 한 번만 담는다. 그룹이 없거나 멤버가 하나도 확정되지
    /// 않으면 빈 배열이다.
    public func personGroupMembers(groupId: String) throws -> [PersonEntity] {
        let sql = "SELECT person_idx FROM PersonGroupMemberships WHERE group_id = ? ORDER BY id ASC"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        sqlite3_bind_text(statement, 1, groupId, -1, SQLITE_TRANSIENT)

        var idxs: [String] = []
        var seen = Set<String>()
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw BibleReferenceError.stepFailed(code: step) }
            let idx = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
            if !idx.isEmpty, seen.insert(idx).inserted { idxs.append(idx) }
        }
        // 위 statement를 다 읽은 뒤에 `person(idx:)`(자체 statement)를 부른다 — 한 커넥션에서 두 statement를 겹쳐 쓰지 않는다.
        return idxs.compactMap { try? person(idx: $0) }
    }

    /// `personRelations(forWord:)`(정방향, source_word 기준)의 역방향 — `target_word` 쪽을
    /// `personsAndPlaces(mentionedIn:)`와 같은 원칙(instr() 역방향 부분 문자열 검색, 2글자 미만 제외)으로
    /// 질의 문자열과 대조한다.
    ///
    /// target_word가 Persons/Places에 없어도(예: "골리앗") 매칭되므로
    /// `personOrPlace(exactWord:)`로는 대체할 수 없다.
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

    // MARK: - 키워드·카테고리 조회 / 인물 프로필 (2026-09-15 신설)
    //
    // `KeywordCategoryIndex`(인물/주제 표제어)로 카테고리만 먼저 확인하고, 콘텐츠는 카테고리에 맞는
    // 저장소(`persons(mentionedIn:)`/`themes(matching:)`)에서 따로 가져온다.

    /// `KeywordCategoryIndex`의 표제어가 질의 문자열 안에 부분 문자열로 있는지 확인해 카테고리(`'인물'`/`'주제'`)만
    /// 돌려준다. `instr(?, keyword) > 0` 패턴이라 한국어 조사가 뒤에 붙어도(다윗+은/이란 등) 잡힌다.
    ///
    /// `status = 'active'`만 조회한다 — `'pending'`은 AI 폴백으로 유입됐지만 아직 hit_count 승격 게이트를
    /// 못 넘은 항목이라 노출하지 않는다.
    public func keywordCategories(mentionedIn query: String) throws -> Set<String> {
        let sql = """
            SELECT DISTINCT category FROM KeywordCategoryIndex
            WHERE status = 'active' AND length(keyword) >= 2 AND instr(?, keyword) > 0
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        sqlite3_bind_text(statement, 1, query, -1, SQLITE_TRANSIENT)

        var results: Set<String> = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw BibleReferenceError.stepFailed(code: step) }
            if let category = sqlite3_column_text(statement, 0).map({ String(cString: $0) }) {
                results.insert(category)
            }
        }
        return results
    }

    /// 인물 프로필 카드 전용 조회 — `Persons`의 13개 보강 컬럼까지 전부 돌려준다.
    /// `personsAndPlaces(mentionedIn:)`(고정 5컬럼 UNION ALL)는 이 컬럼들을 담을 수 없어 분리했으며, 기존
    /// 메서드는 `handleRelation`이 여전히 쓰므로 그대로 둔다.
    ///
    /// `word2`(별칭, 콤마 구분)는 SQL `instr()`이 아니라 전체 로드 후 Swift에서 콤마 분리해 대조한다.
    /// `instr(query, word2)`는 별칭이 둘 이상이면(예: "고니야,여고냐") 콤마 포함 전체 문자열이 query 안에 있어야
    /// 참이라 대부분 거짓이 되기 때문이다.
    ///
    /// 반환 카드의 제목은 항상 `word`(대표 이름)이고, 별칭으로 매칭된 경우에만 `matchedAlias`를 채운다(화면은 별칭을
    /// 부제로만 보여준다).
    public func persons(mentionedIn query: String) throws -> [PersonEntity] {
        let sql = """
            SELECT idx, word, remark, verses, word2, call_title, meaning, introduce,
                   lifetime, event, character, origin, nation, tribe, gender, occupation, seed_memo,
                   rel_grandfather, rel_grandmother, rel_father, rel_mother, rel_spouse, rel_sons,
                   rel_daughters, rel_grandsons, rel_granddaughters
            FROM Persons
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }

        var results: [PersonEntity] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw BibleReferenceError.stepFailed(code: step) }
            func col(_ i: Int32) -> String { sqlite3_column_text(statement, i).map { String(cString: $0) } ?? "" }
            // `rel_*` 컬럼(콤마 구분, 빈 문자열이면 없음) 공용 파서.
            func relNames(_ i: Int32) -> [PersonFamilyMember] {
                col(i).split(separator: ",")
                    .map { Self.parseFamilyMember($0.trimmingCharacters(in: .whitespaces)) }
                    .filter { !$0.name.isEmpty }
            }

            let word = col(1)
            guard word.count >= 2 else { continue }

            let aliasCandidates = col(4).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            var matchedAlias: String?
            if !query.contains(word) {
                guard let hit = aliasCandidates.first(where: { $0.count >= 2 && query.contains($0) }) else { continue }
                matchedAlias = hit
            }

            let idx = col(0)
            let occupation = col(15).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            // 관계/참고 정보/소속 그룹은 이름이 아니라 idx로 조회한다 — 동명이인 카드가 서로의 정보를 가져가지 않게.
            let relations = (try? personRelationRecords(involvingIdx: idx, word: word)) ?? []
            let contextNotes = (try? personContextNotes(forIdx: idx, word: word)) ?? []
            let groupMemberships = (try? personGroupMemberships(forIdx: idx, word: word)) ?? []
            // SELECT 컬럼 순서: 0=idx 1=word 2=remark 3=verses 4=word2 5=call_title 6=meaning
            // 7=introduce 8=lifetime 9=event 10=character 11=origin 12=nation 13=tribe
            // 14=gender 15=occupation 16=seed_memo, 17~25=rel_* 아홉 개. 위 SELECT 문의 나열 순서와
            // 정확히 일치해야 한다(어긋나면 컴파일 에러 없이 조용히 틀린 값이 들어간다).
            let familyRelations = PersonFamilyRelations(
                grandfathers: relNames(17), grandmothers: relNames(18),
                fathers: relNames(19), mothers: relNames(20),
                spouses: relNames(21), sons: relNames(22),
                daughters: relNames(23), grandsons: relNames(24),
                granddaughters: relNames(25)
            )
            results.append(PersonEntity(
                idx: idx, word: word, aliases: aliasCandidates, entityRemark: col(2),
                verseRefs: Self.parseTargets(col(3)), matchedAlias: matchedAlias,
                callTitle: col(5), meaning: col(6), introduce: col(7), lifetime: col(8),
                event: col(9), character: col(10), origin: col(11), nation: col(12),
                tribe: col(13), gender: col(14), occupation: occupation, seedMemo: col(16),
                relations: relations, familyRelations: familyRelations, contextNotes: contextNotes,
                groupMemberships: groupMemberships
            ))
        }
        return Self.filterSwallowedNameMatches(results)
    }

    /// `Persons.idx`(유일 식별자)로 인물 하나를 바로 짚는다. `persons(mentionedIn:)`는 이름 기준이라 동명이인이
    /// 있으면 여러 건이 나와 화면이 어느 쪽인지 알 수 없지만, `PersonRelationRecord.targetIdx`가 채워진 경우(빌드
    /// 시점에 idx 확정)는 이름 재판정 없이 이 메서드로 대상을 확정할 수 있다.
    ///
    /// `idx`가 비어 있으면 nil을 돌려주고, 호출부는 이름 기준 동명이인 검사로 폴백한다.
    public func person(idx targetIdx: String) throws -> PersonEntity? {
        guard !targetIdx.isEmpty else { return nil }
        let sql = """
            SELECT idx, word, remark, verses, word2, call_title, meaning, introduce,
                   lifetime, event, character, origin, nation, tribe, gender, occupation, seed_memo,
                   rel_grandfather, rel_grandmother, rel_father, rel_mother, rel_spouse, rel_sons,
                   rel_daughters, rel_grandsons, rel_granddaughters
            FROM Persons WHERE idx = ?
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        sqlite3_bind_text(statement, 1, targetIdx, -1, SQLITE_TRANSIENT)

        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { return nil }
        guard step == SQLITE_ROW else { throw BibleReferenceError.stepFailed(code: step) }
        func col(_ i: Int32) -> String { sqlite3_column_text(statement, i).map { String(cString: $0) } ?? "" }
        // `persons(mentionedIn:)`와 같은 SELECT 컬럼 순서를 쓴다(WHERE 절만 다르다).
        func relNames(_ i: Int32) -> [PersonFamilyMember] {
            col(i).split(separator: ",")
                .map { Self.parseFamilyMember($0.trimmingCharacters(in: .whitespaces)) }
                .filter { !$0.name.isEmpty }
        }
        let word = col(1)
        let aliasCandidates = col(4).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let idx = col(0)
        let occupation = col(15).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let relations = (try? personRelationRecords(involvingIdx: idx, word: word)) ?? []
        let contextNotes = (try? personContextNotes(forIdx: idx, word: word)) ?? []
        let groupMemberships = (try? personGroupMemberships(forIdx: idx, word: word)) ?? []
        let familyRelations = PersonFamilyRelations(
            grandfathers: relNames(17), grandmothers: relNames(18),
            fathers: relNames(19), mothers: relNames(20),
            spouses: relNames(21), sons: relNames(22),
            daughters: relNames(23), grandsons: relNames(24),
            granddaughters: relNames(25)
        )
        // 항상 idx(유일 식별자)로 짚어 부르므로 별칭 매칭 경로를 타지 않는다 — `matchedAlias`는 항상 nil.
        return PersonEntity(
            idx: idx, word: word, aliases: aliasCandidates, entityRemark: col(2),
            verseRefs: Self.parseTargets(col(3)), matchedAlias: nil,
            callTitle: col(5), meaning: col(6), introduce: col(7), lifetime: col(8),
            event: col(9), character: col(10), origin: col(11), nation: col(12),
            tribe: col(13), gender: col(14), occupation: occupation, seedMemo: col(16),
            relations: relations, familyRelations: familyRelations, contextNotes: contextNotes,
            groupMemberships: groupMemberships
        )
    }

    /// 최장 일치 우선 — 다른 매치 후보의 이름 문자열 안에 완전히 포함되는 더 짧은 매치는 뺀다. 매칭 기준이
    /// `query.contains(word)`(부분 문자열)라, "아브라함"을 검색하면 그 안에 연속으로 들어 있는 "라함"(다른 실존
    /// 인물)도 함께 걸리는 문제를 막는다. "아브라함과 다윗"처럼 서로 포함관계가 아닌 이름은 둘 다 남는다.
    ///
    /// ⚠️ 적용 범위는 의도적으로 `persons(mentionedIn:)` 결과에 한정한다.
    /// `keywordCategories(mentionedIn:)`(SQL `instr()` 기반)도 원리상 같은 부분 문자열 오탐이
    /// 가능하지만, 그쪽은 카테고리 존재 여부만 판정하고 화면에 나열되는 것은 이 함수의 결과다.
    private static func filterSwallowedNameMatches(_ results: [PersonEntity]) -> [PersonEntity] {
        let matchedNames = results.map { $0.matchedAlias ?? $0.word }
        return results.filter { candidate in
            let name = candidate.matchedAlias ?? candidate.word
            return !matchedNames.contains { other in other != name && other.count > name.count && other.contains(name) }
        }
    }

    /// 이 인물(`idx`)이 source든 target이든 걸린 `PersonRelations` 전부(양방향) — `persons(mentionedIn:)`/
    /// `person(idx:)`가 `PersonEntity.relations`를 채울 때 쓴다.
    ///
    /// 기준은 이름이 아니라 `source_idx`/`target_idx`다. 이름(`source_word`/`target_word`)으로 찾으면 "예수"처럼
    /// 동명이인이 여럿인 이름은 세 사람이 모두 예수 그리스도의 열두 제자 관계를 그대로 받는다. 별칭(word2)으로 적힌
    /// 행(예: source_word "스보" = Persons "스비")도 idx로는 정확히 잡힌다.
    ///
    /// idx가 빈 행은 "빌드 시점에 신원을 특정하지 못함"이라(`target_idx` 컬럼 주석: 추측 금지) 이름이 `Persons`에서
    /// 유일할 때만 이름으로 이어 붙이고, 동명이인이 있는 이름이면 어느 쪽인지 알 수 없어 넣지 않는다.
    private func personRelationRecords(involvingIdx idx: String, word: String) throws -> [PersonRelationRecord] {
        let nameIsUnique = try isUniquePersonName(word)
        let sql = """
            SELECT source_word, relation_type, target_word, target_kind, raw_sentence, target_idx, source_idx
            FROM PersonRelations
            WHERE (source_idx <> '' AND source_idx = ?1)
               OR (target_idx <> '' AND target_idx = ?1)
               OR (?3 = 1 AND ((source_idx = '' AND source_word = ?2) OR (target_idx = '' AND target_word = ?2)))
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        sqlite3_bind_text(statement, 1, idx, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, word, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 3, nameIsUnique ? 1 : 0)

        var seen = Set<String>()
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
            let targetIdx = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? ""
            let sourceIdx = sqlite3_column_text(statement, 6).map { String(cString: $0) } ?? ""
            // 중복 제거 키에 idx를 넣는다 — 같은 이름의 다른 사람("야고보" 2명 등)을 같은 행으로 오인해 지우지 않게.
            let key = "\(sourceWord)#\(sourceIdx)|\(relationType)|\(targetWord)#\(targetIdx)"
            guard seen.insert(key).inserted else { continue }
            results.append(PersonRelationRecord(
                sourceWord: sourceWord, relationType: relationType, targetWord: targetWord,
                targetKind: targetKindRaw == "place" ? .place : (targetKindRaw == "person" ? .person : nil),
                rawSentence: rawSentence, targetIdx: targetIdx, sourceIdx: sourceIdx
            ))
        }
        return results
    }

    /// 이 이름의 인물이 `Persons`에 정확히 한 명일 때만 true. idx가 빈 관계/그룹/참고 행을 이름으로 이어 붙여도
    /// 되는지 판단하는 데 쓴다(동명이인이 있으면 어느 쪽 행인지 알 수 없다).
    private func isUniquePersonName(_ word: String) throws -> Bool {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, "SELECT COUNT(*) FROM Persons WHERE word = ?", -1, &statement, nil) == SQLITE_OK else {
            throw BibleReferenceError.statementPrepareFailed(code: sqlite3_errcode(handle))
        }
        sqlite3_bind_text(statement, 1, word, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_ROW else { return false }
        return sqlite3_column_int(statement, 0) == 1
    }

    // MARK: - Themes / Prophecies / TimelineEvents (2026-08-20 신설, 스키마만)
    //
    // `ReferenceEntity.swift`의 같은 이름 MARK 참고 — QueryIntentClassifier의
    // "예언/주제·속성/서사" 카테고리가 조회할 테이블. 스키마만 있고 아직 데이터가 없어(배포 전까지 항목 단위로 채울 예정) 아래 세
    // 메서드는 지금은 빈 배열을 반환한다.
    //
    // `search_keywords`는 콤마로 여러 값을 담는 자유 텍스트라 SQL `instr()` 하나로는 "질의 안에 이 키워드 중
    // 하나라도 있는지"를 걸러낼 수 없다. 세 테이블 모두 수작업으로 큐레이션하는 작은 테이블이라, 전체를 읽어 Swift 쪽에서 부분 문자열
    // 비교한다.
    //
    // ⚠️ 테이블이 비어 있어 실제 매칭 동작은 실측하지 못했다. 데이터가 들어간 뒤 실제 질의로 재확인할 것.

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

    /// 절 하나의 관주 대상만 필요할 때 쓰는 가벼운 버전.
    /// `crossReferences(bookId:chapter:translationCode:)`는 장 전체를 `@Model`로 감싸
    /// `translationCode`를 요구하는 UI 전용 API라, 좌표 목록만 필요한 내부 계산에는 이 메서드를 쓴다.
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
    // 토크나이저는 `unicode61` + prefix 쿼리(`"지혜"*`)다. 한국어는 조사/어미가 어근 뒤에만 붙는 교착어라 어절 앞부분
    // prefix 매칭이 조사 변화(지혜를/지혜가/지혜의/지혜로운…)를 모두 잡고, 3글자 미만 검색어도 그대로 동작한다. `trigram`은
    // 3글자 미만이면 MATCH가 조용히 0건을 내고 조사 변화에도 안정적이지 않았으며 인덱스도 약 2배 커서 쓰지 않는다.
    //
    // 한계: prefix 매칭이라 토큰 "맨 앞부터"만 잡히고 단어 중간 부분 문자열은 잡지 못한다.
    //
    // 여러 단어를 공백 포함해 한 번에 넘기는 경우는 검증하지 않았다 — 호출부가 단어로 쪼갠 뒤 한 단어씩 넘기는 용도로 설계했다.
    //
    // 검색어는 FTS5 쿼리 문법(AND/OR/NOT, 괄호, 콜론 등)으로 해석되지 않도록 항상 큰따옴표로 감싼 리터럴 구문으로 바인딩하고
    // 바깥에 `*`를 붙인다(내부 큰따옴표는 두 번 써서 이스케이프). "삼상 17:4" 같은 콜론 포함 텍스트나 "AND"/"OR" 단어도
    // 문법 에러 없이 "그 글자로 시작하는 토큰"을 찾는다.
    //
    // 정렬은 SQL에서 (book_id, chapter, verse) 오름차순으로 하고 `LIMIT`이 "성경순 앞쪽 N개"를 자른다.
    // 호출부(`SearchViewModel.searchVerses`)는 `rank`를
    // 읽지 않고 자체 재점수하므로 bm25 순 컷은 의미가 없고, 오히려 진짜 첫 등장 절이 상위 N개 밖으로 밀려 빠질 수 있다.
    // `limit`이 `nil`이면 자르지 않는다("더보기"용) — 31,102절 로컬 SQLite라 무제한 조회도 비용이 크지 않다.
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
