//
//  BibleKeywordMatching.swift
//  JBCHBibleResearch
//
//  검색어 키워드 매칭 점수 계산과 친족 관계어 동의어 확장.
//  `SearchViewModel.searchVerses`(키워드 검색)와 `QueryIntentClassifier`(관계 질의 판정)가
//  같은 어휘·점수 규칙을 공유해야 해서 공용 파일로 분리했다.
//

import Foundation

/// 검색어의 친족 관계어 동의어 그룹("동생"을 검색해도 본문의 "아우"를 찾기 위함).
///
/// ⚠️ 그룹은 `ReferenceDataSource/build_reference_data.py`가 927명분 description
/// 코퍼스로 검증한 것에 사용자가 요청한 항목을 더한 것이다. 검색어 확장은 오매칭돼도
/// 그 단어가 본문에 없으면 매치되지 않을 뿐이라, 추출 패턴에서는 제외된 "처"도 포함한다.
/// 임의로 넓은 유의어 사전은 만들지 않는다.
enum RelationSynonyms {
    // 외할아버지/외조부·외할머니/외조모(모계)는 부계 조부모와 다른 사람이라 별도 그룹이다 —
    // 합치면 "다윗의 외할아버지" 검색에 부계 할아버지 본문까지 잡히는 오탐이 생긴다.
    // "동역자"는 동의어가 없지만, `allWords`(관계 질의 판정용)에 포함되려면 `groups`에 있어야 한다.
    private static let groups: [[String]] = [
        ["아버지", "부친", "아비", "아빠"],
        ["어머니", "모친", "어미", "엄마"],
        ["할아버지", "조부"],
        ["할머니", "조모"],
        ["외할아버지", "외조부"],
        ["외할머니", "외조모"],
        ["아내", "부인", "처"],
        ["형제", "오라비"],
        ["아우", "동생", "남동생", "친아우"],
        ["자매", "누이", "여동생"],
        ["숙부", "삼촌"],
        ["조상", "선조"],
        ["자손", "후손", "증손", "고손"],
        ["동역자"],
    ]

    private static let lookup: [String: [String]] = {
        var map: [String: [String]] = [:]
        for group in groups {
            for word in group { map[word] = group }
        }
        return map
    }()

    /// `word`가 속한 동의어 그룹(자기 자신 포함) — 그룹이 없으면 자기 자신 하나만
    /// 담긴 배열을 돌려준다(항상 non-empty, 호출부가 옵셔널을 다룰 필요 없게).
    static func expanded(_ word: String) -> [String] {
        lookup[word] ?? [word]
    }

    /// `QueryIntentClassifier`가 질의의 관계어 등장 여부를 판정할 때 쓰는, `groups`를 평평하게 편
    /// 전체 단어 목록(`groups`는 `private`이라 별도로 노출한다).
    static let allWords: [String] = groups.flatMap { $0 }
}

/// "모두 일치 > 일부 일치" 우선, 그 안에서는 일치한 서로 다른 단어 수로 순위를 매기는 키워드 점수.
enum KeywordMatchScorer {
    /// `allWordsMatched` 차이가 절대적으로 우선한다(한 단어가 아무리 반복돼도 "모두 일치"를 이기지
    /// 못한다). 이를 위해 `Comparable`을 튜플처럼 계층적으로 구현했다.
    struct Score: Comparable, Equatable {
        let allWordsMatched: Bool
        /// 일치한 서로 다른 단어 수. 순위 비교는 이 값에만 의존해, 흔한 단어 하나의 반복 등장이
        /// 순위를 부풀리지 못한다. 검색어가 한 단어면 매칭 결과가 모두 같은 값이라 성경순
        /// tie-break만 남는다(`SearchViewModel.searchVerses` 참고).
        let matchedWordCount: Int
        /// 매칭된 단어들(동의어 포함)의 총 등장 횟수 — 순위 비교에는 쓰이지 않고
        /// `isAnyMatch` 판정과 "N회 일치" 같은 참고 표시용이다.
        let totalOccurrences: Int

        static let none = Score(allWordsMatched: false, matchedWordCount: 0, totalOccurrences: 0)

        var isAnyMatch: Bool { totalOccurrences > 0 }

        static func < (lhs: Score, rhs: Score) -> Bool {
            if lhs.allWordsMatched != rhs.allWordsMatched {
                return !lhs.allWordsMatched && rhs.allWordsMatched
            }
            return lhs.matchedWordCount < rhs.matchedWordCount
        }

        /// `<`가 `totalOccurrences`를 무시하므로 `==`도 같은 두 필드만 비교해야 한다. 합성된 `==`를 쓰면
        /// `Comparable` 계약(`a == b` ⇔ `!(a < b) && !(b < a)`)이 깨져, `SearchViewModel.searchVerses`의
        /// `!=` 동점 판정이 어긋나 성경순 tie-break가 건너뛰어진다.
        static func == (lhs: Score, rhs: Score) -> Bool {
            lhs.allWordsMatched == rhs.allWordsMatched && lhs.matchedWordCount == rhs.matchedWordCount
        }

        /// 코사인 유사도(0~1대)와 한 배열에 섞어 정렬하는 곳(하이브리드 후보 병합)을 위한 스칼라 근사값.
        /// 모두 일치 100 / 일부 일치 50에 일치 단어 수*10 보너스를 더하며, 보너스 상한(40)은
        /// "일부 일치"가 "모두 일치" 최저점(100)을 넘지 못하게 한다.
        var numericValue: Double {
            guard totalOccurrences > 0 else { return 0 }
            let base: Double = allWordsMatched ? 100 : 50
            let bonus = min(Double(matchedWordCount) * 10, 40)
            return base + bonus
        }
    }

    /// `words`(질의를 공백으로 쪼갠 것) 각각이 `content`에 동의어 포함 몇 번 등장하는지 세어
    /// 점수를 매긴다. 대소문자는 구분하지 않는다.
    static func score(words: [String], in content: String) -> Score {
        guard !words.isEmpty else { return .none }
        let lowerContent = content.lowercased()
        var matchedWordCount = 0
        var totalOccurrences = 0
        for word in words {
            let variantOccurrences = RelationSynonyms.expanded(word).reduce(0) { sum, variant in
                sum + lowerContent.occurrenceCount(of: variant.lowercased())
            }
            if variantOccurrences > 0 {
                matchedWordCount += 1
                totalOccurrences += variantOccurrences
            }
        }
        return Score(
            allWordsMatched: matchedWordCount == words.count,
            matchedWordCount: matchedWordCount,
            totalOccurrences: totalOccurrences
        )
    }
}

extension StringProtocol {
    /// 겹치지 않는 부분 문자열 등장 횟수(`components(separatedBy:).count - 1`).
    func occurrenceCount(of substring: String) -> Int {
        guard !substring.isEmpty else { return 0 }
        return components(separatedBy: substring).count - 1
    }
}
