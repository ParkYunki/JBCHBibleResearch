//
//  OutlineSlideOverlay.swift
//  JBCHBibleResearch
//
//  아이패드 성경 조회의 "개요 크게 보기" — 별도 창(`WindowGroup("outline-quick-view")`) 대신 앱 안에서 오른쪽으로 밀려 들어오는
//  패널로 보여 준다(2026-10-13, 목업 결정: A 슬라이드 패널 + 머리의 ⤢로 전체 화면 전환).
//  배경: 별도 창은 닫는 길이 창 안 ✕ 하나뿐이라, 닫으면 개요만 닫혔는데도 앱이 닫힌 것처럼 느껴졌다.
//
//  - 패널: 화면 폭의 약 2/3(최소 420pt, 화면보다 넓어지지 않음). 나머지는 옅게 어두워지며 탭하면 닫힌다.
//  - 전체 화면: 머리의 ⤢로 패널이 성경 조회 본문 영역 전체로 넓어진다(위쪽 내비게이션 바는 그대로 보여 앱 안에 있음이 분명하다).
//  - 닫기: 머리의 "‹ 성경 조회"(전체 화면에서는 "⌄ 성경 조회로 돌아가기"), 바깥 어두운 영역 탭,
//    머리를 패널 모드에서 오른쪽으로 / 전체 화면에서 아래로 80pt 이상 끌기.
//  - 내용(`OutlineQuickViewWindowContent`)은 조회 전용 그대로이며 `isEmbedded`로 자체 ✕와 제목을 끈다.
//
//  iOS 전용. 호출부(`BibleReadingView`)는 아이패드에서만 이 뷰를 띄운다(아이폰은 다중 창도, 이 버튼도 없다).
//

#if os(iOS)
import SwiftUI
import UIKit

struct OutlineSlideOverlay: View {
    let request: OutlineQuickViewRequest
    /// true면 본문 영역 전체를 덮는다(전체 화면), false면 오른쪽 패널.
    @Binding var isExpanded: Bool
    /// 닫기 애니메이션이 끝난 뒤 호출 — 호출부가 요청 상태를 비워 이 뷰를 제거한다.
    let onClose: () -> Void

    /// 처음 나타날 때 false → true로 바꿔 오른쪽에서 밀려 들어오게 한다. 닫을 때는 반대로 돌린 뒤 `onClose`를 부른다.
    @State private var isShown = false
    /// 닫기 애니메이션 중 중복 호출 방지.
    @State private var isClosing = false

    private static let animationDuration: TimeInterval = 0.28
    private static let minimumPanelWidth: CGFloat = 420
    private static let panelWidthRatio: CGFloat = 0.66
    private static let dragCloseDistance: CGFloat = 80

    private var settings: UserSettingsStore { .shared }

    var body: some View {
        GeometryReader { proxy in
            let fullWidth = proxy.size.width
            let panelWidth = isExpanded ? fullWidth : min(fullWidth, max(Self.minimumPanelWidth, fullWidth * Self.panelWidthRatio))
            ZStack(alignment: .trailing) {
                // 바깥(본문 쪽) 어두운 막 — 탭하면 닫힌다. 전체 화면에서는 가려질 곳이 없어 터치를 받지 않는다.
                Color.black
                    .opacity(isShown && !isExpanded ? 0.28 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture { if !isExpanded { close() } }
                    .allowsHitTesting(!isExpanded)
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    chrome
                    Divider()
                    OutlineQuickViewWindowContent(request: request, isEmbedded: true)
                }
                .frame(width: panelWidth)
                .frame(maxHeight: .infinity)
                .background(settings.bibleBackgroundColor ?? Color(UIColor.systemBackground))
                .shadow(color: .black.opacity(isExpanded ? 0 : 0.22), radius: 12, x: -4, y: 0)
                .offset(x: isShown ? 0 : panelWidth)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onAppear {
            withAnimation(.easeOut(duration: Self.animationDuration)) { isShown = true }
        }
        .accessibilityAddTraits(.isModal)
    }

    // MARK: - 머리 줄

    private var chrome: some View {
        HStack(spacing: 8) {
            Button(action: close) {
                Label(
                    isExpanded ? String(localized: "성경 조회로 돌아가기") : String(localized: "성경 조회"),
                    systemImage: isExpanded ? "chevron.down" : "chevron.left"
                )
                .font(.body.weight(.semibold))
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color("AccentColor"))

            Spacer(minLength: 8)

            Text(titleText)
                .font(.headline)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                withAnimation(.easeInOut(duration: Self.animationDuration)) { isExpanded.toggle() }
            } label: {
                Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color("AccentColor"))
            .accessibilityLabel(isExpanded ? String(localized: "패널로 줄이기") : String(localized: "전체 화면으로 보기"))
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(.bar)
        // 머리를 끌어 닫기 — 버튼 탭과 구분되도록 최소 이동 거리를 둔다(본문 스크롤과는 겹치지 않는다).
        .gesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                if isExpanded {
                    if value.translation.height > Self.dragCloseDistance { close() }
                } else if value.translation.width > Self.dragCloseDistance {
                    close()
                }
            }
        )
    }

    private var titleText: String {
        let bookName = BooksProvider.shared.book(id: request.bookId)?.displayName ?? ""
        return String(localized: "\(bookName) \(request.chapter)장 개요")
    }

    // MARK: - 닫기

    private func close() {
        guard !isClosing else { return }
        isClosing = true
        withAnimation(.easeIn(duration: Self.animationDuration)) { isShown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.animationDuration) {
            onClose()
        }
    }
}
#endif
