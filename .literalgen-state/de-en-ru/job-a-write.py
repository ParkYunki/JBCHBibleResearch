from pathlib import Path
import re,json,sys
root=Path.cwd();state=root/'.literalgen-state/de-en-ru'; record=state/'job-a-created.json';created=json.loads(record.read_text()) if record.exists() else []
for c in map(int,sys.argv[1:]):
 rows=[x.split('|') for x in (state/f'job-a-{c:03}.txt').read_text().splitlines()]
 assert all(len(x)==5 for x in rows),(c,[(i+1,len(x)) for i,x in enumerate(rows) if len(x)!=5])
 packets=sorted((root/'Tools/LiteralGen/packets/de-en-ru/18_JOB').glob(f'JOB_{c:03}*.txt'));ids=[]
 for p in packets:ids+=re.findall(r'^#(\d+)\nO ',p.read_text().split('==TARGET ')[0],re.M)
 assert len(rows)==len(ids),(c,len(rows),len(ids)); data=dict(zip(ids,rows))
 for p in packets:
  verses=re.findall(r'^#(\d+)\nO ',p.read_text().split('==TARGET ')[0],re.M)
  for lang,li,di in [('de',0,1),('ru',2,3),('en',None,4)]:
   out=root/f'Tools/LiteralGen/outputs/{lang}/18_JOB/{p.stem}.tsv';out.parent.mkdir(parents=True,exist_ok=True);lines=[]
   for v in verses:
    r=data[v];literal=r[li] if li is not None else '=';diff=r[di];assert len(diff.split())<=60
    lines.append(v+'\t'+literal+'\t'+diff)
   with out.open('x') as f:f.write('\n'.join(lines)+'\n')
   created.append(str(out))
 record.write_text(json.dumps(created,ensure_ascii=False,indent=2)+'\n')
 checkpoint={'book':'18_JOB','created_files':len(created),'created':created,'chapters_done':sorted({int(Path(x).stem.split('_')[1]) for x in created}),'status':'working'}
 (state/'job-a-checkpoint.json').write_text(json.dumps(checkpoint,ensure_ascii=False,indent=2)+'\n')
print('Created chapters',sys.argv[1:],'files total',len(created))
