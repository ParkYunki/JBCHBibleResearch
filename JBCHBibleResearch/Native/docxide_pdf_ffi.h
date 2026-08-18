/*
 * docxide_pdf_ffi.h
 *
 * [2026-08-16 신설] docxide-pdf-ffi(Rust staticlib)가 노출하는 C ABI 전체.
 * Swift 쪽은 이 헤더를 브리징 헤더(JBCHBibleResearch-Bridging-Header.h)에서
 * #import하면 아래 두 함수가 Swift에서 바로 보인다 — 별도 모듈 import 불필요.
 *
 * ⚠️ 이 헤더는 macOS 타깃에만 링크되도록 Xcode 빌드 설정(Header/Library
 * Search Paths, Other Linker Flags)을 macOS 전용으로 스코프해야 한다 —
 * 사용자 요청("iOS상에서는 처리가 안되는 파일 업로드를 막으면 됨")에 따라
 * iOS 빌드는 이 라이브러리 자체가 안 보여야 한다. 자세한 설정 방법은
 * native/docxide-pdf-ffi/README.md 참고.
 */

#ifndef DOCXIDE_PDF_FFI_H
#define DOCXIDE_PDF_FFI_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * DOCX 바이트를 읽어 `output_path`(NUL 종단 UTF-8 경로 문자열)에 PDF 파일을
 * 씁니다. 성공하면 true를 반환합니다.
 *
 * 실패하면 false를 반환하고, `error_out`이 NULL이 아니면 새로 할당한
 * NUL 종단 에러 메시지 문자열을 `*error_out`에 씁니다 — 호출자는 이 문자열을
 * 정확히 한 번 `docxide_pdf_free_string`으로 해제해야 합니다(메모리 누수
 * 방지). 성공 시에는 `*error_out`을 건드리지 않습니다.
 *
 * - docx_ptr/docx_len: 입력 DOCX 파일 바이트(읽기 전용, 호출자 소유,
 *   이 함수 호출이 끝날 때까지만 유효하면 됩니다).
 * - output_path_ptr: PDF를 쓸 경로(NUL 종단 UTF-8, 호출자 소유).
 */
bool docxide_pdf_convert(const unsigned char *docx_ptr,
                          size_t docx_len,
                          const char *output_path_ptr,
                          char **error_out);

/*
 * `docxide_pdf_convert`가 `error_out`에 써 준 에러 메시지 문자열을 해제합니다.
 * NULL을 넘기면 아무 일도 하지 않습니다(안전).
 */
void docxide_pdf_free_string(char *s);

#ifdef __cplusplus
}
#endif

#endif /* DOCXIDE_PDF_FFI_H */
