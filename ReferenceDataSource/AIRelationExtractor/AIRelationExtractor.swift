// AIRelationExtractor.swift
//
// [2026-08-19 신설] PersonRelations 2단계(AI 보조 추출) 도구.
//
// build_reference_data.py(1단계, 정규식)가 어느 관계 패턴에도 걸리지 않은
// description 문장을 매 빌드마다 `UnmatchedRelationSentences.json`으로
// 내보낸다. 이 도구는 그 문장들을 하나씩 온디바이스 FoundationModels
// (`SystemLanguageModel`, Apple Intelligence, 완전 무료·오프라인)에 넣어
// 관계를 구조화된 형태로 추출하고, 결과를 `AIExtractedRelations.json`으로
// 저장한다. 그 파일을 `ReferenceDataSource/`에 두고 `build_reference_data.py`를
// 다시 실행하면 PersonRelations에 자동 병합된다(`extraction_method='ai'`로
// 구분됨) — 정확한 병합 로직은 build_reference_data.py의
// build_person_place_tables() 참고, 실행해서 검증 완료.
//
// ⚠️ 정직한 고지: 이 파일은 FoundationModels가 실제로 존재하는 Apple
// Intelligence 지원 기기(Xcode 26+, macOS 26+)에서만 컴파일·실행할 수
// 있다. 이 프로젝트를 작업하는 환경(Linux 샌드박스)에는 그 프레임워크
// 자체가 없어 컴파일도, 실행도, 단 한 줄도 검증할 수 없었다 — 이 프로젝트의
// 다른 모든 신규 Swift 파일(ReferenceEntity.swift, BibleStructuralRerankerService.swift
// 등)과 동일한 제약이다. 아래 API 시그니처(SystemLanguageModel, @Generable,
// @Guide, LanguageModelSession, GenerationError의 각 case)는 전부 이
// 코드를 작성한 시점에 Apple 공식 개발자 문서(developer.apple.com/documentation/
// foundationmodels)를 직접 조회해 확인한 것이며, 실제 동작하는 오픈소스 CLI
// 예제(github.com/systemsoftware/foundationmodels-cli)의 검증된 호출 패턴과
// 대조까지 마쳤다 — 그럼에도 "실제 기기에서 컴파일해 실행해 봐야 확실하다"는
// 이 프로젝트의 원칙은 동일하게 적용된다. 사용법은 같은 폴더의 README.md 참고.
//
// 빌드/실행: `swiftc AIRelationExtractor.swift -o AIRelationExtractor -parse-as-library`
//           `./AIRelationExtractor`
// (Package.swift 없이 단일 파일 스크립트로 구성했다 — SwiftPM의 플랫폼 버전
// 표기(`.macOS(.v26)` 등)가 Xcode/SwiftPM 버전에 따라 세부 문법이 달라질 수
// 있어, 그 불확실성을 아예 제거하고자 `swiftc` 직접 컴파일 방식을 택했다.)

import FoundationModels
import Foundation

// MARK: - 입출력 JSON 스키마 (build_reference_data.py와 필드명을 정확히 맞춤)

struct UnmatchedSentence: Codable {
    let source_word: String
    let source_idx: String
    let sense_index: Int
    let sentence: String
}

struct AIExtractedRelationRecord: Codable {
    let source_word: String
    let source_idx: String
    let sense_index: Int
    let relation_type: String
    let target_word: String
    let raw_sentence: String
    let model_version: String
}

// MARK: - FoundationModels Guided Generation 스키마
//
// build_reference_data.py의 RELATION_PATTERNS/JOINT_PARENT_RE가 실제로
// 만들어내는 24종 relation_type 문자열과 정확히 동일한 rawValue를 쓴다
// (Python 쪽 문자열과 한 글자도 다르면 안 됨 — 병합 시 그대로 저장되는
// 값이라 여기서 오타가 나면 build_reference_data.py 쪽 필터를 통과하지
// 못하고 조용히 버려짐).
@Generable
enum RelationTypeGuess: String, Codable {
    case sonOf = "son_of"
    case daughterOf = "daughter_of"
    case grandsonOf = "grandson_of"
    case granddaughterOf = "granddaughter_of"
    case grandfatherOf = "grandfather_of"
    case fatherOf = "father_of"
    case motherOf = "mother_of"
    case wifeOf = "wife_of"
    case husbandOf = "husband_of"
    case daughterInLawOf = "daughter_in_law_of"
    case brotherOf = "brother_of"
    case youngerBrotherOf = "younger_brother_of"
    case olderBrotherOf = "older_brother_of"
    case sisterOf = "sister_of"
    case uncleOf = "uncle_of"
    case cousinOf = "cousin_of"
    case descendantOf = "descendant_of"
    case ancestorOf = "ancestor_of"
    case marriedTo = "married_to"
    case teacherOf = "teacher_of"
    case tribeOf = "tribe_of"
    case peopleOf = "people_of"
    case affiliatedWithPlace = "affiliated_with_place"
    case kingOf = "king_of"
    /// 이 문장에서 표제어 본인의 확실한 관계를 찾지 못했을 때(제3자 언급뿐이거나,
    /// 불확실/추정 표현("또는", "~일 수 있음", "동명이인")뿐일 때) 반드시 이 값을 쓴다.
    case none = "none"
}

@Generable
struct ExtractedRelation {
    @Guide(description: """
        관계 유형. 반드시 정의된 24종 값 또는 "none" 중 하나. 문장에 표제어 \
        본인이 아닌 다른 사람들끼리의 관계만 언급되어 있다면(예: "OO의 아들 \
        XX가 ~했다"처럼 XX가 주어인 문장) 반드시 "none"을 쓴다 — 표제어 자신의 \
        관계로 착각해 추출하면 안 된다.
        """)
    let relation_type: RelationTypeGuess

    @Guide(description: "관계 대상 인물/장소의 한글 이름 표제어. relation_type이 \"none\"이면 빈 문자열.")
    let target_word: String
}

@Generable
struct ExtractionResult {
    @Guide(description: "이 문장에서 표제어 본인에 대해 확실하게 뽑아낼 수 있는 관계들. 없으면 빈 배열.")
    let relations: [ExtractedRelation]
}

// MARK: - 공용 지침(Instructions) — 세션마다 동일하게 재사용

let SHARED_INSTRUCTIONS = """
너는 한국어 성경 인명/지명 사전의 설명문에서 인물 관계를 뽑아내는 정보 추출기다.

각 요청마다 "표제어"(설명문이 다루는 인물 본인의 이름)와 "문장"(그 인물 설명문의 \
한 문장)을 받는다. 그 문장에서 **표제어 본인**에 대한 확실한 관계만 구조화해서 \
추출하라. 규칙은 다음과 같다.

1. 문장의 문법적 주어가 표제어 본인이 아니라 문장 속에 언급된 다른 사람인 경우 \
   (예: 표제어가 "나하래"인데 문장이 "스루야의 아들 요압의 무기를 드는 자로 활약함" \
   이라면, "스루야의 아들"은 요압을 가리키는 것이지 나하래를 가리키는 게 아니다) \
   그 관계를 표제어의 관계로 추출하지 말고 relation_type을 "none"으로 응답하라. \
   이것이 가장 중요한 규칙이다 — 기존 정규식 방식이 정확히 이 실수를 반복해서 \
   저질렀기 때문에 너에게 이 작업을 맡기는 것이다.
2. 문장이 "또는", "~일 수 있음", "동명이인", "추정" 같은 표현으로 불확실성을 \
   나타내면 그 관계는 추출하지 말고 "none"으로 응답하라.
3. 한 문장에 표제어 본인의 관계가 여러 개 있으면(예: "아버지의 이름은 A이고 \
   어머니는 B이다") 전부 각각의 항목으로 추출하라.
4. relation_type은 반드시 다음 정의된 값 중에서만 골라라: \
   son_of(~의 아들), daughter_of(~의 딸), grandson_of(~의 손자), \
   granddaughter_of(~의 손녀), grandfather_of(표제어가 ~의 조부), \
   father_of(표제어가 ~의 아버지), mother_of(표제어가 ~의 어머니), \
   wife_of(~의 아내), husband_of(~의 남편), daughter_in_law_of(~의 며느리), \
   brother_of(~의 형제), younger_brother_of(~의 아우/동생), \
   older_brother_of(~의 형), sister_of(~의 자매), uncle_of(~의 숙부), \
   cousin_of(~의 사촌), descendant_of(~의 자손/후손), \
   ancestor_of(표제어가 ~의 조상), married_to(~와 결혼), teacher_of(~의 스승), \
   tribe_of(~ 지파 소속), people_of(~ 족속 소속), \
   affiliated_with_place(~ 사람, 출신/소속), king_of(표제어가 ~의 왕), \
   none(위 어느 것도 확실하지 않음).
5. target_word는 관계 대상의 한글 이름만 적는다(조사·수식어는 빼고 이름만).
"""

// MARK: - 유틸

func log(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

func loadJSON<T: Decodable>(_ path: String, as type: T.Type) throws -> T {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return try JSONDecoder().decode(T.self, from: data)
}

func writeJSON<T: Encodable>(_ value: T, to path: String) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

// MARK: - 메인

@main
struct AIRelationExtractor {
    static func main() async {
        let inputPath = "UnmatchedRelationSentences.json"
        let outputPath = "AIExtractedRelations.json"
        let modelVersionTag = "SystemLanguageModel.default(on-device)"

        // 1) 가용성 확인 — foundationmodels-cli(systemsoftware/foundationmodels-cli)의
        //    검증된 case 분기 패턴을 그대로 따른다.
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            break
        case .unavailable(.deviceNotEligible):
            log("이 기기는 Apple Intelligence를 지원하지 않습니다. 지원 기기에서 다시 실행하세요.")
            exit(1)
        case .unavailable(.appleIntelligenceNotEnabled):
            log("이 기기에서 Apple Intelligence가 꺼져 있습니다. 설정에서 켠 뒤 다시 실행하세요.")
            exit(1)
        case .unavailable(.modelNotReady):
            log("온디바이스 모델이 아직 준비되지 않았습니다(다운로드/최적화 중일 수 있음). 잠시 후 다시 시도하세요.")
            exit(1)
        case .unavailable(let reason):
            log("알 수 없는 이유로 모델을 사용할 수 없습니다: \(reason)")
            exit(1)
        }

        // 2) 한국어 지원 확인(경고만 — 확인이 실패해도 실제 요청은 시도해 본다)
        if !model.supportsLocale(Locale(identifier: "ko_KR")) {
            log("⚠️ 이 기기의 모델이 한국어(ko_KR)를 지원하는지 확인할 수 없었습니다. 계속 진행하되 결과 품질을 직접 검토하세요.")
        }

        // 3) 입력 로드
        guard FileManager.default.fileExists(atPath: inputPath) else {
            log("입력 파일이 없습니다: \(inputPath) — 먼저 build_reference_data.py를 실행해 이 파일을 생성하세요.")
            exit(1)
        }
        let unmatched: [UnmatchedSentence]
        do {
            unmatched = try loadJSON(inputPath, as: [UnmatchedSentence].self)
        } catch {
            log("입력 파일 파싱 실패: \(error)")
            exit(1)
        }
        log("입력 문장 \(unmatched.count)건 로드 완료.")

        // 4) 이어하기 지원 — 출력 파일이 이미 있으면 처리된 항목을 건너뛴다
        //    (수백 건을 온디바이스 모델로 순차 처리하면 시간이 오래 걸릴 수 있어,
        //    중간에 중단되어도 처음부터 다시 돌리지 않도록 하기 위함).
        var results: [AIExtractedRelationRecord] = []
        var doneKeys = Set<String>()
        if FileManager.default.fileExists(atPath: outputPath) {
            if let prior = try? loadJSON(outputPath, as: [AIExtractedRelationRecord].self) {
                results = prior
                for r in prior {
                    doneKeys.insert("\(r.source_word)|\(r.source_idx)|\(r.sense_index)")
                }
                log("기존 결과 파일에서 \(prior.count)건 이어받음 — 그 항목들은 건너뜁니다.")
            }
        }

        var processed = 0
        var extracted = 0
        var skippedNone = 0
        var errorCounts: [String: Int] = [:]

        for item in unmatched {
            let key = "\(item.source_word)|\(item.source_idx)|\(item.sense_index)"
            if doneKeys.contains(key) { continue }

            // 세션은 문장마다 새로 만든다 — 각 추출은 서로 독립적인 작업이라
            // 대화 맥락을 이어갈 필요가 없고, 오히려 세션 하나로 793건을
            // 전부 처리하면 대화 기록이 계속 누적되어 언젠가
            // exceededContextWindowSize에 부딪힐 위험이 있다.
            let session = LanguageModelSession(instructions: SHARED_INSTRUCTIONS)
            let prompt = "표제어: \(item.source_word)\n문장: \(item.sentence)"

            var attempt = 0
            var succeeded = false
            while attempt < 3 && !succeeded {
                attempt += 1
                do {
                    let response = try await session.respond(to: prompt, generating: ExtractionResult.self)
                    let result = response.content
                    for rel in result.relations {
                        if rel.relation_type == .none || rel.target_word.trimmingCharacters(in: .whitespaces).isEmpty {
                            skippedNone += 1
                            continue
                        }
                        results.append(AIExtractedRelationRecord(
                            source_word: item.source_word,
                            source_idx: item.source_idx,
                            sense_index: item.sense_index,
                            relation_type: rel.relation_type.rawValue,
                            target_word: rel.target_word.trimmingCharacters(in: .whitespaces),
                            raw_sentence: item.sentence,
                            model_version: modelVersionTag
                        ))
                        extracted += 1
                    }
                    succeeded = true
                } catch let error as LanguageModelSession.GenerationError {
                    switch error {
                    case .rateLimited:
                        // 속도 제한 — 잠시 쉬었다가 재시도(최대 3회)
                        errorCounts["rateLimited", default: 0] += 1
                        log("[\(item.source_word)] rate limited — 5초 대기 후 재시도 (\(attempt)/3)")
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                    case .guardrailViolation:
                        errorCounts["guardrailViolation", default: 0] += 1
                        log("[\(item.source_word)] 안전 가드레일에 걸려 건너뜀: \(item.sentence)")
                        succeeded = true  // 재시도해도 같은 결과일 가능성이 높아 넘어감
                    case .decodingFailure:
                        errorCounts["decodingFailure", default: 0] += 1
                        log("[\(item.source_word)] 구조화 출력 디코딩 실패 — 건너뜀")
                        succeeded = true
                    case .refusal:
                        errorCounts["refusal", default: 0] += 1
                        log("[\(item.source_word)] 모델이 응답을 거부함 — 건너뜀")
                        succeeded = true
                    case .unsupportedGuide:
                        errorCounts["unsupportedGuide", default: 0] += 1
                        log("치명적: 이 스키마의 @Guide 패턴을 이 모델 버전이 지원하지 않습니다. 중단합니다.")
                        try? writeJSON(results, to: outputPath)
                        exit(1)
                    case .exceededContextWindowSize:
                        errorCounts["exceededContextWindowSize", default: 0] += 1
                        log("[\(item.source_word)] 세션이 새로 만들어졌는데도 컨텍스트 초과 — 문장이 너무 길 수 있음, 건너뜀")
                        succeeded = true
                    case .assetsUnavailable, .unsupportedLanguageOrLocale:
                        errorCounts["fatal", default: 0] += 1
                        log("치명적 오류로 중단합니다: \(error)")
                        try? writeJSON(results, to: outputPath)
                        exit(1)
                    case .concurrentRequests:
                        // 순차 처리만 하므로 이론상 발생하지 않아야 함 — 방어적으로만 처리
                        errorCounts["concurrentRequests", default: 0] += 1
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                    @unknown default:
                        errorCounts["unknown", default: 0] += 1
                        log("[\(item.source_word)] 알 수 없는 GenerationError — 건너뜀: \(error)")
                        succeeded = true
                    }
                } catch {
                    errorCounts["other", default: 0] += 1
                    log("[\(item.source_word)] 예상치 못한 오류 — 건너뜀: \(error)")
                    succeeded = true
                }
            }

            processed += 1
            if processed % 20 == 0 {
                log("진행: \(processed)/\(unmatched.count - doneKeys.count + processed) 처리, \(extracted)건 추출됨")
                try? writeJSON(results, to: outputPath)
            }
        }

        try? writeJSON(results, to: outputPath)
        log("""
            완료 — 처리 \(processed)건, 관계 추출 \(extracted)건, \
            \"관계 없음\" 판정 \(skippedNone)건, 오류 유형별 건수: \(errorCounts)
            결과 파일: \(outputPath)
            다음 단계: 이 파일을 ReferenceDataSource/ 폴더에 둔 채 \
            `python3 build_reference_data.py`를 다시 실행해 PersonRelations에 병합하세요.
            """)
    }
}
