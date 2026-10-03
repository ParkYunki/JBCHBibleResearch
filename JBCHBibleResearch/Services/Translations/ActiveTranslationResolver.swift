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
//  `isEnabled`는 더 이상 설정 화면이 쓰지 않는 예전 필드로, 목록이 비어 있을 때의 폴백에서만 읽는다.

import Foundation
import BibleResearchModels

@MainActor
enum ActiveTranslationResolver {
    /// 동시에 사용할 수 있는 최대 번역본 수(성경 조회 최대 열 수와 같다).
    nonisolated static let maxCount = 3

    /// `all` 중 이 기기에서 사용 중인 번역본을 순서대로(최대 `maxCount`개) 돌려준다.
    /// - 저장된 목록의 코드 순서를 따르고, 중복 코드는 한 번만, 아직 동기화로 도착하지 않아 레코드가 없는 코드는 건너뛴다(목록에서 지우지는 않는다).
    /// - 목록이 비었거나 하나도 매칭되지 않으면(최초 진입) 예전 규칙으로 대신한다: 활성(`isEnabled`) 번역본을 등록 순으로, `defaultTranslationCode`를 맨 앞으로.
    /// - 그래도 비면 번들 번역본을 쓴다(열이 하나도 없는 빈 화면을 막는다).
    static func resolve(from all: [TranslationRegistry]) -> [TranslationRegistry] {
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
}
