//
//  SermonVerseReferencePicker.swift
//  JBCHBibleResearch
//
//  말씀구절 삽입 시트 — 책/장/절 범위를 고르면 해당 구절 본문이 문단으로 삽입되고
//  문단 스타일이 "말씀구절"로 지정되며, 좌표가 `SermonVerseReference`로 함께 저장된다.
//  책/장 선택은 `CrossReferenceTargetPicker`의 `BookChapterPicker`를 재사용하고,
//  본문은 `BibleReferenceStore`를 그때그때 열어 가져온다.
//
//  ⚠️ 구절 텍스트는 항상 번들 기본 번역본(`TranslationBootstrap.resolvedBundledDatabaseURL()`)
//  에서만 가져온다 — 사용자 추가 번역본 선택은 지원하지 않는다.
//

import SwiftUI
import BibleResearchModels

struct SermonVerseReferencePicker: View {
    /// 삽입 확정 시 호출 — 조합된 구절 텍스트와 좌표(책/장/시작절/끝절)를 넘긴다.
    /// 문단 삽입과 `SermonVerseReference` 생성은 호출부(`SermonEditorView`)의 책임이며,
    /// 이 화면은 SwiftData를 직접 만지지 않는다.
    var onInsert: (_ text: String, _ bookId: Int, _ chapter: Int, _ verseStart: Int, _ verseEnd: Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment
    @State private var pendingBook: Book = BooksProvider.shared.books.first
        ?? Book(bookId: 1, testament: .old, orderIndex: 1, nameKo: "창세기", nameOriginal: "Genesis", abbreviation: ["창"], chapterCount: 50)
    @State private var pendingChapter: Int = 1
    @State private var pendingVerseStart: Int = 1
    @State private var pendingVerseEnd: Int = 1
    @State private var errorMessage: String?

    private var settings: UserSettingsStore { .shared }

    private var accent: Color {
        SermonTheme.accent(background: settings.bibleBackgroundColor, environment: environment, fallbackScheme: colorScheme)
    }

    private var textColor: Color { settings.bibleTextColor ?? .primary }

    /// 선택한 범위를 "창세기 1:1-3" 꼴로 미리 보여 준다(삽입될 참조 표기와 같은 모양).
    private var referencePreview: String {
        let end = max(pendingVerseStart, pendingVerseEnd)
        let range = end > pendingVerseStart ? "\(pendingVerseStart)-\(end)" : "\(pendingVerseStart)"
        return "\(pendingBook.nameKo) \(pendingChapter):\(range)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("책 · 장")
                BookChapterPicker(
                    books: BooksProvider.shared.books,
                    selectedBook: pendingBook,
                    selectedChapter: pendingChapter,
                    showsFreeTextSearch: false
                ) { book, chapter in
                    pendingBook = book
                    pendingChapter = chapter
                    pendingVerseStart = 1
                    pendingVerseEnd = 1
                }
                .tint(accent)
            }

            HStack(alignment: .bottom, spacing: 10) {
                verseStepper(title: "시작 절", value: $pendingVerseStart, range: 1...176)
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(textColor.opacity(0.4))
                    .padding(.bottom, 14)
                verseStepper(title: "끝 절", value: $pendingVerseEnd, range: pendingVerseStart...176)
            }
            .onChange(of: pendingVerseStart) { _, newValue in
                if pendingVerseEnd < newValue { pendingVerseEnd = newValue }
            }

            HStack(spacing: 6) {
                Image(systemName: "text.quote")
                Text(referencePreview)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: SermonTheme.pillCornerRadius, style: .continuous))

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 10) {
                Button("취소") { dismiss() }
                    .buttonStyle(SermonPillButtonStyle(isFilled: false, tint: accent))
                Button("삽입") { insert() }
                    .buttonStyle(SermonPillButtonStyle(isFilled: true, tint: accent))
            }
        }
        .padding(20)
        #if os(macOS)
        .frame(width: 380)
        #endif
        .background(settings.bibleBackgroundColor ?? Color.clear)
        .presentationBackground(settings.bibleBackgroundColor.map { AnyShapeStyle($0) } ?? AnyShapeStyle(BackgroundStyle()))
        .presentationSizing(.fitted)
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "book.pages")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(accent, in: Circle())
            Text("말씀구절 추가")
                .font(.headline)
                .foregroundStyle(textColor)
            Spacer()
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(textColor.opacity(0.6))
    }

    /// 라벨 + 작은 스테퍼를 한 칸으로 묶는다. 숫자는 폭이 흔들리지 않게 고정폭 숫자로 그린다.
    private func verseStepper(title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(title)
            Stepper(value: value, in: range) {
                Text("\(value.wrappedValue)절")
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(textColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: SermonTheme.pillCornerRadius, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func insert() {
        guard let text = fetchVerseText() else {
            errorMessage = "해당 구절 본문을 찾지 못했습니다 — 번역본 데이터를 확인해 주세요."
            return
        }
        let verseEnd = pendingVerseEnd > pendingVerseStart ? pendingVerseEnd : nil
        onInsert(text, pendingBook.bookId, pendingChapter, pendingVerseStart, verseEnd)
        dismiss()
    }

    /// 선택한 절 범위의 본문을 이어 붙이고 끝에 "(책이름 장:절)" 참조 표기를 덧붙인다.
    private func fetchVerseText() -> String? {
        guard let store = try? BibleReferenceStore(filePath: TranslationBootstrap.resolvedBundledDatabaseURL().path) else {
            return nil
        }
        let start = pendingVerseStart
        let end = max(pendingVerseStart, pendingVerseEnd)
        var contents: [String] = []
        for verseNumber in start...end {
            guard let verse = try? store.verse(bookId: pendingBook.bookId, chapter: pendingChapter, verse: verseNumber, versionCode: nil) else {
                continue
            }
            contents.append(verse.content)
        }
        guard !contents.isEmpty else { return nil }
        let bookLabel = pendingBook.nameKo
        let referenceLabel = end > start
            ? "\(bookLabel) \(pendingChapter):\(start)-\(end)"
            : "\(bookLabel) \(pendingChapter):\(start)"
        return "\(contents.joined(separator: " ")) (\(referenceLabel))"
    }
}
