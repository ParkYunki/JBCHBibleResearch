import Foundation
import SwiftData
import Testing
@testable import BibleResearchModels

// 스키마 로드와 Tag 중복 방지에 대한 최소 스모크 테스트.
// CloudKit 실서버 왕복은 하지 않는다(로컬 in-memory ModelContainer만 검증).

@Suite("BibleResearchSchema")
struct BibleResearchSchemaTests {
    @Test("모든 모델 타입이 in-memory ModelContainer로 정상 로드된다")
    func schemaLoads() throws {
        let container = try BibleResearchSchema.makeSharedModelContainer(
            cloudKitContainerIdentifier: "iCloud.test.placeholder",
            isStoredInMemoryOnly: true
        )
        #expect(container.schema.entities.count == BibleResearchSchema.modelTypes.count)
    }

    @Test("Tag 생성 시 findOrCreateTag가 같은 정규화 이름에 대해 기존 레코드를 재사용한다")
    func findOrCreateTagDeduplicatesWithinSession() throws {
        let container = try BibleResearchSchema.makeSharedModelContainer(
            cloudKitContainerIdentifier: "iCloud.test.placeholder",
            isStoredInMemoryOnly: true
        )
        let context = ModelContext(container)

        let first = try TagDeduplication.findOrCreateTag(named: "은혜", context: context)
        let second = try TagDeduplication.findOrCreateTag(named: "  은혜  ", context: context)

        #expect(first.id == second.id)
    }

    @Test("병합된 태그는 findOrCreateTag 대상에서 제외된다")
    func mergedTagIsExcludedFromLookup() throws {
        let container = try BibleResearchSchema.makeSharedModelContainer(
            cloudKitContainerIdentifier: "iCloud.test.placeholder",
            isStoredInMemoryOnly: true
        )
        let context = ModelContext(container)

        let winner = try TagDeduplication.findOrCreateTag(named: "믿음", context: context)
        let loser = Tag(name: "믿음", normalizedForm: "믿음", createdAt: .now)
        loser.mergedIntoId = winner.id
        context.insert(loser)

        let resolved = try TagDeduplication.findOrCreateTag(named: "믿음", context: context)
        #expect(resolved.id == winner.id)
    }
}
