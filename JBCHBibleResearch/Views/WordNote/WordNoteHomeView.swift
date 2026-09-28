//
//  WordNoteHomeView.swift
//  JBCHBibleResearch
//
//  [2026-08-13 신설] 사용자 요청 — "왼쪽 사이드바 [개인 묵상], [말씀 요약] 통합할 것 :
//  메뉴명 - [말씀 노트] / 카테고리로 분류할 것 : [개인 묵상], [말씀 요약] / 말씀 노트
//  메뉴 탭하면 리스트에서 리스트 항목 앞에 카테고리를 표시할 것 / 리스트 위에 검색창
//  옆에 카테고리 picker를 주어 선택된 카테고리 별로 조회할 수 있도록 할것."
//
//  기존 `MemoHomeView.swift`(개인 묵상, `UserMemo` 기반)와 `WordSummaryHomeView.swift`
//  (말씀 요약, `VerseSummary` 기반)를 이 화면 하나로 대체한다 — 두 파일은 삭제했다.
//  두 모델은 스키마가 다르므로(폴더/태그는 `UserMemo`에만 있음) 데이터 자체를 합치지
//  않고, `WordNoteItem`(이 파일 하단)이라는 얇은 열거형 래퍼로 둘을 한 목록에 섞어
//  보여주기만 한다 — 실제 편집은 기존 `MemoDetailView`/`WordSummaryEditorView`를
//  그대로 재사용한다(두 화면 모두 성경 조회 화면의 확대보기 액션바에서 "contextual"로
//  여는 경로가 그대로 남아 있어, 이 화면과 무관하게 계속 동작한다).
//
//  ⚠️ [범위 축소, 명확히 플래그] 기존 `MemoHomeView`엔 폴더별 목록 필터 메뉴가
//  있었지만, 이번 요청은 "검색창 옆 카테고리 picker" 하나만 명시했다 — 폴더 필터
//  UI는 이 통합 목록에서 뺐다(오버엔지니어링 방지). 폴더 배정 자체는 여전히
//  `MemoDetailView`의 폴더 메뉴에서 가능하고, ⌘⇧N "새 폴더" 메뉴 커맨드도 이 화면이
//  그대로 이어받아 동작한다(알림창만 남기고 필터 메뉴 UI는 없앤 것).
//
//  [2026-09-12 대개편] 사용자가 검토·승인한 "말씀 노트 레이아웃 개선안" HTML
//  목업(아이폰/아이패드/맥 시뮬레이션, "연구문서 서가" 목업과 통일한 spine 색선
//  포함 — 세션 아티팩트로 공유)을 그대로 반영한다. 착수 전 실제 코드를 먼저
//  확인해 목업이 못 봤던 두 가지 충돌을 발견했고, 사용자에게 직접 확인받아
//  범위를 정했다(추측으로 정하지 않음):
//    1) 목업의 "최근 작성·즐겨찾기"를 이 화면 분류 트리에도 넣을지 물었다 —
//       이미 앱 왼쪽 사이드바(`SidebarNavigationView.swift`)에 연구문서·개인
//       묵상·말씀 요약을 모두 아우르는 "고정됨/오늘/어제/그저께/이번 주/이전"
//       전역 목록이 있어(그 파일 493번째 줄 부근 "MARK: - 고정됨/최근" 참고),
//       사용자가 "빼고 노트 종류·성경별만"을 선택했다 — 그래서 아래 분류
//       트리(`categoryTreeColumn`)엔 최근·즐겨찾기가 없다(전역 사이드바 기능과
//       중복 방지).
//    2) 아이폰도 목업처럼 분류→목록→내용 3단계 push로 바꿀지 물었다 — 사용자가
//       "2단계 유지"를 선택했다. 그래서 아이폰(`isPhoneLayout == true`)은
//       기존 캡슐 필터 + 목록 → 내용 구조를 그대로 두고(`phoneContent`),
//       분류 트리·3열 레이아웃은 아이패드·맥(`isPhoneLayout == false`,
//       `splitTreeContent`)에만 적용한다.
//  이 범위 안에서 실제로 반영한 것:
//    · 아이패드·맥: 기존 2단(목록·내용) → 3단(분류 트리·목록·내용). 분류
//      트리는 "노트 종류"(기존 캡슐과 같은 3항목: 전체/개인 묵상/말씀 요약)와
//      "성경별"(신설 — 구약/신약은 지어낸 분류가 아니라 `Book.testament`,
//      `BookChapterPicker.swift`가 이미 같은 방식으로 쓰는 기존 필드다)로
//      구성된다. 노트가 하나도 없는 책/성경 전체는 목록에서 뺀다(66권을
//      항상 다 보여주면 대부분 0건이라 오히려 붐빈다 — 이 파일 상단
//      "오버엔지니어링 방지" 원칙과 같은 결).
//    · 행 정보 위계 재배열(`WordNoteRowView.swift` 참고)과 spine(책등) 왼쪽
//      색선 — 두 파일이 정확히 같은 색을 쓰도록 `WordNoteCategory.spineColor`
//      로 매핑을 한 곳에 모았다(기존엔 `WordNoteRowView`에만 있었음).
//    · "항목을 선택하세요" 빈 화면 → 최근 노트 카드(`WordNoteRecentEmptyState`).
//      목록 로딩(`WordNoteListContent.reload()`/`mergedItems`)은 건드리지
//      않고, `WordNoteSplitContent`에서 "가장 최근 항목 1개"만 별도로 가볍게
//      (`fetchLimit = 1`) 조회한다.
//    · 목업에도 있었던 "연구문서 서가" 목업과의 폰트(KMU 성곡체 실제 파일
//      로딩)·기기 베젤 통일은 이 화면(SwiftUI 코드)엔 애초에 해당되지 않는
//      항목이라(그건 HTML 목업 두 개 사이의 통일성 문제) 여기선 다루지 않는다.
//

import SwiftUI
import SwiftData
import BibleResearchModels
#if os(iOS)
import UIKit
#endif

/// 통합 목록의 카테고리 — 사용자 요청 문구를 그대로 라벨로 쓴다.
enum WordNoteCategory: String, CaseIterable, Identifiable {
    case personalMemo = "개인 묵상"
    case verseSummary = "말씀 요약"

    var id: String { rawValue }

    /// [2026-09-12 추가] 목업의 spine(책등) 왼쪽 색선·카테고리 배지가 이제
    /// 두 곳(`WordNoteRowView`의 배지·spine, 이 파일의 분류 트리·최근 노트
    /// 카드)에서 정확히 같은 색을 써야 해서, 원래 `WordNoteRowView`에만
    /// private으로 있던 매핑을 이 enum으로 옮겨 단일 출처로 만들었다. 색
    /// 배정 자체는 바뀌지 않았다 — 가죽 표지(개인 손글씨 느낌) → 개인 묵상,
    /// 서재 금박(이 화면 "새 항목" 버튼과 같은 대표색) → 말씀 요약.
    var spineColor: Color {
        switch self {
        case .personalMemo: return JBCHCategoryPalette.wood
        case .verseSummary: return JBCHCategoryPalette.gold
        }
    }
}

/// 검색창 옆 카테고리 picker의 선택값 — "전체"까지 포함해야 해서 `WordNoteCategory`
/// 자체가 아니라 한 단계 감싼 별도 enum을 쓴다.
/// [2026-09-12 추가] `.book(bookId:)` — 아이패드·맥 전용 분류 트리의 "성경별"
/// 필터(`WordNoteListContent.categoryTreeColumn` 참고). 아이폰은 여전히
/// `.all`/`.category`만 쓰는 캡슐 필터라(이 화면 상단 새 주석의 결정 2번),
/// 이 case를 몰라도 기존 동작에 영향이 없다.
enum WordNoteCategoryFilter: Hashable {
    case all
    case category(WordNoteCategory)
    case book(bookId: Int)
}

/// `UserMemo`/`VerseSummary` 두 모델을 한 목록에 섞어 보여주기 위한 얇은 래퍼.
/// 데이터를 복제하지 않고 원본 모델 인스턴스를 그대로 들고 있는다.
enum WordNoteItem: Identifiable {
    case memo(UserMemo)
    case summary(VerseSummary)

    var id: String {
        switch self {
        case .memo(let memo): return "memo-\(memo.id.uuidString)"
        case .summary(let summary): return "summary-\(summary.id.uuidString)"
        }
    }

    var category: WordNoteCategory {
        switch self {
        case .memo: return .personalMemo
        case .summary: return .verseSummary
        }
    }

    /// 목록 정렬 기준 — 기존 각 화면의 정렬 원칙을 그대로 유지한다: 개인 묵상은
    /// "마지막 수정순"(`updatedAt`), 말씀 요약은 "쓴 순서"(`createdAt`, 저널 성격 —
    /// `WordSummaryHomeView.swift` 옛 상단 주석 참고).
    var sortDate: Date {
        switch self {
        case .memo(let memo): return memo.updatedAt
        case .summary(let summary): return summary.createdAt
        }
    }

    var contentText: String {
        switch self {
        case .memo(let memo): return memo.contentText
        case .summary(let summary): return summary.contentText
        }
    }

    var pendingIndexRefresh: Bool {
        switch self {
        case .memo(let memo): return memo.pendingIndexRefresh
        case .summary(let summary): return summary.pendingIndexRefresh
        }
    }

    var bookId: Int {
        switch self {
        case .memo(let memo): return memo.bookId
        case .summary(let summary): return summary.bookId
        }
    }

    var chapter: Int {
        switch self {
        case .memo(let memo): return memo.chapter
        case .summary(let summary): return summary.chapter
        }
    }

    var verse: Int? {
        switch self {
        case .memo(let memo): return memo.verse
        case .summary(let summary): return summary.verse
        }
    }

    /// [2026-08-18 추가] 사용자 요청 — "사이드바 메뉴 밑으로 클로드 앱처럼 기능을
    /// 추가할 것. 고정됨."
    var isPinned: Bool {
        switch self {
        case .memo(let memo): return memo.isPinned
        case .summary(let summary): return summary.isPinned
        }
    }

    /// [2026-09-12 추가] "말씀 노트 레이아웃" 목업 3·4항 반영 — 목록 행
    /// (`WordNoteRowView`)과 상세 패널 빈 상태의 "최근 노트" 카드
    /// (`WordNoteRecentEmptyState`, 이 파일 하단) 둘 다 같은 제목/좌표/
    /// 미리보기/날짜 텍스트를 보여줘야 해서, 원래 `WordNoteRowView`에만
    /// private으로 있던 이 네 계산 프로퍼티를 이 타입으로 옮겨 두 곳이
    /// 정확히 같은 로직·같은 값을 쓰게 한다 — 값 자체는 바뀌지 않았다.
    var previewTitle: String {
        let trimmed = contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let emptyLabel = category == .personalMemo ? "새 메모" : "새 말씀 요약"
        guard !trimmed.isEmpty else { return emptyLabel }
        let firstLine = trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? trimmed
        return String(firstLine.prefix(40))
    }

    /// 목업의 "본문 미리보기" 줄 — 새 데이터 필드가 아니라 `previewTitle`
    /// (첫 줄)이 쓰고 남은 본문 나머지를 그대로 잘라 보여준다. 첫 줄이 본문
    /// 전부였으면(짧은 메모 등) 보여줄 나머지가 없으므로 nil.
    var previewSnippet: String? {
        let trimmed = contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: "\n", maxSplits: 1)
        guard parts.count > 1 else { return nil }
        let rest = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.isEmpty else { return nil }
        return String(rest.prefix(80))
    }

    var coordinateLabel: String {
        let bookName = BooksProvider.shared.book(id: bookId)?.nameKo ?? "\(bookId)권"
        var label = "\(bookName) \(chapter)장"
        if let verse {
            label += " \(verse)절"
        }
        return label
    }

    /// [2026-08-14 변경] 사용자 요청 — "리스트의 개인 묵상에도 작성일자를
    /// 표시해줄 것." 말씀 요약은 "쓴 날짜"(createdAt, 저널 성격), 개인 묵상은
    /// "마지막 수정일"(updatedAt, 절당 하나를 계속 고쳐 쓰는 성격이라 생성일
    /// 보다 수정일이 더 의미 있다 — 위 `sortDate`가 이미 같은 기준으로
    /// 정렬하는 것과 일관됨)을 쓴다.
    var dateLabel: String? {
        let date: Date
        switch self {
        case .memo(let memo): date = memo.updatedAt
        case .summary(let summary): date = summary.createdAt
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
}

/// [2026-09-09 신설] 사용자 보고 — "말씀 노트의 상단과 리스트의 각 행은 왜
/// 흰색이지?" "상단"은 이 화면의 리스트(이미 테마 적용됨 — 아래 `settings`
/// 프로퍼티/`.background` 참고)가 아니라, 그 위 진짜 iOS 시스템 내비게이션
/// 바(`.navigationTitle("말씀 노트")` + `.toolbar`)다 — `BibleReadingView.swift`의
/// `ThemedNavigationBarBackgroundModifier`와 완전히 같은 이유·같은 패턴이라
/// 그대로 옮겨 왔다(테마 배경을 고르지 않았으면 아무것도 바꾸지 않는다).
private struct ThemedNavigationBarBackgroundModifier: ViewModifier {
    let color: Color?

    // [2026-09-10 추가] 위 `.toolbarBackground`가 요구하는 짝 API —
    // `@Environment(\.self)`로 현재 환경을 받아 `Color.resolve(in:)`에
    // 넘긴다(`Color+Hex.swift`의 `hexString(in:)`이 이미 쓰는 것과 같은,
    // 확인된 패턴). `Color(hex:)`로 만든 고정 RGB 색이라 라이트/다크 모드와
    // 무관하게 항상 같은 값이 나온다.
    @Environment(\.self) private var environment

    func body(content: Content) -> some View {
        // [2026-09-10 수정, 컴파일 에러 fix] 사용자 보고 — Xcode 에러
        // "'navigationBar' is unavailable in macOS"(WordNoteHomeView.swift
        // 134:49/135:52). `ToolbarPlacement.navigationBar`는 iOS/iPadOS/
        // tvOS/Mac Catalyst 전용이라, 이 앱의 macOS(순수 AppKit 창) 타깃에는
        // 그 심볼 자체가 없다 — 이 파일들 주석이 애초에 "iOS 16+에 공식
        // 제공하는 API"라고 적어 뒀던 전제를 `#if os(iOS)`로 실제 코드에도
        // 반영한다. macOS는 원래도 이 모디파이어로 바꿀 표준 API가 없다고
        // 판단해 채택한 적이 없으므로(각 파일 상단 주석 참고), macOS
        // 분기는 `color` 값과 무관하게 항상 아무 효과 없이 통과시킨다.
        #if os(iOS)
        if let color {
            content
                .toolbarBackground(color, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                // [2026-09-10 추가, 버그 수정 시도] 사용자 보고 — "테마를
                // 바꾸면 [성경] 화면의 상단(타이틀·책갈피 리스트·책갈피
                // 설정·히스토리·인스펙터 창·번역본 버튼 영역)이 사라짐."
                // 이 세션엔 실기기 재현이 불가능해 100% 확정은 못 했지만,
                // 코드로 확인되는 원인은 이렇다 — 지금까지 이 화면들은
                // `.toolbarBackground(_:for:)`만 쓰고 Apple 공식 문서가
                // 커스텀 배경색과 함께 쓰길 권하는 짝 API인
                // `.toolbarColorScheme(_:for:)`은 지정하지 않았다. 이게
                // 없으면 iOS는 내비게이션 바가 실제로 얼마나 밝은/어두운
                // 배경인지가 아니라 "앱 전체의 현재 라이트/다크 모드"만
                // 보고 시스템 제공 바 아이템의 기본 색을 정한다 — 예를 들어
                // 라이트 모드에서 어두운 테마(밤빛 서재 등, 이 앱의 실제
                // 프리셋 2개 중 1개가 어두운 배경 — `BibleSlideColorTheme.
                // swift` 참고)를 고르면 어두운 배경 위에 여전히 라이트
                // 모드용 짙은 색 아이템이 남아 거의 안 보이게 될 수 있다.
                // 배경색의 WCAG 2.1 상대 휘도(`BibleSlideColorTheme.swift`
                // 상단 주석이 2개 프리셋의 대비를 검증할 때 이미 수동으로
                // 쓴 것과 같은 공식)를 계산해 어두우면 `.dark`(밝은 아이템),
                // 밝으면 `.light`(어두운 아이템)를 명시적으로 지정한다.
                // 이 수정으로도 증상이 그대로 재현되면(예: 매번이 아니라
                // 설정 시트를 닫는 특정 시점에만 재현되는 등) 별도 원인이
                // 더 있다는 뜻이니, 재현되는 정확한 상황을 알려주시면 추가로
                // 조사한다.
                .toolbarColorScheme(Self.isDarkBackground(color, in: environment) ? .dark : .light, for: .navigationBar)
        } else {
            content
        }
        #else
        content
        #endif
    }

    private static func isDarkBackground(_ color: Color, in environment: EnvironmentValues) -> Bool {
        let resolved = color.resolve(in: environment)
        let luminance = 0.2126 * Double(resolved.red) + 0.7152 * Double(resolved.green) + 0.0722 * Double(resolved.blue)
        return luminance < 0.5
    }
}

struct WordNoteHomeView: View {
    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    var body: some View {
        if isPhone {
            WordNoteListContent(isPhoneLayout: true, selectedItem: nil)
        } else {
            WordNoteSplitContent()
        }
    }
}

private struct WordNoteSplitContent: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedItem: WordNoteItem?

    /// [2026-09-12 추가] "말씀 노트 레이아웃" 목업 4항 — 빈 상세 화면의
    /// "최근 노트" 카드용. `WordNoteListContent` 내부 상태(`allMemos`/
    /// `allSummaries`, 목록 전체를 위해 로드됨)를 끌어올리는 대신, "가장
    /// 최근 항목 1개"만 별도로 가볍게(`fetchLimit = 1`) 조회한다 — 목록
    /// 자체의 로딩·정렬·필터링 로직(`WordNoteListContent.reload()`/
    /// `mergedItems`)은 그대로 둔다.
    @State private var mostRecentItem: WordNoteItem?

    /// [2026-09-12 추가] 사용자 보고 — "말씀노트-오른쪽 '항목을
    /// 선택하세요' 흰 영역 -> 테마대로." 이 struct는 지금까지 테마 대상에서
    /// 완전히 빠져 있었다 — 다른 화면들과 같은 읽기 전용 접근 패턴.
    private var settings: UserSettingsStore { .shared }

    var body: some View {
        HStack(spacing: 0) {
            // [2026-09-12 수정] "말씀 노트 레이아웃" 목업 5항 — 분류 트리
            // 열이 새로 생겨(아래 `WordNoteListContent.splitTreeContent`)
            // 이 struct가 감싸는 폭 자체를 넓혔다. 기존 260~380(목록 하나
            // 만의 폭)을 분류 트리(약 200)+목록(약 300)을 합친 폭으로
            // 늘렸을 뿐, 내부 목록 폭 비율은 그대로다.
            WordNoteListContent(isPhoneLayout: false, selectedItem: $selectedItem)
                .frame(minWidth: 460, idealWidth: 560, maxWidth: 720)

            Divider()

            Group {
                if let selectedItem {
                    destinationView(for: selectedItem)
                        .id(selectedItem.id)
                } else {
                    // [2026-09-12 수정] 목업 4항 — "항목을 선택하세요" 한 줄
                    // 대신 최근 노트 카드를 보여주는 미니멀 Empty State로
                    // 대체.
                    WordNoteRecentEmptyState(recentItem: mostRecentItem) { item in
                        selectedItem = item
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(settings.bibleBackgroundColor ?? Color.clear)
                }
            }
        }
        // [2026-08-21 추가] 사용자 요청("아이패드 수정사항") — "말씀노트 리스트에
        // 항목 탭시 - 왼쪽 사이드바 자동 숨김기능." `SidebarVisibilityRequest`
        // (Services/SidebarVisibilityRequest.swift)는 `BibleReadingContentView`가
        // "말씀 요약" 편집기를 열 때 이미 쓰던 것과 같은 싱글턴이다 — 여기서도
        // 같은 계약(열 때 hide, 닫을 때/화면을 떠날 때 restore)을 그대로
        // 재사용한다. `WordNoteItem`은 `Equatable`을 선언하지 않아
        // `.onChange(of: selectedItem)`을 바로 못 쓰므로, 이미 있는 `id: String`
        // (Equatable)로 비교한다 — 타입에 새 프로토콜 준수를 추가하는 대신
        // 가장 적은 변경으로 끝낸다. macOS는 사이드바를 접을 만큼 화면이 좁지
        // 않고(이 항목만 "(맥OS, iOS 공통)" 표기가 없다 — 사용자가 이 화면 하단
        // "성경 매칭 수정 영역 삭제"는 명시적으로 공통 표기했다는 점과 대비된다),
        // 기존 macOS 동작을 건드리지 않기 위해 iOS(아이폰/아이패드)로만 제한한다.
        #if os(iOS)
        .onChange(of: selectedItem?.id) { oldValue, newValue in
            if newValue != nil && oldValue == nil {
                SidebarVisibilityRequest.shared.requestHide()
            } else if newValue == nil && oldValue != nil {
                SidebarVisibilityRequest.shared.requestRestore()
            }
        }
        .onDisappear {
            guard selectedItem != nil else { return }
            SidebarVisibilityRequest.shared.requestRestore()
        }
        #endif
        // [2026-09-12 추가] 위 `mostRecentItem` 주석 참고 — 처음 뜰 때, 그리고
        // 선택을 해제해 Empty State가 다시 보일 때마다 최신 상태로 새로
        // 조회한다(macOS·iOS 공통이라 위 `#if os(iOS)` 블록 밖에 둔다).
        .onAppear { reloadMostRecent() }
        .onChange(of: selectedItem?.id) { _, newValue in
            if newValue == nil { reloadMostRecent() }
        }
    }

    private func reloadMostRecent() {
        var memoDescriptor = FetchDescriptor<UserMemo>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        memoDescriptor.fetchLimit = 1
        var summaryDescriptor = FetchDescriptor<VerseSummary>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        summaryDescriptor.fetchLimit = 1
        let latestMemo = (try? modelContext.fetch(memoDescriptor))?.first
        let latestSummary = (try? modelContext.fetch(summaryDescriptor))?.first
        switch (latestMemo, latestSummary) {
        case let (memo?, summary?):
            mostRecentItem = memo.updatedAt >= summary.createdAt ? .memo(memo) : .summary(summary)
        case let (memo?, nil):
            mostRecentItem = .memo(memo)
        case let (nil, summary?):
            mostRecentItem = .summary(summary)
        case (nil, nil):
            mostRecentItem = nil
        }
    }
}

/// [2026-09-12 신설] "말씀 노트 레이아웃" 목업 4항 — 아이패드·맥 상세 패널이
/// 비어 있을 때(아무 노트도 선택 안 함) "항목을 선택하세요" 한 줄 대신
/// 보여주는 최근 노트 카드. 작성된 노트가 하나도 없으면(카드에 보여줄 게
/// 없음, `recentItem == nil`) 카드 없이 안내 문구만 보여준다 — 없는 데이터를
/// 지어내 채우지 않는다.
private struct WordNoteRecentEmptyState: View {
    let recentItem: WordNoteItem?
    let onSelect: (WordNoteItem) -> Void

    private var settings: UserSettingsStore { .shared }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("아직 선택된 노트가 없습니다")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(settings.bibleTextColor?.opacity(0.7) ?? Color.secondary)
            if let recentItem {
                Button {
                    onSelect(recentItem)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("최근 노트")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(settings.bibleTextColor?.opacity(0.55) ?? .secondary)
                        Text(recentItem.previewTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(settings.bibleTextColor ?? .primary)
                            .lineLimit(1)
                        Text(recentItem.coordinateLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(recentItem.category.spineColor)
                        if let dateLabel = recentItem.dateLabel {
                            Text(dateLabel)
                                .font(.caption2)
                                .foregroundStyle(settings.bibleTextColor?.opacity(0.5) ?? .secondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: 280, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(settings.bibleTextColor?.opacity(0.05) ?? Color.secondary.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(settings.bibleTextColor?.opacity(0.15) ?? Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@ViewBuilder
private func destinationView(for item: WordNoteItem) -> some View {
    switch item {
    case .memo(let memo):
        // [2026-08-21 수정] 사용자 요청("아이패드 수정사항", 맥OS·iOS 공통) —
        // "말씀노트 리스트에 항목 탭 - 에디터 화면의 상단 성경 매칭수정 영역은
        // 삭제할 것." 예전엔 기본값 `.standalone`이 그대로 쓰여 좌표 편집
        // 헤더(BookChapterPicker+절 Stepper)가 보였다 —
        // `MemoPresentationContext.wordNoteList`(MemoDetailView.swift 참고)로
        // 바꿔 읽기전용 좌표 라벨만 보이게 한다.
        MemoDetailView(memo: memo, presentationContext: .wordNoteList)
    case .summary(let summary):
        // [2026-08-27 변경] 사용자 보고 — "iOS 아이폰 - 말씀노트 수정사항: 화면
        // 영역이 기기 가로폭보다 커서 잘림." 바로 위 `.memo` 케이스가 이미
        // `.wordNoteList`를 쓰는 것과 같은 이유로(그 케이스 주석 참고)
        // `.standalone` 대신 `.wordNoteList`로 바꾼다 — `WordSummaryEditorView.
        // WordSummaryPresentationContext.wordNoteList` 상단 주석 참고.
        WordSummaryEditorView(summary: summary, presentationContext: .wordNoteList)
    }
}

private struct WordNoteListContent: View {
    @Environment(\.modelContext) private var modelContext

    let isPhoneLayout: Bool
    var selectedItem: Binding<WordNoteItem?>?

    @State private var allMemos: [UserMemo] = []
    @State private var allSummaries: [VerseSummary] = []
    @State private var folders: [MemoFolder] = []
    @State private var categoryFilter: WordNoteCategoryFilter = .all
    @State private var searchText: String = ""
    @State private var isNewFolderPresented = false
    @State private var newFolderName = ""
    /// [2026-09-12 추가] 아이패드·맥 전용 분류 트리(`categoryTreeColumn`)의
    /// "성경별" 구약/신약 `DisclosureGroup` 펼침 상태. 기본은 둘 다 접힌
    /// 상태 — 노트가 있는 책만 추려도(위 `booksWithNotes`) 처음부터 펼쳐
    /// 두면 "노트 종류" 위에 목록이 바로 붐빌 수 있어, 필요할 때 펼쳐 보게
    /// 했다.
    @State private var expandedTestaments: Set<Book.Testament> = []
    /// [2026-09-09 추가] 사용자 요청 — "테마를 적용하면 배경색과 글자색을
    /// 전체적으로 적용할 수 있는가(... 말씀노트 화면 배경색...)." 지금까지
    /// 이 화면은 `List`(아래 `body`)가 시스템 기본 배경을 그대로 썼다 —
    /// `TranslationColumnView`/`BibleReadingView.BibleReadingContentView`와
    /// 같은 읽기 전용 접근 패턴을 그대로 가져왔다.
    private var settings: UserSettingsStore { .shared }

    private var mergedItems: [WordNoteItem] {
        let items: [WordNoteItem] = allMemos.map { .memo($0) } + allSummaries.map { .summary($0) }
        return items.sorted { $0.sortDate > $1.sortDate }
    }

    private var filteredItems: [WordNoteItem] {
        var result = mergedItems
        // [2026-09-12 수정] `.book(bookId:)` 케이스 추가 — 아이패드·맥 전용
        // 분류 트리의 "성경별" 필터(아래 `categoryTreeColumn`). 기존
        // `.category` 분기는 그대로다.
        switch categoryFilter {
        case .all:
            break
        case .category(let category):
            result = result.filter { $0.category == category }
        case .book(let bookId):
            result = result.filter { $0.bookId == bookId }
        }
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            result = result.filter { $0.contentText.localizedCaseInsensitiveContains(trimmed) }
        }
        return result
    }

    /// [2026-09-12 신설] 분류 트리 각 행의 개수 배지(`treeRow`)와 목록 헤더
    /// (`listHeader`)가 같이 쓴다 — 검색어는 제외하고(트리는 "분류" 기준
    /// 개수를 보여줘야지, 지금 검색창에 뭘 입력 중인지에 따라 숫자가 바뀌면
    /// 오히려 헷갈린다) `mergedItems` 기준으로 센다.
    private func count(for filter: WordNoteCategoryFilter) -> Int {
        switch filter {
        case .all: return mergedItems.count
        case .category(let category): return mergedItems.filter { $0.category == category }.count
        case .book(let bookId): return mergedItems.filter { $0.bookId == bookId }.count
        }
    }

    /// [2026-09-12 신설] 목록 헤더(`listHeader`)용 — 지금 선택된 분류의 제목.
    private var filterTitle: String {
        switch categoryFilter {
        case .all: return "전체"
        case .category(let category): return category.rawValue
        case .book(let bookId): return BooksProvider.shared.book(id: bookId)?.nameKo ?? "\(bookId)권"
        }
    }

    /// [2026-09-12 신설] "성경별" 트리(아래 `testamentDisclosure`)에 보여줄
    /// 책 목록 — 구약/신약 전체 66권을 항상 다 보여주지 않고, 실제로 노트가
    /// 하나라도 있는 책만 추린다. 66권을 다 보여주면 대부분 0건이라 오히려
    /// 붐빈다(이 파일 상단 "오버엔지니어링 방지" 원칙과 같은 결) — 구약/신약
    /// 자체는 지어낸 분류가 아니라 `Book.testament`(이미 `BookChapterPicker.
    /// swift`가 책 그리드에서 구약/신약을 나눌 때 쓰는 것과 같은 기존 필드)를
    /// 그대로 쓴다.
    private func booksWithNotes(in testament: Book.Testament) -> [Book] {
        let bookIdsWithNotes = Set(mergedItems.map { $0.bookId })
        return BooksProvider.shared.books.filter {
            $0.testament == testament && bookIdsWithNotes.contains($0.bookId)
        }
    }

    /// [2026-09-10 신설, 같은 날 재수정] 사용자 요청 — 카테고리 캡슐을
    /// "퍼스널 컬러" 디자인 가이드(아이콘에서 뽑은 서재 금박/밤빛 남색
    /// 팔레트 — 이 세션에서 아티팩트로 공유받은 문서, 03절 "번역본 선택
    /// 팝오버" 칩 목업이 정확히 이 자리와 같은 종류의 컴포넌트다)의 칩
    /// (chip) 컴포넌트 스타일로 다시 그렸다 — 원본 CSS `.chip`/`.chip.on`:
    /// 항상 1.4px 테두리가 있고, 선택 시엔 배경 전체를 채우는 대신 accent
    /// 색 테두리 + accent 12% 틴트 배경 + accent 글자색(굵게)으로 표시한다.
    /// accent는 이미 `AccentColor.colorset`에 그 가이드의 색(라이트
    /// #B8863C/다크 #D4AD64)이 들어 있는 `Color("AccentColor")`를 그대로 써서,
    /// 새 hex를 여기 하드코딩하지 않아도 라이트/다크 모두 가이드 색이
    /// 자동으로 맞는다. 선택되지 않은 상태의 테두리/글자색만 계속 이 화면의
    /// 테마(`settings.bibleTextColor`)를 따르게 했다 — 가이드 04절("퍼스널
    /// 컬러는 사용자가 고른 테마 위에 얹는 기본값일 뿐, 테마를 덮어쓰지
    /// 않는다") 원칙대로, "선택됨" 강조 신호에만 퍼스널 컬러를 쓰고 캡슐의
    /// 평상시 색은 계속 테마를 따른다. `WordNoteCategoryFilter`가 이미
    /// `Hashable`(=Equatable)이라 `==`로 바로 선택 여부를 비교한다.
    private func categoryCapsuleButton(_ filter: WordNoteCategoryFilter, title: String) -> some View {
        let isSelected = categoryFilter == filter
        // [2026-09-10 추가, 빌드 에러 fix] Xcode 에러 — "The compiler is
        // unable to type-check this expression in reasonable time"
        // (이 함수 본문, 정확히 `.foregroundStyle`/`.background`/`.overlay`가
        // 삼항 연산자 + 옵셔널 체이닝(`?.opacity`) + `??` 기본값을 모디파이어
        // 체인 안에 그대로 인라인해서 생긴 문제 — 타입 추론기가 오버로드
        // 조합을 지수적으로 탐색하게 되는, Swift에서 자주 보고되는 알려진
        // 컴파일러 한계다). 에러 메시지가 제시하는 표준 해법대로 각 색상
        // 계산을 명시적 타입(`Color`)의 별도 `let`으로 뽑아 타입 추론기가
        // 각각 독립적으로 짧게 풀 수 있게 나눴다 — 계산 값 자체는 바뀌지
        // 않았다.
        let textColor: Color = isSelected ? Color("AccentColor") : (settings.bibleTextColor?.opacity(0.55) ?? Color.secondary)
        let fillColor: Color = isSelected ? Color("AccentColor").opacity(0.12) : Color.clear
        let borderColor: Color = isSelected ? Color("AccentColor") : (settings.bibleTextColor?.opacity(0.35) ?? Color.secondary.opacity(0.35))
        return Button {
            categoryFilter = filter
        } label: {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .foregroundStyle(textColor)
                .background(
                    Capsule().fill(fillColor)
                )
                .overlay(
                    Capsule().strokeBorder(borderColor, lineWidth: 1.4)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    /// [2026-09-12 신설] 사용자 요청 — "말씀노트 화면에서 캡슐 탭 밑에
    /// 컨텐츠가 시작되는 부분에 연구문서와 통합검색에 사용된 이미지
    /// 구분선을 사용할 것." `SearchView.menuContentOrnamentalDivider`(통합
    /// 검색, 원본)/`DocumentsHomeView.searchContentOrnamentalDivider`(연구
    /// 문서, 같은 시각 언어를 옮겨온 버전)와 완전히 같은 모양(가로선-
    /// `sparkle`-가로선, wood 톤) — 두 프로퍼티 다 각자 파일에 private이라
    /// 직접 재사용은 못 하고 그대로 옮겨 적는다. 이 자리는 `DocumentsHomeView`
    /// 쪽(List 밖 평범한 VStack 안)과 구조가 같아 `.listRowSeparator`/
    /// `.listRowBackground`가 없는 그 버전을 따른다.
    private var wordNoteContentOrnamentalDivider: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(JBCHCategoryPalette.wood.opacity(0.3))
                .frame(height: 1)
            Image(systemName: "sparkle")
                .font(.system(size: 11))
                .foregroundStyle(settings.bibleTextColor?.opacity(0.45) ?? Color.secondary)
            Rectangle()
                .fill(JBCHCategoryPalette.wood.opacity(0.3))
                .frame(height: 1)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    // MARK: - 분류 트리 (아이패드·맥 전용, 2026-09-12 신설)
    //
    // "말씀 노트 레이아웃" 목업 5항 — 아이패드·맥은 기존 2단(목록·내용)을
    // 3단(분류 트리·목록·내용)으로 바꾼다. 이 트리는 아이폰(`phoneContent`,
    // 위 캡슐 필터를 그대로 쓴다)에서는 쓰이지 않는다 — 이 화면 상단
    // "2026-09-12 대개편" 주석의 결정 2번 참고. "노트 종류"는 기존 캡슐과
    // 정확히 같은 3항목(전체/개인 묵상/말씀 요약)을 트리 행 스타일로 다시
    // 그린 것뿐이라 `categoryFilter` 상태·필터링 로직은 전혀 바뀌지 않았다.
    // "최근 작성·즐겨찾기"는 목업 원안엔 있었지만, 이미 앱 왼쪽 사이드바에
    // 전역 기능이 있어(결정 1번) 여기엔 넣지 않았다.

    private var categoryTreeColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text("노트 종류")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.55) ?? .secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 2)

                treeRow(.all, title: "전체", systemImage: "list.bullet", count: count(for: .all))
                ForEach(WordNoteCategory.allCases) { category in
                    treeRow(
                        .category(category), title: category.rawValue,
                        systemImage: category == .personalMemo ? "note.text" : "doc.text",
                        count: count(for: .category(category)), spine: category.spineColor
                    )
                }

                let oldTestamentBooks = booksWithNotes(in: .old)
                let newTestamentBooks = booksWithNotes(in: .new)
                if !oldTestamentBooks.isEmpty || !newTestamentBooks.isEmpty {
                    Divider().padding(.vertical, 8).padding(.horizontal, 14)
                    Text("성경별")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.55) ?? .secondary)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 2)
                    testamentDisclosure(title: "구약", testament: .old, books: oldTestamentBooks)
                    testamentDisclosure(title: "신약", testament: .new, books: newTestamentBooks)
                }
            }
            .padding(.bottom, 16)
        }
    }

    /// 분류 트리 행 하나(노트 종류/성경별 공용). `spine`이 있으면(노트
    /// 종류만 — 위 `categoryTreeColumn`) `WordNoteRowView`/`categoryBadge`와
    /// 같은 색으로 왼쪽에 색선을 그린다 — "연구문서 서가" 목업의 folder-card/
    /// shelf-row 왼쪽 색선과 통일한 시각 언어(그 목업·`WordNoteRowView.swift`
    /// 상단 주석 참고). 성경별 책 행은 대응되는 코드베이스 색이 없어 spine을
    /// 넣지 않았다(임의로 배정하지 않음).
    private func treeRow(
        _ filter: WordNoteCategoryFilter, title: String, systemImage: String, count: Int, spine: Color? = nil
    ) -> some View {
        let isSelected = categoryFilter == filter
        // [2026-09-10 추가, 빌드 에러 fix] 주석 참고(위 `categoryCapsuleButton`)
        // — 타입 추론 시간 초과를 피하려고 색 계산을 명시적 `Color` 상수로 분리.
        let textColor: Color = isSelected ? Color("AccentColor") : (settings.bibleTextColor ?? .primary)
        let iconColor: Color = isSelected ? Color("AccentColor") : (settings.bibleTextColor?.opacity(0.6) ?? .secondary)
        let fillColor: Color = isSelected ? Color("AccentColor").opacity(0.14) : Color.clear
        return Button {
            categoryFilter = filter
        } label: {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 13))
                    .foregroundStyle(iconColor)
                    .frame(width: 16)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.55) ?? .secondary)
                    .monospacedDigit()
            }
            .padding(.vertical, 7)
            .padding(.trailing, 10)
            .padding(.leading, 11)
            .background(fillColor, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(spine ?? Color.clear)
                    .frame(width: 3)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .padding(.horizontal, 6)
    }

    /// "성경별" 아래 구약/신약 한 그룹 — 노트가 있는 책이 없으면(빈 목록)
    /// 아무것도 그리지 않는다(호출부 `categoryTreeColumn`이 이미 구약·신약
    /// 둘 다 비었을 때 "성경별" 표제 자체를 숨기지만, 한쪽만 비었을 수도
    /// 있어 이 함수 자체도 한 번 더 확인한다).
    @ViewBuilder
    private func testamentDisclosure(title: String, testament: Book.Testament, books: [Book]) -> some View {
        if !books.isEmpty {
            DisclosureGroup(isExpanded: Binding(
                get: { expandedTestaments.contains(testament) },
                set: { isOn in
                    if isOn { expandedTestaments.insert(testament) } else { expandedTestaments.remove(testament) }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(books) { book in
                        treeRow(.book(bookId: book.bookId), title: book.nameKo, systemImage: "book.closed", count: count(for: .book(bookId: book.bookId)))
                    }
                }
                .padding(.leading, 10)
            } label: {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
            }
            .padding(.horizontal, 14)
            .tint(settings.bibleTextColor?.opacity(0.6) ?? .secondary)
        }
    }

    /// 목록 열 머리글(아이패드·맥 전용) — 지금 선택된 분류 제목 + 개수.
    /// 아이폰은 캡슐 자체가 이미 선택 상태를 보여줘 따로 두지 않는다.
    private var listHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(filterTitle)
                .font(.title3.weight(.bold))
                .foregroundStyle(settings.bibleTextColor ?? .primary)
                .lineLimit(1)
            Spacer()
            Text("\(filteredItems.count)개의 노트")
                .font(.caption)
                .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? .secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    /// 목록(`List`) 자체 — 기존 `body`에 있던 것을 그대로 옮겼다(동작 변경
    /// 없음). 아이폰(`phoneContent`)·아이패드·맥(`splitTreeContent`) 둘 다
    /// 이 프로퍼티 하나를 공유한다.
    private var wordNoteList: some View {
        List {
            ForEach(filteredItems) { item in
                rowContent(for: item)
            }
            .onDelete { offsets in
                guard isPhoneLayout else { return }
                deleteItems(at: offsets)
            }
        }
        .listStyle(.plain)
        // [2026-09-09 추가] 사용자 요청 — "테마를 적용하면 배경색과
        // 글자색을 전체적으로 적용할 수 있는가(... 말씀노트 화면
        // 배경색...)." `.plain` 스타일은 이미 개별 행마다 별도 카드
        // 배경이 없어(시스템 기본도 지금처럼 하나의 배경 위에 얇은
        // 구분선만 있는 모습이다), 리스트 자체 배경 하나만 바꾸면
        // 되고 각 행 배경을 따로 손볼 필요가 없다 — `scrollContentBackground
        // (.hidden)`으로 시스템 리스트 배경을 끄고, `TranslationColumnView`
        // 컬럼 배경과 똑같은 "nil이면 기존(시스템 기본) 그대로" 폴백으로
        // 교체한다.
        //
        // [2026-09-09 수정, 실기기 확인 후] "리스트 자체 배경 하나만
        // 바꾸면 되고 각 행 배경을 따로 손볼 필요가 없다"는 위 판단은
        // 틀렸다 — 실기기에서 각 행이 여전히 흰색이었다(위 `rowContent`
        // 의 `.listRowBackground(Color.clear)` 추가 참고, 원인은 그
        // 주석에 적었다).
        .scrollContentBackground(.hidden)
        .background(settings.bibleBackgroundColor ?? Color.clear)
        // [2026-09-10 추가] 사용자 보고 — "어두운 배경에서는 리스트의
        // 행을 구분하는 라인이 거의 안보임." 시스템 기본 구분선 색은
        // 라이트/다크 모드에만 맞춰져 있어, 이 리스트처럼 임의의 테마
        // 배경(`settings.bibleBackgroundColor`) 위에서는 배경과 거의
        // 구별되지 않을 수 있다 — 이미 배경과 대비되도록 골라 둔
        // `bibleTextColor`를 옅게(0.3) 써서 구분선도 항상 배경과
        // 대비되게 한다. 테마를 고르지 않았으면(nil) `nil`을 그대로
        // 넘겨 시스템 기본 구분선 색을 그대로 쓴다.
        .listRowSeparatorTint(JBCHCategoryPalette.wood.opacity(0.3))
        // [2026-09-09 추가] 위 `body` 상단 주석 참고 — `SearchView.swift`
        // 의 `.searchable(text:prompt:)`와 같은 패턴. 문구("검색")는 이
        // 화면이 원래 커스텀 텍스트필드에 쓰던 플레이스홀더를 그대로
        // 유지했다(통합검색의 "검색어 입력"과 다른 것은 의도적 — 이
        // 화면 고유의 짧은 문구를 바꿔 달라는 요청은 없었다).
        .searchable(text: $searchText, prompt: "검색")
    }

    /// 아이폰 전용 콘텐츠 — 기존 캡슐 필터 + 구분선 + 목록. 이 화면 상단
    /// "2026-09-12 대개편" 주석의 결정 2번대로 구조를 바꾸지 않았다.
    private var phoneContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                categoryCapsuleButton(.all, title: "전체")
                ForEach(WordNoteCategory.allCases) { category in
                    categoryCapsuleButton(.category(category), title: category.rawValue)
                }
            }
            .padding(4)
            .background(
                Capsule()
                    .fill(settings.bibleTextColor?.opacity(0.1) ?? Color.secondary.opacity(0.12))
            )
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)

            wordNoteContentOrnamentalDivider
            wordNoteList
        }
    }

    /// 아이패드·맥 전용 콘텐츠 — 분류 트리 | 목록. 상세(내용) 열은 이 view
    /// 바깥, `WordNoteSplitContent`가 그 옆에 나란히 그린다.
    private var splitTreeContent: some View {
        HStack(spacing: 0) {
            categoryTreeColumn
                .frame(width: 200)

            Divider()

            VStack(spacing: 0) {
                listHeader
                wordNoteContentOrnamentalDivider
                wordNoteList
            }
        }
    }

    var body: some View {
        // [2026-09-12 수정] 이 화면 상단 "2026-09-12 대개편" 주석 참고 —
        // 기존엔 이 자리에 캡슐 필터+목록이 (아이폰·아이패드·맥 구분 없이)
        // 그대로 인라인돼 있었다. 이제 아이폰은 그 구조를 그대로 유지하는
        // `phoneContent`, 아이패드·맥은 분류 트리가 추가된 `splitTreeContent`
        // 로 갈라진다 — `Group`으로 감싸 아래 `.navigationTitle`/`.toolbar`
        // 등 화면 전체에 걸리는 모디파이어는 이전과 동일하게 분기와 무관하게
        // 한 번만 적용되게 했다(동작 변경 없음, 배치만 정리).
        Group {
            if isPhoneLayout {
                phoneContent
            } else {
                splitTreeContent
            }
        }
        // [2026-09-09 추가] 위 검색창+카테고리 필터 줄은 이 `List` 바깥(이
        // `VStack` 안)이라 `List`의 `.background()`가 닿지 않는다 — 이
        // `VStack` 자신에도 같은 배경을 한 번 더 칠해 그 줄까지 포함한
        // 화면 전체가 테마색으로 이어지게 한다.
        .background(settings.bibleBackgroundColor ?? Color.clear)
        .navigationTitle("말씀 노트")
        // [2026-09-03 추가] 사용자 보고 — "아이폰 하단 메뉴 중 말씀 노트/문서
        // OCR/통합 검색/더보기는 상단 우측 아이콘과 그 밑 타이틀이 따로 있어
        // 아이콘 좌측 영역이 낭비됨." 이 화면은 탭 최상위라 뒤로가기 버튼은
        // 없지만, 기본(automatic) 표시 모드에서는 트레일링 툴바 아이콘만 있는
        // 좁은 줄 아래에 큰 제목을 별도 줄로 한 번 더 그려 그 아이콘 왼쪽 줄
        // 전체가 비어 낭비된다 — 이미 이 코드베이스 다른 화면(`SettingsView.swift`
        // 의 `SettingsHomeView`/`BibleReadingView`/`ChapterRelatedContentPanel`
        // 등)에서 같은 이유로 쓴 `.navigationBarTitleDisplayMode(.inline)`을
        // 그대로 재사용해 제목과 아이콘을 한 줄로 합친다(macOS엔 이 모디파이어
        // 자체가 없어 `#if os(iOS)`로 감싼다).
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // [2026-09-09 추가] 위 `ThemedNavigationBarBackgroundModifier` 주석
        // 참고 — 이 화면의 진짜 시스템 내비게이션 바 배경을 테마에 맞춘다.
        .modifier(ThemedNavigationBarBackgroundModifier(color: settings.bibleBackgroundColor))
        .onAppear {
            reload()
            // [2026-08-18 추가] 사이드바 "고정됨"/"최근" 섹션에서 이 항목을 골라
            // 들어왔을 수 있다 — `WordNoteSelectionRequest.swift` 상단 주석 참고.
            // `reload()`가 방금 끝나 `allMemos`/`allSummaries`가 채워진 뒤라야
            // 대상 UUID를 실제 항목으로 찾을 수 있어 이 순서로 둔다.
            applyPendingSelectionRequest()
        }
        // 이 화면이 이미 떠 있는 채로 사이드바에서 다시 다른 항목을 골랐을 때만
        // 쓰인다(처음 여는 경우는 위 `.onAppear`가 이미 처리).
        .onChange(of: WordNoteSelectionRequest.shared.requestedTarget) { _, _ in
            applyPendingSelectionRequest()
        }
        .toolbar {
            #if os(iOS)
            // [2026-09-10 추가] 사용자 보고 — "[성경] 화면을 제외한 기능의
            // 화면(말씀노트, 문서OCR, 통합검색)의 타이틀이 검은색으로
            // 고정되어있음." 이 화면은 지금까지 시스템 기본 `.navigationTitle`
            // 문구를 그대로 썼는데, 시스템 기본 타이틀 색은 지금 실제
            // 시스템 라이트/다크 모드만 따르지 이 앱이 내비게이션 바에
            // 입힌 임의의 테마 배경색은 전혀 모른다 — 그래서 어두운 테마
            // 배경 위에서도 라이트 모드 검정 글자 그대로 남아 있었다.
            // `BibleReadingView.swift`의 `.principal` 오버라이드와 같은
            // 이유·같은 해법 — 직접 색을 지정한 `Text`로 실제 보이는
            // 타이틀을 덮어쓴다(`.navigationTitle`은 시스템 내부용으로
            // 그대로 남긴다).
            ToolbarItem(placement: .principal) {
                // [2026-09-10 수정] 사용자 요청 — 각 기능 타이틀을 국민대학교
                // 성곡 세리프체로 표시(라이선스 CC BY-ND, 설정 > 라이센스 탭
                // 고지 참고). `.headline`(시스템 기본, semibold 17pt)이 쓰던
                // 굵기·크기를 최대한 그대로 유지하려고 같은 17pt에
                // `relativeTo: .headline`(Dynamic Type 배율 유지)과
                // `.fontWeight(.semibold)`(성곡 세리프는 Regular 한 굵기뿐이라
                // SwiftUI가 화면에 그릴 때만 합성 볼드로 흉내낸다 — 배포되는
                // 폰트 파일 자체를 바꾸는 게 아니라 라이선스의 "변경 금지"
                // 조건과 무관)를 그대로 맞췄다.
                Text("말씀 노트")
                    .font(.custom(SpecialPurposeFonts.titleSerif, size: 20, relativeTo: .title3))
                    .fontWeight(.semibold)
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { createNewMemo() } label: { Text("개인 묵상 추가").font(.body) }
                    Button { createNewSummary() } label: { Text("말씀 요약 추가").font(.body) }
                } label: {
                    // [2026-09-11 변경] 사용자 재검토 요청 — "테마색상
                    // 팔레트 6개가 실제로는 2~3톤처럼 보인다." 서재 금박
                    // (JBCHCategoryPalette.gold)을 이 화면의 핵심 동작(메모
                    // 추가)에 명시 배정한다 — 팔레트 선언부 주석이 애초에
                    // "사용자가 직접 다루는 항목(메모)"용으로 의도했던
                    // 자리다. 예전 `.tint(.accentColor)`는 시스템
                    // AccentColor 자체가 이미 이 색이라 값은 같았지만 아이콘
                    // 색만 바꿔서는 "명시적으로 칠했다"는 인상을 전혀 주지
                    // 못했다 — 채워진 원형 배경(흰 아이콘 대비 7.32:1, 공식
                    // 계산 확인)으로 바꿨다.
                    Image(systemName: "square.and.pencil")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(JBCHCategoryPalette.gold, in: Circle())
                }
                .help("새 항목")
            }
        }
        .alert("새 폴더", isPresented: $isNewFolderPresented) {
            TextField("폴더 이름", text: $newFolderName)
            Button("취소", role: .cancel) { newFolderName = "" }
            Button("만들기") { createFolder() }
        }
        // 11장 File 메뉴 "새 메모 ⌘N" / "새 폴더 ⇧⌘N" — AppCommands.swift 참고.
        // 기존 MemoHomeView가 발행하던 것과 같은 키를 그대로 이어받는다("새 메모"는
        // 개인 묵상 하나를 새로 만든다 — 통합 목록에서 "새로 만들기" 메뉴의 첫 항목과
        // 같은 동작).
        .focusedSceneValue(\.newMemoAction) { createNewMemo() }
        .focusedSceneValue(\.newFolderAction) { isNewFolderPresented = true }
    }

    @ViewBuilder
    private func rowContent(for item: WordNoteItem) -> some View {
        if isPhoneLayout {
            NavigationLink {
                destinationView(for: item)
            } label: {
                WordNoteRowView(item: item)
            }
            // [2026-09-09 추가, 실기기 확인 후] 사용자 보고 — "리스트의 각
            // 행은 왜 흰색인가?" 원인 확인 — 이 아이폰 분기엔 `.listRowBackground`가
            // 아예 없어(바로 아래 macOS/아이패드 분기는 처음부터 갖고
            // 있었다 — `selectedItem?.wrappedValue?.id == item.id ? ... :
            // Color.clear`), 행 하나하나가 시스템 기본 리스트 셀 배경을
            // 그대로 썼다 — `.scrollContentBackground(.hidden)` + `List`
            // 자체의 `.background()`(아래)는 리스트라는 "컨테이너"의 배경만
            // 바꾸지, 각 행 셀이 갖고 있는 자기 배경까지 자동으로 투명하게
            // 만들어주지는 않는다는 뜻이다. 바로 아래 macOS/아이패드 분기가
            // 이미 쓰고 있는 것과 같은 해법 — `.listRowBackground(Color.clear)`
            // 로 이 행의 셀 배경을 명시적으로 지워, 뒤의 `List` 배경(테마색)이
            // 그대로 비치게 한다.
            .listRowBackground(Color.clear)
        } else {
            WordNoteRowView(item: item)
                .contentShape(Rectangle())
                .listRowBackground(
                    selectedItem?.wrappedValue?.id == item.id
                        ? Color("AccentColor").opacity(0.15) : Color.clear
                )
                .onTapGesture {
                    selectedItem?.wrappedValue = item
                }
                .contextMenu {
                    // [2026-08-18 추가] 사용자 요청 — "사이드바 메뉴 밑으로 클로드
                    // 앱처럼 기능을 추가할 것. 고정됨." `DocumentRowView`의
                    // 컨텍스트 메뉴 고정 토글과 같은 위치 원칙.
                    Button {
                        togglePin(item)
                    } label: {
                        Label(item.isPinned ? "고정 해제" : "고정", systemImage: item.isPinned ? "pin.slash" : "pin")
                    }
                    Button(role: .destructive) {
                        delete(item)
                    } label: {
                        Label("삭제", systemImage: "trash")
                    }
                }
        }
    }

    private func reload() {
        do {
            allMemos = try modelContext.fetch(
                FetchDescriptor<UserMemo>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
            )
            allSummaries = try modelContext.fetch(
                FetchDescriptor<VerseSummary>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            )
            folders = try modelContext.fetch(
                FetchDescriptor<MemoFolder>(sortBy: [SortDescriptor(\.name)])
            )
        } catch {
            print("[WordNoteListContent] 목록 로드 실패: \(error)")
        }
    }

    /// [2026-08-18 추가] `WordNoteSelectionRequest.swift` 상단 주석 참고 —
    /// 사이드바 "고정됨"/"최근" 섹션에서 특정 개인 묵상/말씀 요약을 골라 들어온
    /// 요청을 실제 항목으로 바꿔 `selectedItem`에 반영한다. 폰 레이아웃(`selectedItem`
    /// 바인딩이 nil)에서는 조용히 아무 것도 안 한다 — `SidebarNavigationView`
    /// 자체가 iPhone에서는 안 쓰이므로(그 화면 상단 주석 — macOS/iPadOS 전용,
    /// 아이폰은 `PhoneTabView`) 실제로는 이 경로를 안 탄다.
    private func applyPendingSelectionRequest() {
        guard let target = WordNoteSelectionRequest.shared.requestedTarget else { return }
        let resolved: WordNoteItem?
        switch target {
        case .memo(let id):
            resolved = allMemos.first(where: { $0.id == id }).map { .memo($0) }
        case .summary(let id):
            resolved = allSummaries.first(where: { $0.id == id }).map { .summary($0) }
        }
        guard let resolved else { return }
        selectedItem?.wrappedValue = resolved
        WordNoteSelectionRequest.shared.clear()
    }

    private func createFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let folder = MemoFolder(name: trimmed)
        modelContext.insert(folder)
        try? modelContext.save()
        newFolderName = ""
        reload()
    }

    /// `MemoHomeView.createNewMemo()`와 같은 기본 좌표 규칙(이번 세션 마지막 위치 →
    /// 없으면 창세기 1장).
    private func createNewMemo() {
        let bookId = LastBiblePositionTracker.shared.bookId ?? 1
        let chapter = LastBiblePositionTracker.shared.chapter ?? 1
        let memo = UserMemo(bookId: bookId, chapter: chapter)
        modelContext.insert(memo)
        try? modelContext.save()
        BibleReferenceIndexingService.reindexMemo(memo, context: modelContext)
        reload()
        selectedItem?.wrappedValue = .memo(memo)
    }

    /// `WordSummaryHomeView.createNewSummary()`와 같은 규칙 — `verse`는 항상 nil로
    /// 시작한다(사이드바 진입점이라 특정 절이 정해져 있지 않음).
    private func createNewSummary() {
        let bookId = LastBiblePositionTracker.shared.bookId ?? 1
        let chapter = LastBiblePositionTracker.shared.chapter ?? 1
        let summary = VerseSummary(bookId: bookId, chapter: chapter)
        modelContext.insert(summary)
        try? modelContext.save()
        BibleReferenceIndexingService.reindexWordSummary(summary, context: modelContext)
        reload()
        selectedItem?.wrappedValue = .summary(summary)
    }

    /// [2026-08-18 추가] `DocumentsViewModel.togglePin`과 같은 원칙(이산적 액션,
    /// 즉시 저장).
    private func togglePin(_ item: WordNoteItem) {
        switch item {
        case .memo(let memo): memo.isPinned.toggle()
        case .summary(let summary): summary.isPinned.toggle()
        }
        try? modelContext.save()
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            delete(filteredItems[index], skipReload: true)
        }
        try? modelContext.save()
        reload()
    }

    private func delete(_ item: WordNoteItem, skipReload: Bool = false) {
        if selectedItem?.wrappedValue?.id == item.id {
            selectedItem?.wrappedValue = nil
        }
        switch item {
        case .memo(let memo):
            BibleReferenceIndexingService.removeMentions(
                sourceType: .memo, sourceId: memo.id.uuidString, context: modelContext
            )
            modelContext.delete(memo)
        case .summary(let summary):
            BibleReferenceIndexingService.removeMentions(
                sourceType: .wordSummary, sourceId: summary.id.uuidString, context: modelContext
            )
            modelContext.delete(summary)
        }
        guard !skipReload else { return }
        try? modelContext.save()
        reload()
    }
}
