//
//  OriginalWordOccurrencesView.swift
//  JBCHBibleResearch
//
//  [2026-11-02 interlin1] 원문 정보 → 원어 카드의 [돋보기 N절] → "이 단어가 쓰인 구절".
//  같은 Strong 번호가 쓰인 절을 성경 순서로 보여준다(모든 형태 포함). 구절을 누르면 원문 정보 시트를 닫고 성경 화면을 그 장·절로 옮긴다
//  (호출부 `OriginalTextInfoView.onOpenVerse` → `BibleReadingView`).
//
//  - 조회: `OriginalTextLookupService.occurrences(strongCode:)`(전체 스캔, Mac 측정 20~40ms) — 메인 스레드 밖(`Task.detached`).
//  - 본문 미리보기: 원문 정보 구절 카드와 같은 번역본 파일을 메인 스레드 밖에서 한 번 통째로 읽어(`allVerses`) 필요한 절만 남긴다.
//    절마다 `verse()`를 부르지 않는 이유(Mac 측정, 2,041절 기준): 번들 KRV(BibleDB.sqlite)는 절 조회가 인덱스를 못 타
//    7.2초가 걸렸고(다른 번들 성경은 0.2초), 전체 읽기는 어느 파일이든 0.03초 안팎이었다. 사용자 추가 번역본은 인덱스 유무를 알 수 없다.
//  - 목록은 `LazyVStack`으로 화면에 보이는 줄만 만든다(G3588은 7,061절).
//  - 머리: iOS는 이 화면이 내비게이션 스택에 push되고, macOS는 원문 정보 시트 안에서 본문 자리를 바꾼다. 두 곳 모두 이 화면이 직접
//    머리(‹ 원문 정보 · 제목)를 그린다(`VerseLayerHeader`, 책/장 선택 "‹ 책 목록"과 같은 방식).
//

import SwiftUI
import BibleResearchModels

struct OriginalWordOccurrencesView: View {
    /// 본문 미리보기에 쓸 번역본 파일. `translationCode`는 파일에 `version_code` 열이 있을 때 고를 번역본(`BibleReadingViewModel.store(for:)`와 같은 규칙).
    struct PreviewSource: Equatable {
        let filePath: String
        let translationCode: String
    }

    /// `.task(id:)` 키 — Strong 번호와 미리보기 번역본 중 하나라도 바뀌면 다시 읽는다.
    private struct LoadKey: Equatable {
        let strongCode: String
        let previewSource: PreviewSource?
    }

    let word: OriginalWordInfo
    /// 원문 정보 카드의 사전 뜻(앱 언어). 아직 없으면 nil("-").
    let gloss: String?
    /// 원문 정보 화면이 미리 센 절 수. 목록을 다 읽기 전까지 머리에 쓴다.
    let knownVerseCount: Int?
    let previewSource: PreviewSource?
    let onBack: () -> Void
    let onSelectVerse: (BibleVerseRef) -> Void

    private var settings: UserSettingsStore { .shared }
    @Environment(\.colorScheme) private var colorScheme

    private enum LoadState: Equatable {
        case loading
        case loaded
        case failed
    }

    /// 필터 칩 하나 — 책과 그 책에서 쓰인 절 수.
    private struct BookCount: Identifiable {
        let bookId: Int
        var count: Int
        var id: Int { bookId }
    }

    @State private var loadState: LoadState = .loading
    @State private var occurrences: [OriginalWordOccurrence] = []
    /// 책별 절 수(성경 순) — 필터 칩.
    @State private var bookCounts: [BookCount] = []
    @State private var previews: [BibleVerseRef: String] = [:]
    /// nil = 전체.
    @State private var selectedBookId: Int?

    private var linkTint: Color { Color.accentColor }
    private var textColor: Color { settings.bibleTextColor ?? Color.primary }
    private var secondaryTextColor: Color { settings.bibleTextColor?.opacity(0.6) ?? Color.secondary }

    private var filteredOccurrences: [OriginalWordOccurrence] {
        guard let selectedBookId else { return occurrences }
        return occurrences.filter { $0.bookId == selectedBookId }
    }

    private var verseCount: Int? {
        loadState == .loaded ? occurrences.count : knownVerseCount
    }

    var body: some View {
        // 단어 요약·책 칩은 위에 두고 목록만 스크롤한다. 목록(`LazyVStack`)을 `ScrollView`의 바로 아래 내용으로 둬야
        // 보이는 줄만 만든다(다른 스택 안에 넣지 않는다).
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 12) {
                summaryCard
                if loadState == .loaded, !occurrences.isEmpty {
                    bookChips
                }
            }
            .padding([.horizontal, .top], 16)
            .padding(.bottom, 12)
            ScrollView {
                content
                    .padding([.horizontal, .bottom], 16)
            }
        }
        .background(settings.bibleBackgroundColor ?? Color.clear)
        // 목록을 연 채로 미리보기 번역본이 바뀌어도 다시 읽도록 번역본도 키에 넣는다(2차 리뷰 B6).
        .task(id: LoadKey(strongCode: word.strongCode, previewSource: previewSource)) { await load() }
    }

    // MARK: - 머리

    #if os(iOS)
    private static let headerButtonStyle = BibleBarButtonStyle(height: 40, cornerRadius: 10, fontSize: 15)
    private static let headerTitleSize: CGFloat = 20
    #else
    private static let headerButtonStyle = BibleBarButtonStyle()
    private static let headerTitleSize: CGFloat = 17
    #endif

    private var header: some View {
        VerseLayerHeader(title: String(localized: "쓰인 구절"), titleSize: Self.headerTitleSize) {
            Button(action: onBack) {
                Label("원문 정보", systemImage: "chevron.left")
            }
            .buttonStyle(Self.headerButtonStyle)
            .accessibilityLabel("원문 정보로 돌아가기")
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(textColor.opacity(0.14)).frame(height: 1)
        }
    }

    // MARK: - 단어 요약

    private var summaryCard: some View {
        HStack(spacing: 12) {
            Text(word.originalText)
                .font(OriginalTextInfoView.originalTextFont(isHebrew: word.isHebrew, size: 26))
                .foregroundStyle(OriginalTextInfoView.originalTextColor(colorScheme: colorScheme))
                .fixedSize()
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(gloss ?? "-") · \(word.strongCode)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(textColor)
                    .fixedSize(horizontal: false, vertical: true)
                if let verseCount {
                    let countText = String(localized: "쓰인 구절 \(verseCount)절")
                    let formsText = String(localized: "모든 형태 포함")
                    Text(verbatim: "\(countText) · \(formsText)")
                        .font(.system(size: 12))
                        .foregroundStyle(secondaryTextColor)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(OriginalTextInfoView.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(OriginalTextInfoView.cardBorderColor, lineWidth: 1)
        )
    }

    // MARK: - 목록

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        case .failed:
            Text("쓰인 구절을 불러오지 못했습니다.")
                .font(.system(size: 13))
                .foregroundStyle(secondaryTextColor)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        case .loaded:
            if occurrences.isEmpty {
                Text("결과 없음")
                    .font(.system(size: 13))
                    .foregroundStyle(secondaryTextColor)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredOccurrences) { occurrence in
                        row(occurrence)
                    }
                }
                .background(OriginalTextInfoView.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(OriginalTextInfoView.cardBorderColor, lineWidth: 1)
                )
            }
        }
    }

    /// 성경책별 필터 칩. 책이 많으면(구약 39권 등) 여러 줄로 쌓이지 않게 가로로 넘겨 본다.
    private var bookChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                let allTitle = String(localized: "전체")
                chip(title: "\(allTitle) \(occurrences.count)", isSelected: selectedBookId == nil) {
                    selectedBookId = nil
                }
                ForEach(bookCounts) { entry in
                    let name = BooksProvider.shared.book(id: entry.bookId)?.displayName ?? "\(entry.bookId)"
                    chip(title: "\(name) \(entry.count)", isSelected: selectedBookId == entry.bookId) {
                        selectedBookId = entry.bookId
                    }
                }
            }
            .padding(.vertical, 1)
        }
    }

    /// 원문 정보 구절 카드의 번역본 칩(`sourceChip`)과 같은 모양.
    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minHeight: 30)
                .foregroundStyle(isSelected ? Color.white : textColor)
                .background(Capsule().fill(isSelected ? linkTint : OriginalTextInfoView.cardBackground))
                .overlay(Capsule().stroke(isSelected ? linkTint : OriginalTextInfoView.cardBorderColor, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func row(_ occurrence: OriginalWordOccurrence) -> some View {
        let ref = BibleVerseRef(bookId: occurrence.bookId, chapter: occurrence.chapter, verse: occurrence.verse)
        return Button {
            onSelectVerse(ref)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 8) {
                    Text(verbatim: referenceLabel(occurrence))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(linkTint)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        ForEach(Array(occurrence.forms.enumerated()), id: \.offset) { _, form in
                            Text(form)
                                .font(OriginalTextInfoView.originalTextFont(isHebrew: word.isHebrew, size: 15))
                                .foregroundStyle(OriginalTextInfoView.originalTextColor(colorScheme: colorScheme))
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(linkTint.opacity(0.12))
                                )
                        }
                    }
                }
                if let preview = previews[ref] {
                    Text(verbatim: preview)
                        .font(settings.bibleBodyFont)
                        .foregroundStyle(textColor.opacity(0.85))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(OriginalTextInfoView.cardBorderColor).frame(height: 1)
        }
    }

    /// 앱 언어 약칭 참조(예: ko "요1:1", en "John 1:1") — `Book.displayShortReference(chapter:)` + ":절"(`VerseZoomView` 관주 칩과 같은 규칙).
    private func referenceLabel(_ occurrence: OriginalWordOccurrence) -> String {
        let bookAndChapter = BooksProvider.shared.book(id: occurrence.bookId)?.displayShortReference(chapter: occurrence.chapter)
            ?? "\(occurrence.bookId) \(occurrence.chapter)"
        return "\(bookAndChapter):\(occurrence.verse)"
    }

    // MARK: - 읽기

    /// 1) 쓰인 절 목록 → 화면에 먼저 보인다. 2) 본문 미리보기 → 이어서 채운다. 둘 다 메인 스레드 밖에서 읽는다.
    /// `.task(id:)`라 화면이 사라지거나 단어가 바뀌면 취소되고, 늦게 끝난 결과는 버린다.
    private func load() async {
        let strongCode = word.strongCode
        loadState = .loading
        selectedBookId = nil
        previews = [:]
        let found = await Task.detached(priority: .userInitiated) {
            OriginalTextLookupService.occurrences(strongCode: strongCode)
        }.value
        guard !Task.isCancelled else { return }
        guard let found else {
            occurrences = []
            bookCounts = []
            loadState = .failed
            return
        }
        occurrences = found
        // `found`는 성경 순이라 같은 책이 붙어 있다.
        var counts: [BookCount] = []
        for occurrence in found {
            if let last = counts.last, last.bookId == occurrence.bookId {
                counts[counts.count - 1].count += 1
            } else {
                counts.append(BookCount(bookId: occurrence.bookId, count: 1))
            }
        }
        bookCounts = counts
        loadState = .loaded

        guard let previewSource, !found.isEmpty else { return }
        let refs = Set(found.map { BibleVerseRef(bookId: $0.bookId, chapter: $0.chapter, verse: $0.verse) })
        let filePath = previewSource.filePath
        let translationCode = previewSource.translationCode
        let loaded = await Task.detached(priority: .userInitiated) {
            Self.previewTexts(filePath: filePath, translationCode: translationCode, refs: refs)
        }.value
        guard !Task.isCancelled else { return }
        previews = loaded
    }

    /// 번역본 파일을 한 번 통째로 읽어 `refs`의 본문만 남긴다(맨 위 주석의 측정 참고). 실패하면 빈 결과(미리보기 없이 참조만).
    /// `nonisolated` — 이 뷰가 `@MainActor`라 없으면 `Task.detached` 안에서도 메인 액터로 돌아온다. 연결은 이 함수 안에서 열고 닫는다.
    private nonisolated static func previewTexts(filePath: String, translationCode: String, refs: Set<BibleVerseRef>) -> [BibleVerseRef: String] {
        do {
            let store = try BibleReferenceStore(filePath: filePath)
            let versionCode = store.hasVersionCodeColumn ? translationCode : nil
            var result: [BibleVerseRef: String] = [:]
            result.reserveCapacity(refs.count)
            for verse in try store.allVerses(versionCode: versionCode) {
                let ref = BibleVerseRef(bookId: verse.bookId, chapter: verse.chapter, verse: verse.verse)
                guard refs.contains(ref) else { continue }
                let text = verse.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { result[ref] = text }
            }
            return result
        } catch {
            print("[OriginalWordOccurrencesView] 본문 미리보기 조회 실패: \(error)")
            return [:]
        }
    }
}
