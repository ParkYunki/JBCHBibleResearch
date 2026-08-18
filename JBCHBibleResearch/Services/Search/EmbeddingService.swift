//
//  EmbeddingService.swift
//  JBCHBibleResearch
//
//  S11(통합 검색/의미검색) — 텍스트 → 벡터 변환과 코사인 유사도 계산.
//
//  ⚠️⚠️ [이번 라운드에서 가장 불확실한 부분] schema.md 4장은 검색 단계만 "Swift +
//  Accelerate(vDSP)로 brute-force 코사인 유사도"라고 확정했을 뿐, 임베딩 벡터
//  자체를 무엇으로 만들지는 원본 세 문서 어디에도 없다 — 근거 없이 만들지 않는다는
//  원칙에 따라 후보를 추측이 아니라 소거법으로 좁혔다:
//    - FoundationModels(iOS/macOS 26+)는 텍스트 **생성** 전용 API만 제공하고
//      임베딩 벡터를 반환하는 공개 API가 없다(ChapterOutlineDraftService.swift가
//      쓰는 SystemLanguageModel/LanguageModelSession에는 그런 메서드가 없음).
//    - 외부 네트워크 임베딩 API(OpenAI 등)는 schema.md 0장의 "온디바이스" 전제와
//      정면으로 어긋난다.
//    - 남는 유일한 Apple 온디바이스 문장 임베딩 API가 NaturalLanguage 프레임워크의
//      `NLContextualEmbedding`(WWDC23 발표, iOS 17+/macOS 14+ — 이 프로젝트 최소
//      배포 버전인 iOS 18/macOS 15보다 낮아 FoundationModels처럼 이중 가드가 필요
//      없다)이다. 이걸 택했다.
//
//  ⚠️⚠️ [가장 큰 미확인 리스크] `NLContextualEmbedding`이 한국어를 실제로 지원하는지
//  이 세션에서 확신할 수 없다 — 이 앱의 실제 콘텐츠(성경 본문/메모/연구문서)는
//  거의 전부 한국어다. 그래서 지원 언어를 가정하지 않고 매번 `NLContextualEmbedding
//  (language: .korean)`가 nil을 반환하는지로 런타임에 직접 확인하고, nil이면
//  "이 기기에서 의미검색을 쓸 수 없음"으로 정직하게 비활성화한다(FoundationModels
//  가용성 체크와 같은 패턴 — 추측 대신 런타임 확인 + 정직한 실패).
//  `requestAssets()`가 실제로 모델 자산을 다운로드하는 동작·소요 시간·네트워크
//  필요 여부도 실기기 검증 전까지는 미확인이다.
//

import Foundation
import NaturalLanguage
#if canImport(Accelerate)
import Accelerate
#endif

@MainActor
final class EmbeddingService {
    static let shared = EmbeddingService()

    enum Availability: Equatable {
        /// 아직 `prepareIfNeeded()`를 호출하지 않았거나 준비 중.
        case unknown
        case available
        /// `NLContextualEmbedding(language: .korean)`이 nil을 반환 — 이 기기/OS
        /// 버전에서 한국어 문장 임베딩 모델 자체가 없다는 뜻.
        case unsupportedLanguage
        /// 모델은 있지만 자산 다운로드/로드에 실패(네트워크 없음 등).
        case assetPreparationFailed(String)
    }

    private(set) var availability: Availability = .unknown

    private var embedder: NLContextualEmbedding?
    private let language: NLLanguage = .korean

    private init() {}

    /// 최초 1회(또는 실패 후 재시도) 호출. 자산이 없으면 다운로드를 시도할 수 있어
    /// 비동기다 — SearchView.onAppear에서 호출한다.
    func prepareIfNeeded() async {
        guard embedder == nil else { return }
        guard let candidate = NLContextualEmbedding(language: language) else {
            availability = .unsupportedLanguage
            return
        }
        do {
            if !candidate.hasAvailableAssets {
                try await candidate.requestAssets()
            }
            try candidate.load()
            embedder = candidate
            availability = .available
        } catch {
            print("[EmbeddingService] 한국어 임베딩 모델 준비 실패: \(error)")
            availability = .assetPreparationFailed(error.localizedDescription)
        }
    }

    /// 문장(또는 문단) 전체를 하나의 고정 길이 벡터로 변환한다. `NLContextualEmbedding`은
    /// 토큰(어절) 단위 벡터를 돌려주므로, 평균 풀링(mean pooling)으로 문장 전체
    /// 벡터 하나를 만든다 — 트랜스포머 계열 문장 임베딩에서 흔히 쓰는 방식이지만,
    /// 이 모델이 평균 풀링에 얼마나 적합한지는 실측 전까지 미확인이다.
    func embed(_ text: String) -> [Float]? {
        guard let embedder, !text.isEmpty else { return nil }
        do {
            let result = try embedder.embeddingResult(for: text, language: language)
            var accumulated: [Double]?
            var tokenCount = 0
            result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
                if accumulated == nil {
                    accumulated = vector
                } else {
                    for i in 0..<vector.count { accumulated![i] += vector[i] }
                }
                tokenCount += 1
                return true
            }
            guard var summed = accumulated, tokenCount > 0 else { return nil }
            for i in 0..<summed.count { summed[i] /= Double(tokenCount) }
            return summed.map { Float($0) }
        } catch {
            print("[EmbeddingService] 임베딩 계산 실패: \(error)")
            return nil
        }
    }

    /// schema.md 4장 확정 방식 — Accelerate(vDSP)로 코사인 유사도 계산.
    nonisolated func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        #if canImport(Accelerate)
        var dot: Float = 0
        var sumSquaresA: Float = 0
        var sumSquaresB: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        vDSP_svesq(a, 1, &sumSquaresA, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &sumSquaresB, vDSP_Length(b.count))
        let denominator = (sumSquaresA.squareRoot()) * (sumSquaresB.squareRoot())
        guard denominator > 0 else { return 0 }
        return dot / denominator
        #else
        // Accelerate가 없는 빌드 환경(이론상 발생하지 않아야 하지만 방어적으로 순수
        // Swift 폴백을 남긴다).
        var dot: Float = 0, normA: Float = 0, normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denominator = normA.squareRoot() * normB.squareRoot()
        guard denominator > 0 else { return 0 }
        return dot / denominator
        #endif
    }
}
