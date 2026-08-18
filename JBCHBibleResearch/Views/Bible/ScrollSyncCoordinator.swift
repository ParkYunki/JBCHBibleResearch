//
//  ScrollSyncCoordinator.swift
//  JBCHBibleResearch
//
//  근거: bible-research-platform-screens.md 3장/S1 — "중앙 기준(center-anchor) 스크롤
//  동기화". 여러 번역본 컬럼 중 사용자가 실제로 스크롤 중인 컬럼(리더)의 화면 정중앙에
//  있는 절 번호를 기준으로, 나머지 컬럼(팔로워)들이 같은 절이 중앙에 오도록 맞춘다.
//
//  ⚠️ [단순화, 원문서와 차이] 원문서는 "리더 컬럼의 스크롤을 ±1로 증분 확인"하는 성능
//  최적화까지 언급하지만, 이번 구현은 정확성을 먼저 확보하는 데 집중해 TranslationColumnView가
//  보이는 절들의 프레임을 SwiftUI PreferenceKey로 모아 매 스크롤마다 중앙에 가장 가까운
//  절을 다시 계산하는 방식을 썼다(한 장의 절 수가 최대 176개(시편 119편) 수준이라 매번
//  전체 재계산해도 비용이 크지 않다고 판단). ±1 증분 최적화는 실제 성능 문제가 확인되면
//  추가하는 게 맞다고 본다.
//
//  ⚠️ [폴백 규칙] 팔로워 컬럼에 리더가 가리키는 절이 없으면(번역본마다 절 구분이 다를
//  수 있음) screens.md 3장이 명시한 대로 "이전 절로 대체"한다 — 정확히 일치하는 절이
//  없으면 그보다 작은 절 번호 중 가장 큰 것을 찾고, 그마저 없으면 그 컬럼의 첫 절로
//  대체한다.
//

import Foundation
import Observation

@MainActor
@Observable
final class ScrollSyncCoordinator {
    struct SyncEvent: Equatable {
        let sourceColumnID: UUID
        let verse: Int
    }

    /// screens.md 11장 View 메뉴의 "스크롤 동기화" 토글과 연결하기 위해 미리 분리해
    /// 뒀다(메뉴 커맨드 배선 자체는 이번 구현 범위 밖이라 기본값 true로만 둔다).
    var isEnabled = true

    private(set) var latestEvent: SyncEvent?

    /// 리더 컬럼이 "화면 중앙에 있는 절이 바뀌었다"고 보고한다. 같은 컬럼이 같은 절을
    /// 반복 보고하는 경우는 무시해 불필요한 팔로워 재계산을 막는다.
    func reportCenterVerse(_ verse: Int, columnID: UUID) {
        guard isEnabled else { return }
        guard latestEvent?.sourceColumnID != columnID || latestEvent?.verse != verse else { return }
        latestEvent = SyncEvent(sourceColumnID: columnID, verse: verse)
    }

    /// 팔로워 컬럼이 실제로 스크롤할 절 번호를 계산한다. `availableVerses`는 해당
    /// 컬럼(번역본)에 실제로 존재하는 절 번호 오름차순 배열이 아니어도 되며 내부에서
    /// 정렬 여부에 의존하지 않는다.
    func resolveTargetVerse(for requestedVerse: Int, availableVerses: [Int]) -> Int? {
        guard !availableVerses.isEmpty else { return nil }
        if availableVerses.contains(requestedVerse) { return requestedVerse }
        if let previous = availableVerses.filter({ $0 < requestedVerse }).max() {
            return previous
        }
        return availableVerses.min()
    }
}
