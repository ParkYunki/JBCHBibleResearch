from pathlib import Path
import re,json,sys
book=sys.argv[1];r=Path('Tools/LiteralGen');s=Path('.literalgen-state/de-en-ru');p=s/'checkpoint.json';d=json.loads(p.read_text());ps=sorted((r/'packets/de-en-ru'/book).glob('*.txt'));assert ps
chapters={}
for f in ps:
 common=f.read_text().split('==TARGET ')[0]
 m=re.search(r'^@\w+ (\d+)',common);assert m,f
 chapters[m.group(1)]=chapters.get(m.group(1),0)+len(re.findall(r'^#\d+\nO ',common,re.M))
assert not any(x['book']==book for x in d['books']),book
d['books'].append(dict(book=book,packets=len(ps),verses_per_lang=sum(chapters.values()),chapters=chapters,status='pending',missing=[]))
d.update(status='active',current_book=book,phase='Continuing missing books in order')
p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n');print(book,len(ps),'packets',sum(chapters.values()),'verses per language')
