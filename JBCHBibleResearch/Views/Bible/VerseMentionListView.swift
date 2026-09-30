//
//  VerseMentionListView.swift
//  JBCHBibleResearch
//
//  "관련 내용"(이 구절을 언급하는 메모/연구문서/말씀 요약/설교) 목록 뷰.
//  확대보기(VerseZoomView)의 팝오버와 오른쪽 사이드바(ChapterRelatedContentPanel)가 공유한다.
//  표시만 담당하며, 항목 선택 시 무엇을 열지는 호출부가 `onSelect` 클로저로 결정한다.
//

import SwiftUI
import BibleResearchModels

struct VerseMentionListView: View {
    let mentions: [VerseMention]
    let onSelect: (VerseMention) -> Void

    var body: some View {
        List(mentions) { mention in
            Button {
                onSelect(mention)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label(sourceLabel(mention), systemImage: sourceSystemImage(mention))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(mention.snippet.isEmpty ? mention.searchText : mention.snippet)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
        .frame(minWidth: 260, minHeight: 160)
    }

    // exhaustive switch — `VerseMentionSourceType`에 케이스가 늘면 컴파일 에러로 여기를 놓치지 않는다.
    private func sourceLabel(_ mention: VerseMention) -> String {
        switch mention.sourceType {
        case .memo: return "메모"
        case .document: return "연구 문서"
        case .wordSummary: return "말씀 요약"
        case .sermon: return "내 설교"
        }
    }

    private func sourceSystemImage(_ mention: VerseMention) -> String {
        switch mention.sourceType {
        case .memo: return "note.text"
        case .document: return "doc.text"
        case .wordSummary: return "text.book.closed"
        case .sermon: return "mic.fill"
        }
    }
}
