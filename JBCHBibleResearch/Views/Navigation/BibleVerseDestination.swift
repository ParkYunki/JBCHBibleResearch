//
//  BibleVerseDestination.swift
//  JBCHBibleResearch
//
//  성경 조회 화면으로 이동하는 값 기반 내비게이션 목적지.
//
//  `NavigationStack(path: Binding<NavigationPath>)`는 값 기반
//  `NavigationLink(value:)` + `.navigationDestination(for:)`로 push된 항목만 추적한다.
//  클로저 기반 `NavigationLink { ... }`는 path에 기록되지 않아 path를 비워도 pop되지 않는다.
//  그래서 `SearchView`에서 성경 조회로 가는 링크(성경구절/메모 검색 결과, 인물·지명/예언/
//  주제·속성/서사 카드)를 모두 이 타입 하나로 통일했다. 책+장(+절)만 있으면 화면을
//  재구성할 수 있다. 성경 조회가 아닌 다른 화면으로 가는 링크는 이 타입의 대상이 아니다.
//
struct BibleVerseDestination: Hashable {
    let bookId: Int
    let chapter: Int
    /// nil이면 장만 지정한다. `BibleReadingView.initialVerse`의 기본 동작
    /// (장의 시작 부분을 보여주고 별도 하이라이트는 하지 않음)과 같다.
    let verse: Int?
}
