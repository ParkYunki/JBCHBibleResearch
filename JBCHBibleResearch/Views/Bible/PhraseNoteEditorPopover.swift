//
//  PhraseNoteEditorPopover.swift
//  JBCHBibleResearch
//
//  드래그한 표현에 다는 짧은 텍스트 메모(`VersePhraseNote`)의 편집 팝오버와 표시 박스.
//  팝오버는 드래그한 표현을 위에 인용하고 아래에 입력란과 글자 수 카운터를 둔다 —
//  `VerseZoomView`의 "메모" 버튼(새로 만들기)과 `SelectableVerseTextView`의 우클릭
//  "메모 수정"(수정)이 연다. `PhraseNoteBoxView`는 본문 흐름 안에 놓이는 점선 메모 박스.
//

import SwiftUI
import BibleResearchModels

/// `anchorText`/`editingPhraseNote`를 `init`의 `let`이 아니라 `@Binding`으로 받아 `body`가 그릴 때마다
/// 그 순간의 값을 다시 읽는다. 생성자 인자로 값을 한 번만 받으면 탭 시점에 계산한 값과 실제로
/// 받는 값이 어긋나는 경우가 실측으로 확인됐다.
struct PhraseNoteEditorPopover: View {
    /// nil이면 새 메모, 값이 있으면 그 메모를 수정 중.
    @Binding var editingPhraseNote: VersePhraseNote?
    /// 새 메모를 만드는 중일 때(`editingPhraseNote == nil`) 쓸 앵커 텍스트.
    @Binding var pendingAnchorText: String
    var onSave: (String) -> Void
    /// 수정 중인 노트를 인자로 받아 삭제한다(탭 시점에 `editingPhraseNote`를 직접 읽어 넘기므로
    /// 미리 캡처한 값과 어긋날 일이 없다).
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

            // 서식 없는 순수 텍스트 입력(리치 텍스트 에디터와 다름).
            TextEditor(text: $noteText)
                .font(.body)
                .frame(minHeight: 90, maxHeight: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .onChange(of: noteText) { _, newValue in
                    // 글자 수 상한을 넘는 초과분은 입력 즉시 잘라낸다.
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
        // 뷰가 화면에 붙은 뒤 한 번만 `noteText`를 시드한다(부모 상태 변경이 모두 반영된 시점).
        .onAppear {
            noteText = editingPhraseNote?.noteText ?? ""
        }
    }
}

/// 메모를 나타내는 점선 박스. `AnnotatedVerseFlowView`의 `VStack` 안에 놓이는 일반 SwiftUI 서브뷰로,
/// `VersePhraseNote`를 직접 받아 SwiftUI가 실제 높이를 계산하게 둔다(내용에 맞춰 세로로 커짐).
struct PhraseNoteBoxView: View {
    let note: VersePhraseNote
    /// 박스 폭. 레이아웃 협상에 맡기면 짧은 메모도 넓게 그려져서, 호출부(`AnnotatedVerseFlowView.estimatedBoxWidth`)가
    /// 메모 길이로 미리 측정한 값을 `.frame(width:)`로 고정 적용한다. `approximateLeadingOffset`과 같은
    /// 함수로 구해 실제 폭과 오프셋 계산이 가정하는 폭이 어긋나지 않는다.
    let width: CGFloat
    var onTap: () -> Void

    /// 폭 상한(실제 적용은 `width`로 하고 이 값은 호출부 계산의 상한 기준). 높이는 상한 없이 내용에 맞춰 커진다.
    static let boxWidth: CGFloat = 300

    /// 배경색은 메모를 처음 만들 때 한 번 무작위로 정해 `note.colorTagRaw`에 저장한 값을 옅게(25%) 칠한다.
    /// `colorTagRaw`가 빈 문자열인 예전 메모는 노랑으로 대체한다.
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
