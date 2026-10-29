//
//  ConcealableDetailColumn.swift
//  JBCHBibleResearch
//
//  아이패드 세로에서 앱 사이드바가 열려 있는 동안 [목록 | 내용]을 나란히 그리는 화면(말씀 노트·개요)의 내용 칸을 숨기는 수정자.
//  판정(`EnvironmentValues.concealsDetailBesideSidebar`)은 `SidebarNavigationView`가 하고, 이 파일은 "어떻게 숨기는지"만 맡는다.
//
//  숨김 방식: `if`로 트리에서 빼지 않고 폭 0·투명으로만 감춘다. 빼면 편집기의 `.onDisappear`가 돈다. 말씀 노트의 빈 새 묵상/요약은
//  `AutosaveController.deleteIfEmpty`로 삭제되는데 선택은 그 객체를 계속 가리키게 되고, 편집 모드·스크롤·커서도 초기화된다.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

/// 내용 칸이 지금 숨겨져 있는지(`ConcealableDetailColumnModifier`가 설정). 숨긴 동안에도 편집기는 트리에 남아 자기 툴바 항목을
/// 계속 올리므로, `MemoDetailView`/`WordSummaryEditorView`/`OutlineBookBulkEditView`가 이 값을 보고 툴바 항목을 뺀다.
/// 기본값 false라 다른 화면은 영향이 없다. 편집기 안에서 띄우는 시트는 경계에서 false로 되돌린다(시트 안 편집기의 버튼까지 사라지지 않게).
private struct SplitDetailConcealedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isSplitDetailConcealed: Bool {
        get { self[SplitDetailConcealedKey.self] }
        set { self[SplitDetailConcealedKey.self] = newValue }
    }
}

struct ConcealableDetailColumnModifier: ViewModifier {
    let isConcealed: Bool

    /// 마지막으로 보였을 때의 폭. 숨긴 동안 자식에게 이 폭을 그대로 제안해, 숨기고 다시 보일 때 텍스트가 다시 줄바꿈되지 않게 한다
    /// (폭 0을 제안하면 텍스트뷰가 비정상 폭으로 배치된다). 상태가 이 수정자 안에 있어 값이 바뀌어도 옆의 목록 뷰는 다시 계산되지 않는다.
    @State private var lastVisibleWidth: CGFloat?

    /// 한 번도 보인 적 없이 숨긴 상태로 시작할 때(세로·사이드바 열림으로 진입) 쓰는 배치 폭. 보이지 않는 배치에만 쓰이고,
    /// 보이는 순간 실제 폭으로 다시 배치된다.
    private static let fallbackWidth: CGFloat = 320

    func body(content: Content) -> some View {
        content
            .frame(width: isConcealed ? (lastVisibleWidth ?? Self.fallbackWidth) : nil)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
                guard !isConcealed, width > 0 else { return }
                lastVisibleWidth = width
            }
            // 바깥 폭 0 — 자식은 위 폭 그대로 leading에 붙어 화면 밖으로 넘치고, 투명·히트 테스트 끔·접근성 숨김으로 감춘다.
            // 모든 값이 nil/1/false일 때 이 수정자들은 배치·표시에 영향이 없다.
            .frame(width: isConcealed ? 0 : nil, alignment: .leading)
            .opacity(isConcealed ? 0 : 1)
            .allowsHitTesting(!isConcealed)
            .accessibilityHidden(isConcealed)
            .environment(\.isSplitDetailConcealed, isConcealed)
            #if os(iOS)
            // 숨기는 순간 그 안의 편집기가 키보드 포커스를 쥐고 있으면 보이지 않는 곳에 입력이 들어가므로 포커스를 내려놓는다.
            // 한계: 앱 전체 first responder를 내려놓으므로 그 순간 사이드바·목록 검색창에 입력 중이었다면 그 키보드도 내려간다.
            .onChange(of: isConcealed) { _, concealed in
                guard concealed else { return }
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            #endif
    }
}

extension View {
    /// 아이패드 세로에서 사이드바가 열려 있는 동안 내용 칸을 숨긴다(`ConcealableDetailColumnModifier`). 호출부는 iOS에서만 쓴다.
    func concealableDetailColumn(_ isConcealed: Bool) -> some View {
        modifier(ConcealableDetailColumnModifier(isConcealed: isConcealed))
    }
}
