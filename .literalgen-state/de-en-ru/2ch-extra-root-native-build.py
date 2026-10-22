from pathlib import Path
import json
out=[]
def add(l,ch,v,lit=None,diff=None,rep=None):
 p=next((Path('Tools/LiteralGen/outputs')/l/'14_2CH').glob(f'*_{ch:03d}*.tsv'));old=next(r for r in p.read_text().splitlines() if r.startswith(str(v)+'\t'));f=old.split('\t')
 if rep:lit=f[1].replace(*rep);assert lit!=f[1]
 new='\t'.join([f[0],lit if lit is not None else f[1],diff if diff is not None else f[2]]);assert new!=old and len(new.split('\t'))==3 and len(new.split('\t')[2].split())<=60
 out.append({'path':str(p),'old_row':old,'new_row':new})
add('de',23,18,rep=('durch die Hand Davids','durch die Hände Davids'),diff='Das Hebräische sagt „durch die Hände Davids“, ohne ausdrücklich zu sagen, dass David die Lieder dichtete, wie Luther es formuliert.')
add('ru',23,18,rep=('через руку Давида','через руки Давида'),diff='В еврейской формулировке нет отдельного сообщения о восстановлении дневных черед, присутствующего в Синодальном переводе. Она сохраняет образ рук Давида.')
add('ru',24,9,lit='И провели они возглашение в Иуде и в Иерусалиме, чтобы приносили Господу подать Моисея, раба Бога, возложенную на Израиль в пустыне.')
add('de',24,14,rep=('und sie machten daraus Geräte','und er machte daraus Geräte'),diff='Das Machen der Geräte hat im Hebräischen ein einzelnes Subjekt. Das Hebräische sagt „im Haus“, Luther „bei dem Hause“, und nennt Jojadas Tage ausdrücklich.')
add('ru',24,14,rep=('и сделали из него сосуды','и сделал он из него сосуды'),diff='Изготовление сосудов имеет подлежащее в единственном числе; Синодальный перевод передает его множественным.')
add('de',36,7,lit='Und einige von den Geräten des Hauses des HERRN brachte Nebukadnezar nach Babel und legte sie in seinen Palast in Babel.')
add('ru',36,7,lit='И некоторые из сосудов дома Господа принес Навуходоносор в Вавилон и поместил их в своем дворце в Вавилоне.')
add('ru',36,13,lit='И он восстал также против царя Навуходоносора, который заставил его поклясться Богом. И сделал он жесткой свою шею и укрепил свое сердце, чтобы не возвращаться к Господу, Богу Израиля.')
add('ru',36,16,rep=('пока не стало исцеления','пока больше не осталось исцеления'))
p=Path('.literalgen-state/de-en-ru/2ch-extra-root-native-qa.json');p.write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n');print(len(out),p)
