//
//  AppCommands.swift
//  JBCHBibleResearch
//
//  macOS 메뉴 바 커맨드. "해당 컨텍스트에 포커스가 없으면 메뉴 항목 비활성화" 원칙을
//  `@FocusedValue`(AppFocusedValues.swift 참고)로 구현했다 — 화면이 안 보이면 클로저가 nil이라
//  버튼이 자동으로 비활성화된다.
//
//  ⚠️ 미구현 항목: File "번역본 추가..."(번역본 관리 화면 없음)/"인쇄...", Format(서식) 메뉴,
//  Bible "구절로 이동..."(BookChapterPicker 팝오버의 `@State`를 바깥으로 노출해야 함).
//  Format 메뉴는 `RichTextEditor`가 여러 화면에 따로 떠 있어 포커스된 에디터를 FocusedValue로
//  노출하는 추가 배선이 필요하다(대신 macOS 네이티브 서식 팝업/iOS 에디터 툴바 사용).
//

import SwiftUI

struct AppCommands: Commands {
    @FocusedValue(\.selectSection) private var selectSection
    @FocusedValue(\.toggleSidebar) private var toggleSidebar
    @FocusedValue(\.newMemoAction) private var newMemoAction
    @FocusedValue(\.newFolderAction) private var newFolderAction
    @FocusedValue(\.uploadDocumentAction) private var uploadDocumentAction
    @FocusedValue(\.nextChapterAction) private var nextChapterAction
    @FocusedValue(\.previousChapterAction) private var previousChapterAction
    @FocusedValue(\.scrollSyncEnabled) private var scrollSyncEnabled

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // MARK: File

        CommandGroup(after: .newItem) {
            Button("새 메모") { newMemoAction?() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(newMemoAction == nil)

            Button("새 폴더") { newFolderAction?() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(newFolderAction == nil)

            Button("연구 문서 업로드...") { uploadDocumentAction?() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(uploadDocumentAction == nil)
        }

        // MARK: View — 화면 전환/사이드바(9.1의 "Show/Hide Sidebar"류 표준 위치)

        CommandGroup(after: .sidebar) {
            Button("사이드바 토글") { toggleSidebar?() }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(toggleSidebar == nil)

            Divider()

            Button("성경조회로 이동") { selectSection?(.bibleReading) }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(selectSection == nil)
            // 개인 묵상/말씀 요약을 통합한 단일 메뉴(`AppSection.wordNote`).
            Button("말씀 노트로 이동") { selectSection?(.wordNote) }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(selectSection == nil)
            Button("연구 문서로 이동") { selectSection?(.documents) }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(selectSection == nil)
            Button("개요로 이동") { selectSection?(.outline) }
                .keyboardShortcut("4", modifiers: .command)
                .disabled(selectSection == nil)
            Button("통합검색으로 이동") { selectSection?(.search) }
                .keyboardShortcut("5", modifiers: .command)
                .disabled(selectSection == nil)

            Divider()

            // 별도 창이라 FocusedValue 없이 바로 openWindow — 어느 화면에서든 항상 활성화.
            Button("태그 관계 보기") { openWindow(id: "tag-relations") }
                .keyboardShortcut("t", modifiers: [.command, .shift])

            // 매번 새 `BibleReadingView` 인스턴스를 여는 창이라(창마다 다른 성경 조회 가능) FocusedValue 없이 항상 활성화한다.
            Button("성경 조회 새 창") { openWindow(id: "bible-reading") }
                .keyboardShortcut("b", modifiers: [.command, .shift])

            if let scrollSyncEnabled {
                Toggle("스크롤 동기화", isOn: scrollSyncEnabled)
            }
        }

        // MARK: Bible
        //
        // ⚠️ `CommandMenu` 자체를 조건부로 숨기는 표준 방법이 없어 메뉴는 항상 보이고,
        // 성경조회 화면이 활성 창이 아닐 때는 아래 두 버튼만 비활성화된다.
        CommandMenu("성경") {
            Button("다음 장") { nextChapterAction?() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(nextChapterAction == nil)
            Button("이전 장") { previousChapterAction?() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(previousChapterAction == nil)
        }
    }
}
