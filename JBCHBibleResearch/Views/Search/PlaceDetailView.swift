import SwiftUI
import BibleResearchModels
#if os(iOS)
import UIKit
#endif

//
//  PlaceDetailView.swift
//  JBCHBibleResearch
//
//  통합검색 "장소" 항목 하나의 상세 페이지(2026-10-01 신설, PlaceSeed.json 기반).
//  구성: 머리(이름·한 줄 설명) → 개요(소개) → 성경 내용 → 지리 → 역사 → 같은 이름의 다른 지명 → 관련 성경구절.
//  본문 4개 칸은 데이터가 없거나 "기록 없음"만 있으면 "-"로 보인다(빌드가 "-"로 저장, 빈 문자열이 와도 "-"로 보정).
//
//  `PersonDetailView`와 같은 방식이다 — `body`는 `List`를 갖지 않고 `Section` 묶음(`Group`)만 돌려주며,
//  `SearchContentView`가 자신의 `List`에 끼우거나 상세 칼럼의 `List`로 감싼다. `.searchable` 화면에서
//  push(`NavigationLink(value:)`)는 아이폰에서 구조적 결함이 있어 쓰지 않고, 같은 이름의 다른 지명으로 이동할 때는
//  로컬 스택(`switchedPlaces`)만 갈아 끼운다. 성경 인용/관련 구절 처리는 `PersonDetailView`/`ThemeDetailView`와 같은
//  로직을 복제했다(그쪽이 `private`이라 재사용할 수 없음).
//
//  동명 지명(68개 표제어)은 이름이 아니라 `idx`로 구분한다. 이 화면이 받는 `PlaceEntity`는 이미 idx로 확정된 한 곳이며,
//  "같은 이름의 다른 지명" 절은 `ReferenceDataStore.placesSharingName`으로 나머지 곳을 보여준다.
//
struct PlaceDetailView: View {
    private let initialPlace: PlaceEntity
    /// 같은 이름의 다른 지명으로 넘어온 상태. 맨 위가 지금 보이는 지명이다.
    @State private var switchedPlaces: [PlaceEntity] = []

    init(place: PlaceEntity) {
        self.initialPlace = place
    }

    private var place: PlaceEntity { switchedPlaces.last ?? initialPlace }

    private var settings: UserSettingsStore { .shared }

    /// [relverse1 2026-10-29] 구절 열기(`BibleVerseOpener`) — 맥·아이패드는 그 구절이 열린 성경 새 창, 아이폰과 다중 창을 못 쓰는 환경은
    /// "성경 조회" 섹션 전환. 예전에는 맥·아이패드가 `NavigationLink(value:)` push였는데, 한 `List` 행(장 카드/칩 줄) 안에 링크가 여러 개라
    /// 탭 대상이 불안정했고(`OutlineTreeView`·`SearchView.groupedVerseRow` 주석의 같은 문제), 아이패드에서는 push된 `BibleReadingView`가
    /// 내비게이션 바를 숨겨 뒤로 버튼도 없었다.
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    /// [relverse2] 이 화면이 들어 있는 메인 창 — 새 성경 창의 [메인 창으로]가 이 창을 앞으로 가져온다.
    @Environment(\.mainWindowID) private var mainWindowID

    private var verseOpener: BibleVerseOpener {
        BibleVerseOpener(openWindow: openWindow, supportsMultipleWindows: supportsMultipleWindows, originWindowID: mainWindowID)
    }

    /// 빈 값이면 "-". (빌드 산출물은 이미 "-"지만, 예전 DB를 쓰는 경우에도 같은 모양으로 보이게 한다.)
    private func display(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "-" : trimmed
    }

    /// 같은 이름의 다른 지명들(idx 오름차순). 이 지명 자신은 뺀다.
    private var sameNamePlaces: [PlaceEntity] {
        guard let store = ReferenceDataProvider.shared.store else { return [] }
        return (try? store.placesSharingName(word: place.word, excludingIdx: place.idx)) ?? []
    }

    // MARK: - 성경 인용 링크 (PersonDetailView와 같은 로직)

    private struct BibleReferenceLinkGroup {
        let range: Range<String.Index>
        let bookId: Int
        let chapter: Int
        let verse: Int
    }

    /// `BibleReferenceExtractor`는 범위 인용("창세기 9:22-25")을 절마다 Match로 펼치되 모두 같은 `range`를 공유하므로,
    /// 연속으로 같은 `range`인 Match를 한 그룹으로 묶어 링크 하나(첫 절)만 만든다.
    private func bibleReferenceLinkGroups(in text: String) -> [BibleReferenceLinkGroup] {
        var groups: [BibleReferenceLinkGroup] = []
        for match in BibleReferenceExtractor.extract(from: text) {
            if let last = groups.last, last.range == match.range { continue }
            // 절 없는 인용("창세기 17장")은 `verse`가 nil이라 1절로 이동한다.
            groups.append(BibleReferenceLinkGroup(
                range: match.range, bookId: match.bookId, chapter: match.chapter, verse: match.verse ?? 1
            ))
        }
        return groups
    }

    private func abbreviatedCitationLabel(_ matchedText: String, bookId: Int) -> String {
        guard let firstDigitIndex = matchedText.firstIndex(where: { $0.isNumber }) else { return matchedText }
        let book = BooksProvider.shared.book(id: bookId)
        let abbreviation = book?.displayShortName
            ?? matchedText[..<firstDigitIndex].trimmingCharacters(in: .whitespaces)
        return "\(abbreviation) \(matchedText[firstDigitIndex...])"
    }

    /// 본문 중 성경 인용 부분만 약어 + 탭하면 이동하는 링크로 바꾼 `Text`. 인용이 없으면 원문 그대로.
    private func bibleReferenceLinkedText(_ text: String) -> Text {
        let groups = bibleReferenceLinkGroups(in: text)
        guard !groups.isEmpty else { return Text(text) }
        var result = AttributedString()
        var cursor = text.startIndex
        for group in groups {
            if cursor < group.range.lowerBound {
                result += AttributedString(String(text[cursor..<group.range.lowerBound]))
            }
            let matchedText = String(text[group.range])
            var linked = AttributedString("📖 " + abbreviatedCitationLabel(matchedText, bookId: group.bookId))
            linked.link = URL(string: "bibleref:///\(group.bookId)/\(group.chapter)/\(group.verse)")
            linked.font = .footnote.weight(.semibold)
            linked.foregroundColor = JBCHCategoryPalette.gold
            linked.backgroundColor = JBCHCategoryPalette.gold.opacity(0.15)
            result += linked
            cursor = group.range.upperBound
        }
        if cursor < text.endIndex {
            result += AttributedString(String(text[cursor...]))
        }
        return Text(result)
    }

    /// `bibleref:///책ID/장/절` 링크를 `verseOpener`로 연다(맥·아이패드 성경 새 창, 아이폰과 다중 창을 못 쓰는 환경은 성경 탭 전환).
    private func handleBibleReferenceLink(_ url: URL) -> OpenURLAction.Result {
        guard url.scheme == "bibleref" else { return .systemAction }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 3,
              let bookId = Int(parts[0]), let chapter = Int(parts[1]), let verse = Int(parts[2]) else {
            return .systemAction
        }
        // [relverse1] 맥·아이패드는 성경 새 창, 아이폰과 다중 창을 못 쓰는 환경은 섹션 전환(`BibleVerseOpener`).
        verseOpener.open(bookId: bookId, chapter: chapter, verse: verse)
        return .handled
    }

    // MARK: - 관련 성경구절 (PersonDetailView와 같은 로직)

    private struct VerseReferenceGroup: Identifiable {
        let bookId: Int
        let chapter: Int
        let bookNameKo: String
        let verses: [(verse: Int, content: String)]
        var id: String { "\(bookId)-\(chapter)" }
    }

    /// `place.verseRefs`를 절 본문과 함께 책/장 단위로 묶는다(정경순). 다른 화면과 같은 이유로 30개에서 자른다.
    private var groupedVerseReferences: [VerseReferenceGroup] {
        // 앱 언어의 기본 번들 성경으로 보여준다(2026-10-12, `BundledTranslationCatalog.current`).
        guard let store = try? BibleReferenceStore(filePath: TranslationBootstrap.resolvedCurrentLanguageBundledDatabaseURL().path) else {
            return []
        }
        var versesByChapter: [String: (bookId: Int, chapter: Int, bookNameKo: String, verses: [(Int, String)])] = [:]
        var orderedKeys: [String] = []
        for ref in place.verseRefs.prefix(30) {
            guard let verse = try? store.verse(bookId: ref.bookId, chapter: ref.chapter, verse: ref.verse) else { continue }
            let key = "\(ref.bookId)-\(ref.chapter)"
            if versesByChapter[key] == nil {
                let bookName = BooksProvider.shared.book(id: ref.bookId)?.displayName ?? String(localized: "책 \(ref.bookId)")
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
        // [relverse1] plain 버튼은 그려진 글자만 탭을 받으므로, 줄 끝 빈 공간까지 탭 영역으로 넓힌다.
        .contentShape(Rectangle())

        // 절마다 독립된 plain `Button` — 한 행(장 카드)에 여러 개가 있어도 누른 절만 동작한다.
        Button {
            verseOpener.open(bookId: group.bookId, chapter: group.chapter, verse: verse.verse)
        } label: {
            label
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
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

    // MARK: - 카드 뼈대

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

    /// 본문 카드 하나 — 값이 "-"면 인용 링크 처리 없이 그대로 "-"를 보여준다.
    @ViewBuilder
    private func textCard(_ title: String, icon: String, text: String) -> some View {
        let value = display(text)
        cardSection(title, icon: icon) {
            if value == "-" {
                Text("-")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                bibleReferenceLinkedText(value).font(.body)
            }
        }
    }

    // MARK: - 본문

    var body: some View {
        let sameName = sameNamePlaces
        Group {
            if !switchedPlaces.isEmpty {
                Section {
                    Button {
                        switchedPlaces.removeLast()
                    } label: {
                        Label("이전 지명으로", systemImage: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                header(sameNameCount: sameName.count)
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            textCard(String(localized: "detail.overview", defaultValue: "개요", comment: "인물·지명 상세 카드 — 소개(성경 개요 화면과 구분)"), icon: "doc.text.fill", text: place.displayIntroduce)
            textCard(String(localized: "성경 속 이야기"), icon: "book.fill", text: place.displayBibleContents)
            textCard(String(localized: "지리"), icon: "map.fill", text: place.displayGeography)
            textCard(String(localized: "역사"), icon: "clock.fill", text: place.displayHistory)

            if !sameName.isEmpty {
                cardSection(String(localized: "같은 이름의 다른 지명"), icon: "mappin.and.ellipse") {
                    ForEach(Array(sameName.enumerated()), id: \.element.idx) { index, other in
                        Button {
                            switchedPlaces.append(other)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                // 표시만 번역(`display*`). 묶음(`sameNamePlaces`)은 한국어 `word` 기준 그대로다.
                                Text(other.displayRemark.isEmpty ? other.displayWord : other.displayRemark)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(JBCHCategoryPalette.slateTeal)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 2)
                        if index < sameName.count - 1 {
                            Rectangle()
                                .fill((settings.bibleTextColor ?? .primary).opacity(0.12))
                                .frame(height: 0.75)
                        }
                    }
                }
            }

            let verseGroups = groupedVerseReferences
            if !verseGroups.isEmpty {
                Section {
                    ForEach(verseGroups) { group in
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
                // [relverse1] 맥/아이패드 split 상세(`SearchView.macSplitCardLayout`)의 `List`는 바깥 `cardSectionWrapper`가 없어
                // 행 배경이 시스템 기본(흰색/검정)으로 남는다. 위 `cardSection`들처럼 이 절도 직접 투명으로 둔다.
                .listRowBackground(Color.clear)
            }
        }
        .environment(\.openURL, OpenURLAction(handler: handleBibleReferenceLink))
        // 새 검색으로 다른 지명이 들어오면(`initialPlace.idx` 변경) 이전 이동 기록을 비운다.
        .onChange(of: initialPlace.idx) { _, _ in
            switchedPlaces.removeAll()
        }
    }

    private func header(sameNameCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title2)
                    .foregroundStyle(JBCHCategoryPalette.wood)
                // [2026-10-22] 제목·한 줄 설명은 번역 표시(한국어 앱이면 원본 그대로). 글꼴은 실제로 그리는 문자열로 고른다.
                Text(place.displayWord)
                    .font(.titleSerif(place.displayWord, size: 28, relativeTo: .largeTitle))
                    .fontWeight(.bold)
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
                Spacer(minLength: 0)
            }
            if sameNameCount > 0 {
                // 이름이 같은 지명이 더 있다는 표시 — 아래 "같은 이름의 다른 지명"에서 이동한다.
                Text("같은 이름의 지명 \(sameNameCount + 1)곳 중 하나")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(JBCHCategoryPalette.wood.opacity(0.15), in: Capsule())
                    .foregroundStyle(JBCHCategoryPalette.wood)
            }
            if !place.displayRemark.isEmpty {
                Text(place.displayRemark)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
