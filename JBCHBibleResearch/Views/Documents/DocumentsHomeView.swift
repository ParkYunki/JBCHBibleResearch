//
//  DocumentsHomeView.swift
//  JBCHBibleResearch
//
//  S5(연구문서 업로드) 화면. screens.md 3장 S5/S6/S7 절 + 14장(업로드→인덱싱
//  프로세스) 근거. 업로드 3가지 진입점(툴바 `+`, 드래그앤드롭 존, 드롭존 클릭)이
//  모두 `DocumentsViewModel.upload(urls:)` 하나를 공유한다.
//
//  ⚠️ [아이폰 hwp 차단] `UIDevice.current.userInterfaceIdiom == .phone`일 때만
//  `DocumentUploadService.supportedContentTypes(allowHWP:)`에 `false`를 넘긴다 —
//  RootView.swift와 같은 방식(별도 타겟이 아니라 런타임 분기)을 그대로 따랐다.
//  아이패드/맥은 hwp를 그대로 선택할 수 있다(4.1 "검증 후 결정" 대상 — 일단 허용).
//
//  ⚠️ [드래그앤드롭 단순화] 여러 파일을 한꺼번에 드롭하면 `NSItemProvider`별로
//  URL이 비동기·개별적으로 resolve되는데, 이 구현은 "다 모일 때까지 기다렸다 한
//  번에 처리"하지 않고 resolve되는 대로 하나씩 바로 업로드한다 — DispatchGroup 등으로
//  일괄 처리를 만들 수도 있지만, 그러면 완료 콜백이 메인 액터 밖 임의 큐에서 오는
//  문제(Swift 6 엄격 동시성)를 다시 다뤄야 해서 더 단순한 개별 처리 경로를 택했다.
//  최종 동작(모든 드롭 파일이 각자 업로드됨)은 동일하다.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import BibleResearchModels
#if os(iOS)
import UIKit
#endif

/// [2026-08-16 신설] 사용자 요청 — "카테고리는 1) 업로드할 때 지정한 성경
/// 2) 특정 성경을 선택할 수 없는 경우 기존 카테고리 선택 또는 사용자 입력."
/// 두 갈래(성경 장 / 커스텀 카테고리)를 필터 하나로 다루기 위한 타입 — 실제
/// 저장은 그대로 `SourceDocument.relatedChapterRef`/`.category` 두 필드에
/// 각자 남는다(모델 변경 없음), 이건 화면 표시/필터링 용도로만 둘을 묶는다.
private enum DocumentCategoryFilter: Hashable {
    case all
    case uncategorized
    case chapter(BibleChapterRef)
    case custom(UUID)
}

/// [2026-09-09 신설] 사용자 요청 — "[문서 OCR] 배경색을 살펴볼 것." 이 화면은
/// `BibleReadingView`/`WordNoteHomeView`/`SearchView`의 "테마 확장" 작업에서
/// 빠져 있었다 — 완전히 같은 이유·같은 패턴(`.toolbarBackground(_:for:)`,
/// iOS 16+)을 이 화면의 진짜 시스템 내비게이션 바에도 적용한다(테마 배경을
/// 고르지 않았으면 아무것도 바꾸지 않는다).
private struct ThemedNavigationBarBackgroundModifier: ViewModifier {
    let color: Color?

    // [2026-09-10 추가] 위 `.toolbarBackground`가 요구하는 짝 API —
    // `@Environment(\.self)`로 현재 환경을 받아 `Color.resolve(in:)`에
    // 넘긴다(`Color+Hex.swift`의 `hexString(in:)`이 이미 쓰는 것과 같은,
    // 확인된 패턴). `Color(hex:)`로 만든 고정 RGB 색이라 라이트/다크 모드와
    // 무관하게 항상 같은 값이 나온다.
    @Environment(\.self) private var environment

    func body(content: Content) -> some View {
        // [2026-09-10 수정, 컴파일 에러 fix] 사용자 보고 — Xcode 에러
        // "'navigationBar' is unavailable in macOS"(WordNoteHomeView.swift
        // 134:49/135:52). `ToolbarPlacement.navigationBar`는 iOS/iPadOS/
        // tvOS/Mac Catalyst 전용이라, 이 앱의 macOS(순수 AppKit 창) 타깃에는
        // 그 심볼 자체가 없다 — 이 파일들 주석이 애초에 "iOS 16+에 공식
        // 제공하는 API"라고 적어 뒀던 전제를 `#if os(iOS)`로 실제 코드에도
        // 반영한다. macOS는 원래도 이 모디파이어로 바꿀 표준 API가 없다고
        // 판단해 채택한 적이 없으므로(각 파일 상단 주석 참고), macOS
        // 분기는 `color` 값과 무관하게 항상 아무 효과 없이 통과시킨다.
        #if os(iOS)
        if let color {
            content
                .toolbarBackground(color, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                // [2026-09-10 추가, 버그 수정 시도] 사용자 보고 — "테마를
                // 바꾸면 [성경] 화면의 상단(타이틀·책갈피 리스트·책갈피
                // 설정·히스토리·인스펙터 창·번역본 버튼 영역)이 사라짐."
                // 이 세션엔 실기기 재현이 불가능해 100% 확정은 못 했지만,
                // 코드로 확인되는 원인은 이렇다 — 지금까지 이 화면들은
                // `.toolbarBackground(_:for:)`만 쓰고 Apple 공식 문서가
                // 커스텀 배경색과 함께 쓰길 권하는 짝 API인
                // `.toolbarColorScheme(_:for:)`은 지정하지 않았다. 이게
                // 없으면 iOS는 내비게이션 바가 실제로 얼마나 밝은/어두운
                // 배경인지가 아니라 "앱 전체의 현재 라이트/다크 모드"만
                // 보고 시스템 제공 바 아이템의 기본 색을 정한다 — 예를 들어
                // 라이트 모드에서 어두운 테마(밤빛 서재 등, 이 앱의 실제
                // 프리셋 2개 중 1개가 어두운 배경 — `BibleSlideColorTheme.
                // swift` 참고)를 고르면 어두운 배경 위에 여전히 라이트
                // 모드용 짙은 색 아이템이 남아 거의 안 보이게 될 수 있다.
                // 배경색의 WCAG 2.1 상대 휘도(`BibleSlideColorTheme.swift`
                // 상단 주석이 2개 프리셋의 대비를 검증할 때 이미 수동으로
                // 쓴 것과 같은 공식)를 계산해 어두우면 `.dark`(밝은 아이템),
                // 밝으면 `.light`(어두운 아이템)를 명시적으로 지정한다.
                // 이 수정으로도 증상이 그대로 재현되면(예: 매번이 아니라
                // 설정 시트를 닫는 특정 시점에만 재현되는 등) 별도 원인이
                // 더 있다는 뜻이니, 재현되는 정확한 상황을 알려주시면 추가로
                // 조사한다.
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

struct DocumentsHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: DocumentsViewModel?

    /// [2026-08-15 추가, 크래시 수정] macOS는 이 메인 창과 설정 창(`Settings { }`,
    /// `JBCHBibleResearchApp.swift` 참고)이 동시에 떠 있을 수 있다 — 설정 창의
    /// "연구문서 전체 삭제"(SettingsView.swift `deleteAllDocuments()`)처럼 이
    /// 화면을 거치지 않은 다른 코드 경로가 같은 `modelContext`에서 `SourceDocument`
    /// 를 지우면, 이 화면이 그 순간 "떠 있는 채로" 있어서(`.onAppear`가 다시 안
    /// 불림) `viewModel.documents`(한 번 fetch해서 캐시해 두는 배열)가 지워진
    /// 객체를 계속 들고 있게 되고, 다음 리드로우에서 크래시했다(아래 `.onAppear`
    /// 주석 참고 — 그 fix만으로는 "화면이 계속 떠 있던" 이 경우를 못 막는다).
    /// `@Query`는 SwiftData가 컨텍스트 변경을 직접 구독해 자동 갱신해 주므로
    /// (누가 어디서 지웠든 상관없이), 목록 렌더링만큼은 `viewModel.documents`
    /// 대신 이걸 쓴다 — 지워진 객체가 애초에 이 배열에 남아있을 수 없다.
    @Query(sort: [SortDescriptor(\SourceDocument.uploadedAt, order: .reverse)])
    private var queriedDocuments: [SourceDocument]

    /// [2026-08-17 추가] 사용자 요청 — "연구문서 검색에 성경장절도 검색할 수
    /// 있도록 할 것." 문서 본문에서 이미 성경구절을 추출해 두는
    /// `BibleReferenceIndexingService.reindexDocument`(문서 저장 직후 호출)의
    /// 결과물 `VerseMention`을 그대로 재사용한다 — 검색어를 다시 문서 전체
    /// 텍스트에서 정규식으로 훑을 필요 없이, 이미 구조화된(책ID/장/절) 인덱스와
    /// 비교하면 된다. `sourceTypeRaw`(평범한 String 저장 프로퍼티, enum이 아님)로
    /// 걸러 문서 소스만 가져온다 — `removeMentions`(BibleReferenceIndexingService.swift)가
    /// 이미 같은 방식(String 프로퍼티에 대한 #Predicate 등호 비교)을 쓰고 있어
    /// 안전하다고 확인된 패턴이다.
    @Query(filter: #Predicate<VerseMention> { $0.sourceTypeRaw == "document" })
    private var documentVerseMentions: [VerseMention]

    @State private var isFileImporterPresented = false
    @State private var isDropTargeted = false
    /// [2026-08-07 추가] S7 "저장 후 다음" 큐 — 검수 대기 중인 문서 목록을 탭한
    /// 문서부터 시작하도록 회전시켜 담는다. 비어 있지 않으면 시트가 떠 있다는 뜻.
    /// `OCRReviewQueueView.swift` 참고.
    @State private var ocrReviewQueue: [SourceDocument] = []

    /// [2026-08-08 추가] 사용자 요청 — "문서를 업로드할 때 관련 성경 장을 입력받을
    /// 수 있도록". 업로드 3가지 진입점(툴바/드래그앤드롭/드롭존 클릭)에서 URL을
    /// 얻으면 곧바로 업로드하지 않고 일단 여기 담아 뒀다가, 관련 장 확인 시트에서
    /// "건너뛰기" 또는 "이 장으로 업로드"를 고른 뒤에 실제로 업로드한다 — 여러
    /// 파일을 한꺼번에 올려도 이 배치 전체에 같은 장 하나만 적용한다
    /// (DocumentsViewModel.upload(urls:relatedChapter:) 상단 주석 참고).
    @State private var pendingUploadURLs: [URL] = []
    @State private var chapterLinkBook: Book = BooksProvider.shared.books.first
        ?? Book(bookId: 1, testament: .old, orderIndex: 1, nameKo: "창세기", nameOriginal: "Genesis", abbreviation: ["창"], chapterCount: 50)
    @State private var chapterLinkChapter: Int = 1
    /// [2026-08-18 추가] 사용자 요청 — "연구문서 업로드시 반드시 카테고리 입력을
    /// 강제할 것. (선택하거나 개인이 입력하거나)." 관련 성경 장(위 두 프로퍼티,
    /// 여전히 "건너뛰기" 가능)과 달리 이 값은 업로드 확인 시트에서 nil인 동안
    /// "건너뛰기"/"이 장으로 업로드" 두 버튼을 모두 비활성화해 강제한다 —
    /// `UploadChapterLinkSheet` 참고. 새 업로드 배치가 시작될 때마다
    /// (`beginUpload`) nil로 되돌려 이전 배치에서 고른 카테고리가 실수로
    /// 새어 들어가지 않게 한다.
    @State private var pendingUploadCategory: ImageCategory?

    /// [2026-08-16 추가, 2026-08-17 갱신] 사용자 요청 — "업로드 영역과 목록
    /// 리스트 사이에 검색기능 추가할 것" → "띄어쓰기로 나누어 단어별 OR
    /// 검색." 파일명/카테고리/관련 성경 장/태그/본문/성경장절을 함께 매칭한다
    /// (`searchScore(for:)` 참고) — 예를 들어 "창세기"로 검색하면 파일명에
    /// 그 단어가 없어도 관련 장이 "창세기 1장"인 문서가 걸린다.
    @State private var searchText: String = ""
    /// [2026-08-16 추가] 사용자 요청 — "카테고리 기능 추가할 것. 검색기능에도
    /// 카테고리 필터링 기능을 넣을 것." 문서의 "카테고리"를 두 갈래로 본다는
    /// 요청대로(1: 업로드 시 지정한 성경 장, 2: 성경 장이 없을 때 쓰는 기존
    /// 카테고리/사용자 입력) `DocumentCategoryFilter`가 그 두 갈래를 필터 옵션
    /// 하나로 묶는다 — `categoryFilterMenu` 참고.
    @State private var categoryFilter: DocumentCategoryFilter = .all
    #if os(macOS)
    /// [2026-09-11 신설] 맥OS 3번째 열(Inspector, "카테고리 관리") 표시 여부 —
    /// `BibleReadingView.isRelatedContentPresented`와 같은 역할.
    @State private var isCategoryManagerPresented = false
    /// [2026-09-11 신설] `categoryManagerPanel`의 "새 카테고리" 입력창.
    @State private var newCategoryName = ""
    #endif
    /// [2026-09-09 추가] `WordNoteHomeView`/`SearchView`와 같은 읽기 전용
    /// 접근 패턴 — 아래 `ThemedNavigationBarBackgroundModifier`/`List` 테마에 쓴다.
    private var settings: UserSettingsStore { .shared }

    /// [2026-09-11 추가] 연구문서 "문서함" 카드의 책등 강조색을 밝은/어두운
    /// 테마에 맞게 고르기 위한 환경값 — `DocumentRowView.accentSpineColor`와
    /// 완전히 같은 판정 공식(그 struct는 private라 직접 재사용은 못 해 같은
    /// 공식만 옮겨 왔다).
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment

    /// 위 두 환경값으로 "지금 실제로 보이는 배경이 어두운지" 판정 — 테마
    /// 배경이 있으면 그 배경의 WCAG 상대휘도로, 없으면 시스템 라이트/다크로.
    private var isDarkBibleBackground: Bool {
        if let bg = settings.bibleBackgroundColor {
            let resolved = bg.resolve(in: environment)
            let luminance = 0.2126 * Double(resolved.red) + 0.7152 * Double(resolved.green) + 0.0722 * Double(resolved.blue)
            return luminance < 0.5
        }
        return colorScheme == .dark
    }

    private var allowsDragAndDrop: Bool {
        #if os(macOS)
        return true
        #elseif os(iOS)
        return UIDevice.current.userInterfaceIdiom != .phone
        #else
        return false
        #endif
    }

    private var allowsHWP: Bool {
        #if os(macOS)
        return true
        #elseif os(iOS)
        return UIDevice.current.userInterfaceIdiom != .phone
        #else
        return false
        #endif
    }

    /// [2026-09-11 신설] `OutlineTreeView`/`WordNoteHomeView`와 완전히 같은
    /// 이름·같은 판정 — 이 화면은 지금까지 플랫폼별 레이아웃 분기가 전혀
    /// 없었다(위 `allowsDragAndDrop`/`allowsHWP`는 "기능 허용 여부"이지
    /// "레이아웃 분기"가 아니었다). 아이패드 2열/맥 3열+Inspector 분할
    /// (`splitMainContent`)과 기존 아이폰 카드 홈(`phoneMainContent`)을
    /// 가르는 기준.
    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("연구문서")
        // [2026-09-03 추가] 사용자 보고 — "아이폰 하단 메뉴 중 말씀 노트/문서
        // OCR/통합 검색/더보기는 상단 우측 아이콘과 그 밑 타이틀이 따로 있어
        // 아이콘 좌측 영역이 낭비됨." `WordNoteHomeView.swift`의 같은 날짜
        // 주석과 같은 이유·같은 해법 — `.navigationBarTitleDisplayMode(.inline)`.
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // [2026-09-09 추가] 아래 `ThemedNavigationBarBackgroundModifier` 주석
        // 참고 — 이 화면의 진짜 시스템 내비게이션 바 배경을 테마에 맞춘다.
        .modifier(ThemedNavigationBarBackgroundModifier(color: settings.bibleBackgroundColor))
        // [2026-08-18 추가] 아이폰 다중 씬 미지원 fix — `documentRow`가 아이폰에서
        // `NavigationLink(value: document.persistentModelID)`로 미는 목적지를
        // 이 탭(NavigationStack)의 스코프에 등록한다. `DocumentViewerWindowContent`는
        // `WindowGroup(id: "document-viewer", ...)`(맥/아이패드용, JBCHBibleResearchApp.swift
        // 참고)가 쓰던 것과 같은 뷰 — PersistentIdentifier로부터 SourceDocument를
        // 다시 찾아오는 로직이 이미 삭제된 문서까지 안전하게 처리하므로 그대로 재사용한다.
        .navigationDestination(for: PersistentIdentifier.self) { documentID in
            DocumentViewerWindowContent(documentID: documentID)
        }
        #if os(macOS)
        // [2026-09-11 신설] 사용자 요청 — "맥OS 3열+Inspector". `BibleReadingView`
        // 의 `.inspector(isPresented:)`와 같은 API(아래 `categoryManagerPanel`
        // 주석 참고) — 항상 고정된 3번째 열이 아니라, 아래 `.toolbar`의 "카테고리
        // 관리" 버튼으로 여닫는 토글형 3번째 열이다.
        .inspector(isPresented: $isCategoryManagerPresented) {
            categoryManagerPanel
        }
        #endif
        .toolbar {
            #if os(iOS)
            // [2026-09-10 추가] `WordNoteHomeView.swift`와 같은 이유·같은
            // 해법 — 사용자 보고 "[성경] 화면을 제외한 기능의 화면(말씀노트,
            // 문서OCR, 통합검색)의 타이틀이 검은색으로 고정되어있음."
            // [2026-09-11 신설] 사용자 요청 — "문서함의 한 카드를 선택하여
            // 해당 카드의 문서리스트를 보는 화면에서 문서함으로 들어가기
            // 위해서 '연구문서' 최상단 중앙 타이틀 왼쪽 옆에 '<' 아이콘으로
            // 대체할 것." 아래 있던 화면 중앙의 "‹ 문서함" 버튼(`backToShelfButton`)
            // 을 없애고 이 아이콘 하나로 옮겼다 — 카테고리 필터가 "전체"가
            // 아닐 때만(문서함 카드를 탭해 들어왔거나, 기존 방식대로 뭔가
            // 골라도 마찬가지) 보인다.
            // [2026-09-11 수정] 사용자 확인 — 아이패드는 이제 폴더/문서
            // 목록을 "항상 좌우 분할"로 동시에 보여줘(`splitMainContent`
            // 참고) 이 되돌아가기 아이콘이 더 이상 필요 없다 — 아이폰
            // (`isPhone`, 여전히 카드 홈 ↔ 평면 목록을 바꿔치기하는 화면)
            // 에서만 보이도록 조건을 좁혔다.
            if isPhone && categoryFilter != .all {
                ToolbarItem(placement: .navigation) {
                    Button {
                        categoryFilter = .all
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
            }
            ToolbarItem(placement: .principal) {
                // [2026-09-10 수정] `WordNoteHomeView.swift`와 같은 이유·같은
                // 해법 — 각 기능 타이틀을 국민대학교 성곡 세리프체로 표시.
                Text("연구문서")
                    .font(.custom(SpecialPurposeFonts.titleSerif, size: 20, relativeTo: .title3))
                    .fontWeight(.semibold)
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
            }
            #endif
            #if os(macOS)
            // [2026-09-11 신설] 위 `.inspector(isPresented: $isCategoryManagerPresented)`
            // 를 여닫는 토글 버튼 — `BibleReadingView`의 "관련 콘텐츠" 인스펙터
            // 토글 버튼과 같은 원칙(표준 "inspector" 심벌 `sidebar.trailing`,
            // 항상 활성화).
            ToolbarItem(placement: .automatic) {
                Button {
                    isCategoryManagerPresented.toggle()
                } label: {
                    Label("카테고리 관리", systemImage: "sidebar.trailing")
                }
                .help("카테고리 생성 · 이름 변경")
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                // 진입점 1: 툴바 상시 노출 버튼(13장 "새 메모" 버튼과 동일 원칙).
                Button {
                    isFileImporterPresented = true
                } label: {
                    Label("업로드", systemImage: "square.and.arrow.up")
                }
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: DocumentUploadService.supportedContentTypes(allowHWP: allowsHWP),
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                beginUpload(urls: urls)
            }
        }
        // [2026-08-08 추가, 2026-08-18 카테고리 강제 추가] 업로드 확인 시트 —
        // "건너뛰기"로 닫으면 관련 장 없이 업로드, "이 장으로 업로드"를 고르면
        // 관련 장을 실어서 업로드한다. `pendingUploadURLs`가 비어 있지 않은
        // 동안만 떠 있다(OCRReviewQueueView의 큐 바인딩과 같은 원칙). 카테고리는
        // 두 경로 모두 공통으로 필요 — 시트 안에서 고르기 전엔 두 버튼 다
        // 비활성화된다(`UploadChapterLinkSheet` 참고).
        .sheet(isPresented: Binding(
            get: { !pendingUploadURLs.isEmpty },
            set: { isPresented in if !isPresented { pendingUploadURLs = [] } }
        )) {
            UploadChapterLinkSheet(
                book: $chapterLinkBook,
                chapter: $chapterLinkChapter,
                fileCount: pendingUploadURLs.count,
                categories: viewModel?.categories ?? [],
                selectedCategory: $pendingUploadCategory,
                onCreateCategory: { name in viewModel?.createCategory(named: name) },
                onSkip: { finishPendingUpload(relatedChapter: nil) },
                onConfirm: {
                    finishPendingUpload(relatedChapter: BibleChapterRef(bookId: chapterLinkBook.bookId, chapter: chapterLinkChapter))
                }
            )
        }
        // [2026-08-15 수정] 크래시 리포트 — `SourceDocument.conversionStatus`
        // getter에서 `_assertionFailure`(Swift 런타임 fatal error). 원인: 이
        // 화면이 한 번 나타난 뒤(`setUpIfNeeded`) `viewModel`이 계속 살아있는
        // 채로 유지되는데(사이드바 네비게이션 구조상 뷰 자체가 재생성되지
        // 않음), `setUpIfNeeded`는 `guard viewModel == nil`이라 두 번째부터는
        // 아무 것도 하지 않아 `viewModel.documents` 배열이 그때 그대로 캐시된
        // 채 남는다. 그런데 Settings → 개발자 → "연구문서 전체 삭제"처럼 이
        // 뷰모델을 거치지 않고 다른 코드 경로가 같은 `modelContext`에서
        // `SourceDocument`를 직접 지우면(`SettingsView.swift`
        // `deleteAllDocuments()`), 이 화면이 들고 있던 배열은 이미 지워진(무효한)
        // 객체를 계속 참조하게 된다 — SwiftUI가 그 객체로 `DocumentRowView`를
        // 다시 그리려는 순간(꼭 사용자가 뭘 눌러야 일어나는 게 아니라, 다른
        // 이유로 화면이 다시 그려지기만 해도) `.conversionStatus` 같은 프로퍼티
        // 접근이 크래시한다 — 지워진 SwiftData 모델 객체의 프로퍼티 접근은
        // Swift 예외로 잡을 수 없는 런타임 fatal error다.
        //
        // 고침: 이 화면이 "다시 보일 때마다"(setUpIfNeeded로 처음 만들 때뿐
        // 아니라) 항상 최신 목록을 다시 fetch한다 — 그러면 이미 지워진 객체는
        // 배열에서 통째로 빠지고, SwiftUI는 애초에 그 객체로 행을 그리려는
        // 시도조차 하지 않는다. ⚠️ [남은 리스크] macOS는 여러 창을 동시에 열 수
        // 있어, 이 화면이 "떠 있는 동안" 다른 창(Settings)에서 삭제가 일어나는
        // 경우까지는 이 fix로 완전히 막지 못한다 — 그 경우까지 막으려면
        // `@Query`(값이 바뀔 때 자동 갱신)로 바꾸는 더 큰 리팩터링이 필요하다.
        .onAppear {
            setUpIfNeeded()
            viewModel?.loadDocuments()
            viewModel?.loadCategories()
        }
        // 11장 File 메뉴 "연구문서 업로드... ⌘O" — AppCommands.swift 참고.
        .focusedSceneValue(\.uploadDocumentAction) { isFileImporterPresented = true }
        .alert("오류", isPresented: Binding(
            get: { viewModel?.lastErrorDescription != nil },
            set: { if !$0 { viewModel?.lastErrorDescription = nil } }
        )) {
            Button("확인") { viewModel?.lastErrorDescription = nil }
        } message: {
            Text(viewModel?.lastErrorDescription ?? "")
        }
        // [2026-08-07 추가] S7(OCR 검수) — screens.md 14.3 "검수 화면 진입(대기열
        // 방식 — '저장 후 다음'으로 순차 처리)"을 이제 실제로 반영한다. 예전엔 검수
        // 대기 행을 탭하면 NavigationLink로 OCRReviewView 하나만 열고, 저장하면
        // 목록으로 돌아가 사용자가 다음 대기 행을 다시 찾아 탭해야 했다 — 여기서는
        // 탭한 문서를 큐 맨 앞으로 오도록 회전시킨 뒤 시트로 열고, 저장/폐기할
        // 때마다 큐 안에서 자동으로 다음 문서로 넘어간다(OCRReviewQueueView 참고).
        .sheet(isPresented: Binding(
            get: { !ocrReviewQueue.isEmpty },
            set: { isPresented in
                if !isPresented {
                    ocrReviewQueue = []
                    viewModel?.loadDocuments()
                }
            }
        )) {
            OCRReviewQueueView(queue: ocrReviewQueue)
        }
    }

    // MARK: - 문서함 홈(카드형, 2026-09-11 신설)

    /// [2026-09-11 신설] 검색어가 없고 카테고리 필터가 "전체"인 기본 진입
    /// 상태에서만 이 카드형 홈을 보여준다 — 검색 중이거나 이미 특정
    /// 카테고리로 필터가 걸려 있으면(= 폴더 안에 있다고 볼 수 있는 상태)
    /// 기존 평면 목록을 그대로 쓴다. 기존 검색·필터 로직 자체는 전혀
    /// 바꾸지 않고 "기본 화면"만 하나 얹는 것이다.
    private var isShowingShelfHome: Bool {
        categoryFilter == .all && searchText.isEmpty
    }

    private struct DocumentFolderGroup: Identifiable {
        let id: UUID
        let name: String
        let documents: [SourceDocument]
        let filter: DocumentCategoryFilter
        let spineColor: Color
    }

    /// 카테고리별 책등 강조색 — 카테고리 자체엔 색 필드가 없어(`ImageCategory`
    /// 모델 참고) 이름과 색을 고정 연결할 방법이 없다 — 등장 순서(알파벳순,
    /// `DocumentsViewModel.loadCategories()` 정렬 기준 그대로)대로 순환
    /// 배정한다.
    private static let shelfSpineColors: [Color] = [
        JBCHCategoryPalette.gold, JBCHCategoryPalette.wood, JBCHCategoryPalette.slateTeal, JBCHCategoryPalette.wine,
    ]
    /// 위 네 색의 "밤빛 서재"(어두운 배경) 전용 변형 — `JBCHCategoryPalette.swift`
    /// 의 `woodOnDark`/`wineOnDark` 신설 주석 참고.
    private static let shelfSpineColorsOnDark: [Color] = [
        JBCHCategoryPalette.gold, JBCHCategoryPalette.woodOnDark, JBCHCategoryPalette.slateTealOnDark, JBCHCategoryPalette.wineOnDark,
    ]
    private static let uncategorizedGroupID = UUID()

    /// 카테고리(+미분류)별로 문서를 묶는다. 문서가 하나도 없는 카테고리는
    /// 카드로 보여주지 않는다(눌러도 빈 화면만 나오는 카드를 만들 이유가
    /// 없다고 판단했다). "미분류" 카드는 기존 필터 메뉴의 "미분류"
    /// (`.uncategorized`, `matchesCategoryFilter` 참고 — 카테고리도 관련
    /// 성경 장도 둘 다 없는 문서)와 정확히 같은 기준을 쓴다 — 카드에 뜬
    /// 개수와 탭했을 때 실제로 보이는 목록 개수가 어긋나지 않게 하기
    /// 위함이다. ⚠️ 카테고리는 없지만 관련 성경 장은 있는 문서는 이
    /// 정의상 어느 카드에도 속하지 않는다(기존 "미분류" 필터의 정의를
    /// 그대로 따른 결과) — 다만 "최근 문서"(아래)에는 항상 나타나므로
    /// 화면에서 완전히 사라지지는 않는다.
    private func folderGroups(viewModel: DocumentsViewModel) -> [DocumentFolderGroup] {
        var groups: [DocumentFolderGroup] = []
        let onDark = isDarkBibleBackground
        for (index, category) in viewModel.categories.enumerated() {
            let documents = queriedDocuments.filter { $0.category?.id == category.id }
            guard !documents.isEmpty else { continue }
            let spineColor = (onDark ? Self.shelfSpineColorsOnDark : Self.shelfSpineColors)[index % Self.shelfSpineColors.count]
            groups.append(DocumentFolderGroup(id: category.id, name: category.name, documents: documents, filter: .custom(category.id), spineColor: spineColor))
        }
        let uncategorized = queriedDocuments.filter { $0.category == nil && $0.relatedChapterRef == nil }
        if !uncategorized.isEmpty {
            groups.append(DocumentFolderGroup(
                id: Self.uncategorizedGroupID,
                name: "분류 없음",
                documents: uncategorized,
                filter: .uncategorized,
                spineColor: onDark ? JBCHCategoryPalette.shelfSlateOnDark : JBCHCategoryPalette.shelfSlate
            ))
        }
        return groups
    }

    /// 최근 업로드 5개 — `queriedDocuments`가 이미 업로드일 역순 정렬이라
    /// 앞에서 5개만 잘라 쓴다(카테고리와 무관, 목업의 "최근 문서" 절과
    /// 같은 개념).
    private var recentDocuments: [SourceDocument] {
        Array(queriedDocuments.prefix(5))
    }

    @ViewBuilder
    private func shelfHome(viewModel: DocumentsViewModel) -> some View {
        let groups = folderGroups(viewModel: viewModel)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !groups.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("문서함")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(settings.bibleTextColor ?? .primary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                            ForEach(groups) { group in
                                folderCard(group)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                if !recentDocuments.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("최근 문서")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(settings.bibleTextColor ?? .primary)
                            .padding(.horizontal)
                        // [2026-09-11 수정] 사용자 보고 — "최근문서의 타이틀이
                        // 흰색으로 고정되어있음." 이 `DocumentRowView`들은 List
                        // 밖(일반 VStack)에서 재사용돼 List의
                        // `.foregroundStyle(settings.bibleTextColor ?? Color.primary)`
                        // 를 물려받지 못했다 — 파일명 `Text`는 그 상속에만
                        // 기대고 자체 색이 없어(List 안에서 쓰일 때 원래
                        // 그렇게 설계됨) 시스템 기본값(다크 배경 위 흰색처럼
                        // 보임)이 그대로 드러났다. 같은 색을 여기서도 명시한다.
                        VStack(spacing: 0) {
                            ForEach(recentDocuments, id: \.id) { document in
                                DocumentRowView(
                                    document: document,
                                    highlightKeywords: [],
                                    bodyExcerpt: nil,
                                    bodyOccurrenceSum: 0,
                                    matchedTagNames: [],
                                    viewModel: viewModel,
                                    onOpenOCRReview: presentOCRReviewQueue
                                )
                                if document.id != recentDocuments.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding(.horizontal)
                        .foregroundStyle(settings.bibleTextColor ?? Color.primary)
                    }
                }
            }
            .padding(.vertical, 14)
        }
        .scrollContentBackground(.hidden)
        .background(settings.bibleBackgroundColor ?? Color.clear)
    }

    /// 문서함 카드 하나 — 탭하면 기존 `categoryFilter`를 그 카테고리로
    /// 바꾼다(새 네비게이션을 만들지 않는다, 위 타입 주석 참고). 책등
    /// 강조선은 `DocumentRowView.documentRowLabel`의 기존 "책등" 패턴
    /// (`RoundedRectangle().fill(색).frame(width: 3)`)과 같은 언어를 쓴다.
    /// [2026-09-11 확장] `isSelected` 매개변수 추가 — 분할 레이아웃(아이패드/맥,
    /// `folderSidebar`)에서 지금 `categoryFilter`가 가리키는 카드에 옅은 강조
    /// 배경을 얹어 "지금 이 폴더를 보고 있다"를 표시하기 위함. 기본값 `false`라
    /// 기존 호출부(`shelfHome`의 `folderCard(group)`, 아이폰 카드 홈)는 전혀
    /// 바뀌지 않는다.
    private func folderCard(_ group: DocumentFolderGroup, isSelected: Bool = false) -> some View {
        Button {
            categoryFilter = group.filter
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.custom(SpecialPurposeFonts.titleSerif, size: 17, relativeTo: .body))
                        .foregroundStyle(settings.bibleTextColor ?? .primary)
                        .lineLimit(1)
                    Text("\(group.documents.count)개 문서")
                        .font(.caption)
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.4) ?? Color.secondary)
            }
            .padding(.vertical, 12)
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected
                        ? (settings.bibleTextColor?.opacity(0.12) ?? Color.secondary.opacity(0.14))
                        : (settings.bibleTextColor?.opacity(0.05) ?? Color.secondary.opacity(0.06)))
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(group.spineColor)
                    .frame(width: 4)
                    .padding(.vertical, 6)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func content(viewModel: DocumentsViewModel) -> some View {
        VStack(spacing: 0) {
            dropZone(viewModel: viewModel)
                // [2026-09-10 수정] 위 `dropZone` 주석 참고 — 바깥 여백도
                // 같이 줄였다(세로만 — 가로는 좌우 화면 끝과의 간격이라
                // 그대로 둔다).
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            // [2026-08-16 추가] 사용자 요청 — 업로드 영역과 목록 사이에 검색 +
            // 카테고리 필터를 둔다.
            searchAndFilterBar(viewModel: viewModel)

            // [2026-09-11 수정] 사용자 요청 — 위 `searchContentOrnamentalDivider`
            // 주석 참고. 여기 있던 단순 `Divider()`를 대체한다.
            searchContentOrnamentalDivider

            // [2026-09-11 수정] 사용자 요청 — "아이패드 2열 / macOS 3열+Inspector"
            // (실기기 확인 필요, 이 세션엔 컴파일러 없음). 아이폰만 기존
            // 카드 홈 ↔ 평면 목록 바꿔치기(`phoneMainContent`)를 그대로 쓰고,
            // 아이패드/맥은 새 분할 레이아웃(`splitMainContent`)을 쓴다.
            if queriedDocuments.isEmpty {
                Spacer()
                Text("업로드된 연구문서가 없습니다.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else if isPhone {
                phoneMainContent(viewModel: viewModel)
            } else {
                splitMainContent(viewModel: viewModel)
            }
        }
        // [2026-09-09 추가] 사용자 요청 — "[문서 OCR] 배경색을 살펴볼 것."
        // 이 화면은 지금까지 테마 작업 대상에서 아예 빠져 있었다(다른 3개
        // 탭 — 성경/말씀노트/통합검색 — 만 처리됐었다) — `WordNoteHomeView.swift`
        // 의 바깥 `VStack` `.background()`와 같은 이유·같은 패턴: 아래
        // `List`의 `.background()`(있다면)는 리스트 프레임만 칠하지, 그 위
        // 드롭존·검색+필터 줄까지는 닿지 않는다 — 이 VStack 자신에도 같은
        // 배경을 한 번 더 칠해 화면 전체가 테마색으로 이어지게 한다.
        .background(settings.bibleBackgroundColor ?? Color.clear)
    }

    /// [2026-09-11 신설] 아이폰 전용 본문 — 문서함 카드 홈 ↔ 평면 목록을
    /// `isShowingShelfHome`으로 전환하는 기존 동작(Phase 1) 그대로 옮겨 왔을
    /// 뿐, 내용은 바꾸지 않았다. 분할 레이아웃(아이패드/맥)과 분리한 이유는
    /// 아래 `splitMainContent` 주석 참고.
    @ViewBuilder
    private func phoneMainContent(viewModel: DocumentsViewModel) -> some View {
        if isShowingShelfHome {
            shelfHome(viewModel: viewModel)
        } else if filteredResults.isEmpty {
            Spacer()
            Text("검색 결과가 없습니다.")
                .foregroundStyle(.secondary)
            Spacer()
        } else {
            documentList(viewModel: viewModel)
        }
    }

    /// [2026-09-11 신설] 사용자 요청 — "아이패드 2열 / macOS 3열+Inspector"
    /// (실기기 확인 필요, 이 세션엔 컴파일러 없음). 아이폰과 달리 화면을
    /// "문서함 카드 ↔ 문서 목록"으로 완전히 바꿔치기(replace)하지 않고,
    /// 왼쪽엔 문서함 폴더 카드를(`folderSidebar`), 오른쪽엔 그중 고른 폴더
    /// (`categoryFilter`)의 문서 목록을 "항상 좌우로 동시에" 보여준다 —
    /// 사용자가 명시적으로 고른 설계("문서함(폴더 카드) + 해당 폴더의
    /// 문서리스트, 항상 좌우 분할"). 이 화면엔 지금까지 플랫폼별 레이아웃
    /// 분기가 전혀 없었다(Outline/WordNote 등 다른 화면과 달리) — 그
    /// 화면들의 `XxxSplitContent`(HStack + Divider + 고정폭) 패턴을 그대로
    /// 옮겨 왔다.
    ///
    /// ⚠️ 문서를 실제로 "여는" 동작(행 탭 → 별도 창 openWindow, 또는 아이폰
    /// NavigationLink)은 사용자 확인대로 전혀 건드리지 않았다 — 이 분할은
    /// 오직 "어느 폴더를 보고 있는지"만 다루고, 문서 하나의 상세 정보(카테고리/
    /// 관련 성경장 편집 포함)는 이 분할과 무관하게 `DocumentRowView`의 기존
    /// 컨텍스트 메뉴(길게 프레스/우클릭)에서 여는 팝오버로 따로 구현했다
    /// (`DocumentRowView.documentInfoPopover` 참고) — 사용자가 "정보 컬럼이
    /// 항상 3번째 열일 필요는 없다"고 명시적으로 정정한 결과다.
    @ViewBuilder
    private func splitMainContent(viewModel: DocumentsViewModel) -> some View {
        HStack(spacing: 0) {
            folderSidebar(viewModel: viewModel)
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

            Divider()

            if filteredResults.isEmpty {
                VStack {
                    Spacer()
                    Text("검색 결과가 없습니다.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                documentList(viewModel: viewModel)
            }
        }
    }

    /// [2026-09-11 신설] 위 `splitMainContent`의 왼쪽 열 — 기존 `folderGroups`/
    /// `folderCard`(문서함 카드 홈, Phase 1)를 그대로 재사용하되, 탭하면 화면
    /// 전체를 바꿔치기하는 대신 `categoryFilter`만 바꾼다(오른쪽 `documentList`가
    /// 그 값을 그대로 읽는다). "전체 문서"(`allDocumentsCard`) 카드가 새로
    /// 필요했던 이유 — 아이폰의 "‹" 되돌아가기 버튼과 달리, 분할 레이아웃은
    /// 이 왼쪽 열이 늘 보이므로 그 버튼이 필요 없어진 대신, 특정 폴더를 고른
    /// 뒤 "전체 문서"로 되돌아갈 방법이 하나는 있어야 한다.
    @ViewBuilder
    private func folderSidebar(viewModel: DocumentsViewModel) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible())], spacing: 10) {
                allDocumentsCard
                ForEach(folderGroups(viewModel: viewModel)) { group in
                    folderCard(group, isSelected: categoryFilter == group.filter)
                }
            }
            .padding(12)
        }
        .scrollContentBackground(.hidden)
        .background(settings.bibleBackgroundColor ?? Color.clear)
    }

    private var allDocumentsCard: some View {
        Button {
            categoryFilter = .all
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("전체 문서")
                        .font(.custom(SpecialPurposeFonts.titleSerif, size: 17, relativeTo: .body))
                        .foregroundStyle(settings.bibleTextColor ?? .primary)
                        .lineLimit(1)
                    Text("\(queriedDocuments.count)개 문서")
                        .font(.caption)
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                }
                Spacer(minLength: 4)
            }
            .padding(.vertical, 12)
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(categoryFilter == .all
                        ? (settings.bibleTextColor?.opacity(0.12) ?? Color.secondary.opacity(0.14))
                        : (settings.bibleTextColor?.opacity(0.05) ?? Color.secondary.opacity(0.06)))
            )
        }
        .buttonStyle(.plain)
    }

    /// [2026-09-11 신설] 위 `splitMainContent`/`phoneMainContent`가 공유하는
    /// 문서 목록 — 원래 `content(viewModel:)`의 마지막 `else` 분기에 그대로
    /// 있던 `List(filteredResults) { ... }` 블록을 옮겨 왔을 뿐, 내용은 한
    /// 글자도 바꾸지 않았다(중복 구현 방지 — 아이폰/분할 레이아웃 양쪽에서
    /// 완전히 같은 목록을 그린다).
    @ViewBuilder
    private func documentList(viewModel: DocumentsViewModel) -> some View {
        List(filteredResults) { result in
            DocumentRowView(
                document: result.document,
                highlightKeywords: result.score.highlightKeywords,
                bodyExcerpt: result.score.bodyExcerpt,
                bodyOccurrenceSum: result.score.bodyOccurrenceSum,
                matchedTagNames: result.score.matchedTagNames,
                viewModel: viewModel,
                onOpenOCRReview: presentOCRReviewQueue
            )
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        // [2026-09-09 추가] 위 VStack `.background()` 주석 참고 —
        // `SearchView.swift`의 List와 같은 3종 세트
        // (`.scrollContentBackground(.hidden)` + `.background()` +
        // `.foregroundStyle()`). `.plain` 스타일이라 행마다 별도 카드
        // 배경이 없어 리스트 자체 배경 하나만 바꾸면 되고,
        // `.foregroundStyle`은 `DocumentRowView`의 색을 따로 지정하지
        // 않은 `Text`/`Image`가 물려받게 한다.
        .scrollContentBackground(.hidden)
        .background(settings.bibleBackgroundColor ?? Color.clear)
        .foregroundStyle(settings.bibleTextColor ?? Color.primary)
        // [2026-09-10 추가] 사용자 보고 — "어두운 배경에서는
        // 리스트의 행을 구분하는 라인이 거의 안보임."
        // `WordNoteHomeView.swift`와 같은 이유·같은 해법.
        .listRowSeparatorTint(JBCHCategoryPalette.wood.opacity(0.3))
    }

    #if os(macOS)
    /// [2026-09-11 신설] 맥OS 전용 3번째 열(Inspector) — "카테고리 관리".
    /// `BibleReadingView`의 `.inspector(isPresented:)` 패턴(그 화면 상단
    /// 주석 참고)을 그대로 따랐다 — 토글형 툴바 버튼(위 `.toolbar` 참고)으로
    /// 열고 닫는다. 사용자 확인대로 이번엔 "생성 + 이름 변경"만 넣고, "삭제"는
    /// (문서가 속한 카테고리를 지웠을 때 그 문서들을 어떻게 할지 추가 결정이
    /// 필요해) 다음으로 미뤘다.
    private var categoryManagerPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("카테고리 관리")
                .font(.headline)
                .padding()
            Divider()
            if let viewModel {
                List {
                    ForEach(viewModel.categories) { category in
                        CategoryManagerRow(category: category, viewModel: viewModel)
                    }
                }
                .listStyle(.plain)
                Divider()
                HStack {
                    TextField("새 카테고리", text: $newCategoryName)
                        .textFieldStyle(.plain)
                    Button("추가") {
                        let trimmed = newCategoryName.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        _ = viewModel.createCategory(named: trimmed)
                        newCategoryName = ""
                    }
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
            } else {
                Spacer()
            }
        }
        .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
    }
    #endif

    // MARK: - 검색 + 카테고리 필터 (2026-08-16 신설)

    /// 검색창(파일명/관련 성경 장/카테고리 이름 매칭) + 카테고리 필터 메뉴 한 줄.
    /// [2026-09-11 신설] 사용자 요청 — "연구문서 상단 문서 검색란 하단
    /// 단순 구분선 대신 첨부파일의 구분 선 추가할 것. (통합검색에 사용된
    /// 구분선)" `SearchView.menuContentOrnamentalDivider`와 같은 시각 언어
    /// (가로선-`sparkle`-가로선, 같은 wood 톤)를 옮겨 왔다 — 그 프로퍼티는
    /// `SearchView`에 private이라 직접 재사용은 못 하고, 여기는 List 행이
    /// 아니라 일반 VStack 안이라 `.listRowSeparator`/`.listRowBackground`는
    /// 뺐다.
    private var searchContentOrnamentalDivider: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(JBCHCategoryPalette.wood.opacity(0.3))
                .frame(height: 1)
            Image(systemName: "sparkle")
                .font(.system(size: 11))
                .foregroundStyle(settings.bibleTextColor?.opacity(0.45) ?? Color.secondary)
            Rectangle()
                .fill(JBCHCategoryPalette.wood.opacity(0.3))
                .frame(height: 1)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private func searchAndFilterBar(viewModel: DocumentsViewModel) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                // [2026-09-11 수정] 사용자 보고 — "검색란의 돋보기 모양
                // 아이콘 색상이 회색으로 고정되어있음." 같은 줄의 placeholder/
                // 테두리는 이미 테마를 따르는데 이 아이콘만 빠져 있었다.
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                // [2026-09-11 수정] 사용자 보고 — "연구문서 검색창의
                // placeholder, 검색창 테두리"가 테마를 안 따름. 단순
                // `TextField(_:text:)` 이니셜라이저는 placeholder 색을
                // 직접 지정할 방법이 없다 — `prompt:` 파라미터를 받는
                // 이니셜라이저(제목/접근성 문구는 그대로 두고, 실제 보이는
                // placeholder만 별도 `Text`로 지정 가능)로 바꿔 placeholder에
                // 명시적으로 테마 글자색을 옅게 입힌다.
                TextField(
                    "파일명, 관련 성경 장, 카테고리, 태그, 본문, 성경장절로 검색",
                    text: $searchText,
                    prompt: Text("파일명, 관련 성경 장, 카테고리, 태그, 본문, 성경장절로 검색")
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.5) ?? Color.secondary)
                )
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        // [2026-09-11 수정] 위 돋보기 아이콘과 같은 이유·같은
                        // 해법(사용자가 지목한 건 돋보기였지만 바로 옆 같은
                        // 문제라 함께 고쳤다).
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            // [2026-09-11 수정] 위 주석 참고 — 상자 배경(사실상 테두리처럼
            // 보이는 옅은 채움)이 `Color.secondary` 고정이라 테마와 무관했다.
            // 테마 글자색 기반 옅은 채움으로 바꾸고, 지금까지 없던 실제
            // 테두리 획도 하나 추가해 "검색창 테두리"가 테마를 따르도록 한다.
            .background(RoundedRectangle(cornerRadius: 8).fill(settings.bibleTextColor?.opacity(0.08) ?? Color.secondary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(settings.bibleTextColor?.opacity(0.2) ?? Color.secondary.opacity(0.2), lineWidth: 1))
            // [2026-09-11 삭제] 사용자 요청 — "검색란 오른쪽 필터 제거할
            // 것." 카테고리별 탐색은 이제 "문서함" 카드로 대신한다 — 다만
            // 이 메뉴에만 있던 "관련 성경 장별" 필터(`.chapter`)는 이걸
            // 지우면 UI에서 고를 방법이 당분간 없어진다(로직 자체는 그대로
            // 남겨 뒀다 — `categoryFilterMenu`/`chapterFilterOptions` 등).
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// 문서의 "카테고리"를 두 갈래로 다룬다는 요청대로 — 업로드 시 지정한 성경
    /// 장(현재 문서들에 실제로 쓰이고 있는 것만 나열) + 기존 커스텀 카테고리
    /// (`viewModel.categories`, `categoryMenu`가 새로 만드는 것과 같은 목록).
    private func categoryFilterMenu(viewModel: DocumentsViewModel) -> some View {
        Menu {
            Button {
                categoryFilter = .all
            } label: {
                Text("전체")
            }
            Button {
                categoryFilter = .uncategorized
            } label: {
                Text("미분류")
            }
            let chapters = chapterFilterOptions
            if !chapters.isEmpty {
                Divider()
                ForEach(chapters, id: \.self) { ref in
                    Button(chapterLabel(for: ref)) { categoryFilter = .chapter(ref) }
                }
            }
            if !viewModel.categories.isEmpty {
                Divider()
                ForEach(viewModel.categories) { category in
                    Button(category.name) { categoryFilter = .custom(category.id) }
                }
            }
        } label: {
            Label(categoryFilterLabel(viewModel: viewModel), systemImage: "line.3.horizontal.decrease.circle")
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    /// 현재 목록에 실제로 쓰이고 있는 관련 성경 장만 중복 없이, 책/장 순서로.
    private var chapterFilterOptions: [BibleChapterRef] {
        var seen = Set<BibleChapterRef>()
        var result: [BibleChapterRef] = []
        for ref in queriedDocuments.compactMap(\.relatedChapterRef) where !seen.contains(ref) {
            seen.insert(ref)
            result.append(ref)
        }
        return result.sorted { ($0.bookId, $0.chapter) < ($1.bookId, $1.chapter) }
    }

    private func chapterLabel(for ref: BibleChapterRef) -> String {
        guard let book = BooksProvider.shared.book(id: ref.bookId) else { return "\(ref.chapter)장" }
        return "\(book.nameKo) \(ref.chapter)장"
    }

    private func categoryFilterLabel(viewModel: DocumentsViewModel) -> String {
        switch categoryFilter {
        case .all: return "전체"
        case .uncategorized: return "미분류"
        case .chapter(let ref): return chapterLabel(for: ref)
        case .custom(let id):
            return viewModel.categories.first(where: { $0.id == id })?.name ?? "분류"
        }
    }

    /// [2026-08-17 확장] 사용자 요청 — "검색어 띄어쓰기 해서 검색할 때 띄어쓰기로
    /// 글자를 나누어서 각 검색단어별로 OR 검색을 하고, 검색매칭이 가장 많은
    /// 순서대로 정렬시킬 것. 1) 태그 일치 2) 파일명 일치 3) 본문 내용 일치."
    /// 예전에는 검색어 전체를 하나의 부분 문자열로 보고(AND, 전체가 그대로
    /// 포함돼야 함) 매칭했다 — 이제 공백으로 나눈 단어마다 OR로 검색하고, 그
    /// 결과를 태그>파일명>본문 우선순위 + 일치 단어 개수로 정렬한다.
    private var searchWords: [String] {
        searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    /// 문서 하나에 대한 검색 매칭 결과 — 태그/파일명(+카테고리/관련 장)/본문
    /// 세 갈래로 나눠 "몇 개의 검색단어가 그 갈래에서 일치했는지" 센다.
    ///
    /// [2026-08-17 재정정] 사용자 요청 — "검색결과 정렬은 일치하는 갯수
    /// 내림차순으로 할것." 바로 앞서 구현했던 "태그 > 파일명 > 본문" 우선순위
    /// 사전식 정렬을 걷어내고, 세 갈래 개수를 그냥 합친 `totalMatchCount` 하나로
    /// 단순 내림차순 정렬한다 — 갈래별 개수는 그대로 남겨 두되(각각 어디서
    /// 걸렸는지는 여전히 계산해야 본문 스니펫/태그·파일명 매칭 여부를 알 수
    /// 있다), 정렬 기준만 사용자가 명시한 대로 "총 일치 개수" 하나로 바꿨다.
    private struct DocumentSearchScore {
        let tagCount: Int
        let filenameCount: Int
        let contentCount: Int
        /// [2026-08-17 세 번째 정정] 사용자 요청 — "각 문자열 뒤에 검색된 횟수
        /// (xx) 숫자는 지울것." `Self.buildContentSnippet`이 조각마다 붙이던
        /// "(개수)"를 없앴다 — 이제 "단어+뒤 9자 ... 단어+뒤 9자"만 이어붙인,
        /// 개수 표기가 전혀 없는 순수 발췌문이다(70자 캡은 그대로). 본문에서
        /// 전혀 안 걸렸으면(태그/파일명만으로 매칭됐거나 성경장절 참조로만
        /// 매칭됐으면) nil.
        let bodyExcerpt: String?
        /// "(xx 회 일치)"에 쓰는 숫자 — 본문에서 검색단어들이 총 몇 번 등장했는지
        /// (단어별 개수의 합). `bodyExcerpt`가 더 이상 개수를 직접 보여주지
        /// 않으므로 이 숫자를 따로 들고 있어야 화면에 표시할 수 있다.
        let bodyOccurrenceSum: Int
        /// [2026-08-17 추가] 사용자 요청 — "태그가 일치가 되면 (xx 회 일치) 뒤
        /// 본문 앞에 태그명을 뱃지형식으로 보여줄것." 검색단어와 실제로 일치한
        /// 태그의 "이름"들(중복 제거, 문서에 붙은 순서) — `tagCount`(몇 개의
        /// 검색단어가 태그에서 걸렸는지, 정렬용 숫자)와는 별개로, 뱃지에 실제
        /// 표시할 텍스트가 필요해서 태그 자체를 따로 든다.
        let matchedTagNames: [String]
        /// [2026-08-18 추가] 사용자 요청 — "성경장절 검색시 검색에 관련된
        /// 연구문서의 성경 장절은 형광펜강조(범위에 포함된 성경구절인 경우
        /// 범위 텍스트를 강조) 예) 창1:3으로 검색 -> 창1:1-5 의 텍스트 강조가
        /// 되어야 함." 검색어로 타이핑한 단어들(`searchWords`)만 하이라이트
        /// 대상으로 삼으면 "창1:3"을 검색해도 문서에 실제로 적힌 "창1:1~5"는
        /// 글자 그대로 다르니 하이라이트되지 않는다 — 이 문서에서 실제로
        /// 겹친 성경구절의 원문 표현(`verseMentionSearchTexts`)까지 합쳐서
        /// `DocumentRowView.highlightedText`에 넘긴다. 파일명/본문 발췌 둘 다
        /// 이 목록으로 강조한다(검색단어 + 이 문서에서 실제로 겹친 성경구절
        /// 표현).
        let highlightKeywords: [String]

        static let empty = DocumentSearchScore(
            tagCount: 0, filenameCount: 0, contentCount: 0,
            bodyExcerpt: nil, bodyOccurrenceSum: 0, matchedTagNames: [], highlightKeywords: []
        )

        var isMatch: Bool { tagCount > 0 || filenameCount > 0 || contentCount > 0 }
        /// 정렬 기준 — 갈래 구분 없이 그냥 다 더한 "총 일치 개수"(사용자 요청
        /// "일치하는 갯수 내림차순"). 위 `bodyOccurrenceSum`("(xx 회 일치)"
        /// 표시용, 본문만)과는 다른 숫자다 — 태그/파일명까지 섞은 정렬 전용 값.
        var totalMatchCount: Int { tagCount + filenameCount + contentCount }
    }

    private struct DocumentSearchResult: Identifiable {
        let document: SourceDocument
        let score: DocumentSearchScore
        var id: UUID { document.id }
    }

    /// [2026-08-16 신설, 2026-08-17 두 차례 정렬 로직 조정] 검색 + 카테고리
    /// 필터를 모두 통과한 문서를, 사용자 최종 요청("검색결과 정렬은 일치하는
    /// 갯수 내림차순으로 할것") 그대로 `totalMatchCount`(태그+파일명+본문 일치
    /// 개수 합) 내림차순으로 정렬해 돌려준다(직전에 구현했던 "태그>파일명>본문
    /// 우선순위" 사전식 정렬은 이 요청으로 대체됐다). 개수가 같으면 `sorted`가
    /// Swift 표준 안정 정렬이라 원래 순서(최근 업로드순)가 그대로 유지된다.
    /// 검색어가 비어 있으면(공백만 있거나 아예 없으면) 정렬을 건드리지 않고
    /// 원래 `@Query` 순서(최근 업로드순)를 그대로 유지한다.
    private var filteredResults: [DocumentSearchResult] {
        let candidates = queriedDocuments.filter { matchesCategoryFilter($0) }
        guard !searchWords.isEmpty else {
            return candidates.map { DocumentSearchResult(document: $0, score: .empty) }
        }
        let scored: [DocumentSearchResult] = candidates.compactMap { document in
            let score = searchScore(for: document)
            guard score.isMatch else { return nil }
            return DocumentSearchResult(document: document, score: score)
        }
        return scored.sorted { $0.score.totalMatchCount > $1.score.totalMatchCount }
    }

    /// [2026-08-16 확장, 2026-08-17 OR/점수 방식으로 재작성, 2026-08-18
    /// 성경구절 하이라이트 추가] 사용자 요청 — "상단 검색: 본문검색, 태그
    /// 검색 포함" 이후 "띄어쓰기로 나누어 단어별 OR 검색 + 매칭 많은 순
    /// 정렬(태그>파일명>본문)"까지 반영한다. 성경장절 참조 검색
    /// (`verseMentionSearchTexts`)은 단어 단위로 쪼개면 "창세기 1:3"
    /// 같은 표현 자체가 깨지므로(책 이름과 장:절 사이 공백이 의미가 있음)
    /// 예외적으로 검색어 전체 문자열을 그대로 써서 한 번만 확인하고, 걸리면
    /// 본문(content) 점수에 1을 더한다 — 성경구절 언급도 결국 문서 본문에서
    /// 추출된 것이라 본문 갈래로 분류했다. 카테고리 이름/관련 성경 장 라벨은
    /// 예전부터 파일명과 같은 자리(짧은 제목성 메타데이터)에 있었으므로 그대로
    /// 파일명 점수에 합산한다.
    private func searchScore(for document: SourceDocument) -> DocumentSearchScore {
        let words = searchWords
        guard !words.isEmpty else { return .empty }

        let tagNames = (document.documentTags ?? []).compactMap { $0.tag?.name }
        let tagCount = words.filter { word in
            tagNames.contains { $0.localizedCaseInsensitiveContains(word) }
        }.count
        // [2026-08-17 추가] "태그가 일치가 되면 ... 태그명을 뱃지형식으로
        // 보여줄것" — 실제로 매칭된 태그 "이름"만 순서·중복 없이 골라 둔다
        // (위 `tagCount`는 "몇 개의 검색단어가 걸렸는지"라 뱃지에 쓸 태그
        // 이름 목록과는 다른 숫자다).
        var seenTagNames = Set<String>()
        let matchedTagNames = tagNames.filter { name in
            words.contains { name.localizedCaseInsensitiveContains($0) } && seenTagNames.insert(name).inserted
        }

        var titleFields = [document.originalFilename]
        if let category = document.category { titleFields.append(category.name) }
        if let ref = document.relatedChapterRef { titleFields.append(chapterLabel(for: ref)) }
        let filenameCount = words.filter { word in
            titleFields.contains { $0.localizedCaseInsensitiveContains(word) }
        }.count

        let lines = (document.documentTexts ?? []).sorted {
            $0.pageNumber != $1.pageNumber ? $0.pageNumber < $1.pageNumber : $0.lineIndex < $1.lineIndex
        }

        // [2026-08-18 추가] 사용자 요청 — "성경장절 검색시 ... 창1:3으로 검색
        // -> 창1:1-5 의 텍스트 강조가 되어야 함." 타이핑한 단어 그대로가
        // 아니라, 이 문서에서 실제로 겹친 성경구절의 "원문 표현"
        // (`VerseMention.searchText`, 예: "창1:1~5")도 검색/강조 대상에
        // 합친다 — 그래야 검색어와 문서 표기가 글자 그대로 다를 때도(약어↔
        // 전체이름, 범위 포함 등) 실제로 해당 텍스트를 찾아 강조할 수 있다.
        // 검색어로 타이핑한 단어(`words`)와 합쳐 아래 한 루프에서 동일하게
        // 처리한다 — 중복이 섞여 있으면 같은 텍스트를 두 번 세게 되므로
        // 대소문자 무시 기준으로 중복 제거한다.
        let verseTerms = verseMentionSearchTexts(for: document)
        var seenTerms = Set<String>()
        let allTerms = (words + verseTerms).filter { seenTerms.insert($0.lowercased()).inserted }

        // [2026-08-17 갱신] 검색단어(+성경구절 원문 표현)별로 "본문에 몇 번
        // 나오는지"(count)와 "첫 등장 위치에서 그 단어 + 뒤 9자"(excerpt,
        // "10자 미만" 요구사항 — 단어 자체 뒤에 최대 9글자만 더 붙인다)를
        // 함께 구한다. 여러 줄에 걸쳐 셀 수 있게 줄 단위로 다시 훑는다 —
        // `range(of:options:.caseInsensitive)`를 줄 하나 안에서 반복 탐색하는
        // 원리는 `DocumentRowView.highlightedText`와 동일하다(원본 문자열
        // 위에서 바로 대소문자 무시 검색 — lowercased()로 만든 별도 문자열의
        // 인덱스를 재사용하지 않는 이유도 같다).
        var occurrenceCounts: [String: Int] = [:]
        var firstExcerpts: [String: String] = [:]
        for line in lines {
            let text = line.lineText
            for term in allTerms where !term.isEmpty {
                var searchRange = text.startIndex..<text.endIndex
                while let found = text.range(of: term, options: [.caseInsensitive], range: searchRange) {
                    occurrenceCounts[term, default: 0] += 1
                    if firstExcerpts[term] == nil {
                        let tailEnd = text.index(found.upperBound, offsetBy: 9, limitedBy: text.endIndex) ?? text.endIndex
                        firstExcerpts[term] = String(text[found.lowerBound..<tailEnd])
                    }
                    searchRange = found.upperBound..<text.endIndex
                }
            }
        }
        // 몇 개의 "서로 다른" 검색어(타이핑 단어 + 성경구절 표현)가 본문에서
        // 걸렸는지(정렬용 — 개별 등장 횟수가 아니다). `verseTerms`가 실제
        // 줄에서 못 찾아졌더라도(이론상 있을 수 없지만, 방어적으로) 성경구절
        // 매칭 자체는 이미 확정된 사실이라 최소 1은 반영한다.
        var contentCount = occurrenceCounts.keys.count
        if !verseTerms.isEmpty && verseTerms.allSatisfy({ occurrenceCounts[$0] == nil }) {
            contentCount += 1
        }

        // "(xx 회 일치)"에 쓰는 숫자 — 본문에서 검색어(+성경구절 표현)들이 총
        // 몇 번 등장했는지(등장 횟수의 합). 정렬 기준인 `totalMatchCount`
        // (태그/파일명 포함, "서로 다른 단어" 개수)와는 의도적으로 다른 숫자다.
        let bodyOccurrenceSum = occurrenceCounts.values.reduce(0, +)
        let bodyExcerpt = Self.buildContentSnippet(words: allTerms, excerpts: firstExcerpts)
        return DocumentSearchScore(
            tagCount: tagCount, filenameCount: filenameCount, contentCount: contentCount,
            bodyExcerpt: bodyExcerpt, bodyOccurrenceSum: bodyOccurrenceSum, matchedTagNames: matchedTagNames,
            highlightKeywords: allTerms
        )
    }

    /// [2026-08-17 세 번째 정정] 사용자 요청 — "각 문자열 뒤에 검색된 횟수
    /// (xx) 숫자는 지울것." 조각마다 붙이던 "(개수)"를 없애고, 검색어에 등장한
    /// 순서 그대로 "단어+뒤 9자" 발췌만 " ... "로 이어붙인다. 결과가 70자를
    /// 넘으면 70자에서 잘라 말줄임표(…)를 붙인다 — "총 70자를 넘지 않도록"
    /// 요구사항을 "70자 이하"로 해석했다(잘렸다는 걸 알 수 있게 표시).
    private static func buildContentSnippet(words: [String], excerpts: [String: String]) -> String? {
        let segments = words.compactMap { excerpts[$0] }
        guard !segments.isEmpty else { return nil }
        let joined = segments.joined(separator: " ... ")
        guard joined.count > 70 else { return joined }
        let cutIndex = joined.index(joined.startIndex, offsetBy: 70)
        return String(joined[..<cutIndex]) + "…"
    }

    /// [2026-08-17 추가] 사용자 요청 4가지 조건을 모두 `BibleReferenceExtractor`
    /// 하나로 충족한다 — 그 파서가 이미 다음을 다 하고 있기 때문에 새로 구현할
    /// 필요가 없었다:
    /// - 띄어쓰기 무시: 정규식 자체가 책 이름과 장/절 사이 공백을 `\s*`로 허용.
    /// - 약어 ↔ 전체 이름 상호 검색: `Book.abbreviation + [Book.nameKo]`를 모두
    ///   같은 후보 형태(forms) 목록에 넣고 정규식 하나로 매칭하므로, 검색어를
    ///   "약어"로 쓰든 "전체 이름"으로 쓰든, 문서 본문에 어느 쪽으로 적혀 있든
    ///   같은 (bookId, chapter, verse) 좌표로 정규화된다.
    /// - 범위 포함 검색: 문서 쪽 인덱싱(`BibleReferenceIndexingService.
    ///   reindexDocument`)이 이미 "창1:1~5" 같은 범위를 절 하나하나로 펼쳐서
    ///   (`expandRange`) `VerseMention`에 저장해 두므로, 검색어가 그 범위 안의
    ///   절 하나("창세기 1:3")만 가리켜도 좌표가 정확히 일치한다. 반대로 검색어
    ///   자체가 범위여도(예: "창1:1~3") 마찬가지로 펼쳐진 뒤 겹치는 좌표가 있는지
    ///   비교한다.
    ///
    /// 좌표 비교 시 장 번호까지만 적고 절이 없는 쪽("창세기 1장")은 그 장의 어느
    /// 절과도 일치하는 것으로 본다 — `relatedChapterRef` 필터가 이미 장 단위로만
    /// 비교하는 것과 같은 원칙(더 넓은 쪽이 이긴다).
    ///
    /// [2026-08-18 확장] 사용자 요청 — "성경장절 검색시 검색에 관련된 연구문서의
    /// 성경 장절은 형광펜강조(범위에 포함된 성경구절인 경우 범위 텍스트를
    /// 강조)." 원래는 일치 여부(Bool)만 돌려줬는데, 이제 하이라이트할 실제
    /// 문서 원문 표현(`VerseMention.searchText`, 예: "창1:1~5")이 필요해져
    /// `[String]`(겹치는 멘션들의 원문 표현, 중복 제거)을 돌려주도록 확장했다
    /// — 빈 배열이면 예전의 "매칭 안 됨"과 같다. 이 문서의 좌표와 겹치는
    /// `VerseMention`을 찾는 로직 자체는 그대로다.
    private func verseMentionSearchTexts(for document: SourceDocument) -> [String] {
        let queryMatches = searchVerseQueryMatches
        guard !queryMatches.isEmpty else { return [] }
        let docId = document.id.uuidString
        var seen = Set<String>()
        return documentVerseMentions
            .filter { mention in
                guard mention.sourceId == docId else { return false }
                return queryMatches.contains { query in
                    query.bookId == mention.bookId
                        && query.chapter == mention.chapter
                        && (query.verse == nil || mention.verse == nil || query.verse == mention.verse)
                }
            }
            .map(\.searchText)
            // 범위 표현("창1:1~5")은 절 개수만큼 VerseMention으로 펼쳐져 있어
            // 같은 searchText가 여러 번 나올 수 있다 — 중복 제거.
            .filter { seen.insert($0).inserted }
    }

    /// `searchScore(for:)`가 문서마다 반복 호출되는 동안 같은 검색어를 매번
    /// 다시 정규식으로 파싱하지 않도록 한 번만 계산해 둔다(`BibleReferenceExtractor.
    /// extract`는 정규식 컴파일 자체는 캐싱하지만 매칭 스캔은 호출마다 다시
    /// 돈다) — `filteredResults`가 렌더링 한 번에 이 값을 여러 번 참조해도
    /// SwiftUI가 뷰 갱신마다 새로 계산하는 건 다른 필터 조건(태그/본문 스캔)과
    /// 같은 수준이라 별도 캐싱 레이어까지는 두지 않았다.
    private var searchVerseQueryMatches: [BibleReferenceExtractor.Match] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return BibleReferenceExtractor.extract(from: trimmed)
    }

    private func matchesCategoryFilter(_ document: SourceDocument) -> Bool {
        switch categoryFilter {
        case .all:
            return true
        case .uncategorized:
            return document.relatedChapterRef == nil && document.category == nil
        case .chapter(let ref):
            return document.relatedChapterRef == ref
        case .custom(let id):
            return document.category?.id == id
        }
    }

    /// 탭한 문서를 맨 앞으로 오도록 검수 대기 문서 목록을 회전시켜 큐를 만든다 —
    /// 목록 순서 자체는 그대로 유지하되(최근 업로드순), 사용자가 탭한 문서부터
    /// 시작해서 나머지 대기 문서를 이어서 보여주는 것이 "저장 후 다음" 취지에
    /// 맞다고 판단했다.
    private func presentOCRReviewQueue(startingAt document: SourceDocument) {
        guard let viewModel else { return }
        let pending = queriedDocuments.filter { viewModel.hasPendingOCRReview($0) }
        guard let startIndex = pending.firstIndex(where: { $0.persistentModelID == document.persistentModelID }) else {
            ocrReviewQueue = [document]
            return
        }
        ocrReviewQueue = Array(pending[startIndex...]) + Array(pending[..<startIndex])
    }

    // MARK: - 드롭존(진입점 2, 3)

    private func dropZone(viewModel: DocumentsViewModel) -> some View {
        // [2026-09-10 수정] 사용자 보고 — 2건.
        // ① "[문서 OCR]의 [탭해서 업로드] 이 영역이 화면의 1/3을 차지할 만큼
        // 클 필요가 없음." 아이콘 크기(28→18)·줄 간격(8→4)·위아래 여백
        // (24→10, 아래 `.padding(.vertical)` 참고)을 줄여 전체 높이를
        // 줄였다 — 안내 문구 3줄은 그대로 다 남긴다(정보 삭제 없이 여백만
        // 줄이는 쪽을 택했다).
        // ② "해당 폰트색이 어두운 회색?으로 고정되어있으므로 어두운
        // 배경에는 거의 보이지 않음." `.secondary`/`.tertiary`는 시스템
        // 라이트/다크 모드에만 맞춰진 색이라, 이 앱이 별도로 입히는 임의의
        // 테마 배경(`settings.bibleBackgroundColor`)은 전혀 고려하지
        // 않는다 — 이미 배경과 대비되도록 사용자가 고른 `bibleTextColor`를
        // 옅게 써서 항상 배경과 대비되게 하고, 테마를 고르지 않았으면(nil)
        // 원래 색(`Color.secondary`/`.tertiary`)을 그대로 쓴다. 마지막
        // 줄(캡션)은 원래 `.tertiary`가 `Color`가 아니라 `ShapeStyle`이라
        // `??`로 바로 폴백할 수 없어 `AnyShapeStyle`로 두 갈래를 하나의
        // 타입으로 묶었다.
        VStack(spacing: 4) {
            Image(systemName: "arrow.up.doc")
                .font(.system(size: 18))
                .foregroundStyle(settings.bibleTextColor?.opacity(0.7) ?? Color.secondary)
            // 진입점 3: 드롭존 클릭 — 같은 fileImporter를 그대로 연다.
            Text(allowsDragAndDrop ? "드래그해서 파일을 놓거나 클릭해서 업로드" : "탭해서 업로드")
                .font(.callout)
                .foregroundStyle(settings.bibleTextColor?.opacity(0.85) ?? Color.secondary)
            // [2026-08-28 수정, 아이폰도 동일하게 적용] 사용자 요청 —
            // "macOS 연구문서 업로드 영역에 doc 문구 삭제" → 이어서 "동일하게
            // 수정"(아이폰 쪽도 빼 달라는 확인). `.doc`/`.docx` 업로드는 이미
            // 2026-08-25에 막았는데(`DocumentUploadService.supportedContentTypes
            // (allowHWP:)` 상단 주석 참고) 이 안내 문구는 그때 갱신되지 않아
            // "doc"이 여전히 지원 형식인 것처럼 보였다 — 두 분기 모두에서 뺀다.
            Text(allowsHWP ? "hwp · hwpx · pdf · 이미지" : "pdf · 이미지 (아이폰은 hwp 업로드 미지원)")
                .font(.caption2)
                .foregroundStyle(settings.bibleTextColor.map { AnyShapeStyle($0.opacity(0.55)) } ?? AnyShapeStyle(.tertiary))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                // [2026-09-11 수정] 사용자 보고 — "파일 업로드 영역의
                // 점선 테두리"가 테마를 안 따름. 같은 드롭존의 아이콘/
                // 문구는 2026-09-10에 이미 `settings.bibleTextColor`
                // 폴백으로 고쳤는데 이 점선 테두리만 그때 빠졌다 — 같은
                // 패턴으로 마저 맞춘다.
                .foregroundStyle(isDropTargeted ? Color("AccentColor") : (settings.bibleTextColor?.opacity(0.4) ?? Color.secondary.opacity(0.4)))
        )
        .contentShape(Rectangle())
        .onTapGesture { isFileImporterPresented = true }
        .modifier(DropZoneModifier(isEnabled: allowsDragAndDrop, isTargeted: $isDropTargeted) { url in
            beginUpload(urls: [url])
        })
    }

    private func setUpIfNeeded() {
        guard viewModel == nil else { return }
        let vm = DocumentsViewModel(modelContext: modelContext)
        vm.onAppear()
        viewModel = vm
    }

    // MARK: - 업로드 시 관련 성경 장 입력 (2026-08-08 추가)

    /// 업로드 3가지 진입점이 공통으로 호출 — 곧바로 업로드하지 않고 확인 시트를
    /// 띄운다. 시트의 책/장 선택 기본값은 "지금 성경 조회(S1)에서 보고 있던
    /// 위치"(`LastBiblePositionTracker`)로 맞춰 둔다 — 대부분 문서를 올릴 때
    /// 방금 읽던 본문과 관련이 있을 가능성이 높다는 가정.
    private func beginUpload(urls: [URL]) {
        guard !urls.isEmpty else { return }
        if let bookId = LastBiblePositionTracker.shared.bookId, let book = BooksProvider.shared.book(id: bookId) {
            chapterLinkBook = book
            chapterLinkChapter = LastBiblePositionTracker.shared.chapter ?? 1
        }
        // [2026-08-18 추가] 이전 업로드 배치에서 고른 카테고리가 이번 배치로
        // 새어 들어가지 않도록 매번 초기화 — 시트가 다시 뜰 때마다 새로 골라야
        // 한다(카테고리 강제 요청 취지 그대로).
        pendingUploadCategory = nil
        pendingUploadURLs = urls
    }

    private func finishPendingUpload(relatedChapter: BibleChapterRef?) {
        let urls = pendingUploadURLs
        let category = pendingUploadCategory
        pendingUploadURLs = []
        pendingUploadCategory = nil
        viewModel?.upload(urls: urls, relatedChapter: relatedChapter, category: category)
    }
}

#if os(macOS)
/// [2026-09-11 신설] `categoryManagerPanel`(위, 맥OS 전용 Inspector)의 목록
/// 행 — 이름 변경 전용 인라인 편집. `DocumentRowView.categoryMenu`의 "새
/// 분류…" 알림창과 달리, 여기는 이미 있는 카테고리 하나의 이름을 직접
/// 고치는 자리라 텍스트 필드를 그대로 노출해 뒀다(별도 시트/알림 없이 포커스를
/// 잃거나 Return을 누르면 즉시 저장 — 목록형 관리 화면에 흔한 패턴).
private struct CategoryManagerRow: View {
    let category: ImageCategory
    let viewModel: DocumentsViewModel
    @State private var name: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("카테고리 이름", text: $name)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .onAppear { name = category.name }
            .onSubmit { commit() }
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
    }

    private func commit() {
        viewModel.renameCategory(category, to: name)
    }
}
#endif

/// [2026-08-08 추가, 2026-08-18 카테고리 강제 추가] 업로드 확인 시트 — "이
/// 문서(들)는 어느 장과 관련 있는지"를 물어본다. 관련 성경 장 자체는 여전히
/// 선택 사항이라 "건너뛰기"로 바로 업로드할 수 있다(사용자 요청 자체가 "입력받을
/// 수 있도록"이지 "반드시 입력해야"가 아니었음). 반면 카테고리는 사용자 요청 —
/// "연구문서 업로드시 반드시 카테고리 입력을 강제할 것. (선택하거나 개인이
/// 입력하거나)" — 에 따라 두 경로(건너뛰기/이 장으로 업로드) 모두 카테고리를
/// 고르기 전에는 버튼을 누를 수 없다.
private struct UploadChapterLinkSheet: View {
    @Binding var book: Book
    @Binding var chapter: Int
    let fileCount: Int
    /// [2026-08-18 추가] 기존에 만들어 둔 카테고리 목록 — `DocumentRowView.
    /// categoryMenu`와 같은 Menu 구성(기존 분류 선택 + "새 분류…")을 그대로
    /// 재사용한다.
    let categories: [ImageCategory]
    @Binding var selectedCategory: ImageCategory?
    /// [2026-08-18 추가] "새 분류…" 입력을 실제 `ImageCategory`로 만드는 동작 —
    /// 이 시트는 `DocumentsViewModel`을 직접 모르므로(부모가 옵셔널 바인딩으로만
    /// 들고 있음, 다른 화면들의 리졸버 클로저 주입 패턴과 동일) 부모가 만든
    /// 클로저를 그대로 받는다.
    let onCreateCategory: (String) -> ImageCategory?
    let onSkip: () -> Void
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isNewCategoryInputPresented = false
    @State private var newCategoryName = ""

    var body: some View {
        NavigationStack {
            // [2026-08-15 2차 UI/UX 수정] 사용자 재보고 — 이전 `.formStyle(.grouped)`
            // 적용 후에도 검색어 입력창의 placeholder("예:창세기1, 요3")가 실제
            // 입력 상자 안이 아니라 옆으로 밀려나 별도 글자처럼 보였다. 근본 원인 —
            // `Form`/`Section` 행(row) 레이아웃이 자체적으로 자식 컨트롤(특히
            // `.textFieldStyle(.roundedBorder)`처럼 스타일을 직접 지정한 TextField)의
            // 크기를 다시 계산하려 들면서, 안에 있던 `BookChapterPicker`의 좁은
            // `HStack`(버튼+검색창+버튼)과 충돌해 검색창의 실제 레이아웃 폭이
            // placeholder 글자 너비보다 작게 줄어들었다 — 그래서 placeholder
            // 텍스트가 그 좁은 상자 밖으로 삐져나와 보인 것이다(SwiftUI는 기본적으로
            // 넘치는 텍스트를 잘라내지 않는다). `Form` 자체를 걷어내고 일반
            // `VStack`으로 바꿔 이 행 크기 재계산 충돌을 원천적으로 없앴다 —
            // `BookChapterPicker`가 원래 문제없이 쓰이는 다른 화면(성경 조회 상단
            // 툴바)도 전부 `Form` 밖이라는 점과 일치한다.
            VStack(alignment: .leading, spacing: 16) {
                // [2026-08-18 추가] 사용자 요청 — "연구문서 업로드시 반드시
                // 카테고리 입력을 강제할 것. (선택하거나 개인이 입력하거나)."
                // 이 시트에서 가장 먼저 채워야 하는 항목이라 관련 성경 장보다
                // 위에 둔다.
                VStack(alignment: .leading, spacing: 4) {
                    Text("카테고리").font(.body).foregroundStyle(.secondary)
                    Menu {
                        ForEach(categories) { category in
                            Button(category.name) { selectedCategory = category }
                        }
                        if !categories.isEmpty { Divider() }
                        Button("새 분류…") { isNewCategoryInputPresented = true }
                    } label: {
                        HStack {
                            Text(selectedCategory?.name ?? "카테고리를 선택하세요")
                                .foregroundStyle(selectedCategory == nil ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .font(.body)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
                    }
                    .menuStyle(.borderlessButton)
                }

                Divider()

                BookChapterPicker(
                    books: BooksProvider.shared.books,
                    selectedBook: book,
                    selectedChapter: chapter
                ) { newBook, newChapter in
                    book = newBook
                    chapter = newChapter
                }

                // [2026-08-15 2차 UI/UX 수정] 사용자 요청 — "하단 설명문구 - 시스템
                // 기본 폰트, 일반 크기로." `RootView`의 `.appDefaultFont()`(커스텀
                // Paperlogy)를 명시적으로 `.font(.body)`로 되돌린다.
                Text("업로드할 파일 \(fileCount)개와 관련된 성경 장을 지정하면, 성경 조회(S1) 화면에서 이 문서를 바로 찾아볼 수 있습니다. 나중에 문서 목록에서 다시 바꾸거나 해제할 수 있습니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("관련 성경 장")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // [2026-08-18 수정] 카테고리를 고르기 전엔 "건너뛰기"도 막는다
                    // — "건너뛰기"는 관련 성경 장만 생략하는 버튼이지, 카테고리
                    // 강제 자체를 우회하는 경로가 아니다.
                    Button("건너뛰기") {
                        onSkip()
                        dismiss()
                    }
                    .disabled(selectedCategory == nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("이 장으로 업로드") {
                        onConfirm()
                        dismiss()
                    }
                    .disabled(selectedCategory == nil)
                }
            }
            // [2026-08-18 추가] `DocumentRowView.categoryMenu`와 같은 패턴 —
            // "새 분류…" 선택 시 이름을 입력받아 `onCreateCategory`로 실제
            // `ImageCategory`를 만들고 곧바로 선택 상태로 반영한다.
            .alert("새 분류", isPresented: $isNewCategoryInputPresented) {
                TextField("분류 이름", text: $newCategoryName)
                Button("취소", role: .cancel) { newCategoryName = "" }
                Button("추가") {
                    if let category = onCreateCategory(newCategoryName) {
                        selectedCategory = category
                    }
                    newCategoryName = ""
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 320)
        #endif
    }
}

/// macOS/iPadOS에서만 `.onDrop`을 실제로 붙이고, 아이폰(드래그앤드롭 OS 미지원)에서는
/// 아무것도 하지 않는 조건부 modifier. `allowsDragAndDrop`으로 매번 분기 코드를
/// 반복하지 않기 위해 분리했다.
private struct DropZoneModifier: ViewModifier {
    let isEnabled: Bool
    @Binding var isTargeted: Bool
    let onURL: (URL) -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in
                            onURL(url)
                        }
                    }
                }
                return true
            }
        } else {
            content
        }
    }
}

// MARK: - 목록 행

private struct DocumentRowView: View {
    // [2026-09-11 추가, 컴파일 오류 수정] 아래 `accentSpineColor`가 쓰는
    // `settings` — `DocumentsHomeView`(181번 줄)와 같은 패턴, 이 struct엔
    // 아직 없었다.
    private var settings: UserSettingsStore { .shared }
    let document: SourceDocument
    /// [2026-08-17 추가, 이후 성경장절 검색까지 포함하도록 확장] 사용자 요청
    /// — "검색결과 일치하는 텍스트는 형광펜 강조처리." + "성경장절 검색시
    /// 검색에 관련된 연구문서의 성경 장절은 형광펜강조(범위에 포함된 성경구절인
    /// 경우 범위 텍스트를 강조) 예) 창1:3으로 검색 -> 창1:1-5 의 텍스트 강조가
    /// 되어야 함." 타이핑한 검색어뿐 아니라, 부모(`searchScore`)가
    /// `VerseMention`으로 풀어낸 실제 문서 내 성경장절 원문("창1:1-5" 등)도
    /// 함께 담긴다. 검색 중이 아니면(빈 배열) 하이라이트 없이 평범한 텍스트로
    /// 보인다 — `highlightedText(_:keywords:)` 참고.
    let highlightKeywords: [String]
    /// [2026-08-17 추가, 세 차례 형식 변경] 사용자 요청 — "본문 일치는 파일명
    /// 하단에 일치하는 단어 기준 그 라인을 표시할 것" → "일치 단어 뒤 10자
    /// 미만, ...으로 구분, 70자 이내, 일치개수 표시" → "(xx 회 일치)는 조각별
    /// 개수의 합" → "각 문자열 뒤 (xx) 숫자는 지울것." 최종 형태 — 단어별
    /// 개수 표기 없는 순수 발췌문("태초에 하나 ... 창조하시니라")만 담는다.
    /// 본문에서 걸리지 않았으면 nil.
    let bodyExcerpt: String?
    /// "(xx 회 일치)" 접두어에 쓰는 숫자 — 본문에서 검색단어들이 총 몇 번
    /// 등장했는지(부모 `DocumentsHomeView.searchScore`가 계산). `bodyExcerpt`가
    /// nil이면(본문 매치 자체가 없으면) 이 값은 안 쓰인다.
    let bodyOccurrenceSum: Int
    /// [2026-08-17 추가] 사용자 요청 — "태그가 일치가 되면 (xx 회 일치) 뒤
    /// 본문 앞에 태그명을 뱃지형식으로 보여줄것." 실제로 검색어와 일치한 태그
    /// 이름들 — 비어 있으면 뱃지를 그리지 않는다.
    let matchedTagNames: [String]
    let viewModel: DocumentsViewModel
    /// [2026-08-07 추가] 검수 대기 중인 문서를 탭했을 때 부모(DocumentsHomeView)에게
    /// "이 문서부터 시작하는 검수 큐를 열어 달라"고 알린다.
    let onOpenOCRReview: (SourceDocument) -> Void

    @Environment(\.openWindow) private var openWindow
    // [2026-09-11 추가] 사용자 재검토 요청 — 아래 문서 행 강조선이 다크
    // 배경(특히 "밤빛 서재" 테마, navy와 배경이 같은 색)에서 거의 안 보이는
    // 문제(대비 실측 1.00:1)를 고치기 위한 환경값. `colorScheme`은 테마
    // 배경을 안 골랐을 때(nil)의 시스템 기본값 판정용, `environment`는
    // `Color.resolve(in:)`으로 실제 테마 배경의 밝기를 재는 용도 —
    // `ThemedNavigationBarBackgroundModifier.isDarkBackground`와 같은 공식.
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment

    /// [2026-09-11 추가] 위 두 환경값으로 "지금 실제로 보이는 배경이
    /// 어두운지"를 판정해 강조선 색을 고른다 — 테마 배경이 있으면 그 배경의
    /// WCAG 상대휘도(`ThemedNavigationBarBackgroundModifier.isDarkBackground`와
    /// 완전히 같은 공식, 그 struct는 private라 직접 재사용은 못 해 같은
    /// 공식만 옮겨 왔다)로, 없으면 시스템 라이트/다크로 판정한다.
    private var accentSpineColor: Color {
        let isDark: Bool
        if let bg = settings.bibleBackgroundColor {
            let resolved = bg.resolve(in: environment)
            let luminance = 0.2126 * Double(resolved.red) + 0.7152 * Double(resolved.green) + 0.0722 * Double(resolved.blue)
            isDark = luminance < 0.5
        } else {
            isDark = colorScheme == .dark
        }
        return isDark ? JBCHCategoryPalette.navyOnDark : JBCHCategoryPalette.navy
    }
    @State private var isCategoryInputPresented = false
    @State private var categoryInput = ""
    /// [2026-09-11 신설] 사용자 요청 — 문서 하나의 정보(카테고리/관련 성경장
    /// 편집 포함)를 보여주는 팝오버(`documentInfoPopover`) 표시 여부 — 아래
    /// `.contextMenu`의 "문서 정보" 항목에서 켠다.
    @State private var isInfoPopoverPresented = false
    /// [2026-08-08 추가] 업로드 시 건너뛰었거나 나중에 바꾸고 싶을 때 쓰는 편집
    /// 시트 상태. `chapterLinkBook`은 시트를 열 때 `document.relatedChapterRef`
    /// (있으면) 또는 마지막으로 보던 성경 위치(없으면)로 채운다.
    @State private var isChapterLinkEditorPresented = false
    @State private var chapterLinkBook: Book = BooksProvider.shared.books.first
        ?? Book(bookId: 1, testament: .old, orderIndex: 1, nameKo: "창세기", nameOriginal: "Genesis", abbreviation: ["창"], chapterCount: 50)
    @State private var chapterLinkChapter: Int = 1

    /// [2026-08-18 신설] `allowsDragAndDrop`/`allowsHWP`와 같은 패턴 —
    /// `UIDevice`는 iOS에서만 존재하므로 반드시 `#if os(iOS)`로 감싼다(맥 빌드
    /// 깨짐 방지). 아이폰만 다중 씬(멀티 윈도우)을 지원하지 않아 `openWindow`
    /// 대신 `NavigationLink`로 이 탭의 NavigationStack 안에 밀어 넣어야 한다 —
    /// 맥/아이패드는 기존 `openWindow` 그대로.
    private var isPhoneIdiom: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    var body: some View {
        // [2026-08-15 추가, 크래시 fix] 사용자 보고 — `SourceDocument.conversionStatus.getter`
        // fatal error(`DocumentRowView.statusBadge.getter`에서 발생, 이 행의
        // `document`가 이미 지워진 객체를 가리키고 있었다). `List(queriedDocuments)`
        // (DocumentsHomeView 상단 `@Query` 참고)가 이미 "지워진 문서는 배열에서
        // 빠진다"를 보장하는데도 이 크래시가 남아 있었다는 건, SwiftUI가 배열
        // 변경을 반영해 이 행을 트리에서 완전히 제거하기 "직전"의 한 프레임 동안
        // 이 `DocumentRowView` 인스턴스(그리고 그 안에 값으로 박혀 있는 옛
        // `document` 참조)가 다른 이유로(예: 같은 화면의 다른 상태 변화, 다른
        // 창에서의 삭제) 한 번 더 재계산될 수 있다는 뜻이다 — `@Query`로도 완전히
        // 막지 못하는, 한 프레임짜리 경쟁 상태(race)다.
        //
        // `PersistentModel.modelContext`는 사용자가 선언한 `@Model` 저장
        // 프로퍼티(`conversionStatus` 등)와 달리 SwiftData 프레임워크가 직접
        // 관리하는 "이 객체가 지금 어떤 컨텍스트에 속해 있는지" 플래그다 — 객체가
        // 컨텍스트에서 지워지고 저장되면 nil이 된다. 이 값 자체를 읽는 것은
        // (다른 저장 프로퍼티와 달리) 지워진 객체에서도 안전하다 — 정확히 "이
        // 객체를 더 건드려도 되는지" 사전 검사 용도로 Apple이 제공하는 것이다.
        // 그래서 다른 프로퍼티(`originalFilename`, `conversionStatus` 등)를 읽기
        // 전에 이걸로 먼저 걸러낸다.
        if document.modelContext == nil {
            EmptyView()
        } else {
            documentRow
        }
    }

    @ViewBuilder
    private var documentRow: some View {
        // [2026-08-07 수정] 이전엔 NavigationLink 하나가 검수 대기/일반 문서 둘 다
        // 같은 방식(메인 창 안 푸시)으로 열었다. 이제 둘의 진입 방식 자체가
        // 다르다 — 검수 대기는 시트+큐(S7), 그 외엔 별도 창(S6, Preview.app
        // 패턴) — 그래서 NavigationLink 대신 분기하는 Button 하나로 바꿨다.
        //
        // [2026-08-18 추가, 실기기 크래시 fix] 사용자 보고 — 아이폰 실기기에서
        // "Unable to open a window when the app does not support multiple
        // scenes" 런타임 에러. 원인 — 아이패드/맥과 달리 아이폰은 다중
        // 씬(멀티 윈도우)을 지원하지 않아 `openWindow`가 새 창을 못 연다(S6
        // 도입 당시 README에 "실기기 검증 필요"로 이미 위험 표시해 둔
        // 부분). 그래서 아이폰에서만 `openWindow` 대신 이 탭의 NavigationStack
        // 안으로 `NavigationLink(value:)`로 밀어 넣는다 — `.navigationDestination
        // (for: PersistentIdentifier.self)`는 이 파일 하단에 등록.
        Group {
            if viewModel.hasPendingOCRReview(document) {
                Button {
                    onOpenOCRReview(document)
                } label: {
                    documentRowLabel
                }
            } else if isPhoneIdiom {
                NavigationLink(value: document.persistentModelID) {
                    documentRowLabel
                }
            } else {
                Button {
                    openWindow(id: "document-viewer", value: document.persistentModelID)
                } label: {
                    documentRowLabel
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            // [2026-09-11 신설] 사용자 요청 — 문서 하나의 정보(카테고리/관련
            // 성경장 편집 포함)를 "길게 프레스(아이패드)/마우스 오른쪽 버튼
            // (맥)"으로 여는 팝오버로 보여준다 — `.contextMenu`는 이미 이 두
            // 플랫폼 제스처를 그대로 발행해 주므로 새 제스처 인식기가 따로
            // 필요 없다. 아래 `.popover` 참고.
            Button {
                isInfoPopoverPresented = true
            } label: {
                Label("문서 정보", systemImage: "info.circle")
            }
            Divider()
            if document.conversionStatus == .failedNeedsManual {
                Button {
                    viewModel.retry(document)
                } label: {
                    Label("재시도", systemImage: "arrow.clockwise")
                }
            }
            // [2026-08-08 추가] 업로드 시 건너뛰었거나 잘못 골랐을 때를 위한
            // 재설정 경로 — categoryMenu(이미지 분류)와 같은 위치 원칙.
            Button {
                presentChapterLinkEditor()
            } label: {
                Label(
                    document.relatedChapterRef == nil ? "관련 성경 장 설정…" : "관련 성경 장 변경…",
                    systemImage: "book.closed"
                )
            }
            if document.relatedChapterRef != nil {
                Button(role: .destructive) {
                    viewModel.setRelatedChapter(nil, for: document)
                } label: {
                    Label("관련 성경 장 해제", systemImage: "book.closed")
                }
            }
            // [2026-08-18 추가] 사용자 요청 — "사이드바 메뉴 밑으로 클로드 앱처럼
            // 기능을 추가할 것. 고정됨." 사이드바 "고정됨" 섹션에 넣고 뺄 수 있는
            // 토글 — `categoryMenu`/관련 성경 장 재설정과 같은 위치 원칙(컨텍스트
            // 메뉴에서 이산적 액션으로 즉시 반영).
            Button {
                viewModel.togglePin(document)
            } label: {
                Label(document.isPinned ? "고정 해제" : "고정", systemImage: document.isPinned ? "pin.slash" : "pin")
            }
            Button(role: .destructive) {
                viewModel.delete(document)
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
        .sheet(isPresented: $isChapterLinkEditorPresented) {
            ChapterLinkEditorSheet(
                book: $chapterLinkBook,
                chapter: $chapterLinkChapter,
                onSave: {
                    viewModel.setRelatedChapter(BibleChapterRef(bookId: chapterLinkBook.bookId, chapter: chapterLinkChapter), for: document)
                }
            )
        }
        .popover(isPresented: $isInfoPopoverPresented) {
            documentInfoPopover
        }
    }

    /// [2026-08-18 신설] `documentRow`의 Button/NavigationLink 두 경로가 같은
    /// 라벨을 쓰도록 분리 — 위 iPhone 런타임 크래시 fix에서 라벨 중복을
    /// 피하려고 뺐다.
    private var documentRowLabel: some View {
        // [2026-09-04 신설] 사용자 요청 — "07. 배경이 흐린 회색으로 보임 —
        // 책등 강조선." 목록 전체가 시스템 기본 배경 그대로라 지금 누르고
        // 있는 행 말고는 이 앱만의 색이 전혀 안 보인다는 지적에, 가이드
        // artifact의 "① 책등 강조선" 안을 적용한다 — 카드 배경 자체를
        // 바꾸지 않고(라이트/다크 모드 배경은 그대로 시스템 기본) 왼쪽
        // 모서리에 3pt 남색 세로선만 더해, 제본된 책의 책등처럼 보이게 한다.
        // `TranslationColumnView.VerseRow`의 선택 강조선(`RoundedRectangle
        // ().fill(Color("AccentColor")).frame(width: 3)`)과 같은, 이미 검증된
        // 패턴을 그대로 재사용했다 — 배경 자체를 바꾸는 "② 책장 아이보리
        // 카드"는 라이트/다크 모드 양쪽에서 실제로 보기 좋은지 이 세션(Xcode
        // 없음)에서 눈으로 확인할 수 없어, 실기기 확인 없이 넣기엔 위험이
        // 크다고 판단해 이번엔 넣지 않았다 — 필요하시면 실기기로 같이
        // 확인하며 추가하겠다.
        HStack {
                Image(systemName: formatIcon)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    // [2026-08-17 수정, 2026-08-18 성경장절 강조까지 확장] 사용자
                    // 요청 — "검색결과 일치하는 텍스트는 형광펜 강조처리." 검색
                    // 중이 아니면(highlightKeywords 비어 있음) highlightedText가
                    // 그냥 평범한 Text를 돌려줘 기존과 동일하다.
                    highlightedText(document.originalFilename, keywords: highlightKeywords)
                    HStack(spacing: 4) {
                        Text(document.originalFormat.rawValue.uppercased())
                        // [2026-08-08 추가] 관련 성경 장이 설정돼 있으면 목록에서도
                        // 바로 보이게 — 안 그러면 문서가 몇 개만 있어도 어떤 게
                        // 어느 장과 연결됐는지 매번 컨텍스트 메뉴를 열어봐야 한다.
                        if let label = relatedChapterLabel {
                            Text("· \(label)")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    // [2026-08-17 추가, 세 차례 형식 변경] 사용자 요청 — "본문
                    // 일치는 파일명 하단에 ... 표시" → 단어별 발췌+개수+70자
                    // 캡 → "(xx 회 일치)는 조각 개수 합" → "각 조각 뒤 (xx)는
                    // 지우고" → "태그 일치 시 (xx 회 일치) 뒤 본문 앞에 태그명
                    // 뱃지." 최종 레이아웃: "(N회 일치)" 텍스트 + (태그 일치
                    // 시) 태그 뱃지들 + 발췌 본문(하이라이트) 순서로 한 줄에
                    // 나열한다. 본문 매치가 아예 없으면(bodyExcerpt == nil)
                    // 이 줄 자체를 그리지 않는다 — 태그만 일치하고 본문은
                    // 안 걸린 경우는 뱃지를 보여줄 자리가 없어 표시하지 않는다
                    // (요청 문구가 "(xx 회 일치) 뒤 본문 앞에"라 본문 줄의
                    // 존재를 전제하고 있다고 해석했다).
                    if let bodyExcerpt {
                        HStack(spacing: 4) {
                            Text("(\(bodyOccurrenceSum)회 일치)")
                            ForEach(matchedTagNames, id: \.self) { tagName in
                                badge(tagName, color: Self.tagBadgeBlue)
                            }
                            highlightedText(bodyExcerpt, keywords: highlightKeywords)
                                .lineLimit(2)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // [2026-08-16 수정] 사용자 요청 — "카테고리 기능 추가할 것."
                // 원래는 이미지(OCR 분류, 6.4)에서만 커스텀 카테고리를 붙일 수
                // 있었다 — 이제 모든 형식에 다 허용한다(관련 성경 장과는 별개
                // 필드라 둘 다 붙여도 된다 — 예: "창세기 1장" + "설교 자료").
                categoryMenu

                statusBadge
            }
        .padding(.vertical, 4)
        .padding(.leading, 10)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(accentSpineColor)
                .frame(width: 3)
                .padding(.vertical, 3)
        }
    }

    /// 컨텍스트 메뉴에서 시트를 열 때 기본값을 채운다 — 이미 연결돼 있으면 그
    /// 값, 없으면 마지막으로 보던 성경 위치(업로드 시트와 같은 원칙).
    private func presentChapterLinkEditor() {
        if let ref = document.relatedChapterRef, let book = BooksProvider.shared.book(id: ref.bookId) {
            chapterLinkBook = book
            chapterLinkChapter = ref.chapter
        } else if let bookId = LastBiblePositionTracker.shared.bookId, let book = BooksProvider.shared.book(id: bookId) {
            chapterLinkBook = book
            chapterLinkChapter = LastBiblePositionTracker.shared.chapter ?? 1
        }
        isChapterLinkEditorPresented = true
    }

    private var relatedChapterLabel: String? {
        guard let ref = document.relatedChapterRef, let book = BooksProvider.shared.book(id: ref.bookId) else { return nil }
        return "\(book.nameKo) \(ref.chapter)장"
    }

    /// [2026-08-17 신설] 사용자 요청 — "검색결과 일치하는 텍스트는 형광펜
    /// 강조처리." `text` 안에서 `keywords`(검색단어들) 중 하나라도 대소문자
    /// 구분 없이 나타나는 모든 구간에 노란 배경(형광펜 느낌)을 입힌다.
    ///
    /// ⚠️ [구현 선택] `text.range(of:options:.caseInsensitive)`를 원본
    /// `text`(같은 String 인스턴스) 위에서 그대로 반복 탐색한다 — 처음엔
    /// 별도로 `text.lowercased()`를 만들어 그 위에서 찾는 방식을 생각했지만,
    /// `lowercased()`가 만든 새 String은 `String.Index`가 원본과 호환된다는
    /// 보장이 없어(글자 수가 같아 보여도 다른 String 인스턴스의 인덱스는
    /// 서로 바꿔 쓸 수 없다) 안전하지 않다. `.caseInsensitive` 옵션을 쓰면
    /// 원본 문자열 위에서 바로 대소문자 무시 검색이 되므로 이 문제 자체가
    /// 생기지 않는다.
    private func highlightedText(_ text: String, keywords: [String]) -> Text {
        let trimmedKeywords = keywords.filter { !$0.isEmpty }
        guard !trimmedKeywords.isEmpty else { return Text(text) }

        var attributed = AttributedString(text)
        for keyword in trimmedKeywords {
            var searchRange = text.startIndex..<text.endIndex
            while let found = text.range(of: keyword, options: [.caseInsensitive], range: searchRange) {
                if let attrRange = Range(found, in: attributed) {
                    attributed[attrRange].backgroundColor = .yellow.opacity(0.55)
                }
                searchRange = found.upperBound..<text.endIndex
            }
        }
        return Text(attributed)
    }

    private var formatIcon: String {
        switch document.originalFormat {
        case .pdf: return "doc.richtext"
        case .image: return "photo"
        case .hwp, .hwpx: return "doc.text"
        case .doc, .docx, .pages: return "doc" // [2026-08-16 docx/pages 추가] .doc과 같은 아이콘 재사용
        }
    }

    // MARK: - 상태 배지(14.5 시맨틱 색상: 대기/추출중=주황, 완료=초록, 실패=빨강)

    // [2026-09-04 수정] 사용자 요청 — "08. 채도만 살짝 낮추도록." 완료(성공)/
    // 대기·진행(주황)/실패(빨강)라는 상태 신호 자체(색의 의미)는 그대로 두고,
    // iOS 기본 순색(`.orange`/`.green`/`.red`) 대신 채도를 낮춘 톤으로만
    // 바꿨다 — 화면 전체의 차분한 톤(서재 금박·밤빛 남색 등)과 어우러지게
    // 하면서도, 성공=초록/진행=주황/실패=빨강이라는 구분 자체는 그대로라
    // 상태 판별성은 잃지 않는다. `JBCHCategoryPalette`(항목 구분용)와는
    // 성격이 달라(이건 상태 신호) 그 파일에 넣지 않고 여기 따로 둔다.
    private static let statusAmber = Color(hex: "#B36A2E") ?? .orange
    private static let statusGreen = Color(hex: "#5E8C5B") ?? .green
    private static let statusRed = Color(hex: "#A6483C") ?? .red

    // [2026-09-11 추가] 사용자 재검토 요청 — `JBCHCategoryPalette.swift`
    // 주석이 예고한 "참조 일치·태그 배지(초록/파랑) 채도 낮추기, 별도 커밋"이
    // 실제로는 반영 안 돼 있었다. 위 상태 배지와 같은 "채도만 낮추기" 원칙 —
    // 대비 실측(로컬 계산): 라이트 4.51~5.11:1, 다크 2.94~3.33:1로 이미 쓰고
    // 있는 statusRed(다크 2.58~2.93:1)보다 낫다.
    private static let tagBadgeBlue = Color(hex: "#4A6FA5") ?? .blue

    @ViewBuilder
    private var statusBadge: some View {
        if viewModel.hasPendingOCRReview(document) {
            badge("검수 대기", color: Self.statusAmber)
        } else {
            switch document.conversionStatus {
            case .pending:
                badge("대기", color: Self.statusAmber)
            case .convertingNative:
                badge("추출 중", color: Self.statusAmber)
            case .converted:
                // [2026-09-11 수정] 사용자 요청 — "인덱싱 완료 뱃지는
                // 불필요함. 인덱싱이 안되었을 때 처리를 하는 것이 낫고,
                // 인덱싱 완료가 일반적인 상황이므로 굳이 뱃지를 붙일 필요가
                // 없음." 완료 상태는 더 이상 뱃지를 그리지 않고, 아직 안 된
                // 경우(예외적 상황)만 계속 보여준다.
                if document.indexStatus == .indexed {
                    EmptyView()
                } else {
                    badge("추출 중", color: Self.statusAmber)
                }
            case .failedNeedsManual:
                badge("실패", color: Self.statusRed)
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - 카테고리(원래 6.4 이미지 분류였다가, 2026-08-16 모든 형식으로 확장)

    private var categoryMenu: some View {
        Menu {
            Button("미분류") { viewModel.setCategory(nil, for: document) }
            ForEach(viewModel.categories) { category in
                Button(category.name) { viewModel.setCategory(category, for: document) }
            }
            Divider()
            Button("새 분류…") { isCategoryInputPresented = true }
        } label: {
            // [2026-09-11 변경] 사용자 재검토 요청 — "테마색상 팔레트 6개가
            // 실제로는 2~3톤처럼 보인다." 서가 슬레이트를 실제로 분류가
            // 지정된 문서의 라벨에 명시 배정한다. "미분류" 상태는 일부러
            // 색을 그대로 두어 — 칠하면 "이미 분류함"과 "아직 안 함"을
            // 구별하던 기존 신호가 사라진다.
            Group {
                if let categoryName = document.category?.name {
                    Text(categoryName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(JBCHCategoryPalette.shelfSlate, in: Capsule())
                        .overlay(
                            Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                        )
                } else {
                    Text("분류 없음")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .alert("새 분류", isPresented: $isCategoryInputPresented) {
            TextField("분류 이름", text: $categoryInput)
            Button("취소", role: .cancel) { categoryInput = "" }
            Button("추가") {
                if let category = viewModel.createCategory(named: categoryInput) {
                    viewModel.setCategory(category, for: document)
                }
                categoryInput = ""
            }
        }
    }

    /// [2026-09-11 신설] 사용자 요청 — 문서 정보 팝오버(위 `.contextMenu`의
    /// "문서 정보" 항목 참고). 카테고리는 기존 `categoryMenu`(바로 위)를 그대로
    /// 재사용하고, 관련 성경 장은 기존 `presentChapterLinkEditor()`/
    /// `ChapterLinkEditorSheet`(이미 이 struct에 있던 편집 경로, 컨텍스트
    /// 메뉴의 "관련 성경 장 설정…/변경…"과 완전히 같은 시트)를 그대로 연다 —
    /// 팝오버 안에 별도 Book/Chapter 피커를 새로 욱여넣지 않았다(좁은 팝오버
    /// 폭에 `BookChapterPicker`처럼 큰 화면을 그리는 건 실기기 검증 없이는
    /// 위험하다고 판단했다).
    private var documentInfoPopover: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(document.originalFilename)
                        .font(.headline)
                        .lineLimit(2)
                    Text(document.originalFormat.rawValue.uppercased())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
                LabeledContent("상태") {
                    Text(infoStatusText)
                }
                LabeledContent("카테고리") {
                    categoryMenu
                }
                LabeledContent("관련 성경 장") {
                    Button(relatedChapterLabel ?? "설정 안 됨") {
                        presentChapterLinkEditor()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
                if !infoTagNames.isEmpty {
                    LabeledContent("태그") {
                        Text(infoTagNames.joined(separator: ", "))
                    }
                }
                LabeledContent("업로드일") {
                    Text(document.uploadedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .padding()
        }
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 340, minHeight: 200, idealHeight: 320, maxHeight: 420)
    }

    /// [2026-09-11 신설, `searchScore(for:)`와 같은 접근] 태그 이름 목록(읽기전용).
    private var infoTagNames: [String] {
        (document.documentTags ?? []).compactMap { $0.tag?.name }
    }

    /// 위 `DocumentsHomeView.statusBadge`(같은 이름, 다른 struct)와 같은 판정
    /// 기준 — 다만 팝오버는 배지 스타일 없이 텍스트 한 줄로만 보여준다.
    private var infoStatusText: String {
        if viewModel.hasPendingOCRReview(document) { return "검수 대기" }
        switch document.conversionStatus {
        case .pending: return "대기"
        case .convertingNative: return "추출 중"
        case .converted: return document.indexStatus == .indexed ? "완료" : "추출 중"
        case .failedNeedsManual: return "실패"
        }
    }
}

/// [2026-08-08 추가] 문서 목록 행 컨텍스트 메뉴 "관련 성경 장 설정…/변경…"에서
/// 쓰는 편집 시트. 업로드 확인 시트(`UploadChapterLinkSheet`)와 달리 "건너뛰기"가
/// 없다 — 이미 업로드된 문서 하나를 다루는 것이라 "취소/저장"이 더 맞는 문구다.
private struct ChapterLinkEditorSheet: View {
    @Binding var book: Book
    @Binding var chapter: Int
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    /// [2026-09-11 신설] 사용자 보고 — "색상테마도 적용할 수 있도록." 이
    /// 시트는 지금까지 테마 적용 대상에서 빠져 있었다 — 다른 화면들과 같은
    /// 읽기 전용 접근 패턴.
    private var settings: UserSettingsStore { .shared }

    var body: some View {
        NavigationStack {
            // [2026-08-15 2차 UI/UX 수정] `UploadChapterLinkSheet`와 같은 이유(그
            // 파일 주석 참고) — `Form`/`Section` 행 레이아웃이 `BookChapterPicker`의
            // 검색창 placeholder를 상자 밖으로 밀어내는 문제가 있어 `Form` 자체를
            // 걷어내고 일반 `VStack`으로 바꿨다.
            VStack(alignment: .leading, spacing: 16) {
                BookChapterPicker(
                    books: BooksProvider.shared.books,
                    selectedBook: book,
                    selectedChapter: chapter
                ) { newBook, newChapter in
                    book = newBook
                    chapter = newChapter
                }
                Spacer(minLength: 0)
            }
            .padding()
            // [2026-09-11 신설] 위 `settings` 선언부 주석 참고 — `BookChapterPicker`
            // 의 "책 N장" 라벨은 자체 글자색이 없어(다른 화면들에서 이미
            // 반복된 것과 같은 이유 — 상속에만 기대는 `Text`/`Label`) 이
            // 배경색을 물려받는다("이동" 원형 버튼 안 흰 화살표처럼 이미
            // 자기 색을 정한 요소는 그대로 남는다 — 명시적 색이 항상
            // 상속보다 우선한다).
            .foregroundStyle(settings.bibleTextColor ?? Color.primary)
            .background(settings.bibleBackgroundColor ?? Color.clear)
            .navigationTitle("관련 성경 장")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        onSave()
                        dismiss()
                    }
                }
            }
            // [2026-09-11 신설] `DocumentsHomeView.body`가 자기 화면에 쓰는
            // 것과 같은 모디파이어(같은 파일이라 재사용 가능) — 실제
            // 시스템 내비게이션 바 배경까지 테마에 맞춘다(위 `.background()`
            // 는 그 아래 콘텐츠 영역만 칠한다).
            .modifier(ThemedNavigationBarBackgroundModifier(color: settings.bibleBackgroundColor))
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 260)
        #endif
        #if os(iOS)
        // [2026-09-11 신설] 사용자 보고 — "레이아웃 팝업이 컨텐츠에 비해
        // 너무 큼." 원인 — 이 시트의 실제 내용은 `BookChapterPicker`의
        // 한 줄짜리 `standardBody`(책/장 버튼 + 검색창 + 이동 버튼)뿐인데
        // (탭하면 열리는 책/장 그리드는 이 시트가 아니라 `BookChapterPicker`
        // 자신의 별도 `.popover`이고, 그쪽은 이미 `.frame(minWidth: 360,
        // minHeight: 460)`으로 스스로 크기를 잡는다), 지금까지 iOS 쪽엔
        // 위 macOS `.frame(minHeight: 260)`과 같은 제약이 전혀 없어 시스템
        // 기본 시트 크기(내용보다 훨씬 큼)로 떴다 — `BookmarkListPopover`가
        // 이미 쓰는 `.presentationDetents([.height(_:)])` 패턴을 그대로
        // 재사용해, macOS가 이미 쓰는 것과 같은 260을 시트 높이로 고정한다
        // (같은 콘텐츠라 새 값을 추측하지 않고 그대로 재사용했다).
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
        #endif
    }
}
