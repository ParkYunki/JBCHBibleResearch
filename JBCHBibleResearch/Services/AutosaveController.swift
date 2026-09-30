//
//  AutosaveController.swift
//  JBCHBibleResearch
//
//  자동저장 규칙(디바운스 + 안전망 flush)의 공통 구현.
//  - 디바운스: 마지막 변경 후 약 1.5초 뒤 실제 저장(ModelContext.save()).
//  - ⚠️ 안전망: 디바운스 타이머만 믿으면 안 된다 — 화면 이탈/씬 배경 전환/앱 종료 시
//    `flush()`를 호출해 대기 중인 저장을 즉시 커밋해야 한다.
//  - 태그/폴더 변경 같은 이산적 액션은 디바운스 없이 `saveImmediately()`로 바로 저장한다.
//  UserMemo, BookOutline, ChapterSummary 등 여러 모델이 공용으로 쓴다.
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class AutosaveController {
    /// 툴바 저장 상태 아이콘용 상태. ⚠️ 로컬 저장(ModelContext.save()) 완료 여부의 근사치일
    /// 뿐, 실제 CloudKit 업로드 완료를 추적하지 않는다.
    enum SyncStatus {
        case saved
        case pending
        case saving
    }

    private(set) var status: SyncStatus = .saved

    private let modelContext: ModelContext
    private var debounceTask: Task<Void, Never>?
    private let debounceInterval: Duration = .seconds(1.5)

    /// `modelContext.save()`가 성공한 직후 호출할 부수 작업(예: MemoDetailView는
    /// `BibleReferenceIndexingService.reindexMemo`를 넘김). 컨트롤러가 대상 타입을 모르므로
    /// 호출부가 넘기며, 저장이 실패하면 부르지 않는다(반영된 텍스트만 인덱싱해야 함).
    var didSave: (() -> Void)?

    init(modelContext: ModelContext, didSave: (() -> Void)? = nil) {
        self.modelContext = modelContext
        self.didSave = didSave
    }

    /// 본문/성경좌표처럼 타이핑 중인 변경마다 호출해 디바운스 타이머를 (재)시작한다.
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
    /// 대기 중인 디바운스가 있을 때만 즉시 저장한다.
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
            // 실패를 삼키지 않고 콘솔에 남긴다. UI 알림은 화면마다 방식이 달라 호출부 책임이다.
            print("[AutosaveController] 저장 실패: \(error)")
            status = .pending
        }
    }

    /// 화면을 벗어날 때 내용이 비어 있는 레코드를 정리한다. "비어 있는가" 판단은 모델 구성을
    /// 아는 호출부가 `isEmpty`로 넘긴다.
    /// `beforeDelete`는 `modelContext.delete` 직전에 호출한다(예: `removeMentions`로 인덱스
    /// 정리). 삭제 후에는 `sourceId`를 다시 읽을 수 없는 경우가 있기 때문이다.
    func deleteIfEmpty<T: PersistentModel>(_ model: T, isEmpty: Bool, beforeDelete: (() -> Void)? = nil) {
        guard isEmpty else { return }
        beforeDelete?()
        modelContext.delete(model)
        try? modelContext.save()
    }
}
