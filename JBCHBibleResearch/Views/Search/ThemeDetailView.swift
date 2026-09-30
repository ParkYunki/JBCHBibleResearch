import SwiftUI
import BibleResearchModels
#if os(iOS)
import UIKit
#endif

//
//  ThemeDetailView.swift
//  JBCHBibleResearch
//
//  통합검색의 "주제·속성" 카드 항목 하나의 상세 콘텐츠. `SearchContentView`의 `List`
//  (또는 상세 칼럼의 `List`)에 그대로 끼워 넣는 `Section` 묶음(`Group`)이라 독립 화면이
//  아니며 `.navigationTitle`도 없다. 레이아웃(카드/헤더/색)은 `PersonDetailView`와 동일.
//
//  `ThemeRecord`는 인물과 컬럼 구조가 달라(개요/생애/사건 없이 카테고리·키워드·태그·
//  관련 성경구절만 있음) 화면이 더 단순하다. `PersonDetailView`의 성경 인용 자동 링크는
//  이식하지 않았고, 관련 성경구절 로직은 두 화면뿐이라 공용 컴포넌트 없이 복제했다.
//
struct ThemeDetailView: View {
    let theme: ThemeRecord
    private var settings: UserSettingsStore { .shared }

    private var isPhoneIdiom: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    private var categoryLabel: String {
        switch theme.category {
        case "doctrine": return "교리"
        case "practice": return "실천"
        case "topic": return "주제"
        case "named_passage": return "지정 본문"
        default: return theme.category
        }
    }

    private var keywordList: [String] {
        (theme.searchKeywords ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var tagList: [String] {
        (theme.tags ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        Group {
            Section {
                header
            }
            // `PersonDetailView`의 header 행과 같은 좌우 여백(16) — 0이면 제목이 화면 왼쪽에 붙는다.
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if let description = theme.themeDescription, !description.isEmpty {
                cardSection("설명", icon: "doc.text.fill") {
                    Text(description).font(.body)
                }
            }
            if !keywordList.isEmpty {
                cardSection("관련 키워드", icon: "tag.fill") {
                    chipRow(keywordList, tint: JBCHCategoryPalette.wood)
                }
            }
            if !tagList.isEmpty {
                cardSection("태그", icon: "number") {
                    chipRow(tagList, tint: JBCHCategoryPalette.shelfSlate)
                }
            }
            if !groupedVerseReferences.isEmpty {
                Section {
                    ForEach(groupedVerseReferences) { group in
                        verseReferenceGroupCard(group)
                    }
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text("관련 성경구절")
                            .font(.title3.weight(.semibold))
                    }
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
                    .textCase(nil)
                    .padding(.leading, 16)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(theme.title)
                    .font(.custom(SpecialPurposeFonts.titleSerif, size: 28, relativeTo: .largeTitle))
                    .fontWeight(.bold)
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
                Spacer(minLength: 0)
            }
            Text(categoryLabel)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(JBCHCategoryPalette.wine.opacity(0.15), in: Capsule())
                .foregroundStyle(JBCHCategoryPalette.wine)
        }
        .padding(.vertical, 6)
    }

    /// `PersonDetailView.cardSection`과 동일 — 아이콘+제목 헤더 + wood 톤 둥근 테두리 카드.
    @ViewBuilder
    private func cardSection<Content: View>(
        _ title: String, icon: String, @ViewBuilder content: () -> Content
    ) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill((settings.bibleTextColor ?? .primary).opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(JBCHCategoryPalette.wood.opacity(0.3), lineWidth: 1)
            )
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } header: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.title3.weight(.semibold))
            }
            .foregroundStyle(settings.bibleTextColor ?? .primary)
            .textCase(nil)
            .padding(.leading, 16)
        }
    }

    /// `PersonDetailView.header`의 직업 칩과 같은 모양 — 색만 매개변수로 받는다.
    private func chipRow(_ items: [String], tint: Color) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(tint.opacity(0.15), in: Capsule())
                        .foregroundStyle(tint)
                }
            }
        }
    }

    // MARK: - 관련 성경구절 (`PersonDetailView`와 동일 로직 — 상단 주석 참고)

    private struct VerseReferenceGroup: Identifiable {
        let bookId: Int
        let chapter: Int
        let bookNameKo: String
        let verses: [(verse: Int, content: String)]
        var id: String { "\(bookId)-\(chapter)" }
    }

    private var groupedVerseReferences: [VerseReferenceGroup] {
        guard let store = try? BibleReferenceStore(filePath: TranslationBootstrap.resolvedBundledDatabaseURL().path) else {
            return []
        }
        var versesByChapter: [String: (bookId: Int, chapter: Int, bookNameKo: String, verses: [(Int, String)])] = [:]
        var orderedKeys: [String] = []
        for ref in theme.verseRefs.prefix(30) {
            guard let verse = try? store.verse(bookId: ref.bookId, chapter: ref.chapter, verse: ref.verse) else { continue }
            let key = "\(ref.bookId)-\(ref.chapter)"
            if versesByChapter[key] == nil {
                let bookName = BooksProvider.shared.book(id: ref.bookId)?.nameKo ?? "책 \(ref.bookId)"
                versesByChapter[key] = (ref.bookId, ref.chapter, bookName, [])
                orderedKeys.append(key)
            }
            versesByChapter[key]?.verses.append((verse.verse, verse.content))
        }
        let groups = orderedKeys.compactMap { key -> VerseReferenceGroup? in
            guard let g = versesByChapter[key] else { return nil }
            return VerseReferenceGroup(
                bookId: g.bookId, chapter: g.chapter, bookNameKo: g.bookNameKo,
                verses: g.verses.sorted { $0.0 < $1.0 }
            )
        }
        return groups.sorted { ($0.bookId, $0.chapter) < ($1.bookId, $1.chapter) }
    }

    @ViewBuilder
    private func verseReferenceRow(group: VerseReferenceGroup, verse: (verse: Int, content: String)) -> some View {
        let label = HStack(alignment: .top, spacing: 0) {
            Text("\(verse.verse)절) ")
                .font(.body)
                .foregroundStyle(settings.bibleTextColor ?? .primary)
                .fixedSize()
            Text(verse.content)
                .font(.body)
                .foregroundStyle(settings.bibleTextColor ?? .primary)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if isPhoneIdiom {
            Button {
                AppNavigationRequest.shared.request(.bibleReading)
                BibleVerseNavigationRequest.shared.request(bookId: group.bookId, chapter: group.chapter, verse: verse.verse)
            } label: {
                label
            }
            .buttonStyle(.plain)
            .padding(.vertical, 2)
        } else {
            NavigationLink(value: BibleVerseDestination(bookId: group.bookId, chapter: group.chapter, verse: verse.verse)) {
                label
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func verseReferenceGroupCard(_ group: VerseReferenceGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
                    .frame(width: 18)
                Text("\(group.bookNameKo) \(group.chapter)장")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text("\(group.verses.count)절")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
            ForEach(Array(group.verses.enumerated()), id: \.offset) { _, verse in
                verseReferenceRow(group: group, verse: verse)
            }
        }
        .padding(.horizontal, 25)
        .padding(.vertical, 10)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(JBCHCategoryPalette.wood.opacity(0.3), lineWidth: 1)
        )
        .padding(.vertical, 5)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
    }
}
