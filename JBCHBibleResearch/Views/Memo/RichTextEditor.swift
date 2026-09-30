//
//  RichTextEditor.swift
//  JBCHBibleResearch
//
//  메모/개요/말씀 요약이 공유하는 메모장식 리치 텍스트 에디터. 문단 블록 없이 하나의 전체 텍스트에서
//  "선택한 부분"에만 서식(굵게/기울임/밑줄/글자색/글꼴/크기/정렬)을 적용한다.
//  - 저장: `contentHtml` 필드명은 스키마/CloudKit 마이그레이션을 피하려고 그대로 두었고, 실제로는 RTF 문자열이
//    들어간다(`RichTextCodec`). `{\rtf1`로 시작하지 않는 레거시 HTML은 일반 텍스트로 보이며 자동 마이그레이션은
//    없다. 검색/미리보기/임베딩용 `contentText` 계약은 그대로다.
//  - 편집기는 서식 문자열과 순수 텍스트를 함께 내보내며, `didProcessEditing`에서 매 변경마다 재계산한다.
//    부모가 방금 내보낸 값을 되돌려 주면 다시 그리지 않는다(`lastExportedText` 가드, 무한 루프 방지).
//  - iOS(UIViewRepresentable)와 macOS(NSViewRepresentable)를 같은 타입 이름으로 나란히 선언한다.
//  - "줄 간격 1.5"는 전체 줄 높이의 배수로 해석해 `lineSpacing = 한 줄 높이 × (배수 - 1)`로 환산한다.
//

import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - 저장 문자열(RTF) ↔ NSAttributedString 왕복 변환

/// `*.contentHtml` 필드(실제로는 RTF)와 `NSAttributedString` 사이의 변환 모음. 에디터 내부와 프로그램적
/// 텍스트 삽입(`OutlineView`의 "AI 초안 적용")이 같은 규칙을 쓰도록 공유한다.
enum RichTextCodec {
    /// 저장된 문자열을 읽는다. `{\rtf1`로 시작하면 RTF로 디코딩하고, 아니면(빈 문자열/레거시 HTML) 순수 텍스트로
    /// 보고 `defaultAttributes`를 입힌다. 빈 문서에서도 캐럿 높이가 편집모드 기본 서식과 맞도록 폰트뿐 아니라
    /// 문단 스타일(줄간격)까지 받는다.
    static func decode(_ stored: String, defaultAttributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        if stored.hasPrefix("{\\rtf1"), let data = stored.data(using: .utf8) {
            #if os(iOS)
            if let attrString = try? NSAttributedString(
                data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil
            ) {
                return attrString
            }
            #elseif os(macOS)
            if let attrString = NSAttributedString(rtf: data, documentAttributes: nil) {
                return attrString
            }
            #endif
        }
        return NSAttributedString(string: stored, attributes: defaultAttributes)
    }

    /// 서식 있는 문자열을 RTF로, 그리고 그 안의 순수 텍스트를 함께 돌려준다.
    /// RTF 인코딩이 실패하면(이론상 거의 없지만) 순수 텍스트를 두 값 모두에 쓴다
    /// — 서식은 잃어도 최소한 내용은 잃지 않는다.
    static func encode(_ attributed: NSAttributedString) -> (rtf: String, plainText: String) {
        let plainText = attributed.string
        let fullRange = NSRange(location: 0, length: attributed.length)
        #if os(iOS)
        if let data = try? attributed.data(from: fullRange, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]),
           let rtfString = String(data: data, encoding: .utf8) {
            return (rtfString, plainText)
        }
        #elseif os(macOS)
        if let data = attributed.rtf(from: fullRange, documentAttributes: [:]),
           let rtfString = String(data: data, encoding: .utf8) {
            return (rtfString, plainText)
        }
        #endif
        return (plainText, plainText)
    }

    /// 저장된 서식은 유지한 채 각 글자의 크기에만 `factor`를 곱한다(원본 안의 상대적 크기 차이가 보존된다).
    /// `factor == 1.0`이면 복사 없이 그대로 돌려준다.
    static func scalingFontSize(_ attributed: NSAttributedString, by factor: CGFloat) -> NSAttributedString {
        guard attributed.length > 0, factor != 1.0 else { return attributed }
        let mutable = NSMutableAttributedString(attributedString: attributed)
        let fullRange = NSRange(location: 0, length: mutable.length)
        mutable.enumerateAttribute(.font, in: fullRange, options: []) { value, subrange, _ in
            let font = (value as? PlatformFont) ?? EditorDefaultStyle.typingFont
            let newSize = max(1, font.pointSize * factor)
            #if os(iOS)
            let resized = font.withSize(newSize)
            #elseif os(macOS)
            let resized = NSFont(descriptor: font.fontDescriptor, size: newSize) ?? font
            #endif
            mutable.addAttribute(.font, value: resized, range: subrange)
        }
        return mutable
    }
}

// MARK: - 줄 높이 계산 (플랫폼 차이 흡수)

extension PlatformFont {
    /// 줄 간격 배수를 포인트로 환산하려면 한 줄 기본 높이가 필요하다. iOS `UIFont`는 `.lineHeight`를 제공하지만
    /// macOS `NSFont`에는 공개 프로퍼티가 없어 `ascender - descender + leading`으로 직접 구한다.
    var typographicLineHeight: CGFloat {
        #if os(iOS)
        return lineHeight
        #elseif os(macOS)
        return ascender - descender + leading
        #endif
    }
}

extension PlatformColor {
    /// iOS `.systemBackground`와 macOS `.textBackgroundColor`를 한 이름으로 묶는다(둘 다 동적 색상이라
    /// 다크 모드 대응이 따로 필요 없다).
    static var systemContentBackground: PlatformColor {
        #if os(iOS)
        return .systemBackground
        #elseif os(macOS)
        return .textBackgroundColor
        #endif
    }
}

// MARK: - 공개 View

/// 메모/책 개요/장 개요/메모 팝업이 공유하는 리치 텍스트 에디터. 저장 문자열(RTF)과 순수 텍스트 바인딩만
/// 넘기면 되고 중간 상태는 내부에서 처리한다.
struct RichTextEditor: View {
    @Binding var rtfText: String
    @Binding var plainText: String
    var isEditable: Bool
    var placeholder: String = "내용을 입력하세요"

    /// 새로 입력하는 글자의 기본 폰트. 이미 서식이 있는 기존 내용은 바꾸지 않는다.
    var typingFont: PlatformFont = .systemFont(ofSize: 15)
    /// 새로 입력하는 글자의 기본 글자색(기존 서식은 유지). nil이면 시스템 라벨 색.
    var defaultTextColor: PlatformColor? = nil
    /// 1.0이면 추가 줄간격 없음. 그 이상은 `NSParagraphStyle.lineSpacing`으로 환산한다(`typographicLineHeight`).
    var lineHeightMultiple: CGFloat = 1.0
    /// nil이면 기본 배경(투명/시스템 기본 텍스트뷰 배경)을 유지한다.
    var editingBackgroundColor: PlatformColor? = nil
    var readOnlyBackgroundColor: PlatformColor? = nil
    /// `false`로 두면 내부 툴바를 끄고, 호출부가 `RichTextEditorToolbar`를 원하는 위치에 직접 그린다.
    var showsToolbar: Bool = true
    /// macOS에서도 상시 노출 커스텀 툴바를 켠다. 기본 `false`는 선택 시에만 잠깐 뜨는 네이티브 서식 팝업
    /// (`usesInspectorBar`)을 그대로 쓴다.
    var showsToolbarOnMac: Bool = false
    /// 외부에서 그리는 `RichTextEditorToolbar`가 이 안의 텍스트뷰에 서식을 적용하려면 같은 프록시를 공유해야
    /// 한다. nil이면 내부에서 만든 프록시를 쓴다.
    var externalProxy: RichTextEditingProxy? = nil

    @State private var internalProxy = RichTextEditingProxy()
    private var proxy: RichTextEditingProxy { externalProxy ?? internalProxy }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            #if os(iOS)
            if isEditable && showsToolbar {
                toolbar
                Divider()
            }
            #elseif os(macOS)
            if isEditable && showsToolbar && showsToolbarOnMac {
                toolbar
                Divider()
            }
            #endif

            RichTextEditorRepresentable(
                rtfText: $rtfText, plainText: $plainText, isEditable: isEditable, proxy: proxy,
                typingFont: typingFont, defaultTextColor: defaultTextColor, lineHeightMultiple: lineHeightMultiple,
                editingBackgroundColor: editingBackgroundColor, readOnlyBackgroundColor: readOnlyBackgroundColor,
                // macOS 네이티브 서식 팝업을 끄고 커스텀 툴바만 남기려면 실제 텍스트뷰까지 전달해야 한다.
                showsToolbarOnMac: showsToolbarOnMac
            )
            .frame(minHeight: 220)
            .overlay(alignment: .topLeading) {
                // 플레이스홀더 — 텍스트뷰 안쪽 여백에 맞춘 근사치 패딩이라 픽셀 단위로 정확히 겹치지는 않는다.
                if isEditable && plainText.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var toolbar: some View {
        RichTextEditorToolbarContent(proxy: proxy)
    }
}

/// `RichTextEditor`의 내부 툴바를 호출부가 바깥에서 독립적으로 그릴 수 있게 공개한다. 같은 `proxy`
/// 인스턴스를 넘겨야 버튼이 실제 텍스트뷰에 작용한다(`RichTextEditor.showsToolbar`/`externalProxy`).
/// iOS/macOS 양쪽 `RichTextEditingProxy`가 같은 시그니처를 가져 이 뷰에는 플랫폼 분기가 없다.
struct RichTextEditorToolbar: View {
    var proxy: RichTextEditingProxy
    var body: some View { RichTextEditorToolbarContent(proxy: proxy) }
}

/// 툴바 범위는 글꼴/크기/문단 정렬(왼쪽·가운데·오른쪽)까지다. 글머리 기호/인용/제목 스타일은 없다.
private let systemToolbarFontNames = ["Georgia", "Helvetica", "Courier New", "Avenir Next", "Times New Roman"]
private let toolbarFontSizes: [CGFloat] = [12, 13, 14, 15, 17, 19, 22, 26, 32]

private struct RichTextEditorToolbarContent: View {
    var proxy: RichTextEditingProxy
    /// 툴바 아이콘 색을 테마 설정(`bibleTextColor`)에 맞추는 데 쓴다.
    private var settings: UserSettingsStore { .shared }

    var body: some View {
        HStack(spacing: 14) {
            Button { proxy.toggleBold() } label: { Image(systemName: "bold") }
            Button { proxy.toggleItalic() } label: { Image(systemName: "italic") }
            Button { proxy.toggleUnderline() } label: { Image(systemName: "underline") }

            Divider().frame(height: 16)

            Menu {
                Button("기본색") { proxy.applyColor(nil) }
                ForEach(Color.memoTextPalette, id: \.hex) { swatch in
                    Button(swatch.name) { proxy.applyColor(swatch.hex) }
                }
            } label: {
                Image(systemName: "paintpalette")
            }

            // 글꼴 메뉴 — `applyFontFamily`는 family가 아니라 PostScript 이름을 받으므로 `entry.postScriptName`을 넘긴다
            // (`BundledFontRegistrar.swift` 참고). Paperlogy/고운바탕은 각각 별도 서브메뉴, 조선궁서체는 단일 글꼴이라 Button 하나.
            Menu {
                Button("기본 폰트") { proxy.applyFontFamily(nil) }
                Divider()
                Menu("Paperlogy") {
                    ForEach(BundledFonts.paperlogyEntries) { entry in
                        Button(entry.displayName) { proxy.applyFontFamily(entry.postScriptName) }
                    }
                }
                Menu("고운바탕") {
                    ForEach(BundledFonts.gowunBatangEntries) { entry in
                        Button(entry.displayName) { proxy.applyFontFamily(entry.postScriptName) }
                    }
                }
                Button("조선궁서체") { proxy.applyFontFamily(SpecialPurposeFonts.hanja) }
                Divider()
                ForEach(systemToolbarFontNames, id: \.self) { name in
                    Button(name) { proxy.applyFontFamily(name) }
                }
            } label: {
                Image(systemName: "textformat")
            }

            // 글꼴 크기 — 좁은 iPhone 화면의 상시 툴바에서도 탭 한 번으로 끝나도록 자유 입력 대신 Menu로 뒀다.
            Menu {
                ForEach(toolbarFontSizes, id: \.self) { size in
                    Button("\(Int(size))pt") { proxy.applyFontSize(size) }
                }
            } label: {
                Image(systemName: "textformat.size")
            }

            Divider().frame(height: 16)

            Button { proxy.applyAlignment(.left) } label: { Image(systemName: "text.alignleft") }
            Button { proxy.applyAlignment(.center) } label: { Image(systemName: "text.aligncenter") }
            Button { proxy.applyAlignment(.right) } label: { Image(systemName: "text.alignright") }

            Spacer()
        }
        .buttonStyle(.plain)
        .font(.system(size: 15))
        // 아이콘이 모두 `Image(systemName:)` + `.buttonStyle(.plain)`이라 컨테이너에서 한 번에 색을 물려준다.
        .foregroundStyle(settings.bibleTextColor ?? .primary)
        .padding(.vertical, 6)
    }
}

// MARK: - iOS

#if os(iOS)

/// iOS 툴바가 "지금 포커스된 `UITextView`의 선택 영역"에 서식을 적용하기 위한 다리. `makeUIView`가 인스턴스를
/// 만들면서 등록한다. 커서 위치별 굵게 상태를 추적해 버튼에 반영하지는 않는다(토글만 동작).
@MainActor
final class RichTextEditingProxy {
    weak var textView: UITextView?

    func toggleBold() { toggleTrait(.traitBold) }
    func toggleItalic() { toggleTrait(.traitItalic) }

    func toggleUnderline() {
        guard let textView else { return }
        let range = textView.selectedRange
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let isUnderlined = ((attrs[.underlineStyle] as? Int) ?? 0) != 0
            attrs[.underlineStyle] = isUnderlined ? 0 : NSUnderlineStyle.single.rawValue
            textView.typingAttributes = attrs
            return
        }
        let storage = textView.textStorage
        let current = (storage.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int) ?? 0
        storage.beginEditing()
        storage.addAttribute(.underlineStyle, value: current != 0 ? 0 : NSUnderlineStyle.single.rawValue, range: range)
        storage.endEditing()
    }

    /// 선택 영역이 있으면 그 자리를 바꿔 넣고, 캐럿만 있으면 그 위치에 삽입한다. 삽입 텍스트에는 현재
    /// `typingAttributes`가 적용된다. `didProcessEditing`이 걸려 `rtfText`/`plainText` 바인딩도 함께 갱신된다.
    func insertTextAtCursor(_ text: String) {
        guard let textView else { return }
        let range = textView.selectedRange
        let storage = textView.textStorage
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: textView.typingAttributes))
        storage.endEditing()
        textView.selectedRange = NSRange(location: range.location + (text as NSString).length, length: 0)
    }

    func applyColor(_ hex: String?) {
        guard let textView else { return }
        let color = hex.flatMap { Color(hex: $0) }.map(PlatformColor.init) ?? PlatformColor.label
        apply(.foregroundColor, value: color, on: textView)
    }

    func applyFontFamily(_ family: String?) {
        guard let textView else { return }
        let range = textView.selectedRange
        func makeFont(basedOn font: UIFont) -> UIFont {
            guard let family else { return UIFont.systemFont(ofSize: font.pointSize) }
            BundledFontRegistrar.ensureAvailable(family)
            return UIFont(name: family, size: font.pointSize) ?? font
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

    /// `applyFontFamily`와 같은 구조 — 캐럿만 있으면 `typingAttributes`, 선택이 있으면 범위 안 폰트를 순회하며
    /// 크기만 바꾼다(`UIFont.withSize(_:)`가 굵게/기울임 트레이트를 유지한다).
    func applyFontSize(_ size: CGFloat) {
        guard let textView else { return }
        let range = textView.selectedRange
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let font = (attrs[.font] as? UIFont) ?? UIFont.systemFont(ofSize: 15)
            attrs[.font] = font.withSize(size)
            textView.typingAttributes = attrs
            return
        }
        let storage = textView.textStorage
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? UIFont) ?? UIFont.systemFont(ofSize: 15)
            storage.addAttribute(.font, value: font.withSize(size), range: subrange)
        }
        storage.endEditing()
    }

    /// 정렬은 문단 단위 속성이라 캐럿만 있거나 짧게 선택해도 `paragraphRange(for:)`로 걸친 문단 전체에 적용한다.
    /// 기존 문단 스타일의 다른 값(줄간격 등)은 `mutableCopy()`로 복사해 정렬만 덮어써 보존한다.
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
        // 다음에 이어 칠 글자에도 같은 정렬이 적용되도록 타이핑 속성도 맞춰 둔다.
        var attrs = textView.typingAttributes
        attrs[.paragraphStyle] = makeParagraphStyle(basedOn: attrs[.paragraphStyle] as? NSParagraphStyle)
        textView.typingAttributes = attrs
    }

    private func toggleTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
        guard let textView else { return }
        let range = textView.selectedRange
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let font = (attrs[.font] as? UIFont) ?? UIFont.systemFont(ofSize: 15)
            attrs[.font] = font.togglingTrait(trait)
            textView.typingAttributes = attrs
            return
        }
        let storage = textView.textStorage
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? UIFont) ?? UIFont.systemFont(ofSize: 15)
            storage.addAttribute(.font, value: font.togglingTrait(trait), range: subrange)
        }
        storage.endEditing()
    }

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
    /// 조합이 지원되지 않는 폰트에서 `withSymbolicTraits(_:)`가 nil이면 원래 폰트를 반환해 조용히 무시한다.
    func togglingTrait(_ trait: UIFontDescriptor.SymbolicTraits) -> UIFont {
        var traits = fontDescriptor.symbolicTraits
        if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

struct RichTextEditorRepresentable: UIViewRepresentable {
    @Binding var rtfText: String
    @Binding var plainText: String
    var isEditable: Bool
    var proxy: RichTextEditingProxy
    var typingFont: UIFont = .systemFont(ofSize: 15)
    var defaultTextColor: UIColor? = nil
    var lineHeightMultiple: CGFloat = 1.0
    var editingBackgroundColor: UIColor? = nil
    var readOnlyBackgroundColor: UIColor? = nil
    /// iOS엔 네이티브 인스펙터 바가 없어 영향이 없다 — macOS 쪽 구조체와 호출부 시그니처를 맞추기 위해서만 존재한다.
    var showsToolbarOnMac: Bool = false

    private var typingAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = typingFont.typographicLineHeight * max(0, lineHeightMultiple - 1)
        var attrs: [NSAttributedString.Key: Any] = [.font: typingFont, .paragraphStyle: paragraph]
        if let defaultTextColor { attrs[.foregroundColor] = defaultTextColor }
        return attrs
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.font = typingFont
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.textStorage.delegate = context.coordinator
        // 키보드 위 "완료" 액세서리 바 — 메모/개인 묵상/말씀 요약이 모두 이 컴포넌트를 공유하므로 여기 한 곳에서 처리한다.
        textView.inputAccessoryView = Self.makeKeyboardDismissAccessoryView(for: textView)

        context.coordinator.textView = textView
        proxy.textView = textView

        loadInitialContent(into: textView, coordinator: context.coordinator)
        applyBackground(to: textView)
        applyStyleToolsVisibility(to: textView)
        return textView
    }

    /// 키보드 액세서리 바 — 오른쪽 끝의 "완료" 버튼이 `textView`의 첫 반응자를 내려놓는다. 셀렉터 대신
    /// `UIBarButtonItem(primaryAction:)`(iOS 14+) 클로저로 `textView`를 직접 캡처한다.
    private static func makeKeyboardDismissAccessoryView(for textView: UITextView) -> UIToolbar {
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 0, height: 44))
        toolbar.sizeToFit()
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(
            title: "완료",
            primaryAction: UIAction { [weak textView] _ in
                textView?.resignFirstResponder()
            }
        )
        // `primaryAction:` 이니셜라이저는 `style:` 인자가 없어 생성 후 지정한다(`.done`의 iOS 26 대체 이름이 `.prominent`).
        doneButton.style = .prominent
        toolbar.items = [flexibleSpace, doneButton]
        return toolbar
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        uiView.isEditable = isEditable
        proxy.textView = uiView
        applyBackground(to: uiView)
        applyStyleToolsVisibility(to: uiView)

        guard rtfText != context.coordinator.lastExportedText else { return }
        loadInitialContent(into: uiView, coordinator: context.coordinator)
    }

    /// macOS `dismantleNSView`와 같은 위험(아래 주석 참고) — `OutlineTreeView.swift`의 `.id(selection)`이 장 전환마다
    /// `UITextView`를 새로 만들고 버리는데 undo 관리자는 응답자 체인 위쪽과 공유되므로, 해제된 뷰를 가리키는 액션이
    /// 남을 수 있다. 보고된 적은 없지만 같은 경로라 대칭으로 미리 막는다.
    static func dismantleUIView(_ uiView: UITextView, coordinator: Coordinator) {
        uiView.undoManager?.removeAllActions(withTarget: uiView)
    }

    /// iOS "aA" 편집 메뉴(굵게/기울임/밑줄)와 ⌘B/⌘I/⌘U 단축키는 `allowsEditingTextAttributes`가 켜져 있을 때만
    /// 나타나므로 편집 가능할 때만 켠다.
    private func applyStyleToolsVisibility(to textView: UITextView) {
        textView.allowsEditingTextAttributes = isEditable
    }

    private func loadInitialContent(into textView: UITextView, coordinator: Coordinator) {
        // 아래 `setAttributedString`은 `NSTextStorage`가 `processEditing()`을 동기 호출해 `didProcessEditing`이 곧바로
        // 불린다. 이 로드를 사용자 입력으로 착각해 내보내면 화면을 열기만 해도 `updatedAt`이 갱신되고 불필요한
        // 자동저장이 예약되므로 `isLoadingExternally`로 막는다.
        coordinator.isLoadingExternally = true
        let attributed = RichTextCodec.decode(rtfText, defaultAttributes: typingAttributes)
        textView.textStorage.setAttributedString(attributed)
        // `setAttributedString`이 타이핑 속성을 문서 끝 글자 기준으로 다시 계산할 수 있어 기본값을 명시적으로 다시 맞춘다.
        textView.typingAttributes = typingAttributes
        coordinator.isLoadingExternally = false
        coordinator.lastExportedText = rtfText
    }

    /// 조회모드/편집모드별로 지정한 배경색을 적용한다. 색이 nil이면 기본값(투명)을 유지한다.
    private func applyBackground(to textView: UITextView) {
        let color = isEditable ? editingBackgroundColor : readOnlyBackgroundColor
        textView.backgroundColor = color ?? .clear
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextStorageDelegate {
        var parent: RichTextEditorRepresentable
        var lastExportedText: String = ""
        var isProcessing = false
        var isLoadingExternally = false
        weak var textView: UITextView?

        init(_ parent: RichTextEditorRepresentable) { self.parent = parent }

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
                self.lastExportedText = rtf
                self.parent.rtfText = rtf
                self.parent.plainText = plain
                self.isProcessing = false
            }
        }
    }
}

// MARK: - macOS

#elseif os(macOS)

/// iOS `RichTextEditingProxy`와 같은 역할. `showsToolbarOnMac`이 켜진 화면에서는 커스텀 툴바가 이 프록시를
/// 호출하고, 그렇지 않으면 네이티브 서식 팝업(`usesInspectorBar`)이 서식을 담당한다.
@MainActor
final class RichTextEditingProxy {
    weak var textView: NSTextView?

    func toggleBold() { toggleTrait(.bold) }
    func toggleItalic() { toggleTrait(.italic) }

    func toggleUnderline() {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let isUnderlined = ((attrs[.underlineStyle] as? Int) ?? 0) != 0
            attrs[.underlineStyle] = isUnderlined ? 0 : NSUnderlineStyle.single.rawValue
            textView.typingAttributes = attrs
            return
        }
        let current = (storage.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int) ?? 0
        storage.beginEditing()
        storage.addAttribute(.underlineStyle, value: current != 0 ? 0 : NSUnderlineStyle.single.rawValue, range: range)
        storage.endEditing()
    }

    /// iOS `RichTextEditingProxy.insertTextAtCursor(_:)`와 같은 역할.
    func insertTextAtCursor(_ text: String) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: textView.typingAttributes))
        storage.endEditing()
        textView.setSelectedRange(NSRange(location: range.location + (text as NSString).length, length: 0))
    }

    func applyColor(_ hex: String?) {
        guard let textView, let storage = textView.textStorage else { return }
        let color = hex.flatMap { Color(hex: $0) }.map(PlatformColor.init) ?? PlatformColor.labelColor
        let range = textView.selectedRange()
        if range.length == 0 {
            var attrs = textView.typingAttributes
            attrs[.foregroundColor] = color
            textView.typingAttributes = attrs
            return
        }
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: color, range: range)
        storage.endEditing()
    }

    func applyFontFamily(_ family: String?) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        func makeFont(basedOn font: NSFont) -> NSFont {
            guard let family else { return NSFont.systemFont(ofSize: font.pointSize) }
            BundledFontRegistrar.ensureAvailable(family)
            return NSFont(name: family, size: font.pointSize) ?? font
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

    /// iOS `applyFontSize(_:)`와 같은 구조. `NSFont`엔 `withSize(_:)`가 없어 `NSFont(descriptor:size:)`로 새 인스턴스를
    /// 만들고, 실패하면 원래 폰트를 유지한다.
    func applyFontSize(_ size: CGFloat) {
        guard let textView, let storage = textView.textStorage else { return }
        func resized(_ font: NSFont) -> NSFont {
            NSFont(descriptor: font.fontDescriptor, size: size) ?? font
        }
        let range = textView.selectedRange()
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let font = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 15)
            attrs[.font] = resized(font)
            textView.typingAttributes = attrs
            return
        }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: 15)
            storage.addAttribute(.font, value: resized(font), range: subrange)
        }
        storage.endEditing()
    }

    /// iOS `applyAlignment(_:)`와 같은 구조 — 선택이 걸친 문단 전체에 적용한다.
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
            attrs[.font] = font.togglingTrait(trait)
            textView.typingAttributes = attrs
            return
        }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: 15)
            storage.addAttribute(.font, value: font.togglingTrait(trait), range: subrange)
        }
        storage.endEditing()
    }
}

private extension NSFont {
    /// `NSFontDescriptor.withSymbolicTraits(_:)`는 옵셔널이 아니지만 `NSFont(descriptor:size:)`가 실패할 수 있어(`init?`)
    /// 실패 시 원래 폰트를 쓴다.
    func togglingTrait(_ trait: NSFontDescriptor.SymbolicTraits) -> NSFont {
        var traits = fontDescriptor.symbolicTraits
        if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
        let descriptor = fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}

struct RichTextEditorRepresentable: NSViewRepresentable {
    @Binding var rtfText: String
    @Binding var plainText: String
    var isEditable: Bool
    var proxy: RichTextEditingProxy
    var typingFont: NSFont = .systemFont(ofSize: 15)
    var defaultTextColor: NSColor? = nil
    var lineHeightMultiple: CGFloat = 1.0
    var editingBackgroundColor: NSColor? = nil
    var readOnlyBackgroundColor: NSColor? = nil
    /// `true`이면 네이티브 서식 팝업(`usesInspectorBar`)을 끄고 커스텀 `RichTextEditorToolbar`만 쓴다. 네이티브 팝업은
    /// 창 좌표 기준으로 떠서 좁은 `.inspector` 패널 안의 텍스트뷰에서도 위치가 어긋날 수 있고, 앵커를 지정할 API가
    /// 없다(`applyStyleToolsVisibility` 참고). `false`이면 네이티브 바를 그대로 쓴다.
    var showsToolbarOnMac: Bool = false

    private var typingAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = typingFont.typographicLineHeight * max(0, lineHeightMultiple - 1)
        var attrs: [NSAttributedString.Key: Any] = [.font: typingFont, .paragraphStyle: paragraph]
        if let defaultTextColor { attrs[.foregroundColor] = defaultTextColor }
        return attrs
    }

    func makeNSView(context: Context) -> NSScrollView {
        // `usesInspectorBar`(macOS 14+)가 켜지면 텍스트 선택 시 네이티브 서식 팝업이 자동으로 뜬다
        // (`applyStyleToolsVisibility`에서 제어).
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = true
        textView.importsGraphics = true
        textView.isContinuousSpellCheckingEnabled = false
        textView.font = typingFont
        textView.textContainerInset = NSSize(width: 8, height: 8)

        textView.textStorage?.delegate = context.coordinator
        context.coordinator.textView = textView
        proxy.textView = textView

        loadInitialContent(into: textView, coordinator: context.coordinator)
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

        guard rtfText != context.coordinator.lastExportedText else { return }
        loadInitialContent(into: textView, coordinator: context.coordinator)
    }

    /// 장 전환 시 `.id(selection)`(`OutlineTreeView.swift`)이 `NSTextView`를 통째로 새로 만들고 버린다. 그런데
    /// `allowsUndo`가 등록하는 undo 액션은 텍스트뷰가 아니라 윈도우가 공유하는 `NSUndoManager`에 쌓이므로, 버려진
    /// 텍스트뷰를 가리키는 액션이 남아 있다가 Command+Z에서 해제된 객체에 메시지를 보내 크래시한다.
    /// 해제 직전에 `removeAllActions(withTarget:)`으로 이 텍스트뷰를 가리키는 액션만 지운다(Apple 문서 권장 방식,
    /// 다른 화면의 undo 기록은 건드리지 않는다).
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        textView.undoManager?.removeAllActions(withTarget: textView)
    }

    /// 편집 가능할 때만 네이티브 서식 도구(`usesInspectorBar/usesFontPanel/usesRuler`)를 켠다. `showsToolbarOnMac`이
    /// 켜져 있으면 커스텀 `RichTextEditorToolbar`만 남기고 네이티브 도구를 끈다.
    private func applyStyleToolsVisibility(to textView: NSTextView) {
        let usesNativeBar = isEditable && !showsToolbarOnMac
        textView.usesInspectorBar = usesNativeBar
        textView.usesFontPanel = usesNativeBar
        textView.usesRuler = usesNativeBar
    }

    private func loadInitialContent(into textView: NSTextView, coordinator: Coordinator) {
        // iOS `loadInitialContent`와 같은 이유의 가드(자기 변경의 메아리 방지).
        coordinator.isLoadingExternally = true
        let attributed = RichTextCodec.decode(rtfText, defaultAttributes: typingAttributes)
        textView.textStorage?.setAttributedString(attributed)
        // iOS 쪽과 같은 이유로 기본값을 명시적으로 다시 맞춘다.
        textView.typingAttributes = typingAttributes
        coordinator.isLoadingExternally = false
        coordinator.lastExportedText = rtfText
    }

    /// iOS `applyBackground`와 달리 두 색이 모두 nil이면 아무것도 건드리지 않는다 — `NSTextView` 기본값이 이미
    /// `drawsBackground = true` + `.textBackgroundColor`(라이트/다크 자동)라서 끄면 에디터가 투명해진다.
    /// 색을 지정한 화면에서만 덮어쓴다.
    private func applyBackground(to textView: NSTextView) {
        guard let color = isEditable ? editingBackgroundColor : readOnlyBackgroundColor else { return }
        textView.drawsBackground = true
        textView.backgroundColor = color
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextStorageDelegate {
        var parent: RichTextEditorRepresentable
        var lastExportedText: String = ""
        var isProcessing = false
        var isLoadingExternally = false
        weak var textView: NSTextView?

        init(_ parent: RichTextEditorRepresentable) { self.parent = parent }

        // AppKit의 `NSTextStorageDelegate`는 `NSTextStorage.EditActions`가 아니라 전역 typealias
        // `NSTextStorageEditActions`를 쓴다(iOS와 이름이 달라 통일할 수 없다).
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
                self.lastExportedText = rtf
                self.parent.rtfText = rtf
                self.parent.plainText = plain
                self.isProcessing = false
            }
        }
    }
}
#endif
