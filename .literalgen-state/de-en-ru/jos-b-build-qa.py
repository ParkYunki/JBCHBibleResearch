from pathlib import Path
import json,re
base=Path('Tools/LiteralGen/outputs');qa={}
def put(lang,ch,v,lit=None,diff=None):
 ps=[p for p in (base/lang/'06_JOS').glob(f'JOS_{ch:03d}*.tsv') if any(r.split('\t')[0]==str(v) for r in p.read_text().splitlines())];assert len(ps)==1
 p=ps[0];old=next(r for r in p.read_text().splitlines() if r.split('\t')[0]==str(v));key=(str(p),v)
 cur=qa.get(key,{}).get('new_row',old).split('\t')
 if lit is not None:cur[1]=lit
 if diff is not None:cur[2]=diff
 new='\t'.join(cur)
 if new!=old:qa[key]={'path':str(p),'verse':v,'old_row':old,'new_row':new}
put('ru',10,6,lit='И послали мужчины Гаваона к Иисусу в стан, в Галгал, сказать: «Не отводи своих рук от своих рабов; поднимись к нам скорее и спаси нас и помоги нам, ибо собрались против нас все цари аморреянина, живущие в горах».')
put('ru',10,7,lit='И поднялся Иисус из Галгала, он и весь военный народ с ним и все могучие воины.')
put('ru',10,17,lit='И Иисусу было сообщено: «Найдены пять царей, скрывающихся в пещере в Македе».')
for v in [22,23]:
 p=Path(f'Tools/LiteralGen/outputs/ru/06_JOS/JOS_010_1.tsv');r=next(r for r in p.read_text().splitlines() if r.split('\t')[0]==str(v)).split('\t');put('ru',10,v,lit=r[1].replace('этих пять царей','этих пятерых царей'))
put('ru',10,26,diff='Заключительная фраза сохраняет страдательную форму: «были повешены».')
put('de',10,33,lit='Damals zog Horam, der König von Geser, hinauf, um Lachis zu helfen; und Josua schlug ihn und sein Volk, ohne ihm einen Überlebenden übrig zu lassen.',diff='Nah am Hebräischen.')
put('ru',10,33,lit='Тогда поднялся Горам, царь Газера, помочь Лахису; и поразил его Иисус и его народ, не оставив ему ни одного уцелевшего.')
put('de',11,8,lit='Und der HERR gab sie in die Hand Israels; und sie schlugen sie und verfolgten sie bis Groß-Sidon und bis Misrephoth-Majim und bis in die Ebene von Mizpa im Osten; und sie schlugen sie, ohne ihnen einen Überlebenden übrig zu lassen.',diff='Die Hand steht in der Einzahl. Der Text nennt den Ort Misrephoth-Majim; die Zielübersetzung gibt ihn als „die warmen Wasser“ wieder.')
put('en',11,8,diff='Close to the Hebrew.')
put('ru',11,8,lit='И отдал их Господь в руку Израиля, и поразили их и преследовали их до Сидона великого и до Мисрефоф-Маима и до долины Мицфы к востоку; и поразили их, не оставив им ни одного уцелевшего.',diff='Рука названа в единственном числе; Израиль назван собирательно. Избежавшие отдельно не добавлены.')
put('ru',11,7,lit='И пришёл Иисус и весь военный народ с ним внезапно на них при водах Мерома, и напали на них.')
put('ru',11,13,lit='Только все города, стоящие на своём холме, Израиль не сжёг, кроме одного Асора, который сжёг Иисус.',diff='Израиль назван собирательно; о городах сказано, что они стоят на своём холме.')
put('ru',11,15,diff='Близко к еврейскому.')
put('de',12,6,diff='Das Land wird als Besitz gegeben; die Zielübersetzung sagt „einzunehmen“. Der Rubeniter und der Gaditer stehen im kollektiven Singular.')
put('ru',12,22,lit='царь Кедеса — один; царь Иокнеама при Кармиле — один;')
put('de',13,15,lit='Und Mose gab dem Stamm der Söhne Rubens nach ihren Sippen ein Erbe.')
put('ru',13,15,lit='И Моисей дал наследие колену сынов Рувима по их семействам.')
put('de',13,16,lit='Und ihr Gebiet reichte von Aroer, das am Ufer des Baches Arnon liegt, und umfasste die Stadt, die mitten im Bach liegt, und die ganze Ebene bei Medeba:')
put('ru',13,16,lit='И их область была от Ароера, который на берегу потока Арнона, и включала город, который посреди потока, и всю равнину при Медеве:')
put('de',13,24,lit='Und Mose gab dem Stamm Gad, den Söhnen Gads, nach ihren Sippen ein Erbe.')
put('ru',13,24,lit='И Моисей дал наследие колену Гада, сынам Гада, по их семействам.')
put('de',13,29,lit='Und Mose gab dem halben Stamm Manasse ein Erbe; und es gehörte dem halben Stamm der Söhne Manasses nach ihren Sippen.')
put('ru',13,29,lit='И Моисей дал наследие половине колена Манассиина; и принадлежало оно половине колена сынов Манассии по их семействам.')
put('ru',14,1,lit='И вот что унаследовали сыны Израиля в земле Ханаанской, что дали им в наследие Елеазар, священник, и Иисус, сын Навин, и главы отцовских домов колен сынов Израиля.')
put('de',15,13,lit='Und Kaleb, dem Sohn Jephunnes, gab er einen Anteil mitten unter den Söhnen Judas, nach dem Mund des HERRN an Josua: Kirjath-Arba (Arba war der Vater Enaks), das ist Hebron.')
put('ru',15,13,lit='И Халеву, сыну Иефоннии, он дал долю среди сынов Иуды, по устам Господа к Иисусу: Кириаф-Арбы (Арба — отец Енака), это Хеврон.')
put('de',16,10,lit='Und sie vertrieben den Kanaaniter, der in Geser wohnte, nicht; und der Kanaaniter wohnte mitten in Ephraim bis auf diesen Tag und wurde zum Fronarbeiter.')
put('ru',16,10,lit='И они не изгнали Хананея, жившего в Газере; и Хананей жил среди Ефрема до этого дня и стал подневольным работником.')
# Native-language names for the comparison translation.
for l in ['de','ru']:
 for p in sorted((base/l/'06_JOS').glob('JOS_*.tsv')):
  ch=int(p.stem.split('_')[1])
  if not 10<=ch<=16:continue
  for row in p.read_text().splitlines():
   v=int(row.split('\t')[0]);cur=qa.get((str(p),v),{}).get('new_row',row).split('\t');d=cur[2]
   if 'TARGET' not in d:continue
   if l=='de':
    d=d.replace('in TARGET','in der Zielübersetzung').replace('TARGET','die Zielübersetzung')
    if d.startswith('die Zielübersetzung'):d='Die'+d[3:]
   else:
    d=d.replace('в TARGET','в переводе').replace('TARGET','перевод')
    if d.startswith('перевод'):d='Перевод'+d[7:]
   put(l,ch,v,diff=d)
rows=list(qa.values())
Path('.literalgen-state/de-en-ru/jos-b-qa.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
print('QA entries',len(rows))
