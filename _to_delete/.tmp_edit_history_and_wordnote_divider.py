#!/usr/bin/env python3
"""두 파일 수정.

1) BibleReadingHistorySheet.swift — 사용자 요청 "성경-히스토리 디자인도
   테마에 맞도록 수정할것." 이 파일은 이미 대부분 테마가 적용돼 있었다
   (`settings`, `.background(bibleBackgroundColor)`, `.scrollContentBackground
   (.hidden)`, 텍스트 색 전부 이미 반영됨) — 그런데 `OutlineTreeView`/
   `WordNoteHomeView`에서 이미 실기기로 확인된 것과 같은 누락이 하나 남아
   있었다: `row(for:)`(각 조회 이력 행)에 `.listRowBackground(Color.clear)`가
   없어서, List 컨테이너 배경(`.background()`)은 테마색인데 각 행 셀 자체는
   여전히 시스템 기본(흰/검) 배경이었다 — 이게 "디자인이 테마를 안 따른다"는
   이번 보고의 실제 원인으로 보인다.

2) WordNoteHomeView.swift — 사용자 요청 "말씀노트 화면에서 캡슐 탭 밑에
   컨텐츠가 시작되는 부분에 연구문서와 통합검색에 사용된 이미지 구분선을
   사용할 것." `SearchView.menuContentOrnamentalDivider`(통합검색, 원본) /
   `DocumentsHomeView.searchContentOrnamentalDivider`(연구문서, 그 시각
   언어를 옮겨온 버전 — 두 화면 다 "가로선-sparkle-가로선, wood 톤"으로
   동일)와 같은 시각 언어를 이 화면에도 옮겨온다. 이 자리(카테고리 캡슐
   행과 `List` 사이)는 `DocumentsHomeView`의 자리(검색바와 목록 사이, 역시
   List 밖 평범한 VStack)와 구조가 같아 그 버전(`.listRowSeparator`/
   `.listRowBackground` 없는 평범한 VStack용)을 그대로 따른다 — `SearchView`
   버전은 List 행 전용이라 여기엔 맞지 않는다. 두 프로퍼티 다 각 파일에
   private이라 직접 참조 재사용은 안 되고(DocumentsHomeView 자신의 주석에도
   이미 있는 설명), 그래서 새로 옮겨 적는다.
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
# 1) BibleReadingHistorySheet.swift
# =====================================================================
history_path = ROOT / "JBCHBibleResearch/Views/Bible/BibleReadingHistorySheet.swift"

old_row = '''            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }'''
new_row = '''            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // [2026-09-12 추가] 사용자 재보고 — "성경-히스토리 디자인도 테마에
        // 맞도록 수정할것." `OutlineTreeView`/`WordNoteHomeView`가 이미
        // 겪은 것과 같은 누락 — 위 `body`의 `.background(bibleBackgroundColor)`
        // 는 List "컨테이너"의 배경만 바꾸지, 각 행 셀 자체의 배경까지
        // 자동으로 투명하게 만들어주지는 않는다.
        .listRowBackground(Color.clear)
    }'''

apply(history_path, [(old_row, new_row, 1)])

# =====================================================================
# 2) WordNoteHomeView.swift
# =====================================================================
wordnote_path = ROOT / "JBCHBibleResearch/Views/WordNote/WordNoteHomeView.swift"

old_before_body = '''        .buttonStyle(.plain)
    }

    var body: some View {
        VStack(spacing: 0) {'''
new_before_body = '''        .buttonStyle(.plain)
    }

    /// [2026-09-12 신설] 사용자 요청 — "말씀노트 화면에서 캡슐 탭 밑에
    /// 컨텐츠가 시작되는 부분에 연구문서와 통합검색에 사용된 이미지
    /// 구분선을 사용할 것." `SearchView.menuContentOrnamentalDivider`(통합
    /// 검색, 원본)/`DocumentsHomeView.searchContentOrnamentalDivider`(연구
    /// 문서, 같은 시각 언어를 옮겨온 버전)와 완전히 같은 모양(가로선-
    /// `sparkle`-가로선, wood 톤) — 두 프로퍼티 다 각자 파일에 private이라
    /// 직접 재사용은 못 하고 그대로 옮겨 적는다. 이 자리는 `DocumentsHomeView`
    /// 쪽(List 밖 평범한 VStack 안)과 구조가 같아 `.listRowSeparator`/
    /// `.listRowBackground`가 없는 그 버전을 따른다.
    private var wordNoteContentOrnamentalDivider: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(JBCHCategoryPalette.wood.opacity(0.3))
                .frame(height: 1)
            Image(systemName: "sparkle")
                .font(.system(size: 11))
                .foregroundStyle(settings.bibleTextColor?.opacity(0.45) ?? Color.secondary)
            Rectangle()
                .fill(JBCHCategoryPalette.wood.opacity(0.3))
                .frame(height: 1)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    var body: some View {
        VStack(spacing: 0) {'''

old_insert_point = '''            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)

            List {
                ForEach(filteredItems) { item in
                    rowContent(for: item)
                }
                .onDelete { offsets in
                    guard isPhoneLayout else { return }'''
new_insert_point = '''            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)

            // [2026-09-12 추가] 위 `wordNoteContentOrnamentalDivider` 선언부
            // 주석 참고 — 캡슐 탭과 목록(컨텐츠) 사이 경계.
            wordNoteContentOrnamentalDivider

            List {
                ForEach(filteredItems) { item in
                    rowContent(for: item)
                }
                .onDelete { offsets in
                    guard isPhoneLayout else { return }'''

apply(wordnote_path, [
    (old_before_body, new_before_body, 1),
    (old_insert_point, new_insert_point, 1),
])
