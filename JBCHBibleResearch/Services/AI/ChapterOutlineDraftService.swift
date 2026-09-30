//
//  ChapterOutlineDraftService.swift
//  JBCHBibleResearch
//
//  "AI로 초안 제안" 백엔드. FoundationModels(`SystemLanguageModel`, iOS/macOS 26+,
//  Apple Intelligence 지원 기기 필요) 위에 얹은 얇은 래퍼로, 완전 온디바이스이며
//  클라우드 폴백(Private Cloud Compute)은 의도적으로 쓰지 않는다.
//
//  `#if canImport(FoundationModels)` + `@available` 이중 가드를 쓴 이유: 패키지의 최소
//  배포 버전(macOS .v15/iOS .v18)이 FoundationModels 요구 버전(26)보다 낮다. canImport로
//  감싸면 프레임워크가 없는 SDK에서도 컴파일되고 "사용 불가"로 조용히 폴백하므로, 미지원
//  기기에서는 에러 메시지 없이 버튼을 숨기는 동작과 일치한다.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
enum ChapterOutlineDraftService {
    enum DraftError: Error, CustomStringConvertible {
        case unavailable(reason: String)
        case exceededContextWindow
        case underlyingFailure(String)

        var description: String {
            switch self {
            case .unavailable(let reason):
                return reason
            case .exceededContextWindow:
                return "이 장은 너무 길어 AI 초안을 만들 수 없습니다."
            case .underlyingFailure(let message):
                return message
            }
        }
    }

    /// "AI로 초안 제안" 버튼을 보여줄지 여부. 미지원(OS 버전/기기/Apple Intelligence
    /// 꺼짐 등)이면 에러 메시지 없이 버튼을 숨긴다.
    static var isDraftAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                return true
            }
            return false
        } else {
            return false
        }
        #else
        return false
        #endif
    }

    /// 환경설정 "Apple Intelligence 상태 뱃지"용 3단계 상태.
    /// `UnavailableReason`의 케이스 이름으로 직접 매칭하지 않고 `String(describing:)`에
    /// "enabled"가 포함되는지로 "설정에서 꺼짐"과 "기기 미지원"을 구분한다(휴리스틱).
    enum AppleIntelligenceStatus: Equatable {
        case available
        case deviceUnsupported
        case disabledInSettings
    }

    static var appleIntelligenceStatus: AppleIntelligenceStatus {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                let description = String(describing: reason).lowercased()
                return description.contains("enabled") ? .disabledInSettings : .deviceUnsupported
            @unknown default:
                // non-frozen enum에 새 케이스가 추가될 경우 안전한 쪽(미지원)으로 처리한다.
                return .deviceUnsupported
            }
        } else {
            return .deviceUnsupported
        }
        #else
        return .deviceUnsupported
        #endif
    }

    // MARK: - 1단계: 사전 토큰 예산 휴리스틱(9.9절)

    /// ⚠️ 글자당 토큰 비율은 영어 경험칙(대략 3~4자당 1토큰)을 참고한 추정치이며 한글 기준으로
    /// 검증되지 않았다. 보수적으로 영어의 절반(글자당 토큰 소모가 더 크다고 가정)으로 잡았다.
    /// 긴 장(시편 119편 등)으로 실측해 보정해야 한다.
    private static let estimatedCharactersPerToken = 2.0
    private static let promptAndResponseReserveTokens = 1000
    /// 모델 컨텍스트 윈도우 약 4K 토큰.
    private static let modelContextWindowTokens = 4096

    /// 장 본문 글자 수로 미리 걸러 "AI로 초안 제안" 버튼을 비활성화할지 판단한다.
    /// 추정치이므로 생성 중 컨텍스트 초과 오류도 `generateDraft`에서 반드시 함께 처리한다.
    static func canRequestDraft(forChapterCharacterCount characterCount: Int) -> Bool {
        let estimatedTokens = Double(characterCount) / estimatedCharactersPerToken
        let budget = Double(modelContextWindowTokens - promptAndResponseReserveTokens)
        return estimatedTokens <= budget
    }

    // MARK: - 2단계: 실제 생성 + 런타임 안전망(9.9절)

    /// 장 본문을 4~5개 주제로 요약한 초안을 반환한다. 결과는 편집기에 바로 반영되지 않는다.
    /// 호출부(OutlineViewModel)가 미리보기로만 들고 있다가 사용자가 "편집기에 적용"을 눌러야
    /// 문서에 반영되며, 그대로 나가면 저장되지 않는다.
    static func generateDraft(bookNameKo: String, chapter: Int, verseText: String) async -> Result<String, DraftError> {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else {
            return .failure(.unavailable(reason: "iOS/macOS 26 이상이 필요합니다."))
        }
        guard case .available = SystemLanguageModel.default.availability else {
            return .failure(.unavailable(reason: "이 기기에서는 Apple Intelligence를 사용할 수 없습니다."))
        }
        guard canRequestDraft(forChapterCharacterCount: verseText.count) else {
            return .failure(.exceededContextWindow)
        }

        // 책/장 컨텍스트와 부가 제약(구절 번호 언급 금지, 신학적 해석 금지)을 프롬프트에 덧붙인다.
        let prompt = """
        다음은 성경 \(bookNameKo) \(chapter)장의 본문입니다. 해당 텍스트를
        전문적으로 4~5개정도 주제로 요약할 것. 말투는 간결하게 끝맺을 것. 각
        주제는 한 줄씩 작성하고, 구절 번호는 언급하지 말고, 신학적 해석을
        덧붙이지 마세요.

        \(verseText)
        """

        let session = LanguageModelSession()
        do {
            let response = try await session.respond(to: prompt)
            return .success(response.content)
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // 1단계 사전 휴리스틱이 틀렸을 때의 안전망.
            return .failure(.exceededContextWindow)
        } catch {
            return .failure(.underlyingFailure(error.localizedDescription))
        }
        #else
        return .failure(.unavailable(reason: "이 빌드 환경에 FoundationModels 프레임워크가 없습니다."))
        #endif
    }
}
