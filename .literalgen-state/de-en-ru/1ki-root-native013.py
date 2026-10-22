from pathlib import Path
import json,re
rows={
'de':[
('Und siehe, ein Mann Gottes kam aus Juda nach dem Wort des HERRN nach Beth-El, und Jerobeam stand auf dem Altar, um zu räuchern.','Das Hebräische sagt auf dem Altar.'),
('Und er rief gegen den Altar nach dem Wort des HERRN und sagte: „Altar, Altar! So hat der HERR gesagt: ‚Siehe, ein Sohn wird dem Haus Davids geboren, Josia sein Name; und er wird auf dir die Priester der Höhen opfern, die auf dir räuchern, und Menschengebeine werden sie auf dir verbrennen.‘“','Das Verb beim Verbrennen hat im Hebräischen eine ungenannte Mehrzahl als Subjekt.'),
('Und er gab an jenem Tag ein Zeichen und sagte: „Dies ist das Zeichen, das der HERR geredet hat: Siehe, der Altar wird zerrissen, und die Asche darauf wird ausgeschüttet.“','Das Zeichen selbst ist als das bezeichnet, was der HERR geredet hat.'),
('Und es geschah, als der König das Wort des Mannes Gottes hörte, der gegen den Altar in Beth-El gerufen hatte, da streckte Jerobeam seine Hand vom Altar aus und sagte: „Packt ihn!“ Und seine Hand, die er gegen ihn ausgestreckt hatte, verdorrte, und er konnte sie nicht zu sich zurückziehen.','Jerobeam ist beim Ausstrecken ausdrücklich genannt; die Hand wird vom Altar ausgestreckt.'),
('Und der Altar wurde zerrissen, und die Asche wurde vom Altar ausgeschüttet nach dem Zeichen, das der Mann Gottes nach dem Wort des HERRN gegeben hatte.','Das Zerreißen des Altars ist passiv ausgedrückt.'),
('Und der König antwortete und sagte zum Mann Gottes: „Besänftige doch das Angesicht des HERRN, deines Gottes, und bete für mich, damit meine Hand zu mir zurückkehrt!“ Und der Mann Gottes besänftigte das Angesicht des HERRN, und die Hand des Königs kehrte zu ihm zurück und wurde wie zuvor.','Das Zurückkehren der Hand ist aktiv erzählt, nicht als Zurückbringen.'),
('Und der König redete zum Mann Gottes: „Komm mit mir ins Haus und stärke dich, und ich werde dir ein Geschenk geben!“','Nah am Hebräischen.'),
('Und der Mann Gottes sagte zum König: „Wenn du mir die Hälfte deines Hauses gibst, werde ich nicht mit dir kommen, und ich werde kein Brot essen und kein Wasser an diesem Ort trinken.','Das Hebräische verbindet die Verneinungen mit und, ohne ausdrückliches denn.'),
('Denn so hat er mir nach dem Wort des HERRN befohlen und gesagt: ‚Du sollst kein Brot essen und kein Wasser trinken und nicht auf dem Weg zurückkehren, den du gegangen bist.‘“','Das Befehlen hat eine ungenannte Einzahl als aktives Subjekt.'),
('Und er ging auf einem anderen Weg und kehrte nicht auf dem Weg zurück, auf dem er nach Beth-El gekommen war.','Nah am Hebräischen.'),
('Und ein alter Prophet wohnte in Beth-El, und sein Sohn kam und erzählte ihm die ganze Tat, die der Mann Gottes heute in Beth-El getan hatte; die Worte, die er zum König geredet hatte, erzählten sie ihrem Vater.','Zuerst kommt und erzählt sein Sohn in der Einzahl; danach erzählen sie ihrem Vater.'),
('Und ihr Vater redete zu ihnen: „Welchen Weg ist er gegangen?“ Und seine Söhne hatten den Weg gesehen, den der Mann Gottes gegangen war, der aus Juda gekommen war.','Das Hebräische sagt, dass die Söhne den Weg gesehen hatten, nicht dass sie ihn zeigten.'),
('Und er sagte zu seinen Söhnen: „Sattelt mir den Esel!“ Und sie sattelten ihm den Esel, und er ritt darauf.','Das Satteln und Reiten sind eigene mit und verbundene Handlungen.'),
('Und er ging dem Mann Gottes nach und fand ihn unter der Terebinthe sitzen und sagte zu ihm: „Bist du der Mann Gottes, der aus Juda gekommen ist?“ Und er sagte: „Ich bin es.“','Das Hebräische nennt eine Terebinthe; die Antwort hat ein ausdrückliches Ich.'),
('Und er sagte zu ihm: „Geh mit mir ins Haus und iss Brot!“','Nah am Hebräischen.'),
('Und er sagte: „Ich kann nicht mit dir umkehren und mit dir kommen, und ich werde kein Brot essen und mit dir kein Wasser an diesem Ort trinken.','Nah am Hebräischen.'),
('Denn er hat zu mir nach dem Wort des HERRN geredet: ‚Du sollst kein Brot essen und dort kein Wasser trinken; du sollst nicht zurückkehren, um auf dem Weg zu gehen, auf dem du gegangen bist.‘“','Das Reden hat eine ungenannte Einzahl als aktives Subjekt.'),
('Und er sagte zu ihm: „Auch ich bin ein Prophet wie du, und ein Engel hat zu mir nach dem Wort des HERRN geredet und gesagt: ‚Bringe ihn mit dir in dein Haus zurück, damit er Brot isst und Wasser trinkt.‘“ Er log ihm.','Nah am Hebräischen.'),
('Und er kehrte mit ihm zurück und aß Brot in seinem Haus und trank Wasser.','Das Zurückkehren hat den Reisenden als aktives Subjekt, statt eines Zurückführens.'),
('Und es geschah, als sie am Tisch saßen, da geschah das Wort des HERRN zu dem Propheten, der ihn zurückgebracht hatte.','Nah am Hebräischen.'),
('Und er rief dem Mann Gottes, der aus Juda gekommen war, zu und sagte: „So hat der HERR gesagt: ‚Weil du dem Mund des HERRN widerspenstig gewesen bist und das Gebot nicht bewahrt hast, das der HERR, dein Gott, dir geboten hatte,','Nah am Hebräischen.'),
('und zurückgekehrt bist und Brot gegessen und Wasser getrunken hast an dem Ort, von dem er zu dir geredet hatte: Du sollst kein Brot essen und kein Wasser trinken, wird dein Leichnam nicht ins Grab deiner Väter kommen.‘“','Der frühere Sprecher ist mit er bezeichnet, nicht mit ich.'),
('Und es geschah, nachdem er Brot gegessen und nachdem er getrunken hatte, da sattelte er ihm den Esel, dem Propheten, den er zurückgebracht hatte.','Das Satteln hat eine ungenannte Einzahl als aktives Subjekt.'),
('Und er ging, und ein Löwe fand ihn auf dem Weg und tötete ihn; und sein Leichnam war auf den Weg geworfen, und der Esel stand neben ihm, und der Löwe stand neben dem Leichnam.','Nah am Hebräischen.'),
('Und siehe, Männer gingen vorüber und sahen den Leichnam auf den Weg geworfen und den Löwen neben dem Leichnam stehen; und sie kamen und redeten in der Stadt, in der der alte Prophet wohnte.','Das Hebräische enthält ausdrücklich siehe.'),
('Und der Prophet, der ihn vom Weg zurückgebracht hatte, hörte es und sagte: „Er ist der Mann Gottes, der dem Mund des HERRN widerspenstig gewesen ist; und der HERR gab ihn dem Löwen, und der zerbrach ihn und tötete ihn nach dem Wort des HERRN, das er zu ihm geredet hatte.“','Das Zurückbringen geschieht ausdrücklich vom Weg; der Löwe zerbricht ihn.'),
('Und er redete zu seinen Söhnen und sagte: „Sattelt mir den Esel!“ Und sie sattelten.','Das Satteln ist eine eigene Hauptaussage ohne ausdrückliches Objekt.'),
('Und er ging und fand seinen Leichnam auf den Weg geworfen, und der Esel und der Löwe standen neben dem Leichnam; der Löwe hatte den Leichnam nicht gefressen und den Esel nicht zerbrochen.','Das Hebräische nennt das Nichtfressen des ganzen Leichnams und das Nichtzerbrechen des Esels.'),
('Und der Prophet hob den Leichnam des Mannes Gottes auf und legte ihn auf den Esel und brachte ihn zurück und kam in die Stadt des alten Propheten, um ihn zu beklagen und zu begraben.','Das Beklagen und Begraben stehen als Ziele seines Kommens, ohne eigenes sie.'),
('Und er legte seinen Leichnam in sein Grab, und sie klagten um ihn: „Wehe, mein Bruder!“','Mein Bruder enthält ausdrücklich den Besitzbezug.'),
('Und es geschah, nachdem er ihn begraben hatte, da sagte er zu seinen Söhnen: „Wenn ich sterbe, sollt ihr mich in dem Grab begraben, in dem der Mann Gottes begraben ist; neben seine Gebeine legt meine Gebeine!','Das Begraben vor der Rede steht in der Einzahl, nicht sie.'),
('Denn gewiss wird das Wort geschehen, das er nach dem Wort des HERRN gegen den Altar in Beth-El und gegen alle Häuser der Höhen in den Städten Samarias gerufen hat.“','Das Geschehen ist durch Wiederholung des Verbstamms bekräftigt.'),
('Nach dieser Sache kehrte Jerobeam nicht von seinem bösen Weg zurück, und er machte wieder aus dem ganzen Volk Priester der Höhen; wer Lust hatte, dem füllte er die Hand, und er wurde Priester der Höhen.','Der Anwärter hat Lust; das Machen der Priester geschieht erneut.'),
('Und diese Sache wurde dem Haus Jerobeams zur Sünde, um es auszutilgen und von der Fläche des Erdbodens zu vernichten.','Die Fläche des Erdbodens ist ausdrücklich genannt.')
],
'ru':[
('И вот, человек Бога пришёл из Иудеи по слову Господа в Вефиль, и Иеровоам стоял на жертвеннике, чтобы воскурять.','Сказано на жертвеннике.'),
('И он воззвал против жертвенника по слову Господа и сказал: «Жертвенник, жертвенник! Так сказал Господь: „Вот, сын рождается дому Давида, Иосия его имя; и он принесёт на тебе в жертву священников высот, воскуряющих на тебе, и человеческие кости сожгут на тебе“».','У сожжения человеческих костей неназванное множественное подлежащее.'),
('И он дал в тот день знамение, говоря: «Это знамение, которое изрёк Господь: вот, жертвенник будет разорван, и пепел, который на нём, будет высыпан».','Разрыв жертвенника и высыпание пепла выражены страдательно.'),
('И было, когда царь услышал слово человека Бога, который воззвал против жертвенника в Вефиле, Иеровоам простёр свою руку от жертвенника, говоря: «Схватите его!» И его рука, которую он простёр против него, высохла, и он не мог возвратить её к себе.','Рука высохла, а не одеревенела.'),
('И жертвенник был разорван, и пепел был высыпан с жертвенника, по знамению, которое человек Бога дал по слову Господа.','Разрыв и высыпание выражены страдательно.'),
('И царь ответил и сказал человеку Бога: «Умилостиви же лицо Господа, твоего Бога, и помолись обо мне, и моя рука возвратится ко мне!» И человек Бога умилостивил лицо Господа, и рука царя возвратилась к нему и стала как прежде.','Царь не назван Иеровоамом в этом стихе; возвращение руки не имеет отдельного глагола возможности.'),
('И царь сказал человеку Бога: «Приди со мной в дом и подкрепись, и я дам тебе подарок!»','Нет отдельного слова пища.'),
('И человек Бога сказал царю: «Если ты дашь мне половину твоего дома, я не пойду с тобой и не буду есть хлеба и не буду пить воды в этом месте.','Близко к еврейскому.'),
('Ибо так он заповедал мне по слову Господа, говоря: „Не ешь хлеба и не пей воды и не возвращайся дорогой, которой ты шёл“».','Заповедь имеет неназванное единственное действующее подлежащее; здесь нет отдельного там.'),
('И он пошёл другой дорогой и не возвратился дорогой, которой пришёл в Вефиль.','Близко к еврейскому.'),
('А один старый пророк жил в Вефиле, и его сын пришёл и рассказал ему всё дело, которое человек Бога сделал сегодня в Вефиле; слова, которые он говорил царю, они рассказали своему отцу.','В последней части сыновья отдельно не названы.'),
('И их отец сказал им: «Какой дорогой он пошёл?» И его сыновья видели дорогу, которой пошёл человек Бога, пришедший из Иудеи.','Сыновья видели дорогу, а не показали её.'),
('И он сказал своим сыновьям: «Оседлайте мне осла!» И они оседлали ему осла, и он сел на него.','Близко к еврейскому.'),
('И он пошёл за человеком Бога и нашёл его сидящим под теревинфом и сказал ему: «Ты ли человек Бога, пришедший из Иудеи?» И он сказал: «Я».','Назван теревинф, а не дуб.'),
('И он сказал ему: «Пойди со мной в дом и поешь хлеба!»','Прямо сказано со мной.'),
('И он сказал: «Я не могу возвратиться с тобой и прийти с тобой, и не буду есть хлеба и не буду пить с тобой воды в этом месте.','С тобой повторяется при возвращении и приходе.'),
('Ибо он говорил мне по слову Господа: „Не ешь хлеба и не пей там воды; не возвращайся, чтобы идти дорогой, которой ты шёл“».','Говорение имеет неназванное единственное действующее подлежащее.'),
('И он сказал ему: «Также и я пророк, как ты, и ангел говорил мне по слову Господа, говоря: „Возврати его с собой в твой дом, и пусть он поест хлеба и выпьет воды“». Он солгал ему.','Прямо сказано с собой.'),
('И он возвратился с ним и ел хлеб в его доме и пил воду.','Близко к еврейскому.'),
('И было, они сидели у стола, и было слово Господа к пророку, который возвратил его.','Нет отдельного ещё.'),
('И он воззвал к человеку Бога, который пришёл из Иудеи, говоря: «Так сказал Господь: „За то, что ты воспротивился устам Господа и не сохранил заповедь, которую Господь, твой Бог, заповедал тебе,','Близко к еврейскому.'),
('и возвратился и ел хлеб и пил воду в месте, о котором Он говорил тебе: Не ешь хлеба и не пей воды, твой труп не придёт в гробницу твоих отцов“».','Тело названо трупом.'),
('И было после того, как он ел хлеб и после того, как он пил, он оседлал ему осла, пророку, которого он возвратил.','Еда и питьё имеют отдельные повторённые после того.'),
('И он пошёл, и лев нашёл его на дороге и умертвил его, и его труп был брошен на дороге, и осёл стоял рядом с ним, и лев стоял рядом с трупом.','Тело названо трупом.'),
('И вот, люди проходили и увидели труп, брошенный на дороге, и льва, стоящего рядом с трупом; и пришли и рассказали в городе, в котором жил старый пророк.','Тело названо трупом.'),
('И пророк, который возвратил его с дороги, услышал и сказал: «Это человек Бога, который воспротивился устам Господа; и Господь предал его льву, и тот изломал его и умертвил его, по слову Господа, которое Он изрёк ему».','Близко к еврейскому.'),
('И он говорил своим сыновьям, говоря: «Оседлайте мне осла!» И они оседлали.','Близко к еврейскому.'),
('И он пошёл и нашёл его труп брошенным на дороге, и осёл и лев стояли рядом с трупом; лев не съел трупа и не изломал осла.','Тело названо трупом.'),
('И пророк поднял труп человека Бога и положил его на осла и возвратил его, и пришёл в город старого пророка, чтобы оплакать и похоронить его.','Приход в город не имеет отдельно названного подлежащего старый пророк.'),
('И он положил его труп в своей гробнице, и они оплакивали его: «Увы, мой брат!»','Оплакивание имеет множественное подлежащее.'),
('И было после того, как он похоронил его, он сказал своим сыновьям, говоря: «Когда я умру, похороните меня в гробнице, в которой погребён человек Бога; рядом с его костями положите мои кости!','Погребение перед речью имеет действующее подлежащее он.'),
('Ибо непременно сбудется слово, которое он воззвал по слову Господа против жертвенника в Вефиле и против всех домов высот, которые в городах Самарии».','Исполнение усилено повтором корня; прямо названы дома высот.'),
('После этого дела Иеровоам не возвратился со своего злого пути и вновь сделал из народа священников высот; кто хотел, тому он наполнял руку, и он становился священником высот.','Посвящение выражено образом наполнения руки.'),
('И это дело стало грехом дому Иеровоама, чтобы истребить и уничтожить с лица земли.','Цели истребления и уничтожения переданы отдельными глаголами.')
]}
for a in rows.values():assert len(a)==34
r=Path('Tools/LiteralGen');created=[]
for lang,data in rows.items():
 for packet in sorted((r/'packets/de-en-ru/11_1KI').glob('*_013*.txt')):
  b=next(x for x in packet.read_text().split('==TARGET ')[1:] if x.startswith('lang='+lang+' '));vs=[int(x) for x in re.findall(r'^#(\d+) ',b,re.M)];p=r/'outputs'/lang/'11_1KI'/(packet.stem+'.tsv');assert not p.exists();p.parent.mkdir(parents=True,exist_ok=True);out=[]
  for v in vs:
   a,b=data[v-1];assert len(b.split())<=60 and '\t' not in a+b and '\n' not in a+b;out.append(f'{v}\t{a}\t{b}')
  with p.open('x') as f:f.write('\n'.join(out)+'\n')
  created.append(str(p))
q=Path('.literalgen-state/de-en-ru/11_1KI-root-native-created.json');a=json.loads(q.read_text());a.extend(created);q.write_text(json.dumps(a,ensure_ascii=False,indent=2));print('Native013',len(created),'files',68,'rows exclusively created')
