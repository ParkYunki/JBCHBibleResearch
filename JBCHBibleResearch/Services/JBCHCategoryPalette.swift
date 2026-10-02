//
//  JBCHCategoryPalette.swift
//  JBCHBibleResearch
//
//  설정 카테고리 아이콘(`SettingsView.SettingsCategoryRow`)과 통합검색 분류 아이콘(`SearchView`)이 함께 쓰는
//  "구분용" 6색 팔레트. 두 화면에서 같은 이름의 색이 항상 같은 hex를 가리키도록 한 곳에 모은다.
//  기존 색(서재 금박/밤빛 남색/가죽 표지)에 같은 톤·채도의 서고 청람/와인 적갈/서가 슬레이트를 더했다.
//
//  ⚠️ 새 세 색의 hex는 공식 기준이 없는 제품 취향 값이다 — 바꾸려면 이 파일의 hex만 수정하면 된다.
//  ⚠️ 상태 배지(완료/대기/실패)와 참조 일치·태그 배지 색은 기능적 색이라 이 팔레트에 포함하지 않는다.
//

import SwiftUI

/// 설정 카테고리 아이콘·통합검색 분류 아이콘이 함께 쓰는 "구분용" 6색.
/// 각 항목에 어느 색을 배정할지는 화면(SettingsView/SearchView)의 몫이다 —
/// 이 enum은 색 자체의 정의만 갖는다.
enum JBCHCategoryPalette {
    /// 밤빛 남색 — `AccentColor` 다크모드 그러데이션과 같은 색(앱 아이콘 배경).
    /// 성경 본문/번역본처럼 "본문과 직접 관련된" 항목에 배정한다.
    static let navy = Color(hex: "#182644") ?? .indigo

    /// 서재 금박 — 퍼스널 컬러(`AccentColor.colorset`)와 같은 색. 선택/강조를 뜻하는 색이라 구분색으로도
    /// "사용자가 직접 다루는" 항목(모양 설정, 메모)에 한정해 배정한다.
    static let gold = Color(hex: "#B8863C") ?? .orange

    /// 가죽 표지 — 절제된 2차 구분색.
    static let wood = Color(hex: "#5A3826") ?? .brown

    /// 서고 청람 — 고서·서고 분위기의 차분한 청록.
    static let slateTeal = Color(hex: "#4F6D6A") ?? .teal

    /// 서고 청람을 흰색과 20% 섞은 변형. "밤빛 서재" 다크 배경(#182644) 위에서 원색 대비는 2.66:1로
    /// UI 구성요소 권장 최소치(3:1)에 못 미치고, 이 변형은 4.09:1이다.
    /// 어두운 배경일 때만 `PhoneTabView`의 `applyThemedTabBarAppearance`가 쓴다.
    static let slateTealOnDark = Color(hex: "#728A88") ?? .teal

    /// 밤빛 남색을 흰색과 40% 섞은 변형. 밤빛 남색(#182644)은 시스템 다크 모드의 회색 배경(예: #1C1C1E) 위에서
    /// 대비가 1.13:1로 거의 안 보인다. 이 변형은 같은 배경 위에서 4.11:1이다.
    /// `SettingsView`의 복사 형식 미리보기 카드가 시스템 다크 모드일 때만 쓴다.
    static let navyOnDark = Color(hex: "#747D8F") ?? .indigo

    /// 와인 적갈 — 차분한 적갈색.
    static let wine = Color(hex: "#7A3B42") ?? .pink

    /// 서가 슬레이트 — 채도를 낮춘 청회색.
    static let shelfSlate = Color(hex: "#46586B") ?? .gray

    // "문서함" 카드(`DocumentsHomeView`)의 책등 강조색. 가죽 표지/와인 적갈/서가 슬레이트 원색은 "밤빛 서재"(#182644)
    // 위에서 대비가 부족해(약 2.1:1 / 2.4:1 / 3.0:1, UI 구성요소 권장 최소 3:1) `slateTealOnDark`/`navyOnDark`와
    // 같은 방식(흰색과 섞기)으로 밤빛 남색 대비 4.2:1 이상이 되게 만든 변형이다.

    /// 가죽 표지를 흰색과 40% 섞은 변형 — 밤빛 남색 대비 4.45:1.
    static let woodOnDark = Color(hex: "#9C887D") ?? .brown

    /// 가죽 표지를 흰색과 55% 섞은 "글자용" 변형(2026-10-02). `woodOnDark`(40%)는 밤빛 남색 위 4.3:1이라 작은 글씨(12pt 안팎의
    /// 배지·좌표 글자)에 4.5:1 미만이다. 이 변형은 글자가 놓이는 어두운 배경 4종(중립 다크 #2A2927, 남색 테마 #1D2744, 시스템 다크 #1C1C1E,
    /// 밤빛 남색 #182644) 위에서 6.1~7.2:1이고, 같은 색 15% 틴트 배지 위에서도 4.6~5.4:1이다. 가죽 표지 원색(#5A3826)은 같은 배경에서 1.4~1.6:1이라
    /// 거의 보이지 않는다. `WordNoteCategory.spineColor(onDark:)`가 어두운 면에서만 쓴다.
    static let woodTextOnDark = Color(hex: "#B5A59D") ?? .brown

    /// 와인 적갈을 흰색과 40% 섞은 변형 — 밤빛 남색 대비 4.85:1.
    static let wineOnDark = Color(hex: "#AF898E") ?? .pink

    /// 서가 슬레이트를 흰색과 30% 섞은 변형 — 밤빛 남색 대비 4.27:1.
    static let shelfSlateOnDark = Color(hex: "#7E8A97") ?? .gray
}
