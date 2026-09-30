//
//  BibleVerseCopyFormatter.swift
//  JBCHBibleResearch
//
//  S1(성경 조회)에서 선택한 절을 환경설정의 복사 형식에 맞춰 클립보드용 문자열로 만든다.
//  단일 절, 이어진 절(1-5), 떨어진 절(1,3,5)을 지원하며, 이 앱만의 차이는 두 가지다.
//  1. S1은 번역본을 최대 3개까지 나란히 볼 수 있어 여러 번역본을 동시에 복사할 수 있다 —
//     `copyTranslationLabelPosition`이 번역본 이름표 위치를 정하고, 복사에 포함되는 번역본이 1개뿐이면 이름표를 붙이지 않는다.
//  2. 절 번호 스타일은 "(1) / [1] / 1)" 세 가지다.
//
//  ⚠️ 책 이름(약어/전체)은 항상 앱 기본 한글 이름(`Book.nameKo`/`Book.abbreviation`)을 쓴다 —
//  번역본별 언어의 책이름표(`BookNameTableProvider`)는 따르지 않는다. 필요하면 번역본 언어를 따라가도록 확장할 수 있다.
//

import Foundation
import BibleResearchModels

@MainActor
enum BibleVerseCopyFormatter {
    /// 번역본 하나의 스냅샷. 포매터가 뷰모델 타입(`BibleReadingViewModel.ColumnState`)에 의존하지 않도록
    /// 얇은 구조체로 받는다.
    struct TranslationSnapshot {
        let displayName: String
        let verses: [BibleVerse]

        init(displayName: String, verses: [BibleVerse]) {
            self.displayName = displayName
            self.verses = verses
        }
    }

    /// 선택된 절들을 환경설정(`UserSettingsStore`)의 복사 형식대로 하나의
    /// 문자열로 합친다. 선택이 비었거나 번역본이 하나도 없으면 nil.
    static func format(
        book: Book,
        chapter: Int,
        selectedVerses: Set<Int>,
        translations: [TranslationSnapshot],
        settings settingsOverride: UserSettingsStore? = nil
    ) -> String? {
        // 기본 인자 표현식(`= .shared`)은 @MainActor 함수여도 비격리 컨텍스트에서 평가되어 Swift 6에서
        // "Main actor-isolated static property 'shared' can not be referenced from a nonisolated context"
        // 에러가 난다 — 그래서 옵셔널로 받고 함수 본문 안에서 `.shared`를 채운다.
        let settings = settingsOverride ?? .shared
        guard !selectedVerses.isEmpty, !translations.isEmpty else { return nil }
        let sortedVerseNumbers = selectedVerses.sorted()
        let bookName = settings.copyUseAbbreviatedBookName
            ? (book.abbreviation.first ?? book.nameKo)
            : book.nameKo
        let bracket = settings.copyReferenceBracketStyle
        let rangeDescription = formatVerseRange(selectedVerses)

        // 복사 대상 번역본이 1개뿐이면(등록된 번역본 수와 무관) 이름표를 붙이지 않는다.
        let showTranslationLabel = translations.count > 1
        // 장절 위치와 번역본 이름 위치가 같을 때만 둘을 병합/분리하는 로직이 끼어든다 —
        // 다르면 각자 자리에 따로 놓인다(아래 `showTranslationLabel && !sameSide` 분기).
        let sameSide = settings.copyReferencePosition == settings.copyTranslationLabelPosition

        let blocks = translations.compactMap { translation -> String? in
            // 같은 쪽일 때만 참조 문자열 안에 번역본 이름을 끼워 넣는다(`referenceText`가 병합/분리 처리) —
            // 다른 쪽이면 nil을 넘기고 아래에서 번역본 이름을 별도 줄로 붙인다.
            let combinedLabel = (showTranslationLabel && sameSide) ? translation.displayName : nil
            let wholeReference = referenceText(
                bookName: bookName, chapter: chapter, verseText: rangeDescription,
                bracket: bracket, combinedLabel: combinedLabel, settings: settings
            )
            let body = formattedBody(
                for: translation, selectedVerseNumbers: sortedVerseNumbers,
                bookName: bookName, chapter: chapter, bracket: bracket,
                wholeReference: wholeReference, combinedLabel: combinedLabel, settings: settings
            )
            guard let body else { return nil }
            guard showTranslationLabel, !sameSide else { return body }
            return settings.copyTranslationLabelPosition == .beforeBody
                ? "\(translation.displayName)\n\(body)"
                : "\(body)\n\(translation.displayName)"
        }
        guard !blocks.isEmpty else { return nil }
        return blocks.joined(separator: "\n\n")
    }

    /// 참조 브라켓 문자열 하나를 만든다. `combinedLabel`이 있으면(번역본 이름 위치가 참조 위치와 같을 때만 전달)
    /// 설정대로 합치거나("[NKJV Genesis 1:1]") 각자 감싸 이어 붙인다("[NKJV][Genesis 1:1]").
    private static func referenceText(
        bookName: String, chapter: Int, verseText: String,
        bracket: UserSettingsStore.ReferenceBracketStyle,
        combinedLabel: String?,
        settings: UserSettingsStore
    ) -> String {
        let plainReference = "\(bracket.prefix)\(bookName) \(chapter):\(verseText)\(bracket.suffix)"
        guard let combinedLabel else { return plainReference }
        if settings.copyCombineReferenceAndTranslationLabel {
            return "\(bracket.prefix)\(combinedLabel) \(bookName) \(chapter):\(verseText)\(bracket.suffix)"
        }
        return "\(bracket.prefix)\(combinedLabel)\(bracket.suffix)\(plainReference)"
    }

    private static func formattedBody(
        for translation: TranslationSnapshot,
        selectedVerseNumbers: [Int],
        bookName: String,
        chapter: Int,
        bracket: UserSettingsStore.ReferenceBracketStyle,
        wholeReference: String,
        combinedLabel: String?,
        settings: UserSettingsStore
    ) -> String? {
        let byNumber = Dictionary(uniqueKeysWithValues: translation.verses.map { ($0.verse, $0) })
        let selected = selectedVerseNumbers.compactMap { byNumber[$0] }
        guard !selected.isEmpty else { return nil }

        if settings.copyNewlineBetweenVerses {
            if settings.copyRepeatReferenceForEachVerse {
                // 절마다 장:절을 반복하는 모드에서는 절 번호 표시가 중복이라 건너뛴다.
                let lines = selected.map { verse -> String in
                    let ref = referenceText(
                        bookName: bookName, chapter: chapter, verseText: "\(verse.verse)",
                        bracket: bracket, combinedLabel: combinedLabel, settings: settings
                    )
                    return settings.copyReferencePosition == .beforeBody
                        ? "\(ref) \(verse.content)"
                        : "\(verse.content) \(ref)"
                }
                return lines.joined(separator: "\n")
            }
            let lines = selected.enumerated().map { index, verse in
                versePrefix(at: index, verseNumber: verse.verse, settings: settings) + verse.content
            }
            let content = lines.joined(separator: "\n")
            return settings.copyReferencePosition == .beforeBody
                ? "\(wholeReference)\n\(content)"
                : "\(content)\n\(wholeReference)"
        }

        let parts = selected.enumerated().map { index, verse in
            versePrefix(at: index, verseNumber: verse.verse, settings: settings) + verse.content
        }
        let content = parts.joined(separator: " ")
        return settings.copyReferencePosition == .beforeBody
            ? "\(wholeReference) \(content)"
            : "\(content) \(wholeReference)"
    }

    /// `index`는 "지금 복사 중인 선택 구간 안에서의 순번"(0부터) — 첫 번째 구절
    /// 번호 표시 여부(`copyShowFirstVerseNumber`)가 이 순번을 기준으로 한다.
    private static func versePrefix(at index: Int, verseNumber: Int, settings: UserSettingsStore) -> String {
        guard settings.copyShowVerseNumbers else { return "" }
        guard index > 0 || settings.copyShowFirstVerseNumber else { return "" }
        return settings.copyVerseNumberStyle.format(verseNumber) + " "
    }

    /// "이어져 있는 구절(1-5)"과 "떨어져 있는 구절(1,3,5)"을 모두 표현한다 —
    /// 정렬된 절 번호를 연속 구간으로 묶어 구간은 "시작-끝", 구간 사이는 쉼표로
    /// 잇는다(예: {1,2,3,5,7,8} → "1-3,5,7-8"). 단일 절이면 그 번호 하나만
    /// 반환한다(예: {5} → "5").
    static func formatVerseRange(_ verseNumbers: Set<Int>) -> String {
        let sorted = verseNumbers.sorted()
        guard let first = sorted.first else { return "" }
        var groups: [[Int]] = [[first]]
        for verse in sorted.dropFirst() {
            if verse == groups[groups.count - 1].last! + 1 {
                groups[groups.count - 1].append(verse)
            } else {
                groups.append([verse])
            }
        }
        return groups.map { group -> String in
            guard let groupFirst = group.first, let groupLast = group.last else { return "" }
            return group.count == 1 ? "\(groupFirst)" : "\(groupFirst)-\(groupLast)"
        }.joined(separator: ",")
    }
}
