from pathlib import Path
import json
out=[]
def row(lang,ch,v):
 for p in sorted((Path('Tools/LiteralGen/outputs')/lang/'14_2CH').glob(f'*_{ch:03}*.tsv')):
  for l in p.read_text().splitlines():
   if int(l.split('\t')[0])==v:return p,l
 raise ValueError((lang,ch,v))
def edit(lang,ch,v,changes=None,diff=None):
 p,old=row(lang,ch,v); parts=old.split('\t'); lit=parts[1]
 for a,b in changes or []:
  assert a in lit,(lang,ch,v,a)
  lit=lit.replace(a,b)
 parts[1]=lit
 if diff is not None:parts[2]=diff
 new='\t'.join(parts);assert old!=new and len(parts[2].split())<=60
 out.append(dict(path=str(p),old_row=old,new_row=new))
edit('ru',25,9,[('У Господа есть дать','У Господа есть возможность дать')])
edit('de',26,13,[('dreihundertsiebentausendfünfhundert, die','dreihundertsiebentausendfünfhundert Männern, die')])
edit('de',27,5,[('zehntausend Gerste','zehntausend Maß Gerste')])
edit('ru',27,5,[('десять тысяч ячменя','десять тысяч мер ячменя')])
edit('de',28,23,[('ihm zum Straucheln und ganz Israel','ihm und ganz Israel zum Straucheln')])
edit('ru',29,18,[('стол разложения','стол для раскладывания')], 'Дом очищен весь; стол назван по раскладыванию, без отдельного упоминания хлебов.')
edit('de',30,19,[('und nicht nach der Reinigung des Heiligtums','auch wenn er nicht nach der Reinigung des Heiligtums gereinigt ist')])
edit('de',32,31,[('im Land geschehen war, um ihn zu prüfen','im Land geschehen war, allein, um ihn zu prüfen')])
edit('ru',34,10,[('И дали в руку работников','И дали его в руку работников')])
edit('de',35,6,[('bereitet für eure Brüder vor','trefft Vorbereitungen für eure Brüder')])
edit('ru',35,6,[('приготовьте для братьев ваших','сделайте приготовления для братьев ваших')])
edit('de',35,21,[('Gott hat gesagt, mich zu beeilen','Gott hat gesagt, dass ich mich beeilen soll')])
edit('en',30,3,diff='The Hebrew says “at that time”; BSB says “at the regular time.”')
edit('en',31,4,diff='The Hebrew says that they may be strong in the Law of the LORD; BSB says that they could devote themselves to it.')
edit('en',32,20,diff='The Hebrew separately says that they prayed and cried out to heaven; BSB combines these as “cried out to heaven in prayer.”')
edit('en',33,14,diff='The Hebrew leaves the subject unnamed here; BSB names Manasseh.')
edit('en',34,23,diff='The Hebrew leaves the speaker unnamed here and says “who sent you to me”; BSB names Huldah and omits “to me.”')
edit('en',36,22,diff='The Hebrew says “by the mouth of Jeremiah”; BSB says “spoken through Jeremiah.” It narrates the proclamation as a separate action; BSB connects it with “to send.”')
p=Path('.literalgen-state/de-en-ru/2ch-final-extra-qa.json');p.write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
print(len(out),p)
