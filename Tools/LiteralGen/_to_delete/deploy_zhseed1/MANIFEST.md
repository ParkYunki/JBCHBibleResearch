# deploy_zhseed1 — 중국어 참고자료의 옛 책 이름 표기 교체 (2026-10-29)

치환(정확한 문자열만): 创世纪→创世记, 腓利比书→腓立比书, 约翰壹书/贰书/参书→约翰一书/二书/三书.
번체(創世紀, 腓利比書, 約翰壹/貳/參書)는 zh 데이터에 0건이라 바뀐 것이 없다.
글자 수와 UTF-8 바이트 수가 같아 모든 파일 크기가 그대로다.

## 파일 (이 폴더의 상대 경로 = Mac 저장소 루트 기준 대상 경로)
| 파일 | 이전 md5 | 이후 md5 | 바뀐 내용 |
|---|---|---|---|
| `ReferenceDataSource/i18n/zh/PersonSeed.json` | 74e5e905d7fa1cabae1d2086e64a9d5b | 6d4c6853bc74be3e7f138a5b91ffc497 | 1,422곳 (创世纪 1378, 约翰参书 21, 腓利比书 20, 约翰壹书 2, 约翰贰书 1). 항목 330/2948, 줄 781 |
| `ReferenceDataSource/i18n/zh/PlaceSeed.json` | 85101cb8f245fb669b6c8900d324c262 | 11e5846cdc5b1bc39e5f18ca827b14cb | 263곳 (创世纪 260, 腓利比书 3). 항목 108/1052, 줄 119 |
| `ReferenceDataSource/i18n/zh/TribeSeed.json` | 7eb97ec4d9a7d4903fc31a884063232a | e901e07eb0d3e370ec66a981f11fcf64 | 15곳 (创世纪). 항목 8/33, 줄 9 |
| `ReferenceDataSource/i18n/RelationLabelVocab.tsv` | 8f81f45e7b1d1754f408cb0f3b7cad4e | 570d39f7d383a0796e265ec98e2e29b0 | zh 열(4번째)만 10곳 (创世纪). 269·270·286·287·318·328·342·344·345·360행 |
| `JBCHBibleResearch/Resources/OutlineSeed_zh.json` | 076a909cf5253c0d464af5ee12837c1b | e0e3d4b9aabf584c8eaf9cb67c772b7b | 146곳 (腓利比书 82, 约翰壹书 32, 创世纪 25, 约翰贰书 7). 항목 44/1255 |
| `JBCHBibleResearch/Resources/ReferenceData.sqlite` | b260c928fea5682b673ce99900034061 | 9dc606eb8718a2d473a0f85cb1579c54 | zh 행 칸 1,071개, 1,908곳 (아래 표) |

이전 md5는 2026-10-29 작업 끝에 Mac에서 다시 확인했다. 반영하기 전에 Mac 파일의 md5가 위의 "이전" 값과 같은지 확인할 것. 다르면 그 사이에 바뀐 것이므로 덮어쓰지 말 것.

## sqlite를 만든 방법
Mac 사본에서 `lang='zh'` 행의 텍스트 칸에만 UPDATE를 적용했다(`/home/claude/integ/zhseed1/tools/apply_db.py`). 이렇게 하면 FTS 그림자 표 바이트가 Mac 파일 그대로 남는다. 이 결과가 고친 소스로 다시 빌드한 것과 같다는 것을 아래 4번으로 증명했다.

## 검증
1. `PRAGMA integrity_check` = ok (이전·이후 모두). FTS5 `integrity-check` 통과. journal_mode = delete, 남은 -journal/-wal 파일 없음.
2. 26개 표 모두 행 수가 같다. 스키마 객체 44개도 같다.
3. 바뀐 칸은 모두 "이전 값에 치환을 적용한 값"과 정확히 같다(어긋난 칸 0). 바뀐 행은 모두 `lang='zh'`다. 옛 표기는 DB 전체에서 0건 남았다.

| 표 | 바뀐 칸 | 열별 |
|---|---|---|
| PersonsI18n | 942 | lifetime 311, event 207, remark 183, introduce 183, character 57, call_title 1 |
| PlacesI18n | 119 | biblecontents 106, introduce 7, geography 4, history 2 |
| RelationLabelsI18n | 10 | label 10 |
| 나머지 23개 표 | 0 | — |

예시 (키, 칸: 이전 → 이후)
- PersonsI18n ('zh','2') lifetime: 挪亚的孙子（创世纪10:6） → （创世记10:6）
- PersonsI18n ('zh','40') remark: 他们属于创世纪第10章的族谱 → 创世记第10章
- PersonsI18n ('zh','3260') introduce: 约翰参书中记载了长老写给该犹 → 约翰三书中…
- PersonsI18n ('zh','4386') introduce: 约翰福音、约翰壹书、约翰贰书、约翰参书 → 约翰一书、约翰二书、约翰三书
- PlacesI18n ('zh','3') biblecontents: 一直延伸(创世纪10:19) → (创世记10:19)
- RelationLabelsI18n ('zh','동일인 추정, 창 10:23') label: 推定为同一人, 创世纪10:23 → 创世记10:23

4. 다시 빌드해서 확인: 컨테이너에서 `build_reference_data.py`(Mac과 같은 파일, md5 f5e035cb…)를 돌렸다.
   - 고치기 전 소스로 빌드한 것과 Mac 원본은 논리 내용이 같다. 다른 것은 FTS5 내부 세그먼트 바이트(`VerseSearchIndex_data`, `_idx`)뿐이다. `VerseSearchIndex`와 `_content`, `_docsize`는 같다.
   - 고친 소스로 빌드한 것과 이 폴더의 sqlite를 비교하면 차이가 위와 똑같다(FTS 내부 바이트뿐, diff 출력이 한 글자도 다르지 않음).
   - 이전 소스 빌드와 새 소스 빌드를 비교하면 PersonsI18n 942, PlacesI18n 119, RelationLabelsI18n 10칸만 다르다. 빌드 로그도 같다.
   - 따라서 Mac에서 이 폴더의 소스로 다시 빌드해도 같은 내용이 나온다.
5. JSON 4개 모두 유효하고 항목 수가 같다. 각 파일은 "이전 파일 전체에 치환을 적용한 것"과 바이트 단위로 같다.

## 반영 순서
위 6개 파일을 같은 경로에 덮어쓴다. Xcode 대상 설정은 바꿀 필요가 없다(기존 파일 교체).
OutlineSeed_zh.json은 기기당 한 번만 가져온다. 이미 설치한 zh 사용자의 개요는 예전 표기 그대로 남는다. 인물·지명 사전(sqlite)은 앱 재실행 후 바로 바뀐다.
