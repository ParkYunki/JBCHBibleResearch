from pathlib import Path
import json
qa=[]
def fix(lang,stem,v,literal=None,diff=None):
 p=Path('Tools/LiteralGen/outputs')/lang/'05_DEU'/f'{stem}.tsv';old=next(x for x in p.read_text().splitlines() if x.split('\t')[0]==str(v));f=old.split('\t')
 if literal is not None:f[1]=literal
 if diff is not None:f[2]=diff
 new='\t'.join(f)
 assert new!=old
 qa.append({'path':str(p),'verse':v,'old_row':old,'new_row':new})
fix('ru','DEU_002_1',16,'И было, когда из среды народа вымерли все мужи войны,')
fix('ru','DEU_003',24,'«Владыко Господи, Ты начал показывать Твоему рабу Твоё величие и Твою крепкую руку; ибо какой бог на небе и на земле может делать подобное Твоим делам и Твоим могущественным деяниям?')
fix('ru','DEU_004_1',25,'Когда ты произведёшь сыновей и сыновей сыновей, и вы состаритесь в земле, и поступите развратно, и сделаете изваяние, образ чего-либо, и сделаете зло в глазах Господа, Бога твоего, чтобы прогневать Его,')
fix('de','DEU_007',10,'und denen, die ihn hassen, ins Angesicht vergilt, um jeden von ihnen umkommen zu lassen. Er zögert nicht gegenüber dem, der ihn hasst; ins Angesicht vergilt er ihm.')
fix('ru','DEU_007',10,'и воздающий ненавидящим Его, каждому в лицо, чтобы погубить его; Он не медлит с ненавидящим Его, в лицо ему воздаст ему.')
fix('de','DEU_008',12,'damit nicht, wenn du isst und satt wirst und gute Häuser baust und darin wohnst,')
fix('de','DEU_008',14,'dein Herz sich erhebt und du den HERRN, deinen Gott, vergisst, der dich aus dem Land Ägypten herausführt, aus dem Haus der Sklaven,')
fix('ru','DEU_008',12,'чтобы, когда ты поешь и насытишься, и построишь хорошие дома, и поселишься в них,')
fix('ru','DEU_008',13,'и твой крупный и мелкий скот умножится, и серебро и золото умножатся у тебя, и всё, что у тебя, умножится,')
fix('ru','DEU_008',14,'твоё сердце не вознеслось, и ты не забыл Господа, Бога твоего, выводящего тебя из земли Египетской, из дома рабов,')
fix('ru','DEU_009',10,'И Господь дал мне две каменные скрижали, написанные пальцем Бога, и написанное на них соответствовало всем словам, которые Господь говорил вам на горе из среды огня в день собрания.')
fix('ru','DEU_009',26,'И я молился Господу и сказал: «Владыко Господи, не истребляй Твой народ и Твоё наследие, которое Ты выкупил Твоим величием, которое Ты вывел из Египта крепкой рукой.')
fix('de','DEU_011_1',16,'Hütet euch davor, dass euer Herz sich verführen lässt und ihr abweicht und anderen Göttern dient und euch vor ihnen niederwerft;')
fix('ru','DEU_011_1',16,'Берегитесь, чтобы ваше сердце не было обольщено, и вы не свернули, и не стали служить другим богам, и не поклонились им;')
fix('ru','DEU_011_1',17,'И воспылает гнев Господа против вас, и Он заключит небеса, и не будет дождя, и земля не даст своего урожая, и вы быстро погибнете с доброй земли, которую Господь даёт вам.')
fix('ru','DEU_011_1',19,'И учите ваших сыновей этим словам, чтобы говорить о них, когда ты сидишь в твоём доме, и когда идёшь по дороге, и когда ложишься, и когда встаёшь.')
Path('.literalgen-state/de-en-ru/deu-a-qa.json').write_text(json.dumps(qa,ensure_ascii=False,indent=2)+'\n')
Path('.literalgen-state/de-en-ru/deu-a-root-en-qa.json').write_text('[]\n')
p=Path('.literalgen-state/de-en-ru/deu-a-checkpoint.json');cp=json.loads(p.read_text());cp.update({'phase':'complete_with_qa','owned_range':'de/ru001–011; en001–004','qa_rows':len(qa),'qa_file':'.literalgen-state/de-en-ru/deu-a-qa.json','root_en005_011_review':'complete; no confirmed errors','root_en_review_rows':187});p.write_text(json.dumps(cp,ensure_ascii=False,indent=2)+'\n')
print('QA',len(qa),'rows; no output changes')
