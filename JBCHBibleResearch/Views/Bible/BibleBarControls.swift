//
//  BibleBarControls.swift
//  JBCHBibleResearch
//
//  성경 조회(맥OS)의 상단 이동 막대와 구절 선택 하단 메뉴가 함께 쓰는 버튼 규격 (2026-10-02 목업 결정).
//
//  이전에는 상단이 44pt 원형(강조색 12% 배경 + 금색 아이콘), 작은 시스템 책 버튼, 8% 채움 검색창, 32pt 원으로 제각각이었고
//  하단은 기본 버튼 + 강조색 14% 배경에 금색 글자라 배경과 글자가 섞여 읽기 어려웠다.
//
//  규격: 높이 32pt, 모서리 8pt(continuous), 배경 = 테마 글자색 10%(올림 17%, 눌림 24%), 테두리 = 글자색 24%, 글자·아이콘 = 글자색.
//  강조(`primary`)는 한 단계 진한 금갈색 채움 + 흰 글자(밝은 테마), 밝은 금색 채움 + 어두운 글자(어두운 테마)로 대비를 확보한다.
//  모든 색은 사용자 성경 테마(`UserSettingsStore.bibleBackgroundColor/bibleTextColor`)에서 파생해 어떤 테마에서도 같은 농도로 보인다.
//  (고정색은 강조 채움 두 가지뿐.) 플랫폼 공용 SwiftUI API만 써서 iOS 빌드에서도 컴파일되지만, 지금은 맥OS 화면에서만 쓴다.

import SwiftUI

enum BibleBarMetrics {
    static let height: CGFloat = 32
    static let radius: CGFloat = 8
    static let fillOpacity: Double = 0.10
    static let hoverOpacity: Double = 0.17
    static let pressOpacity: Double = 0.24
    static let lineOpacity: Double = 0.24
    static let disabledOpacity: Double = 0.38
}

/// 상단 이동 막대(묶음·구분선·책 버튼·검색창·이동 버튼)의 크기 한 벌. 모양·농도는 같고 크기만 다르다 —
/// 맥은 포인터용 32pt, 아이패드는 터치용 40pt(`BibleBarButtonStyle` 주석의 40/10/15 규격과 같다).
/// 환경값(`\.bibleBarSizing`)으로 내려 보내 묶음/구분선/책 선택기가 같은 크기를 쓰게 한다. 기본값은 맥 규격.
struct BibleBarSizing {
    var height: CGFloat
    var radius: CGFloat
    /// 글자 버튼(책 버튼) 글자 크기.
    var fontSize: CGFloat
    /// 아이콘 버튼(화살표·이동) 아이콘 크기.
    var iconSize: CGFloat
    /// 검색창 입력 글자 크기.
    var fieldFontSize: CGFloat

    static let regular = BibleBarSizing(height: BibleBarMetrics.height, radius: BibleBarMetrics.radius, fontSize: 13, iconSize: 14, fieldFontSize: 12.5)
    static let touch = BibleBarSizing(height: 40, radius: 10, fontSize: 15, iconSize: 16, fieldFontSize: 15)
}

private struct BibleBarSizingKey: EnvironmentKey {
    static let defaultValue = BibleBarSizing.regular
}

extension EnvironmentValues {
    var bibleBarSizing: BibleBarSizing {
        get { self[BibleBarSizingKey.self] }
        set { self[BibleBarSizingKey.self] = newValue }
    }
}

/// 테마에서 파생한 막대 버튼 색. 배경 테마가 없으면 시스템 라이트/다크를 따른다.
struct BibleBarPalette {
    let text: Color
    let strong: Color
    let strongForeground: Color

    init(environment: EnvironmentValues, colorScheme: ColorScheme) {
        let settings = UserSettingsStore.shared
        text = settings.bibleTextColor ?? Color.primary
        let isDark: Bool
        if let background = settings.bibleBackgroundColor {
            let resolved = background.resolve(in: environment)
            // 다른 곳(`ThemedNavigationBarBackgroundModifier`)과 같은 휘도 판정.
            isDark = 0.2126 * Double(resolved.red) + 0.7152 * Double(resolved.green) + 0.0722 * Double(resolved.blue) < 0.5
        } else {
            isDark = colorScheme == .dark
        }
        if isDark {
            strong = Color(hex: "#D1A35E") ?? Color("AccentColor")
            strongForeground = Color(hex: "#1E1B16") ?? Color.black
        } else {
            strong = Color(hex: "#8F611D") ?? Color("AccentColor")
            strongForeground = Color.white
        }
    }
}

/// 단독 버튼 스타일. `isSquare`면 32×32(아이콘만), 아니면 글자 길이에 맞춰 늘어난다(좌우 여백 10pt, 최소 폭 32pt).
struct BibleBarButtonStyle: ButtonStyle {
    enum Kind { case secondary, primary, ghost }
    var kind: Kind = .secondary
    var isSquare = false
    /// 맥OS 기본 규격은 32pt/8pt/13pt. 아이패드(터치)는 40pt/10pt/15pt로 키워 쓴다.
    var height: CGFloat = BibleBarMetrics.height
    var cornerRadius: CGFloat = BibleBarMetrics.radius
    var fontSize: CGFloat = 13

    func makeBody(configuration: Configuration) -> some View {
        BibleBarButtonBody(
            configuration: configuration, kind: kind, isSquare: isSquare,
            height: height, cornerRadius: cornerRadius, fontSize: fontSize
        )
    }
}

private struct BibleBarButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: BibleBarButtonStyle.Kind
    let isSquare: Bool
    let height: CGFloat
    let cornerRadius: CGFloat
    let fontSize: CGFloat

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        let palette = BibleBarPalette(environment: environment, colorScheme: colorScheme)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let pressed = configuration.isPressed
        let hovered = isHovering && isEnabled
        let fill: Color = {
            switch kind {
            case .primary:
                return palette.strong.opacity(pressed ? 0.78 : (hovered ? 0.9 : 1))
            case .secondary:
                return palette.text.opacity(pressed ? BibleBarMetrics.pressOpacity : (hovered ? BibleBarMetrics.hoverOpacity : BibleBarMetrics.fillOpacity))
            case .ghost:
                return palette.text.opacity(pressed ? BibleBarMetrics.pressOpacity : (hovered ? BibleBarMetrics.fillOpacity : 0))
            }
        }()
        configuration.label
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(kind == .primary ? palette.strongForeground : palette.text)
            .padding(.horizontal, isSquare ? 0 : 10)
            .frame(width: isSquare ? height : nil, height: height)
            .frame(minWidth: height)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(kind == .primary ? palette.strong : palette.text.opacity(BibleBarMetrics.lineOpacity), lineWidth: 1))
            .contentShape(shape)
            .opacity(isEnabled ? 1 : BibleBarMetrics.disabledOpacity)
            .onHover { isHovering = $0 }
    }
}

/// 이어 붙인 버튼 묶음(예: 히스토리 이전 + 이전 장). 묶음이 배경·테두리·모서리를 한 번만 그리고, 안쪽 버튼은
/// `BibleBarSegmentItemStyle`로 올림/눌림 색만 칠한다. 버튼 사이에는 `BibleBarSegmentDivider()`를 직접 넣는다.
struct BibleBarSegmentGroup<Content: View>: View {
    @ViewBuilder var content: Content

    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bibleBarSizing) private var sizing

    var body: some View {
        let palette = BibleBarPalette(environment: environment, colorScheme: colorScheme)
        let shape = RoundedRectangle(cornerRadius: sizing.radius, style: .continuous)
        HStack(spacing: 0) { content }
            .buttonStyle(BibleBarSegmentItemStyle())
            .frame(height: sizing.height)
            .background(shape.fill(palette.text.opacity(BibleBarMetrics.fillOpacity)))
            .clipShape(shape)
            .overlay(shape.strokeBorder(palette.text.opacity(BibleBarMetrics.lineOpacity), lineWidth: 1))
    }
}

struct BibleBarSegmentDivider: View {
    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bibleBarSizing) private var sizing

    var body: some View {
        Rectangle()
            .fill(BibleBarPalette(environment: environment, colorScheme: colorScheme).text.opacity(BibleBarMetrics.lineOpacity))
            .frame(width: 1, height: sizing.height)
    }
}

struct BibleBarSegmentItemStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BibleBarSegmentItemBody(configuration: configuration)
    }
}

private struct BibleBarSegmentItemBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bibleBarSizing) private var sizing
    @State private var isHovering = false

    var body: some View {
        let palette = BibleBarPalette(environment: environment, colorScheme: colorScheme)
        let overlayOpacity: Double = configuration.isPressed ? BibleBarMetrics.fillOpacity + 0.06
            : (isHovering && isEnabled ? BibleBarMetrics.fillOpacity - 0.03 : 0)
        configuration.label
            .foregroundStyle(palette.text)
            .frame(width: sizing.height, height: sizing.height)
            .background(palette.text.opacity(overlayOpacity))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : BibleBarMetrics.disabledOpacity)
            .onHover { isHovering = $0 }
    }
}

/// 하단 메뉴의 "n개 절 선택됨" 알약 칩.
struct BibleBarCountChip: View {
    let text: String

    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = BibleBarPalette(environment: environment, colorScheme: colorScheme)
        HStack(spacing: 7) {
            Circle().fill(palette.strong).frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(palette.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .frame(height: 28)
        .background(Capsule().fill(palette.text.opacity(0.08)))
        .accessibilityElement(children: .combine)
    }
}

/// 하단 메뉴의 그룹 구분선(세로 20pt).
struct BibleBarGroupDivider: View {
    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(BibleBarPalette(environment: environment, colorScheme: colorScheme).text.opacity(0.22))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 2)
            .accessibilityHidden(true)
    }
}

/// 하단 메뉴 버튼용 수정자 — 스타일 + 툴팁(아이콘만 남는 좁은 창에서 이름을 알려 준다).
struct BibleBarActionModifier: ViewModifier {
    let kind: BibleBarButtonStyle.Kind
    let help: String

    func body(content: Content) -> some View {
        content
            .buttonStyle(BibleBarButtonStyle(kind: kind))
            .help(help)
    }
}

// MARK: - iOS 상단 이동 막대(캡슐) 부품

/// 캡슐 배경: 글자색 10% 채움 + 24% 테두리 (맥OS 막대와 같은 농도).
/// 2026-10-02: 양끝 타원(`Capsule`) 대신 모서리 10pt 라운드 사각형으로 바꿔 다른 버튼·입력창(모서리 10pt)과 모양을 맞췄다.
/// 이름은 "캡슐"이지만 모양은 라운드 사각형이다(호출부 이름 유지).
struct BibleCapsuleChrome: ViewModifier {
    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let palette = BibleBarPalette(environment: environment, colorScheme: colorScheme)
        content
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.text.opacity(BibleBarMetrics.fillOpacity)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.text.opacity(BibleBarMetrics.lineOpacity), lineWidth: 1))
    }
}

/// 캡슐 안 아이콘 버튼 — 탭 영역 40×44 유지, 배경 없이 글자색 아이콘, 누르는 동안만 옅은 둥근 사각형.
struct BibleCapsuleItemStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BibleCapsuleItemBody(configuration: configuration)
    }
}

private struct BibleCapsuleItemBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = BibleBarPalette(environment: environment, colorScheme: colorScheme)
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(palette.text)
            .frame(width: 40, height: 44)
            .background(
                // 눌림 배경 모서리 8pt — 바깥 라운드 사각형(10pt)과 겹쳐 보이도록 안쪽으로 한 단계 작게.
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.text.opacity(configuration.isPressed ? 0.16 : 0))
                    .padding(.vertical, 4)
            )
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : BibleBarMetrics.disabledOpacity)
    }
}

/// 캡슐 안 "이동" 버튼 — 36×36pt 강조 라운드 사각형(모서리 8pt, 탭 영역은 40×44). 2026-10-02: 원 → 라운드 사각형.
struct BibleCapsuleGoStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BibleCapsuleGoBody(configuration: configuration)
    }
}

private struct BibleCapsuleGoBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = BibleBarPalette(environment: environment, colorScheme: colorScheme)
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(palette.strongForeground)
            .frame(width: 36, height: 36)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(palette.strong.opacity(configuration.isPressed ? 0.78 : 1)))
            .frame(width: 40, height: 44)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : BibleBarMetrics.disabledOpacity)
    }
}

/// 캡슐 안 버튼 사이 구분선(세로 22pt). 모든 버튼 사이에 하나씩 둔다.
struct BibleCapsuleDivider: View {
    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(BibleBarPalette(environment: environment, colorScheme: colorScheme).text.opacity(BibleBarMetrics.lineOpacity))
            .frame(width: 1, height: 22)
            .accessibilityHidden(true)
    }
}

// MARK: - iOS 하단 메뉴 아이콘 전용 버튼

/// 하단 메뉴 아이콘 전용(좁은 화면) 버튼 외형: 44pt 높이 + 둥근 사각형 12pt, 글자색 10% 채움 + 24% 테두리, 아이콘은 글자색.
/// `primary`는 강조 채움, `ghost`는 배경 없는 윤곽선. 이름은 길게 누르면 뜨는 풍선(`contextMenu`)으로 알려 준다 —
/// 라벨이 사라져 아이콘만으로는 뜻을 알기 어렵기 때문(맥OS의 `.help` 툴팁에 해당). 풍선 항목은 누르는 동작이 없는 안내용이다.
struct BibleBarIconOnlyModifier: ViewModifier {
    let kind: BibleBarButtonStyle.Kind
    let title: String
    let systemImage: String

    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        let palette = BibleBarPalette(environment: environment, colorScheme: colorScheme)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        content
            .buttonStyle(.plain)
            .foregroundStyle(kind == .primary ? palette.strongForeground : palette.text)
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
            .background(shape.fill(kind == .primary ? palette.strong : (kind == .ghost ? Color.clear : palette.text.opacity(BibleBarMetrics.fillOpacity))))
            .overlay(shape.strokeBorder(kind == .primary ? palette.strong : palette.text.opacity(BibleBarMetrics.lineOpacity), lineWidth: 1))
            .contentShape(shape)
            .opacity(isEnabled ? 1 : BibleBarMetrics.disabledOpacity)
            .accessibilityLabel(title)
            .contextMenu {
                Label(title, systemImage: systemImage)
            }
    }
}
