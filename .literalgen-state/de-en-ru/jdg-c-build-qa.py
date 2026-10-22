from pathlib import Path
import json,re,hashlib
base=Path.cwd();state=base/'.literalgen-state/de-en-ru';qa={}
def change(ch,l,v,lit=None,diff=None):
 for p in sorted((base/f'Tools/LiteralGen/outputs/{l}/07_JDG').glob(f'JDG_{ch:03}*.tsv')):
  old=next((r for r in p.read_text().splitlines()if r.split('\t')[0]==str(v)),None)
  if old:
   key=(str(p),v);a=(qa[key]['new_row']if key in qa else old).split('\t')
   if lit is not None:a[1]=lit
   if diff is not None:a[2]=diff
   new='\t'.join(a)
   if new!=old:qa[key]={'path':str(p),'verse':v,'old_row':old,'new_row':new}
   return
 raise ValueError((ch,l,v))
change(15,'ru',13,diff='Связывание выражено усиленным «непременно свяжем», и «рука» стоит в единственном числе. Его подняли «со скалы», а не просто повели из ущелья.')
change(16,'de',12,diff='Nah am Hebräischen.')
change(16,'ru',28,lit='И воззвал Самсон к Господу, и сказал: «Владыка, Господи, вспомни меня, прошу, и укрепи меня, прошу, лишь в этот раз, Боже, чтобы мне отомстить одной местью филистимлянам за мои два глаза».')
change(17,'de',10,lit='Und Micha sagte zu ihm: „Bleib bei mir und sei mir Vater und Priester; und ich werde dir zehn Silberstücke jährlich geben und eine Ausstattung an Kleidern und deinen Unterhalt.“ Und der Levit ging hin.')
change(18,'ru',16,lit='И шестьсот человек, опоясанных своими орудиями войны, стояли у входа ворот, те, кто из сынов Дановых.')
change(19,'ru',24,lit='Вот, моя дочь, девственница, и его наложница; выведу же я их, и унизьте их, и делайте им то, что добро в ваших глазах. А этому человеку не делайте этого бесчестного дела».')
change(20,'de',13,lit='Und nun gebt die Männer heraus, die Männer, Söhne der Nichtswürdigkeit, in Gibea, damit wir sie töten und das Böse aus Israel wegschaffen.“ Aber die Söhne Benjamins wollten nicht auf die Stimme ihrer Brüder, der Söhne Israels, hören.',diff='Die Übeltäter heißen wörtlich „Söhne der Nichtswürdigkeit“; die Vorlage hat „böse Buben“.')
change(20,'ru',13,lit='И теперь выдайте людей, сынов негодности, которые в Гиве, и мы умертвим их и удалим зло из Израиля». И не хотели сыны Вениаминовы слушать голоса своих братьев, сынов Израилевых.',diff='Негодность описана образом «сынов негодности», а не только развращённых людей.')
change(20,'de',31,lit='Und die Söhne Benjamins zogen dem Volk entgegen und wurden von der Stadt weggezogen; und sie begannen wie Mal um Mal, vom Volk auf den Straßen Menschen tödlich zu schlagen, von denen eine nach Beth-El hinaufgeht und eine nach Gibea im Feld: etwa dreißig Mann in Israel.')
change(20,'ru',31,lit='И вышли сыны Вениаминовы навстречу народу, были оттянуты от города, и начали, как раз за разом, поражать людей из народа насмерть на дорогах, из которых одна поднимается к Вефилю, а одна к Гиве в поле: около тридцати человек в Израиле.')
change(20,'ru',39,lit='И повернули мужи Израилевы в сражении; а Вениамин начал поражать насмерть среди мужей Израилевых около тридцати человек, ибо говорили: «Он непременно поражён перед нами, как в первом сражении».')
change(21,'ru',3,lit='И сказали: «Почему, Господи, Боже Израилев, это произошло в Израиле, чтобы сегодня недоставало в Израиле одного колена?»')
change(21,'de',6,lit='Und die Söhne Israels hatten Mitleid mit Benjamin, seinem Bruder, und sagten: „Heute ist ein Stamm von Israel abgehauen.',diff='Benjamin wird als einzelner „Bruder“ bezeichnet, nicht als „ihre Brüder“.')
change(21,'ru',6,diff='Вениамин назван одним братом; притяжательное местоимение также стоит в единственном числе.')
(state/'jdg-c-qa.json').write_text(json.dumps(list(qa.values()),ensure_ascii=False,indent=2)+'\n')
rootqa=[]
def rootchange(ch,v,diff):
 for p in sorted((base/'Tools/LiteralGen/outputs/en/07_JDG').glob(f'JDG_{ch:03}*.tsv')):
  old=next((r for r in p.read_text().splitlines()if r.split('\t')[0]==str(v)),None)
  if old:rootqa.append({'path':str(p),'verse':v,'old_row':old,'new_row':f'{v}\t=\t{diff}'});return
rootchange(19,29,'The Hebrew describes the division in relation to her bones; BSB renders this as “limb by limb”.')
rootchange(20,18,'The Hebrew asks who will go up “for us” first; BSB says “Who of us”.')
rootchange(20,43,'The Hebrew explicitly describes treading Benjamin down; BSB replaces this with easily overtaking them. The east is expressed as the rising of the sun.')
rootchange(21,10,'The Hebrew describes twelve thousand “men of valor”, without a superlative, and uses the image “mouth of the sword”; BSB has “most valiant” and “put to the sword”.')
(state/'jdg-c-root-en-qa.json').write_text(json.dumps(rootqa,ensure_ascii=False,indent=2)+'\n')
files=[]
for l,chs in [('de',range(15,22)),('ru',range(15,22)),('en',range(15,19))]:
 for ch in chs:
  for p in sorted((base/'Tools/LiteralGen/packets/de-en-ru/07_JDG').glob(f'JDG_{ch:03}*.txt')):
   b=next(x for x in p.read_text().split('==TARGET ')[1:]if x.startswith(f'lang={l} '));nums=re.findall(r'^#(\d+) ',b,re.M)
   out=base/f'Tools/LiteralGen/outputs/{l}/07_JDG/{p.stem}.tsv';rows=out.read_text().splitlines();assert [r.split('\t')[0]for r in rows]==nums
   for r in rows:
    a=r.split('\t');assert len(a)==3 and all(a)and len(a[2].split())<=60;assert l!='en'or a[1]=='='
   files.append({'path':str(out),'rows':len(rows),'sha256':hashlib.sha256(out.read_bytes()).hexdigest()})
for l in ['de','ru']:
 texts=[]
 for f in files:
  if f'/outputs/{l}/'not in f['path']:continue
  for r in Path(f['path']).read_text().splitlines():
   key=(f['path'],int(r.split('\t')[0]));texts.append((qa[key]['new_row']if key in qa else r).split('\t')[1])
 t='\n'.join(texts)
 for a,b in [('„','“'),('‚','‘')]if l=='de'else[('«','»'),('„','“')]:assert t.count(a)==t.count(b),(l,a,t.count(a),t.count(b))
cp=json.loads((state/'jdg-c-checkpoint.json').read_text());cp.update(status='generation_and_full_qa_complete',completed_chapters=list(range(15,22)),remaining_chapters=[],qa_candidates=len(qa),root_en_independent_rows=103,root_en_qa_candidates=len(rootqa));(state/'jdg-c-checkpoint.json').write_text(json.dumps(cp,ensure_ascii=False,indent=2)+'\n')
(state/'jdg-c-validation.json').write_text(json.dumps({'status':'passed','file_count':len(files),'rows':sum(f['rows']for f in files),'files':files,'all_assigned_verses_reviewed':True,'qa_candidates':len(qa),'root_en_independent_rows':103,'root_en_qa_candidates':len(rootqa),'existing_outputs_modified':False},ensure_ascii=False,indent=2)+'\n')
print(len(files),sum(f['rows']for f in files),len(qa),len(rootqa))
