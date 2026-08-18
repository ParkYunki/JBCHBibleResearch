//
//  JBCHBibleResearchApp.swift
//  JBCHBibleResearch
//
//  Created by 박윤기 on 8/3/26.
//
//  이번 업데이트로 추가된 것:
//  - iCloud(CloudKit) 동기화 설정 (요구사항 2) — 실제로 켜지려면 Xcode의
//    Signing & Capabilities에서 iCloud capability를 추가하고 CloudKit 서비스를 켠 뒤,
//    Containers 목록에 컨테이너를 최소 1개 추가해야 한다(빈 목록이면 컨테이너 생성이
//    실패해 아래 로컬 폴백 경로로 넘어간다). cloudKitDatabase는 .automatic으로 설정해
//    특정 컨테이너 식별자를 하드코딩하지 않는다.
//  - 멀티윈도우(요구사항 4) — 장(章)을 별도 창으로 열 수 있는 WindowGroup(for:) 추가.
//  - macOS Settings 씬(요구사항 5.2 UI) 추가.
//  - 맥OS 메뉴 구성(요구사항 1) — AppCommands.swift 참고.
//

import SwiftUI
import SwiftData
import BibleResearchModels

@main
struct JBCHBibleResearchApp: App {
    // 이전 코드는 `_ = try BibleResearchSchema.makeSharedModelContainer()`로 생성만 해보고
    // 버렸습니다 — 그래서 컨테이너 생성 성공/실패는 콘솔 로그로만 확인 가능했고, 정작
    // ContentView 등 화면 쪽에서 @Query/@Environment(\.modelContext)를 써도 이 컨테이너와
    // 연결돼 있지 않았습니다. 실제로 화면이 이 데이터 레이어를 쓰려면 컨테이너를 만들어서
    // 계속 들고 있다가 .modelContainer(_:)로 Scene에 붙여야 합니다.
    private let modelContainer: ModelContainer

    init() {
        // [2026-08-08 추가] 사용자 요청 — "앱의 내장한 글꼴이 기본 글꼴이 되도록".
        // 모델 컨테이너 준비와 무관하므로 그보다 먼저 실행해도 상관없다 —
        // BundledFontRegistrar.swift 상단 주석 참고(등록 실패해도 앱은 계속 켜진다).
        BundledFontRegistrar.registerBundledFontsIfNeeded()

        do {
            modelContainer = try BibleResearchSchema.makeSharedModelContainer()
            print("[JBCHBibleResearchApp] 모델 컨테이너 생성 성공 (CloudKit 컨테이너: \(BibleResearchSchema.defaultCloudKitContainerIdentifier))")
        } catch {
            // CloudKit 컨테이너 설정(Signing & Capabilities의 iCloud capability, Containers
            // 목록)이 아직 안 돼 있으면 여기로 옵니다. 앱 자체는 계속 켜지도록 로컬 전용
            // (in-memory) 컨테이너로 폴백합니다 — 이 경우 데이터는 기기 간 동기화되지 않고
            // 앱을 껐다 켜면 사라집니다. 원인은 콘솔의 아래 로그로 확인하세요.
            print("[JBCHBibleResearchApp] 모델 컨테이너 생성 실패: \(error)")
            print("[JBCHBibleResearchApp] 로컬 전용(in-memory) 컨테이너로 폴백합니다 — CloudKit 동기화는 비활성 상태입니다.")
            // in-memory 폴백은 CloudKit이 전혀 개입하지 않아 실패할 이유가 사실상 없다고
            // 판단해 강제 언래핑으로 처리했습니다. 그래도 실패한다면 스키마 자체(위 캐치되지
            // 않은 원인)에 문제가 있다는 뜻이라 앱을 계속 켜는 게 의미가 없어 fatalError가
            // 맞다고 봤습니다.
            modelContainer = try! BibleResearchSchema.makeSharedModelContainer(isStoredInMemoryOnly: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                // screens.md 9.1 — 메인 창 최소 크기 1072×700. iPadOS/iPhone에는
                // 이 개념 자체가 없어 macOS에서만 적용한다.
                // [2026-08-15 변경] 사용자 요청 — "메인창 최소 가로길이는 최소
                // 1072로 지정할 것." 기존 1000 → 1072로 확대.
                .frame(minWidth: 1072, minHeight: 700)
                #endif
        }
        .modelContainer(modelContainer)
        // 11장 macOS 메뉴 바 — AppCommands.swift(File/View/Bible), 나머지 메뉴는
        // SwiftUI 기본 제공 항목을 그대로 쓴다(AppCommands.swift 상단 ⚠️ 참고).
        .commands {
            AppCommands()
        }

        // [2026-08-07 추가] S1(성경 조회) 다중 창 — 사용자 요청: "성경 조회 창은
        // 여러 개를 띄울 수 있어야 하고, 각 창마다 다른 성경을 동시에 조회할 수
        // 있어야 한다." `BibleReadingView()`는 자기 `@State private var viewModel:
        // BibleReadingViewModel?`을 뷰 인스턴스마다 새로 만든다(AppFocusedValues.swift
        // 상단 주석이 이미 "전역 싱글턴을 쓰면 창 A에서 고른 화면이 창 B에도 번진다"는
        // 이유로 전역 상태를 피해 온 것과 같은 원칙) — 그래서 이 창을 몇 개를 열든
        // 서로 완전히 독립된 book/chapter/표시 번역본 상태를 가진다. "tag-relations"
        // 창과 같은 패턴, id만 다르다.
        WindowGroup(id: "bible-reading") {
            // [2026-08-08 추가] 사용자 요청 — 이 "새 창"으로 연 보조 창에서는
            // 관련 콘텐츠(인스펙터)/조회 이력 아이콘을 뺀다 — `BibleReadingView.
            // isPrimaryWindow` 상단 주석 참고.
            BibleReadingView(isPrimaryWindow: false)
                #if os(macOS)
                .frame(minWidth: 500, minHeight: 400)
                #endif
        }
        .modelContainer(modelContainer)

        // screens.md 9.1 — "태그 관계" 사이드바 항목이 여는 별도 창(SidebarNavigationView.swift
        // 참고). 2026-08-06: S10(태그 관계 시각화)이 구현되면서 플레이스홀더를
        // 실제 화면(TagRelationsView.swift)으로 교체했다.
        WindowGroup(id: "tag-relations") {
            TagRelationsView()
                #if os(macOS)
                .frame(minWidth: 600, minHeight: 500)
                #endif
        }
        .modelContainer(modelContainer)

        // [2026-08-09 추가, 2026-08-15 삭제] "[성경 조회] 오른쪽 사이드바의 개요 —
        // 개요화면 열기 버튼: 이동가능, 크기조절 가능한 창으로 조회모드로 열기"를
        // 위해 만들었던 `WindowGroup(id: "outline")`이 여기 있었다. 사용자가 이번
        // 라운드에 그 버튼의 동작을 다시 "메인 내비게이션을 개요 섹션으로 전환 +
        // 책/장 자동 선택 + 에디터 화면"으로 되돌렸고(`AppNavigationRequest`/
        // `OutlineNavigationRequest`, `ChapterRelatedContentPanel.jumpToOutlineEditor`
        // 참고), "별도 창에서 보기"는 완전히 새로운 전용 창(`outline-quick-view`,
        // 아래 참고)으로 바뀌면서, 이 창을 여는 호출부가 앱 전체에 하나도 남지
        // 않았다(`openWindow(id: "outline"` 전수 검색 결과 0건) — 죽은 코드라 지웠다.

        // [2026-08-07 추가] S6(연구문서 원문 뷰어) — screens.md 3장 S6 절이 "Preview.app
        // 패턴, 문서마다 별도 창"이라고 명시한 부분을 반영한다. 지금까지는 메인 창 안
        // NavigationLink 푸시였다(4곳: S5 목록/S10 드릴다운/S11 검색결과, 관련문서
        // 진입점). `openWindow(id: "document-viewer", value: document.persistentModelID)`로
        // 열고, 여기서 `PersistentIdentifier`를 다시 `SourceDocument`로 되찾는다 —
        // Codable/Hashable을 요구하는 WindowGroup(for:)에 모델 인스턴스 자체를 직접
        // 넘길 수 없어서 이 우회가 필요하다(Apple 공식 패턴, SwiftData 문서의
        // "여러 창에서 같은 모델 열기" 예시와 동일한 방식).
        // ⚠️ [플랫폼 검증 필요] "tag-relations" 창과 마찬가지로 macOS/iPadOS에서는
        // 진짜 별도 창으로 열리지만, 아이폰은 애초에 다중 창을 지원하지 않아
        // openWindow가 현재 화면을 이 WindowGroup 콘텐츠로 대체하는 형태로 동작할
        // 것으로 예상된다(이미 있던 "tag-relations" 창도 같은 특성 — 실기기 검증
        // 안 됨, 이 프로젝트가 기존에 써 온 것과 같은 패턴이라 새로운 위험은 아니다).
        WindowGroup(id: "document-viewer", for: PersistentIdentifier.self) { $documentID in
            DocumentViewerWindowContent(documentID: documentID)
                #if os(macOS)
                .frame(minWidth: 500, minHeight: 400)
                #endif
        }
        .modelContainer(modelContainer)

        // [2026-08-11 추가] 사용자 요청 — "[관련 내용]에서 연구문서를 클릭하면 PDF로
        // 띄워 해당 성경구절 텍스트로 검색할 것." 위 "document-viewer" 창(문서 ID만
        // 받음)과 값 타입이 달라(문서 ID + 검색어) 별도 WindowGroup으로 분리했다
        // (DocumentSearchRequest.swift 상단 주석 참고) — 기존 "그냥 열기" 흐름은
        // 전혀 건드리지 않는다.
        WindowGroup(id: "document-search", for: DocumentSearchRequest.self) { $request in
            DocumentSearchWindowContent(request: request)
                #if os(macOS)
                .frame(minWidth: 500, minHeight: 400)
                #endif
        }
        .modelContainer(modelContainer)

        // [2026-08-15 추가] 사용자 요청 — "[성경 조회] 인스펙터 개요의 '별도
        // 창에서 보기': 기존 창을 재사용하지 말고 신규 창을 만들 것. 책 개요 /
        // 장 개요(해당 장)만 표시. 상단에 검색창 + 돋보기(배율 확대/축소/원본
        // 크기)." `OutlineQuickViewRequest`가 매번 새 `UUID`를 포함하므로
        // (그 타입 상단 주석 참고) `openWindow(id: "outline-quick-view", value:)`를
        // 부를 때마다 SwiftUI가 항상 새 창을 연다 — 위 "document-viewer"/
        // "document-search"처럼 기존 창을 재사용(값이 같으면 기존 창을 앞으로
        // 가져오는 `WindowGroup(for:)` 기본 동작)하지 않는다.
        WindowGroup(id: "outline-quick-view", for: OutlineQuickViewRequest.self) { $request in
            OutlineQuickViewWindowContent(request: request)
                #if os(macOS)
                .frame(minWidth: 420, minHeight: 400)
                #endif
        }
        .modelContainer(modelContainer)

        // 8장 환경설정 — macOS 전용 Scene 타입이라 iOS/iPadOS에는 아예 존재하지
        // 않는다(`Settings`는 iOS SDK에 없음, canImport가 아니라 os(macOS)로
        // 가드해야 한다). iPadOS/iPhone은 SettingsHostView(시트)/NavigationLink로
        // 별도 진입한다(SidebarNavigationView.swift/PlaceholderScreens.swift 참고).
        // [2026-08-11 변경, 2026-08-16 문구 정리] 사용자 요청 — "환경설정의
        // 메뉴/타이틀은 시스템 기본 글꼴, 보통 크기로". 이제는 이 Settings 창뿐
        // 아니라 위 모든 창이 `.appDefaultFont()`를 안 붙인다(RootView.swift
        // 상단 주석 참고 — "Paperlogy는 성경 본문과 관련될 때만" 정리의 일부),
        // 그래서 SettingsView가 특별한 예외는 아니게 됐다 — 여전히 SettingsView가
        // 아무 `.font(_:)`도 지정하지 않으므로 SwiftUI가 시스템 기본 글꼴/크기로
        // 그린다.
        #if os(macOS)
        Settings {
            SettingsView()
                .modelContainer(modelContainer)
        }
        // screens.md 8장 "macOS 표준 Settings 창 패턴(고정 크기... 리사이즈 불가)".
        .windowResizability(.contentSize)
        #endif
    }
}

