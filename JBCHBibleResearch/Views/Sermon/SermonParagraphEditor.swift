//
//  SermonParagraphEditor.swift
//  JBCHBibleResearch
//
//  설교 전용 문단 스타일 에디터. 문단 스타일이 없는 기존 `RichTextEditor`는 건드리지 않고
//  별도 컴포넌트로 두며, `UITextView`/`NSTextView` 래핑 구조만 같은 관례를 따른다.
//
//  ⚠️ 저장 포맷: `contentHtml`은 실제로는 RTF이고 커스텀 attribute는 RTF에 남지 않는다.
//  그래서 문단 스타일(`SermonParagraphStyle`)은 `paragraphStyles` 필드에 별도로 병행 저장한다.
//  ⚠️ 렌더링: 스타일의 폰트/크기/줄간격은 저장하지 않고 열 때마다 `UserSettingsStore` 현재값으로
//  다시 계산한다(열려 있는 에디터에 설정 변경을 실시간 반영하지는 않는다). 굵게/기울임은
//  `fontPreservingBoldItalic`이 글자 단위로 보존한다.

import SwiftUI
import BibleResearchModels
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - 커스텀 attribute 키

extension NSAttributedString.Key {
    /// 문단 하나의 `SermonParagraphStyle`(rawValue)을 표시하는 커스텀 attribute.
    /// RTF로 저장되지 않아 편집 중에만 유효하며, 저장은 `SermonParagraphStyleCodec.export`가 담당한다.
    static let sermonParagraphStyle = NSAttributedString.Key("com.jbch.sermon.paragraphStyle")
}

// MARK: - 문단 스타일 ↔ 저장 문자열 변환

enum SermonParagraphStyleCodec {
    /// 문단 스타일 배열을 합칠 때 쓰는 구분자(ASCII Unit Separator, U+001F) —
    /// 사용자가 입력할 수 없고 `rawValue`와 충돌하지 않는다.
    static let delimiter = "\u{1F}"

    /// 마지막 저장 시점에 각 스타일이 실제로 어떤 폰트/크기/색이었는지의 스냅샷 한 칸.
    /// `applyStyle`이 현재 글자의 폰트/색과 비교해 다르면 사용자가 수동 지정한 것으로 보고 보존한다.
    struct StyleSnapshot: Codable {
        var fontName: String
        var fontSize: Double
        var colorHex: String
    }

    /// 현재 `UserSettingsStore`의 스타일별 값을 JSON 문자열로 찍는다(`SermonEditorView.save()`가 저장 시마다 호출).
    static func captureSnapshot(settings: UserSettingsStore) -> String {
        var dict: [String: StyleSnapshot] = [:]
        for style in SermonParagraphStyle.allCases {
            dict[style.rawValue] = StyleSnapshot(
                fontName: settings.sermonFontName(for: style),
                fontSize: settings.sermonFontSize(for: style),
                colorHex: settings.sermonFontColorHex(for: style)
            )
        }
        guard let data = try? JSONEncoder().encode(dict), let json = String(data: data, encoding: .utf8) else { return "" }
        return json
    }

    /// 저장된 스냅샷 문자열을 되돌린다. 비어 있거나 디코딩에 실패하면 빈 딕셔너리
    /// ("아직 수동 지정된 적 없음")를 돌려준다.
    static func decodeSnapshot(_ raw: String) -> [SermonParagraphStyle: StyleSnapshot] {
        guard !raw.isEmpty, let data = raw.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: StyleSnapshot].self, from: data) else { return [:] }
        var result: [SermonParagraphStyle: StyleSnapshot] = [:]
        for (key, value) in dict {
            guard let style = SermonParagraphStyle(rawValue: key) else { continue }
            result[style] = value
        }
        return result
    }

    /// 텍스트 스토리지를 `.byParagraphs`로 순회하며 문단별 `.sermonParagraphStyle`을 읽어
    /// 저장용 문자열로 합친다. attribute가 없는 문단은 `.body`로 채운다.
    static func export(from textStorage: NSTextStorage) -> String {
        let fullText = textStorage.string as NSString
        guard fullText.length > 0 else { return "" }
        var styles: [String] = []
        fullText.enumerateSubstrings(
            in: NSRange(location: 0, length: fullText.length), options: .byParagraphs
        ) { _, paragraphRange, _, _ in
            let style = (textStorage.attribute(.sermonParagraphStyle, at: paragraphRange.location, effectiveRange: nil) as? String)
                ?? SermonParagraphStyle.body.rawValue
            styles.append(style)
        }
        return styles.joined(separator: delimiter)
    }

    /// 저장된 문자열을 텍스트 스토리지에 되돌려 문단별 스타일 attribute와 현재 설정값을 적용한다.
    /// 문단 수와 저장 개수가 어긋나면 모자란 자리는 `.body`로 채워 크래시를 막는다.
    static func apply(_ stored: String, to textStorage: NSTextStorage, settings: UserSettingsStore, previousSnapshot: String = "") {
        let raw = stored.isEmpty ? [] : stored.components(separatedBy: delimiter)
        let fullText = textStorage.string as NSString
        guard fullText.length > 0 else { return }
        let snapshot = decodeSnapshot(previousSnapshot)
        var index = 0
        textStorage.beginEditing()
        fullText.enumerateSubstrings(
            in: NSRange(location: 0, length: fullText.length), options: .byParagraphs
        ) { _, paragraphRange, _, _ in
            defer { index += 1 }
            guard paragraphRange.length > 0 else { return }
            let style = (index < raw.count ? SermonParagraphStyle(rawValue: raw[index]) : nil) ?? .body
            applyStyle(style, to: paragraphRange, in: textStorage, settings: settings, previousSnapshot: snapshot)
        }
        textStorage.endEditing()
    }

    /// 문단 하나에 스타일을 적용한다(불러오기와 스타일 pill 선택 양쪽에서 공유).
    /// `previousSnapshot`과 현재 글자의 실제 폰트/색이 다르면 수동 지정으로 보고 유지하고,
    /// 같거나 스냅샷이 없으면 프리셋을 새로 적용한다(굵게/기울임은 보존). 정렬은 프리셋이
    /// 값을 지정하지 않으므로(`.natural`) natural이 아니면 수동 지정으로 본다.
    static func applyStyle(
        _ style: SermonParagraphStyle, to paragraphRange: NSRange,
        in textStorage: NSTextStorage, settings: UserSettingsStore,
        previousSnapshot: [SermonParagraphStyle: StyleSnapshot] = [:]
    ) {
        textStorage.addAttribute(.sermonParagraphStyle, value: style.rawValue, range: paragraphRange)
        let baseFont = settings.sermonPlatformFont(for: style)
        let baseColor = settings.sermonPlatformFontColor(for: style)
        let previous = previousSnapshot[style]
        let previousColor = previous.flatMap { Color(hex: $0.colorHex) }.map(PlatformColor.init)

        textStorage.enumerateAttribute(.font, in: paragraphRange, options: []) { value, subrange, _ in
            let originalFont = (value as? PlatformFont) ?? baseFont
            let isManualFont: Bool = {
                guard let previous else { return false }
                return originalFont.fontName != previous.fontName
                    || abs(Double(originalFont.pointSize) - previous.fontSize) > 0.01
            }()
            guard !isManualFont else { return }
            var resolvedFont = fontPreservingBoldItalic(from: originalFont, applying: baseFont)
            if style == .citation {
                // 인용은 "항상 이탤릭"이 스타일 고정 속성이므로, 보존한 굵게 비트는 두고 기울임만 강제한다.
                resolvedFont = italicVariant(of: resolvedFont)
            }
            textStorage.addAttribute(.font, value: resolvedFont, range: subrange)
        }

        textStorage.enumerateAttribute(.foregroundColor, in: paragraphRange, options: []) { value, subrange, _ in
            let originalColor = value as? PlatformColor
            let isManualColor: Bool = {
                guard let previousColor, let originalColor else { return false }
                return !originalColor.isEqual(previousColor)
            }()
            guard !isManualColor else { return }
            textStorage.addAttribute(.foregroundColor, value: baseColor, range: subrange)
        }

        textStorage.enumerateAttribute(.paragraphStyle, in: paragraphRange, options: []) { value, subrange, _ in
            let existingAlignment = (value as? NSParagraphStyle)?.alignment
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = baseFont.typographicLineHeight * max(0, settings.sermonLineHeightMultiple(for: style) - 1)
            if let existingAlignment, existingAlignment != .natural {
                paragraphStyle.alignment = existingAlignment
            }
            if style == .verseQuote {
                // 왼쪽 세로 바는 표준 attribute로 표현할 수 없어(커스텀 `NSLayoutManager` 필요)
                // 에디터에서는 안쪽 여백과 배경색 박스까지만 구현한다.
                paragraphStyle.headIndent = 14
                paragraphStyle.firstLineHeadIndent = 14
                paragraphStyle.paragraphSpacingBefore = 6
                paragraphStyle.paragraphSpacing = 6
            }
            if style == .citation {
                // 오른쪽 여백은 `tailIndent`를 음수로 주면 trailing margin 기준 거리가 된다.
                //
                // ⚠️ 문단 위아래 점선(구분선)은 표준 attribute로 표현할 수 없어(커스텀
                // `NSLayoutManager` 필요) 에디터에는 없다. 뷰어(`SermonViewerText.swift`)도 편집 화면과
                // 똑같이 보이도록 이 파일의 서식만 그대로 그리므로 점선을 그리지 않는다.
                paragraphStyle.headIndent = 10
                paragraphStyle.firstLineHeadIndent = 10
                paragraphStyle.tailIndent = -10
            }
            textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: subrange)
        }

        if style == .verseQuote {
            textStorage.addAttribute(.backgroundColor, value: settings.sermonVerseQuoteBackgroundPlatformColor, range: paragraphRange)
        } else {
            textStorage.removeAttribute(.backgroundColor, range: paragraphRange)
        }
    }

    /// 인용 스타일용으로 원본 폰트에 이탤릭 비트를 강제로 추가한다. 실패 시 원래 폰트를 반환한다.
    ///
    /// ⚠️ 폰트 패밀리가 이탤릭 변형을 지원하지 않으면(커스텀 한글 폰트 다수) 적용되지 않거나
    /// 시스템의 가짜 기울임으로 그려질 수 있다.
    static func italicVariant(of font: PlatformFont) -> PlatformFont {
        #if os(iOS)
        var traits = font.fontDescriptor.symbolicTraits
        traits.insert(.traitItalic)
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
        #elseif os(macOS)
        // macOS의 `NSFontDescriptor.withSymbolicTraits`는 iOS와 달리 옵셔널이 아니다.
        var traits = font.fontDescriptor.symbolicTraits
        traits.insert(.italic)
        let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
        #endif
    }

    /// 뷰어용 — 저장된 `contentText`와 `paragraphStyles`만으로 문단 배열을 만든다.
    /// `export(from:)`와 같은 `.byParagraphs` 순회라 인덱스가 어긋나지 않으며,
    /// 개수가 어긋나면 `apply`와 동일하게 `.body`로 채운다.
    static func parseParagraphs(text: String, styles storedStyles: String) -> [(text: String, style: SermonParagraphStyle)] {
        let fullText = text as NSString
        guard fullText.length > 0 else { return [] }
        let raw = storedStyles.isEmpty ? [] : storedStyles.components(separatedBy: delimiter)
        var result: [(text: String, style: SermonParagraphStyle)] = []
        var index = 0
        fullText.enumerateSubstrings(
            in: NSRange(location: 0, length: fullText.length), options: .byParagraphs
        ) { substring, _, _, _ in
            defer { index += 1 }
            let style = (index < raw.count ? SermonParagraphStyle(rawValue: raw[index]) : nil) ?? .body
            result.append((text: substring ?? "", style: style))
        }
        return result
    }

    /// 성경구절 선택 → 새 설교 작성 시, 구절들을 `.verseQuote` 문단으로 삽입한 문서를 살아있는
    /// 텍스트뷰 없이 임시 `NSTextStorage`로 미리 만든다(에디터가 열리기 전이라 `insertVerseQuoteParagraph`
    /// 를 쓸 수 없음). RTF, 순수텍스트, 문단스타일 문자열을 돌려준다.
    static func buildVerseQuoteDocument(verseTexts: [String], settings: UserSettingsStore) -> (rtf: String, plainText: String, paragraphStyles: String) {
        guard !verseTexts.isEmpty else { return ("", "", "") }
        let storage = NSTextStorage()
        storage.beginEditing()
        var location = 0
        for text in verseTexts {
            let paragraphText = text + "\n"
            let length = (paragraphText as NSString).length
            storage.replaceCharacters(in: NSRange(location: location, length: 0), with: NSAttributedString(string: paragraphText))
            applyStyle(.verseQuote, to: NSRange(location: location, length: length), in: storage, settings: settings)
            location += length
        }
        storage.endEditing()
        let (rtf, plain) = RichTextCodec.encode(storage)
        let styles = export(from: storage)
        return (rtf, plain, styles)
    }

    /// `originalFont`의 굵게/기울임 비트만 골라 `applying`(현재 설정의 패밀리+크기)에 다시 입힌다.
    /// 분류 비트(세리프 등)까지 복사하면 새 패밀리가 그 조합을 지원하지 않아
    /// `withSymbolicTraits`가 실패할 수 있어 두 비트만 옮기며, 실패하면 `baseFont`를 반환한다.
    static func fontPreservingBoldItalic(from originalFont: PlatformFont, applying baseFont: PlatformFont) -> PlatformFont {
        #if os(iOS)
        let mask: UIFontDescriptor.SymbolicTraits = [.traitBold, .traitItalic]
        let originalBoldItalic = originalFont.fontDescriptor.symbolicTraits.intersection(mask)
        guard !originalBoldItalic.isEmpty else { return baseFont }
        var newTraits = baseFont.fontDescriptor.symbolicTraits
        newTraits.formUnion(originalBoldItalic)
        guard let descriptor = baseFont.fontDescriptor.withSymbolicTraits(newTraits) else { return baseFont }
        return UIFont(descriptor: descriptor, size: baseFont.pointSize)
        #elseif os(macOS)
        let mask: NSFontDescriptor.SymbolicTraits = [.bold, .italic]
        let originalBoldItalic = originalFont.fontDescriptor.symbolicTraits.intersection(mask)
        guard !originalBoldItalic.isEmpty else { return baseFont }
        var newTraits = baseFont.fontDescriptor.symbolicTraits
        newTraits.formUnion(originalBoldItalic)
        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(newTraits)
        return NSFont(descriptor: descriptor, size: baseFont.pointSize) ?? baseFont
        #endif
    }
}

#if os(iOS)

// MARK: - iOS

/// 툴바가 "지금 포커스된 `UITextView`"에 문단 스타일/인라인 서식을 적용하기 위한 다리
/// (`RichTextEditingProxy`와 같은 역할).
@MainActor
final class SermonParagraphEditingProxy {
    weak var textView: UITextView?

    func toggleBold() { toggleTrait(.traitBold) }
    func toggleItalic() { toggleTrait(.traitItalic) }

    /// 커서가 있는 문단의 현재 스타일(툴바 드롭다운 표시용).
    func currentParagraphStyle() -> SermonParagraphStyle {
        guard let textView, let storage = textView.textStorage as NSTextStorage?, storage.length > 0 else { return .body }
        let location = min(textView.selectedRange.location, storage.length - 1)
        guard location >= 0 else { return .body }
        let raw = storage.attribute(.sermonParagraphStyle, at: location, effectiveRange: nil) as? String
        return raw.flatMap(SermonParagraphStyle.init(rawValue:)) ?? .body
    }

    /// 커서가 있는 문단 전체에 스타일을 적용한다(캐럿만 있어도 `paragraphRange(for:)`로 문단 전체).
    func applyParagraphStyle(_ style: SermonParagraphStyle, settings: UserSettingsStore) {
        guard let textView, let storage = textView.textStorage as NSTextStorage? else { return }
        let fullText = storage.string as NSString
        guard fullText.length > 0 else {
            // 빈 문서 — 다음 입력 글자에 적용되도록 타이핑 속성만 맞춘다.
            applyTypingAttributes(for: style, settings: settings, to: textView)
            return
        }
        let paragraphRange = fullText.paragraphRange(for: textView.selectedRange)
        storage.beginEditing()
        SermonParagraphStyleCodec.applyStyle(style, to: paragraphRange, in: storage, settings: settings)
        storage.endEditing()
        applyTypingAttributes(for: style, settings: settings, to: textView)
    }

    /// "말씀구절 + 추가" — 커서 문단 다음에 새 `.verseQuote` 문단을 만들어 구절 텍스트를 넣는다.
    /// 반환값은 새 문단의 0부터 시작하는 순번(`SermonVerseReference.paragraphIndex`용).
    @discardableResult
    func insertVerseQuoteParagraph(text: String, settings: UserSettingsStore) -> Int {
        guard let textView, let storage = textView.textStorage as NSTextStorage? else { return 0 }
        let fullText = storage.string as NSString

        var currentParagraphIndex = -1
        var currentParagraphRange = NSRange(location: 0, length: 0)
        if fullText.length > 0 {
            let selectionLocation = min(textView.selectedRange.location, fullText.length)
            var idx = 0
            fullText.enumerateSubstrings(in: NSRange(location: 0, length: fullText.length), options: .byParagraphs) { _, paragraphRange, _, _ in
                if paragraphRange.location <= selectionLocation {
                    currentParagraphIndex = idx
                    currentParagraphRange = paragraphRange
                }
                idx += 1
            }
        }

        let insertionPoint = currentParagraphRange.location + currentParagraphRange.length
        let needsLeadingNewline = insertionPoint > 0
        let insertedText = (needsLeadingNewline ? "\n" : "") + text + "\n"

        // 새로 삽입한 문단도 다시 열었을 때와 같은 모양이도록 `applyStyle`을 그대로 재사용한다.
        let leadingOffset = needsLeadingNewline ? 1 : 0
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: insertionPoint, length: 0), with: NSAttributedString(string: insertedText))
        let newParagraphRange = NSRange(location: insertionPoint + leadingOffset, length: (insertedText as NSString).length - leadingOffset)
        SermonParagraphStyleCodec.applyStyle(.verseQuote, to: newParagraphRange, in: storage, settings: settings)
        storage.endEditing()

        let newCursorLocation = insertionPoint + (insertedText as NSString).length
        textView.selectedRange = NSRange(location: newCursorLocation, length: 0)

        return currentParagraphIndex + 1
    }

    /// 글자 색상 적용. `hex`가 `nil`이면 현재 문단 스타일의 프리셋 색으로 되돌린다.
    /// 수동 지정 값이 다음에 열 때도 유지되는 것은 `applyStyle`이 저장된 스냅샷과 비교하기
    /// 때문이라 별도 마커는 필요 없다.
    func applyColor(_ hex: String?, settings: UserSettingsStore) {
        guard let textView else { return }
        let resolvedColor: UIColor
        if let hex, let color = Color(hex: hex) {
            resolvedColor = UIColor(color)
        } else {
            resolvedColor = settings.sermonPlatformFontColor(for: currentParagraphStyle())
        }
        apply(.foregroundColor, value: resolvedColor, on: textView)
    }

    /// `family`가 `nil`이면 현재 문단 스타일의 프리셋 글꼴로 되돌린다(크기는 유지).
    func applyFontFamily(_ family: String?, settings: UserSettingsStore) {
        guard let textView else { return }
        let range = textView.selectedRange
        func makeFont(basedOn font: UIFont) -> UIFont {
            let resolvedFamily = family ?? settings.sermonFontName(for: currentParagraphStyle())
            guard resolvedFamily != "System" else { return UIFont.systemFont(ofSize: font.pointSize) }
            BundledFontRegistrar.ensureAvailable(resolvedFamily)
            return UIFont(name: resolvedFamily, size: font.pointSize) ?? font
        }
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let font = (attrs[.font] as? UIFont) ?? UIFont.systemFont(ofSize: 15)
            attrs[.font] = makeFont(basedOn: font)
            textView.typingAttributes = attrs
            return
        }
        let storage = textView.textStorage
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? UIFont) ?? UIFont.systemFont(ofSize: 15)
            storage.addAttribute(.font, value: makeFont(basedOn: font), range: subrange)
        }
        storage.endEditing()
    }

    /// `size`가 `nil`이면 현재 문단 스타일의 프리셋 크기로 되돌린다(글꼴 유지).
    /// `UIFont.withSize(_:)`는 굵게/기울임 트레이트를 유지한다.
    func applyFontSize(_ size: CGFloat?, settings: UserSettingsStore) {
        guard let textView else { return }
        let range = textView.selectedRange
        func makeFont(basedOn font: UIFont) -> UIFont {
            let resolvedSize = size ?? CGFloat(settings.sermonFontSize(for: currentParagraphStyle()))
            return font.withSize(resolvedSize)
        }
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let font = (attrs[.font] as? UIFont) ?? UIFont.systemFont(ofSize: 15)
            attrs[.font] = makeFont(basedOn: font)
            textView.typingAttributes = attrs
            return
        }
        let storage = textView.textStorage
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? UIFont) ?? UIFont.systemFont(ofSize: 15)
            storage.addAttribute(.font, value: makeFont(basedOn: font), range: subrange)
        }
        storage.endEditing()
    }

    /// 정렬은 프리셋이 값을 지정하지 않으므로(`.natural`) 되돌리기도 `applyAlignment(.natural)`이면 된다.
    /// 문단 단위 속성이라 캐럿만 있어도 그 문단 전체에 적용한다.
    func applyAlignment(_ alignment: PlatformTextAlignment) {
        guard let textView else { return }
        func makeParagraphStyle(basedOn existing: NSParagraphStyle?) -> NSMutableParagraphStyle {
            let style = (existing?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            style.alignment = alignment
            return style
        }
        let range = textView.selectedRange
        if range.length == 0 && (textView.text as NSString).length == 0 {
            var attrs = textView.typingAttributes
            attrs[.paragraphStyle] = makeParagraphStyle(basedOn: attrs[.paragraphStyle] as? NSParagraphStyle)
            textView.typingAttributes = attrs
            return
        }
        let storage = textView.textStorage
        let fullText = storage.string as NSString
        let paragraphRange = fullText.paragraphRange(for: range)
        storage.beginEditing()
        storage.enumerateAttribute(.paragraphStyle, in: paragraphRange, options: []) { value, subrange, _ in
            storage.addAttribute(.paragraphStyle, value: makeParagraphStyle(basedOn: value as? NSParagraphStyle), range: subrange)
        }
        storage.endEditing()
        var attrs = textView.typingAttributes
        attrs[.paragraphStyle] = makeParagraphStyle(basedOn: attrs[.paragraphStyle] as? NSParagraphStyle)
        textView.typingAttributes = attrs
    }

    private func applyTypingAttributes(for style: SermonParagraphStyle, settings: UserSettingsStore, to textView: UITextView) {
        let baseFont = settings.sermonPlatformFont(for: style)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = baseFont.typographicLineHeight * max(0, settings.sermonLineHeightMultiple(for: style) - 1)
        var attrs = textView.typingAttributes
        attrs[.font] = baseFont
        attrs[.paragraphStyle] = paragraphStyle
        attrs[.sermonParagraphStyle] = style.rawValue
        textView.typingAttributes = attrs
    }

    private func toggleTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
        guard let textView else { return }
        let range = textView.selectedRange
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let font = (attrs[.font] as? UIFont) ?? UIFont.systemFont(ofSize: 15)
            attrs[.font] = font.togglingSermonTrait(trait)
            textView.typingAttributes = attrs
            return
        }
        let storage = textView.textStorage
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? UIFont) ?? UIFont.systemFont(ofSize: 15)
            storage.addAttribute(.font, value: font.togglingSermonTrait(trait), range: subrange)
        }
        storage.endEditing()
    }

    /// `applyColor`가 쓰는 공통 헬퍼 — 캐럿만 있으면 타이핑 속성, 선택 범위가 있으면 그 범위에 적용한다.
    private func apply(_ key: NSAttributedString.Key, value: Any, on textView: UITextView) {
        let range = textView.selectedRange
        if range.length == 0 {
            var attrs = textView.typingAttributes
            attrs[key] = value
            textView.typingAttributes = attrs
            return
        }
        let storage = textView.textStorage
        storage.beginEditing()
        storage.addAttribute(key, value: value, range: range)
        storage.endEditing()
    }
}

private extension UIFont {
    /// `RichTextEditor.swift`의 `UIFont.togglingTrait(_:)`와 같은 로직(이름 충돌 방지용으로 이름만 다름).
    func togglingSermonTrait(_ trait: UIFontDescriptor.SymbolicTraits) -> UIFont {
        var traits = fontDescriptor.symbolicTraits
        if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

struct SermonParagraphEditorRepresentable: UIViewRepresentable {
    @Binding var rtfText: String
    @Binding var plainText: String
    @Binding var paragraphStyles: String
    /// 마지막 저장 시점의 프리셋 스냅샷(읽기 전용 기준선) — `@Binding`이 아니라 일반 값이며,
    /// 쓰기는 `SermonEditorView.save()`가 담당한다.
    var styleFontSnapshot: String
    var isEditable: Bool
    var proxy: SermonParagraphEditingProxy
    var settings: UserSettingsStore
    var editingBackgroundColor: UIColor? = nil
    var readOnlyBackgroundColor: UIColor? = nil

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        // 편집 배경이 뷰어와 같은 고정 미색이므로 캐럿·선택·메뉴도 라이트 외형으로 고정한다(`SermonViewerPaper`).
        if isEditable { textView.overrideUserInterfaceStyle = .light }
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.textStorage.delegate = context.coordinator
        textView.allowsEditingTextAttributes = isEditable
        context.coordinator.textView = textView
        proxy.textView = textView
        loadContent(into: textView, coordinator: context.coordinator)
        applyBackground(to: textView)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        uiView.isEditable = isEditable
        uiView.allowsEditingTextAttributes = isEditable
        proxy.textView = uiView
        applyBackground(to: uiView)
        guard rtfText != context.coordinator.lastExportedRTF else { return }
        loadContent(into: uiView, coordinator: context.coordinator)
    }

    /// 텍스트뷰가 화면 전환으로 버려질 때, 윈도우 공유 undo 관리자에 남은 액션이 이미 사라진
    /// 텍스트뷰를 참조해 Cmd+Z에서 크래시하는 것을 막는다(`RichTextEditor.dismantleUIView`와 동일).
    static func dismantleUIView(_ uiView: UITextView, coordinator: Coordinator) {
        uiView.undoManager?.removeAllActions(withTarget: uiView)
    }

    private func loadContent(into textView: UITextView, coordinator: Coordinator) {
        coordinator.isLoadingExternally = true
        let defaultAttributes: [NSAttributedString.Key: Any] = [.font: settings.sermonPlatformFont(for: .body)]
        let attributed = RichTextCodec.decode(rtfText, defaultAttributes: defaultAttributes)
        // `apply`는 `NSTextStorage`가 필요하므로(`beginEditing()` 사용), 디코딩한 내용을 먼저
        // 텍스트뷰의 `textStorage`에 넣고 그 위에 바로 스타일을 적용한다.
        textView.textStorage.setAttributedString(attributed)
        SermonParagraphStyleCodec.apply(paragraphStyles, to: textView.textStorage, settings: settings, previousSnapshot: styleFontSnapshot)
        applyBodyTypingAttributesIfEmpty(to: textView)
        coordinator.isLoadingExternally = false
        coordinator.lastExportedRTF = rtfText
    }

    /// 완전히 빈 문서는 `apply`가 순회할 문단이 없어 아무 일도 하지 않으므로, 빈 문서일 때만
    /// "본문" 스타일을 타이핑 속성에 직접 심어 툴바 표시(본문)와 실제 서식을 맞춘다.
    /// `applyTypingAttributes`(private)와 같은 계산이나 간단해 중복을 감수했다.
    private func applyBodyTypingAttributesIfEmpty(to textView: UITextView) {
        guard textView.textStorage.length == 0 else { return }
        let baseFont = settings.sermonPlatformFont(for: .body)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = baseFont.typographicLineHeight * max(0, settings.sermonLineHeightMultiple(for: .body) - 1)
        textView.typingAttributes = [
            .font: baseFont,
            .paragraphStyle: paragraphStyle,
            .sermonParagraphStyle: SermonParagraphStyle.body.rawValue
        ]
    }

    private func applyBackground(to textView: UITextView) {
        let color = isEditable ? editingBackgroundColor : readOnlyBackgroundColor
        textView.backgroundColor = color ?? .clear
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextStorageDelegate {
        var parent: SermonParagraphEditorRepresentable
        var lastExportedRTF: String = ""
        var isProcessing = false
        var isLoadingExternally = false
        weak var textView: UITextView?

        init(_ parent: SermonParagraphEditorRepresentable) { self.parent = parent }

        func textStorage(
            _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorage.EditActions,
            range editedRange: NSRange, changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters) || editedMask.contains(.editedAttributes) else { return }
            guard !isProcessing, !isLoadingExternally else { return }
            isProcessing = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let (rtf, plain) = RichTextCodec.encode(textStorage)
                let styles = SermonParagraphStyleCodec.export(from: textStorage)
                self.lastExportedRTF = rtf
                self.parent.rtfText = rtf
                self.parent.plainText = plain
                self.parent.paragraphStyles = styles
                self.isProcessing = false
            }
        }
    }
}

#elseif os(macOS)

// MARK: - macOS

@MainActor
final class SermonParagraphEditingProxy {
    weak var textView: NSTextView?

    func toggleBold() { toggleTrait(.bold) }
    func toggleItalic() { toggleTrait(.italic) }

    func currentParagraphStyle() -> SermonParagraphStyle {
        guard let textView, let storage = textView.textStorage, storage.length > 0 else { return .body }
        let location = min(textView.selectedRange().location, storage.length - 1)
        guard location >= 0 else { return .body }
        let raw = storage.attribute(.sermonParagraphStyle, at: location, effectiveRange: nil) as? String
        return raw.flatMap(SermonParagraphStyle.init(rawValue:)) ?? .body
    }

    func applyParagraphStyle(_ style: SermonParagraphStyle, settings: UserSettingsStore) {
        guard let textView, let storage = textView.textStorage else { return }
        let fullText = storage.string as NSString
        guard fullText.length > 0 else {
            applyTypingAttributes(for: style, settings: settings, to: textView)
            return
        }
        let paragraphRange = fullText.paragraphRange(for: textView.selectedRange())
        storage.beginEditing()
        SermonParagraphStyleCodec.applyStyle(style, to: paragraphRange, in: storage, settings: settings)
        storage.endEditing()
        applyTypingAttributes(for: style, settings: settings, to: textView)
    }

    @discardableResult
    func insertVerseQuoteParagraph(text: String, settings: UserSettingsStore) -> Int {
        guard let textView, let storage = textView.textStorage else { return 0 }
        let fullText = storage.string as NSString

        var currentParagraphIndex = -1
        var currentParagraphRange = NSRange(location: 0, length: 0)
        if fullText.length > 0 {
            let selectionLocation = min(textView.selectedRange().location, fullText.length)
            var idx = 0
            fullText.enumerateSubstrings(in: NSRange(location: 0, length: fullText.length), options: .byParagraphs) { _, paragraphRange, _, _ in
                if paragraphRange.location <= selectionLocation {
                    currentParagraphIndex = idx
                    currentParagraphRange = paragraphRange
                }
                idx += 1
            }
        }

        let insertionPoint = currentParagraphRange.location + currentParagraphRange.length
        let needsLeadingNewline = insertionPoint > 0
        let insertedText = (needsLeadingNewline ? "\n" : "") + text + "\n"

        // iOS 구현과 같은 이유로 `applyStyle`을 재사용한다.
        let leadingOffset = needsLeadingNewline ? 1 : 0
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: insertionPoint, length: 0), with: NSAttributedString(string: insertedText))
        let newParagraphRange = NSRange(location: insertionPoint + leadingOffset, length: (insertedText as NSString).length - leadingOffset)
        SermonParagraphStyleCodec.applyStyle(.verseQuote, to: newParagraphRange, in: storage, settings: settings)
        storage.endEditing()

        let newCursorLocation = insertionPoint + (insertedText as NSString).length
        textView.setSelectedRange(NSRange(location: newCursorLocation, length: 0))

        return currentParagraphIndex + 1
    }

    private func applyTypingAttributes(for style: SermonParagraphStyle, settings: UserSettingsStore, to textView: NSTextView) {
        let baseFont = settings.sermonPlatformFont(for: style)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = baseFont.typographicLineHeight * max(0, settings.sermonLineHeightMultiple(for: style) - 1)
        var attrs = textView.typingAttributes
        attrs[.font] = baseFont
        attrs[.paragraphStyle] = paragraphStyle
        attrs[.sermonParagraphStyle] = style.rawValue
        textView.typingAttributes = attrs
    }

    /// iOS `applyColor(_:settings:)`와 같은 구조.
    func applyColor(_ hex: String?, settings: UserSettingsStore) {
        guard let textView else { return }
        let resolvedColor: NSColor
        if let hex, let color = Color(hex: hex) {
            resolvedColor = NSColor(color)
        } else {
            resolvedColor = settings.sermonPlatformFontColor(for: currentParagraphStyle())
        }
        apply(.foregroundColor, value: resolvedColor, on: textView)
    }

    func applyFontFamily(_ family: String?, settings: UserSettingsStore) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        func makeFont(basedOn font: NSFont) -> NSFont {
            let resolvedFamily = family ?? settings.sermonFontName(for: currentParagraphStyle())
            guard resolvedFamily != "System" else { return NSFont.systemFont(ofSize: font.pointSize) }
            BundledFontRegistrar.ensureAvailable(resolvedFamily)
            return NSFont(name: resolvedFamily, size: font.pointSize) ?? font
        }
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let font = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 15)
            attrs[.font] = makeFont(basedOn: font)
            textView.typingAttributes = attrs
            return
        }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: 15)
            storage.addAttribute(.font, value: makeFont(basedOn: font), range: subrange)
        }
        storage.endEditing()
    }

    /// AppKit의 `NSFont`엔 `withSize(_:)`가 없어 `NSFont(descriptor:size:)`로 새 인스턴스를 만든다.
    func applyFontSize(_ size: CGFloat?, settings: UserSettingsStore) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        func makeFont(basedOn font: NSFont) -> NSFont {
            let resolvedSize = size ?? CGFloat(settings.sermonFontSize(for: currentParagraphStyle()))
            return NSFont(descriptor: font.fontDescriptor, size: resolvedSize) ?? font
        }
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let font = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 15)
            attrs[.font] = makeFont(basedOn: font)
            textView.typingAttributes = attrs
            return
        }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: 15)
            storage.addAttribute(.font, value: makeFont(basedOn: font), range: subrange)
        }
        storage.endEditing()
    }

    /// `RichTextEditor`의 macOS `applyAlignment(_:)`와 같은 구조 — `NSTextView`는
    /// `textStorage.length`로 빈 문서를 판정한다.
    func applyAlignment(_ alignment: PlatformTextAlignment) {
        guard let textView, let storage = textView.textStorage else { return }
        func makeParagraphStyle(basedOn existing: NSParagraphStyle?) -> NSMutableParagraphStyle {
            let style = (existing?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            style.alignment = alignment
            return style
        }
        let range = textView.selectedRange()
        if storage.length == 0 {
            var attrs = textView.typingAttributes
            attrs[.paragraphStyle] = makeParagraphStyle(basedOn: attrs[.paragraphStyle] as? NSParagraphStyle)
            textView.typingAttributes = attrs
            return
        }
        let fullText = storage.string as NSString
        let paragraphRange = fullText.paragraphRange(for: range)
        storage.beginEditing()
        storage.enumerateAttribute(.paragraphStyle, in: paragraphRange, options: []) { value, subrange, _ in
            storage.addAttribute(.paragraphStyle, value: makeParagraphStyle(basedOn: value as? NSParagraphStyle), range: subrange)
        }
        storage.endEditing()
        var attrs = textView.typingAttributes
        attrs[.paragraphStyle] = makeParagraphStyle(basedOn: attrs[.paragraphStyle] as? NSParagraphStyle)
        textView.typingAttributes = attrs
    }

    private func toggleTrait(_ trait: NSFontDescriptor.SymbolicTraits) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let font = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 15)
            attrs[.font] = font.togglingSermonTrait(trait)
            textView.typingAttributes = attrs
            return
        }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: 15)
            storage.addAttribute(.font, value: font.togglingSermonTrait(trait), range: subrange)
        }
        storage.endEditing()
    }

    /// iOS `apply(_:value:on:)`와 같은 이유·같은 구조.
    private func apply(_ key: NSAttributedString.Key, value: Any, on textView: NSTextView) {
        let range = textView.selectedRange()
        if range.length == 0 {
            var attrs = textView.typingAttributes
            attrs[key] = value
            textView.typingAttributes = attrs
            return
        }
        guard let storage = textView.textStorage else { return }
        storage.beginEditing()
        storage.addAttribute(key, value: value, range: range)
        storage.endEditing()
    }
}

private extension NSFont {
    /// `RichTextEditor.swift`의 `NSFont.togglingTrait(_:)`와 같은 로직(이름 충돌 방지를 위해 이름만 다르다).
    func togglingSermonTrait(_ trait: NSFontDescriptor.SymbolicTraits) -> NSFont {
        var traits = fontDescriptor.symbolicTraits
        if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
        let descriptor = fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}

struct SermonParagraphEditorRepresentable: NSViewRepresentable {
    @Binding var rtfText: String
    @Binding var plainText: String
    @Binding var paragraphStyles: String
    /// iOS 쪽 `styleFontSnapshot`과 같은 역할(그 프로퍼티 주석 참고).
    var styleFontSnapshot: String
    var isEditable: Bool
    var proxy: SermonParagraphEditingProxy
    var settings: UserSettingsStore
    var editingBackgroundColor: NSColor? = nil
    var readOnlyBackgroundColor: NSColor? = nil

    func makeNSView(context: Context) -> NSScrollView {
        // `RichTextEditor`(말씀 요약/메모/개요)와 같은 방식으로 `scrollableTextView()`를 쓴다. 폭 추적·세로 리사이즈가 이미 맞게 설정된
        // 텍스트뷰라, 네이티브 서식 팝업(`usesInspectorBar`)이 올바른 위치/폭 기준으로 뜬다.
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textStorage?.delegate = context.coordinator
        textView.allowsUndo = true
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        // 편집 배경이 뷰어와 같은 고정 미색이므로 캐럿·선택색도 라이트 외형으로 고정한다(`SermonViewerPaper`).
        if isEditable { scrollView.appearance = NSAppearance(named: .aqua) }

        context.coordinator.textView = textView
        proxy.textView = textView
        loadContent(into: textView, coordinator: context.coordinator)
        applyBackground(to: textView)
        applyStyleToolsVisibility(to: textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        textView.isEditable = isEditable
        proxy.textView = textView
        applyBackground(to: textView)
        applyStyleToolsVisibility(to: textView)
        guard rtfText != context.coordinator.lastExportedRTF else { return }
        loadContent(into: textView, coordinator: context.coordinator)
    }

    /// 문서 전환 시 공유 undo 관리자에 죽은 텍스트뷰 참조가 남아 크래시하는 문제를
    /// 막는다(`RichTextEditor.swift`와 같은 방어).
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        (nsView.documentView as? NSTextView)?.undoManager?.removeAllActions(withTarget: nsView.documentView as Any)
    }

    private func loadContent(into textView: NSTextView, coordinator: Coordinator) {
        coordinator.isLoadingExternally = true
        // macOS의 `NSTextView.textStorage`는 Optional이라 guard로 먼저 꺼내 둔다.
        guard let textStorage = textView.textStorage else {
            coordinator.isLoadingExternally = false
            return
        }
        let defaultAttributes: [NSAttributedString.Key: Any] = [.font: settings.sermonPlatformFont(for: .body)]
        let attributed = RichTextCodec.decode(rtfText, defaultAttributes: defaultAttributes)
        textStorage.setAttributedString(attributed)
        SermonParagraphStyleCodec.apply(paragraphStyles, to: textStorage, settings: settings, previousSnapshot: styleFontSnapshot)
        applyBodyTypingAttributesIfEmpty(to: textView, textStorage: textStorage)
        coordinator.isLoadingExternally = false
        coordinator.lastExportedRTF = rtfText
    }

    /// iOS 쪽과 같은 계산 — macOS는 `textStorage`가 Optional이라 이미 꺼낸 값을 받는다.
    private func applyBodyTypingAttributesIfEmpty(to textView: NSTextView, textStorage: NSTextStorage) {
        guard textStorage.length == 0 else { return }
        let baseFont = settings.sermonPlatformFont(for: .body)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = baseFont.typographicLineHeight * max(0, settings.sermonLineHeightMultiple(for: .body) - 1)
        textView.typingAttributes = [
            .font: baseFont,
            .paragraphStyle: paragraphStyle,
            .sermonParagraphStyle: SermonParagraphStyle.body.rawValue
        ]
    }

    /// 말씀 요약 에디터(`RichTextEditor`, `showsToolbarOnMac == false`)와 같은 macOS 네이티브 서식 도구를 편집 가능할 때만 켠다:
    /// 서식 팝업(`usesInspectorBar` — 굵게/기울임/밑줄/글꼴/크기/글자색/정렬/목록), 글꼴 패널(⌘T), 눈금자.
    /// 여기서 바꾼 글꼴·색·정렬은 글자 단위 서식으로 남고, 문단 스타일의 프리셋 재적용 때 "수동 지정"으로 보존된다
    /// (`SermonParagraphStyleCodec.applyStyle`의 스냅샷 비교).
    private func applyStyleToolsVisibility(to textView: NSTextView) {
        textView.usesInspectorBar = isEditable
        textView.usesFontPanel = isEditable
        textView.usesRuler = isEditable
    }

    private func applyBackground(to textView: NSTextView) {
        let color = isEditable ? editingBackgroundColor : readOnlyBackgroundColor
        textView.backgroundColor = color ?? .clear
        textView.drawsBackground = color != nil
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextStorageDelegate {
        var parent: SermonParagraphEditorRepresentable
        var lastExportedRTF: String = ""
        var isProcessing = false
        var isLoadingExternally = false
        weak var textView: NSTextView?

        init(_ parent: SermonParagraphEditorRepresentable) { self.parent = parent }

        // macOS `NSTextStorageDelegate`는 iOS와 달리 중첩 타입이 아니라 전역 typealias
        // `NSTextStorageEditActions`를 쓴다(`RichTextEditor.swift`와 같은 이유).
        func textStorage(
            _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange, changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters) || editedMask.contains(.editedAttributes) else { return }
            guard !isProcessing, !isLoadingExternally else { return }
            isProcessing = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let (rtf, plain) = RichTextCodec.encode(textStorage)
                let styles = SermonParagraphStyleCodec.export(from: textStorage)
                self.lastExportedRTF = rtf
                self.parent.rtfText = rtf
                self.parent.plainText = plain
                self.parent.paragraphStyles = styles
                self.isProcessing = false
            }
        }
    }
}

#endif

// MARK: - 공개 View

/// 문단 프리셋 스타일을 지원하는 설교 작성 에디터 — 텍스트뷰만 감싼다(툴바는
/// `SermonEditorView`가 화면 상단에 구성). 스타일 드롭다운/B/I 토글/"말씀구절 + 추가"는
/// `SermonParagraphEditingProxy`를 통해 이 에디터를 조작한다.
struct SermonParagraphEditor: View {
    @Binding var contentHtml: String
    @Binding var contentText: String
    @Binding var paragraphStyles: String
    /// 호출부(`SermonEditorView`)가 `subject.styleFontSnapshot`을 그대로 넘긴다.
    var styleFontSnapshot: String
    var isEditable: Bool
    var proxy: SermonParagraphEditingProxy

    var body: some View {
        let settings = UserSettingsStore.shared
        #if os(iOS)
        SermonParagraphEditorRepresentable(
            rtfText: $contentHtml,
            plainText: $contentText,
            paragraphStyles: $paragraphStyles,
            styleFontSnapshot: styleFontSnapshot,
            isEditable: isEditable,
            proxy: proxy,
            settings: settings,
            editingBackgroundColor: SermonViewerPaper.platformColor,
            readOnlyBackgroundColor: nil
        )
        #elseif os(macOS)
        SermonParagraphEditorRepresentable(
            rtfText: $contentHtml,
            plainText: $contentText,
            paragraphStyles: $paragraphStyles,
            styleFontSnapshot: styleFontSnapshot,
            isEditable: isEditable,
            proxy: proxy,
            settings: settings,
            editingBackgroundColor: SermonViewerPaper.platformColor,
            readOnlyBackgroundColor: nil
        )
        #endif
    }
}
