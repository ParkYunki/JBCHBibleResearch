from pathlib import Path
import json
qa=[]
def q(lang,ch,v,literal=None,diff=None):
 p=next(p for p in Path(f'Tools/LiteralGen/outputs/{lang}/06_JOS').glob(f'JOS_{ch:03d}*.tsv') if any(x.startswith(str(v)+'\t') for x in p.read_text().splitlines()))
 old=next(x for x in p.read_text().splitlines() if x.startswith(str(v)+'\t')); f=old.split('\t');
 if literal is not None:f[1]=literal
 if diff is not None:f[2]=diff
 new='\t'.join(f); assert old!=new
 qa.append({'path':str(p),'verse':v,'old_row':old,'new_row':new})
q('ru',1,15,literal='пока Господь не даст вашим братьям покоя, как вам, и они также не овладеют землёй, которую Господь, Бог ваш, даёт им; и вы возвратитесь в землю вашего владения, которую Моисей, раб Господа, дал вам за Иорданом к восходу солнца, и овладеете ею».')
q('ru',2,4,diff='После двух мужей стоит местоимение единственного числа «его».')
q('ru',3,17,diff='Начальная фраза перевода о переходе народа относится к предыдущему стиху. «Весь Израиль» не развёрнут в «все сыны Израилевы».')
q('ru',4,18,literal='И было, когда священники, несшие ковчег завета Господа, поднимались из середины Иордана и подошвы ног священников оторвались и оказались на суше, воды Иордана вернулись на своё место и потекли, как прежде, поверх всех его берегов.')
q('ru',9,23,literal='И теперь вы прокляты, и не переведётся у вас раб, а также рубящие дрова и черпающие воду для дома моего Бога».')
q('de',8,2,literal='Und du sollst an Ai und seinem König tun, wie du an Jericho und seinem König getan hast; nur seine Beute und sein Vieh sollt ihr für euch plündern. Lege dir einen Hinterhalt gegen die Stadt hinter ihr!“')
# Keep uncertain lexical alternatives out of difference notes.
q('de',8,15,diff='Das hebräische Verb beschreibt das Geschlagenwerden; ein eigenes Wort für das Vortäuschen fehlt.')
q('ru',8,15,diff='Еврейский текст употребляет глагол поражения; отдельного слова «будто» нет.')
Path('.literalgen-state/de-en-ru/jos-a-qa.json').write_text(json.dumps(qa,ensure_ascii=False,indent=2)+'\n')
print(len(qa))
