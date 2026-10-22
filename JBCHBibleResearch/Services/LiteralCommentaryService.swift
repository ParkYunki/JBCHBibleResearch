//
//  LiteralCommentaryService.swift
//  JBCHBibleResearch
//
//  [2026-10-12 신설] 원문 정보 화면의 "직역"과 "번역과의 차이"를 언어·번역본에 맞춰 찾아 주는 앱 레이어 서비스.
//
//  - 직역: 앱 언어 기준. 한국어는 기존 `OriginalText.sqlite`의 `LiteralTranslation`(원어 → AI 직역),
//    다른 언어는 `Resources/Literal_<언어>.sqlite`의 `LiteralText`(원어·LSV 근거 AI 직역).
//  - 차이 설명: 번역본 코드 기준. KRV는 `LiteralTranslation.difference`, 그 밖의 번들 번역본은 그 번역본 언어의
//    `Literal_<언어>.sqlite` `TranslationDifference`. 데이터가 없으면 nil — 화면이 칸을 숨긴다.
//  - [2026-10-21] 사용자 추가 번역본은 절 본문 지문(`VerseTextFingerprint`)으로 알려진 번역본(NASB1995·NKJV1982·ABAB)을
//    알아보고 그 설명을 찾는다(`externalDifference`).
//  - `Literal_<언어>.sqlite`는 아직 생성 전이라 파일이 없으면 nil을 돌려준다(에러 아님).
//

import Foundation
import BibleResearchModels

@MainActor
final class LiteralCommentaryService {
    static let shared = LiteralCommentaryService()

    /// 언어 코드별 열린 DB. 파일이 없거나 열기에 실패한 언어는 `.some(nil)`로 기억해 다시 찾지 않는다.
    private var stores: [String: LiteralCommentaryStore?] = [:]

    private init() {}

    /// 앱 언어의 절 직역. 데이터가 없으면 nil.
    func appLanguageLiteral(bookId: Int, chapter: Int, verse: Int) -> String? {
        if AppLanguage.isKorean {
            let text = OriginalTextLookupService.shared
                .literalTranslation(bookId: bookId, chapter: chapter, verse: verse)?.literalTranslation
            return (text?.isEmpty ?? true) ? nil : text
        }
        guard let store = store(forLanguage: AppLanguage.baseCode) else { return nil }
        do {
            return try store.literalText(bookId: bookId, chapter: chapter, verse: verse)
        } catch {
            print("[LiteralCommentaryService] 직역 조회 실패: \(error)")
            return nil
        }
    }

    /// 번역본 하나와 원어의 차이 설명. 데이터가 없으면 nil.
    /// `verseText`: 그 번역본의 이 절 본문. 번들이 아닌(사용자가 추가한) 번역본은 이 본문의 지문으로 알려진 번역본을
    /// 알아보고 그 설명을 찾는다(`externalDifference`). 번들 번역본에서는 쓰지 않는다.
    func difference(translationCode: String, verseText: String? = nil, bookId: Int, chapter: Int, verse: Int) -> String? {
        if translationCode == TranslationBootstrap.bundledTranslationCode {
            let text = OriginalTextLookupService.shared
                .literalTranslation(bookId: bookId, chapter: chapter, verse: verse)?.difference
            return (text?.isEmpty ?? true) ? nil : text
        }
        if BundledTranslationCatalog.translation(forCode: translationCode) == nil {
            return externalDifference(userCode: translationCode, verseText: verseText,
                                      bookId: bookId, chapter: chapter, verse: verse)
        }
        // `Literal_<언어>.sqlite`는 기본 언어 코드로 이름 짓는다. 중국어 번들은 languageCodes가 "zh-Hant"/"zh-Hans"라
        // 문자 구분을 떼어 "zh"로 연다(두 번들의 설명은 같은 `Literal_zh.sqlite`에 번역본 코드별로 들어 있다). [2026-10-20]
        guard let code = BundledTranslationCatalog.translation(forCode: translationCode)?.languageCodes.first,
              let language = code.split(separator: "-").first.map(String.init),
              let store = store(forLanguage: language) else { return nil }
        do {
            return try store.difference(translationCode: translationCode, bookId: bookId, chapter: chapter, verse: verse)
        } catch {
            print("[LiteralCommentaryService] 차이 설명 조회 실패: \(error)")
            return nil
        }
    }

    // MARK: - 사용자 추가 번역본 [2026-10-21]
    //
    // 앱에 본문을 배포하지 않는 번역본(사용자가 적법하게 가진 파일을 추가한 경우)의 설명. 번역본은 사용자가 입력한 코드나
    // 파일 이름이 아니라 절 본문의 지문으로 알아본다(사용자 결정). 지문 표 `TranslationVerseHash`는 설명이 있는
    // `Literal_<언어>.sqlite`마다 들어 있다.

    /// 알아본 번역본 코드 → 설명이 들어 있는 언어(앞이 기본). 앱 언어 설명이 있으면 그것, 없으면 영어, 없으면 첫 언어.
    private static let externalNoteLanguages: [String: [String]] = [
        "NASB1995": ["en", "ko"],
        "NKJV1982": ["en", "ko"],
        "ABAB": ["fil"],
    ]

    /// 지문 표를 찾아볼 언어 — 위 표에 나오는 언어를 모두, 중복 없이(표를 고치면 함께 고친다).
    private static let externalLookupLanguages: [String] = ["en", "ko", "fil"]

    /// 사용자 번역본 코드 → 알아본 번역본 코드. 본문이 똑같은 절은 여러 번역본에 맞으므로, 한 번역본에만 맞는 절을
    /// 만나면 기억해 두고 이후 애매한 절에 쓴다. 기기 안에서만 기억한다(UserDefaults).
    private static let recognitionDefaultsKey = "literalCommentary.externalTranslationRecognition"
    private lazy var recognizedExternalCode: [String: String] =
        (UserDefaults.standard.dictionary(forKey: Self.recognitionDefaultsKey) as? [String: String]) ?? [:]

    private func externalDifference(userCode: String, verseText: String?, bookId: Int, chapter: Int, verse: Int) -> String? {
        guard let verseText, let hash = VerseTextFingerprint.hash(of: verseText) else { return nil }

        var candidates: [String] = []
        for language in Self.externalLookupLanguages {
            guard let store = store(forLanguage: language) else { continue }
            do {
                for code in try store.translationCodes(matchingVerseHash: hash, bookId: bookId, chapter: chapter, verse: verse)
                where !candidates.contains(code) {
                    candidates.append(code)
                }
            } catch {
                print("[LiteralCommentaryService] 번역본 지문 조회 실패: \(error)")
            }
        }
        guard !candidates.isEmpty else { return nil }

        let code: String
        if candidates.count == 1 {
            code = candidates[0]
            if recognizedExternalCode[userCode] != code {
                recognizedExternalCode[userCode] = code
                UserDefaults.standard.set(recognizedExternalCode, forKey: Self.recognitionDefaultsKey)
            }
        } else if let known = recognizedExternalCode[userCode], candidates.contains(known) {
            code = known
        } else {
            // 두 번역본의 본문이 이 절에서 똑같고 아직 어느 번역본인지 모른다 — 설명에 번역본 이름이 들어 있어
            // 다른 번역본의 설명을 보여 주면 틀리므로 숨긴다.
            return nil
        }

        let languages = Self.externalNoteLanguages[code] ?? []
        let preferred = AppLanguage.isKorean ? "ko" : AppLanguage.baseCode
        var ordered: [String] = []
        for language in [preferred, "en"] + languages where languages.contains(language) && !ordered.contains(language) {
            ordered.append(language)
        }
        for language in ordered {
            guard let store = store(forLanguage: language) else { continue }
            do {
                if let text = try store.difference(translationCode: code, bookId: bookId, chapter: chapter, verse: verse) {
                    return text
                }
            } catch {
                print("[LiteralCommentaryService] 차이 설명 조회 실패: \(error)")
            }
        }
        return nil
    }

    private func store(forLanguage language: String) -> LiteralCommentaryStore? {
        if let cached = stores[language] { return cached }
        var opened: LiteralCommentaryStore?
        if let url = Bundle.main.url(forResource: "Literal_\(language)", withExtension: "sqlite") {
            do {
                opened = try LiteralCommentaryStore(filePath: url.path)
            } catch {
                print("[LiteralCommentaryService] Literal_\(language).sqlite 열기 실패: \(error)")
            }
        }
        stores[language] = .some(opened)
        return opened
    }
}
