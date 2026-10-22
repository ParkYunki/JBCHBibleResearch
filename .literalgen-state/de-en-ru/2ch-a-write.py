from pathlib import Path
import json,re
ROOT=Path('Tools/LiteralGen'); STATE=Path('.literalgen-state/de-en-ru')
def write(ch,lang,body,diffs):
 rows=body.strip().splitlines() if lang!='en' else ['=']*len(body)
 if lang=='en': verses=body
 else: verses=list(range(1,len(rows)+1))
 data=dict(zip(verses,rows)); created=[]
 for p in sorted((ROOT/'packets/de-en-ru/14_2CH').glob(f'2CH_{ch:03d}*.txt')):
  text=p.read_text(); target=next(x for x in text.split('==TARGET ')[1:] if x.startswith('lang='+lang+' ')); nums=list(map(int,re.findall(r'^#(\d+) ',target,re.M)))
  lines=[f'{v}\t{data[v]}\t{diffs.get(v,{"de":"Nah am Hebräischen.","en":"Close to the Hebrew.","ru":"Близко к еврейскому."}[lang])}' for v in nums]
  for line in lines:
   fields=line.split('\t'); assert len(fields)==3 and len(fields[2].split())<=60
  out=ROOT/'outputs'/lang/'14_2CH'/f'{p.stem}.tsv'; out.parent.mkdir(parents=True,exist_ok=True)
  if out.exists(): continue
  with out.open('x') as f:f.write('\n'.join(lines)+'\n')
  created.append(str(out))
 cp=STATE/'2ch-a-checkpoint.json'; old=json.loads(cp.read_text()) if cp.exists() else {'created':[],'chapters_complete':[]}
 old['created']+=created; old['chapters_complete'].append([ch,lang]);cp.write_text(json.dumps(old,ensure_ascii=False,indent=2)+'\n')
 print(ch,lang,len(rows),created)
