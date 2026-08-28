//
//  UbiquitousFileDownloadMonitor.swift
//  JBCHBibleResearch
//
//  [2026-08-26 신설] 사용자 요청 — "연구문서 뷰어기능 수정. iCloud 상에는 있지만
//  현재 기기에 아직 다운로드상태가 아닌 파일을 뷰어로 열면 다운로드가 이루어져서
//  뷰어로 볼 수 있게 할것. 다운로드 중이면 다운로드 진행률이 나타날 수 있도록."
//
//  `DocumentUploadService.copyIntoICloudDocuments`가 연구 문서를 앱 전용
//  iCloud ubiquity 컨테이너(`Documents/연구 문서`)에 저장해 두므로, 한 기기(예:
//  Mac)에서 올린 문서가 다른 기기(예: iPad)에는 "iCloud 메타데이터만 있고 실제
//  바이트는 아직 안 내려온" 상태로 존재할 수 있다 — macOS/iOS의 "Mac 저장공간
//  최적화"/사용하지 않는 항목 오프로드 설정이 켜져 있으면 특히 그렇다. 지금까지
//  `DocumentViewerViewModel.onAppear()`는 이 상태를 전혀 고려하지 않고
//  `PDFDocument(url:)`/`Data(contentsOf:)`를 바로 읽었다 — 다운로드가 안 된
//  파일은 조용히 nil/빈 결과가 되어 사용자에게 "왜 안 열리는지" 설명도, 다운로드를
//  시도할 기회도 주지 않았다.
//
//  Apple 문서상 "이 URL 하나의 다운로드 진행률"을 한 번에 알려주는 단일 API는
//  없다 — 아래 두 API를 조합해야 한다:
//  1. `FileManager.startDownloadingUbiquitousItem(at:)` — 다운로드를
//     "요청"만 한다(완료 여부나 진행률은 알려주지 않는 fire-and-forget 호출).
//  2. `NSMetadataQuery`(`NSMetadataQueryUbiquitousDocumentsScope`) — 해당
//     파일의 경로로 필터링해 두면, `.NSMetadataQueryDidUpdate` 등의 알림이 올
//     때마다 결과 항목에서 `NSMetadataUbiquitousItemPercentDownloadedKey`
//     (0~100의 Double)/`NSMetadataUbiquitousItemDownloadingStatusKey`(문자열,
//     `NSMetadataUbiquitousItemDownloadingStatusCurrent`와 비교)를 읽어 진행률과
//     완료 여부를 관찰할 수 있다.
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
        // `stop()`은 MainActor 격리 메서드라 (아마도 다른 스레드에서 호출될 수
        // 있는) `deinit`에서 직접 부를 수 없다 — `NSMetadataQuery.stop()`과
        // `NotificationCenter.removeObserver`는 격리 없이도 스레드 안전하게
        // 호출 가능하므로 정리 로직을 여기 그대로 인라인한다.
        query?.stop()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// `url`의 다운로드 상태를 확인해 필요하면 다운로드를 요청하고, 이후
    /// 진행률/완료를 관찰할 때마다 `onUpdate`를 호출한다.
    ///
    /// - 이미 로컬에 있으면(또는 애초에 유비쿼터스 항목이 아니면 — 앱 관리
    ///   컨테이너 밖 파일, 로컬 전용 파일 등) 즉시 `.ready`를 알리고 끝낸다.
    ///   후자의 경우 "다운로드"라는 개념 자체가 없으므로, 실제 파일 접근 성공
    ///   여부는 호출부(뷰모델)의 기존 nil 체크/폴백 메시지가 그대로 처리한다.
    /// - 새로 호출하면 이전에 진행 중이던 관찰은 먼저 정리한다(같은 뷰모델이
    ///   다른 파일을 다시 열 가능성 대비 — 현재 호출부는 문서당 한 번만
    ///   부르지만, 방어적으로 재진입 가능하게 해 둔다).
    func beginMonitoring(url: URL) {
        stop()

        // [2026-08-26 수정, 사용자 보고 fix] "iCloud 문서를 열면 다운로드
        // 진행 없이 바로 '열 수 없습니다'만 뜬다." — 원인: 이 기기가 그
        // 경로를 한 번도 "발견"한 적 없는 iCloud 항목(다른 기기에서 방금
        // 올려 메타데이터만 막 동기화된 파일)은 로컬에 placeholder 파일
        // 엔트리 자체가 아직 없어서, `resourceValues(forKeys:)`를 URL에
        // 직접 걸면 파일이 없다는 에러(NSFileReadNoSuchFileError 등)로
        // 실패한다 — 이건 iCloud 문서 스토리지에 잘 알려진 특성이다(디렉터리를
        // 한 번 나열하거나 NSMetadataQuery를 돌려야 로컬 엔트리가 생긴다).
        // 이전 구현은 이 실패를 "다운로드 볼 필요 없음(.ready)"으로 잘못
        // 해석해 다운로드 자체를 요청하지 않았다. 이제는 이 사전 확인이
        // "성공했고, 이미 로컬에 있거나 iCloud 항목이 아니라고 확인된 경우"
        // 에만 `.ready`로 빠르게 끝내고, 그 외(사전 확인 실패 포함 — 상태를
        // "모른다"는 뜻이지 "이미 있다"는 뜻이 아니다)에는 무조건 다운로드
        // 요청을 시도한다. `startDownloadingUbiquitousItem(at:)`은 로컬
        // placeholder 엔트리가 아직 없어도, 그 경로가 실제 ubiquity 컨테이너
        // 안의 유효한 항목이면 정상적으로 다운로드를 시작한다(Apple 문서 —
        // "Starts downloading (if necessary) the specified item to the local
        // system"). 반대로 그 경로가 진짜 존재하지 않는 항목이면 이 호출이
        // 에러를 던지므로, 그 경우는 아래 `.failed`로 정확히 반영된다(예전엔
        // 이런 경우도 똑같이 "PDF를 열 수 없습니다"였을 뿐이라 회귀가 아니다).
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

    /// 관찰을 멈춘다. 이미 요청된 iCloud 다운로드 자체는(시스템이 백그라운드로
    /// 계속 진행) 취소되지 않는다 — 취소하는 별도 공개 API가 없고, 이 화면을
    /// 벗어난 뒤에도 파일이 계속 받아지는 편이 사용자에게 더 유용하다.
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

        // [주의: 순환 참조 방지] 이 클로저는 `NotificationCenter.addObserver`를
        // 통해 간접적으로 `self.observers`(즉 `self` 자신)에 저장된다. `self`와
        // `query`를 강하게 캡처하면 self → observers → 클로저 → self 순환이
        // 생겨 이 인스턴스가 절대 해제되지 않는다 — `[weak self, weak query]`로
        // 캡처하고 즉시 옵셔널 바인딩한다.
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
