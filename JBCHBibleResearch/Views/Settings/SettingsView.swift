//
//  SettingsView.swift
//  JBCHBibleResearch
//
//  환경설정 화면 — macOS는 `Settings { SettingsView() }` Scene에 얹혀 표준 환경설정
//  창(고정 크기)으로 뜬다. iOS엔 `Settings` Scene이 없어 "더보기" 진입점에서
//  시트(`SettingsHostView`)나 목록 화면(`SettingsHomeView`)으로 띄운다.
//
//  최상위는 "일반"/"성경"(+ DEBUG 전용 "개발자") 탭이고, 각각 하위 탭을 둔다.
//  UI만 있는 항목: 단축키(재지정 불가, 고정 목록만 표시). 나머지 항목은 실제 동작에 연결돼 있다.
//  환경설정 화면 자체의 메뉴/타이틀은 시스템 기본 글꼴·보통 크기를 쓴다(macOS는 `Settings`
//  Scene에 `.appDefaultFont()`를 붙이지 않고, iOS는 `SettingsHostView`에서 `.font(.body)` 지정).
//  "모양" 탭의 성경 조회 본문 글꼴(UserSettingsStore.bibleFontName)과는 별개다.
//

import SwiftUI
import SwiftData
import BibleResearchModels
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

// 최상위는 "일반"/"성경"(+ DEBUG 전용 "개발자")의 2단 구조이고, 하위 탭 전환은
// `GeneralSettingsGroup`/`BibleSettingsGroup`이 담당한다.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsGroup()
                .tabItem { Label("일반", systemImage: "gearshape") }
            BibleSettingsGroup()
                .tabItem { Label("성경", systemImage: "book.closed") }
            // DEBUG 전용 — 개요 화면에서 작성한 서식(RTF)을 배포용 시드 파일로 내보낸다
            // (OutlineSeedExporter.swift 참고). 배포 빌드에서는 이 탭 자체가 빠진다.
            #if DEBUG
            DeveloperSettingsTab()
                .tabItem { Label("개발자", systemImage: "hammer") }
            #endif
        }
        #if os(macOS)
        .frame(width: 560, height: 480)
        #endif
    }
}

/// 일반 설정의 하위 탭(기본/라이센스/단축키)을 세그먼트 Picker로 전환한다.
/// macOS에서는 최상위 `TabView`만 환경설정 창 전용 렌더링을 받아 중첩한 `TabView`는
/// 탭 전환 UI가 그려지지 않으므로, `TabView`를 중첩하지 않고 @State 선택값으로 전환한다.
private struct GeneralSettingsGroup: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case basic, license, shortcuts
        var id: Self { self }
        var title: String {
            switch self {
            case .basic: return "기본"
            case .license: return "라이센스"
            case .shortcuts: return "단축키"
            }
        }
    }

    @State private var selection: Tab = .basic

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selection) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top])

            Group {
                switch selection {
                case .basic:
                    GeneralSettingsTab()
                case .license:
                    LicenseSettingsTab()
                case .shortcuts:
                    ShortcutsSettingsTab()
                }
            }
        }
    }
}

/// 성경 설정의 하위 탭(번역본/모양/복사 형식)을 `GeneralSettingsGroup`과 같은 이유로
/// 세그먼트 Picker로 전환한다.
private struct BibleSettingsGroup: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case translations, appearance, copyFormat
        var id: Self { self }
        var title: String {
            switch self {
            case .translations: return "번역본"
            case .appearance: return "모양"
            case .copyFormat: return "복사 형식"
            }
        }
    }

    @State private var selection: Tab = .translations

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selection) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top])

            Group {
                switch selection {
                case .translations:
                    TranslationsSettingsTab()
                case .appearance:
                    AppearanceSettingsTab()
                case .copyFormat:

                    BibleCopyFormatSettingsTab()
                }
            }
        }
    }
}

/// iPadOS/iPhone "더보기" 진입점 — macOS의 `Settings` Scene과 달리 별도 창 개념이
/// 없어 시트로 감싸고 닫기 버튼을 붙인다.
///
/// RootView의 `.appDefaultFont()`(내장 Paperlogy 강제)를 상속하지 않도록 `.font(.body)`로
/// 시스템 기본 글꼴/보통 크기를 명시해 macOS `Settings` Scene과 동작을 맞춘다.
struct SettingsHostView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SettingsView()
                .navigationTitle("설정")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("닫기") { dismiss() }
                    }
                }
        }
        .font(.body)
    }
}

// MARK: - 일반

/// iPhone "더보기 > 설정" 진입 화면 — "일반"/"성경"을 `Section` 헤더로 두고 하위 항목
/// (기본/라이센스, 번역본/모양/복사 형식)을 바로 나열하는 평평한 2단 구조다. "개발자"는
/// DEBUG 전용 단일 항목이다.
/// `SettingsView`(최상위 `TabView`)를 그대로 push하면 하단 탭바가 이중으로 뜨므로 iPhone은
/// 이 화면을 쓴다. macOS(`Settings` Scene)와 iPadOS(`.sheet`)는 그 문제가 없어 `SettingsView`를 쓴다.
struct SettingsHomeView: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    GeneralSettingsTab()
                        .navigationTitle("기본")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                } label: {
                    SettingsCategoryRow(title: "기본", systemImage: "gearshape.fill", tint: JBCHCategoryPalette.wood)
                }
                NavigationLink {
                    LicenseSettingsTab()
                        .navigationTitle("라이센스")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                } label: {
                    SettingsCategoryRow(title: "라이센스", systemImage: "checkmark.seal.fill", tint: JBCHCategoryPalette.shelfSlate)
                }
                // 단축키(하드웨어 키보드 단축키)는 아이폰에 해당하지 않아 이 목록에서만 뺐다.
                // macOS/iPadOS의 `GeneralSettingsGroup`에는 "단축키" 세그먼트가 남아 있다.
            } header: {
                // `Section("일반")`처럼 문자열을 주면 작은 기본 헤더 스타일이 적용돼,
                // 크기/굵기를 키우려고 커스텀 `header:` 뷰를 쓴다.
                Text("일반")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
            }

            Section {
                NavigationLink {
                    TranslationsManagementTab()
                        .navigationTitle("번역본")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                } label: {
                    SettingsCategoryRow(title: "번역본", systemImage: "books.vertical.fill", tint: JBCHCategoryPalette.navy)
                }
                NavigationLink {
                    AppearanceSettingsTab()
                        .navigationTitle("모양")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                } label: {
                    SettingsCategoryRow(title: "모양", systemImage: "paintpalette.fill", tint: JBCHCategoryPalette.gold)
                }
                NavigationLink {
                    BibleCopyFormatSettingsTab()
                        .navigationTitle("복사 형식")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                } label: {
                    SettingsCategoryRow(title: "복사 형식", systemImage: "doc.on.doc.fill", tint: JBCHCategoryPalette.wine)
                }
            } header: {
                // 위 "일반" 섹션 헤더와 같은 이유·같은 스타일.
                Text("성경")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
            }

            #if DEBUG
            Section {
                NavigationLink {
                    DeveloperSettingsTab()
                        .navigationTitle("개발자")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                } label: {
                    SettingsCategoryRow(title: "개발자", systemImage: "hammer.fill", tint: Color(white: 0.35))
                }
            }
            #endif
        }
        .navigationTitle("설정")
        // 기본 표시 모드는 뒤로가기 버튼 아래에 큰 제목을 별도 줄로 그려 버튼 옆 공간이
        // 낭비되므로 `.inline`으로 한 줄에 합친다(macOS엔 이 모디파이어가 없어 `#if os(iOS)`).
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // `SettingsHostView`와 같은 이유 — NavigationLink push로 열리므로 시스템 기본 글꼴로 되돌린다.
        .font(.body)
    }
}

/// 위 `SettingsHomeView`의 각 행 — iOS "설정" 앱과 같은 "색이 있는 둥근 사각형
/// 배경 위 흰색 SF Symbol" 아이콘 스타일. 아이콘마다 시스템이 주는 기본 크기를
/// 그대로 쓰지 않고 고정 프레임(29pt, iOS 설정 앱 실측과 동일)으로 통일해
/// 목록 전체의 세로 정렬이 흔들리지 않게 한다.
private struct SettingsCategoryRow: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint.gradient)
                .frame(width: 29, height: 29)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                }
        }
    }
}

// MARK: - 일반

// "일반 > 기본" 하위 탭 — 앱 이름/버전 정보와 시작 옵션.
private struct GeneralSettingsTab: View {
    @State private var settings = UserSettingsStore.shared

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    // 사용자에게 보이는 앱 이름 — 앱 번들 표시 이름(project.pbxproj의
                    // INFOPLIST_KEY_CFBundleDisplayName)과 함께 바꿔야 한다.
                    Text("엠마오 성경 연구")
                        .font(.headline)
                    Text("버전 \(versionString) (\(buildString))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("앱 정보", systemImage: "info.circle")
            }

            Section {
                Toggle("시작 시 마지막으로 보던 화면 열기", isOn: $settings.openLastScreenOnLaunch)
            } header: {
                Label("시작 옵션", systemImage: "power")
            }

            // "기본 성경 번역본" 피커는 두지 않는다 — 성경 조회 기본값은 `TranslationsSettingsTab`의
            // "성경 조회 기본 표시" 목록(순서 포함)이 전담한다. `UserSettingsStore.defaultTranslationCode`와
            // 그 값을 읽는 폴백 경로(`BibleReadingViewModel.loadAvailableTranslations`/
            // `TranslationsSettingsTab.seedDefaultDisplayedCodesIfNeeded`)는 표시 목록이 아직 비어 있는
            // 경우를 위한 안전한 폴백으로 남겨 뒀다.
        }
        .formStyle(.grouped)
    }

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildString: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}

// MARK: - 번역본

private struct TranslationsSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @State private var translations: [TranslationRegistry] = []
    @State private var settings = UserSettingsStore.shared

    @State private var isImportSheetPresented = false

    var body: some View {
        Form {
            Section {
                ForEach(translations, id: \.id) { translation in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(translation.displayName)
                            Text(statusText(for: translation))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        // 활성화 토글 — 꺼진 번역본은 검색과 성경 조회 표시에서 제외된다. 삭제와 달리 번들
                        // 번역본도 끌 수 있다. 끄면 `setEnabled(_:for:)`가 "성경 조회 기본 표시" 목록에서도 뺀다.
                        Toggle("", isOn: Binding(
                            get: { translation.isEnabled },
                            set: { setEnabled($0, for: translation) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        if !translation.isBundled {
                            Button(role: .destructive) {
                                delete(translation)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            } header: {
                Label("설치된 번역본", systemImage: "text.book.closed")
            }

            // "성경 조회 기본 표시" — `UserSettingsStore.defaultDisplayedTranslationCodes`에 최대 3개를
            // 순서대로 저장하며, 맨 위가 기본값이다. 이 배열 순서가 그대로 성경 조회 컬럼 순서가 된다
            // (`BibleReadingViewModel.loadAvailableTranslations()`가 배열 순서를 따른다).
            // 토글이 켜져 있음 = 실제로 표시됨이 되도록 최초 진입 시 `seedDefaultDisplayedCodesIfNeeded()`가
            // 목록을 미리 채운다.
            // `Form` 안에서는 `.onMove`/`.onDelete`의 드래그·스와이프 UI가 나타나지 않으므로(특히 macOS
            // `.formStyle(.grouped)`), 버튼 탭으로 표시/숨김·순서 변경을 구현했다.
            Section {
                ForEach(allTranslationsOrderedForDisplaySettings, id: \.id) { translation in
                    translationDisplayRow(translation)
                }
            } header: {
                Label("성경 조회 기본 표시", systemImage: "eye")
            } footer: {
                Text("최대 3개까지 표시할 수 있습니다. 맨 위가 기본값입니다. 눈 아이콘으로 표시 여부를, 위/아래 화살표로 순서를 바꿀 수 있습니다.")
            }

            Section {
                Button {
                    isImportSheetPresented = true
                } label: {
                    Label("번역본 추가...", systemImage: "plus.circle")
                }
            } footer: {

                Text("sqlite, bdb 파일을 업로드할 수 있습니다.\n\n이 앱은 성경 번역본을 제공하거나 배포하지 않습니다. 사용자가 적법하게 보유하거나 사용할 권한이 있는 파일만 가져와주십시오. 가져온 데이터는 이 기기에만 저장되며, 다른 사용자와 공유되지 않습니다.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            reload()
            seedDefaultDisplayedCodesIfNeeded()
        }
        .sheet(isPresented: $isImportSheetPresented) {
            TranslationImportSheet { _ in reload() }
        }
    }

    /// 표시 목록이 비어 있는 최초 진입 시, `BibleReadingViewModel`의 폴백 규칙(등록 순 +
    /// `defaultTranslationCode` 맨 앞, 최대 3개)과 같은 순서로 목록을 미리 저장해
    /// 토글 상태와 실제 표시 상태가 일치하게 한다.
    private func seedDefaultDisplayedCodesIfNeeded() {
        guard settings.defaultDisplayedTranslationCodes.isEmpty, !translations.isEmpty else { return }
        var ordered = translations
        if let preferredCode = settings.defaultTranslationCode,
           let index = ordered.firstIndex(where: { $0.code == preferredCode }) {
            let preferred = ordered.remove(at: index)
            ordered.insert(preferred, at: 0)
        }
        settings.defaultDisplayedTranslationCodes = Array(ordered.prefix(3).map(\.code))
    }

    private func statusText(for translation: TranslationRegistry) -> String {
        var parts = [translation.isBundled ? "번들" : "사용자 추가", translation.licenseType ?? "라이선스 미상"]
        if !translation.isBundled {
            parts.append(TranslationFileMaterializer.syncStatus(for: translation).label)
        }
        return parts.joined(separator: " · ")
    }

    /// 활성화된 번역본만 표시 후보로 삼는다 — 꺼둔 번역본은 먼저 다시 켜야 고를 수 있다.
    /// (아래 `orderedDisplayedTranslations`는 저장된 코드 순서대로 매핑하며, 삭제돼 없는 코드는
    /// `compactMap`이 건너뛴다.)
    private var enabledTranslations: [TranslationRegistry] {
        translations.filter(\.isEnabled)
    }

    private var orderedDisplayedTranslations: [TranslationRegistry] {
        let byCode = Dictionary(uniqueKeysWithValues: enabledTranslations.map { ($0.code, $0) })
        return settings.defaultDisplayedTranslationCodes.compactMap { byCode[$0] }
    }

    /// 아직 표시 목록에 없는 번역본 — 아래 통합 목록의 뒤쪽 절반에 쓴다.
    private var notYetDisplayedTranslations: [TranslationRegistry] {
        let shown = Set(settings.defaultDisplayedTranslationCodes)
        return enabledTranslations.filter { !shown.contains($0.code) }
    }

    /// 표시 중인 번역본(저장된 순서대로) 뒤에 표시하지 않는 번역본을 이어 붙인 통합 목록.
    private var allTranslationsOrderedForDisplaySettings: [TranslationRegistry] {
        orderedDisplayedTranslations + notYetDisplayedTranslations
    }

    /// 표시 중인 번역본은 순서 배지("기본")와 위/아래 화살표(인접 항목 `swapAt`)를,
    /// 표시하지 않는 번역본은 "표시" 눈 아이콘 버튼만 보여준다.
    @ViewBuilder
    private func translationDisplayRow(_ translation: TranslationRegistry) -> some View {
        let displayedIndex = settings.defaultDisplayedTranslationCodes.firstIndex(of: translation.code)
        HStack {
            Text(translation.displayName)
            if displayedIndex == 0 {
                // 맨 위 항목이 기본값임을 나타내는 배지.
                Text("기본")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color("AccentColor").opacity(0.15)))
                    .foregroundStyle(Color("AccentColor"))
            }
            Spacer()
            if let index = displayedIndex {
                Button {
                    moveDisplayedTranslation(from: index, to: index - 1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(index == 0)

                Button {
                    moveDisplayedTranslation(from: index, to: index + 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(index == settings.defaultDisplayedTranslationCodes.count - 1)

                Button {
                    removeDisplayedTranslation(code: translation.code)
                } label: {
                    Image(systemName: "eye.slash")
                }
                .buttonStyle(.borderless)
            } else {
                Button {
                    addDisplayedTranslation(translation)
                } label: {
                    Image(systemName: "eye")
                }
                .buttonStyle(.borderless)
                // 저장 배열에는 삭제된 번역본 코드가 남아 있을 수 있어, 배열 길이 대신 실제로 유효한
                // `orderedDisplayedTranslations.count`로 3개 제한을 판정한다.
                .disabled(orderedDisplayedTranslations.count >= 3)
            }
        }
    }

    /// 표시 중인 두 인접 항목을 맞바꾼다. 인덱스가 범위를 벗어나면 아무것도 하지 않는다.
    private func moveDisplayedTranslation(from index: Int, to newIndex: Int) {
        var codes = settings.defaultDisplayedTranslationCodes
        guard codes.indices.contains(index), codes.indices.contains(newIndex) else { return }
        codes.swapAt(index, newIndex)
        settings.defaultDisplayedTranslationCodes = codes
    }

    private func removeDisplayedTranslation(code: String) {
        settings.defaultDisplayedTranslationCodes.removeAll { $0 == code }
    }

    /// 최대 3개까지만 추가한다(호출부 `.disabled`와 별개로 방어적으로 다시 확인).
    private func addDisplayedTranslation(_ translation: TranslationRegistry) {
        guard settings.defaultDisplayedTranslationCodes.count < 3,
              !settings.defaultDisplayedTranslationCodes.contains(translation.code) else { return }
        settings.defaultDisplayedTranslationCodes.append(translation.code)
    }

    private func reload() {
        translations = (try? modelContext.fetch(FetchDescriptor<TranslationRegistry>(sortBy: [SortDescriptor(\.addedAt)]))) ?? []
    }

    /// "설치된 번역본" 토글의 구현. 끌 때 "성경 조회 기본 표시" 목록에서도 함께 빼며,
    /// 다시 켤 때 표시 목록에 자동으로 되돌리지는 않는다(사용자가 눈 아이콘으로 직접 고른다).
    private func setEnabled(_ isEnabled: Bool, for translation: TranslationRegistry) {
        translation.isEnabled = isEnabled
        if !isEnabled {
            removeDisplayedTranslation(code: translation.code)
        }
        try? modelContext.save()
    }

    private func delete(_ translation: TranslationRegistry) {
        // 로컬 캐시 파일도 함께 정리한다(best-effort). `TranslationsManagementTab.delete(_:)`와
        // 삭제 경로를 같게 유지해야 한쪽만 정리돼 디스크에 고아 파일이 남지 않는다.
        TranslationFileMaterializer.removeLocalCopy(for: translation)
        // 삭제된 번역본 코드가 "성경 조회 기본 표시" 목록에 남으면 "3개가 찼다"는 판정이
        // 계속되므로 함께 뺀다(이미 없는 코드여도 `removeAll`은 무동작).
        removeDisplayedTranslation(code: translation.code)
        modelContext.delete(translation)
        try? modelContext.save()
        reload()
    }
}

/// "더보기 > 설정 > 성경 > 번역본" 화면 — "성경 조회 기본 표시"(순서/노출), "번역본 추가...",
/// 표시 이름·라이선스 인라인 편집, 책이름표 언어 피커, 삭제를 한 화면에 통합했다.
/// `updateDisplayName`/`updateLicenseType`은 SwiftData `@Model`이 자동 관찰되므로
/// 타이핑마다 `reload()`를 부르지 않는다.
///
/// 삭제는 스와이프 대신, 번들이 아닌 행마다 항상 보이는 휴지통 버튼을 쓴다.
///
/// 동기화 상태는 부작용 없는 `TranslationFileMaterializer.syncStatus(for:)`만 표시한다
/// (화면을 열 때마다 `ensureMaterialized`로 파일 쓰기를 시도하지 않는다).
///
/// macOS `Settings` Scene/iPadOS `.sheet`는 편집 기능이 없는 `TranslationsSettingsTab`을 그대로 쓴다.
private struct TranslationsManagementTab: View {
    @Environment(\.modelContext) private var modelContext
    @State private var translations: [TranslationRegistry] = []
    @State private var settings = UserSettingsStore.shared
    @State private var isImportSheetPresented = false

    var body: some View {
        Form {
            Section {
                ForEach(allTranslationsOrderedForDisplaySettings, id: \.id) { translation in
                    translationDisplayRow(translation)
                }
            } header: {
                Label("성경 조회 기본 표시", systemImage: "eye")
            } footer: {
                Text("최대 3개까지 표시할 수 있습니다. 맨 위가 기본값입니다. 눈 아이콘으로 표시 여부를, 위/아래 화살표로 순서를 바꿀 수 있습니다.")
            }

            Section {
                ForEach(translations, id: \.id) { translation in
                    translationEditRow(translation)
                }
            } header: {
                Label("설치된 번역본", systemImage: "text.book.closed")
            }

            Section {
                Button {
                    isImportSheetPresented = true
                } label: {
                    Label("번역본 추가...", systemImage: "plus.circle")
                }
            } footer: {
                Text("sqlite, bdb 파일을 업로드할 수 있습니다.\n\n이 앱은 성경 번역본을 제공하거나 배포하지 않습니다. 사용자가 적법하게 보유하거나 사용할 권한이 있는 파일만 가져와주십시오. 가져온 데이터는 이 기기에만 저장되며, 다른 사용자와 공유되지 않습니다.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            reload()
            seedDefaultDisplayedCodesIfNeeded()
        }
        .sheet(isPresented: $isImportSheetPresented) {
            TranslationImportSheet { _ in reload() }
        }
    }

    /// 표시 이름/라이선스 인라인 편집 + 책이름표 언어 피커 + (번들이 아니면) 삭제 버튼.
    @ViewBuilder
    private func translationEditRow(_ translation: TranslationRegistry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("표시 이름", text: Binding(
                    get: { translation.displayName },
                    set: { updateDisplayName($0, for: translation) }
                ))
                .font(.headline)
                #if os(iOS)
                .textFieldStyle(.roundedBorder)
                #else
                .textFieldStyle(.plain)
                #endif

                // 활성화 토글 — `TranslationsSettingsTab`의 토글과 동일하게 동작한다(진입 경로가 달라 양쪽에 둔다).
                Toggle("", isOn: Binding(
                    get: { translation.isEnabled },
                    set: { setEnabled($0, for: translation) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)

                if !translation.isBundled {
                    Button(role: .destructive) {
                        delete(translation)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }

            Text(statusText(for: translation))
                .font(.caption2)
                .foregroundStyle(.secondary)

            TextField("라이선스(선택)", text: Binding(
                get: { translation.licenseType ?? "" },
                set: { updateLicenseType($0, for: translation) }
            ))
            .font(.caption)
            #if os(iOS)
            .textFieldStyle(.roundedBorder)
            #else
            .textFieldStyle(.plain)
            #endif

            Picker("책이름표 언어", selection: Binding(
                get: { translation.bookNameTableID },
                set: { setBookNameTable($0, for: translation) }
            )) {
                Text("한글 기본").tag(nil as String?)
                ForEach(BookNameTableProvider.shared.builtIn) { table in
                    Text(table.displayName).tag(table.id as String?)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    /// 타이핑마다 `reload()`를 부르지 않는다 — `registry`가 SwiftData `@Model`이라
    /// 값만 바꿔도 화면이 갱신된다.
    private func updateDisplayName(_ name: String, for registry: TranslationRegistry) {
        registry.displayName = name
        try? modelContext.save()
    }

    /// `reload()` 없이 즉시 반영. 빈 문자열은 nil로 정규화해 "라이선스 미상"으로 표시한다.
    private func updateLicenseType(_ license: String, for registry: TranslationRegistry) {
        let trimmed = license.trimmingCharacters(in: .whitespacesAndNewlines)
        registry.licenseType = trimmed.isEmpty ? nil : trimmed
        try? modelContext.save()
    }

    /// 번들 번역본도 책이름표 지정을 막지 않는다 — "번들은 항상 nil"이라는 규칙이
    /// 사용자 변경을 금지하는 근거는 아니다.
    private func setBookNameTable(_ tableID: String?, for registry: TranslationRegistry) {
        registry.bookNameTableID = tableID
        try? modelContext.save()
        reload()
    }

    private func statusText(for translation: TranslationRegistry) -> String {
        var parts = [translation.code, translation.isBundled ? "번들" : "사용자 추가"]
        if !translation.isBundled {
            parts.append(TranslationFileMaterializer.syncStatus(for: translation).label)
        }
        return parts.joined(separator: " · ")
    }

    /// 비활성 번역본은 "성경 조회 기본 표시" 후보에서 뺀다(아래 두 프로퍼티도 동일).
    private var enabledTranslations: [TranslationRegistry] {
        translations.filter(\.isEnabled)
    }

    private var orderedDisplayedTranslations: [TranslationRegistry] {
        let byCode = Dictionary(uniqueKeysWithValues: enabledTranslations.map { ($0.code, $0) })
        return settings.defaultDisplayedTranslationCodes.compactMap { byCode[$0] }
    }

    private var notYetDisplayedTranslations: [TranslationRegistry] {
        let shown = Set(settings.defaultDisplayedTranslationCodes)
        return enabledTranslations.filter { !shown.contains($0.code) }
    }

    private var allTranslationsOrderedForDisplaySettings: [TranslationRegistry] {
        orderedDisplayedTranslations + notYetDisplayedTranslations
    }

    @ViewBuilder
    private func translationDisplayRow(_ translation: TranslationRegistry) -> some View {
        let displayedIndex = settings.defaultDisplayedTranslationCodes.firstIndex(of: translation.code)
        HStack {
            Text(translation.displayName)
            if displayedIndex == 0 {
                Text("기본")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color("AccentColor").opacity(0.15)))
                    .foregroundStyle(Color("AccentColor"))
            }
            Spacer()
            if let index = displayedIndex {
                Button {
                    moveDisplayedTranslation(from: index, to: index - 1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(index == 0)

                Button {
                    moveDisplayedTranslation(from: index, to: index + 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(index == settings.defaultDisplayedTranslationCodes.count - 1)

                Button {
                    removeDisplayedTranslation(code: translation.code)
                } label: {
                    Image(systemName: "eye.slash")
                }
                .buttonStyle(.borderless)
            } else {
                Button {
                    addDisplayedTranslation(translation)
                } label: {
                    Image(systemName: "eye")
                }
                .buttonStyle(.borderless)
                .disabled(orderedDisplayedTranslations.count >= 3)
            }
        }
    }

    private func moveDisplayedTranslation(from index: Int, to newIndex: Int) {
        var codes = settings.defaultDisplayedTranslationCodes
        guard codes.indices.contains(index), codes.indices.contains(newIndex) else { return }
        codes.swapAt(index, newIndex)
        settings.defaultDisplayedTranslationCodes = codes
    }

    private func removeDisplayedTranslation(code: String) {
        settings.defaultDisplayedTranslationCodes.removeAll { $0 == code }
    }

    private func addDisplayedTranslation(_ translation: TranslationRegistry) {
        guard settings.defaultDisplayedTranslationCodes.count < 3,
              !settings.defaultDisplayedTranslationCodes.contains(translation.code) else { return }
        settings.defaultDisplayedTranslationCodes.append(translation.code)
    }

    private func seedDefaultDisplayedCodesIfNeeded() {
        guard settings.defaultDisplayedTranslationCodes.isEmpty, !translations.isEmpty else { return }
        var ordered = translations
        if let preferredCode = settings.defaultTranslationCode,
           let index = ordered.firstIndex(where: { $0.code == preferredCode }) {
            let preferred = ordered.remove(at: index)
            ordered.insert(preferred, at: 0)
        }
        settings.defaultDisplayedTranslationCodes = Array(ordered.prefix(3).map(\.code))
    }

    private func reload() {
        translations = (try? modelContext.fetch(FetchDescriptor<TranslationRegistry>(sortBy: [SortDescriptor(\.addedAt)]))) ?? []
    }

    /// 끌 때 "성경 조회 기본 표시" 목록에서도 함께 뺀다.
    private func setEnabled(_ isEnabled: Bool, for translation: TranslationRegistry) {
        translation.isEnabled = isEnabled
        if !isEnabled {
            removeDisplayedTranslation(code: translation.code)
        }
        try? modelContext.save()
    }

    /// 번들 번역본은 삭제 대상이 아니다 — UI에서도 삭제 버튼을 숨기지만 여기서도 방어적으로 막는다.
    private func delete(_ translation: TranslationRegistry) {
        guard !translation.isBundled else { return }
        TranslationFileMaterializer.removeLocalCopy(for: translation)
        removeDisplayedTranslation(code: translation.code)
        modelContext.delete(translation)
        try? modelContext.save()
        reload()
    }
}

// MARK: - 모양

private struct AppearanceSettingsTab: View {
    @State private var settings = UserSettingsStore.shared
    // hex 추출용 `EnvironmentValues` — 배경색/글자색 `ColorPicker` 저장에 쓴다.
    @Environment(\.self) private var environment

    /// 플랫폼별 API(`NSFontManager`/`UIFont`)로 구한 시스템 글꼴 목록. 내장 Paperlogy는
    /// `BundledFonts.entries`로 맨 위에 따로 보여주므로 중복을 피하려고 "Paperlogy"로
    /// 시작하는 항목은 걸러낸다.
    private static let fontFamilies: [String] = {
        #if os(macOS)
        return NSFontManager.shared.availableFontFamilies.sorted().filter { !$0.hasPrefix("Paperlogy") }
        #elseif os(iOS)
        return UIFont.familyNames.sorted().filter { !$0.hasPrefix("Paperlogy") }
        #else
        return []
        #endif
    }()

    var body: some View {
        Form {
            Section {
                // 고를 때마다 테마 색상 쪽도 함께 정리해야 해서(`selectColorScheme(_:)`) 커스텀 Binding을 쓴다.
                Picker(
                    "화면 모드",
                    selection: Binding(
                        get: { settings.colorSchemePreference },
                        set: { settings.selectColorScheme($0) }
                    )
                ) {
                    ForEach(UserSettingsStore.ColorSchemePreference.allCases) { preference in
                        Text(preference.displayName).tag(preference)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Label("화면 모드", systemImage: "circle.lefthalf.filled")
            }

            // 화면 모드를 고르면 테마 색상이 풀리고(`selectColorScheme`), 테마 색상을 고르면
            // 화면 모드가 맞춰지므로(`applyThemeMode`) 연동 관계가 보이도록 화면 모드 바로 아래 둔다.
            Section {
                Picker(
                    "테마 색상",
                    selection: Binding(
                        get: { settings.bibleThemeModePreference },
                        set: { newMode in
                            guard let newMode else { return }
                            settings.applyThemeMode(newMode, systemColorScheme: environment.colorScheme)
                        }
                    )
                ) {
                    ForEach(UserSettingsStore.BibleThemeModePreference.allCases) { mode in
                        Text(mode.displayName).tag(Optional(mode))
                    }
                }
                .pickerStyle(.segmented)
                // 라벨을 숨긴다 — macOS는 세그먼트 옆에 라벨을 그대로 보여줘 Section 헤더("테마 색상")와
                // 겹치기 때문(접근성 라벨은 유지된다).
                .labelsHidden()

                ColorPicker(
                    "배경색 직접 선택",
                    selection: Binding(
                        get: { settings.bibleBackgroundColor ?? Color.white },
                        set: {
                            settings.bibleBackgroundColorHex = $0.hexString(in: environment)
                            // 임의 색을 직접 고르면 라이트/다크/자동 어디에도 해당하지 않으므로 커스텀으로 표시.
                            settings.markThemeModeAsCustom()
                        }
                    ),
                    supportsOpacity: false
                )

                ColorPicker(
                    "글자색 직접 선택",
                    selection: Binding(
                        get: { settings.bibleTextColor ?? Color.primary },
                        set: {
                            settings.bibleTextColorHex = $0.hexString(in: environment)
                            // 배경색 ColorPicker와 같은 이유.
                            settings.markThemeModeAsCustom()
                        }
                    ),
                    supportsOpacity: false
                )
            } header: {
                Label("테마 색상", systemImage: "paintpalette")
            }

            // 아이폰에서만 미리보기를 표시 설정 위에 둔다. 맥OS/아이패드는 기존 순서(표시 설정 → 미리보기).
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .phone {
                previewSection
                displaySettingsSection
            } else {
                displaySettingsSection
                previewSection
            }
            #else
            displaySettingsSection
            previewSection
            #endif
        }
        .formStyle(.grouped)
    }

    /// "성경 조회 표시" Section. 아이폰에서만 미리보기와 순서를 바꿀 수 있도록
    /// `body`에서 computed property로 분리했다.
    @ViewBuilder
    private var displaySettingsSection: some View {
        // `RichTextEditor`(메모/개요 에디터)는 자체 서식 도구모음이 있어 이 설정의 적용 범위에 포함하지 않는다.
        Section {
            // 내장 Paperlogy 9종을 맨 위에, 그 아래 "시스템 기본", 이어서 설치된 나머지 글꼴 순.
            // 기본값은 내장 Paperlogy(`UserSettingsStore.bibleFontName`)이며 "시스템 기본"도 고를 수 있다.
            Picker("글꼴", selection: $settings.bibleFontName) {
                Section("내장 기본 글꼴") {
                    ForEach(BundledFonts.entries) { entry in
                        Text(entry.displayName).tag(entry.postScriptName)
                    }
                    // `bibleFontName`은 `hanjaFontName`(한자 주석 폰트)과 별개 설정이라 한자 주석 표시에 영향이 없다.
                    Text("조선궁서체").tag(SpecialPurposeFonts.hanja)
                }
                Section("시스템") {
                    Text("시스템 기본").tag("System")
                    ForEach(Self.fontFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
            }

            // 아이폰 폭에서는 세 컨트롤을 한 `HStack`에 넣으면 `Stepper`가 값 텍스트보다 +/- 버튼을
            // 우선해 값이 잘리므로, 아이폰에서만 "절 간격" 행처럼 한 줄 전체 폭을 쓰는 세로 배치를 쓴다.
            // 그 외(맥OS/아이패드)는 3열 가로 배치.
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .phone {
                fullWidthSizeControl(title: "본문 크기", value: $settings.bibleBodyFontSize, range: 12...32)
                fullWidthSizeControl(title: "절 번호 크기", value: $settings.bibleVerseNumberFontSize, range: 8...24)
                fullWidthSizeControl(title: "줄간격", value: $settings.bibleLineSpacing, range: 0...16)
            } else {
                compactSizeControlRow
            }
            #else
            compactSizeControlRow
            #endif

            // `bibleLineSpacing`(한 절 안 줄바꿈 간격)과 달리 절과 절 사이 간격
            // (`TranslationColumnView.columnScrollView`의 `LazyVStack(spacing:)`)이며, 더 넓게 벌릴 수 있도록 0...30 범위.
            HStack {
                Text("절 간격")
                Spacer()
                Stepper(value: $settings.bibleVerseSpacing, in: 0...30, step: 1) {
                    Text("\(Int(settings.bibleVerseSpacing))pt")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .fixedSize()
            }

            // 팔레트 Picker 없이 "테마 색상" Section의 직접 선택 ColorPicker만 쓴다. 기본 색으로의 복귀는
            // `UserSettingsStore.selectColorScheme(_:)`가 처리한다(배경/글자 hex를 빈 문자열로, `bibleThemeModePreference`를 nil로).

            // 개역한글 컬럼의 한자 주석 표시 방식 3단 Picker. 기본값은 "끄기"라 기존 사용자에게
            // 낯선 한자가 갑자기 나타나지 않는다.
            Picker("한자 주석 표시", selection: $settings.hanjaDisplayMode) {
                ForEach(UserSettingsStore.HanjaDisplayMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            // 지금은 번들 폰트(조선궁서체) 하나뿐이라 시스템 기본과의 선택 — 폰트가 추가되면 항목만 늘리면 된다.
            // 한자 주석 표시가 꺼져 있으면 의미가 없으므로 비활성화한다.
            Picker("한자 폰트", selection: $settings.hanjaFontName) {
                Text("조선궁서체 (기본)").tag(SpecialPurposeFonts.hanja)
                Text("시스템 기본").tag("System")
            }
            .disabled(settings.hanjaDisplayMode == .off)
        } header: {
            Label("성경 조회 표시", systemImage: "textformat")
        }
    }

    /// "미리보기" Section.
    @ViewBuilder
    private var previewSection: some View {
        Section {
            previewRow
        } header: {
            Label("미리보기", systemImage: "eye")
        }
    }

    private var previewRow: some View {
        // `TranslationColumnView.VerseRow`와 같이 `.firstTextBaseline`으로 정렬한다 — 작은 뱃지 글꼴과
        // 큰 본문 글꼴은 폰트 어센더 차이로 잉크 시작 높이가 달라 베이스라인 기준 정렬이 필요하다.
        // 실제 조회 화면과 다르면 미리보기로 확인하는 의미가 없다.
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // 절 번호 뱃지 모양(글자색/배경색을 서로 뒤집어 쓰는 공식)을 `TranslationColumnView.VerseRow`와 동일하게 맞춘다.
            Text("1")
                .font(settings.bibleVerseNumberFont.weight(.semibold))
                .foregroundStyle(settings.bibleBackgroundColor ?? .white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .frame(minWidth: 20)
                .background(
                    settings.bibleTextColor ?? JBCHCategoryPalette.navy,
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
            Text("태초에 하나님이 천지를 창조하시니라")
                .font(settings.bibleBodyFont)
                .foregroundStyle(settings.bibleTextColor ?? Color.primary)
                .lineSpacing(settings.bibleLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
        }
        // 설정한 배경색을 반영하고, 미설정(nil)이면 투명.
        .padding(8)
        .background(settings.bibleBackgroundColor ?? Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// macOS/iPadOS용 3열 배치.
    @ViewBuilder
    private var compactSizeControlRow: some View {
        HStack(alignment: .top, spacing: 20) {
            compactSizeControl(
                title: "본문 크기",
                value: $settings.bibleBodyFontSize,
                range: 12...32
            )
            compactSizeControl(
                title: "절 번호 크기",
                value: $settings.bibleVerseNumberFontSize,
                range: 8...24
            )
            compactSizeControl(
                title: "줄간격",
                value: $settings.bibleLineSpacing,
                range: 0...16
            )
        }
    }

    /// 캡션 라벨 아래 값(pt)과 Stepper를 두는 compact 컨트롤.
    @ViewBuilder
    private func compactSizeControl(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Stepper(value: value, in: range, step: 1) {
                Text("\(Int(value.wrappedValue))pt")
            }
        }
    }

    /// 아이폰용 — 한 줄 전체 폭(제목 - Spacer - 값 - Stepper)을 써서 값 텍스트가 잘리지 않는다.
    @ViewBuilder
    private func fullWidthSizeControl(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Stepper(value: value, in: range, step: 1) {
                Text("\(Int(value.wrappedValue))pt")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .fixedSize()
        }
    }
}

// MARK: - 성경 구절 복사 형식 (2026-08-08 추가)
//
// 실제 서식은 `BibleVerseCopyFormatter`(S1 "복사" 버튼과 같은 함수)를 그대로 호출해 미리보기를
// 만든다 — 따로 구현하면 둘이 어긋날 위험이 있어 하나로 합쳤다.

private struct BibleCopyFormatSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    // `quotePreviewAccent`가 라이트/다크에 따라 변형을 고르는 데 필요. 이 화면은 성경 조회 테마를
    // 입지 않으므로 시스템 모드만 본다.
    @Environment(\.colorScheme) private var colorScheme
    @State private var settings = UserSettingsStore.shared
    /// 등록된 번역본 총 개수 — 복사 시 실제 개수가 아니라 이 설정이 의미 있을 가능성을 등록 수로 판단한다.
    @State private var registeredTranslationCount = 0

    var body: some View {
        Form {
            Section {
                Picker("구분 기호", selection: $settings.copyReferenceBracketStyle) {
                    Text("[창세기 1:1]").tag(UserSettingsStore.ReferenceBracketStyle.square)
                    Text("(창세기 1:1)").tag(UserSettingsStore.ReferenceBracketStyle.round)
                }
                .pickerStyle(.segmented)

                Toggle("성경 이름 약어 사용 (창세기 → 창)", isOn: $settings.copyUseAbbreviatedBookName)

                Picker("성경 장절 위치", selection: $settings.copyReferencePosition) {
                    ForEach(UserSettingsStore.TextPosition.allCases) { position in
                        Text(position.displayName).tag(position)
                    }
                }
                .pickerStyle(.segmented)

                Picker("번역본 이름 위치", selection: $settings.copyTranslationLabelPosition) {
                    ForEach(UserSettingsStore.TextPosition.allCases) { position in
                        Text(position.displayName).tag(position)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(registeredTranslationCount <= 1)

                // 두 위치가 다르면 이 설정이 적용될 자리가 없으므로, 비활성화 대신 숨긴다("왜 안 먹히지" 오해 방지).
                // 위치가 같아지는 순간 나타난다.
                if registeredTranslationCount > 1, settings.copyReferencePosition == settings.copyTranslationLabelPosition {
                    Toggle("번역본 이름과 장절을 합쳐서 표시", isOn: $settings.copyCombineReferenceAndTranslationLabel)
                }
            } header: {
                Label("기본 설정", systemImage: "doc.on.doc")
            } footer: {
                if registeredTranslationCount <= 1 {
                    Text("등록된 번역본이 1개뿐이라 번역본 이름 위치는 지금 적용되지 않습니다.")
                } else if settings.copyReferencePosition == settings.copyTranslationLabelPosition {
                    Text(settings.copyCombineReferenceAndTranslationLabel
                        ? "예: [NKJV 창세기 1:1]"
                        : "예: [NKJV][창세기 1:1]")
                }
            }

            Section {
                Toggle("절마다 줄바꿈 하기", isOn: $settings.copyNewlineBetweenVerses)

                if settings.copyNewlineBetweenVerses {
                    Toggle("매 절마다 장:절 표기", isOn: $settings.copyRepeatReferenceForEachVerse)
                        .padding(.leading, 12)
                        .onChange(of: settings.copyRepeatReferenceForEachVerse) { _, newValue in
                            // 이 모드에서는 절 번호 표시가 의미 없어 자동으로 끈다.
                            if newValue {
                                settings.copyShowVerseNumbers = false
                                settings.copyShowFirstVerseNumber = false
                            }
                        }
                }

                Toggle("절 번호 표시", isOn: $settings.copyShowVerseNumbers)
                    .disabled(settings.copyRepeatReferenceForEachVerse)
                    .onChange(of: settings.copyShowVerseNumbers) { _, newValue in
                        if !newValue { settings.copyShowFirstVerseNumber = false }
                    }

                if settings.copyShowVerseNumbers {
                    Picker("번호 스타일", selection: $settings.copyVerseNumberStyle) {
                        ForEach(UserSettingsStore.VerseNumberStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(settings.copyRepeatReferenceForEachVerse)

                    Toggle("첫 절 번호 표시", isOn: $settings.copyShowFirstVerseNumber)
                        .disabled(settings.copyRepeatReferenceForEachVerse)
                }
            } header: {
                Label("상세 출력 형식", systemImage: "list.bullet.rectangle")
            }

            Section {
                // 실제로 복사/공유될 성경 본문 서식을 보여주는 자리라 밤빛 남색을 배정한다. 배경은 8%로 옅게 깔아
                // 텍스트 대비를 해치지 않고, 테두리로 색을 드러낸다.
                Text(previewText)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .background(
                        quotePreviewAccent.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(quotePreviewAccent, lineWidth: 1)
                    )
            } header: {
                Label("미리보기", systemImage: "text.quote")
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadTranslationCount)
    }

    private func loadTranslationCount() {
        registeredTranslationCount = (try? modelContext.fetch(FetchDescriptor<TranslationRegistry>()))?.count ?? 0
    }

    /// 미리보기 카드 강조색 — 시스템이 다크 모드면 밝게 섞은 `navyOnDark`, 아니면 `navy`.
    private var quotePreviewAccent: Color {
        colorScheme == .dark ? JBCHCategoryPalette.navyOnDark : JBCHCategoryPalette.navy
    }

    /// 창세기 1:1-2, 번역본 1~2개로 실제 서식 함수를 돌려 만드는 미리보기 — 실제 "복사" 결과와 항상 같다.
    private var previewText: String {
        let sampleBook = BooksProvider.shared.books.first(where: { $0.bookId == 1 })
            ?? Book(bookId: 1, testament: .old, orderIndex: 1, nameKo: "창세기", nameOriginal: "Genesis", abbreviation: ["창"], chapterCount: 50)
        let verses = [
            BibleVerse(uid: 1, versionCode: nil, bookId: 1, chapter: 1, verse: 1, content: "태초에 하나님이 천지를 창조하시니라", paragraph: nil),
            BibleVerse(uid: 2, versionCode: nil, bookId: 1, chapter: 1, verse: 2, content: "땅이 혼돈하고 공허하며 흑암이 깊음 위에 있고", paragraph: nil),
        ]
        var translations = [BibleVerseCopyFormatter.TranslationSnapshot(displayName: "번역본 A", verses: verses)]
        if registeredTranslationCount > 1 {
            translations.append(BibleVerseCopyFormatter.TranslationSnapshot(displayName: "번역본 B", verses: verses))
        }
        return BibleVerseCopyFormatter.format(
            book: sampleBook, chapter: 1, selectedVerses: [1, 2],
            translations: translations, settings: settings
        ) ?? ""
    }
}

// MARK: - 단축키(선택 — 스펙 자체가 "필수 아님")

private struct ShortcutsSettingsTab: View {
    private let shortcuts: [(String, String)] = [
        ("새 메모", "⌘N"), ("새 폴더", "⇧⌘N"), ("연구 문서 업로드", "⌘O"),
        ("사이드바 토글", "⌥⌘S"), ("성경조회로 이동", "⌘1"), ("개인 묵상으로 이동", "⌘2"),
        ("연구 문서로 이동", "⌘3"), ("개요로 이동", "⌘4"), ("통합검색으로 이동", "⌘5"),
        ("말씀 요약으로 이동", "⌘6"),
        ("태그 관계 보기", "⇧⌘T"), ("다음 장", "⌘]"), ("이전 장", "⌘["),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(shortcuts, id: \.0) { shortcut in
                    LabeledContent(shortcut.0) {
                        Text(shortcut.1)
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            } header: {
                Label("단축키", systemImage: "keyboard")
            } footer: {
                Text("현재는 재지정할 수 없고, 위 고정된 단축키만 지원합니다(사용자 재지정은 다음 단계 후보).")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 라이센스
// 라이선스·저작권 고지.
private struct LicenseSettingsTab: View {
    var body: some View {
        Form {
            // (재)대한성서공회 저작권부 회신 기준 — 개역한글판(1961)/관주성경전서 개역한글판(1962)은
            // 저작재산권 보호기간이 만료돼 무료로 쓸 수 있으나 동일성유지권·성명표시권은 지켜야 한다.
            // 오픈소스가 아니라 보호기간 만료라 아래 "오픈소스 라이선스 고지"와 별도 섹션으로 분리했다.
            Section {
                Text("여기에 사용한 성경전서 개역한글판의 저작권은 (재)대한성서공회에 있습니다.")
                Text("성경전서 개역한글판 ⓒ (재)대한성서공회")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("성경 본문 저작권", systemImage: "book.closed")
            } footer: {
                Text("성경전서 개역한글판(1961)과 관주성경전서 개역한글판(1962)은 저작재산권 보호기간이 만료되어 (재)대한성서공회의 허가 없이 무료로 사용할 수 있습니다. 다만 본문을 임의로 변경·수정하지 않고 그대로 사용해야 하며(동일성유지권), 저작권이 (재)대한성서공회에 있다는 표시(성명표시권)를 해야 합니다 — (재)대한성서공회 저작권부 회신(2026-08-19) 기준.")
            }

            // STEPBible-Data(CC BY 4.0)는 "STEP Bible"을 www.STEPBible.org에 링크해 표시하면 된다.
            // hwp 뷰어는 hwp-swift(네이티브, LGPL-2.1 — 수정 없이 SPM 의존성으로만 쓰면 소스 공개 의무는
            // 없으나 라이선스/저작자 고지 필요)와 rhwp(웹 뷰어, MIT, 오프라인 번들 — 원문은
            // Resources/rhwp_LICENSE.txt)를 함께 고지한다. hwp-swift는 폰트를 번들하지 않는다.
            Section {
                Text("hwp 문서는 두 가지 뷰어로 열어 비교할 수 있습니다. 네이티브 뷰어는 오픈소스 hwp-swift(github.com/sboh1214/hwp-swift, LGPL-2.1 라이선스)를 사용하며, 별도로 폰트를 번들하지 않고 기기에 설치된 시스템 폰트로 렌더링합니다.")

                Link("hwp-swift 저장소 보기", destination: URL(string: "https://github.com/sboh1214/hwp-swift")!)

                Text("웹 뷰어는 오픈소스 rhwp(github.com/edwardkim/rhwp, MIT 라이선스)를 이 앱에 오프라인 번들해 사용합니다. 외부 서버 없이 기기 안에서만 문서를 렌더링합니다.")

                Link("rhwp 저장소 보기", destination: URL(string: "https://github.com/edwardkim/rhwp")!)

                // SwiftText(MIT), ZIPFoundation(MIT), docxide-pdf(Apache 2.0) — 각 저장소 LICENSE 원문 기준.
                Text("doc/docx/pages 문서 업로드·텍스트 추출은 오픈소스 SwiftText(github.com/Cocoanetics/SwiftText, MIT 라이선스)를 사용합니다. SwiftText가 zip 압축 해제에 쓰는 ZIPFoundation(github.com/weichsel/ZIPFoundation, MIT 라이선스)도 함께 포함됩니다.")

                Link("SwiftText 저장소 보기", destination: URL(string: "https://github.com/Cocoanetics/SwiftText")!)

                Link("ZIPFoundation 저장소 보기", destination: URL(string: "https://github.com/weichsel/ZIPFoundation")!)

                Text("docx → PDF 변환(맥 전용)은 오픈소스 docxide-pdf(github.com/sverrejb/docxide-pdf, Apache License 2.0)를 사용합니다. 변환은 이 기기 안에서만 이뤄지며 외부 서버로 전송되지 않습니다.")

                Link("docxide-pdf 저장소 보기", destination: URL(string: "https://github.com/sverrejb/docxide-pdf")!)

                Text("원문 정보(히브리어 구약·그리스어 신약 원어 데이터)는 STEP Bible(www.STEPBible.org, Tyndale House Cambridge 제공)의 STEPBible-Data(TAHOT/TAGNT)를 사용하며, Creative Commons Attribution 4.0 International(CC BY 4.0) 라이선스를 따릅니다.")

                Link("STEPBible-Data 저장소 보기", destination: URL(string: "https://github.com/STEPBible/STEPBible-Data")!)

                // 출처는 (재)대한성서공회 회신으로 확정됐다 — 위 "성경 본문 저작권" 섹션 참고.
                Text("관주(구절 연결) 정보는 (재)대한성서공회의 관주성경전서 개역한글판(1962)을 따릅니다. 저작재산권 보호기간이 만료되어 무료로 사용하되, 위 '성경 본문 저작권' 섹션과 같은 조건(동일성유지권·성명표시권)을 지킵니다.")

                // 한자/히브리어/헬라어 전용 폰트와 번들 폰트의 라이선스 고지. 조선궁서체는 표준 오픈소스
                // 라이선스가 아니라 (주)조선일보사 고지 문구를 그대로 옮겼다.
                Text("한자 주석 기본 폰트인 조선궁서체의 지적재산권은 (주)조선일보사에 있고 개인 및 기업 사용자에게 무료로 제공됩니다. 사용자들은 이를 다른 이에게 자유롭게 배포할 수 있습니다. 다만 어떠한 경우에도 복사 또는 배포에 따른 대가를 요구하거나 수정해서 판매할 수 없으며, 배포된 형태 그대로 사용해야 합니다.")

                // Ezra SIL(software.sil.org/ezra) — 히브리어 문자 배치 지능만 Ralph Hancock·John Hudson의
                // MIT/X11, 그 외 폰트 소프트웨어는 SIL OFL 1.1.
                Text("원문 정보 화면의 히브리어 원어 표기는 SIL Global이 배포하는 Ezra SIL 폰트를 사용합니다. 히브리어 문자 배치 지능은 Ralph Hancock과 John Hudson이 만든 MIT/X11 라이선스를, 그 외 폰트 소프트웨어 자체는 SIL Open Font License(OFL) 1.1을 따릅니다.")

                Link("Ezra SIL 다운로드 페이지 보기", destination: URL(string: "https://software.sil.org/ezra/")!)

                // Gentium — SIL OFL.txt(Copyright 2003-2025 SIL Global, Reserved Font Names "Gentium"·"SIL") 기준.
                // 번들 파일의 family 이름이 "Gentium"이라 문구와 일치하며, "Gentium Plus"는 현재 명칭이다.
                Text("원문 정보 화면의 그리스어(헬라어) 원어 표기는 SIL Global이 배포하는 Gentium 폰트(현재 명칭 Gentium Plus)를 사용하며, SIL Open Font License(OFL) 1.1을 따릅니다.")

                Link("Gentium 폰트 페이지 보기", destination: URL(string: "https://software.sil.org/gentium/")!)

                // Gowun Batang — OFL.txt(Copyright 2021 The Gowun Batang Project Authors) 기준. Paperlogy처럼
                // 번들해 "글꼴" 설정에서 고르는 일반 글꼴이라 언어 전용 폰트 항목과 성격이 다르다.
                Text("앱 내장 기본 글꼴 중 고운바탕(Gowun Batang)은 The Gowun Batang Project Authors가 배포하는 오픈소스 폰트로, SIL Open Font License(OFL) 1.1을 따릅니다.")

                Link("Gowun Batang 저장소 보기", destination: URL(string: "https://github.com/yangheeryu/Gowun-Batang")!)
            } header: {
                Label("오픈소스 라이선스 고지", systemImage: "doc.plaintext")
            } footer: {
                Text("원문 정보 화면의 한글 뜻풀이는 위 STEPBible 영어 뜻풀이를 기기 내(Apple Translation 프레임워크) 자동 번역한 것이며, 사용자가 직접 수정할 수 있습니다. 신학 용어의 표준 역어와 다를 수 있습니다.")
            }

            // 폰트 저작권/라이선스 고지는 배포 페이지(80.kookmin.ac.kr/vision/font)에 명시된 조건과
            // 폰트 파일 name 테이블의 고지를 그대로 옮긴 것이다(페이지에 표시 문구 예시·앱 임베딩 조항은 없음).
            Section {
                Text("각 기능 화면 상단 타이틀에는 국민대학교 창학 80주년 기념 서체 'KMU80 성곡 세리프(Sungkok Serif)'를 사용합니다. 이 폰트의 저작권은 국민대학교에 있으며(Copyright © 2026 KOOKMIN UNIVERSITY. ALL RIGHTS RESERVED.), 국민대학교 산학협력으로 (주)티랩이 제작했습니다.")

                Link("성곡 세리프체 배포 페이지 보기", destination: URL(string: "https://80.kookmin.ac.kr/vision/font")!)

                Image("LicenseCCBYND")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 220)
                    .accessibilityLabel("CC BY-ND 라이선스 배지")

                Text("라이선스: CC BY-ND(저작자표시-변경금지). 저작권 정보를 표시하면 상업적 이용을 포함해 사용할 수 있으나, 서체 자체를 변경하거나 2차적 저작물을 만들 수 없고, 폰트 파일 자체를 유료로 재판매할 수 없습니다.")
            } header: {
                Label("타이틀 서체 라이선스", systemImage: "textformat")
            } footer: {
                Text("배포 페이지에 저작권 표시 문구의 구체적 예시나 앱 내 임베딩에 대한 별도 조항은 없어, 위 문구는 페이지에 명시된 라이선스 조건과 폰트 파일에 내장된 저작권 고지를 그대로 옮긴 것입니다.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 개발자 (DEBUG 전용, OutlineSeedExporter.swift 참고)
// 개요(S8/S9) 화면에서 서식 포함으로 작성한 결과(RTF)를 배포용 OutlineSeed.json 포맷으로
// 내보내는 버튼만 제공한다 — 별도 에디터가 아니다.

#if DEBUG
import UniformTypeIdentifiers

private struct DeveloperSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    /// "온보딩 다시 보기" 버튼용 — 이 화면이 `.sheet`(아이패드)로 떠 있으면 먼저 닫아야
    /// 같은 RootView가 온보딩 시트를 띄울 수 있다(SwiftUI는 시트 두 개를 동시에 못 띄운다).
    /// macOS Settings Scene/아이폰 NavigationLink 진입에서는 `dismiss()`가 무해하다.
    @Environment(\.dismiss) private var dismiss
    @State private var exportDocument: OutlineSeedJSONDocument?
    @State private var isExporterPresented = false
    @State private var lastExportSummary: OutlineSeedExporter.Summary?
    @State private var exportError: String?

    // 테스트로 쌓인 형광펜/관주/구절별 메모를 지우는 1회성 삭제용 상태. 데이터가 CloudKit 연동
    // SwiftData 스토어에만 있어 이 기기에서 버튼으로 지운다. 개인 묵상·말씀요약(UserMemo)은
    // 실제 내용일 수 있어 대상에서 제외한다.
    @State private var testDataCounts: (highlight: Int, crossReference: Int, phraseNote: Int)?
    @State private var isDeleteConfirmationPresented = false
    @State private var deleteResultMessage: String?

    // 연구문서 데이터(레코드만)를 지우는 1회성 삭제용 상태 — 기능/화면/모델은 유지한다.
    // SourceDocument 삭제 시 cascade 자식(DocumentText/ConvertedPDF/OCRResult/DocumentAnchor/
    // DocumentMarkdown)은 함께 지워지지만, VerseMention은 관계가 아니라 원시 문자열 `sourceId`로
    // 연결돼 자동 삭제되지 않아 별도로 지운다. ImageCategory(사용자 분류 체계)와 원본 파일은 건드리지 않는다.
    @State private var documentDataCounts: (document: Int, verseMention: Int)?
    @State private var isDeleteDocumentsConfirmationPresented = false
    @State private var deleteDocumentsResultMessage: String?

    var body: some View {
        Form {
            Section {
                Text("사이드바 \"개요\" 메뉴에서 평소처럼 리치 에디터로 책/장 개요를 작성하세요 — 이 기기의 DB에 그대로 쌓입니다.")
                Button {
                    export()
                } label: {
                    Label("개요 시딩 파일 내보내기...", systemImage: "square.and.arrow.up")
                }
                if let summary = lastExportSummary {
                    Text("책 개요 \(summary.bookCount)개 / 장 개요 \(summary.chapterCount)개를 내보냈습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let exportError {
                    Text(exportError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Label("개요 시딩", systemImage: "text.book.closed")
            } footer: {
                Text("내보낸 파일을 Resources/OutlineSeed.json에 덮어쓰고 Xcode Copy Bundle Resources에 등록하면(최초 1회만 필요) 신규 사용자 DB에 기본값으로 채워집니다. 이 탭 자체는 배포 빌드에서 빠집니다.")
            }

            // 온보딩 시트 재표시용. 신호만 AppOnboardingReplayRequest에 보내고 실제 표시는 관찰자
            // AppOnboardingPresenter가 맡는다. dismiss() 직후 바로 요청하면 macOS에서 시트 닫힘
            // 애니메이션 중 다음 시트가 열려 빈 시트만 뜨므로, 요청을 0.3초 지연시킨다.
            Section {
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        AppOnboardingReplayRequest.shared.requestReplay()
                    }
                } label: {
                    Label("온보딩 다시 보기", systemImage: "sparkles")
                }
            } header: {
                Label("온보딩 미리보기", systemImage: "sparkles")
            } footer: {
                Text("완료 플래그(hasCompletedOnboarding)와 마지막 확인 버전(lastSeenAppVersion)은 건드리지 않습니다 — 내용만 미리 봅니다. 이 화면이 시트로 떠 있는 경우(아이패드) 먼저 닫힌 뒤 온보딩이 뜹니다.")
            }

            // "새로워진 점" 시트 재표시용 — 온보딩 버튼과 같은 패턴(WhatsNewReplayRequest 신호 →
            // WhatsNewPresenter가 표시)이며, 같은 이유로 요청을 지연시킨다.
            Section {
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        WhatsNewReplayRequest.shared.requestReplay()
                    }
                } label: {
                    Label("새로워진 점 다시 보기", systemImage: "gift")
                }
            } header: {
                Label("새로워진 점 미리보기", systemImage: "gift")
            } footer: {
                Text("마지막 확인 버전(lastSeenAppVersion)은 건드리지 않습니다 — 내용만 미리 봅니다. 현재 버전(\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"))에 등록된 WhatsNewContent 항목이 없으면 아무 일도 일어나지 않습니다. 이 화면이 시트로 떠 있는 경우(아이패드) 먼저 닫힌 뒤 뜹니다.")
            }

            Section {
                if let counts = testDataCounts {
                    Text("형광펜 \(counts.highlight)개 · 관주 \(counts.crossReference)개 · 구절별 메모 \(counts.phraseNote)개")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(role: .destructive) {
                    refreshCounts()
                    isDeleteConfirmationPresented = true
                } label: {
                    Label("형광펜/관주/구절별 메모 전체 삭제", systemImage: "trash")
                }
                if let deleteResultMessage {
                    Text(deleteResultMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("테스트 데이터 삭제", systemImage: "trash")
            } footer: {
                Text("이 기기(및 iCloud로 동기된 다른 기기)의 형광펜·관주·구절별 메모를 전부 지웁니다 — 되돌릴 수 없습니다. 개인 묵상/말씀요약(말씀 노트)은 지우지 않습니다.")
            }

            Section {
                if let counts = documentDataCounts {
                    Text("연구 문서 \(counts.document)개 · 구절 언급 \(counts.verseMention)개")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(role: .destructive) {
                    refreshDocumentCounts()
                    isDeleteDocumentsConfirmationPresented = true
                } label: {
                    Label("연구 문서 전체 삭제", systemImage: "trash")
                }
                if let deleteDocumentsResultMessage {
                    Text(deleteDocumentsResultMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("연구 문서 데이터 삭제", systemImage: "doc.badge.gearshape")
            } footer: {
                Text("사이드바 \"연구 문서\"에 등록된 모든 문서(원본 파일 참조·OCR 결과·변환본·본문 텍스트)와 거기서 파생된 성경구절 언급을 전부 지웁니다 — 되돌릴 수 없습니다. 사용자 저장공간의 원본 파일 자체는 지우지 않고, 이 앱의 등록 정보만 지웁니다. \"연구 문서\" 기능/화면은 그대로 남아 있어 다시 업로드할 수 있습니다.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshCounts()
            refreshDocumentCounts()
        }
        .fileExporter(
            isPresented: $isExporterPresented,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "OutlineSeed"
        ) { result in
            if case .failure(let error) = result {
                exportError = "저장 실패: \(error.localizedDescription)"
            }
        }
        .confirmationDialog(
            "형광펜, 관주, 구절별 메모를 전부 삭제할까요?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("전체 삭제", role: .destructive) { deleteTestData() }
            Button("취소", role: .cancel) {}
        } message: {
            if let counts = testDataCounts {
                Text("형광펜 \(counts.highlight)개, 관주 \(counts.crossReference)개, 구절별 메모 \(counts.phraseNote)개가 삭제됩니다. 되돌릴 수 없습니다.")
            }
        }
        .confirmationDialog(
            "연구 문서를 전부 삭제할까요?",
            isPresented: $isDeleteDocumentsConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("전체 삭제", role: .destructive) { deleteAllDocuments() }
            Button("취소", role: .cancel) {}
        } message: {
            if let counts = documentDataCounts {
                Text("연구 문서 \(counts.document)개와 관련 DB자료(구절 언급 \(counts.verseMention)개)가 삭제됩니다. 원본 파일 자체는 지워지지 않습니다. 되돌릴 수 없습니다.")
            }
        }
    }

    private func export() {
        exportError = nil
        do {
            let (data, summary) = try OutlineSeedExporter.exportSeedJSON(context: modelContext)
            exportDocument = OutlineSeedJSONDocument(data: data)
            lastExportSummary = summary
            isExporterPresented = true
        } catch {
            exportError = "내보내기 실패: \(error.localizedDescription)"
        }
    }

    private func refreshCounts() {
        let highlightCount = (try? modelContext.fetchCount(FetchDescriptor<VerseHighlight>())) ?? 0
        let crossReferenceCount = (try? modelContext.fetchCount(FetchDescriptor<VerseCrossReference>())) ?? 0
        let phraseNoteCount = (try? modelContext.fetchCount(FetchDescriptor<VersePhraseNote>())) ?? 0
        testDataCounts = (highlightCount, crossReferenceCount, phraseNoteCount)
    }

    private func deleteTestData() {
        do {
            for item in try modelContext.fetch(FetchDescriptor<VerseHighlight>()) { modelContext.delete(item) }
            for item in try modelContext.fetch(FetchDescriptor<VerseCrossReference>()) { modelContext.delete(item) }
            for item in try modelContext.fetch(FetchDescriptor<VersePhraseNote>()) { modelContext.delete(item) }
            try modelContext.save()
            deleteResultMessage = "삭제 완료 (\(Date.now.formatted(date: .omitted, time: .shortened)))"
        } catch {
            deleteResultMessage = "삭제 실패: \(error.localizedDescription)"
        }
        refreshCounts()
    }

    private func refreshDocumentCounts() {
        // ⚠️ VerseMention.sourceType은 String rawValue enum이라 `#Predicate` 등호 비교의 안전성을
        // 확신할 수 없어, 전체를 가져와 Swift에서 거른다.
        let documentCount = (try? modelContext.fetchCount(FetchDescriptor<SourceDocument>())) ?? 0
        let verseMentionCount = ((try? modelContext.fetch(FetchDescriptor<VerseMention>())) ?? [])
            .filter { $0.sourceType == .document }.count
        documentDataCounts = (documentCount, verseMentionCount)
    }

    private func deleteAllDocuments() {
        do {
            // SourceDocument 삭제 시 cascade 자식(DocumentText/ConvertedPDF/OCRResult/DocumentAnchor/
            // DocumentMarkdown)은 자동으로 지워진다. DB 레코드를 지우기 전에 저장된 실제 파일부터
            // 지운다(개별 삭제 DocumentsViewModel.delete와 동일 규칙).
            for item in try modelContext.fetch(FetchDescriptor<SourceDocument>()) {
                DocumentUploadService.deleteStoredFile(for: item)
                modelContext.delete(item)
            }
            // 관계 없이 sourceId 문자열로만 연결된 VerseMention은 별도로 지운다.
            for item in try modelContext.fetch(FetchDescriptor<VerseMention>()) where item.sourceType == .document {
                modelContext.delete(item)
            }
            try modelContext.save()
            deleteDocumentsResultMessage = "삭제 완료 (\(Date.now.formatted(date: .omitted, time: .shortened)))"
        } catch {
            deleteDocumentsResultMessage = "삭제 실패: \(error.localizedDescription)"
        }
        refreshDocumentCounts()
    }
}

/// `fileExporter`용 최소 `FileDocument` 래퍼 — 완성된 JSON `Data`를 그대로 감싼다.
private struct OutlineSeedJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
#endif
