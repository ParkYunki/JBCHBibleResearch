from pathlib import Path
import json,re,collections,hashlib
s=Path('.literalgen-state/de-en-ru');qp=s/'pro-c-qa.json';qa=json.loads(qp.read_text())
def add(lang,ch,v,lit=None,diff=None):
 rows=[]
 for p in Path(f'Tools/LiteralGen/outputs/{lang}/20_PRO').glob(f'PRO_{ch:03d}*.tsv'):
  for old in p.read_text().splitlines():
   a=old.split('\t')
   if a[0]==str(v):rows.append((p,old,a))
 assert len(rows)==1
 p,old,a=rows[0]
 if lit is not None:a[1]=lit
 if diff is not None:a[2]=diff
 new='\t'.join(a)
 if new!=old and not any(x['path']==str(p.resolve()) and x['old_row']==old for x in qa):qa.append({'path':str(p.resolve()),'old_row':old,'new_row':new})
add('de',23,15,'Mein Sohn, wenn dein Herz weise geworden ist, wird mein Herz sich freuen, auch ich werde mich freuen.')
add('ru',23,15,'Сын мой, если сердце твое стало мудрым, возрадуется сердце мое, и я возрадуюсь.')
add('de',25,15,'Durch Langsamkeit zum Zorn wird ein Anführer überredet, und eine weiche Zunge wird einen Knochen zerbrechen.')
add('de',25,20,'Einer, der am kalten Tag ein Kleid ablegt, Essig auf Natron und einer, der Lieder über einem bösen Herzen singt.')
add('de',25,23,'Nordwind gebiert Regen, und eine verborgene Zunge zürnende Gesichter.')
add('ru',25,23,'Северный ветер рождает дождь, и тайный язык — негодующие лица.')
add('de',26,6,'Füße schneidet ab und Gewalttat trinkt, wer Worte durch die Hand eines Toren sendet.')
add('de',26,8,'Wie einer, der einen Stein in eine Schleuder bindet, so ist, wer einem Toren Ehre gibt.')
add('de',28,13,'Wer seine Vergehen bedeckt, wird keinen Erfolg haben; wer bekennt und verlässt, dem wird Erbarmen zuteilwerden.')
add('de',29,11,'Seinen ganzen Geist lässt ein Tor heraus, aber ein Weiser hält ihn beruhigend zurück.')
add('ru',29,11,'Весь дух свой выпускает глупый, а мудрый унимает его, удерживая назад.')
add('de',29,18,'Wo keine Schau ist, wird ein Volk zügellos, aber wer das Gesetz bewahrt, glücklich ist er!', 'Genannt ist eine Schau.')
add('de',30,3,'Und ich habe Weisheit nicht gelernt, und Erkenntnis der Heiligen kenne ich.', 'Der zweite Satz sagt positiv, dass ich Erkenntnis der Heiligen kenne; Heilige steht im Plural.')
add('ru',30,3,'И я не учился мудрости, и знание святых я знаю.', 'Второе высказывание положительное: знание святых я знаю.')
add('de',31,4,'Nicht für Könige, Lamuel, nicht für Könige ist es, Wein zu trinken, und für Fürsten: „Wo ist Rauschtrank?“')
add('de',31,8,'Öffne deinen Mund für den Stummen, für das Recht aller Söhne des Dahinschwindens!', 'Der Stumme steht im Singular; Söhne des Dahinschwindens bleibt als Bild erhalten.')
add('ru',31,8,'Открой уста твои для немого, для суда всех сынов исчезновения!', 'Сохранён образ сынов исчезновения вместо сирот.')
qp.write_text(json.dumps(qa,ensure_ascii=False,indent=2)+'\n')
q=s/'pro-c-checkpoint.json';state=json.loads(q.read_text());paths=[Path(x)for x in state['created']];assert len(paths)==len(set(paths))==42
counts=collections.Counter();quotes={l:collections.Counter()for l in ['de','en','ru']};hashes={}
for p in paths:
 lang=p.parts[-3];a=[x.split('\t')for x in p.read_text().splitlines()];assert all(len(x)==3 for x in a)
 b=(Path('Tools/LiteralGen/packets/de-en-ru/20_PRO')/(p.stem+'.txt')).read_text().split('==TARGET ');t=next(x for x in b[1:]if x.startswith('lang='+lang+' '));ids=re.findall(r'^#(\d+) ',t,re.M);assert [x[0]for x in a]==ids
 for v,lit,diff in a:
  assert lit and diff and len(diff.split())<=60
  if lang=='en':assert lit=='='
  for c in ('„','“','‚','‘')if lang=='de'else('«','»','„','“')if lang=='ru'else('“','”'):quotes[lang][c]+=lit.count(c)
 counts[lang]+=len(a);hashes[str(p.resolve())]=hashlib.sha256(p.read_bytes()).hexdigest()
assert dict(counts)=={'de':331,'ru':331,'en':212}
for x in qa:
 assert x['old_row'] in Path(x['path']).read_text().splitlines()
 assert len(x['new_row'].split('\t'))==3 and len(x['new_row'].split('\t')[2].split())<=60
state.update(status='assigned_complete',chapters=sorted(set(state['chapters'])),files=42,rows=874,verses_per_language=dict(counts),qa_candidates=len(qa),delegation={'21–27':'de,en,ru','28–31':'de,ru; root owns en'})
q.write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n');(s/'pro-c-created.json').write_text(json.dumps(state['created'],indent=2)+'\n');(s/'pro-c-final-hashes.json').write_text(json.dumps(hashes,indent=2)+'\n')
v={'files':42,'rows':874,'counts':dict(counts),'quote_counts':{l:dict(n)for l,n in quotes.items()},'qa_candidates':len(qa),'ids_match':True,'three_fields':True,'diff_limit':True,'english_equals':True};(s/'pro-c-validation.json').write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n');print(json.dumps(v,ensure_ascii=False))
