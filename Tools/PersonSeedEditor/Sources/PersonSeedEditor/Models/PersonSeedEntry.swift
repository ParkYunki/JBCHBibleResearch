import Foundation

//
//  PersonSeedEntry.swift
//  PersonSeedEditor
//
//  [2026-09-16 신설] PersonSeed.json 항목 하나(~3068건)를 그대로 옮긴 모델.
//  이 세션에서 실제 파일을 파이썬으로 읽어 키 목록/타입을 확인하고 만들었다
//  (idx/kind2/kind/word/word2/call/meaning/introduce/lifetime/event/
//  character/description/remark/memo/verses — 최상위 15개 키, 순서까지
//  실제 파일과 동일). 메인 앱(JBCHBibleResearch)의 `PersonEntity`/
//  `PersonFamilyRelations`(영문 필드명)와 이름 규칙을 맞추되, JSON 키는
//  한글 그대로라 `CodingKeys`로 매핑한다.
//
//  ⚠️ 이 구조체가 모델링하지 않은 키가 원본에 생기면(예: 나중에 필드 추가)
//  디코딩은 그 키를 조용히 무시하고, 저장(업서트) 시에는 그 키가 통째로
//  사라진다 — `Codable`의 구조적 한계다. 지금은 실제 파일의 최상위/중첩
//  키를 전부 반영했으므로 문제 없지만, 앞으로 PersonSeed.json 스키마가
//  바뀌면 이 파일도 함께 업데이트해야 한다.
struct PersonSeedEntry: Codable, Identifiable, Equatable {
    var idx: String
    var kind2: String
    var kind: String
    var word: String
    var word2: [String]
    var call: String
    var meaning: String
    var introduce: String
    var lifetime: String
    var event: String
    var character: String
    var description: PersonSeedDescription
    var remark: String
    var memo: String
    var verses: [String]

    var id: String { idx }

    /// "새 인물 추가" 버튼이 만드는 빈 항목 — 문자열은 전부 빈 문자열,
    /// 배열은 빈 배열, `관계`는 원본 관례대로 길이 1짜리 배열 안에 빈
    /// 관계 dict 하나를 담는다(원본 파일이 예외 없이 이 모양이라는 것을
    /// 이 세션에서 python으로 실측 확인함 — "관계 always list-of-1? {1}").
    static func blank(idx: String) -> PersonSeedEntry {
        PersonSeedEntry(
            idx: idx, kind2: "0", kind: "인명", word: "", word2: [],
            call: "", meaning: "", introduce: "", lifetime: "", event: "", character: "",
            description: PersonSeedDescription(
                origin: "", nation: "", tribe: "", gender: "", occupations: [],
                relations: [PersonSeedRelationBlock.blank]
            ),
            remark: "", memo: "", verses: []
        )
    }
}

struct PersonSeedDescription: Codable, Equatable {
    var origin: String
    var nation: String
    var tribe: String
    var gender: String
    var occupations: [String]
    /// 원본은 이 배열이 항상 길이 1이다(관계 정보가 아예 없는 사람도 빈
    /// dict 하나를 담은 배열) — 하지만 "혹시 0개나 2개 이상인 항목이
    /// 있을 가능성"까지 구조적으로 막아버리진 않는다(디코딩 실패로 이어질
    /// 수 있는 과도한 가정 지양). 편집 화면은 `relations.first`만 쓴다.
    var relations: [PersonSeedRelationBlock]

    enum CodingKeys: String, CodingKey {
        case origin = "출신"
        case nation = "민족"
        case tribe = "지파"
        case gender = "성별"
        case occupations = "직업/직위"
        case relations = "관계"
    }
}

struct PersonSeedRelationBlock: Codable, Equatable {
    var grandfather: StringOrArray
    var grandmother: StringOrArray
    var father: StringOrArray
    var mother: StringOrArray
    var spouse: StringOrArray
    var sons: StringOrArray
    var daughters: StringOrArray
    var grandsons: StringOrArray
    var granddaughters: StringOrArray
    var otherRelations: [String]

    enum CodingKeys: String, CodingKey {
        case grandfather = "할아버지"
        case grandmother = "할머니"
        case father = "아버지"
        case mother = "어머니"
        case spouse = "배우자"
        case sons = "아들"
        case daughters = "딸"
        case grandsons = "손자"
        case granddaughters = "손녀"
        case otherRelations = "기타관계"
    }

    static let blank = PersonSeedRelationBlock(
        grandfather: .string(""), grandmother: .string(""),
        father: .string(""), mother: .string(""),
        spouse: .string(""), sons: .string(""), daughters: .string(""),
        grandsons: .string(""), granddaughters: .string(""),
        otherRelations: []
    )
}
