//
//  BibleReadingViewModel.swift
//  JBCHBibleResearch
//
//  S1(성경 조회) 화면의 상태와 데이터 접근을 담당한다. 등록된 각 번역본(TranslationRegistry)에
//  대해 BibleReferenceStore를 열어 두고, 선택된 책/장이 바뀔 때마다 새로 조회한다.
//  형광펜/구간 메모/관주/난외주/한자 주석/관련 문서는 장 단위로 한 번에 불러와 두고,
//  절 렌더링 시점에는 메모리 인덱스로만 조회한다.
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
        /// 이 번역본 자신의 언어로 표시하는 "책 장" 레이블(예: "John 3"). registry.bookNameTableID가
        /// nil이거나 해당 이름표를 못 찾으면 한글 기본 이름으로 폴백된다.
        var localizedBookChapterLabel: String = ""
    }

    private(set) var selectedBook: Book
    private(set) var selectedChapter: Int
    private(set) var availableTranslations: [TranslationRegistry] = []
    /// 지금 화면에 나란히 표시 중인 번역본(최대 3개). iPhone은 화면 레이어에서 이 중 첫 번째만
    /// 골라 1열로 보여준다.
    private(set) var displayedTranslationIDs: [PersistentIdentifier] = []
    private(set) var columns: [ColumnState] = []
    var lastErrorDescription: String?

    /// 클립보드 복사용 다중 선택 — 절 번호 기준이며 모든 컬럼이 공유한다. 장을 이동하면 이전 장의
    /// 절 번호는 의미가 없으므로 `selectBook`/`goToChapter`에서 비운다.
    private(set) var selectedVerses: Set<Int> = []
    var hasVerseSelection: Bool { !selectedVerses.isEmpty }

    /// 검색 결과 등에서 이동해 온 절의 임시 강조 상태. 실제 스크롤/강조는
    /// `TranslationColumnView.highlightedVerse`가 맡고, 이 뷰모델은 강조 대상 절과 자동 해제 타이머만 관리한다.
    private(set) var highlightedVerse: Int?
    private var highlightClearWorkItem: DispatchWorkItem?
    private static let highlightDuration: TimeInterval = 2.5

    /// 이 절을 몇 초간만 강조 표시한다. 이미 진행 중인 타이머가 있으면 취소하고 새로 시작한다.
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
    // ⚠️ BookOutline/ChapterSummary는 S8/S9의 find-or-create(BookOutlineDeduplication/
    // ChapterSummaryDeduplication)를 쓰지 않고 읽기 전용 fetch만 한다 — 방문만으로 빈 개요
    // 레코드가 생기는 부작용을 피하기 위함이다. 내용이 비어 있으면 "없음"으로 취급한다.
    private(set) var relatedBookOutlinePreview: String?
    private(set) var relatedChapterSummaryPreview: String?
    /// 개요/장 요약의 `contentHtml`(실제로는 RTF)을 서식 그대로 담는다 — `ChapterRelatedContentPanel`이
    /// `RichTextEditor(isEditable: false)`로 재현한다. 위 Preview는 "개요가 있는지" 판단용 트리밍 텍스트다.
    private(set) var relatedBookOutlineRTF: String?
    private(set) var relatedChapterSummaryRTF: String?
    private(set) var relatedChapterMemos: [UserMemo] = []
    /// `phraseMemos`가 VerseRow 재생성(스크롤 prefetch 포함)마다 장 전체 배열을 훑지 않도록 절 번호로
    /// 인덱싱한다. 번역본 조건은 절 번호 키로 표현할 수 없어 `phraseMemos`가 직접 거른다.
    /// `UserMemo.verse`가 옵셔널이라 없는 경우는 조회되지 않는 -1 키로 몰아 둔다.
    private var relatedChapterMemosIndex: [Int: [UserMemo]] = [:]
    private func rebuildRelatedChapterMemosIndex() {
        relatedChapterMemosIndex = Dictionary(grouping: relatedChapterMemos) { $0.verse ?? -1 }
    }
    /// 이 장 안의 `VerseSummary` 전부 — 저널 성격이라 한 절에 여러 개가 쌓일 수 있다
    /// (`relatedChapterMemos`와 같은 원칙).
    private(set) var relatedChapterWordSummaries: [VerseSummary] = []
    /// ⚠️ `SourceDocument.relatedChapterRef`는 Codable 구조체 옵셔널이라 `#Predicate` 필터링을 신뢰할 수
    /// 없어, 전체 fetch 후 Swift 레벨에서 거른다. 문서가 아주 많아지면 장 이동마다 전체 스캔이 느려질 수 있다.
    private(set) var relatedDocuments: [SourceDocument] = []
    /// 이 장의 `SermonVerseReference` — 절 단위 좌표를 직접 들고 있어, 장 전체를 한 번 불러 두고
    /// 절별로는 Swift 레벨에서 거른다(`sermonVerseReferences(verse:)`).
    private(set) var relatedChapterSermonVerseReferences: [SermonVerseReference] = []

    // MARK: - 구간 주석(형광펜/표시/관주) — 2026-08-08 신설
    //
    // 지금 보고 있는 장 전체를 한 번에 불러와 두고, 절 렌더링 시점에는 메모리 필터링만 한다.
    private(set) var chapterHighlights: [VerseHighlight] = []
    /// "(번역본코드|절번호) → 형광펜 목록" 인덱스 — 스크롤로 VerseRow가 다시 그려질 때마다 장 전체를
    /// 훑지 않기 위함이다. `chapterHighlights`를 바꾸는 각 지점에서 `rebuildHighlightsIndex()`를
    /// 명시적으로 호출한다(`@Observable`이 `private(set)` + `didSet` + 초기값 조합을 계산 프로퍼티로
    /// 취급해 `didSet` 자동화는 컴파일 에러가 난다).
    private var chapterHighlightsIndex: [String: [VerseHighlight]] = [:]
    private func rebuildHighlightsIndex() {
        chapterHighlightsIndex = Dictionary(grouping: chapterHighlights) { "\($0.translationCode)|\($0.verse)" }
    }
    /// 사용자 관주(SwiftData, `source == .user`)와 `ReferenceData.sqlite`의 번들 관주
    /// (`source == .bundled`, insert하지 않은 인메모리 인스턴스)를 함께 담는다. 절 번호로만 거르므로
    /// `crossReferences(translationCode:verse:)`는 출처를 구분할 필요가 없다.
    private(set) var chapterCrossReferences: [VerseCrossReference] = []
    /// `chapterHighlightsIndex`와 같은 이유·방식(명시적 호출)으로 유지한다.
    private var chapterCrossReferencesIndex: [String: [VerseCrossReference]] = [:]
    private func rebuildCrossReferencesIndex() {
        chapterCrossReferencesIndex = Dictionary(grouping: chapterCrossReferences) { "\($0.translationCode)|\($0.verse)" }
    }
    /// 드래그한 특정 표현에 붙이는 짧은 "메모" — `chapterHighlights`와 같은 원칙.
    private(set) var chapterPhraseNotes: [VersePhraseNote] = []
    /// `chapterHighlightsIndex`와 같은 이유·방식(명시적 호출)으로 유지한다.
    private var chapterPhraseNotesIndex: [String: [VersePhraseNote]] = [:]
    private func rebuildPhraseNotesIndex() {
        chapterPhraseNotesIndex = Dictionary(grouping: chapterPhraseNotes) { "\($0.translationCode)|\($0.verse)" }
    }
    /// 난외주 — `chapterCrossReferences`와 같이 사용자 생성분(현재 편집 UI가 없어 항상 비어 있음)과
    /// 번들분(`ReferenceData.sqlite`, 인메모리 인스턴스)을 함께 담는다.
    private(set) var chapterMarginalNotes: [VerseMarginalNote] = []
    /// `chapterHighlightsIndex`와 같은 이유·방식. 현재 이 배열을 바꾸는 곳은 장 로드(전체 재대입) 한 곳뿐이다.
    private var chapterMarginalNotesIndex: [String: [VerseMarginalNote]] = [:]
    private func rebuildMarginalNotesIndex() {
        chapterMarginalNotesIndex = Dictionary(grouping: chapterMarginalNotes) { "\($0.translationCode)|\($0.verse)" }
    }
    /// 절 단위 한자 주석 — 100% 번들 전용이라 SwiftData를 거치지 않고,
    /// `ReferenceDataStore.hanjaAnnotations(bookId:chapter:)`가 돌려준 절 번호별 딕셔너리를 그대로 들고 있는다.
    private(set) var chapterHanjaAnnotations: [Int: [HanjaWordAnnotation]] = [:]

    // MARK: - 왼쪽 기본 성경 칸 한자/난외주 인라인 렌더링 캐시 — 2026-09-02 신설
    //
    // `VerseAnnotationRenderer.attributedContentWithInlineAnnotations`로 절마다 `AttributedString`을
    // 다시 만드는 비용을 줄이는 렌더링 캐시.
    //
    // ⚠️ 위 인덱스들과 달리 아래 정책을 반드시 유지할 것:
    //   1. 장이 바뀌어도 비우지 않고 세션 동안 유지한다 — 성경 전체를 캐싱해도 최대 15~60MB
    //      수준으로 추정돼 장 단위로 비울 이유가 없다.
    //   2. 디스크(SwiftData)에는 저장하지 않는다 — 재료가 번들 SQLite에 있어 재계산이 싸고,
    //      직렬화 비용이 더 클 수 있으며, 렌더링 캐시를 CloudKit 동기화 대상에 넣을 이유도 없다.
    //   3. 키에 `bookId`/`chapter`가 반드시 들어간다 — 이 캐시는 여러 장에 걸쳐 남으므로
    //      절 번호만 쓰면 다른 장의 같은 절 번호끼리 충돌한다.
    private struct InlineAnnotationCacheKey: Hashable {
        let bookId: Int
        let chapter: Int
        let translationCode: String
        let verse: Int
        /// 한자 "탭하면 보기" 모드에서는 같은 절이 선택 여부에 따라 `hanjaWords`가 빈 배열/실제 목록으로
        /// 달리 호출된다. 이를 키에 포함하지 않으면 선택 전에 캐시된 한자 없는 결과가 선택 후에도
        /// 반환된다.
        let includeHanja: Bool
    }
    private var inlineAnnotationCache: [InlineAnnotationCacheKey: AttributedString] = [:]
    /// 마지막으로 캐시를 채울 때 쓴 폰트/글자색/한자폰트 — 이 값이 바뀌면(설정 화면 모양 탭)
    /// 캐시 전체를 한 번에 비운다.
    private var inlineAnnotationCacheFont: PlatformFont?
    private var inlineAnnotationCacheTextColor: PlatformColor?
    private var inlineAnnotationCacheHanjaFont: PlatformFont?

    /// `TranslationColumnView.VerseRow.verseContentText`가 호출 — 캐시에 있으면 그대로 돌려주고,
    /// 없거나 폰트/색이 바뀌었으면 새로 계산해 캐시한 뒤 돌려준다.
    func cachedInlineAnnotatedContent(
        bookId: Int, chapter: Int, translationCode: String, verse: Int,
        text: String, highlights: [VerseHighlight], phraseNotes: [VersePhraseNote],
        hanjaWords: [HanjaWordAnnotation], marginalNotes: [VerseMarginalNote],
        font: PlatformFont, textColor: PlatformColor, hanjaFont: PlatformFont?
    ) -> AttributedString {
        if inlineAnnotationCacheFont != font || inlineAnnotationCacheTextColor != textColor
            || inlineAnnotationCacheHanjaFont != hanjaFont {
            inlineAnnotationCache.removeAll()
            inlineAnnotationCacheFont = font
            inlineAnnotationCacheTextColor = textColor
            inlineAnnotationCacheHanjaFont = hanjaFont
        }
        let key = InlineAnnotationCacheKey(
            bookId: bookId, chapter: chapter, translationCode: translationCode, verse: verse,
            includeHanja: !hanjaWords.isEmpty
        )
        if let cached = inlineAnnotationCache[key] { return cached }
        let attributed = VerseAnnotationRenderer.attributedContentWithInlineAnnotations(
            text: text, highlights: highlights, phraseNotes: phraseNotes,
            hanjaWords: hanjaWords, marginalNotes: marginalNotes, font: font, textColor: textColor, hanjaFont: hanjaFont
        )
        inlineAnnotationCache[key] = attributed
        return attributed
    }

    /// 형광펜/구간메모가 바뀔 때 그 절 하나만 캐시에서 지운다. 호출하는 함수들은 모두 현재 보고 있는
    /// 장에서만 쓰이므로 `selectedBook`/`selectedChapter`를 그대로 쓴다.
    private func invalidateInlineAnnotationCache(translationCode: String, verse: Int) {
        // 같은 절이 `includeHanja` true/false 두 항목으로 캐시될 수 있어 둘 다 지운다.
        for includeHanja in [true, false] {
            let key = InlineAnnotationCacheKey(
                bookId: selectedBook.bookId, chapter: selectedChapter, translationCode: translationCode,
                verse: verse, includeHanja: includeHanja
            )
            inlineAnnotationCache.removeValue(forKey: key)
        }
    }

    // MARK: - 메모/연구문서 안의 성경구절 언급("관련 내용") — 2026-08-11 신설
    //
    // `chapterHighlights`와 같은 원칙 — 장 전체를 한 번에 불러와 두고 절 렌더링 시점엔 메모리
    // 필터링만 한다(인덱스 재계산은 `BibleReferenceIndexingService`가 담당).
    private(set) var chapterVerseMentions: [VerseMention] = []
    /// `relatedChapterMemosIndex`와 같은 이유·방식(스크롤 prefetch마다의 선형 탐색 방지).
    /// `VerseMention.verse`가 옵셔널이라 없는 경우는 조회되지 않는 -1 키로 몰아 둔다.
    private var chapterVerseMentionsIndex: [Int: [VerseMention]] = [:]
    private func rebuildVerseMentionsIndex() {
        chapterVerseMentionsIndex = Dictionary(grouping: chapterVerseMentions) { $0.verse ?? -1 }
    }

    /// `TranslationColumnView.VerseRow`가 호출 — 이 번역본·이 절에 걸린 형광펜/표시만
    /// 골라 낸다.
    func highlights(translationCode: String, verse: Int) -> [VerseHighlight] {
        chapterHighlightsIndex["\(translationCode)|\(verse)"] ?? []
    }

    func crossReferences(translationCode: String, verse: Int) -> [VerseCrossReference] {
        chapterCrossReferencesIndex["\(translationCode)|\(verse)"] ?? []
    }

    /// `TranslationColumnView.VerseRow`가 호출 — 이 번역본·이 절에 걸린 난외주만
    /// 골라 낸다. 위 `crossReferences(translationCode:verse:)`와 같은 원칙.
    func marginalNotes(translationCode: String, verse: Int) -> [VerseMarginalNote] {
        chapterMarginalNotesIndex["\(translationCode)|\(verse)"] ?? []
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
        chapterPhraseNotesIndex["\(translationCode)|\(verse)"] ?? []
    }

    /// 이 절을 정확히 언급하는 메모/연구문서 — 번역본과 무관하다. ⚠️ 절 번호 없이 장만 가리키는
    /// 언급(`verse == nil`)은 그 장의 모든 절 아이콘에 똑같이 나타나 신호가 흐려지므로 제외한다.
    func verseMentions(verse: Int) -> [VerseMention] {
        chapterVerseMentionsIndex[verse] ?? []
    }

    /// `relatedChapterSermonVerseReferences` 중 이 절(verseStart...verseEnd 범위에 포함)만 걸러 돌려준다 —
    /// 이미 불러온 배열만 필터링하므로 절을 옮길 때마다 다시 fetch하지 않는다.
    func sermonVerseReferences(verse: Int) -> [SermonVerseReference] {
        relatedChapterSermonVerseReferences.filter { ref in
            verse >= ref.verseStart && verse <= (ref.verseEnd ?? ref.verseStart)
        }
    }

    /// `VerseMention.sourceId`(UUID 문자열)로 실제 `UserMemo`를 되찾는다 — `EmbeddingChunk`와 같은
    /// 이유로 `VerseMention`은 관계가 아니라 원시 문자열 ID로만 출처를 가리킨다.
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

    /// 위 `resolveMemo(for:)`와 같은 이유 — 말씀 요약 쪽.
    func resolveWordSummary(for mention: VerseMention) -> VerseSummary? {
        guard mention.sourceType == .wordSummary, let uuid = UUID(uuidString: mention.sourceId) else { return nil }
        return (try? modelContext.fetch(
            FetchDescriptor<VerseSummary>(predicate: #Predicate { $0.id == uuid })
        ))?.first
    }

    /// 위 `resolveMemo(for:)`와 같은 이유 — "내 설교"(`.sermon`, 본문 자동 추출) 쪽. 이 mention은
    /// `Sermon.id`로만 출처를 가리키며, `SermonDelivery`는 자동 추출 범위 밖이다(메인 설교문만 대상).
    func resolveSermon(for mention: VerseMention) -> Sermon? {
        guard mention.sourceType == .sermon, let uuid = UUID(uuidString: mention.sourceId) else { return nil }
        return (try? modelContext.fetch(
            FetchDescriptor<Sermon>(predicate: #Predicate { $0.id == uuid })
        ))?.first
    }

    /// 이 번역본·이 절에 보여줄 메모 아이콘 대상. `relatedChapterMemos`를 다시 쿼리하지 않고 필터링만 한다.
    ///
    /// 구간 메모(`rangeStart != nil`)는 특정 번역본의 특정 표현에 종속되므로 그 번역본 컬럼에서만,
    /// 절 전체 메모(`rangeStart == nil`)는 번역본과 무관하게 그 절을 보여주는 모든 컬럼에 노출한다.
    func phraseMemos(translationCode: String, verse: Int) -> [UserMemo] {
        (relatedChapterMemosIndex[verse] ?? []).filter { memo in
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
        rebuildHighlightsIndex()
        invalidateInlineAnnotationCache(translationCode: translationCode, verse: verse)
    }

    func deleteHighlight(_ highlight: VerseHighlight) {
        modelContext.delete(highlight)
        try? modelContext.save()
        chapterHighlights.removeAll { $0.id == highlight.id }
        rebuildHighlightsIndex()
        invalidateInlineAnnotationCache(translationCode: highlight.translationCode, verse: highlight.verse)
    }

    // MARK: - "메모"(신규, 드래그 표현 부연설명) — 2026-08-11 신설

    /// "확대보기"에서 표현을 드래그하고 새 "메모" 버튼을 눌렀을 때 호출.
    func addPhraseNote(
        translationCode: String, verse: Int, range: NSRange, anchorText: String, noteText: String
    ) {
        // 메모 배경색은 처음 만들 때 한 번만 무작위로 골라 `colorTagRaw`에 저장한다 — 이후 화면
        // (`PhraseNoteBoxView`)은 저장된 값을 읽기만 하므로 다시 열어도 같은 색이다.
        let colorTag = HighlightColorTag.allCases.randomElement() ?? .yellow
        let note = VersePhraseNote(
            translationCode: translationCode, bookId: selectedBook.bookId, chapter: selectedChapter,
            verse: verse, rangeStart: range.location, rangeEnd: range.location + range.length,
            anchorText: anchorText, noteText: noteText, colorTagRaw: colorTag.rawValue
        )
        modelContext.insert(note)
        try? modelContext.save()
        // 확대보기 메모는 디바운스 없이 항상 즉시 저장하므로, 지연 신호 없이 여기서 바로 FTS 보조
        // 인덱스도 최신화한다.
        UserContentSearchIndexLocation.upsert(
            category: .phraseNote, sourceId: note.id.uuidString, content: note.noteText
        )
        chapterPhraseNotes.append(note)
        rebuildPhraseNotesIndex()
        invalidateInlineAnnotationCache(translationCode: translationCode, verse: verse)
    }

    /// 우클릭(macOS)/편집 메뉴(iOS)의 "메모 수정" 또는 편집 팝오버 저장 버튼에서 호출.
    func updatePhraseNote(_ note: VersePhraseNote, noteText: String) {
        note.noteText = noteText
        note.updatedAt = .now
        try? modelContext.save()
        // 수정 시에도 즉시 FTS 보조 인덱스를 최신화한다.
        UserContentSearchIndexLocation.upsert(
            category: .phraseNote, sourceId: note.id.uuidString, content: note.noteText
        )
    }

    func deletePhraseNote(_ note: VersePhraseNote) {
        modelContext.delete(note)
        try? modelContext.save()
        // FTS 보조 인덱스에 남은 항목도 함께 지운다(정확성엔 영향 없지만 죽은 행 누적을 막는다).
        UserContentSearchIndexLocation.delete(category: .phraseNote, sourceId: note.id.uuidString)
        chapterPhraseNotes.removeAll { $0.id == note.id }
        rebuildPhraseNotesIndex()
        invalidateInlineAnnotationCache(translationCode: note.translationCode, verse: note.verse)
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
        rebuildCrossReferencesIndex()
    }

    func deleteCrossReference(_ reference: VerseCrossReference) {
        modelContext.delete(reference)
        try? modelContext.save()
        chapterCrossReferences.removeAll { $0.id == reference.id }
        rebuildCrossReferencesIndex()
    }

    /// `VerseCrossReference` 한 개가 대상을 여러 개(`targets`) 가질 수 있어, 그중 하나만 지울 때는
    /// 배열에서 그 항목만 뺀다. 마지막 하나였다면 레코드 자체를 `deleteCrossReference`로 지운다.
    func removeCrossReferenceTarget(_ target: BibleVerseRef, from reference: VerseCrossReference) {
        var updated = reference.targets
        updated.removeAll { $0 == target }
        if updated.isEmpty {
            deleteCrossReference(reference)
        } else {
            reference.targets = updated
            // 사이드바 "최근" 목록이 이 시각을 정렬 기준으로 쓰므로(`SidebarQuickItem.sortDate`)
            // 대상 하나를 지우는 것도 수정으로 보고 갱신한다.
            reference.updatedAt = .now
            try? modelContext.save()
        }
    }

    /// 관주 팝오버가 `VerseCrossReference.groupedEntries` 항목 단위로 보여주므로 지우는 단위도 그
    /// 항목 전체(여러 절 포함 가능)다. `removeCrossReferenceTarget`(절 하나만 지움)은 정합 정보가
    /// 없는 레거시 데이터를 절 단위로 대체 표시할 때를 위해 남겨 둔다.
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
            // `removeCrossReferenceTarget`과 같은 이유.
            reference.updatedAt = .now
            try? modelContext.save()
        }
    }

    /// 개인 묵상 등록 — 한 구절에 여러 개가 등록될 수 있어 매번 새 `UserMemo`를 만든다
    /// (`rangeStart == nil`이면 절 전체 메모라는 규칙은 그대로, `phraseMemos` 필터와 호환). 수정·자동저장을
    /// 지원하지 않으므로 빈 메모를 미리 만들지 않고, 화면의 입력 초안(`VerseZoomView.newPersonalNoteText`)을
    /// "등록" 시점에 완성된 내용으로 한 번만 저장한다.
    func createPersonalNote(verse: Int, contentText: String) {
        let memo = UserMemo(
            bookId: selectedBook.bookId, chapter: selectedChapter, verse: verse,
            contentHtml: contentText, contentText: contentText
        )
        modelContext.insert(memo)
        try? modelContext.save()
        relatedChapterMemos.insert(memo, at: 0)
        rebuildRelatedChapterMemosIndex()
        BibleReferenceIndexingService.reindexMemo(memo, context: modelContext)
    }

    /// 개인 묵상 삭제 — `WordNoteHomeView.delete(_:)`와 같은 순서(관련 내용 인덱스 제거 → 모델 삭제 →
    /// 저장 → 메모리 배열에서 제거)를 따른다.
    func deletePersonalNote(_ memo: UserMemo) {
        BibleReferenceIndexingService.removeMentions(
            sourceType: .memo, sourceId: memo.id.uuidString, context: modelContext
        )
        modelContext.delete(memo)
        try? modelContext.save()
        relatedChapterMemos.removeAll { $0.id == memo.id }
        rebuildRelatedChapterMemosIndex()
    }

    /// 이 장 전체에 대한 개인 묵상 — `verse == nil`(장 단위 좌표)인 빈 `UserMemo`를 만들어 돌려준다. 호출부가 메모 편집기로 열고,
    /// 내용 없이 닫히면 편집기(`MemoDetailView`)가 빈 메모를 스스로 지운다(`createPhraseMemo`와 같은 흐름).
    func createChapterMemo() -> UserMemo {
        let memo = UserMemo(bookId: selectedBook.bookId, chapter: selectedChapter)
        modelContext.insert(memo)
        try? modelContext.save()
        relatedChapterMemos.insert(memo, at: 0)
        rebuildRelatedChapterMemosIndex()
        BibleReferenceIndexingService.reindexMemo(memo, context: modelContext)
        return memo
    }

    /// 이 장 단위(절·구간에 달리지 않은) 개인 묵상, 최근 수정순. 내용이 비어 있는 것은 뺀다.
    var chapterLevelMemos: [UserMemo] {
        relatedChapterMemos.filter {
            $0.verse == nil && $0.rangeStart == nil
                && !$0.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
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
        rebuildRelatedChapterMemosIndex()
        // 새로 만든 메모도 이벤트 기반 인덱싱 대상 — 이 시점엔 보통 본문이 비어 있어 no-op이지만
        // 다른 저장 경로와 일관되게 항상 호출한다.
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

    // `booksProvider: BooksProvider = .shared`처럼 기본 인자에서 MainActor 격리 정적 프로퍼티를 참조하면
    // Swift 6 엄격 동시성에서 오류가 난다(기본 인자 표현식은 nonisolated 컨텍스트에서 평가됨).
    // 그래서 옵셔널로 받고 본문(MainActor 컨텍스트)에서 `?? .shared`로 대체한다.
    // `initialBook`이 명시된 호출(검색 결과 탭 등)은 사용자의 명확한 의도이므로 마지막 위치를 무시하고
    // 그대로 연다. nil인 일반 진입만 `LastBiblePositionTracker`(메모리 전용, 앱 재시작 시 사라짐)로
    // 복원하고, 없으면 첫 번째 책 1장을 쓴다.
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
        // 진입할 때마다 전체 재스캔하지 않는다 — 관련 내용 인덱스 최신화는 각 메모/문서 저장·삭제
        // 지점에서 개별적으로 책임진다(`BibleReferenceIndexingService.swift` 참고).
        purgeLegacyMarkHighlights()
        // 번역본 로딩과 무관한 가벼운 자가 치유 작업.
        resetLegacyCrossReferenceUpdatedAtIfNeeded()
        loadAvailableTranslations()
        // `availableTranslations`가 채워진 뒤여야 "기본 번역본"을 고를 수 있고, `refreshRelatedContent()`가
        // 부르는 `rebuildBookmarkedVersesIndex()`가 마이그레이션된 데이터를 보도록 그보다 먼저 실행한다.
        migrateLegacyBookmarksIfNeeded()
        refreshRelatedContent()
    }

    /// 제거된 "표시"(수동 밑줄, `.mark`) 형광펜 레코드를 정리한다. 화면 진입 때마다 조회하지만 정리 후엔
    /// 0건이라 저비용이다 — 일회성 플래그 대신 매번 확인하는 이유는 CloudKit 동기화로 다른 기기의
    /// 예전 데이터가 나중에 다시 들어오는 경우까지 자가 치유하기 위함이다.
    private func purgeLegacyMarkHighlights() {
        let markRaw = VerseHighlightStyle.mark.rawValue
        let descriptor = FetchDescriptor<VerseHighlight>(predicate: #Predicate { $0.styleRaw == markRaw })
        guard let legacy = try? modelContext.fetch(descriptor), !legacy.isEmpty else { return }
        for highlight in legacy { modelContext.delete(highlight) }
        try? modelContext.save()
        // 메모리에 캐시된 장(`chapterHighlights`)에도 섞여 있을 수 있어 함께 제거한다.
        chapterHighlights.removeAll { $0.styleRaw == markRaw }
        rebuildHighlightsIndex()
        // 여러 장(다른 책 포함)에 흩어진 레코드를 한꺼번에 지우는 정리라 절 하나로 좁히기 어려워
        // 캐시 전체를 비운다.
        inlineAnnotationCache.removeAll()
    }

    /// `VerseCrossReference.updatedAt`을 나중에 추가했을 때 SwiftData 경량 마이그레이션이 기존 관주에
    /// "마이그레이션이 실행된 시각"을 일괄로 채워, 사이드바 "최근" 목록에서 실제 생성일과 무관하게
    /// 그 하루에 고정돼 보였다. 관주는 부분 수정 대신 통째로 지우고 다시 만드는 방식으로 쓰이므로
    /// 저장돼 있는 `updatedAt`은 모두 오염된 값으로 보고 앱 진입 시마다 `nil`로 되돌린다
    /// (`SidebarQuickItem.sortDate`의 `updatedAt ?? createdAt` 폴백이 생성일을 보여준다).
    /// 이후 실제 대상 삭제 편집(`removeCrossReferenceTarget`/`removeCrossReferenceGroup`)이 일어나면
    /// 그때 다시 채워지므로 진짜 편집 이력까지 지우지는 않는다.
    private func resetLegacyCrossReferenceUpdatedAtIfNeeded() {
        let descriptor = FetchDescriptor<VerseCrossReference>(predicate: #Predicate { $0.updatedAt != nil })
        guard let contaminated = try? modelContext.fetch(descriptor), !contaminated.isEmpty else { return }
        for reference in contaminated {
            reference.updatedAt = nil
        }
        try? modelContext.save()
    }

    /// 번역본 목록(`availableTranslations`)과 표시 중인 열(`displayedTranslationIDs`)을 SwiftData의 현재 상태에 맞춘다.
    /// 화면 진입 때뿐 아니라 설정에서 번역본을 켜고 끄거나 다른 기기의 변경이 CloudKit으로 도착할 때도 호출된다
    /// (`BibleReadingContentView`가 `TranslationRegistry` 변화를 감지해 부른다).
    ///
    /// 후보는 항상 "활성(`isEnabled`)" 번역본뿐이다. 예전에는 최초 선택·정리 단계가 비활성 번역본까지 포함한 전체(`all`)를
    /// 기준으로 해서, 한 기기에서 끈 번역본이 다른 기기에서 계속 열로 뜨고 — 그 기기에 파일이 아직 없으면
    /// "이 번역본의 파일이 아직 이 기기에 없습니다" 오류 열만 남아 빈 화면이 됐다.
    func loadAvailableTranslations() {
        let descriptor = FetchDescriptor<TranslationRegistry>(sortBy: [SortDescriptor(\.addedAt, order: .forward)])
        do {
            let all = try modelContext.fetch(descriptor)
            let enabled = all.filter(\.isEnabled)
            // 팝오버(`TranslationPickerPopover`)의 후보 전체다(`TranslationRegistry.isEnabled` 참고).
            availableTranslations = enabled

            // "성경 조회 기본 표시" 목록(`defaultDisplayedTranslationCodes`)은 UserDefaults라 기기별이다. 다른 기기에서 끈
            // 번역본의 코드가 이 기기 목록에 남아 있으면, 같은 기기에서 끌 때(`SettingsView.setEnabled`)와 똑같이 뺀다.
            // 아직 동기화로 도착하지 않은 번역본(레코드 자체가 없음)은 건드리지 않는다. 다시 켜도 자동으로 되돌리지 않는다.
            let disabledCodes = Set(all.filter { !$0.isEnabled }.map(\.code))
            let enabledCodes = Set(enabled.map(\.code))
            let staleCodes = disabledCodes.subtracting(enabledCodes)   // 같은 code의 활성 행이 있으면(중복 행) 유지한다.
            if !staleCodes.isEmpty {
                let pruned = UserSettingsStore.shared.defaultDisplayedTranslationCodes.filter { !staleCodes.contains($0) }
                if pruned != UserSettingsStore.shared.defaultDisplayedTranslationCodes {
                    UserSettingsStore.shared.defaultDisplayedTranslationCodes = pruned
                }
            }

            // 모두 꺼져 있으면 열이 하나도 없는 빈 화면이 되므로, 이때만 번들 번역본을 표시용으로 쓴다(목록/팝오버는 그대로 비어 있다).
            let candidates = enabled.isEmpty ? all.filter(\.isBundled) : enabled
            let validIDs = Set(candidates.map(\.persistentModelID))
            // 사용자가 세션 중 고른 조합은 유지하되, 꺼졌거나 삭제된 번역본은 걸러낸다.
            let previousCount = displayedTranslationIDs.count
            displayedTranslationIDs = displayedTranslationIDs.filter { validIDs.contains($0) }
            if displayedTranslationIDs.isEmpty {
                // 최초 진입이거나 표시 중이던 열이 전부 사라진 경우 — 이전 열 개수(없으면 최대 개수)만큼 기본 선택으로 채운다.
                displayedTranslationIDs = defaultDisplayedSelection(from: candidates, limit: previousCount > 0 ? previousCount : maxColumns)
            }
            reloadVerses()
        } catch {
            lastErrorDescription = "등록된 번역본 목록을 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// 기본 표시 번역본 선택 — `defaultDisplayedTranslationCodes`(표시 번역본 체크박스)가 있으면 최우선, 비어 있으면
    /// "등록 순 + defaultTranslationCode 맨 앞" 규칙. 후보(`candidates`)는 호출부가 이미 활성 번역본으로 좁혀서 넘긴다.
    private func defaultDisplayedSelection(from candidates: [TranslationRegistry], limit: Int) -> [PersistentIdentifier] {
        let count = min(max(limit, 1), maxColumns)
        let preferredCodes = UserSettingsStore.shared.defaultDisplayedTranslationCodes
        if !preferredCodes.isEmpty {
            // 중복 code 행이 있어도 `Dictionary(uniqueKeysWithValues:)`처럼 죽지 않게 첫 행을 쓴다.
            let byCode = Dictionary(candidates.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
            let chosen = preferredCodes.compactMap { byCode[$0] }
            if !chosen.isEmpty {
                return Array(chosen.prefix(count)).map(\.persistentModelID)
            }
        }
        var ordered = candidates
        if let preferredCode = UserSettingsStore.shared.defaultTranslationCode,
           let index = ordered.firstIndex(where: { $0.code == preferredCode }) {
            let preferred = ordered.remove(at: index)
            ordered.insert(preferred, at: 0)
        }
        return ordered.prefix(count).map(\.persistentModelID)
    }

    // `recordHistory`가 false면 조회 이력에 남기지 않는다(`navigateToBookmark`만 false를 넘긴다).
    func selectBook(_ book: Book, chapter: Int = 1, recordHistory: Bool = true) {
        pushCurrentLocationToBackStack()
        selectedBook = book
        selectedChapter = max(1, chapter)
        clearVerseSelection()
        reloadVerses()
        refreshRelatedContent()
        LastBiblePositionTracker.shared.update(bookId: book.bookId, chapter: selectedChapter)
        // 조회 이력 기록 — `init`의 마지막 위치 복원은 이 메서드를 거치지 않으므로 탭 전환마다 중복 이력이
        // 쌓이지 않는다.
        if recordHistory {
            BibleReadingHistoryService.record(bookId: book.bookId, chapter: selectedChapter, context: modelContext)
        }
    }

    func goToChapter(_ chapter: Int, recordHistory: Bool = true) {
        guard chapter >= 1 else { return }
        pushCurrentLocationToBackStack()
        selectedChapter = chapter
        clearVerseSelection()
        reloadVerses()
        refreshRelatedContent()
        LastBiblePositionTracker.shared.update(bookId: selectedBook.bookId, chapter: chapter)
        if recordHistory {
            BibleReadingHistoryService.record(bookId: selectedBook.bookId, chapter: chapter, context: modelContext)
        }
    }

    // MARK: - 조회 이력 (2026-08-08 추가)

    /// 최신순 조회 이력 중 최근 1개월분만 반환한다(저장 상한은 `BibleReadingHistoryService.maxEntries`).
    /// 다른 창에서 쌓인 이력까지 반영되도록 캐싱하지 않는다.
    func fetchHistory() -> [BibleReadingHistoryEntry] {
        let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
        let all = (try? modelContext.fetch(
            FetchDescriptor<BibleReadingHistoryEntry>(sortBy: [SortDescriptor(\.viewedAt, order: .reverse)])
        )) ?? []
        return all.filter { $0.viewedAt >= oneMonthAgo }
    }

    /// 히스토리 항목을 탭하면 그 책/장으로 이동한다. `entry.verse`가 있으면 `recordHistory: false`로
    /// `selectBook`의 장 단위 기록을 끄고 그 절로 이동·강조한 뒤 절 단위 이력 한 줄만 남긴다(끄지 않으면
    /// 장 단위·절 단위 이력이 둘 다 쌓인다). 없으면 `selectBook`이 장 단위로 기록한다.
    func jumpToHistoryEntry(_ entry: BibleReadingHistoryEntry) {
        guard let book = booksProvider.book(id: entry.bookId) else { return }
        if let verse = entry.verse {
            selectBook(book, chapter: entry.chapter, recordHistory: false)
            highlightVerseTemporarily(verse)
            recordVerseHistory(verse: verse)
        } else {
            selectBook(book, chapter: entry.chapter)
        }
    }

    /// 확대보기/사이드바 검색 직행처럼 장 이동 없이 "이미 보고 있는 장의 절 하나"를 가리키는
    /// 이벤트를 조회 이력에 남긴다. 장 이동을 유발하지 않을 수 있어 `selectBook`/`goToChapter`와
    /// 분리했고, 호출부가 명시적으로만 부른다.
    func recordVerseHistory(verse: Int) {
        BibleReadingHistoryService.record(bookId: selectedBook.bookId, chapter: selectedChapter, verse: verse, context: modelContext)
    }

    // MARK: - 책갈피 (2026-08-28 신설)
    //
    // 저장 단위는 조회 이력과 같다: 절을 정확히 하나 선택 중이면 그 절, 아니면 현재 장 전체.
    // 히스토리 이력에는 남기지 않는다.

    /// 책갈피 목록/토글 상태가 바뀔 때마다 올리는 카운터. 책갈피는 `@Observable`이 추적하지 않는
    /// SwiftData 컬렉션이라, 이 값을 읽게 해서 토글 직후 뷰가 다시 그려지도록 신호를 준다
    /// (`SearchResultsPopRequest.swift`와 같은 이벤트 카운터 패턴).
    private(set) var bookmarkVersion = 0

    /// 번역본 코드가 없던(`translationCode == ""`) 레거시 책갈피를 기본 번역본 코드로 채운다.
    /// `onAppear()`에서 `availableTranslations`가 채워진 뒤 호출하며, 채울 대상이 없으면 무동작이다.
    /// CloudKit 동기화로 다른 기기의 예전 데이터가 뒤늦게 들어와도 자가 치유된다(`purgeLegacyMarkHighlights()`와 같은 패턴).
    private func migrateLegacyBookmarksIfNeeded() {
        let legacy = BibleBookmarkService.fetchAll(context: modelContext).filter { $0.translationCode.isEmpty }
        guard !legacy.isEmpty, let code = defaultBookmarkTranslationCode else { return }
        for bookmark in legacy {
            bookmark.translationCode = code
        }
        try? modelContext.save()
    }

    /// 레거시 마이그레이션 기준 "기본 번역본" — `UserSettingsStore.shared.defaultTranslationCode`가
    /// 등록돼 있으면 그것, 아니면 등록 순 첫 번째 번역본.
    private var defaultBookmarkTranslationCode: String? {
        if let preferred = UserSettingsStore.shared.defaultTranslationCode,
           availableTranslations.contains(where: { $0.code == preferred }) {
            return preferred
        }
        return availableTranslations.first?.code
    }

    /// 현재 장에서 절 번호가 있는 책갈피의 번역본 코드별 절 집합(절 옆 세로선 표시용).
    /// 절마다 `BibleBookmarkService.isBookmarked`를 부르면 매번 책갈피 전체를 다시 읽어 스크롤 성능이
    /// 떨어지므로, 장이 바뀌거나 책갈피가 바뀔 때만 한 번 계산해 둔다(`chapterHighlightsIndex`와 같은 원칙).
    /// "장 전체" 책갈피(`verse == nil`)는 제외한다.
    private(set) var bookmarkedVersesInChapter: [String: Set<Int>] = [:]
    /// "장 전체" 책갈피(`verse == nil`)가 있는 번역본 코드 집합(칼럼 세로 리본 표시용).
    /// `bookmarkedVersesInChapter`와 같은 fetch 결과로 함께 계산해 `fetchAll`을 두 번 부르지 않는다.
    private(set) var chapterBookmarkedTranslationCodes: Set<String> = []

    /// 위 두 값을 현재 책/장 기준으로 다시 계산한다.
    private func rebuildBookmarkedVersesIndex() {
        let bookId = selectedBook.bookId
        let chapter = selectedChapter
        let all = BibleBookmarkService.fetchAll(context: modelContext)
        let chapterBookmarks = all.filter { $0.bookId == bookId && $0.chapter == chapter }
        var versesByTranslation: [String: Set<Int>] = [:]
        var chapterCodes: Set<String> = []
        for bookmark in chapterBookmarks {
            if let verse = bookmark.verse {
                versesByTranslation[bookmark.translationCode, default: []].insert(verse)
            } else {
                chapterCodes.insert(bookmark.translationCode)
            }
        }
        bookmarkedVersesInChapter = versesByTranslation
        chapterBookmarkedTranslationCodes = chapterCodes
    }

    /// 이 절을 정확히 가리키는 그 번역본(`translationCode`)의 책갈피가 있는지(절 번호 옆 세로선 표시 여부).
    func isVerseBookmarked(translationCode: String, verse: Int) -> Bool {
        bookmarkedVersesInChapter[translationCode]?.contains(verse) ?? false
    }

    /// 현재 장 전체가 그 번역본(`translationCode`) 기준으로 책갈피돼 있는지(칼럼 세로 리본 표시 여부).
    func isChapterBookmarked(translationCode: String) -> Bool {
        chapterBookmarkedTranslationCodes.contains(translationCode)
    }

    /// 현재 위치(절 하나만 선택 중이면 그 절, 아니면 장)가 해당 번역본 기준으로 이미 책갈피인지 —
    /// 툴바 책갈피 아이콘의 설정/해제 모양을 결정한다.
    func isCurrentPositionBookmarked(translationCode: String) -> Bool {
        _ = bookmarkVersion
        return BibleBookmarkService.isBookmarked(
            bookId: selectedBook.bookId, chapter: selectedChapter,
            verse: selectedVerses.count == 1 ? selectedVerses.first : nil,
            translationCode: translationCode,
            context: modelContext
        )
    }

    /// 툴바 책갈피 아이콘 탭 — 현재 위치를 해당 번역본 기준으로 설정/해제 토글한다.
    func toggleBookmarkForCurrentPosition(translationCode: String) {
        BibleBookmarkService.toggle(
            bookId: selectedBook.bookId, chapter: selectedChapter,
            verse: selectedVerses.count == 1 ? selectedVerses.first : nil,
            translationCode: translationCode,
            context: modelContext
        )
        bookmarkVersion += 1
        rebuildBookmarkedVersesIndex()
    }

    /// 책갈피 이동 팝오버가 열릴 때마다 새로 불러온다(다른 창에서 쌓인 책갈피 반영을 위해 캐싱하지 않음).
    /// 번역본으로 좁히지 않고 전체를 반환한다.
    func fetchBookmarks() -> [BibleBookmark] {
        BibleBookmarkService.fetchAll(context: modelContext)
    }

    /// 책갈피 목록의 스와이프 삭제용. 이미 존재하는 조합이라 `BibleBookmarkService.toggle`은 항상 삭제만 일으킨다.
    /// 삭제한 책갈피가 현재 위치와 같을 수 있어 `bookmarkVersion`도 올린다.
    func deleteBookmark(_ bookmark: BibleBookmark) {
        BibleBookmarkService.toggle(bookId: bookmark.bookId, chapter: bookmark.chapter, verse: bookmark.verse, translationCode: bookmark.translationCode, context: modelContext)
        bookmarkVersion += 1
        rebuildBookmarkedVersesIndex()
    }

    /// 책갈피 목록에서 탭한 책/장(+있으면 절)으로 이동한다. `recordHistory: false`라 조회 이력에는 남기지 않는다.
    /// 절은 `highlightVerseTemporarily`로 잠깐 강조만 하고 `selectedVerses`는 건드리지 않는다(`selectBook`이 이미 비운다).
    func navigateToBookmark(_ bookmark: BibleBookmark) {
        guard let book = booksProvider.book(id: bookmark.bookId) else { return }
        selectBook(book, chapter: bookmark.chapter, recordHistory: false)
        if let verse = bookmark.verse {
            highlightVerseTemporarily(verse)
        }
    }

    // MARK: - 클립보드 복사용 절 선택 (2026-08-08 추가)

    /// 범위/개별 다중 선택의 "기준점" — 마지막으로 일반 클릭 또는 Option 클릭한 절 번호.
    /// Shift/Cmd 클릭(범위 선택) 시 이 절부터 새로 클릭한 절까지를 범위로 잡는다.
    private(set) var verseSelectionAnchor: Int?

    /// 일반 클릭 — 이 절 하나만 선택한다. 이미 정확히 이 절 하나만 선택된 상태에서 다시 클릭하면 선택을 해제한다
    /// (iOS/iPadOS는 `onToggleVerseSelection` 경로가 재탭 해제를 처리하므로, macOS 일반 클릭 경로용).
    func selectSingleVerse(_ verse: Int) {
        if selectedVerses == [verse] {
            selectedVerses = []
            verseSelectionAnchor = nil
            return
        }
        selectedVerses = [verse]
        verseSelectionAnchor = verse
    }

    /// Option 클릭 — 이 절만 선택 목록에서 추가/제거한다(다른 선택은 유지).
    /// Control+클릭은 macOS 컨텍스트 메뉴와 겹칠 수 있어 Option 키를 쓴다.
    func toggleVerseSelection(_ verse: Int) {
        if selectedVerses.contains(verse) {
            selectedVerses.remove(verse)
        } else {
            selectedVerses.insert(verse)
        }
        verseSelectionAnchor = verse
    }

    /// Shift/Cmd 클릭 — 기준점(`verseSelectionAnchor`)부터 이 절까지를 범위로 선택한다.
    /// 기준점이 없으면 이 절 하나만 선택하고 새 기준점으로 삼는다.
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

    /// 선택된 절들을 환경설정(복사 형식) 그대로 문자열로 만든다. 클립보드에 넣는 일은 호출부(View) 책임이다
    /// (플랫폼 API 분기를 뷰 레이어에만 두는 관례).
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

    /// 선택된 절들을 "기준 번역본(맨 왼쪽 열)" 한 곳만으로 문자열로 만든다. 말씀 요약을 열면 기준 번역본만
    /// 남기고 나머지 열을 숨기므로 그 상태와 일치시킨 것이다. 번역본 이름표는 `BibleVerseCopyFormatter`가
    /// 번역본이 1개면 붙이지 않는다.
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

    /// 현재 책/장 기준으로 책 개요/장 개요/메모/연구문서 등 관련 콘텐츠를 다시 읽어온다.
    /// `selectBook`/`goToChapter`/`onAppear`가 자동 호출하지만, 화면 밖에서 편집한 변경을 반영해야 할 때
    /// 호출부가 직접 부를 수 있도록 public이다.
    func refreshRelatedContent() {
        let bookId = selectedBook.bookId
        let chapter = selectedChapter

        // 미리보기 문자열과 원본 RTF를 같은 레코드("가장 최근 수정된, 내용이 있는 개요")에서 함께 뽑기 위해
        // 레코드를 먼저 고른 뒤 두 값을 파생시킨다.
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
        rebuildRelatedChapterMemosIndex()

        // 관련 말씀 요약은 작성 순서(`createdAt` 내림차순, `WordSummaryHomeView`와 같은 기준).
        relatedChapterWordSummaries = (try? modelContext.fetch(
            FetchDescriptor<VerseSummary>(
                predicate: #Predicate { $0.bookId == bookId && $0.chapter == chapter },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        )) ?? []

        // ⚠️ `relatedChapterRef`는 전체 fetch 후 Swift 레벨에서 거른다(`relatedDocuments` 선언부 주석 참고).
        let targetRef = BibleChapterRef(bookId: bookId, chapter: chapter)
        let allDocuments = (try? modelContext.fetch(
            FetchDescriptor<SourceDocument>(sortBy: [SortDescriptor(\.uploadedAt, order: .reverse)])
        )) ?? []
        relatedDocuments = allDocuments.filter { $0.relatedChapterRef == targetRef }

        // `bookId`/`chapter`가 SwiftData 저장 프로퍼티라 `#Predicate`로 바로 걸러도 안전하다.
        relatedChapterSermonVerseReferences = (try? modelContext.fetch(
            FetchDescriptor<SermonVerseReference>(
                predicate: #Predicate { $0.bookId == bookId && $0.chapter == chapter }
            )
        )) ?? []

        // 구간 주석(형광펜/표시/관주)은 이 장 분량을 통째로 불러온다.
        chapterHighlights = (try? modelContext.fetch(
            FetchDescriptor<VerseHighlight>(
                predicate: #Predicate { $0.bookId == bookId && $0.chapter == chapter }
            )
        )) ?? []
        rebuildHighlightsIndex()
        // 번들분 관주/난외주는 SwiftData가 아니라 `ReferenceDataProvider.shared.store`(ReferenceData.sqlite, 읽기 전용)에서
        // 읽어 사용자 생성분과 합친다. SwiftData 조회는 `sourceRaw != "bundled"`로 걸러, 예전 방식으로 남아 있을 수 있는
        // 번들 레코드가 이중으로 보이지 않게 한다(`ReferenceDataMigration.cleanupLegacyBundledRecords(in:)`의 1회성
        // 정리가 끝나기 전까지의 안전망).
        let bundledSourceRaw = VerseCrossReferenceSource.bundled.rawValue
        let userCrossReferences = (try? modelContext.fetch(
            FetchDescriptor<VerseCrossReference>(
                predicate: #Predicate { $0.bookId == bookId && $0.chapter == chapter && $0.sourceRaw != bundledSourceRaw }
            )
        )) ?? []
        // `try?`는 이미 옵셔널인 표현식을 이중 옵셔널로 감싸지 않고 평탄화한다(SE-0230) — 타입은 `[VerseCrossReference]?`.
        let bundledCrossReferences = try? ReferenceDataProvider.shared.store?.crossReferences(
            bookId: bookId, chapter: chapter, translationCode: TranslationBootstrap.bundledTranslationCode
        )
        chapterCrossReferences = userCrossReferences + (bundledCrossReferences ?? [])
        rebuildCrossReferencesIndex()

        chapterPhraseNotes = (try? modelContext.fetch(
            FetchDescriptor<VersePhraseNote>(
                predicate: #Predicate { $0.bookId == bookId && $0.chapter == chapter }
            )
        )) ?? []
        rebuildPhraseNotesIndex()

        let userMarginalNotes = (try? modelContext.fetch(
            FetchDescriptor<VerseMarginalNote>(
                predicate: #Predicate { $0.bookId == bookId && $0.chapter == chapter && $0.sourceRaw != bundledSourceRaw }
            )
        )) ?? []
        let bundledMarginalNotes = try? ReferenceDataProvider.shared.store?.marginalNotes(
            bookId: bookId, chapter: chapter, translationCode: TranslationBootstrap.bundledTranslationCode
        )
        chapterMarginalNotes = userMarginalNotes + (bundledMarginalNotes ?? [])
        rebuildMarginalNotesIndex()

        // 절 단위 한자 주석은 ReferenceData.sqlite에서만 읽는다.
        chapterHanjaAnnotations = (try? ReferenceDataProvider.shared.store?.hanjaAnnotations(
            bookId: bookId, chapter: chapter
        )) ?? [:]

        // 이 장 분량의 성경구절 언급 인덱스를 통째로 불러온다. 인덱스 재계산은 `onAppear`에서만 하고 여기서는
        // 이미 계산된 결과만 읽는다(장 이동마다 메모/문서 전체를 다시 스캔하지 않기 위해).
        rebuildBookmarkedVersesIndex()

        chapterVerseMentions = (try? modelContext.fetch(
            FetchDescriptor<VerseMention>(
                predicate: #Predicate { $0.bookId == bookId && $0.chapter == chapter }
            )
        )) ?? []
        rebuildVerseMentionsIndex()
    }

    private static func makePreview(_ text: String, limit: Int = 80) -> String {
        if text.count <= limit { return text }
        return String(text.prefix(limit)) + "…"
    }

    /// 마지막 장에서는 다음 책 1장으로 이동한다. 상한 검사가 없으면 존재하지 않는 장 번호로 넘어가 빈 화면이 뜬다.
    /// `selectedBook.chapterCount`가 그 책의 마지막 장 번호다.
    func nextChapter() {
        if selectedChapter < selectedBook.chapterCount {
            goToChapter(selectedChapter + 1)
        } else if let nextBook = booksProvider.book(after: selectedBook) {
            selectBook(nextBook, chapter: 1)
        }
        // 요한계시록 마지막 장이면 `booksProvider.book(after:)`가 nil이라 아무 것도 하지 않는다.
    }

    /// 1장에서는 이전 책의 마지막 장으로 이동한다(창세기 1장이면 이동하지 않는다).
    func previousChapter() {
        if selectedChapter > 1 {
            goToChapter(selectedChapter - 1)
        } else if let previousBook = booksProvider.book(before: selectedBook) {
            selectBook(previousBook, chapter: previousBook.chapterCount)
        }
        // 창세기 1장이면 `booksProvider.book(before:)`가 nil이라 아무 것도 하지 않는다.
    }

    // MARK: - 절 단위 이전/다음 이동 (2026-09-27 신설)
    //
    // 실제 이동은 `goToChapter`/`selectBook`을 재사용해 조회 이력 기록·관련 내용 새로고침 등 기존 부수효과를 그대로 물려받는다.
    // 장/책 경계를 넘으면 이전 장 마지막 절 ↔ 다음 장 1절로 이어지고(`previousChapter`/`nextChapter`와 같은 책 경계 처리),
    // 이동한 절은 `selectedVerses`에 선택된 채로 남는다.

    /// "이전 구절" 버튼이 실제로 갈 곳이 있는지(화살표 비활성화 판정). 같은 장에 이전 절이 있거나,
    /// 장 첫 절이면 이전 장/책이 있어야 true — `previousChapter()`의 경계 판정과 같다.
    func canGoToPreviousVerse(from verse: Int) -> Bool {
        if verse > 1 { return true }
        return selectedChapter > 1 || booksProvider.book(before: selectedBook) != nil
    }

    /// `canGoToPreviousVerse(from:)`와 대칭. `columns.first?.verses.count`가 로드된 장의 마지막 절 번호다
    /// (`reloadVerses()`가 동기 호출이라 `goToChapter`/`selectBook` 직후에도 최신값이다 — `ColumnState.verses` 선언부 참고).
    func canGoToNextVerse(from verse: Int) -> Bool {
        let versesInChapter = columns.first?.verses.count ?? 0
        if verse < versesInChapter { return true }
        return selectedChapter < selectedBook.chapterCount || booksProvider.book(after: selectedBook) != nil
    }

    /// 장 경계를 넘으면 이전 장의 마지막 절로 이어진다. `goToChapter`/`selectBook`이 먼저
    /// `clearVerseSelection()`을 호출하므로 `selectedVerses`는 그 뒤에 설정해야 지워지지 않는다.
    func goToPreviousVerse(from verse: Int) {
        guard canGoToPreviousVerse(from: verse) else { return }
        if verse > 1 {
            selectedVerses = [verse - 1]
            verseSelectionAnchor = verse - 1
            return
        }
        if selectedChapter > 1 {
            goToChapter(selectedChapter - 1)
        } else if let previousBook = booksProvider.book(before: selectedBook) {
            selectBook(previousBook, chapter: previousBook.chapterCount)
        }
        let lastVerse = columns.first?.verses.count ?? 1
        selectedVerses = [lastVerse]
        verseSelectionAnchor = lastVerse
    }

    /// `goToPreviousVerse(from:)`와 대칭 — 장 경계를 넘으면 다음 장의 1절로 이어진다.
    func goToNextVerse(from verse: Int) {
        guard canGoToNextVerse(from: verse) else { return }
        let versesInChapter = columns.first?.verses.count ?? 0
        if verse < versesInChapter {
            selectedVerses = [verse + 1]
            verseSelectionAnchor = verse + 1
            return
        }
        if selectedChapter < selectedBook.chapterCount {
            goToChapter(selectedChapter + 1)
        } else if let nextBook = booksProvider.book(after: selectedBook) {
            selectBook(nextBook, chapter: 1)
        }
        selectedVerses = [1]
        verseSelectionAnchor = 1
    }

    // MARK: - 브라우저 스타일 뒤로/앞으로 탐색 (2026-08-20 추가)
    //
    // 브라우저 history.back/forward처럼 사용자가 실제로 거쳐온 임의의 책/장 순서(`selectBook`/`goToChapter`를 타는
    // 모든 경로)를 되짚는다. 인접 장 ±1 이동인 `previousChapter`/`nextChapter`와 다른 개념이다.
    // `BibleReadingHistoryService`의 영구 방문 기록과 별개로, 이 뷰모델 인스턴스(=이 창) 안에서만 사는
    // 순수 인메모리 스택이다.

    private struct ChapterLocation: Equatable {
        let bookId: Int
        let chapter: Int
        /// 이 장을 떠나는 순간 절을 정확히 하나 선택 중이었다면 그 절도 함께 기억한다(그 외에는 장 전체).
        let verse: Int?
    }

    private var backStack: [ChapterLocation] = []
    private var forwardStack: [ChapterLocation] = []

    var canGoBackInHistory: Bool { !backStack.isEmpty }
    var canGoForwardInHistory: Bool { !forwardStack.isEmpty }

    private var currentLocation: ChapterLocation {
        ChapterLocation(
            bookId: selectedBook.bookId,
            chapter: selectedChapter,
            verse: selectedVerses.count == 1 ? selectedVerses.first : nil
        )
    }

    /// `selectBook`/`goToChapter`가 이동 직전에 호출 — 현재 자리를 뒤로가기 스택에 쌓고, 앞으로가기 스택은 비운다(브라우저 표준 동작).
    /// `goBackInHistory`/`goForwardInHistory`는 이 메서드를 거치지 않으므로 뒤로/앞으로 이동이 스택에 다시 쌓이지 않는다.
    private func pushCurrentLocationToBackStack() {
        backStack.append(currentLocation)
        forwardStack.removeAll()
    }

    /// 스택에서 꺼낸 위치로 이동한다 — `pushCurrentLocationToBackStack`을 타지 않는다는 점만 빼면
    /// `selectBook`과 같은 부수효과를 수행한다.
    private func navigate(toHistory location: ChapterLocation) {
        guard let book = booksProvider.book(id: location.bookId) else { return }
        selectedBook = book
        selectedChapter = max(1, location.chapter)
        clearVerseSelection()
        reloadVerses()
        refreshRelatedContent()
        LastBiblePositionTracker.shared.update(bookId: book.bookId, chapter: selectedChapter)
        // `location.verse`를 이력에도 반영하고(안 그러면 절로 돌아갔는데 이력엔 장만 남는다)
        // `highlightVerseTemporarily`로 그 절을 강조한다.
        BibleReadingHistoryService.record(bookId: book.bookId, chapter: selectedChapter, verse: location.verse, context: modelContext)
        if let verse = location.verse {
            highlightVerseTemporarily(verse)
        }
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
        // 말씀 요약 편집을 끝낼 때처럼 "예전에 저장해 둔 목록"을 되돌리는 호출이 있어, 그 사이 꺼졌거나 삭제된 번역본이 섞여
        // 있을 수 있다 — 활성 번역본만 남긴다. 전부 사라졌으면(저장해 둔 열이 모두 꺼짐) 기본 선택으로 대체한다.
        let validIDs = Set(availableTranslations.map(\.persistentModelID))
        let filtered = ids.filter { validIDs.contains($0) }
        if filtered.isEmpty, !ids.isEmpty, !availableTranslations.isEmpty {
            displayedTranslationIDs = defaultDisplayedSelection(from: availableTranslations, limit: ids.count)
        } else {
            displayedTranslationIDs = Array(filtered.prefix(maxColumns))
        }
        reloadVerses()
    }

    // `Book.chapterCount`(books.json 정적 데이터)를 BookChapterPicker가 직접 쓰므로 장 개수는 여기서 조회하지 않는다.

    private func reloadVerses() {
        // `.filter`는 `availableTranslations`(등록 순)의 순서를 그대로 물려받아 `displayedTranslationIDs`의 순서가 버려진다.
        // 그래서 `displayedTranslationIDs` 기준으로 매핑해 그 배열의 순서가 곧 컬럼 순서가 되게 한다.
        let byID = Dictionary(uniqueKeysWithValues: availableTranslations.map { ($0.persistentModelID, $0) })
        let displayed = displayedTranslationIDs.compactMap { byID[$0] }
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
                // 번들 파일(version_code 컬럼 없음)과 사용자 추가 파일을 구분하지 않고 연다 — `BibleReferenceStore`가
                // PRAGMA table_info로 스스로 판단한다.
                // ⚠️ version_code 컬럼이 있는 파일에서 `registry.code`가 실제 표기와 다르면(대소문자/표기 차이) 결과가 비어 보일 수 있다.
                let versionCode = store.hasVersionCodeColumn ? registry.code : nil
                state.verses = try store.verses(bookId: selectedBook.bookId, chapter: selectedChapter, versionCode: versionCode)
            } catch {
                state.errorDescription = error.localizedDescription
            }
            return state
        }
    }

    private func store(for registry: TranslationRegistry) throws -> BibleReferenceStore {
        // 다른 기기에서 CloudKit으로 막 동기화된 사용자 추가 번역본은 `sqliteFileReference`가 이 기기에 없는 경로를
        // 가리킬 수 있다(sqliteData만 도착한 상태). 그래서 `TranslationFileMaterializer`가 필요하면 로컬로 다시 써내고 필드를 갱신한다.
        // 번들 번역본은 `registry.code`로 어느 번들 파일인지 구분해야 한다(인자 없는 `resolvedBundledDatabaseURL()`은 KRV 고정이라 국한문 열도 KRV로 뜬다).
        let path = registry.isBundled
            ? try TranslationBootstrap.resolvedBundledDatabaseURL(for: registry.code).path
            : try TranslationFileMaterializer.ensureMaterialized(registry, context: modelContext)
        if let cached = storeCache[path] { return cached }
        let store = try BibleReferenceStore(filePath: path)
        storeCache[path] = store
        return store
    }
}
