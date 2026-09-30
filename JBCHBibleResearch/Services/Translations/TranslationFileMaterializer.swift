//
//  TranslationFileMaterializer.swift
//  JBCHBibleResearch
//
//  동기화로 도착한 `sqliteData`를 이 기기의 Application Support에 실제 .sqlite 파일로 써내는 타입.
//  동기화된 Data를 SQLite로 바로 열 수 없고, `sqliteFileReference`는 이 기기에서만 유효한 로컬 경로라
//  다른 기기에서 추가된 번역본은 `sqliteData`만 도착한 상태가 되기 때문이다.
//
//  ⚠️ "sqliteFileReference가 가리키는 파일이 디스크에 없고 sqliteData는 있다"는 조건만으로 판단한다.
//

import Foundation
import SwiftData
import BibleResearchModels

/// `LocalizedError`도 채택한다 — `Error, CustomStringConvertible`만으로는 `error.localizedDescription`이
/// `.description`을 읽지 않고 Foundation의 일반 문구로 대체된다. 이 에러는 "동기화 중" 상태 문구의 통로라 정확한 문구가 표시돼야 한다.
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
    /// 사용자 추가 번역본의 로컬 사본 디렉터리. Documents는 사용자에게 노출되는 영역(파일 앱 등)이라 Application Support 아래 전용 폴더를 쓴다.
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

    /// import 시점에 실제 바이트를 로컬 캐시 파일로 써낸다. 반환된 경로를 `TranslationRegistry.sqliteFileReference`에 저장하면 된다.
    ///
    /// 로컬 사본을 새로 써내는 시점(import 직후, 또는 다른 기기에서 동기화돼 처음 materialize될 때)에
    /// `TranslationSearchIndex`(FTS5 보조 인덱스)도 한 번 빌드한다. 이미 로컬 사본이 있는 번역본은
    /// `ensureMaterialized`가 이 함수를 부르지 않으므로 인덱스를 백필하지 않는다.
    /// 인덱스 빌드 실패는 느린 LIKE 경로로 폴백할 수 있어(`SearchViewModel.searchVerses`) best-effort로 무시한다(`try?`).
    /// 인덱스 빌드에 `registry.code`가 필요해(version_code 컬럼이 있는 파일일 때) registry 전체를 받는다.
    @discardableResult
    static func writeLocalCopy(data: Data, registry: TranslationRegistry) throws -> URL {
        let url = try localFileURL(for: registry.id)
        try data.write(to: url, options: .atomic)

        if let sourceStore = try? BibleReferenceStore(filePath: url.path) {
            let versionCode = sourceStore.hasVersionCodeColumn ? registry.code : nil
            // 색인 생성 실패는 best-effort로 무시하므로 반환값(색인 파일 경로)은 명시적으로 버린다.
            _ = try? TranslationSearchIndex.ensureBuilt(
                sourceStore: sourceStore, registryID: registry.id,
                indexDirectory: url.deletingLastPathComponent(), versionCode: versionCode
            )
        }

        return url
    }

    /// `registry.sqliteFileReference`가 이 기기의 실제 파일을 가리키는지 확인하고, 없으면 `sqliteData`로 다시 써낸다.
    /// 성공 시 유효한 로컬 파일 경로를 반환한다.
    ///
    /// `context`는 새로 써낸 경로로 sqliteFileReference를 갱신해 다음부터 다시 materialize하지 않게 하려고 필요하다
    /// (이 필드는 기기마다 다시 생성되므로 동기화 대상이 아니다).
    static func ensureMaterialized(_ registry: TranslationRegistry, context: ModelContext) throws -> String {
        precondition(!registry.isBundled, "번들 번역본은 TranslationBootstrap.resolvedBundledDatabaseURL()로 직접 연다 — materialize 대상이 아니다.")

        if !registry.sqliteFileReference.isEmpty,
           FileManager.default.fileExists(atPath: registry.sqliteFileReference) {
            return registry.sqliteFileReference
        }

        guard let data = registry.sqliteData else {
            throw TranslationMaterializationError.noLocalCopyAvailable
        }

        let url = try writeLocalCopy(data: data, registry: registry)
        registry.sqliteFileReference = url.path
        try context.save()
        return url.path
    }

    /// 번역본 삭제 시 로컬 캐시 파일도 정리한다. best-effort — 실패해도 삭제를 막지 않는다(고아 파일이 남는 정도).
    static func removeLocalCopy(for registry: TranslationRegistry) {
        guard !registry.sqliteFileReference.isEmpty else { return }
        try? FileManager.default.removeItem(atPath: registry.sqliteFileReference)
    }

    /// 번역본의 동기화 상태를 보여주기 위한 순수 조회. `ensureMaterialized`와 달리 **아무것도 쓰지 않으므로**
    /// 목록을 그릴 때마다 부작용 없이 호출할 수 있다. 실제로 파일을 열어 읽을 때는 `ensureMaterialized`를 쓴다.
    enum SyncStatus: Equatable {
        /// 번들 정적 자산 — 동기화 개념이 없다.
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
