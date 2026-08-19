import Foundation

//
//  ReferenceEntity.swift
//  BibleResearchModels
//
//  [2026-08-19 신설] `ReferenceDataStore`의 Persons/Places/PersonRelations
//  조회 결과를 담는 값 타입. SwiftData `@Model`이 아니라 평범한 구조체다 —
//  `HanjaCharacterInfo`/`HanjaWordAnnotation`과 같은 원칙(정적 참조 데이터를
//  퍼시스턴스 레이어에 넣지 않는다, `ReferenceDataStore.swift` 상단 주석
//  참고).
//
//  ⚠️ [미검증] 이 세션엔 Xcode가 없어 컴파일 확인을 못 했다 — 배치 위치는
//  일단 `ReferenceData/` 폴더로 뒀지만, 이 패키지의 기존 관례상 더 맞는
//  위치(예: `Models/`)가 있다면 옮겨도 무방하다(이 타입들은 다른 파일을
//  참조하지 않는 순수 값 타입이라 이동 비용이 낮다).
//

/// `Persons`/`Places` 테이블 조회 결과 — 인물/지명 사전 한 항목.
public struct ReferenceEntity {
    public enum Kind {
        case person
        case place
    }

    public let idx: String
    public let word: String
    /// 원본 체크포인트의 "description" — 여러 동명이인 의미가 "1. ... 2. ..."
    /// 형태로 한 문자열에 섞여 있을 수 있다(원본 데이터의 한계, 스키마
    /// 문제 아님).
    public let entityDescription: String
    /// 이 이름이 언급되는 성경 좌표 전체 — 여러 동명이인의 verses가 섞여
    /// 있을 수 있다는 같은 한계가 적용된다.
    public let verseRefs: [BibleVerseRef]
    public let kind: Kind

    public init(idx: String, word: String, entityDescription: String, verseRefs: [BibleVerseRef], kind: Kind) {
        self.idx = idx
        self.word = word
        self.entityDescription = entityDescription
        self.verseRefs = verseRefs
        self.kind = kind
    }
}

/// `PersonRelations` 테이블 조회 결과 — 관계 하나("~의 아들/형제/지파" 등).
public struct PersonRelationRecord {
    public let sourceWord: String
    public let relationType: String
    public let targetWord: String
    /// nil이면 규칙 추출은 됐지만 대상 이름이 이 번들 데이터셋(체크포인트가
    /// 일부만 담고 있음) 안에서 확인되지 않은 경우 — 호출부는 이 경우
    /// `ReferenceDataStore.personOrPlace(exactWord:)`를 시도하지 말아야
    /// 한다(어차피 nil이 나옴, 조회 낭비 방지 목적으로 여기서 미리 구분).
    public let targetKind: ReferenceEntity.Kind?
    public let rawSentence: String

    public init(sourceWord: String, relationType: String, targetWord: String, targetKind: ReferenceEntity.Kind?, rawSentence: String) {
        self.sourceWord = sourceWord
        self.relationType = relationType
        self.targetWord = targetWord
        self.targetKind = targetKind
        self.rawSentence = rawSentence
    }
}

/// `VerseSearchIndex`(FTS5 trigram) 조회 결과 한 건.
public struct FullTextVerseMatch {
    public let bookId: Int
    public let chapter: Int
    public let verse: Int
    public let content: String
    /// SQLite `bm25()` 값 — 관례상 낮을수록(더 음수에 가까울수록) 관련성이
    /// 높다. UI에 그대로 노출하기보다는 정렬 기준으로만 쓰는 걸 권장한다
    /// (양수/음수 스케일이 사용자에게 직관적이지 않다).
    public let rank: Double

    public init(bookId: Int, chapter: Int, verse: Int, content: String, rank: Double) {
        self.bookId = bookId
        self.chapter = chapter
        self.verse = verse
        self.content = content
        self.rank = rank
    }
}
