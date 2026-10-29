//
//  TitleFont.swift
//  JBCHBibleResearch
//
//  [2026-10-12 신설] 기능 화면 타이틀 서체 선택 — 다국어에서 "한 단어 안에 글꼴이 섞이는" 문제를 막는다.
//
//  배경: 타이틀 서체 KMU80 성곡 세리프(`SpecialPurposeFonts.titleSerif`)에는 한글과 기본 라틴만 있고
//  é·ü·ñ·ç 같은 라틴 악센트, 키릴, 베트남어 성조 글자, 태국어가 없다. 시스템은 없는 글자만 골라 다른
//  글꼴로 대체하므로 "Créer"의 é만 다른 글꼴로 그려진다. 그래서 문자열 전체를 그 글자가 모두 있는
//  글꼴 하나로 바꾼다.
//
//  규칙(위에서부터 먼저 맞는 것):
//   1. 한글이 하나라도 있으면 KMU80 — 한국어 화면/한국어 데이터(인물·지명·문서 제목)는 기존과 똑같다.
//   2. 앱 언어의 기본 타이틀 서체(`languageDefaultPostScriptName`)가 KMU80이 아니고, 그 서체가 글자를
//      모두 가지면 그 서체 — 같은 언어 화면 안에서 고정 타이틀과 데이터 타이틀의 서체를 맞춘다.
//   3. KMU80이 글자를 모두 가지면 KMU80.
//   4. 태국 문자가 있으면 Noto Serif Thai(숫자·영문은 이 글꼴에 없어 시스템 글꼴로 대체된다).
//   5. Gentium이 글자를 모두 가지면 Gentium(라틴 악센트·키릴·베트남어).
//   6. 그 밖(다른 언어 앱의 일본어 가나·중국어 한자 등)은 KMU80 — 기존 동작(없는 글자는 시스템 글꼴로 대체)을 유지한다.
//  [2026-10-29 fontdef2] ja 앱의 기본 타이틀 서체는 Shippori Mincho, zh 앱(zh-Hans·zh-Hant)은 LXGW WenKai TC다. 두 글꼴은 그 언어
//  앱에서는 시작할 때 등록되고(다른 언어 앱은 `DeferredFontRegistry` 참고 — 그 앱의 타이틀은 이 글꼴을 고르지 않는다),
//  가나·한자·기본 라틴과 SemiBold/Bold 굵기(호출부의 `.fontWeight`)를 가진다(LXGW는 SemiBold 파일이 없어 가까운 굵기로
//  맞춰진다). 한글이 있는 타이틀은 규칙 1이 먼저라 그대로 KMU80이다. ja·zh-Hans·zh-Hant `Localizable.xcstrings` 값의 글자는
//  한국어 고지 문구(타이틀 아님)를 빼고 모두 각 글꼴에 있다(fontTools 실측).
//  글자 판정은 문자·결합 부호·숫자만 본다. 기호(✓, ⚠️ 등)는 어느 글꼴이든 시스템 대체로 그려지므로 제외한다.
//
//  고정 문구(`Text("말씀 노트")`처럼 로컬라이즈 키로 그리는 타이틀)는 실제 표시 문자열을 알 수 없어
//  앱 언어만으로 정한다(`Font.titleSerif(size:relativeTo:)`). 언어별 기본값은 2026-10-12 기준
//  `Localizable.xcstrings` 전 언어 값을 KMU80 문자표와 대조해 정했다 — ko/en/id/fil은 KMU80으로 모두
//  표시되고, de/es/fr/it/pt/ru/vi는 빠지는 글자가 있다.
//

import SwiftUI
import CoreText

enum TitleFont {
    /// 앱 언어 기준 타이틀 서체 PostScript 이름.
    static var languageDefaultPostScriptName: String {
        switch AppLanguage.baseCode {
        case "th":
            return SpecialPurposeFonts.titleSerifThai
        case "de", "es", "fr", "it", "pt", "ru", "vi":
            return SpecialPurposeFonts.titleSerifLatinFallback
        case "ja":
            // [2026-10-29 fontdef2] KMU80에는 가나만 있고 한자가 없어 한 단어 안에서 글꼴이 섞였다.
            return BundledFonts.shipporiMinchoRegularPostScriptName
        case "zh":
            // [2026-10-29 fontdef2] zh-Hans·zh-Hant 모두(`baseCode == "zh"`). KMU80에는 한자가 없다.
            return BundledFonts.lxgwWenKaiTCRegularPostScriptName
        default:
            // ko, en, id, fil: KMU80이 모든 글자를 가진다.
            return SpecialPurposeFonts.titleSerif
        }
    }

    /// 실제 표시 문자열 기준 타이틀 서체 PostScript 이름(파일 상단 규칙).
    static func postScriptName(for text: String) -> String {
        let scalars: [Unicode.Scalar] = text.unicodeScalars.filter(isCoverageRelevant)
        let primary = SpecialPurposeFonts.titleSerif
        if scalars.contains(where: isHangul) { return primary }

        let languageDefault = languageDefaultPostScriptName
        if languageDefault != primary, covers(languageDefault, scalars) { return languageDefault }
        if covers(primary, scalars) { return primary }
        if scalars.contains(where: isThai) { return SpecialPurposeFonts.titleSerifThai }
        if covers(SpecialPurposeFonts.titleSerifLatinFallback, scalars) { return SpecialPurposeFonts.titleSerifLatinFallback }
        return primary
    }

    // MARK: - 문자 판정

    /// 글꼴 대체 여부를 가르는 문자만 남긴다 — 문자(한글·라틴·키릴·태국 문자 등), 결합 부호(태국어 성조,
    /// 분해된 베트남어 부호), 숫자.
    private static func isCoverageRelevant(_ scalar: Unicode.Scalar) -> Bool {
        let properties = scalar.properties
        if properties.isAlphabetic { return true }
        switch properties.generalCategory {
        case .nonspacingMark, .spacingMark, .decimalNumber:
            return true
        default:
            return false
        }
    }

    private static func isHangul(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x11FF, 0x3130...0x318F, 0xA960...0xA97F, 0xAC00...0xD7AF, 0xD7B0...0xD7FF:
            return true
        default:
            return false
        }
    }

    private static func isThai(_ scalar: Unicode.Scalar) -> Bool {
        (0x0E00...0x0E7F).contains(scalar.value)
    }

    // MARK: - 글꼴 문자표

    /// PostScript 이름별 문자표 캐시. 글꼴이 아직 등록되지 않았으면 저장하지 않고 다음 호출에서 다시 구한다.
    private static var characterSets: [String: CharacterSet] = [:]

    private static func covers(_ postScriptName: String, _ scalars: [Unicode.Scalar]) -> Bool {
        guard let characterSet = characterSet(for: postScriptName) else { return false }
        return scalars.allSatisfy { characterSet.contains($0) }
    }

    /// `CTFontCreateWithName`은 이름에 맞는 글꼴이 없으면 다른 글꼴(대체 글꼴)을 돌려주므로,
    /// 실제로 받은 글꼴의 PostScript 이름이 요청과 같을 때만 문자표를 믿는다.
    private static func characterSet(for postScriptName: String) -> CharacterSet? {
        if let cached = characterSets[postScriptName] { return cached }
        BundledFontRegistrar.ensureAvailable(postScriptName)
        let font = CTFontCreateWithName(postScriptName as CFString, 12, nil)
        guard (CTFontCopyPostScriptName(font) as String) == postScriptName else { return nil }
        let characterSet = CTFontCopyCharacterSet(font) as CharacterSet
        characterSets[postScriptName] = characterSet
        return characterSet
    }
}

extension Font {
    /// 고정 문구 타이틀용 — 앱 언어 기준 타이틀 서체(`TitleFont.languageDefaultPostScriptName`).
    static func titleSerif(size: CGFloat, relativeTo textStyle: Font.TextStyle) -> Font {
        let name = TitleFont.languageDefaultPostScriptName
        BundledFontRegistrar.ensureAvailable(name)
        return .custom(name, size: size, relativeTo: textStyle)
    }

    /// 표시 문자열을 아는 타이틀용(데이터 이름·사용자 입력·조합 문자열) — 그 문자열의 글자를 모두 가진 서체.
    static func titleSerif(_ text: String, size: CGFloat, relativeTo textStyle: Font.TextStyle) -> Font {
        let name = TitleFont.postScriptName(for: text)
        BundledFontRegistrar.ensureAvailable(name)
        return .custom(name, size: size, relativeTo: textStyle)
    }
}
