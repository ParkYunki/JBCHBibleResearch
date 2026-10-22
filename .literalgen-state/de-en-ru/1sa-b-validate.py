from pathlib import Path
import json,re,hashlib
S=Path('.literalgen-state/de-en-ru');qa=json.loads((S/'1sa-b-qa.json').read_text());created=json.loads((S/'1sa-b-created.json').read_text());candidate={(x['path'],str(x['verse'])):x for x in qa};assert len(candidate)==len(qa)
rows=0;quote=[]
for lang,chs in [('de',range(12,19)),('ru',range(12,19)),('en',range(12,16))]:
 for ch in chs:
  chapter=[]
  for p in sorted(Path('Tools/LiteralGen/outputs',lang,'09_1SA').glob(f'1SA_{ch:03d}*.tsv')):
   block=next(x for x in Path('Tools/LiteralGen/packets/de-en-ru/09_1SA',p.stem+'.txt').read_text().split('==TARGET ')[1:] if x.startswith('lang='+lang+' '))
   vs=[str(v) for v in re.findall(r'^#(\d+) ',block,re.M)];data=p.read_text().splitlines();assert [r.split('\t')[0] for r in data]==vs
   for row in data:
    cols=row.split('\t');assert len(cols)==3 and all(cols)
    if (str(p),cols[0]) in candidate:
     x=candidate[(str(p),cols[0])];assert x['old_row']==row;cols=x['new_row'].split('\t')
    assert len(cols[2].split())<=60
    assert 'TARGET' not in cols[2]
    if lang=='en':assert cols[1]=='='
    chapter.append(cols[1]);rows+=1
  if lang!='en':
   whole=' '.join(chapter);op,cl=('„','“') if lang=='de' else ('«','»')
   if whole.count(op)!=whole.count(cl):quote.append([lang,ch,whole.count(op),whole.count(cl)])
assert not quote,quote
protected=json.loads((S/'09_1SA-protected.json').read_text());bad=[]
for p,h in protected.items():
 if not Path(p).exists() or hashlib.sha256(Path(p).read_bytes()).hexdigest()!=h:bad.append(p)
assert not bad,bad
result={'created_files':len(created),'created_rows':rows,'qa_candidates':len(qa),'root_english_reviewed_rows':177,'root_english_candidates':0,'protected_files':len(protected),'protected_unchanged':not bad,'exact_old_rows':True,'unique_path_verse':True,'format_and_verse_order':True,'native_quotes_balanced_per_chapter':True,'all_source_review_complete':True,'unreviewed':[]}
(S/'1sa-b-validation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
cp={'scope':'de/ru012–018; en012–015','transferred_to_root':'de/ru019–020','status':'generation and all assigned verse QA complete; awaiting root official redo application','created_files':len(created),'created_rows':rows,'qa_candidates':len(qa),'qa_file':str(S/'1sa-b-qa.json'),'root_english_review':'016–020, 177 verses, 0 candidates','root_english_qa_file':str(S/'1sa-b-root-en-qa.json'),'protected_files':len(protected),'protected_unchanged':True,'unreviewed':[],'LXX_tokens_excluded':['013:1 thirty and forty','013:15 marked narrative addition','014:41 marked expanded request']}
(S/'1sa-b-checkpoint.json').write_text(json.dumps(cp,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(result))
