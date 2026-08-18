//
//  AppFocusedValues.swift
//  JBCHBibleResearch
//
//  screens.md 11장(macOS 메뉴 바) — "메뉴 항목은 해당 컨텍스트에 포커스가 없으면
//  비활성화됩니다"를 그대로 구현하는 방법으로 `FocusedSceneValue`를 썼다.
//
//  ⚠️ [설계 결정, 근거] 처음엔 사이드바 선택 상태를 앱 전역 싱글턴(@Observable
//  static shared)으로 옮겨서 메뉴가 직접 조작하게 하려 했으나, 이 앱의 메인
//  WindowGroup은 macOS에서 여러 창으로 동시에 열릴 수 있다(File > New Window 등
//  표준 동작 — WindowGroup(id:for:)로 단일 인스턴스 제한을 걸지 않았다). 전역
//  싱글턴을 쓰면 창 A에서 "성경조회"를 선택했을 때 창 B의 사이드바까지 같이
//  바뀌는 버그가 생긴다. `FocusedSceneValue`는 "지금 활성(키) 상태인 창/씬"에만
//  값을 연결하므로 이 문제가 없다 — 각 화면(SidebarNavigationView, MemoHomeView,
//  DocumentsHomeView, BibleReadingView)이 자기 로컬 `@State`는 그대로 유지한 채
//  `.focusedSceneValue`로 액션 클로저만 밖으로 노출하고, `AppCommands.swift`가
//  `@FocusedValue`로 그 클로저를 읽어 메뉴 버튼에 연결한다.
//

import SwiftUI

// MARK: - 사이드바(View 메뉴 — 화면 전환, 사이드바 토글)

private struct SelectSectionKey: FocusedValueKey { typealias Value = (AppSection) -> Void }
private struct ToggleSidebarKey: FocusedValueKey { typealias Value = () -> Void }

// MARK: - 메모(File 메뉴 — 새 메모/새 폴더)

private struct NewMemoActionKey: FocusedValueKey { typealias Value = () -> Void }
private struct NewFolderActionKey: FocusedValueKey { typealias Value = () -> Void }

// MARK: - 연구문서(File 메뉴 — 업로드)

private struct UploadDocumentActionKey: FocusedValueKey { typealias Value = () -> Void }

// MARK: - 성경 조회(Bible 메뉴 — 다음/이전 장, View 메뉴 — 스크롤 동기화)

private struct NextChapterActionKey: FocusedValueKey { typealias Value = () -> Void }
private struct PreviousChapterActionKey: FocusedValueKey { typealias Value = () -> Void }
private struct ScrollSyncEnabledKey: FocusedValueKey { typealias Value = Binding<Bool> }

extension FocusedValues {
    var selectSection: ((AppSection) -> Void)? {
        get { self[SelectSectionKey.self] }
        set { self[SelectSectionKey.self] = newValue }
    }

    var toggleSidebar: (() -> Void)? {
        get { self[ToggleSidebarKey.self] }
        set { self[ToggleSidebarKey.self] = newValue }
    }

    var newMemoAction: (() -> Void)? {
        get { self[NewMemoActionKey.self] }
        set { self[NewMemoActionKey.self] = newValue }
    }

    var newFolderAction: (() -> Void)? {
        get { self[NewFolderActionKey.self] }
        set { self[NewFolderActionKey.self] = newValue }
    }

    var uploadDocumentAction: (() -> Void)? {
        get { self[UploadDocumentActionKey.self] }
        set { self[UploadDocumentActionKey.self] = newValue }
    }

    var nextChapterAction: (() -> Void)? {
        get { self[NextChapterActionKey.self] }
        set { self[NextChapterActionKey.self] = newValue }
    }

    var previousChapterAction: (() -> Void)? {
        get { self[PreviousChapterActionKey.self] }
        set { self[PreviousChapterActionKey.self] = newValue }
    }

    /// S1 활성 시 "스크롤 동기화" 체크 토글(11장 View 메뉴). `ScrollSyncCoordinator`에
    /// 실제 on/off 플래그가 없어서 이번에 하나 추가했다(ScrollSyncCoordinator.swift
    /// 참고) — Binding으로 노출해 메뉴의 체크 상태(⌘로 토글할 때 체크마크가
    /// 즉시 반영)까지 맞춘다.
    var scrollSyncEnabled: Binding<Bool>? {
        get { self[ScrollSyncEnabledKey.self] }
        set { self[ScrollSyncEnabledKey.self] = newValue }
    }
}
