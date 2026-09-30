//
//  CrossReferenceTargetPicker.swift
//  JBCHBibleResearch
//
//  "관주 연결" 생성 시트 — 확대보기 하단 관주 아이콘에서 연다.
//  구절 선택 UI는 메인 화면(BibleReadingView.chapterNavigationControls)과 같은 `HStack` +
//  `.background(.bar)` 구성을 쓰며(`Form`은 행 배치가 달라 쓰지 않는다), 단일 추가와 텍스트 일괄 등록을 함께 제공한다.
//

import SwiftUI
import BibleResearchModels

/// "추가된 관주" 목록은 단일 추가든 일괄 파싱이든 사용자가 인지하는 단위인 "항목" 하나당 한 줄만 보인다 —
/// `verses`가 여러 절이어도 `label` 하나로 대표하고, 저장 시(`onSave`)에는 `verses`를 펼쳐 DB에 절 단위로 등록한다.
private struct CrossReferenceEntryGroup: Identifiable {
    let id = UUID()
    let label: String
    let verses: [BibleVerseRef]
}

struct CrossReferenceTargetPicker: View {
    let sourceLabel: String
    /// 텍스트를 선택해 연 경우 타이틀에 보일 선택 텍스트. 선택 없이(절 전체) 열렸으면 nil.
    var anchorText: String? = nil
    /// 지금 선택한 범위와 겹치는 기존 관주(`VerseZoomView.overlappingCrossReferences`가 전달) —
    /// "등록된 관주" 섹션에 읽기 전용으로 보인다.
    var existingReferences: [VerseCrossReference] = []
    /// "등록된 관주" 각 행의 X 버튼 콜백 — 항목이 속한 원본 레코드와 지울 절 목록을 넘긴다.
    /// 실제 삭제는 `BibleReadingViewModel.removeCrossReferenceGroup`이 맡고, 이 화면은 SwiftData를 직접 만지지 않는다.
    var onDeleteExisting: (_ reference: VerseCrossReference, _ verses: [BibleVerseRef]) -> Void = { _, _ in }
    /// 저장 콜백: 절 목록(DB 저장용, 전부 펼친 것)과 항목별 라벨/절 개수(표시용)를 함께 넘긴다.
    var onSave: (_ targets: [BibleVerseRef], _ entryLabels: [String], _ entryVerseCounts: [Int]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var groups: [CrossReferenceEntryGroup] = []
    @State private var pendingBook: Book = BooksProvider.shared.books.first
        ?? Book(bookId: 1, testament: .old, orderIndex: 1, nameKo: "창세기", nameOriginal: "Genesis", abbreviation: ["창"], chapterCount: 50)
    @State private var pendingChapter: Int = 1
    @State private var pendingVerse: Int = 1

    // 텍스트 일괄 입력 — 파싱은 `BulkCrossReferenceParser`가 담당한다.
    @State private var bulkText: String = ""
    @State private var unrecognizedFragments: [String] = []

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(sourceLabel)와(과) 연결할 구절을 선택하세요")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                // 메인 성경 조회 화면 상단바(BibleReadingView.chapterNavigationControls)와 비슷한 구성.
                // 자유 텍스트 검색창은 끄고(`showsFreeTextSearch: false`) [추가] 버튼을 절 Stepper 옆에 둔다.
                // `Spacer`를 넣지 않는 이유: 탐욕적이라 책 버튼과 절 컨트롤 사이가 화면 끝까지 벌어진다(간격은 HStack spacing으로 충분).
                HStack(spacing: 8) {
                    BookChapterPicker(
                        books: BooksProvider.shared.books,
                        selectedBook: pendingBook,
                        selectedChapter: pendingChapter,
                        showsFreeTextSearch: false
                    ) { book, chapter in
                        pendingBook = book
                        pendingChapter = chapter
                    }

                    Stepper(value: $pendingVerse, in: 1...176) {
                        // 지정이 없으면 루트의 `.appDefaultFont()`(Paperlogy)가 적용되므로 시스템 기본 폰트를 명시한다.
                        Text("\(pendingVerse)절")
                            .font(.body)
                    }
                    .fixedSize()

                    Button {
                        addSingleTarget()
                    } label: {
                        Label("추가", systemImage: "plus")
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)

                Divider()

                // 텍스트 일괄 등록 — 콤마/줄바꿈으로 구분된 여러 구절 표기를 파싱해 `groups`에 추가한다.
                // 항상 펼쳐진 섹션이며 타이틀은 시스템 기본 폰트(`.font(.body)`)를 쓴다.
                VStack(alignment: .leading, spacing: 6) {
                    Text("텍스트로 일괄 등록")
                        .font(.body.weight(.semibold))

                    Text("여러 구절을 콤마(,) 또는 줄바꿈으로 구분해 붙여넣으면 한 번에 추가합니다. 예: 창1:1, 출애굽기1:2~3, 시편112편1,3,5절")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $bulkText)
                        .font(.body)
                        .frame(minHeight: 70, maxHeight: 110)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )

                    if !unrecognizedFragments.isEmpty {
                        Text("인식하지 못한 항목: \(unrecognizedFragments.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Button {
                        applyBulkText()
                    } label: {
                        Label("파싱해서 추가", systemImage: "text.badge.plus")
                    }
                    .disabled(bulkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                // 선택 범위와 겹치는 기존 관주가 있을 때만 보이는 섹션(새로 추가하는 `groups`와는 별개).
                if !existingReferences.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("등록된 관주")
                            .font(.body.weight(.semibold))
                        // 삭제는 `onDeleteExisting`이 DB에 반영한다. `existingReferences`는 호출부가 매번 새로 계산해 넘기므로
                        // 이 시트에 별도 갱신 코드는 필요 없다.
                        ForEach(Array(existingDisplayEntries.enumerated()), id: \.offset) { _, entry in
                            HStack(spacing: 8) {
                                Text(entry.label)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button {
                                    onDeleteExisting(entry.reference, entry.verses)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    Divider()
                }

                // `groups`(항목) 하나당 한 행 — 단일 추가도 절 1개짜리 항목으로 들어온다.
                if groups.isEmpty {
                    Spacer()
                    Text("추가된 관주가 없습니다.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    List {
                        Section("추가된 관주") {
                            ForEach(groups) { group in
                                Text(group.label)
                            }
                            .onDelete { offsets in
                                groups.remove(atOffsets: offsets)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            // 선택 텍스트가 있으면 인용 부호로 감싸 타이틀 앞에 붙인다(길면 SwiftUI가 말줄임 처리).
            .navigationTitle(navigationTitleText)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        onSave(groups.flatMap(\.verses), groups.map(\.label), groups.map { $0.verses.count })
                        dismiss()
                    }
                    .disabled(groups.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 460)
        #endif
    }

    /// `anchorText`가 있으면(구간 선택) 원문을 인용해 타이틀에 보이고, 없으면 "관주 연결"만 보인다.
    private var navigationTitleText: String {
        guard let anchorText, !anchorText.isEmpty else { return "관주 연결" }
        return "“\(anchorText)” 관주 연결"
    }

    /// `existingReferences`를 (라벨, 절목록, 원본 레코드) 쌍으로 정제한다. 저장된 `entryLabels`/
    /// `entryVerseCounts`가 정합적이면 그대로 쓰고, 아니면(해당 필드가 생기기 전 데이터 등) 절 하나당 하나로 폴백한다.
    /// `reference`는 삭제 시 `BibleReadingViewModel.removeCrossReferenceGroup(_:from:)`에 넘기기 위해 함께 든다.
    private var existingDisplayEntries: [(label: String, verses: [BibleVerseRef], reference: VerseCrossReference)] {
        existingReferences.flatMap { reference -> [(label: String, verses: [BibleVerseRef], reference: VerseCrossReference)] in
            if let grouped = reference.groupedEntries {
                return grouped.map { (label: $0.label, verses: $0.verses, reference: reference) }
            }
            return reference.targets.map { target in
                let name = BooksProvider.shared.book(id: target.bookId)?.nameKo ?? "책 \(target.bookId)"
                return (label: "\(name) \(target.chapter):\(target.verse)", verses: [target], reference: reference)
            }
        }
    }

    /// 절 Stepper 옆 [추가] 버튼 — 지금 고른 책/장/절 하나를 항목 하나로 추가한다.
    private func addSingleTarget() {
        let label = "\(pendingBook.abbreviation.first ?? pendingBook.nameKo)\(pendingChapter):\(pendingVerse)"
        let verse = BibleVerseRef(bookId: pendingBook.bookId, chapter: pendingChapter, verse: pendingVerse)
        groups.append(CrossReferenceEntryGroup(label: label, verses: [verse]))
    }

    /// 일괄 입력란의 텍스트를 파싱해 `groups`에 항목 단위로 추가한다. 인식하지
    /// 못한 조각이 있으면 입력란을 비우지 않고 그대로 남겨(사용자가 고쳐서 다시
    /// 시도할 수 있도록) 아래에 경고 문구로 보여준다.
    private func applyBulkText() {
        let result = BulkCrossReferenceParser.parse(bulkText)
        for parsed in result.groups {
            groups.append(CrossReferenceEntryGroup(label: parsed.label, verses: parsed.verses))
        }
        unrecognizedFragments = result.unrecognizedFragments
        if result.unrecognizedFragments.isEmpty {
            bulkText = ""
        }
    }
}
