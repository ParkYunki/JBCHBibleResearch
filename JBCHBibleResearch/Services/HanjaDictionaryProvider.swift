//
//  HanjaDictionaryProvider.swift
//  JBCHBibleResearch
//
//  [2026-08-14 신설] 사용자 요청 — "한자도, 각 개별 한자 정보까지 제공하기를
//  원함." 앱 번들에서 한 번만 읽어 메모리에 캐시해 둔다. `BooksProvider`와
//  같은 "번들 리소스 → 싱글턴 캐시" 패턴.
//
//  [2026-08-15 변경] 사용자 요청 — "성경관련 json seed 파일은 기본 제공 db에
//  넣을 것 ... 한문사전." `Resources/HanjaDictionary.json`을 직접 읽던 것을,
//  `Resources/ReferenceData.sqlite`(번들, 읽기 전용)의 `HanjaDictionary` 테이블에서
//  `ReferenceDataProvider.shared.store?.allHanjaDictionaryEntries()`로 읽어 오도록
//  바꿨다 — 공개 API(`info(for:)`/`infoList(for:)`)는 그대로라 이 타입을 호출하는
//  쪽은 손댈 필요가 없었다.
//  `HanjaCharacterInfo` 자체도 이제 `BibleResearchModels` 패키지가 정의한다
//  (`ReferenceDataStore`의 반환 타입과 공유).
//
//  이 사전은 글자 단위(음/훈)만 담당한다 — "이 절의 이 단어가 이 한자다"라는
//  절 단위 매핑은 `ReferenceDataStore.hanjaAnnotations(bookId:chapter:)`의
//  책임이다.
//  [2026-08-15 변경] 사용자 요청 — "한자 주석표시: 탭하면 보기 - 구절을
//  선택하면 해당 구절만 국한문 혼용으로 표시." 메인 읽기 화면
//  (`TranslationColumnView`)의 한자 팝오버(단어+훈음 나열)를 없애고 절 선택 시
//  인라인 한자 표시로 바꿨다 — 이 사전을 실제로 호출하는 곳은 이제 확대보기
//  (`VerseZoomView.hanjaGlossSection`) 하나뿐이다.
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

    /// 한자 한 글자의 훈음 정보. 원본 코드포인트를 그대로 쓰되(NFKC 정규화 없이
    /// 먼저 시도), 못 찾으면 정규화 후 한 번 더 찾는다 — `HanjaDictionary` 테이블
    /// 생성 시 NFKC로 정규화해 뒀는데(README "이어서 60" — 호환용 한자 코드포인트
    /// 이슈), 주석 원본(`02개역국한문.bdb`)은 정규화 전 코드포인트를 쓸 수도
    /// 있어서다.
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
