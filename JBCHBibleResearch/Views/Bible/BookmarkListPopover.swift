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
#if os(iOS)
import UIKit
#endif

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

    /// [2026-09-04 신설] 사용자 보고 — "전체 영역에 비해 컨텐츠 영역이
    /// 1/3부분임. 작은 컨텐츠 영역에 스크롤까지 있음. 위아래 여백이
    /// 불필요함." 아이폰에서는 `.popover`가 자동으로 시트로 바뀌는데(아래
    /// `isPhone` 참고), 이 뷰 자체는 고정 폭(300)·높이 상한(최대 360, 아래
    /// `list` 참고)짜리 작은 카드라 시트가 기본 크기(예: 화면 대부분)로
    /// 뜨면 그 안에 작은 카드 하나만 떠 있고 나머지는 빈 여백이 된다.
    /// `.presentationDetents`로 시트 높이 자체를 실제 컨텐츠 높이에 맞춰
    /// 계산해, 여백을 없애는 쪽으로 정리했다(아이패드/macOS의 실제 팝오버는
    /// 원래도 이 문제가 없어 손대지 않는다 — `isPhone`이 false면 기존과
    /// 완전히 동일).
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
        .frame(width: isPhone ? nil : 300)
        #if os(iOS)
        .modifier(BookmarkSheetSizingModifier(isPhone: isPhone, sheetHeight: sheetHeight))
        #endif
        .onAppear {
            // [2026-08-08 조회 이력 시트와 같은 이유] 팝오버를 열 때마다 새로
            // 불러온다 — 다른 창에서 설정/해제한 책갈피까지 반영되도록
            // 캐싱하지 않는다.
            bookmarks = viewModel.fetchBookmarks()
        }
    }

    /// [2026-09-04 신설] `BibleReadingView.swift`의 같은 이름 프로퍼티와
    /// 정확히 같은 판정(그쪽은 `private`라 이 파일에서 직접 재사용은 안 돼,
    /// 로직만 그대로 옮겨 왔다) — 아이폰이면 `.popover`가 시트로 바뀐다.
    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    #if os(iOS)
    /// 위 `body`의 `.presentationDetents` 주석 참고 — 헤더(약 44) + 구분선(1)
    /// + 컨텐츠(빈 상태 180 고정, 목록이면 `list`와 같은 계산식으로 최대
    /// 360)를 더해 시트가 딱 그만큼만 뜨게 한다.
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
            if !bookmarks.isEmpty {
                Text("\(bookmarks.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
            Spacer()
            // [2026-09-04 신설] 사용자 요청 — "닫기 버튼을 추가할 것." 팝오버는
            // 바깥을 탭해도 닫히지만, 명시적인 닫기 동작을 요청하셔서 같은 줄에
            // 추가했다 — 새 줄을 만들지 않아 세로 공간을 더 쓰지 않는다.
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
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
        // [2026-09-04 변경] 사용자 요청 — "화면영역이 낭비되지 않도록 정리."
        // 예전엔 "책/장:절" 한 줄 + 저장 시각 한 줄, 총 두 줄짜리 행이라 한
        // 행에 56pt를 잡아 뒀다. 아래 `row(for:)`를 한 줄(제목 + 오른쪽 정렬된
        // 상대 시각)로 합쳐 행이 짧아진 만큼, 같은 화면 높이에 더 많은 항목이
        // 보이도록 44pt(HIG 최소 탭 영역과도 맞는 값)로 줄였다.
        .frame(height: min(CGFloat(bookmarks.count) * 44 + 8, 360))
    }

    private func row(for bookmark: BibleBookmark) -> some View {
        Button {
            viewModel.navigateToBookmark(bookmark)
            onDismiss()
        } label: {
            // [2026-09-04 변경] 사용자 요청 — "화면영역이 낭비되지 않도록
            // 정리." 제목/시각을 세로로 나눈 두 줄 대신, 한 줄 안에서 제목은
            // 왼쪽에 그대로 두고 시각은 오른쪽 끝으로 보내 가로 공간을 마저
            // 쓴다(Safari 읽기 목록 등에서 흔한 배치) — 세로 공간을 절반 가까이
            // 줄인다.
            HStack(spacing: 8) {
                Text(bookChapterLabel(for: bookmark))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(Self.relativeTimeFormatter.localizedString(for: bookmark.createdAt, relativeTo: .now))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    /// [2026-08-26 `BibleReadingHistorySheet.bookChapterLabel`과 동일한 규칙]
    /// `verse`가 있으면 "장:절", 없으면 "장"으로 보여준다.
    ///
    /// [2026-09-04 수정] 사용자 요청("북마크를 번역본 별로 저장하도록")의
    /// 직접적인 결과 — 이제 같은 책/장(:절) 위치라도 번역본이 다르면 서로
    /// 다른 책갈피가 될 수 있어(`BibleBookmark.translationCode`), 등록된
    /// 번역본이 2개 이상일 때는 행 제목 끝에 번역본 이름을 붙여 구분한다(예:
    /// "창세기 2장 · 개역개정"). 번역본이 1개뿐이면 구분할 필요가 없어(모든
    /// 책갈피가 어차피 같은 번역본) 원래 표시 그대로 둔다 — 불필요한 잡음을
    /// 더하지 않기 위해서다.
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
/// [2026-09-04 신설] 위 `body`의 `.presentationDetents` 주석 참고 — 아이폰
/// (시트로 바뀔 때)에만 높이를 컨텐츠에 맞추고, 아이패드(진짜 팝오버)는
/// 이 모디파이어 자체가 아무 것도 하지 않아 기존 그대로다.
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
