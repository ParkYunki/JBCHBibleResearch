from pathlib import Path
import json
rows={
'de':[
('Und David war ein wenig über die Höhe hinausgegangen, und siehe, Ziba, der Diener Mephiboseths, kam ihm entgegen, und ein Paar Esel war gesattelt, und auf ihnen waren zweihundert Brote und hundert Rosinen und hundert Sommerfrüchte und ein Schlauch Wein.','Das Hebräische nennt Sommerfrüchte und einen Weinschlauch, ohne Kuchen oder Krug ausdrücklich zu nennen.'),
('Und der König sagte zu Ziba: „Was hast du da?“ Und Ziba sagte: „Die Esel sind für das Haus des Königs zum Reiten und das Brot und die Sommerfrüchte für die jungen Männer zum Essen und der Wein für den Müden in der Wüste zum Trinken.“','Das Hebräische nennt junge Männer und Sommerfrüchte; der Müde steht in der Einzahl.'),
('Und der König sagte: „Und wo ist der Sohn deines Herrn?“ Und Ziba sagte zum König: „Siehe, er wohnt in Jerusalem, denn er sagte: ‚Heute wird mir das Haus Israel das Königreich meines Vaters zurückgeben.‘“','Sein Wohnen ist als andauernde Tätigkeit ausgedrückt.'),
('Und der König sagte zu Ziba: „Siehe, dir gehört alles, was Mephiboseth gehört.“ Und Ziba sagte: „Ich habe mich niedergeworfen; möge ich Gnade in deinen Augen finden, mein Herr, der König!“','Das Niederwerfen steht als vollzogene Handlung; die Augen sind ausdrücklich genannt.'),
('Und der König David kam bis Bahurim, und siehe, von dort kam ein Mann aus der Sippe des Hauses Sauls heraus, und sein Name war Simei, der Sohn Geras; er kam fortwährend heraus und fluchte.','David wird ausdrücklich genannt; das Herauskommen ist wiederholt.'),
('Und er bewarf David mit Steinen und alle Knechte des Königs David; und alles Volk und alle Helden waren zu seiner Rechten und zu seiner Linken.','Das Hebräische verbindet die Aussagen mit und, ohne ausdrückliches denn.'),
('Und so sagte Simei, als er fluchte: „Heraus, heraus, du Mann des Blutes und Mann der Nichtswürdigkeit!','Das Hebräische sagt Mann des Blutes, ohne Hund zu nennen.'),
('Der HERR hat alles Blut des Hauses Sauls auf dich zurückgebracht, an dessen Stelle du regiert hast; und der HERR hat das Königtum in die Hand Absaloms, deines Sohnes, gegeben, und siehe, du bist in deinem Unheil, denn du bist ein Mann des Blutes!“','Das Hebräische sagt Mann des Blutes, ohne Hund zu nennen; es beschreibt das Zurückbringen des Blutes auf ihn.'),
('Und Abisai, der Sohn der Zeruja, sagte zum König: „Warum soll dieser tote Hund meinem Herrn, dem König, fluchen? Lass mich doch hinübergehen und seinen Kopf entfernen!“','Die Bitte zum Hinübergehen ist ausdrücklich markiert; das Entfernen des Kopfes folgt als eigener Wunsch.'),
('Und der König sagte: „Was habe ich mit euch zu tun, ihr Söhne der Zeruja? So möge er fluchen, denn der HERR hat ihm gesagt: ‚Fluche David!‘ Und wer wird sagen: ‚Warum hast du so gehandelt?‘“','Die letzte Frage blickt auf eine vollzogene Handlung zurück.'),
('Und David sagte zu Abisai und zu allen seinen Knechten: „Siehe, mein Sohn, der aus meinem Innern hervorgegangen ist, sucht meine Seele; wie viel mehr jetzt der Benjaminiter! Lasst ihn, dass er fluche, denn der HERR hat es ihm gesagt.','Das Hebräische verwendet die Bilder des Innern und der Seele.'),
('Vielleicht wird der HERR auf mein Auge sehen, und der HERR wird mir Gutes zurückgeben anstelle seines Fluches an diesem Tag.“','Das Hebräische nennt mein Auge statt Elend und wiederholt den Namen des HERRN.'),
('Und David und seine Männer gingen auf dem Weg; und Simei ging an der Seite des Berges ihm gegenüber, ging und fluchte und warf ihm gegenüber mit Steinen und warf Staub mit Staub.','Das Hebräische nennt Staub, nicht Erdklöße.'),
('Und der König und alles Volk, das bei ihm war, kamen müde an, und er erholte sich dort.','Nah am Hebräischen.'),
('Und Absalom und alles Volk, die Männer Israels, kamen nach Jerusalem, und Ahithophel war bei ihm.','Nah am Hebräischen.'),
('Und es geschah, als Husai, der Arachiter, Davids Freund, zu Absalom kam, da sagte Husai zu Absalom: „Es lebe der König! Es lebe der König!“','Husai und Absalom werden jeweils wiederholt genannt; der Zuruf wünscht dem König Leben.'),
('Und Absalom sagte zu Husai: „Ist das deine Güte gegenüber deinem Freund? Warum bist du nicht mit deinem Freund gegangen?“','Nah am Hebräischen.'),
('Und Husai sagte zu Absalom: „Nein, sondern wem der HERR und dieses Volk und alle Männer Israels erwählt haben, dem werde ich gehören, und bei ihm werde ich bleiben.','Nah am Hebräischen.'),
('Und zweitens: Wem soll ich dienen? Nicht vor seinem Sohn? Wie ich vor deinem Vater gedient habe, so werde ich vor dir sein.“','Nah am Hebräischen.'),
('Und Absalom sagte zu Ahithophel: „Gebt euch Rat! Was sollen wir tun?“','Die Aufforderung enthält ausdrücklich euch.'),
('Und Ahithophel sagte zu Absalom: „Geh zu den Nebenfrauen deines Vaters hinein, die er zurückgelassen hat, um das Haus zu bewahren; und ganz Israel wird hören, dass du deinem Vater stinkend geworden bist, und die Hände aller, die bei dir sind, werden stark werden.“','Das Hebräische nennt die Hände in der Mehrzahl und ihr Starkwerden.'),
('Und sie spannten Absalom das Zelt auf dem Dach auf, und Absalom ging zu den Nebenfrauen seines Vaters hinein vor den Augen ganz Israels.','Das Hebräische nennt das Zelt, nicht eine Hütte.'),
('Und der Rat Ahithophels, den er in jenen Tagen gab, war, wie wenn jemand das Wort Gottes befragte; so war aller Rat Ahithophels sowohl für David als auch für Absalom.','Das Wort Gottes ist ausdrücklich genannt; Ahithophels Rat wird wiederholt.')
],
'ru':[
('И Давид прошёл немного дальше вершины, и вот, Сива, слуга Мемфивосфея, навстречу ему, и пара ослов осёдланных, и на них двести хлебов и сто связок изюма и сто летних плодов и мех вина.','Названы осёдланные ослы и летние плоды, без отдельного слова смоквы.'),
('И царь сказал Сиве: «Что это у тебя?» И Сива сказал: «Ослы для дома царя, чтобы ездить, а хлеб и летние плоды, чтобы есть юношам, а вино, чтобы пить утомлённому в пустыне».','Названы летние плоды; утомлённый стоит в единственном числе.'),
('И царь сказал: «А где сын твоего господина?» И Сива сказал царю: «Вот, он живёт в Иерусалиме, ибо сказал: „Сегодня дом Израиля возвратит мне царство моего отца“».','Говорение выражено прошедшим временем; названо сегодня.'),
('И царь сказал Сиве: «Вот, тебе всё, что принадлежит Мемфивосфею». И Сива сказал: «Я поклонился; да найду милость в твоих глазах, мой господин царь!»','Поклонение передано отдельным высказыванием Сивы.'),
('И царь Давид пришёл до Бахурима, и вот, оттуда выходит человек из рода дома Саула, и имя его Семей, сын Геры; он всё выходил и проклинал.','Выход повторён и усилен.'),
('И он бросал камни в Давида и во всех рабов царя Давида; а весь народ и все богатыри были справа и слева от него.','Царь не назван повторно в конце стиха, там стоит местоименное указание.'),
('И так сказал Семей, проклиная: «Выходи, выходи, человек крови и человек негодности!','Сохранено повторение слова человек и образ человека крови.'),
('Господь возвратил на тебя всю кровь дома Саула, вместо которого ты царствовал, и Господь отдал царство в руку Авессалома, твоего сына, и вот, ты в своём бедствии, ибо ты человек крови!»','Рука стоит в единственном числе; сказано человек крови.'),
('И Авесса, сын Саруи, сказал царю: «Почему этот мёртвый пёс проклинает моего господина царя? Позволь мне, пожалуйста, перейти и снять его голову!»','Частица просьбы при переходе выражена явно.'),
('И царь сказал: «Что мне и вам, сыны Саруи? Пусть так проклинает, ибо Господь сказал ему: „Проклинай Давида!“ И кто скажет: „Почему ты так поступил?“»','Последний вопрос обращён к совершённому действию, а не к настоящему.'),
('И Давид сказал Авессе и всем своим рабам: «Вот, мой сын, который вышел из моих внутренностей, ищет мою душу; тем более теперь вениамитянин! Оставьте его, и пусть проклинает, ибо Господь сказал ему.','Нет отдельного если; вениамитянин не назван сыном вениамитянина.'),
('Может быть, Господь посмотрит на мой глаз, и Господь возвратит мне добро вместо его проклятия в этот день».','Еврейское выражение называет мой глаз вместо уничижения.'),
('И Давид и его люди шли по дороге, а Семей шёл по склону горы напротив него, шёл и проклинал, и бросал камни напротив него, и сыпал пылью.','Близко к еврейскому.'),
('И царь и весь народ, который был с ним, пришли утомлённые, и он освежился там.','Освежение имеет единственное число.'),
('И Авессалом и весь народ, люди Израиля, пришли в Иерусалим, и Ахитофел был с ним.','Близко к еврейскому.'),
('И было, когда Хусий Архитянин, друг Давида, пришёл к Авессалому, Хусий сказал Авессалому: «Да живёт царь! Да живёт царь!»','Близко к еврейскому.'),
('И Авессалом сказал Хусию: «Такова твоя милость к твоему другу? Почему ты не пошёл с твоим другом?»','Первая фраза передана вопросом.'),
('И Хусий сказал Авессалому: «Нет, но кого избрал Господь и этот народ и каждый человек Израиля, тому я буду принадлежать и с ним останусь.','Сказано буду принадлежать, без отдельного пойду вслед.'),
('И во-вторых, кому я буду служить? Не перед его ли сыном? Как я служил перед твоим отцом, так буду перед тобой».','Сохранён повтор предлога перед; в конце сказано буду, без отдельного служить.'),
('И Авессалом сказал Ахитофелу: «Дайте себе совет! Что нам делать?»','В повелении явно присутствует себе.'),
('И Ахитофел сказал Авессалому: «Войди к наложницам твоего отца, которых он оставил охранять дом, и весь Израиль услышит, что ты стал зловонным для твоего отца, и укрепятся руки всех, кто с тобой».','Сохранён образ зловония вместо ненавистности.'),
('И для Авессалома раскинули шатёр на крыше, и Авессалом вошёл к наложницам своего отца на глазах всего Израиля.','Близко к еврейскому.'),
('А совет Ахитофела, который он советовал в те дни, был как если бы кто спрашивал слово Бога; таков был весь совет Ахитофела и для Давида, и для Авессалома.','Совет в начале стоит в единственном числе; явно названо слово Бога.')
]}
created=[]
for lang,data in rows.items():
 assert len(data)==23
 p=Path(f'Tools/LiteralGen/outputs/{lang}/10_2SA/2SA_016.tsv');assert not p.exists()
 lines=[]
 for v,(literal,diff) in enumerate(data,1):
  assert len(diff.split())<=60 and '\t' not in literal+diff and '\n' not in literal+diff
  lines.append(f'{v}\t{literal}\t{diff}')
 with p.open('x') as f:f.write('\n'.join(lines)+'\n')
 created.append(str(p))
r=Path('.literalgen-state/de-en-ru/10_2SA-root-native-created.json');a=json.loads(r.read_text());a.extend(created);r.write_text(json.dumps(a,ensure_ascii=False,indent=2));print('Native016',len(created),'files',46,'rows exclusively created')
