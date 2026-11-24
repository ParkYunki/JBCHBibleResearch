# JBCH 중국어 원어 정렬: 상태 요약 (ChatGPT 전달용, 회차마다 이 파일만 첨부)

## 고정 원칙 (재논의 금지)
- 중국어 직역 31,104절(Literal_zh.sqlite LiteralText)은 그대로 둔다.
- 원어 단어 번호는 OriginalText.sqlite 기준(ORDER BY word_order, rowid, 0-기반 word_index).
- WordAlignment(book_id, chapter, verse, word_index, phrase, start) 스키마는 바꾸지 않는다. start는 Unicode scalar 오프셋이고 Python이 계산한다.
- 판본 제외: 신약 [TR]·[Byz], 구약 [LXX] 단어는 짝을 짓지 않는다(edition_flags_v2.json). hold 224절 해결, 남은 hold 1절(요 7:53).
- AI는 중국어 문장에 `{구간|번호}` 표시만 한다. 오프셋, 문자열 일치, 판본 제외, 문장부호 경계 검사는 Python(check.py)이 한다.

## 진행 상황 (2026-11-11)
- 1~3단계: 완료(“~” 표시 한국어 한정, 절 번호 집합 비교, edition_flags).
- 4단계: 도구 중국어 모드 완료. 기존 언어 회귀 0건.
- 시범 200절: 198절 합격, 짝 비율 83.4%(관사·접속사·목적격 표지 미대응이 대부분).
- 지금: 시범 결과 교차 검수(이 회차) → 토큰 절약 구조(압축 패킷, 승인 사전, 위험도별 재검토) 적용 → 본작업.

## 이번 회차 요청
- 첨부한 데이터 파일의 짝 판정만 한다. 지시는 align_zh_review_instructions.md를 따른다.
