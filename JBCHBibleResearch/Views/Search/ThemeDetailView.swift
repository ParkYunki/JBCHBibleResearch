import SwiftUI
import BibleResearchModels
#if os(iOS)
import UIKit
#endif

//
//  ThemeDetailView.swift
//  JBCHBibleResearch
//
//  [2026-09-15 신설, 2026-09-16 재작성] 통합검색의 "주제·속성" 카드 항목
//  하나의 상세 콘텐츠 — `PersonDetailView.swift`와 같은 배경(claude/bible-
//  research-platform-search-category-expansion-proposal.md, 참고 목업
//  "인물·주제 상세 화면")으로 만들었다.
//
//  [2026-09-16 재작성] `PersonDetailView.swift` 상단 주석과 정확히 같은 이유·
//  같은 구조 변경 — 통합검색 페이지 자체가 인물/주제/관계 카드로 전환되는
//  방식으로 바뀌면서, 이 타입도 더 이상 `NavigationLink`로 push되는 독립
//  화면이 아니라 `SearchContentView`의 `List`(또는 그 옆 상세 칼럼의 `List`)
//  안에 그대로 끼워 넣는 `Section` 묶음(`Group`)이 됐다. `.navigationTitle`도
//  함께 없앴다.
//
//  `ThemeRecord`에는 인물처럼 개요/생애/사건 같은 서술 섹션이 없고 대신
//  카테고리 배지·키워드·태그·관련 성경구절만 있다 — 이 화면이 `PersonDetailView`
//  보다 훨씬 단순한 것은 실수가 아니라 두 테이블의 컬럼 구조 자체가 다르기
//  때문이다(`ReferenceEntity.swift`의 Themes/Prophecies/TimelineEvents
//  MARK 주석 참고 — "같은 토픽이라서"가 아니라 "컬럼 구조가 다르기 때문에"
//  별도 타입).
//
//  [2026-09-16 재작성 2차] 사용자 요청 — "주제에 대한 화면레이아웃 디자인을
//  '인물' 검색 결과 화면 레이아웃 디자인과 동일하게 할 것." 기존엔 이
//  화면만 시스템 기본 `Section("제목")`(옅은 회색 캡션 헤더)과 파란/보라
//  계열 칩을 썼는데, `PersonDetailView`는 그 사이 "아이콘 + `.title3.
//  weight(.semibold)` 헤더 + 가죽 표지(wood) 톤 둥근 테두리 카드"
//  (`PersonDetailView.cardSection`)로 이미 통일돼 있었다 — 필드 구조가
//  다르다는 위 설명은 "무엇을 보여줄지"에만 해당하고 "어떻게 보여줄지"까지
//  달라야 할 이유는 아니어서, 아래 각 절을 `PersonDetailView`와 같은
//  카드 스타일로 다시 그렸다:
//  - 제목 폰트 크기를 `PersonDetailView.header`와 같은 28(세리프)로 맞춤.
//  - 카테고리 배지는 그대로 두되(어떤 주제인지 구분하는 이 화면 고유
//    정보) 임의 `Color.purple` 대신 브랜드 팔레트(`JBCHCategoryPalette.
//    wine`, 이 두 화면 어디에도 아직 쓰이지 않은 색이라 다른 배지와 뜻이
//    겹치지 않는다)로 바꿈.
//  - "설명"/"관련 키워드"/"태그" — `PersonDetailView.cardSection`과 똑같은
//    래퍼(아이콘+제목 헤더, wood 테두리 카드)로 감쌈. 키워드/태그 칩도
//    `PersonDetailView.header`의 직업 칩(`.caption2.weight(.bold)`, wood
//    15% 배경)과 같은 모양으로 맞추고, 태그는 겹치지 않게
//    `JBCHCategoryPalette.shelfSlate`를 씀.
//  - "관련 성경구절" — 기존 `BibleVerseChipRow`(단순 칩 나열) 대신
//    `PersonDetailView`가 쓰는 "책/장 카드 + N절) 본문(매달린 들여쓰기)"
//    스타일을 그대로 옮겨왔다(`groupedVerseReferences`/
//    `verseReferenceGroupCard`/`verseReferenceRow` — `PersonDetailView`의
//    동명 함수와 로직이 동일하다. 이 프로젝트가 이미 써온 "3곳 미만이면
//    짧게 복제" 관례를 따름 — 두 화면뿐이라 공용 컴포넌트로 새로 뽑아내는
//    것은 이번 요청 범위를 벗어난 근거 없는 리팩토링이 될 수 있어 하지
//    않았다).
//  - "설명" 절엔 `PersonDetailView`의 성경 인용 자동 링크
//    (`bibleReferenceLinkedText`)는 넣지 않았다 — 이번 요청은
//    "레이아웃"(카드/헤더/색)에 한정되고, 그 기능은 별도 로직(정규식
//    파싱+링크 처리) 이식이 필요해 사용자가 명시적으로 요청한 범위를
//    넘어서기 때문이다.
//
//  ⚠️ [미검증] 이 세션엔 Xcode가 없어 컴파일 확인을 못 했다 — `PersonDetailView.swift`
//  와 같은 caveat, 실기기 빌드 확인 필요.
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
            // [2026-09-16 재작성] `PersonDetailView`의 header 행과 같은
            // 좌우 여백(16) — 전부 0이면 제목이 화면 맨 왼쪽에 붙는다.
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

    /// `PersonDetailView.cardSection`과 동일 — 소제목마다 아이콘+`.title3.
    /// weight(.semibold)` 헤더 + wood 톤 둥근 테두리 카드로 감싼다.
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

    /// `PersonDetailView.header`의 직업 칩과 동일한 모양(`.caption2.weight(.bold)`
    /// + 가로 6/세로 2 패딩 + 15% 배경 캡슐) — 색만 매개변수로 받는다.
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
