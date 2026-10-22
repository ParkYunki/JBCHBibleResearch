from pathlib import Path
import re,sys
for c in map(int,sys.argv[1:]):
 for p in sorted(Path('Tools/LiteralGen/packets/de-en-ru/20_PRO').glob(f'PRO_{c:03}*.txt')):
  b=p.read_text().split('==TARGET ')
  targets={}
  for t in b[1:]:
   lang=re.match(r'lang=(\w+)',t)[1]
   targets[lang]=dict(re.findall(r'^#(\d+) (.*)$',t,re.M))
  print(p.name)
  for v,o in re.findall(r'^#(\d+)\nO (.*)$',b[0],re.M):
   print(v+' O '+(o if '[LXX]' in o else ' '.join(re.findall(r'[\u0590-\u05ff]+',o))))
   for lang in ['de','en','ru']:print(lang+' '+targets[lang][v])
