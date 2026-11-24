//
//  SermonAdvance.swift
//  JBCHBibleResearch
//
//  [2026-11-14 내 설교 고도화] 설교 에디터·상세·목록·뷰어가 함께 쓰는 지원 코드.
//  - `SermonPrefs`: 기기별 설정 키(UserDefaults/@AppStorage). iCloud로 동기화하지 않는다.
//  - `SermonShortcut`: 구절 치환 단축키(기본 ⌃R = 말씀구절 스타일, ⌃T = 현재 스타일 유지).
//  - `SermonQuoteService`: 선택한 성경 참조 → 구절 본문 + 출처 표기("(요 3:16)").
//  - `SermonTextStats`: 글자 수·예상 시간·개요(대/중/소주제) 구간별 분량.
//  - `SermonLinkChain`: 이어지는 설교(상위 링크) 연쇄 조회(최대 10단계, 순환 안전).
//  - `SermonReferenceLink`: 설교가 참고한 연구 자료 링크(JSON으로 `Sermon.referenceLinksJSON`에 저장).
//

import Foundation
import SwiftUI
import SwiftData
import BibleResearchModels

// MARK: - 기기별 설정 키

enum SermonPrefs {
    /// 설교 인용 번역본(`TranslationRegistry.code`). 빈 문자열이면 앱 언어의 번들 기본 번역본.
    static let quoteVersionCode = "sermon.quote.versionCode"
    /// 출처 표기 방식: `abbr`(요 3:16) / `full`(요한복음 3:16) / `none`(표기 안 함).
    static let citationMode = "sermon.quote.citationMode"
    static let verseStyleKey = "sermon.shortcut.verseStyle.key"
    static let verseStyleModifier = "sermon.shortcut.verseStyle.modifier"
    static let verseInlineKey = "sermon.shortcut.verseInline.key"
    static let verseInlineModifier = "sermon.shortcut.verseInline.modifier"
    /// 분당 글자 수(예상 설교 시간 계산).
    static let charsPerMinute = "sermon.stats.charsPerMinute"
    static let defaultCharsPerMinute = 280
    /// 에디터 개요 내비게이터 펼침(이 기기).
    static let outlineVisible = "sermon.editor.outlineVisible"
    /// 에디터 오른쪽 패널의 마지막 탭(이 기기).
    static let paneTab = "sermon.editor.paneTab"
    static let viewerKeepAwake = "sermon.viewer.keepAwake"
    static let viewerTargetMinutes = "sermon.viewer.targetMinutes"
    static let defaultViewerTargetMinutes = 30

    static var citationModeValue: String {
        UserDefaults.standard.string(forKey: citationMode) ?? "abbr"
    }

    static var charsPerMinuteValue: Int {
        let value = UserDefaults.standard.integer(forKey: charsPerMinute)
        return value > 0 ? value : defaultCharsPerMinute
    }

    static var keepAwakeValue: Bool {
        UserDefaults.standard.object(forKey: viewerKeepAwake) == nil ? true : UserDefaults.standard.bool(forKey: viewerKeepAwake)
    }

    static var targetMinutesValue: Int {
        let value = UserDefaults.standard.integer(forKey: viewerTargetMinutes)
        return value > 0 ? value : defaultViewerTargetMinutes
    }
}

// MARK: - 구절 치환 단축키

enum SermonShortcutModifier: String, CaseIterable, Identifiable {
    case control, option, controlShift, commandShift
    var id: Self { self }

    var symbol: String {
        switch self {
        case .control: return "⌃"
        case .option: return "⌥"
        case .controlShift: return "⌃⇧"
        case .commandShift: return "⌘⇧"
        }
    }
}

/// 구절 치환 동작 종류.
enum SermonVerseSubstituteMode {
    /// 구절을 "말씀구절" 문단으로 삽입(기본 ⌃R).
    case verseStyle
    /// 현재 문단 안에서 현재 스타일 그대로 바꿈(기본 ⌃T).
    case inline
}

struct SermonShortcut: Equatable {
    var key: String          // 소문자 한 글자(a–z)
    var modifier: SermonShortcutModifier

    var label: String { "\(modifier.symbol)\(key.uppercased())" }

    static func load(mode: SermonVerseSubstituteMode) -> SermonShortcut {
        let defaults = UserDefaults.standard
        let keyName = mode == .verseStyle ? SermonPrefs.verseStyleKey : SermonPrefs.verseInlineKey
        let modName = mode == .verseStyle ? SermonPrefs.verseStyleModifier : SermonPrefs.verseInlineModifier
        let fallbackKey = mode == .verseStyle ? "r" : "t"
        let rawKey = (defaults.string(forKey: keyName) ?? fallbackKey).lowercased()
        let key = (rawKey.count == 1 && rawKey.unicodeScalars.allSatisfy { $0.isASCII && CharacterSet.lowercaseLetters.contains($0) }) ? rawKey : fallbackKey
        let modifier = defaults.string(forKey: modName).flatMap(SermonShortcutModifier.init(rawValue:)) ?? .control
        return SermonShortcut(key: key, modifier: modifier)
    }

    /// 키 이벤트가 이 단축키인지. `characters`는 수정키를 무시한 글자(소문자 비교).
    func matches(characters: String, control: Bool, option: Bool, command: Bool, shift: Bool) -> Bool {
        guard characters.lowercased() == key else { return false }
        switch modifier {
        case .control: return control && !option && !command && !shift
        case .option: return option && !control && !command && !shift
        case .controlShift: return control && shift && !option && !command
        case .commandShift: return command && shift && !control && !option
        }
    }

    /// 설정 화면의 경고 문구. 문제가 없으면 nil. (앱·시스템 단축키 목록은 확인된 것만 담는다 — 실기기 확인 필요.)
    func conflictNote(otherThan other: SermonShortcut) -> String? {
        if self == other { return String(localized: "두 동작이 같은 키입니다.") }
        switch modifier {
        case .control:
            if "abdefhklnoptvy".contains(key) {
                return String(localized: "macOS 텍스트 입력의 기본 키(⌃\(key.uppercased()))와 겹칠 수 있습니다. 앱이 먼저 처리하도록 했지만 실기기에서 확인이 필요합니다.")
            }
        case .commandShift:
            if "bnt".contains(key) {
                return String(localized: "앱의 기존 단축키(⇧⌘B · ⇧⌘N · ⇧⌘T)와 겹칩니다.")
            }
        default:
            break
        }
        return nil
    }
}

// MARK: - 상태 표시

extension SermonStatus {
    var displayName: String {
        switch self {
        case .draft: return String(localized: "초안")
        case .refining: return String(localized: "다듬는 중")
        case .complete: return String(localized: "완성")
        }
    }

    var tint: Color {
        switch self {
        case .draft: return Color(white: 0.45)
        case .refining: return Color(red: 0.66, green: 0.37, blue: 0.0)
        case .complete: return Color(red: 0.18, green: 0.49, blue: 0.31)
        }
    }
}

// MARK: - 연구 자료 링크 (설교 → 연구 자료)

nonisolated enum SermonReferenceKind: String, Codable, CaseIterable, Sendable {
    case chapterSummary   // 장 개요
    case bookOutline      // 책 개요
    case verseSummary     // 말씀 요약
    case memo             // 개인 묵상(메모)
}

nonisolated struct SermonReferenceLink: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var kind: SermonReferenceKind
    var title: String
    var bookId: Int
    var chapter: Int
    /// 원본 레코드 id — 열 때 이 값으로 다시 찾는다(지워졌으면 목록에서 "삭제됨"으로 보인다).
    var itemId: UUID
}

extension Sermon {
    var status: SermonStatus {
        get { statusRaw.flatMap(SermonStatus.init(rawValue:)) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    var parentLinkUUIDs: [UUID] {
        get { parentLinkIds.split(separator: "\n").compactMap { UUID(uuidString: String($0)) } }
        set {
            var seen = Set<UUID>()
            parentLinkIds = newValue.filter { seen.insert($0).inserted }.map(\.uuidString).joined(separator: "\n")
        }
    }

    var referenceLinks: [SermonReferenceLink] {
        get {
            guard !referenceLinksJSON.isEmpty, let data = referenceLinksJSON.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([SermonReferenceLink].self, from: data)) ?? []
        }
        set {
            guard !newValue.isEmpty, let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8) else {
                referenceLinksJSON = ""
                return
            }
            referenceLinksJSON = json
        }
    }

    /// 화면에 보일 주 본문 — 직접 지정한 값이 있으면 그것, 없으면 본문 속 첫 성경 참조(제안값). 없으면 nil.
    var effectiveMainPassage: (text: String, isSuggested: Bool)? {
        let trimmed = mainPassage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return (trimmed, false) }
        if let suggested = SermonPassage.suggestion(from: contentText) { return (suggested, true) }
        return nil
    }
}

enum SermonPassage {
    /// 본문 텍스트 속 첫 성경 참조 원문(예: "요 3:1-15"). 없으면 nil.
    @MainActor
    static func suggestion(from text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let matches = BibleReferenceExtractor.extract(from: text)
        guard let first = matches.first(where: { $0.kind == .reference }) else { return nil }
        let trimmed = first.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - 이어지는 설교(상위 링크) 연쇄

struct SermonLinkNode: Identifiable {
    /// 목록 안 순서(안정적인 식별자 — 다시 그려도 바뀌지 않는다).
    let id: Int
    let sermon: Sermon
    /// 1 = 현재 설교가 직접 연결한 설교.
    let depth: Int
    /// 이미 위에 나온 설교로 되돌아가는 연결(순환/중복) — 한 번만 보이고 더 따라가지 않는다.
    let isRepeat: Bool
    /// 단계 상한에 걸려 이 아래로 더 이어지는 연결이 남아 있다.
    let hasMore: Bool
}

enum SermonLinkChain {
    static let maxDepth = 10

    /// `start`의 상위 링크를 깊이 우선으로 따라간 평평한 목록(들여쓰기용 `depth` 포함).
    /// 이미 나온 설교는 `isRepeat`로 한 번만 보이고 멈춘다(순환 안전). 지워진 설교(id만 남은 링크)는 건너뛴다.
    static func ancestors(of start: Sermon, among all: [Sermon]) -> [SermonLinkNode] {
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<UUID> = [start.id]
        var result: [SermonLinkNode] = []

        func visit(_ sermon: Sermon, depth: Int) {
            for parentID in sermon.parentLinkUUIDs {
                guard let parent = byID[parentID] else { continue }
                if seen.contains(parentID) {
                    result.append(SermonLinkNode(id: result.count, sermon: parent, depth: depth, isRepeat: true, hasMore: false))
                    continue
                }
                seen.insert(parentID)
                let hasMore = depth >= maxDepth && parent.parentLinkUUIDs.contains { byID[$0] != nil }
                result.append(SermonLinkNode(id: result.count, sermon: parent, depth: depth, isRepeat: false, hasMore: hasMore))
                if depth < maxDepth { visit(parent, depth: depth + 1) }
            }
        }
        visit(start, depth: 1)
        return result
    }

    /// 이 설교를 상위로 연결해 둔 설교(역링크, 자동).
    static func followers(of sermon: Sermon, among all: [Sermon]) -> [Sermon] {
        all.filter { $0.id != sermon.id && $0.parentLinkUUIDs.contains(sermon.id) }
    }
}

// MARK: - 글자 수 · 예상 시간 · 개요

struct SermonOutlineEntry: Identifiable {
    let id: Int              // 문단 순번(0부터)
    let level: Int           // 0 대주제 · 1 중주제 · 2 소주제
    let title: String
    /// 이 제목부터 다음 제목 직전까지의 글자 수(공백·줄바꿈 제외).
    let characters: Int
}

struct SermonTextStats: Equatable {
    var characters: Int = 0          // 줄바꿈 제외, 공백 포함
    var charactersNoSpace: Int = 0
    var paragraphs: Int = 0

    static func compute(text: String) -> SermonTextStats {
        var stats = SermonTextStats()
        guard !text.isEmpty else { return stats }
        var paragraphStarted = false
        for scalar in text.unicodeScalars {
            if scalar == "\n" || scalar == "\r" || scalar == "\u{2028}" || scalar == "\u{2029}" {
                paragraphStarted = false
                continue
            }
            if !paragraphStarted { stats.paragraphs += 1; paragraphStarted = true }
            stats.characters += 1
            if !CharacterSet.whitespaces.contains(scalar) { stats.charactersNoSpace += 1 }
        }
        return stats
    }

    /// 예상 설교 시간(분). 글자 수(공백 포함) ÷ 분당 글자 수.
    func estimatedMinutes(charsPerMinute: Int) -> Double {
        guard charsPerMinute > 0 else { return 0 }
        return Double(characters) / Double(charsPerMinute)
    }

    static func minutesLabel(_ minutes: Double) -> String {
        if minutes < 1 { return String(localized: "1분 미만") }
        return String(localized: "약 \(Int(minutes.rounded()))분")
    }

    /// 대주제·중주제·소주제 문단을 제목으로 보는 개요. 제목이 없으면 빈 배열.
    static func outline(text: String, styles: String) -> [SermonOutlineEntry] {
        let paragraphs = SermonParagraphStyleCodec.parseParagraphs(text: text, styles: styles)
        var entries: [SermonOutlineEntry] = []
        var currentIndex: Int?
        var currentLevel = 0
        var currentTitle = ""
        var count = 0

        func flush() {
            if let index = currentIndex {
                entries.append(SermonOutlineEntry(id: index, level: currentLevel, title: currentTitle, characters: count))
            }
        }

        for (index, paragraph) in paragraphs.enumerated() {
            let level: Int?
            switch paragraph.style {
            case .mainTheme: level = 0
            case .midTheme: level = 1
            case .subTheme: level = 2
            default: level = nil
            }
            let visible = paragraph.text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count
            if let level {
                flush()
                currentIndex = index
                currentLevel = level
                currentTitle = paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines)
                count = visible
            } else {
                count += visible
            }
        }
        flush()
        return entries
    }
}

// MARK: - 설교 인용 서비스 (구절 치환)

@MainActor
enum SermonQuoteService {
    struct Target {
        let bookId: Int
        let chapter: Int
        let verseStart: Int
        let verseEnd: Int?
        /// 본문 전체 텍스트 기준 NSRange(참조 표기가 있는 자리).
        let range: NSRange
    }

    /// `selection`(NSRange, `text` 기준)에서 치환할 성경 참조를 찾는다.
    /// - 선택이 있으면: 선택 전체가 하나의 참조여야 한다(앞뒤 공백은 허용).
    /// - 캐럿만 있으면: 캐럿이 있는 문단에서 캐럿에 닿는 참조.
    /// 장을 넘는 범위·절 없는 장 참조·이어쓰기 표기는 치환하지 않는다(추측하지 않고 nil).
    static func target(in text: String, selection: NSRange) -> Target? {
        let ns = text as NSString
        guard selection.location != NSNotFound, selection.location <= ns.length else { return nil }
        let scanRange: NSRange
        if selection.length > 0 {
            scanRange = selection
        } else {
            scanRange = ns.paragraphRange(for: NSRange(location: min(selection.location, ns.length), length: 0))
        }
        guard scanRange.length > 0, NSMaxRange(scanRange) <= ns.length else { return nil }
        let scanned = ns.substring(with: scanRange)
        let matches = BibleReferenceExtractor.extract(from: scanned).filter { $0.kind == .reference }
        guard !matches.isEmpty else { return nil }

        // 같은 원문 범위로 펼쳐진 Match들을 한 묶음으로 본다.
        var groups: [(range: NSRange, items: [BibleReferenceExtractor.Match])] = []
        for match in matches {
            let local = NSRange(match.range, in: scanned)
            if let index = groups.firstIndex(where: { NSEqualRanges($0.range, local) }) {
                groups[index].items.append(match)
            } else {
                groups.append((local, [match]))
            }
        }

        let chosen: (range: NSRange, items: [BibleReferenceExtractor.Match])?
        if selection.length > 0 {
            let trimmedLength = scanned.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count
            chosen = groups.first { trimmedLength > 0 && $0.range.length == trimmedLength }
        } else {
            let caret = selection.location - scanRange.location
            chosen = groups.first { caret >= $0.range.location && caret <= NSMaxRange($0.range) }
        }
        guard let chosen, let first = chosen.items.first else { return nil }
        guard chosen.items.allSatisfy({ $0.bookId == first.bookId && $0.chapter == first.chapter }) else { return nil }
        let verses = chosen.items.compactMap(\.verse)
        guard verses.count == chosen.items.count, let start = verses.min(), let end = verses.max() else { return nil }
        let absolute = NSRange(location: scanRange.location + chosen.range.location, length: chosen.range.length)
        return Target(bookId: first.bookId, chapter: first.chapter, verseStart: start, verseEnd: end > start ? end : nil, range: absolute)
    }

    /// 출처 표기. 예: "(요 3:16)" / "(요한복음 3:16-18)". 표기 안 함이면 빈 문자열.
    static func citation(bookId: Int, chapter: Int, verseStart: Int, verseEnd: Int?) -> String {
        let mode = SermonPrefs.citationModeValue
        guard mode != "none", let book = BooksProvider.shared.books.first(where: { $0.bookId == bookId }) else { return "" }
        let label = mode == "full" ? book.displayName : book.displayShortName
        let range = (verseEnd ?? verseStart) > verseStart ? "\(verseStart)-\(verseEnd ?? verseStart)" : "\(verseStart)"
        return "(\(label) \(chapter):\(range))"
    }

    /// 설교 인용 번역본에서 구절 본문을 이어 붙여 돌려준다(절 번호·출처 표기 없음). 못 찾으면 nil.
    static func verseText(for target: Target, context: ModelContext) -> String? {
        let code = UserDefaults.standard.string(forKey: SermonPrefs.quoteVersionCode) ?? ""
        let store: BibleReferenceStore
        var versionCode: String?
        if !code.isEmpty,
           let registry = (try? context.fetch(FetchDescriptor<TranslationRegistry>(predicate: #Predicate { $0.code == code })))?.first,
           registry.isEnabled,
           let path = try? (registry.isBundled
                ? TranslationBootstrap.resolvedBundledDatabaseURL(for: registry.code).path
                : TranslationFileMaterializer.ensureMaterialized(registry, context: context)),
           let opened = try? BibleReferenceStore(filePath: path) {
            store = opened
            versionCode = opened.hasVersionCodeColumn ? registry.code : nil
        } else if let opened = try? BibleReferenceStore(filePath: TranslationBootstrap.resolvedCurrentLanguageBundledDatabaseURL().path) {
            store = opened
            versionCode = nil
        } else {
            return nil
        }
        let end = target.verseEnd ?? target.verseStart
        var contents: [String] = []
        for number in target.verseStart...max(target.verseStart, end) {
            guard let verse = try? store.verse(bookId: target.bookId, chapter: target.chapter, verse: number, versionCode: versionCode) else { continue }
            let trimmed = verse.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { contents.append(trimmed) }
        }
        return contents.isEmpty ? nil : contents.joined(separator: " ")
    }
}
