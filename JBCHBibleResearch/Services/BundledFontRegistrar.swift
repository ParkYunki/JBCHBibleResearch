//
//  BundledFontRegistrar.swift
//  JBCHBibleResearch
//
//  [2026-08-08 신설] 사용자 요청 — "앱의 내장한 글꼴이 기본 글꼴이 되도록.
//  .../Fonts 이하 라이센스 프리 글꼴을 저장해 두었음(Paperlogy-4Regular)."
//  Paperlogy 9개 굵기 파일(Paperlogy-1Thin.ttf ~ Paperlogy-9Black.ttf)을 앱
//  실행 시 한 번 CoreText에 등록해, 이후 SwiftUI `Font.custom(_:size:)`와
//  설정 화면의 글꼴 목록(NSFontManager/UIFont)에서 곧바로 쓸 수 있게 한다.
//
//  ⚠️ [필수 확인 사항, Xcode에서 직접 처리해야 함] 이 세션은 .xcodeproj 파일 자체를
//  열거나 수정할 수 없다 — 그래서 `Fonts` 폴더가 실제로 앱 타겟의 "Copy Bundle
//  Resources" 빌드 단계에 포함돼 있는지는 사용자가 Xcode에서 직접 확인해야 한다:
//  File > "Add Files to \"JBCHBibleResearch\"..." 로 `Fonts` 폴더를 선택하고
//  타겟 멤버십 체크박스를 켤 것(폴더 참조/그룹 어느 쪽으로 추가해도 아래 로직이
//  둘 다 찾아본다). 이 파일이 추가되지 않은 상태에서는 `bundledPaperlogyFontURLs()`가
//  빈 배열을 반환해 등록이 조용히 스킵되고, `Font.custom("Paperlogy-4Regular", ...)`은
//  SwiftUI가 알아서 시스템 기본 글꼴로 대체한다 — 즉 폰트 파일이 아직 타겟에 없어도
//  앱이 깨지지는 않는다(UserSettingsStore.bibleBodyFont 상단 주석과 같은 안전망).
//
//  프로세스 단위(.process)로만 등록한다 — `.persistent`(디스크 영구 등록)는 앱
//  삭제 후에도 흔적이 남을 수 있어 피한다. CTFontManagerRegisterFontsForURL은
//  macOS/iOS 모두에 있는 크로스플랫폼 CoreText API라 플랫폼 분기가 필요 없다.
//

import Foundation
import CoreText
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// 이 프로젝트가 내장한 Paperlogy 폰트 9종의 메타데이터. `fonttools`로 각 .ttf의
/// name 테이블을 직접 확인해 얻은 값이다 — 9개 굵기가 "Paperlogy"라는 하나의
/// family 아래 굵기 배리에이션으로 묶여 있지 않고, 굵기마다 완전히 독립된
/// PostScript 이름(예: "Paperlogy-4Regular")과 family 이름(예: "Paperlogy 4
/// Regular")을 갖는다 — 그래서 `Font.custom`에는 family 이름이 아니라 이 PostScript
/// 이름을 쓴다(Apple 문서상 `UIFont(name:)`/`NSFont(name:)`가 공식적으로 기대하는
/// 값은 PostScript 이름이고, family 이름 매칭은 그 family에 폰트가 하나뿐일 때만
/// 우연히 맞는 것이라 신뢰하지 않는다).
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

    /// [2026-08-19 신설] 사용자 요청 — "앱 내 기본 번들 폰트 추가: GowunBatang-
    /// Regular.ttf, GowunBatang-Bold.ttf(페이퍼로지 폰트와 같은 번들)." 고운바탕
    /// (yangheeryu/Gowun-Batang, OFL-1.1) 두 굵기 — Paperlogy와 정확히 같은 방식
    /// (fonttools로 확인한 실제 PostScript 이름을 그대로 씀, family 이름이 아님)
    /// 으로 등록·선택 가능하게 한다.
    static let gowunBatangEntries: [Entry] = [
        Entry(postScriptName: "GowunBatang-Regular", displayName: "고운바탕 Regular"),
        Entry(postScriptName: "GowunBatang-Bold", displayName: "고운바탕 Bold"),
    ]

    /// 설정 화면 "글꼴" Picker의 "내장 기본 글꼴" 섹션에 그대로 나열하는 전체
    /// 목록 — Paperlogy 9종 + 고운바탕 2종.
    static let entries: [Entry] = paperlogyEntries + gowunBatangEntries

    /// 사용자 요청 그대로 — 앱 기본 글꼴.
    static let defaultPostScriptName = "Paperlogy-4Regular"
}

/// [2026-08-19 신설] 사용자가 목록에서 "고르는" 범용 글꼴(`BundledFonts`)과 달리,
/// 특정 언어의 글자를 항상 이 글꼴로만 렌더링하도록 고정하는 특수 목적 폰트 —
/// 한자 주석(ChosunGs)/원문 정보의 히브리어(SILEOT=Ezra SIL)/그리스어(Gentium).
/// 한자만 사용자가 켜고 끌 수 있어(`UserSettingsStore.hanjaFontName`) 예외적으로
/// "선택 가능"이지만, 그 선택지 자체가 이 상수 하나뿐이라 `BundledFonts.entries`
/// 목록(여러 굵기 중 자유 선택)과는 성격이 달라 별도 타입으로 분리했다.
///
/// PostScript 이름은 전부 fonttools로 `Fonts/*.ttf`의 name 테이블(ID 6)을 직접
/// 읽어 확인했다(Paperlogy 때와 같은 방법론, 위 BundledFontRegistrar 상단 주석
/// 참고) — family 이름을 짐작해서 쓰지 않는다.
enum SpecialPurposeFonts {
    /// 한자 주석 기본 폰트 — 조선궁서체(ChosunGs.TTF). 지적재산권은 (주)조선일보사에
    /// 있고 개인/기업에 무료로 제공되는 라이선스(설정 화면 오픈소스 라이선스 고지
    /// 참고) — OFL/MIT 같은 표준 오픈소스 라이선스가 아니라 이 프로젝트 특유의
    /// 재배포 조건이 있으므로, 이 상수 자체를 다른 프로젝트로 그대로 복사해 쓰지
    /// 않도록 주의.
    static let hanja = "ChosunGs"
    /// 원문 정보 히브리어 표기 폰트 — Ezra SIL(SILEOT.ttf, software.sil.org/ezra).
    /// 폰트 소프트웨어 자체는 SIL OFL 1.1, 히브리어 문자 배치 로직만 별도로
    /// Ralph Hancock/John Hudson의 MIT 라이선스.
    static let hebrew = "EzraSIL"
    /// 원문 정보 그리스어(헬라어) 표기 폰트 — SIL Gentium(사용자 표기로는
    /// "Gentium Plus", 번들 파일명 `Gentium-Regular.ttf`/`Gentium-Bold.ttf`,
    /// fonttools로 확인한 실제 family/PostScript 이름은 "Gentium"/"Gentium-*"다 —
    /// 업로드받은 OFL.txt의 Reserved Font Name도 "Gentium"과 일치). SIL OFL 1.1.
    static let greekRegular = "Gentium-Regular"
    static let greekBold = "Gentium-Bold"
}

enum BundledFontRegistrar {
    private(set) static var registeredPostScriptNames: [String] = []
    private static var didRegister = false

    /// 앱 시작 시 1회만 호출하면 된다(`JBCHBibleResearchApp.init()`). 중복
    /// 호출해도 안전하다(두 번째 호출부터는 즉시 반환).
    ///
    /// [2026-08-19 수정] 이름은 그대로지만 범위가 넓어졌다 — 원래 Paperlogy
    /// 9종만 등록했는데, 이제 사용자가 고르는 폰트(Paperlogy+고운바탕,
    /// `BundledFonts.entries`)와 특수 목적 폰트(한자/히브리어/그리스어,
    /// `SpecialPurposeFonts`) 전부를 이 한 번의 호출에서 함께 등록한다 —
    /// CoreText 등록은 "이 폰트를 어디에 쓸지"와 무관하게 앱 시작 시 한 번만
    /// 하면 되는 공통 절차라 굳이 나눌 이유가 없다.
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
        let expectedCount = BundledFonts.entries.count + 4 // 한자 1 + 히브리어 1 + 그리스어 2
        print("[BundledFontRegistrar] 번들 폰트 \(registeredPostScriptNames.count)/\(expectedCount)개 등록 완료: \(registeredPostScriptNames)")
    }

    /// [2026-09-02 추가] 사용자 보고 — 아이패드에서 손글씨(Scribble) 도구모음을
    /// 연 뒤 성경 조회로 돌아오면 한자 폰트(조선궁서체)가 기본 글꼴로 보이다가,
    /// 앱을 재시작해야만 복구되는 증상. 조사해 보니 이 앱이 쓰는 화면들은
    /// `PlatformFont(name:)`/`Font.custom(_:)`가 실패하면 이미 전부 시스템
    /// 기본 글꼴로 조용히 대체하도록 돼 있어(`??`/SwiftUI의 기본 동작) 우리
    /// 코드가 예전 값을 잘못 들고 있는 게 아니었다 — 그 순간 iOS(CoreText)가
    /// 실제로 그 이름의 폰트를 못 찾겠다고 답하고 있었다는 뜻이다. iOS 17+에서
    /// `.process` 범위로 등록한 커스텀 폰트가 메모리 압박(memory pressure)
    /// 상황에서 시스템에 의해 조용히 등록 해제되는 사례가 실제로 보고돼 있고
    /// (https://developer.apple.com/forums/thread/741720), "앱을 재시작해야만
    /// 복구된다"는 것도 그 보고와 정확히 일치한다. 문제는 위
    /// `registerBundledFontsIfNeeded()`가 `didRegister` 가드로 프로세스당 딱
    /// 한 번만 등록을 시도해, 시스템이 등록을 취소해버린 뒤에는 앱이 다시는
    /// 스스로 복구를 시도하지 않는다는 데 있었다. 이 함수는 이 앱이 등록해 둔
    /// 커스텀 폰트(Paperlogy/고운바탕/조선궁서체/히브리어/그리스어 전부 —
    /// 같은 원인이라 특정 폰트만 예외로 둘 근거가 없다)를 실제로 쓰기 직전마다
    /// 불러, 그 이름이 아직 살아있는지 가볍게 확인하고(CoreText 캐시 조회라
    /// 비용이 매우 작다) 없어졌으면 그 자리에서 전체 재등록을 한 번 더
    /// 시도한다. `postScriptName`이 우리가 등록한 목록에 없는 이름(예:
    /// "System", 사용자가 고른 시스템 폰트)이면 즉시 반환하고 아무 것도 하지
    /// 않는다 — 우리가 관리하지 않는 이름까지 재등록을 시도할 이유가 없다.
    static func ensureAvailable(_ postScriptName: String) {
        guard didRegister, registeredPostScriptNames.contains(postScriptName) else { return }
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

    /// [2026-08-19 수정, 이전 `bundledPaperlogyFontURLs`] `Fonts` 폴더가 "폴더
    /// 참조"(파란 폴더, 디렉터리 구조 유지)로 추가됐으면 `subdirectory: "Fonts"`
    /// 에서 그 안의 .ttf/.TTF 전부를 찾고(더 이상 "Paperlogy"로 시작하는 것만
    /// 거르지 않는다 — ChosunGs/SILEOT/Gentium-*/GowunBatang-*도 이 폴더에 함께
    /// 있다), "그룹"(노란 폴더, 번들 루트로 평탄화)으로 추가됐으면 루트에서 이
    /// 프로젝트가 아는 접두어로 시작하는 파일만 찾는다 — 둘 중 어느 쪽으로
    /// Xcode에 추가되더라도 동작하게 하기 위한 이중 조회는 그대로 유지한다.
    ///
    /// ⚠️ [대소문자] `ChosunGs.TTF`만 확장자가 대문자다(나머지는 소문자 .ttf) —
    /// `Bundle.urls(forResourcesWithExtension:)`는 파일시스템 대소문자 구분
    /// 설정에 따라 동작이 달라질 수 있어, 안전하게 "ttf"/"TTF" 둘 다 조회해
    /// 합친 뒤 중복(같은 파일이 두 조회 모두에 걸리는 경우)을 제거한다.
    private static func bundledCustomFontURLs() -> [URL] {
        let subdirectoryURLs = (
            (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
                + (Bundle.main.urls(forResourcesWithExtension: "TTF", subdirectory: "Fonts") ?? [])
        )
        let dedupedSubdirectory = Array(Set(subdirectoryURLs))
        if !dedupedSubdirectory.isEmpty { return dedupedSubdirectory }

        let knownPrefixes = ["Paperlogy", "GowunBatang", "ChosunGs", "SILEOT", "Gentium"]
        let rootURLs = (
            (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
                + (Bundle.main.urls(forResourcesWithExtension: "TTF", subdirectory: nil) ?? [])
        )
        return Array(Set(rootURLs)).filter { url in
            knownPrefixes.contains { url.lastPathComponent.hasPrefix($0) }
        }
    }
}

extension View {
    /// [2026-08-08 추가, 2026-08-16 사용 중단] 한때 사용자 요청으로 "앱에서
    /// 사용되는 글꼴도 여기에 내장된 기본글꼴(Paperlogy-4Regular)로" 이 헬퍼를
    /// RootView와 모든 별도 Scene(성경 조회 새 창/태그 관계/문서 뷰어/개요 새
    /// 창)에 붙여 앱 전역 기본 폰트로 강제했었다. 그런데 그 뒤로 "이 화면은
    /// 시스템 기본폰트로 되돌려달라"는 요청이 화면마다 반복됐고, 결국
    /// "Paperlogy는 성경 본문과 관련될 때만 쓰고 나머지는 전부 시스템 기본
    /// 글꼴/보통 크기로" 정리하기로 해서 모든 호출부를 뺐다(RootView.swift
    /// 상단 주석 참고). 이 헬퍼 자체는 혹시 나중에 다시 필요해질 수 있어
    /// 지우지 않고 남겨 뒀지만, 현재는 아무 곳에서도 호출하지 않는다 — 실제
    /// Paperlogy 적용은 `UserSettingsStore.bibleBodyFont`(성경 본문/절 텍스트),
    /// `EditorDefaultStyle`(메모 편집기 기본 서식), `RichTextEditor`의 글꼴
    /// 선택 메뉴(사용자가 원할 때 직접 고르는 옵션) 세 곳이 각자 독립적으로
    /// 담당한다.
    func appDefaultFont() -> some View {
        font(.custom(BundledFonts.defaultPostScriptName, size: 17, relativeTo: .body))
    }
}
