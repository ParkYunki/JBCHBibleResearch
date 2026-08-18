//
//  TranslationImportSheet.swift
//  JBCHBibleResearch
//
//  S12(번역본 관리) "추가" 흐름의 공용 UI. 두 번째 사용처(설정 8.3 탭의 "번역본
//  추가..." 버튼)가 처음부터 있어서(SettingsView.swift가 이미 비활성 버튼 + 안내
//  문구로 자리를 잡아 뒀었다) sheet 하나로 분리해 TranslationManagementView와
//  공유한다 — addendum 원칙("두 번째 사용처가 생긴 시점에 맞춰 공통화") 그대로.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import BibleResearchModels

struct TranslationImportSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    var onImported: (TranslationRegistry) -> Void = { _ in }

    @State private var pickedFileURL: URL?
    @State private var validation: TranslationFileValidation?
    @State private var code: String = ""
    @State private var displayName: String = ""
    @State private var licenseType: String = ""
    @State private var bookNameTableID: String?
    @State private var isFileImporterPresented = false
    @State private var isValidating = false
    @State private var errorMessage: String?

    // sqlite/sqlite3/db/bdb 표준 UTType이 없어(hwp/hwpx와 같은 이유,
    // DocumentUploadService.swift 참고) 확장자 기반으로 직접 선언한다. "bdb"는
    // 2026-08-07 사용자가 실제 사용자 추가 번역본 파일 확장자로 확인해 준 값이다
    // (BibleReferenceStore.swift 상단 주석 — `Bible(id, book, chapter, verse,
    // btext)` 스키마 참고).
    private static let sqliteContentTypes: [UTType] = {
        let extensions = ["sqlite", "sqlite3", "db", "bdb"]
        let types = extensions.compactMap { UTType(filenameExtension: $0) }
        return types.isEmpty ? [.data] : types
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section("파일") {
                    Button {
                        isFileImporterPresented = true
                    } label: {
                        Label(pickedFileURL?.lastPathComponent ?? "SQLite 파일 선택...", systemImage: "doc.badge.plus")
                    }
                    if isValidating {
                        ProgressView("파일 확인 중...")
                    }
                }

                if let validation {
                    Section("검증 결과") {
                        if validation.hasVersionCodeColumn {
                            if validation.availableVersionCodes.isEmpty {
                                Text("⚠️ version_code 컬럼은 있지만 실제 값을 찾지 못했습니다.")
                                    .foregroundStyle(.orange)
                            } else {
                                Picker("이 파일에서 가져올 번역본", selection: $code) {
                                    ForEach(validation.availableVersionCodes, id: \.self) { versionCode in
                                        Text(versionCode).tag(versionCode)
                                    }
                                }
                                if validation.availableVersionCodes.count > 1 {
                                    Text("이 파일에는 번역본이 \(validation.availableVersionCodes.count)개 들어있습니다. 나머지는 같은 파일로 가져오기를 다시 실행해 추가하세요.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Text("이 파일은 번역본 1개만 포함합니다(version_code 컬럼 없음).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if !validation.chapterMismatches.isEmpty {
                            DisclosureGroup {
                                ForEach(validation.chapterMismatches) { mismatch in
                                    Text("\(mismatch.bookName): 기대 \(mismatch.expectedChapters)장 / 발견 \(mismatch.foundChapters)장")
                                        .font(.caption)
                                }
                            } label: {
                                Text("⚠️ 표준 장 수와 다른 책 \(validation.chapterMismatches.count)개")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    Section("등록 정보") {
                        TextField("번역본 코드 (예: NIV)", text: $code)
                        TextField("표시 이름 (예: New International Version)", text: $displayName)
                        TextField("라이선스(선택)", text: $licenseType)
                        Picker("책이름표 언어", selection: $bookNameTableID) {
                            Text("한글 기본").tag(nil as String?)
                            ForEach(BookNameTableProvider.shared.builtIn) { table in
                                Text(table.displayName).tag(table.id as String?)
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("번역본 가져오기")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("가져오기", action: performImport)
                        .disabled(!canImport)
                }
            }
        }
        .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: Self.sqliteContentTypes) { result in
            handlePicked(result)
        }
        // [2026-08-11 추가] 사용자 요청 — "[+ 번역본 추가...] 클릭하면 바로
        // 파일선택 화면으로 열릴 것". 이 시트가 뜨자마자 파일 선택기를 자동으로
        // 띄운다 — 사용자가 "SQLite 파일 선택..." 버튼을 한 번 더 누를 필요가
        // 없다. 사용자가 취소하면 시트는 그대로 남아 있고, 이 버튼으로 다시
        // 시도할 수 있다(기존 동작 그대로 유지).
        .onAppear {
            isFileImporterPresented = true
        }
    }

    private var canImport: Bool {
        validation != nil
            && !code.trimmingCharacters(in: .whitespaces).isEmpty
            && !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func handlePicked(_ result: Result<URL, Error>) {
        errorMessage = nil
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let url):
            pickedFileURL = url
            validation = nil
            isValidating = true
            defer { isValidating = false }
            do {
                let validationResult = try TranslationImportService.validate(fileURL: url)
                validation = validationResult
                if let firstCode = validationResult.availableVersionCodes.first {
                    code = firstCode
                } else if code.isEmpty {
                    // version_code 컬럼 자체가 없는 파일 — 파일명에서 코드를 추정해
                    // 미리 채워 준다(사용자가 원하면 바로 고칠 수 있음).
                    code = url.deletingPathExtension().lastPathComponent
                        .uppercased()
                        .filter { $0.isLetter || $0.isNumber }
                }
                if displayName.isEmpty {
                    displayName = url.deletingPathExtension().lastPathComponent
                }
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            }
        }
    }

    private func performImport() {
        guard let pickedFileURL else { return }
        do {
            let registry = try TranslationImportService.importTranslation(
                fileURL: pickedFileURL,
                code: code,
                displayName: displayName,
                licenseType: licenseType,
                bookNameTableID: bookNameTableID,
                context: modelContext
            )
            onImported(registry)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }
}
