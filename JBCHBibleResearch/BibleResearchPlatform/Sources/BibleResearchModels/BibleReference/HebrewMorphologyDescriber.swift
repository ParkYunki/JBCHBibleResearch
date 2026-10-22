import Foundation

// 원문 정보 카드에 형태소(문법) 설명을 한글로 보여주기 위한 히브리어/아람어 디코더.
//
// 코드 체계 출처: https://hb.openscriptures.org/parsing/HebrewMorphologyCodes.html
// (Open Scriptures Hebrew Bible Project, CC BY 4.0). 원문 DB(STEPBible-Data TAHOT)도
// 같은 OSHB 형태소 코드 체계를 쓴다. 한국어 설명 문장은 새로 작성한 것이다.
//
// 그리스어(Robinson 태그)는 디코딩하지 않는다 — `OriginalWordInfo.isHebrew`가 false이면
// `morphDescriptionKo`는 빈 문자열을 돌려준다.
public enum HebrewMorphologyDescriber {

    private static let posNameKo: [Character: String] = [
        "A": String(localized: "형용사", bundle: .main), "C": String(localized: "접속사", bundle: .main), "D": String(localized: "부사", bundle: .main), "N": String(localized: "명사", bundle: .main),
        "P": String(localized: "대명사", bundle: .main), "R": String(localized: "전치사", bundle: .main), "S": String(localized: "접미사", bundle: .main), "T": String(localized: "불변화사", bundle: .main), "V": String(localized: "동사", bundle: .main),
    ]

    private static let verbStemHebrewKo: [Character: String] = [
        "q": String(localized: "칼", bundle: .main), "N": String(localized: "니팔", bundle: .main), "p": String(localized: "피엘", bundle: .main), "P": String(localized: "푸알", bundle: .main), "h": String(localized: "히필", bundle: .main), "H": String(localized: "호팔", bundle: .main),
        "t": String(localized: "히트파엘", bundle: .main), "o": String(localized: "폴렐", bundle: .main), "O": String(localized: "폴랄", bundle: .main), "r": String(localized: "히트폴렐", bundle: .main), "m": String(localized: "포엘", bundle: .main), "M": String(localized: "포알", bundle: .main),
        "k": String(localized: "팔렐", bundle: .main), "K": String(localized: "풀랄", bundle: .main), "Q": String(localized: "칼 수동", bundle: .main), "l": String(localized: "필펠", bundle: .main), "L": String(localized: "폴팔", bundle: .main), "f": String(localized: "히트팔펠", bundle: .main),
        "D": String(localized: "니트파엘", bundle: .main), "j": String(localized: "페알랄", bundle: .main), "i": String(localized: "필렐", bundle: .main), "u": String(localized: "호트파알", bundle: .main), "c": String(localized: "티필", bundle: .main),
        "v": String(localized: "히쉬타펠", bundle: .main), "w": String(localized: "니트팔렐", bundle: .main), "y": String(localized: "니트포엘", bundle: .main), "z": String(localized: "히트포엘", bundle: .main),
    ]

    private static let verbStemAramaicKo: [Character: String] = [
        "q": String(localized: "페알", bundle: .main), "Q": String(localized: "페일", bundle: .main), "u": String(localized: "히트페엘", bundle: .main), "p": String(localized: "파엘", bundle: .main), "P": String(localized: "이트파알", bundle: .main),
        "M": String(localized: "히트파알", bundle: .main), "a": String(localized: "아펠", bundle: .main), "h": String(localized: "하펠", bundle: .main), "s": String(localized: "사펠", bundle: .main), "e": String(localized: "샤펠", bundle: .main), "H": String(localized: "호팔", bundle: .main),
        "i": String(localized: "이트페엘", bundle: .main), "t": String(localized: "히쉬타펠", bundle: .main), "v": String(localized: "이쉬타펠", bundle: .main), "w": String(localized: "히타펠", bundle: .main), "o": String(localized: "폴렐", bundle: .main),
        "z": String(localized: "이트포엘", bundle: .main), "r": String(localized: "히트폴렐", bundle: .main), "f": String(localized: "히트팔펠", bundle: .main), "b": String(localized: "헤팔", bundle: .main), "c": String(localized: "티펠", bundle: .main),
        "m": String(localized: "포엘", bundle: .main), "l": String(localized: "팔펠", bundle: .main), "L": String(localized: "이트팔펠", bundle: .main), "O": String(localized: "이트폴렐", bundle: .main), "G": String(localized: "잇타팔", bundle: .main),
    ]

    private static let verbConjugationKo: [Character: String] = [
        "p": String(localized: "완료(카탈)", bundle: .main),
        "q": String(localized: "순차적 완료(베카탈)", bundle: .main),
        "i": String(localized: "미완료(이크톨)", bundle: .main),
        "w": String(localized: "순차적 미완료(바브 계속법, 와이크톨)", bundle: .main),
        "h": String(localized: "권유법(코호타티브)", bundle: .main),
        "j": String(localized: "명령법 3인칭(유씨브)", bundle: .main),
        "v": String(localized: "명령법", bundle: .main),
        "r": String(localized: "능동분사", bundle: .main),
        "s": String(localized: "수동분사", bundle: .main),
        "a": String(localized: "부정사 절대형", bundle: .main),
        "c": String(localized: "부정사 연계형", bundle: .main),
    ]

    private static let adjectiveTypeKo: [Character: String] = [
        "a": String(localized: "형용사", bundle: .main), "c": String(localized: "기수", bundle: .main), "g": String(localized: "종족명(gentilic)", bundle: .main), "o": String(localized: "서수", bundle: .main),
    ]

    private static let nounTypeKo: [Character: String] = [
        "c": String(localized: "보통명사", bundle: .main), "g": String(localized: "종족명(gentilic)", bundle: .main), "p": String(localized: "고유명사", bundle: .main),
    ]

    private static let pronounTypeKo: [Character: String] = [
        "d": String(localized: "지시대명사", bundle: .main), "f": String(localized: "부정대명사", bundle: .main), "i": String(localized: "의문대명사", bundle: .main),
        "p": String(localized: "인칭대명사", bundle: .main), "r": String(localized: "관계대명사", bundle: .main),
    ]

    private static let prepositionTypeKo: [Character: String] = [
        "d": String(localized: "정관사 결합형", bundle: .main),
    ]

    private static let suffixTypeKo: [Character: String] = [
        "d": String(localized: "방향격 헤(directional he)", bundle: .main), "h": String(localized: "부가적 헤(paragogic he)", bundle: .main),
        "n": String(localized: "부가적 눈(paragogic nun)", bundle: .main), "p": String(localized: "대명접미사", bundle: .main),
    ]

    private static let particleTypeKo: [Character: String] = [
        "a": String(localized: "긍정사", bundle: .main), "d": String(localized: "정관사", bundle: .main), "e": String(localized: "권고사", bundle: .main), "i": String(localized: "의문사", bundle: .main),
        "j": String(localized: "감탄사", bundle: .main), "m": String(localized: "지시사", bundle: .main), "n": String(localized: "부정사(否定詞)", bundle: .main), "o": String(localized: "목적격 표시어", bundle: .main),
        "r": String(localized: "관계사", bundle: .main),
    ]

    private static let personKo: [Character: String] = ["1": String(localized: "1인칭", bundle: .main), "2": String(localized: "2인칭", bundle: .main), "3": String(localized: "3인칭", bundle: .main)]
    private static let genderKo: [Character: String] = ["b": String(localized: "양성(명사)", bundle: .main), "c": String(localized: "공성(동사)", bundle: .main), "f": String(localized: "여성", bundle: .main), "m": String(localized: "남성", bundle: .main)]
    private static let numberKo: [Character: String] = ["d": String(localized: "쌍수", bundle: .main), "p": String(localized: "복수", bundle: .main), "s": String(localized: "단수", bundle: .main)]
    private static let stateKo: [Character: String] = ["a": String(localized: "절대형", bundle: .main), "c": String(localized: "연계형", bundle: .main), "d": String(localized: "한정형", bundle: .main)]
    private static let languageKo: [Character: String] = ["H": String(localized: "히브리어", bundle: .main), "A": String(localized: "아람어", bundle: .main)]

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
            return decodeNounLike(posKo: String(localized: "명사", bundle: .main), typeTable: nounTypeKo, rest: &rest)
        case "A":
            return decodeNounLike(posKo: String(localized: "형용사", bundle: .main), typeTable: adjectiveTypeKo, rest: &rest)
        case "P":
            return decodePronoun(&rest)
        case "S":
            return decodeSuffix(&rest)
        case "T":
            guard let t = rest.first else { return String(localized: "불변화사", bundle: .main) }
            return String(localized: "불변화사(\(particleTypeKo[t] ?? String(t)))", bundle: .main)
        case "R":
            guard let t = rest.first, let name = prepositionTypeKo[t] else { return String(localized: "전치사", bundle: .main) }
            return String(localized: "전치사(\(name))", bundle: .main)
        case "C":
            return String(localized: "접속사", bundle: .main)
        case "D":
            return String(localized: "부사", bundle: .main)
        default:
            return posNameKo[posCode] ?? String(localized: "품사(\(String(posCode)))", bundle: .main)
        }
    }

    private static func decodeVerb(_ rest: inout Substring, lang: Character) -> String {
        guard let stemCode = rest.first else { return String(localized: "동사", bundle: .main) }
        rest = rest.dropFirst()
        let stemTable = (lang == "H") ? verbStemHebrewKo : verbStemAramaicKo
        let stemKo = stemTable[stemCode] ?? String(localized: "어간(\(String(stemCode)))", bundle: .main)

        var conjCode: Character?
        var conjKo = ""
        if let c = rest.first {
            conjCode = c
            rest = rest.dropFirst()
            conjKo = verbConjugationKo[c] ?? String(localized: "활용형(\(String(c)))", bundle: .main)
        }

        var parts = [String(localized: "\(stemKo) 어간", bundle: .main), conjKo]

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
        var parts = [String(localized: "대명사", bundle: .main)]
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
        var parts = [String(localized: "접미사", bundle: .main)]
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
