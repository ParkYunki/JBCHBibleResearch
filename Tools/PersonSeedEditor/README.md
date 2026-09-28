# PersonSeedEditor

`PersonSeed.json`(인물 데이터, `ReferenceDataSource/PersonSeed.json`)을 GUI로
수정하기 위한 별도 macOS 앱입니다. 메인 앱(`JBCHBibleResearch`, App Sandbox
켜짐)과는 완전히 분리된 독립 Swift 패키지라, 메인 앱을 전혀 건드리지 않고
파일 시스템 접근·`python3` 서브프로세스 실행을 자유롭게 할 수 있습니다.

## 실행 방법

```bash
cd Tools/PersonSeedEditor
swift run
```

첫 실행은 컴파일 때문에 다소 걸릴 수 있습니다. 이후 실행부터는 빠릅니다.

⚠️ 이 코드는 Xcode/Swift 툴체인이 없는 환경에서 작성돼 `swift build`로도
컴파일을 확인하지 못했습니다 — 처음 `swift run` 했을 때 컴파일 에러가
나올 수 있습니다. 에러 메시지를 알려주시면 바로 고치겠습니다.

## 할 수 있는 것

- 인물 목록 검색(이름/별칭/idx), 추가, 삭제
- 모든 필드 편집: 이름/별칭/호칭/뜻풀이, 개요·생애·사건·성품, 인물 정보
  (출신/민족/지파/성별/직업), 가족관계 9종(할아버지~손녀), 기타관계
  (제자/동역자/친구 등 "이름(라벨)" 형식), 관련 구절
- 기타관계 항목마다 "동명이인 확인" 버튼 — 같은 이름을 가진 PersonSeed.json
  항목이 몇 명인지 바로 확인(오늘 세션에서 야고보/요한/빌립 문제를 고칠 때
  썼던 것과 같은 확인 방식)
- "재빌드" 버튼 — `python3 build_reference_data.py`를 실행해
  `ReferenceData.sqlite`까지 한 번에 갱신(터미널에서 직접 실행하던 것과 동일)

## 저장 방식과 안전장치

이 앱은 JSON을 직접 다시 써 넣지 않습니다. 대신 검증된 파이썬 스크립트
(`ReferenceDataSource/apply_person_edit.py`)를 호출해 `json.load` → 메모리에서
수정 → `json.dump(ensure_ascii=False, indent=2)` 방식으로 안전하게 반영합니다
(이 세션 내내 PersonSeed.json을 손으로 고칠 때 써 온 것과 같은 패턴). idx가
중복되거나, 삭제 대상이 정확히 1건이 아니면 스크립트가 거부합니다 —
애매하면 아무것도 건드리지 않습니다.

## 재빌드 후 확인

재빌드가 끝나면 `JBCHBibleResearch` 앱을 다시 시작해야 새 데이터를
읽습니다(앱이 시작할 때 `ReferenceData.sqlite`를 번들에서 한 번만 엽니다).

## 알려진 제약

- "동명이인 확인" 버튼은 정보 확인용일 뿐, 어느 후보를 골랐는지 저장하지는
  않습니다. `기타관계` 문자열 포맷("이름(라벨)") 자체엔 idx를 끼워 넣을
  자리가 없어서입니다 — 애매하면 이름을 더 구체적으로 고치거나(예:
  "예수" → "유스도라 하는 예수") 새 항목으로 분리하는 지금까지의 방식을
  그대로 따르면 됩니다.
- 이 도구는 `Tools/PersonSeedEditor` 위치(저장소 루트 기준 상대 경로)를
  전제로 `PersonSeed.json` 경로를 스스로 계산합니다(`RepoPaths.swift`) —
  이 폴더를 저장소 밖으로 옮기면 동작하지 않습니다.
