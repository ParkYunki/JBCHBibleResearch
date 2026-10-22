from pathlib import Path
import json
base=Path('Tools/LiteralGen/outputs');qa={}
def put(lang,ch,v,lit=None,diff=None):
 ps=[p for p in (base/lang/'07_JDG').glob(f'JDG_{ch:03d}*.tsv') if any(r.split('\t')[0]==str(v) for r in p.read_text().splitlines())];assert len(ps)==1
 p=ps[0];old=next(r for r in p.read_text().splitlines() if r.split('\t')[0]==str(v));key=(str(p),v);cur=qa.get(key,{}).get('new_row',old).split('\t')
 if lit is not None:cur[1]=lit
 if diff is not None:cur[2]=diff
 new='\t'.join(cur)
 if new!=old:qa[key]={'path':str(p),'verse':v,'old_row':old,'new_row':new}
put('de',8,13,diff='Die Zielübersetzung ergänzt „ehe“; die hebräische Wendung beginnt mit „von“.')
put('de',8,18,diff='„Schön“ steht nicht ausdrücklich im Text; der Vergleich nennt Königssöhne, nicht allgemein Kinder.')
put('en',8,18,diff='The Hebrew has plural “sons of the king”; BSB has singular “the son of a king”.')
put('ru',8,18,diff='Близко к еврейскому.')
put('ru',8,16,lit='И он взял старейшин города и тернии пустыни и колючки и ими преподал урок мужам Сокхофа.',diff='Употреблён глагол со значением дать познать, а не общее обозначение наказания.')
put('ru',8,24,lit='И Гедеон сказал им: «Я обращусь к вам с одной просьбой: дайте мне каждый по серьге из своей добычи». Ибо у них были золотые серьги, ибо они были Измаильтянами.')
put('de',8,26,lit='Und das Gewicht der goldenen Ringe, die er erbeten hatte, war tausendsiebenhundert [Gewichtseinheiten] Gold, außer den Halbmonden und den Anhängern und den Purpurgewändern, die die Könige Midians trugen, und außer den Halsketten an den Hälsen ihrer Kamele.')
put('ru',8,26,lit='И вес золотых серёг, которые он попросил, был тысяча семьсот [весовых единиц] золота, кроме полумесяцев и подвесок и пурпуровых одежд, которые были на царях Мадиама, и кроме ожерелий, которые были на шеях их верблюдов.')
put('de',9,4,lit='Und sie gaben ihm siebzig [Gewichtseinheiten] Silber aus dem Haus Baal-Beriths; und Abimelech warb damit nichtige und leichtfertige Männer an, und sie folgten ihm.')
put('ru',9,6,diff='Дуб назван находящимся в Сихеме, не просто близ него.')
put('de',9,9,diff='Nah am Hebräischen.')
put('en',9,9,diff='The Hebrew describes going to sway over the trees; BSB uses the idiom “hold sway over the trees”.')
put('ru',9,13,lit='И виноградная лоза сказала им: „Оставлю ли я своё молодое вино, веселящее богов и людей, и пойду ли качаться над деревьями?“',diff='Сохраняется образ качания над деревьями.')
put('ru',9,17,lit='ибо мой отец сражался за вас и отбросил от себя свою душу и избавил вас из руки Мадиама;')
put('ru',9,24,diff='Сначала названы насилие и возложение крови; руки укреплены для убийства его братьев.')
put('ru',9,27,lit='И они вышли в поле и собрали виноград своих виноградников и топтали его и устроили празднества и вошли в дом своего бога и ели и пили и проклинали Авимелеха.')
put('ru',9,48,lit='И Авимелех поднялся на гору Селмон, он и весь народ, который с ним; и Авимелех взял топоры в свою руку и срубил ветвь с деревьев и поднял её и положил на своё плечо; и сказал народу, который с ним: «Что вы видели, как я сделал, поспешите сделать так же!»')
put('ru',11,1,lit='И Иеффай, Галаадитянин, был могучим воином; и он был сыном женщины-блудницы, и Галаад породил Иеффая.',diff='В конце Галаад активно назван породившим Иеффая, а не Иеффай — родившимся от него.')
put('de',11,19,lit='Und Israel sandte Boten zu Sihon, dem König des Amoriters, dem König von Hesbon; und Israel sagte zu ihm: ‚Lass uns doch durch dein Land ziehen bis zu meinem Ort.‘')
put('ru',11,35,lit='И было, когда он увидел её, он разодрал свои одежды и сказал: «Ах, моя дочь! Ты совсем согнула меня, и ты среди тех, кто приводит меня в смятение; а я открыл свои уста к Господу и не могу повернуть назад».')
put('ru',12,4,lit='И Иеффай собрал всех мужей Галаада и сразился с Ефремом; и мужи Галаада поразили Ефрема, ибо говорили: «Вы, Галаадитяне, беглецы Ефрема, среди Ефрема, среди Манассии».',diff='Бойцы названы мужами, а Ефрем — собирательным именем. Слово «среди» повторено при Ефреме и Манассии.')
put('ru',13,24,diff='Мальчик назван словом, более общим по возрасту, чем «младенец».')
put('ru',14,3,lit='И его отец и его мать сказали ему: «Разве нет женщины среди дочерей твоих братьев и во всём моём народе, что ты идёшь взять жену из необрезанных Филистимлян?» И Самсон сказал своему отцу: «Её возьми мне, ибо она угодна моим глазам».')
put('ru',14,7,lit='И он спустился и говорил с женщиной; и она была угодна глазам Самсона.')
put('ru',14,15,lit='И в седьмой день они сказали жене Самсона: «Уговори своего мужа, чтобы он объяснил нам загадку, чтобы мы не сожгли тебя и дом твоего отца огнём. Вы позвали нас, чтобы обобрать нас, не так ли?»')
put('ru',14,17,lit='И она плакала перед ним семь дней, в которые у них был пир; и в седьмой день он объяснил ей, ибо она теснила его. И она объяснила загадку сынам своего народа.')
put('ru',14,16,diff='Ненависть усилена словом «только». В словах женщины стоит прошедшее «мне не объяснил», тогда как перевод говорит «мне не разгадаешь».')
rows=list(qa.values());Path('.literalgen-state/de-en-ru/jdg-b-qa.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n');print('QA',len(rows))
Path('.literalgen-state/de-en-ru/jdg-b-root-en-qa.json').write_text('[]\n')
