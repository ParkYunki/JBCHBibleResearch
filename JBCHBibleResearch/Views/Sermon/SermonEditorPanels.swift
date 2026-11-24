//
//  SermonEditorPanels.swift
//  JBCHBibleResearch
//
//  [2026-11-14 내 설교 고도화] 에디터·상세 화면이 함께 쓰는 보조 화면.
//  - `SermonFindController` / `SermonFindBar`: 문서 안 찾기·바꾸기
//  - `SermonOutlinePanel`: 대/중/소주제 개요 내비게이터(구간별 분량)
//  - `SermonResearchPane`: 연구 자료(장 개요·책 개요·말씀 요약·개인 묵상) 열람 + 참고 자료 링크
//  - `SermonParentLinkPicker` / `SermonLinkChainSection`: 이어지는 설교(상위 링크) 선택·표시
//

import SwiftUI
import SwiftData
import BibleResearchModels

// MARK: - 문서 안 찾기

/// 찾기·바꾸기 상태. 텍스트 접근은 호출부가 넘기는 프록시가 맡는다(이 객체는 프록시를 붙들지 않는다).
@MainActor
@Observable
final class SermonFindController {
    var isVisible = false
    var showsReplace = false
    var query = ""
    var replacement = ""
    private(set) var ranges: [NSRange] = []
    private(set) var current: Int?

    var countLabel: String {
        if query.isEmpty { return "" }
        if ranges.isEmpty { return String(localized: "없음") }
        return "\((current ?? 0) + 1) / \(ranges.count)"
    }

    func open(with selectedText: String?, proxy: SermonParagraphEditingProxy) {
        if let selectedText, !selectedText.isEmpty, !selectedText.contains("\n"), selectedText.count <= 60 {
            query = selectedText
        }
        isVisible = true
        refresh(proxy: proxy, resetCurrent: true)
    }

    func close(proxy: SermonParagraphEditingProxy) {
        isVisible = false
        ranges = []
        current = nil
        proxy.clearFind()
        proxy.focusEditor()
    }

    /// 일치 목록을 다시 만든다. `resetCurrent`면 캐럿 이후 첫 항목으로, 아니면 이전 순번을 유지한다(범위를 벗어나면 끝으로).
    func refresh(proxy: SermonParagraphEditingProxy, resetCurrent: Bool) {
        guard isVisible else { return }
        ranges = proxy.findRanges(query)
        if ranges.isEmpty {
            current = nil
        } else if resetCurrent || current == nil {
            let caret = proxy.selectionRange.location
            current = ranges.firstIndex(where: { $0.location >= caret }) ?? 0
        } else if let value = current {
            current = min(value, ranges.count - 1)
        }
        proxy.showFind(ranges, current: current)
    }

    func next(proxy: SermonParagraphEditingProxy) { step(1, proxy: proxy) }
    func previous(proxy: SermonParagraphEditingProxy) { step(-1, proxy: proxy) }

    private func step(_ delta: Int, proxy: SermonParagraphEditingProxy) {
        if ranges.isEmpty { refresh(proxy: proxy, resetCurrent: true) }
        guard !ranges.isEmpty else { return }
        let base = current ?? 0
        current = (base + delta + ranges.count) % ranges.count
        proxy.showFind(ranges, current: current)
    }

    func replaceCurrent(proxy: SermonParagraphEditingProxy) {
        guard let index = current, ranges.indices.contains(index) else { return }
        proxy.replace(ranges[index], with: replacement)
        // 바꾼 글자에 찾는 말이 다시 들어 있으면 같은 자리에 머물지 않고 다음으로 넘어간다.
        let containsQuery = !query.isEmpty && replacement.range(of: query, options: .caseInsensitive) != nil
        refresh(proxy: proxy, resetCurrent: false)
        if containsQuery, !ranges.isEmpty { current = (index + 1) % ranges.count; proxy.showFind(ranges, current: current) }
    }

    func replaceAll(proxy: SermonParagraphEditingProxy) {
        guard !ranges.isEmpty else { return }
        proxy.replaceAll(ranges, with: replacement)
        refresh(proxy: proxy, resetCurrent: true)
    }
}

struct SermonFindBar: View {
    @Bindable var find: SermonFindController
    let proxy: SermonParagraphEditingProxy
    var accent: Color
    @FocusState private var queryFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(String(localized: "문서에서 찾기"), text: $find.query)
                    .textFieldStyle(.plain)
                    .focused($queryFocused)
                    .onSubmit { find.next(proxy: proxy) }
                    .submitLabel(.search)
                    .id("sermon-find-query")
                Text(find.countLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button { find.previous(proxy: proxy) } label: { Image(systemName: "chevron.up") }
                    .accessibilityLabel(String(localized: "이전 찾기"))
                    .disabled(find.ranges.isEmpty)
                Button { find.next(proxy: proxy) } label: { Image(systemName: "chevron.down") }
                    .accessibilityLabel(String(localized: "다음 찾기"))
                    .disabled(find.ranges.isEmpty)
                Button { find.showsReplace.toggle() } label: {
                    Text(String(localized: "바꾸기")).font(.caption.weight(.semibold))
                }
                .buttonStyle(SermonMiniPillButtonStyle(isFilled: find.showsReplace, tint: accent))
                Button { find.close(proxy: proxy) } label: { Image(systemName: "xmark") }
                    .accessibilityLabel(String(localized: "찾기 닫기"))
            }
            if find.showsReplace {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary)
                    TextField(String(localized: "바꿀 말"), text: $find.replacement)
                        .textFieldStyle(.plain)
                        .id("sermon-find-replacement")
                    Button(String(localized: "바꾸기")) { find.replaceCurrent(proxy: proxy) }
                        .buttonStyle(SermonMiniPillButtonStyle(isFilled: false, tint: accent))
                        .disabled(find.current == nil)
                    Button(String(localized: "모두 바꾸기")) { find.replaceAll(proxy: proxy) }
                        .buttonStyle(SermonMiniPillButtonStyle(isFilled: false, tint: accent))
                        .disabled(find.ranges.isEmpty)
                }
            }
        }
        .buttonStyle(.plain)
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(SermonViewerPaper.color)
        .tint(accent)
        .onAppear { queryFocused = true }
        .onChange(of: find.query) { _, _ in find.refresh(proxy: proxy, resetCurrent: true) }
    }
}

// MARK: - 개요 내비게이터

struct SermonOutlinePanel: View {
    let entries: [SermonOutlineEntry]
    let stats: SermonTextStats
    var accent: Color
    let onSelect: (Int) -> Void

    private var maxCharacters: Int { max(1, entries.map(\.characters).max() ?? 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "개요"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(localized: "\(stats.characters)자"))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            if entries.isEmpty {
                Text(String(localized: "대주제·중주제·소주제 스타일을 쓰면 여기에 개요가 만들어집니다."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(entries) { entry in
                            Button { onSelect(entry.id) } label: { row(entry) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .background(SermonViewerPaper.color)
    }

    private func row(_ entry: SermonOutlineEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.title.isEmpty ? String(localized: "(제목 없음)") : entry.title)
                    .font(entry.level == 0 ? .subheadline.weight(.bold) : (entry.level == 1 ? .footnote.weight(.semibold) : .footnote))
                    .foregroundStyle(entry.level == 2 ? Color.secondary : Color.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Text("\(entry.characters)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                Capsule()
                    .fill(accent.opacity(0.35))
                    .frame(width: max(2, proxy.size.width * CGFloat(entry.characters) / CGFloat(maxCharacters)), height: 3)
            }
            .frame(height: 3)
        }
        .padding(.leading, 12 + CGFloat(entry.level) * 12)
        .padding(.trailing, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

// MARK: - 연구 자료 패널

nonisolated struct SermonChapterRef: Hashable, Sendable {
    var bookId: Int
    var chapter: Int
}

extension SermonChapterRef {
    /// 주 본문과 이 설교에 단 구절 참조에서 장 후보를 뽑는다(중복 제거, 최대 8개).
    @MainActor
    static func suggestions(for sermon: Sermon?, mainPassage: String?) -> [SermonChapterRef] {
        var result: [SermonChapterRef] = []
        func add(_ ref: SermonChapterRef) { if !result.contains(ref) { result.append(ref) } }
        if let mainPassage, !mainPassage.isEmpty,
           let match = BibleReferenceExtractor.extract(from: mainPassage).first(where: { $0.kind == .reference }) {
            add(SermonChapterRef(bookId: match.bookId, chapter: match.chapter))
        }
        for reference in sermon?.verseReferences ?? [] { add(SermonChapterRef(bookId: reference.bookId, chapter: reference.chapter)) }
        return Array(result.prefix(8))
    }

    @MainActor
    var label: String {
        let name = BooksProvider.shared.book(id: bookId)?.displayName ?? "\(bookId)"
        return "\(name) \(chapter)"
    }
}

/// 연구 자료 본문을 읽을 수 있는 평문으로 돌려준다. 기존 데이터 중에는 `contentText`에 RTF 원문(`{\rtf1 …`)이
/// 그대로 들어 있는 것이 있어, 그대로 보여 주면 RTF 코드가 화면에 나온다 — 그런 값만 RTF로 해석해 글자만 꺼낸다.
/// 일반 평문이면 값을 바꾸지 않는다(원본 레코드는 수정하지 않는다).
@MainActor
enum SermonResearchText {
    static func plain(_ stored: String) -> String {
        guard let start = stored.range(of: "{\\rtf1") else { return stored }
        // RTF 앞에는 공백·보이지 않는 문자만 허용한다 — 그 밖의 글자가 앞서면 RTF가 아니라 "rtf1"을 언급한 일반 글이다.
        guard stored[..<start.lowerBound].allSatisfy({ $0.isWhitespace || $0 == "\u{FEFF}" || $0 == "\u{200B}" }) else { return stored }
        let rtf = String(stored[start.lowerBound...])
        // 1순위: 시스템 RTF 해석기. 실패하면 `decode`가 입력을 그대로 돌려주므로 아직 RTF로 보이면 직접 해석한다.
        let decoded = RichTextCodec.decode(rtf, defaultAttributes: [:]).string
        let text = decoded.contains("\\rtf1") ? stripRTF(rtf) : decoded
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 글꼴·색 표 같은 부가 그룹을 건너뛰고 본문 글자만 꺼내는 최소 RTF 해석기(`\uN` 유니코드, `\par`, `\tab` 지원).
    private static func stripRTF(_ rtf: String) -> String {
        let chars = Array(rtf.unicodeScalars)
        var out = String.UnicodeScalarView()
        var depth = 0
        var skipDepth: Int?
        var uc = 1
        var ucStack: [Int] = []
        var skipCount = 0
        var highSurrogate: UInt32?
        var i = 0
        let skippedWords: Set<String> = ["fonttbl", "colortbl", "expandedcolortbl", "stylesheet", "info", "pict", "header", "footer"]

        func emit(_ scalar: Unicode.Scalar) {
            guard skipDepth == nil else { return }
            out.append(scalar)
        }

        while i < chars.count {
            let c = chars[i]
            switch c {
            case "{":
                depth += 1
                ucStack.append(uc)
                i += 1
            case "}":
                if let s = skipDepth, depth == s { skipDepth = nil }
                depth -= 1
                if let saved = ucStack.popLast() { uc = saved }
                i += 1
            case "\\":
                i += 1
                guard i < chars.count else { break }
                let next = chars[i]
                if next == "\\" || next == "{" || next == "}" {
                    if skipCount > 0 { skipCount -= 1 } else { emit(next) }
                    i += 1
                } else if next == "\n" || next == "\r" {
                    emit("\n")
                    i += 1
                } else if next == "*" {
                    if skipDepth == nil { skipDepth = depth }
                    i += 1
                } else if next == "'" {
                    // `\'hh` — 코드 페이지 바이트. ASCII 범위만 글자로 쓰고 나머지는 건너뛴다(`\uN`이 본문을 담는다).
                    i += 1
                    var hex = ""
                    while hex.count < 2, i < chars.count, chars[i].properties.isASCIIHexDigit {
                        hex.unicodeScalars.append(chars[i])
                        i += 1
                    }
                    if skipCount > 0 { skipCount -= 1 }
                    else if let value = UInt32(hex, radix: 16), value < 0x80, let scalar = Unicode.Scalar(value) { emit(scalar) }
                } else if (next.value >= 0x41 && next.value <= 0x5A) || (next.value >= 0x61 && next.value <= 0x7A) {
                    var word = ""
                    while i < chars.count, (chars[i].value >= 0x41 && chars[i].value <= 0x5A) || (chars[i].value >= 0x61 && chars[i].value <= 0x7A) {
                        word.unicodeScalars.append(chars[i])
                        i += 1
                    }
                    var digits = ""
                    if i < chars.count, chars[i] == "-" { digits = "-"; i += 1 }
                    while i < chars.count, chars[i].value >= 0x30, chars[i].value <= 0x39 {
                        digits.unicodeScalars.append(chars[i])
                        i += 1
                    }
                    let number = Int(digits)
                    if i < chars.count, chars[i] == " " { i += 1 }
                    if skippedWords.contains(word) {
                        if skipDepth == nil { skipDepth = depth }
                    } else if word == "par" || word == "line" {
                        emit("\n")
                    } else if word == "tab" {
                        emit("\t")
                    } else if word == "uc", let number {
                        uc = max(0, number)
                    } else if word == "u", let number {
                        let raw = UInt32(truncatingIfNeeded: number < 0 ? number + 65536 : number)
                        if (0xD800...0xDBFF).contains(raw) {
                            highSurrogate = raw
                        } else if (0xDC00...0xDFFF).contains(raw), let high = highSurrogate {
                            let combined = 0x10000 + ((high - 0xD800) << 10) + (raw - 0xDC00)
                            if let scalar = Unicode.Scalar(combined) { emit(scalar) }
                            highSurrogate = nil
                        } else if let scalar = Unicode.Scalar(raw) {
                            emit(scalar)
                        }
                        skipCount = uc
                    }
                } else {
                    // 그 밖의 제어 기호(`\~` 등)는 무시한다.
                    i += 1
                }
            case "\n", "\r":
                i += 1
            default:
                if skipCount > 0 { skipCount -= 1 } else { emit(c) }
                i += 1
            }
        }
        return String(out)
    }
}

/// 연구 자료 링크의 원본을 다시 찾아 제목·본문을 돌려준다.
@MainActor
enum SermonReferenceResolver {
    static func resolve(_ link: SermonReferenceLink, context: ModelContext) -> String? {
        let itemId = link.itemId
        switch link.kind {
        case .chapterSummary:
            return (try? context.fetch(FetchDescriptor<ChapterSummary>(predicate: #Predicate { $0.id == itemId })))?.first.map { SermonResearchText.plain($0.contentText) }
        case .bookOutline:
            return (try? context.fetch(FetchDescriptor<BookOutline>(predicate: #Predicate { $0.id == itemId })))?.first.map { SermonResearchText.plain($0.contentText) }
        case .verseSummary:
            return (try? context.fetch(FetchDescriptor<VerseSummary>(predicate: #Predicate { $0.id == itemId })))?.first.map { SermonResearchText.plain($0.contentText) }
        case .memo:
            return (try? context.fetch(FetchDescriptor<UserMemo>(predicate: #Predicate { $0.id == itemId })))?.first.map { SermonResearchText.plain($0.contentText) }
        }
    }

    static func kindLabel(_ kind: SermonReferenceKind) -> String {
        switch kind {
        case .chapterSummary: return String(localized: "장 개요")
        case .bookOutline: return String(localized: "책 개요")
        case .verseSummary: return String(localized: "말씀 요약")
        case .memo: return String(localized: "개인 묵상")
        }
    }
}

private struct SermonResearchItem: Identifiable {
    let id: UUID
    let kind: SermonReferenceKind
    let title: String
    let text: String
    let bookId: Int
    let chapter: Int
}

struct SermonResearchPane: View {
    enum Tab: String { case research, links }

    /// 링크를 저장할 설교. 회차 사본을 편집할 때는 그 회차의 메인 설교.
    let sermon: Sermon?
    let suggestions: [SermonChapterRef]
    var accent: Color

    @Environment(\.modelContext) private var context
    @State private var tab: Tab = .research
    @State private var bookId = 1
    @State private var chapter = 1
    @State private var items: [SermonResearchItem] = []
    @State private var opened: SermonResearchItem?
    @State private var didPickInitial = false

    var body: some View {
        VStack(spacing: 0) {
            SermonSegmentedPill(
                items: [
                    .init(tag: Tab.research, label: String(localized: "연구 자료")),
                    .init(tag: Tab.links, label: String(localized: "참고 자료 \(sermon?.referenceLinks.count ?? 0)")),
                ],
                selection: $tab, accent: accent
            )
            .padding(10)
            Divider()
            switch tab {
            case .research: researchTab
            case .links: linksTab
            }
        }
        .background(SermonViewerPaper.color)
        .onAppear {
            if !didPickInitial, let first = suggestions.first { bookId = first.bookId; chapter = first.chapter }
            didPickInitial = true
            reload()
        }
        .onChange(of: bookId) { _, _ in clampChapter(); reload() }
        .onChange(of: chapter) { _, _ in reload() }
        .sheet(item: $opened) { item in
            SermonResearchItemSheet(item: item, sermon: sermon, accent: accent)
        }
    }

    // MARK: 연구 자료 탭

    private var currentBook: Book? { BooksProvider.shared.book(id: bookId) }

    private var researchTab: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                if !suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(suggestions, id: \.self) { ref in
                                Button { bookId = ref.bookId; chapter = ref.chapter } label: { Text(ref.label).font(.caption.weight(.semibold)) }
                                    .buttonStyle(SermonMiniPillButtonStyle(isFilled: ref.bookId == bookId && ref.chapter == chapter, tint: accent))
                            }
                        }
                    }
                }
                HStack(spacing: 8) {
                    Picker(String(localized: "책"), selection: $bookId) {
                        ForEach(BooksProvider.shared.books) { book in Text(book.displayName).tag(book.bookId) }
                    }
                    .labelsHidden()
                    Stepper(value: $chapter, in: 1...max(1, currentBook?.chapterCount ?? 1)) {
                        Text(String(localized: "\(chapter)장")).font(.subheadline.monospacedDigit())
                    }
                }
            }
            .padding(10)
            Divider()
            if items.isEmpty {
                Text(String(localized: "이 장에 저장된 연구 자료가 없습니다."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(items) { item in researchCard(item) }
                    }
                    .padding(10)
                }
            }
        }
    }

    private func researchCard(_ item: SermonResearchItem) -> some View {
        let linked = isLinked(item)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                SermonBadge(text: SermonReferenceResolver.kindLabel(item.kind), color: accent)
                Text(item.title).font(.footnote.weight(.semibold)).lineLimit(1)
                Spacer()
            }
            Text(item.text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(4)
            HStack(spacing: 8) {
                Button(String(localized: "전체 보기")) { opened = item }
                    .buttonStyle(SermonMiniPillButtonStyle(isFilled: false, tint: accent))
                if sermon != nil {
                    Button {
                        toggleLink(item)
                    } label: {
                        Label(linked ? String(localized: "링크됨") : String(localized: "참고 자료로 링크"), systemImage: linked ? "checkmark" : "link")
                    }
                    .buttonStyle(SermonMiniPillButtonStyle(isFilled: linked, tint: accent))
                }
            }
        }
        .padding(10)
        .background(SermonTheme.cardFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: 참고 자료 탭

    private var linksTab: some View {
        let links = sermon?.referenceLinks ?? []
        return Group {
            if links.isEmpty {
                Text(String(localized: "연구 자료 탭에서 [참고 자료로 링크]를 누르면 여기에 모입니다."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(links) { link in linkRow(link) }
                    }
                    .padding(10)
                }
            }
        }
    }

    private func linkRow(_ link: SermonReferenceLink) -> some View {
        let text = SermonReferenceResolver.resolve(link, context: context)
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    SermonBadge(text: SermonReferenceResolver.kindLabel(link.kind), color: accent)
                    Text(link.title).font(.footnote.weight(.semibold)).lineLimit(1)
                }
                if let text {
                    Text(text).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                } else {
                    Text(String(localized: "원본이 삭제되었습니다.")).font(.footnote).foregroundStyle(.red)
                }
            }
            Spacer(minLength: 0)
            if let text {
                Button { opened = SermonResearchItem(id: link.itemId, kind: link.kind, title: link.title, text: text, bookId: link.bookId, chapter: link.chapter) } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "전체 보기"))
            }
            Button { removeLink(link) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "링크 해제"))
        }
        .padding(10)
        .background(SermonTheme.cardFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: 데이터

    private func clampChapter() {
        let maxChapter = max(1, currentBook?.chapterCount ?? 1)
        if chapter > maxChapter { chapter = maxChapter }
        if chapter < 1 { chapter = 1 }
    }

    private func isLinked(_ item: SermonResearchItem) -> Bool {
        sermon?.referenceLinks.contains { $0.itemId == item.id } ?? false
    }

    private func toggleLink(_ item: SermonResearchItem) {
        guard let sermon else { return }
        var links = sermon.referenceLinks
        if let index = links.firstIndex(where: { $0.itemId == item.id }) {
            links.remove(at: index)
        } else {
            links.append(SermonReferenceLink(kind: item.kind, title: item.title, bookId: item.bookId, chapter: item.chapter, itemId: item.id))
        }
        sermon.referenceLinks = links
        sermon.updatedAt = .now
        try? context.save()
    }

    private func removeLink(_ link: SermonReferenceLink) {
        guard let sermon else { return }
        sermon.referenceLinks = sermon.referenceLinks.filter { $0.id != link.id }
        sermon.updatedAt = .now
        try? context.save()
    }

    private func reload() {
        let b = bookId, c = chapter
        let bookName = currentBook?.displayName ?? "\(b)"
        var result: [SermonResearchItem] = []
        if let summary = (try? context.fetch(FetchDescriptor<ChapterSummary>(predicate: #Predicate { $0.bookId == b && $0.chapter == c })))?.first,
           !summary.contentText.isEmpty {
            result.append(SermonResearchItem(id: summary.id, kind: .chapterSummary, title: String(localized: "\(bookName) \(c)장 개요"), text: SermonResearchText.plain(summary.contentText), bookId: b, chapter: c))
        }
        if let outline = (try? context.fetch(FetchDescriptor<BookOutline>(predicate: #Predicate { $0.bookId == b })))?.first,
           !outline.contentText.isEmpty {
            result.append(SermonResearchItem(id: outline.id, kind: .bookOutline, title: String(localized: "\(bookName) 개요"), text: SermonResearchText.plain(outline.contentText), bookId: b, chapter: c))
        }
        let summaries = (try? context.fetch(FetchDescriptor<VerseSummary>(
            predicate: #Predicate { $0.bookId == b && $0.chapter == c }, sortBy: [SortDescriptor(\.createdAt)]
        ))) ?? []
        for summary in summaries where !summary.contentText.isEmpty {
            result.append(SermonResearchItem(id: summary.id, kind: .verseSummary, title: verseTitle(bookName, c, summary.verse, summary.verseEnd), text: SermonResearchText.plain(summary.contentText), bookId: b, chapter: c))
        }
        let memos = (try? context.fetch(FetchDescriptor<UserMemo>(
            predicate: #Predicate { $0.bookId == b && $0.chapter == c }, sortBy: [SortDescriptor(\.createdAt)]
        ))) ?? []
        for memo in memos where !memo.contentText.isEmpty {
            result.append(SermonResearchItem(id: memo.id, kind: .memo, title: verseTitle(bookName, c, memo.verse, memo.verseEnd), text: SermonResearchText.plain(memo.contentText), bookId: b, chapter: c))
        }
        items = result
    }

    private func verseTitle(_ book: String, _ chapter: Int, _ verse: Int?, _ verseEnd: Int?) -> String {
        guard let verse else { return "\(book) \(chapter)" }
        if let verseEnd, verseEnd > verse { return "\(book) \(chapter):\(verse)-\(verseEnd)" }
        return "\(book) \(chapter):\(verse)"
    }
}

private struct SermonResearchItemSheet: View {
    let item: SermonResearchItem
    let sermon: Sermon?
    var accent: Color
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(item.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .navigationTitle(item.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(String(localized: "닫기")) { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }
}

// MARK: - 이어지는 설교 (상위 링크)

/// 이 설교의 "이어지는 설교"를 고르는 시트. 자기 자신은 목록에서 뺀다. 순환 연결은 막지 않고 표시 쪽(`SermonLinkChain`)이 안전하게 처리한다.
struct SermonParentLinkPicker: View {
    let sermon: Sermon
    @Query(sort: \Sermon.updatedAt, order: .reverse) private var sermons: [Sermon]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var candidates: [Sermon] {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return sermons.filter { $0.id != sermon.id && (trimmed.isEmpty || $0.title.lowercased().contains(trimmed)) }
    }

    var body: some View {
        NavigationStack {
            List(candidates, id: \.id) { candidate in
                let selected = sermon.parentLinkUUIDs.contains(candidate.id)
                Button { toggle(candidate) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.title.isEmpty ? String(localized: "제목 없음") : candidate.title).foregroundStyle(.primary)
                            Text(candidate.updatedAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        SermonBadge(text: candidate.status.displayName, color: candidate.status.tint)
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? SermonTheme.accent : .secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $search, prompt: String(localized: "설교 제목 검색"))
            .navigationTitle(String(localized: "이어지는 설교 연결"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(String(localized: "완료")) { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 480)
        #endif
    }

    private func toggle(_ candidate: Sermon) {
        var ids = sermon.parentLinkUUIDs
        if let index = ids.firstIndex(of: candidate.id) { ids.remove(at: index) } else { ids.append(candidate.id) }
        sermon.parentLinkUUIDs = ids
        sermon.updatedAt = .now
        try? context.save()
    }
}

/// 이어지는 설교 연쇄(최대 10단계)를 들여쓰기로 보여 준다. 이 설교를 이어받는 설교(역링크)는 아래에 따로 나온다.
struct SermonLinkChainSection: View {
    let sermon: Sermon
    var accent: Color
    var onOpen: (Sermon) -> Void
    var onEdit: (() -> Void)? = nil
    @Query(sort: \Sermon.updatedAt, order: .reverse) private var sermons: [Sermon]

    var body: some View {
        let ancestors = SermonLinkChain.ancestors(of: sermon, among: sermons)
        let followers = SermonLinkChain.followers(of: sermon, among: sermons)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(String(localized: "이어지는 설교"), systemImage: "arrow.triangle.branch")
                    .font(.subheadline.weight(.bold))
                Spacer()
                if let onEdit {
                    Button(String(localized: "연결 편집"), action: onEdit)
                        .buttonStyle(SermonMiniPillButtonStyle(isFilled: false, tint: accent))
                }
            }
            if ancestors.isEmpty {
                Text(String(localized: "연결된 설교가 없습니다. 연속 강해가 아니어도 앞서 전한 설교를 상위로 연결할 수 있습니다."))
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(ancestors) { node in
                    Button { onOpen(node.sermon) } label: {
                        HStack(spacing: 6) {
                            Text(String(localized: "\(node.depth)단계"))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(accent)
                            Text(node.sermon.title.isEmpty ? String(localized: "제목 없음") : node.sermon.title)
                                .font(.footnote)
                                .foregroundStyle(node.isRepeat ? Color.secondary : Color.primary)
                                .lineLimit(1)
                            if node.isRepeat { SermonBadge(text: String(localized: "위에 이미 나옴"), color: .secondary) }
                            if node.hasMore { SermonBadge(text: String(localized: "더 이어짐"), color: SermonTheme.warning) }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.leading, CGFloat(node.depth - 1) * 14)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if !followers.isEmpty {
                Divider()
                Text(String(localized: "이 설교를 이어받는 설교"))
                    .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                ForEach(followers, id: \.id) { follower in
                    Button { onOpen(follower) } label: {
                        HStack {
                            Text(follower.title.isEmpty ? String(localized: "제목 없음") : follower.title).font(.footnote).lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - 참고 자료 (상세 화면용)

/// 설교가 참고한 연구 자료 링크 목록 — 눌러서 원문을 읽고, 링크를 해제할 수 있다. 링크 추가는 에디터의 연구 자료 패널에서 한다.
struct SermonReferenceLinksSection: View {
    let sermon: Sermon
    var accent: Color
    @Environment(\.modelContext) private var context
    @State private var opened: SermonResearchItem?

    var body: some View {
        let links = sermon.referenceLinks
        VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "참고 자료 (\(links.count))"), systemImage: "link")
                .font(.subheadline.weight(.bold))
            if links.isEmpty {
                Text(String(localized: "설교 작성 화면의 [연구 자료]에서 참고한 장 개요·말씀 요약·묵상을 링크해 둘 수 있습니다."))
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(links) { link in
                    let text = SermonReferenceResolver.resolve(link, context: context)
                    Button {
                        if let text {
                            opened = SermonResearchItem(id: link.itemId, kind: link.kind, title: link.title, text: text, bookId: link.bookId, chapter: link.chapter)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            SermonBadge(text: SermonReferenceResolver.kindLabel(link.kind), color: accent)
                            Text(link.title).font(.footnote).lineLimit(1)
                            if text == nil { SermonBadge(text: String(localized: "삭제됨"), color: .red) }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(text == nil)
                    .contextMenu {
                        Button(role: .destructive) {
                            sermon.referenceLinks = sermon.referenceLinks.filter { $0.id != link.id }
                            sermon.updatedAt = .now
                            try? context.save()
                        } label: { Label(String(localized: "링크 해제"), systemImage: "link.badge.minus") }
                    }
                }
            }
        }
        .sheet(item: $opened) { item in
            SermonResearchItemSheet(item: item, sermon: sermon, accent: accent)
        }
    }
}
