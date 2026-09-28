import json

path = "PersonSeed.json"
with open(path, encoding="utf-8") as f:
    data = json.load(f)

changes = []

for e in data:
    if e.get("idx") == "4150" and e.get("word") == "엘르아살":
        desc = e.get("description") or {}
        rel = desc.get("관계")
        if isinstance(rel, list) and rel:
            rel = rel[0]
        if isinstance(rel, dict) and rel.get("아버지") == "도대#525":
            rel["아버지"] = "도도#3356"
            changes.append("엘르아살(4150) 아버지: 도대#525 -> 도도#3356")

    if e.get("idx") == "468" and e.get("word") == "다윗":
        desc = e.get("description") or {}
        rel = desc.get("관계")
        if isinstance(rel, list) and rel:
            rel = rel[0]
        others = rel.get("기타관계") if isinstance(rel, dict) else None
        if isinstance(others, list):
            if "도대#525(기타)" in others:
                i = others.index("도대#525(기타)")
                others[i] = "도도#3356(기타)"
                changes.append("다윗(468) 기타관계: 도대#525(기타) -> 도도#3356(기타)")
            if "이대#2810(다윗의 30용사)" in others:
                # 이미 같은 목록에 "잇대#4452(다윗의 30용사)"가 정확한 idx로
                # 존재함(동일 인물의 중복 표기) -> 치환 대신 제거해 중복을
                # 만들지 않는다.
                assert "잇대#4452(다윗의 30용사)" in others, "잇대#4452 항목이 없어 예상과 다름 - 확인 필요"
                others.remove("이대#2810(다윗의 30용사)")
                changes.append("다윗(468) 기타관계: 이대#2810(다윗의 30용사) 제거 (잇대#4452(다윗의 30용사)와 중복)")

assert len(changes) == 3, f"예상한 3건이 아니라 {len(changes)}건 변경됨: {changes}"
for c in changes:
    print("  -", c)

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")

print("SAVED")
