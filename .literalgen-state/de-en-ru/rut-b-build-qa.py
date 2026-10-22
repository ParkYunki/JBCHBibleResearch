from pathlib import Path
import json
qa={}
def put(lang,v,lit=None,diff=None):
 p=Path(f'Tools/LiteralGen/outputs/{lang}/08_RUT/RUT_002.tsv');old=next(r for r in p.read_text().splitlines() if r.split('\t')[0]==str(v));cur=qa.get((str(p),v),{}).get('new_row',old).split('\t')
 if lit is not None:cur[1]=lit
 if diff is not None:cur[2]=diff
 new='\t'.join(cur)
 if new!=old:qa[(str(p),v)]={'path':str(p),'verse':v,'old_row':old,'new_row':new}
put('de',6,lit='Und der junge Mann, der über die Schnitter gestellt war, antwortete und sagte: „Sie ist eine junge Moabitin, die mit Naemi vom Feld Moabs zurückgekehrt ist.')
put('ru',6,lit='И юноша, поставленный над жнецами, ответил и сказал: «Она молодая Моавитянка, возвратившаяся с Ноеминью с поля Моава.',diff='Женщина названа возвратившейся, не просто пришедшей; поле Моава стоит в единственном числе.')
# The feminine helpers retain both youth and their service role naturally.
for l,changes in [('de',{8:('meine jungen Frauen','meine jungen Mägde'),22:('seinen jungen Frauen','seinen jungen Mägden'),23:('die jungen Frauen des Boas','die jungen Mägde des Boas')}),('ru',{8:('моих молодых женщин','моих молодых служанок'),22:('с его молодыми женщинами','с его молодыми служанками'),23:('молодых женщин Вооза','молодых служанок Вооза')})]:
 p=Path(f'Tools/LiteralGen/outputs/{l}/08_RUT/RUT_002.tsv')
 for v,(a,b) in changes.items():
  lit=next(r for r in p.read_text().splitlines() if r.split('\t')[0]==str(v)).split('\t')[1];assert a in lit;put(l,v,lit=lit.replace(a,b))
p=Path('Tools/LiteralGen/outputs/ru/08_RUT/RUT_002.tsv');lit=next(r for r in p.read_text().splitlines() if r.startswith('11\t')).split('\t')[1]
put('ru',11,lit=lit.replace('Мне непременно было рассказано','Мне действительно было рассказано'))
put('ru',18,diff='Имя Руфи и слова «из пазухи своей» в тексте отсутствуют.')
put('ru',22,diff='Действие в другом поле выражено активным глаголом с неназванными действующими лицами.')
put('ru',23,diff='Совместность выражена глаголом «держалась»; подбор указан как цель.')
Path('.literalgen-state/de-en-ru/rut-b-qa.json').write_text(json.dumps(list(qa.values()),ensure_ascii=False,indent=2)+'\n')
Path('.literalgen-state/de-en-ru/rut-b-root-en-qa.json').write_text('[]\n')
print('QA',len(qa))
