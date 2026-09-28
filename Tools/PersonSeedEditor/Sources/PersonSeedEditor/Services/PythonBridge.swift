import Foundation

//
//  PythonBridge.swift
//  PersonSeedEditor
//
//  [2026-09-16 신설] `apply_person_edit.py`/`build_reference_data.py`를
//  `Process`로 실행한다. 이 패키지는 App Sandbox가 없는 SPM 실행 파일이라
//  (`Package.swift` 상단 주석 참고) 임의 경로의 파이썬 서브프로세스를 실행하는
//  데 별도 엔타이틀먼트가 필요 없다.
//
//  ⚠️ `/usr/bin/env python3`를 쓴다 — 시스템 python3 경로가 Mac마다
//  다를 수 있어(Homebrew/pyenv 등) `env`로 PATH에서 찾게 한다. 이 세션(원격
//  기기 셸)에서 `python3 apply_person_edit.py ...`가 실제로 정상 동작하는
//  것까지는 확인했지만, `Process`를 통한 실행 자체는 Xcode/Swift 툴체인이
//  없어 검증하지 못했다 — 사용자의 실제 Mac에서 처음 "저장"을 눌러볼 때
//  확인이 필요하다.
enum PythonBridgeError: Error, LocalizedError {
    case processLaunchFailed(String)
    case nonZeroExit(status: Int32, stderr: String, stdout: String)
    case decodingFailed(String)
    case appError(String)

    var errorDescription: String? {
        switch self {
        case .processLaunchFailed(let message):
            return "파이썬 프로세스를 시작하지 못했습니다: \(message)"
        case .nonZeroExit(let status, let stderr, let stdout):
            var text = "파이썬 스크립트가 오류로 종료됐습니다(종료 코드 \(status))."
            if !stderr.isEmpty { text += "\n\(stderr)" }
            if !stdout.isEmpty { text += "\n\(stdout)" }
            return text
        case .decodingFailed(let message):
            return "파이썬 응답을 해석하지 못했습니다: \(message)"
        case .appError(let message):
            return message
        }
    }
}

struct PythonBridge {
    /// 파이썬 스크립트를 돌릴 작업 디렉터리 — `ReferenceDataSource`
    /// (build_reference_data.py가 자기 디렉터리 기준 상대 경로로 다른
    /// 시드 파일들을 열기 때문에 반드시 이 디렉터리에서 실행해야 한다).
    let workingDirectory: URL

    private func runSync(arguments: [String], stdinData: Data?) throws -> (stdout: Data, stderr: Data) {
        let process = Process()
        process.currentDirectoryURL = workingDirectory
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3"] + arguments

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw PythonBridgeError.processLaunchFailed(error.localizedDescription)
        }

        // [주의] stdin에 큰 데이터를 쓰면서 동시에 stdout을 blocking read하면
        // 파이프 버퍼가 가득 찼을 때 교착(deadlock)될 수 있다 — 이 세션 하나
        // 인물 항목(payload)은 몇 KB 수준이라 실제로 문제될 가능성은 낮지만,
        // 쓰기를 별도 큐에서 하도록 방어적으로 분리했다.
        let writeQueue = DispatchQueue(label: "PersonSeedEditor.PythonBridge.stdin")
        writeQueue.async {
            if let stdinData {
                stdinPipe.fileHandleForWriting.write(stdinData)
            }
            stdinPipe.fileHandleForWriting.closeFile()
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw PythonBridgeError.nonZeroExit(
                status: process.terminationStatus,
                stderr: String(data: stderrData, encoding: .utf8) ?? "",
                stdout: String(data: stdoutData, encoding: .utf8) ?? ""
            )
        }
        return (stdoutData, stderrData)
    }

    private struct UpsertResponse: Decodable {
        let ok: Bool
        let error: String?
        let action: String?
        let idx: String?
        let total: Int?
    }

    private struct DeleteResponse: Decodable {
        let ok: Bool
        let error: String?
        let action: String?
        let idx: String?
        let removed_word: String?
        let total: Int?
    }

    private struct NextIdxResponse: Decodable {
        let ok: Bool
        let error: String?
        let next_idx: String?
    }

    func nextIdx(scriptPath: URL, seedPath: URL) throws -> String {
        let (stdout, _) = try runSync(
            arguments: [scriptPath.path, "--seed-path", seedPath.path, "next-idx"],
            stdinData: nil
        )
        let response: NextIdxResponse
        do {
            response = try JSONDecoder().decode(NextIdxResponse.self, from: stdout)
        } catch {
            throw PythonBridgeError.decodingFailed(error.localizedDescription)
        }
        guard response.ok, let value = response.next_idx else {
            throw PythonBridgeError.appError(response.error ?? "next-idx 응답을 알 수 없습니다.")
        }
        return value
    }

    /// - Returns: "updated" 또는 "added"
    @discardableResult
    func upsert(_ entry: PersonSeedEntry, scriptPath: URL, seedPath: URL, allowNew: Bool) throws -> String {
        let payload: Data
        do {
            payload = try JSONEncoder().encode(entry)
        } catch {
            throw PythonBridgeError.appError("항목을 JSON으로 바꾸지 못했습니다: \(error.localizedDescription)")
        }
        var args = [scriptPath.path, "--seed-path", seedPath.path, "upsert"]
        if allowNew { args.append("--allow-new") }
        let (stdout, _) = try runSync(arguments: args, stdinData: payload)
        let response: UpsertResponse
        do {
            response = try JSONDecoder().decode(UpsertResponse.self, from: stdout)
        } catch {
            throw PythonBridgeError.decodingFailed(error.localizedDescription)
        }
        guard response.ok, let action = response.action else {
            throw PythonBridgeError.appError(response.error ?? "upsert 응답을 알 수 없습니다.")
        }
        return action
    }

    /// - Returns: 삭제된 항목의 `word`
    @discardableResult
    func delete(idx: String, scriptPath: URL, seedPath: URL) throws -> String {
        let (stdout, _) = try runSync(
            arguments: [scriptPath.path, "--seed-path", seedPath.path, "delete", "--idx", idx],
            stdinData: nil
        )
        let response: DeleteResponse
        do {
            response = try JSONDecoder().decode(DeleteResponse.self, from: stdout)
        } catch {
            throw PythonBridgeError.decodingFailed(error.localizedDescription)
        }
        guard response.ok else {
            throw PythonBridgeError.appError(response.error ?? "delete 응답을 알 수 없습니다.")
        }
        return response.removed_word ?? ""
    }

    /// `build_reference_data.py`를 실행하고 stdout/stderr을 한 줄씩
    /// `onOutput`으로 실시간 전달한다(재빌드 로그 뷰용). `onOutput`은
    /// 메인 액터에서 호출된다.
    func rebuild(scriptPath: URL, onOutput: @escaping @MainActor (String) -> Void) throws {
        let process = Process()
        process.currentDirectoryURL = workingDirectory
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", scriptPath.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                onOutput(text)
            }
        }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            throw PythonBridgeError.processLaunchFailed(error.localizedDescription)
        }
        process.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil

        if process.terminationStatus != 0 {
            throw PythonBridgeError.nonZeroExit(status: process.terminationStatus, stderr: "", stdout: "")
        }
    }
}
