//
//  SelectableVerseTextView.swift
//  JBCHBibleResearch
//
//  "구절 확대보기"(VerseZoomView.swift) 전용 선택 모드 텍스트 뷰.
//  SwiftUI `Text.textSelection`은 드래그로 고른 정확한 글자 범위를 코드로 읽을 수 없어,
//  `UITextView`(iOS)/`NSTextView`(macOS)를 직접 감싸 `selectedRange`를 읽는다.
//  이 범위는 `VerseHighlight`/`VerseCrossReference`/`VersePhraseNote`의 rangeStart/rangeEnd로
//  저장되며, UTF-16 단위 `NSRange`라 `VerseAnnotations.swift`의 저장 규칙과 변환 없이 일치한다.
//
//  설계: 확대보기는 표시 모드(`AnnotatedVerseFlowView`, 순수 SwiftUI)와 선택 모드(이 파일)로
//  분리되어 있다. 이 뷰는 새 구간을 드래그로 고르는 동안에만 보이므로 `selectedRange`를 정확히
//  읽는 데 집중하고, 줄바꿈·줄 간격(2.3배)·형광펜/밑줄/메모 글자색만 표시 모드와 맞춘다.
//  줄바꿈은 `VerseAnnotationRenderer.forcedBreakText(...)`로 표시 모드의 `lineRanges(...)`
//  경계를 강제하고, 주석 표현은 `buildLines(...)`의 세그먼트 분해를 재사용한다.
//  `TightBackgroundLayoutManager`는 줄 간격만큼 형광펜이 늘어나지 않도록 배경 채우기만 가로챈다.
//

import SwiftUI
import BibleResearchModels
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// 줄 프래그먼트 사용 영역(줄 간격 포함) 대신 글자 자체의 타이트한 박스만 배경색으로
/// 채우는 `NSLayoutManager`. 이 파일의 선택 모드에서만 쓰인다(표시 모드는 TextKit을 쓰지 않는다).
///
/// ⚠️ 실패에 안전하다 — 텍스트 컨테이너나 참조 폰트를 못 찾으면 `super` 구현으로 넘긴다.
final class TightBackgroundLayoutManager: NSLayoutManager {
    /// 세로 타이트 박스 계산에 쓸 폰트 — 선택 모드는 절 전체가 한 폰트라
    /// 매번 `textStorage`를 다시 조회할 필요 없이 호출부가 미리 넣어 둔다.
    var referenceFont: PlatformFont?

    // `fillBackgroundRectArray`는 이 텍스트뷰의 모든 배경 채우기 요청을 받는데, 여기에는
    // 실제 하이라이트(`.backgroundColor` 속성 구간)뿐 아니라 OS 기본 드래그-선택 강조도 포함된다.
    // 타이트 사각형 재계산을 선택 강조에까지 적용하면, 한글 텍스트에서 드래그 선택이 깜박였다
    // (한글은 `forcedBreakText`가 U+2028을 끼워 넣어 리드로우마다 사각형 집합이 달라지는 것으로
    // 추정, 영문은 치환이 없어 정상). 그래서 `.backgroundColor`가 걸린 구간에만 적용하고
    // 나머지는 `super`에 맡긴다.
    private func hasExplicitBackgroundColorAttribute(in charRange: NSRange) -> Bool {
        guard let storage = textStorage, charRange.length > 0,
            charRange.location >= 0, charRange.location + charRange.length <= storage.length
        else { return false }
        var found = false
        storage.enumerateAttribute(.backgroundColor, in: charRange, options: []) { value, _, stop in
            if value != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    override func fillBackgroundRectArray(
        _ rectArray: UnsafePointer<CGRect>, count rectCount: Int,
        forCharacterRange charRange: NSRange, color: PlatformColor
    ) {
        guard hasExplicitBackgroundColorAttribute(in: charRange) else {
            super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
            return
        }
        guard let container = textContainers.first, let font = referenceFont else {
            super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
            return
        }
        let glyphRange = self.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return }

        let ascender = font.ascender
        let descender = font.descender
        color.setFill()

        // `buildLines(...)`가 줄 단위로 세그먼트를 나누므로 `charRange`가 여러 줄에 걸치는 일은
        // 드물지만, 안전하게 줄 단위로 한 번 더 나눈다.
        enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, lineGlyphRange, _ in
            let clipped = NSIntersectionRange(lineGlyphRange, glyphRange)
            guard clipped.length > 0 else { return }
            // `location(forGlyphAt:).y`는 줄 프래그먼트 원점 기준 상대값이므로 `lineRect.origin.y`를
            // 더해야 절대 좌표의 베이스라인이 된다.
            let baselineY = lineRect.origin.y + self.location(forGlyphAt: clipped.location).y
            let tightTop = baselineY - ascender
            let tightHeight = ascender - descender

            self.enumerateEnclosingRects(
                forGlyphRange: clipped,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: container
            ) { rect, _ in
                let tightRect = CGRect(x: rect.minX, y: tightTop, width: rect.width, height: tightHeight)
                #if os(iOS)
                UIRectFill(tightRect)
                #elseif os(macOS)
                NSBezierPath(rect: tightRect).fill()
                #endif
            }
        }
    }
}

#if os(iOS)

struct SelectableVerseTextView: UIViewRepresentable {
    let text: String
    let font: PlatformFont
    let textColor: PlatformColor
    /// `VerseAnnotationRenderer.lineRanges(...)`가 줄을 나누는 폭. 표시 모드에 넘기는
    /// `effectiveTextWidth`와 같은 값이어야 두 모드의 줄바꿈이 어긋나지 않는다.
    let containerWidth: CGFloat
    /// 세로/가로 모드별 줄당 글자수. 표시 모드(`AnnotatedVerseFlowView`)와 같은 값이어야 한다.
    let targetCharsPerLine: Int
    /// 이미 주석이 걸린 표현을 선택 모드에서도 글자색/배경으로 보여 주기 위한 입력
    /// (메모 내용인 박스/화살표는 표시 모드 전용).
    let highlights: [VerseHighlight]
    let phraseNotes: [VersePhraseNote]
    /// 관주가 걸린 표현을 밑줄로 보여 주기 위한 입력(표시 모드와 같은 신호).
    let crossReferences: [VerseCrossReference]
    /// 한자 단어를 색으로 표시하기 위한 입력(표시 모드와 같은 신호).
    var hanjaWords: [HanjaWordAnnotation] = []
    /// `true`(기본값)면 표시 모드와 줄바꿈을 맞추려고 한글 텍스트에 보이지 않는 U+2028을 끼워
    /// 넣는다(`VerseZoomView`용). `false`면 이 치환을 건너뛰어 뷰 자체 폭 기준으로 줄바꿈한다
    /// (`VerseTextSelectionPopover`용 — 한글 번역본의 드래그 선택 깜박임 회피).
    /// 자세한 내용은 `VerseAnnotationRenderer.selectionModeAttributedText` 참고.
    var matchDisplayModeLineBreaks: Bool = true
    @Binding var selectedRange: NSRange

    private var attributedText: NSAttributedString {
        VerseAnnotationRenderer.selectionModeAttributedText(
            text: text, highlights: highlights, phraseNotes: phraseNotes, crossReferences: crossReferences,
            hanjaWords: hanjaWords, matchDisplayModeLineBreaks: matchDisplayModeLineBreaks,
            font: font, textColor: textColor, containerWidth: containerWidth,
            targetCharsPerLine: targetCharsPerLine
        )
    }

    // `TightBackgroundLayoutManager`를 쓰려면 `UITextView()` 기본 생성자 대신
    // `NSTextStorage`/`NSTextContainer`를 직접 엮어 `UITextView(frame:textContainer:)`로 만들어야
    // 한다. `.attributedText` 세터는 `textStorage`를 교체하지 않고 내용만 갱신하므로 연결이 유지된다.
    // `textStorage`/`layoutManager`는 `Coordinator`가 강하게 붙들어 텍스트 뷰 수명 동안
    // 해제되지 않게 한다.
    func makeUIView(context: Context) -> UITextView {
        let coordinator = context.coordinator
        coordinator.layoutManager.referenceFont = font
        let container = NSTextContainer()
        container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        coordinator.layoutManager.addTextContainer(container)

        let textView = UITextView(frame: .zero, textContainer: container)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.delegate = coordinator
        textView.attributedText = attributedText
        return textView
    }

    // 프로그램적 선택 복원이 사용자의 드래그 선택을 되돌리지 않도록, `Coordinator`가 마지막으로
    // 보고한 범위와 같은 바인딩 값이면 `selectedRange` 재설정을 건너뛴다(macOS `updateNSView`와 동일).
    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.layoutManager.referenceFont = font
        let expected = attributedText
        if !uiView.attributedText.isEqual(to: expected) {
            uiView.attributedText = expected
        }
        if uiView.selectedRange != selectedRange && selectedRange != context.coordinator.lastReportedSelectedRange {
            uiView.selectedRange = selectedRange
        }
    }

    // iOS 16+ — `isScrollEnabled = false`인 `UITextView`의 실제 콘텐츠 높이를 SwiftUI에 알려 준다.
    // 없으면 줄바꿈된 본문이 잘려 보인다.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fitting.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SelectableVerseTextView
        /// `Coordinator`가 강하게 붙들어야 텍스트 뷰가 살아 있는 동안 해제되지 않는다(`makeUIView` 참고).
        let textStorage = NSTextStorage()
        let layoutManager = TightBackgroundLayoutManager()
        /// 마지막으로 바인딩에 내보낸 선택 범위(`updateUIView` 참고).
        var lastReportedSelectedRange: NSRange?

        init(_ parent: SelectableVerseTextView) {
            self.parent = parent
            super.init()
            textStorage.addLayoutManager(layoutManager)
        }

        // `updateUIView`가 프로그램적으로 선택을 맞출 때 이 델리게이트가 동기 호출될 수 있고, 뷰 업데이트 중
        // `@Binding`을 바로 바꾸면 정의되지 않은 동작("Modifying state during view update")이 된다.
        // 그래서 다음 런루프 틱으로 미룬다.
        func textViewDidChangeSelection(_ textView: UITextView) {
            let newRange = textView.selectedRange
            // 되돌아온 바인딩 값이 자신이 보고한 값인지 `updateUIView`에서 알아보기 위해 기록한다.
            lastReportedSelectedRange = newRange
            DispatchQueue.main.async { [weak self] in
                self?.parent.selectedRange = newRange
            }
        }
    }
}

#elseif os(macOS)

struct SelectableVerseTextView: NSViewRepresentable {
    let text: String
    let font: PlatformFont
    let textColor: PlatformColor
    /// 줄바꿈 기준 폭. 위 iOS 쪽 `containerWidth` 참고.
    let containerWidth: CGFloat
    /// 위 iOS 쪽 `targetCharsPerLine` 참고.
    let targetCharsPerLine: Int
    /// 위 iOS 쪽 `highlights`/`phraseNotes` 참고.
    let highlights: [VerseHighlight]
    let phraseNotes: [VersePhraseNote]
    /// 위 iOS 쪽 `crossReferences` 참고.
    let crossReferences: [VerseCrossReference]
    /// 한자 단어를 색으로 표시하기 위한 입력(표시 모드와 같은 신호).
    var hanjaWords: [HanjaWordAnnotation] = []
    /// `true`(기본값)면 표시 모드와 줄바꿈을 맞추려고 한글 텍스트에 보이지 않는 U+2028을 끼워
    /// 넣는다(`VerseZoomView`용). `false`면 이 치환을 건너뛰어 뷰 자체 폭 기준으로 줄바꿈한다
    /// (`VerseTextSelectionPopover`용 — 한글 번역본의 드래그 선택 깜박임 회피).
    /// 자세한 내용은 `VerseAnnotationRenderer.selectionModeAttributedText` 참고.
    var matchDisplayModeLineBreaks: Bool = true
    @Binding var selectedRange: NSRange

    private var attributedText: NSAttributedString {
        VerseAnnotationRenderer.selectionModeAttributedText(
            text: text, highlights: highlights, phraseNotes: phraseNotes, crossReferences: crossReferences,
            hanjaWords: hanjaWords, matchDisplayModeLineBreaks: matchDisplayModeLineBreaks,
            font: font, textColor: textColor, containerWidth: containerWidth,
            targetCharsPerLine: targetCharsPerLine
        )
    }

    // 위 iOS 쪽 `makeUIView`와 같은 이유로 `NSTextView()` 기본 생성자 대신
    // `NSTextStorage`/`NSTextContainer`를 직접 엮고, `Coordinator`가 이를 강하게 붙든다.
    func makeNSView(context: Context) -> NSTextView {
        let coordinator = context.coordinator
        coordinator.layoutManager.referenceFont = font
        let container = NSTextContainer()
        container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        coordinator.layoutManager.addTextContainer(container)

        let textView = NSTextView(frame: .zero, textContainer: container)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.delegate = coordinator
        textView.textStorage?.setAttributedString(attributedText)
        return textView
    }

    // 드래그 중에는 `nsView`의 실제 선택이 계속 앞서 나가는데, `Coordinator`는 바인딩을 한 틱
    // 늦게 갱신한다. 이때 뒤처진 바인딩 값과 실제 선택이 다르다고 `setSelectedRange`로 되돌리면
    // 선택 영역이 좁아졌다 넓어지는 깜박임이 생긴다. 그래서 `Coordinator`가 마지막으로 보고한 값
    // (`lastReportedSelectedRange`)과 같은 바인딩이 돌아오면 되돌림을 건너뛰고, 다른 값
    // (화면 새로 열기, 외부에서의 선택 초기화 등)만 반영한다.
    func updateNSView(_ nsView: NSTextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.layoutManager.referenceFont = font
        let expected = attributedText
        if !nsView.attributedString().isEqual(to: expected) {
            nsView.textStorage?.setAttributedString(expected)
        }
        if nsView.selectedRange() != selectedRange && selectedRange != context.coordinator.lastReportedSelectedRange {
            nsView.setSelectedRange(selectedRange)
        }
    }

    // macOS 13+ — 위 iOS 쪽 `sizeThatFits`와 같은 이유.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        guard let container = nsView.textContainer, let layoutManager = nsView.layoutManager else { return nil }
        let width = proposal.width ?? nsView.bounds.width
        guard width > 0 else { return nil }
        container.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        return CGSize(width: width, height: used.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SelectableVerseTextView
        /// 위 iOS 쪽 `Coordinator`와 같은 이유로 강하게 붙든다.
        let textStorage = NSTextStorage()
        let layoutManager = TightBackgroundLayoutManager()
        /// 마지막으로 바인딩에 내보낸 선택 범위(`updateNSView` 참고). `nil`이면 항상 `setSelectedRange`가 동작한다.
        var lastReportedSelectedRange: NSRange?

        init(_ parent: SelectableVerseTextView) {
            self.parent = parent
            super.init()
            textStorage.addLayoutManager(layoutManager)
        }

        // 위 iOS `Coordinator`와 같은 이유로 바인딩 갱신을 다음 런루프 틱으로 미룬다.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let newRange = textView.selectedRange()
            // 되돌아온 바인딩 값이 자신이 보고한 값인지 `updateNSView`에서 알아보기 위해 기록한다.
            lastReportedSelectedRange = newRange
            DispatchQueue.main.async { [weak self] in
                self?.parent.selectedRange = newRange
            }
        }
    }
}
#endif
