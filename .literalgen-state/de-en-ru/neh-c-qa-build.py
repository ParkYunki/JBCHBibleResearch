from pathlib import Path
import json,re,hashlib
S=Path('.literalgen-state/de-en-ru');R=Path.cwd();own=[]
def add(ch,lang,v,lit=None,diff=None):
 p=next(p for p in sorted((R/f'Tools/LiteralGen/outputs/{lang}/16_NEH').glob(f'NEH_{ch:03}*.tsv'))if any(r.startswith(str(v)+'\t')for r in p.read_text().splitlines()))
 old=next(r for r in p.read_text().splitlines()if r.startswith(str(v)+'\t'));a=old.split('\t');a[1]=a[1]if lit is None else lit;a[2]=a[2]if diff is None else diff;new='\t'.join(a)
 assert old!=new and len(a[2].split())<=60
 own.append({'path':str(p),'old_row':old,'new_row':new})
add(11,'de',25,lit='Und bei den Dörfern mit ihren Feldern wohnten einige von den Söhnen Judas in Kirjath-Arba und seinen Töchtern und in Dibon und seinen Töchtern und in Kabzeel und seinen Dörfern,')
add(11,'ru',25,lit='И в селениях с полями их некоторые из сынов Иуды жили в Кириаф-Арбе и дочерях её, и в Дивоне и дочерях его, и в Иекавцеиле и сёлах его,')
add(12,'ru',28,diff='Близко к еврейскому.')
add(12,'ru',42,lit='и Маасея, и Шемаия, и Елеазар, и Уззий, и Иоханан, и Малхия, и Елам, и Езер; и раздались голоса певцов, а Израхия — надзиратель.',diff='Певцы дают услышать свои голоса; Израхия отдельно назван надзирателем.')
add(12,'de',45,lit='Und sie bewahrten den Dienst ihres Gottes und den Dienst der Reinigung; ebenso die Sänger und die Torhüter nach dem Gebot Davids und seines Sohnes Salomo.')
add(12,'ru',45,lit='И хранили они службу Бога своего и службу очищения; также певцы и привратники по заповеди Давида и Соломона, сына его.')
(S/'neh-c-qa.json').write_text(json.dumps(own,ensure_ascii=False,indent=2)+'\n')
files=[]
for lang in ['de','ru']:
 for ch in [10,11,12]:
  for pkt in sorted(Path('Tools/LiteralGen/packets/de-en-ru/16_NEH').glob(f'NEH_{ch:03}*.txt')):
   p=R/f'Tools/LiteralGen/outputs/{lang}/16_NEH/{pkt.stem}.tsv';rows=p.read_text().splitlines();b=next(b for b in pkt.read_text().split('==TARGET ')[1:]if b.startswith('lang='+lang+' '));nums=re.findall(r'^#(\d+) ',b,re.M)
   assert [r.split('\t')[0]for r in rows]==nums
   assert all(len(r.split('\t'))==3 and len(r.split('\t')[2].split())<=60 for r in rows)
   files.append({'path':str(p),'rows':len(rows),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(S/'neh-c-validation.json').write_text(json.dumps({'files':len(files),'rows':sum(f['rows']for f in files),'checks':'verse_order, three_fields, DIFF_length, full_packet_source_review','details':files},ensure_ascii=False,indent=2)+'\n')
cp=json.loads((S/'neh-c-checkpoint.json').read_text());cp['status']='native_generated_and_reviewed_root_QA_pending';cp['qa_rows']=len(own);(S/'neh-c-checkpoint.json').write_text(json.dumps(cp,ensure_ascii=False,indent=2)+'\n')
print('validated',len(files),sum(f['rows']for f in files),'QA',len(own))
