//
//  TranslationBootstrap.swift
//  JBCHBibleResearch
//
//  번들 기본 번역본을 TranslationRegistry에 등록하는 앱 시작 시 부트스트랩.
//  번들 번역본도 레코드가 있어야 번역본 목록을 한 가지 방식으로 다룰 수 있지만, 이 레코드는 설치 시 저절로
//  생기지 않으므로 앱이 처음 뜰 때 한 번 심어 넣는다.
//
//  ⚠️ 번들 파일에 실제로 어떤 번역본이 들어있는지 확정되지 않아 code를 "KRV"로 가정했다.
//  다르면 표시 이름만 바꾸면 된다(BibleDB.sqlite 데이터에는 영향 없음).
//

import Foundation
import SwiftData
import BibleResearchModels

enum TranslationBootstrapError: Error, CustomStringConvertible {
    case bundledDatabaseNotFound
    case unknownBundledTranslationCode(String)

    var description: String {
        switch self {
        case .bundledDatabaseNotFound:
            return "앱 번들에서 BibleDB.sqlite를 찾을 수 없습니다. Xcode 타겟의 Copy Bundle Resources에 Resources/BibleDB.sqlite가 포함돼 있는지 확인하세요."
        case .unknownBundledTranslationCode(let code):
            return "알 수 없는 번들 번역본 코드입니다: \(code)"
        }
    }
}

@MainActor
enum TranslationBootstrap {
    /// TranslationRegistry.code 값 — 번들 기본 번역본을 가리키는 고정 코드.
    static let bundledTranslationCode = "KRV"

    /// 표시 이름. `code`("KRV")는 `BibleReferenceStore`의 version_code 매칭 등에서 참조할 수 있어 바꾸지 않는다.
    static let bundledDisplayName = "개역한글"

    /// 앱 번들 안의 BibleDB.sqlite 절대 경로를 찾는다. 설치 위치가 기기/버전마다
    /// 달라질 수 있어(특히 iOS 샌드박스), 저장된 문자열을 재사용하지 않고 매번
    /// Bundle.main에서 새로 조회한다 — TranslationRegistry.sqliteFileReference는
    /// 참고용으로만 채워두고, 실제 파일 열기는 항상 이 함수를 통한다.
    static func resolvedBundledDatabaseURL() throws -> URL {
        guard let url = Bundle.main.url(forResource: "BibleDB", withExtension: "sqlite") else {
            throw TranslationBootstrapError.bundledDatabaseNotFound
        }
        return url
    }

    // 국한문 번역본을 두 번째 번들 번역본으로 등록하던 것은 철회했다. 이 상수는 이미 등록된 레코드를
    // `removeHanjaTranslationIfPresent`가 찾아 지우는 데 쓴다. `BibleDB_Hanja.bdb`는 이제
    // `HanjaAnnotationSeed.json`/`HanjaDictionary.json`의 원천 자료로만 쓰인다.
    static let hanjaTranslationCode = "KRV_HANJA"
    static let hanjaDisplayName = "개역한글(국한문)"

    /// `code`에 맞는 번들 번역본 파일 경로를 찾는다. 코드→파일 매핑을 이 한 곳에서만 알아,
    /// 화면 레이어가 개별 번들 번역본의 존재를 몰라도 된다.
    static func resolvedBundledDatabaseURL(for code: String) throws -> URL {
        switch code {
        case bundledTranslationCode: return try resolvedBundledDatabaseURL()
        default: throw TranslationBootstrapError.unknownBundledTranslationCode(code)
        }
    }

    /// TranslationRegistry에 번들 번역본 레코드가 없으면 만든다. 앱 시작 시 한 번 호출하며, 이미 있으면 아무 것도 하지 않는다(멱등).
    /// CloudKit은 @Attribute(.unique)를 지원하지 않아 code 중복 삽입을 DB가 막지 못하므로,
    /// 호출부의 "앱 시작 시 1회" 규율이 유일한 방어선이다.
    static func ensureBundledTranslationRegistered(in context: ModelContext) throws {
        var descriptor = FetchDescriptor<TranslationRegistry>(
            predicate: #Predicate { $0.code == bundledTranslationCode }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            // 멱등 가드가 이름 변경을 막지 않도록, 이전 실행에서 만들어진 레코드의 displayName이 최신 값과 다르면 고쳐 쓴다.
            if existing.displayName != bundledDisplayName {
                existing.displayName = bundledDisplayName
                try context.save()
            }
            return
        }
        // 번들 리소스가 없으면(빌드 설정 누락 등) 조용히 넘어가지 않고 여기서 실패시켜 원인을 드러낸다.
        let url = try resolvedBundledDatabaseURL()
        let registry = TranslationRegistry(
            code: bundledTranslationCode,
            displayName: bundledDisplayName,
            isBundled: true,
            isUserAdded: false,
            licenseType: nil,
            sqliteFileReference: url.path,
            sqliteData: nil
        )
        context.insert(registry)
        try context.save()
    }

    /// 예전에 두 번째 번들 번역본으로 등록됐던 `KRV_HANJA` 레코드를 정리한다. 이미 그 레코드가 CloudKit에 만들어진
    /// 기기에 남으면 쓰지 않는 번역본 열이 계속 보이기 때문이다. `deduplicateRegistries`와 같은 자리(앱 시작 시 1회)에서 호출한다.
    static func removeHanjaTranslationIfPresent(in context: ModelContext) throws {
        let descriptor = FetchDescriptor<TranslationRegistry>(
            predicate: #Predicate { $0.code == hanjaTranslationCode }
        )
        let stale = try context.fetch(descriptor)
        guard !stale.isEmpty else { return }
        for registry in stale {
            context.delete(registry)
        }
        try context.save()
    }

    /// 같은 `code`의 `TranslationRegistry` 행이 여러 개면 하나만 남긴다. CloudKit은 `@Attribute(.unique)`를
    /// 지원하지 않아, 여러 기기가 서로의 레코드를 보기 전에 처음 실행되면 기기마다 "KRV" 행을 만들고
    /// 병합 후 중복이 남는다(같은 번역본이 여러 열에 나란히 보인다). 번들 항목이 있으면 번들을,
    /// 아니면 가장 먼저 추가된 것을 남긴다.
    static func deduplicateRegistries(in context: ModelContext) throws {
        let all = try context.fetch(FetchDescriptor<TranslationRegistry>(sortBy: [SortDescriptor(\.addedAt, order: .forward)]))
        let grouped = Dictionary(grouping: all, by: \.code)
        var didDelete = false
        for group in grouped.values where group.count > 1 {
            // `all`이 addedAt 오름차순이라 `group[0]`이 가장 먼저 추가된 것이다.
            let survivor = group.first(where: { $0.isBundled }) ?? group[0]
            for duplicate in group where duplicate.persistentModelID != survivor.persistentModelID {
                if !duplicate.isBundled {
                    TranslationFileMaterializer.removeLocalCopy(for: duplicate)
                }
                context.delete(duplicate)
                didDelete = true
            }
        }
        if didDelete {
            try context.save()
        }
    }
}
