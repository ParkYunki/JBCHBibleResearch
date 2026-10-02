//
//  BookmarkListPopover.swift
//  JBCHBibleResearch
//
//  성경조회의 책갈피 이동 팝업 — 책갈피 목록을 보여주고, 항목을 탭하면 해당 위치로 이동한다.
//  `TranslationPickerPopover`와 같은 `.popover` 패턴이지만 칩 그리드가 아닌 목록형이다.
//  머리·구분선·행·빈 상태는 조회 이력(`BibleReadingHistorySheet`)과 같은 공통 부품(`BibleListLayerParts.swift`)을 쓴다.
//  삭제: 스와이프(iOS/트랙패드) · 행에 마우스를 올리면 나타나는 삭제 버튼(macOS) · 우클릭/길게 누르기 메뉴.
//  항목을 탭해 이동해도 조회 이력은 남지 않는다 — `BibleReadingViewModel.navigateToBookmark` 참고.

import SwiftUI
import BibleResearchModels
#if os(iOS)
import UIKit
#endif

struct BookmarkListPopover: View {
    /// 책갈피 목록이 성경 본문 테마(배경/글자색)를 따르도록 하는 사용자 설정.
    private var settings: UserSettingsStore { .shared }
    let viewModel: BibleReadingViewModel
    var onDismiss: () -> Void

    @State private var bookmarks: [BibleBookmark] = []

    private static let relativeTimeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .short
        return formatter
    }()

    /// 아이폰에서는 `.popover`가 시트로 바뀌므로(`isPhone` 참고), 고정 폭·높이 상한의 작은 카드가
    /// 큰 시트 안에 떠 여백이 생기지 않도록 `.presentationDetents`로 시트 높이를 컨텐츠에 맞춘다.
    /// 아이패드/macOS 팝오버는 영향이 없다.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BibleListLayerHeader(title: "책갈피", count: bookmarks.count, topInset: headerTopInset, onDismiss: onDismiss)
            BibleListLayerDivider()
            if bookmarks.isEmpty {
                BibleListLayerEmptyState(
                    systemImage: "bookmark",
                    title: "책갈피가 없습니다",
                    message: "책갈피 아이콘을 눌러 지금 위치를 저장하세요."
                )
            } else {
                list
            }
        }
        .background(settings.bibleBackgroundColor ?? Color.clear)
        .frame(width: isPhone ? nil : BibleListLayerMetrics.bookmarkWidth)
        #if os(iOS)
        .modifier(BookmarkSheetSizingModifier(isPhone: isPhone, sheetHeight: sheetHeight))
        #endif
        .onAppear {
            // 열 때마다 새로 불러온다 — 다른 창에서 설정/해제한 책갈피도 반영되도록 캐싱하지 않는다.
            bookmarks = viewModel.fetchBookmarks()
        }
    }

    /// `BibleReadingView`의 같은 이름 프로퍼티와 같은 판정(그쪽이 `private`라 재사용 불가) —
    /// 아이폰이면 `.popover`가 시트로 바뀐다.
    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    /// 머리 위 여백 — 팝오버 14, 아이폰 시트는 드래그 표시 아래 숨 쉴 공간 때문에 18(조회 이력과 같은 값).
    private var headerTopInset: CGFloat { isPhone ? 18 : 14 }

    /// 목록 영역 높이: 행 높이 기준으로 계산하며 상한은 "전체 상한 − 머리 − 구분선".
    private var listHeight: CGFloat {
        let cap = BibleListLayerMetrics.bookmarkMaxHeight
            - BibleListLayerMetrics.headerHeight(topInset: 14)
            - BibleListLayerMetrics.dividerHeight
        return min(CGFloat(bookmarks.count) * BibleListLayerMetrics.rowHeight + BibleListLayerMetrics.listVerticalPadding, cap)
    }

    #if os(iOS)
    /// 시트 높이: 머리 + 구분선 + 컨텐츠(빈 상태 고정, 목록은 `listHeight`와 같은 계산식).
    private var sheetHeight: CGFloat {
        let contentHeight = bookmarks.isEmpty ? BibleListLayerMetrics.emptyStateHeight : listHeight
        return BibleListLayerMetrics.headerHeight(topInset: headerTopInset) + BibleListLayerMetrics.dividerHeight + contentHeight
    }
    #endif

    private var list: some View {
        List {
            ForEach(bookmarks) { bookmark in
                BibleListLayerRow(
                    title: bookChapterLabel(for: bookmark),
                    meta: Self.relativeTimeFormatter.localizedString(for: bookmark.createdAt, relativeTo: .now),
                    onSelect: {
                        viewModel.navigateToBookmark(bookmark)
                        onDismiss()
                    },
                    onDelete: { delete(bookmark) },
                    deleteLabel: "책갈피 삭제"
                )
                .bibleListLayerRowChrome()
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        delete(bookmark)
                    } label: {
                        Label("삭제", systemImage: "trash")
                    }
                }
            }
        }
        .bibleListLayerListStyle()
        .frame(height: listHeight)
    }

    private func delete(_ bookmark: BibleBookmark) {
        viewModel.deleteBookmark(bookmark)
        bookmarks.removeAll { $0.id == bookmark.id }
    }

    /// `verse`가 있으면 "장:절", 없으면 "장"으로 표시한다. 등록된 번역본이 2개 이상이면
    /// 번역본별로 책갈피가 구분되므로 끝에 번역본 이름을 붙인다(예: "창세기 2장 · 개역개정").
    private func bookChapterLabel(for bookmark: BibleBookmark) -> String {
        let base: String
        if let book = BooksProvider.shared.book(id: bookmark.bookId) {
            if let verse = bookmark.verse {
                base = "\(book.nameKo) \(bookmark.chapter):\(verse)"
            } else {
                base = "\(book.nameKo) \(bookmark.chapter)장"
            }
        } else {
            if let verse = bookmark.verse {
                base = "책 \(bookmark.bookId) \(bookmark.chapter):\(verse)"
            } else {
                base = "책 \(bookmark.bookId) \(bookmark.chapter)장"
            }
        }
        guard viewModel.availableTranslations.count > 1 else { return base }
        let translationName = viewModel.availableTranslations.first { $0.code == bookmark.translationCode }?.displayName ?? bookmark.translationCode
        guard !translationName.isEmpty else { return base }
        return "\(base) · \(translationName)"
    }
}

#if os(iOS)
/// 아이폰(시트)에서만 높이를 컨텐츠에 맞추고, 아이패드/macOS 팝오버에서는 아무 것도 하지 않는다.
private struct BookmarkSheetSizingModifier: ViewModifier {
    let isPhone: Bool
    let sheetHeight: CGFloat
    func body(content: Content) -> some View {
        if isPhone {
            content
                .presentationDetents([.height(sheetHeight)])
                .presentationDragIndicator(.visible)
        } else {
            content
        }
    }
}
#endif
