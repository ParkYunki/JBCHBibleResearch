//
//  RichTextEditor.swift
//  JBCHBibleResearch
//
//  [2026-08-09 전면 교체] 사용자가 다른 프로젝트의 macOS 전용 리치 텍스트 에디터
//  참고 파일(`RichTextEditor.swift`, `NSTextView`/AppKit 래퍼)을 제공하며 요청:
//  "사이드바 [개요], [내 메모], [메모 팝업] 등의 리치 텍스트 구성을, 첨부파일을
//  면밀히 살펴보고 최대한 그대로 구성하되 macOS/iOS 둘 다 호환되게, 완벽히
//  반영하지 않아도 되지만 호환성 유지한도 내에서 최대한. 그리고 새 문단을 버튼
//  으로 추가하는 게 아니라 메모장처럼 풀 텍스트로 작성하고 문단 구분은 하지
//  않도록."
//
//  ⚠️ [기존 RichTextBlockEditor.swift/MemoRichTextDocument.swift 폐기, 이유]
//  이전 구현은 "문단(블록) 배열 + 문단 전체 단위 서식 토글 + '새 문단' 버튼"
//  구조였다(그 파일들 상단 주석 — Xcode 컴파일 검증이 불가능한 환경에서 SwiftUI
//  표준 API만으로 안전하게 구현하려던 의도적 단순화였다). 이번 요청은 정확히 그
//  구조를 없애 달라는 것이라 전면 교체했다. 참고 파일이 macOS 전용이라, 그 설계
//  원칙 3가지는 그대로 가져오고 iOS/iPadOS 대응만 대칭적으로 추가했다:
//    1. 편집기가 "서식 있는 문자열"과 "순수 텍스트" 두 값을 항상 함께 부모에게
//       돌려준다.
//    2. `NSTextStorageDelegate.didProcessEditing`에서 매 변경(문자/속성 모두)마다
//       그 두 값을 재계산해 내보낸다.
//    3. 부모가 방금 내보낸 값과 같은 값을 다시 내려보내면(에디터 자신이 만든
//       변경의 메아리) 뷰를 다시 그리지 않는다 — 무한 루프 방지("lastExportedText"
//       가드).
//  iOS 쪽은 `SelectableVerseTextView.swift`가 이미 쓰고 있는 관례를 그대로 따랐다
//  — `#if os(iOS)` UIViewRepresentable / `#elseif os(macOS)` NSViewRepresentable를
//  같은 타입 이름으로 나란히 선언한다(둘을 하나로 묶는 추상화 레이어를 새로 만들지
//  않는다 — 이 프로젝트가 반복적으로 택해 온, 컴파일 신뢰도를 우선하는 방식).
//
//  ⚠️ [저장 형식 변경, 명확히 플래그] `UserMemo`/`BookOutline`/`ChapterSummary`의
//  `contentHtml` 필드는 스키마상 이름은 그대로 두었다(스키마 변경/CloudKit
//  마이그레이션을 피하려는 목적 — 문자열 필드라 내부에 뭘 담든 스키마 자체는
//  바뀌지 않는다). 하지만 지금부터 그 안에는 HTML이 아니라 **RTF 문자열**이
//  저장된다 — 참고 파일이 `NSAttributedString.rtf(from:documentAttributes:)`로
//  만드는 바로 그 형식이다(아래 `RichTextCodec` 참고). `contentText`(검색/미리보기/
//  임베딩용 순수 텍스트) 쪽 계약은 전혀 바뀌지 않았다 — `MemoRowView`/
//  `SearchViewModel`/`EmbeddingIndexingService`/`TagDrilldownView` 등 다른 모든
//  화면은 `contentText`만 읽으므로 이번 변경의 영향이 없다(전수 확인함).
//  유일한 부작용: 이전에 HTML로 저장돼 있던 기존 메모/개요를 다시 열면, `{\rtf1`로
//  시작하지 않으니 "일반 텍스트"로 인식되어 `<p>...</p>` 같은 태그가 그대로 화면에
//  보인다 — 1회성 전환 비용으로, 자동 마이그레이션은 이번 범위 밖이다(사용자에게
//  별도로 안내함).
//
//  ⚠️ [문단 스타일(H1~H3/목록/인용) 제거] 참고 파일에는 그런 개념 자체가 없고,
//  "메모장처럼 풀 텍스트, 문단 구분 없음" 요청과도 직접 배치되므로 이번 교체에서
//  헤딩/목록/인용 토글을 들어냈다. 남는 서식은 굵게/기울임/밑줄/글자색/글꼴
//  다섯 가지뿐이다 — 문단 전체가 아니라 "선택한 부분"에만 적용된다(이전 구현이
//  범위 밖으로 남겨 뒀던 부분 선택 서식이, 참고 파일처럼 진짜 텍스트 뷰를 직접
//  감싸는 방식으로 바뀌면서 오히려 자연스럽게 가능해졌다).
//
//  ⚠️ [플랫폼별 UI 차이, 의도적] macOS는 참고 파일 그대로 `usesInspectorBar/
//  usesFontPanel/usesRuler = true`만 켠다 — 텍스트를 선택하면 애플이 직접 그리는
//  네이티브 서식 팝업(macOS 14+)이 자동으로 뜨므로 별도 SwiftUI 툴바를 만들지
//  않았다. iOS/iPadOS는 그런 자동 서식 팝업이 없어(`allowsEditingTextAttributes`는
//  굵게/기울임/밑줄까지만 "aA" 메뉴로 지원) 색상/글꼴까지 다루는 작은 커스텀
//  툴바를 별도로 뒀다. 기능은 최대한 맞췄지만 겉모습(챙기는 서식 항목의 개수 등)은
//  플랫폼마다 다르다 — "완벽하게 반영하지 않아도 되지만 호환성 유지한도 내에서
//  최대한"이라는 요청 범위 안의 의도적 타협이다.
//
//  ⚠️ [Xcode 확인 필요] `UIFontDescriptor.withSymbolicTraits(_:)`(iOS, 실패 시
//  nil 가능)와 `NSFontDescriptor.withSymbolicTraits(_:)`(macOS, 항상 성공하지만
//  그 디스크립터로 실제 `NSFont`를 만드는 `NSFont(descriptor:size:)`가 실패 가능)
//  둘 다 컴파일 검증 없이 기억에 의존해 작성했다 — 굵게/기울임 토글이 실기기에서
//  기대대로 동작하는지 확인이 필요하다.
//
//  [2026-08-09 추가] 사용자 요청 — "성경 조회 사이드바 메모/확대보기 메모"의
//  편집모드 기본 입력 스타일(글꼴/크기/줄간격/배경색)과 조회모드 배경색을
//  다른 화면(내 메모/개요)과 다르게 지정할 수 있어야 한다. `typingFont`/
//  `lineHeightMultiple`/`editingBackgroundColor`/`readOnlyBackgroundColor`
//  네 파라미터를 추가했다 — 전부 기본값이 "기존 동작 그대로"라 다른 호출부
//  (MemoDetailView 표준 모드, OutlineView)는 코드를 바꾸지 않아도 영향이 없다.
//  ⚠️ [용어 해석] "줄 간격 1.5"는 애플 API의 `NSParagraphStyle.lineSpacing`
//  (줄 사이에 "추가"하는 포인트 값)이 아니라, 워드프로세서에서 흔히 말하는
//  "1.5줄 간격"(전체 줄 높이가 한 줄 기본 높이의 1.5배)로 해석했다 — 그래서
//  `lineSpacing = 폰트의 한 줄 높이 × (배수 - 1)`로 환산한다(아래
//  `typographicLineHeight` 참고).
//

import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - 저장 문자열(RTF) ↔ NSAttributedString 왕복 변환

/// `*.contentHtml` 필드(실제로는 RTF — 위 파일 상단 주석 참고)와 화면에 그릴
/// `NSAttributedString` 사이의 변환을 한 곳에 모은다. 에디터 내부
/// (`RichTextEditorRepresentable.Coordinator`)와, 에디터를 거치지 않고 프로그램적
/// 으로 텍스트를 넣는 경우(`OutlineView`의 "AI 초안 적용")가 같은 규칙을 쓰도록
/// 공유한다.
enum RichTextCodec {
    /// 저장된 문자열을 읽어들인다. `{\rtf1`로 시작하면 RTF로 디코딩하고,
    /// 아니면(빈 문자열이거나, 예전 HTML 형식으로 저장된 레거시 데이터이거나)
    /// 있는 그대로를 순수 텍스트로 취급해 기본 서식을 입힌다 — 레거시 HTML은
    /// 태그가 그대로 보이는 1회성 전환 비용을 감수한다(파일 상단 주석 참고).
    /// `defaultAttributes`는 폰트만이 아니라 문단 스타일(줄간격)까지 함께
    /// 넘길 수 있도록 `[NSAttributedString.Key: Any]`로 받는다 — 실제로
    /// 화면에 아무 내용도 없을 때(빈 문서)조차 캐럿 높이가 편집모드 기본
    /// 서식과 맞아떨어지게 하기 위해서다.
    static func decode(_ stored: String, defaultAttributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        if stored.hasPrefix("{\\rtf1"), let data = stored.data(using: .utf8) {
            #if os(iOS)
            if let attrString = try? NSAttributedString(
                data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil
            ) {
                return attrString
            }
            #elseif os(macOS)
            if let attrString = NSAttributedString(rtf: data, documentAttributes: nil) {
                return attrString
            }
            #endif
        }
        return NSAttributedString(string: stored, attributes: defaultAttributes)
    }

    /// 서식 있는 문자열을 RTF로, 그리고 그 안의 순수 텍스트를 함께 돌려준다.
    /// RTF 인코딩이 실패하면(이론상 거의 없지만) 순수 텍스트를 두 값 모두에 쓴다
    /// — 서식은 잃어도 최소한 내용은 잃지 않는다.
    static func encode(_ attributed: NSAttributedString) -> (rtf: String, plainText: String) {
        let plainText = attributed.string
        let fullRange = NSRange(location: 0, length: attributed.length)
        #if os(iOS)
        if let data = try? attributed.data(from: fullRange, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]),
           let rtfString = String(data: data, encoding: .utf8) {
            return (rtfString, plainText)
        }
        #elseif os(macOS)
        if let data = attributed.rtf(from: fullRange, documentAttributes: [:]),
           let rtfString = String(data: data, encoding: .utf8) {
            return (rtfString, plainText)
        }
        #endif
        return (plainText, plainText)
    }

    /// [2026-08-15 추가] 사용자 요청 — "[개요 별도 창] 상단에 돋보기 버튼(배율
    /// 확대/축소/원본크기) 기능." 저장된 서식(굵게/기울임/글꼴 종류/글자색/
    /// 밑줄/문단 정렬 등)은 전혀 건드리지 않고, 지금 각 글자에 걸려 있는
    /// 크기에 배율(`factor`)만 곱한다 — `normalizingFontSize`(모든 글자 크기를
    /// 하나의 절대값으로 맞추는 것)와 달리 원본 문서 안의 상대적인 크기 차이
    /// (예: 강조를 위해 일부러 크게 쓴 글자)를 그대로 유지한 채 전체를 함께
    /// 확대/축소한다 — 브라우저의 "페이지 확대"와 같은 개념. `factor == 1.0`이면
    /// "원본 크기"이므로 아무 작업도 하지 않고 그대로 돌려준다(불필요한 복사
    /// 방지). 호출부는 `OutlineQuickViewWindowContent.attributedText` 참고.
    static func scalingFontSize(_ attributed: NSAttributedString, by factor: CGFloat) -> NSAttributedString {
        guard attributed.length > 0, factor != 1.0 else { return attributed }
        let mutable = NSMutableAttributedString(attributedString: attributed)
        let fullRange = NSRange(location: 0, length: mutable.length)
        mutable.enumerateAttribute(.font, in: fullRange, options: []) { value, subrange, _ in
            let font = (value as? PlatformFont) ?? EditorDefaultStyle.typingFont
            let newSize = max(1, font.pointSize * factor)
            #if os(iOS)
            let resized = font.withSize(newSize)
            #elseif os(macOS)
            let resized = NSFont(descriptor: font.fontDescriptor, size: newSize) ?? font
            #endif
            mutable.addAttribute(.font, value: resized, range: subrange)
        }
        return mutable
    }
}

// MARK: - 줄 높이 계산 (플랫폼 차이 흡수)

extension PlatformFont {
    /// "줄 간격 1.5" 같은 배수 지정을 실제 포인트 값으로 환산하려면 폰트의
    /// "한 줄 기본 높이"가 필요하다. iOS `UIFont`는 이걸 `.lineHeight`로 바로
    /// 제공하지만, ⚠️ macOS `NSFont`에는 그런 공개 프로퍼티가 없다 —
    /// AppKit에서 관용적으로 쓰는 계산식(`ascender - descender + leading`,
    /// `NSLayoutManager.defaultLineHeight(for:)` 내부 구현과 동일한 값)으로
    /// 직접 구한다.
    var typographicLineHeight: CGFloat {
        #if os(iOS)
        return lineHeight
        #elseif os(macOS)
        return ascender - descender + leading
        #endif
    }
}

extension PlatformColor {
    /// "조회모드 배경 = 시스템 배경색" 요청용 — iOS `.systemBackground`와 macOS
    /// `.textBackgroundColor`(텍스트 컨테이너 배경 전용, 라이트/다크 모드에
    /// 맞춰 자동 전환)를 하나의 이름으로 묶는다. 둘 다 애플이 제공하는 표준
    /// 동적(dynamic) 색상이라 다크 모드 전환에 별도 대응이 필요 없다.
    static var systemContentBackground: PlatformColor {
        #if os(iOS)
        return .systemBackground
        #elseif os(macOS)
        return .textBackgroundColor
        #endif
    }
}

// MARK: - 공개 View

/// 메모(S2/S3)/책 개요(S8)/장 개요(S9)/메모 팝업이 공유하는 리치 텍스트 에디터.
/// 호출부는 저장 문자열(RTF) 바인딩과 순수 텍스트 바인딩 두 개만 넘기면 된다 —
/// 문단 배열 같은 중간 상태를 직접 관리할 필요가 없다(옛 `RichTextBlockEditor` +
/// `MemoRichTextDocument` 조합 대신, 이 타입이 내부적으로 다 처리한다).
struct RichTextEditor: View {
    @Binding var rtfText: String
    @Binding var plainText: String
    var isEditable: Bool
    var placeholder: String = "내용을 입력하세요"

    /// 새로 입력하는 글자에 적용되는 기본 폰트("편집모드의 기본 입력 스타일").
    /// 이미 서식이 있는 기존 내용을 되돌려 바꾸지는 않는다 — 어디까지나
    /// "새로 칠 때" 기본값이다.
    var typingFont: PlatformFont = .systemFont(ofSize: 15)
    /// [2026-08-14 추가] 사용자 요청 — "모든 에디터 창 기본 설정: 글자색."
    /// `typingFont`와 같은 원칙(새로 입력하는 글자에만 적용, 기존 서식은 그대로) —
    /// nil이면 기존 기본값(시스템 라벨 색)을 그대로 쓴다.
    var defaultTextColor: PlatformColor? = nil
    /// 1.0 = 기존 동작(추가 줄간격 없음). 1.5를 넘기면 "1.5줄 간격"에 해당하는
    /// 만큼 `NSParagraphStyle.lineSpacing`을 계산해 넣는다(위 파일 상단 주석의
    /// 용어 해석 참고).
    var lineHeightMultiple: CGFloat = 1.0
    /// nil이면 기존 기본값(투명/시스템 기본 텍스트뷰 배경)을 그대로 쓴다 —
    /// 다른 호출부(내 메모/개요)에 영향이 없도록 하는 하위 호환 기본값.
    var editingBackgroundColor: PlatformColor? = nil
    var readOnlyBackgroundColor: PlatformColor? = nil
    /// [2026-08-11 추가] 사용자 요청 — "확대보기/사이드바 메모 팝업의 글꼴 스타일
    /// 라인을 성경장절정보 라인보다 위로 옮길 것". 이 컴포넌트가 내부적으로
    /// 그리는 iOS 툴바 대신, 호출부(MemoDetailView)가 `RichTextEditorToolbar`를
    /// 직접 헤더보다 먼저 그리고 싶을 때 `false`로 내부 툴바를 끈다. 기본값
    /// `true`는 기존 모든 호출부(내 메모/개요)의 동작을 그대로 유지한다.
    var showsToolbar: Bool = true
    /// [2026-08-12 추가] 사용자 요청("말씀 요약" 화면) — "말씀 스타일 툴바는
    /// 오른쪽 사이드바 에디터영역에 위치하게." macOS는 지금까지 커스텀 툴바가
    /// 아예 없었다 — 텍스트를 선택하면 애플이 직접 그리는 네이티브 서식 팝업
    /// (`usesInspectorBar`)만 떴다. 그 팝업은 선택할 때만 잠깐 뜨는 방식이라
    /// "사이드바 에디터 영역 안에 자리 잡은" 형태가 아니다 — 그래서 iOS와 같은
    /// 상시 노출형 툴바를 macOS에도 켤 수 있는 옵션을 추가했다. 기본값 `false`는
    /// 기존 macOS 호출부(내 메모/개요) 화면을 전혀 건드리지 않는다 — 말씀 요약
    /// 편집기(`WordSummaryEditorView`)만 명시적으로 `true`를 넘긴다.
    var showsToolbarOnMac: Bool = false
    /// 위 `showsToolbar`와 짝을 이룬다 — 외부에서 그리는 `RichTextEditorToolbar`가
    /// 이 안의 실제 텍스트뷰에 서식을 적용하려면 같은 프록시 인스턴스를 공유해야
    /// 한다(프록시가 "지금 포커스된 텍스트뷰"를 들고 있는 다리 역할이기 때문—
    /// 아래 `RichTextEditingProxy` 상단 주석 참고). nil이면(기존 모든 호출부)
    /// 이 컴포넌트가 내부적으로 만드는 프록시를 그대로 쓴다.
    var externalProxy: RichTextEditingProxy? = nil

    @State private var internalProxy = RichTextEditingProxy()
    private var proxy: RichTextEditingProxy { externalProxy ?? internalProxy }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            #if os(iOS)
            if isEditable && showsToolbar {
                toolbar
                Divider()
            }
            #elseif os(macOS)
            if isEditable && showsToolbar && showsToolbarOnMac {
                toolbar
                Divider()
            }
            #endif

            RichTextEditorRepresentable(
                rtfText: $rtfText, plainText: $plainText, isEditable: isEditable, proxy: proxy,
                typingFont: typingFont, defaultTextColor: defaultTextColor, lineHeightMultiple: lineHeightMultiple,
                editingBackgroundColor: editingBackgroundColor, readOnlyBackgroundColor: readOnlyBackgroundColor,
                // [2026-08-12 추가] macOS 네이티브 서식 팝업(`usesInspectorBar`)을
                // 끄고 커스텀 툴바만 남기려면 이 값이 실제 텍스트뷰 struct까지
                // 전달돼야 한다 — 두 struct 모두 마지막 파라미터라 순서 그대로 추가.
                showsToolbarOnMac: showsToolbarOnMac
            )
            .frame(minHeight: 220)
            .overlay(alignment: .topLeading) {
                // 참고 파일에는 없지만, "메모장처럼" 요청과 잘 맞는 저비용 UX —
                // 텍스트 뷰 안쪽 여백(8pt + 기본 lineFragmentPadding)에 대략
                // 맞춘 근사치 패딩이라 픽셀 단위로 정확히 겹치지는 않는다.
                if isEditable && plainText.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var toolbar: some View {
        RichTextEditorToolbarContent(proxy: proxy)
    }
}

/// [2026-08-11 추가, 2026-08-12 크로스플랫폼으로 확장] `RichTextEditor`가
/// 내부적으로 쓰는 툴바를 호출부가 컴포넌트 바깥에서 독립적으로도 그릴 수 있게
/// 공개한다 — `RichTextEditor.showsToolbar`/`showsToolbarOnMac`/`externalProxy`
/// 상단 주석 참고. 같은 `proxy` 인스턴스를 넘겨야 버튼이 실제 텍스트뷰에
/// 작용한다.
///
/// [2026-08-12] 원래 iOS 전용이었다(macOS는 네이티브 `usesInspectorBar` 팝업만
/// 썼다) — "말씀 요약" 편집기 요청으로 macOS에도 상시 노출 툴바가 필요해져
/// `#if os(iOS)` 가드를 뺐다. 이 뷰 자체는 `proxy.toggleBold()` 등 메서드 호출만
/// 하는데, 그 메서드들은 iOS/macOS `RichTextEditingProxy` 두 클래스(각각
/// `#if os(iOS)`/`#elseif os(macOS)`로 플랫폼별로 정의됨) 모두에 이름과 시그니처가
/// 동일하게 있어 이 뷰 코드 자체는 손댈 필요가 없었다.
struct RichTextEditorToolbar: View {
    var proxy: RichTextEditingProxy
    var body: some View { RichTextEditorToolbarContent(proxy: proxy) }
}

/// [2026-08-12 추가] 사용자 요청 — "아이패드 서식 툴바는 너무 빈약함. 최소한
/// 메모 앱과 같은 서식이 있어야 함 ... 글꼴변경(페이퍼로지 포함) / 글꼴크기 /
/// 문단 정렬(왼쪽,가운데,오른쪽)." 요청 범위를 이 세 가지로 명시적으로
/// 한정했다 — 참고 화면(첨부 스크린샷)에 보이는 글머리 기호/인용/제목 스타일
/// 등은 이번 요청 범위 밖이라 넣지 않았다(과거 세션에서 이미 한 번 스코프를
/// 줄인 결정과 같은 원칙 — 필요해지면 나중에 별도로 추가).
private let systemToolbarFontNames = ["Georgia", "Helvetica", "Courier New", "Avenir Next", "Times New Roman"]
private let toolbarFontSizes: [CGFloat] = [12, 13, 14, 15, 17, 19, 22, 26, 32]

private struct RichTextEditorToolbarContent: View {
    var proxy: RichTextEditingProxy

    var body: some View {
        HStack(spacing: 14) {
            Button { proxy.toggleBold() } label: { Image(systemName: "bold") }
            Button { proxy.toggleItalic() } label: { Image(systemName: "italic") }
            Button { proxy.toggleUnderline() } label: { Image(systemName: "underline") }

            Divider().frame(height: 16)

            Menu {
                Button("기본색") { proxy.applyColor(nil) }
                ForEach(Color.memoTextPalette, id: \.hex) { swatch in
                    Button(swatch.name) { proxy.applyColor(swatch.hex) }
                }
            } label: {
                Image(systemName: "paintpalette")
            }

            // [2026-08-12 확장] 기존 3개(Georgia/Helvetica/Courier New)에
            // 앱 내장 Paperlogy 9종(`BundledFonts.entries`)과 아이패드에서도
            // 항상 쓸 수 있는 시스템 내장 폰트 2종(Avenir Next/Times New Roman)을
            // 더했다 — `applyFontFamily`가 받는 이름은 family가 아니라 PostScript
            // 이름이라(`BundledFontRegistrar.swift` 상단 주석 참고) `entry.postScriptName`을
            // 그대로 넘긴다.
            Menu {
                Button("기본 폰트") { proxy.applyFontFamily(nil) }
                Divider()
                Menu("Paperlogy") {
                    ForEach(BundledFonts.entries) { entry in
                        Button(entry.displayName) { proxy.applyFontFamily(entry.postScriptName) }
                    }
                }
                Divider()
                ForEach(systemToolbarFontNames, id: \.self) { name in
                    Button(name) { proxy.applyFontFamily(name) }
                }
            } label: {
                Image(systemName: "textformat")
            }

            // [2026-08-12 신설] 글꼴 크기. iOS 기본 본문 크기(15pt)를 중심으로
            // 자주 쓰는 크기들을 나열했다 — 자유 입력(TextField)이 아니라 Menu인
            // 이유는 이 컴포넌트가 iPhone 좁은 화면의 상시 노출 툴바에도 쓰이기
            // 때문에(숫자 입력 키보드 전환 없이) 탭 한 번으로 끝나는 쪽이 낫다고
            // 판단했다.
            Menu {
                ForEach(toolbarFontSizes, id: \.self) { size in
                    Button("\(Int(size))pt") { proxy.applyFontSize(size) }
                }
            } label: {
                Image(systemName: "textformat.size")
            }

            Divider().frame(height: 16)

            // [2026-08-12 신설] 문단 정렬(왼쪽/가운데/오른쪽) — 사용자가 명시적으로
            // 요청한 3가지만 넣었다(양쪽 정렬/자연 정렬 등은 요청 범위 밖).
            Button { proxy.applyAlignment(.left) } label: { Image(systemName: "text.alignleft") }
            Button { proxy.applyAlignment(.center) } label: { Image(systemName: "text.aligncenter") }
            Button { proxy.applyAlignment(.right) } label: { Image(systemName: "text.alignright") }

            Spacer()
        }
        .buttonStyle(.plain)
        .font(.system(size: 15))
        .padding(.vertical, 6)
    }
}

// MARK: - iOS

#if os(iOS)

/// 위 iOS 전용 툴바가 "지금 포커스된 `UITextView`의 선택 영역"에 직접 서식을
/// 적용하기 위한 다리. `makeUIView`가 실제 인스턴스를 만들면서 이 프록시에
/// 등록해 준다. 커서 위치가 바뀔 때마다 "지금 굵게 상태인지"를 추적해 버튼을
/// 눌러진 상태로 보여주는 것까지는 하지 않는다(범위를 눌렀을 때 토글만 되는
/// 단순한 형태) — 매 선택 변경마다 다시 계산하는 비용/복잡도 대비 필요성이
/// 낮다고 판단했다.
@MainActor
final class RichTextEditingProxy {
    weak var textView: UITextView?

    func toggleBold() { toggleTrait(.traitBold) }
    func toggleItalic() { toggleTrait(.traitItalic) }

    func toggleUnderline() {
        guard let textView else { return }
        let range = textView.selectedRange
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let isUnderlined = ((attrs[.underlineStyle] as? Int) ?? 0) != 0
            attrs[.underlineStyle] = isUnderlined ? 0 : NSUnderlineStyle.single.rawValue
            textView.typingAttributes = attrs
            return
        }
        let storage = textView.textStorage
        let current = (storage.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int) ?? 0
        storage.beginEditing()
        storage.addAttribute(.underlineStyle, value: current != 0 ? 0 : NSUnderlineStyle.single.rawValue, range: range)
        storage.endEditing()
    }

    /// [2026-08-12 추가] 사용자 요청 — "[말씀 복사] 탭/클릭시 오른쪽 사이드바
    /// 에디터 커서 위치한 곳에 성경구절 복사 붙여넣기 실행." 지금 선택 영역이
    /// 있으면 그 자리를 바꿔치기하고(일반적인 "붙여넣기" 동작과 동일), 캐럿만
    /// 있으면(길이 0) 그 위치에 밀어 넣는다 — 삽입한 텍스트는 지금 타이핑
    /// 속성(`typingAttributes`, 편집기 기본 서식)을 그대로 입혀 붙는다. 실제
    /// 삽입은 `NSTextStorage.replaceCharacters(in:with:)`인데, 이 편집기의
    /// 다른 서식 적용 메서드들(`toggleBold` 등)과 마찬가지로 `NSTextStorageDelegate.
    /// didProcessEditing`가 자동으로 걸려 `rtfText`/`plainText` 바인딩까지 별도
    /// 코드 없이 그대로 갱신된다.
    func insertTextAtCursor(_ text: String) {
        guard let textView else { return }
        let range = textView.selectedRange
        let storage = textView.textStorage
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: textView.typingAttributes))
        storage.endEditing()
        textView.selectedRange = NSRange(location: range.location + (text as NSString).length, length: 0)
    }

    func applyColor(_ hex: String?) {
        guard let textView else { return }
        let color = hex.flatMap { Color(hex: $0) }.map(PlatformColor.init) ?? PlatformColor.label
        apply(.foregroundColor, value: color, on: textView)
    }

    func applyFontFamily(_ family: String?) {
        guard let textView else { return }
        let range = textView.selectedRange
        func makeFont(basedOn font: UIFont) -> UIFont {
            guard let family else { return UIFont.systemFont(ofSize: font.pointSize) }
            return UIFont(name: family, size: font.pointSize) ?? font
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

    /// [2026-08-12 추가] 사용자 요청 — "글꼴크기". `applyFontFamily`와 완전히
    /// 같은 구조(캐럿만 있으면 `typingAttributes`, 선택 범위가 있으면
    /// `enumerateAttribute`로 기존 폰트의 다른 속성(굵게/기울임 등)은 보존한 채
    /// 크기만 바꾼다 — `UIFont.withSize(_:)`가 트레이트를 그대로 유지해 준다.
    func applyFontSize(_ size: CGFloat) {
        guard let textView else { return }
        let range = textView.selectedRange
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let font = (attrs[.font] as? UIFont) ?? UIFont.systemFont(ofSize: 15)
            attrs[.font] = font.withSize(size)
            textView.typingAttributes = attrs
            return
        }
        let storage = textView.textStorage
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? UIFont) ?? UIFont.systemFont(ofSize: 15)
            storage.addAttribute(.font, value: font.withSize(size), range: subrange)
        }
        storage.endEditing()
    }

    /// [2026-08-12 추가] 사용자 요청 — "문단 정렬(왼쪽, 가운데, 오른쪽)". 정렬은
    /// 글자 단위가 아니라 문단(paragraph) 단위 속성이라, 선택 범위가 짧아도
    /// (예: 캐럿만 있거나 한 글자만 선택돼도) 그 문단 전체에 적용돼야 자연스럽다
    /// — `NSString.paragraphRange(for:)`로 선택 범위가 걸친 문단 전체 범위를
    /// 구해서 적용한다. 기존 문단 스타일의 다른 값(줄간격 등, `applyLineHeight`
    /// 등에서 설정)은 `mutableCopy()`로 복사해 정렬값만 덮어써 보존한다.
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
        // 다음에 이어 칠 글자에도 같은 정렬이 적용되도록 타이핑 속성도 맞춰 둔다.
        var attrs = textView.typingAttributes
        attrs[.paragraphStyle] = makeParagraphStyle(basedOn: attrs[.paragraphStyle] as? NSParagraphStyle)
        textView.typingAttributes = attrs
    }

    private func toggleTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
        guard let textView else { return }
        let range = textView.selectedRange
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let font = (attrs[.font] as? UIFont) ?? UIFont.systemFont(ofSize: 15)
            attrs[.font] = font.togglingTrait(trait)
            textView.typingAttributes = attrs
            return
        }
        let storage = textView.textStorage
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? UIFont) ?? UIFont.systemFont(ofSize: 15)
            storage.addAttribute(.font, value: font.togglingTrait(trait), range: subrange)
        }
        storage.endEditing()
    }

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
    /// ⚠️ [Xcode 확인 필요, 파일 상단 주석 참고] 조합이 지원되지 않는 폰트에서
    /// `withSymbolicTraits(_:)`가 nil을 돌려주면 원래 폰트를 그대로 반환해
    /// 조용히 무시한다 — 서식 하나가 안 먹는 게 에디터가 멈추는 것보다 낫다.
    func togglingTrait(_ trait: UIFontDescriptor.SymbolicTraits) -> UIFont {
        var traits = fontDescriptor.symbolicTraits
        if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

struct RichTextEditorRepresentable: UIViewRepresentable {
    @Binding var rtfText: String
    @Binding var plainText: String
    var isEditable: Bool
    var proxy: RichTextEditingProxy
    var typingFont: UIFont = .systemFont(ofSize: 15)
    var defaultTextColor: UIColor? = nil
    var lineHeightMultiple: CGFloat = 1.0
    var editingBackgroundColor: UIColor? = nil
    var readOnlyBackgroundColor: UIColor? = nil
    /// iOS엔 애초에 네이티브 인스펙터 바가 없어(macOS 전용 AppKit 기능) 이 값이
    /// 아무 영향도 없다 — macOS 쪽 구조체와 호출부 시그니처를 맞추기 위해서만
    /// 존재한다(`RichTextEditor.body`의 공유 호출부 참고).
    var showsToolbarOnMac: Bool = false

    private var typingAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = typingFont.typographicLineHeight * max(0, lineHeightMultiple - 1)
        var attrs: [NSAttributedString.Key: Any] = [.font: typingFont, .paragraphStyle: paragraph]
        if let defaultTextColor { attrs[.foregroundColor] = defaultTextColor }
        return attrs
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.font = typingFont
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.textStorage.delegate = context.coordinator

        context.coordinator.textView = textView
        proxy.textView = textView

        loadInitialContent(into: textView, coordinator: context.coordinator)
        applyBackground(to: textView)
        applyStyleToolsVisibility(to: textView)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        uiView.isEditable = isEditable
        proxy.textView = uiView
        applyBackground(to: uiView)
        applyStyleToolsVisibility(to: uiView)

        guard rtfText != context.coordinator.lastExportedText else { return }
        loadInitialContent(into: uiView, coordinator: context.coordinator)
    }

    /// [2026-08-31 추가] macOS에서 신고된 크래시(아래 macOS 쪽 `dismantleNSView`
    /// 주석 참고)와 정확히 같은 구조적 위험이 아이패드에도 있다 — `OutlineTreeView.
    /// swift`의 `.id(selection)`이 장을 바꿀 때마다 이 `UITextView`도 통째로
    /// 새로 만들고 버리는데, `UITextView`의 undo 관리자 역시 응답자 체인을 타고
    /// 올라가 윈도우가 공유하는 것을 쓰는 건 UIKit도 AppKit과 같다. 아직 실제로
    /// 보고되진 않았지만(외장 키보드로 Command+Z를 쓰는 경우가 적어서로 보임 —
    /// 개요 편집 화면은 아이패드에서도 "풀 기능"으로 지원되는 화면이라 이 코드
    /// 경로를 그대로 탄다), 같은 원인이 같은 결과를 낼 것이 확실해 macOS와
    /// 대칭으로 미리 막는다.
    static func dismantleUIView(_ uiView: UITextView, coordinator: Coordinator) {
        uiView.undoManager?.removeAllActions(withTarget: uiView)
    }

    /// [2026-08-09 추가] 사용자 요청 — "조회모드 스타일 도구 감추기". iOS의 "aA"
    /// 편집 메뉴(굵게/기울임/밑줄)와 하드웨어 키보드 단축키(⌘B/⌘I/⌘U)는
    /// `allowsEditingTextAttributes`가 켜져 있을 때만 나타난다 — 편집 가능할
    /// 때만 켠다(macOS `usesInspectorBar`에 해당하는, iOS가 기본 제공하는 가장
    /// 가까운 대응책도 같은 원리로 꺼 둔다).
    private func applyStyleToolsVisibility(to textView: UITextView) {
        textView.allowsEditingTextAttributes = isEditable
    }

    private func loadInitialContent(into textView: UITextView, coordinator: Coordinator) {
        // [자기 자신이 만든 변경의 메아리 방지] 아래서 `setAttributedString`을
        // 부르면 `NSTextStorage`가 내부적으로 `processEditing()`을 동기 호출해
        // `didProcessEditing` 델리게이트가 곧바로(비동기 큐에 들어가기 전에) 다시
        // 불린다 — 이 프로그램적 로드를 "사용자가 입력한 변경"으로 착각해 다시
        // 내보내면, 화면을 열기만 해도 매번 `updatedAt`이 갱신되고 불필요한
        // 자동저장이 예약되는 부작용이 생긴다(참고 파일에는 없던, 이 프로젝트의
        // 자동저장 체계 때문에 새로 필요해진 가드).
        coordinator.isLoadingExternally = true
        let attributed = RichTextCodec.decode(rtfText, defaultAttributes: typingAttributes)
        textView.textStorage.setAttributedString(attributed)
        // `setAttributedString`이 타이핑 속성을 문서 끝 글자 기준으로 다시
        // 계산해 버릴 수 있어, "새로 입력할 때 기본값"은 항상 명시적으로
        // 다시 맞춰 준다 — 기존 내용의 서식과는 무관하다.
        textView.typingAttributes = typingAttributes
        coordinator.isLoadingExternally = false
        coordinator.lastExportedText = rtfText
    }

    /// "조회모드는 시스템 배경색, 편집모드는 지정한 색"(예: 흰색) — 요청한
    /// 화면에서만 값을 넘기고, 나머지 화면은 nil을 넘겨 기존 기본값(투명)을
    /// 그대로 유지한다.
    private func applyBackground(to textView: UITextView) {
        let color = isEditable ? editingBackgroundColor : readOnlyBackgroundColor
        textView.backgroundColor = color ?? .clear
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextStorageDelegate {
        var parent: RichTextEditorRepresentable
        var lastExportedText: String = ""
        var isProcessing = false
        var isLoadingExternally = false
        weak var textView: UITextView?

        init(_ parent: RichTextEditorRepresentable) { self.parent = parent }

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
                self.lastExportedText = rtf
                self.parent.rtfText = rtf
                self.parent.plainText = plain
                self.isProcessing = false
            }
        }
    }
}

// MARK: - macOS

#elseif os(macOS)

/// iOS `RichTextEditingProxy`와 같은 역할 — macOS는 `usesInspectorBar`가 켜지면
/// 텍스트 선택 시 애플이 직접 그리는 네이티브 서식 팝업이 뜨므로, 실제로는
/// 이 프록시를 호출할 커스텀 툴바가 없다(위 `RichTextEditor.body`가 macOS에서는
/// 툴바 자체를 그리지 않는다). 그래도 API 대칭을 위해 남겨 둔다 — 나중에 mac에도
/// 커스텀 단축 버튼을 붙이고 싶어지면 바로 쓸 수 있다.
@MainActor
final class RichTextEditingProxy {
    weak var textView: NSTextView?

    func toggleBold() { toggleTrait(.bold) }
    func toggleItalic() { toggleTrait(.italic) }

    func toggleUnderline() {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let isUnderlined = ((attrs[.underlineStyle] as? Int) ?? 0) != 0
            attrs[.underlineStyle] = isUnderlined ? 0 : NSUnderlineStyle.single.rawValue
            textView.typingAttributes = attrs
            return
        }
        let current = (storage.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int) ?? 0
        storage.beginEditing()
        storage.addAttribute(.underlineStyle, value: current != 0 ? 0 : NSUnderlineStyle.single.rawValue, range: range)
        storage.endEditing()
    }

    /// iOS `RichTextEditingProxy.insertTextAtCursor(_:)`와 같은 역할 — 상단 주석
    /// 참고.
    func insertTextAtCursor(_ text: String) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: textView.typingAttributes))
        storage.endEditing()
        textView.setSelectedRange(NSRange(location: range.location + (text as NSString).length, length: 0))
    }

    func applyColor(_ hex: String?) {
        guard let textView, let storage = textView.textStorage else { return }
        let color = hex.flatMap { Color(hex: $0) }.map(PlatformColor.init) ?? PlatformColor.labelColor
        let range = textView.selectedRange()
        if range.length == 0 {
            var attrs = textView.typingAttributes
            attrs[.foregroundColor] = color
            textView.typingAttributes = attrs
            return
        }
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: color, range: range)
        storage.endEditing()
    }

    func applyFontFamily(_ family: String?) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        func makeFont(basedOn font: NSFont) -> NSFont {
            guard let family else { return NSFont.systemFont(ofSize: font.pointSize) }
            return NSFont(name: family, size: font.pointSize) ?? font
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

    /// iOS `RichTextEditingProxy.applyFontSize(_:)`와 같은 이유/구조 — 상단
    /// 주석 참고. `NSFont`엔 `withSize(_:)` 편의 메서드가 없어(AppKit) `NSFont
    /// (descriptor:size:)`로 새 인스턴스를 만든다 — `applyFontFamily`의
    /// `makeFont`와 마찬가지로 실패하면(이론상 거의 없음) 원래 폰트를 그대로 둔다.
    func applyFontSize(_ size: CGFloat) {
        guard let textView, let storage = textView.textStorage else { return }
        func resized(_ font: NSFont) -> NSFont {
            NSFont(descriptor: font.fontDescriptor, size: size) ?? font
        }
        let range = textView.selectedRange()
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let font = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 15)
            attrs[.font] = resized(font)
            textView.typingAttributes = attrs
            return
        }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: 15)
            storage.addAttribute(.font, value: resized(font), range: subrange)
        }
        storage.endEditing()
    }

    /// iOS `RichTextEditingProxy.applyAlignment(_:)`와 같은 이유/구조 — 상단
    /// 주석 참고(정렬은 문단 단위 속성이라 `paragraphRange(for:)`로 선택이 걸친
    /// 문단 전체에 적용한다).
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
            attrs[.font] = font.togglingTrait(trait)
            textView.typingAttributes = attrs
            return
        }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: 15)
            storage.addAttribute(.font, value: font.togglingTrait(trait), range: subrange)
        }
        storage.endEditing()
    }
}

private extension NSFont {
    /// ⚠️ [Xcode 확인 필요, 파일 상단 주석 참고] `NSFontDescriptor.
    /// withSymbolicTraits(_:)` 자체는 옵셔널이 아니지만(디스크립터는 속성
    /// 사전이라 실패할 게 없다), 그 디스크립터로 실제 `NSFont` 인스턴스를 만드는
    /// `NSFont(descriptor:size:)`는 실패할 수 있어(`init?`) 실패 시 원래 폰트를
    /// 그대로 쓴다.
    func togglingTrait(_ trait: NSFontDescriptor.SymbolicTraits) -> NSFont {
        var traits = fontDescriptor.symbolicTraits
        if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
        let descriptor = fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}

struct RichTextEditorRepresentable: NSViewRepresentable {
    @Binding var rtfText: String
    @Binding var plainText: String
    var isEditable: Bool
    var proxy: RichTextEditingProxy
    var typingFont: NSFont = .systemFont(ofSize: 15)
    var defaultTextColor: NSColor? = nil
    var lineHeightMultiple: CGFloat = 1.0
    var editingBackgroundColor: NSColor? = nil
    var readOnlyBackgroundColor: NSColor? = nil
    /// [2026-08-12 추가] 사용자 보고 — "구절 선택후 하단 메뉴의 [말씀 요약]
    /// 버튼 클릭 - 서식 툴바 위치가 내 의도와는 다름." 원인: macOS 네이티브
    /// `usesInspectorBar`는 텍스트를 선택하면 애플이 화면(창) 좌표 기준으로
    /// 띄우는 별도 플로팅 팝오버라, 이 텍스트뷰가 좁은 `.inspector` 오른쪽
    /// 패널 안에 있어도 팝오버 자체는 창 전체 폭을 기준으로 재배치될 수 있어
    /// 왼쪽 성경 본문 위에 떠 보이는 것으로 확인됐다 — SwiftUI/AppKit 어느
    /// 쪽에도 이 팝오버의 앵커 위치를 직접 지정하는 API가 없어 위치 자체를
    /// 고칠 방법이 없다. 대신 이 네이티브 팝오버를 아예 끄고, 항상 오른쪽
    /// 패널 안에 제대로 자리 잡는 커스텀 SwiftUI 툴바(`RichTextEditorToolbar`)
    /// 하나만 쓰기로 했다 — `showsToolbarOnMac`이 켜진 화면(말씀 요약)에서만
    /// 이 값에 따라 네이티브 바를 끈다(`applyStyleToolsVisibility` 참고).
    /// 기존 화면(내 메모/개요, `showsToolbarOnMac == false`)은 지금까지처럼
    /// 네이티브 바를 그대로 쓴다 — 동작 변화 없음.
    var showsToolbarOnMac: Bool = false

    private var typingAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = typingFont.typographicLineHeight * max(0, lineHeightMultiple - 1)
        var attrs: [NSAttributedString.Key: Any] = [.font: typingFont, .paragraphStyle: paragraph]
        if let defaultTextColor { attrs[.foregroundColor] = defaultTextColor }
        return attrs
    }

    func makeNSView(context: Context) -> NSScrollView {
        // 사용자가 제공한 참고 파일의 설정을 그대로 가져왔다 — `usesInspectorBar`
        // (macOS 14+)가 켜지면 텍스트를 선택했을 때 애플이 직접 그리는 굵게/
        // 기울임/밑줄/정렬/글머리 기호/글꼴/색상 팝업이 자동으로 뜬다. 그래서
        // mac 쪽은(iOS와 달리) 커스텀 SwiftUI 툴바를 따로 만들지 않았다.
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = true
        textView.importsGraphics = true
        textView.isContinuousSpellCheckingEnabled = false
        textView.font = typingFont
        textView.textContainerInset = NSSize(width: 8, height: 8)

        textView.textStorage?.delegate = context.coordinator
        context.coordinator.textView = textView
        proxy.textView = textView

        loadInitialContent(into: textView, coordinator: context.coordinator)
        applyBackground(to: textView)
        applyStyleToolsVisibility(to: textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        textView.isEditable = isEditable
        proxy.textView = textView
        applyBackground(to: textView)
        applyStyleToolsVisibility(to: textView)

        guard rtfText != context.coordinator.lastExportedText else { return }
        loadInitialContent(into: textView, coordinator: context.coordinator)
    }

    /// [2026-08-31 추가] 크래시 수정 — 사용자 보고: "개요 1장을 수정하고, 2장으로
    /// 넘어갔다가, 다시 1장에서 Command Z 실행취소를 하면 크래시 발생." 크래시
    /// 로그가 정확히 `-[NSUndoManager undoNestedGroup]` → `-[_NSUndoStack
    /// popAndInvoke]` → `objc_msgSend`를 가리켰다.
    ///
    /// 원인: `OutlineTreeView.swift`의 `.id(selection)`(장을 바꿀 때마다 이
    /// 화면 전체를 새로 만드는 그 modifier)이 장을 전환할 때마다 이
    /// `NSTextView`를 통째로 새로 만들고 이전 것은 버린다. 그런데
    /// `textView.allowsUndo = true`(위 `makeNSView`)가 등록하는 undo 액션은
    /// 이 텍스트뷰 인스턴스 전용이 아니라 **윈도우가 공유하는 단 하나의
    /// `NSUndoManager`**에 쌓인다 — `NSTextView`는 자기 것을 따로 만들지 않고
    /// 응답자 체인을 타고 올라가 윈도우의 것을 그대로 쓰기 때문이다(이 프로젝트
    /// 어디에도 `undoManager`를 서브클래싱하거나 재정의한 곳이 없다). 그래서
    /// 1장을 편집하며 쌓인 undo 액션들이, 1장의 `NSTextView`가 사라진 뒤에도
    /// 이미 해제된 그 인스턴스를 가리킨 채 스택에 그대로 남는다. 나중에 다시
    /// 1장으로 돌아와(이때도 `.id(selection)`이 또 다른 새 `NSTextView`를
    /// 만든다) Command Z를 누르면, 스택에 남아 있던 그 죽은 인스턴스를 가리키는
    /// 액션이 다시 호출되면서 이미 해제된 객체에 메시지를 보내 크래시한다 —
    /// 신고받은 크래시 로그와 정확히 일치하는 흐름이다.
    ///
    /// 해법은 Apple 공식 문서가 명시한 그대로다 — `NSUndoManager.
    /// removeAllActions(withTarget:)` 문서: "타깃이 해제되기 직전에, 이후의
    /// undo/redo 메시지가 유효하지 않은 객체로 가지 않도록 그 타깃을 가리키는
    /// 등록된 액션을 전부 지워야 한다." `dismantleNSView`는 SwiftUI가 이 뷰를
    /// 없애기 직전에 불러주는 지점이라 정확히 맞는 위치다. `withTarget:`을 써서
    /// 이 텍스트뷰를 가리키는 액션만 지우므로, 같은 윈도우의 다른 화면이 갖고
    /// 있을 수 있는 무관한 undo 기록은 건드리지 않는다.
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        textView.undoManager?.removeAllActions(withTarget: textView)
    }

    /// [2026-08-09 추가] 사용자 요청 — "조회모드 스타일 도구 감추기". 참고 파일이
    /// 항상 켜 두던 `usesInspectorBar/usesFontPanel/usesRuler`(텍스트 선택 시
    /// 뜨는 네이티브 서식 팝업/도구)를 편집 가능할 때만 켠다 — 조회 전용으로
    /// 열었을 때(예: 개요를 별도 창으로 열람만 할 때) 서식 도구가 뜨지 않는다.
    /// [2026-08-12 추가] `showsToolbarOnMac`이 켜져 있으면(말씀 요약 화면)
    /// 위치가 어긋나는 네이티브 팝업을 완전히 끄고, 그 화면이 대신 붙이는
    /// 커스텀 `RichTextEditorToolbar` 하나만 남긴다 — 위 struct 상단 주석 참고.
    private func applyStyleToolsVisibility(to textView: NSTextView) {
        let usesNativeBar = isEditable && !showsToolbarOnMac
        textView.usesInspectorBar = usesNativeBar
        textView.usesFontPanel = usesNativeBar
        textView.usesRuler = usesNativeBar
    }

    private func loadInitialContent(into textView: NSTextView, coordinator: Coordinator) {
        // iOS `RichTextEditorRepresentable.loadInitialContent`와 같은 이유의
        // 가드 — 위 주석 참고.
        coordinator.isLoadingExternally = true
        let attributed = RichTextCodec.decode(rtfText, defaultAttributes: typingAttributes)
        textView.textStorage?.setAttributedString(attributed)
        // iOS 쪽과 같은 이유로, "새로 입력할 때 기본값"을 항상 명시적으로
        // 다시 맞춘다.
        textView.typingAttributes = typingAttributes
        coordinator.isLoadingExternally = false
        coordinator.lastExportedText = rtfText
    }

    /// iOS `RichTextEditorRepresentable.applyBackground`와 같은 역할이지만,
    /// ⚠️ mac 쪽은 두 색 모두 nil일 때 "아무것도 건드리지 않는다"가 iOS와
    /// 다른 점이다 — `NSTextView`는 기본값 자체가 `drawsBackground = true` +
    /// `backgroundColor = .textBackgroundColor`(적당히 흰/검 자동 전환)라서,
    /// iOS의 `.clear` 기본값과 달리 여기서 명시적으로 끌 이유가 없다. 실제로
    /// 처음 이 필드를 추가했을 때 무조건 `drawsBackground = false`로 꺼버려서
    /// 개요/내 메모 화면의 에디터가 투명해지는 회귀가 있었다 — 그래서 "색을
    /// 지정한 화면에서만 덮어쓴다"로 고쳤다.
    private func applyBackground(to textView: NSTextView) {
        guard let color = isEditable ? editingBackgroundColor : readOnlyBackgroundColor else { return }
        textView.drawsBackground = true
        textView.backgroundColor = color
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextStorageDelegate {
        var parent: RichTextEditorRepresentable
        var lastExportedText: String = ""
        var isProcessing = false
        var isLoadingExternally = false
        weak var textView: NSTextView?

        init(_ parent: RichTextEditorRepresentable) { self.parent = parent }

        // [2026-08-12 수정] 빌드 에러 — AppKit(macOS)의 `NSTextStorageDelegate`는
        // iOS와 달리 아직 `NSTextStorage.EditActions`(중첩 타입)가 아니라 예전
        // 전역 typealias `NSTextStorageEditActions`를 그대로 쓴다. 위 iOS 쪽
        // `Coordinator`(489행)는 `NSTextStorage.EditActions`가 맞고, 이 macOS
        // 쪽만 다르다 — 두 플랫폼의 이름이 서로 다르게 갈린 경우라 하나로
        // 통일할 수 없다.
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
                self.lastExportedText = rtf
                self.parent.rtfText = rtf
                self.parent.plainText = plain
                self.isProcessing = false
            }
        }
    }
}
#endif
