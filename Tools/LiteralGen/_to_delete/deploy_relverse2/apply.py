#!/usr/bin/env python3
"""i18nbatch1: Localizable.xcstrings에 누락 번역을 넣는다.

사용법: python3 -I apply.py <Localizable.xcstrings> [translations.json]

- translations.json 형식: {키: {언어: 값}} (기본값: 이 스크립트 옆의 translations.json)
- 파일에 없는 키(예: 아직 반영 전인 '메인 창으로')는 건너뛰고 알린다. 새 키를 만들지 않는다.
- 이미 stringUnit/variations가 있는 언어는 덮어쓰지 않는다.
- 새 항목 state는 기존 번역(비 ko) 항목과 같은 "needs_review".
- 출력은 Xcode 형식(" : " 구분자, 2칸 들여쓰기, 빈 객체는 "{\n\n<indent>}")으로 쓴다.
  기존 키 순서는 그대로 두고, localizations 안의 언어 키만 정렬한다(기존 파일 규칙과 동일).
- 쓰기 전에 원본을 그대로 다시 직렬화해 바이트 단위로 같은지 확인하고, 다르면 아무것도 쓰지 않는다.
"""
import json
import os
import re
import sys
import tempfile

STATE = "needs_review"
SPEC_RE = re.compile(r"%(?:(\d+)\$)?(@|lld|ld|d|f|s)")


def _escape(s):
    out = []
    for ch in s:
        if ch == '"':
            out.append('\\"')
        elif ch == "\\":
            out.append("\\\\")
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif ord(ch) < 0x20:
            out.append("\\u%04x" % ord(ch))
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def _dump(obj, level, out):
    ind = "  " * level
    if isinstance(obj, dict):
        if not obj:
            out.append("{\n\n" + ind + "}")
            return
        out.append("{\n")
        items = list(obj.items())
        for i, (k, v) in enumerate(items):
            out.append(ind + "  " + _escape(k) + " : ")
            _dump(v, level + 1, out)
            out.append(",\n" if i < len(items) - 1 else "\n")
        out.append(ind + "}")
    elif isinstance(obj, list):
        if not obj:
            out.append("[\n\n" + ind + "]")
            return
        out.append("[\n")
        for i, v in enumerate(obj):
            out.append(ind + "  ")
            _dump(v, level + 1, out)
            out.append(",\n" if i < len(obj) - 1 else "\n")
        out.append(ind + "]")
    elif isinstance(obj, bool):
        out.append("true" if obj else "false")
    elif obj is None:
        out.append("null")
    elif isinstance(obj, str):
        out.append(_escape(obj))
    else:
        out.append(json.dumps(obj))


def serialize(doc):
    out = []
    _dump(doc, 0, out)
    return "".join(out)  # Xcode는 파일 끝 개행을 쓰지 않는다


def specs(s):
    """포맷 지정자를 (순번, 종류) 목록으로. 위치 지정이 있으면 그 번호, 없으면 등장 순서."""
    s = s.replace("%%", "")
    res = []
    for i, m in enumerate(SPEC_RE.finditer(s), 1):
        res.append((int(m.group(1)) if m.group(1) else i, m.group(2)))
    return sorted(res)


def main():
    if len(sys.argv) not in (2, 3):
        print(__doc__)
        return 2
    path = sys.argv[1]
    tpath = sys.argv[2] if len(sys.argv) == 3 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "translations.json")

    with open(path, encoding="utf-8") as f:
        raw = f.read()
    doc = json.loads(raw)
    with open(tpath, encoding="utf-8") as f:
        trans = json.load(f)

    if serialize(doc) != raw:
        print("ERROR: 원본 재직렬화 결과가 원본과 다릅니다. 서식 규칙이 맞지 않아 중단합니다.", file=sys.stderr)
        return 1

    strings = doc["strings"]
    added, skipped_keys, kept, errors = 0, [], 0, []
    for key, langs in trans.items():
        if key not in strings:
            skipped_keys.append(key)
            continue
        src = specs(key)
        for lang, value in langs.items():
            if specs(value) != src:
                errors.append("%r [%s]: 지정자 불일치 %s vs %s" % (key, lang, specs(value), src))
        if errors:
            continue
        entry = strings[key]
        locs = dict(entry.get("localizations", {}))
        for lang, value in langs.items():
            if lang in locs:
                kept += 1
                continue
            locs[lang] = {"stringUnit": {"state": STATE, "value": value}}
            added += 1
        entry["localizations"] = {k: locs[k] for k in sorted(locs)}
        strings[key] = {k: entry[k] for k in sorted(entry)}

    if errors:
        print("ERROR: 포맷 지정자 검사 실패, 아무것도 쓰지 않았습니다.", file=sys.stderr)
        for e in errors:
            print("  " + e, file=sys.stderr)
        return 1

    text = serialize(doc)
    json.loads(text)  # 유효성 확인
    d = os.path.dirname(os.path.abspath(path))
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".xcstrings.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.chmod(tmp, os.stat(path).st_mode & 0o7777)  # 원본 권한 유지(mkstemp 기본 0600 방지)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise

    print("추가 %d개, 기존 값 유지(덮어쓰지 않음) %d개" % (added, kept))
    for k in skipped_keys:
        print("건너뜀: 파일에 키가 없습니다 -> %r" % k)
    return 0


if __name__ == "__main__":
    sys.exit(main())
