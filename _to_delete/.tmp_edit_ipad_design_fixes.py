#!/usr/bin/env python3
"""아이패드 디자인 수정 4건.

1) SidebarNavigationView.swift — "왼쪽 사이드바 선택된 기능의 파란색 ->
   테마대로." 이미 macOS용으로 확인된 `.tint(#D1A35E)`가 `sidebarMenuList`
   (안쪽 List)에 걸려 있는데 아이패드에서는 여전히 시스템 기본 파란색이
   보인다는 보고 — `NavigationSplitView`가 플랫폼별로 사이드바 선택 강조색을
   다르게 해석(macOS AppKit vs iPadOS UIKit 브리징)해 안쪽 List의 `.tint()`
   만으로는 부족할 수 있다는 판단으로, `NavigationSplitView` 자신을 감싸는
   자리에도 같은 색을 한 번 더 건다. 실기기 검증은 못 했다 — 아직 파란색이면
   알려달라고 주석에 명시.

2) BibleReadingView.swift, 두 군데:
   a) "성경-성경이동버튼들 영역 -> 아이폰 디자인을 참고." 아이패드가 지금까지
      macOS와 같은 `chapterNavigationControlsStandard`를 썼는데, 아이폰
      전용이던 `compactChapterNavigationBar`(하나로 이어진 캡슐 막대)로
      통일한다 — 그 프로퍼티는 이미 `#if os(iOS)`(아이폰+아이패드 공통)
      안에 있어 그대로 재사용 가능하다.
   b) "성경-타이틀(성경 조회) 크기를 키울것 -> 연구문서, 말씀노트 타이틀과
      동일하게." 아이패드용 "성경 조회" 타이틀이 17pt(`.headline` 배율)로
      다른 두 화면(20pt, `.title3` 배율)보다 작았다 — 그 두 화면과 정확히
      같은 크기로 맞춘다.

3) WordNoteHomeView.swift — "말씀노트-오른쪽 '항목을 선택하세요' 흰 영역 ->
   테마대로." `WordNoteSplitContent`(아이패드/맥 분할 레이아웃의 detail
   플레이스홀더)가 지금까지 테마 대상에서 완전히 빠져 있었다 — `settings`
   프로퍼티를 추가하고 배경/글자색을 다른 화면들과 같은 패턴으로 맞춘다.
"""
import pathlib

ROOT = pathlib.Path.home() / "mnt" / "JBCHBibleResearch"


def apply(path: pathlib.Path, replacements):
    src = path.read_text()
    for old, new, count in replacements:
        found = src.count(old)
        assert found == count, f"{path.name}: expected {count} occurrence(s), found {found}\n---OLD---\n{old[:300]}"
        src = src.replace(old, new)
    path.write_text(src)
    print(f"OK: {path}")


# =====================================================================
# 1) SidebarNavigationView.swift
# =====================================================================
sidebar_path = ROOT / "JBCHBibleResearch/Views/Navigation/SidebarNavigationView.swift"

old_sidebar = '''                    #endif
            }
        }
        .focusedSceneValue(\\.selectSection) { section in'''
new_sidebar = '''                    #endif
            }
        }
        // [2026-09-12 추가] 사용자 보고(아이패드) — "왼쪽 사이드바 선택된
        // 기능의 파란색 -> 테마대로." 아래 `sidebarMenuList`에 이미 있는
        // 같은 톤의 `.tint()`가 macOS에서는 선택 행 배경을 금색으로 바꾸는
        // 데 성공했지만, 아이패드에서는 여전히 시스템 기본 파란색이 보인다는
        // 보고다. `NavigationSplitView`는 사이드바 선택 강조색을 플랫폼별로
        // 다르게 해석한다(macOS는 AppKit `NSOutlineView` 브리징, 아이패드는
        // UIKit `UISplitViewController` 브리징) — 안쪽 `List`에만 건
        // `.tint()`가 두 플랫폼 모두에 항상 반영된다는 보장이 없어,
        // `NavigationSplitView` 자신을 감싸는 자리에도 같은 색을 한 번 더
        // 걸어 스플릿 뷰 자체의 색 해석 시점에도 이 값이 보이게 한다.
        // ⚠️ 이 세션엔 실기기/시뮬레이터가 없어 이 시도가 실제로 아이패드
        // 에서 해결되는지 확인하지 못했다 — 빌드 후에도 여전히 파란색이면
        // 알려달라(UIKit 브리징 특유의 알려진 제약이라 추가 조치가 더
        // 필요할 수 있다).
        .tint(Color(hex: "#D1A35E") ?? Color("AccentColor"))
        .focusedSceneValue(\\.selectSection) { section in'''
apply(sidebar_path, [(old_sidebar, new_sidebar, 1)])

# =====================================================================
# 2) BibleReadingView.swift
# =====================================================================
bible_path = ROOT / "JBCHBibleResearch/Views/Bible/BibleReadingView.swift"

# 2-a) 성경 이동 버튼 영역 — 아이패드도 아이폰과 같은 compactChapterNavigationBar
old_nav_controls = '''    @ViewBuilder
    private var chapterNavigationControls: some View {
        #if os(iOS)
        if isPhone {
            compactChapterNavigationBar
        } else {
            chapterNavigationControlsStandard
        }
        #else
        chapterNavigationControlsStandard
        #endif
    }'''
new_nav_controls = '''    @ViewBuilder
    private var chapterNavigationControls: some View {
        // [2026-09-12 수정] 사용자 요청(아이패드) — "성경-성경이동버튼들
        // 영역 -> 아이폰 디자인을 참고." 기존엔 아이패드가 macOS와 같은
        // `chapterNavigationControlsStandard`(개별 원형 버튼 + 사이 간격)를
        // 썼는데, 아이폰만 쓰던 `compactChapterNavigationBar`(하나로 이어진
        // 캡슐 막대)로 통일해 달라는 요청이다. `compactChapterNavigationBar`는
        // 이미 `#if os(iOS)`(아이폰+아이패드 공통) 안에 정의돼 있어 새로
        // 만들 것 없이 그대로 아이패드에도 적용한다. macOS는 그대로 둔다 —
        // 요청 대상이 "아이패드"로 명시됐다.
        #if os(iOS)
        compactChapterNavigationBar
        #else
        chapterNavigationControlsStandard
        #endif
    }'''
apply(bible_path, [(old_nav_controls, new_nav_controls, 1)])

# 2-b) "성경 조회" 타이틀 크기 — 연구문서/말씀노트와 동일하게
old_title = '''            } else {
                Text("성경 조회")
                    .font(.custom(SpecialPurposeFonts.titleSerif, size: 17, relativeTo: .headline))
                    .fontWeight(.semibold)
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
            }
        }
        #endif'''
new_title = '''            } else {
                // [2026-09-12 수정] 사용자 요청(아이패드) — "성경-타이틀
                // (성경 조회) 크기를 키울것 -> 연구문서, 말씀노트 타이틀과
                // 동일하게." `DocumentsHomeView`/`WordNoteHomeView`의
                // 타이틀이 쓰는 것과 정확히 같은 크기(size 20, `.title3`
                // 배율)로 맞춘다 — 기존 17pt(`.headline` 배율)는 그 두
                // 화면보다 작았다.
                Text("성경 조회")
                    .font(.custom(SpecialPurposeFonts.titleSerif, size: 20, relativeTo: .title3))
                    .fontWeight(.semibold)
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
            }
        }
        #endif'''
apply(bible_path, [(old_title, new_title, 1)])

# =====================================================================
# 3) WordNoteHomeView.swift
# =====================================================================
wordnote_path = ROOT / "JBCHBibleResearch/Views/WordNote/WordNoteHomeView.swift"

old_split = '''private struct WordNoteSplitContent: View {
    @State private var selectedItem: WordNoteItem?

    var body: some View {
        HStack(spacing: 0) {
            WordNoteListContent(isPhoneLayout: false, selectedItem: $selectedItem)
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)

            Divider()

            Group {
                if let selectedItem {
                    destinationView(for: selectedItem)
                        .id(selectedItem.id)
                } else {
                    VStack {
                        Spacer()
                        Text("항목을 선택하세요")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }'''
new_split = '''private struct WordNoteSplitContent: View {
    @State private var selectedItem: WordNoteItem?

    /// [2026-09-12 추가] 사용자 보고 — "말씀노트-오른쪽 '항목을
    /// 선택하세요' 흰 영역 -> 테마대로." 이 struct는 지금까지 테마 대상에서
    /// 완전히 빠져 있었다 — 다른 화면들과 같은 읽기 전용 접근 패턴.
    private var settings: UserSettingsStore { .shared }

    var body: some View {
        HStack(spacing: 0) {
            WordNoteListContent(isPhoneLayout: false, selectedItem: $selectedItem)
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)

            Divider()

            Group {
                if let selectedItem {
                    destinationView(for: selectedItem)
                        .id(selectedItem.id)
                } else {
                    VStack {
                        Spacer()
                        Text("항목을 선택하세요")
                            .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(settings.bibleBackgroundColor ?? Color.clear)
                }
            }
        }'''
apply(wordnote_path, [(old_split, new_split, 1)])
