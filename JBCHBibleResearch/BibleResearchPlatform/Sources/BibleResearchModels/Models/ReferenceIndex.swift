import Foundation
import SwiftData

// 근거: bible-research-platform-schema.md 2장(구조 인덱스 계층). 6.3에서 KeywordIndex는
// Tag로 통합됐지만(Tags.swift 참고), ThemeIndex/ThemeLink/PersonIndex/PlaceIndex/
// TimelineEvent는 6장에서 변경 대상이 아니었으므로 원본 스키마 그대로 유지한다.

/// 주제(테마) 마스터 목록. ⚠️ `name UNIQUE`가 원본 스키마에 없었으므로 unique를
/// 애초에 붙이지 않는다 — Tag/BookOutline과 달리 이 테이블은 addendum이 크리티컬
/// 이슈로 지적한 대상이 아니었다(원본에 unique 표기 자체가 없었음).
@Model
public final class ThemeIndex {
    public var id: UUID = UUID()
    public var name: String = ""
    public var themeDescription: String = ""
    public var createdAt: Date = Date.now

    // ⚠️ 2026-08-06 실기기 확인: to-many @Relationship은 타입 자체가 Optional이어야
    // CloudKit이 받아들인다(Tags.swift 상단 주석 참고).
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

/// 원본 `KeywordOccurrence(id, keyword_id, book_id, chapter, verse?, context_snippet, position)`.
/// 6.3: "원본의 keyword_id → tag_id로 통일". 성경 본문 내 발생 — 현재 어떤 화면도
/// 이 테이블을 채우도록 설계돼 있지 않다(향후 확장 여지로만 유지, 6.3 그대로).
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

/// 원본 `coordinates?` — CoreLocation 등 특정 프레임워크에 종속시키지 않기 위해
/// 위도/경도 원시값(Double?)으로 저장한다. 📝 구현 결정: 원본 문서에 좌표 표현 방식이
/// 명시돼 있지 않아, 가장 프레임워크 중립적인 형태를 선택했다.
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

/// 원본 `TimelineEvent(id, title, era_or_date, description, person_ids[], place_ids[],
/// verse_refs[])`. person_ids/place_ids는 원본이 명시한 그대로 원시 UUID 배열로 유지한다
/// (PersonIndex/PlaceIndex로의 실제 @Relationship 전환은 근거 없는 리팩토링이라 보류 —
/// 필요해지면 별도 논의).
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
