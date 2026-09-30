//
//  UbiquitousFileDownloadMonitor.swift
//  JBCHBibleResearch
//
//  iCloud에만 있고 이 기기에 아직 내려받지 않은 파일의 다운로드를 요청하고 진행률을 관찰한다.
//
//  `DocumentUploadService.copyIntoICloudDocuments`가 연구 문서를 앱 전용
//  iCloud ubiquity 컨테이너에 저장하므로, 다른 기기에서 올린 문서는 메타데이터만 있고 실제
//  바이트는 아직 없을 수 있다. 한 URL의 다운로드 진행률을 한 번에 알려주는 단일 API는 없어 두
//  API를 조합한다.
//  1. `FileManager.startDownloadingUbiquitousItem(at:)` — 다운로드를
//    요청만 한다(진행률/완료 미제공).
//  2.
//    `NSMetadataQuery`(`NSMetadataQueryUbiquitousDocumentsScope`)
//    — 파일 경로로 필터링해
//    `NSMetadataUbiquitousItemPercentDownloadedKey`(0~100
//    Double)와 `NSMetadataUbiquitousItemDownloadingStatusKey`로
//    진행률/완료를 관찰한다.
//

import Foundation

@MainActor
final class UbiquitousFileDownloadMonitor {
    enum Status: Equatable {
        /// 파일이 이 기기에 이미 있거나(로컬 파일 포함), 다운로드가 끝나
        /// 이제 읽을 수 있는 상태.
        case ready
        /// 다운로드 요청됨/진행 중. `progress`는 0.0~1.0(percentDownloaded가
        /// 아직 안 왔으면 0으로 시작).
        case downloading(progress: Double)
        /// 다운로드 요청 자체가 실패했거나(`startDownloadingUbiquitousItem`
        /// 에러), `NSMetadataQuery`가 다운로드 에러를 보고한 경우.
        case failed(String)
    }

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private let onUpdate: (Status) -> Void

    init(onUpdate: @escaping (Status) -> Void) {
        self.onUpdate = onUpdate
    }

    deinit {
        // `stop()`은 MainActor 격리라 deinit에서 직접 부를 수 없다.
        // `NSMetadataQuery.stop()`과 `removeObserver`는 격리 없이 스레드
        // 안전하므로 정리 로직을 인라인한다.
        query?.stop()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// `url`의 다운로드 상태를 확인해 필요하면 다운로드를 요청하고, 이후 진행률/완료를 관찰할 때마다
    /// `onUpdate`를 호출한다.
    ///
    /// - 이미 로컬에 있거나 iCloud 항목이 아니면 즉시 `.ready`를 알린다. 후자는 다운로드
    ///   개념이 없으므로 실제 파일 접근 성공 여부는 호출부의 nil 체크/폴백 메시지가 처리한다.
    /// - 새로 호출하면 이전 관찰은 먼저 정리한다(재진입 가능).
    func beginMonitoring(url: URL) {
        stop()

        // 사전 확인(`resourceValues`)의 실패는 "이미 있다"가 아니라 "상태를 모른다"는
        // 뜻이다. 이 기기가 아직 발견하지 못한 iCloud 항목은 로컬 placeholder 엔트리가
        // 없어 `resourceValues`가 파일 없음 에러로 실패한다. 그래서 로컬에 있거나
        // iCloud 항목이 아니라고 확인된 경우에만 `.ready`로 끝내고, 그 외에는 다운로드를
        // 요청한다. `startDownloadingUbiquitousItem(at:)`은
        // placeholder가 없어도 유효한 ubiquity 항목이면 다운로드를 시작하고, 존재하지
        // 않는 항목이면 에러를 던져 아래에서 `.failed`로 반영된다.
        if let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
        ]) {
            if values.isUbiquitousItem == false {
                // 확실히 iCloud 항목이 아님 — 다운로드라는 개념 자체가 없다.
                onUpdate(.ready)
                return
            }
            if values.ubiquitousItemDownloadingStatus == .current {
                onUpdate(.ready)
                return
            }
        }

        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
            onUpdate(.failed("다운로드를 시작할 수 없습니다: \(error.localizedDescription)"))
            return
        }

        onUpdate(.downloading(progress: 0))
        startQuery(for: url)
    }

    /// 관찰을 멈춘다. 이미 요청된 iCloud 다운로드는 취소되지 않는다(시스템이 백그라운드로 계속
    /// 진행하며, 취소하는 공개 API도 없다).
    func stop() {
        query?.stop()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        query = nil
    }

    private func startQuery(for url: URL) {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemPathKey, url.path)
        self.query = query

        // 이 클로저는 `addObserver`를 통해 `self.observers`에 저장되므로
        // `self`/`query`를 강하게 캡처하면 순환 참조로 해제되지 않는다. `[weak
        // self, weak query]`로 캡처한다.
        let handleUpdate: () -> Void = { [weak self, weak query] in
            guard let self, let query, let item = query.results.first as? NSMetadataItem else { return }
            self.handle(item: item)
        }

        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { _ in
                handleUpdate()
            }
        )
        observers.append(
            center.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main) { _ in
                handleUpdate()
            }
        )

        query.start()
    }

    private func handle(item: NSMetadataItem) {
        let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
        let percent = item.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double
        let downloadError = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingErrorKey) as? NSError

        if let downloadError {
            onUpdate(.failed(downloadError.localizedDescription))
            stop()
            return
        }

        if status == NSMetadataUbiquitousItemDownloadingStatusCurrent {
            onUpdate(.ready)
            stop()
            return
        }

        onUpdate(.downloading(progress: (percent ?? 0) / 100))
    }
}
