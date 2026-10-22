from pathlib import Path
import re,json
S=Path('.literalgen-state/de-en-ru');B=Path('Tools/LiteralGen')
def write(ch,text,diffs,packet=None,start=1,langs=None):
 lines=[x.split('|') for x in text.splitlines()]; assert all(len(x)==2 for x in lines)
 q=S/'pro-c-checkpoint.json';state=json.loads(q.read_text()) if q.exists() else {'book':'20_PRO','chapters':[],'created':[],'rows':0}
 for p in sorted((B/'packets/de-en-ru/20_PRO').glob(f'PRO_{ch:03d}*.txt')):
  if packet and p.stem!=packet:continue
  blocks=p.read_text().split('==TARGET ')
  for lang,i in [('de',0),('ru',1),('en',None)]:
   if langs and lang not in langs:continue
   block=next(x for x in blocks[1:] if x.startswith('lang='+lang+' '));vs=[int(v) for v in re.findall(r'^#(\d+) ',block,re.M)]
   out=B/'outputs'/lang/'20_PRO'/(p.stem+'.tsv');out.parent.mkdir(parents=True,exist_ok=True)
   rows=[]
   for v in vs:
    literal='=' if lang=='en' else lines[v-start][i];diff=diffs.get(lang,{}).get(v,{'de':'Nah am Hebräischen.','ru':'Близко к еврейскому.','en':'Close to the Hebrew.'}[lang]);assert len(diff.split())<=60
    rows.append(f'{v}\t{literal}\t{diff}')
   with out.open('x') as f:f.write('\n'.join(rows)+'\n')
   state['created'].append(str(out.resolve()));state['rows']+=len(rows)
 state.setdefault('packet_units',[]).append(packet or f'PRO_{ch:03d}');state['chapters'].append(ch);state['status']='in_progress';q.write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n')
 if not (S/'pro-c-qa.json').exists():(S/'pro-c-qa.json').write_text('[]\n')
 print(ch,len(lines),'verses',len(state['created']),'total files')
