//! [2026-08-16 신설] docxide-pdf(https://github.com/sverrejb/docxide-pdf,
//! Apache-2.0)를 감싸는 아주 얇은 C ABI 어댑터. 이 파일의 유일한 목적은
//! `docxide_pdf::convert_docx_bytes_to_pdf(input: &[u8], path: impl AsRef<Path>)
//! -> Result<(), Error>`(실제 crate 소스 src/lib.rs를 직접 읽어 확인한
//! 시그니처 — README 예제만 보고 추측하지 않았다)를 Swift가 부를 수 있는
//! `extern "C"` 함수로 바꾸는 것뿐이다. 변환 로직 자체는 전부 docxide-pdf가
//! 담당한다.
//!
//! ⚠️ 이 파일은 Rust 툴체인이 없는 샌드박스에서 작성돼 `cargo build`로
//! 컴파일 검증을 못 했다. 문법은 표준적인 Rust FFI 관용구(CString::into_raw/
//! from_raw 쌍, slice::from_raw_parts)를 따랐지만, 실제 빌드 시 사소한
//! 오류가 있을 수 있다는 점을 감안하고 진행할 것 — README.md의 "빌드가 실패
//! 하면" 절 참고.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::Path;
use std::slice;

/// DOCX 바이트를 읽어 `output_path_ptr`(NUL 종단 UTF-8 경로)에 PDF 파일을
/// 쓴다. 성공하면 `true`.
///
/// 실패하면 `false`를 반환하고, `error_out`이 널이 아니면 새로 할당한 에러
/// 메시지를 `*error_out`에 채운다 — Swift 쪽은 이 문자열을 반드시
/// `docxide_pdf_free_string`으로 해제해야 한다(그렇지 않으면 누수).
///
/// # Safety
/// `docx_ptr`는 `docx_len`바이트만큼 유효해야 하고, `output_path_ptr`는
/// NUL로 끝나는 유효한 UTF-8 C 문자열이어야 한다 — 둘 다 이 함수가 반환할
/// 때까지만 유효하면 된다(이 함수는 두 포인터를 보관하지 않는다).
#[no_mangle]
pub extern "C" fn docxide_pdf_convert(
    docx_ptr: *const u8,
    docx_len: usize,
    output_path_ptr: *const c_char,
    error_out: *mut *mut c_char,
) -> bool {
    if docx_ptr.is_null() || docx_len == 0 || output_path_ptr.is_null() {
        write_error(error_out, "invalid arguments (null pointer or empty input)");
        return false;
    }

    // SAFETY: 호출자(Swift)가 이 함수 호출이 끝날 때까지 `docx_ptr`가
    // `docx_len`바이트만큼 유효함을 보장해야 한다 — 위 헤더 주석(docxide_pdf_ffi.h)
    // 에 명시.
    let input: &[u8] = unsafe { slice::from_raw_parts(docx_ptr, docx_len) };

    // SAFETY: 호출자가 `output_path_ptr`가 NUL로 끝나는 유효한 포인터임을
    // 보장해야 한다 — 위와 같은 이유.
    let path_cstr = unsafe { CStr::from_ptr(output_path_ptr) };
    let path_str = match path_cstr.to_str() {
        Ok(s) => s,
        Err(_) => {
            write_error(error_out, "output path is not valid UTF-8");
            return false;
        }
    };

    match docxide_pdf::convert_docx_bytes_to_pdf(input, Path::new(path_str)) {
        Ok(()) => true,
        Err(e) => {
            write_error(error_out, &e.to_string());
            false
        }
    }
}

/// `docxide_pdf_convert`가 `error_out`에 써 준 문자열을 해제한다. 널을
/// 넘기면 아무 일도 하지 않는다.
///
/// # Safety
/// `s`는 `docxide_pdf_convert`가 반환한 포인터여야 하고, 각 포인터는 정확히
/// 한 번만 이 함수에 넘겨야 한다(중복 해제 금지).
#[no_mangle]
pub extern "C" fn docxide_pdf_free_string(s: *mut c_char) {
    if s.is_null() {
        return;
    }
    // SAFETY: `s`가 `CString::into_raw`로 만들어진 포인터라는 보장은 호출자
    // 책임(위 문서화한 대로 이 라이브러리 자신이 만든 포인터만 여기로 와야
    // 한다). `CString::from_raw`가 소유권을 되찾아 스코프 끝에서 드롭시켜
    // 해제한다.
    unsafe {
        let _ = CString::from_raw(s);
    }
}

/// `error_out`이 널이 아니면 `message`를 새 `CString`으로 할당해 채운다.
/// `message`에 내부 NUL 바이트가 있는(있을 리 거의 없지만 방어적으로 처리)
/// 경우를 대비해 `CString::new`가 실패하면 고정 문구로 대체한다.
fn write_error(error_out: *mut *mut c_char, message: &str) {
    if error_out.is_null() {
        return;
    }
    let c_message = CString::new(message)
        .unwrap_or_else(|_| CString::new("(error message contained a NUL byte)").unwrap());
    // SAFETY: `error_out`이 널이 아님을 위에서 확인했고, 유효한 `*mut c_char`
    // 쓰기 대상이라는 보장은 호출자(Swift) 책임 — 위 헤더 주석 참고.
    unsafe {
        *error_out = c_message.into_raw();
    }
}
