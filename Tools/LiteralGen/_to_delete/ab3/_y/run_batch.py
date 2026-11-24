#!/usr/bin/env python3
"""원어 단어 ↔ 한국어 직역 짝짓기: Anthropic Message Batches API 실행기 (표준 라이브러리만 사용).

사용(Mac 터미널, 이 파일이 있는 폴더에서):
  python3 run_batch.py submit --packets packets/ko --out results/ko --first 5     # 시범 5묶음
  python3 run_batch.py submit --packets packets/ko --out results/ko --skip-done  # 나머지 전부
  python3 run_batch.py resume <batch_id> --out results/ko                         # 중단된 대기 재개

- API 키: ~/Developer/.anthropic_api_key (환경변수 ANTHROPIC_API_KEY가 있으면 그것 우선). 키는 출력하지 않는다.
- 제출 후 끝날 때까지 60초마다 상태를 확인하고, 끝나면 결과를 out 폴더에 묶음별 .txt로 저장한다.
- 사용량(토큰)을 usage.jsonl에 남기고 합계를 출력한다.
"""
import argparse, json, os, sys, time, urllib.request, urllib.error, pathlib

API = "https://api.anthropic.com/v1/messages/batches"
VERSION = "2023-06-01"
MODEL = "claude-sonnet-5-5"
HERE = pathlib.Path(__file__).resolve().parent


def api_key():
    k = os.environ.get("ANTHROPIC_API_KEY")
    if not k:
        p = pathlib.Path.home() / "Developer" / ".anthropic_api_key"
        k = p.read_text(encoding="utf-8").strip()
    if not k.startswith("sk-ant-"):
        sys.exit("API 키 형식이 아닙니다.")
    return k


def call(method, url, key, body=None):
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "x-api-key": key, "anthropic-version": VERSION, "content-type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.read()
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code}: {e.read().decode('utf-8', 'replace')[:800]}")


def submit(args, key):
    system = (HERE / "prompt_ko.md").read_text(encoding="utf-8")
    pk = sorted((HERE / args.packets).glob("p*.txt"))
    out = HERE / args.out
    if args.skip_done:
        pk = [p for p in pk if not ((out / p.name).exists() and (out / p.name).stat().st_size > 10)]
    if args.range:
        lo, hi = args.range
        pk = [p for p in pk if lo <= int(p.stem[1:]) <= hi]
    if args.first:
        pk = pk[: args.first]
    if not pk:
        sys.exit("보낼 묶음이 없습니다.")
    reqs = [{
        "custom_id": p.stem,
        "params": {
            "model": args.model,
            "max_tokens": args.max_tokens,
            # 이 모델은 생각(thinking)이 기본으로 켜질 수 있어, 시범에서 출력 한도를 생각에 다 써 버렸다(본문 0자).
            # 정답 형식만 필요한 작업이라 끈다. 이 모델에서 끄는 값은 "between_tools"(API 오류 안내문 기준, 도구 미사용이라 생각 없음).
            "system": [{"type": "text", "text": system, "cache_control": {"type": "ephemeral"}}],
            "messages": [{"role": "user", "content": p.read_text(encoding="utf-8")}],
        },
    } for p in pk]
    if args.thinking != "omit":
        for r in reqs:
            r["params"]["thinking"] = {"type": args.thinking}
    res = json.loads(call("POST", API, key, {"requests": reqs}))
    bid = res["id"]
    (HERE / "last_batch_id.txt").write_text(bid + "\n", encoding="utf-8")
    print(f"제출: {len(reqs)}묶음, batch id = {bid}")
    wait_and_fetch(bid, out, key)


def wait_and_fetch(bid, out, key):
    while True:
        st = json.loads(call("GET", f"{API}/{bid}", key))
        c = st.get("request_counts", {})
        print(time.strftime("%H:%M:%S"), st.get("processing_status"), c, flush=True)
        if st.get("processing_status") == "ended":
            break
        time.sleep(60)
    raw = call("GET", st["results_url"], key).decode("utf-8")
    out.mkdir(parents=True, exist_ok=True)
    tot = {"input_tokens": 0, "output_tokens": 0, "cache_read_input_tokens": 0, "cache_creation_input_tokens": 0}
    ok = bad = 0
    credit_out = False
    with open(out / "usage.jsonl", "a", encoding="utf-8") as uf:
        for line in raw.splitlines():
            if not line.strip():
                continue
            r = json.loads(line)
            cid = r["custom_id"]
            res = r["result"]
            if res["type"] != "succeeded":
                err = json.dumps(res.get("error", {}), ensure_ascii=False)
                if "credit balance" in err:
                    credit_out = True
                bad += 1
                print("실패:", cid, res["type"], json.dumps(res.get("error", {}), ensure_ascii=False)[:300])
                continue
            msg = res["message"]
            text = "".join(b.get("text", "") for b in msg["content"] if b.get("type") == "text")
            (out / f"{cid}.txt").write_text(text.strip() + "\n", encoding="utf-8")
            u = msg.get("usage", {})
            for k in tot:
                tot[k] += u.get(k) or 0
            kinds = [b.get("type") for b in msg["content"]]
            uf.write(json.dumps({"batch": bid, "packet": cid, "stop": msg.get("stop_reason"), "blocks": kinds, "chars": len(text), "usage": u}) + "\n")
            if not text.strip():
                print("주의: 본문이 비어 있음:", cid, kinds)
            if msg.get("stop_reason") == "max_tokens":
                print("주의: 출력이 잘림(max_tokens):", cid)
            ok += 1
    print(f"완료: 성공 {ok}, 실패 {bad}")
    if credit_out:
        print("API 크레딧이 부족해 실패한 묶음이 있습니다. 남은 묶음은 이 결과 폴더 기준 --skip-done 으로 다시 보낼 수 있습니다.")
    print("토큰 합계:", tot)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("submit")
    s.add_argument("--packets", default="packets/ko")
    s.add_argument("--out", default="results/ko")
    s.add_argument("--first", type=int, default=0)
    s.add_argument("--range", type=int, nargs=2, metavar=("FROM", "TO"), help="묶음 번호 범위(포함), 예: --range 2315 3110")
    s.add_argument("--skip-done", action="store_true")
    s.add_argument("--model", default=MODEL)
    s.add_argument("--max-tokens", type=int, default=16000)
    s.add_argument("--thinking", default="between_tools", help="between_tools(끔) | adaptive | omit(모델 기본값)")
    r = sub.add_parser("resume")
    r.add_argument("batch_id")
    r.add_argument("--out", default="results/ko")
    a = ap.parse_args()
    key = api_key()
    if a.cmd == "submit":
        submit(a, key)
    else:
        wait_and_fetch(a.batch_id, HERE / a.out, key)


if __name__ == "__main__":
    main()
