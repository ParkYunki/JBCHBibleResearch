#!/usr/bin/env python3
"""TranslationPickerPopover.swift — body의 `.frame(width: 340)` 주석이
방금 없앤 8자 절단(`truncatedChipLabel`)을 여전히 언급하고 있어(스크린샷
리뷰 중 발견) 최신 상태로 고친다. 코드 자체(.frame(width: 340))는 바꾸지
않는다 — 세로 한 줄 레이아웃에서도 팝오버 폭 자체는 그대로 340이 적당하다.
"""
import pathlib

PATH = pathlib.Path.home() / "mnt" / "JBCHBibleResearch" / "JBCHBibleResearch/Views/Bible/TranslationPickerPopover.swift"

old = '''        // [2026-09-05 수정] 사용자 보고(맥OS) — "팝업의 좌우 폭을 조금더
        // 늘릴것." 아래 `chip(for:)`가 이제 표시 이름을 8자로 잘라 보여주긴
        // 하지만("최대 8자 + …"), 그 8자 자체도 이전 폭(300)에서는 칩 2열이
        // 빠듯했다 — 여유 있게 늘린다.
        .frame(width: 340)'''
new = '''        // [2026-09-05 수정] 사용자 보고(맥OS) — "팝업의 좌우 폭을 조금더
        // 늘릴것." 300은 번역본 이름이 조금만 길어도 빠듯했다 — 여유 있게
        // 늘린다. [2026-09-11 주석 갱신] 이 폭을 정한 근거였던 "칩 2열" 배치
        // 자체가 세로 한 줄 레이아웃(`translationList`)으로 바뀌면서 없어졌지만,
        // 340이라는 폭 자체는 세로 한 줄 행에도 여전히 적당해 값은 그대로
        // 뒀다(번역본 이름 + 순서 배지가 한 행에 여유 있게 들어간다).
        .frame(width: 340)'''

src = PATH.read_text()
count = src.count(old)
assert count == 1, f"expected 1 occurrence, found {count}"
src = src.replace(old, new)
PATH.write_text(src)
print("OK:", PATH)
