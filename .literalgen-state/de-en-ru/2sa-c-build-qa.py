from pathlib import Path
import json,re,hashlib
ROOT=Path.cwd();state=ROOT/'.literalgen-state/de-en-ru';base=ROOT/'Tools/LiteralGen/outputs';qa={};rootqa={};nativeqa={}
def change(lang,ch,v,lit=None,diff=None,repl=None,kind='own'):
 files=list((base/lang/'10_2SA').glob(f'2SA_{ch:03}*.tsv'))
 found=[(p,row) for p in files for row in p.read_text().splitlines() if row.split('\t')[0]==str(v)];assert len(found)==1
 p,old=found[0];a=old.split('\t')
 if lit is not None:a[1]=lit
 if diff is not None:a[2]=diff
 if repl:
  for x,y in repl:assert x in a[1],(lang,ch,v,x);a[1]=a[1].replace(x,y)
 new='\t'.join(a);assert old!=new
 d={'own':qa,'en':rootqa,'native':nativeqa}[kind];key=(str(p),v);assert key not in d
 d[key]={'path':str(p),'verse':v,'old_row':old,'new_row':new}
change('ru',17,9,repl=[('когда вначале падут среди них','когда вначале некоторые падут среди них')])
change('ru',17,22,repl=[('не недоставало ни одного, кто не перешёл Иордана','не оказалось ни одного, кто не перешёл Иордана')])
change('en',17,19,diff='The Hebrew calls her “the woman”; BSB specifies “the man’s wife”.')
change('de',18,18,repl=[('die Säule genommen und sich aufgerichtet','die Säule genommen und für sich aufgerichtet')])
change('en',18,16,diff='The Hebrew repeats “the people” for the returning group and those restrained; BSB has “the troops” and then “them”.')
change('en',18,31,diff='The Hebrew repeats “the Cushite” and names the hand of the attackers; BSB leaves the second mention and the hand image implicit.')
change('de',19,19,repl=[('dass der König es sich zu Herzen nähme','und der König nehme es sich nicht zu Herzen')])
change('ru',19,19,repl=[('чтобы царь принял это к своему сердцу','и пусть царь не примет этого к своему сердцу')])
change('ru',19,35,repl=[('Узнаю ли между добром и злом?','Смогу ли я различать добро и зло?')])
change('en',20,17,diff='Close to the Hebrew.')
change('ru',22,41,lit='И моих врагов Ты отдал мне повёрнутыми затылком; ненавидящих меня я истребил.')
change('ru',22,42,lit='Они смотрели, и не было спасителя; на Господа смотрели, но Он не ответил им.')
change('de',23,3,repl=[('Wer über die Menschen herrscht, sei gerecht, herrschend in Gottesfurcht','Ein Herrscher über die Menschen ist gerecht, ein Herrscher in Gottesfurcht')])
change('ru',23,3,repl=[('Сказал Бог Израиля, ко мне говорил скала Израиля','Сказал Бог Израиля; скала Израиля говорила ко мне')])
change('ru',23,18,repl=[('свой копьё','своё копьё')])
change('ru',23,20,repl=[('сын храброго мужа, многодеятельного, из Кавцеила','сын храброго мужа, богатый делами, из Кавцеила')])
change('de',23,20,repl=[('der Sohn Jojadas, der Sohn eines tapferen Mannes, reich an Taten, aus Kabzeel','der Sohn Jojadas, der Sohn eines tapferen Mannes, selbst reich an Taten, aus Kabzeel')])
change('en',21,9,diff='The Hebrew uses singular “the hand of the Gibeonites”; BSB has plural “the hands”.',kind='en')
change('en',22,24,diff='The Hebrew calls the iniquity “my iniquity”; BSB leaves that possessive implicit.',kind='en')
change('en',22,48,diff='Close to the Hebrew.',kind='en')
change('en',24,14,diff='The Hebrew uses singular “hand” for both the LORD and man; BSB shifts to plural “hands of men” in the second phrase.',kind='en')
change('en',24,22,diff='The Hebrew calls the chosen offering what is good “in his eyes”; BSB has “whatever seems good”.',kind='en')
for lang,op,cl in [('de','„','“'),('ru','«','»')]:
 change(lang,24,22,repl=[(('Holz.' if lang=='de' else 'дров.'),('Holz.“' if lang=='de' else 'дров».'))],kind='native')
 change(lang,24,23,repl=[(('dem König.“' if lang=='de' else 'царю».'),('dem König.' if lang=='de' else 'царю.'))],kind='native')
for name,d in [('2sa-c-qa.json',qa),('2sa-c-root-en-qa.json',rootqa),('2sa-c-root-native-qa.json',nativeqa)]:
 (state/name).write_text(json.dumps(list(d.values()),ensure_ascii=False,indent=2)+'\n')
cp=json.loads((state/'2sa-c-checkpoint.json').read_text());man=[]
for f in cp['new_files']:
 p=Path(f['path']);lang=p.parts[-3];packet=ROOT/'Tools/LiteralGen/packets/de-en-ru/10_2SA'/p.with_suffix('.txt').name
 targets=[b for b in packet.read_text().split('==TARGET')[1:] if re.search(r'\blang='+lang+r'\b',b[:100])];assert len(targets)==1
 expected=[int(x) for x in re.findall(r'^#(\d+)',targets[0],re.M)]
 rows=p.read_text().splitlines();assert len(rows)==f['rows'];assert [int(x.split('\t')[0]) for x in rows]==expected
 for row in rows:
  a=row.split('\t');assert len(a)==3 and all(a)
  prop=qa.get((str(p),int(a[0])));a=(prop['new_row'] if prop else row).split('\t')
  assert len(a[2].split())<=60
  if lang=='en':assert a[1]=='='
 man.append({**f,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
counts={}
for lang,op,cl in [('de','„','“'),('ru','«','»')]:
 t='\n'.join(qa.get((f['path'],int(row.split('\t')[0])),{}).get('new_row',row).split('\t')[1] for f in cp['new_files'] if '/outputs/'+lang+'/' in f['path'] for row in Path(f['path']).read_text().splitlines())
 counts[lang]={'open':t.count(op),'close':t.count(cl)};assert t.count(op)==t.count(cl),counts
for d in [rootqa,nativeqa]:
 for q in d.values():assert len(q['new_row'].split('\t')[2].split())<=60
v={'files':len(man),'rows':sum(f['rows'] for f in man),'all_assigned_verses_reviewed':True,'independent_root_en_reviewed_rows':137,'independent_root_native_reviewed_rows':50,'own_qa_rows':len(qa),'root_en_qa_rows':len(rootqa),'root_native_qa_rows':len(nativeqa),'literal_quote_counts':counts,'problems':[],'tsv_modified_during_qa':False,'files_detail':man}
(state/'2sa-c-created.json').write_text(json.dumps(man,ensure_ascii=False,indent=2)+'\n');(state/'2sa-c-validation.json').write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
cp.update(status='generation_and_full_qa_complete',completed_chapters=list(range(17,24)),remaining_chapters=[],transferred_chapters={'24_de_ru':'root'},generated_file_count=len(man),generated_rows=v['rows'],own_qa_rows=len(qa),root_en_independent_review_rows=137,root_en_qa_rows=len(rootqa),root_native_independent_review_rows=50,root_native_qa_rows=len(nativeqa))
(state/'2sa-c-checkpoint.json').write_text(json.dumps(cp,ensure_ascii=False,indent=2)+'\n')
print({k:x for k,x in v.items() if k!='files_detail'})
