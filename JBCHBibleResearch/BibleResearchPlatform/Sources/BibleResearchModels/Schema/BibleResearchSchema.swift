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
        // 설교 ↔ 태그 조인 (Tags.swift) — 2026-09-28 신설
        SermonTag.self,
        // 설교 회차 사본 ↔ 태그 조인 (Tags.swift) — 2026-09-29 신설, "회차마다 독립적인 태그"
        SermonDeliveryTag.self,
        // 사용자 콘텐츠 (UserContent.swift)
        MemoFolder.self, UserMemo.self, BookOutline.self, ChapterSummary.self,
        LectureNote.self, Comparison.self,
        // 말씀 요약 — 개인 묵상과 별개의 저널형 모델 (UserContent.swift) — 2026-08-12 신설
        VerseSummary.self,
        // 성경 조회 이력 (BibleReadingHistory.swift) — 2026-08-08 신설
        BibleReadingHistoryEntry.self,
        // 성경 조회 책갈피 (BibleBookmark.swift) — 2026-08-28 신설
        BibleBookmark.self,
        // 통합 검색 이력 (SearchHistory.swift) — 2026-09-04 신설
        SearchHistoryEntry.self,
        // 문서 파이프라인 (Documents.swift)
        ImageCategory.self, SourceDocument.self, DocumentText.self, ConvertedPDF.self,
        OCRResult.self, DocumentMarkdown.self, DocumentAnchor.self,
        // 구조 인덱스 (ReferenceIndex.swift)
        ThemeIndex.self, ThemeLink.self, KeywordOccurrence.self, PersonIndex.self,
        PlaceIndex.self, TimelineEvent.self,
        // [2026-08-19 삭제] EmbeddingChunk.self — 의미검색(AI) 기능 삭제(사용자
        // 요청)와 함께 뺐다. Models/Embedding.swift 상단 주석 참고.
        // 번역본 레지스트리
        TranslationRegistry.self,
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
        // 설교 관리 (Sermons.swift) — 2026-09-28 신설. 설계 근거:
        // claude/sermon-management-screens-and-schema.md(프로젝트 문서).
        Sermon.self, SermonDelivery.self, SermonGathering.self, SermonVerseReference.self,
        // 설교 마인드맵 (MindMaps.swift) — 2026-09-29 신설. 설계 근거: 대화 중
        // 확정된 "내 설교 마인드맵" 기능(Claude 아티팩트 HTML 목업 참고).
        MindMapNode.self,
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
    /// [2026-09-29 신설] 사용자 보고 — "'내 설교' 기능이 추가된 이후에 이전의
    /// 데이터가 삭제됨." 원인 추적 — `JBCHBibleResearchApp.init()`을 직접 읽어
    /// 보니, 이 팩토리가 (CloudKit 문제든 스키마 문제든) 어떤 이유로든 던지면
    /// 그 catch 분기가 곧장 `isStoredInMemoryOnly: true`(디스크에 전혀 안
    /// 남는 임시 저장소)로 폴백하고 있었다 — 그 분기 자신의 기존 주석에도
    /// "데이터는... 앱을 껐다 켜면 사라집니다"라고 이미 적혀 있다. 즉 지금
    /// 사용자가 겪은 증상과 정확히 일치하는 폴백 경로가 코드에 이미 존재했다.
    /// "내 설교" 기능이 `BibleResearchSchema.modelTypes`에 새 `@Model` 타입
    /// 6종(Sermon 등)을 추가한 게 이 스키마의 가장 최근 변경이라, `ModelContainer`
    /// 생성이 처음 실패하기 시작한 시점과 맞아떨어질 가능성이 가장 높다 —
    /// 다만 이 환경(Xcode/실기기 없음)에서는 실제 에러 메시지를 직접 볼 수
    /// 없어 정확한 원인(CloudKit 스키마 반영 문제인지, 그 6종 모델 자체의
    /// 다른 문제인지)까지는 확정하지 못했다. `enableCloudKit` 매개변수를
    /// 새로 둬, "CloudKit만 빼고 나머지는 그대로"인 중간 단계 폴백을
    /// `JBCHBibleResearchApp.init()`이 시도할 수 있게 한다 — 아래 참고.
    public static func makeSharedModelContainer(
        cloudKitContainerIdentifier: String = defaultCloudKitContainerIdentifier,
        isStoredInMemoryOnly: Bool = false,
        enableCloudKit: Bool = true
    ) throws -> ModelContainer {
        // [2026-09-29 수정] in-memory 전용 스토어는 CloudKit과 함께 쓸 수 없다 —
        // CloudKit 미러링은 디스크 기반 영구 저장소를 전제로 하며, SwiftData는
        // isStoredInMemoryOnly == true인 ModelConfiguration에 .private/.automatic
        // cloudKitDatabase를 함께 지정하면 ModelContainer 생성 시점에 에러를 던진다.
        // 기존 코드는 이 폴백(JBCHBibleResearchApp.init()의 catch 분기, "CloudKit
        // 동기화는 비활성 상태입니다" 주석 참고)에서도 항상 cloudKitDatabase를
        // 넘기고 있어, 주석이 말하는 의도("동기화 비활성" 상태로 계속 켜지는 것)와
        // 실제 동작(생성 자체가 실패)이 어긋나 있었다. isStoredInMemoryOnly이거나
        // enableCloudKit이 false면 cloudKitDatabase를 .none으로 둬 그 의도대로
        // 동작하게 한다 — `enableCloudKit: false` + `isStoredInMemoryOnly: false`
        // 조합이 바로 "디스크에는 그대로 남기고 CloudKit만 끈" 새 중간 폴백이다.
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: (isStoredInMemoryOnly || !enableCloudKit) ? .none : .private(cloudKitContainerIdentifier)
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
