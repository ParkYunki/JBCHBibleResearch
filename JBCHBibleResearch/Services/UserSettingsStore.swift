//
//  UserSettingsStore.swift
//  JBCHBibleResearch
//
//  screens.md 8장(환경설정) 값 중 실제로 다른 화면이 참조하는 것들을 담는
//  UserDefaults 기반 저장소. 8장의 모든 항목을 다 담지는 않는다 — 이 타입에 없는
//  설정(동기화 일시중지, 저장공간 경로 등)은 SettingsView.swift가 UI만 갖고 있고
//  실제 동작에 연결돼 있지 않다는 뜻이다(SettingsView.swift 상단 주석 참고).
//
//  ⚠️ [범위] SwiftData/CloudKit로 옮기지 않고 UserDefaults를 쓴 이유: 이 값들은
//  "이 기기에서의 앱 사용 방식" 설정이지, 여러 기기에서 동기화돼야 하는 연구
//  데이터가 아니다(schema.md 어디에도 이런 종류의 설정을 CloudKit에 올리라는
//  요구사항이 없다) — `NSUbiquitousKeyValueStore`로 기기 간 동기화하는 방안도
//  있지만, 근거 없이 그렇게까지 확장하지 않았다.
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class UserSettingsStore {
    static let shared = UserSettingsStore()

    private let defaults: UserDefaults

    private enum Key {
        static let openLastScreenOnLaunch = "settings.openLastScreenOnLaunch"
        static let lastSelectedSection = "settings.lastSelectedSection"
        static let colorSchemePreference = "settings.colorSchemePreference"
        static let aiChapterDraftEnabled = "settings.aiChapterDraftEnabled"
        // [2026-08-19 추가] 사용자 요청 — "앱을 설치할 때, 처음 시작할 때 색인을
        // 자동으로 설치하면 안되는가?" 첫 실행 시 AI 의미검색 색인 만들기를
        // 자동으로 시작하면서 안내 화면을 보여준 적이 있는지 — 한 번 보여준
        // 뒤엔(완료/취소 여부와 무관하게) 앱을 켤 때마다 다시 뜨지 않게 막는
        // 용도. `BibleIndexOnboardingOverlay.swift` 참고.
        static let hasOfferedBibleIndexOnboarding = "settings.hasOfferedBibleIndexOnboarding"
        // [2026-08-28 추가] 사용자 요청 — "처음 설치하시는 사람을 위한 가이드
        // 화면"과 "업데이트 시 무엇이 바뀌었는지 소개하는 화면"을 구분하기 위한
        // 플래그 두 개. `hasCompletedOnboarding`은 `AppOnboardingOverlay.swift`의
        // 첫 실행 가이드 카루셀을 한 번만 보여주기 위한 완료 플래그 —
        // `hasOfferedBibleIndexOnboarding`과 같은 1회성 패턴. `lastSeenAppVersion`은
        // `WhatsNewOverlay.swift`가 "이번 버전의 새 소식을 이미 봤는지"를 판단하는
        // 데 쓰는, 마지막으로 본 `CFBundleShortVersionString` 값이다.
        static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
        static let lastSeenAppVersion = "settings.lastSeenAppVersion"
        static let defaultTranslationCode = "settings.defaultTranslationCode"
        static let defaultDisplayedTranslationCodes = "settings.defaultDisplayedTranslationCodes"
        static let lastManualSyncAt = "settings.lastManualSyncAt"
        // [2026-08-08 추가] S1(성경 조회) 표시 폰트 — 사용자 요청 "본문크기, 색상,
        // 절 크기, 줄간격, 글꼴".
        static let bibleFontName = "settings.bible.fontName"
        static let bibleBodyFontSize = "settings.bible.bodyFontSize"
        static let bibleVerseNumberFontSize = "settings.bible.verseNumberFontSize"
        static let bibleLineSpacing = "settings.bible.lineSpacing"
        static let bibleVerseSpacing = "settings.bible.verseSpacing"
        static let bibleTextColorHex = "settings.bible.textColorHex"
        static let bibleBackgroundColorHex = "settings.bible.backgroundColorHex"
        // [2026-08-08 추가] 성경 구절 복사 형식 — 사용자 요청, FormatTabView.swift
        // (사용자가 업로드한 참고 소스) 참고.
        static let copyReferencePosition = "settings.bible.copy.referencePosition"
        static let copyReferenceBracketStyle = "settings.bible.copy.referenceBracketStyle"
        static let copyUseAbbreviatedBookName = "settings.bible.copy.useAbbreviatedBookName"
        static let copyTranslationLabelPosition = "settings.bible.copy.translationLabelPosition"
        static let copyNewlineBetweenVerses = "settings.bible.copy.newlineBetweenVerses"
        static let copyRepeatReferenceForEachVerse = "settings.bible.copy.repeatReferenceForEachVerse"
        static let copyShowVerseNumbers = "settings.bible.copy.showVerseNumbers"
        static let copyVerseNumberStyle = "settings.bible.copy.verseNumberStyle"
        static let copyShowFirstVerseNumber = "settings.bible.copy.showFirstVerseNumber"
        // [2026-08-08 추가] "성경장절과 번역본이 동일하게 본문 앞/뒤에 위치했을 때,
        // 합쳐서 보일지 분리해서 보일지" — copyReferencePosition과
        // copyTranslationLabelPosition이 같은 값일 때만 의미가 있다.
        static let copyCombineReferenceAndTranslationLabel = "settings.bible.copy.combineReferenceAndTranslationLabel"
        // [2026-08-13 추가] 사용자 요청 — "개요 기본 정보를 앱의 기본 DB에 넣되,
        // 배포할 때는 사용자 DB로 복사해서 수정 가능하게." `OutlineSeedImporter`가
        // 이 값을 이용해 "이미 한 번 복사했는지"를 판단한다(딱 한 번만 실행,
        // 그 뒤엔 사용자가 지운 내용을 다시 채워 넣지 않도록).
        static let hasImportedOutlineSeed = "settings.hasImportedOutlineSeed"
        // [2026-08-14 추가] 사용자 요청 — "개요: 폴더 구조 ... 한번 펼친 폴더
        // 내용은 다음에 개요를 눌렀을 때에도 그 상태가 유지되도록." 왼쪽 트리의
        // 펼침 상태(구약/신약, 책)를 앱 재실행 후에도 유지하기 위해 저장한다.
        static let outlineExpandedTestaments = "settings.outline.expandedTestaments"
        static let outlineExpandedBookIds = "settings.outline.expandedBookIds"
        // [2026-08-14 추가] 사용자 요청 — "기본 관주 정보도 시딩하기를 원함 ...
        // 우선 넣어보고, 책을 보면서 확인을 하고자 함." `CrossReferenceSeedImporter`가
        // "이미 한 번 넣었는지"를 판단하는 데 쓴다 — `hasImportedOutlineSeed`와
        // 같은 1회성 플래그 패턴.
        static let hasImportedCrossReferenceSeed = "settings.hasImportedCrossReferenceSeed"
        // [2026-08-14 추가] 사용자 요청 — "개역한글 난외주 정보가 있음 ... 각주와
        // 국한문만." `MarginalNoteSeedImporter`용 1회성 플래그.
        static let hasImportedMarginalNoteSeed = "settings.hasImportedMarginalNoteSeed"
        // [2026-08-14 추가] 사용자 요청 — "두 번째 번역본(국한문 전체 중복
        // 테이블)을 지우고 → 절 단위 한자 주석 모델." `HanjaAnnotationSeedImporter`용
        // 1회성 플래그.
        static let hasImportedHanjaAnnotationSeed = "settings.hasImportedHanjaAnnotationSeed"
        // [2026-08-15 추가] 사용자 요청 — "성경관련 json seed 파일은 기본 제공
        // db에 넣을 것." 관주/난외주 번들분을 SwiftData에서 ReferenceData.sqlite로
        // 옮기며, 이전에 이미 SwiftData로 들어간 번들분을 1회성으로 정리하는
        // `ReferenceDataMigration.cleanupLegacyBundledRecords`용 플래그.
        static let hasCleanedUpLegacyBundledReferenceData = "settings.hasCleanedUpLegacyBundledReferenceData"
        // [2026-08-14 추가] 개역한글 본문에 한자 주석을 표시하는 방식 — "탭하면
        // 보기"/"항상 보기(국한문식)"/"끄기" 중 선택. 사용자가 "둘 다 지원,
        // 설정으로 전환"을 골라 셋 중 고르게 했다.
        static let hanjaDisplayMode = "settings.bible.hanjaDisplayMode"
        // [2026-08-19 추가] 사용자 요청 — "설정 내 모양 탭의 한자 주석 표시
        // 밑에 '한자' 폰트를 변경할 수 있는 기능 추가." `bibleFontName`과 같은
        // 패턴("System" 문자열이면 시스템 기본, 아니면 PostScript 이름) —
        // 다만 지금은 선택지가 `SpecialPurposeFonts.hanja`(조선궁서체) 하나뿐
        // 이라 사실상 켜기/끄기에 가깝다.
        static let hanjaFontName = "settings.bible.hanjaFontName"
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

    /// 성경 장절 표기를 감싸는 괄호 스타일. 사용자 요청 예시 그대로 두 가지만—
    /// [창세기 1:1] / (창세기 1:1).
    enum ReferenceBracketStyle: String, CaseIterable, Identifiable {
        case square, round
        var id: String { rawValue }
        var prefix: String { self == .square ? "[" : "(" }
        var suffix: String { self == .square ? "]" : ")" }
    }

    /// 절 번호 표시 스타일. 사용자 요청 예시 그대로 세 가지 — (1), [1], 1).
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

    /// [2026-08-14 추가] 개역한글 본문 한자 주석 표시 방식. `.off`가 기본값 —
    /// 두 번째 번들 번역본(국한문)을 없앤 대신 넣는 기능이라, 기존에 이 화면을
    /// 안 쓰던 사용자에게 갑자기 낯선 한자가 나타나지 않게 안전한 값으로 시작한다.
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

    /// 8.1 "시작 시 마지막으로 보던 화면 열기"(기본 켜짐).
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

    /// 8.6 화면 모드.
    var colorSchemePreference: ColorSchemePreference {
        didSet { defaults.set(colorSchemePreference.rawValue, forKey: Key.colorSchemePreference) }
    }

    /// 8.4 "장 개요 작성 시 AI 초안 제안 받기"(기본 켜짐) — `OutlineViewModel.
    /// isAIDraftAvailable`이 이 값과 `ChapterOutlineDraftService.isDraftAvailable`을
    /// AND로 묶어 최종 버튼 표시 여부를 정한다.
    var isAIChapterDraftEnabled: Bool {
        didSet { defaults.set(isAIChapterDraftEnabled, forKey: Key.aiChapterDraftEnabled) }
    }

    /// [2026-08-19 추가] `BibleIndexOnboardingOverlay`가 앱 첫 실행 시 딱 한 번만
    /// 뜨도록 막는 플래그. 사용자가 "백그라운드에서 계속하기"로 넘기든, 색인이
    /// 실제로 끝나든, 어느 쪽이든 한 번 보여준 뒤엔 true로 바뀐다 — 색인 진행
    /// 상태 자체는 `EmbeddingIndexingService.shared.status`가 앱을 껐다 켜도
    /// 그대로 남아 있으므로(디스크 파일 기반), 이 플래그는 오직 "안내 화면을
    /// 또 띄울지"만 결정한다.
    var hasOfferedBibleIndexOnboarding: Bool {
        didSet { defaults.set(hasOfferedBibleIndexOnboarding, forKey: Key.hasOfferedBibleIndexOnboarding) }
    }

    /// [2026-08-28 추가] `AppOnboardingOverlay.swift`가 앱 첫 실행 시 5페이지
    /// 가이드 카루셀을 딱 한 번만 보여주도록 막는 완료 플래그. 버튼으로 끝까지
    /// 넘기든 스와이프로 시트를 내리든(`onDismiss`에서 처리) 상관없이 true로
    /// 바뀐다. 이 값이 true가 되는 순간 `lastSeenAppVersion`도 현재 버전으로
    /// 같이 기록해, 방금 설치를 마친 사람에게 "새 소식" 화면이 곧바로 뜨지
    /// 않도록 한다(`WhatsNewOverlay.swift` 참고).
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    /// [2026-08-28 추가] `WhatsNewOverlay.swift`가 마지막으로 "새 소식" 화면을
    /// 보여준 시점의 앱 버전(`CFBundleShortVersionString`). 앱 실행 시 이 값과
    /// 현재 버전이 다르면(그리고 `hasCompletedOnboarding`이 true이면) 해당 버전의
    /// `WhatsNewContent` 항목을 찾아 보여주고, 보여준 뒤 현재 버전으로 갱신한다.
    /// 아직 한 번도 기록된 적 없으면(신규 설치) nil.
    var lastSeenAppVersion: String? {
        didSet { defaults.set(lastSeenAppVersion, forKey: Key.lastSeenAppVersion) }
    }

    /// 8.1 "기본 성경 번역본" 피커. `TranslationRegistry.code`를 저장한다 — S1이
    /// 아직 아무 번역본도 선택되지 않은 첫 진입 시(`BibleReadingViewModel.
    /// loadAvailableTranslations`) 이 코드를 우선 표시하도록 반영했다.
    var defaultTranslationCode: String? {
        didSet { defaults.set(defaultTranslationCode, forKey: Key.defaultTranslationCode) }
    }

    /// [2026-08-07 추가, 원본 문서 재확인으로 발견한 누락] screens.md 8.3 "성경
    /// 조회(S1) 기본 표시 3개 체크박스 선택" — `defaultTranslationCode`(8.1, 단일
    /// 선택 "맨 앞으로 당기기" 용도)와는 다른 별개 항목이다. 여기엔 S1이 처음 열릴
    /// 때 3개 컬럼에 기본으로 띄울 번역본을 사용자가 직접 고른 목록(등록 순서와
    /// 무관하게, 고른 순서 그대로)을 저장한다. 비어 있으면(기본값) `BibleReadingViewModel
    /// .loadAvailableTranslations()`가 기존처럼 "등록 순 + defaultTranslationCode
    /// 맨 앞" 규칙으로 대체한다 — 즉 이 설정은 "있으면 우선, 없으면 기존 동작 유지"다.
    var defaultDisplayedTranslationCodes: [String] {
        didSet { defaults.set(defaultDisplayedTranslationCodes, forKey: Key.defaultDisplayedTranslationCodes) }
    }

    /// [2026-08-07 추가, 원본 문서 재확인으로 발견한 누락] screens.md 8.2(동기화)
    /// "마지막 동기화 시각" 표시 항목 — 지금까지 SyncSettingsTab엔 이 정보 자체가
    /// 없었다. `modelContext.save()`가 성공한 시각을 기록할 뿐, 실제 iCloud 업로드
    /// 완료 시각은 아니다(SwiftData/CloudKit엔 "지금 업로드 다 됐다"를 알려주는
    /// 표준 API가 없다 — SyncSettingsTab의 기존 ⚠️ 주석과 같은 한계) — 그래서
    /// "마지막으로 로컬 저장을 시도한 시각"이라는 의미로만 쓴다.
    var lastManualSyncAt: Date? {
        didSet { defaults.set(lastManualSyncAt, forKey: Key.lastManualSyncAt) }
    }

    // MARK: - S1 표시 폰트 (2026-08-08 추가)

    /// `NSFontManager.shared.availableFontFamilies`/`UIFont.familyNames`에서 고른
    /// 글꼴 이름, 내장 Paperlogy 폰트의 PostScript 이름(`BundledFonts.entries`),
    /// 또는 "System"(시스템 기본 서체). [2026-08-08 변경] 사용자 요청으로 기본값을
    /// "System"에서 내장 기본 글꼴(`BundledFonts.defaultPostScriptName` =
    /// "Paperlogy-4Regular")로 바꿨다 — 아직 Xcode 타겟에 폰트 파일이 등록되지
    /// 않아 실제로 로드되지 않는 상태여도, `bibleBodyFont`가 알아서 시스템 폰트로
    /// 대체하므로 안전하다(BundledFontRegistrar.swift 상단 주석 참고).
    /// [2026-08-11] 한때 이 기본값을 "System"으로 되돌렸다가, 사용자 요청이
    /// 이 S1 성경 조회 글꼴이 아니라 "환경설정 화면 자체의 메뉴/타이틀 글꼴"을
    /// 가리킨 것으로 확인돼 다시 원래대로(내장 Paperlogy) 되돌렸다 — 환경설정
    /// 화면 자체의 글꼴은 대신 SettingsView.swift/JBCHBibleResearchApp.swift에서
    /// 처리한다(`.appDefaultFont()`를 그 화면들에만 적용하지 않는 방식).
    var bibleFontName: String {
        didSet { defaults.set(bibleFontName, forKey: Key.bibleFontName) }
    }

    /// 본문(절 텍스트) 크기. 기존 `TranslationColumnView`가 고정으로 쓰던
    /// `.font(.body)`(시스템 기본, 대략 17pt)를 대체한다.
    var bibleBodyFontSize: Double {
        didSet { defaults.set(bibleBodyFontSize, forKey: Key.bibleBodyFontSize) }
    }

    /// 절 번호(맨 앞 숫자) 크기. 기존엔 `.font(.caption)`(고정)이었다.
    var bibleVerseNumberFontSize: Double {
        didSet { defaults.set(bibleVerseNumberFontSize, forKey: Key.bibleVerseNumberFontSize) }
    }

    /// 절과 절 사이 줄간격. SwiftUI `Text.lineSpacing(_:)`에 그대로 전달한다.
    var bibleLineSpacing: Double {
        didSet { defaults.set(bibleLineSpacing, forKey: Key.bibleLineSpacing) }
    }

    /// [2026-08-20 추가] 사용자 요청 — "성경조회표시 - 본문색상 위 절 간격 조절
    /// 기능추가". `bibleLineSpacing`(한 절 안에서 줄바꿈될 때의 줄간격)과는
    /// 다른 값이다 — 이건 절과 절(각 `VerseRow`) 사이의 간격으로,
    /// `TranslationColumnView.columnScrollView`의 `LazyVStack(spacing:)`에
    /// 전달한다(기존엔 10으로 고정돼 있었다).
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

    /// [2026-09-01 추가] 사용자 요청 — "성경 조회 배경색/글자색 테마색상 추가."
    /// 배경색도 위 `bibleTextColorHex`와 완전히 같은 패턴(빈 문자열 = 시스템
    /// 기본 배경, 사용자가 명시적으로 고르기 전엔 손대지 않음)으로 저장한다.
    var bibleBackgroundColorHex: String {
        didSet { defaults.set(bibleBackgroundColorHex, forKey: Key.bibleBackgroundColorHex) }
    }

    // MARK: - 성경 구절 복사 형식 (2026-08-08 추가)
    //
    // 사용자가 참고 소스로 올린 FormatTabView.swift의 설정 항목을 이 앱의 저장
    // 방식(UserDefaults 기반 @Observable 프로퍼티)으로 옮긴 것 — 이름과 의미는
    // 최대한 그대로 유지했다. 다만 FormatTabView.swift에는 없던 항목 하나를
    // 추가했다: `copyTranslationLabelPosition` — 이 앱은 S1에서 번역본을 최대
    // 3개까지 나란히 볼 수 있어서, 여러 번역본을 한꺼번에 복사할 때 "번역본
    // 이름표를 본문 앞/뒤 중 어디에 둘지"가 원본 앱에는 없던 새로운 결정 지점이다.

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

    /// `copyNewlineBetweenVerses`가 켜져 있을 때만 의미가 있다 — 켜면 매 절마다
    /// "장:절 본문" 형태로 반복하고, 이 경우 절 번호 표시는 의미가 없어져
    /// 자동으로 무시된다(BibleVerseCopyFormatter 참고, FormatTabView.swift의
    /// `.disabled(repeatReferenceForEachVerse)`와 같은 원칙).
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

    /// [2026-08-08 추가] `copyReferencePosition`과 `copyTranslationLabelPosition`이
    /// 같은 쪽(둘 다 본문 앞 또는 둘 다 본문 뒤)일 때만 의미가 있다. 켜면 한
    /// 괄호 안에 합친다 — 예: "[NKJV 창세기 1:1]". 끄면 같은 괄호 스타일로 각각
    /// 감싸 나란히 붙인다 — 예: "[NKJV][창세기 1:1]". 두 위치가 다르면 이 설정과
    /// 무관하게 항상 분리된 형태(번역본 이름표가 독립된 줄)로 나온다.
    var copyCombineReferenceAndTranslationLabel: Bool {
        didSet { defaults.set(copyCombineReferenceAndTranslationLabel, forKey: Key.copyCombineReferenceAndTranslationLabel) }
    }

    /// [2026-08-13 추가] `OutlineSeedImporter.importIfNeeded` 참고 — 앱 번들에
    /// 든 기본 개요(`OutlineSeed.sqlite`)를 사용자 DB로 딱 한 번만 복사하기 위한
    /// 완료 플래그.
    var hasImportedOutlineSeed: Bool {
        didSet { defaults.set(hasImportedOutlineSeed, forKey: Key.hasImportedOutlineSeed) }
    }

    /// [2026-08-14 추가] 개요 트리(`OutlineTreeView`)에서 펼쳐 둔 구약/신약 —
    /// 값은 `"old"`/`"new"`(`Testament.rawValue`)만 들어간다.
    var outlineExpandedTestaments: [String] {
        didSet { defaults.set(outlineExpandedTestaments, forKey: Key.outlineExpandedTestaments) }
    }

    /// 개요 트리에서 펼쳐 둔 책들의 `bookId` 목록.
    var outlineExpandedBookIds: [Int] {
        didSet { defaults.set(outlineExpandedBookIds, forKey: Key.outlineExpandedBookIds) }
    }

    /// [2026-08-14 추가] `CrossReferenceSeedImporter.importIfNeeded` 참고 — 앱
    /// 번들에 든 기본 관주(`Resources/CrossReferenceSeed.json`)를 사용자 DB로
    /// 딱 한 번만 복사하기 위한 완료 플래그. `hasImportedOutlineSeed`와 동일한
    /// 패턴.
    var hasImportedCrossReferenceSeed: Bool {
        didSet { defaults.set(hasImportedCrossReferenceSeed, forKey: Key.hasImportedCrossReferenceSeed) }
    }

    /// [2026-08-14 추가] `MarginalNoteSeedImporter.importIfNeeded` 참고 — 앱
    /// 번들에 든 기본 난외주(`Resources/MarginalNoteSeed.json`)를 사용자 DB로
    /// 딱 한 번만 복사하기 위한 완료 플래그.
    var hasImportedMarginalNoteSeed: Bool {
        didSet { defaults.set(hasImportedMarginalNoteSeed, forKey: Key.hasImportedMarginalNoteSeed) }
    }

    /// [2026-08-14 추가] `HanjaAnnotationSeedImporter.importIfNeeded` 참고 — 앱
    /// 번들에 든 `Resources/HanjaAnnotationSeed.json`을 사용자 DB로 딱 한 번만
    /// 복사하기 위한 완료 플래그.
    var hasImportedHanjaAnnotationSeed: Bool {
        didSet { defaults.set(hasImportedHanjaAnnotationSeed, forKey: Key.hasImportedHanjaAnnotationSeed) }
    }

    /// [2026-08-15 추가] `ReferenceDataMigration.cleanupLegacyBundledRecords` 참고 —
    /// 예전 방식(JSON→SwiftData 1회성 시딩)으로 이미 들어간 번들 관주/난외주
    /// 레코드를 1회성으로 정리했는지.
    var hasCleanedUpLegacyBundledReferenceData: Bool {
        didSet { defaults.set(hasCleanedUpLegacyBundledReferenceData, forKey: Key.hasCleanedUpLegacyBundledReferenceData) }
    }

    /// [2026-08-14 추가] `TranslationColumnView`가 개역한글 컬럼을 그릴 때 참고하는
    /// 한자 주석 표시 방식.
    var hanjaDisplayMode: HanjaDisplayMode {
        didSet { defaults.set(hanjaDisplayMode.rawValue, forKey: Key.hanjaDisplayMode) }
    }

    /// [2026-08-19 추가] 한자 주석(성경 조회 인라인 표시 + 확대보기 한자
    /// 뜻풀이)에 쓰는 폰트. `bibleFontName`과 똑같이 "System"이면 시스템 기본,
    /// 아니면 그 PostScript 이름을 그대로 쓴다. 기본값은 이 프로젝트가 번들한
    /// 조선궁서체(`SpecialPurposeFonts.hanja`) — 등록에 실패해도(Fonts 폴더가
    /// 타겟에 아직 안 걸려 있는 경우 등) `Font.custom`이 알아서 시스템 폰트로
    /// 대체하므로 안전하다(`BundledFontRegistrar.swift` 상단 주석과 같은 안전망).
    var hanjaFontName: String {
        didSet { defaults.set(hanjaFontName, forKey: Key.hanjaFontName) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.openLastScreenOnLaunch = defaults.object(forKey: Key.openLastScreenOnLaunch) as? Bool ?? true
        self.lastSelectedSectionRawValue = defaults.string(forKey: Key.lastSelectedSection)
        self.colorSchemePreference = (defaults.string(forKey: Key.colorSchemePreference)).flatMap(ColorSchemePreference.init) ?? .system
        self.isAIChapterDraftEnabled = defaults.object(forKey: Key.aiChapterDraftEnabled) as? Bool ?? true
        self.hasOfferedBibleIndexOnboarding = defaults.object(forKey: Key.hasOfferedBibleIndexOnboarding) as? Bool ?? false
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
        self.bibleTextColorHex = defaults.string(forKey: Key.bibleTextColorHex) ?? ""
        self.bibleBackgroundColorHex = defaults.string(forKey: Key.bibleBackgroundColorHex) ?? ""

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
        self.hanjaDisplayMode = (defaults.string(forKey: Key.hanjaDisplayMode)).flatMap(HanjaDisplayMode.init) ?? .off
        self.hanjaFontName = defaults.string(forKey: Key.hanjaFontName) ?? SpecialPurposeFonts.hanja

        // [2026-08-14 추가] 기본값 — 구약을 펼친 채로 시작하는 편이(책이 39권,
        // 신약보다 훨씬 자주 참조됨) 처음 여는 사용자에게 자연스럽다고 판단했다.
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

    /// `bibleTextColorHex`가 비어 있으면(기본값 — 사용자가 아직 색을 고르지
    /// 않음) nil을 돌려줘, 호출부가 `.foregroundStyle(.primary)`처럼 시스템
    /// 기본색(라이트/다크 모드 자동 대응)을 쓰게 한다. `Color+Hex.swift`의 기존
    /// 단방향 변환(hex → Color)을 그대로 재사용한다 — SwiftUI `Color`에서 값을
    /// 다시 hex로 뽑아내는 안전한 공개 API가 없다는 그 파일의 기존 제약과 같은
    /// 이유로, 설정 화면은 자유 색상 선택 대신 `Color.memoTextPalette`와 같은
    /// 미리 정한 팔레트에서만 고르게 한다(AppearanceSettingsTab 참고).
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

    /// [2026-08-19 추가] `hanjaFontName`을 실제 SwiftUI `Font`로 바꾼다 — 크기는
    /// 호출부마다 다르므로(성경 조회 인라인은 본문 크기를 따라가고, 확대보기
    /// 한자 뜻풀이는 17pt 고정) 인자로 받는다. `bibleBodyFont`와 같은 안전망 —
    /// 폰트가 실제로 등록되지 않았어도 SwiftUI가 알아서 시스템 폰트로 대체한다.
    func hanjaFont(size: CGFloat) -> Font {
        guard hanjaFontName != "System" else { return .system(size: size) }
        BundledFontRegistrar.ensureAvailable(hanjaFontName)
        return .custom(hanjaFontName, size: size)
    }
}
