//
//  SermonEditorView.swift
//  JBCHBibleResearch
//
//  S-SER2 "설교 작성 — 프리셋 스타일 리치 에디터".
//  메인 `Sermon`과 특정 회차 `SermonDelivery` 양쪽을 같은 화면으로 편집한다
//  (대상만 다르다). `SermonDelivery`에는 title 필드가 없어 제목 입력은
//  `.sermon` 대상일 때만 보이고, 회차에서는 대주제(mainTheme) 문단이 제목 역할을 한다.
//  문단 스타일 6종은 항상 보이는 가로 pill 한 줄로 고르고, 굵게/기울임/
//  말씀구절 추가/서식 도구는 그 아래·옆에 둔다.
//

import SwiftUI
import SwiftData
import BibleResearchModels
#if os(iOS)
import UIKit
#endif


/// 다른 뷰 파일들(`DocumentsHomeView` 등)이 각자 두는 것과 같은 구현 — iOS 16+ `Color.resolve`와
/// WCAG 상대휘도로 내비게이션 바의 다크/라이트 색조를 정한다.
/// ⚠️ 파일마다 `private`로 중복 선언한다 — 같은 모듈에서 `private`(fileprivate) 선언과 non-private
/// 동일 이름 선언이 섞이면 "Invalid redeclaration" 충돌이 나므로 공유(internal)로 바꾸면 안 된다.
private struct ThemedNavigationBarBackgroundModifier: ViewModifier {
    let color: Color?

    @Environment(\.self) private var environment

    func body(content: Content) -> some View {
        #if os(iOS)
        if let color {
            content
                .toolbarBackground(color, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(Self.isDarkBackground(color, in: environment) ? .dark : .light, for: .navigationBar)
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

/// `RichTextEditor.swift`의 `toolbarFontSizes`와 같은 목적 — 6종 프리셋 크기(16/17/19/20/24/34)를
/// 포함한 자주 쓰는 값들.
private let sermonToolbarFontSizes: [CGFloat] = [12, 13, 14, 15, 16, 17, 19, 20, 22, 24, 28, 32, 34, 40]

struct SermonEditorView: View {
    let subject: SermonEditingSubject
    /// `true`면 새 설교 작성 모드 — 제목 입력이 보이고, `save()`가 제목·본문 중 하나라도 있을 때만
    /// 실제로 insert한다(아무 입력 없이 닫으면 저장하지 않음). 수정일자는 `save()`의 `touchUpdatedAt()`이 채운다.
    var isNewSermon: Bool = false
    /// 아이패드·맥은 오른쪽 패널에 이 화면을 직접 얹고 아이폰은 값 기반 push라, `.sheet`/`.fullScreenCover`
    /// 전제의 `dismiss`에 기댈 수 없다(특히 아이패드·맥). 호출부가 넘긴 이 클로저로 "취소/닫기"를 구현한다.
    var onRequestClose: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    /// `onRequestClose`가 없는 곳(아이폰 push)에서 마인드맵 "설교문 적용" 후 이 화면을 닫는 대체 수단.
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment
    @Environment(\.sermonHasFixedTitle) private var hasFixedTitle

    @State private var contentHtml: String = ""
    @State private var contentText: String = ""
    @State private var paragraphStyles: String = ""
    @State private var currentStyle: SermonParagraphStyle = .body
    @State private var isVersePickerPresented = false
    @State private var hasLoaded = false
    /// 새 설교 제목 입력 상태 — `isNewSermon`일 때만 쓰인다.
    @State private var title: String = ""
    /// `isNewSermon`일 때 `modelContext.insert(sermon)`을 이미 했는지 — 중복 삽입 방지.
    @State private var hasInsertedNewSermon = false
    /// 마인드맵 "설교문 적용"이 본문을 바깥에서 바꿨을 때 true — 이 편집기가 든 옛 본문 사본이
    /// `onDisappear → save()`로 적용된 내용을 덮어쓰는 것을 막는다.
    @State private var skipSaveOnDisappear = false

    /// `.sermon`이면 `Sermon.sermonTags`, `.delivery`면 회차의 `deliveryTags`(`SermonEditingSubject.tags`) —
    /// 두 태그 집합은 서로 독립이다. `SermonDetailView.tagSection`과 같은 패턴.
    @State private var tags: [Tag] = []
    @State private var tagInput = ""
    @State private var tagSuggestions: [Tag] = []
    @State private var hasLoadedTags = false

    private let proxy = SermonParagraphEditingProxy()

    private var settings: UserSettingsStore { .shared }

    /// 테마색상 반영 — `SermonHomeView.accent`/`SermonDetailView.accent`와 같은 코드.
    private var accent: Color {
        SermonTheme.accent(background: settings.bibleBackgroundColor, environment: environment, fallbackScheme: colorScheme)
    }

    private var isPhoneIdiom: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    /// "취소"/"완료" 라벨 전환용 — 제목 또는 본문이 입력돼 있는지. `save()`의 지연 삽입 가드와
    /// 같은 기준이어야 라벨이 실제 저장 여부와 일치한다.
    private var hasEnteredContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            titleField
            if let parentSermon = subject.parentSermon {
                referencedMainSermonBanner(parentSermon)
            }
            styleToolbar
            Divider()
            SermonParagraphEditor(
                contentHtml: $contentHtml,
                contentText: $contentText,
                paragraphStyles: $paragraphStyles,
                styleFontSnapshot: subject.styleFontSnapshot,
                isEditable: true,
                proxy: proxy
            )
            .frame(maxHeight: .infinity)
            Divider()
            tagSection
        }
        .navigationTitle(hasFixedTitle ? SermonFixedTitle.navigationText : (isNewSermon ? "새 설교 작성" : "설교 작성"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .modifier(ThemedNavigationBarBackgroundModifier(color: settings.bibleBackgroundColor))
        .toolbar {
            // 아이폰은 push된 화면이라 시스템 뒤로가기 "<"가 이미 `onDisappear → save()`를 태우므로
            // 이 버튼은 아이패드·맥(뒤로가기 없이 오른쪽 패널에 얹힘)에서만 보인다. `#if os(iOS)`가
            // 아니라 `isPhoneIdiom`으로 판단해야 아이패드에서도 보인다.
            if isNewSermon && !isPhoneIdiom {
                ToolbarItem(placement: .cancellationAction) {
                    // 저장 동작은 그대로 두고 라벨만 실제 동작에 맞춘다 — 입력이 있으면 "완료"(닫으면
                    // 저장됨), 제목·본문이 모두 비어 있으면 "취소"(`save()` 가드가 저장을 건너뜀).
                    Button(hasEnteredContent ? "완료" : "취소") { onRequestClose?() }
                }
            }
        }
        .sheet(isPresented: $isVersePickerPresented) {
            SermonVerseReferencePicker { text, bookId, chapter, verseStart, verseEnd in
                insertVerseQuote(text: text, bookId: bookId, chapter: chapter, verseStart: verseStart, verseEnd: verseEnd)
            }
        }
        .onAppear {
            loadIfNeeded()
            loadTagsIfNeeded()
        }
        .onDisappear {
            // 마인드맵이 본문을 바꾼 뒤 닫히는 경우엔 저장하지 않는다(옛 사본이 새 본문을 덮어씀) —
            // 직전에 `onFlush`에서 이미 저장했다.
            if !skipSaveOnDisappear { save() }
        }
        // 마인드맵 "설교문 적용" 흐름: (1) `onFlush` — 적용 직전 현재 본문을 즉시 저장, (2) 마인드맵이
        // 적용·저장, (3) `onReplaced` — 저장 없이 닫는다. 닫기는 `onRequestClose`, 없으면 `dismiss()`.
        .onSermonExternalContentChange(
            onFlush: flushForExternalChange,
            onReplaced: closeForExternalChange
        )
        .background(settings.bibleBackgroundColor ?? Color.clear)
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 560)
        #endif
    }

    // MARK: - 새 설교 제목 (요구사항 — "새 설교 작성 레이어 팝업 제거, 본문
    /// `.sermon`(메인 설교문) 대상일 때만 보이는 제목 입력(새 설교·기존 설교 공통). `.delivery`는
    /// title 필드가 없어 제외한다. 새 설교는 아직 `modelContext`에 없는 `@State title`에, 기존 설교는
    /// `sermon.title`에 직접 바인딩하며 디스크 저장은 `save()`(제출/화면 이탈 시)가 맡는다.
    @ViewBuilder
    private var titleField: some View {
        if case .sermon(let sermon) = subject {
            VStack(alignment: .leading, spacing: 4) {
                if isNewSermon {
                    TextField("설교 제목", text: $title)
                        .font(.title3.bold())
                        .foregroundStyle(settings.bibleTextColor ?? .primary)
                        .textFieldStyle(.plain)
                        .onSubmit { save() }
                } else {
                    TextField(
                        "설교 제목",
                        text: Binding(get: { sermon.title }, set: { sermon.title = $0 })
                    )
                    .font(.title3.bold())
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
                    .textFieldStyle(.plain)
                    .onSubmit { save() }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)
            Divider()
        }
    }

    // MARK: - 태그 (요구사항 — "태그 입력은 메인 설교문, 모임에 따른 설교문
    // 하단에 추가할 수 있도록 할 것", 2026-09-29)
    //
    // ⚠️ 태그 줄은 화면 맨 아래 고정 영역에 둔다 — 문단 목록이 SwiftUI `ForEach`가 아니라
    // `SermonParagraphEditor`(UITextView/NSTextView 래퍼)라 같은 스크롤 안에 SwiftUI 콘텐츠를
    // 끼워 넣을 수 없기 때문이다.
    private var tagSectionLabel: String {
        switch subject {
        case .sermon: return "설교 태그"
        case .delivery: return "이 회차만의 태그 (메인 설교 태그와 별도)"
        }
    }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tagSectionLabel)
                .font(.caption)
                .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)

            FlowLayoutHStack {
                ForEach(tags) { tag in
                    HStack(spacing: 4) {
                        Text(tag.name)
                        Button {
                            removeTag(tag)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.15))
                    .foregroundStyle(accent)
                    .clipShape(Capsule())
                }
            }

            HStack {
                TextField("태그 입력 후 Enter", text: $tagInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .onSubmit { commitTagInput() }
                    .onChange(of: tagInput) { _, newValue in
                        updateTagSuggestions(for: newValue)
                    }
                if !tagSuggestions.isEmpty {
                    Menu {
                        ForEach(tagSuggestions) { suggestion in
                            Button(suggestion.name) { addTag(suggestion) }
                        }
                    } label: {
                        Image(systemName: "chevron.down.circle")
                    }
                }
            }
            .frame(maxWidth: 280)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - "참조한 메인 설교" 배너 (요구사항 6)

    /// `.delivery`를 편집할 때만 보인다. 누르면 S-SER3(뷰어)로만 이동하고 편집 화면으로는
    /// 연결하지 않아 메인 설교의 수정 불가를 보장한다.
    @ViewBuilder
    private func referencedMainSermonBanner(_ mainSermon: Sermon) -> some View {
        let label = bannerLabel(mainSermon)
        Group {
            if isPhoneIdiom {
                NavigationLink {
                    SermonViewerView(subject: .sermon(mainSermon))
                } label: {
                    bannerContent(label)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    openWindow(id: "sermon-viewer", value: SermonViewerTarget.sermon(mainSermon))
                } label: {
                    bannerContent(label)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func bannerLabel(_ mainSermon: Sermon) -> String {
        let gatheringName = subject.gathering?.name ?? "모임 미지정"
        let dateText = subject.deliveredAt?.formatted(date: .abbreviated, time: .omitted) ?? ""
        let title = mainSermon.title.isEmpty ? "제목 없음" : mainSermon.title
        return "참조한 메인 설교(읽기 전용) · \(gatheringName) \(dateText) — \(title)"
    }

    private func bannerContent(_ label: String) -> some View {
        HStack {
            Image(systemName: "arrow.up.doc")
                .foregroundStyle(accent)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(accent.opacity(0.12))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(accent.opacity(0.5), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    // MARK: - 툴바 (문단 스타일 pill 한 줄 + B/I + 말씀구절 추가)

    /// 목업 Editor.dc.html의 "[대주제][중주제][소주제][말씀구절][인용][본문]"
    /// pill 한 줄 — 항상 6종이 다 보이고, 현재 문단의 스타일이 액센트로
    /// 채워진다. 가로 스크롤로 감싸 아이폰 폭에서도 잘리지 않게 한다.
    private var styleToolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 스타일 pill은 가로 스크롤 안에 둬 아이폰 폭에서도 6종이 잘리지 않게 하고, 굵게/기울임은
            // 스크롤 밖 같은 `HStack`에 고정해 한 줄로 보이게 한다.
            HStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(SermonParagraphStyle.allCases, id: \.self) { style in
                            Button {
                                currentStyle = style
                                proxy.applyParagraphStyle(style, settings: .shared)
                            } label: {
                                Text(styleDisplayName(style))
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 7)
                                    .background(style == currentStyle ? accent : Color.secondary.opacity(0.12))
                                    .foregroundStyle(style == currentStyle ? Color.white : Color.primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Divider().frame(height: 18)

                Button {
                    proxy.toggleBold()
                } label: {
                    Image(systemName: "bold")
                }
                Button {
                    proxy.toggleItalic()
                } label: {
                    Image(systemName: "italic")
                }
            }
            .tint(accent)

            HStack {
                Spacer()

                Button {
                    isVersePickerPresented = true
                } label: {
                    Label("말씀구절 추가", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                }
            }
            .tint(accent)

            formatToolbar
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// 문단 정렬·글자 색상·크기·글꼴 지정 툴바(`RichTextEditorToolbarContent`와 같은 구성). 각 메뉴
    /// 맨 위 "프리셋 ○○로" 항목은 `nil`을 넘겨 현재 문단 스타일의 프리셋 값으로 되돌린다(수동 지정을
    /// 취소하는 유일한 방법). 정렬은 `.natural` 버튼이 되돌리기 역할을 한다.
    private var formatToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                Menu {
                    Button("프리셋 색상으로") { proxy.applyColor(nil, settings: settings) }
                    Divider()
                    ForEach(Color.memoTextPalette, id: \.hex) { swatch in
                        Button(swatch.name) { proxy.applyColor(swatch.hex, settings: settings) }
                    }
                } label: {
                    Image(systemName: "paintpalette")
                }

                Menu {
                    Button("프리셋 글꼴로") { proxy.applyFontFamily(nil, settings: settings) }
                    Divider()
                    Menu("Paperlogy") {
                        ForEach(BundledFonts.paperlogyEntries) { entry in
                            Button(entry.displayName) { proxy.applyFontFamily(entry.postScriptName, settings: settings) }
                        }
                    }
                    Menu("고운바탕") {
                        ForEach(BundledFonts.gowunBatangEntries) { entry in
                            Button(entry.displayName) { proxy.applyFontFamily(entry.postScriptName, settings: settings) }
                        }
                    }
                    Button("조선궁서체") { proxy.applyFontFamily(SpecialPurposeFonts.hanja, settings: settings) }
                    Divider()
                    Button("시스템 기본") { proxy.applyFontFamily("System", settings: settings) }
                } label: {
                    Image(systemName: "textformat")
                }

                Menu {
                    Button("프리셋 크기로") { proxy.applyFontSize(nil, settings: settings) }
                    Divider()
                    ForEach(sermonToolbarFontSizes, id: \.self) { size in
                        Button("\(Int(size))pt") { proxy.applyFontSize(size, settings: settings) }
                    }
                } label: {
                    Image(systemName: "textformat.size")
                }

                Divider().frame(height: 16)

                Button { proxy.applyAlignment(.left) } label: { Image(systemName: "text.alignleft") }
                Button { proxy.applyAlignment(.center) } label: { Image(systemName: "text.aligncenter") }
                Button { proxy.applyAlignment(.right) } label: { Image(systemName: "text.alignright") }
                Button { proxy.applyAlignment(.natural) } label: { Image(systemName: "arrow.uturn.backward") }
            }
            .buttonStyle(.plain)
            .font(.system(size: 15))
        }
        .tint(accent)
    }

    private func styleDisplayName(_ style: SermonParagraphStyle) -> String {
        switch style {
        case .mainTheme: return "대주제"
        case .midTheme: return "중주제"
        case .subTheme: return "소주제"
        case .verseQuote: return "말씀구절"
        case .citation: return "인용"
        case .body: return "본문"
        }
    }

    // MARK: - 로드/저장

    private func loadIfNeeded() {
        guard !hasLoaded else { return }
        contentHtml = subject.contentHtml
        contentText = subject.contentText
        paragraphStyles = subject.paragraphStyles
        if isNewSermon, case .sermon(let sermon) = subject {
            title = sermon.title
        }
        hasLoaded = true
    }

    /// 마인드맵 알림이 "이 편집기의 설교"를 가리키는지 판별하는 ID — 회차 사본
    /// (`.delivery`)은 마인드맵 대상이 아니라 `nil`.
    private var externalChangeSermonID: PersistentIdentifier? {
        if case .sermon(let sermon) = subject { return sermon.persistentModelID }
        return nil
    }

    /// (1) 마인드맵이 적용하기 직전 — 지금까지 입력한 본문을 즉시 저장한다.
    /// (`body`의 타입 추론 부담을 줄이려고 클로저 대신 메서드로 뺐다.)
    private func flushForExternalChange(_ id: PersistentIdentifier) {
        guard externalChangeSermonID == id else { return }
        save()
    }

    /// (3) 마인드맵이 적용·저장한 뒤 — 저장하지 않고 닫는다.
    private func closeForExternalChange(_ id: PersistentIdentifier) {
        guard externalChangeSermonID == id else { return }
        skipSaveOnDisappear = true
        if let onRequestClose {
            onRequestClose()
        } else {
            dismiss()
        }
    }

    private func save() {
        if isNewSermon, case .sermon(let sermon) = subject {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            sermon.title = trimmedTitle
            if !hasInsertedNewSermon {
                let trimmedContent = contentText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedTitle.isEmpty || !trimmedContent.isEmpty else { return }
                modelContext.insert(sermon)
                hasInsertedNewSermon = true
            }
        }
        subject.contentHtml = contentHtml
        subject.contentText = contentText
        subject.paragraphStyles = paragraphStyles
        // 이번 저장 시점의 프리셋 값을 스냅샷으로 저장 — 다음에 열 때 `applyStyle`이 실제 값과
        // 비교해 사용자의 수동 서식 지정을 가려낸다.
        subject.styleFontSnapshot = SermonParagraphStyleCodec.captureSnapshot(settings: settings)
        subject.touchUpdatedAt()
        try? modelContext.save()
        // 저장 직후 통합 검색용 성경구절 인덱스를 갱신한다(`reindexMemo` 등과 같은 자리).
        // 회차 사본(`.delivery`)은 인덱싱하지 않는다.
        if case .sermon(let sermon) = subject {
            BibleReferenceIndexingService.reindexSermon(sermon, context: modelContext)
        }
    }

    // MARK: - 태그 로드/입력 (`SermonDetailView.tagSection`과 같은 패턴을
    // `SermonEditingSubject.tags`/`addTagJoin`/`removeTagJoin`을 통해 재사용)

    private func loadTagsIfNeeded() {
        guard !hasLoadedTags else { return }
        tags = subject.tags
        hasLoadedTags = true
    }

    private func updateTagSuggestions(for input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else {
            tagSuggestions = []
            return
        }
        do {
            let all = try modelContext.fetch(FetchDescriptor<Tag>(
                predicate: #Predicate<Tag> { $0.mergedIntoId == nil }
            ))
            tagSuggestions = Array(
                all
                    .filter { $0.normalizedForm.contains(trimmed) }
                    .filter { candidate in !tags.contains { $0.id == candidate.id } }
                    .sorted { $0.name < $1.name }
                    .prefix(8)
            )
        } catch {
            tagSuggestions = []
        }
    }

    private func commitTagInput() {
        let trimmed = tagInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            let tag = try TagDeduplication.findOrCreateTag(named: trimmed, context: modelContext)
            addTag(tag)
        } catch {
            print("[SermonEditorView] 태그 생성 실패: \(error)")
        }
        tagInput = ""
        tagSuggestions = []
    }

    private func addTag(_ tag: Tag) {
        guard !tags.contains(where: { $0.id == tag.id }) else { return }
        subject.addTagJoin(tag, context: modelContext)
        tags.append(tag)
        tagInput = ""
        tagSuggestions = []
        try? modelContext.save()
    }

    private func removeTag(_ tag: Tag) {
        subject.removeTagJoin(for: tag, context: modelContext)
        tags.removeAll { $0.id == tag.id }
        try? modelContext.save()
    }

    // MARK: - 말씀구절 삽입 (설계 문서 2.2 S-SER2 "말씀구절 스타일의 특수성")

    /// `SermonVerseReferencePicker`가 확정한 구절을 에디터 본문에 새 `.verseQuote` 문단으로 삽입하고,
    /// 그 문단 순번과 함께 `SermonVerseReference`를 저장한다(좌표가 구조적으로 정확).
    private func insertVerseQuote(text: String, bookId: Int, chapter: Int, verseStart: Int, verseEnd: Int?) {
        let paragraphIndex = proxy.insertVerseQuoteParagraph(text: text, settings: .shared)
        currentStyle = .verseQuote
        let reference = subject.makeVerseReference(
            bookId: bookId, chapter: chapter, verseStart: verseStart, verseEnd: verseEnd,
            paragraphIndex: paragraphIndex
        )
        modelContext.insert(reference)
        // 텍스트 스토리지를 직접 바꾸면 `didProcessEditing`이 바인딩을 비동기(`DispatchQueue.main.async`)로
        // 뒤늦게 갱신한다 — 바로 저장하면 방금 삽입한 구절이 빠질 수 있어 한 틱 미뤄 저장한다.
        DispatchQueue.main.async {
            save()
        }
    }
}
