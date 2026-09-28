// swift-tools-version:5.9
//
//  Package.swift
//  PersonSeedEditor
//
//  [2026-09-16 신설] 사용자 요청 — "인물 데이터를 수기로 수정할 수 있도록
//  개발자 페이지에 기능을 추가할 수 있는가?" 처음엔 메인 앱(JBCHBibleResearch)의
//  DEBUG 전용 "개발자" 탭에 화면을 하나 더 추가하는 안을 검토했지만, 그 앱이
//  App Sandbox를 켜고 있어(`JBCHBibleResearch.entitlements` 확인 — 사용자
//  선택 파일 외 임의 경로 접근/파이썬 서브프로세스 실행이 보장되지 않음)
//  저장소의 PersonSeed.json을 자유롭게 읽고 쓰거나 build_reference_data.py를
//  실행하는 게 실기기(이 세션엔 Xcode가 없어 검증 불가)에서 막힐 위험이 컸다.
//  사용자가 직접 "아예 별도 앱을 만드는 것은?"이라고 제안해 — 메인 앱과
//  완전히 분리된, 샌드박스가 없는 이 독립 SwiftUI 커맨드라인 패키지로
//  만들기로 확정했다. 이 방식의 장점:
//    1) 메인 앱(이미 검증된 프로덕션 코드)을 전혀 건드리지 않는다 — 이번
//       기능에 버그가 있어도 실제 배포되는 앱에는 아무 영향이 없다.
//    2) `swift run`으로 실행하는 SPM 실행 파일은 기본적으로 App Sandbox가
//       적용되지 않는다 — PersonSeed.json 직접 읽기/쓰기, python3 서브프로세스
//       실행(재빌드) 모두 별도 엔타이틀먼트 없이 바로 된다.
//    3) Xcode 프로젝트 파일(.xcodeproj)을 손으로 만들 필요가 없다 — 이
//       Package.swift 하나면 충분하고, 구조가 단순해 Xcode 없이 작성해도
//       위험이 적다.
//
//  실행 방법(사용자가 터미널에서): 이 폴더(Tools/PersonSeedEditor)에서
//  `swift run` — 최초 실행은 컴파일 때문에 몇 초~수십 초 걸릴 수 있다.
//
//  ⚠️ [미검증] 이 세션엔 Xcode/Swift 툴체인이 없어 `swift build`로도 컴파일을
//  확인하지 못했다 — 사용자가 실제 Mac에서 `swift run`으로 처음 빌드해 볼 때
//  컴파일 에러가 나올 수 있다. 발견되면 알려주면 바로 고치겠다.
//
import PackageDescription

let package = Package(
    name: "PersonSeedEditor",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "PersonSeedEditor",
            path: "Sources/PersonSeedEditor"
        )
    ]
)
