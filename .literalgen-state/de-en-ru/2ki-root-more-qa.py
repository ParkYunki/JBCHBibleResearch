from pathlib import Path
import json
s=Path('.literalgen-state/de-en-ru');p=s/'2ki-root-native-qa.json';q=json.loads(p.read_text())
def add(lang,file,v,change=None,literal=None,diff=None):
 path=Path('Tools/LiteralGen/outputs')/lang/'12_2KI'/file;old=next(r for r in path.read_text().splitlines() if r.split('\t')[0]==str(v));a=old.split('\t')
 if change:
  assert change[0] in a[1];a[1]=a[1].replace(*change)
 if literal:a[1]=literal
 if diff:a[2]=diff
 assert len(a[2].split())<=60
 q.append({'path':str(path),'old_row':old,'new_row':'\t'.join(a)})
add('de','2KI_003.tsv',3,change=('der Israel sündigen gemacht hatte','der Israel zum Sündigen gebracht hatte'))
add('ru','2KI_004_2.tsv',40,change=('они налили мужчинам есть','они налили мужчинам похлёбки для еды'))
add('de','2KI_002.tsv',21,change=('von dort wird nicht mehr Tod und Fehlgeburt kommen','von dort werden nicht mehr Tod und Fehlgeburt kommen'))
for v in [16,17]:
 add('de','2KI_004_1.tsv',v,change=('wenn die Zeit wieder auflebt' if v==16 else 'wenn die Zeit wieder auflebte','wenn diese Zeit wiederkehrt' if v==16 else 'als diese Zeit wiederkehrte'),diff='Die hebräische Zeitangabe wird ohne ein ausdrücklich genanntes Jahr wiedergegeben; Luther nennt das Jahr.')
 add('ru','2KI_004_1.tsv',v,change=('когда оживёт время' if v==16 else 'когда ожило время','когда это время вновь наступит' if v==16 else 'когда это время вновь наступило'),diff='Еврейское указание времени передано без отдельного слова «год»; Синодальный перевод прямо называет год.')
p.write_text(json.dumps(q,ensure_ascii=False,indent=2)+'\n');print(len(q),'QA candidates')
