//
//  UserContentSearchIndexLocation.swift
//  JBCHBibleResearch
//
//  [2026-09-05 신설] 개요/메모/개인 묵상/말씀 요약/연구문서 5개 카테고리의
//  검색 전체 스캔을 줄이기 위해 도입한 FTS5 보조 인덱스(`UserContentSearchIndex`,
//  BibleResearchModels 패키지)가 실제로 저장될 디렉터리를 정하는 앱 레이어
//  정책. `BibleResearchModels` 패키지는 앱 타겟(이 프로젝트가 어떤 폴더
//  구조를 쓰는지)에 의존할 수 없다는 이유로 그 패키지의 `TranslationSearchIndex`/
//  `TranslationFileMaterializer`도 디렉터리는 항상 호출부(앱 레이어)가 넘겨
//  받는 구조다 — 이 파일은 그 규칙을 그대로 따라 `TranslationFileMaterializer.
//  translationsDirectory()`와 같은 패턴(Application Support 아래 전용 폴더)을
//  재사용한다.
//

import Foundation
import BibleResearchModels

@MainActor
enum UserContentSearchIndexLocation {
    /// 카테고리 태그 — `UserContentSearchIndex`의 `category` 컬럼에 그대로
    /// 들어간다. `VerseMentionSourceType`(memo/document/wordSummary 3종만
    /// 있음)과 달리 이 인덱스는 개요/장별개요/메모 문구까지 6종을 모두
    /// 다뤄야 해서 그 enum을 재사용하지 않고 이 전용 태그 집합을 새로 둔다
    /// (기존 enum을 억지로 확장하면 그 타입의 원래 책임 — VerseMention 추출
    /// 대상 판별 — 과 무관한 케이스가 섞여 오히려 혼란스럽다).
    enum Category: String {
        case outline
        case chapterSummary
        case memo
        case wordSummary
        case phraseNote
        case document
    }

    static func directory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let directory = base.appendingPathComponent("SearchIndex", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// [2026-09-05 신설] 저장 지점(자동저장 화면 이탈, 말씀메모 추가/수정 등)
    /// 여러 곳에서 반복될 "디렉터리 구하기 + 인덱스 갱신"을 한 줄로 줄인
    /// 편의 함수 — 실패해도(디스크 문제 등) 검색 자체가 막히면 안 되므로
    /// 조용히 무시한다(`SourceDocument.rebuildCachedCombinedText()` 호출부들과
    /// 같은 원칙 — 인덱스는 검색 속도를 위한 보조 수단일 뿐, 이게 실패했다고
    /// 저장 자체를 막거나 사용자에게 에러를 보여줄 이유가 없다. 인덱스가 없는
    /// 항목은 `SearchViewModel`의 자가 치유 백필이 다음 검색에서 다시 채운다).
    static func upsert(category: Category, sourceId: String, content: String) {
        guard let directory = try? directory() else { return }
        try? UserContentSearchIndex.upsert(
            category: category.rawValue, sourceId: sourceId, content: content, indexDirectory: directory
        )
    }

    /// [2026-09-05 신설] 항목이 완전히 삭제될 때(빈 메모 정리 등) 호출하는
    /// 정리용 편의 함수 — `BibleReferenceIndexingService.removeMentions`를
    /// 삭제 직전에 부르는 기존 호출부들과 같은 자리에 나란히 둔다. 위
    /// `UserContentSearchIndex.swift` 상단 주석대로 안 불러도 정확성엔
    /// 영향 없지만(존재하지 않는 항목의 후보는 검색 쪽 join에서 자연히
    /// 걸러짐), 이미 정리하는 자리이니 함께 지워 인덱스 파일이 죽은 행으로
    /// 불필요하게 커지는 것을 막는다.
    static func delete(category: Category, sourceId: String) {
        guard let directory = try? directory() else { return }
        try? UserContentSearchIndex.delete(category: category.rawValue, sourceId: sourceId, indexDirectory: directory)
    }
}
