//
//  VerseMentionListView.swift
//  JBCHBibleResearch
//
//  [2026-08-11 신설] "관련 내용"(이 구절을 언급하는 메모/연구문서) 목록 — 확대보기
//  하단 아이콘의 팝오버(VerseZoomView)와 구절 선택 후 오른쪽 사이드바
//  (ChapterRelatedContentPanel)가 공유한다. 이 뷰 자체는 표시만 담당하고, 항목을
//  골랐을 때 실제로 무엇을 열지(메모 편집기 시트 vs 연구문서 PDF 검색 창)는
//  호출부가 `onSelect` 클로저로 결정한다 — `BibleReadingContentView`가 그 콜백
//  하나로 두 화면(확대보기/사이드바)의 동작을 통일한다.
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

    // [2026-08-12 추가] 사용자 요청으로 `VerseMentionSourceType`에 `.wordSummary`가
    // 새로 생기면서(VerseMentions.swift 참고), 기존 "메모 아니면 연구문서" 2지선다
    // 삼항연산자로는 말씀 요약 언급이 "연구문서"로 잘못 표시될 수 있었다 — 세
    // 경우를 모두 다루는 exhaustive switch로 바꿨다(새 케이스가 또 생기면 컴파일
    // 에러로 여기를 놓치지 않게 된다).
    private func sourceLabel(_ mention: VerseMention) -> String {
        switch mention.sourceType {
        case .memo: return "메모"
        case .document: return "연구문서"
        case .wordSummary: return "말씀 요약"
        }
    }

    private func sourceSystemImage(_ mention: VerseMention) -> String {
        switch mention.sourceType {
        case .memo: return "note.text"
        case .document: return "doc.text"
        case .wordSummary: return "text.book.closed"
        }
    }
}
