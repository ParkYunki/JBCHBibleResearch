//
//  Color+Hex.swift
//  JBCHBibleResearch
//
//  `RichTextEditor`(Views/Memo/RichTextEditor.swift)의 색상 서식 툴바(iOS)는
//  하드코딩된 hex 문자열 팔레트에서만 고른다 — SwiftUI Color에서 값을 다시
//  읽어낼 안전한 공개 API가 없어서(이미 만들어진 Color가 불투명 타입이라
//  원래 hex를 되돌려 받을 방법이 없다), 팔레트 자체를 hex 문자열로 정의해 둔다.
//  이 확장은 그 hex 문자열을 화면에 그릴 때만 Color로 "만드는" 단방향 변환이다.
//
//  [2026-09-01 추가] 위 제약이 이제 일부 해소됐다 — 사용자가 "성경 조회 배경색/
//  글자색에 팔레트뿐 아니라 컬러피커(자유 선택)도 제공할 것"을 요청해, Apple
//  공식 문서(iOS 17.0+/macOS 14.0+) 기준 `Color.resolve(in:) -> Color.Resolved`가
//  이제 "Color에서 값을 다시 읽어내는 안전한 공개 API"임을 확인했다. 다만
//  `Color.Resolved.red/green/blue`는 **Linear sRGB**(감마 보정 전, extended-range)
//  Float라 — 그대로 255를 곱해 hex로 쓰면 실제 화면에 보이는 색보다 어둡게
//  나온다 — 표준(감마 보정된) sRGB로 변환한 뒤에 hex로 인코딩해야 `ColorPicker`가
//  보여주는 색과 저장되는 hex가 일치한다(`hexString(in:)` 참고). 기존
//  `memoTextPalette`처럼 "미리 정한 팔레트에서만 고른다"는 제약은 그 자체로도
//  여전히 유효한 설계(메모 색이 중구난방 안 되게)라 손대지 않았고, 이번 추가는
//  성경 조회 배경/글자색처럼 사용자가 더 세밀하게 고르고 싶어할 수 있는 곳에
//  한해 별도로 컬러피커 경로를 마련한 것이다.
//
//  [2026-09-02 수정] 사용자 요청으로 성경 조회 "배경색"/"본문 색상" 팔레트
//  Picker 자체를 없애고 위 컬러피커만 남기게 되면서, 그 팔레트 Picker
//  전용으로 있던 `bibleBackgroundPalette`도 함께 지웠다(더 이상 쓰는 곳이
//  없음) — `memoTextPalette`는 `RichTextEditor.swift`가 여전히 쓰므로 그대로
//  둔다.
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

    /// [2026-09-01 추가] `ColorPicker`로 고른 임의의 색을 "#RRGGBB" hex 문자열로
    /// 바꾼다 — `UserSettingsStore`가 색을 hex 문자열로 저장하는 기존 관례
    /// (`bibleTextColorHex` 등)를 그대로 따르기 위함. `Color.resolve(in:)`가
    /// 요구하는 `EnvironmentValues`는 View 안에서 `@Environment(\.self)`로 얻어
    /// 넘겨야 한다. 위 파일 상단 주석 참고 — resolve 결과는 Linear sRGB라 감마
    /// 보정(`toGammaCorrectedSRGB`)을 거쳐야 화면에 보이는 색과 같은 hex가 나온다.
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

    /// 인라인 색상 서식용 소수 팔레트. 임의의 컬러피커 대신 미리 정한 몇 가지로
    /// 제한한다 — 10.1의 "태그 팔레트 제외" 원칙과 같은 취지로, 메모마다 색이
    /// 중구난방이 되는 걸 막기 위함. ⚠️ 원문서에 구체적인 팔레트가 명시돼 있지 않아
    /// 합리적인 기본값을 골랐다 — 필요시 조정 가능.
    static let memoTextPalette: [(name: String, hex: String)] = [
        ("검정", "#1A1A1A"),
        ("빨강", "#D32F2F"),
        ("주황", "#F57C00"),
        ("초록", "#388E3C"),
        ("파랑", "#1976D2"),
        ("보라", "#7B1FA2"),
    ]
}
