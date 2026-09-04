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
//  [2026-09-04 수정] 사용자 보고 — "번역본을 해제 선택했을 때, 어떤 순서 기준으로
//  나오는지 불분명함. 1) 순서를 표시할 것. 2) 가장 나중에 선택된 것이 가장
//  후순서로 배치되게 할 것." 원인: `selectedIDs`가 지금까지 `Set<PersistentIdentifier>`
//  였다 — Set은 원래 순서 개념이 없어(해시 기반), 실제 화면 컬럼 순서를 정하는
//  `BibleReadingViewModel.setDisplayedTranslations(_:)`/`reloadVerses()`(그 함수
//  상단의 2026-08-27 주석 — "결과 순서가 필터링 대상의 순서를 그대로 물려받는다"는
//  바로 그 문제)에 넘기기 직전 호출부(`BibleReadingView.swift`)가 `Array(selected)`로
//  변환하는 순간 순서가 통째로(해시 순서로) 뒤섞였다. `setDisplayedTranslations`
//  자체는 이미 "받은 배열 순서 그대로" 컬럼을 만들도록 돼 있어(위 주석 참고),
//  이 팝오버가 순서를 보존해 넘기기만 하면 된다 — `selectedIDs`를 선택한 순서를
//  그대로 유지하는 배열로 바꾸고(선택 시 맨 뒤에 추가, 해제 시 그 자리만 제거),
//  선택된 칩에 순서 번호 배지를 붙여 사용자가 결과 순서를 미리 확인할 수 있게
//  했다(iOS 사진 앱의 "다중 선택" 순서 배지와 같은 원칙 — 그리드 배치 자체는
//  움직이지 않고, 번호만 선택 순서를 반영해 바뀐다).
//

import SwiftUI
import SwiftData
import BibleResearchModels

struct TranslationPickerPopover: View {
    let available: [TranslationRegistry]
    let maxSelection: Int
    /// [2026-09-04 변경] `Set` → 순서 보존 배열. 선택된 순서 그대로 유지되며,
    /// 이 배열의 순서가 곧 `onDone`으로 넘어가 실제 컬럼 표시 순서가 된다.
    @State var selectedIDs: [PersistentIdentifier]
    var onDone: ([PersistentIdentifier]) -> Void

    init(available: [TranslationRegistry], selected: [PersistentIdentifier], maxSelection: Int, onDone: @escaping ([PersistentIdentifier]) -> Void) {
        self.available = available
        self.maxSelection = maxSelection
        self._selectedIDs = State(initialValue: selected)
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
                // [2026-09-04 변경] 배열에서 그 값만 제거 — 나머지 항목들의
                // 상대 순서(=선택된 순서)는 그대로 유지된다.
                selectedIDs.removeAll { $0 == registry.persistentModelID }
            } else if canToggleOn {
                // [2026-09-04 변경] 사용자 요청 — "가장 나중에 선택된 것이
                // 가장 후순서로 배치." 항상 배열 맨 뒤에 추가한다.
                selectedIDs.append(registry.persistentModelID)
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
        // [2026-09-04 신설] 위 파일 상단 주석 참고 — 선택된 칩에만 선택 순서
        // 번호 배지를 얹는다(iOS 사진 앱 "다중 선택" 순서 배지와 같은 원칙).
        // 칩 자체의 탭 영역(above Button)과 겹치지 않도록 배지는 순수 표시용
        // 오버레이로만 얹고 탭 제스처는 받지 않는다(`allowsHitTesting(false)`).
        .overlay(alignment: .topTrailing) {
            if let order = selectedIDs.firstIndex(of: registry.persistentModelID) {
                Text("\(order + 1)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.accentColor))
                    .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                    .offset(x: 5, y: -5)
                    .allowsHitTesting(false)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selectedIDs)
    }
}
