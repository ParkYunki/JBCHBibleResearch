//
//  SharedMemoPayload.swift
//  JBCHBibleResearch
//
//  개인 묵상(`UserMemo`) 하나를 두 기기 사이에서 파일로 주고받기 위한 전송 계층.
//  (1) 전송용 스냅샷 `SharedMemoPayload`
//  (2) 이 앱 전용 파일 형식 `UTType.jbchMemo` — 식별자 문자열은 `Info.plist`의
//      `UTExportedTypeDeclarations`/`CFBundleDocumentTypes`와 정확히 같아야 한다
//  (3) 인코딩/디코딩 `SharedMemoFile`, `ShareLink`용 `Transferable` 래퍼 `TransferableSharedMemo`
//
//  내보내기는 `MemoDetailView`의 공유 버튼, 받기는 `.onOpenURL` → `PendingMemoImportRequest`가 쓴다.
//

import Foundation
import UniformTypeIdentifiers
import CoreTransferable
import BibleResearchModels

/// `UserMemo`(SwiftData `@Model`, 참조 타입이라 그대로 인코딩할 수 없음) 하나를 옮기기 위한 JSON 스냅샷.
///
/// `nonisolated`: 기본 액터 격리(`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) 때문에 표시하지 않으면
/// 합성된 `Codable` 준수가 MainActor에 격리되어 비격리인 `SharedMemoFile.encode`/`decode`에서 쓸 수 없다.
/// 상태 없는 순수 값 타입뿐이라 비격리로 둬도 안전하다.
///
/// `id`/`folder`는 담지 않는다:
/// - `id`를 옮기면 두 기기의 레코드가 같은 UUID를 공유하게 되므로, 받는 쪽은 항상 새 `UUID`로 레코드를 만든다.
/// - 폴더는 담지 않으므로 받는 쪽 `UserMemo.folder`는 항상 `nil`이다(태그는 `tagNames`로 전달).
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
    /// 받는 쪽 미리보기에 작성 시각을 참고용으로 보여준다. 받는 기기의 `UserMemo.createdAt`은 추가 시점의 `.now`로 새로 남긴다.
    var originalCreatedAt: Date
}

extension UTType {
    /// 이 앱 전용 "개인 묵상 공유 파일" 형식. 순수 JSON이라 `.json`에 속하게 선언해, 이 형식을 모르는 앱에서도 텍스트로 볼 수 있다.
    /// 식별자 문자열은 `Info.plist`에 등록된 것과 정확히 같아야 시스템이 이 앱이 여는 형식으로 인식한다.
    static var jbchMemo: UTType {
        UTType(exportedAs: "com.jbch.bibleresearch.memo", conformingTo: .json)
    }
}

/// `.jbchmemo` 파일의 인코딩/디코딩. 내보내기와 받기 양쪽이 같은 로직을 쓴다.
///
/// `nonisolated`: `TransferableSharedMemo`의 `FileRepresentation` `exporting` 클로저는 MainActor 밖에서 실행되므로,
/// 기본 액터 격리 상태면 `encode`/`fileExtension` 호출이 격리 에러가 된다. 상태 없는 순수 함수뿐이라 타입 전체를 비격리로 둔다.
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

/// `ShareLink`용 `Transferable` 래퍼. 파일 인코딩/쓰기는 값이 만들어질 때가 아니라 사용자가 공유 시트에서
/// 항목을 고르는 순간(`exporting` 클로저)에만 일어나 항상 최신 내용이 담긴다.
/// 값 자체는 가벼워, `MemoDetailView`가 매번 현재 상태로 새로 만들어 넘긴다.
struct TransferableSharedMemo: Transferable {
    let payload: SharedMemoPayload
    /// 공유 시트/파일 이름에 쓸 라벨(예: "창세기 1장 묵상"). 파일명에 못 쓰는 문자 치환은 여기서 한다.
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
