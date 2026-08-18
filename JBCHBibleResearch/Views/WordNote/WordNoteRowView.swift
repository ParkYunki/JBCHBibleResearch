//
//  WordNoteRowView.swift
//  JBCHBibleResearch
//
//  [2026-08-13 신설] `WordNoteHomeView`(개인 묵상+말씀 요약 통합 목록)의 행 하나.
//  기존 `MemoRowView`/`WordSummaryHomeView.WordSummaryRowView`(둘 다 이제 삭제됨)와
//  같은 원칙(미리보기 첫 줄 + 성경 좌표 + 인덱스 갱신 배지)에, 사용자 요청대로
//  "리스트 항목 앞에 카테고리를 표시"하는 배지를 앞에 붙였다.
//

import SwiftUI
import BibleResearchModels

struct WordNoteRowView: View {
    let item: WordNoteItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                categoryBadge
                Text(previewTitle)
                    .font(.headline)
                    .lineLimit(1)
                if item.pendingIndexRefresh {
                    indexRefreshBadge
                }
            }
            HStack(spacing: 6) {
                Text(coordinateLabel)
                if let dateLabel {
                    Text("·")
                    Text(dateLabel)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if item.pendingIndexRefresh {
                Text("이 항목을 열었다가 닫으면 관련 구절 인덱스가 다시 생성됩니다.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    /// 사용자 요청 — "리스트에서 리스트 항목 앞에 카테고리를 표시할 것."
    private var categoryBadge: some View {
        Text(item.category.rawValue)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(categoryColor.opacity(0.15))
            .foregroundStyle(categoryColor)
            .clipShape(Capsule())
    }

    private var categoryColor: Color {
        switch item.category {
        case .personalMemo: return .blue
        case .verseSummary: return .green
        }
    }

    /// `MemoRowView.indexRefreshBadge`/`WordSummaryRowView.indexRefreshBadge`와
    /// 같은 시각 언어(연구문서 상태 배지 — 대기/추출중=주황).
    private var indexRefreshBadge: some View {
        Text("인덱스 갱신 필요")
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.15))
            .foregroundStyle(Color.orange)
            .clipShape(Capsule())
    }

    private var previewTitle: String {
        let trimmed = item.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let emptyLabel = item.category == .personalMemo ? "새 메모" : "새 말씀 요약"
        guard !trimmed.isEmpty else { return emptyLabel }
        let firstLine = trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? trimmed
        return String(firstLine.prefix(40))
    }

    private var coordinateLabel: String {
        let bookName = BooksProvider.shared.book(id: item.bookId)?.nameKo ?? "\(item.bookId)권"
        var label = "\(bookName) \(item.chapter)장"
        if let verse = item.verse {
            label += " \(verse)절"
        }
        return label
    }

    /// [2026-08-14 변경] 사용자 요청 — "리스트의 개인 묵상에도 작성일자를 표시해줄
    /// 것." 원래는 말씀 요약(저널 성격, 같은 절에 여러 개가 쌓일 수 있음)만 날짜를
    /// 보여줬다 — 이제 개인 묵상도 함께 보여준다. 말씀 요약은 "쓴 날짜"(createdAt,
    /// 저널 성격), 개인 묵상은 "마지막 수정일"(updatedAt, 절당 하나를 계속 고쳐
    /// 쓰는 성격이라 생성일보다 수정일이 더 의미 있다 — `WordNoteItem.sortDate`가
    /// 이미 같은 기준으로 정렬하는 것과 일관됨)을 쓴다.
    private var dateLabel: String? {
        let date: Date
        switch item {
        case .memo(let memo): date = memo.updatedAt
        case .summary(let summary): date = summary.createdAt
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
}
