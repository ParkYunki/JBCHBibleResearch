import Foundation

//
//  PersonSeedStore.swift
//  PersonSeedEditor
//
//  [2026-09-16 신설] 화면이 쓰는 단일 진실 공급원 — PersonSeed.json 전체를
//  메모리에 올려 두고(현재 3068건, 파일 크기 수 MB대라 macOS 앱에서 전체를
//  들고 있는 데 문제 없음) 목록/검색/편집/추가/삭제를 모두 이 배열 기준으로
//  다룬다. 실제 디스크 반영은 전부 `PythonBridge`(→ apply_person_edit.py)를
//  거친다 — 이 클래스는 성공하면 메모리 배열도 같은 내용으로 갱신해 화면과
//  파일이 항상 일치하게 유지한다.
@MainActor
final class PersonSeedStore: ObservableObject {
    @Published private(set) var persons: [PersonSeedEntry] = []
    @Published var isLoading = false
    @Published var isBusy = false
    @Published var lastError: String?
    @Published var lastMessage: String?
    @Published var rebuildLog: String = ""
    @Published var isRebuilding = false

    private let bridge = PythonBridge(workingDirectory: RepoPaths.referenceDataSourceDir)

    /// `word` 또는 `word2`(별칭) 중 하나라도 정확히 같은 이름을 가진 모든
    /// 항목 — "동명이인 후보" 조회용. 별도 sqlite 조회 없이 지금 메모리에
    /// 올라와 있는 PersonSeed.json 원본만으로 계산한다(이 화면이 다루는
    /// 데이터의 원천이 그것뿐이므로 — build 후 sqlite와는 이론상 항상 같은
    /// 내용이어야 한다).
    func candidates(named name: String) -> [PersonSeedEntry] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return persons.filter { $0.word == trimmed || $0.word2.contains(trimmed) }
    }

    func load() {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let seedURL = RepoPaths.seedPath
        guard FileManager.default.fileExists(atPath: seedURL.path) else {
            lastError = "PersonSeed.json을 찾을 수 없습니다 — 이 도구가 저장소 밖으로 옮겨졌을 수 있습니다.\n예상 경로: \(seedURL.path)"
            return
        }
        do {
            let data = try Data(contentsOf: seedURL)
            persons = try JSONDecoder().decode([PersonSeedEntry].self, from: data)
        } catch {
            lastError = "PersonSeed.json을 읽는 데 실패했습니다: \(error.localizedDescription)"
        }
    }

    func nextIdx() -> String {
        // [2026-09-16] 파이썬을 다시 호출하지 않고 지금 메모리에 있는 배열
        // 기준으로 바로 계산한다 — `apply_person_edit.py`의 next-idx 명령과
        // 정확히 같은 규칙(가장 큰 숫자 idx + 1)이라 결과가 같다. 저장 시
        // 어차피 upsert가 idx 중복 여부를 다시 검사하므로 안전하다.
        let maxIdx = persons.compactMap { Int($0.idx) }.max() ?? 0
        return String(maxIdx + 1)
    }

    func addBlankPerson() -> PersonSeedEntry {
        PersonSeedEntry.blank(idx: nextIdx())
    }

    /// 새 인물이면 `isNew: true`로 호출 — `--allow-new`를 붙여 upsert한다.
    func save(_ entry: PersonSeedEntry, isNew: Bool) async {
        isBusy = true
        lastError = nil
        lastMessage = nil
        defer { isBusy = false }
        do {
            let action = try await Task.detached(priority: .userInitiated) { [bridge] in
                try bridge.upsert(
                    entry,
                    scriptPath: RepoPaths.applyEditScriptPath,
                    seedPath: RepoPaths.seedPath,
                    allowNew: isNew
                )
            }.value
            if let index = persons.firstIndex(where: { $0.idx == entry.idx }) {
                persons[index] = entry
            } else {
                persons.append(entry)
            }
            lastMessage = action == "added"
                ? "새 인물(idx=\(entry.idx))을 추가했습니다."
                : "idx=\(entry.idx) 항목을 저장했습니다."
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func delete(_ entry: PersonSeedEntry) async {
        isBusy = true
        lastError = nil
        lastMessage = nil
        defer { isBusy = false }
        do {
            let removedWord = try await Task.detached(priority: .userInitiated) { [bridge] in
                try bridge.delete(idx: entry.idx, scriptPath: RepoPaths.applyEditScriptPath, seedPath: RepoPaths.seedPath)
            }.value
            persons.removeAll { $0.idx == entry.idx }
            lastMessage = "\(removedWord)(idx=\(entry.idx))을(를) 삭제했습니다."
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// `build_reference_data.py`를 실행해 ReferenceData.sqlite까지 다시
    /// 만든다 — 지금까지 이 세션이 터미널에서 직접 실행해 온 것과 완전히
    /// 같은 스크립트다. 로그를 실시간으로 `rebuildLog`에 누적한다.
    func rebuild() async {
        isRebuilding = true
        lastError = nil
        lastMessage = nil
        rebuildLog = ""
        defer { isRebuilding = false }
        do {
            try await Task.detached(priority: .userInitiated) { [bridge] in
                try bridge.rebuild(scriptPath: RepoPaths.buildScriptPath) { [weak self] chunk in
                    self?.rebuildLog += chunk
                }
            }.value
            lastMessage = "재빌드가 끝났습니다 — ReferenceData.sqlite가 갱신됐습니다."
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
