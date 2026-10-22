from pathlib import Path
import json,hashlib,re,sys
R=Path('Tools/LiteralGen');S=Path('.literalgen-state/de-en-ru');langs=['de','en','ru'];master=S/'checkpoint.json'
mode=sys.argv[1];book=sys.argv[2] if len(sys.argv)>2 else '01_GEN'
state=json.loads(master.read_text());info=next(x for x in state['books'] if x['book']==book)
packets=sorted((R/'packets/de-en-ru'/book).glob('*.txt'));files=[R/'outputs'/l/book/(p.stem+'.tsv') for l in langs for p in packets]
protected=json.loads(Path(state['protected_snapshot']).read_text());planfile=S/(book+'-redo-plan.json')
if mode=='status':
 complete=[str(p) for p in files if p.exists()];missing=[str(p) for p in files if not p.exists()]
 info.update(existing_files=len(complete),expected_files=len(files),missing=missing)
 state['current_book']=book;master.write_text(json.dumps(state,ensure_ascii=False,indent=2))
 print(book,'files',len(complete),'/',len(files),'rows',sum(len(Path(p).read_text().splitlines()) for p in complete),'/',info['verses_per_lang']*3)
elif mode=='prepare':
 assert all(p.exists() for p in files),'Book is not complete'
 changes={};seen=set()
 for qfile in sys.argv[3:]:
  for item in json.loads(Path(qfile).read_text()):
   path=Path(item.get('path',item.get('file','')))
   if path.is_absolute():path=path.relative_to(Path.cwd())
   dest=str(path);assert path in files and dest not in protected
   old=item.get('old_row',item.get('old'));new=item.get('new_row',item.get('new'))
   key=(dest,old.split('\t')[0]);assert key not in seen,(key,'duplicate QA');seen.add(key)
   text=changes.get(dest,path.read_text());lines=text.splitlines();assert lines.count(old)==1,(qfile,dest,item.get('verse'))
   assert old.split('\t')[0]==new.split('\t')[0]
   lines[lines.index(old)]=new;changes[dest]='\n'.join(lines)+'\n'
 plan={dest:{'hash':hashlib.sha256(Path(dest).read_bytes()).hexdigest(),'text':text} for dest,text in changes.items() if text!=Path(dest).read_text()}
 planfile.write_text(json.dumps(plan,ensure_ascii=False))
 print('Confirmed new-file redo candidates',len(plan))
elif mode=='queue':
 plan=json.loads(planfile.read_text())
 for l in langs:
  p=R/f'redo_{l}.txt';entries=p.read_text() if p.exists() else ''
  if entries and not entries.endswith('\n'):entries+='\n'
  for dest in sorted(plan):
   if Path(dest).parts[3]!=l:continue
   rel=str(Path(dest).relative_to(R))
   if not any(x.split('\t')[0]==rel for x in entries.splitlines()):entries+=rel+'\tQA: confirmed packet wording or native grammar correction\n'
  p.write_text(entries)
 print('Confirmed candidates queued')
elif mode=='apply':
 plan=json.loads(planfile.read_text())
 for dest,item in plan.items():
  p=Path(dest);assert dest not in protected and p in files
  l=p.parts[3];rel=str(p.relative_to(R))
  assert any(x.split('\t')[0]==rel for x in (R/f'redo_{l}.txt').read_text().splitlines())
  assert hashlib.sha256(p.read_bytes()).hexdigest()==item['hash']
  for row in item['text'].splitlines():
   c=row.split('\t');assert len(c)==3 and all(c) and c[0].isdigit() and len(c[2].split())<=60
   if l=='en':assert c[1]=='='
 for dest,item in plan.items():Path(dest).write_text(item['text'])
 print('Only queued same-task files rewritten',len(plan))
elif mode=='verify':
 assert all(p.exists() for p in files)
 for l in langs:
  count=0;quotes=''
  for packet in packets:
   block=next(b for b in packet.read_text().split('==TARGET ')[1:] if b.startswith('lang='+l+' '));expected=re.findall(r'^#(\d+) ',block,re.M)
   p=R/'outputs'/l/book/(packet.stem+'.tsv');rows=[x.split('\t') for x in p.read_text().splitlines()]
   assert [x[0] for x in rows]==expected,p
   assert all(len(x)==3 and all(x) and len(x[2].split())<=60 for x in rows),p
   if l=='en':assert all(x[1]=='=' for x in rows),p
   quotes+=p.read_text();count+=len(rows)
  assert count==info['verses_per_lang'],(l,count)
  a,b={'de':('„','“'),'en':('“','”'),'ru':('«','»')}[l]
  assert quotes.count(a)==quotes.count(b),(l,'unbalanced quotes',quotes.count(a),quotes.count(b))
  assert not (R/f'redo_{l}.txt').read_text().strip(),l
  print(l,book,len(packets),'files',count,'rows; redo 0')
 assert all(Path(p).exists() and hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in protected.items()),'Protected output changed'
 info.update(status='complete',created_files=len(files),rows=info['verses_per_lang']*3,check_passed=True,redo=0,protected_unchanged=len(protected),missing=[])
 master.write_text(json.dumps(state,ensure_ascii=False,indent=2));print('Book complete;',len(protected),'protected outputs unchanged')
elif mode=='start':
 baseline=S/(book+'-protected.json');snap={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((R/'outputs').rglob('*.tsv'))}
 assert not baseline.exists();baseline.write_text(json.dumps(snap));state['protected_snapshot']=str(baseline);state['protected_files']=len(snap);state['current_book']=book;info['status']='active';master.write_text(json.dumps(state,ensure_ascii=False,indent=2));print('Started',book,'protected',len(snap))
else:raise ValueError(mode)
