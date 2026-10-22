from pathlib import Path
import re,json,sys
ch=int(sys.argv[1]);lang=sys.argv[2];stage=Path(sys.argv[3]);s=Path('.literalgen-state/de-en-ru');rows=stage.read_text().splitlines();plans=[]
for packet in sorted(Path('Tools/LiteralGen/packets/de-en-ru/19_PSA').glob(f'PSA_{ch:03}*.txt')):
 b=next(x for x in packet.read_text().split('==TARGET ')[1:] if x.startswith('lang='+lang+' '));nums=[int(v) for v in re.findall(r'^#(\d+) ',b,re.M)]
 out=Path(f'Tools/LiteralGen/outputs/{lang}/19_PSA/{packet.stem}.tsv');assert not out.exists();result=[]
 for v in nums:
  lit,diff=rows[v-1].split('|');assert lit and diff and '\t' not in lit and len(diff.split())<=60;result.append(f'{v}\t{lit}\t{diff}')
 plans.append((out,'\n'.join(result)+'\n'))
assert sum(len(t.splitlines()) for _,t in plans)==len(rows)
record=s/'19_PSA-root-created.json';created=json.loads(record.read_text()) if record.exists() else []
for out,t in plans:
 out.parent.mkdir(parents=True,exist_ok=True)
 with out.open('x') as f:f.write(t)
 created.append(str(out))
record.write_text(json.dumps(created,ensure_ascii=False,indent=2)+'\n');print(ch,lang,len(plans),'files',len(rows),'rows')
