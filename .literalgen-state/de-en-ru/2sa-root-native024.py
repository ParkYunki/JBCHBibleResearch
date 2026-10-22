from pathlib import Path
import json
rows={
'de':[
('Und der Zorn des HERRN entbrannte wieder gegen Israel, und er reizte David gegen sie, indem er sagte: „Geh, zähle Israel und Juda!“','Nah am Hebräischen.'),
('Und der König sagte zu Joab, dem Heerführer, der bei ihm war: „Durchziehe doch alle Stämme Israels von Dan bis Beer-Seba, und mustert das Volk, damit ich die Zahl des Volkes weiß!“','Das Beiihmsein des Heerführers ist ausdrücklich genannt; die Aufforderung zum Mustern steht in der Mehrzahl.'),
('Und Joab sagte zum König: „Möge der HERR, dein Gott, zum Volk, so viel es ist und so viel es ist, hundertmal hinzufügen, und die Augen meines Herrn, des Königs, mögen es sehen; aber warum hat mein Herr, der König, Gefallen an dieser Sache?“','Der Vergleich so viel es ist wird wiederholt; die Augen sehen, ohne ein eigenes Wort für Lust.'),
('Und das Wort des Königs war stark gegen Joab und gegen die Heerführer, und Joab und die Heerführer gingen vor dem König hinaus, um das Volk, Israel, zu mustern.','Nah am Hebräischen.'),
('Und sie gingen über den Jordan und lagerten in Aroer, zur Rechten der Stadt, die mitten im Tal lag, nach Gad und nach Jaser hin.','Das Hebräische verbindet Gad und Jaser als Richtungsangaben.'),
('Und sie kamen nach Gilead und in das Land Thachtim-Hodsi, und sie kamen nach Dan-Jaan und ringsum nach Sidon.','Das Hebräische nennt das Land Thachtim-Hodsi.'),
('Und sie kamen zur Festung Tyrus und zu allen Städten der Heviter und der Kanaaniter, und sie zogen hinaus in den Süden Judas, nach Beer-Seba.','Nah am Hebräischen.'),
('Und sie durchzogen das ganze Land und kamen am Ende von neun Monaten und zwanzig Tagen nach Jerusalem.','Nah am Hebräischen.'),
('Und Joab gab dem König die Zahl der Musterung des Volkes; und Israel zählte achthunderttausend tapfere Männer, die das Schwert zogen, und die Männer Judas fünfhunderttausend Mann.','Nah am Hebräischen.'),
('Und Davids Herz schlug ihn, nachdem er das Volk gezählt hatte; und David sagte zum HERRN: „Ich habe sehr gesündigt mit dem, was ich getan habe; und nun, HERR, lass doch die Schuld deines Knechtes vorübergehen, denn ich habe sehr töricht gehandelt!“','Das Zählen steht als aktive Handlung; die Bitte gebraucht das Bild des Vorübergehenlassens.'),
('Und David stand am Morgen auf; und das Wort des HERRN geschah zu Gad, dem Propheten, dem Seher Davids, indem er sagte:','Nah am Hebräischen.'),
('„Geh und rede zu David: ‚So hat der HERR gesagt: Drei Dinge lege ich dir auf; wähle dir eines davon, und ich werde es dir tun.‘“','Die drei Dinge werden ihm auferlegt, nicht bloß zu ihm gebracht.'),
('Und Gad kam zu David und berichtete ihm und sagte zu ihm: „Sollen sieben Jahre Hunger in deinem Land kommen oder drei Monate deines Fliehens vor deinen Bedrängern, während einer dich verfolgt, oder drei Tage Pest in deinem Land? Nun erkenne und sieh, welches Wort ich dem zurückbringen soll, der mich gesandt hat!“','Der Verfolger steht in der Einzahl; die Antwort wird als zurückzubringendes Wort beschrieben.'),
('Und David sagte zu Gad: „Mir ist sehr angst; lasst uns doch in die Hand des HERRN fallen, denn seine Erbarmungen sind zahlreich, aber in die Hand eines Menschen möge ich nicht fallen!“','Die Erbarmungen stehen in der Mehrzahl; Mensch steht in der Einzahl.'),
('Und der HERR gab Pest in Israel vom Morgen bis zur bestimmten Zeit; und vom Volk starben von Dan bis Beer-Seba siebzigtausend Mann.','Geben der Pest und Sterben des Volkes sind als eigene Aussagen verbunden.'),
('Und der Engel streckte seine Hand nach Jerusalem aus, um es zu verderben, und den HERRN reute das Unheil; und er sagte zum Engel, der im Volk Verderben brachte: „Genug! Lass jetzt deine Hand sinken!“ Und der Engel des HERRN war bei der Tenne Aravnas, des Jebusiters.','Nah am Hebräischen.'),
('Und David sagte zum HERRN, als er den Engel sah, der im Volk schlug, und sagte: „Siehe, ich habe gesündigt, und ich habe verkehrt gehandelt; aber diese Schafe, was haben sie getan? Deine Hand sei doch gegen mich und gegen das Haus meines Vaters!“','Die Redeeinleitung wird wiederholt; die Bitte enthält eine ausdrückliche Bittepartikel.'),
('Und Gad kam an jenem Tag zu David und sagte zu ihm: „Geh hinauf, errichte dem HERRN einen Altar auf der Tenne Aravnas, des Jebusiters!“','Das Hebräische nennt jenen Tag, nicht nur dieselbe Zeit.'),
('Und David ging hinauf nach dem Wort Gads, wie der HERR geboten hatte.','Nah am Hebräischen.'),
('Und Aravna schaute hinaus und sah den König und seine Knechte zu ihm herüberkommen; und Aravna ging hinaus und warf sich vor dem König mit seinem Gesicht zur Erde nieder.','Aravna wird zweimal genannt; sein Hinausgehen ist ausdrücklich erwähnt.'),
('Und Aravna sagte: „Warum ist mein Herr, der König, zu seinem Knecht gekommen?“ Und David sagte: „Um von dir die Tenne zu kaufen, um dem HERRN einen Altar zu bauen, damit die Plage vom Volk abgewehrt wird.“','Aravna ist als Sprecher ausdrücklich genannt; das Abwehren der Plage steht im Passiv.'),
('Und Aravna sagte zu David: „Mein Herr, der König, nehme und opfere, was gut ist in seinen Augen! Siehe, die Rinder zum Brandopfer und die Dreschschlitten und das Geschirr der Rinder zum Holz.','Die Rinder stehen in der Mehrzahl; die Augen sind ausdrücklich genannt.'),
('Dies alles gab Aravna, der König, dem König.“ Und Aravna sagte zum König: „Der HERR, dein Gott, möge dich annehmen!“','Nah am Hebräischen.'),
('Und der König sagte zu Aravna: „Nein, sondern ich werde es gewiss von dir um einen Preis kaufen und dem HERRN, meinem Gott, nicht umsonst Brandopfer opfern.“ Und David kaufte die Tenne und die Rinder um fünfzig Schekel Silber.','Die Rinder stehen in der Mehrzahl; Schekel sind ausdrücklich genannt.'),
('Und David baute dort dem HERRN einen Altar und opferte Brandopfer und Friedensopfer; und der HERR ließ sich für das Land erbitten, und die Plage wurde von Israel abgewehrt.','David wird ausdrücklich genannt; das Abwehren der Plage ist passiv.')
],
'ru':[
('И гнев Господа снова возгорелся против Израиля, и он побудил Давида против них, говоря: «Пойди, исчисли Израиль и Иуду!»','Побуждение Давида направлено против них.'),
('И царь сказал Иоаву, начальнику войска, который был с ним: «Пройди же по всем коленам Израиля от Дана до Вирсавии, и исчислите народ, чтобы мне знать число народа!»','В перечне колен нет отдельного и Иудиным.'),
('И Иоав сказал царю: «Да прибавит Господь, твой Бог, к народу столько же и столько же стократно, и глаза моего господина царя пусть увидят; но почему мой господин царь желает этого дела?»','Сравнение столько же повторяется дважды.'),
('И слово царя превозмогло Иоава и начальников войска, и Иоав и начальники войска вышли от лица царя, чтобы исчислить народ, Израиль.','Сохранён образ выхода от лица царя.'),
('И они перешли Иордан и расположились станом в Ароере, справа от города, который посреди долины, к Гаду и к Иазеру.','Гад и Иазер названы как направления.'),
('И они пришли в Галаад и в землю Тахтим-Ходши, и пришли в Дан-Яан и вокруг к Сидону.','Близко к еврейскому.'),
('И они пришли к крепости Тира и ко всем городам хивеянина и хананеянина, и вышли на юг Иудеи, в Вирсавию.','Хивеянин и хананеянин названы в собирательном единственном числе.'),
('И они обошли всю землю и пришли в конце девяти месяцев и двадцати дней в Иерусалим.','Близко к еврейскому.'),
('И Иоав дал царю число переписи народа; и было в Израиле восемьсот тысяч мужей доблести, извлекающих меч, а людей Иуды — пятьсот тысяч человек.','Способность к войне выражена образом извлечения меча.'),
('И сердце Давида ударило его после того, как он исчислил народ; и Давид сказал Господу: «Я весьма согрешил тем, что сделал; и теперь, Господи, удали же вину Твоего раба, ибо я поступил весьма глупо!»','Сердце ударило Давида; названа вина раба, которую он просит удалить.'),
('И Давид встал утром; и слово Господа было к Гаду, пророку, прозорливцу Давида, говоря:','Нет отдельного указания на другой день.'),
('«Пойди и скажи Давиду: „Так сказал Господь: Три вещи налагаю Я на тебя; выбери себе одну из них, и Я сделаю её тебе“».','Нет отдельного слова наказания; действие Бога выражено активно.'),
('И Гад пришёл к Давиду и сообщил ему и сказал ему: «Придут ли к тебе семь лет голода в твоей стране, или три месяца твоего бегства перед твоими врагами, когда он преследует тебя, или три дня мора в твоей стране? Теперь узнай и посмотри, какое слово мне возвратить пославшему меня!»','Преследователь назван в единственном числе; ответ выражен как возвращаемое слово.'),
('И Давид сказал Гаду: «Мне весьма тесно; пусть же мы впадём в руку Господа, ибо многочисленны Его милосердия, а в руку человека да не впаду я!»','Первое впадение имеет множественное число; рука и человек — единственное. Нет заключительной фразы о выборе мора при жатве пшеницы.'),
('И Господь дал мор в Израиле от утра до назначенного времени; и умерло из народа от Дана до Вирсавии семьдесят тысяч человек.','Нет отдельной фразы о том, что язва началась в народе.'),
('И ангел простёр свою руку к Иерусалиму, чтобы погубить его, и Господь пожалел о бедствии и сказал ангелу, губившему народ: «Довольно! Теперь опусти свою руку!» И ангел Господа был у гумна Орны иевусеянина.','У первого упоминания ангела нет отдельного определения Божий.'),
('И Давид сказал Господу, когда увидел ангела, поражавшего народ, и сказал: «Вот, я согрешил, и я поступил беззаконно; а эти овцы, что они сделали? Пусть же Твоя рука будет на мне и на доме моего отца!»','Давид не назван пастырем.'),
('И Гад пришёл к Давиду в тот день и сказал ему: «Поднимись, поставь Господу жертвенник на гумне Орны иевусеянина!»','Повеление явно говорит о подъёме.'),
('И Давид поднялся по слову Гада, как повелел Господь.','Сказано поднялся; Гад не назван здесь пророком.'),
('И Орна выглянул и увидел царя и его рабов, идущих к нему, и Орна вышел и поклонился царю лицом до земли.','Близко к еврейскому.'),
('И Орна сказал: «Почему мой господин царь пришёл к своему рабу?» И Давид сказал: «Чтобы купить у тебя гумно, чтобы построить жертвенник Господу, и да будет удержано поражение от народа».','Прекращение поражения выражено страдательно как его удержание от народа.'),
('И Орна сказал Давиду: «Пусть мой господин царь возьмёт и вознесёт то, что хорошо в его глазах! Вот волы для всесожжения и молотильные сани и принадлежности волов для дров.','Названы молотильные сани, а не повозки; сохранён образ глаз.'),
('Всё дал Орна, царь, царю». И Орна сказал царю: «Да примет тебя Господь, твой Бог!»','Орна назван царём; заключительная просьба говорит о принятии.'),
('И царь сказал Орне: «Нет, но я непременно куплю у тебя за цену и не вознесу Господу, моему Богу, всесожжения даром». И Давид купил гумно и волов за пятьдесят сиклей серебра.','Покупка усилена повтором корня; всесожжения стоят во множественном числе.'),
('И Давид построил там жертвенник Господу и вознёс всесожжения и мирные жертвы, и Господь внял мольбе за землю, и поражение было удержано от Израиля.','Израиль назван собирательно; прекращение поражения выражено страдательно.')
]}
created=[]
for lang,data in rows.items():
 assert len(data)==25
 p=Path(f'Tools/LiteralGen/outputs/{lang}/10_2SA/2SA_024.tsv');assert not p.exists()
 lines=[]
 for v,(literal,diff) in enumerate(data,1):
  assert len(diff.split())<=60 and '\t' not in literal+diff and '\n' not in literal+diff
  lines.append(f'{v}\t{literal}\t{diff}')
 with p.open('x') as f:f.write('\n'.join(lines)+'\n')
 created.append(str(p))
r=Path('.literalgen-state/de-en-ru/10_2SA-root-native-created.json');a=json.loads(r.read_text());a.extend(created);r.write_text(json.dumps(a,ensure_ascii=False,indent=2));print('Native024',len(created),'files',50,'rows exclusively created')
