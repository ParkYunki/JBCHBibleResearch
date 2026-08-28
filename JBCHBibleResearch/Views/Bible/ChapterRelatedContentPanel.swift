//
//  ChapterRelatedContentPanel.swift
//  JBCHBibleResearch
//
//  [2026-08-08 신설] 사용자 요청 — "성경 장을 읽을 때 이 성경의 개요와 메모, 연구문서가
//  있다는 것을 한번에 확인할 수 있는 화면이 있는가?" screens.md 원본 대형 항목
//  목록엔 "S1 관련문서 패널"이 진입점으로 적혀 있었지만, 2026-08-07 라운드(S1~S11
//  전수 대조)에서 실제 코드에는 그런 패널이 없다는 걸 확인하고 README에 "미구현"으로
//  남겨 뒀던 항목이다 — 이번에 처음 구현한다.
//
//  BibleReadingView.swift가 `.inspector(isPresented:)`(iOS17+/macOS14+)로 이 뷰를
//  붙인다 — 사용자가 고른 배치("보조 사이드 패널": 창 폭이 넓으면 상시 노출, 좁으면
//  모달처럼 접힘)와 정확히 일치하는 SwiftUI 표준 동작이라 별도 반응형 레이아웃
//  코드가 필요 없었다.
//
//  [2026-08-11 재구성] 사용자 요청 — "절을 선택하지 않거나 두 구절 이상 선택하면
//  성경개요/장개요만 나와야 하고, 한 구절을 선택하면 해당 개요 + 관련 메모 +
//  연구 문서가 나와야 함." 이전엔 메모/연구문서 섹션이 절 선택 여부와 무관하게
//  "이 장 전체"를 대상으로 항상 떠 있었다 — 이제 정확히 절 하나가 선택돼 있을
//  때만 나타나고, 내용도 "이 절과 관련된 것"으로 좁힌다. "관련"의 기준은 두
//  가지를 합친다: ① 그 메모 자신의 좌표(memo.verse)가 정확히 이 절인 것(기존
//  "메모 작성" 흐름으로 만든, 이 절에 직접 달린 메모) + 문서는 업로드 시 "관련
//  성경 장"으로 수동 지정된 것(기존 `relatedChapterRef`/`relatedDocuments` 기능,
//  없애지 않고 그대로 살렸다), ② 메모/문서 본문 텍스트 안에서 이 절 참조가
//  자동으로 추출된 것(`VerseMention`, 2026-08-11 "관련 내용" 인덱스 — 지난
//  라운드에서 별도 "N절 관련 내용" 섹션으로 먼저 넣었던 것을 이번에 이 두
//  섹션으로 흡수했다). 두 기준을 합쳐야 기존에 이미 동작하던 기능(수동 태깅)을
//  잃지 않으면서 새 기능(자동 추출)도 같이 보여줄 수 있다.
//

import SwiftUI
import SwiftData
import BibleResearchModels
#if os(iOS)
import UIKit
#endif

struct ChapterRelatedContentPanel: View {
    let viewModel: BibleReadingViewModel
    /// 메모를 탭하면 호출부(BibleReadingView)가 기존 "메모 작성" 시트를 그대로
    /// 재사용해 연다 — `.sheet(item:)`은 대상이 새로 만든 메모든 기존 메모든
    /// 구분 없이 그 메모를 편집기로 띄운다.
    let onSelectMemo: (UserMemo) -> Void
    /// [2026-08-12 추가] 사용자 요청 — "[관련 말씀 요약] ... 개인 묵상, 연구문서와
    /// 동일한 프로세스로." `onSelectMemo`와 같은 역할 — 호출부(BibleReadingView)가
    /// 이 말씀 요약을 인스펙터 편집기로 연다.
    var onSelectWordSummary: (VerseSummary) -> Void = { _ in }
    /// [2026-08-11 추가] 정확히 절 하나가 선택돼 있을 때만 넘긴다(다중 선택이면
    /// "어느 절 기준인지" 모호해진다 — VerseZoomView를 여는 조건과 같은 원칙,
    /// BibleReadingView.verseSelectionActionBar 참고). nil이면 메모/연구문서
    /// 섹션 자체를 숨기고 개요만 보여준다.
    var selectedVerse: Int? = nil
    /// "관련 내용"(자동 추출) 목록에서 항목을 골랐을 때 — 메모는 편집기 시트로,
    /// 연구문서는 PDF 검색+이동 창으로 연다(호출부 BibleReadingView 책임).
    var onSelectVerseMention: (VerseMention) -> Void = { _ in }

    /// [2026-08-15 추가] 사용자 요청 — "개요 상단에 줄이기/펼치기 버튼 추가."
    /// 책 개요/장 개요를 독립적으로 접고 펼 수 있어야 해서 각자 상태를
    /// 따로 둔다. 기본값 `true`는 예전 동작(항상 내용이 보이던 미리보기)과
    /// 가장 가까운 시작 상태다.
    ///
    /// [2026-08-27 주석 정정] 이 프로퍼티가 비교 대상으로 삼던
    /// `OutlineBookBulkEditView.expandedChapters`(장마다 개별 접기/펼치기
    /// 아코디언)는 그 화면이 "탭한 장 하나만 보여주기"로 재설계되며 없어졌다
    /// (`OutlineBookBulkEditView.swift` 상단 주석 참고) — 이 패널 자체의
    /// 접기/펼치기 상태(`isBookOutlineExpanded`/`isChapterSummaryExpanded`)는
    /// 그 화면과 무관하게 독립적으로 계속 동작하므로 기능적으로는 영향이
    /// 없고, 옛 비유가 더 이상 맞지 않아 정정만 한다.
    @State private var isBookOutlineExpanded = true
    @State private var isChapterSummaryExpanded = true

    @Environment(\.openWindow) private var openWindow

    /// [2026-08-18 신설, 아이폰 실기기 크래시 fix] DocumentsHomeView.swift의
    /// `isPhoneIdiom`과 같은 패턴 — 아이폰은 다중 씬을 지원하지 않아
    /// `openWindow`가 런타임 에러를 낸다.
    private var isPhoneIdiom: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    var body: some View {
        // [2026-08-28 추가, 사용자 보고 — "성경조회 인스펙터 > 관련 연구문서
        // 클릭시 반응없음"] 원인 확정: 이 패널을 붙이는 `BibleReadingView`의
        // `.inspector(isPresented:)`(iOS/iPadOS 분기)는 이 뷰를 그 어떤
        // `NavigationStack`으로도 감싸지 않은 채 그대로 넘긴다 — `.sheet`/
        // `.fullScreenCover`로 여는 다른 화면들(`MemoDetailView`,
        // `TagRelationsView`, `OutlineTreeView`)은 전부 호출부가 명시적으로
        // `NavigationStack { ... }`로 감싸는 것과 다르다. 그 결과 아이폰
        // 전용 분기(`documentSection`의 `isPhoneIdiom`)가 쓰는
        // `NavigationLink { DocumentViewerWindowContent(...) }`가 자신을
        // 밀어 올릴 `NavigationStack`을 못 찾아 탭해도 아무 일도 일어나지
        // 않는다(SwiftUI 표준 동작 — `NavigationLink`는 조상 `NavigationStack`/
        // `NavigationView`가 없으면 조용히 아무 반응도 하지 않는다). 아이패드/
        // 맥은 같은 자리에서 `Button { openWindow(...) }`(다중 씬 지원 플랫폼
        // 전용, `isPhoneIdiom` 상단 주석 참고)만 쓰므로 이 문제 자체가 없었다.
        //
        // 고치려면 이 뷰 자신을 `NavigationStack`으로 감싸야 하는데, 지금까지
        // 이 뷰의 `.navigationTitle`/`.navigationBarTitleDisplayMode(.inline)`이
        // (감싸는 스택이 없어) 화면에 아무 효과도 못 내고 있었을 가능성이 있어,
        // 단순히 감싸기만 하면 지금까지 없던 제목 표시줄이 새로 나타나는
        // 의도치 않은 화면 변화가 생길 수 있다. 그래서 감싸되 그 표시줄 자체를
        // 계속 숨겨 둔다 — 기존 화면 모양은 그대로 유지하면서 `NavigationLink`가
        // 필요로 하는 스택만 새로 생기게 하는 최소 변경이다.
        //
        // [2026-08-28 빌드 에러로 수정] `ToolbarPlacement.navigationBar`는
        // iOS/iPadOS(+tvOS/watchOS) 전용이라 macOS엔 그 케이스 자체가 없다
        // (`'navigationBar' is unavailable in macOS`) — `PhoneTabView.swift`의
        // `fullScreenCover`와 같은 종류의 실수다. `#if os(iOS)`로 감싼다.
        // macOS는 이 값을 숨길 대응되는 API가 없어 그대로 둔다 — macOS의
        // `.inspector` 패널(보조 유틸리티 창 성격)이 `NavigationStack`의
        // `.navigationTitle`을 실제로 어떻게 그리는지는 이 환경(빌드 도구 없음)
        // 에서 확인할 수 없었다 — 혹시 제목 표시줄이 새로 보이면 알려주시면
        // 됩니다.
        NavigationStack {
            List {
                outlineSection
                if let selectedVerse {
                    memoSection(verse: selectedVerse)
                    wordSummarySection(verse: selectedVerse)
                    documentSection(verse: selectedVerse)
                }
            }
            .navigationTitle("이 장의 관련 콘텐츠")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    // MARK: - 개요(S8 책 개요 + S9 장 개요) — 선택 상태와 무관하게 항상 표시
    //
    // ⚠️ [2026-08-15 크래시 수정, 배경] 원래 `RichTextEditor(isEditable: false)`
    // (내부적으로 진짜 `NSTextView`/`NSScrollView`, `NSViewRepresentable`)를
    // 이 자리에 리스트 행으로 박아 넣었었다. 실기기 크래시 리포트로 확인된
    // 원인 — 이 패널은 `.inspector(isPresented:)`(macOS `NSSplitView` 기반)로
    // 붙어 있어 사용자가 그 분할선을 드래그하면 패널 폭이 라이브로 바뀌는데,
    // 그 리사이즈 이벤트 루프 도중 `NSTextView`가 `setAttributedString`/
    // 레이아웃 재계산을 하면서 AppKit이 이미 진행 중인 제약 조건 갱신 패스에
    // 재진입해(`-[NSWindow _postWindowNeedsUpdateConstraints]` 예외) 앱이
    // 죽었다. 그래서 `NSViewRepresentable`을 전혀 쓰지 않는, 순정 SwiftUI
    // `Text(AttributedString)` 렌더링으로 바꿨다 — 이후의 모든 개요 표시 관련
    // 변경(아래 3라운드 포함)도 계속 이 원칙을 따른다.
    //
    // [2026-08-15 3차 변경] 사용자 요청 4가지 — ① "'개요' 타이틀/'책 개요'/'장
    // 개요' 글자 크기를 왼쪽 사이드바 메뉴명 크기와 동일하게" — 처음엔 이걸
    // "사이드바가 상속받는 그 폰트"(`.appDefaultFont()` = Paperlogy-4Regular
    // 17pt)를 그대로 쓰는 걸로 해석했었다. [2026-08-15 5차 수정] 사용자가
    // 명시적으로 정정 — "페이퍼로지 폰트 말고 시스템 폰트로, 크기는 일반."
    // 즉 이 세 제목은 페이퍼로지가 아니라 시스템 기본 글꼴 + 표준(body) 크기로
    // 그린다(`.font(.body)`) — 사이드바 메뉴명과 "느낌"(평범한 내비게이션
    // 레이블 크기)만 맞추는 것이지, 앱 브랜딩 글꼴(Paperlogy)까지 강제하는 게
    // 아니다. `.appDefaultFont()` 대신 `.font(.body)`로 바꿨다.
    // ② "개요내용의 글자크기는 원래 에디터에 입력한 글자 사이즈 그대로" —
    // 지난 라운드에 추가했던 "왼쪽 성경 본문 크기로 통일"(`normalizingFontSize`)
    // 을 되돌렸다 — `outlineAttributedText`가 이제 RTF를 크기 변형 없이 그대로
    // 디코딩만 한다. ③ "새 창에서 보기 — 기존 창 재사용 금지, 책 개요/장 개요
    // (해당 장)만 표시, 상단 검색창 + 돋보기(배율)" — `OutlineQuickViewWindowContent`
    // (신설, `OutlineQuickViewRequest` 상단 주석 참고) 별도 창으로 교체했다.
    // ④ "'개요 화면 열기' 버튼 → 왼쪽 사이드바 개요 → 성경 선택 → 장 선택 후
    // 나오는 에디터 화면으로 전환" — `onJumpToOutline` 클로저(별도 창을 열던
    // 콜백)를 없애고, `AppNavigationRequest`(섹션 전환) + `OutlineNavigationRequest`
    // (책/장 선택, 신설)를 함께 호출하는 `jumpToOutlineEditor()`로 바꿨다 —
    // 이 버튼이 원래(2026-08-08~09) 하던 일과 같다(`AppNavigationRequest.swift`
    // 상단 주석 참고), 다만 이번엔 책/장까지 미리 선택된 채로 에디터 화면에
    // 진입한다는 점이 새로 추가됐다.
    //
    // 배경색/줄간격은 여전히 개요를 실제로 "쓰는" 화면(`OutlineBookBulkEditView`)이
    // 공유하는 `EditorDefaultStyle`(배경 #F5F1E8, 줄간격 배수 2.0)을 그대로
    // 가져와 적용한다 — 글자 "크기"만 원본 그대로이고, 배경/줄간격은 에디터
    // 기준이라는 요청을 그대로 반영했다.

    // ⚠️ [2026-08-15 4차 수정] "개요" 타이틀을 `Section(header:)` 슬롯에
    // `.appDefaultFont()`와 함께 넣었더니, 실기기 스크린샷으로 "책 개요"/"장
    // 개요"(일반 콘텐츠 행)는 커졌는데 이 타이틀만 여전히 작게 보인다는 게
    // 확인됐다 — macOS `List`의 섹션 헤더는 그 안에 어떤 `Text`/`.font(_:)`를
    // 넣든 시스템이 자체적으로 작은 보조 스타일을 강제로 씌운다(문서화되지
    // 않은 AppKit 브리징 동작, `.font(_:)` 오버라이드가 먹히지 않는다). 그래서
    // `header:` 슬롯 자체를 쓰지 않고, "개요"를 "책 개요"/"장 개요"와 똑같이
    // 그냥 평범한 리스트 행으로 넣었다 — 평범한 행은 스크린샷에서 이미 폰트
    // 적용이 확인됐으므로 이 쪽이 훨씬 신뢰할 수 있다.
    // [2026-08-20 추가] 사용자 요청 — "인스펙터 전체적인 스타일을 UI/UX 전문가
    // 관점에서 세련되게 조정 ... 적절한 색상과 아이콘을 추가할 것." macOS
    // `List`가 `Section(header:)` 슬롯 안 텍스트에 강제로 작은 보조 스타일을
    // 씌우는 문제(바로 위 [2026-08-15 4차 수정] 주석 참고) 때문에 애초에
    // "개요" 제목은 header 슬롯을 안 쓰고 평범한 행으로 넣어 뒀었다 — 그
    // 우회 패턴을 아래 세 섹션(개인 묵상/말씀 요약/연구문서, 지금까지는
    // `Section("문자열")`로 header 슬롯을 그대로 쓰고 있었다)에도 똑같이
    // 적용해 네 섹션 제목이 전부 같은 방식(아이콘+색 + 시스템이 축소하지
    // 않는 일반 크기)으로 보이게 통일했다. 아이콘 색은 섹션마다 다르게 둬서
    // (teal/blue/purple/orange) 한눈에 구분되게 하되, 제목 글자 자체는
    // 계속 `.secondary`로 눌러 둔다(이 패널 전체가 "보조 정보" 패널이라
    // 본문 성경 읽기 화면보다 시각적으로 튀면 안 된다는 기존 원칙 유지).
    private func sectionTitleRow(_ title: String, systemImage: String, tint: Color) -> some View {
        Label {
            Text(title)
                .font(.body)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
    }

    /// "이 절에 작성됨"/"본문에서 언급됨"/"이 장에 연결됨" — 각 항목이 왜 이
    /// 목록에 나왔는지 알려주는 작은 배지. 전에는 아이콘 없이 굵은 캡션
    /// 글자만 있었다 — 아이콘을 더해 항목들을 스캔하기 쉽게 했다(사용자 요청
    /// "적절한 색상과 아이콘을 추가할 것").
    private func originBadge(_ text: String, systemImage: String) -> some View {
        Label {
            Text(text).font(.caption.bold())
        } icon: {
            Image(systemName: systemImage).font(.caption2)
        }
        .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(isExpanded.wrappedValue ? "접기" : "펼치기")

                Text(title)
                    .font(.body)
                    .foregroundStyle(.secondary)

                Spacer()

                // [2026-08-28 추가] 사용자 요청 — "개요 섹션의 '별도 창에서
                // 보기' -> 아이폰에서 이 버튼을 아예 숨길 것." 다중 씬을
                // 지원하지 않는 아이폰에서 `openOutlineQuickViewWindow()`가
                // 부르는 `openWindow`는 "Unable to open a window when the
                // app does not support multiple scenes" 크래시로 이어진다
                // (아직 실제 신고는 없었지만 `documentSection`의
                // `taggedDocuments`/`handleVerseMentionSelected`가 겪은 것과
                // 완전히 같은 구조라 발견 즉시 공유했고, 사용자가 "숨길 것"으로
                // 확정했다). 아이폰에는 이미 대체 진입점("개요 화면 열기" —
                // 메인 내비게이션을 개요 섹션으로 전환)이 있어 대신 쓸 수
                // 있다.
                if !isPhoneIdiom {
                    Button {
                        openOutlineQuickViewWindow()
                    } label: {
                        Image(systemName: "macwindow")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("별도 창에서 보기")
                }
            }

            if isExpanded.wrappedValue {
                Text(outlineAttributedText(rtfText))
                    .lineSpacing(EditorDefaultStyle.lineSpacingPoints)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(EditorDefaultStyle.backgroundSwiftUIColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    /// 저장된 RTF를 크기 변형 없이 그대로 디코딩해 `AttributedString`으로
    /// 변환한다 — "개요내용의 글자크기는 원래 에디터에 입력한 글자 사이즈
    /// 그대로 보여줄 것"(사용자 요청). `AttributedString(_ attributedString:
    /// NSAttributedString)`은(iOS/macOS 공통, 특정 `AttributeScope`를 지정하는
    /// throwing 버전과 달리) 실패하지 않는 일반 변환 이니셜라이저라 플랫폼별
    /// 분기(`\.appKit`/`\.uiKit`)가 필요 없다. `defaultAttributes`는 RTF가
    /// 아닌 레거시/빈 텍스트일 때만 쓰이는 폴백이라, 에디터가 실제로 쓰는
    /// 기본 서체·크기(`EditorDefaultStyle.typingFont`)를 그대로 맞춘다.
    private func outlineAttributedText(_ rtfText: String) -> AttributedString {
        let decoded = RichTextCodec.decode(rtfText, defaultAttributes: [.font: EditorDefaultStyle.typingFont])
        return AttributedString(decoded)
    }

    /// "별도 창에서 보기" — 항상 새 창을 연다(`OutlineQuickViewRequest` 상단
    /// 주석 참고, `requestID`가 매번 새 `UUID`라 SwiftUI의 "같은 값이면 기존
    /// 창 재사용" 기본 동작을 우회한다).
    private func openOutlineQuickViewWindow() {
        openWindow(
            id: "outline-quick-view",
            value: OutlineQuickViewRequest(bookId: viewModel.selectedBook.bookId, chapter: viewModel.selectedChapter)
        )
    }

    /// "개요 화면 열기" — 메인 내비게이션을 개요(S8/S9) 섹션으로 전환하고,
    /// 지금 보고 있는 책/장을 미리 선택해 에디터 화면(`OutlineBookBulkEditView`,
    /// 기본값이 편집 가능)으로 바로 진입한다. `AppNavigationRequest.swift`/
    /// `OutlineNavigationRequest.swift` 상단 주석 참고.
    private func jumpToOutlineEditor() {
        AppNavigationRequest.shared.request(.outline)
        OutlineNavigationRequest.shared.request(bookId: viewModel.selectedBook.bookId, chapter: viewModel.selectedChapter)
    }

    // MARK: - 메모(구절 선택 시에만) — 이 절에 직접 달린 메모 + 이 절을 언급하는 메모

    @ViewBuilder
    private func memoSection(verse: Int) -> some View {
        let coordinateMemos = viewModel.relatedChapterMemos.filter { $0.verse == verse }
        let mentionedMemos = viewModel.verseMentions(verse: verse).filter { $0.sourceType == .memo }
        // [2026-08-11 12차 수정] 사용자 요청 — "x절 관련 메모 -> x절 관련 개인
        // 주석." 사이드바 섹션명("개인 주석")과 일관되게 맞춘다.
        // [2026-08-12 변경] "개인 주석" → "개인 묵상" 메뉴명 일괄 변경.
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
                }
            }
        }
    }

    private func memoPreview(_ memo: UserMemo) -> String {
        let trimmed = memo.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(내용 없음)" : trimmed
    }

    // MARK: - 말씀 요약(구절 선택 시에만) — [2026-08-12 신설]
    // 사용자 요청 — "[성경 조회] 오른쪽 상단 버튼중 사이드 인스펙터 창 버튼 -
    // 관련 문서 정보에 [관련 말씀 요약] 추가." 위 `memoSection(verse:)`와 완전히
    // 같은 구조(이 절에 직접 달린 것 + 본문에서 언급된 것) — 다만 말씀 요약은
    // 저널 성격이라 "이 절에 작성됨"에 해당하는 항목이 여러 개(날짜별로 쌓인
    // 기록) 나올 수 있다.

    @ViewBuilder
    private func wordSummarySection(verse: Int) -> some View {
        let coordinateSummaries = viewModel.relatedChapterWordSummaries.filter { $0.verse == verse }
        let mentionedSummaries = viewModel.verseMentions(verse: verse).filter { $0.sourceType == .wordSummary }
        Section {
            sectionTitleRow(
                "\(verse)절 관련 말씀 요약 (\(coordinateSummaries.count + mentionedSummaries.count))",
                // `text.quote`는 `BibleReadingView.verseSelectionActionBar`의
                // "말씀 요약" 버튼과 같은 아이콘 — 어디서 왔든 같은 기능은 같은
                // 아이콘으로 보이게 통일했다(사용자 요청 "앱의 전체적인
                // 통일성").
                // [2026-08-28 변경] 사용자 보고 — "번역본 선택 아이콘과 말씀
                // 요약 아이콘이 같다." 실제로 둘 다 `text.book.closed`를 썼던
                // 것을 확인(`BibleReadingView.swift`의 "번역본 선택"/"설치된
                // 번역본"(SettingsView.swift)은 그대로 두고, "말씀 요약" 쪽만
                // `text.quote`로 바꿔 구분한다 — 위 통일성 원칙은 "말씀 요약"
                // 두 곳(이 패널 + 액션바) 사이에서는 그대로 유지된다.
                systemImage: "text.quote", tint: .purple
            )
            if coordinateSummaries.isEmpty && mentionedSummaries.isEmpty {
                emptyRow("이 절에 작성됐거나 이 절을 언급하는 말씀 요약이 없습니다.")
            } else {
                // [2026-08-20 추가] 사용자 요청 — "관련 말씀 요약을 제목으로
                // 인식하는 맨 앞줄을 좀더 강조하고, 그 밑에 본문의 일부를
                // 표시할 것." `WordSummaryEditorView`가 새 요약을 만들 때
                // 항상 "yyyy.MM.dd 말씀"으로 첫 줄을 미리 채워 두므로(그 화면
                // 상단 주석 참고) 그 첫 줄이 사실상 제목 역할을 한다 — 아래
                // `wordSummaryTitleLine`/`wordSummaryBodyPreview`가 그 첫 줄과
                // 나머지 본문을 분리해서, 제목은 굵고 크게, 본문 일부는 그
                // 아래 보조 색으로 보여준다.
                ForEach(coordinateSummaries) { summary in
                    Button {
                        onSelectWordSummary(summary)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            originBadge("이 절에 작성됨 · \(wordSummaryDateLabel(summary))", systemImage: "square.and.pencil")
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
                }
            }
        }
    }

    /// 요약 본문의 첫 줄(제목처럼 보이는 줄, 위 주석 참고) — 없으면 전체
    /// 트리밍된 텍스트를 그대로 쓴다(레거시로 줄바꿈 없이 한 줄만 쓴 요약도
    /// 여전히 자연스럽게 보이도록).
    private func wordSummaryTitleLine(_ summary: VerseSummary) -> String {
        let trimmed = summary.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "(내용 없음)" }
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        let cleaned = firstLine.trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? trimmed : cleaned
    }

    /// 첫 줄을 뺀 나머지 본문 — 미리보기용으로 줄바꿈을 공백으로 이어붙인다.
    /// 둘째 줄부터가 없으면(제목 한 줄짜리 요약) 빈 문자열을 돌려주고, 호출부가
    /// 그 경우 본문 줄 자체를 그리지 않는다.
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
        Section {
            sectionTitleRow(
                "\(verse)절 관련 연구문서 (\(taggedDocuments.count + mentionedDocuments.count))",
                systemImage: "doc.text.magnifyingglass", tint: .orange
            )
            if taggedDocuments.isEmpty && mentionedDocuments.isEmpty {
                emptyRow("이 장에 연결됐거나 이 절을 언급하는 연구문서가 없습니다.")
            } else {
                ForEach(taggedDocuments) { document in
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
                ForEach(mentionedDocuments) { mention in
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
                }
            }
        }
    }

    /// 위 `taggedDocuments` 행 — 파일명 위에 "이 장에 연결됨" 배지를 얹어
    /// `mentionedDocuments` 행(originBadge + 본문)과 같은 리듬으로 보이게 한다.
    private func documentRowLabel(_ document: SourceDocument) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            originBadge("이 장에 연결됨", systemImage: "paperclip")
            Label(document.originalFilename, systemImage: "doc.text")
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
