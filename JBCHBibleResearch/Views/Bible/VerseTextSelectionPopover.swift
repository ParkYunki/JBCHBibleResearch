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
//  `.popover(item:)`로 띄운다 — SwiftUI의 `.popover`는 아이폰(컴팩트 폭)에서
//  자동으로 시트 형태로, 아이패드/macOS에서는 원래의 팝오버 형태로 적응해서
//  뜨므로, "작은 팝오버/시트"라는 요청을 플랫폼별 분기 없이 이 한 가지
//  구현으로 만족한다.
//
//  [2026-09-05 근본 재설계] 사용자 보고 — 이 팝오버에서 텍스트를 드래그로
//  선택하는 동안 한글 번역본에서만 선택 영역이 아주 빠르게 깜박임(영문은
//  정상). 처음엔 이 팝오버가 재사용하던 `SelectableVerseTextView`(확대보기
//  전용으로 만든 커스텀 TextKit 엔진 — 직접 짠 `NSLayoutManager` 서브클래스,
//  표시 모드와 줄바꿈을 맞추려는 보이지 않는 문자 삽입 등)안에서 원인을
//  두 차례 추정해 고쳤지만(그 파일의 `hasExplicitBackgroundColorAttribute`/
//  `matchDisplayModeLineBreaks` 관련 주석 참고) 둘 다 실제 원인이 아니었다 —
//  재현이 계속됐다.
//
//  이 팝오버의 실제 목적은 "이 번역본 이 구절에서 일부 텍스트만 순수하게
//  골라 복사"하는 것뿐이라, 애초에 `SelectableVerseTextView`가 필요했던
//  이유(정확한 문자 범위를 앱 코드로 읽어와 DB에 저장하는 것 — 형광펜/메모/
//  관주를 만드는 확대보기의 요구사항)가 이 화면에는 없다. 컴파일러/기기 없이
//  세 번째 추정을 더 얹는 대신, 사용자와 상의해 이 팝오버 전용으로 그
//  커스텀 엔진 자체를 걷어내고 SwiftUI 기본 `.textSelection(.enabled)`로
//  바꿨다 — 드래그 선택을 OS가 직접 그리고 관리하므로, 지금까지 찾은
//  원인이든 아직 못 찾은 원인이든 이 앱의 커스텀 코드가 그 과정에 전혀
//  개입하지 않아 구조적으로 재발할 수 없다.
//
//  대가(사용자 확인 후 진행): 이 앱 코드로 "정확히 몇 번째~몇 번째 글자를
//  선택했는지" 다시 읽어올 방법이 없다 — SwiftUI의 `.textSelection`은 선택
//  UI만 공짜로 제공할 뿐 그 범위를 코드로 노출하지 않는다. 그래서 부분
//  선택 복사는 OS 자체 복사(맥 ⌘C·우클릭 복사, iOS 길게 눌러 복사)에 맡기고,
//  이 팝오버의 "복사" 버튼은 선택 여부와 무관하게 절 전체(한자 삽입 포함)를
//  복사하는 용도로 단순화했다 — 확대보기(`VerseZoomView`)는 여전히 정확한
//  범위가 필요하므로 `SelectableVerseTextView`를 그대로 쓴다(이 파일과는
//  무관, 영향 없음).
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
    /// 영향이 없다.
    var hanjaWords: [HanjaWordAnnotation] = []
    /// 복사 확정 시 넘길 텍스트 — 실제 클립보드 접근/토스트 표시는 book/chapter나
    /// 토스트 상태를 들고 있는 호출부(`BibleReadingView`)의 책임이다(다른
    /// 복사 경로들과 같은 원칙).
    var onCopy: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    /// [2026-08-27 신설] 한자 주석이 괄호로 삽입된, 실제로 화면에 보여줄
    /// 텍스트. `VerseAnnotationRenderer.plainTextWithInlineHanja`는 본문
    /// 읽기 화면의 `attributedContentWithInlineAnnotations`와 동일한 삽입
    /// 알고리즘을 쓴다. `hanjaWords`가 빈 배열이면 원본 `text`를 그대로
    /// 돌려주므로 개역한글이 아닌 번역본은 동작 변화가 없다.
    private var displayText: String {
        VerseAnnotationRenderer.plainTextWithInlineHanja(text: text, hanjaWords: hanjaWords)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(translationDisplayName) \(verseNumber)절 — 드래그(또는 길게 눌러)로 선택한 뒤 복사하세요")
                .font(.caption)
                .foregroundStyle(.secondary)

            // [2026-09-05 근본 재설계] 위 파일 상단 주석 참고 — 커스텀
            // TextKit 대신 SwiftUI 기본 `.textSelection(.enabled)`. 드래그로
            // 고른 부분은 OS 자체 복사(⌘C/우클릭/길게 눌러 복사)로 바로
            // 복사할 수 있다.
            ScrollView {
                Text(displayText)
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 280, height: 200)

            HStack {
                Button("취소") { dismiss() }
                Spacer()
                Button("복사") {
                    // [2026-09-05 변경] 위 파일 상단 주석 참고 — 이제 이
                    // 버튼은 부분 선택과 무관하게 항상 절 전체를 복사한다
                    // (부분 선택 복사는 OS 자체 복사에 맡긴다).
                    onCopy(displayText)
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
