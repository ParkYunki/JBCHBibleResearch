//
//  TranslationPickerPopover.swift
//  JBCHBibleResearch
//
//  등록된 번역본이 4개 이상일 때, 칩을 토글해 화면에 동시 표시할 번역본을
//  최대 3개까지 고르는 팝오버. 3개 이하면 BibleReadingView가 버튼을 숨긴다.
//  선택 순서를 배열로 보존해(선택 시 맨 뒤 추가, 해제 시 해당 항목만 제거)
//  그 순서가 그대로 컬럼 표시 순서가 되며, 선택된 행에 순서 번호 배지를 표시한다.
//  닫기(X)는 onDone을 부르지 않으므로 "적용" 없이 닫으면 선택 변경이 반영되지 않는다.

import SwiftUI
import SwiftData
import BibleResearchModels
#if os(iOS)
import UIKit
#endif

struct TranslationPickerPopover: View {
    let available: [TranslationRegistry]
    let maxSelection: Int
    /// 선택한 순서를 유지하는 배열 — 이 순서가 `onDone`으로 넘어가 컬럼 표시 순서가 된다.
    @State var selectedIDs: [PersistentIdentifier]
    var onDone: ([PersistentIdentifier]) -> Void

    /// 닫기(X) 버튼 전용.
    @Environment(\.dismiss) private var dismiss

    /// 앱 테마(성경 읽기 화면의 배경/텍스트 색상) 읽기 전용 접근.
    private var settings: UserSettingsStore { .shared }
    /// `applyButtonForeground`에서 `Color.resolve(in:)`로 실제 밝기를 재는 데 쓴다.
    @Environment(\.self) private var environment

    init(available: [TranslationRegistry], selected: [PersistentIdentifier], maxSelection: Int, onDone: @escaping ([PersistentIdentifier]) -> Void) {
        self.available = available
        self.maxSelection = maxSelection
        self._selectedIDs = State(initialValue: selected)
        self.onDone = onDone
    }

    /// 아이폰에서 `.popover`가 시트로 바뀔 때 남는 여백이 시스템 기본 흰 배경으로
    /// 보이지 않게 하려는 판정. `BookmarkListPopover.isPhone`과 같은 로직(그쪽은 `private`).
    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    #if os(iOS)
    /// 아이폰 시트 높이 근사치 — 각 구성요소의 실제 패딩값을 더한다. 목록은
    /// `available.count`에 비례하고, 푸터 안내 문구 높이는 `footer`와 같은 조건
    /// (`selectedIDs.count >= maxSelection`)일 때만 더한다. 행 높이 44는 HIG 최소 탭 영역 기준.
    private var sheetHeight: CGFloat {
        // 헤더 위쪽 패딩(18)과 장식 구분선(≈20)을 반영한 값. 목록/푸터 사이 `Divider()`는 얇은 선(1).
        let headerHeight: CGFloat = 52
        let headerDividerHeight: CGFloat = 20
        let footerDividerHeight: CGFloat = 1
        let chipRowHeight: CGFloat = 44
        let chipCount = CGFloat(available.count)
        let chipSpacing: CGFloat = 8
        let listOuterPadding: CGFloat = 24
        let listHeight = listOuterPadding + chipCount * chipRowHeight + max(0, chipCount - 1) * chipSpacing
        let footerOuterPadding: CGFloat = 24
        let footerButtonRowHeight: CGFloat = 38
        let footerWarningHeight: CGFloat = selectedIDs.count >= maxSelection ? 20 : 0
        let footerHeight = footerOuterPadding + footerButtonRowHeight + footerWarningHeight
        return headerHeight + headerDividerHeight + listHeight + footerDividerHeight + footerHeight
    }
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            translationPickerContentOrnamentalDivider
            translationList
                .padding(12)
            Divider()
            footer
        }
        // `sheetHeight`는 근사치라 이 VStack이 남는 공간을 못 채우면 시트 기본 배경(흰색)이
        // 드러난다. 아이폰에서만 시트 전체 높이까지 늘려 아래 `.background()`가 전부 칠하게
        // 한다(아이패드/macOS는 nil이라 내용 크기 그대로).
        .frame(maxHeight: isPhone ? .infinity : nil, alignment: .top)
        // 시스템 기본 배경은 다크 모드에서 거의 검게 보이므로 테마 배경색을 적용한다.
        .background(settings.bibleBackgroundColor ?? Color.clear)
        // 폭 340 — 번역본 이름과 순서 배지가 한 행에 여유 있게 들어간다.
        .frame(width: isPhone ? nil : 340)
        // 아이폰(시트)에서만 시트 높이를 컨텐츠에 맞추고, 아이패드/macOS는 아무 동작도 하지 않는다.
        #if os(iOS)
        .modifier(TranslationPickerSheetSizingModifier(isPhone: isPhone, sheetHeight: sheetHeight))
        #endif
    }

    /// `BookmarkListPopover.header`와 같은 패딩(가로 16/세로 10)·닫기 아이콘 스타일로 통일.
    private var header: some View {
        HStack {
            // 타이틀에 자체 글자색이 없으면 다크 배경에서 시스템 기본색이 그대로 드러나므로 테마 글자색을 쓴다.
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
        // 위쪽 여백만 더 띄운다.
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    /// 타이틀 아래 장식 구분선(가로선-`sparkle`-가로선, wood 톤). `SearchView`/
    /// `BibleReadingHistorySheet`의 것과 같은 모양이며, `private`라 복제했다.
    private var translationPickerContentOrnamentalDivider: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(JBCHCategoryPalette.wood.opacity(0.3))
                .frame(height: 1)
            Image(systemName: "sparkle")
                .font(.system(size: 11))
                .foregroundStyle(settings.bibleTextColor?.opacity(0.45) ?? Color.secondary)
            Rectangle()
                .fill(JBCHCategoryPalette.wood.opacity(0.3))
                .frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    /// 번역본을 세로 한 줄로 나열한다. `ScrollView` + `.frame(maxHeight:)`는 내용과 무관하게
    /// 상한만큼 빈 공간을 확보하므로, `VStack`으로 실제 높이만 차지하게 했다.
    /// ⚠️ 알려진 한계: 번역본이 아주 많아지면 스크롤 없이 목록이 계속 길어진다 —
    /// 그 경우 높이를 실측해 스크롤 상한을 두는 작업이 필요하다.
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
                // `.borderedProminent`는 라벨 글자색을 흰색으로 고정해 밝은 테마색에서 글자가
                // 안 보이므로, `chip(for:)`와 같은 저수준 스타일(Capsule 채우기 + 계산한 글자색)을
                // 쓴다. `applyButtonTint`/`applyButtonForeground` 참고.
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
                .contentShape(Rectangle())
            }

            // 최대 개수에 도달했을 때만, 나머지 칩이 눌리지 않는 이유를 안내한다.
            if selectedIDs.count >= maxSelection {
                // 같은 푸터의 "N / M 선택됨"과 같은 테마 글자색을 쓴다.
                Text("다른 번역본을 보려면 먼저 하나를 해제하세요.")
                    .font(.caption2)
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// 선택 순서 배지는 이름 오른쪽에 인라인으로 배치한다. 이름은 `.lineLimit(1)`의
    /// 기본 말줄임으로 폭에 맞춰 잘린다.
    private func chip(for registry: TranslationRegistry) -> some View {
        let isSelected = selectedIDs.contains(registry.persistentModelID)
        let canToggleOn = isSelected || selectedIDs.count < maxSelection
        return Button {
            if isSelected {
                // 해당 값만 제거 — 나머지 항목의 상대 순서(=선택 순서)는 유지된다.
                selectedIDs.removeAll { $0 == registry.persistentModelID }
            } else if canToggleOn {
                // 항상 맨 뒤에 추가해 가장 나중에 선택한 것이 가장 후순서가 되게 한다.
                selectedIDs.append(registry.persistentModelID)
            }
        } label: {
            HStack(spacing: 10) {
                Text(registry.displayName)
                    .font(isSelected ? .body.weight(.semibold) : .body)
                    .foregroundStyle(isSelected ? Color("AccentColor") : (settings.bibleTextColor ?? Color.primary))
                    .lineLimit(1)
                Spacer(minLength: 8)
                // 선택된 행에만 선택 순서 번호 배지를 붙인다.
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
        .contentShape(Rectangle())
        .opacity(!isSelected && !canToggleOn ? 0.4 : 1)
        .disabled(!isSelected && !canToggleOn)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selectedIDs)
    }

    /// 테마 텍스트색, 없으면(테마 미지정) `Color("AccentColor")`.
    private var applyButtonTint: Color {
        settings.bibleTextColor ?? Color("AccentColor")
    }

    /// WCAG 상대휘도 공식(`DocumentsHomeView.isDarkBibleBackground`와 동일)으로
    /// `applyButtonTint`(버튼 배경)의 밝기를 재어 글자색을 흰색/검정 중 읽히는 쪽으로
    /// 고른다. 항상 흰색이면 밝은 테마색에서 글자가 안 보인다.
    private var applyButtonForeground: Color {
        let resolved = applyButtonTint.resolve(in: environment)
        let luminance = 0.2126 * Double(resolved.red) + 0.7152 * Double(resolved.green) + 0.0722 * Double(resolved.blue)
        return luminance < 0.5 ? Color.white : Color.black
    }
}

#if os(iOS)
/// `BookmarkListPopover.BookmarkSheetSizingModifier`와 같은 구조(`private`라 복제).
/// 아이폰(시트)에서만 높이를 컨텐츠에 맞추고, 아이패드/macOS는 아무 동작도 하지 않는다.
private struct TranslationPickerSheetSizingModifier: ViewModifier {
    let isPhone: Bool
    let sheetHeight: CGFloat
    func body(content: Content) -> some View {
        if isPhone {
            content
                .presentationDetents([.height(sheetHeight)])
                .presentationDragIndicator(.visible)
        } else {
            content
        }
    }
}
#endif
