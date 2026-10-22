# -*- coding: utf-8 -*-
from pathlib import Path
import json
qa=[]
def q(lang,ch,v,literal=None,diff=None):
 p=next(p for p in Path(f'Tools/LiteralGen/outputs/{lang}/07_JDG').glob(f'JDG_{ch:03d}*.tsv') if any(x.startswith(str(v)+'\t') for x in p.read_text().splitlines()))
 old=next(x for x in p.read_text().splitlines() if x.startswith(str(v)+'\t'));f=old.split('\t')
 if literal is not None:f[1]=literal
 if diff is not None:f[2]=diff
 new='\t'.join(f);assert new!=old;qa.append({'path':str(p),'verse':v,'old_row':old,'new_row':new})
q('ru',3,16,literal='И Аод сделал себе меч, и у него было двое уст, его длина составляла локоть; и он припоясал его под своими одеждами к своему правому бедру.')
q('de',4,11,literal='Und Heber, der Keniter, hatte sich von dem Keniter getrennt, von den Söhnen Hobabs, des Schwiegervaters Moses, und sein Zelt bis zur Eiche in Zaanannim aufgeschlagen, die bei Kedes liegt.')
q('ru',4,11,literal='И Хевер, кенеянин, отделился от кенеянина, от сынов Ховава, тестя Моисея, и раскинул свой шатёр до дуба в Цаанниме возле Кедеса.')
q('ru',4,9,diff='В еврейском тексте нет отдельного «знай»; Господь продаст Сисару. Рука женщины стоит в единственном числе.')
q('de',5,7,literal='Die Landbewohner blieben aus in Israel, sie blieben aus, bis ich, Debora, aufstand, bis ich aufstand, eine Mutter in Israel.')
q('ru',5,7,literal='Не стало сельских жителей в Израиле, не стало, пока не встала я, Девора, пока не встала я, мать в Израиле.')
q('de',5,13,literal='Damals zog das übriggebliebene Volk zu den Edlen hinab; der HERR zog für mich unter den Helden hinab.')
q('ru',5,13,literal='Тогда остаток народа спустился к знатным; Господь спустился для меня среди могучих.')
q('de',6,7,literal='Und es geschah, als die Söhne Israels wegen Midians zum HERRN schrien,',diff='Die Söhne Israels werden ausdrücklich genannt.') if False else None
Path('.literalgen-state/de-en-ru/jdg-a-qa.json').write_text(json.dumps(qa,ensure_ascii=False,indent=2)+'\n')
# Independent QA of root English 004–007.
rootqa=[]
def e(ch,v,diff):
 p=next(p for p in Path('Tools/LiteralGen/outputs/en/07_JDG').glob(f'JDG_{ch:03d}*.tsv') if any(x.startswith(str(v)+'\t') for x in p.read_text().splitlines()));old=next(x for x in p.read_text().splitlines() if x.startswith(str(v)+'\t'));f=old.split('\t');f[2]=diff;rootqa.append({'path':str(p),'verse':v,'old_row':old,'new_row':'\t'.join(f)})
e(5,8,'The Hebrew uses a singular choosing verb with an unnamed subject; BSB has plural “they.”')
e(6,8,'The Hebrew explicitly names the LORD as sender and separately says He brought them up and brought them out; BSB begins with “He” and combines the two actions into “brought you up out.”')
Path('.literalgen-state/de-en-ru/jdg-a-root-en-qa.json').write_text(json.dumps(rootqa,ensure_ascii=False,indent=2)+'\n')
print('A QA',len(qa),'root EN QA',len(rootqa))
