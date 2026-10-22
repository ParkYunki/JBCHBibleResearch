//
//  VerseTextFingerprint.swift
//  JBCHBibleResearch
//
//  [2026-10-21] 사용자 추가 번역본 인식용 절 본문 지문.
//  생성 스크립트 `Tools/LiteralGen/ext_hashes.py`와 규칙이 **완전히 같아야** 한다:
//  1) NFC 정규화  2) A–Z는 소문자로  3) a–z, 0–9, 한글 음절(U+AC00–U+D7A3)만 남김(공백·구두점·괄호·그 밖 문자는 버림)
//  4) 남은 문자열 UTF-8의 SHA-256 앞 8바이트를 빅엔디언 부호 있는 64비트 정수로.
//  남은 문자가 없으면 nil(지문 없음).
//

import Foundation
import CryptoKit

nonisolated enum VerseTextFingerprint {
    static func normalized(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.precomposedStringWithCanonicalMapping.unicodeScalars {
            switch scalar.value {
            case 0x41...0x5A:
                if let lower = Unicode.Scalar(scalar.value + 0x20) { scalars.append(lower) }
            case 0x61...0x7A, 0x30...0x39, 0xAC00...0xD7A3:
                scalars.append(scalar)
            default:
                continue
            }
        }
        return String(scalars)
    }

    static func hash(of text: String) -> Int64? {
        let normalizedText = normalized(text)
        guard !normalizedText.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(normalizedText.utf8))
        var value: UInt64 = 0
        for byte in digest.prefix(8) {
            value = (value << 8) | UInt64(byte)
        }
        return Int64(bitPattern: value)
    }
}
