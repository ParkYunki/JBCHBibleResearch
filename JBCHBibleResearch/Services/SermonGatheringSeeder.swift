//
//  SermonGatheringSeeder.swift
//  JBCHBibleResearch
//
//  SermonGathering 초기 시드값(주일설교, 청년회 말씀, 구역모임, 조모임)을 최초 실행 시
//  1회 생성한다. `OutlineSeedImporter`/`TranslationBootstrap`과 같은 run-once 패턴
//  (`UserSettingsStore` 플래그)이며, 데이터가 코드에 적힌 4개 문자열뿐이라 별도 시드
//  파일은 없다. 비동기가 필요 없어 `async`가 아니다(ContentView의 부트스트랩 `.task`에서
//  `await` 없이 호출).
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
        // 저장 성공/실패와 무관하게 1회만 시도하도록 플래그를 올린다 — 실패해도 사용자가
        // 직접 모임 이름을 입력해 만들 수 있어 재시도가 필요 없다.
        UserSettingsStore.shared.hasSeededSermonGatherings = true
    }
}
