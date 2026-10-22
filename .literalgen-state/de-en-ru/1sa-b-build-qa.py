from pathlib import Path
import json
base=Path('Tools/LiteralGen/outputs'); qa=[]
def put(lang,ch,v,lit=None,diff=None,repl=None,reason='Native grammar or definite wording correction'):
 found=[]
 for p in (base/lang/'09_1SA').glob(f'1SA_{ch:03d}*.tsv'):
  for row in p.read_text().splitlines():
   if row.split('\t')[0]==str(v):found.append((p,row))
 assert len(found)==1,(lang,ch,v)
 p,old=found[0]; a=old.split('\t')
 if lit is not None:a[1]=lit
 if diff is not None:a[2]=diff
 if repl:
  for x,y in repl:
   assert x in a[1],(lang,ch,v,x)
   a[1]=a[1].replace(x,y)
 new='\t'.join(a);assert new!=old
 qa.append({'path':str(p),'verse':v,'old_row':old,'new_row':new,'reason':reason})
put('ru',12,3,repl=[('чей вол я взял, и чей осёл я взял','чьего вола я взял, и чьего осла я взял')])
put('de',12,21,lit='Und weicht nicht ab, um den Nichtigkeiten nachzufolgen, die nicht nützen und nicht retten, denn nichtig sind sie.',reason='Use native plural antecedent to preserve the explicit plural verbs and pronoun.')
put('ru',12,21,lit='И не уклоняйтесь вслед за пустыми вещами, которые не приносят пользы и не избавляют, ибо они пустота.',reason='Native grammatical supplement preserves the plural verbs and pronoun.')
put('ru',12,25,diff='Делание зла усилено повтором глагольного корня; конец выражен страдательной формой.')
put('de',13,17,diff='Die verheerende Schar ist als Subjekt genannt, die drei Abteilungen beschreiben ihre Gliederung.')
put('ru',14,24,diff='Хлеб назван дважды; состояние людей выражено страдательным глаголом угнетения.')
put('ru',14,47,repl=[('налагал осуждение','выносил осуждение')],diff='Вефор не назван; Саул овладел царством. Моав и Едом сохранены как имена.')
put('de',15,29,lit='Und auch der Ruhm Israels wird nicht lügen und nicht bereuen, denn er ist kein Mensch, dass er bereute.“')
put('ru',15,23,repl=[('Он отверг тебя быть царём','Он отверг тебя как царя')])
put('ru',15,26,repl=[('Господь отверг тебя от того, чтобы быть царём над Израилем','Господь отверг тебя, чтобы ты не был царём над Израилем')])
put('en',15,27,diff='The Hebrew leaves the person grabbing unnamed; BSB explicitly names Saul.')
put('en',15,28,diff='Close to the Hebrew.')
put('de',17,34,repl=[('Und wenn der Löwe und der Bär kamen und ein Schaf aus der Herde wegtrugen,','Und es kam der Löwe, auch der Bär, und trug ein Schaf aus der Herde weg,')],reason='Preserve singular coming and carrying verbs while keeping an additive mention of the bear.')
put('ru',17,34,repl=[('И когда приходили лев и медведь и уносили овцу из стада,','И приходил лев, а также медведь, и уносил овцу из стада,')],reason='Preserve singular narrative verbs with a native additive construction.')
put('ru',17,39,repl=[('И опоясал Давид его мечом','И опоясался Давид его мечом')])
put('de',17,40,repl=[('in das Hirtengerät, das er hatte','in seine Hirtentasche')],diff='Nah am Hebräischen.',reason='The contextual container is a native bag; remove an incorrect difference about playing a sling.')
put('ru',17,40,repl=[('в свой пастушеский сосуд, то есть в сумку','в свою пастушескую сумку, в котомку')],reason='Use a native contextual container noun rather than an unintended hard vessel.')
put('de',17,49,repl=[('in das Gerät','in die Tasche')])
put('ru',17,49,repl=[('в сосуд','в сумку')])
put('ru',18,2,repl=[('в дом своего отца','в дом его отца')],reason='Avoid a reflexive father reference attaching to Saul, the governing subject.')
keys=[(x['path'],x['verse']) for x in qa];assert len(keys)==len(set(keys))
for x in qa:
 a=x['new_row'].split('\t');assert len(a)==3 and len(a[2].split())<=60
Path('.literalgen-state/de-en-ru/1sa-b-qa.json').write_text(json.dumps(qa,ensure_ascii=False,indent=2)+'\n')
print(len(qa))
