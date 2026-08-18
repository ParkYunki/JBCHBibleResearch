//
//  EmbeddingIndexingService.swift
//  JBCHBibleResearch
//
//  S11 의미검색이 실제로 결과를 내려면 `EmbeddingChunk` 행이 미리 채워져 있어야
//  한다 — 이 타입이 그 색인(생성/갱신)을 담당한다.
//
//  ⚠️ [13.5 대비 단순화] 원문서(13.5)는 "메모 저장 시점엔 재인덱싱 필요로 표시만
//  해두고, 앱 유휴 시점에 백그라운드에서 비동기로 재계산"을 권장했다. 이 구현은
//  그 "더티 플래그 + 유휴 스케줄러"를 새로 만드는 대신, **S11 화면에 진입할 때마다
//  메모/연구문서 전체를 스캔해 변경된 것만 재계산**하는 방식으로 단순화했다 —
//  메모/문서는 실제 규모가 수백~수천 건 수준이라 매번 전체 스캔해도 "바뀐 것만
//  실제로 임베딩 계산"하면 비용이 크지 않다고 판단했다(변경분만 계산하는 로직은
//  아래 upsertChunk의 chunkText 비교로 구현). 앱 전역 유휴 감지·백그라운드 스케줄링
//  인프라 자체가 없는 상태에서 그걸 새로 만드는 건 이번 라운드 범위를 벗어난다고
//  봤다 — 오버엔지니어링 방지 원칙.
//
//  ⚠️ [성경 전체는 별도 취급] 성경은 규모가 다르다(66권 1,189장). 화면 진입마다
//  자동으로 스캔하면 첫 진입 시 UI가 오래 멈출 위험이 커서, **사용자가 명시적으로
//  버튼을 눌러야만** 시작되는 별도 함수(`reindexBundledBibleChapters`)로 분리했다.
//  schema.md 4장이 스스로 "수만~10만 청크 규모에서 검색 시 UI가 멈추지 않도록
//  반드시 로딩 상태와 비동기 처리가 필요"라고 경고한 지점과 같은 문제라, 진행률
//  콜백 + 취소 가능한 Task + 주기적 `Task.yield()`로 대응했다.
//
//  ⚠️ [청크 단위 결정 — 원본에 없던 구현 결정] EmbeddingChunk.verseRef는 절
//  단위 좌표 하나만 표현할 수 있지만, 절 단위로 1,189장 × 평균 26절 ≈ 31,000개를
//  전부 임베딩하면 이번 세션엔 규모/성능을 전혀 검증할 수 없다. 그래서 **장 단위로
//  청크를 묶었다**(장 전체 절을 이어붙인 텍스트 하나 = 청크 하나) — verseRef는
//  "이 장의 첫 절"을 가리키는 대표 좌표로 쓰고, `verse` 필드에 실제로 존재하지 않는
//  0을 센티널 값으로 넣어 "장 전체"라는 의미를 표시했다(0은 유효한 절 번호가 될 수
//  없어 나중에 진짜 절 단위 청크를 추가해도 충돌하지 않는다). 검색 결과는 정확한
//  절이 아니라 "그 절을 포함할 가능성이 있는 장"을 가리키게 된다 — 절 단위 정밀도가
//  필요해지면 청크를 절 단위로 재설계해야 한다(다음 단계 후보로 남긴다).
//

import Foundation
import SwiftData
import BibleResearchModels

@MainActor
enum EmbeddingIndexingService {
    /// `EmbeddingChunk.embeddingModel`에 기록하는 식별자. 나중에 임베딩 생성 방식을
    /// 바꾸면 이 문자열도 바꿔야 한다 — upsertChunk가 이 값이 다르면 텍스트가 같아도
    /// 무조건 재계산한다(서로 다른 모델의 벡터가 같은 공간에 섞이면 유사도 비교
    /// 자체가 무의미해지므로).
    static let embeddingModelIdentifier = "NLContextualEmbedding-ko-mean-pool-v1"

    // MARK: - 메모 + 연구문서(자동, 화면 진입 시)

    static func reindexMemosAndDocuments(context: ModelContext) async {
        guard EmbeddingService.shared.availability == .available else { return }
        await reindexMemos(context: context)
        await reindexDocuments(context: context)
        try? context.save()
    }

    private static func reindexMemos(context: ModelContext) async {
        guard let memos = try? context.fetch(FetchDescriptor<UserMemo>()) else { return }
        var cache = existingChunks(context: context, sourceType: .memo) { "\($0.sourceId)" }
        for memo in memos {
            guard !memo.contentText.isEmpty else { continue }
            upsertChunk(
                context: context,
                identityKey: memo.id.uuidString,
                cache: &cache,
                sourceType: .memo,
                sourceId: memo.id.uuidString,
                verseRef: nil,
                translationCode: nil,
                chunkIndex: 0,
                text: memo.contentText
            )
            if Task.isCancelled { return }
        }
    }

    private static func reindexDocuments(context: ModelContext) async {
        guard let allDocuments = try? context.fetch(FetchDescriptor<SourceDocument>()) else { return }
        // ⚠️ IndexStatus는 String rawValue enum이라 #Predicate 등호 비교가 이 SwiftData
        // 버전에서 컴파일/동작하는지 확신할 수 없어(다른 곳에서도 같은 이유로 회피한
        // 패턴), 안전하게 전체를 가져와 Swift에서 걸렀다.
        let indexedDocuments = allDocuments.filter { $0.indexStatus == .indexed }
        var cache = existingChunks(context: context, sourceType: .document) { "\($0.sourceId)#\($0.chunkIndex)" }
        for document in indexedDocuments {
            let lines = document.documentTexts ?? []
            guard !lines.isEmpty else { continue }
            let byPage = Dictionary(grouping: lines, by: \.pageNumber)
            for (page, pageLines) in byPage {
                let text = pageLines.sorted { $0.lineIndex < $1.lineIndex }
                    .map(\.lineText).joined(separator: "\n")
                guard !text.isEmpty else { continue }
                upsertChunk(
                    context: context,
                    identityKey: "\(document.id.uuidString)#\(page)",
                    cache: &cache,
                    sourceType: .document,
                    sourceId: document.id.uuidString,
                    verseRef: nil,
                    translationCode: nil,
                    chunkIndex: page,
                    text: text
                )
                if Task.isCancelled { return }
            }
        }
    }

    // MARK: - 성경(수동, 장 단위)

    /// 진행률: (완료한 장 수, 전체 장 수). 취소 가능(Task.cancel()로 중단하면 그때까지
    /// 처리한 만큼만 저장된 채로 멈춘다 — 다음에 다시 호출하면 이미 끝난 장은
    /// chunkText 비교로 건너뛰고 이어서 진행된다).
    static func reindexBundledBibleChapters(
        context: ModelContext,
        store: BibleReferenceStore,
        books: [Book],
        translationCode: String,
        onProgress: @escaping (Int, Int) -> Void
    ) async {
        guard EmbeddingService.shared.availability == .available else { return }
        var cache = existingChunks(context: context, sourceType: .verse) {
            guard let ref = $0.verseRef else { return "" }
            return "\(ref.bookId)#\(ref.chapter)#\($0.translationCode ?? "")"
        }

        let totalChapters = books.reduce(0) { $0 + $1.chapterCount }
        var done = 0
        for book in books {
            guard book.chapterCount > 0 else { continue }
            for chapter in 1...book.chapterCount {
                if Task.isCancelled { return }
                defer {
                    done += 1
                    onProgress(done, totalChapters)
                }
                guard let verses = try? store.verses(
                    bookId: book.bookId, chapter: chapter,
                    versionCode: store.hasVersionCodeColumn ? translationCode : nil
                ), !verses.isEmpty else { continue }
                let text = verses.map(\.content).joined(separator: " ")
                upsertChunk(
                    context: context,
                    identityKey: "\(book.bookId)#\(chapter)#\(translationCode)",
                    cache: &cache,
                    sourceType: .verse,
                    sourceId: "",
                    verseRef: BibleVerseRef(bookId: book.bookId, chapter: chapter, verse: 0),
                    translationCode: translationCode,
                    chunkIndex: 0,
                    text: text
                )
                // MainActor 위에서 도는 긴 루프라 주기적으로 양보하지 않으면 UI가
                // 멈춘 것처럼 보일 수 있다.
                if done % 10 == 0 {
                    try? context.save()
                    await Task.yield()
                }
            }
        }
        try? context.save()
    }

    // MARK: - 공통

    private static func existingChunks(
        context: ModelContext,
        sourceType: EmbeddingSourceType,
        identityKey: (EmbeddingChunk) -> String
    ) -> [String: EmbeddingChunk] {
        guard let all = try? context.fetch(FetchDescriptor<EmbeddingChunk>()) else { return [:] }
        let filtered = all.filter { $0.sourceType == sourceType }
        var result: [String: EmbeddingChunk] = [:]
        for chunk in filtered {
            result[identityKey(chunk)] = chunk
        }
        return result
    }

    private static func upsertChunk(
        context: ModelContext,
        identityKey: String,
        cache: inout [String: EmbeddingChunk],
        sourceType: EmbeddingSourceType,
        sourceId: String,
        verseRef: BibleVerseRef?,
        translationCode: String?,
        chunkIndex: Int,
        text: String
    ) {
        guard !text.isEmpty else { return }
        if let existing = cache[identityKey],
           existing.chunkText == text,
           existing.embeddingModel == embeddingModelIdentifier {
            return // 이미 같은 모델로 만든 최신 벡터.
        }
        guard let vector = EmbeddingService.shared.embed(text) else { return }
        if let existing = cache[identityKey] {
            existing.chunkText = text
            existing.embeddingVector = vector.asData
            existing.embeddingModel = embeddingModelIdentifier
            existing.createdAt = .now
        } else {
            let chunk = EmbeddingChunk(
                sourceType: sourceType,
                sourceId: sourceId,
                verseRef: verseRef,
                translationCode: translationCode,
                chunkText: text,
                chunkIndex: chunkIndex,
                embeddingVector: vector.asData,
                embeddingModel: embeddingModelIdentifier
            )
            context.insert(chunk)
            cache[identityKey] = chunk
        }
    }
}
