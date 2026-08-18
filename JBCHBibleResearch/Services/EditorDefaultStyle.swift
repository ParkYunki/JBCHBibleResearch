//
//  EditorDefaultStyle.swift
//  JBCHBibleResearch
//
//  [2026-08-14 신설] 사용자 요청 — "[공통] 모든 에디터 창 기본 설정: 기본 글꼴
//  페이퍼로지 3라이트 14pt, 글자색 #2B2B2F, 배경색 #F5F1E8, 줄간격 2.0."
//  개인 묵상/말씀 요약/개요(책·장)/개요 시드 편집기까지 이 앱의 모든
//  `RichTextEditor` 호출부가 공유하는 단일 값 — 여기 한 곳만 고치면 전부
//  같이 바뀐다.
//
//  ⚠️ [범위, 명확히 분리] 사용자가 같은 요청에서 확인한 원칙 — "메뉴 - 설정 -
//  모양에서 설정한 값은 순수 성경조회의 본문과 성경구절 텍스트에만 적용." 즉
//  `UserSettingsStore.bibleBodyFont`/`bibleTextColor`/`bibleLineSpacing`(모양
//  탭, 사용자가 자유롭게 바꿀 수 있는 값)과 이 파일의 값은 서로 완전히 별개다 —
//  이 파일은 "에디터 창"(사용자가 직접 글을 쓰는 화면)의 고정 기본값이고, 모양
//  탭은 "성경 읽기 화면"의 사용자 설정값이다. 서로 못 건드리게 의도적으로 분리했다.
//

import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum EditorDefaultStyle {
    static let fontName = "Paperlogy-3Light"
    static let fontSize: CGFloat = 14
    static let textColorHex = "#2B2B2F"
    static let backgroundColorHex = "#F5F1E8"
    /// "줄간격 2.0" — `RichTextEditor.lineHeightMultiple`의 용어 해석(파일 상단
    /// 주석)을 그대로 따른다: 배수 지정이며, 1.0이 "추가 줄간격 없음"이다.
    static let lineHeightMultiple: CGFloat = 2.0

    /// 폰트가 아직 앱 번들/타겟에 등록되지 않았다면(BundledFontRegistrar.swift
    /// 상단 주석 참고) 시스템 폰트로 조용히 대체한다 — `MemoDetailView.
    /// contextualTypingFont`와 동일한 안전장치.
    static var typingFont: PlatformFont {
        PlatformFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
    }

    static var backgroundColor: PlatformColor {
        Color(hex: backgroundColorHex).map(PlatformColor.init) ?? PlatformColor.white
    }

    static var textColor: PlatformColor {
        Color(hex: textColorHex).map(PlatformColor.init) ?? PlatformColor.black
    }

    /// [2026-08-15 추가] 사용자 요청 — "[성경 조회] 오른쪽 인스펙터 — 개요내용의
    /// 배경색은 에디터 배경색과 동일하게." `ChapterRelatedContentPanel`/
    /// `OutlineQuickViewWindowContent`처럼 편집기 밖(순정 SwiftUI `Text`)에서
    /// "에디터와 같은 배경"을 흉내내야 하는 곳들이 재사용한다. `backgroundColor`
    /// (AppKit/UIKit `PlatformColor`, 실제 에디터 텍스트뷰가 쓰는 값)와 값 자체는
    /// 같지만 SwiftUI `Text`/`.background(_:)`가 요구하는 `Color` 타입으로
    /// 돌려준다. 색상 파싱이 실패할 이유가 없는 상수 hex 문자열이지만
    /// `Color(hex:)`가 실패 가능한(`init?`) API라 방어적으로 `.clear` 폴백을 둔다.
    static var backgroundSwiftUIColor: Color {
        Color(hex: backgroundColorHex) ?? .clear
    }

    /// [2026-08-15 추가] 사용자 요청 — "개요내용의 줄간격도 [에디터와] 동일하게."
    /// `RichTextEditor.typingAttributes`가 매번 직접 계산하던 것과 완전히 같은
    /// 공식(`typographicLineHeight * (배수 - 1)`, `RichTextEditor.swift` 상단
    /// "용어 해석" 주석 참고)을 여기 한 곳에 모아 둔다 — 편집기 밖에서 "에디터와
    /// 같은 모양"을 흉내내야 하는 화면들이 공식을 중복 계산하지 않게 한다.
    static var lineSpacingPoints: CGFloat {
        typingFont.typographicLineHeight * max(0, lineHeightMultiple - 1)
    }
}
