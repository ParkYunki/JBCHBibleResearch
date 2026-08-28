//
//  DocumentUploadService.swift
//  JBCHBibleResearch
//
//  screens.md 14.1 — 업로드 직후 SourceDocument 생성(형식 공통). S5의 "업로드"
//  버튼(툴바), 드래그앤드롭, 드롭존 클릭 세 진입점이 모두 이 서비스 하나를
//  공유한다(스펙 "3가지 진입점이 같은 함수 호출, 중복 구현 방지").
//
//  ⚠️ [불확실, 확인 필요] `file_bookmark`(security-scoped bookmark) 생성 옵션은
//  macOS/iOS가 다르다 — macOS 샌드박스 앱은 `.withSecurityScope`가 필요하고, iOS는
//  `UIDocumentPickerViewController`/`fileImporter`가 넘겨주는 URL 자체가 이미
//  임시로 보안 스코프가 열린 상태라 옵션 없이 bookmarkData만 떠도 된다고 알려져
//  있다(플랫폼별 분기, `#if os(macOS)`). 실제 기기에서 "다른 세션에 앱을 다시 열었을
//  때도 파일에 접근되는지" 검증이 안 됐다 — schema.md addendum 3장이 이미 명시한
//  미검증 리스크와 같은 항목이다.
//
//  ⚠️ [범위, 확인 필요] `storage_location_kind` 판별은 파일 경로 문자열에 의존하는
//  휴리스틱이다(iCloud Drive 컨테이너 경로 패턴 매칭) — 정확한 판별 규칙이 스펙에
//  없어 가장 단순한 추정으로 구현했다. iCloud Drive 저장이 실패해 폴백할 때만 이
//  휴리스틱을 쓴다(아래 "iCloud Drive 저장" 섹션 참고).
//
//  [2026-08-11 추가] 사용자 요청 — "연구문서 원본/OCR 이미지를 실제로 iCloud
//  드라이브의 'JBCH 성경 연구' 폴더 아래에 저장할 것"(환경설정 화면 저장공간 탭
//  안내 문구를 그 경로로 바꾸면서 확인된 요청 — 문구만이 아니라 실제 동작도
//  바꾸는 쪽을 선택했다). 이제 업로드 시 원본을 그 자리에 그대로 두지 않고,
//  이 앱의 iCloud 컨테이너(Documents 폴더, CloudKit과 같은 컨테이너 식별자를
//  재사용) 아래 "JBCH 성경 연구/연구 문서"(이미지가 아닌 형식) 또는 "JBCH 성경
//  연구/OCR 이미지"(이미지 형식) 하위 폴더로 복사한다 — "이동"이 아니라 "복사"다
//  (사용자가 원본 파일을 다른 용도로 계속 쓸 수 있으므로 원본을 지우지 않는다).
//
//  ⚠️ [2026-08-15 되돌림] 한때 이 컨테이너를 Finder의 "iCloud Drive"에 사용자가
//  직접 볼 수 있는 공개 폴더로 노출했다가(그때는 컨테이너 자체가 Finder에
//  "JBCH 성경 연구"로 보이므로 이 경로의 같은 이름 세그먼트를 없앴었다), 사용자
//  판단으로 다시 비공개로 되돌렸다 — "괜히 공개했다가 사용자가 마음대로 폴더
//  파일을 추가하거나, 삭제하는 것보다 나음"(Finder에서 직접 건드리면
//  `SourceDocument.fileBookmark`가 가리키는 파일이 깨질 수 있음). 그래서 이
//  경로도 원래 구조("JBCH 성경 연구" 세그먼트 포함)로 함께 되돌렸다 — `Info.plist`
//  상단 주석 참고.
//
//  [2026-08-16 수정] 사용자 지적 — 컨테이너가 비공개로 되돌아간 뒤에도 그
//  "JBCH 성경 연구" 세그먼트까지 같이 되돌아온 건 잘못이었다. 이 컨테이너
//  (`iCloud~com~jbch~JBCHBibleResearch`) 자체가 이미 앱 전용이라, 그 안에서
//  또 "JBCH 성경 연구"로 한 번 더 감쌀 이유가 없다(공개 노출 여부와는 별개
//  문제). 실제 디스크 경로가 `.../Documents/JBCH 성경 연구/연구 문서`가 아니라
//  `.../Documents/연구 문서`여야 한다는 지적을 받아 그 세그먼트를 없앴다 —
//  아래 `copyIntoICloudDocuments`와 `SettingsView.swift`의 표시 문구를 함께
//  고쳤다. 이미 업로드된 기존 문서는 예전 경로에 그대로 남아 있고 계속
//  정상적으로 열린다(`fileBookmark`가 실제 위치를 직접 가리키므로).
//
//  ⚠️ [필수 확인 사항, Xcode에서 직접 처리해야 함] 이 세션은 Xcode의 Signing &
//  Capabilities 화면을 열 수 없다 — `JBCHBibleResearch.entitlements`에
//  `com.apple.developer.ubiquity-container-identifiers` 키를 직접 추가해 뒀지만,
//  실제로 iCloud Drive에 저장되려면 사용자가 Xcode에서 "iCloud" capability의
//  "iCloud Documents" 항목이 켜져 있는지 확인/재적용해야 한다(프로비저닝
//  프로파일 갱신 필요). 이 capability가 반영되지 않으면
//  `FileManager.url(forUbiquityContainerIdentifier:)`가 nil을 돌려주고, 아래
//  로직은 앱이 멈추지 않도록 조용히 기존 방식(원본 위치 참조)으로 폴백한다.
//

import Foundation
import SwiftData
import UniformTypeIdentifiers
import PDFKit
import BibleResearchModels

enum DocumentUploadError: Error, CustomStringConvertible {
    case unsupportedFormat(String)
    case securityScopedAccessFailed
    case bookmarkCreationFailed(String)
    /// [2026-08-11 추가] iCloud Drive 컨테이너를 쓸 수 없을 때(iCloud 로그인
    /// 안 됨, capability 미설정 등) — `createSourceDocument`는 이 에러를 잡아서
    /// 기존 방식(원본 위치 참조)으로 폴백하므로, 사용자에게 직접 노출되는 경우는
    /// 거의 없다(콘솔 로그로만 남는다).
    case iCloudContainerUnavailable

    var description: String {
        switch self {
        case .unsupportedFormat(let ext):
            return "지원하지 않는 파일 형식입니다(.\(ext))."
        case .securityScopedAccessFailed:
            return "파일에 접근할 권한을 얻지 못했습니다."
        case .bookmarkCreationFailed(let message):
            return "파일 위치를 저장하지 못했습니다: \(message)"
        case .iCloudContainerUnavailable:
            return "iCloud Drive를 사용할 수 없습니다 — iCloud 로그인 상태와 저장공간을 확인해주세요."
        }
    }
}

@MainActor
enum DocumentUploadService {
    /// [2026-08-16 추가] 사용자 질문 — "HWP 파일만 동기화 폴더에 저장되지 않는
    /// 이유는?" 조사해 보니, `copyIntoICloudDocuments`가 실패했을 때(iCloud
    /// 미로그인, capability 미설정, 그 파일 특유의 접근 권한 문제 등) 지금까지는
    /// 콘솔에만 로그를 남기고 조용히 원본 위치를 그대로 참조하는 방식으로
    /// 폴백했다 — 업로드 자체는 "성공"으로 보이니 사용자는 실패 사실 자체를 알
    /// 방법이 없었다. `createSourceDocument`가 폴백할 때 그 실패 사유를 여기
    /// 잠깐 담아 두고, 호출부(`DocumentsViewModel.upload`)가 읽어서 사용자에게
    /// 알림으로 보여준다(다음 업로드 시도 때 갱신되거나 성공 시 nil로 지워진다).
    static private(set) var lastICloudCopyFailureReason: String?

    /// 14.2 표에 따른 지원 형식.
    ///
    /// [2026-08-16 재확인, pages 여전히 제외 → 같은 날 다시 번복, 지원으로 확정]
    /// 사용자 요청 — "pages 업로드 지원 확인(텍스트 추출/미리보기 검색 포함)."
    /// 처음엔 신뢰할 만한 크로스플랫폼 Swift 파서를 못 찾아 v1 제외 결정을
    /// 유지하기로 했었다(직접 웹 검색·리버스엔지니어링 문서까지 확인). 그런데
    /// 사용자가 "SwiftText(docx에 이미 쓴 그 패키지)가 pages도 파싱할 수 있다"며
    /// 재확인을 요청했고, 실제로 그 저장소의 `Sources/SwiftTextPages/
    /// PagesFile.swift` 소스를 직접 읽어 확인한 결과 — Snappy 블록 해제와
    /// protobuf 와이어 디코딩까지 패키지 안에 순수 Swift로 구현돼 있어 Apple
    /// 프레임워크도 Pages.app도 필요 없고, macOS/iOS 모두 동작한다(README
    /// 주장을 소스 코드로 직접 검증 — Package.swift만 훑어봤던 앞선 조사에서
    /// 놓쳤던 모듈). 그래서 지원 형식에 추가한다 — 자세한 추출 경위는
    /// DocumentTextExtractionService.swift의 `extractPages` 참고.
    ///
    /// [2026-08-16 `docx` 추가, 2026-08-25 `doc`/`docx` 업로드 차단으로 번복]
    /// 사용자가 "13데살로니가전서(황종순).docx" 실사례로 보고한 "인스펙터
    /// 연구문서 검색창에서 성경과 장 사이 공백이 사라져 검색이 안 된다" 버그를
    /// 조사한 결과 — 원본 docx의 `word/document.xml`(zip 내부 XML 직접 확인),
    /// 그 문서를 변환한 PDF의 텍스트 레이어(pdfplumber로 글자 단위 폰트/좌표까지
    /// 확인), `VerseMention.searchText` 추출 경로(`BibleReferenceExtractor`),
    /// `PDFSearchController`/`PDFKitRepresentable`의 document/pdfView 대입
    /// 순서, `DocumentViewerViewModel.onAppear()`의 동기 실행 여부까지 — 이 앱
    /// 코드가 만지는 모든 지점을 직접 파일 바이트/문자 단위로 검증했지만 전부
    /// 깨끗했다. 유일하게 직접 들여다볼 수 없는 지점은 `.docx → PDF` 변환을
    /// 전담하는 서드파티 Rust 라이브러리 docxide-pdf(`DocxToPDFConverter.swift`)
    /// 뿐이었고, 사용자가 "라이브러리의 버그로 보임. 라이브러리가 개선될때까지는
    /// docx doc 업로드 기능을 막을 것"이라고 명시적으로 지시했다.
    ///
    /// 그래서 `.docx`뿐 아니라 `.doc`도 함께 막는다 — `.doc`은 docxide-pdf를
    /// 쓰지 않지만(macOS AppKit `NSAttributedString(.docFormat)` 경로, 위
    /// 예전 주석대로 iOS 지원 여부조차 "확인 안 됨"으로 남아 있던 형식이라
    /// 어차피 신뢰도가 낮았다), 사용자가 "docx doc" 둘 다 명시했으므로 함께
    /// 막는다. `.pages`는 이번 조사·지시 대상이 아니었고 별도의 순수 Swift
    /// 파서(SwiftTextPages)를 쓰므로 그대로 둔다.
    ///
    /// 이미 업로드된 기존 `.doc`/`.docx` 문서는 이 목록과 무관하게 계속 열람·
    /// 검색 가능하다(`SourceDocument.originalFormat`, `DocxToPDFConverter`,
    /// `DocumentTextExtractionService` 등은 그대로 둠) — 이 함수는 파일 선택기
    /// (Finder 열기 다이얼로그)에 노출되는 "새로 고를 수 있는 형식" 목록만
    /// 제어한다. 드래그앤드롭 경로는 이 목록을 거치지 않으므로
    /// `createSourceDocument`의 확장자 스위치에서 별도로 막는다(아래 참고).
    // [2026-08-28 `pages` 업로드 차단으로 재번복] 사용자 요청 — "연구문서 업로드시
    // pages 파일 차단할 것(hwp, pdf 파일만 업로드 가능하도록)." 위 2026-08-16 결정
    // (SwiftTextPages 소스 코드까지 직접 확인해 "지원 확정")을 다시 번복한다 —
    // 이번엔 파서 신뢰도 문제가 아니라 사용자가 업로드 가능한 "연구문서" 형식
    // 자체를 hwp/pdf로 좁히기로 한 명시적 정책 결정이다. 이미지(jpg/png/heic)는
    // 이 함수가 같이 다루긴 하지만 "연구문서"가 아니라 별도 기능인 "OCR
    // 이미지" 업로드(DocumentsHomeView.swift "문서·OCR" 탭)라 사용자가 이번
    // 차단 범위에서 명시적으로 제외했다 — 그대로 둔다.
    //
    // `.doc`/`.docx`를 막을 때와 같은 방식 — 파일 선택기 목록에서만 빼고
    // (`createSourceDocument`의 스위치 문에서도 함께 막는다, 아래 참고),
    // `OriginalFormat.pages`/`DocumentTextExtractionService.extractPages`
    // 자체는 그대로 둔다 — 이미 업로드된 기존 `.pages` 문서는 계속 열람·검색
    // 가능해야 한다.
    static func supportedContentTypes(allowHWP: Bool) -> [UTType] {
        var types: [UTType] = [.pdf, .jpeg, .png, .heic]
        if allowHWP {
            // hwp/hwpx는 표준 UTType이 없어 확장자 기반으로 직접 선언한다.
            if let hwp = UTType(filenameExtension: "hwp") { types.append(hwp) }
            if let hwpx = UTType(filenameExtension: "hwpx") { types.append(hwpx) }
        }
        return types
    }

    /// 3가지 업로드 진입점(툴바 버튼/드래그앤드롭/드롭존 클릭)이 공유하는 단일
    /// 경로. `SourceDocument`를 만들고 컨텍스트에 저장한 뒤, 형식별 텍스트 추출은
    /// 호출부(S5 화면)가 `DocumentTextExtractionService`로 이어서 트리거한다 —
    /// 이 함수 자체는 "업로드 접수"까지만 책임진다(14.1/14.2의 책임 분리 그대로).
    /// [2026-08-08 추가] `relatedChapterRef` — 업로드 확인 시트에서 사용자가 "이
    /// 문서는 OO장에 관한 것"이라고 지정했으면 그대로 넘어온다(건너뛰면 nil,
    /// DocumentsHomeView.swift 참고). 이 함수는 그 값을 그대로 모델에 실어 나를
    /// 뿐 검증하지 않는다 — 책/장 유효성은 호출부가 `BookChapterPicker`로 이미
    /// 보장한다.
    /// [2026-08-18 추가] `category` — 사용자 요청 "연구문서 업로드시 반드시
    /// 카테고리 입력을 강제할 것." 실제 "반드시"는 호출부(`DocumentsHomeView`의
    /// 업로드 확인 시트)가 카테고리를 고르기 전엔 업로드 버튼 자체를 비활성화하는
    /// 방식으로 강제한다 — 이 함수/`SourceDocument.category` 자체는 여전히
    /// 옵셔널로 둔다(모델 레이어까지 non-optional로 강제하면 이 함수를 거치는
    /// 다른 경로가 생길 때마다 항상 카테고리를 준비해야 하는 불필요한 경직성이
    /// 생긴다 — UI 정책과 데이터 제약을 분리하는 이 프로젝트의 기존 원칙).
    static func createSourceDocument(
        from url: URL, context: ModelContext, relatedChapterRef: BibleChapterRef? = nil, category: ImageCategory? = nil
    ) throws -> SourceDocument {
        let ext = url.pathExtension.lowercased()
        let format: OriginalFormat
        switch ext {
        case "hwp": format = .hwp
        case "hwpx": format = .hwpx
        case "pdf": format = .pdf
        // [2026-08-25 제거] `.doc`/`.docx` 업로드 차단 — 위
        // `supportedContentTypes(allowHWP:)` 주석 참고. 파일 선택기는
        // 이미 목록에서 뺐지만, 드래그앤드롭(`DropZoneModifier`)은 파일
        // 확장자를 가리지 않고 아무 `.fileURL`이나 이 함수까지 그대로
        // 넘기므로, 실제 차단은 이 스위치가 `default` 분기로 떨어져
        // `DocumentUploadError.unsupportedFormat`을 던지는 지점에서
        // 일어난다 — 기존에 정말 모르는 확장자를 막던 것과 동일한 경로.
        // 이미 업로드된 `.doc`/`.docx` 문서의 `OriginalFormat` 케이스
        // 자체는 그대로 남아 있으므로 기존 문서 열람/검색은 영향 없다.
        // [2026-08-28 제거] `.pages` 업로드 차단 — 위 `supportedContentTypes(allowHWP:)`
        // 주석 참고. `.doc`/`.docx`와 마찬가지로 드래그앤드롭은 이 스위치의
        // `default` 분기(`DocumentUploadError.unsupportedFormat`)에서 막힌다.
        // 이미 업로드된 `.pages` 문서의 `OriginalFormat.pages` 케이스 자체는
        // 그대로 남아 있으므로 기존 문서 열람/검색은 영향 없다.
        case "jpg", "jpeg", "png", "heic", "heif": format = .image
        default:
            throw DocumentUploadError.unsupportedFormat(ext)
        }

        // [2026-08-11 추가, 2026-08-16 docx/pages 추가] 원본을 이 앱의 iCloud
        // Drive 폴더로 복사한다 — 형식이 이미지면 "OCR 이미지", 그 외(pdf/hwp/
        // hwpx/doc/docx/pages)는 "연구 문서" 하위 폴더. 실패하면(iCloud
        // 미로그인/capability 미설정 등) 업로드 자체를 막지 않고 기존 방식(원본
        // 위치 참조 + 휴리스틱 판별)으로 폴백한다.
        let storageURL: URL
        let storageKind: StorageLocationKind
        // [2026-08-18 추가, fileBookmark 기기 간 이식 불가 문제 fix] icloudDrive
        // 저장이 성공한 경우에만 값이 생긴다 — ConvertedPDF.pdfPath와 같은 "컨테이너
        // Documents/ 기준 상대경로" 규칙. `storageURL.lastPathComponent`를 쓰는 이유는
        // `copyIntoICloudDocuments`가 이름이 겹치면 "이름 2.ext"로 바꿔서 돌려줄 수
        // 있어서(url.lastPathComponent가 아니라 실제로 저장된 파일명을 써야 함).
        let subfolder = format == .image ? "OCR 이미지" : "연구 문서"
        var originalFilePath: String?
        do {
            storageURL = try copyIntoICloudDocuments(sourceURL: url, subfolder: subfolder)
            storageKind = .icloudDrive
            originalFilePath = "\(subfolder)/\(storageURL.lastPathComponent)"
            lastICloudCopyFailureReason = nil
        } catch {
            let reason = describe(error)
            print("[DocumentUploadService] iCloud Drive 저장 실패, 원본 위치 참조로 폴백: \(reason)")
            lastICloudCopyFailureReason = reason
            storageURL = url
            storageKind = inferStorageLocationKind(for: url)
        }

        // [2026-08-18 수정] icloudDrive인 경우에도 북마크는 여전히 만들어 둔다 —
        // originalFilePath 계산이 나중에 실패하는 예외적 상황(예: 컨테이너 식별자가
        // 바뀌는 등)에 대비한 이중 안전장치일 뿐, 정상 상황에선 원본 파일 열기에
        // 북마크를 더 이상 쓰지 않는다(resolveOriginalFileURL(for:) 참고).
        let bookmark = try makeSecurityScopedBookmark(for: storageURL)

        let document = SourceDocument(
            originalFilename: url.lastPathComponent,
            originalFormat: format,
            fileBookmark: bookmark,
            originalFilePath: originalFilePath,
            storageLocationKind: storageKind,
            conversionStatus: .pending,
            indexStatus: .notIndexed,
            converterUsed: .none,
            category: category,
            relatedChapterRef: relatedChapterRef,
            uploadedAt: .now
        )
        context.insert(document)
        try context.save()
        return document
    }

    // [2026-08-17 추가, 컴파일러 경고로 발견] `(error as? CustomStringConvertible)?.description
    // ?? error.localizedDescription`이 "Conditional cast from 'any Error' to 'any
    // CustomStringConvertible' always succeeds" 경고를 냈다 — Apple 플랫폼에서는
    // 모든 `Error`가 NSError로 브리징 가능하고 NSError 자체가 CustomStringConvertible을
    // 채택하고 있어 이 캐스팅이 항상 성공하기 때문에, `?? error.localizedDescription`
    // 뒤쪽 분기는 죽은 코드나 다름없었다(실제 오동작은 아니었다 — TranslationImportService.swift
    // `describe(_:)`에 같은 문제가 먼저 발견돼 고쳐진 전례가 있어 그 패턴을 그대로
    // 가져왔다). `LocalizedError.errorDescription`(있으면 더 읽기 좋은 사용자 대상
    // 메시지)을 먼저 확인하고, 없으면 `String(describing:)`(CustomStringConvertible을
    // 채택한 타입이면 그 타입의 `.description`을 그대로 써준다)로 폴백한다 — 의미
    // 없는 캐스팅 경고 없이 같은 동작을 낸다.
    private static func describe(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let message = localized.errorDescription {
            return message
        }
        return String(describing: error)
    }

    // MARK: - hwp/hwpx → PDF 사전 변환 (2026-08-16 신설)

    /// [2026-08-16 신설] 사용자 요청 — "hwp 업로드할 때 pdf를 생성하고 pdf
    /// 파일을 열수 있도록. (같은이름) 기존 데이터는 변환하지 않아도 됨." 업로드
    /// 직후(`DocumentsViewModel.upload`가 텍스트 추출과 같은 Task에서 호출) 한
    /// 번만 `RhwpPDFExportService`로 변환해 두고, `ConvertedPDF` 레코드에
    /// 남긴다 — `HWPToPDFPane`(DocumentViewerView.swift)이 이 레코드가 있으면
    /// 열 때마다 다시 변환하지 않고 이 파일을 바로 연다. 이 함수 자체가 형식을
    /// 확인해서 hwp/hwpx가 아니면 조용히 아무것도 안 하므로, 호출부가 모든
    /// 업로드에 대해 무조건 호출해도 안전하다 — `DocumentTextExtractionService.
    /// extract`를 형식 구분 없이 항상 부르는 것과 같은 패턴.
    ///
    /// 이미 `ConvertedPDF`가 있으면(멱등성 — 재시도/중복 호출에도 다시 안 만듦)
    /// 건너뛴다. 실패해도(WKWebView 문제, iCloud 컨테이너 사용 불가 등) throw
    /// 하지 않고 콘솔 로그만 남긴다 — 업로드 자체는 이미 끝난 뒤라 실패해도 막을
    /// 게 없고, `HWPToPDFPane`이 레코드가 없을 때 즉시-변환 경로로 자동
    /// 대체되므로 사용자 경험이 완전히 막히지는 않는다.
    ///
    /// [2026-08-16 추가] 사용자 요청 — "docxide-pdf + PDFKit로 docx를 pdf로
    /// 변환하는 것을 검토할 것" → "진행할 것." 이 함수는 이제 hwp/hwpx뿐
    /// 아니라 `.docx`(macOS 전용)도 이 자리에서 함께 조율한다 — 호출부
    /// (`DocumentsViewModel.upload`/`retry`)는 형식 구분 없이 항상 이
    /// 함수 하나만 부르면 되는 기존 패턴을 그대로 유지한다.
    static func generateConvertedPDF(for document: SourceDocument, context: ModelContext) async {
        if document.originalFormat == .hwp || document.originalFormat == .hwpx {
            await generateConvertedPDFForHWP(for: document, context: context)
        }
        #if os(macOS)
        if document.originalFormat == .docx {
            await generateConvertedPDFForDocx(for: document, context: context)
        }
        #endif
    }

    private static func generateConvertedPDFForHWP(for document: SourceDocument, context: ModelContext) async {
        guard (document.convertedPDFs ?? []).isEmpty else { return }

        do {
            // [2026-08-18 수정, 기기 간 이식 fix] 북마크 대신 resolveOriginalFileURL —
            // 다른 기기에서 이 변환이 재시도되어도(예: 재시도 버튼) originalFilePath로
            // 원본을 찾을 수 있다.
            let sourceURL = try resolveOriginalFileURL(for: document, context: context)
            let hwpData = try readSecurityScopedData(from: sourceURL)
            let pdfData = try await RhwpPDFExportService().exportPDF(documentData: hwpData)

            guard let containerURL = FileManager.default.url(
                forUbiquityContainerIdentifier: BibleResearchSchema.defaultCloudKitContainerIdentifier
            ) else {
                print("[DocumentUploadService] hwp → PDF 변환은 성공했지만 iCloud 컨테이너를 쓸 수 없어 저장하지 못함: \(document.originalFilename)")
                return
            }

            let subfolder = "연구 문서"
            let folderURL = containerURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(subfolder, isDirectory: true)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

            // "같은 이름" 요청 — hwp 원본과 같은 기본 파일명에 확장자만 .pdf로
            // 바꾼다. 이름이 이미 있으면(드물지만) `uniqueDestinationURL`이
            // "이름 2.pdf" 식으로 비켜 준다(위 `copyIntoICloudDocuments`와
            // 같은 규칙).
            let baseName = (document.originalFilename as NSString).deletingPathExtension
            let destinationURL = uniqueDestinationURL(in: folderURL, filename: baseName + ".pdf")

            var coordinatorError: NSError?
            var writeError: Error?
            NSFileCoordinator().coordinate(
                writingItemAt: destinationURL, options: [], error: &coordinatorError
            ) { writeURL in
                do {
                    try pdfData.write(to: writeURL, options: .atomic)
                } catch {
                    writeError = error
                }
            }
            if let coordinatorError { throw coordinatorError }
            if let writeError { throw writeError }

            // 컨테이너의 실제 절대 디스크 경로는 기기/재설치마다 달라질 수 있어
            // "Documents/" 바로 아래부터의 상대 경로만 저장한다(ConvertedPDF.pdfPath
            // 상단 주석 참고) — 읽을 때 `FileManager.url(forUbiquityContainerIdentifier:)`
            // 로 다시 절대 경로를 구성한다.
            let relativePath = "\(subfolder)/\(destinationURL.lastPathComponent)"
            let pageCount = PDFDocument(data: pdfData)?.pageCount ?? 0

            let converted = ConvertedPDF(
                pdfPath: relativePath,
                pageCount: pageCount,
                converterUsed: .rhwpWebViewPDFExport,
                sourceDocument: document
            )
            context.insert(converted)
            try context.save()
        } catch {
            print("[DocumentUploadService] hwp → PDF 사전 변환 실패(\(document.originalFilename)): \(error)")
        }
    }

    // MARK: - docx → PDF 사전 변환 (2026-08-16 신설, macOS 전용)

    #if os(macOS)
    /// [2026-08-16 신설] 사용자 요청 — "docxide-pdf + PDFKit로 docx를 pdf로
    /// 변환하는 것을 검토할 것" → "진행할 것. iOS상에서는 처리가 안되는 파일
    /// 업로드를 막으면 됨." 위 hwp용 함수와 같은 원칙(멱등성, 실패해도 throw
    /// 안 함, 업로드 Task에서 형식 무관하게 호출돼도 안전)을 그대로 따른다 —
    /// 다른 점은 변환기(`DocxToPDFConverter`, docxide-pdf 감쌈)가 바이트를
    /// 돌려주는 게 아니라 파일 경로에 직접 쓰는 API라는 것뿐이다.
    ///
    /// iCloud 컨테이너에 직접 쓰지 않고 임시 위치에 먼저 쓴 뒤 "coordinated
    /// move"로 옮기는 이유 — 이 프로젝트는 iCloud로 동기화되는 위치에 쓸 때
    /// 항상 `NSFileCoordinator`로 감싸는 게 원칙인데(`copyIntoICloudDocuments`
    /// 상단 주석 참고, Apple 공식 권장 방식), Rust(docxide-pdf) 쪽 쓰기는
    /// Swift 클로저 밖에서 일어나 그 자체를 코디네이터로 감쌀 수 없다. 그래서
    /// "Rust가 임시 파일에 쓴다 → Swift가 그 파일을 코디네이트된 이동으로
    /// iCloud 폴더에 옮긴다" 두 단계로 나눴다.
    private static func generateConvertedPDFForDocx(for document: SourceDocument, context: ModelContext) async {
        guard (document.convertedPDFs ?? []).isEmpty else { return }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            // [2026-08-18 수정, 기기 간 이식 fix] 북마크 대신 resolveOriginalFileURL.
            let sourceURL = try resolveOriginalFileURL(for: document, context: context)
            let docxData = try readSecurityScopedData(from: sourceURL)
            try DocxToPDFConverter.convert(docxData: docxData, outputURL: tempURL)

            guard let containerURL = FileManager.default.url(
                forUbiquityContainerIdentifier: BibleResearchSchema.defaultCloudKitContainerIdentifier
            ) else {
                print("[DocumentUploadService] docx → PDF 변환은 성공했지만 iCloud 컨테이너를 쓸 수 없어 저장하지 못함: \(document.originalFilename)")
                return
            }

            let subfolder = "연구 문서"
            let folderURL = containerURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(subfolder, isDirectory: true)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

            // hwp 쪽과 같은 "같은 이름" 규칙 — docx 원본과 같은 기본 파일명에
            // 확장자만 .pdf로.
            let baseName = (document.originalFilename as NSString).deletingPathExtension
            let destinationURL = uniqueDestinationURL(in: folderURL, filename: baseName + ".pdf")

            var coordinatorError: NSError?
            var moveError: Error?
            NSFileCoordinator().coordinate(
                writingItemAt: destinationURL, options: [], error: &coordinatorError
            ) { writeURL in
                do {
                    try FileManager.default.moveItem(at: tempURL, to: writeURL)
                } catch {
                    moveError = error
                }
            }
            if let coordinatorError { throw coordinatorError }
            if let moveError { throw moveError }

            let relativePath = "\(subfolder)/\(destinationURL.lastPathComponent)"
            let pageCount = PDFDocument(url: destinationURL)?.pageCount ?? 0

            let converted = ConvertedPDF(
                pdfPath: relativePath,
                pageCount: pageCount,
                converterUsed: .docxidePdf,
                sourceDocument: document
            )
            context.insert(converted)
            try context.save()
        } catch {
            print("[DocumentUploadService] docx → PDF 사전 변환 실패(\(document.originalFilename)): \(error)")
        }
    }
    #endif

    /// security-scoped URL에서 파일 바이트를 읽는다 — `DocumentViewerViewModel.
    /// readSecurityScopedData`와 같은 패턴(중복이지만 두 파일이 서로 다른
    /// 레이어라 공유 유틸로 뽑기보다 각자 짧게 유지하는 쪽을 택했다).
    private static func readSecurityScopedData(from url: URL) throws -> Data {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    // MARK: - iCloud Drive 저장 (2026-08-11 신설, 2026-08-15 비공개로 되돌림)
    //
    // `FileManager.url(forUbiquityContainerIdentifier:)`로 이 앱의 iCloud
    // 컨테이너(CloudKit과 같은 컨테이너 식별자를 재사용 —
    // `BibleResearchSchema.defaultCloudKitContainerIdentifier`) 안의 표준
    // "Documents" 폴더 아래에 "<subfolder>" 경로를 만들고 그 안으로 원본을
    // 복사한다.
    //
    // [2026-08-16 수정] 사용자 지적 — 이 컨테이너는 이미 앱 전용 private
    // 컨테이너(`iCloud~com~jbch~JBCHBibleResearch`)라 그 안에 다시 "JBCH 성경
    // 연구" 세그먼트를 두는 건 중복이다(실제 디스크 경로는
    // `.../Mobile Documents/iCloud~com~jbch~JBCHBibleResearch/Documents/연구 문서`
    // 여야 하는데, 예전 코드는 그 사이에 "JBCH 성경 연구/"를 하나 더 끼워
    // `.../Documents/JBCH 성경 연구/연구 문서`가 됐었다). 그 세그먼트를 없애
    // "Documents/연구 문서" · "Documents/OCR 이미지"로 바로 붙게 했다 — 아래
    // `SettingsView.swift`의 저장 위치 표시 문구도 같이 맞췄다. ⚠️ 이미
    // 업로드된 기존 문서는 예전 경로("Documents/JBCH 성경 연구/…")에 그대로
    // 남아 있다 — `fileBookmark`가 실제 파일 위치를 직접 가리키므로 여전히
    // 정상적으로 열리지만, 새로 옮겨주지는 않는다(원한다면 별도 마이그레이션이
    // 필요).
    //
    // ⚠️ [2026-08-15 정책 확정] 이 컨테이너는 의도적으로 비공개(private scope)로
    // 둔다 — Finder의 "iCloud Drive"에 사용자가 직접 볼 수 있는 폴더로 노출하지
    // 않는다는 뜻(`Info.plist` 상단 주석 참고). 사용자 판단 — "괜히 공개했다가
    // 사용자가 마음대로 폴더 파일을 추가하거나, 삭제하는 것보다 나음." Finder에서
    // 직접 파일을 지우거나 옮기면 이 앱이 SwiftData에 들고 있는 북마크
    // (`SourceDocument.fileBookmark`)가 깨져 원본을 못 여는 문제가 생길 수
    // 있어서다. 기기 간 iCloud 동기화 자체는 비공개 상태에서도 그대로 된다.
    //
    // `NSFileCoordinator`로 감싸는 이유는 iCloud로 동기화되는 위치에 파일을 쓸 때
    // Apple이 공식적으로 권장하는 방식이기 때문이다(다른 프로세스/기기의 동기화
    // 데몬과 충돌 없이 안전하게 쓰기 위함).
    private static func copyIntoICloudDocuments(sourceURL: URL, subfolder: String) throws -> URL {
        guard let containerURL = FileManager.default.url(
            forUbiquityContainerIdentifier: BibleResearchSchema.defaultCloudKitContainerIdentifier
        ) else {
            throw DocumentUploadError.iCloudContainerUnavailable
        }

        let folderURL = containerURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(subfolder, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        // [2026-08-15 수정] 사용자 보고 — "파일 앞에 9CF1CDC5_, 65CDAF3F_ 같은
        // 문자열이 붙음." 이전엔 이름이 실제로 겹치는지와 무관하게 매번 짧은
        // UUID를 파일명 앞에 붙였다 — Finder에서 원본 파일명 그대로 찾고 싶은
        // 사용자 입장에서는 불필요한 잡음이었다. 이제는 같은 폴더에 정말 같은
        // 이름의 파일이 이미 있을 때만(파일명 충돌이 실제로 있을 때만) macOS
        // Finder에 익숙한 "파일명 2.pdf" 표기로 구분하고, 그 외에는 원본
        // 파일명을 그대로 쓴다.
        let destinationURL = uniqueDestinationURL(in: folderURL, filename: sourceURL.lastPathComponent)

        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { sourceURL.stopAccessingSecurityScopedResource() } }

        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(
            readingItemAt: sourceURL, options: [],
            writingItemAt: destinationURL, options: [],
            error: &coordinatorError
        ) { readURL, writeURL in
            do {
                try FileManager.default.copyItem(at: readURL, to: writeURL)
            } catch {
                copyError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let copyError { throw copyError }
        return destinationURL
    }

    /// [2026-08-15 신설] `filename`이 `folderURL`에 이미 있으면 macOS Finder에
    /// 익숙한 "파일명 2.pdf", "파일명 3.pdf" ... 형태로 비어 있는 이름을 찾는다.
    /// 겹치지 않으면 원본 파일명을 그대로 돌려준다 — 위 `copyIntoICloudDocuments`
    /// 수정 주석 참고.
    private static func uniqueDestinationURL(in folderURL: URL, filename: String) -> URL {
        let candidate = folderURL.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        let ext = (filename as NSString).pathExtension
        let base = (filename as NSString).deletingPathExtension
        var index = 2
        while true {
            let newName = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            let newCandidate = folderURL.appendingPathComponent(newName)
            if !FileManager.default.fileExists(atPath: newCandidate.path) {
                return newCandidate
            }
            index += 1
        }
    }

    // MARK: - Security-scoped bookmark

    private static func makeSecurityScopedBookmark(for url: URL) throws -> Data {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing { url.stopAccessingSecurityScopedResource() }
        }
        do {
            #if os(macOS)
            return try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            #else
            return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            #endif
        } catch {
            throw DocumentUploadError.bookmarkCreationFailed(error.localizedDescription)
        }
    }

    /// [2026-08-15 추가] 사용자 요청 — "연구문서를 앱에서 삭제하면 파일도 삭제할 것."
    /// `storageLocationKind == .icloudDrive`인 문서만 지운다 — 이 경우에만
    /// `copyIntoICloudDocuments`가 이 앱의 iCloud 컨테이너 안에 만든 "우리
    /// 소유" 복사본이기 때문이다. `.userFolder`/`.appManagedFallback`(iCloud
    /// 저장 실패 시 폴백)은 `fileBookmark`가 사용자가 원래 고른 바깥 위치의
    /// 원본을 그대로 가리키므로, 앱이 SourceDocument 레코드를 지운다고 해서
    /// 사용자의 그 원본 파일까지 마음대로 지우면 안 된다 — 그래서 이 두 경우는
    /// 건너뛴다. 파일 삭제가 실패해도(이미 없어졌거나 접근 불가) DB 레코드
    /// 삭제 자체는 막지 않는다 — 호출부가 결과를 무시하고 계속 진행할 수 있게
    /// throw 없이 콘솔 로그만 남긴다.
    /// [2026-08-16 추가] `generateConvertedPDF`가 iCloud 컨테이너 안에 직접
    /// 만들어 둔 사전 변환 PDF 파일 — 위 `deleteStoredFile`(원본 파일)과 같은
    /// 이유(우리가 직접 만든 우리 소유 파일이라 문서 삭제 시 함께 지우지
    /// 않으면 고아 파일로 남는다)로, `SourceDocument.convertedPDFs` 레코드가
    /// 가리키는 상대 경로를 그대로 지운다. `deleteStoredFile`과 별도 함수로
    /// 뽑은 이유는 전자가 `document.fileBookmark` 하나(단수)만 다루는 반면,
    /// 이건 `convertedPDFs`(배열, 이론상 여러 개일 수 있음)를 순회해야 해서다.
    static func deleteConvertedPDFFiles(for document: SourceDocument) {
        let convertedPDFs = document.convertedPDFs ?? []
        guard !convertedPDFs.isEmpty else { return }
        guard let containerURL = FileManager.default.url(
            forUbiquityContainerIdentifier: BibleResearchSchema.defaultCloudKitContainerIdentifier
        ) else { return }

        for converted in convertedPDFs {
            let pdfURL = containerURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(converted.pdfPath, isDirectory: false)
            var coordinatorError: NSError?
            NSFileCoordinator().coordinate(
                writingItemAt: pdfURL, options: .forDeleting, error: &coordinatorError
            ) { writeURL in
                do {
                    try FileManager.default.removeItem(at: writeURL)
                } catch let removeError as NSError where removeError.code == NSFileNoSuchFileError {
                    // 이미 없는 파일 — 문제 아님.
                } catch {
                    print("[DocumentUploadService] 사전 변환 PDF 삭제 실패(\(converted.pdfPath)): \(error.localizedDescription)")
                }
            }
            if let coordinatorError {
                print("[DocumentUploadService] 사전 변환 PDF 삭제 조정 실패(\(converted.pdfPath)): \(coordinatorError.localizedDescription)")
            }
        }
    }

    static func deleteStoredFile(for document: SourceDocument) {
        guard document.storageLocationKind == .icloudDrive else { return }
        // [2026-08-18 수정, 기기 간 이식 fix] originalFilePath가 있으면(정상 케이스)
        // 그걸로 직접 URL을 계산한다 — 삭제는 되돌릴 수 없는 동작이라, 이 기기의
        // 북마크가 이식 불가라서 실패하는 일이 없어야 한다. 문서가 곧 지워질
        // 것이므로 마이그레이션 소급 저장(originalFilePath 백필)은 의미가 없어
        // context 없이 쓸 수 있는 이 인라인 버전을 쓴다(resolveOriginalFileURL과
        // 달리 ModelContext 인자가 필요 없다).
        let resolvedURL: URL?
        if let relativePath = document.originalFilePath,
           let containerURL = FileManager.default.url(
               forUbiquityContainerIdentifier: BibleResearchSchema.defaultCloudKitContainerIdentifier
           ) {
            resolvedURL = containerURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(relativePath, isDirectory: false)
        } else if let bookmark = document.fileBookmark {
            resolvedURL = try? resolveURL(from: bookmark)
        } else {
            resolvedURL = nil
        }
        guard let resolvedURL else { return }
        // [2026-08-25 수정, 경고] 이 블록을 감싸던 `do { ... } catch { ... }`가
        // "'catch' block is unreachable because no errors are thrown in 'do'
        // block" 경고를 냈다 — 실제로 이 블록 안에는 던지는 코드가 없다.
        // `startAccessingSecurityScopedResource()`는 `Bool`을 반환할 뿐이고,
        // `NSFileCoordinator.coordinate`는 에러를 던지는 대신 `error:` inout
        // 파라미터로 보고하며(`coordinatorError`, 아래에서 이미 별도 처리),
        // 안쪽 클로저의 `FileManager.removeItem`은 이미 자기 자신의 `do/catch`로
        // 처리된다. 유일하게 던질 수 있었던 지점은 `resolveURL(from:)`인데,
        // 위(627행)에서 이미 `try?`로 호출해 실패 시 `resolvedURL = nil` →
        // `guard let resolvedURL else { return }`로 조용히 반환하는 경로를
        // 타므로, 이 catch는 애초에 이 코드가 짜인 시점부터 한 번도 실행될
        // 수 없었던 죽은 코드였다(삭제해도 동작 변화 없음 — 이 catch가 찍던
        // 로그는 이미 `try?` 때문에 지금도 절대 찍히지 않는다).
        let url = resolvedURL
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }

        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(
            writingItemAt: url, options: .forDeleting, error: &coordinatorError
        ) { writeURL in
            do {
                try FileManager.default.removeItem(at: writeURL)
            } catch let removeError as NSError where removeError.code == NSFileNoSuchFileError {
                // 이미 없는 파일 — 문제 아님(예: 사용자가 다른 경로로 이미 지움).
            } catch {
                print("[DocumentUploadService] 파일 삭제 실패(\(url.lastPathComponent)): \(error.localizedDescription)")
            }
        }
        if let coordinatorError {
            print("[DocumentUploadService] 파일 삭제 조정 실패(\(url.lastPathComponent)): \(coordinatorError.localizedDescription)")
        }
    }

    /// 저장된 북마크를 실제 URL로 되돌린다. 뷰어(S6)/재추출 시 호출.
    static func resolveURL(from bookmark: Data) throws -> URL {
        var isStale = false
        #if os(macOS)
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
        #else
        let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
        #endif
        // ⚠️ isStale이면 원칙적으로 북마크를 다시 만들어 SourceDocument.fileBookmark를
        // 갱신해야 한다(Apple 권장 패턴) — 이번 구현은 갱신 로직까지는 넣지 않았다,
        // 호출부가 필요하면 추가할 수 있도록 isStale 여부만 남겨 둔다는 점을 여기 문서화.
        return url
    }

    /// [2026-08-18 신설, fileBookmark 기기 간 이식 불가 문제 fix] 원본 파일 URL을
    /// 구하는 창구 — 뷰어(S6)/텍스트 추출/OCR 검수 등 원본 파일을 여는 모든 곳이
    /// 이제 `resolveURL(from: document.fileBookmark)`를 직접 부르는 대신 이 함수를
    /// 쓴다. `document.originalFilePath`가 있으면(icloudDrive 저장 성공 케이스)
    /// 그 상대경로로 절대 URL을 직접 계산한다 — `ConvertedPDF.pdfPath`를 읽는
    /// 것과 정확히 같은 방식이고, 북마크가 전혀 필요 없다(이 앱이 소유한 iCloud
    /// 컨테이너 안의 파일이라 앱 자체의 샌드박스 권한만으로 접근 가능 — 기기가
    /// 바뀌어도 항상 똑같이 계산되므로 fileBookmark의 기기 간 이식 문제가 없다).
    ///
    /// `originalFilePath`가 없는(이 fix 이전에 업로드된) 기존 문서는 `fileBookmark`로
    /// 폴백해서 열되, 성공하면 그 자리에서 `originalFilePath`를 소급으로 채워
    /// 저장한다 — 그 기기에서 한 번이라도 성공적으로 열리면(원래 업로드한 기기일
    /// 가능성이 높다, 북마크가 그 기기에서만 안정적이므로), CloudKit 동기화를 통해
    /// 다른 기기에서도 그 뒤로는 이 상대경로로 열 수 있게 된다.
    /// `storageLocationKind`가 `.icloudDrive`가 아니면(사용자가 앱 바깥에서 고른
    /// 파일) 여전히 북마크만 쓴다 — 그 경우는 애초에 이 앱 소유 파일이 아니라
    /// 상대경로 계산 자체가 불가능하다(이 필드 상단 주석 참고).
    static func resolveOriginalFileURL(for document: SourceDocument, context: ModelContext) throws -> URL {
        if document.storageLocationKind == .icloudDrive,
           let relativePath = document.originalFilePath,
           let containerURL = FileManager.default.url(
               forUbiquityContainerIdentifier: BibleResearchSchema.defaultCloudKitContainerIdentifier
           ) {
            return containerURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(relativePath, isDirectory: false)
        }

        guard let bookmark = document.fileBookmark else {
            throw DocumentUploadError.securityScopedAccessFailed
        }
        let url = try resolveURL(from: bookmark)

        // 마이그레이션 — icloudDrive인데 originalFilePath가 아직 없는 기존 문서.
        // 북마크 해석이 (이 기기에서는) 성공했으니, 이 URL이 실제로 컨테이너
        // "Documents/" 아래에 있는지 확인하고 상대경로를 역산해 채워 넣는다.
        if document.storageLocationKind == .icloudDrive,
           document.originalFilePath == nil,
           let containerURL = FileManager.default.url(
               forUbiquityContainerIdentifier: BibleResearchSchema.defaultCloudKitContainerIdentifier
           ) {
            let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
            let containerPath = documentsURL.standardizedFileURL.path
            let resolvedPath = url.standardizedFileURL.path
            if resolvedPath.hasPrefix(containerPath + "/") {
                document.originalFilePath = String(resolvedPath.dropFirst(containerPath.count + 1))
                try? context.save()
            }
        }

        return url
    }

    // MARK: - 저장 위치 추정(휴리스틱, ⚠️ 검증 필요)

    private static func inferStorageLocationKind(for url: URL) -> StorageLocationKind {
        let path = url.path
        if path.contains("Mobile Documents/com~apple~CloudDocs") {
            return .icloudDrive
        }
        // ⚠️ [수정] `FileManager.homeDirectoryForCurrentUser`는 iOS에서 쓸 수 없다
        // (샌드박스 홈 디렉터리 개념 자체가 macOS와 다름) — macOS에서만 실제 홈
        // 경로와 대조하고, 그 외 플랫폼에서는 아래 고정 접두사 검사만으로 판단한다.
        #if os(macOS)
        if path.contains(FileManager.default.homeDirectoryForCurrentUser.path) {
            return .userFolder
        }
        #endif
        if path.hasPrefix("/Users/") || path.hasPrefix("/var/mobile/") {
            return .userFolder
        }
        return .appManagedFallback
    }
}
