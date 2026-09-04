//
//  BibleSlideColorTheme.swift
//  JBCHBibleResearch
//
//  [2026-09-01 신설] 사용자 요청 — "설정 - 성경 - 모양에 (배경색/글자색) 테마색상
//  추가할 것". 배경색과 글자색을 한 쌍으로 묶어 "테마" 하나로 고를 수 있게 하는
//  용도 — 배경/글자색을 각각 따로 고르다 대비가 나쁜 조합(예: 밝은 배경 + 밝은
//  글자)이 되는 걸 막아준다. `AppearanceSettingsTab`의 테마 선택 UI가 이 목록을
//  그대로 쓴다.
//
//  [2026-09-04 전면 개정] 사용자 요청 — "(공통) 설정 - 성경 - 모양의 테마
//  색상을 전면수정하여 퍼스널 컬러 팔레트를 기본으로 하여 조합을 만들어서
//  제공하도록." 기존 5개(네이비 그레이/아이보리/다크 슬레이트/딥 블루/딥
//  그린 슬레이트)는 팔레트 작업 이전에 사용자가 그대로 준 임의의 배경/글자
//  색이었다 — 이제 퍼스널 컬러 팔레트(서재 금박/밤빛 남색/가죽 표지/책장
//  아이보리/연한 금박, `JBCHCategoryPalette.swift`의 서고 청람 포함)의 색만
//  조합해 다시 짰다. 5개 모두 이름이 가리키는 그 팔레트 색을 "배경 또는
//  글자" 중 한쪽에 실제로 그대로 쓴다(임의 색 없음).
//
//  ⚠️ [배경으로 쓸 때 어둡게 조정한 것] "서재 아이보리"(팔레트의 책장
//  아이보리를 그대로 배경으로 씀)를 뺀 나머지 4개는 어두운 배경 위에 밝은
//  글자를 놓는 구성이라, 팔레트의 액센트용 원색(서재 금박·서고 청람 등)을
//  그대로 큰 배경 면적에 칠하면 장시간 읽기엔 너무 밝거나(대비 과다/눈부심)
//  대비가 부족해질 수 있다 — 그래서 배경으로 쓸 때만 톤을 낮췄다(글자색은
//  전부 팔레트 원색 그대로). 아래 각 조합은 WCAG 2.1 상대 휘도 공식으로 대비
//  비율을 실제로 계산해 확인했다(전부 일반 텍스트 기준 AA 최소 4.5:1 이상):
//  서재 아이보리 15.1:1 · 밤빛 서재 9.3:1 · 가죽 서고 9.1:1 · 서고 청람 8.1:1
//  · 와인 저녁 7.3:1.
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

    /// 퍼스널 컬러 팔레트 기반 5가지 테마 조합 — 위 2026-09-04 개정 주석 참고.
    static let all: [BibleSlideColorTheme] = [
        // 책장 아이보리(#F7F0E2) 배경 그대로 + 짙은 잉크색 글자 — 밝은 화면을
        // 선호할 때의 기본값. 대비 15.1:1.
        BibleSlideColorTheme(name: "서재 아이보리", backgroundHex: "#F7F0E2", textHex: "#241A10"),
        // 밤빛 남색(#182644) 배경 그대로 + 연한 금박(#E4C98A) 글자 — 이미
        // `AccentColor` 다크모드가 쓰는 것과 같은 남색·금색 조합. 대비 9.3:1.
        BibleSlideColorTheme(name: "밤빛 서재", backgroundHex: "#182644", textHex: "#E4C98A"),
        // 가죽 표지(#5A3826) 배경 그대로 + 책장 아이보리 글자 — 가죽 장정
        // 책을 펼친 듯한 조합. 대비 9.1:1.
        BibleSlideColorTheme(name: "가죽 서고", backgroundHex: "#5A3826", textHex: "#F7F0E2"),
        // 서고 청람(`JBCHCategoryPalette.slateTeal` #4F6D6A)은 원색 그대로는
        // 대비가 4.97:1로 다소 빠듯해, 배경 전용으로 한 단계 어둡게 낮춘 값
        // (#374C4A)을 썼다 — 글자색은 책장 아이보리 그대로. 대비 8.1:1.
        BibleSlideColorTheme(name: "서고 청람", backgroundHex: "#374C4A", textHex: "#F7F0E2"),
        // 와인 적갈(#7A3B42) 배경 그대로 + 책장 아이보리 글자. 대비 7.3:1.
        BibleSlideColorTheme(name: "와인 저녁", backgroundHex: "#7A3B42", textHex: "#F7F0E2"),
    ]
}
