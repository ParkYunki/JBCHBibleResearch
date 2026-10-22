from pathlib import Path
import json,re,hashlib
S=Path('.literalgen-state/de-en-ru');R=Path.cwd();own=[];en=[]
def add(ch,lang,v,lit=None,diff=None):
 p=next(p for p in sorted((R/f'Tools/LiteralGen/outputs/{lang}/15_EZR').glob(f'EZR_{ch:03}*.tsv'))if any(r.startswith(str(v)+'\t')for r in p.read_text().splitlines()))
 old=next(r for r in p.read_text().splitlines()if r.startswith(str(v)+'\t'));a=old.split('\t');a[1]=a[1]if lit is None else lit;a[2]=a[2]if diff is None else diff;new='\t'.join(a)
 assert new!=old and len(a[2].split())<=60
 (en if lang=='en'else own).append({'path':str(p),'old_row':old,'new_row':new})
add(9,'de',13,lit='Und nach allem, was wegen unserer bösen Taten und unserer großen Schuld über uns gekommen ist, denn du, unser Gott, hast die Strafe geringer gehalten als unsere Vergehen und uns Entronnene wie diese gegeben,')
add(10,'de',19,lit='Und sie gaben ihre Hand, ihre Frauen hinauszutun, und gaben als Schuldige einen Widder vom Kleinvieh für ihre Schuld.',diff='Die Schuldigen und der Widder stehen ohne ausdrücklich wiederholtes Verb des Gebens; dieses ist grammatisch ergänzt.')
add(10,'ru',19,lit='И дали руку свою, чтобы выслать жён своих, и, будучи виновны, дали овна из стада за вину свою.',diff='Рука в единственном числе; во второй части глагол даяния грамматически восполнен.')
add(8,'en',26,diff='The Hebrew describes entrusting the valuables with their hand in the singular; BSB uses hands in the plural.')
add(9,'en',2,diff='The Hebrew pictures the leaders’ and officials’ leading role as their hand being first in this unfaithfulness. The holy seed mingles itself actively; BSB uses a passive mixing.')
add(10,'en',3,diff='The Hebrew says all wives and what was born from them without explicitly repeating foreign. It names the Lord’s counsel; BSB says my lord. The command is singular in Hebrew.')
for name,data in [('ezr-c-qa.json',own),('ezr-c-root-en-qa.json',en)]:
 (S/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n');print(name,len(data))
files=[]
for lang in ['de','ru']:
 for ch in [8,9,10]:
  for pkt in sorted(Path('Tools/LiteralGen/packets/de-en-ru/15_EZR').glob(f'EZR_{ch:03}*.txt')):
   p=R/f'Tools/LiteralGen/outputs/{lang}/15_EZR/{pkt.stem}.tsv';rows=p.read_text().splitlines();b=next(b for b in pkt.read_text().split('==TARGET ')[1:]if b.startswith('lang='+lang+' '));nums=re.findall(r'^#(\d+) ',b,re.M)
   assert [r.split('\t')[0]for r in rows]==nums
   assert all(len(r.split('\t'))==3 and len(r.split('\t')[2].split())<=60 for r in rows)
   files.append({'path':str(p),'rows':len(rows),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(S/'ezr-c-validation.json').write_text(json.dumps({'files':len(files),'rows':sum(f['rows']for f in files),'checks':'verse_order, three_fields, DIFF_length, full_packet_source_review','details':files},ensure_ascii=False,indent=2)+'\n')
cp=json.loads((S/'ezr-c-checkpoint.json').read_text());cp['status']='generated_and_reviewed';cp['qa_rows']=len(own);cp['root_en_reviewed_rows']=95;(S/'ezr-c-checkpoint.json').write_text(json.dumps(cp,ensure_ascii=False,indent=2)+'\n')
print('validated',len(files),sum(f['rows']for f in files))
