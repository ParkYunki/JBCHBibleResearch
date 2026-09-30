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

import SwiftUI
import Translation
import SwiftData
import BibleResearchModels

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

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    /// 원어 색을 라이트/다크에 맞춰 고르기 위해 필요하다.
    @Environment(\.colorScheme) private var colorScheme
    @State private var words: [OriginalWordInfo] = []
    /// 직역/번역 차이 카드 데이터(`LiteralTranslation` 조회 결과). 데이터가 없는 절이면 nil이고 카드를 숨긴다.
    @State private var literalInfo: LiteralTranslationInfo?
    /// 번들 기본 번역본(KRV 개역한글)에서 읽은 절 본문. 원문 정보는 절에만 종속되므로
    /// 화면에 켜 둔 번역본과 무관하게 항상 KRV로 고정한다.
    @State private var krvVerseText: String = ""
    @State private var koreanGlosses: [String: String] = [:]
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var isTranslating = false
    /// 편집 중인 단어(연필 아이콘을 누른 단어). nil이면 편집 알림창이 뜨지 않는다.
    @State private var editingWord: OriginalWordInfo?
    @State private var editingText: String = ""

    private var displayTitle: String {
        let name = BooksProvider.shared.book(id: bookId)?.nameKo ?? "책 \(bookId)"
        return "\(name) \(chapter):\(verseNumber) 원문 정보"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // biblehub 인터리니어 링크(시스템 기본 브라우저로 열림). 슬러그를 못 찾거나 URL이 안 만들어지면
                    // 깨진 링크를 보여주는 대신 숨긴다.
                    if let interlinearURL = bibleHubInterlinearURL {
                        Link(destination: interlinearURL) {
                            Label("영문-원어성경", systemImage: "safari")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(.blue)
                    }
                    // 원어 데이터가 없는 절에서도 KRV 본문은 보이도록 `words.isEmpty` 분기 밖에 둔다.
                    if !krvVerseText.isEmpty {
                        // 메인 본문 목록(TranslationColumnView)과 같은 폰트/줄간격/글자색을 써서 "모양" 설정을 따른다.
                        Text(krvVerseText)
                            .font(UserSettingsStore.shared.bibleBodyFont)
                            .foregroundStyle(UserSettingsStore.shared.bibleTextColor ?? Color.primary)
                            .lineSpacing(UserSettingsStore.shared.bibleLineSpacing)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(cardBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(cardBorderColor, lineWidth: 1)
                            )
                    }
                    // 직역과 번역 차이 카드 — 성경 구절 아래, 원어 카드 위. 다른 카드들과 같은 스타일로 통일한다.
                    if let literalInfo {
                        literalTranslationCard(literalInfo)
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
                            ForEach(words) { word in
                                wordCard(word)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(settings.bibleBackgroundColor ?? Color.clear)
            .navigationTitle(displayTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                // `.primaryAction`/`.topBarTrailing`은 이 자리에 그려지지 않아 `.confirmationAction`을 쓴다.
                // 아이콘은 앱 전체에서 "메모"를 가리키는 `text.bubble`로 통일해, 누르면 메모하기로 간다는 걸 알 수 있게 한다.
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: onSwitchToMemo) {
                        Label("메모하기", systemImage: "text.bubble")
                    }
                    .help("메모하기로 전환")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 420)
        #endif
        .modifier(VerseNavArrowsModifier(
            canGoPrevious: canGoToPreviousVerse,
            canGoNext: canGoToNextVerse,
            onPrevious: onNavigateToPreviousVerse,
            onNext: onNavigateToNextVerse
        ))
        // `.task(id:)`로 절/장/권이 바뀔 때마다 다시 로드한다 — 시트가 열린 채 이전/다음 절로 이동해도
        // 원어 정보가 첫 절 데이터로 멈춰 있지 않도록 하기 위해서다.
        .task(id: "\(bookId)-\(chapter)-\(verseNumber)") { loadWords() }
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

    /// 직역과 "번역과의 차이" 설명 카드. 스타일은 `cardBackground`/`cardBorderColor`를 따른다.
    private func literalTranslationCard(_ info: LiteralTranslationInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("직역 (원어 그대로)", systemImage: "text.alignleft")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(settings.bibleTextColor?.opacity(0.75) ?? Color.secondary)

            Text(info.literalTranslation)
                .font(UserSettingsStore.shared.bibleBodyFont.italic())
                .foregroundStyle(settings.bibleTextColor ?? Color.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)

            if let difference = info.difference, !difference.isEmpty {
                Rectangle()
                    .fill(cardBorderColor)
                    .frame(height: 1)

                Label("번역과의 차이", systemImage: "arrow.left.arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)

                Text(difference)
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
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(cardBorderColor, lineWidth: 1)
        )
    }

    private func wordCard(_ word: OriginalWordInfo) -> some View {
        VStack(spacing: 8) {
            // 편집용 연필 아이콘은 한글 뜻 헤드라인 오른쪽에 둔다.
            HStack(spacing: 6) {
                Group {
                    if let korean = koreanGlosses[word.strongCode] {
                        Text(korean)
                    } else if isTranslating && !word.glossEn.isEmpty {
                        Text("번역 중…")
                    } else {
                        Text("-")
                    }
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(settings.bibleTextColor ?? .primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

                Button {
                    beginEditingKorean(for: word)
                } label: {
                    Image(systemName: "pencil.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                }
                .buttonStyle(.plain)
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
                            .foregroundStyle(.blue)
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
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(cardBorderColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
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
        let morph = word.morphDescriptionKo
        return morph.isEmpty ? word.glossEn : morph
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
        literalInfo = OriginalTextLookupService.shared.literalTranslation(bookId: bookId, chapter: chapter, verse: verseNumber)
        loadCachedGlosses()
        loadKRVVerseText()
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
            translationConfiguration = TranslationSession.Configuration(
                source: Locale.Language(identifier: "en"),
                target: Locale.Language(identifier: "ko")
            )
        }
    }

    /// `loadCachedGlosses`가 채워 두는, 이번에 실제로 번역해야 할 (Strong번호, 영어)
    /// 목록 — `translationTask`의 클로저는 `translationConfiguration`이 바뀔 때만
    /// 다시 불리므로, 매개변수로 직접 못 넘기고 상태로 들고 있다가 여기서 읽는다.
    @State private var pendingTranslationRequests: [(strongCode: String, glossEn: String)] = []

    private func translateMissingGlosses(session: TranslationSession) async {
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
