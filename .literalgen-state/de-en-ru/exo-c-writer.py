from pathlib import Path
import json
B=Path('/Users/arkuni/Developer/JBCHBibleResearch/Tools/LiteralGen');S=B.parent.parent/'.literalgen-state/de-en-ru';C=S/'exo-c-checkpoint.json'
CL={'de':'Nah am Hebräischen.','en':'Close to the Hebrew.','ru':'Близко к еврейскому.'}
def chapter(c,data):
 rows={}
 for line in data.strip().splitlines():
  a=line.split('|');assert len(a)==6,(c,a)
  v=int(a[0]);assert v not in rows;rows[v]=a
 packets=sorted((B/'packets/de-en-ru/02_EXO').glob(f'EXO_{c:03}*.txt'));expected=[];new=[]
 for p in packets:
  vv=[int(l[1:]) for l in p.read_text().split('==TARGET')[0].splitlines() if l.startswith('#') and l[1:].isdigit()];expected+=vv
  for lang,li,di in [('de',1,3),('en',None,4),('ru',2,5)]:
   out=B/'outputs'/lang/'02_EXO'/(p.stem+'.tsv');out.parent.mkdir(parents=True,exist_ok=True);rr=[]
   for v in vv:
    a=rows[v];lit='=' if li is None else a[li];note=CL[lang] if a[di]=='0' else a[di];assert len(note.split())<=60
    rr.append(f'{v}\t{lit}\t{note}')
   with out.open('x') as f:f.write('\n'.join(rr)+'\n')
   new.append({'path':str(out),'rows':len(rr)})
 assert sorted(rows)==expected
 cp=json.loads(C.read_text()) if C.exists() else {'completed_chapters':[],'new_files':[]}
 cp['completed_chapters'].append(c);cp['new_files']+=new;cp['remaining_chapters']=[i for i in range(29,41) if i not in cp['completed_chapters']];cp['status']='in_progress';C.write_text(json.dumps(cp,ensure_ascii=False,indent=2));print(c,len(new),sum(a['rows'] for a in new))
