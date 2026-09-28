//
//  SharedMemoPayload.swift
//  JBCHBibleResearch
//
//  [2026-09-13 신설] 사용자 요청 — "묵상한 내용을 에어드롭으로 전달할 수
//  있는가?" → "개인묵상을 공유받으면 이 앱의 개인묵상으로 들어갈수 있도록
//  할수 있는가?" 두 기기가 이 앱을 통해 개인 묵상(`UserMemo`) 하나를
//  파일로 주고받기 위한 전송 계층이다. 세 부분으로 나뉜다 —
//  (1) 전송용 스냅샷 구조체(`SharedMemoPayload`),
//  (2) 이 앱 전용 파일 형식 등록(`UTType.jbchMemo` — 실제 확장자/문서타입
//      선언 자체는 `Info.plist`의 `UTExportedTypeDeclarations`/
//      `CFBundleDocumentTypes`에 있다. 이 파일의 식별자 문자열은 그 두
//      곳과 정확히 같아야 한다),
//  (3) 그 파일을 실제로 읽고 쓰는 인코딩/디코딩(`SharedMemoFile`)과
//      `ShareLink`가 요구하는 `Transferable` 래퍼(`TransferableSharedMemo`).
//
//  내보내기 쪽은 `Views/Memo/MemoDetailView.swift`의 공유 버튼이, 받기
//  쪽은 `JBCHBibleResearchApp.swift`의 `.onOpenURL` → `PendingMemoImportRequest`
//  (별도 파일, `PendingMemoImportRequest.swift`)가 이 파일을 함께 쓴다.
//
//  ⚠️ [컴파일러 없는 환경에서 작성됨] 이 세션엔 Xcode/Swift 컴파일러가
//  없어 직접 빌드해 확인하지 못했다. `ShareLink`/`Transferable`/
//  `FileRepresentation`은 iOS 16+/macOS 13+의 안정된 표준 API이고(이
//  프로젝트 배포 타깃 26.5보다 훨씬 아래), Apple 공식 문서/샘플 코드가
//  보여주는 형태를 그대로 따랐다 — 다만 실기기에서 반드시 한 번 확인이
//  필요하다.
//

import Foundation
import UniformTypeIdentifiers
import CoreTransferable
import BibleResearchModels

/// [2026-09-13 신설] `UserMemo`(SwiftData `@Model`, 참조 타입이라 그대로
/// 인코딩할 수 없음) 하나를 다른 기기로 옮기기 위해 필요한 필드만 뽑은
/// 평범한 JSON 스냅샷.
///
/// [2026-09-17 추가, 빌드 경고 수정] `nonisolated` 표시 — 바로 아래
/// `SharedMemoFile`이 이미 겪었던 것과 똑같은 문제(그 타입 선언부 주석 참고,
/// `Services/BookNameTable.swift`가 원조 사례)다. 이 프로젝트 기본 액터 격리
/// 설정(`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) 때문에 이 struct를
/// `nonisolated`로 표시하지 않으면 합성된 `Encodable`/`Decodable` 준수 자체가
/// MainActor에 격리되는데, `SharedMemoFile.encode`/`decode`(이미 `nonisolated`)가
/// 그 준수를 비격리 컨텍스트에서 쓰려다 "Swift 6에서는 에러가 될 경고"가
/// 났다. `BookNameTable`과 같은 이유로 안전하다 — 이 struct도 상태 없는
/// 순수 값 타입(Int/String/Date 등)뿐이라 비격리로 둬도 동시성 안전성에
/// 영향이 없다.
///
/// `id`/`folder`는 일부러 담지 않는다:
/// - `id`를 그대로 옮기면 두 기기의 로컬 레코드가 같은 UUID를 공유하게
///   되어 이후 조회/재인덱싱에서 서로 다른 두 메모가 한 식별자를 다투게
///   된다 — 받는 쪽은 항상 새 `UUID`로 새 레코드를 만든다
///   (`PendingMemoImportRequest.importIntoLibrary` 참고).
/// - 폴더는 사용자 결정("폴더는 폴더 없음으로 받되, 태그 정보는 같이
///   보내기")에 따라 이 페이로드 자체에 담지 않는다 — 받는 쪽
///   `UserMemo.folder`는 항상 `nil`로 시작한다.
nonisolated struct SharedMemoPayload: Codable {
    var bookId: Int
    var chapter: Int
    var verse: Int?
    var rangeStart: Int?
    var rangeEnd: Int?
    var annotationTranslationCode: String?
    var anchorText: String?
    var contentText: String
    var tagNames: [String]
    /// 받는 쪽 미리보기 화면에 "언제 작성된 묵상인지" 참고용으로만 보여준다
    /// — 받는 기기의 `UserMemo.createdAt`은 실제로 추가되는 지금 시각으로
    /// 새로 남긴다(이 앱의 다른 모든 생성 경로와 같은 규칙 — `UserMemo.init`
    /// 기본값이 `.now`인 것과 동일).
    var originalCreatedAt: Date
}

extension UTType {
    /// 이 앱 전용 "개인 묵상 공유 파일" 형식. 순수 JSON이라 `.json`에
    /// 속하게 선언해, 이 형식을 모르는 다른 기기/앱에서 열어도 최소한
    /// 텍스트로는 내용을 볼 수 있다. 이 식별자 문자열은 `Info.plist`의
    /// `UTExportedTypeDeclarations`/`CFBundleDocumentTypes`에 등록된 것과
    /// 정확히 같아야 시스템이 "이 앱이 여는 파일 형식"으로 인식한다.
    static var jbchMemo: UTType {
        UTType(exportedAs: "com.jbch.bibleresearch.memo", conformingTo: .json)
    }
}

/// `.jbchmemo` 파일의 인코딩/디코딩을 한 곳에 모은다 — 내보내기
/// (`TransferableSharedMemo`)와 받기(`PendingMemoImportRequest`) 양쪽이
/// 같은 로직을 쓴다.
///
/// [2026-09-16 추가, 빌드 에러 수정] `nonisolated` 표시 — 이 프로젝트의
/// 기본 액터 격리 설정(`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
/// project.pbxproj)때문에 명시하지 않으면 이 타입의 static 멤버가 전부
/// 암묵적으로 MainActor에 격리된다. 그런데 바로 아래 `TransferableSharedMemo`의
/// `FileRepresentation` `exporting` 클로저는 Apple `Transferable` API 자체가
/// MainActor 밖(비격리 컨텍스트)에서 실행하므로, `encode`/`fileExtension`을
/// 거기서 호출하면 "Main actor-isolated ... cannot be called from outside of
/// the actor" 에러가 난다 — `Services/BookNameTable.swift`가 겪은 것과 같은
/// 종류의 문제이고, 그곳과 동일하게 타입 전체를 `nonisolated`로 표시해
/// 해결한다(개별 멤버마다 표시하는 대신 — 이 타입엔 상태가 없는 순수
/// 인코딩/디코딩 함수뿐이라 타입 전체를 비격리로 둬도 동시성 안전성에
/// 영향이 없다). `decode`는 현재 호출부(`PendingMemoImportRequest.
/// handleOpenedFile`, MainActor 컨텍스트)에서는 에러가 보고되지 않았지만,
/// 같은 타입 안에 있으므로 함께 비격리된다 — MainActor에서 nonisolated
/// 함수를 호출하는 것은 항상 허용되므로 그 호출부엔 영향이 없다.
nonisolated enum SharedMemoFile {
    static let fileExtension = "jbchmemo"

    static func encode(_ payload: SharedMemoPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    static func decode(_ data: Data) throws -> SharedMemoPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SharedMemoPayload.self, from: data)
    }
}

/// `ShareLink`가 요구하는 `Transferable` 래퍼. 실제 파일 인코딩/쓰기는
/// 값이 만들어지는 시점(뷰의 `body`가 다시 그려질 때마다)이 아니라, 사용자가
/// 공유 시트에서 실제로 항목을 고르는 순간에만(`FileRepresentation`의
/// `exporting` 클로저) 일어난다 — 그래야 화면을 열어 둔 채 내용을 수정한
/// 뒤 공유해도 항상 최신 내용이 담긴다(`MemoDetailView`의 공유 버튼이 매번
/// 현재 `memo`/`memoTags` 상태로 새 `TransferableSharedMemo` 값을 만들어
/// 넘기는 이유이기도 하다 — 값 자체는 가볍고, 무거운 작업(파일 쓰기)만
/// 미뤄 둔다).
struct TransferableSharedMemo: Transferable {
    let payload: SharedMemoPayload
    /// 공유 시트/파일 이름에 쓸 사람이 읽는 라벨(예: "창세기 1장 묵상") —
    /// 실제 파일명에 못 쓰는 문자 치환은 여기서 한다.
    let displayName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .jbchMemo) { transferable in
            let data = try SharedMemoFile.encode(transferable.payload)
            let safeName = transferable.displayName
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("\(safeName).\(SharedMemoFile.fileExtension)")
            try data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
