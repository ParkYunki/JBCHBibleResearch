//
//  ReferenceDataProvider.swift
//  JBCHBibleResearch
//
//  [2026-08-15 신설] 사용자 요청 — "성경관련 json seed 파일은 기본 제공 db에
//  넣을 것. 난외주/성경한자/한문사전/관주." `BibleResearchModels.ReferenceDataStore`
//  (패키지, 순수 SQLite 리더 — 앱 번들 경로를 모른다)를 실제로 여는 곳. 이
//  파일이 `Bundle.main.url(forResource: "ReferenceData", withExtension: "sqlite")`을
//  찾아 넘겨준다 — `TranslationBootstrap.resolvedBundledDatabaseURL()`과 같은
//  "번들 경로 해석은 앱 레이어 책임" 원칙(패키지는 어떤 앱에 얹혀도 재사용
//  가능하게 특정 Bundle에 의존하지 않는다).
//
//  `BooksProvider`와 같은 "번들 리소스 → 싱글턴 캐시" 패턴. `store`가 nil이면
//  (리소스 파일이 Xcode 타겟에 없거나 손상된 경우) 관주/난외주/한자주석/한자사전이
//  전부 "번들분 없음"으로 조용히 빈 결과를 내도록 호출부가 옵셔널 체이닝으로
//  처리한다 — `BooksProvider`가 books.json 로드 실패 시 빈 배열로 폴백하는 것과
//  같은 원칙(임의의 더미 데이터를 만들지 않는다).
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
