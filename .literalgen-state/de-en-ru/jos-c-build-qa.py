from pathlib import Path
import json,re,hashlib
base=Path.cwd(); state=base/'.literalgen-state/de-en-ru'; qa={}
def change(ch,lang,v,lit=None,diff=None):
 for p in sorted((base/f'Tools/LiteralGen/outputs/{lang}/06_JOS').glob(f'JOS_{ch:03}*.tsv')):
  old=next((r for r in p.read_text().splitlines() if r.split('\t')[0]==str(v)),None)
  if old:
   key=(str(p),v); row=qa[key]['new_row'] if key in qa else old; a=row.split('\t')
   if lit is not None:a[1]=lit
   if diff is not None:a[2]=diff
   new='\t'.join(a)
   if new!=old:qa[key]={'path':str(p),'verse':v,'old_row':old,'new_row':new}
   return
 raise ValueError((ch,lang,v))
change(17,'de',2,diff='Nah am Hebräischen.')
change(17,'ru',2,diff='Близко к еврейскому.')
change(17,'de',11,diff='Die Städte haben bildlich „Töchter“; am Ende stehen „drei Höhenzüge“, nicht „der dritte Teil Nepheths“.')
change(17,'ru',11,diff='Зависимые поселения названы «дочерьми» городов; в конце названы три возвышенности, а не «третья часть Нафефа с сёлами».')
change(17,'de',15,diff='Der Wald soll im Land des Pheresiters gerodet werden; die Vorlage verbindet das Umhauen mit den Pheresitern und Riesen. Pheresiter steht im kollektiven Singular.')
change(17,'en',18,diff='The Hebrew uses the collective singular Canaanite and describes the mountain’s limits as its “outgoings”; BSB uses plural “Canaanites” and “farthest limits”.')
change(18,'ru',28,diff='Иевусеянин назван собирательно в единственном числе; перевод имеет название «Иевус».')
change(20,'de',5,lit='Und wenn der Bluträcher ihm nachjagt, sollen sie den Totschläger nicht in seine Hand ausliefern; denn ohne Wissen hat er seinen Nächsten erschlagen, und er hat ihn nicht schon gestern und vorgestern gehasst.')
change(20,'ru',5,lit='И если мститель за кровь погонится за ним, то они не выдадут убийцу в его руку, ибо он без знания поразил своего ближнего и не ненавидел его ни вчера, ни третьего дня.')
for lang in ['de','ru']:
 for p in sorted((base/f'Tools/LiteralGen/outputs/{lang}/06_JOS').glob('JOS_021*.tsv')):
  for row in p.read_text().splitlines():
   v,lit,diff=row.split('\t')
   if diff in ['Nah am Hebräischen.','Близко к еврейскому.'] and ('Weideplätze' in lit or 'пастбищ' in lit):
    change(21,lang,int(v),diff='Die Flächen bei den Städten sind Weideplätze, nicht städtische „Vorstädte“.' if lang=='de' else 'Участки при городах названы пастбищами, а не городскими «предместьями».')
change(21,'de',9,diff='Der hebräische Text verwendet eine unbestimmte Einzahl beim Nennen der Namen; die Vorlage hat „sie ... nannten“.')
change(21,'de',26,lit='Die Gesamtzahl der Städte war zehn, dazu ihre Weideplätze, für die Sippen der übrigen Söhne Kahaths.')
change(21,'de',33,lit='Alle Städte des Gersoniters nach ihren Sippen: dreizehn Städte und ihre Weideplätze.')
change(21,'ru',40,lit='Все города сынов Мерариных по их семействам, оставшихся из семейств левитов: их жребием были двенадцать городов.')
change(22,'de',16,lit='„So sagt die ganze Gemeinde des HERRN: Was ist diese Untreue, mit der ihr dem Gott Israels untreu geworden seid, dass ihr euch heute davon abwendet, dem HERRN zu folgen, indem ihr euch einen Altar baut, um euch heute gegen den HERRN aufzulehnen?')
change(22,'de',22,lit='„Gott, der Gott, der HERR, Gott, der Gott, der HERR! Er weiß es, und Israel soll es wissen! Wenn es in Auflehnung und wenn es in Untreue gegen den HERRN geschah, rette uns an diesem Tag nicht!')
change(22,'ru',22,lit='«Бог, Бог, Господь, Бог, Бог, Господь! Он знает, и Израиль пусть знает! Если в восстании и если в неверности Господу — не спасай нас в этот день!')
change(23,'de',4,lit='Seht, ich habe euch diese übrig gebliebenen Völker als Erbteil für eure Stämme zufallen lassen, vom Jordan an, und alle Völker, die ich ausgerottet habe, bis zum großen Meer zum Sonnenuntergang hin.')
change(23,'ru',4,lit='Смотрите, я отдал вам по жребию эти оставшиеся народы в удел вашим коленам, от Иордана, и все народы, которые я истребил, до великого моря к заходу солнца.')
change(23,'de',11,lit='Und achtet sehr auf eure Seelen, dass ihr den HERRN, euren Gott, liebt.')
change(24,'de',10,lit='Und ich wollte nicht auf Bileam hören; und er segnete euch gewiss, und ich rettete euch aus seiner Hand.')
(state/'jos-c-qa.json').write_text(json.dumps(list(qa.values()),ensure_ascii=False,indent=2)+'\n')
rootqa=[]
def rootchange(ch,v,diff):
 for p in sorted((base/'Tools/LiteralGen/outputs/en/06_JOS').glob(f'JOS_{ch:03}*.tsv')):
  old=next((r for r in p.read_text().splitlines() if r.split('\t')[0]==str(v)),None)
  if old:rootqa.append({'path':str(p),'verse':v,'old_row':old,'new_row':f'{v}\t=\t{diff}'});return
rootchange(22,33,'The Hebrew names “the sons of Israel” twice and says the report was “good in their eyes”; BSB names “the Israelites” once and says they were satisfied.')
rootchange(24,13,'The Hebrew shifts to singular “you” for laboring on the land, then back to plural “you” for building and planting; BSB uses the same English pronoun throughout.')
(state/'jos-c-root-en-qa.json').write_text(json.dumps(rootqa,ensure_ascii=False,indent=2)+'\n')
cp=json.loads((state/'jos-c-checkpoint.json').read_text());cp.update(completed_chapters=list(range(17,25)),remaining_chapters=[],status='generation_complete_qa_complete',qa_path=str(state/'jos-c-qa.json'),root_en_qa_path=str(state/'jos-c-root-en-qa.json'));(state/'jos-c-checkpoint.json').write_text(json.dumps(cp,ensure_ascii=False,indent=2)+'\n')
print('QA',len(qa),'rootQA',len(rootqa))
