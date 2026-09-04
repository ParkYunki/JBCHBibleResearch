//
//  AppBootstrapProgress.swift
//  JBCHBibleResearch
//
//  [2026-09-03 신설] 사용자 요청 — "아이폰 초기설치후 실행시 온보딩 메세지
//  하단에 다음버튼을 눌러도 십몇초 동안 반응이 없다가 나중에야 눌림." 문제를
//  고치며(`ContentView.swift`의 부트스트랩 `.task`, `OutlineSeedImporter.swift`
//  상단 주석 참고) 이어진 대화에서, "이 작업이 끝나기 전까지는 왜 반응이
//  느릴 수 있는지" 온보딩 카루셀에 짧은 안내(스피너+문구)를 보여 달라는
//  요청을 추가로 받았다.
//
//  `ContentView`의 부트스트랩 `.task`(TranslationBootstrap/OutlineSeedImporter/
//  ReferenceDataMigration)와 `AppOnboardingOverlay.swift`의 `AppOnboardingSheet`는
//  서로 다른 `.task`로 독립적으로 실행되는 별개의 뷰 계층이라, 후자가 전자의
//  진행 상태를 알 방법이 없다 — `AppNavigationRequest`/`SearchResultsPopRequest`
//  등과 같은 원칙(가벼운 메모리 전용 `@Observable` 싱글턴)으로 그 값을
//  하나 공유한다. 다만 이 값은 "이벤트 발생 여부"가 아니라 "지금 진행
//  중인지 아닌지"라는 상태 자체라 카운터 대신 단순 `Bool`을 쓴다.
//
//  ⚠️ [범위] 이 값은 온보딩 카루셀에 안내 문구를 보여주는 용도로만 쓴다 —
//  실제로 메인 스레드를 오래 붙잡지 않게 만드는 작업(주기적 `Task.yield()`)은
//  `OutlineSeedImporter.swift`/`EmbeddingIndexingService.swift`/`EmbeddingService.swift`
//  가 이미 따로 한다. 이 플래그를 끈다고 해서 그 작업들이 더 빨라지지는
//  않는다.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppBootstrapProgress {
    static let shared = AppBootstrapProgress()

    /// 앱을 실행할 때마다(매 실행 초기값 `true`) `ContentView`의 부트스트랩
    /// `.task`가 시작되고, 그 작업이 끝나면(성공/실패 무관) `markFinished()`가
    /// `false`로 내린다. 영구 저장하지 않는다 — 이번 실행 동안의 진행 상태일
    /// 뿐, `UserSettingsStore`의 "1회만 실행" 플래그들과는 성격이 다르다.
    private(set) var isPreparingInitialData = true

    private init() {}

    func markFinished() {
        isPreparingInitialData = false
    }
}
