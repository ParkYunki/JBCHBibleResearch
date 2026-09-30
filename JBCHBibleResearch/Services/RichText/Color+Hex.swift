//
//  Color+Hex.swift
//  JBCHBibleResearch
//
//  SwiftUI `Color`와 hex 문자열 사이의 변환 확장.
//  - `init?(hex:)`: hex 팔레트 문자열을 화면에 그릴 Color로 만드는 단방향 변환.
//  - `hexString(in:)`: `ColorPicker`로 고른 임의의 색을 "#RRGGBB"로 되돌린다
//    (`Color.resolve(in:)`, iOS 17.0+/macOS 14.0+).
//  - `memoTextPalette`: `RichTextEditor`(Views/Memo/RichTextEditor.swift)의
//    색상 서식 툴바가 고르는 고정 hex 팔레트.
//

import Foundation
import SwiftUI

extension Color {
    init?(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") { hexString.removeFirst() }
        guard hexString.count == 6, let value = UInt32(hexString, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }

    /// `ColorPicker`로 고른 색을 "#RRGGBB" hex 문자열로 바꾼다(`UserSettingsStore`의 hex 저장 관례).
    /// `environment`는 View 안에서 `@Environment(\.self)`로 얻어 넘겨야 한다.
    /// `resolve(in:)` 결과는 Linear sRGB라 감마 보정을 거쳐야 화면에 보이는 색과 같은 hex가 나온다.
    func hexString(in environment: EnvironmentValues) -> String {
        let resolved = resolve(in: environment)
        func toGammaCorrectedSRGB(_ linear: Float) -> Float {
            let clamped = min(max(linear, 0), 1)
            return clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
        }
        let r = Int((toGammaCorrectedSRGB(resolved.red) * 255).rounded())
        let g = Int((toGammaCorrectedSRGB(resolved.green) * 255).rounded())
        let b = Int((toGammaCorrectedSRGB(resolved.blue) * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// 인라인 색상 서식용 소수 팔레트. 메모마다 색이 중구난방이 되지 않도록 미리 정한 몇 가지로 제한한다.
    /// ⚠️ 구체적인 팔레트가 원문서에 없어 임의로 고른 기본값이다.
    static let memoTextPalette: [(name: String, hex: String)] = [
        ("검정", "#1A1A1A"),
        ("빨강", "#D32F2F"),
        ("주황", "#F57C00"),
        ("초록", "#388E3C"),
        ("파랑", "#1976D2"),
        ("보라", "#7B1FA2"),
    ]
}
