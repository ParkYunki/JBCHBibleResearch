from pathlib import Path
import json,re,hashlib
ROOT=Path.cwd();s=ROOT/'.literalgen-state/de-en-ru';qa=[]
def change(lang,v,repl=None,lit=None,diff=None):
 found=[(p,r) for p in (ROOT/f'Tools/LiteralGen/outputs/{lang}/11_1KI').glob('1KI_006*.tsv') for r in p.read_text().splitlines() if r.startswith(str(v)+'\t')];assert len(found)==1
 p,old=found[0];a=old.split('\t')
 if repl:
  for x,y in repl:assert x in a[1];a[1]=a[1].replace(x,y)
 if lit is not None:a[1]=lit
 if diff is not None:a[2]=diff
 new='\t'.join(a);assert old!=new
 qa.append({'path':str(p),'verse':v,'old_row':old,'new_row':new})
change('ru',10,repl=[('кедровыми деревьями','кедровыми брёвнами')])
change('de',18,repl=[('Koloquinten','Kürbisformen')],diff='Nah am Hebräischen.')
change('ru',27,repl=[('а их крылья к середине дома касались крылом крыла','а их крылья, обращённые к середине дома, касались друг друга, крыло к крылу')])
(s/'1ki-c-extra006-qa.json').write_text(json.dumps(qa,ensure_ascii=False,indent=2)+'\n')
qmap={(q['path'],q['verse']):q['new_row'] for q in qa};cp=json.loads((s/'1ki-c-extra006-checkpoint.json').read_text());files=[];quotes={}
for f in cp['new_files']:
 p=Path(f['path']);lang=p.parts[-3];packet=ROOT/'Tools/LiteralGen/packets/de-en-ru/11_1KI'/p.with_suffix('.txt').name
 block=next(b for b in packet.read_text().split('==TARGET')[1:] if re.search(r'\blang='+lang+r'\b',b[:70]));nums=[int(n) for n in re.findall(r'^#(\d+)',block,re.M)];rows=p.read_text().splitlines();assert [int(r.split('\t')[0]) for r in rows]==nums;assert len(rows)==f['rows']
 for row in rows:
  a=qmap.get((str(p),int(row.split('\t')[0])),row).split('\t');assert len(a)==3 and all(a);assert len(a[2].split())<=60
 files.append({**f,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
for lang,op,cl in [('de','„','“'),('ru','«','»')]:
 t='\n'.join(qmap.get((f['path'],int(r.split('\t')[0])),r).split('\t')[1] for f in cp['new_files'] if '/outputs/'+lang+'/' in f['path'] for r in Path(f['path']).read_text().splitlines());quotes[lang]={'open':t.count(op),'close':t.count(cl)};assert t.count(op)==t.count(cl)
v={'files':len(files),'rows':sum(f['rows'] for f in files),'all_assigned_verses_reviewed':True,'own_qa_rows':len(qa),'literal_quote_counts':quotes,'problems':[],'tsv_modified_during_qa':False,'files_detail':files}
(s/'1ki-c-extra006-created.json').write_text(json.dumps(files,ensure_ascii=False,indent=2)+'\n');(s/'1ki-c-extra006-validation.json').write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
cp.update(status='generation_and_full_qa_complete',completed_chapters=[6],remaining_chapters=[],generated_file_count=len(files),generated_rows=v['rows'],own_qa_rows=len(qa));(s/'1ki-c-extra006-checkpoint.json').write_text(json.dumps(cp,ensure_ascii=False,indent=2)+'\n');print({k:x for k,x in v.items() if k!='files_detail'})
