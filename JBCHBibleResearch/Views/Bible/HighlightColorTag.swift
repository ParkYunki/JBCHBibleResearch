//
//  HighlightColorTag.swift
//  JBCHBibleResearch
//
//  구간 주석(형광펜) 기본 팔레트 5색. `VerseHighlight.colorTag`(순수 문자열)를 실제 색상값으로
//  바꾸는 것은 앱(UI) 레이어의 책임이다 — 데이터 모델 패키지(BibleResearchModels)는
//  SwiftUI/UIKit/AppKit에 의존하지 않는다.
//

import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

#if os(iOS)
typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
#elseif os(macOS)
typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
#endif

/// `NSTextAlignment`는 UIKit/AppKit 양쪽에 같은 이름·case로 따로 정의돼 있어, `#if os(iOS)` 없이 쓰는
/// 크로스플랫폼 파일에서 모호하지 않도록 `PlatformColor`/`PlatformFont`처럼 별칭을 둔다.
typealias PlatformTextAlignment = NSTextAlignment

/// `VerseHighlight.colorTag` 문자열과 1:1 대응(`rawValue`). 새 색은 케이스만 추가하면 되고,
/// 저장된 기존 데이터는 rawValue 기반이라 순서와 무관하게 그대로 유효하다.
enum HighlightColorTag: String, CaseIterable, Identifiable {
    case yellow, green, blue, pink, purple

    var id: String { rawValue }

    var swiftUIColor: Color {
        switch self {
        case .yellow: return Color(red: 0.98, green: 0.78, blue: 0.29)
        case .green: return Color(red: 0.60, green: 0.80, blue: 0.35)
        case .blue: return Color(red: 0.53, green: 0.72, blue: 0.92)
        case .pink: return Color(red: 0.93, green: 0.58, blue: 0.69)
        case .purple: return Color(red: 0.69, green: 0.66, blue: 0.93)
        }
    }

    var platformColor: PlatformColor { PlatformColor(swiftUIColor) }

    /// 형광펜 배경 위의 절 번호/글자가 묻히지 않도록 살짝 옅게 쓴다(`VerseAnnotationRenderer`가 배경색으로 사용).
    var backgroundOpacity: Double { 0.55 }
}
