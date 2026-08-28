import Foundation
import SwiftData

// [2026-08-28 신설] 사용자 요청 — "성경조회 기능의 책갈피 기능 추가. 히스토리
// 이력 제외." `BibleReadingHistory.swift`의 기존 원칙(성경 좌표는 관계가 아니라
// 원시 Int로 저장, CloudKit 동기화 단순화)을 그대로 따른다 — 다만 이력과 달리
// "몇 개가 쌓였는지"가 아니라 "지금 이 위치가 책갈피인지"가 핵심이라 100개 캡
// 같은 트리밍 정책은 없다(사용자가 직접 설정/해제하는 항목이라 자동으로 지울
// 이유가 없다).
//
// 저장 단위는 사용자 확인대로 조회 이력과 동일하다 — 구절을 선택한 채로
// 책갈피를 설정하면 그 절까지, 선택 없이 설정하면 장 전체를 가리킨다(`verse`
// 옵셔널). `BibleBookmarkService.swift` 상단 주석 참고.

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
    public var createdAt: Date = Date.now

    public init(id: UUID = UUID(), bookId: Int, chapter: Int, verse: Int? = nil, createdAt: Date = .now) {
        self.id = id
        self.bookId = bookId
        self.chapter = chapter
        self.verse = verse
        self.createdAt = createdAt
    }
}
