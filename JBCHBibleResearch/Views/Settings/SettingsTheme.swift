//
//  SettingsTheme.swift
//  JBCHBibleResearch
//
//  설정 화면 공통 테마 (2026-10-02 목업 채택: 설정 화면도 성경 읽기 테마·화면 모드·버튼 규격을 따른다).
//
//  이전에는 "모양" 탭의 색 선택기/미리보기를 빼면 설정 전체가 시스템 색의 `Form(.grouped)`/`List`라
//  테마를 바꿔도 설정 화면만 다른 앱처럼 보였다. 여기서 한 번에 입힌다.
//
//  규칙(모든 색은 `UserSettingsStore.bibleBackgroundColor/bibleTextColor`에서 파생):
//   - 페이지 배경 = 테마 배경색, 글자 = 테마 글자색, 구분선 = 글자색 14%, 카드(Form 행) = 글자색 6%.
//   - 강조(스위치 켜짐·배지·선택된 탭) = `BibleBarPalette.strong`(밝은 테마 #8F611D / 어두운 테마 #D1A35E).
//   - 테마 색이 지정되지 않았으면(nil) 시스템 색을 그대로 쓰고 강조색만 바꾼다.
//   - 한계: Stepper/ColorPicker/드롭다운 메뉴는 시스템이 그려 테마색을 못 입히고 라이트/다크만 따른다.
//

import SwiftUI

// MARK: - 색 헬퍼

enum SettingsThemeColors {
    /// 설정 안의 삭제·경고 글자/아이콘색. 밝은 테마는 와인, 어두운 테마는 어두운 배경용 와인.
    static func destructive(isDarkBackground: Bool) -> Color {
        isDarkBackground ? JBCHCategoryPalette.wineOnDark : JBCHCategoryPalette.wine
    }

    /// 테마 배경의 휘도 판정(`BibleBarPalette`와 같은 식). 배경이 없으면 시스템 화면 모드.
    static func isDarkBackground(environment: EnvironmentValues, colorScheme: ColorScheme) -> Bool {
        if let background = UserSettingsStore.shared.bibleBackgroundColor {
            let resolved = background.resolve(in: environment)
            return 0.2126 * Double(resolved.red) + 0.7152 * Double(resolved.green) + 0.0722 * Double(resolved.blue) < 0.5
        }
        return colorScheme == .dark
    }
}

// MARK: - 컨테이너(Form/List) 테마

private struct SettingsThemedFormModifier: ViewModifier {
    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let settings = UserSettingsStore.shared
        let palette = BibleBarPalette(environment: environment, colorScheme: colorScheme)
        if let background = settings.bibleBackgroundColor {
            let text = settings.bibleTextColor ?? Color.primary
            content
                .scrollContentBackground(.hidden)
                .background(background)
                .foregroundStyle(text)
                .listRowSeparatorTint(text.opacity(0.14))
                .tint(palette.strong)
                #if os(iOS)
                // iPad 시트의 상단/하단 탭 막대도 테마 배경에 맞춘다.
                .toolbarBackground(background, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                #endif
        } else {
            content.tint(palette.strong)
        }
    }
}

/// 하위 탭 막대(`SettingsCapsuleTabs`)가 `Form` 바깥(VStack)에 있어서 그 영역 배경도 테마색으로 칠한다.
private struct SettingsThemedBackdropModifier: ViewModifier {
    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let settings = UserSettingsStore.shared
        let palette = BibleBarPalette(environment: environment, colorScheme: colorScheme)
        if let background = settings.bibleBackgroundColor {
            content
                .background(background.ignoresSafeArea())
                .foregroundStyle(settings.bibleTextColor ?? Color.primary)
                .tint(palette.strong)
        } else {
            content.tint(palette.strong)
        }
    }
}

/// 내비게이션 바(iOS)/창 툴바(macOS) 배경을 테마 배경에 맞춘다(다른 화면 파일의 `ThemedNavigationBarBackgroundModifier`와 같은 휘도 판정).
private struct SettingsThemedBarModifier: ViewModifier {
    @Environment(\.self) private var environment

    func body(content: Content) -> some View {
        if let color = UserSettingsStore.shared.bibleBackgroundColor {
            let resolved = color.resolve(in: environment)
            let isDark = 0.2126 * Double(resolved.red) + 0.7152 * Double(resolved.green) + 0.0722 * Double(resolved.blue) < 0.5
            #if os(iOS)
            content
                .toolbarBackground(color, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(isDark ? .dark : .light, for: .navigationBar)
            #elseif os(macOS)
            content
                .toolbarBackground(color, for: .windowToolbar)
                .toolbarBackground(.visible, for: .windowToolbar)
                .toolbarColorScheme(isDark ? .dark : .light, for: .windowToolbar)
            #else
            content
            #endif
        } else {
            content
        }
    }
}

/// iOS push 화면의 제목 — 다른 기능 화면과 같은 성곡 세리프 17pt를 가운데에 둔다. macOS엔 제목 줄이 없어 아무것도 안 한다.
private struct SettingsNavigationPageModifier: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.custom(SpecialPurposeFonts.titleSerif, size: 17, relativeTo: .title3))
                        .foregroundStyle(UserSettingsStore.shared.bibleTextColor ?? Color.primary)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .modifier(SettingsThemedBarModifier())
        #else
        content.navigationTitle(title)
        #endif
    }
}

extension View {
    /// 설정 `Form`/`List`에 테마 배경·글자·구분선·강조색을 입힌다. `.formStyle(.grouped)` 다음에 붙인다.
    func settingsThemedForm() -> some View { modifier(SettingsThemedFormModifier()) }

    /// `Form` 밖(하위 탭 막대를 포함한 VStack) 배경까지 테마색으로 칠한다.
    func settingsThemedBackdrop() -> some View { modifier(SettingsThemedBackdropModifier()) }

    /// `Section { } header: { }` 전체에 붙여 행 배경을 테마 카드색(글자색 6%)으로 바꾼다.
    ///
    /// 조건 분기를 가진 `ViewModifier`로 감싸면 `Form`이 `Section` 경계를 못 알아볼 수 있어, `listRowBackground(_:)`(옵셔널 허용)를 직접 호출한다.
    /// `Form`/`List` 컨테이너에 걸어서는 행에 적용되지 않아 `Section`마다 붙인다. 배경 테마가 없으면 nil이라 시스템 기본.
    func settingsRowBackground() -> some View {
        let settings = UserSettingsStore.shared
        let card: Color? = settings.bibleBackgroundColor == nil ? nil : (settings.bibleTextColor ?? Color.primary).opacity(0.06)
        return listRowBackground(card)
    }

    /// 내비게이션 바/창 툴바 배경을 테마색으로.
    func settingsThemedBar() -> some View { modifier(SettingsThemedBarModifier()) }

    /// push되는 설정 화면의 제목(성곡 세리프, 인라인)과 테마 바.
    func settingsNavigationPage(_ title: String) -> some View { modifier(SettingsNavigationPageModifier(title: title)) }
}

// MARK: - 캡슐 탭 (시스템 세그먼트 Picker 대체)

/// 성경 조회 막대와 같은 버튼 규격(`BibleBarButtonStyle`)의 캡슐형 탭. 선택된 항목은 강조(primary), 나머지는 글자색 10% 채움.
/// 시스템 `.segmented` Picker는 테마색을 못 입혀 대체한다.
struct SettingsCapsuleTabs<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    /// true면 폭을 꽉 채워 균등 분할(설정 폼 안의 선택지), false면 글자 폭만큼(상단 하위 탭).
    var fillsWidth = false

    var body: some View {
        #if os(iOS)
        let height: CGFloat = 40, radius: CGFloat = 10, fontSize: CGFloat = 15
        #else
        let height: CGFloat = BibleBarMetrics.height, radius: CGFloat = BibleBarMetrics.radius, fontSize: CGFloat = 13
        #endif
        HStack(spacing: 6) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isSelected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: fillsWidth ? .infinity : nil)
                }
                .buttonStyle(BibleBarButtonStyle(kind: isSelected ? .primary : .secondary, height: height, cornerRadius: radius, fontSize: fontSize))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }
}
