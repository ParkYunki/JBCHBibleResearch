//
//  MindMapScrollTouchConfigurator.swift
//  JBCHBibleResearch
//
//  마인드맵 캔버스(iOS/iPadOS) 화면 이동을 "두 손가락 드래그"로 바꾸는 부품.
//
//  배경: 캔버스에서 한 손가락 드래그는 선택 사각형(러버밴드)/노드 이동/선 끌기에 쓰이는데, `ScrollView`의 기본 스크롤도
//  한 손가락 드래그라 두 제스처가 경쟁해 화면 이동이 잘 되지 않았다. SwiftUI `ScrollView`에는 스크롤에 필요한 손가락 수를
//  지정하는 API가 없어, 바탕의 `UIScrollView.panGestureRecognizer.minimumNumberOfTouches`를 2로 올린다.
//  (한 손가락은 SwiftUI 제스처가 받고, 두 손가락 드래그만 스크롤이 받는다.)
//
//  사용: `ScrollView` 콘텐츠 안쪽에 `.background(ScrollViewTwoFingerPan())`로 붙인다 — 콘텐츠 안에 있어야 상위 뷰 사슬에서
//  자기를 감싼 `UIScrollView`를 찾을 수 있다. 찾지 못하면 아무 것도 하지 않는다(기본 동작 유지).
//
//  ⚠️ 외부 포인터(아이패드 마우스/트랙패드)의 스크롤 이벤트가 이 설정과 어떻게 상호작용하는지는 실기기 확인이 필요하다.

#if os(iOS)
import SwiftUI
import UIKit

struct ScrollViewTwoFingerPan: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }

    func updateUIView(_ uiView: Probe, context: Context) { uiView.apply() }

    /// 화면에 보이지 않고 터치도 받지 않는 탐침 뷰. 창에 붙는 순간(그리고 갱신될 때마다) 감싸는 스크롤 뷰를 찾아 설정한다.
    final class Probe: UIView {
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
            var candidate: UIView? = superview
            while let view = candidate {
                if let scrollView = view as? UIScrollView {
                    if scrollView.panGestureRecognizer.minimumNumberOfTouches != 2 {
                        scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
                    }
                    return
                }
                candidate = view.superview
            }
        }
    }
}
#endif
