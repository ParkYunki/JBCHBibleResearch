//
//  EmbeddingService.swift
//  JBCHBibleResearch
//
//  문장 → 벡터 변환. `intfloat/multilingual-e5-small`(Core ML, 384차원)을 쓴다.
//
//  [모델 리소스] `Scripts/convert_multilingual_e5_small.py`가 만든
//  `MultilingualE5Small.mlpackage`와 `MultilingualE5SmallTokenizer/` 폴더를 Xcode
//  프로젝트에 추가해야 동작한다. 없으면 `checkAvailability()`가 `.unavailable`을
//  반환한다.
//
//  [토크나이저] Core ML은 토큰화를 포함하지 않으므로 SPM 패키지
//  `swift-transformers`(https://github.com/huggingface/swift-transformers)의
//  "Tokenizers" 제품이 필요하다. XLM-RoBERTa 계열 토크나이저(SentencePiece Unigram)는
//  이 패키지에 `UnigramTokenizer`로 등록돼 있다.
//
//  [query/passage 비대칭 검색] E5 계열은 검색어와 색인 대상 문장에 서로 다른
//  접두사("query: "/"passage: ")를 붙여야 한다 — `embedQuery(_:)`는
//  `BibleSemanticSearchService`(검색어)가, `embedPassage(_:)`는
//  `EmbeddingIndexingService`(성경 절 색인)가 쓴다.
//

import Foundation
import CoreML
import Tokenizers
#if canImport(Accelerate)
import Accelerate
#endif

@MainActor
enum EmbeddingService {
    enum Availability: Equatable {
        case available
        case unavailable(reason: String)
    }

    enum EmbeddingError: Error, CustomStringConvertible {
        case unavailable(String)
        case emptyResult
        case underlyingFailure(String)

        var description: String {
            switch self {
            case .unavailable(let reason): return reason
            case .emptyResult: return "문장에서 임베딩 벡터를 만들지 못했습니다."
            case .underlyingFailure(let message): return message
            }
        }
    }

    /// `Scripts/convert_multilingual_e5_small.py`가 만든 파일 이름과 반드시 같아야
    /// 한다 — 바꾸려면 스크립트의 `OUTPUT_MODEL_NAME`/`OUTPUT_TOKENIZER_DIR`도
    /// 같이 바꿔야 한다.
    private static let modelResourceName = "MultilingualE5Small"
    private static let tokenizerResourceName = "MultilingualE5SmallTokenizer"
    /// 변환 스크립트의 `MAX_LENGTH`와 반드시 같아야 한다 — Core ML 모델이 고정
    /// 입력 길이로 트레이싱됐기 때문에(가변 길이가 아님), Swift 쪽에서 이 길이에
    /// 맞춰 패딩/자르기를 해야 한다.
    private static let maxTokenLength = 128
    /// intfloat/multilingual-e5-small은 384차원을 낸다(모델 카드 명시) —
    /// `EmbeddingIndexingService`가 색인 파일 헤더에 이 값을 그대로 기록한다.
    static let dimension = 384

    private static var cachedModel: MLModel?
    private static var cachedTokenizer: Tokenizer?
    private static var cachedPadTokenId: Int?
    private static var cachedAvailability: Availability?

    static func checkAvailability() async -> Availability {
        if let cachedAvailability { return cachedAvailability }

        guard let modelURL = Bundle.main.url(forResource: modelResourceName, withExtension: "mlmodelc") else {
            let result = Availability.unavailable(reason: "임베딩 모델(\(modelResourceName).mlpackage)이 앱에 포함되지 않았습니다. Scripts/convert_multilingual_e5_small.py로 변환한 뒤 Xcode 프로젝트에 추가해주세요.")
            cachedAvailability = result
            return result
        }
        guard let tokenizerFolderURL = Bundle.main.url(forResource: tokenizerResourceName, withExtension: nil) else {
            let result = Availability.unavailable(reason: "토크나이저 파일(\(tokenizerResourceName)/)이 앱에 포함되지 않았습니다.")
            cachedAvailability = result
            return result
        }

        do {
            // `MLModel(contentsOf:)`는 모델을 메모리에 올리는 동기 호출이라 `@MainActor`에서
            // 직접 실행하면 메인 스레드를 붙잡아 UI가 멈춘다(앱 첫 설치 직후 색인이 바로
            // 시작되는 경우). `Task.detached`로 백그라운드에서 로드한다 — `MLModel`은
            // 스레드 안전 타입이고, 캐시 대입은 여전히 메인 액터에서 이뤄진다.
            let model = try await Task.detached(priority: .userInitiated) {
                try MLModel(contentsOf: modelURL)
            }.value
            let tokenizer = try await AutoTokenizer.from(modelFolder: tokenizerFolderURL)
            cachedModel = model
            cachedTokenizer = tokenizer
            // XLM-RoBERTa 계열 표준 pad 토큰 — 실제 vocab에 없으면(이론상 없어야
            // 정상이지만 방어적으로) 공식 기본 ID인 1로 대체한다.
            cachedPadTokenId = tokenizer.convertTokenToId("<pad>") ?? 1
            let result = Availability.available
            cachedAvailability = result
            return result
        } catch {
            print("[EmbeddingService] 모델/토크나이저 로드 실패(원본 에러, 콘솔 전용): \(error)")
            let result = Availability.unavailable(reason: "임베딩 모델을 불러오지 못했습니다.")
            cachedAvailability = result
            return result
        }
    }

    /// 색인 대상(성경 절 본문)용 — E5 비대칭 검색 규약의 "passage: " 접두사.
    static func embedPassage(_ text: String) async throws -> [Float] {
        try await embed(withPrefix: "passage: ", text: text)
    }

    /// 사용자 검색어용 — E5 비대칭 검색 규약의 "query: " 접두사.
    static func embedQuery(_ text: String) async throws -> [Float] {
        try await embed(withPrefix: "query: ", text: text)
    }

    private static func embed(withPrefix prefix: String, text: String) async throws -> [Float] {
        let availability = await checkAvailability()
        guard case .available = availability, let model = cachedModel, let tokenizer = cachedTokenizer, let padTokenId = cachedPadTokenId else {
            if case .unavailable(let reason) = availability {
                throw EmbeddingError.unavailable(reason)
            }
            throw EmbeddingError.unavailable("임베딩 모델을 사용할 수 없습니다.")
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EmbeddingError.emptyResult }

        do {
            var tokenIds = tokenizer.encode(text: prefix + trimmed)
            if tokenIds.count > maxTokenLength {
                tokenIds = Array(tokenIds.prefix(maxTokenLength))
            }
            let actualCount = tokenIds.count
            let paddingCount = maxTokenLength - actualCount

            let inputIdsArray = try MLMultiArray(shape: [1, NSNumber(value: maxTokenLength)], dataType: .int32)
            let attentionMaskArray = try MLMultiArray(shape: [1, NSNumber(value: maxTokenLength)], dataType: .int32)
            for i in 0..<actualCount {
                inputIdsArray[i] = NSNumber(value: tokenIds[i])
                attentionMaskArray[i] = NSNumber(value: 1)
            }
            for i in 0..<paddingCount {
                inputIdsArray[actualCount + i] = NSNumber(value: padTokenId)
                attentionMaskArray[actualCount + i] = NSNumber(value: 0)
            }

            let inputProvider = try MLDictionaryFeatureProvider(dictionary: [
                "input_ids": MLFeatureValue(multiArray: inputIdsArray),
                "attention_mask": MLFeatureValue(multiArray: attentionMaskArray),
            ])
            let output = try await model.prediction(from: inputProvider)
            guard let embeddingArray = output.featureValue(for: "embedding")?.multiArrayValue else {
                throw EmbeddingError.emptyResult
            }
            var vector = [Float](repeating: 0, count: dimension)
            for i in 0..<min(dimension, embeddingArray.count) {
                vector[i] = embeddingArray[i].floatValue
            }
            return vector
        } catch let error as EmbeddingError {
            throw error
        } catch {
            // Core ML/Tokenizers 에러의 원문은 콘솔에만 남기고, 화면엔 영어 타입명이
            // 없는 문구만 보낸다.
            print("[EmbeddingService] 임베딩 실패(원본 에러, 콘솔 전용): \(error)")
            throw EmbeddingError.underlyingFailure("문장을 벡터로 변환하는 중 문제가 발생했습니다.")
        }
    }

    // MARK: - 코사인 유사도

    #if canImport(Accelerate)
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        var sumSquaresA: Float = 0
        vDSP_svesq(a, 1, &sumSquaresA, vDSP_Length(a.count))
        var sumSquaresB: Float = 0
        vDSP_svesq(b, 1, &sumSquaresB, vDSP_Length(b.count))
        let denominator = (sumSquaresA * sumSquaresB).squareRoot()
        guard denominator > 0 else { return 0 }
        return dot / denominator
    }
    #else
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, sumSquaresA: Float = 0, sumSquaresB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            sumSquaresA += a[i] * a[i]
            sumSquaresB += b[i] * b[i]
        }
        let denominator = (sumSquaresA * sumSquaresB).squareRoot()
        guard denominator > 0 else { return 0 }
        return dot / denominator
    }
    #endif
}
