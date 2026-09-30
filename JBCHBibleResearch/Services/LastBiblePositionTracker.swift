//
//  LastBiblePositionTracker.swift
//  JBCHBibleResearch
//
//  마지막으로 본 성경 위치(책/장)를 추적한다. 새 메모의 기본 성경 좌표와 앱 재시작 후 성경 조회 화면
//  위치 복원이 이 값을 공유하므로 `UserDefaults`에 영구 저장한다.
//  `BibleReadingViewModel`이 책/장을 바꿀 때마다(selectBook/goToChapter) 갱신한다.
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
