//
//  TranslationImportService.swift
//  JBCHBibleResearch
//
//  S12(번역본 관리) — 사용자가 고른 SQLite 파일을 검증하고 TranslationRegistry로
//  등록한다. `TranslationImportError`(Services/BookNameTable.swift, 이전 앱에서
//  이식된 대기 중 타입)를 실제로 던지는 첫 번째 호출부다.
//
//  ⚠️ [범위, 확인 필요] screens.md S12 원문 자체는 이 세션에 없다(다른 문서의
//  간접 언급으로만 재구성). 아래 검증 규칙(장 수 대조 등)은 원문이 미리 준비해 둔
//  `TranslationImportError.bookNumberingMismatch` 케이스가 있다는 사실에서
//  거꾸로 추론한 것이지, 원문에서 "이렇게 검증하라"고 직접 확인한 것이 아니다.
//  실제 S12 스펙 원문을 확인할 수 있게 되면 이 파일의 검증 규칙을 다시 대조해야 한다.
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
    /// `hasVersionCodeColumn`이 false면 항상 빈 배열(BibleReferenceStore.availableVersionCodes와
    /// 동일한 규칙).
    let availableVersionCodes: [String]
    let chapterMismatches: [TranslationChapterMismatch]
}

@MainActor
enum TranslationImportService {
    /// 선택된 파일을 열어 읽을 수 있는지, 기대하는 스키마(BibleVerses 테이블)를
    /// 갖고 있는지, 66권 정경 순서와 장 수가 맞는지 확인한다. 저장(import)은 하지
    /// 않는다 — 화면이 이 결과를 사용자에게 보여준 뒤 `importTranslation`을
    /// 별도로 호출한다.
    static func validate(fileURL: URL) throws -> TranslationFileValidation {
        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer { if didAccess { fileURL.stopAccessingSecurityScopedResource() } }

        let store: BibleReferenceStore
        do {
            store = try BibleReferenceStore(filePath: fileURL.path)
        } catch BibleReferenceError.unrecognizedSchema(let path) {
            // 2026-08-07: BibleReferenceStore가 이제 BibleVerses/Bible 두 스키마를
            // 알고 있다(BibleReferenceStore.swift 상단 주석 참고) — 둘 다 아니면
            // "파일을 못 연 것"이 아니라 "스키마가 다른 것"이므로 구분해서 안내한다.
            throw TranslationImportError.invalidSchema(BibleReferenceError.unrecognizedSchema(path: path).description)
        } catch {
            throw TranslationImportError.fileNotReadable(describe(error))
        }

        let codes: [String]
        do {
            codes = try store.availableVersionCodes()
        } catch {
            // BibleVerses 테이블 자체가 없거나 PRAGMA/쿼리가 실패하는 경우가 여기로
            // 온다 — "SQLite 파일이긴 하지만 우리가 기대하는 스키마가 아니다".
            throw TranslationImportError.invalidSchema(describe(error))
        }

        // 장 수 대조는 66권 전부 순회하며 MAX(chapter)를 쿼리한다 — import는 한 파일당
        // 한 번만 일어나는 작업이라 66회 쿼리 정도의 비용은 문제되지 않는다고 판단했다
        // (S11 색인처럼 반복 호출되는 경로가 아님, 오버엔지니어링 방지 원칙).
        // version_code 컬럼이 있는 파일은 첫 번째 코드만 기준으로 삼는다 — 코드별로
        // 장 수 구조가 달라질 이유가 없고, 코드마다 반복 검사하면 검증 시간만 배로
        // 늘어난다고 봤다.
        let referenceCode = store.hasVersionCodeColumn ? codes.first : nil
        var mismatches: [TranslationChapterMismatch] = []
        for book in BooksProvider.shared.books {
            // [2026-08-07 수정, 컴파일러 경고로 발견] `maxChapter`는 `Int?`를
            // 반환하는데(SE-0230에 따라 `try?`가 그 Optional을 한 겹 더 씌우지 않고
            // 평탄화한다), `guard let foundOrNil = try? ...`는 이미 그 한 겹을
            // 벗겨내 `foundOrNil`을 항상 `Int`(옵셔널 아님)로 만든다 — 그래서
            // "이 책 자체가 파일에 없으면 nil이 나와 0으로 대체한다"는 원래 의도가
            // 실제로는 절대 실행되지 않는 죽은 코드였다: 쿼리가 성공했지만 값이
            // nil이면(=이 책이 파일에 전혀 없음) guard 자체가 실패해 `continue`로
            // 건너뛰어버려, "책이 아예 빠져 있다"는 진짜 문제가 조용히 무시되고
            // 있었다. `try`/`catch`로 "쿼리 자체가 실패함"(건너뜀)과 "쿼리는
            // 성공했지만 이 책이 없음"(0장으로 기록)을 구분해 고쳤다.
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

    /// 실제 등록. `validate(fileURL:)`를 먼저 호출해 사용자에게 결과를 보여준 뒤
    /// 호출하는 것을 전제로 한다(이 함수 자체는 장 수 불일치를 이유로 막지 않는다 —
    /// 표준과 다른 정경 순서를 쓰는 번역본이 실제로 존재할 수 있어, 최종 판단은
    /// 사용자에게 맡긴다).
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

        // CloudKit이 @Attribute(.unique)를 지원하지 않아(README "CloudKit 제약 적용"
        // 절) DB 레벨 중복 방지가 불가능하다 — 저장 전에 직접 검사하는 것이 유일한
        // 방어선이다(TranslationBootstrap.ensureBundledTranslationRegistered와 같은 패턴).
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

        // sqliteData(CKAsset 동기화용)와는 별개로, 이 기기에서 바로 열어 쓸 수 있는
        // 로컬 사본을 Application Support에 써 둔다(TranslationFileMaterializer 참고 —
        // 6.7이 요구하는 "동기화 데이터는 로컬 파일로 한 번 써낸 뒤 열어야 한다"는
        // 규칙을 import 시점에도 동일하게 적용한 것).
        do {
            let localURL = try TranslationFileMaterializer.writeLocalCopy(data: data, registryID: registry.id)
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

    // [2026-08-07 수정, 컴파일러 경고로 발견] `error as? CustomStringConvertible`은
    // Apple 플랫폼에서 모든 Error가 NSError로 브리징 가능하고 NSError 자체가
    // CustomStringConvertible을 채택하고 있어 "항상 성공하는 캐스팅"이라는 경고가
    // 떴다 — 실제로 틀린 동작은 아니었지만(구체 타입이 진짜로 CustomStringConvertible을
    // 채택했으면 그 타입의 description이 그대로 쓰인다) 죽은 분기나 다름없었다.
    // `String(describing:)`이 CustomStringConvertible 채택 타입에 대해서는 이미
    // 그 타입의 `.description`을 그대로 써주므로, 가운데 분기 없이 바로 이걸
    // 써도 동작은 같고 의미 없는 캐스팅 경고만 사라진다.
    private static func describe(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let message = localized.errorDescription {
            return message
        }
        return String(describing: error)
    }
}
