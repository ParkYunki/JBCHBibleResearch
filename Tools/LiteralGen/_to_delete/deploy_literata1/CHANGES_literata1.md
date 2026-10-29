# CHANGES_literata1 — Literata 글꼴 추가, 베트남어 앱 성경 본문 기본 글꼴 (2026-10-29)

## 결정 요약
- **번역본별 글꼴 설정은 없다.** 성경 본문 글꼴은 `UserSettingsStore.bibleFontName` 하나뿐이다.
  `TranslationColumnView`(열마다 같은 `settings.bibleBodyFont`/`platformBodyFont`), `VerseZoomView`, `OriginalTextInfoView`가 모두 이 값을 쓴다.
  `TranslationRegistry`(SwiftData 모델)와 `BundledTranslation`에도 글꼴 필드가 없다.
- 그래서 지시대로 **앱 언어가 vi일 때 `bibleFontName` 기본값을 `Literata-Regular`로** 했다. 저장된 값(`settings.bible.fontName`)이 있으면 그 값을 쓴다.
  - 번들 성경은 앱 언어의 것 하나만 보인다(`BundledTranslationCatalog.isVisible`: `!isBundled || code == current.code`). 그래서 VIE1934 번들이 보이는 앱은 베트남어 앱뿐이다. 한국어 앱에서 VIE1934 번들을 나란히 보는 경우는 현재 구조에서 생기지 않는다.
- 설교 문단 스타일 기본값(`languageAdjustedDefaultFontName`)과 메모 기본값(`EditorDefaultStyle`)은 **바꾸지 않았다**(조정자 지시).
- 글꼴 메뉴에는 **모든 언어에서** Literata를 보이게 했다(`Family.languageCode`를 `String?`로 바꾸고 nil이면 모든 언어에 보이게 함).
- 2026-10-12 결정("성경 본문 기본 글꼴 Paperlogy는 바꾸지 않는다")을 vi에 한해 바꾼다. 사용자 결정(2026-10-29)이다. 다른 언어는 그대로 `Paperlogy-4Regular`다.

## 글꼴 파일 (`/mnt/user-data/outputs/deploy_literata1/Fonts/` → Mac `JBCHBibleResearch/JBCHBibleResearch/Fonts/`)
| 파일 | 크기 | PostScript | wght | 용도 |
|---|---|---|---|---|
| Literata-Regular.ttf | 270,776 | Literata-Regular | 400 | 본문 기본 |
| Literata-SemiBold.ttf | 271,192 | Literata-SemiBold | 600 | 절 번호 `.weight(.semibold)` |
| Literata-Bold.ttf | 271,312 | Literata-Bold | 700 | 메모·설교 굵게 토글, `boldVariant` |
| Literata-Italic.ttf | 259,212 | Literata-Italic | 400 | 직역 카드 `.italic()`(Literal_vi.sqlite 있음), 메모 기울임 토글 |
| OFL-Literata.txt | 4,389 | — | — | 원본 OFL.txt 그대로 |
합계 1,076,881 bytes(약 1.08 MB, 압축 전).

- 출처: github.com/google/fonts `ofl/literata/`(clone HEAD 58466038, METADATA 상류 커밋 googlefonts/literata 0c2761b, Version 3.103).
  원본 sha256: `Literata[opsz,wght].ttf` b41138c9…4440, `Literata-Italic[opsz,wght].ttf` d483dfae…d465.
- 정적 TTF는 google/fonts에 없다(가변 글꼴만 있음). 가변 글꼴의 named instance에는 postScriptNameID가 없다(전부 0xFFFF). CoreText가 그 이름을 어떻게 붙이는지는 여기서 확인할 수 없다. 이 앱은 `UIFont(name:)`/`Font.custom`을 PostScript 이름으로 쓰고, 등록 목록(`registeredPostScriptNames`)을 **파일 이름**으로 만든다. 그래서 fontTools 4.65 `instancer`로 정적 인스턴스를 만들었다.
  - opsz=12로 고정했다. fvar 기본값이고 모든 named instance의 값이다. `updateFontNames=True`를 쓰면 이름에 "12pt"가 붙는다(`Literata-12ptBold`). 그래서 이름 테이블은 직접 넣었다. 규칙은 번들된 Be Vietnam Pro와 같다(ID1/2/4/6, SemiBold만 ID16/17).
  - Bold의 fsSelection(BOLD 비트)과 macStyle은 직접 설정했다. Italic은 원본 Italic 파일에서 만들어 fsSelection ITALIC, italicAngle −2가 들어 있다.
  - fsType=0(설치 가능, 임베딩 제한 없음)이다. 원본과 인스턴스 모두 확인했다.
  - OFL.txt에는 Reserved Font Name이 없다. 그래서 수정본(인스턴스)도 "Literata" 이름을 쓸 수 있다.
  - 재현 스크립트: `/tmp/claude-0/-home-claude/de68392e-3416-5f0f-b626-1d4c970e0865/scratchpad/tools/instance.py`
- 등록: Info.plist에 UIAppFonts가 없고 `BundledFontRegistrar`가 CTFontManager `.process`로 등록한다. 프로젝트는 `PBXFileSystemSynchronizedRootGroup`을 쓰므로 `Fonts/`에 파일을 넣으면 타깃에 자동으로 포함된다. 번들 루트로 평탄화되는 경우를 위해 `knownPrefixes`에 `"Literata-"`를 추가했다. 라이선스 파일 이름을 `OFL.txt`가 아니라 `OFL-Literata.txt`로 한 것도 평탄화 때문이다. 기존 `OFL-*.txt` 규칙을 따르고 이름 충돌을 피한다.

## 글자표 실측 (4종 모두 같은 결과)
- 베트남어 전체: 모음 12종×대소문자×성조 6가지(성조 없음 포함)를 NFC로 만든 134자 + đĐ + ASCII 문자를 합친 186/186자. 분해형 결합 부호 8/8(GPOS `mark` 기능 유지).
- ASCII 전체와 일반 구두점(– — ‘ ’ “ ” … « » ‹ › ‐ ′ ″ 등): 120/120.
- Latin-1 보충 96/96. Latin Extended-A 127/128(U+017F long s만 없음). Latin Extended-B 78/208, Latin Extended Additional 168/256(아프리카 문자 등이 빠짐. 베트남어 블록 U+1EA0–1EF9는 모두 있음).
- 키릴 94/96, 그리스어 82/129, 한글 0.
- **VIE1934 번들 본문에 쓰인 146자: 146/146.** 31,102절 모두 NFC다.
- 빠지는 것: 문단 마커 `●`(U+25CF). 앱이 `"● "`로 덧붙이는 기호다. Paperlogy에는 있고 Literata와 Be Vietnam Pro에는 없다. 베트남어 앱에서는 이 글자만 시스템 대체 글꼴로 그려진다.
- 비교: Paperlogy-4Regular에는 VIE1934 글자 중 57자가 없다(ĂăĐđĩũƠơƯư와 ạ…ỹ). 지금 베트남어 앱 본문은 한 단어 안에서도 글꼴이 섞이는데, 이번 변경으로 해결된다.
- PIL 렌더링으로 요한복음 3:16과 대문자 성조 글자를 4종 모두 확인했다. 깨짐은 없었다.
- 참고(글꼴과 무관, 데이터): VIE1934에 깨진 인코딩으로 보이는 문자가 있다. Þ ð Ì Ò가 4절(창 40:12, 40:18, 사 55:8, 마 6:10)에 나온다(예: "nghiÞa chiêm bao ðoì laÌ thêÒ"). `Aïc`/`Aït`/`Oït`는 112곳에 나온다(원본도 그런지는 확인하지 않았다).

## 코드 변경 (`/home/claude/integ/literata1.diff`, Mac 현재 파일과 sha1이 같은 사본에 `git apply --check` 통과)
- `Services/BundledFontRegistrar.swift`
  - `bibleDefaultPostScriptName`(vi → `Literata-Regular`, 그 밖 → `defaultPostScriptName`)을 추가했다.
  - `literataRegularPostScriptName`, `literataEntries`(Regular/SemiBold/Bold)를 추가했다. Italic은 메뉴에 넣지 않는다.
  - `Family.languageCode: String?`로 바꿨다. `multilingualFamilies` 맨 앞에 `Literata`(nil)를 넣었고, `visibleMultilingualFamilies`는 nil도 통과시킨다.
  - `bundledFamilyNamePrefixes`에 "Literata", `knownPrefixes`에 "Literata-"를 추가했다. 등록 로그 기대 개수는 +9로 바꿨다(Italic 1개 포함).
- `Services/UserSettingsStore.swift`: `bibleFontName` 기본값을 `BundledFonts.bibleDefaultPostScriptName`으로 바꿨다(주석 포함).
- `Views/Settings/SettingsView.swift`: Picker 주석을 고쳤다. 라이센스 탭에 Literata 저장소 링크와 OFL 고지를 따로 넣었다. 수정본이므로 기존 "수정 없이" 문구와 분리했다.
- `Views/Memo/RichTextEditor.swift`, `Views/Sermon/SermonEditorView.swift`: 주석만 고쳤다. 메뉴는 `visibleMultilingualFamilies`를 그대로 쓰므로 자동으로 반영된다.
- `Localizable.xcstrings`: 새 고지 키 1개를 추가했다. 조정자 지시(B1)로 ko/en 규칙의 예외가 되어 17개 언어 값을 모두 넣었다. 바로 위 다국어 글꼴 고지 키의 문체·용어를 따랐고 state는 `needs_review`다. diff는 이 키의 추가 106줄뿐이다.
- `TitleFont.swift`: 바꾸지 않았다. 타이틀 서체는 KMU80/Gentium/Noto Serif Thai를 이름으로 고정해 쓰고 `bibleFontName`이나 메뉴 목록을 참조하지 않는다.

## 검증
- 다른 언어: `bibleDefaultPostScriptName`은 vi가 아니면 `defaultPostScriptName`("Paperlogy-4Regular")을 그대로 돌려준다. `languageAdjustedDefaultFontName`(설교·메모)은 바꾸지 않았다. 따라서 ko와 그 밖의 언어의 기본 글꼴은 바뀌지 않는다. 메뉴에는 Literata 항목이 추가된다.
- vi 사용자 중 글꼴을 한 번도 고르지 않은 사람(키 없음)은 업데이트 후 Paperlogy 대신 Literata로 보인다(의도한 변경). 글꼴을 골랐던 사람(Paperlogy 포함)은 저장된 값을 그대로 쓴다. `bibleFontName`은 `didSet`에서만 저장되고, init 대입은 저장하지 않는다.
- 동기화와 구버전:
  - `bibleFontName`은 UserDefaults 전용이다. iCloud KVS 동기화 대상(`syncedSermonStringSettings`)이 아니므로 다른 기기로 전파되지 않는다.
  - 설교 스타일 글꼴(KVS 동기화)은 기본값을 바꾸지 않았다. 이 값을 바꾸는 UI 코드도 Views에서 찾지 못했다. 따라서 이번 변경으로 KVS에 "Literata-*"가 올라가는 경로는 없다.
  - 메모·설교 본문(RTF, CloudKit 동기화)에 글꼴 메뉴로 Literata를 적용한 경우, Literata가 없는 구버전 앱에서는 그 글꼴이 등록돼 있지 않아 다른 글꼴로 대체되어 보인다(문자는 보존). 설교와 메모 에디터의 `UIFont(name:) ?? 기존 글꼴` 경로는 nil일 때 폴백한다. 이는 2026-10-12 다국어 글꼴과 같은 성격이다. 구버전에서 그 문서를 편집해 저장하면 해당 구간의 글꼴 속성이 대체 글꼴로 바뀔 수 있다. 실제 대체 글꼴은 기기에서 확인해야 한다.

## 기기에서 확인할 것
1. vi 앱을 처음 설치하거나 설정 키가 없을 때 본문이 Literata로 보이는지, 설정 > 모양 > 글꼴에 "Literata Regular"가 선택되어 보이는지.
2. 콘솔 `[BundledFontRegistrar] 번들 폰트 N/N개 등록 완료`에서 N이 같은지(이전보다 +4).
3. 절 번호(`.weight(.semibold)`)가 Literata SemiBold로 보이는지, 직역 카드 `.italic()`이 진짜 Italic으로 보이는지(같은 family 해석).
4. ko/en 앱 본문은 Paperlogy 그대로인지, 메모·설교·설정 메뉴에 Literata가 보이는지.
5. 메모에서 Literata 선택 → 굵게/기울임 토글.
6. macOS에 사용자가 Literata를 따로 설치한 경우 같은 PostScript 이름이 겹친다. 등록 로그와 표시를 확인한다(드문 경우).
