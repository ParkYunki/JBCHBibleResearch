//
//  AppSection.swift
//  JBCHBibleResearch
//
//  screens.md 9.1 — 메인 창 사이드바(macOS/iPadOS) 항목 정의. "태그 관계"만 본문
//  영역을 바꾸지 않고 별도 창을 여는 예외라 opensSeparateWindow로 구분해 뒀다.
//

import Foundation

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case bibleReading
    // [2026-08-13 변경] 사용자 요청 — "왼쪽 사이드바 [개인 묵상], [말씀 요약]
    // 통합할 것 : 메뉴명 - [말씀 노트]." 기존 `.memos`(개인 묵상)/`.wordSummary`
    // (말씀 요약) 두 섹션을 이 케이스 하나로 합쳤다 — 실제 데이터(UserMemo/
    // VerseSummary)는 여전히 별개 모델이고, `WordNoteHomeView`가 카테고리
    // picker로 구분해 한 목록에 섞어 보여준다(그 파일 상단 주석 참고).
    case wordNote
    case documents
    case outline
    case tagRelations
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bibleReading: return "성경 조회"
        // [2026-08-13 변경] "개인 묵상"+"말씀 요약" 통합 메뉴명 — 사용자 요청
        // 문구를 그대로 썼다. 이전 이력(개인 주석→개인 묵상 개명 등)은
        // `WordNoteHomeView.swift` 상단 주석에 옮겨 적었다.
        case .wordNote: return "말씀 노트"
        case .documents: return "연구문서"
        case .outline: return "개요"
        case .tagRelations: return "태그 관계"
        case .search: return "통합 검색"
        }
    }

    var systemImage: String {
        switch self {
        case .bibleReading: return "book"
        case .wordNote: return "note.text"
        case .documents: return "doc.text"
        case .outline: return "list.bullet.rectangle"
        case .tagRelations: return "circle.grid.cross"
        case .search: return "magnifyingglass"
        }
    }

    /// screens.md 9.1 — 태그 관계 항목을 누르면 본문 영역을 바꾸는 대신 별도
    /// WindowGroup("tag-relations")을 연다(macOS/iPadOS 멀티윈도우 특성 활용).
    var opensSeparateWindow: Bool {
        self == .tagRelations
    }

    /// [2026-08-08 추가] PhoneTabView.swift(iPhone 탭바)가 직접 탭으로 노출하는
    /// 섹션만 모은 목록 — `.search`/`.tagRelations`는 탭바에 자리가 없다("더보기"
    /// 후보, 아직 미확정). `@FocusedValue(\.selectSection)`으로 들어온 값이 탭바에
    /// 없는 섹션이면 무시해야 하므로 그 판별에 쓴다.
    // [2026-08-13 변경] "개인 묵상"+"말씀 요약" 탭 통합 — `.wordNote` 하나로 대체.
    static var phoneTabBarSections: Set<AppSection> {
        [.wordNote, .bibleReading, .documents, .outline]
    }

    /// [2026-08-18 추가, 같은 날 검색창 이관으로 갱신] 사이드바(`SidebarNavigationView`)
    /// 목록에서 빼는 항목들.
    /// - `.tagRelations`: 사용자 요청 — "'태그 관계' 메뉴 삭제 - 기능 삭제는
    ///   추후 보류." case 자체와 `opensSeparateWindow`/WindowGroup("tag-relations")은
    ///   그대로 남겨 둔다(AppCommands.swift "태그 관계 보기" 메뉴 커맨드가 여전히
    ///   그 창을 직접 연다 — 기능은 살아 있고, 사이드바 진입점 하나만 없앤 것).
    /// - `.search`: 사용자 요청 — "왼쪽 사이드바 맨 위 상단 검색기능: 버튼이
    ///   아니라 검색 텍스트박스+버튼으로 배치." 지금까지 이 목록의 한 행(=버튼)
    ///   이었던 "통합 검색" 진입점을, 목록 위에 고정된 검색 텍스트박스+버튼으로
    ///   대체한다(`SidebarNavigationView.sidebarSearchBar` 참고) — 그 컨트롤이
    ///   `selection`을 직접 `.search`로 바꾸므로, 목록에 같은 목적의 행이 두 번
    ///   있을 필요가 없다. `.search` case/`SearchView` 자체는 그대로 남는다.
    static var sidebarMenuCases: [AppSection] {
        allCases.filter { $0 != .tagRelations && $0 != .search }
    }
}
