# 판정: A 없음 → 반영 가능

> **2차 독립 리뷰 범위:** 제공된 `code_review_01.diff` 11개 파일(1,910줄) 및 `code_review_01_instructions.md`. 1차 리뷰가 이미 다룬 메모/이동 동시 입력, VoiceOver 일반 점검, LazyVGrid 미생성 항목 스크롤, iPhone 가장자리 스와이프, 좁은 카드 줄 넘침은 중복 기재하지 않았다. 줄 번호는 각 파일 **수정본(+쪽)** 기준이다. 원본 프로젝트와 번들 DB 및 Xcode 빌드 환경은 제공되지 않았으므로 아래 B 항목을 실제 오류로 단정하지 않는다.

## A: 확실한 오류 (수정안 포함)

| # | 파일:줄 | 문제 | 근거 | 수정안 |
|---|---|---|---|---|
| — | — | 제공된 diff만으로 확정할 수 있는 신규 컴파일 오류·크래시·기능 오동작은 발견하지 못함 | SQLite 문장 정리(`defer`), 결과 수신 후 취소 확인, 별도 백그라운드 연결, Unicode scalar 경계 확인이 코드상 반영됨 | — |

## B: 빌드·기기에서 확인 필요

| # | 파일:줄 | 내용 | 확인 방법 |
|---|---|---|---|
| B1 | `OriginalTextStore.swift:52` | 기존 절 조회 쿼리에 `rowid ASC`가 추가됐다. **`original_words`가 `WITHOUT ROWID` 테이블이면** `no such column: rowid`로 모든 `words(...)` 조회가 실패한다. diff에는 이 테이블의 실제 `CREATE TABLE` 정의가 없어 확인 필요. | 배포 `OriginalText.sqlite`에서 `SELECT sql FROM sqlite_master WHERE name='original_words';`를 확인하고, `SELECT ... FROM original_words ... ORDER BY word_order ASC, rowid ASC LIMIT 1`을 직접 실행. `WITHOUT ROWID`라면 고유 기본 키 컬럼 등 실제 존재하는 안정적인 정렬 키로 대체. |
| B2 | `OriginalTextInfoView.swift:232` | `.navigationDestination(item: $occurrenceWord)`의 `item`은 `Hashable` 적합성을 요구한다. `OriginalWordInfo`의 전체 타입 선언은 diff에 없어 `Hashable` 적합 여부를 판단할 수 없다. | iOS 18 대상으로 빌드하여 해당 오버로드의 제네릭 제약을 확인. 미적합하다면 식별 가능한 `Hashable` 경로 값(예: Strong 번호+단어 위치)으로 push 상태를 바꾸거나 타입 적합성을 검토. |
| B3 | `OriginalWordOccurrencesView.swift:328–341`, `OriginalTextLookupService.swift:101–133` | 앱 타깃 기본 MainActor 격리와 패키지 타깃 비격리가 혼합되어 있다. `nonisolated` 메서드 안에서 사용하는 `BibleVerseRef` 생성/해시, `BibleReferenceStore` 호출, `OriginalTextStore` 호출이 실제 선언의 격리/`Sendable` 요구와 충돌하지 않는지는 diff만으로 확정할 수 없다. | 지정된 Swift 5 및 세 빌드 설정에서 iOS·macOS 빌드. 해당 함수의 actor-isolation 진단 및 detached 캡처 진단을 확인; 패키지 소스 타입 선언의 격리도 함께 확인. |
| B4 | `BibleReadingViewModel.swift:293–294`, `OriginalWordOccurrencesView.swift:328–341` | 본문 미리보기는 기존 `storeCache`의 경로를 가져와 **새 SQLite 연결**로 번역본 전체를 읽는다. 사용자 추가 번역본이 보안 범위 URL 또는 외부 파일 접근 권한에 의존한다면, 경로 문자열만 넘겨 새 연결을 여는 방식이 실제 배포 환경에서 접근 가능한지 확인 필요. | 앱 번들 KRV뿐 아니라 Files에서 추가한 외부 번역본, 앱 재실행 후 재열기, macOS 샌드박스 환경에서 '쓰인 구절' 미리보기가 나타나는지 테스트. 실패 로그(`본문 미리보기 조회 실패`)와 파일 접근 권한을 확인. |
| B5 | `OriginalTextInfoView.swift:173–207`, `OriginalTextInfoView.swift:978–981` | macOS에서 쓰인 구절 화면을 띄운 동안에도 원문 정보 시트의 공통 하단 `VerseSheetFooter`가 남는다. 이전/다음 절을 누르면 `loadWords()`가 `occurrenceWord=nil`로 바꾸어 목록이 닫히도록 되어 있으나, 사용자가 원하는 겹침 화면 내 키보드 동작인지 불명확하다. | macOS 시트에서 쓰인 구절 화면을 연 상태로 Esc, 하단 ‹/›, 키보드 단축키를 각각 사용하여 기대한 화면이 닫히는지 및 현재 절이 바뀌는지 확인. 의도와 다르면 목록 표시 중 이전/다음 절 컨트롤을 숨기거나 비활성화. |
| B6 | `OriginalWordOccurrencesView.swift:93`, `OriginalWordOccurrencesView.swift:287–324` | 목록 로드 작업의 식별자는 `word.strongCode`뿐이다. `previewSource`(번역본 파일·코드)가 목록 화면 생존 중 바뀌어도 `.task`가 **자동 재실행되지 않는다**. 실제로 부모 화면의 번역본 선택을 목록 화면이 열린 채 바꿀 수 있는 구조인지는 diff상 불명확하다. | iPadOS 다중 창 및 macOS 시트에서 목록을 열린 상태로 번역본 선택/창 상태 변경이 가능한지 확인. 가능한 경우 미리보기가 이전 번역본으로 남는지 검사. 해당 전환이 허용되면 `.task(id:)`에 미리보기 소스 ID도 포함. |
| B7 | `OriginalWordOccurrencesView.swift:328–341` | `allVerses(versionCode:)` 전체 결과를 한 번 순회하는 구현은 측정 근거가 있지만, 번역본 파일이 매우 크거나 `allVerses`가 전체 행을 배열로 물질화하는 경우 순간 메모리 피크가 커질 수 있다. 실제 함수 구현은 diff에 없다. | iOS 실제 기기에서 용량이 가장 큰 사용자 번역본 및 G3588(7,061절) 목록을 사용해 Instruments Allocations/Memory Gauge로 피크 사용량과 지연을 측정. |

## C: 참고

| # | 파일:줄 | 내용 |
|---|---|---|
| C1 | `OriginalTextInfoView.swift:1007–1015`, `OriginalWordOccurrencesView.swift:292–324` | 두 조회 모두 `Task.detached` 완료를 `.value`로 기다린 뒤 `Task.isCancelled`를 확인하므로 **취소된 UI 작업의 결과 적용은 막는다**. 다만 기다리는 detached 작업 자체를 취소하지는 않아, 빠르게 절/단어를 바꾸면 이전 DB 스캔이 끝날 때까지 지속될 수 있다. 이는 확정 오류가 아니라 부하 관찰 사항이다. |
| C2 | `OriginalWordOccurrencesView.swift:65–68`, `OriginalWordOccurrencesView.swift:175–180` | 책 칩 변경 시 `filteredOccurrences`가 최대 7,061개 배열을 새로 만들지만 표시 노드는 `LazyVStack`으로 지연 생성된다. diff만으로 체감 성능 문제를 확정할 근거는 없다. |
| C3 | `LiteralCommentaryService.swift:48–70` | `start`의 음수 및 상한을 검사하고, `literalScalars.count - phraseScalars.count` 조건으로 합산 오버플로를 피한다. `phrase`가 더 길면 조건이 거짓이 되어 슬라이스 인덱싱에 도달하지 않는다. 유효한 Unicode scalar 오프셋 기준으로 안전하다. |
| C4 | `OriginalTextStore.swift:154–199` | `(책, 장, 절, 형태)` 단위 SQL 그룹화 후 같은 절의 형태를 합치는 방식은 `group_concat`의 쉼표 충돌을 피한다. 형태를 원어 등장순으로 유지하는 것은 `ORDER BY ..., MIN(word_order)`에 의존하므로, 동일 `word_order`가 여러 형태에 존재할 때 둘 사이의 상대순서는 정의되지 않는다. 실제 중복 데이터가 해당 Strong 조회 결과에 있는지 확인하기 전에는 오류로 단정할 수 없다. |
| C5 | `Localizable.xcstrings:76009–76055` | 새 절 수 문자열의 영어 `one/other` 복수형과 `%lld` 값이 대응한다. 추가된 `%@` 항목도 사용처의 문자열 보간과 일치한다. 제공된 diff 범위에서 형식 지정자 불일치는 보이지 않는다. |

**종합:** 확인 가능한 A등급 오류는 없다. 특히 **B1(실제 DB 스키마)**과 **B2·B3(실제 앱 빌드)**는 반영 전에 우선 확인할 가치가 크다. 나머지는 외부 번역본과 macOS 화면 동작을 중심으로 한 기기 검증 항목이다.
