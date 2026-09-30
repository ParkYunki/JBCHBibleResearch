//
//  WordNoteSelectionRequest.swift
//  JBCHBibleResearch
//
//  사이드바의 개인 묵상/말씀 요약 항목을 탭하면 본문 영역을 "말씀 노트"
//  (`WordNoteHomeView`)로 전환하면서 그 항목을 미리 선택해 열기 위한 요청 객체.
//
//  `OutlineNavigationRequest.swift`와 같은 이유로 평범한 Equatable 값을 담는
//  @Observable 싱글턴 + `.onChange` 방식을 쓴다 — `.focusedSceneValue`에 클로저를
//  게시하는 방식은 툴바를 가진 뷰에서 읽으면 실기기 크래시로 이어진 전례가 있다.
//

import Foundation
import Observation

enum WordNoteSelectionTarget: Hashable {
    case memo(UUID)
    case summary(UUID)
}

@MainActor
@Observable
final class WordNoteSelectionRequest {
    static let shared = WordNoteSelectionRequest()

    private(set) var requestedTarget: WordNoteSelectionTarget?

    private init() {}

    /// `SidebarNavigationView`의 "고정됨"/"최근" 섹션 행이 호출한다.
    func request(_ target: WordNoteSelectionTarget) {
        requestedTarget = target
    }

    /// 요청을 소비한 쪽(`WordNoteListContent`)이 처리 후 반드시 호출해 비운다 —
    /// 안 비우면 같은 항목을 다시 요청했을 때 `.onChange`가 값이 그대로라고
    /// 판단해 반응하지 않을 수 있다.
    func clear() {
        requestedTarget = nil
    }
}
