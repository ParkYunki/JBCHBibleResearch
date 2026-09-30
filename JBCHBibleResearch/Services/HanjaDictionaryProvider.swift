//
//  HanjaDictionaryProvider.swift
//  JBCHBibleResearch
//
//  한자 한 글자 단위(음/훈) 사전. 번들 `ReferenceData.sqlite`의
//  `HanjaDictionary` 테이블을 `ReferenceDataProvider.shared.store`로
//  한 번 읽어 메모리에 캐시한다(`BooksProvider`와 같은 "번들 리소스 → 싱글턴 캐시" 패턴).
//
//  "이 절의 이 단어가 이 한자다"라는 절 단위 매핑은 이 사전이 아니라
//  `ReferenceDataStore.hanjaAnnotations(bookId:chapter:)`의
//  책임이다. 현재 이 사전을 호출하는 곳은
//  확대보기(`VerseZoomView.hanjaGlossSection`)뿐이다.
//

import Foundation
import BibleResearchModels

@MainActor
final class HanjaDictionaryProvider {
    static let shared = HanjaDictionaryProvider()

    /// 한 글자(Character) → 훈음 정보. 자소 결합이 다를 수 있으니 조회 쪽에서도
    /// 항상 이 사전을 만들 때 쓴 것과 같은 정규화(NFKC)를 거친 문자로 찾아야 한다
    /// (`character(for:)` 참고).
    private let byChar: [Character: HanjaCharacterInfo]

    private init() {
        guard let store = ReferenceDataProvider.shared.store else {
            print("[HanjaDictionaryProvider] ReferenceData.sqlite를 열 수 없어 한자 사전이 비어 있습니다.")
            byChar = [:]
            return
        }
        do {
            let entries = try store.allHanjaDictionaryEntries()
            byChar = Dictionary(uniqueKeysWithValues: entries.compactMap { entry -> (Character, HanjaCharacterInfo)? in
                guard let first = entry.char.first, entry.char.count == 1 else { return nil }
                return (first, entry)
            })
        } catch {
            print("[HanjaDictionaryProvider] 한자 사전 로드 실패: \(error)")
            byChar = [:]
        }
    }

    /// 한자 한 글자의 훈음 정보. 원본 코드포인트로 먼저 찾고, 없으면 NFKC 정규화 후 한 번 더
    /// 찾는다 — 테이블은 NFKC로 정규화해 만들었지만 주석 원본(`02개역국한문.bdb`)은 정규화 전
    /// 코드포인트를 쓸 수 있어서다.
    func info(for character: Character) -> HanjaCharacterInfo? {
        if let direct = byChar[character] { return direct }
        let normalized = String(character).precomposedStringWithCompatibilityMapping
        guard let normalizedChar = normalized.first else { return nil }
        return byChar[normalizedChar]
    }

    /// 여러 글자로 된 한자 문자열(예: "太初") 전체의 훈음 정보를 순서대로.
    /// 사전에 없는 글자는 건너뛴다(전부 없으면 빈 배열).
    func infoList(for hanja: String) -> [HanjaCharacterInfo] {
        hanja.compactMap { info(for: $0) }
    }
}
