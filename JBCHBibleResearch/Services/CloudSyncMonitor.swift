import CoreData
import Foundation
import Observation

/// 로컬 save와 별개로 SwiftData의 CloudKit setup/import/export 실패를 관찰한다.
/// 컨테이너 생성 이후 발생하는 서버 오류는 App.init의 catch로 전달되지 않는다.
@MainActor
@Observable
final class CloudSyncMonitor {
    static let shared = CloudSyncMonitor()

    /// 성공한 원격 수신만 기록한다. 각 화면이 보관한 목록·표시 캐시를 다시 조회할 때 쓴다.
    private(set) var remoteImportRevision = 0

    private var failures: [Int: String] = [:]
    /// 설정 화면에서 원인을 볼 수 있도록 단계별 오류 원문(도메인/코드/하위 오류)을 보관한다. 화면의 짧은 안내문
    /// (`errorMessage`)은 시스템의 일반 문구("작업을 완료할 수 없습니다")만 담는 경우가 많아 원인을 알 수 없다.
    private var failureDetails: [Int: String] = [:]
    @ObservationIgnored private var observer: NSObjectProtocol?

    var errorMessage: String? {
        failures.keys.sorted().first.flatMap { failures[$0] }
    }

    /// `errorMessage`와 같은 단계의 오류 원문. 설정 > 기본 > iCloud 동기화에 표시한다.
    var errorDetail: String? {
        failures.keys.sorted().first.flatMap { failureDetails[$0] }
    }

    private init() {}

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
                Self.shared.receive(event)
            }
        }
    }

    func disable(reason: String) {
        failures[-1] = reason
    }

    private func receive(_ event: NSPersistentCloudKitContainer.Event) {
        guard event.endDate != nil else { return }
        let phase = Int(event.type.rawValue)
        if event.succeeded {
            // import 성공으로 export 실패를 숨기지 않는다. 같은 단계가 성공해야 해제한다.
            failures.removeValue(forKey: phase)
            failureDetails.removeValue(forKey: phase)
            if event.type == .import {
                // SwiftData가 mainContext에 변경을 반영할 기회를 준 뒤 화면에 알린다.
                DispatchQueue.main.async {
                    self.remoteImportRevision += 1
                }
            }
            return
        }

        let details = event.error.map { Self.errorDetails($0 as NSError) } ?? "알 수 없는 오류"
        print("[CloudSyncMonitor] \(event.type) 실패: \(details)")
        // 원문이 매우 길 수 있어(userInfo 전체 덤프) 화면용으로는 앞부분만 둔다. 전체는 위 콘솔 로그에 남는다.
        failureDetails[phase] = "\(event.type) 단계 오류\n" + String(details.prefix(1500))
        if details.contains("production schema") {
            failures[phase] = "서버의 운영 스키마가 앱의 데이터 모델과 일치하지 않습니다. 개발자가 CloudKit 스키마를 운영 환경에 배포해야 합니다."
        } else {
            failures[phase] = "기기 간 데이터 동기화에 실패했습니다. \(event.error?.localizedDescription ?? details)"
        }
    }

    /// Partial Failure의 바깥 설명만 기록하면 실제 서버 오류가 가려지므로 하위 오류도 읽는다.
    private static func errorDetails(_ error: NSError, depth: Int = 0) -> String {
        guard depth < 8 else { return error.localizedDescription }
        var details = ["\(error.domain)(\(error.code)): \(error.localizedDescription)", String(describing: error.userInfo)]
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            details.append(errorDetails(underlying, depth: depth + 1))
        }
        if let partialErrors = error.userInfo["CKPartialErrors"] as? [AnyHashable: NSError] {
            details.append(contentsOf: partialErrors.values.map { errorDetails($0, depth: depth + 1) })
        }
        return details.joined(separator: "\n")
    }
}
