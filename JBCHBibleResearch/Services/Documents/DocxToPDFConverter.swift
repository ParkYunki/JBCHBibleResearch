//
//  DocxToPDFConverter.swift
//  JBCHBibleResearch
//
//  [2026-08-16 신설] 사용자 요청 — "docxide-pdf + PDFKit로 docx를 pdf로
//  변환하는 것을 검토할 것" → "진행할 것. iOS상에서는 처리가 안되는 파일
//  업로드를 막으면 됨." docxide-pdf(https://github.com/sverrejb/docxide-pdf,
//  Rust, Apache-2.0, Word 출력과 SSIM 90%대까지 맞추는 고품질 렌더러)를 감싼
//  C ABI(native/docxide-pdf-ffi, `docxide_pdf_convert`/`docxide_pdf_free_string`
//  — 브리징 헤더로 노출됨, 어떤 Swift 파일에서든 import 없이 바로 보임)를
//  안전한 Swift API로 감싼다.
//
//  ⚠️ macOS 전용 — docxide-pdf는 폰트를 macOS/Linux/Windows의 시스템 폰트
//  디렉터리를 훑어 찾는다(README에 명시, iOS는 언급조차 없음). 문서에 폰트가
//  임베드돼 있지 않으면 iOS에서 텍스트가 깨지거나 안 나올 위험이 있어,
//  사용자가 "iOS는 처리가 안 되는 걸 막으면 된다"고 결정했다 — 그래서 이
//  파일 전체를 `#if os(macOS)`로 감싸 iOS 빌드에서 아예 컴파일되지 않는다.
//  Xcode 빌드 설정(Library/Header Search Paths, Other Linker Flags)도 macOS
//  SDK 전용으로 스코프해야 한다 — native/docxide-pdf-ffi/README.md "Xcode
//  연동" 절 참고.
//
//  변환은 업로드 시점에 한 번만 실행해 `ConvertedPDF` 레코드로 남긴다
//  (hwp/hwpx가 이미 쓰던 것과 똑같은 모델·같은 파이프라인 —
//  `DocumentUploadService.generateConvertedPDF` 참고). 그 PDF는
//  `DocumentViewerView`의 `.docx` 원본 탭에서 이미 있는 `PDFKitRepresentable`
//  + `pdfSearchBar`(PDF/hwp 탭이 쓰는 것과 동일)로 그대로 열람·검색된다 —
//  이 파일은 "변환"만 책임지고, 뷰어 쪽 재사용은 별도 커밋(DocumentViewerView.swift
//  참고).
//

#if os(macOS)
import Foundation

enum DocxToPDFConverter {
    enum ConversionError: LocalizedError {
        case invalidInput
        case underlying(String)

        var errorDescription: String? {
            switch self {
            case .invalidInput:
                return "docx → PDF 변환 실패: 입력 데이터가 비어 있습니다."
            case .underlying(let message):
                return "docx → PDF 변환 실패: \(message)"
            }
        }
    }

    /// `docxData`(원본 docx 파일 바이트)를 읽어 `outputURL`에 PDF를 쓴다.
    /// `outputURL`은 `.pdf` 확장자로 끝나야 한다 — 안 그래도 docxide-pdf가
    /// 내부적으로 `.with_extension("pdf")`를 강제하지만(Rust 쪽 소스 확인),
    /// 헷갈리지 않게 호출부가 처음부터 `.pdf`로 넘기는 편이 안전하다.
    ///
    /// 실제 변환/렌더링(텍스트 배치, 표, 이미지, 폰트 임베딩 등)은 전부
    /// Rust 쪽(docxide-pdf)이 담당한다 — 이 함수는 바이트 포인터를 안전하게
    /// 넘기고, 실패 시 에러 문자열을 읽어 온 뒤 반드시 해제하는 것만
    /// 책임진다(메모리 누수 방지 — `docxide_pdf_free_string` 호출).
    static func convert(docxData: Data, outputURL: URL) throws {
        guard !docxData.isEmpty else {
            throw ConversionError.invalidInput
        }

        var errorPointer: UnsafeMutablePointer<CChar>?

        let success = docxData.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) -> Bool in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return false
            }
            return outputURL.path.withCString { pathPointer in
                docxide_pdf_convert(baseAddress, rawBuffer.count, pathPointer, &errorPointer)
            }
        }

        if !success {
            let message: String
            if let errorPointer {
                message = String(cString: errorPointer)
                docxide_pdf_free_string(errorPointer)
            } else {
                message = "알 수 없는 오류"
            }
            throw ConversionError.underlying(message)
        }
    }
}
#endif
