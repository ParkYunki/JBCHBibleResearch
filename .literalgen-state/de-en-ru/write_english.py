from pathlib import Path
import json,re,sys
book,chapter,diff_file=sys.argv[1],int(sys.argv[2]),sys.argv[3]
r=Path('Tools/LiteralGen');s=Path('.literalgen-state/de-en-ru');data=json.loads(Path(diff_file).read_text());assert str(chapter) in data
diffs=data[str(chapter)];packets=sorted((r/'packets/de-en-ru'/book).glob(f'*_{chapter:03d}*.txt'));assert packets
plans=[];expected=[]
for packet in packets:
 b=next(x for x in packet.read_text().split('==TARGET ')[1:] if x.startswith('lang=en '));vs=[int(v) for v in re.findall(r'^#(\d+) ',b,re.M)];expected+=vs
 p=r/'outputs/en'/book/(packet.stem+'.tsv');assert not p.exists(),p
 rows=[]
 for v in vs:
  d=diffs.get(str(v),'Close to the Hebrew.');assert d and len(d.split())<=60 and '\t' not in d and '\n' not in d;rows.append(f'{v}\t=\t{d}')
 plans.append((p,'\n'.join(rows)+'\n'))
assert set(map(int,diffs))<=set(expected)
for p,text in plans:
 p.parent.mkdir(parents=True,exist_ok=True)
 with p.open('x') as f:f.write(text)
record=s/(book+'-root-created.json');created=json.loads(record.read_text()) if record.exists() else []
created.extend(str(p) for p,_ in plans);record.write_text(json.dumps(created,ensure_ascii=False,indent=2))
print(book,'EN',chapter,len(plans),'files',len(expected),'rows exclusively created')
