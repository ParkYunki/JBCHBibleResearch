// swift-tools-version: 6.0
import PackageDescription

// 근거: bible-research-platform-schema.md 0장 — "SwiftData + CloudKit(ModelConfiguration)
// 공유 Swift Package, 3개 타겟(macOS/iPadOS/iOS)이 동일 데이터 레이어 사용".
// 이 패키지는 데이터 모델 레이어만 담는다. 화면(SwiftUI) 레이어는 각 앱 타겟에 남는다.
let package = Package(
    name: "BibleResearchModels",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "BibleResearchModels",
            targets: ["BibleResearchModels"]
        ),
    ],
    targets: [
        .target(
            name: "BibleResearchModels",
            path: "Sources/BibleResearchModels",
            // BibleReferenceStore.swift가 번역본 SQLite 파일을 직접 여는 데 필요
            // (schema.md 1장 — 정적 참조 데이터는 SwiftData가 아니라 원시 SQLite로 접근).
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "BibleResearchModelsTests",
            dependencies: ["BibleResearchModels"],
            path: "Tests/BibleResearchModelsTests"
        ),
    ]
)
