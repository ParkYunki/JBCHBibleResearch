//
//  OutlineQuickViewWindowContent.swift
//  JBCHBibleResearch
//
//  [2026-08-15 신설] `WindowGroup(id: "outline-quick-view", for:
//  OutlineQuickViewRequest.self)`(JBCHBibleResearchApp.swift 참고) 전용 창.
//  사용자 요청 — "[성경 조회] 오른쪽 인스펙터 개요의 '별도 창에서 보기': 책
//  개요 / 장 개요(해당 장) 두 내용만 표시. 상단에 검색창, 돋보기 버튼(배율
//  확대/축소/원본크기)." `ChapterRelatedContentPanel.outlineRow`가 인스펙터
//  안에서 보여주는 것과 같은 내용을, 편집기(`OutlineBookBulkEditView`)로
//  이동하지 않고도 크게/독립적으로 볼 수 있는 순수 조회 전용 창이다 — 이
//  창에서도 편집은 되지 않는다(에디터 기능 없음, `ChapterRelatedContentPanel.swift`
//  상단 크래시 수정 주석과 같은 이유로 `NSViewRepresentable`이 아니라 순정
//  SwiftUI `Text(AttributedString)`로 그린다).
//
//  [2026-08-15 2차 변경] 사용자 요청 2가지 — ① "검색 기능: 일치하는 검색어
//  숫자 + 검색어 이동(다음/이전) 버튼 추가." 검색으로 실제 "이동"하려면 스크롤할
//  대상이 필요한데, 책 개요/장 개요를 각각 통짜 `Text` 하나로 그리면(1차
//  구현) 그 안의 특정 위치로 스크롤할 방법이 없다. 그래서 각 개요를 줄바꿈
//  기준 문단(`OutlineParagraph`)으로 쪼개 `ScrollViewReader` + `.id(paragraph.id)`
//  로 스크롤 가능하게 만들었다(`DocumentViewerView.extractedTextPane`이 이미
//  쓰는 "줄 단위로 쪼개 스크롤"과 같은 패턴). 서식(`NSAttributedString`)은
//  `attributedSubstring(from:)`으로 잘라내 각 문단이 원본 서식을 그대로
//  유지한다. ② "돋보기 기능: 메뉴 안에서 분기하지 말고 아이콘 버튼 3개를
//  나열해 클릭 한 번으로 확대/축소/원본크기." 이전엔 `Menu`(첫 클릭으로 메뉴를
//  열고 두 번째 클릭으로 항목을 고르는 2단계) 안에 세 항목을 넣었었다 — 이제
//  `Menu` 없이 세 `Button`을 나란히 둬 클릭 한 번으로 바로 실행된다.
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
    /// [2026-09-01 추가] 사용자 요청 — "ipad상에서 개요를 새창으로 띄울때
    /// 닫기버튼 넣어줄 것." `DocumentViewerView.dismissWindow` 상단 주석과
    /// 정확히 같은 이유 — macOS는 `WindowGroup`이 진짜 독립 창을 만들어
    /// 트래픽라이트(빨간 닫기 버튼)가 이미 있지만, iPadOS/iPhone은 이 창을
    /// 닫을 시스템 제공 버튼이 없다(`openWindow`가 다중 씬 미지원 기기에서는
    /// 새 창 대신 현재 화면을 통째로 대체하기도 해 뒤로 갈 방법조차 없을 수
    /// 있다). `dismissWindow()`(인자 없음 — "이 환경 값이 속한 창을 닫는다")로
    /// 닫는다.
    #if os(iOS)
    @Environment(\.dismissWindow) private var dismissWindow
    #endif
    let request: OutlineQuickViewRequest?

    /// 책 개요/장 개요를 줄바꿈 기준으로 쪼갠 문단들 — 검색 "이동"이 실제로
    /// 스크롤할 수 있는 단위(위 파일 상단 주석 참고). 데이터 로드 시 한 번만
    /// 만든다(줄 내용 자체는 편집되지 않으므로 다시 만들 필요가 없다 — 확대/
    /// 축소·검색은 렌더링 시점에만 영향을 준다).
    @State private var paragraphs: [OutlineParagraph] = []
    @State private var hasLoaded = false
    @State private var searchQuery = ""
    /// 지금 몇 번째 일치 항목을 보고 있는지(0-based) — `searchMatches`의 인덱스.
    @State private var currentMatchIndex = 0
    /// 돋보기 버튼이 조작하는 배율 — 1.0이 "원본 크기". 0.5~3.0으로 제한해
    /// 텍스트가 읽을 수 없이 작아지거나(레이아웃 붕괴) 창 밖으로 넘치는 걸
    /// 막는다.
    @State private var zoomScale: CGFloat = 1.0

    private static let minZoom: CGFloat = 0.5
    private static let maxZoom: CGFloat = 3.0
    private static let zoomStep: CGFloat = 0.1

    /// [2026-08-15 5차 수정] 사용자 보고 — "문단 간격이 실제 에디터에서 보는
    /// 것과 많이 다름." 원인 — 이전(4차) 구현은 임의로 고른 "확대율 1.0을 넘는
    /// 만큼 × 8pt"라는 상수를 썼는데, 이 숫자는 실제 에디터가 줄간격을 계산하는
    /// 공식과 아무 관계가 없었다(그냥 "틈이 안 보이게 0에서 시작해 적당히
    /// 벌어지게"만 맞춘 임시값). 에디터는 `RichTextEditor.applyTypingAttributes`가
    /// `NSParagraphStyle.lineSpacing = typingFont.typographicLineHeight *
    /// (lineHeightMultiple - 1)`로 계산한다 — 이게 정확히 `EditorDefaultStyle.
    /// lineSpacingPoints`다. 이 창은 "책 개요"/"장 개요" 전체를 줄바꿈 기준으로
    /// 쪼개 별도 `Text`들을 나열하는 구조라(검색 "이동" 때문 — 위 2차 변경 주석
    /// 참고), 원본에서는 그냥 "다음 줄로 넘어가는 줄간격"이었던 것이 여기서는
    /// "문단(Text) 사이 간격"이 됐을 뿐, 값 자체는 정확히 같아야 한다 — 그래서
    /// 임의의 "×8" 대신 에디터와 완전히 같은 값(`lineSpacingPoints`)을 쓰고,
    /// 글자 크기가 `zoomScale`만큼 커지면(`RichTextCodec.scalingFontSize`) 줄
    /// 간격도 같은 비율로 커져야 자연스러우므로 `zoomScale`을 곱한다. 100%
    /// 배율에서도 이제 0이 아니라 실제 줄간격 값이 적용되지만, 앞서(4차) 스크롤
    /// 뷰 배경을 문단 배경과 맞춰 뒀기 때문에(틈이 보여도 이질감 없음) 다시
    /// "갈라진 틈"처럼 보이지 않는다.
    private var interParagraphSpacing: CGFloat {
        EditorDefaultStyle.lineSpacingPoints * zoomScale
    }

    /// [2026-08-15 5차 수정] 원본에서 빈 줄(연속 줄바꿈으로 생긴 빈 문단)이었던
    /// 자리 — 문단 분리 전에는 그 빈 줄도 에디터에서 폰트 한 줄 높이만큼
    /// 공간을 차지했다. 분리 후엔 빈 문자열 `Text`가 내용이 없어 높이가
    /// 찌그러들 수 있어(플랫폼/폰트에 따라 0에 가깝게 측정될 수 있음), 아래
    /// `.frame(minHeight:)`로 "그 배율에서의 한 줄 높이"(줄 기본 높이 ×
    /// 줄간격 배수, `RichTextEditor`가 쓰는 것과 같은 공식)를 강제로 보장한다.
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
                        // [2026-08-15 3차 수정, 5차 수정으로 갱신] 검색 "이동"을
                        // 만들려고(2차 변경 상단 주석) 개요 하나를 문단별로 쪼개
                        // `LazyVStack`에 나열한다 — 원래 하나로 이어져 있던 본문을
                        // 여러 `Text`로 잘라 그리는 구조이므로, 문단 사이 간격
                        // (`interParagraphSpacing`)이 곧 "그 잘린 지점의 줄간격"이다.
                        // ⚠️ 이 값이 왜 0이 아니라 에디터의 실제 줄간격 값인지는
                        // 위 `interParagraphSpacing` 프로퍼티 주석(5차 수정) 참고 —
                        // 틈이 보여도 스크롤 뷰 배경을 문단 배경과 맞춰 뒀기(4차
                        // 수정) 때문에 이질감이 없다.
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
                                    // [2026-08-15 5차 수정] 임의 상수 대신
                                    // `interParagraphSpacing`과 동일한 공식(에디터의
                                    // 실제 `NSParagraphStyle.lineSpacing`)을 그대로
                                    // 쓴다 — 한 문단 안에서 줄바꿈으로 여러 줄이 될
                                    // 때(긴 문단)도 문단과 문단 사이 간격과 똑같은
                                    // 값이어야 에디터에서 보던 것과 일치한다.
                                    .lineSpacing(interParagraphSpacing)
                                    .textSelection(.enabled)
                                    // 빈 줄(원본의 연속 줄바꿈)이 찌그러지지 않고
                                    // 에디터와 같은 한 줄 높이를 차지하도록 최소
                                    // 높이를 보장한다 — 위 `scaledSingleLineHeight`
                                    // 주석 참고.
                                    .frame(maxWidth: .infinity, minHeight: scaledSingleLineHeight, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .background(EditorDefaultStyle.backgroundSwiftUIColor)
                                    .id(paragraph.id)
                            }
                        }
                        .padding()
                    }
                    // [2026-08-15 4차 수정] 사용자 보고 — "확대하면 이전에 없던
                    // 문단과 문단 사이가 갈라진 틈이 보임." 3차 수정(위 주석)에서
                    // 100% 배율의 틈은 없앴지만, 100%를 넘겨 확대하면
                    // `interParagraphSpacing`이 다시 0보다 커지면서(요청대로 확대
                    // 시 문단 간격도 함께 벌어짐) 그 벌어진 틈으로 스크롤 뷰의
                    // 기본 배경(플랫폼 기본값 — 흰색/텍스트뷰 배경 등, 문단 배경
                    // `EditorDefaultStyle.backgroundSwiftUIColor`와 다름)이 다시
                    // 비쳐 보였다. 문단 간격을 없애는 대신(확대 시 간격이 벌어지는
                    // 동작 자체는 사용자가 원했던 것), 스크롤 뷰 배경 자체를 문단
                    // 배경과 같은 색으로 맞춰 틈이 보여도 이질감이 없게 했다.
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
    /// 위 `dismissWindow` 프로퍼티 주석 참고 — iPadOS/iPhone 전용 닫기 버튼.
    /// `DocumentViewerView.closeWindowButton`과 완전히 같은 모양·동작이다.
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

            // [2026-08-15 2차 변경] 사용자 요청 — "메뉴 안에서 분기하지 말고
            // 아이콘 버튼 3개를 나열, 클릭 한 번으로 확대/축소/원본크기." 이전
            // `Menu` 하나 대신 독립된 `Button` 3개.
            Button {
                zoomScale = min(Self.maxZoom, zoomScale + Self.zoomStep)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("확대")

            Button {
                zoomScale = max(Self.minZoom, zoomScale - Self.zoomStep)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("축소")

            Button {
                zoomScale = 1.0
            } label: {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("원본 크기 (\(Int((zoomScale * 100).rounded()))%)")
        }
        .padding(8)
    }

    // MARK: - 검색 — 일치 개수 + 다음/이전 이동

    private struct SearchMatch {
        let paragraphID: Int
        /// 해당 문단의 원본(확대/축소 적용 전) 텍스트 기준 위치 — `scalingFontSize`가
        /// 글자 수/오프셋을 바꾸지 않으므로(포인트 크기만 바꿈) 확대/축소된
        /// 텍스트에도 그대로 적용할 수 있다.
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

    /// 줄바꿈("\n") 기준으로 서식을 유지한 채 잘라낸다 — `attributedSubstring(from:)`
    /// 이 원본 `NSAttributedString`의 속성(굵게/기울임/색 등)을 그대로 보존해
    /// 잘라내므로, 검색/확대·축소가 문단 단위로 적용돼도 서식이 깨지지 않는다.
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
