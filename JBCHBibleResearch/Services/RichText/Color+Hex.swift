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
