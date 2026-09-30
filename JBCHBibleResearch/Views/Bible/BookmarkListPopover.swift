//
//  BookmarkListPopover.swift
//  JBCHBibleResearch
//
//  성경조회의 책갈피 이동 팝업 — 책갈피 목록을 보여주고, 항목을 탭하면 해당 위치로 이동한다.
//  `TranslationPickerPopover`와 같은 `.popover` 패턴이지만 칩 그리드가 아닌 목록형이다.
//  헤더(개수 배지), 한 줄 행(책/장(:절) + 상대 저장 시각), 스와이프 삭제, 빈 상태 안내를 제공한다.
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
            header
            Divider()
            if bookmarks.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(settings.bibleBackgroundColor ?? Color.clear)
        .frame(width: isPhone ? nil : 300)
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

    #if os(iOS)
    /// 시트 높이: 헤더(약 44) + 구분선(1) + 컨텐츠(빈 상태 180 고정, 목록은 `list`와 같은 계산식으로 최대 360).
    private var sheetHeight: CGFloat {
        let headerHeight: CGFloat = 44
        let dividerHeight: CGFloat = 1
        let contentHeight: CGFloat = bookmarks.isEmpty ? 180 : min(CGFloat(bookmarks.count) * 44 + 8, 360)
        return headerHeight + dividerHeight + contentHeight
    }
    #endif

    private var header: some View {
        HStack(spacing: 6) {
            Text("책갈피")
                .font(.headline)
                .foregroundStyle(settings.bibleTextColor ?? .primary)
            if !bookmarks.isEmpty {
                Text("\(bookmarks.count)")
                    .font(.caption)
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(settings.bibleTextColor?.opacity(0.12) ?? Color.secondary.opacity(0.15), in: Capsule())
            }
            Spacer()
            // 팝오버는 바깥 탭으로도 닫히지만, 명시적 닫기 버튼을 같은 줄에 둔다(세로 공간 절약).
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("닫기")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bookmark")
                .font(.system(size: 28))
                .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
            Text("책갈피가 없습니다")
                .font(.callout)
                .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
            Text("성경 조회 상단의 책갈피 아이콘을 눌러 지금 위치를 저장하세요.")
                .font(.caption)
                .foregroundStyle(settings.bibleTextColor?.opacity(0.4) ?? Color.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }

    private var list: some View {
        // `List`는 자체 배경이 있어 `.background()`만으로는 바뀌지 않는다 —
        // `.scrollContentBackground(.hidden)`와 `.background()`를 짝으로 쓴다.
        List {
            ForEach(bookmarks) { bookmark in
                row(for: bookmark)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            delete(bookmark)
                        } label: {
                            Label("삭제", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(settings.bibleBackgroundColor ?? Color.clear)
        // 행 높이 44pt(HIG 최소 탭 영역) 기준으로 계산하며 최대 360.
        .frame(height: min(CGFloat(bookmarks.count) * 44 + 8, 360))
    }

    private func row(for bookmark: BibleBookmark) -> some View {
        Button {
            viewModel.navigateToBookmark(bookmark)
            onDismiss()
        } label: {
            // 제목은 왼쪽, 상대 시각은 오른쪽 끝에 두어 한 줄로 구성한다(세로 공간 절약).
            HStack(spacing: 8) {
                Text(bookChapterLabel(for: bookmark))
                    .font(.body)
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(Self.relativeTimeFormatter.localizedString(for: bookmark.createdAt, relativeTo: .now))
                    .font(.caption)
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
