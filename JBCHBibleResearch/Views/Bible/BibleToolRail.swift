//
//  BibleToolRail.swift
//  JBCHBibleResearch
//
//  macOS 전용: 성경 조회 본문 왼쪽의 세로 도구 레일. 예전에 툴바 오른쪽에 있던 아이콘 묶음(책갈피 이동·책갈피 설정/해제·조회 이력·
//  관련 콘텐츠·번역본 선택·새 창)을 이 레일로 옮겼다(2026-10-02, 사용자 결정):
//  - 툴바 아이콘 묶음이 macOS 26에서 시스템 유리 캡슐로 그려지던 것을 없애려고 툴바를 떠난다. 레일 버튼은 직접 그리는 "플랫" 스타일이다.
//  - 레일 접기 토글: 레일 맨 아래 버튼 / 접힌 상태의 16pt 손잡이 / 메뉴 "성경 > 성경 도구 레일 접기"(`AppCommands`)가 같은 값
//    (`BibleToolRailDefaults.collapsedKey`, UserDefaults)을 바꾼다. 모든 성경 조회 창이 같은 값을 공유하고 앱을 다시 켜도 유지된다.
//  - 이 뷰가 `viewModel`에서 읽는 값은 책갈피 여부·번역본 수·첫 열 번역본뿐이라(스크롤/절 선택과 무관) 본문이 다시 그려져도
//    레일이 불필요하게 다시 계산되지 않는다. 팝오버/시트 표시 상태는 호출부(`BibleReadingContentView`)의 `@State`를 바인딩으로 받는다.
//  iOS/아이패드는 기존 툴바 방식을 유지한다. 접힘 키 상수는 `AppCommands`(양 플랫폼 컴파일)도 쓰므로 `#if` 밖에 둔다.

import SwiftUI

enum BibleToolRailDefaults {
    /// `@AppStorage`/메뉴가 함께 쓰는 키 — 오타로 둘이 어긋나지 않게 상수로 둔다.
    static let collapsedKey = "bibleToolRail.collapsed"
}

#if os(macOS)

import SwiftData
import AppKit
import BibleResearchModels

struct BibleToolRail: View {
    let viewModel: BibleReadingViewModel
    /// false면(macOS 보조 창) 책갈피/조회 이력/관련 콘텐츠를 뺀다(예전 툴바와 같은 규칙, `BibleReadingView.isPrimaryWindow` 참고).
    let isPrimaryWindow: Bool
    /// 말씀 요약 편집 중이면 책갈피·조회 이력·번역본·새 창을 감추고 "관련 콘텐츠" 자리를 "말씀 요약 닫기"로 쓴다(예전 툴바와 같은 규칙).
    let isWordSummaryEditing: Bool
    @Binding var isBookmarkListPresented: Bool
    @Binding var isHistoryPresented: Bool
    @Binding var isRelatedContentPresented: Bool
    @Binding var isTranslationPickerPresented: Bool
    let onCloseWordSummary: () -> Void

    @AppStorage(BibleToolRailDefaults.collapsedKey) private var isCollapsed = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme

    private var settings: UserSettingsStore { .shared }

    private static let railWidth: CGFloat = 52
    private static let handleWidth: CGFloat = 16

    var body: some View {
        if isCollapsed {
            collapsedHandle
        } else {
            expandedRail
        }
    }

    // MARK: - 표시 조건 (예전 `toolbarContent`와 동일)

    private var showNavigationGroup: Bool { isPrimaryWindow && !isWordSummaryEditing }
    private var showRelatedGroup: Bool { isPrimaryWindow }
    /// 활성 번역본이 둘 이상이면 창마다 보일 번역본(1~`maxColumns`개)을 고를 수 있게 버튼을 보인다. 선택은 이 창의
    /// `viewModel`에만 걸리므로(`setDisplayedTranslations`) 다른 성경 조회 창에 번지지 않는다. 예전에는 `maxColumns`(3)개를
    /// 넘을 때만 보여 번역본이 2~3개면 하나만 골라 볼 방법이 없었다.
    private var showTranslationPicker: Bool {
        viewModel.availableTranslations.count > 1 && !isWordSummaryEditing
    }
    private var showNewWindow: Bool { !isWordSummaryEditing }
    private var showWindowGroup: Bool { showTranslationPicker || showNewWindow }

    /// 책갈피 대상 번역본 — macOS는 맨 왼쪽 열(`BibleReadingContentView.bookmarkTargetTranslationCode`와 같은 규칙).
    private var bookmarkTargetTranslationCode: String? { viewModel.columns.first?.registry.code }

    // MARK: - 색

    /// 테마 배경이 있으면 그 배경의 상대휘도로, 없으면 시스템 외형으로 어두운 배경인지 판정한다(다른 화면의 판정식과 같다).
    private var isDarkBackground: Bool {
        guard let background = settings.bibleBackgroundColor else { return colorScheme == .dark }
        let resolved = background.resolve(in: environment)
        let luminance = 0.2126 * Double(resolved.red) + 0.7152 * Double(resolved.green) + 0.0722 * Double(resolved.blue)
        return luminance < 0.5
    }

    /// 어두운 배경에서는 앱 강조색(6.9:1)을 쓴다. 밝은 배경에서는 강조색(#B8863C)이 3:1에 못 미쳐(2.6~2.9:1) 더 진한 갈색을 쓴다.
    private var iconColor: Color {
        isDarkBackground ? Color("AccentColor") : Color(red: 0.42, green: 0.35, blue: 0.23)
    }

    /// "눌림/켜짐" 상태의 채움색과 그 위 아이콘색. 어두운 배경의 금색 위에서는 흰색 대비가 모자라 어두운 글자색을 쓴다.
    private var activeFill: Color { Color("AccentColor") }
    private var activeForeground: Color { isDarkBackground ? Color(red: 0.11, green: 0.105, blue: 0.10) : .white }

    private var railBackground: some View {
        ZStack {
            settings.bibleBackgroundColor ?? Color(nsColor: .windowBackgroundColor)
            // 본문과 한 단계 다른 톤 — 사이드바 옆에 또 하나의 세로 막대가 생기므로 구분이 필요하다.
            (settings.bibleTextColor ?? Color.primary).opacity(0.05)
        }
    }

    private var separatorColor: Color { (settings.bibleTextColor ?? Color.primary).opacity(0.12) }

    // MARK: - 펼친 레일

    private var expandedRail: some View {
        VStack(spacing: 4) {
            if showNavigationGroup { navigationGroup }
            if showNavigationGroup && (showRelatedGroup || showWindowGroup) { groupRule }
            if showRelatedGroup { relatedGroup }
            if showRelatedGroup && showWindowGroup { groupRule }
            if showWindowGroup { windowGroup }

            Spacer(minLength: 0)

            RailButton(
                systemImage: "chevron.left.2", label: "도구 레일 접기", help: "도구 레일 접기",
                iconColor: iconColor, activeFill: activeFill, activeForeground: activeForeground
            ) {
                isCollapsed = true
            }
        }
        .padding(.vertical, 10)
        .frame(width: Self.railWidth)
        .frame(maxHeight: .infinity)
        .background(railBackground)
        .overlay(alignment: .trailing) { Rectangle().fill(separatorColor).frame(width: 1) }
    }

    private var collapsedHandle: some View {
        VStack(spacing: 0) {
            Button {
                isCollapsed = false
            } label: {
                Image(systemName: "chevron.right.2")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(iconColor)
                    .frame(width: Self.handleWidth, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("도구 레일 펼치기")
            .accessibilityLabel("도구 레일 펼치기")
            .padding(.top, 10)
            Spacer(minLength: 0)
        }
        .frame(width: Self.handleWidth)
        .frame(maxHeight: .infinity)
        .background(railBackground)
        .overlay(alignment: .trailing) { Rectangle().fill(separatorColor).frame(width: 1) }
    }

    private var groupRule: some View {
        Rectangle().fill(separatorColor).frame(width: 28, height: 1).padding(.vertical, 4)
    }

    // MARK: - 그룹

    /// 탐색: 책갈피 이동 · 책갈피 설정/해제 · 조회 이력.
    private var navigationGroup: some View {
        VStack(spacing: 2) {
            RailButton(
                systemImage: "list.star", label: "책갈피 이동", help: "책갈피로 이동",
                iconColor: iconColor, activeFill: activeFill, activeForeground: activeForeground
            ) {
                isBookmarkListPresented = true
            }
            .popover(isPresented: $isBookmarkListPresented, arrowEdge: .trailing) {
                BookmarkListPopover(viewModel: viewModel) {
                    isBookmarkListPresented = false
                }
            }

            let code = bookmarkTargetTranslationCode
            let isMarked = code.map { viewModel.isCurrentPositionBookmarked(translationCode: $0) } ?? false
            RailButton(
                systemImage: isMarked ? "bookmark.fill" : "bookmark",
                label: isMarked ? "책갈피 해제" : "책갈피 설정",
                help: isMarked ? "이 위치 책갈피 해제" : "이 위치 책갈피로 설정",
                // 책갈피는 예전 툴바처럼 와인 색 하나로 칠한다.
                iconColor: JBCHCategoryPalette.wine, activeFill: activeFill, activeForeground: activeForeground,
                isDisabled: code == nil
            ) {
                // 대상 번역본이 없으면(`emptyState`) 아무것도 하지 않는다. `isDisabled`가 이 경우 버튼을 비활성화한다.
                guard let code else { return }
                viewModel.toggleBookmarkForCurrentPosition(translationCode: code)
            }

            RailButton(
                systemImage: "clock", label: "조회 이력", help: "최근 조회한 책/장 이력 보기",
                iconColor: iconColor, activeFill: activeFill, activeForeground: activeForeground
            ) {
                isHistoryPresented = true
            }
            // 책갈피 목록과 같은 방식(레일 아이콘에 붙는 팝오버)으로 띄운다 — 예전 시트(모달)는 열려 있는 동안 본문을 조작할 수 없었다.
            .popover(isPresented: $isHistoryPresented, arrowEdge: .trailing) {
                BibleReadingHistorySheet(viewModel: viewModel) {
                    isHistoryPresented = false
                }
            }
        }
    }

    /// 보기: 관련 콘텐츠(떠 있는 도구창) 토글. 말씀 요약 편집 중에는 같은 버튼이 "닫기"로 동작한다.
    private var relatedGroup: some View {
        RailButton(
            systemImage: isWordSummaryEditing ? "xmark.circle" : "sidebar.trailing",
            label: isWordSummaryEditing ? "말씀 요약 닫기" : "관련 콘텐츠",
            help: isWordSummaryEditing ? "말씀 요약 편집 마치기" : "이 장의 개요·메모·연구문서 보기",
            iconColor: iconColor, activeFill: activeFill, activeForeground: activeForeground,
            isOn: isRelatedContentPresented && !isWordSummaryEditing
        ) {
            if isWordSummaryEditing {
                onCloseWordSummary()
            } else {
                isRelatedContentPresented.toggle()
            }
        }
    }

    /// 창: 번역본 선택 · 새 창.
    private var windowGroup: some View {
        VStack(spacing: 2) {
            if showTranslationPicker {
                RailButton(
                    systemImage: "text.book.closed", label: "번역본 선택", help: "번역본 선택",
                    iconColor: iconColor, activeFill: activeFill, activeForeground: activeForeground
                ) {
                    isTranslationPickerPresented = true
                }
                .popover(isPresented: $isTranslationPickerPresented, arrowEdge: .trailing) {
                    TranslationPickerPopover(
                        available: viewModel.availableTranslations,
                        selected: viewModel.columns.map(\.registry.persistentModelID),
                        maxSelection: viewModel.maxColumns
                    ) { selected in
                        // `TranslationPickerPopover.selectedIDs`가 선택 순서를 보존하는 배열이라 `Set` 변환 없이 그대로 넘긴다.
                        viewModel.setDisplayedTranslations(selected)
                        isTranslationPickerPresented = false
                    }
                }
            }
            if showNewWindow {
                RailButton(
                    systemImage: "macwindow.badge.plus", label: "성경 조회 새 창", help: "성경 조회 새 창으로 열기",
                    iconColor: iconColor, activeFill: activeFill, activeForeground: activeForeground
                ) {
                    openWindow(id: "bible-reading")
                }
            }
        }
    }
}

/// 플랫 레일 버튼 — 평소엔 아이콘만, 마우스를 올리면 옅은 배경, `isOn`이면 강조색 채움. 시스템 유리 재질을 쓰지 않는다.
/// 호버 상태를 버튼마다 따로 갖도록 별도 뷰로 뺐다.
private struct RailButton: View {
    let systemImage: String
    let label: String
    let help: String
    let iconColor: Color
    let activeFill: Color
    let activeForeground: Color
    var isOn: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .regular))
                .frame(width: 36, height: 36)
                .foregroundStyle(isOn ? activeForeground : iconColor)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isOn ? activeFill : (isHovering ? iconColor.opacity(0.16) : Color.clear))
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(label)
    }
}

#endif
