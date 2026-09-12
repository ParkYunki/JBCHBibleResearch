#!/usr/bin/env python3
"""DocumentsHomeView.swift의 ChapterLinkEditorSheet(문서 길게프레스 → "관련
성경 장 설정…/변경…") 수정.
1) 사용자 보고 — "레이아웃 팝업이 컨텐츠에 비해 너무 큼." 이 시트의 실제
   내용은 BookChapterPicker의 한 줄짜리 standardBody뿐인데, macOS만
   `.frame(minWidth: 480, minHeight: 260)`으로 크기를 잡아 뒀고 iOS(아이패드
   포함)는 아무 제약이 없어 시스템 기본 시트 크기(내용보다 훨씬 큼)로 떴다 —
   `BookmarkListPopover`가 이미 쓰는 `.presentationDetents([.height(_:)])`
   패턴을 그대로 재사용해, macOS가 이미 쓰는 것과 같은 260을 시트 높이로
   고정한다.
2) 사용자 보고 — "색상테마도 적용할 수 있도록." 지금까지 테마(성경 읽기
   화면의 배경/텍스트 색) 적용 대상에서 빠져 있었다 — `settings` 프로퍼티,
   배경/글자색, `ThemedNavigationBarBackgroundModifier`(이 파일에 이미 있는
   같은 private 구조체, 같은 파일이라 재사용 가능)를 추가한다.
"""
import pathlib

ROOT = pathlib.Path.home() / "mnt" / "JBCHBibleResearch"
PATH = ROOT / "JBCHBibleResearch/Views/Documents/DocumentsHomeView.swift"


def apply(path: pathlib.Path, replacements):
    src = path.read_text()
    for old, new, count in replacements:
        found = src.count(old)
        assert found == count, f"{path.name}: expected {count} occurrence(s), found {found}\n---OLD---\n{old[:200]}"
        src = src.replace(old, new)
    path.write_text(src)
    print(f"OK: {path}")


old = '''private struct ChapterLinkEditorSheet: View {
    @Binding var book: Book
    @Binding var chapter: Int
    let onSave: () -> Void
    @Environment(\\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            // [2026-08-15 2차 UI/UX 수정] `UploadChapterLinkSheet`와 같은 이유(그
            // 파일 주석 참고) — `Form`/`Section` 행 레이아웃이 `BookChapterPicker`의
            // 검색창 placeholder를 상자 밖으로 밀어내는 문제가 있어 `Form` 자체를
            // 걷어내고 일반 `VStack`으로 바꿨다.
            VStack(alignment: .leading, spacing: 16) {
                BookChapterPicker(
                    books: BooksProvider.shared.books,
                    selectedBook: book,
                    selectedChapter: chapter
                ) { newBook, newChapter in
                    book = newBook
                    chapter = newChapter
                }
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("관련 성경 장")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        onSave()
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 260)
        #endif
    }
}'''

new = '''private struct ChapterLinkEditorSheet: View {
    @Binding var book: Book
    @Binding var chapter: Int
    let onSave: () -> Void
    @Environment(\\.dismiss) private var dismiss
    /// [2026-09-11 신설] 사용자 보고 — "색상테마도 적용할 수 있도록." 이
    /// 시트는 지금까지 테마 적용 대상에서 빠져 있었다 — 다른 화면들과 같은
    /// 읽기 전용 접근 패턴.
    private var settings: UserSettingsStore { .shared }

    var body: some View {
        NavigationStack {
            // [2026-08-15 2차 UI/UX 수정] `UploadChapterLinkSheet`와 같은 이유(그
            // 파일 주석 참고) — `Form`/`Section` 행 레이아웃이 `BookChapterPicker`의
            // 검색창 placeholder를 상자 밖으로 밀어내는 문제가 있어 `Form` 자체를
            // 걷어내고 일반 `VStack`으로 바꿨다.
            VStack(alignment: .leading, spacing: 16) {
                BookChapterPicker(
                    books: BooksProvider.shared.books,
                    selectedBook: book,
                    selectedChapter: chapter
                ) { newBook, newChapter in
                    book = newBook
                    chapter = newChapter
                }
                Spacer(minLength: 0)
            }
            .padding()
            // [2026-09-11 신설] 위 `settings` 선언부 주석 참고 — `BookChapterPicker`
            // 의 "책 N장" 라벨은 자체 글자색이 없어(다른 화면들에서 이미
            // 반복된 것과 같은 이유 — 상속에만 기대는 `Text`/`Label`) 이
            // 배경색을 물려받는다("이동" 원형 버튼 안 흰 화살표처럼 이미
            // 자기 색을 정한 요소는 그대로 남는다 — 명시적 색이 항상
            // 상속보다 우선한다).
            .foregroundStyle(settings.bibleTextColor ?? Color.primary)
            .background(settings.bibleBackgroundColor ?? Color.clear)
            .navigationTitle("관련 성경 장")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        onSave()
                        dismiss()
                    }
                }
            }
            // [2026-09-11 신설] `DocumentsHomeView.body`가 자기 화면에 쓰는
            // 것과 같은 모디파이어(같은 파일이라 재사용 가능) — 실제
            // 시스템 내비게이션 바 배경까지 테마에 맞춘다(위 `.background()`
            // 는 그 아래 콘텐츠 영역만 칠한다).
            .modifier(ThemedNavigationBarBackgroundModifier(color: settings.bibleBackgroundColor))
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 260)
        #endif
        #if os(iOS)
        // [2026-09-11 신설] 사용자 보고 — "레이아웃 팝업이 컨텐츠에 비해
        // 너무 큼." 원인 — 이 시트의 실제 내용은 `BookChapterPicker`의
        // 한 줄짜리 `standardBody`(책/장 버튼 + 검색창 + 이동 버튼)뿐인데
        // (탭하면 열리는 책/장 그리드는 이 시트가 아니라 `BookChapterPicker`
        // 자신의 별도 `.popover`이고, 그쪽은 이미 `.frame(minWidth: 360,
        // minHeight: 460)`으로 스스로 크기를 잡는다), 지금까지 iOS 쪽엔
        // 위 macOS `.frame(minHeight: 260)`과 같은 제약이 전혀 없어 시스템
        // 기본 시트 크기(내용보다 훨씬 큼)로 떴다 — `BookmarkListPopover`가
        // 이미 쓰는 `.presentationDetents([.height(_:)])` 패턴을 그대로
        // 재사용해, macOS가 이미 쓰는 것과 같은 260을 시트 높이로 고정한다
        // (같은 콘텐츠라 새 값을 추측하지 않고 그대로 재사용했다).
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
        #endif
    }
}'''

apply(PATH, [(old, new, 1)])
