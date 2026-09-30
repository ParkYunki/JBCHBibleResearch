//
//  ReferenceDataMigration.swift
//  JBCHBibleResearch
//
//  1회성 정리: 관주/난외주 번들분은 이제 `ReferenceData.sqlite`에서 매번 읽으므로, 예전에 SwiftData로 복사해 둔
//  번들분 레코드(`sourceRaw == bundled`)를 지운다. 그대로 두면 화면에 두 번씩(SwiftData 1개 + SQLite 1개)
//  나타난다. 플래그(`hasCleanedUpLegacyBundledReferenceData`)로 1회만 실행한다.
//
//  ⚠️ `VerseHanjaAnnotation`(구 한자 주석)은 타입 자체가 스키마(`BibleResearchSchema.modelTypes`)에서 삭제돼
//  `FetchDescriptor`를 만들 수 없으므로 정리하지 못한다. 실사용자 배포 이력이 없는 테스트 데이터라 건너뛴다.
//  CloudKit에 고아 레코드가 남을 수 있으나, 스키마에 없는 타입이라 앱이 읽지 않고 크래시도 나지 않는다.
//

import Foundation
import SwiftData
import BibleResearchModels

@MainActor
enum ReferenceDataMigration {
    static func cleanupLegacyBundledRecords(in context: ModelContext) {
        guard !UserSettingsStore.shared.hasCleanedUpLegacyBundledReferenceData else { return }
        defer { UserSettingsStore.shared.hasCleanedUpLegacyBundledReferenceData = true }

        let bundledRaw = VerseCrossReferenceSource.bundled.rawValue
        var didDelete = false

        if let staleCrossReferences = try? context.fetch(
            FetchDescriptor<VerseCrossReference>(predicate: #Predicate { $0.sourceRaw == bundledRaw })
        ), !staleCrossReferences.isEmpty {
            for record in staleCrossReferences { context.delete(record) }
            didDelete = true
            print("[ReferenceDataMigration] 레거시 번들 관주 \(staleCrossReferences.count)건 정리")
        }

        if let staleMarginalNotes = try? context.fetch(
            FetchDescriptor<VerseMarginalNote>(predicate: #Predicate { $0.sourceRaw == bundledRaw })
        ), !staleMarginalNotes.isEmpty {
            for record in staleMarginalNotes { context.delete(record) }
            didDelete = true
            print("[ReferenceDataMigration] 레거시 번들 난외주 \(staleMarginalNotes.count)건 정리")
        }

        if didDelete {
            try? context.save()
        }
    }
}
