//
//  TranslationFileMaterializer.swift
//  JBCHBibleResearch
//
//  근거: bible-research-platform-schema.md 6.7(TranslationRegistry) + README.md
//  "🛠️ 런타임 오류 수정" 절 위쪽에 적힌 미해결 지점 — "동기화된 Data를 SQLite로
//  바로 열 수 없다. 동기화 완료 시점에 로컬 앱지원 디렉터리에 실제 .sqlite 파일로
//  한 번 써낸 뒤(sqliteFileReference 갱신) 열어야 한다"는 6.7 원문 요구를 실제
//  코드로 만든 것이다. S12(번역본 관리) 작업 전까지는 이 함수가 없어도 문제가
//  드러나지 않았다 — 지금까지 등록된 번역본이 번들 하나뿐이라 sqliteData가 채워질
//  일이 없었기 때문이다(TranslationBootstrap은 sqliteData: nil로 만든다). S12로
//  사용자 추가 번역본이 실제로 생기고, 그 레코드가 다른 기기로 CloudKit 동기화되면
//  sqliteFileReference(이 기기에서만 유효한 로컬 경로)는 그대로 안 맞고 sqliteData만
//  도착한 상태가 된다 — 이 타입이 그 간극을 메운다.
//
//  ⚠️ [범위, 검증 필요] 실제 CloudKit 동기화로 다른 기기에 sqliteData가 도착하는
//  과정 자체는 이 세션에서 실기기로 확인할 수 없다. 여기서는 "sqliteFileReference가
//  가리키는 파일이 이 기기 디스크에 없고 sqliteData는 있다"는 조건만으로 판단한다.
//

import Foundation
import SwiftData
import BibleResearchModels

/// `LocalizedError`도 함께 채택한다 — `Error, CustomStringConvertible`만 채택하면
/// `error.localizedDescription`(Swift 표준 프로퍼티, 많은 호출부가 관성적으로 씀)이
/// `.description`을 읽지 않고 Foundation의 일반 문구("작업을 완료할 수 없습니다")로
/// 대체돼 버린다 — README의 "기존 버그" 절에 이미 `BibleReferenceError`에서 같은
/// 함정을 발견해 기록해 뒀는데, 이 타입을 처음 만들 때 그 교훈을 놓쳤다. [2026-08-07,
/// 프로젝트 원본 문서 재확인 라운드] screens.md 4.3/6.7이 "새 기기에서 처음 받는
/// 동안은 S1/S12에 '동기화 중...' 로딩 상태가 필요하다"고 명시했는데, 이 에러가
/// 바로 그 상태를 표현하는 통로라 정확한 문구가 실제로 표시되는 게 중요하다.
enum TranslationMaterializationError: Error, LocalizedError, CustomStringConvertible {
    case noLocalCopyAvailable

    var description: String {
        switch self {
        case .noLocalCopyAvailable:
            return "이 번역본의 파일이 아직 이 기기에 없습니다(동기화 대기 중일 수 있습니다)."
        }
    }

    var errorDescription: String? { description }
}

@MainActor
enum TranslationFileMaterializer {
    /// 사용자 추가 번역본의 로컬 사본을 보관하는 디렉터리. Application Support 아래
    /// 전용 폴더를 쓴다 — Documents 디렉터리는 사용자에게 노출되는(파일 앱 등) 영역이라
    /// 내부 캐시 파일을 두기에 맞지 않다고 판단했다.
    static func translationsDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let directory = base.appendingPathComponent("Translations", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// `registryID`에 대응하는 로컬 파일 경로(파일이 실제로 존재하는지는 보장하지 않는다).
    static func localFileURL(for registryID: UUID) throws -> URL {
        try translationsDirectory().appendingPathComponent("\(registryID.uuidString).sqlite")
    }

    /// 가져오기(import) 시점에 실제 바이트를 로컬 캐시 파일로 써낸다. 반환된 경로를
    /// `TranslationRegistry.sqliteFileReference`에 저장하면 된다.
    @discardableResult
    static func writeLocalCopy(data: Data, registryID: UUID) throws -> URL {
        let url = try localFileURL(for: registryID)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// `registry.sqliteFileReference`가 이 기기에 실제로 존재하는 파일을 가리키는지
    /// 확인하고, 없으면 `sqliteData`로부터 다시 써낸다(동기화로 막 도착한 레코드).
    /// 성공 시 유효한 로컬 파일 경로 문자열을 반환한다 — 호출부(BibleReadingViewModel/
    /// SearchViewModel의 `store(for:)`)는 이 경로로 `BibleReferenceStore`를 연다.
    ///
    /// `context`가 필요한 이유: sqliteFileReference를 새로 써낸 경로로 갱신해
    /// 다음 호출부터는 다시 materialize할 필요가 없게 만들기 때문이다(이 필드 자체는
    /// 기기마다 다시 생성되므로 동기화 대상이 아니라는 6.7 정책과 일치 — README 참고).
    static func ensureMaterialized(_ registry: TranslationRegistry, context: ModelContext) throws -> String {
        precondition(!registry.isBundled, "번들 번역본은 TranslationBootstrap.resolvedBundledDatabaseURL()로 직접 연다 — materialize 대상이 아니다.")

        if !registry.sqliteFileReference.isEmpty,
           FileManager.default.fileExists(atPath: registry.sqliteFileReference) {
            return registry.sqliteFileReference
        }

        guard let data = registry.sqliteData else {
            throw TranslationMaterializationError.noLocalCopyAvailable
        }

        let url = try writeLocalCopy(data: data, registryID: registry.id)
        registry.sqliteFileReference = url.path
        try context.save()
        return url.path
    }

    /// 번역본 삭제 시 로컬 캐시 파일도 함께 정리한다(best-effort — 실패해도 삭제
    /// 자체를 막지 않는다, 디스크에 고아 파일이 남는 정도라 치명적이지 않다고 판단).
    static func removeLocalCopy(for registry: TranslationRegistry) {
        guard !registry.sqliteFileReference.isEmpty else { return }
        try? FileManager.default.removeItem(atPath: registry.sqliteFileReference)
    }

    /// [2026-08-07 추가] screens.md 4.3/6.7 — "새 기기에서 처음 받는 동안은 S1/S12에
    /// '동기화 중...' 로딩 상태가 필요합니다"를 화면(설정 8.3 탭, S12 관리 화면)에
    /// 표시하기 위한 순수 조회 함수. `ensureMaterialized`와 달리 **아무것도 쓰지
    /// 않는다**(파일 생성/저장 없음) — 목록을 그릴 때마다 부작용 없이 호출할 수
    /// 있어야 하기 때문이다. 실제로 파일을 열어 써야 하는 시점(S1/S11에서 본문을
    /// 읽을 때)에는 여전히 `ensureMaterialized`를 쓴다.
    enum SyncStatus: Equatable {
        /// 번들 정적 자산 — 애초에 동기화 개념이 없다(schema.md 0장/6장).
        case bundled
        /// 이 기기에 실제로 열 수 있는 로컬 파일이 있다.
        case available
        /// 로컬 파일은 없지만 CloudKit CKAsset(`sqliteData`)은 도착해 있다 — 다음
        /// `ensureMaterialized` 호출 시 로컬로 써낼 수 있는 "동기화 중" 상태.
        case pendingMaterialization
        /// 로컬 파일도 `sqliteData`도 없다 — 아직 CloudKit에서 이 레코드의 파일
        /// 자체가 도착하지 않은 상태(진짜 "동기화 대기")이거나, import가 비정상
        /// 종료된 경우.
        case notYetSynced

        var label: String {
            switch self {
            case .bundled: return "번들"
            case .available: return "동기화됨"
            case .pendingMaterialization: return "동기화 중…"
            case .notYetSynced: return "동기화 대기 중"
            }
        }
    }

    static func syncStatus(for registry: TranslationRegistry) -> SyncStatus {
        if registry.isBundled { return .bundled }
        if !registry.sqliteFileReference.isEmpty, FileManager.default.fileExists(atPath: registry.sqliteFileReference) {
            return .available
        }
        return registry.sqliteData != nil ? .pendingMaterialization : .notYetSynced
    }
}
