//
//  ScrollSyncCoordinator.swift
//  JBCHBibleResearch
//
//  여러 번역본 컬럼 중 사용자가 스크롤 중인 컬럼(리더)의 화면 정중앙에 있는 절을 기준으로,
//  나머지 컬럼(팔로워)이 같은 절을 중앙에 맞추는 "중앙 기준 스크롤 동기화" 조정자.
//  TranslationColumnView가 보이는 절들의 프레임을 PreferenceKey로 모아 매 스크롤마다 중앙에 가장
//  가까운 절을 다시 계산한다(장당 최대 176절이라 전체 재계산 비용이 크지 않음). ±1 증분 최적화는
//  실제 성능 문제가 확인되면 추가한다.
//
//  ⚠️ 폴백: 팔로워 컬럼에 리더가 가리키는 절이 없으면(번역본마다 절 구분이 다를 수 있음) 그보다 작은
//  절 번호 중 가장 큰 것으로, 그마저 없으면 그 컬럼의 첫 절로 대체한다.
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

    /// "스크롤 동기화" 메뉴 토글과 연결하기 위해 분리해 뒀다(메뉴 배선은 아직 없어 기본값 true).
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
