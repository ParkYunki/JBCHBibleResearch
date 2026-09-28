import Foundation

//
//  StringOrArray.swift
//  PersonSeedEditor
//
//  [2026-09-16 신설] PersonSeed.json의 관계 필드(할아버지/할머니/아버지/
//  어머니/배우자/아들/딸/손자/손녀)는 값이 없거나 하나면 순수 문자열("",
//  "노아"), 둘 이상이면 문자열 배열(["시돈", "헷"])로 섞여 저장돼 있다
//  (build_reference_data.py 쪽에서도 `[val] if isinstance(val, str) else val`
//  로 이미 같은 방식으로 다룬다 — 이 세션에서 python으로 실측 확인함,
//  9개 필드 중 배우자/아들/딸/손자/손녀 5개가 실제로 두 타입 다 나타남).
//  Swift `Codable`은 "문자열 아니면 배열"을 그대로 표현할 방법이 없어 이
//  enum으로 감싼다.
enum StringOrArray: Codable, Equatable {
    case string(String)
    case array([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let single = try? container.decode(String.self) {
            self = .string(single)
            return
        }
        let list = try container.decode([String].self)
        self = .array(list)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .array(let values):
            try container.encode(values)
        }
    }

    /// 화면(편집 UI)에서는 항상 이름 목록으로만 다룬다 — 빈 문자열은 빈
    /// 배열로, 그 외에는 원래 형태(문자열 1개/배열 N개)와 무관하게 이름
    /// 목록으로 통일해서 보여준다.
    var values: [String] {
        switch self {
        case .string(let value):
            return value.isEmpty ? [] : [value]
        case .array(let values):
            return values
        }
    }

    /// 편집 UI가 넘겨준 이름 목록을 다시 원본 관례(0~1개=문자열, 2개
    /// 이상=배열)로 되돌린다. 이 값을 실제로 디스크에 쓰는 건 Swift가
    /// 아니라 `apply_person_edit.py`(json.dump)이므로, 여기서 형태가 원본과
    /// 완전히 똑같이 유지되지 않아도(예: 원래 배열 1개였던 게 문자열로
    /// 바뀜) 의미상 손실은 없다 — build_reference_data.py가 두 형태 모두
    /// 동일하게 처리하기 때문. 다만 최대한 기존 관례를 따라 불필요한
    /// git diff 노이즈를 줄인다.
    static func fromValues(_ values: [String]) -> StringOrArray {
        let cleaned = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if cleaned.count <= 1 {
            return .string(cleaned.first ?? "")
        }
        return .array(cleaned)
    }
}
