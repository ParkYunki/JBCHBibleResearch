//
//  VerseTextSelectionPopover.swift
//  JBCHBibleResearch
//
//  [2026-08-26 신설] 사용자 요청 — "iOS 성경 구절 길게 프레스/맥OS 마우스
//  오른쪽버튼 → [선택] 메뉴 추가 - 일부 텍스트를 선택하여 복사할 수 있는
//  기능." 어떤 화면으로 구현할지 사용자에게 직접 확인한 결과 — "작은
//  팝오버/시트로 그 자리에서 선택"을 선택했다(확대보기 VerseZoomView 전체를
//  열지 않는 쪽).
//
//  드래그로 정확한 문자 범위(NSRange)를 고르는 것 자체는 확대보기가 이미
//  갖고 있는 `SelectableVerseTextView`(TextKit 기반, `selectedRange`를 정확히
//  읽어 온다)를 그대로 재사용한다 — 이 팝오버는 그 위에 "복사" 버튼 하나를
//  얹은 얇은 껍데기일 뿐이다. 형광펜/메모/관주/한자 같은 주석 데이터는 일부러
//  넘기지 않는다(빈 배열) — 이 팝오버의 목적은 "이 번역본 이 구절에서 일부
//  텍스트만 순수하게 골라 복사"이지 주석을 보여주는 것이 아니고, 성경 조회
//  화면(TranslationColumnView)의 컨텍스트 메뉴에서 호출되므로 굳이 그 데이터를
//  다시 끌어올 필요가 없다.
//
//  `.popover(item:)`로 띄운다 — SwiftUI의 `.popover`는 아이폰(컴팩트 폭)에서
//  자동으로 시트 형태로, 아이패드/macOS에서는 원래의 팝오버 형태로 적응해서
//  뜨므로, "작은 팝오버/시트"라는 요청을 플랫폼별 분기 없이 이 한 가지
//  구현으로 만족한다.
//

import SwiftUI
import BibleResearchModels

struct VerseTextSelectionPopover: View {
    let verseNumber: Int
    let translationDisplayName: String
    let text: String
    /// [2026-08-27 신설] 사용자 요청 — "개역한글(번들 성경)인 경우 한자
    /// 주석까지 같이 나오도록(한자도 복사 가능하게)." 개역한글이 아니면
    /// 호출부(`BibleReadingView`)가 `viewModel.hanjaWords(...)`를 통해 항상
    /// 빈 배열을 넘기므로, 이 프로퍼티는 무조건 받아도 다른 번역본에는
    /// 영향이 없다. 기본값 `[]`을 둔 이유는 이 뷰가 "이 번역본 이 구절에서
    /// 일부 텍스트만 순수하게 골라 복사"라는 원래 목적상 대부분 호출부가
    /// 주석 데이터를 넘기지 않아도 되게 하기 위함이다(위 파일 상단 주석 참고).
    var hanjaWords: [HanjaWordAnnotation] = []
    /// 복사 확정 시 넘길 텍스트 — 실제 클립보드 접근/토스트 표시는 book/chapter나
    /// 토스트 상태를 들고 있는 호출부(`BibleReadingView`)의 책임이다(다른
    /// 복사 경로들과 같은 원칙).
    var onCopy: (String) -> Void

    @State private var selectedRange = NSRange(location: 0, length: 0)
    @Environment(\.dismiss) private var dismiss

    private var font: PlatformFont { .systemFont(ofSize: 16) }
    private var textColor: PlatformColor {
        #if os(iOS)
        .label
        #else
        .labelColor
        #endif
    }

    /// [2026-08-27 신설] 한자 주석이 괄호로 삽입된, 실제로 화면에 보여주고
    /// 드래그 대상으로 삼을 텍스트. `VerseAnnotationRenderer.plainTextWithInlineHanja`는
    /// 본문 읽기 화면의 `attributedContentWithInlineAnnotations`와 동일한
    /// 삽입 알고리즘을 쓰되(뒤에서부터 삽입해 앞쪽 오프셋이 안 밀리게),
    /// 이 뷰 전용의 별도 함수다 — `SelectableVerseTextView`가 이미 쓰고 있는
    /// `selectionModeAttributedText`(확대보기 형광펜/메모 생성용, 원본
    /// `verse.content`의 오프셋을 그대로 보존해야 함)는 절대 건드리지
    /// 않는다. `hanjaWords`가 빈 배열이면 원본 `text`를 그대로 돌려주므로
    /// 개역한글이 아닌 번역본은 동작 변화가 없다.
    private var displayText: String {
        VerseAnnotationRenderer.plainTextWithInlineHanja(text: text, hanjaWords: hanjaWords)
    }

    /// 지금 드래그로 고른 부분 문자열 — `selectedRange`는 `SelectableVerseTextView`
    /// 상단 주석이 명시한 대로 UTF-16 단위 `NSRange`라, `Range(_:in:)`으로
    /// 안전하게 `String` 부분범위로 바꾼다(범위가 어긋나면 nil이 되므로 빈
    /// 문자열로 처리 — 아래 "복사"가 그 경우 전체 텍스트로 대체한다).
    /// 한자가 삽입된 `displayText` 기준으로 계산해야 화면에 보이는 좌표와
    /// 실제로 잘라내는 문자열이 일치한다(원본 `text` 기준이면 한자가 삽입된
    /// 만큼 오프셋이 밀려 엉뚱한 부분이 잘린다).
    private var selectedText: String {
        guard selectedRange.length > 0, let range = Range(selectedRange, in: displayText) else { return "" }
        return String(displayText[range])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(translationDisplayName) \(verseNumber)절 — 복사할 부분을 드래그로 선택하세요")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                SelectableVerseTextView(
                    // [2026-08-27 변경] 한자가 괄호로 삽입된 `displayText`를
                    // 보여준다. `SelectableVerseTextView`의 `hanjaWords`
                    // 파라미터는 원본 `text` 기준 오프셋을 전제로 하므로
                    // (선택 모드 색칠용), 여기서는 기본값 `[]`로 그대로 두고
                    // 대신 텍스트 자체에 한자를 바로 박아 넣는 방식을 썼다 —
                    // 둘을 같이 넘기면 오프셋이 어긋난다.
                    text: displayText, font: font, textColor: textColor,
                    containerWidth: 280, targetCharsPerLine: 20,
                    highlights: [], phraseNotes: [], crossReferences: [],
                    selectedRange: $selectedRange
                )
                .frame(width: 280)
            }
            .frame(maxHeight: 200)

            HStack {
                Button("취소") { dismiss() }
                Spacer()
                Button("복사") {
                    // 아무것도 드래그로 고르지 않고 눌러도(길이 0) 빈 문자열을
                    // 복사하는 대신 절 전체를 복사한다 — "선택"에 들어왔다가
                    // 아무 반응 없이 끝나는 것보다, 기존 "복사"(전체) 동작으로
                    // 안전하게 폴백하는 편이 낫다고 판단했다.
                    onCopy(selectedText.isEmpty ? displayText : selectedText)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
    }
}
