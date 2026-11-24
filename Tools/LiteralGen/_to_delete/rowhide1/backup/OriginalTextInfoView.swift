//
//  OriginalTextInfoView.swift
//  JBCHBibleResearch
//
//  선택한 절의 히브리어/그리스어 원어 단어를 카드 그리드로 보여주는 "원문 정보" 시트.
//  데이터셋은 STEPBible-Data(CC BY 4.0)이고, 카드에는 한글 뜻풀이·원어·음역·형태소(문법) 설명·
//  Strong 번호를 표시한다. 원문은 번역본과 무관하게 book/chapter/verse에만 종속되므로
//  번역본 선택이나 구간 드래그가 필요 없다. 형태소 설명은 `HebrewMorphologyDescriber`가
//  히브리어만 지원해 그리스어는 영어 뜻풀이로 대체한다.
//
//  ⚠️ 한글 뜻풀이: 오픈 라이선스 한글 Strong 사전이 없어 STEPBible의 영어 뜻풀이를 Apple
//  `Translation` 프레임워크로 번역하고, `StrongGlossTranslation`(SwiftData)에 Strong 번호
//  단위로 캐싱해 두 번째부터는 재번역 없이 캐시를 읽는다. 기계번역 수준이라 신학적 표준
//  역어와 다를 수 있다.
//
//  [2026-10-12] 다국어 개편(목업 승인):
//  - 구절 카드: 성경 조회에 켜 둔 열의 번역본 본문(`verseSources`). 차이 설명이 있는 번역본이 둘 이상이면 칩으로 전환.
//    열 정보가 없으면 예전처럼 KRV.
//  - 직역 카드: 앱 언어 직역(AI) → 원어 어순(STEPBible 문맥 번역) → 영어 직역 LSV(항상 접힌 상태로 시작) →
//    번역과의 차이(고른 번역본 이름 표시). 데이터 출처는 `LiteralCommentaryService`.
//  - 단어 카드: 뜻풀이를 앱 언어로(한국어는 기존 캐시·수정 기능 그대로, 다른 언어는 기기 번역 결과를 실행 중에만
//    메모리에 보관하고 수정 기능 없음, 영어는 원문 뜻 그대로) + "문맥" 줄(`translationEn`).
//
//  [2026-11-02 interlin1] 원문 정보 개편(사양: original-text-interlinear-proposal-2026-10-31, 목업 승인):
//  - 직역 카드: "원어 어순" 줄을 "단어별" 칸(위 = 직역 속 말 / 가운데 = 문맥 영어 / 아래 = 원어)으로 바꿨다. 칸을 누르면 아래 원어 카드로
//    스크롤해 잠깐 강조한다. 영어 직역(LSV)은 접지 않고 항상 보인다.
//  - 원어 카드: 원어 → 음역·Strong → (품사 정보, 펼쳤을 때만) → 사전 뜻 → "이 절에서" → [쓰인 구절 | 네이버 · biblehub].
//    연필은 오른쪽 위 구석. "문맥" 줄은 단어별 칸 가운데 줄로 옮겨 카드에서 뺐다.
//  - 쓰인 구절(`OriginalWordOccurrencesView`): iOS는 이 시트의 내비게이션 스택에 push, macOS는 시트 안에서 화면을 바꾼다.

import SwiftUI
import Translation
import SwiftData
import BibleResearchModels

/// [2026-10-12] 원문 정보 화면 구절 카드에 보여줄 번역본 한 줄 — 성경 조회 화면에 켜 둔 열(왼쪽부터)의 이 절 본문.
/// 차이 설명 데이터가 있는 번역본이 둘 이상이면 칩으로 바꿔 볼 수 있다.
struct OriginalTextVerseSource: Hashable, Identifiable {
    var id: String { code }
    /// `TranslationRegistry.code`.
    let code: String
    let displayName: String
    /// 이 절 본문. 그 번역본에 이 절이 없으면 빈 문자열.
    let text: String
    /// [2026-11-02 interlin1] 이 번역본 SQLite 파일 경로(`BibleReadingViewModel.verseTextFilePath`) — "쓰인 구절" 본문 미리보기용.
    /// nil이면 미리보기 없이 참조만 보인다.
    var databasePath: String? = nil
}

struct OriginalTextInfoView: View {
    /// 화면 배경과 본문 보조 텍스트 색을 테마에 맞추는 데 쓴다.
    private var settings: UserSettingsStore { .shared }
    let bookId: Int
    let chapter: Int
    let verseNumber: Int
    /// "메모하기로 전환" 툴바 버튼 콜백. 호출부가 이 시트를 닫고 메모하기 시트를 여는 순서를
    /// 책임진다(한 화면이 시트 두 개를 동시에 띄울 수 없음).
    let onSwitchToMemo: () -> Void
    /// `VerseZoomView`의 같은 이름 프로퍼티들과 같은 목적 — `VerseNavArrowsModifier` 참고. 기본값이 있어 생략 가능.
    var onNavigateToPreviousVerse: () -> Void = {}
    var onNavigateToNextVerse: () -> Void = {}
    var canGoToPreviousVerse: Bool = false
    var canGoToNextVerse: Bool = false
    /// 성경 조회 화면에 켜 둔 열(왼쪽부터)의 이 절 본문. 비어 있으면 KRV 본문을 직접 읽는다.
    var verseSources: [OriginalTextVerseSource] = []
    /// [2026-11-02 interlin1] "쓰인 구절"에서 절을 골랐을 때. 호출부가 이 시트를 닫고 성경 화면을 그 장·절로 옮긴다
    /// (시트가 닫힌 뒤에 옮겨야 한다 — `onSwitchToMemo`와 같은 이유).
    var onOpenVerse: (BibleVerseRef) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    /// 원어 색을 라이트/다크에 맞춰 고르기 위해 필요하다.
    @Environment(\.colorScheme) private var colorScheme
    @State private var words: [OriginalWordInfo] = []
    /// 앱 언어 직역(`LiteralCommentaryService`). 없으면 직역 문장 줄을 숨긴다.
    @State private var appLiteral: String?
    /// 공통 영어 직역(LSV). 없으면 그 칸을 숨긴다. [2026-11-02 interlin1] 접기 없이 항상 보인다.
    @State private var literalEnglish: LiteralEnglishInfo?
    /// [2026-11-02 interlin1] 원어 단어 위치(`words`의 0부터 위치) → 직역 문장 속 말(`LiteralCommentaryService.alignedPhrases`).
    /// 짝 데이터가 없으면 비어 있고, 단어별 칸 위 줄은 "—", 원어 카드의 "이 절에서" 줄은 숨는다.
    @State private var alignedPhrases: [Int: String] = [:]
    /// [2026-11-04 mergecell] `alignedPhrases`와 같은 짝의 직역 속 시작 위치까지. 연이은 단어가 같은 구간을 함께 쓰는지 가릴 때 쓴다(`wordCellRuns`).
    @State private var alignedSpans: [Int: LiteralCommentaryService.AlignedPhrase] = [:]
    /// [2026-11-02 interlin1] Strong 번호 → 쓰인 절 수. 화면을 열 때(절이 바뀔 때) 백그라운드에서 한 번에 센다. 아직 없으면 버튼에 숫자 없이.
    @State private var verseCounts: [String: Int] = [:]
    /// [2026-11-02 interlin1] 단어별 칸을 눌러 잠깐 강조 중인 원어 카드 위치와, 강조를 끄는 예약의 차례 번호(나중 누름이 앞 예약을 무효로 한다).
    @State private var highlightedWordIndex: Int?
    @State private var highlightGeneration = 0
    /// [2026-11-02 interlin1] "쓰인 구절" 화면 대상 단어. nil이면 원문 정보 본 화면.
    @State private var occurrenceWord: OriginalWordInfo?
    /// [2026-11-02 interlin1] 지금 화면에 읽어 둔 절(책-장-절). 절이 바뀔 때만 쓰인 구절 화면·강조를 닫는다(번역본 열 목록만 바뀐 경우는 그대로).
    @State private var loadedVerseKey: String?
    /// [2026-11-02 interlin1] 원어 카드 품사 정보 펼침 — 모든 카드 공통, 처음엔 접힘, 마지막 상태를 기억한다.
    /// 키는 기존 UserDefaults 키 규칙(`기능.항목`, 예: "bibleToolRail.collapsed", "sermon.listSort")을 따른다.
    @AppStorage("originalTextInfo.showsMorphology") private var showsMorphology = false
    /// 번역본 코드 → 차이 설명. `verseSources` 중 데이터가 있는 번역본만 들어 있다.
    @State private var differences: [String: String] = [:]
    /// 구절 카드·차이 설명에 지금 보여주는 번역본 코드.
    @State private var selectedSourceCode: String?
    /// 한국어가 아닌 앱 언어의 단어 뜻(영어 뜻 → 기기 번역). 키는 영어 뜻 문자열.
    @State private var foreignGlosses: [String: String] = [:]
    /// 실행 중 번역 결과 보관(시트를 다시 열어도 재번역하지 않도록). 키 "언어|영어 뜻".
    private static var foreignGlossCache: [String: String] = [:]
    /// 번들 기본 번역본(KRV 개역한글)에서 읽은 절 본문. 원문 정보는 절에만 종속되므로
    /// 화면에 켜 둔 번역본과 무관하게 항상 KRV로 고정한다.
    @State private var krvVerseText: String = ""
    @State private var koreanGlosses: [String: String] = [:]
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var isTranslating = false
    /// 편집 중인 단어(연필 아이콘을 누른 단어). nil이면 편집 알림창이 뜨지 않는다.
    @State private var editingWord: OriginalWordInfo?
    @State private var editingText: String = ""

    /// 링크 색 — 시스템 파랑 대신 테마 포인트색(AccentColor). 맥·아이패드·아이폰 공통(2026-10-02).
    private var linkTint: Color { Color.accentColor }

    private var displayTitle: String {
        let name = BooksProvider.shared.book(id: bookId)?.displayName ?? String(localized: "책 \(bookId)")
        return String(localized: "\(name) \(chapter):\(verseNumber) 원문 정보")
    }

    /// 시트 본문(스크롤 영역). macOS/iOS 모두 같은 내용을 쓴다.
    /// [2026-11-02 interlin1] 단어별 칸 → 원어 카드 스크롤을 위해 `ScrollViewReader`로 감쌌다.
    private var mainScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // biblehub 인터리니어 링크(시스템 기본 브라우저로 열림). 슬러그를 못 찾거나 URL이 안 만들어지면
                    // 깨진 링크를 보여주는 대신 숨긴다.
                    if let interlinearURL = bibleHubInterlinearURL {
                        Link(destination: interlinearURL) {
                            Label("영문-원어성경", systemImage: "safari")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(linkTint)
                    }
                    // 원어 데이터가 없는 절에서도 구절 본문은 보이도록 `words.isEmpty` 분기 밖에 둔다.
                    verseCard
                    // 직역 카드 — 구절 아래, 원어 카드 위. 보여줄 내용이 하나도 없으면 숨긴다.
                    if hasLiteralCardContent {
                        literalCard(proxy: proxy)
                    }
                    if words.isEmpty {
                        ContentUnavailableView(
                            "원문 정보 없음",
                            systemImage: "character.book.closed",
                            description: Text("이 절에 대한 원문 데이터를 찾을 수 없습니다.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            wordsHeader
                            // 화면 너비에 맞춰 여러 열로 자동 배치한다.
                            LazyVGrid(columns: gridColumns, spacing: 12) {
                                // 원본 DB에 같은 절·같은 word_order가 겹치는 행(17쌍)이 있어 `word.id` 대신 위치로 구분한다.
                                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                                    wordCard(word, index: index)
                                        .id(Self.wordCardScrollID(index))
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(settings.bibleBackgroundColor ?? Color.clear)
    }

    /// 시트 껍데기. macOS는 시스템 도구 모음이 제목 줄·버튼 줄을 시스템 회색으로 그려 본문의 테마 배경과 색이 끊겼으므로,
    /// 내비게이션 스택을 쓰지 않고 시트 안에 제목 줄(`VerseSheetHeader`)과 하단 버튼 줄(`VerseSheetFooter`)을 직접 그린다
    /// (확대보기 `VerseZoomView`와 같은 바탕·선·그림자 — 2026-10-02 목업 결정). iOS/iPadOS는 기존 내비게이션 바 툴바를 그대로 쓴다.
    /// [2026-11-02 interlin1] 쓰인 구절: macOS는 내비게이션 스택이 없어 같은 시트 안에서 본문 자리를 바꾼다(아래 버튼 줄은 그대로).
    /// 본 화면은 숨기기만 하고 계층에 남겨 돌아왔을 때 스크롤 위치가 그대로다. iOS/iPadOS는 기존 내비게이션 스택에 push한다.
    @ViewBuilder
    private var sheetRoot: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            ZStack {
                VStack(spacing: 0) {
                    VerseSheetHeader(title: displayTitle)
                    mainScroll
                }
                .opacity(occurrenceWord == nil ? 1 : 0)
                .allowsHitTesting(occurrenceWord == nil)
                .accessibilityHidden(occurrenceWord != nil)
                if let word = occurrenceWord {
                    occurrencesView(for: word)
                }
            }
            VerseSheetFooter {
                // 내비게이션 툴바의 `.cancellationAction`이 주던 Esc 닫기를 `.cancelAction` 단축키로 유지한다.
                Button("닫기") { dismiss() }
                    .buttonStyle(BibleBarButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 0)
                // 아이콘은 앱 전체에서 "메모"를 가리키는 `text.bubble`로 통일해, 누르면 메모하기로 간다는 걸 알 수 있게 한다.
                Button(action: onSwitchToMemo) {
                    Label("메모하기", systemImage: "text.bubble")
                }
                .buttonStyle(BibleBarButtonStyle())
                .help("메모하기로 전환")
            }
        }
        #else
        // 아이패드·아이폰: 시스템 내비게이션 바 대신 시트 안에 직접 그린 머리(닫기 · 세리프 제목) + 조작줄(‹ n절 › · 메모하기)
        // — `VerseZoomView`와 같은 부품(`VerseLayerHeader`/`VerseLayerStrip`). 2026-10-02 "구절 레이어 통일안".
        NavigationStack {
            VStack(spacing: 0) {
                VerseLayerHeader(title: displayTitle) {
                    Button("닫기") { dismiss() }
                        .buttonStyle(BibleBarButtonStyle(height: 40, cornerRadius: 10, fontSize: 15))
                }
                VerseLayerStrip(
                    verseLabel: String(localized: "\(verseNumber)절"),
                    canGoPrevious: canGoToPreviousVerse, canGoNext: canGoToNextVerse,
                    onPrevious: onNavigateToPreviousVerse, onNext: onNavigateToNextVerse
                ) {
                    // 아이콘은 앱 전체에서 "메모"를 가리키는 `text.bubble`로 통일(원문 정보 ↔ 메모하기 전환 버튼 한 쌍).
                    Button(action: onSwitchToMemo) {
                        Label("메모하기", systemImage: "text.bubble")
                    }
                    .buttonStyle(BibleBarButtonStyle(kind: .primary, height: 40, cornerRadius: 10, fontSize: 15))
                    .accessibilityLabel("메모하기로 전환")
                    // [2026-10-29 zoommenu2] 줄이 좁아 아이콘만 남을 때(`VerseLayerStrip` 4번 배치) 포인터를 올리면 이름이 보이게.
                    .help("메모하기")
                }
                mainScroll
            }
            .background(UserSettingsStore.shared.bibleBackgroundColor ?? Color.clear)
            .toolbar(.hidden, for: .navigationBar)
            // [2026-11-02 interlin1] 쓰인 구절. 화면 머리(‹ 원문 정보 · 제목)는 본 화면처럼 직접 그리고 시스템 바는 숨긴다.
            .navigationDestination(item: $occurrenceWord) { word in
                occurrencesView(for: word)
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
        #endif
    }

    var body: some View {
        sheetRoot
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 420)
        #endif
        // iOS는 조작줄(`VerseLayerStrip`)에 ‹ › 버튼이 있어 모서리 화살표를 쓰지 않는다.
        #if os(macOS)
        .modifier(VerseNavArrowsModifier(
            canGoPrevious: canGoToPreviousVerse,
            canGoNext: canGoToNextVerse,
            onPrevious: onNavigateToPreviousVerse,
            onNext: onNavigateToNextVerse
        ))
        #endif
        // `.task(id:)`로 절/장/권이 바뀔 때마다 다시 로드한다 — 시트가 열린 채 이전/다음 절로 이동해도
        // 원어 정보가 첫 절 데이터로 멈춰 있지 않도록 하기 위해서다.
        // 켜 둔 번역본 목록이 바뀌어도(차이 설명 대상이 달라지므로) 다시 읽는다.
        .task(id: "\(bookId)-\(chapter)-\(verseNumber)|\(verseSources.map(\.code).joined(separator: ","))") {
            loadWords()
            await loadVerseCounts()
        }
        .translationTask(translationConfiguration) { session in
            await translateMissingGlosses(session: session)
        }
        // Strong 번호 단위 캐시(`StrongGlossTranslation`)를 직접 고치므로, 같은 Strong 번호가 나오는
        // 다른 모든 절에도 수정이 적용된다(알림창 메시지에 명시).
        .alert(
            "한글 뜻풀이 수정",
            isPresented: Binding(
                get: { editingWord != nil },
                set: { isPresented in if !isPresented { editingWord = nil } }
            )
        ) {
            TextField("한글 뜻풀이", text: $editingText)
            Button("취소", role: .cancel) { editingWord = nil }
            Button("저장") { commitKoreanEdit() }
        } message: {
            if let word = editingWord {
                Text("\(word.originalText) (\(word.strongCode)) — 같은 Strong 번호가 나오는 다른 절에도 이 번역이 적용됩니다.")
            }
        }
    }

    // MARK: - 구절 카드

    /// 지금 고른 번역본(없으면 첫 열).
    private var currentSource: OriginalTextVerseSource? {
        verseSources.first { $0.code == selectedSourceCode } ?? verseSources.first
    }

    /// 칩으로 바꿔 볼 수 있는 번역본 — 차이 설명 데이터가 있는 열만(사용자 결정).
    private var sourcesWithDifference: [OriginalTextVerseSource] {
        verseSources.filter { differences[$0.code] != nil }
    }

    private var currentVerseText: String {
        if let source = currentSource { return source.text }
        return krvVerseText
    }

    @ViewBuilder
    private var verseCard: some View {
        let text = currentVerseText
        if !text.isEmpty || currentSource != nil {
            VStack(spacing: 10) {
                let chipSources = sourcesWithDifference
                if chipSources.count >= 2 {
                    // 차이 설명이 있는 번역본이 둘 이상일 때만 칩. 고르면 구절 본문과 아래 차이 설명이 함께 바뀐다.
                    FlowLayoutHStack(spacing: 6) {
                        ForEach(chipSources) { source in
                            sourceChip(source)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                } else if let source = currentSource {
                    Text(verbatim: source.displayName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                }
                // 메인 본문 목록(TranslationColumnView)과 같은 폰트/줄간격/글자색을 써서 "모양" 설정을 따른다.
                Text(verbatim: text.isEmpty ? "—" : text)
                    .font(UserSettingsStore.shared.bibleBodyFont)
                    .foregroundStyle(UserSettingsStore.shared.bibleTextColor ?? Color.primary)
                    .lineSpacing(UserSettingsStore.shared.bibleLineSpacing)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(cardBorderColor, lineWidth: 1)
            )
        }
    }

    private func sourceChip(_ source: OriginalTextVerseSource) -> some View {
        let isSelected = source.code == currentSource?.code
        return Button {
            selectedSourceCode = source.code
        } label: {
            Text(verbatim: source.displayName)
                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(isSelected ? Color.white : (settings.bibleTextColor ?? Color.primary))
                .background(
                    Capsule().fill(isSelected ? linkTint : cardBackground)
                )
                .overlay(
                    Capsule().stroke(isSelected ? linkTint : cardBorderColor, lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - 직역 카드

    private var currentDifference: String? {
        guard let code = currentSource?.code else { return nil }
        return differences[code]
    }

    private var hasLiteralCardContent: Bool {
        // [2026-11-02 interlin1] "원어 어순"(문맥 영어가 있는 단어만) 대신 단어별 칸 — 원어 단어가 하나라도 있으면 보인다.
        appLiteral != nil || !words.isEmpty || literalEnglish != nil || currentDifference != nil
    }

    /// AI 생성 표시 배지(직역·차이 설명). 고유 표기라 번역하지 않는다.
    private var aiBadge: some View {
        Text(verbatim: "AI")
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(linkTint)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(linkTint, lineWidth: 1))
    }

    private var sectionLabelColor: Color {
        settings.bibleTextColor?.opacity(0.6) ?? Color.secondary
    }

    private func literalCard(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let appLiteral {
                HStack(spacing: 6) {
                    Label("직역 (원어 그대로)", systemImage: "text.alignleft")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.75) ?? Color.secondary)
                    aiBadge
                }

                Text(verbatim: appLiteral)
                    .font(UserSettingsStore.shared.bibleBodyFont.italic())
                    .foregroundStyle(settings.bibleTextColor ?? Color.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            if !words.isEmpty {
                // [2026-11-02 interlin1] 단어별 칸 — "원어 어순" 줄을 대신한다. 원문 단어 순서대로 왼쪽부터 흘려 놓는다
                // (히브리어도 칸 순서는 왼쪽부터, 칸 안의 글자는 오른쪽→왼쪽 그대로).
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("단어별")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(sectionLabelColor)
                    Spacer(minLength: 0)
                    Text("위부터 직역 속 말 · 영어 · 원어")
                        .font(.system(size: 11))
                        .foregroundStyle(sectionLabelColor)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.top, appLiteral == nil ? 0 : 4)
                FlowLayoutHStack(spacing: 6, clampsItemsToRowWidth: true) {
                    // [2026-11-04 mergecell] 연이은 단어가 직역 속 같은 말을 함께 쓰면 한 칸으로 묶어 그 말을 한 번만 보인다.
                    ForEach(wordCellRuns, id: \.lowerBound) { run in
                        if run.count == 1 {
                            wordCell(words[run.lowerBound], index: run.lowerBound, proxy: proxy)
                        } else {
                            mergedWordCell(run, proxy: proxy)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 영어 화면은 직역이 곧 LSV(`Literal_en`의 basis = LSV)라 같은 문장을 또 보여주지 않는다.
            // [2026-11-02 interlin1] 접기(DisclosureGroup) 없이 항상 보인다.
            if let literalEnglish, literalEnglish.text != appLiteral {
                Rectangle()
                    .fill(cardBorderColor)
                    .frame(height: 1)
                Text("영어 직역 (LSV)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(sectionLabelColor)
                VStack(spacing: 6) {
                    // 원본의 시행 구분 표기 " || "는 줄바꿈으로 보여준다.
                    Text(verbatim: literalEnglish.text.replacingOccurrences(of: " || ", with: "\n"))
                        .font(.system(size: 14.5, design: .serif))
                        .foregroundStyle(settings.bibleTextColor ?? Color.primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .center)
                    // CC BY-SA 4.0 출처 표기(원문 표기 그대로).
                    Text(verbatim: "Literal Standard Version © 2020 Covenant Press · CC BY-SA 4.0")
                        .font(.system(size: 10.5))
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.45) ?? Color.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            if let difference = currentDifference, let source = currentSource {
                Rectangle()
                    .fill(cardBorderColor)
                    .frame(height: 1)

                HStack(spacing: 6) {
                    Label("번역과의 차이", systemImage: "arrow.left.arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(sectionLabelColor)
                    Text(verbatim: "· \(source.displayName)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(settings.bibleTextColor ?? Color.primary)
                        .lineLimit(1)
                    aiBadge
                }

                Text(verbatim: difference)
                    .font(.system(size: 13.5))
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.75) ?? Color.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(cardBorderColor, lineWidth: 1)
        )
    }

    // MARK: 단어별 칸 [2026-11-02 interlin1]

    /// 단어별 칸 하나(3줄): 위 = 직역 속 말(짝 없으면 "—"), 가운데 = 문맥 영어(`translationEn`), 아래 = 원어.
    /// 위 줄과 가운데 줄이 같은 말이면(영어 화면: 직역이 영어라 짝 말이 문맥 영어와 겹치기 쉽다) 가운데 줄을 비워 같은 말을 두 번 쓰지 않는다.
    /// 줄 자리는 남겨(투명) 모든 칸이 같은 높이로 줄 맞춰 놓이고, 원어 줄이 칸마다 같은 높이에 온다. 판정은 `isSameGloss`.
    /// 누르면 아래 같은 위치의 원어 카드로 스크롤하고 잠깐 강조한다.
    private func wordCell(_ word: OriginalWordInfo, index: Int, proxy: ScrollViewProxy) -> some View {
        let phrase = alignedPhrases[index]
        let english = word.translationEn
        let showsEnglish = !english.isEmpty && !(phrase.map { Self.isSameGloss($0, english) } ?? false)
        let isHighlighted = highlightedWordIndex == index
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let textColor = settings.bibleTextColor ?? Color.primary
        return Button {
            jumpToWordCard(index, proxy: proxy)
        } label: {
            VStack(spacing: 2) {
                Text(verbatim: phrase ?? "—")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(phrase == nil ? sectionLabelColor : textColor)
                // 빈 문자열이면 줄 높이가 0이 되므로 공백 한 칸으로 자리를 지킨다.
                Text(verbatim: english.isEmpty ? " " : english)
                    .font(.system(size: 11))
                    .foregroundStyle(textColor.opacity(0.7))
                    .opacity(showsEnglish ? 1 : 0)
                Text(verbatim: word.originalText)
                    .font(Self.originalTextFont(isHebrew: word.isHebrew, size: 17))
                    .foregroundStyle(hebrewTextColor)
            }
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(minWidth: 44)
            .background(shape.fill(linkTint.opacity(isHighlighted ? 0.2 : 0.08)))
            .overlay(shape.stroke(isHighlighted ? linkTint : Color.clear, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: wordCellAccessibilityText(phrase: phrase, english: showsEnglish ? english : "", original: word.originalText)))
        .accessibilityHint(Text("원어 카드로 이동"))
    }

    /// [2026-11-04 mergecell] 단어별 칸 묶음 — `words` 위치 범위 목록(앞부터 빈틈 없이). 바로 이웃한 단어끼리 짝(`alignedSpans`)이 같으면
    /// (같은 말, 같은 시작 위치) 한 범위로 묶고, 짝이 없는 단어는 늘 혼자 범위다. 떨어진 단어가 같은 짝을 쓰는 경우는 묶지 않는다.
    private var wordCellRuns: [Range<Int>] {
        var runs: [Range<Int>] = []
        var lower = 0
        while lower < words.count {
            var upper = lower + 1
            if let span = alignedSpans[lower] {
                while upper < words.count, alignedSpans[upper] == span {
                    upper += 1
                }
            }
            runs.append(lower ..< upper)
            lower = upper
        }
        return runs
    }

    /// [2026-11-04 mergecell] 묶인 단어별 칸: 위 = 함께 쓰는 직역 속 말(한 번), 아래 = 단어마다 영어·원어 작은 칸(누르면 그 원어 카드로).
    /// 영어 줄을 비우는 규칙은 `wordCell`과 같다(짝 말과 영어가 같으면 투명). 칸 순서·모양은 `wordCell`과 맞춘다.
    private func mergedWordCell(_ run: Range<Int>, proxy: ScrollViewProxy) -> some View {
        let phrase = alignedPhrases[run.lowerBound] ?? "—"
        let textColor = settings.bibleTextColor ?? Color.primary
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let innerShape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        let isAnyHighlighted = highlightedWordIndex.map { run.contains($0) } ?? false
        return VStack(spacing: 2) {
            Text(verbatim: phrase)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(textColor)
                .lineLimit(1)
                // 위 줄을 눌러도 묶음 첫 단어의 원어 카드로 간다(혼자 칸은 칸 전체가 버튼). VoiceOver에는 단어 버튼마다 이 말이 들어간다.
                .contentShape(Rectangle())
                .onTapGesture { jumpToWordCard(run.lowerBound, proxy: proxy) }
                .accessibilityHidden(true)
            HStack(spacing: 2) {
                ForEach(Array(run), id: \.self) { index in
                    let word = words[index]
                    let english = word.translationEn
                    let showsEnglish = !english.isEmpty && !Self.isSameGloss(phrase, english)
                    let isHighlighted = highlightedWordIndex == index
                    Button {
                        jumpToWordCard(index, proxy: proxy)
                    } label: {
                        VStack(spacing: 2) {
                            // 빈 문자열이면 줄 높이가 0이 되므로 공백 한 칸으로 자리를 지킨다.
                            Text(verbatim: english.isEmpty ? " " : english)
                                .font(.system(size: 11))
                                .foregroundStyle(textColor.opacity(0.7))
                                .opacity(showsEnglish ? 1 : 0)
                            Text(verbatim: word.originalText)
                                .font(Self.originalTextFont(isHebrew: word.isHebrew, size: 17))
                                .foregroundStyle(hebrewTextColor)
                        }
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 44)
                        .background(innerShape.fill(linkTint.opacity(isHighlighted ? 0.2 : 0)))
                        .overlay(innerShape.stroke(isHighlighted ? linkTint : Color.clear, lineWidth: 1))
                        .contentShape(innerShape)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: wordCellAccessibilityText(phrase: phrase, english: showsEnglish ? english : "", original: word.originalText)))
                    .accessibilityHint(Text("원어 카드로 이동"))
                }
            }
        }
        .padding(.horizontal, 4)
        // 안쪽 칸에는 위아래 여백을 두지 않아 줄 높이가 `wordCell`과 같다(위 6 · 말 · 2 · 영어 · 2 · 원어 · 아래 6) — 원어 줄이 칸마다 같은 높이에 온다.
        .padding(.vertical, 6)
        .frame(minWidth: 44)
        .background(shape.fill(linkTint.opacity(isAnyHighlighted ? 0.14 : 0.08)))
        .accessibilityElement(children: .contain)
    }

    private func wordCellAccessibilityText(phrase: String?, english: String, original: String) -> String {
        [phrase ?? "", english, original].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// 짝 말과 문맥 영어가 "같은 말"인지 — 대소문자, 문장부호, 보충어 괄호("[the]", "<obj.>"의 괄호), 여러 칸 공백 차이는 무시한다
    /// (예: "Word" = "Word,", "In the" = "In [the]"). 글자·숫자가 하나도 없으면 같다고 보지 않는다.
    private static func isSameGloss(_ lhs: String, _ rhs: String) -> Bool {
        let left = glossComparisonKey(lhs)
        return !left.isEmpty && left == glossComparisonKey(rhs)
    }

    private static func glossComparisonKey(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                scalars.append(scalar)
            } else if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                scalars.append(" ")
            }
        }
        return String(scalars).split(separator: " ").joined(separator: " ")
    }

    /// 원어 카드 스크롤 대상 id(`ScrollViewReader`). 원어 카드 `ForEach`는 위치로 구분하므로 같은 위치를 쓴다.
    private static func wordCardScrollID(_ index: Int) -> String {
        "originalTextInfo.wordCard.\(index)"
    }

    /// 단어별 칸 → 원어 카드로 스크롤하고 1.6초 동안 테두리로 강조한다. 그 사이 다른 칸을 누르면 앞 예약은 무시된다(`highlightGeneration`).
    private func jumpToWordCard(_ index: Int, proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo(Self.wordCardScrollID(index), anchor: .center)
        }
        highlightGeneration += 1
        let generation = highlightGeneration
        highlightedWordIndex = index
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard highlightGeneration == generation else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                highlightedWordIndex = nil
            }
        }
    }

    // MARK: - 원어 카드

    /// 원어 카드 목록 제목 줄 — "원어 단어 (N)"과 품사 정보 펼치기/접기(모든 카드 공통).
    private var wordsHeader: some View {
        HStack(spacing: 8) {
            Text("원어 단어 (\(words.count))")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(sectionLabelColor)
            Spacer(minLength: 0)
            Button {
                showsMorphology.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text("품사 정보")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(showsMorphology ? 180 : 0))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(linkTint)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(linkTint.opacity(0.35), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityValue(showsMorphology ? Text("펼침") : Text("접힘"))
        }
        .padding(.horizontal, 2)
    }

    private func wordCard(_ word: OriginalWordInfo, index: Int) -> some View {
        let isHighlighted = highlightedWordIndex == index
        let showsEditButton = AppLanguage.isKorean
        return VStack(spacing: 6) {
            // 1. 원어(글꼴·색은 예전 그대로).
            Text(word.originalText)
                .font(originalTextFont(for: word))
                .foregroundStyle(hebrewTextColor)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // 2. 음역 · Strong 번호.
            Text(verbatim: word.transliteration.isEmpty ? word.strongCode : "\(word.transliteration) · \(word.strongCode)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // 3. 품사 정보 — 제목 줄 버튼으로 펼쳤을 때만.
            if showsMorphology {
                let morphOrFallback = morphOrFallbackText(word)
                if !morphOrFallback.isEmpty {
                    Text(morphOrFallback)
                        .font(.system(size: 12))
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // 4. 사전 뜻(앱 언어). "번역 중…"/"-" 처리는 예전 그대로.
            Group {
                if let headline = headlineGloss(for: word) {
                    Text(verbatim: headline)
                } else if isTranslating && !word.glossEn.isEmpty {
                    Text("번역 중…")
                } else {
                    Text(verbatim: "-")
                }
            }
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(settings.bibleTextColor ?? .primary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)

            // 5. 이 절에서 — 짝 데이터가 지금 직역과 맞을 때만(`alignedPhrases`).
            if let phrase = alignedPhrases[index] {
                Text("이 절에서: \(phrase)")
                    .font(.system(size: 12))
                    .foregroundStyle(linkTint)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(linkTint.opacity(0.12))
                    )
            }

            // 6. 쓰인 구절 | 네이버 · biblehub.
            wordCardLinksRow(word)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.top, showsEditButton ? Self.wordCardTopPaddingWithEdit : Self.wordCardTopPadding)
        .padding(.bottom, Self.wordCardBottomPadding)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isHighlighted ? linkTint : cardBorderColor, lineWidth: isHighlighted ? 2 : 1)
        )
        .overlay(alignment: .topTrailing) {
            // 직접 수정은 한국어 뜻(`StrongGlossTranslation` 캐시)만 지원한다.
            if showsEditButton {
                Button {
                    beginEditingKorean(for: word)
                } label: {
                    // `pencil.circle`(옅은 글자색)은 장식처럼 보여 "수정" 버튼으로 읽히지 않았다(사용자 피드백 2026-10-29).
                    // 시스템 표준 편집 기호 `pencil`(SF Symbols 1.0, iOS 13+/macOS 11+)에 같은 카드의 링크 아이콘과
                    // 같은 포인트색을 써서 누를 수 있는 요소임을 드러낸다.
                    Image(systemName: "pencil")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(linkTint)
                        .frame(width: Self.wordCardIconSize, height: Self.wordCardIconSize)
                        .contentShape(WordCardHitArea(insets: Self.editButtonHitOutsets))
                }
                .buttonStyle(.plain)
                .padding(.top, Self.editButtonInset)
                .padding(.trailing, Self.editButtonInset)
                .accessibilityLabel("한글 뜻풀이 수정")
                .help("한글 뜻풀이 수정")
            }
        }
    }

    /// 원어 카드 아래 줄: [돋보기 + "N절"] | 네이버 · biblehub. 좁은 카드(약 170pt)에서 넘치면 "N절" 대신 숫자만 쓴다(`ViewThatFits`).
    private func wordCardLinksRow(_ word: OriginalWordInfo) -> some View {
        let count = verseCounts[word.strongCode]
        return ViewThatFits(in: .horizontal) {
            wordCardLinksRowContent(word, count: count, compact: false)
            wordCardLinksRowContent(word, count: count, compact: true)
        }
    }

    private func wordCardLinksRowContent(_ word: OriginalWordInfo, count: Int?, compact: Bool) -> some View {
        HStack(spacing: Self.wordCardRowSpacing) {
            occurrenceButton(word, count: count, compact: compact)

            Rectangle()
                .fill(cardBorderColor)
                .frame(width: 1, height: 18)

            // 두 링크 사이만 `wordCardLinkGap`으로 띄우고, 맞닿는 쪽 히트 영역은 그 절반까지만 넓혀 서로 겹치지 않게 한다.
            HStack(spacing: Self.wordCardLinkGap) {
                if let naverURL = naverDictionaryURL(for: word) {
                    Link(destination: naverURL) {
                        naverBadge
                            .contentShape(WordCardHitArea(insets: Self.naverLinkHitOutsets))
                    }
                    .accessibilityLabel("네이버 사전에서 찾기")
                    .help("네이버 사전에서 찾기")
                }

                // 원어 단어별 biblehub Strong 사전 링크.
                if let strongURL = bibleHubStrongURL(for: word) {
                    Link(destination: strongURL) {
                        Image(systemName: "safari")
                            .font(.system(size: 13))
                            .foregroundStyle(linkTint)
                            .frame(width: Self.wordCardIconSize, height: Self.wordCardIconSize)
                            .contentShape(WordCardHitArea(insets: Self.siteLinkHitOutsets))
                    }
                    .accessibilityLabel("biblehub.com에서 찾기")
                    .help("biblehub.com에서 찾기")
                }
            }
        }
    }

    /// 쓰인 구절 버튼. 절 수를 아직 못 셌으면(백그라운드 조회 중·실패) 돋보기만 보이고 눌러도 된다(목록은 따로 조회한다).
    private func occurrenceButton(_ word: OriginalWordInfo, count: Int?, compact: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        // 숫자만 보이는 좁은 배치에서도 접근성 이름·도움말은 "이 단어가 쓰인 구절 N절" 그대로.
        let accessibilityText: Text = count.map { Text("이 단어가 쓰인 구절 \($0)절") } ?? Text("이 단어가 쓰인 구절")
        return Button {
            occurrenceWord = word
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                if let count {
                    if compact {
                        Text(verbatim: "\(count)")
                    } else {
                        Text("쓰인 구절 \(count)절")
                    }
                }
            }
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(linkTint)
            .padding(.horizontal, 7)
            .frame(minWidth: Self.wordCardRowHeight, minHeight: Self.wordCardRowHeight)
            .overlay(shape.stroke(linkTint.opacity(0.35), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .help(accessibilityText)
    }

    // MARK: 원어 카드 아이콘 히트 영역
    // 아이콘은 16×16 그대로 레이아웃하고(카드 줄바꿈·높이 유지), 누르는 영역만 `contentShape`로 아이콘 밖까지 넓힌다
    // (Apple Developer Forums thread 831676에서 Apple 엔지니어가 권한 `contentShape(Circle().inset(by: -8))`와 같은 방식).
    // [2026-11-02 interlin1] 배치가 바뀌어 기준을 다시 잡았다.
    //  - 연필: 카드 오른쪽 위 구석(위·오른쪽 6pt 안쪽). 히트 영역 = 위·오른쪽은 카드 테두리까지(6), 왼쪽 22, 아래 8
    //    → 44×30pt(카드 위쪽 y 0~30). 연필이 보이는 카드(한국어)는 내용 위 여백을 30으로 늘려, 원어 줄이 아무리 넓어도
    //    히트 영역과 겹치지 않는다. 연필이 없는 언어는 예전 위 여백(18).
    //  - 아래 줄 링크: 줄 높이 28(쓰인 구절 버튼). 아이콘 16 위아래로 6씩 넓혀 줄 높이를 채우고, 아래는 카드 아래 여백(14) 안까지 더 넓힌다.
    //    왼쪽(네이버)은 세로선까지(줄 간격 6) — 세로선 너머 쓰인 구절 버튼과 겹치지 않는다. 오른쪽(biblehub)은 카드 안쪽 여백(14)까지.
    //    네이버↔biblehub 맞닿는 쪽은 간격(`wordCardLinkGap`)의 절반씩.
    // 결과 히트 영역: 연필 44×30pt, 링크 각 26~34×34pt — HIG 최소(iOS 28pt) 이상.
    private static let wordCardIconSize: CGFloat = 16
    private static let wordCardLinkGap: CGFloat = 8
    private static let wordCardRowSpacing: CGFloat = 6
    private static let wordCardRowHeight: CGFloat = 28
    private static let wordCardTopPadding: CGFloat = 18
    private static let wordCardBottomPadding: CGFloat = 14
    private static let editButtonInset: CGFloat = 6
    private static let wordCardTopPaddingWithEdit: CGFloat = editButtonInset + wordCardIconSize + editButtonHitOutsets.bottom
    private static let editButtonHitOutsets = EdgeInsets(top: editButtonInset, leading: 22, bottom: 8, trailing: editButtonInset)
    private static let naverLinkHitOutsets = EdgeInsets(top: 6, leading: wordCardRowSpacing, bottom: 12, trailing: wordCardLinkGap / 2)
    private static let siteLinkHitOutsets = EdgeInsets(top: 6, leading: wordCardLinkGap / 2, bottom: 12, trailing: 14)

    /// 테마 글자색이 지정돼 있으면 그 색을 쓰고(전용 서체로 한글 헤드라인과 이미 구분됨),
    /// 미지정 시엔 라이트/다크에 대응하는 남색을 쓴다.
    private var hebrewTextColor: Color {
        Self.originalTextColor(colorScheme: colorScheme)
    }

    /// [2026-11-02 interlin1] 원어 글자색 규칙을 "쓰인 구절" 화면(`OriginalWordOccurrencesView`)도 같이 쓰도록 정적 함수로 뺐다(값은 그대로).
    static func originalTextColor(colorScheme: ColorScheme) -> Color {
        if let themeColor = UserSettingsStore.shared.bibleTextColor {
            return themeColor
        }
        return colorScheme == .dark
            ? Color(red: 0.55, green: 0.7, blue: 1.0)
            : Color(red: 0.09, green: 0.25, blue: 0.78)
    }

    /// 히브리어/그리스어 전용 폰트를 `word.isHebrew`로 고른다. 히브리어 성서 조판체(Ezra SIL)는
    /// 굵은 변형이 없고 볼드체를 쓰는 관례도 없어 `.bold()`를 씌우지 않는다.
    private func originalTextFont(for word: OriginalWordInfo) -> Font {
        Self.originalTextFont(isHebrew: word.isHebrew, size: 26)
    }

    /// [2026-11-02 interlin1] 크기를 받는 공용판 — 단어별 칸(17)·쓰인 구절 화면도 같은 글꼴을 쓴다. 원어 카드는 예전 그대로 26.
    static func originalTextFont(isHebrew: Bool, size: CGFloat) -> Font {
        if isHebrew {
            BundledFontRegistrar.ensureAvailable(SpecialPurposeFonts.hebrew)
            return .custom(SpecialPurposeFonts.hebrew, size: size)
        } else {
            BundledFontRegistrar.ensureAvailable(SpecialPurposeFonts.greekBold)
            return .custom(SpecialPurposeFonts.greekBold, size: size)
        }
    }

    /// 테마 글자색의 옅은 opacity를 테두리색으로 쓴다(`DocumentsHomeView`의 카드 테두리와 같은 관례).
    /// 테마 미지정 시엔 `Color.secondary` 계열로 대체한다.
    private var cardBorderColor: Color {
        Self.cardBorderColor
    }

    /// [2026-11-02 interlin1] 쓰인 구절 화면과 공용(값은 그대로).
    static var cardBorderColor: Color {
        UserSettingsStore.shared.bibleTextColor?.opacity(0.2) ?? Color.secondary.opacity(0.2)
    }

    /// 형태소 설명이 있으면 그걸(히브리어), 없으면(그리스어 등 미지원 언어) 영어
    /// 뜻풀이를 대신 보여준다 — 카드 맨 아래 보조 설명줄이 항상 비어 보이지
    /// 않도록.
    private func morphOrFallbackText(_ word: OriginalWordInfo) -> String {
        if AppLanguage.isKorean {
            let morph = word.morphDescriptionKo
            return morph.isEmpty ? word.glossEn : morph
        }
        // [2026-10-12] 형태 설명은 한국어 전용이라 다른 언어는 영어 사전 뜻을 보여준다. 제목이 이미 영어 뜻이면
        // (영어 화면, 번역 실패) 같은 글자를 두 번 쓰지 않도록 형태 코드를 보여준다.
        if word.glossEn.isEmpty || headlineGloss(for: word) == word.glossEn {
            return word.morphCode
        }
        return word.glossEn
    }

    /// 단어 카드 제목(앱 언어 뜻). 한국어는 기존 캐시, 영어는 원문 뜻, 그 밖은 기기 번역 결과. 아직 없으면 nil.
    private func headlineGloss(for word: OriginalWordInfo) -> String? {
        if AppLanguage.isKorean { return koreanGlosses[word.strongCode] }
        guard !word.glossEn.isEmpty else { return nil }
        if AppLanguage.baseCode == "en" { return word.glossEn }
        return foreignGlosses[word.glossEn]
    }

    // biblehub은 REST API가 없어 URL에 영문 책 이름 슬러그가 필요하다(`1_kings`처럼 숫자+밑줄, 아가서만 `songs`).
    // 66권 전체를 하드코딩했다. Strong 링크는 앞자리 "H"/"G"와 0-padding을 뗀 순수 숫자만 받는다.
    private static let bibleHubSlugs: [Int: String] = [
        1: "genesis", 2: "exodus", 3: "leviticus", 4: "numbers", 5: "deuteronomy",
        6: "joshua", 7: "judges", 8: "ruth", 9: "1_samuel", 10: "2_samuel",
        11: "1_kings", 12: "2_kings", 13: "1_chronicles", 14: "2_chronicles", 15: "ezra",
        16: "nehemiah", 17: "esther", 18: "job", 19: "psalms", 20: "proverbs",
        21: "ecclesiastes", 22: "songs", 23: "isaiah", 24: "jeremiah", 25: "lamentations",
        26: "ezekiel", 27: "daniel", 28: "hosea", 29: "joel", 30: "amos",
        31: "obadiah", 32: "jonah", 33: "micah", 34: "nahum", 35: "habakkuk",
        36: "zephaniah", 37: "haggai", 38: "zechariah", 39: "malachi",
        40: "matthew", 41: "mark", 42: "luke", 43: "john", 44: "acts",
        45: "romans", 46: "1_corinthians", 47: "2_corinthians", 48: "galatians", 49: "ephesians",
        50: "philippians", 51: "colossians", 52: "1_thessalonians", 53: "2_thessalonians", 54: "1_timothy",
        55: "2_timothy", 56: "titus", 57: "philemon", 58: "hebrews", 59: "james",
        60: "1_peter", 61: "2_peter", 62: "1_john", 63: "2_john", 64: "3_john",
        65: "jude", 66: "revelation",
    ]

    private var bibleHubInterlinearURL: URL? {
        guard let slug = Self.bibleHubSlugs[bookId] else { return nil }
        return URL(string: "https://biblehub.com/interlinear/\(slug)/\(chapter)-\(verseNumber).htm")
    }

    /// strong_code(예: "H0430", "G2316")에서 언어 경로(hebrew/greek)와 앞자리
    /// 0을 뗀 순수 번호를 뽑아 biblehub Strong 사전 URL을 만든다.
    private func bibleHubStrongURL(for word: OriginalWordInfo) -> URL? {
        let code = word.strongCode
        guard let first = code.first else { return nil }
        let langPath: String
        switch first {
        case "H": langPath = "hebrew"
        case "G": langPath = "greek"
        default: return nil
        }
        let digits = code.dropFirst()
        guard let number = Int(digits) else { return nil }
        return URL(string: "https://biblehub.com/\(langPath)/\(number).htm")
    }

    // 네이버 사전 딥링크. `query`는 Strong 번호 숫자만(`bibleHubStrongURL`과 같은 규칙, 예: "H0430"→430), `range=all`.
    //   히브리어: https://dict.naver.com/hbokodict/#/search?range=all&query=<번호>
    //   헬라어:   https://dict.naver.com/grckodict/#/search?range=all&query=<번호>
    // `#/search?...`는 SPA 해시 라우팅 쿼리라 문자열 그대로 넘긴다.
    private func naverDictionaryURL(for word: OriginalWordInfo) -> URL? {
        let code = word.strongCode
        guard let first = code.first else { return nil }
        let dictPath: String
        switch first {
        case "H": dictPath = "hbokodict"
        case "G": dictPath = "grckodict"
        default: return nil
        }
        let digits = code.dropFirst()
        guard let number = Int(digits) else { return nil }
        return URL(string: "https://dict.naver.com/\(dictPath)/#/search?range=all&query=\(number)")
    }

    /// 네이버 브랜드 그린의 작은 원형 "N" 배지 — 로고 자산 없이 네이버 링크임을 표시한다.
    private var naverBadge: some View {
        Text("N")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: Self.wordCardIconSize, height: Self.wordCardIconSize)
            .background(Circle().fill(naverBrandColor))
    }

    private var naverBrandColor: Color {
        Color(red: 0x03 / 255.0, green: 0xC7 / 255.0, blue: 0x5A / 255.0)
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12)]
    }

    /// 테마 글자색의 아주 옅은 opacity로 카드를 배경에서 살짝 띄운다(`DocumentsHomeView`와 같은 관례).
    /// 미지정 시엔 `Color.secondary` 계열로 대체한다.
    private var cardBackground: Color {
        Self.cardBackground
    }

    /// [2026-11-02 interlin1] 쓰인 구절 화면과 공용(값은 그대로).
    static var cardBackground: Color {
        UserSettingsStore.shared.bibleTextColor?.opacity(0.08) ?? Color.secondary.opacity(0.08)
    }

    private func loadWords() {
        words = OriginalTextLookupService.shared.words(bookId: bookId, chapter: chapter, verse: verseNumber)
        let commentary = LiteralCommentaryService.shared
        appLiteral = commentary.appLanguageLiteral(bookId: bookId, chapter: chapter, verse: verseNumber)
        literalEnglish = OriginalTextLookupService.shared.literalEnglish(bookId: bookId, chapter: chapter, verse: verseNumber)
        alignedSpans = commentary.alignedPhraseSpans(bookId: bookId, chapter: chapter, verse: verseNumber, literal: appLiteral)
        alignedPhrases = alignedSpans.mapValues(\.text)
        // 절 수는 `loadVerseCounts()`가 이어서 채운다. 앞 절 숫자가 남아 보이지 않게 비운다.
        verseCounts = [:]
        // 절이 바뀌면 쓰인 구절 화면·카드 강조를 닫는다(번역본 열 목록만 바뀌어 다시 읽는 경우는 그대로 둔다).
        let verseKey = "\(bookId)-\(chapter)-\(verseNumber)"
        if loadedVerseKey != verseKey {
            loadedVerseKey = verseKey
            occurrenceWord = nil
            highlightedWordIndex = nil
        }

        var found: [String: String] = [:]
        for source in verseSources {
            if let text = commentary.difference(translationCode: source.code, verseText: source.text, bookId: bookId, chapter: chapter, verse: verseNumber) {
                found[source.code] = text
            }
        }
        differences = found
        // 고른 번역본을 유지하되, 이 절에 그 번역본 데이터가 없어지면 데이터가 있는 첫 열(없으면 첫 열)로 옮긴다.
        let keepSelection = selectedSourceCode.map { code in
            verseSources.contains { $0.code == code } && (found[code] != nil || found.isEmpty)
        } ?? false
        if !keepSelection {
            selectedSourceCode = verseSources.first { found[$0.code] != nil }?.code ?? verseSources.first?.code
        }

        loadCachedGlosses()
        if verseSources.isEmpty {
            loadKRVVerseText()
        }
    }

    /// [2026-11-02 interlin1] 이 절 단어들의 Strong 번호별 쓰인 절 수를 백그라운드에서 한 번에 센다(전체 스캔 1회).
    /// `.task(id:)` 안에서 불리므로 절이 바뀌면 이 작업은 취소되고, 늦게 끝난 결과는 버린다.
    private func loadVerseCounts() async {
        let codes = Array(Set(words.map(\.strongCode).filter { !$0.isEmpty })).sorted()
        guard !codes.isEmpty else { return }
        let counts = await Task.detached(priority: .userInitiated) {
            OriginalTextLookupService.verseCounts(strongCodes: codes)
        }.value
        guard !Task.isCancelled else { return }
        verseCounts = counts
    }

    /// "쓰인 구절" 본문 미리보기 번역본 — 구절 카드와 같은 번역본(`currentSource`: 칩으로 고른 것, 없으면 첫 열).
    /// 켜 둔 열 정보가 없으면 구절 카드처럼 KRV. 파일 경로를 모르면 nil(미리보기 없이 참조만).
    private var occurrencePreviewSource: OriginalWordOccurrencesView.PreviewSource? {
        if let source = currentSource {
            guard let path = source.databasePath else { return nil }
            return OriginalWordOccurrencesView.PreviewSource(filePath: path, translationCode: source.code)
        }
        guard let url = try? TranslationBootstrap.resolvedBundledDatabaseURL() else { return nil }
        return OriginalWordOccurrencesView.PreviewSource(filePath: url.path, translationCode: TranslationBootstrap.bundledTranslationCode)
    }

    private func occurrencesView(for word: OriginalWordInfo) -> some View {
        OriginalWordOccurrencesView(
            word: word,
            gloss: headlineGloss(for: word),
            knownVerseCount: verseCounts[word.strongCode],
            previewSource: occurrencePreviewSource,
            onBack: { occurrenceWord = nil },
            onSelectVerse: onOpenVerse
        )
    }

    /// 번들 KRV DB에서 이 절 텍스트를 읽는다. 시트가 열릴 때 한 번만 조회하므로 커넥션을 캐싱하지 않는다.
    /// 실패하면 빈 문자열로 두고 조용히 건너뛴다(원어 정보는 이 텍스트와 무관하게 보여야 함).
    private func loadKRVVerseText() {
        do {
            let path = try TranslationBootstrap.resolvedBundledDatabaseURL().path
            let store = try BibleReferenceStore(filePath: path)
            krvVerseText = try store.verse(bookId: bookId, chapter: chapter, verse: verseNumber)?.content ?? ""
        } catch {
            print("[OriginalTextInfoView] KRV 절 텍스트 조회 실패: \(error)")
            krvVerseText = ""
        }
    }

    /// 이 절에 등장하는 Strong 번호들의 캐시를 한 번에 읽어 온다. 캐시에 있어도
    /// `sourceEnglishGloss`가 지금 원문 데이터의 영어 뜻풀이와 다르면(원문 데이터가
    /// 나중에 갱신된 경우) 오래된 캐시로 취급해 다시 번역 대상에 포함시킨다.
    private func loadCachedGlosses() {
        guard AppLanguage.isKorean else {
            loadForeignGlosses()
            return
        }
        // `#Predicate`의 `contains`는 `Set`보다 `Array` 캡처가 안정적이라 배열로 넘긴다.
        let codes = Array(Set(words.map(\.strongCode)))
        guard !codes.isEmpty else { return }
        let descriptor = FetchDescriptor<StrongGlossTranslation>(
            predicate: #Predicate { codes.contains($0.strongCode) }
        )
        let cached = (try? modelContext.fetch(descriptor)) ?? []
        var cacheByCode: [String: StrongGlossTranslation] = [:]
        for entry in cached { cacheByCode[entry.strongCode] = entry }

        // 캐시 조회는 영어 뜻풀이 유무와 무관하게 항상 한다(사용자가 직접 입력해 둔 값을 불러오기 위해).
        // 자동번역 대상만 영어 뜻풀이가 있는 단어로 제한한다.
        var freshGlosses: [String: String] = [:]
        var missing: [(strongCode: String, glossEn: String)] = []
        var seenCodes = Set<String>()
        for word in words {
            guard !seenCodes.contains(word.strongCode) else { continue }
            seenCodes.insert(word.strongCode)
            if let entry = cacheByCode[word.strongCode], entry.sourceEnglishGloss == word.glossEn {
                if !entry.koreanGloss.isEmpty {
                    freshGlosses[word.strongCode] = entry.koreanGloss
                }
            } else if !word.glossEn.isEmpty {
                missing.append((word.strongCode, word.glossEn))
            }
        }
        koreanGlosses = freshGlosses

        if !missing.isEmpty {
            pendingTranslationRequests = missing
            requestTranslation(target: "ko")
        }
    }

    /// [2026-10-12] 한국어가 아닌 앱 언어의 단어 뜻. 실행 중 캐시에 없는 영어 뜻만 기기 번역에 넘긴다.
    /// 영어 화면은 번역하지 않는다(`headlineGloss`가 원문 뜻을 바로 쓴다).
    private func loadForeignGlosses() {
        let language = AppLanguage.code
        let glosses = Array(Set(words.map(\.glossEn).filter { !$0.isEmpty }))
        guard AppLanguage.baseCode != "en", !glosses.isEmpty else {
            foreignGlosses = [:]
            return
        }
        var found: [String: String] = [:]
        var missing: [String] = []
        for gloss in glosses {
            if let cached = Self.foreignGlossCache["\(language)|\(gloss)"] {
                found[gloss] = cached
            } else {
                missing.append(gloss)
            }
        }
        foreignGlosses = found
        if !missing.isEmpty {
            pendingForeignGlosses = missing
            requestTranslation(target: language)
        }
    }

    /// 같은 언어 설정이 이미 있으면 `invalidate()`로 `translationTask`를 다시 돌리고, 없으면 새로 만든다
    /// (같은 값을 다시 대입하면 작업이 다시 실행되지 않을 수 있다).
    private func requestTranslation(target: String) {
        let targetLanguage = Locale.Language(identifier: target)
        if translationConfiguration?.target == targetLanguage {
            translationConfiguration?.invalidate()
        } else {
            translationConfiguration = TranslationSession.Configuration(
                source: Locale.Language(identifier: "en"),
                target: targetLanguage
            )
        }
    }

    /// `loadCachedGlosses`가 채워 두는, 이번에 실제로 번역해야 할 (Strong번호, 영어)
    /// 목록 — `translationTask`의 클로저는 `translationConfiguration`이 바뀔 때만
    /// 다시 불리므로, 매개변수로 직접 못 넘기고 상태로 들고 있다가 여기서 읽는다.
    @State private var pendingTranslationRequests: [(strongCode: String, glossEn: String)] = []
    /// 한국어가 아닌 앱 언어에서 이번에 번역할 영어 뜻 목록.
    @State private var pendingForeignGlosses: [String] = []

    private func translateMissingGlosses(session: TranslationSession) async {
        guard AppLanguage.isKorean else {
            await translateForeignGlosses(session: session)
            return
        }
        let requests = pendingTranslationRequests
        guard !requests.isEmpty else { return }
        isTranslating = true
        defer { isTranslating = false }

        do {
            let sessionRequests = requests.map {
                TranslationSession.Request(sourceText: $0.glossEn, clientIdentifier: $0.strongCode)
            }
            let responses = try await session.translations(from: sessionRequests)
            for response in responses {
                guard let strongCode = response.clientIdentifier,
                      let sourceGloss = requests.first(where: { $0.strongCode == strongCode })?.glossEn else { continue }
                let korean = response.targetText
                koreanGlosses[strongCode] = korean
                upsertCache(strongCode: strongCode, sourceEnglishGloss: sourceGloss, koreanGloss: korean)
            }
            try? modelContext.save()
        } catch {
            print("[OriginalTextInfoView] 번역 실패: \(error)")
        }
        pendingTranslationRequests = []
    }

    /// 한국어가 아닌 앱 언어의 단어 뜻 번역. 실패하면(기기 번역이 그 언어를 지원하지 않거나 언어 자료 내려받기를
    /// 거절한 경우 등) 영어 뜻을 그대로 보여준다. 결과는 메모리에만 두고 저장하지 않는다.
    private func translateForeignGlosses(session: TranslationSession) async {
        let requests = pendingForeignGlosses
        guard !requests.isEmpty else { return }
        isTranslating = true
        defer { isTranslating = false }
        let language = AppLanguage.code

        do {
            let sessionRequests = requests.enumerated().map { index, gloss in
                TranslationSession.Request(sourceText: gloss, clientIdentifier: String(index))
            }
            let responses = try await session.translations(from: sessionRequests)
            for response in responses {
                guard let identifier = response.clientIdentifier, let index = Int(identifier),
                      requests.indices.contains(index) else { continue }
                let gloss = requests[index]
                foreignGlosses[gloss] = response.targetText
                Self.foreignGlossCache["\(language)|\(gloss)"] = response.targetText
            }
        } catch {
            print("[OriginalTextInfoView] 번역 실패(\(language)): \(error)")
        }
        for gloss in requests where foreignGlosses[gloss] == nil {
            foreignGlosses[gloss] = gloss
        }
        pendingForeignGlosses = []
    }

    /// 편집창 초기값을 현재 값(없으면 빈 문자열)으로 채운다.
    private func beginEditingKorean(for word: OriginalWordInfo) {
        editingText = koreanGlosses[word.strongCode] ?? ""
        editingWord = word
    }

    /// 사용자가 알림창에서 "저장"을 누르면 호출된다. 빈 문자열 저장은 막는다 —
    /// 실수로 지우고 저장하면 자동번역 결과였는지 사용자가 일부러 비운 것인지
    /// 구분할 수 없어 오히려 혼란스럽다(취소하고 싶으면 "취소" 버튼을 쓰면 된다).
    private func commitKoreanEdit() {
        guard let word = editingWord else { return }
        let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { editingWord = nil }
        guard !trimmed.isEmpty else { return }
        koreanGlosses[word.strongCode] = trimmed
        upsertCache(strongCode: word.strongCode, sourceEnglishGloss: word.glossEn, koreanGloss: trimmed)
        try? modelContext.save()
    }

    private func upsertCache(strongCode: String, sourceEnglishGloss: String, koreanGloss: String) {
        let descriptor = FetchDescriptor<StrongGlossTranslation>(
            predicate: #Predicate { $0.strongCode == strongCode }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.sourceEnglishGloss = sourceEnglishGloss
            existing.koreanGloss = koreanGloss
            existing.updatedAt = .now
        } else {
            modelContext.insert(StrongGlossTranslation(
                strongCode: strongCode, sourceEnglishGloss: sourceEnglishGloss, koreanGloss: koreanGloss
            ))
        }
    }
}

/// 뷰 경계에서 변마다 지정한 만큼 바깥으로 넓힌 사각형 — `contentShape`로 히트 영역만 넓히는 데 쓴다(레이아웃 크기는 그대로).
/// `Rectangle().inset(by: -n)`은 네 변을 똑같이만 넓힐 수 있어, 이웃 버튼 쪽만 덜 넓히려고 변별 값을 받는다.
private struct WordCardHitArea: Shape {
    let insets: EdgeInsets

    func path(in rect: CGRect) -> Path {
        Path(CGRect(
            x: rect.minX - insets.leading,
            y: rect.minY - insets.top,
            width: rect.width + insets.leading + insets.trailing,
            height: rect.height + insets.top + insets.bottom
        ))
    }
}
