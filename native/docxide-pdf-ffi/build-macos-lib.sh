#!/bin/bash
#
# [2026-08-16 신설] docxide-pdf-ffi를 macOS용 유니버설(arm64+x86_64) 정적
# 라이브러리로 빌드한다. Xcode는 Rust 코드를 직접 빌드하지 못하므로, 이
# 스크립트를 Rust 소스나 docxide-pdf 의존성 버전이 바뀔 때마다 "사용자가
# 직접" 실행해 결과물(libdocxide_pdf_ffi.a)을 새로 만들어야 한다 — Xcode
# 빌드 자체는 이 스크립트를 자동으로 호출하지 않는다.
#
# 사전 준비: rustup 설치(https://rustup.rs) 후 아래 타깃 추가.
#   rustup target add aarch64-apple-darwin x86_64-apple-darwin
#
# 사용법: native/docxide-pdf-ffi 디렉터리에서
#   ./build-macos-lib.sh
# 결과물: dist/libdocxide_pdf_ffi.a (lipo로 합친 유니버설 바이너리)
#         + include/docxide_pdf_ffi.h를 그대로 Xcode 프로젝트에 추가하면 됨.
#
# ⚠️ iOS 타깃은 의도적으로 안 만든다 — 사용자 요청("iOS상에서는 처리가
# 안되는 파일 업로드를 막으면 됨")에 따라 이 변환 기능은 macOS 전용이다.

set -euo pipefail
cd "$(dirname "$0")"

if ! command -v cargo >/dev/null 2>&1; then
    echo "오류: cargo(Rust 툴체인)를 찾을 수 없습니다. https://rustup.rs 에서 설치하세요." >&2
    exit 1
fi

# [2026-08-17 추가, 실제 빌드에서 확인된 에러 대응] docxide-pdf의 하위 의존성
# 중 하나가 압축 백엔드로 `libz-sys`(zlib C 바인딩)를 요구하면, macOS는
# libz.dylib/zlib.h는 있어도 pkg-config용 .pc 메타데이터가 없어 빌드가
# "you may be able to install zlib using your system-packager: brew install
# zlib" 에러로 멈춘다(README.md "빌드가 실패하면" 절 참고). `brew`가 있고
# zlib이 이미 설치돼 있으면(keg-only라 PATH/PKG_CONFIG_PATH에 자동으로 안
# 잡힘) 여기서 미리 `PKG_CONFIG_PATH`를 잡아 둔다 — zlib이 아직 없으면 이
# 블록은 조용히 건너뛰고, 그 경우 사용자가 README 안내대로 `brew install
# zlib`을 먼저 실행해야 한다.
if command -v brew >/dev/null 2>&1 && zlib_prefix="$(brew --prefix zlib 2>/dev/null)"; then
    export PKG_CONFIG_PATH="${zlib_prefix}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
    echo "== zlib pkg-config 경로 설정: ${zlib_prefix}/lib/pkgconfig =="
fi

rustup target add aarch64-apple-darwin x86_64-apple-darwin

echo "== aarch64-apple-darwin(Apple Silicon) 빌드 =="
cargo build --release --target aarch64-apple-darwin

echo "== x86_64-apple-darwin(Intel) 빌드 =="
cargo build --release --target x86_64-apple-darwin

mkdir -p dist
lipo -create \
    target/aarch64-apple-darwin/release/libdocxide_pdf_ffi.a \
    target/x86_64-apple-darwin/release/libdocxide_pdf_ffi.a \
    -output dist/libdocxide_pdf_ffi.a

echo ""
echo "완료: dist/libdocxide_pdf_ffi.a (arm64+x86_64 유니버설)"
lipo -info dist/libdocxide_pdf_ffi.a
echo ""
echo "다음 단계는 native/docxide-pdf-ffi/README.md의 'Xcode 연동' 절을 참고하세요."
