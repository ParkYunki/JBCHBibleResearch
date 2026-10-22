# coding: utf-8
from pathlib import Path
import json,hashlib,re
S=Path('.literalgen-state/de-en-ru')
def row(lang,ch,v):
 for p in sorted(Path(f'Tools/LiteralGen/outputs/{lang}/12_2KI').glob(f'2KI_{ch:03}*.tsv')):
  for x in p.read_text().splitlines():
   if x.split('\t')[0]==str(v):return p,x
 raise ValueError((lang,ch,v))
def candidate(ls,l,ch,v,lit=None,diff=None,replace=None,why=''):
 p,old=row(l,ch,v);cols=old.split('\t');new=cols.copy()
 if lit is not None:new[1]=lit
 if diff is not None:new[2]=diff
 if replace:
  for a,b in replace:
   assert a in new[1],(l,ch,v,a);new[1]=new[1].replace(a,b)
 nr='\t'.join(new);assert nr!=old
 assert not any(a['path']==str(p) and a['verse']==v for a in ls)
 ls.append({'path':str(p),'verse':v,'old_row':old,'new_row':nr,'reason':why})
a=[]
candidate(a,'ru',17,1,replace=[('в Самарии над Израилем на девять лет.','в Самарии над Израилем и царствовал девять лет.')],why='Avoid implying an advance fixed term of appointment; express duration idiomatically.')
candidate(a,'de',17,16,diff='Ein Gussbild wird im Singular genannt, dann zwei Kälber; das Anfertigen wird vor dem Ascherabild wiederholt.',why='Definite singular/plural and repeated verb contrast.')
candidate(a,'de',17,25,replace=[('diese töteten unter ihnen.','diese töteten einige von ihnen.')],why='Minimal object supplement makes German transitive killing clause grammatical.')
candidate(a,'ru',17,25,replace=[('те убивали среди них.','те убивали некоторых из них.')],why='Minimal object supplement makes the killing clause idiomatic.')
candidate(a,'de',17,31,diff='Das Verbrennen wird ausdrücklich mit dem Feuer verbunden.',why='Target omits explicit fire.')
candidate(a,'ru',17,34,diff='Закон и заповедь стоят в единственном числе.',why='Target has plural commandments.')
candidate(a,'de',19,21,replace=[('Dich verachtet, dich verspottet die Jungfrau, die Tochter Zion; hinter dir schüttelt den Kopf die Tochter Jerusalem.','Dich hat die Jungfrau, die Tochter Zion, verachtet und verspottet; hinter dir hat die Tochter Jerusalem den Kopf geschüttelt.')],diff='Das Verachten, Verspotten und Kopfschütteln stehen in vollendeten Verbformen.',why='Preserve completed Hebrew forms as already retained in Russian.')
candidate(a,'ru',20,18,replace=[('которых ты родишь','которых ты породишь')],why='Male father begets rather than gives birth.')
candidate(a,'ru',21,6,replace=[('занимался вызыванием мёртвых и волшебниками','прибегал к вызыванию мёртвых и к волшебникам')],why='Use a natural government for both coordinated terms.')
candidate(a,'de',23,13,replace=[('den Scheusal der Sidonier','das Scheusal der Sidonier'),('den Scheusal Moabs','das Scheusal Moabs')],why='Scheusal is neuter.')
candidate(a,'de',23,19,replace=[('um zu erzürnen','um Zorn zu erregen')],why='Natural German expression without inserting an explicit object absent from O.')
candidate(a,'ru',23,19,replace=[('чтобы прогневать','чтобы вызвать гнев')],why='Natural Russian without an omitted required object.')
candidate(a,'ru',24,1,replace=[('потом повернул и восстал','потом повернулся и восстал')],why='Intransitive turn requires reflexive Russian form.')
(S/'2ki-c-qa.json').write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n')
b=[]
candidate(b,'en',22,15,diff='The Hebrew says the man sent them “to me”; BSB leaves the destination unstated.',why='Restore a definite omitted phrase difference.')
candidate(b,'en',23,35,diff='The Hebrew describes each person’s assessment; BSB expresses it as his wealth.',why='The original DIFF incorrectly made each man the subject of paying; O makes Jehoiakim the subject of exacting.')
candidate(b,'en',25,21,diff='Judah is the subject of going into exile in Hebrew; BSB expresses the exile passively.',why='Definite voice difference.')
candidate(b,'en',25,28,diff='The Hebrew uses the singular “throne” of the kings; BSB uses the plural “thrones”.',why='Definite singular/plural difference.')
(S/'2ki-c-root-en-qa.json').write_text(json.dumps(b,ensure_ascii=False,indent=2)+'\n')
(S/'2ki-c-root-native-qa.json').write_text('[]\n')
cp=json.loads((S/'2ki-c-checkpoint.json').read_text());files=cp['new_files'];issues=[];manifest=[]
for f in files:
 p=Path(f['path']);data=p.read_bytes();lines=data.decode().splitlines();ch=int(p.stem.split('_')[1]);l=p.parts[-3]
 packet=Path('Tools/LiteralGen/packets/de-en-ru/12_2KI')/(p.stem+'.txt');s=packet.read_text();t=next(t for t in s.split('==TARGET ')[1:] if t.startswith(f'lang={l} '));expected=[int(x) for x in re.findall(r'^#(\d+) ',t,re.M)]
 assert [int(x.split('\t')[0]) for x in lines]==expected
 for x in lines:
  c=x.split('\t');assert len(c)==3 and all(c) and len(c[2].split())<=60
  if l=='en':assert c[1]=='='
 manifest.append({'path':str(p),'rows':len(lines),'sha256':hashlib.sha256(data).hexdigest()})
cp.update({'status':'complete','generated_files':len(files),'generated_rows':sum(f['rows'] for f in files),'own_qa_rows':len(a),'root_en_reviewed_rows':107,'root_en_qa_rows':len(b),'root_native_reviewed_rows':60,'root_native_qa_rows':0,'all_assigned_verses_reviewed':True,'excluded_root_candidates':['de017:23','ru017:23','de018:21']})
(S/'2ki-c-checkpoint.json').write_text(json.dumps(cp,ensure_ascii=False,indent=2)+'\n')
(S/'2ki-c-created.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
(S/'2ki-c-validation.json').write_text(json.dumps({'files':len(files),'rows':sum(f['rows'] for f in files),'packet_verse_sequences':True,'three_columns':True,'all_english_literal_equals':True,'difference_word_limit':60,'issues':issues,'review':'All own O/TARGET rows and root English022–025/native025 checked. Exact candidates only; no TSV edits.','qa_rows':len(a)+len(b)},ensure_ascii=False,indent=2)+'\n')
print({'files':len(files),'rows':sum(f['rows'] for f in files),'own_qa':len(a),'root_en_qa':len(b),'root_native_qa':0})
