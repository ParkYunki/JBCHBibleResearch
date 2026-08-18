import Foundation

// 근거: bible-research-platform-schema.md 2장 — "번역본 종속적인 verse row가 아니라
// 성경 좌표(book_id, chapter, verse) 자체를 참조 키로 사용". BibleVerses는 번역본별
// SQLite 파일(BibleReference/BibleReferenceStore.swift)로 이 SwiftData/CloudKit 레이어
// 밖에 있으므로, 좌표를 가리키는 모든 곳에서 관계가 아니라 값 타입으로 저장한다.

/// 책+장 단위 참조. `LectureNote.chapterRefs`에 사용.
public struct BibleChapterRef: Codable, Hashable, Sendable {
    public var bookId: Int
    public var chapter: Int

    public init(bookId: Int, chapter: Int) {
        self.bookId = bookId
        self.chapter = chapter
    }
}

/// 책+장+절 단위 참조. `DocumentAnchor.linkedVerse`/`TimelineEvent.verseRefs`에 사용.
public struct BibleVerseRef: Codable, Hashable, Sendable {
    public var bookId: Int
    public var chapter: Int
    public var verse: Int

    public init(bookId: Int, chapter: Int, verse: Int) {
        self.bookId = bookId
        self.chapter = chapter
        self.verse = verse
    }
}
