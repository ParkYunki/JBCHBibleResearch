//
//  VerseMentionListView.swift
//  JBCHBibleResearch
//
//  "관련 내용"(이 구절을 언급하는 메모/연구문서/말씀 요약/설교) 목록 뷰.
//  확대보기(VerseZoomView)의 "관련 내용 N개" 팝오버가 쓴다(오른쪽 사이드 패널 `ChapterRelatedContentPanel`은
//  이 뷰를 쓰지 않고 섹션별 행을 직접 그린다).
//  표시만 담당하며, 항목 선택 시 무엇을 열지는 호출부가 `onSelect` 클로저로 결정한다.
//

import SwiftUI
import BibleResearchModels

struct VerseMentionListView: View {
    let mentions: [VerseMention]
    /// 연구문서·내 설교 행의 출처 제목(`BibleReadingViewModel.mentionSourceTitle(for:)` — 장 로드 때 채운 사전을
    /// 읽기만 해 `body`에서 불러도 조회가 없다). nil이면 이름 줄을 뺀다.
    let titleProvider: (VerseMention) -> String?
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
                    if let truncation = Self.sourceTitleTruncation(mention.sourceType) {
                        // 연구문서·내 설교(2026-10-29): 출처 제목 1줄(말줄임) + 언급 내용 2줄.
                        // 종류 아이콘은 바로 위 라벨에 있어 제목 줄에는 다시 붙이지 않는다.
                        if let title = titleProvider(mention) {
                            Text(title)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(truncation)
                        }
                        Text(mention.snippet.isEmpty ? mention.searchText : mention.snippet)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text(mention.snippet.isEmpty ? mention.searchText : mention.snippet)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
        .frame(minWidth: 260, minHeight: 160)
    }

    /// 출처 제목을 붙이는 종류와 말줄임 위치 — `VerseRelatedSheet`와 같은 규칙(파일명은 가운데, 설교 제목은 끝). 나머지는 nil.
    private static func sourceTitleTruncation(_ sourceType: VerseMentionSourceType) -> Text.TruncationMode? {
        switch sourceType {
        case .document: return .middle
        case .sermon: return .tail
        case .memo, .wordSummary: return nil
        }
    }

    // exhaustive switch — `VerseMentionSourceType`에 케이스가 늘면 컴파일 에러로 여기를 놓치지 않는다.
    private func sourceLabel(_ mention: VerseMention) -> String {
        switch mention.sourceType {
        case .memo: return String(localized: "메모")
        case .document: return String(localized: "연구 문서")
        case .wordSummary: return String(localized: "말씀 요약")
        case .sermon: return String(localized: "내 설교")
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
