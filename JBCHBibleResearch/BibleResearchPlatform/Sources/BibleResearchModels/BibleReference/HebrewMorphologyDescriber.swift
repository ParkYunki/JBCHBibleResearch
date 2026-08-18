import Foundation

// [2026-08-13 신설] "원문 정보" 카드에 형태소(문법) 설명을 한글로 보여주기 위한 디코더.
//
// 코드 체계 출처(정의표만 참고 — 코드 자체는 저작물이 아니라 언어학적 분류 체계):
//   https://hb.openscriptures.org/parsing/HebrewMorphologyCodes.html
//   (Open Scriptures Hebrew Bible Project, CC BY 4.0)
// STEPBible-Data(TAHOT, 이 프로젝트가 실제로 사용 중인 원문 DB의 출처)도 동일한
// OSHB 형태소 코드 체계를 그대로 쓴다.
//
// 이 파일이 만들어 내는 한국어 문장 자체는 우리가 새로 작성한 것이며, 특정 상용
// 원어성경 DB의 문장을 옮긴 것이 아니다. (scratchpad의 morph_parser.py를 그대로
// Swift로 이식 — 창세기 1장/출애굽기 2장/나훔 1~2장 데이터로 결과를 검증했다.)
//
// 그리스어(Robinson 태그, 예: "N-NSF")는 신뢰할 만한 단일 출처를 확보하지 못해
// 이번에는 디코딩하지 않는다 — `OriginalWordInfo.isHebrew`가 false인 경우
// `morphDescriptionKo`는 빈 문자열을 돌려준다.
public enum HebrewMorphologyDescriber {

    private static let posNameKo: [Character: String] = [
        "A": "형용사", "C": "접속사", "D": "부사", "N": "명사",
        "P": "대명사", "R": "전치사", "S": "접미사", "T": "불변화사", "V": "동사",
    ]

    private static let verbStemHebrewKo: [Character: String] = [
        "q": "칼", "N": "니팔", "p": "피엘", "P": "푸알", "h": "히필", "H": "호팔",
        "t": "히트파엘", "o": "폴렐", "O": "폴랄", "r": "히트폴렐", "m": "포엘", "M": "포알",
        "k": "팔렐", "K": "풀랄", "Q": "칼 수동", "l": "필펠", "L": "폴팔", "f": "히트팔펠",
        "D": "니트파엘", "j": "페알랄", "i": "필렐", "u": "호트파알", "c": "티필",
        "v": "히쉬타펠", "w": "니트팔렐", "y": "니트포엘", "z": "히트포엘",
    ]

    private static let verbStemAramaicKo: [Character: String] = [
        "q": "페알", "Q": "페일", "u": "히트페엘", "p": "파엘", "P": "이트파알",
        "M": "히트파알", "a": "아펠", "h": "하펠", "s": "사펠", "e": "샤펠", "H": "호팔",
        "i": "이트페엘", "t": "히쉬타펠", "v": "이쉬타펠", "w": "히타펠", "o": "폴렐",
        "z": "이트포엘", "r": "히트폴렐", "f": "히트팔펠", "b": "헤팔", "c": "티펠",
        "m": "포엘", "l": "팔펠", "L": "이트팔펠", "O": "이트폴렐", "G": "잇타팔",
    ]

    private static let verbConjugationKo: [Character: String] = [
        "p": "완료(카탈)",
        "q": "순차적 완료(베카탈)",
        "i": "미완료(이크톨)",
        "w": "순차적 미완료(바브 계속법, 와이크톨)",
        "h": "권유법(코호타티브)",
        "j": "명령법 3인칭(유씨브)",
        "v": "명령법",
        "r": "능동분사",
        "s": "수동분사",
        "a": "부정사 절대형",
        "c": "부정사 연계형",
    ]

    private static let adjectiveTypeKo: [Character: String] = [
        "a": "형용사", "c": "기수", "g": "종족명(gentilic)", "o": "서수",
    ]

    private static let nounTypeKo: [Character: String] = [
        "c": "보통명사", "g": "종족명(gentilic)", "p": "고유명사",
    ]

    private static let pronounTypeKo: [Character: String] = [
        "d": "지시대명사", "f": "부정대명사", "i": "의문대명사",
        "p": "인칭대명사", "r": "관계대명사",
    ]

    private static let prepositionTypeKo: [Character: String] = [
        "d": "정관사 결합형",
    ]

    private static let suffixTypeKo: [Character: String] = [
        "d": "방향격 헤(directional he)", "h": "부가적 헤(paragogic he)",
        "n": "부가적 눈(paragogic nun)", "p": "대명접미사",
    ]

    private static let particleTypeKo: [Character: String] = [
        "a": "긍정사", "d": "정관사", "e": "권고사", "i": "의문사",
        "j": "감탄사", "m": "지시사", "n": "부정사(否定詞)", "o": "목적격 표시어",
        "r": "관계사",
    ]

    private static let personKo: [Character: String] = ["1": "1인칭", "2": "2인칭", "3": "3인칭"]
    private static let genderKo: [Character: String] = ["b": "양성(명사)", "c": "공성(동사)", "f": "여성", "m": "남성"]
    private static let numberKo: [Character: String] = ["d": "쌍수", "p": "복수", "s": "단수"]
    private static let stateKo: [Character: String] = ["a": "절대형", "c": "연계형", "d": "한정형"]
    private static let languageKo: [Character: String] = ["H": "히브리어", "A": "아람어"]

    /// 전체 형태소 코드(예: "HC/Vqw3ms")를 한국어 설명 문장으로 변환한다.
    /// 언어 문자(H/A)는 전체 문자열의 첫 세그먼트에만 한 번 붙는다는 OSHB 명세를
    /// 그대로 따른다 — 두 번째 이후 세그먼트는 언어 문자 없이 품사 코드부터 시작.
    public static func describe(_ morphCode: String) -> String {
        guard !morphCode.isEmpty else { return "" }
        var segments = morphCode.split(separator: "/", omittingEmptySubsequences: false).map(String.init)

        var lang: Character = "H"
        if let first = segments.first, let firstChar = first.first, languageKo[firstChar] != nil {
            lang = firstChar
            segments[0] = String(first.dropFirst())
        }

        let described = segments.map { decodeSegment($0, lang: lang) }.filter { !$0.isEmpty }
        return described.joined(separator: " + ")
    }

    // MARK: - Segment decoding

    private static func decodeSegment(_ body: String, lang: Character) -> String {
        guard let posCode = body.first else { return "" }
        var rest = Substring(body.dropFirst())

        switch posCode {
        case "V":
            return decodeVerb(&rest, lang: lang)
        case "N":
            return decodeNounLike(posKo: "명사", typeTable: nounTypeKo, rest: &rest)
        case "A":
            return decodeNounLike(posKo: "형용사", typeTable: adjectiveTypeKo, rest: &rest)
        case "P":
            return decodePronoun(&rest)
        case "S":
            return decodeSuffix(&rest)
        case "T":
            guard let t = rest.first else { return "불변화사" }
            return "불변화사(\(particleTypeKo[t] ?? String(t)))"
        case "R":
            guard let t = rest.first, let name = prepositionTypeKo[t] else { return "전치사" }
            return "전치사(\(name))"
        case "C":
            return "접속사"
        case "D":
            return "부사"
        default:
            return posNameKo[posCode] ?? "품사(\(posCode))"
        }
    }

    private static func decodeVerb(_ rest: inout Substring, lang: Character) -> String {
        guard let stemCode = rest.first else { return "동사" }
        rest = rest.dropFirst()
        let stemTable = (lang == "H") ? verbStemHebrewKo : verbStemAramaicKo
        let stemKo = stemTable[stemCode] ?? "어간(\(stemCode))"

        var conjCode: Character?
        var conjKo = ""
        if let c = rest.first {
            conjCode = c
            rest = rest.dropFirst()
            conjKo = verbConjugationKo[c] ?? "활용형(\(c))"
        }

        var parts = ["\(stemKo) 어간", conjKo]

        // 분사/부정사가 아니면 인칭이 옴
        if let cc = conjCode, ["p", "q", "i", "w", "h", "j", "v"].contains(cc) {
            if let c = rest.first, let p = personKo[c] {
                parts.append(p)
                rest = rest.dropFirst()
            } else if rest.first == "x" {
                rest = rest.dropFirst()
            }
        }

        if let c = rest.first, let g = genderKo[c] {
            parts.append(g)
            rest = rest.dropFirst()
        }
        if let c = rest.first, let n = numberKo[c] {
            parts.append(n)
            rest = rest.dropFirst()
        }
        // 분사(r,s)는 state를 가질 수 있음
        if let c = rest.first, let s = stateKo[c] {
            parts.append(s)
            rest = rest.dropFirst()
        }

        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func decodeNounLike(posKo: String, typeTable: [Character: String], rest: inout Substring) -> String {
        var parts = [posKo]
        if let t = rest.first, let name = typeTable[t] {
            parts.append(name)
            rest = rest.dropFirst()
        }
        if let c = rest.first, let g = genderKo[c] {
            parts.append(g)
            rest = rest.dropFirst()
        }
        if let c = rest.first, let n = numberKo[c] {
            parts.append(n)
            rest = rest.dropFirst()
        }
        if let c = rest.first, let s = stateKo[c] {
            parts.append(s)
            rest = rest.dropFirst()
        }
        return parts.joined(separator: " ")
    }

    private static func decodePronoun(_ rest: inout Substring) -> String {
        var parts = ["대명사"]
        if let t = rest.first, let name = pronounTypeKo[t] {
            parts.append(name)
            rest = rest.dropFirst()
        }
        if let c = rest.first, let p = personKo[c] {
            parts.append(p)
            rest = rest.dropFirst()
        }
        if let c = rest.first, let g = genderKo[c] {
            parts.append(g)
            rest = rest.dropFirst()
        }
        if let c = rest.first, let n = numberKo[c] {
            parts.append(n)
            rest = rest.dropFirst()
        }
        return parts.joined(separator: " ")
    }

    private static func decodeSuffix(_ rest: inout Substring) -> String {
        var parts = ["접미사"]
        if let t = rest.first, let name = suffixTypeKo[t] {
            parts.append(name)
            rest = rest.dropFirst()
        }
        if let c = rest.first, let p = personKo[c] {
            parts.append(p)
            rest = rest.dropFirst()
        }
        if let c = rest.first, let g = genderKo[c] {
            parts.append(g)
            rest = rest.dropFirst()
        }
        if let c = rest.first, let n = numberKo[c] {
            parts.append(n)
            rest = rest.dropFirst()
        }
        return parts.joined(separator: " ")
    }
}

extension OriginalWordInfo {
    /// 형태소 코드를 한국어 문법 설명으로 변환한 값(히브리어만 지원, 그리스어는 빈 문자열).
    /// UI(OriginalTextInfoView)에서 카드 하단 설명 텍스트로 쓴다.
    public var morphDescriptionKo: String {
        guard isHebrew else { return "" }
        return HebrewMorphologyDescriber.describe(morphCode)
    }
}
