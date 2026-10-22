# -*- coding: utf-8 -*-
import json,re,hashlib
from pathlib import Path
S=Path('.literalgen-state/de-en-ru');cp=json.loads((S/'2ki-a-checkpoint.json').read_text());own=[];root=[]
def row(lang,ch,v):
 for p in Path(f'Tools/LiteralGen/outputs/{lang}/12_2KI').glob(f'2KI_{ch:03}*.tsv'):
  for r in p.read_text().splitlines():
   if r.split('\t')[0]==str(v):return p,r
 raise ValueError((lang,ch,v))
def put(out,lang,ch,v,fn):
 p,old=row(lang,ch,v);f=old.split('\t');fn(f);new='\t'.join(f);assert new!=old;out.append(dict(path=str(p),verse=v,old_row=old,new_row=new))
def sub(out,lang,ch,v,a,b,col=1):
 def f(x):assert a in x[col];x[col]=x[col].replace(a,b)
 put(out,lang,ch,v,f)
for v in range(9,15):
 def fix(f,v=v):
  f[1]=re.sub(r'(?<!начальника )его пятьдесят(?! человек)', 'его пятьдесят человек',f[1]);f[1]=f[1].replace('твоих пятьдесят!','твоих пятьдесят человек!').replace('их пятьдесят;','их пятьдесят человек;')
  if v==13:f[1]=f[1].replace('пусть, пожалуйста, моя душа и душа этих твоих рабов, пятидесяти, будет драгоценна','пусть, пожалуйста, моя душа и душа этих твоих рабов, пятидесяти человек, будут драгоценны')
 put(own,'ru',1,v,fix)
sub(own,'de',3,23,'Die Könige haben einander gewiss vernichtet','Die Könige sind gewiss vernichtet worden')
sub(own,'ru',3,23,'Цари непременно истребили друг друга','Цари непременно истреблены')
put(own,'en',3,23,lambda f:f.__setitem__(2,'The Hebrew describes the kings as destroyed, using a passive verb, and then says each struck his neighbor; BSB describes clashing swords and slaughtering one another.'))
# Improve plainly non-native adverbial and preserve the actual object rather than an invented subject.
sub(own,'ru',5,1,'и с поднятым лицом','и почитаемым')
# Keep the source image in the difference while using native Russian wording.
put_5=own[-1];ff=put_5['new_row'].split('\t');ff[2]='Его почёт описан образом поднятого лица; Сирия названа страной.';put_5['new_row']='\t'.join(ff)
sub(root,'en',5,13,'servants master','servants’ master',2)
put(root,'en',6,10,lambda f:f.__setitem__(2,'The Hebrew says “not once and not twice” and identifies the warning source as the man of God; BSB says “Time and again” and names Elisha.'))
put(root,'en',8,21,lambda f:f.__setitem__(2,'The Hebrew includes the chariot commanders among those he struck; BSB includes them among those surrounded. It says the people fled to their tents, where BSB says his troops fled to their homes.'))
put(root,'en',8,27,lambda f:f.__setitem__(2,'The Hebrew leaves the man unnamed and uses singular “way”; BSB supplies Ahaziah and uses plural “ways.”'))
for name,data in [('2ki-a-qa.json',own),('2ki-a-root-en-qa.json',root)]:
 assert len({(x['path'],x['verse']) for x in data})==len(data)
 (S/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
files=cp['created'];count=0
for fn in files:
 p=Path(fn);lines=p.read_text().splitlines();count+=len(lines);lang=p.parts[3];s=(Path('Tools/LiteralGen/packets/de-en-ru/12_2KI')/(p.stem+'.txt')).read_text();t=s.split('==TARGET lang='+lang)[1].split('==TARGET')[0];nums=list(map(int,re.findall(r'^#(\d+) ',t,re.M)));assert [int(x.split('\t')[0]) for x in lines]==nums
 for line in lines:
  f=line.split('\t');assert len(f)==3 and all(f) and len(f[2].split())<=60
  if lang=='en':assert f[1]=='='
protected=json.loads((S/'12_2KI-protected.json').read_text());bad=[f for f,h in protected.items() if not Path(f).exists() or hashlib.sha256(Path(f).read_bytes()).hexdigest()!=h];assert not bad
rootfiles=[p for p in Path('Tools/LiteralGen/outputs/en/12_2KI').glob('2KI_00[5-8]*.tsv')]
v=dict(created_files=len(files),created_rows=count,own_full_qa=True,own_candidates=len(own),root_en_files=len(rootfiles),root_en_rows=sum(len(p.read_text().splitlines()) for p in rootfiles),root_en_full_qa=True,root_en_candidates=len(root),protected_files=len(protected),protected_unchanged=True,tsv_direct_changes=False)
(S/'2ki-a-validation.json').write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n');(S/'2ki-a-created.json').write_text(json.dumps({f:hashlib.sha256(Path(f).read_bytes()).hexdigest() for f in files},indent=2)+'\n');cp.update(status='complete',validation=v);(S/'2ki-a-checkpoint.json').write_text(json.dumps(cp,ensure_ascii=False,indent=2)+'\n');print(v)
