//
//  TranslationBootstrap.swift
//  JBCHBibleResearch
//
//  근거: bible-research-platform-schema.md 6.7(TranslationRegistry), 1장(번들 기본 테이블).
//  번들 기본 번역본도 TranslationRegistry에 레코드가 있어야 S1 화면이 "등록된 번역본
//  목록"을 한 가지 방식으로 다룰 수 있다(번들/사용자 추가를 구분해서 따로 처리하지 않아도
//  됨). 하지만 이 레코드가 앱 설치 시 저절로 생기지는 않으므로, 앱이 처음 뜰 때(최초 1회)
//  이 타입이 TranslationRegistry에 번들 번역본 레코드를 심어 넣는 "부트스트랩" 역할을 한다.
//
//  ⚠️ [가정, 확인 필요] 번들 파일에 실제로 어떤 번역본이 들어있는지(개역한글/개역개정 등)
//  대화에서 확정된 적이 없다. schema.md 1장이 이 파일을 "번들 제공 KRV 스키마"라고 표현한
//  것이 유일한 단서라 code를 "KRV"로 썼다. 실제 번역본명이 다르면 표시 이름만 바꾸면
//  된다 — BibleDB.sqlite 데이터 자체에는 영향 없음.
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

    /// [2026-08-08 변경] 사용자 요청 — 표시 이름을 "개역 한글(KRV)"에서
    /// "개역한글"로 변경. `code`("KRV")는 그대로 둔다 — 다른 곳(예:
    /// `BibleReferenceStore`의 version_code 매칭)이 이 값을 참조할 수 있어
    /// 표시 이름만 바꾸는 것이 안전하다.
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

    // [2026-08-14 추가, 같은 날 두 번째 번역본 등록은 철회] `02개역국한문.bdb`를
    // 한때 두 번째 번들 번역본으로 등록했었다("국한문혼용과 개역한글은 내용이
    // 거의 동일하여 두 개를 같이 불러와서 쓰는게 효율적이지 않다"는 사용자 지적
    // 이후 철회). 이 코드는 더 이상 등록하지 않지만, 상수 자체는 아래
    // `removeHanjaTranslationIfPresent`가 예전에 이미 등록된 레코드를 찾아
    // 지우는 데 계속 쓴다 — `BibleDB_Hanja.bdb` 원본 데이터는 이제
    // `HanjaAnnotationSeed.json`/`HanjaDictionary.json`을 뽑아내는 원천 자료로만
    // 쓰인다(HanjaAnnotationSeedImporter.swift/HanjaDictionaryProvider.swift 참고).
    static let hanjaTranslationCode = "KRV_HANJA"
    static let hanjaDisplayName = "개역한글(국한문)"

    /// 여러 개로 늘어난 번들 번역본 중 `code`에 맞는 파일 경로를 찾는다.
    /// `BibleReadingViewModel`/`SearchViewModel`처럼 "번들이면 어떤 코드든 파일을
    /// 찾아 연다"는 화면 레이어가 개별 번들 번역본의 존재를 몰라도 되도록,
    /// 코드→파일 매핑은 이 한 곳에서만 안다. [2026-08-14 변경] 국한문 두 번째
    /// 번역본 등록을 철회하며 `bundledTranslationCode` 하나만 남았다 — 그래도
    /// 함수 형태(코드 문자열 → URL)는 그대로 유지해 `resolvedBundledDatabaseURL(for:
    /// registry.code)`를 그대로 쓰는 호출부(`BibleReadingViewModel`/
    /// `SearchViewModel`)를 되돌리지 않아도 되게 했다.
    static func resolvedBundledDatabaseURL(for code: String) throws -> URL {
        switch code {
        case bundledTranslationCode: return try resolvedBundledDatabaseURL()
        default: throw TranslationBootstrapError.unknownBundledTranslationCode(code)
        }
    }

    /// TranslationRegistry에 번들 번역본 레코드가 없으면 하나 만든다. 앱 시작 시
    /// (모델 컨테이너 생성 직후, 첫 화면이 뜨기 전) 한 번 호출하면 된다. 이미 있으면
    /// 아무 것도 하지 않는다(멱등) — CloudKit은 @Attribute(.unique)를 지원하지 않아
    /// code 중복 삽입을 DB 레벨에서 막을 수 없으므로, 호출부가 "앱 시작 시 1회"라는
    /// 규율을 지키는 것이 유일한 방어선이다.
    static func ensureBundledTranslationRegistered(in context: ModelContext) throws {
        var descriptor = FetchDescriptor<TranslationRegistry>(
            predicate: #Predicate { $0.code == bundledTranslationCode }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            // [2026-08-08 추가] 이미 이전 실행에서 이 레코드가 만들어졌다면(과거엔
            // displayName이 "개역 한글(KRV)"였다) 위 "이미 있으면 건너뛴다"는 멱등
            // 가드에 막혀 이름 변경이 반영되지 않는다 — 여기서 최신 값과 다르면
            // 고쳐 쓴다.
            if existing.displayName != bundledDisplayName {
                existing.displayName = bundledDisplayName
                try context.save()
            }
            return
        }
        // 번들 리소스가 실제로 없으면(빌드 설정 누락 등) 여기서 바로 실패시켜 원인을
        // 명확히 알 수 있게 한다 — 조용히 넘어가면 나중에 S1 화면에서 "성경 없음"으로만
        // 보여 원인 추적이 어려워진다.
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

    /// [2026-08-14 추가, 같은 날 되돌림] 한때 `ensureHanjaTranslationRegistered`가
    /// 국한문을 두 번째 번들 번역본으로 등록했었지만, 사용자 요청 — "두 번째
    /// 번역본(국한문 전체 중복 테이블)을 지우고 → 절 단위 한자 주석 모델"로
    /// 대체하며 그 함수를 없앴다. 이 함수는 그 사이(오늘 안에서만) 앱을 이미
    /// 실행해 `TranslationRegistry(code: "KRV_HANJA")`가 CloudKit에 이미 만들어진
    /// 기기를 위한 정리용이다 — 남아 있으면 S1 화면에 더 이상 쓰지 않는 번역본
    /// 열이 계속 보이게 된다. `deduplicateRegistries`와 같은 자리(둘 다 앱 시작
    /// 시 1회)에서 호출한다.
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

    /// [2026-08-07 추가] S1(성경 조회)에서 "3개 열에 전부 같은 번역본이 표시된다"는
    /// 제보를 조사하다가 찾은 근본 원인 — `ensureBundledTranslationRegistered`는
    /// 같은 프로세스 안에서는 멱등(이미 있으면 건너뜀)이지만, CloudKit이
    /// `@Attribute(.unique)`를 지원하지 않아(README "CloudKit 제약 적용" 절) 여러
    /// 기기에서 서로의 레코드를 아직 못 본 상태로 거의 동시에 처음 실행되면 기기마다
    /// 자기 몫의 "KRV" `TranslationRegistry` 행을 따로 만들어 버릴 수 있다. 나중에
    /// CloudKit이 병합하면 `code`가 같은 행이 여러 개 남는데, `BibleReadingViewModel`은
    /// "등록된 번역본 개수만큼 열을 그린다"는 원칙 자체는 정확히 지키고 있어서(코드
    /// 문제 아님), 결과적으로 서로 다른 행이지만 내용이 똑같은 번역본이 여러 열에
    /// 나란히 보이는 것처럼 보인다. `TranslationImportService.importTranslation`이
    /// "code는 앱 전체에서 유일해야 한다"는 규칙을 이미 전제하고 있으므로(가져오기
    /// 시점에 직접 중복 검사), 여기서도 같은 규칙으로 정리하는 것이 맞다 — 번들
    /// 항목이 섞여 있으면 번들을 남기고, 아니면 가장 먼저 추가된 것을 남긴다.
    static func deduplicateRegistries(in context: ModelContext) throws {
        let all = try context.fetch(FetchDescriptor<TranslationRegistry>(sortBy: [SortDescriptor(\.addedAt, order: .forward)]))
        let grouped = Dictionary(grouping: all, by: \.code)
        var didDelete = false
        for group in grouped.values where group.count > 1 {
            // `all`이 이미 addedAt 오름차순이라 group도 같은 순서를 유지한다 —
            // `group[0]`이 자연히 "가장 먼저 추가된 것"이다.
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
