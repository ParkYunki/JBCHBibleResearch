//
//  BibleReadingViewModel.swift
//  JBCHBibleResearch
//
//  S1(성경 조회) 화면의 상태와 데이터 접근을 담당한다. 등록된 각 번역본(TranslationRegistry)에
//  대해 BibleReferenceStore를 열어 두고, 선택된 책/장이 바뀔 때마다 새로 조회한다.
//
//  ⚠️ [범위 밖, 검증 필요] 번역본 4개 이상 등록 시 "칩 토글로 최대 3개 선택"하는
//  팝오버(screens.md 3장)는 TranslationPickerPopover가 UI를 제공하지만, 이번 구현에서는
//  번들 번역본 1개만 부트스트랩되므로 실제로 4개 이상 등록된 상태로 테스트하지 못했다 —
//  S12(번역본 관리) 구현 후 다중 등록 상태에서 재검증이 필요하다.
//

import Foundation
import SwiftData
import Observation
import BibleResearchModels

@MainActor
@Observable
final class BibleReadingViewModel {
    struct ColumnState: Identifiable {
        let id: UUID
        let registry: TranslationRegistry
        var verses: [BibleVerse] = []
        var errorDescription: String?
        /// 이 번역본 자신의 언어로 표시하는 "책 장" 레이블(예: "John 3"). 2026-08-06
        /// 추가 — TranslationInfo.swift(이전 앱)의 bookNameTableID/resolvedBookDisplayName
        /// 개념을 이식(BookNameTableProvider.swift 참고). registry.bookNameTableID가
        /// nil이거나 해당 이름표를 못 찾으면 한글 기본 이름으로 자동 폴백된다.
        var localizedBookChapterLabel: String = ""
    }

    private(set) var selectedBook: Book
    private(set) var selectedChapter: Int
    private(set) var availableTranslations: [TranslationRegistry] = []
    /// 지금 화면에 나란히 표시 중인 번역본(최대 3개, screens.md 3장/4장 — macOS/iPadOS
    /// 기준. iPhone은 화면 레이어에서 이 중 첫 번째만 골라 1열로 보여준다).
    private(set) var displayedTranslationIDs: [PersistentIdentifier] = []
    private(set) var columns: [ColumnState] = []
    var lastErrorDescription: String?

    /// [2026-08-08 추가] 클립보드 복사용 다중 선택 — 절 번호 기준(모든 컬럼이
    /// 공유한다, TranslationColumnView.swift 상단 주석 참고). 장을 이동하면
    /// 이전 장의 절 번호가 그대로 남아 있어도 의미가 없으므로 `selectBook`/
    /// `goToChapter`에서 비운다.
    private(set) var selectedVerses: Set<Int> = []
    var hasVerseSelection: Bool { !selectedVerses.isEmpty }

    /// [2026-08-19 추가] 사용자 요청 — "검색 결과중 - 성경구절을 클릭하면
    /// 해당하는 절까지 스크롤 이동해서 잠시 하이라이트 표시해줄것." 실제
    /// 스크롤/강조 표시는 `TranslationColumnView.highlightedVerse`가 맡는다 —
    /// 그 프로퍼티는 원래 이 용도로 미리 마련돼 있었지만(그쪽 `VerseRow.
    /// isHighlighted` 상단 주석 참고) 실제로 연결된 적은 없었다. 이 뷰모델은
    /// "지금 몇 절이 강조 대상인지"만 들고 있고, 몇 초 뒤 자동으로 끄는 타이머도
    /// 여기서 관리한다.
    private(set) var highlightedVerse: Int?
    private var highlightClearWorkItem: DispatchWorkItem?
    private static let highlightDuration: TimeInterval = 2.5

    /// 이 절을 몇 초간만 강조 표시한다. 이미 다른 절이 강조돼 있었다면(또는 같은
    /// 절의 이전 타이머가 아직 안 끝났다면) 그 타이머를 취소하고 새로 시작한다.
    func highlightVerseTemporarily(_ verse: Int) {
        highlightClearWorkItem?.cancel()
        highlightedVerse = verse
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.highlightedVerse == verse else { return }
            self.highlightedVerse = nil
        }
        highlightClearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.highlightDuration, execute: workItem)
    }

    // MARK: - 이 장의 관련 콘텐츠(개요/메모/연구문서) — 2026-08-08 추가
    //
    // 사용자 요청 — "성경 장을 읽을 때 이 성경의 개요와 메모, 연구문서가 있다는
    // 것을 한번에 확인할 수 있는 화면". screens.md 원본 대형 항목 목록엔 "S1
    // 관련문서 패널"이 있었지만 실제로 만들어진 적이 없었다(README 2026-08-07
    // 라운드 기록 참고) — 이번에 처음 구현한다.
    //
    // ⚠️ [범위] BookOutline/ChapterSummary 조회는 S8/S9(OutlineViewModel)의
    // "find-or-create"(BookOutlineDeduplication/ChapterSummaryDeduplication)를
    // 쓰지 않는다 — 그 로직은 "편집하러 들어왔으니 없으면 빈 문서를 만들어 둔다"는
    // 의도인데, 이 패널은 순수 조회 목적이라 방문만 해도 빈 개요 레코드가 생기는
    // 부작용을 만들고 싶지 않다. 그래서 여기서는 읽기 전용 fetch만 하고, 내용이
    // 비어 있으면(사용자가 실제로 아무것도 안 쓴 경우) "없음"으로 취급한다.
    private(set) var relatedBookOutlinePreview: String?
    private(set) var relatedChapterSummaryPreview: String?
    /// [2026-08-15 추가] 사용자 요청 — "[성경 조회] 오른쪽 인스펙터 — 개요:
    /// 단순 텍스트 몇 줄이 아니라, 왼쪽 개요 기능에서 입력한 텍스트와 서식이
    /// 그대로 표시될 것." 위 `relatedBookOutlinePreview`/`relatedChapterSummaryPreview`
    /// (트리밍된 순수 텍스트, "개요가 있는지" 판단용으로 남겨 둠)와 달리, 이
    /// 둘은 `BookOutline`/`ChapterSummary.contentHtml`(실제로는 RTF —
    /// `RichTextEditor.swift` 상단 주석 참고)을 그대로 담아 `ChapterRelatedContentPanel`이
    /// `RichTextEditor(isEditable: false)`로 서식까지 재현할 수 있게 한다.
    private(set) var relatedBookOutlineRTF: String?
    private(set) var relatedChapterSummaryRTF: String?
    private(set) var relatedChapterMemos: [UserMemo] = []
    /// [2026-08-12 추가] 사용자 요청 — "[성경 조회] 오른쪽 상단 버튼중 사이드
    /// 인스펙터 창 버튼 - 관련 문서 정보에 [관련 말씀 요약] 추가." 개인 묵상
    /// (`relatedChapterMemos`)과 완전히 같은 원칙 — 이 장 안의 `VerseSummary`를
    /// 전부 불러온다(저널 성격이라 한 절에 여러 개가 쌓일 수 있음).
    private(set) var relatedChapterWordSummaries: [VerseSummary] = []
    /// ⚠️ [범위, 검증 필요] `SourceDocument.relatedChapterRef`는 Codable 구조체
    /// 옵셔널 필드라 SwiftData `#Predicate`로 안전하게 필터링할 수 있다는 확신이
    /// 없다(이 프로젝트가 이미 다른 곳 — TagGraphViewModel 등 — 에서 복잡한
    /// 관계/구조체 조건은 전체 fetch 후 Swift 레벨에서 거른다는 원칙을 따르고
    /// 있다). 문서가 아주 많아지면 매 장 이동마다 전체 스캔이 느려질 수 있다 —
    /// 지금 규모(v1)에서는 허용 가능하다고 판단했다.
    private(set) var relatedDocuments: [SourceDocument] = []

    // MARK: - 구간 주석(형광펜/표시/관주) — 2026-08-08 신설
    //
    // 사용자 요청 — "성경구절의 특정단어, 특정 표현에 관주를 넣거나, 표시를 하거나,
    // 메모를 넣거나, 형광펜을 칠하고 싶음". README "이어서 16" 설계 논의 참고.
    // 절 단위 메모(`relatedChapterMemos`)와 같은 원칙으로, 지금 보고 있는 장
    // 전체 분량을 한 번에 불러와 두고 각 절 렌더링 시점에는 메모리에서 필터링만
    // 한다(장 하나 분량이라 매 절마다 새로 쿼리할 필요가 없다).
    private(set) var chapterHighlights: [VerseHighlight] = []
    /// [2026-08-15 변경] 사용자 요청 — "성경관련 json seed 파일은 기본 제공 db에
    /// 넣을 것 ... 관주." 이제 이 배열은 두 출처를 섞어 담는다: 사용자가 실제로
    /// 만든 관주(SwiftData, `source == .user`)와, `ReferenceData.sqlite`에서 매번
    /// 읽어 오는 번들 관주(`source == .bundled`, `ModelContext`에 `insert`하지
    /// 않은 인메모리 인스턴스 — `ReferenceDataStore.crossReferences(...)` 상단
    /// 주석 참고). 아래 `crossReferences(translationCode:verse:)` 필터링 메서드는
    /// 손대지 않아도 된다 — 어차피 절 번호로만 걸러서 두 출처를 구분할 필요가
    /// 없다.
    private(set) var chapterCrossReferences: [VerseCrossReference] = []
    /// [2026-08-11 신설] "메모"(신규, 드래그한 특정 표현에 짧은 텍스트를 붙이는
    /// 기능) — 위 `chapterHighlights`와 완전히 같은 원칙(장 전체를 한 번에 불러와
    /// 절 렌더링 시점엔 메모리 필터링만).
    private(set) var chapterPhraseNotes: [VersePhraseNote] = []
    /// [2026-08-14 신설, 2026-08-15 변경] 난외주 — 위 `chapterCrossReferences`와
    /// 완전히 같은 이유로 사용자 생성분(SwiftData, 지금은 편집 UI가 없어 항상
    /// 비어 있다)과 번들분(`ReferenceData.sqlite`, 인메모리 인스턴스)을 섞어 담는다.
    private(set) var chapterMarginalNotes: [VerseMarginalNote] = []
    /// [2026-08-14 신설, 2026-08-15 변경] 절 단위 한자 주석 — 사용자가 직접 만드는
    /// 경로가 아예 없는 100% 번들 전용 데이터라(`VerseHanjaAnnotation` `@Model`
    /// 자체를 삭제했다, `BibleResearchModels`의 "삭제, 같은 날 되돌림" 주석 참고)
    /// 더 이상 SwiftData를 거치지 않는다 — `ReferenceDataStore.hanjaAnnotations(
    /// bookId:chapter:)`가 돌려준 절 번호별 딕셔너리를 그대로 들고 있는다.
    private(set) var chapterHanjaAnnotations: [Int: [HanjaWordAnnotation]] = [:]

    // MARK: - 메모/연구문서 안의 성경구절 언급("관련 내용") — 2026-08-11 신설
    //
    // 사용자 요청 — "메모/연구문서 안의 성경구절을 추출해 DB에 저장하고, 해당
    // 구절에서 그 메모/문서를 확인할 수 있도록." `chapterHighlights`와 같은 원칙 —
    // 지금 보고 있는 장 전체 분량을 한 번에 불러와 두고, 절 단위 렌더링 시점에는
    // 메모리에서 필터링만 한다(`BibleReferenceIndexingService`가 실제 인덱스
    // 재계산을 담당 — `onAppear` 참고).
    private(set) var chapterVerseMentions: [VerseMention] = []

    /// `TranslationColumnView.VerseRow`가 호출 — 이 번역본·이 절에 걸린 형광펜/표시만
    /// 골라 낸다.
    func highlights(translationCode: String, verse: Int) -> [VerseHighlight] {
        chapterHighlights.filter { $0.translationCode == translationCode && $0.verse == verse }
    }

    func crossReferences(translationCode: String, verse: Int) -> [VerseCrossReference] {
        chapterCrossReferences.filter { $0.translationCode == translationCode && $0.verse == verse }
    }

    /// `TranslationColumnView.VerseRow`가 호출 — 이 번역본·이 절에 걸린 난외주만
    /// 골라 낸다. 위 `crossReferences(translationCode:verse:)`와 같은 원칙.
    func marginalNotes(translationCode: String, verse: Int) -> [VerseMarginalNote] {
        chapterMarginalNotes.filter { $0.translationCode == translationCode && $0.verse == verse }
    }

    /// `TranslationColumnView.VerseRow`가 호출 — 이 번역본·이 절의 한자 주석
    /// 단어 목록. 개역한글(`TranslationBootstrap.bundledTranslationCode`) 외의
    /// 번역본은 애초에 이 코드로 저장된 레코드가 없어 항상 빈 배열이 나온다 —
    /// 호출부가 번역본별로 따로 분기할 필요가 없다(`crossReferences`와 동일한
    /// 원칙).
    func hanjaWords(translationCode: String, verse: Int) -> [HanjaWordAnnotation] {
        guard translationCode == TranslationBootstrap.bundledTranslationCode else { return [] }
        return chapterHanjaAnnotations[verse] ?? []
    }

    /// `TranslationColumnView.VerseRow`/`VerseZoomView`가 호출 — 이 번역본·이 절에
    /// 걸린 "메모"(드래그 표현 부연설명)만 골라 낸다. 형광펜/표시와 같은 원칙 —
    /// 특정 표현에 종속되므로 번역본별로 다르다.
    func phraseNotes(translationCode: String, verse: Int) -> [VersePhraseNote] {
        chapterPhraseNotes.filter { $0.translationCode == translationCode && $0.verse == verse }
    }

    /// [2026-08-11 추가] 이 절을 정확히 언급하는 메모/연구문서("관련 내용") —
    /// 번역본과 무관하다(메모/문서 텍스트 안의 언급이라 특정 번역본에 종속되지
    /// 않는다). ⚠️ [범위] "요한복음 3장"처럼 절 번호 없이 장만 가리키는 언급
    /// (`verse == nil`)은 여기 포함하지 않는다 — 포함하면 그 장의 모든 절 아이콘에
    /// 똑같이 나타나 오히려 신호가 흐려진다고 판단했다.
    func verseMentions(verse: Int) -> [VerseMention] {
        chapterVerseMentions.filter { $0.verse == verse }
    }

    /// [2026-08-11 추가] `VerseMention.sourceId`(UUID 문자열)로 실제 `UserMemo`를
    /// 되찾는다 — `VerseMention`은 `EmbeddingChunk`와 같은 이유로 관계가 아니라
    /// 원시 문자열 ID로만 출처를 가리킨다(`VerseMentions.swift` 상단 주석 참고).
    func resolveMemo(for mention: VerseMention) -> UserMemo? {
        guard mention.sourceType == .memo, let uuid = UUID(uuidString: mention.sourceId) else { return nil }
        return (try? modelContext.fetch(
            FetchDescriptor<UserMemo>(predicate: #Predicate { $0.id == uuid })
        ))?.first
    }

    /// 위 `resolveMemo(for:)`와 같은 이유 — 연구문서 쪽.
    func resolveDocument(for mention: VerseMention) -> SourceDocument? {
        guard mention.sourceType == .document, let uuid = UUID(uuidString: mention.sourceId) else { return nil }
        return (try? modelContext.fetch(
            FetchDescriptor<SourceDocument>(predicate: #Predicate { $0.id == uuid })
        ))?.first
    }

    /// [2026-08-12 추가] 위 `resolveMemo(for:)`와 같은 이유 — 말씀 요약 쪽.
    func resolveWordSummary(for mention: VerseMention) -> VerseSummary? {
        guard mention.sourceType == .wordSummary, let uuid = UUID(uuidString: mention.sourceId) else { return nil }
        return (try? modelContext.fetch(
            FetchDescriptor<VerseSummary>(predicate: #Predicate { $0.id == uuid })
        ))?.first
    }

    /// 이 번역본·이 절에 보여줄 메모 아이콘 대상. `relatedChapterMemos`를 다시
    /// 쿼리하지 않고 그대로 필터링만 한다.
    ///
    /// ⚠️ [2026-08-11 수정, 버그] 원래는 `rangeStart != nil`(구간 메모)만 걸렀다 —
    /// "내 메모"(MemoHomeView)에서 성경 좌표만 지정하고 만든 절 전체 메모는
    /// `rangeStart`가 nil이라 여기서 항상 빠졌고, 그 결과 메인 화면/확대보기
    /// 어디에도 메모 아이콘이 뜨지 않았다(사용자 보고 — "내 메모에서 입력한
    /// 메모의 아이콘이 안 보임"). 구간 메모(`rangeStart != nil`)는 특정
    /// 번역본의 특정 표현에 종속되므로 그 번역본 컬럼에서만 보여주고,
    /// 절 전체 메모(`rangeStart == nil`)는 번역본과 무관하게 그 절을 보여주는
    /// 모든 컬럼에 노출한다.
    func phraseMemos(translationCode: String, verse: Int) -> [UserMemo] {
        relatedChapterMemos.filter { memo in
            guard memo.verse == verse else { return false }
            if memo.rangeStart != nil {
                return memo.annotationTranslationCode == translationCode
            }
            return true
        }
    }

    /// "구절 확대보기"에서 형광펜/표시를 적용할 때 호출. `range`는 `UITextView.
    /// selectedRange`/`NSTextView.selectedRange()`가 준 UTF-16 단위 `NSRange` —
    /// `VerseAnnotations.swift` 상단 주석이 정한 저장 규칙과 정확히 같은 단위다.
    func addHighlight(
        translationCode: String, verse: Int, range: NSRange, anchorText: String,
        style: VerseHighlightStyle, colorTag: String?
    ) {
        let highlight = VerseHighlight(
            translationCode: translationCode, bookId: selectedBook.bookId, chapter: selectedChapter,
            verse: verse, rangeStart: range.location, rangeEnd: range.location + range.length,
            anchorText: anchorText, style: style, colorTag: colorTag
        )
        modelContext.insert(highlight)
        try? modelContext.save()
        chapterHighlights.append(highlight)
    }

    func deleteHighlight(_ highlight: VerseHighlight) {
        modelContext.delete(highlight)
        try? modelContext.save()
        chapterHighlights.removeAll { $0.id == highlight.id }
    }

    // MARK: - "메모"(신규, 드래그 표현 부연설명) — 2026-08-11 신설

    /// "확대보기"에서 표현을 드래그하고 새 "메모" 버튼을 눌렀을 때 호출.
    func addPhraseNote(
        translationCode: String, verse: Int, range: NSRange, anchorText: String, noteText: String
    ) {
        // [2026-08-12 추가] 사용자 요청 — "메모상자 배경색 추가: 형광펜 색
        // 연하게 20~30%정도 랜덤 색상으로 보여지게 - 한번 지정되면 다음에
        // 열어도 바뀌지 않게 - DB저장." 메모를 처음 만드는 이 시점에 딱 한
        // 번만 무작위로 색을 골라 `colorTagRaw`에 저장한다 — 이후 화면(
        // `PhraseNoteBoxView`)은 그 저장된 값을 그대로 읽기만 하므로, 같은
        // 메모를 다시 열어도 항상 같은 색으로 보인다.
        let colorTag = HighlightColorTag.allCases.randomElement() ?? .yellow
        let note = VersePhraseNote(
            translationCode: translationCode, bookId: selectedBook.bookId, chapter: selectedChapter,
            verse: verse, rangeStart: range.location, rangeEnd: range.location + range.length,
            anchorText: anchorText, noteText: noteText, colorTagRaw: colorTag.rawValue
        )
        modelContext.insert(note)
        try? modelContext.save()
        chapterPhraseNotes.append(note)
    }

    /// 우클릭(macOS)/편집 메뉴(iOS)의 "메모 수정" 또는 편집 팝오버 저장 버튼에서 호출.
    func updatePhraseNote(_ note: VersePhraseNote, noteText: String) {
        note.noteText = noteText
        note.updatedAt = .now
        try? modelContext.save()
    }

    func deletePhraseNote(_ note: VersePhraseNote) {
        modelContext.delete(note)
        try? modelContext.save()
        chapterPhraseNotes.removeAll { $0.id == note.id }
    }

    /// "관주 연결"에서 호출. `range`가 nil이면(절 전체 관주) `anchorText`도 nil로
    /// 저장한다 — `VerseAnnotations.swift`의 `VerseCrossReference` 옵셔널 규칙 참고.
    func addCrossReference(
        translationCode: String, verse: Int, range: NSRange?, anchorText: String?, targets: [BibleVerseRef],
        entryLabels: [String] = [], entryVerseCounts: [Int] = []
    ) {
        let reference = VerseCrossReference(
            translationCode: translationCode, bookId: selectedBook.bookId, chapter: selectedChapter,
            verse: verse, rangeStart: range?.location,
            rangeEnd: range.map { $0.location + $0.length }, anchorText: anchorText,
            source: .user, targets: targets, entryLabels: entryLabels, entryVerseCounts: entryVerseCounts
        )
        modelContext.insert(reference)
        try? modelContext.save()
        chapterCrossReferences.append(reference)
    }

    func deleteCrossReference(_ reference: VerseCrossReference) {
        modelContext.delete(reference)
        try? modelContext.save()
        chapterCrossReferences.removeAll { $0.id == reference.id }
    }

    /// [2026-08-09 추가] 사용자 요청 — "관주 -> 클릭했을 때 나오는 풍선 팝업의
    /// 작은 (x) 아이콘"으로 개별 대상만 지울 수 있게. `VerseCrossReference` 한
    /// 개가 대상을 여러 개(`targets`) 가질 수 있어(한 번의 "관주 연결" 조작에서
    /// 여러 구절을 골랐을 수 있음), 그중 하나만 지울 때는 배열에서 그 항목만
    /// 빼야 한다 — 마지막 하나였다면(배열이 비게 되면) 레코드 자체가 더 이상
    /// 의미가 없으므로 `deleteCrossReference`로 통째로 지운다.
    func removeCrossReferenceTarget(_ target: BibleVerseRef, from reference: VerseCrossReference) {
        var updated = reference.targets
        updated.removeAll { $0 == target }
        if updated.isEmpty {
            deleteCrossReference(reference)
        } else {
            reference.targets = updated
            // [2026-08-25 추가] 사이드바 "최근" 이력 목록이 이 시각을 정렬
            // 기준으로 쓴다(`SidebarNavigationView.SidebarQuickItem.sortDate`
            // 참고) — 대상을 하나 지우는 것도 이 관주를 "수정"한 것이므로 갱신한다.
            reference.updatedAt = .now
            try? modelContext.save()
        }
    }

    /// [2026-08-12 추가] 사용자 요청 — "관주를 클릭해서 볼 때는... 정제되어서
    /// 보여져야 함." 팝오버가 이제 절 하나당 행이 아니라 "사용자가 입력한 항목"
    /// (`VerseCrossReference.groupedEntries`) 하나당 행을 보여주므로, 지우는
    /// 단위도 그 항목 전체(여러 절을 포함할 수 있음)로 맞춘다. 위
    /// `removeCrossReferenceTarget`(절 하나만 지움)은 정합 정보가 없는 레거시
    /// 데이터를 절 단위로 대체 표시할 때를 위해 그대로 남겨 둔다.
    func removeCrossReferenceGroup(_ verses: [BibleVerseRef], from reference: VerseCrossReference) {
        // groupedEntries가 정합적이면(entryLabels/entryVerseCounts가 targets와
        // 맞으면) 그 메타데이터에서도 해당 항목을 함께 지워 정합을 유지한다.
        if let grouped = reference.groupedEntries,
           let groupIndex = grouped.firstIndex(where: { $0.verses == verses }) {
            var labels = reference.entryLabels
            var counts = reference.entryVerseCounts
            labels.remove(at: groupIndex)
            counts.remove(at: groupIndex)
            reference.entryLabels = labels
            reference.entryVerseCounts = counts
        }

        var updated = reference.targets
        for verse in verses {
            if let index = updated.firstIndex(of: verse) {
                updated.remove(at: index)
            }
        }
        if updated.isEmpty {
            deleteCrossReference(reference)
        } else {
            reference.targets = updated
            // [2026-08-25 추가] 위 `removeCrossReferenceTarget`과 같은 이유.
            reference.updatedAt = .now
            try? modelContext.save()
        }
    }

    /// "메모 작성"(구간 메모)에서 호출 — 만든 메모를 그대로 돌려주므로 호출부(뷰)가
    /// 기존 `memoBeingCreated` 시트 흐름에 곧바로 넘길 수 있다(절 전체 메모를 만들
    /// 때와 동일한 패턴, `BibleReadingView.createMemo` 참고).
    /// [2026-08-11 추가] 사용자 요청 — "메모(→개인 주석)는 관주처럼 항상
    /// 활성화되도록. 드래그하지 않아도 절에 종속되도록." 이 절에 이미 있는
    /// 절 전체 메모(`rangeStart == nil` — 구간 메모가 아님)를 찾는다. 번역본과
    /// 무관하다(`phraseMemos(translationCode:verse:)` 상단 주석과 같은 이유 —
    /// 절 전체 메모는 특정 번역본에 종속되지 않는다).
    func verseLevelMemo(verse: Int) -> UserMemo? {
        relatedChapterMemos.first { $0.verse == verse && $0.rangeStart == nil }
    }

    /// 위 `verseLevelMemo(verse:)`가 없으면 새로 만든다 — "개인 주석" 버튼(확대보기)
    /// 전용. "내 메모"(MemoHomeView.createNewMemo)와 같은 방식으로 좌표만 채운
    /// 빈 메모를 만들고, 호출부가 곧바로 편집기 시트로 연다.
    func openOrCreateVerseMemo(verse: Int) -> UserMemo {
        if let existing = verseLevelMemo(verse: verse) { return existing }
        let memo = UserMemo(bookId: selectedBook.bookId, chapter: selectedChapter, verse: verse)
        modelContext.insert(memo)
        try? modelContext.save()
        relatedChapterMemos.insert(memo, at: 0)
        BibleReferenceIndexingService.reindexMemo(memo, context: modelContext)
        return memo
    }

    func createPhraseMemo(translationCode: String, verse: Int, range: NSRange, anchorText: String) -> UserMemo {
        let memo = UserMemo(
            bookId: selectedBook.bookId, chapter: selectedChapter, verse: verse,
            rangeStart: range.location, rangeEnd: range.location + range.length,
            annotationTranslationCode: translationCode, anchorText: anchorText
        )
        modelContext.insert(memo)
        try? modelContext.save()
        relatedChapterMemos.insert(memo, at: 0)
        // [2026-08-11 추가] 새로 만든 메모도 이벤트 기반 인덱싱 대상 — 이 시점엔
        // 보통 본문이 비어 있어 실질적으로는 no-op이지만(사용자가 방금 만들었을
        // 뿐 아직 아무것도 안 씀), 다른 저장 경로와 일관되게 항상 호출해 둔다.
        BibleReferenceIndexingService.reindexMemo(memo, context: modelContext)
        return memo
    }

    let scrollSyncCoordinator = ScrollSyncCoordinator()

    /// sqliteFileReference(파일 경로) 기준 캐시 — 같은 파일을 매 장 이동마다 다시 열지
    /// 않는다.
    private var storeCache: [String: BibleReferenceStore] = [:]

    /// TranslationColumnView.columnID(ScrollSyncCoordinator의 리더/팔로워 식별자)를
    /// registry마다 안정적으로 유지하기 위한 캐시. 장을 이동할 때마다 컬럼 UUID가
    /// 바뀌면 SwiftUI가 컬럼 뷰를 매번 새로 만들어(스크롤 위치·애니메이션이 끊기고)
    /// 동기화 이벤트의 출처 판별도 불안정해지므로, registry당 UUID 하나를 계속
    /// 재사용한다.
    private var columnIDsByRegistry: [PersistentIdentifier: UUID] = [:]

    private let modelContext: ModelContext
    private let booksProvider: BooksProvider
    let maxColumns = 3

    // 2026-08-06: `booksProvider: BooksProvider = .shared`처럼 기본 인자 값에서 곧바로
    // MainActor 격리 정적 프로퍼티(.shared)를 참조하면 Swift 6 엄격 동시성에서 오류가
    // 난다 — 기본 인자 표현식은 이 타입이 @MainActor여도 자동으로 격리되지 않기
    // 때문이다(초기화 본문과 달리 표현식 자체가 nonisolated 컨텍스트에서 평가됨).
    // 그래서 파라미터를 옵셔널로 받고, 본문(= MainActor 컨텍스트) 안에서 `?? .shared`로
    // 대체한다.
    // [2026-08-08 추가] 사용자 요청 — "[성경 조회] 상태에서 다른 메뉴로 이동 후 다시
    // 돌아오면 직전에 보던 장을 유지". `initialBook`이 명시된 호출(SearchView.swift —
    // 검색 결과 탭)은 사용자의 명확한 의도이므로 마지막 위치를 무시하고 그대로 연다.
    // `initialBook`이 nil인 일반 진입(사이드바/탭바에서 매개변수 없이 여는 경우)만
    // `LastBiblePositionTracker`(메모리 전용, 앱 재시작 시 사라짐 — 그 경우 3번째
    // 폴백인 "첫 번째 책 1장"을 그대로 쓴다)로 복원한다.
    init(modelContext: ModelContext, booksProvider: BooksProvider? = nil, initialBook: Book? = nil, initialChapter: Int? = nil) {
        self.modelContext = modelContext
        let resolvedBooksProvider = booksProvider ?? .shared
        self.booksProvider = resolvedBooksProvider
        let fallbackBook = Book(bookId: 1, testament: .old, orderIndex: 1, nameKo: "창세기", nameOriginal: "Genesis", abbreviation: ["창"], chapterCount: 50)
        if let initialBook {
            self.selectedBook = initialBook
            self.selectedChapter = initialChapter ?? 1
        } else if let lastBookId = LastBiblePositionTracker.shared.bookId,
                  let lastBook = resolvedBooksProvider.book(id: lastBookId) {
            self.selectedBook = lastBook
            self.selectedChapter = initialChapter ?? LastBiblePositionTracker.shared.chapter ?? 1
        } else {
            self.selectedBook = resolvedBooksProvider.books.first ?? fallbackBook
            self.selectedChapter = initialChapter ?? 1
        }
    }

    func onAppear() {
        // [2026-08-11 변경] 사용자 요청 — "성경 조회 화면에 들어갈 때마다 재스캔이
        // 아니라, 메모/연구문서를 등록·수정·삭제할 때마다 재계산." 여기서 전체
        // 재스캔을 부르던 걸 없앴다 — 이제 인덱스 최신화는 각 저장/삭제 지점
        // (MemoDetailView/MemoHomeView/DocumentTextExtractionService/
        // OCRReviewViewModel/DocumentsViewModel)에서 개별적으로 책임진다
        // (BibleReferenceIndexingService.swift 상단 주석 참고).
        purgeLegacyMarkHighlights()
        loadAvailableTranslations()
        refreshRelatedContent()
    }

    /// [2026-08-12 추가] 사용자 요청 — "기존 밑줄 데이터는 모두 삭제할 것."
    /// 확대보기의 "표시"(수동 밑줄, `.mark`) 버튼을 없앤 뒤, 그 전에 이미
    /// 만들어져 있던 `.mark` 형광펜 레코드를 정리한다. 화면에 들어올 때마다
    /// 조회하지만, 한 번 지워진 뒤로는 검색 결과가 항상 0건이라 사실상 저비용
    /// 무동작이다 — 일회성 플래그 대신 매번 확인하는 쪽을 택한 이유는,
    /// CloudKit 동기화로 다른 기기에 남아 있던 예전 데이터가 나중에 다시
    /// 들어올 가능성까지 자가 치유하기 위해서다.
    private func purgeLegacyMarkHighlights() {
        let markRaw = VerseHighlightStyle.mark.rawValue
        let descriptor = FetchDescriptor<VerseHighlight>(predicate: #Predicate { $0.styleRaw == markRaw })
        guard let legacy = try? modelContext.fetch(descriptor), !legacy.isEmpty else { return }
        for highlight in legacy { modelContext.delete(highlight) }
        try? modelContext.save()
        // 지금 메모리에 캐시된 장(`chapterHighlights`)에도 섞여 있을 수 있으니
        // 함께 제거한다 — 그대로 두면 다음 재조회 전까지 화면에 남아 보인다.
        chapterHighlights.removeAll { $0.styleRaw == markRaw }
    }

    func loadAvailableTranslations() {
        let descriptor = FetchDescriptor<TranslationRegistry>(sortBy: [SortDescriptor(\.addedAt, order: .forward)])
        do {
            let all = try modelContext.fetch(descriptor)
            availableTranslations = all
            // 아직 아무것도 선택돼 있지 않으면(최초 진입) 기본 표시 목록을 정한다.
            // 2026-08-07(원본 문서 재확인 라운드): 8.3 "성경 조회(S1) 기본 표시 3개
            // 체크박스 선택"(UserSettingsStore.defaultDisplayedTranslationCodes)이
            // 있으면 최우선으로 그 목록을 쓴다 — 8.1의 defaultTranslationCode(맨
            // 앞으로 당기기)와는 별개 설정이다. 8.3 설정이 비어 있으면(사용자가
            // 아직 체크박스를 고르지 않음) 기존처럼 "등록 순 + defaultTranslationCode
            // 맨 앞" 규칙으로 대체한다.
            if displayedTranslationIDs.isEmpty {
                let preferredCodes = UserSettingsStore.shared.defaultDisplayedTranslationCodes
                if !preferredCodes.isEmpty {
                    let byCode = Dictionary(uniqueKeysWithValues: all.map { ($0.code, $0) })
                    let chosen = preferredCodes.compactMap { byCode[$0] }
                    displayedTranslationIDs = Array(chosen.prefix(maxColumns)).map(\.persistentModelID)
                }
                if displayedTranslationIDs.isEmpty {
                    var ordered = all
                    if let preferredCode = UserSettingsStore.shared.defaultTranslationCode,
                       let index = ordered.firstIndex(where: { $0.code == preferredCode }) {
                        let preferred = ordered.remove(at: index)
                        ordered.insert(preferred, at: 0)
                    }
                    displayedTranslationIDs = ordered.prefix(maxColumns).map(\.persistentModelID)
                }
            } else {
                // 목록이 바뀌었을 수 있으니(예: 번역본 삭제) 더 이상 존재하지 않는 선택은
                // 걸러낸다.
                let stillValid = Set(all.map(\.persistentModelID))
                displayedTranslationIDs = displayedTranslationIDs.filter { stillValid.contains($0) }
            }
            reloadVerses()
        } catch {
            lastErrorDescription = "등록된 번역본 목록을 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    func selectBook(_ book: Book, chapter: Int = 1) {
        pushCurrentLocationToBackStack()
        selectedBook = book
        selectedChapter = max(1, chapter)
        clearVerseSelection()
        reloadVerses()
        refreshRelatedContent()
        LastBiblePositionTracker.shared.update(bookId: book.bookId, chapter: selectedChapter)
        // [2026-08-08 추가] 조회 이력 기록 — `init`이 마지막 위치를 "복원"할 때는
        // 이 메서드를 거치지 않으므로(직접 selectedBook/selectedChapter를 대입) 여기서
        // 기록해도 탭 전환마다 중복 이력이 쌓이지 않는다.
        BibleReadingHistoryService.record(bookId: book.bookId, chapter: selectedChapter, context: modelContext)
    }

    func goToChapter(_ chapter: Int) {
        guard chapter >= 1 else { return }
        pushCurrentLocationToBackStack()
        selectedChapter = chapter
        clearVerseSelection()
        reloadVerses()
        refreshRelatedContent()
        LastBiblePositionTracker.shared.update(bookId: selectedBook.bookId, chapter: chapter)
        BibleReadingHistoryService.record(bookId: selectedBook.bookId, chapter: chapter, context: modelContext)
    }

    // MARK: - 조회 이력 (2026-08-08 추가)

    /// 최신순으로 정렬된 조회 이력 전체(최대 100개, `BibleReadingHistoryService.maxEntries`)를
    /// 반환한다. 히스토리 시트가 열릴 때마다 새로 불러 쓴다(다른 창에서 쌓인 이력까지
    /// 반영되도록 캐싱하지 않는다).
    func fetchHistory() -> [BibleReadingHistoryEntry] {
        (try? modelContext.fetch(
            FetchDescriptor<BibleReadingHistoryEntry>(sortBy: [SortDescriptor(\.viewedAt, order: .reverse)])
        )) ?? []
    }

    /// 히스토리 목록에서 항목을 탭했을 때 그 책/장으로 이동한다. `selectBook`을
    /// 그대로 재사용하므로 이 이동 자체도 새 이력으로 다시 기록된다 — "지금 다시
    /// 조회했다"는 것 역시 실제 조회 이벤트이므로 자연스러운 동작이다.
    func jumpToHistoryEntry(_ entry: BibleReadingHistoryEntry) {
        guard let book = booksProvider.book(id: entry.bookId) else { return }
        selectBook(book, chapter: entry.chapter)
    }

    // MARK: - 클립보드 복사용 절 선택 (2026-08-08 추가)

    /// [2026-08-15 추가, 이후 보조키 Control → Option 변경] 범위/개별 다중
    /// 선택의 "기준점" — 마지막으로 일반 클릭 또는 Option 클릭(개별 토글)한
    /// 절 번호. Shift/Cmd 클릭(범위 선택) 시 이 값부터 새로 클릭한 절까지를
    /// 범위로 잡는다. `TranslationColumnView`가 macOS에서 `NSEvent.
    /// modifierFlags`로 어떤 클릭인지 구분해 아래 세 메서드 중 하나를 호출한다.
    private(set) var verseSelectionAnchor: Int?

    /// 일반 클릭 — 기존 선택을 전부 지우고 이 절 하나만 선택한다("클릭하면
    /// 구절이 선택되고, 다른 구절을 클릭하면 선택이 바뀌게" 요청).
    func selectSingleVerse(_ verse: Int) {
        selectedVerses = [verse]
        verseSelectionAnchor = verse
    }

    /// Option 클릭 — 이 절 하나만 선택 목록에서 추가/제거한다(다른 절 선택은
    /// 그대로 유지). "개별 다중 선택은 컨트롤 키" 요청이었으나, macOS에서
    /// Control+클릭이 컨텍스트 메뉴 열기와 겹칠 수 있어 Option 키로 교체했다
    /// (`TranslationColumnView.swift`의 tap 핸들러 주석 참고).
    func toggleVerseSelection(_ verse: Int) {
        if selectedVerses.contains(verse) {
            selectedVerses.remove(verse)
        } else {
            selectedVerses.insert(verse)
        }
        verseSelectionAnchor = verse
    }

    /// Shift/Cmd 클릭 — 기준점(`verseSelectionAnchor`)부터 이 절까지를 범위로
    /// 선택한다("범위 선택은 쉬프트, 커맨드키" 요청). 기준점이 아직 없으면(예:
    /// 아무것도 선택 안 된 상태에서 바로 Shift 클릭) 그냥 이 절 하나만 선택하고
    /// 이 절을 새 기준점으로 삼는다.
    func extendVerseSelection(to verse: Int) {
        guard let anchor = verseSelectionAnchor else {
            selectSingleVerse(verse)
            return
        }
        let range = anchor <= verse ? anchor...verse : verse...anchor
        selectedVerses = Set(range)
    }

    func clearVerseSelection() {
        selectedVerses.removeAll()
        verseSelectionAnchor = nil
    }

    /// 지금 선택된 절들을 환경설정(복사 형식) 그대로 문자열로 만든다. 클립보드에
    /// 실제로 넣는 것은 호출부(View) 책임이다 — `UIPasteboard`/`NSPasteboard`는
    /// 플랫폼 API라 뷰모델이 직접 알 필요가 없다(플랫폼 분기를 뷰 레이어에만
    /// 두는 이 프로젝트의 기존 관례, DocumentsHomeView의 `#if os(iOS)` 등과 같은
    /// 원칙).
    func formattedCopyText() -> String? {
        let translations = columns.map {
            BibleVerseCopyFormatter.TranslationSnapshot(displayName: $0.registry.displayName, verses: $0.verses)
        }
        return BibleVerseCopyFormatter.format(
            book: selectedBook,
            chapter: selectedChapter,
            selectedVerses: selectedVerses,
            translations: translations
        )
    }

    /// [2026-08-12 추가, 2026-08-12 2차 수정] 사용자 요청 — "말씀 요약 ... 그
    /// 다음줄: 선택된 성경구절 자동입력" + "말씀 복사 탭 시 에디터 커서 위치에
    /// 성경구절 붙여넣기." `formattedCopyText()`(지금 화면에 보이는 모든
    /// 번역본)와 달리, 항상 "기준 번역본(맨 왼쪽 열)" 한 곳만 쓴다 — 말씀 요약을
    /// 열면 어차피 기준 번역본만 남기고 나머지 열을 숨기므로(BibleReadingView.swift
    /// `openWordSummaryEditor()` 참고) 그 상태와 일치시킨 것이다. 번역본 이름표는
    /// `BibleVerseCopyFormatter`가 "번역본이 1개면 안 붙인다" 규칙을 그대로
    /// 따르므로 여기서 따로 처리할 필요가 없다.
    ///
    /// [2026-08-12 2차 수정] 사용자 요청 — "2개 이상 선택시에도 하단의 버튼이
    /// 유지될 것"(말씀 요약을 여러 절 한 번에 시작할 수 있어야 함) + "[말씀
    /// 복사]는 1구절 이상 선택 시 항상 활성화." 단일 절(`Int`)만 받던 것을
    /// `Set<Int>`로 바꿨다 — `BibleVerseCopyFormatter.format`이 원래 다중 선택을
    /// 지원하므로(연속/비연속 구간 모두) 이 함수만 넓히면 된다.
    func formattedBaseTranslationText(forVerses verseNumbers: Set<Int>) -> String? {
        guard let firstColumn = columns.first, !verseNumbers.isEmpty else { return nil }
        let translation = BibleVerseCopyFormatter.TranslationSnapshot(
            displayName: firstColumn.registry.displayName, verses: firstColumn.verses
        )
        return BibleVerseCopyFormatter.format(
            book: selectedBook,
            chapter: selectedChapter,
            selectedVerses: verseNumbers,
            translations: [translation]
        )
    }

    // MARK: - 이 장의 관련 콘텐츠 새로고침 (2026-08-08 추가)

    /// 지금 보고 있는 책/장 기준으로 책 개요/장 개요/메모/연구문서를 다시
    /// 읽어온다. `selectBook`/`goToChapter`/`onAppear`가 자동으로 호출하지만,
    /// 패널에서 메모를 새로 만들거나 문서의 관련 장을 바꾼 뒤(다른 화면에서
    /// 편집한 경우)처럼 화면 밖 변경을 반영해야 할 때 호출부가 직접 부를 수도
    /// 있도록 public으로 둔다.
    func refreshRelatedContent() {
        let bookId = selectedBook.bookId
        let chapter = selectedChapter

        // [2026-08-15 변경] 미리보기 문자열(트리밍된 순수 텍스트)과 원본 RTF를
        // 같은 레코드에서 함께 뽑아내야 해서(둘 다 "가장 최근에 수정된, 내용이
        // 있는 개요" 기준), `.compactMap { ... }.first`(문자열만 남기던 방식)
        // 대신 `.first { ... }`로 레코드 자체를 먼저 고른 뒤 두 값을 함께
        // 파생시키는 방식으로 바꿨다 — `relatedBookOutlineRTF`/
        // `relatedChapterSummaryRTF` 상단 주석 참고.
        let selectedBookOutline = (try? modelContext.fetch(
            FetchDescriptor<BookOutline>(
                predicate: #Predicate { $0.bookId == bookId },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
        ))?.first { !$0.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        relatedBookOutlinePreview = selectedBookOutline.map {
            Self.makePreview($0.contentText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        relatedBookOutlineRTF = selectedBookOutline?.contentHtml

        let selectedChapterSummary = (try? modelContext.fetch(
            FetchDescriptor<ChapterSummary>(
                predicate: #Predicate { $0.bookId == bookId && $0.chapter == chapter },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
        ))?.first { !$0.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        relatedChapterSummaryPreview = selectedChapterSummary.map {
            Self.makePreview($0.contentText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        relatedChapterSummaryRTF = selectedChapterSummary?.contentHtml

        relatedChapterMemos = (try? modelContext.fetch(
            FetchDescriptor<UserMemo>(
                predicate: #Predicate { $0.bookId == bookId && $0.chapter == chapter },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
        )) ?? []

        // [2026-08-12 추가] "관련 말씀 요약" — 저널 성격을 살려 작성 순서
        // (`createdAt` 내림차순, `WordSummaryHomeView`와 같은 정렬 기준)로.
        relatedChapterWordSummaries = (try? modelContext.fetch(
            FetchDescriptor<VerseSummary>(
                predicate: #Predicate { $0.bookId == bookId && $0.chapter == chapter },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        )) ?? []

        // ⚠️ 위 relatedDocuments 프로퍼티 상단 주석 참고 — `relatedChapterRef`는
        // 전체 fetch 후 Swift 레벨에서 거른다.
        let targetRef = BibleChapterRef(bookId: bookId, chapter: chapter)
        let allDocuments = (try? modelContext.fetch(
            FetchDescriptor<SourceDocument>(sortBy: [SortDescriptor(\.uploadedAt, order: .reverse)])
        )) ?? []
        relatedDocuments = allDocuments.filter { $0.relatedChapterRef == targetRef }

        // [2026-08-08 추가] 구간 주석(형광펜/표시/관주) — 이 장 분량을 통째로
        // 불러온다(위 `chapterHighlights` 상단 주석 참고).
        chapterHighlights = (try? modelContext.fetch(
            FetchDescriptor<VerseHighlight>(
                predicate: #Predicate { $0.bookId == bookId && $0.chapter == chapter }
            )
        )) ?? []
        // [2026-08-15 변경] 사용자 요청 — "성경관련 json seed 파일은 기본 제공
        // db에 넣을 것." 관주/난외주의 "번들분"은 더 이상 SwiftData에 없다 —
        // `ReferenceDataProvider.shared.store`(ReferenceData.sqlite, 읽기 전용)에서
        // 매번 이 장 분량을 다시 읽어 사용자 생성분과 합친다. SwiftData 쪽
        // 조회는 `sourceRaw != "bundled"`로 걸러 혹시 남아 있을 수 있는 예전
        // 방식(구 CrossReferenceSeedImporter/MarginalNoteSeedImporter)의 번들
        // 레코드를 이중으로 보여주지 않는다 — 실제 정리는 `ReferenceDataMigration.
        // cleanupLegacyBundledRecords(in:)`(ContentView 부트스트랩)가 1회성으로
        // 지운다, 이 필터는 그 정리가 아직 안 끝난 짧은 틈까지 방어하는 안전망.
        let bundledSourceRaw = VerseCrossReferenceSource.bundled.rawValue
        let userCrossReferences = (try? modelContext.fetch(
            FetchDescriptor<VerseCrossReference>(
                predicate: #Predicate { $0.bookId == bookId && $0.chapter == chapter && $0.sourceRaw != bundledSourceRaw }
            )
        )) ?? []
        // [Swift 5+, SE-0230] `try?`가 이미 옵셔널인 표현식을 이중 옵셔널로
        // 감싸지 않고 그대로 평탄화하므로(`store?.crossReferences(...)`가
        // `store == nil`이면 이미 nil), 타입은 `[VerseCrossReference]?` 그대로다.
        let bundledCrossReferences = try? ReferenceDataProvider.shared.store?.crossReferences(
            bookId: bookId, chapter: chapter, translationCode: TranslationBootstrap.bundledTranslationCode
        )
        chapterCrossReferences = userCrossReferences + (bundledCrossReferences ?? [])

        chapterPhraseNotes = (try? modelContext.fetch(
            FetchDescriptor<VersePhraseNote>(
                predicate: #Predicate { $0.bookId == bookId && $0.chapter == chapter }
            )
        )) ?? []

        let userMarginalNotes = (try? modelContext.fetch(
            FetchDescriptor<VerseMarginalNote>(
                predicate: #Predicate { $0.bookId == bookId && $0.chapter == chapter && $0.sourceRaw != bundledSourceRaw }
            )
        )) ?? []
        let bundledMarginalNotes = try? ReferenceDataProvider.shared.store?.marginalNotes(
            bookId: bookId, chapter: chapter, translationCode: TranslationBootstrap.bundledTranslationCode
        )
        chapterMarginalNotes = userMarginalNotes + (bundledMarginalNotes ?? [])

        // [2026-08-15 변경] 절 단위 한자 주석은 이제 100% ReferenceData.sqlite에서만
        // 읽는다(SwiftData 경로 자체가 없어졌다 — 위 프로퍼티 선언부 주석 참고).
        chapterHanjaAnnotations = (try? ReferenceDataProvider.shared.store?.hanjaAnnotations(
            bookId: bookId, chapter: chapter
        )) ?? [:]

        // [2026-08-11 추가] "관련 내용" — 이 장 분량의 성경구절 언급 인덱스를 통째로
        // 불러온다(위 `chapterHighlights`와 같은 원칙). 인덱스 자체의 재계산은
        // `onAppear`에서만 한다(여기서는 이미 계산된 결과를 읽기만 한다) — 장을
        // 이동할 때마다(`selectBook`/`goToChapter`) 메모/문서 전체를 다시 스캔할
        // 필요는 없다.
        chapterVerseMentions = (try? modelContext.fetch(
            FetchDescriptor<VerseMention>(
                predicate: #Predicate { $0.bookId == bookId && $0.chapter == chapter }
            )
        )) ?? []
    }

    private static func makePreview(_ text: String, limit: Int = 80) -> String {
        if text.count <= limit { return text }
        return String(text.prefix(limit)) + "…"
    }

    /// [2026-08-20 수정] 사용자 요청 — "요한계시록을 제외하고 각 성경의 마지막
    /// 장에서 다음장을 클릭하면 다음 성경 1장으로 이동." 기존엔 상한 검사가
    /// 아예 없어서(`goToChapter`의 `guard`는 하한 1만 본다) 마지막 장에서
    /// 눌러도 존재하지 않는 장 번호로 그냥 넘어가 빈 화면("이 장에 표시할
    /// 절이 없습니다")이 떴다. `selectedBook.chapterCount`가 곧 그 책의
    /// 마지막 장 번호다.
    func nextChapter() {
        if selectedChapter < selectedBook.chapterCount {
            goToChapter(selectedChapter + 1)
        } else if let nextBook = booksProvider.book(after: selectedBook) {
            selectBook(nextBook, chapter: 1)
        }
        // 요한계시록 마지막 장이면 `booksProvider.book(after:)`가 nil을 돌려주므로
        // 아무 것도 하지 않는다 — 더 넘어갈 책이 없다.
    }

    /// [2026-08-20 수정] 사용자 요청 — "창세기를 제외하고 각 성경의 1장에서
    /// 이전장을 클릭하면 전 성경(이전 책) 마지막 장으로 이동." 기존엔
    /// `max(1, selectedChapter - 1)`이라 1장에서 눌러도 그냥 1장에 머물렀다.
    func previousChapter() {
        if selectedChapter > 1 {
            goToChapter(selectedChapter - 1)
        } else if let previousBook = booksProvider.book(before: selectedBook) {
            selectBook(previousBook, chapter: previousBook.chapterCount)
        }
        // 창세기 1장이면 `booksProvider.book(before:)`가 nil을 돌려주므로
        // 아무 것도 하지 않는다.
    }

    // MARK: - 브라우저 스타일 뒤로/앞으로 탐색 (2026-08-20 추가)
    //
    // 사용자 요청 — "이전 장 이동하는 화살표 옆에 이전에 찾아봤던 장 바로가기
    // 아이콘 추가(history.back). 다음 장 이동하는 화살표 옆에 앞에서 온 성경
    // 장을 바로가는 아이콘 추가(history.forward())." 바로 위 `previousChapter`/
    // `nextChapter`(항상 인접한 장 ±1로만 이동)와는 완전히 다른 개념이다 — 이건
    // 브라우저처럼 사용자가 실제로 거쳐온 임의의 책/장 순서(책 피커 선택, 검색
    // 결과 클릭, 관주 이동, 조회 이력 항목 클릭 등 `selectBook`/`goToChapter`를
    // 타는 모든 경로)를 그대로 되짚어 간다.
    //
    // 기존 `BibleReadingHistoryService`/`fetchHistory()`(위)는 SwiftData에 영구
    // 저장되는 "방문 기록 목록"이고 되돌아가기/다시가기 포인터 개념이 없다 —
    // 이 스택은 그와 별개로 이 뷰모델 인스턴스(=이 창) 안에서만 살아있는
    // 순수 인메모리 상태다.

    private struct ChapterLocation: Equatable {
        let bookId: Int
        let chapter: Int
    }

    private var backStack: [ChapterLocation] = []
    private var forwardStack: [ChapterLocation] = []

    var canGoBackInHistory: Bool { !backStack.isEmpty }
    var canGoForwardInHistory: Bool { !forwardStack.isEmpty }

    private var currentLocation: ChapterLocation {
        ChapterLocation(bookId: selectedBook.bookId, chapter: selectedChapter)
    }

    /// `selectBook`/`goToChapter`가 실제 이동 직전에 호출한다 — "지금 있던
    /// 자리"를 뒤로가기 스택에 쌓고, 새로 이동하는 순간 "앞으로" 갈 곳은
    /// 무의미해지므로 앞으로가기 스택을 비운다(브라우저의 표준 동작과 동일 —
    /// 뒤로 갔다가 새 링크를 클릭하면 그 이전의 "앞으로" 기록이 사라지는 것과
    /// 같다). `goBackInHistory`/`goForwardInHistory`는 이 메서드를 거치지 않고
    /// `selectedBook`/`selectedChapter`를 직접 대입하므로(아래) 뒤로/앞으로
    /// 이동 자체가 다시 스택에 쌓이는 일은 없다.
    private func pushCurrentLocationToBackStack() {
        backStack.append(currentLocation)
        forwardStack.removeAll()
    }

    /// 스택에서 꺼낸 위치로 이동한다 — `pushCurrentLocationToBackStack`을 타지
    /// 않는다는 점만 빼면 `selectBook`과 같은 부수효과(재조회/관련내용
    /// 새로고침/최근 위치·조회 이력 기록)를 그대로 수행한다.
    private func navigate(toHistory location: ChapterLocation) {
        guard let book = booksProvider.book(id: location.bookId) else { return }
        selectedBook = book
        selectedChapter = max(1, location.chapter)
        clearVerseSelection()
        reloadVerses()
        refreshRelatedContent()
        LastBiblePositionTracker.shared.update(bookId: book.bookId, chapter: selectedChapter)
        BibleReadingHistoryService.record(bookId: book.bookId, chapter: selectedChapter, context: modelContext)
    }

    func goBackInHistory() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(currentLocation)
        navigate(toHistory: previous)
    }

    func goForwardInHistory() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(currentLocation)
        navigate(toHistory: next)
    }

    /// 번역본 선택 팝오버에서 호출 — 표시 목록을 교체한다(최대 maxColumns개까지만 유지).
    func setDisplayedTranslations(_ ids: [PersistentIdentifier]) {
        displayedTranslationIDs = Array(ids.prefix(maxColumns))
        reloadVerses()
    }

    // 2026-08-06: 책의 장 개수는 더 이상 여기서 BibleReferenceStore에 쿼리하지 않는다.
    // `Book.chapterCount`(books.json 정적 데이터, KoreanUtil.swift 이식분 — README
    // 참고)를 BookChapterPicker가 직접 쓴다. `BibleReferenceStore.maxChapter(bookId:)`는
    // 패키지에 남아 있으니, 이후 정적 데이터와 실제 파일 내용이 어긋나는지 교차
    // 검증하고 싶을 때 재사용할 수 있다.

    private func reloadVerses() {
        let displayed = availableTranslations.filter { displayedTranslationIDs.contains($0.persistentModelID) }
        columns = displayed.map { registry in
            let columnID = columnIDsByRegistry[registry.persistentModelID] ?? {
                let newID = UUID()
                columnIDsByRegistry[registry.persistentModelID] = newID
                return newID
            }()
            var state = ColumnState(id: columnID, registry: registry)
            state.localizedBookChapterLabel = BookNameTableProvider.shared.displayName(
                forBookId: selectedBook.bookId,
                bookNameTableID: registry.bookNameTableID
            ) + " \(selectedChapter)"
            do {
                let store = try store(for: registry)
                // 번들 파일(version_code 컬럼 없음)과 사용자 추가 파일(있을 수 있음)을
                // 구분하지 않고 그냥 연다 — BibleReferenceStore가 PRAGMA table_info로
                // 스스로 판단한다(BibleReferenceStore.swift 참고). 컬럼이 있는 파일인데
                // registry.code가 실제 version_code 표기와 일치하지 않으면(대소문자/표기
                // 차이 가능성, BibleReferenceModels.swift의 ⚠️ 참고) 결과가 비어 보일 수
                // 있다 — 아직 실제 다중 번역본 파일로 검증하지 못했다.
                let versionCode = store.hasVersionCodeColumn ? registry.code : nil
                state.verses = try store.verses(bookId: selectedBook.bookId, chapter: selectedChapter, versionCode: versionCode)
            } catch {
                state.errorDescription = error.localizedDescription
            }
            return state
        }
    }

    private func store(for registry: TranslationRegistry) throws -> BibleReferenceStore {
        // 2026-08-07(S12): 사용자 추가 번역본은 더 이상 registry.sqliteFileReference를
        // 곧바로 믿지 않는다 — 다른 기기에서 CloudKit으로 막 동기화된 레코드는 이
        // 필드가 이 기기에 없는 경로를 가리킬 수 있다(sqliteData만 도착한 상태).
        // TranslationFileMaterializer가 필요하면 로컬로 다시 써내고 필드를
        // 갱신한다 — TranslationFileMaterializer.swift 상단 주석 참고.
        // [2026-08-14 수정] 번들 번역본이 KRV 하나뿐일 때는 무조건 같은 파일을
        // 열어도 됐지만, 국한문 번들 번역본이 추가되면서 `registry.code`로
        // 어느 번들 파일인지 반드시 구분해야 한다 — `resolvedBundledDatabaseURL()`
        // (인자 없음, KRV 고정)를 그대로 쓰면 국한문 열도 항상 KRV 내용이
        // 뜨는 회귀가 생긴다.
        let path = registry.isBundled
            ? try TranslationBootstrap.resolvedBundledDatabaseURL(for: registry.code).path
            : try TranslationFileMaterializer.ensureMaterialized(registry, context: modelContext)
        if let cached = storeCache[path] { return cached }
        let store = try BibleReferenceStore(filePath: path)
        storeCache[path] = store
        return store
    }
}
