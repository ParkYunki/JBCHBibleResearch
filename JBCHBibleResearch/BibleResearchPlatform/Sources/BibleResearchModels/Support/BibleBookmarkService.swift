import Foundation
import SwiftData

// [2026-08-28 신설] 사용자 요청 — "성경조회 기능의 책갈피 기능 추가." "설정/해제
// 토글"과 "정확히 일치하는 책갈피 찾기" 정책을 모두 이 서비스가 책임진다 —
// `BibleBookmark` 모델 자체엔 정책 로직을 넣지 않는다(`BibleReadingHistoryService.swift`와
// 동일한 이 프로젝트의 관례).
//
// [2026-09-04 변경] 사용자 요청 — "북마크를 번역본 별로 저장." book/chapter/verse
// 조합만으로 찾던 것을 `translationCode`까지 정확히 일치해야 같은 책갈피로 본다 —
// `BibleBookmark.swift` 상단 주석 참고. 대상 번역본 코드 자체를 결정하는 규칙(맨
// 왼쪽 컬럼/현재 화면 컬럼)은 이 서비스가 아니라 호출부(`BibleReadingViewModel`)의
// 책임이다.
//
// ⚠️ 이 파일은 Xcode에서 컴파일·테스트되지 않았습니다(다른 Support 파일들과 동일한
// 제약 승계).
public enum BibleBookmarkService {
    /// bookId/chapter/verse/translationCode가 정확히 일치하는 책갈피가 있으면
    /// 그것을 돌려준다(없으면 nil). `verse`가 nil인 책갈피(장 전체)와 값이 있는
    /// 책갈피(그 절)는 서로 다른 책갈피로 구분하고, 같은 위치라도 번역본이
    /// 다르면 역시 서로 다른 책갈피로 구분한다.
    public static func find(bookId: Int, chapter: Int, verse: Int?, translationCode: String, context: ModelContext) -> BibleBookmark? {
        let all = (try? context.fetch(FetchDescriptor<BibleBookmark>())) ?? []
        return all.first { $0.bookId == bookId && $0.chapter == chapter && $0.verse == verse && $0.translationCode == translationCode }
    }

    /// 지금 이 위치(장, 또는 절까지)가 해당 번역본 기준으로 이미 책갈피로 설정돼
    /// 있는지.
    public static func isBookmarked(bookId: Int, chapter: Int, verse: Int?, translationCode: String, context: ModelContext) -> Bool {
        find(bookId: bookId, chapter: chapter, verse: verse, translationCode: translationCode, context: context) != nil
    }

    /// 설정/해제 토글 — 이미 있으면 지우고, 없으면 새로 만든다. 호출부
    /// (`BibleReadingViewModel.toggleBookmarkForCurrentPosition`)가 "지금 절을
    /// 선택 중인지"로 `verse` 인자를, "맨 왼쪽/현재 화면 번역본이 무엇인지"로
    /// `translationCode` 인자를 결정해 넘긴다(선택 중이면 그 절, 아니면 nil).
    @discardableResult
    public static func toggle(bookId: Int, chapter: Int, verse: Int?, translationCode: String, context: ModelContext) -> Bool {
        if let existing = find(bookId: bookId, chapter: chapter, verse: verse, translationCode: translationCode, context: context) {
            context.delete(existing)
            return false
        }
        context.insert(BibleBookmark(bookId: bookId, chapter: chapter, verse: verse, translationCode: translationCode, createdAt: .now))
        return true
    }

    /// 책갈피 전체 목록(모든 번역본 통틀어) — 최신 설정순. 조회 이력과 달리
    /// 개수 상한은 없다(사용자가 직접 설정/해제하는 항목이라 자동으로 지울
    /// 이유가 없다 — `BibleBookmark.swift` 상단 주석 참고). 특정 번역본으로
    /// 좁히지 않는 이유는 호출부(`BibleReadingViewModel.fetchBookmarks`,
    /// `rebuildBookmarkedVersesIndex`) 상단 주석 참고 — 각자 필요한 기준으로
    /// 이 결과를 다시 거른다.
    public static func fetchAll(context: ModelContext) -> [BibleBookmark] {
        (try? context.fetch(
            FetchDescriptor<BibleBookmark>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        )) ?? []
    }
}
