import Foundation
import SwiftData

// 성경 좌표(book_id/chapter/verse)는 관계가 아니라 원시 Int로 저장한다 — 번역본 종속적인 verse row가
// 아니라 성경 좌표 자체를 참조 키로 쓰는 설계다. BibleVerses는 번역본별 SQLite 파일이라 이 SwiftData/CloudKit
// 레이어에 존재하지 않아 관계로 연결할 대상도 없다.

/// 메모 분류용 폴더. 메모당 1개만(단일 소속), 중첩 없음(플랫한 목록).
@Model
public final class MemoFolder {
    public var id: UUID = UUID()
    public var name: String = ""
    public var createdAt: Date = Date.now

    // ⚠️ to-many @Relationship도 타입 자체가 Optional이어야 CloudKit이 받아들인다
    // ([T] = []는 컴파일되지만 런타임에 CoreData 134060으로 실패). Tags.swift 상단 주석 참고.
    @Relationship(deleteRule: .nullify, inverse: \UserMemo.folder)
    public var memos: [UserMemo]? = []

    public init(id: UUID = UUID(), name: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

/// 개인묵상(플레인 텍스트) 글자수 제한. `NoteTextLimit`(`VerseAnnotations.swift`)과 같은 목적이고 값만 2000이다.
public struct MemoTextLimit {
    public static let maxCharacters = 2000
}

/// 사용자 메모. `content_html` + `content_text`(검색·임베딩용) 이원화.
/// 편집이 순수 텍스트라 `content_html`에도 항상 `content_text`와 같은 평문이 들어간다(RTF 서식 없음).
/// ⚠️ 태그는 배열 필드가 아니라 `MemoTag` 조인을 통해서만 연결된다.
@Model
public final class UserMemo {
    public var id: UUID = UUID()

    /// CloudKit은 non-optional 프로퍼티에 리터럴 기본값을 요구해 창세기 1장(book_id=1, chapter=1)을 기본값으로 둔다.
    /// "이번 세션 마지막 위치" 우선 로직은 이 모델이 아니라 메모 생성 화면(앱 레이어)의 책임이며,
    /// 이 값은 스키마 제약을 만족시키기 위한 자리표시자다.
    public var bookId: Int = 1
    public var chapter: Int = 1
    public var verse: Int?

    // 절 안 특정 표현에 대한 메모용 앵커(전부 옵셔널). nil이면 "절 전체" 메모, 채워지면 "그 표현" 메모다.
    // 앵커 규칙(오프셋 단위, 자가 치유용 스냅샷)은 `VerseAnnotations.swift` 상단 주석과 동일하다.
    public var rangeStart: Int?
    public var rangeEnd: Int?
    public var annotationTranslationCode: String?
    public var anchorText: String?

    public var contentHtml: String = ""
    public var contentText: String = ""

    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now

    /// 본문이 바뀌어 재인덱싱(`BibleReferenceIndexingService.reindexMemo`)이 필요한 상태면 `true`.
    /// 재인덱싱은 자동저장마다가 아니라 화면을 정상적으로 벗어날 때 한 번만 실행되고, 끝나면 `false`로 저장된다.
    /// 편집 중 강제 종료되면 `true`로 남는데, 이는 "인덱스가 최신이 아닐 수 있다"는 신호라 목록(MemoRowView)이 배지로 보여준다.
    public var pendingIndexRefresh: Bool = false

    /// 고정(핀) 여부. 기본값이 있는 저장 프로퍼티 추가라 SwiftData 가벼운 마이그레이션으로 처리되며 기존 데이터는 `false`다.
    public var isPinned: Bool = false

    // deleteRule은 MemoFolder.memos 쪽(inverse 선언부)에서만 지정한다 — 같은 관계 양쪽에 중복 지정하지 않는다.
    public var folder: MemoFolder?

    public var memoTags: [MemoTag]? = []

    public init(
        id: UUID = UUID(),
        bookId: Int,
        chapter: Int,
        verse: Int? = nil,
        rangeStart: Int? = nil,
        rangeEnd: Int? = nil,
        annotationTranslationCode: String? = nil,
        anchorText: String? = nil,
        contentHtml: String = "",
        contentText: String = "",
        pendingIndexRefresh: Bool = false,
        isPinned: Bool = false,
        folder: MemoFolder? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.bookId = bookId
        self.chapter = chapter
        self.verse = verse
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.annotationTranslationCode = annotationTranslationCode
        self.anchorText = anchorText
        self.contentHtml = contentHtml
        self.contentText = contentText
        self.pendingIndexRefresh = pendingIndexRefresh
        self.isPinned = isPinned
        self.folder = folder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 말씀 요약 — 구절을 골라 [말씀 요약]을 누를 때마다 새 레코드가 쌓이는 저널/묵상노트 성격이다.
/// 절당 하나를 덮어쓰는 `UserMemo`(개인 묵상)와 데이터 모양이 달라 별개 모델이다.
/// 본문은 `contentHtml`(실제로는 RTF, `UserMemo`와 같은 관례)/`contentText`(검색·미리보기용) 이원화. 폴더는 두지 않는다.
@Model
public final class VerseSummary {
    public var id: UUID = UUID()
    public var bookId: Int = 1
    public var chapter: Int = 1
    public var verse: Int?

    public var contentHtml: String = ""
    public var contentText: String = ""

    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now

    /// `UserMemo.pendingIndexRefresh`와 같은 용도.
    public var pendingIndexRefresh: Bool = false

    /// 관계에 `@Relationship`을 붙이지 않는다 — deleteRule은 `Tag.summaryTags`/`SummaryTag.summary` 쪽에서만 지정한다
    /// (`UserMemo.folder`와 같은 원칙).
    public var summaryTags: [SummaryTag]? = []

    /// `UserMemo.isPinned`와 같은 용도.
    public var isPinned: Bool = false

    public init(
        id: UUID = UUID(),
        bookId: Int,
        chapter: Int,
        verse: Int? = nil,
        contentHtml: String = "",
        contentText: String = "",
        pendingIndexRefresh: Bool = false,
        isPinned: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.bookId = bookId
        self.chapter = chapter
        self.verse = verse
        self.contentHtml = contentHtml
        self.contentText = contentText
        self.pendingIndexRefresh = pendingIndexRefresh
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 책 단위 개요. 항상 순수 사용자 입력이다(AI 없음, source 필드 없음).
/// ⚠️ unique 제약이 없다 — 대신 `conflictingOutlineId`로 사용자 선택형 충돌 해소를 쓴다.
/// BookOutline은 자유 텍스트라 두 기기의 내용이 다를 수 있어 Tag처럼 자동 병합하지 않는다.
@Model
public final class BookOutline {
    public var id: UUID = UUID()
    public var bookId: Int = 1
    public var contentHtml: String = ""
    public var contentText: String = ""
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now

    /// non-nil = 다른 기기와 내용 충돌. 경고 배너를 표시한다.
    public var conflictingOutlineId: UUID?

    public init(
        id: UUID = UUID(),
        bookId: Int,
        contentHtml: String = "",
        contentText: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.bookId = bookId
        self.contentHtml = contentHtml
        self.contentText = contentText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 장 단위 개요. AI가 제안해도 최종 확정은 순수 사용자 입력이라 `source` 필드는 없다.
/// BookOutline/UserMemo와 같은 `content_html`+`content_text` 구조(서식 편집기 컴포넌트 공유).
@Model
public final class ChapterSummary {
    public var id: UUID = UUID()
    public var bookId: Int = 1
    public var chapter: Int = 1
    public var contentHtml: String = ""
    public var contentText: String = ""
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now

    public init(
        id: UUID = UUID(),
        bookId: Int,
        chapter: Int,
        contentHtml: String = "",
        contentText: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.bookId = bookId
        self.chapter = chapter
        self.contentHtml = contentHtml
        self.contentText = contentText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// ⚠️ `chapterRefs`/`linkedMemoIds`는 관계가 아니라 배열 필드로 유지한다(원본 스키마 그대로).
@Model
public final class LectureNote {
    public var id: UUID = UUID()
    public var title: String = ""
    public var chapterRefs: [BibleChapterRef] = []
    public var contentMd: String = ""
    public var linkedMemoIds: [UUID] = []
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now

    public init(
        id: UUID = UUID(),
        title: String,
        chapterRefs: [BibleChapterRef] = [],
        contentMd: String = "",
        linkedMemoIds: [UUID] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.chapterRefs = chapterRefs
        self.contentMd = contentMd
        self.linkedMemoIds = linkedMemoIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
public final class Comparison {
    public var id: UUID = UUID()
    public var title: String = ""
    public var comparedTargets: [String] = []
    public var notesMd: String = ""
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now

    public init(
        id: UUID = UUID(),
        title: String,
        comparedTargets: [String] = [],
        notesMd: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.comparedTargets = comparedTargets
        self.notesMd = notesMd
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// `LectureNote.chapterRefs`가 쓰는 `BibleChapterRef`는 Models/BibleCoordinates.swift에 정의되어 있다
// (다른 모델과 공유하기 위해 별도 파일로 분리).
