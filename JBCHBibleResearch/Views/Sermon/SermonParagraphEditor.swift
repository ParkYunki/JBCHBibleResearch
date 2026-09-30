//
//  SermonParagraphEditor.swift
//  JBCHBibleResearch
//
//  [2026-09-28 3단계(에디터) 신설] 설계 문서 5장 확정사항 — "기존 `RichTextEditor`는
//  건드리지 않고, 설교 전용 새 에디터 컴포넌트를 별도로 만든다"(설계 문서 근거:
//  `RichTextEditor.swift`가 2026-08-09에 "메모장처럼 풀 텍스트, 문단 구분 없음"으로
//  전면 교체되며 문단 스타일 기능 자체를 의도적으로 제거했다 — 그 결정을 다시
//  건드리지 않기 위해 별도 컴포넌트로 분리한다). 저수준 `NSTextView`/`UITextView`
//  래핑 구조 자체는 `RichTextEditor.swift`의 것을 그대로 참고했지만(플랫폼별
//  `#if os(iOS)/#elseif os(macOS)` 완전 분기, `RichTextEditingProxy`,
//  `NSTextStorageDelegate` 훅 등 이 프로젝트의 기존 관례), 코드는 공유하지 않고
//  완전히 새 타입으로 둔다 — 두 컴포넌트가 서로 다른 진화를 해도 서로 건드리지
//  않게 하기 위함(이 파일의 존재 이유 자체가 "기존 걸 건드리지 않기" 위함이므로).
//
//  ⚠️ [저장 포맷, 중요] `RichTextEditor.swift` 상단 주석에서 직접 확인한 사실 —
//  `contentHtml`은 실제로는 RTF 문자열이고(2026-08-09부터), RTF는 폰트/색상/
//  문단정렬 같은 "표준" 서식만 보존하며 커스텀 attribute는 저장 과정에서 사라진다.
//  그래서 이 에디터는 문단 스타일(`SermonParagraphStyle`)을 `contentHtml`(RTF) 안에
//  넣지 않고, `Sermon`/`SermonDelivery.paragraphStyles`라는 별도 필드에 병행
//  저장한다(`SermonParagraphStyleCodec` 참고). RTF 인코딩/디코딩 자체는
//  `RichTextEditor.swift`의 `RichTextCodec`(같은 모듈, public 아님/internal이라
//  그대로 재사용 가능)을 그대로 쓴다 — 이 부분까지 새로 만들 근거가 없다.
//
//  ⚠️ [렌더링 원칙] 문단 스타일의 실제 폰트/크기/줄간격은 저장 시점에 고정하지
//  않고, 항상 그 순간의 `UserSettingsStore` 값에서 다시 계산한다(설계 문서 3.3 —
//  "각 스타일의 폰트/크기는 사용자가 나중에 바꿀 수 있어야 한다"). 즉 이미 저장된
//  설교라도 에디터를 다시 열면 그 시점의 최신 설정으로 다시 그려진다 — 별도의
//  "열려 있는 에디터에 설정 변경을 실시간 반영" 메커니즘은 만들지 않았다(설정을
//  바꾼 뒤 화면을 다시 열면 자연히 최신값으로 보이므로, 그 이상의 복잡도를 더할
//  근거가 없다고 판단했다).
//
//  ⚠️ [굵게/기울임 보존] RTF는 굵게/기울임을 표준 서식으로 정확히 보존한다.
//  문단 스타일 폰트를 다시 계산해 적용할 때 문단 전체의 `.font`를 통째로
//  덮어쓰면 이 굵게/기울임 정보가 사라진다 — `SermonParagraphStyleCodec.
//  fontPreservingBoldItalic(from:applying:)`가 문단 안 각 글자 단위(run)의
//  기존 굵게/기울임 비트만 골라 새 폰트에 다시 입혀 이 문제를 막는다.
//
//  ⚠️ [Xcode 확인 필요] 아래 항목들은 이 세션이 Xcode 빌드/실기기 테스트를 할 수
//  없어 코드 리뷰만으로 작성됐다 — 실제 빌드 후 반드시 확인해 주세요:
//    1. `fontPreservingBoldItalic`의 `withSymbolicTraits` 결과(플랫폼별 옵셔널
//       차이는 `RichTextEditor.swift`의 `togglingTrait` 관례를 그대로 따랐다).
//    2. `insertVerseQuoteParagraph`의 문단 인덱스 계산 — 특히 빈 문서, 커서가
//       문서 맨 앞/맨 뒤에 있을 때, 연속된 빈 줄이 있을 때의 경계 케이스.
//    3. `SermonParagraphStyleCodec.apply`가 문단 수와 저장된 스타일 개수가
//       어긋난 실제 데이터(예: 사용자가 수동으로 줄바꿈만 추가한 경우)에도
//       크래시 없이 `.body`로 안전하게 대체하는지.
//

import SwiftUI
import BibleResearchModels
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - 커스텀 attribute 키

extension NSAttributedString.Key {
    /// 문단 하나가 어떤 `SermonParagraphStyle`인지 표시하는 커스텀 attribute.
    /// 값은 `SermonParagraphStyle.rawValue`(String)다. RTF로 저장되지 않으므로
    /// (상단 주석 참고) 오직 편집 중(in-memory)에만 의미가 있고, 저장은
    /// `SermonParagraphStyleCodec.export`가 별도 필드로 담당한다.
    static let sermonParagraphStyle = NSAttributedString.Key("com.jbch.sermon.paragraphStyle")
}

// MARK: - 문단 스타일 ↔ 저장 문자열 변환

enum SermonParagraphStyleCodec {
    /// 문단 스타일 배열을 하나의 문자열로 합칠 때 쓰는 구분자 — ASCII Unit
    /// Separator(U+001F). 사용자가 실제로 타이핑할 수 있는 문자가 아니라서
    /// `SermonParagraphStyle.rawValue`(영문 카멜케이스)와 절대 충돌하지 않는다.
    static let delimiter = "\u{1F}"

    /// [2026-09-29 5번 항목(수동 서식 항상 유지) 신설] 마지막 저장 시점에 각
    /// `SermonParagraphStyle`이 실제로 어떤 폰트/크기/색이었는지 찍어 둔 스냅샷
    /// 한 칸 — `Sermon.styleFontSnapshot`/`SermonDelivery.styleFontSnapshot`
    /// 상단 주석에 이 값이 왜 필요한지 자세히 적어 뒀다. `applyStyle`이 이
    /// 스냅샷과 "지금 이 글자의 실제 폰트/색"을 비교해, 다르면 "사용자가
    /// 수동으로 바꿔 둔 것"으로 보고 보존한다.
    struct StyleSnapshot: Codable {
        var fontName: String
        var fontSize: Double
        var colorHex: String
    }

    /// 지금 `UserSettingsStore`의 6종 스타일 값을 JSON 문자열로 찍는다 — 매
    /// 저장(`export`가 아니라 `SermonEditorView.save()`가 호출하는 시점)마다
    /// 새로 계산해 `styleFontSnapshot`에 넣는다.
    static func captureSnapshot(settings: UserSettingsStore) -> String {
        var dict: [String: StyleSnapshot] = [:]
        for style in SermonParagraphStyle.allCases {
            dict[style.rawValue] = StyleSnapshot(
                fontName: settings.sermonFontName(for: style),
                fontSize: settings.sermonFontSize(for: style),
                colorHex: settings.sermonFontColorHex(for: style)
            )
        }
        guard let data = try? JSONEncoder().encode(dict), let json = String(data: data, encoding: .utf8) else { return "" }
        return json
    }

    /// 저장된 스냅샷 문자열을 `[SermonParagraphStyle: StyleSnapshot]`로
    /// 되돌린다 — 비어 있거나(처음 저장되는 문서) 디코딩에 실패하면(과거
    /// 데이터 등) 빈 딕셔너리를 돌려줘, 호출부가 "스냅샷 없음 = 아직 아무것도
    /// 수동 지정된 적 없음"으로 안전하게 처리하게 한다.
    static func decodeSnapshot(_ raw: String) -> [SermonParagraphStyle: StyleSnapshot] {
        guard !raw.isEmpty, let data = raw.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: StyleSnapshot].self, from: data) else { return [:] }
        var result: [SermonParagraphStyle: StyleSnapshot] = [:]
        for (key, value) in dict {
            guard let style = SermonParagraphStyle(rawValue: key) else { continue }
            result[style] = value
        }
        return result
    }

    /// 편집기 텍스트 스토리지를 문단(`NSString.enumerateSubstrings(options:
    /// .byParagraphs)`, Apple 표준 API — 직접 인덱스를 계산하는 것보다 경계
    /// 케이스에 안전하다) 단위로 순회하며 각 문단의 `.sermonParagraphStyle`
    /// attribute를 읽어 저장용 문자열로 합친다. attribute가 없는 문단(예: 옛
    /// 데이터를 막 불러온 직후, 아직 `apply`를 거치지 않은 상태)은 `.body`로
    /// 채운다.
    static func export(from textStorage: NSTextStorage) -> String {
        let fullText = textStorage.string as NSString
        guard fullText.length > 0 else { return "" }
        var styles: [String] = []
        fullText.enumerateSubstrings(
            in: NSRange(location: 0, length: fullText.length), options: .byParagraphs
        ) { _, paragraphRange, _, _ in
            let style = (textStorage.attribute(.sermonParagraphStyle, at: paragraphRange.location, effectiveRange: nil) as? String)
                ?? SermonParagraphStyle.body.rawValue
            styles.append(style)
        }
        return styles.joined(separator: delimiter)
    }

    /// 저장된 문자열을 실제 텍스트 스토리지에 되돌린다 — 각 문단에
    /// `.sermonParagraphStyle` attribute를 심고, 그 스타일의 "현재" 설정값
    /// (폰트/크기/줄간격)을 적용한다. 문단 수와 저장된 개수가 어긋나면(과거
    /// 데이터, 수동 편집 등) 모자란 자리는 `.body`로 채운다 — 에디터가 절대
    /// 크래시하지 않아야 한다는 이 프로젝트의 기존 방어적 원칙
    /// (`BundledFontRegistrar` 등)과 동일하다.
    static func apply(_ stored: String, to textStorage: NSTextStorage, settings: UserSettingsStore, previousSnapshot: String = "") {
        let raw = stored.isEmpty ? [] : stored.components(separatedBy: delimiter)
        let fullText = textStorage.string as NSString
        guard fullText.length > 0 else { return }
        let snapshot = decodeSnapshot(previousSnapshot)
        var index = 0
        textStorage.beginEditing()
        fullText.enumerateSubstrings(
            in: NSRange(location: 0, length: fullText.length), options: .byParagraphs
        ) { _, paragraphRange, _, _ in
            defer { index += 1 }
            guard paragraphRange.length > 0 else { return }
            let style = (index < raw.count ? SermonParagraphStyle(rawValue: raw[index]) : nil) ?? .body
            applyStyle(style, to: paragraphRange, in: textStorage, settings: settings, previousSnapshot: snapshot)
        }
        textStorage.endEditing()
    }

    /// 문단 하나(`paragraphRange`)에 스타일 하나를 적용하는 실제 로직 —
    /// `apply(_:to:settings:previousSnapshot:)`(불러오기)와 편집기의 스타일
    /// pill(사용자가 지금 고르는 경우) 양쪽이 공유한다.
    ///
    /// [2026-09-29 5번 항목 확장] `previousSnapshot`(마지막 저장 시점의 프리셋
    /// 값, 비어 있으면 "아직 아무것도 수동 지정된 적 없음")과 "지금 이 글자의
    /// 실제 폰트/색"을 비교해 다르면 사용자가 수동으로 지정한 것으로 보고
    /// 그대로 둔다 — 같으면(또는 스냅샷이 아예 없으면) 새 프리셋값을 새로
    /// 계산해 적용한다(기존 동작, 굵게/기울임은 계속 보존). 정렬은 프리셋
    /// 자체가 값을 지정하지 않으므로(항상 `.natural`) "natural이 아니면 곧
    /// 수동 지정"으로 판단한다 — 별도 스냅샷이 필요 없다.
    static func applyStyle(
        _ style: SermonParagraphStyle, to paragraphRange: NSRange,
        in textStorage: NSTextStorage, settings: UserSettingsStore,
        previousSnapshot: [SermonParagraphStyle: StyleSnapshot] = [:]
    ) {
        textStorage.addAttribute(.sermonParagraphStyle, value: style.rawValue, range: paragraphRange)
        let baseFont = settings.sermonPlatformFont(for: style)
        let baseColor = settings.sermonPlatformFontColor(for: style)
        let previous = previousSnapshot[style]
        let previousColor = previous.flatMap { Color(hex: $0.colorHex) }.map(PlatformColor.init)

        textStorage.enumerateAttribute(.font, in: paragraphRange, options: []) { value, subrange, _ in
            let originalFont = (value as? PlatformFont) ?? baseFont
            let isManualFont: Bool = {
                guard let previous else { return false }
                return originalFont.fontName != previous.fontName
                    || abs(Double(originalFont.pointSize) - previous.fontSize) > 0.01
            }()
            guard !isManualFont else { return }
            var resolvedFont = fontPreservingBoldItalic(from: originalFont, applying: baseFont)
            if style == .citation {
                // [2026-09-29 10번 항목] 사용자 요청 — "[인용] 스타일:
                // 초록색 계열의 이탤릭체..." 굵게/기울임은 원래 사용자가
                // 직접 켠 것만 보존하는 게 이 함수의 원래 취지(파일 상단
                // 주석)지만, 인용 스타일은 "항상 이탤릭"이 스타일 자체의
                // 고정 속성이므로 위에서 보존한 굵게 비트는 그대로 두고
                // 기울임만 추가로 강제한다.
                resolvedFont = italicVariant(of: resolvedFont)
            }
            textStorage.addAttribute(.font, value: resolvedFont, range: subrange)
        }

        textStorage.enumerateAttribute(.foregroundColor, in: paragraphRange, options: []) { value, subrange, _ in
            let originalColor = value as? PlatformColor
            let isManualColor: Bool = {
                guard let previousColor, let originalColor else { return false }
                return !originalColor.isEqual(previousColor)
            }()
            guard !isManualColor else { return }
            textStorage.addAttribute(.foregroundColor, value: baseColor, range: subrange)
        }

        textStorage.enumerateAttribute(.paragraphStyle, in: paragraphRange, options: []) { value, subrange, _ in
            let existingAlignment = (value as? NSParagraphStyle)?.alignment
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = baseFont.typographicLineHeight * max(0, settings.sermonLineHeightMultiple(for: style) - 1)
            if let existingAlignment, existingAlignment != .natural {
                paragraphStyle.alignment = existingAlignment
            }
            if style == .verseQuote {
                // [2026-09-29 6-2번 항목] 목업의 "박스 안 왼쪽 바 + 내용" 중
                // 안쪽 여백만 문단 들여쓰기로 흉내낸다 — 왼쪽 세로 바 자체는
                // `NSAttributedString`/`NSParagraphStyle` 표준 attribute로
                // 표현할 방법이 없고(커스텀 `NSLayoutManager` 서브클래스가
                // 필요한 저수준 작업), 이 세션은 Xcode 빌드/실기기 렌더링
                // 확인이 불가능해 검증 못 할 그림 그리기 코드를 프로덕션에
                // 넣지 않는다는 원칙에 따라 이번엔 배경색 박스(아래
                // `.backgroundColor`)까지만 구현한다 — 왼쪽 바는 Xcode에서
                // 직접 확인하며 추가해야 하는 후속 작업으로 남긴다.
                paragraphStyle.headIndent = 14
                paragraphStyle.firstLineHeadIndent = 14
                paragraphStyle.paragraphSpacingBefore = 6
                paragraphStyle.paragraphSpacing = 6
            }
            if style == .citation {
                // [2026-09-29 10번 항목] 사용자 요청 — "왼쪽여백 10pt +
                // 오른쪽여백 10pt." 왼쪽은 `verseQuote`와 같은 방식
                // (`headIndent`/`firstLineHeadIndent`), 오른쪽은
                // `NSParagraphStyle.tailIndent`를 음수로 주면 "trailing
                // margin(오른쪽 끝)에서부터의 거리"가 된다는 Apple 표준
                // 문서화된 동작(양수면 leading margin 기준 절대 위치,
                // 0 이하면 trailing margin 기준 상대 거리)을 그대로 쓴 것 —
                // 이 프로젝트가 지금까지 우측 여백을 준 적이 없어 새로
                // 도입하지만, 커스텀 그리기가 필요한 `verseQuote` 왼쪽
                // 바와 달리 표준 attribute만으로 완결되는 값이라 별도
                // 검증 없이 적용한다.
                //
                // ⚠️ [보류] "문단 위아래 점선(구분선)"은 `NSAttributedString`/
                // `NSParagraphStyle` 표준 attribute로 표현할 방법이 없다
                // (밑줄/취소선은 텍스트 줄 위치에 그려질 뿐, 문단 블록
                // 전체 폭에 걸친 위아래 테두리와는 다르다) — 위 `verseQuote`
                // 왼쪽 바와 정확히 같은 이유(커스텀 `NSLayoutManager`
                // 서브클래스 필요, 이 세션은 Xcode 렌더링 확인 불가)로
                // 에디터 쪽은 이번에 구현하지 않는다. 대신 읽기 전용
                // 뷰어(`SermonViewerView.paragraphText`)는 순정 SwiftUI라
                // `Path`+`StrokeStyle(dash:)`로 바로 그릴 수 있어 거기엔
                // 넣었다 — verseQuote가 "에디터는 배경색만, 뷰어는 왼쪽
                // 바까지" 였던 것과 같은 구조.
                paragraphStyle.headIndent = 10
                paragraphStyle.firstLineHeadIndent = 10
                paragraphStyle.tailIndent = -10
            }
            textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: subrange)
        }

        if style == .verseQuote {
            textStorage.addAttribute(.backgroundColor, value: settings.sermonVerseQuoteBackgroundPlatformColor, range: paragraphRange)
        } else {
            textStorage.removeAttribute(.backgroundColor, range: paragraphRange)
        }
    }

    /// [2026-09-29 10번 항목] `style == .citation`에 강제로 이탤릭 비트만
    /// 추가한다 — `fontPreservingBoldItalic`과 같은 계열(굵게/기울임 비트만
    /// 옮기고 패밀리 분류 비트는 옮기지 않아 `withSymbolicTraits` 실패
    /// 가능성을 줄임)이나, 원본 폰트의 기존 비트가 아니라 항상 이탤릭을
    /// "추가"한다는 점만 다르다.
    ///
    /// ⚠️ [Xcode 확인 필요] `withSymbolicTraits`는 그 폰트 패밀리가 이탤릭
    /// 변형을 지원하지 않으면(커스텀 한글 폰트 다수가 별도 이탤릭 글리프를
    /// 만들지 않음) 실패할 수 있다 — 실패 시 `?? font`로 원래(직립) 폰트를
    /// 그대로 반환하는 기존 방어적 관례를 따랐다. 지금 인용 스타일에 쓰는
    /// 폰트(`UserSettingsStore.sermonFontName(for: .citation)`)가 실제
    /// 이탤릭을 지원하는지는 빌드 후 화면으로 확인해야 한다 — 지원하지
    /// 않으면 시스템이 자동으로 "가짜 기울임(synthetic oblique)"을 그릴 수도,
    /// 아무 변화가 없을 수도 있다(플랫폼/폰트에 따라 다름).
    static func italicVariant(of font: PlatformFont) -> PlatformFont {
        #if os(iOS)
        var traits = font.fontDescriptor.symbolicTraits
        traits.insert(.traitItalic)
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
        #elseif os(macOS)
        // [2026-09-29 수정] `fontPreservingBoldItalic` 바로 위와 동일한 플랫폼
        // 차이 -- `NSFontDescriptor.withSymbolicTraits`는 iOS의
        // `UIFontDescriptor` 판(옵셔널)과 달리 macOS에서는 옵셔널이 아니다
        // (non-optional 반환). 처음 `guard let`으로 썼던 건 iOS 쪽 시그니처를
        // 그대로 옮긴 실수였고, 그대로 두면 "조건부 바인딩 초기화 값이
        // Optional 타입이 아니다" 컴파일 에러가 난다 -- 바로 위 함수가 이미
        // 쓰는 형태로 바로잡는다.
        var traits = font.fontDescriptor.symbolicTraits
        traits.insert(.italic)
        let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
        #endif
    }

    /// [2026-09-28 4단계(뷰어) 신설] 뷰어(`SermonViewerView`)는 `NSTextStorage`를
    /// 만들지 않고 저장된 `contentText`(순수 문자열) + `paragraphStyles`만으로
    /// 읽기 전용 렌더링을 한다 — `export(from:)`가 텍스트 스토리지의 `.string`을
    /// 같은 `.byParagraphs` 옵션으로 순회해 만든 배열이 바로 이 `storedStyles`이므로
    /// (`RichTextCodec.encode`가 `contentText`로 넘기는 값도 `attributed.string`,
    /// 즉 텍스트 스토리지의 문자열 그대로 — `SermonParagraphEditor.swift` 상단
    /// 주석 참고), 저장된 `text`를 여기서도 똑같이 `.byParagraphs`로 순회하면
    /// 인덱스가 어긋나지 않는다. 문단 수와 저장된 스타일 개수가 어긋나면(과거
    /// 데이터 등) `apply(_:to:settings:)`와 동일하게 `.body`로 안전하게 채운다.
    static func parseParagraphs(text: String, styles storedStyles: String) -> [(text: String, style: SermonParagraphStyle)] {
        let fullText = text as NSString
        guard fullText.length > 0 else { return [] }
        let raw = storedStyles.isEmpty ? [] : storedStyles.components(separatedBy: delimiter)
        var result: [(text: String, style: SermonParagraphStyle)] = []
        var index = 0
        fullText.enumerateSubstrings(
            in: NSRange(location: 0, length: fullText.length), options: .byParagraphs
        ) { substring, _, _, _ in
            defer { index += 1 }
            let style = (index < raw.count ? SermonParagraphStyle(rawValue: raw[index]) : nil) ?? .body
            result.append((text: substring ?? "", style: style))
        }
        return result
    }

    /// [2026-09-29 7번 항목 신설] 사용자 요청 — "성경구절 선택시(단일, 다중)
    /// 하단 기능에 '설교작성' 메뉴 추가" — 사용자 확정: 누르면 항상 새 설교
    /// 작성 화면을 연다(구절을 각각 `.verseQuote` 문단으로 자동 삽입). 이
    /// 함수는 그 "삽입된 상태"를 살아있는 `UITextView`/`NSTextView` 없이
    /// 미리 만든다 — `BibleReadingView`는 아직 에디터 화면 자체를 열기 전이라
    /// (에디터가 열려야만 `SermonParagraphEditingProxy.textView`가 생긴다)
    /// `insertVerseQuoteParagraph`(살아있는 텍스트뷰 전용)를 재사용할 수 없다.
    /// 대신 임시 `NSTextStorage`에 문단별로 `applyStyle(.verseQuote, ...)`를
    /// 직접 적용해 완전히 같은 서식(굵게/기울임 없음, 프리셋 폰트/색/박스)을
    /// 만든 뒤 `RichTextCodec.encode`/`export(from:)`로 저장 가능한 형태(RTF+
    /// 순수텍스트+문단스타일 문자열)까지 만들어 돌려준다 — `Sermon(contentHtml:
    /// contentText:paragraphStyles:)`에 그대로 넣을 수 있다.
    static func buildVerseQuoteDocument(verseTexts: [String], settings: UserSettingsStore) -> (rtf: String, plainText: String, paragraphStyles: String) {
        guard !verseTexts.isEmpty else { return ("", "", "") }
        let storage = NSTextStorage()
        storage.beginEditing()
        var location = 0
        for text in verseTexts {
            let paragraphText = text + "\n"
            let length = (paragraphText as NSString).length
            storage.replaceCharacters(in: NSRange(location: location, length: 0), with: NSAttributedString(string: paragraphText))
            applyStyle(.verseQuote, to: NSRange(location: location, length: length), in: storage, settings: settings)
            location += length
        }
        storage.endEditing()
        let (rtf, plain) = RichTextCodec.encode(storage)
        let styles = export(from: storage)
        return (rtf, plain, styles)
    }

    /// ⚠️ [Xcode 확인 필요, 파일 상단 주석 참고] `originalFont`의 굵게/기울임
    /// 비트만 골라 `applying`(현재 설정의 패밀리+크기)에 다시 입힌다.
    /// `applying.fontDescriptor.symbolicTraits` 전체를 그대로 복사하지 않는
    /// 이유 — 원래 폰트 계열의 분류 비트(예: 세리프)까지 함께 옮기면, 새
    /// 계열(예: 산세리프)의 디스크립터가 그 조합을 지원하지 않아
    /// `withSymbolicTraits`가 실패할 수 있다. 그래서 굵게/기울임 두 비트만
    /// 골라 옮긴다 — `RichTextEditor.swift`의 `togglingTrait`와 같은 계열의
    /// 방어적 처리(실패하면 원래 폰트를 그대로 반환).
    static func fontPreservingBoldItalic(from originalFont: PlatformFont, applying baseFont: PlatformFont) -> PlatformFont {
        #if os(iOS)
        let mask: UIFontDescriptor.SymbolicTraits = [.traitBold, .traitItalic]
        let originalBoldItalic = originalFont.fontDescriptor.symbolicTraits.intersection(mask)
        guard !originalBoldItalic.isEmpty else { return baseFont }
        var newTraits = baseFont.fontDescriptor.symbolicTraits
        newTraits.formUnion(originalBoldItalic)
        guard let descriptor = baseFont.fontDescriptor.withSymbolicTraits(newTraits) else { return baseFont }
        return UIFont(descriptor: descriptor, size: baseFont.pointSize)
        #elseif os(macOS)
        let mask: NSFontDescriptor.SymbolicTraits = [.bold, .italic]
        let originalBoldItalic = originalFont.fontDescriptor.symbolicTraits.intersection(mask)
        guard !originalBoldItalic.isEmpty else { return baseFont }
        var newTraits = baseFont.fontDescriptor.symbolicTraits
        newTraits.formUnion(originalBoldItalic)
        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(newTraits)
        return NSFont(descriptor: descriptor, size: baseFont.pointSize) ?? baseFont
        #endif
    }
}

#if os(iOS)

// MARK: - iOS

/// 툴바(`SermonEditorView`가 소유)가 "지금 포커스된 `UITextView`"에 문단
/// 스타일/인라인 서식을 적용하기 위한 다리 — `RichTextEditingProxy`와 같은
/// 역할·같은 이유(파일 상단 주석 참고, 코드는 공유하지 않고 새로 둔다).
@MainActor
final class SermonParagraphEditingProxy {
    weak var textView: UITextView?

    func toggleBold() { toggleTrait(.traitBold) }
    func toggleItalic() { toggleTrait(.traitItalic) }

    /// 커서가 있는 문단의 현재 스타일 — 툴바의 드롭다운이 지금 어느 스타일이
    /// 선택돼 있는지 보여줄 때 쓴다.
    func currentParagraphStyle() -> SermonParagraphStyle {
        guard let textView, let storage = textView.textStorage as NSTextStorage?, storage.length > 0 else { return .body }
        let location = min(textView.selectedRange.location, storage.length - 1)
        guard location >= 0 else { return .body }
        let raw = storage.attribute(.sermonParagraphStyle, at: location, effectiveRange: nil) as? String
        return raw.flatMap(SermonParagraphStyle.init(rawValue:)) ?? .body
    }

    /// 커서가 있는 문단 전체에 스타일을 적용한다 — 정렬(`applyAlignment`)과
    /// 같은 이유로 `NSString.paragraphRange(for:)`로 문단 전체 범위를 구한다
    /// (선택 범위가 짧아도/캐럿만 있어도 그 문단 전체에 적용돼야 자연스럽다).
    func applyParagraphStyle(_ style: SermonParagraphStyle, settings: UserSettingsStore) {
        guard let textView, let storage = textView.textStorage as NSTextStorage? else { return }
        let fullText = storage.string as NSString
        guard fullText.length > 0 else {
            // 빈 문서 — 다음에 입력할 글자부터 이 스타일이 적용되도록 타이핑
            // 속성만 맞춰 둔다.
            applyTypingAttributes(for: style, settings: settings, to: textView)
            return
        }
        let paragraphRange = fullText.paragraphRange(for: textView.selectedRange)
        storage.beginEditing()
        SermonParagraphStyleCodec.applyStyle(style, to: paragraphRange, in: storage, settings: settings)
        storage.endEditing()
        applyTypingAttributes(for: style, settings: settings, to: textView)
    }

    /// "말씀구절 + 추가" — 커서가 있는 문단 "다음"에 새 문단을 만들어 구절
    /// 텍스트를 넣고 `.verseQuote` 스타일을 지정한다. 반환값은 그 새 문단의
    /// 0부터 시작하는 순번(`SermonVerseReference.paragraphIndex`용).
    ///
    /// ⚠️ [Xcode 확인 필요, 파일 상단 주석 참고] 문단 인덱스 계산의 경계
    /// 케이스(빈 문서/문서 맨 끝 등)는 실기기에서 재확인이 필요하다.
    @discardableResult
    func insertVerseQuoteParagraph(text: String, settings: UserSettingsStore) -> Int {
        guard let textView, let storage = textView.textStorage as NSTextStorage? else { return 0 }
        let fullText = storage.string as NSString

        var currentParagraphIndex = -1
        var currentParagraphRange = NSRange(location: 0, length: 0)
        if fullText.length > 0 {
            let selectionLocation = min(textView.selectedRange.location, fullText.length)
            var idx = 0
            fullText.enumerateSubstrings(in: NSRange(location: 0, length: fullText.length), options: .byParagraphs) { _, paragraphRange, _, _ in
                if paragraphRange.location <= selectionLocation {
                    currentParagraphIndex = idx
                    currentParagraphRange = paragraphRange
                }
                idx += 1
            }
        }

        let insertionPoint = currentParagraphRange.location + currentParagraphRange.length
        let needsLeadingNewline = insertionPoint > 0
        let insertedText = (needsLeadingNewline ? "\n" : "") + text + "\n"

        // [2026-09-29 6-2/7번 항목 수정] 예전엔 여기서 폰트/줄간격만 직접
        // 설정해 `SermonParagraphStyleCodec.applyStyle`이 매기는 박스 배경/
        // 글자색/여백(6-2번 항목)을 못 받았다 — 새로 삽입한 문단도 다시 열었을
        // 때와 똑같은 모양이어야 하므로, 직접 서식을 짜 넣는 대신 `applyStyle`을
        // 그대로 재사용한다(중복 로직 제거 겸 일관성 확보).
        let leadingOffset = needsLeadingNewline ? 1 : 0
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: insertionPoint, length: 0), with: NSAttributedString(string: insertedText))
        let newParagraphRange = NSRange(location: insertionPoint + leadingOffset, length: (insertedText as NSString).length - leadingOffset)
        SermonParagraphStyleCodec.applyStyle(.verseQuote, to: newParagraphRange, in: storage, settings: settings)
        storage.endEditing()

        let newCursorLocation = insertionPoint + (insertedText as NSString).length
        textView.selectedRange = NSRange(location: newCursorLocation, length: 0)

        return currentParagraphIndex + 1
    }

    /// [2026-09-29 5번 항목 신설] 사용자 요청 — "에디터 기능에서 문단 정렬,
    /// 글자 색상, 글자크기, 글꼴 선택을 지정할 수 있도록 기능을 추가할 것."
    /// `RichTextEditor.RichTextEditingProxy`의 같은 이름 메서드들(Views/Memo/
    /// RichTextEditor.swift)과 완전히 같은 구조를 그대로 옮겨왔다 — 다른 점은
    /// `hex`/`family`/`size`가 `nil`이면 "이 문단 스타일의 프리셋 값으로
    /// 되돌리기"라는 뜻이라는 것뿐(그 값들을 읽으려면 `currentParagraphStyle()`
    /// + `settings`가 필요해 파라미터로 받는다). 이렇게 적용한 값이 "수동
    /// 지정"으로 다음에 열 때도 유지되는 이유는 별도 마커가 아니라
    /// `SermonParagraphStyleCodec.applyStyle`이 저장된 스냅샷과 "지금 값이
    /// 다른지"만 비교하기 때문(그 함수 상단 주석 참고) — 여기는 그냥 값만
    /// 바꾸면 된다.
    func applyColor(_ hex: String?, settings: UserSettingsStore) {
        guard let textView else { return }
        let resolvedColor: UIColor
        if let hex, let color = Color(hex: hex) {
            resolvedColor = UIColor(color)
        } else {
            resolvedColor = settings.sermonPlatformFontColor(for: currentParagraphStyle())
        }
        apply(.foregroundColor, value: resolvedColor, on: textView)
    }

    /// `family`가 `nil`이면 지금 문단 스타일의 프리셋 글꼴로 되돌린다(크기는
    /// 그대로 유지) — `applyFontSize(_:settings:)`와 대칭.
    func applyFontFamily(_ family: String?, settings: UserSettingsStore) {
        guard let textView else { return }
        let range = textView.selectedRange
        func makeFont(basedOn font: UIFont) -> UIFont {
            let resolvedFamily = family ?? settings.sermonFontName(for: currentParagraphStyle())
            guard resolvedFamily != "System" else { return UIFont.systemFont(ofSize: font.pointSize) }
            BundledFontRegistrar.ensureAvailable(resolvedFamily)
            return UIFont(name: resolvedFamily, size: font.pointSize) ?? font
        }
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let font = (attrs[.font] as? UIFont) ?? UIFont.systemFont(ofSize: 15)
            attrs[.font] = makeFont(basedOn: font)
            textView.typingAttributes = attrs
            return
        }
        let storage = textView.textStorage
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? UIFont) ?? UIFont.systemFont(ofSize: 15)
            storage.addAttribute(.font, value: makeFont(basedOn: font), range: subrange)
        }
        storage.endEditing()
    }

    /// `size`가 `nil`이면 지금 문단 스타일의 프리셋 크기로 되돌린다(글꼴은
    /// 그대로 유지) — `UIFont.withSize(_:)`가 트레이트(굵게/기울임)를 그대로
    /// 유지해 준다(`RichTextEditor`의 같은 메서드와 같은 이유).
    func applyFontSize(_ size: CGFloat?, settings: UserSettingsStore) {
        guard let textView else { return }
        let range = textView.selectedRange
        func makeFont(basedOn font: UIFont) -> UIFont {
            let resolvedSize = size ?? CGFloat(settings.sermonFontSize(for: currentParagraphStyle()))
            return font.withSize(resolvedSize)
        }
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let font = (attrs[.font] as? UIFont) ?? UIFont.systemFont(ofSize: 15)
            attrs[.font] = makeFont(basedOn: font)
            textView.typingAttributes = attrs
            return
        }
        let storage = textView.textStorage
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? UIFont) ?? UIFont.systemFont(ofSize: 15)
            storage.addAttribute(.font, value: makeFont(basedOn: font), range: subrange)
        }
        storage.endEditing()
    }

    /// 정렬은 프리셋이 애초에 값을 지정하지 않아(항상 `.natural`) 되돌리기
    /// 항목도 그냥 `applyAlignment(.natural)`을 호출하면 된다 — 별도 분기 불필요.
    /// `RichTextEditor.RichTextEditingProxy.applyAlignment(_:)`와 완전히 같은
    /// 구조(그 파일 참고) — 정렬은 글자가 아니라 문단 단위 속성이라 캐럿만
    /// 있어도 그 문단 전체에 적용한다.
    func applyAlignment(_ alignment: PlatformTextAlignment) {
        guard let textView else { return }
        func makeParagraphStyle(basedOn existing: NSParagraphStyle?) -> NSMutableParagraphStyle {
            let style = (existing?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            style.alignment = alignment
            return style
        }
        let range = textView.selectedRange
        if range.length == 0 && (textView.text as NSString).length == 0 {
            var attrs = textView.typingAttributes
            attrs[.paragraphStyle] = makeParagraphStyle(basedOn: attrs[.paragraphStyle] as? NSParagraphStyle)
            textView.typingAttributes = attrs
            return
        }
        let storage = textView.textStorage
        let fullText = storage.string as NSString
        let paragraphRange = fullText.paragraphRange(for: range)
        storage.beginEditing()
        storage.enumerateAttribute(.paragraphStyle, in: paragraphRange, options: []) { value, subrange, _ in
            storage.addAttribute(.paragraphStyle, value: makeParagraphStyle(basedOn: value as? NSParagraphStyle), range: subrange)
        }
        storage.endEditing()
        var attrs = textView.typingAttributes
        attrs[.paragraphStyle] = makeParagraphStyle(basedOn: attrs[.paragraphStyle] as? NSParagraphStyle)
        textView.typingAttributes = attrs
    }

    private func applyTypingAttributes(for style: SermonParagraphStyle, settings: UserSettingsStore, to textView: UITextView) {
        let baseFont = settings.sermonPlatformFont(for: style)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = baseFont.typographicLineHeight * max(0, settings.sermonLineHeightMultiple(for: style) - 1)
        var attrs = textView.typingAttributes
        attrs[.font] = baseFont
        attrs[.paragraphStyle] = paragraphStyle
        attrs[.sermonParagraphStyle] = style.rawValue
        textView.typingAttributes = attrs
    }

    private func toggleTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
        guard let textView else { return }
        let range = textView.selectedRange
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let font = (attrs[.font] as? UIFont) ?? UIFont.systemFont(ofSize: 15)
            attrs[.font] = font.togglingSermonTrait(trait)
            textView.typingAttributes = attrs
            return
        }
        let storage = textView.textStorage
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? UIFont) ?? UIFont.systemFont(ofSize: 15)
            storage.addAttribute(.font, value: font.togglingSermonTrait(trait), range: subrange)
        }
        storage.endEditing()
    }

    /// `applyColor(_:settings:)`가 쓰는 작은 공통 헬퍼 — `RichTextEditor.
    /// RichTextEditingProxy.apply(_:value:on:)`와 완전히 같은 구조(캐럿만
    /// 있으면 타이핑 속성, 선택 범위가 있으면 그 범위에 바로 적용).
    private func apply(_ key: NSAttributedString.Key, value: Any, on textView: UITextView) {
        let range = textView.selectedRange
        if range.length == 0 {
            var attrs = textView.typingAttributes
            attrs[key] = value
            textView.typingAttributes = attrs
            return
        }
        let storage = textView.textStorage
        storage.beginEditing()
        storage.addAttribute(key, value: value, range: range)
        storage.endEditing()
    }
}

private extension UIFont {
    /// `RichTextEditor.swift`의 `UIFont.togglingTrait(_:)`와 완전히 같은 로직
    /// (이름만 충돌 방지를 위해 다르게 뒀다 — 같은 모듈 안에 두 `private
    /// extension UIFont`가 각자 다른 메서드 이름으로 공존한다).
    func togglingSermonTrait(_ trait: UIFontDescriptor.SymbolicTraits) -> UIFont {
        var traits = fontDescriptor.symbolicTraits
        if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

struct SermonParagraphEditorRepresentable: UIViewRepresentable {
    @Binding var rtfText: String
    @Binding var plainText: String
    @Binding var paragraphStyles: String
    /// [2026-09-29 5번 항목 신설] 마지막 저장 시점의 프리셋 스냅샷(읽기 전용,
    /// `SermonParagraphStyleCodec.StyleSnapshot` 상단 주석 참고) — `@Binding`이
    /// 아니라 일반 값이다. 이 에디터가 직접 갱신하지 않고(수동 서식 감지의
    /// "기준선"일 뿐, 쓰기는 `SermonEditorView.save()`의 몫), 매 렌더마다
    /// 호출부가 최신 `subject.styleFontSnapshot`을 그대로 넘겨준다.
    var styleFontSnapshot: String
    var isEditable: Bool
    var proxy: SermonParagraphEditingProxy
    var settings: UserSettingsStore
    var editingBackgroundColor: UIColor? = nil
    var readOnlyBackgroundColor: UIColor? = nil

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.textStorage.delegate = context.coordinator
        textView.allowsEditingTextAttributes = isEditable
        context.coordinator.textView = textView
        proxy.textView = textView
        loadContent(into: textView, coordinator: context.coordinator)
        applyBackground(to: textView)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        uiView.isEditable = isEditable
        uiView.allowsEditingTextAttributes = isEditable
        proxy.textView = uiView
        applyBackground(to: uiView)
        guard rtfText != context.coordinator.lastExportedRTF else { return }
        loadContent(into: uiView, coordinator: context.coordinator)
    }

    /// `RichTextEditor.dismantleUIView`와 같은 이유 — 이 텍스트뷰가 화면
    /// 전환(`.id(selection)` 등)으로 통째로 버려질 때, 응답자 체인을 타고
    /// 올라가 윈도우가 공유하는 undo 관리자에 이 텍스트뷰를 대상으로 하는
    /// 액션이 남아 있으면 이후 Cmd+Z가 이미 사라진 텍스트뷰를 참조해 크래시할
    /// 수 있다(실제 보고된 macOS 크래시와 같은 구조적 위험, RichTextEditor.swift
    /// 상단 주석 참고) — 대칭으로 미리 막는다.
    static func dismantleUIView(_ uiView: UITextView, coordinator: Coordinator) {
        uiView.undoManager?.removeAllActions(withTarget: uiView)
    }

    private func loadContent(into textView: UITextView, coordinator: Coordinator) {
        coordinator.isLoadingExternally = true
        let defaultAttributes: [NSAttributedString.Key: Any] = [.font: settings.sermonPlatformFont(for: .body)]
        let attributed = RichTextCodec.decode(rtfText, defaultAttributes: defaultAttributes)
        // [빌드 에러 수정] `SermonParagraphStyleCodec.apply`는 `NSTextStorage`를
        // 요구한다(내부에서 `beginEditing()/endEditing()`을 쓰기 때문 —
        // `NSMutableAttributedString`엔 그 메서드가 없다). 그래서 별도의
        // `NSMutableAttributedString`을 만들어 스타일을 입힌 뒤 텍스트뷰에
        // 옮기는 대신, 디코딩한 내용을 먼저 실제 텍스트뷰의 `textStorage`
        // (이미 `NSTextStorage`)에 넣고 그 위에 바로 스타일을 적용한다.
        textView.textStorage.setAttributedString(attributed)
        SermonParagraphStyleCodec.apply(paragraphStyles, to: textView.textStorage, settings: settings, previousSnapshot: styleFontSnapshot)
        applyBodyTypingAttributesIfEmpty(to: textView)
        coordinator.isLoadingExternally = false
        coordinator.lastExportedRTF = rtfText
    }

    /// [2026-09-29 버그 수정] 사용자 보고 — "새 설교 작성, 설교 편집에서
    /// 기본스타일이 본문으로 선택되어있지만, 실제 본문 스타일이 적용되어있지
    /// 않음." 원인: `SermonParagraphStyleCodec.apply`는 `.byParagraphs`로 실제
    /// 문단을 순회하며 스타일을 입히는데, 완전히 빈 문서는 순회할 문단 자체가
    /// 없어(`guard fullText.length > 0 else { return }`) 아무 일도 하지
    /// 않는다 — 그래서 새로 만든 빈 설교를 열면 툴바의 스타일 필은 "본문"이
    /// 선택돼 보이지만(`SermonEditorView.currentStyle` 초기값), 실제
    /// `UITextView.typingAttributes`(다음에 입력할 글자가 받을 서식)는 UIKit
    /// 기본값(시스템 폰트)에 머물러 있었다. 빈 문서일 때만 "본문" 스타일 하나를
    /// 타이핑 속성에 직접 심어 이 간극을 메운다 — `SermonParagraphEditingProxy.
    /// applyTypingAttributes`(private)와 완전히 같은 계산이지만, 그 함수는
    /// "사용자가 지금 스타일을 고름" 경로 전용이라 여기서 재사용하지 않고
    /// (private 스코프이기도 함) 같은 세 줄만 그대로 옮겨 왔다 — 새 함수를
    /// 만들 만큼 복잡하지 않은 로직이라 중복을 감수했다.
    private func applyBodyTypingAttributesIfEmpty(to textView: UITextView) {
        guard textView.textStorage.length == 0 else { return }
        let baseFont = settings.sermonPlatformFont(for: .body)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = baseFont.typographicLineHeight * max(0, settings.sermonLineHeightMultiple(for: .body) - 1)
        textView.typingAttributes = [
            .font: baseFont,
            .paragraphStyle: paragraphStyle,
            .sermonParagraphStyle: SermonParagraphStyle.body.rawValue
        ]
    }

    private func applyBackground(to textView: UITextView) {
        let color = isEditable ? editingBackgroundColor : readOnlyBackgroundColor
        textView.backgroundColor = color ?? .clear
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextStorageDelegate {
        var parent: SermonParagraphEditorRepresentable
        var lastExportedRTF: String = ""
        var isProcessing = false
        var isLoadingExternally = false
        weak var textView: UITextView?

        init(_ parent: SermonParagraphEditorRepresentable) { self.parent = parent }

        func textStorage(
            _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorage.EditActions,
            range editedRange: NSRange, changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters) || editedMask.contains(.editedAttributes) else { return }
            guard !isProcessing, !isLoadingExternally else { return }
            isProcessing = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let (rtf, plain) = RichTextCodec.encode(textStorage)
                let styles = SermonParagraphStyleCodec.export(from: textStorage)
                self.lastExportedRTF = rtf
                self.parent.rtfText = rtf
                self.parent.plainText = plain
                self.parent.paragraphStyles = styles
                self.isProcessing = false
            }
        }
    }
}

#elseif os(macOS)

// MARK: - macOS

@MainActor
final class SermonParagraphEditingProxy {
    weak var textView: NSTextView?

    func toggleBold() { toggleTrait(.bold) }
    func toggleItalic() { toggleTrait(.italic) }

    func currentParagraphStyle() -> SermonParagraphStyle {
        guard let textView, let storage = textView.textStorage, storage.length > 0 else { return .body }
        let location = min(textView.selectedRange().location, storage.length - 1)
        guard location >= 0 else { return .body }
        let raw = storage.attribute(.sermonParagraphStyle, at: location, effectiveRange: nil) as? String
        return raw.flatMap(SermonParagraphStyle.init(rawValue:)) ?? .body
    }

    func applyParagraphStyle(_ style: SermonParagraphStyle, settings: UserSettingsStore) {
        guard let textView, let storage = textView.textStorage else { return }
        let fullText = storage.string as NSString
        guard fullText.length > 0 else {
            applyTypingAttributes(for: style, settings: settings, to: textView)
            return
        }
        let paragraphRange = fullText.paragraphRange(for: textView.selectedRange())
        storage.beginEditing()
        SermonParagraphStyleCodec.applyStyle(style, to: paragraphRange, in: storage, settings: settings)
        storage.endEditing()
        applyTypingAttributes(for: style, settings: settings, to: textView)
    }

    @discardableResult
    func insertVerseQuoteParagraph(text: String, settings: UserSettingsStore) -> Int {
        guard let textView, let storage = textView.textStorage else { return 0 }
        let fullText = storage.string as NSString

        var currentParagraphIndex = -1
        var currentParagraphRange = NSRange(location: 0, length: 0)
        if fullText.length > 0 {
            let selectionLocation = min(textView.selectedRange().location, fullText.length)
            var idx = 0
            fullText.enumerateSubstrings(in: NSRange(location: 0, length: fullText.length), options: .byParagraphs) { _, paragraphRange, _, _ in
                if paragraphRange.location <= selectionLocation {
                    currentParagraphIndex = idx
                    currentParagraphRange = paragraphRange
                }
                idx += 1
            }
        }

        let insertionPoint = currentParagraphRange.location + currentParagraphRange.length
        let needsLeadingNewline = insertionPoint > 0
        let insertedText = (needsLeadingNewline ? "\n" : "") + text + "\n"

        // iOS `insertVerseQuoteParagraph`와 같은 이유(그 파일 위쪽 주석 참고).
        let leadingOffset = needsLeadingNewline ? 1 : 0
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: insertionPoint, length: 0), with: NSAttributedString(string: insertedText))
        let newParagraphRange = NSRange(location: insertionPoint + leadingOffset, length: (insertedText as NSString).length - leadingOffset)
        SermonParagraphStyleCodec.applyStyle(.verseQuote, to: newParagraphRange, in: storage, settings: settings)
        storage.endEditing()

        let newCursorLocation = insertionPoint + (insertedText as NSString).length
        textView.setSelectedRange(NSRange(location: newCursorLocation, length: 0))

        return currentParagraphIndex + 1
    }

    private func applyTypingAttributes(for style: SermonParagraphStyle, settings: UserSettingsStore, to textView: NSTextView) {
        let baseFont = settings.sermonPlatformFont(for: style)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = baseFont.typographicLineHeight * max(0, settings.sermonLineHeightMultiple(for: style) - 1)
        var attrs = textView.typingAttributes
        attrs[.font] = baseFont
        attrs[.paragraphStyle] = paragraphStyle
        attrs[.sermonParagraphStyle] = style.rawValue
        textView.typingAttributes = attrs
    }

    /// iOS `SermonParagraphEditingProxy.applyColor(_:settings:)`와 같은
    /// 이유·같은 구조(그 파일 참고).
    func applyColor(_ hex: String?, settings: UserSettingsStore) {
        guard let textView else { return }
        let resolvedColor: NSColor
        if let hex, let color = Color(hex: hex) {
            resolvedColor = NSColor(color)
        } else {
            resolvedColor = settings.sermonPlatformFontColor(for: currentParagraphStyle())
        }
        apply(.foregroundColor, value: resolvedColor, on: textView)
    }

    func applyFontFamily(_ family: String?, settings: UserSettingsStore) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        func makeFont(basedOn font: NSFont) -> NSFont {
            let resolvedFamily = family ?? settings.sermonFontName(for: currentParagraphStyle())
            guard resolvedFamily != "System" else { return NSFont.systemFont(ofSize: font.pointSize) }
            BundledFontRegistrar.ensureAvailable(resolvedFamily)
            return NSFont(name: resolvedFamily, size: font.pointSize) ?? font
        }
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let font = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 15)
            attrs[.font] = makeFont(basedOn: font)
            textView.typingAttributes = attrs
            return
        }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: 15)
            storage.addAttribute(.font, value: makeFont(basedOn: font), range: subrange)
        }
        storage.endEditing()
    }

    /// `NSFont`엔 `withSize(_:)`가 없어(AppKit) `NSFont(descriptor:size:)`로
    /// 새 인스턴스를 만든다 — `RichTextEditor.RichTextEditingProxy.
    /// applyFontSize(_:)`(macOS 쪽)와 완전히 같은 관례.
    func applyFontSize(_ size: CGFloat?, settings: UserSettingsStore) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        func makeFont(basedOn font: NSFont) -> NSFont {
            let resolvedSize = size ?? CGFloat(settings.sermonFontSize(for: currentParagraphStyle()))
            return NSFont(descriptor: font.fontDescriptor, size: resolvedSize) ?? font
        }
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let font = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 15)
            attrs[.font] = makeFont(basedOn: font)
            textView.typingAttributes = attrs
            return
        }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: 15)
            storage.addAttribute(.font, value: makeFont(basedOn: font), range: subrange)
        }
        storage.endEditing()
    }

    /// `RichTextEditor.RichTextEditingProxy.applyAlignment(_:)`(macOS 쪽)와
    /// 완전히 같은 구조 — `NSTextView`는 `.text`가 아니라 `.string`이 없고
    /// `textStorage.length`로 빈 문서를 판정한다(그 파일 참고).
    func applyAlignment(_ alignment: PlatformTextAlignment) {
        guard let textView, let storage = textView.textStorage else { return }
        func makeParagraphStyle(basedOn existing: NSParagraphStyle?) -> NSMutableParagraphStyle {
            let style = (existing?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            style.alignment = alignment
            return style
        }
        let range = textView.selectedRange()
        if storage.length == 0 {
            var attrs = textView.typingAttributes
            attrs[.paragraphStyle] = makeParagraphStyle(basedOn: attrs[.paragraphStyle] as? NSParagraphStyle)
            textView.typingAttributes = attrs
            return
        }
        let fullText = storage.string as NSString
        let paragraphRange = fullText.paragraphRange(for: range)
        storage.beginEditing()
        storage.enumerateAttribute(.paragraphStyle, in: paragraphRange, options: []) { value, subrange, _ in
            storage.addAttribute(.paragraphStyle, value: makeParagraphStyle(basedOn: value as? NSParagraphStyle), range: subrange)
        }
        storage.endEditing()
        var attrs = textView.typingAttributes
        attrs[.paragraphStyle] = makeParagraphStyle(basedOn: attrs[.paragraphStyle] as? NSParagraphStyle)
        textView.typingAttributes = attrs
    }

    private func toggleTrait(_ trait: NSFontDescriptor.SymbolicTraits) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let font = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 15)
            attrs[.font] = font.togglingSermonTrait(trait)
            textView.typingAttributes = attrs
            return
        }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: 15)
            storage.addAttribute(.font, value: font.togglingSermonTrait(trait), range: subrange)
        }
        storage.endEditing()
    }

    /// `apply(_:value:on:)`(iOS 쪽)와 같은 이유·같은 구조.
    private func apply(_ key: NSAttributedString.Key, value: Any, on textView: NSTextView) {
        let range = textView.selectedRange()
        if range.length == 0 {
            var attrs = textView.typingAttributes
            attrs[key] = value
            textView.typingAttributes = attrs
            return
        }
        guard let storage = textView.textStorage else { return }
        storage.beginEditing()
        storage.addAttribute(key, value: value, range: range)
        storage.endEditing()
    }
}

private extension NSFont {
    /// `RichTextEditor.swift`의 `NSFont.togglingTrait(_:)`와 완전히 같은 로직
    /// (이름만 충돌 방지를 위해 다르게 뒀다).
    func togglingSermonTrait(_ trait: NSFontDescriptor.SymbolicTraits) -> NSFont {
        var traits = fontDescriptor.symbolicTraits
        if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
        let descriptor = fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}

struct SermonParagraphEditorRepresentable: NSViewRepresentable {
    @Binding var rtfText: String
    @Binding var plainText: String
    @Binding var paragraphStyles: String
    /// iOS `SermonParagraphEditorRepresentable.styleFontSnapshot`와 같은
    /// 이유·같은 구조(그 프로퍼티 상단 주석 참고).
    var styleFontSnapshot: String
    var isEditable: Bool
    var proxy: SermonParagraphEditingProxy
    var settings: UserSettingsStore
    var editingBackgroundColor: NSColor? = nil
    var readOnlyBackgroundColor: NSColor? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textStorage?.delegate = context.coordinator
        textView.allowsUndo = true

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        context.coordinator.textView = textView
        proxy.textView = textView
        loadContent(into: textView, coordinator: context.coordinator)
        applyBackground(to: textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        textView.isEditable = isEditable
        proxy.textView = textView
        applyBackground(to: textView)
        guard rtfText != context.coordinator.lastExportedRTF else { return }
        loadContent(into: textView, coordinator: context.coordinator)
    }

    /// `RichTextEditor.swift`가 macOS에서 실제로 신고받은 크래시(문서 전환 시
    /// 공유 undo 관리자에 죽은 텍스트뷰 참조가 남는 문제)와 같은 방어 — 상단
    /// 주석 참고.
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        (nsView.documentView as? NSTextView)?.undoManager?.removeAllActions(withTarget: nsView.documentView as Any)
    }

    private func loadContent(into textView: NSTextView, coordinator: Coordinator) {
        coordinator.isLoadingExternally = true
        // [빌드 에러 수정, iOS 쪽과 같은 이유] macOS의 `NSTextView.textStorage`는
        // Optional이라 guard로 먼저 꺼내 둔다.
        guard let textStorage = textView.textStorage else {
            coordinator.isLoadingExternally = false
            return
        }
        let defaultAttributes: [NSAttributedString.Key: Any] = [.font: settings.sermonPlatformFont(for: .body)]
        let attributed = RichTextCodec.decode(rtfText, defaultAttributes: defaultAttributes)
        textStorage.setAttributedString(attributed)
        SermonParagraphStyleCodec.apply(paragraphStyles, to: textStorage, settings: settings, previousSnapshot: styleFontSnapshot)
        applyBodyTypingAttributesIfEmpty(to: textView, textStorage: textStorage)
        coordinator.isLoadingExternally = false
        coordinator.lastExportedRTF = rtfText
    }

    /// iOS `loadContent`의 `applyBodyTypingAttributesIfEmpty`와 같은 이유·같은
    /// 계산(파일 상단 iOS 쪽 주석 참고) — macOS `NSTextView.textStorage`가
    /// Optional이라 이미 꺼내 둔 `textStorage`를 그대로 받는다.
    private func applyBodyTypingAttributesIfEmpty(to textView: NSTextView, textStorage: NSTextStorage) {
        guard textStorage.length == 0 else { return }
        let baseFont = settings.sermonPlatformFont(for: .body)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = baseFont.typographicLineHeight * max(0, settings.sermonLineHeightMultiple(for: .body) - 1)
        textView.typingAttributes = [
            .font: baseFont,
            .paragraphStyle: paragraphStyle,
            .sermonParagraphStyle: SermonParagraphStyle.body.rawValue
        ]
    }

    private func applyBackground(to textView: NSTextView) {
        let color = isEditable ? editingBackgroundColor : readOnlyBackgroundColor
        textView.backgroundColor = color ?? .clear
        textView.drawsBackground = color != nil
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextStorageDelegate {
        var parent: SermonParagraphEditorRepresentable
        var lastExportedRTF: String = ""
        var isProcessing = false
        var isLoadingExternally = false
        weak var textView: NSTextView?

        init(_ parent: SermonParagraphEditorRepresentable) { self.parent = parent }

        // [빌드 에러 수정] AppKit(macOS)의 `NSTextStorageDelegate`는 iOS와 달리
        // 아직 `NSTextStorage.EditActions`(중첩 타입)가 아니라 예전 전역
        // typealias `NSTextStorageEditActions`를 쓴다 — `RichTextEditor.swift`
        // (Views/Memo/RichTextEditor.swift, 2026-08-12 수정 주석)에 이미 같은
        // 이유로 기록된, 이 프로젝트에서 이전에 한 번 해결된 문제다.
        func textStorage(
            _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange, changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters) || editedMask.contains(.editedAttributes) else { return }
            guard !isProcessing, !isLoadingExternally else { return }
            isProcessing = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let (rtf, plain) = RichTextCodec.encode(textStorage)
                let styles = SermonParagraphStyleCodec.export(from: textStorage)
                self.lastExportedRTF = rtf
                self.parent.rtfText = rtf
                self.parent.plainText = plain
                self.parent.paragraphStyles = styles
                self.isProcessing = false
            }
        }
    }
}

#endif

// MARK: - 공개 View

/// 문단 프리셋 스타일을 지원하는 설교 작성 에디터 — 텍스트뷰만 감싼다(툴바는
/// `SermonEditorView`가 화면 상단에 직접 구성한다, 파일 상단 주석 참고). 6종
/// 스타일 드롭다운/B/I 토글/"말씀구절 + 추가"는 모두 `SermonParagraphEditingProxy`
/// 를 통해 이 에디터를 조작한다.
struct SermonParagraphEditor: View {
    @Binding var contentHtml: String
    @Binding var contentText: String
    @Binding var paragraphStyles: String
    /// [2026-09-29 5번 항목] 호출부(`SermonEditorView`)가 `subject.
    /// styleFontSnapshot`을 그대로 넘긴다 — `SermonParagraphEditorRepresentable.
    /// styleFontSnapshot` 상단 주석 참고.
    var styleFontSnapshot: String
    var isEditable: Bool
    var proxy: SermonParagraphEditingProxy

    var body: some View {
        let settings = UserSettingsStore.shared
        #if os(iOS)
        SermonParagraphEditorRepresentable(
            rtfText: $contentHtml,
            plainText: $contentText,
            paragraphStyles: $paragraphStyles,
            styleFontSnapshot: styleFontSnapshot,
            isEditable: isEditable,
            proxy: proxy,
            settings: settings,
            editingBackgroundColor: .systemBackground,
            readOnlyBackgroundColor: nil
        )
        #elseif os(macOS)
        SermonParagraphEditorRepresentable(
            rtfText: $contentHtml,
            plainText: $contentText,
            paragraphStyles: $paragraphStyles,
            styleFontSnapshot: styleFontSnapshot,
            isEditable: isEditable,
            proxy: proxy,
            settings: settings,
            editingBackgroundColor: .textBackgroundColor,
            readOnlyBackgroundColor: nil
        )
        #endif
    }
}
