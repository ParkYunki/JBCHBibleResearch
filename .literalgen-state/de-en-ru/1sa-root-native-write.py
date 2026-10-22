from pathlib import Path
import json,re
S=Path('.literalgen-state/de-en-ru');R=Path('Tools/LiteralGen')
def write(ch,lang,rows):
 packets=sorted((R/'packets/de-en-ru/09_1SA').glob(f'1SA_{ch:03d}*.txt'));plans=[]
 for packet in packets:
  block=next(x for x in packet.read_text().split('==TARGET ')[1:] if x.startswith('lang='+lang+' '));vs=re.findall(r'^#(\d+) ',block,re.M);out=R/'outputs'/lang/'09_1SA'/(packet.stem+'.tsv');assert not out.exists(),out
  lines=[]
  for v in vs:
   lit,diff=rows[int(v)-1];assert lit and diff and '\t' not in lit+diff and '\n' not in lit+diff and len(diff.split())<=60
   lines.append(v+'\t'+lit+'\t'+diff)
  plans.append((out,'\n'.join(lines)+'\n'))
 assert sum(t.count('\n') for _,t in plans)==len(rows)
 p=S/'09_1SA-root-native-created.json';created=json.loads(p.read_text()) if p.exists() else []
 for out,t in plans:
  out.parent.mkdir(parents=True,exist_ok=True)
  with out.open('x') as f:f.write(t)
  created.append(str(out))
 p.write_text(json.dumps(created,ensure_ascii=False,indent=2)+'\n');print(lang,ch,len(plans),'files',len(rows),'rows exclusively created')
