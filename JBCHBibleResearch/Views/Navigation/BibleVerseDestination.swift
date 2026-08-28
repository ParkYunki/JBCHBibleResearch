//
//  BibleVerseDestination.swift
//  JBCHBibleResearch
//
//  [2026-08-26 신설] 사용자 재보고 — "검색결과의 성경장절을 클릭한 후 다시
//  사이드바 검색창에 검색을 하면 오른쪽 영역이 검색결과로 바뀌지 않음(위
//  '<' 버튼을 눌러야만 바뀜)"이 `detailNavigationPath = NavigationPath()`
//  (SidebarNavigationView.swift 9.1) + `SearchResultsPopRequest`(13장)를
//  거쳐서도 계속 재현됐다. Apple 개발자 포럼
//  (https://developer.apple.com/forums/thread/743963, 채택된 답변 참고)에서
//  확인한 진짜 원인 — `NavigationStack(path: Binding<NavigationPath>)`가
//  추적하는 건 값 기반 `NavigationLink(value:)` + `.navigationDestination(for:)`
//  조합으로 push된 항목뿐이고, `SearchView.swift`가 성경 조회로 이동할 때
//  써 온 클로저 기반 `NavigationLink { BibleReadingView(...) }`는 **애초에
//  그 path에 전혀 기록되지 않는다.** 그래서 `path`를 빈 값으로 대입해도
//  이 방식으로 push된 화면은 pop되지 않았다 — 기존에 만든 리셋 메커니즘
//  자체는 올바르게 동작하고 있었지만, 정작 pop 대상이 될 수 없는 종류의
//  push를 상대하고 있었던 것이 문제였다.
//
//  근본적인 수정: 성경 조회로 이동하는 `NavigationLink`를 값 기반으로
//  바꾸고, 그 값을 이 타입 하나로 통일한다. `SearchView.swift`의 여섯
//  곳(성경구절 검색 결과, 메모 검색 결과, 인물·지명/예언/주제·속성/서사
//  카드)이 전부 "책+장(+절)"만 있으면 화면을 재구성할 수 있는 동일한
//  목적지라 하나의 타입으로 충분하다 — 메모/말씀요약/문서 검색 결과처럼
//  성경 조회가 아닌 다른 화면으로 가는 링크는 이번 신고 범위 밖이라
//  손대지 않았다(그쪽도 클로저 기반이라 이론상 같은 버그가 있을 수 있지만,
//  아직 신고되지 않은 영역까지 미리 고치는 건 근거 없는 리팩토링이다).
//
struct BibleVerseDestination: Hashable {
    let bookId: Int
    let chapter: Int
    /// nil이면 장만 지정(예: 메모 검색 결과 → 그 장으로만 이동) — `BibleReadingView.
    /// initialVerse`의 기본 동작(장의 시작 부분을 보여주고 별도 하이라이트는
    /// 하지 않음)과 동일하게 흘러간다.
    let verse: Int?
}
