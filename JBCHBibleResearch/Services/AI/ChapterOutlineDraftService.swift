//
//  ChapterOutlineDraftService.swift
//  JBCHBibleResearch
//
//  screens.md S9 — "AI로 초안 제안" 백엔드. FoundationModels(`SystemLanguageModel`,
//  iOS/macOS 26+, Apple Intelligence 지원 기기 필요) 위에 얇게 얹은 래퍼다. 완전
//  온디바이스·무료이며 클라우드 폴백(Private Cloud Compute)은 스펙에서 의도적으로
//  제외했다.
//
//  ⚠️⚠️ [매우 높은 불확실성, Xcode 실기기 검증 필수] 이 세션엔 Xcode/컴파일러가 없어
//  FoundationModels API를 실제로 컴파일해 본 적이 없다. 아래 심볼들(`SystemLanguageModel`,
//  `.default`, `.availability`, `LanguageModelSession`, `session.respond(to:)`,
//  `response.content`)은 2025년 WWDC 발표 시점 지식을 근거로 작성했고, 그 중
//  `LanguageModelSession.GenerationError.exceededContextWindowSize`만은 사용자가 준
//  screens.md 원문(9.9절)에 정확히 그 이름으로 명시돼 있어 신뢰도가 높다. 나머지
//  세부 시그니처(특히 `Response` 타입의 프로퍼티 이름, `Availability`의 연관값 구조)는
//  실제 빌드로 재확인이 필요하다 — 컴파일 오류가 나면 정확한 오류 메시지를 알려주면
//  바로 고치겠다.
//
//  `#if canImport(FoundationModels)` + `@available` 이중 가드를 쓴 이유: 이 앱
//  패키지(Package.swift)의 최소 배포 버전은 macOS(.v15)/iOS(.v18)로, FoundationModels가
//  요구하는 26보다 훨씬 낮다. canImport로 감싸 두면 이 프레임워크 자체가 없는(더 이전
//  Xcode/SDK) 환경에서도 이 파일이 컴파일은 되고 "사용 불가"로 조용히 폴백한다 —
//  S9 스펙의 "미지원 기기: 버튼을 숨김(에러 메시지 없이)" 원칙과 정확히 같은 모양이다.
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
                // S9 스펙 9.9절의 안내 문구를 그대로 썼다.
                return "이 장은 너무 길어 AI 초안을 만들 수 없습니다."
            case .underlyingFailure(let message):
                return message
            }
        }
    }

    /// "AI로 초안 제안" 버튼을 보여줄지 여부. 미지원(OS 버전/기기/Apple Intelligence
    /// 꺼짐 등) 상태에서는 버튼 자체를 숨긴다(에러 메시지 없이) — S9 스펙 그대로.
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

    /// 8.4 환경설정 "Apple Intelligence 상태 뱃지"용 3단계 상태.
    /// ⚠️ `SystemLanguageModel.Availability.UnavailableReason`의 정확한 케이스
    /// 이름(예: `.deviceNotEligible`/`.appleIntelligenceNotEnabled`)을 이 세션에서
    /// 컴파일로 확인할 수 없어, 이름으로 직접 패턴 매칭하는 대신 `String(describing:)`
    /// 결과에 "enabled"가 포함되는지로 "설정에서 꺼짐"과 "기기 자체 미지원"을
    /// 구분한다 — 케이스 이름이 조금 달라도 이 휴리스틱은 깨지지 않을 가능성이 높다고
    /// 판단했다(더 안전한 방향으로 타협).
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
                // Apple 프레임워크의 non-frozen enum 대비(라이브러리 진화) — 이 세션에서
                // 실제로 다른 케이스가 있는지 확인할 수 없어 안전한 쪽(미지원)으로 처리.
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

    /// ⚠️ [실측 필요] "글자당 토큰 비율"은 Apple의 경험칙(영어 기준 대략 3~4자당
    /// 1토큰)을 참고했으나 한글 기준으로는 검증된 바가 없다는 것이 스펙 원문의
    /// 명시적 경고다. 한글은 음절 단위로 정보 밀도가 더 높을 가능성이 있어 보수적으로
    /// 영어 경험치의 절반(글자당 토큰 소모가 더 크다고 가정) 수준으로 잡아 뒀다 —
    /// 이 상수 자체가 검증 전 추정치임을 코드 밖에서도 계속 강조해야 한다. 실제
    /// 기기에서 긴 장(시편 119편 등)으로 실측 후 보정 필요.
    private static let estimatedCharactersPerToken = 2.0
    private static let promptAndResponseReserveTokens = 1000
    /// 스펙 9.9절 "약 4K 토큰" 그대로.
    private static let modelContextWindowTokens = 4096

    /// 장 절 본문 글자 수로 미리 걸러 "AI로 초안 제안" 버튼을 비활성화할지 판단한다.
    /// 이 휴리스틱만 믿지 않고, 실제 생성 중 컨텍스트 초과 오류가 나면 2단계
    /// (아래 `generateDraft`의 `.exceededContextWindow`)로도 반드시 걸러낸다(9.9절
    /// "사전 추정만 믿지 않고 반드시 병행").
    static func canRequestDraft(forChapterCharacterCount characterCount: Int) -> Bool {
        let estimatedTokens = Double(characterCount) / estimatedCharactersPerToken
        let budget = Double(modelContextWindowTokens - promptAndResponseReserveTokens)
        return estimatedTokens <= budget
    }

    // MARK: - 2단계: 실제 생성 + 런타임 안전망(9.9절)

    /// 장 본문을 넘기면 4~5개 주제로 나눈 요약 초안을 반환한다(2026-08-06 사용자
    /// 지정 프롬프트 — "전문적으로 4~5개정도 주제로 요약, 말투는 간결하게 끝맺을
    /// 것"). 결과는 편집기에 바로 반영되지 않는다 — 호출부(OutlineViewModel)가
    /// 별도 미리보기 상태로만 들고 있다가, 사용자가 "편집기에 적용"을 눌러야 실제
    /// 문서에 반영된다(9.9절 "미리보기 상태에서 그대로 두고 나가면 저장되지 않고
    /// 사라진다").
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

        // 2026-08-06: 사용자가 지정한 프롬프트 문구를 그대로 반영했다 — "해당
        // 텍스트를 전문적으로 4~5개정도 주제로 요약할 것. 말투는 간결하게 끝맺을
        // 것." 책/장 컨텍스트와 부가 제약(구절 번호 언급 금지, 신학적 해석 금지 —
        // 기존 프롬프트에서 이미 확정돼 있던 조건, 사용자가 새로 바꾸라고 한 부분이
        // 아니라 그대로 유지)만 앞뒤로 덧붙였다.
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
            // 1단계 사전 휴리스틱이 틀렸을 때의 2단계 안전망(9.9절).
            return .failure(.exceededContextWindow)
        } catch {
            return .failure(.underlyingFailure(error.localizedDescription))
        }
        #else
        return .failure(.unavailable(reason: "이 빌드 환경에 FoundationModels 프레임워크가 없습니다."))
        #endif
    }
}
