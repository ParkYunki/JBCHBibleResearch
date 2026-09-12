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
    /// [2026-09-09 추가] 사용자 요청 — "테마를 적용하면 배경색과 글자색을
    /// 전체적으로 적용할 수 있는가(... 말씀노트 화면 배경색...)." 이 행의
    /// 제목/좌표 텍스트는 지금까지 시스템 기본색(`.primary`/`.secondary`)을
    /// 썼다 — `WordNoteHomeView`가 이제 리스트 배경을 테마색으로 바꿀 수
    /// 있으므로(그 파일 상단 주석 참고), 이 행 텍스트도 같은 색을 읽어야
    /// 한다. `TranslationColumnView`와 같은 읽기 전용 접근 패턴.
    private var settings: UserSettingsStore { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                categoryBadge
                Text(previewTitle)
                    .font(.headline)
                    // [2026-09-09 추가] 위 `settings` 주석 참고 — 카테고리/
                    // 인덱스 갱신 배지(아래)는 의미색(파랑·초록·주황)이라
                    // 테마와 무관하게 그대로 두지만, 이 제목 텍스트는 리스트
                    // 배경과 같은 테마 계열이어야 대비가 유지된다.
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
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
            // [2026-09-09 수정] `TranslationColumnView` 아이콘들이 이미
            // 쓰는 `settings.bibleTextColor ?? .secondary` 폴백 관례를
            // 그대로 따랐다.
            .foregroundStyle(settings.bibleTextColor ?? .secondary)
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
        // [2026-09-11 수정] 사용자 재검토 요청 — "다른 화면(설정/검색/개요/
        // 문서)의 항목 구분 배지는 전부 JBCHCategoryPalette를 쓰는데 이
        // 배지만 iOS 기본색이다." 가죽 표지(개인 손글씨 느낌) → 개인 묵상,
        // 서재 금박(이 탭 "새 항목" 버튼과 같은 대표색) → 말씀 요약으로
        // 배정한다.
        switch item.category {
        case .personalMemo: return JBCHCategoryPalette.wood
        case .verseSummary: return JBCHCategoryPalette.gold
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
