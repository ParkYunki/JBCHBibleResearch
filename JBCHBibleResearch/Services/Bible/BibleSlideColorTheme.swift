//
//  BibleSlideColorTheme.swift
//  JBCHBibleResearch
//
//  배경색과 글자색을 한 쌍으로 묶은 "테마" 목록 — 각각 따로 고르다 대비가 나쁜 조합이 되는 것을 막는다.
//  `AppearanceSettingsTab`의 테마 선택 UI가 이 목록을 그대로 쓴다.
//
//  색은 퍼스널 컬러 팔레트(`JBCHCategoryPalette.swift` 참고)의 색만 조합했다. 어두운 배경 구성에서는
//  눈부심/대비 부족을 피하려고 배경으로 쓸 때만 팔레트 원색의 톤을 낮췄고, 각 조합의 대비는
//  WCAG 2.1 상대 휘도 공식으로 계산해 AA 기준(4.5:1) 이상임을 확인했다.
//
//  색은 hex 문자열로만 들고 있다 — `UserSettingsStore`가 hex로 저장하는 관례(`bibleTextColorHex` 등)와
//  맞추기 위함이며, SwiftUI `Color`는 그릴 때만 `Color(hex:)`(`Color+Hex.swift`)로 만든다.
//

import SwiftUI

struct BibleSlideColorTheme: Identifiable {
    let name: String
    let backgroundHex: String
    let textHex: String

    var id: String { name }

    var background: Color { Color(hex: backgroundHex) ?? .black }
    var text: Color { Color(hex: textHex) ?? .white }

    /// 선택 가능한 테마 목록 — 라이트(서재 아이보리)와 다크(밤빛 서재) 두 가지.
    static let all: [BibleSlideColorTheme] = [
        // 책장 아이보리(#F7F0E2) 배경 + 짙은 잉크색 글자, 대비 15.1:1.
        // `UserSettingsStore.BibleThemeModePreference.light`가 이 이름으로 찾아 쓴다.
        BibleSlideColorTheme(name: "서재 아이보리", backgroundHex: "#F7F0E2", textHex: "#241A10"),
        // 밤빛 남색(#182644) 배경 + 연한 금박(#E4C98A) 글자, 대비 9.3:1 (`AccentColor` 다크모드와 같은 조합).
        // `UserSettingsStore.BibleThemeModePreference.dark`가 이 이름으로 찾아 쓴다.
        BibleSlideColorTheme(name: "밤빛 서재", backgroundHex: "#182644", textHex: "#E4C98A"),
    ]
}
