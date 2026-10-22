//
//  BundledTranslationCatalog.swift
//  JBCHBibleResearch
//
//  [2026-10-12 신설] 언어별 번들 성경 — "앱 언어마다 그 언어의 번들 성경 하나만 보인다"(사용자 결정).
//
//  - 한국어(ko)는 기존과 같이 개역한글(KRV, `Resources/BibleDB.sqlite`)이다.
//  - 다른 언어는 저작권 문제가 없는 번역본(퍼블릭 도메인 또는 앱 배포가 허용된 CC 라이선스)을 하나씩 번들한다.
//    파일은 `Resources/Bible_<code>.sqlite`(스키마는 KRV와 같은 `BibleVerses`). 원본·라이선스·변환 기록은
//    프로젝트 문서 `claude/bundled-bibles-2026-10-12.md` 참고.
//  - 그 언어의 파일이 아직 번들에 없거나(단계적 추가), 번들 성경이 없는 언어는 BSB(영어)를 쓴다(2026-10-20부터 zh도 번들 있음) —
//    번역본이 하나도 없는 빈 화면을 막기 위한 폴백이다(사용자 결정 2026-10-12). BSB 파일도 없으면 KRV.
//
//  "보이는 것"만 나눈다:
//  - 이 기기에는 앱 언어의 번들 하나만 `TranslationRegistry`에 등록한다(`TranslationBootstrap`).
//  - 레코드는 CloudKit으로 동기화되므로, 언어가 다른 기기에서 등록한 번들 레코드도 도착한다. 그래서 목록을 쓰는
//    곳(`ActiveTranslationResolver`, 설정 > 번역본, 성경 조회 폴백)은 `visible(_:)`로 다른 언어의 번들을 걸러낸다.
//  - 인물·지명·주제의 구절 본문, 질문형 검색 카드의 구절, 설교 말씀구절 삽입은 이 기기 언어의 번들(`current`)을 연다
//    (`TranslationBootstrap.resolvedCurrentLanguageBundledDatabaseURL()`, 사용자 결정 2026-10-12).
//  - 한자 주석·원문 정보의 "번역과의 차이"·본문 속 성경 참조 인식처럼 한국어 본문 자체가 전제인 기능은 계속
//    KRV를 직접 연다(`TranslationBootstrap.resolvedBundledDatabaseURL()`). 한자 주석은 KRV 열에서만 보인다.
//
//  `nonisolated`: 검색 등 백그라운드 경로에서도 부를 수 있게 한다. 불변 값만 읽는다.
//

import Foundation
import BibleResearchModels

nonisolated struct BundledTranslation: Hashable {
    /// `TranslationRegistry.code` — 기기 간 동기화·사용 중 목록(`defaultDisplayedTranslationCodes`)에서 쓰는 고정 식별자.
    let code: String
    /// 번역본 이름(원어 표기, 번역하지 않는다).
    let displayName: String
    /// 앱 번들 리소스 이름(확장자 `sqlite`).
    let resourceName: String
    /// 이 번들을 보여줄 앱 언어(`AppLanguage.baseCode`).
    let languageCodes: [String]
    /// 열 머리글 등에 쓸 책 이름표(`BookNameTable.BuiltInBookNameTable`). nil이면 한글 이름.
    let bookNameTableID: String?
    /// `TranslationRegistry.licenseType`에 기록하는 라이선스 요약.
    let licenseType: String
    /// 설정 > 라이센스 탭에 그대로 보여주는 저작권·출처 고지(원문 표기 — 번역하지 않는다). CC 라이선스는 저작자 표시가 의무다.
    /// ⚠️ 원본 배포본의 저작권 페이지(eBible.org `copr.htm`)와 맞춰야 한다 — 파일을 받을 때 대조해 갱신한다.
    let attribution: String
}

nonisolated enum BundledTranslationCatalog {
    typealias Names = BookNameTable.BuiltInBookNameTable

    /// 기본(폴백) 번들 — 개역한글. 코드는 `TranslationBootstrap.bundledTranslationCode`와 같다.
    static let korean = BundledTranslation(
        code: "KRV", displayName: "개역한글", resourceName: "BibleDB",
        languageCodes: ["ko"], bookNameTableID: nil, licenseType: "Public Domain (KBS 1961/1962)",
        attribution: "성경전서 개역한글판 ⓒ (재)대한성서공회"
    )

    static let all: [BundledTranslation] = [
        korean,
        BundledTranslation(code: "BSB", displayName: "Berean Standard Bible", resourceName: "Bible_BSB",
                           languageCodes: ["en"], bookNameTableID: Names.english, licenseType: "Public Domain",
                           attribution: "Berean Standard Bible — Public Domain (berean.bible). Text source: eBible.org"),
        BundledTranslation(code: "RV1909", displayName: "Reina-Valera 1909", resourceName: "Bible_RV1909",
                           languageCodes: ["es"], bookNameTableID: Names.spanish, licenseType: "Public Domain",
                           attribution: "Santa Biblia — Reina-Valera 1909 — Public Domain. Text source: eBible.org"),
        BundledTranslation(code: "LSG1910", displayName: "Louis Segond 1910", resourceName: "Bible_LSG1910",
                           languageCodes: ["fr"], bookNameTableID: Names.french, licenseType: "Public Domain",
                           attribution: "Louis Segond 1910 — Public Domain. Text source: eBible.org"),
        BundledTranslation(code: "LUT1912", displayName: "Lutherbibel 1912", resourceName: "Bible_LUT1912",
                           languageCodes: ["de"], bookNameTableID: Names.german, licenseType: "Public Domain",
                           attribution: "Lutherbibel 1912 — Public Domain. Text source: eBible.org"),
        BundledTranslation(code: "RIV1927", displayName: "Riveduta 1927", resourceName: "Bible_RIV1927",
                           languageCodes: ["it"], bookNameTableID: Names.italian, licenseType: "Public Domain",
                           attribution: "Riveduta Bibbia 1927 (Giovanni Luzzi) — Public Domain. Text source: eBible.org"),
        BundledTranslation(code: "BPM", displayName: "Bíblia Portuguesa Mundial", resourceName: "Bible_BPM",
                           languageCodes: ["pt"], bookNameTableID: Names.portuguese, licenseType: "Public Domain",
                           attribution: "Bíblia Portuguesa Mundial — Public Domain. Text source: eBible.org"),
        BundledTranslation(code: "SYN", displayName: "Синодальный перевод", resourceName: "Bible_SYN",
                           languageCodes: ["ru"], bookNameTableID: Names.russian, licenseType: "Public Domain",
                           attribution: "Синодальный перевод (1876) — Public Domain. Text source: eBible.org"),
        BundledTranslation(code: "VIE1934", displayName: "Kinh Thánh 1934", resourceName: "Bible_VIE1934",
                           languageCodes: ["vi"], bookNameTableID: Names.vietnamese, licenseType: "Public Domain",
                           attribution: "Kinh Thánh (1934) — Public Domain. Text source: eBible.org"),
        BundledTranslation(code: "TGLULB", displayName: "Banal na Bibliya (ULB)", resourceName: "Bible_TGLULB",
                           languageCodes: ["fil", "tl"], bookNameTableID: Names.tagalog, licenseType: "CC BY-SA 4.0",
                           attribution: "Banal na Bibliya (Unlocked Literal Bible, Tagalog) © 2018 Door43 World Missions Community — CC BY-SA 4.0 (creativecommons.org/licenses/by-sa/4.0). Text source: eBible.org"),
        BundledTranslation(code: "THKJV", displayName: "พระคัมภีร์ภาษาไทยฉบับ KJV", resourceName: "Bible_THKJV",
                           languageCodes: ["th"], bookNameTableID: Names.thai, licenseType: "CC BY-NC-ND 4.0",
                           attribution: "พระคัมภีร์ภาษาไทยฉบับ KJV © 2003 Philip Pope — CC BY-NC-ND 4.0 (creativecommons.org/licenses/by-nc-nd/4.0). Text source: eBible.org"),
        BundledTranslation(code: "AYT", displayName: "Alkitab Yang Terbuka", resourceName: "Bible_AYT",
                           languageCodes: ["id"], bookNameTableID: Names.english, licenseType: "CC BY-NC-SA (YLSA-AYT, non-commercial)",
                           attribution: "Alkitab Yang Terbuka (AYT) © 2011–2024 YLSA-AYT — non-commercial use, Creative Commons BY-NC-SA (ayt.co). Text source: eBible.org"),
        BundledTranslation(code: "JPBUNGO", displayName: "文語訳聖書", resourceName: "Bible_JPBUNGO",
                           languageCodes: ["ja"], bookNameTableID: Names.japanese, licenseType: "Public Domain",
                           attribution: "文語訳聖書（明治元訳 旧約 1887年・大正改訳 新約 1917年）— Public Domain"),
        // [2026-10-20] 중국어: 官話和合譯本 1919 원판(上帝版, 옛 구두점). 번체는 CCEL 전자 텍스트, 간체는 그것을
        // OpenCC로 변환한 것(사용자 결정). languageCodes는 `AppLanguage.bundleLanguageKey`("zh-Hant"/"zh-Hans")와 맞춘다.
        BundledTranslation(code: "CUV1919", displayName: "官話和合譯本（上帝版）", resourceName: "Bible_CUV1919",
                           languageCodes: ["zh-Hant"], bookNameTableID: Names.chineseTraditional, licenseType: "Public Domain",
                           attribution: "官話和合譯本（1919，上帝版）— Public Domain. Text source: CCEL (ccel.org), electronic text by Paul W. Sheng"),
        BundledTranslation(code: "CUV1919S", displayName: "官话和合译本（上帝版·简体）", resourceName: "Bible_CUV1919S",
                           languageCodes: ["zh-Hans"], bookNameTableID: Names.chineseSimplified, licenseType: "Public Domain",
                           attribution: "官话和合译本（1919，上帝版）简体字版 — Public Domain. Converted from the CCEL traditional text with OpenCC"),
    ]

    /// 설정 > 라이센스 탭에 고지할 번들 성경(KRV는 별도 섹션) — 실제로 앱에 들어 있는 것만.
    static let noticeEntries: [BundledTranslation] = all.filter { translation in
        translation.code != korean.code
            && Bundle.main.url(forResource: translation.resourceName, withExtension: "sqlite") != nil
    }

    static func translation(forCode code: String) -> BundledTranslation? {
        all.first { $0.code == code }
    }

    /// 영어 번들 — 번들 성경이 없는 언어의 폴백.
    static var english: BundledTranslation? { translation(forCode: "BSB") }

    /// 지금 앱 언어에서 보여줄 번들.
    /// 1) 그 언어의 번들 파일이 있으면 그것, 2) 한국어면 KRV, 3) 그 밖(번들이 없는 언어·파일이 아직 없는 언어)은 BSB,
    /// 4) BSB 파일도 없으면 KRV(빈 화면 방지).
    static let current: BundledTranslation = {
        let language = AppLanguage.baseCode
        // 중국어는 간체/번체 번들이 따로 있어 문자 구분까지 본다("zh-Hant"/"zh-Hans"). 그 밖은 baseCode와 같다.
        let key = AppLanguage.bundleLanguageKey
        if let match = all.first(where: { $0.languageCodes.contains(key) }), isInBundle(match) {
            return match
        }
        if language == "ko" { return korean }
        if let english, isInBundle(english) { return english }
        return korean
    }()

    private static func isInBundle(_ translation: BundledTranslation) -> Bool {
        Bundle.main.url(forResource: translation.resourceName, withExtension: "sqlite") != nil
    }

    /// 목록에 보여도 되는 번역본인지 — 사용자 추가 번역본은 항상, 번들은 지금 언어의 번들만.
    static func isVisible(_ registry: TranslationRegistry) -> Bool {
        !registry.isBundled || registry.code == current.code
    }

    static func visible(_ registries: [TranslationRegistry]) -> [TranslationRegistry] {
        registries.filter(isVisible)
    }
}
