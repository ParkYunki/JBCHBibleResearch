# -*- coding: utf-8 -*-
import json,hashlib,re
from pathlib import Path
S=Path('.literalgen-state/de-en-ru'); cp=json.loads((S/'1ki-a-checkpoint.json').read_text()); own=[]; en=[]
def row(lang,ch,v):
 for p in Path(f'Tools/LiteralGen/outputs/{lang}/11_1KI').glob(f'1KI_{ch:03}*.tsv'):
  for r in p.read_text().splitlines():
   if r.split('\t')[0]==str(v):return p,r
 raise ValueError((lang,ch,v))
def replace(out,lang,ch,v,a,b,col=1,diff=None):
 p,old=row(lang,ch,v);fields=old.split('\t');assert a in fields[col],(lang,ch,v,a);fields[col]=fields[col].replace(a,b)
 if diff is not None:fields[2]=diff
 new='\t'.join(fields);assert new!=old;out.append(dict(path=str(p),verse=v,old_row=old,new_row=new))
replace(own,'de',1,13,'Mein Sohn Salomo, dein Sohn','Dein Sohn Salomo')
replace(own,'ru',1,2,'будет ему ухаживающей','будет ухаживать за ним')
replace(own,'ru',1,12,'дай мне, пожалуйста, посоветовать тебе совет','позволь мне, пожалуйста, дать тебе совет',diff='Сохранены призыв идти и просьба; жизнь названа душой.')
replace(own,'de',2,44,'dessen dein Herz bewusst ist','das dein Herz kennt')
replace(own,'ru',2,26,'ты мужчина смерти','ты человек смерти')
replace(own,'ru',2,27,'изгнал Авиафара от священства Господу','удалил Авиафара от служения священником Господа')
replace(own,'ru',3,9,'этот Твой весомый народ','этот Твой великий народ')
replace(own,'de',3,18,'nach meiner Geburt','nach meiner Entbindung')
replace(own,'de',3,26,'über ihren Sohn entbrannt','für ihren Sohn entbrannt')
replace(own,'ru',3,26,'её сострадание согрелось к её сыну','в ней разгорелось сострадание к её сыну')
replace(own,'ru',5,13,'набрал повинность со всего Израиля','набрал со всего Израиля людей на повинность')
replace(own,'en',2,29,'The Hebrew explicitly repeats Solomon as sender; BSB does so too.','Close to the Hebrew.',2)
replace(own,'en',1,43,'The Hebrew begins with an affirmative “indeed”; BSB has “Not at all.”','Close to the Hebrew.',2)
replace(en,'en',7,42,'Close to the Hebrew.','The Hebrew places the bowls of the capitals on the front of the pillars; BSB places them atop the pillars.',2)
for name,data in [('1ki-a-qa.json',own),('1ki-a-root-en-qa.json',en),('1ki-a-root-native-qa.json',[])]:
 assert len({(x['path'],x['verse']) for x in data})==len(data)
 (S/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
files=cp['created'];rows=0
for f in files:
 p=Path(f);lines=p.read_text().splitlines();rows+=len(lines)
 packet=Path('Tools/LiteralGen/packets/de-en-ru/11_1KI')/(p.stem+'.txt');s=packet.read_text();lang=p.parts[3];target=s.split('==TARGET lang='+lang)[1].split('==TARGET')[0];expected=[int(x) for x in re.findall(r'^#(\d+) ',target,re.M)]
 assert [int(x.split('\t')[0]) for x in lines]==expected
 for line in lines:
  fields=line.split('\t');assert len(fields)==3 and all(fields)
  assert len(fields[2].split())<=60
  if lang=='en':assert fields[1]=='='
protected=json.loads((S/'11_1KI-protected.json').read_text());bad=[f for f,h in protected.items() if not Path(f).exists() or hashlib.sha256(Path(f).read_bytes()).hexdigest()!=h];assert not bad
rooten=list(Path('Tools/LiteralGen/outputs/en/11_1KI').glob('1KI_00[4-7]*.tsv'));rootnative=[p for l in ['de','ru'] for p in Path(f'Tools/LiteralGen/outputs/{l}/11_1KI').glob('1KI_007*.tsv')]
validation=dict(own_files=len(files),own_rows=rows,own_full_qa=True,own_qa_candidates=len(own),root_en_files=len(rooten),root_en_rows=sum(len(p.read_text().splitlines()) for p in rooten),root_en_full_qa=True,root_en_candidates=len(en),root_native_files=len(rootnative),root_native_rows=sum(len(p.read_text().splitlines()) for p in rootnative),root_native_full_qa=True,root_native_candidates=0,protected_files=len(protected),protected_unchanged=True,tsv_direct_changes=False)
(S/'1ki-a-validation.json').write_text(json.dumps(validation,ensure_ascii=False,indent=2)+'\n');(S/'1ki-a-created.json').write_text(json.dumps({f:hashlib.sha256(Path(f).read_bytes()).hexdigest() for f in files},indent=2)+'\n');cp.update(status='complete',validation=validation,qa_files=['1ki-a-qa.json','1ki-a-root-en-qa.json','1ki-a-root-native-qa.json']);(S/'1ki-a-checkpoint.json').write_text(json.dumps(cp,ensure_ascii=False,indent=2)+'\n');print(validation)
