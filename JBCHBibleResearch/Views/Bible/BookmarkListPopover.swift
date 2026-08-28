//
//  BookmarkListPopover.swift
//  JBCHBibleResearch
//
//  [2026-08-28 신설] 사용자 요청 — "성경조회 기능의 책갈피 기능 추가 ... 책갈피
//  아이콘 왼쪽 옆에 책갈피 이동 아이콘 추가(작은 레이어 팝업창 안에 책갈피 리스트
//  출력 -> 터치 이동)." `TranslationPickerPopover.swift`와 같은 "`.popover`로
//  띄우는 작은 팝업" 패턴이지만, 그 팝업은 칩 그리드인 반면 이 팝업은
//  `BibleReadingHistorySheet`(조회 이력 시트)와 같은 "탭하면 이동" 목록형이라
//  레이아웃은 그쪽을 따르고 프레젠테이션 방식(시트가 아니라 팝오버)만 다르게 했다.
//
//  히스토리와 달리 항목을 탭해 이동해도 새 이력이 남지 않는다(사용자 요청 —
//  "히스토리 이력 제외") — `BibleReadingViewModel.navigateToBookmark` 참고.
//

import SwiftUI
import BibleResearchModels

struct BookmarkListPopover: View {
    let viewModel: BibleReadingViewModel
    var onDismiss: () -> Void

    @State private var bookmarks: [BibleBookmark] = []

    var body: some View {
        Group {
            if bookmarks.isEmpty {
                ContentUnavailableView("책갈피가 없습니다", systemImage: "bookmark")
                    .frame(width: 280, height: 180)
            } else {
                List(bookmarks) { bookmark in
                    Button {
                        viewModel.navigateToBookmark(bookmark)
                        onDismiss()
                    } label: {
                        Text(bookChapterLabel(for: bookmark))
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .frame(width: 280, height: min(CGFloat(bookmarks.count) * 44 + 16, 360))
            }
        }
        .onAppear {
            // [2026-08-08 조회 이력 시트와 같은 이유] 팝오버를 열 때마다 새로
            // 불러온다 — 다른 창에서 설정/해제한 책갈피까지 반영되도록
            // 캐싱하지 않는다.
            bookmarks = viewModel.fetchBookmarks()
        }
    }

    /// [2026-08-26 `BibleReadingHistorySheet.bookChapterLabel`과 동일한 규칙]
    /// `verse`가 있으면 "장:절", 없으면 "장"으로 보여준다.
    private func bookChapterLabel(for bookmark: BibleBookmark) -> String {
        guard let book = BooksProvider.shared.book(id: bookmark.bookId) else {
            if let verse = bookmark.verse {
                return "책 \(bookmark.bookId) \(bookmark.chapter):\(verse)"
            }
            return "책 \(bookmark.bookId) \(bookmark.chapter)장"
        }
        if let verse = bookmark.verse {
            return "\(book.nameKo) \(bookmark.chapter):\(verse)"
        }
        return "\(book.nameKo) \(bookmark.chapter)장"
    }
}
