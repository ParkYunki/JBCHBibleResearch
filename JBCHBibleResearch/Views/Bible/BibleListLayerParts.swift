//
//  BibleListLayerParts.swift
//  JBCHBibleResearch
//
//  성경 조회의 "목록에서 골라 그 장으로 이동" 레이어(책갈피 목록 `BookmarkListPopover`, 조회 이력
//  `BibleReadingHistorySheet`)가 함께 쓰는 공통 부품 — 머리, 구분선, 섹션 머리, 행, 빈 상태, 목록 스타일.
//  두 화면이 같은 모양을 유지하도록 한 곳에 모았다(2026-10-02 통일 시안: 둘 다 레일/툴바에 붙는 팝오버,
//  구절 글자는 본문색 + 왼쪽 강조 막대, 머리 아래는 헤어라인, 책갈피는 hover 삭제 버튼 + 우클릭 메뉴).
//
//  색은 모두 사용자 성경 테마(`UserSettingsStore.bibleTextColor`)에서 파생한다 — 고정색(wood 등)은
//  어두운 테마 배경에서 보이지 않아 쓰지 않는다. 강조 막대만 `Color("AccentColor")`.
//
//  `TranslationPickerPopover`/`TranslationColumnView`에도 비슷한 머리가 복제돼 있으나 이번 통일 범위
//  밖이라 건드리지 않았다(필요하면 `BibleListLayerHeader`로 교체 가능).

import SwiftUI

/// 레이어 크기·높이 계산에 쓰는 값. 높이 값은 폰트 크기에서 계산한 근사치다(아이폰 시트 높이와 팝오버 높이 산정용).
enum BibleListLayerMetrics {
    /// 행 최소 높이(HIG 최소 탭 영역).
    static let rowHeight: CGFloat = 44
    /// 섹션 머리 한 줄의 근사 높이(위 10 + 글자 약 17 + 아래 4, 목록 행 여백 포함 반올림).
    static let sectionHeaderHeight: CGFloat = 34
    /// 목록 위아래 여유.
    static let listVerticalPadding: CGFloat = 8
    /// 책갈피 팝오버 폭 / 조회 이력 팝오버 폭.
    static let bookmarkWidth: CGFloat = 320
    static let historyWidth: CGFloat = 380
    /// 머리(제목 17pt bold 한 줄 ≈ 22 + 아래 10) 높이 — 위 여백은 컨테이너가 정하므로 인자로 받는다.
    static func headerHeight(topInset: CGFloat) -> CGFloat { topInset + 32 }
    /// 팝오버 전체 높이 상한(머리 + 구분선 + 목록).
    static let bookmarkMaxHeight: CGFloat = 392
    static let historyMaxHeight: CGFloat = 500
    /// 구분선 두께.
    static let dividerHeight: CGFloat = 1
    /// 빈 상태 영역 고정 높이(아이폰 시트/팝오버 높이 산정용).
    static let emptyStateHeight: CGFloat = 180
}

/// 머리: 제목 + 개수 배지(0이면 숨김) + 원형 닫기 버튼.
/// 위 여백은 컨테이너마다 다르다(팝오버 14, 아이폰 시트는 상태바/드래그 표시 때문에 더 큼) — `topInset`으로 받는다.
struct BibleListLayerHeader: View {
    let title: String
    var count: Int = 0
    var topInset: CGFloat = 14
    var onDismiss: () -> Void

    private var settings: UserSettingsStore { .shared }

    var body: some View {
        let textColor = settings.bibleTextColor ?? .primary
        HStack(spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(textColor)
            if count > 0 {
                Text("\(count)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(textColor.opacity(0.6))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(textColor.opacity(0.12), in: Capsule())
            }
            Spacer()
            // 팝오버는 바깥을 눌러도 닫히지만, 키보드/보조기기 사용자를 위해 명시적 닫기 버튼을 둔다.
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(textColor.opacity(0.6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("닫기")
        }
        .padding(.horizontal, 16)
        .padding(.top, topInset)
        .padding(.bottom, 10)
    }
}

/// 머리 아래 1pt 헤어라인. 색은 본문색 12% — 어떤 테마 배경에서도 같은 농도로 보인다.
struct BibleListLayerDivider: View {
    private var settings: UserSettingsStore { .shared }

    var body: some View {
        Rectangle()
            .fill((settings.bibleTextColor ?? .primary).opacity(0.12))
            .frame(height: BibleListLayerMetrics.dividerHeight)
    }
}

/// 섹션 머리(예: 조회 이력의 "오늘"). 행보다 작고 옅게 — 목록의 주인공은 행이다.
/// `List` 안에서 행처럼 쓰므로 호출부가 `bibleListLayerRowChrome()`과 `.listRowSeparator(.hidden)`를 붙인다.
struct BibleListLayerSectionHeader: View {
    let title: String
    let count: Int

    private var settings: UserSettingsStore { .shared }

    var body: some View {
        let textColor = settings.bibleTextColor ?? .primary
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(textColor.opacity(0.6))
            Text("\(count)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(textColor.opacity(0.4))
            Rectangle()
                .fill(textColor.opacity(0.12))
                .frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 행: 왼쪽 강조 막대 + 제목(본문색 semibold) + 보조 텍스트 + chevron.
/// `onDelete`가 있으면 우클릭/길게 누르기 메뉴에 삭제를 넣고, macOS에서는 마우스를 올린 동안 chevron 자리에
/// 삭제 버튼을 보인다(스와이프 삭제는 `List` 행에만 걸 수 있어 호출부가 따로 붙인다).
struct BibleListLayerRow: View {
    let title: String
    let meta: String
    var onSelect: () -> Void
    var onDelete: (() -> Void)? = nil
    var deleteLabel: String = "삭제"

    private var settings: UserSettingsStore { .shared }

    #if os(macOS)
    @State private var isHovering = false
    #endif

    /// hover 삭제 버튼 표시 여부 — macOS에서만 true가 될 수 있다.
    private var showsDeleteButton: Bool {
        #if os(macOS)
        return isHovering && onDelete != nil
        #else
        return false
        #endif
    }

    var body: some View {
        let textColor = settings.bibleTextColor ?? .primary
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(meta)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(textColor.opacity(0.6))
                    .lineLimit(1)
                    .layoutPriority(1)
                // 삭제 버튼이 같은 자리에 겹쳐 뜨므로 자리는 유지하고 보이지 않게만 한다(행 폭이 흔들리지 않게).
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(textColor.opacity(0.4))
                    .opacity(showsDeleteButton ? 0 : 1)
            }
            .padding(.leading, 26)
            .padding(.trailing, 16)
            .padding(.vertical, 11)
            .frame(minHeight: BibleListLayerMetrics.rowHeight)
            // 책등 강조 막대(`DocumentRowView.documentRowLabel` 패턴). 글자 대신 막대에만 강조색을 써 라이트 테마 대비를 지킨다.
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color("AccentColor"))
                    .frame(width: 3)
                    .padding(.vertical, 8)
                    .padding(.leading, 16)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if showsDeleteButton, let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.red)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
                .help(deleteLabel)
                .accessibilityLabel(deleteLabel)
            }
        }
        #if os(macOS)
        .background(isHovering ? textColor.opacity(0.07) : Color.clear)
        .onHover { isHovering = $0 }
        #endif
        .contextMenu {
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label(deleteLabel, systemImage: "trash")
                }
            }
        }
    }
}

/// 빈 상태: 아이콘 + 한 줄 설명 + 보조 안내. 두 목록이 같은 구성이며 색은 성경 테마를 따른다.
struct BibleListLayerEmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    private var settings: UserSettingsStore { .shared }

    var body: some View {
        let textColor = settings.bibleTextColor ?? .primary
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(textColor.opacity(0.6))
            Text(title)
                .font(.callout)
                .foregroundStyle(textColor.opacity(0.6))
            Text(message)
                .font(.caption)
                .foregroundStyle(textColor.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// 목록 레이어의 `List` 공통 스타일. `List`는 자체 배경이 있어 `.background()`만으로는 바뀌지 않으므로
    /// `.scrollContentBackground(.hidden)`와 짝으로 쓴다. 행 구분선은 본문색 12%.
    func bibleListLayerListStyle() -> some View {
        let settings = UserSettingsStore.shared
        return self
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(settings.bibleBackgroundColor ?? Color.clear)
            .listRowSeparatorTint((settings.bibleTextColor ?? .primary).opacity(0.12))
    }

    /// `List` 행 공통 처리 — 좌우 여백은 행 부품이 직접 가지므로 시스템 inset을 없애고, 행 배경은 투명하게 한다
    /// (`List` 컨테이너 배경만 바꾸면 각 행 셀 배경은 그대로 남는다).
    func bibleListLayerRowChrome() -> some View {
        self
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
    }
}
