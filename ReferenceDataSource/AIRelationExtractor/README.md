# AIRelationExtractor — PersonRelations 2단계(AI 보조 추출) 도구

## 이게 뭔가요

`build_reference_data.py`의 `PersonRelations` 추출기는 1단계로 정규식(`RELATION_PATTERNS`) 기반
패턴 매칭을 수행합니다. 이 방식은 빠르고 예측 가능하지만, 문장의 진짜 문법적 주어를 판단하지
못한다는 구조적 한계가 있습니다(예: "여선지자 훌다의 시아버지 OO" 같은 제3자 언급을 표제어 본인의
관계로 잘못 추출하는 경우 — 이미 발견된 11건의 오탐이 이 유형입니다).

2단계는 1단계가 매칭하지 못한 문장(현재 793건, `UnmatchedRelationSentences.json`)을 애플의
온디바이스 언어모델(FoundationModels)에 넣어, 문맥을 이해한 상태에서 관계를 추출하거나
"관계 없음(제3자 언급 등)"으로 판단하게 합니다.

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

- `AIRelationExtractor.swift` — 실행 파일 소스
- `README.md` — 이 문서

실행하려면 `ReferenceDataSource/UnmatchedRelationSentences.json` (상위 폴더, 793건)이 필요합니다.
빌드된 `build_reference_data.py`를 이미 device에 반영했다면 이미 존재할 것입니다.

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

1. `UnmatchedRelationSentences.json`(793건)을 읽습니다.
2. 이미 `AIExtractedRelations.json`이 존재하면 (source_word, source_idx, sense_index) 기준으로
   이미 처리된 항목을 건너뜁니다 — 중간에 중단해도 재실행 시 이어서 진행됩니다.
3. 문장 하나마다 새 `LanguageModelSession`을 만들어 관계를 추출하거나 `none`으로 판단합니다.
4. 20건마다 `AIExtractedRelations.json`에 중간 저장(flush)합니다.
5. 끝나면 처리/추출/스킵 건수와 오류 유형별 통계를 출력합니다.

**소요 시간은 제가 임의로 추정하지 않습니다.** 온디바이스 모델 추론 속도는 기기(M1/M2/M3/M4,
메모리)에 따라 크게 달라지고, 793건 × 세션 생성 오버헤드가 더해지므로, 실제 실행해서 처음
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

## 결과 확인 방법 (선택)

```bash
sqlite3 ../JBCHBibleResearch/Resources/ReferenceData.sqlite \
  "SELECT extraction_method, COUNT(*) FROM PersonRelations GROUP BY extraction_method;"
```

`ai` 건수가 0보다 크면 정상적으로 반영된 것입니다.

## 참고 — 검증 범위에 대한 정직한 고지

- Python 쪽(내보내기/병합 로직)은 실제로 실행하여 검증했습니다(합성 픽스처로 신규 삽입/none
  스킵/잘못된 키 거부 세 가지 분기를 모두 확인).
- Swift 쪽(`AIRelationExtractor.swift`)은 Apple 공식 최신 문서와 실제로 컴파일되는 오픈소스
  참고 프로젝트를 근거로 작성했지만, 이 세션에서는 컴파일·실행이 불가능하여 실제 빌드 결과는
  검증하지 못했습니다. 빌드 시 오류가 발생하면 오류 메시지를 알려주시면 원인을 분석해
  수정하겠습니다.
