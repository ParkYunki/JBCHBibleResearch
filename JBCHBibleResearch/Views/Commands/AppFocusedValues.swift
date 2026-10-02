//
//  AppFocusedValues.swift
//  JBCHBibleResearch
//
//  메뉴 바 커맨드가 쓰는 `FocusedSceneValue` 키 모음(AppCommands.swift가 `@FocusedValue`로 읽는다).
//
//  ⚠️ 설계 결정: 사이드바 선택 상태를 전역 싱글턴으로 두지 않았다. 메인 WindowGroup이 macOS에서
//  여러 창으로 열릴 수 있어, 싱글턴이면 창 A의 선택이 창 B의 사이드바까지 바꾼다.
//  `FocusedSceneValue`는 활성(키) 창/씬에만 값을 연결하므로, 각 화면(SidebarNavigationView,
//  MemoHomeView, DocumentsHomeView, BibleReadingView)은 로컬 `@State`를 유지한 채
//  `.focusedSceneValue`로 액션 클로저만 노출한다.
//

import SwiftUI

// MARK: - 사이드바(View 메뉴 — 화면 전환, 사이드바 토글)

private struct SelectSectionKey: FocusedValueKey { typealias Value = (AppSection) -> Void }
private struct ToggleSidebarKey: FocusedValueKey { typealias Value = () -> Void }

// MARK: - 메모(File 메뉴 — 새 메모/새 폴더)

private struct NewMemoActionKey: FocusedValueKey { typealias Value = () -> Void }
// 성경 조회 "본문에서 찾기"(⌘F) — `BibleChapterFind.swift`가 노출하고 Bible 메뉴가 읽는다.
private struct FindInChapterActionKey: FocusedValueKey { typealias Value = () -> Void }
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

    var findInChapterAction: (() -> Void)? {
        get { self[FindInChapterActionKey.self] }
        set { self[FindInChapterActionKey.self] = newValue }
    }

    var nextChapterAction: (() -> Void)? {
        get { self[NextChapterActionKey.self] }
        set { self[NextChapterActionKey.self] = newValue }
    }

    var previousChapterAction: (() -> Void)? {
        get { self[PreviousChapterActionKey.self] }
        set { self[PreviousChapterActionKey.self] = newValue }
    }

    /// S1 활성 시 "스크롤 동기화" 체크 토글. Binding으로 노출해 메뉴 체크 상태가 즉시 반영되게 한다.
    var scrollSyncEnabled: Binding<Bool>? {
        get { self[ScrollSyncEnabledKey.self] }
        set { self[ScrollSyncEnabledKey.self] = newValue }
    }
}
