//
//  LastBiblePositionTracker.swift
//  JBCHBibleResearch
//
//  screens.md 13.1 — "새 메모"를 만들 때 쓸 성경 좌표 기본값 결정 표의 두 번째 행:
//  "S2/S3 목록의 '+' 버튼 / ⌘N → 이번 세션에서 마지막으로 본 성경 위치". 13.1은
//  이 값을 "가벼운 앱 상태로만 추적, 영구 저장 불필요"라고 명시했었다.
//
//  [2026-08-08 변경] 사용자 요청 — "앱을 종료했다 켜면 다시 이전 봤던 성경 장이
//  나올 수 있도록"(S1 위치를 앱 재시작 후에도 복원). 이전엔 이 타입이 메모리
//  전용이라 `BibleReadingViewModel.init`이 이 값으로 폴백해도 앱을 완전히
//  껐다 켜면(프로세스 재시작) 사라져 있었다 — 13.1의 원래 요구사항(메모 기본
//  좌표용)은 "영구 저장 불필요"였지만, 이번 새 요구사항(S1 위치 복원)은
//  명시적으로 "영구 저장 필요"다. 두 기능이 같은 트래커를 공유하므로, 이
//  트래커 자체를 `UserDefaults` 백업으로 바꿔 두 요구사항을 동시에 만족시켰다
//  (메모 기본 좌표 쪽도 영구 저장되어 나쁠 것은 없다 — 오히려 일관적이다).
//
//  BibleReadingViewModel이 책/장을 바꿀 때마다(selectBook/goToChapter) 이 트래커를
//  갱신한다.
//

import Foundation
import Observation

@MainActor
@Observable
final class LastBiblePositionTracker {
    static let shared = LastBiblePositionTracker()

    private enum Key {
        static let bookId = "lastBiblePosition.bookId"
        static let chapter = "lastBiblePosition.chapter"
    }

    private let defaults: UserDefaults

    private(set) var bookId: Int?
    private(set) var chapter: Int?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.bookId = defaults.object(forKey: Key.bookId) as? Int
        self.chapter = defaults.object(forKey: Key.chapter) as? Int
    }

    func update(bookId: Int, chapter: Int) {
        self.bookId = bookId
        self.chapter = chapter
        defaults.set(bookId, forKey: Key.bookId)
        defaults.set(chapter, forKey: Key.chapter)
    }
}
