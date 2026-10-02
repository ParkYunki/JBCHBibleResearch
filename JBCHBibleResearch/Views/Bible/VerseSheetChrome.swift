//
//  VerseSheetChrome.swift
//  JBCHBibleResearch
//
//  macOS 구절 선택 레이어 시트(확대보기 = 메모하기/개인 묵상, 원문 정보)의 하단 버튼 줄·제목 줄·도구 타일 부품 (2026-10-02 목업 결정).
//  버튼 규격은 `BibleBarControls.swift`(성경 조회 막대)와 같은 농도(글자색 10% 채움 / 24% 테두리)를 쓰고, 모든 색은 사용자 성경 테마에서 파생한다.
//
//  - `VerseSheetHeader`: 시스템 도구 모음 대신 시트 안에 직접 그리는 제목 줄(성곡 세리프 + 아래 헤어라인).
//  - `VerseSheetFooter`: 하단 버튼 줄 — 테마 배경 위에 강조색 6% 톤 + 위쪽 선 + 옅은 그림자.
//  - `VerseToolTileStyle` / `VerseToolBoxChrome`: 메모·개인 묵상·관주 타일(72×56)과 형광펜 색 점 상자의 공통 껍데기.
//  macOS 전용이다(iOS/iPadOS는 내비게이션 바 툴바를 그대로 쓴다).

#if os(macOS)
import SwiftUI

/// 시트 안 제목 줄.
struct VerseSheetHeader: View {
    let title: String

    var body: some View {
        let textColor = UserSettingsStore.shared.bibleTextColor ?? Color.primary
        Text(title)
            .font(.custom(SpecialPurposeFonts.titleSerif, size: 17, relativeTo: .title3))
            .fontWeight(.semibold)
            .foregroundStyle(textColor)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                Rectangle().fill(textColor.opacity(0.14)).frame(height: 1)
            }
            .accessibilityAddTraits(.isHeader)
    }
}

/// 시트 하단 버튼 줄. 안쪽 버튼은 호출부에서 `BibleBarButtonStyle`을 지정한다.
struct VerseSheetFooter<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let settings = UserSettingsStore.shared
        let base: Color = settings.bibleBackgroundColor ?? Color(nsColor: .windowBackgroundColor)
        let textColor: Color = settings.bibleTextColor ?? Color.primary
        HStack(spacing: 8) { content }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    base
                    Color("AccentColor").opacity(0.06)
                }
                .shadow(color: Color.black.opacity(0.07), radius: 3, x: 0, y: -2)
            }
            .overlay(alignment: .top) {
                Rectangle().fill(textColor.opacity(0.25)).frame(height: 1)
            }
    }
}

/// 상자형 도구(타일, 형광펜 상자)의 공통 껍데기: 높이 56, 모서리 10, 글자색 10% 채움 + 24% 테두리.
struct VerseToolBoxChrome: ViewModifier {
    var fillOpacity: Double = BibleBarMetrics.fillOpacity

    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let palette = BibleBarPalette(environment: environment, colorScheme: colorScheme)
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        content
            .frame(height: 56)
            .background(shape.fill(palette.text.opacity(fillOpacity)))
            .overlay(shape.strokeBorder(palette.text.opacity(BibleBarMetrics.lineOpacity), lineWidth: 1))
    }
}

/// 72×56 도구 타일 버튼 스타일(아이콘 위, 이름 아래 라벨을 받는다).
struct VerseToolTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        VerseToolTileBody(configuration: configuration)
    }
}

private struct VerseToolTileBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        let palette = BibleBarPalette(environment: environment, colorScheme: colorScheme)
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let hovered = isHovering && isEnabled
        let fill: Double = configuration.isPressed ? BibleBarMetrics.pressOpacity
            : (hovered ? BibleBarMetrics.hoverOpacity : BibleBarMetrics.fillOpacity)
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(palette.text)
            .frame(width: 72, height: 56)
            .background(shape.fill(palette.text.opacity(fill)))
            .overlay(shape.strokeBorder(palette.text.opacity(BibleBarMetrics.lineOpacity), lineWidth: 1))
            .contentShape(shape)
            .opacity(isEnabled ? 1 : BibleBarMetrics.disabledOpacity)
            .onHover { isHovering = $0 }
    }
}
#endif
