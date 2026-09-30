//
//  SermonHomeView.swift
//  JBCHBibleResearch
//
//  S-SER1 "내 설교 목록" — 설계 문서 claude/sermon-management-screens-and-schema.md
//  2.2 S-SER1 참고. [말씀 단위 묶음]/[날짜별] 두 보기 방식을 토글하며, 같은
//  데이터(Sermon + SermonDelivery)를 다르게 조회할 뿐이라 스키마 변경은 없다.
//
//  진입점: iOS는 "더보기" 목록의 "내 설교" 행 — `PlaceholderScreens.swift`의
//  "태그 관계"와 같은 이유로 `.fullScreenCover`를 쓴다(단순 `NavigationLink`가
//  아니라): 이 화면은 `.searchable`을 쓰는데, `SearchView.swift` 상단 주석이
//  실기기 로그 세 차례로 확인한 "이미 중첩된 NavigationStack 안에서 .searchable이
//  활성 상태로 그 자리에서 더 push하는 조합은 구조적으로 깨진다"는 문제를 피하기
//  위해서다 — "더보기" 안에 단순 push로 넣으면 정확히 그 깨진 조합이 재현된다.
//  `.fullScreenCover`로 열면 이 화면이 자기 자신의 독립된 NavigationStack의
//  루트가 되어(WordNoteHomeView/SearchView가 이미 안전하게 쓰는 것과 같은
//  위치), 그 문제 자체가 성립하지 않는다.
//  iPad/macOS는 사이드바 "연구문서" 바로 아래 "내 설교" 항목(AppSection.swift/
//  SidebarNavigationView.swift) — `NavigationSplitView`의 detail 컬럼이 이미
//  단독 `NavigationStack`이라(WordNoteHomeView/DocumentsHomeView와 같은 자리)
//  똑같이 안전하다. 이 화면 자체는 두 플랫폼에서 그대로 재사용된다
//  (`DocumentsHomeView`가 이미 쓰는 "한 파일, isPhoneIdiom 분기" 관례).
//
//  [2026-09-28 디자인 정합화] 사용자 지적 — "디자인이 목업 html과 너무 차이가
//  큼." 이전엔 시스템 기본 `List`/`.segmented Picker`만 썼는데, 목업(Claude
//  아티팩트 "내 설교 관리 화면 목업"의 `Main.dc.html`/`MacList.dc.html`)은
//  카드형 행 + 태그 배지 + 액센트 색 버튼을 쓴다. `List`를 `DocumentsHomeView`가
//  이미 쓰는 "ScrollView + 카드" 관례(그 파일 551·767행 `LazyVGrid` 카드 목록)로
//  바꾸고, 색은 새로 고르지 않고 `SermonTheme`(SermonSupport.swift, 이번에
//  추가 — `JBCHCategoryPalette.wine`/다크 짝을 그대로 재사용)만 입혔다.
//
//  [2026-09-29 전면 수정, 사용자 지적 3건]
//  (1) "새 설교 작성후 아무런 입력없이 닫으면 데이터 등록되지 않도록 할것" —
//      예전 `createNewSermon()`은 "새 설교" 버튼을 누르는 즉시 빈 `Sermon`을
//      insert+save했다(제목도 안 쓰고 나가도 빈 설교가 DB에 남는 버그). 이제
//      `SermonCreationSheet`(이 파일 맨 아래, `SermonDeliveryCreationSheet`와
//      같은 패턴)가 "만들기"를 눌러야만(제목 필수) 실제로 insert한다.
//  (2) "내 설교 클릭 - 왼쪽 설교함 - 오른쪽 상세리스트. 왼쪽설교함 - 말씀단위
//      묶음(메인설교문). 오른쪽 상세리스트 - 메인설교문을 활용한 모임에 따른
//      설교문리스트" — 아이패드·맥은 "말씀단위묶음/날짜별 토글 + 단일 목록"
//      대신, `DocumentsHomeView.splitMainContent`와 같은 패턴(HStack + 고정폭
//      왼쪽 열)으로 왼쪽엔 항상 말씀단위 목록을, 오른쪽엔 고른 설교의 상세
//      (`SermonDetailView`)를 그 자리에 바로 보여준다 — 예전엔 별도 창
//      (`openWindow(id: "sermon-detail")`)을 열었다. 아이폰은 화면이 좁아
//      왼쪽/오른쪽이 성립하지 않아 기존 목록→상세 push 방식을 그대로 둔다
//      (사용자 확인). ⚠️ `JBCHBibleResearchApp.swift`의 `WindowGroup(id:
//      "sermon-detail", ...)` 등록 자체는 그대로 남겨 뒀다 — 이제 이 화면
//      에서는 호출하지 않지만(더 이상 필요한 호출부가 없음을 grep으로 확인),
//      다른 곳에서 참조할 수도 있어 임의로 지우지 않았다.
//  (3) "설정-테마색상에 따른 디자인 색상 변화 필요" — `SermonTheme.accent`의
//      새 판(`accent(background:environment:fallbackScheme:)`, SermonSupport.
//      swift)과 `settings.bibleBackgroundColor`/`bibleTextColor`를
//      `DocumentsHomeView`와 같은 패턴으로 적용했다.
//
//  [2026-09-29 재수정] 사용자 지적 — "새 설교 작성 레이어 팝업이 필요없지
//  않은가? 새 설교 작성 버튼을 누르면 오른쪽 상세 이력 리스트에 메인설교의
//  '본문편집' 클릭하면 나오는 창에 제목칸을 넣고 띄우는 것으로 하면 될 것
//  같음. 날짜는 입력받지 말고 현재 시간을 수정일자로 등록할 것." 위 (1)에서
//  만들었던 `SermonCreationSheet`(제목+첫 모임+날짜 입력 시트)를 완전히
//  없앴다 — "새 설교" 버튼은 이제 시트를 띄우지 않고 곧장 `SermonEditorView`
//  (본문편집 화면, `isNewSermon: true`)를 연다. 그 화면 안에 새로 생긴 제목
//  필드(`SermonEditorView.newSermonTitleField`)가 시트의 제목 입력을 대신하고,
//  모임/날짜 선택 단계는 아예 없앴다 — 대신 `SermonEditorView.save()`가 매번
//  호출하는 `subject.touchUpdatedAt()`이 저장 시점의 현재 시각을 그대로
//  `updatedAt`에 넣으므로 "현재 시간을 수정일자로 등록"이 자동으로 성립한다.
//  "아무 입력 없이 닫으면 저장 안 함" 요구사항(위 (1))은 검증 위치만
//  `SermonEditorView.save()`로 옮겨 그대로 유지했다. 아이폰은 여전히
//  `pendingNewSermon` → `navigationDestination(item:)`로 곧장 push하고,
//  아이패드·맥은 별도 창 대신 (2)에서 이미 확정한 오른쪽 패널 자리에
//  `SermonDetailView` 대신 이 에디터를 직접 얹는다(같은 "제자리에 보여준다"
//  원칙의 연장, 새 패턴이 아니다).
//

import SwiftUI
import SwiftData
import BibleResearchModels
#if os(iOS)
import UIKit
#endif

private enum SermonListViewMode: String, CaseIterable {
    case bySermon = "말씀 단위 묶음"
    case byDate = "날짜별"
}


/// [2026-09-29 신설] 사용자 요청 — "설정-테마색상에 따른 디자인 색상 변화
/// 필요." `DocumentsHomeView`/`BibleReadingView`/`WordNoteHomeView`/
/// `SearchView`가 이미 각자 파일에 두고 있는 것과 완전히 같은 타입·같은
/// 구현(그 파일들 주석 — "iOS 16+ 공식 API + WCAG 상대휘도로 다크/라이트
/// 아이템 색 결정")이다.
///
/// ⚠️ [2026-09-29 수정, 빌드 에러 fix] 처음엔 "내 설교" 화면 3개가 공유하는
/// `SermonSupport.swift`에 `private` 없이 한 번만 선언했었다 — 사용자 보고,
/// Xcode 에러 "Invalid redeclaration of 'ThemedNavigationBarBackgroundModifier'"
/// (SearchView.swift:54). 원인: Swift는 파일 최상위의 `private`(=`fileprivate`)
/// 선언과 다른 파일의 `private` 아닌(= internal) 같은 이름 선언이 같은
/// 모듈 안에 있으면, 접근 범위와 무관하게 이름 충돌로 처리한다 — 기존 4개
/// 파일이 서로 충돌 없이 같은 이름을 쓸 수 있었던 건 넷 다 예외 없이
/// `private`였기 때문이다. 그래서 공유하는 대신, 그 4개 파일과 완전히 같은
/// 관례대로 이 파일에도 `private`로 다시 선언한다(기능당 하나 공유가 아니라
/// 파일마다 중복 — 이 프로젝트가 실제로 쓰는 관례는 후자였다).
private struct ThemedNavigationBarBackgroundModifier: ViewModifier {
    let color: Color?

    @Environment(\.self) private var environment

    func body(content: Content) -> some View {
        #if os(iOS)
        if let color {
            content
                .toolbarBackground(color, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(Self.isDarkBackground(color, in: environment) ? .dark : .light, for: .navigationBar)
        } else {
            content
        }
        #elseif os(macOS)
        // [2026-09-29 수정] 사용자 보고(맥OS) — 이 화면 상단 제목 표시줄
        // "흰색 바" 영역이 테마 배경색과 안 맞음 -> 배경색 맞추기. 기존
        // 결론("macOS는 `.navigationBar` 플레이스먼트 자체가 없어 이
        // 모디파이어로 바꿀 표준 API가 없다")은 `.navigationBar`(iOS 전용)
        // 하나만 시도해 본 결과였다 — `ToolbarPlacement`에는 macOS 전용으로
        // 따로 존재하는 `.windowToolbar`(macOS 13+, 이 앱 배포 타깃은
        // project.pbxproj 확인 결과 macOS 26.5라 버전 문제 없음) 케이스가
        // 있고, 이 화면은 `SidebarNavigationView`의 `NavigationSplitView`
        // detail 컬럼에 바로 들어가 macOS 창의 통합 툴바에 제목이 그려지는
        // 구조(SidebarNavigationView.swift 확인)라 `.windowToolbar`가 바로 그
        // 창 툴바를 가리킨다고 판단해 적용한다. 다만 이 환경(빌드 도구 없음)
        // 에서 실제 빌드·실기기 확인은 못 했으니, 적용 후 기대한 배경색
        // 매칭이 실제로 되는지 확인해 주시면 좋겠다.
        if let color {
            content
                .toolbarBackground(color, for: .windowToolbar)
                .toolbarBackground(.visible, for: .windowToolbar)
                .toolbarColorScheme(Self.isDarkBackground(color, in: environment) ? .dark : .light, for: .windowToolbar)
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

struct SermonHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment
    /// [2026-09-29 신설] 사용자 지적 — "내 설교 - 왼쪽 영역으로 '본문편집'
    /// 버튼, '뷰어로 보기' 이동." 아이패드·맥에서 왼쪽 "설교함" 행에 편집/
    /// 뷰어 버튼을 추가하며 필요해졌다 — `SermonDetailView`가 이미 같은
    /// 이유로 갖고 있던 것과 완전히 같다(그 파일의 `editorButton`/
    /// `viewerButton` 참고).
    @Environment(\.openWindow) private var openWindow

    @Query(sort: \Sermon.updatedAt, order: .reverse) private var sermons: [Sermon]
    @Query(sort: \SermonDelivery.deliveredAt, order: .reverse) private var deliveries: [SermonDelivery]

    @State private var viewMode: SermonListViewMode = .bySermon
    @State private var searchText = ""
    /// [2026-09-29 재수정] "새 설교" 버튼을 누르면 아직 `modelContext`에
    /// insert하지 않은 `Sermon` 인스턴스를 바로 여기 담는다 — 아이폰은 이 값
    /// 기반 내비게이션(`NavigationLink`는 프로그램적으로 트리거할 수 없어
    /// `.navigationDestination(item:)`를 씀)으로 곧장 에디터를 push하고,
    /// 아이패드·맥은 `splitContent`가 오른쪽 패널에 이 값이 있으면
    /// `SermonDetailView` 대신 에디터를 직접 보여준다(둘 다 아래). `Sermon`은
    /// SwiftData `PersistentModel`이라 기본으로 `Hashable`을 만족해 바인딩
    /// 가능하다. 실제 insert는 `SermonEditorView.save()`가 제목/본문 중
    /// 하나라도 채워졌을 때만 한다(시트가 하던 지연 삽입 검증을 그대로
    /// 옮김) — 이 값 자체는 화면 전환용일 뿐 데이터 등록과 무관하다.
    @State private var pendingNewSermon: Sermon?
    /// 메인 `Sermon` 삭제 확인 대화상자 대상. `Sermon.deliveries`/
    /// `verseReferences`가 `.cascade`라(Sermons.swift) 삭제 시 이력·구절
    /// 레코드가 함께 사라진다 — 그래서 Document/Memo류의 "확인 없이 바로
    /// 삭제" 관례를 따르지 않고, SettingsView의 "전체 삭제" 확인 대화상자
    /// 패턴을 그대로 재사용한다(사용자 승인 — "이대로 진행").
    @State private var sermonPendingDelete: Sermon?
    /// [2026-09-29 신설] 아이패드·맥 전용 — 왼쪽 "설교함"(말씀단위 목록)에서
    /// 고른 설교. 오른쪽 "상세리스트" 패널이 이 값을 그대로 읽어 그 설교의
    /// 활용 이력을 보여준다(위 파일 상단 주석 (2)).
    @State private var selectedSermonID: PersistentIdentifier?
    /// [2026-09-29 신설] 사용자 요청 — "'이 설교를 새 모임에서 사용' 버튼을
    /// 왼쪽 설교 리스트로 이동 + 리스트 항목 하단에 '새 모임' 버튼 추가."
    /// 예전엔 오른쪽 패널(`SermonDetailView.isAddDeliveryPresented`)이 갖고
    /// 있던 상태를 그대로 여기로 옮겼다 — `.sheet(item:)`이라 어느 설교
    /// 행에서 눌렀는지가 이 값 자체(nil이 아니면 그 설교)로 정해진다.
    @State private var sermonPendingNewDelivery: Sermon?
    /// [2026-09-29 신설] 사용자 요청 — "편집을 눌러도 새창이 아니라 상세
    /// 모임 리스트 영역에 나타날 수 있도록." 지금까지 왼쪽 설교함 행의
    /// "편집" 버튼은 `openWindow(id: "sermon-editor", ...)`로 별도 창을
    /// 열었다 — 이 값이 있으면 `splitContent` 오른쪽 패널이 `SermonDetailView`
    /// 대신 그 자리에 곧장 `SermonEditorView`를 얹는다. `pendingNewSermon`
    /// (새 설교 작성)과 같은 구조지만 완전히 별개 상태다 — 이건 "이미 있는
    /// 설교를 편집 중"이라 `isNewSermon: false`로 열고, `SermonEditorView.
    /// save()`도 매번 그냥 저장하는 일반 경로(지연 삽입 없음)를 탄다.
    @State private var editingSermon: Sermon?

    private var settings: UserSettingsStore { .shared }

    /// [2026-09-29 수정] 테마색상 반영 — `SermonSupport.swift`의 새 판 참고.
    private var accent: Color {
        SermonTheme.accent(background: settings.bibleBackgroundColor, environment: environment, fallbackScheme: colorScheme)
    }

    /// [2026-09-29 신설] 사용자 요청 — "설교문 리스트 하단 버튼 4개,
    /// 뷰어 버튼과 같은 스타일(채움)로 통일하되 색상은 서로 다르게."
    /// `SermonMindMapView.isDarkSurface`와 완전히 같은 WCAG 상대휘도
    /// 공식(그 파일 참고 — 이 프로젝트가 여러 파일에 걸쳐 같은 공식을
    /// 각자 두는 것과 같은 관례) — 아래 3개 버튼의 `JBCHCategoryPalette`
    /// 색이 라이트/다크 어느 변형을 쓸지 고르는 데 쓴다.
    private var isDarkSurface: Bool {
        if let background = settings.bibleBackgroundColor {
            let resolved = background.resolve(in: environment)
            let luminance = 0.2126 * Double(resolved.red) + 0.7152 * Double(resolved.green) + 0.0722 * Double(resolved.blue)
            return luminance < 0.5
        }
        return colorScheme == .dark
    }

    /// 아래 사이드바 행 버튼 4개(모임/Map/편집/뷰어) 전용 색 — 사용자
    /// 요청대로 "뷰어" 버튼(=`accent`=wine)과 같은 채움 스타일을 쓰되
    /// 서로 구분되도록 색만 다르게 했다. 새 hex를 추측해 만들지 않고
    /// `JBCHCategoryPalette`(이미 이 파일이 마인드맵 화면과 공유하는
    /// 팔레트)에서 wine과 겹치지 않는 3색을 더 골랐다 — gold는 OnDark
    /// 변형이 없다는 알려진 한계(`SermonMindMapView.resolvedColor` 주석
    /// 참고)가 있어 여기서도 피한다.
    private var joinButtonTint: Color { isDarkSurface ? JBCHCategoryPalette.navyOnDark : JBCHCategoryPalette.navy }
    private var mapButtonTint: Color { isDarkSurface ? JBCHCategoryPalette.slateTealOnDark : JBCHCategoryPalette.slateTeal }
    private var editButtonTint: Color { isDarkSurface ? JBCHCategoryPalette.woodOnDark : JBCHCategoryPalette.wood }

    private var isPhoneIdiom: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    private var filteredSermons: [Sermon] {
        guard !searchText.isEmpty else { return sermons }
        return sermons.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.contentText.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredDeliveries: [SermonDelivery] {
        guard !searchText.isEmpty else { return deliveries }
        return deliveries.filter { delivery in
            (delivery.sermon?.title.localizedCaseInsensitiveContains(searchText) ?? false)
                || delivery.contentText.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedSermon: Sermon? {
        guard let selectedSermonID else { return nil }
        return sermons.first { $0.persistentModelID == selectedSermonID }
    }

    var body: some View {
        Group {
            if isPhoneIdiom {
                // [2026-09-29 수정] 사용자 보고 — "'취소' 버튼은 아이패드·맥
                // 에서만 보이는데, 맥에서 새 설교를 쓰다 취소하려면 '<'를
                // 눌러야 하나 '취소'를 눌러야 하나?" 원인 확인 — 바로 아래
                // `.navigationDestination(item: $pendingNewSermon)`이 지금까지
                // 플랫폼 구분 없이 이 `body` 전체에 걸려 있었다. `splitContent`
                // (아이패드·맥)는 이미 자기 안에서 `if let pendingNewSermon`
                // 으로 오른쪽 패널에 에디터를 직접 얹는데(splitContent 주석
                // 참고), `NavigationSplitView`의 detail 컬럼 자체가 하나의
                // `NavigationStack`이라(파일 상단 주석 (2)) 같은 `pendingNewSermon`
                // 이 `nil`→값으로 바뀌는 그 순간 이 `navigationDestination`도
                // 동시에 반응해 그 위에 에디터를 한 번 더 push했다 — 결과적으로
                // "이미 오른쪽 패널에 얹힌 에디터" 위에 "push된 에디터"가 한
                // 겹 더 쌓이고, push된 쪽엔 시스템이 자동으로 진짜 뒤로가기
                // "<"를 붙인다. 그래서 같은 화면에 "<"(그 push를 pop, 안쪽
                // 겹만 닫힘)와 "취소"(`pendingNewSermon`을 nil로 돌려 양쪽
                // 다 닫힘)라는 서로 다르게 동작하는 두 버튼이 같이 보였던
                // 것 — 사용자가 겪은 혼란의 실제 원인이다. 고치는 방법은 이
                // push 자체가 필요한 아이폰(`navigationDestination(item:)`으로
                // "만" 화면을 여는 플랫폼)에서만 이 모디파이어를 걸도록
                // 범위를 좁히는 것 — 아이패드·맥은 `splitContent`의 직접
                // 얹기만 남아 다시 하나의 에디터, 하나의 닫기 버튼("취소")만
                // 보인다.
                phoneContent
                    .navigationDestination(item: $pendingNewSermon) { sermon in
                        SermonEditorView(
                            subject: .sermon(sermon),
                            isNewSermon: true,
                            onRequestClose: { pendingNewSermon = nil }
                        )
                    }
            } else {
                splitContent
            }
        }
        .navigationTitle("내 설교")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .modifier(ThemedNavigationBarBackgroundModifier(color: settings.bibleBackgroundColor))
        .confirmationDialog(
            "이 설교를 삭제할까요?",
            isPresented: Binding(
                get: { sermonPendingDelete != nil },
                set: { isPresented in if !isPresented { sermonPendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: sermonPendingDelete
        ) { sermon in
            Button("삭제", role: .destructive) { deleteSermon(sermon) }
            Button("취소", role: .cancel) {}
        } message: { sermon in
            let count = (sermon.deliveries ?? []).count
            Text(count > 0
                ? "이 설교와 활용 이력 \(count)건이 모두 삭제됩니다. 되돌릴 수 없습니다."
                : "이 설교가 삭제됩니다. 되돌릴 수 없습니다.")
        }
    }

    // MARK: - 아이폰 본문 (기존 그대로 — 말씀단위묶음/날짜별 토글 + 단일 목록)

    private var phoneContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                header

                SermonSegmentedPill(
                    items: [
                        .init(tag: SermonListViewMode.bySermon, label: SermonListViewMode.bySermon.rawValue),
                        .init(tag: SermonListViewMode.byDate, label: SermonListViewMode.byDate.rawValue),
                    ],
                    selection: $viewMode,
                    accent: accent
                )

                switch viewMode {
                case .bySermon:
                    if filteredSermons.isEmpty {
                        emptyState(text: "아직 등록한 설교가 없습니다.")
                    } else {
                        ForEach(filteredSermons) { sermon in
                            sermonRow(sermon)
                        }
                    }
                case .byDate:
                    if filteredDeliveries.isEmpty {
                        emptyState(text: "아직 사용 이력이 없습니다.")
                    } else {
                        ForEach(filteredDeliveries) { delivery in
                            deliveryRow(delivery)
                        }
                    }
                }
            }
            .padding(16)
        }
        .searchable(text: $searchText, prompt: "제목·본문 검색")
        .background(settings.bibleBackgroundColor ?? Color.clear)
    }

    // MARK: - 아이패드·맥 본문 — 왼쪽 설교함(말씀단위 목록) / 오른쪽 상세리스트
    //
    // [2026-09-29 신설] 위 파일 상단 주석 (2) 참고. `DocumentsHomeView.
    // splitMainContent`(HStack + Divider + 고정폭 왼쪽 열)와 같은 패턴 — 이
    // 화면엔 지금까지 플랫폼별 레이아웃 분기가 토글 하나뿐이었으나, 이번에
    // Documents/Outline/WordNote 등이 이미 쓰는 분할 관례로 맞춘다.
    private var splitContent: some View {
        VStack(spacing: 0) {
            header
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 8)

            Divider()

            HStack(spacing: 0) {
                sermonSidebar
                    // [2026-09-29 수정] 사용자 요청 — "오른쪽의 설교리스트
                    // 영역을 현재 크기의 절반으로 줄이고, 상세 모임리스트를
                    // 그만큼 더 늘릴것." 기존 280/340/440을 그대로 절반으로.
                    // [2026-09-29 재수정] 사용자 요청 — "설교문 리스트
                    // 영역 10px 늘리기(버튼 텍스트가 잘림)." 행 버튼 4개가
                    // 이제 `.frame(maxWidth: .infinity)`로 폭을 나눠 갖게
                    // 되면서(바로 위 커밋) 가로 여유가 더 필요해져, 세 값을
                    // 모두 10px씩 늘렸다.
                    .frame(minWidth: 150, idealWidth: 180, maxWidth: 230)

                Divider()

                if let pendingNewSermon {
                    // [2026-09-29 신설] "새 설교" 버튼(아이패드·맥) — 별도
                    // 팝업 없이, 원래 `SermonDetailView`가 뜨던 이 자리에
                    // 곧장 에디터(제목 필드 포함)를 얹는다. `SermonEditorView`
                    // 안에 `@Environment(\.dismiss)`가 기댈 프레젠테이션이
                    // 없어(시트/창이 아니라 그냥 얹힌 뷰라서) `onRequestClose`로
                    // 직접 이 값을 nil로 되돌린다.
                    SermonEditorView(
                        subject: .sermon(pendingNewSermon),
                        isNewSermon: true,
                        onRequestClose: { self.pendingNewSermon = nil }
                    )
                } else if let editingSermon {
                    // [2026-09-29 신설] 사용자 요청 — "편집을 눌러도 새창이
                    // 아니라 상세 모임 리스트 영역에." 위 `pendingNewSermon`
                    // 분기와 완전히 같은 패턴, 다만 `isNewSermon: false`(이미
                    // 있는 설교)라 지연 삽입 없이 그냥 저장된다.
                    SermonEditorView(
                        subject: .sermon(editingSermon),
                        onRequestClose: { self.editingSermon = nil }
                    )
                } else if let selectedSermon {
                    SermonDetailView(sermon: selectedSermon)
                } else {
                    emptySelectionPane
                }
            }
        }
        .searchable(text: $searchText, prompt: "제목·본문 검색")
        // [2026-09-30 신설] 사용자 요청 — 마인드맵 "설교문 적용" 후 "해당
        // 설교를 클릭해서 모임 리스트가 보이는 화면으로 이동". 마인드맵 창이
        // 본문을 적용·저장하고 나면 이 설교를 목록에서 선택해 오른쪽 패널이
        // `SermonDetailView`(모임 리스트)를 보이게 한다. 이 설교의 인라인 편집기가
        // 열려 있었다면 편집기 스스로 저장 없이 닫히지만(`SermonEditorView`),
        // 상태(`editingSermon`)는 여기서도 함께 비워 둔다. 새 설교 작성 중
        // (`pendingNewSermon`)은 다른 설교라 건드리지 않는다.
        .onSermonExternalContentChange(onReplaced: { id in
            if editingSermon?.persistentModelID == id {
                editingSermon = nil
            }
            selectedSermonID = id
        })
        .background(settings.bibleBackgroundColor ?? Color.clear)
        .sheet(item: $sermonPendingNewDelivery) { sermon in
            SermonDeliveryCreationSheet(sermon: sermon)
        }
    }

    /// 왼쪽 "설교함" — 늘 말씀단위 목록만 보여준다(토글 없음). 고르면
    /// `selectedSermonID`만 바뀌고, 오른쪽 `SermonDetailView`가 그 값을
    /// 그대로 읽어 다시 그린다(별도 창을 열지 않음).
    private var sermonSidebar: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if filteredSermons.isEmpty {
                    emptyState(text: "아직 등록한 설교가 없습니다.")
                } else {
                    ForEach(filteredSermons) { sermon in
                        VStack(alignment: .leading, spacing: 0) {
                            Button {
                                // [2026-09-29 신설] 새 설교 작성 중(`pendingNewSermon`
                                // 있음)에 다른 설교를 고르면, 만들던 새 설교는
                                // (제목/본문이 비어 있었다면) 그냥 버려지고
                                // (`SermonEditorView.save()`의 지연 삽입 검증,
                                // 뷰가 사라질 때 `onDisappear`로 호출됨) 고른
                                // 설교로 전환된다.
                                pendingNewSermon = nil
                                editingSermon = nil
                                selectedSermonID = sermon.persistentModelID
                            } label: {
                                sermonRowLabel(sermon)
                                    .overlay(alignment: .leading) {
                                        if sermon.persistentModelID == selectedSermonID {
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(accent)
                                                .frame(width: 3)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)

                            // [2026-09-29 신설] 사용자 지적 — "내 설교 - 왼쪽
                            // 영역으로 '본문편집'버튼, '뷰어로 보기' 이동 ->
                            // '편집', '뷰어' 이름 변경." 예전엔 오른쪽 패널
                            // (`SermonDetailView`)의 본문 안에 있었다 — 그
                            // 화면에선 아이패드·맥 전용으로 없앴고(그 파일
                            // `body` 주석 참고), 대신 여기 왼쪽 설교함 행에
                            // 바로 붙여 "고르지 않고도 곧장 편집/뷰어로"
                            // 갈 수 있게 했다. `SermonDetailView.editorButton`/
                            // `viewerButton`의 아이패드·맥 분기와 완전히 같은
                            // `openWindow` 호출을 그대로 재사용한다.
                            // [2026-09-29 재수정] 사용자 요청 — "버튼간
                            // 간격은 지금보다 1/2가량으로 좁힐 것." 기존 8 → 4.
                            HStack(spacing: 4) {
                                // [2026-09-29 이동] 사용자 요청 — "'이 설교를
                                // 새 모임에서 사용' 버튼을 왼쪽 설교 리스트로
                                // 이동." 예전엔 오른쪽 패널(`SermonDetailView.
                                // deliverySection`)에 있던 버튼을 여기로
                                // 옮겼다 — 편집/뷰어와 같은 "행 하나에서 바로
                                // 처리" 원칙, 라벨은 목업/기존 관례("새 모임")
                                // 그대로.
                                Button {
                                    sermonPendingNewDelivery = sermon
                                } label: {
                                    sermonRowActionLabel(title: "모임", systemImage: "plus.circle")
                                }
                                .buttonStyle(SermonMiniPillButtonStyle(isFilled: true, tint: joinButtonTint))
                                // [2026-09-29 신설] "마인드맵" 기능 — 사용자
                                // 요청 원문("내 설교 리스트 항목 밑에 모임
                                // 버튼 오른쪽 부분에 Map 버튼 추가") 그대로,
                                // "모임" 버튼 바로 오른쪽에 둔다 — Claude
                                // 아티팩트 HTML 목업의
                                // "배치 근거" 설명과 동일. 아이콘은 사용자가
                                // 최종 확정한 "트리 아이콘"(자료구조 관련) —
                                // `point.3.connected.trianglepath.dotted`는
                                // SF Symbols 4(iOS 16+/macOS 13+)부터 제공되는
                                // "점 3개가 서로 이어진" 기존 심벌이라 이
                                // 앱의 배포 타깃(iOS 18+/macOS 15+, project.
                                // pbxproj 확인)에서 쓸 수 있다 — 다만 이
                                // 환경엔 Xcode/SF Symbols 앱이 없어 정확한
                                // 렌더링 모양(목업의 "루트+자식 2개" 트리
                                // 형태와 얼마나 비슷한지)까지는 직접 확인하지
                                // 못했다. ⚠️ [Xcode 확인 필요] 빌드 후 실제
                                // 렌더링을 보고 더 트리에 가까운 다른 심벌이
                                // 낫다고 판단되면 이 한 곳만 바꾸면 된다.
                                Button {
                                    openWindow(id: "sermon-mindmap", value: SermonMindMapTarget.sermon(sermon))
                                } label: {
                                    sermonRowActionLabel(title: "Map", systemImage: "point.3.connected.trianglepath.dotted")
                                }
                                .buttonStyle(SermonMiniPillButtonStyle(isFilled: true, tint: mapButtonTint))
                                Button {
                                    // [2026-09-29 수정] 사용자 요청 — "편집을
                                    // 눌러도 새창이 아니라 상세 모임 리스트
                                    // 영역에 나타날 수 있도록." 기존
                                    // `openWindow(id: "sermon-editor", ...)`를
                                    // 없애고 `editingSermon`을 채워 오른쪽
                                    // 패널이 그 자리에서 곧장 에디터를
                                    // 보여주게 한다(`splitContent` 참고).
                                    pendingNewSermon = nil
                                    selectedSermonID = sermon.persistentModelID
                                    editingSermon = sermon
                                } label: {
                                    sermonRowActionLabel(title: "편집", systemImage: "square.and.pencil")
                                }
                                .buttonStyle(SermonMiniPillButtonStyle(isFilled: true, tint: editButtonTint))
                                Button {
                                    openWindow(id: "sermon-viewer", value: SermonViewerTarget.sermon(sermon))
                                } label: {
                                    sermonRowActionLabel(title: "뷰어", systemImage: "eyeglasses")
                                }
                                .buttonStyle(SermonMiniPillButtonStyle(isFilled: true, tint: accent))
                            }
                            .padding(.horizontal, 4)
                            .padding(.top, 4)
                        }
                        // [2026-09-29 참고] `sermonRowLabel`이 이미 자기 카드
                        // 배경(`SermonTheme.cardFill`, padding 16)을 갖고 있어
                        // 여기서 VStack 전체를 또 카드로 감싸지 않는다 — 감싸면
                        // 카드 안에 카드가 겹쳐 보이는 이중 배경이 생긴다. 편집/
                        // 뷰어 버튼 줄은 그 카드 바로 아래, 사이드바 배경 위에
                        // 얇게 붙는 형태로 둔다.
                        .contextMenu {
                            Button(role: .destructive) {
                                sermonPendingDelete = sermon
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var emptySelectionPane: some View {
        VStack {
            Spacer()
            Text("왼쪽에서 설교를 선택하세요.")
                .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 상단(제목 + 새 설교) — 목업 Main.dc.html 헤더

    private var header: some View {
        HStack {
            Text("내 설교")
                .font(.title2.bold())
                .foregroundStyle(settings.bibleTextColor ?? .primary)
            Spacer()
            Button {
                startNewSermon()
            } label: {
                Label("새 설교", systemImage: "plus")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(accent)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func emptyState(text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
    }

    // MARK: - 말씀 단위 묶음 행 (아이폰 전용 — push로 상세 화면 이동)

    @ViewBuilder
    private func sermonRow(_ sermon: Sermon) -> some View {
        NavigationLink {
            SermonDetailView(sermon: sermon)
        } label: {
            sermonRowLabel(sermon)
        }
        .buttonStyle(.plain)
        // [2026-09-28 삭제 기능] 파급력이 큰 삭제라 바로 지우지 않고
        // `sermonPendingDelete`를 거쳐 확인 대화상자를 띄운다(위 프로퍼티
        // 주석 참고).
        .contextMenu {
            Button(role: .destructive) {
                sermonPendingDelete = sermon
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
    }

    /// 목업 Main.dc.html 카드(제목 → 태그 배지 → 구분선 → 활용 이력/수정일).
    /// [2026-09-29 신설] 사용자 요청 — "최근 모임 : 년. 월. 일 (요일) 모임명 /
    /// 최근 수정일 : 년. 월. 일 (요일) 시간(24시간)" 형식 그대로. 사용자가
    /// "시간(24시간)"이라고 명시했으므로 기기의 12/24시간제 설정과 무관하게
    /// 항상 24시간제(HH)로 고정한 `DateFormatter`를 직접 만든다 — `Date.
    /// FormatStyle`의 로케일 종속 기본 표기(자동 12/24시간 전환)에 맡기지 않는다.
    private static let gatheringDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy. M. d (E)"
        return formatter
    }()

    private static let updatedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy. M. d (E) HH:mm"
        return formatter
    }()

    /// [2026-09-29 신설, 버그 수정] 사용자 보고 — "설교문 리스트 하단 버튼
    /// 디자인 수정: 아이콘 줄바꿈 텍스트"(첨부 스크린샷 — 좁아진 설교함
    /// 폭에서 `Label("새 모임", ...)`의 한글 텍스트가 음절 단위로
    /// (새/모/임 세 줄) 깨져 보였다). 원인은 `Label`이 가로 공간이 부족하면
    /// 아이콘을 위로 올리고 텍스트를 그 아래 두는데, 그 텍스트마저 한 줄에
    /// 다 못 들어가면 한글은 띄어쓰기 기준이 아니라 음절 단위로 줄바꿈되기
    /// 때문이다. 아이콘(위)/텍스트(아래) 두 줄 레이아웃 자체는 요청대로
    /// 유지하되, `.lineLimit(1)`로 텍스트가 더 쪼개지지 않게 고정한다 —
    /// 라벨을 "모임"/"편집"/"뷰어" 두 글자로 줄인 것과 함께라면 한 줄에
    /// 안전하게 들어간다. `SermonDetailView.swift`가 공유하는
    /// `SermonMiniPillButtonStyle` 자체는 건드리지 않는다 — 그쪽은 아이콘
    /// 없는 `Text`만 써서 이 문제가 없다.
    // [2026-09-30 재수정] 사용자 재지적 — "설교문 리스트 행 하위 버튼 4개:
    // 높이와 폭을 동일하게 맞출 것(폭과 길이가 각각 다름)." 원인: 직전
    // 수정은 `.frame(maxWidth: .infinity, minHeight: 44)`를 **버튼 바깥**에
    // 걸었는데, `SermonMiniPillButtonStyle`은 그 스타일 안에서 라벨 크기에
    // 맞춰 배경(알약)을 그리므로 바깥 프레임은 알약 크기를 바꾸지 못했다 —
    // 그래서 아이콘/글자 폭이 다른 4개 알약이 각자 내용 크기로 그려졌다.
    // 해결: 크기를 **라벨 안**에 걸어(스타일이 그 크기에 패딩을 더해 배경을
    // 그린다) 4개 모두 같은 폭(HStack이 균등 분배)·같은 높이가 되게 했다.
    private func sermonRowActionLabel(title: String, systemImage: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.callout)
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 38)
    }

    private func sermonRowLabel(_ sermon: Sermon) -> some View {
        let sortedDeliveries = (sermon.deliveries ?? []).sorted { $0.deliveredAt > $1.deliveredAt }
        let tags = (sermon.sermonTags ?? []).compactMap(\.tag).filter { !$0.isMerged }
        return VStack(alignment: .leading, spacing: 10) {
            Text(sermon.title.isEmpty ? "제목 없음" : sermon.title)
                .font(.headline)
                .foregroundStyle(settings.bibleTextColor ?? .primary)
                .multilineTextAlignment(.leading)

            if !tags.isEmpty {
                FlowLayoutHStack {
                    ForEach(tags) { tag in
                        SermonBadge(text: "#\(tag.name)", color: accent)
                    }
                }
            }

            if !sortedDeliveries.isEmpty {
                Divider()
            }

            // [2026-09-29 수정] 사용자 요청 — "타이틀 하단 분할된 두 영역을
            // 병합할것." 예전엔 `HStack` + `Spacer`로 "N회 사용 · 최근 ..."
            // (왼쪽)과 "수정 ..."(오른쪽)이 좌우로 갈라져 있었다 — 좁아진
            // 설교함(절반 폭, 2026-09-29 이전 변경) 폭에서는 왼쪽 텍스트가
            // 길어지면 두 영역이 시각적으로 따로 노는 느낌이 더 심해졌다.
            // 요청대로 한 세로 블록(x회 사용 / 최근 모임 / 최근 수정일 3줄)
            // 으로 합쳤다 — 마지막 줄(최근 수정일)만 회색, 나머지는 기존
            // 색(사용 이력 있음: `SermonTheme.success` 초록, 없음: secondary)
            // 그대로 유지한다.
            VStack(alignment: .leading, spacing: 4) {
                if let latest = sortedDeliveries.first {
                    Text("\(sortedDeliveries.count)회 사용")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SermonTheme.success)
                    Text("최근 : \(Self.gatheringDateFormatter.string(from: latest.deliveredAt)) \(latest.gathering?.name ?? "모임 미지정")")
                        .font(.caption)
                        .foregroundStyle(SermonTheme.success)
                } else {
                    Text("사용 이력 없음")
                        .font(.caption)
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
                }
                Text("수정 : \(Self.updatedAtFormatter.string(from: sermon.updatedAt))")
                    .font(.caption)
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: SermonTheme.cardCornerRadius, style: .continuous).fill(SermonTheme.cardFill))
    }

    // MARK: - 날짜별 행 (아이폰 전용 — 아이패드·맥은 splitContent가 대체)

    @ViewBuilder
    private func deliveryRow(_ delivery: SermonDelivery) -> some View {
        // 설계 문서 2.2 S-SER1 — "날짜별은 그 회차의 실제 본문(해당 SermonDelivery
        // 대상)으로 바로 진입" — 상세/이력 화면을 거치지 않고 곧바로 작성 화면
        // (3단계 완료 — SermonEditorView)으로 이동한다.
        NavigationLink {
            SermonEditorView(subject: .delivery(delivery))
        } label: {
            deliveryRowLabel(delivery)
        }
        .buttonStyle(.plain)
        // [2026-09-28 삭제 기능] 개별 이력은 캐스케이드로 다른 걸 끌고 내려가지
        // 않아(Sermons.swift — `SermonDelivery` 자신에 걸린 `.cascade`
        // 관계 없음) Document/WordNote 관례대로 확인 없이 바로 지운다.
        .contextMenu {
            Button(role: .destructive) {
                deleteDelivery(delivery)
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
    }

    private func deliveryRowLabel(_ delivery: SermonDelivery) -> some View {
        let isModified = (delivery.sermon?.contentText).map { $0 != delivery.contentText } ?? false
        return HStack(spacing: 12) {
            Text(delivery.deliveredAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 90, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(delivery.gathering?.name ?? "모임 미지정")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(settings.bibleTextColor ?? .primary)
                Text(delivery.sermon?.title.isEmpty == false ? delivery.sermon!.title : "제목 없음")
                    .font(.caption)
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.6) ?? Color.secondary)
            }
            Spacer()
            if isModified {
                SermonBadge(text: "수정됨", color: SermonTheme.warning)
            } else {
                SermonBadge(text: "메인과 동일", color: SermonTheme.success)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: SermonTheme.cardCornerRadius, style: .continuous).fill(SermonTheme.cardFill))
    }

    // MARK: - 삭제

    /// `sermonPendingDelete` 확인 대화상자에서 "삭제"를 눌렀을 때만 호출된다.
    /// `Sermon.deliveries`/`verseReferences`가 `.cascade`라 이 한 번의 삭제로
    /// 연결된 이력·구절 레코드까지 함께 지워진다(Sermons.swift).
    private func deleteSermon(_ sermon: Sermon) {
        if selectedSermonID == sermon.persistentModelID {
            selectedSermonID = nil
        }
        // [2026-09-29 추가] 사용자 요청 — "통합 검색에 '내 설교' 탭... + 성경구절
        // 파싱." `MemoHomeView.delete`가 메모를 지우기 전 `removeMentions`부터
        // 부르는 것과 같은 관례 — 삭제 전에 `sourceId`(sermon.id.uuidString)를
        // 미리 확보해야 하므로 `modelContext.delete(sermon)`보다 먼저 호출한다.
        BibleReferenceIndexingService.removeMentions(sourceType: .sermon, sourceId: sermon.id.uuidString, context: modelContext)
        modelContext.delete(sermon)
        try? modelContext.save()
    }

    /// 개별 활용 이력만 지운다 — 확인 대화상자 없이 즉시 실행(Document/
    /// WordNote 컨텍스트 메뉴 삭제와 같은 관례).
    private func deleteDelivery(_ delivery: SermonDelivery) {
        modelContext.delete(delivery)
        try? modelContext.save()
    }

    // MARK: - 새 설교

    /// [2026-09-29 재수정] "새 설교" 버튼이 직접 부르는 함수 — 시트를 거치지
    /// 않고, 아직 `modelContext`에 insert하지 않은 `Sermon`을 하나 만들어
    /// `pendingNewSermon`에 담기만 한다. 실제 화면 전환(아이폰 push/아이패드·
    /// 맥 오른쪽 패널 전환)은 이 값을 읽는 `body`/`splitContent`가 맡고,
    /// 실제 insert는 `SermonEditorView.save()`가 제목/본문 중 하나라도
    /// 채워졌을 때만 한다(위 파일 상단 주석 [2026-09-29 재수정] 참고).
    private func startNewSermon() {
        pendingNewSermon = Sermon(title: "")
    }
}
