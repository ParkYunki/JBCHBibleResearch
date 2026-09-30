//
//  AppSection.swift
//  JBCHBibleResearch
//
//  메인 창 사이드바(macOS/iPadOS) 항목 정의. "태그 관계"만 본문 영역을 바꾸지 않고
//  별도 창을 여는 예외라 opensSeparateWindow로 구분한다.
//

import Foundation

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case bibleReading
    // 개인 묵상(UserMemo)과 말씀 요약(VerseSummary)은 데이터 모델이 별개지만
    // 메뉴는 이 케이스 하나로 통합했다. `WordNoteHomeView`가 카테고리 picker로 구분한다.
    case wordNote
    case documents
    // "내 설교". iPhone에서는 `.searchable`을 쓰는 화면이라 `.tagRelations`/`.outline`처럼
    // 탭바가 아닌 "더보기" 안 전체화면 모달로 연다(`PlaceholderScreens.swift` 참고).
    case sermons
    case outline
    case tagRelations
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bibleReading: return "성경 조회"
        case .wordNote: return "말씀 노트"
        case .documents: return "연구 문서"
        case .sermons: return "내 설교"
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
        case .sermons: return "mic"
        case .outline: return "list.bullet.rectangle"
        case .tagRelations: return "circle.grid.cross"
        case .search: return "magnifyingglass"
        }
    }

    /// 태그 관계 항목은 본문 영역을 바꾸는 대신 별도 WindowGroup("tag-relations")을 연다.
    var opensSeparateWindow: Bool {
        self == .tagRelations
    }

    /// iPhone 탭바(`PhoneTabView`)가 직접 탭으로 노출하는 섹션. `@FocusedValue(\.selectSection)`으로
    /// 들어온 값이 탭바에 없는 섹션이면 무시해야 하므로 그 판별에 쓴다.
    /// `.outline`/`.tagRelations`는 탭바가 아니라 "더보기" 안 전체화면 모달로 연다.
    static var phoneTabBarSections: Set<AppSection> {
        [.wordNote, .bibleReading, .documents, .search]
    }

    /// 사이드바(`SidebarNavigationView`) 목록에서 빼는 항목.
    /// - `.tagRelations`: 사이드바 진입점만 없앴다. case와 WindowGroup("tag-relations")은
    ///   유지되며 AppCommands의 "태그 관계 보기" 메뉴 커맨드가 여전히 그 창을 연다.
    /// - `.search`: 목록 위 고정 검색창(`SidebarNavigationView.sidebarSearchBar`)이
    ///   `selection`을 직접 `.search`로 바꾸므로 목록에 같은 목적의 행을 두지 않는다.
    static var sidebarMenuCases: [AppSection] {
        allCases.filter { $0 != .tagRelations && $0 != .search }
    }
}
