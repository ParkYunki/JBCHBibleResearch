#!/usr/bin/env python3
"""OriginalTextInfoView.swift — 사용자 요청: "성경-원문정보의 성경구절, 원어카드의
디자인도 기존 지정색을 버리고 테마에 따라 색상을 수정할것."

대상은 이 파일의 `cardBackground`/`cardBorderColor`(상단 KRV 구절 카드와
`wordCard`가 공유) 및 `hebrewTextColor`(원어 단어 강조색) 세 프로퍼티 —
전부 플랫폼/colorScheme 기준의 고정값이었지 `settings.bibleTextColor`/
`bibleBackgroundColor`(성경 읽기 테마)를 전혀 참조하지 않았다.

- cardBackground/cardBorderColor: `DocumentsHomeView.swift`(약 900번째 줄)가
  이미 쓰는 관례 — 테마 글자색의 옅은 opacity(카드 채움 0.08 / 테두리 0.2)로
  "카드"를 테마 배경 위에서 살짝 띄운다. 테마 미지정 시엔 같은 opacity의
  `Color.secondary`로 대체(TranslationPickerPopover 칩과 동일 관례) — 기존
  플랫폼 시스템색과는 다르지만, 이 값들 자체가 "테마 미지정" 상태에서
  일반적으로 쓰이는 이 코드베이스의 표준 대체값이다.
- hebrewTextColor: 테마 글자색이 있으면 그대로 쓴다(원어 단어는 이미 전용
  서체 `originalTextFont`/26pt로 헤드라인과 충분히 구분됨). 테마 미지정
  시에는 기존 라이트/다크 대응 남색(2026-08-19 수정본)을 그대로 유지해
  기존 동작을 보존한다.

`cardBorderColor`/`cardBackground`가 `Color(uiColor:)`/`Color(nsColor:)`를
쓰던 유일한 자리였으므로(파일 전체 grep 확인 — UIDevice/UIColor/NSColor 등
다른 사용처 없음), 이제 쓸모없어진 `import UIKit`/`import AppKit`도 같이
정리한다.
"""
import pathlib

PATH = pathlib.Path.home() / "mnt" / "JBCHBibleResearch" / "JBCHBibleResearch/Views/Bible/OriginalTextInfoView.swift"


def apply(path, replacements):
    src = path.read_text()
    for old, new, count in replacements:
        found = src.count(old)
        assert found == count, f"expected {count} occurrence(s), found {found}\n---OLD---\n{old[:200]}"
        src = src.replace(old, new)
    path.write_text(src)
    print("OK:", path)


edits = []

# --- 1) 이제 안 쓰는 UIKit/AppKit import 제거 (uiColor:/nsColor: 제거로 유일한 사용처 사라짐) ---
old_imports = '''#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct OriginalTextInfoView: View {'''
new_imports = '''struct OriginalTextInfoView: View {'''
edits.append((old_imports, new_imports, 1))

# --- 2) hebrewTextColor: 테마 글자색 우선, 미지정 시 기존 라이트/다크 남색 유지 ---
old_hebrew = '''    /// 스크린샷의 원어 텍스트 파란색(iOS 기본 System Blue보다 살짝 진하고
    /// 채도 높은 남색 계열)에 맞춘 커스텀 색. [2026-08-19 수정] 사용자 보고 —
    /// "야간에는 배경이 검은색이어서 눈에 잘 안보임." 이 진한 남색은 흰 배경
    /// 기준으로 고른 값이라 다크모드 검은 배경에서는 대비가 부족했다 — 다크
    /// 모드에서는 더 밝고 채도 낮은 블루를 대신 쓴다.
    private var hebrewTextColor: Color {
        colorScheme == .dark
            ? Color(red: 0.55, green: 0.7, blue: 1.0)
            : Color(red: 0.09, green: 0.25, blue: 0.78)
    }'''
new_hebrew = '''    /// [2026-09-12 수정] 사용자 요청 — "원어카드의 디자인도 기존 지정색을
    /// 버리고 테마에 따라 색상을 수정할것." 테마 글자색(`settings.
    /// bibleTextColor`)이 지정돼 있으면 그 색을 그대로 쓴다 — 원어 단어는
    /// 이미 전용 서체(`originalTextFont`, 26pt, 히브리어/그리스어 전용
    /// 폰트)로 바로 위 한글 뜻 헤드라인과 충분히 구분되므로 별도 강조색이
    /// 없어도 된다. 테마 미지정 시엔 기존 라이트/다크 대응 남색(2026-08-19
    /// 수정본, 아래 두 줄)을 그대로 유지한다 — 테마를 켜지 않은 기존
    /// 사용자의 화면은 바뀌지 않도록.
    private var hebrewTextColor: Color {
        if let themeColor = settings.bibleTextColor {
            return themeColor
        }
        return colorScheme == .dark
            ? Color(red: 0.55, green: 0.7, blue: 1.0)
            : Color(red: 0.09, green: 0.25, blue: 0.78)
    }'''
edits.append((old_hebrew, new_hebrew, 1))

# --- 3) cardBorderColor: 플랫폼 구분선 고정색 → 테마 글자색 옅은 opacity ---
old_border = '''    private var cardBorderColor: Color {
        #if os(iOS)
        Color(uiColor: .separator)
        #else
        Color(nsColor: .separatorColor)
        #endif
    }'''
new_border = '''    /// [2026-09-12 수정] 사용자 요청 — "성경구절, 원어카드의 디자인도 기존
    /// 지정색을 버리고 테마에 따라 색상을 수정할것." 기존엔 플랫폼 구분선
    /// 고정색(`.separator`/`.separatorColor`)이라 테마 배경(특히 어두운
    /// 커스텀 배경) 위에서 대비가 어색했다 — `DocumentsHomeView.swift`의
    /// 카드 테두리가 이미 쓰는 것과 같은 관례(테마 글자색의 옅은 opacity)로
    /// 바꾼다. 테마 미지정 시엔 `TranslationPickerPopover`의 칩 테두리와
    /// 같은 대체값(`Color.secondary` 계열)을 쓴다.
    private var cardBorderColor: Color {
        settings.bibleTextColor?.opacity(0.2) ?? Color.secondary.opacity(0.2)
    }'''
edits.append((old_border, new_border, 1))

# --- 4) cardBackground: 플랫폼 그룹 배경 고정색 → 테마 글자색 아주 옅은 opacity ---
old_bg = '''    private var cardBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }'''
new_bg = '''    /// [2026-09-12 수정] 사용자 요청 — 위 `cardBorderColor` 주석 참고.
    /// 기존엔 플랫폼 그룹 배경 고정색이라 테마 배경과 잘 어울리지 않았다 —
    /// `DocumentsHomeView.swift`(약 900번째 줄)가 이미 쓰는 것과 같은 관례
    /// (테마 글자색의 아주 옅은 opacity로 "카드"를 배경에서 살짝 띄운다).
    private var cardBackground: Color {
        settings.bibleTextColor?.opacity(0.08) ?? Color.secondary.opacity(0.08)
    }'''
edits.append((old_bg, new_bg, 1))

apply(PATH, edits)
