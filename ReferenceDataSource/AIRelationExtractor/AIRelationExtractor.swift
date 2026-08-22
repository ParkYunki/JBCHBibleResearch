// AIRelationExtractor.swift
//
// [2026-08-19 신설, 2026-08-20 v2 프롬프트 개정] PersonRelations 2단계(AI 보조 추출) 도구.
//
// build_reference_data.py(1단계, 정규식)가 어느 관계 패턴에도 걸리지 않은
// description 문장을 매 빌드마다 `UnmatchedRelationSentences.json`으로
// 내보낸다. 이 도구는 그 문장들을 하나씩 온디바이스 FoundationModels
// (`SystemLanguageModel`, Apple Intelligence, 완전 무료·오프라인)에 넣어
// 관계를 구조화된 형태로 추출하고, 결과를 `AIExtractedRelations.json`으로
// 저장한다. 그 파일을 `ReferenceDataSource/`에 두고 `build_reference_data.py`를
// 다시 실행하면 PersonRelations에 자동 병합된다(`extraction_method='ai'`로
// 구분됨) — 정확한 병합 로직은 build_reference_data.py의
// build_person_place_tables() 참고.
//
// ⚠️ 2026-08-20 v2 개정 배경(중요, 반드시 읽을 것):
// v1 프롬프트로 실제 사용자 기기에서 732건을 추출·병합한 뒤, 그 중 140건을
// 원문(raw_sentence) 대조로 표본 검수한 결과 **정확도가 약 11%에 불과했다**
// (1단계 정규식의 오탐율은 0.3% 미만). v1 결과는 전량 DB에서 제거하고
// `AIExtractedRelations.v1_저품질_참고용.json`으로 보관만 해 두었다(재사용 금지).
// 검수에서 반복 확인된 6가지 실패 패턴을 아래 SHARED_INSTRUCTIONS에 명시적
// 금지 규칙 + 실제 오답 사례로 추가했고, 코드 레벨 방어 필터(자기순환 차단,
// 원문에 없는 target_word 차단, 일반명사 target_word 차단)도 신설했다 — 프롬프트만
// 믿지 않고 기계적으로 검증 가능한 것은 전부 코드로 걸러낸다는 이 프로젝트의
// 원칙에 따른 것이다. model_version 태그에 "v2_2026-08-20"을 넣어 이후
// 배치와 v1을 DB에서 구분할 수 있게 했다.
//
// ⚠️ 정직한 고지(v1과 동일하게 유지): 이 파일은 FoundationModels가 실제로
// 존재하는 Apple Intelligence 지원 기기(Xcode 26+, macOS 26+)에서만
// 컴파일·실행할 수 있다. 이 프로젝트를 작업하는 환경(Linux 샌드박스)에는 그
// 프레임워크 자체가 없어 컴파일도, 실행도, 단 한 줄도 검증할 수 없었다. 아래
// API 시그니처는 v1과 동일(변경 없음, 이미 실기기에서 컴파일·실행 검증됨) —
// 이번에 바뀐 것은 SHARED_INSTRUCTIONS 문자열 내용과 결과 후처리 필터
// 로직뿐이며, 이 두 가지는 이 프로젝트의 원칙상 실기기 재실행으로만 최종
// 검증할 수 있다(v1 병합 결과를 실제 병합해 그 raw_sentence를 대조 검수한
// 것처럼, v2도 같은 방식의 표본 검수를 다시 거칠 것을 강력히 권장한다).
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
// 못하고 조용히 버려짐). v1과 동일, 변경 없음.
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
    /// 불확실/추정 표현("또는", "~일 수 있음", "동명이인")뿐일 때, 혹은 아래
    /// SHARED_INSTRUCTIONS의 2~7번 금지 규칙 중 하나에 해당할 때) 반드시 이 값을 쓴다.
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

    @Guide(description: """
        관계 대상 인물/장소의 한글 이름 표제어. relation_type이 "none"이면 빈 \
        문자열. 반드시 문장에 실제로 등장하는 고유명사만 적어라(조사·수식어는 \
        빼고 이름만) — "아들", "딸", "왕", "여자", "조상" 같은 일반명사나, \
        "~의 조상"처럼 관계를 나타내는 말이 붙은 어구를 통째로 적으면 안 된다. \
        문장에 등장하지 않는 이름을 지어내면 안 된다.
        """)
    let target_word: String
}

@Generable
struct ExtractionResult {
    @Guide(description: "이 문장에서 표제어 본인에 대해 확실하게 뽑아낼 수 있는 관계들. 없으면 빈 배열.")
    let relations: [ExtractedRelation]
}

// MARK: - 공용 지침(Instructions) — 세션마다 동일하게 재사용
//
// v2: v1 결과 732건 중 140건 표본 검수(정확도 약 11%)에서 확인된 6가지
// 반복 오류 패턴을 실제 사례와 함께 명시적으로 금지했다. 전부 이 프로젝트가
// 실제로 병합·저장했던 raw_sentence에서 가져온 진짜 사례다(지어낸 예시 아님).

let SHARED_INSTRUCTIONS = """
너는 한국어 성경 인명/지명 사전의 설명문에서 인물 관계를 뽑아내는 정보 추출기다. \
너의 이전 버전은 아래 6가지 실수를 반복해서 732건 중 89%가 틀렸다. 같은 실수를 \
반복하지 마라 — 확신이 없으면 "none"이 항상 안전한 선택이다.

각 요청마다 "표제어"(설명문이 다루는 인물 본인의 이름)와 "문장"(그 인물 설명문의 \
한 문장)을 받는다. 그 문장에서 **표제어 본인**에 대한 확실한 관계만 구조화해서 \
추출하라. 규칙은 다음과 같다.

1. [주어 착각 금지] 문장의 문법적 주어가 표제어 본인이 아니라 문장 속에 언급된 \
   다른 사람인 경우(예: 표제어가 "나하래"인데 문장이 "스루야의 아들 요압의 무기를 \
   드는 자로 활약함"이라면, "스루야의 아들"은 요압을 가리키는 것이지 나하래를 \
   가리키는 게 아니다) 그 관계를 표제어의 관계로 추출하지 말고 "none"으로 응답하라.

2. [단순 문맥 언급을 가족관계로 착각 금지 — 가장 흔한 실수] "~와 관련이 있다", \
   "~를 통해", "~와 함께" 같은 표현은 단지 같은 이야기에 등장한다는 뜻일 뿐 \
   가족관계·결혼관계가 아니다. 실제 오답 사례: "베드로를 통해 성령을 받고 세례를 \
   받음"에서 married_to를 추출하면 안 된다(단순히 세례를 받았을 뿐이다). \
   "예수님과 제자들의 사역을 헌신적으로 뒷바라지한 여성도"에서 mother_of를 \
   추출하면 안 된다(후원자일 뿐 어머니가 아니다). "브리스길라 부부의 가르침을 \
   받은 후 고린도 교회의 지도자가 됨"에서 husband_of나 grandfather_of를 \
   추출하면 안 된다(가르침을 받았을 뿐이다). 결혼은 "~와 결혼하였다"처럼 결혼 \
   자체가 명시적으로 서술된 경우에만 추출하라.

3. [조상-후손 방향 반전 금지] "OO를 조상으로 둔 후손이다" 문장은 표제어 본인이 \
   OO의 **후손**이라는 뜻이다. 이 경우 표제어를 ancestor_of나 grandfather_of \
   등으로 추출하면 방향이 정반대가 된다 — 절대 하지 마라. 게다가 OO가 "로마인", \
   "유대인", "헬라인" 같은 민족/종족이지 특정 개인 이름이 아니면, 그런 집단은 \
   인명사전의 표제어가 될 수 없으므로 애초에 관계를 추출하지 말고 "none"으로 \
   응답하라.

4. [동일인 별칭을 가족관계로 착각 금지] "~와 동일 인물이다", "본명은 ~이다", \
   "~의 헬라식/아람어 이름이다"처럼 **같은 사람의 다른 이름**을 설명하는 문장에서는 \
   어떤 relation_type도 추출하지 말고 "none"으로 응답하라. 실제 오답 사례: \
   "도르가와 동일"(다비다=도르가는 동일인)에서 sister_of를 추출하면 안 된다. \
   "본명 바예수"(엘루마=바예수는 동일인)에서 mother_of를 추출하면 안 된다.

5. [세대 단정 금지] "~ 족속의 조상이다", "~ 자손이다", "~를 조상으로 둔 \
   후손이다"처럼 여러 세대를 아우르는 표현만 있고 부모-자녀 관계(한 세대 차이)가 \
   명시적으로 확정되지 않으면, son_of/daughter_of/grandson_of/granddaughter_of/ \
   grandfather_of처럼 세대를 특정하는 관계유형을 쓰지 말고 ancestor_of나 \
   descendant_of만 사용하라. 정확한 세대 수를 함부로 단정하지 마라.

6. [성별 모순 금지] 문장에 성별이 드러나는 단어(아들/딸/형/누이/그/그녀 등)가 \
   있으면 그 성별과 모순되는 relation_type을 고르지 마라. 실제 오답 사례: \
   "아브라함과 그두라 사이에서 태어난 첫째 **아들**"에서 daughter_of를 추출하면 \
   안 된다(아들이라고 명시됐다).

7. [자기 자신 금지] target_word가 표제어 자신과 완전히 같은 이름이면 안 된다. \
   "none"으로 응답하라.

8. 문장이 "또는", "~일 수 있음", "동명이인", "추정" 같은 표현으로 불확실성을 \
   나타내면 그 관계는 추출하지 말고 "none"으로 응답하라.

9. 한 문장에 표제어 본인의 관계가 여러 개 있으면(예: "아버지의 이름은 A이고 \
   어머니는 B이다") 전부 각각의 항목으로 추출하라.

10. relation_type은 반드시 다음 정의된 값 중에서만 골라라: \
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

11. target_word는 문장에 실제로 등장하는 고유명사(사람/지명 이름)만 적는다 \
   (조사·수식어는 빼고 이름만). "아들", "왕", "여자" 같은 일반명사나 \
   "~의 조상"처럼 관계어가 붙은 어구를 통째로 적지 마라. 문장에 없는 이름을 \
   지어내지 마라.
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

// MARK: - v2 신설: 프롬프트만 믿지 않는 기계적 방어 필터
//
// 13차 부록 표본 검수에서, 프롬프트로 막기 어려운 실수들 중 코드로 100%
// 기계적으로 검증 가능한 것들만 골라 여기서 걸러낸다(추측성 필터가 아니라,
// 실제로 참/거짓을 판별할 수 있는 조건만 사용).
//   (a) 자기순환: target_word == source_word
//   (b) 환각 방지: target_word가 원문 문장에 문자 그대로 등장하지 않으면
//       (조사 등 사소한 차이는 있을 수 있으나, 최소한 부분 문자열로도 없으면
//       모델이 문장에 없는 이름을 지어냈을 가능성이 매우 높다) 버린다.
//   (c) 일반명사 target_word 차단: 실제 이름일 수 없는 흔한 일반명사/조사구.
let GENERIC_TARGET_BLOCKLIST: Set<String> = [
    "아들", "딸", "아버지", "어머니", "왕", "여자", "남자", "사람", "자손",
    "후손", "조상", "가문", "형제", "자매", "아내", "남편", "며느리", "사위",
]

func isTargetWordValid(sourceWord: String, targetWord: String, sentence: String) -> Bool {
    let target = targetWord.trimmingCharacters(in: .whitespaces)
    if target.isEmpty { return false }
    if target == sourceWord { return false }  // (a) 자기순환
    if GENERIC_TARGET_BLOCKLIST.contains(target) { return false }  // (c) 일반명사
    if target.count < 2 { return false }
    if !sentence.contains(target) { return false }  // (b) 환각 방지(원문 부분 문자열 검사)
    return true
}

// MARK: - 메인

@main
struct AIRelationExtractor {
    static func main() async {
        let inputPath = "UnmatchedRelationSentences.json"
        let outputPath = "AIExtractedRelations.json"
        let modelVersionTag = "SystemLanguageModel.default(on-device)+prompt_v2_2026-08-20"

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
        //    ⚠️ v2로 넘어오면서 프롬프트가 바뀌었으므로, v1 시절 결과 파일을
        //    그대로 이어받으면 안 된다 — README 안내대로 반드시 새 파일로
        //    시작하라(v1 결과는 이미 AIExtractedRelations.v1_저품질_참고용.json
        //    으로 옮겨 두었을 것이다).
        var results: [AIExtractedRelationRecord] = []
        var doneKeys = Set<String>()
        if FileManager.default.fileExists(atPath: outputPath) {
            if let prior = try? loadJSON(outputPath, as: [AIExtractedRelationRecord].self) {
                results = prior
                for r in prior {
                    doneKeys.insert("\(r.source_word)|\(r.source_idx)|\(r.sense_index)")
                }
                log("기존 결과 파일에서 \(prior.count)건 이어받음 — 그 항목들은 건너뜁니다. (v1 결과를 이어받는 것이라면 README를 다시 확인하세요.)")
            }
        }

        var processed = 0
        var extracted = 0
        var skippedNone = 0
        var skippedByFilter = 0
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
                        if rel.relation_type == .none {
                            skippedNone += 1
                            continue
                        }
                        let target = rel.target_word.trimmingCharacters(in: .whitespaces)
                        guard isTargetWordValid(sourceWord: item.source_word, targetWord: target, sentence: item.sentence) else {
                            skippedByFilter += 1
                            continue
                        }
                        results.append(AIExtractedRelationRecord(
                            source_word: item.source_word,
                            source_idx: item.source_idx,
                            sense_index: item.sense_index,
                            relation_type: rel.relation_type.rawValue,
                            target_word: target,
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
                log("진행: \(processed)/\(unmatched.count - doneKeys.count + processed) 처리, \(extracted)건 추출됨, 필터로 걸러짐 \(skippedByFilter)건")
                try? writeJSON(results, to: outputPath)
            }
        }

        try? writeJSON(results, to: outputPath)
        log("""
            완료 — 처리 \(processed)건, 관계 추출 \(extracted)건, \
            "관계 없음" 판정 \(skippedNone)건, 방어 필터로 걸러짐 \(skippedByFilter)건, \
            오류 유형별 건수: \(errorCounts)
            결과 파일: \(outputPath)
            다음 단계: 이 파일을 ReferenceDataSource/ 폴더에 둔 채 \
            `python3 build_reference_data.py`를 다시 실행해 PersonRelations에 병합하세요. \
            병합 후에는 지난번처럼 소량이라도 원문과 대조하는 표본 검수를 권장합니다.
            """)
    }
}
