//
//  BibleTopBar.swift
//  JBCHBibleResearch
//
//  성경 조회(아이폰/아이패드)의 직접 그린 상단바 (2026-10-21 목업 확정).
//
//  배경: 앱을 나갔다 돌아오면 시스템 내비게이션 바(`isNavigationBarHidden == true`)가 통째로 사라지는 증상이 있었다
//  (`NavigationBarGuard`로 복구했지만 시스템 바 상태에 의존하는 구조 자체가 원인). 그래서 이 화면은 시스템 바를 쓰지 않고
//  (`.toolbar(.hidden, for: .navigationBar)`) 화면 안의 상단 인셋에 이 막대를 직접 그린다.
//
//  구성
//  - 아이폰(1행 52pt, 아래에 장 이동 막대): 왼쪽 = 번역본 이름 + "책 장" 제목, 오른쪽 = 라운드 사각 묶음 5개
//    [책갈피 이동 | 책갈피 설정/해제 | 조회 이력 | 관련 콘텐츠 | 번역본 선택].
//  - 아이패드 두 줄(상단바 60pt + 장 이동 막대): 가운데 제목(번역본 줄 + "책 장"), 양끝 배치 —
//    왼쪽 끝 [사이드바 열기(사이드바가 닫혀 있을 때만) | 책갈피 이동 | 책갈피], 오른쪽 끝 [조회 이력 | 관련 콘텐츠(인스펙터)].
//  - 아이패드 한 줄(폭이 넉넉할 때, `singleRowCenter`를 넘기면): 왼쪽 묶음 + 번역본 칩, 가운데 장 이동 막대(책/장 버튼 포함), 오른쪽 묶음.
//    폭이 모자라면 호출부(`BibleReadingView.topInsetContent`)의 `ViewThatFits`가 두 줄로 되돌린다.
//  - 제목("책 장")을 탭하면 책/장 그리드 팝오버가 열린다(`BookChapterGridPopover`). 번역본 선택은 별도 아이콘(아이폰)이거나
//    번역본 이름 줄/칩(아이패드)을 탭한다(활성 번역본이 둘 이상일 때).
//  - 아이콘 모양은 상단 이동 막대와 같은 `BibleBarSegmentGroup` 규격(글자색 10% 채움 + 24% 테두리, 모서리 10pt).
//    활성 상태(책갈피 설정됨, 관련 콘텐츠 열림)는 `BibleBarPalette.strong` 채움 + `strongForeground` 글자.
//    모든 색은 사용자 성경 테마(`bibleBackgroundColor/bibleTextColor`)에서 파생해 라이트/다크/사용자 테마에서 같은 농도로 보인다.
//
//  동작 규칙은 이전 시스템 툴바(2026-10-21 이전 `BibleReadingView.toolbarContent`)와 같다.
//  - 아이패드에서 말씀 요약 편집 중에는 사이드바 열기·책갈피·조회 이력 아이콘을 숨기고, 관련 콘텐츠 자리는 "말씀 요약 닫기"로 바뀐다.
//    (아이폰은 편집기가 시트로 덮으므로 숨기지 않는다.)
//  - 책갈피 설정/해제는 대상 번역본이 없으면(빈 화면) 비활성이다.
//  - 번역본이 하나뿐이면 번역본 선택 UI는 나타나지 않는다.
//
//  막대의 배경·안전영역 확장·구분선은 호출부(`BibleReadingView.topInsetContent`)가 입힌다. iOS 전용.

#if os(iOS)
import BibleResearchModels
import SwiftData
import SwiftUI

struct BibleTopBar: View {
    let viewModel: BibleReadingViewModel
    /// 지금 보고 있는 번역본 이름(아이폰은 스와이프 중인 컬럼). 표시된 번역본이 없으면 빈 문자열.
    let translationDisplayName: String
    /// 책갈피 설정/해제가 대상으로 삼을 번역본 코드. nil이면 책갈피 버튼을 비활성화한다.
    let bookmarkTargetTranslationCode: String?
    /// 말씀 요약 편집기가 인스펙터 자리를 쓰는 중인지.
    let isEditingSummary: Bool
    /// 아이패드 한 줄 배치일 때 가운데에 놓을 장 이동 막대. nil이면(아이폰, 아이패드 두 줄) 상단바만 그린다.
    var singleRowCenter: AnyView? = nil
    @Binding var isBookmarkListPresented: Bool
    @Binding var isHistoryPresented: Bool
    @Binding var isRelatedContentPresented: Bool
    @Binding var isTranslationPickerPresented: Bool
    /// 말씀 요약 편집 마치기(뒷정리 포함) — 이전 툴바의 "말씀 요약 닫기"와 같은 동작.
    let onCloseWordSummary: () -> Void

    /// 제목 탭으로 여는 책/장 그리드 팝오버. 다른 팝오버와 달리 이 막대만 쓰므로 부모가 아니라 여기서 가진다.
    @State private var isBookPickerPresented = false

    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    private var palette: BibleBarPalette {
        BibleBarPalette(environment: environment, colorScheme: colorScheme)
    }

    /// 아이폰 36pt, 아이패드 40pt(`BibleBarSizing.touch`). 모서리는 둘 다 10pt.
    private var sizing: BibleBarSizing {
        isPhone ? .phoneTopBar : .touch
    }

    /// 아이패드에서 말씀 요약 편집 중 숨기는 아이콘 묶음 판정.
    private var hidesIconsWhileEditingSummary: Bool {
        !isPhone && isEditingSummary
    }

    private var showsTranslationPicker: Bool {
        viewModel.availableTranslations.count > 1 && !hidesIconsWhileEditingSummary
    }

    private var isCurrentPositionBookmarked: Bool {
        guard let code = bookmarkTargetTranslationCode else { return false }
        return viewModel.isCurrentPositionBookmarked(translationCode: code)
    }

    var body: some View {
        Group {
            if isPhone {
                phoneLayout
            } else if let center = singleRowCenter {
                singleRowLayout(center: center)
            } else {
                padLayout
            }
        }
        .environment(\.bibleBarSizing, sizing)
    }

    // MARK: - 레이아웃

    private var phoneLayout: some View {
        HStack(spacing: 8) {
            titleBlock(alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            BibleBarSegmentGroup {
                bookmarkListItem
                BibleBarSegmentDivider()
                bookmarkToggleItem
                BibleBarSegmentDivider()
                historyItem
                BibleBarSegmentDivider()
                relatedItem
                if showsTranslationPicker {
                    BibleBarSegmentDivider()
                    translationIconItem
                }
            }
            .fixedSize()
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(height: 52)
    }

    /// 아이패드 두 줄 배치의 윗줄 — 좌우 묶음이 같은 폭(`maxWidth: .infinity`)을 나눠 가져 제목이 항상 가운데에 온다.
    private var padLayout: some View {
        HStack(spacing: 16) {
            HStack(spacing: 0) {
                padLeftGroup
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            titleBlock(alignment: .center)

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                padRightGroup
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
    }

    /// 아이패드 한 줄 배치 — 왼쪽 묶음 + 번역본 칩, 가운데 장 이동 막대, 오른쪽 묶음. 가운데 막대가 남는 폭을 차지해 두 묶음 사이에 놓인다
    /// (왼쪽이 번역본 칩만큼 더 넓어 정확한 화면 중앙에서는 약간 오른쪽으로 치우친다).
    private func singleRowLayout(center: AnyView) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                padLeftGroup
                singleRowTranslationChip
            }
            .fixedSize()
            center
            padRightGroup
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
    }

    /// 아이패드 왼쪽 묶음: [사이드바 열기 | 책갈피 이동 | 책갈피]. 사이드바 열기는 사이드바가 닫혀 있을 때만.
    @ViewBuilder
    private var padLeftGroup: some View {
        if !hidesIconsWhileEditingSummary {
            BibleBarSegmentGroup {
                if showsSidebarOpenButton {
                    sidebarOpenItem
                    BibleBarSegmentDivider()
                }
                bookmarkListItem
                BibleBarSegmentDivider()
                bookmarkToggleItem
            }
            .fixedSize()
        }
    }

    /// 아이패드 오른쪽 묶음: [조회 이력 | 관련 콘텐츠]. 말씀 요약 편집 중에는 관련 콘텐츠 칸(= 말씀 요약 닫기)만 남는다.
    private var padRightGroup: some View {
        BibleBarSegmentGroup {
            if !hidesIconsWhileEditingSummary {
                historyItem
                BibleBarSegmentDivider()
            }
            relatedItem
        }
        .fixedSize()
    }

    /// 아이패드: 사이드바가 닫혀 있고 말씀 요약 편집 중이 아닐 때만 둔다(이전 툴바와 같은 조건 —
    /// 말씀 요약 편집 중에는 `SidebarVisibilityRequest`의 자동 복원 계약과 사이드바 값을 다투게 되므로 노출하지 않는다).
    private var showsSidebarOpenButton: Bool {
        !isPhone && !isEditingSummary && !IPadSidebarInspectorCoordination.shared.isSidebarVisible
    }

    // MARK: - 제목

    private func titleBlock(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            translationLine
            bookChapterTitleButton
        }
    }

    /// "책 장" 제목 — 탭하면 책/장 그리드 팝오버(장 이동 막대의 책 버튼과 같은 내용)가 열린다.
    private var bookChapterTitleButton: some View {
        Button {
            isBookPickerPresented = true
        } label: {
            // 타이틀 폰트는 국민대학교 성곡 세리프체(`SpecialPurposeFonts.titleSerif`, CC BY-ND — 설정 > 라이센스 탭 고지).
            // `.fontWeight(.semibold)`는 합성 볼드 보정이다(이전 아이패드 타이틀과 동일).
            HStack(spacing: 4) {
                Text("\(viewModel.selectedBook.displayName) \(viewModel.selectedChapter)장")
                    .font(.titleSerif(size: isPhone ? 19 : 21, relativeTo: .title3))
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.text.opacity(0.6))
            }
            .foregroundStyle(palette.text)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("책과 장 고르기")
        .popover(isPresented: $isBookPickerPresented) {
            BookChapterGridPopover(
                books: BooksProvider.shared.books,
                selectedBook: viewModel.selectedBook,
                selectedChapter: viewModel.selectedChapter
            ) { book, chapter in
                viewModel.selectBook(book, chapter: chapter)
                isBookPickerPresented = false
            }
        }
    }

    /// 제목 위 번역본 이름 줄. 활성 번역본이 둘 이상이면 탭해서 번역본 선택을 연다.
    /// 아이폰은 오른쪽 `translationIconItem`이 팝오버(시트)를 맡고 이 줄은 같은 값을 켜기만 한다 — 같은 바인딩에 `.popover`를
    /// 두 곳에 걸면 충돌하므로, 팝오버는 아이패드에서는 이 줄에만, 아이폰에서는 아이콘에만 붙인다.
    @ViewBuilder
    private var translationLine: some View {
        if !translationDisplayName.isEmpty {
            if showsTranslationPicker {
                Button {
                    isTranslationPickerPresented = true
                } label: {
                    HStack(spacing: 3) {
                        Text(translationDisplayName)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.strong)
                    .frame(minHeight: 22)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("번역본 선택")
                .popover(isPresented: isPhone ? .constant(false) : $isTranslationPickerPresented) {
                    translationPopoverContent
                }
            } else {
                Text(translationDisplayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.strong)
                    .lineLimit(1)
                    .frame(minHeight: 22)
            }
        }
    }

    /// 아이패드 한 줄 배치의 번역본 칩 — 장 이동 막대와 같은 라운드 사각 버튼. 번역본이 하나뿐이면 글자만 보인다.
    @ViewBuilder
    private var singleRowTranslationChip: some View {
        if !translationDisplayName.isEmpty {
            if showsTranslationPicker {
                Button {
                    isTranslationPickerPresented = true
                } label: {
                    HStack(spacing: 4) {
                        Text(translationDisplayName)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                }
                .buttonStyle(BibleBarButtonStyle(height: sizing.height, cornerRadius: sizing.radius, fontSize: 13))
                .accessibilityLabel("번역본 선택")
                .popover(isPresented: $isTranslationPickerPresented) {
                    translationPopoverContent
                }
            } else {
                Text(translationDisplayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.strong)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - 아이콘 칸

    /// 묶음 안의 아이콘 한 칸. 모양(정사각 칸, 올림/눌림/활성 색)은 `BibleTopBarItemStyle`이 입힌다.
    private func item(
        _ systemImage: String, label: LocalizedStringKey, isActive: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: sizing.iconSize, weight: .semibold))
        }
        .buttonStyle(BibleTopBarItemStyle(isActive: isActive))
        .accessibilityLabel(label)
    }

    private var sidebarOpenItem: some View {
        item("sidebar.leading", label: "사이드바 열기") {
            IPadSidebarInspectorCoordination.shared.requestShowSidebar()
        }
    }

    private var bookmarkListItem: some View {
        item("list.star", label: "책갈피 이동") {
            isBookmarkListPresented = true
        }
        .popover(isPresented: $isBookmarkListPresented) {
            BookmarkListPopover(viewModel: viewModel) {
                isBookmarkListPresented = false
            }
        }
    }

    private var bookmarkToggleItem: some View {
        item(
            isCurrentPositionBookmarked ? "bookmark.fill" : "bookmark",
            label: isCurrentPositionBookmarked ? "책갈피 해제" : "책갈피 설정",
            isActive: isCurrentPositionBookmarked
        ) {
            // 대상 번역본이 없으면(빈 화면) 아무것도 하지 않는다. 아래 `.disabled`가 이 경우 버튼을 비활성화한다.
            guard let code = bookmarkTargetTranslationCode else { return }
            viewModel.toggleBookmarkForCurrentPosition(translationCode: code)
        }
        .disabled(bookmarkTargetTranslationCode == nil)
    }

    private var historyItem: some View {
        item("clock", label: "조회 이력") {
            isHistoryPresented = true
        }
        .popover(isPresented: $isHistoryPresented) {
            BibleReadingHistorySheet(viewModel: viewModel) {
                isHistoryPresented = false
            }
        }
    }

    /// 관련 콘텐츠 패널 토글. 말씀 요약 편집기가 이 자리를 빌려 쓰는 동안에는 `isRelatedContentPresented`를 토글해도 인스펙터가 계속
    /// 열려 있으므로(`.inspector`의 `get`이 `wordSummaryBeingEdited`도 봄) 같은 버튼이 "닫기"(뒷정리 포함)로 동작한다.
    private var relatedItem: some View {
        item(
            isEditingSummary ? "xmark.circle" : "sidebar.trailing",
            label: isEditingSummary ? "말씀 요약 닫기" : "관련 콘텐츠",
            isActive: isEditingSummary || isRelatedContentPresented
        ) {
            if isEditingSummary {
                onCloseWordSummary()
            } else {
                isRelatedContentPresented.toggle()
            }
        }
    }

    /// 아이폰 전용 번역본 선택 아이콘(아이패드는 번역본 이름 줄/칩이 대신한다).
    private var translationIconItem: some View {
        item("text.book.closed", label: "번역본 선택") {
            isTranslationPickerPresented = true
        }
        .popover(isPresented: $isTranslationPickerPresented) {
            translationPopoverContent
        }
    }

    private var translationPopoverContent: some View {
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

extension BibleBarSizing {
    /// 아이폰 상단바 아이콘 묶음 — 높이 36pt(다섯 칸이 180pt), 모서리 10pt.
    static let phoneTopBar = BibleBarSizing(height: 36, radius: 10, fontSize: 15, iconSize: 16, fieldFontSize: 15)
}

/// 상단바 아이콘 칸 스타일 — `BibleBarSegmentItemStyle`과 같은 정사각 칸에, 활성 상태(`isActive`)면 강조색 채움을 더한다.
private struct BibleTopBarItemStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        BibleTopBarItemBody(configuration: configuration, isActive: isActive)
    }
}

private struct BibleTopBarItemBody: View {
    let configuration: ButtonStyleConfiguration
    let isActive: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bibleBarSizing) private var sizing

    var body: some View {
        let palette = BibleBarPalette(environment: environment, colorScheme: colorScheme)
        let pressed = configuration.isPressed
        let fill: Color = isActive
            ? palette.strong.opacity(pressed ? 0.78 : 1)
            : palette.text.opacity(pressed ? BibleBarMetrics.fillOpacity + 0.06 : 0)
        configuration.label
            .foregroundStyle(isActive ? palette.strongForeground : palette.text)
            .frame(width: sizing.height, height: sizing.height)
            .background(fill)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : BibleBarMetrics.disabledOpacity)
    }
}
#endif
