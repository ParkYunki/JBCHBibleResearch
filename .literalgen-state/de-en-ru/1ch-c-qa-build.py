from pathlib import Path
import json,re,hashlib
S=Path('.literalgen-state/de-en-ru'); BASE=Path.cwd(); candidates=[]
def add(ch,lang,v,lit=None,diff=None,bucket=None):
 p=next(p for p in sorted((BASE/f'Tools/LiteralGen/outputs/{lang}/13_1CH').glob(f'1CH_{ch:03}*.tsv')) if any(r.startswith(str(v)+'\t') for r in p.read_text().splitlines()))
 old=next(r for r in p.read_text().splitlines() if r.startswith(str(v)+'\t'));a=old.split('\t'); a[1]=a[1] if lit is None else lit;a[2]=a[2] if diff is None else diff;new='\t'.join(a)
 assert old!=new and len(a[2].split())<=60
 (candidates if bucket is None else bucket).append({'path':str(p),'old_row':old,'new_row':new})
add(17,'de',7,lit='Und nun sollst du so zu meinem Knecht David sagen: So spricht der HERR Zebaoth: Ich habe dich von der Weide genommen, von hinter der Herde, damit du Fürst über mein Volk Israel seist.')
add(17,'ru',7,lit='И теперь так скажи рабу Моему Давиду: так говорит Господь Саваоф: Я взял тебя с пастбища, от следования за стадом, чтобы ты был правителем над народом Моим Израилем.')
add(19,'ru',14,lit='И приблизился Иоав и народ, который с ним, к Сириянам для битвы; и они побежали от него.')
add(22,'de',12,lit='Nur gebe dir der HERR Einsicht und Verständnis und bestelle dich über Israel, damit du das Gesetz des HERRN, deines Gottes, bewahrst.')
add(22,'ru',12,lit='Только пусть даст тебе Господь рассудительность и разумение и поставит тебя над Израилем, чтобы ты соблюдал закон Господа, Бога твоего.')
add(23,'de',13,lit='Die Söhne Amrams: Aaron und Mose. Und Aaron wurde abgesondert, um ihn zum Hochheiligen zu heiligen, ihn und seine Söhne auf ewig, um vor dem HERRN zu räuchern, ihm zu dienen und in seinem Namen zu segnen auf ewig.',diff='Aaron wird als Hochheiliger geheiligt; seine Söhne werden ebenfalls genannt.')
add(23,'ru',13,lit='Сыновья Амрама: Аарон и Моисей. И отделён был Аарон, чтобы освятить его как святого святых, его и сыновей его навеки, чтобы воскурять пред Господом, служить Ему и благословлять именем Его навеки.',diff='Аарон освящается как святой святых; отдельного слова «лице» нет.')
en=[]
add(28,'en',8,diff='The Hebrew says in the ears of our God and calls the inheritors your sons after you; BSB expresses hearing and uses your descendants.',bucket=en)
add(28,'en',18,diff='The Hebrew describes the cherubim spreading out and covering the ark without an explicit wings noun; BSB supplies their wings.',bucket=en)
add(29,'en',11,diff='The Hebrew names victory and describes God reflexively as raising Himself to be head over all; BSB uses splendor and the passive You are exalted.',bucket=en)
native=[]
add(29,'ru',19,lit='И Соломону, сыну моему, дай целое сердце соблюдать Твои заповеди, Твои свидетельства и Твои уставы, и делать всё, и построить дворец, для которого я сделал приготовления».',bucket=native)
for name,data in [('1ch-c-qa.json',candidates),('1ch-c-root-en-qa.json',en),('1ch-c-root-native-qa.json',native)]:
 (S/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
 print(name,len(data))
cp=json.loads((S/'1ch-c-checkpoint.json').read_text());cp['assigned']={'de':[17,28],'ru':[17,28],'en':[17,21]};cp['status']='generated_and_reviewed';cp['qa_rows']=len(candidates);(S/'1ch-c-checkpoint.json').write_text(json.dumps(cp,ensure_ascii=False,indent=2)+'\n')
files=[]
for lang,chs in [('de',range(17,29)),('ru',range(17,29)),('en',range(17,22))]:
 for ch in chs:
  for pkt in sorted(Path('Tools/LiteralGen/packets/de-en-ru/13_1CH').glob(f'1CH_{ch:03}*.txt')):
   p=BASE/f'Tools/LiteralGen/outputs/{lang}/13_1CH/{pkt.stem}.tsv';rows=p.read_text().splitlines();b=next(b for b in pkt.read_text().split('==TARGET ')[1:] if b.startswith('lang='+lang+' '));nums=re.findall(r'^#(\d+) ',b,re.M)
   assert [r.split('\t')[0]for r in rows]==nums
   assert all(len(r.split('\t'))==3 and len(r.split('\t')[2].split())<=60 and (lang!='en' or r.split('\t')[1]=='=')for r in rows)
   files.append({'path':str(p),'rows':len(rows),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(S/'1ch-c-validation.json').write_text(json.dumps({'files':len(files),'rows':sum(f['rows']for f in files),'checks':'verse_order, 3_fields, DIFF_length, en_literal, packet_source_review','details':files},ensure_ascii=False,indent=2)+'\n')
print(len(files),sum(f['rows']for f in files))
