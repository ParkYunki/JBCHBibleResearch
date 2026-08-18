//
//  HighlightColorTag.swift
//  JBCHBibleResearch
//
//  [2026-08-08 신설] 구간 주석(형광펜) 기능 — README "이어서 16" 설계 논의에서
//  합의한 기본 팔레트 5색. `VerseHighlight.colorTag`(순수 문자열)를 실제 색상값
//  으로 바꾸는 건 앱(UI) 레이어의 책임이다 — 데이터 모델 패키지(BibleResearchModels)는
//  SwiftUI/UIKit/AppKit에 의존하지 않는다는 기존 원칙(BibleReferenceModels.swift
//  상단 주석)을 그대로 따른다.
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

/// [2026-08-12 추가] `NSTextAlignment`는 UIKit/AppKit 양쪽에 같은 이름·같은
/// case(`.left`/`.center`/`.right`/`.justified`/`.natural`)로 각각 따로
/// 정의돼 있다 — `RichTextEditorToolbarContent`처럼 `#if os(iOS)`로 감싸지
/// 않은 크로스플랫폼 파일에서 어느 쪽이 쓰이는지 모호해지지 않도록, 위
/// `PlatformColor`/`PlatformFont`와 같은 원칙으로 별칭을 둔다.
typealias PlatformTextAlignment = NSTextAlignment

/// `VerseHighlight.colorTag`에 저장되는 문자열과 1:1 대응(`rawValue`). 새 색을
/// 추가하려면 여기 케이스만 늘리면 된다 — 저장된 옛 데이터의 `colorTag` 문자열은
/// 그대로 유효하다(rawValue 기반이라 순서에 의존하지 않는다).
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

    /// 형광펜 배경 위에 얹는 절 번호/글자가 안 묻히도록 살짝 옅게 쓴다 —
    /// `VerseAnnotationRenderer`가 이 값을 배경색으로 쓴다(원색 그대로 쓰면
    /// 본문 글자가 잘 안 보인다).
    var backgroundOpacity: Double { 0.55 }
}
