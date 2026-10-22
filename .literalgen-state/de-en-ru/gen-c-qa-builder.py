import pathlib,json,re
B=pathlib.Path('/Users/arkuni/Developer/JBCHBibleResearch/Tools/LiteralGen');S=B.parent.parent/'.literalgen-state/de-en-ru';qpath=S/'gen-c-qa.json';qa={}
def fix(lang,stem,v,oldpart=None,newpart=None,lit=None,note=None,reason=''):
 p=B/'outputs'/lang/'01_GEN'/(stem+'.tsv');old=next(r for r in p.read_text().splitlines() if r.startswith(str(v)+'\t'));key=(str(p),v);a=qa.get(key,{'new_row':old})['new_row'].split('\t')
 if lit is not None:a[1]=lit
 if note is not None:a[2]=note
 new='\t'.join(a)
 if oldpart is not None:
  assert oldpart in new,(lang,stem,v,oldpart);new=new.replace(oldpart,newpart)
 if new!=old:qa[key]={'path':str(p),'verse':v,'old_row':old,'new_row':new,'reason':(qa[key]['reason']+' '+reason if key in qa else reason)}
# Restore corrections lost from temporary state.
for lang,cl in [('de','Nah am Hebräischen.'),('en','Close to the Hebrew.'),('ru','Близко к еврейскому.')]:
 p=B/'outputs'/lang/'01_GEN/GEN_035.tsv'
 for r in p.read_text().splitlines():
  v,l,n=r.split('\t')
  if n.strip()=='-':fix(lang,'GEN_035',int(v),note=cl,reason='Expand a leftover temporary close marker to the required localized sentence.')
for lang,v,o,n in [('ru',23,'и чему он делал, Господь давал успех.','и во всем, что он делал, Господь давал успех.'),('ru',19,'По этим вещам поступил со мной твой раб','Так поступил со мной твой раб'),('de',19,'Nach diesen Dingen hat dein Knecht mir getan','Solches hat dein Knecht mir getan')]:fix(lang,'GEN_039',v,o,n,reason='Use grammatical native syntax for the relative or manner expression.')
for lang,cl in [('de','“'),('ru','»')]:
 p=B/'outputs'/lang/'01_GEN/GEN_041_1.tsv';l=next(r.split('\t')[1] for r in p.read_text().splitlines() if r.startswith('24\t'))
 if not l.endswith(cl):fix(lang,'GEN_041_1',24,lit=l+cl,reason='Close Pharaoh’s dream report before Joseph begins his reply.')
for lang,v,o,n in [('ru',16,'заколи жертву','заколи животное'),('de',34,'war fünf Anteile größer als die Portionen von ihnen allen','war fünfmal so groß wie die Portionen von ihnen allen'),('ru',34,'была на пять долей больше долей всех их','была впятеро больше долей всех их')]:fix(lang,'GEN_043_1' if v<=30 else 'GEN_043_2',v,o,n,reason='Ordinary slaughter does not imply a sacrifice.' if v==16 else 'Express the fivefold ratio rather than an additive difference of five portions.')
# Corrections identified while creating remaining chapters.
fix('de','GEN_048',2,note='Bewahrt das bereits vollendete Kommen.',reason='Replace an unidiomatic German difference sentence.')
fix('ru','GEN_049_1',10,'из-под его ног','из пространства между его ногами',reason='מִבֵּין means from between, not from underneath.')
fix('de','GEN_049_1',20,note='Nah am Hebräischen.',reason='The output does not express a singular king, so its existing difference claim is unsupported.')
fix('ru','GEN_049_1',26,'до желанного вечных холмов','до желанных благ вечных холмов',reason='Supply the minimal noun required for natural Russian nominal syntax.')
fix('ru','GEN_049_1',24,'Могучего Иакова','Могучего Иаковлева',reason='Keep the divine title as the Mighty One belonging to Jacob, rather than potentially describing Jacob himself.')
fix('ru','GEN_049_1',29,'Я собираюсь к моим народам','Я буду собран к моему народу',note='Близко к еврейскому.',reason='Preserve passive gathering and the singular people in עַמִּי; remove the false plural difference claim.')
fix('de','GEN_049_1',29,'zu meinen Völkern','zu meinem Volk',note='Nah am Hebräischen.',reason='The actual עַמִּי is singular my people, unlike the plural in verse 33.')
fix('de','GEN_049_1',10,'noch der Herrscherstab zwischen seinen Füßen','noch der Herrscherstab aus dem Raum zwischen seinen Füßen',reason='Retain both from and between in מִבֵּין using the minimal German complement.')
# Final native grammar and speech-boundary review.
p=B/'outputs/de/01_GEN/GEN_047_1.tsv'
l=next(r.split('\t')[1] for r in p.read_text().splitlines() if r.startswith('19\t'))
fix('de','GEN_047_1',19,lit=l+'“',reason='Close the Egyptian petition beginning in verse 18 before the narrative resumes.')
fix('de','GEN_046_1',25,'alle Seelen sieben','alle Seelen waren sieben',reason='Supply the copula required by German numeral syntax.')
fix('de','GEN_046_1',30,'nachdem ich dein Angesicht gesehen habe, dass du noch lebst','nachdem ich dein Angesicht gesehen habe, denn du lebst noch',reason='Render the final causal clause with native German syntax.')
fix('ru','GEN_046_1',30,'после того как я увидел твое лицо, что ты еще жив','после того как я увидел твое лицо, ибо ты еще жив',reason='Render the final causal clause with native Russian syntax.')
fix('ru','GEN_040',10,'ее гроздья созрели ягодами','ее виноградные гроздья созрели',reason='Replace an ungrammatical instrumental with a native expression retaining the ripe grape clusters.')
fix('ru','GEN_042_1',21,'которого страдание души мы видели','страдание души которого мы видели',reason='Use native order for the genitive relative pronoun.')
fix('ru','GEN_042_1',25,'и возвратить их серебро','и велел возвратить их серебро',reason='Supply the governing verb for the dangling infinitives while retaining the separate filling action.')
fix('de','GEN_044_1',30,', und seine Seele ist an dessen Seele gebunden,',' — seine Seele ist an dessen Seele gebunden —,',reason='Separate the parenthetical statement from the conditional clause so German verb order is grammatical.')
fix('de','GEN_035',11,'ein Volk und eine Versammlung von Völkern wird aus dir sein','ein Volk und eine Versammlung von Völkern werden aus dir sein',reason='Use plural agreement required by coordinated German subjects.')
fix('ru','GEN_035',11,'народ и собрание народов будет от тебя','народ и собрание народов будут от тебя',reason='Use plural agreement for the coordinated Russian subjects.')
fix('de','GEN_044_2',31,'dann wird es geschehen, wenn er sieht','dann wird es geschehen: Wenn er sieht',reason='Use a colon before the following independent conditional construction.')
fix('ru','GEN_044_2',31,'то будет, когда он увидит','то будет так: когда он увидит',reason='Supply the minimal correlate to introduce the following conditional statement in native Russian.')
# Remove duplicated sentence punctuation around quoted difference snippets.
for p in sorted((B/'outputs/en/01_GEN').glob('GEN_0*.tsv')):
 c=int(p.stem[4:7])
 if 35<=c<=50:
  for r in p.read_text().splitlines():
   v,l,n=r.split('\t')
   if '.”.' in n:fix('en',p.stem,int(v),note=n.replace('.”.','”.'),reason='Remove duplicate full stops around a quoted snippet.')
# Save unique original-row proposals, never touch outputs.
def save():
 qpath.write_text(json.dumps(list(qa.values()),ensure_ascii=False,indent=2));print('QA',len(qa))
save()
