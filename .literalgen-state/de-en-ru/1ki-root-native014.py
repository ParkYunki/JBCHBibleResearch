from pathlib import Path
import re,json
rows={
'de':[
('Zu jener Zeit wurde Abia, der Sohn Jerobeams, krank.','Das Krankwerden ist als Ereignis erzählt.'),
('Und Jerobeam sagte zu seiner Frau: „Mach dich doch auf und verändere dich, damit man nicht erkennt, dass du Jerobeams Frau bist, und geh nach Silo; siehe, dort ist Ahia, der Prophet, er hat über mich geredet, dass ich König über dieses Volk sein sollte.','Das Reden betrifft ihn; es ist nicht ausdrücklich als Gespräch mit ihm bezeichnet.'),
('Und nimm in deine Hand zehn Brote und Kuchen und eine Flasche Honig und komm zu ihm; er wird dir mitteilen, was dem Jungen geschehen wird.“','Die Hand ist ausdrücklich genannt; die Mitteilung folgt als eigene Aussage.'),
('Und Jerobeams Frau tat so und machte sich auf und ging nach Silo und kam in das Haus Ahias; und Ahia konnte nicht sehen, denn seine Augen waren vor Alter starr geworden.','Nah am Hebräischen.'),
('Und der HERR hatte zu Ahia gesagt: „Siehe, Jerobeams Frau kommt, um von dir ein Wort über ihren Sohn zu erfragen, denn er ist krank; so und so sollst du zu ihr reden.“ Und es geschah, als sie kam, da stellte sie sich fremd.','Nah am Hebräischen.'),
('Und es geschah, als Ahia den Laut ihrer Füße hörte, als sie durch den Eingang kam, da sagte er: „Komm herein, Jerobeams Frau! Warum stellst du dich fremd? Und ich bin mit Hartem zu dir gesandt.','Das Hebräische sagt mit Hartem gesandt, ohne eigenes Wort für Bote.'),
('Geh, sage zu Jerobeam: ‚So hat der HERR, der Gott Israels, gesagt: Weil ich dich aus der Mitte des Volkes erhöht und dich zum Fürsten über mein Volk Israel gesetzt habe','Das Hebräische beginnt die Begründung mit weil.'),
('und das Königtum vom Haus Davids gerissen und es dir gegeben habe, du aber nicht wie mein Knecht David gewesen bist, der meine Gebote bewahrt hat und mit seinem ganzen Herzen hinter mir hergegangen ist, um nur das Rechte in meinen Augen zu tun,','Die Augen sind ausdrücklich genannt; nur das Rechte wird getan.'),
('und du mehr Böses getan hast als alle, die vor dir waren, und hingegangen bist und dir andere Götter und gegossene Bilder gemacht hast, um mich zu reizen, und mich hinter deinen Rücken geworfen hast,','Nah am Hebräischen.'),
('darum, siehe, bringe ich Unheil zum Haus Jerobeams und werde von Jerobeam jeden, der an die Wand uriniert, ausrotten, den Eingeschlossenen und den Verlassenen in Israel; und ich werde hinter dem Haus Jerobeams ausfegen, wie man Kot ausfegt, bis er ganz vergangen ist.','Das Hebräische bezeichnet das Männliche bildlich als an die Wand Urinierenden und gebraucht kein eigenes Wort für Nachkommen.'),
('Wer von Jerobeam in der Stadt stirbt, den werden die Hunde fressen, und wer auf dem Feld stirbt, den werden die Vögel des Himmels fressen; denn der HERR hat geredet.‘','Nah am Hebräischen.'),
('Und du, mach dich auf, geh in dein Haus! Wenn deine Füße in die Stadt kommen, wird das Kind sterben.','Die Füße stehen in der Mehrzahl.'),
('Und ganz Israel wird um ihn klagen und ihn begraben, denn dieser allein wird von Jerobeam in ein Grab kommen, weil in ihm im Haus Jerobeams etwas Gutes zum HERRN, dem Gott Israels, hin gefunden worden ist.','Das Gute ist zum HERRN hin gerichtet.'),
('Und der HERR wird sich einen König über Israel aufrichten, der das Haus Jerobeams ausrotten wird, dies heute; und was? Auch jetzt!','Das Hebräische nennt diesen Tag und jetzt, ohne eigenes Verb für geschehen.'),
('Und der HERR wird Israel schlagen, wie das Rohr im Wasser schwankt, und Israel aus diesem guten Erdboden ausreißen, den er ihren Vätern gegeben hat, und sie jenseits des Stromes zerstreuen, weil sie ihre Ascheren gemacht haben, die den HERRN reizen.','Das Rohr schwankt mit aktivem Verb; das Reizen ist als Tätigkeit beschrieben.'),
('Und er wird Israel wegen der Sünden Jerobeams hingeben, die er begangen und durch die er Israel zum Sündigen gebracht hat.“','Nah am Hebräischen.'),
('Und Jerobeams Frau machte sich auf und ging und kam nach Thirza; sie kam an die Schwelle des Hauses, und der Junge starb.','Nah am Hebräischen.'),
('Und sie begruben ihn, und ganz Israel klagte um ihn nach dem Wort des HERRN, das er durch die Hand seines Knechtes Ahia, des Propheten, geredet hatte.','Das Hebräische bewahrt das Bild der Hand seines Knechtes.'),
('Und die übrigen Taten Jerobeams, wie er Krieg geführt und wie er regiert hat, siehe, sie sind im Buch der Tagesereignisse der Könige von Israel geschrieben.','Nah am Hebräischen.'),
('Und die Tage, die Jerobeam regierte, waren zweiundzwanzig Jahre; und er legte sich zu seinen Vätern, und Nadab, sein Sohn, wurde an seiner Stelle König.','Das Hebräische nennt die Tage und gebraucht das Bild des Sichlegens zu den Vätern.'),
('Und Rehabeam, der Sohn Salomos, regierte in Juda. Einundvierzig Jahre alt war Rehabeam, als er König wurde, und siebzehn Jahre regierte er in Jerusalem, der Stadt, die der HERR aus allen Stämmen Israels erwählt hatte, um seinen Namen dort hinzusetzen; und der Name seiner Mutter war Naema, die Ammonitin.','Nah am Hebräischen.'),
('Und Juda tat das Böse in den Augen des HERRN, und sie reizten ihn zum Eifer mehr als alles, was ihre Väter getan hatten, durch ihre Sünden, die sie begingen.','Das Böse steht ausdrücklich in den Augen des HERRN.'),
('Und auch sie bauten sich Höhen und Gedenksteine und Ascheren auf jedem hohen Hügel und unter jedem grünen Baum.','Das Hebräische verbindet mit und, ohne ausdrückliches denn; auch sie und sich sind genannt.'),
('Und auch Kultprostituierte gab es im Land; sie taten nach allen Gräueln der Nationen, die der HERR vor den Söhnen Israels vertrieben hatte.','Die Bezeichnung des Kultprostituierten steht im Hebräischen in der kollektiven Einzahl.'),
('Und es geschah im fünften Jahr des Königs Rehabeam, da zog Sisak, der König von Ägypten, gegen Jerusalem hinauf.','Nah am Hebräischen.'),
('Und er nahm die Schätze des Hauses des HERRN und die Schätze des Hauses des Königs, und alles nahm er; und er nahm alle goldenen Schilde, die Salomo gemacht hatte.','Das Nehmen wird dreimal wiederholt; Salomo machte die Schilde mit aktivem Verb.'),
('Und der König Rehabeam machte an ihrer Stelle bronzene Schilde und vertraute sie der Hand der Obersten der Läufer an, die den Eingang des Hauses des Königs bewachten.','Das Machen ist Rehabeams aktive Handlung; die Wächter heißen Läufer.'),
('Und es geschah, sooft der König in das Haus des HERRN kam, da trugen die Läufer sie und brachten sie in die Kammer der Läufer zurück.','Nah am Hebräischen.'),
('Und die übrigen Taten Rehabeams und alles, was er getan hat, sind sie nicht im Buch der Tagesereignisse der Könige von Juda geschrieben?','Das Hebräische fragt nach dem Geschriebensein, statt es mit siehe festzustellen.'),
('Und Krieg war zwischen Rehabeam und Jerobeam alle Tage.','Das Hebräische sagt alle Tage ohne eigenes Wort für Leben.'),
('Und Rehabeam legte sich zu seinen Vätern und wurde bei seinen Vätern in der Stadt Davids begraben; und der Name seiner Mutter war Naema, die Ammonitin, und Abiam, sein Sohn, wurde an seiner Stelle König.','Das Hebräische gebraucht das Bild des Sichlegens zu den Vätern.')
],
'ru':[
('В то время заболел Авия, сын Иеровоама.','Близко к еврейскому.'),
('И Иеровоам сказал своей жене: «Встань же и измени свой вид, и пусть не узнают, что ты жена Иеровоама, и пойди в Силом; вот, там Ахия, пророк; он говорил обо мне, что я буду царём над этим народом.','Частица просьбы и вот выражены явно.'),
('И возьми в свою руку десять хлебов и лепёшки и бутылку мёда и приди к нему; он сообщит тебе, что будет с мальчиком».','Названа рука; нет отдельного выражения для человека Божия.'),
('И жена Иеровоама сделала так и встала и пошла в Силом и пришла в дом Ахии; а Ахия не мог видеть, ибо его глаза застыли от старости.','Близко к еврейскому.'),
('А Господь сказал Ахии: «Вот, жена Иеровоама приходит спросить у тебя слово о своём сыне, ибо он болен; так и так говори ей». И было, когда она пришла, она выдавала себя за другую.','Её приход в изменённом виде рассказан отдельно после слов Господа.'),
('И было, когда Ахия услышал звук её ног, когда она шла во вход, он сказал: «Войди, жена Иеровоама! Почему ты выдаёшь себя за другую? А я послан к тебе с тяжёлым.','Вопрос описывает её действие; посылание выражено страдательно, без отдельного слова посланник.'),
('Пойди, скажи Иеровоаму: „Так сказал Господь, Бог Израиля: За то, что Я возвысил тебя из среды народа и поставил тебя вождём над Моим народом Израилем','Нет отдельного определения простой при народе; фраза начинается с основания за то, что.'),
('и отторг царство от дома Давида и дал его тебе, а ты не был как Мой раб Давид, который хранил Мои заповеди и который ходил за Мной всем своим сердцем, чтобы делать только правое в Моих глазах,','Близко к еврейскому.'),
('и ты сделал больше зла, чем все, которые были прежде тебя, и пошёл и сделал себе иных богов и литые изображения, чтобы гневить Меня, а Меня ты бросил за свою спину,','Сохранён образ бросания за спину; изображения названы литыми.'),
('поэтому вот, Я навожу бедствие на дом Иеровоама и отсеку у Иеровоама мочащегося к стене, заключённого и оставленного в Израиле, и вымету за домом Иеровоама, как выметают навоз, пока он не исчезнет.','Назван навоз, а не сор; дом Иеровоама назван повторно.'),
('Умершего у Иеровоама в городе съедят псы, а умершего в поле съедят птицы небес, ибо Господь сказал“.','Оба раза употреблён глагол есть; в конце стоит ибо.'),
('А ты встань, пойди в свой дом; когда твои ноги войдут в город, ребёнок умрёт.','Ноги стоят во множественном числе.'),
('И весь Израиль будет оплакивать его и похоронит его, ибо этот один у Иеровоама придёт в гробницу, так как в нём в доме Иеровоама найдено доброе к Господу, Богу Израиля.','Израиль назван собирательно; доброе направлено к Господу.'),
('И Господь поставит Себе царя над Израилем, который отсечёт дом Иеровоама, это сегодня; и что? Также теперь!','Еврейский текст говорит об этом дне прямо как о сегодня.'),
('И Господь поразит Израиль, как колеблется тростник в воде, и вырвет Израиль из этой доброй земли, которую Он дал их отцам, и рассеет их за рекой, потому что они сделали свои ашеры, гневящие Господа.','Израиль повторён как собирательное имя; ашеры названы прямо, а не общим словом идолы.'),
('И Он предаст Израиль из-за грехов Иеровоама, которыми он согрешил и которыми побудил Израиль грешить».','Имя Господа не повторяется отдельно в этом стихе.'),
('И жена Иеровоама встала и пошла и пришла в Фирцу; она пришла к порогу дома, и мальчик умер.','Прямо назван приход к порогу, без отдельного глагола переступить.'),
('И его похоронили, и весь Израиль оплакивал его, по слову Господа, которое Он изрёк рукой Своего раба Ахии, пророка.','Сохранён образ руки раба.'),
('А прочие дела Иеровоама, как он воевал и как царствовал, вот, они записаны в книге событий дней царей Израиля.','Вот выражено явно.'),
('И дни, которые Иеровоам царствовал, были двадцать два года; и он лёг с отцами своими, и Нават, его сын, воцарился вместо него.','Названы дни; сохранён образ того, как он лёг с отцами.'),
('И Ровоам, сын Соломона, царствовал в Иудее. Ровоаму был сорок один год, когда он воцарился, и семнадцать лет он царствовал в Иерусалиме, городе, который Господь избрал из всех колен Израиля, чтобы поместить там Своё имя; и имя его матери Наама аммонитянка.','Помещение имени выражено активным действием.'),
('И Иуда делал злое в глазах Господа, и они возбуждали Его ревность более всего, что сделали их отцы своими грехами, которыми согрешили.','Прямо названо возбуждение ревности.'),
('И также они строили себе высоты и столбы и ашеры на каждом высоком холме и под каждым зелёным деревом.','Названы ашеры и зелёное дерево, а не капища и тенистое дерево.'),
('И также храмовые блудники были в земле; они делали согласно всем мерзостям народов, которых Господь изгнал перед сынами Израиля.','Обозначение храмового блудника стоит в собирательном единственном числе.'),
('И было в пятый год царя Ровоама, Сусаким, царь Египта, поднялся против Иерусалима.','Подъём выражен явно.'),
('И он взял сокровища дома Господа и сокровища дома царя, и всё взял; и взял все золотые щиты, которые сделал Соломон.','Нет сообщения о Давиде, рабах Адраазара и перенесении щитов в Иерусалим; взятие повторено трижды.'),
('И царь Ровоам сделал вместо них медные щиты и вверил их руке начальников бегунов, охранявших вход дома царя.','Рука стоит в единственном числе; охраняющие названы бегунами.'),
('И было, каждый раз, когда царь приходил в дом Господа, бегуны несли их и возвращали их в комнату бегунов.','Сказано приходил; нет отдельного потом.'),
('А прочие дела Ровоама и всё, что он сделал, разве они не записаны в книге событий дней царей Иуды?','Еврейский текст задаёт вопрос о записи.'),
('И война была между Ровоамом и Иеровоамом все дни.','Нет отдельного слова жизнь.'),
('И Ровоам лёг с отцами своими и был погребён с отцами своими в городе Давида; и имя его матери Наама аммонитянка, и Авия, его сын, воцарился вместо него.','Сохранён образ того, как он лёг с отцами.')
]}
for x in rows.values():assert len(x)==31
r=Path('Tools/LiteralGen');created=[]
for lang,data in rows.items():
 for packet in sorted((r/'packets/de-en-ru/11_1KI').glob('*_014*.txt')):
  b=next(x for x in packet.read_text().split('==TARGET ')[1:] if x.startswith('lang='+lang+' '));vs=[int(x) for x in re.findall(r'^#(\d+) ',b,re.M)];p=r/'outputs'/lang/'11_1KI'/(packet.stem+'.tsv');assert not p.exists();p.parent.mkdir(parents=True,exist_ok=True);out=[]
  for v in vs:
   a,b=data[v-1];assert len(b.split())<=60 and '\t' not in a+b and '\n' not in a+b;out.append(f'{v}\t{a}\t{b}')
  with p.open('x') as f:f.write('\n'.join(out)+'\n')
  created.append(str(p))
q=Path('.literalgen-state/de-en-ru/11_1KI-root-native-created.json');a=json.loads(q.read_text());a.extend(created);q.write_text(json.dumps(a,ensure_ascii=False,indent=2));print('Native014',len(created),'files',62,'rows exclusively created')
