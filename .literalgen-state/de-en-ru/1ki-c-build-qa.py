from pathlib import Path
import json,re,hashlib
ROOT=Path.cwd();s=ROOT/'.literalgen-state/de-en-ru';base=ROOT/'Tools/LiteralGen/outputs';qa={};enqa={};nativeqa={}
def change(lang,ch,v,lit=None,diff=None,repl=None,kind='own'):
 found=[(p,r) for p in (base/lang/'11_1KI').glob(f'1KI_{ch:03}*.tsv') for r in p.read_text().splitlines() if r.split('\t')[0]==str(v)];assert len(found)==1
 p,old=found[0];a=old.split('\t')
 if lit is not None:a[1]=lit
 if diff is not None:a[2]=diff
 if repl:
  for x,y in repl:assert x in a[1],(lang,ch,v,x);a[1]=a[1].replace(x,y)
 new='\t'.join(a);assert old!=new
 q={'own':qa,'en':enqa,'native':nativeqa}[kind];key=(str(p),v);assert key not in q
 q[key]={'path':str(p),'verse':v,'old_row':old,'new_row':new}
change('de',16,3,repl=[('werde ich hinter Baesa und hinter seinem Haus ausfegen','werde ich wegfegen, was von Baesa und seinem Haus übrig ist')])
change('ru',16,3,repl=[('Я вымету остаток после Ваасы и после его дома','Я вымету всё, что останется от Ваасы и его дома')],diff='Удаление выражено выметанием остатка Ваасы и его дома.')
change('de',17,15,repl=[('und sie aß, sie und er und ihr Haus','und sie aßen, sie und er und ihr Haus')])
change('ru',18,26,repl=[('который был сделан','который он сделал')])
change('ru',18,34,repl=[('Сделайте втрое','Сделайте в третий раз'),('сделали втрое','сделали в третий раз')])
change('de',18,28,repl=[('bis Blut auf sie ausgegossen wurde','bis Blut über sie strömte')])
change('de',18,39,repl=[('Und alles Volk sah es und fiel auf seine Gesichter und sagte','Und alles Volk sah es, und sie fielen auf ihre Gesichter und sagten')])
change('ru',18,39,repl=[('И весь народ увидел, и пали','И весь народ увидел, и они пали')])
change('de',19,4,repl=[('er bat für seine Seele, zu sterben','er erbat für seine Seele den Tod')])
change('de',20,10,repl=[('zu Handvoll für alles Volk reicht, das zu meinen Füßen ist','zu einer Handvoll für jeden aus dem ganzen Volk reicht, das zu meinen Füßen ist')])
change('de',20,38,repl=[('stellte sich für den König an den Weg','stellte sich an den Weg, um auf den König zu warten')])
change('ru',20,38,repl=[('стал для царя у дороги','стал у дороги, ожидая царя')])
change('de',21,22,repl=[('wegen der Kränkung, mit der du gekränkt und Israel sündigen gemacht hast','wegen des Ärgers, den du erregt hast, und weil du Israel sündigen gemacht hast')])
change('ru',21,22,repl=[('за раздражение, которым ты раздражил и ввёл Израиль в грех','за раздражение, которое ты вызвал, и за то, что ввёл Израиль в грех')])
change('ru',21,19,repl=[('твою кровь, и твою','твою кровь, да, твою')],diff='В конце повторно подчёркнуто, что речь о его собственной крови.')
change('en',22,3,diff='The Hebrew names the king of Israel, asks “Do you know”, and describes remaining silent; BSB uses “who”, “Do you not know”, and “have failed to take it”.',kind='en')
change('de',22,3,diff='Die Frage enthält kein eigenes Nicht; das Zögern wird als Schweigen beschrieben.',kind='native')
change('de',22,6,diff='Nah am Hebräischen.',kind='native')
change('de',22,16,repl=[('Bis wie viele Male muss ich dich beschwören','Wie oft muss ich dich beschwören')],kind='native')
change('ru',22,16,repl=[('До скольких раз мне заклинать тебя','Сколько раз мне ещё заклинать тебя')],kind='native')
change('de',22,22,repl=[('und auch vermögen','und es auch vermögen')],kind='native')
change('ru',22,22,repl=[('Ты обольстишь и также сможешь','Ты обольстишь, и это тебе удастся')],kind='native')
change('de',22,27,repl=[('Wasser der Bedrängnis zu essen','Wasser der Bedrängnis')],kind='native')
change('ru',22,27,repl=[('кормите его хлебом тесноты и водою тесноты','давайте ему хлеб тесноты и воду тесноты')],kind='native')
change('de',22,43,repl=[('doch die Höhen wichen nicht, noch opferte und räucherte das Volk auf den Höhen','doch die Höhen wichen nicht; das Volk opferte und räucherte weiterhin auf den Höhen')],kind='native')
change('ru',22,43,repl=[('ещё народ приносил жертвы','народ ещё приносил жертвы')],kind='native')
for name,d in [('1ki-c-qa.json',qa),('1ki-c-root-en-qa.json',enqa),('1ki-c-root-native-qa.json',nativeqa)]:
 (s/name).write_text(json.dumps(list(d.values()),ensure_ascii=False,indent=2)+'\n')
cp=json.loads((s/'1ki-c-checkpoint.json').read_text());man=[]
for f in cp['new_files']:
 p=Path(f['path']);lang=p.parts[-3];packet=ROOT/'Tools/LiteralGen/packets/de-en-ru/11_1KI'/p.with_suffix('.txt').name
 targets=[b for b in packet.read_text().split('==TARGET')[1:] if re.search(r'\blang='+lang+r'\b',b[:100])];assert len(targets)==1
 expect=[int(x) for x in re.findall(r'^#(\d+)',targets[0],re.M)];rows=p.read_text().splitlines();assert len(rows)==f['rows'];assert [int(x.split('\t')[0]) for x in rows]==expect
 for row in rows:
  a=row.split('\t');assert len(a)==3 and all(a)
  a=qa.get((str(p),int(a[0])),{}).get('new_row',row).split('\t');assert len(a[2].split())<=60
  if lang=='en':assert a[1]=='='
 man.append({**f,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
counts={}
for lang,op,cl in [('de','„','“'),('ru','«','»')]:
 t='\n'.join(qa.get((f['path'],int(row.split('\t')[0])),{}).get('new_row',row).split('\t')[1] for f in cp['new_files'] if '/outputs/'+lang+'/' in f['path'] for row in Path(f['path']).read_text().splitlines())
 counts[lang]={'open':t.count(op),'close':t.count(cl)};assert t.count(op)==t.count(cl),counts
for d in [enqa,nativeqa]:
 for q in d.values():assert len(q['new_row'].split('\t')[2].split())<=60
v={'files':len(man),'rows':sum(f['rows'] for f in man),'all_assigned_verses_reviewed':True,'independent_root_en_reviewed_rows':146,'independent_root_native_reviewed_rows':106,'own_qa_rows':len(qa),'root_en_qa_rows':len(enqa),'root_native_qa_rows':len(nativeqa),'literal_quote_counts':counts,'problems':[],'tsv_modified_during_qa':False,'files_detail':man}
(s/'1ki-c-created.json').write_text(json.dumps(man,ensure_ascii=False,indent=2)+'\n');(s/'1ki-c-validation.json').write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
cp.update(status='generation_and_full_qa_complete',completed_chapters=list(range(15,22)),remaining_chapters=[],transferred_chapters={'22_de_ru':'root'},generated_file_count=len(man),generated_rows=v['rows'],own_qa_rows=len(qa),root_en_independent_review_rows=146,root_en_qa_rows=len(enqa),root_native_independent_review_rows=106,root_native_qa_rows=len(nativeqa))
(s/'1ki-c-checkpoint.json').write_text(json.dumps(cp,ensure_ascii=False,indent=2)+'\n');print({k:x for k,x in v.items() if k!='files_detail'})
