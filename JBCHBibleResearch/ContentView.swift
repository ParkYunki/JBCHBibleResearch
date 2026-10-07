//
//  ContentView.swift
//  JBCHBibleResearch
//
//  Created by 박윤기 on 8/3/26.
//
//  앱의 최상위 뷰. 내비게이션 뼈대(RootView)를 띄우고, 앱 최초 진입 시 1회
//  TranslationBootstrap으로 번들 번역본을 TranslationRegistry에 등록한다.
//  테마/온보딩/공유받은 메모 가져오기 등 앱 전체 진입점 modifier도 여기에 모아 둔다.
//

import SwiftUI
import BibleResearchModels
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    // "테마 색상"의 "자동" 모드가 유효한 라이트/다크 상태를 따라가는 데 필요.
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var bootstrapErrorDescription: String?

    /// 화면 모드가 라이트/다크를 강제하고 있으면 그 값을, "시스템 따름"이면
    /// 실제 시스템 값(`systemColorScheme`)을 돌려준다 — "테마 색상 자동"이 따라야 할 건
    /// 화면 모드가 실제로 렌더링하는 명암이기 때문이다.
    private var effectiveColorScheme: ColorScheme {
        UserSettingsStore.shared.colorSchemePreference.colorScheme ?? systemColorScheme
    }

    var body: some View {
        RootView()
            .safeAreaInset(edge: .bottom) {
                if let message = CloudSyncMonitor.shared.errorMessage {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("iCloud 동기화 실패", systemImage: "exclamationmark.icloud")
                            .font(.callout.bold())
                        Text(message)
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.regularMaterial)
                }
            }
            // `colorSchemePreference`를 `RootView`가 아니라 여기서 읽어야 한다. 값을 읽는 뷰가
            // `TabView`를 직접 만들면, 값이 바뀔 때마다 body가 다시 실행되어 `TabView`가 통째로
            // 재생성되고 선택된 탭/내비게이션 스택이 초기화된다(화면모드를 바꾸면 "성경" 탭으로 이동).
            // (Apple Developer Forums 스레드 726363과 같은 원인)
            .preferredColorScheme(UserSettingsStore.shared.colorSchemePreference.colorScheme)
            // 유효 라이트/다크가 바뀔 때마다, 그리고 앱이 처음 뜰 때 1회 다시 계산한다.
            // `syncAutoThemeIfNeeded`는 `bibleThemeModePreference == .auto`일 때만
            // 실제로 hex를 바꾸므로 라이트/다크 고정이나 커스텀 상태에는 영향이 없다.
            .onChange(of: effectiveColorScheme) { _, newValue in
                UserSettingsStore.shared.syncAutoThemeIfNeeded(systemColorScheme: newValue)
            }
            .task {
                UserSettingsStore.shared.syncAutoThemeIfNeeded(systemColorScheme: effectiveColorScheme)
            }
            // 배경색이 바뀔 때마다 UIKit 탭바 외형을 다시 적용한다(`applyThemedTabBarAppearance`,
            // `PhoneTabView.swift`). 위 `colorSchemePreference`와 같은 이유로 `TabView`를 직접
            // 구성하지 않는 이 자리에 둔다. `PhoneTabView`는 아이폰 전용이라 iOS에서만 필요하다.
            #if os(iOS)
            .onAppear {
                applyThemedTabBarAppearance(color: UserSettingsStore.shared.bibleBackgroundColor)
            }
            .onChange(of: UserSettingsStore.shared.bibleBackgroundColor) { _, newValue in
                applyThemedTabBarAppearance(color: newValue)
            }
            #endif
            // 앱 최초 실행 시 1회 안내 카루셀(AppOnboardingOverlay.swift).
            .appOnboarding()
            // 업데이트 후 최초 실행 시 해당 버전의 `WhatsNewContent`를 보여준다.
            // `hasCompletedOnboarding`이 true인 기존 설치에서만 뜬다(WhatsNewOverlay.swift).
            .whatsNewOverlay()
            .task {
                // 온보딩 카루셀이 이 블록의 진행 상태를 보여줄 수 있도록 한다
                // (`AppBootstrapProgress.swift`). `defer`로 성공/실패 어느 경로로 끝나도
                // 항상 한 번 내려간다.
                defer { AppBootstrapProgress.shared.markFinished() }
                do {
                    try TranslationBootstrap.ensureBundledTranslationRegistered(in: modelContext)
                    // 예전에 등록됐던 국한문혼용 번들 번역본을 이미 등록된 기기에서 정리한다.
                    try TranslationBootstrap.removeHanjaTranslationIfPresent(in: modelContext)
                    // CloudKit 다중 기기 초기 부트스트랩 경합으로 생길 수 있는 code 중복
                    // TranslationRegistry를 앱이 뜰 때마다 정리한다.
                    try TranslationBootstrap.deduplicateRegistries(in: modelContext)
                    // 번들 기본 개요(OutlineSeed.sqlite, 있으면)를 사용자 DB로 1회 복사한다.
                    // 실패해도 throw하지 않고 내부에서 처리하므로 다른 부트스트랩을 막지 않는다.
                    await OutlineSeedImporter.importIfNeeded(into: modelContext)
                    // SermonGathering 초기 시드(주일설교/청년회 말씀/구역모임/조모임)를 최초 실행 시
                    // 생성한다. 비동기가 필요 없는 가벼운 작업이라 `await` 없이 호출한다.
                    SermonGatheringSeeder.seedIfNeeded(into: modelContext)
                    // 기기마다 시드가 돌아 생긴 같은 이름의 모임 종류를 하나로 합친다(모임 선택 시트의 칩 중복 방지).
                    SermonGatheringSeeder.deduplicate(in: modelContext)
                    // 기기마다 만들어져 생긴 같은 이름의 개인 묵상 폴더를 하나로 합친다(`MemoFolderMaintenance`).
                    MemoFolderMaintenance.deduplicate(in: modelContext)
                    // 동기화 중 같은 id로 따로 생긴 말씀 요약 중복 중, 내용이 완전히 같은 것만 삭제한다(태그는 남길 쪽으로 옮김).
                    let removedSummaries = VerseSummaryDeduplication.deduplicate(in: modelContext)
                    if removedSummaries > 0 { print("[ContentView] 중복 말씀 요약 \(removedSummaries)건 정리") }
                    // 관주/난외주/한자주석/한자사전은 사용자가 편집하지 않는 정적 참조 데이터라
                    // CloudKit 동기화 대상이 아니며, 번들 `Resources/ReferenceData.sqlite`(읽기 전용)에서
                    // 직접 읽는다(`ReferenceDataProvider`/`ReferenceDataStore`). 예전에 SwiftData로
                    // 복사돼 들어간 번들분(있다면)만 여기서 1회성으로 정리한다.
                    ReferenceDataMigration.cleanupLegacyBundledRecords(in: modelContext)
                    // 의미(임베딩) 검색 제거 전 버전이 만들어 둔 성경 임베딩 색인 파일(약 95MB)을 정리한다.
                    LegacyEmbeddingIndexCleanup.run()
                } catch {
                    // 번들 리소스 누락 등 부트스트랩 실패는 S1이 "표시할 번역본 없음"으로
                    // 조용히 보이는 대신, 사용자가 원인을 바로 알 수 있도록 알림으로
                    // 드러낸다.
                    print("[ContentView] 번들 번역본 등록 실패: \(error)")
                    bootstrapErrorDescription = error.localizedDescription
                }
            }
            .alert(
                "번들 번역본을 등록하지 못했습니다",
                isPresented: Binding(
                    get: { bootstrapErrorDescription != nil },
                    set: { if !$0 { bootstrapErrorDescription = nil } }
                )
            ) {
                Button("확인") { bootstrapErrorDescription = nil }
            } message: {
                Text(bootstrapErrorDescription ?? "")
            }
            // 공유받은 `.jbchmemo` 파일: `JBCHBibleResearchApp`의 `.onOpenURL`이
            // `PendingMemoImportRequest`에 담아 두면 여기서 감지해 미리보기 시트를 띄운다
            // (`PendingMemoImportRequest.swift`). `.sheet(item:)`이라 시트가 닫히면
            // (`ImportedMemoPreviewSheet`가 `consume()` 호출) 페이로드가 비워져,
            // 같은 파일을 다시 열어도 새 요청으로 인식된다.
            .sheet(item: Binding(
                get: { PendingMemoImportRequest.shared.pending },
                set: { if $0 == nil { PendingMemoImportRequest.shared.consume() } }
            )) { pending in
                ImportedMemoPreviewSheet(payload: pending.payload) {
                    PendingMemoImportRequest.shared.consume()
                }
            }
            // 받은 파일이 이 앱의 형식이 아니거나 손상됐을 때 미리보기 시트 대신 알림을
            // 띄운다(`PendingMemoImportRequest.handleOpenedFile`).
            .alert(
                "받은 파일을 열 수 없습니다",
                isPresented: Binding(
                    get: { PendingMemoImportRequest.shared.lastImportError != nil },
                    set: { if !$0 { PendingMemoImportRequest.shared.consumeError() } }
                )
            ) {
                Button("확인") { PendingMemoImportRequest.shared.consumeError() }
            } message: {
                Text(PendingMemoImportRequest.shared.lastImportError ?? "")
            }
    }
}

#Preview {
    // 프리뷰 캔버스는 실제 앱 Scene의 .modelContainer(_:)를 거치지 않으므로,
    // @Environment(\.modelContext)가 비어 있으면 여기서 크래시한다. 프리뷰 전용으로
    // 메모리 전용 컨테이너를 직접 붙여준다.
    ContentView()
        .modelContainer(try! BibleResearchSchema.makeSharedModelContainer(isStoredInMemoryOnly: true))
}
