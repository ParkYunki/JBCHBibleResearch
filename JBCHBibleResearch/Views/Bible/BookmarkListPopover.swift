//
//  BookmarkListPopover.swift
//  JBCHBibleResearch
//
//  [2026-08-28 신설] 사용자 요청 — "성경조회 기능의 책갈피 기능 추가 ... 책갈피
//  아이콘 왼쪽 옆에 책갈피 이동 아이콘 추가(작은 레이어 팝업창 안에 책갈피 리스트
//  출력 -> 터치 이동)." `TranslationPickerPopover.swift`와 같은 "`.popover`로
//  띄우는 작은 팝업" 패턴이지만, 그 팝업은 칩 그리드인 반면 이 팝업은 "탭하면
//  이동" 목록형이다.
//
//  히스토리와 달리 항목을 탭해 이동해도 새 이력이 남지 않는다(사용자 요청 —
//  "히스토리 이력 제외") — `BibleReadingViewModel.navigateToBookmark` 참고.
//
//  [2026-08-28 재설계] 사용자 요청 — "책갈피 팝업과 그 항목들을 UI/UX 전문가
//  관점에서 디자인을 변경할 것." 초판은 `BibleReadingHistorySheet`의 레이아웃
//  (한 줄짜리 `Text` 행)을 그대로 옮겨 온 것뿐이었다 — 이번엔 이 팝업 자신의
//  목적("가끔 몇 개 없는 위치를 빠르게 훑고 이동")에 맞춰 다시 짰다.
//  - 헤더("책갈피" + 개수 배지)를 추가해, 어떤 팝업인지/몇 개가 있는지 목록을
//    보기 전에 바로 알 수 있게 했다(`TranslationPickerPopover`의 "표시할
//    번역본 (최대 N개)" 헤더와 같은 이유).
//  - 각 행을 "책/장(:절)" 한 줄 + 저장 시각(상대 표기, 예: "3일 전") 한 줄로
//    나눴다 — 히스토리(정확한 년월일시분초가 요구사항이었다, 상단 주석 참고)와
//    달리 책갈피는 "언제 저장했는지"가 정밀할 필요는 없고 "최근에 저장한 것"
//    정도만 한눈에 구분되면 충분해서, 더 읽기 쉬운 상대 시각으로 바꿨다.
//  - 스와이프 삭제(`​.swipeActions`)를 추가했다 — 지금까지는 책갈피를 지우려면
//    그 위치로 다시 이동해 툴바의 책갈피 아이콘을 다시 눌러야만 했는데(설정/
//    해제 토글 하나뿐), 이동 목록에서 바로 정리할 수 있는 편이 북마크/즐겨찾기
//    목록의 통상적인 관리 방식(Safari 읽기 목록, 미리알림 등)과도 맞고 사용성이
//    분명히 낫다고 판단해 추가했다 — `BibleReadingViewModel.deleteBookmark` 참고.
//  - 빈 상태 안내에 "어떻게 추가하는지"까지 덧붙였다 — 그냥 "없습니다"보다,
//    처음 보는 사용자가 다음에 뭘 해야 할지 바로 알 수 있는 편이 낫다.
//

import SwiftUI
import BibleResearchModels

struct BookmarkListPopover: View {
    let viewModel: BibleReadingViewModel
    var onDismiss: () -> Void

    @State private var bookmarks: [BibleBookmark] = []

    private static let relativeTimeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .short
        return formatter
    }()

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
        .frame(width: 300)
        .onAppear {
            // [2026-08-08 조회 이력 시트와 같은 이유] 팝오버를 열 때마다 새로
            // 불러온다 — 다른 창에서 설정/해제한 책갈피까지 반영되도록
            // 캐싱하지 않는다.
            bookmarks = viewModel.fetchBookmarks()
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("책갈피")
                .font(.headline)
            if !bookmarks.isEmpty {
                Text("\(bookmarks.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bookmark")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("책갈피가 없습니다")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("성경 조회 상단의 책갈피 아이콘을 눌러 지금 위치를 저장하세요.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }

    private var list: some View {
        List {
            ForEach(bookmarks) { bookmark in
                row(for: bookmark)
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
        .frame(height: min(CGFloat(bookmarks.count) * 56 + 8, 360))
    }

    private func row(for bookmark: BibleBookmark) -> some View {
        Button {
            viewModel.navigateToBookmark(bookmark)
            onDismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(bookChapterLabel(for: bookmark))
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(Self.relativeTimeFormatter.localizedString(for: bookmark.createdAt, relativeTo: .now))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func delete(_ bookmark: BibleBookmark) {
        viewModel.deleteBookmark(bookmark)
        bookmarks.removeAll { $0.id == bookmark.id }
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
