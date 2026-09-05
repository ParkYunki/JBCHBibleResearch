//
//  VerseAnnotationRenderer.swift
//  JBCHBibleResearch
//
//  [2026-08-08 신설] 구간 주석(형광펜/표시) 렌더링. 평소 읽기 화면
//  (`TranslationColumnView.VerseRow`)에서 절 원문에 배경색/밑줄 span을 입힌
//  `AttributedString`을 만든다 — README "이어서 16" 설계 논의의 "읽기 모드는
//  AttributedString으로" 방침을 구현한다.
//
//  ⚠️ [자가 치유 앵커링] 저장된 rangeStart/rangeEnd로 잘라낸 텍스트가 `anchorText`
//  (주석을 만든 시점의 스냅샷)와 다르면(번역본 데이터가 나중에 고쳐진 경우), 오프셋을
//  무시하고 `anchorText`를 본문 안에서 다시 찾아 그 위치에 스타일을 입힌다. 그마저도
//  못 찾으면(그 표현 자체가 통째로 사라짐) 그 주석은 조용히 건너뛴다 — 잘못된 위치에
//  스타일을 입히는 것보다 안전하다.
//
//  ⚠️ [범위 밖으로 남겨둔 것] "표시"는 밑줄 하나로만 구현했다(README 논의에서
//  사용자가 준 예시가 밑줄이었고, 박스/기호 등 추가 스타일은 실제 필요할 때
//  더 붙이면 된다 — 근거 없는 선제 확장을 피한다).
//

import SwiftUI
import BibleResearchModels
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum VerseAnnotationRenderer {
    /// `highlights`가 비어 있으면 nil을 돌려준다 — 호출부가 그 경우 평범한
    /// `Text(verse.content)`(기존 경로, 훨씬 흔한 케이스)를 그대로 쓰도록 유도해,
    /// 대다수의 절에서는 AttributedString 변환 비용조차 들지 않게 한다.
    ///
    /// ⚠️ [2026-08-09 수정, 버그 원인] 처음엔 `nsAttributedContent(...)`(아래,
    /// `NSMutableAttributedString`)를 만든 뒤 `AttributedString(_:)`로 통째로
    /// 브리징했었다 — 배경색(형광펜)은 이 경로로도 SwiftUI `Text`에 잘 나타났지만,
    /// 밑줄(표시)은 사용자 보고대로 메인 읽기 화면에서 전혀 안 보였다. `Text`가
    /// `NSAttributedString`에서 브리징된 밑줄 속성(`.underlineStyle`/
    /// `.underlineColor`, 특히 `.thick` 같은 변형)을 신뢰성 있게 렌더링하지 않는
    /// 것으로 보인다 — 반면 `VerseZoomView`의 `UITextView`/`NSTextView`는 같은
    /// `NSAttributedString`을 직접 그리므로 브리징 자체가 없어 문제가 없었다(그래서
    /// 확대보기에서는 표시가 보였다는 사용자 관찰과 정확히 들어맞는다).
    ///
    /// 고친 방법 — `NSAttributedString`을 거치지 않고, `AttributedString` 고유
    /// API(`.font`/`.foregroundColor`/`.backgroundColor`/`.underlineStyle`)로
    /// 절 텍스트를 "구간별 조각"으로 나눠 직접 이어 붙인다. 인덱스 변환이 애매한
    /// `NSRange → AttributedString.Index` 변환을 아예 피할 수 있어 더 안전하다.
    static func attributedContent(
        text: String,
        highlights: [VerseHighlight],
        // [2026-08-11 추가] 사용자 요청 — "메모가 있는 구절의 특정표현은 ... 글자색을
        // 다르게 표현하도록." 형광펜(배경색)/표시(밑줄)와 독립적인 세 번째 속성
        // (글자색)이라 겹칠 수 있다 — 아래에서 경계점 기반으로 다시 짰다.
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

        // [2026-08-11 재작성] 형광펜/표시(highlightSegments)와 메모 글자색(noteRanges)이
        // 서로 독립적으로 겹칠 수 있어("이 표현에 형광펜 + 메모 둘 다"), 예전처럼
        // 형광펜 구간만 기준으로 순서대로 이어 붙이는 방식으론 표현할 수 없다 —
        // 두 종류의 구간이 시작/끝나는 모든 지점(경계점)을 모아 그 사이사이를
        // "겹치지 않는 최소 조각"으로 나누고, 조각마다 그 조각을 덮는 형광펜/표시와
        // 메모 존재 여부를 각각 독립적으로 확인해 속성을 입힌다.
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

            // 이 조각은 경계점 구성상 어느 형광펜 구간과도 "부분적으로만" 겹칠 수
            // 없다(겹치면 완전히 포함되거나 전혀 안 겹친다) — 먼저 만들어진 것 우선.
            if let covering = highlightSegments.first(where: {
                $0.range.location <= start && $0.range.location + $0.range.length >= end
            }) {
                switch covering.highlight.style {
                case .highlight:
                    let tag = HighlightColorTag(rawValue: covering.highlight.colorTag ?? "") ?? .yellow
                    run.backgroundColor = tag.swiftUIColor.opacity(tag.backgroundOpacity)
                case .mark:
                    // [2026-08-09 수정] 사용자 요청 — "확대보기의 밑줄 표시는 주황색
                    // 굵은 줄로 표시됨. 그와 동일하게 메인창에서도 밑줄에 대한
                    // 스타일이 동일하게 처리 될수 있도록 할것." ⚠️ SwiftUI
                    // `Text.LineStyle`은 두께 파라미터가 없어 색상만 맞춘다(아래
                    // `nsAttributedContent`의 `.thick` 참고, 플랫폼 제약).
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

    /// "메모"(드래그 표현 부연설명)가 붙은 구간의 글자색. 형광펜(배경색 5종: 노랑/
    /// 초록/파랑/분홍/보라)이나 표시(주황 밑줄)와 겹쳐도 구분되도록, 그 색들과
    /// 겹치지 않는 색을 골랐다 — ⚠️ 정확한 색상은 제품 취향 문제라 임의로 정했다,
    /// 실기기에서 보고 다른 색이 낫다면 이 상수만 바꾸면 된다.
    static let phraseNoteTextColor = Color.blue

    /// [2026-08-15 신설] 사용자 요청 — "확대보기 성경구절 수정 - 한자가 있는
    /// 단어는 색깔로 표현해 줄 것." 형광펜 배경색(노랑/초록/파랑/분홍/보라),
    /// 밑줄(주황, 표시/관주), 메모 글자색(파랑)과 겹치지 않는 색을 새로
    /// 골랐다 — 위 `phraseNoteTextColor`와 같은 성격의 임의 선택, 실기기에서
    /// 보고 다른 색이 낫다면 이 상수만 바꾸면 된다.
    static let hanjaWordTextColor = Color.brown

    /// [2026-08-11 11차 수정] 사용자 요청 — "선택모드에서도 형광펜, 밑줄, 메모가
    /// 있는 텍스트(파란색)을 표시할 것." 선택 모드(`SelectableVerseTextView`)는
    /// `NSAttributedString`을 직접 쓰는 `UITextView`/`NSTextView`라 SwiftUI
    /// `Color`가 아니라 `PlatformColor`가 필요하다 — `HighlightColorTag.
    /// platformColor`와 같은 방식(`PlatformColor(Color)`)으로 변환해 둔다.
    static var phraseNoteTextPlatformColor: PlatformColor { PlatformColor(phraseNoteTextColor) }

    private static func plainRun(_ substring: String, font: PlatformFont, textColor: PlatformColor) -> AttributedString {
        var run = AttributedString(substring)
        run.font = Font(font)
        run.foregroundColor = Color(textColor)
        return run
    }

    /// [2026-08-14 신설, 2026-08-15 확장] 사용자 요청 — "국한문식 항상 보기(A)."
    /// / "난외주가 있으면 해당 단어 왼쪽 상단(윗첨자) 숫자 추가."
    /// `attributedContent`가 만든(또는 형광펜/메모가 없어 nil이면 새로 만든
    /// 평범한) `AttributedString` 위에 두 종류의 "삽입"을 끼워 넣는다 — 한자
    /// 주석 단어 뒤의 "(한자)"와, 난외주 앵커 위치의 위첨자 번호(①②③...).
    ///
    /// ⚠️ [삽입 순서] 예전엔 한자만 있어 `rangeEnd` 내림차순 하나로 충분했다
    /// — 이제 두 종류(한자 `rangeEnd`, 난외주 `anchorOffset`)를 오프셋 하나의
    /// 목록으로 합친 뒤 "전체를 오프셋 내림차순"으로 처리한다. 원리는 같다 —
    /// `Range(nsRange, in:)`으로 위치를 찾아 그 자리에 문자를 끼워 넣으면
    /// 그보다 뒤에 있는 모든 위치가 밀리므로, 뒤에서부터 처리해야 아직 처리
    /// 안 한(더 앞쪽) 위치가 항상 원본 `text`와 동일한 좌표를 유지한다.
    /// 두 종류를 섞어 하나의 목록으로 정렬하는 이유 — 어느 한 종류만 먼저 다
    /// 처리하면(예: 한자를 전부 끝내고 나서 난외주 처리), 이미 삽입된 한자
    /// 괄호 텍스트 때문에 아직 처리 안 한 난외주의 저장된 오프셋이 밀려서
    /// 안 맞게 된다 — 두 종류를 합쳐서 한 번에 뒤에서부터 처리해야 이 문제가
    /// 없다.
    ///
    /// 한자 부분은 본문과 구분되도록 살짝 옅은 색 + 기울임을, 난외주 위첨자는
    /// `note.markerText`(원본 `02개역난외주.bdb`의 `<SUP>...</SUP>` 캡처 글자
    /// 그대로, 대부분 ①②③... 일부는 `*`)를 작게 표시한다 — [2026-08-15
    /// 재수정, 이어서 67] 처음엔 앱이 절마다 새로 번호를 매겼는데(아래
    /// 삭제된 `circledNumeral` 참고), 사용자 확인 요청으로 원본 번호가 절
    /// 단위가 아니라 장 전체에 걸쳐 이어지고 반복 단어는 번호를 재사용하는
    /// 등 앱의 가정과 57% 달랐던 사실이 드러나 원본 글자를 그대로 쓰기로
    /// 했다. 색상은 취향 문제라 필요하면 이 부분만 바꾸면 된다(형광펜
    /// 색상 상수와 같은 성격).
    static func attributedContentWithInlineAnnotations(
        text: String,
        highlights: [VerseHighlight],
        phraseNotes: [VersePhraseNote] = [],
        hanjaWords: [HanjaWordAnnotation] = [],
        marginalNotes: [VerseMarginalNote] = [],
        font: PlatformFont,
        textColor: PlatformColor,
        // [2026-08-19 추가] 사용자 요청 — "한자 기본 폰트(조선궁서체)를 성경
        // 조회에 표시되는 한자에 적용." 넘기지 않으면(nil, 기본값) 예전처럼
        // 본문 글꼴을 그대로 쓴다 — 호출부(TranslationColumnView)가 아직
        // 안 고쳐졌어도 컴파일이 깨지지 않게 하기 위한 기본 인자.
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

    // [2026-08-15 삭제, 이어서 67] `circledNumeral(_:)`(절마다 1부터 새로
    // 번호를 매기던 헬퍼)가 여기 있었다 — 원본 `<SUP>` 태그 번호를 그대로
    // 쓰기로 하면서(`VerseMarginalNote.markerText`) 더 이상 앱이 번호를
    // 새로 만들 필요가 없어져 지웠다. 자세한 경위는 위
    // `attributedContentWithInlineAnnotations` 주석과
    // `VerseMarginalNote` 클래스 주석 참고.

    /// 난외주 위첨자 번호의 색 — 형광펜 배경 5색, 밑줄(주황), 메모 글자색(파랑),
    /// 한자 인라인(옅은 회색+기울임)과 겹치지 않는 색으로 새로 골랐다(위
    /// `hanjaWordTextColor`/`phraseNoteTextColor`와 같은 성격의 임의 선택).
    static let marginalNoteMarkerColor = Color.purple

    /// [2026-08-11 8차 수정, 삭제됨] 확대보기 전용 `NSMutableAttributedString`
    /// 생성 함수(`nsAttributedContent`)가 여기 있었다 — 확대보기가 TextKit
    /// (`UITextView`/`NSTextView`)로 형광펜/표시/메모/줄바꿈을 전부 직접 그리던
    /// 시절의 것으로, 지금은 표시 모드가 `AnnotatedVerseFlowView` + `buildLines(...)`
    /// (아래)로 완전히 대체되어 이 함수를 쓰는 곳이 없다 — 죽은 코드로 남겨
    /// 두면 이미 사라진 타입(`HighlightOverlayRect` 등)을 언급하는 주석만
    /// 헷갈리게 남으므로 통째로 지웠다. 자세한 배경은 이 파일 상단
    /// [2026-08-11 8차 수정] 주석과 `SelectableVerseTextView.swift` 상단 주석
    /// 참고.

    /// [2026-08-11 2차 수정] 사용자 요청 — "띄어쓰기 포함 23자가 되는 글자를
    /// 찾고 앞뒤로 가까운 띄어쓰기 포인트를 찾아 그 띄어쓰기로 줄바꿈을 할
    /// 것." 줄 시작(`lineStart`)에서 `targetCharsPerLine`번째 글자 위치를
    /// 목표점으로 잡고, 그 지점에서 줄바꿈 지점을 찾아 그 다음 줄도 같은
    /// 방식으로 반복한다. 남은 구간에 띄어쓰기가 하나도 없으면(매우 긴 단일
    /// 단어) 그 지점에서 멈춘다 — 글자 중간을 끊지 않는다는 원칙(어절 단위)을
    /// 지키기 위해서다.
    ///
    /// [2026-09-01 변경] 사용자 요청 — "한라인에서 20글자(공백포함) 이후
    /// 나타나는 첫 공백에서 줄바꿈으로 바꿀 것." 원래는 목표 지점 앞뒤로
    /// 가장 가까운 띄어쓰기를 찾았는데(`nearestSpaceIndex`, 앞으로도 뒤로도
    /// 검색), 이제는 목표 지점부터 뒤로만 검색해 처음 만나는 띄어쓰기에서
    /// 끊는다(`firstSpaceIndex`) — 목표 지점 이전에 띄어쓰기가 있어도 더는
    /// 그쪽으로 끊지 않는다.
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

    /// [2026-09-01 신설, `nearestSpaceIndex` 대체] `target` 위치부터
    /// `upperBound` 방향으로(뒤로만) 훑어 처음 만나는 띄어쓰기(U+0020)
    /// 위치를 돌려준다. `[target, upperBound)` 범위 밖으로는 나가지 않는다
    /// (절 끝을 넘어가지 않게) — `target` 이전 구간은 아예 보지 않는다.
    private static func firstSpaceIndex(in ns: NSString, from target: Int, to upperBound: Int) -> Int? {
        guard upperBound > target else { return nil }
        var index = max(target, 0)
        while index < upperBound {
            if ns.character(at: index) == 0x20 { return index }
            index += 1
        }
        return nil
    }

    /// [2026-08-11 2차 수정] 사용자 요청 — "성경 구절에는 라틴, 숫자가 포함되지
    /// 않음... 영문성경 및 그외 성경은 그대로 유지." 번역본 자체엔 "언어"
    /// 필드가 없어(`TranslationRegistry` — 사용자 추가 번역본은 임의 언어일
    /// 수 있음) 절 텍스트 자체에 라틴 문자/숫자가 있는지로 판정한다 — 번들
    /// 한글 번역본은 항상 없고, 영문 성경(KJV 등) 등은 항상 있어 실질적으로
    /// 번역본 구분과 같은 효과를 낸다.
    static func containsLatinOrDigit(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (scalar.value >= 0x41 && scalar.value <= 0x5A)
                || (scalar.value >= 0x61 && scalar.value <= 0x7A)
                || (scalar.value >= 0x30 && scalar.value <= 0x39)
        }
    }

    // MARK: - [2026-08-11 8차 수정, 확대보기 전면 재설계] 순수 SwiftUI 표시 레이어
    //
    // 사용자가 제공한 설계 문서("SwiftUI 성경 본문 주석 UI 명세")를 그대로 채택한다
    // — 이 문서의 진단이 지금까지 8라운드 동안 겪은 버그들의 근본 원인과 정확히
    // 겹친다: 메모 박스 높이를 `NSString.boundingRect`로 추측하고, 그 추측치를
    // TextKit 줄간격에 강제로 주입하고, 형광펜/메모 좌표를 TextKit 글리프 좌표와
    // SwiftUI 좌표 사이에서 손으로 맞춰 온 것 — 전부 "SwiftUI가 원래 잘하는 일을
    // TextKit으로 재발명"한 것이었다.
    //
    // 새 구조: 확대보기를 "표시 모드"(이 섹션, 순수 SwiftUI)와 "선택 모드"
    // (`SelectableVerseTextView`, 드래그로 새 구간을 고를 때만 잠깐 뜨는 최소
    // 컴포넌트로 축소)로 분리한다. 표시 모드는 절 텍스트를 우리가 직접 줄 단위로
    // 나눠(`lineRanges(...)`) 각 줄을 SwiftUI `Text` 세그먼트의 `HStack`으로 그리고,
    // 메모 박스는 그 줄 바로 아래 `VStack`의 실제 서브뷰로 끼워 넣는다 — 그러면
    // "메모가 길어지면 다음 내용이 밀려난다"가 SwiftUI `VStack`이 원래 하는 일이 되어
    // 별도의 높이 추정/줄간격 주입 코드가 필요 없다(`Views/Bible/AnnotatedVerseFlowView.swift`
    // 참고).

    /// 절 텍스트를 시각적 "줄" 단위로 나눈 문자 범위 목록. 한글(라틴/숫자 없는
    /// 절)은 기존에 검증된 23자 최근접 띄어쓰기 알고리즘(`koreanLineRanges`)을
    /// 그대로 재사용하고, 라틴/혼합 절(영문 성경 등)은 화면에 올리지 않는
    /// "측정 전용" TextKit 인스턴스(`measuredLineRanges`)로 실제 폭 기준 줄바꿈
    /// 지점을 구한다 — 둘 다 언어와 무관하게 같은 반환 형태([NSRange])라 호출부가
    /// 분기할 필요가 없다.
    ///
    /// ⚠️ [측정 전용 TextKit] `measuredLineRanges`가 만드는 `NSLayoutManager`는
    /// 어떤 뷰에도 연결되지 않고 이 함수 안에서만 존재했다 사라진다 — 화면에
    /// 그려지지 않으므로 지금까지 겪은 델리게이트 재진입/좌표 브리징 문제가
    /// 원천적으로 발생할 수 없다. 순수하게 "이 폭에서 TextKit이라면 어디서
    /// 줄을 바꿨을까"를 한 번 물어보는 계산기로만 쓴다.
    /// [2026-08-12 추가] `targetCharsPerLine` — 아이폰 확대보기에서 세로/가로
    /// 모드마다 줄당 글자수를 다르게 쓰기 위한 매개변수(사용자 요청). 기본값
    /// 23은 예전 고정값과 같아, 이 값을 안 넘기는 다른 호출부(있다면)는 기존과
    /// 동일하게 동작한다. 라틴/혼합 절(`measuredLineRanges`)은 글자수가 아니라
    /// 폭 기준이라 이 값과 무관하다.
    static func lineRanges(for text: String, font: PlatformFont, containerWidth: CGFloat, targetCharsPerLine: Int = 23) -> [NSRange] {
        guard !text.isEmpty else { return [] }
        if containsLatinOrDigit(text) {
            return measuredLineRanges(for: text, font: font, containerWidth: containerWidth)
        }
        return koreanLineRanges(for: text, targetCharsPerLine: targetCharsPerLine)
    }

    /// [2026-08-11 10차 수정] 사용자 요청 — "선택모드에 들어가는 텍스트를
    /// 표시모드와 동일하게 일치시킬 것(줄바꿈까지)." 선택 모드
    /// (`SelectableVerseTextView`)는 평범한 `UITextView`/`NSTextView`라 자기
    /// 나름의 자동 줄바꿈으로 줄을 나누는데, 표시 모드는 이 파일의
    /// `lineRanges(...)`가 고른 경계를 그대로 쓴다 — 한글 절은 23자 최근접
    /// 띄어쓰기라는, 실제 픽셀 폭과 무관한 완전히 다른 알고리즘이라 자동
    /// 줄바꿈과 우연히 어긋날 수 있다(사용자가 보고한 증상).
    ///
    /// 두 모드가 항상 정확히 같은 자리에서 줄을 바꾸도록, `lineRanges(...)`가
    /// 고른 경계 사이에 "건너뛴 구분자"가 있으면(`koreanLineRanges`가
    /// `lineStart = position + 1`로 스킵하는 그 한 글자 — 설계상 항상 공백,
    /// `lineBreakPositions`가 애초에 띄어쓰기에서만 끊기(2026-09-01부터는
    /// `firstSpaceIndex`로 목표 지점 이후 첫 띄어쓰기) 때문이다) 그 자리를
    /// U+2028(라인 구분자)로 바꿔치기해 강제로 줄을
    /// 바꾼다. **삽입이 아니라 치환**이라 글자 수·인덱스가 그대로 유지되므로,
    /// 이 문자열을 기준으로 얻은 `selectedRange`는 원본 `text`에서도 똑같은
    /// 위치를 정확히 가리킨다(호출부가 별도 보정을 할 필요가 없다).
    ///
    /// 라틴/혼합 절(`measuredLineRanges`)은 줄 사이에 건너뛴 구분자가 없다 —
    /// 줄 끝 공백이 이미 그 줄 범위 안에 포함되어 있어(TextKit이 라인
    /// 프래그먼트를 나눌 때 공백을 앞 줄에 붙이는 관례) 딱 붙어 있으므로
    /// 손대지 않는다. 같은 폰트·같은 폭·같은 `lineFragmentPadding = 0`으로
    /// 구성한 `UITextView`/`NSTextView`는 이 함수가 쓰는 것과 동일한 TextKit
    /// 엔진이 자동 줄바꿈을 계산하므로, 이미 정확히 같은 자리에서 줄이
    /// 바뀐다 — 강제 치환이 필요 없다.
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

    /// [2026-08-11 11차 수정] 사용자 요청 — "선택모드에서도 형광펜, 밑줄, 메모가
    /// 있는 텍스트(파란색)을 표시할 것." 선택 모드(`SelectableVerseTextView`,
    /// iOS/macOS 둘 다)가 그리는 `NSAttributedString`을 여기 한 곳에서 만든다
    /// — 표시 모드(`AnnotatedVerseFlowView`)와 똑같이 `buildLines(...)`의
    /// 세그먼트 분해(형광펜/메모 경계점 기준으로 겹치지 않게 쪼갠 조각, 조각당
    /// 하나의 덮는 형광펜과 메모 id 목록)를 그대로 재사용한다 — 두 모드가
    /// "어느 표현에 무엇이 붙어 있는지" 판정하는 로직 자체를 공유하므로 서로
    /// 어긋날 수 없다. 메모 "내용"(박스/화살표)은 여기서 그리지 않는다 — 그건
    /// 여전히 표시 모드 전용이고, 여기서는 "이 표현에 메모가 있다"는 신호로
    /// 글자색만 바꾼다.
    /// [2026-08-27 신설] 사용자 요청 — "성경구절 길게 누르거나(iOS) 마우스
    /// 오른쪽 버튼을 눌러 '선택' 기능을 클릭하면, 개역한글(번들 성경)인
    /// 경우 한자 주석까지 같이 나오도록(한자도 복사 가능하게)."
    /// `VerseTextSelectionPopover` 전용 — `attributedContentWithInlineAnnotations`
    /// (성경 조회 본문의 "항상 보기"/"탭하면 보기" 인라인 한자 표시)와 완전히
    /// 같은 삽입 규칙(단어 뒤, `rangeEnd` 위치에 "(한자)")을 쓰되, 여기서는
    /// `AttributedString`이 아니라 평범한 `String`을 돌려준다 — 이 결과가
    /// 그대로 `SelectableVerseTextView`의 `text:`(선택 가능한 원본 문자열)로
    /// 들어가서, 사용자가 드래그로 고르는 범위 자체에 한자 글자가 포함돼
    /// 그대로 복사되게 하기 위해서다. 반대로 `selectionModeAttributedText`
    /// (바로 아래, `VerseZoomView`의 "드래그로 새 형광펜/메모 만들기" 선택
    /// 모드 전용)는 한자를 텍스트에 삽입하지 않고 단어 색상만 바꾸는데 —
    /// 그건 그 화면이 만드는 형광펜/메모의 `rangeStart`/`rangeEnd`가 원본
    /// `verse.content` 기준 오프셋으로 저장돼야 하기 때문에 텍스트 길이 자체를
    /// 바꿀 수 없어서다(그 함수 자체 주석 참고). 이 팝오버는 그런 저장 용도가
    /// 없이 "보이는 대로 복사"만 하면 되므로 텍스트에 직접 끼워 넣는 쪽을
    /// 택했다 — 그래서 이 함수를 그 함수와 공유하지 않고 따로 둔다(용도가
    /// 근본적으로 달라, 억지로 공유하면 오히려 두 화면 다 헷갈리게 만든다).
    ///
    /// 삽입은 내림차순(오프셋이 큰 것부터)으로 처리한다 — 오른쪽부터 끼워
    /// 넣어야, 아직 처리하지 않은(더 왼쪽에 있는) 삽입 지점들의 오프셋이
    /// 앞선 삽입 때문에 밀리지 않는다(`attributedContentWithInlineAnnotations`
    /// 와 정확히 같은 이유로 같은 순서를 쓴다).
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
        // [2026-08-12 추가] 사용자 요청 — "특정 텍스트를 선택하여 관주를 넣는
        // 부분에 현재 밑줄처럼 표시할 것." 아래 `crossReferences` 참고.
        crossReferences: [VerseCrossReference] = [],
        // [2026-08-15 추가] 사용자 요청 — "확대보기 성경구절 수정 - 한자가
        // 있는 단어는 색깔로 표현해 줄 것." 표시 모드(`AnnotatedVerseFlowView`)
        // 와 시각적으로 어긋나지 않도록 선택 모드에도 같은 신호를 반영한다.
        hanjaWords: [HanjaWordAnnotation] = [],
        // [2026-09-05 추가] 사용자 보고 — 우클릭 "선택"(`VerseTextSelectionPopover`)
        // 에서 텍스트 드래그 선택 중 한글 번역본에서만 선택 영역이 빠르게
        // 깜박임(영문은 정상). 원인: 아래 `forcedBreakText`가 하는 일은 바로
        // 위 [2026-08-11 10차 수정] 주석이 설명하듯 "선택 모드 줄바꿈을 표시
        // 모드와 맞추는 것"인데, `VerseTextSelectionPopover`는 애초에 표시
        // 모드(`AnnotatedVerseFlowView`)를 같이 보여주지 않는 화면이라(그
        // 파일 상단 주석 — "이 팝오버의 목적은... 주석을 보여주는 것이
        // 아니다") 줄바꿈을 맞출 대상 자체가 없다 — 그런데도 지금까지
        // 무조건 `forcedBreakText`를 거쳐 한글 텍스트에만 보이지 않는
        // U+2028(줄 구분자)이 곳곳에(대략 23자마다) 끼워져 있었다. 영문/숫자
        // 포함 텍스트는 이 치환이 사실상 없는 것과 같다(같은 파일
        // `forcedBreakText` 주석 참고 — 라틴 줄 사이엔 "건너뛴 구분자"가
        // 없어 실질적으로 치환되지 않는다) — 이게 지금까지 찾아낸, 한글/영문
        // 경로 사이의 유일한 문자열 내용 차이다.
        //
        // 표시 모드와 맞출 필요가 없는 호출부(`VerseTextSelectionPopover`)는
        // 이 플래그를 `false`로 넘겨 `forcedBreakText`를 건너뛰고 원본
        // `text`를 그대로 쓰게 한다 — 그러면 `NSTextView`/`UITextView`가
        // (영문과 똑같이) 자기 폭 기준으로 자연스럽게 줄바꿈하므로, 한글
        // 텍스트에서도 영문과 동일한 코드 경로를 타게 되어 U+2028과 관련된
        // 어떤 TextKit 상호작용이 원인이었든 이 화면에서는 아예 발생하지
        // 않는다. 기본값은 `true`(기존 동작 유지)라 표시 모드와의 줄바꿈
        // 일치가 실제로 필요한 `VerseZoomView`(선택 모드로 새 형광펜/표시/
        // 메모/관주를 만들 때) 호출부는 코드를 바꾸지 않아도 그대로 동작한다.
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
                // `forcedBreakText`는 줄 사이의 "건너뛴 구분자"만 U+2028로
                // 치환하고 그 외 인덱스는 전혀 바꾸지 않으므로(치환이지 삽입이
                // 아님), 세그먼트 범위는 `displayText`에서도 그대로 유효하다.
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
                        result.addAttribute(.underlineColor, value: PlatformColor.orange, range: range)
                    }
                }
                // [2026-08-12 추가] 사용자 요청 — "관주가 있는 텍스트에 현재
                // 밑줄처럼 표시할 것(성경문구만 봐서는 관주 여부를 확인할 수
                // 없어서)." 예전 "표시"(사용자가 직접 켜던 `.mark`)와 같은
                // 시각 스타일(주황 실선 밑줄)을 재사용하되, 이번엔 사용자가
                // 켜고 끄는 게 아니라 관주가 실제로 등록돼 있으면 자동으로
                // 켜진다 — `.mark`와 독립적이라 이미 밑줄이어도 중복 적용은
                // 무해하다(같은 속성을 같은 값으로 한 번 더 쓸 뿐).
                if segment.hasCrossReference {
                    result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                    result.addAttribute(.underlineColor, value: PlatformColor.orange, range: range)
                }
                // [2026-08-15 추가] 사용자 요청 — "한자가 있는 단어는 색깔로
                // 표현." 메모 글자색(아래)이 있으면 그게 우선이도록 이 블록을
                // 먼저 적용한다 — `AnnotatedVerseFlowView.segmentView`와 같은
                // 우선순위(메모 > 한자).
                if segment.hasHanja {
                    result.addAttribute(.foregroundColor, value: PlatformColor(hanjaWordTextColor), range: range)
                }
                if !segment.noteIDs.isEmpty {
                    result.addAttribute(.foregroundColor, value: phraseNoteTextPlatformColor, range: range)
                }
            }
        }
        return result
    }

    /// 기존 `lineBreakPositions`(목표 글자수 이후 첫 띄어쓰기 지점)를 그대로 재사용해
    /// "지점 목록"이 아니라 "줄 범위 목록"으로 바꿔 준다. 지점 자체의 U+2028
    /// 문자(그 자리의 공백 하나)는 줄 사이의 "구분자"이지 어느 줄에도 속하지
    /// 않는 것으로 취급해, 각 줄 범위는 그 공백을 포함하지 않는다(줄 끝에
    /// 보이지 않는 공백이 남는 걸 방지 — SwiftUI `Text`는 U+2028 치환이 필요
    /// 없다, 애초에 줄을 우리가 나눠서 각각 별도 `Text`로 그리기 때문이다).
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

    /// 라틴/혼합 절 전용 — 화면에 올리지 않는 임시 `NSLayoutManager`로 실제
    /// 폭 기준 줄바꿈 지점을 측정한다. 지금까지 이 경우엔 "한글 전각 폭 추정
    /// × 21자"라는 근사치를 썼는데(정확한 글자 폭이 아니라 어긋날 수 있다고
    /// 스스로 주석에 적어 뒀었다), 실제 TextKit 타이프세팅 결과를 그대로
    /// 읽어오는 이 방식이 근사치보다 정확하다 — 그러면서도 아무것도 화면에
    /// 그리지 않으므로 이 세션 내내 문제였던 "TextKit 표시 좌표"와는 무관하다.
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

    /// 표시 레이어(`AnnotatedVerseFlowView`)가 한 줄을 `HStack`으로 그릴 때 쓰는
    /// 최소 단위 — "겹치지 않는 조각"(위 `attributedContent`와 같은 경계점
    /// 분해 원리) 하나에 그 조각을 덮는 형광펜(있다면)과, 그 조각을 앵커로 삼는
    /// "메모"(드래그 표현 부연설명)들의 id 목록을 함께 들고 있는다. `.mark`
    /// (표시/밑줄)는 배경이 아니라 밑줄이라 `highlight` 자체를 그대로 참조해
    /// 뷰 쪽에서 스타일을 고른다.
    struct VerseTextSegment: Identifiable {
        let id = UUID()
        let range: NSRange
        let text: String
        let highlight: VerseHighlight?
        let noteIDs: [UUID]
        /// [2026-08-12 추가] 사용자 요청 — "특정 텍스트를 선택하여 관주를 넣는
        /// 부분에 현재 밑줄처럼 표시할 것." 이 조각이 하나 이상의
        /// `VerseCrossReference`(구간 지정이 있는 것만 — 절 전체 관주는 특정
        /// 표현이 없어 대상이 아니다)에 덮여 있는지. `highlight`(형광펜/표시)와
        /// 완전히 독립적인 신호라 별도 필드로 둔다 — 형광펜 배경 위에도, 아무
        /// 형광펜이 없어도 똑같이 밑줄을 그릴 수 있어야 한다.
        let hasCrossReference: Bool
        /// [2026-08-15 신설] 사용자 요청 — "확대보기 성경구절 수정 - 한자가
        /// 있는 단어는 색깔로 표현해 줄 것." `hasCrossReference`와 완전히
        /// 같은 원리(경계점 기반 조각 분해로 이 조각이 어느 한자 단어
        /// 범위에 통째로 덮여 있는지) — `HanjaWordAnnotation`은 오프셋이
        /// 이미 그 번역본 원문 기준 UTF-16 절대 위치라 관주/형광펜과 달리
        /// `anchorText` 재탐색이 필요 없다(`HanjaWordAnnotation` 상단 주석
        /// 참고).
        let hasHanja: Bool
    }

    /// 시각적 줄 하나 — 그 줄의 세그먼트들과, 그 줄에 "앵커"(시작 위치)를 둔
    /// 메모 목록. 메모가 하드랩으로 다음 줄까지 걸치는 극히 드문 경우에도
    /// "시작 위치가 있는 줄" 기준으로 하나의 줄에만 속하게 해, 같은 메모의
    /// 박스가 두 줄에 중복으로 나타나지 않게 한다.
    struct VerseLine: Identifiable {
        let id = UUID()
        let range: NSRange
        let segments: [VerseTextSegment]
        let notes: [VersePhraseNote]
    }

    /// 절 텍스트 + 주석을 표시 레이어가 바로 그릴 수 있는 `[VerseLine]`로
    /// 조립한다. `lineRanges(...)`로 줄을 나눈 뒤, 각 줄 범위 안에서 형광펜/
    /// 메모 경계점으로 다시 쪼갠다 — `attributedContent`가 절 전체에 대해 하던
    /// 경계점 분해를 "줄 범위로 미리 자른 부분 문자열"에 대해 반복하는 것과
    /// 같은 원리다.
    static func buildLines(
        text: String, highlights: [VerseHighlight], phraseNotes: [VersePhraseNote],
        // [2026-08-12 추가] 사용자 요청 — "특정 텍스트를 선택하여 관주를 넣는
        // 부분에 현재 밑줄처럼 표시할 것(관주가 있는지 성경문구만 봐서는 확인이
        // 안 됨)." 형광펜/메모와 같은 원리(경계점 기반 조각 분해)로 처리한다 —
        // 다만 절 전체 관주(구간 지정이 없는 것, `rangeStart`/`rangeEnd`/
        // `anchorText`가 nil)는 밑줄 그을 특정 표현이 없으므로 대상에서 뺀다.
        crossReferences: [VerseCrossReference] = [],
        // [2026-08-15 추가] 사용자 요청 — "확대보기 성경구절 수정 - 한자가
        // 있는 단어는 색깔로 표현해 줄 것." 관주/형광펜과 같은 경계점 기반
        // 조각 분해에 함께 참여한다(아래 `resolvedHanjaRanges` 참고).
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
        // [2026-08-15 추가] 오프셋이 이미 이 번역본 원문 기준 절대 위치라
        // (`HanjaWordAnnotation` 상단 주석 참고) 관주/형광펜처럼 `anchorText`로
        // 다시 찾을 필요 없이 그대로 쓰되, 데이터가 지금 본문 길이와 안 맞는
        // 극단적인 경우(있다면)에 대비해 범위만 안전하게 검증한다.
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

            // 왼쪽→오른쪽 순서로 정렬해 두면, 이 배열 순서를 그대로 세로
            // 쌓기 순서로 쓰는 `AnnotatedVerseFlowView`가 "먼저 나오는 표현의
            // 메모가 위에" 오도록 자연스럽게 맞는다.
            let notesStartingHere = resolvedNotes.filter {
                $0.range.location >= lineRange.location && $0.range.location < lineRange.location + lineRange.length
            }.sorted { $0.range.location < $1.range.location }.map(\.note)
            return VerseLine(range: lineRange, segments: segments, notes: notesStartingHere)
        }
    }

    /// 저장된 오프셋이 지금 본문과 안 맞으면(번역본 데이터가 고쳐진 경우)
    /// `anchorText`로 다시 찾는 "자가 치유" — `VerseAnnotations.swift` 상단
    /// 주석 참고. 어느 쪽으로도 못 찾으면 nil.
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
        // [2026-08-11 6차 수정] 사용자 보고 — "줄바꿈을 넘어 형광펜 칠할 경우
        // 확대보기에서 표현안됨." 원인: `nsAttributedContent`의 23자 강제
        // 줄바꿈이 `full`(렌더링용 사본) 안의 특정 공백(U+0020)을 줄 구분자
        // (U+2028)로 1:1 치환한다 — 그 치환된 공백이 하필 이 주석의 앵커
        // 텍스트 "내부"에 있으면(두 단어를 잇는 공백이 줄바꿈 지점으로
        // 골라진 경우), 위 두 시도(정확 오프셋 일치·리터럴 검색) 모두 문자가
        // 달라져 실패한다 — 앵커 텍스트엔 원래 공백(U+0020)이 있는데 `full`
        // 에는 U+2028이 들어 있어 절대 같아질 수 없다. 강제 줄바꿈 치환은
        // 항상 "공백 자리에만, 길이 보존"으로 이뤄진다는 보장이 있으므로
        // (`lineBreakPositions`/`firstSpaceIndex` 참고), U+2028을 다시
        // 공백으로 되돌린 정규화 사본에서 앵커 텍스트를 찾고, 그 결과
        // 위치(문자 인덱스)를 원본 `full`에 그대로 재사용한다 — 치환이
        // 길이를 바꾸지 않으므로 인덱스가 어긋나지 않는다.
        guard full.contains("\u{2028}") else { return nil }
        let normalized = full.replacingOccurrences(of: "\u{2028}", with: " ") as NSString
        guard normalized.length == full.length else { return nil }
        let normalizedFound = normalized.range(of: anchorText)
        return normalizedFound.location == NSNotFound ? nil : normalizedFound
    }
}
