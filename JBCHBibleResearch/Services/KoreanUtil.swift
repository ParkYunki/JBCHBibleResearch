//
//  KoreanUtil.swift
//  JBCHBibleResearch
//
//  2026-08-06: 사용자가 이전에 만들어 쓰던 앱(BibleSeminarPresentationForIOS)의
//  KoreanUtil.swift를 그대로 이식했다 — 초성 검색(예: "ㅇㅎㅂㅇ"으로 "요한복음" 찾기)
//  로직이 이미 실제 사용 이력이 있고 완성도가 높아 새로 만들지 않고 그대로 가져왔다.
//  원본 파일의 로직/주석(요/여가 초성 "ㅇ"으로 뭉개져 오검색되던 버그와 그 수정
//  이유)도 그대로 유지한다. `BibleBook`(원본 앱의 책 모델)만 이 프로젝트의
//  `BibleResearchModels.Book`에 맞춰 별도 확장(`Book+Search.swift`)으로 옮겼다.
//

import Foundation

enum KoreanUtil {
    private static let choseongList: [Character] = [
        "ㄱ","ㄲ","ㄴ","ㄷ","ㄸ","ㄹ","ㅁ","ㅂ","ㅃ",
        "ㅅ","ㅆ","ㅇ","ㅈ","ㅉ","ㅊ","ㅋ","ㅌ","ㅍ","ㅎ"
    ]

    static func extractChoseong(from text: String) -> String {
        var result = ""
        for char in text {
            let v = char.unicodeScalars.first!.value
            if v >= 0xAC00 && v <= 0xD7A3 {
                result.append(choseongList[Int((v - 0xAC00) / (21 * 28))])
            } else if v >= 0x3131 && v <= 0x314E {
                result.append(char)
            }
        }
        return result
    }

    static func isChoseongOnly(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { $0.value >= 0x3131 && $0.value <= 0x314E }
    }
}
