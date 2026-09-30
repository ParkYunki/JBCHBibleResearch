//
//  TranslationImportService.swift
//  JBCHBibleResearch
//
//  S12(번역본 관리) — 사용자가 고른 SQLite 파일을 검증하고 TranslationRegistry로 등록한다.
//  `TranslationImportError`(Services/BookNameTable.swift)를 실제로 던지는 호출부다.
//
//  ⚠️ 장 수 대조 등 검증 규칙은 `TranslationImportError.bookNumberingMismatch` 케이스가 있다는 사실에서
//  추론한 것으로, S12 스펙 원문에서 직접 확인한 규칙이 아니다.
//

import Foundation
import SwiftData
import BibleResearchModels

struct TranslationChapterMismatch: Identifiable {
    let bookId: Int
    let bookName: String
    let expectedChapters: Int
    let foundChapters: Int
    var id: Int { bookId }
}

struct TranslationFileValidation {
    let hasVersionCodeColumn: Bool
    /// `hasVersionCodeColumn`이 false면 항상 빈 배열(`BibleReferenceStore.availableVersionCodes`와 같은 규칙).
    let availableVersionCodes: [String]
    let chapterMismatches: [TranslationChapterMismatch]
}

@MainActor
enum TranslationImportService {
    /// 파일을 열어 읽을 수 있는지, BibleVerses 스키마를 갖고 있는지, 66권 정경 순서와 장 수가 맞는지 확인한다.
    /// 저장은 하지 않는다 — 화면이 결과를 보여준 뒤 `importTranslation`을 별도로 호출한다.
    static func validate(fileURL: URL) throws -> TranslationFileValidation {
        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer { if didAccess { fileURL.stopAccessingSecurityScopedResource() } }

        let store: BibleReferenceStore
        do {
            store = try BibleReferenceStore(filePath: fileURL.path)
        } catch BibleReferenceError.unrecognizedSchema(let path) {
            // BibleVerses/Bible 두 스키마 모두 아니면 파일을 못 연 것이 아니라 스키마가 다른 것이므로 구분해서 안내한다.
            throw TranslationImportError.invalidSchema(BibleReferenceError.unrecognizedSchema(path: path).description)
        } catch {
            throw TranslationImportError.fileNotReadable(describe(error))
        }

        let codes: [String]
        do {
            codes = try store.availableVersionCodes()
        } catch {
            // BibleVerses 테이블이 없거나 쿼리가 실패하면, SQLite 파일이지만 기대한 스키마가 아닌 경우다.
            throw TranslationImportError.invalidSchema(describe(error))
        }

        // 66권 전부 MAX(chapter)를 쿼리한다 — import는 파일당 한 번이라 66회 쿼리 비용은 문제되지 않는다.
        // version_code 컬럼이 있으면 코드별로 장 수 구조가 다를 이유가 없어 첫 번째 코드만 기준으로 삼는다.
        let referenceCode = store.hasVersionCodeColumn ? codes.first : nil
        var mismatches: [TranslationChapterMismatch] = []
        for book in BooksProvider.shared.books {
            // `try/catch`로 "쿼리 실패"(건너뜀)와 "쿼리는 성공했지만 이 책이 없음"(0장으로 기록)을 구분한다.
            // `guard let ... = try?`를 쓰면 책이 아예 빠진 경우가 조용히 무시된다.
            let found: Int
            do {
                found = try store.maxChapter(bookId: book.bookId, versionCode: referenceCode) ?? 0
            } catch {
                continue
            }
            if found != book.chapterCount {
                mismatches.append(TranslationChapterMismatch(
                    bookId: book.bookId, bookName: book.nameKo,
                    expectedChapters: book.chapterCount, foundChapters: found
                ))
            }
        }

        return TranslationFileValidation(
            hasVersionCodeColumn: store.hasVersionCodeColumn,
            availableVersionCodes: codes,
            chapterMismatches: mismatches
        )
    }

    /// 실제 등록. `validate(fileURL:)` 결과를 사용자에게 보여준 뒤 호출하는 것을 전제로 한다.
    /// 표준과 다른 정경 순서의 번역본이 있을 수 있어 장 수 불일치로 막지 않고, 최종 판단은 사용자에게 맡긴다.
    static func importTranslation(
        fileURL: URL,
        code: String,
        displayName: String,
        licenseType: String?,
        bookNameTableID: String?,
        context: ModelContext
    ) throws -> TranslationRegistry {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else { throw TranslationImportError.missingRequiredField("번역본 코드") }
        guard !trimmedName.isEmpty else { throw TranslationImportError.missingRequiredField("표시 이름") }

        // CloudKit이 @Attribute(.unique)를 지원하지 않아 DB 레벨 중복 방지가 불가능하므로 저장 전에 직접 검사한다
        // (`TranslationBootstrap.ensureBundledTranslationRegistered`와 같은 패턴).
        var descriptor = FetchDescriptor<TranslationRegistry>(predicate: #Predicate { $0.code == trimmedCode })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor), !existing.isEmpty {
            throw TranslationImportError.duplicateCode(trimmedCode)
        }

        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer { if didAccess { fileURL.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw TranslationImportError.fileNotReadable(describe(error))
        }

        let trimmedLicense = licenseType?.trimmingCharacters(in: .whitespacesAndNewlines)
        let registry = TranslationRegistry(
            code: trimmedCode,
            displayName: trimmedName,
            isBundled: false,
            isUserAdded: true,
            licenseType: (trimmedLicense?.isEmpty ?? true) ? nil : trimmedLicense,
            sqliteFileReference: "",
            sqliteData: data,
            bookNameTableID: bookNameTableID
        )

        // sqliteData(CKAsset 동기화용)와 별개로, 이 기기에서 바로 열 로컬 사본을 Application Support에 써 둔다
        // (`TranslationFileMaterializer` 참고).
        do {
            let localURL = try TranslationFileMaterializer.writeLocalCopy(data: data, registry: registry)
            registry.sqliteFileReference = localURL.path
        } catch {
            throw TranslationImportError.migrationFailed(describe(error))
        }

        context.insert(registry)
        do {
            try context.save()
        } catch {
            context.delete(registry)
            TranslationFileMaterializer.removeLocalCopy(for: registry)
            throw TranslationImportError.migrationFailed(describe(error))
        }
        return registry
    }

    // Error가 CustomStringConvertible이면 `String(describing:)`이 그 description을 그대로 쓰므로,
    // `as? CustomStringConvertible` 분기는 필요 없다(항상 성공하는 캐스팅 경고만 낳는다).
    private static func describe(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let message = localized.errorDescription {
            return message
        }
        return String(describing: error)
    }
}
