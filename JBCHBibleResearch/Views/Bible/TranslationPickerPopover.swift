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

    /// [2026-09-11 신설] 사용자 보고 — "적용버튼의 색상이 테마색상으로
    /// 되도록(파란색X)." 이 팝오버는 지금까지 테마(성경 읽기 화면의
    /// 배경/텍스트 색상) 적용 대상에서 빠져 있었다 — `DocumentsHomeView`/
    /// `WordNoteHomeView` 등 다른 화면들과 같은 읽기 전용 접근 패턴.
    private var settings: UserSettingsStore { .shared }
    /// [2026-09-11 신설] 아래 `applyButtonForeground`가 `Color.resolve(in:)`로
    /// 실제 밝기를 재는 데 쓴다 — `DocumentRowView.accentSpineColor`와 같은
    /// 목적의 같은 환경값.
    @Environment(\.self) private var environment

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
            translationList
                .padding(12)
            Divider()
            footer
        }
        // [2026-09-11 신설] 사용자 보고 — "배경색이 왜 검은색 고정이지?"
        // 이 팝오버는 지금까지 배경 자체가 테마 대상에서 빠져 있었다 —
        // 시스템 기본 배경만 써서, 다크 모드(또는 사용자가 앱 "화면모드"를
        // 다크로 설정)일 때 그 기본 배경이 거의 검게 보인 것이다.
        // `BookmarkListPopover.swift`가 이미 쓰는 것과 같은 패턴.
        .background(settings.bibleBackgroundColor ?? Color.clear)
        // [2026-09-05 수정] 사용자 보고(맥OS) — "팝업의 좌우 폭을 조금더
        // 늘릴것." 300은 번역본 이름이 조금만 길어도 빠듯했다 — 여유 있게
        // 늘린다. [2026-09-11 주석 갱신] 이 폭을 정한 근거였던 "칩 2열" 배치
        // 자체가 세로 한 줄 레이아웃(`translationList`)으로 바뀌면서 없어졌지만,
        // 340이라는 폭 자체는 세로 한 줄 행에도 여전히 적당해 값은 그대로
        // 뒀다(번역본 이름 + 순서 배지가 한 행에 여유 있게 들어간다).
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
            // [2026-09-11 신설] 위 `body`의 `.background()` 주석 참고 — 이
            // 타이틀은 자체 글자색이 없어(다른 화면들에서 이미 반복된 것과
            // 같은 이유) 시스템 기본값(다크 배경 위 흰색처럼 보임)이 그대로
            // 드러났었다.
            Text("표시할 번역본")
                .font(.headline)
                .foregroundStyle(settings.bibleTextColor ?? .primary)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("닫기")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// [2026-09-11 2차 재설계] 사용자 보고 — "번역본을 가로로 한줄이
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
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(selectedIDs.count) / \(maxSelection) 선택됨")
                    .font(.caption)
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                Spacer()
                // [2026-09-11 수정] 사용자 보고 — "적용버튼의 '적용' 글자가
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
                .buttonStyle(.plain)
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

    /// [2026-09-11 2차 재설계] 사용자 요청으로 목록이 "칩"(작은 알약형
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
                    .foregroundStyle(isSelected ? Color("AccentColor") : (settings.bibleTextColor ?? Color.primary))
                    .lineLimit(1)
                Spacer(minLength: 8)
                // [2026-09-04 신설, 2026-09-11 배치만 인라인으로 변경] 위
                // 파일 상단 주석 참고 — 선택된 행에만 선택 순서 번호 배지를
                // 붙인다(iOS 사진 앱 "다중 선택" 순서 배지와 같은 원칙).
                if let order = selectedIDs.firstIndex(of: registry.persistentModelID) {
                    Text("\(order + 1)")
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
                    .fill(isSelected ? Color("AccentColor").opacity(0.15) : (settings.bibleTextColor?.opacity(0.08) ?? Color.secondary.opacity(0.1)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color("AccentColor").opacity(0.5) : (settings.bibleTextColor?.opacity(0.3) ?? Color.secondary.opacity(0.35)), lineWidth: 1)
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
}
