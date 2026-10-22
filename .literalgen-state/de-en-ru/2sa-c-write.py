from pathlib import Path
import json,re
ROOT=Path.cwd(); STATE=ROOT/'.literalgen-state/de-en-ru'
def write(ch,lang,text,diffs=None):
 rows=text.strip().splitlines(); trans={i+1:r for i,r in enumerate(rows)}
 diffs=diffs or {}; close={'de':'Nah am Hebräischen.','en':'Close to the Hebrew.','ru':'Близко к еврейскому.'}[lang]
 cp=json.loads((STATE/'2sa-c-checkpoint.json').read_text())
 for p in sorted((ROOT/'Tools/LiteralGen/packets/de-en-ru/10_2SA').glob(f'2SA_{ch:03}*.txt')):
  s=p.read_text(); blocks=s.split('==TARGET '); target=next(b for b in blocks[1:] if b.startswith(f'lang={lang} ')); nums=[int(x) for x in re.findall(r'^#(\d+) ',target,re.M)]
  out=ROOT/f'Tools/LiteralGen/outputs/{lang}/10_2SA/{p.stem}.tsv'; lines=[]
  for v in nums:
   lit='=' if lang=='en' else trans[v]; diff=diffs.get(v,close)
   assert '\t' not in lit and len(diff.split())<=60
   lines.append(f'{v}\t{lit}\t{diff}')
  out.parent.mkdir(parents=True,exist_ok=True)
  with out.open('x') as f:f.write('\n'.join(lines)+'\n')
  cp['new_files'].append({'path':str(out),'rows':len(nums)})
 (STATE/'2sa-c-checkpoint.json').write_text(json.dumps(cp,ensure_ascii=False,indent=2)+'\n')
