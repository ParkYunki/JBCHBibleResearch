# coding: utf-8
exec(open('.literalgen-state/de-en-ru/1ch-c-write.py').read())
de='''Und David und die Obersten des Heeres sonderten zum Dienst die Söhne Asaphs und Hemans und Jedithuns ab, die mit Leiern, Harfen und Zimbeln weissagten; und ihre Zahl war die der Männer der Arbeit für ihren Dienst.
Von den Söhnen Asaphs: Sakkur und Joseph und Nethanja und Asarela, die Söhne Asaphs, unter der Hand Asaphs, der unter den Händen des Königs weissagte.
Von Jedithun: die Söhne Jedithuns: Gedalja und Sori und Jesaja, Hasabja und Matthithja, sechs, unter den Händen ihres Vaters Jedithun, der mit der Leier weissagte, um dem HERRN zu danken und ihn zu loben.
Von Heman: die Söhne Hemans: Bukkia, Matthanja, Usiel, Sebuel und Jerimoth, Hananja, Hanani, Eliatha, Giddalthi und Romamthi-Eser, Josbekasa, Mallothi, Hothir, Mahesioth.
Alle diese waren Söhne Hemans, des Sehers des Königs in den Worten Gottes, um ein Horn zu erheben; und Gott gab Heman vierzehn Söhne und drei Töchter.
Alle diese waren unter den Händen ihres Vaters beim Gesang des Hauses des HERRN mit Zimbeln, Harfen und Leiern zum Dienst des Hauses Gottes; unter den Händen des Königs waren Asaph und Jedithun und Heman.
Und ihre Zahl mit ihren Brüdern, die im Gesang für den HERRN gelehrt waren, jeder Verständige, war zweihundertachtundachtzig.
Und sie warfen Lose für den Dienst, den Kleinen ebenso wie den Großen, den Verständigen mit dem Lernenden.
Und das erste Los kam für Asaph auf Joseph heraus; das zweite auf Gedalja, er und seine Brüder und seine Söhne, zwölf.'''.splitlines()
ru='''И отделили Давид и начальники войска для служения сынов Асафа, и Емана, и Идифуна, пророчествующих на цитрах, псалтирях и кимвалах; и было число их, мужей работы для служения их.
Из сынов Асафа: Заккур, и Иосиф, и Нефания, и Ашарела, сыновья Асафа, под рукой Асафа, пророчествующего под руками царя.
У Идифуна: сыновья Идифуна: Гедалия, и Цери, и Исаия, Хашавия и Маттафия, шестеро, под руками отца своего Идифуна, пророчествующего на цитре для благодарения и хвалы Господу.
У Емана: сыновья Емана: Буккия, Матфания, Озиил, Шевуил и Иеримоф, Ханания, Ханани, Елиафа, Гиддалти и Ромамти-Езер, Иошбекаша, Маллофи, Гофир, Махазиоф.
Все эти — сыновья Емана, прозорливца царя в словах Бога, чтобы вознести рог; и дал Бог Еману четырнадцать сыновей и трёх дочерей.
Все эти были под руками отца своего при пении дома Господа с кимвалами, псалтирями и цитрами для служения дома Бога; под руками царя были Асаф, и Идифун, и Еман.
И было число их с братьями их, обученными пению Господу, всех разумеющих, двести восемьдесят восемь.
И бросили они жребии служения, малый наравне с большим, разумеющий с учащимся.
И вышел первый жребий Асафу, Иосифу; второй — Гедалии, он, и братья его, и сыновья его, двенадцать.'''.splitlines()
ordsde=['dritte','vierte','fünfte','sechste','siebte','achte','neunte','zehnte','elfte','zwölfte','dreizehnte','vierzehnte','fünfzehnte','sechzehnte','siebzehnte','achtzehnte','neunzehnte','zwanzigste','einundzwanzigste','zweiundzwanzigste','dreiundzwanzigste','vierundzwanzigste']
namesde=['Sakkur','Jizri','Nethanja','Bukkia','Jesarela','Jesaja','Matthanja','Simei','Asareel','Hasabja','Subael','Matthithja','Jeremoth','Hanaja','Josbekasa','Hanani','Mallothi','Eliatha','Hothir','Giddalthi','Mahesioth','Romamthi-Eser']
ordsru=['третий','четвёртый','пятый','шестой','седьмой','восьмой','девятый','десятый','одиннадцатый','двенадцатый','тринадцатый','четырнадцатый','пятнадцатый','шестнадцатый','семнадцатый','восемнадцатый','девятнадцатый','двадцатый','двадцать первый','двадцать второй','двадцать третий','двадцать четвёртый']
namesru=['Заккур','Ицрий','Нефания','Буккия','Иесарела','Исаия','Матфания','Шимей','Азариил','Хашавия','Шуваил','Маттафия','Иеримоф','Ханания','Иошбекаша','Ханани','Маллофи','Елиафа','Гофир','Гиддалти','Махазиоф','Ромамти-Езер']
for o,n in zip(ordsde,namesde):de.append(f'Das {o}: {n}, seine Söhne und seine Brüder, zwölf.')
for o,n in zip(ordsru,namesru):ru.append(f'{o}: {n}, сыновья его и братья его, двенадцать.')
write(25,'de','\n'.join(de),{1:'Das Weissagen wird als Tätigkeit ausgedrückt.',2:'Die Leitung wird mit Hand und Händen ausgedrückt.',3:'Simei wird hier nicht ausdrücklich genannt; das Instrument steht im Singular.',5:'Das Erheben betrifft ein Horn, nicht ausdrücklich das bestimmte Horn.',6:'Der Vater steht im Singular; Asaph, Jedithun und Heman werden gesondert dem König zugeordnet.',8:'Genannt werden klein und groß, nicht ausdrücklich das Alter; Lose stehen im Plural.'})
write(25,'ru','\n'.join(ru),{1:'Названо число мужей работы, а не действие отчисления.',2:'Названо пророчествование; руководство выражено рукой и руками.',3:'Семей здесь прямо не назван; названы пророчествование и благодарение.',5:'Сохранён образ вознесения рога.',6:'Асаф, Идифун и Еман находятся под руководством царя, а не названы альтернативой ему.',8:'Жребии во множественном числе; разумеющий и учащийся в единственном.'})
