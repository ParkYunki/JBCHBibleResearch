# CHANGES_fontdef1 — 성경 본문 기본 글꼴을 앱 언어별로 + CJK 글꼴 + 확대보기 줄바꿈 단위 (2026-10-29)

기준은 literata1·versewrap1이 들어간 Mac 현재 파일이다. `fontdef1_base/` 사본과 Mac 파일의 sha1이 5개 모두 같다.

| 파일 | sha1 |
|---|---|
| BundledFontRegistrar.swift | c03f6eb0… |
| UserSettingsStore.swift | fa9185b0… |
| SettingsView.swift | e6fb3837… |
| VerseZoomView.swift | 22f2830f… |
| Localizable.xcstrings | f632b9dd… |

- diff: `/home/claude/integ/fontdef1.diff`(349줄). 사본에 `git apply --check`가 통과했고, 적용 결과가 `fontdef1/`과 바이트 단위로 같다. xcstrings JSON 파싱도 통과했다.
  - 1차본(언어별 기본값만)은 Mac 저장소에서도 `--check`가 통과했다. 최종본은 Mac 파일과 sha1이 같은 사본으로 확인했다.
- 글꼴 파일: `/mnt/user-data/outputs/deploy_fontdef1/Fonts/` → Mac `JBCHBibleResearch/JBCHBibleResearch/Fonts/`
- Mac 파일은 바꾸지 않았다. 빌드는 하지 못했다(이 환경에 Swift가 없다).

## A. 기본값 (`BundledFonts.bibleDefaultPostScriptName`, `AppLanguage.baseCode` 기준)
| baseCode | 기본값 |
|---|---|
| vi, ru, en, es, fr, de, it, pt, id, fil | Literata-Regular |
| th | NotoSerifThai-Regular |
| ja | ShipporiMincho-Regular |
| zh(zh-Hans·zh-Hant 모두) | LXGWWenKaiTC-Regular |
| ko, 그 밖 | Paperlogy-4Regular(그대로) |

- 사용자 선택값을 기본값과 구분하는 방식(전 언어 공통):
  - `init`에서 `defaults.string(forKey: "settings.bible.fontName") ?? 기본값`을 쓴다. 키가 없을 때만 기본값이다.
  - 저장은 `didSet`에서만 일어난다. init 대입은 저장하지 않는다.
  - 예전에 Paperlogy를 직접 골라 둔 사용자는 그대로 Paperlogy다.
  - 이 값을 쓰는 곳은 설정 Picker 하나뿐이다. `removeObject`나 "기본값으로 되돌리기"는 없다. KVS 동기화 대상도 아니다.
- `AppLanguage.code`는 `preferredLocalizations.first`라서 값은 로컬라이제이션 18개 가운데 하나다. 없는 언어는 developmentRegion인 ko로 간다. "tl"은 로컬라이제이션에 없어 넣지 않았다.

## B. CJK 글꼴
### 넣은 파일 (google/fonts main, raw.githubusercontent.com, 서브셋·수정 없음)
| 파일 | 바이트 | gzip -9 | PostScript(ID 6) | wght | fsType |
|---|---|---|---|---|---|
| ShipporiMincho-Regular.ttf | 8,677,284 | 4,523,428 | ShipporiMincho-Regular | 400 | 0 |
| ShipporiMincho-SemiBold.ttf | 8,650,032 | 4,597,863 | ShipporiMincho-SemiBold | 600 | 0 |
| ShipporiMincho-Bold.ttf | 8,563,788 | 4,657,341 | ShipporiMincho-Bold | 700 | 0 |
| LXGWWenKaiTC-Regular.ttf | 13,110,528 | 7,514,710 | LXGWWenKaiTC-Regular | 400 | 0 |
| LXGWWenKaiTC-Bold.ttf | 12,881,104 | 7,634,965 | LXGWWenKaiTC-Bold | 700 | 0 |
| OFL-ShipporiMincho.txt | 4,399 | | | | |
| OFL-LXGWWenKaiTC.txt | 4,390 | | | | |

- 합계 51,891,525 bytes(약 49.5 MiB, 압축 전). 7개를 `zip -9`로 묶으면 28,933,225 bytes(약 27.6 MiB)다. IPA 다운로드 크기는 약 +28 MB로 추정한다(App Store 압축 방식은 확인하지 않았다).
- 설치 크기는 Fonts 폴더 기준 약 46 MiB에서 약 96 MiB가 된다.
- 30MB를 넘는 파일은 없다(가장 큰 파일이 13.1MB). 그래서 따로 반영할 방법은 필요 없다.
- sha256:
  - ShipporiMincho: Regular 769b5269…70b2, SemiBold bc792554…4d2d, Bold 63bc4edd…c286
  - LXGWWenKaiTC: Regular 4fcc5aec…8d95, Bold 5c9feadf…7f23
  - OFL: Shippori 41fba056…7174, LXGW 4fff27d3…c7174
  - 받아 둔 Regular 2종과 바이트 단위로 같다.
- 상류: METADATA.pb 기준으로 Shippori는 fontdasu/ShipporiMincho 커밋 63431fee, LXGW는 aaronbell/LxgwWenkaiTC 커밋 a5cf76f5다. google/fonts 커밋 해시는 GitHub API 응답이 비어 기록하지 못했다.
- 이름 규칙:
  - 파일 이름과 PostScript 이름(ID 6)이 5개 모두 같다. 그래서 등록 목록(`registeredPostScriptNames` = 파일 이름) 규칙에 맞고, 이름을 고칠 필요가 없었다.
  - Shippori SemiBold는 ID1이 "Shippori Mincho", ID2가 "SemiBold"이고 ID16·17이 있다. Bold는 fsSelection BOLD와 macStyle 1이 설정돼 있다.
- OFL 두 파일에는 Reserved Font Name 선언이 없다. 원본 그대로이므로 고지는 "수정 없이"로 했다.
- 넣지 않은 것: Shippori Medium·ExtraBold, LXGW Light. 앱 기준(본문 Regular, 절 번호 SemiBold, 굵게 토글 Bold)에 해당하지 않는다.

### 글자 확인 (fontTools cmap, Mac 번들 DB, 굵기별)
| 본문 | Regular | SemiBold | Bold | 빠지는 글자 |
|---|---|---|---|---|
| JPBUNGO(31,099절, 공백 제외 3,771종) | 3762 | 3762 | 3762 | 帓 獾×6 靀 鸅×4 麆×9 麣 齑 齼 ｀ |
| CUV1919(3,146종) | 3145 | — | 3145 | 僈×2 |
| CUV1919S(3,032종) | 3031 | — | 3031 | 僈×2 |

- 굵기별 결과는 조정자 실측과 같다(3,772는 공백을 포함한 수로 보인다).
- 직역 데이터:
  - Literal_ja: Shippori Regular에 1,988/1,988자가 모두 있다.
  - Literal_zh: LXGW Regular에 3,025/3,042자가 있다. 빠지는 17자는 모두 히브리 문자다(1절). 대체 글꼴로 그려진다.
- 두 글꼴 모두 ASCII 94/94, `●`, 숫자가 있다. 한글은 0자다.

### 굵기 처리
- 절 번호는 `.custom(본문 글꼴).weight(.semibold)`다(`TranslationColumnView` 778행).
  - Shippori Mincho: SemiBold 파일이 있어 같은 family의 SemiBold로 맞춰질 것으로 본다(Literata와 같은 구조).
  - LXGW WenKai TC: SemiBold가 없다. family 안의 글꼴은 Regular(weight 0.0)와 Bold(0.4)뿐이다. `.semibold`는 0.3이라 CoreText의 가장 가까운 굵기 선택으로는 Bold가 고를 가능성이 높다. 합성 굵기는 같은 family에 Bold가 있으면 쓰지 않을 것으로 본다.
  - 다만 CoreText의 굵기 매칭 규칙은 공개 문서가 없다. 기기에서 확인해야 한다.
  - 그래서 SemiBold 대용 파일을 만들지 않았다. 원본에 없는 인스턴스는 수정본이 되고, LXGW는 가변 글꼴도 아니다. 코드 분기도 넣지 않았다.
- 굵게 토글(`boldVariant`, `.traitBold`): 두 글꼴 모두 Bold가 같은 family라 Bold로 간다.

### 기울임
- 직역 카드는 `bibleBodyFont.italic()`이다(`OriginalTextInfoView` 352행). 두 글꼴 모두 Italic 면이 없다.
- SwiftUI가 Italic 면이 없는 사용자 글꼴에 기울임을 합성하는지는 공개 문서가 없다. 기기에서 확인해야 한다.
- 지금 기본값 Paperlogy에도 Italic이 없으므로 바뀌는 상황은 아니다. 지금까지 ja/zh 글자는 시스템 대체 글꼴(Hiragino/PingFang 등)로 그려졌다. 그 경우 기울임이 어떻게 보였는지도 확인되지 않았다.

### 메뉴 노출: 해당 언어에서만 (`languageCode` "ja" / "zh")
- 근거: 기존 지역 전용 글꼴(th·ru·vi)과 같은 규칙이다.
  - 두 글꼴의 라틴 글자는 부수적이다. Literata처럼 모든 언어용 본문 세리프로 고른 글꼴이 아니다.
  - 다른 언어 사용자의 메뉴에 무거운 CJK 전용 글꼴이 늘어날 이유가 없다.
- 현재 선택된 값이면 설정 Picker에 계속 보인다(기존 필터). 파일은 모든 기기에 들어 있으므로 다른 언어 기기에서 만든 메모·설교의 글꼴도 그려진다.

### 코드
- `BundledFontRegistrar.swift`
  - `shipporiMinchoEntries`(3), `lxgwWenKaiTCEntries`(2)와 Regular PostScript 상수를 추가했다.
  - `multilingualFamilies`에 ja·zh Family를 추가했다.
  - `bundledFamilyNamePrefixes`, `knownPrefixes`(`ShipporiMincho-`, `LXGWWenKaiTC-`)와 주석을 고쳤다.
  - 새 파일 5개가 모두 메뉴 항목이라 `selectableFontCount`가 5 늘어난다. 그래서 등록 로그 기대 개수(+9)는 그대로다.
- `SettingsView.swift`: 라이센스 탭에 고지 문구 1개와 저장소 링크 2개(OFL 저작권 줄의 URL)를 넣었다. 링크 라벨은 기존 `"%@ 저장소 보기"` 키를 쓴다.
- `Localizable.xcstrings`: 새 고지 키 1개를 넣었다. 17개 언어, `needs_review`, literata1과 같은 예외다. "일본어"와 "일치 없음" 사이에 106줄을 추가했고 다른 줄은 바뀌지 않았다. 문체는 바로 위 다국어 글꼴 고지 키를 따랐다.
- `RichTextEditor`·`SermonEditorView`: 바꾸지 않았다. `visibleMultilingualFamilies`를 쓰므로 자동으로 반영된다.

### 실행 때 등록 비용
- 지금은 `JBCHBibleResearchApp.init`에서 번들 글꼴 전부를 모든 언어에서 실행할 때마다 등록한다. `CTFontManagerRegisterFontsForURL(.process)`를 파일마다 동기로 메인 스레드에서 부른다.
  - 현재 약 46 MiB(ChosunGs 8.8 MiB, 고운바탕 2종 약 16 MiB 포함)다. 이번 변경으로 약 96 MiB, 파일 47개가 된다.
- 이 등록이 파일을 얼마나 읽는지, 시간과 메모리가 얼마나 드는지는 Apple 문서에 없다. 이 환경(Linux)에서는 CoreText를 잴 수 없어 실측하지 못했다.
- 제안(코드는 넣지 않음):
  1. 먼저 잰다. 등록 루프 앞뒤와 파일마다 `CFAbsoluteTimeGetCurrent()`나 `os_signpost`로 시간을 찍고, Instruments Allocations로 메모리를 본다. 구형 기기에서 콜드 스타트로 확인한다.
  2. 의미 있는 차이가 나오면 지연 등록을 넣는다. 앱 언어가 ja/zh일 때만 실행 시 CJK 파일을 등록하고, 그 밖의 언어는 필요할 때 등록한다.
     - 지금 `ensureAvailable`은 `registeredPostScriptNames`에 없는 이름이면 바로 돌아간다. 그래서 다른 언어 기기에서 CJK 글꼴이 들어간 메모를 열 때 등록하려면, 이 함수가 그 이름을 알아보는 경로가 필요하다. RTF의 `UIFont(name:)` 경로 등 호출부를 함께 손봐야 해서 측정 결과를 보고 정하는 것이 맞다.

### 타이틀 서체(`TitleFont.swift`)와의 관계
- `TitleFont`는 `bibleFontName`이나 메뉴 목록을 참조하지 않는다. 이번 변경으로 바뀌는 것은 없다.
- 지금 ja/zh 타이틀은 KMU80이다(규칙 6, `languageDefaultPostScriptName` default).
  - fontTools 실측: KMU80에는 가나 170자가 있고 CJK 한자는 0자다. 그래서 일본어 타이틀은 가나가 KMU80, 한자가 시스템 글꼴로 한 단어 안에서 섞인다. 중국어 타이틀은 한자가 모두 시스템 글꼴이다.
- 제안(코드는 넣지 않음): `languageDefaultPostScriptName`에 `case "ja"`(ShipporiMincho-Regular), `case "zh"`(LXGWWenKaiTC-Regular)를 넣는다. 그러면 규칙 2("앱 언어 기본 서체가 글자를 모두 가지면 그 서체")가 고정 문구와 데이터 타이틀에 그대로 적용된다. 한글이 있는 타이틀은 규칙 1(KMU80)이 먼저라 바뀌지 않는다. 타이틀 서체는 따로 결정할 사항이라 범위에 넣지 않았다.

## C. 확대보기 줄바꿈 단위 (`VerseZoomView.swift`)
- 새로 `lineBreakUnitWidth`를 넣었다.
  - 본문 글꼴 자체에 "가"(U+AC00) 글리프가 있으면 기존 `hangulCharWidth`(그 글꼴로 잰 값)를 쓴다.
  - 없으면 같은 크기(`font.pointSize`, 19pt)의 `PlatformFont(name: "Paperlogy-4Regular")`로 `"가".size(withAttributes:)`를 실제로 잰다. 고정값 0.88em을 쓰지 않는다.
  - Paperlogy를 만들 수 없으면 기존 값으로 물러난다.
- 글리프 판정에는 `CTFontGetGlyphsForCharacters(font as CTFont, &0xAC00, &glyph, 1) && glyph != 0`를 쓴다.
  - 근거 API: CoreText `CTFontGetGlyphsForCharacters`. "Performs basic character-to-glyph mapping"으로, 대체 글꼴을 찾지 않는다. 대응하지 못한 문자가 있으면 false를 돌려주고 그 글리프를 0으로 둔다(CTFont.h).
  - `CTFontRef`는 "toll-free bridged with UIFont in iOS and NSFont in OS X"이다(Core Text Programming Guide, Overview). 그래서 `as CTFont`로 넘긴다. 파일에 `import CoreText`를 추가했다. `as CTFont` 캐스트는 빌드로 확인해야 한다.
- 쓰는 곳은 `lineBreakWidth`의 비한글 경로 한 곳이다(`targetWidth = lineBreakUnitWidth × targetCharsPerLine`).
  - 한글 경로 `effectiveTextWidth`("가" 23자)는 손대지 않았다.
  - 선택 모드(`SelectableVerseTextView` `containerWidth`·`.frame(width:)`)와 표시 모드(`AnnotatedVerseFlowView`)는 지금처럼 같은 `lineBreakWidth`를 받는다. 두 모드가 같은 값을 쓴다.
- KRV 회귀 검토:
  - 31,088절(한국어 경로): 코드 경로가 같다. 바뀌지 않는다.
  - 라틴 문자·숫자가 있는 14절(비한글 경로, 한 줄짜리 짧은 문구):
    - 기본값 Paperlogy와 고운바탕처럼 "가"가 있는 글꼴: 판정이 true이므로 값이 바이트 단위로 같다.
    - 한국어 사용자가 한글이 없는 글꼴(시스템 기본, Literata, Inter 등)을 골라 둔 경우: 이 14절의 폭 단위가 대체 글꼴의 "가"에서 Paperlogy의 "가"로 바뀐다. 한 줄 문구라 보이는 차이는 없을 것으로 본다. 다만 엄밀히 바이트 단위로 같지는 않다.
- ja·zh에도 같은 경로가 적용된다.
  - JPBUNGO·CUV는 한글이 없어 비한글 경로다. Shippori와 LXGW에는 "가"가 없다(cmap 확인). 그래서 단위가 Paperlogy "가"(지금 기본값일 때와 같은 값)가 된다.
  - 결과적으로 ja·zh의 줄 폭은 지금(Paperlogy 기본값)과 같다. versewrap1 시뮬레이션(CUV 중앙값 17.7/19.7 "가")의 전제가 유지된다.
  - Literata(라틴·vi·ru)와 Noto Serif Thai(th)도 같은 경로를 탄다. 1차 보고에서 말한 "아이폰 세로에서 C에 막힐 위험"이 없어진다.

## 줄 높이 참고 (hhea ascent+descent, CoreText 기준)
| 글꼴 | ascent+descent |
|---|---|
| Paperlogy | 1.178em |
| Literata | 1.485em |
| Noto Serif Thai | 1.598em |
| Shippori Mincho | 1.448em |
| LXGW WenKai TC | 1.317em |

기본값이 바뀌는 언어에서는 한 줄 높이가 커진다.

## 1차 보고 요약 (라틴·vi·ru·th)
- Literata는 SYN·BSB·RV1909·LSG1910·LUT1912·RIV1927·BPM·AYT·VIE1934 본문 글자를 모두 갖고 있다.
  - TGLULB에는 U+0081(데이터 오류, 22절)이 있다. Paperlogy에도 없는 글자라 지금과 같다.
  - `●`는 시스템 대체 글꼴로 그려진다.
  - 키릴은 현대 러시아어 전체가 있다. Ѳѳ Ѵѵ Ѐѐ와 확장 키릴은 없다. SYN에는 나오지 않는다.
- th: Noto Serif Thai에는 THKJV의 “ ” ‘ ’ ( ) [ ](7천 곳 이상)와 숫자가 없다.
  - 절 번호(`TranslationColumnView` 778행)는 시스템 글꼴로 그려진다.
  - 사용자 결정대로 Noto Serif Thai로 두었다. 섞여 보이는 것이 문제면 IBM Plex Sans Thai(77/77자와 숫자 포함)로 `case "th"` 한 줄만 바꾸면 된다.

## 기기에서 확인할 것
1. 각 언어를 새로 설치(키 없음)했을 때 기본 글꼴과 설정 Picker 선택 표시. ja → Shippori Mincho Regular, zh-Hans·zh-Hant → LXGW WenKai TC Regular.
2. 콘솔 `[BundledFontRegistrar] 번들 폰트 N/N개`에서 N이 같은지(이전보다 +5).
3. zh 절 번호(`.semibold`)가 LXGW Bold로 보이는지, 합성 굵기인지, Regular인지. ja 절 번호가 Shippori SemiBold인지.
4. ja/zh 원문 정보 직역 카드 `.italic()`이 기울어지는지.
5. 확대보기 BSB·SYN·THKJV·JPBUNGO·CUV 요 3:16(iPhone 393pt 세로)에서 오른쪽 여백이 남는지. 선택 모드로 바꿨을 때 줄 경계가 같은지.
6. KRV(Paperlogy 기본값) 확대보기 줄 위치가 이전과 같은지. 시스템 기본 글꼴을 골라 둔 상태에서 신 6:19 등 라틴 문자·숫자가 있는 절도 확인한다.
7. 콜드 스타트 시간(구형 기기, ko 앱)이 이전과 비교해 늘었는지. 위 B의 측정 제안을 따른다.
8. ja/zh 메모 에디터에서 Shippori·LXGW 굵게 토글. 다른 언어 기기에서 그 메모가 같은 글꼴로 보이는지.
