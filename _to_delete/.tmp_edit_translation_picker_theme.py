#!/usr/bin/env python3
"""TranslationPickerPopover.swift — 사용자 보고 "배경색이 왜 검은색 고정이지?"
원인: 이 팝오버는 지난 수정(적용 버튼 색상)에서도 정작 팝오버 전체의
배경/글자색 자체는 테마 대상에서 빠져 있었다 — 시스템 기본 배경만 썼고,
시스템이 다크 모드(또는 사용자가 "화면모드"를 다크로 설정)일 때 그 기본
배경이 거의 검게 보인 것이다. `BookmarkListPopover.swift`(이미 같은 문제를
겪고 고친 같은 파일 계열의 팝오버)가 쓰는 것과 완전히 같은 패턴 —
`.background(settings.bibleBackgroundColor ?? Color.clear)` + 개별 텍스트/
아이콘마다 `settings.bibleTextColor`(짙기는 opacity로 구분) — 을 그대로
옮겨 온다. 상태를 나타내는 색(주황 경고 문구, 선택 강조에 쓰는
`Color("AccentColor")`)은 의미가 있는 색이라 손대지 않는다(다른 화면들의
같은 원칙 — 상태/강조 신호는 테마와 무관하게 유지).
"""
import pathlib

PATH = pathlib.Path.home() / "mnt" / "JBCHBibleResearch" / "JBCHBibleResearch/Views/Bible/TranslationPickerPopover.swift"


def apply(path, replacements):
    src = path.read_text()
    for old, new, count in replacements:
        found = src.count(old)
        assert found == count, f"expected {count} occurrence(s), found {found}\n---OLD---\n{old[:200]}"
        src = src.replace(old, new)
    path.write_text(src)
    print("OK:", path)


edits = []

# --- 1) body: 팝오버 전체 배경 ---
old_1 = '''        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            translationList
                .padding(12)
            Divider()
            footer
        }
        // [2026-09-05 수정] 사용자 보고(맥OS) — "팝업의 좌우 폭을 조금더
        // 늘릴것." 300은 번역본 이름이 조금만 길어도 빠듯했다 — 여유 있게
        // 늘린다. [2026-09-11 주석 갱신] 이 폭을 정한 근거였던 "칩 2열" 배치
        // 자체가 세로 한 줄 레이아웃(`translationList`)으로 바뀌면서 없어졌지만,
        // 340이라는 폭 자체는 세로 한 줄 행에도 여전히 적당해 값은 그대로
        // 뒀다(번역본 이름 + 순서 배지가 한 행에 여유 있게 들어간다).
        .frame(width: 340)
    }'''
new_1 = '''        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            translationList
                .padding(12)
            Divider()
            footer
        }
        // [2026-09-11 신설] 사용자 보고 — "배경색이 왜 검은색 고정이지?"
        // 이 팝오버는 지금까지 배경 자체가 테마 대상에서 빠져 있었다 —
        // 시스템 기본 배경만 써서, 다크 모드(또는 사용자가 앱 "화면모드"를
        // 다크로 설정)일 때 그 기본 배경이 거의 검게 보인 것이다.
        // `BookmarkListPopover.swift`가 이미 쓰는 것과 같은 패턴.
        .background(settings.bibleBackgroundColor ?? Color.clear)
        // [2026-09-05 수정] 사용자 보고(맥OS) — "팝업의 좌우 폭을 조금더
        // 늘릴것." 300은 번역본 이름이 조금만 길어도 빠듯했다 — 여유 있게
        // 늘린다. [2026-09-11 주석 갱신] 이 폭을 정한 근거였던 "칩 2열" 배치
        // 자체가 세로 한 줄 레이아웃(`translationList`)으로 바뀌면서 없어졌지만,
        // 340이라는 폭 자체는 세로 한 줄 행에도 여전히 적당해 값은 그대로
        // 뒀다(번역본 이름 + 순서 배지가 한 행에 여유 있게 들어간다).
        .frame(width: 340)
    }'''
edits.append((old_1, new_1, 1))

# --- 2) header: 타이틀/닫기 아이콘 ---
old_2 = '''    private var header: some View {
        HStack {
            Text("표시할 번역본")
                .font(.headline)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("닫기")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }'''
new_2 = '''    private var header: some View {
        HStack {
            // [2026-09-11 신설] 위 `body`의 `.background()` 주석 참고 — 이
            // 타이틀은 자체 글자색이 없어(다른 화면들에서 이미 반복된 것과
            // 같은 이유) 시스템 기본값(다크 배경 위 흰색처럼 보임)이 그대로
            // 드러났었다.
            Text("표시할 번역본")
                .font(.headline)
                .foregroundStyle(settings.bibleTextColor ?? .primary)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("닫기")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }'''
edits.append((old_2, new_2, 1))

# --- 3) footer: 카운터 텍스트 ---
old_3 = '''                Text("\\(selectedIDs.count) / \\(maxSelection) 선택됨")
                    .font(.caption)
                    .foregroundStyle(.secondary)'''
new_3 = '''                Text("\\(selectedIDs.count) / \\(maxSelection) 선택됨")
                    .font(.caption)
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)'''
edits.append((old_3, new_3, 1))

# --- 4) chip: 미선택 상태 글자색/배경/테두리 ---
old_4 = '''                Text(registry.displayName)
                    .font(isSelected ? .body.weight(.semibold) : .body)
                    .foregroundStyle(isSelected ? Color("AccentColor") : Color.primary)
                    .lineLimit(1)'''
new_4 = '''                Text(registry.displayName)
                    .font(isSelected ? .body.weight(.semibold) : .body)
                    .foregroundStyle(isSelected ? Color("AccentColor") : (settings.bibleTextColor ?? Color.primary))
                    .lineLimit(1)'''
edits.append((old_4, new_4, 1))

old_5 = '''            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color("AccentColor").opacity(0.15) : Color.secondary.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color("AccentColor").opacity(0.5) : Color.secondary.opacity(0.35), lineWidth: 1)
            )'''
new_5 = '''            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color("AccentColor").opacity(0.15) : (settings.bibleTextColor?.opacity(0.08) ?? Color.secondary.opacity(0.1)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color("AccentColor").opacity(0.5) : (settings.bibleTextColor?.opacity(0.3) ?? Color.secondary.opacity(0.35)), lineWidth: 1)
            )'''
edits.append((old_5, new_5, 1))

apply(PATH, edits)
