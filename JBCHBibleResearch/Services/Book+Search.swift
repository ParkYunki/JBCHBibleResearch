//
//  Book+Search.swift
//  JBCHBibleResearch
//
//  `KoreanUtil`의 초성 유틸 기반 책 이름 검색. 원본 앱의 `BibleBook.matches(query:)` 로직을
//  이식했다. 자음만 입력하면 초성 prefix로 비교하고, 완성형 글자가 섞이면 위치별로 비교한다
//  ("요"와 "여"가 둘 다 초성 "ㅇ"으로 뭉개져 오검색되는 것을 막음).
//

import Foundation
import BibleResearchModels

extension Book {
    var choseong: String { KoreanUtil.extractChoseong(from: nameKo) }

    /// `query`가 이 책의 이름/약칭과 매칭되는지. 자유 입력과 책 그리드 피커의 검색창이 함께 쓴다.
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

    /// [2026-10-29 bookgrid1] 책 그리드 피커 검색창 전용. 먼저 `matches(query:)`(한국어 이름·약칭·초성)로 비교하고,
    /// 한국어가 아닌 앱에서는 앱 언어 책 이름/약칭(`displayName`/`displayShortName`)도 대소문자 무시·부분 일치로 비교한다
    /// (예: 중국어 "创"·"创世" → 创世纪, 영어 "gen" → Genesis).
    /// - 한국어 앱은 `matches(query:)` 결과 그대로다. 한국어에서 `displayShortName`(`abbreviation.first`)을 부분 일치로
    ///   더 비교하면 `matches`의 약칭 비교(배열 원소와 정확히 같은지)보다 넓어져 기존 결과가 바뀌므로 비교하지 않는다.
    /// - `matches(query:)`는 `matchBookPrefix`의 초성 단계도 쓰므로 의미를 바꾸지 않고 이 함수를 따로 둔다.
    func matchesGridSearch(query: String) -> Bool {
        guard !query.isEmpty else { return true }
        if matches(query: query) { return true }
        guard !AppLanguage.isKorean else { return false }
        return displayName.localizedCaseInsensitiveContains(query)
            || displayShortName.localizedCaseInsensitiveContains(query)
    }
}
