//
//  AnnotatedVerseFlowView.swift
//  JBCHBibleResearch
//
//  [2026-08-11 8차 수정, 확대보기 전면 재설계] 사용자가 제공한 설계 문서
//  ("SwiftUI 성경 본문 주석 UI 명세")를 그대로 채택한 확대보기 "표시 모드" 전용
//  뷰 — 배경/근거는 `VerseAnnotationRenderer.swift` 상단 [2026-08-11 8차 수정]
//  주석 참고. 절 텍스트를 줄 단위(`VerseAnnotationRenderer.VerseLine`)로 나눠
//  각 줄을 SwiftUI `Text` 세그먼트의 `HStack`으로, 그 줄에 메모가 있으면 바로
//  아래에 실제 서브뷰(`PhraseNoteBoxView`)로 끼워 넣는다 — SwiftUI `VStack`이
//  원래 하는 "다음 콘텐츠를 밀어낸다"를 그대로 쓰므로, 예전처럼 메모 박스
//  높이를 미리 추측해 TextKit 줄간격에 몰래 주입하는 코드가 전혀 필요 없다.
//
//  형광펜/표시 취소, 메모 수정/삭제는 이제 우클릭(구 `SelectableVerseTextView`가
//  UIMenu/NSMenu를 플랫폼별로 손수 구성하던 방식)이 아니라, 각 세그먼트에
//  SwiftUI 표준 `.contextMenu`를 붙여 처리한다 — iOS는 길게 눌러서, macOS는
//  우클릭으로 뜨는 게 SwiftUI가 플랫폼별로 알아서 처리해 줘서 플랫폼 분기
//  코드가 사라졌다.
//
//  메모 박스와 그 표현을 잇는 화살표는 `anchorPreference`/`overlayPreferenceValue`
//  로 그린다 — 두 좌표(표현 세그먼트의 프레임, 박스의 프레임) 모두 SwiftUI
//  자신이 레이아웃한 결과를 그대로 읽는 것이라, 이 세션 내내 문제였던
//  "TextKit 글리프 좌표 ↔ SwiftUI 좌표"를 손으로 맞추는 작업 자체가 없다.
//

import SwiftUI
import BibleResearchModels

/// 표현 세그먼트(텍스트)와 메모 박스, 두 종류의 좌표를 한 `PreferenceKey`로
/// 함께 모은다 — 같은 뷰 트리 안에서 두 종류를 따로 모으려면
/// `.overlayPreferenceValue`를 중첩해야 해서 번거롭고, 화살표를 그릴 때
/// "이 메모 id의 텍스트 좌표"와 "이 메모 id의 박스 좌표"를 동시에 봐야 하므로
/// 하나의 구조체로 합쳐 두는 편이 자연스럽다.
private struct VerseAnchorCollection {
    /// 표현 세그먼트 좌표 — 한 메모의 앵커 표현이 형광펜 등으로 인해 세그먼트
    /// 여러 개로 쪼개질 수 있어(경계점 분해 원리, `VerseAnnotationRenderer.
    /// buildLines` 참고) 배열로 모은다. 화살표를 그릴 땐 이 배열의 합집합
    /// 사각형을 쓴다.
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

/// 메모 박스에서 그 표현으로 긋는 화살표 — `VerseZoomView.swift`의 옛
/// `NoteConnectorArrow`와 같은 모양(직선 + 화살촉)이지만, 좌표 출처가 전부
/// SwiftUI 프레임이라 훨씬 신뢰할 수 있다.
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
    /// [2026-08-12 추가] 사용자 요청 — "특정 텍스트를 선택하여 관주를 넣는
    /// 부분에 현재 밑줄처럼 표시할 것." `VerseAnnotationRenderer.buildLines(...)`
    /// 에 그대로 전달해 관주가 걸린 표현에 자동으로 밑줄이 그려지게 한다 —
    /// 자세한 배경은 그 함수 상단 주석 참고.
    let crossReferences: [VerseCrossReference]
    /// [2026-08-15 추가] 사용자 요청 — "확대보기 성경구절 수정 - 한자가 있는
    /// 단어는 색깔로 표현해 줄 것." `VerseAnnotationRenderer.buildLines(...)`
    /// 에 그대로 전달 — 관주와 같은 경계점 기반 조각 분해에 참여해 그 조각의
    /// `hasHanja`를 켠다(아래 `segmentView` 참고).
    var hanjaWords: [HanjaWordAnnotation] = []
    let font: PlatformFont
    let textColor: PlatformColor
    /// 줄바꿈 계산에 쓸 폭 — 호출부(`VerseZoomView`)가 실제 화면 폭(패딩 제외)을
    /// 넘긴다. `VerseAnnotationRenderer.lineRanges(...)`가 이 폭 기준으로 한글은
    /// `targetCharsPerLine`자 최근접 띄어쓰기, 라틴/혼합은 TextKit 측정으로 줄을
    /// 나눈다.
    let containerWidth: CGFloat
    /// [2026-08-12 추가] 사용자 질의 — "메모 상자 왼쪽 시작 위치가 제한이 있는지
    /// ... 지정텍스트보다 훨씬 왼쪽부터 시작이 되니까 화살표가 길게 늘어짐."
    /// 원인은 `approximateLeadingOffset`가 메모 박스를 밀 수 있는 최대 거리를
    /// `containerWidth`(성경 본문 한 줄의 좁은 목표 폭, 아이폰에서 200~300대)
    /// 기준으로 계산해 왔다는 것 — 그런데 메모 박스는 그 좁은 본문 줄 폭에
    /// 갇혀 있지 않고 화면 콘텐츠 영역 전체 폭까지 밀릴 수 있다. `availableWidth`
    /// (`VerseZoomView`의 스크롤 영역 실제 폭, 패딩만 뺀 값)를 별도로 받아 그
    /// 기준으로 계산하도록 고쳤다.
    let availableWidth: CGFloat
    /// [2026-08-12 추가] 세로/가로 모드마다 다른 줄당 글자수(사용자 요청) —
    /// `VerseZoomView.targetCharsPerLine` 참고.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                       let textAnchors = collection.textAnchors[note.id] {
                        let boxRect = proxy[boxAnchor]
                        let textRect = textAnchors.map { proxy[$0] }.reduce(CGRect.null) { $0.union($1) }
                        // [2026-08-12 재수정] 사용자 요청 — "화살표가 텍스트길이의
                        // 가로 가운데를 가리키는 것 같은데, 텍스트의 가장 맨 왼쪽
                        // 글자의 가운데를 가리키게 할 것." `textRect.minX`(가장
                        // 왼쪽 글자의 왼쪽 "끝")만으로는 아직 그 글자의 가운데가
                        // 아니라 요청과 다르다 — 첫 글자 폭의 절반
                        // (`leadingCharacterHalfWidth`, 아래)을 더해 그 글자의
                        // 가운데를 근사한다.
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

    /// [2026-08-15 신설] `segmentView`(아래, `@ViewBuilder`)에서 분리한 순수
    /// 값 계산 — 이 함수 자체는 `@ViewBuilder`가 아니라 안에서 평범한
    /// `if`/`return`을 자유롭게 쓸 수 있다.
    private func baseTextColor(hasNote: Bool, hasHanja: Bool) -> Color {
        if hasNote { return VerseAnnotationRenderer.phraseNoteTextColor }
        if hasHanja { return VerseAnnotationRenderer.hanjaWordTextColor }
        return Color(textColor)
    }

    @ViewBuilder
    private func segmentView(_ segment: VerseAnnotationRenderer.VerseTextSegment) -> some View {
        let hasNote = !segment.noteIDs.isEmpty
        // [2026-08-15 추가, 같은 날 컴파일 에러 수정] 사용자 요청 — "한자가
        // 있는 단어는 색깔로 표현." 메모 글자색(파랑)이 이미 있으면 그게
        // 우선(기존 규칙 유지), 메모가 없고 한자 단어면 `hanjaWordTextColor`
        // (갈색), 둘 다 아니면 기존 본문 색 그대로.
        // ⚠️ [컴파일 에러] `if/else if/else`로 직접 대입하면 "Type '()'
        // cannot conform to 'View'"가 난다 — 이 함수가 `@ViewBuilder`라서,
        // View를 만들지 않는 일반 `if` 문(단순 값 대입)까지도 빌더가 "View를
        // 만드는 분기"로 해석하려 시도해 실패한다. 아래처럼 View가 아닌
        // 일반 함수 호출로 값을 계산해 대입하면(함수 "안"의 if/else는
        // `@ViewBuilder`의 영향을 받지 않는다) 문제없다.
        let baseColor = baseTextColor(hasNote: hasNote, hasHanja: segment.hasHanja)
        let notesHere = phraseNotes.filter { segment.noteIDs.contains($0.id) }

        // [2026-08-12 변경] 사용자 요청 — "특정 텍스트를 선택하여 관주를 넣는
        // 부분에 현재 밑줄처럼 표시할 것." 예전 "표시"(`.mark`, 사용자가 직접
        // 켜던 밑줄)와 같은 시각 스타일(주황 실선)을, 이제 관주가 걸린 조각에도
        // 켠다 — 두 조건(레거시 `.mark` 데이터 / 관주 있음) 중 하나라도
        // 참이면 밑줄이 켜지도록 `underlineActive` 하나로 합쳐, 스위치 분기
        // 끝에 공통으로 딱 한 번만 적용한다(분기별로 각각 걸면, 나중에 이
        // Group 바깥에서 또 걸 때 `false`가 앞서 걸린 `true`를 덮어써 버리는
        // 순서 문제가 생길 수 있어 — 항상 단일 지점에서만 적용).
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

    /// [2026-08-11 8차 수정] 메모 박스의 가로(X) 시작 위치를 "그 표현의 화면상
    /// 위치를 기준으로" 정하라는 설계 문서 요구를 반영한다. 정확한 위치는
    /// 화살표(`NoteConnectorArrow`, 실제 SwiftUI 프레임 기반)가 보정해 주므로,
    /// 여기서는 박스가 "대략 그 근처"에서 시작하도록 그 표현 앞에 오는
    /// 세그먼트들의 문자열 폭을 같은 폰트로 측정해 더한다 — TextKit 좌표를
    /// 전혀 쓰지 않는 순수 문자열 측정이라 이 세션의 버그들과 무관한 종류의
    /// 근사치다(어긋나도 화살표가 정확한 위치를 가리켜 주므로 기능이 깨지지
    /// 않는다).
    ///
    /// [2026-08-12 수정] 사용자 질의로 확인된 버그 — 예전엔 `maxLeading =
    /// containerWidth - PhraseNoteBoxView.boxWidth`(박스의 고정 최대폭 300)로
    /// 계산했는데, 아이폰처럼 `containerWidth`(본문 한 줄의 좁은 목표 폭)가
    /// 300보다 작은 화면에서는 이 값이 항상 0이 되어 — 표현이 줄의 어디에
    /// 있든 박스가 무조건 맨 왼쪽에서 시작하고, 화살표만 길게 늘어졌다. 이제
    /// (1) 박스가 실제로 밀릴 수 있는 폭은 좁은 본문 줄이 아니라 화면 콘텐츠
    /// 영역 전체(`availableWidth`)이고, (2) 박스 폭 자체도 이제 가변(최대
    /// 300)이므로 고정 300 대신 메모 텍스트 길이로 추정한 실제 폭
    /// (`estimatedBoxWidth`)을 뺀다 — 둘 다 고쳐야 짧은 메모가 표현 바로
    /// 아래/근처에서 시작할 수 있다.
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

    /// [2026-08-12 신설, 2026-08-12 재수정] `PhraseNoteBoxView`가 이제 고정
    /// 300이 아니라 내용에 맞춰 최대 300까지 커지는 가변 폭이라(사용자 요청,
    /// `PhraseNoteBoxView.swift` 참고) 그 실제 렌더링 폭을 여기서 미리 계산해
    /// `PhraseNoteBoxView.width`로 그대로 넘긴다 — SwiftUI의 `frame(maxWidth:)`
    /// + `fixedSize` 레이아웃 협상에 맡겼을 때 실기기에서 가변폭이 제대로
    /// 동작하지 않는 문제가 있어(사용자 보고), 협상 대신 이 값을 직접 계산해
    /// 고정 `frame(width:)`로 적용하는 방식으로 바꿨다.
    ///
    /// `.caption` 크기(대략 12pt)로 근사 측정한다 — 정확한 SwiftUI 텍스트
    /// 레이아웃과 몇 pt씩 다를 수 있어, 너무 타이트해서 불필요하게 줄바꿈되는
    /// 것을 피하려고 여유(+8pt)를 살짝 더 둔다. 아주 짧은 메모(예: 한 글자)도
    /// 너무 좁아 보이지 않도록 최소 60pt를 보장한다.
    private func estimatedBoxWidth(for note: VersePhraseNote) -> CGFloat {
        let captionFont = PlatformFont.systemFont(ofSize: 12)
        let textWidth = (note.noteText as NSString).size(withAttributes: [.font: captionFont]).width
        let padded = textWidth + 16 + 8 // .padding(8) 좌우 = 16, 여유 8
        return min(max(padded, 60), PhraseNoteBoxView.boxWidth)
    }

    /// [2026-08-12 신설] 화살표가 "첫 글자의 왼쪽 끝"이 아니라 "첫 글자의
    /// 가운데"를 가리키게 하기 위한 보정값 — 메모가 붙은 표현의 첫 글자
    /// (`note.anchorText.first`)를 본문 폰트(`font`, 이 뷰가 실제로 절 텍스트를
    /// 그릴 때 쓰는 것과 동일)로 측정해 그 폭의 절반을 돌려준다. 다른 근사
    /// 계산들(`estimatedBoxWidth` 등)과 같은 원칙 — 정확한 글리프 경계가
    /// 아니라 문자열 폭 측정 근사치지만, 화살표가 "대략 어디를 가리키는지"
    /// 안내하는 용도로는 충분하다.
    private func leadingCharacterHalfWidth(for note: VersePhraseNote) -> CGFloat {
        guard let firstChar = note.anchorText.first else { return 0 }
        let width = (String(firstChar) as NSString).size(withAttributes: [.font: font]).width
        return width / 2
    }
}
