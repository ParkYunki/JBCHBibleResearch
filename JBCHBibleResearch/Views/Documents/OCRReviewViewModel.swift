//
//  OCRReviewViewModel.swift
//  JBCHBibleResearch
//
//  S7(OCR 검수) 상태/데이터 접근. screens.md 3장 "OCR 검수(S7, 핵심 플로우)" +
//  14.3(이미지 경로, 검수 필수) 근거.
//
//  ⚠️ [단순화, 확인 필요] 14.3은 "S7 검수 화면 진입(대기열 방식 — '저장 후 다음'으로
//  순차 처리)"라고 적었지만, 이 구현은 S5 문서 목록에서 검수 대기 중인 문서를 하나씩
//  탭해서 들어가는 방식이다(DocumentsHomeView.swift의 NavigationLink 참고) — 별도의
//  전용 "검수 대기열" 브라우저 화면은 만들지 않았다. 여러 건이 검수 대기 중이면
//  목록에서 "검수 대기" 배지가 달린 다음 문서를 다시 탭하면 되므로 기능적으로는
//  동등하지만, "저장 후 다음"처럼 같은 화면 안에서 곧장 다음 항목으로 넘어가는
//  전용 UX는 아니다.
//

import Foundation
import SwiftData
import Observation
import BibleResearchModels

@MainActor
@Observable
final class OCRReviewViewModel {
    let document: SourceDocument
    private(set) var ocrResult: OCRResult?
    var editedText: String = ""
    var lastErrorDescription: String?
    private(set) var isRetrying = false
    /// [저장]을 눌러 성공적으로 반영되면 true — 화면이 이 값을 보고 목록으로 돌아간다.
    private(set) var didSave = false

    private let modelContext: ModelContext

    init(document: SourceDocument, modelContext: ModelContext) {
        self.document = document
        self.modelContext = modelContext
    }

    func onAppear() {
        ocrResult = (document.ocrResults ?? []).first { $0.status == .draft }
        editedText = ocrResult?.rawText ?? ""
    }

    /// [저장] — 14.3: `OCRResult.status → user_reviewed`, `DocumentText` 동급 레코드로
    /// 반영, `index_status = indexed`. 저장을 눌러야만 반영된다(자동 저장 없음, 요구사항
    /// 그대로).
    func save() {
        guard let ocrResult else { return }
        ocrResult.rawText = editedText
        ocrResult.status = .userReviewed

        // 검수 확정된 텍스트를 줄 단위 DocumentText로도 반영해서, S6 "추출 텍스트"
        // 탭/향후 의미검색 파이프라인이 OCR 결과도 hwp/pdf와 동일하게 다룰 수 있게
        // 한다(14.4 "텍스트 확보 후 공통 단계").
        let lines = editedText.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            let record = DocumentText(pageNumber: 0, lineIndex: index, lineText: line, sourceDocument: document)
            modelContext.insert(record)
        }
        document.indexStatus = .indexed
        // [2026-09-05 추가] 사용자 요청 — "연구문서 combinedText 반복 재생성
        // 문제를 캐싱 필드로 해결." `documentTexts`를 직접 수정하는 두 번째
        // 지점(`DocumentTextExtractionService.extract`가 첫 번째) — 여기서도
        // 캐시를 함께 갱신해야 어긋나지 않는다(`SourceDocument.cachedCombinedText`
        // 선언부 주석 참고).
        document.rebuildCachedCombinedText()
        // [2026-09-05 추가] `DocumentTextExtractionService.extract(for:context:)`의
        // 같은 훅과 동일한 이유 — 캐시를 갱신하는 두 지점 모두에서 FTS 인덱스도
        // 함께 최신화해야 어긋나지 않는다.
        UserContentSearchIndexLocation.upsert(
            category: .document, sourceId: document.id.uuidString, content: document.cachedCombinedText
        )

        do {
            try modelContext.save()
            didSave = true
            // [2026-08-11 추가] 사용자 요청 — "연구문서를 등록/수정할 때마다 관련
            // 성경구절 인덱스 재계산." OCR 검수 확정도 "문서 텍스트가 처음
            // indexed가 되는" 저장 지점이라 동일하게 호출한다.
            BibleReferenceIndexingService.reindexDocument(document, context: modelContext)
        } catch {
            lastErrorDescription = "저장 실패: \(error.localizedDescription)"
        }
    }

    /// [재시도] — 기존 draft 결과를 버리고 OCR을 다시 실행한다.
    func retry() async {
        isRetrying = true
        if let ocrResult {
            modelContext.delete(ocrResult)
            self.ocrResult = nil
            try? modelContext.save()
        }
        await DocumentTextExtractionService.extract(for: document, context: modelContext)
        onAppear()
        isRetrying = false
    }

    /// [폐기] — ⚠️ 스펙에 "폐기"가 OCR 결과만 지우는지 SourceDocument 전체(이미지
    /// 원본 참조 포함)를 지우는지 명시돼 있지 않다. 텍스트 추출을 포기한 이미지를
    /// 목록에 남겨 둬도 쓸모가 적다고 판단해 이 구현은 SourceDocument 전체를
    /// 삭제한다 — 제품 의도가 "이미지는 남기고 결과만 지운다"라면 바꿔야 한다.
    func discard() {
        // [2026-08-11 추가] 사용자 요청 — "삭제했을 때는 그 관련내용도 다 삭제."
        BibleReferenceIndexingService.removeMentions(
            sourceType: .document, sourceId: document.id.uuidString, context: modelContext
        )
        modelContext.delete(document)
        try? modelContext.save()
        didSave = true // 목록으로 돌아가는 트리거를 재사용.
    }
}
