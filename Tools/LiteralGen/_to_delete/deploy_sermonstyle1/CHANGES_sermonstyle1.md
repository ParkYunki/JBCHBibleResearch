# sermonstyle1 — 설교 에디터: 스타일 변경 시 이전 스타일의 굵게가 남는 문제 (2026-10-29)

## 사용자 요청
"내 설교 - 에디터 - 스타일: 다른 스타일에서 본문 스타일로 변경하는 경우 이전 스타일의 볼드체가 본문 스타일에 계속 유지됨.
본문 스타일을 누르면 볼드체도 본문 스타일에 맞도록 변경되기를 원함."

## 원인 (소스 근거)
- 스타일 pill / F1~F6 → `SermonParagraphEditingProxy.applyParagraphStyle`(iOS·macOS) → `SermonParagraphStyleCodec.applyStyle`.
- `applyStyle`은 글자마다 `fontPreservingBoldItalic(from: 원래글꼴, applying: 새 프리셋)`을 호출한다. 이 함수는 원래 글꼴의
  굵게·기울임 symbolic trait를 새 프리셋 글꼴에 **무조건** 다시 입힌다. 원래 글꼴이 대주제·중주제·소주제 프리셋
  (Paperlogy ExtraBold/Bold/SemiBold) 자체라서 굵은 경우에도 그 굵기를 "사용자 굵게"로 보고 본문(GowunBatang-Regular)에 넘긴다
  → `GowunBatang-Bold`로 바뀐다(고운바탕 Regular/Bold는 family "Gowun Batang"을 공유해 trait 변환이 성공).
- 굵게는 `.font`의 trait로만 표현된다(`strokeWidth`·사용자 정의 속성 없음). 강조1도 `fontSettingBold`로 trait를 켠다.
- 참고: Paperlogy 7Bold/8ExtraBold는 OS/2 fsSelection·macStyle의 bold 비트가 없다(usWeightClass 700/800만 있음). 증상이 재현된다는 것은
  CoreText가 이 글꼴들에 bold trait를 보고한다는 뜻이다(빌드 환경이 없어 실기 확인은 못 함). 수정은 같은 `fontIsBold` 판정을 양쪽에
  써서 CoreText가 어느 쪽으로 판정하든 일관되게 동작한다.

## 구분 가능 여부와 선택
- 문단 스타일 attribute(`.sermonParagraphStyle`)는 편집 중 모든 문단에 붙어 있어 **이전 스타일을 알 수 있다**.
- 이전 프리셋 글꼴이 굵지 않은데 굵은 글자 → 사용자가 넣은 굵게(굵게 버튼·강조1) → 보존.
- 이전 프리셋 글꼴 자체가 굵음 → 그 문단의 굵게는 프리셋 굵기와 구분할 수 없음 → 새 스타일 기준으로 초기화.
- 이는 기존 `SermonEmphasisEditor.clear`의 규칙("프리셋 글꼴이 굵지 않을 때만 굵게를 끈다")과 같은 기준이다.
- 즉 구분 가능한 경우는 사용자 서식을 남기고, 구분 불가능한 경우(굵은 제목 스타일)는 선택지 (a)로 처리한다.
  (b) "문단 전체가 굵을 때만 초기화"는 제목 문단 안 강조1 같은 일부 구간이 섞이면 결국 같은 판정이 되고, 일부만 굵은 이유가
  프리셋 때문인지 알 수 없어 채택하지 않았다.
- 기울임·밑줄·배경은 건드리지 않는다. 글자색 처리는 기존 그대로다(아래 "기존 동작" 참고).

## 변경 (JBCHBibleResearch/Views/Sermon/SermonParagraphEditor.swift)
1. `applyStyle(... dropsStyleBold: Bool = false)` 추가. true면 attribute를 덮어쓰기 전에 `.sermonParagraphStyle` 구간별로 이전 스타일을 읽고
   (없거나 알 수 없으면 그 문단 첫 글자의 스타일, 그것도 없을 때만 `.body` — `export`·`currentParagraphStyle`과 같은 규칙. 검토 B 반영), 이전 프리셋이 굵으면 그 구간의 굵게 trait를 넘기지 않는다. 구간별 처리라 여러 문단 선택에서도
   문단마다 판정한다.
2. `fontPreservingBoldItalic(... dropBold: Bool = false)` 추가(iOS·macOS 양쪽).
3. iOS·macOS `applyParagraphStyle`만 `dropsStyleBold: true`로 호출. 불러오기(`apply`), 말씀구절 삽입, 마인드맵 내보내기,
   `buildVerseQuoteDocument`는 기본값 false → 동작 변화 없음(RTF에 스타일 attribute가 없어 이전 스타일을 알 수 없으므로 보존이 맞다).

## 엣지 케이스
- 여러 문단 선택: 스타일 구간별로 판정. 대주제+본문(사용자 굵게) 동시 선택 → 대주제 굵기만 빠지고 본문의 사용자 굵게는 남는다.
- 커서만 있음 / 빈 문단 / 빈 문서: 범위 길이 0이면 글꼴 처리 없음, `applyTypingAttributes`가 이미 `.font = 새 프리셋`으로 덮어쓰므로 타이핑 굵기도 정상.
- 본문 → 본문 재적용: 이전 프리셋(본문)이 굵지 않으므로 사용자 굵게 보존(변화 없음).
- 말씀구절: 설교 본문에 링크 attribute는 없다(구절 연결은 `SermonVerseReference.paragraphIndex`로 별도 저장). 글꼴 외 속성은 건드리지 않는다.
- th/ru/vi: `languageAdjustedDefaultFontName`이 바꾼 프리셋(IBMPlexSansThai-Bold, Inter-ExtraBold/Bold, Gentium-Regular, NotoSerifThai-Regular 등)도
  `settings.sermonPlatformFont(for:)`로 같은 경로를 탄다. IBMPlexSansThai-Bold·Inter-Bold는 fsSelection bold라 확실히 굵게로 판정되어 제거된다.
- 굵은 제목 문단 안에 사용자가 넣은 굵게/강조1은 본문으로 바꿀 때 사라진다(구분 불가 — 의도된 (a) 처리).
- 에디터가 열린 채 설정에서 제목 프리셋 글꼴을 굵지 않은 글꼴로 바꾼 직후에는, 화면의 옛 굵은 글꼴을 사용자 굵게로 본다(에디터가 설정 변경을
  실시간 반영하지 않는 기존 구조 탓, 드묾).

## 저장·동기화·실행 취소
- 저장 형식 변화 없음: 결과는 표준 `.font`이므로 RTF(`RichTextCodec.encode`)에 그대로 저장되고 `paragraphStyles`·스냅샷 형식도 그대로다. CloudKit 필드 추가 없음.
- 실행 취소: 스타일 적용은 원래부터 `textStorage`를 직접 고치고 undo를 등록하지 않는다(소스에 `registerUndo` 없음). 이번 변경으로 달라지지 않는다.

## 기존 동작(이번 범위 밖, 확인만)
- pill 경로는 `previousSnapshot`을 넘기지 않아 글자색이 항상 새 프리셋 색으로 바뀐다 → 강조1(와인색)·강조3(파란색)·사용자 지정 색은 스타일 변경 시 사라진다
  (밑줄·형광펜 배경은 남는다).
- 여러 문단 선택 시 줄간격/목록은 첫 문단 값(`extras(at: paragraphRange.location)`)으로 모든 문단이 맞춰진다.
- 스타일 변경 undo 미지원.

## 문구
새 문구 없음(Localizable.xcstrings 변경 없음).

## 검증
- 정적 분석만(빌드 도구 없음). `git apply --check`를 Mac 현재 파일 사본에 통과, 적용 결과가 수정본과 동일함을 확인.
- 실기 테스트 권장: ① 대주제/중주제/소주제 → 본문: 굵게 해제 ② 본문에서 일부 단어 굵게 → 소주제 → 본문: 그 단어만 굵게 유지?
  (소주제 프리셋이 굵게로 판정되면 해제됨 — 의도) ③ 본문 일부 굵게 → 인용: 굵게 유지 ④ 대주제+본문 여러 문단 선택 → 본문 ⑤ 대주제 → 중주제: 중주제 프리셋 굵기(Paperlogy-7Bold)로 바뀌고 ExtraBold/과도한 굵기가 남지 않는지
  ⑥ ru/th 언어에서 ① 반복 ⑦ 저장 후 다시 열기·다른 기기 동기화 후 모양 동일.
