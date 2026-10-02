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
    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme

    /// 지금 이 행이 놓인 배경이 어두운지 — 테마 배경이 있으면 그 상대휘도로, 없으면 시스템 외형으로 판정한다
    /// (`WordNoteHomeView.isDarkTheme`와 같은 공식). 어두운 면에서는 가죽 표지색을 글자용 밝은 변형으로 바꾼다.
    private var isDarkSurface: Bool {
        if let background = settings.bibleBackgroundColor {
            let resolved = background.resolve(in: environment)
            let luminance = 0.2126 * Double(resolved.red) + 0.7152 * Double(resolved.green) + 0.0722 * Double(resolved.blue)
            return luminance < 0.5
        }
        return colorScheme == .dark
    }

    var body: some View {
        // 인덱스 갱신 배지는 노트 상태에 가까워 첫 줄(카테고리 배지 옆)에 둔다.
        VStack(alignment: .leading, spacing: Self.contentSpacing) {
            HStack(spacing: Self.badgeRowSpacing) {
                categoryBadge
                if item.pendingIndexRefresh {
                    indexRefreshBadge
                }
                Spacer(minLength: 6)
                if let dateLabel = item.dateLabel {
                    Text(dateLabel)
                        .font(Self.dateFont)
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.7) ?? .secondary)
                }
            }
            Text(item.previewTitle)
                .font(Self.titleFont)
                // 배지는 의미색이라 테마와 무관하게 두고, 제목만 테마 계열로 맞춰 대비를 유지한다.
                .foregroundStyle(settings.bibleTextColor ?? .primary)
                .lineLimit(1)
            Text(item.coordinateLabel)
                .font(Self.coordinateFont)
                // 배지·spine과 같은 `categoryColor`로 강조한다.
                .foregroundStyle(categoryColor)
            if let previewSnippet = item.previewSnippet {
                Text(previewSnippet)
                    .font(Self.snippetFont)
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.75) ?? .secondary)
                    .lineSpacing(Self.snippetLineSpacing)
                    .lineLimit(2)
            }
            if item.pendingIndexRefresh {
                Text("이 항목을 열었다가 닫으면 관련 구절 인덱스가 다시 생성됩니다.")
                    .font(Self.noticeFont)
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
        // 행과 행 사이 여유 — spine 막대는 내용에 붙어 있고(위 오버레이) 이 바깥 여백이 구분선과 막대 사이를 벌린다.
        .padding(.vertical, Self.rowOuterVerticalPadding)
    }

    // MARK: - 글자 크기·간격 (macOS는 한 단계씩 키우고 간격을 넓혔다, 2026-10-02)
    //
    // macOS 텍스트 스타일은 caption/caption2/footnote가 모두 10pt라 한 단계 위(`footnote`)가 눈에 안 보인다. 그래서 macOS는 포인트 크기를
    // 직접 정한다(macOS에는 Dynamic Type이 없다): 배지 10→11, 날짜 10→11, 제목 13→15, 성경 구절 10→12, 미리보기 10→12.
    // iOS/아이패드는 같은 요청 범위(맥 목록)가 아니라 기존 값을 그대로 둔다.

    #if os(macOS)
    private static let badgeFont = Font.system(size: 11, weight: .bold)
    private static let dateFont = Font.system(size: 11)
    private static let titleFont = Font.system(size: 15, weight: .semibold)
    private static let coordinateFont = Font.system(size: 12, weight: .semibold)
    private static let snippetFont = Font.system(size: 12)
    private static let noticeFont = Font.system(size: 11)
    private static let contentSpacing: CGFloat = 7
    private static let badgeRowSpacing: CGFloat = 8
    private static let snippetLineSpacing: CGFloat = 2
    private static let rowOuterVerticalPadding: CGFloat = 8
    private static let badgeHorizontalPadding: CGFloat = 8
    private static let badgeVerticalPadding: CGFloat = 3
    #else
    private static let badgeFont = Font.caption2.bold()
    private static let dateFont = Font.caption
    private static let titleFont = Font.headline
    private static let coordinateFont = Font.caption.weight(.semibold)
    private static let snippetFont = Font.caption
    private static let noticeFont = Font.caption2
    private static let contentSpacing: CGFloat = 4
    private static let badgeRowSpacing: CGFloat = 6
    private static let snippetLineSpacing: CGFloat = 0
    private static let rowOuterVerticalPadding: CGFloat = 0
    private static let badgeHorizontalPadding: CGFloat = 6
    private static let badgeVerticalPadding: CGFloat = 2
    #endif

    /// 리스트 항목 앞에 표시하는 카테고리 배지.
    private var categoryBadge: some View {
        Text(item.category.rawValue)
            .font(Self.badgeFont)
            .padding(.horizontal, Self.badgeHorizontalPadding)
            .padding(.vertical, Self.badgeVerticalPadding)
            .background(categoryColor.opacity(0.15))
            .foregroundStyle(categoryColor)
            .clipShape(Capsule())
    }

    /// 가죽 표지=개인 묵상, 서재 금박=말씀 요약(`WordNoteCategory.spineColor`).
    private var categoryColor: Color { item.category.spineColor(onDark: isDarkSurface) }

    /// 연구문서 상태 배지와 같은 시각 언어(대기/추출중=주황).
    private var indexRefreshBadge: some View {
        Text("인덱스 갱신 필요")
            .font(Self.badgeFont)
            .padding(.horizontal, Self.badgeHorizontalPadding)
            .padding(.vertical, Self.badgeVerticalPadding)
            .background(Color.orange.opacity(0.15))
            .foregroundStyle(Color.orange)
            .clipShape(Capsule())
    }
}
