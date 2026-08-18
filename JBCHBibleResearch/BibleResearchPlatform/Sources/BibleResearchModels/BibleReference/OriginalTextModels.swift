import Foundation

// [2026-08-09 신설] 사용자 요청 — "각 절을 선택했을 때 확대보기 버튼 옆에 '원문 정보'라는
// 버튼이 있어 히브리어 그리스어 원문에 대한 정보를 넣고자 함." 데이터 출처는
// STEPBible-Data(TAHOT/TAGNT, CC BY 4.0) — Resources/OriginalText.sqlite로 변환해
// 번들에 포함한다(정확한 변환 스크립트와 컬럼 매핑 근거는 앱 README 참고).
//
// BibleVerse/Book과 같은 이유로 SwiftData @Model이 아니라 순수 값 타입 + 별도
// 읽기 전용 SQLite 접근(OriginalTextStore)으로 구현한다 — 정적 참조 데이터라
// CloudKit 동기화 대상이 아니다.

/// 절 하나에 속한 원어 단어 하나. `wordOrder`로 원문 어순대로 정렬된다.
public struct OriginalWordInfo: Sendable, Hashable, Identifiable {
    public var id: String { "\(bookId).\(chapter).\(verse)#\(wordOrder)" }

    public let bookId: Int
    public let chapter: Int
    public let verse: Int
    public let wordOrder: Int
    /// 원어 표기(히브리어/그리스어, 모음/악센트 포함).
    public let originalText: String
    /// 음역(라틴 문자 표기).
    public let transliteration: String
    /// Strong 번호(예: "G2316", "H7225") — 접두/접미 변형 문자는 제거한 표준형.
    public let strongCode: String
    /// 형태소 분석 코드(원본 표기 그대로, 예: "N-NSF", "HR/Ncfsa").
    public let morphCode: String
    /// STEPBible 원문 사전에서 뽑은 영어 뜻풀이. 관사/전치사 등 일부 기능어는
    /// 빈 문자열일 수 있다(원본 데이터에 뜻풀이가 없는 경우 — UI에서 빈 값으로 처리).
    public let glossEn: String

    /// 히브리어("H")/그리스어("G") 구분 — `strongCode`의 첫 글자로 판단한다.
    public var isHebrew: Bool { strongCode.hasPrefix("H") }

    public init(
        bookId: Int, chapter: Int, verse: Int, wordOrder: Int,
        originalText: String, transliteration: String,
        strongCode: String, morphCode: String, glossEn: String
    ) {
        self.bookId = bookId
        self.chapter = chapter
        self.verse = verse
        self.wordOrder = wordOrder
        self.originalText = originalText
        self.transliteration = transliteration
        self.strongCode = strongCode
        self.morphCode = morphCode
        self.glossEn = glossEn
    }
}
