//
//  WordNoteRowView.swift
//  JBCHBibleResearch
//
//  `WordNoteHomeView`(개인 묵상+말씀 요약 통합 목록)의 행 하나.
//  정보 위계: 노트 종류·날짜 -> 제목 -> 성경 구절 -> 본문 미리보기.
//  카테고리 색은 왼쪽 spine 색선으로도 표시해 목록을 훑을 때 종류가 구분되게 한다.
//  미리보기/좌표/날짜 라벨과 카테고리 색 매핑은 "최근 노트" 카드와 같은 값을 보여줘야 하므로
//  `WordNoteItem`/`WordNoteCategory.spineColor`의 공용 프로퍼티를 읽기만 한다.
//

import SwiftUI
import BibleResearchModels

struct WordNoteRowView: View {
    let item: WordNoteItem
    /// 제목/좌표 텍스트가 테마(리스트 배경)와 같은 색 계열을 쓰도록 읽는 설정(읽기 전용).
    private var settings: UserSettingsStore { .shared }

    var body: some View {
        // 인덱스 갱신 배지는 노트 상태에 가까워 첫 줄(카테고리 배지 옆)에 둔다.
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                categoryBadge
                if item.pendingIndexRefresh {
                    indexRefreshBadge
                }
                Spacer(minLength: 6)
                if let dateLabel = item.dateLabel {
                    Text(dateLabel)
                        .font(.caption)
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.7) ?? .secondary)
                }
            }
            Text(item.previewTitle)
                .font(.headline)
                // 배지는 의미색이라 테마와 무관하게 두고, 제목만 테마 계열로 맞춰 대비를 유지한다.
                .foregroundStyle(settings.bibleTextColor ?? .primary)
                .lineLimit(1)
            Text(item.coordinateLabel)
                .font(.caption.weight(.semibold))
                // 배지·spine과 같은 `categoryColor`로 강조한다.
                .foregroundStyle(categoryColor)
            if let previewSnippet = item.previewSnippet {
                Text(previewSnippet)
                    .font(.caption)
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.75) ?? .secondary)
                    .lineLimit(2)
            }
            if item.pendingIndexRefresh {
                Text("이 항목을 열었다가 닫으면 관련 구절 인덱스가 다시 생성됩니다.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
        // 왼쪽 3pt 여백을 더 두고 그 안에 spine 막대를 그린다(패딩을 먼저 적용해야 오버레이가 여백까지 포함한 경계에 맞춰진다).
        .padding(.leading, 11)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(categoryColor)
                .frame(width: 3)
        }
    }

    /// 리스트 항목 앞에 표시하는 카테고리 배지.
    private var categoryBadge: some View {
        Text(item.category.rawValue)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(categoryColor.opacity(0.15))
            .foregroundStyle(categoryColor)
            .clipShape(Capsule())
    }

    /// 가죽 표지=개인 묵상, 서재 금박=말씀 요약(`WordNoteCategory.spineColor`).
    private var categoryColor: Color { item.category.spineColor }

    /// 연구문서 상태 배지와 같은 시각 언어(대기/추출중=주황).
    private var indexRefreshBadge: some View {
        Text("인덱스 갱신 필요")
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.15))
            .foregroundStyle(Color.orange)
            .clipShape(Capsule())
    }
}
