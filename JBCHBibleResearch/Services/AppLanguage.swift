//
//  AppLanguage.swift
//  JBCHBibleResearch
//
//  [2026-10-11 신설] 국제화(i18n) — 앱이 지금 실제로 표시 중인 언어와, 그 언어에 맞춘 성경 책 이름.
//
//  - 언어 판별은 `Bundle.main.preferredLocalizations`를 쓴다. 사용자가 고른 시스템/앱별 언어 중
//    이 앱이 실제로 지원하는 언어(Localizable.xcstrings의 18개 언어)로 이미 좁혀진 값이라, 지원하지 않는 언어(예: 아랍어)를
//    쓰는 사용자도 앱이 고른 표시 언어를 정확히 반영한다. iOS·macOS 모두 언어를 바꾸면 앱이 다시
//    시작되므로 프로세스 수명 동안 한 번만 계산해 둔다.
//  - 책 이름은 내장 이름표(`BookNameTable`)에서 앱 언어에 맞는 표를 쓴다. 한국어는 기존과 같이
//    `Book.nameKo`/`Book.abbreviation`을 쓴다.
//  - ⚠️ 이 값은 "화면 표시용"이다. 본문 속 성경 참조 추출(`BibleReferenceExtractor`), 복사 형식
//    (`BibleVerseCopyFormatter`), 설교 본문에 삽입되는 참조 표기, 저장되는 관주 라벨처럼 한국어 이름을
//    전제로 하는 곳은 계속 `nameKo`/`abbreviation`을 쓴다.
//  - [2026-10-29 booklabel1] 자유 입력 파싱(`BooksProvider.matchBookPrefix`)은 한국어 후보·초성을 항상 인식하고,
//    한국어가 아닌 앱에서는 이 파일의 `bookNameTable`(fullNames/shortNames)도 후보로 함께 인식한다.
//
//  `nonisolated`: 프로젝트 기본 액터 격리(MainActor) 때문에 검색 등 백그라운드 경로에서 호출하지 못하게
//  되는 것을 막는다. 모두 불변 값만 읽는다.
//

import Foundation
import BibleResearchModels

nonisolated enum AppLanguage {
    /// 앱이 표시 중인 언어 코드("ko", "en", "es" …). 목록이 비는 예외 상황은 개발 언어(ko)로 본다.
    static let code: String = Bundle.main.preferredLocalizations.first ?? "ko"

    static var isKorean: Bool { code.hasPrefix("ko") }

    /// 지역·문자 구분을 뺀 언어 코드("pt-BR" → "pt", "zh-Hant" → "zh", "fil" → "fil").
    static var baseCode: String { code.split(separator: "-").first.map(String.init) ?? code }

    /// 번들 성경을 고를 때 쓰는 언어 키. 중국어만 문자 구분을 남긴다("zh-Hant…" → "zh-Hant", 그 밖의 "zh…" → "zh-Hans").
    /// 나머지 언어는 `baseCode`와 같다. [2026-10-20] 중국어 번들(CUV1919 번체/CUV1919S 간체) 추가.
    static var bundleLanguageKey: String {
        if code.hasPrefix("zh-Hant") { return "zh-Hant" }
        if code.hasPrefix("zh") { return "zh-Hans" }
        return baseCode
    }

    /// [2026-10-22] 참고자료(인물·지명·개요) 번역 데이터 언어 키. 한국어면 nil(= 기존 한국어 데이터 그대로).
    /// 사용자 확정: 중국어(zh-Hans/zh-Hant 모두) → "zh"(간체 데이터 하나뿐), 스페인어(es, es-MX …) → "es",
    /// 그 밖의 비한국어 → "en". 값은 `ReferenceData.sqlite`의 `*I18n.lang`, `OutlineSeed_<값>.json`과 같다.
    /// [2026-10-28 9차] 프랑스어(fr, fr-CA …) → "fr", 독일어(de …) → "de", 러시아어(ru …) → "ru" 추가. 지역 변형은
    /// `baseCode`로 묶는다(`bookNameTableID`와 같은 규칙). 이 목록은 `build_reference_data.py`의 `I18N_LANGS`와 같아야 한다 —
    /// 여기만 늘리고 DB를 다시 빌드하지 않으면 그 언어는 번역 행이 없어 한국어로 보인다(`ReferenceDataStore` 폴백).
    static var referenceDataLanguage: String? {
        if isKorean { return nil }
        if code.hasPrefix("zh") { return "zh" }
        switch baseCode {
        case "es", "fr", "de", "ru": return baseCode
        default: return "en"
        }
    }

    /// 앱 언어에 대응하는 내장 책 이름표 id. 한국어면 nil(= 한글 기본 이름).
    /// 지역 변형(en-CA, fr-CA, es-MX, pt-BR)은 언어 단위 이름표를 같이 쓴다.
    /// ⚠️ 인도네시아어(id)는 출처가 확인된 공개 책 이름 데이터를 아직 확보하지 못해 영어 이름표로 표시한다.
    static var bookNameTableID: String? {
        typealias T = BookNameTable.BuiltInBookNameTable
        // 중국어는 간체/번체가 서로 다른 이름표라 언어 코드 전체로 먼저 구분한다.
        if code.hasPrefix("zh-Hant") { return T.chineseTraditional }
        if code.hasPrefix("zh") { return T.chineseSimplified }
        switch baseCode {
        case "en", "id": return T.english
        case "es": return T.spanish
        case "fr": return T.french
        case "de": return T.german
        case "it": return T.italian
        case "ja": return T.japanese
        case "th": return T.thai
        case "pt": return T.portuguese
        case "ru": return T.russian
        case "vi": return T.vietnamese
        case "fil", "tl": return T.tagalog
        default: return nil
        }
    }

    /// 책 약칭과 장 번호를 이어 쓸 때의 구분 문자. 한국어·일본어·중국어는 붙여 쓰고("창1", "創1", "创世纪1"),
    /// 그 밖의 언어는 한 칸 띄운다("Gen 1", "1 Sam 3", "Бытие 1") — 띄어쓰기를 하는 문자 체계의 일반 참조 표기.
    /// [2026-10-29 booklabel1] 화면 표시 전용(`Book.displayShortReference(chapter:)`). 입력 해석은 공백 유무를 모두 받는다.
    static var bookChapterSeparator: String {
        if isKorean || baseCode == "ja" || baseCode == "zh" { return "" }
        return " "
    }

    /// 앱 언어 책 이름표(한 번만 만든다). 한국어면 nil.
    /// [2026-10-29 booklabel1] `BooksProvider.matchBookPrefix`가 입력 후보로 쓰도록 `fileprivate` → 모듈 내부 공개.
    static let bookNameTable: BookNameTable? = bookNameTableID.flatMap { id in
        BookNameTable.builtInBookNameTables().first { $0.id == id }
    }
}

extension Book {
    /// 화면 표시용 책 이름(예: ko "창세기", en "Genesis", es "Génesis", ja "創世記").
    /// 이름표에 해당 책 이름이 없으면 한글 이름으로 폴백한다(`BookNameTableProvider.displayName`과 같은 규칙).
    nonisolated var displayName: String {
        guard let table = AppLanguage.bookNameTable else { return nameKo }
        let index = bookId - 1
        guard table.fullNames.indices.contains(index), !table.fullNames[index].isEmpty else { return nameKo }
        return table.fullNames[index]
    }

    /// 화면 표시용 약칭(예: ko "창", en "Gen", es "Gén"). 약칭이 없으면 `displayName`.
    nonisolated var displayShortName: String {
        guard let table = AppLanguage.bookNameTable else { return abbreviation.first ?? nameKo }
        let index = bookId - 1
        if table.shortNames.indices.contains(index), !table.shortNames[index].isEmpty {
            return table.shortNames[index]
        }
        return displayName
    }

    /// 화면 표시용 "약칭+장" 문구(예: ko "창1", ja "創1", zh "创世纪1", en "Gen 1", es "1 Sam 3").
    /// 한국어는 기존 표시(`abbreviation.first ?? nameKo` + 장 번호, 공백 없음)와 같다.
    /// ⚠️ 저장·검색 키로 쓰지 않는다(앱 언어에 따라 값이 바뀐다).
    nonisolated func displayShortReference(chapter: Int) -> String {
        "\(displayShortName)\(AppLanguage.bookChapterSeparator)\(chapter)"
    }
}
