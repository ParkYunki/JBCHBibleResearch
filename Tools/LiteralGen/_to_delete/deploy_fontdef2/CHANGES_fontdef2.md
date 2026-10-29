# CHANGES_fontdef2 — CJK 타이틀 서체, CJK 글꼴은 해당 언어 앱에서만 시작 등록 + 다른 언어 앱은 파일 단위 지연 등록 (2026-10-29)

- 기준: fontdef1을 적용한 파일과, fontdef1이 건드리지 않은 Mac 현재 파일이다.
  - 건드리지 않은 Mac 파일의 sha1: TitleFont d3325347…, RichTextEditor 63626956…, JBCHBibleResearchApp 565c0ddd…, SermonParagraphEditor a6f3fe13…(리뷰 C5로 추가).
  - 사본: `/home/claude/integ/fontdef2_base/`
- diff: `/home/claude/integ/fontdef2.diff`(372줄, 파일 6개). 수정본은 `/home/claude/integ/fontdef2/`이다. fontdef1.diff는 덮어쓰지 않았다.
  - `fontdef2_base`에 `git apply --check`가 통과했고, 적용 결과가 수정본과 바이트 단위로 같다.
  - Mac과 같은 원본에 fontdef1.diff를 적용한 뒤 fontdef2.diff `--check`를 하는 연쇄 확인도 통과했다.
- 빌드는 하지 못했다(이 환경에 Swift가 없다). 새 xcstrings 키는 없다.

## 1. 타이틀 서체 (`TitleFont.swift`)
- `languageDefaultPostScriptName`: `case "ja"` → `ShipporiMincho-Regular`, `case "zh"`(zh-Hans·zh-Hant 모두) → `LXGWWenKaiTC-Regular`. 그 밖의 언어는 그대로다.
- **고정 문구 경로**(`Font.titleSerif(size:relativeTo:)`): 앱 언어 기본값을 바로 쓴다.
  - ja·zh-Hans·zh-Hant xcstrings 값 1,185개의 글자(문자·결합 부호·숫자)를 fontTools로 대조했다. 각 글꼴에 없는 것은 한국어 고지 문구 2개(관주·개역한글 저작권, "한글 (가. 나. 다.)")의 한글과 U+FE0F뿐이다. 이 두 문구는 타이틀이 아니다.
- **문자열 경로**(`postScriptName(for:)`):
  - 한글이 있으면 KMU80이다(규칙 1이 먼저다. 바뀌지 않음).
  - 그 밖에는 앱 언어 기본값(Shippori/LXGW)이 글자를 모두 가지면 그 글꼴이다(규칙 2). 기본 라틴도 두 글꼴에 있다.
  - 두 글꼴에 없는 글자(예: JPBUNGO의 9자)가 들어간 타이틀은 지금처럼 규칙 3 이하로 내려간다.
  - 다른 언어 앱에서는 기본값이 Shippori/LXGW가 아니고 규칙 3–6에도 이 글꼴이 없다. 그래서 타이틀 때문에 지연 등록이 일어나지 않는다.
- **굵기**: `.titleSerif`는 굵기를 받지 않는다. 호출부 26곳 가운데 18곳이 `.fontWeight(.semibold)` 또는 `.bold`를 붙인다.
  - Shippori: SemiBold·Bold 파일이 있다. 해당 언어 앱에서 시작할 때 등록된다.
  - LXGW: Bold만 있다. `.semibold`는 가장 가까운 굵기(Bold일 가능성이 높음)로 맞춰질 것으로 본다. CoreText 매칭 규칙은 문서가 없어 기기에서 확인해야 한다.
  - 지금까지 KMU80은 Regular 하나라 SwiftUI가 굵기를 합성했다. ja/zh에서는 이제 실제 굵은 글꼴로 바뀌어 모양이 달라진다.

## 2. 시작 때 등록 범위
- `registerBundledFontsIfNeeded`는 `DeferredFontRegistry.fonts`(다른 언어 앱 전용 CJK 파일)를 등록 목록에서 뺀다.
  - ja 앱: Shippori 3개는 시작 때 등록한다. LXGW 2개는 지연 등록한다.
  - zh 앱: LXGW 2개는 시작 때 등록한다. Shippori 3개는 지연 등록한다.
  - 그 밖의 언어 앱: 5개 모두 지연 등록한다.
- 언어 기준은 메뉴 노출 규칙(`Family.languageCode == AppLanguage.baseCode`)과 같다. DEBUG 빌드는 시작 때 `assertMatchesMenuFamilies()`로 두 목록(`languageFontNames`와 메뉴의 ja/zh Family 항목)이 같은지 확인한다.
- 등록 로그 기대 개수: `selectableFontCount + 9 − DeferredFontRegistry.fonts.count`. ja 앱은 −2, zh 앱은 −3, 그 밖은 −5다. 지연 등록은 별도 로그(`지연 등록 이름: N ms, 메인/백그라운드 스레드`)로 남는다.
- 설정 Picker는 현재 선택값이면 목록에 계속 보인다(기존 필터, 이름만 쓴다). 그 값으로 본문을 그릴 때 `ensureAvailable`이 지연 등록한다. 그래서 메뉴, 선택값 표시, 등록 규칙이 서로 어긋나지 않는다.

## 3. 다른 언어 앱에서 이 글꼴이 필요해지는 경우 (소스 전수 확인)
| 경로 | 글꼴 생성 | 처리 |
|---|---|---|
| 메모·말씀 요약·개요·설교 본문·마인드맵·관련 내용·설교 뷰어 등 RTF 문서(iCloud 동기화). 모든 디코딩이 `RichTextCodec.decode` 한 곳을 지난다(7곳 호출) | RTF를 읽을 때 글꼴 표의 이름으로 글꼴을 만든다 | **읽기 직전에** `DeferredFontRegistry.registerFonts(referencedInRTF:)`가 RTF 머리 16KB에서 지연 글꼴 PostScript 이름을 찾아, 그 이름이 속한 글꼴 묶음 전체를 동기로 등록한다(2차 리뷰 A1) |
| 설정 `bibleFontName`(앱 언어를 바꾸기 전에 고른 값) | `bibleBodyFont` 등 `ensureAvailable` 다음에 `.custom`/`PlatformFont(name:)` | 시작 직후 백그라운드 미리 등록, 그리고 `ensureAvailable` 지연 등록 |
| 설교 문단 스타일 글꼴 6종(KVS 동기화), 한자 글꼴 | `sermonFont`/`sermonPlatformFont`/`hanjaFont`(모두 `ensureAvailable` 다음) | 위와 같다 |
| 메모·설교 에디터 글꼴 메뉴 적용 | `ensureAvailable` 다음 `UIFont(name:)` | 메뉴에는 해당 언어에서만 보이므로 다른 언어 앱에서는 이 경로를 탈 일이 없다. 타더라도 지연 등록된다 |
| 타이틀 | `TitleFont`(`ensureAvailable` 다음) | 다른 언어 앱에서는 이 글꼴을 고르지 않는다 |
| `SermonParagraphEditor` `isManualFont`의 `PlatformFont(name: previous.fontName)`(스타일 스냅샷 이름) | 원래 `ensureAvailable` 없음 | 리뷰 C5에 따라 바로 앞에 `BundledFontRegistrar.ensureAvailable(previous.fontName)`를 넣었다(431–432행). `SermonParagraphStyleCodec`은 기본 MainActor라 호출 격리가 맞다. 지연 대상이 아니면 사전 조회와 기존 1초 간격 확인뿐이고, "System"은 등록 목록에 없어 바로 돌아간다. 부작용이 없다 |

- 앱이 쓰는 RTF의 글꼴 표에는 PostScript 이름이 들어간다. 번들 `OutlineSeed.json` RTF에서 `\fonttbl\f0\fnil\fcharset0 Paperlogy-4Regular;…GowunBatang-Regular;…AppleSDGothicNeo-Regular` 형태를 확인했다. 번들 파일 이름도 PostScript 이름과 같다.
- **2안(등록하지 않음)은 고르지 않았다.**
  - RTF를 읽을 때 등록되지 않은 글꼴은 대체 글꼴 속성으로 바뀐다. 그 문서를 다른 언어 기기에서 편집해 저장하면 원래 글꼴 이름이 사라진다. 이 손실은 iCloud로 원래 기기에도 퍼진다.
  - 사용자 결정(1안)과도 같다.

## 4. 지연 등록 설계 (`BundledFontRegistrar.swift`의 `DeferredBundledFont`, `DeferredFontRegistry`)
- **묶음 단위로 등록하고, 파일마다 한 번만** (2차 리뷰 A1):
  - `DeferredBundledFont` 하나가 파일 하나(= PostScript 이름 하나)다. 상태는 pending, registered, failed 셋이다.
  - pending일 때만 `CTFontManagerRegisterFontsForURL(.process)`를 부른다. `kCTFontManagerErrorAlreadyRegistered`는 성공으로 본다.
  - 등록 요청은 묶음 단위다. 묶음은 `languageFontNames`의 한 줄(Shippori 3개, LXGW 2개)이다. `familyMembers`는 이름에서 묶음을 찾는 표이고, `registerFamily(of:)`가 묶음의 각 파일에 `registerIfNeeded()`를 부른다.
    - `ensureAvailable`: deferredFont 블록 첫 줄에서 `registerFamily`를 부른다. 기존 guard는 유지했다.
    - `registerFonts(referencedInRTF:)`, `prefetch`: 둘 다 묶음 단위다.
  - 묶음으로 바꾼 이유: 굵기 짝은 이름이 아니라 특성으로 같은 family에서 찾는다. 첫 구현처럼 요청된 파일 하나만 등록하면, 다른 언어 앱에서 굵게가 원래 모양으로 나오지 않는다. 특성으로 찾는 경로는 다음과 같다.
    - `TranslationColumnView` 778행과 `SettingsView` 858행의 `.weight(.semibold)`
    - `VerseAnnotationRenderer.boldVariant`
    - `RichTextEditor` `togglingTrait`
    - `SermonParagraphEditor` 487·554·564행의 `withSymbolicTraits`
  - 한 파일이 failed가 되어도 나머지는 정상 등록된다. 파일마다 상태와 잠금이 따로이고, `registerFamily`는 각 파일의 결과와 관계없이 끝까지 돈다.
  - RTF 훑기(2차 리뷰 C3): `DeferredBundledFont.isPending`이 `withLockIfAvailable`로 상태를 본다. 다른 스레드가 등록 중이면 기다리지 않고 pending으로 본다.
    - 묶음에 pending 파일이 하나라도 있으면 그 묶음의 이름들을 `contains`로 검사한다. 하나라도 나오면 묶음 전체를 등록한다.
    - pending 파일이 없는 묶음은 검사를 건너뛴다. 모든 등록 경로가 묶음 전체를 시도하므로, 이 묶음은 이미 짝 파일까지 등록됐거나 실패가 확정된 상태다. 그래서 이미 등록된 파일이 RTF에 나와도 짝 파일 처리가 빠지지 않는다.
    - 동작은 C3 전과 같다. 전에도 pending이 아닌 파일의 `registerIfNeeded()`는 아무 일도 하지 않았다.
- **동시성**:
  - 파일마다 `OSAllocatedUnfairLock<State>`이 하나다(리뷰 B2로 `NSLock`에서 바꿈). 같은 파일을 메인(`ensureAvailable`, RTF 디코딩)과 백그라운드(미리 등록)가 동시에 요청하면, 첫 요청만 등록하고 나머지는 잠금에서 기다렸다가 결과를 받는다. 중복 등록이 없다.
  - 잠금을 바꾼 이유는 우선순위 역전이다. `.utility` 미리 등록 작업이 잠금을 쥔 채 큰 파일을 등록하는 동안 메인이 같은 파일을 기다릴 수 있다. os_unfair_lock 기반 잠금은 기다리는 스레드의 우선순위를 잠금 소유 스레드에 넘겨 준다. `NSLock`은 이를 보장하지 않는다.
  - `Task.detached` 우선순위를 올리는 방법(대안)은 고르지 않았다. 잠금 교체가 구조를 바꾸지 않고(상태가 잠금 안으로 들어갈 뿐), 배포 대상(iOS 18, macOS 26)이 `OSAllocatedUnfairLock`(iOS 16+, macOS 13+)을 쓸 수 있기 때문이다. 미리 등록은 `.utility`로 두어, 메인이 기다리지 않는 평소에는 첫 화면 작업과 경쟁하지 않게 했다.
  - `withLock` 클로저 안에서는 `registerFile()`만 부른다. throw하는 코드가 없고, 이 객체의 잠금을 다시 잡는 경로도 없다(`registerFile`은 `registerIfNeeded`·`registerAgain`을 부르지 않는다).
    - 앱 코드에는 글꼴 등록 알림(`kCTFontManagerRegisteredFontsChangedNotification` 등)을 받는 곳이 없다(Mac 소스 grep). 그래서 등록 중 같은 스레드에서 앱 코드로 다시 들어오는 경로도 없다.
    - os_unfair_lock은 같은 스레드가 다시 잡으면 프로세스를 멈추므로(재진입 불가) 이 점을 확인했다.
  - 중첩 `State` enum에 `nonisolated`를 명시했다(리뷰 B1). 기본 MainActor 모드에서 격리 추론을 피하기 위한 것이고, 의미는 같다. 이 클래스 안의 다른 중첩 타입은 없다.
  - 다른 파일끼리는 서로 막지 않는다.
  - Core Text 함수는 여러 스레드에서 동시에 불러도 된다(Core Text Programming Guide – Multicore Considerations).
  - 레지스트리 표(`fonts`)는 `static let`이라 초기화가 한 번만 일어나고 이후 읽기 전용이다.
- **메인 스레드 비용**:
  - 메인에서 등록하는 것은 지금 그릴 글꼴의 묶음이다. Shippori는 3개(약 25.9MB), LXGW는 2개(약 26.0MB)다.
    - 다른 언어 앱에서 그 글꼴을 처음 쓸 때 한 번만 생기는 비용이고, "원래 모양으로 보여 주기"를 위해 허용한다(조정자 결정).
    - 처음 구현(요청된 파일 하나만 등록)보다 첫 등록 비용이 커진다.
  - 설정에 저장된 이름은 `JBCHBibleResearchApp.init`에서 `Task.detached(priority: .utility)`로 묶음째 미리 등록한다.
  - 문서 RTF는 디코딩 순간이 문서 문자열을 처음 손에 쥐는 지점이다. 그 전에 비동기로 등록하려면 시작할 때 SwiftData의 모든 문서를 훑어야 한다. 비용이 문서 수에 비례하고 대부분의 사용자에게는 필요 없어 넣지 않았다.
  - 등록마다 걸린 시간(ms)과 스레드를 로그로 남긴다. 실제 값은 기기에서 이 로그로 잰다. 이 환경에서는 CoreText를 잴 수 없다.
  - 이미 등록된 뒤의 비용은 사전 조회와 잠금 하나다. 지연 대상이 아닌 이름은 사전 조회 하나만 늘어난다(성경 목록에서 절마다 부르는 경로).
- **실패**: failed로 남기고 다시 시도하지 않는다. 호출부의 기존 폴백(`?? .systemFont`, SwiftUI의 대체 글꼴)이 시스템 대체 글꼴로 그린다.
- **소실 대비**: 시작 때 등록한 글꼴과 같은 1초 간격 확인을 지연 글꼴에도 적용한다. 요청한 글꼴이 사라졌으면, 같은 묶음에서 registered 상태이면서 실제로 `UIFont(name:)`/`NSFont(name:)`로 찾을 수 없는 파일만 `registerAgain()`한다(2차 리뷰 A1 검토).
  - 묶음으로 넓힌 근거: 소실은 프로세스 범위 등록이 통째로 풀리는 경우라, 짝 파일도 함께 사라졌을 가능성이 높다. 요청 파일만 되살리면 굵게가 대체 글꼴로 남는다.
  - 부작용이 없는 이유:
    - 실제로 사라진 파일만 다시 등록하므로 쓸데없는 등록 호출이 없다.
    - pending(아직 쓰지 않은 짝)과 failed 파일은 건드리지 않는다. `isRegistered` 확인과 `registerAgain`의 기존 guard 둘 다 이를 막는다.
    - 이미 등록된 파일을 다시 등록하게 되더라도 `alreadyRegistered`를 성공으로 보므로 상태가 바뀌지 않는다.
  - 확인 간격 코드는 `shouldCheckAvailability(of:)`로 뽑아냈다. 기존 경로의 동작은 같다.
- **다시 그리기는 필요 없다**:
  - 글꼴을 이름으로 만드는 경로는 만들기 직전에 `ensureAvailable`를 부르고, RTF는 읽기 직전에 훑는다. 둘 다 동기로 묶음 등록을 마친 뒤 돌아온다.
  - 굵기 짝을 특성으로 찾는 경로(`.weight`, `boldVariant`, `togglingTrait`, 설교 편집기)는 이름으로 만든 글꼴에서 출발한다. 그 시점에는 위 호출이 이미 묶음 전체를 등록해 둔 뒤다. 1차 문서의 "모든 생성 경로가 ensureAvailable을 부른다"는 표현은 사실과 달라 이렇게 고쳤다.
  - 그래서 대체 글꼴로 먼저 그려졌다가 바뀌는 텍스트가 없다.
  - 백그라운드 미리 등록이 진행 중이면 메인 요청은 그 등록이 끝나기를 기다린다.
- **macOS 영향** (2차 리뷰 C2로 정정): `UserSettingsStore.shared`는 iOS에서는 원래 `App.init`(55행 `applyThemedTabBarAppearance`)에서 생성됐다. macOS에서는 원래 첫 Scene 본문(`ContentView` 29행, `AppColorSchemeModifier`)에서 처음 생성됐는데, 이번 미리 등록 때문에 `App.init` 안, 글꼴 등록 직후(ModelContainer 생성 전)로 앞당겨진다.
  - init은 UserDefaults를 읽고 끝에서 `startSermonStyleCloudSync()`를 부른다(`defaults === .standard`일 때).
    1. `applyCloudSermonSettings(pushMissingLocalValues: true)`가 KVS 값을 읽어 반영하고, KVS에 없는 로컬 값을 KVS에 올린다.
    2. `NSUbiquitousKeyValueStore.didChangeExternallyNotification` 관찰자를 `.main` 큐에 등록한다.
    3. `synchronize()`를 부른다.
  - 이 순서에 기대는 코드는 없다.
    - 앱 전체에서 `NSUbiquitousKeyValueStore`를 쓰는 파일은 `UserSettingsStore.swift` 하나다(uploads 전체 grep, 패키지 포함).
    - 이 init은 ModelContainer, ModelContext, `CloudSyncMonitor` 등 다른 싱글턴을 참조하지 않는다. 같은 파일 grep 결과는 `BundledFontRegistrar.ensureAvailable`뿐이고, 이는 init이 아니라 글꼴 계산 프로퍼티 안에 있다.
    - `App.init`에서 앞에 실행되는 것은 `CloudSyncMonitor.shared.start()`(CloudKit 알림 구독)와 글꼴 등록뿐이다. 뒤의 macOS 코드(`NSWindowAssertWhenDisplayCycleLimitReached` 설정, 컨테이너 생성)는 이 스토어를 읽지 않는다.
    - KVS 관찰자는 `.main` 큐로 비동기로 전달되므로, 생성 시점이 앞당겨져도 알림 처리는 메인 런루프가 돈 뒤에 일어난다. iOS에서 이미 같은 시점에 생성되던 것과 같은 조건이다.

## 기기에서 확인할 것
1. ko 앱 시작 로그가 `N/(selectable+9−5)`이고 N이 같은지. ja 앱은 −2, zh 앱은 −3.
2. ja 기기에서 메모에 Shippori Bold를 적용한다. 동기화된 ko 기기에서 그 메모를 열면 `지연 등록 ShipporiMincho-Bold: … ms, 메인 스레드` 로그가 Shippori 묶음 3개 파일에 대해 파일마다 1번씩 나오는지 본다. 본문, 굵게, 절 번호(SemiBold)가 원래 모양으로 보이는지도 본다. 편집하고 저장한 뒤 ja 기기에서도 글꼴이 유지되는지 본다.
3. 같은 문서를 여러 창/화면에서 동시에 열어도 지연 등록 로그가 파일당 1번인지.
4. ja 앱에서 Shippori를 본문 글꼴로 고르고 앱 언어를 ko로 바꿔 다시 시작한다. 백그라운드 스레드 로그가 나오고 본문이 Shippori로 보이는지 본다.
5. ja/zh 타이틀(고정 문구, 인물 이름 같은 데이터 타이틀, 한글 섞인 타이틀)의 글꼴과 굵기.
6. 지연 등록 시간(ms)이 첫 표시에 체감되는지(구형 기기, 13MB LXGW 파일).
