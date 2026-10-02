//
//  IPadPaneSeparation.swift
//  JBCHBibleResearch
//
//  아이패드 성경 조회의 세 영역(사이드바 | 본문 | 개요 인스펙터)을 눈으로 구분하기 위한 공통 부품.
//
//  문제: 세 영역이 모두 같은 테마 배경색(`UserSettingsStore.bibleBackgroundColor`) 하나로 칠해지고 경계선도 없어
//  (UIKit `UISplitViewController`는 macOS `NSSplitView`와 달리 구분선을 거의 그리지 않는다) 어디까지가 본문인지 알 수 없었다.
//
//  해법(2026-10-02 결정, A안): 본문은 테마색 그대로 두고, 사이드바와 인스펙터만 ① 글자색 5%를 얹어 아주 살짝
//  어둡게(어두운 테마는 밝게) 하고 ② 본문과 맞닿는 가장자리에 글자색 15% 1pt 선을 긋는다.
//  글자색에서 파생하므로 어떤 테마에서도 같은 농도로 보이고, 테마를 고르지 않았을 때(배경 nil)는 시스템 기본 배경 위에 얹는다.
//
//  맥OS는 `NSSplitView`가 이미 구분선을 그리고 창 너비/레이아웃이 다르므로 아무것도 바꾸지 않는다(이 부품은 아이패드에서만 동작).
//  아이폰은 사이드바/인스펙터 열이 없다(인스펙터는 시트) — 역시 동작하지 않는다.

import SwiftUI
#if os(iOS)
import UIKit
#endif

extension View {
    /// 테마 배경을 칠한다. 아이패드에서 `tinted`가 true이면 글자색 5% 톤을 한 겹 더 얹는다.
    /// 기존 `.background(settings.bibleBackgroundColor ?? Color.clear)`를 이 함수로 바꿔 쓴다
    /// (톤은 반드시 같은 `.background` 안에서 쌓아야 한다 — 따로 `.background`를 한 번 더 걸면 앞의 불투명 배경 뒤로 가려진다).
    func themedPaneBackground(tinted: Bool) -> some View {
        let settings = UserSettingsStore.shared
        return background {
            ZStack {
                settings.bibleBackgroundColor ?? Color.clear
                if tinted && IPadPaneSeparation.isActive {
                    (settings.bibleTextColor ?? Color.primary).opacity(IPadPaneSeparation.tintOpacity)
                }
            }
        }
    }

    /// 본문과 맞닿는 가장자리에 1pt 헤어라인을 긋는다(아이패드 전용). 사이드바는 `.trailing`, 인스펙터는 `.leading`.
    /// 세로 전체를 채우도록 안전영역을 무시하고, 터치는 가로채지 않는다.
    @ViewBuilder
    func iPadPaneSeparator(_ edge: HorizontalEdge) -> some View {
        if IPadPaneSeparation.isActive {
            let settings = UserSettingsStore.shared
            overlay(alignment: edge == .leading ? .leading : .trailing) {
                Rectangle()
                    .fill((settings.bibleTextColor ?? Color.primary).opacity(IPadPaneSeparation.lineOpacity))
                    .frame(width: 1)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        } else {
            self
        }
    }
}

enum IPadPaneSeparation {
    /// 톤 농도(글자색 기준) — 본문과의 차이가 느껴지되 글자 대비는 해치지 않는 값.
    static let tintOpacity: Double = 0.05
    /// 헤어라인 농도 — 책갈피/이력 목록의 구분선(12%)보다 약간 진하게 해 영역 경계로 읽히게 한다.
    static let lineOpacity: Double = 0.15

    /// 아이패드(및 비-아이폰 iOS)에서만 켠다.
    static var isActive: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom != .phone
        #else
        false
        #endif
    }
}
