//
//  EditorDefaultStyle.swift
//  JBCHBibleResearch
//
//  모든 `RichTextEditor` 호출부(개인 묵상/말씀 요약/개요/개요 시드 편집기)가 공유하는 에디터
//  창 기본 스타일: 글꼴 페이퍼로지 3라이트 14pt, 글자색 #2B2B2F, 배경색 #F5F1E8, 줄간격
//  2.0. 여기 한 곳만 고치면 전부 바뀐다.
//
//  ⚠️ 설정 > 모양의
//  값(`UserSettingsStore.bibleBodyFont`/`bibleTextColor`/`bibleLineSpacing`)은
//  성경 읽기 화면에만 적용되며, 이 파일의 에디터 창 고정 기본값과는 의도적으로 분리돼 있다.
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
    /// `RichTextEditor.lineHeightMultiple`의 용어 해석(파일 상단 주석)을
    /// 따른다: 배수 지정이며 1.0이 "추가 줄간격 없음"이다.
    static let lineHeightMultiple: CGFloat = 2.0

    /// 폰트가 아직 앱 번들/타겟에 등록되지 않았다면(BundledFontRegistrar.swift
    /// 상단 주석 참고) 시스템 폰트로 조용히 대체한다 — `MemoDetailView.
    /// contextualTypingFont`와 동일한 안전장치.
    static var typingFont: PlatformFont {
        BundledFontRegistrar.ensureAvailable(fontName)
        return PlatformFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
    }

    static var backgroundColor: PlatformColor {
        Color(hex: backgroundColorHex).map(PlatformColor.init) ?? PlatformColor.white
    }

    static var textColor: PlatformColor {
        Color(hex: textColorHex).map(PlatformColor.init) ?? PlatformColor.black
    }

    /// 편집기 밖(순정 SwiftUI `Text`)에서 에디터와 같은 배경을 흉내내는
    /// 화면(`ChapterRelatedContentPanel`/`OutlineQuickViewWindowContent`)이
    /// 재사용한다. `backgroundColor`와 같은 값이며, `Color(hex:)`가 실패 가능한
    /// API라 `.clear`로 폴백한다.
    static var backgroundSwiftUIColor: Color {
        Color(hex: backgroundColorHex) ?? .clear
    }

    /// `RichTextEditor.typingAttributes`와 같은
    /// 공식(`typographicLineHeight * (배수 - 1)`)을 한 곳에 모아, 편집기 밖
    /// 화면이 중복 계산하지 않게 한다.
    static var lineSpacingPoints: CGFloat {
        typingFont.typographicLineHeight * max(0, lineHeightMultiple - 1)
    }
}
