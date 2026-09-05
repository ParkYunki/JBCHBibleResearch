//
//  WhatsNewContent.swift
//  JBCHBibleResearch
//
//  [2026-08-28 신설] 사용자 요청 — "업데이트 할때마다 어떤 것을 업데이트 했는지
//  소개해주는 화면 필요함. 처음 설치하는 사람에게는 필요하지 않음." 이 화면
//  (`WhatsNewOverlay.swift`)이 버전별로 보여줄 안내 문구를 여기 한곳에 모아
//  둔다 — 화면 쪽 코드는 이 목록에서 "지금 버전에 해당하는 항목"만 찾아
//  보여줄 뿐, 문구 자체는 건드리지 않는다.
//
//  [유지보수 방법] 새 버전을 배포하기 전, 그 버전에서 사용자가 실제로 체감할
//  변경 사항(버그 수정 포함, 다만 기술적인 원인 설명이 아니라 "무엇이
//  좋아졌는지"를 사용자 언어로)을 이 배열에 새 `WhatsNewEntry`로 추가하면
//  된다 — `version`은 `project.pbxproj`의 `MARKETING_VERSION`(예: "1.0")과
//  정확히 같은 문자열이어야 한다(다르면 `WhatsNewOverlay`가 못 찾아 조용히
//  건너뛴다).
//
//  [1.0 항목 출처] 사용자 확인 — "제가 이번 세션 작업내역을 사용자 언어로
//  번역해 1.0 항목 시딩." 이 세션에서 실제로 반영된 사용자 체감 변경 사항
//  (성경조회/통합검색/문서 재구조화 라운드 전체)을 기술 용어 없이 옮겼다.
//

import Foundation

struct WhatsNewEntry: Identifiable {
    let version: String
    let items: [String]

    var id: String { version }
}

enum WhatsNewContent {
    static let entries: [WhatsNewEntry] = [
        WhatsNewEntry(version: "1.0.2", items: [
            "UI 색상 및 기타 레이아웃 수정",
            "성경 스크롤 버그 수정",
            "검색 이력 기능 추가"
        ]),
        WhatsNewEntry(version: "1.0.1", items: [
            "기타 버그 수정",
            "pdf 검색기능 보정",
            "성경 배경및 글꼴의 테마색상 추가"
        ]),
        WhatsNewEntry(version: "1.0", items: [
            "성경 조회 화면에 책갈피 기능을 추가했습니다. 자주 보는 장·절을 저장해 두고, 목록에서 골라 바로 이동할 수 있습니다.",
            "통합 검색 결과에서 성경구절을 탭하면 이제 정확하게 성경 조회 화면의 해당 구절로 이동합니다.",
            "아이폰 하단 메뉴에 \"통합 검색\" 탭을 새로 추가했습니다. \"개요\"는 \"더보기\" 메뉴 안에서 볼 수 있습니다.",
            "성경 조회 화면에서 관련 연구문서를 눌렀을 때 반응이 없거나 앱이 종료되던 문제를 고쳤습니다.",
            "\"번역본 선택\"과 \"말씀 요약\" 아이콘이 서로 구분되도록 바꿨습니다.",
            "연구문서 업로드 형식을 hwp·pdf 중심으로 정리했습니다."
        ])
    ]

    /// `version`(예: "1.0")에 해당하는 항목을 찾는다. 이 목록에 아직 등록되지
    /// 않은 버전이면 nil — 호출부(`WhatsNewOverlay`)는 이 경우 화면을 보여주지
    /// 않고 조용히 넘어간다(빈 "새로워진 점" 화면을 보여주는 대신).
    static func entry(for version: String) -> WhatsNewEntry? {
        entries.first { $0.version == version }
    }
}
