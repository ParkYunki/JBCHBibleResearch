# AIRelationExtractor — PersonRelations 2단계(AI 보조 추출) 도구

## ⚠️ 2026-08-20 최종 업데이트 — 이 파이프라인은 현재 사용 중지 상태

v1(732건)·v2(6가지 금지 규칙+코드 필터 추가, 551건) 두 차례 모두 실제 기기에서
추출·병합한 뒤 원문(`raw_sentence`) 대조 표본 검수를 거쳤으나, **정확도가
각각 약 11% / 약 12%로 사실상 동일**했다(1단계 정규식의 오탐율 0.3% 미만과
비교하면 압도적으로 낮음). 핵심 실패 패턴("~와 관련이 있다" 같은 단순 문맥
언급을 가족관계로 오인, "~를 조상으로 둔 후손이다" 방향 반전, 문장에 명시된
관계어를 무시하고 다른 값을 고름)은 프롬프트를 상당히 정교하게 다듬어도 해소되지
않았다. 사용자와 상의해 **AI 추출분을 전부 폐기하고 1단계 정규식(3595건) +
수기 교정(6건) = 3601건만 실사용 데이터로 확정**하기로 결정했다.

- `ReferenceDataSource/AIExtractedRelations.v1_저품질_참고용.json`(732건)와
  `AIExtractedRelations.v2_저품질_참고용.json`(551건)은 **참고/향후 재설계용으로만
  보관**한다 — `build_reference_data.py`는 정확히 `AIExtractedRelations.json`
  파일만 자동으로 읽으므로 이름이 다른 이 파일들은 병합에 관여하지 않는다.
- `UnmatchedRelationSentences.json`(771건)은 현재 **미해결로 남긴다** — AI로
  더 줄이려는 시도는 이 방식으로는 보류.
- 이 폴더(`AIRelationExtractor.swift`/`README.md`)는 코드 자체는 지우지
  않고 남겨둔다 — 향후 다른 접근(예: 모델에게는 문장 속 관계어를 그대로
  인용만 하게 하고, 관계어→relation_type 변환은 Python 쪽 고정 사전이
  담당하는 하이브리드 방식)으로 재설계할 때 참고 자료로 쓸 수 있다. **현재
  상태로는 실행해도 결과를 신뢰할 수 없으므로 재설계 없이 그대로 다시
  돌리는 것은 권장하지 않는다.**

아래 "빌드 및 실행" 절 이하는 v2 상태를 그대로 남겨둔 **참고 문서**다(재설계
전까지는 실행하지 않는 것을 권장).

---

## 이게 뭔가요

`build_reference_data.py`의 `PersonRelations` 추출기는 1단계로 정규식(`RELATION_PATTERNS`) 기반
패턴 매칭을 수행합니다. 이 방식은 빠르고 예측 가능하지만, 문장의 진짜 문법적 주어를 판단하지
못한다는 구조적 한계가 있습니다(예: "여선지자 훌다의 시아버지 OO" 같은 제3자 언급을 표제어 본인의
관계로 잘못 추출하는 경우 — 이미 발견된 11건의 오탐이 이 유형입니다).

2단계는 1단계가 매칭하지 못한 문장(현재 771건, `UnmatchedRelationSentences.json`)을 애플의
온디바이스 언어모델(FoundationModels)에 넣어, 문맥을 이해한 상태에서 관계를 추출하거나
"관계 없음(제3자 언급 등)"으로 판단하게 합니다. **다만 위 2026-08-20 업데이트에서 보듯, 이
접근 자체가 정규식보다 훨씬 오류에 취약하다는 것이 실측으로 확인됐으므로, 병합 후 표본 검수는
선택이 아니라 필수 단계로 취급해야 합니다.**

**이 도구는 이 샌드박스(Linux 컨테이너)에서 컴파일도 실행도 불가능합니다.** FoundationModels는
Apple Intelligence를 지원하는 실제 Mac(macOS 26+)에서만 동작하는 프레임워크이기 때문입니다.
아래 안내에 따라 사용자의 Mac에서 직접 빌드·실행해야 합니다.

## 사전 요구사항

- macOS 26 (Tahoe) 이상, Apple Intelligence를 지원하는 Apple Silicon Mac
- 시스템 설정에서 Apple Intelligence가 켜져 있어야 함 (꺼져 있으면 도구가 시작 시
  `appleIntelligenceNotEnabled` 오류를 출력하고 종료합니다)
- Xcode 26 이상 (Swift 6 툴체인, FoundationModels 프레임워크 포함)
- 모델 다운로드가 아직 안 되어 있다면 `modelNotReady` 오류가 뜰 수 있습니다 — 이 경우 시스템
  설정 > Apple Intelligence & Siri 에서 다운로드 진행 상태를 확인하세요.

## 준비물

이 폴더(`ReferenceDataSource/AIRelationExtractor/`)에는 다음이 들어 있습니다:

- `AIRelationExtractor.swift` — 실행 파일 소스(v2 프롬프트, 2026-08-20 개정)
- `README.md` — 이 문서

실행하려면 `ReferenceDataSource/UnmatchedRelationSentences.json` (상위 폴더, 현재 771건)이
필요합니다. 빌드된 `build_reference_data.py`를 이미 device에 반영했다면 이미 존재할 것입니다.

## 빌드 및 실행

터미널에서 **`ReferenceDataSource/` 폴더로 이동한 뒤** (상대 경로로 입출력 JSON을 찾기 때문에
반드시 이 위치에서 실행해야 합니다):

```bash
cd /Users/arkuni/Developer/JBCHBibleResearch/ReferenceDataSource

swiftc AIRelationExtractor/AIRelationExtractor.swift \
  -o AIRelationExtractor/AIRelationExtractor \
  -parse-as-library

./AIRelationExtractor/AIRelationExtractor
```

동작:

1. `UnmatchedRelationSentences.json`(현재 771건)을 읽습니다.
2. 이미 `AIExtractedRelations.json`이 존재하면 (source_word, source_idx, sense_index) 기준으로
   이미 처리된 항목을 건너뜁니다 — 중간에 중단해도 재실행 시 이어서 진행됩니다. **v1에서 v2로
   넘어온 지금은 이 파일이 없는 상태(v1은 이름을 바꿔 보관 중)이므로 처음부터 새로 시작합니다.**
3. 문장 하나마다 새 `LanguageModelSession`을 만들어 관계를 추출하거나 `none`으로 판단합니다.
4. **(v2 신설)** 추출된 관계 각각에 대해 코드 레벨 방어 필터(`isTargetWordValid`)를 통과한
   것만 저장합니다 — 자기순환, 원문에 없는 이름, 일반명사 이름은 자동으로 걸러집니다.
5. 20건마다 `AIExtractedRelations.json`에 중간 저장(flush)합니다.
6. 끝나면 처리/추출/스킵(관계없음 판정/필터로 걸러짐 각각 별도 집계)/오류 유형별 통계를
   출력합니다.

**소요 시간은 제가 임의로 추정하지 않습니다.** 온디바이스 모델 추론 속도는 기기(M1/M2/M3/M4,
메모리)에 따라 크게 달라지고, 771건 × 세션 생성 오버헤드가 더해지므로, 실제 실행해서 처음
20~30건 처리 시간을 보고 전체 예상 시간을 가늠하시는 것을 권장합니다. 중간 저장이 되므로
급하지 않다면 나눠서 실행하셔도 무방합니다.

## 실행 후: 결과를 앱에 반영하기

`AIExtractedRelations.json`이 `ReferenceDataSource/` 바로 아래에 생성되면, 평소처럼 빌드
스크립트를 다시 실행하기만 하면 됩니다:

```bash
cd /Users/arkuni/Developer/JBCHBibleResearch/ReferenceDataSource
python3 build_reference_data.py
```

`build_reference_data.py`는 `AIExtractedRelations.json`이 존재하면 자동으로 읽어, 이미 1단계
정규식으로 잡힌 (source_word, source_idx, sense_index, target_word, relation_type) 조합과
중복되지 않는 항목만 `extraction_method = 'ai'`로 `PersonRelations` 테이블에 추가합니다.
`relation_type`이 유효한 24종 중 하나가 아니거나 `target_word`가 비어 있는 등 형식이 잘못된
레코드는 콘솔에 경고를 남기고 건너뜁니다(검증 로직은 합성 테스트로 이미 확인됨).

재실행은 안전합니다 — 매번 처음부터 다시 계산하므로 이전 산출물이 남아있어도 중복 삽입되지
않습니다.

## 결과 확인 방법 (선택, v2에서는 필수에 가깝게 권장)

```bash
sqlite3 ../JBCHBibleResearch/Resources/ReferenceData.sqlite \
  "SELECT extraction_method, COUNT(*) FROM PersonRelations GROUP BY extraction_method;"
```

`ai` 건수가 0보다 크면 정상적으로 반영된 것입니다. **v1의 교훈에 따라, 병합 직후 반드시
`raw_sentence`(같은 테이블에 저장돼 있음) 컬럼을 몇 건이라도 직접 조회해 원문과 대조하는
표본 검수를 거친 뒤 커밋하세요**:

```bash
sqlite3 ../JBCHBibleResearch/Resources/ReferenceData.sqlite \
  "SELECT source_word, relation_type, target_word, raw_sentence FROM PersonRelations \
   WHERE extraction_method='ai' ORDER BY RANDOM() LIMIT 30;"
```

## 참고 — 검증 범위에 대한 정직한 고지

- Python 쪽(내보내기/병합 로직)은 실제로 실행하여 검증했습니다(합성 픽스처로 신규 삽입/none
  스킵/잘못된 키 거부 세 가지 분기를 모두 확인, 실사용 병합도 v1에서 이미 성공적으로 검증됨).
- Swift 쪽(`AIRelationExtractor.swift`)의 API 호출 골격(가용성 체크, 세션 생성, 오류 처리)은
  v1이 실제 기기에서 컴파일·실행·병합까지 성공해 이미 검증됐습니다. **다만 v2에서 바뀐 것은
  프롬프트 문자열과 후처리 필터 로직이며, 이 부분의 실제 효과(정확도가 실제로 올라가는지)는
  이 세션에서는 검증할 수 없고 실기기 재실행 + 표본 검수로만 확인할 수 있습니다.** 빌드 시
  오류가 발생하거나, 재검수에서도 오류율이 여전히 높으면 알려주시면 원인을 분석해 추가로
  수정하겠습니다.
