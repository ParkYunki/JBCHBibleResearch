from pathlib import Path
import json
out=[]
def add(ch,v,diff):
 rows=[(str(p),r) for p in Path('Tools/LiteralGen/outputs/en/12_2KI').glob(f'2KI_{ch:03d}*.tsv') for r in p.read_text().splitlines() if r.split('\t')[0]==str(v)]
 assert len(rows)==1
 p,old=rows[0];a=old.split('\t');a[2]=diff
 out.append({'path':p,'verse':v,'old_row':old,'new_row':'\t'.join(a)})
add(13,23,'The Hebrew says He was unwilling to destroy them and separately states He had not cast them from His face. BSB places both destroying and casting under His unwillingness.')
add(14,26,'The Hebrew explicitly says there was no one in each of the two groups; BSB describes both groups as afflicted.')
add(15,4,'The Hebrew repeats the high places as the location of sacrifice and burning incense; BSB uses there.')
add(15,14,'The Hebrew separately states going up and coming and repeats Samaria as the place of the attack; BSB condenses the movement and names Samaria once.')
add(16,9,'The Hebrew repeats the king of Assyria and makes Damascus itself the object of deportation; BSB uses he and explicitly supplies its people.')
add(16,11,'The Hebrew repeats Uriah the priest and Damascus; BSB uses he for the second Uriah reference and leaves the return location implicit.')
add(16,12,'The Hebrew names the king three times and the altar twice; BSB uses pronouns after their first mention.')
add(16,18,'The Hebrew uses one verb for both the Sabbath structure and the outer royal entrance; BSB uses separate removing and closing verbs.')
Path('.literalgen-state/de-en-ru/2ki-b-root-en-qa.json').write_text(json.dumps(out,ensure_ascii=False,indent=2))
print(len(out))
