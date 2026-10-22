from pathlib import Path
import json,re
text='''1	Und der HERR redete zu Mose und sagte:	Nah am Hebräischen.
2	„Rede zur ganzen Gemeinde der Söhne Israels und sage zu ihnen: Heilig sollt ihr sein, denn heilig bin ich, der HERR, euer Gott.	Bewahrt „Söhne“ statt des allgemeineren „Kinder“.
3	Jeder von euch soll seine Mutter und seinen Vater fürchten, und meine Sabbate sollt ihr bewahren. Ich bin der HERR, euer Gott.	Nennt ausdrücklich die Sabbate statt allgemeiner Feiertage.
4	Ihr sollt euch nicht den Götzen zuwenden und euch keine gegossenen Götter machen. Ich bin der HERR, euer Gott.	Nah am Hebräischen.
5	Und wenn ihr dem HERRN ein Friedensopfer schlachtet, sollt ihr es zu eurer Annahme schlachten.	Die Annahme wird auf die Opfernden bezogen; „Dankopfer“ gibt den Opferbegriff enger wieder.
6	Am Tag, an dem ihr es schlachtet, und am folgenden Tag soll es gegessen werden; und was bis zum dritten Tag übrig bleibt, soll mit Feuer verbrannt werden.	Bewahrt das passive Gegessenwerden und Verbranntwerden.
7	Und wenn es am dritten Tag doch gegessen wird, ist es Unreines; es wird nicht angenommen werden.	Die Unreinheit und das Nichtangenommenwerden beziehen sich auf das Opfer statt ausdrücklich auf den Esser.
8	Und wer davon isst, soll seine Schuld tragen, denn er hat das Heilige des HERRN entweiht; und jene Seele soll von ihren Völkern abgeschnitten werden.	Bewahrt die Völker in der Mehrzahl und den Bezug auf das Heilige statt nur auf ein Heiligtum.
9	Und wenn ihr die Ernte eures Landes erntet, sollst du den Rand deines Feldes nicht vollständig abernten, und die Nachlese deiner Ernte sollst du nicht auflesen.	Bewahrt den Wechsel von der Mehrzahl der Angesprochenen zur Einzahl und nennt ausdrücklich die Nachlese.
10	Und deinen Weinberg sollst du nicht nachlesen, und die abgefallenen Trauben deines Weinbergs sollst du nicht auflesen. Dem Armen und dem Fremden sollst du sie lassen. Ich bin der HERR, euer Gott.	Bewahrt die Wiederholung des Weinbergs und die Trauben statt allgemeiner Beeren.
11	Ihr sollt nicht stehlen und nicht verleugnen und nicht lügen, einer gegen seinen Nächsten.	Nah am Hebräischen.
12	Und ihr sollt nicht bei meinem Namen zur Lüge schwören und so den Namen deines Gottes entweihen. Ich bin der HERR.	Nah am Hebräischen.
13	Du sollst deinen Nächsten nicht bedrücken und nicht berauben. Der Lohn eines Tagelöhners soll nicht über Nacht bei dir bleiben bis zum Morgen.	Nennt ausdrücklich das Übernachten des Lohns.
14	Du sollst einem Tauben nicht fluchen und vor einen Blinden kein Hindernis legen; und du sollst deinen Gott fürchten. Ich bin der HERR.	Bewahrt „und“ vor dem Fürchten statt einer ausdrücklichen Begründung mit „denn“.
15	Ihr sollt im Gericht kein Unrecht tun. Du sollst das Gesicht des Armen nicht erheben und das Gesicht des Großen nicht ehren; in Gerechtigkeit sollst du deinen Nächsten richten.	Bewahrt das zweimalige Bild des Gesichts.
16	Du sollst unter deinen Völkern nicht als Verleumder umhergehen; du sollst nicht gegen das Blut deines Nächsten stehen. Ich bin der HERR.	Bewahrt das Umhergehen und die Mehrzahl bei den Völkern.
17	Du sollst deinen Bruder in deinem Herzen nicht hassen. Du sollst deinen Nächsten gewiss zurechtweisen und seinetwegen keine Sünde tragen.	Bewahrt die Verstärkung des Zurechtweisens und „Sünde“ statt allgemeiner Schuld.
18	Du sollst dich nicht rächen und den Söhnen deines Volkes nichts nachtragen; und du sollst deinen Nächsten lieben wie dich selbst. Ich bin der HERR.	Bewahrt die Söhne und das tatsächliche Rächen statt bloßer Rachgier.
19	Meine Satzungen sollt ihr bewahren. Dein Vieh sollst du nicht mit einer anderen Art sich paaren lassen; dein Feld sollst du nicht mit zweierlei besäen; und ein Kleid aus zweierlei, aus Mischgewebe, soll nicht auf dich kommen.	Wolle und Leinen werden hier nicht ausdrücklich genannt; „zweierlei“ wird wiederholt.
20	Und wenn ein Mann mit Samenerguss bei einer Frau liegt und sie eine Sklavin ist, die für einen Mann bestimmt, aber keineswegs losgekauft und der keine Freiheit gegeben worden ist, soll eine Ahndung erfolgen. Sie sollen nicht getötet werden, denn sie ist nicht freigelassen worden.	Die Frau ist für einen Mann bestimmt statt von ihm verschmäht; bewahrt das passive Getötetwerden und Freigelassenwerden.
21	Und er soll dem HERRN sein Schuldopfer bringen, zum Eingang des Zeltes der Begegnung, einen Widder als Schuldopfer.	Bewahrt die zweimalige Nennung des Schuldopfers.
22	Und der Priester soll mit dem Widder des Schuldopfers vor dem HERRN für ihn Sühne schaffen wegen seiner Sünde, die er gesündigt hat; und es soll ihm vergeben werden wegen seiner Sünde, die er gesündigt hat.	Bewahrt die Vergebung als passiven Vorgang und nennt den Widder ausdrücklich.
23	Und wenn ihr in das Land kommt und irgendeinen Baum zur Nahrung pflanzt, sollt ihr seine Frucht als seine Vorhaut behandeln. Drei Jahre soll sie euch unbeschnitten sein; sie soll nicht gegessen werden.	Bewahrt den einzelnen Baum und das passive Nichtgegessenwerden.
24	Und im vierten Jahr soll seine ganze Frucht heilig sein, als Lobpreisgaben für den HERRN.	Bewahrt die Mehrzahl der Lobpreisgaben.
25	Und im fünften Jahr sollt ihr seine Frucht essen, damit sein Ertrag euch vermehrt wird. Ich bin der HERR, euer Gott.	Nennt die Vermehrung des Ertrags statt eines zusätzlichen Einsammelns.
26	Ihr sollt nicht mit dem Blut essen. Ihr sollt keine Wahrsagerei und keine Zeichendeuterei treiben.	Bewahrt „mit dem Blut“ statt „vom Blut“; Vogelgeschrei und das Wählen von Tagen werden nicht ausdrücklich genannt.
27	Ihr sollt den Rand eures Hauptes nicht rund abschneiden; und du sollst den Rand deines Bartes nicht zerstören.	Bewahrt die Ränder und den Wechsel von der Mehrzahl zur Einzahl statt eines vollständigen Abscherens.
28	Und wegen eines Toten sollt ihr keinen Schnitt in euer Fleisch machen und keine eingeritzte Schrift an euch anbringen. Ich bin der HERR.	Bewahrt das Fleisch und den Schnitt statt eines allgemeinen Mals am Leib.
29	Du sollst deine Tochter nicht entweihen, indem du sie zur Hurerei bringst, damit das Land nicht hurt und das Land nicht voll Schandtat wird.	Bewahrt das Entweihen der Tochter und die zweimalige Nennung des Landes.
30	Meine Sabbate sollt ihr bewahren und mein Heiligtum fürchten. Ich bin der HERR.	Nennt die Sabbate statt allgemeiner Feiertage.
31	Ihr sollt euch nicht den Totenbeschwörern und den Wahrsagern zuwenden; ihr sollt sie nicht aufsuchen, um durch sie unrein zu werden. Ich bin der HERR, euer Gott.	Das Zuwenden bezieht sich auf beide Gruppen, das Aufsuchen folgt als weiteres Verbot.
32	Vor grauem Haar sollst du aufstehen und das Gesicht eines Alten ehren; und du sollst deinen Gott fürchten. Ich bin der HERR.	Bewahrt das graue Haar und das Gesicht des einzelnen Alten.
33	Und wenn ein Fremder bei dir in eurem Land wohnt, sollt ihr ihn nicht bedrücken.	Bewahrt den Wechsel zwischen dem einzelnen und den mehreren Angesprochenen.
34	Wie ein Einheimischer aus eurer Mitte soll euch der Fremde sein, der bei euch wohnt; und du sollst ihn lieben wie dich selbst, denn Fremde wart ihr im Land Ägypten. Ich bin der HERR, euer Gott.	Der Fremde soll wie ein Einheimischer sein; das Wohnen gehört ausdrücklich zur Beschreibung des Fremden.
35	Ihr sollt kein Unrecht tun im Gericht, beim Messen, beim Wiegen und beim Abmessen des Inhalts.	Die Elle wird nicht ausdrücklich als Maß genannt.
36	Gerechte Waagen, gerechte Gewichtssteine, ein gerechtes Epha und ein gerechtes Hin sollt ihr haben. Ich bin der HERR, euer Gott, der euch aus dem Land Ägypten herausgeführt hat.	Bewahrt die Gewichtssteine und die benannten Maße Epha und Hin statt allgemeiner Pfunde, Scheffel und Kannen.
37	Und ihr sollt alle meine Satzungen und alle meine Rechtsbestimmungen bewahren und sie tun. Ich bin der HERR.“	Nah am Hebräischen.'''
rows=text.splitlines();packets=sorted(Path('Tools/LiteralGen/packets/de-en-ru/03_LEV').glob('LEV_019*.txt'));plans=[]
for packet in packets:
 b=next(x for x in packet.read_text().split('==TARGET ')[1:] if x.startswith('lang=de '));vs=re.findall(r'^#(\d+) ',b,re.M);selected=[x for x in rows if x.split('\t')[0] in vs];assert [x.split('\t')[0] for x in selected]==vs
 p=Path('Tools/LiteralGen/outputs/de/03_LEV')/(packet.stem+'.tsv');assert not p.exists();plans.append((p,'\n'.join(selected)+'\n'))
assert len(rows)==37
for row in rows:
 c=row.split('\t');assert len(c)==3 and all(c) and len(c[2].split())<=60
for p,t in plans:
 with p.open('x') as f:f.write(t)
s=Path('.literalgen-state/de-en-ru/03_LEV-root-created.json');a=json.loads(s.read_text());a.extend(str(p) for p,_ in plans);s.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n');print('DE LEV019 2 files 37 rows exclusively created')
