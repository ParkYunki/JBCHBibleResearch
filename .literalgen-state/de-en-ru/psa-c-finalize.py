from pathlib import Path
import json,re,collections,hashlib
s=Path('.literalgen-state/de-en-ru');qpath=s/'psa-c-qa.json';q=json.loads(qpath.read_text())
def add(lang,ch,v,literal=None,diff=None):
 found=[]
 for p in Path(f'Tools/LiteralGen/outputs/{lang}/19_PSA').glob(f'PSA_{ch:03d}*.tsv'):
  for row in p.read_text().splitlines():
   a=row.split('\t')
   if a[0]==str(v):found.append((p,row,a))
 assert len(found)==1
 p,old,a=found[0]
 if literal is not None:a[1]=literal
 if diff is not None:a[2]=diff
 new='\t'.join(a)
 if old!=new and not any(x['path']==str(p.resolve()) and x['old_row']==old for x in q):q.append({'path':str(p.resolve()),'old_row':old,'new_row':new})
add('ru',108,1,diff='Твёрдость сердца названа один раз; также названа слава моя.')
add('de',110,6,'Er wird unter den Völkern richten, mit Leichen füllen; er hat ein Haupt über weitem Land zerschmettert.')
add('ru',110,6,'Он будет судить среди народов, наполнит трупами, сокрушил голову над обширной землёй.')
add('ru',109,21,'А Ты, Господи, Господи, сотвори со мною ради имени Твоего, ибо блага милость Твоя, избавь меня!', 'Близко к еврейскому.')
add('ru',106,47,'Спаси нас, Господи, Боже наш, и собери нас из народов, чтобы воздавать благодарение имени святости Твоей, хвалиться хвалою Твоею!')
add('de',106,3,'Glücklich sind die, die das Recht bewahren; glücklich, wer zu jeder Zeit Gerechtigkeit tut!')
add('ru',106,3,'Блаженны хранящие суд; блажен творящий правду во всякое время!')
add('de',119,103,'Wie süß ist dein Spruch meinem Gaumen, süßer als Honig meinem Mund!')
add('de',119,91,'Nach deinen Gerichten stehen sie heute, denn alle sind deine Knechte.')
qpath.write_text(json.dumps(q,ensure_ascii=False,indent=2)+'\n')
cp=s/'psa-c-checkpoint.json';state=json.loads(cp.read_text());paths=[Path(x) for x in state['created']];assert len(paths)==len(set(paths))==150
counts=collections.Counter();quotes={l:collections.Counter() for l in ['de','en','ru']};hashes={};bychapter=collections.Counter()
for p in paths:
 lang=p.parts[-3];a=[x.split('\t') for x in p.read_text().splitlines()];assert all(len(x)==3 for x in a)
 packet=Path('Tools/LiteralGen/packets/de-en-ru/19_PSA')/(p.stem+'.txt');b=packet.read_text().split('==TARGET ');t=next(x for x in b[1:] if x.startswith('lang='+lang+' '));ids=re.findall(r'^#(\d+) ',t,re.M);assert [x[0] for x in a]==ids
 for v,lit,diff in a:
  assert len(diff.split())<=60 and lit and diff
  if lang=='en':assert lit=='='
  for c in ('„','“','‚','‘') if lang=='de' else ('«','»','„','“') if lang=='ru' else ('“','”'):quotes[lang][c]+=lit.count(c)
 counts[lang]+=len(a);bychapter[int(p.stem.split('_')[1])]+=len(a);hashes[str(p.resolve())]=hashlib.sha256(p.read_bytes()).hexdigest()
assert dict(counts)=={'de':845,'ru':845,'en':845}
for x in q:
 assert x['old_row'] in Path(x['path']).read_text().splitlines()
 assert len(x['new_row'].split('\t'))==3 and len(x['new_row'].split('\t')[2].split())<=60
state.update(status='assigned_complete',chapters=sorted(set(state['chapters'])),files=len(paths),rows=sum(counts.values()),verses_per_language=dict(counts),qa_candidates=len(q),assignment_101_120={'files':90,'rows':1704,'verses_per_language':568})
cp.write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n');(s/'psa-c-created.json').write_text(json.dumps(state['created'],indent=2)+'\n');(s/'psa-c-final-hashes.json').write_text(json.dumps(hashes,indent=2)+'\n')
result={'files':len(paths),'rows':sum(counts.values()),'counts':dict(counts),'quote_counts':{l:dict(n)for l,n in quotes.items()},'qa_candidates':len(q),'ids_match':True,'three_fields':True,'diff_limit':True,'english_equals':True}
(s/'psa-c-validation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps(result,ensure_ascii=False))
