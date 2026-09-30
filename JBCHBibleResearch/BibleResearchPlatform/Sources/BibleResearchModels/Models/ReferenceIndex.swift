import Foundation
import SwiftData

// ThemeIndex/ThemeLink/PersonIndex/PlaceIndex/TimelineEvent: 구조 인덱스 계층.
// KeywordIndex는 Tag로 통합됐다(Tags.swift 참고).

/// 주제(테마) 마스터 목록. ⚠️ `name`에 unique 제약을 두지 않는다.
@Model
public final class ThemeIndex {
    public var id: UUID = UUID()
    public var name: String = ""
    public var themeDescription: String = ""
    public var createdAt: Date = Date.now

    // to-many @Relationship은 타입 자체가 Optional이어야 CloudKit이 받아들인다(Tags.swift 상단 주석 참고).
    @Relationship(deleteRule: .cascade, inverse: \ThemeLink.theme)
    public var links: [ThemeLink]? = []

    public init(id: UUID = UUID(), name: String, themeDescription: String = "", createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.themeDescription = themeDescription
        self.createdAt = createdAt
    }
}

@Model
public final class ThemeLink {
    public var id: UUID = UUID()
    public var bookId: Int = 1
    public var chapter: Int = 1
    public var verse: Int?
    public var note: String = ""

    public var theme: ThemeIndex?

    public init(
        id: UUID = UUID(),
        bookId: Int,
        chapter: Int,
        verse: Int? = nil,
        note: String = "",
        theme: ThemeIndex? = nil
    ) {
        self.id = id
        self.bookId = bookId
        self.chapter = chapter
        self.verse = verse
        self.note = note
        self.theme = theme
    }
}

/// 성경 본문 내 키워드 발생 위치(`Tag`와 연결). 현재 이 테이블을 채우는 화면은 없다(향후 확장용).
@Model
public final class KeywordOccurrence {
    public var id: UUID = UUID()
    public var bookId: Int = 1
    public var chapter: Int = 1
    public var verse: Int?
    public var contextSnippet: String = ""
    public var position: Int = 0

    public var tag: Tag?

    public init(
        id: UUID = UUID(),
        bookId: Int,
        chapter: Int,
        verse: Int? = nil,
        contextSnippet: String = "",
        position: Int = 0,
        tag: Tag? = nil
    ) {
        self.id = id
        self.bookId = bookId
        self.chapter = chapter
        self.verse = verse
        self.contextSnippet = contextSnippet
        self.position = position
        self.tag = tag
    }
}

@Model
public final class PersonIndex {
    public var id: UUID = UUID()
    public var name: String = ""
    public var aliases: [String] = []
    public var personDescription: String = ""

    public init(id: UUID = UUID(), name: String, aliases: [String] = [], personDescription: String = "") {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.personDescription = personDescription
    }
}

/// 좌표는 CoreLocation 등 특정 프레임워크에 종속되지 않도록 위도/경도 원시값(Double?)으로 저장한다.
@Model
public final class PlaceIndex {
    public var id: UUID = UUID()
    public var name: String = ""
    public var aliases: [String] = []
    public var latitude: Double?
    public var longitude: Double?
    public var placeDescription: String = ""

    public init(
        id: UUID = UUID(),
        name: String,
        aliases: [String] = [],
        latitude: Double? = nil,
        longitude: Double? = nil,
        placeDescription: String = ""
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.latitude = latitude
        self.longitude = longitude
        self.placeDescription = placeDescription
    }
}

/// `personIds`/`placeIds`는 PersonIndex/PlaceIndex로의 @Relationship이 아니라 원시 UUID 배열로 유지한다.
@Model
public final class TimelineEvent {
    public var id: UUID = UUID()
    public var title: String = ""
    public var eraOrDate: String = ""
    public var eventDescription: String = ""
    public var personIds: [UUID] = []
    public var placeIds: [UUID] = []
    public var verseRefs: [BibleVerseRef] = []

    public init(
        id: UUID = UUID(),
        title: String,
        eraOrDate: String = "",
        eventDescription: String = "",
        personIds: [UUID] = [],
        placeIds: [UUID] = [],
        verseRefs: [BibleVerseRef] = []
    ) {
        self.id = id
        self.title = title
        self.eraOrDate = eraOrDate
        self.eventDescription = eventDescription
        self.personIds = personIds
        self.placeIds = placeIds
        self.verseRefs = verseRefs
    }
}
