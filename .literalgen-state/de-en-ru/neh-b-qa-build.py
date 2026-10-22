from pathlib import Path
import re,json
q=[]
def add(l,ch,v,lit=None,diff=None):
 p=next(p for p in Path(f'Tools/LiteralGen/outputs/{l}/16_NEH').glob(f'NEH_{ch:03}*.tsv') if any(s.startswith(str(v)+'\t') for s in p.read_text().splitlines()));old=next(s for s in p.read_text().splitlines() if s.startswith(str(v)+'\t'));a=old.split('\t');a[1]=lit if lit is not None else a[1];a[2]=diff if diff is not None else a[2]
 if old!='\t'.join(a):q.append({'path':str(p),'old_row':old,'new_row':'\t'.join(a)})
add('de',8,10,'Und er sagte ihnen: „Geht, esst Fettes und trinkt Süßes und sendet Anteile dem, dem nichts bereitet ist, denn der Tag ist unserem Herrn heilig; und seid nicht bekümmert, denn die Freude des HERRN ist eure Zuflucht.“')
add('de',9,19,'hast du sie in deinen großen Erbarmungen nicht in der Wüste verlassen. Die Wolkensäule wich bei Tag nicht von ihnen, um sie auf dem Weg zu führen, und die Feuersäule bei Nacht, um ihnen und dem Weg zu leuchten, auf dem sie gehen sollten.')
add('de',9,25,'Und sie nahmen befestigte Städte und fetten Boden ein und nahmen Häuser voll alles Guten, ausgehauene Zisternen, Weinberge und Ölbäume und Speisebäume in Menge in Besitz; und sie aßen und wurden satt und fett und schwelgten in deiner großen Güte.')
add('ru',9,9,'И Ты увидел угнетение наших отцов в Египте и услышал их вопль у Чермного моря.','Близко к еврейскому.')
add('ru',8,5,'И Ездра открыл книгу перед глазами всего народа, ибо он был выше всего народа; и когда он открыл её, весь народ встал.','Близко к еврейскому.')
add('de',9,7,'Du bist der HERR, der Gott, der du Abram erwählt und ihn aus Ur der Chaldäer herausgeführt und seinen Namen Abraham gesetzt hast.')
add('ru',9,19,'Ты в Твоих великих состраданиях не оставил их в пустыне. Облачный столп не отходил от них днём, чтобы вести их на пути, и огненный столп ночью, чтобы светить им и пути, которым они должны идти.')
Path('.literalgen-state/de-en-ru/neh-b-qa.json').write_text(json.dumps(q,ensure_ascii=False,indent=2))
q=[]
add('en',7,7,diff='Close to the Hebrew.')
add('en',9,19,diff='The Hebrew says the cloud pillar did not depart from above them; BSB describes it as never turning away from guiding them.')
Path('.literalgen-state/de-en-ru/neh-b-root-en-qa.json').write_text(json.dumps(q,ensure_ascii=False,indent=2))
files=[];rows=0
for l in ['de','ru']:
 for ch in range(7,10):
  for p in sorted(Path('Tools/LiteralGen/packets/de-en-ru/16_NEH').glob(f'NEH_{ch:03}*.txt')):
   t=next(x for x in p.read_text().split('==TARGET ')[1:] if x.startswith('lang='+l+' '));vs=re.findall(r'^#(\d+) ',t,re.M);o=Path(f'Tools/LiteralGen/outputs/{l}/16_NEH')/(p.stem+'.tsv');rr=o.read_text().splitlines();assert [x.split('\t')[0] for x in rr]==vs
   for x in rr:assert len(x.split('\t'))==3 and len(x.split('\t')[2].split())<=60
   files.append(str(o));rows+=len(rr)
cp={'book':'16_NEH','assignment':'de/ru007–009','phase':'complete_pending_book_check','files':len(files),'rows':rows,'qa_candidates':7,'root_en_qa_candidates':2}
Path('.literalgen-state/de-en-ru/neh-b-checkpoint.json').write_text(json.dumps(cp,ensure_ascii=False,indent=2));Path('.literalgen-state/de-en-ru/neh-b-validation.json').write_text(json.dumps({'files':files,'rows':rows,'structure_passed':True},ensure_ascii=False,indent=2));print(cp)
