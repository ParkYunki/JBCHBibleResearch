import Foundation

//
//  RepoPaths.swift
//  PersonSeedEditor
//
//  [2026-09-16 신설] `swift run`은 어느 디렉터리에서 실행하든(현재 작업
//  디렉터리, `FileManager.default.currentDirectoryPath`) 동작해야 하므로
//  런타임 CWD에 의존하지 않는다 — 대신 이 파일의 "컴파일 시점 절대 경로"
//  (`#filePath`, 이 파일을 빌드한 바로 그 Mac의 실제 소스 경로)를 기준으로
//  저장소 루트를 역산한다. 이 패키지가 <저장소 루트>/Tools/PersonSeedEditor/
//  Sources/PersonSeedEditor/RepoPaths.swift 위치에 있다는 전제(이 저장소의
//  현재 구조) 하에, 5단계 위로 올라가면 저장소 루트다.
//
//  ⚠️ 이 패키지 폴더 자체를 저장소 밖으로 옮기면(예: 다른 위치에 복사) 이
//  계산이 깨진다 — 그 경우 아래 `repoRoot`가 잘못된 경로를 가리키고,
//  `PersonSeedStore.load()`가 "PersonSeed.json을 찾을 수 없습니다" 오류로
//  바로 알려준다(조용히 틀린 파일을 쓰지 않도록).
enum RepoPaths {
    static let repoRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        // RepoPaths.swift -> Sources/PersonSeedEditor -> Sources -> PersonSeedEditor(패키지) -> Tools -> 저장소 루트
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url
    }()

    static var referenceDataSourceDir: URL {
        repoRoot.appendingPathComponent("ReferenceDataSource", isDirectory: true)
    }

    static var seedPath: URL {
        referenceDataSourceDir.appendingPathComponent("PersonSeed.json", isDirectory: false)
    }

    static var applyEditScriptPath: URL {
        referenceDataSourceDir.appendingPathComponent("apply_person_edit.py", isDirectory: false)
    }

    static var buildScriptPath: URL {
        referenceDataSourceDir.appendingPathComponent("build_reference_data.py", isDirectory: false)
    }
}
