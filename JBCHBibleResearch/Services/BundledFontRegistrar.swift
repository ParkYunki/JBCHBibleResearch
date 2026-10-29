//
//  BundledFontRegistrar.swift
//  JBCHBibleResearch
//
//  앱에 내장한 Paperlogy(9종)·고운바탕·다국어 글꼴(태국어/키릴/베트남어, 2026-10-12)·Literata(2026-10-29) 등 번들 글꼴을 앱 실행 시 한 번 CoreText에
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
    /// [2026-10-29 사용자 결정] 베트남어 앱(번들 성경 VIE1934)은 Literata Regular, 그 밖의 언어는 기존과 같은 Paperlogy Regular.
    /// 이 앱에는 번역본별 글꼴 설정이 없어(본문 글꼴은 `bibleFontName` 하나) 앱 언어로 정한다. 번들 성경은 앱 언어의 것 하나만
    /// 보이므로(`BundledTranslationCatalog.isVisible`) VIE1934가 보이는 기기는 베트남어 앱뿐이다.
    /// ⚠️ 설교 문단 스타일·메모 에디터 기본값(`languageAdjustedDefaultFontName`)은 이 값과 별개이며 바꾸지 않았다.
    static var bibleDefaultPostScriptName: String {
        AppLanguage.baseCode == "vi" ? literataRegularPostScriptName : defaultPostScriptName
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

    static let notoSerifThaiEntries: [Entry] = [
        Entry(postScriptName: "NotoSerifThai-Regular", displayName: "Noto Serif Thai Regular"),
        Entry(postScriptName: "NotoSerifThai-Bold", displayName: "Noto Serif Thai Bold"),
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
    ]

    // MARK: 공통 글꼴 / 지역 전용 글꼴 (2026-10-12, 사용자 결정: 앱 언어 기준)
    //
    // - 공통(모든 언어의 메뉴에 표시): Paperlogy, 고운바탕, Literata(2026-10-29)
    // - 지역 전용(그 앱 언어에서만 메뉴에 표시): IBM Plex Sans Thai·Noto Serif Thai(th), Inter(ru),
    //   Be Vietnam Pro(vi), 조선궁서체(ko — 한자 주석용 한국어 전용 글꼴)
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
    static let bundledFamilyNamePrefixes: [String] = ["Paperlogy", "IBM Plex Sans Thai", "Noto Serif Thai", "Inter", "Be Vietnam Pro", "Literata"]

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
    static func registerBundledFontsIfNeeded() {
        guard !didRegister else { return }
        didRegister = true

        let urls = bundledCustomFontURLs()
        guard !urls.isEmpty else {
            print("[BundledFontRegistrar] 번들 폰트 파일을 앱 번들에서 찾지 못했습니다 — Fonts 폴더가 Xcode 타겟(Copy Bundle Resources)에 포함돼 있는지 확인하세요. 등록 전까지는 시스템 기본 글꼴로 표시됩니다.")
            return
        }

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
        let expectedCount = BundledFonts.selectableFontCount + 9
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

    static func ensureAvailable(_ postScriptName: String) {
        guard didRegister, registeredPostScriptNames.contains(postScriptName) else { return }
        let now = Date()
        if let last = lastAvailabilityCheckAt[postScriptName], now.timeIntervalSince(last) < availabilityCheckInterval {
            return
        }
        lastAvailabilityCheckAt[postScriptName] = now
        guard !isFontCurrentlyAvailable(postScriptName) else { return }
        didRegister = false
        registerBundledFontsIfNeeded()
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

extension View {
    /// 현재 호출하는 곳이 없는 헬퍼 — 앱 전역 기본 폰트 강제를 철회하고 Paperlogy를 성경
    /// 본문 관련 화면에만 쓰기로 해 호출부를 모두 제거했다. 실제 적용은
    /// `UserSettingsStore.bibleBodyFont`, `EditorDefaultStyle`, `RichTextEditor`의 글꼴 메뉴가 담당한다.
    func appDefaultFont() -> some View {
        font(.custom(BundledFonts.defaultPostScriptName, size: 17, relativeTo: .body))
    }
}
