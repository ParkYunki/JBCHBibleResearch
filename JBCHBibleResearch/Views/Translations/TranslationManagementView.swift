//
//  TranslationManagementView.swift
//  JBCHBibleResearch
//
//  S12(번역본 관리). PlaceholderScreens.swift의 TranslationManagementPlaceholderView를
//  대체한다 — 아이폰은 "더보기" 탭에서, macOS/iPadOS는 설정(⌘,/툴바 톱니바퀴)의
//  "번역본" 탭에서 진입한다(이 프로젝트가 지금까지 다른 화면들을 배선해 온 것과
//  같은 자리, PlaceholderScreens.swift 상단 주석 참고). 목록 자체는 그 설정 탭
//  (TranslationsSettingsTab, SettingsView.swift 8.3)에도 이미 있었지만, 이 화면은
//  "가져오기"까지 실제로 수행하고 책이름표 언어를 인라인으로 바꿀 수 있어 더
//  완전한 관리 화면이다.
//
//  [2026-08-07 수정] 원래 이 자리에는 "screens.md S12 원문이 이 세션에 없어
//  추론으로 만들었다"는 ⚠️가 있었다 — 이후 Claude.ai 프로젝트 지식에 원본
//  세 문서(schema/screens/addendum.md)가 새로 동기화돼 실제로 대조할 수 있게
//  됐다. 대조 결과: S12 섹션 자체엔 목업 ASCII 아트가 없어(screens.md 3장, S12
//  절은 텍스트 설명만 있다) "목록+편집" 형태 자체는 원문과 어긋나지 않았지만,
//  8.3(환경설정 번역본 탭) 스펙의 "동기화 상태 컬럼"/"S1 기본 표시 3개 체크박스
//  선택"과 S12 자체의 "편집" 요구가 누락돼 있었다 — 이번 라운드에서 보완했다
//  (아래 표시 이름/라이선스 TextField, TranslationRowView.statusLabel, README
//  참고).
//

import SwiftUI
import SwiftData
import BibleResearchModels

struct TranslationManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: TranslationManagementViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("번역본 관리")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel?.isImportSheetPresented = true
                } label: {
                    Label("추가", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel?.isImportSheetPresented ?? false },
            set: { viewModel?.isImportSheetPresented = $0 }
        )) {
            TranslationImportSheet { registry in
                viewModel?.handleImported(registry)
            }
        }
        .onAppear(perform: setUpIfNeeded)
        .alert("오류", isPresented: Binding(
            get: { viewModel?.lastErrorDescription != nil },
            set: { if !$0 { viewModel?.lastErrorDescription = nil } }
        )) {
            Button("확인") { viewModel?.lastErrorDescription = nil }
        } message: {
            Text(viewModel?.lastErrorDescription ?? "")
        }
    }

    @ViewBuilder
    private func content(viewModel: TranslationManagementViewModel) -> some View {
        if viewModel.rows.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "character.book.closed")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("등록된 번역본이 없습니다.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(viewModel.rows) { row in
                    TranslationRowView(row: row, viewModel: viewModel)
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private func setUpIfNeeded() {
        guard viewModel == nil else { return }
        let vm = TranslationManagementViewModel(modelContext: modelContext)
        vm.onAppear()
        viewModel = vm
    }
}

private struct TranslationRowView: View {
    let row: TranslationManagementViewModel.Row
    let viewModel: TranslationManagementViewModel

    private var registry: TranslationRegistry { row.registry }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // [2026-08-07 추가] screens.md S12 "목록에서 삭제/편집" — 표시 이름과
            // 라이선스를 이 자리에서 바로 고칠 수 있다(번들도 포함, 6.7이 막은 건
            // "번들 삭제"뿐이라 편집까지 막을 근거는 없다고 판단). 다른 편집
            // 화면(메모/개요)과 같은 원칙으로 별도 저장 버튼 없이 즉시 반영된다.
            TextField("표시 이름", text: Binding(
                get: { registry.displayName },
                set: { viewModel.updateDisplayName($0, for: registry) }
            ))
            .font(.headline)
            #if os(iOS)
            .textFieldStyle(.roundedBorder)
            #else
            .textFieldStyle(.plain)
            #endif

            HStack(spacing: 6) {
                Text(subtitleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            TextField("라이선스(선택)", text: Binding(
                get: { registry.licenseType ?? "" },
                set: { viewModel.updateLicenseType($0, for: registry) }
            ))
            .font(.caption)
            #if os(iOS)
            .textFieldStyle(.roundedBorder)
            #else
            .textFieldStyle(.plain)
            #endif

            if let materializationError = row.materializationErrorDescription {
                Label(materializationError, systemImage: "icloud.and.arrow.down")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Picker("책이름표 언어", selection: Binding(
                get: { registry.bookNameTableID },
                set: { viewModel.setBookNameTable($0, for: registry) }
            )) {
                Text("한글 기본").tag(nil as String?)
                ForEach(BookNameTableProvider.shared.builtIn) { table in
                    Text(table.displayName).tag(table.id as String?)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            if !registry.isBundled {
                Button(role: .destructive) {
                    viewModel.delete(registry)
                } label: {
                    Label("삭제", systemImage: "trash")
                }
            }
        }
    }

    /// screens.md 4.3/6.7 "동기화 중..." 요구를 반영한 상태 라벨. `row
    /// .materializationErrorDescription`은 `TranslationManagementViewModel.reload()`가
    /// 매번 `ensureMaterialized`를 시도한 결과다 — 실패(nil이 아님)면 아직 로컬
    /// 사본이 없다는 뜻이라 그 메시지를 아래 Label로 그대로 보여주고, 성공(nil)이면
    /// 여기선 "동기화됨"으로 짧게만 표시한다. 번들은 애초에 동기화 개념이 없어
    /// `subtitleText`가 이 라벨 자체를 붙이지 않는다(중복 표시 방지).
    private var statusLabel: String {
        row.materializationErrorDescription == nil ? "동기화됨" : "동기화 대기 중"
    }

    private var subtitleText: String {
        var parts = [registry.code, registry.isBundled ? "번들" : "사용자 추가"]
        if !registry.isBundled {
            parts.append(statusLabel)
        }
        return parts.joined(separator: " · ")
    }
}
