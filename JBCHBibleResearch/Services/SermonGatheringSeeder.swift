//
//  SermonGatheringSeeder.swift
//  JBCHBibleResearch
//
//  [2026-09-28 신설] 설계 문서(claude/sermon-management-screens-and-schema.md,
//  프로젝트) 확정사항 — "SermonGathering 초기 시드값: 주일설교, 청년회 말씀,
//  구역모임, 조모임 4개를 최초 실행 시 미리 생성해 둔다." `OutlineSeedImporter`/
//  `TranslationBootstrap`과 같은 "run-once, UserSettingsStore 플래그로 1회만"
//  패턴을 그대로 따른다 — 다만 이 데이터는 파일에서 읽어오는 게 아니라(그럴
//  만큼 크지 않다) 코드에 직접 적힌 4개 문자열이라 별도 JSON/시드 파일을 두지
//  않는다. `TranslationBootstrap.deduplicateRegistries(in:)`/`ReferenceDataMigration
//  .cleanupLegacyBundledRecords(in:)`처럼 비동기가 필요 없는 가벼운 작업이라
//  `async`로 만들지 않았다(ContentView.swift의 부트스트랩 `.task`에서 `await`
//  없이 호출한다).
//

import Foundation
import SwiftData
import BibleResearchModels

@MainActor
enum SermonGatheringSeeder {
    static let defaultNames = ["주일설교", "청년회 말씀", "구역모임", "조모임"]

    static func seedIfNeeded(into context: ModelContext) {
        guard !UserSettingsStore.shared.hasSeededSermonGatherings else { return }
        do {
            let existing = try context.fetch(FetchDescriptor<SermonGathering>())
            let existingNames = Set(existing.map(\.name))
            for name in defaultNames where !existingNames.contains(name) {
                context.insert(SermonGathering(name: name))
            }
            try context.save()
        } catch {
            print("[SermonGatheringSeeder] 초기 모임 종류 시드 실패: \(error)")
        }
        // 저장 성공/실패와 무관하게 1회만 시도하도록 플래그를 올린다 — 실패해도
        // 사용자가 직접 모임 이름을 입력해 만들 수 있어(설계 문서 참고) 매번
        // 재시도할 필요는 없다(OutlineSeedImporter 등 기존 시더와 같은 원칙).
        UserSettingsStore.shared.hasSeededSermonGatherings = true
    }
}
