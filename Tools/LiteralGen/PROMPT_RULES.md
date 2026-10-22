# Literal translation + translation-difference generator (rules)

You write two fields for every Bible verse in a PACKET, for each TARGET language block.
Work only from the PACKET. Do not use outside Bible texts. Do not explain your work. Output data only.

## PACKET format
- `@BOOK CH | verses=a-b` header.
- `==COMMON`: for each verse `#n`, then
  - `O` = original-language words in order, each `word=contextual English gloss`.
    Flags: `[TR]` word only in the Textus Receptus (not in NA27/28); `[NA]` word in NA27/28 but not in the Textus Receptus;
    `[Byz]` word in neither (other manuscripts only; ignore it);
    `[LXX]` Septuagint addition not in the Hebrew text; `(title)`…`(text)` = Psalm superscription, then the verse body.
  - `E` = Literal Standard Version (English literal). Reference only.
- `==TARGET lang=xx bible=CODE (name)`: `#n <target Bible text>`; `(none)` = the target Bible has no text at this verse number.

## Field 1: LITERAL (in the TARGET language)
- Translate the ORIGINAL (O line) literally. Base text: NT = NA28 (ignore `[TR]` and `[Byz]` words, include `[NA]` words); OT = Hebrew (ignore `[LXX]` words).
- Keep original word order where the target grammar allows; keep tense, voice, person, number, articles, conjunctions ("and", "for", "but").
- Render idioms word for word (e.g. σπλάγχνα = "inner parts/bowels", not "heart").
- Psalm titles: put the title first, then the verse body, in one line (as in the O line).
- Proper names: use the spelling of the TARGET Bible.
- Add as few words as possible. No paraphrase, no interpretation, no brackets, no notes.
- lang=en: write only `=` (the app uses LSV for English).
- If EVERY word of a verse is `[TR]` (the verse is absent from NA28, e.g. Matt 17:21), translate the TR words literally anyway (the field must not be empty).

## Field 2: DIFFERENCE (in the TARGET language)
- Explain how the TARGET Bible text differs from the original. 1–3 sentences, at most ~60 words (CJK/Thai: ~120 characters).
- Mention only differences that the original supports: words added or omitted, restructuring or moved clauses, notable word choices,
  tense/number changes, verse-boundary differences, and textual variants.
- Textual variants: say the target follows the Textus Receptus / critical text ONLY when its wording shows it
  (e.g. it translates a `[TR]` word, or omits an `[NA]` word). Use the language card's terms.
- Quote short phrases of the target Bible in the language's quotation marks; give original words as `word ("meaning")`.
- If nothing notable: write only the language card's "close" sentence (Greek or Hebrew form).
- Whole-`[TR]` verse: first sentence = the verse is absent from the critical text and the target includes it following the Textus Receptus; second sentence = the literal translates the Textus Receptus.
- If the target is `(none)`: say in one sentence that this Bible has no text at this verse (its content is in a neighboring verse).
- No theology, no judgment of quality, no guesses about translator intent.

## OUTPUT
For every TARGET block, one line per verse, same order and verse numbers as the packet:
`<verse>\t<LITERAL>\t<DIFFERENCE>`
- Exactly 3 fields separated by a TAB. No tabs or line breaks inside fields. No header, no blank lines, no code fences, no markdown.
- Write each TARGET block to its own file (see README), or, in a chat, prefix each block with a line `=== <lang> <packet file name>`.
