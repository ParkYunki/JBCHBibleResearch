//
//  DocumentViewerErrorLog.swift
//  JBCHBibleResearch
//
//  연구문서 뷰어의 iCloud 다운로드/원본 파일 해석 실패 사유(`downloadStatus = .failed(...)`에 채워지는
//  메시지)를 화면 표시와 별도로 앱 내 저장공간의 로그 파일에도 남긴다 — 화면 메시지를 놓쳐도 나중에
//  확인할 수 있게 하기 위함.
//
//  `TranslationFileMaterializer.translationsDirectory()`와 같은 이유로 Application Support 아래 전용
//  폴더를 쓴다 — Documents는 사용자에게 노출되는 영역이라 내부 로그 파일을 두기에 맞지 않다.
//
import Foundation

enum DocumentViewerErrorLog {
    /// 이 크기를 넘으면 회전한다(로그 무한 증가 방지). 최근 진단이 목적이라 이전 세대 하나만 보존한다.
    private static let maxBytesBeforeRotation = 1_000_000

    private static var logFileURL: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }
        let directory = base.appendingPathComponent("Logs", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("document-viewer-errors.log", isDirectory: false)
    }

    /// `context`(문서 파일명 등)와 `message`(실패 사유)를 타임스탬프와 함께 한 줄로 append한다.
    /// 로깅 실패는 조용히 무시한다 — 로그 남기기가 뷰어 기능을 막아서는 안 된다.
    static func log(context: String, message: String) {
        guard let url = logFileURL else { return }
        rotateIfNeeded(url: url)

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(context): \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: url.path) {
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func rotateIfNeeded(url: URL) {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
              size > maxBytesBeforeRotation else { return }
        let rotatedURL = url.deletingLastPathComponent()
            .appendingPathComponent("document-viewer-errors.1.log", isDirectory: false)
        try? FileManager.default.removeItem(at: rotatedURL)
        try? FileManager.default.moveItem(at: url, to: rotatedURL)
    }
}
