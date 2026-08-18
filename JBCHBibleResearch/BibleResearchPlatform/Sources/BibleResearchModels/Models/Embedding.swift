import Foundation
import SwiftData

// 근거: bible-research-platform-schema.md 4장(Vector DB / RAG) + 13.5(EmbeddingChunk
// 재계산 타이밍 — source_type=memo, source_id=memo.id 확인).
// 검색은 sqlite-vec 등 확장 없이 Swift + Accelerate(vDSP)로 brute-force 코사인
// 유사도를 계산한다(schema.md 0장/4장 확정). 이 모델 자체는 그 계산 알고리즘과 무관하게
// 벡터를 저장하는 SwiftData 엔티티일 뿐이다.

public enum EmbeddingSourceType: String, Codable, Sendable, CaseIterable {
    case verse, document, memo
}

@Model
public final class EmbeddingChunk {
    public var id: UUID = UUID()
    public var sourceType: EmbeddingSourceType = EmbeddingSourceType.memo

    /// `document`/`memo`: 해당 `SourceDocument`/`UserMemo`의 `id`(UUID 문자열).
    /// `verse`: 아래 `verseRef`를 대신 사용하므로 이 필드는 빈 문자열로 둔다.
    public var sourceId: String = ""

    /// `sourceType == .verse`일 때만 사용. schema.md 2장 원칙대로 좌표를 값으로 저장.
    public var verseRef: BibleVerseRef?

    /// 📝 구현 결정(원본 문서에 없던 세부사항): `sourceType == .verse`일 때, 어떤
    /// 번역본의 본문을 임베딩했는지가 원본 스키마에 명시돼 있지 않다. 같은 구절이라도
    /// 번역본마다 문장이 달라 임베딩 벡터도 달라지므로, 이 필드 없이는 검색 결과가
    /// 어느 번역본에서 나온 유사도인지 구분할 수 없다. `TranslationRegistry.code`를
    /// 참조하는 문자열로 추가했다 — 관계로 만들지 않은 이유는 상단 원칙(성경 관련
    /// 참조는 이 레이어에서 항상 값으로 저장)과의 일관성 때문이다. ⚠️ 확인 필요:
    /// 사용자 확정 전까지는 가정으로 남겨둔다.
    public var translationCode: String?

    public var chunkText: String = ""
    public var chunkIndex: Int = 0
    public var embeddingVector: Data = Data()
    public var embeddingModel: String = ""
    public var createdAt: Date = Date.now

    public init(
        id: UUID = UUID(),
        sourceType: EmbeddingSourceType,
        sourceId: String = "",
        verseRef: BibleVerseRef? = nil,
        translationCode: String? = nil,
        chunkText: String,
        chunkIndex: Int,
        embeddingVector: Data,
        embeddingModel: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.sourceType = sourceType
        self.sourceId = sourceId
        self.verseRef = verseRef
        self.translationCode = translationCode
        self.chunkText = chunkText
        self.chunkIndex = chunkIndex
        self.embeddingVector = embeddingVector
        self.embeddingModel = embeddingModel
        self.createdAt = createdAt
    }
}
