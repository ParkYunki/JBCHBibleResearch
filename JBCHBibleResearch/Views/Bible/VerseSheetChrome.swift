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

// MARK: - 아이패드·아이폰 레이어 공용 부품 (2026-10-02 목업 "구절 레이어 통일안")
//
// 메모하기(`VerseZoomView`)·원문 정보(`OriginalTextInfoView`)·책/장 선택(`BookChapterPicker`)이 같은 머리·버튼·카드 규격을 쓰게 한다.
// 머리 = 1줄 [닫기/뒤로 · 세리프 제목] + (시트만) 2줄 [‹ n절 › 묶음 · 전환/도구 버튼]. 버튼 40pt/모서리 10pt, 색은 모두 성경 테마에서 파생.
// 머리(`VerseLayerHeader`)·관주 칩·개인 묵상 카드는 맥도 함께 쓴다(2026-10-02 맥 통일). 조작줄/하단 도구 줄은 iOS/iPadOS 전용(`#if os(iOS)`).

import SwiftUI

/// 머리 1줄 — 왼쪽 버튼(닫기/뒤로), 가운데 성곡 세리프 제목. 제목은 양쪽 버튼 폭만큼 여백을 두어 겹치지 않는다.
struct VerseLayerHeader<Leading: View>: View {
    let title: String
    var titleSize: CGFloat = 20
    @ViewBuilder var leading: Leading

    var body: some View {
        let textColor = UserSettingsStore.shared.bibleTextColor ?? Color.primary
        ZStack {
            Text(title)
                .font(.custom(SpecialPurposeFonts.titleSerif, size: titleSize, relativeTo: .title3))
                .fontWeight(.semibold)
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 96)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 0) {
                leading
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }
}

#if os(iOS)
/// 머리 2줄 — 구절 이동 묶음 [‹ n절 ›]과 오른쪽 전환/도구 버튼. 아래에 글자색 14% 선.
/// 묶음은 성경 조회 상단 막대의 `BibleBarSegmentGroup`을 터치용 크기로 쓴다.
struct VerseLayerStrip<Trailing: View>: View {
    let verseLabel: String
    let canGoPrevious: Bool
    let canGoNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        let textColor = UserSettingsStore.shared.bibleTextColor ?? Color.primary
        HStack(spacing: 10) {
            BibleBarSegmentGroup {
                Button(action: onPrevious) {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                }
                .disabled(!canGoPrevious)
                .accessibilityLabel("이전 절")
                BibleBarSegmentDivider()
                Text(verseLabel)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 58, minHeight: 40)
                BibleBarSegmentDivider()
                Button(action: onNext) {
                    Image(systemName: "chevron.right").font(.system(size: 16, weight: .semibold))
                }
                .disabled(!canGoNext)
                .accessibilityLabel("다음 절")
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) { trailing }
        }
        .environment(\.bibleBarSizing, .touch)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(textColor.opacity(0.14)).frame(height: 1)
        }
    }
}

/// 시트 아래쪽 도구 줄 바탕 — 맥 `VerseSheetFooter`와 같은 톤(테마 배경 + 강조색 6% + 위쪽 선 + 옅은 그림자).
struct VerseLayerFooter<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let settings = UserSettingsStore.shared
        let base: Color = settings.bibleBackgroundColor ?? Color(uiColor: .systemBackground)
        let textColor: Color = settings.bibleTextColor ?? Color.primary
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        HStack(alignment: .top, spacing: isPhone ? 10 : 16) { content }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    base
                    Color("AccentColor").opacity(0.06)
                }
                .shadow(color: Color.black.opacity(0.07), radius: 3, x: 0, y: -2)
                .ignoresSafeArea(edges: .bottom)
            }
            .overlay(alignment: .top) {
                Rectangle().fill(textColor.opacity(0.25)).frame(height: 1)
            }
    }
}

/// 도구 하나 — 44pt 상자(내용) 아래, 상자 바깥에 이름. 성경 조회 하단 메뉴와 같은 배치다.
struct VerseLayerToolCaption<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 5) {
            content
            Text(title)
                .font(.caption)
                .foregroundStyle(UserSettingsStore.shared.bibleTextColor ?? Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityHidden(true)
        }
    }
}

/// 상자 모양(44pt, 모서리 10, 글자색 10% 바탕 + 24% 선) — 버튼이 아닌 묶음(형광펜 점 줄)용.
struct VerseLayerBoxModifier: ViewModifier {
    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let palette = BibleBarPalette(environment: environment, colorScheme: colorScheme)
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        content
            .frame(minWidth: 44, minHeight: 44)
            .background(shape.fill(palette.text.opacity(BibleBarMetrics.fillOpacity)))
            .overlay(shape.strokeBorder(palette.text.opacity(BibleBarMetrics.lineOpacity), lineWidth: 1))
    }
}

extension View {
    func verseLayerBox() -> some View { modifier(VerseLayerBoxModifier()) }
}

/// 도구 상자 버튼 스타일 — 위 상자 모양에 눌림 색(24%)을 더한다.
struct VerseLayerToolButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        VerseLayerToolButtonBody(configuration: configuration)
    }
}

private struct VerseLayerToolButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = BibleBarPalette(environment: environment, colorScheme: colorScheme)
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        configuration.label
            .font(.system(size: 20))
            .foregroundStyle(palette.text)
            .padding(.horizontal, 10)
            .frame(minWidth: 44, minHeight: 44)
            .background(shape.fill(palette.text.opacity(configuration.isPressed ? BibleBarMetrics.pressOpacity : BibleBarMetrics.fillOpacity)))
            .overlay(shape.strokeBorder(palette.text.opacity(BibleBarMetrics.lineOpacity), lineWidth: 1))
            .contentShape(shape)
            .opacity(isEnabled ? 1 : BibleBarMetrics.disabledOpacity)
    }
}
#endif

/// 관주 구절 칩 — 테마 강조색(바탕 12% + 선 35%, 모서리 8). 맥·아이패드·아이폰 공통(2026-10-02 맥 통일: 이전 옅은 파랑 폐기).
struct VerseLinkChipModifier: ViewModifier {
    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let palette = BibleBarPalette(environment: environment, colorScheme: colorScheme)
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        content
            .foregroundStyle(palette.strong)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(shape.fill(palette.strong.opacity(0.12)))
            .overlay(shape.strokeBorder(palette.strong.opacity(0.35), lineWidth: 1))
    }
}

/// 개인 묵상 카드 바탕 — 강조색 11% 바탕 + 35% 선, 모서리 12(노랑은 테마와 따로 놀아 대체). 맥·아이패드·아이폰 공통.
struct VerseNoteCardModifier: ViewModifier {
    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let palette = BibleBarPalette(environment: environment, colorScheme: colorScheme)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        content
            .padding(10)
            .background(shape.fill(palette.strong.opacity(0.11)))
            .overlay(shape.strokeBorder(palette.strong.opacity(0.35), lineWidth: 1))
    }
}
