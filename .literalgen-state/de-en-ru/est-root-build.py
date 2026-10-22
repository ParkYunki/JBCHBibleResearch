from pathlib import Path
import json
s=Path('.literalgen-state/de-en-ru')
d={
'1':{
'1':'The Hebrew repeats the king’s name in identifying him; BSB expresses the identification as a relative clause.',
'3':'The Hebrew names the force of Persia and Media; BSB specifies military leaders.',
'5':'The Hebrew orders the ranks from great to small; BSB reverses them.',
'6':'The Hebrew lists the couches without a verb of arranging them; BSB supplies that they were arranged.',
'7':'The Hebrew describes the quantity of royal wine according to the king’s hand; BSB describes its free flow according to his bounty.',
'8':'The Hebrew says there was no compulsion in drinking; BSB says there was no limit.',
'11':'The Hebrew speaks of peoples in the plural; BSB says the people.',
'13':'The Hebrew says the king spoke to the wise men; BSB describes consultation.',
'14':'The Hebrew describes men seeing the king’s face and sitting first in the kingdom; BSB interprets this as personal access and highest rank.',
'17':'The Hebrew describes husbands as despised in the women’s eyes; BSB omits the image of eyes.',
'18':'The Hebrew leaves the content of what the noble women will say unstated; BSB supplies the same thing.',
'19':'The Hebrew says the king should give her royal position to another; BSB uses a passive clause.',
'20':'The Hebrew places great to small after the husbands; BSB reverses the order and applies it to the women.',
'21':'The Hebrew describes the matter as good in their eyes; BSB says they were pleased with the counsel.',
'22':'The Hebrew also says each man should speak the language of his people; BSB omits this final phrase.'
},
'2':{
'2':'The Hebrew describes the speakers as the king’s young men, his servants; BSB calls them attendants.',
'3':'The Hebrew calls the place the house of the women and repeats young virgin; BSB uses harem and young women.',
'4':'The Hebrew repeats the image of being good in the king’s eyes; BSB renders this as pleasing him.',
'8':'The Hebrew describes the young women as being gathered; BSB says they gathered.',
'9':'The Hebrew names her portions without describing the diet as special; BSB specifies a special diet.',
'11':'The Hebrew asks what would be done to her; BSB says what was happening to her.',
'14':'The Hebrew says she would be called by name without naming the caller; BSB makes the king the subject of summoning.',
'15':'The Hebrew calls Hegai the king’s eunuch, keeper of the women; BSB calls him the king’s trusted official in charge of the harem.',
'18':'The Hebrew names a release for the provinces without explicitly mentioning tax; BSB specifies a tax holiday.',
'21':'The Hebrew says they sought to stretch out a hand against the king; BSB interprets this as conspiring to assassinate him.',
'22':'The Hebrew says Esther spoke in Mordecai’s name; BSB says on Mordecai’s behalf.',
'23':'The Hebrew says they were hanged on wood or a tree; BSB specifies gallows.'
},
'3':{
'1':'The Hebrew says the king placed Haman’s throne above those of all the princes; BSB describes elevation to a position above them.',
'4':'The Hebrew asks whether Mordecai’s words would stand; BSB asks whether his behavior would be tolerated.',
'6':'The Hebrew says they told him Mordecai’s people and he sought to stretch out a hand against Mordecai alone; BSB omits the informants and uses hands in the plural.',
'7':'The Hebrew runs from day to day and from month to month to the twelfth month without a separate statement that the lot fell; BSB supplies that statement.',
'9':'The Hebrew promises to weigh silver into the hands of those doing the work to bring it into the king’s treasuries; BSB describes depositing it in the treasury to pay those carrying it out.',
'10':'The Hebrew names his hand; BSB specifies his finger.',
'11':'The Hebrew says the silver is given to Haman; BSB renders this as an instruction to keep his money.'
}}
(s/'est-root-diffs.json').write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
