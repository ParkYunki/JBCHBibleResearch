//
//  WordNoteVersePickerSheet.swift
//  JBCHBibleResearch
//
//  말씀 노트(개인 묵상·말씀 요약)의 "관련 말씀" 선택 시트 — 책·장을 고르고, 그 장의 절 번호를 눌러 한 절 또는 절 범위
//  (같은 장 안, 예: 3-5절)를 정한다. 절을 고르지 않으면 장 전체에 연결된다(2026-10-13).
//
//  - 책·장 선택은 앱 공용 `BookChapterPicker`(그리드 + "요3:16" 같은 직접 입력)를 그대로 쓴다.
//  - 절 번호 누르기: 처음 누른 절이 시작 → 다른 절을 누르면 거기까지 범위(앞쪽 절을 누르면 앞뒤를 바꿔 잡는다) →
//    범위가 잡힌 뒤 누르면 그 절 하나로 다시 시작. "장 전체"는 절 선택을 지운다.
//  - 절 수는 번들 번역본에서 조회한다(`BibleReferenceExtractor.maxVerse`). 조회에 실패하면 추측하지 않고 "장 전체"만 가능하다.
//  - 새 항목을 만든 직후 자동으로 여는 신호는 `WordNoteVersePickerRequest`가 전달한다(만든 쪽 → 편집 화면).
//

import SwiftUI
import BibleResearchModels

/// 관련 말씀 선택 값. `verse == nil`이면 장 전체, `verseEnd`는 `verse`보다 클 때만 의미가 있다.
struct WordNoteVerseSelection: Equatable {
    var bookId: Int
    var chapter: Int
    var verse: Int?
    var verseEnd: Int?
}

/// "창세기 1장 3-5절" 형식의 라벨. 책 이름을 못 찾았을 때의 대체 문구는 호출부마다 달라(기존 라벨 그대로 유지) 이름을 받아서 쓴다.
enum WordNoteVerseLabel {
    static func text(bookName: String, chapter: Int, verse: Int?, verseEnd: Int?) -> String {
        guard let verse else {
            return String(localized: "\(bookName) \(chapter)장")
        }
        if let verseEnd, verseEnd > verse {
            return String(localized: "\(bookName) \(chapter)장 \(verse)-\(verseEnd)절")
        }
        return String(localized: "\(bookName) \(chapter)장 \(verse)절")
    }
}

/// 새로 만든 개인 묵상·말씀 요약의 편집 화면이 열릴 때 "관련 말씀 선택 시트를 자동으로 띄워라"는 신호.
/// 만든 쪽(`WordNoteHomeView`)이 `request(id:)`로 남기고, 편집 화면이 자기 id로 `consume(id:)`해 한 번만 소비한다.
@MainActor
final class WordNoteVersePickerRequest {
    static let shared = WordNoteVersePickerRequest()

    private var pendingID: UUID?

    private init() {}

    func request(id: UUID) {
        pendingID = id
    }

    /// 이 id에 대한 요청이 있었으면 true를 돌려주고 비운다(다른 id의 요청은 건드리지 않는다).
    func consume(id: UUID) -> Bool {
        guard pendingID == id else { return false }
        pendingID = nil
        return true
    }
}

struct WordNoteVersePickerSheet: View {
    let cancelTitle: String
    let onConfirm: (WordNoteVerseSelection) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var bookId: Int
    @State private var chapter: Int
    @State private var startVerse: Int?
    @State private var endVerse: Int?
    /// 현재 장의 마지막 절 번호. nil이면 조회 실패.
    @State private var verseCount: Int?

    private var gold: Color { JBCHCategoryPalette.gold }
    private var accent: Color { Color("AccentColor") }

    init(
        initial: WordNoteVerseSelection,
        cancelTitle: String = String(localized: "취소"),
        onConfirm: @escaping (WordNoteVerseSelection) -> Void
    ) {
        self.cancelTitle = cancelTitle
        self.onConfirm = onConfirm
        _bookId = State(initialValue: initial.bookId)
        _chapter = State(initialValue: initial.chapter)
        _startVerse = State(initialValue: initial.verse)
        // 끝 절은 시작 절보다 클 때만 범위로 인정한다.
        var normalizedEnd: Int?
        if let start = initial.verse, let end = initial.verseEnd, end > start {
            normalizedEnd = end
        }
        _endVerse = State(initialValue: normalizedEnd)
    }

    private var currentBook: Book {
        BooksProvider.shared.book(id: bookId)
            ?? Book(bookId: 1, testament: .old, orderIndex: 1, nameKo: "창세기", nameOriginal: "Genesis", abbreviation: ["창"], chapterCount: 50)
    }

    private var previewLabel: String {
        WordNoteVerseLabel.text(
            bookName: BooksProvider.shared.book(id: bookId)?.displayName ?? "",
            chapter: chapter, verse: startVerse, verseEnd: endVerse
        )
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                BookChapterPicker(
                    books: BooksProvider.shared.books,
                    selectedBook: currentBook,
                    selectedChapter: chapter,
                    onSelectVerse: { book, newChapter, verse in
                        let count = applyBookChapter(book, newChapter)
                        if let count, verse >= 1, verse <= count {
                            startVerse = verse
                            endVerse = nil
                        }
                    },
                    onSelect: { book, newChapter in
                        _ = applyBookChapter(book, newChapter)
                    }
                )

                HStack(spacing: 10) {
                    Image(systemName: "book")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(gold)
                    Text(previewLabel)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button {
                        startVerse = nil
                        endVerse = nil
                    } label: {
                        Text("장 전체")
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(startVerse == nil ? Color.white : gold)
                            .background(Capsule().fill(startVerse == nil ? gold : Color.clear))
                            .overlay(Capsule().stroke(gold, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(startVerse == nil ? .isSelected : [])
                }

                Text("시작 절을 누른 뒤 끝 절을 누르면 범위가 됩니다. 절을 고르지 않으면 장 전체에 연결됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let count = verseCount, count > 0 {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 46, maximum: 60), spacing: 8)], spacing: 8) {
                            ForEach(1...count, id: \.self) { number in
                                verseCell(number)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } else {
                    Text("이 장의 절 수를 불러오지 못했습니다. 장 전체로만 연결할 수 있습니다.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
            .padding()
            .navigationTitle("관련 말씀 선택")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(cancelTitle) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onConfirm(WordNoteVerseSelection(bookId: bookId, chapter: chapter, verse: startVerse, verseEnd: endVerse))
                        dismiss()
                    } label: {
                        Text("선택").fontWeight(.semibold)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 540)
        #endif
        .onAppear { refreshVerseCount() }
    }

    // MARK: - 절 칸

    private func verseCell(_ number: Int) -> some View {
        let isEdge = startVerse == number || endVerse == number
        let isInside = isInSelection(number)
        return Button {
            tapVerse(number)
        } label: {
            Text(String(number))
                .font(.body.monospacedDigit().weight(isEdge ? .bold : .regular))
                .frame(maxWidth: .infinity, minHeight: 40)
                .foregroundStyle(isInside ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isInside ? accent.opacity(isEdge ? 1 : 0.7) : Color.secondary.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "\(number)절"))
        .accessibilityAddTraits(isInside ? .isSelected : [])
    }

    private func isInSelection(_ number: Int) -> Bool {
        guard let start = startVerse else { return false }
        let end = endVerse ?? start
        return number >= start && number <= end
    }

    private func tapVerse(_ number: Int) {
        guard let start = startVerse else {
            startVerse = number
            endVerse = nil
            return
        }
        if endVerse == nil {
            if number > start {
                endVerse = number
            } else if number < start {
                endVerse = start
                startVerse = number
            }
            // number == start: 그대로 한 절.
        } else {
            startVerse = number
            endVerse = nil
        }
    }

    // MARK: - 책·장 변경

    /// 책·장이 바뀌면 절 선택은 지운다. 새 장의 절 수를 돌려준다(조회 실패 시 nil).
    @discardableResult
    private func applyBookChapter(_ book: Book, _ newChapter: Int) -> Int? {
        if book.bookId != bookId || newChapter != chapter {
            startVerse = nil
            endVerse = nil
        }
        bookId = book.bookId
        chapter = newChapter
        return refreshVerseCount()
    }

    @discardableResult
    private func refreshVerseCount() -> Int? {
        let count = BibleReferenceExtractor.maxVerse(bookId: bookId, chapter: chapter)
        verseCount = count
        return count
    }
}
