from pathlib import Path
import json,re
D={}
D['de',8]='''An jenem Tag gab der König Ahasveros der Königin Esther das Haus Hamans, des Bedrängers der Juden; und Mardochai kam vor den König, denn Esther hatte mitgeteilt, was er ihr war.|Nah am Hebräischen.
Und der König nahm seinen Siegelring ab, den er Haman weggenommen hatte, und gab ihn Mardochai; und Esther setzte Mardochai über das Haus Hamans.|Nah am Hebräischen.
Und Esther redete erneut vor dem König und fiel vor seine Füße und weinte und flehte ihn an, das Böse Hamans, des Agagiters, und seinen Plan, den er gegen die Juden geplant hatte, wegzunehmen.|Der Plan steht im Singular; Plan und Planen wiederholen denselben Wortstamm.
Und der König streckte Esther das goldene Zepter entgegen; und Esther erhob sich und stand vor dem König.|Esther steht vor dem König; ein zusätzliches Herantreten ist nicht genannt.
Und sie sprach: „Wenn es dem König gut erscheint und wenn ich Gunst vor ihm gefunden habe und die Sache vor dem König recht ist und ich gut bin in seinen Augen, so werde geschrieben, die Briefe zurückzunehmen, den Plan Hamans, des Sohnes Hammedathas, des Agagiters, die er geschrieben hat, um die Juden in allen Provinzen des Königs zu vernichten.|Die Briefe sind ausdrücklich als Hamans Plan bezeichnet.
Denn wie werde ich es vermögen und das Unheil ansehen, das mein Volk treffen wird? Und wie werde ich es vermögen und die Vernichtung meiner Verwandtschaft ansehen?“|Das Vermögen wird in beiden Fragen ausdrücklich wiederholt.
Und der König Ahasveros sprach zur Königin Esther und zu Mardochai, dem Juden: „Siehe, das Haus Hamans habe ich Esther gegeben, und ihn haben sie an das Holz gehängt, weil er seine Hand gegen die Juden ausgestreckt hatte.|Nah am Hebräischen.
Und ihr, schreibt über die Juden, wie es gut ist in euren Augen, im Namen des Königs und versiegelt es mit dem Siegelring des Königs; denn eine Schrift, die im Namen des Königs geschrieben und mit dem Siegelring des Königs versiegelt ist, kann nicht zurückgenommen werden.“|Die Unwiderruflichkeit ist als Unmöglichkeit ausgedrückt.
Und die Schreiber des Königs wurden zu jener Zeit gerufen, im dritten Monat, das ist der Monat Sivan, an seinem dreiundzwanzigsten Tag; und es wurde nach allem geschrieben, was Mardochai geboten hatte, an die Juden und an die Satrapen und die Statthalter und die Obersten der Provinzen von Indien bis Kusch, hundertundsiebenundzwanzig Provinzen, Provinz und Provinz nach ihrer Schrift und Volk und Volk nach seiner Sprache, und an die Juden nach ihrer Schrift und ihrer Sprache.|Provinz und Volk werden jeweils wiederholt; Kusch wird beim Namen genannt.
Und er schrieb im Namen des Königs Ahasveros und versiegelte es mit dem Siegelring des Königs; und er sandte Briefe durch die Hand der Läufer auf Pferden, Reiter der königlichen Rennpferde, Söhne der Stuten,|Schreiben und Versiegeln stehen aktiv; genannt sind Pferde und Stutenfohlen statt junger Maultiere.
dass der König den Juden in Stadt und Stadt gestattet hatte, sich zu versammeln und für ihr Leben einzustehen, jede Streitmacht eines Volkes und einer Provinz, die sie bedrängten, zu vertilgen und zu töten und zu vernichten, Kinder und Frauen, und ihre Beute zu plündern,|Stadt wird wiederholt; Töten und Vernichten sind ausdrücklich nebeneinandergestellt.
an einem Tag in allen Provinzen des Königs Ahasveros, am dreizehnten des zwölften Monats, das ist der Monat Adar.|Nah am Hebräischen.
Eine Abschrift der Schrift sollte als Gesetz in Provinz und Provinz gegeben werden, allen Völkern offen bekannt, damit die Juden für diesen Tag bereit wären, sich an ihren Feinden zu rächen.|Genannt ist eine Abschrift; Provinz wird wiederholt.
Die Läufer, Reiter der königlichen Rennpferde, zogen aus, beschleunigt und gedrängt durch das Wort des Königs; und das Gesetz wurde in der Burg Susan gegeben.|Die Boten reiten königliche Pferde; das Gesetz wird gegeben, ohne ausdrückliches Anschlagen.
Und Mardochai ging vom Angesicht des Königs hinaus in königlicher Kleidung aus Blau und Weiß und mit einer großen goldenen Krone und einem Mantel aus Byssus und Purpur; und die Stadt Susan jauchzte und freute sich.|Nah am Hebräischen.
Den Juden war Licht und Freude und Wonne und Ehre.|Nah am Hebräischen.
Und in Provinz und Provinz und in Stadt und Stadt, an jedem Ort, wohin das Wort des Königs und sein Gesetz gelangten, war den Juden Freude und Wonne, ein Gastmahl und ein guter Tag; und viele aus den Völkern des Landes wurden Juden, denn die Furcht vor den Juden war auf sie gefallen.|Provinz und Stadt werden wiederholt; Gastmahl und guter Tag stehen im Singular.'''
D['ru',8]='''В тот день царь Артаксеркс дал царице Есфири дом Амана, врага Иудеев; и Мардохей пришёл пред лицо царя, ибо Есфирь рассказала, кем он ей был.|Близко к еврейскому.
И снял царь свой перстень, который отнял у Амана, и дал его Мардохею; и поставила Есфирь Мардохея над домом Амана.|Должность смотрителя отдельно не названа.
И Есфирь вновь говорила пред царём, и пала пред ногами его, и плакала, и умоляла его отвратить зло Амана, Агагитянина, и замысел его, который он замыслил против Иудеев.|Аман назван Агагитянином; повторены замысел и замыслил.
И простёр царь к Есфири золотой скипетр; и встала Есфирь, и стала пред лицом царя.|Близко к еврейскому.
И сказала: «Если царю благоугодно и если я нашла милость пред ним, и дело правильно пред лицом царя, и я хороша в глазах его, пусть будет написано возвратить письма, замысел Амана, сына Амадафа, Агагитянина, которые он написал, чтобы погубить Иудеев во всех областях царя.|Аман назван Агагитянином; письма прямо названы его замыслом.
Ибо как смогу я и увижу зло, которое постигнет народ мой? И как смогу я и увижу гибель родни моей?»|В обоих вопросах сохранено отдельное смогу.
И сказал царь Артаксеркс царице Есфири и Мардохею Иудеянину: «Вот, дом Амана я дал Есфири, а его повесили на дереве за то, что он простёр руку свою на Иудеев.|Близко к еврейскому.
А вы напишите об Иудеях, как хорошо в глазах ваших, от имени царя и запечатайте перстнем царя; ибо письмо, которое написано от имени царя и запечатано перстнем царя, нельзя возвратить».|Буквально говорится о возвращении письма.
И были созваны писцы царя в то время, в третий месяц, то есть месяц Сиван, в двадцать третий день его; и написано было по всему, что повелел Мардохей, к Иудеям и к сатрапам, и наместникам, и начальникам областей от Индии до Куша, ста двадцати семи областей, области и области по письму её, и народу и народу по языку его, и к Иудеям по письму их и по языку их.|Область и народ повторены; место названо Кушем.
И написал он от имени царя Артаксеркса, и запечатал перстнем царя, и послал письма рукою гонцов на конях, всадников на царских скакунах, сыновьях кобылиц,|Названы кони и потомство кобылиц, без дромадеров и мулов.
что царь позволил Иудеям в городе и городе собраться и встать за жизнь свою, истребить и убить и погубить всякое войско народа и области, теснивших их, детей и женщин, и добычу их разграбить,|Повторён город; названа всякая военная сила народа и области.
в один день во всех областях царя Артаксеркса, в тринадцатый день двенадцатого месяца, то есть месяца Адара.|Близко к еврейскому.
Копию письма надлежало дать как закон в области и области, открытый всем народам, чтобы Иудеи были готовы к этому дню отомстить врагам своим.|Область повторена.
Гонцы, всадники на царских скакунах, вышли, торопимые и понуждаемые словом царя; и закон был дан в Сузах, крепости.|Закон был дан; крепость названа вместо престольного города.
И Мардохей вышел от лица царя в царской одежде голубой и белой, и с большим золотым венцом, и в одеянии из виссона и пурпура; и город Сузы ликовал и радовался.|Близко к еврейскому.
У Иудеев были свет и радость, и веселье, и честь.|Названы свет и честь, вместо освещения и торжества.
И в области и области, и в городе и городе, в месте, куда доходило слово царя и закон его, у Иудеев были радость и веселье, пир и добрый день; и многие из народов земли становились Иудеями, ибо страх пред Иудеями пал на них.|Область и город повторены; становление Иудеями выражено продолжающимся действием.'''
D['de',9]='''Und im zwölften Monat, das ist der Monat Adar, an seinem dreizehnten Tag, als das Wort des Königs und sein Gesetz zur Ausführung gelangten, an dem Tag, da die Feinde der Juden gehofft hatten, über sie zu herrschen, da kehrte es sich um, sodass die Juden selbst über ihre Hasser herrschten.|Das Herrschen der Juden wird als eingetretene Umkehr beschrieben.
Die Juden versammelten sich in ihren Städten in allen Provinzen des Königs Ahasveros, um die Hand gegen die auszustrecken, die ihr Unheil suchten; und kein Mann stand vor ihnen, denn die Furcht vor ihnen war auf alle Völker gefallen.|Es heißt, kein Mann stand vor ihnen, ohne ausdrückliches Können.
Und alle Obersten der Provinzen und die Satrapen und die Statthalter und die das Werk des Königs taten, unterstützten die Juden; denn die Furcht vor Mardochai war auf sie gefallen.|Die Beamten werden als die bezeichnet, die das Werk des Königs tun.
Denn Mardochai war groß im Haus des Königs, und sein Ruf ging durch alle Provinzen; denn der Mann Mardochai wurde immer größer.|Der Mann Mardochai wird ausdrücklich erneut genannt.
Und die Juden schlugen alle ihre Feinde mit dem Schlag des Schwertes und mit Tötung und Vernichtung; und sie taten mit ihren Hassern nach ihrem Willen.|Ein Rauben ist hier nicht genannt.
Und in der Burg Susan töteten und vernichteten die Juden fünfhundert Mann,|Nah am Hebräischen.
und Parsandatha und Dalphon und Aspatha|Die Namen sind ohne zusätzliches Tötungsverb mit und verbunden.
und Poratha und Adalja und Aridatha|Die Namen sind jeweils durch und verbunden.
und Parmastha und Arisai und Aridai und Vajesatha,|Die Namen sind jeweils durch und verbunden.
die zehn Söhne Hamans, des Sohnes Hammedathas, des Bedrängers der Juden, töteten sie; aber nach der Beute streckten sie ihre Hand nicht aus.|Das Töten ist ausdrücklich genannt; Hand steht im Singular.
An jenem Tag kam die Zahl der Getöteten in der Burg Susan vor den König.|Nah am Hebräischen.
Und der König sprach zur Königin Esther: „In der Burg Susan haben die Juden fünfhundert Mann und die zehn Söhne Hamans getötet und vernichtet; was haben sie in den übrigen Provinzen des Königs getan? Und was ist deine Bitte? Sie werde dir gegeben. Und was ist noch dein Verlangen? Es werde getan.“|Die Frage nach den anderen Provinzen bezieht sich auf bereits Getanes.
Und Esther sprach: „Wenn es dem König gut erscheint, so werde auch morgen den Juden, die in Susan sind, gestattet, nach dem Gesetz von heute zu handeln; und die zehn Söhne Hamans sollen sie an das Holz hängen.“|Die Juden in Susan sind ausdrücklich bezeichnet.
Und der König befahl, dass so getan werde; und ein Gesetz wurde in Susan gegeben, und die zehn Söhne Hamans hängten sie auf.|Das Aufhängen steht aktiv mit ungenanntem Handelnden; ein Anschlagen des Gesetzes ist nicht genannt.
Und die Juden, die in Susan waren, versammelten sich auch am vierzehnten Tag des Monats Adar und töteten in Susan dreihundert Mann; aber nach der Beute streckten sie ihre Hand nicht aus.|Hand steht im Singular; die Beute ist ohne Besitzanzeige genannt.
Und die übrigen Juden in den Provinzen des Königs versammelten sich und standen für ihr Leben ein und hatten Ruhe vor ihren Feinden und töteten unter ihren Hassern fünfundsiebzigtausend; aber nach der Beute streckten sie ihre Hand nicht aus,|Hand steht im Singular; das Ruhen steht neben dem Einstehen für das Leben.
am dreizehnten Tag des Monats Adar; und an seinem vierzehnten ruhten sie und machten ihn zum Tag des Gastmahls und der Freude.|Das Machen des Festtags hat denselben Mehrzahlsbezug wie das Ruhen.
Und die Juden, die in Susan waren, hatten sich an seinem dreizehnten und an seinem vierzehnten versammelt und ruhten an seinem fünfzehnten und machten ihn zum Tag des Gastmahls und der Freude.|Die Juden selbst machten den Tag zum Festtag.
Darum machen die Juden auf dem offenen Land, die in den offenen Städten wohnen, den vierzehnten Tag des Monats Adar zu Freude und Gastmahl und einem guten Tag und zum Senden von Anteilen, einer an seinen Nächsten.|Das Feiern steht gegenwärtig; genannt sind ein guter Tag und das Senden von Anteilen.
Und Mardochai schrieb diese Worte und sandte Briefe an alle Juden in allen Provinzen des Königs Ahasveros, die nahen und die fernen,|Nah am Hebräischen.
um ihnen festzusetzen, dass sie den vierzehnten Tag des Monats Adar und seinen fünfzehnten Tag Jahr für Jahr halten sollten,|Jahr wird wiederholt.
entsprechend den Tagen, an denen die Juden vor ihren Feinden ruhten, und dem Monat, der ihnen von Kummer zu Freude und von Trauer zu einem guten Tag verwandelt worden war, um sie zu Tagen des Gastmahls und der Freude zu machen und des Sendens von Anteilen, einer an seinen Nächsten, und von Gaben an die Bedürftigen.|Der gute Tag steht im Singular; Anteile und Gaben sind getrennt benannt.
Und die Juden nahmen an, was sie zu tun begonnen hatten und was Mardochai ihnen geschrieben hatte.|Nah am Hebräischen.
Denn Haman, der Sohn Hammedathas, der Agagiter, der Bedränger aller Juden, hatte gegen die Juden geplant, sie zu vernichten, und Pur, das ist das Los, geworfen, sie zu verwirren und zu vernichten.|Haman warf das Los; ein gesondertes Werfenlassen ist nicht genannt.
Und als sie vor den König kam, befahl er durch den Brief, sein böser Plan, den er gegen die Juden geplant hatte, solle auf seinen Kopf zurückkehren; und sie sollten ihn und seine Söhne an das Holz hängen.|Esther wird hier nicht beim Namen genannt; der Plan steht im Singular.
Darum nannten sie diese Tage Purim nach dem Namen Pur. Darum, wegen aller Worte dieses Briefes und dessen, was sie dabei gesehen hatten und was ihnen widerfahren war,|Der Name Pur wird ausdrücklich wiederholt; auch darum steht zweimal.
setzten die Juden es fest und nahmen es auf sich und auf ihren Samen und auf alle, die sich ihnen anschlossen, dass es nicht vergehen sollte, diese beiden Tage nach ihrer Vorschrift und zu ihrer festgesetzten Zeit Jahr für Jahr zu halten.|Die Nachkommen werden als Same bezeichnet; Jahr wird wiederholt.
Und diese Tage sollten in Generation und Generation, Familie und Familie, Provinz und Provinz und Stadt und Stadt erinnert und gehalten werden; und diese Tage Purim sollten unter den Juden nicht vergehen, und ihr Gedächtnis sollte bei ihrem Samen nicht aufhören.|Generation, Familie, Provinz und Stadt werden jeweils wiederholt; genannt ist der Same.
Und die Königin Esther, die Tochter Abihails, und Mardochai, der Jude, schrieben mit aller Vollmacht, um diesen zweiten Purimbrief zu bestätigen.|Genannt ist volle Macht statt Ernst.
Und er sandte Briefe an alle Juden in hundertundsiebenundzwanzig Provinzen des Königreichs Ahasveros, Worte des Friedens und der Wahrheit,|Friede und Wahrheit sind ausdrücklich als Hauptwörter genannt.
um diese Tage Purim zu ihren festgesetzten Zeiten zu bestätigen, wie Mardochai, der Jude, und die Königin Esther sie ihnen festgesetzt hatten und wie sie sich selbst und ihrem Samen die Angelegenheiten der Fasten und ihres Hilfeschreis festgesetzt hatten.|Die Nachkommen heißen Same; die Fasten stehen in der Mehrzahl.
Und der Befehl Esthers bestätigte diese Angelegenheiten des Purim; und es wurde in das Buch geschrieben.|Esthers Befehl ist das Subjekt des Bestätigens; das Buch ist bestimmt.'''
D['ru',9]='''И в двенадцатый месяц, то есть месяц Адар, в тринадцатый день его, когда пришло время исполниться слову царя и закону его, в день, когда враги Иудеев надеялись властвовать над ними, вышло наоборот: сами Иудеи стали властвовать над ненавидящими их.|Близко к еврейскому.
Собрались Иудеи в городах своих во всех областях царя Артаксеркса, чтобы простереть руку на ищущих зла им; и никто не устоял пред ними, ибо страх пред ними пал на все народы.|Сказано, что никто не устоял; способность отдельно не названа.
И все начальники областей и сатрапы, и наместники, и делающие работу царя поддерживали Иудеев, ибо страх пред Мардохеем пал на них.|Близко к еврейскому.
Ибо велик был Мардохей в доме царя, и весть о нём шла по всем областям, ибо этот муж Мардохей становился всё более великим.|Повторено имя Мардохея; величие выражено продолжающимся возрастанием.
И поразили Иудеи всех врагов своих ударом меча, и убийством, и истреблением; и поступали с ненавидящими их по желанию своему.|Действия названы также существительными: удар, убийство и истребление.
И в Сузах, крепости, убили и погубили Иудеи пятьсот человек,|Названа крепость вместо престольного города.
и Паршандафу, и Далфона, и Асфафу,|Близко к еврейскому.
и Порафу, и Адалью, и Аридафу,|Близко к еврейскому.
и Пармашфу, и Арисая, и Аридая, и Ваиезафу,|Близко к еврейскому.
десятерых сыновей Амана, сына Амадафа, врага Иудеев, убили они; но на добычу не простёрли руки своей.|Близко к еврейскому.
В тот день число убитых в Сузах, крепости, пришло пред лицо царя.|Число приходит пред царя; отдельные сообщавшие не названы.
И сказал царь царице Есфири: «В Сузах, крепости, убили и погубили Иудеи пятьсот человек и десятерых сыновей Амана; что сделали они в остальных областях царя? И каково прошение твоё? Да будет дано тебе. И какова ещё просьба твоя? Да будет исполнена».|Названа крепость вместо престольного города.
И сказала Есфирь: «Если царю благоугодно, пусть будет дано и завтра Иудеям, которые в Сузах, делать по закону сегодняшнего дня; и десятерых сыновей Амана пусть повесят на дереве».|Сказано по закону сегодняшнего дня, а не только то же, что сегодня.
И повелел царь сделать так; и дан был закон в Сузах, и десятерых сыновей Амана повесили.|Близко к еврейскому.
И собрались Иудеи, которые в Сузах, также в четырнадцатый день месяца Адара, и убили в Сузах триста человек; но на добычу не простёрли руки своей.|Близко к еврейскому.
И остальные Иудеи, которые в областях царя, собрались, и встали за жизнь свою, и имели покой от врагов своих, и убили среди ненавидящих их семьдесят пять тысяч; но на добычу не простёрли руки своей,|Защита жизни и покой перечислены как действия рядом с собранием.
в тринадцатый день месяца Адара; и покоились в четырнадцатый день его, и сделали его днём пира и радости.|Близко к еврейскому.
А Иудеи, которые в Сузах, собрались в тринадцатый день его и в четырнадцатый день его, и покоились в пятнадцатый день его, и сделали его днём пира и радости.|Близко к еврейскому.
Поэтому Иудеи сельские, живущие в открытых городах, делают четырнадцатый день месяца Адара радостью и пиром, и добрым днём, и посыланием долей, каждый ближнему своему.|Названы открытые города и посылание долей.
И написал Мардохей эти слова, и послал письма ко всем Иудеям во всех областях царя Артаксеркса, близким и далёким,|Близко к еврейскому.
чтобы установить им соблюдение четырнадцатого дня месяца Адара и пятнадцатого дня его год за годом,|Год повторён.
как дней, в которые Иудеи покоились от врагов своих, и месяца, который обратился для них из печали в радость и из плача в добрый день, чтобы сделать их днями пира и радости, и посылания долей, каждый ближнему своему, и даров нуждающимся.|Доли и дары названы разными словами.
И приняли Иудеи то, что начали делать, и то, что Мардохей написал им.|Близко к еврейскому.
Ибо Аман, сын Амадафа, Агагитянин, враг всех Иудеев, замыслил против Иудеев погубить их и бросил пур, то есть жребий, чтобы привести их в смятение и погубить их.|Назван Агагитянин; цель жребия выражена также как приведение в смятение.
И когда она пришла пред царя, он повелел письмом: пусть возвратится злой замысел его, который он замыслил против Иудеев, на голову его; и пусть повесят его и сыновей его на дереве.|Есфирь здесь не названа по имени; письмо не названо новым.
Поэтому назвали эти дни Пурим по имени пур. Поэтому, из-за всех слов этого письма и того, что они видели в этом и что постигло их,|Поэтому повторено дважды.
установили Иудеи и приняли на себя и на семя своё, и на всех присоединяющихся к ним, чтобы не проходило соблюдение этих двух дней по предписанию их и по времени их год за годом.|Потомки названы семенем; год повторён.
И эти дни должны быть памятны и соблюдаемы в роде и роде, семье и семье, области и области и городе и городе; и эти дни Пурим не пройдут среди Иудеев, и память о них не прекратится у семени их.|Род, семья, область и город повторены; потомки названы семенем.
И написала царица Есфирь, дочь Абихаила, и Мардохей Иудеянин со всей силой, чтобы подтвердить это второе письмо о Пуриме.|Письмо названо вторым вместо нового; действие — подтвердить.
И он послал письма ко всем Иудеям в сто двадцать семь областей царства Артаксеркса, слова мира и истины,|Послал стоит в единственном числе.
чтобы подтвердить эти дни Пурим в назначенные времена их, как установили им Мардохей Иудеянин и царица Есфирь и как они установили для себя и для семени своего дела постов и вопля своего.|Названы дела постов и вопля; потомки названы семенем.
И повеление Есфири подтвердило эти дела Пурима; и было записано в книгу.|Близко к еврейскому.'''
D['de',10]='''Und der König Ahasveros legte eine Abgabe auf das Land und die Inseln des Meeres.|Nah am Hebräischen.
Und alles Werk seiner Kraft und seiner Macht und die genaue Darstellung der Größe Mardochais, den der König groß gemacht hatte, sind sie nicht im Buch der Worte der Tage der Könige von Medien und Persien geschrieben?|Der Satz fragt, ob es nicht geschrieben ist; das Großmachen Mardochais ist ausdrücklich als Handlung bezeichnet.
Denn Mardochai, der Jude, war der Zweite nach dem König Ahasveros und groß bei den Juden und wohlgefällig der Menge seiner Brüder, Gutes für sein Volk suchend und Frieden redend zu seinem ganzen Samen.|Genannt sind Frieden und Same statt das Beste und Geschlecht.'''
D['ru',10]='''И наложил царь Артаксеркс подать на землю и острова моря.|Близко к еврейскому.
И все дела силы его и могущества его, и подробное изложение величия Мардохея, которого возвеличил царь, разве не записаны они в книге слов дней царей Мидии и Персии?|Сохранён вопрос: разве не записаны они.
Ибо Мардохей Иудеянин был вторым после царя Артаксеркса и великим у Иудеев, и угодным множеству братьев своих, ищущим добра народу своему и говорящим мир всему семени своему.|Названы мир и семя вместо блага и племени.'''
if __name__=='__main__':
 created=[]
 for (lang,ch),body in D.items():
  values=[line.split('|') for line in body.splitlines()]
  assert len(values)=={8:17,9:32,10:3}[ch], (lang,ch,len(values))
  for p in sorted(Path('Tools/LiteralGen/packets/de-en-ru/17_EST').glob(f'EST_{ch:03d}*.txt')):
   block=next(b for b in p.read_text().split('==TARGET ')[1:] if b.startswith('lang='+lang+' '))
   verses=[int(v) for v in re.findall(r'^#(\d+) ',block,re.M)]
   dest=Path('Tools/LiteralGen/outputs')/lang/'17_EST'/(p.stem+'.tsv');dest.parent.mkdir(parents=True,exist_ok=True)
   text=''.join(str(v)+'\t'+'\t'.join(values[v-1])+'\n' for v in verses)
   assert all(len(x)==2 and len(x[1].split())<=60 for x in values)
   with dest.open('x') as f:f.write(text)
   created.append(str(dest.resolve()))
 state=Path('.literalgen-state/de-en-ru')
 (state/'est-c-checkpoint.json').write_text(json.dumps({'book':'17_EST','chapters':[8,9,10],'created':created,'files':len(created),'rows':104,'status':'native_created_en_review_pending'},ensure_ascii=False,indent=2)+'\n')
 (state/'est-c-qa.json').write_text('[]\n')
 print(json.dumps({'files':len(created),'rows':104}))
