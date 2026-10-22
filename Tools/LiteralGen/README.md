# 언어별 직역·번역 차이 설명 생성 절차 (LiteralGen)

빌레몬서 시범(2026-10-12)과 같은 결과물을 성경 전체로 만드는 절차입니다. 다른 AI 도구로 생성하고,
검사·DB 변환은 이 폴더의 스크립트로 합니다. 함께 볼 문서: 프로젝트 문서 `original-text-literal-2026-10-12.md`(DB 구조),
`literal-generation-pilot-2026-10-12.md`(시범 기록·생성 규칙).

## 1. 결과물
- 12개 언어 × 31,100절: 앱 언어 **직역** + 그 언어 번들 성경과의 **차이 설명**.
- 최종 파일: `JBCHBibleResearch/Resources/Literal_<언어>.sqlite` (`import_outputs.py --build`가 만든다. 손으로 만들지 않는다).
- 언어와 비교 번역본: en=BSB · es=RV1909 · fr=LSG1910 · de=LUT1912 · it=RIV1927 · pt=BPM · ru=SYN · vi=VIE1934 · fil=TGLULB · th=THKJV · id=AYT · ja=JPBUNGO.
  (한국어 KRV는 기존 데이터. 영어 직역은 LSV를 그대로 쓰므로 en은 차이 설명만 만든다.)

## 2. 폴더
| 경로 | 내용 |
|---|---|
| `PROMPT_RULES.md` | 생성 규칙(영어). **모든 호출의 맨 앞에 한 번** 넣는다 |
| `lang/<언어>.md` | 언어 카드: 용어·문체·시범 예시 4절 |
| `make_packets.py` | 입력 묶음 만들기(원어+문맥 번역+LSV는 한 번, 번역본 본문은 언어별) |
| `packets/<언어묶음>/<NN_BOOK>/<BOOK>_<장>[_부분].txt` | AI에게 줄 입력 |
| `outputs/<언어>/<NN_BOOK>/<BOOK>_<장>[_부분].tsv` | AI 출력(언어별 파일) |
| `split_blocks.py` | 채팅 답변 → 출력 파일로 나누기 |
| `import_outputs.py` | 검사(`--check`), 재생성 목록(`redo_<언어>.txt`), DB 만들기(`--build`) |
| `outputs/*/57_PHM/PHM_001.tsv` | 빌레몬서 시범 결과(기준 예시). 덮어쓰지 않는다 |

## 3. 작업 단위 (토큰 절약의 핵심)
- **묶음 1개 = 1장(30절 넘으면 30절씩)**. 약 1,400개.
- 원어·LSV(입력의 약 70%)는 묶음마다 **한 번만** 넣고, 같은 묶음에서 **여러 언어를 함께** 만든다.
  언어를 하나씩 따로 돌리면 원어 입력을 12번 보내게 된다.
- 권장 언어 묶음(비슷한 언어끼리, 한 번 출력이 너무 길지 않게):
  1. `es,pt,it,fr`  2. `de,en,ru`  3. `vi,id,fil`  4. `th,ja`
  출력이 잘리거나 언어가 섞이면 2개 언어로 줄인다.
- 대략적인 규모(참고): 원어·LSV 입력 약 1,270만 자, 번역본 본문 언어당 약 140만~490만 자.
  4묶음으로 나누면 언어별로 따로 할 때보다 입력이 절반 이하로 준다. 출력(약 37만 칸)은 줄일 수 없으므로 설명을 짧게 쓰는 규칙을 지킨다.

## 4. 절차
### 4-1. 묶음 만들기 (저장소 루트에서)
```
python3 Tools/LiteralGen/make_packets.py --langs es,pt,it,fr --books ALL
python3 Tools/LiteralGen/make_packets.py --langs de,en,ru --books ALL
python3 Tools/LiteralGen/make_packets.py --langs vi,id,fil --books ALL
python3 Tools/LiteralGen/make_packets.py --langs th,ja --books ALL
```
이미 모든 언어의 출력이 있는 묶음은 만들지 않으므로, 중간에 다시 실행해도 남은 것만 생긴다.
처음에는 `--books RUT,JON,MRK`처럼 몇 권으로 시작해 품질을 본다(구약 히브리어 확인 포함).

### 4-2. 생성 — 사용하는 도구에 맞게 하나 고른다
**A. 파일을 읽고 쓸 수 있는 AI 에이전트(권장)**: 아래 "시작 프롬프트"를 준다. 에이전트가 묶음을 차례로 읽고
`outputs/<언어>/…/<같은 이름>.tsv`에 바로 쓴다. 규칙·언어 카드는 세션 처음에 한 번만 읽는다.

**B. 채팅형 AI**: 대화 처음에 `PROMPT_RULES.md`와 해당 언어 카드들을 붙여 넣고(한 번), 이후 묶음 파일을 하나씩 첨부해
"이 묶음을 처리해."라고만 보낸다. 답변을 텍스트 파일로 저장해 `split_blocks.py`로 나눈다.
대화가 길어지면 새 대화를 열고 규칙·카드를 다시 붙인다(긴 대화는 규칙을 흐리게 한다).

**C. API 스크립트**: 메시지 순서를 `[PROMPT_RULES] → [==COMMON 블록] → [언어 카드 + ==TARGET 블록]`로 두면
앞부분이 묶음 안에서 같아 프롬프트 캐시를 쓸 수 있다. 출력은 B와 같은 `=== <lang> <파일>` 블록으로 받는다.
temperature는 0~0.3.

### 4-3. 검사 → 재생성 → DB
```
python3 Tools/LiteralGen/import_outputs.py --check            # 언어별 통과/실패 수, redo_<언어>.txt
python3 Tools/LiteralGen/import_outputs.py --check --langs fr
```
- 검사 항목: 절 수·순서가 묶음과 같은지, 칸 3개, 빈 칸, 마크다운·머리말, 언어 글자(th/ja/ru/vi), en 직역 칸 "=", 설명 길이(700자 초과).
- `redo_<언어>.txt`에 적힌 묶음만 다시 생성해 같은 파일에 덮어쓴다(그 언어만, 같은 묶음 파일로).
- 한 언어가 전부 통과하면:
```
python3 Tools/LiteralGen/import_outputs.py --build --langs fr --generator "<모델 이름>"
```
  → `Resources/Literal_fr.sqlite`를 다시 만든다(review_status = `ai`, 빌레몬서 시범분 포함).

### 4-4. 표본 검수
- 언어마다 책 3권 이상(구약 산문·시가서·신약 서신)에서 20절씩 원어민 또는 해당 언어 사용자가 본다.
- 볼 것: 직역이 원어 어순·시제를 지켰는지, 설명이 실제 차이만 말하는지, 사본 차이(TR/비평 본문)를 번역본 문구 근거 없이 말하지 않는지, 이름 표기가 그 번역본과 같은지.
- 문제가 반복되면 `lang/<언어>.md`에 금지·예시를 한 줄 추가하고 해당 책을 다시 생성한다.

## 5. 시작 프롬프트 (A·B 공통, 그대로 복사)
```
첨부한 README.md(Tools/LiteralGen)와 PROMPT_RULES.md, lang/<언어>.md를 먼저 읽어라. 프로젝트 문서 2개는 배경 자료다.
작업: Tools/LiteralGen/packets/<언어묶음>/ 의 묶음을 책 순서대로 처리해, 묶음의 ==TARGET 블록마다
Tools/LiteralGen/outputs/<언어>/<NN_BOOK>/<묶음 이름>.tsv 를 만든다(형식은 PROMPT_RULES.md의 OUTPUT).
규칙:
- 묶음 파일 외의 자료(DB, 다른 성경)를 읽지 마라. 규칙·언어 카드는 한 번 읽고 다시 읽지 마라.
- 출력 파일에는 데이터만 쓴다. 진행 설명은 책 하나가 끝날 때 한 줄만.
- 책 하나가 끝날 때마다 `python3 Tools/LiteralGen/import_outputs.py --check --langs <해당 언어들>`을 실행하고,
  redo 목록에 있는 묶음만 고쳐 다시 쓴다.
- 이미 있는 outputs 파일(특히 57_PHM)은 덮어쓰지 마라. 파일을 지우지 마라.
- 확신이 없는 사본 차이는 쓰지 말고 문구 차이만 쓴다.
범위: <책 코드 또는 ALL>, 언어 묶음: <예: es,pt,it,fr>
```
이어 할 때: "같은 규칙으로 이어서 해라. 먼저 import_outputs.py --check 로 남은 것과 실패한 것을 확인해라."

## 6. 토큰을 아끼는 규칙
- 묶음 하나에 여러 언어(위 4묶음). 원어 입력을 언어마다 다시 보내지 않는다.
- 규칙·카드는 세션(대화)당 한 번. 매 요청은 "다음 묶음" 한 줄 + 묶음 파일.
- 출력은 TSV만(JSON·설명·인사 금지). 차이가 없으면 카드의 "close" 한 문장. en 직역은 "=".
- 실패한 묶음만 다시 만든다(redo 목록). 통과한 파일은 다시 생성하지 않는다.
- 긴 장은 이미 30절씩 나뉘어 있다. 출력이 잘리는 도구면 `--max 15`로 다시 만든다.

## 7. 주의
- 파일 위치: 원본 자료는 `BibleSources/`(앱 번들에 안 들어감). `JBCHBibleResearch/` 안에 작업 파일을 두지 않는다(번들에 들어간다). 최종 DB만 Resources에.
- 라이선스: LSV(CC BY-SA 4.0)를 근거로 한 직역은 같은 라이선스(앱 설정의 고지 문구로 표시). 태국어 KJV(CC BY-NC-ND)는 설명에서 짧은 인용만.
- 정확도: AI 생성물이므로 앱에 "AI" 표시가 붙는다. 검수한 범위는 나중에 review_status를 `reviewed`로 바꾼다(스크립트 추가 필요).
