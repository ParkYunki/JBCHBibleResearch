#!/usr/bin/env python3
"""채팅형 AI 답변을 출력 파일로 나눠 저장한다.

답변을 텍스트 파일로 저장한 뒤:
  python3 Tools/LiteralGen/split_blocks.py answer.txt
답변 안의 블록 형식:
  === <lang> <묶음 파일 이름>        (예: === fr PHM_001.txt)
  <절>\t<직역>\t<차이 설명>
  …
→ Tools/LiteralGen/outputs/<lang>/<NN_BOOK>/<묶음 이름>.tsv 로 저장(이미 있으면 .tsv를 덮어쓴다).
저장 뒤 import_outputs.py --check 로 검사한다.
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from make_packets import BID  # noqa: E402

HEAD = re.compile(r'^===\s*([a-z]{2,3})\s+([1-3]?[A-Z]{2,3})_(\d{3})(_\d+)?(?:\.txt)?\s*$')


def main(path):
    cur = None
    blocks = {}
    for raw in open(path, encoding='utf-8'):
        line = raw.rstrip('\n')
        m = HEAD.match(line.strip())
        if m:
            lang, book, ch, part = m.group(1), m.group(2), m.group(3), m.group(4) or ''
            cur = (lang, book, f'{book}_{ch}{part}')
            blocks[cur] = []
            continue
        if cur and line.strip() and not line.startswith('```'):
            blocks[cur].append(line)
    for (lang, book, stem), rows in blocks.items():
        d = os.path.join(HERE, 'outputs', lang, f'{BID[book]:02d}_{book}')
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, stem + '.tsv'), 'w', encoding='utf-8') as fh:
            fh.write('\n'.join(rows) + '\n')
        print(f'{lang} {stem}: {len(rows)}행')


if __name__ == '__main__':
    main(sys.argv[1])
