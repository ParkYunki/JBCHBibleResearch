//
//  BibleReferenceIndexingService.swift
//  JBCHBibleResearch
//
//  [2026-08-11 신설] `BibleReferenceExtractor`가 찾아낸 성경 구절 언급을 `VerseMention`
//  테이블에 채워 넣는다.
//
//  [2026-08-11 수정] 사용자 질문 — "메모를 등록할 때마다 재추출하는가, 아니면
//  초기작업을 임의로 한 것인가?"에 답하며 실제 트리거를 다시 확인했다. 원래는
//  `EmbeddingIndexingService.swift`가 쓰는 원칙(더티 플래그 스케줄러 대신, **성경
//  조회(S1) 화면에 진입할 때마다** 메모/연구문서 전체를 스캔해 바뀐 것만 다시
//  계산)을 그대로 따랐었는데, 사용자가 "화면 진입 시점이 아니라 메모/연구문서를
//  등록·수정할 때마다, 삭제하면 관련 인덱스도 같이 지워지도록" 바꿔 달라고
//  요청해 트리거 방식 자체를 바꿨다.
//
//  이제 이 파일은 두 층으로 나뉜다:
//  - `reindexMemo(_:context:)`/`reindexDocument(_:context:)`: 메모/문서 **하나**를
//    저장한 직후 호출 — 그 소스의 기존 인덱스를 지우고 지금 텍스트로 다시 추출해
//    넣는다. 실제 호출부는 `MemoDetailView`(저장 성공 시), `MemoHomeView`(새 메모
//    생성), `BibleReadingViewModel.createPhraseMemo`(구간 메모 생성),
//    `DocumentTextExtractionService`/`OCRReviewViewModel`(문서 텍스트가 처음
//    `indexed` 상태가 되는 시점) — 모두 그 저장 로직 바로 다음 줄에서 부른다.
//  - `removeMentions(sourceType:sourceId:context:)`: 메모/문서를 삭제할 때 호출 —
//    그 소스의 인덱스 레코드를 전부 지운다. 호출부는 `MemoHomeView.delete`/
//    `deleteMemos`, `MemoDetailView`의 "빈 메모 자동 정리"(`AutosaveController.
//    deleteIfEmpty`), `DocumentsViewModel.delete`, `OCRReviewViewModel.discard`.
//
//  ⚠️ [기존 전체 재스캔 함수 보존, 더 이상 자동 호출되지 않음] 아래
//  `reindexMemosAndDocuments(context:)`(전체 재스캔)는 코드 자체는 남겨 뒀지만
//  더 이상 어디서도 자동으로 호출하지 않는다(`BibleReadingViewModel.onAppear()`의
//  호출을 제거했다). 그래서 이 기능이 나오기 전부터 있었지만 그 뒤로 한 번도
//  수정되지 않은 메모/문서, 또는 다른 기기에서 CloudKit으로 막 동기화돼 들어와
//  이 기기에서 아직 한 번도 저장/삭제 이벤트가 발생하지 않은 메모/문서는 인덱스가
//  비어 있을 수 있다 — 이번 세션 동안 실제로 만들어진 데이터는 이미 이전
//  라운드의 화면 진입 재스캔으로 인덱싱이 끝난 상태라 당장 문제는 없지만, 완전한
//  안전망이 필요하면(예: 새 기기에서 처음 실행할 때 한 번 전체 백필) 이 함수를
//  적절한 시점에 다시 호출하는 지점을 추가하면 된다 — 지금은 사용자가 명시적으로
//  요청한 범위(등록/수정/삭제 이벤트 기반)만 구현했다.
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
        // ⚠️ IndexStatus는 String rawValue enum이라 #Predicate 등호 비교를 이 프로젝트가
        // 다른 곳(EmbeddingIndexingService 등)에서도 회피해 온 패턴 그대로, 전체를
        // 가져와 Swift에서 거른다. "인덱싱 완료"(검수 끝난 텍스트) 상태만 대상으로
        // 한다 — 아직 검수 전인 OCR 초안(draft) 텍스트까지 성경구절을 추출하면
        // 나중에 검수 중 내용이 바뀔 때 다시 계산해야 해서 이중 작업이 된다.
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

    /// [2026-08-12 추가] 사용자 요청 — "[관련 말씀 요약]... 개인 묵상, 연구문서와
    /// 동일한 프로세스로 저장/수정/삭제될 때 말씀구절 추출하여 저장하도록."
    /// `reindexMemo`와 완전히 같은 모양 — 말씀 요약 하나를 저장한 직후 호출한다.
    static func reindexWordSummary(_ summary: VerseSummary, context: ModelContext) {
        reindexSingleSource(
            context: context, sourceType: .wordSummary, sourceId: summary.id.uuidString, text: summary.contentText
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
        // [2026-08-12 수정] 사용자 질문 — "수정될 때마다 문서 텍스트를 읽어들여서
        // 관련 말씀구절을 추출하여 DB에 저장이 되는가? ... 매우 비효율적이므로
        // 대체 안을 제안." 실측 확인 결과: 저장 트리거 자체는 이미 디바운스돼
        // 있지만(`AutosaveController.scheduleSave` — 타이핑 멈추고 약 1.5초 뒤에만
        // 실제 저장), 그 매 저장마다 이 함수와 `reindexSingleSource`가 "앱 전체
        // VerseMention 테이블 전부"를 fetch한 뒤 Swift에서 `sourceId`로 걸러내고
        // 있었다 — 메모/문서가 많아질수록 정작 손댈 필요 없는 다른 소스의 레코드까지
        // 매번 통째로 읽어 오는 구조였다(정말 비효율적인 부분은 여기였다). 고친
        // 내용: `sourceId`(String, 평범한 저장 프로퍼티) 하나로 `#Predicate`를 걸어
        // 그 소스에 해당하는 행만 fetch한다 — 동작(트리거 시점, 결과)은 완전히
        // 동일하고 비용만 "테이블 전체"에서 "이 소스 하나(보통 한 자릿수 행)"로
        // 줄어든다. `sourceType`은 `VerseMentionSourceType`이 String rawValue enum
        // 이라(이 프로젝트가 다른 곳에서도 이런 타입의 #Predicate 등호 비교를
        // 회피해 온 전례가 있어) predicate에 넣지 않고, `sourceId`로 좁힌 결과를
        // Swift에서 한 번 더 `sourceType`으로 확인한다(대부분 이미 1건 이하라
        // 비용이 사실상 없다).
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
        // [2026-08-12 수정] `removeMentions` 상단 주석 참고 — 여기가 실제로 매
        // 자동저장마다(디바운스 후) 반복 호출되는 경로라, 전체 테이블을 읽던
        // 이전 버전이 그 "비효율" 지적의 핵심이었다. `sourceId` predicate로 좁힌다.
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
