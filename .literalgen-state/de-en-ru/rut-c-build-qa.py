from pathlib import Path
import json,re,hashlib
base=Path.cwd();state=base/'.literalgen-state/de-en-ru';qa=[]
def change(ch,l,v,lit=None,diff=None,root=False):
 p=base/f'Tools/LiteralGen/outputs/{l}/08_RUT/RUT_{ch:03}.tsv';old=next(r for r in p.read_text().splitlines()if r.split('\t')[0]==str(v));a=old.split('\t')
 if lit is not None:a[1]=lit
 if diff is not None:a[2]=diff
 if '\t'.join(a)!=old: (rootqa if root else qa).append({'path':str(p),'verse':v,'old_row':old,'new_row':'\t'.join(a)})
change(3,'ru',5,lit='И сказала ей она: «Всё, что ты говоришь мне, я сделаю».')
change(3,'de',10,lit='Und er sagte: „Gesegnet seist du vom HERRN, meine Tochter! Du hast deine letzte Güte besser erwiesen als die erste, indem du nicht den jungen Männern nachgegangen bist, ob arm oder reich.')
change(4,'de',11,lit='Und das ganze Volk am Tor und die Ältesten sagten: „Zeugen! Der HERR mache die Frau, die in dein Haus kommt, wie Rahel und wie Leah, die beide das Haus Israel gebaut haben. Und schaffe dir Vermögen in Ephratha und rufe einen Namen aus in Bethlehem.')
change(4,'ru',7,diff='Обувь названа сандалией, а не сапогом; дающий передаёт её своему ближнему.')
change(4,'ru',15,lit='И будет он для тебя тем, кто возвращает душу и поддерживает твою седину, ибо твоя невестка, которая любит тебя, родила его, она, которая тебе лучше семи сыновей».')
rootqa=[]
change(3,'en',17,diff='The Hebrew names six of barley without specifying the measure and says not to return “empty”; BSB supplies “measures” and expands this to “empty-handed”.',root=True)
change(4,'en',3,diff='The Hebrew says Naomi “has sold” the portion of the field; BSB has “is selling”.',root=True)
change(4,'en',16,diff='The child is placed at her bosom; BSB says “on her lap”.',root=True)
(state/'rut-c-qa.json').write_text(json.dumps(qa,ensure_ascii=False,indent=2)+'\n');(state/'rut-c-root-en-qa.json').write_text(json.dumps(rootqa,ensure_ascii=False,indent=2)+'\n')
files=[];m={(x['path'],x['verse']):x['new_row']for x in qa}
for l in ['de','ru']:
 texts=[]
 for ch in [3,4]:
  p=base/f'Tools/LiteralGen/packets/de-en-ru/08_RUT/RUT_{ch:03}.txt';b=next(x for x in p.read_text().split('==TARGET ')[1:]if x.startswith(f'lang={l} '));nums=re.findall(r'^#(\d+) ',b,re.M)
  out=base/f'Tools/LiteralGen/outputs/{l}/08_RUT/{p.stem}.tsv';rows=out.read_text().splitlines();assert [r.split('\t')[0]for r in rows]==nums
  for r in rows:
   a=r.split('\t');assert len(a)==3 and all(a)and len(a[2].split())<=60
   texts.append(m.get((str(out),int(a[0])),r).split('\t')[1])
  files.append({'path':str(out),'rows':len(rows),'sha256':hashlib.sha256(out.read_bytes()).hexdigest()})
 text='\n'.join(texts)
 for a,b in [('„','“'),('‚','‘')]if l=='de'else[('«','»'),('„','“')]:assert text.count(a)==text.count(b),(l,a,text.count(a),text.count(b))
cp=json.loads((state/'rut-c-checkpoint.json').read_text());cp.update(status='generation_and_full_qa_complete',completed_chapters=[3,4],remaining_chapters=[],qa_candidates=len(qa),root_en_independent_rows=40,root_en_qa_candidates=len(rootqa));(state/'rut-c-checkpoint.json').write_text(json.dumps(cp,ensure_ascii=False,indent=2)+'\n')
(state/'rut-c-validation.json').write_text(json.dumps({'status':'passed','files':files,'file_count':len(files),'rows':sum(f['rows']for f in files),'all_assigned_verses_reviewed':True,'qa_candidates':len(qa),'root_en_independent_rows':40,'root_en_qa_candidates':len(rootqa),'existing_outputs_modified':False},ensure_ascii=False,indent=2)+'\n');print('files',len(files),'rows',sum(f['rows']for f in files),'QA',len(qa),'root QA',len(rootqa))
