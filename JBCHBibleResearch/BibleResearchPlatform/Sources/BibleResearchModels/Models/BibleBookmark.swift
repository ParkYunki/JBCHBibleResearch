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
//
// [2026-09-04 변경] 사용자 요청 — "북마크를 번역본 별로 북마크 데이터를
// 저장하도록. (macos, ipados) 가장 왼쪽의 번역본에 저장. (iOS아이폰) 현재 화면에
// 표시된 번역본에 저장. 화면에 북마크 세로선도 번역본마다 다르게 나와야 한다."
// 이전까지는 책갈피가 번역본과 무관(모든 번역본 칼럼이 같은 책갈피 세로선을
// 공유)했는데, 이제 `translationCode`(`TranslationRegistry.code`)를 함께 저장해
// 정확히 어느 번역본의 책갈피인지 구분한다 — 대상 번역본 선택 규칙(맨 왼쪽/현재
// 화면) 자체는 `BibleReadingView.swift`의 `bookmarkTargetTranslationCode`가
// 정하고, 실제 조회/토글은 여기 값으로 정확히 일치하는 것만 찾는다
// (`BibleBookmarkService.find` 참고).
//
// 이 필드가 생기기 전(레거시) 책갈피는 기본값 ""로 저장돼 있었다 — 사용자 확인
// (기존 책갈피는 "첫 번째(기본) 번역본으로 자동 전환")에 따라
// `BibleReadingViewModel.migrateLegacyBookmarksIfNeeded()`가 앱 시작 시 한 번
// 채워 넣는다. 정상적으로 동작 중인 앱에서는 빈 문자열로 남아 있는 책갈피가
// 있어서는 안 된다.

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
    /// 이 책갈피가 속한 번역본(`TranslationRegistry.code`). 위 2026-09-04 변경
    /// 주석 참고 — 레거시 데이터(빈 문자열)는 마이그레이션 대상이다.
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
