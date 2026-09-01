//
//  OriginalTextInfoView.swift
//  JBCHBibleResearch
//
//  [2026-08-09 신설] "원문 정보" — 사용자 요청: "각 절을 선택했을 때 확대보기 버튼
//  옆에 '원문 정보'라는 버튼이 있어 히브리어 그리스어 원문에 대한 정보를 넣고자 함."
//  사용자가 고른 사양(AskUserQuestion) 그대로 구현한다:
//    - 데이터셋: STEPBible-Data (CC BY 4.0)
//    - 표시 정보: Strong번호 + 원어 + 음역 + 영어 + 한글(4가지 모두)
//    - 화면 구조: 절 전체를 원어 단어 목록으로(드래그 선택 아님) — 원문은 번역본과
//      무관하게 book/chapter/verse에만 종속되므로, 구절 확대보기와 달리 "번역본
//      선택"이나 구간 드래그가 필요 없다.
//
//  [2026-08-13 수정] 사용자 요청(첨부 카드 목업) — "완벽하지는 않더라도 되도록
//  첨부파일 모양처럼 표현하고 싶음." 위 4항목 스펙에 한글 형태소(문법) 설명을
//  더해 카드 그리드(`LazyVGrid`)로 다시 짰다. 형태소 설명은
//  `HebrewMorphologyDescriber`(BibleResearchModels, OSHB 코드 체계 기반)가
//  히브리어만 지원 — 그리스어 단어는 이 자리에 기존처럼 영어 뜻풀이를 보여준다.
//
//  ⚠️ [한글 뜻풀이 출처] 오픈 라이선스 한글 Strong 사전이 존재하지 않아(리서치 결과,
//  바이블렉스/옥스퍼드 원어성경대전 등은 전부 상업 라이선스) STEPBible의 영어
//  뜻풀이를 Apple `Translation` 프레임워크로 그때그때 번역한다. 사용자 결정 —
//  "최초 번역된 내용은 DB에 저장될 수 있게 할 것. 그 이후부터는 DB내용을 조회할것."
//  `StrongGlossTranslation`(SwiftData)에 Strong 번호 단위로 캐싱해, 두 번째부터는
//  재번역 없이 캐시를 읽는다. 번역 품질은 기계번역 수준이며, 신학적으로 확립된
//  용어(예: 전문 성경사전의 표준 역어)와 다를 수 있다는 한계가 있다.
//

import SwiftUI
import Translation
import SwiftData
import BibleResearchModels
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct OriginalTextInfoView: View {
    let bookId: Int
    let chapter: Int
    let verseNumber: Int
    /// [2026-08-28 신설] 사용자 요청 — "[메모하기]-[원문정보] 각 레이어창 마다
    /// 쉽게 오갈 수 있도록 화살표라든지 기능을 추가할 것." 이 화면의 툴바에
    /// "메모하기로 전환" 버튼을 추가하기 위한 콜백 — 호출부(BibleReadingView)가
    /// 이 시트를 닫고 메모하기(구 확대보기) 시트를 여는 순서를 책임진다(같은
    /// 화면이 시트 두 개를 동시에 띄울 수 없는 기존 제약, `VerseZoomView.
    /// onSwitchToOriginalTextInfo`와 같은 이유). 이 구조체는 커스텀 init이
    /// 없어 컴파일러가 만들어 주는 memberwise init에 이 값도 자동으로 포함된다.
    let onSwitchToMemo: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    /// [2026-08-19 추가] 사용자 보고 — "히브리어/헬라어가 파란색인데, 야간에는
    /// 배경이 검은색이어서 눈에 잘 안보임." 아래 `hebrewTextColor`가 라이트
    /// 모드 스크린샷에 맞춘 진한 남색 고정값이었다 — 다크모드에서 검은 배경과
    /// 대비가 부족했다. 라이트/다크를 구분해 색을 고르기 위해 필요하다.
    @Environment(\.colorScheme) private var colorScheme
    @State private var words: [OriginalWordInfo] = []
    /// [2026-08-13 추가] 사용자 요청 — "타이틀 아래 원문 정보 가장 상단에 해당
    /// 구절(개역한글 KRV) 텍스트를 보여줄것." 번들 기본 번역본(KRV=개역한글,
    /// `TranslationBootstrap`/`Resources/BibleDB.sqlite`)에서 직접 읽는다 —
    /// 사용자가 다른 번역본을 화면에 켜 두었어도 이 시트는 항상 KRV 고정(원문
    /// 정보는 절 자체에 종속되지 편집 화면에서 고른 번역본과는 무관하므로).
    @State private var krvVerseText: String = ""
    @State private var koreanGlosses: [String: String] = [:]
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var isTranslating = false
    /// [2026-08-09 추가] 사용자 요청 — "원문정보의 한글 번역을 수정할 수 있게 할
    /// 것." 편집 중인 단어(연필 아이콘을 누른 단어) — nil이면 편집 알림창이 안 뜬다.
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
                    // [2026-08-13 추가] 사용자 요청 — "원문 정보 상단에 [영문-원어성경]
                    // 이라는 텍스트로 아이콘과 함께 biblehub.com 인터리니어 링크를
                    // 넣어 웹브라우저로 열리게 할것." `Link`는 시스템 기본 브라우저로
                    // 연다(별도 WebView 없이). 이 절에 대응하는 biblehub 슬러그를
                    // 못 찾거나(성경 66권 밖 등, 사실상 없음) URL 자체가 안 만들어지면
                    // 조용히 숨긴다 — 깨진 링크를 보여주는 것보다 낫다.
                    if let interlinearURL = bibleHubInterlinearURL {
                        Link(destination: interlinearURL) {
                            Label("영문-원어성경", systemImage: "safari")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(.blue)
                    }
                    // [2026-08-13 추가] 사용자 요청 — "타이틀 아래 원문 정보 가장
                    // 상단에 해당 구절(개역한글 KRV) 텍스트를 보여줄것." 원어 단어
                    // 데이터가 없는 절(아직 못 채운 ~128개 장 중 하나)이어도 이
                    // 텍스트만은 보이게, `words.isEmpty` 분기 밖으로 뺐다.
                    if !krvVerseText.isEmpty {
                        // [2026-08-13 수정] 사용자 요청 — "상단 말씀 구절도 메인창
                        // 성경 조회 내용처럼 글꼴을 동일하게 하고, 가운데 정렬로
                        // 할것." 메인 본문 목록(TranslationColumnView)이 절 본문에
                        // 쓰는 폰트/줄간격/글자색을 그대로 가져온다 — 사용자가
                        // "모양" 설정에서 폰트를 바꾸면 여기도 같이 바뀐다.
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
                    if words.isEmpty {
                        ContentUnavailableView(
                            "원문 정보 없음",
                            systemImage: "character.book.closed",
                            description: Text("이 절에 대한 원문 데이터를 찾을 수 없습니다.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                    } else {
                        // [2026-08-13 수정] 사용자 요청 — "완벽하지는 않더라도 되도록
                        // 첨부파일 모양처럼 표현하고 싶음"(카드 그리드 목업: 한글 뜻
                        // 헤드라인 → 원어(파란색, 굵게) → 음역([...]) → 형태소 문법
                        // 설명 순서). 세로 한 줄 카드였던 걸 `LazyVGrid`로 바꿔
                        // 화면 너비에 맞게 여러 열로 자동 배치한다.
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(words) { word in
                                wordCard(word)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle(displayTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                // [2026-08-29 재수정] 사용자 요청 — "메모하기, 원문 정보 각각
                // 하단에 닫기 오른쪽 버튼 옆에 두도록." `VerseZoomView.swift`의
                // 펜/눈동자 토글이 실제로 이 자리(이 시트의 아래쪽 버튼줄)에
                // 정상적으로 그려지는 것을 스크린샷으로 확인했으므로, 안
                // 그려지던 `.primaryAction`/`.topBarTrailing` 대신 같은
                // `.confirmationAction`을 쓴다.
                // [2026-08-29 3차 수정] 사용자 요청 — "좌우 화살표 대신 메모하기
                // 아이콘과, 원어 정보 아이콘으로 각각 대치할 것." 화살표 대신,
                // "메모하기"가 성경 조회 하단 액션바에서 이미 쓰는 아이콘
                // (`BibleReadingView.swift`의 `Label("메모하기", systemImage:
                // "arrow.up.left.and.arrow.down.right")`)과 똑같은 걸 써서 —
                // 이 버튼을 누르면 "메모하기"로 간다는 것을 아이콘만 보고도
                // 알 수 있게 했다.
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: onSwitchToMemo) {
                        Label("메모하기", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .help("메모하기로 전환")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 420)
        #endif
        .onAppear { loadWords() }
        .translationTask(translationConfiguration) { session in
            await translateMissingGlosses(session: session)
        }
        // [2026-08-09 추가] 사용자 요청 — "원문정보의 한글 번역을 수정할 수 있게
        // 할 것." Strong 번호 단위 캐시(`StrongGlossTranslation`)를 그대로
        // 고쳐 쓴다 — 그래서 이 한 번의 수정이 같은 Strong 번호가 나오는 성경 내
        // 다른 모든 절에도 똑같이 적용된다(캐시 설계 자체가 "절 단위"가 아니라
        // "Strong 번호 단위"이기 때문 — StrongGlossTranslation.swift 상단 주석 참고).
        // 이 점을 알림창 메시지에 명시해 사용자가 오해하지 않게 했다.
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

    // [2026-08-13 재작업] 사용자가 준 실제 스크린샷(카드: "허리를" 헤드라인 →
    // "מָתְנַיִם" 파란 굵은 원어 → "[mot.Na.yim]" 음역 → "명사 보통명사 남성
    // 쌍수 절대형" 회색 형태소 설명, 전부 가운데 정렬 + 옅은 회색 라운드 테두리)에
    // "테두리 색상, 원문 색상, 품사 글꼴 색상, 정렬까지 동일하게" 맞춰 달라는
    // 요청 — 이전 라운드의 좌측 정렬 + 파란 굵은 테두리 버전을 갈아엎는다.
    // 스크린샷에는 Strong번호/연필 아이콘이 안 보이지만, 편집 기능(연필)과 기존
    // 4항목 스펙(Strong번호 포함)은 유지해야 해서 둘 다 카드 맨 아래에 아주 작게
    // 눈에 덜 띄게 남겨 뒀다 — 완전히 지우면 "한글 뜻풀이 수정" 기능이 없어진다.
    private func wordCard(_ word: OriginalWordInfo) -> some View {
        VStack(spacing: 8) {
            // [2026-08-13 재수정] 사용자 요청 — "한글 뜻풀이 수정용 연필
            // 아이콘은 한글 뜻 단어 오른쪽 옆에 배치하고, 조금더 진하고,
            // 조금더 크게 할것." 카드 우상단 구석에 옅게 떠 있던 걸 한글
            // 헤드라인과 같은 줄로 옮기고(HStack), 색은 `.quaternary`→
            // `.secondary`로 진하게, 크기는 12→14로 키웠다(18로 한 번 키웠다가
            // 사용자 요청으로 14·`pencil.circle`(테두리만, 채움 없음)로 재조정).
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
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

                Button {
                    beginEditingKorean(for: word)
                } label: {
                    Image(systemName: "pencil.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 5) {
                Text(word.originalText)
                    .font(originalTextFont(for: word))
                    .foregroundStyle(hebrewTextColor)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                // [2026-08-15 추가] 사용자 요청 — "원문 옆에 네이버 링크 추가
                // (원어-네이버링크-영문링크), 네이버 링크임을 표시할 수 있도록."
                // 순서를 정확히 지키기 위해 원어 `Text` 바로 다음, 기존 biblehub
                // ("영문") 링크 앞에 넣는다 — `naverDictionaryURL`/`naverBadge`
                // 상단 주석 참고.
                if let naverURL = naverDictionaryURL(for: word) {
                    Link(destination: naverURL) {
                        naverBadge
                    }
                    .help("네이버 사전에서 찾기")
                }

                // [2026-08-13 추가] 사용자 요청 — "각 원어 단어 옆에 아이콘을
                // 넣고 biblehub.com/hebrew|greek/{Strong숫자}.htm 주소를 넣고
                // 웹브라우저로 열리게 할것."
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
                    .foregroundStyle(.secondary)
            }

            let morphOrFallback = morphOrFallbackText(word)
            if !morphOrFallback.isEmpty {
                Text(morphOrFallback)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }

            Text(word.strongCode)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardBackground)
        )
        // [2026-08-13 수정] 사용자 요청 — 스크린샷의 옅은 회색 라운드 테두리와
        // 동일하게(이전엔 진한 파란 테두리였음).
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(cardBorderColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }

    /// 스크린샷의 원어 텍스트 파란색(iOS 기본 System Blue보다 살짝 진하고
    /// 채도 높은 남색 계열)에 맞춘 커스텀 색. [2026-08-19 수정] 사용자 보고 —
    /// "야간에는 배경이 검은색이어서 눈에 잘 안보임." 이 진한 남색은 흰 배경
    /// 기준으로 고른 값이라 다크모드 검은 배경에서는 대비가 부족했다 — 다크
    /// 모드에서는 더 밝고 채도 낮은 블루를 대신 쓴다.
    private var hebrewTextColor: Color {
        colorScheme == .dark
            ? Color(red: 0.55, green: 0.7, blue: 1.0)
            : Color(red: 0.09, green: 0.25, blue: 0.78)
    }

    /// [2026-08-19 신설] 사용자 요청 — "히브리어 기본폰트(SILEOT)는 히브리어
    /// 표기에, 헬라어 기본폰트(Gentium)는 그리스어 표기에 적용." 언어는
    /// `word.isHebrew`(strongCode 접두 "H"/"G")로 가른다. 기존에 이 Text가
    /// 항상 `.bold`였으므로(위 `HStack` — 이전엔 `.system(size: 26, weight:
    /// .bold)`), 그리스어는 굵기가 있는 `Gentium-Bold`를 그대로 쓴다. 히브리어
    /// 성서 조판체(Ezra SIL)는 애초에 굵은 변형이 따로 없어(SIL이 배포하는
    /// 유일한 굵기) 인위적으로 `.bold()`를 씌우지 않는다 — 성서 히브리어
    /// 조판에서 볼드체를 쓰는 관례 자체가 없다.
    private func originalTextFont(for word: OriginalWordInfo) -> Font {
        if word.isHebrew {
            return .custom(SpecialPurposeFonts.hebrew, size: 26)
        } else {
            return .custom(SpecialPurposeFonts.greekBold, size: 26)
        }
    }

    private var cardBorderColor: Color {
        #if os(iOS)
        Color(uiColor: .separator)
        #else
        Color(nsColor: .separatorColor)
        #endif
    }

    /// 형태소 설명이 있으면 그걸(히브리어), 없으면(그리스어 등 미지원 언어) 영어
    /// 뜻풀이를 대신 보여준다 — 카드 맨 아래 보조 설명줄이 항상 비어 보이지
    /// 않도록.
    private func morphOrFallbackText(_ word: OriginalWordInfo) -> String {
        let morph = word.morphDescriptionKo
        return morph.isEmpty ? word.glossEn : morph
    }

    // [2026-08-13 추가] biblehub.com 딥링크 2건 — 사용자 요청:
    // "① 원문 정보 상단에 [영문-원어성경] 텍스트로 인터리니어 링크
    //    (biblehub.com/interlinear/{영문책이름}/{장}-{절}.htm)
    //  ② 각 원어 단어 옆에 Strong 사전 링크
    //    (biblehub.com/hebrew|greek/{Strong숫자}.htm)"
    // biblehub은 book/chapter/verse REST API가 없어 URL에 박히는 영문 책
    // 이름(슬러그)이 필요 — genesis/1-1.htm, 1_kings/1-1.htm(숫자+밑줄) 형태를
    // 직접 https://biblehub.com/interlinear/genesis/1-1.htm,
    // https://biblehub.com/interlinear/1_kings/1-1.htm,
    // https://biblehub.com/interlinear/songs/1-1.htm(아가서만 예외 슬러그)로
    // 조회해 확인한 뒤 66권 전체를 하드코딩했다. Strong 링크는
    // https://biblehub.com/hebrew/430.htm, https://biblehub.com/greek/2316.htm
    // 처럼 앞자리 "H"/"G"와 0-padding을 뗀 순수 숫자만 받는다.
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

    // [2026-08-15 신설, 같은 날 수정] 네이버 사전 딥링크 — 사용자 요청: "원문
    // 옆에 네이버 링크 추가(원어-네이버링크-영문링크), 네이버 링크임을 표시할
    // 수 있도록." 처음엔 `query=`에 원어 단어 자체(유니코드 히브리어/그리스어
    // 글자)를 percent-encoding해 넣었는데, 사용자가 다시 정정 — "query는 스트롱
    // 코드 숫자만, range는 둘 다 all로":
    //   히브리어: https://dict.naver.com/hbokodict/#/search?range=all&query=<스트롱번호>
    //   헬라어:   https://dict.naver.com/grckodict/#/search?range=all&query=<스트롱번호>
    // "스트롱번호"는 `bibleHubStrongURL`이 이미 하는 것과 같은 규칙(코드 앞자리
    // "H"/"G"를 떼고 남은 숫자, 앞의 0도 자연히 사라짐 — 예: "H0430"→430)이라
    // 그 로직을 그대로 따른다. `#/search?...`는 네이버 사전 SPA의 해시 라우팅
    // 쿼리라 `URL(string:)`이 구조를 해석할 필요 없이 문자열 그대로 넘기면 된다.
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

    /// 네이버 브랜드 그린(#03C75A)의 작은 원형 "N" 배지 — 실제 네이버 로고
    /// 이미지 자산 없이도 "이 링크는 네이버로 연결된다"를 한눈에 표시하기
    /// 위한 최소 구현이다(사용자 요청 "네이버 링크임을 표시할 수 있도록").
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

    private var cardBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    private func loadWords() {
        words = OriginalTextLookupService.shared.words(bookId: bookId, chapter: chapter, verse: verseNumber)
        loadCachedGlosses()
        loadKRVVerseText()
    }

    /// [2026-08-13 추가] 번들 KRV(개역한글) DB에서 이 절 텍스트 한 줄을 읽어 온다.
    /// `OriginalTextLookupService.shared`처럼 커넥션을 캐싱하지 않는다 — 이 시트가
    /// 열릴 때 한 번만 조회하면 되는 값이라(원어 단어 목록처럼 반복 조회되지
    /// 않음) 매번 새로 여는 편이 캐시 수명 관리보다 단순하다. 실패하면(번들 DB를
    /// 못 찾음/해당 절이 없음) 빈 문자열로 두고 조용히 건너뛴다 — 원어 정보
    /// 자체는 이 텍스트 유무와 무관하게 계속 보여야 하므로 별도 에러 UI를 만들지
    /// 않았다.
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
        // ⚠️ [2026-08-09] `#Predicate`의 `contains` 매크로 변환은 `Set`보다 `Array`
        // 캡처가 더 안정적으로 확인돼(SwiftData 초기 버전에서 Set 캡처 관련 알려진
        // 이슈들이 있었음) 배열로 만들어 넘긴다.
        let codes = Array(Set(words.map(\.strongCode)))
        guard !codes.isEmpty else { return }
        let descriptor = FetchDescriptor<StrongGlossTranslation>(
            predicate: #Predicate { codes.contains($0.strongCode) }
        )
        let cached = (try? modelContext.fetch(descriptor)) ?? []
        var cacheByCode: [String: StrongGlossTranslation] = [:]
        for entry in cached { cacheByCode[entry.strongCode] = entry }

        // [2026-08-09 수정] 사용자 요청 — "한글정보가 없는 것도 수정할 수 있게 할
        // 것." 이전엔 `word.glossEn`이 빈 단어는 여기서 통째로 건너뛰어서, 그런
        // 단어에 사용자가 나중에 연필 아이콘으로 직접 입력해 캐시에 저장해 둬도
        // 다시 열 때마다 안 불러와지는 버그가 있었다 — 캐시 조회는 영어 뜻풀이
        // 유무와 무관하게 항상 하고, "자동번역 대상에 넣을지"만 영어 뜻풀이가
        // 있을 때로 제한한다.
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

    /// [2026-08-09 추가] 연필 아이콘을 누르면 지금 값(있으면 캐시값, 없으면 빈
    /// 문자열)을 편집창 초기값으로 채운다 — 자동번역 결과가 이미 있으면 그걸
    /// 고쳐 쓰는 흐름이 되고, 아직 없으면(번역 중이거나 "-") 처음부터 직접
    /// 입력하는 흐름이 된다.
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
