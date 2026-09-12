#!/usr/bin/env python3
"""ChapterRelatedContentPanel.swift — 사용자 요청: "성경-인스펙터 창의 디자인도
테마에 맞도록 수정할것." (`BibleReadingView`가 `.inspector(isPresented:)`로
붙이는 "관련 콘텐츠" 패널 — macOS/iOS 공용.)

이 패널은 지금까지 배경(List 시스템 기본 배경)과 거의 모든 글자색
(`.primary`/`.secondary`)이 테마(`settings.bibleBackgroundColor`/
`bibleTextColor`)를 전혀 참조하지 않았다. `OutlineTreeView.swift`/
`WordNoteHomeView.swift`/`SearchView.swift`/`DocumentsHomeView.swift`가 이미
겪고 고친 것과 완전히 같은 3종 세트를 그대로 재사용한다:
  1) List 자체: `.scrollContentBackground(.hidden)` + `.background(settings.
     bibleBackgroundColor ?? Color.clear)`
  2) 각 "행"(Section 안의 개별 뷰 — Section 자체가 아니라 그 안의 각 행에
     적용해야 실제로 반영된다는 게 `WordNoteHomeView`/`OutlineTreeView`에서
     이미 실기기로 확인된 사실이다): `.listRowBackground(Color.clear)`
  3) 텍스트/아이콘: `.secondary` → `settings.bibleTextColor?.opacity(0.6) ??
     Color.secondary`, `.primary` → `settings.bibleTextColor ?? .primary`
     (다른 화면들에서 이미 반복된 것과 같은 opacity 값)

의도적으로 그대로 두는 것 두 가지:
  - `sectionTitleRow`의 아이콘 색(`tint`, teal/blue/purple/orange) — 2026-08-20
    주석에 이미 있듯 "섹션마다 다르게 둬서 한눈에 구분되게" 하려고 고른
    범주 구분용 색이라, 다른 화면들의 상태/강조 색과 같은 원칙으로 유지한다.
  - `outlineRow`의 개요 본문 미리보기 배경(`EditorDefaultStyle.
    backgroundSwiftUIColor`) — 2026-08-15 주석에 이미 있듯 이 개요를 실제로
    "쓰는" 화면(`OutlineBookBulkEditView`)과 일부러 같은 배경(#F5F1E8)을
    맞춘 것이라, 여기만 테마색으로 바꾸면 정작 그 원본 편집 화면과 미리보기가
    서로 달라 보이게 된다 — 그대로 둔다.
"""
import pathlib

PATH = pathlib.Path.home() / "mnt" / "JBCHBibleResearch" / "JBCHBibleResearch/Views/Bible/ChapterRelatedContentPanel.swift"


def apply(path, replacements):
    src = path.read_text()
    for old, new, count in replacements:
        found = src.count(old)
        assert found == count, f"expected {count} occurrence(s), found {found}\n---OLD---\n{old[:300]}"
        src = src.replace(old, new)
    path.write_text(src)
    print("OK:", path)


edits = []

# --- 1) settings 프로퍼티 추가 ---
old_settings = '''    private var isPhoneIdiom: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    var body: some View {'''
new_settings = '''    private var isPhoneIdiom: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    /// [2026-09-12 추가] 사용자 요청 — "성경-인스펙터 창의 디자인도 테마에
    /// 맞도록 수정할것." 이 패널은 지금까지 배경/본문 글자색이 전부 시스템
    /// 기본값(`.primary`/`.secondary`, `List`의 시스템 배경)이라 성경 읽기
    /// 테마(`bibleBackgroundColor`/`bibleTextColor`)를 전혀 따르지 않았다.
    private var settings: UserSettingsStore { .shared }

    var body: some View {'''
edits.append((old_settings, new_settings, 1))

# --- 2) List 자체 배경 ---
old_list = '''            List {
                outlineSection
                if let selectedVerse {
                    memoSection(verse: selectedVerse)
                    wordSummarySection(verse: selectedVerse)
                    documentSection(verse: selectedVerse)
                }
            }
            .navigationTitle("이 장의 관련 콘텐츠")'''
new_list = '''            List {
                outlineSection
                if let selectedVerse {
                    memoSection(verse: selectedVerse)
                    wordSummarySection(verse: selectedVerse)
                    documentSection(verse: selectedVerse)
                }
            }
            // [2026-09-12 추가] 위 `settings` 선언부 주석 참고 — `OutlineTreeView`/
            // `WordNoteHomeView`가 이미 쓰는 것과 같은 관례.
            .scrollContentBackground(.hidden)
            .background(settings.bibleBackgroundColor ?? Color.clear)
            .navigationTitle("이 장의 관련 콘텐츠")'''
edits.append((old_list, new_list, 1))

# --- 3) sectionTitleRow: 제목 글자색 + 행 배경 ---
old_title_row = '''    private func sectionTitleRow(_ title: String, systemImage: String, tint: Color) -> some View {
        Label {
            Text(title)
                .font(.body)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
    }'''
new_title_row = '''    private func sectionTitleRow(_ title: String, systemImage: String, tint: Color) -> some View {
        Label {
            Text(title)
                .font(.body)
                .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
        } icon: {
            // [2026-09-12 확인] `tint`(teal/blue/purple/orange)는 2026-08-20
            // 주석대로 섹션을 한눈에 구분하기 위한 범주색이라 테마와 무관하게
            // 그대로 둔다 — 다른 화면들의 상태/강조 색과 같은 원칙.
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
        .listRowBackground(Color.clear)
    }'''
edits.append((old_title_row, new_title_row, 1))

# --- 4) originBadge: 글자색만 (임베디드 서브뷰라 listRowBackground 대상 아님) ---
old_origin_badge = '''    private func originBadge(_ text: String, systemImage: String) -> some View {
        Label {
            Text(text).font(.caption.bold())
        } icon: {
            Image(systemName: systemImage).font(.caption2)
        }
        .foregroundStyle(.secondary)
    }'''
new_origin_badge = '''    private func originBadge(_ text: String, systemImage: String) -> some View {
        Label {
            Text(text).font(.caption.bold())
        } icon: {
            Image(systemName: systemImage).font(.caption2)
        }
        .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
    }'''
edits.append((old_origin_badge, new_origin_badge, 1))

# --- 5) outlineSection: "개요 화면 열기" 버튼 행 배경 ---
old_open_editor_button = '''            Button {
                jumpToOutlineEditor()
            } label: {
                Label("개요 화면 열기", systemImage: "arrow.up.right.square")
            }
        }
    }

    private func outlineRow(title: String, rtfText: String, isExpanded: Binding<Bool>) -> some View {'''
new_open_editor_button = '''            Button {
                jumpToOutlineEditor()
            } label: {
                Label("개요 화면 열기", systemImage: "arrow.up.right.square")
            }
            .listRowBackground(Color.clear)
        }
    }

    private func outlineRow(title: String, rtfText: String, isExpanded: Binding<Bool>) -> some View {'''
edits.append((old_open_editor_button, new_open_editor_button, 1))

# --- 6) outlineRow: 접기 화살표 색 ---
old_chevron = '''                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(isExpanded.wrappedValue ? "접기" : "펼치기")'''
new_chevron = '''                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                }
                .buttonStyle(.plain)
                .help(isExpanded.wrappedValue ? "접기" : "펼치기")'''
edits.append((old_chevron, new_chevron, 1))

# --- 7) outlineRow: "책 개요"/"장 개요" 제목 색 ---
old_outline_title = '''                Text(title)
                    .font(.body)
                    .foregroundStyle(.secondary)

                Spacer()'''
new_outline_title = '''                Text(title)
                    .font(.body)
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)

                Spacer()'''
edits.append((old_outline_title, new_outline_title, 1))

# --- 8) outlineRow: "새창으로 보기" 라벨 색 ---
old_new_window_label = '''                        Label("새창으로 보기", systemImage: "macwindow")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("별도 창에서 보기")'''
new_new_window_label = '''                        Label("새창으로 보기", systemImage: "macwindow")
                            .font(.body)
                            .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("별도 창에서 보기")'''
edits.append((old_new_window_label, new_new_window_label, 1))

# --- 9) outlineRow: 행 전체 배경(바깥 VStack) — 안쪽 개요 미리보기 박스
#        (EditorDefaultStyle.backgroundSwiftUIColor)는 의도적으로 그대로 둔다.
old_outline_row_end = '''                .frame(height: Self.outlineBoxHeight)
                .background(EditorDefaultStyle.backgroundSwiftUIColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    /// 저장된 RTF를 크기 변형 없이 그대로 디코딩해 `AttributedString`으로'''
new_outline_row_end = '''                .frame(height: Self.outlineBoxHeight)
                // [2026-09-12 확인] 이 개요 미리보기 배경(#F5F1E8)은 2026-08-15
                // 주석대로 실제 편집 화면(`OutlineBookBulkEditView`)과 일부러
                // 맞춘 것이라 테마와 무관하게 그대로 둔다 — 여기만 바꾸면
                // 원본 편집 화면과 미리보기가 서로 달라 보이게 된다.
                .background(EditorDefaultStyle.backgroundSwiftUIColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .listRowBackground(Color.clear)
    }

    /// 저장된 RTF를 크기 변형 없이 그대로 디코딩해 `AttributedString`으로'''
edits.append((old_outline_row_end, new_outline_row_end, 1))

# --- 10) memoSection: 두 ForEach 행 배경 + 본문 글자색 ---
old_memo_section = '''                ForEach(coordinateMemos) { memo in
                    Button {
                        onSelectMemo(memo)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            originBadge("이 절에 작성됨", systemImage: "square.and.pencil")
                            Text(memoPreview(memo))
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .lineSpacing(2)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(mentionedMemos) { mention in
                    Button {
                        onSelectVerseMention(mention)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            originBadge("본문에서 언급됨", systemImage: "text.magnifyingglass")
                            Text(mention.snippet.isEmpty ? mention.searchText : mention.snippet)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .lineSpacing(2)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }'''
new_memo_section = '''                ForEach(coordinateMemos) { memo in
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
                }'''
edits.append((old_memo_section, new_memo_section, 1))

# --- 11) wordSummarySection: 두 ForEach 행 배경 + 본문 글자색 ---
old_word_summary_section = '''                ForEach(coordinateSummaries) { summary in
                    Button {
                        onSelectWordSummary(summary)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            originBadge("이 절에 작성됨 · \\(wordSummaryDateLabel(summary))", systemImage: "square.and.pencil")
                            Text(wordSummaryTitleLine(summary))
                                .font(.callout.bold())
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            let body = wordSummaryBodyPreview(summary)
                            if !body.isEmpty {
                                Text(body)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .lineSpacing(2)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(mentionedSummaries) { mention in
                    Button {
                        onSelectVerseMention(mention)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            originBadge("본문에서 언급됨", systemImage: "text.magnifyingglass")
                            Text(mention.snippet.isEmpty ? mention.searchText : mention.snippet)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .lineSpacing(2)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }'''
new_word_summary_section = '''                ForEach(coordinateSummaries) { summary in
                    Button {
                        onSelectWordSummary(summary)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            originBadge("이 절에 작성됨 · \\(wordSummaryDateLabel(summary))", systemImage: "square.and.pencil")
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
                }'''
edits.append((old_word_summary_section, new_word_summary_section, 1))

# --- 12) documentSection: 두 ForEach 행 배경 + 본문 글자색 ---
old_document_section = '''                ForEach(taggedDocuments) { document in
                    // [2026-08-18 수정, 아이폰 크래시 fix] 아이폰만 NavigationLink
                    // 푸시로(다중 씬 미지원, isPhoneIdiom 참고) — 이 패널은
                    // BibleReadingView의 인스펙터라 그 화면의 NavigationStack
                    // 안으로 그대로 밀려 들어간다.
                    //
                    // [2026-08-20 추가] 사용자 요청 — "관련 말씀 요약, 관련
                    // 연구문서에 대한 간격, 줄간격을 여유롭게 할것." 예전엔
                    // 파일명만 있는 한 줄짜리 `Label`이라 바로 아래
                    // `mentionedDocuments`(본문에서 언급됨) 행과 생김새가
                    // 달랐다 — 같은 배지+2줄 구조로 맞춰 통일했다.
                    Group {
                        if isPhoneIdiom {
                            NavigationLink {
                                DocumentViewerWindowContent(documentID: document.persistentModelID)
                            } label: {
                                documentRowLabel(document)
                            }
                        } else {
                            Button {
                                openWindow(id: "document-viewer", value: document.persistentModelID)
                            } label: {
                                documentRowLabel(document)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
                ForEach(groupedMentionedDocuments) { group in
                    // 탭하면 그룹의 대표(가장 먼저 등장한 mention) 위치로
                    // 이동한다 — 여러 위치가 텍스트만 같을 뿐 실제로는 문서
                    // 안 서로 다른 곳일 수 있어, 완전히 같은 텍스트인 이상
                    // 어느 곳으로 가도(글자상) 사용자가 찾던 내용은 동일하다.
                    Button {
                        onSelectVerseMention(group.representative)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                originBadge("본문에서 언급됨", systemImage: "text.magnifyingglass")
                                if group.count > 1 {
                                    Text("\\(group.count)곳에서 언급됨")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(group.representative.snippet.isEmpty ? group.representative.searchText : group.representative.snippet)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .lineSpacing(2)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }'''
new_document_section = '''                ForEach(taggedDocuments) { document in
                    // [2026-08-18 수정, 아이폰 크래시 fix] 아이폰만 NavigationLink
                    // 푸시로(다중 씬 미지원, isPhoneIdiom 참고) — 이 패널은
                    // BibleReadingView의 인스펙터라 그 화면의 NavigationStack
                    // 안으로 그대로 밀려 들어간다.
                    //
                    // [2026-08-20 추가] 사용자 요청 — "관련 말씀 요약, 관련
                    // 연구문서에 대한 간격, 줄간격을 여유롭게 할것." 예전엔
                    // 파일명만 있는 한 줄짜리 `Label`이라 바로 아래
                    // `mentionedDocuments`(본문에서 언급됨) 행과 생김새가
                    // 달랐다 — 같은 배지+2줄 구조로 맞춰 통일했다.
                    Group {
                        if isPhoneIdiom {
                            NavigationLink {
                                DocumentViewerWindowContent(documentID: document.persistentModelID)
                            } label: {
                                documentRowLabel(document)
                            }
                        } else {
                            Button {
                                openWindow(id: "document-viewer", value: document.persistentModelID)
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
                    // 탭하면 그룹의 대표(가장 먼저 등장한 mention) 위치로
                    // 이동한다 — 여러 위치가 텍스트만 같을 뿐 실제로는 문서
                    // 안 서로 다른 곳일 수 있어, 완전히 같은 텍스트인 이상
                    // 어느 곳으로 가도(글자상) 사용자가 찾던 내용은 동일하다.
                    Button {
                        onSelectVerseMention(group.representative)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                originBadge("본문에서 언급됨", systemImage: "text.magnifyingglass")
                                if group.count > 1 {
                                    Text("\\(group.count)곳에서 언급됨")
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
                }'''
edits.append((old_document_section, new_document_section, 1))

# --- 13) documentRowLabel: 파일명 글자색 (임베디드 서브뷰) ---
old_document_row_label = '''    private func documentRowLabel(_ document: SourceDocument) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            originBadge("이 장에 연결됨", systemImage: "paperclip")
            Label(document.originalFilename, systemImage: "doc.text")
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
    }'''
new_document_row_label = '''    private func documentRowLabel(_ document: SourceDocument) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            originBadge("이 장에 연결됨", systemImage: "paperclip")
            Label(document.originalFilename, systemImage: "doc.text")
                .font(.callout)
                .foregroundStyle(settings.bibleTextColor ?? .primary)
                .lineLimit(2)
        }
    }'''
edits.append((old_document_row_label, new_document_row_label, 1))

# --- 14) emptyRow: 글자색 + 행 배경 ---
old_empty_row = '''    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}'''
new_empty_row = '''    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
            .listRowBackground(Color.clear)
    }
}'''
edits.append((old_empty_row, new_empty_row, 1))

apply(PATH, edits)
