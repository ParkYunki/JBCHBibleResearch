//
//  AutosaveController.swift
//  JBCHBibleResearch
//
//  screens.md 12장 — 자동저장 규칙(디바운스 + 안전망 flush)의 공통 구현.
//  - 디바운스: 마지막 변경 후 약 1.5초 뒤 실제 저장(ModelContext.save()).
//  - ⚠️ 안전망: "디바운스 타이머만 믿으면 안 된다"(12장) — 화면 이탈/씬 배경 전환/
//    앱 종료 시 `flush()`를 반드시 호출해 대기 중인 저장을 즉시 커밋해야 한다.
//  - 태그/폴더 변경처럼 이산적 액션은 디바운스 없이 `saveImmediately()`로 바로 저장
//    (13.3 — "태그는 이산적 액션이라 디바운스 없이 바로 저장").
//
//  2026-08-06: 원래 `MemoAutosaveController`라는 이름으로 UserMemo(S2/S3) 전용으로만
//  썼다 — 그때 남긴 주석에 "실제로 두 번째 사용처가 생기면 그때 제네릭화하는 편이
//  안전하다"고 적어 뒀는데, 지금 S8/S9(BookOutline/ChapterSummary) 화면이 그 두 번째
//  사용처다. 그래서 이번에 `AutosaveController`로 리네임하고, 유일하게 타입에 묶여
//  있던 `deleteIfEmpty(_:isEmpty:)`를 `PersistentModel` 제네릭으로 바꿨다(디바운스/flush
//  로직 자체는 애초에 저장 대상 타입과 무관했다). 근거 없는 선제적 제네릭화가 아니라,
//  실제 두 번째 사용처가 생긴 시점에 맞춘 리팩토링이다(review-addendum "오버엔지니어링
//  금지" 원칙과 상충하지 않음).
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class AutosaveController {
    /// 12장 "저장 상태 표시(선택)" — 툴바에 작은 동기화 상태 아이콘을 두는 것을
    /// 권장한다고 명시했다. ⚠️ 이 상태는 "로컬 저장(ModelContext.save()) 완료 여부"의
    /// 근사치일 뿐, 실제 CloudKit 업로드 완료를 추적하지는 않는다 — CloudKit 동기화
    /// 이벤트를 직접 구독하려면 별도의 더 깊은 통합이 필요해 이번 범위에서는
    /// 로컬 저장 상태로 근사했다.
    enum SyncStatus {
        case saved
        case pending
        case saving
    }

    private(set) var status: SyncStatus = .saved

    private let modelContext: ModelContext
    private var debounceTask: Task<Void, Never>?
    private let debounceInterval: Duration = .seconds(1.5)

    /// [2026-08-11 추가] 사용자 요청 — "메모/연구문서를 등록·수정할 때마다 관련
    /// 성경구절 인덱스를 재계산." 이 컨트롤러는 `UserMemo`/`BookOutline`/
    /// `ChapterSummary` 여러 타입에 공용으로 쓰여 타입을 모르므로, 실제로
    /// `modelContext.save()`가 성공한 직후 호출할 부수 작업을 호출부가 이 클로저로
    /// 넘긴다(MemoDetailView는 `BibleReferenceIndexingService.reindexMemo`를 넘김).
    /// 저장이 실패하면 부르지 않는다 — 실제로 반영된 텍스트만 인덱싱해야 한다.
    var didSave: (() -> Void)?

    init(modelContext: ModelContext, didSave: (() -> Void)? = nil) {
        self.modelContext = modelContext
        self.didSave = didSave
    }

    /// 본문/성경좌표처럼 "타이핑 중" 성격의 변경마다 호출 — 디바운스 타이머를
    /// (재)시작한다.
    func scheduleSave() {
        status = .pending
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled else { return }
            self.performSave()
        }
    }

    /// 이산적 액션(태그/폴더 변경) 또는 안전망 flush 시 즉시 저장.
    func saveImmediately() {
        debounceTask?.cancel()
        debounceTask = nil
        performSave()
    }

    /// 안전망 — 화면 이탈, 씬이 백그라운드로 갈 때, 앱 종료 시 반드시 호출한다.
    /// 대기 중인 디바운스가 있을 때만 즉시 강제 저장을 커밋한다(12장).
    func flush() {
        guard debounceTask != nil else { return }
        saveImmediately()
    }

    private func performSave() {
        debounceTask = nil
        status = .saving
        do {
            try modelContext.save()
            status = .saved
            didSave?()
        } catch {
            // 저장 실패를 조용히 삼키지 않는다. 다만 이 타입은 UI 알림을 직접 띄우지
            // 않는다(화면마다 배너/토스트 방식이 다를 수 있어 호출부 책임으로 남김) —
            // 최소한 콘솔에는 남긴다.
            print("[AutosaveController] 저장 실패: \(error)")
            status = .pending
        }
    }

    /// 13.4 — 화면을 벗어날 때, 내용이 전혀 채워지지 않은 빈 레코드를 정리한다.
    /// "비어 있는가" 판단은 각 모델 구성을 아는 호출부(MemoDetailView 등)가 넘겨준다.
    /// UserMemo 전용이던 시절엔 타입이 고정돼 있었으나, 제네릭화 이후에는 어떤
    /// `PersistentModel`이든 동일하게 쓸 수 있다.
    /// [2026-08-11 추가] `beforeDelete` — 실제로 지워지기 직전(아직 `modelContext.
    /// delete` 전) 호출할 부수 작업. 호출부(MemoDetailView)가 이 시점에
    /// `BibleReferenceIndexingService.removeMentions(...)`로 그 소스의 인덱스를
    /// 함께 정리한다 — 삭제 후에는 `sourceId`(UUID 문자열)를 다시 읽을 수 없는
    /// 경우가 있어(이미 컨텍스트에서 빠진 모델) 삭제 직전에 부른다.
    func deleteIfEmpty<T: PersistentModel>(_ model: T, isEmpty: Bool, beforeDelete: (() -> Void)? = nil) {
        guard isEmpty else { return }
        beforeDelete?()
        modelContext.delete(model)
        try? modelContext.save()
    }
}
