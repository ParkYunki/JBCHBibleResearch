import Foundation
import SwiftData

// 성경 조회 화면의 책갈피. `BibleReadingHistory.swift`와 같은 원칙으로 성경 좌표를
// 관계가 아니라 원시 Int로 저장한다(CloudKit 동기화 단순화). 사용자가 직접
// 설정/해제하는 항목이라 이력과 달리 개수 제한(트리밍) 정책이 없다.
//
// 구절을 선택한 채 설정하면 그 절까지, 선택 없이 설정하면 장 전체를 가리킨다
// (`verse` 옵셔널). 책갈피는 번역본별로 저장되며(`translationCode`), 조회/토글은
// 값이 정확히 일치하는 것만 찾는다(`BibleBookmarkService.find`). 대상 번역본
// 선택 규칙은 `BibleReadingView`의 `bookmarkTargetTranslationCode`가 정한다.
//
// `translationCode`가 없던 시절의 레거시 책갈피는 ""로 저장돼 있어,
// `BibleReadingViewModel.migrateLegacyBookmarksIfNeeded()`가 앱 시작 시 한 번
// 첫 번째(기본) 번역본 코드로 채운다. 정상 상태에서는 빈 문자열이 남아 있으면 안 된다.

/// 성경 조회(S1) 화면에서 사용자가 직접 설정/해제하는 책갈피 한 건. 조회
/// 이력(`BibleReadingHistoryEntry`)과 달리 자동으로 쌓이지 않고, 오직
/// `BibleBookmarkService.toggle(...)`을 통해서만 추가/삭제된다.
@Model
public final class BibleBookmark {
    public var id: UUID = UUID()
    public var bookId: Int = 1
    public var chapter: Int = 1
    /// nil이면 "장 전체"를 가리키는 책갈피, 값이 있으면 그 절까지 가리키는
    /// 책갈피다(`BibleReadingHistoryEntry.verse`와 동일한 규칙).
    public var verse: Int? = nil
    /// 이 책갈피가 속한 번역본(`TranslationRegistry.code`). 레거시 데이터(빈 문자열)는
    /// 마이그레이션 대상이다.
    public var translationCode: String = ""
    public var createdAt: Date = Date.now

    public init(id: UUID = UUID(), bookId: Int, chapter: Int, verse: Int? = nil, translationCode: String, createdAt: Date = .now) {
        self.id = id
        self.bookId = bookId
        self.chapter = chapter
        self.verse = verse
        self.translationCode = translationCode
        self.createdAt = createdAt
    }
}
