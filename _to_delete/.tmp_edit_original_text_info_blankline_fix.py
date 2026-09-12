#!/usr/bin/env python3
"""OriginalTextInfoView.swift — 방금 UIKit/AppKit import 제거 편집에서 import
블록과 struct 선언 사이 빈 줄이 같이 없어졌다(코드 동작엔 영향 없으나 스타일
정리). 원래 있던 빈 줄만 되돌린다."""
import pathlib

PATH = pathlib.Path.home() / "mnt" / "JBCHBibleResearch" / "JBCHBibleResearch/Views/Bible/OriginalTextInfoView.swift"

old = '''import BibleResearchModels
struct OriginalTextInfoView: View {'''
new = '''import BibleResearchModels

struct OriginalTextInfoView: View {'''

src = PATH.read_text()
count = src.count(old)
assert count == 1, f"expected 1 occurrence, found {count}"
src = src.replace(old, new)
PATH.write_text(src)
print("OK:", PATH)
