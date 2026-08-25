import Foundation
import SwiftData

// [2026-08-08 신설] 사용자 요청 — "성경구절의 특정단어, 특정 표현에 관주를 넣거나,
// 표시를 하거나, 메모를 넣거나, 형광펜을 칠하고 싶음." README "이어서 16" 설계
// 논의에서 합의한 "구간 주석" 공통 구조를 구현한다.
//
// 공통 앵커 필드(번역본 코드 + 성경 좌표 + 문자 오프셋 + 스냅샷 텍스트)는 아래
// 두 모델(VerseHighlight/VerseCrossReference)과 `UserContent.swift`의 `UserMemo`
// 확장분(rangeStart/rangeEnd/translationCode/anchorText) 전부가 같은 의미로
// 중복 선언한다 — SwiftData `@Model`은 프로토콜/믹스인으로 저장 프로퍼티를 공유할
// 수 없고, 이 프로젝트도 이미 성경 좌표(bookId/chapter)를 여러 모델에 값 타입으로
// 중복 선언하는 관례를 따르고 있다(`BibleCoordinates.swift` 상단 주석 참고).
//
// 오프셋(rangeStart/rangeEnd)은 그 번역본 절 원문(`BibleVerse.content`)을
// `NSString`(UTF-16 단위)으로 봤을 때의 `NSRange`와 정확히 같은 규칙을 쓴다 —
// 앱 레이어의 `UITextView.selectedRange`/`NSTextView.selectedRange()`가 원래
// 그 단위로 값을 주기 때문에, 저장/조회 양쪽에서 변환 없이 그대로 맞춰 쓸 수 있다.
//
// `anchorText`는 주석을 만든 시점에 그 구간에 있던 실제 텍스트 스냅샷이다 — 나중에
// 번역본 데이터가 고쳐져 오프셋이 안 맞아도, 이 텍스트를 본문에서 다시 찾아 자동으로
// 재정렬하는 "자가 치유" 용도다(Kindle/애플 북스 하이라이트와 같은 원리). 실제
// 재정렬 로직은 앱 레이어의 `VerseAnnotationRenderer`가 담당한다(이 패키지는 순수
// 데이터 모델만 다루고 렌더링에는 관여하지 않는다는 기존 원칙 — BibleReferenceModels.swift
// 상단 주석 참고).

/// `VerseHighlight.style` — 형광펜(색상 배경)과 표시(밑줄)를 하나의 모델로 묶는다.
/// 사용자가 "설계 논의" 단계에서 두 기능을 같은 구조로 보는 데 동의했다.
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
    /// 형광펜 색상 태그(예: "yellow"/"green"/"blue"/"pink"/"purple") — 실제 색상값
    /// 매핑은 앱 레이어(`HighlightColorTag`)의 책임이다. `style == .mark`일 때는
    /// 보통 nil(표시는 색을 안 씀).
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

/// [2026-08-11 신설] 사용자 요청 — "특정 표현부분을 드래그해서 부연설명하는 기능을
/// 추가 구현하도록. 기능명: [메모]. 메모는 단순 텍스트 입력임(한글 기준 200자
/// 미만)." `VerseHighlight`와 똑같은 앵커 구조(번역본 코드 + 성경 좌표 + 문자
/// 오프셋 + 스냅샷 텍스트, 자가 치유 재정렬도 동일하게 `VerseAnnotationRenderer.
/// resolvedRange`를 그대로 재사용한다)를 쓰되, 색상 태그 대신 짧은 설명 텍스트
/// (`noteText`)를 담는다.
///
/// ⚠️ [기존 "메모"(UserMemo)와의 관계] 이 세션 초기에 만든 `UserMemo`(리치 텍스트
/// 에디터로 여는 메모)는 이번 요청으로 화면 라벨이 "개인 주석"으로 바뀌었고,
/// 절 전체에 종속되는 용도로만 쓰인다(VerseZoomView.openPersonalNote 참고).
/// 특정 표현(드래그 구간)에 짧게 붙이는 용도는 이 `VersePhraseNote`가 새로
/// 맡는다 — 이전에 있던 "구간 메모"(`UserMemo.rangeStart != nil`로 만든 레코드)
/// 는 기존 데이터라 그대로 남아 있고 계속 열람/편집 가능하지만(사이드바/확대보기
/// 목록에 계속 나타남), 새로 만드는 경로는 이 타입을 쓴다.
public struct NoteTextLimit {
    /// "한글 기준 200자 미만" — Swift `String.count`(그래핌 클러스터 개수)는
    /// 한글 음절 하나를 문자 하나로 세므로 이 요구사항과 정확히 들어맞는다.
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
    /// [2026-08-12 추가] 사용자 요청 — "메모상자 배경색 추가: 형광펜 색 연하게
    /// 20~30%정도 랜덤 색상으로 보여지게 - 한번 지정되면 다음에 열어도 바뀌지
    /// 않게 - DB저장." `HighlightColorTag`(형광펜 5색 팔레트, 앱 레이어)의
    /// `rawValue` 문자열을 그대로 담는다 — 이 모델 패키지는 SwiftUI/색상 타입에
    /// 의존하지 않는다는 기존 원칙(`VerseHighlight.colorTag`와 같은 패턴)을
    /// 그대로 따른다. 생성 시(`BibleReadingViewModel.addPhraseNote`)에 딱 한
    /// 번 무작위로 골라 저장하고, 그 뒤로는 이 값을 그대로 읽기만 한다 — 빈
    /// 문자열이면(이 필드가 생기기 전에 만들어진 메모) 화면 쪽이 고정 색으로
    /// 안전하게 대체한다.
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

/// `VerseCrossReference.source` — 사용자가 직접 만든 관주인지, 나중에 가져올
/// 번들 관주 데이터셋에서 온 것인지 구분한다(README "이어서 16" 설계 논의 —
/// 번들 데이터셋 자체는 아직 없고, 스키마만 그 경로를 미리 열어 둔다).
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

    /// [2026-08-12 추가] 사용자 요청 — "관주를 클릭해서 볼 때는 사용자가 입력한
    /// 텍스트가 정제되어서 보여져야 함." 한 번의 "관주 연결" 조작에서 여러 구절을
    /// 고를 수 있는데(`targets`), 그 여러 구절이 실제로는 사용자가 입력/선택한 몇
    /// 개의 "논리적 항목"(예: "출애굽기1:2~3" 하나가 절 2개로 분해됨)으로 묶여
    /// 있었다는 사실을 `targets` 배열 하나만 봐서는 알 수 없다. DB 저장은 여전히
    /// `targets`(절 단위로 분해된 배열) 그대로 하되, 그 배열을 몇 개씩 끊어 읽어야
    /// 원래 "항목"이 되는지(`entryVerseCounts`, 항목별 절 개수)와 각 항목을 어떤
    /// 문구로 보여줄지(`entryLabels`, 예: "시112:1,3,5")를 나란히 남겨 둔다 —
    /// 표시할 때는 분해되기 전의 정제된 문구를 그대로 쓸 수 있다.
    ///
    /// 두 배열의 길이가 다르거나 합계가 `targets.count`와 안 맞으면(예: 이 필드가
    /// 생기기 전에 저장된 데이터, 또는 낱개 target이 하나씩 지워져 대응이 깨진
    /// 경우) `groupedEntries`가 nil을 돌려준다 — 호출부가 그때는 절 단위 표시로
    /// 안전하게 되돌아간다(이 모델은 그 폴백을 강제하지 않고 정합 여부만 알려준다).
    public var entryLabels: [String] = []
    public var entryVerseCounts: [Int] = []
    /// [2026-08-25 추가] 사용자 요청 — "왼쪽 사이드바 메뉴 명 하단 수정된 이력
    /// 리스트에 성경 내용의 ... 주석 수정한 내용도 이력에 나타날 수 있도록."
    /// 이전엔 `createdAt`만 있어 대상 절 하나만 지우는 편집(`removeCrossReferenceTarget`/
    /// `removeCrossReferenceGroup`, `BibleReadingViewModel.swift`)이 `targets`를
    /// 제자리에서 바꿔도 어떤 시각도 갱신되지 않았다 — `VersePhraseNote.updatedAt`과
    /// 완전히 같은 이유로 추가한다. 기존 레코드는 기본값(생성 시각과 같은 `.now`,
    /// 실제로는 그 레코드의 `createdAt`과 마이그레이션 시점 값이 다를 수 있지만
    /// 이 필드가 없던 과거엔 애초에 "마지막 수정" 개념 자체가 없었으므로 안전한
    /// 폴백이다)으로 채워진다 — SwiftData의 추가적(additive) 라이트웨이트
    /// 마이그레이션(신규 저장 프로퍼티 + 기본값)이라 기존 사용자 데이터에
    /// 영향을 주지 않는다(`VersePhraseNote`가 이미 같은 방식으로 검증됨).
    public var updatedAt: Date = Date.now

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
        self.sourceRaw = source.rawValue
        self.targets = targets
        self.entryLabels = entryLabels
        self.entryVerseCounts = entryVerseCounts
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// [2026-08-14 신설] 사용자 요청 — "개역한글 난외주 정보가 있음 ... 각주와
/// 국한문만" (소제목은 이번 범위 제외, `MarginalNoteSeedImporter.swift` 상단
/// 주석 참고). 인쇄본 관주성경의 "난외주"(단어 뜻풀이 — 예: "베델리엄" 옆에
/// 〔진주〕, 구약 인용 출처 — 예: 〔사 7:14〕)를 절 단위로 담는다.
///
/// ⚠️ [2026-08-14 신설 당시 의도적으로 단순화했던 부분, 2026-08-15 되돌림]
/// 원본 데이터는 각 각주가 절 본문의 특정 단어 위치(위 첨자 ①②③ 등)에
/// 연결돼 있지만, 처음엔 "절 단위 목록이면 충분하다"고 판단해
/// `rangeStart`/`rangeEnd`로 정확한 글자 위치까지 앵커링하지 않았다 —
/// 사용자 요청("난외주가 있으면 해당 단어 위첨자 숫자 추가")으로 이 판단을
/// 뒤집어 `anchorOffset`(아래)을 추가했다. `HanjaWordAnnotation`과 같은
/// 이유로 "자가 치유" 재탐색은 하지 않는다 — 값 자체가 이미 그 번역본
/// 원문(`BibleVerse.content`) 기준 UTF-16 절대 위치로 미리 계산돼 있다
/// (`ReferenceDataStore.marginalNotes(...)`가 `ReferenceData.sqlite`에서
/// 그대로 읽어 채운다).
///
/// ⚠️ [2026-08-15 재수정, 이어서 67] 위첨자 숫자를 처음엔 앱이 절마다
/// `VerseAnnotationRenderer.circledNumeral(index+1)`로 새로 매겼는데,
/// 사용자 질문("원본 태그 번호를 유지했는가?")에 실측으로 답하며 드러난
/// 사실 — 원본 번호는 절 단위가 아니라 장(chapter) 전체에 걸쳐 이어지고
/// (창4:1=①, 창4:7=②, 창4:16=③), 같은 단어가 한 절에 반복되면 같은
/// 번호를 재사용하기도 한다(창10:25 — "나눔" 두 번 다 ①) — 전체 1,616개
/// 절 중 929개(57%)가 "절마다 1부터"라는 가정과 달랐다. 사용자가 "원본
/// 글자 그대로"를 선택해, `markerText`(아래)에 원본 `<SUP>` 태그 캡처
/// 문자열을 그대로 담고 앱은 더 이상 번호를 새로 매기지 않는다.
@Model
public final class VerseMarginalNote {
    public var id: UUID = UUID()
    public var translationCode: String = ""
    public var bookId: Int = 1
    public var chapter: Int = 1
    public var verse: Int = 1
    public var noteText: String = ""
    /// [2026-08-15 신설] 이 각주가 붙는 단어가 절 본문에서 시작하는 지점
    /// (UTF-16 오프셋, `HanjaWordAnnotation.rangeStart`와 같은 단위/규칙).
    /// 폭이 없는 "삽입 지점"이라 시작/끝 두 값 대신 하나만 둔다(위첨자
    /// 마커를 이 위치에 끼워 넣는 용도 — `VerseAnnotationRenderer`가 소비).
    /// 원본 철자가 지금 쓰는 개역한글 본문과 달라 위치를 못 찾은 소수
    /// 사례(1,801개 중 39개, `extract_marginal_note_anchors.py` 참고)는
    /// nil — 그 각주는 본문 안 위첨자 없이 절 아래 목록에만 나온다.
    public var anchorOffset: Int?
    /// [2026-08-15 신설, 이어서 67] 원본 `02개역난외주.bdb`의 `<SUP>...</SUP>`
    /// 안에 실제로 찍혀 있던 마커 글자 — 대부분 ①②③...⑫이지만 `*`도 쓰인다
    /// (전체 마커 중 275건). 앱이 새로 번호를 매기지 않고 이 값을 그대로
    /// 위첨자/각주 목록 번호로 쓴다(위 클래스 주석 참고). 원본에도 안 찍혀
    /// 있을 이유는 없지만(모든 각주가 `<SUP>`에서 나온 것), 만약을 대비해
    /// 옵셔널로 둔다 — nil이면 화면 레이어가 안전하게 빈 문자열로 대체한다.
    public var markerText: String?
    /// `VerseCrossReference.source`와 완전히 같은 개념(user/bundled)이라 새 enum을
    /// 따로 선언하지 않고 `VerseCrossReferenceSource`를 그대로 재사용했다 — 지금은
    /// 항상 `.bundled`지만(편집 UI가 없음), 이후 사용자가 직접 각주를 추가하는
    /// 기능이 생기면 `.user`를 그대로 쓸 수 있다.
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

/// [2026-08-14 신설] 사용자 요청 — "두 번째 번역본(국한문 전체 중복 테이블)을
/// 지우고 → 절 단위 한자 주석 모델." 기존 `TranslationRegistry(code: "KRV_HANJA")`
/// 두 번째 번들 번역본을 없애는 대신, `02개역국한문.bdb`에서 뽑아낸 "이 절의 이
/// 단어에 이 한자가 붙는다" 정보를 개역한글 본문 위에 얹는 주석 데이터로 저장한다.
///
/// `words`의 `rangeStart`/`rangeEnd`는 `VerseHighlight`와 완전히 같은 규칙 —
/// 그 번역본 절 원문(`BibleVerse.content`)을 UTF-16 단위로 봤을 때의 오프셋이다.
/// 다만 여기서는 "자가 치유" 재탐색을 하지 않는다(`anchorText` 스냅샷이 곧
/// `words[i].ko`이므로, 화면 레이어가 필요하면 `ko` 문자열로 그때그때 다시 찾을
/// 수 있어 별도 재정렬 로직이 필요 없다).
///
/// 한 절에 여러 한자 단어가 있을 수 있어(예: 창1:1 = 태초/천지/창조 3개) 단어
/// 하나당 레코드를 만들지 않고 절 하나당 레코드 하나에 배열로 묶었다 — 단어
/// 단위로 만들면 122,730건이 되어 `CrossReferenceSeedImporter` 상단 주석에 적어둔
/// CloudKit 요청 제한 문제가 훨씬 커진다. 절 단위로 묶으면 29,288건으로 줄어든다.
///
/// ⚠️ 이 데이터의 한자 자체(`hanja`)의 저작권 출처 확인 상태는 `TranslationBootstrap.
/// ensureHanjaTranslationRegistered`(구 버전, 이번에 제거)에 남겼던 것과 동일하게
/// 아직 미확정이다 — `02개역국한문.bdb` 자체의 출처 논의(README "이어서 59")를
/// 그대로 승계한다.
/// [2026-08-15 신설] 사용자 요청 — "성경관련 json seed 파일은 기본 제공 db에
/// 넣을 것 ... 한문사전." 개별 한자 한 글자의 훈음 정보. 예전엔
/// `Resources/HanjaDictionary.json`을 앱 레이어(`HanjaDictionaryProvider`)가
/// 직접 읽었지만, 이제 `Resources/ReferenceData.sqlite`의 `HanjaDictionary`
/// 테이블에서 `ReferenceDataStore.allHanjaDictionaryEntries()`가 읽어 온다 —
/// 반환 타입을 패키지 공용으로 옮겨 앱 레이어와 공유한다.
public struct HanjaCharacterInfo: Codable, Hashable, Sendable {
    public let char: String
    public let eum: String
    public let hun: String
    public let count: Int
    /// "high"/"medium"/"review" — `HanjaDictionary.json` 생성 스크립트가 매긴
    /// 신뢰도 등급(README "이어서 60" 참고). "review"는 Claude가 원자전 확인
    /// 없이 정리해 사용자 검수를 권장하는 희귀 한자(15자).
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

// [2026-08-15 삭제, 같은 날 되돌림] `VerseHanjaAnnotation` `@Model`(SwiftData/
// CloudKit 저장)이 여기 있었다. 사용자 요청 — "성경관련 json seed 파일은 기본
// 제공 db에 넣을 것 ... 한자주석." 한자 주석은 100% 번들 전용 데이터라(사용자가
// 직접 만드는 경로가 없음, `VerseCrossReference`/`VerseMarginalNote`와 달리
// "미래에 사용자가 추가할 수도" 여지도 없었다) SwiftData/CloudKit에 담아
// 기기마다 동기화할 이유가 전혀 없었다 — `ReferenceData.sqlite`(번들, 읽기
// 전용)의 `HanjaAnnotations` 테이블로 완전히 대체했다(`ReferenceDataStore.
// hanjaAnnotations(bookId:chapter:)` 참고). 이 세션 당일 안에 만들었다 지운
// 모델이라 기존 사용자 데이터 마이그레이션도 필요 없었다. `HanjaWordAnnotation`
// (바로 위) 자체는 그대로 남아 있다 — `@Model`이 아니라 처음부터 평범한
// `Codable` 값 타입이었어서, `ReferenceDataStore`의 반환값으로 그대로 재사용한다.
