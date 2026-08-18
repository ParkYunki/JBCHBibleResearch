import Foundation
import SwiftData

// [2026-08-11 신설] 사용자 요청 — "메모/연구문서 안에 성경 장절로 되어 있는 모든
// 성경 구절을 추출하여 DB에 저장 → 해당 구절을 클릭하면 확인할 수 있도록." +
// "구절 선택 후 오른쪽 사이드바에 [관련 내용] 추가 — 그 구절이 들어간 메모/연구문서
// 내용 일부를 보여주고, 클릭하면 그 위치로 이동."
//
// ⚠️ [설계 결정] 원본 스펙(schema.md 2장)의 `KeywordOccurrence`(ReferenceIndex.swift)는
// "성경 본문 안의 키워드 발생"을 뜻하는 완전히 다른 방향의 모델이라(성경 → 태그),
// 이번 요청(메모/문서 텍스트 → 성경구절)에 재사용할 수 없었다 — 새 모델을 추가했다.
// `DocumentAnchor`(Documents.swift, `anchorType: .verseRef`)도 검토했지만, 그건
// "문서 안의 정확한 위치(페이지/줄/오프셋)"까지 표현하도록 설계된 좀 더 무거운
// 모델이고 `UserMemo`에는 붙일 수 없다(그 모델의 `sourceDocument` 관계가 필수적
// 구조) — 메모/문서 양쪽에 공통으로 붙일 수 있는 가벼운 모델을 새로 만드는 편이
// 기존 모델을 억지로 확장하는 것보다 안전하다고 판단했다.
//
// `searchText`(사용자가 실제로 쓴 원문 표현, 예: "요 3:16")와 `bookId`/`chapter`/
// `verse`(구조화된 좌표)를 분리해서 저장한다 — 사용자 요청의 "검색어로 삼을
// 원문텍스트로 된 성경구절과, 성경 구절의 seq정보로 별도 저장" 부분을 그대로
// 반영한다. `searchText`는 문서 안에서 그 위치를 다시 찾을 때(PDF 검색 등) 검색어로
// 쓰고, `bookId`/`chapter`/`verse`는 성경 조회 화면에서 "이 절을 언급한 메모/문서"를
// 구조적으로 찾을 때 쓴다.

public enum VerseMentionSourceType: String, Codable, Sendable, CaseIterable {
    case memo
    case document
    /// [2026-08-12 추가] 사용자 요청 — "[관련 말씀 요약]... 개인 묵상, 연구문서와
    /// 동일한 프로세스로 저장/수정/삭제될 때 말씀구절 추출하여 저장하도록."
    /// `VerseSummary`(말씀 요약) 전용 소스 타입 — `.memo`(UserMemo)와 데이터
    /// 모양은 비슷하지만 별개 모델이라 소스 타입도 구분해야 한다.
    case wordSummary
}

/// 메모(`UserMemo`)/연구문서(`SourceDocument`) 본문 안에서 정규식으로 추출한 성경
/// 구절 참조 1건. `BibleReferenceIndexingService`(앱 레이어)가 채워 넣고, 그 메모/
/// 문서의 본문이 바뀔 때마다 통째로 다시 계산해 갱신한다(`EmbeddingIndexingService`와
/// 같은 "전체 재스캔, 바뀐 것만 갱신" 원칙 — 이 프로젝트가 이미 채택한 방식).
@Model
public final class VerseMention {
    public var id: UUID = UUID()
    public var sourceTypeRaw: String = VerseMentionSourceType.memo.rawValue
    /// `UserMemo.id`/`SourceDocument.id`의 `uuidString` — `EmbeddingChunk.sourceId`와
    /// 같은 패턴(관계가 아니라 원시 문자열 ID)이다. 관계로 직접 연결하지 않은 이유도
    /// 같다: 메모/문서 어느 쪽이든 될 수 있는 "다형적" 출처를 표현해야 하는데, 이
    /// 패키지의 기존 관례(`EmbeddingChunk`)가 이미 이 방식을 쓰고 있어 새 패턴을
    /// 만들지 않았다.
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
