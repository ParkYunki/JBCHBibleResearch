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
//  [2026-09-04 리디자인] 사용자 요청 — "우측 상단 번역본 아이콘 클릭했을 때 나오는
//  팝업을 UX/UI 전문가 관점에서 리디자인할 것. 낭비되는 공간없이 정리하고, 닫기버튼도
//  추가할 것." 두 가지를 손봤다.
//  (1) 칩 목록을 담는 `ScrollView`에 높이 상한이 없어서, 번역본이 몇 개 안 될 때도
//  팝오버가 화면 대부분을 차지하는 빈 공간으로 늘어져 있었다 — `.frame(maxHeight:)`로
//  상한을 둬 실제 칩 개수만큼만 차지하고, 그 상한을 넘는 경우(번역본이 많이 등록된
//  경우)에만 스크롤되게 했다.
//  (2) 제목만 있던 상단에 닫기(X) 버튼을 추가하고, 헤더/목록/푸터 사이에 구분선을
//  둬 "제목 → 목록 → 액션"이라는 구조가 한눈에 보이게 정리했다. 닫기 버튼은
//  `@Environment(\.dismiss)`로 구현했다 — `.popover`/`.sheet`로 띄운 뷰 안에서
//  표준적으로 쓰는 방식이라 호출부(BibleReadingView.swift)를 손댈 필요가 없고,
//  `onDone`을 부르지 않으므로 "적용" 없이 닫으면 기존과 같이 선택 변경사항이
//  반영되지 않는다(취소와 동일한 동작).
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

    /// [2026-09-04 신설] 위 파일 상단 리디자인 주석 참고 — 닫기(X) 버튼 전용.
    @Environment(\.dismiss) private var dismiss

    init(available: [TranslationRegistry], selected: [PersistentIdentifier], maxSelection: Int, onDone: @escaping ([PersistentIdentifier]) -> Void) {
        self.available = available
        self.maxSelection = maxSelection
        self._selectedIDs = State(initialValue: selected)
        self.onDone = onDone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            chipGrid
                .padding(12)
            Divider()
            footer
        }
        // [2026-09-05 수정] 사용자 보고(맥OS) — "팝업의 좌우 폭을 조금더
        // 늘릴것." 아래 `chip(for:)`가 이제 표시 이름을 8자로 잘라 보여주긴
        // 하지만("최대 8자 + …"), 그 8자 자체도 이전 폭(300)에서는 칩 2열이
        // 빠듯했다 — 여유 있게 늘린다.
        .frame(width: 340)
    }

    /// [2026-09-05 수정] 사용자 보고(맥OS) — "상단 타이틀과 닫기 버튼의
    /// 디자인을 [우측상단 책갈피 목록]을 참조하여 동일한 디자인으로 하라."
    /// `BookmarkListPopover.header`와 정확히 같은 패딩(가로 16/세로 10)과
    /// 닫기 아이콘 스타일(`.font(.system(size: 18))`, symbolRenderingMode
    /// 없음)로 맞췄다 — 같은 파일 계열(S1 상단 조회 관련 팝오버)이 서로
    /// 다른 헤더 규격을 쓰던 것을 통일한다.
    private var header: some View {
        HStack {
            Text("표시할 번역본")
                .font(.headline)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("닫기")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// [2026-09-04 변경] 위 파일 상단 리디자인 주석 참고 — 칩이 몇 개 안 될
    /// 때도 팝오버가 빈 공간으로 늘어지지 않도록 높이 상한(`maxHeight`)을
    /// 뒀다. 이 상한을 넘는 경우(번역본이 많을 때)에만 실제로 스크롤된다.
    private var chipGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                ForEach(available) { registry in
                    chip(for: registry)
                }
            }
            // [2026-09-04 신설] 사용자 보고 — "표시순서 숫자 뱃지가...
            // 상단이 잘려 보임." 아래 `chip(for:)`의 순서 배지가
            // `.offset(y: -7)`로 칩 위쪽 바깥까지 살짝 튀어나오는데, 맨 윗줄
            // 칩들은 이 `ScrollView`의 클리핑 경계에 바로 붙어 있어 그만큼
            // 잘려 보였다 — 배지가 튀어나올 여유 공간을 미리 확보한다.
            .padding(.top, 8)
        }
        .frame(maxHeight: 280)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// [2026-09-05 수정] 사용자 보고(맥OS) — "버튼 좌우폭 크기를 일정하게
    /// 하고, 버튼 배경색이 너무 흐려서 경계가 모호함." 원인 (1) 각 칩이
    /// `Text(registry.displayName)`의 자연 크기로만 그려져, `LazyVGrid`의
    /// 칸(column) 폭은 균일해도 그 안의 버튼 자체는 번역본 이름 길이에 따라
    /// 제각각으로 보였다 — `.frame(maxWidth: .infinity)`로 칩이 칸 폭을
    /// 그대로 채우게 한다. (2) `.buttonStyle(.bordered).tint(.secondary)`는
    /// 미선택 칩에 아주 옅은 회색조 배경만 줘 경계가 흐릿했다 — 이 화면
    /// 자체와 같은 파일 계열(`BookChapterPicker.swift`의 `bookCircleButton`/
    /// `chapterButton`)이 이미 쓰는 "강조색 배경 15% + 테두리 획" 언어를
    /// 그대로 재사용해(근거 없는 새 스타일 발명 대신 기존 패턴 재사용),
    /// 선택/미선택 상태 모두 배경과 테두리가 뚜렷이 보이게 했다.
    /// [2026-09-05 신설] 위 `chip(for:)` 주석 참고 — 8자를 넘는 번역본
    /// 표시 이름을 "앞 8자 + …"로 자른다. 8자 이하면 원본 그대로 돌려준다.
    private static func truncatedChipLabel(_ name: String) -> String {
        guard name.count > 8 else { return name }
        return String(name.prefix(8)) + "…"
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
            // [2026-09-05 수정] 사용자 보고(맥OS) — "버튼에 표시할 글자를
            // 8자 이상일때 [8자 + ...] 으로 수정하라." 기존
            // `.lineLimit(1)` + `.minimumScaleFactor(0.85)`만으로는 긴
            // 이름이 글자 자체가 줄어들어 작게 보였을 뿐 잘리지 않았다 —
            // 요청대로 8자를 넘으면 앞 8자만 보이고 "..."으로 표시한다.
            Text(Self.truncatedChipLabel(registry.displayName))
                .font(isSelected ? .body.weight(.semibold) : .body)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
                )
                .overlay(
                    Capsule().stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .opacity(!isSelected && !canToggleOn ? 0.4 : 1)
        .disabled(!isSelected && !canToggleOn)
        // [2026-09-04 신설] 위 파일 상단 주석 참고 — 선택된 칩에만 선택 순서
        // 번호 배지를 얹는다(iOS 사진 앱 "다중 선택" 순서 배지와 같은 원칙).
        // 칩 자체의 탭 영역(above Button)과 겹치지 않도록 배지는 순수 표시용
        // 오버레이로만 얹고 탭 제스처는 받지 않는다(`allowsHitTesting(false)`).
        .overlay(alignment: .topTrailing) {
            if let order = selectedIDs.firstIndex(of: registry.persistentModelID) {
                // [2026-09-04 수정] 사용자 보고 — "표시순서 숫자 뱃지가 너무
                // 작고 그마저도 상단이 잘려 보임. 위아래 영역이 충분한데,
                // 컨텐츠 영역이 너무 작아보임." 원 16pt · `.caption2` 안에서
                // 숫자가 지나치게 작게 보였다 — 원을 20pt로 키우고 폰트도
                // `.caption`(한 단계 큰 크기)으로 올려 숫자가 원 안에서
                // 여유 있게 보이도록 했다. 오프셋도 커진 원 크기에 비례해
                // 5→7로 늘려 칩 모서리에 자연스럽게 걸치게 했다(위 `chipGrid`
                // 의 `.padding(.top, 8)`이 이 오프셋만큼의 클리핑 여유를
                // 함께 확보한다).
                Text("\(order + 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.accentColor))
                    .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                    .offset(x: 7, y: -7)
                    .allowsHitTesting(false)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selectedIDs)
    }
}
