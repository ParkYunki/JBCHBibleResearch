//
//  UserContentSearchIndexLocation.swift
//  JBCHBibleResearch
//
//  개요/메모/개인 묵상/말씀 요약/연구문서 등 사용자 콘텐츠 검색용 FTS5 보조 인덱스
//  (`UserContentSearchIndex`, BibleResearchModels 패키지)가 저장될 디렉터리를 정하는
//  앱 레이어 정책. 패키지는 앱의 폴더 구조에 의존할 수 없어 디렉터리를 항상 호출부가
//  넘기며, `TranslationFileMaterializer.translationsDirectory()`와 같은 패턴
//  (Application Support 아래 전용 폴더)을 따른다.
//

import Foundation
import BibleResearchModels

@MainActor
enum UserContentSearchIndexLocation {
    /// 카테고리 태그 — `UserContentSearchIndex`의 `category` 컬럼에 그대로 들어간다.
    /// `VerseMentionSourceType`은 대상이 달라(3종) 재사용하지 않고 전용 태그 집합을 둔다.
    enum Category: String {
        case outline
        case chapterSummary
        case memo
        case wordSummary
        case phraseNote
        case document
        /// 첫 `searchSermons` 호출 시 자가 치유 백필된다(`contentCandidateSourceIds` 참고).
        case sermon
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

    /// "디렉터리 구하기 + 인덱스 갱신"을 한 줄로 줄인 편의 함수. 인덱스는 검색 속도용 보조
    /// 수단이므로 실패해도 조용히 무시한다 — 누락 항목은 `SearchViewModel`의 자가 치유
    /// 백필이 다음 검색에서 다시 채운다.
    static func upsert(category: Category, sourceId: String, content: String) {
        guard let directory = try? directory() else { return }
        try? UserContentSearchIndex.upsert(
            category: category.rawValue, sourceId: sourceId, content: content, indexDirectory: directory
        )
    }

    /// 항목이 완전히 삭제될 때(빈 메모 정리 등) 호출하는 정리용 편의 함수. 안 불러도
    /// 정확성엔 영향 없지만(검색 join에서 걸러짐) 죽은 행으로 인덱스 파일이 커지는 것을 막는다.
    static func delete(category: Category, sourceId: String) {
        guard let directory = try? directory() else { return }
        try? UserContentSearchIndex.delete(category: category.rawValue, sourceId: sourceId, indexDirectory: directory)
    }
}
