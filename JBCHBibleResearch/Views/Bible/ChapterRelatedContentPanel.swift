//
//  ChapterRelatedContentPanel.swift
//  JBCHBibleResearch
//
//
//  성경 읽기 화면의 보조(인스펙터) 패널 — 성경 개요/장 개요와, 한 절을 선택했을 때
//  그 절의 관련 개인 묵상·말씀 요약·연구문서·설교문을 보여준다.
//  `BibleReadingView`가 `.inspector(isPresented:)`로 붙인다(창이 넓으면 상시 노출,
//  좁으면 모달처럼 접힘).
//  절 선택이 없거나 여러 절이면 개요만, 정확히 한 절이면 관련 섹션도 표시한다.
//  "관련" 기준은 두 가지를 합친다: ① 좌표가 정확히 이 절인 항목(메모의 `verse`,
//  "관련 성경 장"으로 수동 지정된 문서) ② 본문 텍스트에서 자동 추출된 절 참조(`VerseMention`).
//

import SwiftUI
import SwiftData
import BibleResearchModels
#if os(iOS)
import UIKit
#endif

/// 내비게이션/툴바 바 배경을 성경 읽기 테마 배경색에 맞춘다. 다른 화면 파일들과 같은 타입을
/// 파일별 `private`로 중복 선언한다(파일 최상위 `private` 선언은 이름이 충돌하지 않는다).
///
/// ⚠️ macOS는 `.windowToolbar`를 쓰지만, `.inspector`로 붙는 보조 패널의 제목 표시줄에도
/// 효과가 있는지는 보장되지 않는다.
private struct ThemedNavigationBarBackgroundModifier: ViewModifier {
    let color: Color?

    @Environment(\.self) private var environment

    func body(content: Content) -> some View {
        #if os(iOS)
        // iOS에서는 이 패널이 제목 표시줄을 항상 숨겨(아래 body 참고) 보이는 바가 없다.
        // 다른 파일들과 같은 모양을 유지해 둔다.
        if let color {
            content
                .toolbarBackground(color, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(Self.isDarkBackground(color, in: environment) ? .dark : .light, for: .navigationBar)
        } else {
            content
        }
        #elseif os(macOS)
        if let color {
            content
                .toolbarBackground(color, for: .windowToolbar)
                .toolbarBackground(.visible, for: .windowToolbar)
                .toolbarColorScheme(Self.isDarkBackground(color, in: environment) ? .dark : .light, for: .windowToolbar)
        } else {
            content
        }
        #else
        content
        #endif
    }

    private static func isDarkBackground(_ color: Color, in environment: EnvironmentValues) -> Bool {
        let resolved = color.resolve(in: environment)
        let luminance = 0.2126 * Double(resolved.red) + 0.7152 * Double(resolved.green) + 0.0722 * Double(resolved.blue)
        return luminance < 0.5
    }
}

struct ChapterRelatedContentPanel: View {
    let viewModel: BibleReadingViewModel
    /// 메모를 탭하면 호출부(BibleReadingView)가 기존 "메모 작성" 시트로 연다.
    let onSelectMemo: (UserMemo) -> Void
    /// 말씀 요약을 탭하면 호출부(BibleReadingView)가 인스펙터 편집기로 연다.
    var onSelectWordSummary: (VerseSummary) -> Void = { _ in }
    /// 정확히 한 절이 선택됐을 때만 넘긴다(다중 선택이면 기준 절이 모호해진다).
    /// nil이면 개요만 표시한다.
    var selectedVerse: Int? = nil
    /// "관련 내용"(자동 추출) 항목을 골랐을 때 — 메모는 편집기 시트, 연구문서는
    /// PDF 검색+이동 창으로 연다(호출부 책임).
    var onSelectVerseMention: (VerseMention) -> Void = { _ in }

    /// 책 개요/장 개요를 독립적으로 접고 펼치는 상태(기본 펼침).
    @State private var isBookOutlineExpanded = true
    @State private var isChapterSummaryExpanded = true

    /// 펼친 개요 박스의 고정 높이 — 이보다 긴 개요는 박스 안에서만 스크롤된다.
    private static let outlineBoxHeight: CGFloat = 260

    @Environment(\.openWindow) private var openWindow
    /// macOS 떠 있는 도구창(`RelatedContentPanelController`)은 SwiftUI 씬(`WindowGroup`) 밖의 `NSHostingController`에 올라가
    /// `@Environment(\.openWindow)`가 동작한다는 보장이 없다. 그래서 호출부(성경 조회 창)가 자기 환경의 `OpenWindowAction`을
    /// 넘기면 그것을 우선 쓴다. nil(기본)이면 기존처럼 환경 값을 쓴다 — iOS/아이패드 인스펙터 경로는 변화 없음.
    var injectedOpenWindow: OpenWindowAction? = nil

    /// `openWindow(id:value:)`의 단일 진입점 — 주입된 액션이 있으면 그것을, 없으면 환경 값을 쓴다.
    private func openAppWindow<V: Hashable & Codable>(id: String, value: V) {
        if let injectedOpenWindow {
            injectedOpenWindow(id: id, value: value)
        } else {
            openWindow(id: id, value: value)
        }
    }

    /// 아이폰은 다중 씬을 지원하지 않아 `openWindow`가 런타임 에러를 낸다
    /// (DocumentsHomeView의 `isPhoneIdiom`과 같은 패턴).
    private var isPhoneIdiom: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    /// 성경 읽기 테마(`bibleBackgroundColor`/`bibleTextColor`)를 이 패널에 적용하기 위한 설정.
    private var settings: UserSettingsStore { .shared }

    var body: some View {
        // `.inspector`로 붙을 때 이 뷰 위에는 `NavigationStack`이 없어(아이폰은 시트 루트),
        // 아이폰 분기의 `NavigationLink`가 탭해도 반응하지 않는다. 그래서 스택으로 감싸되,
        // 기존 화면 모양이 바뀌지 않도록 제목 표시줄은 계속 숨긴다.
        // `ToolbarPlacement.navigationBar`는 macOS에 없어 `#if os(iOS)`로 감쌌다.
        NavigationStack {
            List {
                outlineSection
                if let selectedVerse {
                    memoSection(verse: selectedVerse)
                    wordSummarySection(verse: selectedVerse)
                    documentSection(verse: selectedVerse)
                    sermonSection(verse: selectedVerse)
                }
            }
            // 테마 배경 적용 — `OutlineTreeView`/`WordNoteHomeView`와 같은 관례.
            .scrollContentBackground(.hidden)
            // 아이패드 인스펙터: 본문과 구분되도록 옅은 톤(`IPadPaneSeparation.swift`). 아이폰 시트/맥 패널은 테마색 그대로.
            .themedPaneBackground(tinted: true)
            // 제목은 "책 한글명 + 장" — BibleReadingView 툴바 타이틀 두 번째 줄과 같은 조합.
            .navigationTitle("\(viewModel.selectedBook.nameKo) \(viewModel.selectedChapter)장")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            // 이 값은 반드시 `NavigationStack` 콘텐츠 안쪽에 둔다. 스택 바깥(아이폰에서 시트로 열린
            // 루트)에 두면 전환 도중 선호값이 잘못 해석돼 부모 화면(`BibleReadingView`)의 내비게이션
            // 바까지 숨겨진 채 남을 가능성이 있다(간헐적으로 상단 영역이 통째로 사라지던 증상).
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
        // macOS에서 바 배경을 테마색에 맞춘다(`ThemedNavigationBarBackgroundModifier` 참고).
        .modifier(ThemedNavigationBarBackgroundModifier(color: settings.bibleBackgroundColor))
    }

    // MARK: - 개요(S8 책 개요 + S9 장 개요) — 선택 상태와 무관하게 항상 표시
    //
    // ⚠️ 개요 본문은 `RichTextEditor`(`NSViewRepresentable` 기반 `NSTextView`) 대신 순정 SwiftUI
    // `Text(AttributedString)`로 그린다. macOS `.inspector`(NSSplitView) 폭을 드래그하는 동안
    // `NSTextView`가 레이아웃을 재계산하며 AppKit 제약 갱신 패스에 재진입해 크래시했기 때문이다.
    //
    // 제목("개요"/"책 개요"/"장 개요")은 시스템 폰트 `.font(.body)`로 그리고, 개요 내용은 RTF의
    // 원본 글자 크기를 그대로 쓴다. 배경/줄간격은 편집 화면(`OutlineBookBulkEditView`)과 같은
    // `EditorDefaultStyle`을 따른다.

    // ⚠️ macOS `List`는 `Section(header:)` 슬롯 안 텍스트에 `.font(_:)`와 무관하게 작은 보조
    // 스타일을 강제한다. 그래서 섹션 제목은 header 슬롯 대신 일반 리스트 행(아이콘+색, `.body`
    // 크기)으로 넣는다. 아이콘 색은 섹션 구분용이고, 제목 글자는 보조 정보 패널답게 `.secondary`
    // 톤으로 눌러 둔다.
    private func sectionTitleRow(_ title: String, systemImage: String, tint: Color) -> some View {
        Label {
            Text(title)
                .font(.body)
                .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
        } icon: {
            // 범주색(teal/blue/purple/orange)은 섹션 구분용이라 테마와 무관하게 유지한다.
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
        .listRowBackground(Color.clear)
    }

    /// "이 절에 작성됨"/"본문에서 언급됨"/"이 장에 연결됨" — 항목이 목록에 나온 이유를 알리는 작은 배지.
    private func originBadge(_ text: String, systemImage: String) -> some View {
        Label {
            Text(text).font(.caption.bold())
        } icon: {
            Image(systemName: systemImage).font(.caption2)
        }
        .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
    }

    private var outlineSection: some View {
        Section {
            sectionTitleRow("개요", systemImage: "list.bullet.clipboard", tint: .teal)
            if viewModel.relatedBookOutlineRTF == nil && viewModel.relatedChapterSummaryRTF == nil {
                emptyRow("아직 작성된 개요가 없습니다.")
            }
            if let rtf = viewModel.relatedBookOutlineRTF {
                outlineRow(title: "책 개요", rtfText: rtf, isExpanded: $isBookOutlineExpanded)
            }
            if let rtf = viewModel.relatedChapterSummaryRTF {
                outlineRow(title: "장 개요", rtfText: rtf, isExpanded: $isChapterSummaryExpanded)
            }
            Button {
                jumpToOutlineEditor()
            } label: {
                Label("개요 화면 열기", systemImage: "arrow.up.right.square")
            }
            .listRowBackground(Color.clear)
        }
    }

    private func outlineRow(title: String, rtfText: String, isExpanded: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    isExpanded.wrappedValue.toggle()
                } label: {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                }
                .buttonStyle(.plain)
                .help(isExpanded.wrappedValue ? "접기" : "펼치기")

                Text(title)
                    .font(.body)
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)

                Spacer()

                // 다중 씬을 지원하지 않는 아이폰에서는 `openOutlineQuickViewWindow()`의 `openWindow`가
                // 크래시하므로 숨긴다(대체 진입점: "개요 화면 열기").
                if !isPhoneIdiom {
                    Button {
                        openOutlineQuickViewWindow()
                    } label: {
                        Label("새창으로 보기", systemImage: "macwindow")
                            .font(.body)
                            .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("별도 창에서 보기")
                }
            }

            if isExpanded.wrappedValue {
                // 고정 높이 박스 + `ScrollView` — 개요 길이와 무관하게 인스펙터에서 차지하는 자리는 일정하고,
                // 넘치는 내용은 박스 안에서만 스크롤된다.
                ScrollView {
                    Text(outlineAttributedText(rtfText))
                        .lineSpacing(EditorDefaultStyle.lineSpacingPoints)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: Self.outlineBoxHeight)
                // 배경(#F5F1E8)은 실제 편집 화면(`OutlineBookBulkEditView`)과 일부러 맞춘 것이라 테마와 무관하게 유지한다.
                .background(EditorDefaultStyle.backgroundSwiftUIColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .listRowBackground(Color.clear)
    }

    /// 저장된 RTF를 크기 변형 없이 디코딩해 `AttributedString`으로 변환한다(에디터에 입력한 글자 크기 그대로).
    /// `defaultAttributes`는 RTF가 아닌 레거시/빈 텍스트일 때만 쓰이는 폴백이다.
    private func outlineAttributedText(_ rtfText: String) -> AttributedString {
        let decoded = RichTextCodec.decode(rtfText, defaultAttributes: [.font: EditorDefaultStyle.typingFont])
        return AttributedString(decoded)
    }

    /// "별도 창에서 보기" — 항상 새 창을 연다(`requestID`가 매번 새 `UUID`라, 같은 값이면
    /// 기존 창을 재사용하는 SwiftUI 기본 동작을 우회한다).
    private func openOutlineQuickViewWindow() {
        openAppWindow(
            id: "outline-quick-view",
            value: OutlineQuickViewRequest(bookId: viewModel.selectedBook.bookId, chapter: viewModel.selectedChapter)
        )
    }

    /// "개요 화면 열기" — 메인 내비게이션을 개요 섹션으로 전환하고, 현재 책/장을 미리 선택해
    /// 에디터 화면(`OutlineBookBulkEditView`)으로 바로 진입한다.
    private func jumpToOutlineEditor() {
        AppNavigationRequest.shared.request(.outline)
        OutlineNavigationRequest.shared.request(bookId: viewModel.selectedBook.bookId, chapter: viewModel.selectedChapter)
    }

    // MARK: - 메모(구절 선택 시에만) — 이 절에 직접 달린 메모 + 이 절을 언급하는 메모

    @ViewBuilder
    private func memoSection(verse: Int) -> some View {
        let coordinateMemos = viewModel.relatedChapterMemos.filter { $0.verse == verse }
        let mentionedMemos = viewModel.verseMentions(verse: verse).filter { $0.sourceType == .memo }
        Section {
            sectionTitleRow(
                "\(verse)절 관련 개인 묵상 (\(coordinateMemos.count + mentionedMemos.count))",
                systemImage: "note.text", tint: .blue
            )
            if coordinateMemos.isEmpty && mentionedMemos.isEmpty {
                emptyRow("이 절에 달렸거나 이 절을 언급하는 개인 묵상이 없습니다.")
            } else {
                ForEach(coordinateMemos) { memo in
                    Button {
                        onSelectMemo(memo)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            originBadge("이 절에 작성됨", systemImage: "square.and.pencil")
                            Text(memoPreview(memo))
                                .font(.callout)
                                .foregroundStyle(settings.bibleTextColor ?? .primary)
                                .lineSpacing(2)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
                ForEach(mentionedMemos) { mention in
                    Button {
                        onSelectVerseMention(mention)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            originBadge("본문에서 언급됨", systemImage: "text.magnifyingglass")
                            Text(mention.snippet.isEmpty ? mention.searchText : mention.snippet)
                                .font(.callout)
                                .foregroundStyle(settings.bibleTextColor ?? .primary)
                                .lineSpacing(2)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            }
        }
    }

    private func memoPreview(_ memo: UserMemo) -> String {
        let trimmed = memo.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(내용 없음)" : trimmed
    }

    // MARK: - 말씀 요약(구절 선택 시에만) — [2026-08-12 신설]
    // 위 `memoSection(verse:)`와 같은 구조(이 절에 직접 달린 것 + 본문에서 언급된 것).
    // 말씀 요약은 저널 성격이라 "이 절에 작성됨" 항목이 날짜별로 여러 개 나올 수 있다.

    @ViewBuilder
    private func wordSummarySection(verse: Int) -> some View {
        let coordinateSummaries = viewModel.relatedChapterWordSummaries.filter { $0.verse == verse }
        let mentionedSummaries = viewModel.verseMentions(verse: verse).filter { $0.sourceType == .wordSummary }
        Section {
            sectionTitleRow(
                "\(verse)절 관련 말씀 요약 (\(coordinateSummaries.count + mentionedSummaries.count))",
                // `text.quote`는 `BibleReadingView.verseSelectionActionBar`의 "말씀 요약" 버튼과 같은 아이콘이다(번역본 선택의 `text.book.closed`와는 구분).
                systemImage: "text.quote", tint: .purple
            )
            if coordinateSummaries.isEmpty && mentionedSummaries.isEmpty {
                emptyRow("이 절에 작성됐거나 이 절을 언급하는 말씀 요약이 없습니다.")
            } else {
                // `WordSummaryEditorView`가 새 요약의 첫 줄을 "yyyy.MM.dd 말씀"으로 미리 채우므로 첫 줄이
                // 사실상 제목이다 — 제목은 굵게, 나머지 본문 일부는 보조 색으로 보여준다.
                ForEach(coordinateSummaries) { summary in
                    Button {
                        onSelectWordSummary(summary)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            originBadge("이 절에 작성됨 · \(wordSummaryDateLabel(summary))", systemImage: "square.and.pencil")
                            Text(wordSummaryTitleLine(summary))
                                .font(.callout.bold())
                                .foregroundStyle(settings.bibleTextColor ?? .primary)
                                .lineLimit(1)
                            let body = wordSummaryBodyPreview(summary)
                            if !body.isEmpty {
                                Text(body)
                                    .font(.callout)
                                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                                    .lineSpacing(2)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
                ForEach(mentionedSummaries) { mention in
                    Button {
                        onSelectVerseMention(mention)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            originBadge("본문에서 언급됨", systemImage: "text.magnifyingglass")
                            Text(mention.snippet.isEmpty ? mention.searchText : mention.snippet)
                                .font(.callout)
                                .foregroundStyle(settings.bibleTextColor ?? .primary)
                                .lineSpacing(2)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            }
        }
    }

    /// 요약 본문의 첫 줄(제목 역할). 줄바꿈 없이 한 줄만 쓴 레거시 요약은 트리밍한 전체 텍스트를 쓴다.
    private func wordSummaryTitleLine(_ summary: VerseSummary) -> String {
        let trimmed = summary.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "(내용 없음)" }
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        let cleaned = firstLine.trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? trimmed : cleaned
    }

    /// 첫 줄을 뺀 나머지 본문(줄바꿈은 공백으로 연결). 한 줄짜리 요약이면 빈 문자열을 돌려주고,
    /// 호출부는 그 경우 본문 줄을 그리지 않는다.
    private func wordSummaryBodyPreview(_ summary: VerseSummary) -> String {
        let trimmed = summary.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.components(separatedBy: .newlines)
        guard lines.count > 1 else { return "" }
        return lines.dropFirst()
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func wordSummaryDateLabel(_ summary: VerseSummary) -> String {
        Self.dateLabelFormatter.string(from: summary.createdAt)
    }

    private static let dateLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter
    }()

    // MARK: - 연구문서(구절 선택 시에만) — 이 장에 수동 태깅된 문서 + 이 절을 언급하는 문서

    @ViewBuilder
    private func documentSection(verse: Int) -> some View {
        let taggedDocuments = viewModel.relatedDocuments
        let mentionedDocuments = viewModel.verseMentions(verse: verse).filter { $0.sourceType == .document }
        // 원본 문서가 같은 절 인용구를 여러 위치에 반복하는 경우가 있어, 화면에 보이는 텍스트
        // (스니펫, 없으면 검색어)가 글자 그대로 같은 항목만 한 줄로 묶어 "N곳에서 언급됨"으로
        // 표시한다. 텍스트가 서로 다르면 합치지 않는다.
        let groupedMentionedDocuments = groupedByDisplayText(mentionedDocuments)
        Section {
            sectionTitleRow(
                "\(verse)절 관련 연구문서 (\(taggedDocuments.count + groupedMentionedDocuments.count))",
                systemImage: "doc.text.magnifyingglass", tint: .orange
            )
            if taggedDocuments.isEmpty && mentionedDocuments.isEmpty {
                emptyRow("이 장에 연결됐거나 이 절을 언급하는 연구문서가 없습니다.")
            } else {
                ForEach(taggedDocuments) { document in
                    // 아이폰만 NavigationLink 푸시(다중 씬 미지원, isPhoneIdiom 참고).
                    // 행 모양은 아래 `mentionedDocuments` 행과 같은 배지+2줄 구조로 맞춘다.
                    Group {
                        if isPhoneIdiom {
                            NavigationLink {
                                DocumentViewerWindowContent(documentID: document.persistentModelID)
                            } label: {
                                documentRowLabel(document)
                            }
                        } else {
                            Button {
                                openAppWindow(id: "document-viewer", value: document.persistentModelID)
                            } label: {
                                documentRowLabel(document)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                }
                ForEach(groupedMentionedDocuments) { group in
                    // 탭하면 그룹의 대표(가장 먼저 등장한 mention) 위치로 이동한다 — 텍스트가 같으므로
                    // 어느 위치로 가도 찾던 내용은 동일하다.
                    Button {
                        onSelectVerseMention(group.representative)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                originBadge("본문에서 언급됨", systemImage: "text.magnifyingglass")
                                if group.count > 1 {
                                    Text("\(group.count)곳에서 언급됨")
                                        .font(.caption2)
                                        .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                                }
                            }
                            Text(group.representative.snippet.isEmpty ? group.representative.searchText : group.representative.snippet)
                                .font(.callout)
                                .foregroundStyle(settings.bibleTextColor ?? .primary)
                                .lineSpacing(2)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            }
        }
    }

    /// `documentSection`/`sermonSection`용 — 화면에 보일 텍스트가 같은 `VerseMention`들을
    /// 대표 1개 + 개수로 압축한다. 등장 순서는 `order` 배열로 유지한다.
    private struct GroupedMention: Identifiable {
        let id: UUID
        let representative: VerseMention
        let count: Int
    }

    private func groupedByDisplayText(_ mentions: [VerseMention]) -> [GroupedMention] {
        var order: [String] = []
        var buckets: [String: [VerseMention]] = [:]
        for mention in mentions {
            let key = mention.snippet.isEmpty ? mention.searchText : mention.snippet
            if buckets[key] == nil {
                order.append(key)
            }
            buckets[key, default: []].append(mention)
        }
        return order.compactMap { key in
            guard let group = buckets[key], let first = group.first else { return nil }
            return GroupedMention(id: first.id, representative: first, count: group.count)
        }
    }

    /// 위 `taggedDocuments` 행 — "이 장에 연결됨" 배지 + 파일명(`mentionedDocuments` 행과 같은 구조).
    private func documentRowLabel(_ document: SourceDocument) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            originBadge("이 장에 연결됨", systemImage: "paperclip")
            Label(document.originalFilename, systemImage: "doc.text")
                .font(.callout)
                .foregroundStyle(settings.bibleTextColor ?? .primary)
                .lineLimit(2)
        }
    }

    // MARK: - 내 설교(구절 선택 시에만) — 이 구절에 "말씀구절"로 연결된 설교문 +
    // documentSection과 같은 두 신호(수동 "말씀구절" 참조 + 본문 언급) — 다만 수동 신호의 좌표는
    // 장 전체가 아니라 절 범위다(`BibleReadingViewModel.sermonVerseReferences(verse:)` 참고).

    /// 선택한 절에 "말씀구절"로 연결된 설교문과, 이 절을 언급하는 설교문을 보여준다.
    @ViewBuilder
    private func sermonSection(verse: Int) -> some View {
        let taggedReferences = viewModel.sermonVerseReferences(verse: verse)
        let mentionedSermons = viewModel.verseMentions(verse: verse).filter { $0.sourceType == .sermon }
        // documentSection과 같은 이유로, 같은 텍스트는 "N곳에서 언급됨"으로 묶는다.
        let groupedMentionedSermons = groupedByDisplayText(mentionedSermons)
        Section {
            sectionTitleRow(
                "\(verse)절 관련 설교문 (\(taggedReferences.count + groupedMentionedSermons.count))",
                systemImage: "mic.fill", tint: .purple
            )
            if taggedReferences.isEmpty && mentionedSermons.isEmpty {
                emptyRow("이 절에 연결됐거나 이 절을 언급하는 설교문이 없습니다.")
            } else {
                ForEach(taggedReferences) { reference in
                    sermonReferenceRow(reference)
                }
                ForEach(groupedMentionedSermons) { group in
                    Button {
                        onSelectVerseMention(group.representative)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                originBadge("본문에서 언급됨", systemImage: "text.magnifyingglass")
                                if group.count > 1 {
                                    Text("\(group.count)곳에서 언급됨")
                                        .font(.caption2)
                                        .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                                }
                            }
                            Text(group.representative.snippet.isEmpty ? group.representative.searchText : group.representative.snippet)
                                .font(.callout)
                                .foregroundStyle(settings.bibleTextColor ?? .primary)
                                .lineSpacing(2)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            }
        }
    }

    /// 수동 "말씀구절" 참조 한 행 — `.sermon`/`.delivery` 중 채워진 쪽(설계상 상호 배타적)으로
    /// 분기해 `SermonViewerView`/"sermon-viewer" 창을 연다. 아이폰/그 외 분기는 `taggedDocuments` 행과 같다.
    @ViewBuilder
    private func sermonReferenceRow(_ reference: SermonVerseReference) -> some View {
        if let sermon = reference.sermon {
            Group {
                if isPhoneIdiom {
                    NavigationLink {
                        SermonViewerView(subject: .sermon(sermon))
                    } label: {
                        sermonReferenceRowLabel(title: sermon.title.isEmpty ? "제목 없음" : sermon.title)
                    }
                } else {
                    Button {
                        openAppWindow(id: "sermon-viewer", value: SermonViewerTarget.sermon(sermon))
                    } label: {
                        sermonReferenceRowLabel(title: sermon.title.isEmpty ? "제목 없음" : sermon.title)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
            .listRowBackground(Color.clear)
        } else if let delivery = reference.delivery {
            // 회차 사본(SermonDelivery) — 소속 모임 이름 + 날짜로 표시한다.
            let gatheringName = delivery.gathering?.name ?? "모임 미지정"
            let dateText = delivery.deliveredAt.formatted(date: .abbreviated, time: .omitted)
            Group {
                if isPhoneIdiom {
                    NavigationLink {
                        SermonViewerView(subject: .delivery(delivery))
                    } label: {
                        sermonReferenceRowLabel(title: "\(gatheringName) \(dateText)")
                    }
                } else {
                    Button {
                        openAppWindow(id: "sermon-viewer", value: SermonViewerTarget.delivery(delivery))
                    } label: {
                        sermonReferenceRowLabel(title: "\(gatheringName) \(dateText)")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
            .listRowBackground(Color.clear)
        }
        // 둘 다 nil이면(설계상 불가능한 상태) 아무 것도 그리지 않는다.
    }

    private func sermonReferenceRowLabel(title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            originBadge("말씀구절로 연결됨", systemImage: "text.book.closed")
            Label(title, systemImage: "mic.fill")
                .font(.callout)
                .foregroundStyle(settings.bibleTextColor ?? .primary)
                .lineLimit(2)
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
            .listRowBackground(Color.clear)
    }
}
