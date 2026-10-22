from pathlib import Path
import json,re
rows=[
('Und sie blieben drei Jahre, ohne Krieg zwischen Syrien und Israel.','Das Hebräische lässt sie drei Jahre bleiben; Syrien steht als kollektiver Name.'),
('Und es geschah im dritten Jahr, da zog Josaphat, der König von Juda, zum König von Israel hinab.','Nah am Hebräischen.'),
('Und der König von Israel sagte zu seinen Knechten: „Wisst ihr, dass Ramoth in Gilead uns gehört? Und wir schweigen, statt es aus der Hand des Königs von Syrien zu nehmen!“','Nah am Hebräischen.'),
('Und er sagte zu Josaphat: „Wirst du mit mir nach Ramoth in Gilead in den Krieg ziehen?“ Und Josaphat sagte zum König von Israel: „Wie ich, so du; wie mein Volk, so dein Volk; wie meine Pferde, so deine Pferde.“','Die Vergleiche stehen ohne eigene Aussage des Wollens.'),
('Und Josaphat sagte zum König von Israel: „Erfrage doch heute das Wort des HERRN!“','Nah am Hebräischen.'),
('Und der König von Israel versammelte die Propheten, etwa vierhundert Mann, und sagte zu ihnen: „Soll ich gegen Ramoth in Gilead in den Krieg ziehen oder es unterlassen?“ Und sie sagten: „Zieh hinauf, und der Herr wird es in die Hand des Königs geben!“','Das Hinaufziehen ist im Hebräischen ausdrücklich genannt.'),
('Und Josaphat sagte: „Ist hier nicht noch ein Prophet des HERRN, damit wir durch ihn fragen?“','Nah am Hebräischen.'),
('Und der König von Israel sagte zu Josaphat: „Noch ist ein Mann da, durch den man den HERRN befragen kann; aber ich hasse ihn, denn er weissagt über mich nichts Gutes, sondern nur Böses: Micha, der Sohn Jemlas.“ Und Josaphat sagte: „Der König sage nicht so!“','Das Hebräische nennt Hass ausdrücklich; Micha wird am Ende der Beschreibung genannt.'),
('Und der König von Israel rief einen Eunuchen und sagte: „Schnell Micha, den Sohn Jemlas!“','Die Aufforderung nennt Micha ohne eigenes Verb des Bringens.'),
('Und der König von Israel und Josaphat, der König von Juda, saßen jeder auf seinem Thron, in Kleider gekleidet, auf einer Tenne am Eingang des Tores von Samaria; und alle Propheten weissagten vor ihnen.','Das Hebräische nennt eine Tenne statt eines Platzes.'),
('Und Zedekia, der Sohn Knaenas, machte sich eiserne Hörner und sagte: „So hat der HERR gesagt: ‚Mit diesen wirst du Syrien stoßen, bis du sie vernichtet hast.‘“','Syrien steht als kollektiver Name.'),
('Und alle Propheten weissagten so und sagten: „Zieh nach Ramoth in Gilead hinauf und habe Erfolg, und der HERR wird es in die Hand des Königs geben!“','Nah am Hebräischen.'),
('Und der Bote, der gegangen war, Micha zu rufen, redete zu ihm und sagte: „Siehe doch, die Worte der Propheten sind mit einem Mund gut für den König; dein Wort sei doch wie das Wort eines von ihnen, und rede Gutes!“','Das Hebräische bewahrt das Bild eines Mundes und vergleicht sein Wort mit dem eines Einzelnen.'),
('Und Micha sagte: „So wahr der HERR lebt, was der HERR mir sagen wird, das werde ich reden!“','Nah am Hebräischen.'),
('Und er kam zum König, und der König sagte zu ihm: „Micha, sollen wir gegen Ramoth in Gilead in den Krieg ziehen oder es unterlassen?“ Und er sagte zu ihm: „Zieh hinauf und habe Erfolg, und der HERR wird es in die Hand des Königs geben!“','Die Antwort hat kein eigenes Ja.'),
('Und der König sagte zu ihm: „Bis wie viele Male muss ich dich beschwören, dass du zu mir nichts als Wahrheit im Namen des HERRN redest?“','Das Hebräische formuliert eine Frage nach der Anzahl der Beschwörungen.'),
('Und er sagte: „Ich sah ganz Israel auf den Bergen zerstreut wie Schafe, die keinen Hirten haben; und der HERR sagte: ‚Diese haben keine Herren; sie sollen jeder in sein Haus in Frieden zurückkehren.‘“','Herren steht im Hebräischen in der Mehrzahl.'),
('Und der König von Israel sagte zu Josaphat: „Habe ich dir nicht gesagt: Er weissagt über mich nichts Gutes, sondern nur Böses?“','Nah am Hebräischen.'),
('Und er sagte: „Darum höre das Wort des HERRN! Ich sah den HERRN auf seinem Thron sitzen und das ganze Heer des Himmels bei ihm stehen, zu seiner Rechten und zu seiner Linken.','Nah am Hebräischen.'),
('Und der HERR sagte: ‚Wer wird Ahab betören, dass er hinaufzieht und in Ramoth in Gilead fällt?‘ Und dieser sagte so, und jener sagte so.','Nah am Hebräischen.'),
('Und der Geist trat heraus und stellte sich vor den HERRN und sagte: ‚Ich werde ihn betören.‘','Der Geist ist bestimmt bezeichnet; die Frage des HERRN folgt im nächsten hebräischen Vers.'),
('Und der HERR sagte zu ihm: ‚Womit?‘ Und er sagte: ‚Ich werde ausgehen und ein Geist der Lüge im Mund aller seiner Propheten sein.‘ Und er sagte: ‚Du wirst ihn betören und auch vermögen; geh aus und tue so!‘','Der Vers beginnt im Hebräischen mit der Frage des HERRN; der Mund gehört ausdrücklich allen seinen Propheten.'),
('Und nun, siehe, der HERR hat einen Geist der Lüge in den Mund aller dieser deiner Propheten gegeben, und der HERR hat Unheil über dich geredet.“','Nah am Hebräischen.'),
('Und Zedekia, der Sohn Knaenas, trat heran und schlug Micha auf die Wange und sagte: „Welchen Weg ist der Geist des HERRN von mir fortgezogen, um mit dir zu reden?“','Das Hebräische fragt nach dem Weg des Fortziehens.'),
('Und Micha sagte: „Siehe, du wirst es an jenem Tag sehen, an dem du in eine Kammer innerhalb einer Kammer gehst, um dich zu verbergen!“','Die Kammer liegt in einer Kammer, statt eines Gehens von einer in die andere.'),
('Und der König von Israel sagte: „Nimm Micha und bringe ihn zu Amon, dem Obersten der Stadt, und zu Joas, dem Sohn des Königs, zurück!','Das Hebräische befiehlt ein Zurückbringen, nicht nur ein Bleibenlassen.'),
('Und sage: ‚So hat der König gesagt: Setzt diesen ins Gefängnis und gebt ihm Brot der Bedrängnis und Wasser der Bedrängnis zu essen, bis ich in Frieden komme!‘“','Bedrängnis wird beim Brot und beim Wasser wiederholt.'),
('Und Micha sagte: „Wenn du wirklich in Frieden zurückkehrst, hat der HERR nicht durch mich geredet!“ Und er sagte: „Hört, ihr Völker alle!“','Die Rückkehr ist durch Wiederholung des Verbstamms bekräftigt; Völker steht in der Mehrzahl.'),
('Und der König von Israel und Josaphat, der König von Juda, zogen nach Ramoth in Gilead hinauf.','Nah am Hebräischen.'),
('Und der König von Israel sagte zu Josaphat: „Ich werde mich verkleiden und in die Schlacht gehen, du aber zieh deine Kleider an!“ Und der König von Israel verkleidete sich und ging in die Schlacht.','Nah am Hebräischen.'),
('Und der König von Syrien hatte seinen Wagenführern, zweiunddreißig, geboten und gesagt: „Kämpft nicht gegen einen Kleinen oder einen Großen, sondern gegen den König von Israel allein!“','Nah am Hebräischen.'),
('Und es geschah, als die Wagenführer Josaphat sahen, da sagten sie: „Gewiss ist er der König von Israel!“ Und sie wandten sich gegen ihn, um zu kämpfen, und Josaphat schrie.','Das Hebräische nennt ihr Sagen, nicht nur ihr Meinen.'),
('Und es geschah, als die Wagenführer sahen, dass er nicht der König von Israel war, da kehrten sie von seiner Verfolgung zurück.','Die Rückkehr aus seiner Verfolgung ist ausdrücklich genannt.'),
('Und ein Mann spannte den Bogen in seiner Arglosigkeit und traf den König von Israel zwischen den Verbindungen und dem Panzer; und er sagte zu seinem Wagenführer: „Wende deine Hand und bringe mich aus dem Lager, denn ich bin verwundet!“','Der Treffer liegt zwischen den Verbindungen und dem Panzer; das Lager wird ausdrücklich genannt.'),
('Und die Schlacht steigerte sich an jenem Tag, und der König wurde im Wagen gegenüber Syrien aufrecht gehalten und starb am Abend; und das Blut der Wunde floss in den Schoß des Wagens.','Das Aufrechthalten ist passiv; der Wagen steht gegenüber Syrien. Die Wunde steht in der Einzahl; der Wagen hat bildlich einen Schoß.'),
('Und der Ruf ging bei Sonnenuntergang durch das Lager und lautete: „Jeder in seine Stadt und jeder in sein Land!“','Der Ruf geht im Hebräischen selbst durch das Lager, statt eines Veranlassens des Ausrufens.'),
('Und der König starb und kam nach Samaria, und sie begruben den König in Samaria.','Das Kommen ist aktiv erzählt; König wird wiederholt.'),
('Und man spülte den Wagen beim Teich von Samaria ab, und die Hunde leckten sein Blut, und die Huren badeten, nach dem Wort des HERRN, das er geredet hatte.','Das Spülen hat im Hebräischen eine ungenannte Einzahl als Subjekt; die Huren badeten, ohne ihn als Objekt.'),
('Und die übrigen Taten Ahabs und alles, was er getan hat, und das elfenbeinerne Haus, das er gebaut hat, und alle Städte, die er gebaut hat, sind sie nicht im Buch der Tagesereignisse der Könige von Israel geschrieben?','Das Hebräische fragt nach dem Geschriebensein, statt es mit siehe festzustellen.'),
('Und Ahab legte sich zu seinen Vätern, und Ahasja, sein Sohn, wurde an seiner Stelle König.','Das Hebräische gebraucht das Bild des Sichlegens zu den Vätern.'),
('Und Josaphat, der Sohn Asas, wurde König über Juda im vierten Jahr Ahabs, des Königs von Israel.','Nah am Hebräischen.'),
('Josaphat war fünfunddreißig Jahre alt, als er König wurde, und fünfundzwanzig Jahre regierte er in Jerusalem; und der Name seiner Mutter war Asuba, die Tochter Silhis.','Josaphat wird ausdrücklich genannt; die Aussage über seinen Wandel folgt erst im nächsten hebräischen Vers.'),
('Und er ging auf dem ganzen Weg seines Vaters Asa, wich nicht davon ab, indem er tat, was recht war in den Augen des HERRN; doch die Höhen wichen nicht, noch opferte und räucherte das Volk auf den Höhen.','Der hebräische Vers enthält auch den Wandel auf Asas Weg und das Rechte in den Augen des HERRN. Die Höhen wichen nicht, ohne ihn als ausdrücklichen Handelnden ihrer Entfernung.'),
('Und Josaphat schloss Frieden mit dem König von Israel.','Das Schließen des Friedens ist als Handlung erzählt.'),
('Und die übrigen Taten Josaphats und seine Stärke, die er bewies, und wie er Krieg führte, sind sie nicht im Buch der Tagesereignisse der Könige von Juda geschrieben?','Das Hebräische fragt nach dem Geschriebensein, statt es mit siehe festzustellen.'),
('Und den Rest der Kultprostituierten, der in den Tagen seines Vaters Asa übrig geblieben war, schaffte er aus dem Land.','Die Bezeichnung des Kultprostituierten steht im Hebräischen in der kollektiven Einzahl.'),
('Und es gab keinen König in Edom; ein Statthalter war König.','Nah am Hebräischen.'),
('Josaphat machte Tarsisschiffe, um nach Ophir nach Gold zu fahren; doch er fuhr nicht, denn die Schiffe wurden in Ezeon-Geber zerbrochen.','Tarsisschiffe sind ausdrücklich genannt; das Nichtfahren steht in der Einzahl.'),
('Damals sagte Ahasja, der Sohn Ahabs, zu Josaphat: „Meine Knechte sollen mit deinen Knechten in den Schiffen fahren!“ Und Josaphat wollte nicht.','Seine Knechte sollen mit den Knechten Josaphats fahren, nicht mit dessen Schiffen als einzigem Gegenüber.'),
('Und Josaphat legte sich zu seinen Vätern und wurde bei seinen Vätern in der Stadt Davids, seines Vaters, begraben, und Joram, sein Sohn, wurde an seiner Stelle König.','Das Hebräische gebraucht das Bild des Sichlegens zu den Vätern.'),
('Ahasja, der Sohn Ahabs, wurde König über Israel in Samaria im siebzehnten Jahr Josaphats, des Königs von Juda, und regierte über Israel zwei Jahre.','Nah am Hebräischen.'),
('Und er tat das Böse in den Augen des HERRN und ging auf dem Weg seines Vaters und auf dem Weg seiner Mutter und auf dem Weg Jerobeams, des Sohnes Nebats, der Israel zum Sündigen gebracht hatte.','Das Hebräische wiederholt auf dem Weg bei Vater, Mutter und Jerobeam; die Augen sind ausdrücklich genannt.'),
('Und er diente Baal und warf sich vor ihm nieder und reizte den HERRN, den Gott Israels, zum Zorn, nach allem, was sein Vater getan hatte.','Das Hebräische nennt das Niederwerfen und ausdrücklich alles, was sein Vater getan hatte.')
]
assert len(rows)==53
r=Path('Tools/LiteralGen');created=[]
for packet in sorted((r/'packets/de-en-ru/11_1KI').glob('*_022*.txt')):
 b=next(x for x in packet.read_text().split('==TARGET ')[1:] if x.startswith('lang=de '));vs=[int(x) for x in re.findall(r'^#(\d+) ',b,re.M)];p=r/'outputs/de/11_1KI'/(packet.stem+'.tsv');assert not p.exists();p.parent.mkdir(parents=True,exist_ok=True);out=[]
 for v in vs:
  a,b=rows[v-1];assert len(b.split())<=60 and '\t' not in a+b and '\n' not in a+b;out.append(f'{v}\t{a}\t{b}')
 with p.open('x') as f:f.write('\n'.join(out)+'\n')
 created.append(str(p))
q=Path('.literalgen-state/de-en-ru/11_1KI-root-native-created.json');assert not q.exists();q.write_text(json.dumps(created,ensure_ascii=False,indent=2));print('DE022',len(created),'files',53,'rows exclusively created')
