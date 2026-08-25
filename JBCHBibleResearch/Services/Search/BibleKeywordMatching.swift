//
//  BibleKeywordMatching.swift
//  JBCHBibleResearch
//
//  [2026-08-20 신설] 사용자 요청 — "하이브리드 검색/키워드 단일 검색 공통 —
//  띄어쓰기 단어가 모두 일치하면 100, 한 단어만 일치하면 50, 그 중 여러 번
//  일치한 횟수*10처럼 가중치로 계산하고, 모두 일치해야 가장 높은 점수가
//  확보되도록 내림차순 정렬할 것" + "관계 검색에서 아우/동생, 아내/처/부인
//  같은 동의어도 처리할 것." `SearchViewModel.searchVerses`(키워드 단일
//  검색)와 `BibleSemanticSearchService`(하이브리드 검색의 키워드 후보 병합)
//  두 곳이 똑같은 점수 계산 규칙을 써야 "적어도 키워드 검색만큼은 못하지
//  않는다"는 일관성이 보장되므로, 이 둘의 세 번째 이전 사용처가 아니라
//  애초에 두 곳이 "같은 규칙을 공유해야만 하는" 관계라 공용 파일로 분리했다
//  (`SearchViewModel.storeCache` 상단 주석의 "세 번째 사용처 전엔 공통 헬퍼로
//  뽑지 않는다" 원칙과 다른 근거 — 여기는 애초부터 두 곳이 같은 계약을
//  지켜야 하는 경우다).
//
//  ⚠️ [미검증] 이 세션엔 Xcode가 없어 컴파일 확인 못 함 — 이 프로젝트의 다른
//  Swift 파일들과 같은 caveat.
//

import Foundation

/// [2026-08-20 신설] 검색어의 친족 관계어 동의어 그룹. 사용자가 "동생"이라고
/// 검색해도 본문이 "아우"라고 쓰여 있으면 찾아야 한다는 요청에 따른다.
///
/// ⚠️ [근거와 한계] 이 목록은 `ReferenceDataSource/build_reference_data.py`의
/// "12차, 동의어 확장"에서 927명분 description 코퍼스 전체를 실측해 이미
/// 검증된 그룹(조부/할아버지, 아버지/부친/아비, 아내/부인, 형제/오라비,
/// 아우/남동생, 자매/누이/여동생, 숙부/삼촌, 조상/선조)을 그대로 가져왔다 —
/// 다만 그 실측은 "description 문장에서 관계를 뽑아낼 때"라는 다른 목적(추출
/// 정밀도)을 위한 것이었고, 여기(검색어 확장, 회수율 목적)는 사용자 질의가
/// 성경 본문과 다른 단어를 써도 찾아지게 하는 것이 목적이라 성격이 다르다.
/// 그래서 "처"(build_reference_data.py는 "처형/처음/처녀"와의 오매칭 때문에
/// 추출 패턴에서는 제외했다)처럼 추출 쪽에서는 뺐지만 사용자가 이번에
/// 명시적으로 요청한 항목(아내/처/부인)은 그대로 포함했다 — 검색어 확장은
/// "이 단어가 실제 본문에 있으면 찾는다"일 뿐이라 오매칭 위험이 추출 때와
/// 다르다(오매칭돼도 그저 그 변형 단어가 본문에 없어 매치가 안 될 뿐이다).
/// 과도한 확장(오버엔지니어링)을 피하려고 사용자가 언급했거나 이미 검증된
/// 그룹만 담았다 — 임의로 폭넓은 유의어 사전을 새로 만들지 않았다.
enum RelationSynonyms {
    // [2026-08-20 갱신] 사용자 요청 — "관계에 엄마 아빠 할아버지 할머니 조부
    // 조모 외할아버지 외조부 외할머니 외조모 누이 추가할 것" + "동역자도
    // 추가할 것". `build_reference_data.py`(같은 날짜 갱신분)와 그대로 짝을
    // 맞췄다:
    //   - "아빠"/"엄마"는 기존 아버지/어머니 그룹에 합류(순수 동의어, 같은
    //     사람을 가리킴).
    //   - "할아버지/조부"(부계)는 그대로 두고, "할머니/조모"(부계 조모)를
    //     새 그룹으로 신설. "외할아버지/외조부"·"외할머니/외조모"(모계)는
    //     부계 조부모와 실제로 다른 사람을 가리키므로 각각 별도 그룹으로
    //     신설했다 — 합치면 "다윗의 외할아버지"를 검색했는데 다윗의 (부계)
    //     할아버지에 관한 본문까지 회수되는 오탐이 생긴다(build_reference_
    //     data.py의 grandmother_of/maternal_grandfather_of/maternal_
    //     grandmother_of 신설과 같은 근거).
    //   - "누이"는 이미 자매 그룹에 있어(927명분 실측으로 이미 검증됨) 추가할
    //     필요 없음 — 사용자에게 별도 확인 요망 사항으로 보고함.
    //   - "동역자"는 매칭되는 다른 동의어가 없어(코퍼스 실측: "동역자" 단독
    //     11건, 이체자·유의어 형태 없음) 원소 하나짜리 그룹으로 추가한다 —
    //     `expanded(_:)`는 그룹이 없어도 자기 자신만 담긴 배열을 돌려주므로
    //     `expanded(_:)` 동작 자체엔 이 추가가 필요 없지만, `allWords`(관계
    //     질의 판정용, 아래 주석 참고)에 포함되려면 반드시 `groups`에 있어야
    //     한다.
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

    /// [2026-08-20 추가] `QueryIntentClassifier`가 "질의에 관계어가 등장하는지"를
    /// 판정할 때 필요한, 위 `groups`를 평평하게 편 전체 단어 목록. `groups`
    /// 자체는 `private`이라(이 열거형 밖에서 "이 단어가 어떤 그룹에 속하는지"를
    /// 몰라도 되게 캡슐화한 것) 새로 추가하지 않고는 바깥에서 꺼낼 방법이
    /// 없었다 — 기존 동작(`expanded(_:)`)은 전혀 건드리지 않는 순수 추가.
    static let allWords: [String] = groups.flatMap { $0 }
}

/// [2026-08-20 신설] "단어가 모두 일치 = 최고 점수, 일부만 일치 = 그보다 낮은
/// 점수, 그 안에서는 등장 횟수가 많을수록 가중치" 요청을 코드로 옮긴 것.
enum KeywordMatchScorer {
    /// `allWordsMatched`가 다르면 그 차이가 절대적으로 우선한다(단어 하나만
    /// 반복해서 아무리 많이 나와도 "모두 일치"를 절대 이길 수 없다) — 사용자가
    /// 명시적으로 강조한 제약("특히 중요한 것은 모두 일치해야 가장 높은 점수가
    /// 확보되어야 함")을 위해 `Comparable`을 튜플처럼 계층적으로 구현했다.
    struct Score: Comparable, Equatable {
        let allWordsMatched: Bool
        /// [2026-08-25 변경] 사용자 요청 — "단어가 가장 많이 일치하는 경우를
        /// 가중치를 가장 높이되, 같은 단어가 여러번 나온다해서 가중치를
        /// 높게하지 않도록, 같은 단어가 여러번 나온다해도 한번 나온 구절과
        /// 가중치는 같게 계산할 것." 순위 비교는 이제 오직 "서로 다른 단어가
        /// 몇 개나 일치했는지"(matchedWordCount)에만 의존한다 — 흔한 단어
        /// 하나가 본문에 여러 번 등장하는 절이, 서로 다른 단어 여러 개가 각각
        /// 한 번씩만 걸린 절보다 부당하게 앞서는 일을 막는다. 검색어가 한
        /// 단어뿐이면(`words.count == 1`) 매칭되는 모든 결과의 이 값이 항상
        /// 1로 같아져(못 찾은 경우는 애초에 `isAnyMatch`가 false라 걸러진다)
        /// 가중치 차이 자체가 없어진다 — "단어가 한 개인 경우는 무조건 성경
        /// 순서" 요구사항이 이 규칙 하나로 자동으로 충족된다
        /// (`SearchViewModel.searchVerses`의 정렬 쪽 tie-break 참고).
        let matchedWordCount: Int
        /// 매칭된 단어들이(동의어 포함) 본문에 등장한 총 횟수 — 더 이상 순위
        /// 비교에는 쓰이지 않고, `isAnyMatch` 판정과 화면의 "N회 일치" 같은
        /// 참고 표시 용도로만 남겨 둔다.
        let totalOccurrences: Int

        static let none = Score(allWordsMatched: false, matchedWordCount: 0, totalOccurrences: 0)

        var isAnyMatch: Bool { totalOccurrences > 0 }

        static func < (lhs: Score, rhs: Score) -> Bool {
            if lhs.allWordsMatched != rhs.allWordsMatched {
                return !lhs.allWordsMatched && rhs.allWordsMatched
            }
            return lhs.matchedWordCount < rhs.matchedWordCount
        }

        /// 코사인 유사도(0~1대)와 한 배열에 섞어 정렬해야 하는 곳(하이브리드
        /// 검색 후보 병합)을 위한 단일 스칼라 근사값. "모두 일치 = 100,
        /// 일부만 일치 = 50"이라는 사용자 요청의 기본 골격은 그대로 두되,
        /// [2026-08-25] 보너스 산정 기준을 `totalOccurrences`(등장 총 횟수)에서
        /// `matchedWordCount`(서로 다른 단어 일치 개수)로 바꿨다 — 위 `<`와
        /// 같은 이유(반복 등장이 순위를 부풀리지 않게). 상한(40)을 두는 이유도
        /// 그대로다 — 상한이 없으면 "일부 일치" 후보의 점수가 "모두 일치"
        /// 최저점(100)을 넘어설 수 있어, 사용자가 명시한 "모두 일치해야 가장
        /// 높은 점수" 제약이 깨진다. `matchedWordCount`는 `allWordsMatched`가
        /// false인 경우 항상 `words.count - 1` 이하이므로, 실제 쓰이는 질의
        /// 길이(수 단어)에서는 이 상한에 사실상 걸리지 않는다.
        var numericValue: Double {
            guard totalOccurrences > 0 else { return 0 }
            let base: Double = allWordsMatched ? 100 : 50
            let bonus = min(Double(matchedWordCount) * 10, 40)
            return base + bonus
        }
    }

    /// `words`(질의를 공백 기준으로 쪼갠 것) 각각이 `content` 안에 동의어까지
    /// 포함해 몇 번 등장하는지 세어 점수를 매긴다. 대소문자 구분 없이 비교한다
    /// (기존 `SearchViewModel.computeWordMatchScore`와 같은 규칙).
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
    /// 겹치지 않는 부분 문자열 등장 횟수 — `components(separatedBy:).count - 1`은
    /// 흔히 쓰이는 Swift 관용구(공식 문서에 명시된 API는 아니지만, 분리자 개수는
    /// 곧 등장 횟수라는 정의 그대로다).
    func occurrenceCount(of substring: String) -> Int {
        guard !substring.isEmpty else { return 0 }
        return components(separatedBy: substring).count - 1
    }
}
