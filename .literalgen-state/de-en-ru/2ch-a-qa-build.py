from pathlib import Path
import re,json,hashlib
state=Path('.literalgen-state/de-en-ru');own=[];en=[];native=[]
def add(dest,lang,ch,v,lit=None,diff=None,replace=None):
 ps=[p for p in (Path('Tools/LiteralGen/outputs')/lang/'14_2CH').glob(f'*_{ch:03d}*.tsv') if any(r.startswith(str(v)+'\t') for r in p.read_text().splitlines())];assert len(ps)==1
 p=ps[0];old=next(r for r in p.read_text().splitlines() if r.startswith(str(v)+'\t'));f=old.split('\t')
 if replace:lit=f[1].replace(*replace);assert lit!=f[1]
 new='\t'.join([f[0],lit if lit is not None else f[1],diff if diff is not None else f[2]]);assert old!=new
 assert len(new.split('\t'))==3 and len(new.split('\t')[2].split())<=60
 dest.append({'path':str(p),'old_row':old,'new_row':new})
add(own,'de',1,6,lit='Und Salomo ging dort zum bronzenen Altar hinauf, der beim Zelt der Begegnung vor dem HERRN war; und er brachte auf ihm tausend Brandopfer dar.')
add(own,'ru',1,6,lit='И Соломон поднялся там к бронзовому жертвеннику, который был при шатре встречи перед Господом, и вознес на нем тысячу всесожжений.')
add(own,'en',1,13,diff='The Hebrew explicitly says from before the Tent of Meeting; BSB says before the Tent of Meeting.')
add(own,'ru',2,13,replace=('Хирам-Авия,','Хирама-Авия,'))
add(own,'ru',3,10,lit='И он сделал в доме Святого Святых двух херувимов как изваянную работу; и их покрыли золотом.')
add(own,'ru',4,4,replace=('трое','три'))
add(own,'de',5,13,replace=('дем HERRN','dem HERRN')) if False else None
add(own,'de',5,13,replace=('dem HERRN zu loben und zu danken','den HERRN zu loben und ihm zu danken'))
add(own,'ru',6,19,replace=('Господи, мой Бог','Господи, Боже мой'))
add(own,'de',6,32,lit='Und auch wenn der Fremde, der nicht von deinem Volk Israel ist, aus fernem Land um deines großen Namens und deiner starken Hand und deines ausgestreckten Arms willen kommt — und sie kommen und beten zu diesem Haus hin —,')
add(own,'ru',6,32,lit='И также если иноплеменник, который не из Твоего народа Израиля, придет из далекой земли ради Твоего великого имени и Твоей крепкой руки, и Твоей простертой мышцы, — и они придут и будут молиться в направлении этого дома, —')
add(own,'de',6,38,replace=('wohin man sie gefangen geführt hat','wohin man sie gefangen geführt hatte'))
add(own,'de',7,1,replace=('als Salomo zu beten beendet hatte','als Salomo das Beten beendet hatte'))
add(own,'ru',7,10,lit='И в двадцать третий день седьмого месяца он отпустил людей к своим шатрам, радующихся и благих сердцем о благе, которое Господь сделал Давиду и Соломону, и Израилю, Своему народу.')
add(own,'de',8,9,diff='Nah am Hebräischen.')
add(own,'ru',9,1,replace=('с весьма большим войском','с весьма большим сопровождением'),diff='Сопровождение обозначено как многочисленная сила, а не только богатство.')
add(own,'ru',9,15,replace=('шестьсот кованого золота','шестьсот весовых единиц кованого золота'))
add(own,'ru',9,16,replace=('триста золота','триста весовых единиц золота'))
# Independent English review of all root chapters 008–012.
add(en,'en',8,6,diff='The Hebrew separately names cities for horsemen and repeats desire and desired; BSB uses cities for horses and whatever he desired.')
add(en,'en',8,16,diff='The Hebrew begins with until the day the foundation was laid and then until completion; BSB begins from that day.')
add(en,'en',9,18,diff='The Hebrew speaks of two lions beside the armrests; BSB distributes one lion beside each armrest.')
add(en,'en',9,23,diff='The Hebrew pictures seeking Solomon’s face; BSB expresses seeking an audience with him.')
add(en,'en',10,6,diff='The Hebrew describes the elders as standing before Solomon; BSB interprets this as serving him.')
add(en,'en',10,16,diff='The Hebrew does not explicitly say Israel saw this. It states there is no inheritance in Jesse’s son, where BSB asks a question. The final movement is to their tents; BSB says they went home.')
add(en,'en',11,18,diff='The Hebrew places Abihail after the lineage through Jerimoth without a joining word; BSB supplies and of to identify Mahalath’s maternal line.')
add(en,'en',11,21,diff='The Hebrew says he took eighteen wives and uses an active fathering verb for his children; BSB says he had wives and was the father of the children.')
add(en,'en',12,7,diff='The Hebrew explicitly mentions Shishak’s hand as the means; BSB says through Shishak.')
# Root native 010–012 independent review.
add(native,'de',10,16,lit='Und weil der König nicht auf ganz Israel gehört hatte, antwortete das Volk dem König mit den Worten: „Welchen Anteil haben wir an David? Und kein Erbe am Sohn Isais! Jeder zu deinen Zelten, Israel! Nun sieh nach deinem Haus, David!“ Und ganz Israel ging zu seinen Zelten.')
add(native,'ru',10,16,lit='И потому что царь не послушал всего Израиля, народ ответил царю так: «Какая нам часть в Давиде? И нет наследия в сыне Иессея! Каждый к твоим шатрам, Израиль! Теперь смотри за твоим домом, Давид!» И ушел весь Израиль к своим шатрам.')
add(native,'ru',11,14,replace=('отвергли их от священства Господу','отстранили их от священнического служения Господу'))
add(native,'de',12,7,diff='Das Hebräische nennt ausdrücklich Sisaks Hand als ausführendes Mittel; Luther sagt nur „durch Sisak“.')
for fn,data in [('2ch-a-qa.json',own),('2ch-a-root-en-qa.json',en),('2ch-a-root-native-qa.json',native)]:
 (state/fn).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n');print(fn,len(data))
cp=json.loads((state/'2ch-a-checkpoint.json').read_text());res=[]
for path in cp['created']:
 p=Path(path);lang=p.parts[3];rows=p.read_text().splitlines();packet=Path('Tools/LiteralGen/packets/de-en-ru/14_2CH')/(p.stem+'.txt');t=next(b for b in packet.read_text().split('==TARGET ')[1:] if b.startswith('lang='+lang+' '));vs=re.findall(r'^#(\d+) ',t,re.M);assert [r.split('\t')[0] for r in rows]==vs
 for r in rows:
  f=r.split('\t');assert len(f)==3 and len(f[2].split())<=60 and (lang!='en' or f[1]=='=')
 res.append({'path':path,'rows':len(rows),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(state/'2ch-a-validation.json').write_text(json.dumps({'files':res,'rows':sum(x['rows'] for x in res),'own_qa':len(own),'root_en_reviewed_rows':107,'root_en_qa':len(en),'root_native_reviewed_rows':116,'root_native_qa':len(native)},ensure_ascii=False,indent=2)+'\n')
cp['status']='generation and complete assigned QA finished';cp['native_chapters']=[1,2,3,4,5,6,7,8,9];cp['english_chapters']=[1,2,3,4,5,6,7];cp['delegated_to_root_native']=[10,11,12];(state/'2ch-a-checkpoint.json').write_text(json.dumps(cp,ensure_ascii=False,indent=2)+'\n');print('validated',len(res),sum(x['rows'] for x in res))
