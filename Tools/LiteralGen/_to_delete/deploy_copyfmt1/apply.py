#!/usr/bin/env python3
"""i18nbatch2: Localizable.xcstrings 번역 일괄 처리(1차 i18nbatch1/apply.py 확장).

사용법:
  python3 -I apply.py <Localizable.xcstrings> fill    [translations.json]
  python3 -I apply.py <Localizable.xcstrings> replace [translations.json]
  (뒤에 --dry-run을 붙이면 검사만 하고 쓰지 않는다)

translations.json 형식(기본값: 이 스크립트 옆의 translations.json):
  {"fill": {키: {언어: 값}},
   "replace": [{"key": 키, "lang": 언어, "old": 현재 값, "new": 새 값, ...}]}

fill 모드 (1차와 같은 규칙)
- 파일에 없는 키는 건너뛰고 알린다. 새 키를 만들지 않는다.
- 이미 stringUnit/variations가 있는 언어는 덮어쓰지 않는다.
- 새 항목 state는 기존 번역(비 ko) 항목과 같은 "needs_review".

replace 모드 (이번에 추가)
- "replace" 목록에 적힌 (키, 언어)만 바꾼다. 목록 밖은 건드리지 않는다.
- 키·언어가 없거나, stringUnit이 아니거나(variations 등), 현재 값이 old와 다르면 전체를 중단하고 아무것도 쓰지 않는다.
  (다른 작업이 그 값을 먼저 바꾼 경우를 덮어쓰지 않기 위함)
- 현재 값이 이미 new면 "이미 반영됨"으로 세고 넘어간다(다시 실행해도 안전).
- 바꾸는 것은 stringUnit.value 하나뿐이다. state 등 다른 필드는 그대로 둔다.
- 같은 (키, 언어)가 목록에 두 번 있으면 중단한다.

공통
- 모든 새 값은 키의 포맷 지정자(%@, %lld …)와 종류·순번이 같아야 한다. 하나라도 다르면 중단한다.
- 출력은 Xcode 형식(" : " 구분자, 2칸 들여쓰기, 빈 객체는 "{\n\n<indent>}", 파일 끝 개행 없음).
- 쓰기 전에 원본을 그대로 다시 직렬화해 바이트 단위로 같은지 확인하고, 다르면 아무것도 쓰지 않는다.
- 쓰기는 같은 폴더의 임시 파일에 쓴 뒤 os.replace로 바꾼다(원본 권한 유지).
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


def do_fill(strings, fill):
    added, skipped_keys, kept, errors = 0, [], 0, []
    for key, langs in fill.items():
        if key not in strings:
            skipped_keys.append(key)
            continue
        src = specs(key)
        for lang, value in langs.items():
            if specs(value) != src:
                errors.append("%r [%s]: 지정자 불일치 %s vs %s" % (key, lang, specs(value), src))
    if errors:
        return None, errors
    for key, langs in fill.items():
        if key not in strings:
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
    msgs = ["추가 %d개, 기존 값 유지(덮어쓰지 않음) %d개" % (added, kept)]
    msgs += ["건너뜀: 파일에 키가 없습니다 -> %r" % k for k in skipped_keys]
    return (added, msgs), []


def do_replace(strings, items):
    errors, seen, plan, already = [], set(), [], 0
    for n, it in enumerate(items):
        try:
            key, lang, old, new = it["key"], it["lang"], it["old"], it["new"]
        except (KeyError, TypeError):
            errors.append("항목 %d: key/lang/old/new가 모두 있어야 합니다" % n)
            continue
        if (key, lang) in seen:
            errors.append("%r [%s]: 목록에 중복" % (key, lang))
            continue
        seen.add((key, lang))
        if specs(new) != specs(key):
            errors.append("%r [%s]: 지정자 불일치 %s vs %s" % (key, lang, specs(new), specs(key)))
            continue
        entry = strings.get(key)
        if entry is None:
            errors.append("%r: 파일에 키가 없습니다" % key)
            continue
        loc = entry.get("localizations", {}).get(lang)
        if loc is None:
            errors.append("%r [%s]: 그 언어 값이 없습니다(교체 대상 아님 — fill로 넣으세요)" % (key, lang))
            continue
        if set(loc) != {"stringUnit"} or not isinstance(loc["stringUnit"].get("value"), str):
            errors.append("%r [%s]: stringUnit 단일 값이 아닙니다(variations 등) — 손대지 않습니다" % (key, lang))
            continue
        cur = loc["stringUnit"]["value"]
        if cur == new:
            already += 1
            continue
        if cur != old:
            errors.append("%r [%s]: 현재 값이 old와 다릅니다\n      현재: %r\n      old : %r" % (key, lang, cur, old))
            continue
        plan.append((loc["stringUnit"], new))
    if errors:
        return None, errors
    for unit, new in plan:
        unit["value"] = new
    return (len(plan), ["교체 %d개, 이미 반영됨 %d개" % (len(plan), already)]), []


def main():
    args = [a for a in sys.argv[1:] if a != "--dry-run"]
    dry = "--dry-run" in sys.argv[1:]
    if len(args) not in (2, 3) or args[1] not in ("fill", "replace"):
        print(__doc__)
        return 2
    path, mode = args[0], args[1]
    tpath = args[2] if len(args) == 3 else os.path.join(
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
    if mode == "fill":
        result, errors = do_fill(strings, trans.get("fill", {}))
    else:
        result, errors = do_replace(strings, trans.get("replace", []))
    if errors:
        print("ERROR: 검사 실패, 아무것도 쓰지 않았습니다.", file=sys.stderr)
        for e in errors:
            print("  " + e, file=sys.stderr)
        return 1
    changed, msgs = result

    text = serialize(doc)
    json.loads(text)  # 유효성 확인
    if dry or changed == 0:
        for m in msgs:
            print(m)
        print("(쓰지 않음: %s)" % ("--dry-run" if dry else "바뀐 값 없음"))
        return 0
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

    for m in msgs:
        print(m)
    return 0


if __name__ == "__main__":
    sys.exit(main())
