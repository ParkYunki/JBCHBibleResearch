//
//  ContentView.swift
//  JBCHBibleResearch
//
//  Created by 박윤기 on 8/3/26.
//
//  2026-08-06: 화면 레이어 시작 — 기본 템플릿(Hello, world) 대신 실제 내비게이션
//  뼈대(RootView)를 띄운다. 여기서 앱 최초 진입 시 1회, TranslationBootstrap으로
//  번들 번역본을 TranslationRegistry에 등록한다(Views/Navigation, Views/Bible,
//  Services 참고).
//

import SwiftUI
import BibleResearchModels
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var bootstrapErrorDescription: String?

    var body: some View {
        RootView()
            // [2026-09-03 신설] 사용자 보고 — "더보기 > 설정 > 성경 > 모양의
            // 화면모드를 바꾸면 자동으로 성경으로 이동하는데, 화면모드를 바꿔도
            // 현재 페이지를 유지하도록." 원래 `RootView.swift`의 `body`가
            // `UserSettingsStore.shared.colorSchemePreference`를 직접 읽으면서
            // 동시에 그 안에서 `PhoneTabView`(진짜 `TabView`)를 만들고 있었다 —
            // Apple Developer Forums 스레드 726363("App Lost all selection
            // info of navigation and tab, after update a AppStorage state")이
            // 확인해 준 것과 같은 원인: 그 값이 바뀔 때마다 `TabView`를 직접
            // 구성하는 바로 그 뷰의 body가 다시 실행되며 `TabView`가 통째로
            // 다시 만들어져, 선택된 탭이 기본값(`.bibleReading` = "성경")으로
            // 되돌아가고 그 안의 내비게이션 스택도 함께 초기화됐다(=화면모드를
            // 바꾸면 자동으로 "성경"으로 이동). 그 포럼 답변의 해법 그대로 —
            // 값을 읽는 자리와 TabView를 만드는 자리를 분리 — 이 modifier를
            // `RootView`(TabView를 직접 만드는 그 뷰) 대신 여기(`RootView()`를
            // 만드는 바깥 자리)로 옮겼다. `RootView.swift`의 옛 위치 주석 참고.
            .preferredColorScheme(UserSettingsStore.shared.colorSchemePreference.colorScheme)
            // [2026-08-28 추가] 사용자 요청 — "처음 설치하시는 사람을 위한
            // 가이드 화면이 필요함." 앱 최초 실행 시 1회, 5페이지 안내 카루셀을
            // 보여준다 — AppOnboardingOverlay.swift 참고. `.bibleIndexOnboarding()`
            // 보다 먼저 배치해 "앱 소개 → (필요 시) 색인 안내" 순서로 자연스럽게
            // 읽히게 했다.
            //
            // [2026-09-03 수정] 여기 남겨 뒀던 "두 `.task`는 각각 독립적으로
            // 실행되므로 실제 기기에서 두 시트가 동시에 뜨려고 경합할
            // 가능성은 남아 있다"는 경고가 실제로 재현됐다 — 다른 Mac에 새로
            // 설치했을 때 온보딩 카루셀도 색인 안내 시트도 아닌, 내용 없는
            // 빈 시트만 뜨는 문제로 보고됨. `BibleIndexOnboardingOverlay.swift`
            // 쪽에서 색인 안내 "시트"만 온보딩이 끝난 뒤로 미루도록 고쳐 이
            // 경합을 없앴다(색인 자체는 여전히 온보딩과 무관하게 즉시
            // 시작함) — 그 파일의 `hasPendingSheet` 상단 주석 참고.
            .appOnboarding()
            // [2026-08-19 추가] 사용자 요청 — "앱을 설치할 때, 처음 시작할 때
            // 색인을 자동으로 설치하면 안되는가?" 최초 실행(또는 아직 색인이
            // 없는 실행) 1회, 성경 전체 임베딩 색인을 자동으로 시작하고 진행
            // 상황을 보여준다 — BibleIndexOnboardingOverlay.swift 참고. 아래
            // TranslationBootstrap 등 기존 부트스트랩 `.task`와는 독립적으로
            // 동작한다(서로 순서 의존성 없음 — 색인은 번들 DB를 직접 열어
            // 읽지 SwiftData 부트스트랩 결과를 필요로 하지 않는다).
            .bibleIndexOnboarding()
            // [2026-08-28 추가] 사용자 요청 — "업데이트 할때마다 어떤 것을
            // 업데이트 했는지 소개해주는 화면 필요함. 처음 설치하는 사람에게는
            // 필요하지 않음." `hasCompletedOnboarding`이 true인 기존 설치에서만,
            // 버전이 바뀌었을 때 해당 버전의 `WhatsNewContent` 항목을 보여준다 —
            // WhatsNewOverlay.swift 참고.
            .whatsNewOverlay()
            .task {
                // [2026-09-03 신설] 사용자 요청 — 온보딩 카루셀이 이 블록의
                // 진행 상태를 보여줄 수 있도록(`AppBootstrapProgress.swift`
                // 상단 주석 참고). `defer`로 걸어 성공/실패(catch) 어느 경로로
                // 끝나도 항상 한 번 내려간다.
                defer { AppBootstrapProgress.shared.markFinished() }
                do {
                    try TranslationBootstrap.ensureBundledTranslationRegistered(in: modelContext)
                    // [2026-08-14 추가, 같은 날 되돌림] "개역한글 국한문혼용을
                    // 두 번째 번들 번역본으로 등록"했던 것을, 사용자 요청으로 다시
                    // 없앤다 — "두 번째 번역본(국한문 전체 중복 테이블)을 지우고
                    // → 절 단위 한자 주석 모델"로 대체. 기존에 이미 등록된 사용자
                    // 기기에서는 `TranslationBootstrap.removeHanjaTranslationIfPresent`가
                    // 정리한다(TranslationBootstrap.swift 상단 주석 참고).
                    try TranslationBootstrap.removeHanjaTranslationIfPresent(in: modelContext)
                    // [2026-08-07 추가] TranslationBootstrap.deduplicateRegistries 상단
                    // 주석 참고 — CloudKit 다중 기기 초기 부트스트랩 경합으로 생길 수
                    // 있는 code 중복 TranslationRegistry를 앱이 뜰 때마다 정리한다.
                    try TranslationBootstrap.deduplicateRegistries(in: modelContext)
                    // [2026-08-13 추가] 사용자 요청 — 번들 기본 개요(OutlineSeed.sqlite,
                    // 있으면)를 사용자 DB로 1회 복사한다. `OutlineSeedImporter.swift`
                    // 상단 주석 참고 — 실패해도(throw하지 않고 내부에서 처리) 다른
                    // 부트스트랩을 막지 않는다.
                    await OutlineSeedImporter.importIfNeeded(into: modelContext)
                    // [2026-08-14 추가, 2026-08-15 방식 전환] 관주/난외주/한자주석/
                    // 한자사전 — 예전엔 여기서 CrossReferenceSeedImporter/
                    // MarginalNoteSeedImporter/HanjaAnnotationSeedImporter가 각각
                    // JSON→SwiftData 1회성 복사를 했다. 사용자 요청 — "성경관련
                    // json seed 파일은 기본 제공 db에 넣을 것." 이 네 데이터셋은
                    // 사용자가 편집하지 않는 정적 참조 데이터라 애초에 CloudKit
                    // 동기화 대상으로 삼을 이유가 없었다 — `Resources/
                    // ReferenceData.sqlite`(번들, 읽기 전용)에서 직접 읽도록
                    // 바꾸고(`ReferenceDataProvider`/`ReferenceDataStore` 참고),
                    // 세 임포터는 전부 삭제했다. 이전에 이미 SwiftData로 들어간
                    // 번들분(있다면)만 아래에서 1회성으로 정리한다.
                    ReferenceDataMigration.cleanupLegacyBundledRecords(in: modelContext)
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
    }
}

#Preview {
    // 프리뷰 캔버스는 실제 앱 Scene의 .modelContainer(_:)를 거치지 않으므로,
    // @Environment(\.modelContext)가 비어 있으면 여기서 크래시한다. 프리뷰 전용으로
    // 메모리 전용 컨테이너를 직접 붙여준다.
    ContentView()
        .modelContainer(try! BibleResearchSchema.makeSharedModelContainer(isStoredInMemoryOnly: true))
}
