//
//  BundledFontRegistrar.swift
//  JBCHBibleResearch
//
//  앱에 내장한 Paperlogy(9종)·고운바탕 등 번들 글꼴을 앱 실행 시 한 번 CoreText에
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
        Entry(postScriptName: "GowunBatang-Regular", displayName: "고운바탕 Regular"),
        Entry(postScriptName: "GowunBatang-Bold", displayName: "고운바탕 Bold"),
    ]

    /// 설정 화면 "내장 기본 글꼴" 섹션에 나열하는 전체 목록(Paperlogy 9종 + 고운바탕 2종).
    static let entries: [Entry] = paperlogyEntries + gowunBatangEntries

    /// 앱 기본 글꼴의 PostScript 이름.
    static let defaultPostScriptName = "Paperlogy-4Regular"
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
        let expectedCount = BundledFonts.entries.count + 5 // 한자 1 + 히브리어 1 + 그리스어 2 + 타이틀 세리프 1
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

        let knownPrefixes = ["Paperlogy", "GowunBatang", "ChosunGs", "SILEOT", "Gentium", "KMU80SungkokSerif"]
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
