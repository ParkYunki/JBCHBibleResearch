from pathlib import Path
import json
out=[]
def add(l,ch,v,a=None,b=None):
 ps=[p for p in (Path('Tools/LiteralGen/outputs')/l/'13_1CH').glob(f'*_{ch:03d}*.tsv') if any(r.startswith(str(v)+'\t') for r in p.read_text().splitlines())];assert len(ps)==1
 p=ps[0];old=next(r for r in p.read_text().splitlines() if r.startswith(str(v)+'\t'));f=old.split('\t');new='\t'.join([f[0],a or f[1],b or f[2]]);assert new!=old
 out.append({'path':str(p),'old_row':old,'new_row':new})
add('de',10,1,b='Nah am Hebräischen.')
add('de',11,1,b='Nah am Hebräischen.')
add('de',11,7,b='Nah am Hebräischen.')
add('de',11,19,a='Und er sagte: „Fern sei es mir vor meinem Gott, dies zu tun! Sollte ich das Blut dieser Männer unter Einsatz ihres Lebens trinken? Denn unter Einsatz ihres Lebens haben sie es gebracht.“ Und er wollte es nicht trinken. Dies taten die drei Helden.')
add('ru',13,2,a='И Давид сказал всему собранию Израиля: «Если это угодно вам и это от Господа, нашего Бога, пошлём повсюду к нашим оставшимся братьям во всех землях Израиля и с ними к священникам и левитам в их городах с пастбищами, чтобы они собрались к нам.')
add('de',15,12,a='Und er sagte zu ihnen: „Ihr seid die Häupter der Väter unter den Leviten. Heiligt euch, ihr und eure Brüder, und bringt die Lade des HERRN, des Gottes Israels, dorthin hinauf, wo ich ihr einen Platz bereitet habe.')
add('ru',15,12,a='И сказал им: «Вы главы отцов у левитов. Освятитесь, вы и ваши братья, и поднимите ковчег Господа, Бога Израиля, туда, где я приготовил для него место.')
add('de',16,7,a='An jenem Tag gab David damals zuerst den Auftrag, dem HERRN durch die Hand Asaphs und seiner Brüder zu danken:')
add('de',16,36,a='Gesegnet sei der HERR, der Gott Israels, von Ewigkeit bis Ewigkeit! Und das ganze Volk sagte: „Amen!“ und lobte den HERRN.')
add('ru',16,35,a='И скажите: «Спаси нас, Боже нашего спасения, и собери нас и избавь нас от народов, чтобы благодарить Твоё святое имя, чтобы хвалиться Твоей хвалой!»')
add('ru',16,36,a='Благословен Господь, Бог Израиля, от века до века! И весь народ сказал: «Аминь!» и хвалил Господа.')
add('de',16,40,a='um dem HERRN beständig am Morgen und am Abend Brandopfer auf dem Brandopferaltar darzubringen und nach allem zu handeln, was im Gesetz des HERRN geschrieben ist, das er Israel geboten hat;')
for x in out:assert len(x['new_row'].split('\t'))==3 and len(x['new_row'].split('\t')[2].split())<=60
p=Path('.literalgen-state/de-en-ru/1ch-a-extra-b-native-qa.json');p.write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n');print(len(out),p)
