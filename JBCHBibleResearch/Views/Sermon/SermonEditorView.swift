//
//  SermonEditorView.swift
//  JBCHBibleResearch
//
//  S-SER2 "설교 작성 — 프리셋 스타일 리치 에디터" — 설계 문서
//  claude/sermon-management-screens-and-schema.md 2.2 S-SER2 참고.
//
//  [2026-09-28 3단계(에디터) 신설] `SermonComingSoonView(mode: .editor, ...)`를
//  대체한다. 메인 `Sermon`과 특정 회차 `SermonDelivery` 양쪽을 같은 화면(이
//  파일 하나)으로 편집한다 — "화면은 S-SER2 하나를 공유하되 대상만 다르다"
//  (설계 문서 2.2 S-SER1a). 제목 편집은 이 화면의 몫이 아니다 — `SermonDetailView.
//  titleSection` 상단 주석이 이미 "본문 편집은 에디터의 몫, 제목은 상세 화면의
//  몫"으로 역할을 나눴고, 애초에 `SermonDelivery`엔 title 필드 자체가 없다(설계
//  문서 3장) — 대주제(mainTheme) 문단이 사실상 제목 역할을 한다(목업의 "#
//  거듭남이란 무엇인가" 예시 참고).
//
//  [2026-09-28 디자인 정합화] 사용자 지적 — "디자인이 목업 html과 너무 차이가
//  큼." 목업(`Editor.dc.html`/`MacEditor.dc.html`)은 문단 스타일 6종을 항상
//  보이는 가로 "필(pill)" 한 줄로 보여준다 — 예전엔 `Menu` 드롭다운 하나로
//  줄였었다(그때 주석 — "iPad/macOS 전용 pill 한 줄 레이아웃은 시각적 향상
//  사항이라 이번 라운드에서는 만들지 않았다, 근거 없는 추가 작업을 만들지
//  않는다는 원칙"). 이번엔 사용자가 명시적으로 "목업대로 반영"을 요청했으므로
//  그 근거가 생겨, 예고했던 pill 한 줄 레이아웃을 이제 만든다 — 드롭다운
//  기능을 없애는 게 아니라 상호작용 방식만 "펼쳐서 고르기"에서 "항상 보이는
//  6개 중 탭"으로 바꾼 것뿐이라 요구사항(문단 스타일 지정)은 그대로다. 굵게/
//  기울임/말씀구절 추가는 계속 남겨 두되(실제로 쓰는 기능이라 목업에 없다고
//  없애지 않음) pill 줄 아래 두 번째 줄로 옮겼다.
//

import SwiftUI
import SwiftData
import BibleResearchModels
#if os(iOS)
import UIKit
#endif


/// [2026-09-29 신설] 사용자 요청 — "설정-테마색상에 따른 디자인 색상 변화
/// 필요." `DocumentsHomeView`/`BibleReadingView`/`WordNoteHomeView`/
/// `SearchView`가 이미 각자 파일에 두고 있는 것과 완전히 같은 타입·같은
/// 구현(그 파일들 주석 — "iOS 16+ 공식 API + WCAG 상대휘도로 다크/라이트
/// 아이템 색 결정")이다.
///
/// ⚠️ [2026-09-29 수정, 빌드 에러 fix] 처음엔 "내 설교" 화면 3개가 공유하는
/// `SermonSupport.swift`에 `private` 없이 한 번만 선언했었다 — 사용자 보고,
/// Xcode 에러 "Invalid redeclaration of 'ThemedNavigationBarBackgroundModifier'"
/// (SearchView.swift:54). 원인: Swift는 파일 최상위의 `private`(=`fileprivate`)
/// 선언과 다른 파일의 `private` 아닌(= internal) 같은 이름 선언이 같은
/// 모듈 안에 있으면, 접근 범위와 무관하게 이름 충돌로 처리한다 — 기존 4개
/// 파일이 서로 충돌 없이 같은 이름을 쓸 수 있었던 건 넷 다 예외 없이
/// `private`였기 때문이다. 그래서 공유하는 대신, 그 4개 파일과 완전히 같은
/// 관례대로 이 파일에도 `private`로 다시 선언한다(기능당 하나 공유가 아니라
/// 파일마다 중복 — 이 프로젝트가 실제로 쓰는 관례는 후자였다).
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

/// `RichTextEditor.swift`의 파일 스코프 `toolbarFontSizes`와 같은 이유 — 이
/// 화면의 6종 프리셋 크기(16/17/19/20/24/34)를 모두 포함해 자주 쓰는 값들을
/// 더했다.
private let sermonToolbarFontSizes: [CGFloat] = [12, 13, 14, 15, 16, 17, 19, 20, 22, 24, 28, 32, 34, 40]

struct SermonEditorView: View {
    let subject: SermonEditingSubject
    /// [2026-09-29 신설] 사용자 요청 — "새 설교 작성 레이어 팝업이 필요없지
    /// 않은가? ... 제목칸을 넣고 띄우는 것으로 하면 될 것 같음." 예전엔
    /// `SermonCreationSheet`(제목+첫 모임+날짜 입력 시트, `SermonHomeView.swift`
    /// 맨 아래에 있었음)가 이 정보를 먼저 받은 뒤에만 에디터로 이동했다 —
    /// 이제 그 시트를 통째로 없애고, 곧장 이 에디터를 "제목 입력 필드가 붙은
    /// 새 설교 작성 화면"으로 띄운다. `true`일 때만 새 설교용 제목 입력이
    /// 보이고, `save()`가 "제목 또는 본문 중 하나라도 있어야 실제로
    /// insert한다"는 지연 삽입 규칙을 적용한다 — 기존 요구사항("아무 입력
    /// 없이 닫으면 저장 안 함")은 그대로 유지하고, 검증 위치만 시트에서
    /// 이 화면으로 옮겼을 뿐이다. "날짜는 입력받지 말고 현재 시간을
    /// 수정일자로 등록" 요구사항은 별도 처리 없이도 이미 만족된다 —
    /// `save()`가 매번 호출하는 `subject.touchUpdatedAt()`이 저장 시점의
    /// 현재 시각을 `updatedAt`에 넣기 때문(첫 모임/날짜 선택 단계 자체를
    /// 아예 없앴다).
    var isNewSermon: Bool = false
    /// 아이폰은 `navigationDestination(item:)`(값 기반 push)으로, 아이패드·
    /// 맥은 `SermonHomeView.splitContent`가 오른쪽 패널에 이 화면을 직접
    /// 얹는 방식으로 띄운다 — 둘 다 `.sheet`/`.fullScreenCover`가 아니라서
    /// `@Environment(\.dismiss)`가 기댈 프레젠테이션이 없다(특히 아이패드·
    /// 맥 쪽은 동작하지 않는다). 대신 호출부(`SermonHomeView`)가 자기
    /// `pendingNewSermon` 상태를 nil로 돌리는 클로저를 넘겨받아, 두 플랫폼
    /// 모두 같은 코드로 "취소/닫기"를 구현한다.
    var onRequestClose: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    /// [2026-09-30 신설] `onRequestClose`가 없는 곳(아이폰 `NavigationLink`로 push된
    /// 편집기, `SermonDetailView.editorButton`)에서도 마인드맵 "설교문 적용"이
    /// 이 화면을 닫을 수 있게 하는 대체 수단 — push된 화면에서는 `dismiss()`가
    /// 실제로 뒤로 간다(위 `onRequestClose` 주석은 "얹힌 뷰/창"에서 동작하지
    /// 않는다는 얘기다).
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment

    @State private var contentHtml: String = ""
    @State private var contentText: String = ""
    @State private var paragraphStyles: String = ""
    @State private var currentStyle: SermonParagraphStyle = .body
    @State private var isVersePickerPresented = false
    @State private var hasLoaded = false
    /// 새 설교 제목 입력 상태 — `isNewSermon`일 때만 쓰인다.
    @State private var title: String = ""
    /// [2026-09-29 신설] `isNewSermon`일 때 실제 `modelContext.insert(sermon)`을
    /// 이미 했는지 — 한 번 삽입한 뒤에는 같은 세션 안에서 중복 삽입하지
    /// 않도록 `save()`가 이 값으로 분기한다.
    @State private var hasInsertedNewSermon = false
    /// [2026-09-30 신설] 마인드맵 "설교문 적용"(`SermonMindMapExporter.apply`)이
    /// 이 설교의 본문을 바깥에서 바꿨다고 알려 왔을 때 true — 이 편집기가 들고
    /// 있는 옛 본문 사본이 `onDisappear → save()`로 방금 적용된 내용을
    /// 덮어쓰는 것을 막는다. 아래 `.onSermonExternalContentChange` 참고.
    @State private var skipSaveOnDisappear = false

    /// [2026-09-29 신설] 요구사항 — "태그 입력은 메인 설교문, 모임에 따른
    /// 설교문 하단에 추가할 수 있도록 할 것." `subject`가 `.sermon`이면
    /// `Sermon.sermonTags`, `.delivery`면 새로 추가한 `SermonDelivery.
    /// deliveryTags`를 가리킨다(`SermonEditingSubject.tags`, SermonSupport.
    /// swift) — 두 태그 집합은 서로 완전히 독립적이다. `SermonDetailView.
    /// tagSection`과 같은 패턴(로컬 캐시 + `TagDeduplication.findOrCreateTag`)을
    /// 그대로 따른다.
    @State private var tags: [Tag] = []
    @State private var tagInput = ""
    @State private var tagSuggestions: [Tag] = []
    @State private var hasLoadedTags = false

    private let proxy = SermonParagraphEditingProxy()

    private var settings: UserSettingsStore { .shared }

    /// [2026-09-29 수정] 테마색상 반영 — `SermonSupport.swift`의 새 판 참고
    /// (`SermonHomeView.accent`/`SermonDetailView.accent`와 같은 이유·같은 코드).
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

    /// [2026-09-29 신설] "취소"/"완료" 라벨 전환용 — 새 설교 작성 중 제목
    /// 또는 본문 중 하나라도 입력돼 있는지. `save()`의 지연 삽입 가드
    /// (`!trimmedTitle.isEmpty || !trimmedContent.isEmpty`)와 정확히 같은
    /// 기준을 써야 라벨이 실제 저장 여부와 항상 일치한다.
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
        .navigationTitle(isNewSermon ? "새 설교 작성" : "설교 작성")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .modifier(ThemedNavigationBarBackgroundModifier(color: settings.bibleBackgroundColor))
        .toolbar {
            // [2026-09-29 수정] 사용자 지적 — "작성한 다음에 왼쪽상단 '<'
            // 버튼을 눌러야 하나? '취소'를 눌러야 하나?" 아이폰은 이 화면이
            // `navigationDestination(item:)`로 push된 것이라 시스템 뒤로가기
            // "<"가 이미 있고, 그게 `pendingNewSermon`을 nil로 되돌려
            // `onDisappear → save()`(지연 삽입/버림)를 그대로 태운다 — 여기
            // "취소" 버튼은 정확히 같은 동작을 하는 두 번째 컨트롤이라
            // 혼란만 줬다. 그래서 아이패드·맥(뒤로가기 자체가 없는, 오른쪽
            // 패널에 직접 얹히는 경우)에서만 보이도록 좁힌다 — iOS에서도
            // `#if os(iOS)`가 아니라 `isPhoneIdiom`으로 판단해야, 아이패드
            // "본체"(터치 기반, 이 뷰가 여전히 오른쪽 패널에 얹히는 폭)에서도
            // 이 버튼이 그대로 보인다.
            if isNewSermon && !isPhoneIdiom {
                ToolbarItem(placement: .cancellationAction) {
                    // [2026-09-29 수정] 사용자 결정 — 위 "취소를 누르면
                    // 저장되는 게 맞나?" 질문에 대한 답으로, 자동 저장
                    // 동작(제목/본문 중 하나라도 있으면 닫을 때 저장) 자체는
                    // 그대로 두고 라벨만 실제 동작에 맞게 바꾼다 — 뭔가
                    // 입력돼 있으면 "완료"(눌러도 그 내용이 저장됨을 정확히
                    // 알려줌), 제목·본문이 둘 다 비어 있으면 "취소"(눌러도
                    // 아무것도 저장되지 않음 — 실제로 `save()`의 지연 삽입
                    // 가드가 그 경우엔 저장을 건너뛰므로 이름이 사실과
                    // 맞는다).
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
            // [2026-09-30 변경] 마인드맵이 본문을 바꾼 뒤 닫히는 경우엔 저장하지
            // 않는다(옛 사본이 새 본문을 덮어쓰기 때문) — 그 직전에 이미
            // `onFlush`에서 저장을 마쳤다.
            if !skipSaveOnDisappear { save() }
        }
        // [2026-09-30 신설] 사용자 요청 — 마인드맵 "설교문 적용" 시 편집 화면을
        // 자동으로 닫기. 순서: (1) `onFlush` — 적용 직전 지금까지 입력한 본문을
        // 즉시 저장해 마인드맵이 최신 본문 뒤에 붙이게 하고, (2) 마인드맵이
        // 적용·저장한 뒤 (3) `onReplaced` — 저장 없이 닫는다. 닫는 방법은
        // 호출부가 넘긴 `onRequestClose`(홈 오른쪽 패널/별도 창), 없으면
        // `dismiss()`(아이폰 push).
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
    // 편집 화면에 제목칸만 추가", 2026-09-29) — `isNewSermon`일 때만 보인다.
    // 기존 설교/회차 편집 화면(제목은 `SermonDetailView.titleSection`의 몫,
    // `SermonEditorView.swift` 상단 주석 참고)에는 영향을 주지 않는다.
    /// [2026-09-29 수정] 사용자 요청 — "제목 수정기능은 편집에디터 화면으로
    /// 이동." 지금까지는 `isNewSermon`(새 설교 작성)일 때만 이 필드가 보였고,
    /// 기존 설교 제목 수정은 `SermonDetailView.titleSection`(오른쪽 패널
    /// 인라인 TextField)이 전담했다 — 그 필드를 읽기 전용으로 바꾸면서(그
    /// 파일 참고) 제목 수정 기능 자체를 이 에디터 화면 하나로 모은다.
    /// `.sermon`(메인 설교문) 대상일 땐 새 설교든 기존 설교든 항상 보이고,
    /// `.delivery`(회차 사본)는 원래도 별도 제목이 없어(`SermonSupport.swift`의
    /// `SermonEditingSubject`엔 애초에 `title` 프로퍼티가 없다) 그대로 뺀다.
    /// 새 설교는 아직 `modelContext`에 없는 `@State private var title`에,
    /// 기존 설교는 이미 저장된 `Sermon` 객체(`sermon.title`)에 직접
    /// 바인딩한다 — 후자는 `SermonDetailView.titleSection`이 쓰던 것과
    /// 똑같이, 타이핑마다 메모리상의 모델을 바로 바꾸고 실제 디스크 저장은
    /// `save()`(제출/화면 이탈 시 호출)가 맡는다.
    @ViewBuilder
    private var titleField: some View {
        if case .sermon(let sermon) = subject {
            VStack(alignment: .leading, spacing: 4) {
                if isNewSermon {
                    // [2026-09-29 수정] 사용자 요청 — "새 설교 작성 시 제목
                    // 하단 설명 문구 삭제." 저장 조건 자체(제목/본문 중
                    // 하나라도 있어야 저장됨)는 `save()`의 지연 삽입 검증
                    // 로직에 그대로 남아 있다 — 지워지는 건 이 안내 문구 한
                    // 줄뿐, 동작은 바뀌지 않는다.
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
    // ⚠️ 목업(Editor.dc.html/MacEditor.dc.html)은 이 태그 줄을 문단 목록과
    // 같은 스크롤 영역 안, 맨 아래에 둔다. 실제 에디터는 문단 목록이 SwiftUI
    // `ForEach`가 아니라 `SermonParagraphEditor`(UITextView/NSTextView를 감싼
    // 대표 뷰, `SermonParagraphEditor.swift`)라 같은 스크롤 안에 다른 SwiftUI
    // 콘텐츠를 끼워 넣을 수 없다 — 그래서 위 `styleToolbar`(상단 고정)와
    // 대칭으로 이 태그 줄을 화면 맨 아래 고정 영역으로 둔다. "설교문 하단"
    // 이라는 요구사항 자체(태그를 본문 아래에서 입력할 수 있어야 한다)는
    // 그대로 만족한다.
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

    /// `.delivery`를 편집할 때만 보인다. 누르면 S-SER3(뷰어)로만 이동한다 —
    /// S-SER2(편집)로는 구조적으로 연결하지 않는다(설계 문서 2.2 S-SER2 —
    /// "편집 화면 자체를 만들지 않음"으로 수정불가를 보장). [2026-09-28
    /// 디자인 정합화] 목업의 강조 배너(액센트 배경+테두리)와 맞췄다 — 예전엔
    /// `Color.secondary.opacity(0.08)` 밋밋한 배경이었다.
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
            // [2026-09-29 수정] 사용자 요청 — "대주제,중주제,소주제...본문
            // 스타일 옆에 볼드 이텔릭을 붙여서 한줄로 표시되게 할것." 원래
            // 굵게/기울임 버튼은 스타일 pill 줄 바로 아래 별도 줄에 있었다 —
            // 스타일 pill들이 가로 스크롤 안에 있어야 하는 이유(아이폰 폭에서
            // 6종이 다 안 잘리게)는 그대로 살리면서, 굵게/기울임 버튼만
            // 스크롤 영역 밖 같은 `HStack`에 붙여 "한 줄"로 보이게 했다 —
            // 두 버튼은 항상 고정 위치에 보이고, pill들만 그 왼쪽 공간
            // 안에서 스크롤된다.
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

    /// [2026-09-29 5번 항목 신설] 사용자 요청 — "에디터 기능에서 문단 정렬,
    /// 글자 색상, 글자크기, 글꼴 선택을 지정할 수 있도록 기능을 추가할 것."
    /// `RichTextEditorToolbarContent`(Views/Memo/RichTextEditor.swift)의 같은
    /// 항목들과 같은 구성(색상 팔레트/글꼴 메뉴/크기 메뉴/정렬 버튼)을 그대로
    /// 따르되, 각 메뉴 맨 위에 "프리셋 ○○로" 항목을 추가했다 — 눌러 두면
    /// `SermonParagraphEditingProxy`가 `nil`을 넘겨 지금 문단 스타일의 프리셋
    /// 값으로 되돌린다(수동 지정을 취소하는 유일한 방법이므로 빼면 안 됨).
    /// 정렬의 "되돌리기"는 `.natural`을 직접 고르는 것과 같아 별도 메뉴 없이
    /// 버튼 하나로 뒀다.
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

    /// [2026-09-29 수정] `isNewSermon`일 때는 `SermonCreationSheet`가 하던
    /// "만들기 전까지는 insert하지 않는다" 검증을 여기로 옮겼다 — 제목·본문이
    /// 모두 비어 있으면 그냥 반환해 아무것도 insert/save하지 않는다(요구사항
    /// "아무런 입력없이 닫으면 데이터 등록되지 않도록 할 것"은 그대로 유지).
    /// 제목 또는 본문 중 하나라도 있으면 그 시점에 딱 한 번만
    /// `modelContext.insert(sermon)`하고(`hasInsertedNewSermon`로 중복 삽입
    /// 방지), 그 뒤엔 원래부터 있던 공통 저장 블록(아래)을 그대로 탄다 —
    /// `subject.touchUpdatedAt()`이 매 저장마다 `updatedAt = .now`를 넣으므로
    /// "현재 시간을 수정일자로 등록"은 별도 코드 없이 항상 성립한다.
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
        // [2026-09-29 5번 항목] 이번 저장 시점의 프리셋 값을 스냅샷으로 찍어
        // 둔다 — 다음에 열 때 `SermonParagraphStyleCodec.applyStyle`이 이
        // 스냅샷과 실제 값을 비교해 사용자의 수동 서식 지정을 가려낸다
        // (`Sermon.styleFontSnapshot` 상단 주석 참고).
        subject.styleFontSnapshot = SermonParagraphStyleCodec.captureSnapshot(settings: settings)
        subject.touchUpdatedAt()
        try? modelContext.save()
        // [2026-09-29 추가] 사용자 요청 — "통합 검색에 '내 설교' 탭... + 성경구절
        // 파싱." `MemoDetailView`/`WordSummaryEditorView`가 저장 직후 각자의
        // `reindexMemo`/`reindexWordSummary`를 부르는 것과 같은 자리·같은 이유
        // (`BibleReferenceIndexingService.swift` 상단 주석 — "그 저장 로직 바로
        // 다음 줄에서 부른다"). 회차 사본(`.delivery`)은 이번 요청 범위 밖이라
        // 인덱싱하지 않는다.
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

    /// `SermonVerseReferencePicker`가 확정한 구절을 (1) 에디터 본문에 새
    /// 문단으로 삽입하고 `.verseQuote` 스타일을 지정한 뒤, (2) 그 문단 순번과
    /// 함께 `SermonVerseReference`를 만들어 저장한다 — 손으로 "요 3:16"이라고
    /// 타이핑하는 것과 달리 좌표가 구조적으로 정확하다(설계 문서 근거).
    private func insertVerseQuote(text: String, bookId: Int, chapter: Int, verseStart: Int, verseEnd: Int?) {
        let paragraphIndex = proxy.insertVerseQuoteParagraph(text: text, settings: .shared)
        currentStyle = .verseQuote
        let reference = subject.makeVerseReference(
            bookId: bookId, chapter: chapter, verseStart: verseStart, verseEnd: verseEnd,
            paragraphIndex: paragraphIndex
        )
        modelContext.insert(reference)
        // `insertVerseQuoteParagraph`가 텍스트 스토리지를 직접 바꾸므로
        // `NSTextStorageDelegate.didProcessEditing`이 비동기(`DispatchQueue.
        // main.async`, `SermonParagraphEditor.swift` 참고)로 뒤늦게
        // `contentHtml`/`contentText`/`paragraphStyles` 바인딩을 갱신한다 —
        // 그 갱신을 기다리지 않고 바로 저장하면 방금 삽입한 구절이 아직
        // 반영되지 않은 이전 상태로 저장될 수 있어, 다음 실행 루프로 한 틱
        // 미뤄 저장한다.
        DispatchQueue.main.async {
            save()
        }
    }
}
