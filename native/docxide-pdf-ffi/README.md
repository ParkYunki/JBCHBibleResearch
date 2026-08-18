# docxide-pdf-ffi

[2026-08-16 신설] 사용자 요청 — "docxide-pdf + PDFKit로 docx를 pdf로 변환하는 것을
검토할 것" → "진행할 것. iOS상에서는 처리가 안되는 파일 업로드를 막으면 됨."

[docxide-pdf](https://github.com/sverrejb/docxide-pdf)(Apache-2.0, 순수 Rust)를
Swift에서 부를 수 있게 감싼 아주 얇은 C ABI 어댑터. Xcode/SwiftPM은 Rust 코드를
직접 빌드하지 못하므로, **아래 절차를 macOS에서 수동으로(또는 Xcode "Run
Script" 빌드 단계로) 한 번 실행**해 정적 라이브러리를 만들고, 그 결과물을
Xcode 프로젝트에 링크해야 합니다.

⚠️ 이 crate는 Rust 툴체인이 없는 리눅스 샌드박스에서 작성돼 `cargo build`로
컴파일 검증을 하지 못했습니다. Rust 문법 자체는 신중하게(표준 FFI 관용구만
사용) 작성했지만, 실제 빌드 시 사소한 오류가 날 수 있습니다 — 아래 "빌드가
실패하면" 절 참고.

## 왜 macOS 전용인가

- `docxide-pdf`는 폰트를 macOS/Linux/Windows의 시스템 폰트 디렉터리를 훑어
  찾습니다(README에 명시) — iOS는 언급조차 없어, 문서에 폰트가 임베드돼 있지
  않으면 iOS에서 텍스트가 깨지거나 안 나올 위험이 있습니다.
- iOS 앱 샌드박스는 임의 정적 라이브러리를 문제없이 링크할 수는 있지만(Rust는
  iOS 크로스컴파일 자체는 지원), 위 폰트 문제 때문에 품질을 보장할 수 없어
  사용자가 "iOS는 막으면 된다"고 결정했습니다.
- 그래서 이 스크립트는 **macOS(arm64+x86_64) 유니버설 정적 라이브러리만**
  만듭니다. iOS용 빌드는 의도적으로 만들지 않습니다.

## 빌드

```bash
# 1) rustup 설치(아직 없다면): https://rustup.rs
# 2) 타깃 추가
rustup target add aarch64-apple-darwin x86_64-apple-darwin
# 3) 빌드
cd native/docxide-pdf-ffi
./build-macos-lib.sh
```

성공하면 `dist/libdocxide_pdf_ffi.a`(유니버설 정적 라이브러리)가 생깁니다.
`include/docxide_pdf_ffi.h`(C 헤더)는 이미 이 폴더에 있습니다.

### 빌드가 실패하면

- `error[E0308]` 등 타입 불일치 — `src/lib.rs`가 가정한 `docxide_pdf::
  convert_docx_bytes_to_pdf(input: &[u8], path: impl AsRef<Path>) ->
  Result<(), Error>` 시그니처가 실제 배포된 crate 버전과 다를 수 있습니다(이
  코드는 GitHub의 `main` 브랜치 소스를 읽고 작성했지만, crates.io에 올라간
  `0.16.x` 태그 버전과 미묘하게 다를 가능성을 배제 못 함 — "Work in progress"
  라이브러리라 API가 자주 바뀝니다). 에러 메시지의 정확한 시그니처에 맞춰
  `src/lib.rs`의 함수 호출부만 고치면 됩니다 — FFI 경계(extern "C" 함수 두 개)
  자체는 그대로 두고 됩니다.
- `error: linking with 'cc' failed` — Xcode Command Line Tools가 필요합니다
  (`xcode-select --install`).
- 의존성 해석 실패 — `Cargo.lock`이 이 폴더에 없으므로 처음 빌드 시 인터넷
  접속이 필요합니다(crates.io에서 `docxide-pdf`와 그 하위 의존성을 받아옴).
- [2026-08-17 추가, 실제 빌드에서 확인된 에러] `you may be able to install
  zlib using your system-packager: brew install zlib` — `libz-sys` crate(어떤
  하위 의존성이 `flate2`/`zlib` 계열 압축 백엔드를 요구할 때 끼어드는 C
  바인딩)의 빌드 스크립트가 `pkg-config`로 zlib을 못 찾을 때 나는 메시지입니다.
  macOS는 Xcode SDK에 `libz.dylib`/`zlib.h`는 들어 있지만 pkg-config가 읽는
  `.pc` 메타데이터 파일은 없어서 생깁니다. 고치는 순서:
  1. `brew install zlib` (에러 메시지가 알려주는 그대로).
  2. Homebrew의 `zlib`은 keg-only(macOS 자체 zlib과 충돌 방지 위해 `/opt/
     homebrew`나 `/usr/local`에 자동으로 안 걸림)라 `pkg-config`가 여전히
     못 찾을 수 있습니다 — `PKG_CONFIG_PATH`를 명시적으로 잡아 줘야 합니다:
     ```bash
     export PKG_CONFIG_PATH="$(brew --prefix zlib)/lib/pkgconfig:$PKG_CONFIG_PATH"
     ```
  3. `pkg-config` 자체가 없으면(`brew list pkg-config`로 확인) `brew install
     pkg-config`도 필요합니다.
  4. 이 스크립트를 Xcode의 "Run Script" 빌드 단계로 돌리고 있다면, Xcode의
     Run Script는 터미널 셸 설정(`~/.zshrc` 등)을 상속하지 않아 2번에서 잡은
     `PKG_CONFIG_PATH`가 안 보일 수 있습니다 — 이 경우 `build-macos-lib.sh`
     맨 위(또는 Run Script 내용 맨 위)에 `export PKG_CONFIG_PATH="$(/opt/
     homebrew/bin/brew --prefix zlib)/lib/pkgconfig"`처럼 절대 경로로 직접
     추가하는 편이 안전합니다(Intel Mac이면 `/usr/local/bin/brew`).
  5. 위 조치 후 `cd native/docxide-pdf-ffi && ./build-macos-lib.sh`(또는
     터미널에서 직접 `cargo build --release --target aarch64-apple-darwin`)를
     다시 실행합니다.

## Xcode 연동

1. **파일 추가**: `dist/libdocxide_pdf_ffi.a`와 `include/docxide_pdf_ffi.h`를
   Xcode 프로젝트로 드래그해 추가합니다(예: `JBCHBibleResearch/Native/` 같은
   새 그룹). "Copy items if needed" 체크.

2. **브리징 헤더 추가**: 이 프로젝트엔 지금까지 브리징 헤더가 없었습니다(직접
   확인함). `JBCHBibleResearch/JBCHBibleResearch-Bridging-Header.h` 새 파일을
   만들고 안에 한 줄만 넣습니다.

   ```objc
   #import "docxide_pdf_ffi.h"
   ```

   그다음 앱 타깃의 Build Settings → **Objective-C Bridging Header**에
   `JBCHBibleResearch/JBCHBibleResearch-Bridging-Header.h` 경로를 입력합니다.
   이렇게 하면 `docxide_pdf_convert`/`docxide_pdf_free_string`이 어떤 Swift
   파일에서든 `import` 없이 바로 보입니다.

3. **macOS 전용으로 스코프**(⚠️ 이 단계가 "iOS는 처리 안 되는 걸 막는다"는
   요청의 핵심입니다 — 안 하면 iOS 빌드가 이 라이브러리를 찾다가 실패하거나,
   찾더라도 빌드에 불필요하게 끼어듭니다):
   - Build Settings에서 **Library Search Paths**와 **Header Search Paths**를
     macOS 전용 조건부 설정으로 넣습니다 — 설정 값 옆의 플랫폼 스코프
     드롭다운(`Any macOS SDK`)을 골라 macOS 빌드에서만 적용되게 합니다
     (`LIBRARY_SEARCH_PATHS[sdk=macosx*]`처럼 표시됨).
   - **Other Linker Flags**에 `-ldocxide_pdf_ffi`도 같은 방식으로 macOS
     SDK 전용으로만 추가합니다.
   - 브리징 헤더 자체(`#import "docxide_pdf_ffi.h"`)는 모든 플랫폼에
     그대로 둬도 괜찮습니다 — 헤더 선언만 있고 실제 링크가 macOS에서만
     일어나므로, `DocxToPDFConverter.swift`(다음 단계) 쪽의 `#if os(macOS)`
     가드가 실제 호출을 막아 주는 한 iOS 빌드는 이 심볼들을 아예 참조하지
     않습니다.

4. **Swift 래퍼**: `DocumentUploadService.swift`/`DocumentViewerViewModel
   .swift`가 쓰는 `DocxToPDFConverter`(JBCHBibleResearch/Services/Documents/
   DocxToPDFConverter.swift)가 위 두 C 함수를 안전한 Swift API로 감싸 둡니다
   — 이 파일 자체가 `#if os(macOS)`로 감싸져 있어 iOS 빌드에선 통째로
   빠집니다.
