//
//  OutlineQuickViewWindowContent.swift
//  JBCHBibleResearch
//
//  `WindowGroup(id: "outline-quick-view", for: OutlineQuickViewRequest.self)`
//  전용 창. 책 개요와 해당 장 개요만 보여 주는 조회 전용 창이며(편집 없음),
//  상단에 검색창(일치 개수 + 다음/이전 이동)과 배율 조절 버튼 3개(확대/축소/원본)를 둔다.
//  크래시를 피하려고 `NSViewRepresentable` 대신 순정 SwiftUI `Text(AttributedString)`로 그린다.
//  검색 이동을 위해 개요를 줄바꿈 기준 문단(`OutlineParagraph`)으로 쪼개
//  `ScrollViewReader` + `.id`로 스크롤하며, 서식은 `attributedSubstring(from:)`으로 보존한다.
//

import SwiftUI
import SwiftData
import BibleResearchModels
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct OutlineQuickViewWindowContent: View {
    @Environment(\.modelContext) private var modelContext
    /// iPadOS/iPhone 전용 닫기 버튼용 환경 값 — macOS는 창 자체에 닫기 버튼이 있지만
    /// iOS에는 이 창을 닫을 시스템 버튼이 없다. `dismissWindow()`는 이 환경 값이 속한 창을 닫는다.
    #if os(iOS)
    @Environment(\.dismissWindow) private var dismissWindow
    #endif
    let request: OutlineQuickViewRequest?

    /// 책 개요/장 개요를 줄바꿈 기준으로 쪼갠 문단들 — 검색 이동이 스크롤할 단위.
    /// 로드 시 한 번만 만든다(확대/축소·검색은 렌더링 시점에만 영향을 준다).
    @State private var paragraphs: [OutlineParagraph] = []
    @State private var hasLoaded = false
    @State private var searchQuery = ""
    /// 지금 몇 번째 일치 항목을 보고 있는지(0-based) — `searchMatches`의 인덱스.
    @State private var currentMatchIndex = 0
    /// 돋보기 버튼이 조작하는 배율(1.0 = 원본 크기). 0.5~3.0으로 제한해 레이아웃 붕괴를 막는다.
    @State private var zoomScale: CGFloat = 1.0

    private static let minZoom: CGFloat = 0.5
    private static let maxZoom: CGFloat = 3.0
    private static let zoomStep: CGFloat = 0.1

    /// 문단 사이 간격 — 에디터의 줄간격(`RichTextEditor.applyTypingAttributes`의
    /// `NSParagraphStyle.lineSpacing`, 곧 `EditorDefaultStyle.lineSpacingPoints`)과 같은 값을
    /// 써야 에디터에서 보던 모양과 일치한다. 글자 크기가 `zoomScale`만큼 커지므로 같은 비율로 곱한다.
    private var interParagraphSpacing: CGFloat {
        EditorDefaultStyle.lineSpacingPoints * zoomScale
    }

    /// 빈 문단(원본의 연속 줄바꿈)이 높이 0에 가깝게 찌그러지지 않도록 보장하는 최소 높이 —
    /// 배율이 적용된 한 줄 높이(줄 기본 높이 × 줄간격 배수, `RichTextEditor`와 같은 공식).
    private var scaledSingleLineHeight: CGFloat {
        EditorDefaultStyle.typingFont.typographicLineHeight * EditorDefaultStyle.lineHeightMultiple * zoomScale
    }

    var body: some View {
        if let request, let book = BooksProvider.shared.book(id: request.bookId) {
            content(request: request, book: book)
        } else {
            requestNotFoundMessage
        }
    }

    @ViewBuilder
    private func content(request: OutlineQuickViewRequest, book: Book) -> some View {
        ScrollViewReader { scrollProxy in
            VStack(spacing: 0) {
                header(scrollProxy: scrollProxy)
                Divider()
                if paragraphs.isEmpty {
                    Text("아직 작성된 개요가 없습니다.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        // 개요를 문단별로 쪼개 나열하므로 문단 사이 간격이 곧 원본의 줄간격이다
                        // (값의 근거는 `interParagraphSpacing` 참고).
                        LazyVStack(alignment: .leading, spacing: interParagraphSpacing) {
                            ForEach(paragraphs) { paragraph in
                                if paragraph.isFirstInBlock {
                                    Text(paragraph.blockTitle)
                                        .font(.headline)
                                        .foregroundStyle(.secondary)
                                        .padding(.top, paragraph.id == 0 ? 0 : 16)
                                        .padding(.bottom, 4)
                                }
                                Text(displayedAttributedText(for: paragraph))
                                    // 한 문단이 여러 줄로 줄바꿈될 때도 문단 사이와 같은 줄간격을 쓴다.
                                    .lineSpacing(interParagraphSpacing)
                                    .textSelection(.enabled)
                                    // 빈 줄이 찌그러지지 않도록 최소 높이 보장(`scaledSingleLineHeight` 참고).
                                    .frame(maxWidth: .infinity, minHeight: scaledSingleLineHeight, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .background(EditorDefaultStyle.backgroundSwiftUIColor)
                                    .id(paragraph.id)
                            }
                        }
                        .padding()
                    }
                    // 확대 시 벌어진 문단 사이 틈으로 스크롤 뷰 기본 배경이 비치지 않도록
                    // 문단 배경과 같은 색으로 맞춘다.
                    .background(EditorDefaultStyle.backgroundSwiftUIColor)
                }
            }
            .onChange(of: searchQuery) { _, _ in
                currentMatchIndex = 0
                scrollToCurrentMatch(scrollProxy: scrollProxy)
            }
        }
        .navigationTitle("\(book.nameKo) \(request.chapter)장 개요")
        .onAppear { loadIfNeeded(bookId: request.bookId, chapter: request.chapter) }
        #if os(iOS)
        .overlay(alignment: .topTrailing) {
            closeWindowButton
        }
        #endif
    }

    #if os(iOS)
    /// iPadOS/iPhone 전용 닫기 버튼(`dismissWindow` 참고).
    private var closeWindowButton: some View {
        Button {
            dismissWindow()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 22))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .background(Circle().fill(.background))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .padding(12)
        .accessibilityLabel("닫기")
    }
    #endif

    // MARK: - 상단 바 — 검색창(일치 개수 + 다음/이전) + 돋보기(개별 버튼 3개)

    private func header(scrollProxy: ScrollViewProxy) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("검색", text: $searchQuery)
                .textFieldStyle(.plain)

            if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let matches = searchMatches
                Text(matches.isEmpty ? "0/0" : "\(currentMatchIndex + 1)/\(matches.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button {
                    goToPreviousMatch(scrollProxy: scrollProxy)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .disabled(matches.isEmpty)
                .help("이전 일치 항목")

                Button {
                    goToNextMatch(scrollProxy: scrollProxy)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .disabled(matches.isEmpty)
                .help("다음 일치 항목")
            }

            Spacer(minLength: 8)

            // 클릭 한 번으로 실행되도록 `Menu` 대신 독립된 버튼 3개를 둔다. 기존 프로젝트의 원형 버튼
            // 스타일(`BookChapterPicker`와 동일: 강조색 12% 배경 + 35% 테두리)을 28pt로 축소 적용했고,
            // `contentShape(Circle())`로 탭 영역을 시각 크기와 맞췄다. 아이콘은 명시적 크기를 줘야 서로
            // 구분되며, 대각선 화살표 아이콘은 심볼 폭이 넓어 12pt로 작게 잡는다.
            Button {
                zoomScale = min(Self.maxZoom, zoomScale + Self.zoomStep)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color("AccentColor"))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color("AccentColor").opacity(0.12)))
                    .overlay(Circle().stroke(Color("AccentColor").opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .help("확대")

            Button {
                zoomScale = max(Self.minZoom, zoomScale - Self.zoomStep)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color("AccentColor"))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color("AccentColor").opacity(0.12)))
                    .overlay(Circle().stroke(Color("AccentColor").opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .help("축소")

            Button {
                zoomScale = 1.0
            } label: {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color("AccentColor"))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color("AccentColor").opacity(0.12)))
                    .overlay(Circle().stroke(Color("AccentColor").opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .help("원본 크기 (\(Int((zoomScale * 100).rounded()))%)")
        }
        .padding(8)
    }

    // MARK: - 검색 — 일치 개수 + 다음/이전 이동

    private struct SearchMatch {
        let paragraphID: Int
        /// 해당 문단의 원본(확대/축소 적용 전) 텍스트 기준 위치 — `scalingFontSize`는
        /// 글자 수/오프셋을 바꾸지 않으므로 확대/축소된 텍스트에도 그대로 쓸 수 있다.
        let range: NSRange
    }

    /// 검색어와 일치하는 모든 구간을 문단 순서대로(위→아래) 모은다 — 다음/이전
    /// 버튼이 이 배열의 인덱스를 오가며 순환한다.
    private var searchMatches: [SearchMatch] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        var results: [SearchMatch] = []
        for paragraph in paragraphs {
            let text = paragraph.rawAttributed.string as NSString
            guard text.length > 0 else { continue }
            var searchRange = NSRange(location: 0, length: text.length)
            while true {
                let found = text.range(of: query, options: .caseInsensitive, range: searchRange)
                if found.location == NSNotFound { break }
                results.append(SearchMatch(paragraphID: paragraph.id, range: found))
                let nextLocation = found.location + found.length
                guard nextLocation < text.length else { break }
                searchRange = NSRange(location: nextLocation, length: text.length - nextLocation)
            }
        }
        return results
    }

    private func goToNextMatch(scrollProxy: ScrollViewProxy) {
        let matches = searchMatches
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matches.count
        scrollToCurrentMatch(scrollProxy: scrollProxy)
    }

    private func goToPreviousMatch(scrollProxy: ScrollViewProxy) {
        let matches = searchMatches
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matches.count) % matches.count
        scrollToCurrentMatch(scrollProxy: scrollProxy)
    }

    private func scrollToCurrentMatch(scrollProxy: ScrollViewProxy) {
        let matches = searchMatches
        guard matches.indices.contains(currentMatchIndex) else { return }
        withAnimation {
            scrollProxy.scrollTo(matches[currentMatchIndex].paragraphID, anchor: .center)
        }
    }

    /// 이 문단을 화면에 그릴 최종 서식 — 확대/축소(`RichTextCodec.scalingFontSize`)를
    /// 먼저 적용한 뒤, 검색어와 일치하는 구간에 배경 강조를 입힌다("지금 보고
    /// 있는" 일치 항목은 주황, 나머지는 노랑으로 구분).
    private func displayedAttributedText(for paragraph: OutlineParagraph) -> AttributedString {
        let scaled = RichTextCodec.scalingFontSize(paragraph.rawAttributed, by: zoomScale)
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AttributedString(scaled)
        }
        let mutable = NSMutableAttributedString(attributedString: scaled)
        for (globalIndex, match) in searchMatches.enumerated() where match.paragraphID == paragraph.id {
            let isCurrent = globalIndex == currentMatchIndex
            mutable.addAttribute(.backgroundColor, value: isCurrent ? PlatformColor.orange : PlatformColor.yellow, range: match.range)
            mutable.addAttribute(.foregroundColor, value: PlatformColor.black, range: match.range)
        }
        return AttributedString(mutable)
    }

    // MARK: - 로드 — RTF 디코딩 → 줄바꿈 기준 문단으로 분할

    private func loadIfNeeded(bookId: Int, chapter: Int) {
        guard !hasLoaded else { return }
        hasLoaded = true

        let bookOutlineRTF = (try? modelContext.fetch(
            FetchDescriptor<BookOutline>(
                predicate: #Predicate { $0.bookId == bookId },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
        ))?.first { !$0.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?.contentHtml

        let chapterSummaryRTF = (try? modelContext.fetch(
            FetchDescriptor<ChapterSummary>(
                predicate: #Predicate { $0.bookId == bookId && $0.chapter == chapter },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
        ))?.first { !$0.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?.contentHtml

        var result: [OutlineParagraph] = []
        var nextID = 0
        func appendBlock(title: String, rtfText: String?) {
            guard let rtfText else { return }
            let decoded = RichTextCodec.decode(rtfText, defaultAttributes: [.font: EditorDefaultStyle.typingFont])
            for (index, piece) in splitIntoParagraphs(decoded).enumerated() {
                result.append(OutlineParagraph(id: nextID, blockTitle: title, isFirstInBlock: index == 0, rawAttributed: piece))
                nextID += 1
            }
        }
        appendBlock(title: "책 개요", rtfText: bookOutlineRTF)
        appendBlock(title: "장 개요 (\(chapter)장)", rtfText: chapterSummaryRTF)
        paragraphs = result
    }

    /// 줄바꿈("\n") 기준으로 서식을 유지한 채 자른다 — `attributedSubstring(from:)`이
    /// 굵게/기울임/색 등 속성을 보존한다.
    private func splitIntoParagraphs(_ attributed: NSAttributedString) -> [NSAttributedString] {
        let fullString = attributed.string as NSString
        let totalLength = fullString.length
        guard totalLength > 0 else { return [attributed] }

        var pieces: [NSAttributedString] = []
        var searchStart = 0
        while searchStart <= totalLength {
            let remaining = NSRange(location: searchStart, length: totalLength - searchStart)
            let newlineRange = fullString.range(of: "\n", range: remaining)
            let pieceRange: NSRange
            let isLastPiece: Bool
            if newlineRange.location == NSNotFound {
                pieceRange = remaining
                isLastPiece = true
            } else {
                pieceRange = NSRange(location: searchStart, length: newlineRange.location - searchStart)
                isLastPiece = false
            }
            pieces.append(attributed.attributedSubstring(from: pieceRange))
            if isLastPiece { break }
            searchStart = newlineRange.location + 1
        }
        return pieces
    }

    private var requestNotFoundMessage: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("개요를 찾을 수 없습니다.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// `OutlineQuickViewWindowContent`가 책 개요/장 개요를 줄바꿈 기준으로 쪼갠
/// 문단 하나. `id`는 `ScrollViewReader.scrollTo(_:)`가 검색 "다음/이전" 이동에
/// 쓰는 앵커다.
private struct OutlineParagraph: Identifiable {
    let id: Int
    let blockTitle: String
    /// 이 블록(책 개요/장 개요)의 첫 문단이면 `true` — 그 앞에 블록 제목을
    /// 한 번만 그리기 위한 표시.
    let isFirstInBlock: Bool
    let rawAttributed: NSAttributedString
}
