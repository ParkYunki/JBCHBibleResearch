//
//  AppCommands.swift
//  JBCHBibleResearch
//
//  screens.md 11장(macOS 메뉴 바)의 실제 구현. "메뉴 항목은 해당 컨텍스트에 포커스가
//  없으면 비활성화됩니다" 원칙을 `@FocusedValue`(AppFocusedValues.swift 참고)로
//  구현했다 — 해당 화면이 지금 안 보이면 클로저 자체가 nil이라 버튼이 자동으로
//  비활성화된다.
//
//  ⚠️ [이번 범위에 포함하지 않은 메뉴 항목, 이유와 함께 정리]
//  - File "번역본 추가..." — S12(번역본 관리)가 아직 구현되지 않아 열 화면이 없다.
//  - File "인쇄..." — 인쇄 기능 자체가 이번 범위에 없다.
//  - Format(서식) 메뉴(굵게/기울임/밑줄/색상/글꼴) — `RichTextEditor`(Views/Memo/
//    RichTextEditor.swift)가 메모 S2/S3, 개요 S8/S9, 메모 팝업 세 곳에 따로 떠
//    있어, 메뉴에서 서식을 적용하려면 "지금 포커스된 에디터가 어느 것인지"를
//    FocusedValue로 노출하는 추가 배선이 필요하다. 범위가 커서 이번 라운드엔
//    만들지 않았다 — macOS는 텍스트 선택 시 뜨는 네이티브 서식 팝업(usesInspectorBar)
//    으로, iOS는 에디터 자체 툴바로 대신한다(RichTextEditor.swift 상단 주석 참고).
//  - Bible "구절로 이동..." — BookChapterPicker의 팝오버를 메뉴에서 강제로 열려면
//    그 팝오버의 `@State`도 바깥으로 노출해야 해서 범위 밖으로 남겼다(다음/이전
//    장은 상태가 필요 없어 바로 구현했다).
//  - Edit/Window/Help 메뉴 — SwiftUI `WindowGroup`이 기본 제공하는 표준 항목을
//    그대로 쓴다(커맨드 그룹을 제거하지 않았으므로 자동으로 남아 있다).
//  - `⌃⌘1~3/0` 문단 스타일 단축키는 원문서 스스로 "다른 앱과 충돌 여부 재확인
//    필요"라고 표시한 항목이라, Format 메뉴 자체를 만들지 않은 지금 단계에서는
//    해당 사항이 없다.
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

            Button("연구문서 업로드...") { uploadDocumentAction?() }
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
            // [2026-08-13 변경] 사용자 요청 — "[개인 묵상], [말씀 요약] 통합할
            // 것 : 메뉴명 - [말씀 노트]." 옛 ⌘2("개인 묵상으로 이동")/⌘6("말씀
            // 요약으로 이동") 두 메뉴 항목을 이 하나로 합쳤다(`AppSection.wordNote`).
            Button("말씀 노트로 이동") { selectSection?(.wordNote) }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(selectSection == nil)
            Button("연구문서로 이동") { selectSection?(.documents) }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(selectSection == nil)
            Button("개요로 이동") { selectSection?(.outline) }
                .keyboardShortcut("4", modifiers: .command)
                .disabled(selectSection == nil)
            Button("통합검색으로 이동") { selectSection?(.search) }
                .keyboardShortcut("5", modifiers: .command)
                .disabled(selectSection == nil)

            Divider()

            // 별도 창이라 FocusedValue 없이 바로 openWindow — 항상 활성화(9.1 원칙:
            // "클릭 시 새 창이 열림/앞으로 옴"은 어느 화면에서든 가능해야 한다).
            Button("태그 관계 보기") { openWindow(id: "tag-relations") }
                .keyboardShortcut("t", modifiers: [.command, .shift])

            // [2026-08-07 추가] 사용자 요청 — "성경 조회 창은 여러 개를 띄울 수 있어야
            // 하고, 각 창마다 다른 성경을 동시에 조회할 수 있어야 한다." 매번 새
            // `BibleReadingView` 인스턴스를 만들어 여는 것이라(JBCHBibleResearchApp.swift
            // "bible-reading" WindowGroup 참고) 여기도 FocusedValue 없이 항상 활성화한다.
            Button("성경 조회 새 창") { openWindow(id: "bible-reading") }
                .keyboardShortcut("b", modifiers: [.command, .shift])

            if let scrollSyncEnabled {
                Toggle("스크롤 동기화", isOn: scrollSyncEnabled)
            }
        }

        // MARK: Bible
        //
        // ⚠️ [단순화] 스펙은 "성경조회 화면이 활성 창일 때만" 나타나는 메뉴를
        // 의도했지만, `CommandMenu`는 메뉴 자체를 조건부로 숨기는 표준 방법이
        // 없다(항상 메뉴는 보이고, 그 안의 항목을 개별적으로 disabled 처리하는 게
        // SwiftUI Commands의 일반적인 패턴 — Xcode의 Product 메뉴 등도 이렇게
        // 동작한다). 그래서 이 구현은 메뉴는 항상 보이되, S1이 아닐 때는 아래
        // 두 버튼이 회색으로 비활성화되는 방식을 택했다.
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
