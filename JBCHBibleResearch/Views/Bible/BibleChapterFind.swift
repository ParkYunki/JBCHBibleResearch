//
//  BibleChapterFind.swift
//  JBCHBibleResearch
//
//  성경 조회 "본문에서 찾기"(⌘F) — 통합검색(`SearchView`)과 달리 지금 화면에 열린 장의 본문 안에서만 찾는다.
//
//  왜 시스템 찾기 막대가 아닌가: 성경 본문은 `NSTextView`가 아니라 SwiftUI `Text`(`LazyVStack` 안의 `VerseRow`)로 그려져
//  AppKit의 찾기 막대/`.findNavigator`가 붙을 수 없다. 그래서 직접 찾기 막대를 두고 다음 방식으로 동작한다.
//  - 대상: 이 창에 열린 모든 번역본 컬럼의 절 본문(`BibleVerse.content`). 대소문자·악센트를 무시하고 부분 문자열로 찾는다.
//  - 표시: 일치한 절 행의 배경을 옅게 칠하고, 지금 보는 일치 절은 더 진하게 + 테두리를 그린다(글자 단위 강조는 하지 않는다 —
//    본문이 형광펜/한자/난외주 경로로 나뉘어 그려지고 캐시되므로 그 경로를 건드리지 않기 위함).
//  - 이동: 다음/이전 일치 절로 이동할 때 기존 `highlightVerseTemporarily`(검색 결과 이동과 같은 경로)로 모든 컬럼을 그 절로 스크롤한다.
//  - 상태는 창마다 따로다(`BibleReadingContentView`의 `@State`) — 다른 성경 조회 창으로 번지지 않는다.

import SwiftUI
import SwiftData
import BibleResearchModels

/// 찾기 상태와 일치 계산. 한 장(최대 176절) × 컬럼 3개 이하라 입력할 때마다 전부 다시 계산해도 비용이 작다.
@Observable
final class BibleChapterFindModel {
    /// 찾기 막대 표시 여부.
    var isPresented = false
    /// 입력한 찾을 말(그대로). 계산에는 앞뒤 공백을 뗀 값을 쓴다.
    var query = ""

    /// 일치한 절 번호(오름차순, 컬럼 합집합). 같은 절 번호는 어느 컬럼에서도 같은 절이다.
    private(set) var matchedVerses: [Int] = []
    /// `matchedVerses`에서 지금 보고 있는 위치.
    private(set) var currentIndex = 0
    /// 컬럼별 일치 절 — 컬럼마다 번역이 달라 일치하는 절이 다를 수 있어 따로 둔다.
    private var versesByColumn: [UUID: Set<Int>] = [:]
    /// ⌘F를 다시 눌렀을 때 입력창에 포커스를 돌려주기 위한 카운터.
    private(set) var focusToken = 0

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var currentVerse: Int? {
        matchedVerses.indices.contains(currentIndex) ? matchedVerses[currentIndex] : nil
    }

    /// 이 컬럼에서 일치한 절 번호 집합.
    func matchedVerses(in columnID: UUID) -> Set<Int> {
        guard isPresented else { return [] }
        return versesByColumn[columnID] ?? []
    }

    func present() {
        isPresented = true
        focusToken += 1
    }

    /// 막대를 닫고 찾을 말과 강조를 모두 지운다.
    func close() {
        isPresented = false
        query = ""
        reset()
    }

    private func reset() {
        matchedVerses = []
        currentIndex = 0
        versesByColumn = [:]
    }

    /// 찾을 말이나 표시 중인 장/번역본이 바뀔 때 호출한다. 지금 보던 절이 아직 일치하면 그 위치를 유지해 입력을 이어 칠 때 튀지 않게 한다.
    func recompute(columns: [BibleReadingViewModel.ColumnState]) {
        let needle = trimmedQuery
        guard isPresented, !needle.isEmpty else {
            reset()
            return
        }
        let previousVerse = currentVerse
        var byColumn: [UUID: Set<Int>] = [:]
        var union = Set<Int>()
        for column in columns {
            var matched = Set<Int>()
            for verse in column.verses
            where verse.content.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                matched.insert(verse.verse)
            }
            byColumn[column.id] = matched
            union.formUnion(matched)
        }
        let sorted = union.sorted()
        versesByColumn = byColumn
        matchedVerses = sorted
        if let previousVerse, let index = sorted.firstIndex(of: previousVerse) {
            currentIndex = index
        } else {
            currentIndex = 0
        }
    }

    /// 다음 일치 절(끝에서 처음으로 돌아간다). 일치가 없으면 아무 것도 하지 않는다.
    func next() {
        guard !matchedVerses.isEmpty else { return }
        currentIndex = (currentIndex + 1) % matchedVerses.count
    }

    func previous() {
        guard !matchedVerses.isEmpty else { return }
        currentIndex = (currentIndex - 1 + matchedVerses.count) % matchedVerses.count
    }
}

/// 본문 위에 끼우는 찾기 막대(레이아웃 안의 한 줄 — 겹쳐 그리지 않아 상단 바/레일과 충돌하지 않는다).
struct BibleChapterFindBar: View {
    @Bindable var model: BibleChapterFindModel
    var onNext: () -> Void
    var onPrevious: () -> Void

    @FocusState private var isFieldFocused: Bool
    private var settings: UserSettingsStore { .shared }

    var body: some View {
        let textColor = settings.bibleTextColor ?? .primary
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(textColor.opacity(0.6))
            TextField("본문에서 찾기", text: $model.query)
                .textFieldStyle(.plain)
                .foregroundStyle(textColor)
                .focused($isFieldFocused)
                // Return = 다음, Shift+Return = 이전, Esc = 닫기(표준 찾기 막대 관례).
                // 키 하나만 받는 `onKeyPress(_:action:)`는 `KeyPress`(수식키)를 주지 않아 `keys:` 형태를 쓴다.
                .onKeyPress(keys: [.return], phases: .down) { press in
                    if press.modifiers.contains(.shift) {
                        onPrevious()
                        return .handled
                    }
                    return .ignored
                }
                .onSubmit { onNext() }
                .onKeyPress(.escape) {
                    model.close()
                    return .handled
                }
                .accessibilityLabel("본문에서 찾기")
            Text(statusText)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(textColor.opacity(0.6))
                .lineLimit(1)
            Button(action: onPrevious) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .foregroundStyle(textColor.opacity(model.matchedVerses.isEmpty ? 0.3 : 0.8))
            .disabled(model.matchedVerses.isEmpty)
            .help("이전 일치 (⇧Return)")
            .accessibilityLabel("이전 일치")
            Button(action: onNext) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .foregroundStyle(textColor.opacity(model.matchedVerses.isEmpty ? 0.3 : 0.8))
            .disabled(model.matchedVerses.isEmpty)
            .help("다음 일치 (Return)")
            .accessibilityLabel("다음 일치")
            Button {
                model.close()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(textColor.opacity(0.6))
            .help("닫기 (Esc)")
            .accessibilityLabel("찾기 닫기")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(barBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(textColor.opacity(0.12)).frame(height: 1)
        }
        .onAppear { isFieldFocused = true }
        .onChange(of: model.focusToken) { _, _ in isFieldFocused = true }
    }

    /// 사용자 성경 테마 배경이 있으면 그것을, 없으면 시스템 재질을 쓴다(테마 글자색이 시스템 재질 위에서 안 보이는 일을 피한다).
    @ViewBuilder
    private var barBackground: some View {
        if let background = settings.bibleBackgroundColor {
            Rectangle().fill(background)
        } else {
            Rectangle().fill(.regularMaterial)
        }
    }

    private var statusText: String {
        if model.trimmedQuery.isEmpty { return "" }
        if model.matchedVerses.isEmpty { return "일치 없음" }
        return "\(model.currentIndex + 1)/\(model.matchedVerses.count)절"
    }
}

/// 찾기 상태를 본문 상태(장/번역본 변경)와 연결하고 메뉴(⌘F)에 액션을 노출한다.
private struct BibleChapterFindWiring: ViewModifier {
    let viewModel: BibleReadingViewModel
    let model: BibleChapterFindModel

    /// 표시 중인 장/번역본이 바뀌었는지 보는 값 — 바뀌면 같은 찾을 말로 일치를 다시 계산한다.
    private struct Signature: Hashable {
        let bookId: Int
        let chapter: Int
        let translations: [PersistentIdentifier]
    }

    private var signature: Signature {
        Signature(
            bookId: viewModel.selectedBook.bookId,
            chapter: viewModel.selectedChapter,
            translations: viewModel.displayedTranslationIDs
        )
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: model.query) { _, _ in refresh(scrollToCurrent: true) }
            .onChange(of: model.isPresented) { _, presented in
                if presented { refresh(scrollToCurrent: true) }
            }
            .onChange(of: signature) { _, _ in refresh(scrollToCurrent: false) }
            // Bible 메뉴 "본문에서 찾기… ⌘F" — AppCommands.swift 참고. 성경 조회 창이 키 창일 때만 활성화된다.
            .focusedSceneValue(\.findInChapterAction) { model.present() }
    }

    private func refresh(scrollToCurrent: Bool) {
        model.recompute(columns: viewModel.columns)
        if scrollToCurrent, let verse = model.currentVerse {
            viewModel.highlightVerseTemporarily(verse)
        }
    }
}

extension View {
    func bibleChapterFind(viewModel: BibleReadingViewModel, model: BibleChapterFindModel) -> some View {
        modifier(BibleChapterFindWiring(viewModel: viewModel, model: model))
    }
}
