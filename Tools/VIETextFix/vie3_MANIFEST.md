# deploy_vie3 — VIE1934 원본 오타·하이픈 공백, TGLULB U+0081, 차이 설명 정리 (2026-10-29)

## 파일
| 파일 | 이전 md5 (Mac 현재) | 이후 md5 | 내용 |
|---|---|---|---|
| `JBCHBibleResearch/Resources/Bible_VIE1934.sqlite` | 5495d89a74ae21698776b7e1bee71df3 | 57124d3cad82d4ef29becc490bfce434 | content 42절 (43곳) |
| `JBCHBibleResearch/Resources/Bible_TGLULB.sqlite` | 1bd6affd19ffd189b3a40de7eebb716e | be0defff51563964fc5393405b8a5fc1 | content 22절, U+0081 24개 삭제 |
| `JBCHBibleResearch/Resources/Literal_vi.sqlite` | 7272f6e9cabb9d0deff226eff553db0e | 0c7f73f6a66104a73fd927d193bff7b3 | TranslationDifference 26행 삭제 (29,008 → 28,982) |

- 모두 30MB 이하라 파일을 그대로 넣었다. 이전 md5는 2026-10-29 작업 끝에 Mac에서 다시 확인했다. 덮어쓰기 전에 Mac 파일 md5가 "이전" 값과 같은지 확인할 것.
- `Literal_fil.sqlite`(타갈로그어)는 바꾸지 않았다. TGLULB 22절의 설명에는 U+0081이나 원본 오류에 대한 언급이 없다. `TranslationVerseHash`는 ABAB만 들어 있어 TGLULB 본문 변경과 관계가 없다.
- 이 폴더의 다른 파일
  - `vie_edits.json`: 치환 43건(절, 이전·이후 문자열, 근거)
  - `evidence_vie3.tsv`: 절별 근거 URL·인용, 확인 못 한 절
  - `regen_targets_vie3.tsv`: 이번에 지운 26행(+지운 설명 원문)
  - `regen_targets_all.tsv`: vie2 2,084 + 추가 12 + vie3 26 = 2,122행 전체
  - `Tools/VIETextFix/apply_vie3.py`, `Tools/VIETextFix/verify_vie3.py`

## 1. VIE1934 — 고친 42절
대조본: S1 bible.com VIE1925(id 193), S2 kinhthanh.httlvn.org VI1934, S3 ebible.com/vietnamese, S4 biblehub.com/multilingual·ccel.org(옛 VNI 판본).
biblehub/multi, bibliaparalela/multi, cnbible, transcripture, bibliaonline은 eBible 사본이라(같은 오타) 근거로 쓰지 않았다.

| 절 | 이전 → 이후 | 근거 |
|---|---|---|
| 창 13:10 | đồng ó → đồng đó | S1 |
| 창 20:13 | làm cco tôi pưu lạc → làm cho tôi phải lưu lạc | S3, S4 |
| 민 7:37 | thánhhh → thánh | S3 |
| 민 24:21 | ì ngươi đóng → Ổ ngươi đóng | S3, S4 |
| 신 3:6 | connnnn trẻ → con trẻ | S3, S4 |
| 신 3:8 | Ạt-nnôn → Ạt-nôn | S3 |
| 수 18:21 | Bết-Hôt-la → Bết-Hốt-la | S2 (S3·S4는 "Bết-Hô-đa"로 다름. 같은 성경 수 15:6·18:19는 Bết-Hốt-la) |
| 삿 7:11 | cóóóóóómạnh → có sức mạnh | S4 |
| 삼상 16:2 | g: àm sao tôi đii → Làm sao tôi đi / ngggggggơi → ngươi | S3 |
| 삼하 12:5 | đđng → đáng | S3 |
| 삼하 12:6 | conkhông → con, vì đã làm như vậy, và vì không | S3, S4 |
| 왕상 11:1 | người n Ê-đôm → người nữ Mô-áp, Am-môn, Ê-đôm | S3 |
| 왕하 11:15 | Giêiêô-gia-đa → Giê-hô-gia-đa | S4 |
| 시 106:47 | Chúa, úa, … ngợ hen Chúaa. → Chúa, … ngợi khen Chúa. | S3 |
| 잠 8:24 | s sh ra → sanh ra | S4 |
| 사 23:16 | mầyầyy → mầy! | S3 |
| 렘 38:7 | quănăng → quăng | S3 |
| 막 3:22 | nhờờờờờờ chúa quỉ mà ttttttrừ → nhờ phép chúa quỉ mà trừ | S3, S4 |
| 막 16:20 | làm cho v???? → làm cho vững đạo. | S1, S2, ccel (S1·S2는 끝에 ] 또는 ) 가 있으나 이 DB에는 여는 괄호가 없어 넣지 않음) |
| 하이픈 뒤 공백 23절 | 눅 1:26, 2:4, 2:25, 2:42, 3:8, 3:24, 3:27, 3:28, 3:31, 3:35, 3:36, 3:37, 4:31, 9:52, 9:53, 14:5, 16:23, 17:11, 23:18, 23:26, 23:51, 딤후 4:13, 히 5:10 | 같은 성경 다른 곳(또는 같은 절)의 붙은 표기 + S3·ccel 눅 3장(공백 없음) |

요청서의 "24곳"은 현재 DB에서 다시 세면 23곳이다(이름 안 `-` 뒤 공백).

## 확인 못 해 고치지 않은 5절
| 절 | 현재 | 사유 |
|---|---|---|
| 대상 12:8 | có ó ững người | 독립 대조본에 이 절 본문을 찾지 못함 |
| 욥 33:17 | nguời | 대조본(S4, ccel)도 같은 "nguời"이고 "chở"가 더 있음 |
| 시 135:11 | Từc | 대조본 본문을 찾지 못함 |
| 슥 12:6 | ỡ chỗ mình | eBible 사본만 찾음(같은 오타) |
| 롬 16:9 | Eâch-ta-chy | ebible.com도 같은 글자. 독립 대조본 없음 |

## 2. TGLULB — U+0081 (22절, 24개) 삭제
- 원본 `BibleSources/tglulb_usfm.zip`(md5 c8c3bf79…)의 USFM에도 같은 자리에 U+0081이 있다. 렘 46–47장 7개, 애 3장 6개, 호 2장 9줄 11개다.
- 모두 공백 뒤, 절 첫머리, 절 끝, 대시 뒤(렘 46:28 `Yahweh—\x81sapagkat`)에 있다. 지워도 단어가 붙지 않고 빠지는 글자도 없다. 시의 행 경계 자리에 들어간 비인쇄 C1 제어문자로 판단했다. 따옴표·대시·악센트 자리를 차지한 경우는 없다(애 3:24는 `\x81“Si`처럼 따옴표가 따로 있음).
- 외부 TGLULB(ULB) 대조본은 온라인에서 찾지 못했다(biblehub의 타갈로그어는 1905 Ang Dating Biblia, ebible.com은 다른 번역). 지워도 눈에 보이는 본문은 바뀌지 않는다.

## 3. Literal_vi — 틀린 설명이 된 26행 삭제
고친 42절 중 TranslationDifference가 원본 오타·하이픈을 설명하던 행이다(삭제와 칸 비우기 중 삭제를 고른 근거는 vie2와 같음).
창 13:10, 민 7:37, 신 3:6, 수 18:21, 삿 7:11, 삼하 12:5, 12:6, 왕상 11:1, 왕하 11:15, 시 106:47, 사 23:16, 렘 38:7(오타 + "Ê-thi-ô-bi" 설명이 섞인 행), 막 3:22, 16:20, 눅 2:4, 2:25, 2:42, 9:52, 9:53, 14:5, 17:11, 23:18, 23:26, 23:51, 딤후 4:13, 히 5:10.
행이 없거나 "Gần với Hy Lạp." 같은 일반 설명인 절은 두었다.

## 검증 (`verify_vie3.py`)
- `integrity_check` ok(이전·이후 6개), journal_mode delete, 남은 -journal/-wal 없음.
- VIE1934: 스키마 같음, 31,102행, 바뀐 행 42개 = 대상 절, content 밖의 칸 차이 0. `audit_vie.py`로 남은 이상 토큰은 미확인 3개(nguời, Từc, Eâch)뿐이다.
- TGLULB: 스키마 같음, 31,103행, 바뀐 행 22개, content 밖의 칸 차이 0. 각 행은 "이전 값에서 U+0081만 뺀 것"과 같고, 남은 U+0081은 0이다.
- Literal_vi: 스키마·LiteralText 같음. TranslationDifference 29,008 → 28,982. 지운 키 = 목록, 남은 행 모두 같음, 새 행 0. VACUUM함.

## 반영
위 3개 파일을 같은 경로에 덮어쓴다. 또는 연결 폴더 밖 사본에서 `python3 -I Tools/VIETextFix/apply_vie3.py vie_edits.json Bible_VIE1934.sqlite Bible_TGLULB.sqlite Literal_vi.sqlite regen_targets_vie3.tsv`를 돌린다. 기준 md5가 아닌 사본에서는 assert에서 멈추고 아무것도 바꾸지 않는다.
