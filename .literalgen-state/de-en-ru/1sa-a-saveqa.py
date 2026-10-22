# -*- coding: utf-8 -*-
from pathlib import Path
import json
base=Path('.literalgen-state/de-en-ru')
qa=[]
def add(lang,ch,v,lit=None,diff=None,replace=None):
 for p in sorted(Path(f'Tools/LiteralGen/outputs/{lang}/09_1SA').glob(f'1SA_{ch:03}*.tsv')):
  rows=p.read_text().splitlines()
  found=[r for r in rows if r.startswith(str(v)+'\t')]
  if found:
   old=found[0];f=old.split('\t')
   if lit is not None:f[1]=lit
   if diff is not None:f[2]=diff
   if replace:
    for a,b in replace:
     assert a in f[1] or a in f[2],(lang,ch,v,a)
     f=[x.replace(a,b) for x in f]
   new='\t'.join(f);assert old!=new
   qa.append(dict(path=str(p),verse=v,old_row=old,new_row=new));return
 raise ValueError((lang,ch,v))
add('ru',1,7,replace=[('сетовалa','сетовала')])
add('ru',1,16,replace=[('Твою рабу','твою рабу')])
add('ru',1,18,replace=[('Твоя раба','твоя раба')])
add('ru',1,24,replace=[('И она поднялась с ним','И она привела его с собой наверх')])
add('de',2,4,diff='Das Hebräische nennt Strauchelnde und ein aktives Sich-Umgürten.')
add('ru',2,8,replace=[('с знатными','со знатными')])
add('de',2,29,lit='Warum tretet ihr gegen mein Schlachtopfer und meine Gabe, die ich für die Wohnung geboten habe? Und warum ehrst du deine Söhne mehr als mich, um euch vom Besten aller Gaben Israels, meines Volkes, zu mästen?',diff='Das Hebräische wechselt vom Treten in der Mehrzahl zum Ehren in der Einzahl und kehrt beim Mästen zur Mehrzahl zurück.')
add('ru',2,29,lit='Почему вы пинаете Мою жертву и Моё приношение, которые Я повелел для жилища? И почему ты чтишь твоих сыновей больше Меня, чтобы вам утучнять себя начатком всех приношений Израиля, Моего народа?',diff='Обращение меняется с множественного числа при пинании на единственное при почитании, а утучнение снова относится к нескольким лицам.')
add('de',7,8,lit='Und die Söhne Israels sagten zu Samuel: „Verstumme für uns nicht im Schreien zum HERRN, unserem Gott, damit er uns aus der Hand der Philister rette!“')
add('ru',7,12,diff='Близко к еврейскому.')
add('de',8,12,lit='Und er wird sich Oberste über Tausende und Oberste über Fünfzig einsetzen und sie sein Pflugland pflügen und seine Ernte ernten und seine Kriegsgeräte und die Geräte seines Wagens machen lassen.')
add('ru',8,12,lit='И он поставит себе начальников тысяч и начальников пятидесяти; они будут пахать его пахоту и жать его жатву, и делать орудия его войны и принадлежности его колесницы.')
add('de',9,3,diff='Das Hebräische wiederholt Kis und Saul ausdrücklich und enthält eine Bitte.')
add('ru',9,4,diff='Близко к еврейскому.')
add('ru',9,7,diff='Еврейский текст называет сосуды, а не сумы.')
add('de',9,16,diff='Nah am Hebräischen.')
add('de',9,19,diff='Nah am Hebräischen.')
add('ru',9,19,diff='Близко к еврейскому.')
add('de',9,26,diff='Nah am Hebräischen.')
assert len({(q['path'],q['verse']) for q in qa})==len(qa)
(base/'1sa-a-qa.json').write_text(json.dumps(qa,ensure_ascii=False,indent=2)+'\n')
(base/'1sa-a-root-en-qa.json').write_text('[]\n')
print('QA',len(qa),'root EN QA',0)
add('ru',3,11,lit='И Господь сказал Самуилу: «Вот, Я делаю дело в Израиле, при котором у всякого, кто услышит о нём, зазвенят оба уха.')
add('de',9,7,diff='Das Hebräische nennt Gefäße in der Mehrzahl statt eines Sacks.')
add('de',9,22,replace=[('am Kopf der Geladenen','an der Spitze der Geladenen')])
(base/'1sa-a-qa.json').write_text(json.dumps(qa,ensure_ascii=False,indent=2)+'\n')
print('Final QA',len(qa))
