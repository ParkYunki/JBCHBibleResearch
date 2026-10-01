//
//  AppBootstrapProgress.swift
//  JBCHBibleResearch
//
//  초기 데이터 준비(부트스트랩)가 진행 중인지를 온보딩 카루셀에 알리는 공유 상태.
//
//  `ContentView`의 부트스트랩 `.task`(TranslationBootstrap/OutlineSeedImporter/
//  ReferenceDataMigration)와 `AppOnboardingSheet`는 서로 독립된 뷰 계층이라 진행 상태를
//  직접 알 수 없다. 그래서 `AppNavigationRequest` 등과 같은 원칙(메모리 전용 `@Observable`
//  싱글턴)으로 값을 공유한다. 이벤트가 아니라 상태 자체라 카운터 대신 `Bool`을 쓴다.
//
//  ⚠️ 안내 문구를 보여주는 용도로만 쓴다. 메인 스레드를 오래 붙잡지 않게 하는 작업(주기적
//  `Task.yield()`)은 `OutlineSeedImporter`가 따로 하며, 이 플래그를 끈다고 그 작업이 빨라지지는 않는다.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppBootstrapProgress {
    static let shared = AppBootstrapProgress()

    /// 매 실행 초기값 `true`이며, `ContentView`의 부트스트랩 `.task`가 끝나면(성공/실패
    /// 무관) `markFinished()`가 `false`로 내린다. 이번 실행 동안의 상태일 뿐이라 영구
    /// 저장하지 않는다.
    private(set) var isPreparingInitialData = true

    private init() {}

    func markFinished() {
        isPreparingInitialData = false
    }
}
