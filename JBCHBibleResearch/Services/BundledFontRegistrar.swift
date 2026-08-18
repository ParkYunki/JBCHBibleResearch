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
    static let entries: [Entry] = [
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

    /// 사용자 요청 그대로 — 앱 기본 글꼴.
    static let defaultPostScriptName = "Paperlogy-4Regular"
}

enum BundledFontRegistrar {
    private(set) static var registeredPostScriptNames: [String] = []
    private static var didRegister = false

    /// 앱 시작 시 1회만 호출하면 된다(`JBCHBibleResearchApp.init()`). 중복
    /// 호출해도 안전하다(두 번째 호출부터는 즉시 반환).
    static func registerBundledFontsIfNeeded() {
        guard !didRegister else { return }
        didRegister = true

        let urls = bundledPaperlogyFontURLs()
        guard !urls.isEmpty else {
            print("[BundledFontRegistrar] Paperlogy 폰트 파일을 앱 번들에서 찾지 못했습니다 — Fonts 폴더가 Xcode 타겟(Copy Bundle Resources)에 포함돼 있는지 확인하세요. 등록 전까지는 시스템 기본 글꼴로 표시됩니다.")
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
        print("[BundledFontRegistrar] Paperlogy 폰트 \(registeredPostScriptNames.count)/\(BundledFonts.entries.count)개 등록 완료: \(registeredPostScriptNames)")
    }

    /// `Fonts` 폴더가 "폴더 참조"(파란 폴더, 디렉터리 구조 유지)로 추가됐으면
    /// `subdirectory: "Fonts"`에서 찾고, "그룹"(노란 폴더, 번들 루트로 평탄화)으로
    /// 추가됐으면 루트에서 "Paperlogy"로 시작하는 .ttf 파일을 찾는다 — 둘 중 어느
    /// 쪽으로 Xcode에 추가되더라도 동작하게 하기 위한 이중 조회다.
    private static func bundledPaperlogyFontURLs() -> [URL] {
        if let subdirectoryURLs = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts"),
           !subdirectoryURLs.isEmpty {
            return subdirectoryURLs
        }
        let rootURLs = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        return rootURLs.filter { $0.lastPathComponent.hasPrefix("Paperlogy") }
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
