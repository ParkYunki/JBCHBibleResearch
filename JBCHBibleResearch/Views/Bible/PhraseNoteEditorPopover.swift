//
//  PhraseNoteEditorPopover.swift
//  JBCHBibleResearch
//
//  [2026-08-11 신설] 사용자 요청 — "특정 표현부분을 드래그해서 부연설명하는 기능을
//  추가 구현하도록. 기능명: [메모]. 메모는 단순 텍스트 입력임(한글 기준 200자
//  미만)." `VersePhraseNote`를 만들거나 고칠 때 쓰는 작은 팝오버 — 드래그한
//  표현을 위에 인용해 보여주고, 아래에 짧은 텍스트 입력란과 글자 수 카운터를
//  둔다. `VerseZoomView`(확대보기)의 "메모" 액션 버튼과, `SelectableVerseTextView`의
//  우클릭 "메모 수정" 둘 다 이 팝오버를 연다(전자는 새로 만들기, 후자는 수정).
//

import SwiftUI
import BibleResearchModels

/// [2026-08-11 15차 수정] 사용자가 제공한 두 라운드의 `[메모진단]` 로그로
/// 확인한 것 — `anchorText`/`isEditing`을 이 뷰의 `init(...)`에서 `let`
/// 상수로 한 번 받아 두는 예전 설계는, "탭 시점에 계산한 값"과 "초기화
/// 시점에 실제로 이 뷰가 받는 값"이 SwiftUI 내부적으로 어긋나는 경우가
/// 실측으로 확인됐다(예: 같은 텍스트를 골라도 어떤 시도는 성공, 어떤
/// 시도는 3번 연속 실패 — `.id(...)`로 뷰 정체성을 새로 만들어도, 팝오버를
/// 여는 시점을 다음 런루프 틱으로 미뤄도 패턴이 사라지지 않았다). 즉
/// "언제 스냅샷을 뜨느냐"의 문제가 아니라 "생성자 인자로 값을 한 번만
/// 받는 것 자체"가 문제였을 가능성이 높다고 판단해, 아예 그 경로를
/// 없앴다 — `anchorText`/`editingPhraseNote`를 `@Binding`으로 받아,
/// `body`가 그릴 때마다(그리고 `.onAppear`가 뷰가 실제로 화면에 붙은
/// 뒤에) 항상 "그 순간의" 값을 다시 읽는다. `@Binding`의 `get` 클로저는
/// SwiftUI가 그 값을 참조할 때마다 매번 새로 호출되는 것이라, 구조체
/// 생성 시점에 값을 "얼려서" 들고 있는 `let`과는 근본적으로 다르다.
struct PhraseNoteEditorPopover: View {
    /// nil이면 새 메모, 값이 있으면 그 메모를 수정 중.
    @Binding var editingPhraseNote: VersePhraseNote?
    /// 새 메모를 만드는 중일 때(`editingPhraseNote == nil`) 쓸 앵커 텍스트.
    @Binding var pendingAnchorText: String
    var onSave: (String) -> Void
    /// 수정 중인 노트를 인자로 받아 삭제한다 — 이전엔 `onDelete: (() -> Void)?`
    /// 로 노트를 미리 캡처해 뒀는데(닫힌 클로저), 그 캡처 시점도 같은 종류의
    /// 어긋남 위험이 있어 탭 시점에 `editingPhraseNote`를 직접 읽어 넘기는
    /// 쪽으로 바꿨다.
    var onDelete: (VersePhraseNote) -> Void = { _ in }

    @State private var noteText: String = ""
    @Environment(\.dismiss) private var dismiss

    private var anchorText: String { editingPhraseNote?.anchorText ?? pendingAnchorText }
    private var isEditing: Bool { editingPhraseNote != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("“\(anchorText)”")
                .font(.callout.bold())
                .lineLimit(2)
                .foregroundStyle(.secondary)

            // [2026-08-11 추가] "메모는 단순 텍스트 입력임" — 리치 텍스트 에디터
            // (RichTextEditor, "개인 주석"이 쓰는 것)와 달리 서식 없는 순수 텍스트.
            TextEditor(text: $noteText)
                .font(.body)
                .frame(minHeight: 90, maxHeight: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .onChange(of: noteText) { _, newValue in
                    // "한글 기준 200자 미만" — 초과분은 입력 즉시 잘라낸다.
                    if newValue.count > NoteTextLimit.maxCharacters {
                        noteText = String(newValue.prefix(NoteTextLimit.maxCharacters))
                    }
                }

            Text("\(noteText.count)/\(NoteTextLimit.maxCharacters)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)

            HStack {
                if let note = editingPhraseNote {
                    Button("삭제", role: .destructive) {
                        onDelete(note)
                        dismiss()
                    }
                }
                Spacer()
                Button("취소") { dismiss() }
                Button("저장") {
                    onSave(noteText)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
        // [2026-08-11 15차 수정] 뷰가 실제로 화면에 붙은 뒤(레이아웃이 끝난
        // 뒤) 딱 한 번 `noteText`를 시드한다 — `init`에서 미리 받아 두는
        // 것보다 훨씬 늦은 시점이라, 그 시점엔 부모 쪽 상태 변경이 확실히
        // 다 반영되어 있다.
        .onAppear {
            noteText = editingPhraseNote?.noteText ?? ""
        }
    }
}

/// [2026-08-11 신설, 2026-08-11 8차 수정 전면 개편] 사용자 요청 — "확대보기 -
/// 성경 본문 하단 관주, 메모정보가 있는 라인에 [관련 내용] 추가... 메모를
/// 나타내는 점선 박스." 예전엔 `SelectableVerseTextView`(TextKit)가 미리
/// 계산해 준 `PhraseNoteOverlayRect`(좌표 + `estimatedContentHeight` 추정치)를
/// 받아 그 좌표에 `.offset`으로 겹쳐 그렸다 — 이제는 사용자가 제공한 설계
/// 문서("SwiftUI 성경 본문 주석 UI 명세")를 따라 `AnnotatedVerseFlowView`의
/// `VStack` 안에 놓이는 "평범한 SwiftUI 서브뷰"로 바뀌었다: `VersePhraseNote`
/// (원본 데이터)를 직접 받아 SwiftUI 자신의 텍스트 레이아웃이 실제 높이를
/// 계산하게 둔다 — `estimatedContentHeight`(NSString.boundingRect 근사치, 실기기
/// 렌더링과 몇 pt씩 어긋나던 것)가 아예 필요 없어졌다. 위치(X/Y)도 더 이상
/// TextKit 글리프 좌표가 아니라 `VStack`의 문서 흐름 자체이므로, 이 뷰는 오직
/// "내용에 맞춰 커지는 점선 박스"만 책임진다.
struct PhraseNoteBoxView: View {
    let note: VersePhraseNote
    /// [2026-08-12 재수정] 사용자 보고 — "메모 상자의 가로크기가 글자수에 따라
    /// 가변적으로 그려지지 않음." 처음엔 `.frame(maxWidth: boxWidth)` +
    /// `.fixedSize(horizontal: false, ...)` 조합으로 "짧으면 좁게, 길면 300까지"
    /// 를 SwiftUI의 레이아웃 협상에 맡겼는데, 실기기에서 두 메모의 실제 길이가
    /// 서로 달라도 박스가 거의 같은(넓은) 폭으로 그려지는 게 확인됐다 — 이
    /// 뷰는 `VStack(alignment: .leading)` 안에서 같은 줄의 성경 본문
    /// (`lineRow`)과 형제 관계인데, 그 본문 줄이 이미 상당히 넓게(18~23자 폭)
    /// 그려져 있으면 VStack이 그 폭을 기준으로 자식들에게 큰 값을 제안하고,
    /// `frame(maxWidth:)` + `fixedSize`가 그 큰 제안을 그대로 받아들이는
    /// 경로가 있었던 것으로 보인다(정확한 SwiftUI 내부 협상 규칙까지 단정하긴
    /// 어렵지만, 재현 결과가 이 가설과 일치한다). 협상에 기대는 대신, 호출부
    /// (`AnnotatedVerseFlowView.estimatedBoxWidth`)가 메모 텍스트 길이로 미리
    /// 직접 측정한 폭을 그대로 받아 `.frame(width:)`(고정값)로 적용한다 —
    /// 레이아웃 협상 여지를 아예 없애 결과가 항상 예측 가능하다. 이 값은
    /// `approximateLeadingOffset`가 화살표/오프셋을 계산할 때 쓰는 값과 정확히
    /// 같은 함수로 구해, 박스의 "실제 그려지는 폭"과 "오프셋 계산이 가정하는
    /// 폭"이 서로 어긋날 일이 없다.
    let width: CGFloat
    var onTap: () -> Void

    /// [2026-08-11 2차 수정] 사용자 요청 — "메모를 표시하는 박스는... 최대
    /// 300x100으로 할 것." 높이는 설계 문서의 "메모 내용에 따라 세로 높이만
    /// 자동으로 증가한다"를 그대로 따라 상한을 없앴다(예전 `maxHeight: 100` +
    /// `clipped()`는 SwiftUI가 실제로 계산한 높이를 억지로 잘라내는 것이었는데,
    /// 이제 그 실제 높이가 곧 예약된 공간이라 — `VStack`이 그 뒤 콘텐츠를
    /// 자동으로 밀어내므로 — 잘라낼 이유가 없다). 폭의 상한값 — 실제 적용은
    /// 이제 `width`(호출부가 미리 계산해 넘기는 값)를 통해서만 이뤄지고, 이
    /// 상수는 그 계산의 상한 기준으로만 쓰인다.
    static let boxWidth: CGFloat = 300

    /// [2026-08-12 추가] 사용자 요청 — "메모상자 배경색 추가: 형광펜 색 연하게
    /// 20~30%정도 랜덤 색상으로 보여지게 - 한번 지정되면 다음에 열어도 바뀌지
    /// 않게 - DB저장." 실제 무작위 선택은 메모를 처음 만들 때 딱 한 번
    /// (`BibleReadingViewModel.addPhraseNote`)만 일어나고, 그 결과
    /// (`note.colorTagRaw`)를 여기서는 그대로 읽어 옅게(25%, 요청 범위
    /// 20~30% 안) 칠하기만 한다 — 이 필드가 생기기 전에 만들어진 메모
    /// (`colorTagRaw`가 빈 문자열)는 고정값(노랑)으로 안전하게 대체한다.
    private var backgroundColor: Color {
        (HighlightColorTag(rawValue: note.colorTagRaw)?.swiftUIColor ?? HighlightColorTag.yellow.swiftUIColor)
            .opacity(0.25)
    }

    var body: some View {
        Text(note.noteText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(8)
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor)
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.6))
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
    }
}
