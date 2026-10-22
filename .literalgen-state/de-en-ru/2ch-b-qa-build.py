from pathlib import Path
import json
q=[]
def add(lang,ch,v,lit=None,diff=None):
 ps=Path(f'Tools/LiteralGen/outputs/{lang}/14_2CH').glob(f'2CH_{ch:03}*.tsv')
 p=next(p for p in ps if any(s.startswith(str(v)+'\t') for s in p.read_text().splitlines()))
 old=next(s for s in p.read_text().splitlines() if s.startswith(str(v)+'\t'));a=old.split('\t');a[1]=lit if lit is not None else a[1];a[2]=diff if diff is not None else a[2];new='\t'.join(a)
 if old!=new:q.append({'path':str(p),'old_row':old,'new_row':new})
add('de',22,6,'Und er kehrte um, um in Jesreel von den Schlägen geheilt zu werden, mit denen sie ihn in Rama geschlagen hatten, als er gegen Hasael, den König von Syrien, kämpfte. Und Asarja, der Sohn Jorams, der König Judas, zog hinab, um Joram, den Sohn Ahabs, in Jesreel zu sehen, denn er war krank.','Genannt ist Asarja statt Ahasja; die Schläge sind aktiv ausgedrückt, und genannt ist das Sehen.')
add('ru',22,6,'И он возвратился исцелиться в Изрееле от ударов, которыми они поразили его в Раме, когда он сражался с Азаилом, царём Сирии. И Азария, сын Иорама, царь Иуды, сошёл увидеть Иорама, сына Ахава, в Изрееле, ибо тот болен.','Назван Азария вместо Охозии; сохранены удары и схождение.')
add('de',22,11,'Und Josabeath, die Tochter des Königs, nahm Joas, den Sohn Ahasjas, und stahl ihn aus der Mitte der Söhne des Königs, die getötet wurden, und setzte ihn und seine Amme in die Bettenkammer. Und Josabeath, die Tochter des Königs Joram, die Frau des Priesters Jojada, verbarg ihn vor Athalja, denn sie war die Schwester Ahasjas; und sie tötete ihn nicht.')
add('ru',22,11,'И Иосавеф, дочь царя, взяла Иоаса, сына Охозии, и украла его из среды сынов царя, которых умерщвляли, и поместила его и его кормилицу в комнату кроватей. И Иосавеф, дочь царя Иорама, жена священника Иодая, скрыла его от Гофолии, ибо она была сестрой Охозии; и та не умертвила его.')
add('de',15,2,'Und er ging Asa entgegen und sagte zu ihm: „Hört mich, Asa und ganz Juda und Benjamin! Der HERR ist mit euch, wenn ihr mit ihm seid; und wenn ihr ihn sucht, wird er von euch gefunden werden; und wenn ihr ihn verlasst, wird er euch verlassen.')
add('de',15,4,'Und in seiner Bedrängnis kehrte es zum HERRN, dem Gott Israels, um; und sie suchten ihn, und er wurde von ihnen gefunden.')
add('de',15,15,'Und ganz Juda freute sich über den Eid, denn sie hatten mit ihrem ganzen Herzen geschworen und mit ihrem ganzen Willen ihn gesucht; und er wurde von ihnen gefunden, und der HERR verschaffte ihnen ringsum Ruhe.')
add('ru',16,9,'Ибо Господь: Его глаза странствуют по всей земле, чтобы показать силу с теми, чьё сердце всецело обращено к Нему. В этом ты поступил глупо; ибо отныне с тобой войны».')
add('de',20,34,diff='Die ersten und die letzten Begebenheiten sind ausdrücklich genannt.')
add('ru',20,34,diff='Первые и последние дела выражены прямо.')
Path('.literalgen-state/de-en-ru/2ch-b-qa.json').write_text(json.dumps(q,ensure_ascii=False,indent=2))
q=[]
add('en',21,15,diff='The Hebrew speaks of many or severe illnesses; BSB uses a severe illness.')
add('en',20,21,diff='The Hebrew leaves the subject unnamed and says splendor of holiness without a possessive expression; BSB names Jehoshaphat and adds His.')
add('en',24,15,diff='The Hebrew says he was satisfied with days; BSB uses full of years.')
add('en',24,11,diff='The Hebrew repeats day in day by day; BSB says daily.')
add('en',20,28,diff='The Hebrew says they came to the house of the LORD; BSB explicitly describes going into it.')
Path('.literalgen-state/de-en-ru/2ch-b-root-en-qa.json').write_text(json.dumps(q,ensure_ascii=False,indent=2))
