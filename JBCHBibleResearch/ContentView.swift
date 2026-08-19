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
            // [2026-08-19 추가] 사용자 요청 — "앱을 설치할 때, 처음 시작할 때
            // 색인을 자동으로 설치하면 안되는가?" 최초 실행(또는 아직 색인이
            // 없는 실행) 1회, 성경 전체 임베딩 색인을 자동으로 시작하고 진행
            // 상황을 보여준다 — BibleIndexOnboardingOverlay.swift 참고. 아래
            // TranslationBootstrap 등 기존 부트스트랩 `.task`와는 독립적으로
            // 동작한다(서로 순서 의존성 없음 — 색인은 번들 DB를 직접 열어
            // 읽지 SwiftData 부트스트랩 결과를 필요로 하지 않는다).
            .bibleIndexOnboarding()
            .task {
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
                    OutlineSeedImporter.importIfNeeded(into: modelContext)
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
