from pathlib import Path
import json,re,hashlib
base=Path('Tools/LiteralGen/outputs');state=Path('.literalgen-state/de-en-ru');own=[];cross=[]
def add(dest,lang,ch,v,literal=None,diff=None):
 ps=[p for p in (base/lang/'13_1CH').glob(f'1CH_{ch:03d}*.tsv') if any(x.startswith(str(v)+'\t') for x in p.read_text().splitlines())];assert len(ps)==1
 p=ps[0];old=next(x for x in p.read_text().splitlines() if x.startswith(str(v)+'\t')); f=old.split('\t');new='\t'.join([f[0],literal if literal is not None else f[1],diff if diff is not None else f[2]])
 assert old!=new and len(new.split('\t'))==3 and len(new.split('\t')[2].split())<=60
 dest.append({'path':str(p),'old_row':old,'new_row':new})
# Newly produced native language review.
add(own,'ru',3,17,diff='Слово «Асир» передано как обозначение пленника, а не как отдельное имя.')
add(own,'de',4,19,literal='Und die Söhne der Frau Hodijas, der Schwester Nahams: der Vater Kegilas, des Garmiters, und von Esthemoa, dem Maachathiter.')
add(own,'ru',4,19,literal='И сыновья жены Годии, сестры Нахама: отец Кеилы Гармиянина и Ешфемоа Маахатянина.',diff='Годия относится к мужу женщины; далее названы Кеила Гармиянин и Ешфемоа Маахатянин.')
# Clarify a supplement without implying unsupported transmission claims.
add(own,'ru',6,28,diff='В данном еврейском словесном ряду имя Иоиля не выражено; Вашни передано как имя первенца.')
for v in [58,59,60,64,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81]:
 add(own,'ru',6,v,diff='Еврейское обозначение передано как пастбищные угодья вместо городских предместий.')
# Own EN001–003 compare complete packets.
add(own,'en',1,11,diff='The Hebrew uses an active fathering verb; BSB says “was the father of.”')
add(own,'en',2,3,diff='The Hebrew says the daughter of Shua the Canaanite; BSB treats Bath-shua as a personal name. It coordinates Er’s wickedness and his death rather than using a relative clause for the LORD.')
# Root EN004–006 independent full review.
add(cross,'en',4,22,diff='The Hebrew says the words or matters are ancient; BSB describes these names as coming from ancient records.')
for v in range(4,15):
 diff='The Hebrew twice uses an active fathering verb; BSB twice says “was the father of.”'
 if v==10:diff='The Hebrew uses an active fathering verb and calls the building the house; BSB says “was the father of” and specifies the temple.'
 add(cross,'en',6,v,diff=diff)
for fn,data in [('1ch-a-qa.json',own),('1ch-a-root-en-qa.json',cross)]:
 (state/fn).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
 print(fn,len(data))
# Validate every assigned row and preserve exact creation inventory.
cp=json.loads((state/'1ch-a-checkpoint.json').read_text()); result=[]
for path in cp['created']:
 p=Path(path);lang=p.parts[3];rows=p.read_text().splitlines();packet=Path('Tools/LiteralGen/packets/de-en-ru/13_1CH')/(p.stem+'.txt');t=next(x for x in packet.read_text().split('==TARGET ')[1:] if x.startswith('lang='+lang+' '));vs=re.findall(r'^#(\d+) ',t,re.M)
 assert [r.split('\t')[0] for r in rows]==vs
 for r in rows:
  f=r.split('\t');assert len(f)==3 and len(f[2].split())<=60 and (lang!='en' or f[1]=='=')
 result.append({'path':path,'rows':len(rows),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(state/'1ch-a-validation.json').write_text(json.dumps({'files':result,'rows':sum(x['rows'] for x in result),'own_qa':len(own),'root_en_reviewed_rows':150,'root_en_qa':len(cross)},ensure_ascii=False,indent=2)+'\n')
cp['status']='assigned generation and full QA complete';cp['qa_file']='1ch-a-qa.json';cp['root_en_qa_file']='1ch-a-root-en-qa.json';(state/'1ch-a-checkpoint.json').write_text(json.dumps(cp,ensure_ascii=False,indent=2)+'\n')
print('validated',len(result),sum(x['rows'] for x in result))
