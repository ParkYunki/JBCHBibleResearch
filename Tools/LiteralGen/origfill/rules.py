import re
def nt_text(s):
    return re.sub(r"[,.;¶]+$", "", s.strip())
def ot_text(s):
    s = s.replace("/", "")
    if s.endswith("\\׃"): s = s[:-2]
    return s.replace("\\", "")
def ot_tl(s): return s.replace("/", "")
def ot_morph(m): return m if m.startswith("H") else "H" + m
def clean_tr(s): return re.sub(r"\s+", " ", s.replace("/", "")).strip()
def nt_strong(sc): return re.sub(r"(?<=\d)[A-Za-z]$", "", sc)
def ot_strong(s):
    m = re.search(r"\{(H\d+)[A-Za-z]?\}", s); return m.group(1) if m else ""
