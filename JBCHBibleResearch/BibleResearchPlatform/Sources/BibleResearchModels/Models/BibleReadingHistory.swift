import Foundation
import SwiftData

// [2026-08-08 신설] 사용자 요청 — "조회 이력(히스토리) 기능 추가 (년월일 시분초),
// 100개의 조회한 성경과 장의 이력을 저장하고 조회할 수 있도록". UserContent.swift
// 상단 주석의 기존 원칙(성경 좌표는 관계가 아니라 원시 Int로 저장)을 그대로 따른다 —
// 이 이력 항목은 특정 "조회 사건"의 스냅샷이라 BibleChapterRef 값 타입보다는
// UserMemo/ChapterSummary처럼 bookId/chapter를 직접 필드로 갖는 편이 CloudKit
// 저장·정렬(SortDescriptor(\.viewedAt)) 모두에 단순하다.

/// 성경 조회(S1) 화면에서 실제로 "이동"이 일어날 때마다(책/장을 바꿀 때) 하나씩
/// 쌓이는 조회 이력 한 건. 100개 캡/중복 방지는 모델이 아니라
/// `BibleReadingHistoryService`(앱 레이어)가 책임진다 — 이 모델은 순수 데이터
/// 구조체 역할만 한다(BookOutlineDeduplication 등과 동일하게, 모델 자체엔 정책
/// 로직을 넣지 않는 이 프로젝트의 관례).
@Model
public final class BibleReadingHistoryEntry {
    public var id: UUID = UUID()
    public var bookId: Int = 1
    public var chapter: Int = 1
    /// [2026-08-26 추가] 사용자 요청 — "성경 조회 히스토리 이력에 성경 장에 대해
    /// 기록하던 것을 장절까지 기록을 남겨둘것." 기존 필드(bookId/chapter)는 그대로
    /// 두고 절 정보만 선택적으로 얹는다 — CloudKit 동기화 중인 기존 레코드와의
    /// 호환을 위해 새 필드는 항상 옵셔널 + 기본값이어야 한다(UserContent.swift/
    /// 다른 @Model 상단 주석의 공통 관례). nil이면 "장 단위" 이동(책/장 선택, 이전·
    /// 다음 장 버튼, 뒤로/앞으로 가기 — `BibleReadingViewModel.selectBook`/
    /// `goToChapter`/`navigate(toHistory:)`)이고, 값이 있으면 "절 단위" 이동
    /// (확대보기를 열었거나, 사이드바 상단 검색에서 구절 결과를 눌러 그 절로 바로
    /// 이동한 경우 — `BibleReadingViewModel.recordVerseHistory` 참고)이다.
    public var verse: Int? = nil
    /// 사용자가 이 책/장을 조회한 시각(년월일 시분초 전부 필요 — 화면에서
    /// `yyyy-MM-dd HH:mm:ss` 포맷으로 표시한다).
    public var viewedAt: Date = Date.now

    public init(id: UUID = UUID(), bookId: Int, chapter: Int, verse: Int? = nil, viewedAt: Date = .now) {
        self.id = id
        self.bookId = bookId
        self.chapter = chapter
        self.verse = verse
        self.viewedAt = viewedAt
    }
}
