from pathlib import Path
import json,re
state=Path('.literalgen-state/de-en-ru')
created=json.loads((state/'2ki-b-created.json').read_text())
changes={}
def change(lang,ch,v,repls=None,lit=None,diff=None):
 paths=list(Path(f'Tools/LiteralGen/outputs/{lang}/12_2KI').glob(f'2KI_{ch:03d}*.tsv'))
 matches=[(p,r) for p in paths for r in p.read_text().splitlines() if r.split('\t')[0]==str(v)]
 assert len(matches)==1,(lang,ch,v)
 p,old=matches[0];key=(str(p),v)
 row=changes.get(key,{'old_row':old,'new_row':old})['new_row'];a=row.split('\t')
 if repls:
  for before,after in repls:
   assert before in a[1],(key,before)
   a[1]=a[1].replace(before,after)
 if lit is not None:a[1]=lit
 if diff is not None:a[2]=diff
 new='\t'.join(a)
 if old!=new:changes[key]={'path':str(p),'verse':v,'old_row':old,'new_row':new}
# German possessives, combining exact candidates per verse.
for path in created:
 p=Path(path)
 if '/de/' not in path:continue
 ch=int(p.name[4:7])
 for row in p.read_text().splitlines():
  v,lit,diff=row.split('\t');v=int(v);new=lit
  new=new.replace('Haus Ahab','Haus Ahabs')
  for head in ['Jahr','Sohnes','Angelegenheiten','Tage','Tod']:
   new=re.sub(r'\b'+head+r' (Joas|Joahas)\b',head+r' des \1',new)
  new=re.sub(r'\b(der|dem|den) Sohn (Joas|Joahas)\b',r'\1 Sohn des \2',new)
  if ch==12 and v==19:continue # root already queued
  if new!=lit:change('de',ch,v,lit=new)
change('de',9,3,[('gieße ihn','gieße Öl')])
change('ru',9,3,[('вылей на','вылей масло на')])
change('de',9,31,[('Ist Friede, Simri, der seinen Herrn getötet hat?', 'Ist Friede, Simri, du Mörder deines Herrn?')])
change('ru',9,34,[('Посмотрите же за этой проклятой','Позаботьтесь же об этой проклятой')])
change('ru',10,9,diff='В конце стоит глагол поражения.')
change('ru',10,23,[('нет ли здесь с вами кого из рабов Господа, а только служители Ваала', 'чтобы здесь с вами не было никого из рабов Господа, а были только служители Ваала')])
change('de',10,30,[('werden Söhne bis zur vierten Generation dir','werden dir Söhne bis zur vierten Generation')])
# Native minimal completion of source ellipsis.
change('de',11,2,[(', ihn und seine Amme in die Bettenkammer',', und verbarg ihn und seine Amme in der Bettenkammer')])
change('ru',11,2,[(', его и его кормилицу в комнату постелей',' и скрыла его и его кормилицу в спальне')])
change('de',11,6,diff='Die Läufer sind ausdrücklich genannt.')
change('de',11,12,[('gab die Krone und das Zeugnis auf ihn','legte ihm die Krone und das Zeugnis auf')])
change('ru',12,5,[('укрепят повреждение','устранят повреждение')])
change('ru',12,6,[('укрепили повреждение','устранили повреждение')])
change('ru',12,7,[('укрепляете повреждение','устраняете повреждение'),('отдайте его на повреждение дома','отдайте его на устранение повреждения дома')])
change('ru',12,8,[('укреплять повреждение','устранять повреждение')])
change('ru',12,10,[('великий священник','первосвященник')])
change('ru',12,12,[('укрепить повреждение','устранить повреждение')])
change('ru',12,15,[('не считались с людьми','не требовали отчёта от людей')],diff='Сохранены рука и отсутствие требования отчёта.')
change('ru',12,16,[('Серебро вины и серебро грехов','Серебро за вину и серебро за грехи')])
change('de',12,20,[('verschworen eine Verschwörung','schmiedeten eine Verschwörung')],diff='Joas ist ausdrücklich genannt.')
change('ru',14,26,diff='Бедствие названо весьма горьким; дважды прямо выражено отсутствие людей.')
# Correct reflexive antecedent: the people bury him with HIS fathers.
change('ru',15,7,[('похоронили его с отцами своими','похоронили его с его отцами')])
change('ru',15,12,[('будут сидеть тебе','будут сидеть для тебя')])
# Native noun phrase, without forcing the uncommon idiom.
change('ru',15,13,[('месяц дней','полный месяц')],diff='Близко к еврейскому.')
change('de',10,32,[('an Israel abzuschneiden','Teile von Israel abzuschneiden')])
change('ru',10,32,[('отсекать у Израиля','отсекать части от Израиля')])
change('ru',11,3,[('был он с нею в доме Господа скрывающимся шесть лет','скрывался он с нею в доме Господа шесть лет')])
change('ru',11,5,[('хранить стражу','нести стражу')])
change('ru',11,6,[('храните стражу дома для отвращения нападения','несите стражу дома для охраны')])
change('ru',11,7,[('хранят стражу','несут стражу')])
change('ru',11,17,[('чтобы быть народом','чтобы они были народом')])
change('de',9,31,diff='Simri ist direkt angeredet.')
change('de',13,22,diff='Genannt sind alle Tage des Joahas, ohne eigenes Verb leben.')
change('de',13,25,diff='Der Sohn des Joahas ist ausdrücklich genannt.')
change('de',16,19,[('Angelegenheiten Ahas','Angelegenheiten des Ahas')])
change('ru',16,15,diff='Возлияния имеют множественное число.')
qa=list(changes.values())
(state/'2ki-b-qa.json').write_text(json.dumps(qa,ensure_ascii=False,indent=2))
print('own candidates',len(qa))
