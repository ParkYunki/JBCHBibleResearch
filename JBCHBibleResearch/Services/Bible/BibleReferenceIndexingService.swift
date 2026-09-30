//
//  BibleReferenceIndexingService.swift
//  JBCHBibleResearch
//
//  `BibleReferenceExtractor`가 찾아낸 성경 구절 언급을 `VerseMention` 테이블에 채워 넣는다.
//
//  - `reindexMemo`/`reindexWordSummary`/`reindexSermon`/`reindexDocument`: 소스 **하나**를 저장한 직후 호출 —
//    그 소스의 기존 인덱스를 지우고 지금 텍스트로 다시 추출해 넣는다.
//  - `removeMentions(sourceType:sourceId:context:)`: 소스를 삭제할 때 호출 — 그 소스의 인덱스 레코드를 전부 지운다.
//
//  ⚠️ `reindexMemosAndDocuments(context:)`(전체 재스캔)는 코드만 남아 있고 자동 호출되지 않는다. 그래서 저장/삭제
//  이벤트가 한 번도 없었던 기존 메모/문서나 다른 기기에서 CloudKit으로 막 동기화된 메모/문서는 인덱스가 비어 있을
//  수 있다. 완전한 안전망(예: 새 기기 첫 실행 시 전체 백필)이 필요하면 적절한 시점에 이 함수를 호출하면 된다.
//

import Foundation
import SwiftData
import BibleResearchModels

@MainActor
enum BibleReferenceIndexingService {
    static func reindexMemosAndDocuments(context: ModelContext) {
        reindexMemos(context: context)
        reindexDocuments(context: context)
        try? context.save()
    }

    private static func reindexMemos(context: ModelContext) {
        guard let memos = try? context.fetch(FetchDescriptor<UserMemo>()) else { return }
        reindexSources(
            context: context,
            sourceType: .memo,
            items: memos.map { (key: $0.id.uuidString, text: $0.contentText) }
        )
    }

    private static func reindexDocuments(context: ModelContext) {
        guard let allDocuments = try? context.fetch(FetchDescriptor<SourceDocument>()) else { return }
        // ⚠️ IndexStatus는 String rawValue enum이라 #Predicate 등호 비교를 피하고(프로젝트 공통 패턴) 전체를
        // 가져와 Swift에서 거른다. 검수가 끝난 `indexed` 텍스트만 대상으로 한다 — 검수 전 OCR 초안까지
        // 추출하면 검수 중 내용이 바뀔 때 이중 작업이 된다.
        let indexed = allDocuments.filter { $0.indexStatus == .indexed }
        let items: [(key: String, text: String)] = indexed.map { document in
            let lines = (document.documentTexts ?? []).sorted {
                $0.pageNumber != $1.pageNumber ? $0.pageNumber < $1.pageNumber : $0.lineIndex < $1.lineIndex
            }
            let text = lines.map(\.lineText).joined(separator: "\n")
            return (document.id.uuidString, text)
        }
        reindexSources(context: context, sourceType: .document, items: items)
    }

    /// 공통 재계산 — 소스(메모/문서) 하나마다 지금 텍스트로 다시 추출한 결과와 DB에
    /// 이미 있는 결과를 지문(fingerprint) 집합으로 비교해서, 다를 때만 그 소스의
    /// 기존 레코드를 전부 지우고 새로 넣는다(레코드 수가 보통 소스 하나당 한 자릿수라
    /// 부분 diff 대신 통째 교체가 더 단순하고 충분히 저렴하다).
    private static func reindexSources(
        context: ModelContext,
        sourceType: VerseMentionSourceType,
        items: [(key: String, text: String)]
    ) {
        let existing = (try? context.fetch(FetchDescriptor<VerseMention>())) ?? []
        var existingBySource = Dictionary(
            grouping: existing.filter { $0.sourceType == sourceType },
            by: \.sourceId
        )

        for item in items {
            guard !item.text.isEmpty else {
                if let stale = existingBySource.removeValue(forKey: item.key) {
                    for old in stale { context.delete(old) }
                }
                continue
            }
            let matches = BibleReferenceExtractor.extract(from: item.text)
            let existingForSource = existingBySource.removeValue(forKey: item.key) ?? []

            let currentFingerprint = Set(matches.map {
                fingerprint(bookId: $0.bookId, chapter: $0.chapter, verse: $0.verse, searchText: $0.searchText)
            })
            let existingFingerprint = Set(existingForSource.map {
                fingerprint(bookId: $0.bookId, chapter: $0.chapter, verse: $0.verse, searchText: $0.searchText)
            })
            guard currentFingerprint != existingFingerprint else { continue }

            for old in existingForSource { context.delete(old) }
            for match in matches {
                let mention = VerseMention(
                    sourceType: sourceType,
                    sourceId: item.key,
                    bookId: match.bookId,
                    chapter: match.chapter,
                    verse: match.verse,
                    searchText: match.searchText,
                    snippet: BibleReferenceExtractor.snippet(for: match, in: item.text)
                )
                context.insert(mention)
            }
        }

        // 더 이상 존재하지 않는 소스(메모/문서가 그 사이 삭제됨)에 남은 인덱스는
        // 고아 레코드 — 정리한다.
        for orphaned in existingBySource.values.flatMap({ $0 }) {
            context.delete(orphaned)
        }
    }

    private static func fingerprint(bookId: Int, chapter: Int, verse: Int?, searchText: String) -> String {
        "\(bookId)#\(chapter)#\(verse ?? -1)#\(searchText)"
    }

    // MARK: - 이벤트 기반 재계산(소스 하나) — 2026-08-11 추가

    /// 메모 하나를 저장한 직후 호출. 그 메모의 기존 인덱스를 지우고 지금
    /// `contentText`로 다시 추출해 넣는다.
    static func reindexMemo(_ memo: UserMemo, context: ModelContext) {
        reindexSingleSource(
            context: context, sourceType: .memo, sourceId: memo.id.uuidString, text: memo.contentText
        )
    }

    /// 말씀 요약 하나를 저장한 직후 호출 — `reindexMemo`와 같은 동작.
    static func reindexWordSummary(_ summary: VerseSummary, context: ModelContext) {
        reindexSingleSource(
            context: context, sourceType: .wordSummary, sourceId: summary.id.uuidString, text: summary.contentText
        )
    }

    /// 메인 설교문(`Sermon`) 하나를 저장한 직후 호출 — `reindexMemo`와 같은 동작. 회차 사본(`SermonDelivery`)은
    /// 인덱싱하지 않는다.
    static func reindexSermon(_ sermon: Sermon, context: ModelContext) {
        reindexSingleSource(
            context: context, sourceType: .sermon, sourceId: sermon.id.uuidString, text: sermon.contentText
        )
    }

    /// 연구문서 하나가 텍스트를 확보한(처음 `indexStatus == .indexed`가 된) 직후
    /// 호출. 아직 검수 전(초안)이면 인덱스에 남아 있으면 안 되므로 기존 레코드만
    /// 정리하고 새로 추출하지 않는다 — `reindexDocuments`(전체 재스캔)의 "인덱싱
    /// 완료 상태만 대상" 규칙과 동일하다.
    static func reindexDocument(_ document: SourceDocument, context: ModelContext) {
        guard document.indexStatus == .indexed else {
            removeMentions(sourceType: .document, sourceId: document.id.uuidString, context: context)
            return
        }
        let lines = (document.documentTexts ?? []).sorted {
            $0.pageNumber != $1.pageNumber ? $0.pageNumber < $1.pageNumber : $0.lineIndex < $1.lineIndex
        }
        let text = lines.map(\.lineText).joined(separator: "\n")
        reindexSingleSource(context: context, sourceType: .document, sourceId: document.id.uuidString, text: text)
    }

    /// 메모/연구문서를 삭제하기 직전(또는 직후, 순서는 무관 — `sourceId`만 있으면
    /// 된다)에 호출 — 그 소스가 남긴 `VerseMention` 레코드를 전부 지운다.
    static func removeMentions(sourceType: VerseMentionSourceType, sourceId: String, context: ModelContext) {
        // 전체 VerseMention 테이블을 읽지 않도록 `sourceId` predicate로 그 소스의 행만 fetch한다.
        // `sourceType`은 String rawValue enum이라(프로젝트 공통으로 #Predicate 등호 비교를 피함)
        // predicate에 넣지 않고, 좁혀진 결과를 Swift에서 한 번 더 거른다.
        let predicate = #Predicate<VerseMention> { $0.sourceId == sourceId }
        guard let candidates = try? context.fetch(FetchDescriptor<VerseMention>(predicate: predicate)) else { return }
        var didDelete = false
        for mention in candidates where mention.sourceType == sourceType {
            context.delete(mention)
            didDelete = true
        }
        guard didDelete else { return }
        try? context.save()
    }

    /// `reindexMemo`/`reindexDocument`가 공유하는 실제 재계산 — 소스 하나의 기존
    /// 레코드를 전부 지우고, 텍스트가 비어 있지 않으면 다시 추출해 새로 넣는다.
    /// (소스 하나당 레코드가 보통 한 자릿수라, 위 전체 재스캔의 지문 비교 최적화
    /// 없이 그냥 통째로 교체해도 충분히 저렴하다 — 애초에 이 함수는 "그 소스가
    /// 막 저장됨"이 확실한 시점에만 불리므로 매번 다시 쓰는 게 맞다.)
    private static func reindexSingleSource(
        context: ModelContext, sourceType: VerseMentionSourceType, sourceId: String, text: String
    ) {
        // 자동저장마다(디바운스 후) 반복 호출되는 경로라, `sourceId` predicate로 그 소스의 행만 fetch한다.
        let predicate = #Predicate<VerseMention> { $0.sourceId == sourceId }
        guard let candidates = try? context.fetch(FetchDescriptor<VerseMention>(predicate: predicate)) else { return }
        for old in candidates where old.sourceType == sourceType {
            context.delete(old)
        }
        if !text.isEmpty {
            let matches = BibleReferenceExtractor.extract(from: text)
            for match in matches {
                let mention = VerseMention(
                    sourceType: sourceType, sourceId: sourceId, bookId: match.bookId, chapter: match.chapter,
                    verse: match.verse, searchText: match.searchText,
                    snippet: BibleReferenceExtractor.snippet(for: match, in: text)
                )
                context.insert(mention)
            }
        }
        try? context.save()
    }
}
