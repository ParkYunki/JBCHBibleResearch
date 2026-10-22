from pathlib import Path
import json,re
ROOT=Path('Tools/LiteralGen')
def write(ch,lang,rows,notes=None):
    notes=notes or {}
    if isinstance(rows,str): rows={i+1:s for i,s in enumerate(rows.strip().splitlines())}
    created=[]
    for p in sorted((ROOT/'packets/de-en-ru/12_2KI').glob(f'2KI_{ch:03d}*.txt')):
        b=p.read_text().split('==TARGET ')
        t=next(x for x in b[1:] if x.startswith('lang='+lang+' '))
        vs=[int(v) for v in re.findall(r'^#(\d+) ',t,re.M)]
        if lang!='en' and not all(v in rows for v in vs): continue
        dest=ROOT/'outputs'/lang/'12_2KI'/(p.stem+'.tsv')
        if dest.exists(): continue
        close={'de':'Nah am Hebräischen.','en':'Close to the Hebrew.','ru':'Близко к еврейскому.'}[lang]
        out=[]
        for v in vs:
            lit='=' if lang=='en' else rows[v]
            diff=notes.get(v,close)
            assert len(diff.split())<=60 and '\t' not in lit and '\n' not in lit
            out.append(f'{v}\t{lit}\t{diff}')
        with dest.open('x') as f:f.write('\n'.join(out)+'\n')
        created.append(str(dest))
    cp=Path('.literalgen-state/de-en-ru/2ki-b-created.json')
    a=json.loads(cp.read_text()) if cp.exists() else []
    a+=created;cp.write_text(json.dumps(a,ensure_ascii=False,indent=2))
    return created
