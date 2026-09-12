#!/usr/bin/env python3
"""번역본 선택 팝오버(TranslationPickerPopover.swift) 수정 스크립트.
1) 번역본 목록을 가로 한 줄(HStack + 가로 ScrollView) → 세로 한 줄(VStack, 매 항목이
   한 행을 꽉 채움)로 변경.
2) "적용" 버튼 색상을 시스템 기본 파란색(.borderedProminent 기본 tint) 대신
   테마 텍스트색(`UserSettingsStore.bibleTextColor`)을 따르게 하고, 글자색은
   그 배경과의 WCAG 대비를 계산해 흰색/검정 중 실제로 읽히는 쪽을 고른다
   (이 코드베이스에 이미 5차례 이상 쓰인 `isDarkBibleBackground` 공식 재사용 —
   `.buttonStyle(.borderedProminent)`는 라벨 글자색을 시스템이 강제로 흰색
   고정하는 것으로 알려져 있어, 테마색이 밝은 색(예: 크림/금색 계열 다크
   테마의 텍스트색)일 때 흰 글자가 안 보이는 새 버그를 만들 위험이 있다 —
   그래서 `.borderedProminent`를 아예 쓰지 않고, 같은 파일의 기존 칩 버튼과
   같은 저수준 스타일(Capsule fill + 직접 지정한 foregroundStyle)로 새로
   만든다).
"""
import pathlib

ROOT = pathlib.Path.home() / "mnt" / "JBCHBibleResearch"
PATH = ROOT / "JBCHBibleResearch/Views/Bible/TranslationPickerPopover.swift"


def apply(path: pathlib.Path, replacements):
    src = path.read_text()
    for old, new, count in replacements:
        found = src.count(old)
        assert found == count, f"{path.name}: expected {count} occurrence(s), found {found}\n---OLD---\n{old[:200]}"
        src = src.replace(old, new)
    path.write_text(src)
    print(f"OK: {path}")


edits = []

# --- A) settings/environment 프로퍼티 추가 ---
old_a = '''    /// [2026-09-04 신설] 위 파일 상단 리디자인 주석 참고 — 닫기(X) 버튼 전용.
    @Environment(\\.dismiss) private var dismiss

    init(available: [TranslationRegistry], selected: [PersistentIdentifier], maxSelection: Int, onDone: @escaping ([PersistentIdentifier]) -> Void) {'''
new_a = '''    /// [2026-09-04 신설] 위 파일 상단 리디자인 주석 참고 — 닫기(X) 버튼 전용.
    @Environment(\\.dismiss) private var dismiss

    /// [2026-09-11 신설] 사용자 보고 — "적용버튼의 색상이 테마색상으로
    /// 되도록(파란색X)." 이 팝오버는 지금까지 테마(성경 읽기 화면의
    /// 배경/텍스트 색상) 적용 대상에서 빠져 있었다 — `DocumentsHomeView`/
    /// `WordNoteHomeView` 등 다른 화면들과 같은 읽기 전용 접근 패턴.
    private var settings: UserSettingsStore { .shared }
    /// [2026-09-11 신설] 아래 `applyButtonForeground`가 `Color.resolve(in:)`로
    /// 실제 밝기를 재는 데 쓴다 — `DocumentRowView.accentSpineColor`와 같은
    /// 목적의 같은 환경값.
    @Environment(\\.self) private var environment

    init(available: [TranslationRegistry], selected: [PersistentIdentifier], maxSelection: Int, onDone: @escaping ([PersistentIdentifier]) -> Void) {'''
edits.append((old_a, new_a, 1))

# --- B) body: chipGrid -> translationList 이름 변경 ---
old_b = '''            chipGrid
                .padding(12)'''
new_b = '''            translationList
                .padding(12)'''
edits.append((old_b, new_b, 1))

# --- C) chipGrid(가로) -> translationList(세로) 재구현 ---
old_c = '''    /// [2026-09-11 재설계] 사용자 보고(첨부 스크린샷) — "일렬로 보여주고,
    /// 창이 이렇게 클 필요가 없음." 2열 `LazyVGrid`를 세로 `ScrollView`로
    /// 감싸고 `.frame(maxHeight: 280)`으로 상한만 뒀던 예전 구조는, 번역본이
    /// 3~4개뿐이라 실제로는 1~2행만 차는데도 그 상한(최대 280pt)까지 세로
    /// 공간을 미리 확보해 둬 팝오버 아래쪽에 빈 공간이 크게 남았다(정확히
    /// 스크린샷에 보이는 증상). 한 줄(가로 `ScrollView`)로 바꾸면 항상 실제
    /// 칩 높이만큼만 차지하므로 높이 상한 자체가 필요 없어진다 — 번역본이
    /// 많아 한 줄에 다 안 들어와도 가로 스크롤로 자연스럽게 해결된다.
    private var chipGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(available) { registry in
                    chip(for: registry)
                }
            }
            // [2026-09-04 신설] 사용자 보고 — "표시순서 숫자 뱃지가...
            // 상단이 잘려 보임." 아래 `chip(for:)`의 순서 배지가
            // `.offset(y: -7)`로 칩 위쪽 바깥까지 살짝 튀어나오는데, 맨 앞
            // 칩들은 이 `ScrollView`의 클리핑 경계에 바로 붙어 있어 그만큼
            // 잘려 보였다 — 배지가 튀어나올 여유 공간을 미리 확보한다.
            .padding(.top, 8)
            .padding(.horizontal, 2)
        }
    }'''
new_c = '''    /// [2026-09-11 2차 재설계] 사용자 보고 — "번역본을 가로로 한줄이
    /// 아니라 세로 한줄로 바꿀것." 바로 위 주석(2026-09-11 1차 재설계)이
    /// "가로 한 줄"로 바꾼 이유 자체는 유효하다(세로 `ScrollView` +
    /// `.frame(maxHeight:)` 조합은 실제 내용과 무관하게 그 상한만큼 빈
    /// 공간을 미리 확보해 버린다) — 이번엔 세로 방향을 다시 요청받았으므로
    /// `ScrollView`를 아예 걷어내고 평범한 `VStack`으로 바꿨다. `VStack`은
    /// (`ScrollView`와 달리) 어느 축이든 항상 자식들의 실제 높이만큼만
    /// 차지하므로, 세로로 바꿔도 그 "빈 공간" 버그가 재현되지 않는다.
    /// ⚠️ [알려진 한계] 번역본 개수가 아주 많아지면(현재는 번들 1개만
    /// 실기기 검증됨 — S12 번역본 관리 미구현) 이 목록이 스크롤 없이
    /// 계속 길어진다 — 그 시점엔 높이를 실측해 스크롤 상한을 두는 별도
    /// 작업이 필요하다(지금은 있지도 않은 다수 번역본 상황을 가정한
    /// 선제적 스크롤 처리를 새로 만들지 않았다).
    private var translationList: some View {
        VStack(spacing: 8) {
            ForEach(available) { registry in
                chip(for: registry)
            }
        }
        .padding(.horizontal, 2)
    }'''
edits.append((old_c, new_c, 1))

# --- D) footer의 "적용" 버튼 — 테마색 + 대비 계산 foreground로 교체 ---
old_d = '''                Button("적용") { onDone(selectedIDs) }
                    .buttonStyle(.borderedProminent)'''
new_d = '''                // [2026-09-11 수정] 사용자 보고 — "적용버튼의 '적용' 글자가
                // 흰색으로 고정됨, 적용버튼의 색상이 테마색상으로 되도록
                // (파란색X)." `.buttonStyle(.borderedProminent)`는 라벨
                // 글자색을 시스템이 흰색으로 고정한다 — 테마 텍스트색이
                // 밝은 색(다크 테마 계열)일 때 그대로 두면 흰 글자가 안
                // 보이는 새 문제가 생긴다. 그래서 `.borderedProminent`
                // 대신 이 파일의 `chip(for:)`가 이미 쓰는 것과 같은 저수준
                // 스타일(Capsule 채우기 + 직접 계산한 글자색)로 새로
                // 만들었다 — `applyButtonTint`/`applyButtonForeground` 참고.
                Button {
                    onDone(selectedIDs)
                } label: {
                    Text("적용")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(applyButtonForeground)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(applyButtonTint))
                }
                .buttonStyle(.plain)'''
edits.append((old_d, new_d, 1))

# --- E) truncatedChipLabel(더 이상 안 씀) 제거, chip(for:) 전체 재작성 ---
old_e = '''    /// [2026-09-05 수정] 사용자 보고(맥OS) — "버튼 좌우폭 크기를 일정하게
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
            // [2026-09-11 수정] 위 `chipGrid` 재설계 주석 참고 — 2열
            // 그리드에서는 칸 폭이 균일하도록 `.frame(maxWidth: .infinity)`로
            // 칩이 칸을 꽉 채우게 했지만, 한 줄(가로 스크롤) 구조에서는 같은
            // modifier가 각 칩을 한없이 넓히려 들어 오히려 어색하다 — 칩이
            // 자기 텍스트 크기만큼만 차지하게 뺀다.
            Text(Self.truncatedChipLabel(registry.displayName))
                .font(isSelected ? .body.weight(.semibold) : .body)
                .foregroundStyle(isSelected ? Color("AccentColor") : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? Color("AccentColor").opacity(0.15) : Color.secondary.opacity(0.12))
                )
                .overlay(
                    Capsule().stroke(isSelected ? Color("AccentColor").opacity(0.5) : Color.secondary.opacity(0.4), lineWidth: 1)
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
                Text("\\(order + 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color("AccentColor")))
                    .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                    .offset(x: 7, y: -7)
                    .allowsHitTesting(false)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selectedIDs)
    }
}'''
new_e = '''    /// [2026-09-11 2차 재설계] 사용자 요청으로 목록이 "칩"(작은 알약형
    /// 버튼)에서 "꽉 찬 한 행"으로 바뀌면서, 좁은 칩 폭에 맞추려고 있던
    /// 8자 절단(`truncatedChipLabel`)은 더 이상 필요 없다 — 이제 팝오버
    /// 전체 폭(340pt)을 한 행이 그대로 쓰므로 `.lineLimit(1)`의 기본
    /// 말줄임(자간 그대로, 실제 폭에 맞춰 자동으로 자름)이 8자 고정 절단보다
    /// 더 자연스럽다. 선택 순서 배지도 칩 모서리에 튀어나오게 얹던
    /// `.overlay(alignment: .topTrailing)` + `.offset` 방식 대신, 한 행
    /// 안에서 이름 오른쪽에 나란히(inline) 배치한다 — 그 오프셋 수치들은
    /// 작은 칩 전용으로 튜닝된 값이라 꽉 찬 행에는 맞지 않는다.
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
            HStack(spacing: 10) {
                Text(registry.displayName)
                    .font(isSelected ? .body.weight(.semibold) : .body)
                    .foregroundStyle(isSelected ? Color("AccentColor") : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                // [2026-09-04 신설, 2026-09-11 배치만 인라인으로 변경] 위
                // 파일 상단 주석 참고 — 선택된 행에만 선택 순서 번호 배지를
                // 붙인다(iOS 사진 앱 "다중 선택" 순서 배지와 같은 원칙).
                if let order = selectedIDs.firstIndex(of: registry.persistentModelID) {
                    Text("\\(order + 1)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color("AccentColor")))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color("AccentColor").opacity(0.15) : Color.secondary.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color("AccentColor").opacity(0.5) : Color.secondary.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .opacity(!isSelected && !canToggleOn ? 0.4 : 1)
        .disabled(!isSelected && !canToggleOn)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selectedIDs)
    }

    /// [2026-09-11 신설] 위 "적용" 버튼 주석 참고 — 테마 텍스트색이 있으면
    /// 그 색, 없으면(테마 미지정) 기존 기본값 `Color("AccentColor")`.
    private var applyButtonTint: Color {
        settings.bibleTextColor ?? Color("AccentColor")
    }

    /// [2026-09-11 신설] `DocumentsHomeView.isDarkBibleBackground`/
    /// `DocumentRowView.accentSpineColor`와 완전히 같은 WCAG 상대휘도
    /// 공식 — 다만 여기서는 "화면 배경"이 아니라 위 `applyButtonTint`
    /// (버튼 배경) 자체의 밝기를 재서, 그 위에 놓일 글자색을 흰색/검정
    /// 중 실제로 읽히는 쪽으로 고른다. 이렇게 하지 않고 항상 흰색으로
    /// 두면(기존 `.borderedProminent`의 동작) 테마 텍스트색이 밝은
    /// 색(예: 크림/금색 계열 다크 테마)일 때 글자가 안 보이는 문제가
    /// 그대로 남는다 — 사용자가 지적한 "적용 글자가 흰색으로 고정됨"이
    /// 바로 이 문제다.
    private var applyButtonForeground: Color {
        let resolved = applyButtonTint.resolve(in: environment)
        let luminance = 0.2126 * Double(resolved.red) + 0.7152 * Double(resolved.green) + 0.0722 * Double(resolved.blue)
        return luminance < 0.5 ? Color.white : Color.black
    }
}'''
edits.append((old_e, new_e, 1))

apply(PATH, edits)
