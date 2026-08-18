//
//  ReferenceDataMigration.swift
//  JBCHBibleResearch
//
//  [2026-08-15 신설] 사용자 요청 — "성경관련 json seed 파일은 기본 제공 db에
//  넣을 것. 난외주/성경한자/한문사전/관주." 관주/난외주의 번들분을
//  `CrossReferenceSeedImporter`/`MarginalNoteSeedImporter`(둘 다 이번에 삭제)로
//  SwiftData에 이미 복사해 넣은 적이 있다면(이 세션 안에서 실제로 그랬다),
//  이제 그 번들분은 `ReferenceData.sqlite`에서 매번 새로 읽어 오므로 SwiftData
//  쪽에 남은 옛 레코드는 그대로 두면 화면에 두 번씩(SwiftData 1개 + SQLite 1개)
//  나타난다 — 1회성으로 지운다. `OutlineSeedImporter` 등과 같은 "1회 실행 후
//  플래그로 다시 안 함" 패턴.
//
//  ⚠️ [범위] `VerseHanjaAnnotation`(구 한자 주석 `@Model`)은 스키마
//  (`BibleResearchSchema.modelTypes`)에서 타입 자체를 통째로 지웠다 — 그래서
//  이 마이그레이션이 그 레코드까지 정리하지는 못한다(타입이 없으면
//  `FetchDescriptor`를 만들 수조차 없다). 이 타입은 오늘 이 세션 안에서만
//  만들어졌다 지워진 테스트용 데이터라(실사용자 배포 이력이 없다) 정리를
//  건너뛰어도 실질적 위험이 없다고 판단했다 — CloudKit에 소량의 고아
//  레코드가 남을 수 있지만, 스키마에 없는 타입이라 앱이 다시 읽어 오지도
//  않고 크래시도 나지 않는다(SwiftData/CloudKit이 조용히 무시한다).
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
