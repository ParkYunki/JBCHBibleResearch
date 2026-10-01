//
//  NavigationBarGuard.swift
//  JBCHBibleResearch
//
//  아이폰 성경 화면 상단 바(번역본 / 책+장 / 책갈피·이력·관련 콘텐츠 아이콘)가 간헐적으로 사라지는 증상 대응.
//  상단 바는 SwiftUI `.toolbar`가 만드는 시스템 `UINavigationBar`다. 이 화면은 바를 숨기는 코드가 없는데도
//  (관련 콘텐츠 시트 안의 `.toolbar(.hidden, for: .navigationBar)` 선호값 누수, 시트/팝오버 전환 중 툴바 구성 변경 등)
//  시스템 쪽 바 상태가 "숨김/투명"으로 남는 사례가 있어, 화면이 실제로 맨 위에 보이는 조용한 시점에 바 상태를 점검해
//  숨겨져 있으면 되돌리고 로그로 남긴다(콘솔 앱에서 카테고리 NavBarGuard로 확인).
//
//  되돌리는 대상은 바 자체의 표시 상태(`isNavigationBarHidden`/`isHidden`/`alpha`)뿐이다. 이 화면은 바를 숨길 의도가 없어
//  (다른 화면이 push된 동안은 그 화면이 맨 위라 점검하지 않는다) 점검이 의도된 숨김을 덮어쓰지 않는다.
//

#if os(iOS)
import SwiftUI
import UIKit
import os

private let navigationBarGuardLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "JBCHBibleResearch", category: "NavBarGuard"
)

/// `.background`에 붙여 쓰는 보이지 않는 감시자. `recheckToken`이 바뀌면(시트/팝오버가 닫히는 등) 점검을 다시 예약한다.
struct NavigationBarGuard: UIViewControllerRepresentable {
    let recheckToken: Bool

    func makeUIViewController(context: Context) -> NavigationBarGuardController {
        NavigationBarGuardController()
    }

    func updateUIViewController(_ controller: NavigationBarGuardController, context: Context) {
        controller.update(token: recheckToken)
    }
}

final class NavigationBarGuardController: UIViewController {
    private var pendingWorkItem: DispatchWorkItem?
    private var lastToken: Bool?
    /// 시트/전환이 끝나기를 기다리며 다시 예약한 횟수 — 무한 재예약 방지.
    private var deferredAttempts = 0
    private static let maxDeferredAttempts = 6

    override func loadView() {
        // 터치를 가로채지 않는 빈 뷰.
        let emptyView = UIView()
        emptyView.isUserInteractionEnabled = false
        emptyView.backgroundColor = .clear
        view = emptyView
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        deferredAttempts = 0
        scheduleVerification()
    }

    func update(token: Bool) {
        guard token != lastToken else { return }
        lastToken = token
        deferredAttempts = 0
        scheduleVerification()
    }

    /// 시트 닫힘/화면 전환 애니메이션(약 0.4초)이 끝난 뒤 점검하도록 기본 0.7초 뒤에 실행한다. 연달아 호출돼도 마지막 한 번만 실행된다.
    private func scheduleVerification(after delay: TimeInterval = 0.7) {
        pendingWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.verify() }
        pendingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func verify() {
        guard isViewLoaded, let window = view.window, let navigationController else { return }

        // 시트/커버가 떠 있거나 전환 중이면 바 상태가 일시적으로 다를 수 있어 잠시 뒤 다시 본다.
        var topmost: UIViewController? = window.rootViewController
        while let presented = topmost?.presentedViewController { topmost = presented }
        let isCoveredByPresentation = topmost !== window.rootViewController
        if isCoveredByPresentation || navigationController.transitionCoordinator != nil {
            guard deferredAttempts < Self.maxDeferredAttempts else { return }
            deferredAttempts += 1
            scheduleVerification(after: 0.5)
            return
        }

        // 이 화면이 스택 맨 위(다른 화면이 push된 동안은 점검하지 않는다).
        guard let top = navigationController.topViewController,
              sequence(first: self as UIViewController, next: { $0.parent }).contains(where: { $0 === top }) else { return }

        let bar = navigationController.navigationBar
        var repairs: [String] = []
        if navigationController.isNavigationBarHidden {
            navigationController.setNavigationBarHidden(false, animated: false)
            repairs.append("isNavigationBarHidden")
        }
        if bar.isHidden {
            bar.isHidden = false
            repairs.append("navigationBar.isHidden")
        }
        if bar.alpha < 0.99 {
            repairs.append("navigationBar.alpha(\(bar.alpha))")
            bar.alpha = 1
        }

        let barHeight = Double(bar.bounds.height)
        let item = top.navigationItem
        let trailingCount = item.trailingItemGroups.count + (item.rightBarButtonItems?.count ?? 0)
        let hasTitleView = item.titleView != nil
        if repairs.isEmpty {
            navigationBarGuardLogger.debug(
                "정상 — barHeight=\(barHeight) trailingItems=\(trailingCount) titleView=\(hasTitleView)"
            )
        } else {
            navigationBarGuardLogger.notice(
                "바 상태 복구: \(repairs.joined(separator: ", "), privacy: .public) — barHeight=\(barHeight) trailingItems=\(trailingCount) titleView=\(hasTitleView)"
            )
        }
        #if DEBUG
        print("[NavBarGuard] repairs=\(repairs) barHeight=\(barHeight) trailingItems=\(trailingCount) titleView=\(hasTitleView)")
        #endif
    }
}
#endif
