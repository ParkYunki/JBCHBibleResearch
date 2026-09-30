//
//  PlaceholderScreens.swift
//  JBCHBibleResearch
//
//  iPhone "더보기" 탭의 메뉴 화면(`MorePlaceholderView`)과 내부용 자리표시 화면.
//  나머지 화면은 각자의 View 파일로 구현되어 있어 대체 대상 플레이스홀더는 남아 있지 않다.
//

import SwiftUI

private struct ComingSoonView: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3)
            Text("곧 제공됩니다")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(title)
    }
}

/// iPhone "더보기" 탭 — 태그 관계·개요·내 설교·설정으로 진입한다.
/// 태그 관계·개요·내 설교는 NavigationLink push가 아니라 `.fullScreenCover`로 연다
/// (macOS/iPadOS의 별도 창에 대응하는 iPhone식 처리). 세 화면 모두 자체 `.searchable`이나
/// 자체 `NavigationStack`을 쓰기 때문이다.
///
/// 개요(`OutlineTreeView`)는 아이폰 분기에서 자기 `NavigationStack(path:)`를 이미
/// 소유하므로 이 파일에서 다시 `NavigationStack`으로 감싸지 않는다 — 스택이 중첩되면
/// 공식적으로 지원되지 않는 구성이 된다.
///
/// `isOutlinePresented`는 이 화면 로컬 상태가 아니라 `PhoneTabView`가 들고 바인딩으로
/// 내려준다. 성경 조회 화면의 "개요 화면 열기"(`AppNavigationRequest.shared.request(.outline)`)는
/// "더보기"가 선택된 탭이 아닐 때도 모달을 띄워야 하는데, 선택되지 않은 탭 안의 모달은
/// 그 탭이 보이기 전까지 나타나지 않기 때문이다.
struct MorePlaceholderView: View {
    @State private var isTagRelationsPresented = false
    // `SermonHomeView`가 `.searchable`을 쓰므로 `.tagRelations`/`.outline`과 같은 이유로
    // NavigationLink push가 아니라 `.fullScreenCover`로 연다.
    @State private var isSermonHomePresented = false
    @Binding var isOutlinePresented: Bool

    var body: some View {
        List {
            Button {
                isTagRelationsPresented = true
            } label: {
                Label("태그 관계", systemImage: "circle.grid.cross")
            }
            Button {
                isOutlinePresented = true
            } label: {
                Label("개요", systemImage: "list.bullet.rectangle")
            }
            Button {
                isSermonHomePresented = true
            } label: {
                Label("내 설교", systemImage: "mic")
            }
            // macOS `Settings` Scene용 최상위 `TabView`를 가진 `SettingsView`를 직접 push하면
            // 하단 탭바가 이중으로 뜨므로, iPhone 전용 진입 화면 `SettingsHomeView`를 쓴다.
            NavigationLink {
                SettingsHomeView()
            } label: {
                Label("설정", systemImage: "gearshape")
            }
        }
        .navigationTitle("더보기")
        // 다른 탭 화면들과 맞춰 타이틀을 인라인으로 표시한다. 멀티플랫폼 단일 타겟이라
        // 아래 `.fullScreenCover`와 마찬가지로 `#if os(iOS)`로 감싼다.
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // `fullScreenCover`는 iOS/iPadOS 전용이라 macOS에는 심볼이 없다. 멀티플랫폼 단일
        // 타겟이라 macOS 빌드도 이 파일을 컴파일하므로 `#if os(iOS)`로 감싼다.
        #if os(iOS)
        .fullScreenCover(isPresented: $isTagRelationsPresented) {
            NavigationStack {
                TagRelationsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("닫기") { isTagRelationsPresented = false }
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: $isSermonHomePresented) {
            NavigationStack {
                SermonHomeView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("닫기") { isSermonHomePresented = false }
                        }
                    }
            }
        }
        #endif
    }
}
