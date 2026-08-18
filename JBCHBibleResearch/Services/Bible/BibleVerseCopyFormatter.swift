//
//  BibleVerseCopyFormatter.swift
//  JBCHBibleResearch
//
//  S1(성경 조회) — 사용자 요청: "성경 구절을 클립보드에 복사할 수 있도록. 단일구절,
//  여러구절(이어져 있는 구절(1-5), 떨어져 있는 구절(1,3,5))을 복사하는 기능. 어떤
//  스타일로 복사할 것인지는 환경설정에 추가할 것." 참고 소스로 올려준
//  FormatTabView.swift의 항목/의미를 그대로 옮기되, 이 앱만의 차이 두 가지를
//  반영했다:
//  1. S1은 번역본을 최대 3개까지 나란히 볼 수 있어, 선택한 절을 여러 번역본에서
//     동시에 복사할 수 있다 — `copyTranslationLabelPosition`(원본엔 없던 설정)이
//     그 경우 번역본 이름표 위치를 정한다. 번역본이 1개뿐이면(여기선 "지금 복사에
//     실제로 포함되는 번역본 수" 기준) 이름표 자체를 안 붙인다.
//  2. 절 번호 스타일은 사용자 요청 예시 그대로 "(1) / [1] / 1)" 세 가지다(원본은
//     "1. "도 있었지만 요청 목록엔 없어 넣지 않았다).
//
//  ⚠️ [단순화, 플래그] 책 이름(약어/전체)은 항상 앱 기본 한글 이름
//  (`Book.nameKo`/`Book.abbreviation`)을 쓴다 — 번역본마다 다른 언어의 책이름표
//  (`BookNameTableProvider`, 예: 영어 번역본의 "Gen"/"Genesis")를 따로 쓰지
//  않는다. 사용자 요청 예시가 "[Gen 1:1]"/"[Genesis 1:1]"처럼 영어 표기도
//  들었지만, 이는 약어/전체 구분을 설명하기 위한 예시로 보여 실제 다국어 참조
//  요구까지는 아니라고 판단했다 — 필요하면 번역본별 언어를 따라가도록 확장할 수
//  있다(BookNameTableProvider가 이미 그 데이터를 갖고 있다).
//

import Foundation
import BibleResearchModels

@MainActor
enum BibleVerseCopyFormatter {
    /// 번역본 하나의 스냅샷 — `BibleReadingViewModel.ColumnState`를 그대로 쓰지
    /// 않고 얇은 구조체로 받는 이유는 이 포매터를 뷰모델 타입에 의존시키지 않기
    /// 위해서다(단위 테스트/재사용을 쉽게 하려는 목적, 이 세션은 실제 테스트를
    /// 돌릴 수 없지만 구조상 분리해 두는 게 맞다고 판단했다).
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
        // ⚠️ [수정] 기본 인자 표현식(`= .shared`)은 이 함수가 @MainActor로 격리돼
        // 있어도 항상 비격리(nonisolated) 컨텍스트에서 평가된다 — Swift 6
        // 언어 모드에서 "Main actor-isolated static property 'shared' can not
        // be referenced from a nonisolated context" 에러의 원인. 파라미터를
        // 옵셔널로 받고, 실제 격리된 함수 본문 안에서 `.shared`를 대신 채운다.
        let settings = settingsOverride ?? .shared
        guard !selectedVerses.isEmpty, !translations.isEmpty else { return nil }
        let sortedVerseNumbers = selectedVerses.sorted()
        let bookName = settings.copyUseAbbreviatedBookName
            ? (book.abbreviation.first ?? book.nameKo)
            : book.nameKo
        let bracket = settings.copyReferenceBracketStyle
        let rangeDescription = formatVerseRange(selectedVerses)

        // 번역본이 실제로 1개뿐이면(등록된 번역본 수와 무관하게, "지금 복사하는
        // 대상"이 1개면) 이름표 자체를 붙이지 않는다 — 요청의 "번역본이 한 개라면
        // 비활성화" 취지를 그대로 반영.
        let showTranslationLabel = translations.count > 1
        // [2026-08-08 추가] 사용자 요청 — "성경장절과 번역본이 동일하게 본문 앞/뒤에
        // 위치했을 때, 합쳐서 보일지 분리해서 보일지". 두 위치가 같을 때만 이
        // 병합 로직이 끼어든다 — 다르면(예: 번역본은 앞, 장절은 뒤) 원래대로 각자
        // 자리에 따로 놓인다(아래 `showTranslationLabel && !sameSide` 분기).
        let sameSide = settings.copyReferencePosition == settings.copyTranslationLabelPosition

        let blocks = translations.compactMap { translation -> String? in
            // 같은 쪽에 있을 때만 참조 문자열 자체에 번역본 이름을 끼워 넣는다
            // (`referenceText(...)`가 병합/분리 설정을 보고 처리) — 다른 쪽이면
            // nil을 넘겨 참조는 참조대로만 만들고, 아래에서 번역본 이름을 별도
            // 줄로 붙인다.
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

    /// 참조 브라켓 문자열 하나를 만든다. `combinedLabel`이 있으면(번역본 이름
    /// 위치가 참조 위치와 같을 때만 넘어온다) 사용자가 고른 방식대로 합치거나
    /// 나란히 붙인다 — 예: "[NKJV Genesis 1:1]"(합침, `copyCombineReferenceAndTranslationLabel
    /// == true`) 또는 "[NKJV][Genesis 1:1]"(분리, 같은 괄호 스타일로 각자
    /// 감싼 뒤 그대로 이어 붙인다).
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
                // FormatTabView.swift와 같은 원칙 — 절마다 장:절을 반복하는
                // 모드에서는 절 번호 표시가 중복이라 아예 건너뛴다.
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
