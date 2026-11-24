//
//  SermonEditorTools.swift
//  JBCHBibleResearch
//
//  [2026-11-14 내 설교 고도화] 에디터 프록시(`SermonParagraphEditingProxy`)의 추가 기능.
//  - 문서 안 찾기/바꾸기(임시 배경 하이라이트), 개요(제목) 위치로 스크롤
//  - 서식 복사/붙여넣기(문단 스타일·줄간격·들여쓰기·간격·정렬 + 직접 지정한 글꼴/크기/색)
//  - 성경 구절 치환(선택한 참조 → 구절 본문 + 출처 표기)
//  iOS(UITextView)와 macOS(NSTextView)는 같은 구조로 따로 구현한다(`SermonParagraphEditor.swift`의 관례).
//

import SwiftUI
import BibleResearchModels
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - 문단 스타일 이름

extension SermonParagraphStyle {
    var sermonDisplayName: String {
        switch self {
        case .mainTheme: return String(localized: "대주제")
        case .midTheme: return String(localized: "중주제")
        case .subTheme: return String(localized: "소주제")
        case .verseQuote: return String(localized: "말씀구절")
        case .citation: return String(localized: "인용")
        case .body: return String(localized: "본문")
        }
    }
}

// MARK: - 서식 복사 값

struct SermonCopiedFormat: Equatable {
    var style: SermonParagraphStyle
    var extras: SermonParagraphExtras
    var alignment: PlatformTextAlignment
    /// 프리셋과 다르게 직접 지정돼 있던 값만 담는다(nil이면 붙여넣을 때 건드리지 않는다).
    var fontName: String?
    var fontSize: Double?
    var colorHex: String?

    var summary: String {
        var parts = [style.sermonDisplayName]
        if let fontSize { parts.append("\(Int(fontSize.rounded()))pt") }
        if let lineHeight = extras.lineHeight { parts.append(String(format: "줄간격 %.1f", lineHeight)) }
        if let colorHex { parts.append(colorHex) }
        return parts.joined(separator: " · ")
    }
}

extension SermonParagraphStyleCodec {
    /// 위치가 속한 문단의 0부터 시작하는 순번(`SermonVerseReference.paragraphIndex` 규약과 같은 `.byParagraphs` 기준).
    static func paragraphIndex(containing location: Int, in text: NSString) -> Int {
        guard text.length > 0 else { return 0 }
        var result = 0
        var index = 0
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: .byParagraphs) { _, range, _, stop in
            if range.location <= location { result = index } else { stop.pointee = true }
            index += 1
        }
        return result
    }

    /// 문단 순번에 해당하는 문단 범위(줄바꿈 포함). 순번이 범위를 벗어나면 nil.
    static func paragraphRange(at index: Int, in text: NSString) -> NSRange? {
        guard text.length > 0, index >= 0 else { return nil }
        var current = 0
        var found: NSRange?
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: .byParagraphs) { _, _, enclosing, stop in
            if current == index { found = enclosing; stop.pointee = true }
            current += 1
        }
        return found
    }

    static func hexString(of color: PlatformColor) -> String? {
        guard let rgba = color.sermonRGBA else { return nil }
        func channel(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", channel(rgba.r), channel(rgba.g), channel(rgba.b))
    }

    /// 선택(또는 캐럿) 위치의 서식을 읽는다. 글꼴·크기·색은 그 문단 스타일의 프리셋과 다를 때만 담는다.
    static func captureFormat(in storage: NSTextStorage, selection: NSRange, settings: UserSettingsStore) -> SermonCopiedFormat? {
        guard storage.length > 0 else { return nil }
        let text = storage.string as NSString
        let location = min(max(0, selection.location), storage.length - 1)
        let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
        guard paragraph.location < storage.length else { return nil }
        let style = (storage.attribute(.sermonParagraphStyle, at: paragraph.location, effectiveRange: nil) as? String)
            .flatMap(SermonParagraphStyle.init(rawValue:)) ?? .body
        let extras = extras(in: storage, at: paragraph.location)
        let alignment = (storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle)?.alignment ?? .natural
        // 글자 서식은 선택 첫 글자, 캐럿이면 캐럿 바로 앞 글자(문단 맨 앞이면 첫 글자)에서 읽는다.
        let sampleIndex = (selection.length > 0 || location == paragraph.location) ? location : location - 1
        let font = storage.attribute(.font, at: min(max(0, sampleIndex), storage.length - 1), effectiveRange: nil) as? PlatformFont
        let color = storage.attribute(.foregroundColor, at: min(max(0, sampleIndex), storage.length - 1), effectiveRange: nil) as? PlatformColor
        let presetFont = settings.sermonPlatformFont(for: style)
        let presetColor = settings.sermonPlatformFontColor(for: style)

        var fontName: String?
        var fontSize: Double?
        if let font {
            if font.familyName != presetFont.familyName { fontName = font.fontName }
            if abs(Double(font.pointSize) - Double(presetFont.pointSize)) > 0.01 { fontSize = Double(font.pointSize) }
        }
        var colorHex: String?
        if let color, !color.sermonIsClose(to: presetColor) { colorHex = hexString(of: color) }
        return SermonCopiedFormat(style: style, extras: extras, alignment: alignment, fontName: fontName, fontSize: fontSize, colorHex: colorHex)
    }
}

/// 하드웨어 키보드 글자 판별 — 입력 소스가 한글 등이어도 물리 키로 a–z를 얻는다.
enum SermonKeyLetters {
    /// macOS ANSI 키코드(Carbon `kVK_ANSI_*`) → 소문자.
    static let macKeyCodes: [UInt16: String] = [
        0x00: "a", 0x0B: "b", 0x08: "c", 0x02: "d", 0x0E: "e", 0x03: "f", 0x05: "g", 0x04: "h", 0x22: "i", 0x26: "j",
        0x28: "k", 0x25: "l", 0x2E: "m", 0x2D: "n", 0x1F: "o", 0x23: "p", 0x0C: "q", 0x0F: "r", 0x01: "s", 0x11: "t",
        0x20: "u", 0x09: "v", 0x0D: "w", 0x07: "x", 0x10: "y", 0x06: "z",
    ]

    /// iOS HID 사용 코드(a = 4 … z = 29) → 소문자.
    static func letter(forHIDUsage usage: Int) -> String? {
        guard usage >= 4, usage <= 29, let scalar = UnicodeScalar(UInt32(97 + usage - 4)) else { return nil }
        return String(Character(scalar))
    }
}

/// 툴바가 보여 주는 "지금 커서 위치의 서식".
struct SermonActiveFormat: Equatable {
    var fontName: String = ""
    var fontSize: Double = 0
    var colorHex: String?
    var alignment: PlatformTextAlignment = .natural
}

extension SermonParagraphEditingProxy {
    static func familyLabel(of font: PlatformFont) -> String {
        #if os(iOS)
        return font.familyName
        #else
        return font.familyName ?? font.fontName
        #endif
    }

    func refreshActiveFormat() {
        let attributes = sampleAttributes()
        var format = SermonActiveFormat()
        if let font = attributes[.font] as? PlatformFont {
            format.fontName = Self.familyLabel(of: font)
            format.fontSize = Double(font.pointSize)
        }
        if let color = attributes[.foregroundColor] as? PlatformColor { format.colorHex = SermonParagraphStyleCodec.hexString(of: color) }
        if let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle { format.alignment = paragraph.alignment }
        if activeFormat != format { activeFormat = format }
    }

    /// 복사한 문단 추가 서식(줄간격·목록·들여쓰기·문단 간격)을 선택 문단에 모두 적용한다. 각 항목은 `updateExtra`로 실행 취소에 등록된다.
    func applyExtras(_ extras: SermonParagraphExtras, settings: UserSettingsStore) {
        updateExtra(\.lineHeight, to: extras.lineHeight, settings: settings, actionName: String(localized: "서식 붙여넣기"))
        updateExtra(\.list, to: extras.list, settings: settings, actionName: String(localized: "서식 붙여넣기"))
        updateExtra(\.firstLineIndent, to: extras.firstLineIndent, settings: settings, actionName: String(localized: "서식 붙여넣기"))
        updateExtra(\.leftIndent, to: extras.leftIndent, settings: settings, actionName: String(localized: "서식 붙여넣기"))
        updateExtra(\.rightIndent, to: extras.rightIndent, settings: settings, actionName: String(localized: "서식 붙여넣기"))
        updateExtra(\.spaceBefore, to: extras.spaceBefore, settings: settings, actionName: String(localized: "서식 붙여넣기"))
        updateExtra(\.spaceAfter, to: extras.spaceAfter, settings: settings, actionName: String(localized: "서식 붙여넣기"))
    }
}

#if os(iOS)

// MARK: - iOS 프록시 확장

extension SermonParagraphEditingProxy {
    var selectionRange: NSRange { textView?.selectedRange ?? NSRange(location: 0, length: 0) }

    /// 선택이 있으면 선택 첫 글자의 속성, 캐럿만 있으면 다음에 입력될 글자의 속성(타이핑 속성).
    func sampleAttributes() -> [NSAttributedString.Key: Any] {
        guard let textView else { return [:] }
        let storage = textView.textStorage
        let selection = textView.selectedRange
        if selection.length > 0, selection.location < storage.length {
            return storage.attributes(at: selection.location, effectiveRange: nil)
        }
        return textView.typingAttributes
    }
    var documentText: String { textView?.text ?? "" }

    func focusEditor() { textView?.becomeFirstResponder() }

    /// 이 순번의 문단을 화면 위쪽으로 올리고 캐럿을 그 문단 처음에 둔다(개요 내비게이터).
    func scrollToParagraph(_ index: Int) {
        guard let textView, let range = SermonParagraphStyleCodec.paragraphRange(at: index, in: textView.textStorage.string as NSString) else { return }
        textView.selectedRange = NSRange(location: range.location, length: 0)
        let layoutManager = textView.layoutManager
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: range.location, length: min(1, range.length)), actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textView.textContainer)
        let maxOffset = max(0, textView.contentSize.height - textView.bounds.height + textView.adjustedContentInset.bottom)
        let target = max(0, rect.minY + textView.textContainerInset.top - 12)
        textView.setContentOffset(CGPoint(x: 0, y: min(target, maxOffset)), animated: true)
    }

    // MARK: 찾기

    func findRanges(_ query: String) -> [NSRange] {
        guard let textView, !query.isEmpty else { return [] }
        let text = textView.textStorage.string as NSString
        var results: [NSRange] = []
        var searchRange = NSRange(location: 0, length: text.length)
        while searchRange.length > 0 {
            let found = text.range(of: query, options: [.caseInsensitive], range: searchRange)
            if found.location == NSNotFound || found.length == 0 { break }
            results.append(found)
            let next = NSMaxRange(found)
            searchRange = NSRange(location: next, length: text.length - next)
        }
        return results
    }

    /// 일치 항목을 칠한다(`SermonLayoutManager`가 그리는 표시일 뿐 저장되는 서식이 아니다). `current`는 주황, 나머지는 노랑.
    func showFind(_ ranges: [NSRange], current: Int?) {
        guard let textView, let layoutManager = textView.layoutManager as? SermonLayoutManager else { return }
        let length = textView.textStorage.length
        layoutManager.findHighlights = ranges.enumerated().compactMap { index, range in
            NSMaxRange(range) <= length ? SermonFindHighlight(range: range, isCurrent: index == current) : nil
        }
        if let current, ranges.indices.contains(current), NSMaxRange(ranges[current]) <= length {
            textView.scrollRangeToVisible(ranges[current])
        }
    }

    func clearFind() {
        guard let layoutManager = textView?.layoutManager as? SermonLayoutManager else { return }
        layoutManager.findHighlights = []
    }

    /// 범위를 바꾼다(타이핑과 같은 경로라 실행 취소에 등록된다).
    func replace(_ range: NSRange, with replacement: String) {
        guard let textView, NSMaxRange(range) <= textView.textStorage.length else { return }
        if textView.markedTextRange != nil { textView.unmarkText() }
        textView.selectedRange = range
        textView.insertText(replacement)
    }

    /// 뒤에서부터 바꿔 앞쪽 범위가 어긋나지 않게 한다.
    func replaceAll(_ ranges: [NSRange], with replacement: String) {
        guard let textView else { return }
        textView.undoManager?.beginUndoGrouping()
        for range in ranges.sorted(by: { $0.location > $1.location }) { replace(range, with: replacement) }
        textView.undoManager?.endUndoGrouping()
    }

    // MARK: 서식 복사

    func copyFormat(settings: UserSettingsStore) -> SermonCopiedFormat? {
        guard let textView else { return nil }
        return SermonParagraphStyleCodec.captureFormat(in: textView.textStorage, selection: textView.selectedRange, settings: settings)
    }

    /// 선택(없으면 캐럿 문단)에 복사한 서식을 입힌다. 글꼴·크기·색은 복사한 쪽에 직접 지정돼 있던 것만 옮긴다.
    func pasteFormat(_ format: SermonCopiedFormat, settings: UserSettingsStore) {
        guard let textView, textView.textStorage.length > 0 else { return }
        let original = textView.selectedRange
        let paragraphRange = (textView.textStorage.string as NSString).paragraphRange(for: original)
        textView.undoManager?.beginUndoGrouping()
        applyParagraphStyle(format.style, settings: settings)
        applyExtras(format.extras, settings: settings)
        applyAlignment(format.alignment)
        let charRange = original.length > 0 ? original : paragraphRange
        textView.selectedRange = charRange
        if let name = format.fontName { applyFontFamily(name, settings: settings) }
        if let size = format.fontSize { applyFontSize(CGFloat(size), settings: settings) }
        if let hex = format.colorHex { applyColor(hex, settings: settings) }
        textView.selectedRange = original
        textView.undoManager?.endUndoGrouping()
        refreshActiveStyle()
    }

    // MARK: 구절 치환

    func canSubstituteVerse() -> Bool {
        guard let textView, textView.isEditable else { return false }
        return SermonQuoteService.target(in: textView.textStorage.string, selection: textView.selectedRange) != nil
    }

    /// 참조 범위를 구절로 바꾼다. 말씀구절 스타일이면 새 문단의 순번을 돌려준다(`SermonVerseReference` 저장용), 인라인이면 nil.
    @discardableResult
    func substituteReference(range: NSRange, quote: String, citation: String, mode: SermonVerseSubstituteMode, settings: UserSettingsStore) -> Int? {
        guard let textView, NSMaxRange(range) <= textView.textStorage.length else { return nil }
        if textView.markedTextRange != nil { textView.unmarkText() }
        let storage = textView.textStorage
        let plan = SermonVerseSubstitutionPlan.make(in: storage.string as NSString, range: range, quote: quote, citation: citation, mode: mode)
        textView.selectedRange = plan.replaceRange
        textView.insertText(plan.replacement)
        guard mode == .verseStyle else { return nil }

        let newText = storage.string as NSString
        let verseLocation = min(plan.verseOffset, max(0, newText.length - 1))
        let verseParagraph = newText.paragraphRange(for: NSRange(location: verseLocation, length: 0))
        performUndoableAttributeEdit(on: textView, range: verseParagraph, actionName: String(localized: "구절 치환")) { target in
            target.beginEditing()
            SermonParagraphStyleCodec.applyStyle(.verseQuote, to: verseParagraph, in: target, settings: settings, isStyleChange: true)
            target.endEditing()
        }
        var caret = NSMaxRange(verseParagraph)
        if caret > verseParagraph.location, newText.character(at: caret - 1) == 10 { caret -= 1 }
        textView.selectedRange = NSRange(location: caret, length: 0)
        applyTypingAttributes(for: .verseQuote, settings: settings, to: textView)
        refreshActiveStyle()
        return SermonParagraphStyleCodec.paragraphIndex(containing: verseLocation, in: newText)
    }
}

#elseif os(macOS)

// MARK: - macOS 프록시 확장

extension SermonShortcutModifier {
    /// 우클릭 메뉴 항목에 단축키를 표시하기 위한 수정키.
    var eventModifierFlags: NSEvent.ModifierFlags {
        switch self {
        case .control: return [.control]
        case .option: return [.option]
        case .controlShift: return [.control, .shift]
        case .commandShift: return [.command, .shift]
        }
    }
}

extension SermonParagraphEditingProxy {
    var selectionRange: NSRange { textView?.selectedRange() ?? NSRange(location: 0, length: 0) }

    func sampleAttributes() -> [NSAttributedString.Key: Any] {
        guard let textView, let storage = textView.textStorage else { return [:] }
        let selection = textView.selectedRange()
        if selection.length > 0, selection.location < storage.length {
            return storage.attributes(at: selection.location, effectiveRange: nil)
        }
        return textView.typingAttributes
    }
    var documentText: String { textView?.string ?? "" }

    func focusEditor() { textView?.window?.makeFirstResponder(textView) }

    func scrollToParagraph(_ index: Int) {
        guard let textView, let layoutManager = textView.layoutManager,
              let range = SermonParagraphStyleCodec.paragraphRange(at: index, in: textView.string as NSString) else { return }
        textView.setSelectedRange(NSRange(location: range.location, length: 0))
        guard let container = textView.textContainer else { return }
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: range.location, length: min(1, range.length)), actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
        let y = max(0, rect.minY + textView.textContainerInset.height - 12)
        if let clip = textView.enclosingScrollView?.contentView {
            clip.scroll(to: NSPoint(x: 0, y: y))
            textView.enclosingScrollView?.reflectScrolledClipView(clip)
        } else {
            textView.scrollRangeToVisible(range)
        }
    }

    func findRanges(_ query: String) -> [NSRange] {
        guard let textView, !query.isEmpty else { return [] }
        let text = textView.string as NSString
        var results: [NSRange] = []
        var searchRange = NSRange(location: 0, length: text.length)
        while searchRange.length > 0 {
            let found = text.range(of: query, options: [.caseInsensitive], range: searchRange)
            if found.location == NSNotFound || found.length == 0 { break }
            results.append(found)
            let next = NSMaxRange(found)
            searchRange = NSRange(location: next, length: text.length - next)
        }
        return results
    }

    func showFind(_ ranges: [NSRange], current: Int?) {
        guard let textView, let layoutManager = textView.layoutManager else { return }
        let full = NSRange(location: 0, length: (textView.string as NSString).length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
        for (index, range) in ranges.enumerated() where NSMaxRange(range) <= full.length {
            let color = index == current ? NSColor(red: 1.0, green: 0.62, blue: 0.26, alpha: 1) : NSColor(red: 1.0, green: 0.89, blue: 0.54, alpha: 1)
            layoutManager.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: range)
        }
        if let current, ranges.indices.contains(current), NSMaxRange(ranges[current]) <= full.length {
            textView.scrollRangeToVisible(ranges[current])
        }
    }

    func clearFind() {
        guard let textView, let layoutManager = textView.layoutManager else { return }
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: (textView.string as NSString).length))
    }

    func replace(_ range: NSRange, with replacement: String) {
        guard let textView, NSMaxRange(range) <= (textView.string as NSString).length else { return }
        if textView.hasMarkedText() { textView.unmarkText() }
        textView.insertText(replacement, replacementRange: range)
    }

    func replaceAll(_ ranges: [NSRange], with replacement: String) {
        guard let textView else { return }
        textView.undoManager?.beginUndoGrouping()
        for range in ranges.sorted(by: { $0.location > $1.location }) { replace(range, with: replacement) }
        textView.undoManager?.endUndoGrouping()
    }

    func copyFormat(settings: UserSettingsStore) -> SermonCopiedFormat? {
        guard let textView, let storage = textView.textStorage else { return nil }
        return SermonParagraphStyleCodec.captureFormat(in: storage, selection: textView.selectedRange(), settings: settings)
    }

    func pasteFormat(_ format: SermonCopiedFormat, settings: UserSettingsStore) {
        guard let textView, let storage = textView.textStorage, storage.length > 0 else { return }
        let original = textView.selectedRange()
        let paragraphRange = (storage.string as NSString).paragraphRange(for: original)
        textView.undoManager?.beginUndoGrouping()
        applyParagraphStyle(format.style, settings: settings)
        applyExtras(format.extras, settings: settings)
        applyAlignment(format.alignment)
        let charRange = original.length > 0 ? original : paragraphRange
        textView.setSelectedRange(charRange)
        if let name = format.fontName { applyFontFamily(name, settings: settings) }
        if let size = format.fontSize { applyFontSize(CGFloat(size), settings: settings) }
        if let hex = format.colorHex { applyColor(hex, settings: settings) }
        textView.setSelectedRange(original)
        textView.undoManager?.endUndoGrouping()
        refreshActiveStyle()
    }

    func canSubstituteVerse() -> Bool {
        guard let textView, textView.isEditable else { return false }
        return SermonQuoteService.target(in: textView.string, selection: textView.selectedRange()) != nil
    }

    @discardableResult
    func substituteReference(range: NSRange, quote: String, citation: String, mode: SermonVerseSubstituteMode, settings: UserSettingsStore) -> Int? {
        guard let textView, let storage = textView.textStorage, NSMaxRange(range) <= storage.length else { return nil }
        if textView.hasMarkedText() { textView.unmarkText() }
        let plan = SermonVerseSubstitutionPlan.make(in: storage.string as NSString, range: range, quote: quote, citation: citation, mode: mode)
        textView.setSelectedRange(plan.replaceRange)
        textView.insertText(plan.replacement, replacementRange: plan.replaceRange)
        guard mode == .verseStyle else { return nil }

        let newText = storage.string as NSString
        let verseLocation = min(plan.verseOffset, max(0, newText.length - 1))
        let verseParagraph = newText.paragraphRange(for: NSRange(location: verseLocation, length: 0))
        performUndoableAttributeEdit(on: textView, range: verseParagraph, actionName: String(localized: "구절 치환")) { target in
            target.beginEditing()
            SermonParagraphStyleCodec.applyStyle(.verseQuote, to: verseParagraph, in: target, settings: settings, isStyleChange: true)
            target.endEditing()
        }
        var caret = NSMaxRange(verseParagraph)
        if caret > verseParagraph.location, newText.character(at: caret - 1) == 10 { caret -= 1 }
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        applyTypingAttributes(for: .verseQuote, settings: settings, to: textView)
        refreshActiveStyle()
        return SermonParagraphStyleCodec.paragraphIndex(containing: verseLocation, in: newText)
    }
}

#endif

// MARK: - 구절 치환 계획 (플랫폼 공용)

/// 치환할 텍스트와 범위를 정한다. 텍스트뷰에 쓰기 전에 순수 계산만 하므로 두 플랫폼이 같은 결과를 낸다.
struct SermonVerseSubstitutionPlan {
    let replaceRange: NSRange
    let replacement: String
    /// 치환 뒤 말씀구절 문단이 시작하는 위치(말씀구절 스타일일 때만 의미가 있다).
    let verseOffset: Int

    static func make(in text: NSString, range: NSRange, quote: String, citation: String, mode: SermonVerseSubstituteMode) -> SermonVerseSubstitutionPlan {
        let tail = citation.isEmpty ? "" : " \(citation)"
        switch mode {
        case .inline:
            // 현재 스타일 유지 — 줄 안에서 따옴표로 묶어 바꾼다.
            return SermonVerseSubstitutionPlan(replaceRange: range, replacement: "\u{201C}\(quote)\u{201D}\(tail)", verseOffset: range.location)
        case .verseStyle:
            let paragraph = text.paragraphRange(for: range)
            let before = text.substring(with: NSRange(location: paragraph.location, length: range.location - paragraph.location))
            let afterStart = NSMaxRange(range)
            let after = text.substring(with: NSRange(location: afterStart, length: max(0, NSMaxRange(paragraph) - afterStart)))
            let beforeBlank = before.trimmingCharacters(in: .whitespaces).isEmpty
            let afterBlank = after.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            var replacement = quote + tail
            var leading = 0
            if !beforeBlank { replacement = "\n" + replacement; leading = 1 }
            if !afterBlank { replacement += "\n" }
            // 참조 앞이 공백뿐이면 그 공백도 함께 지워 말씀구절 문단이 공백으로 시작하지 않게 한다.
            let replaceRange = beforeBlank
                ? NSRange(location: paragraph.location, length: NSMaxRange(range) - paragraph.location)
                : range
            return SermonVerseSubstitutionPlan(replaceRange: replaceRange, replacement: replacement, verseOffset: replaceRange.location + leading)
        }
    }
}
