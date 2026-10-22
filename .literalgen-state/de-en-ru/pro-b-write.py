from pathlib import Path
import re,json,sys,hashlib
s=Path('.literalgen-state/de-en-ru');created=json.loads((s/'pro-b-created.json').read_text());cp=json.loads((s/'pro-b-checkpoint.json').read_text())
for c in map(int,sys.argv[1:]):
 vals=[x.split('|') for x in (s/f'pro-b-stage-{c:03}.txt').read_text().splitlines() if x]
 assert all(len(x)==5 for x in vals)
 total=0
 for p in sorted(Path('Tools/LiteralGen/packets/de-en-ru/20_PRO').glob(f'PRO_{c:03}*.txt')):
  ids=re.findall(r'^#(\d+)$',p.read_text().split('==TARGET ')[0],re.M)
  for lang,idx in [('de',0),('ru',2),('en',4)]:
   out=Path(f'Tools/LiteralGen/outputs/{lang}/20_PRO')/(p.stem+'.tsv');out.parent.mkdir(parents=True,exist_ok=True);rows=[]
   for v in ids:
    rec=vals[int(v)-1];lit='=' if lang=='en' else rec[idx];diff=rec[idx] if lang=='en' else rec[idx+1]
    if diff=='~':diff={'de':'Nah am Hebräischen.','ru':'Близко к еврейскому.','en':'Close to the Hebrew.'}[lang]
    assert len(diff.split())<=60
    rows.append(v+'\t'+lit+'\t'+diff)
   with out.open('x') as f:f.write('\n'.join(rows)+'\n')
   created.append({'path':str(out),'rows':len(rows),'sha256':hashlib.sha256(out.read_bytes()).hexdigest()})
  total+=len(ids)
 assert total==len(vals)
 cp['completed'].append(c);cp['pending'].remove(c)
 (s/'pro-b-created.json').write_text(json.dumps(created,ensure_ascii=False,indent=2)+'\n');(s/'pro-b-checkpoint.json').write_text(json.dumps(cp,indent=2)+'\n')
 print(c,total,'verses/lang')
