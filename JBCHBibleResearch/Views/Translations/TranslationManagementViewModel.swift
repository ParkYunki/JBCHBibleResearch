//
//  TranslationManagementViewModel.swift
//  JBCHBibleResearch
//
//  S12(번역본 관리) 화면의 상태. 목록 로드 시 사용자 추가 번역본을 하나씩
//  materialize 시도한다(TranslationFileMaterializer 참고) — CloudKit 동기화로
//  이 기기에 막 도착해 sqliteFileReference가 아직 로컬 경로를 가리키지 않는
//  레코드를 화면에 들어오는 시점에 "치유"해서, S1/S11이 나중에 그냥 열 수 있게
//  만든다.
//

import Foundation
import SwiftData
import Observation
import BibleResearchModels

@MainActor
@Observable
final class TranslationManagementViewModel {
    struct Row: Identifiable {
        let registry: TranslationRegistry
        var id: PersistentIdentifier { registry.persistentModelID }
        /// materialize 시도 결과. nil이면 정상(로컬에서 바로 열 수 있음).
        var materializationErrorDescription: String?
    }

    private(set) var rows: [Row] = []
    var lastErrorDescription: String?
    var isImportSheetPresented = false

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func onAppear() { reload() }

    func reload() {
        do {
            let registries = try modelContext.fetch(
                FetchDescriptor<TranslationRegistry>(sortBy: [SortDescriptor(\.addedAt, order: .forward)])
            )
            rows = registries.map { registry in
                var materializationError: String?
                if !registry.isBundled {
                    do {
                        _ = try TranslationFileMaterializer.ensureMaterialized(registry, context: modelContext)
                    } catch {
                        // [2026-08-07 수정, 컴파일러 경고로 발견] `error as?
                        // CustomStringConvertible`은 Apple 플랫폼에서 모든 Error가
                        // NSError로 브리징돼 "항상 성공하는 캐스팅"이라는 경고가 떴다.
                        // `ensureMaterialized`가 던지는 `TranslationMaterializationError`는
                        // 이미 `LocalizedError`를 채택하고 있으니(위 파일들 README
                        // "CustomStringConvertible-only 에러 타입" 절 참고) 그 경로를
                        // 먼저 쓰고, 아니면 `String(describing:)`으로 대체한다
                        // (TranslationImportService.describe(_:)와 같은 원칙).
                        materializationError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                    }
                }
                return Row(registry: registry, materializationErrorDescription: materializationError)
            }
        } catch {
            lastErrorDescription = "번역본 목록을 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// 번들 번역본은 삭제 대상이 아니다 — 호출부(뷰)가 UI에서 애초에 삭제 버튼을
    /// 숨기지만, 여기서도 한 번 더 막아 실수로 지워지는 걸 방지한다.
    func delete(_ registry: TranslationRegistry) {
        guard !registry.isBundled else { return }
        TranslationFileMaterializer.removeLocalCopy(for: registry)
        modelContext.delete(registry)
        do {
            try modelContext.save()
        } catch {
            lastErrorDescription = "번역본을 삭제하지 못했습니다: \(error.localizedDescription)"
        }
        reload()
    }

    /// S1 다중 번역본 컬럼 헤더에 반영되는 책이름표 언어(BookNameTableProvider 참고).
    /// 번들 번역본도 원칙적으로는 바꿀 수 있게 막지 않는다 — 6.7이 "번들은 항상
    /// nil"이라 정했을 뿐 사용자가 바꾸는 것 자체를 금지한 근거는 없어서다.
    func setBookNameTable(_ tableID: String?, for registry: TranslationRegistry) {
        registry.bookNameTableID = tableID
        do {
            try modelContext.save()
        } catch {
            lastErrorDescription = "책이름표 설정을 저장하지 못했습니다: \(error.localizedDescription)"
        }
        reload()
    }

    /// [2026-08-07 추가, 원본 문서 재확인으로 발견한 누락] screens.md S12 "목록에서
    /// 삭제/**편집**" — 지금까지 이 화면은 삭제와 책이름표 변경만 있고 표시
    /// 이름·라이선스를 고치는 길이 없었다. `reload()`를 다시 부르지 않는다 —
    /// `row.registry`가 이미 이 인스턴스를 그대로 참조하고 있어(SwiftData `@Model`
    /// 관찰 대상) 값을 바로 바꾸기만 해도 화면이 갱신된다. 매 타자마다 전체 목록을
    /// 다시 훑고 66권 순회하는 `ensureMaterialized`까지 재실행하면(= `reload()`)
    /// 타이핑이 버벅일 수 있어 의도적으로 뺐다.
    func updateDisplayName(_ name: String, for registry: TranslationRegistry) {
        registry.displayName = name
        try? modelContext.save()
    }

    /// 위와 동일한 이유로 `reload()` 없이 즉시 반영. 빈 문자열은 "라이선스 미상"
    /// 표시로 되돌아가도록 nil로 정규화한다.
    func updateLicenseType(_ license: String, for registry: TranslationRegistry) {
        let trimmed = license.trimmingCharacters(in: .whitespacesAndNewlines)
        registry.licenseType = trimmed.isEmpty ? nil : trimmed
        try? modelContext.save()
    }

    func handleImported(_ registry: TranslationRegistry) {
        reload()
    }
}
