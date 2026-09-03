//
//  BibleSlideColorTheme.swift
//  JBCHBibleResearch
//
//  [2026-09-01 신설] 사용자 요청 — "설정 - 성경 - 모양에 (배경색/글자색) 테마색상
//  추가할 것", 아래 스펙(사용자가 그대로 준 5가지 테마)을 반영한다. 배경색과
//  글자색을 한 쌍으로 묶어 "테마" 하나로 고를 수 있게 하는 용도 — 배경/글자색을
//  각각 따로 고르다 대비가 나쁜 조합(예: 밝은 배경 + 밝은 글자)이 되는 걸
//  막아준다. `AppearanceSettingsTab`의 테마 선택 UI가 이 목록을 그대로 쓴다.
//
//  각 색은 hex 문자열로만 들고 있다 — `UserSettingsStore`가 배경/글자색을 hex
//  문자열로 저장하는 기존 관례(`bibleTextColorHex` 등)와 맞추기 위함이고,
//  실제 SwiftUI `Color`는 화면에 그릴 때만 `Color+Hex.swift`의 기존 단방향
//  변환(`Color(hex:)`)으로 만든다.
//

import SwiftUI

struct BibleSlideColorTheme: Identifiable {
    let name: String
    let backgroundHex: String
    let textHex: String

    var id: String { name }

    var background: Color { Color(hex: backgroundHex) ?? .black }
    var text: Color { Color(hex: textHex) ?? .white }

    /// 사용자가 그대로 준 5가지 테마 조합.
    static let all: [BibleSlideColorTheme] = [
        BibleSlideColorTheme(name: "네이비 그레이", backgroundHex: "#1E222A", textHex: "#E8E6E3"),
        BibleSlideColorTheme(name: "아이보리", backgroundHex: "#F5F1E8", textHex: "#3A332C"),
        BibleSlideColorTheme(name: "다크 슬레이트", backgroundHex: "#2B2B2F", textHex: "#F2F2F2"),
        BibleSlideColorTheme(name: "딥 블루", backgroundHex: "#11151C", textHex: "#F4F1DE"),
        BibleSlideColorTheme(name: "딥 그린 슬레이트", backgroundHex: "#1F3328", textHex: "#ECE8E1"),
    ]
}
