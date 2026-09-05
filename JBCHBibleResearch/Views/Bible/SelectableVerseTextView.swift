//
//  SelectableVerseTextView.swift
//  JBCHBibleResearch
//
//  [2026-08-08 신설] "구절 확대보기"(VerseZoomView.swift) 전용 — 사용자가 드래그로
//  구절 텍스트의 정확한 시작/끝 위치를 고를 수 있어야 한다. README "이어서 16"
//  설계 논의에서 확인한 대로, SwiftUI의 `Text(...).textSelection(.enabled)`는
//  드래그 선택 UI 자체는 공짜로 제공하지만 "정확히 몇 번째~몇 번째 글자를
//  골랐는지"를 코드로 읽어올 방법이 없다(애플이 그 API를 공개하지 않음) — 우리는
//  그 정확한 범위가 있어야 `VerseHighlight`/`VerseCrossReference`/`VersePhraseNote`의
//  rangeStart/rangeEnd를 저장할 수 있으므로, `UITextView`(iOS)/`NSTextView`(macOS)를
//  직접 감싸 `selectedRange`를 읽는다.
//
//  `selectedRange`는 UTF-16 단위 `NSRange`다 — `VerseAnnotations.swift` 상단
//  주석이 명시한 저장 규칙과 정확히 같은 단위라 변환 없이 그대로 쓸 수 있다.
//
//  [2026-08-11 8차 수정, 확대보기 전면 재설계] 사용자가 제공한 설계 문서를 따라
//  확대보기를 "표시 모드"(`AnnotatedVerseFlowView`, 순수 SwiftUI)와 "선택 모드"
//  (이 파일)로 분리했다 — 배경은 `VerseAnnotationRenderer.swift` 상단
//  [2026-08-11 8차 수정] 주석 참고. 이 파일은 그 분리로 역할이 크게 줄었다:
//  기존엔 형광펜/표시/메모를 실제로 그리는 것(배경색·밑줄·점선 박스 오버레이),
//  메모가 있는 줄만 줄간격을 늘리는 것, 우클릭 메뉴로 기존 주석을 취소/수정하는
//  것까지 전부 이 뷰(정확히는 그 내부 TextKit `Coordinator`)의 책임이었다 —
//  그 결과 `NSLayoutManagerDelegate` 줄간격 주입, `TightHighlightLayoutManager`
//  배경 사각형 재계산, TextKit 글리프 좌표와 SwiftUI 좌표를 손으로 맞추는
//  코드가 계속 쌓였고, 그 과정에서 무한 재귀 크래시·재레이아웃 미반영·좌표
//  오차 같은 버그가 여러 라운드에 걸쳐 반복됐다(README "이어서 34~39" 참고).
//
//  이제 이 뷰가 화면에 뜨는 시점은 사용자가 새 형광펜/표시/메모/관주를 만들려고
//  텍스트를 드래그로 고르는 그 순간뿐이다 — 그 순간엔 기존 주석을 "예쁘게"
//  보여줄 필요가 없다(선택이 끝나면 곧바로 표시 모드로 돌아가 `AnnotatedVerseFlowView`
//  가 다시 보여준다). 그래서 이 뷰는 서식 없는 평범한 텍스트만 그리고, 오직
//  `selectedRange`를 정확히 읽어 오는 것 하나에만 집중한다 — 재귀 위험이 있는
//  델리게이트도, 손으로 계산하는 좌표도 전혀 없다.
//
//  [2026-08-11 10차 수정] 사용자 요청 — "선택모드의 한 라인에 들어가는 텍스트를
//  표시모드와 동일하게 일치시킬 것(줄바꿈까지). 줄 간격을 2.3으로 할 것."
//  줄바꿈은 `VerseAnnotationRenderer.forcedBreakText(...)`(그 파일 상단
//  [2026-08-11 10차 수정] 주석 참고)로 표시 모드와 같은 `lineRanges(...)`
//  경계를 그대로 강제한다. 줄 간격은 `RichTextEditor.swift`가 이미 쓰는
//  "배수 → 포인트" 환산 관용식(`typographicLineHeight * (배수 - 1)`)을 그대로
//  재사용해 `NSParagraphStyle.lineSpacing`으로 적용한다 — 예전(README "이어서
//  30") "구절 확대보기" 줄간격 2.3 요구사항과 같은 계산식이다.
//
//  [2026-08-11 11차 수정] 사용자 요청 — "선택모드에서도 형광펜, 밑줄, 메모가
//  있는 텍스트(파란색)을 표시할 것." 메모 "내용"(박스/화살표)은 여전히 표시
//  모드 전용이지만, 형광펜 배경·표시(밑줄)·메모가 달린 텍스트의 파란 글자색은
//  `VerseAnnotationRenderer.buildLines(...)`가 표시 모드에서도 이미 쓰는
//  세그먼트 분해(형광펜/메모 경계점 기준으로 겹치지 않게 쪼갠 조각들)를 그대로
//  재사용해 `NSAttributedString` 속성으로 입힌다 — 별도의 좌표 계산이나 겹침
//  판정 로직을 새로 만들 필요가 없다(이미 검증된 로직 재사용).
//
//  [2026-08-11 12차 수정] 사용자 보고 — "줄 간격만큼 형광펜 영역이 늘어나지
//  않도록, 텍스트 부분만 칠해질 수 있도록." 기본 `NSLayoutManager`는
//  `.backgroundColor` 속성이 걸린 구간을 그 줄의 "줄 프래그먼트 사용 영역"
//  기준으로 채우는데, 이 사각형의 높이는 `paragraphStyle.lineSpacing`(바로
//  위 "이어서 42"에서 2.3으로 추가한 값)으로 늘어난 줄 간격까지 포함한다 —
//  이 프로젝트가 "이어서 39"에서 표시 모드의 형광펜/메모 위치 버그의 근본
//  원인으로 이미 확인한 것과 근본적으로 같은 부류의 문제다. 아래
//  `TightBackgroundLayoutManager`가 그때 검증한 것과 같은 원리(글리프의
//  베이스라인 위치 + 폰트 ascender/descender로 "실제 글자 높이"만 계산)를
//  재사용해 배경 채우기 자체를 가로챈다 — "그리기"만 가로채는 안전한
//  개입이라(레이아웃 자체를 바꾸는 예전의 `NSLayoutManagerDelegate` 방식과
//  달리 무한 재귀 위험이 없다), 이 커스텀 레이어를 쓰려면 `UITextView`/
//  `NSTextView`를 기본 생성자 대신 `NSTextStorage`/`NSTextContainer`를 직접
//  엮어 만들어야 한다(아래 `makeUIView`/`makeNSView`).
//

import SwiftUI
import BibleResearchModels
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// 세로 방향으로 "줄 프래그먼트 사용 영역"(줄 간격 포함) 대신 글자 자체의
/// 타이트한 박스만 배경색으로 채우는 `NSLayoutManager`. 오직 이 파일의 선택
/// 모드 미리보기에서만 쓰인다 — 표시 모드(`AnnotatedVerseFlowView`)는 애초에
/// TextKit을 전혀 쓰지 않아 이 문제 자체가 없다.
///
/// ⚠️ 실패에 안전하다 — 텍스트 컨테이너나 참조 폰트를 못 찾으면 기본 구현
/// (`super`)으로 그대로 넘긴다. 최악의 경우에도 "줄간격만큼 늘어난 예전
/// 모습"으로 돌아갈 뿐 그리기 자체가 실패하거나 크래시하지 않는다.
final class TightBackgroundLayoutManager: NSLayoutManager {
    /// 세로 타이트 박스 계산에 쓸 폰트 — 선택 모드는 절 전체가 한 폰트라
    /// 매번 `textStorage`를 다시 조회할 필요 없이 호출부가 미리 넣어 둔다.
    var referenceFont: PlatformFont?

    // [2026-09-05 수정] 사용자 보고 — 우클릭 "선택"(`VerseTextSelectionPopover`,
    // 이 파일의 `SelectableVerseTextView`를 재사용)에서 텍스트를 드래그로
    // 선택하는 동안 한글 번역본에서만 선택 영역이 아주 빠르게 깜박임(영문
    // 번역본은 정상). 원인 분석: `fillBackgroundRectArray`는 이 텍스트뷰의
    // *모든* 배경 채우기 요청을 가로채는데, 그 요청에는 (1) 실제 하이라이트
    // (`.backgroundColor` 속성이 걸린 구간 — `VerseAnnotationRenderer.
    // selectionModeAttributedText`의 `.highlight` 케이스에서만 설정됨. 실제로
    // `VerseTextSelectionPopover`는 highlights를 아예 빈 배열로 넘기므로 그
    // 화면에선 (1)이 절대 발생하지 않는다) 뿐 아니라 (2) OS 기본 드래그-선택
    // 강조 자체도 포함된다 — 지금까지 이 타이트-사각형 재계산이 (2)에도
    // 무조건 적용되고 있었다.
    //
    // 한글 텍스트는 `VerseAnnotationRenderer.forcedBreakText`가 표시 모드와
    // 줄바꿈 위치를 맞추려고 특정 공백을 U+2028(줄 구분자)로 치환해 넣는데
    // (영문/숫자 포함 텍스트는 `containsLatinOrDigit` 분기로 이 치환이 전혀
    // 없다), 드래그로 그 경계를 넘나들 때마다 `enumerateLineFragments`/
    // `enumerateEnclosingRects`가 매 리드로우마다 살짝 다른 사각형 집합을
    // 계산해 선택 영역이 깜박이는 것으로 추정된다.
    //
    // 이 재계산은 애초에 (1)(실제 하이라이트)을 "줄간격 없이 타이트하게"
    // 그리기 위해 만든 것(위 [2026-08-11 12차 수정] 주석 참고)이므로,
    // `.backgroundColor` 속성이 실제로 걸려 있는 구간에만 적용하고 그 외
    // (선택 강조 등)는 시스템 기본 동작(`super`)에 맡긴다 — 기존 하이라이트
    // 렌더링(`VerseZoomView`의 형광펜 표시)은 그대로 유지되고, 하이라이트가
    // 없는 순수 드래그 선택만 기본 동작으로 되돌아간다.
    //
    // ⚠️ 미검증 — 이 세션은 Swift 컴파일러가 없어 직접 빌드/실행 확인이
    // 불가능하다. 코드 분석에 근거한 가설이며 실제 기기에서 반드시 재확인이
    // 필요하다.
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

        // `buildLines(...)`가 애초에 줄 단위로 세그먼트를 나눠 주므로, 여기
        // 들어오는 `charRange` 하나가 여러 줄에 걸치는 일은 실질적으로 없다
        // — 그래도 안전하게 줄 단위로 한 번 더 나눈다(`enumerateLineFragments`).
        enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, lineGlyphRange, _ in
            let clipped = NSIntersectionRange(lineGlyphRange, glyphRange)
            guard clipped.length > 0 else { return }
            // "이어서 39"에서 검증한 것과 같은 식 — `location(forGlyphAt:).y`는
            // 그 글리프가 속한 줄 프래그먼트의 원점 기준 상대값이므로, 줄
            // 프래그먼트 원점(`lineRect.origin.y`)을 더해야 절대 좌표의
            // 베이스라인이 나온다.
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
    /// [2026-08-11 10차 수정] `VerseAnnotationRenderer.lineRanges(...)`가 줄을
    /// 나눌 때 쓰는 것과 정확히 같은 폭 — 호출부(`VerseZoomView`)가 표시
    /// 모드에도 넘기는 `effectiveTextWidth`와 동일한 값을 넘겨야 두 모드의
    /// 줄바꿈이 어긋나지 않는다.
    let containerWidth: CGFloat
    /// [2026-08-12 추가] 세로/가로 모드마다 다른 줄당 글자수(사용자 요청) —
    /// 표시 모드(`AnnotatedVerseFlowView`)와 정확히 같은 값을 받아야 두 모드의
    /// 줄바꿈이 어긋나지 않는다(위 `containerWidth` 주석과 같은 원칙).
    let targetCharsPerLine: Int
    /// [2026-08-11 11차 수정] 선택 모드에서도 형광펜/표시/메모 글자색을 함께
    /// 보여 달라는 요청 — 메모 "내용"(박스/화살표)은 여전히 표시 모드
    /// 전용이지만, 어떤 표현에 이미 주석이 있는지는 선택 모드에서도 알 수
    /// 있어야 드래그로 새 구간을 고를 때 기존 주석과 겹치는지 가늠하기
    /// 쉽다.
    let highlights: [VerseHighlight]
    let phraseNotes: [VersePhraseNote]
    /// [2026-08-12 추가] 사용자 요청 — "특정 텍스트를 선택하여 관주를 넣는
    /// 부분에 현재 밑줄처럼 표시할 것." 표시 모드(`AnnotatedVerseFlowView`)와
    /// 같은 신호를 선택 모드에도 넘겨, 드래그로 새 구간을 고를 때도 이미 관주가
    /// 걸린 표현이 어디인지 밑줄로 보인다.
    let crossReferences: [VerseCrossReference]
    /// [2026-08-15 추가] 사용자 요청 — "확대보기 성경구절 수정 - 한자가 있는
    /// 단어는 색깔로 표현해 줄 것." 표시 모드(`AnnotatedVerseFlowView`)와
    /// 같은 신호를 선택 모드에도 넘겨 시각적으로 어긋나지 않게 한다.
    var hanjaWords: [HanjaWordAnnotation] = []
    /// [2026-09-05 신설] 사용자 보고 — 우클릭 "선택"(`VerseTextSelectionPopover`)
    /// 에서 한글 번역본만 드래그 선택 중 빠르게 깜박임(영문은 정상). 원인과
    /// 해결은 `VerseAnnotationRenderer.selectionModeAttributedText`의 같은
    /// 이름 파라미터 주석 참고 — 요약하면, 이 값이 `true`(기본값)면 기존과
    /// 똑같이 선택 모드 줄바꿈을 표시 모드와 맞추려고 한글 텍스트에 보이지
    /// 않는 U+2028을 끼워 넣고(`VerseZoomView`가 필요로 하는 동작, 그대로
    /// 유지), `false`면 그 치환을 건너뛰어 `NSTextView`/`UITextView`가 영문과
    /// 똑같이 자기 폭 기준으로 자연스럽게 줄바꿈한다(표시 모드를 같이 보여줄
    /// 필요가 없는 `VerseTextSelectionPopover` 전용).
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

    // [2026-08-11 12차 수정] `TightBackgroundLayoutManager`(파일 상단)를 쓰려면
    // `UITextView()` 기본 생성자(자체 기본 레이아웃 매니저를 내부적으로
    // 만든다) 대신, `NSTextStorage`/`NSTextContainer`를 직접 엮어
    // `UITextView(frame:textContainer:)`로 만들어야 한다 — 그래야 우리가 만든
    // 레이아웃 매니저가 실제로 쓰인다. 이후 `.attributedText` 세터는(공식
    // 문서 기준으로도) 이 `textStorage`를 그대로 바꿔치기하지 않고 내용만
    // 갱신하므로, 커스텀 레이아웃 매니저 연결은 계속 유지된다.
    //
    // ⚠️ `textStorage`/`layoutManager`는 `Coordinator`가 강한 참조로 붙들고
    // 있다(아래) — TextKit 내부 그래프의 정확한 강/약 참조 방향을 단정할
    // 근거가 없어(문서화가 애매하고 이 프로젝트에서 직접 검증할 수도 없다),
    // "로컬 변수로만 만들면 나중에 해제돼 크래시할 수도 있다"는 위험을
    // 아예 없애는 쪽을 택했다 — `Coordinator`는 SwiftUI가 이 표현 뷰의
    // 수명 내내 들고 있어 준다.
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

    // [2026-09-05 수정] 사용자 요청 — macOS 쪽 드래그 선택 깜박임 수정을
    // "iOS도 동일하게 반영하라." macOS `updateNSView`와 정확히 같은 원인·
    // 같은 수정(아래 `Coordinator.lastReportedSelectedRange` 참고) — 이
    // 코드가 macOS `NSViewRepresentable`과 완전히 대칭 구조라 같은 레이스
    // 컨디션이 이론상 그대로 있었다(사용자가 이번에 iOS에서도 명시적으로
    // 재현/보고하지 않았어도 코드 구조가 동일하면 동일한 결함이 있다는 것은
    // 추측이 아니다).
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

    // iOS 16+ — `UIViewRepresentable`이 SwiftUI 레이아웃 시스템에 실제 컨텐츠
    // 높이를 알려주는 공식 지점. 이게 없으면 `isScrollEnabled = false`인
    // `UITextView`는 SwiftUI 쪽에서 크기를 못 잡아 줄바꿈된 본문이 잘려 보인다.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fitting.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SelectableVerseTextView
        /// [2026-08-11 12차 수정] `makeUIView` 상단 주석 참고 — 이 두 객체를
        /// `Coordinator`가 강하게 붙들고 있어야 텍스트 뷰가 살아 있는 동안
        /// 절대 해제되지 않는다는 게 보장된다.
        let textStorage = NSTextStorage()
        let layoutManager = TightBackgroundLayoutManager()
        /// [2026-09-05 신설] macOS `Coordinator.lastReportedSelectedRange`와
        /// 같은 이유 — 위 `updateUIView` 주석 참고.
        var lastReportedSelectedRange: NSRange?

        init(_ parent: SelectableVerseTextView) {
            self.parent = parent
            super.init()
            textStorage.addLayoutManager(layoutManager)
        }

        // [2026-08-09 수정] 사용자 보고 — "Modifying state during view update,
        // this will cause undefined behavior." `updateUIView`가 `uiView.
        // selectedRange = selectedRange`로 프로그램적으로 선택을 맞출 때도 이
        // 델리게이트가 동기적으로 다시 호출될 수 있는데, 그 순간이 SwiftUI가
        // 아직 뷰를 업데이트하는 도중이면 `@Binding` 값을 그 자리에서 바로
        // 바꾸는 게 정의되지 않은 동작이 된다 — 다음 런루프 틱으로 미뤄
        // "뷰 업데이트가 끝난 뒤"에 상태를 바꾸는 표준적인 우회법을 쓴다.
        func textViewDidChangeSelection(_ textView: UITextView) {
            let newRange = textView.selectedRange
            // [2026-09-05 신설] macOS 쪽과 같은 이유 — 위 `updateUIView`
            // 주석 참고.
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
    /// [2026-08-11 10차 수정] 위 iOS 쪽 `containerWidth` 주석과 같은 이유.
    let containerWidth: CGFloat
    /// [2026-08-12 추가] 위 iOS 쪽 `targetCharsPerLine` 주석과 같은 이유.
    let targetCharsPerLine: Int
    /// [2026-08-11 11차 수정] 위 iOS 쪽 `highlights`/`phraseNotes` 주석과 같은 이유.
    let highlights: [VerseHighlight]
    let phraseNotes: [VersePhraseNote]
    /// [2026-08-12 추가] 위 iOS 쪽 `crossReferences` 주석과 같은 이유.
    let crossReferences: [VerseCrossReference]
    /// [2026-08-15 추가] 사용자 요청 — "확대보기 성경구절 수정 - 한자가 있는
    /// 단어는 색깔로 표현해 줄 것." 표시 모드(`AnnotatedVerseFlowView`)와
    /// 같은 신호를 선택 모드에도 넘겨 시각적으로 어긋나지 않게 한다.
    var hanjaWords: [HanjaWordAnnotation] = []
    /// [2026-09-05 신설] 사용자 보고 — 우클릭 "선택"(`VerseTextSelectionPopover`)
    /// 에서 한글 번역본만 드래그 선택 중 빠르게 깜박임(영문은 정상). 원인과
    /// 해결은 `VerseAnnotationRenderer.selectionModeAttributedText`의 같은
    /// 이름 파라미터 주석 참고 — 요약하면, 이 값이 `true`(기본값)면 기존과
    /// 똑같이 선택 모드 줄바꿈을 표시 모드와 맞추려고 한글 텍스트에 보이지
    /// 않는 U+2028을 끼워 넣고(`VerseZoomView`가 필요로 하는 동작, 그대로
    /// 유지), `false`면 그 치환을 건너뛰어 `NSTextView`/`UITextView`가 영문과
    /// 똑같이 자기 폭 기준으로 자연스럽게 줄바꿈한다(표시 모드를 같이 보여줄
    /// 필요가 없는 `VerseTextSelectionPopover` 전용).
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

    // [2026-08-11 12차 수정] 위 iOS 쪽 `makeUIView` 주석과 같은 이유 —
    // `TightBackgroundLayoutManager`를 쓰려면 `NSTextView()` 기본 생성자
    // 대신 `NSTextStorage`/`NSTextContainer`를 직접 엮어야 한다.
    // `textStorage`/`layoutManager`는 `Coordinator`가 강하게 붙들고 있다.
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

    // [2026-09-05 수정] 사용자 보고(맥OS) — "구절 클릭 - 마우스 오른쪽
    // 버튼 - '선택' - 텍스트를 드래그 하는데 선택된 영역이 계속 깜박거림."
    // 원인: 마우스로 드래그하는 동안 `NSTextView`의 실제 선택 영역은 계속
    // (동기적으로) 앞서 나가는데, 그 변화를 감지한 `textViewDidChangeSelection`
    // (아래 `Coordinator`)은 `DispatchQueue.main.async`로 한 틱 늦게
    // `parent.selectedRange`(바인딩)에 반영한다(그 함수의 주석 참고 — 뷰
    // 업데이트 도중 상태를 바꾸는 정의되지 않은 동작을 피하려고 일부러
    // 늦춘 것). 문제는 이 함수가 그 뒤 다시 불릴 때 "지금 `nsView`의 실제
    // 선택"과 "그 한 틱 전에 넘어온 `selectedRange` 바인딩 값"을 비교해
    // 다르면 무조건 `nsView.setSelectedRange(selectedRange)`로 되돌린다는
    // 점이다 — 사용자가 계속 드래그 중이면 그 사이 `nsView`의 실제 선택이
    // 이미 더 나아가 있으므로, 이 되돌림이 방금 넓어진 선택 영역을 순간적
    // 으로 다시 좁혀 버렸다가 다음 업데이트에서 다시 넓어지는 일이 반복돼
    // "깜박거림"으로 보인다.
    //
    // 고치는 방법은 "이 바인딩 갱신이 `nsView` 스스로 방금 보고한 값을
    // 그대로 돌려받은 것인지"를 구분하는 것이다 — 그런 경우엔 `nsView`가
    // 이미 정확한 최신 선택을 들고 있으므로(드래그가 계속됐다면 그보다 더
    // 나아가 있을 수도 있으므로) 되돌려 쓸 필요가 없다. `Coordinator`가
    // 자신이 마지막으로 내보낸 값을 기억해 뒀다가(`lastReportedSelectedRange`,
    // 아래), 여기로 그 값과 같은 바인딩이 돌아오면 `setSelectedRange`를
    // 건너뛴다 — 반대로 다른 값(예: 화면을 새로 열거나 외부에서 선택을
    // 프로그램적으로 초기화하는 경우)이 들어오면 여전히 정상 반영된다.
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

    // macOS 13+ — 위 iOS 쪽 `sizeThatFits` 주석과 같은 이유.
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
        /// [2026-08-11 12차 수정] 위 iOS 쪽 `Coordinator` 주석과 같은 이유.
        let textStorage = NSTextStorage()
        let layoutManager = TightBackgroundLayoutManager()
        /// [2026-09-05 신설] 위 `updateNSView` 주석 참고 — 이 좌표기가
        /// 마지막으로 바인딩에 내보낸 선택 범위. `nil`이면(아직 한 번도
        /// 사용자가 선택을 바꾼 적 없음) 항상 정상적으로 `setSelectedRange`가
        /// 동작한다.
        var lastReportedSelectedRange: NSRange?

        init(_ parent: SelectableVerseTextView) {
            self.parent = parent
            super.init()
            textStorage.addLayoutManager(layoutManager)
        }

        // [2026-08-09 수정] 위 iOS `Coordinator` 쪽 주석과 같은 이유 —
        // `updateNSView`가 `nsView.setSelectedRange(selectedRange)`로
        // 프로그램적으로 선택을 맞출 때 이 델리게이트가 동기적으로 다시 불릴
        // 수 있고, 그게 SwiftUI 뷰 업데이트 도중이면 `@Binding`을 그 자리에서
        // 바로 바꾸는 게 정의되지 않은 동작이 된다 — 다음 런루프 틱으로 미룬다.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let newRange = textView.selectedRange()
            // [2026-09-05 신설] 위 `updateNSView` 주석 참고 — 이 값을 미리
            // 기록해 둬야, 잠시 뒤 이 값이 다시 `updateNSView`로 돌아왔을 때
            // "내가 방금 보고한 값의 메아리"임을 알아보고 되돌림을 건너뛸 수
            // 있다.
            lastReportedSelectedRange = newRange
            DispatchQueue.main.async { [weak self] in
                self?.parent.selectedRange = newRange
            }
        }
    }
}
#endif
