//
//  ReferenceDataProvider.swift
//  JBCHBibleResearch
//
//  `BibleResearchModels.ReferenceDataStore`(순수 SQLite 리더 — 앱 번들 경로를 모른다)를 실제로 여는 곳.
//  `Bundle.main`에서 ReferenceData.sqlite를 찾아 넘긴다 — `TranslationBootstrap.resolvedBundledDatabaseURL()`과
//  같은 "번들 경로 해석은 앱 레이어 책임" 원칙이다(패키지가 특정 Bundle에 의존하지 않게 한다).
//
//  `BooksProvider`와 같은 "번들 리소스 → 싱글턴 캐시" 패턴. `store`가 nil이면(리소스가 타겟에 없거나 손상)
//  관주/난외주/한자주석/한자사전이 빈 결과가 되도록 호출부가 옵셔널 체이닝으로 처리한다(임의의 더미 데이터를
//  만들지 않는다).
//

import Foundation
import BibleResearchModels

@MainActor
final class ReferenceDataProvider {
    static let shared = ReferenceDataProvider()

    let store: ReferenceDataStore?

    private init() {
        guard let url = Bundle.main.url(forResource: "ReferenceData", withExtension: "sqlite") else {
            print("[ReferenceDataProvider] ReferenceData.sqlite가 번들에 없습니다 — 관주/난외주/한자주석/한자사전이 전부 비어 있게 됩니다.")
            store = nil
            return
        }
        do {
            store = try ReferenceDataStore(filePath: url.path)
        } catch {
            print("[ReferenceDataProvider] ReferenceData.sqlite 열기 실패: \(error)")
            store = nil
        }
    }
}
