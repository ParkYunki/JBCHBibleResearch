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

    /// 이름 비교용 키 — 앞뒤/가운데 공백, 대소문자, 전각/반각 차이를 무시한다("청년회 말씀"="청년회말씀").
    static func normalizedKey(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }

    /// 같은 이름의 `SermonGathering`을 하나로 합친다. CloudKit은 `@Attribute(.unique)`를 지원하지 않고 위 시드는 기기마다 1회씩 돌아,
    /// 기기끼리 동기화가 되기 전에 각각 시드하면 "구역모임" 같은 같은 이름의 행이 여러 개 남는다(모임 선택 시트에 칩이 중복돼 보임).
    /// 가장 먼저 만든 행을 남기고, 중복 행에 달린 모임 기록(`SermonDelivery`)은 남긴 행으로 옮긴 뒤 중복 행을 지운다.
    /// 이름이 비어 있는 행은 건드리지 않는다. 변경이 없으면 저장하지 않는다(여러 번 불러도 안전 — 멱등).
    /// 앱 시작 시와 모임 선택 시트가 열릴 때 부른다(그 사이 동기화로 도착한 중복까지 정리).
    static func deduplicate(in context: ModelContext) {
        do {
            let all = try context.fetch(FetchDescriptor<SermonGathering>(sortBy: [SortDescriptor(\.createdAt, order: .forward)]))
            var survivors: [String: SermonGathering] = [:]
            var didChange = false
            for gathering in all {
                let key = normalizedKey(gathering.name)
                guard !key.isEmpty else { continue }
                if let survivor = survivors[key] {
                    for delivery in gathering.deliveries ?? [] {
                        delivery.gathering = survivor
                    }
                    context.delete(gathering)
                    didChange = true
                } else {
                    survivors[key] = gathering
                }
            }
            if didChange { try context.save() }
        } catch {
            print("[SermonGatheringSeeder] 중복 모임 종류 정리 실패: \(error)")
        }
    }
}
