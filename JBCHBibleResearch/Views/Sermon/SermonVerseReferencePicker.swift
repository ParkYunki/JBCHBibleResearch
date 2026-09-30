//
//  SermonVerseReferencePicker.swift
//  JBCHBibleResearch
//
//  [2026-09-28 3단계(에디터) 신설] 설계 문서 2.2 S-SER2 "말씀구절 스타일의 특수성" —
//  "+ 추가" 버튼으로 책/장/절을 선택하면 본문에 그 구절 텍스트가 자동 삽입되면서
//  문단 스타일이 "말씀구절"로 지정되고, 그 좌표가 `SermonVerseReference`로 함께
//  저장된다. 책/장 선택 UI는 `CrossReferenceTargetPicker.swift`(관주 연결 시트)의
//  단일 추가 구성(`BookChapterPicker` + 절 Stepper + "추가" 버튼)을 그대로 따른다 —
//  이미 검증된 같은 성격의 화면이 있는데 새 패턴을 만들 근거가 없다. 다른 점은
//  절 범위(시작~끝)를 받아 여러 절을 한 번에 삽입할 수 있다는 것과, 저장된 좌표만
//  넘기는 관주 연결과 달리 이 화면은 실제 구절 "본문 텍스트"까지 가져와야 한다는
//  것 — `BibleReferenceStore`를 그때그때 여는 관례(`SearchViewModel`/
//  `ThemeDetailView`/`PersonDetailView`/`BibleReferenceExtractor` 등이 이미 쓰는
//  `try? BibleReferenceStore(filePath: TranslationBootstrap.
//  resolvedBundledDatabaseURL().path)` 패턴)를 그대로 재사용한다.
//
//  ⚠️ [번역본 범위] 항상 번들 기본 번역본(`TranslationBootstrap.
//  resolvedBundledDatabaseURL()`)에서만 구절 텍스트를 가져온다 — 사용자가 추가
//  등록한 다른 번역본을 고를 수 있게 하는 것은 이 설계 문서 범위 밖이라(S1의
//  다중 번역본 비교와 달리 S-SER2는 애초에 번역본 선택 UI를 요구하지 않음)
//  추측으로 넣지 않았다.
//

import SwiftUI
import BibleResearchModels

struct SermonVerseReferencePicker: View {
    /// 삽입 확정 시 호출 — 조합된 구절 텍스트와 구조적 좌표(책/장/시작절/끝절)를
    /// 그대로 넘긴다. 실제 문단 삽입 + `SermonVerseReference` 생성은 호출부
    /// (`SermonEditorView`)의 책임이다 — 이 화면은 SwiftData를 직접 만지지
    /// 않는다는 이 프로젝트의 기존 원칙(`CrossReferenceTargetPicker` 등)과 동일.
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

    /// 선택한 절 범위의 본문을 이어 붙이고, 끝에 "(책이름 장:절)" 형태의
    /// 참조 표기를 덧붙인다 — 목업(Editor.dc.html)의 말씀구절 예시("요한복음
    /// 3:5 \"...\"")와 같은 모양.
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
