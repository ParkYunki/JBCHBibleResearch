import SwiftUI

//
//  ContentView.swift
//  PersonSeedEditor
//
//  [2026-09-16 신설] 전체 레이아웃 — 좌측 인물 목록(sidebar), 우측 편집
//  폼(detail). 새 인물 추가는 `pendingNewEntry`(아직 저장 전) 상태로 임시
//  진입하고, 저장/취소 후에는 다시 목록 선택 모드로 돌아간다.
struct ContentView: View {
    @EnvironmentObject var store: PersonSeedStore
    @State private var selection: String?
    @State private var pendingNewEntry: PersonSeedEntry?
    @State private var showRebuildSheet = false

    var body: some View {
        NavigationSplitView {
            PersonListSidebar(selection: $selection) {
                pendingNewEntry = store.addBlankPerson()
                selection = nil
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            if let pendingNewEntry {
                PersonEditorView(
                    entry: pendingNewEntry,
                    isNew: true,
                    onSaved: { saved in
                        self.pendingNewEntry = nil
                        selection = saved.idx
                    },
                    onDeleted: { self.pendingNewEntry = nil }
                )
                .id("new-\(pendingNewEntry.idx)")
            } else if let selection, let entry = store.persons.first(where: { $0.idx == selection }) {
                PersonEditorView(
                    entry: entry,
                    isNew: false,
                    onSaved: { _ in },
                    onDeleted: { self.selection = nil }
                )
                .id(entry.idx)
            } else {
                ContentUnavailableView(
                    "인물을 선택하세요",
                    systemImage: "person.crop.circle",
                    description: Text("왼쪽 목록에서 고르거나 + 버튼으로 새 인물을 추가하세요.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showRebuildSheet = true
                } label: {
                    Label("재빌드", systemImage: "hammer")
                }
                .help("build_reference_data.py를 실행해 ReferenceData.sqlite를 다시 만듭니다.")
            }
        }
        .sheet(isPresented: $showRebuildSheet) {
            RebuildSheet()
        }
        .overlay(alignment: .bottom) {
            if let message = store.lastMessage {
                StatusBanner(text: message, isError: false)
            } else if let error = store.lastError {
                StatusBanner(text: error, isError: true)
            }
        }
        .onAppear {
            store.load()
        }
    }
}

private struct StatusBanner: View {
    let text: String
    let isError: Bool

    var body: some View {
        Text(text)
            .font(.callout)
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(isError ? Color.red.opacity(0.15) : Color.green.opacity(0.15))
            .foregroundStyle(isError ? .red : .green)
            .padding(8)
    }
}

/// [2026-09-16 신설] "재빌드" 버튼 — `python3 build_reference_data.py`를
/// 실행해 ReferenceData.sqlite를 갱신한다. 이 세션 내내 사람이 터미널에서
/// 직접 실행해 온 것과 완전히 같은 스크립트를 그대로 호출할 뿐이다.
private struct RebuildSheet: View {
    @EnvironmentObject var store: PersonSeedStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ReferenceData.sqlite 재빌드").font(.headline)
                Spacer()
                Button("닫기") { dismiss() }
            }

            Text("PersonSeed.json을 포함한 모든 시드 파일을 다시 읽어 ReferenceData.sqlite를 새로 만듭니다. 앱(JBCHBibleResearch)이 켜져 있다면 재빌드 후 앱을 다시 시작해야 새 데이터를 읽습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                Text(store.rebuildLog.isEmpty ? "(아직 실행하지 않았습니다)" : store.rebuildLog)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(minHeight: 260)
            .background(Color.black.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))

            HStack {
                Spacer()
                Button {
                    Task { await store.rebuild() }
                } label: {
                    if store.isRebuilding {
                        ProgressView()
                    } else {
                        Label("지금 재빌드 실행", systemImage: "hammer.fill")
                    }
                }
                .disabled(store.isRebuilding)
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 420)
    }
}
