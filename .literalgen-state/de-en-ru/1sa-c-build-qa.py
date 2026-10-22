from pathlib import Path
import json,hashlib,re
ROOT=Path.cwd(); state=ROOT/'.literalgen-state/de-en-ru'; base=ROOT/'Tools/LiteralGen/outputs'
qa={}; rootqa={}
def change(lang,ch,v,lit=None,diff=None,repl=None,ind=False):
 files=list((base/lang/'09_1SA').glob(f'1SA_{ch:03}*.tsv'))
 found=[(p,row) for p in files for row in p.read_text().splitlines() if row.split('\t')[0]==str(v)]
 assert len(found)==1,(lang,ch,v)
 p,old=found[0]; a=old.split('\t')
 if lit is not None:a[1]=lit
 if diff is not None:a[2]=diff
 if repl:
  for oldtext,newtext in repl:
   assert oldtext in a[1],(lang,ch,v,oldtext)
   a[1]=a[1].replace(oldtext,newtext)
 new='\t'.join(a); assert old!=new
 target=rootqa if ind else qa
 key=(str(p),v); assert key not in target
 target[key]={'path':str(p),'verse':v,'old_row':old,'new_row':new}
change('ru',22,8,repl=[('мой сын заключает с сыном Иессея','мой сын заключает союз с сыном Иессея')])
change('de',22,14,repl=[('deiner Leibwache zugetan','einer, der deinen Befehlen folgt')],diff='Nah am Hebräischen.')
change('ru',22,14,repl=[('следующий твоей страже','исполняющий твои повеления')],diff='Близко к еврейскому.')
change('de',24,6,repl=[('Fern sei es von mir vom HERRN her, dass ich','Der HERR verhüte, dass ich')])
change('ru',24,6,repl=[('Да будет далеко от меня от Господа, чтобы сделать это дело','Да не допустит Господь, чтобы я сделал это дело'),('протянуть мою руку','протянул мою руку')])
change('de',24,11,repl=[('denn indem ich den Flügel deines Mantels abschnitt und dich nicht tötete, erkenne und sieh','denn ich habe den Flügel deines Mantels abgeschnitten und dich nicht getötet. Erkenne und sieh')])
change('ru',24,11,repl=[('ибо, отрезав крыло твоего плаща и не убив тебя, знай и смотри','ибо я отрезал крыло твоего плаща и не убил тебя. Знай и смотри')])
change('en',24,18,diff='The Hebrew says “you have reported”; BSB has “you have shown”.')
change('ru',25,29,repl=[('Он выпращит','Он выбросит')])
change('ru',25,31,repl=[('— пролить кровь напрасно и спасти себя самому.','из-за напрасно пролитой крови и того, что мой господин спас себя сам.')])
change('ru',26,8,repl=[('дай же я поражу его','дай же мне поразить его')])
change('de',26,11,repl=[('Fern sei es von mir vom HERRN her, meine Hand gegen den Gesalbten des HERRN auszustrecken.','Der HERR verhüte, dass ich meine Hand gegen den Gesalbten des HERRN ausstrecke.')])
change('ru',26,11,repl=[('Да будет далеко от меня от Господа протянуть мою руку против помазанника Господа.','Да не допустит Господь, чтобы я протянул мою руку против помазанника Господа.')])
change('de',26,25,repl=[('handeln und gewiss vermögen','handeln und es gewiss vermögen')])
change('de',27,7,lit='Und die Zeit, die David im Gebiet der Philister wohnte, betrug ein Jahr und vier Monate.')
change('ru',27,7,lit='И время, которое Давид жил в области филистимлян, составило год и четыре месяца.')
change('ru',28,8,repl=[('И переоделся Саул','И изменил свой облик Саул')])
change('ru',29,10,repl=[('встань рано утром, и рабы','встань рано утром, ты и рабы')])
change('ru',30,18,repl=[('две свои жены','двух своих жён')])
change('ru',30,19,repl=[('И не недоставало им ничего','И ничего у них не пропало')])
change('en',25,2,diff='The Hebrew lists three thousand sheep before a thousand goats; BSB reverses their order.',ind=True)
change('en',25,16,diff='The Hebrew gives the time pair as “night and day”; BSB has “day and night”.',ind=True)
change('en',25,23,diff='The Hebrew names David twice; BSB uses “him” for the second occurrence.',ind=True)
p=base/'en/09_1SA/1SA_025_2.tsv'; old=next(x for x in p.read_text().splitlines() if x.startswith('37\t'))
diff=old.split('\t')[2]+' It says he became a stone; BSB has “like a stone”.'
change('en',25,37,diff=diff,ind=True)
for name,items in [('1sa-c-qa.json',qa),('1sa-c-root-en-qa.json',rootqa)]:
 (state/name).write_text(json.dumps(list(items.values()),ensure_ascii=False,indent=2)+'\n')
cp=json.loads((state/'1sa-c-checkpoint.json').read_text()); manifests=[]; problems=[]
for f in cp['new_files']:
 p=Path(f['path']);lang=p.parts[-3];packet=ROOT/'Tools/LiteralGen/packets/de-en-ru/09_1SA'/p.with_suffix('.txt').name
 s=packet.read_text(); targets=[b for b in s.split('==TARGET')[1:] if re.search(r'\blang='+lang+r'\b',b[:100])];assert len(targets)==1
 expected=[int(x) for x in re.findall(r'^#(\d+)',targets[0],re.M)]
 rows=p.read_text().splitlines(); assert len(rows)==f['rows'];assert [int(x.split('\t')[0]) for x in rows]==expected
 for row in rows:
  a=row.split('\t'); assert len(a)==3 and all(a)
  proposal=qa.get((str(p),int(a[0]))); a=(proposal['new_row'] if proposal else row).split('\t')
  assert len(a[2].split())<=60,(str(p),a[0],len(a[2].split()))
  if lang=='en':assert a[1]=='='
 manifests.append({**f,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
for q in rootqa.values():assert len(q['new_row'].split('\t')[2].split())<=60
(state/'1sa-c-created.json').write_text(json.dumps(manifests,ensure_ascii=False,indent=2)+'\n')
validation={'files':len(manifests),'rows':sum(x['rows'] for x in manifests),'all_assigned_verses_reviewed':True,'independent_root_en_reviewed_rows':161,'own_qa_rows':len(qa),'independent_root_en_qa_rows':len(rootqa),'problems':problems,'tsv_modified_during_qa':False,'files_detail':manifests}
(state/'1sa-c-validation.json').write_text(json.dumps(validation,ensure_ascii=False,indent=2)+'\n')
cp.update(status='generation_and_full_qa_complete',completed_chapters=list(range(21,32)),remaining_chapters=[],generated_file_count=len(manifests),generated_rows=sum(x['rows'] for x in manifests),own_qa_rows=len(qa),root_en_independent_review_rows=161,root_en_qa_rows=len(rootqa))
(state/'1sa-c-checkpoint.json').write_text(json.dumps(cp,ensure_ascii=False,indent=2)+'\n')
print({k:v for k,v in validation.items() if k!='files_detail'})
