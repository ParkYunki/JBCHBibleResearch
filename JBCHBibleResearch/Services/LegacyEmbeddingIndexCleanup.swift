//
//  LegacyEmbeddingIndexCleanup.swift
//  JBCHBibleResearch
//
//  의미(임베딩) 검색을 제거하기 전 버전이 사용자 기기에 만들어 둔 성경 임베딩 색인
//  (`Application Support/BibleVerseEmbeddingIndex`, 약 95MB)을 정리한다. 더는 아무 코드도
//  읽지 않는 파일이라 남겨 두면 저장공간만 차지한다. 캐시성 데이터(번들 DB로 언제든 재생성 가능했던
//  파생 데이터)이므로 사용자 입력 데이터와 무관하다.
//

import Foundation

enum LegacyEmbeddingIndexCleanup {
    /// 폴더가 없으면 아무 일도 하지 않는다. 실패해도 앱 동작과 무관하므로 에러는 무시한다.
    static func run() {
        Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
            let directory = base.appendingPathComponent("BibleVerseEmbeddingIndex", isDirectory: true)
            guard fileManager.fileExists(atPath: directory.path) else { return }
            try? fileManager.removeItem(at: directory)
        }
    }
}
