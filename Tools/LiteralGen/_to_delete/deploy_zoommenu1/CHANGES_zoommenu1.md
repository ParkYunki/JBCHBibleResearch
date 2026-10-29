# zoommenu1 (2026-10-29)

기준: Mac 현재 파일(md5 확인: VerseSheetChrome.swift a8803b31…, VerseZoomView.swift ff0fd3a1…).
`zoommenu1.diff`는 저장소 루트에서 `git apply` (경로 `JBCHBibleResearch/...`). 사본에 `git apply --check` 통과, 적용 결과가 수정본과 바이트 단위로 같음.
수정본: `/home/claude/integ/zoommenu1/JBCHBibleResearch/Views/Bible/{VerseSheetChrome,VerseZoomView}.swift`
xcstrings는 고치지 않음.

## 증상 (사용자 보고, iPhone 러시아어)
성경 탭 → 구절 선택 → 하단 메뉴 "메모하기"(`VerseZoomView`) 하단 도구 줄: 이름 한 줄 말줄임, 형광펜 색 점이 화면 왼쪽 밖으로 넘침, 도구 간격 불규칙.

## 원인 (소스 근거)
- `VerseLayerFooter`: `HStack(alignment: .top, spacing: 10/16)`에 도구 4개. 러시아어 이상 폭 합계 ≈ 492pt > 화면 402pt.
- `VerseLayerToolCaption`의 이름: `.lineLimit(1).minimumScaleFactor(0.8)` → 0.8배로 줄인 뒤에도 말줄임("Личное размышле…").
- 형광펜 상자: `verseLayerBox()` = `.frame(minWidth: 44, minHeight: 44)`. 최소값만 준 유연 프레임은 폭을 max(44, min(자식 폭, 제안 폭))으로 보고하므로,
  `HStack`이 몫(약 100pt)을 제안하면 상자가 100pt로 줄고 안의 색 점 줄(5×21 + 4×6 + 16 = 145pt, 고정 크기)은 상자 양옆으로 넘친다.
  줄은 왼쪽 끝(10pt)부터 놓이므로 노란 점이 화면 밖으로 나감. 스크린샷 실측(상자 약 10~116pt, 점 약 -8~127pt)과 맞음.
- 간격 불규칙: 각 도구 폭 = 줄어든 이름 폭이라 제각각.

## 수정
### 1. 공용 이름 라벨 `VerseLayerWrappedTitle` + `VerseLayerBalancedTitleLayout` (VerseSheetChrome.swift, iOS·macOS 공용)
- 한 줄 폭이 `singleLineMaxWidth` 이하이면 한 줄 그대로.
- 넘으면 공백 또는 글자 사이 하이픈 뒤(UAX #14에서 줄바꿈이 허용되는 자리)에서 나눈 두 줄 중 긴 줄이 가장 짧아지는 폭(+1pt, 한 줄 폭 이하)을 쓴다.
  폭은 숨긴 `Text`(앞부분·뒷부분)를 같은 글꼴로 재서 정하므로 Dynamic Type을 따르고, 가장 긴 단어보다 좁아지지 않아 단어 중간에서 끊기지 않는다.
  그 폭에서 Text가 앞 줄부터 채워도(greedy) 두 줄 안에 들어가는 것이 보장된다.
- 축소 대신 말줄임 대신 "폭을 넓힘"을 택한 이유: 두 줄 + 축소는 SwiftUI Text가 긴 단어를 글자 단위로 끊는다(상단 "Прос/мот…"가 그 사례). 말줄임은 뜻이 사라짐.
- 공백이 없는 이름(th·ja·zh)은 한 줄 폭 그대로(나눌 자리를 알 수 없음).
- 제안 폭과 상관없이 같은 폭을 보고(`fixedSize`와 같은 동작)해서 `ViewThatFits`의 이상 크기 측정과 실제 배치가 일치.
- 숨긴 측정용 Text는 `.hidden().accessibilityHidden(true)`.

### 2. iOS/iPadOS 도구 줄 (VerseZoomView.swift `actionBar`)
- `ViewThatFits(in: .horizontal)` 후보 순서
  1) 예전 배치 그대로(이름 한 줄, 기존 `Text` 경로)
  2) 한 줄, 이름은 `VerseLayerWrappedTitle(singleLineMaxWidth: 44)` (44pt 상자보다 넓은 이름만 두 줄)
  3) 두 줄 배치: 형광펜 상자 한 줄, 아래 줄에 메모·개인 묵상·관주(이름은 2와 같음)
- 형광펜 상자에 `.fixedSize()` → 어떤 배치에서도 145pt(아이패드 172pt) 아래로 줄지 않음.
- 도구 줄은 계속 `.top` 정렬: 상자(아이콘)는 모두 44pt라 이름이 두 줄인 도구가 있어도 아이콘 높이가 같다.
- 도구 간격 값은 `VerseLayerToolMetrics.spacing`(아이폰 10 / 아이패드 16)으로 빼서 `VerseLayerFooter`와 함께 씀(값 동일).
- `VerseLayerToolCaption`에 `wrapsTitle: Bool = false` 추가. false 경로는 예전 코드 그대로.
- 도구 버튼 3개는 `layerTools(wrapsTitles:)`, 형광펜은 `highlighterTool`로 옮김(동작·접근성 라벨·`disabled`/`opacity` 그대로).

### 3. macOS 도구 타일 (VerseZoomView.swift `toolTile`, VerseSheetChrome.swift `VerseToolTileBody`)
- 이름: `Text(title)`(줄 수 제한 없음, 72pt 고정 폭) → `VerseLayerWrappedTitle(singleLineMaxWidth: 60)`.
- 타일: `.frame(width: 72, height: 56)` → `.padding(.horizontal, 6).frame(minWidth: 72).frame(height: 56).fixedSize()`.
  60pt 이하 이름(한국어 전부)은 예전과 같은 72×56. 러시아어는 92/96pt로 넓어짐. 줄 전체 최대 ≈ 473pt < 시트 최소 폭 525pt.
- 높이: 아이콘(19pt) + 4 + 11.5pt 두 줄(≈ 27pt) ≈ 51pt ≤ 56.

## 한국어
- 아이폰 세로(375pt 이상)·가로·아이패드·맥 모두 1번 후보(예전 배치) 또는 예전 72pt 타일 그대로. 바뀌는 것은 형광펜 상자의 `fixedSize()`뿐이며, 이는 상자가 이상 폭보다 줄어들 때만 효과가 있다(한국어는 그런 경우 없음).
- 예외: 폭 330pt 미만(아이폰 디스플레이 확대 모드 320pt, 아이패드 Slide Over)은 예전에도 한국어 줄이 넘쳤던 폭이고, 이제 3번(두 줄 배치)으로 바뀐다.

## 17개 언어 라벨과 추정 폭 (iOS `.caption` 12pt 기준, Inter로 재고 스크린샷 실측으로 0.97 보정, th는 Loma, CJK는 Noto Sans CJK)
A = 예전 한 줄 배치 필요 폭, B = 이름 두 줄 배치 필요 폭(좌우 여백 20 + 간격 30 + 형광펜 145 포함). 선택 = 아이폰 375 / 402 / 440pt에서 고르는 후보. Mac = 메모/개인 묵상/관주 타일 폭(² = 두 줄).

| 언어 | 형광펜 | 메모 | 개인 묵상 | 관주 | A | B | 선택 375/402/440 | Mac |
|---|---|---|---|---|---|---|---|---|
| ko | 형광펜 (33) | 메모 (22) | 개인 묵상 (47) | 관주 (22) | 330 | 327 | 1/1/1 | 72/72/72 |
| de | Hervorhebung (80) | Notizen (42) | Persönliche Andacht (114) | Querverweise (77) | 429 | 382 | 3/2/1 | 72/76²/86 |
| en, en-CA | Highlight (49) | Notes (32) | Personal Devotion (100) | Cross-References (100) | 439 | 353 | 2/2/1 | 72/72²/74² |
| es, es-MX | Resaltado (54) | Notas (32) | Devocional personal (112) | Referencias cruzadas (119) | 470 | 367 | 2/2/2 | 72/73²/77² |
| fil | Highlighter (60) | Mga Tala (50) | Personal na Debosyon (123) | Mga Cross-Reference (121) | 489 | 371 | 2/2/2 | 72/76²/76² |
| fr, fr-CA | Surlignage (59) | Notes (32) | Méditation personnelle (126) | Références croisées (112) | 477 | 369 | 2/2/2 | 72/76²/74² |
| id | Stabilo (38) | Catatan (43) | Renungan Pribadi (97) | Referensi Silang (89) | 425 | 349 | 2/2/1 | 72/72²/72² |
| it | Evidenziatore (75) | Note (26) | Meditazione personale (125) | Riferimenti incrociati (112) | 477 | 368 | 2/2/2 | 72/79²/72² |
| ja | ハイライト (60) | メモ (24) | 個人の黙想 (60) | 引照 (24) | 343 | 343 | 1/1/1 | 72/72/72 |
| pt-BR | Marca-texto (67) | Anotações (59) | Devocional pessoal (107) | Referências cruzadas (119) | 480 | 382 | 3/2/2 | 72/73²/77² |
| ru | Маркер (44) | Заметки (48) | Личное размышление (127) | Параллельные места (122) | 492 | 411 | 3/3/2 | 72/92²/96² |
| th | ปากกาไฮไลต์ (70) | บันทึก (31) | การเฝ้าเดี่ยวส่วนตัว (101) | ข้ออ้างอิงโยง (68) | 407 | 407 | 3/3/1 | 72/108/76 |
| vi | Bút tô sáng (62) | Ghi chú (42) | Tĩnh nguyện cá nhân (117) | Tham chiếu chéo (95) | 451 | 372 | 2/2/2 | 72/81²/72² |
| zh-Hans | 荧光笔 (36) | 笔记 (24) | 个人灵修 (48) | 串珠 (24) | 331 | 331 | 1/1/1 | 72/72/72 |
| zh-Hant | 螢光筆 (36) | 筆記 (24) | 個人靈修 (48) | 串珠 (24) | 331 | 331 | 1/1/1 | 72/72/72 |

- 가장 긴 두 줄 이름: ru "Параллельные / места" 86pt, "Личное / размышление" 82pt. 두 줄에 모두 들어감.
- 3번(두 줄 배치) 아래 줄 최대 폭: ru 256pt(아이폰) / 268pt(아이패드) → 320pt 폭에서도 들어감. 형광펜 줄은 145/172pt.
- 아이폰 가로·아이패드 시트(폭 540pt 이상): 모든 언어 1번 또는 2번.

## 번역 축소 제안 (적용 안 함)
| 언어 | 키 | 현재 | 제안 | 효과 |
|---|---|---|---|---|
| ru | 관주 | Параллельные места | Параллели (63pt) | 402pt 아이폰에서 3번 → 2번(B 411 → 388) |
| ru | 뷰어 | Просмотрщик | Просмотр | 상단 버튼 폭 감소(아래 참고) |
| ru | 원문 정보 | Текст оригинала | Оригинал | 상단 버튼 폭 감소 |
| th | 개인 묵상 | การเฝ้าเดี่ยวส่วนตัว | เฝ้าเดี่ยว (44pt) | 공백이 없어 두 줄로 못 나눔. 402pt에서 3번 → 1번 가능 |

## 상단 버튼("원문 정보", "뷰어/편집") — 원인이 달라 고치지 않음
- `VerseLayerStrip`(VerseSheetChrome.swift)의 `HStack`에서 버튼이 눌리고, `BibleBarButtonStyle`(BibleBarControls.swift, 성경 조회 막대 공용)은 높이 40pt 고정에
  `lineLimit`이 없어 이름이 15pt 두 줄로 접히며 단어 중간에서 끊기고 말줄임된다("Прос/мот…").
- ru 필요 폭 ≈ 513pt(번역을 줄여도 ≈ 433pt) > 402pt라 번역만으로는 안 된다. 제안: `VerseLayerStrip` 오른쪽 버튼에 `ViewThatFits`로 "아이콘만" 후보를 두기(접근성 라벨 유지).
  `BibleBarButtonStyle`은 공용이라 이번에는 손대지 않음.

## 확인할 테스트
- ko: 아이폰 SE(375)·16 Pro(402)·Pro Max(440) 세로/가로, 아이패드, 맥 — 예전과 픽셀 단위로 같은지.
- ru: 375·402 → 두 줄 배치, 440 → 한 줄 + 이름 두 줄. 노란 점이 상자 안·화면 안에 있는지.
- de·fr·vi·en: 375에서 en/es/fr/it/vi/id/fil = 한 줄 + 이름 두 줄, de/pt-BR = 두 줄 배치.
- en "Cross-References" → "Cross-/References"로 하이픈 뒤에서 나뉘는지(글자 중간 끊김 없음).
- 회전·Dynamic Type 변경 시 후보가 바뀌어도 선택 모드(`isSelecting`)·흐림 처리 그대로인지, 버튼 동작(형광펜/메모/개인 묵상/관주) 그대로인지.
- 아주 큰 접근성 글자(AX3 이상): 3번 배치에서도 이름 폭이 넓어져 넘칠 수 있음(남은 위험). 형광펜 상자는 고정 크기라 줄 폭 ≥ 192pt면 넘치지 않음.
- VoiceOver: 도구 버튼은 예전과 같은 라벨("메모" 등), 숨긴 측정용 글자는 읽히지 않아야 함(맥 타일 포함).
