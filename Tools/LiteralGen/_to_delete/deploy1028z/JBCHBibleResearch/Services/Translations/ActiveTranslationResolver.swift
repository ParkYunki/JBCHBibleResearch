//
//  ActiveTranslationResolver.swift
//  JBCHBibleResearch
//
//  "사용 중인 번역본"(설정 > 번역본에서 스위치를 켠 번역본)을 한 곳에서 정한다 (2026-10-02, 설정 번역본 통합).
//
//  이전에는 "설치된 번역본" 스위치(`TranslationRegistry.isEnabled`, CloudKit으로 기기 간 동기화)와 "성경 조회 기본 표시"
//  목록(`UserSettingsStore.defaultDisplayedTranslationCodes`, 기기별 UserDefaults, 최대 3개·순서)이 따로 있어 "활성화"가 무엇을
//  뜻하는지 헷갈렸다. 지금은 후자 하나로 합쳤다 — 목록에 있으면 사용 중(성경 조회 열 후보, 번역본 선택 팝오버 후보, 통합검색 대상),
//  없으면 꺼짐이고 순서가 곧 열 순서다. 최대 3개.
//
//  ⚠️ 켜고 끄는 것은 "이미 추가된 번역본을 이 기기에서 보이게 할지"일 뿐이다. 번역본 추가·삭제(`TranslationRegistry` 레코드와
//  `sqliteData`의 CloudKit 동기화)는 건드리지 않고, 목록이 기기별이라 한 기기에서 끈다고 다른 기기가 꺼지지 않는다.
//  `isEnabled`는 더 이상 앱이 쓰지 않는 예전 필드로(스키마·CloudKit 호환 때문에 모델에는 남겨 둔다), 목록이 비어 있을 때의 폴백과
//  그 폴백 결과를 이 기기 목록으로 옮기는 1회 이행(`seedDeviceListIfNeeded(in:)`)에서만 읽는다.

import Foundation
import SwiftData
import BibleResearchModels

@MainActor
enum ActiveTranslationResolver {
    /// 동시에 사용할 수 있는 최대 번역본 수(성경 조회 최대 열 수와 같다).
    nonisolated static let maxCount = 3

    /// `all` 중 이 기기에서 사용 중인 번역본을 순서대로(최대 `maxCount`개) 돌려준다.
    /// - 저장된 목록의 코드 순서를 따르고, 중복 코드는 한 번만, 아직 동기화로 도착하지 않아 레코드가 없는 코드는 건너뛴다(목록에서 지우지는 않는다).
    /// - 목록이 비었거나 하나도 매칭되지 않으면(최초 진입) 예전 규칙으로 대신한다: 활성(`isEnabled`) 번역본을 등록 순으로, `defaultTranslationCode`를 맨 앞으로.
    /// - 그래도 비면 번들 번역본을 쓴다(열이 하나도 없는 빈 화면을 막는다).
    static func resolve(from allRegistries: [TranslationRegistry]) -> [TranslationRegistry] {
        // 다른 앱 언어의 번들 성경(동기화로 도착한 레코드)은 이 기기에서 보이지 않는다(`BundledTranslationCatalog`).
        let all = BundledTranslationCatalog.visible(allRegistries)
        let settings = UserSettingsStore.shared
        // 중복 code 행이 있어도 죽지 않게 첫 행을 쓴다.
        let byCode = Dictionary(all.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        var chosen: [TranslationRegistry] = []
        for code in settings.defaultDisplayedTranslationCodes where seen.insert(code).inserted {
            if let registry = byCode[code] { chosen.append(registry) }
        }
        if !chosen.isEmpty { return Array(chosen.prefix(maxCount)) }

        var ordered = all.filter(\.isEnabled).sorted { $0.addedAt < $1.addedAt }
        if let preferredCode = settings.defaultTranslationCode,
           let index = ordered.firstIndex(where: { $0.code == preferredCode }) {
            let preferred = ordered.remove(at: index)
            ordered.insert(preferred, at: 0)
        }
        if !ordered.isEmpty { return Array(ordered.prefix(maxCount)) }
        return Array(all.filter(\.isBundled).sorted { $0.addedAt < $1.addedAt }.prefix(maxCount))
    }

    /// 이 기기의 사용 중 목록(`defaultDisplayedTranslationCodes`)에 지금 보이는 번역본이 하나도 없으면(최초 실행, 목록이 생기기 전 버전에서
    /// 업데이트) 폴백 규칙(`resolve(from:)`)의 결과를 목록에 써 넣는다. 그 뒤로는 동기화되는 `isEnabled`가 바뀌거나 다른 기기에서 번역본이
    /// 추가돼도 이 기기의 켜짐/꺼짐이 따라 바뀌지 않는다(새로 도착한 번역본은 "꺼짐"으로 나타난다).
    /// 고른 번역본을 맨 앞에 두고, 기존 항목(지금 레코드가 없거나 보이지 않는 코드)은 중복 없이 뒤에 그대로 붙인다(잘라내지 않는다).
    /// - 앞에 두는 이유: 기존 항목이 앞에 있으면 그 번역본이 나중에 도착했을 때 방금 켠 번역본이 3개 밖으로 밀려 꺼진다.
    /// - 자르지 않는 이유: 앱 언어를 되돌려 예전 번들 번역본이 다시 보이면 자리가 남는 만큼 다시 켜진다. 목록을 읽는 곳(`resolve(from:)`,
    ///   설정의 `activeTranslations`, `BibleReadingViewModel.defaultDisplayedSelection`, `SearchViewModel.resolveActiveTranslations`)은
    ///   모두 레코드가 있는 code만 골라 `maxCount`(3)로 자르므로 목록이 길어도 사용 중은 최대 3개다.
    /// 번역본 레코드가 하나도 없으면(번들 등록 실패 등) 아무것도 쓰지 않아 다음 실행에서 다시 시도한다.
    static func seedDeviceListIfNeeded(in context: ModelContext) {
        guard let allRegistries = try? context.fetch(FetchDescriptor<TranslationRegistry>(sortBy: [SortDescriptor(\.addedAt)])) else { return }
        let visibleCodes = Set(BundledTranslationCatalog.visible(allRegistries).map(\.code))
        let settings = UserSettingsStore.shared
        guard !settings.defaultDisplayedTranslationCodes.contains(where: { visibleCodes.contains($0) }) else { return }
        let seeded = resolve(from: allRegistries).map(\.code)
        // 고를 번역본이 없으면(레코드 없음) 기존 목록을 그대로 둔다.
        guard !seeded.isEmpty else { return }
        var codes: [String] = []
        for code in seeded + settings.defaultDisplayedTranslationCodes where !codes.contains(code) {
            codes.append(code)
        }
        guard codes != settings.defaultDisplayedTranslationCodes else { return }
        settings.defaultDisplayedTranslationCodes = codes
    }
}
