#!/usr/bin/env python3
"""사용자 추가 번역본(앱에 배포하지 않음)의 절 본문 지문 표를 Literal_<언어>.sqlite에 넣는다. [2026-10-21]

앱은 사용자가 추가한 번역본의 절 본문으로 같은 지문을 계산해, 이 표에서 맞는 번역본 코드를 찾고
그 코드의 TranslationDifference 설명을 보여 준다(`VerseTextFingerprint.swift`와 정규화·해시 규칙이 같아야 한다).

정규화: NFC → A–Z는 소문자로 → a–z, 0–9, 한글 음절(U+AC00–U+D7A3)만 남김(공백·구두점·괄호·그 밖 문자는 버림).
지문: 정규화 문자열 UTF-8의 SHA-256 앞 8바이트, 빅엔디언 부호 있는 64비트 정수.
본문 원본은 저장하지 않는다(지문으로 본문을 되살릴 수 없다).

사용: python3 Tools/LiteralGen/ext_hashes.py <원본.bdb> <번역본 코드> <출력 sqlite 경로> [<출력 sqlite 경로> ...]
  출력 sqlite는 홈 폴더 등 쓰기 가능한 곳의 작업 사본이어야 한다(연결 폴더 안 SQLite 쓰기는 저널 삭제가 막혀 실패할 수 있음).
"""
import sqlite3, sys, hashlib, unicodedata


def normalized(text):
    out = []
    for ch in unicodedata.normalize('NFC', text or ''):
        o = ord(ch)
        if 0x41 <= o <= 0x5A:
            out.append(chr(o + 0x20))
        elif 0x61 <= o <= 0x7A or 0x30 <= o <= 0x39 or 0xAC00 <= o <= 0xD7A3:
            out.append(ch)
    return ''.join(out)


def fingerprint(text):
    n = normalized(text)
    if not n:
        return None
    return int.from_bytes(hashlib.sha256(n.encode('utf-8')).digest()[:8], 'big', signed=True)


def ensure_tables(db):
    db.execute('''CREATE TABLE IF NOT EXISTS LiteralText (book_id INTEGER NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL,
        text TEXT NOT NULL, basis TEXT, generator TEXT, generated_at TEXT, review_status TEXT,
        PRIMARY KEY(book_id, chapter, verse)) WITHOUT ROWID''')
    db.execute('''CREATE TABLE IF NOT EXISTS TranslationDifference (translation_code TEXT NOT NULL, book_id INTEGER NOT NULL,
        chapter INTEGER NOT NULL, verse INTEGER NOT NULL, explanation TEXT NOT NULL, generator TEXT, generated_at TEXT,
        review_status TEXT, PRIMARY KEY(translation_code, book_id, chapter, verse)) WITHOUT ROWID''')
    db.execute('''CREATE TABLE IF NOT EXISTS TranslationVerseHash (translation_code TEXT NOT NULL, book_id INTEGER NOT NULL,
        chapter INTEGER NOT NULL, verse INTEGER NOT NULL, hash INTEGER NOT NULL,
        PRIMARY KEY(translation_code, book_id, chapter, verse)) WITHOUT ROWID''')
    db.execute('CREATE INDEX IF NOT EXISTS idx_verse_hash ON TranslationVerseHash(book_id, chapter, verse, hash)')


def main():
    src, code, outs = sys.argv[1], sys.argv[2], sys.argv[3:]
    rows = []
    for b, c, v, t in sqlite3.connect(src).execute('SELECT book, chapter, verse, btext FROM Bible'):
        h = fingerprint(t)
        if h is not None:
            rows.append((code, int(b), int(c), int(v), h))
    for out in outs:
        db = sqlite3.connect(out)
        ensure_tables(db)
        db.execute('DELETE FROM TranslationVerseHash WHERE translation_code = ?', (code,))
        db.executemany('INSERT INTO TranslationVerseHash VALUES (?,?,?,?,?)', rows)
        db.commit()
        n = db.execute('SELECT COUNT(*) FROM TranslationVerseHash WHERE translation_code = ?', (code,)).fetchone()[0]
        print(f'{out}: {code} 지문 {n}')
        db.close()


if __name__ == '__main__':
    main()
