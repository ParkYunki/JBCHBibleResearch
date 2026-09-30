//
//  DocxToPDFConverter.swift
//  JBCHBibleResearch
//
//  docxide-pdf(Rust, https://github.com/sverrejb/docxide-pdf)를 감싼 C ABI(native/docxide-pdf-ffi의
//  `docxide_pdf_convert`/`docxide_pdf_free_string`, 브리징 헤더로 노출)를 안전한 Swift API로 감싸
//  docx를 PDF로 변환한다.
//
//  ⚠️ macOS 전용 — docxide-pdf는 macOS/Linux/Windows 시스템 폰트 디렉터리에서 폰트를 찾으며 iOS는
//  지원 대상이 아니다(문서에 폰트가 임베드돼 있지 않으면 텍스트가 깨질 위험). 그래서 파일 전체를
//  `#if os(macOS)`로 감싸 iOS 빌드에서는 컴파일되지 않는다. Xcode 빌드 설정(Library/Header Search
//  Paths, Other Linker Flags)도 macOS SDK 전용으로 스코프해야 한다.
//
//  변환은 업로드 시점에 한 번만 실행해 `ConvertedPDF` 레코드로 남긴다(hwp/hwpx와 같은 파이프라인 —
//  `DocumentUploadService.generateConvertedPDF`). 이 파일은 "변환"만 책임진다.
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

    /// `docxData`(docx 파일 바이트)를 읽어 `outputURL`에 PDF를 쓴다. `outputURL`은 `.pdf`로 끝나야 한다
    /// (docxide-pdf가 내부적으로 `.with_extension("pdf")`를 강제한다).
    /// 렌더링은 전부 Rust 쪽이 담당하고, 이 함수는 바이트 포인터 전달과 실패 시 에러 문자열을 읽은 뒤
    /// `docxide_pdf_free_string`으로 반드시 해제하는 것(누수 방지)만 책임진다.
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
