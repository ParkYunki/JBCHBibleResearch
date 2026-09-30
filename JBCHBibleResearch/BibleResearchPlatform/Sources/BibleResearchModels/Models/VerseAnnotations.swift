import Foundation
import SwiftData

// 구간 주석 공통 구조 — 성경구절의 특정 단어/표현에 관주·표시·메모·형광펜을 붙인다.
//
// 공통 앵커 필드(번역본 코드 + 성경 좌표 + 문자 오프셋 + 스냅샷 텍스트)는 아래 모델들과 `UserContent.swift`의
// `UserMemo` 확장분(rangeStart/rangeEnd/translationCode/anchorText)이 같은 의미로 중복 선언한다 —
// SwiftData `@Model`은 프로토콜/믹스인으로 저장 프로퍼티를 공유할 수 없다.
//
// 오프셋(rangeStart/rangeEnd)은 번역본 절 원문(`BibleVerse.content`)을 `NSString`(UTF-16 단위)으로 봤을 때의
// `NSRange`와 같은 규칙이다 — `UITextView.selectedRange`/`NSTextView.selectedRange()`가 그 단위라
// 저장/조회 시 변환이 필요 없다.
//
// `anchorText`는 주석 생성 시점의 구간 텍스트 스냅샷이다. 번역본 데이터가 고쳐져 오프셋이 안 맞아도
// 이 텍스트를 본문에서 다시 찾아 자동 재정렬하는 "자가 치유"에 쓴다. 재정렬 로직은 앱 레이어의
// `VerseAnnotationRenderer`가 담당하며, 이 패키지는 순수 데이터 모델만 다룬다.

/// `VerseHighlight.style` — 형광펜(색상 배경)과 표시(밑줄)를 하나의 모델로 묶는다.
public enum VerseHighlightStyle: String, Codable, Sendable {
    /// 형광펜 — `colorTag`가 실제 배경색을 가리킨다.
    case highlight
    /// 표시 — 밑줄. 색을 안 쓰므로 `colorTag`는 보통 nil.
    case mark
}

/// 형광펜/표시 — 절 안의 특정 구간(단어/구절)에 색이나 밑줄을 입힌다.
@Model
public final class VerseHighlight {
    public var id: UUID = UUID()
    public var translationCode: String = ""
    public var bookId: Int = 1
    public var chapter: Int = 1
    public var verse: Int = 1
    public var rangeStart: Int = 0
    public var rangeEnd: Int = 0
    public var anchorText: String = ""
    public var styleRaw: String = VerseHighlightStyle.highlight.rawValue
    /// 형광펜 색상 태그(예: "yellow"/"green"/"blue"/"pink"/"purple"). 실제 색상값 매핑은 앱 레이어
    /// (`HighlightColorTag`)의 책임이다. `style == .mark`일 때는 보통 nil(표시는 색을 안 씀).
    public var colorTag: String?
    public var createdAt: Date = Date.now

    public var style: VerseHighlightStyle {
        get { VerseHighlightStyle(rawValue: styleRaw) ?? .highlight }
        set { styleRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        translationCode: String,
        bookId: Int,
        chapter: Int,
        verse: Int,
        rangeStart: Int,
        rangeEnd: Int,
        anchorText: String,
        style: VerseHighlightStyle,
        colorTag: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.translationCode = translationCode
        self.bookId = bookId
        self.chapter = chapter
        self.verse = verse
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.anchorText = anchorText
        self.styleRaw = style.rawValue
        self.colorTag = colorTag
        self.createdAt = createdAt
    }
}

// `VersePhraseNote` — `VerseHighlight`와 같은 앵커 구조(자가 치유 재정렬도 `VerseAnnotationRenderer.resolvedRange`
// 재사용)에 색상 태그 대신 짧은 설명 텍스트(`noteText`)를 담는다. 절 전체에 종속되는 `UserMemo`(개인 주석)와 달리
// 드래그한 특정 표현에 붙이는 용도다. 기존 `UserMemo.rangeStart != nil` 구간 메모는 그대로 열람/편집되지만
// 새로 만드는 경로는 이 타입을 쓴다.

/// `VersePhraseNote.noteText` 글자수 제한.
public struct NoteTextLimit {
    /// "한글 기준 200자 미만" — `String.count`(그래핌 클러스터 개수)는 한글 음절 하나를 한 글자로 세므로 그대로 들어맞는다.
    public static let maxCharacters = 199
}

@Model
public final class VersePhraseNote {
    public var id: UUID = UUID()
    public var translationCode: String = ""
    public var bookId: Int = 1
    public var chapter: Int = 1
    public var verse: Int = 1
    public var rangeStart: Int = 0
    public var rangeEnd: Int = 0
    public var anchorText: String = ""
    public var noteText: String = ""
    /// 메모상자 배경색. `HighlightColorTag`(앱 레이어 형광펜 팔레트)의 `rawValue`를 그대로 담는다 —
    /// 이 패키지는 SwiftUI/색상 타입에 의존하지 않는다(`VerseHighlight.colorTag`와 같은 패턴).
    /// 생성 시(`BibleReadingViewModel.addPhraseNote`) 한 번 무작위로 골라 저장하고 이후엔 읽기만 한다.
    /// 빈 문자열(이 필드 도입 전 메모)이면 화면 쪽이 고정 색으로 대체한다.
    public var colorTagRaw: String = ""
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now

    public init(
        id: UUID = UUID(),
        translationCode: String,
        bookId: Int,
        chapter: Int,
        verse: Int,
        rangeStart: Int,
        rangeEnd: Int,
        anchorText: String,
        noteText: String,
        colorTagRaw: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.translationCode = translationCode
        self.bookId = bookId
        self.chapter = chapter
        self.verse = verse
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.anchorText = anchorText
        self.noteText = noteText
        self.colorTagRaw = colorTagRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// `VerseCrossReference.source` — 사용자가 만든 관주인지 번들 관주 데이터셋에서 온 것인지 구분한다(번들 데이터셋은 아직 없고 스키마만 열어 둔다).
public enum VerseCrossReferenceSource: String, Codable, Sendable {
    case user
    case bundled
}

/// 관주 — 절 안의 특정 구간(또는 절 전체)을 다른 구절들과 연결한다.
@Model
public final class VerseCrossReference {
    public var id: UUID = UUID()
    public var translationCode: String = ""
    public var bookId: Int = 1
    public var chapter: Int = 1
    public var verse: Int = 1
    /// 옵셔널 — 번들 관주 데이터는 구간 정보 없이 "절 전체"에 대한 관주일 수 있다.
    /// nil이면 절 전체에 대한 관주로 취급한다.
    public var rangeStart: Int?
    public var rangeEnd: Int?
    public var anchorText: String?
    public var sourceRaw: String = VerseCrossReferenceSource.user.rawValue
    public var targets: [BibleVerseRef] = []
    public var createdAt: Date = Date.now

    /// 한 번의 "관주 연결"에서 고른 여러 구절이 몇 개의 "논리적 항목"(예: "출애굽기1:2~3" 하나가 절 2개로 분해)이었는지는
    /// `targets`만으로 알 수 없다. 저장은 절 단위로 분해된 `targets` 그대로 두고, 항목별 절 개수(`entryVerseCounts`)와
    /// 표시 문구(`entryLabels`, 예: "시112:1,3,5")를 나란히 남겨 분해 전의 정제된 문구로 표시한다.
    ///
    /// 두 배열의 길이가 다르거나 합계가 `targets.count`와 안 맞으면(필드 도입 전 데이터, 또는 target을 하나씩 지워
    /// 대응이 깨진 경우) `groupedEntries`가 nil을 돌려준다 — 호출부는 절 단위 표시로 되돌아간다.
    public var entryLabels: [String] = []
    public var entryVerseCounts: [Int] = []
    /// 대상 절을 지우는 편집(`removeCrossReferenceTarget`/`removeCrossReferenceGroup`)이 일어난 시각.
    /// 한 번도 편집되지 않았으면 nil이며, 호출부(`SidebarQuickItem.sortDate`)가 `createdAt`으로 대체 표시한다.
    /// 비-옵셔널 `Date.now` 기본값이면 SwiftData 가벼운 마이그레이션이 기존 레코드 전부를 "마이그레이션이 실행된 시각"으로
    /// 채워 정렬 날짜가 그날로 고정되므로 옵셔널로 둔다.
    ///
    /// ⚠️ 알려진 한계: 옵셔널 전환은 앞으로의 오염만 막는다. 이미 마이그레이션 시점 날짜로 채워진 기존 관주의 `updatedAt`은
    /// nil로 되돌아가지 않는다. 진짜 편집과 마이그레이션 오염을 구분할 근거가 없어 별도 자가 치유 마이그레이션은 두지 않았다.
    public var updatedAt: Date?

    public var source: VerseCrossReferenceSource {
        get { VerseCrossReferenceSource(rawValue: sourceRaw) ?? .user }
        set { sourceRaw = newValue.rawValue }
    }

    /// `entryLabels`/`entryVerseCounts`가 `targets`와 정합적일 때만 (라벨, 그
    /// 라벨에 해당하는 절들) 쌍의 배열을 돌려준다 — 정합이 안 맞으면 nil.
    public var groupedEntries: [(label: String, verses: [BibleVerseRef])]? {
        guard entryLabels.count == entryVerseCounts.count,
              !entryLabels.isEmpty,
              entryVerseCounts.allSatisfy({ $0 > 0 }),
              entryVerseCounts.reduce(0, +) == targets.count else { return nil }
        var result: [(label: String, verses: [BibleVerseRef])] = []
        var cursor = 0
        for (label, count) in zip(entryLabels, entryVerseCounts) {
            result.append((label, Array(targets[cursor..<(cursor + count)])))
            cursor += count
        }
        return result
    }

    public init(
        id: UUID = UUID(),
        translationCode: String,
        bookId: Int,
        chapter: Int,
        verse: Int,
        rangeStart: Int? = nil,
        rangeEnd: Int? = nil,
        anchorText: String? = nil,
        source: VerseCrossReferenceSource = .user,
        targets: [BibleVerseRef] = [],
        entryLabels: [String] = [],
        entryVerseCounts: [Int] = [],
        createdAt: Date = .now,
        // 기본값 nil — 새로 만드는 관주는 편집되기 전까지 "편집된 적 없음"으로 표현한다(`updatedAt` 프로퍼티 주석 참고).
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.translationCode = translationCode
        self.bookId = bookId
        self.chapter = chapter
        self.verse = verse
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.anchorText = anchorText
        self.sourceRaw = source.rawValue
        self.targets = targets
        self.entryLabels = entryLabels
        self.entryVerseCounts = entryVerseCounts
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 개역한글 난외주(단어 뜻풀이, 구약 인용 출처 등)를 절 단위로 담는다.
///
/// 각주는 절 본문의 특정 단어 위치(위첨자)에 연결되며 `anchorOffset`이 그 위치를 가리킨다.
/// `HanjaWordAnnotation`과 같이 "자가 치유" 재탐색은 하지 않는다 — 값이 이미 번역본 원문(`BibleVerse.content`)
/// 기준 UTF-16 절대 위치로 계산돼 있다(`ReferenceDataStore.marginalNotes(...)`가 `ReferenceData.sqlite`에서 그대로 읽는다).
///
/// ⚠️ 위첨자 번호는 앱이 새로 매기지 않고 원본 `<SUP>` 태그 문자열(`markerText`)을 그대로 쓴다.
/// 원본 번호는 절이 아니라 장 전체에 걸쳐 이어지고(창4:1=①, 창4:7=②) 같은 단어가 한 절에서 반복되면 같은 번호를
/// 재사용하므로(창10:25) "절마다 1부터"라는 가정과 다르다(1,616개 절 중 929개).
@Model
public final class VerseMarginalNote {
    public var id: UUID = UUID()
    public var translationCode: String = ""
    public var bookId: Int = 1
    public var chapter: Int = 1
    public var verse: Int = 1
    public var noteText: String = ""
    /// 이 각주가 붙는 단어가 절 본문에서 시작하는 지점(UTF-16 오프셋, `HanjaWordAnnotation.rangeStart`와 같은 단위).
    /// 폭이 없는 "삽입 지점"이라 값 하나만 둔다(`VerseAnnotationRenderer`가 위첨자 마커를 이 위치에 끼워 넣는다).
    /// 원본 철자가 현재 본문과 달라 위치를 못 찾은 소수 사례(1,801개 중 39개)는 nil — 본문 위첨자 없이 절 아래 목록에만 나온다.
    public var anchorOffset: Int?
    /// 원본 `02개역난외주.bdb`의 `<SUP>...</SUP>`에 찍힌 마커 글자 — 대부분 ①~⑫이지만 `*`도 쓰인다.
    /// 위첨자/각주 목록 번호로 그대로 쓴다. nil이면 화면 레이어가 빈 문자열로 대체한다.
    public var markerText: String?
    /// `VerseCrossReference.source`와 같은 개념이라 `VerseCrossReferenceSource`를 재사용한다.
    /// 지금은 항상 `.bundled`(편집 UI 없음)이며, 사용자 추가 기능이 생기면 `.user`를 쓴다.
    public var sourceRaw: String = VerseCrossReferenceSource.bundled.rawValue
    public var createdAt: Date = Date.now

    public var source: VerseCrossReferenceSource {
        get { VerseCrossReferenceSource(rawValue: sourceRaw) ?? .bundled }
        set { sourceRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        translationCode: String,
        bookId: Int,
        chapter: Int,
        verse: Int,
        noteText: String,
        anchorOffset: Int? = nil,
        markerText: String? = nil,
        source: VerseCrossReferenceSource = .bundled,
        createdAt: Date = .now
    ) {
        self.id = id
        self.translationCode = translationCode
        self.bookId = bookId
        self.chapter = chapter
        self.verse = verse
        self.noteText = noteText
        self.anchorOffset = anchorOffset
        self.markerText = markerText
        self.sourceRaw = source.rawValue
        self.createdAt = createdAt
    }
}

// 한자 단어 주석(`HanjaWordAnnotation`) — `02개역국한문.bdb`에서 뽑은 "이 절의 이 단어에 이 한자가 붙는다" 정보를
// 개역한글 본문 위에 얹는 주석 데이터다.
//
// `rangeStart`/`rangeEnd`는 `VerseHighlight`와 같은 규칙(번역본 절 원문의 UTF-16 오프셋)이다. "자가 치유"
// 재탐색은 하지 않는다 — 스냅샷이 곧 `ko` 문자열이라 필요하면 화면 레이어가 그 문자열로 다시 찾을 수 있다.
//
// ⚠️ 한자(`hanja`) 데이터의 저작권 출처는 아직 미확정이다(`02개역국한문.bdb` 자체의 출처 문제를 승계한다).

/// 개별 한자 한 글자의 훈음 정보. `ReferenceDataStore.allHanjaDictionaryEntries()`가
/// `Resources/ReferenceData.sqlite`의 `HanjaDictionary` 테이블에서 읽으며, 앱 레이어와 공유하도록 패키지 공용 타입으로 둔다.
public struct HanjaCharacterInfo: Codable, Hashable, Sendable {
    public let char: String
    public let eum: String
    public let hun: String
    public let count: Int
    /// "high"/"medium"/"review" 신뢰도 등급. "review"는 원자전 확인 없이 정리해 사용자 검수를 권장하는 희귀 한자(15자)다.
    public let confidence: String

    public init(char: String, eum: String, hun: String, count: Int, confidence: String) {
        self.char = char
        self.eum = eum
        self.hun = hun
        self.count = count
        self.confidence = confidence
    }
}

public struct HanjaWordAnnotation: Codable, Hashable, Sendable {
    /// 이 단어의 한글 표기(예: "태초"). 오프셋이 틀어졌을 때 화면 레이어가 본문에서
    /// 다시 찾는 용도로도 쓸 수 있다.
    public var ko: String
    /// 이 단어에 대응하는 한자(예: "太初"). 한 글자일 수도, 여러 글자일 수도 있다.
    public var hanja: String
    public var rangeStart: Int
    public var rangeEnd: Int

    public init(ko: String, hanja: String, rangeStart: Int, rangeEnd: Int) {
        self.ko = ko
        self.hanja = hanja
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
    }
}

// 한자 주석은 100% 번들 전용 데이터라 SwiftData/CloudKit 동기화 대상이 아니다 — `ReferenceData.sqlite`(번들, 읽기 전용)의
// `HanjaAnnotations` 테이블에서 `ReferenceDataStore.hanjaAnnotations(bookId:chapter:)`가 읽는다.
// `HanjaWordAnnotation`(바로 위)은 `@Model`이 아닌 `Codable` 값 타입이라 그 반환값으로 쓰인다.
