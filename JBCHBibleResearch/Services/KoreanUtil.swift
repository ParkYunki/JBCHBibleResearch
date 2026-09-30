//
//  KoreanUtil.swift
//  JBCHBibleResearch
//
//  초성 검색 유틸(예: "ㅇㅎㅂㅇ"으로 "요한복음" 찾기). "요"/"여"가 초성 "ㅇ"으로 뭉개져 오검색되던 문제를
//  피하는 로직이 이미 들어 있다. `Book`용 확장은 `Book+Search.swift`에 있다.
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
