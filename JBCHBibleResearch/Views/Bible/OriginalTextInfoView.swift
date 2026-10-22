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

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    /// 원어 색을 라이트/다크에 맞춰 고르기 위해 필요하다.
    @Environment(\.colorScheme) private var colorScheme
    @State private var words: [OriginalWordInfo] = []
    /// 앱 언어 직역(`LiteralCommentaryService`). 없으면 직역 문장 줄을 숨긴다.
    @State private var appLiteral: String?
    /// 공통 영어 직역(LSV). 없으면 접기 줄을 숨긴다.
    @State private var literalEnglish: LiteralEnglishInfo?
    /// LSV 펼침 상태 — 절을 옮길 때마다 접힌 상태로 돌아간다(사용자 결정: 모든 언어에서 접어서 표시).
    @State private var isLiteralEnglishExpanded = false
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
    private var mainScroll: some View {
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
                    literalCard
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
                    // 화면 너비에 맞춰 여러 열로 자동 배치한다.
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        // 원본 DB에 같은 절·같은 word_order가 겹치는 행(17쌍)이 있어 `word.id` 대신 위치로 구분한다.
                        ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                            wordCard(word)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(settings.bibleBackgroundColor ?? Color.clear)
    }

    /// 시트 껍데기. macOS는 시스템 도구 모음이 제목 줄·버튼 줄을 시스템 회색으로 그려 본문의 테마 배경과 색이 끊겼으므로,
    /// 내비게이션 스택을 쓰지 않고 시트 안에 제목 줄(`VerseSheetHeader`)과 하단 버튼 줄(`VerseSheetFooter`)을 직접 그린다
    /// (확대보기 `VerseZoomView`와 같은 바탕·선·그림자 — 2026-10-02 목업 결정). iOS/iPadOS는 기존 내비게이션 바 툴바를 그대로 쓴다.
    @ViewBuilder
    private var sheetRoot: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            VerseSheetHeader(title: displayTitle)
            mainScroll
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
                }
                mainScroll
            }
            .background(UserSettingsStore.shared.bibleBackgroundColor ?? Color.clear)
            .toolbar(.hidden, for: .navigationBar)
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
        .task(id: "\(bookId)-\(chapter)-\(verseNumber)|\(verseSources.map(\.code).joined(separator: ","))") { loadWords() }
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

    /// 원어 어순 줄 — STEPBible 문맥 번역을 원문 순서대로(빈 값 제외).
    private var wordOrderGlosses: [String] {
        words.map(\.translationEn).filter { !$0.isEmpty }
    }

    private var currentDifference: String? {
        guard let code = currentSource?.code else { return nil }
        return differences[code]
    }

    private var hasLiteralCardContent: Bool {
        appLiteral != nil || !wordOrderGlosses.isEmpty || literalEnglish != nil || currentDifference != nil
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

    private var literalCard: some View {
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

            let glosses = wordOrderGlosses
            if !glosses.isEmpty {
                // 원어 어순(사용자 결정: 직역 카드 안). STEPBible 문맥 번역이라 영어 그대로 보여준다.
                Text("원어 어순")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(sectionLabelColor)
                    .frame(maxWidth: .infinity, alignment: .center)
                FlowLayoutHStack(spacing: 5) {
                    ForEach(Array(glosses.enumerated()), id: \.offset) { _, gloss in
                        Text(verbatim: gloss)
                            .font(.system(size: 12))
                            .foregroundStyle(settings.bibleTextColor ?? Color.primary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(linkTint.opacity(0.14))
                            )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }

            // 영어 화면은 직역이 곧 LSV(`Literal_en`의 basis = LSV)라 같은 문장을 접기 줄로 또 보여주지 않는다.
            if let literalEnglish, literalEnglish.text != appLiteral {
                Rectangle()
                    .fill(cardBorderColor)
                    .frame(height: 1)
                DisclosureGroup(isExpanded: $isLiteralEnglishExpanded) {
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
                    .padding(.top, 6)
                } label: {
                    Text("영어 직역 (LSV)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(sectionLabelColor)
                }
                .tint(sectionLabelColor)
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

    private func wordCard(_ word: OriginalWordInfo) -> some View {
        VStack(spacing: 8) {
            // 편집용 연필 아이콘은 한글 뜻 헤드라인 오른쪽에 둔다.
            HStack(spacing: 6) {
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

                // 직접 수정은 한국어 뜻(`StrongGlossTranslation` 캐시)만 지원한다.
                if AppLanguage.isKorean {
                    Button {
                        beginEditingKorean(for: word)
                    } label: {
                        Image(systemName: "pencil.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 5) {
                Text(word.originalText)
                    .font(originalTextFont(for: word))
                    .foregroundStyle(hebrewTextColor)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                // 원어 바로 다음, biblehub 링크 앞에 네이버 사전 링크를 둔다(`naverDictionaryURL`/`naverBadge`).
                if let naverURL = naverDictionaryURL(for: word) {
                    Link(destination: naverURL) {
                        naverBadge
                    }
                    .help("네이버 사전에서 찾기")
                }

                // 원어 단어별 biblehub Strong 사전 링크.
                if let strongURL = bibleHubStrongURL(for: word) {
                    Link(destination: strongURL) {
                        Image(systemName: "safari")
                            .font(.system(size: 13))
                            .foregroundStyle(linkTint)
                    }
                    .help("biblehub.com에서 찾기")
                }
            }
            .padding(.top, 2)

            if !word.transliteration.isEmpty {
                Text("[\(word.transliteration)]")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
            }

            // [2026-10-12] 이 절 문맥의 영어 번역(STEPBible). 사전형 뜻과 다르게 문맥에 맞춘 형태다.
            if !word.translationEn.isEmpty {
                HStack(spacing: 4) {
                    Text("문맥")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.5) ?? Color.secondary)
                    Text(verbatim: word.translationEn)
                        .font(.system(size: 12))
                        .foregroundStyle(settings.bibleTextColor ?? Color.primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(linkTint.opacity(0.14))
                )
            }

            let morphOrFallback = morphOrFallbackText(word)
            if !morphOrFallback.isEmpty {
                Text(morphOrFallback)
                    .font(.system(size: 12))
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }

            Text(word.strongCode)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(settings.bibleTextColor?.opacity(0.4) ?? Color.secondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(cardBorderColor, lineWidth: 1)
        )
    }

    /// 테마 글자색이 지정돼 있으면 그 색을 쓰고(전용 서체로 한글 헤드라인과 이미 구분됨),
    /// 미지정 시엔 라이트/다크에 대응하는 남색을 쓴다.
    private var hebrewTextColor: Color {
        if let themeColor = settings.bibleTextColor {
            return themeColor
        }
        return colorScheme == .dark
            ? Color(red: 0.55, green: 0.7, blue: 1.0)
            : Color(red: 0.09, green: 0.25, blue: 0.78)
    }

    /// 히브리어/그리스어 전용 폰트를 `word.isHebrew`로 고른다. 히브리어 성서 조판체(Ezra SIL)는
    /// 굵은 변형이 없고 볼드체를 쓰는 관례도 없어 `.bold()`를 씌우지 않는다.
    private func originalTextFont(for word: OriginalWordInfo) -> Font {
        if word.isHebrew {
            BundledFontRegistrar.ensureAvailable(SpecialPurposeFonts.hebrew)
            return .custom(SpecialPurposeFonts.hebrew, size: 26)
        } else {
            BundledFontRegistrar.ensureAvailable(SpecialPurposeFonts.greekBold)
            return .custom(SpecialPurposeFonts.greekBold, size: 26)
        }
    }

    /// 테마 글자색의 옅은 opacity를 테두리색으로 쓴다(`DocumentsHomeView`의 카드 테두리와 같은 관례).
    /// 테마 미지정 시엔 `Color.secondary` 계열로 대체한다.
    private var cardBorderColor: Color {
        settings.bibleTextColor?.opacity(0.2) ?? Color.secondary.opacity(0.2)
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
            .frame(width: 16, height: 16)
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
        settings.bibleTextColor?.opacity(0.08) ?? Color.secondary.opacity(0.08)
    }

    private func loadWords() {
        words = OriginalTextLookupService.shared.words(bookId: bookId, chapter: chapter, verse: verseNumber)
        let commentary = LiteralCommentaryService.shared
        appLiteral = commentary.appLanguageLiteral(bookId: bookId, chapter: chapter, verse: verseNumber)
        literalEnglish = OriginalTextLookupService.shared.literalEnglish(bookId: bookId, chapter: chapter, verse: verseNumber)
        isLiteralEnglishExpanded = false

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
