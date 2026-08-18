//
//  CrossReferenceTargetPicker.swift
//  JBCHBibleResearch
//
//  "관주 연결" 생성 시트 — 확대보기 하단 관주 아이콘에서 연다.
//
//  [2026-08-11 재작성] 사용자 보고 — "관주연결의 구성이 틀어져 있음... 성경 검색하는
//  텍스트 입력은 성경 조회 메인창 상단에 있는 것처럼 할 것"(스크린샷 확인). 원래 이
//  화면은 `Form` + `Section("...와(과) 연결할 구절")` 안에 `BookChapterPicker`를
//  끼워 넣은 구성이었다 — `BookChapterPicker` 자체는 메인 화면(BibleReadingView.
//  chapterNavigationControls)과 같은 컴포넌트를 재사용하고 있었지만, `Form`이 각
//  자식 뷰를 "라벨: 컨트롤" 형태의 행으로 자체 배치하다 보니 메인 화면의 평범한
//  `HStack`(`.safeAreaInset(edge: .top)` 안, `.background(.bar)`) 배치와는 전혀
//  다르게 보였다 — 이게 "구성이 틀어져 있다"는 체감의 실제 원인으로 보인다.
//  `Form`/`Section`을 걷어내고, 메인 화면과 동일하게 평범한 `HStack` +
//  `.background(.bar)`로 바꿨다. 긴 안내 문장("OO장 N절와(과) 연결할 구절")도
//  `Section` 제목(원래 라벨 하나만 들어가야 자연스러운 자리)으로 쓰는 대신, 그
//  위에 별도의 캡션 텍스트로 뺐다 — "장"이 빠졌던 문구 버그(VerseZoomView.
//  crossReferenceSourceLabel)도 같은 라운드에서 함께 고쳤다.
//

import SwiftUI
import BibleResearchModels

/// [2026-08-12 추가] 사용자 요청 — "일괄 등록시 분해되어서 각 절별로 보여지는
/// 것이 아니라... 사용자가 입력한 텍스트가 정제되어서 보여지게 하되, DB상에서는
/// 분해되어서 등록되게끔." 단일 추가(책/장/절 하나)든 일괄 텍스트 파싱이든, 이
/// 화면의 "추가된 관주" 목록은 사용자가 인지하는 단위인 "항목" 하나당 한 줄만
/// 보여준다 — `verses`가 절 여러 개(범위/콤마 나열)를 담고 있어도 `label`
/// 하나로 대표한다. 저장 시(`onSave`)엔 `verses`를 모두 펼쳐 DB에는 여전히
/// 절 단위로 낱개 등록한다.
private struct CrossReferenceEntryGroup: Identifiable {
    let id = UUID()
    let label: String
    let verses: [BibleVerseRef]
}

struct CrossReferenceTargetPicker: View {
    let sourceLabel: String
    /// [2026-08-12 추가] 사용자 요청 — "맨 상단 '관주 연결' 타이틀 — 만일
    /// 텍스트를 선택해서 관주 연결을 하고자 할 때 선택된 텍스트를 보여줄
    /// 것." 선택 없이(절 전체) 열렸으면 nil.
    var anchorText: String? = nil
    /// [2026-08-12 추가] 사용자 요청 — "관주 버튼 → ... 내 의도 -> 새로 만들기
    /// 시트 + 기존 관주 보기." 지금 선택한 범위와 겹치는, 이미 저장된
    /// 관주들(`VerseZoomView.overlappingCrossReferences`가 골라 넘긴다) —
    /// 이 시트가 "등록된 관주" 섹션으로 보여준다(읽기 전용, 이 시트 자체가
    /// 새로 추가하는 `groups`와는 별개).
    var existingReferences: [VerseCrossReference] = []
    /// [2026-08-15 신설] 사용자 요청 — 확대보기 관주 상태줄의 팝오버(및 그
    /// 안의 삭제 X버튼)를 없애면서, "등록된 관주" 목록의 삭제 기능을 이
    /// 시트로 옮겼다 — 아래 "등록된 관주" 섹션의 각 행에 X 버튼을 그리고,
    /// 눌리면 그 항목이 속한 원본 `VerseCrossReference`와 지울 절 목록을
    /// 그대로 호출부에 넘긴다(실제 삭제는 `BibleReadingViewModel.
    /// removeCrossReferenceGroup`이 담당 — 이 화면은 SwiftData를 직접 만지지
    /// 않는다는 기존 원칙을 유지).
    var onDeleteExisting: (_ reference: VerseCrossReference, _ verses: [BibleVerseRef]) -> Void = { _, _ in }
    /// [2026-08-12 변경] 기존엔 절 단위로 전부 펼쳐진 `[BibleVerseRef]` 하나만
    /// 넘겼는데, 그러면 호출부(`BibleReadingViewModel.addCrossReference`)가
    /// "사용자가 원래 어떻게 묶어서 입력했는지"(정제된 표시 문구)를 알 방법이
    /// 없었다 — 이제 절 목록(DB 저장용, 그대로 다 펼친 것)과 항목별 라벨/개수
    /// (표시용)를 함께 넘긴다.
    var onSave: (_ targets: [BibleVerseRef], _ entryLabels: [String], _ entryVerseCounts: [Int]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var groups: [CrossReferenceEntryGroup] = []
    @State private var pendingBook: Book = BooksProvider.shared.books.first
        ?? Book(bookId: 1, testament: .old, orderIndex: 1, nameKo: "창세기", nameOriginal: "Genesis", abbreviation: ["창"], chapterCount: 50)
    @State private var pendingChapter: Int = 1
    @State private var pendingVerse: Int = 1

    // [2026-08-12 추가] 사용자 요청 — "관주를 일괄로 처리할 수 있도록 텍스트박스를
    // 두고, 거기에 입력하는 텍스트에 성경장절 문구를 추출하여 일괄 등록." 위의
    // 단일 항목 입력(BookChapterPicker + Stepper)은 그대로 두고, 그 아래에
    // 자유 텍스트 일괄 입력을 추가한다 — 파싱은 `BulkCrossReferenceParser`가 담당.
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

                // 메인 성경 조회 화면 상단바(BibleReadingView.chapterNavigationControls)와
                // 비슷한 구성이되, [2026-08-12 변경] 사용자 요청 — "관주 연결시 화면
                // 상단 중앙 성경을 타이핑해서 성경을 찾는 텍스트 공간은 필요없음.
                // 대신 절 숫자 지정 오른쪽 옆에 [추가] 버튼 추가." 자유 텍스트
                // 입력(BookChapterPicker의 TextField+"이동")은 이 화면에서 꺼두고
                // (`showsFreeTextSearch: false`), 아래에 따로 있던 "목록에 추가"
                // 버튼을 절 Stepper 바로 옆으로 옮겼다.
                // [2026-08-12 수정] 사용자 보고 — "성경 책 버튼과 절 버튼 사이의
                // 공백이 지나치게 김." 자유 텍스트 검색창(TextField)이 있던
                // 시절엔 그 칸이 남는 폭을 가져가 자연스러웠는데, 그 칸을 끈
                // 뒤로는 아래 `Spacer(minLength: 8)`이 혼자 남는 폭을 전부
                // 차지해(SwiftUI `Spacer`는 기본이 "탐욕적") 책 버튼과 절
                // 컨트롤 사이가 화면 끝까지 벌어져 있었다 — `HStack(spacing: 8)`
                // 자체가 이미 자식 사이에 8pt를 주므로, 이 `Spacer`는 그냥 뺐다.
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
                        // [2026-08-11 추가] 사용자 요청 — "[절] 영역 폰트는 시스템
                        // 기본 폰트에 일반 크기로." 지정이 없으면 루트의
                        // `.appDefaultFont()`(Paperlogy)가 그대로 적용된다.
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

                // [2026-08-12 추가, 2026-08-12 재수정] 텍스트 일괄 등록 — 콤마/
                // 줄바꿈으로 구분된 여러 구절 표기를 한 번에 파싱해 `groups`에
                // 추가한다. 사용자 요청 — "텍스트로 일괄 등록은 펼쳐져 있는 상태로
                // 오픈할 것. (타이틀을 시스템 기본폰트로 할것.) 접는 기능 뺄것."
                // — `DisclosureGroup`(접고 펼 수 있는 형태)이던 것을 항상 펼쳐진
                // 평범한 섹션으로 바꾸고, 타이틀은 `.appDefaultFont()`(Paperlogy)
                // 대신 `.font(.body)`로 시스템 기본 폰트를 쓴다(이 파일의 다른
                // "시스템 기본 폰트" 지정들과 같은 방식).
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

                // [2026-08-12 추가] 사용자 요청 — "관주가 있는 텍스트를 선택하고
                // 관주버튼을 눌렀을 때: 등록된 관주 리스트." `existingReferences`
                // (선택 범위와 겹치는, 이미 저장된 관주)가 있을 때만 보여주는
                // 읽기 전용 섹션 — 새로 추가하는 `groups`(아래 "추가된 관주")와는
                // 완전히 별개다.
                if !existingReferences.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("등록된 관주")
                            .font(.body.weight(.semibold))
                        // [2026-08-15 신설] 사용자 요청 — "삭제기능은 편집모드에
                        // 관주버튼 누르면 나오는 관주연결팝업에서의 리스트에
                        // 각 항목별로 (x)를 붙여 삭제기능을 옮길것." 항목마다
                        // X 버튼을 붙인다 — 삭제하면 `onDeleteExisting`이
                        // 실제 DB 반영을 맡고, 이 시트 자신은 `existingReferences`
                        // 를 다시 계산해 주는 호출부(VerseZoomView)의 재렌더링에
                        // 맡긴다(이 시트는 그 배열을 직접 들고 있지 않고 매번
                        // 새로 계산해 받는 `let` 프로퍼티라 별도 갱신 코드가
                        // 필요 없다).
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

                // [2026-08-12 변경] 사용자 요청 — "일괄 등록시 분해되어서 각
                // 절별로 보여지는 것이 아니라... 사용자가 입력한 텍스트가
                // 정제되어서 보여지게." 절 하나당 행이 아니라 `groups`(항목)
                // 하나당 행 — 단일 추가도 절 1개짜리 항목 하나로 들어온다.
                if groups.isEmpty {
                    Spacer()
                    // [2026-08-12 수정] 사용자 요청 — "추가된 관주가 없습니다.
                    // (시스템 글꼴체로 변경)."
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
            // [2026-08-12 변경] 사용자 요청 — "맨 상단 '관주 연결' 타이틀 —
            // 만일 텍스트를 선택해서 관주 연결을 하고자 할 때 선택된 텍스트를
            // 보여줄 것." 선택 텍스트가 있으면 그 원문을 인용 부호로 감싸
            // 타이틀 앞에 붙인다 — 길면 SwiftUI가 알아서 말줄임(...)한다.
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

    /// [2026-08-12 추가] `anchorText`가 있으면(구간 선택) 그 원문을 인용해
    /// 타이틀에 보여주고, 없으면(절 전체) 예전 그대로 "관주 연결"만 보여준다.
    private var navigationTitleText: String {
        guard let anchorText, !anchorText.isEmpty else { return "관주 연결" }
        return "“\(anchorText)” 관주 연결"
    }

    /// [2026-08-12 추가, 2026-08-15 변경] `existingReferences`(선택 범위와
    /// 겹치는, 이미 저장된 관주들)를 화면에 보여줄 (라벨, 절목록, 원본
    /// 레코드) 3종 쌍들로 정제한다 — 저장된 `entryLabels`/`entryVerseCounts`가
    /// 정합적이면 그대로 쓰고, 아니면(이 필드가 생기기 전 데이터 등) 절
    /// 하나당 하나의 표시로 폴백한다. `reference`를 함께 들고 있는 이유 —
    /// 위 "등록된 관주" 목록에 X(삭제) 버튼이 생기면서, 그 항목이 원래 어느
    /// `VerseCrossReference` 레코드에 속했는지 알아야
    /// `BibleReadingViewModel.removeCrossReferenceGroup(_:from:)`을 부를 수
    /// 있다.
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
