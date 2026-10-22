# -*- coding: utf-8 -*-
from pathlib import Path
import json
b=Path('.literalgen-state/de-en-ru');qa=[];cross=[];native=[]
def add(arr,lang,ch,v,lit=None,diff=None,repl=None):
 for p in sorted(Path(f'Tools/LiteralGen/outputs/{lang}/10_2SA').glob(f'2SA_{ch:03}*.tsv')):
  found=[r for r in p.read_text().splitlines() if r.startswith(str(v)+'\t')]
  if found:
   old=found[0];f=old.split('\t')
   if lit is not None:f[1]=lit
   if diff is not None:f[2]=diff
   if repl:
    for a,z in repl:
     assert a in f[1] or a in f[2],(lang,ch,v,a)
     f=[x.replace(a,z) for x in f]
   new='\t'.join(f);assert old!=new
   arr.append(dict(path=str(p),verse=v,old_row=old,new_row=new));return
 raise ValueError((lang,ch,v))
add(qa,'ru',1,12,repl=[('И они оплакивали и плакали','И они рыдали и плакали')],diff='Названы рыдание и плач.')
add(qa,'de',1,18,lit='Und er sagte, man solle die Söhne Judas den Bogen lehren; siehe, es ist im Buch der Redlichen geschrieben:')
add(qa,'ru',1,18,lit='И он сказал, чтобы сынов Иуды научили луку; вот, это написано в книге Праведного:')
add(qa,'ru',2,22,repl=[('Зачем мне поразить тебя на землю?','Зачем мне повергнуть тебя на землю?')])
add(qa,'de',3,28,lit='Und David hörte es danach und sagte: „Ich und mein Königtum sind vor dem HERRN für immer unschuldig am Blut Abners, des Sohnes Ners.')
add(qa,'ru',3,28,lit='И Давид услышал после этого и сказал: «Я и моё царство невинны перед Господом навеки в крови Авенира, сына Нира.')
add(qa,'de',5,8,repl=[('Ein Blinder und ein Lahmer wird','Ein Blinder und ein Lahmer werden')])
add(qa,'ru',5,8,repl=[('Слепой и хромой не войдёт','Слепой и хромой не войдут')])
add(qa,'ru',7,8,repl=[('чтобы быть правителем','чтобы ты был правителем')])
add(qa,'ru',7,21,repl=[('чтобы дать узнать Твоему рабу','чтобы дать Твоему рабу это узнать')])
add(cross,'en',5,12,diff='Close to the Hebrew.')
add(cross,'en',7,7,diff='The Hebrew says “tribes of Israel”; BSB uses “leaders.”')
add(native,'de',8,5,repl=[('schlug unter Syrien','schlug unter den Syrern')])
add(native,'ru',8,5,repl=[('поразил среди Сирии','поразил среди сирийцев')])
add(native,'de',8,13,repl=[('achtzehntausend.','achtzehntausend Mann.')])
add(native,'ru',8,13,repl=[('Соли, восемнадцати тысяч.','Соли — восемнадцати тысяч человек.')])
for arr in (qa,cross,native):
 assert len({(q['path'],q['verse']) for q in arr})==len(arr)
 for q in arr:
  assert len(q['new_row'].split('\t'))==3 and len(q['new_row'].split('\t')[2].split())<=60
for name,arr in [('qa',qa),('root-en-qa',cross),('root-native-qa',native)]:
 (b/f'2sa-a-{name}.json').write_text(json.dumps(arr,ensure_ascii=False,indent=2)+'\n')
print('own',len(qa),'EN',len(cross),'native',len(native))
add(qa,'de',6,6,repl=[('Usa streckte sich zur Lade Gottes aus','Usa streckte seine Hand zur Lade Gottes aus')])
add(qa,'ru',6,6,repl=[('Оза простёрся к ковчегу Бога','Оза протянул руку к ковчегу Бога')])
(b/'2sa-a-qa.json').write_text(json.dumps(qa,ensure_ascii=False,indent=2)+'\n')
print('own final',len(qa))
