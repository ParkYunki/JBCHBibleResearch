//
//  SermonSettingsTab.swift
//  JBCHBibleResearch
//
//  [2026-11-14 내 설교 고도화] 설정 > 설교.
//  모두 이 기기에만 저장한다(UserDefaults) — iCloud로 동기화하지 않는다. 기기마다 키보드·화면이 달라서다.
//  - 설교 인용 번역본(구절 치환에 쓰는 번역본, 성경 조회 번역본과 별개)
//  - 인라인 치환 시 출처 표기 방식
//  - 구절 치환 단축키(말씀구절 스타일 ⌃R / 현재 스타일 유지 ⌃T 기본)
//  - 분당 글자 수(예상 설교 시간), 뷰어 화면 꺼짐 방지
//

import SwiftUI
import SwiftData
import BibleResearchModels

struct SermonSettingsTab: View {
    @Query(sort: \TranslationRegistry.displayName) private var translations: [TranslationRegistry]

    @AppStorage(SermonPrefs.quoteVersionCode) private var quoteVersionCode = ""
    @AppStorage(SermonPrefs.citationMode) private var citationMode = "abbr"
    @AppStorage(SermonPrefs.charsPerMinute) private var charsPerMinute = SermonPrefs.defaultCharsPerMinute
    @AppStorage(SermonPrefs.viewerKeepAwake) private var keepAwake = true

    @AppStorage(SermonPrefs.verseStyleKey) private var verseStyleKey = "r"
    @AppStorage(SermonPrefs.verseStyleModifier) private var verseStyleModifier = SermonShortcutModifier.control.rawValue
    @AppStorage(SermonPrefs.verseInlineKey) private var verseInlineKey = "t"
    @AppStorage(SermonPrefs.verseInlineModifier) private var verseInlineModifier = SermonShortcutModifier.control.rawValue

    private static let letters = Array("abcdefghijklmnopqrstuvwxyz").map(String.init)

    private var enabledTranslations: [TranslationRegistry] { translations.filter(\.isEnabled) }

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "인용 번역본"), selection: $quoteVersionCode) {
                    Text(String(localized: "앱 언어의 기본 번역본")).tag("")
                    ForEach(enabledTranslations, id: \.code) { translation in
                        Text(translation.displayName).tag(translation.code)
                    }
                }
                Picker(String(localized: "출처 표기"), selection: $citationMode) {
                    Text(String(localized: "(요 3:16)")).tag("abbr")
                    Text(String(localized: "(요한복음 3:16)")).tag("full")
                    Text(String(localized: "표기 안 함")).tag("none")
                }
            } header: {
                Label(String(localized: "구절 인용"), systemImage: "text.quote")
            } footer: {
                Text(String(localized: "설교 본문에서 ‘요 3:16’ 같은 표기를 구절로 바꿀 때 쓰는 번역본과 출처 표기입니다. 성경 조회 화면의 번역본과는 따로 정합니다."))
            }
            .settingsRowBackground()

            Section {
                shortcutRow(
                    title: String(localized: "말씀구절 스타일로 치환"),
                    key: $verseStyleKey, modifier: $verseStyleModifier,
                    mode: .verseStyle
                )
                shortcutRow(
                    title: String(localized: "현재 스타일 유지하며 치환"),
                    key: $verseInlineKey, modifier: $verseInlineModifier,
                    mode: .inline
                )
            } header: {
                Label(String(localized: "구절 치환 단축키"), systemImage: "keyboard")
            } footer: {
                Text(String(localized: "하드웨어 키보드에서 쓰는 단축키입니다. 에디터에서 성경 구절 표기를 선택하거나 그 옆에 커서를 두고 누릅니다. 우클릭(길게 누르기) 메뉴에도 같은 항목이 있습니다."))
            }
            .settingsRowBackground()

            Section {
                Stepper(value: $charsPerMinute, in: 100...600, step: 10) {
                    LabeledContent(String(localized: "분당 글자 수"), value: "\(charsPerMinute)")
                }
                Toggle(String(localized: "뷰어에서 화면 꺼짐 방지"), isOn: $keepAwake)
            } header: {
                Label(String(localized: "분량 · 뷰어"), systemImage: "clock")
            } footer: {
                Text(String(localized: "예상 설교 시간은 글자 수(공백 포함) ÷ 분당 글자 수로 계산합니다. 기본값은 \(SermonPrefs.defaultCharsPerMinute)자입니다."))
            }
            .settingsRowBackground()
        }
        .formStyle(.grouped)
        .settingsThemedForm()
    }

    /// 키(a–z) + 수정키 선택 한 줄과, 겹침 안내.
    @ViewBuilder
    private func shortcutRow(
        title: String, key: Binding<String>, modifier: Binding<String>,
        mode: SermonVerseSubstituteMode
    ) -> some View {
        let current = SermonShortcut.load(mode: mode)
        let otherShortcut = SermonShortcut.load(mode: mode == .verseStyle ? .inline : .verseStyle)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Picker(String(localized: "수정키"), selection: modifier) {
                    ForEach(SermonShortcutModifier.allCases) { option in Text(option.symbol).tag(option.rawValue) }
                }
                .labelsHidden()
                .fixedSize()
                Picker(String(localized: "키"), selection: key) {
                    ForEach(Self.letters, id: \.self) { letter in Text(letter.uppercased()).tag(letter) }
                }
                .labelsHidden()
                .fixedSize()
                Text(current.label)
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.11), in: RoundedRectangle(cornerRadius: 5))
            }
            if let note = current.conflictNote(otherThan: otherShortcut) {
                Label(note, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(SermonTheme.warning)
            }
        }
    }
}
