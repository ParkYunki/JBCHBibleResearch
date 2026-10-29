//
//  BundledFontRegistrar.swift
//  JBCHBibleResearch
//
//  앱에 내장한 Paperlogy(9종)·고운바탕·다국어 글꼴(태국어/키릴/베트남어, 2026-10-12)·Literata·Shippori Mincho·LXGW WenKai TC(2026-10-29) 등 번들 글꼴을 앱 실행 시 한 번 CoreText에
//  등록해, SwiftUI `Font.custom(_:size:)`와 설정 화면 글꼴 목록에서 바로 쓰게 한다.
//
//  프로세스 단위(.process)로만 등록한다 — `.persistent`는 앱 삭제 후에도 흔적이 남을 수
//  있어 피한다. CTFontManagerRegisterFontsForURL은 macOS/iOS 공통 API라 플랫폼 분기가 없다.
//
//  ⚠️ `Fonts` 폴더가 앱 타겟의 "Copy Bundle Resources"에 포함돼 있어야 한다(폴더 참조/그룹
//  어느 쪽이든 조회함). 빠져 있으면 등록이 조용히 스킵되고 `Font.custom`은 시스템 기본
//  글꼴로 대체되므로 앱이 깨지지는 않는다.

import Foundation
import CoreText
import os
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// 내장 Paperlogy 폰트 9종의 메타데이터. 9개 굵기는 하나의 family 배리에이션이 아니라
/// 굵기마다 독립된 PostScript 이름/family 이름을 가지므로(.ttf name 테이블 확인),
/// `Font.custom`에는 family 이름이 아닌 PostScript 이름을 쓴다.
enum BundledFonts {
    struct Entry: Identifiable, Hashable {
        /// `Font.custom(_:size:)`/설정값 저장에 그대로 쓰는 실제 폰트 식별자.
        let postScriptName: String
        /// 설정 화면 Picker에 보여줄 사람이 읽기 좋은 이름.
        let displayName: String
        var id: String { postScriptName }
    }

    /// 가는 굵기 → 굵은 굵기 순.
    static let paperlogyEntries: [Entry] = [
        Entry(postScriptName: "Paperlogy-1Thin", displayName: "Paperlogy Thin"),
        Entry(postScriptName: "Paperlogy-2ExtraLight", displayName: "Paperlogy ExtraLight"),
        Entry(postScriptName: "Paperlogy-3Light", displayName: "Paperlogy Light"),
        Entry(postScriptName: "Paperlogy-4Regular", displayName: "Paperlogy Regular"),
        Entry(postScriptName: "Paperlogy-5Medium", displayName: "Paperlogy Medium"),
        Entry(postScriptName: "Paperlogy-6SemiBold", displayName: "Paperlogy SemiBold"),
        Entry(postScriptName: "Paperlogy-7Bold", displayName: "Paperlogy Bold"),
        Entry(postScriptName: "Paperlogy-8ExtraBold", displayName: "Paperlogy ExtraBold"),
        Entry(postScriptName: "Paperlogy-9Black", displayName: "Paperlogy Black"),
    ]

    /// 내장 고운바탕(OFL-1.1) 2종. Paperlogy와 같이 PostScript 이름으로 등록·선택한다.
    static let gowunBatangEntries: [Entry] = [
        Entry(postScriptName: "GowunBatang-Regular", displayName: String(localized: "고운바탕 Regular")),
        Entry(postScriptName: "GowunBatang-Bold", displayName: String(localized: "고운바탕 Bold")),
    ]

    /// 설정 화면 "내장 기본 글꼴" 섹션에 나열하는 전체 목록(Paperlogy 9종 + 고운바탕 2종).
    static let entries: [Entry] = paperlogyEntries + gowunBatangEntries

    /// 앱 기본 글꼴의 PostScript 이름.
    static let defaultPostScriptName = "Paperlogy-4Regular"

    /// 성경 조회 본문 글꼴(`UserSettingsStore.bibleFontName`)의 기본값 — 저장된 값이 없을 때만 쓴다.
    /// [2026-10-29 사용자 결정, fontdef1] 앱 언어(`AppLanguage.baseCode`)별 기본값:
    ///  - vi, ru와 라틴 문자 언어(en·en-CA, es·es-MX, fr·fr-CA, de, it, pt-BR, id, fil): Literata Regular
    ///  - th: Noto Serif Thai Regular (숫자·라틴·괄호·따옴표가 없어 그 글자만 시스템 글꼴로 대체된다)
    ///  - ja: Shippori Mincho Regular, zh(zh-Hans·zh-Hant 모두): LXGW WenKai TC Regular
    ///  - ko와 그 밖(목록에 없는 언어): 기존과 같은 Paperlogy Regular
    /// 이 앱에는 번역본별 글꼴 설정이 없어(본문 글꼴은 `bibleFontName` 하나) 앱 언어로 정한다. 번들 성경은 앱 언어의 것 하나만
    /// 보인다(`BundledTranslationCatalog.isVisible`).
    /// ⚠️ 설교 문단 스타일·메모 에디터 기본값(`languageAdjustedDefaultFontName`)은 이 값과 별개이며 바꾸지 않았다.
    static var bibleDefaultPostScriptName: String {
        switch AppLanguage.baseCode {
        case "vi", "ru", "en", "es", "fr", "de", "it", "pt", "id", "fil":
            return literataRegularPostScriptName
        case "th":
            return notoSerifThaiRegularPostScriptName
        case "ja":
            return shipporiMinchoRegularPostScriptName
        case "zh":
            return lxgwWenKaiTCRegularPostScriptName
        default:
            return defaultPostScriptName
        }
    }

    // MARK: 다국어 글꼴 (2026-10-12 추가)
    //
    // Paperlogy·고운바탕·KMU80에 없는 문자(태국어, 러시아어 키릴, 베트남어 성조 글자)를 같은 글꼴로
    // 일관되게 그리기 위해 번들한 SIL OFL 1.1 글꼴. 출처·라이선스는 `Fonts/OFL-*.txt`와 설정 > 라이센스 탭.
    //  - IBM Plex Sans Thai: google/fonts `ofl/ibmplexsansthai` (태국어 + 기본 라틴. 키릴·베트남어 없음)
    //  - Noto Serif Thai: notofonts.github.io `fonts/NotoSerifThai/hinted/ttf` (태국어만 — 라틴·숫자 없음,
    //    숫자/영문은 시스템 글꼴로 대체된다)
    //  - Inter: rsms/inter v4.1 `extras/ttf` (라틴·키릴·베트남어)
    //  - Be Vietnam Pro: google/fonts `ofl/bevietnampro` (라틴·베트남어. 키릴 없음)
    //  - Literata(2026-10-29): google/fonts `ofl/literata`의 가변 글꼴(opsz·wght)에서 fontTools instancer로 만든 정적 인스턴스
    //    4종(opsz 12 = 원본 fvar 기본값·named instance 값, wght 400/600/700, Italic 400). 이름 테이블은 Be Vietnam Pro와 같은
    //    규칙(Regular/Bold/Italic은 family "Literata", SemiBold는 family "Literata SemiBold" + 표시 family "Literata")으로 넣었다.
    //    라틴·베트남어·키릴·그리스어. 성경 본문용 세리프라 모든 앱 언어의 메뉴에 보인다(`Family.languageCode == nil`).
    //    Italic은 메뉴에 넣지 않는다 — 원문 정보 직역 카드의 `.italic()`, 메모 기울임 토글이 같은 family에서 찾아 쓴다.
    //  - Shippori Mincho(2026-10-29 fontdef1): google/fonts `ofl/shipporimincho` 원본 그대로(서브셋·수정 없음). Regular/SemiBold/Bold
    //    3종만 넣었다(본문·절 번호 `.weight(.semibold)`·굵게 토글). 일본어 가나·한자·라틴. 일본어 앱 메뉴에만 보인다.
    //  - LXGW WenKai TC(2026-10-29 fontdef1): google/fonts `ofl/lxgwwenkaitc` 원본 그대로. 원본에 SemiBold가 없어 Regular/Bold
    //    2종만 넣었다(Light는 쓰지 않음). 번체 기준이지만 CUV1919S(간체) 본문 글자도 1자(僈)를 빼고 모두 있다. 중국어 앱 메뉴에만 보인다.
    //    두 글꼴 모두 Italic이 없다. 파일 하나가 8~13MB라 메뉴는 해당 언어에서만 보이게 했다.
    // 굵기마다 family 이름이 따로라(name 테이블 확인) Paperlogy처럼 PostScript 이름으로 쓴다.
    // ⚠️ 이 글꼴들에는 한글이 없다. 한글이 섞이면 그 글자만 시스템 글꼴로 대체된다.

    /// 글꼴 메뉴의 서브메뉴 하나(family 이름 + 굵기별 항목). `languageCode`는 이 글꼴을 메뉴에 보여줄
    /// 앱 언어(`AppLanguage.baseCode`) — 지역 전용 글꼴이다(아래 `visibleMultilingualFamilies`). nil이면 모든 언어에 보인다.
    struct Family: Identifiable, Hashable {
        let name: String
        let entries: [Entry]
        let languageCode: String?
        var id: String { name }
    }

    static let literataRegularPostScriptName = "Literata-Regular"

    /// Literata 메뉴 항목. 번들 파일은 이 3종 + `Literata-Italic`(메뉴에 넣지 않음, `selectableFontCount`에 없음).
    static let literataEntries: [Entry] = [
        Entry(postScriptName: literataRegularPostScriptName, displayName: "Literata Regular"),
        Entry(postScriptName: "Literata-SemiBold", displayName: "Literata SemiBold"),
        Entry(postScriptName: "Literata-Bold", displayName: "Literata Bold"),
    ]

    static let ibmPlexSansThaiEntries: [Entry] = [
        Entry(postScriptName: "IBMPlexSansThai-Light", displayName: "IBM Plex Sans Thai Light"),
        Entry(postScriptName: "IBMPlexSansThai-Regular", displayName: "IBM Plex Sans Thai Regular"),
        Entry(postScriptName: "IBMPlexSansThai-Medium", displayName: "IBM Plex Sans Thai Medium"),
        Entry(postScriptName: "IBMPlexSansThai-SemiBold", displayName: "IBM Plex Sans Thai SemiBold"),
        Entry(postScriptName: "IBMPlexSansThai-Bold", displayName: "IBM Plex Sans Thai Bold"),
    ]

    /// `Fonts/NotoSerifThai-Regular.ttf` name 테이블 ID 6 값.
    static let notoSerifThaiRegularPostScriptName = "NotoSerifThai-Regular"

    static let notoSerifThaiEntries: [Entry] = [
        Entry(postScriptName: notoSerifThaiRegularPostScriptName, displayName: "Noto Serif Thai Regular"),
        Entry(postScriptName: "NotoSerifThai-Bold", displayName: "Noto Serif Thai Bold"),
    ]

    /// `Fonts/ShipporiMincho-*.ttf` name 테이블 ID 6 값(파일 이름과 같다).
    static let shipporiMinchoRegularPostScriptName = "ShipporiMincho-Regular"

    static let shipporiMinchoEntries: [Entry] = [
        Entry(postScriptName: shipporiMinchoRegularPostScriptName, displayName: "Shippori Mincho Regular"),
        Entry(postScriptName: "ShipporiMincho-SemiBold", displayName: "Shippori Mincho SemiBold"),
        Entry(postScriptName: "ShipporiMincho-Bold", displayName: "Shippori Mincho Bold"),
    ]

    /// `Fonts/LXGWWenKaiTC-*.ttf` name 테이블 ID 6 값(파일 이름과 같다).
    static let lxgwWenKaiTCRegularPostScriptName = "LXGWWenKaiTC-Regular"

    static let lxgwWenKaiTCEntries: [Entry] = [
        Entry(postScriptName: lxgwWenKaiTCRegularPostScriptName, displayName: "LXGW WenKai TC Regular"),
        Entry(postScriptName: "LXGWWenKaiTC-Bold", displayName: "LXGW WenKai TC Bold"),
    ]

    static let interEntries: [Entry] = [
        Entry(postScriptName: "Inter-Light", displayName: "Inter Light"),
        Entry(postScriptName: "Inter-Regular", displayName: "Inter Regular"),
        Entry(postScriptName: "Inter-Medium", displayName: "Inter Medium"),
        Entry(postScriptName: "Inter-SemiBold", displayName: "Inter SemiBold"),
        Entry(postScriptName: "Inter-Bold", displayName: "Inter Bold"),
        Entry(postScriptName: "Inter-ExtraBold", displayName: "Inter ExtraBold"),
    ]

    static let beVietnamProEntries: [Entry] = [
        Entry(postScriptName: "BeVietnamPro-Light", displayName: "Be Vietnam Pro Light"),
        Entry(postScriptName: "BeVietnamPro-Regular", displayName: "Be Vietnam Pro Regular"),
        Entry(postScriptName: "BeVietnamPro-Medium", displayName: "Be Vietnam Pro Medium"),
        Entry(postScriptName: "BeVietnamPro-SemiBold", displayName: "Be Vietnam Pro SemiBold"),
        Entry(postScriptName: "BeVietnamPro-Bold", displayName: "Be Vietnam Pro Bold"),
        Entry(postScriptName: "BeVietnamPro-ExtraBold", displayName: "Be Vietnam Pro ExtraBold"),
    ]

    /// 글꼴 메뉴(메모 에디터·설교 에디터)와 설정 > 성경 조회 글꼴 목록에 보여줄 다국어 글꼴 묶음.
    static let multilingualFamilies: [Family] = [
        Family(name: "Literata", entries: literataEntries, languageCode: nil),
        Family(name: "IBM Plex Sans Thai", entries: ibmPlexSansThaiEntries, languageCode: "th"),
        Family(name: "Noto Serif Thai", entries: notoSerifThaiEntries, languageCode: "th"),
        Family(name: "Inter", entries: interEntries, languageCode: "ru"),
        Family(name: "Be Vietnam Pro", entries: beVietnamProEntries, languageCode: "vi"),
        Family(name: "Shippori Mincho", entries: shipporiMinchoEntries, languageCode: "ja"),
        // zh-Hans·zh-Hant 모두 `AppLanguage.baseCode == "zh"`다.
        Family(name: "LXGW WenKai TC", entries: lxgwWenKaiTCEntries, languageCode: "zh"),
    ]

    // MARK: 공통 글꼴 / 지역 전용 글꼴 (2026-10-12, 사용자 결정: 앱 언어 기준)
    //
    // - 공통(모든 언어의 메뉴에 표시): Paperlogy, 고운바탕, Literata(2026-10-29)
    // - 지역 전용(그 앱 언어에서만 메뉴에 표시): IBM Plex Sans Thai·Noto Serif Thai(th), Inter(ru),
    //   Be Vietnam Pro(vi), Shippori Mincho(ja), LXGW WenKai TC(zh, 2026-10-29), 조선궁서체(ko — 한자 주석용 한국어 전용 글꼴)
    // 숨김은 "고르는 메뉴"에만 적용한다. 글꼴 파일은 모든 기기에 번들돼 있으므로 다른 언어 기기에서 만든
    // 문서·이미 저장된 설정은 그대로 그려진다. 설정 화면 Picker처럼 현재 선택값을 보여줘야 하는 곳은
    // 현재 선택된 글꼴이면 숨기지 않는다(그래야 빈칸으로 보이지 않는다). 타이틀 대체 서체(`TitleFont`)는
    // 자동 선택이라 이 구분과 무관하다.

    /// 지금 앱 언어의 메뉴에 보여줄 지역 전용 다국어 글꼴.
    static var visibleMultilingualFamilies: [Family] {
        multilingualFamilies.filter { $0.languageCode == nil || $0.languageCode == AppLanguage.baseCode }
    }

    /// 한국어 전용 글꼴(조선궁서체)을 메뉴에 보여줄지.
    static var isKoreanOnlyFontVisible: Bool { AppLanguage.isKorean }

    /// 시스템 글꼴 목록(설정 화면)에서 번들 글꼴이 중복으로 보이지 않게 걸러낼 family 이름 접두어.
    /// 등록된 번들 글꼴도 `UIFont.familyNames`/`NSFontManager.availableFontFamilies`에 나타난다.
    static let bundledFamilyNamePrefixes: [String] = [
        "Paperlogy", "IBM Plex Sans Thai", "Noto Serif Thai", "Inter", "Be Vietnam Pro", "Literata", "Shippori Mincho", "LXGW WenKai TC",
    ]

    /// 등록 확인 로그에 쓰는 번들 글꼴 총 개수(목록에서 고르는 글꼴만, 특수 목적 폰트 제외).
    static var selectableFontCount: Int {
        entries.count + multilingualFamilies.reduce(0) { $0 + $1.entries.count }
    }

    /// 기본 스타일 값(에디터 기본 글꼴, 설교 문단 스타일 기본 글꼴)을 앱 언어에 맞게 바꾼다.
    /// Paperlogy/고운바탕에 그 언어 글자가 없으면 같은 굵기의 다국어 글꼴로 바꾸고, 그 밖은 그대로 둔다.
    ///  - th: Paperlogy → IBM Plex Sans Thai(ExtraBold 이상은 Bold — 번들 최대 굵기), 고운바탕 → Noto Serif Thai
    ///  - ru: Paperlogy → Inter, 고운바탕 → Gentium(이미 번들, 키릴 지원)
    ///  - vi: Paperlogy → Be Vietnam Pro(Paperlogy는 베트남어 성조 글자 일부만 있어 한 단어 안에서 글꼴이 섞인다),
    ///        고운바탕은 베트남어를 모두 지원하므로 그대로
    /// ⚠️ "기본값"에만 쓴다. 사용자가 직접 고른 글꼴(저장된 값)과 이미 저장된 문서의 글꼴은 바꾸지 않는다.
    nonisolated static func languageAdjustedDefaultFontName(_ postScriptName: String) -> String {
        let language = AppLanguage.baseCode
        guard language == "th" || language == "ru" || language == "vi" else { return postScriptName }

        if postScriptName.hasPrefix("Paperlogy-") {
            let weight: String
            switch postScriptName {
            case "Paperlogy-1Thin", "Paperlogy-2ExtraLight", "Paperlogy-3Light": weight = "Light"
            case "Paperlogy-4Regular": weight = "Regular"
            case "Paperlogy-5Medium": weight = "Medium"
            case "Paperlogy-6SemiBold": weight = "SemiBold"
            case "Paperlogy-7Bold": weight = "Bold"
            case "Paperlogy-8ExtraBold", "Paperlogy-9Black": weight = language == "th" ? "Bold" : "ExtraBold"
            default: return postScriptName
            }
            switch language {
            case "th": return "IBMPlexSansThai-\(weight)"
            case "ru": return "Inter-\(weight)"
            default: return "BeVietnamPro-\(weight)"
            }
        }

        if postScriptName.hasPrefix("GowunBatang-") {
            let isBold = postScriptName == "GowunBatang-Bold"
            switch language {
            case "th": return isBold ? "NotoSerifThai-Bold" : "NotoSerifThai-Regular"
            case "ru": return isBold ? "Gentium-Bold" : "Gentium-Regular"
            default: return postScriptName
            }
        }
        return postScriptName
    }
}

/// 목록에서 고르는 범용 글꼴(`BundledFonts`)과 달리, 특정 언어 글자를 항상 이 글꼴로만
/// 렌더링하도록 고정하는 특수 목적 폰트 — 한자(ChosunGs)/히브리어(Ezra SIL)/그리스어(Gentium).
/// PostScript 이름은 family 이름이 아니라 각 .ttf name 테이블(ID 6)에서 확인한 값이다.
enum SpecialPurposeFonts {
    /// 한자 주석 기본 폰트 — 조선궁서체(ChosunGs.TTF). 지적재산권은 (주)조선일보사에 있고
    /// 개인/기업 무료 제공 라이선스라 표준 오픈소스 라이선스가 아니다 — 다른 프로젝트로
    /// 그대로 복사해 쓰지 말 것.
    static let hanja = "ChosunGs"
    /// 원문 정보 히브리어 표기 폰트 — Ezra SIL(SILEOT.ttf). 폰트는 SIL OFL 1.1,
    /// 히브리어 문자 배치 로직은 Ralph Hancock/John Hudson의 MIT 라이선스.
    static let hebrew = "EzraSIL"
    /// 원문 정보 그리스어 표기 폰트 — SIL Gentium(번들 파일 `Gentium-Regular.ttf`/
    /// `Gentium-Bold.ttf`, 실제 family/PostScript 이름은 "Gentium"/"Gentium-*"). SIL OFL 1.1.
    static let greekRegular = "Gentium-Regular"
    static let greekBold = "Gentium-Bold"

    /// 기능 화면 타이틀(말씀 노트/연구문서/통합 검색/성경 조회) 전용 서체 — 국민대학교
    /// 'KMU80 성곡 세리프'(`Fonts/KMU80SungkokSerif.otf`). PostScript 이름("KMU-SungkokSerif")은
    /// family 이름("KMU80 Sungkok Serif")과 다르다. CC BY-ND 라이선스로, 고지 문구는 설정
    /// 화면 "라이센스" 탭에 있다. Regular 하나뿐이라 굵게 표시할 곳은 SwiftUI가 화면에서만
    /// 합성 볼드를 적용하며 폰트 파일 자체는 변경하지 않는다.
    static let titleSerif = "KMU-SungkokSerif"

    /// 타이틀 대체 서체(2026-10-12) — KMU80에 없는 라틴 악센트·키릴·베트남어 글자가 들어간 타이틀에
    /// 쓴다(`TitleFont` 참고). 이미 번들된 SIL Gentium(라틴·키릴·베트남어·그리스어 지원)을 재사용한다.
    static let titleSerifLatinFallback = "Gentium-Regular"
    /// 태국어 타이틀 서체 — Noto Serif Thai(태국어 글자만 있음, 숫자·영문은 시스템 글꼴로 대체).
    static let titleSerifThai = "NotoSerifThai-Regular"
}

enum BundledFontRegistrar {
    private(set) static var registeredPostScriptNames: [String] = []
    private static var didRegister = false

    /// 앱 시작 시 1회 호출한다(`JBCHBibleResearchApp.init()`). 중복 호출해도 안전하다.
    /// 사용자 선택 폰트(`BundledFonts.entries`)와 특수 목적 폰트(`SpecialPurposeFonts`)를
    /// 한 번에 모두 등록한다.
    /// [2026-10-29 fontdef2] 다른 앱 언어 전용 CJK 글꼴(`DeferredFontRegistry.fonts`)은 여기서 등록하지 않는다.
    /// 그 글꼴은 필요할 때 파일 하나씩 등록한다(`ensureAvailable`, `DeferredFontRegistry.registerFonts(referencedInRTF:)`).
    static func registerBundledFontsIfNeeded() {
        guard !didRegister else { return }
        didRegister = true

        let bundledURLs = bundledCustomFontURLs()
        guard !bundledURLs.isEmpty else {
            print("[BundledFontRegistrar] 번들 폰트 파일을 앱 번들에서 찾지 못했습니다 — Fonts 폴더가 Xcode 타겟(Copy Bundle Resources)에 포함돼 있는지 확인하세요. 등록 전까지는 시스템 기본 글꼴로 표시됩니다.")
            return
        }
        #if DEBUG
        DeferredFontRegistry.assertMatchesMenuFamilies()
        #endif
        // 파일 이름 = PostScript 이름(번들 규칙)이라 파일 이름으로 거른다.
        let urls = bundledURLs.filter { DeferredFontRegistry.font(named: $0.deletingPathExtension().lastPathComponent) == nil }

        for url in urls {
            var unmanagedError: Unmanaged<CFError>?
            let success = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &unmanagedError)
            if success {
                registeredPostScriptNames.append(url.deletingPathExtension().lastPathComponent)
            } else {
                let description = unmanagedError?.takeRetainedValue().localizedDescription ?? "알 수 없는 오류"
                print("[BundledFontRegistrar] \(url.lastPathComponent) 등록 실패: \(description)")
            }
        }
        // 한자 1 + 히브리어 1 + Gentium 5(그리스어/타이틀 대체 서체 — 번들 굵기 전체) + 타이틀 세리프 1
        // + Literata Italic 1(메뉴에 없는 기울임 짝, 2026-10-29)
        // − 이 앱 언어에서 시작 때 등록하지 않는 CJK 글꼴(ja 앱 2, zh 앱 3, 그 밖 5 — 2026-10-29 fontdef2)
        let expectedCount = BundledFonts.selectableFontCount + 9 - DeferredFontRegistry.fonts.count
        print("[BundledFontRegistrar] 번들 폰트 \(registeredPostScriptNames.count)/\(expectedCount)개 등록 완료: \(registeredPostScriptNames)")
    }

    /// 등록한 커스텀 폰트를 쓰기 직전에 호출해, 이름이 아직 살아있는지 확인하고 사라졌으면
    /// 전체 재등록을 한 번 더 시도한다. iOS 17+에서 `.process` 범위 커스텀 폰트가 메모리
    /// 압박 시 조용히 등록 해제되는 사례가 있고(https://developer.apple.com/forums/thread/741720),
    /// `didRegister` 가드 때문에 앱이 스스로 복구하지 못하던 문제를 막는다. 등록 목록에 없는
    /// 이름(예: 시스템 폰트)이면 즉시 반환한다.
    ///
    /// 성경 조회 화면은 보이는 절 수만큼 이 함수를 반복 호출하므로, 매번 `UIFont(name:)`를
    /// 조회하면 빠른 스와이프 시 프레임이 밀린다 — 폰트 이름별로 최소 1초 간격으로만 실제
    /// 확인한다(폰트 소실은 드문 사건이라 최대 1초 지연은 문제되지 않는다).
    private static var lastAvailabilityCheckAt: [String: Date] = [:]
    private static let availabilityCheckInterval: TimeInterval = 1.0

    ///
    /// [2026-10-29 fontdef2] 시작 때 등록하지 않은 CJK 글꼴(`DeferredFontRegistry`)이면 그 글꼴 묶음(같은 family의 번들 파일
    /// 전부, 예: Shippori Regular·SemiBold·Bold)을 지금 동기로 등록한다(파일마다 한 번만). 이름으로 글꼴을 만드는 호출부는 이 함수
    /// 다음에 `UIFont(name:)`/`NSFont(name:)`/`Font.custom`을 쓴다. 굵기 짝은 이름이 아니라 특성으로 같은 family에서 찾으므로
    /// (`.weight(.semibold)`, `VerseAnnotationRenderer.boldVariant`, `RichTextEditor` `togglingTrait`, 설교 편집기 굵게/기울임)
    /// 묶음 전체를 함께 등록해 두어야 원래 모양이 나온다. 등록에 실패한 파일은 호출부의 기존 폴백(`?? .systemFont`, SwiftUI의
    /// 시스템 글꼴 대체)이 시스템 대체 글꼴로 그린다. 한 파일이 실패해도 묶음의 다른 파일 등록에는 영향이 없다(파일마다 상태가 따로다).
    static func ensureAvailable(_ postScriptName: String) {
        if let deferredFont = DeferredFontRegistry.font(named: postScriptName) {
            DeferredFontRegistry.registerFamily(of: postScriptName)
            guard deferredFont.registerIfNeeded(), shouldCheckAvailability(of: postScriptName) else { return }
            // 시작 때 등록한 글꼴과 같은 소실 대비 — 요청한 글꼴이 사라졌으면 묶음에서 등록했던 파일 가운데 실제로 사라진 것만
            // 다시 등록한다(굵기 짝도 함께 사라졌을 수 있다). 등록 전·실패 파일은 건드리지 않는다.
            if !isFontCurrentlyAvailable(postScriptName) {
                for member in DeferredFontRegistry.familyMembers[postScriptName] ?? []
                where member.isRegistered && !isFontCurrentlyAvailable(member.postScriptName) {
                    member.registerAgain()
                }
            }
            return
        }
        guard didRegister, registeredPostScriptNames.contains(postScriptName) else { return }
        guard shouldCheckAvailability(of: postScriptName) else { return }
        guard !isFontCurrentlyAvailable(postScriptName) else { return }
        didRegister = false
        registerBundledFontsIfNeeded()
    }

    /// 이름별 1초 간격 제한(위 주석). 확인할 차례이면 시각을 기록하고 true.
    private static func shouldCheckAvailability(of postScriptName: String) -> Bool {
        let now = Date()
        if let last = lastAvailabilityCheckAt[postScriptName], now.timeIntervalSince(last) < availabilityCheckInterval {
            return false
        }
        lastAvailabilityCheckAt[postScriptName] = now
        return true
    }

    private static func isFontCurrentlyAvailable(_ postScriptName: String) -> Bool {
        #if os(iOS)
        return UIFont(name: postScriptName, size: 12) != nil
        #elseif os(macOS)
        return NSFont(name: postScriptName, size: 12) != nil
        #else
        return true
        #endif
    }

    /// 번들의 커스텀 폰트 파일(.ttf/.TTF/.otf/.OTF) URL을 찾는다. `Fonts`가 폴더 참조로
    /// 추가됐으면 `subdirectory: "Fonts"`의 전부를, 그룹(번들 루트로 평탄화)으로 추가됐으면
    /// 루트에서 이 프로젝트가 아는 접두어로 시작하는 파일만 찾는다.
    ///
    /// ⚠️ `ChosunGs.TTF`만 확장자가 대문자이고 `urls(forResourcesWithExtension:)`는 파일시스템
    /// 대소문자 설정에 따라 동작이 달라질 수 있어, 대/소문자 확장자를 모두 조회한 뒤 중복을 제거한다.
    private static func bundledCustomFontURLs() -> [URL] {
        let subdirectoryURLs = (
            (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
                + (Bundle.main.urls(forResourcesWithExtension: "TTF", subdirectory: "Fonts") ?? [])
                + (Bundle.main.urls(forResourcesWithExtension: "otf", subdirectory: "Fonts") ?? [])
                + (Bundle.main.urls(forResourcesWithExtension: "OTF", subdirectory: "Fonts") ?? [])
        )
        let dedupedSubdirectory = Array(Set(subdirectoryURLs))
        if !dedupedSubdirectory.isEmpty { return dedupedSubdirectory }

        let knownPrefixes = [
            "Paperlogy", "GowunBatang", "ChosunGs", "SILEOT", "Gentium", "KMU80SungkokSerif",
            "IBMPlexSansThai", "NotoSerifThai", "Inter-", "BeVietnamPro", "Literata-",
            "ShipporiMincho-", "LXGWWenKaiTC-",
        ]
        let rootURLs = (
            (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
                + (Bundle.main.urls(forResourcesWithExtension: "TTF", subdirectory: nil) ?? [])
                + (Bundle.main.urls(forResourcesWithExtension: "otf", subdirectory: nil) ?? [])
                + (Bundle.main.urls(forResourcesWithExtension: "OTF", subdirectory: nil) ?? [])
        )
        return Array(Set(rootURLs)).filter { url in
            knownPrefixes.contains { url.lastPathComponent.hasPrefix($0) }
        }
    }
}

// MARK: - 앱 언어 전용 CJK 글꼴의 지연 등록 (2026-10-29 fontdef2)
//
// 사용자 결정: Shippori Mincho(ja)·LXGW WenKai TC(zh)는 그 언어 앱에서만 시작할 때 등록한다. 다른 언어 앱에서 이 글꼴이
// 필요해지면(그 언어 기기에서 이 글꼴을 적용한 메모·설교·말씀 요약·개요가 iCloud로 동기화돼 열릴 때, 앱 언어를 바꾸기 전에
// 저장한 설정 이름) 그 글꼴 묶음만 그때 등록해 원래 모양으로 그린다.
//
// - 등록 단위: 글꼴 묶음(`languageFontNames`의 한 줄 = 같은 family의 번들 파일 전부, 리뷰 A1). 등록 호출은 파일마다 따로 하고,
//   한 파일은 한 번만 등록한다(`DeferredBundledFont.lockedState`). 한 파일이 실패해도 나머지 파일은 따로 등록된다.
//   묶음으로 등록하는 이유: 굵기 짝(SemiBold/Bold)은 이름이 아니라 특성으로 같은 family에서 찾기 때문이다(`ensureAvailable` 주석).
// - 동시성: 파일마다 잠금(`OSAllocatedUnfairLock`)이 하나다. 같은 파일을 여러 곳(메인의 `ensureAvailable`·RTF 읽기, 백그라운드 미리 등록)이
//   동시에 요청하면 첫 요청만 `CTFontManagerRegisterFontsForURL`을 부르고, 나머지는 그 등록이 끝날 때까지 기다린 뒤 결과를 받는다.
//   다른 파일끼리는 서로 기다리지 않는다. 메인이 기다리는 동안 잠금을 쥔 스레드는 우선순위를 넘겨받는다.
//   Core Text 함수는 여러 스레드에서 동시에 불러도 된다(Core Text Programming Guide – Multicore Considerations).
// - 메인 스레드 비용: 메인에서 등록하는 것은 지금 그릴 글꼴의 묶음뿐이다(Shippori 3개 약 25.9MB, LXGW 2개 약 26.0MB). 다른 언어
//   앱에서 그 글꼴을 처음 쓸 때 한 번만 생기는 비용이다(사용자 결정). 설정에 저장된 이름은 시작 직후 백그라운드에서 묶음째 미리
//   등록한다(`prefetch`). 등록마다 걸린 시간과 스레드를 로그로 남겨 기기에서 잴 수 있게 했다.
// - 실패: `.failed`로 남기고 다시 시도하지 않는다. 호출부의 기존 폴백이 시스템 대체 글꼴로 그린다.
// - 다시 그리기: 필요 없다. 글꼴을 이름으로 만드는 경로는 만들기 직전에 `ensureAvailable`을 부르고(SwiftUI `.custom`,
//   `UIFont(name:)`/`NSFont(name:)`), RTF는 읽기 직전에 `registerFonts(referencedInRTF:)`를 부른다. 굵기 짝을 특성으로 찾는 경로
//   (`.weight`, `boldVariant`, `togglingTrait`, 설교 편집기)는 이름으로 만든 글꼴에서 출발하므로, 그 이름의 `ensureAvailable`/RTF
//   훑기가 이미 묶음 전체를 등록해 둔 뒤다. 등록이 동기로 끝난 뒤에 글꼴을 만들므로 대체 글꼴로 먼저 그려진 텍스트가 없다.
//   백그라운드 미리 등록이 아직 진행 중이면 메인의 요청은 같은 파일 잠금에서 기다렸다가 등록된 상태로 돌아간다.

/// 시작할 때 등록하지 않는 번들 글꼴 파일 하나(파일 이름 = PostScript 이름).
nonisolated final class DeferredBundledFont: @unchecked Sendable {
    let postScriptName: String

    /// 기본 MainActor 격리 모드에서 중첩 타입의 격리 추론을 피하려고 `nonisolated`를 명시한다(fontdef2 리뷰 B1).
    nonisolated private enum State { case pending, registered, failed }
    /// 등록 상태와 그 잠금. `OSAllocatedUnfairLock`은 os_unfair_lock 기반이라, 메인 스레드가 기다리면 잠금을 쥔 스레드
    /// (예: `.utility` 우선순위의 미리 등록 작업)에 우선순위를 넘겨 준다(우선순위 역전 방지, fontdef2 리뷰 B2).
    /// 잠금 안에서는 `registerFile()`만 부른다 — throw가 없고, 이 객체의 잠금을 다시 잡는 경로(재진입)도 없다.
    private let lockedState = OSAllocatedUnfairLock(initialState: State.pending)

    init(postScriptName: String) {
        self.postScriptName = postScriptName
    }

    /// 아직 등록하지 않았으면 지금 등록한다. 등록돼 있으면 true, 실패했으면(이전 실패 포함) false.
    /// 다른 스레드가 같은 파일을 등록하는 중이면 그 등록이 끝날 때까지 기다린다.
    @discardableResult
    func registerIfNeeded() -> Bool {
        lockedState.withLock { state in
            if state == .pending {
                state = registerFile() ? .registered : .failed
            }
            return state == .registered
        }
    }

    /// 아직 등록을 시도하지 않았는지(리뷰 C3, RTF 훑기에서 쓴다). 다른 스레드가 지금 이 파일을 등록하는 중이면(잠금을 쥐고 있으면)
    /// 기다리지 않고 true로 본다 — 그 등록은 pending 상태에서 시작됐고, 필요한 호출부는 뒤이어 `registerIfNeeded()`에서 기다린다.
    var isPending: Bool {
        lockedState.withLockIfAvailable { $0 == .pending } ?? true
    }

    /// 등록에 성공한 상태인지(소실 대비 재등록 대상 고르기). 다른 스레드가 등록 중이면 그 등록이 끝날 때까지 기다린다.
    var isRegistered: Bool {
        lockedState.withLock { $0 == .registered }
    }

    /// 등록했던 글꼴이 사라졌을 때(`BundledFontRegistrar.ensureAvailable`의 소실 대비) 그 파일만 한 번 더 등록한다.
    func registerAgain() {
        lockedState.withLock { state in
            guard state == .registered else { return }
            state = registerFile() ? .registered : .failed
        }
    }

    /// `lockedState` 잠금 안에서만 부른다. 이 객체의 다른 메서드를 부르지 않는다(재진입 없음).
    private func registerFile() -> Bool {
        // `BundledFontRegistrar.bundledCustomFontURLs`와 같은 순서 — `Fonts` 폴더, 없으면 번들 루트(평탄화된 경우).
        guard let url = Bundle.main.url(forResource: postScriptName, withExtension: "ttf", subdirectory: "Fonts")
            ?? Bundle.main.url(forResource: postScriptName, withExtension: "ttf") else {
            print("[BundledFontRegistrar] 지연 등록 실패: \(postScriptName).ttf를 앱 번들에서 찾지 못했습니다. 시스템 대체 글꼴로 표시됩니다.")
            return false
        }
        let start = CFAbsoluteTimeGetCurrent()
        var unmanagedError: Unmanaged<CFError>?
        var success = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &unmanagedError)
        let error = unmanagedError?.takeRetainedValue()
        // 이미 등록돼 있으면(예: 소실 대비 재등록이 실제로는 필요 없던 경우) 쓸 수 있는 상태다.
        if !success, let error, CFErrorGetCode(error) == CTFontManagerError.alreadyRegistered.rawValue {
            success = true
        }
        let milliseconds = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let thread = Thread.isMainThread ? "메인" : "백그라운드"
        if success {
            print("[BundledFontRegistrar] 지연 등록 \(postScriptName): \(String(format: "%.1f", milliseconds))ms, \(thread) 스레드")
        } else {
            let description = error?.localizedDescription ?? "알 수 없는 오류"
            print("[BundledFontRegistrar] 지연 등록 실패 \(postScriptName): \(description) (\(String(format: "%.1f", milliseconds))ms, \(thread) 스레드). 시스템 대체 글꼴로 표시됩니다.")
        }
        return success
    }
}

nonisolated enum DeferredFontRegistry {
    /// 앱 언어(`AppLanguage.baseCode`)별 전용 CJK 글꼴의 PostScript 이름(= 번들 파일 이름).
    /// `BundledFonts.multilingualFamilies`에서 같은 `languageCode`의 Family 항목과 같아야 한다(DEBUG에서 확인).
    /// 메뉴 노출 규칙(`visibleMultilingualFamilies`)과 시작 때 등록 규칙이 같은 언어 코드를 쓴다.
    static let languageFontNames: [(languageCode: String, postScriptNames: [String])] = [
        ("ja", ["ShipporiMincho-Regular", "ShipporiMincho-SemiBold", "ShipporiMincho-Bold"]),
        ("zh", ["LXGWWenKaiTC-Regular", "LXGWWenKaiTC-Bold"]),
    ]

    /// 이 앱 언어에서 시작 때 등록하지 않는 글꼴 묶음(`languageFontNames`의 한 줄 = 묶음 하나). ja 앱은 LXGW 묶음,
    /// zh 앱은 Shippori 묶음, 그 밖은 두 묶음. 앱 언어는 실행 중 바뀌지 않으므로(`AppLanguage.code`는 `static let`) 한 번만 만든다.
    /// 아래 `fonts`·`familyMembers`는 이 배열의 같은 객체를 가리킨다.
    private static let families: [[DeferredBundledFont]] = languageFontNames
        .filter { $0.languageCode != AppLanguage.baseCode }
        .map { group in group.postScriptNames.map { DeferredBundledFont(postScriptName: $0) } }

    /// PostScript 이름 → 파일. ja 앱은 LXGW 2개, zh 앱은 Shippori 3개, 그 밖은 5개.
    static let fonts: [String: DeferredBundledFont] = Dictionary(
        uniqueKeysWithValues: families.joined().map { ($0.postScriptName, $0) }
    )

    /// PostScript 이름 → 그 글꼴이 속한 묶음 전체(자기 자신 포함, `languageFontNames` 순서).
    static let familyMembers: [String: [DeferredBundledFont]] = Dictionary(
        uniqueKeysWithValues: families.flatMap { family in family.map { ($0.postScriptName, family) } }
    )

    static func font(named postScriptName: String) -> DeferredBundledFont? {
        fonts[postScriptName]
    }

    /// 그 글꼴이 속한 묶음의 파일을 모두 등록한다(파일마다 한 번만, 동기). 지연 대상이 아닌 이름이면 아무것도 하지 않는다.
    /// 파일마다 따로 `registerIfNeeded()`를 부르므로 한 파일의 실패가 다른 파일 등록을 막지 않는다.
    static func registerFamily(of postScriptName: String) {
        for member in familyMembers[postScriptName] ?? [] {
            member.registerIfNeeded()
        }
    }

    /// RTF 문자열(`RichTextCodec.decode`)이 쓰는 지연 글꼴을 읽기 전에 등록한다. RTF를 읽을 때 등록되지 않은 글꼴 이름은
    /// 대체 글꼴로 바뀌어 버리고, 그 문서를 다시 저장하면 원래 글꼴 이름이 사라지므로(동기화로 다른 기기에도 퍼진다) 반드시
    /// 읽기 전에 동기로 등록해야 한다.
    /// 앱이 쓰는 RTF는 글꼴 표(`{\fonttbl\f0\fnil\fcharset0 Paperlogy-4Regular;…}`)에 PostScript 이름을 적는다
    /// (번들 `OutlineSeed.json`의 RTF로 확인). 글꼴 표는 RTF 머리에 있으므로 앞부분만 훑는다.
    /// 묶음 단위로 등록한다(리뷰 A1). 묶음에 등록 전(pending) 파일이 하나도 없으면 그 묶음은 이름 검사를 건너뛴다(리뷰 C3).
    /// 이 레지스트리의 모든 등록 경로(`ensureAvailable`, 이 함수, `prefetch`)가 묶음 전체를 시도하므로, pending이 없는 묶음은
    /// 이미 짝 파일까지 등록(또는 실패 확정)된 상태다 — RTF에 그 이름이 나와도 더 할 일이 없다.
    static func registerFonts(referencedInRTF rtf: String) {
        guard !fonts.isEmpty else { return }
        let header = rtf.prefix(fontTableScanLength)
        for family in families where family.contains(where: { $0.isPending }) {
            guard family.contains(where: { header.contains($0.postScriptName) }) else { continue }
            for member in family {
                member.registerIfNeeded()
            }
        }
    }

    /// RTF 머리에서 글꼴 표를 찾는 범위. 글꼴 표는 `{\rtf1\ansi…\cocoartf…` 바로 다음에 오고 글꼴 하나가 40바이트 안팎이다.
    private static let fontTableScanLength = 16_384

    /// 설정에 저장된 글꼴 이름 가운데 지연 글꼴을 백그라운드에서 미리 등록한다(시작 직후, `JBCHBibleResearchApp.init`).
    /// 화면이 먼저 요청하면 그 요청은 같은 파일 잠금에서 기다리므로 중복 등록은 생기지 않는다.
    /// 대상은 그 이름이 속한 묶음 전체다(리뷰 A1). 같은 묶음의 이름이 여러 개 있어도 파일은 한 번씩만 넣는다.
    static func prefetch(_ postScriptNames: [String]) {
        var seen = Set<String>()
        let targets = postScriptNames
            .flatMap { familyMembers[$0] ?? [] }
            .filter { seen.insert($0.postScriptName).inserted }
        guard !targets.isEmpty else { return }
        Task.detached(priority: .utility) {
            for font in targets {
                font.registerIfNeeded()
            }
        }
    }

    #if DEBUG
    /// `languageFontNames`와 글꼴 메뉴(`BundledFonts.multilingualFamilies`)의 언어 전용 항목이 같은지 확인한다.
    @MainActor
    static func assertMatchesMenuFamilies() {
        for group in languageFontNames {
            let menuNames = BundledFonts.multilingualFamilies
                .filter { $0.languageCode == group.languageCode }
                .flatMap(\.entries)
                .map(\.postScriptName)
            assert(Set(menuNames) == Set(group.postScriptNames),
                   "DeferredFontRegistry.languageFontNames(\(group.languageCode))가 글꼴 메뉴 항목과 다릅니다: \(menuNames)")
        }
    }
    #endif
}

extension View {
    /// 현재 호출하는 곳이 없는 헬퍼 — 앱 전역 기본 폰트 강제를 철회하고 Paperlogy를 성경
    /// 본문 관련 화면에만 쓰기로 해 호출부를 모두 제거했다. 실제 적용은
    /// `UserSettingsStore.bibleBodyFont`, `EditorDefaultStyle`, `RichTextEditor`의 글꼴 메뉴가 담당한다.
    func appDefaultFont() -> some View {
        font(.custom(BundledFonts.defaultPostScriptName, size: 17, relativeTo: .body))
    }
}
