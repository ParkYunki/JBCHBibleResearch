//
//  VerseAnnotationRenderer.swift
//  JBCHBibleResearch
//
//  구간 주석(형광펜/표시)을 `AttributedString`으로 렌더링한다. 평소 읽기 화면
//  (`TranslationColumnView.VerseRow`)에서 절 원문에 배경색/밑줄 span을 입힌다.
//
//  ⚠️ 자가 치유 앵커링: 저장된 rangeStart/rangeEnd로 잘라낸 텍스트가 `anchorText`
//  (주석 생성 시점의 스냅샷)와 다르면(번역본 데이터가 나중에 고쳐진 경우) 오프셋을
//  무시하고 `anchorText`를 본문에서 다시 찾아 그 위치에 입힌다. 그마저 못 찾으면
//  그 주석은 조용히 건너뛴다 — 잘못된 위치에 스타일을 입히는 것보다 안전하다.
//
//  "표시"는 밑줄 하나로만 구현했다(박스/기호 등 추가 스타일은 필요할 때 추가).
//

import SwiftUI
import BibleResearchModels
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum VerseAnnotationRenderer {
    /// `highlights`와 `phraseNotes`가 모두 비어 있으면 nil을 돌려준다 — 호출부가 평범한
    /// `Text(verse.content)`를 그대로 쓰게 해 대다수 절에서 변환 비용을 피한다.
    ///
    /// `NSAttributedString`을 `AttributedString(_:)`로 브리징하면 SwiftUI `Text`가 밑줄 속성
    /// (`.underlineStyle`/`.underlineColor`)을 신뢰성 있게 렌더링하지 않아, `AttributedString`
    /// 고유 API로 구간별 조각을 직접 이어 붙인다(`NSRange → AttributedString.Index` 변환도 피한다).
    static func attributedContent(
        text: String,
        highlights: [VerseHighlight],
        // 형광펜(배경색)/표시(밑줄)와 독립적인 세 번째 속성(글자색)이라 겹칠 수 있다.
        phraseNotes: [VersePhraseNote] = [],
        font: PlatformFont,
        textColor: PlatformColor
    ) -> AttributedString? {
        guard !highlights.isEmpty || !phraseNotes.isEmpty else { return nil }

        let full = text as NSString
        struct HighlightSegment { let range: NSRange; let highlight: VerseHighlight }
        let highlightSegments: [HighlightSegment] = highlights.compactMap { highlight in
            guard let range = resolvedRange(
                start: highlight.rangeStart, end: highlight.rangeEnd,
                anchorText: highlight.anchorText, in: full
            ), range.length > 0 else { return nil }
            return HighlightSegment(range: range, highlight: highlight)
        }
        let noteRanges: [NSRange] = phraseNotes.compactMap { note in
            guard let range = resolvedRange(
                start: note.rangeStart, end: note.rangeEnd, anchorText: note.anchorText, in: full
            ), range.length > 0 else { return nil }
            return range
        }

        guard !highlightSegments.isEmpty || !noteRanges.isEmpty else { return nil }

        // 형광펜/표시와 메모 글자색은 서로 독립적으로 겹칠 수 있으므로, 두 종류 구간의 모든
        // 시작/끝 지점(경계점)으로 "겹치지 않는 최소 조각"을 나누고 조각마다 각각 속성을 입힌다.
        var boundaries = Set<Int>([0, full.length])
        for segment in highlightSegments {
            boundaries.insert(segment.range.location)
            boundaries.insert(segment.range.location + segment.range.length)
        }
        for range in noteRanges {
            boundaries.insert(range.location)
            boundaries.insert(range.location + range.length)
        }
        let sortedBoundaries = boundaries.sorted()

        var result = AttributedString()
        for index in 0..<(sortedBoundaries.count - 1) {
            let start = sortedBoundaries[index]
            let end = sortedBoundaries[index + 1]
            guard end > start else { continue }
            let range = NSRange(location: start, length: end - start)
            var run = plainRun(full.substring(with: range), font: font, textColor: textColor)

            // 경계점 구성상 조각은 어느 형광펜 구간과도 부분 겹침이 없다(완전 포함 또는 무관) — 먼저 만들어진 것 우선.
            if let covering = highlightSegments.first(where: {
                $0.range.location <= start && $0.range.location + $0.range.length >= end
            }) {
                switch covering.highlight.style {
                case .highlight:
                    let tag = HighlightColorTag(rawValue: covering.highlight.colorTag ?? "") ?? .yellow
                    run.backgroundColor = tag.swiftUIColor.opacity(tag.backgroundOpacity)
                case .mark:
                    // 확대보기의 주황 굵은 밑줄과 색을 맞춘다. ⚠️ SwiftUI `Text.LineStyle`엔 두께
                    // 파라미터가 없어 색상만 맞출 수 있다(플랫폼 제약).
                    run.underlineStyle = Text.LineStyle(pattern: .solid, color: .orange)
                }
            }
            if noteRanges.contains(where: { $0.location <= start && $0.location + $0.length >= end }) {
                run.foregroundColor = phraseNoteTextColor
            }
            result += run
        }
        return result
    }

    /// "메모"(드래그 표현 부연설명)가 붙은 구간의 글자색. 형광펜(배경 5색)·표시(주황 밑줄)와
    /// 겹치지 않는 색을 임의로 골랐다 — 다른 색이 낫다면 이 상수만 바꾸면 된다.
    static let phraseNoteTextColor = Color.blue

    /// 한자 주석이 있는 단어의 글자색. 형광펜/밑줄/메모 글자색과 겹치지 않는 색을 임의로 골랐다
    /// — 이 상수만 바꾸면 된다.
    static let hanjaWordTextColor = Color.brown

    /// 한자 단어를 "굵게" 표시하기 위한 굵은 글꼴(2026-10-07, 메모+한자 구분 목업 B안).
    /// 규칙: 파랑 글자 = 메모가 있음, 굵게 = 한자 단어 — 서로 다른 수단이라 메모(파랑)가 한자 색(황갈)을 덮어도
    /// 굵기로 한자 단어임이 남는다. 글꼴에 굵은 변형이 없으면(트레이트 변환 실패) 원래 글꼴을 그대로 돌려줘 모양이 변하지 않는다.
    static func boldVariant(of font: PlatformFont) -> PlatformFont {
        #if os(iOS)
        let traits = font.fontDescriptor.symbolicTraits.union(.traitBold)
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
        #else
        return NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        #endif
    }

    /// 선택 모드(`SelectableVerseTextView`)는 `NSAttributedString`을 직접 쓰는
    /// `UITextView`/`NSTextView`라 SwiftUI `Color`가 아니라 `PlatformColor`가 필요하다.
    static var phraseNoteTextPlatformColor: PlatformColor { PlatformColor(phraseNoteTextColor) }

    private static func plainRun(_ substring: String, font: PlatformFont, textColor: PlatformColor) -> AttributedString {
        var run = AttributedString(substring)
        run.font = Font(font)
        run.foregroundColor = Color(textColor)
        return run
    }

    /// `attributedContent`가 만든(형광펜/메모가 없으면 새로 만든 평범한) `AttributedString`에
    /// 한자 주석 단어 뒤의 "(한자)"와 난외주 앵커 위치의 위첨자 마커를 끼워 넣는다.
    ///
    /// ⚠️ 삽입 순서: 한자(`rangeEnd`)와 난외주(`anchorOffset`)를 오프셋 하나의 목록으로 합쳐
    /// 오프셋 내림차순으로 처리한다. 앞쪽에 삽입하면 뒤쪽 위치가 밀리므로 뒤에서부터 처리해야
    /// 미처리 위치가 원본 `text` 좌표를 유지하고, 한 종류를 먼저 다 처리하면 다른 종류의
    /// 저장 오프셋이 어긋난다.
    ///
    /// 한자는 옅은 색 + 기울임, 난외주 마커는 `note.markerText`(원본 `<SUP>` 캡처 글자 그대로,
    /// 대부분 ①②③..., 일부는 `*`)를 작게 표시한다. 원본 번호는 절 단위가 아니라 장 전체에 걸쳐
    /// 이어지고 반복 단어는 번호를 재사용하므로 앱이 번호를 새로 매기지 않는다.
    static func attributedContentWithInlineAnnotations(
        text: String,
        highlights: [VerseHighlight],
        phraseNotes: [VersePhraseNote] = [],
        hanjaWords: [HanjaWordAnnotation] = [],
        marginalNotes: [VerseMarginalNote] = [],
        font: PlatformFont,
        textColor: PlatformColor,
        // nil이면 본문 글꼴을 그대로 쓴다.
        hanjaFont: PlatformFont? = nil
    ) -> AttributedString {
        let base = attributedContent(
            text: text, highlights: highlights, phraseNotes: phraseNotes, font: font, textColor: textColor
        ) ?? plainRun(text, font: font, textColor: textColor)

        enum Insertion {
            case hanja(String)
            case marginalNoteMarker(String)
        }
        var insertions: [(offset: Int, item: Insertion)] = hanjaWords.map { word in
            (offset: word.rangeEnd, item: .hanja(word.hanja))
        }
        for note in marginalNotes {
            guard let offset = note.anchorOffset, let marker = note.markerText, !marker.isEmpty else { continue }
            insertions.append((offset: offset, item: .marginalNoteMarker(marker)))
        }
        insertions.sort { $0.offset > $1.offset }

        var result = base
        for entry in insertions {
            let nsRange = NSRange(location: entry.offset, length: 0)
            guard let index = Range(nsRange, in: result)?.lowerBound else { continue }
            switch entry.item {
            case .hanja(let hanja):
                var hanjaRun = AttributedString("(\(hanja))")
                hanjaRun.font = Font(hanjaFont ?? font).italic()
                hanjaRun.foregroundColor = Color(textColor).opacity(0.6)
                result.insert(hanjaRun, at: index)
            case .marginalNoteMarker(let marker):
                var markerRun = AttributedString(marker)
                markerRun.font = .system(size: font.pointSize * 0.7)
                markerRun.foregroundColor = marginalNoteMarkerColor
                result.insert(markerRun, at: index)
            }
        }
        return result
    }


    /// 난외주 위첨자 번호의 색 — 형광펜·밑줄·메모 글자색·한자 인라인 표시와 겹치지 않는 색을 임의로 골랐다.
    static let marginalNoteMarkerColor = Color.purple


    /// 줄 시작(`lineStart`)에서 `targetCharsPerLine`번째 글자를 목표점으로 잡고, 목표점부터
    /// 뒤로만 검색해 처음 만나는 띄어쓰기에서 줄을 나누는 과정을 반복한다. 남은 구간에
    /// 띄어쓰기가 없으면(매우 긴 단일 단어) 멈춘다 — 어절 중간은 끊지 않는다.
    private static func lineBreakPositions(in text: String, targetCharsPerLine: Int) -> [Int] {
        let ns = text as NSString
        guard targetCharsPerLine > 0, ns.length > targetCharsPerLine else { return [] }
        var positions: [Int] = []
        var lineStart = 0
        while ns.length - lineStart > targetCharsPerLine {
            let target = min(lineStart + targetCharsPerLine, ns.length - 1)
            guard let spaceIndex = firstSpaceIndex(in: ns, from: target, to: ns.length) else {
                break
            }
            positions.append(spaceIndex)
            lineStart = spaceIndex + 1
        }
        return positions
    }

    /// `target`부터 `upperBound` 방향으로만 훑어 처음 만나는 띄어쓰기(U+0020) 위치를 돌려준다.
    /// `[target, upperBound)` 밖은 보지 않는다(절 끝을 넘지 않게).
    private static func firstSpaceIndex(in ns: NSString, from target: Int, to upperBound: Int) -> Int? {
        guard upperBound > target else { return nil }
        var index = max(target, 0)
        while index < upperBound {
            if ns.character(at: index) == 0x20 { return index }
            index += 1
        }
        return nil
    }

    /// 절 텍스트에 라틴 문자/숫자가 있는지. 번역본에 "언어" 필드가 없고(`TranslationRegistry` —
    /// 사용자 추가 번역본은 임의 언어) 번들 한글 번역본에는 항상 없고 영문 성경 등에는 항상
    /// 있어, 텍스트로 판정해도 번역본 구분과 같은 효과를 낸다.
    static func containsLatinOrDigit(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (scalar.value >= 0x41 && scalar.value <= 0x5A)
                || (scalar.value >= 0x61 && scalar.value <= 0x7A)
                || (scalar.value >= 0x30 && scalar.value <= 0x39)
        }
    }

    // MARK: - [2026-08-11 8차 수정, 확대보기 전면 재설계] 순수 SwiftUI 표시 레이어
    //
    // 확대보기를 "표시 모드"(이 섹션, 순수 SwiftUI)와 "선택 모드"(`SelectableVerseTextView`,
    // 드래그로 새 구간을 고를 때만 뜨는 최소 컴포넌트)로 분리한다. 표시 모드는 절을 직접 줄
    // 단위로 나눠(`lineRanges(...)`) 줄마다 `Text` 세그먼트의 `HStack`으로 그리고, 메모 박스는
    // 그 줄 아래 `VStack`의 서브뷰로 끼워 넣는다 — 높이 추정이나 TextKit 줄간격 주입이
    // 필요 없다(`Views/Bible/AnnotatedVerseFlowView.swift` 참고).

    /// 절 텍스트를 시각적 "줄" 단위로 나눈 문자 범위 목록. 라틴/숫자 없는 절은
    /// `koreanLineRanges`(목표 글자수 이후 첫 띄어쓰기), 라틴/혼합 절은 화면에 붙이지 않는
    /// "측정 전용" TextKit(`measuredLineRanges`)으로 실제 폭 기준 줄바꿈을 구한다.
    /// 반환 형태가 같아 호출부는 분기하지 않는다.
    ///
    /// `targetCharsPerLine`은 아이폰 세로/가로 모드마다 줄당 글자수를 달리하기 위한
    /// 매개변수다. 라틴/혼합 절은 폭 기준이라 이 값과 무관하다.
    static func lineRanges(for text: String, font: PlatformFont, containerWidth: CGFloat, targetCharsPerLine: Int = 23) -> [NSRange] {
        guard !text.isEmpty else { return [] }
        if containsLatinOrDigit(text) {
            return measuredLineRanges(for: text, font: font, containerWidth: containerWidth)
        }
        return koreanLineRanges(for: text, targetCharsPerLine: targetCharsPerLine)
    }

    /// 선택 모드(`SelectableVerseTextView`)의 자동 줄바꿈을 표시 모드(`lineRanges(...)`)와
    /// 일치시킨 텍스트. `lineRanges(...)` 경계 사이에 건너뛴 구분자(`koreanLineRanges`가
    /// `lineStart = position + 1`로 스킵하는 한 글자 — 설계상 항상 공백)가 있으면 U+2028(라인
    /// 구분자)로 **치환**해 강제로 줄을 바꾼다. 삽입이 아니라 치환이라 글자 수·인덱스가 유지되므로,
    /// 이 문자열에서 얻은 `selectedRange`가 원본 `text`에서도 같은 위치를 가리킨다.
    ///
    /// 라틴/혼합 절(`measuredLineRanges`)은 줄 끝 공백이 이미 앞 줄 범위에 포함되어 건너뛴
    /// 구분자가 없고, 같은 폰트·폭·`lineFragmentPadding = 0`의 `UITextView`/`NSTextView`가 같은
    /// TextKit 엔진으로 줄바꿈하므로 치환이 필요 없다.
    static func forcedBreakText(from text: String, font: PlatformFont, containerWidth: CGFloat, targetCharsPerLine: Int = 23) -> String {
        let ranges = lineRanges(for: text, font: font, containerWidth: containerWidth, targetCharsPerLine: targetCharsPerLine)
        guard ranges.count > 1 else { return text }
        let mutable = NSMutableString(string: text)
        for i in 0..<(ranges.count - 1) {
            let currentEnd = ranges[i].location + ranges[i].length
            let nextStart = ranges[i + 1].location
            guard nextStart > currentEnd, currentEnd < mutable.length else { continue }
            mutable.replaceCharacters(in: NSRange(location: currentEnd, length: 1), with: "\u{2028}")
        }
        return mutable as String
    }

    /// `VerseTextSelectionPopover` 전용 — 한자 주석을 `rangeEnd` 위치에 "(한자)"로 삽입한 평범한
    /// `String`을 돌려준다(`attributedContentWithInlineAnnotations`와 같은 삽입 규칙). 표시·복사
    /// 텍스트에 한자가 그대로 포함되게 하려는 것이다. 반대로 `selectionModeAttributedText`
    /// (`VerseZoomView`의 선택 모드)는 형광펜/메모의 `rangeStart`/`rangeEnd`가 원본
    /// `verse.content` 기준 오프셋으로 저장돼야 해서 텍스트 길이를 바꾸지 않고 단어 색만
    /// 바꾸므로, 용도가 달라 두 함수는 공유하지 않는다.
    ///
    /// 삽입은 오프셋 내림차순으로 처리한다 — 뒤에서부터 끼워야 아직 처리하지 않은 앞쪽
    /// 오프셋이 밀리지 않는다.
    static func plainTextWithInlineHanja(text: String, hanjaWords: [HanjaWordAnnotation]) -> String {
        guard !hanjaWords.isEmpty else { return text }
        let insertions = hanjaWords
            .map { (offset: $0.rangeEnd, hanja: $0.hanja) }
            .sorted { $0.offset > $1.offset }
        var result = text
        for entry in insertions {
            let nsRange = NSRange(location: entry.offset, length: 0)
            guard let index = Range(nsRange, in: result)?.lowerBound else { continue }
            result.insert(contentsOf: "(\(entry.hanja))", at: index)
        }
        return result
    }

    static func selectionModeAttributedText(
        text: String, highlights: [VerseHighlight], phraseNotes: [VersePhraseNote],
        // 구간이 지정된 관주 표현에 밑줄을 그린다(아래 `crossReferences` 사용부 참고).
        crossReferences: [VerseCrossReference] = [],
        // 한자 단어를 표시 모드(`AnnotatedVerseFlowView`)와 같은 색으로 표시한다.
        hanjaWords: [HanjaWordAnnotation] = [],
        // false면 `forcedBreakText`를 건너뛰고 원본 `text`를 그대로 쓴다. 표시 모드와 줄바꿈을
        // 맞출 필요가 없는 호출부(`VerseTextSelectionPopover`)에서 한글 텍스트에 U+2028이 끼어드는
        // 것을 막기 위한 것 — 기본값 true는 줄바꿈 일치가 필요한 `VerseZoomView` 동작을 유지한다.
        matchDisplayModeLineBreaks: Bool = true,
        font: PlatformFont, textColor: PlatformColor, containerWidth: CGFloat, targetCharsPerLine: Int = 23
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = font.typographicLineHeight * (2.3 - 1)
        let displayText = matchDisplayModeLineBreaks
            ? forcedBreakText(from: text, font: font, containerWidth: containerWidth, targetCharsPerLine: targetCharsPerLine)
            : text
        let result = NSMutableAttributedString(
            string: displayText,
            attributes: [.font: font, .foregroundColor: textColor, .paragraphStyle: paragraph]
        )

        let lines = buildLines(
            text: text, highlights: highlights, phraseNotes: phraseNotes, crossReferences: crossReferences,
            hanjaWords: hanjaWords, font: font, containerWidth: containerWidth, targetCharsPerLine: targetCharsPerLine
        )
        for line in lines {
            for segment in line.segments {
                // `forcedBreakText`는 치환만 하고 인덱스를 바꾸지 않으므로 세그먼트 범위가 `displayText`에서도 유효하다.
                let range = segment.range
                guard range.length > 0, range.location + range.length <= result.length else { continue }

                if let highlight = segment.highlight {
                    switch highlight.style {
                    case .highlight:
                        let tag = HighlightColorTag(rawValue: highlight.colorTag ?? "") ?? .yellow
                        result.addAttribute(
                            .backgroundColor,
                            value: tag.platformColor.withAlphaComponent(tag.backgroundOpacity),
                            range: range
                        )
                    case .mark:
                        result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                        result.addAttribute(.underlineColor, value: PlatformColor.systemOrange, range: range)
                    }
                }
                // 관주가 등록된 표현은 "표시"(`.mark`)와 같은 주황 밑줄로 자동 표시한다.
                // `.mark`와 독립적이며 중복 적용은 무해하다.
                if segment.hasCrossReference {
                    result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                    result.addAttribute(.underlineColor, value: PlatformColor.systemOrange, range: range)
                }
                // 메모 글자색(아래)이 우선하도록 먼저 적용한다(`AnnotatedVerseFlowView.segmentView`와 같은 우선순위: 메모 > 한자).
                if segment.hasHanja {
                    result.addAttribute(.foregroundColor, value: PlatformColor(hanjaWordTextColor), range: range)
                    // 메모 색(아래)이 이 글자색을 덮어도 굵기로 한자 단어임이 남는다(`boldVariant` 참고).
                    result.addAttribute(.font, value: boldVariant(of: font), range: range)
                }
                if !segment.noteIDs.isEmpty {
                    result.addAttribute(.foregroundColor, value: phraseNoteTextPlatformColor, range: range)
                }
            }
        }
        return result
    }

    /// `lineBreakPositions`의 "지점 목록"을 "줄 범위 목록"으로 바꾼다. 지점의 공백 한 글자는
    /// 줄 사이의 구분자로 어느 줄에도 속하지 않는다(줄 끝에 보이지 않는 공백이 남는 것을 방지).
    /// SwiftUI `Text`는 줄마다 따로 그려 U+2028 치환이 필요 없다.
    static func koreanLineRanges(for text: String, targetCharsPerLine: Int = 23) -> [NSRange] {
        let ns = text as NSString
        let positions = lineBreakPositions(in: text, targetCharsPerLine: targetCharsPerLine)
        guard !positions.isEmpty else { return [NSRange(location: 0, length: ns.length)] }
        var ranges: [NSRange] = []
        var lineStart = 0
        for position in positions {
            ranges.append(NSRange(location: lineStart, length: position - lineStart))
            lineStart = position + 1
        }
        ranges.append(NSRange(location: lineStart, length: ns.length - lineStart))
        return ranges
    }

    /// 라틴/혼합 절 전용 — 어떤 뷰에도 연결하지 않는 임시 `NSLayoutManager`로 실제 폭 기준
    /// 줄바꿈 지점을 측정한다. 화면에 그리지 않아 TextKit 표시 좌표 문제와 무관하다.
    static func measuredLineRanges(for text: String, font: PlatformFont, containerWidth: CGFloat) -> [NSRange] {
        let ns = text as NSString
        guard containerWidth > 0 else { return [NSRange(location: 0, length: ns.length)] }
        let textStorage = NSTextStorage(string: text, attributes: [.font: font])
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: containerWidth, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        layoutManager.ensureLayout(for: container)

        var ranges: [NSRange] = []
        let glyphCount = layoutManager.numberOfGlyphs
        guard glyphCount > 0 else { return [NSRange(location: 0, length: ns.length)] }
        layoutManager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: glyphCount)) { _, _, _, glyphRange, _ in
            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            guard charRange.length > 0 else { return }
            ranges.append(charRange)
        }
        return ranges.isEmpty ? [NSRange(location: 0, length: ns.length)] : ranges
    }

    /// 표시 레이어(`AnnotatedVerseFlowView`)가 한 줄을 `HStack`으로 그릴 때 쓰는 최소 단위 —
    /// 경계점으로 나눈 "겹치지 않는 조각" 하나와 그 조각을 덮는 형광펜(있다면), 그 조각을
    /// 앵커로 삼는 메모 id 목록. `.mark`(밑줄)는 배경이 아니므로 `highlight`를 그대로 참조해
    /// 뷰가 스타일을 고른다.
    struct VerseTextSegment: Identifiable {
        let id = UUID()
        let range: NSRange
        let text: String
        let highlight: VerseHighlight?
        let noteIDs: [UUID]
        /// 이 조각이 구간 지정이 있는 `VerseCrossReference`(절 전체 관주는 대상 아님)에 덮여
        /// 있는지. `highlight`와 독립적이라 별도 필드로 둔다 — 형광펜 유무와 무관하게 밑줄을 그린다.
        let hasCrossReference: Bool
        /// 이 조각이 한자 단어 범위에 통째로 덮여 있는지. `HanjaWordAnnotation` 오프셋은 이미
        /// 원문 기준 UTF-16 절대 위치라 관주/형광펜과 달리 `anchorText` 재탐색이 필요 없다.
        let hasHanja: Bool
    }

    /// 시각적 줄 하나 — 그 줄의 세그먼트들과 그 줄에 앵커(시작 위치)를 둔 메모 목록. 메모가
    /// 다음 줄까지 걸쳐도 시작 위치가 있는 줄에만 속해 메모 박스가 중복 표시되지 않는다.
    struct VerseLine: Identifiable {
        let id = UUID()
        let range: NSRange
        let segments: [VerseTextSegment]
        let notes: [VersePhraseNote]
    }

    /// 절 텍스트 + 주석을 표시 레이어가 그릴 `[VerseLine]`로 조립한다. `lineRanges(...)`로 줄을
    /// 나눈 뒤 줄 범위 안에서 형광펜/메모/관주/한자 경계점으로 다시 쪼갠다(`attributedContent`와 같은 원리).
    static func buildLines(
        text: String, highlights: [VerseHighlight], phraseNotes: [VersePhraseNote],
        // 구간이 지정된 관주만 밑줄 대상이다 — 절 전체 관주(`rangeStart`/`rangeEnd`/`anchorText`가 nil)는 밑줄 그을 표현이 없다.
        crossReferences: [VerseCrossReference] = [],
        // 관주/형광펜과 같은 경계점 분해에 참여한다(아래 `resolvedHanjaRanges`).
        hanjaWords: [HanjaWordAnnotation] = [],
        font: PlatformFont, containerWidth: CGFloat, targetCharsPerLine: Int = 23
    ) -> [VerseLine] {
        let full = text as NSString
        let lines = lineRanges(for: text, font: font, containerWidth: containerWidth, targetCharsPerLine: targetCharsPerLine)

        struct ResolvedHighlight { let range: NSRange; let highlight: VerseHighlight }
        let resolvedHighlights: [ResolvedHighlight] = highlights.compactMap { highlight in
            guard let range = resolvedRange(
                start: highlight.rangeStart, end: highlight.rangeEnd, anchorText: highlight.anchorText, in: full
            ), range.length > 0 else { return nil }
            return ResolvedHighlight(range: range, highlight: highlight)
        }
        struct ResolvedNote { let range: NSRange; let note: VersePhraseNote }
        let resolvedNotes: [ResolvedNote] = phraseNotes.compactMap { note in
            guard let range = resolvedRange(
                start: note.rangeStart, end: note.rangeEnd, anchorText: note.anchorText, in: full
            ), range.length > 0 else { return nil }
            return ResolvedNote(range: range, note: note)
        }
        let resolvedCrossReferenceRanges: [NSRange] = crossReferences.compactMap { reference in
            guard let start = reference.rangeStart, let end = reference.rangeEnd,
                  let anchor = reference.anchorText else { return nil }
            guard let range = resolvedRange(start: start, end: end, anchorText: anchor, in: full),
                  range.length > 0 else { return nil }
            return range
        }
        // 오프셋이 이미 원문 기준 절대 위치라 `anchorText` 재탐색 없이 쓰되, 본문 길이와 안 맞는 경우에 대비해 범위만 검증한다.
        let resolvedHanjaRanges: [NSRange] = hanjaWords.compactMap { word in
            let range = NSRange(location: word.rangeStart, length: word.rangeEnd - word.rangeStart)
            guard range.length > 0, range.location >= 0, range.location + range.length <= full.length else { return nil }
            return range
        }

        return lines.map { lineRange in
            var boundaries = Set<Int>([lineRange.location, lineRange.location + lineRange.length])
            for resolved in resolvedHighlights {
                let clipped = NSIntersectionRange(resolved.range, lineRange)
                guard clipped.length > 0 else { continue }
                boundaries.insert(clipped.location)
                boundaries.insert(clipped.location + clipped.length)
            }
            for resolved in resolvedNotes {
                let clipped = NSIntersectionRange(resolved.range, lineRange)
                guard clipped.length > 0 else { continue }
                boundaries.insert(clipped.location)
                boundaries.insert(clipped.location + clipped.length)
            }
            for range in resolvedCrossReferenceRanges {
                let clipped = NSIntersectionRange(range, lineRange)
                guard clipped.length > 0 else { continue }
                boundaries.insert(clipped.location)
                boundaries.insert(clipped.location + clipped.length)
            }
            for range in resolvedHanjaRanges {
                let clipped = NSIntersectionRange(range, lineRange)
                guard clipped.length > 0 else { continue }
                boundaries.insert(clipped.location)
                boundaries.insert(clipped.location + clipped.length)
            }
            let sortedBoundaries = boundaries.sorted()

            var segments: [VerseTextSegment] = []
            for index in 0..<max(0, sortedBoundaries.count - 1) {
                let segStart = sortedBoundaries[index]
                let segEnd = sortedBoundaries[index + 1]
                guard segEnd > segStart else { continue }
                let segRange = NSRange(location: segStart, length: segEnd - segStart)
                let coveringHighlight = resolvedHighlights.first {
                    $0.range.location <= segStart && $0.range.location + $0.range.length >= segEnd
                }?.highlight
                let noteIDs = resolvedNotes.filter {
                    $0.range.location <= segStart && $0.range.location + $0.range.length >= segEnd
                }.map { $0.note.id }
                let hasCrossReference = resolvedCrossReferenceRanges.contains {
                    $0.location <= segStart && $0.location + $0.length >= segEnd
                }
                let hasHanja = resolvedHanjaRanges.contains {
                    $0.location <= segStart && $0.location + $0.length >= segEnd
                }
                segments.append(VerseTextSegment(
                    range: segRange, text: full.substring(with: segRange),
                    highlight: coveringHighlight, noteIDs: noteIDs, hasCrossReference: hasCrossReference,
                    hasHanja: hasHanja
                ))
            }

            // 왼쪽→오른쪽 순서로 정렬해 "먼저 나오는 표현의 메모가 위에" 쌓이게 한다(`AnnotatedVerseFlowView`가 이 순서를 그대로 쓴다).
            let notesStartingHere = resolvedNotes.filter {
                $0.range.location >= lineRange.location && $0.range.location < lineRange.location + lineRange.length
            }.sorted { $0.range.location < $1.range.location }.map(\.note)
            return VerseLine(range: lineRange, segments: segments, notes: notesStartingHere)
        }
    }

    /// 저장된 오프셋이 지금 본문과 안 맞으면(번역본 데이터가 고쳐진 경우) `anchorText`로 다시 찾는
    /// "자가 치유". 못 찾으면 nil. `VerseAnnotations.swift` 상단 주석 참고.
    static func resolvedRange(start: Int, end: Int, anchorText: String, in full: NSString) -> NSRange? {
        let candidate = NSRange(location: start, length: max(0, end - start))
        if candidate.location >= 0,
           candidate.location + candidate.length <= full.length,
           full.substring(with: candidate) == anchorText {
            return candidate
        }
        guard !anchorText.isEmpty else { return nil }
        let found = full.range(of: anchorText)
        if found.location != NSNotFound { return found }
        // `forcedBreakText`의 강제 줄바꿈은 공백을 U+2028로 길이 보존 치환하므로, 앵커 텍스트 내부의
        // 공백이 치환된 본문에서는 위 두 시도가 모두 실패한다. U+2028을 공백으로 되돌린 정규화 사본에서
        // 앵커를 찾고, 치환이 길이를 바꾸지 않으므로 그 인덱스를 원본 `full`에 그대로 재사용한다.
        guard full.contains("\u{2028}") else { return nil }
        let normalized = full.replacingOccurrences(of: "\u{2028}", with: " ") as NSString
        guard normalized.length == full.length else { return nil }
        let normalizedFound = normalized.range(of: anchorText)
        return normalizedFound.location == NSNotFound ? nil : normalizedFound
    }
}
