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
    @State private var pendingBook: Book = BooksProvider.shared.books.first
        ?? Book(bookId: 1, testament: .old, orderIndex: 1, nameKo: "창세기", nameOriginal: "Genesis", abbreviation: ["창"], chapterCount: 50)
    @State private var pendingChapter: Int = 1
    @State private var pendingVerseStart: Int = 1
    @State private var pendingVerseEnd: Int = 1
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("삽입할 말씀구절을 선택하세요")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

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

                VStack(alignment: .leading, spacing: 8) {
                    Stepper(value: $pendingVerseStart, in: 1...176) {
                        Text("\(pendingVerseStart)절부터").font(.body)
                    }
                    .onChange(of: pendingVerseStart) { _, newValue in
                        if pendingVerseEnd < newValue { pendingVerseEnd = newValue }
                    }

                    Stepper(value: $pendingVerseEnd, in: pendingVerseStart...176) {
                        Text("\(pendingVerseEnd)절까지").font(.body)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("말씀구절 추가")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("삽입") { insert() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 380)
        #endif
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
