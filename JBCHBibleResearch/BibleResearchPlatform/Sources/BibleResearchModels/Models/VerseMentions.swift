import Foundation
import SwiftData

// 메모/연구문서 본문에서 추출한 성경구절 언급(`VerseMention`) — 구절을 클릭해 확인하고, 성경 조회에서
// "이 구절이 들어간 메모/문서" 목록(관련 내용)을 보여주는 데 쓴다.
//
// ⚠️ `KeywordOccurrence`(ReferenceIndex.swift)는 성경 → 태그 방향이라 재사용할 수 없고, `DocumentAnchor`
// (`anchorType: .verseRef`)는 문서 내 정확한 위치까지 표현하는 무거운 모델이며 `UserMemo`에는 붙일 수 없다
// (`sourceDocument` 관계가 필수 구조). 그래서 메모/문서 양쪽에 붙일 수 있는 가벼운 별도 모델을 둔다.
//
// `searchText`(사용자가 쓴 원문 표현, 예: "요 3:16")와 `bookId`/`chapter`/`verse`(구조화된 좌표)를 분리해 저장한다.
// `searchText`는 문서 안에서 그 위치를 다시 찾을 때(PDF 검색 등)의 검색어, 좌표는 성경 조회 화면에서
// "이 절을 언급한 메모/문서"를 구조적으로 찾을 때 쓴다.

public enum VerseMentionSourceType: String, Codable, Sendable, CaseIterable {
    case memo
    case document
    /// `VerseSummary`(말씀 요약) 전용 — `UserMemo`와 별개 모델이라 소스 타입도 구분한다.
    case wordSummary
    /// `Sermon`(메인 설교문) 본문에서 추출한 언급(`BibleReferenceIndexingService.reindexSermon` 참고).
    /// 회차 사본(`SermonDelivery`)은 대상이 아니며 메인 설교문 기준으로만 다룬다.
    case sermon
}

/// 메모/연구문서 등 본문 안에서 정규식으로 추출한 성경 구절 참조 1건. `BibleReferenceIndexingService`(앱 레이어)가
/// 채우며, 본문이 바뀔 때마다 통째로 다시 계산해 갱신한다("전체 재스캔, 바뀐 것만 갱신" 원칙).
@Model
public final class VerseMention {
    public var id: UUID = UUID()
    public var sourceTypeRaw: String = VerseMentionSourceType.memo.rawValue
    /// `UserMemo.id`/`SourceDocument.id`의 `uuidString`. 메모/문서 등 "다형적" 출처를 표현해야 해서 관계 대신
    /// 원시 문자열 ID를 쓴다(`EmbeddingChunk.sourceId`와 같은 패턴).
    public var sourceId: String = ""
    public var bookId: Int = 1
    public var chapter: Int = 1
    public var verse: Int?
    /// 원문에서 실제로 매칭된 표현 그대로(예: "요한복음 3:16", "창 1장 1절") — 검색어로
    /// 쓴다.
    public var searchText: String = ""
    /// 미리보기용 주변 문맥(~3줄). 사이드바 "관련 내용" 목록에 그대로 보여준다.
    public var snippet: String = ""
    public var createdAt: Date = Date.now

    public var sourceType: VerseMentionSourceType {
        get { VerseMentionSourceType(rawValue: sourceTypeRaw) ?? .memo }
        set { sourceTypeRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        sourceType: VerseMentionSourceType,
        sourceId: String,
        bookId: Int,
        chapter: Int,
        verse: Int? = nil,
        searchText: String,
        snippet: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.sourceTypeRaw = sourceType.rawValue
        self.sourceId = sourceId
        self.bookId = bookId
        self.chapter = chapter
        self.verse = verse
        self.searchText = searchText
        self.snippet = snippet
        self.createdAt = createdAt
    }
}
