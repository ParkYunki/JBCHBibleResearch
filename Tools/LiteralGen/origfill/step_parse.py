"""STEPBible TAGNT/TAHOT 읽기 (make_packets.load_step과 같은 절 번호: 앞쪽 주 참조, 시편 표제 0절은 1절 앞에 붙임).
반환: {(book_id, ch, v): [dict(orig, translit, tr, strong_raw, morph, gloss_raw, editions, wtype)]}"""
import glob, os, re, collections

BOOKS = ("GEN EXO LEV NUM DEU JOS JDG RUT 1SA 2SA 1KI 2KI 1CH 2CH EZR NEH EST JOB PSA PRO ECC SNG ISA JER LAM "
         "EZK DAN HOS JOL AMO OBA JON MIC NAM HAB ZEP HAG ZEC MAL MAT MRK LUK JHN ACT ROM 1CO 2CO GAL EPH PHP COL "
         "1TH 2TH 1TI 2TI TIT PHM HEB JAS 1PE 2PE 1JN 2JN 3JN JUD REV").split()
STEPCODE = {"Gen": "GEN", "Exo": "EXO", "Lev": "LEV", "Num": "NUM", "Deu": "DEU", "Jos": "JOS", "Jdg": "JDG",
            "Rut": "RUT", "1Sa": "1SA", "2Sa": "2SA", "1Ki": "1KI", "2Ki": "2KI", "1Ch": "1CH", "2Ch": "2CH",
            "Ezr": "EZR", "Neh": "NEH", "Est": "EST", "Job": "JOB", "Psa": "PSA", "Pro": "PRO", "Ecc": "ECC",
            "Sng": "SNG", "Isa": "ISA", "Jer": "JER", "Lam": "LAM", "Ezk": "EZK", "Dan": "DAN", "Hos": "HOS",
            "Jol": "JOL", "Amo": "AMO", "Oba": "OBA", "Jon": "JON", "Mic": "MIC", "Nam": "NAM", "Hab": "HAB",
            "Zep": "ZEP", "Hag": "HAG", "Zec": "ZEC", "Mal": "MAL", "Mat": "MAT", "Mrk": "MRK", "Luk": "LUK",
            "Jhn": "JHN", "Act": "ACT", "Rom": "ROM", "1Co": "1CO", "2Co": "2CO", "Gal": "GAL", "Eph": "EPH",
            "Php": "PHP", "Col": "COL", "1Th": "1TH", "2Th": "2TH", "1Ti": "1TI", "2Ti": "2TI", "Tit": "TIT",
            "Phm": "PHM", "Heb": "HEB", "Jas": "JAS", "1Pe": "1PE", "2Pe": "2PE", "1Jn": "1JN", "2Jn": "2JN",
            "3Jn": "3JN", "Jud": "JUD", "Rev": "REV"}
BID = {b: i + 1 for i, b in enumerate(BOOKS)}
REF = re.compile(r"^([1-3]?[A-Za-z]{2,3})\.(\d+)\.(\d+)(\S*?)#(\d+)=(\S+)")


def load(step_dir, target=None):
    """target(b, c, v, alt, wnum, nt) -> (b, c, v) 또는 None(제외). 없으면 주 참조(NRSV 절 번호)."""
    out = collections.defaultdict(list)
    for f in sorted(glob.glob(os.path.join(step_dir, "TA*.txt"))):
        nt = "TAGNT" in os.path.basename(f)
        for line in open(f, encoding="utf-8"):
            m = REF.match(line)
            if not m or m.group(1) not in STEPCODE:
                continue
            cols = line.rstrip("\n").split("\t")
            b = BID[STEPCODE[m.group(1)]]
            c, v = int(m.group(2)), int(m.group(3))
            d = {"alt": m.group(4), "wtype": m.group(6), "line": line.rstrip("\n")}
            if nt:
                gk = cols[1]
                mm = re.match(r"^(.*?) \((.*)\)$", gk)
                d.update(orig=mm.group(1) if mm else gk, translit=mm.group(2) if mm else "",
                         tr=cols[2], sm=cols[3], lg=cols[4], ed=cols[5] if len(cols) > 5 else "")
            else:
                d.update(orig=cols[1], translit=cols[2], tr=cols[3], strong=cols[4], morph=cols[5] if len(cols) > 5 else "",
                         ed="")
            key = (b, c, v)
            if target is not None:
                key = target(b, c, v, m.group(4), int(m.group(5)), nt)
                if key is None:
                    continue
            out[(key[0], key[1], max(key[2], 1))].append(d)
    return out
