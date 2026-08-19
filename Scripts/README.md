# 의미검색 임베딩 모델 설정 (multilingual-e5-small)

AI 검색(의미검색)이 쓰는 임베딩 모델을 준비하는 1회성 작업입니다. 이 세션(샌드박스)은
huggingface.co 접속이 막혀 있어서 아래 단계를 직접 실행해보지 못했습니다 —
**맥 터미널에서 실행**해주세요.

## 1) Python 환경 준비 및 변환 실행

```bash
cd JBCHBibleResearch/Scripts
python3 -m venv .venv
source .venv/bin/activate
pip install torch transformers coremltools
python3 convert_multilingual_e5_small.py
```

몇 분 정도 걸릴 수 있습니다(모델 다운로드 + Core ML 변환). 완료되면 `Scripts/` 폴더 안에
다음 두 가지가 생깁니다.

- `MultilingualE5Small.mlpackage`
- `MultilingualE5SmallTokenizer/` (폴더)

에러가 나면 그 메시지를 그대로 알려주세요 — `convert_multilingual_e5_small.py` 상단
주석에 적어둔 대로, 이 스크립트는 한 번도 실행 검증이 안 됐습니다.

## 2) Xcode에 리소스 추가

1. `MultilingualE5Small.mlpackage`를 Xcode 프로젝트 내비게이터로 드래그해서
   `JBCHBibleResearch` 타겟에 추가합니다(빌드 시 자동으로 `.mlmodelc`로 컴파일됩니다).
2. `MultilingualE5SmallTokenizer/` 폴더는 **폴더 참조(파란 폴더 아이콘)**로 추가해야
   합니다 — "Create groups"가 아니라 "Create folder references"를 선택하세요. 개별
   파일로 흩어져 추가되면 `EmbeddingService.swift`가 폴더를 찾지 못합니다.

## 3) SPM 의존성 추가 (토크나이저)

Xcode → File → Add Package Dependencies → 아래 URL 입력:

```
https://github.com/huggingface/swift-transformers
```

버전은 `from: 1.3.0`(기본값)으로 두고, 제품 목록에서 **`Tokenizers`만** 체크해
`JBCHBibleResearch` 타겟에 추가합니다(`Transformers`나 `Hub`는 필요 없습니다 —
네트워크 다운로드 기능까지 딸려와 앱이 무거워집니다).

## 완료 확인

빌드 후 검색 화면에서 AI 검색 토글을 켜고 "색인 만들기"를 눌렀을 때 에러 없이
진행률이 올라가면 정상입니다. `EmbeddingService.checkAvailability()`가
`.unavailable`을 반환한다면 위 두 리소스 중 하나가 빠졌거나 이름이 다른 것입니다
(`EmbeddingService.swift`의 `modelResourceName`/`tokenizerResourceName` 상수와
실제 파일 이름이 정확히 일치해야 합니다).
