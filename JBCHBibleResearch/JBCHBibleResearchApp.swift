//
//  JBCHBibleResearchApp.swift
//  JBCHBibleResearch
//
//  Created by 박윤기 on 8/3/26.
//
//  앱 진입점. 공유 ModelContainer를 만들어 모든 Scene에 붙이고, 메인 창과 보조 창
//  (성경 조회, 태그 관계, 문서 뷰어, 설교 등)의 WindowGroup, macOS 메뉴(AppCommands.swift),
//  macOS Settings 씬을 정의한다.
//
//  iCloud(CloudKit) 동기화가 실제로 켜지려면 Xcode의 Signing & Capabilities에서 iCloud
//  capability와 CloudKit 서비스를 켜고 Containers 목록에 컨테이너를 최소 1개 추가해야 한다
//  (빈 목록이면 컨테이너 생성이 실패해 아래 로컬 폴백 경로로 넘어간다). cloudKitDatabase는
//  .automatic이라 특정 컨테이너 식별자를 하드코딩하지 않는다.
//

import SwiftUI
import SwiftData
import BibleResearchModels

@main
struct JBCHBibleResearchApp: App {
    // 컨테이너를 계속 들고 있다가 `.modelContainer(_:)`로 각 Scene에 붙여야
    // 화면의 @Query/@Environment(\.modelContext)가 이 컨테이너와 연결된다.
    private let modelContainer: ModelContainer

    init() {
        // 모델 컨테이너 준비와 무관하므로 먼저 실행해도 된다
        // (BundledFontRegistrar.swift 참고 — 등록에 실패해도 앱은 계속 켜진다).
        BundledFontRegistrar.registerBundledFontsIfNeeded()

        // macOS 안전망(2026-10-01) — 성경 조회에서 인스펙터를 연 채 툴바 ">>"(넘침 메뉴)를 누르면 `NSGenericException: The window has
        // been marked as needing another Update Constraints in Window pass, but it has already had more ... passes than there are
        // views`로 앱이 종료됐다. 스택에 앱 코드는 없고 `SplitViewChildController.hostingView(_:didUpdateMinSize:maxSize:)`가
        // 제약 갱신 중에 다시 무효화를 거는 SwiftUI/AppKit 내부 순환이다(근본 원인은 미확정). AppKit은 이 한도 초과를 기본값으로는 예외로
        // 종료시키지만, 이 UserDefaults 키(비공개 키 — 공식 문서 없음, UTM 등 다른 앱도 같은 우회를 사용)를 끄면 예외 없이 이후 갱신
        // 표시를 무시한다(크래시 로그의 "Future marking ... might be ignored" 문구가 그 경로다). 순환 자체를 없애지는 못하므로
        // 근본 원인을 찾으면 제거한다. 다른 곳에서 읽는 값이 아니라 `init()` 맨 앞(윈도우 생성 전)에서 한 번만 설정한다.
        #if os(macOS)
        UserDefaults.standard.set(false, forKey: "NSWindowAssertWhenDisplayCycleLimitReached")
        #endif

        // `UITabBar.appearance()`(UIKit 외형 프록시)는 탭바가 윈도우에 "처음 추가되기 전"에
        // 설정해야 확실히 반영된다. `PhoneTabView.onAppear`만으로는 실기기에서 반영되지
        // 않아, 윈도우가 만들어지기 전인 여기에서 먼저 호출한다
        // (`PhoneTabView.swift`의 `applyThemedTabBarAppearance` 참고).
        #if os(iOS)
        applyThemedTabBarAppearance(color: UserSettingsStore.shared.bibleBackgroundColor)
        #endif

        // 컨테이너 생성이 실패하면 곧장 in-memory로 폴백하지 않고, 먼저 "디스크에는 그대로
        // 남기되 CloudKit만 끈" 컨테이너를 시도한다. in-memory 폴백은 디스크의 기존 데이터를
        // 통째로 안 보이게 하고 새 데이터도 저장되지 않으므로, CloudKit이 원인일 때(가장 흔한
        // 경우)에는 이 중간 단계에서 성공해 기존 데이터가 그대로 보이고 기기 간 동기화만
        // 잠시 꺼진다. 이 단계까지 실패해야만 마지막 수단으로 in-memory를 쓴다.
        //
        // ⚠️ 실패 원인이 CloudKit 스키마 반영 문제인지 다른 모델 타입 문제인지는 확정하지
        // 못했다 — 아래 "실패(CloudKit 포함)" 로그의 `error` 값을 Xcode 콘솔에서 확인해야 한다.
        do {
            modelContainer = try BibleResearchSchema.makeSharedModelContainer()
            print("[JBCHBibleResearchApp] 모델 컨테이너 생성 성공 (CloudKit 컨테이너: \(BibleResearchSchema.defaultCloudKitContainerIdentifier))")
        } catch let cloudKitError {
            print("[JBCHBibleResearchApp] 모델 컨테이너 생성 실패(CloudKit 포함): \(cloudKitError)")
            print("[JBCHBibleResearchApp] 디스크 로컬 전용(CloudKit 비활성) 컨테이너로 재시도합니다 — 기존에 저장된 데이터는 그대로 남아 있어야 합니다.")
            do {
                modelContainer = try BibleResearchSchema.makeSharedModelContainer(enableCloudKit: false)
                print("[JBCHBibleResearchApp] 디스크 로컬 전용 컨테이너 생성 성공 — CloudKit 동기화만 비활성 상태입니다. 위 첫 번째 에러 메시지를 확인해 원인을 해결한 뒤 다시 켜 주세요.")
            } catch let diskError {
                // CloudKit과 무관하게 디스크 스토어 자체(또는 스키마) 문제라는 뜻이다.
                // 앱이 아예 못 켜지는 것보다는 낫다고 판단해 이 경우에만 in-memory로 폴백한다.
                // 기존 데이터가 보이지 않고 새로 입력한 것도 저장되지 않으므로, 이 로그가
                // 찍히면 반드시 원인을 먼저 해결해야 한다.
                print("[JBCHBibleResearchApp] 디스크 로컬 전용 컨테이너도 실패: \(diskError)")
                print("[JBCHBibleResearchApp] ⚠️ 마지막 수단으로 in-memory 컨테이너로 폴백합니다 — 이 세션에서는 기존 데이터가 보이지 않고 새 데이터도 저장되지 않습니다. 위 두 에러 메시지를 반드시 확인해 주세요.")
                modelContainer = try! BibleResearchSchema.makeSharedModelContainer(isStoredInMemoryOnly: true)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                // 메인 창 최소 크기. iPadOS/iPhone에는 이 개념이 없어 macOS에서만 적용한다.
                .frame(minWidth: 1072, minHeight: 700)
                #endif
                // 다른 기기에서 `MemoDetailView`의 `ShareLink`로 내보낸 `.jbchmemo` 파일을
                // 열면(앱이 켜져 있을 때 받는 경우 포함) 이 클로저가 파일 URL과 함께 호출된다.
                // `Info.plist`의 `CFBundleDocumentTypes`/`UTExportedTypeDeclarations`가 이 형식을
                // 앱이 연다고 등록해 둔 덕분이다. 파싱과 미리보기 시트 표시는
                // `PendingMemoImportRequest`(신호 전용 싱글턴)와 `ContentView`의
                // `.sheet(item:)`이 맡고, 이 클로저는 그 둘을 잇는 통로일 뿐이다.
                // 앱 전체 진입점 modifier(`.appOnboarding()` 등)와 같이 이 첫 번째
                // `WindowGroup`에만 붙인다.
                .onOpenURL { url in
                    PendingMemoImportRequest.shared.handleOpenedFile(at: url)
                }
        }
        .modelContainer(modelContainer)
        // macOS 메뉴 바 — AppCommands.swift(File/View/Bible), 나머지 메뉴는
        // SwiftUI 기본 제공 항목을 그대로 쓴다(AppCommands.swift 상단 ⚠️ 참고).
        .commands {
            AppCommands()
        }

        // 성경 조회(S1) 다중 창 — 여러 개를 띄울 수 있고 창마다 다른 성경을 동시에 조회한다.
        // `BibleReadingView()`가 자기 `@State` viewModel을 뷰 인스턴스마다 새로 만들므로
        // (전역 싱글턴을 쓰면 창 A의 선택이 창 B로 번지는 것을 피하는
        // AppFocusedValues.swift와 같은 원칙) 창마다 book/chapter/번역본 상태가 독립이다.
        WindowGroup(id: "bible-reading") {
            // 이 "새 창"으로 연 보조 창에서는 관련 콘텐츠(인스펙터)/조회 이력 아이콘을 뺀다
            // (`BibleReadingView.isPrimaryWindow` 참고).
            BibleReadingView(isPrimaryWindow: false)
                .modifier(AppColorSchemeModifier())
                #if os(macOS)
                .frame(minWidth: 500, minHeight: 400)
                #endif
        }
        .modelContainer(modelContainer)

        // "태그 관계" 사이드바 항목이 여는 별도 창(SidebarNavigationView.swift 참고).
        WindowGroup(id: "tag-relations") {
            TagRelationsView()
                .modifier(AppColorSchemeModifier())
                #if os(macOS)
                .frame(minWidth: 600, minHeight: 500)
                #endif
        }
        .modelContainer(modelContainer)

        // 연구문서 원문 뷰어 — Preview.app 패턴으로 문서마다 별도 창.
        // `openWindow(id: "document-viewer", value: document.persistentModelID)`로 열고 여기서
        // `PersistentIdentifier`를 다시 `SourceDocument`로 되찾는다 — Codable/Hashable을 요구하는
        // WindowGroup(for:)에 모델 인스턴스를 직접 넘길 수 없어서 필요한 우회다.
        // ⚠️ macOS/iPadOS에서는 별도 창으로 열리지만, 아이폰은 다중 창을 지원하지 않아
        // openWindow가 현재 화면을 이 WindowGroup 콘텐츠로 대체하는 형태로 동작할 것으로
        // 예상된다("tag-relations" 창도 같은 특성, 실기기 미검증).
        WindowGroup(id: "document-viewer", for: PersistentIdentifier.self) { $documentID in
            DocumentViewerWindowContent(documentID: documentID)
                .modifier(AppColorSchemeModifier())
                #if os(macOS)
                .frame(minWidth: 500, minHeight: 400)
                #endif
        }
        .modelContainer(modelContainer)

        // 연구문서를 PDF로 띄워 검색어로 찾는 창. "document-viewer"와 값 타입(문서 ID + 검색어)이
        // 달라 별도 WindowGroup으로 분리했다(DocumentSearchRequest.swift 참고).
        WindowGroup(id: "document-search", for: DocumentSearchRequest.self) { $request in
            DocumentSearchWindowContent(request: request)
                .modifier(AppColorSchemeModifier())
                #if os(macOS)
                .frame(minWidth: 500, minHeight: 400)
                #endif
        }
        .modelContainer(modelContainer)

        // 성경 조회 인스펙터 개요의 "별도 창에서 보기" — 항상 신규 창을 연다.
        // `OutlineQuickViewRequest`가 매번 새 `UUID`를 포함하므로(그 타입 참고) 값이 같으면
        // 기존 창을 앞으로 가져오는 `WindowGroup(for:)` 기본 동작과 달리, `openWindow` 호출마다
        // SwiftUI가 새 창을 연다.
        WindowGroup(id: "outline-quick-view", for: OutlineQuickViewRequest.self) { $request in
            OutlineQuickViewWindowContent(request: request)
                .modifier(AppColorSchemeModifier())
                #if os(macOS)
                .frame(minWidth: 420, minHeight: 400)
                #endif
        }
        .modelContainer(modelContainer)

        // "내 설교" 상세 창. "document-viewer"와 같은 이유로 `@Query` 기반
        // `SermonDetailWindowContent`(Views/Sermon/SermonDetailView.swift)가 창이 떠 있는 동안
        // 대상이 삭제돼도 안전하게 "찾을 수 없음"으로 넘어가게 한다.
        WindowGroup(id: "sermon-detail", for: PersistentIdentifier.self) { $sermonID in
            SermonDetailWindowContent(sermonID: sermonID)
                .modifier(AppColorSchemeModifier())
                #if os(macOS)
                .frame(minWidth: 760, minHeight: 640)
                #endif
        }
        .modelContainer(modelContainer)

        // 설교 작성(S-SER2)/뷰어(S-SER3) 창 — `SermonContentWindowContent`
        // (Views/Sermon/SermonSupport.swift)가 `mode`에 따라 에디터/뷰어로 분기한다.
        // `SermonContentTarget`이 Sermon(메인)/SermonDelivery(회차 사본) 중 어느 쪽을 열지 함께 싣는다.
        WindowGroup(id: "sermon-editor", for: SermonContentTarget.self) { $target in
            SermonContentWindowContent(mode: .editor, target: target)
                .modifier(AppColorSchemeModifier())
                #if os(macOS)
                .frame(minWidth: 960, minHeight: 680)
                #endif
        }
        .modelContainer(modelContainer)

        // "새 설교" 작성 창 — 아직 저장하지 않은 `Sermon`을 창 안에서 만들어 들고 있어 별도 `WindowGroup`/값 타입
        // (`SermonNewTarget`, SermonSupport.swift)을 쓴다. 에디터 창("sermon-editor")과 크기는 같다.
        WindowGroup(id: "sermon-new", for: SermonNewTarget.self) { $target in
            SermonNewWindowContent(target: target)
                .modifier(AppColorSchemeModifier())
                #if os(macOS)
                .frame(minWidth: 960, minHeight: 680)
                #endif
        }
        .modelContainer(modelContainer)

        // 두 WindowGroup이 같은 값 타입(`SermonContentTarget`)을 공유하면 뷰어 창이
        // 열리지 않는 문제가 있어(iPad), 내용은 같고 타입만 다른 `SermonViewerTarget`
        // 래퍼(SermonSupport.swift)를 쓴다 — 원인 분석은 그 타입 선언부 주석 참고.
        WindowGroup(id: "sermon-viewer", for: SermonViewerTarget.self) { $wrapped in
            SermonContentWindowContent(mode: .viewer, target: wrapped?.target)
                #if os(macOS)
                .frame(minWidth: 1000, minHeight: 700)
                #endif
        }
        .modelContainer(modelContainer)

        // 설교 마인드맵 창(아이패드·맥). 아이폰은 다중 창을 지원하지 않아 `SermonMindMapView`를
        // 여는 `NavigationLink` push로 대체한다. 값 타입은 "sermon-viewer"와 같은 이유로
        // `SermonContentTarget`/`SermonViewerTarget`과 겹치지 않는 `SermonMindMapTarget`
        // (SermonSupport.swift)을 쓴다.
        WindowGroup(id: "sermon-mindmap", for: SermonMindMapTarget.self) { $target in
            SermonMindMapWindowContent(target: target)
                .modifier(AppColorSchemeModifier())
                #if os(macOS)
                .frame(minWidth: 1000, minHeight: 700)
                #endif
        }
        .modelContainer(modelContainer)

        // 환경설정 — macOS 전용 Scene 타입이라 iOS/iPadOS에는 존재하지 않는다
        // (`Settings`는 iOS SDK에 없어 canImport가 아니라 os(macOS)로 가드해야 한다).
        // iPadOS/iPhone은 SettingsHostView(시트)/NavigationLink로 별도 진입한다
        // (SidebarNavigationView.swift/PlaceholderScreens.swift 참고).
        // SettingsView는 `.font(_:)`를 지정하지 않아 시스템 기본 글꼴/크기로 그려진다.
        #if os(macOS)
        Settings {
            SettingsView()
                .modelContainer(modelContainer)
        }
        // macOS 표준 Settings 창 패턴 — 고정 크기, 리사이즈 불가.
        .windowResizability(.contentSize)
        #endif
    }
}

/// 보조 `WindowGroup` 창에 앱의 화면 모드(라이트/다크/시스템)를 적용하는 수정자.
/// `.preferredColorScheme`은 메인 창의 `ContentView`에서만 걸려 있어, 보조 창(마인드맵·편집기 등)은 앱을 라이트로 설정해도
/// macOS가 다크 외형이면 시스템 다크로 그려져 글자색(`.primary`)이 흰색이 되고 앱 테마 배경(미색)과 겹쳐 안 보였다(2026-10-01 보고).
/// 작은 창 콘텐츠에서 값을 읽으므로 `ContentView` 주석의 TabView 재생성 문제는 해당되지 않는다.
/// 설교 뷰어 창("sermon-viewer")은 자체적으로 라이트 외형을 고정하므로 제외한다.
private struct AppColorSchemeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.preferredColorScheme(UserSettingsStore.shared.colorSchemePreference.colorScheme)
    }
}
