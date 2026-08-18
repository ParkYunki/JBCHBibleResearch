import Foundation
import SwiftData

// 근거: bible-research-platform-screens.md 6.1(BookOutline)/6.2(MemoFolder)/6.5(UserMemo)/
// 6.6(ChapterSummary) + review-addendum.md 1.4(BookOutline 충돌 처리) + 13장(새 메모 생성 흐름).
//
// 성경 좌표(book_id/chapter/verse)는 관계가 아니라 원시 Int로 저장한다 — schema.md 2장의
// 결정("번역본 종속적인 verse row가 아니라 성경 좌표 자체를 참조 키로 사용")을 그대로 따른다.
// BibleVerses는 번역본별 SQLite 파일이라 애초에 이 SwiftData/CloudKit 레이어 안에 존재하지
// 않으므로 관계로 연결할 대상 자체가 없다.

/// 6.2 — 메모 분류용 폴더. 메모당 1개만(단일 소속), 중첩 없음(플랫한 목록).
@Model
public final class MemoFolder {
    public var id: UUID = UUID()
    public var name: String = ""
    public var createdAt: Date = Date.now

    // ⚠️ 2026-08-06 실기기 확인: to-many @Relationship도 타입 자체가 Optional이어야
    // CloudKit이 받아들인다([T] = []로는 컴파일은 되지만 런타임에 CoreData 134060으로
    // 실패함). Tags.swift 상단 주석 참고.
    @Relationship(deleteRule: .nullify, inverse: \UserMemo.folder)
    public var memos: [UserMemo]? = []

    public init(id: UUID = UUID(), name: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

/// 6.5 — 서식 있는 사용자 메모. `content_html`(서식) + `content_text`(검색·임베딩용) 이원화.
/// ⚠️ 태그는 더 이상 배열 필드가 아니다 — `MemoTag` 조인을 통해서만 연결된다
/// (6.5 "⚠️ 6.3과의 정합성 수정" 참고).
@Model
public final class UserMemo {
    public var id: UUID = UUID()

    /// 📝 구현 결정: CloudKit은 non-optional 프로퍼티에 리터럴 기본값을 요구한다.
    /// 여기서는 13.1의 "마지막 위치가 없을 때의 고정 기본값"인 창세기 1장(book_id=1,
    /// chapter=1)을 모델 레벨 기본값으로도 사용한다. 단, 13.1에 명시된 "이번 세션 마지막
    /// 위치" 우선 로직은 이 모델 레이어가 아니라 메모 생성 화면(앱 레이어)의 책임이다 —
    /// 이 기본값은 어디까지나 CloudKit 스키마 제약을 만족시키기 위한 자리표시자다.
    public var bookId: Int = 1
    public var chapter: Int = 1
    public var verse: Int?

    // [2026-08-08 추가] 사용자 요청 — "성경구절의 특정 표현에 메모를 넣고 싶음".
    // 전부 옵셔널이라 기존 절 단위 메모(현재 데이터)는 전혀 영향받지 않는다 —
    // nil이면 지금처럼 "절 전체" 메모, 채워지면 "그 표현"에 대한 메모다. 앵커
    // 규칙(오프셋 단위, 자가 치유용 스냅샷)은 `VerseAnnotations.swift` 상단 주석과
    // 완전히 동일하다.
    public var rangeStart: Int?
    public var rangeEnd: Int?
    public var annotationTranslationCode: String?
    public var anchorText: String?

    public var contentHtml: String = ""
    public var contentText: String = ""

    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now

    /// [2026-08-12 신설] 사용자 논의 — "말씀 요약 화면을 벗어났을 때 트리거를
    /// 실행할 수 있는가?" 재인덱싱(`BibleReferenceIndexingService.reindexMemo`)을
    /// 매 자동저장(디바운스)마다가 아니라 화면을 정상적으로 벗어날 때(닫기 버튼/
    /// 사이드바 이동) 한 번만 실행하기로 결정하면서 생긴 필드다. 본문이 바뀌어
    /// 인덱스가 이제 최신이 아니게 된 시점에 `true`로 저장되고(콘텐츠 변경과
    /// 같은 저장에 함께 실려 나간다), 정상 종료로 실제 재인덱싱이 끝나면 다시
    /// `false`로 저장된다. 편집 중 앱이 강제 종료되면 이 값이 `true`인 채로
    /// 남는다 — 그게 정확히 "이 메모는 인덱스가 최신이 아닐 수 있다"는 신호라,
    /// 목록 화면(MemoRowView)이 이 값을 읽어 배지로 보여준다.
    public var pendingIndexRefresh: Bool = false

    /// [2026-08-18 추가] 사용자 요청 — "사이드바 메뉴 밑으로 클로드 앱처럼 기능을
    /// 추가할 것. 고정됨." 다른 필드들과 같은 패턴(기본값 있는 저장 프로퍼티
    /// 추가만으로 SwiftData가 가벼운 마이그레이션을 자동 처리 — `pendingIndexRefresh`
    /// 가 이미 이 방식으로 추가된 전례) — 기존 데이터는 전부 `false`로 시작한다.
    public var isPinned: Bool = false

    // deleteRule은 MemoFolder.memos 쪽(inverse 선언부)에서만 지정한다 — 같은 관계
    // 양쪽에 deleteRule을 중복 지정하지 않는다(단순함 우선, 6.2).
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

/// [2026-08-12 신설] 사용자 요청 — "왼쪽 사이드바 [말씀 요약] 기능, 성경 구절
/// 선택시 확대보기 오른쪽 옆 [말씀 요약]버튼추가 ... 왼쪽 사이드바 [말씀 요약] -
/// 개인 주석과 기능 동일." `UserMemo`와 거의 같은 모양(서식 있는 본문을
/// `contentHtml`(실제로는 RTF, `UserMemo`와 같은 관례)/`contentText`(검색·미리보기용)
/// 이원화로 저장)이지만 의도적으로 별개 모델이다 — 성경 조회 화면에서 구절을
/// 고르고 [말씀 요약]을 누를 때마다("매번 새 글 생성" 방식, 사용자 확인) 그
/// 절에 대한 새 요약 레코드가 계속 쌓이는 저널/묵상노트 성격이라, "절 하나당
/// 하나"로 덮어쓰는 `UserMemo`(개인 묵상)와 근본적으로 다른 데이터 모양이다.
/// 폴더/태그는 이번 요청 범위에 없어 두지 않았다(필요해지면 `UserMemo`의
/// `MemoFolder`/`MemoTag` 패턴을 그대로 가져오면 된다).
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

    /// [2026-08-12 신설] `UserMemo.pendingIndexRefresh`와 완전히 같은 이유 —
    /// 그 프로퍼티 상단 주석 참고.
    public var pendingIndexRefresh: Bool = false

    /// [2026-08-14 신설] 사용자 요청 — "말씀 요약도 개인 묵상처럼 태그를 입력할
    /// 수 있게." `UserMemo.memoTags`와 같은 이유로 관계 자체엔 `@Relationship`을
    /// 붙이지 않는다(deleteRule은 `Tag.summaryTags`/`SummaryTag.summary` 쪽에서만
    /// 지정 — `UserContent.swift`의 `UserMemo.folder` 옆 기존 주석과 같은 원칙).
    public var summaryTags: [SummaryTag]? = []

    /// [2026-08-18 추가] `UserMemo.isPinned`와 같은 이유·같은 패턴.
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

/// 6.1 — 책 단위 개요. 항상 순수 사용자 입력(AI 없음, source 필드를 두지 않는다).
/// ⚠️ 원본 6.1은 `book_id UNIQUE`였으나 addendum 1.1/1.4에 따라 unique 제약을 제거하고,
/// 대신 `conflictingOutlineId`로 사용자 선택형 충돌 해소를 적용한다(Tag처럼 자동 병합하지
/// 않는다 — BookOutline은 자유 텍스트라 두 기기의 내용이 다를 수 있기 때문, addendum 1.4).
@Model
public final class BookOutline {
    public var id: UUID = UUID()
    public var bookId: Int = 1
    public var contentHtml: String = ""
    public var contentText: String = ""
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now

    /// non-nil = 다른 기기와 내용 충돌. S8에 경고 배너 표시(addendum 1.2/1.4).
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

/// 6.6 — 장 단위 개요. 원본 스키마엔 `source[user|ai]`가 있었으나, "AI가 제안해도 최종
/// 확정은 순수 사용자 입력"이라는 확정 결정에 따라 제거했다(6.6). `content_md` →
/// `content_html`+`content_text`로 BookOutline/UserMemo와 통일(서식 편집기 컴포넌트
/// 공유를 위해, 6.8/6.9).
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

/// 원본 schema.md 5장 — 그대로 유지, 6장에서 변경 대상 아님.
/// ⚠️ `chapterRefs`/`linkedMemoIds`는 원본 스키마가 배열 필드로 정의했던 그대로
/// 유지했다(관계로 바꾸는 근거 없는 리팩토링을 하지 않는다는 프로젝트 원칙).
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

/// 원본 schema.md 5장 — 그대로 유지.
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

// `LectureNote.chapterRefs`가 쓰는 `BibleChapterRef`는 Models/BibleCoordinates.swift에
// 정의되어 있다(DocumentAnchor/TimelineEvent 등 다른 모델과 공유하기 위해 별도 파일로 분리).
