import Foundation
import SwiftData

// 성경 조회 이력. UserContent.swift와 같은 원칙으로 성경 좌표를 관계가 아니라
// 원시 Int로 저장한다 — 특정 "조회 사건"의 스냅샷이라 BibleChapterRef 값 타입보다
// bookId/chapter를 직접 필드로 갖는 편이 CloudKit 저장·정렬
// (SortDescriptor(\.viewedAt))에 단순하다.

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
    /// 나중에 추가된 필드라 CloudKit 동기화 중인 기존 레코드와의 호환을 위해
    /// 옵셔널 + 기본값이다. nil이면 "장 단위" 이동(책/장 선택, 이전·다음 장,
    /// 뒤로/앞으로 가기), 값이 있으면 "절 단위" 이동(확대보기, 검색 결과에서 절로
    /// 직접 이동 — `BibleReadingViewModel.recordVerseHistory` 참고)이다.
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
