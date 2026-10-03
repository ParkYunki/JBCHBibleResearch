//
//  SermonTextLayout.swift
//  JBCHBibleResearch
//
//  설교 글자 스타일의 "모양" 계층 — 에디터, 스크롤 뷰어, 페이지 뷰어가 똑같이 보이도록 세 화면이 같은 코드를 쓴다.
//
//  - `SermonStyleMetrics`: 문단 스타일별 위·아래 간격과 들여쓰기 수치(2026-10-03 스타일 재설계).
//  - `SermonLayoutManager`: TextKit 1 레이아웃 매니저. ① 말씀구절 문단을 "박스 + 왼쪽 세로 바 + 위·아래 안여백"으로,
//    ② 표준 `.backgroundColor`(강조2 형광펜 등)를 줄마다 "글자 상자" 모양으로 직접 그린다.
//    에디터·스크롤 뷰어·페이지 뷰어가 모두 이 매니저(TextKit 1)를 써서 같은 그림이 나온다.
//  - `SermonTextKit1`: 위 레이아웃 매니저를 쓰는 텍스트뷰/스크롤뷰 생성 헬퍼.
//  - `SermonEmphasis` / `SermonEmphasisEditor`: 드래그한 글자에만 적용하는 강조 1·2·3.
//
//  ⚠️ 저장 포맷: 말씀구절 박스/바 attribute(`sermonVerseBoxFill/Bar`)는 RTF에 남지 않는다. 문단 스타일을 다시 입힐 때
//  (`SermonParagraphStyleCodec.applyStyle`) 매번 다시 심는다. 강조는 표준 attribute(색·굵기·배경·밑줄)라 RTF에 그대로 저장된다.

import SwiftUI
import BibleResearchModels
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - 커스텀 attribute

extension NSAttributedString.Key {
    /// 말씀구절 문단 박스 배경색(`PlatformColor`). 문단 전체에 심는다.
    static let sermonVerseBoxFill = NSAttributedString.Key("com.jbch.sermon.verseBoxFill")
    /// 말씀구절 문단 왼쪽 세로 바 색(`PlatformColor`).
    static let sermonVerseBoxBar = NSAttributedString.Key("com.jbch.sermon.verseBoxBar")
}

// MARK: - 색 비교 도우미

extension PlatformColor {
    /// sRGB 성분(비교용). 변환에 실패하면 nil.
    var sermonRGBA: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? {
        #if os(iOS)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        return getRed(&r, green: &g, blue: &b, alpha: &a) ? (r, g, b, a) : nil
        #elseif os(macOS)
        guard let c = usingColorSpace(.sRGB) else { return nil }
        return (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
        #endif
    }

    /// 두 색이 사실상 같은 색인지(성분 차 0.01 이내).
    func sermonIsClose(to other: PlatformColor) -> Bool {
        guard let a = sermonRGBA, let b = other.sermonRGBA else { return false }
        return abs(a.r - b.r) < 0.01 && abs(a.g - b.g) < 0.01 && abs(a.b - b.b) < 0.01 && abs(a.a - b.a) < 0.01
    }
}

// MARK: - 스타일별 간격/들여쓰기 수치

/// 문단 스타일별 위·아래 간격과 들여쓰기(pt, 글꼴 배율 1.0 기준). 뷰어의 "Aa" 배율은 글자 크기와 함께 이 값들에도 곱해진다.
struct SermonStyleMetrics {
    /// 문단 위 간격(`paragraphSpacingBefore`).
    var spacingBefore: CGFloat
    /// 문단 아래 간격(`paragraphSpacing`).
    var spacingAfter: CGFloat
    /// 왼쪽 들여쓰기(`headIndent`, 첫 줄 포함).
    var leftIndent: CGFloat
    /// 오른쪽 들여쓰기(양수. `tailIndent`는 음수로 넣는다).
    var rightIndent: CGFloat
    /// 첫 줄만 더 들이는 양(`firstLineHeadIndent - headIndent`).
    var firstLineIndent: CGFloat

    /// 말씀구절 박스의 위·아래 안여백 = 글자 크기 × 이 비율. 레이아웃 매니저가 그릴 때와 문단 간격 계산이 같은 값을 쓴다.
    static let versePaddingRatio: CGFloat = 0.6

    static func metrics(for style: SermonParagraphStyle, fontSize: CGFloat) -> SermonStyleMetrics {
        switch style {
        case .mainTheme:
            return SermonStyleMetrics(spacingBefore: 30, spacingAfter: 12, leftIndent: 0, rightIndent: 0, firstLineIndent: 0)
        case .midTheme:
            return SermonStyleMetrics(spacingBefore: 24, spacingAfter: 8, leftIndent: 0, rightIndent: 0, firstLineIndent: 0)
        case .subTheme:
            return SermonStyleMetrics(spacingBefore: 18, spacingAfter: 6, leftIndent: 0, rightIndent: 0, firstLineIndent: 0)
        case .body:
            // 첫 줄 1글자(= 글자 크기 1em) 들여쓰기 + 문단 아래 간격 14.
            // TextKit은 `lineSpacing`을 문단의 마지막 줄 아래에도 더하므로 문단 사이 실제 간격 = lineSpacing + 14.
            // (4였을 때는 줄 사이 간격과 4pt밖에 차이가 없어 문단 구분이 안 보였다.)
            return SermonStyleMetrics(spacingBefore: 0, spacingAfter: 14, leftIndent: 0, rightIndent: 0, firstLineIndent: fontSize)
        case .verseQuote:
            // 박스 위·아래 안여백은 문단 간격 안쪽에 그려지므로 (바깥 간격 + 안여백)을 문단 간격으로 준다.
            let padding = fontSize * versePaddingRatio
            return SermonStyleMetrics(spacingBefore: 8 + padding, spacingAfter: 14 + padding, leftIndent: 22, rightIndent: 14, firstLineIndent: 0)
        case .citation:
            return SermonStyleMetrics(spacingBefore: 6, spacingAfter: 14, leftIndent: 22, rightIndent: 22, firstLineIndent: 0)
        }
    }
}

// MARK: - 레이아웃 매니저 (말씀구절 박스 + 글자 배경)

/// 에디터·스크롤 뷰어·페이지 뷰어가 함께 쓰는 TextKit 1 레이아웃 매니저.
final class SermonLayoutManager: NSLayoutManager {
    /// 말씀구절 박스 왼쪽 세로 바 두께.
    private static let verseBarWidth: CGFloat = 3

    /// 표준 `.backgroundColor` 칠하기는 막는다 — TextKit 1은 이 attribute를 줄 높이(줄 간격 포함) 전체로 칠해
    /// 줄 사이가 이어진 큰 덩어리가 된다. 대신 `drawBackground`에서 줄마다 글자 상자 모양으로 직접 칠한다.
    /// 선택 영역 같은 다른 배경은 그대로 super가 칠한다(칠하려는 색이 이 범위의 `.backgroundColor`와 같을 때만 건너뛴다).
    override func fillBackgroundRectArray(
        _ rectArray: UnsafePointer<CGRect>, count rectCount: Int, forCharacterRange charRange: NSRange, color: PlatformColor
    ) {
        if let storage = textStorage, charRange.length > 0, NSMaxRange(charRange) <= storage.length,
           let attributeColor = storage.attribute(.backgroundColor, at: charRange.location, effectiveRange: nil) as? PlatformColor,
           attributeColor.sermonIsClose(to: color) {
            return
        }
        super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        // 말씀구절 박스/글자 배경을 먼저 칠하고 그 위에 `super`(선택 영역 하이라이트 등)를 칠한다 —
        // 순서가 반대면 불투명한 박스가 macOS의 드래그 선택 색을 덮어 선택이 보이지 않는다.
        guard let storage = textStorage, glyphsToShow.length > 0 else {
            super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
            return
        }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        // 박스의 위·아래 안여백은 줄 영역 바깥(문단 간격 안)에 그려지므로, 스크롤 중 새로 드러나는 띠에 안여백만 걸리고
        // 줄은 없는 경우를 위해 앞뒤 문단까지 확인한다. 단, 같은 컨테이너(페이지) 안의 글리프로만 제한한다.
        var containerGlyphs = NSRange(location: 0, length: 0)
        let hasContainer = textContainer(forGlyphAt: glyphsToShow.location, effectiveRange: &containerGlyphs) != nil && containerGlyphs.length > 0
        let drawableGlyphs = hasContainer ? containerGlyphs : glyphsToShow
        let text = storage.string as NSString
        var verseScan = charRange
        if verseScan.location > 0 {
            verseScan.location = text.paragraphRange(for: NSRange(location: verseScan.location - 1, length: 0)).location
            verseScan.length = NSMaxRange(charRange) - verseScan.location
        }
        if NSMaxRange(verseScan) < text.length {
            let after = text.paragraphRange(for: NSRange(location: NSMaxRange(verseScan), length: 0))
            verseScan.length = NSMaxRange(after) - verseScan.location
        }
        drawVerseBoxes(storage: storage, charRange: verseScan, glyphsToShow: drawableGlyphs, origin: origin)
        drawTextBackgrounds(storage: storage, charRange: charRange, origin: origin)
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    // MARK: 말씀구절 박스

    private func drawVerseBoxes(storage: NSTextStorage, charRange: NSRange, glyphsToShow: NSRange, origin: CGPoint) {
        let text = storage.string as NSString
        let verseRaw = SermonParagraphStyle.verseQuote.rawValue
        var cursor = charRange.location
        let end = min(NSMaxRange(charRange), text.length)
        while cursor < end {
            let paragraph = text.paragraphRange(for: NSRange(location: cursor, length: 0))
            let next = NSMaxRange(paragraph)
            cursor = next > cursor ? next : cursor + 1
            guard paragraph.length > 0,
                  (storage.attribute(.sermonParagraphStyle, at: paragraph.location, effectiveRange: nil) as? String) == verseRaw,
                  let fill = storage.attribute(.sermonVerseBoxFill, at: paragraph.location, effectiveRange: nil) as? PlatformColor
            else { continue }
            let bar = storage.attribute(.sermonVerseBoxBar, at: paragraph.location, effectiveRange: nil) as? PlatformColor

            // 이 문단 중 지금 그리는 구간에 들어 있는 글리프(페이지가 나뉘면 일부만).
            let paragraphGlyphs = glyphRange(forCharacterRange: paragraph, actualCharacterRange: nil)
            let visible = NSIntersectionRange(paragraphGlyphs, glyphsToShow)
            guard visible.length > 0 else { continue }
            let firstGlyph = visible.location
            let lastGlyph = NSMaxRange(visible) - 1
            let firstRect = lineFragmentRect(forGlyphAt: firstGlyph, effectiveRange: nil)
            let lastRect = lineFragmentRect(forGlyphAt: lastGlyph, effectiveRange: nil)
            let firstChar = characterIndexForGlyph(at: firstGlyph)
            let lastChar = characterIndexForGlyph(at: lastGlyph)
            let firstFont = (storage.attribute(.font, at: firstChar, effectiveRange: nil) as? PlatformFont) ?? PlatformFont.systemFont(ofSize: 16)
            let lastFont = (storage.attribute(.font, at: lastChar, effectiveRange: nil) as? PlatformFont) ?? firstFont
            // 기준선은 줄 상자 맨 위에서 `location.y` 아래다. 글자 상자 = 기준선 위 ascender ~ 아래 |descender|.
            let firstBaseline = firstRect.minY + location(forGlyphAt: firstGlyph).y
            let lastBaseline = lastRect.minY + location(forGlyphAt: lastGlyph).y
            let padding = firstFont.pointSize * SermonStyleMetrics.versePaddingRatio
            let top = firstBaseline - firstFont.ascender - padding
            let bottom = lastBaseline - lastFont.descender + padding
            guard bottom > top else { continue }

            let box = CGRect(x: firstRect.minX + origin.x, y: top + origin.y, width: firstRect.width, height: bottom - top)
            fillRect(box, color: fill)
            if let bar {
                fillRect(CGRect(x: box.minX, y: box.minY, width: Self.verseBarWidth, height: box.height), color: bar)
            }
        }
    }

    // MARK: 글자 배경(강조2 형광펜 등)

    private func drawTextBackgrounds(storage: NSTextStorage, charRange: NSRange, origin: CGPoint) {
        storage.enumerateAttribute(.backgroundColor, in: charRange, options: []) { value, attributeRange, _ in
            guard let color = value as? PlatformColor else { return }
            let glyphRange = self.glyphRange(forCharacterRange: attributeRange, actualCharacterRange: nil)
            self.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, container, lineGlyphRange, _ in
                let runGlyphs = NSIntersectionRange(lineGlyphRange, glyphRange)
                guard runGlyphs.length > 0 else { return }
                // 줄 끝의 문단 구분 문자(\n, \r, U+2028/2029)는 칠하지 않는다 — 이 글리프의 영역은 줄 오른쪽 끝까지 이어져
                // 배경이 컨테이너 폭 전체로 번지고, 글자 없는 빈 문단에도 띠가 생긴다. 글자가 안 남으면 건너뛴다.
                var runChars = self.characterRange(forGlyphRange: runGlyphs, actualGlyphRange: nil)
                let text = storage.string as NSString
                while runChars.length > 0 {
                    let last = text.character(at: NSMaxRange(runChars) - 1)
                    if last == 0x0A || last == 0x0D || last == 0x2028 || last == 0x2029 {
                        runChars.length -= 1
                    } else {
                        break
                    }
                }
                guard runChars.length > 0 else { return }
                let paintGlyphs = self.glyphRange(forCharacterRange: runChars, actualCharacterRange: nil)
                let bounds = self.boundingRect(forGlyphRange: paintGlyphs, in: container)
                guard bounds.width > 0.5 else { return }
                let font = (storage.attribute(.font, at: runChars.location, effectiveRange: nil) as? PlatformFont)
                    ?? PlatformFont.systemFont(ofSize: 17)
                let baselineY = lineRect.minY + self.location(forGlyphAt: paintGlyphs.location).y
                let box = CGRect(
                    x: bounds.minX + origin.x,
                    y: baselineY - font.ascender + origin.y,
                    width: bounds.width,
                    height: font.ascender - font.descender
                )
                self.fillRect(box, color: color)
            }
        }
    }

    private func fillRect(_ rect: CGRect, color: PlatformColor) {
        color.setFill()
        #if os(iOS)
        UIRectFill(rect)
        #elseif os(macOS)
        NSBezierPath(rect: rect).fill()
        #endif
    }
}

// MARK: - TextKit 1 텍스트뷰 생성 헬퍼

/// `keepStorageAlive`의 연관 객체 키(주소만 쓴다).
private nonisolated(unsafe) var sermonStorageKey: UInt8 = 0

/// `SermonLayoutManager`를 쓰는 TextKit 1 스택(저장소 → 레이아웃 매니저 → 컨테이너)을 만든다.
/// 좌우 여백은 텍스트뷰 inset으로만 주고 컨테이너의 `lineFragmentPadding`은 0이다 — 그래야 에디터/스크롤/페이지가 같은 위치에서 글자가 시작한다.
enum SermonTextKit1 {
    /// 저장소와 컨테이너를 함께 돌려준다. 저장소가 레이아웃 매니저를 붙들고(저장소 → 레이아웃 매니저 → 컨테이너)
    /// 레이아웃 매니저는 저장소를 붙들지 않으므로, 호출자가 저장소를 반드시 `keepStorageAlive`로 텍스트뷰에 매달아야 한다 —
    /// 그렇지 않으면 이 함수가 끝나는 순간 스택이 해제되어 텍스트뷰가 빈 화면이 된다.
    static func makeContainer(size: CGSize) -> (storage: NSTextStorage, container: NSTextContainer) {
        let storage = NSTextStorage()
        let layoutManager = SermonLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: size)
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        return (storage, container)
    }

    /// 텍스트뷰가 스택(저장소)을 확실히 붙들게 한다.
    static func keepStorageAlive(_ owner: AnyObject, storage: NSTextStorage) {
        objc_setAssociatedObject(owner, &sermonStorageKey, storage, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    #if os(iOS)
    static func makeTextView() -> UITextView {
        let (storage, container) = makeContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        let textView = UITextView(frame: .zero, textContainer: container)
        keepStorageAlive(textView, storage: storage)
        return textView
    }
    #elseif os(macOS)
    /// `NSTextView.scrollableTextView()`와 같은 구성(폭 추적·세로 리사이즈)에 TextKit 1 스택을 끼운 스크롤뷰+텍스트뷰.
    /// `makeTextView`는 (컨테이너, 초기 frame)으로 텍스트뷰(하위 클래스 포함)를 만든다.
    static func makeScrollView(makeTextView: (NSTextContainer, NSRect) -> NSTextView) -> (scrollView: NSScrollView, textView: NSTextView) {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        let (storage, container) = makeContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        let textView = makeTextView(container, NSRect(x: 0, y: 0, width: 400, height: 400))
        keepStorageAlive(textView, storage: storage)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView
        return (scrollView, textView)
    }
    #endif
}

// MARK: - 강조 1·2·3 (드래그한 글자에만)

/// 드래그한 글자에만 얹는 글자 단위 강조. 문단 스타일과 별개이며 색·굵기·배경·밑줄 표준 attribute로 RTF에 그대로 저장된다.
enum SermonEmphasis: Int, CaseIterable {
    case one = 1   // 굵게 + 와인색
    case two = 2   // 노란 형광펜
    case three = 3 // 파란 밑줄

    var displayName: String { "강조\(rawValue)" }

    static var oneColor: PlatformColor { PlatformColor(Color(hex: "#753B44") ?? .red) }
    static var twoColor: PlatformColor { PlatformColor(Color(hex: "#FFE08A") ?? .yellow) }
    static var threeColor: PlatformColor { PlatformColor(Color(hex: "#1F5F8B") ?? .blue) }
}

enum SermonEmphasisEditor {
    /// 선택 범위에 강조를 적용한다. 같은 강조가 범위 전체에 이미 있으면 해제(토글), 다른 강조가 있으면 교체한다.
    /// `kind`가 nil이면 해제만 한다. 호출자가 `beginEditing/endEditing`으로 감싼다.
    static func apply(_ kind: SermonEmphasis?, range: NSRange, in storage: NSTextStorage, settings: UserSettingsStore) {
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
        let alreadyApplied = kind.map { isApplied($0, range: range, in: storage) } ?? false
        clear(range: range, in: storage, settings: settings)
        guard let kind, !alreadyApplied else { return }
        switch kind {
        case .one:
            storage.addAttribute(.foregroundColor, value: SermonEmphasis.oneColor, range: range)
            storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
                guard let font = value as? PlatformFont else { return }
                storage.addAttribute(.font, value: fontSettingBold(font, bold: true), range: subrange)
            }
        case .two:
            storage.addAttribute(.backgroundColor, value: SermonEmphasis.twoColor, range: range)
        case .three:
            storage.addAttribute(.foregroundColor, value: SermonEmphasis.threeColor, range: range)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
    }

    /// 범위 전체가 해당 강조의 모양인지.
    static func isApplied(_ kind: SermonEmphasis, range: NSRange, in storage: NSTextStorage) -> Bool {
        var all = true
        switch kind {
        case .one, .three:
            let target = kind == .one ? SermonEmphasis.oneColor : SermonEmphasis.threeColor
            storage.enumerateAttribute(.foregroundColor, in: range, options: []) { value, _, stop in
                if let color = value as? PlatformColor, color.sermonIsClose(to: target) { return }
                all = false
                stop.pointee = true
            }
        case .two:
            storage.enumerateAttribute(.backgroundColor, in: range, options: []) { value, _, stop in
                if let color = value as? PlatformColor, color.sermonIsClose(to: SermonEmphasis.twoColor) { return }
                all = false
                stop.pointee = true
            }
        }
        return all
    }

    /// 범위의 강조를 모두 걷어낸다 — 글자색은 그 문단 스타일의 프리셋 색으로, 굵게는(프리셋 글꼴이 굵지 않을 때만) 끈다.
    static func clear(range: NSRange, in storage: NSTextStorage, settings: UserSettingsStore) {
        storage.enumerateAttribute(.backgroundColor, in: range, options: []) { value, subrange, _ in
            if let color = value as? PlatformColor, color.sermonIsClose(to: SermonEmphasis.twoColor) {
                storage.removeAttribute(.backgroundColor, range: subrange)
            }
        }
        storage.enumerateAttribute(.foregroundColor, in: range, options: []) { value, subrange, _ in
            guard let color = value as? PlatformColor else { return }
            let isOne = color.sermonIsClose(to: SermonEmphasis.oneColor)
            let isThree = color.sermonIsClose(to: SermonEmphasis.threeColor)
            guard isOne || isThree else { return }
            // 문단 스타일이 서로 다른 구간이 섞일 수 있어 문단 단위로 나눠 되돌린다.
            let text = storage.string as NSString
            var location = subrange.location
            while location < NSMaxRange(subrange) {
                let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
                let piece = NSIntersectionRange(subrange, paragraph)
                guard piece.length > 0 else { break }
                let styleRaw = storage.attribute(.sermonParagraphStyle, at: piece.location, effectiveRange: nil) as? String
                let style = styleRaw.flatMap(SermonParagraphStyle.init(rawValue:)) ?? .body
                storage.addAttribute(.foregroundColor, value: settings.sermonPlatformFontColor(for: style), range: piece)
                if isThree {
                    storage.removeAttribute(.underlineStyle, range: piece)
                }
                if isOne, !fontIsBold(settings.sermonPlatformFont(for: style)) {
                    storage.enumerateAttribute(.font, in: piece, options: []) { fontValue, fontRange, _ in
                        guard let font = fontValue as? PlatformFont else { return }
                        storage.addAttribute(.font, value: fontSettingBold(font, bold: false), range: fontRange)
                    }
                }
                location = NSMaxRange(piece)
            }
        }
    }

    // MARK: 굵게 도우미

    static func fontIsBold(_ font: PlatformFont) -> Bool {
        #if os(iOS)
        return font.fontDescriptor.symbolicTraits.contains(.traitBold)
        #elseif os(macOS)
        return font.fontDescriptor.symbolicTraits.contains(.bold)
        #endif
    }

    /// 굵게 비트만 켜거나 끈 글꼴. 글꼴 패밀리가 해당 굵기를 지원하지 않아 실패하면 원래 글꼴을 돌려준다.
    static func fontSettingBold(_ font: PlatformFont, bold: Bool) -> PlatformFont {
        #if os(iOS)
        var traits = font.fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) } else { traits.remove(.traitBold) }
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
        #elseif os(macOS)
        var traits = font.fontDescriptor.symbolicTraits
        if bold { traits.insert(.bold) } else { traits.remove(.bold) }
        let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
        #endif
    }
}
