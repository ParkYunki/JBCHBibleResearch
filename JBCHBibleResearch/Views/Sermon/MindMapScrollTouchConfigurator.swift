//
//  MindMapScrollTouchConfigurator.swift
//  JBCHBibleResearch
//
//  마인드맵 캔버스(iOS/iPadOS) 화면 이동을 설정하는 부품.
//
//  배경: 캔버스에서 한 손가락 드래그는 선택 사각형(러버밴드)/노드 이동/선 끌기에 쓰이는데, `ScrollView`의 기본 스크롤도
//  한 손가락 드래그라 두 제스처가 경쟁해 화면 이동이 잘 되지 않았다. SwiftUI `ScrollView`에는 스크롤에 필요한 손가락 수를
//  지정하는 API가 없어, 바탕의 `UIScrollView.panGestureRecognizer.minimumNumberOfTouches`를 바꾼다.
//
//  두 가지 모드 (2026-10-02 "이동/선택" 버튼):
//   - 선택 모드(`isOneFingerPan == false`, 기본): 두 손가락 드래그만 스크롤. 한 손가락은 SwiftUI 제스처(선택/노드 이동)가 받는다.
//   - 이동 모드(`isOneFingerPan == true`): 한 손가락 드래그로 스크롤. 호출 쪽이 캔버스/노드의 SwiftUI 드래그 제스처를 꺼 둔다.
//
//  두 손가락 이동 보강: 선택 모드에서 두 손가락 드래그가 먹히지 않는다는 보고(아이패드)가 있었다. 원인은 코드만으로 확정하지 못했고,
//  SwiftUI 드래그 제스처가 같은 터치를 먼저 잡아 스크롤 인식기를 막는 경우로 추정한다. 그래서 같은 스크롤 뷰에 두 손가락 `UIPanGestureRecognizer`를
//  하나 더 붙여(다른 인식기와 동시 인식 허용) (1) 두 손가락이 닿아 움직이는 동안 `onTwoFingerPanActive(true)`로 알려
//  SwiftUI 쪽 드래그(선택 사각형 등)를 무시하게 하고, (2) 기본 스크롤 인식기가 움직이지 않을 때에 한해 직접 `contentOffset`을 옮긴다.
//  기본 인식기가 이미 스크롤 중이면 직접 옮기지 않아 이중으로 움직이지 않는다.
//
//  사용: `ScrollView` 콘텐츠 안쪽에 `.background(ScrollViewTwoFingerPan(...))`로 붙인다 — 콘텐츠 안에 있어야 상위 뷰 사슬에서
//  자기를 감싼 `UIScrollView`를 찾을 수 있다. 찾지 못하면 아무 것도 하지 않는다(기본 동작 유지).
//
//  ⚠️ 실기기 확인 필요: (1) 두 손가락 이동이 실제로 되는지, (2) 외부 포인터(마우스/트랙패드) 스크롤과의 상호작용.

import SwiftUI
#if os(iOS)
import UIKit
import UIKit.UIGestureRecognizerSubclass
#endif

/// 두 손가락이 닿아 있는 동안 "처음 닿은 때 대비 두 손가락 사이 거리 변화량(pt, 화면 절대 거리)"을 알려 주는 공유 객체.
/// `MagnifyGesture`는 비율(`magnification`)만 주는데, 손가락을 오므리고 이동하면 기준 거리가 작아 몇 pt만 변해도 비율이 크게 나와
/// 이동이 핀치로 오인식된다(2026-10-02 보고). 그래서 핀치 인정 여부를 절대 거리(pt)로 판정하려고 UIKit 터치에서 직접 잰다.
/// iOS의 `ScrollViewTwoFingerPan`이 값을 채우고, 마인드맵 뷰가 읽는다. 맥OS에서는 값이 채워지지 않는다(`isTwoTouchActive == false`).
final class TwoFingerSpreadTracker {
    /// 두 손가락이 정확히 닿아 있는지.
    var isTwoTouchActive = false
    /// 두 번째 손가락이 닿은 순간의 거리 대비 현재 거리 변화량(pt). 벌리면 +, 오므리면 −.
    var delta: CGFloat = 0
}

#if os(iOS)
/// 상태를 바꾸지 않고(항상 `.possible`) 터치만 관찰해 `TwoFingerSpreadTracker`에 거리를 기록하는 인식기. 다른 인식기를 막지 않는다.
private final class TwoFingerSpreadRecognizer: UIGestureRecognizer {
    let tracker: TwoFingerSpreadTracker
    private var baseDistance: CGFloat?

    init(tracker: TwoFingerSpreadTracker) {
        self.tracker = tracker
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { update(with: event) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { update(with: event) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { update(with: event) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { update(with: event) }

    override func reset() {
        baseDistance = nil
        tracker.isTwoTouchActive = false
        tracker.delta = 0
    }

    private func update(with event: UIEvent) {
        // 끝나는 중인 터치는 제외하고 지금 닿아 있는 터치만 센다.
        let active = (event.allTouches ?? []).filter { $0.phase != .ended && $0.phase != .cancelled }
        guard active.count == 2 else {
            baseDistance = nil
            tracker.isTwoTouchActive = false
            tracker.delta = 0
            return
        }
        let points = active.map { $0.location(in: nil) }
        let distance = hypot(points[0].x - points[1].x, points[0].y - points[1].y)
        if baseDistance == nil { baseDistance = distance }
        tracker.isTwoTouchActive = true
        tracker.delta = distance - (baseDistance ?? distance)
    }
}

struct ScrollViewTwoFingerPan: UIViewRepresentable {
    /// true면 한 손가락 드래그로 스크롤(이동 모드), false면 두 손가락(선택 모드).
    var isOneFingerPan = false
    /// 두 손가락 화면 이동이 진행 중인지 알린다 — SwiftUI 쪽 드래그 제스처가 그 동안 선택 사각형 등을 그리지 않게 하려는 용도.
    var onTwoFingerPanActive: (Bool) -> Void = { _ in }
    /// 직접 스크롤해도 되는지 — 핀치 확대 중에는 false(핀치가 `scrollTo`로 위치를 정하므로 서로 다투지 않게 한다).
    var allowsDirectPan: () -> Bool = { true }
    /// 두 손가락 거리 변화량을 받을 공유 객체(핀치 오인식 판정용). nil이면 측정하지 않는다.
    var spreadTracker: TwoFingerSpreadTracker?

    func makeUIView(context: Context) -> Probe { Probe() }

    func updateUIView(_ uiView: Probe, context: Context) {
        uiView.isOneFingerPan = isOneFingerPan
        uiView.onTwoFingerPanActive = onTwoFingerPanActive
        uiView.allowsDirectPan = allowsDirectPan
        uiView.spreadTracker = spreadTracker
        uiView.apply()
    }

    /// 화면에 보이지 않고 터치도 받지 않는 탐침 뷰. 창에 붙는 순간(그리고 갱신될 때마다) 감싸는 스크롤 뷰를 찾아 설정한다.
    final class Probe: UIView, UIGestureRecognizerDelegate {
        var isOneFingerPan = false
        var onTwoFingerPanActive: (Bool) -> Void = { _ in }
        var allowsDirectPan: () -> Bool = { true }
        var spreadTracker: TwoFingerSpreadTracker?

        private var spreadRecognizer: TwoFingerSpreadRecognizer?
        private weak var scrollView: UIScrollView?
        private var twoFingerRecognizer: UIPanGestureRecognizer?
        /// 직전 이벤트까지의 두 손가락 이동량(창 좌표). 이벤트마다 증분만 적용해 시작 오프셋 기억이 필요 없게 한다.
        private var lastTranslation: CGPoint = .zero

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        func apply() {
            guard let scrollView = scrollView ?? findScrollView() else { return }
            self.scrollView = scrollView
            let touches = isOneFingerPan ? 1 : 2
            if scrollView.panGestureRecognizer.minimumNumberOfTouches != touches {
                scrollView.panGestureRecognizer.minimumNumberOfTouches = touches
            }
            installTwoFingerRecognizerIfNeeded(on: scrollView)
            installSpreadRecognizerIfNeeded(on: scrollView)
            // 이동 모드에서는 기본 스크롤이 두 손가락도 받으므로 보조 인식기는 끈다.
            twoFingerRecognizer?.isEnabled = !isOneFingerPan
        }

        private func findScrollView() -> UIScrollView? {
            var candidate: UIView? = superview
            while let view = candidate {
                if let scrollView = view as? UIScrollView { return scrollView }
                candidate = view.superview
            }
            return nil
        }

        private func installSpreadRecognizerIfNeeded(on scrollView: UIScrollView) {
            guard spreadRecognizer == nil, let spreadTracker else { return }
            let recognizer = TwoFingerSpreadRecognizer(tracker: spreadTracker)
            recognizer.delegate = self
            scrollView.addGestureRecognizer(recognizer)
            spreadRecognizer = recognizer
        }

        private func installTwoFingerRecognizerIfNeeded(on scrollView: UIScrollView) {
            guard twoFingerRecognizer == nil else { return }
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handleTwoFingerPan(_:)))
            recognizer.minimumNumberOfTouches = 2
            recognizer.maximumNumberOfTouches = 2
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            scrollView.addGestureRecognizer(recognizer)
            twoFingerRecognizer = recognizer
        }

        @objc private func handleTwoFingerPan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began:
                lastTranslation = .zero
                onTwoFingerPanActive(true)
            case .changed:
                guard let scrollView else { return }
                // 창 좌표 기준 — 스크롤 뷰 좌표로 재면 스크롤하는 만큼 기준이 움직여 이동량이 어긋난다.
                let translation = recognizer.translation(in: nil)
                let delta = CGPoint(x: translation.x - lastTranslation.x, y: translation.y - lastTranslation.y)
                lastTranslation = translation
                // 기본 스크롤 인식기가 이미 움직이는 중이면 이중 이동을 막기 위해 증분만 추적하고 직접 옮기지 않는다.
                let native = scrollView.panGestureRecognizer.state
                guard native != .began, native != .changed, allowsDirectPan() else { return }
                let inset = scrollView.adjustedContentInset
                let minX = -inset.left
                let minY = -inset.top
                let maxX = max(minX, scrollView.contentSize.width - scrollView.bounds.width + inset.right)
                let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
                var offset = scrollView.contentOffset
                offset.x = min(max(offset.x - delta.x, minX), maxX)
                offset.y = min(max(offset.y - delta.y, minY), maxY)
                scrollView.setContentOffset(offset, animated: false)
            case .ended, .cancelled, .failed:
                onTwoFingerPanActive(false)
            default:
                break
            }
        }

        // 핀치(`MagnifyGesture`)·SwiftUI 드래그·기본 스크롤과 동시에 인식되게 한다.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
#endif
