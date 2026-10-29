//
//  VerseSheetChrome.swift
//  JBCHBibleResearch
//
//  macOS 구절 선택 레이어 시트(확대보기 = 메모하기/개인 묵상, 원문 정보)의 하단 버튼 줄·제목 줄·도구 타일 부품 (2026-10-02 목업 결정).
//  버튼 규격은 `BibleBarControls.swift`(성경 조회 막대)와 같은 농도(글자색 10% 채움 / 24% 테두리)를 쓰고, 모든 색은 사용자 성경 테마에서 파생한다.
//
//  - `VerseSheetHeader`: 시스템 도구 모음 대신 시트 안에 직접 그리는 제목 줄(성곡 세리프 + 아래 헤어라인).
//  - `VerseSheetFooter`: 하단 버튼 줄 — 테마 배경 위에 강조색 6% 톤 + 위쪽 선 + 옅은 그림자.
//  - `VerseToolTileStyle` / `VerseToolBoxChrome`: 메모·개인 묵상·관주 타일(최소 72, 높이 56)과 형광펜 색 점 상자의 공통 껍데기.
//  macOS 전용이다(iOS/iPadOS는 내비게이션 바 툴바를 그대로 쓴다).

#if os(macOS)
import SwiftUI

/// 시트 안 제목 줄.
struct VerseSheetHeader: View {
    let title: String

    var body: some View {
        let textColor = UserSettingsStore.shared.bibleTextColor ?? Color.primary
        Text(title)
            .font(.titleSerif(title, size: 17, relativeTo: .title3))
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

/// 도구 타일 버튼 스타일(폭 최소 72·높이 56, 아이콘 위, 이름 아래 라벨을 받는다).
struct VerseToolTileStyle: ButtonStyle {
    /// 타일 최소 폭과, 그 안에서 이름이 한 줄로 남는 최대 폭(좌우 안쪽 여백 6pt씩을 뺀 값).
    static let minimumWidth: CGFloat = 72
    static let singleLineTitleWidth: CGFloat = minimumWidth - 12

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
            // [2026-10-29 zoommenu1] 폭 72 고정 → 최소 72. 이름이 두 줄로도 72pt(안쪽 60pt)에 안 들어가는 언어(러시아어 등)만
            // 타일이 넓어진다. 한국어 등 60pt 이하 이름은 예전과 같은 72×56. `fixedSize`로 줄에서 눌려 이름이 잘리지 않게 한다.
            .padding(.horizontal, 6)
            .frame(minWidth: VerseToolTileStyle.minimumWidth)
            .frame(height: 56)
            .fixedSize()
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
                .font(.titleSerif(title, size: titleSize, relativeTo: .title3))
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

/// [2026-10-29 zoommenu1] 도구 이름 — 단어 단위로 최대 두 줄, 가운데 정렬.
/// 한 줄 폭이 `singleLineMaxWidth` 이하이면 지금처럼 한 줄로 두고, 넘으면 두 줄 중 긴 줄이 가장 짧아지는 단어 경계에서 나눈 폭을 쓴다.
/// 나눌 수 있는 자리는 공백과 하이픈 뒤(유니코드 줄바꿈 규칙 UAX #14에서 줄바꿈이 허용되는 자리)뿐이다. 공백이 없는 이름(태국어·중국어·일본어)은 한 줄 폭 그대로다.
/// 폭은 숨긴 `Text`(나눈 앞부분·뒷부분)를 같은 글꼴로 재서 정하므로 글자 크기(Dynamic Type)가 바뀌어도 맞고,
/// 그 폭이 가장 긴 단어보다 좁아지지 않아 단어 중간에서 끊기지 않는다(축소·말줄임 없이 두 줄에 다 들어간다).
struct VerseLayerWrappedTitle: View {
    let title: String
    var singleLineMaxWidth: CGFloat = 0

    var body: some View {
        let normalized = title.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        let phrases = Self.splitPhrases(normalized)
        VerseLayerBalancedTitleLayout(singleLineMaxWidth: singleLineMaxWidth) {
            Text(normalized)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            ForEach(phrases.indices, id: \.self) { index in
                Text(phrases[index]).lineLimit(1).hidden().accessibilityHidden(true)
            }
        }
    }

    /// 나눌 수 있는 자리마다 [앞부분, 뒷부분]을 차례로 이어 붙인 배열(길이 = 자리 수 × 2).
    private static func splitPhrases(_ text: String) -> [String] {
        let characters = Array(text)
        var phrases: [String] = []
        for index in characters.indices where index > 0 && index < characters.count - 1 {
            if characters[index] == " " {
                phrases.append(String(characters[..<index]))
                phrases.append(String(characters[(index + 1)...]))
            } else if characters[index] == "-", characters[index - 1].isLetter, characters[index + 1].isLetter {
                phrases.append(String(characters[...index]))
                phrases.append(String(characters[(index + 1)...]))
            }
        }
        return phrases
    }
}

/// `VerseLayerWrappedTitle` 전용. 첫 자식 = 보이는 이름, 나머지 = 숨긴 [앞부분, 뒷부분] 쌍.
/// 제안 폭과 상관없이 위 규칙으로 정한 폭을 보고한다(`fixedSize`처럼). 그래서 `ViewThatFits`가 이상 크기를 잴 때도 같은 폭이 나온다.
struct VerseLayerBalancedTitleLayout: Layout {
    let singleLineMaxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let title = subviews.first else { return .zero }
        let width = titleWidth(subviews)
        return CGSize(width: width, height: title.sizeThatFits(ProposedViewSize(width: width, height: nil)).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let title = subviews.first else { return }
        let width = titleWidth(subviews)
        title.place(at: CGPoint(x: bounds.midX, y: bounds.minY), anchor: .top, proposal: ProposedViewSize(width: width, height: nil))
        // 숨긴 측정용 이름은 보이지 않으므로 아무 데나 두어도 된다(배치하지 않은 자식도 SwiftUI가 가운데에 두므로 명시한다).
        for phrase in subviews.dropFirst() {
            phrase.place(at: CGPoint(x: bounds.midX, y: bounds.minY), anchor: .top, proposal: .unspecified)
        }
    }

    private func titleWidth(_ subviews: Subviews) -> CGFloat {
        let oneLine = subviews[0].sizeThatFits(.unspecified).width
        guard oneLine > singleLineMaxWidth else { return oneLine }
        let widths = subviews.dropFirst().map { $0.sizeThatFits(.unspecified).width }
        var best = oneLine
        var index = 0
        while index + 1 < widths.count {
            best = min(best, max(widths[index], widths[index + 1]))
            index += 2
        }
        guard best < oneLine else { return oneLine }
        // 반올림 오차로 마지막 단어가 다음 줄로 밀리지 않게 1pt 여유. 한 줄 폭을 넘지는 않는다.
        return min(oneLine, best.rounded(.up) + 1)
    }
}

#if os(iOS)
/// 머리 2줄 — 구절 이동 묶음 [‹ n절 ›]과 오른쪽 전환/도구 버튼. 아래에 글자색 14% 선.
/// 묶음은 성경 조회 상단 막대의 `BibleBarSegmentGroup`을 터치용 크기로 쓴다.
///
/// [2026-10-29 zoommenu2] 오른쪽 버튼(`BibleBarButtonStyle`, 높이 40 고정·줄 수 제한 없음)은 줄이 좁으면 눌려 이름이 두 줄로 접히고
/// 단어 중간에서 끊겼다(러시아어 "Прос/мот…"). 이제 `ViewThatFits`가 아래 순서로 처음 들어가는 배치를 고른다.
///   1) 예전 그대로(간격 10, 여백 최소 8)
///   2) 간격만 좁힘(간격 6, 여백 최소 0) — 글자는 그대로
///   3) 2 + `verseLayerStripCollapsible()`을 붙인 버튼만 아이콘만
///   4) 2 + 모든 버튼 아이콘만
/// 아이콘만일 때 이름은 각 버튼의 `accessibilityLabel`·`help`(호출부)로 남는다. 넓은 화면은 1번이라 모양이 같다.
struct VerseLayerStrip<Trailing: View>: View {
    let verseLabel: String
    let canGoPrevious: Bool
    let canGoNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        let textColor = UserSettingsStore.shared.bibleTextColor ?? Color.primary
        ViewThatFits(in: .horizontal) {
            row(spacing: 10, spacerMinLength: 8, collapse: .none)
            row(spacing: 6, spacerMinLength: 0, collapse: .none)
            row(spacing: 6, spacerMinLength: 0, collapse: .marked)
            row(spacing: 6, spacerMinLength: 0, collapse: .all)
        }
        .environment(\.bibleBarSizing, .touch)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(textColor.opacity(0.14)).frame(height: 1)
        }
    }

    private enum Collapse { case none, marked, all }

    @ViewBuilder
    private func row(spacing: CGFloat, spacerMinLength: CGFloat, collapse: Collapse) -> some View {
        HStack(spacing: spacing) {
            verseGroup
            Spacer(minLength: spacerMinLength)
            if collapse == .all {
                HStack(spacing: 8) { trailing }
                    .labelStyle(.iconOnly)
            } else {
                HStack(spacing: 8) { trailing }
                    .environment(\.verseLayerStripCollapsesMarked, collapse == .marked)
            }
        }
    }

    private var verseGroup: some View {
        let textColor = UserSettingsStore.shared.bibleTextColor ?? Color.primary
        return BibleBarSegmentGroup {
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
    }
}

/// [2026-10-29 zoommenu2] `VerseLayerStrip` 3번 배치에서 이 버튼만 아이콘만 보이게 하는 표시. 먼저 접어도 뜻이 통하는 버튼(펜/눈 토글)에 붙인다.
private struct VerseLayerStripCollapsesMarkedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var verseLayerStripCollapsesMarked: Bool {
        get { self[VerseLayerStripCollapsesMarkedKey.self] }
        set { self[VerseLayerStripCollapsesMarkedKey.self] = newValue }
    }
}

private struct VerseLayerStripCollapsibleModifier: ViewModifier {
    @Environment(\.verseLayerStripCollapsesMarked) private var collapses

    func body(content: Content) -> some View {
        if collapses {
            content.labelStyle(.iconOnly)
        } else {
            content
        }
    }
}

extension View {
    func verseLayerStripCollapsible() -> some View { modifier(VerseLayerStripCollapsibleModifier()) }
}

/// 시트 도구 줄 바탕 — 2026-10-07: 화면 맨 아래 고정 바에서 "말씀구절 아래" 본문 흐름 안으로 옮겨(목업 결정) 스크롤 내용의 일부가 되었다.
/// 그래서 하단 고정 바용 배경(테마 배경 + 강조색 6% + 그림자 + 아래 안전영역 확장)은 없애고, 구절과 구분하는 위쪽 선만 둔다.
struct VerseLayerFooter<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let settings = UserSettingsStore.shared
        let textColor: Color = settings.bibleTextColor ?? Color.primary
        HStack(alignment: .top, spacing: VerseLayerToolMetrics.spacing) { content }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) {
                Rectangle().fill(textColor.opacity(0.25)).frame(height: 1)
            }
    }
}

/// [2026-10-29 zoommenu1] 하단 도구 사이 간격. `VerseLayerFooter`와 확대 보기 도구 줄(`VerseZoomView.actionBar`의 `ViewThatFits` 후보들)이 같은 값을 쓴다.
enum VerseLayerToolMetrics {
    static var spacing: CGFloat { UIDevice.current.userInterfaceIdiom == .phone ? 10 : 16 }
}

/// 도구 하나 — 44pt 상자(내용) 아래, 상자 바깥에 이름. 성경 조회 하단 메뉴와 같은 배치다.
/// [2026-10-29 zoommenu1] `wrapsTitle`이 true면 이름을 단어 단위로 최대 두 줄에 담는다(`VerseLayerWrappedTitle`, 44pt 이하 이름은 한 줄 그대로).
/// 기본값 false는 예전 그대로(한 줄, 0.8배까지 축소) — 한 줄 배치가 들어가는 화면(한국어 포함)은 이 경로라 모양이 바뀌지 않는다.
/// [2026-10-29 zoommenu2] `shrinksTitleToFit`이 true면(확대 보기 도구 줄의 마지막 후보, 아주 큰 접근성 글자 전용) 받은 폭을 다 쓰고
/// 이름은 두 줄 + 0.5배까지 축소. 이 경로만 단어 중간 끊김이 생길 수 있다(넘치는 것보다 낫다).
struct VerseLayerToolCaption<Content: View>: View {
    let title: String
    var wrapsTitle: Bool = false
    var shrinksTitleToFit: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 5) {
            content
            if shrinksTitleToFit {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(UserSettingsStore.shared.bibleTextColor ?? Color.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .accessibilityHidden(true)
            } else if wrapsTitle {
                VerseLayerWrappedTitle(title: title, singleLineMaxWidth: 44)
                    .font(.caption)
                    .foregroundStyle(UserSettingsStore.shared.bibleTextColor ?? Color.primary)
                    .accessibilityHidden(true)
            } else {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(UserSettingsStore.shared.bibleTextColor ?? Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: shrinksTitleToFit ? .infinity : nil)
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
