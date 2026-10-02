//
//  UserSettingsStore.swift
//  JBCHBibleResearch
//
//  UserDefaults 기반 사용자 설정 저장소. 다른 화면이 실제로 참조하는 설정만 담는다.
//  이 타입에 없는 설정(동기화 일시중지, 저장공간 경로 등)은 SettingsView.swift에
//  UI만 있고 동작에는 연결돼 있지 않다.
//
//  ⚠️ SwiftData/CloudKit 대신 UserDefaults를 쓴 이유: 이 값들은 "이 기기에서의 앱 사용
//  방식" 설정이지 기기 간 동기화가 필요한 연구 데이터가 아니다.
//  `NSUbiquitousKeyValueStore`를 통한 기기 간 동기화는 적용하지 않았다.
//

import Foundation
import Observation
import SwiftUI
import BibleResearchModels

@MainActor
@Observable
final class UserSettingsStore {
    static let shared = UserSettingsStore()

    private let defaults: UserDefaults

    private enum Key {
        static let openLastScreenOnLaunch = "settings.openLastScreenOnLaunch"
        static let lastSelectedSection = "settings.lastSelectedSection"
        static let colorSchemePreference = "settings.colorSchemePreference"
        // 첫 실행 가이드 완료 여부(hasCompletedOnboarding)와, "새 소식" 화면이 마지막으로
        // 확인한 앱 버전(lastSeenAppVersion, CFBundleShortVersionString).
        static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
        static let lastSeenAppVersion = "settings.lastSeenAppVersion"
        static let defaultTranslationCode = "settings.defaultTranslationCode"
        static let defaultDisplayedTranslationCodes = "settings.defaultDisplayedTranslationCodes"
        static let lastManualSyncAt = "settings.lastManualSyncAt"
        // S1(성경 조회) 표시 폰트/크기/간격/색상.
        static let bibleFontName = "settings.bible.fontName"
        static let bibleBodyFontSize = "settings.bible.bodyFontSize"
        static let bibleVerseNumberFontSize = "settings.bible.verseNumberFontSize"
        static let bibleLineSpacing = "settings.bible.lineSpacing"
        static let bibleVerseSpacing = "settings.bible.verseSpacing"
        static let bibleTextColorHex = "settings.bible.textColorHex"
        static let bibleBackgroundColorHex = "settings.bible.backgroundColorHex"
        // 테마 색상 자동/라이트/다크 3단 선택(BibleThemeModePreference).
        static let bibleThemeModePreference = "settings.bible.themeModePreference"
        // 성경 구절 복사 형식.
        static let copyReferencePosition = "settings.bible.copy.referencePosition"
        static let copyReferenceBracketStyle = "settings.bible.copy.referenceBracketStyle"
        static let copyUseAbbreviatedBookName = "settings.bible.copy.useAbbreviatedBookName"
        static let copyTranslationLabelPosition = "settings.bible.copy.translationLabelPosition"
        static let copyNewlineBetweenVerses = "settings.bible.copy.newlineBetweenVerses"
        static let copyRepeatReferenceForEachVerse = "settings.bible.copy.repeatReferenceForEachVerse"
        static let copyShowVerseNumbers = "settings.bible.copy.showVerseNumbers"
        static let copyVerseNumberStyle = "settings.bible.copy.verseNumberStyle"
        static let copyShowFirstVerseNumber = "settings.bible.copy.showFirstVerseNumber"
        // 장절과 번역본 표기를 합칠지 분리할지 — copyReferencePosition과
        // copyTranslationLabelPosition이 같은 값일 때만 의미가 있다.
        static let copyCombineReferenceAndTranslationLabel = "settings.bible.copy.combineReferenceAndTranslationLabel"
        // 1회성 시드 복사 완료 플래그 — 한 번만 실행해, 사용자가 지운 내용을 다시
        // 채워 넣지 않도록 한다(OutlineSeedImporter).
        static let hasImportedOutlineSeed = "settings.hasImportedOutlineSeed"
        // 개요 트리의 펼침 상태(구약/신약, 책) — 재실행 후에도 유지한다.
        static let outlineExpandedTestaments = "settings.outline.expandedTestaments"
        static let outlineExpandedBookIds = "settings.outline.expandedBookIds"
        // CrossReferenceSeedImporter용 1회성 플래그(hasImportedOutlineSeed와 같은 패턴).
        static let hasImportedCrossReferenceSeed = "settings.hasImportedCrossReferenceSeed"
        // MarginalNoteSeedImporter용 1회성 플래그.
        static let hasImportedMarginalNoteSeed = "settings.hasImportedMarginalNoteSeed"
        // HanjaAnnotationSeedImporter용 1회성 플래그.
        static let hasImportedHanjaAnnotationSeed = "settings.hasImportedHanjaAnnotationSeed"
        // 번들 관주/난외주를 ReferenceData.sqlite로 옮기면서, 이미 SwiftData에 들어간 번들분을
        // 1회성으로 정리했는지(ReferenceDataMigration.cleanupLegacyBundledRecords).
        static let hasCleanedUpLegacyBundledReferenceData = "settings.hasCleanedUpLegacyBundledReferenceData"
        // SermonGatheringSeeder용 1회성 플래그.
        static let hasSeededSermonGatherings = "settings.sermon.hasSeededGatherings"
        // 개역한글 본문의 한자 주석 표시 방식: 탭하면 보기/항상 보기(국한문식)/끄기.
        static let hanjaDisplayMode = "settings.bible.hanjaDisplayMode"
        // 한자 주석 폰트 — bibleFontName과 같은 규칙("System"이면 시스템 기본, 아니면 PostScript 이름).
        static let hanjaFontName = "settings.bible.hanjaFontName"
        // 설교 문단 스타일 6종별 폰트/크기 — bibleFontName/bibleBodyFontSize와 같은 저장 방식
        // (UserDefaults, didSet 즉시 반영).
        static let sermonMainThemeFontName = "settings.sermon.mainTheme.fontName"
        static let sermonMainThemeFontSize = "settings.sermon.mainTheme.fontSize"
        static let sermonMidThemeFontName = "settings.sermon.midTheme.fontName"
        static let sermonMidThemeFontSize = "settings.sermon.midTheme.fontSize"
        static let sermonSubThemeFontName = "settings.sermon.subTheme.fontName"
        static let sermonSubThemeFontSize = "settings.sermon.subTheme.fontSize"
        static let sermonVerseQuoteFontName = "settings.sermon.verseQuote.fontName"
        static let sermonVerseQuoteFontSize = "settings.sermon.verseQuote.fontSize"
        static let sermonCitationFontName = "settings.sermon.citation.fontName"
        static let sermonCitationFontSize = "settings.sermon.citation.fontSize"
        static let sermonBodyFontName = "settings.sermon.body.fontName"
        static let sermonBodyFontSize = "settings.sermon.body.fontSize"
        // 문단 스타일별 글자 색상(hex). bibleTextColorHex와 달리 빈 값이 없고, init에서 항상
        // 기본값이 채워진다.
        static let sermonMainThemeFontColorHex = "settings.sermon.mainTheme.fontColorHex"
        static let sermonMidThemeFontColorHex = "settings.sermon.midTheme.fontColorHex"
        static let sermonSubThemeFontColorHex = "settings.sermon.subTheme.fontColorHex"
        static let sermonVerseQuoteFontColorHex = "settings.sermon.verseQuote.fontColorHex"
        static let sermonCitationFontColorHex = "settings.sermon.citation.fontColorHex"
        static let sermonBodyFontColorHex = "settings.sermon.body.fontColorHex"
        // 말씀구절 박스 배경색 — 이 스타일만 배경 박스를 가진다.
        static let sermonVerseQuoteBackgroundColorHex = "settings.sermon.verseQuote.backgroundColorHex"
        // 말씀구절 박스 왼쪽 세로 바 색 — 기본값은 중주제 색과 같지만, 독립적으로 바꿀 수
        // 있도록 별도 키로 둔다(현재 뷰어는 편집기와 같은 서식을 그려 이 색을 쓰지 않는다).
        static let sermonVerseQuoteBarColorHex = "settings.sermon.verseQuote.barColorHex"
        // 설교 뷰어의 전체 글꼴 배율(80~200%)과 스크롤/페이지 넘김 모드. 스타일별 크기와 달리
        // 전체 배율 하나뿐이며 상대 크기 비율은 유지된다.
        static let sermonViewerFontScale = "settings.sermon.viewer.fontScale"
        static let sermonViewerUsesPageMode = "settings.sermon.viewer.usesPageMode"
    }

    // MARK: - S1 표시 폰트

    /// "본문 앞/본문 뒤" 두 자리에서 공통으로 쓰는 위치 값 — 복사 형식의 "성경
    /// 장절 위치"와 "번역본 이름 위치" 둘 다 이 타입을 쓴다(둘은 서로 별개 설정이지만
    /// 값의 모양이 같다).
    enum TextPosition: String, CaseIterable, Identifiable {
        case beforeBody, afterBody
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .beforeBody: return "본문 앞"
            case .afterBody: return "본문 뒤"
            }
        }
    }

    /// 성경 장절 표기를 감싸는 괄호 스타일 — [창세기 1:1] / (창세기 1:1).
    enum ReferenceBracketStyle: String, CaseIterable, Identifiable {
        case square, round
        var id: String { rawValue }
        var prefix: String { self == .square ? "[" : "(" }
        var suffix: String { self == .square ? "]" : ")" }
    }

    /// 절 번호 표시 스타일 — (1), [1], 1).
    enum VerseNumberStyle: String, CaseIterable, Identifiable {
        case parenthesis, bracket, closingParen
        var id: String { rawValue }
        func format(_ number: Int) -> String {
            switch self {
            case .parenthesis: return "(\(number))"
            case .bracket: return "[\(number)]"
            case .closingParen: return "\(number))"
            }
        }
        var displayName: String {
            switch self {
            case .parenthesis: return "(1)"
            case .bracket: return "[1]"
            case .closingParen: return "1)"
            }
        }
    }

    /// 개역한글 본문 한자 주석 표시 방식. `.off`가 기본값 — 기존 사용자에게 갑자기
    /// 낯선 한자가 나타나지 않게 한다.
    enum HanjaDisplayMode: String, CaseIterable, Identifiable {
        /// 한자 주석을 표시하지 않는다.
        case off
        /// 평소엔 순수 한글만 보이고, 한자가 있는 단어를 탭하면 팝오버로 훈음을 보여준다.
        case tapToReveal
        /// 국한문혼용처럼 해당 단어 뒤에 "(한자)"를 항상 붙여서 보여준다.
        case alwaysInline
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .off: return "끄기"
            case .tapToReveal: return "탭하면 보기"
            case .alwaysInline: return "항상 보기(국한문식)"
            }
        }
    }

    /// "시작 시 마지막으로 보던 화면 열기"(기본 켜짐).
    var openLastScreenOnLaunch: Bool {
        didSet { defaults.set(openLastScreenOnLaunch, forKey: Key.openLastScreenOnLaunch) }
    }

    /// 위 토글이 켜져 있을 때 실제로 복원할 마지막 사이드바 항목. `AppSection`이
    /// `RawRepresentable(String)`이라 그대로 문자열로 저장한다.
    var lastSelectedSectionRawValue: String? {
        didSet { defaults.set(lastSelectedSectionRawValue, forKey: Key.lastSelectedSection) }
    }

    enum ColorSchemePreference: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .system: return "시스템 따름"
            case .light: return "라이트"
            case .dark: return "다크"
            }
        }
        /// `.preferredColorScheme(_:)`에 넘길 값. `.system`은 nil(강제하지 않음).
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    /// 화면 모드.
    var colorSchemePreference: ColorSchemePreference {
        didSet { defaults.set(colorSchemePreference.rawValue, forKey: Key.colorSchemePreference) }
    }

    /// 화면 모드를 고를 때 호출한다 — 테마 색상 선택을 해제한다(배경/글자 hex를 빈 문자열로,
    /// `bibleThemeModePreference`를 nil로). `didSet` 대신 명시적 함수로 둔 이유: `applyThemeMode`가
    /// 반대 방향으로 `colorSchemePreference`를 바꾸므로, 서로를 되돌리는 `didSet`을 걸면
    /// 상호 되먹임과 `init` 중 미초기화 프로퍼티 접근 위험이 생긴다.
    func selectColorScheme(_ preference: ColorSchemePreference) {
        colorSchemePreference = preference
        bibleBackgroundColorHex = ""
        bibleTextColorHex = ""
        markThemeModeAsCustom()
    }

    /// `AppOnboardingOverlay`의 첫 실행 가이드를 한 번만 보여주기 위한 완료 플래그(버튼으로
    /// 끝까지 넘기든 시트를 내리든 true). true가 될 때 `lastSeenAppVersion`도 현재 버전으로
    /// 기록해, 방금 설치한 사람에게 "새 소식" 화면이 바로 뜨지 않게 한다.
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    /// `WhatsNewOverlay`가 마지막으로 "새 소식"을 보여준 앱 버전(`CFBundleShortVersionString`).
    /// 현재 버전과 다르고 `hasCompletedOnboarding`이 true이면 해당 버전 내용을 보여준 뒤 갱신한다.
    /// 기록이 없으면(신규 설치) nil.
    var lastSeenAppVersion: String? {
        didSet { defaults.set(lastSeenAppVersion, forKey: Key.lastSeenAppVersion) }
    }

    /// "기본 성경 번역본" 피커. `TranslationRegistry.code`를 저장한다 — S1이
    /// 아직 아무 번역본도 선택되지 않은 첫 진입 시(`BibleReadingViewModel.
    /// loadAvailableTranslations`) 이 코드를 우선 표시하도록 반영했다.
    var defaultTranslationCode: String? {
        didSet { defaults.set(defaultTranslationCode, forKey: Key.defaultTranslationCode) }
    }

    /// S1이 처음 열릴 때 3개 컬럼에 기본으로 띄울 번역본 목록(고른 순서 그대로). 단일 선택인
    /// `defaultTranslationCode`(맨 앞으로 당기기)와는 별개다. 비어 있으면
    /// `BibleReadingViewModel.loadAvailableTranslations()`가 "등록 순 + defaultTranslationCode
    /// 맨 앞" 규칙으로 대체한다.
    var defaultDisplayedTranslationCodes: [String] {
        didSet { defaults.set(defaultDisplayedTranslationCodes, forKey: Key.defaultDisplayedTranslationCodes) }
    }

    /// "마지막 동기화 시각" — `modelContext.save()`가 성공한 시각일 뿐 실제 iCloud 업로드
    /// 완료 시각은 아니다(SwiftData/CloudKit에 완료를 알려주는 표준 API가 없음). 즉 "마지막으로
    /// 로컬 저장을 시도한 시각"의 의미로만 쓴다.
    var lastManualSyncAt: Date? {
        didSet { defaults.set(lastManualSyncAt, forKey: Key.lastManualSyncAt) }
    }

    // MARK: - S1 표시 폰트 (2026-08-08 추가)

    /// 글꼴 이름 — 시스템 글꼴 목록에서 고른 이름, 내장 Paperlogy 폰트의 PostScript 이름
    /// (`BundledFonts.entries`), 또는 "System"(시스템 기본 서체). 기본값은 내장 기본 글꼴
    /// (`BundledFonts.defaultPostScriptName`)이며, 폰트가 로드되지 않았어도 `bibleBodyFont`가
    /// 시스템 폰트로 대체한다(BundledFontRegistrar.swift 참고).
    var bibleFontName: String {
        didSet { defaults.set(bibleFontName, forKey: Key.bibleFontName) }
    }

    /// 본문(절 텍스트) 크기.
    var bibleBodyFontSize: Double {
        didSet { defaults.set(bibleBodyFontSize, forKey: Key.bibleBodyFontSize) }
    }

    /// 절 번호(맨 앞 숫자) 크기.
    var bibleVerseNumberFontSize: Double {
        didSet { defaults.set(bibleVerseNumberFontSize, forKey: Key.bibleVerseNumberFontSize) }
    }

    /// 절과 절 사이 줄간격. SwiftUI `Text.lineSpacing(_:)`에 그대로 전달한다.
    var bibleLineSpacing: Double {
        didSet { defaults.set(bibleLineSpacing, forKey: Key.bibleLineSpacing) }
    }

    /// 절과 절(각 `VerseRow`) 사이 간격 — `TranslationColumnView.columnScrollView`의
    /// `LazyVStack(spacing:)`에 전달한다. 한 절 안의 줄간격(`bibleLineSpacing`)과는 별개다.
    var bibleVerseSpacing: Double {
        didSet { defaults.set(bibleVerseSpacing, forKey: Key.bibleVerseSpacing) }
    }

    /// 본문 글자 색 — 16진 문자열("#RRGGBB")로 저장한다. 빈 문자열이면 "시스템 기본
    /// 색(primary, 라이트/다크 모드에 자동 대응)"이라는 뜻으로 취급한다 — 색을
    /// 강제로 저장해 버리면 다크 모드에서 검정 글씨처럼 보이는 문제가 생길 수 있어,
    /// "사용자가 명시적으로 고르기 전엔 손대지 않는다"는 원칙을 지켰다.
    var bibleTextColorHex: String {
        didSet { defaults.set(bibleTextColorHex, forKey: Key.bibleTextColorHex) }
    }

    /// 배경색도 `bibleTextColorHex`와 같은 패턴으로 저장한다(빈 문자열 = 시스템 기본 배경).
    var bibleBackgroundColorHex: String {
        didSet { defaults.set(bibleBackgroundColorHex, forKey: Key.bibleBackgroundColorHex) }
    }

    /// 테마 색상 자동/라이트/다크 3단 선택. 화면 모드(`ColorSchemePreference`)와는 독립적인
    /// 설정이다(예: 화면 모드는 다크여도 성경 본문만 밝게 읽을 수 있어야 함). `nil`은 셋 중
    /// 어디에도 해당하지 않는 "커스텀" 상태(`markThemeModeAsCustom()`)이며, 3단 `Picker`가
    /// "선택 없음"을 표현할 수 있도록 Optional로 둔다.
    enum BibleThemeModePreference: String, CaseIterable, Identifiable {
        // `allCases`는 선언 순서를 따르므로 Picker에 자동/라이트/다크 순으로 보이도록 이 순서로
        // 선언했다. raw value는 case 이름에서 오므로 순서를 바꿔도 저장된 기존 값은 깨지지 않는다.
        case auto, light, dark
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .auto: return "자동 변경"
            case .light: return "연한 금박"
            case .dark: return "밤빛 남색"
            }
        }
    }

    var bibleThemeModePreference: BibleThemeModePreference? {
        didSet { defaults.set(bibleThemeModePreference?.rawValue, forKey: Key.bibleThemeModePreference) }
    }

    /// `mode`(`.auto`이면 `systemColorScheme`으로 판정한 라이트/다크)에 대응하는
    /// `BibleSlideColorTheme`의 배경/글자 hex 쌍. 프리셋 "서재 아이보리"/"밤빛 서재"를
    /// 이름으로 참조한다.
    private static func fixedThemeHex(
        for mode: BibleThemeModePreference,
        systemColorScheme: ColorScheme
    ) -> (background: String, text: String) {
        let resolvedIsDark = mode == .auto ? systemColorScheme == .dark : mode == .dark
        let themeName = resolvedIsDark ? "밤빛 서재" : "서재 아이보리"
        let theme = BibleSlideColorTheme.all.first { $0.name == themeName } ?? BibleSlideColorTheme.all[0]
        return (theme.backgroundHex, theme.textHex)
    }

    /// 테마 색상 3단 중 하나를 골랐을 때 `AppearanceSettingsTab`이 호출한다 — 모드를 저장하고
    /// 그에 맞는 배경/글자 hex를 즉시 반영한다. "자동"은 이후 상태가 바뀔 때마다
    /// `syncAutoThemeIfNeeded(systemColorScheme:)`가 다시 갱신한다.
    func applyThemeMode(_ mode: BibleThemeModePreference, systemColorScheme: ColorScheme) {
        bibleThemeModePreference = mode
        let hex = Self.fixedThemeHex(for: mode, systemColorScheme: systemColorScheme)
        bibleBackgroundColorHex = hex.background
        bibleTextColorHex = hex.text
        // 화면 모드도 함께 맞춘다(`selectColorScheme(_:)`의 반대 방향 연동).
        switch mode {
        case .light: colorSchemePreference = .light
        case .dark: colorSchemePreference = .dark
        case .auto: colorSchemePreference = .system
        }
    }

    /// "자동" 모드일 때만 동작 — 지금 유효한 라이트/다크 상태에 맞춰 배경/
    /// 글자 hex를 다시 써넣는다. `ContentView`가 그 상태가 바뀔 때마다,
    /// 그리고 앱이 뜰 때 1회 호출한다(그 파일의 `effectiveColorScheme`
    /// 관련 주석 참고). `.light`/`.dark`를 명시적으로 고른 경우나 커스텀
    /// (nil)일 때는 아무 것도 하지 않는다.
    func syncAutoThemeIfNeeded(systemColorScheme: ColorScheme) {
        guard bibleThemeModePreference == .auto else { return }
        let hex = Self.fixedThemeHex(for: .auto, systemColorScheme: systemColorScheme)
        bibleBackgroundColorHex = hex.background
        bibleTextColorHex = hex.text
    }

    /// 사용자가 `ColorPicker`로 hex를 직접 바꾸면 3단 어디에도 해당하지 않게 된다 —
    /// `AppearanceSettingsTab`이 이 함수로 `bibleThemeModePreference`를 nil로 되돌려
    /// 3단 Picker가 "선택 없음"으로 보이게 한다.
    func markThemeModeAsCustom() {
        bibleThemeModePreference = nil
    }

    // MARK: - 성경 구절 복사 형식 (2026-08-08 추가)
    //
    // 참고 소스 FormatTabView.swift의 설정 항목을 이 앱의 저장 방식(UserDefaults 기반
    // @Observable 프로퍼티)으로 옮긴 것. `copyTranslationLabelPosition`은 이 앱에서 추가한
    // 항목 — S1에서 번역본을 최대 3개까지 나란히 볼 수 있어, 여러 번역본을 복사할 때 번역본
    // 이름표를 본문 앞/뒤 어디에 둘지 정해야 하기 때문이다.

    var copyReferencePosition: TextPosition {
        didSet { defaults.set(copyReferencePosition.rawValue, forKey: Key.copyReferencePosition) }
    }

    var copyReferenceBracketStyle: ReferenceBracketStyle {
        didSet { defaults.set(copyReferenceBracketStyle.rawValue, forKey: Key.copyReferenceBracketStyle) }
    }

    var copyUseAbbreviatedBookName: Bool {
        didSet { defaults.set(copyUseAbbreviatedBookName, forKey: Key.copyUseAbbreviatedBookName) }
    }

    /// 여러 번역본을 한꺼번에 복사할 때만 의미가 있다(등록된 번역본이 1개뿐이면
    /// 설정 화면에서 비활성화 — SettingsView.swift 참고).
    var copyTranslationLabelPosition: TextPosition {
        didSet { defaults.set(copyTranslationLabelPosition.rawValue, forKey: Key.copyTranslationLabelPosition) }
    }

    var copyNewlineBetweenVerses: Bool {
        didSet { defaults.set(copyNewlineBetweenVerses, forKey: Key.copyNewlineBetweenVerses) }
    }

    /// `copyNewlineBetweenVerses`가 켜져 있을 때만 의미가 있다 — 켜면 매 절마다 "장:절 본문"
    /// 형태로 반복하고, 이때 절 번호 표시는 자동으로 무시된다(BibleVerseCopyFormatter 참고).
    var copyRepeatReferenceForEachVerse: Bool {
        didSet { defaults.set(copyRepeatReferenceForEachVerse, forKey: Key.copyRepeatReferenceForEachVerse) }
    }

    var copyShowVerseNumbers: Bool {
        didSet { defaults.set(copyShowVerseNumbers, forKey: Key.copyShowVerseNumbers) }
    }

    var copyVerseNumberStyle: VerseNumberStyle {
        didSet { defaults.set(copyVerseNumberStyle.rawValue, forKey: Key.copyVerseNumberStyle) }
    }

    /// 켜면 선택한 구절 중 첫 번째 구절에도 번호를 붙인다(꺼져 있으면 첫 구절은
    /// 번호 없이, 두 번째 구절부터 번호가 붙는다 — "1:1처럼 문맥상 명백한 첫 절은
    /// 번호를 생략하고 싶다"는 사용 패턴을 위한 옵션).
    var copyShowFirstVerseNumber: Bool {
        didSet { defaults.set(copyShowFirstVerseNumber, forKey: Key.copyShowFirstVerseNumber) }
    }

    /// `copyReferencePosition`과 `copyTranslationLabelPosition`이
    /// 같은 쪽(둘 다 본문 앞 또는 둘 다 본문 뒤)일 때만 의미가 있다. 켜면 한
    /// 괄호 안에 합친다 — 예: "[NKJV 창세기 1:1]". 끄면 같은 괄호 스타일로 각각
    /// 감싸 나란히 붙인다 — 예: "[NKJV][창세기 1:1]". 두 위치가 다르면 이 설정과
    /// 무관하게 항상 분리된 형태(번역본 이름표가 독립된 줄)로 나온다.
    var copyCombineReferenceAndTranslationLabel: Bool {
        didSet { defaults.set(copyCombineReferenceAndTranslationLabel, forKey: Key.copyCombineReferenceAndTranslationLabel) }
    }

    /// `OutlineSeedImporter.importIfNeeded`용 — 번들 기본 개요(`OutlineSeed.sqlite`)를
    /// 사용자 DB로 한 번만 복사했는지.
    var hasImportedOutlineSeed: Bool {
        didSet { defaults.set(hasImportedOutlineSeed, forKey: Key.hasImportedOutlineSeed) }
    }

    /// 개요 트리(`OutlineTreeView`)에서 펼쳐 둔 구약/신약 — `"old"`/`"new"`(`Testament.rawValue`)만 들어간다.
    var outlineExpandedTestaments: [String] {
        didSet { defaults.set(outlineExpandedTestaments, forKey: Key.outlineExpandedTestaments) }
    }

    /// 개요 트리에서 펼쳐 둔 책들의 `bookId` 목록.
    var outlineExpandedBookIds: [Int] {
        didSet { defaults.set(outlineExpandedBookIds, forKey: Key.outlineExpandedBookIds) }
    }

    /// `CrossReferenceSeedImporter.importIfNeeded`용 — 번들 기본 관주
    /// (`Resources/CrossReferenceSeed.json`)를 사용자 DB로 한 번만 복사했는지.
    var hasImportedCrossReferenceSeed: Bool {
        didSet { defaults.set(hasImportedCrossReferenceSeed, forKey: Key.hasImportedCrossReferenceSeed) }
    }

    /// `MarginalNoteSeedImporter.importIfNeeded`용 — 번들 기본 난외주
    /// (`Resources/MarginalNoteSeed.json`)를 사용자 DB로 한 번만 복사했는지.
    var hasImportedMarginalNoteSeed: Bool {
        didSet { defaults.set(hasImportedMarginalNoteSeed, forKey: Key.hasImportedMarginalNoteSeed) }
    }

    /// `HanjaAnnotationSeedImporter.importIfNeeded`용 — 번들
    /// `Resources/HanjaAnnotationSeed.json`을 사용자 DB로 한 번만 복사했는지.
    var hasImportedHanjaAnnotationSeed: Bool {
        didSet { defaults.set(hasImportedHanjaAnnotationSeed, forKey: Key.hasImportedHanjaAnnotationSeed) }
    }

    /// `ReferenceDataMigration.cleanupLegacyBundledRecords`용 — JSON→SwiftData 시딩으로 이미
    /// 들어간 번들 관주/난외주 레코드를 1회성으로 정리했는지.
    var hasCleanedUpLegacyBundledReferenceData: Bool {
        didSet { defaults.set(hasCleanedUpLegacyBundledReferenceData, forKey: Key.hasCleanedUpLegacyBundledReferenceData) }
    }

    /// `SermonGatheringSeeder.seedIfNeeded`용 — 기본 모임 종류(주일설교/청년회 말씀/구역모임/조모임)를
    /// 시딩했는지.
    var hasSeededSermonGatherings: Bool {
        didSet { defaults.set(hasSeededSermonGatherings, forKey: Key.hasSeededSermonGatherings) }
    }

    /// `TranslationColumnView`가 개역한글 컬럼을 그릴 때 참고하는 한자 주석 표시 방식.
    var hanjaDisplayMode: HanjaDisplayMode {
        didSet { defaults.set(hanjaDisplayMode.rawValue, forKey: Key.hanjaDisplayMode) }
    }

    /// 한자 주석(성경 조회 인라인 표시 + 확대보기 한자 뜻풀이)에 쓰는 폰트. `bibleFontName`과
    /// 같은 규칙이며 기본값은 번들 조선궁서체(`SpecialPurposeFonts.hanja`). 등록되지 않았어도
    /// `Font.custom`이 시스템 폰트로 대체한다.
    var hanjaFontName: String {
        didSet { defaults.set(hanjaFontName, forKey: Key.hanjaFontName) }
    }

    // MARK: - 설교 작성 문단 스타일 폰트 (3단계, 2026-09-28 추가)
    //
    // 문단 스타일별 기본값(대주제=Paperlogy-8ExtraBold/34pt, 중주제=Paperlogy-6SemiBold/24pt,
    // 소주제=Paperlogy-5Medium/16pt, 말씀구절=ChosunGs/20pt, 본문=GowunBatang-Regular/19pt,
    // 인용=AppleGothic/17pt)은 설계 문서 3.3의 확정값이다.
    //
    // ⚠️ `sermonCitationFontName`의 기본값 "AppleGothic"은 번들 폰트가 아닌 시스템 폰트다.
    // macOS에는 내장돼 있으나 iOS/iPadOS에 같은 PostScript 이름이 있는지는 검증하지 못했다.
    // 없으면 `Font.custom`이 시스템 기본 폰트로 대체하므로 크래시는 없지만, "인용" 문단이
    // 의도와 다른 폰트로 보일 수 있다.
    var sermonMainThemeFontName: String {
        didSet { defaults.set(sermonMainThemeFontName, forKey: Key.sermonMainThemeFontName) }
    }
    var sermonMainThemeFontSize: Double {
        didSet { defaults.set(sermonMainThemeFontSize, forKey: Key.sermonMainThemeFontSize) }
    }
    var sermonMidThemeFontName: String {
        didSet { defaults.set(sermonMidThemeFontName, forKey: Key.sermonMidThemeFontName) }
    }
    var sermonMidThemeFontSize: Double {
        didSet { defaults.set(sermonMidThemeFontSize, forKey: Key.sermonMidThemeFontSize) }
    }
    var sermonSubThemeFontName: String {
        didSet { defaults.set(sermonSubThemeFontName, forKey: Key.sermonSubThemeFontName) }
    }
    var sermonSubThemeFontSize: Double {
        didSet { defaults.set(sermonSubThemeFontSize, forKey: Key.sermonSubThemeFontSize) }
    }
    var sermonVerseQuoteFontName: String {
        didSet { defaults.set(sermonVerseQuoteFontName, forKey: Key.sermonVerseQuoteFontName) }
    }
    var sermonVerseQuoteFontSize: Double {
        didSet { defaults.set(sermonVerseQuoteFontSize, forKey: Key.sermonVerseQuoteFontSize) }
    }
    var sermonCitationFontName: String {
        didSet { defaults.set(sermonCitationFontName, forKey: Key.sermonCitationFontName) }
    }
    var sermonCitationFontSize: Double {
        didSet { defaults.set(sermonCitationFontSize, forKey: Key.sermonCitationFontSize) }
    }
    var sermonBodyFontName: String {
        didSet { defaults.set(sermonBodyFontName, forKey: Key.sermonBodyFontName) }
    }
    var sermonBodyFontSize: Double {
        didSet { defaults.set(sermonBodyFontSize, forKey: Key.sermonBodyFontSize) }
    }
    var sermonMainThemeFontColorHex: String {
        didSet { defaults.set(sermonMainThemeFontColorHex, forKey: Key.sermonMainThemeFontColorHex) }
    }
    var sermonMidThemeFontColorHex: String {
        didSet { defaults.set(sermonMidThemeFontColorHex, forKey: Key.sermonMidThemeFontColorHex) }
    }
    var sermonSubThemeFontColorHex: String {
        didSet { defaults.set(sermonSubThemeFontColorHex, forKey: Key.sermonSubThemeFontColorHex) }
    }
    var sermonVerseQuoteFontColorHex: String {
        didSet { defaults.set(sermonVerseQuoteFontColorHex, forKey: Key.sermonVerseQuoteFontColorHex) }
    }
    var sermonCitationFontColorHex: String {
        didSet { defaults.set(sermonCitationFontColorHex, forKey: Key.sermonCitationFontColorHex) }
    }
    var sermonBodyFontColorHex: String {
        didSet { defaults.set(sermonBodyFontColorHex, forKey: Key.sermonBodyFontColorHex) }
    }
    var sermonVerseQuoteBackgroundColorHex: String {
        didSet { defaults.set(sermonVerseQuoteBackgroundColorHex, forKey: Key.sermonVerseQuoteBackgroundColorHex) }
    }
    var sermonVerseQuoteBarColorHex: String {
        didSet { defaults.set(sermonVerseQuoteBarColorHex, forKey: Key.sermonVerseQuoteBarColorHex) }
    }

    /// 뷰어 "Aa" 컨트롤이 조절하는 전체 배율(0.8~2.0, 기본 1.0). 스타일별 크기에 곱해져
    /// 상대 비율은 유지된다(`sermonFont(for:scale:)`).
    var sermonViewerFontScale: Double {
        didSet { defaults.set(sermonViewerFontScale, forKey: Key.sermonViewerFontScale) }
    }
    /// 좌우 페이지 넘기기(true)/세로 스크롤(false) 중 마지막으로 선택한 모드. 기본값은
    /// 내용이 잘려 보일 걱정이 없는 세로 스크롤(false).
    var sermonViewerUsesPageMode: Bool {
        didSet { defaults.set(sermonViewerUsesPageMode, forKey: Key.sermonViewerUsesPageMode) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.openLastScreenOnLaunch = defaults.object(forKey: Key.openLastScreenOnLaunch) as? Bool ?? true
        self.lastSelectedSectionRawValue = defaults.string(forKey: Key.lastSelectedSection)
        self.colorSchemePreference = (defaults.string(forKey: Key.colorSchemePreference)).flatMap(ColorSchemePreference.init) ?? .system
        self.hasCompletedOnboarding = defaults.object(forKey: Key.hasCompletedOnboarding) as? Bool ?? false
        self.lastSeenAppVersion = defaults.string(forKey: Key.lastSeenAppVersion)
        self.defaultTranslationCode = defaults.string(forKey: Key.defaultTranslationCode)
        self.defaultDisplayedTranslationCodes = defaults.stringArray(forKey: Key.defaultDisplayedTranslationCodes) ?? []
        self.lastManualSyncAt = defaults.object(forKey: Key.lastManualSyncAt) as? Date

        self.bibleFontName = defaults.string(forKey: Key.bibleFontName) ?? BundledFonts.defaultPostScriptName
        self.bibleBodyFontSize = defaults.object(forKey: Key.bibleBodyFontSize) as? Double ?? 17
        self.bibleVerseNumberFontSize = defaults.object(forKey: Key.bibleVerseNumberFontSize) as? Double ?? 12
        self.bibleLineSpacing = defaults.object(forKey: Key.bibleLineSpacing) as? Double ?? 4
        self.bibleVerseSpacing = defaults.object(forKey: Key.bibleVerseSpacing) as? Double ?? 10
        // 설정을 한 번도 건드리지 않은 신규 사용자는 "서재 아이보리" 테마로 시작한다.
        // ⚠️ 빈 문자열("")은 "명시적으로 시스템 기본으로 되돌린 상태"로도 쓰이므로, 비어 있다고
        // 채우면 시스템 기본으로 돌아갈 수 없게 된다. 그래서 키 자체가 저장된 적 없을 때
        // (`defaults.object(forKey:) == nil`)만 새 기본값을 쓰고, 저장된 값은 빈 문자열이어도
        // 그대로 존중한다.
        let defaultReadingTheme = BibleSlideColorTheme.all.first { $0.name == "서재 아이보리" }
        if defaults.object(forKey: Key.bibleTextColorHex) == nil {
            self.bibleTextColorHex = defaultReadingTheme?.textHex ?? ""
        } else {
            self.bibleTextColorHex = defaults.string(forKey: Key.bibleTextColorHex) ?? ""
        }
        if defaults.object(forKey: Key.bibleBackgroundColorHex) == nil {
            self.bibleBackgroundColorHex = defaultReadingTheme?.backgroundHex ?? ""
        } else {
            self.bibleBackgroundColorHex = defaults.string(forKey: Key.bibleBackgroundColorHex) ?? ""
        }
        // 위 "순수 신규 설치" 판정을 재사용 — 신규 설치는 모드도 `.light`로 맞춘다. 기존
        // 사용자는 저장된 모드를 존중하고, 없으면 커스텀(nil)으로 둔다(기존 hex가 삭제된
        // 프리셋 중 하나였을 수 있어 남은 2개 중 하나로 단정하지 않는다).
        if defaults.object(forKey: Key.bibleTextColorHex) == nil {
            self.bibleThemeModePreference = .light
        } else {
            self.bibleThemeModePreference = defaults.string(forKey: Key.bibleThemeModePreference).flatMap(BibleThemeModePreference.init)
        }

        self.copyReferencePosition = (defaults.string(forKey: Key.copyReferencePosition)).flatMap(TextPosition.init) ?? .afterBody
        self.copyReferenceBracketStyle = (defaults.string(forKey: Key.copyReferenceBracketStyle)).flatMap(ReferenceBracketStyle.init) ?? .square
        self.copyUseAbbreviatedBookName = defaults.object(forKey: Key.copyUseAbbreviatedBookName) as? Bool ?? false
        self.copyTranslationLabelPosition = (defaults.string(forKey: Key.copyTranslationLabelPosition)).flatMap(TextPosition.init) ?? .beforeBody
        self.copyNewlineBetweenVerses = defaults.object(forKey: Key.copyNewlineBetweenVerses) as? Bool ?? false
        self.copyRepeatReferenceForEachVerse = defaults.object(forKey: Key.copyRepeatReferenceForEachVerse) as? Bool ?? false
        self.copyShowVerseNumbers = defaults.object(forKey: Key.copyShowVerseNumbers) as? Bool ?? false
        self.copyVerseNumberStyle = (defaults.string(forKey: Key.copyVerseNumberStyle)).flatMap(VerseNumberStyle.init) ?? .parenthesis
        self.copyShowFirstVerseNumber = defaults.object(forKey: Key.copyShowFirstVerseNumber) as? Bool ?? false
        self.copyCombineReferenceAndTranslationLabel = defaults.object(forKey: Key.copyCombineReferenceAndTranslationLabel) as? Bool ?? true

        self.hasImportedOutlineSeed = defaults.object(forKey: Key.hasImportedOutlineSeed) as? Bool ?? false
        self.hasImportedCrossReferenceSeed = defaults.object(forKey: Key.hasImportedCrossReferenceSeed) as? Bool ?? false
        self.hasImportedMarginalNoteSeed = defaults.object(forKey: Key.hasImportedMarginalNoteSeed) as? Bool ?? false
        self.hasImportedHanjaAnnotationSeed = defaults.object(forKey: Key.hasImportedHanjaAnnotationSeed) as? Bool ?? false
        self.hasCleanedUpLegacyBundledReferenceData = defaults.object(forKey: Key.hasCleanedUpLegacyBundledReferenceData) as? Bool ?? false
        self.hasSeededSermonGatherings = defaults.object(forKey: Key.hasSeededSermonGatherings) as? Bool ?? false
        self.hanjaDisplayMode = (defaults.string(forKey: Key.hanjaDisplayMode)).flatMap(HanjaDisplayMode.init) ?? .off
        self.hanjaFontName = defaults.string(forKey: Key.hanjaFontName) ?? SpecialPurposeFonts.hanja
        // 설교 문단 스타일 기본 글자 크기(2026-10-01: 화면에 비해 커서 줄임 — 최종 대주제 25/중주제 20/소주제 17/말씀구절 15/인용 15/본문 15, 이전 34/24/16/20/17/19).
        // 이 값을 바꾸는 설정 UI가 없어 저장된 값이 없으므로 기본값 변경만으로 기존 기기에도 적용된다. 이미 저장된 설교 본문은
        // `styleFontSnapshot`이 옛 크기와 같은 글자를 "수동 지정이 아님"으로 보고 불러올 때 새 크기로 다시 입힌다.
        self.sermonMainThemeFontName = defaults.string(forKey: Key.sermonMainThemeFontName) ?? "Paperlogy-8ExtraBold"
        self.sermonMainThemeFontSize = defaults.object(forKey: Key.sermonMainThemeFontSize) as? Double ?? 25
        self.sermonMidThemeFontName = defaults.string(forKey: Key.sermonMidThemeFontName) ?? "Paperlogy-6SemiBold"
        self.sermonMidThemeFontSize = defaults.object(forKey: Key.sermonMidThemeFontSize) as? Double ?? 20
        self.sermonSubThemeFontName = defaults.string(forKey: Key.sermonSubThemeFontName) ?? "Paperlogy-5Medium"
        self.sermonSubThemeFontSize = defaults.object(forKey: Key.sermonSubThemeFontSize) as? Double ?? 17
        self.sermonVerseQuoteFontName = defaults.string(forKey: Key.sermonVerseQuoteFontName) ?? SpecialPurposeFonts.hanja
        self.sermonVerseQuoteFontSize = defaults.object(forKey: Key.sermonVerseQuoteFontSize) as? Double ?? 15
        self.sermonCitationFontName = defaults.string(forKey: Key.sermonCitationFontName) ?? "AppleGothic"
        self.sermonCitationFontSize = defaults.object(forKey: Key.sermonCitationFontSize) as? Double ?? 15
        self.sermonBodyFontName = defaults.string(forKey: Key.sermonBodyFontName) ?? "GowunBatang-Regular"
        self.sermonBodyFontSize = defaults.object(forKey: Key.sermonBodyFontSize) as? Double ?? 15
        // 글자색 기본값(목업 Editor.dc.html의 STYLE_DEFS 기반): 대주제/본문/말씀구절은 어두운
        // 무채색(#2B211D), 중주제는 와인색(#7A3B42), 소주제는 웜그레이(#6B5D52), 인용은 초록
        // 계열 지정에 맞춘 차분한 세이지 그린(#3F7355)이다. 정확한 톤이 지정된 값이 아니라
        // 제안 기본값이며, 설정에서 바꿀 수 있다.
        self.sermonMainThemeFontColorHex = defaults.string(forKey: Key.sermonMainThemeFontColorHex) ?? "#2B211D"
        self.sermonMidThemeFontColorHex = defaults.string(forKey: Key.sermonMidThemeFontColorHex) ?? "#7A3B42"
        self.sermonSubThemeFontColorHex = defaults.string(forKey: Key.sermonSubThemeFontColorHex) ?? "#6B5D52"
        self.sermonVerseQuoteFontColorHex = defaults.string(forKey: Key.sermonVerseQuoteFontColorHex) ?? "#2B211D"
        self.sermonCitationFontColorHex = defaults.string(forKey: Key.sermonCitationFontColorHex) ?? "#3F7355"
        self.sermonBodyFontColorHex = defaults.string(forKey: Key.sermonBodyFontColorHex) ?? "#2B211D"
        // 말씀구절 박스 배경색 기본값(목업의 --accent-soft).
        self.sermonVerseQuoteBackgroundColorHex = defaults.string(forKey: Key.sermonVerseQuoteBackgroundColorHex) ?? "#F3E4E1"
        self.sermonVerseQuoteBarColorHex = defaults.string(forKey: Key.sermonVerseQuoteBarColorHex) ?? "#7A3B42"
        self.sermonViewerFontScale = defaults.object(forKey: Key.sermonViewerFontScale) as? Double ?? 1.0
        self.sermonViewerUsesPageMode = defaults.object(forKey: Key.sermonViewerUsesPageMode) as? Bool ?? false

        // 구약을 펼친 채로 시작한다(39권이라 신약보다 자주 참조됨).
        self.outlineExpandedTestaments = defaults.stringArray(forKey: Key.outlineExpandedTestaments) ?? ["old"]
        self.outlineExpandedBookIds = defaults.array(forKey: Key.outlineExpandedBookIds) as? [Int] ?? []
    }
}

// MARK: - S1 표시 폰트 → SwiftUI 값 변환

extension UserSettingsStore {
    /// `TranslationColumnView`의 절 본문에 그대로 쓸 `Font`. `bibleFontName`이
    /// "System"이면 시스템 기본 서체를, 아니면 사용자가 고른 글꼴 이름으로
    /// `.custom`을 쓴다(글꼴 이름이 실제로 이 기기에 없으면 SwiftUI가 알아서
    /// 시스템 기본으로 대체한다 — 별도 존재 확인 로직이 필요 없다).
    var bibleBodyFont: Font {
        guard bibleFontName != "System" else { return .system(size: bibleBodyFontSize) }
        BundledFontRegistrar.ensureAvailable(bibleFontName)
        return .custom(bibleFontName, size: bibleBodyFontSize)
    }

    /// 절 번호에 쓰는 `Font` — 글꼴은 본문과 같게 맞추고 크기만 별도로 뺐다.
    var bibleVerseNumberFont: Font {
        guard bibleFontName != "System" else { return .system(size: bibleVerseNumberFontSize) }
        BundledFontRegistrar.ensureAvailable(bibleFontName)
        return .custom(bibleFontName, size: bibleVerseNumberFontSize)
    }

    /// `bibleTextColorHex`가 비어 있으면 nil을 돌려줘, 호출부가 시스템 기본색(`.primary`,
    /// 라이트/다크 자동 대응)을 쓰게 한다. hex → Color 단방향 변환(`Color+Hex.swift`)만 쓴다 —
    /// SwiftUI `Color`에서 hex를 다시 뽑는 안전한 공개 API가 없기 때문이다.
    var bibleTextColor: Color? {
        guard !bibleTextColorHex.isEmpty else { return nil }
        return Color(hex: bibleTextColorHex)
    }

    /// `bibleBackgroundColorHex`가 비어 있으면(기본값) nil을 돌려줘, 호출부가
    /// 시스템 기본 배경(라이트/다크 모드 자동 대응, 예: `.background(.clear)`나
    /// 배경 수정자 자체를 생략)을 쓰게 한다 — 위 `bibleTextColor`와 같은 이유.
    var bibleBackgroundColor: Color? {
        guard !bibleBackgroundColorHex.isEmpty else { return nil }
        return Color(hex: bibleBackgroundColorHex)
    }

    /// `hanjaFontName`을 SwiftUI `Font`로 바꾼다. 크기는 호출부마다 달라(성경 조회 인라인은
    /// 본문 크기, 확대보기 한자 뜻풀이는 17pt 고정) 인자로 받는다. 폰트가 등록되지 않았으면
    /// SwiftUI가 시스템 폰트로 대체한다.
    func hanjaFont(size: CGFloat) -> Font {
        guard hanjaFontName != "System" else { return .system(size: size) }
        BundledFontRegistrar.ensureAvailable(hanjaFontName)
        return .custom(hanjaFontName, size: size)
    }


    /// `SermonParagraphStyle` 하나를 SwiftUI `Font`로 바꾼다(폰트 미등록 시 시스템 기본으로
    /// 대체). `SermonParagraphEditor`(NSAttributedString 기반)는 이 값 대신 아래
    /// `sermonPlatformFont(for:)`를 쓰며, 이 함수는 순정 SwiftUI 화면(예: 스타일 드롭다운
    /// 라벨 미리보기)용이다.
    func sermonFont(for style: SermonParagraphStyle, scale: Double = 1.0) -> Font {
        let name = sermonFontName(for: style)
        let size = sermonFontSize(for: style) * scale
        guard name != "System" else { return .system(size: size) }
        BundledFontRegistrar.ensureAvailable(name)
        return .custom(name, size: size)
    }

    /// `SermonParagraphEditor`가 실제 텍스트 스토리지에 적용할 `PlatformFont`
    /// (iOS `UIFont`/macOS `NSFont`) — `EditorDefaultStyle.typingFont`와 같은
    /// 안전망(등록 실패 시 시스템 폰트로 대체).
    func sermonPlatformFont(for style: SermonParagraphStyle, scale: Double = 1.0) -> PlatformFont {
        let name = sermonFontName(for: style)
        let size = sermonFontSize(for: style) * scale
        guard name != "System" else { return .systemFont(ofSize: size) }
        BundledFontRegistrar.ensureAvailable(name)
        return PlatformFont(name: name, size: size) ?? .systemFont(ofSize: size)
    }

    /// 문단 스타일별 폰트 이름 — 위 두 함수가 중복 스위치문을 만들지 않도록
    /// 여기 한 곳에 모았다.
    func sermonFontName(for style: SermonParagraphStyle) -> String {
        switch style {
        case .mainTheme: return sermonMainThemeFontName
        case .midTheme: return sermonMidThemeFontName
        case .subTheme: return sermonSubThemeFontName
        case .verseQuote: return sermonVerseQuoteFontName
        case .citation: return sermonCitationFontName
        case .body: return sermonBodyFontName
        }
    }

    /// 문단 스타일별 폰트 크기 — 위 `sermonFontName(for:)`와 같은 이유.
    func sermonFontSize(for style: SermonParagraphStyle) -> Double {
        switch style {
        case .mainTheme: return sermonMainThemeFontSize
        case .midTheme: return sermonMidThemeFontSize
        case .subTheme: return sermonSubThemeFontSize
        case .verseQuote: return sermonVerseQuoteFontSize
        case .citation: return sermonCitationFontSize
        case .body: return sermonBodyFontSize
        }
    }

    /// 문단 스타일별 글자 색상(hex). `bibleTextColorHex`와 달리 빈 문자열이 "시스템 기본"을
    /// 뜻하지 않고, 6종 모두 항상 구체적인 값을 갖는다(`init` 참고).
    func sermonFontColorHex(for style: SermonParagraphStyle) -> String {
        switch style {
        case .mainTheme: return sermonMainThemeFontColorHex
        case .midTheme: return sermonMidThemeFontColorHex
        case .subTheme: return sermonSubThemeFontColorHex
        case .verseQuote: return sermonVerseQuoteFontColorHex
        case .citation: return sermonCitationFontColorHex
        case .body: return sermonBodyFontColorHex
        }
    }

    /// 순정 SwiftUI 화면(스타일 드롭다운 미리보기 등)용 `Color` — hex가 잘못된
    /// 값이면(이론상 발생하지 않지만 방어적으로) `.primary`로 안전하게 대체한다.
    func sermonFontColor(for style: SermonParagraphStyle) -> Color {
        Color(hex: sermonFontColorHex(for: style)) ?? .primary
    }

    /// `SermonParagraphEditor`가 실제 텍스트 스토리지에 적용할 `PlatformColor`
    /// (iOS `UIColor`/macOS `NSColor`) — `RichTextEditor.RichTextEditingProxy.
    /// applyColor(_:)`와 같은 hex → Color → PlatformColor 변환 관례를 그대로
    /// 따른다(`Color+Hex.swift` 참고).
    func sermonPlatformFontColor(for style: SermonParagraphStyle) -> PlatformColor {
        PlatformColor(sermonFontColor(for: style))
    }

    /// 말씀구절 박스 배경색 — `SermonParagraphStyleCodec.applyStyle`이
    /// `.verseQuote` 문단에만 `.backgroundColor` attribute로 적용한다(6-2번 항목).
    var sermonVerseQuoteBackgroundColor: Color {
        Color(hex: sermonVerseQuoteBackgroundColorHex) ?? Color(hex: "#F3E4E1")!
    }

    var sermonVerseQuoteBackgroundPlatformColor: PlatformColor {
        PlatformColor(sermonVerseQuoteBackgroundColor)
    }

    /// 말씀구절 박스 왼쪽 세로 바 색 설정값(뷰어가 편집기와 같은 서식을 그리게 되면서 현재는 화면에서 쓰지 않는다).
    var sermonVerseQuoteBarColor: Color {
        Color(hex: sermonVerseQuoteBarColorHex) ?? Color(hex: "#7A3B42")!
    }

    /// 문단 스타일별 줄간격 배수 — `RichTextEditor.lineHeightMultiple`과 같은 해석(1.0 = 추가
    /// 줄간격 없음). 대주제/중주제/소주제=1.4, 말씀구절/인용=1.7, 본문=1.6. 목업 STYLE_DEFS의
    /// line-height 기반이며, 목업이 말씀구절 값을 따로 명시하지 않아 같은 박스형 문단인
    /// 인용구 값(1.7)을 재사용했다.
    func sermonLineHeightMultiple(for style: SermonParagraphStyle) -> CGFloat {
        switch style {
        case .mainTheme: return 1.4
        case .midTheme: return 1.4
        case .subTheme: return 1.4
        case .verseQuote: return 1.7
        case .citation: return 1.7
        case .body: return 1.6
        }
    }
}
