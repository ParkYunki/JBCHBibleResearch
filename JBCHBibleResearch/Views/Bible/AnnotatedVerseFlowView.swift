//
//  AnnotatedVerseFlowView.swift
//  JBCHBibleResearch
//
//  확대보기 "표시 모드" 전용 뷰. 절 텍스트를 줄 단위(`VerseAnnotationRenderer.VerseLine`)로
//  나눠 각 줄을 SwiftUI `Text` 세그먼트의 `HStack`으로 그리고, 그 줄에 메모가 있으면
//  바로 아래에 실제 서브뷰(`PhraseNoteBoxView`)를 끼워 넣는다 — `VStack`이 다음 콘텐츠를
//  밀어내는 동작을 그대로 쓰므로 메모 박스 높이를 추측해 줄간격에 주입할 필요가 없다.
//
//  형광펜/표시 취소, 메모 수정/삭제는 각 세그먼트의 SwiftUI 표준 `.contextMenu`로
//  처리한다(iOS는 길게 누르기, macOS는 우클릭).
//
//  메모 박스와 그 표현을 잇는 화살표는 `anchorPreference`/`overlayPreferenceValue`로
//  그린다 — 두 좌표 모두 SwiftUI가 레이아웃한 프레임이라 TextKit 글리프 좌표와
//  SwiftUI 좌표를 손으로 맞출 필요가 없다.
//

import SwiftUI
import BibleResearchModels

/// 표현 세그먼트(텍스트)와 메모 박스, 두 종류의 좌표를 한 `PreferenceKey`로
/// 함께 모은다 — 화살표를 그릴 때 같은 메모 id의 텍스트 좌표와 박스 좌표를
/// 동시에 봐야 하기 때문이다.
private struct VerseAnchorCollection {
    /// 표현 세그먼트 좌표 — 한 메모의 앵커 표현이 형광펜 등으로 인해 세그먼트
    /// 여러 개로 쪼개질 수 있어(`VerseAnnotationRenderer.buildLines` 참고) 배열로 모은다.
    var textAnchors: [UUID: [Anchor<CGRect>]] = [:]
    /// 메모 박스 좌표 — 박스는 메모 하나당 하나뿐이라 1:1이다.
    var boxAnchors: [UUID: Anchor<CGRect>] = [:]
}

private struct VerseAnchorCollectionKey: PreferenceKey {
    static var defaultValue = VerseAnchorCollection()
    static func reduce(value: inout VerseAnchorCollection, nextValue: () -> VerseAnchorCollection) {
        let next = nextValue()
        for (id, anchors) in next.textAnchors {
            value.textAnchors[id, default: []].append(contentsOf: anchors)
        }
        for (id, anchor) in next.boxAnchors {
            value.boxAnchors[id] = anchor
        }
    }
}

/// 메모 박스에서 그 표현으로 긋는 화살표(직선 + 화살촉).
private struct NoteConnectorArrow: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        let angle = atan2(to.y - from.y, to.x - from.x)
        let arrowLength: CGFloat = 6
        let arrowAngle: CGFloat = .pi / 7
        let p1 = CGPoint(x: to.x - arrowLength * cos(angle - arrowAngle), y: to.y - arrowLength * sin(angle - arrowAngle))
        let p2 = CGPoint(x: to.x - arrowLength * cos(angle + arrowAngle), y: to.y - arrowLength * sin(angle + arrowAngle))
        path.move(to: to)
        path.addLine(to: p1)
        path.move(to: to)
        path.addLine(to: p2)
        return path
    }
}

struct AnnotatedVerseFlowView: View {
    let text: String
    let highlights: [VerseHighlight]
    let phraseNotes: [VersePhraseNote]
    /// `VerseAnnotationRenderer.buildLines(...)`에 전달해 관주가 걸린 표현에 밑줄이 그려지게 한다.
    let crossReferences: [VerseCrossReference]
    /// `VerseAnnotationRenderer.buildLines(...)`에 전달 — 관주와 같은 경계점 기반 조각
    /// 분해에 참여해 그 조각의 `hasHanja`를 켠다(`segmentView` 참고).
    var hanjaWords: [HanjaWordAnnotation] = []
    let font: PlatformFont
    let textColor: PlatformColor
    /// 줄바꿈 계산에 쓸 폭 — 호출부(`VerseZoomView`)가 실제 화면 폭(패딩 제외)을 넘긴다.
    /// `VerseAnnotationRenderer.lineRanges(...)`가 이 폭 기준으로 한글은
    /// `targetCharsPerLine`자 최근접 띄어쓰기, 라틴/혼합은 TextKit 측정으로 줄을 나눈다.
    let containerWidth: CGFloat
    /// 메모 박스가 밀릴 수 있는 최대 거리 계산용 폭(`VerseZoomView` 스크롤 영역 실제 폭, 패딩 제외).
    /// 박스는 좁은 본문 줄 폭(`containerWidth`)에 갇히지 않고 화면 콘텐츠 영역 전체 폭까지
    /// 밀릴 수 있어 `containerWidth`와 따로 받는다.
    let availableWidth: CGFloat
    /// 세로/가로 모드마다 다른 줄당 글자수 — `VerseZoomView.targetCharsPerLine` 참고.
    let targetCharsPerLine: Int

    var onRequestRemoveHighlight: (VerseHighlight) -> Void = { _ in }
    var onRequestEditPhraseNote: (VersePhraseNote) -> Void = { _ in }
    var onRequestDeletePhraseNote: (VersePhraseNote) -> Void = { _ in }

    private var lines: [VerseAnnotationRenderer.VerseLine] {
        VerseAnnotationRenderer.buildLines(
            text: text, highlights: highlights, phraseNotes: phraseNotes, crossReferences: crossReferences,
            hanjaWords: hanjaWords, font: font, containerWidth: containerWidth, targetCharsPerLine: targetCharsPerLine
        )
    }

    /// 줄과 줄 사이 간격 — 선택 모드(`SelectableVerseTextView`)의 줄간격 공식
    /// (`VerseAnnotationRenderer.selectionModeAttributedText`의
    /// `font.typographicLineHeight * (2.3 - 1)`)을 그대로 재사용해 두 모드가 같은 값을 쓰게 한다.
    /// 한 줄과 그 줄의 메모 상자 사이 간격(안쪽 VStack spacing: 6)과는 별개다.
    private var lineSpacing: CGFloat {
        font.typographicLineHeight * (2.3 - 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: lineSpacing) {
            ForEach(lines) { line in
                VStack(alignment: .leading, spacing: 6) {
                    lineRow(line)
                    ForEach(line.notes) { note in
                        PhraseNoteBoxView(note: note, width: estimatedBoxWidth(for: note)) { onRequestEditPhraseNote(note) }
                            .anchorPreference(key: VerseAnchorCollectionKey.self, value: .bounds) { anchor in
                                VerseAnchorCollection(boxAnchors: [note.id: anchor])
                            }
                            .padding(.leading, approximateLeadingOffset(for: note, in: line))
                            .contextMenu {
                                Button("메모 수정") { onRequestEditPhraseNote(note) }
                                Button("메모 삭제", role: .destructive) { onRequestDeletePhraseNote(note) }
                            }
                    }
                }
            }
        }
        .overlayPreferenceValue(VerseAnchorCollectionKey.self) { collection in
            GeometryReader { proxy in
                ForEach(phraseNotes.filter { note in
                    collection.boxAnchors[note.id] != nil && collection.textAnchors[note.id] != nil
                }) { note in
                    if let boxAnchor = collection.boxAnchors[note.id],
                       let textAnchors = collection.textAnchors[note.id],
                       let firstTextAnchor = textAnchors.first {
                        let boxRect = proxy[boxAnchor]
                        // 앵커가 줄바꿈 경계를 가로질러 여러 세그먼트로 쪼개지면 union의
                        // `.minX`/`.maxY`가 다음 줄 기준이 되어 화살표가 대각선으로 늘어진다.
                        // `textAnchors`는 줄 순서(위→아래, 왼→오)로 쌓이므로 첫 원소가
                        // 박스가 놓이는 줄의 첫 세그먼트다 — 그것만 기준으로 삼는다
                        // (한 줄에만 있는 메모는 first == union이라 결과가 같다).
                        let textRect = proxy[firstTextAnchor]
                        // `textRect.minX`는 첫 글자의 왼쪽 끝이라, 첫 글자 폭의 절반을 더해
                        // 그 글자의 가운데를 가리키게 한다.
                        let arrowTargetX = textRect.minX + leadingCharacterHalfWidth(for: note)
                        NoteConnectorArrow(
                            from: CGPoint(x: boxRect.minX + 8, y: boxRect.minY),
                            to: CGPoint(x: arrowTargetX, y: textRect.maxY + 2)
                        )
                        .stroke(Color.secondary.opacity(0.6), lineWidth: 1)
                    }
                }
            }
        }
    }

    private func lineRow(_ line: VerseAnnotationRenderer.VerseLine) -> some View {
        HStack(spacing: 0) {
            ForEach(line.segments) { segment in
                segmentView(segment)
                    .anchorPreference(key: VerseAnchorCollectionKey.self, value: .bounds) { anchor in
                        guard !segment.noteIDs.isEmpty else { return VerseAnchorCollection() }
                        var collection = VerseAnchorCollection()
                        for id in segment.noteIDs { collection.textAnchors[id] = [anchor] }
                        return collection
                    }
            }
            Spacer(minLength: 0)
        }
    }

    /// `segmentView`(`@ViewBuilder`)에서 분리한 순수 값 계산 — `@ViewBuilder` 안에서
    /// 값 대입용 `if/else`를 직접 쓰면 "Type '()' cannot conform to 'View'"가 나기 때문이다.
    private func baseTextColor(hasNote: Bool, hasHanja: Bool) -> Color {
        if hasNote { return VerseAnnotationRenderer.phraseNoteTextColor }
        if hasHanja { return VerseAnnotationRenderer.hanjaWordTextColor }
        return Color(textColor)
    }

    @ViewBuilder
    private func segmentView(_ segment: VerseAnnotationRenderer.VerseTextSegment) -> some View {
        let hasNote = !segment.noteIDs.isEmpty
        // 글자색 우선순위: 메모(파랑) > 한자 단어(갈색) > 기존 본문 색.
        let baseColor = baseTextColor(hasNote: hasNote, hasHanja: segment.hasHanja)
        let notesHere = phraseNotes.filter { segment.noteIDs.contains($0.id) }

        // 레거시 `.mark` 데이터와 관주가 걸린 조각 모두 같은 밑줄(주황 실선)을 켠다.
        // 분기별로 각각 걸면 바깥에서 다시 걸 때 `false`가 앞선 `true`를 덮어쓸 수 있어,
        // `underlineActive` 하나로 합쳐 단일 지점에서만 적용한다.
        let underlineActive = segment.hasCrossReference || segment.highlight?.style == .mark
        Group {
            switch segment.highlight?.style {
            case .highlight:
                let tag = HighlightColorTag(rawValue: segment.highlight?.colorTag ?? "") ?? .yellow
                Text(segment.text)
                    .font(Font(font))
                    .foregroundStyle(baseColor)
                    .background(tag.swiftUIColor.opacity(tag.backgroundOpacity))
            case .mark, nil:
                Text(segment.text)
                    .font(Font(font))
                    .foregroundStyle(baseColor)
            }
        }
        .underline(underlineActive, pattern: .solid, color: .orange)
        .contextMenu {
            if let highlight = segment.highlight {
                Button(highlight.style == .highlight ? "형광펜 취소" : "표시 취소", role: .destructive) {
                    onRequestRemoveHighlight(highlight)
                }
            }
            ForEach(notesHere) { note in
                Button("메모 수정") { onRequestEditPhraseNote(note) }
                Button("메모 삭제", role: .destructive) { onRequestDeletePhraseNote(note) }
            }
        }
    }

    /// 메모 박스의 가로 시작 위치를 그 표현의 화면상 위치 근처로 잡는다. 정확한 위치는
    /// 화살표가 보정하므로, 표현 앞에 오는 세그먼트들의 문자열 폭을 같은 폰트로 측정해
    /// 더한 근사치를 쓴다(어긋나도 기능은 깨지지 않는다).
    ///
    /// 박스가 실제로 밀릴 수 있는 폭은 좁은 본문 줄(`containerWidth`)이 아니라 화면 콘텐츠
    /// 영역 전체(`availableWidth`)이고, 박스 폭도 가변이라 고정 최대폭 대신
    /// `estimatedBoxWidth`를 뺀다. 그렇지 않으면 폭이 좁은 화면에서 최대 이동 거리가 항상
    /// 0이 되어 박스가 무조건 맨 왼쪽에서 시작하고 화살표만 길게 늘어진다.
    private func approximateLeadingOffset(
        for note: VersePhraseNote, in line: VerseAnnotationRenderer.VerseLine
    ) -> CGFloat {
        var widthBefore: CGFloat = 0
        for segment in line.segments {
            if segment.noteIDs.contains(note.id) { break }
            widthBefore += (segment.text as NSString).size(withAttributes: [.font: font]).width
        }
        let maxLeading = max(availableWidth - estimatedBoxWidth(for: note), 0)
        return min(widthBefore, maxLeading)
    }

    /// `PhraseNoteBoxView`의 가변 폭(내용에 맞춰 최대 `boxWidth`까지)을 미리 계산해
    /// `PhraseNoteBoxView.width`로 넘긴다 — `frame(maxWidth:)` + `fixedSize` 협상에
    /// 맡기면 실기기에서 가변폭이 제대로 동작하지 않아 고정 `frame(width:)`로 적용한다.
    ///
    /// 실제 SwiftUI 텍스트 레이아웃과 몇 pt 다를 수 있어 여유(+8pt)를 두고, 아주 짧은
    /// 메모도 너무 좁아 보이지 않도록 최소 60pt를 보장한다.
    private func estimatedBoxWidth(for note: VersePhraseNote) -> CGFloat {
        // 실제 렌더링은 `Text(...).font(.caption)`이다. `.caption`은 Dynamic Type
        // 텍스트 스타일이라 플랫폼과 사용자 글자 크기 설정에 따라 포인트 크기가 달라지므로,
        // 고정 12pt 대신 `preferredFont(forTextStyle: .caption1)`(SwiftUI `.caption`과 같은
        // 스타일)로 측정해야 텍스트가 길수록 커지는 누적 오차(오른쪽 여백 확대)가 생기지 않는다.
        let captionFont = PlatformFont.preferredFont(forTextStyle: .caption1)
        let textWidth = (note.noteText as NSString).size(withAttributes: [.font: captionFont]).width
        let padded = textWidth + 16 + 8 // .padding(8) 좌우 = 16, 여유 8
        return min(max(padded, 60), PhraseNoteBoxView.boxWidth)
    }

    /// 화살표가 첫 글자의 왼쪽 끝이 아니라 가운데를 가리키게 하는 보정값 — 메모가 붙은
    /// 표현의 첫 글자(`note.anchorText.first`)를 본문 폰트로 측정한 폭의 절반.
    /// 글리프 경계가 아닌 문자열 폭 근사치다.
    private func leadingCharacterHalfWidth(for note: VersePhraseNote) -> CGFloat {
        guard let firstChar = note.anchorText.first else { return 0 }
        let width = (String(firstChar) as NSString).size(withAttributes: [.font: font]).width
        return width / 2
    }
}
