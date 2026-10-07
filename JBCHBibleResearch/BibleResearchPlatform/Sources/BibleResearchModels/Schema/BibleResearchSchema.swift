import Foundation
import SwiftData

// SwiftData + CloudKit 공유 Swift Package — 3개 타겟이 동일한 데이터 레이어를 쓴다.
// BibleVerses/Books는 정적 참조 데이터라 CloudKit 동기화 대상이 아니므로 여기 포함하지 않고,
// 별도의 BibleReferenceStore(비-SwiftData, 원시 SQLite 읽기 전용)로 관리한다.

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
        // 말씀 요약 태그 조인 (Tags.swift)
        SummaryTag.self,
        // 연구문서 태그 조인 (Tags.swift)
        DocumentTag.self,
        // 설교 ↔ 태그 조인 (Tags.swift)
        SermonTag.self,
        // 설교 회차 사본 ↔ 태그 조인 (Tags.swift) — 회차마다 독립적인 태그
        SermonDeliveryTag.self,
        // 사용자 콘텐츠 (UserContent.swift)
        MemoFolder.self, UserMemo.self, BookOutline.self, ChapterSummary.self,
        LectureNote.self, Comparison.self,
        // 말씀 요약 — 개인 묵상과 별개의 저널형 모델 (UserContent.swift)
        VerseSummary.self,
        // 성경 조회 이력 (BibleReadingHistory.swift)
        BibleReadingHistoryEntry.self,
        // 성경 조회 책갈피 (BibleBookmark.swift)
        BibleBookmark.self,
        // 통합 검색 이력 (SearchHistory.swift)
        SearchHistoryEntry.self,
        // 문서 파이프라인 (Documents.swift)
        ImageCategory.self, SourceDocument.self, DocumentText.self, ConvertedPDF.self,
        OCRResult.self, DocumentMarkdown.self, DocumentAnchor.self,
        // 이미지 문서의 쪽 (Documents.swift) — 한 문서에 여러 장
        DocumentImagePage.self,
        // 구조 인덱스 (ReferenceIndex.swift)
        ThemeIndex.self, ThemeLink.self, KeywordOccurrence.self, PersonIndex.self,
        PlaceIndex.self, TimelineEvent.self,
        // 번역본 레지스트리
        TranslationRegistry.self,
        // 구간 주석 — 형광펜/표시/관주 (VerseAnnotations.swift)
        VerseHighlight.self, VerseCrossReference.self,
        // 구간 주석 — 특정 표현 부연설명 "메모" (VerseAnnotations.swift)
        VersePhraseNote.self,
        // 원문 정보 — 한글 뜻풀이 번역 캐시 (StrongGlossTranslation.swift)
        StrongGlossTranslation.self,
        // 메모/연구문서 안의 성경구절 추출 인덱스 (VerseMentions.swift)
        VerseMention.self,
        // 난외주(단어 뜻풀이/구약 인용 출처) — 번들분은 ReferenceData.sqlite에서 읽고, 이 모델은
        // 사용자가 직접 만든 난외주(source == .user)용이다.
        VerseMarginalNote.self,
        // 설교 관리 (Sermons.swift) — 설계 근거: claude/sermon-management-screens-and-schema.md(프로젝트 문서).
        Sermon.self, SermonDelivery.self, SermonGathering.self, SermonVerseReference.self,
        // 설교 마인드맵 (MindMaps.swift)
        MindMapNode.self,
    ]

    public static var schema: Schema {
        Schema(modelTypes)
    }

    /// macOS/iPadOS/iOS 3개 타겟이 공유하는 ModelContainer 생성 팩토리.
    /// iOS "뷰어 전용" 제한은 데이터 레벨이 아니라 화면(타겟 멤버십) 레벨에서 구현하므로
    /// 플랫폼 분기 없이 동일하게 쓰인다.
    ///
    /// - Parameter cloudKitContainerIdentifier: 기본값은 `defaultCloudKitContainerIdentifier`
    ///   (entitlements와 일치). 실제 Xcode 프로젝트의 CloudKit 컨테이너 설정과 반드시 일치해야 한다.
    /// - Parameter isStoredInMemoryOnly: true면 디스크에 남지 않는 임시 저장소(앱을 끄면 데이터 소실).
    /// - Parameter enableCloudKit: false면 디스크 저장은 유지한 채 CloudKit만 끈다
    ///   (`JBCHBibleResearchApp.init()`의 중간 단계 폴백용).
    public static func makeSharedModelContainer(
        cloudKitContainerIdentifier: String = defaultCloudKitContainerIdentifier,
        isStoredInMemoryOnly: Bool = false,
        enableCloudKit: Bool = true
    ) throws -> ModelContainer {
        // in-memory 전용 스토어는 CloudKit과 함께 쓸 수 없다 — isStoredInMemoryOnly == true인
        // ModelConfiguration에 cloudKitDatabase를 지정하면 ModelContainer 생성 시 에러를 던진다.
        // 그래서 in-memory이거나 enableCloudKit이 false면 `.none`으로 둔다.
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: (isStoredInMemoryOnly || !enableCloudKit) ? .none : .private(cloudKitContainerIdentifier)
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
