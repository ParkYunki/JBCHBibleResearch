//
//  OCRReviewQueueView.swift
//  JBCHBibleResearch
//
//  S7(OCR 검수) — screens.md 14.3 "검수 화면 진입(대기열 방식 — '저장 후 다음'으로
//  순차 처리)"를 실제로 구현한 얇은 컨테이너. `DocumentsHomeView`가 검수 대기 중인
//  문서 배열(탭한 문서가 맨 앞에 오도록 회전된 상태)을 시트로 건네주면, 이 뷰는
//  그 배열을 인덱스로 훑으면서 `OCRReviewView`를 계속 재사용한다 — 저장/폐기가
//  성공할 때마다 다음 인덱스로 넘어가고, 마지막 문서까지 끝나면 시트를 닫는다.
//
//  `.id(document.persistentModelID)`로 다음 문서의 `OCRReviewView`를 완전히 새
//  뷰로 취급하게 만든다 — 안 그러면 SwiftUI가 같은 뷰 정체성으로 보고 내부
//  `@State`(viewModel, loadedImage 등)를 이전 문서 것 그대로 재사용해버릴 수 있다.
//

import SwiftUI
import SwiftData
import BibleResearchModels

struct OCRReviewQueueView: View {
    @Environment(\.dismiss) private var dismiss
    let queue: [SourceDocument]

    @State private var index = 0

    var body: some View {
        NavigationStack {
            if index < queue.count {
                OCRReviewView(
                    document: queue[index],
                    onAdvance: advance,
                    queuePosition: (index: index, count: queue.count)
                )
                .id(queue[index].persistentModelID)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("닫기") { dismiss() }
                    }
                }
            } else {
                // 큐가 비어 있는 상태로 열렸거나(이론상 DocumentsHomeView가 막아 줌)
                // 방금 마지막 문서를 처리해 dismiss()가 아직 반영되기 전 찰나에만
                // 보일 수 있는 화면 — 실제로 오래 보이는 일은 없어야 한다.
                ProgressView()
            }
        }
    }

    /// 다음 인덱스로 넘어가거나(더 남은 문서가 있으면), 없으면 시트를 닫는다.
    private func advance() {
        if index + 1 < queue.count {
            index += 1
        } else {
            dismiss()
        }
    }
}
