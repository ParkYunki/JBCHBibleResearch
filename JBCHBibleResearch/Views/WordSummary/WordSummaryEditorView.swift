//
//  WordSummaryEditorView.swift
//  JBCHBibleResearch
//
//  [2026-08-12 신설] 사용자 요청 — "왼쪽 사이드바 [말씀 요약] - 개인 주석(개인
//  묵상)과 기능 동일 ... 리스트 요소를 클릭하면 오른쪽영역에 에디터." `VerseSummary`
//  하나를 여는 리치 텍스트 에디터 — `MemoDetailView.swift`(개인 묵상)와 거의 같은
//  구조로 만들었다(자동저장 컨트롤러, 성경 좌표 헤더, `.standalone`/`.contextual`
//  두 표시 방식). 태그/폴더는 이번 요청 범위에 없어 두지 않았다.
//
//  [2026-08-12 추가] 사용자 요청 — "성경 구절 선택시 확대보기 오른쪽 옆 [말씀
//  요약]버튼 ... 에디터 제일 첫줄: 현재날짜 '말씀', 그 다음줄: 선택된 성경구절
//  자동입력." `.contextual`로 열릴 때는 `BibleReadingView`가 이미 그 정제된
//  문구를 채운 새 `VerseSummary`를 만들어 넘긴다 — 이 화면은 그 내용을 그대로
//  편집기에 띄우기만 한다.
//
//  [2026-08-12 3차 수정, 버그 수정] 사용자 보고 — "[맥OS] 오른쪽 사이드바
//  에디터 영역의 닫기(x) 버튼을 누르면 삭제가 되는데? ... 말씀요약 한 내용이
//  삭제버튼을 누르지 않고 알아서 삭제가 되는 케이스는 없음." 원래 `.contextual`은
//  "화면이 열렸을 때의 문구(`seedTextSnapshot`)와 완전히 같은 채로 닫혔는지"를
//  빈 레코드 판정 기준으로 썼는데, `.inspector` 컬럼이 macOS에서 창 크기 변화 등
//  레이아웃 사정으로 내부적으로 뷰를 다시 만들면(SwiftUI가 `onAppear`를 예상보다
//  더 자주 다시 부를 수 있다) `loadIfNeeded()`가 재실행되면서 `seedTextSnapshot`이
//  "그 시점까지 사용자가 이미 입력해 둔 내용"으로 다시 캡처될 수 있었다 — 그러면
//  실제로 방금 막 쓴 내용이 있어도 "seedTextSnapshot과 똑같다"고 오판해 통째로
//  지워질 수 있었다(정확한 재현 트리거는 Xcode 없이 이 세션에서 100% 확정할 수
//  없었지만, 이 스냅샷-비교 방식 자체가 근본 원인이라 판단해 아예 없앴다).
//  지금은 `.standalone`과 완전히 같은 규칙(진짜로 텍스트가 한 글자도 없어야만
//  자동 정리)을 쓴다 — 미리 채워 준 날짜/구절 문구가 남아 있는 한(사용자가 전부
//  지우지 않는 한) 절대 자동 삭제되지 않는다. "아무것도 안 쓰고 바로 닫으면 문구만
//  담긴 레코드가 쌓인다"는 부작용은 남지만, 그런 레코드는 목록 화면(`WordSummaryHomeView`)
//  에서 사용자가 직접 삭제 버튼으로 지우면 된다 — 사용자가 명시한 원칙("삭제
//  버튼을 누르지 않는 한 절대 지워지지 않아야 함")과 맞다.
//

import SwiftUI
import SwiftData
import BibleResearchModels
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum WordSummaryPresentationContext {
    /// "말씀 요약" 사이드바 탭(WordSummaryHomeView) — 성경 좌표를 직접 바꿀 수
    /// 있는 헤더를 쓴다.
    case standalone
    /// 성경 조회 화면의 [말씀 요약] 버튼으로 연 인스펙터 패널 — 이미 어느 절의
    /// 요약인지 정해진 채로 열리므로 읽기전용 좌표 라벨만 보여준다.
    case contextual
}

struct WordSummaryEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var summary: VerseSummary
    var presentationContext: WordSummaryPresentationContext = .standalone
    /// [2026-08-12 추가] 사용자 요청 — "[말씀 복사] 탭/클릭시 오른쪽 사이드바
    /// 에디터 커서 위치한 곳에 성경구절 복사 붙여넣기 실행." 이 버튼은 에디터
    /// 바깥(성경 조회 화면의 하단 액션바)에 있어, 그 버튼이 이 안의 텍스트뷰에
    /// 직접 접근할 방법이 필요하다 — `RichTextEditor.externalProxy`와 같은 원칙
    /// (`RichTextEditor.swift` 상단 주석 참고)으로, 호출부(BibleReadingView)가
    /// 프록시를 만들어 이 뷰와 그 버튼 양쪽에 같은 인스턴스를 넘긴다. nil이면
    /// (기존 호출부, `WordSummaryHomeView`) 내부적으로 만드는 프록시를 그대로 쓴다.
    var externalProxy: RichTextEditingProxy? = nil
    /// [2026-08-20 추가, 2026-08-21 삭제] "확대보기"/"원문 정보" 버튼을 이 화면
    /// 안(상단 좌표 라인)에 뒀었다 — 사용자가 "macOS처럼 하단 말씀복사 옆에
    /// 자리할 수 있도록" 요청해, 진짜 목적지인 바깥 하단 액션바
    /// (`BibleReadingView.verseSelectionActionBar`)로 옮겼다. 그 액션바가 이미
    /// `isVerseZoomPresented`/`isOriginalTextInfoPresented` 시트 상태를 갖고
    /// 있어(평소 절 선택 모드의 "확대보기"/"원문 정보" 버튼과 같은 시트) 이
    /// 화면은 더 이상 그 상태를 클로저로 받아올 필요가 없다.

    @State private var autosave: AutosaveController?
    @State private var isEditable = true
    @State private var hasLoadedMetadata = false

    /// [2026-08-14 신설] 사용자 요청 — "말씀 요약의 글을 클릭했을 때에도 개인
    /// 묵상 유형의 글처럼 태그를 입력할 수 있게." `MemoDetailView`의 태그 상태를
    /// 그대로 옮겨왔다 — `SummaryTag`(이 화면 전용 조인)를 통해 연결한다.
    @State private var summaryTags: [Tag] = []
    @State private var tagInput: String = ""
    @State private var tagSuggestions: [Tag] = []
    @State private var drilldownTag: Tag?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            RichTextEditor(
                rtfText: Binding(
                    get: { summary.contentHtml },
                    set: { newValue in
                        summary.contentHtml = newValue
                        summary.updatedAt = .now
                        // [2026-08-12 추가] 사용자 논의 — "화면을 벗어났을 때
                        // 트리거를 실행" 방식으로 바꾸면서 생긴 표시. 이 저장
                        // (디바운스)에 본문 변경과 함께 실려 나가므로, 만약 정상
                        // 종료(`handleDisappear`) 전에 앱이 강제 종료되면 이
                        // `true`만 디스크에 남는다 — 목록 화면이 그 신호로
                        // "인덱스 갱신 필요" 배지를 보여준다(`WordSummaryRowView`
                        // 참고).
                        summary.pendingIndexRefresh = true
                        autosave?.scheduleSave()
                    }
                ),
                plainText: Binding(
                    get: { summary.contentText },
                    set: { summary.contentText = $0 }
                ),
                isEditable: isEditable,
                typingFont: EditorDefaultStyle.typingFont,
                defaultTextColor: EditorDefaultStyle.textColor,
                lineHeightMultiple: EditorDefaultStyle.lineHeightMultiple,
                // [2026-08-14 변경] `MemoDetailView`와 같은 이유(그 파일 주석 참고) —
                // 조회/편집 배경을 완전히 같은 값으로 고정해 모드 전환 시 배경이
                // 바뀌는 것처럼 보이던 불일치를 없앴다.
                editingBackgroundColor: EditorDefaultStyle.backgroundColor,
                readOnlyBackgroundColor: EditorDefaultStyle.backgroundColor,
                // [2026-08-12 추가] 사용자 요청 — "말씀 스타일 툴바는 오른쪽
                // 사이드바 에디터영역에 위치하게." `.contextual`(성경 조회 화면의
                // 인스펙터)일 때만 macOS 상시 노출 툴바를 켠다 — `RichTextEditor.
                // showsToolbarOnMac` 상단 주석 참고. `.standalone`(말씀 요약
                // 사이드바 탭)은 이번 요청 범위 밖이라 건드리지 않았다.
                showsToolbarOnMac: presentationContext == .contextual,
                externalProxy: externalProxy
            )
            .padding()
            .frame(maxHeight: .infinity)

            Divider().padding(.horizontal)

            tagSection
                .padding()
        }
        .sheet(item: $drilldownTag) { tag in
            TagDrilldownView(tag: tag)
        }
        .toolbar {
            // [2026-08-12 변경] 사용자 요청 — "[맥OS] 오른쪽 사이드바 에디터
            // 영역의 상단버튼 중 닫기 버튼 오른쪽 눈모양 버튼 없앨 것." 읽기전용
            // 토글은 `.contextual`(성경 조회 인스펙터)에서는 의미가 적다 — 방금
            // 만든 새 저널 항목을 곧바로 편집하는 흐름이라 항상 편집 가능한 채로
            // 두는 편이 자연스럽다. `.standalone`(말씀 요약 사이드바 탭, 기존
            // 항목을 훑어보기만 할 수도 있는 화면)에는 그대로 남긴다.
            if presentationContext == .standalone {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isEditable.toggle()
                    } label: {
                        Image(systemName: isEditable ? "eye" : "pencil")
                    }
                    .help(isEditable ? "읽기 전용으로 보기" : "편집하기")
                }
            }
        }
        .onAppear(perform: loadIfNeeded)
        .onDisappear(perform: handleDisappear)
    }

    // MARK: - 상단 성경 좌표 + 동기화 상태

    @ViewBuilder
    private var header: some View {
        switch presentationContext {
        case .standalone:
            HStack {
                BookChapterPicker(
                    books: BooksProvider.shared.books,
                    selectedBook: BooksProvider.shared.book(id: summary.bookId)
                        ?? Book(bookId: 1, testament: .old, orderIndex: 1, nameKo: "창세기", nameOriginal: "Genesis", abbreviation: ["창"], chapterCount: 50),
                    selectedChapter: summary.chapter
                ) { book, chapter in
                    summary.bookId = book.bookId
                    summary.chapter = chapter
                    autosave?.saveImmediately()
                }
                .disabled(!isEditable)

                Stepper(value: Binding(
                    get: { summary.verse ?? 0 },
                    set: { newValue in
                        summary.verse = newValue == 0 ? nil : newValue
                        autosave?.saveImmediately()
                    }
                ), in: 0...176) {
                    Text(summary.verse.map { "\($0)절" } ?? "절 없음")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .disabled(!isEditable)
                .fixedSize()

                Spacer()

                syncStatusLabel
            }
            .padding()

        case .contextual:
            // [2026-08-20 추가, 2026-08-21 이동] "확대보기"/"원문 정보" 버튼이
            // 한때 여기 있었다 — 이제 바깥 하단 액션바(`BibleReadingView.
            // verseSelectionActionBar`)의 "말씀 복사" 옆으로 옮겼다(위
            // `onRequestVerseZoom`/`onRequestOriginalTextInfo` 삭제 주석 참고).
            HStack {
                Text(contextualCoordinateLabel)
                    .font(.callout.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                syncStatusLabel
            }
            .padding()
        }
    }

    private var contextualCoordinateLabel: String {
        let bookName = BooksProvider.shared.book(id: summary.bookId)?.nameKo ?? ""
        if let verse = summary.verse {
            return "\(bookName) \(summary.chapter)장 \(verse)절"
        }
        return "\(bookName) \(summary.chapter)장"
    }

    // [2026-08-14 삭제] `contextualTypingFont` — `MemoDetailView`와 같은 이유로
    // 삭제. 이제 모든 모드가 `EditorDefaultStyle.typingFont`를 공유한다.

    @ViewBuilder
    private var syncStatusLabel: some View {
        switch autosave?.status {
        case .saved, .none:
            Label("동기화됨", systemImage: "checkmark.icloud")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .pending:
            Label("대기 중", systemImage: "icloud")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .saving:
            Label("동기화 중", systemImage: "arrow.triangle.2.circlepath.icloud")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 태그 — `MemoDetailView.tagSection`/태그 조작 메서드와 완전히 같은
    // 구조(그 파일 참고), `UserMemo`/`MemoTag` 대신 `VerseSummary`/`SummaryTag`를 쓴다.

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("태그").font(.caption).foregroundStyle(.secondary)

            FlowLayoutHStack {
                ForEach(summaryTags) { tag in
                    HStack(spacing: 4) {
                        Text(tag.name)
                            .onTapGesture { drilldownTag = tag }
                        if isEditable {
                            Button {
                                removeTag(tag)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
                }
            }

            if isEditable {
                HStack {
                    TextField("태그 입력 후 Enter", text: $tagInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                        .onSubmit { commitTagInput() }
                        .onChange(of: tagInput) { _, newValue in
                            updateTagSuggestions(for: newValue)
                        }
                    if !tagSuggestions.isEmpty {
                        Menu {
                            ForEach(tagSuggestions) { suggestion in
                                Button(suggestion.name) { addTag(suggestion) }
                            }
                        } label: {
                            Image(systemName: "chevron.down.circle")
                        }
                    }
                }
                .frame(maxWidth: 280)
            }
        }
    }

    private func updateTagSuggestions(for input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else {
            tagSuggestions = []
            return
        }
        do {
            let all = try modelContext.fetch(FetchDescriptor<Tag>(
                predicate: #Predicate<Tag> { $0.mergedIntoId == nil }
            ))
            tagSuggestions = Array(
                all
                    .filter { $0.normalizedForm.contains(trimmed) }
                    .filter { candidate in !summaryTags.contains { $0.id == candidate.id } }
                    .sorted {
                        // [2026-08-14] `MemoDetailView`와 달리 이 화면은 `Tag`가
                        // 개인 묵상/말씀 요약 양쪽에서 쓰일 수 있으므로, 빈도수를
                        // 두 조인 타입 합으로 계산한다 — 한쪽에서만 자주 쓰인
                        // 태그도 정확히 추천 순위에 반영되도록.
                        let lhsCount = ($0.memoTags?.count ?? 0) + ($0.summaryTags?.count ?? 0)
                        let rhsCount = ($1.memoTags?.count ?? 0) + ($1.summaryTags?.count ?? 0)
                        if lhsCount != rhsCount { return lhsCount > rhsCount }
                        return $0.name < $1.name
                    }
                    .prefix(8)
            )
        } catch {
            tagSuggestions = []
        }
    }

    private func commitTagInput() {
        let trimmed = tagInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            let tag = try TagDeduplication.findOrCreateTag(named: trimmed, context: modelContext)
            addTag(tag)
        } catch {
            print("[WordSummaryEditorView] 태그 생성 실패: \(error)")
        }
        tagInput = ""
        tagSuggestions = []
    }

    private func addTag(_ tag: Tag) {
        guard !summaryTags.contains(where: { $0.id == tag.id }) else { return }
        let join = SummaryTag(summary: summary, tag: tag)
        modelContext.insert(join)
        summaryTags.append(tag)
        tagInput = ""
        tagSuggestions = []
        autosave?.saveImmediately()
    }

    private func removeTag(_ tag: Tag) {
        if let join = (summary.summaryTags ?? []).first(where: { $0.tag?.id == tag.id }) {
            modelContext.delete(join)
        }
        summaryTags.removeAll { $0.id == tag.id }
        autosave?.saveImmediately()
    }

    // MARK: - 로드/저장

    private func loadIfNeeded() {
        guard !hasLoadedMetadata else { return }
        summaryTags = (summary.summaryTags ?? []).compactMap(\.tag).filter { !$0.isMerged }
        // [2026-08-12 2차 수정] 사용자 논의 — "말씀 요약 화면을 벗어났을 때
        // 트리거를 실행 할 수 있는가?" 원래는 여기서 `AutosaveController`의
        // `didSave` 클로저로 매 자동저장(디바운스)마다 재인덱싱했다 — 타이핑을
        // 쉬어가며 오래 쓰면 그만큼 여러 번 도는 구조였다. 화면을 벗어날 때
        // (`handleDisappear()`, 닫기 버튼이든 사이드바로 다른 메뉴 이동이든)
        // 딱 한 번만 실행하도록 옮겼다 — 편집 중엔 "관련 말씀 요약"/"관련
        // 내용" 패널을 어차피 동시에 볼 수 없는 구조라(같은 인스펙터 자리를
        // 편집기와 교대로 쓴다) 화면상 체감되는 손실이 없다. `didSave`는
        // 더 이상 필요 없어 뺐다 — 저장 자체(콘텐츠 보존)는 계속 디바운스대로
        // 일어나고, 그때마다 `pendingIndexRefresh = true`만 같이 저장된다.
        autosave = AutosaveController(modelContext: modelContext)
        hasLoadedMetadata = true
    }

    private func handleDisappear() {
        autosave?.flush()
        // [2026-08-12 3차 수정, 버그 수정] 사용자 보고 — "닫기(x) 버튼을 누르면
        // 삭제가 되는데? ... 삭제버튼을 누르지 않고 알아서 삭제가 되는 케이스는
        // 없음." 예전엔 `.contextual`만 "열렸을 때의 미리 채운 문구와 완전히
        // 같은 채로 닫혔는지"로 판정했는데(스냅샷 비교), 이제는 `.standalone`과
        // 완전히 같은 기준(진짜 텍스트가 한 글자도 없을 때만)으로 통일했다 — 위
        // 파일 상단 주석 참고. 미리 채워 준 날짜/구절 문구가 남아 있는 한 이
        // 조건은 절대 참이 되지 않는다.
        // [2026-08-14 변경] 태그 기능이 생기면서, 본문은 비어도 태그가 붙어 있으면
        // (예: 나중에 채우려고 태그만 먼저 달아 둔 경우) 지우지 않도록 `MemoDetailView`
        // 와 같은 조건을 추가했다.
        let isEmpty = summary.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && summaryTags.isEmpty
        // [2026-08-12 추가] `MemoDetailView.handleDisappear()`와 같은 이유 — 빈
        // 레코드라 실제로 지워질 때도, 혹시 남아 있을 수 있는 인덱스를 함께 정리한다.
        autosave?.deleteIfEmpty(summary, isEmpty: isEmpty) { [modelContext] in
            BibleReferenceIndexingService.removeMentions(
                sourceType: .wordSummary, sourceId: summary.id.uuidString, context: modelContext
            )
        }
        // [2026-08-12 추가] 사용자 논의 — "화면을 닫으면 인덱스를 생성." 지워지지
        // 않고 남은(=`isEmpty`가 아니었던) 레코드만, 그리고 지난 저장 이후로
        // 실제 본문이 바뀌어 인덱스가 낡았을 때만(`pendingIndexRefresh`) 재인덱싱한다
        // — 아무것도 안 고치고 열어만 봤다 닫으면 불필요한 재계산을 또 하지 않는다.
        if !isEmpty && summary.pendingIndexRefresh {
            BibleReferenceIndexingService.reindexWordSummary(summary, context: modelContext)
            summary.pendingIndexRefresh = false
            try? modelContext.save()
        }
    }
}
