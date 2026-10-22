from pathlib import Path
import json,re
rows=[
('Und sein Haus baute Salomo dreizehn Jahre, und er vollendete sein ganzes Haus.','Das Vollenden folgt als eigene Aussage mit und.'),
('Und er baute das Haus des Waldes des Libanon: hundert Ellen seine Länge und fünfzig Ellen seine Breite und dreißig Ellen seine Höhe, auf vier Reihen von Zedernsäulen, und Zedernbalken waren auf den Säulen.','Die Balken auf den Säulen sind eine eigene Beschreibung, ohne ausdrückliches Legen des Bodens.'),
('Und es war oben mit Zedern gedeckt über den Seitenräumen, die auf den Säulen waren: fünfundvierzig, fünfzehn die Reihe.','Nah am Hebräischen.'),
('Und Fensterrahmen waren in drei Reihen, und Fenster war gegenüber Fenster dreimal.','Die Rahmen sind ausdrücklich genannt.'),
('Und alle Eingänge und die Türpfosten waren viereckig gerahmt, und gegenüber war Fenster zu Fenster dreimal.','Das Hebräische nennt Eingänge und Türpfosten getrennt.'),
('Und die Säulenhalle machte er: fünfzig Ellen ihre Länge und dreißig Ellen ihre Breite; und eine Halle war vor ihnen und Säulen und ein Vordach vor ihnen.','Das Hebräische nennt ein Vordach.'),
('Und die Thronhalle, wo er richten würde, die Gerichtshalle, machte er, und sie war mit Zedern gedeckt vom Boden bis zum Boden.','Das Hebräische sagt Boden bis Boden, nicht Boden bis Decke; er richtet mit aktivem Verb.'),
('Und sein Haus, wo er wohnen sollte, im anderen Hof einwärts von der Halle, war von derselben Machart; und ein Haus machte er für die Tochter des Pharaos, die Salomo genommen hatte, wie diese Halle.','Das Hebräische vergleicht mit dieser Halle, statt im ersten Vergleich andere Gebäude zu nennen.'),
('All diese waren aus kostbaren Steinen nach den Maßen behauener Steine, mit der Säge gesägt von innen und von außen, und vom Fundament bis zu den Gesimsen und von außen bis zum großen Hof.','Das Hebräische nennt Maße behauener Steine und die Säge in der Einzahl.'),
('Und das Fundament bestand aus kostbaren Steinen, großen Steinen, Steinen von zehn Ellen und Steinen von acht Ellen.','Die Steine werden bei beiden Maßen wiederholt.'),
('Und darüber waren kostbare Steine nach den Maßen behauener Steine und Zedern.','Das Hebräische nennt Maße behauener Steine, ohne eigenes Wort für Winkeleisen.'),
('Und der große Hof hatte ringsum drei Reihen behauener Steine und eine Reihe Zedernbalken, ebenso der innere Hof des Hauses des HERRN und die Halle des Hauses.','Nah am Hebräischen.'),
('Und der König Salomo sandte hin und holte Hiram aus Tyrus.','Das Holen ist als aktive Handlung des Königs erzählt.'),
('Er war der Sohn einer Witwe aus dem Stamm Naphthali, und sein Vater war ein Mann aus Tyrus, ein Bronzearbeiter; und er wurde mit Weisheit und Einsicht und Kenntnis erfüllt, um alle Arbeit in Bronze zu tun. Und er kam zum König Salomo und tat seine ganze Arbeit.','Das Erfülltwerden ist passiv ausgedrückt; Weisheit, Einsicht und Kenntnis werden getrennt genannt.'),
('Und er formte die zwei Säulen aus Bronze: achtzehn Ellen die Höhe der einen Säule, und eine Schnur von zwölf Ellen umgab die zweite Säule.','Das Hebräische gibt die Höhe der einen und den Umfang der zweiten Säule getrennt an.'),
('Und zwei Knäufe machte er, um sie auf die Köpfe der Säulen zu setzen, gegossen aus Bronze: fünf Ellen die Höhe des einen Knaufs und fünf Ellen die Höhe des zweiten Knaufs.','Die Höhe wird für beide Knäufe getrennt genannt.'),
('Gitter in Gitterarbeit, Geflechte in Kettenarbeit für die Knäufe, die auf dem Kopf der Säulen waren: sieben für den einen Knauf und sieben für den zweiten Knauf.','Das Hebräische nennt Gitter und Kettengeflechte getrennt und wiederholt sieben für beide Knäufe.'),
('Und er machte die Säulen und zwei Reihen ringsum auf dem einen Gitter, um die Knäufe zu bedecken, die über den Granatäpfeln waren; und ebenso machte er es für den zweiten Knauf.','Die Säulen sind ausdrücklich genannt; das zweite Machen wird als eigene Handlung erzählt.'),
('Und die Knäufe, die auf dem Kopf der Säulen waren, waren Lilienarbeit in der Halle, vier Ellen.','Das Hebräische sagt in der Halle, nicht vor der Halle.'),
('Und Knäufe waren auf den zwei Säulen auch oben, gegenüber dem Bauch, der jenseits des Gitters war; und die Granatäpfel waren zweihundert in Reihen ringsum auf dem zweiten Knauf.','Das Hebräische nennt am Ende den zweiten Knauf, nicht jeden Knauf.'),
('Und er richtete die Säulen an der Halle des Tempels auf, und er richtete die rechte Säule auf und nannte ihren Namen Jachin; und er richtete die linke Säule auf und nannte ihren Namen Boas.','Das Aufrichten wird bei jeder Säule wiederholt.'),
('Und auf dem Kopf der Säulen war Lilienarbeit, und die Arbeit der Säulen war vollendet.','Nah am Hebräischen.'),
('Und er machte das gegossene Meer: zehn Ellen von seinem Rand bis zu seinem Rand, rund ringsum, und fünf Ellen seine Höhe; und eine Schnur von dreißig Ellen umgab es ringsum.','Nah am Hebräischen.'),
('Und Kürbisformen unter seinem Rand umgaben es ringsum, zehn auf die Elle, umschlossen das Meer ringsum; zwei Reihen der Kürbisformen waren bei seinem Guss mitgegossen.','Die Formen sind unter dem Rand; ihr Gießen geschieht bei demselben Guss.'),
('Es stand auf zwölf Rindern: drei nach Norden gewandt und drei nach Westen gewandt und drei nach Süden gewandt und drei nach Osten gewandt, und das Meer war oben auf ihnen, und alle ihre Hinterteile waren nach innen.','Nah am Hebräischen.'),
('Und seine Dicke war eine Handbreit, und sein Rand war wie die Arbeit des Randes eines Bechers, eine Lilienblüte; zweitausend Bath fasste es.','Nah am Hebräischen.'),
('Und er machte die zehn Gestelle aus Bronze: vier Ellen die Länge des einen Gestells und vier Ellen seine Breite und drei Ellen seine Höhe.','Länge und Breite werden getrennt mit vier Ellen genannt.'),
('Und dies war die Machart des Gestells: Rahmen hatten sie, und Rahmen waren zwischen den Leisten.','Die Rahmen werden zweimal genannt.'),
('Und auf den Rahmen zwischen den Leisten waren Löwen, Rinder und Cherubim; und auf den Leisten war oben ein Sockel, und unter den Löwen und den Rindern waren Kränze in absteigender Arbeit.','Das Hebräische nennt einen Sockel oben auf den Leisten.'),
('Und vier Bronzeräder waren an dem einen Gestell und Bronzeachsen, und seine vier Füße hatten Schultern; unter dem Becken waren die Schultern gegossen, jenseits jedes Kranzes.','Das Hebräische nennt Bronzeachsen und Kränze; die Schultern sind unter dem Becken.'),
('Und seine Öffnung war innerhalb des Knaufs und nach oben eine Elle, und ihre Öffnung war rund in Sockelarbeit, eine Elle und eine halbe Elle; und auch auf ihrer Öffnung waren Schnitzereien, und ihre Rahmen waren viereckig, nicht rund.','Die Öffnung heißt bildlich Mund; Schnitzereien sind ausdrücklich genannt.'),
('Und die vier Räder waren unter den Rahmen, und die Achsen der Räder waren am Gestell; und die Höhe des einen Rades war eine Elle und eine halbe Elle.','Nah am Hebräischen.'),
('Und die Machart der Räder war wie die Machart eines Wagenrades; ihre Achsen und ihre Felgen und ihre Speichen und ihre Naben waren alle gegossen.','Nah am Hebräischen.'),
('Und vier Schultern waren an den vier Ecken des einen Gestells; aus dem Gestell waren seine Schultern.','Die Schultern sind aus dem Gestell selbst.'),
('Und auf dem Kopf des Gestells war ringsum ein Rundes von einer halben Elle Höhe; und auf dem Kopf des Gestells waren seine Halter und seine Rahmen aus ihm selbst.','Das Hebräische wiederholt den Kopf des Gestells und nennt seine Halter und Rahmen.'),
('Und er schnitzte auf die Platten seiner Halter und auf seine Rahmen Cherubim, Löwen und Palmen nach dem Raum eines jeden und Kränze ringsum.','Das Schnitzen ist seine aktive Handlung, nicht als Veranlassen ausgedrückt.'),
('So machte er die zehn Gestelle: ein Guss, ein Maß, eine Gestalt für sie alle.','Ein Guss wird ausdrücklich genannt.'),
('Und er machte zehn Bronzebecken: vierzig Bath fasste das eine Becken, vier Ellen maß das eine Becken, ein Becken auf dem einen Gestell für die zehn Gestelle.','Das eine Becken wird bei Inhalt und Maß wiederholt.'),
('Und er setzte die Gestelle, fünf an die rechte Seite des Hauses und fünf an die linke Seite des Hauses; und das Meer setzte er an die rechte Seite des Hauses, ostwärts, gegenüber dem Süden.','Das Hebräische wiederholt die Seite des Hauses und nennt ostwärts ausdrücklich.'),
('Und Hiram machte die Becken und die Schaufeln und die Sprengschalen; und Hiram vollendete die ganze Arbeit, die er für den König Salomo am Haus des HERRN tat:','Das Hebräische nennt zuerst Becken, nicht Töpfe; Hiram wird als Vollender erneut genannt.'),
('zwei Säulen und die zwei Schalen der Knäufe, die auf dem Kopf der Säulen waren, und die zwei Gitter, um die zwei Schalen der Knäufe auf dem Kopf der Säulen zu bedecken,','Die Schalen der Knäufe werden als eigene Teile bezeichnet.'),
('und die vierhundert Granatäpfel für die zwei Gitter, zwei Reihen Granatäpfel für das eine Gitter, um die zwei Schalen der Knäufe zu bedecken, die an der Vorderseite der Säulen waren,','Das Hebräische sagt an der Vorderseite der Säulen.'),
('und die zehn Gestelle und die zehn Becken auf den Gestellen,','Die Gestelle sind als Ort der Becken erneut genannt.'),
('und das eine Meer und die zwölf Rinder unter dem Meer,','Das Hebräische nennt ausdrücklich ein Meer.'),
('und die Töpfe und die Schaufeln und die Sprengschalen und alle diese Geräte, die Hiram für den König Salomo am Haus des HERRN gemacht hatte, aus polierter Bronze.','Nah am Hebräischen.'),
('In der Ebene des Jordans goss der König sie in der dichten Erde zwischen Sukkoth und Zarthan.','Der König gießt mit aktivem Verb, statt das Gießen zu veranlassen.'),
('Und Salomo ließ alle Geräte wegen ihrer sehr, sehr großen Menge liegen; das Gewicht der Bronze wurde nicht untersucht.','Das Hebräische nennt die Nichtuntersuchung des Gewichts als eigene passive Aussage.'),
('Und Salomo machte alle Geräte im Haus des HERRN: den goldenen Altar und den goldenen Tisch, auf dem das Brot des Angesichts war,','Das Brot steht in der Einzahl und bewahrt das Bild des Angesichts.'),
('und die Leuchter, fünf rechts und fünf links vor dem inneren Heiligtum, aus reinem Gold, und die Blüte und die Lampen und die Zangen aus Gold,','Die Blüte steht in der Einzahl.'),
('und die Schalen und die Messer und die Sprengschalen und die Löffel und die Feuerpfannen aus reinem Gold, und die Angeln für die Türen des inneren Hauses, des Allerheiligsten, und für die Türen des Hauses, der Tempelhalle, aus Gold.','Die Türen stehen in der Mehrzahl.'),
('Und vollendet war die ganze Arbeit, die der König Salomo am Haus des HERRN getan hatte; und Salomo brachte die heiligen Gaben seines Vaters David hinein, das Silber und das Gold und die Geräte; er legte sie in die Schatzkammern des Hauses des HERRN.','Die Schatzkammern stehen im Hebräischen in der Mehrzahl.')
]
assert len(rows)==51
r=Path('Tools/LiteralGen');created=[]
for packet in sorted((r/'packets/de-en-ru/11_1KI').glob('*_007*.txt')):
 b=next(x for x in packet.read_text().split('==TARGET ')[1:] if x.startswith('lang=de '));vs=[int(x) for x in re.findall(r'^#(\d+) ',b,re.M)];p=r/'outputs/de/11_1KI'/(packet.stem+'.tsv');assert not p.exists();p.parent.mkdir(parents=True,exist_ok=True);out=[]
 for v in vs:
  a,b=rows[v-1];assert len(b.split())<=60 and '\t' not in a+b and '\n' not in a+b;out.append(f'{v}\t{a}\t{b}')
 with p.open('x') as f:f.write('\n'.join(out)+'\n')
 created.append(str(p))
q=Path('.literalgen-state/de-en-ru/11_1KI-root-native-created.json');a=json.loads(q.read_text());a.extend(created);q.write_text(json.dumps(a,ensure_ascii=False,indent=2));print('DE007',len(created),'files',51,'rows exclusively created')
