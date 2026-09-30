//
//  VerseTextSelectionPopover.swift
//  JBCHBibleResearch
//
//  성경 구절 길게 누르기(iOS)/우클릭(macOS) → [선택] 메뉴에서 뜨는 작은 팝오버.
//  일부 텍스트를 골라 복사할 수 있다. `.popover(item:)`는 아이폰(컴팩트 폭)에서 시트로,
//  아이패드/macOS에서는 팝오버로 자동 적응하므로 플랫폼 분기가 필요 없다.
//
//  선택 UI는 커스텀 TextKit(`SelectableVerseTextView`)이 아니라 SwiftUI 기본
//  `.textSelection(.enabled)`를 쓴다 — 한글 번역본에서 드래그 선택 영역이 깜박이던
//  문제를 커스텀 엔진 안에서 고치지 못해, 선택을 OS가 직접 그리게 해 구조적으로 피했다.
//  대가: 선택한 문자 범위를 코드로 읽을 수 없어, 부분 복사는 OS 자체 복사(⌘C/우클릭/길게 눌러 복사)에
//  맡기고 "복사" 버튼은 선택과 무관하게 절 전체(한자 삽입 포함)를 복사한다.
//  정확한 범위가 필요한 확대보기(`VerseZoomView`)는 `SelectableVerseTextView`를 그대로 쓴다.
//

import SwiftUI
import BibleResearchModels

struct VerseTextSelectionPopover: View {
    /// 성경 본문 테마(`bibleTextColor`)를 따르기 위한 계산 프로퍼티.
    private var settings: UserSettingsStore { .shared }
    let verseNumber: Int
    let translationDisplayName: String
    let text: String
    /// 한자 주석. 개역한글이 아니면 호출부가 빈 배열을 넘기므로 다른 번역본에는 영향이 없다.
    var hanjaWords: [HanjaWordAnnotation] = []
    /// 복사 확정 시 넘길 텍스트 — 클립보드 접근/토스트 표시는 호출부(`BibleReadingView`)의 책임이다.
    var onCopy: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    /// 한자 주석이 괄호로 삽입된 표시용 텍스트. `hanjaWords`가 비어 있으면 원본 `text` 그대로다.
    private var displayText: String {
        VerseAnnotationRenderer.plainTextWithInlineHanja(text: text, hanjaWords: hanjaWords)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(translationDisplayName) \(verseNumber)절 — 드래그(또는 길게 눌러)로 선택한 뒤 복사하세요")
                .font(.caption)
                .foregroundStyle(.secondary)

            // `ScrollView`로 감싸지 않는다 — iOS에서 스크롤 팬 제스처가 `.textSelection`의
            // 드래그 선택 제스처와 경쟁해 선택이 시작되지 않고 OS 퀵메뉴만 뜬다.
            // 대가: 매우 긴 절은 스크롤 없이 팝업 높이가 그만큼 커진다.
            Text(displayText)
                .font(.system(size: 16))
                .foregroundStyle(settings.bibleTextColor ?? .primary)
                .textSelection(.enabled)
                .frame(maxWidth: 280, alignment: .leading)

            HStack {
                Button("취소") { dismiss() }
                Spacer()
                Button("복사") {
                    // 부분 선택과 무관하게 항상 절 전체를 복사한다.
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
