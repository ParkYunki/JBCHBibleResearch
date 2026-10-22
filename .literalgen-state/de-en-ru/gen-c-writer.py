import pathlib,json,re
B=pathlib.Path('/Users/arkuni/Developer/JBCHBibleResearch/Tools/LiteralGen'); S=B.parent.parent/'.literalgen-state/de-en-ru';S.mkdir(parents=True,exist_ok=True)
def chapter(c,data):
 d={}
 for row in data.strip().splitlines():
  a=row.split('|');assert len(a)==6,(c,len(a),row);d[int(a[0])]=a[1:]
 files=[]
 for p in sorted((B/'packets/de-en-ru/01_GEN').glob(f'GEN_{c:03}*.txt')):
  vs=[int(v) for v in re.findall(r'^#(\d+)\nO ',p.read_text().split('==TARGET')[0],re.M)]
  for lang,li,ni,close in [('de',0,2,'Nah am Hebräischen.'),('en',None,3,'Close to the Hebrew.'),('ru',1,4,'Близко к еврейскому.')]:
   if c>=48 and lang=='en':continue
   out=[]
   for v in vs:
    r=d[v];lit='=' if li is None else r[li];n=close if r[ni].strip()=='-' else r[ni];assert len(n.split())<=60;assert '(' not in lit and ')' not in lit
    out.append(f'{v}\t{lit}\t{n}')
   dest=B/'outputs'/lang/'01_GEN'/(p.stem+'.tsv');dest.parent.mkdir(parents=True,exist_ok=True)
   with dest.open('x') as f:f.write('\n'.join(out)+'\n')
   files.append({'path':str(dest),'rows':len(out)})
 cp=S/'gen-c-checkpoint.json';j=json.loads(cp.read_text()) if cp.exists() else {'completed_chapters':list(range(35,45)),'root_completed_en':[48,49,50],'new_files':[]}
 j['completed_chapters'].append(c);j['new_files']+=files;j['remaining_chapters']=[i for i in range(35,51) if i not in j['completed_chapters']];j['status']='in_progress';cp.write_text(json.dumps(j,ensure_ascii=False,indent=2));print(c,len(files),sum(x['rows'] for x in files))
