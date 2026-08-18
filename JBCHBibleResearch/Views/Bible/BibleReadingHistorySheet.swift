//
//  BibleReadingHistorySheet.swift
//  JBCHBibleResearch
//
//  [2026-08-08 신설] 사용자 요청 — "조회 이력(히스토리) 기능 추가 (년월일 시분초),
//  100개의 조회한 성경과 장의 이력을 저장하고 조회할 수 있도록". S1 툴바에서 시트로
//  띄운다. 항목을 탭하면 그 책/장으로 이동한 뒤 시트를 닫는다(다시 조회한 것이므로
//  그 이동 자체도 새 이력으로 기록된다 — BibleReadingViewModel.jumpToHistoryEntry
//  상단 주석 참고).
//

import SwiftUI
import BibleResearchModels

struct BibleReadingHistorySheet: View {
    let viewModel: BibleReadingViewModel
    var onDismiss: () -> Void

    @State private var entries: [BibleReadingHistoryEntry] = []

    /// 요청사항 그대로 "년월일 시분초"를 모두 보여준다.
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter
    }()

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView("조회 이력이 없습니다", systemImage: "clock")
                } else {
                    List(entries) { entry in
                        Button {
                            viewModel.jumpToHistoryEntry(entry)
                            onDismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bookChapterLabel(for: entry))
                                Text(Self.timestampFormatter.string(from: entry.viewedAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("조회 이력")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기", action: onDismiss)
                }
            }
        }
        .onAppear {
            // 시트를 열 때마다 새로 불러온다 — 다른 창에서 쌓인 이력까지 반영하기
            // 위해 캐싱하지 않는다(BibleReadingViewModel.fetchHistory 상단 주석 참고).
            entries = viewModel.fetchHistory()
        }
    }

    private func bookChapterLabel(for entry: BibleReadingHistoryEntry) -> String {
        guard let book = BooksProvider.shared.book(id: entry.bookId) else {
            return "책 \(entry.bookId) \(entry.chapter)장"
        }
        return "\(book.nameKo) \(entry.chapter)장"
    }
}
