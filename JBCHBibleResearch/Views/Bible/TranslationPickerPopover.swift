//
//  TranslationPickerPopover.swift
//  JBCHBibleResearch
//
//  screens.md 3장/9장 — 등록된 번역본이 4개 이상일 때, 칩을 토글해 화면에 동시 표시할
//  번역본을 최대 3개까지 고르는 팝오버. 3개 이하로 등록돼 있으면 이 UI 자체가 필요
//  없으므로 BibleReadingView가 그 경우 버튼을 숨긴다.
//
//  ⚠️ 번들 번역본 1개만 부트스트랩된 상태로만 검증했다 — 실제 4개 이상 등록 상태에서의
//  동작은 S12(번역본 관리) 구현 후 재검증이 필요하다(BibleReadingViewModel.swift 상단
//  주석 참고).
//

import SwiftUI
import SwiftData
import BibleResearchModels

struct TranslationPickerPopover: View {
    let available: [TranslationRegistry]
    let maxSelection: Int
    @State var selectedIDs: Set<PersistentIdentifier>
    var onDone: (Set<PersistentIdentifier>) -> Void

    init(available: [TranslationRegistry], selected: [PersistentIdentifier], maxSelection: Int, onDone: @escaping (Set<PersistentIdentifier>) -> Void) {
        self.available = available
        self.maxSelection = maxSelection
        self._selectedIDs = State(initialValue: Set(selected))
        self.onDone = onDone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("표시할 번역본 (최대 \(maxSelection)개)")
                .font(.headline)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                    ForEach(available) { registry in
                        chip(for: registry)
                    }
                }
            }

            HStack {
                Text("\(selectedIDs.count) / \(maxSelection) 선택됨")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("적용") { onDone(selectedIDs) }
                    .buttonStyle(.borderedProminent)
            }

            // [2026-08-07 추가] screens.md 3장/9장 — 최대 개수(3개)에 도달했을 때
            // 안내 문구가 있어야 한다는 요구가 있었는데, 지금까지는 위 카운터
            // ("3 / 3 선택됨")만 있고 "왜 나머지 칩이 눌리지 않는지"를 설명하는
            // 문구가 없었다. 비활성화된 칩만 보고 이유를 짐작해야 하는 상태였다 —
            // 개수가 꽉 찼을 때만 나타나는 고정 안내문을 추가한다.
            if selectedIDs.count >= maxSelection {
                Text("다른 번역본을 보려면 먼저 하나를 해제하세요.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .frame(minWidth: 280)
    }

    private func chip(for registry: TranslationRegistry) -> some View {
        let isSelected = selectedIDs.contains(registry.persistentModelID)
        let canToggleOn = isSelected || selectedIDs.count < maxSelection
        return Button {
            if isSelected {
                selectedIDs.remove(registry.persistentModelID)
            } else if canToggleOn {
                selectedIDs.insert(registry.persistentModelID)
            }
        } label: {
            Text(registry.displayName)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? .accentColor : .secondary)
        .disabled(!isSelected && !canToggleOn)
    }
}
