//
//  Book+Search.swift
//  JBCHBibleResearch
//
//  KoreanUtil.swift 상단 주석 참고 — 사용자가 이전에 실제로 쓰던 앱의
//  `BibleBook.matches(query:)` 로직을 이 프로젝트의 `Book`(BibleResearchModels) 타입에
//  맞춰 그대로 이식했다. 원본이 이미 고쳐 둔 버그(자음 하나만 입력해도 매 위치의
//  초성만 비교하고, 완성형 글자가 섞이면 그 위치는 정확히 같은 글자인지 비교하는
//  규칙 — "요"와 "여"가 둘 다 초성 "ㅇ"으로 뭉개져 오검색되는 걸 막음)까지 그대로
//  가져왔으므로 로직을 다시 검증하지 않고 신뢰했다.
//

import Foundation
import BibleResearchModels

extension Book {
    var choseong: String { KoreanUtil.extractChoseong(from: nameKo) }

    /// `query`가 이 책의 이름/약칭과 매칭되는지. screens.md 3장의 "요한복음 3장" 같은
    /// 자유 입력과, 책 그리드 피커의 검색창 둘 다 이 함수 하나로 처리한다.
    func matches(query: String) -> Bool {
        guard !query.isEmpty else { return true }
        if nameKo.contains(query) || abbreviation.contains(query) { return true }

        // 전부 자음(초성)만 입력했다면 초성 prefix 비교.
        if KoreanUtil.isChoseongOnly(query) {
            return choseong.hasPrefix(query)
        }

        // 완성형 글자가 섞여 있으면 위치별로 비교하되, 자음 한 글자가 온 위치는 그
        // 위치의 초성만, 완성형 글자가 온 위치는 정확히 같은 글자인지를 비교한다.
        let nameChars = Array(nameKo)
        let queryChars = Array(query)
        guard queryChars.count <= nameChars.count else { return false }

        for (i, qChar) in queryChars.enumerated() {
            let nChar = nameChars[i]
            let qScalar = qChar.unicodeScalars.first?.value ?? 0

            if qScalar >= 0x3131 && qScalar <= 0x314E {
                guard KoreanUtil.extractChoseong(from: String(nChar)).first == qChar else { return false }
            } else {
                guard qChar == nChar else { return false }
            }
        }
        return true
    }
}
