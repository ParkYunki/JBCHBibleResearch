#!/usr/bin/env python3
"""
apply_person_edit.py

[2026-09-16 신설] PersonSeedEditor(Tools/PersonSeedEditor, 별도 macOS 앱)가
PersonSeed.json을 안전하게 수정하기 위해 호출하는 헬퍼 스크립트. 이 세션이
사람 요청으로 PersonSeed.json을 여러 차례 고칠 때 계속 써 온 것과 정확히
같은 패턴(json.load -> 메모리에서 수정 -> json.dump(ensure_ascii=False,
indent=2))을 그대로 재사용한다 — Swift 쪽(JSONEncoder)이 파일 포맷팅을
직접 책임지지 않고, 이미 검증된 이 파이썬 경로로만 실제 디스크 쓰기가
일어나게 해서 위험을 줄였다(Swift는 UI + "무엇을 바꿀지"만 담당).

세 가지 하위 명령:
  next-idx                 - 현재 가장 큰 숫자 idx + 1을 알려준다(신규 추가용).
  upsert [--allow-new]     - stdin으로 받은 person dict 하나를 idx가 같은
                              기존 항목과 통째로 교체한다. idx가 없으면(신규)
                              --allow-new가 있을 때만 배열 맨 끝에 추가한다.
  delete --idx <idx>       - idx가 정확히 하나만 일치할 때만 그 항목을 삭제한다
                              (0건/2건 이상이면 안전을 위해 아무것도 지우지
                              않고 오류로 알린다).

모든 명령은 stdout에 JSON 한 줄(`{"ok": true/false, ...}`)만 출력한다 —
Swift 쪽이 파싱하기 쉽게 로그성 print를 섞지 않는다.
"""
import argparse
import io
import json
import sys


def load(path):
    with io.open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def save(path, data):
    # [주의] 이 세션 내내 검증한 것과 동일 — json.dump는 뒤에 개행을 추가하지
    # 않는다. PersonSeed.json 기존 포맷(2-space indent, 비ASCII 문자 그대로,
    # 파일 끝 개행 없음)과 맞추기 위해 일부러 그대로 둔다.
    with io.open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def emit(obj):
    print(json.dumps(obj, ensure_ascii=False))


def cmd_next_idx(args):
    data = load(args.seed_path)
    max_idx = 0
    for e in data:
        raw = e.get("idx", "")
        try:
            n = int(raw)
        except (TypeError, ValueError):
            continue
        if n > max_idx:
            max_idx = n
    emit({"ok": True, "next_idx": str(max_idx + 1)})


def cmd_upsert(args):
    data = load(args.seed_path)
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        emit({"ok": False, "error": f"stdin JSON 파싱 실패: {exc}"})
        sys.exit(1)

    idx = payload.get("idx", "")
    if not idx:
        emit({"ok": False, "error": "idx가 비어 있습니다 — 저장을 중단합니다."})
        sys.exit(1)

    matches = [i for i, e in enumerate(data) if e.get("idx") == idx]
    if len(matches) > 1:
        emit({
            "ok": False,
            "error": f"idx={idx}가 이미 {len(matches)}건 중복 존재합니다 — "
                     "자동으로 하나를 고르지 않고 중단합니다. PersonSeed.json을 "
                     "직접 확인해 주세요.",
        })
        sys.exit(1)

    if matches:
        data[matches[0]] = payload
        action = "updated"
    else:
        if not args.allow_new:
            emit({
                "ok": False,
                "error": f"idx={idx}를 가진 기존 항목을 찾지 못했습니다. "
                         "새로 추가하려면 --allow-new 옵션이 필요합니다.",
            })
            sys.exit(1)
        data.append(payload)
        action = "added"

    save(args.seed_path, data)
    emit({"ok": True, "action": action, "idx": idx, "total": len(data)})


def cmd_delete(args):
    data = load(args.seed_path)
    matches = [i for i, e in enumerate(data) if e.get("idx") == args.idx]
    if len(matches) != 1:
        emit({
            "ok": False,
            "error": f"idx={args.idx} 일치 항목이 {len(matches)}건입니다 "
                     "(정확히 1건일 때만 삭제합니다).",
        })
        sys.exit(1)

    removed = data.pop(matches[0])
    save(args.seed_path, data)
    emit({
        "ok": True,
        "action": "deleted",
        "idx": args.idx,
        "removed_word": removed.get("word", ""),
        "total": len(data),
    })


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed-path", required=True, help="PersonSeed.json 경로")
    sub = parser.add_subparsers(dest="op", required=True)

    p_next = sub.add_parser("next-idx")
    p_next.set_defaults(func=cmd_next_idx)

    p_upsert = sub.add_parser("upsert")
    p_upsert.add_argument("--allow-new", action="store_true")
    p_upsert.set_defaults(func=cmd_upsert)

    p_delete = sub.add_parser("delete")
    p_delete.add_argument("--idx", required=True)
    p_delete.set_defaults(func=cmd_delete)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
