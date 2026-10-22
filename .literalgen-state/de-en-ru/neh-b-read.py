from pathlib import Path
import sys,re
ch=int(sys.argv[1]);lo=int(sys.argv[2]) if len(sys.argv)>2 else 1;hi=int(sys.argv[3]) if len(sys.argv)>3 else 999
for p in sorted(Path('Tools/LiteralGen/packets/de-en-ru/16_NEH').glob(f'NEH_{ch:03d}*.txt')):
 b=p.read_text().split('==TARGET ');o=dict(re.findall(r'^#(\d+)\nO (.*)$',b[0],re.M));ts={l:dict(re.findall(r'^#(\d+) (.*)$',next(x for x in b[1:] if x.startswith('lang='+l+' ')),re.M)) for l in ['de','ru','en']}
 for v in o:
  if not lo<=int(v)<=hi:continue
  clean=re.sub(r'[\u0590-\u05ff]+=[^\u0590-\u05ff]*?\[LXX\]', '', o[v]);print('#'+v+' O '+' '.join(re.findall(r'[\u0590-\u05ff]+',clean)))
  for l,t in ts.items():print(l+' '+t[v])
