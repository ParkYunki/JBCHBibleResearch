from pathlib import Path
import json,re
state=Path('.literalgen-state/de-en-ru'); own=[];other=[]
def change(dest,lang,ch,v,lit=None,diff=None):
 for p in sorted((Path('Tools/LiteralGen/outputs')/lang/'15_EZR').glob(f'*_{ch:03}*.tsv')):
  for old in p.read_text().splitlines():
   f=old.split('\t')
   if int(f[0])==v:
    if lit is not None:f[1]=lit
    if diff is not None:f[2]=diff
    new='\t'.join(f);assert new!=old
    dest.append(dict(path=str(p),old_row=old,new_row=new));return
 raise ValueError((lang,ch,v))
change(own,'de',1,3,diff='Sein Gott soll mit ihm sein; im Zieltext fehlt hier das Possessivpronomen.')
change(own,'de',1,6,diff='Silberne Gefäße und Gold werden getrennt genannt, nicht silberne und goldene Geräte.')
change(own,'de',1,8,diff='Nah am Hebräischen.')
change(own,'ru',1,2,lit='«Так говорит Кир, царь Персии: все царства земли дал мне Господь, Бог небес, и Он возложил на меня обязанность построить Ему дом в Иерусалиме, который в Иудее.')
change(own,'de',2,2,lit='die mit Serubabel, Jesua, Nehemia, Seraja, Reelaja, Mardochai, Bilsa, Mispar, Bigevai, Rehum und Baana kamen. Die Zahl der Männer des Volkes Israel:')
change(own,'ru',2,2,lit='которые пришли с Зоровавелем, Иисусом, Неемиею, Сараием, Реелаем, Мардохеем, Билшаном, Мисфаром, Бигваем, Рехумом и Вааном. Число мужей народа Израиля:')
change(own,'de',3,9,lit='Und Jesua trat hin, und seine Söhne und seine Brüder, Kadmiel und seine Söhne, die Söhne Judas, als einer, um über die Arbeiter am Haus Gottes Aufsicht zu führen, und die Söhne Henadads, ihre Söhne und ihre Brüder, die Leviten.')
change(other,'en',1,7,diff='The Hebrew says “the house”; BSB says “the temple.”')
change(other,'en',2,64,diff='The Hebrew describes the whole assembly “as one”; BSB gives the assembly’s total without that comparison.')
change(other,'en',3,3,diff='The Hebrew introduces their fear with “because”; BSB introduces it with “even though.” The altar’s bases are plural in Hebrew; BSB says “its foundation.”')
change(other,'en',3,11,diff='The Hebrew says the house of the LORD was founded; BSB says the foundation of the house of the LORD had been laid.')
for name,data in [('ezr-a-qa.json',own),('ezr-a-root-en-qa.json',other)]:
 for x in data:assert len(x['new_row'].split('\t'))==3 and len(x['new_row'].split('\t')[2].split())<=60
 (state/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
created=json.loads((state/'ezr-a-checkpoint.json').read_text())['created'];report=[]
for path in created:
 p=Path(path);lines=p.read_text().splitlines();lang=p.parts[-3]
 packet=Path('Tools/LiteralGen/packets/de-en-ru/15_EZR')/(p.stem+'.txt')
 target=next(x for x in packet.read_text().split('==TARGET ')[1:] if x.startswith('lang='+lang+' '));expected=list(map(int,re.findall(r'^#(\d+) ',target,re.M)))
 assert [int(l.split('\t')[0]) for l in lines]==expected
 assert all(len(l.split('\t'))==3 and len(l.split('\t')[2].split())<=60 for l in lines)
 report.append(dict(path=path,rows=len(lines),valid=True))
(state/'ezr-a-created.json').write_text(json.dumps(created,ensure_ascii=False,indent=2)+'\n')
(state/'ezr-a-validation.json').write_text(json.dumps(dict(files=len(created),rows=sum(x['rows'] for x in report),files_validated=report,own_qa_rows=188,en_cross_qa_rows=94,own_candidates=len(own),en_candidates=len(other)),ensure_ascii=False,indent=2)+'\n')
print(len(created),sum(x['rows'] for x in report),len(own),len(other))
