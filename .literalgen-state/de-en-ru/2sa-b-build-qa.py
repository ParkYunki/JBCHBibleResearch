from pathlib import Path
import json
S=Path('.literalgen-state/de-en-ru');qa=[];root=[]
def put(lang,ch,v,lit=None,diff=None,repl=None,reason='Native wording or definite source contrast',dest=qa):
 found=[]
 for p in Path('Tools/LiteralGen/outputs',lang,'10_2SA').glob(f'2SA_{ch:03d}*.tsv'):
  for r in p.read_text().splitlines():
   if r.split('\t')[0]==str(v):found.append((p,r))
 assert len(found)==1,(lang,ch,v)
 p,old=found[0];a=old.split('\t')
 if lit is not None:a[1]=lit
 if diff is not None:a[2]=diff
 if repl:
  for x,y in repl:
   assert x in a[1],(lang,ch,v,x)
   a[1]=a[1].replace(x,y)
 new='\t'.join(a);assert new!=old
 dest.append({'path':str(p),'verse':v,'old_row':old,'new_row':new,'reason':reason})
put('ru',12,16,repl=[('ради юноши','ради мальчика')],reason='Use the contextual child sense of נער without imposing adolescent age.')
put('de',13,8,repl=[('kochte die Kuchen','garte die Kuchen')],reason='Use a native general cooking verb rather than implying boiling cakes.')
put('ru',13,8,repl=[('приготовила лепёшки перед его глазами, и сварила лепёшки','сделала лепёшки перед его глазами, и приготовила лепёшки')],reason='Use general cooking language without imposing boiling as the method.')
put('de',14,7,repl=[('meine Glut auslöschen, die übrig geblieben ist','mein Glutstück auslöschen, das übrig geblieben ist')],diff='Das Bild ist ein verbleibendes Glutstück, nicht nur ein Funke; das Töten benennt keine besondere Weise des Würgens.',reason='Preserve the singular ember rather than only a mass noun for heat.')
put('ru',14,26,repl=[('через промежутки дней','по истечении дней')],reason='Use native wording for the interval ending.')
put('de',15,20,repl=[('Kehhre zurück','Kehre zurück')],reason='Spelling correction.')
put('en',13,6,diff='Close to the Hebrew.',dest=root,reason='Two cakes and a couple of cakes are equivalent wording here.')
put('en',15,8,diff='The Hebrew repeats the vow and vowing root and does not name Hebron in the quoted promise; BSB adds “in Hebron.”',dest=root,reason='Exclude the explicitly LXX-marked final token; describe only definite wording.')
put('en',15,31,diff='The Hebrew has an active reporting form with David named, followed by David saying his prayer; BSB makes someone tell David. The Hebrew uses an ordinary saying verb for the prayer.',dest=root,reason='Compare the actual active O form without conjectural source explanation.')
put('en',16,12,diff='The Hebrew names “my eye” and repeats the LORD’s name; BSB has “my affliction” and leaves the second LORD implicit.',dest=root,reason='Compare actual O eye wording without manuscript explanation.')
put('en',16,20,diff='The Hebrew command is plural and explicitly says “for yourselves”; BSB says “Give me counsel.”',dest=root,reason='Preserve explicit addressee number and pronominal complement.')
put('de',16,13,repl=[('warf Staub mit Staub','bestäubte ihn mit Staub')],dest=root,reason='Native German verb and retained dust image, as flagged by root.')
put('de',16,18,repl=[('wem der HERR','wen der HERR')],dest=root,reason='Accusative object of erwählen, as flagged by root.')
for name,a in [('2sa-b-qa.json',qa),('2sa-b-root-en-qa.json',root)]:
 assert len({(x['path'],x['verse']) for x in a})==len(a)
 for x in a:
  c=x['new_row'].split('\t');assert len(c)==3 and len(c[2].split())<=60
 (S/name).write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n')
print({'own':len(qa),'root':len(root)})
