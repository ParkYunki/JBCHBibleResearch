import Foundation
import SwiftData

// 근거: bible-research-platform-schema.md 0장/6장 — "SwiftData + CloudKit
// (ModelConfiguration) 공유 Swift Package, 3개 타겟이 동일 데이터 레이어 사용".
// BibleVerses/Books는 여기 포함되지 않는다 — 정적 참조 데이터라 CloudKit 동기화
// 대상이 아니며(schema.md 0장/1장), 별도의 BibleReferenceStore(비-SwiftData, 원시
// SQLite 읽기 전용 접근)로 관리한다.
//
// ⚠️ 이 파일은 Xcode + 실제 CloudKit 컨테이너 환경에서 검증되지 않았습니다.
// 특히 아래 항목은 실제 빌드 시 재확인이 필요합니다:
//   - Package.swift의 플랫폼 최소 버전(.macOS(.v15)/.iOS(.v18))은 SwiftData+CloudKit이
//     동작하는 최소 버전(대략 macOS 14/iOS 17 이상)을 넉넉히 잡은 추정치입니다.
//     실제 배포 타겟은 제품 정책에 따라 낮출 수 있습니다.
//   - CloudKit 컨테이너 식별자는 실제 프로젝트의 JBCHBibleResearch.entitlements에서
//     확인한 값(`iCloud.com.jbch.JBCHBibleResearch`)을 기본값으로 반영했습니다.

public enum BibleResearchSchema {
    /// 실제 프로젝트의 `JBCHBibleResearch.entitlements`에 등록된 iCloud 컨테이너
    /// 식별자. entitlements 쪽 값이 바뀌면 이 상수도 함께 갱신해야 한다.
    public static let defaultCloudKitContainerIdentifier = "iCloud.com.jbch.JBCHBibleResearch"

    /// 이 패키지가 다루는 모든 SwiftData 모델 타입의 단일 진실 공급원.
    /// 새 @Model을 추가하면 반드시 이 목록에도 추가해야 한다 — 빠뜨리면 그 모델은
    /// ModelContainer에 등록되지 않아 조용히 CloudKit 동기화에서 제외된다.
    public static let modelTypes: [any PersistentModel.Type] = [
        // 태그/관계 (Tags.swift)
        Tag.self, MemoTag.self, TagRelation.self,
        // 말씀 요약 태그 조인 (Tags.swift) — 2026-08-14 신설
        SummaryTag.self,
        // 연구문서 태그 조인 (Tags.swift) — 2026-08-16 신설
        DocumentTag.self,
        // 사용자 콘텐츠 (UserContent.swift)
        MemoFolder.self, UserMemo.self, BookOutline.self, ChapterSummary.self,
        LectureNote.self, Comparison.self,
        // 말씀 요약 — 개인 묵상과 별개의 저널형 모델 (UserContent.swift) — 2026-08-12 신설
        VerseSummary.self,
        // 성경 조회 이력 (BibleReadingHistory.swift) — 2026-08-08 신설
        BibleReadingHistoryEntry.self,
        // 문서 파이프라인 (Documents.swift)
        ImageCategory.self, SourceDocument.self, DocumentText.self, ConvertedPDF.self,
        OCRResult.self, DocumentMarkdown.self, DocumentAnchor.self,
        // 구조 인덱스 (ReferenceIndex.swift)
        ThemeIndex.self, ThemeLink.self, KeywordOccurrence.self, PersonIndex.self,
        PlaceIndex.self, TimelineEvent.self,
        // 임베딩 / 번역본 레지스트리
        EmbeddingChunk.self, TranslationRegistry.self,
        // 구간 주석 — 형광펜/표시/관주 (VerseAnnotations.swift) — 2026-08-08 신설
        VerseHighlight.self, VerseCrossReference.self,
        // 구간 주석 — 특정 표현 부연설명 "메모"(VerseAnnotations.swift) — 2026-08-11 신설
        VersePhraseNote.self,
        // 원문 정보 — 한글 뜻풀이 번역 캐시 (StrongGlossTranslation.swift) — 2026-08-09 신설
        StrongGlossTranslation.self,
        // 메모/연구문서 안의 성경구절 추출 인덱스 (VerseMentions.swift) — 2026-08-11 신설
        VerseMention.self,
        // 난외주(단어 뜻풀이/구약 인용 출처) — 2026-08-14 신설, MarginalNoteSeedImporter.swift 참고
        // [2026-08-15] 이제 "번들분"은 여기 SwiftData가 아니라 ReferenceData.sqlite에서
        // 읽는다 — 이 모델은 "사용자가 직접 만든 난외주"(source == .user, 아직 편집
        // UI는 없음)를 위한 자리로만 남는다.
        VerseMarginalNote.self,
        // [2026-08-15 삭제] VerseHanjaAnnotation.self — 위 VerseAnnotations.swift의
        // "삭제, 같은 날 되돌림" 주석 참고. ReferenceData.sqlite로 완전히 대체.
    ]

    public static var schema: Schema {
        Schema(modelTypes)
    }

    /// macOS/iPadOS/iOS 3개 타겟이 공유하는 ModelContainer 생성 팩토리.
    /// iOS "뷰어 전용" 제한은 데이터 레벨이 아니라 화면(타겟 멤버십) 레벨에서
    /// 구현한다(schema.md 6장) — 그래서 이 팩토리는 플랫폼 분기 없이 동일하게 쓰인다.
    ///
    /// - Parameter cloudKitContainerIdentifier: 기본값은 `defaultCloudKitContainerIdentifier`
    ///   (entitlements와 일치). 다른 값을 넘기면 그 값을 그대로 쓴다 — 실제 값은 Xcode
    ///   프로젝트의 CloudKit 컨테이너 설정과 반드시 일치해야 한다.
    public static func makeSharedModelContainer(
        cloudKitContainerIdentifier: String = defaultCloudKitContainerIdentifier,
        isStoredInMemoryOnly: Bool = false
    ) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
