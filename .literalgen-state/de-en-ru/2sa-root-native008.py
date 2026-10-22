from pathlib import Path
import json,re
rows={
'de':[
('Und es geschah danach, und David schlug die Philister und unterwarf sie, und David nahm Metheg-Amma aus der Hand der Philister.','David wird zweimal genannt; Metheg-Amma steht als Bezeichnung des genommenen Ortes.'),
('Und er schlug Moab und maß sie mit der Messschnur, indem er sie zur Erde hinlegen ließ; und er maß zwei Schnurlängen zum Töten und eine volle Schnurlänge zum Lebenlassen. Und Moab wurde David zu Knechten, die Tribut trugen.','Das Hebräische nennt das Messen mit der Schnur und das Hinlegen; Moab wird als kollektiver Name gebraucht.'),
('Und David schlug Hadadeser, den Sohn Rehobs, den König von Zoba, als er ging, seine Hand am Fluss Euphrat wiederherzustellen.','Die Macht wird mit dem Bild seiner Hand beschrieben.'),
('Und David nahm von ihm tausendsiebenhundert Reiter und zwanzigtausend Mann zu Fuß gefangen; und David durchtrennte die Sehnen der ganzen Wagenmacht und ließ davon hundert Wagen übrig.','David wird zweimal genannt; das Objekt des Sehnendurchtrennens heißt wörtlich die ganze Wagenmacht, ohne ausdrückliche Nennung der Rosse.'),
('Und Syrien von Damaskus kam, um Hadadeser, dem König von Zoba, zu helfen; und David schlug unter Syrien zweiundzwanzigtausend Mann.','Syrien wird im Hebräischen als kollektiver Name gebraucht.'),
('Und David setzte Besatzungen in Syrien von Damaskus, und Syrien wurde David zu Knechten, die Tribut trugen; und der HERR rettete David überall, wohin er ging.','Besatzungen sind ausdrücklich genannt; der HERR rettete David.'),
('Und David nahm die goldenen Schilde, die Hadadesers Knechten gehörten, und brachte sie nach Jerusalem.','Nah am Hebräischen.'),
('Und aus Betah und aus Berothai, den Städten Hadadesers, nahm der König David sehr viel Bronze.','Nah am Hebräischen.'),
('Und Thoi, der König von Hamath, hörte, dass David das ganze Heer Hadadesers geschlagen hatte.','Nah am Hebräischen.'),
('Und Thoi sandte Joram, seinen Sohn, zum König David, um ihn nach dem Wohlergehen zu fragen und ihn zu segnen, weil er gegen Hadadeser gekämpft und ihn geschlagen hatte, denn Hadadeser war ein Mann der Kriege Thois; und in seiner Hand waren silberne Gefäße und goldene Gefäße und bronzene Gefäße.','Thoi wird als Sender ausdrücklich genannt; Hadadeser heißt ein Mann seiner Kriege. Die Gefäße sind dreimal genannt und befinden sich in der Hand.'),
('Auch sie heiligte der König David dem HERRN, zusammen mit dem Silber und dem Gold, das er von allen Nationen geheiligt hatte, die er unterworfen hatte:','Nah am Hebräischen.'),
('von Syrien und von Moab und von den Söhnen Ammons und von den Philistern und von Amalek und von der Beute Hadadesers, des Sohnes Rehobs, des Königs von Zoba.','Ammon wird mit dem Wort Söhne bezeichnet.'),
('Und David machte sich einen Namen, als er vom Schlagen Syriens im Salztal zurückkehrte, achtzehntausend.','Das Schlagen gehört im Hebräischen zur Rückkehrbeschreibung; die Zahl steht danach ohne eigenes Wort für Mann.'),
('Und er setzte Besatzungen in Edom; in ganz Edom setzte er Besatzungen, und ganz Edom wurde David zu Knechten; und der HERR rettete David überall, wohin er ging.','Das Setzen der Besatzungen wird wiederholt; der HERR rettete David.'),
('Und David regierte über ganz Israel, und David übte Recht und Gerechtigkeit für sein ganzes Volk.','Davids Name wird wiederholt.'),
('Und Joab, der Sohn der Zeruja, war über das Heer, und Josaphat, der Sohn Ahiluds, war Geschichtsschreiber.','Nah am Hebräischen.'),
('Und Zadok, der Sohn Ahitobs, und Ahimelech, der Sohn Abjathars, waren Priester, und Seraja war Schreiber.','Nah am Hebräischen.'),
('Und Benaja, der Sohn Jojadas, und die Krether und die Plether; und Davids Söhne waren Priester.','Bei Benaja steht kein ausdrückliches Wort für über; die Gruppen sind mit und verbunden.')
],
'ru':[
('И было после этого, и Давид поразил филистимлян и смирил их, и Давид взял Мефег-Гаамма из руки филистимлян.','Рука стоит в единственном числе.'),
('И он поразил Моав и измерил их верёвкой, уложив их на землю; и отмерил две верёвки на умерщвление и полную верёвку на оставление в живых. И стал Моав у Давида рабами, несущими дань.','Моав назван собирательно; названа полная длина верёвки.'),
('И Давид поразил Адраазара, сына Рехова, царя Сувы, когда тот шёл восстановить свою руку при реке Евфрате.','Владычество выражено образом руки.'),
('И Давид захватил у него тысячу семьсот всадников и двадцать тысяч пеших людей, и Давид подрезал жилы всей колесничной силе и оставил из неё сто колесниц.','Объект подрезания жил назван колесничной силой, без отдельного слова кони; оставлены сто колесниц.'),
('И пришла Сирия Дамасская на помощь Адраазару, царю Сувы, и Давид поразил среди Сирии двадцать две тысячи человек.','Сирия названа собирательно.'),
('И Давид поставил гарнизоны в Сирии Дамасской, и стала Сирия у Давида рабами, несущими дань, и Господь спасал Давида везде, куда он ходил.','Еврейский глагол говорит о спасении Давида; Сирия названа собирательно.'),
('И Давид взял золотые щиты, которые были у рабов Адраазара, и принёс их в Иерусалим.','В еврейском стихе нет заключительного сообщения о Сусакиме, Ровоаме и Соломоне.'),
('И из Бефы и из Берофы, городов Адраазара, царь Давид взял весьма много меди.','Названо взятие из городов, а не в городах.'),
('И Фой, царь Имафа, услышал, что Давид поразил всё войско Адраазара.','Близко к еврейскому.'),
('И Фой послал своего сына Иорама к царю Давиду спросить его о благополучии и благословить его за то, что он воевал с Адраазаром и поразил его, ибо Адраазар был человеком войн Фоя; и в его руке были серебряные сосуды и золотые сосуды и медные сосуды.','Сказано благословить, а не благодарить; Адраазар назван человеком войн Фоя. Рука стоит в единственном числе, сосуды названы трижды.'),
('Также и их царь Давид посвятил Господу вместе с серебром и золотом, которое он посвятил от всех народов, которых покорил:','Еврейский текст не содержит отдельного слова отнятого.'),
('от Сирии и от Моава и от сынов Аммона и от филистимлян и от Амалика и от добычи Адраазара, сына Рехова, царя Сувы.','Сирия, Моав и Амалик названы собирательно, Аммон — через слово сыны.'),
('И Давид сделал себе имя, возвращаясь от поражения Сирии в долине Соли, восемнадцати тысяч.','Сирия названа собирательно.'),
('И он поставил гарнизоны в Идумее; во всей Идумее поставил гарнизоны, и вся Идумея была рабами Давида, и Господь спасал Давида везде, куда он ходил.','Идумея названа собирательно; глагол говорит о спасении Давида.'),
('И Давид царствовал над всем Израилем, и Давид творил суд и правду для всего своего народа.','Суд и правда совершаются для всего народа.'),
('И Иоав, сын Саруи, был над войском, и Иосафат, сын Ахилуда, — дееписателем.','Положение Иоава выражено предлогом над, без отдельного слова начальник.'),
('И Садок, сын Ахитува, и Ахимелех, сын Авиафара, были священниками, и Сераия — писцом.','Близко к еврейскому.'),
('И Ванея, сын Иодая, и хелефеи и фелефеи; а сыновья Давида были священниками.','При Ванее нет отдельного слова начальник или предлога над; сыновья Давида названы священниками.')
]}
created=[]
for lang, data in rows.items():
 assert len(data)==18
 p=Path(f'Tools/LiteralGen/outputs/{lang}/10_2SA/2SA_008.tsv');assert not p.exists()
 text=[]
 for i,(literal,diff) in enumerate(data,1):
  assert len(diff.split())<=60 and '\t' not in literal+diff and '\n' not in literal+diff
  text.append(f'{i}\t{literal}\t{diff}')
 with p.open('x') as f:f.write('\n'.join(text)+'\n')
 created.append(str(p))
Path('.literalgen-state/de-en-ru/10_2SA-root-native-created.json').write_text(json.dumps(created,ensure_ascii=False,indent=2))
print('Native008',len(created),'files',36,'rows exclusively created')
