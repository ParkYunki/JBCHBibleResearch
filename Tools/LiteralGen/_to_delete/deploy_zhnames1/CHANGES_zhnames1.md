# zhnames1 — 중국어 간체/번체 fullNames 표준 표기 정리 (2026-10-29)

대상: `JBCHBibleResearch/Services/BookNameTable.swift` (fullNames와 주석만 바꿈. shortNames는 그대로)
diff: `/home/claude/integ/zhnames1.diff` (Mac 현재 파일 사본에서 `git apply --check` 통과, 적용 결과가 수정본과 같음)

## 기준
- 번들 sqlite(`Bible_CUV1919.sqlite`, `Bible_CUV1919S.sqlite`)에는 `BibleVerses` 테이블만 있고 책 이름 테이블이나 머리글이 없다.
- CUV1919 원본 `cuvbible.zip`(CCEL): 각 권 HTML에는 제목이 없고, `index.html` 목차에만 책 이름이 있다.
- 대조본 `cmn-cu89t_usfm.zip`, `cmn-cu89s_usfm.zip`: 66권 모두 `\h`, `\toc1`, `\toc2`, `\mt1` 값이 같다. 이것을 기준으로 삼았다.
- 信望愛 https://bible.fhl.net/new/listall.html : 번체 66권이 cu89t와 모두 같다.

## 변경 (bookId, 이전, 이후, 근거)
| bookId | 간체 이전 → 이후 | 번체 이전 → 이후 | 근거 |
|---|---|---|---|
| 1 | 创世纪 → 创世记 | 創世紀 → 創世記 | cu89s/cu89t `\toc1`, FHL |
| 50 | 腓利比书 → 腓立比书 | 腓利比書 → 腓立比書 | cu89s/cu89t, FHL, CCEL 목차 |
| 62 | 约翰壹书 → 约翰一书 | 約翰壹書 → 約翰一書 | cu89s/cu89t, FHL, CCEL 목차 |
| 63 | 约翰贰书 → 约翰二书 | 約翰貳書 → 約翰二書 | 위와 같음 |
| 64 | 约翰参书 → 约翰三书 | 約翰參書 → 約翰三書 | 위와 같음 |

나머지 61권은 간체·번체 모두 이미 기준과 같다.

1919 계열과의 차이: CUV1919 원본 CCEL 목차에는 창세기가 "創世紀"로 되어 있다(나머지 4권은 현대 표기와 같다). 1919 원판 인쇄본의 표기는 소스로 확인하지 못했다. 작업 지시에 따라 현대 일반 표기 "創世記/创世记"를 썼다.

## 영향
- 표시: `Book.displayName`(BibleTopBar, BookChapterPicker, ChapterRelatedContentPanel, BibleReadingView 이전/다음 장, 북마크·읽기 기록, 사이드바, 검색 결과·메모·요약·노트, 인물/지명/주제 상세, 개요(OutlineTree/BulkEdit/QuickView/Slide), 말씀노트, 문서, 관주 대상 선택, VerseRelatedSheet), `BookNameTableProvider.displayName`(CUV 열의 `localizedBookChapterLabel`, VerseZoomView 제목). CUV 열 라벨은 한국어 앱에서도 바뀐다.
- 입력: booklabel1 `matchBookPrefix`를 Python으로 흉내 내 확인했다. 간체·번체 모두 66권의 "전체이름+1", "전체이름 3:16", "약칭+1" 입력이 자기 책으로 해석된다. 이름끼리, 또 약칭과 중복되는 것은 없다. 그리드 검색에서 "世纪", "利比", "壹"은 이제 결과가 없고, "世记", "立比", "一书"는 해당 권 하나만 나온다.
- 예전 표기 입력("创世纪1", "腓利比书1", "约翰壹书1" 등)은 이제 인식되지 않는다(nil이 나오고 오류 알림이 뜬다). 약칭("创1", "腓1", "约一1")은 계속 된다. 별칭은 추가하지 않았다(기본값 따름). BulkCrossReferenceParser에 붙여 넣는 텍스트도 같은 규칙을 따른다.
- 저장 데이터: SermonVerseReferencePicker가 설교 말씀구절 문단 끝에 "(创世纪 1:1)"처럼 `displayName`을 문자열로 넣는다. 이미 저장된 설교는 예전 표기를 그대로 갖고, 새로 넣는 구절만 "创世记"가 된다. 좌표는 `SermonVerseReference`에 따로 저장되므로 연결은 유지된다. 메모 공유 파일 이름(`shareDisplayName`)도 내보낼 때마다 새 표기가 된다. 복사(`BibleVerseCopyFormatter`), 저장되는 관주 라벨, 참조 추출은 `nameKo`/`abbreviation`을 쓰므로 영향이 없다.

## 이번 범위 밖 (남은 일)
- 다른 파일 주석의 예시 "创世纪1"/"创世纪"가 이제 맞지 않는다: AppLanguage.swift 82·117행, BooksProvider.swift 65·120행, Book+Search.swift 47행, BookChapterPicker.swift 283행. 이 파일들에는 Mac에서 아직 커밋하지 않은 변경이 있어서 건드리지 않았다.
- 중국어 참고자료 시드의 본문에 예전 표기가 남아 있다. `ReferenceDataSource/i18n/zh/PersonSeed.json`에 "创世纪" 752회, PlaceSeed에 117회, TribeSeed에 9회, `Resources/OutlineSeed_zh.json`에 줄 단위로 15곳이 있고 "腓利比书", "约翰壹书"도 있다. 이 본문은 파싱하지 않으므로 기능에는 영향이 없다. 다만 화면에서 책 이름표와 표기가 서로 다르게 보인다.
