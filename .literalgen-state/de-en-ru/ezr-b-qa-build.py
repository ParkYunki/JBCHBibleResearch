from pathlib import Path
import json,re
q=[]
def add(l,ch,v,lit=None,diff=None):
 p=next(p for p in Path(f'Tools/LiteralGen/outputs/{l}/15_EZR').glob(f'EZR_{ch:03}*.tsv') if any(s.startswith(str(v)+'\t') for s in p.read_text().splitlines()));old=next(s for s in p.read_text().splitlines() if s.startswith(str(v)+'\t'));a=old.split('\t');a[1]=lit if lit is not None else a[1];a[2]=diff if diff is not None else a[2]
 if old!='\t'.join(a):q.append({'path':str(p),'old_row':old,'new_row':'\t'.join(a)})
for v in [2,3,4,5]:add('ru',7,v,diff='Близко к еврейскому.')
add('de',4,14,'Jetzt, weil wir das Salz des Palastes salzen und es uns nicht ziemt, die Blöße des Königs zu sehen, deswegen haben wir gesandt und dem König mitgeteilt,')
add('de',5,10,'Und auch ihre Namen fragten wir sie, um dir Mitteilung zu machen, damit wir den Namen der Männer aufschrieben, die an ihrer Spitze waren.')
add('ru',5,10,'И также их имена спросили мы у них, чтобы сообщить тебе, чтобы написать имя мужей, которые во главе их.')
add('de',6,5,'Und auch die Geräte des Hauses Gottes aus Gold und Silber, die Nebukadnezar aus dem Tempel in Jerusalem herausgebracht und nach Babel gebracht hat, sollen sie zurückgeben; und jedes komme zum Tempel in Jerusalem an seinen Ort, und du sollst es im Haus Gottes niederlegen.“')
add('ru',6,5,'И также сосуды дома Бога из золота и серебра, которые Навуходоносор вынес из храма в Иерусалиме и принёс в Вавилон, пусть возвратят; и пусть каждый придёт в храм в Иерусалиме на своё место, и ты положи их в доме Бога».')
add('de',6,11,'Und von mir ist ein Befehl gegeben: Jedem Menschen, der dieses Wort ändert, soll ein Balken aus seinem Haus gerissen werden, und aufgerichtet soll er daran geschlagen werden; und sein Haus soll deswegen zum Misthaufen gemacht werden.')
Path('.literalgen-state/de-en-ru/ezr-b-qa.json').write_text(json.dumps(q,ensure_ascii=False,indent=2))
q=[]
add('en',5,10,diff='The Aramaic says the name of the men at their heads, with name singular; BSB uses names of their leaders.')
add('en',7,12,diff='The Aramaic includes a word of completeness before the closing formula; BSB condenses the closing to Greetings.')
add('en',4,9,diff='The Aramaic lists the Susa people, Dahites, and Elamites separately; BSB combines the final groups as Elamites of Susa. Earlier group names are rendered as judges and officials in BSB.')
Path('.literalgen-state/de-en-ru/ezr-b-root-en-qa.json').write_text(json.dumps(q,ensure_ascii=False,indent=2))
files=[];rows=0
for l in ['de','ru']:
 for ch in range(4,8):
  for p in sorted(Path('Tools/LiteralGen/packets/de-en-ru/15_EZR').glob(f'EZR_{ch:03}*.txt')):
   t=next(x for x in p.read_text().split('==TARGET ')[1:] if x.startswith('lang='+l+' '));vs=re.findall(r'^#(\d+) ',t,re.M);o=Path(f'Tools/LiteralGen/outputs/{l}/15_EZR')/(p.stem+'.tsv');rr=o.read_text().splitlines();assert [x.split('\t')[0] for x in rr]==vs
   for x in rr:assert len(x.split('\t'))==3 and len(x.split('\t')[2].split())<=60
   files.append(str(o));rows+=len(rr)
cp={'book':'15_EZR','assignment':'de/ru004–007','phase':'complete_pending_book_check','files':len(files),'rows':rows,'qa_candidates':10,'root_en_qa_candidates':3}
Path('.literalgen-state/de-en-ru/ezr-b-checkpoint.json').write_text(json.dumps(cp,ensure_ascii=False,indent=2));Path('.literalgen-state/de-en-ru/ezr-b-validation.json').write_text(json.dumps({'files':files,'rows':rows,'structure_passed':True},ensure_ascii=False,indent=2));print(cp)
