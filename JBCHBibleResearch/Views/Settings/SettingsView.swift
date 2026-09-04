//
//  SettingsView.swift
//  JBCHBibleResearch
//
//  screens.md 8장(환경설정) — macOS는 `Settings { SettingsView() }` Scene에
//  얹혀 표준 환경설정 창(고정 크기, 리사이즈 불가)으로 뜬다. iPadOS/iPhone엔
//  macOS의 `Settings` Scene 자체가 없어(iOS엔 이 API가 없다), "더보기" 진입점에서
//  시트로 띄운다(SettingsPlaceholderView 자리를 대신하는 SettingsHostView 참고).
//
//  ⚠️ [정직하게 표시] 각 탭 항목 중 실제로 다른 화면의 동작에 연결된 것과, UI만
//  있고 실제 백엔드가 없는 것을 아래 각 탭 주석에 명시했다 — 있어 보이지만 아무
//  일도 안 하는 컨트롤을 만들지 않기 위해서다(과장 없이 정직하게 표시하는 원칙).
//  연결된 것: 시작 시 마지막 화면/기본 번역본, AI 초안 토글, 화면 모드, 글꼴/
//  본문 크기/절 번호 크기/줄간격/색상, 성경 구절 복사 형식, 번역본 추가/삭제.
//  [2026-09-03 정정] 아래 "TranslationImportSheet에 연결돼 실제로 동작한다"
//  문구가 가리키던 TranslationManagementView.swift는 번역본 화면 통합(사용자
//  결정 — "더보기 > 설정 > 성경 > 번역본으로 통합, 더보기 > 번역본 관리 삭제")
//  으로 삭제됐다 — 그 기능은 이제 `TranslationsManagementTab`(아래 "번역본"
//  MARK 섹션) 하나가 전담한다.
//  [2026-08-11 정정, 아래 "저장공간" 섹션 주석 참고] "저장공간"은 더 이상
//  UI만 있는 상태가 아니다 — `DocumentUploadService.copyIntoICloudDocuments`가
//  실제로 그 경로에 파일을 복사한다(단, iCloud 컨테이너를 못 쓰면 조용히
//  원본 위치 참조로 폴백 — 그 경우는 화면에 실시간 반영 안 됨). 이 줄은 그
//  변경 전 상태를 가리키던 것이라 남겨 두면 혼동을 준다.
//  UI만 있는 것: 단축키(재지정 불가, 고정 목록만 표시).
//  [2026-08-07] "번역본 추가..."는 S12(번역본 관리) 구현과 함께
//  TranslationImportSheet에 연결돼 실제로 동작한다(TranslationManagementView.swift 참고).
//  [2026-08-08] "폰트"(S1 본문 크기/색상/절 번호 크기/줄간격/글꼴)와 "복사 형식"
//  (성경 구절 클립보드 복사 서식)도 실제로 동작한다 — `TranslationColumnView`/
//  `BibleVerseCopyFormatter` 참고.
//  [2026-08-11] 사용자 요청 세 가지 반영:
//  1) 화면 디자인 개선 — 각 탭에 `.formStyle(.grouped)`와 아이콘이 붙은 섹션
//     헤더/설명(footer)를 적용해 내용별 구분과 가독성을 높였다(전체 기능/저장
//     로직은 그대로, 표시 방식만 바꿨다).
//  2) "동기화" 탭 삭제 — CloudKit 동기화 상태는 대부분 UI만 있고 실제로 값이
//     의미 있게 동작하지 않아(SyncSettingsTab 옛 주석 참고) 혼동만 준다는
//     판단으로 탭 자체를 없앴다. 관련 UserSettingsStore.lastManualSyncAt
//     프로퍼티는 다른 화면이 참조하지 않아 그대로 둬도 무해하므로 남겨뒀다.
//  3) [1차 요청은 "S1 성경 조회 글꼴"과 혼동해 잘못 반영했다가, 재요청으로 정정]
//     "환경설정 화면 자체의 메뉴/타이틀"을 시스템 기본 글꼴·보통 크기로 바꿨다
//     — macOS는 JBCHBibleResearchApp.swift의 `Settings` Scene에서
//     `.appDefaultFont()`(내장 Paperlogy 강제)를 빼서, iOS는 아래
//     SettingsHostView에 `.font(.body)`를 명시해서 처리했다. "모양" 탭이
//     제공하는 S1(성경 조회) 본문 글꼴 설정(UserSettingsStore.bibleFontName)은
//     이 요청과 무관해 원래 기본값(내장 Paperlogy)으로 그대로 둔다.
//

import SwiftUI
import SwiftData
import BibleResearchModels
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

// [2026-08-21 갱신] 사용자 요청(공통 — macOS/iOS 둘 다) — "일반 - 상위 탭
// 추가: 기본/라이센스/단축키. 성경 - 상위 탭 추가: 번역본/모양/복사 형식.
// 저장공간 탭 삭제. AI 탭 삭제." 기존엔 8개 탭이 한 줄로 나란히 있었는데,
// 이제 최상위는 "일반"/"성경" 두 탭(+ DEBUG 전용 "개발자")뿐이고, 그 안에
// 하위 탭을 다시 두는 2단 구조다 — 아래 `GeneralSettingsGroup`/
// `BibleSettingsGroup`이 그 하위 탭 전환을 담당한다. "AI"/"저장공간" 탭은
// 자리 자체를 없앴다(위 `AISettingsTab`/`StorageSettingsTab` 삭제 주석 참고).
// [2026-08-25 정정] 하위 탭은 처음엔 `TabView` 중첩으로 구현했었으나, macOS
// 데스크톱에서 그 안쪽 TabView가 아예 렌더링되지 않는 문제가 실기기에서
// 확인돼 `Picker(...).pickerStyle(.segmented)` 기반 전환으로 바꿨다 — 상세
// 원인은 `GeneralSettingsGroup`/`BibleSettingsGroup` 선언부 주석 참고.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsGroup()
                .tabItem { Label("일반", systemImage: "gearshape") }
            BibleSettingsGroup()
                .tabItem { Label("성경", systemImage: "book.closed") }
            // [2026-08-14 복원] 사용자 지적 — "개요 시딩을 리치 에디터로 작성하고
            // 싶어서 임시(배포시 제외) 페이지를 요청했는데 왜 평문 JSON 방식으로
            // 마음대로 바꿨나." 개요 화면(`OutlineBookBulkEditView`) 자체가 이미
            // 리치 에디터 서식을 완전히 지원하므로 새 에디터를 만들 필요는 없고,
            // 그 화면에서 작성한 결과(서식 포함 RTF)를 배포용 시드 파일로 뽑아내는
            // "내보내기" 기능만 개발자 전용으로 복원하면 된다 — OutlineSeedExporter.swift
            // 참고. #if DEBUG로 배포 빌드에서는 이 탭 자체가 빠진다. 이 탭은 이번
            // 재구성 요청 대상이 아니라 최상위에 그대로 남겨뒀다.
            #if DEBUG
            DeveloperSettingsTab()
                .tabItem { Label("개발자", systemImage: "hammer") }
            #endif
        }
        #if os(macOS)
        .frame(width: 560, height: 480)
        #endif
    }
}

/// [2026-08-25 수정] 사용자 신고 — macOS 데스크톱 앱에서 이 하위 탭들이 아예
/// 보이지 않고 눌러도 반응이 없음(실기기 재현으로 확인됨). 원인: 여기서
/// `TabView`를 다시 `TabView` 안에 중첩하고 있었는데, macOS에서는 최상위
/// TabView(SettingsView.body, `Settings { }` Scene의 루트)만 환경설정 창
/// 전용 렌더링(윈도우 툴바의 세그먼트 아이콘)을 받고, 이 안쪽에 중첩된
/// TabView는 그 처리를 받지 못해 탭 전환 UI 자체가 그려지지 않았다 — iOS의
/// 기본(바닥) 탭 바처럼 중첩 상태에서도 자체 UI를 그려 주는 폴백이 macOS
/// TabView에는 없다. 같은 파일 안에서 이미 검증된 대안 패턴 —
/// `AppearanceSettingsTab`/`BibleCopyFormatSettingsTab`이 쓰는
/// `Picker(...).pickerStyle(.segmented)` — 로 바꿔, 진짜 TabView를 중첩하지
/// 않고 선택 상태(@State)에 따라 하위 화면만 전환한다. 하위 탭 뷰
/// (GeneralSettingsTab/LicenseSettingsTab/ShortcutsSettingsTab 등) 자체는
/// 전혀 손대지 않았다 — 감싸는 방식만 바뀌었을 뿐 내용/저장 로직은 동일하다.
private struct GeneralSettingsGroup: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case basic, license, shortcuts
        var id: Self { self }
        var title: String {
            switch self {
            case .basic: return "기본"
            case .license: return "라이센스"
            case .shortcuts: return "단축키"
            }
        }
    }

    @State private var selection: Tab = .basic

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selection) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top])

            Group {
                switch selection {
                case .basic:
                    GeneralSettingsTab()
                case .license:
                    LicenseSettingsTab()
                case .shortcuts:
                    ShortcutsSettingsTab()
                }
            }
        }
    }
}

/// [2026-08-25 수정] 위 `GeneralSettingsGroup`과 같은 원인·같은 방식으로 중첩
/// TabView를 세그먼트 Picker로 교체했다 — 하위 탭 뷰(TranslationsSettingsTab/
/// AppearanceSettingsTab/BibleCopyFormatSettingsTab) 자체는 그대로다.
private struct BibleSettingsGroup: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case translations, appearance, copyFormat
        var id: Self { self }
        var title: String {
            switch self {
            case .translations: return "번역본"
            case .appearance: return "모양"
            case .copyFormat: return "복사 형식"
            }
        }
    }

    @State private var selection: Tab = .translations

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selection) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top])

            Group {
                switch selection {
                case .translations:
                    TranslationsSettingsTab()
                case .appearance:
                    AppearanceSettingsTab()
                case .copyFormat:
                    // [2026-08-08 추가] 사용자 요청 — 성경 구절 클립보드 복사 형식(참조 위치/
                    // 괄호 스타일/약어/번역본 위치/줄바꿈/절 번호 스타일)을 위한 탭.
                    BibleCopyFormatSettingsTab()
                }
            }
        }
    }
}

/// iPadOS/iPhone "더보기" 진입점 — macOS의 `Settings` Scene과 달리 별도 창 개념이
/// 없어 시트로 감싸고 닫기 버튼을 붙인다.
///
/// [2026-08-11 추가] 사용자 요청 — "환경설정의 메뉴/타이틀은 시스템 기본 글꼴,
/// 보통 크기로". 이 시트는 RootView(`.appDefaultFont()` = 내장 Paperlogy 강제)
/// 안에서 `.sheet(...)`로 뜨기 때문에 아무것도 안 하면 그 폰트를 그대로
/// 상속받는다 — `.font(.body)`로 명시적으로 시스템 기본 글꼴/보통 크기(Dynamic
/// Type 표준 스타일)로 덮어써서 macOS `Settings` Scene(JBCHBibleResearchApp.swift,
/// 거기도 같은 이유로 `.appDefaultFont()`를 붙이지 않는다)과 동작을 맞췄다.
struct SettingsHostView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SettingsView()
                .navigationTitle("설정")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("닫기") { dismiss() }
                    }
                }
        }
        .font(.body)
    }
}

// MARK: - 일반

/// [2026-09-03 개정] 사용자 요청 — "더보기 - 설정의 [일반], [성경] 그리고 그
/// 각각 하위 메뉴들을 한 화면에 통합할 수 있도록." 원래 이 화면은 "일반"/
/// "성경"/"개발자" 세 카테고리만 보여주고, 그 하위 항목(기본/라이센스,
/// 번역본/모양/복사 형식)은 각각 한 번 더 눌러 들어가야 하는 `GeneralSettingsListView`/
/// `BibleSettingsListView`(두 화면 모두 아래에서 지웠다)로 갈라져 있었다 —
/// 3단 드릴다운(설정 → 일반/성경 → 그 하위 항목)이었던 것을, 여기 한 화면
/// 안에 "일반"/"성경"을 `Section` 헤더로 두고 그 아래 하위 항목을 바로
/// 늘어놓는 2단 구조(설정 → 하위 항목)로 평평하게 폈다. "개발자"는 원래도
/// 하위 항목이 없는 단일 항목이라(DEBUG 전용) 그대로 별도 섹션에 둔다. 각
/// 항목의 아이콘 배지(`SettingsCategoryRow`)와 목적지 화면(`GeneralSettingsTab`/
/// `LicenseSettingsTab`/`TranslationsManagementTab`/`AppearanceSettingsTab`/
/// `BibleCopyFormatSettingsTab`/`DeveloperSettingsTab`)은 전혀 손대지 않고
/// 그대로 재사용한다 — 이 화면이 바꾸는 것은 오직 "몇 번 눌러야 거기 닿는지"
/// 뿐이다.
///
/// [이전 안, 참고] 원래(2026-09-03 이전) 여기 있던 설계 — "더보기"의 "설정"
/// 항목이 다른 진입점과 달리 `SettingsView()`(macOS `Settings` Scene용
/// 최상위 `TabView`)를 그대로 push해 하단에 탭바가 이중으로 뜨던 문제를,
/// 아이콘 목록 화면으로 바꿔 해결했던 것 — 은 그대로 유효하다. macOS
/// (`Settings` Scene, 독립된 환경설정 창)와 iPadOS(`SettingsHostView`를
/// `.sheet`로, 독립된 모달)는 이 문제 자체가 없어 그대로 뒀고, iPhone 전용
/// 진입점만 계속 이 화면(`SettingsHomeView`)을 쓴다.
struct SettingsHomeView: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    GeneralSettingsTab()
                        .navigationTitle("기본")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                } label: {
                    SettingsCategoryRow(title: "기본", systemImage: "gearshape.fill", tint: JBCHCategoryPalette.wood)
                }
                NavigationLink {
                    LicenseSettingsTab()
                        .navigationTitle("라이센스")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                } label: {
                    SettingsCategoryRow(title: "라이센스", systemImage: "checkmark.seal.fill", tint: JBCHCategoryPalette.shelfSlate)
                }
                // [2026-09-03 삭제] 사용자 요청 — "아이폰 쪽에서는 단축키 내용을
                // 뺄 것." `ShortcutsSettingsTab`이 보여주는 내용(⌘/⌥/⇧ 등 macOS/
                // 하드웨어 키보드 단축키, `ShortcutsSettingsTab` 선언부 참고)
                // 자체가 아이폰에는 해당하지 않아 이 목록에서만 뺐다 — macOS
                // `Settings` Scene과 iPadOS `.sheet`가 쓰는 `GeneralSettingsGroup`
                // (아래 참고)의 "단축키" 세그먼트는 그대로 남아 있고,
                // `ShortcutsSettingsTab` 자체도 지우지 않았다(그 두 플랫폼에서는
                // 여전히 유효한 내용이라 이 화면 이외에는 영향이 없다).
            } header: {
                // [2026-09-03 추가] 사용자 요청 — "일반, 성경의 중간 타이틀의
                // 글자를 조금더 키우고 굵게 할것." `Section("일반")`처럼 문자열을
                // 바로 주면 시스템 기본 섹션 헤더 스타일(작은 크기·보통 굵기)이
                // 적용된다 — 그 크기/굵기만 키우기 위해 커스텀 `header:` 뷰로
                // 바꿨다. 색상(`.secondary`)과 좌우 위치 등 그 외 스타일은
                // 기존 그대로 유지한다.
                Text("일반")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
            }

            Section {
                NavigationLink {
                    TranslationsManagementTab()
                        .navigationTitle("번역본")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                } label: {
                    SettingsCategoryRow(title: "번역본", systemImage: "books.vertical.fill", tint: JBCHCategoryPalette.navy)
                }
                NavigationLink {
                    AppearanceSettingsTab()
                        .navigationTitle("모양")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                } label: {
                    SettingsCategoryRow(title: "모양", systemImage: "paintpalette.fill", tint: JBCHCategoryPalette.gold)
                }
                NavigationLink {
                    BibleCopyFormatSettingsTab()
                        .navigationTitle("복사 형식")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                } label: {
                    SettingsCategoryRow(title: "복사 형식", systemImage: "doc.on.doc.fill", tint: JBCHCategoryPalette.wine)
                }
            } header: {
                // 위 "일반" 섹션 헤더와 같은 이유·같은 스타일.
                Text("성경")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
            }

            #if DEBUG
            Section {
                NavigationLink {
                    DeveloperSettingsTab()
                        .navigationTitle("개발자")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                } label: {
                    SettingsCategoryRow(title: "개발자", systemImage: "hammer.fill", tint: Color(white: 0.35))
                }
            }
            #endif
        }
        .navigationTitle("설정")
        // [2026-09-03 추가] 사용자 보고 — "더보기 - 설정 이하 메뉴에 공통적으로
        // 뒤로가기 아이콘과 그 밑에 타이틀이 있는데 뒤로가기 아이콘 우측 영역
        // 빈공간이 낭비되고 있음." 기본(automatic) 표시 모드는 뒤로가기
        // 버튼만 있는 좁은 줄 아래에 큰 제목을 별도 줄로 한 번 더 그려, 그
        // 뒤로가기 버튼 옆(같은 줄) 공간이 그대로 비어 낭비된다 — 이미 이
        // 코드베이스 다른 화면(`ChapterRelatedContentPanel`/`BibleReadingView`/
        // `VerseZoomView`/`CrossReferenceTargetPicker`/`DocumentsHomeView`/
        // `OriginalTextInfoView`)에서 같은 이유로 확인·적용해 둔 대안 —
        // `.navigationBarTitleDisplayMode(.inline)` — 을 그대로 재사용해 뒤로가기
        // 버튼과 제목을 한 줄로 합친다(macOS엔 이 모디파이어 자체가 없어
        // `#if os(iOS)`로 감싼다).
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // `SettingsHostView`와 같은 이유(위 주석 참고) — 이 화면도 NavigationLink
        // push로 열리므로 명시적으로 시스템 기본 글꼴/보통 크기로 되돌린다.
        .font(.body)
    }
}

/// 위 `SettingsHomeView`의 각 행 — iOS "설정" 앱과 같은 "색이 있는 둥근 사각형
/// 배경 위 흰색 SF Symbol" 아이콘 스타일. 아이콘마다 시스템이 주는 기본 크기를
/// 그대로 쓰지 않고 고정 프레임(29pt, iOS 설정 앱 실측과 동일)으로 통일해
/// 목록 전체의 세로 정렬이 흔들리지 않게 한다.
private struct SettingsCategoryRow: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint.gradient)
                .frame(width: 29, height: 29)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                }
        }
    }
}

// MARK: - 일반

// [2026-08-21 갱신] 사용자 요청 — "일반 - 상위 탭 추가: 기본/라이센스/단축키.
// 기본 탭 에다 일반 에 있는 기능 + 정보의 앱 정보." 이 탭이 새 "기본" 하위 탭이
// 되고, 옛 "정보" 탭(지금은 `LicenseSettingsTab`, 아래 MARK 참고) 맨 위에 있던
// "앱 정보" Section(이름/버전)을 그대로 여기로 옮겨왔다 — 그 Section이 쓰던
// `versionString`/`buildString`도 함께 옮겼다(옛 "정보" 탭 나머지 내용 중 이
// 둘을 쓰는 곳이 없음을 확인 후 이동, 복사가 아님).
private struct GeneralSettingsTab: View {
    @State private var settings = UserSettingsStore.shared

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    // [2026-08-11 변경] 사용자 요청 — 앱 이름을 "JBCH 성경 연구"로
                    // 변경(프로젝트 코드명 "JBCHBibleResearch"는 내부 식별자로만
                    // 남고, 사용자에게 보이는 이름은 여기와 앱 번들 표시 이름
                    // 둘 다 바꿨다 — project.pbxproj의 INFOPLIST_KEY_CFBundleDisplayName
                    // 참고).
                    Text("JBCH 성경 연구")
                        .font(.headline)
                    Text("버전 \(versionString) (\(buildString))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("앱 정보", systemImage: "info.circle")
            }

            Section {
                Toggle("시작 시 마지막으로 보던 화면 열기", isOn: $settings.openLastScreenOnLaunch)
            } header: {
                Label("시작 옵션", systemImage: "power")
            }

            // [2026-08-26 삭제] 사용자 보고 — "설정...->일반 -> 기본 -> 성경
            // 조회 기본값 : 동작하지 않음 --> 제거." 여기 있던 "기본 성경
            // 번역본" 피커(`settings.defaultTranslationCode`)를 없앴다 — 자세한
            // 원인은 `TranslationsSettingsTab`의 "성경 조회 기본 표시" 섹션
            // 상단 주석 참고(요약: 그 탭을 한 번이라도 열면 그 뒤로는 이 값이
            // 다시 반영될 길이 없어 사실상 죽은 컨트롤이었다). 대신 그 탭의
            // "성경 조회 기본 표시" 목록 하나가 순서(드래그로 변경 가능)까지
            // 포함해 기본값을 전담한다. `defaultTranslationCode` 프로퍼티
            // 자체(`UserSettingsStore`)와 그 값을 읽는 두 폴백 경로
            // (`BibleReadingViewModel.loadAvailableTranslations`/
            // `TranslationsSettingsTab.seedDefaultDisplayedCodesIfNeeded`)는
            // 그대로 남겨 뒀다 — 이 값을 바꿀 UI가 이제 없으니 항상 nil이라
            // 실질적으로 동작하지 않지만, "성경 조회 기본 표시" 목록이 아직
            // 한 번도 채워지지 않은 이론상의 상태(예: 기존 사용자의 예전
            // 선택값 이전)에 대한 안전한 폴백으로는 여전히 무해하다 — 요청
            // 범위는 "설정 화면의 그 컨트롤 제거"였지 그 하부 폴백 로직 삭제가
            // 아니었다.
        }
        .formStyle(.grouped)
    }

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildString: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}

// MARK: - 번역본

private struct TranslationsSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @State private var translations: [TranslationRegistry] = []
    @State private var settings = UserSettingsStore.shared
    // [2026-08-07] S12(번역본 관리)가 구현되면서 이 탭도 TranslationImportSheet를
    // 공유해 실제로 동작하게 됐다 — 아래 "번역본 추가..." 버튼 참고.
    @State private var isImportSheetPresented = false

    var body: some View {
        Form {
            Section {
                ForEach(translations, id: \.id) { translation in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(translation.displayName)
                            Text(statusText(for: translation))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !translation.isBundled {
                            Button(role: .destructive) {
                                delete(translation)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            } header: {
                Label("설치된 번역본", systemImage: "text.book.closed")
            }

            // [2026-08-07 추가, 원본 문서 재확인으로 발견한 누락] screens.md 8.3
            // "성경 조회 기본 표시 3개 체크박스 선택" — 지금까지 이 탭엔
            // 목록/추가/삭제만 있고 이 항목이 빠져 있었다. UserSettingsStore
            // .defaultDisplayedTranslationCodes에 최대 3개까지 저장한다.
            // [2026-08-11 변경] 사용자 요청 — "기본 OFF를 기본 ON으로, 끄면
            // 안 나오는 것으로". 예전에는 이 목록이 비어 있으면(토글이 전부
            // 꺼진 것처럼 보여도) BibleReadingViewModel이 "등록 순서대로 자동
            // 선택"하는 폴백을 태워 실제로는 번역본이 표시됐다 — 토글 상태와
            // 실제 동작이 어긋나는 문제였다. 이제 이 탭이 처음 열릴 때(아직 아무
            // 것도 저장돼 있지 않을 때) `seedDefaultDisplayedCodesIfNeeded()`가
            // 등록 순서(+ 기본 번역본 맨 앞) 규칙 그대로 최대 3개를 미리 채워
            // 넣어서, 토글이 켜져 있는 것 = 실제로 보인다는 뜻이 정확히 일치하게
            // 했다. 이후 토글을 끄면 목록에서 실제로 빠지므로 자동 선택 폴백
            // 문구도 더 이상 필요 없어 지웠다.
            // [2026-08-26 재작성] 사용자 보고 — "설정...->일반 -> 기본 ->
            // 성경 조회 기본값 : 동작하지 않음." 실제 원인: 이 탭이 처음 열릴
            // 때마다 `seedDefaultDisplayedCodesIfNeeded()`가 그 시점의
            // `defaultTranslationCode`(일반 탭의 그 피커) 값을 한 번 반영해
            // `defaultDisplayedTranslationCodes`(바로 이 목록)를 채워 넣는데,
            // 그 뒤로는 `BibleReadingViewModel.loadAvailableTranslations()`가
            // "8.3(이 목록)이 있으면 최우선"이라 8.1(그 피커)은 이미 채워진
            // 뒤로는 다시 반영될 길이 영영 없다 — 즉 이 번역본 탭을 한 번이라도
            // 연 이후로는 그 피커를 바꿔도 실제 표시엔 아무 영향이 없었다.
            // 사용자 요청대로 그 피커는 없애고(위 `GeneralSettingsTab` 참고),
            // 이 목록 자체를 "드래그로 순서를 바꿀 수 있고, 맨 위가 기본값"인
            // 진짜 단일 설정으로 승격한다 — 순서가 실제 성경 조회 컬럼 순서로
            // 이어지는 것은 이미 위 `loadAvailableTranslations()`의
            // `preferredCodes.compactMap { byCode[$0] }`가 배열 순서를 그대로
            // 따르고 있어(멤버십 필터가 아니라 순서 있는 매핑), 별도로 고칠
            // 필요가 없었다 — 여기 목록 자체가 정확한 순서로 저장되기만 하면
            // 된다.
            // [2026-08-27 재작성] 사용자 보고 — "설치된 성경을 보이게/안보이게
            // 하는 옵션이 사라졌음, 드래그로 순서를 바꿀 수 없음." 원인:
            // 바로 위 `editMode` 컴파일 에러와 같은 근본 원인이었다 —
            // `.onMove`/`.onDelete`는 실제 드래그 손잡이나 스와이프-삭제
            // 버튼 같은 조작 UI를 `List`가 그려 주는 경우에만 동작하는데,
            // 이 화면은 `Form { Section { ForEach ... } } `이라 (특히 macOS
            // `.formStyle(.grouped)`에서는) 그 조작 UI 자체가 전혀 나타나지
            // 않는다 — 클로저 자체는 멀쩡해도 사용자가 그것을 트리거할 방법이
            // 없었다는 뜻. 그 결과 "표시 중인 번역본을 뺄" 방법이 아예 없어,
            // 3개가 이미 차 있으면 나머지 설치된 번역본은 "추가" 버튼이
            // 비활성화된 채로만 보여 "옵션이 사라진 것"처럼 보였다. `List`의
            // 암묵적 제스처 UI에 다시 기대는 대신, 평범한 버튼 탭(모든
            // 플랫폼에서 동일하게 동작)으로 표시/숨김·순서 변경을 명시적으로
            // 구현한다 — macOS Form의 드래그/스와이프 지원 여부를 또 추측하지
            // 않기 위해서다.
            Section {
                ForEach(allTranslationsOrderedForDisplaySettings, id: \.id) { translation in
                    translationDisplayRow(translation)
                }
            } header: {
                Label("성경 조회 기본 표시", systemImage: "eye")
            } footer: {
                Text("최대 3개까지 표시할 수 있습니다. 맨 위가 기본값입니다. 눈 아이콘으로 표시 여부를, 위/아래 화살표로 순서를 바꿀 수 있습니다.")
            }

            Section {
                Button {
                    isImportSheetPresented = true
                } label: {
                    Label("번역본 추가...", systemImage: "plus.circle")
                }
            } footer: {
                // [2026-08-11 추가] 사용자 요청 — 업로드 형식/책임 범위/개인정보
                // 안내를 버튼 아래에 명시.
                Text("sqlite, bdb 파일을 업로드할 수 있습니다.\n\n이 앱은 성경 번역본을 제공하거나 배포하지 않습니다. 사용자가 적법하게 보유하거나 사용할 권한이 있는 파일만 가져와주십시오. 가져온 데이터는 이 기기에만 저장되며, 다른 사용자와 공유되지 않습니다.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            reload()
            seedDefaultDisplayedCodesIfNeeded()
        }
        .sheet(isPresented: $isImportSheetPresented) {
            TranslationImportSheet { _ in reload() }
        }
    }

    /// [2026-08-11 신설] 위 "기본 ON" 변경의 실제 구현 — 아직 아무 번역본도
    /// 명시적으로 고르지 않은 상태(최초 진입)라면, BibleReadingViewModel의 기존
    /// 폴백 규칙("등록 순 + defaultTranslationCode 맨 앞", 최대 3개)과 똑같은
    /// 순서로 목록을 만들어 저장소에 미리 써 둔다. 이렇게 하면 토글이 화면에
    /// "켜짐"으로 보이는 상태가 실제 S1 표시 상태와 항상 일치한다 — 더 이상
    /// "빈 목록 = 자동 선택"이라는 암묵적 규칙에 의존하지 않는다.
    private func seedDefaultDisplayedCodesIfNeeded() {
        guard settings.defaultDisplayedTranslationCodes.isEmpty, !translations.isEmpty else { return }
        var ordered = translations
        if let preferredCode = settings.defaultTranslationCode,
           let index = ordered.firstIndex(where: { $0.code == preferredCode }) {
            let preferred = ordered.remove(at: index)
            ordered.insert(preferred, at: 0)
        }
        settings.defaultDisplayedTranslationCodes = Array(ordered.prefix(3).map(\.code))
    }

    private func statusText(for translation: TranslationRegistry) -> String {
        var parts = [translation.isBundled ? "번들" : "사용자 추가", translation.licenseType ?? "라이선스 미상"]
        if !translation.isBundled {
            parts.append(TranslationFileMaterializer.syncStatus(for: translation).label)
        }
        return parts.joined(separator: " · ")
    }

    /// [2026-08-26 신설] 위 "성경 조회 기본 표시" 섹션 재작성 참고 —
    /// `defaultDisplayedTranslationCodes`(순서 있는 코드 배열)를 실제
    /// `TranslationRegistry`로 그 순서 그대로 매핑한다. 코드에 대응하는
    /// 번역본이 사라졌으면(삭제됨) `compactMap`이 조용히 건너뛴다 —
    /// `BibleReadingViewModel.loadAvailableTranslations()`의 "더 이상 존재하지
    /// 않는 선택은 걸러낸다"와 같은 방어.
    private var orderedDisplayedTranslations: [TranslationRegistry] {
        let byCode = Dictionary(uniqueKeysWithValues: translations.map { ($0.code, $0) })
        return settings.defaultDisplayedTranslationCodes.compactMap { byCode[$0] }
    }

    /// 아직 표시 목록에 없는 번역본 — 아래 통합 목록의 뒤쪽 절반에 쓴다.
    private var notYetDisplayedTranslations: [TranslationRegistry] {
        let shown = Set(settings.defaultDisplayedTranslationCodes)
        return translations.filter { !shown.contains($0.code) }
    }

    /// [2026-08-27 신설] 위 섹션 재작성 참고 — 표시 중인 번역본(순서대로) +
    /// 표시하지 않는 번역본을 이어 붙인 한 줄짜리 목록. "설치된 번역본
    /// 전체를 놓고 각각 보이게/안보이게 고른다"는 사용자가 기억하는 예전
    /// UX(토글 방식)를 그대로 복원하면서, 순서 정보(표시 중인 것만 앞쪽에
    /// 그 순서 그대로)도 한 목록 안에서 같이 보여준다.
    private var allTranslationsOrderedForDisplaySettings: [TranslationRegistry] {
        orderedDisplayedTranslations + notYetDisplayedTranslations
    }

    /// [2026-08-27 신설] 표시 중인 번역본은 순서 배지(맨 위 "기본")와 위/아래
    /// 화살표(인접한 두 항목을 맞바꾸는 것만으로 충분 — 한 번에 한 칸씩만
    /// 옮기므로 `swapAt`이 `move(fromOffsets:toOffset:)`보다 오히려 더
    /// 단순하고 경계 조건이 분명하다)를, 표시하지 않는 번역본은 "표시" 눈
    /// 아이콘 버튼만 보여준다.
    @ViewBuilder
    private func translationDisplayRow(_ translation: TranslationRegistry) -> some View {
        let displayedIndex = settings.defaultDisplayedTranslationCodes.firstIndex(of: translation.code)
        HStack {
            Text(translation.displayName)
            if displayedIndex == 0 {
                // "맨 위쪽이 기본 값이라는 것을 나타낼 수 있도록"
                Text("기본")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
            }
            Spacer()
            if let index = displayedIndex {
                Button {
                    moveDisplayedTranslation(from: index, to: index - 1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(index == 0)

                Button {
                    moveDisplayedTranslation(from: index, to: index + 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(index == settings.defaultDisplayedTranslationCodes.count - 1)

                Button {
                    removeDisplayedTranslation(code: translation.code)
                } label: {
                    Image(systemName: "eye.slash")
                }
                .buttonStyle(.borderless)
            } else {
                Button {
                    addDisplayedTranslation(translation)
                } label: {
                    Image(systemName: "eye")
                }
                .buttonStyle(.borderless)
                // [2026-08-27 수정] 사용자 보고 — "성경 조회 기본표시가 3번째
                // 활성화가 되지 않음." 원인: 삭제된 번역본의 코드가
                // `defaultDisplayedTranslationCodes`(원시 저장 배열)에 그대로
                // 남아 있으면(바로 아래 `delete(_:)` 수정 참고), 실제로 화면에
                // "표시 중"으로 보이는 항목은 2개뿐인데도 원시 배열 길이는
                // 여전히 3이라 이 조건이 계속 true가 돼 새 번역본을 추가할 수
                // 없었다. 실제 화면에 뜨는 유효한 항목 수(`orderedDisplayedTranslations`
                // — 존재하지 않는 코드는 이미 걸러진 목록, 위 프로퍼티 주석
                // 참고)를 기준으로 판정하도록 바꿨다.
                .disabled(orderedDisplayedTranslations.count >= 3)
            }
        }
    }

    /// 표시 중인 두 항목(`index`, `index`±1)을 맞바꾼다 — 위/아래 화살표가 항상
    /// 인접한 위치로만 옮기므로 `swapAt` 하나로 충분하고, 둘 다 유효한 인덱스일
    /// 때만 수행해 경계에서 죽지 않는다(호출부에서 이미 `.disabled`로 막지만
    /// 방어적으로 한 번 더 확인).
    private func moveDisplayedTranslation(from index: Int, to newIndex: Int) {
        var codes = settings.defaultDisplayedTranslationCodes
        guard codes.indices.contains(index), codes.indices.contains(newIndex) else { return }
        codes.swapAt(index, newIndex)
        settings.defaultDisplayedTranslationCodes = codes
    }

    private func removeDisplayedTranslation(code: String) {
        settings.defaultDisplayedTranslationCodes.removeAll { $0 == code }
    }

    /// "최대 3개까지"(기존 규칙 그대로) — 이미 가득 찼으면 버튼이 비활성화돼
    /// 있으므로(호출부 `.disabled`) 여기서 다시 개수를 확인할 필요는 없지만,
    /// 방어적으로 한 번 더 막는다.
    private func addDisplayedTranslation(_ translation: TranslationRegistry) {
        guard settings.defaultDisplayedTranslationCodes.count < 3,
              !settings.defaultDisplayedTranslationCodes.contains(translation.code) else { return }
        settings.defaultDisplayedTranslationCodes.append(translation.code)
    }

    private func reload() {
        translations = (try? modelContext.fetch(FetchDescriptor<TranslationRegistry>(sortBy: [SortDescriptor(\.addedAt)]))) ?? []
    }

    private func delete(_ translation: TranslationRegistry) {
        // [2026-09-03 정정] 원래 "TranslationManagementViewModel.delete(_:)와
        // 동일하게"였다 — 그 타입은 번역본 화면 통합(더보기 > 번역본 관리
        // 삭제)으로 사라졌다. 아래 `TranslationsManagementTab.delete(_:)`(같은
        // 파일, "번역본" MARK 섹션)가 이 함수를 그대로 포팅해 갔으니 이제는
        // "그 함수와 동일하게"로 읽으면 된다 — 로컬 캐시 파일도 함께
        // 정리한다(best-effort) — 두 곳에서 삭제 경로가 갈라지면서 한쪽만
        // 정리하면 디스크에 고아 파일이 남는다.
        TranslationFileMaterializer.removeLocalCopy(for: translation)
        // [2026-08-27 추가] 사용자 보고 — "성경 조회 기본표시가 3번째 활성화가
        // 되지 않음." 근본 원인: 이 함수가 번역본을 지우면서도
        // `defaultDisplayedTranslationCodes`(성경 조회 기본 표시 목록)에서 그
        // 코드를 빼지 않아, 삭제된 번역본의 코드가 저장소에 영구히 남아
        // "3개가 이미 찼다"는 판정을 계속 유발했다(위 `translationDisplayRow`
        // "add" 버튼 `.disabled` 수정 참고). 삭제 시점에 바로 정리해 이 문제가
        // 다시 쌓이지 않게 한다 — 기존 `removeDisplayedTranslation(code:)`를
        // 그대로 재사용(이미 없는 코드를 지워도 `removeAll`은 안전하게 무동작).
        removeDisplayedTranslation(code: translation.code)
        modelContext.delete(translation)
        try? modelContext.save()
        reload()
    }
}

/// [2026-09-03 신설] 사용자 결정 — "번역본 화면 통합안: 더보기 > 설정 > 성경 >
/// 번역본으로 통합(더보기 > 번역본 관리의 항목 삭제)." 이전에 두 화면으로
/// 나뉘어 있던 기능을 하나로 합쳤다 — 위 `TranslationsSettingsTab`의 "성경
/// 조회 기본 표시"(순서/노출 토글)와 "번역본 추가..."는 그대로 가져오고,
/// (이제 삭제된) `TranslationManagementView`/`TranslationManagementViewModel`
/// (더보기 > 번역본 관리)에만 있던 "표시 이름"/"라이선스" 인라인 편집과
/// "책이름표 언어" 피커를 그 목록 행에 그대로 옮겨왔다. `updateDisplayName`/
/// `updateLicenseType`이 타이핑마다 `reload()`를 다시 부르지 않는 것은
/// `TranslationManagementViewModel`의 원래 이유 그대로다 — 매 타자마다 전체
/// 목록을 다시 훑을 이유가 없어서다(SwiftData `@Model`은 자동으로 관찰되므로
/// 값만 바꿔도 화면이 갱신된다).
///
/// [삭제 UI, 사용자 질의 — "번역본 삭제기능은 어디있지?"] 옛 번역본 관리
/// 화면은 스와이프로만 삭제할 수 있었는데, 위 목업(정적 스크린샷)에는 스와이프
/// 제스처가 보이지 않아 이 질문이 나왔다. 이 화면이 합쳐 들어가는 대상인
/// `TranslationsSettingsTab`이 원래 쓰던 방식 — 각 행에 바로 보이는 휴지통
/// 아이콘 버튼(번들이 아닌 것만) — 을 그대로 유지해 숨겨진 제스처 없이 항상
/// 눈에 보이게 했다(옛 화면의 `.swipeActions`는 가져오지 않았다).
///
/// [동기화 상태 표시, 의도적으로 하나만 유지] 두 원본이 "동기화 상태"를 서로
/// 다른 방식으로 계산했다 — `TranslationsSettingsTab.statusText(for:)`는
/// `TranslationFileMaterializer.syncStatus(for:)`(그 파일 선언부 주석: "아무것도
/// 쓰지 않는" 순수 조회, 렌더링마다 불러도 안전)만 읽고, `TranslationManagementViewModel
/// .reload()`는 그 대신 매번 `ensureMaterialized`를 실제로 시도해(파일 쓰기
/// 부작용 있음, 66권 순회) 실패하면 별도 오류 배지를 보여줬다. 이 화면은 전자
/// (부작용 없는 `syncStatus`)만 유지한다 — 후자는 "번역본 조회 도중 화면을
/// 열 때마다 파일 쓰기를 시도"하는 무거운 동작이라, 화면을 하나로 합치면서
/// 더 자주(순서 변경/토글 때마다) 실행될 위험까지 새로 만들고 싶지 않았다.
/// 필요하시면(=이 사전 복구 동작을 실제로 원하시면) 알려주시면 다시 넣겠다.
///
/// macOS `Settings` Scene/iPadOS `.sheet`가 쓰는 원래 `TranslationsSettingsTab`
/// (위, 간단한 목록·편집 불가)은 그대로 남겨 뒀다 — 이번 통합은 "아이폰 →
/// 더보기 → 설정 → 성경 → 번역본" 화면 하나로 한정된 결정이라, 다른 두
/// 플랫폼에는 편집 기능이 새로 생기지 않는다.
private struct TranslationsManagementTab: View {
    @Environment(\.modelContext) private var modelContext
    @State private var translations: [TranslationRegistry] = []
    @State private var settings = UserSettingsStore.shared
    @State private var isImportSheetPresented = false

    var body: some View {
        Form {
            Section {
                ForEach(allTranslationsOrderedForDisplaySettings, id: \.id) { translation in
                    translationDisplayRow(translation)
                }
            } header: {
                Label("성경 조회 기본 표시", systemImage: "eye")
            } footer: {
                Text("최대 3개까지 표시할 수 있습니다. 맨 위가 기본값입니다. 눈 아이콘으로 표시 여부를, 위/아래 화살표로 순서를 바꿀 수 있습니다.")
            }

            Section {
                ForEach(translations, id: \.id) { translation in
                    translationEditRow(translation)
                }
            } header: {
                Label("설치된 번역본", systemImage: "text.book.closed")
            }

            Section {
                Button {
                    isImportSheetPresented = true
                } label: {
                    Label("번역본 추가...", systemImage: "plus.circle")
                }
            } footer: {
                Text("sqlite, bdb 파일을 업로드할 수 있습니다.\n\n이 앱은 성경 번역본을 제공하거나 배포하지 않습니다. 사용자가 적법하게 보유하거나 사용할 권한이 있는 파일만 가져와주십시오. 가져온 데이터는 이 기기에만 저장되며, 다른 사용자와 공유되지 않습니다.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            reload()
            seedDefaultDisplayedCodesIfNeeded()
        }
        .sheet(isPresented: $isImportSheetPresented) {
            TranslationImportSheet { _ in reload() }
        }
    }

    /// [`TranslationManagementView.TranslationRowView` 포팅] 표시 이름/라이선스
    /// 인라인 편집 + 책이름표 언어 피커 + (번들이 아니면) 삭제 버튼.
    @ViewBuilder
    private func translationEditRow(_ translation: TranslationRegistry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("표시 이름", text: Binding(
                    get: { translation.displayName },
                    set: { updateDisplayName($0, for: translation) }
                ))
                .font(.headline)
                #if os(iOS)
                .textFieldStyle(.roundedBorder)
                #else
                .textFieldStyle(.plain)
                #endif

                if !translation.isBundled {
                    Button(role: .destructive) {
                        delete(translation)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }

            Text(statusText(for: translation))
                .font(.caption2)
                .foregroundStyle(.secondary)

            TextField("라이선스(선택)", text: Binding(
                get: { translation.licenseType ?? "" },
                set: { updateLicenseType($0, for: translation) }
            ))
            .font(.caption)
            #if os(iOS)
            .textFieldStyle(.roundedBorder)
            #else
            .textFieldStyle(.plain)
            #endif

            Picker("책이름표 언어", selection: Binding(
                get: { translation.bookNameTableID },
                set: { setBookNameTable($0, for: translation) }
            )) {
                Text("한글 기본").tag(nil as String?)
                ForEach(BookNameTableProvider.shared.builtIn) { table in
                    Text(table.displayName).tag(table.id as String?)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    /// [`TranslationManagementViewModel.updateDisplayName` 포팅] 타이핑마다
    /// `reload()`를 다시 부르지 않는다 — `translation`이 이미 이 인스턴스를
    /// 그대로 참조하는 SwiftData `@Model`이라 값만 바꿔도 화면이 갱신된다.
    private func updateDisplayName(_ name: String, for registry: TranslationRegistry) {
        registry.displayName = name
        try? modelContext.save()
    }

    /// [`TranslationManagementViewModel.updateLicenseType` 포팅] 위와 동일한
    /// 이유로 `reload()` 없이 즉시 반영. 빈 문자열은 "라이선스 미상" 표시로
    /// 되돌아가도록 nil로 정규화한다.
    private func updateLicenseType(_ license: String, for registry: TranslationRegistry) {
        let trimmed = license.trimmingCharacters(in: .whitespacesAndNewlines)
        registry.licenseType = trimmed.isEmpty ? nil : trimmed
        try? modelContext.save()
    }

    /// [`TranslationManagementViewModel.setBookNameTable` 포팅] 번들 번역본도
    /// 원칙적으로는 바꿀 수 있게 막지 않는다 — 번들은 항상 nil이라는 규칙이
    /// 사용자가 바꾸는 것 자체를 금지한 근거는 아니라서다.
    private func setBookNameTable(_ tableID: String?, for registry: TranslationRegistry) {
        registry.bookNameTableID = tableID
        try? modelContext.save()
        reload()
    }

    private func statusText(for translation: TranslationRegistry) -> String {
        var parts = [translation.code, translation.isBundled ? "번들" : "사용자 추가"]
        if !translation.isBundled {
            parts.append(TranslationFileMaterializer.syncStatus(for: translation).label)
        }
        return parts.joined(separator: " · ")
    }

    private var orderedDisplayedTranslations: [TranslationRegistry] {
        let byCode = Dictionary(uniqueKeysWithValues: translations.map { ($0.code, $0) })
        return settings.defaultDisplayedTranslationCodes.compactMap { byCode[$0] }
    }

    private var notYetDisplayedTranslations: [TranslationRegistry] {
        let shown = Set(settings.defaultDisplayedTranslationCodes)
        return translations.filter { !shown.contains($0.code) }
    }

    private var allTranslationsOrderedForDisplaySettings: [TranslationRegistry] {
        orderedDisplayedTranslations + notYetDisplayedTranslations
    }

    @ViewBuilder
    private func translationDisplayRow(_ translation: TranslationRegistry) -> some View {
        let displayedIndex = settings.defaultDisplayedTranslationCodes.firstIndex(of: translation.code)
        HStack {
            Text(translation.displayName)
            if displayedIndex == 0 {
                Text("기본")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
            }
            Spacer()
            if let index = displayedIndex {
                Button {
                    moveDisplayedTranslation(from: index, to: index - 1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(index == 0)

                Button {
                    moveDisplayedTranslation(from: index, to: index + 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(index == settings.defaultDisplayedTranslationCodes.count - 1)

                Button {
                    removeDisplayedTranslation(code: translation.code)
                } label: {
                    Image(systemName: "eye.slash")
                }
                .buttonStyle(.borderless)
            } else {
                Button {
                    addDisplayedTranslation(translation)
                } label: {
                    Image(systemName: "eye")
                }
                .buttonStyle(.borderless)
                .disabled(orderedDisplayedTranslations.count >= 3)
            }
        }
    }

    private func moveDisplayedTranslation(from index: Int, to newIndex: Int) {
        var codes = settings.defaultDisplayedTranslationCodes
        guard codes.indices.contains(index), codes.indices.contains(newIndex) else { return }
        codes.swapAt(index, newIndex)
        settings.defaultDisplayedTranslationCodes = codes
    }

    private func removeDisplayedTranslation(code: String) {
        settings.defaultDisplayedTranslationCodes.removeAll { $0 == code }
    }

    private func addDisplayedTranslation(_ translation: TranslationRegistry) {
        guard settings.defaultDisplayedTranslationCodes.count < 3,
              !settings.defaultDisplayedTranslationCodes.contains(translation.code) else { return }
        settings.defaultDisplayedTranslationCodes.append(translation.code)
    }

    private func seedDefaultDisplayedCodesIfNeeded() {
        guard settings.defaultDisplayedTranslationCodes.isEmpty, !translations.isEmpty else { return }
        var ordered = translations
        if let preferredCode = settings.defaultTranslationCode,
           let index = ordered.firstIndex(where: { $0.code == preferredCode }) {
            let preferred = ordered.remove(at: index)
            ordered.insert(preferred, at: 0)
        }
        settings.defaultDisplayedTranslationCodes = Array(ordered.prefix(3).map(\.code))
    }

    private func reload() {
        translations = (try? modelContext.fetch(FetchDescriptor<TranslationRegistry>(sortBy: [SortDescriptor(\.addedAt)]))) ?? []
    }

    /// [`TranslationManagementViewModel.delete` 포팅] 번들 번역본은 삭제 대상이
    /// 아니다 — 호출부(위 `translationEditRow`)가 UI에서 애초에 삭제 버튼을
    /// 숨기지만, 여기서도 한 번 더 막아 실수로 지워지는 걸 방지한다(원본의
    /// 방어적 가드를 그대로 가져왔다).
    private func delete(_ translation: TranslationRegistry) {
        guard !translation.isBundled else { return }
        TranslationFileMaterializer.removeLocalCopy(for: translation)
        removeDisplayedTranslation(code: translation.code)
        modelContext.delete(translation)
        try? modelContext.save()
        reload()
    }
}

// [2026-08-21 삭제] 사용자 요청 — "AI 탭 삭제" / "저장공간 탭 삭제". 옛
// `AISettingsTab`(Apple Intelligence 상태 + 장 개요 AI 초안 토글)과
// `StorageSettingsTab`(iCloud 동기화 상태/연구문서 저장 위치 표시) 두 탭을
// 통째로 지웠다 — 둘 다 이 파일 안에서만 쓰이는 `private struct`라(위에서
// 확인: `AISettingsTab()`/`StorageSettingsTab()` 호출부가 SettingsView.body
// 한 곳씩뿐) 삭제해도 다른 파일에 영향이 없다. 이 탭들이 노출하던 설정값
// (`UserSettingsStore.isAIChapterDraftEnabled` 등) 자체는 다른 화면
// (`ChapterOutlineDraftService`)이 계속 참조하므로 그대로 남겨 뒀다 — 지운
// 것은 어디까지나 이 설정 화면의 UI 진입점뿐이다.

// MARK: - 모양

private struct AppearanceSettingsTab: View {
    @State private var settings = UserSettingsStore.shared
    // [2026-09-01 추가] `Color.hexString(in:)`(Color+Hex.swift 참고)가 hex 추출에
    // 필요로 하는 `EnvironmentValues`를 얻기 위함 — 아래 배경색/글자색
    // `ColorPicker`가 고른 색을 저장할 때 쓴다.
    @Environment(\.self) private var environment

    /// [2026-08-08 추가] 사용자 요청 — "본문크기, 색상, 절 크기, 줄간격, 글꼴"을
    /// 조정할 수 있어야 한다. 이 목록은 macOS(`NSFontManager`)/iOS(`UIFont`)에서
    /// 각각 다른 API로 구해야 해서 플랫폼별로 분기한다 — 정렬해 사용자가 찾기 쉽게
    /// 했다.
    ///
    /// [2026-08-08 추가] 내장 Paperlogy 폰트가 시스템에 실제로 등록됐다면(Xcode
    /// 타겟에 Fonts가 포함되고 앱이 `BundledFontRegistrar`로 등록에 성공한 경우)
    /// 이 시스템 목록에도 "Paperlogy 4 Regular"처럼 family 이름으로 나타난다 —
    /// `BundledFonts.entries`(사람이 읽기 좋은 이름 + 안전한 PostScript 식별자)로
    /// 이미 맨 위에 별도로 보여주므로, 여기서는 중복/혼동을 피하려고 "Paperlogy"로
    /// 시작하는 항목을 걸러낸다.
    private static let fontFamilies: [String] = {
        #if os(macOS)
        return NSFontManager.shared.availableFontFamilies.sorted().filter { !$0.hasPrefix("Paperlogy") }
        #elseif os(iOS)
        return UIFont.familyNames.sorted().filter { !$0.hasPrefix("Paperlogy") }
        #else
        return []
        #endif
    }()

    var body: some View {
        Form {
            Section {
                Picker("화면 모드", selection: $settings.colorSchemePreference) {
                    ForEach(UserSettingsStore.ColorSchemePreference.allCases) { preference in
                        Text(preference.displayName).tag(preference)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Label("화면 모드", systemImage: "circle.lefthalf.filled")
            }

            // [2026-09-03 변경] 사용자 요청 — "미리보기를 성경 조회 표시
            // 단락 위에 이동시킬 것." 아이폰에서만 `previewSection`을
            // `displaySettingsSection`보다 앞에 둔다 — 맥OS/아이패드는 이
            // 요청 대상이 아니라(사용자가 "아이폰 - 더보기 - 설정 - 성경 -
            // 모양"이라고 화면을 명시했다) 기존 순서(표시 설정 → 미리보기)를
            // 그대로 둔다.
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .phone {
                previewSection
                displaySettingsSection
            } else {
                displaySettingsSection
                previewSection
            }
            #else
            displaySettingsSection
            previewSection
            #endif
        }
        .formStyle(.grouped)
    }

    /// [2026-09-03 신설] 사용자 요청 — "미리보기를 성경 조회 표시 단락 위에
    /// 이동시킬 것(아이폰)." 아래 `body`가 아이폰에서만 이 프로퍼티를
    /// `previewSection`보다 뒤에 배치를 바꿔 보여준다 — 원래 이 Section의
    /// 내용(글꼴/크기/색상/한자 주석 Picker들)은 전혀 손대지 않고, `body`
    /// 안에 인라인으로 있던 것을 이름 붙은 computed property로만 뽑아냈다
    /// (순서를 조건부로 바꾸려면 각 Section이 독립된 표현식이어야 하므로).
    @ViewBuilder
    private var displaySettingsSection: some View {
        // [2026-08-08 추가, 원래 "아직 구현 안 됨"으로 표시돼 있던 자리] 사용자
        // 요청으로 실제 조정 UI를 만들었다. `RichTextEditor`(메모/개요 에디터,
        // Views/Memo/RichTextEditor.swift)는 이번 범위에 포함하지 않았다 —
        // 사용자 요청이 명시적으로 "S1(성경 조회) 화면"을 가리켰고, 에디터는
        // 이미 자체 서식 도구모음이 있어 성격이 다르다고 판단했다.
        Section {
            // [2026-08-08 추가] 사용자 요청 — "환경설정에 폰트를 바꿀 때도 이
            // 기본글꼴이 상단에 오도록". 내장 Paperlogy 9종을 맨 위에, 그
            // 아래 "시스템 기본", 그 아래 시스템에 설치된 나머지 글꼴 순으로
            // 보여준다. [2026-08-11] 한때 기본 선택값을 "시스템 기본"으로
            // 되돌렸다가, 이 설정(S1 성경 조회 본문 글꼴)은 요청 대상이
            // 아니었음이 확인돼 원래 기본값(내장 Paperlogy)으로 다시
            // 되돌렸다(UserSettingsStore.bibleFontName 기본값 참고) — 사용자가
            // 바꾸고 싶으면 이 Picker에서 언제든 "시스템 기본"을 고르면 된다.
            Picker("글꼴", selection: $settings.bibleFontName) {
                Section("내장 기본 글꼴") {
                    ForEach(BundledFonts.entries) { entry in
                        Text(entry.displayName).tag(entry.postScriptName)
                    }
                    // [2026-09-02 추가] 사용자 요청 — "조선궁서체도 성경 본문
                    // 글꼴에서 선택할 수 있도록". 지금까지는 "한자 폰트" Picker
                    // (아래, 한자 주석 전용)에서만 고를 수 있었다 — 이 Picker의
                    // 선택은 완전히 별도 설정(`bibleFontName`)이라 한자 주석
                    // 표시(`hanjaFontName`)에는 영향이 없다.
                    Text("조선궁서체").tag(SpecialPurposeFonts.hanja)
                }
                Section("시스템") {
                    Text("시스템 기본").tag("System")
                    ForEach(Self.fontFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
            }

            // [2026-08-11 변경] 사용자 요청 — "본문크기/절 번호 크기/줄
            // 간격을 한 줄에 표현할 것". 세 Stepper를 세로로 나열하던 걸
            // 한 HStack에 묶었다 — 각 항목은 위에 작은 캡션 라벨, 아래에
            // 값+Stepper를 두는 compact 배치.
            // [2026-09-03 변경] 사용자 보고 — "본문 크기, 절 번호 크기,
            // 줄 간격 에 대한 숫자가 안보임." 이 세 컨트롤을 나란히 한
            // `HStack`에 욱여넣은 건 2026-08-11 당시 "한 줄에 표현할 것"
            // 요청대로 만든 것인데, 아이폰 폭에서는 각 컨트롤이 실제로
            // 필요로 하는 너비(캡션 + "12pt" 같은 값 텍스트 + Stepper
            // +/- 버튼)를 3개 합치면 화면 폭을 넘겨, `Stepper`가 자기
            // 라벨(값 텍스트)보다 +/- 버튼 쪽을 우선해 값 텍스트가 잘려
            // 안 보이게 된다 — 바로 아래 "절 간격" 행(한 줄 전체를 쓰는
            // `HStack` + `Spacer()` + `Stepper`)은 이 문제가 없는 것과
            // 대조된다. 그래서 아이폰에서만 그 "절 간격" 행과 같은
            // 스타일(제목 - 여백 - 값+Stepper, 한 줄 전체 폭 사용)로
            // 세로 3줄로 바꾸고, 그 외(맥OS/아이패드, 가로 폭이 넉넉해
            // 원래도 문제가 없었다)는 기존 3열 가로 배치를 그대로 둔다.
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .phone {
                fullWidthSizeControl(title: "본문 크기", value: $settings.bibleBodyFontSize, range: 12...32)
                fullWidthSizeControl(title: "절 번호 크기", value: $settings.bibleVerseNumberFontSize, range: 8...24)
                fullWidthSizeControl(title: "줄간격", value: $settings.bibleLineSpacing, range: 0...16)
            } else {
                compactSizeControlRow
            }
            #else
            compactSizeControlRow
            #endif

            // [2026-08-20 추가] 사용자 요청 — "본문색상 위 절 간격 조절
            // 기능추가". `bibleLineSpacing`(위 compactSizeControl "줄간격",
            // 한 절 안에서 줄바꿈될 때의 간격)과는 다른 값이다 — 이건 절과
            // 절 사이 간격(`TranslationColumnView.columnScrollView`의
            // `LazyVStack(spacing:)`)이라 별도 컨트롤로 뒀다. 범위는 위
            // "줄간격"과 같은 0...16 대신 절 사이는 더 넓게 벌릴 수 있어야
            // 해서 0...30으로 잡았다.
            HStack {
                Text("절 간격")
                Spacer()
                Stepper(value: $settings.bibleVerseSpacing, in: 0...30, step: 1) {
                    Text("\(Int(settings.bibleVerseSpacing))pt")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .fixedSize()
            }

            // [2026-09-02 수정] 사용자 요청 — "배경색 직접 선택/글자색
            // 직접 선택이 있으므로 배경색/본문 색상(팔레트 Picker)은 제거할
            // 것." 아래 두 `ColorPicker`만 남기고, 팔레트에서 고르던
            // `Picker("배경색", ...)`/`Picker("본문 색상", ...)`는 삭제했다
            // (`Color.bibleBackgroundPalette`도 이제 이 파일 말고는 쓰는
            // 곳이 없어 `Color+Hex.swift`에서 함께 지웠다 — `Color.
            // memoTextPalette`는 `RichTextEditor.swift`가 여전히 써서
            // 그대로 남겨 뒀다). 팔레트 Picker에 있던 "시스템 기본"(빈
            // 문자열로 리셋) 옵션이 함께 없어진 것을 사용자가 다시 지적해,
            // 아래에 전용 초기화 버튼을 별도로 추가했다.
            Group {
                // 배경과 글자색을 미리 맞춰 둔 테마 5종을 먼저 보여준다 —
                // 대비가 안 맞는 조합(예: 밝은 배경 + 밝은 글자)을 고를
                // 위험 없이 빠르게 고를 수 있다. `BibleSlideColorTheme.all`
                // 참고.
                VStack(alignment: .leading, spacing: 8) {
                    Text("테마 색상")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(BibleSlideColorTheme.all) { theme in
                                themeSwatchButton(theme)
                            }
                        }
                    }
                }

                ColorPicker(
                    "배경색 직접 선택",
                    selection: Binding(
                        get: { settings.bibleBackgroundColor ?? Color.white },
                        set: { settings.bibleBackgroundColorHex = $0.hexString(in: environment) }
                    ),
                    supportsOpacity: false
                )

                ColorPicker(
                    "글자색 직접 선택",
                    selection: Binding(
                        get: { settings.bibleTextColor ?? Color.primary },
                        set: { settings.bibleTextColorHex = $0.hexString(in: environment) }
                    ),
                    supportsOpacity: false
                )

                // [2026-09-02 추가] 사용자 요청 — "시스템 기본색상으로 돌릴
                // 초기화 버튼 추가." 빈 문자열이 곧 "시스템 기본을 쓴다"는
                // 뜻이므로(`bibleBackgroundColor`/`bibleTextColor` 위
                // 선언부 주석 참고), 두 hex를 함께 빈 문자열로 되돌리기만
                // 하면 된다. 배경/글자 둘 다 안 골랐을 때는 되돌릴 게 없어
                // 버튼을 비활성화한다.
                Button("시스템 기본색상으로 되돌리기") {
                    settings.bibleBackgroundColorHex = ""
                    settings.bibleTextColorHex = ""
                }
                .disabled(settings.bibleBackgroundColorHex.isEmpty && settings.bibleTextColorHex.isEmpty)
            }

            // [2026-08-14 추가] 사용자 요청 — "두 번째 번역본(국한문 전체
            // 중복 테이블)을 지우고 → 절 단위 한자 주석 모델 ... 둘 다 지원,
            // 설정으로 전환." 개역한글 컬럼에 한자 주석을 어떻게 보여줄지
            // 고르는 3단 Picker. 기본값은 "끄기"(UserSettingsStore.
            // hanjaDisplayMode 기본값 참고) — 기존에 이 기능을 몰랐던
            // 사용자에게 갑자기 낯선 한자가 나타나지 않게.
            Picker("한자 주석 표시", selection: $settings.hanjaDisplayMode) {
                ForEach(UserSettingsStore.HanjaDisplayMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            // [2026-08-19 추가] 사용자 요청 — "설정 내 모양 탭의 한자 주석
            // 표시 밑에 '한자' 폰트를 변경할 수 있는 기능 추가." 지금은
            // 번들 폰트(조선궁서체) 하나뿐이라 시스템 기본과의 이지선다 —
            // 나중에 다른 한자 폰트가 추가되면 이 Picker에 항목만 늘리면
            // 된다(`bibleFontName` Picker와 같은 구조). 한자 주석 표시
            // 자체가 꺼져 있으면 무의미하므로 비활성화한다.
            Picker("한자 폰트", selection: $settings.hanjaFontName) {
                Text("조선궁서체 (기본)").tag(SpecialPurposeFonts.hanja)
                Text("시스템 기본").tag("System")
            }
            .disabled(settings.hanjaDisplayMode == .off)
        } header: {
            Label("성경 조회 표시", systemImage: "textformat")
        }
    }

    /// [2026-09-03 신설] 위 `displaySettingsSection`과 같은 이유로 뽑아낸
    /// "미리보기" Section — 내용은 그대로, 이름만 붙였다.
    @ViewBuilder
    private var previewSection: some View {
        Section {
            previewRow
        } header: {
            Label("미리보기", systemImage: "eye")
        }
    }

    private var previewRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("1")
                .font(settings.bibleVerseNumberFont)
                .foregroundStyle(.secondary)
                .frame(minWidth: 20, alignment: .trailing)
            Text("태초에 하나님이 천지를 창조하시니라")
                .font(settings.bibleBodyFont)
                .foregroundStyle(settings.bibleTextColor ?? Color.primary)
                .lineSpacing(settings.bibleLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
        }
        // [2026-09-01 추가] 배경색 설정을 추가하면서, 미리보기도 실제 배경색을
        // 반영하도록 확장했다 — 설정을 안 골랐으면(nil) 기존과 동일하게 투명.
        .padding(8)
        .background(settings.bibleBackgroundColor ?? Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// [2026-09-01 추가] "테마 색상" 한 항목(배경+글자색 조합)을 스와치 하나로
    /// 보여주는 버튼 — 탭하면 배경색/글자색을 동시에 그 테마 값으로 바꾼다.
    private func themeSwatchButton(_ theme: BibleSlideColorTheme) -> some View {
        let isSelected = settings.bibleBackgroundColorHex == theme.backgroundHex
            && settings.bibleTextColorHex == theme.textHex
        return Button {
            settings.bibleBackgroundColorHex = theme.backgroundHex
            settings.bibleTextColorHex = theme.textHex
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.background)
                    .frame(width: 56, height: 40)
                    .overlay {
                        Text("가")
                            .font(.headline)
                            .foregroundStyle(theme.text)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                                lineWidth: isSelected ? 2 : 1
                            )
                    }
                Text(theme.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    /// [2026-09-03 신설] 위 `compactSizeControlRow`를 macOS/iPadOS 전용으로
    /// 옮기며 그 3열 배치 자체를 여기로 뽑아냈다 — 원래 `body`에 인라인으로
    /// 있던 것을 이름 붙은 computed property로만 바꿨을 뿐, 내용은 그대로다.
    @ViewBuilder
    private var compactSizeControlRow: some View {
        HStack(alignment: .top, spacing: 20) {
            compactSizeControl(
                title: "본문 크기",
                value: $settings.bibleBodyFontSize,
                range: 12...32
            )
            compactSizeControl(
                title: "절 번호 크기",
                value: $settings.bibleVerseNumberFontSize,
                range: 8...24
            )
            compactSizeControl(
                title: "줄간격",
                value: $settings.bibleLineSpacing,
                range: 0...16
            )
        }
    }

    /// [2026-08-11 신설] 본문 크기/절 번호 크기/줄간격을 한 줄에 나란히 배치하기
    /// 위한 compact 컨트롤 — 캡션 라벨 아래 값(pt)과 Stepper.
    @ViewBuilder
    private func compactSizeControl(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Stepper(value: value, in: range, step: 1) {
                Text("\(Int(value.wrappedValue))pt")
            }
        }
    }

    /// [2026-09-03 신설] 아이폰 전용 — 바로 아래 "절 간격" 행과 완전히 같은
    /// 스타일(제목 - Spacer - 값(pt) - Stepper)로, 한 줄 전체 폭을 쓴다 —
    /// 위 `compactSizeControl`(3열 압축용)과 달리 이 컨트롤 하나가 그 줄
    /// 전부를 쓰므로 값 텍스트가 잘릴 일이 없다.
    @ViewBuilder
    private func fullWidthSizeControl(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Stepper(value: value, in: range, step: 1) {
                Text("\(Int(value.wrappedValue))pt")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .fixedSize()
        }
    }
}

// MARK: - 성경 구절 복사 형식 (2026-08-08 추가)
//
// 사용자 요청 + 참고 소스 FormatTabView.swift를 이 앱 저장 방식으로 옮긴 탭.
// 실제 서식 로직은 `BibleVerseCopyFormatter`(S1이 "복사" 버튼을 누를 때 쓰는 것과
// 완전히 같은 함수)를 그대로 호출해 미리보기를 만든다 — 미리보기 따로, 실제 동작
// 따로 구현하면 언젠가 둘이 어긋날 위험이 있어 하나로 합쳤다.

private struct BibleCopyFormatSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings = UserSettingsStore.shared
    /// "번역본이 한 개라면 비활성화"(사용자 요청 원문)를 위해 등록된 번역본 총
    /// 개수를 본다 — 실제 복사 시점에 몇 개를 함께 복사하는지가 아니라, 이
    /// 설정이 "언젠가 의미가 있을 가능성이 있는지"를 등록 수로 미리 판단한다.
    @State private var registeredTranslationCount = 0

    var body: some View {
        Form {
            // [2026-08-11 변경] 사용자 요청 — 순서를 "구분기호 / 성경 이름 약어
            // 사용 / 성경 장절 위치 / 번역본 이름 위치 / 번역본 이름과 장절을
            // 합쳐서 표시"로 재배열했다(기존엔 "장절 위치 → 구분기호 → 약어 →
            // 번역본 위치" 순이었다). 저장되는 값/로직은 그대로, 표시 순서만
            // 바꿨다.
            Section {
                Picker("구분 기호", selection: $settings.copyReferenceBracketStyle) {
                    Text("[창세기 1:1]").tag(UserSettingsStore.ReferenceBracketStyle.square)
                    Text("(창세기 1:1)").tag(UserSettingsStore.ReferenceBracketStyle.round)
                }
                .pickerStyle(.segmented)

                Toggle("성경 이름 약어 사용 (창세기 → 창)", isOn: $settings.copyUseAbbreviatedBookName)

                Picker("성경 장절 위치", selection: $settings.copyReferencePosition) {
                    ForEach(UserSettingsStore.TextPosition.allCases) { position in
                        Text(position.displayName).tag(position)
                    }
                }
                .pickerStyle(.segmented)

                Picker("번역본 이름 위치", selection: $settings.copyTranslationLabelPosition) {
                    ForEach(UserSettingsStore.TextPosition.allCases) { position in
                        Text(position.displayName).tag(position)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(registeredTranslationCount <= 1)

                // [2026-08-08 추가] 사용자 요청 — "성경장절과 번역본이 동일하게
                // 본문 앞/뒤에 위치했을 때, 합쳐서 보일지 분리해서 보일지". 두
                // 위치가 다르면 이 설정 자체가 적용될 자리가 없으므로 아예 숨긴다
                // (비활성화만 하지 않고 숨기는 이유: "왜 안 먹히지" 오해를 줄이려는
                // 목적 — 위치가 같아지는 순간 자연스럽게 나타난다).
                if registeredTranslationCount > 1, settings.copyReferencePosition == settings.copyTranslationLabelPosition {
                    Toggle("번역본 이름과 장절을 합쳐서 표시", isOn: $settings.copyCombineReferenceAndTranslationLabel)
                }
            } header: {
                Label("기본 설정", systemImage: "doc.on.doc")
            } footer: {
                if registeredTranslationCount <= 1 {
                    Text("등록된 번역본이 1개뿐이라 번역본 이름 위치는 지금 적용되지 않습니다.")
                } else if settings.copyReferencePosition == settings.copyTranslationLabelPosition {
                    Text(settings.copyCombineReferenceAndTranslationLabel
                        ? "예: [NKJV 창세기 1:1]"
                        : "예: [NKJV][창세기 1:1]")
                }
            }

            Section {
                Toggle("절마다 줄바꿈 하기", isOn: $settings.copyNewlineBetweenVerses)

                if settings.copyNewlineBetweenVerses {
                    Toggle("매 절마다 장:절 표기", isOn: $settings.copyRepeatReferenceForEachVerse)
                        .padding(.leading, 12)
                        .onChange(of: settings.copyRepeatReferenceForEachVerse) { _, newValue in
                            // FormatTabView.swift와 같은 원칙 — 이 모드에서는 절
                            // 번호 표시가 의미 없어져 자동으로 끈다.
                            if newValue {
                                settings.copyShowVerseNumbers = false
                                settings.copyShowFirstVerseNumber = false
                            }
                        }
                }

                // [2026-08-11 삭제] 사용자 요청 — "[절마다 줄바꿈 하기] 아래
                // 빈 공백 라인 삭제". 여기 있던 `Divider()`를 없앴다.
                Toggle("절 번호 표시", isOn: $settings.copyShowVerseNumbers)
                    .disabled(settings.copyRepeatReferenceForEachVerse)
                    .onChange(of: settings.copyShowVerseNumbers) { _, newValue in
                        if !newValue { settings.copyShowFirstVerseNumber = false }
                    }

                if settings.copyShowVerseNumbers {
                    Picker("번호 스타일", selection: $settings.copyVerseNumberStyle) {
                        ForEach(UserSettingsStore.VerseNumberStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(settings.copyRepeatReferenceForEachVerse)

                    Toggle("첫 절 번호 표시", isOn: $settings.copyShowFirstVerseNumber)
                        .disabled(settings.copyRepeatReferenceForEachVerse)
                }
            } header: {
                Label("상세 출력 형식", systemImage: "list.bullet.rectangle")
            }

            Section {
                Text(previewText)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Label("미리보기", systemImage: "text.quote")
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadTranslationCount)
    }

    private func loadTranslationCount() {
        registeredTranslationCount = (try? modelContext.fetch(FetchDescriptor<TranslationRegistry>()))?.count ?? 0
    }

    /// 창세기 1:1-2 두 절, 번역본 1~2개(등록 개수에 따라)로 실제 서식 함수를
    /// 그대로 돌려서 만드는 미리보기 — 그래서 여기 보이는 결과가 실제 "복사"
    /// 버튼을 눌렀을 때와 항상 정확히 같다.
    private var previewText: String {
        let sampleBook = BooksProvider.shared.books.first(where: { $0.bookId == 1 })
            ?? Book(bookId: 1, testament: .old, orderIndex: 1, nameKo: "창세기", nameOriginal: "Genesis", abbreviation: ["창"], chapterCount: 50)
        let verses = [
            BibleVerse(uid: 1, versionCode: nil, bookId: 1, chapter: 1, verse: 1, content: "태초에 하나님이 천지를 창조하시니라", paragraph: nil),
            BibleVerse(uid: 2, versionCode: nil, bookId: 1, chapter: 1, verse: 2, content: "땅이 혼돈하고 공허하며 흑암이 깊음 위에 있고", paragraph: nil),
        ]
        var translations = [BibleVerseCopyFormatter.TranslationSnapshot(displayName: "번역본 A", verses: verses)]
        if registeredTranslationCount > 1 {
            translations.append(BibleVerseCopyFormatter.TranslationSnapshot(displayName: "번역본 B", verses: verses))
        }
        return BibleVerseCopyFormatter.format(
            book: sampleBook, chapter: 1, selectedVerses: [1, 2],
            translations: translations, settings: settings
        ) ?? ""
    }
}

// MARK: - 단축키(선택 — 스펙 자체가 "필수 아님")

private struct ShortcutsSettingsTab: View {
    private let shortcuts: [(String, String)] = [
        ("새 메모", "⌘N"), ("새 폴더", "⇧⌘N"), ("연구문서 업로드", "⌘O"),
        ("사이드바 토글", "⌥⌘S"), ("성경조회로 이동", "⌘1"), ("개인 묵상으로 이동", "⌘2"),
        ("연구문서로 이동", "⌘3"), ("개요로 이동", "⌘4"), ("통합검색으로 이동", "⌘5"),
        ("말씀 요약으로 이동", "⌘6"),
        ("태그 관계 보기", "⇧⌘T"), ("다음 장", "⌘]"), ("이전 장", "⌘["),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(shortcuts, id: \.0) { shortcut in
                    LabeledContent(shortcut.0) {
                        Text(shortcut.1)
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            } header: {
                Label("단축키", systemImage: "keyboard")
            } footer: {
                Text("현재는 재지정할 수 없고, 위 고정된 단축키만 지원합니다(사용자 재지정은 다음 단계 후보).")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 라이센스
//
// [2026-08-21 수정] 사용자 요청 — "정보 이름 변경 - 라이센스." 옛 이름
// `AboutSettingsTab`/탭 라벨 "정보"를 각각 `LicenseSettingsTab`/"라이센스"로
// 바꿨다. 맨 위에 있던 "앱 정보" Section(이름/버전 표시)은 새 "기본" 탭
// (`GeneralSettingsTab`)으로 옮겨서 여기서는 빠졌다 — 남은 내용은 전부
// 라이선스·저작권 고지라 새 이름과 실제 내용이 맞는다.
private struct LicenseSettingsTab: View {
    var body: some View {
        Form {
            // [2026-08-19 추가] 사용자가 (재)대한성서공회 저작권부에 직접 문의해
            // 받은 회신 그대로 반영 — "성경전서 개역한글판(1961)"과 "관주성경전서
            // 개역한글판(1962)"은 저작재산권 보호기간이 만료돼 허가 없이 무료로
            // 쓸 수 있으나, 동일성유지권(본문을 임의로 변경·수정하지 않고 그대로
            // 사용)과 성명표시권(저작권이 (재)대한성서공회에 있다는 표시)은 지켜야
            // 한다는 내용. 회신에 적힌 두 표준 문구(정식/약식)를 그대로 옮겼다 —
            // 위 "오픈소스 라이선스 고지"와 성격이 달라(이 두 판본은 오픈소스가
            // 아니라 저작권 보호기간 만료) 별도 섹션으로 분리했다.
            //
            // 이 회신은 아래 "오픈소스 라이선스 고지" 섹션에 있던 관주(구절 연결)
            // 정보 출처 문구("아직 확인 중")도 함께 해소한다 — 그 문구를 이 회신
            // 내용으로 갱신했다.
            Section {
                Text("여기에 사용한 성경전서 개역한글판의 저작권은 (재)대한성서공회에 있습니다.")
                Text("성경전서 개역한글판 ⓒ (재)대한성서공회")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("성경 본문 저작권", systemImage: "book.closed")
            } footer: {
                Text("성경전서 개역한글판(1961)과 관주성경전서 개역한글판(1962)은 저작재산권 보호기간이 만료되어 (재)대한성서공회의 허가 없이 무료로 사용할 수 있습니다. 다만 본문을 임의로 변경·수정하지 않고 그대로 사용해야 하며(동일성유지권), 저작권이 (재)대한성서공회에 있다는 표시(성명표시권)를 해야 합니다 — (재)대한성서공회 저작권부 회신(2026-08-19) 기준.")
            }

            // [2026-08-13 추가] OriginalTextLookupService.swift/README.md에 "라이선스
            // 고지 미구현"으로 남아 있던 TODO 해소 — STEPBible-Data(CC BY 4.0)
            // 크레딧을 hwp 뷰어 고지와 같은 섹션에 추가한다. STEPBible 라이선스
            // 조건은 "STEP Bible"을 www.STEPBible.org에 링크해 표시하는 것뿐이라
            // 문구를 그 요건 그대로 옮겼다(github.com/STEPBible/STEPBible-Data
            // README 라이선스 문구 참고).
            //
            // [2026-08-16 정정] 기존 문구가 실제로 이 앱에 한 번도 쓰인 적 없는
            // 프로젝트(rhwp-studio/postmelee/alhangeul-macos)를 잘못 가리키고
            // 있었다 — 실제 hwp 뷰어 구현 이력은 edwardkim/rhwp(WASM, MIT, 폐기)
            // → hwp-swift(sboh1214/hwp-swift, 네이티브 Swift, LGPL-2.1, 현재
            // 사용 중, DocumentViewerView.swift 상단 참고)다. LGPL-2.1은 수정 없이
            // SPM 의존성으로만 쓰면 소스 공개 의무는 없지만 라이선스/저작자 고지는
            // 필요해 이 문구를 그에 맞게 바로잡았다. hwp-swift는 폰트를 번들하지
            // 않으므로(README "번들 폰트 금지") 폰트 라이선스 문장도 지웠다.
            //
            // [2026-08-16 재정정] "폐기"라고 적었던 rhwp를 hwp-swift 네이티브
            // 뷰어의 렌더링 완전성 비교용 "웹 뷰어"로 다시 추가했다
            // (RhwpWebViewerPane.swift 참고, DocumentViewerView.swift의
            // hwpViewerModeToggle에서 "hwp-swift (네이티브)"/"rhwp (웹)" 두
            // 뷰어를 전환할 수 있다) — 그래서 rhwp 고지 문구를 되살린다.
            // rhwp(@rhwp/core npm 패키지, MIT, Copyright (c) 2025-2026 Edward
            // Kim)는 Resources/rhwp_LICENSE.txt에 원문을 그대로 번들해 뒀다.
            Section {
                Text("hwp 문서는 두 가지 뷰어로 열어 비교할 수 있습니다. 네이티브 뷰어는 오픈소스 hwp-swift(github.com/sboh1214/hwp-swift, LGPL-2.1 라이선스)를 사용하며, 별도로 폰트를 번들하지 않고 기기에 설치된 시스템 폰트로 렌더링합니다.")

                Link("hwp-swift 저장소 보기", destination: URL(string: "https://github.com/sboh1214/hwp-swift")!)

                Text("웹 뷰어는 오픈소스 rhwp(github.com/edwardkim/rhwp, MIT 라이선스)를 이 앱에 오프라인 번들해 사용합니다. 외부 서버 없이 기기 안에서만 문서를 렌더링합니다.")

                Link("rhwp 저장소 보기", destination: URL(string: "https://github.com/edwardkim/rhwp")!)

                // [2026-08-17 추가] 사용자 요청 — "지금까지 사용된 오픈소스
                // 라이선스 고지를 메뉴 - 설정... - 정보에 추가 기입할 것." doc/docx/
                // pages 업로드·검색(SwiftText)과 docx→PDF 변환(docxide-pdf)을 구현하며
                // 새로 들어온 오픈소스 의존성 세 개 — 지금까지 이 섹션에 빠져 있었다.
                // 라이선스 원문(LICENSE 파일)을 각 저장소에서 직접 확인해 표기했다:
                // SwiftText — Copyright (c) 2024 Oliver Drobnik, MIT.
                // ZIPFoundation — Copyright (c) 2017-2026 Thomas Zoechling, MIT.
                // docxide-pdf — Apache License 2.0.
                Text("doc/docx/pages 문서 업로드·텍스트 추출은 오픈소스 SwiftText(github.com/Cocoanetics/SwiftText, MIT 라이선스)를 사용합니다. SwiftText가 zip 압축 해제에 쓰는 ZIPFoundation(github.com/weichsel/ZIPFoundation, MIT 라이선스)도 함께 포함됩니다.")

                Link("SwiftText 저장소 보기", destination: URL(string: "https://github.com/Cocoanetics/SwiftText")!)

                Link("ZIPFoundation 저장소 보기", destination: URL(string: "https://github.com/weichsel/ZIPFoundation")!)

                Text("docx → PDF 변환(맥 전용)은 오픈소스 docxide-pdf(github.com/sverrejb/docxide-pdf, Apache License 2.0)를 사용합니다. 변환은 이 기기 안에서만 이뤄지며 외부 서버로 전송되지 않습니다.")

                Link("docxide-pdf 저장소 보기", destination: URL(string: "https://github.com/sverrejb/docxide-pdf")!)

                Text("원문 정보(히브리어 구약·그리스어 신약 원어 데이터)는 STEP Bible(www.STEPBible.org, Tyndale House Cambridge 제공)의 STEPBible-Data(TAHOT/TAGNT)를 사용하며, Creative Commons Attribution 4.0 International(CC BY 4.0) 라이선스를 따릅니다.")

                Link("STEPBible-Data 저장소 보기", destination: URL(string: "https://github.com/STEPBible/STEPBible-Data")!)

                // [2026-08-14 추가] 사용자 요청 — "기본 관주 정보도 시딩 ... 우선
                // 넣어보고 책을 보면서 확인." `CrossReferenceSeedImporter.swift`
                // 상단 주석과 같은 취지 — 대한성서공회 확인 전까지는 출처가
                // 확정된 상태가 아님을 사용자에게도 투명하게 알린다(과장 없이
                // 정직하게 표시하는 이 파일의 원래 원칙).
                // [2026-08-19 갱신] (재)대한성서공회 저작권부에 직접 문의해 회신을
                // 받아 출처가 확정됐다 — 위 "성경 본문 저작권" 섹션 참고. "아직
                // 확인 중"이던 이전 문구를 확정된 내용으로 바꿨다.
                Text("관주(구절 연결) 정보는 (재)대한성서공회의 관주성경전서 개역한글판(1962)을 따릅니다. 저작재산권 보호기간이 만료되어 무료로 사용하되, 위 '성경 본문 저작권' 섹션과 같은 조건(동일성유지권·성명표시권)을 지킵니다.")

                // [2026-08-19 추가] 사용자 요청 — "앱 내 언어별 폰트 추가"(한자/
                // 히브리어/헬라어 전용 폰트 + 고운바탕 번들 폰트) 4건의 라이선스
                // 고지. 조선궁서체는 표준 오픈소스 라이선스가 아니라 사용자가
                // 직접 제공한 (주)조선일보사 고지 문구를 그대로 옮겼다(요청
                // 원문 — "위 내용을 참고하여 적절하게 추가할 것").
                Text("한자 주석 기본 폰트인 조선궁서체의 지적재산권은 (주)조선일보사에 있고 개인 및 기업 사용자에게 무료로 제공됩니다. 사용자들은 이를 다른 이에게 자유롭게 배포할 수 있습니다. 다만 어떠한 경우에도 복사 또는 배포에 따른 대가를 요구하거나 수정해서 판매할 수 없으며, 배포된 형태 그대로 사용해야 합니다.")

                // [2026-08-19 추가] SILEOT.ttf(Ezra SIL) — software.sil.org/ezra
                // 다운로드 페이지의 라이선스 절 그대로 옮김: 히브리어 문자 배치
                // 지능(레이아웃 로직)만 별도로 Ralph Hancock·John Hudson의
                // MIT/X11 라이선스이고, 그 외 폰트 소프트웨어 자체는 SIL Open
                // Font License(OFL) 1.1이다.
                Text("원문 정보 화면의 히브리어 원어 표기는 SIL Global이 배포하는 Ezra SIL 폰트를 사용합니다. 히브리어 문자 배치 지능은 Ralph Hancock과 John Hudson이 만든 MIT/X11 라이선스를, 그 외 폰트 소프트웨어 자체는 SIL Open Font License(OFL) 1.1을 따릅니다.")

                Link("Ezra SIL 다운로드 페이지 보기", destination: URL(string: "https://software.sil.org/ezra/")!)

                // [2026-08-19 추가] Gentium-Regular.ttf/Gentium-Bold.ttf — 사용자가
                // 첨부한 OFL.txt(Copyright 2003-2025 SIL Global, Reserved Font
                // Names "Gentium"·"SIL") 그대로. fonttools로 확인한 실제 번들
                // 파일의 family 이름도 "Gentium"이라 이 문구와 일치한다(사용자가
                // 요청 메시지에서 부른 "GentiumPlus"는 SIL이 이 폰트를 부르는
                // 현재 마케팅 명칭 — BundledFontRegistrar.swift의
                // `SpecialPurposeFonts.greekRegular/greekBold` 상단 주석 참고).
                Text("원문 정보 화면의 그리스어(헬라어) 원어 표기는 SIL Global이 배포하는 Gentium 폰트(현재 명칭 Gentium Plus)를 사용하며, SIL Open Font License(OFL) 1.1을 따릅니다.")

                Link("Gentium 폰트 페이지 보기", destination: URL(string: "https://software.sil.org/gentium/")!)

                // [2026-08-19 추가] GowunBatang-Regular.ttf/GowunBatang-Bold.ttf —
                // github.com/yangheeryu/Gowun-Batang의 OFL.txt(Copyright 2021 The
                // Gowun Batang Project Authors) 그대로. Paperlogy와 같은 방식으로
                // 앱에 번들해 "글꼴" 설정에서 바로 고를 수 있다(BundledFonts.
                // gowunBatangEntries 참고) — 특정 언어 전용이 아니라 사용자가
                // 자유롭게 고르는 일반 글꼴이라 위 세 항목과 성격이 다르다.
                Text("앱 내장 기본 글꼴 중 고운바탕(Gowun Batang)은 The Gowun Batang Project Authors가 배포하는 오픈소스 폰트로, SIL Open Font License(OFL) 1.1을 따릅니다.")

                Link("Gowun Batang 저장소 보기", destination: URL(string: "https://github.com/yangheeryu/Gowun-Batang")!)
            } header: {
                Label("오픈소스 라이선스 고지", systemImage: "doc.plaintext")
            } footer: {
                Text("원문 정보 화면의 한글 뜻풀이는 위 STEPBible 영어 뜻풀이를 기기 내(Apple Translation 프레임워크) 자동 번역한 것이며, 사용자가 직접 수정할 수 있습니다. 신학 용어의 표준 역어와 다를 수 있습니다.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 개발자 (DEBUG 전용, OutlineSeedExporter.swift 참고)
//
// [2026-08-14 복원] 개요(S8/S9) 화면은 이미 리치 에디터 서식을 완전히 지원하는
// 실제 프로덕션 화면이다 — 개발자(박윤기)가 DEBUG 빌드에서 사이드바 "개요" 메뉴로
// 들어가 평소처럼 서식을 넣어 작성하면 된다. 이 탭은 그렇게 작성한 결과(서식
// 포함 RTF)를 배포용 `OutlineSeed.json` 포맷으로 뽑아내는 "내보내기" 버튼 하나만
// 제공한다 — 새 에디터가 아니다.

#if DEBUG
import UniformTypeIdentifiers

private struct DeveloperSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    /// [2026-08-29 신설] "온보딩 다시 보기" 버튼용 — 아이패드처럼 이 화면 자체가
    /// `.sheet`(SettingsHostView, SidebarNavigationView 참고)로 떠 있는 경우
    /// 그 시트부터 닫아야, 같은 RootView가 곧이어 온보딩 시트를 새로 띄울 수
    /// 있다(SwiftUI는 같은 뷰가 시트 두 개를 동시에 띄우지 못한다). macOS의
    /// `Settings` Scene(별도 창)이나 아이폰의 `NavigationLink` 진입(시트 아님)
    /// 에서는 `dismiss()`가 그 창/화면을 닫을 뿐이라 무해하다.
    @Environment(\.dismiss) private var dismiss
    @State private var exportDocument: OutlineSeedJSONDocument?
    @State private var isExporterPresented = false
    @State private var lastExportSummary: OutlineSeedExporter.Summary?
    @State private var exportError: String?

    // [2026-08-14 추가] 사용자 요청 — "그동안 테스트로 작성된 형광펜정보, 메모,
    // 관주 정보는 모두 삭제할것." 실제 데이터는 이 기기의 CloudKit 연동
    // SwiftData 스토어에만 있어(파일로 직접 지울 방법이 없다 — 이 탭 자체가
    // "이 기기에서 앱을 실행해 버튼을 누르는" 방식인 이유) 1회성 삭제 버튼으로
    // 만든다. 범위는 확인 질문에서 명확히 확정한 대로: 형광펜(VerseHighlight)/
    // 관주(VerseCrossReference)/구절별 메모(VersePhraseNote) 세 가지만 —
    // 개인 묵상·말씀요약(UserMemo)은 테스트 데이터가 아니라 실제 내용일 수
    // 있어 이 삭제 대상에서 제외했다(사용자가 명시적으로 "구절별 메모만"이라고
    // 선택).
    @State private var testDataCounts: (highlight: Int, crossReference: Int, phraseNote: Int)?
    @State private var isDeleteConfirmationPresented = false
    @State private var deleteResultMessage: String?

    // [2026-08-15 추가] 사용자 요청 — "사이드바의 연구문서 - 기존에 등록된
    // 데이터와 관련 DB자료를 모두 삭제할 것." 확인 질문에서 "기능은 유지하고
    // 데이터만 삭제"로 범위를 확정했다 — 사이드바 "연구문서" 메뉴/화면/모델
    // (SourceDocument 등)은 그대로 두고, 지금 쌓여 있는 레코드만 지운다. 위
    // "테스트 데이터 삭제"와 완전히 같은 패턴(1회성 버튼, 실제 데이터는 이
    // 기기의 CloudKit 연동 SwiftData 스토어에만 있어 파일로 직접 지울 방법이
    // 없다).
    //
    // `SourceDocument`를 지우면 `deleteRule: .cascade`로 걸린 자식들
    // (DocumentText/ConvertedPDF/OCRResult/DocumentAnchor/DocumentMarkdown,
    // Documents.swift 참고)은 자동으로 같이 지워진다. 다만 `VerseMention`은
    // 관계가 아니라 원시 문자열 `sourceId`로만 연결된 "관련 DB자료"라 자동으로
    // 안 지워진다 — 기존 단건 삭제(`DocumentsViewModel.delete(_:)`)도
    // `BibleReferenceIndexingService.removeMentions`로 이걸 지운다.
    // `ImageCategory`(문서 분류 이름표)는 문서에 딸린 "데이터"가 아니라
    // 사용자가 만든 분류 체계라 삭제 대상에서 뺐다. 원본 파일 자체(사용자
    // 지정 저장공간의 실제 파일)도 이 앱이 관리하는 DB 레코드가 아니므로
    // 건드리지 않는다.
    // [2026-08-19 수정] `EmbeddingChunk`(임베딩 청크)는 의미검색(AI) 기능
    // 삭제(사용자 요청)와 함께 이 카운트/삭제 대상에서도 뺐다.
    @State private var documentDataCounts: (document: Int, verseMention: Int)?
    @State private var isDeleteDocumentsConfirmationPresented = false
    @State private var deleteDocumentsResultMessage: String?

    var body: some View {
        Form {
            Section {
                Text("사이드바 \"개요\" 메뉴에서 평소처럼 리치 에디터로 책/장 개요를 작성하세요 — 이 기기의 DB에 그대로 쌓입니다.")
                Button {
                    export()
                } label: {
                    Label("개요 시딩 파일 내보내기...", systemImage: "square.and.arrow.up")
                }
                if let summary = lastExportSummary {
                    Text("책 개요 \(summary.bookCount)개 / 장 개요 \(summary.chapterCount)개를 내보냈습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let exportError {
                    Text(exportError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Label("개요 시딩", systemImage: "text.book.closed")
            } footer: {
                Text("내보낸 파일을 Resources/OutlineSeed.json에 덮어쓰고 Xcode Copy Bundle Resources에 등록하면(최초 1회만 필요) 신규 사용자 DB에 기본값으로 채워집니다. 이 탭 자체는 배포 빌드에서 빠집니다.")
            }

            // [2026-08-29 신설] 사용자 요청 — "온보딩 메세지가 한번봤기 때문에
            // 안보이는데 개발자모드에서는 볼 수 있도록 하게 해줘." 이 기기에서
            // 이미 온보딩을 완료해 `hasCompletedOnboarding`이 true가 된 뒤에도,
            // 개발자가 카루셀 내용(문구/디자인)을 다시 확인할 수 있게 한다.
            // `AppOnboardingReplayRequest`(AppOnboardingOverlay.swift)에 신호만
            // 보내고, 실제로 시트를 여는 것은 그 신호를 관찰하는
            // `AppOnboardingPresenter`(ContentView가 붙인 `.appOnboarding()`)의
            // 몫이다 — 이 화면 자신은 온보딩 뷰를 직접 열지 않는다.
            //
            // [2026-09-03 수정] 사용자가 "새로워진 점 다시 보기"(아래, 완전히
            // 같은 패턴)로 실제 재현 — 최초 신고했던 "빈 상자만 뜨는" 증상이
            // 그대로 나타났다. 원인은 이 설정 화면을 닫는 `dismiss()`와 다음
            // 시트를 열라는 신호(`requestReplay()`)를 같은 동기 실행 안에서
            // 곧바로 이어 붙인 데 있었다 — macOS SwiftUI는 한 시트가 닫히는
            // 애니메이션이 끝나기도 전에 같은 뷰 계층에서 다음 시트를 열려고
            // 하면 상태가 꼬여 빈 시트만 뜨는 문제가 실제로 보고돼 있다(Apple
            // 개발자 포럼 https://developer.apple.com/forums/thread/682219 —
            // 권장 해법이 정확히 "짧은 지연을 두고 다음 시트를 요청하라"다).
            // `requestReplay()` 호출만 짧게 지연시켜, 이 설정 시트의 닫힘
            // 애니메이션이 끝난 뒤에 다음 시트를 요청하게 했다.
            Section {
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        AppOnboardingReplayRequest.shared.requestReplay()
                    }
                } label: {
                    Label("온보딩 다시 보기", systemImage: "sparkles")
                }
            } header: {
                Label("온보딩 미리보기", systemImage: "sparkles")
            } footer: {
                Text("완료 플래그(hasCompletedOnboarding)와 마지막 확인 버전(lastSeenAppVersion)은 건드리지 않습니다 — 내용만 미리 봅니다. 이 화면이 시트로 떠 있는 경우(아이패드) 먼저 닫힌 뒤 온보딩이 뜹니다.")
            }

            // [2026-09-03 신설] 사용자 요청 — "설정.. 개발자 메뉴에 '새로워진
            // 점'을 다시볼 수 있도록 기능을 추가할 것." 위 "온보딩 미리보기"와
            // 완전히 같은 패턴 — `WhatsNewReplayRequest`(WhatsNewOverlay.swift)에
            // 신호만 보내고, 실제로 시트를 여는 것은 그 신호를 관찰하는
            // `WhatsNewPresenter`(ContentView가 붙인 `.whatsNewOverlay()`)의
            // 몫이다.
            // [2026-09-03 수정] 사용자 보고 — 이 버튼으로 실제 재현된 최초
            // 신고 증상("빈 상자") 원인 분석 — 위 "온보딩 다시 보기" 버튼
            // 수정 주석 참고. 같은 패턴이라 같은 지연을 그대로 적용했다.
            Section {
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        WhatsNewReplayRequest.shared.requestReplay()
                    }
                } label: {
                    Label("새로워진 점 다시 보기", systemImage: "gift")
                }
            } header: {
                Label("새로워진 점 미리보기", systemImage: "gift")
            } footer: {
                Text("마지막 확인 버전(lastSeenAppVersion)은 건드리지 않습니다 — 내용만 미리 봅니다. 현재 버전(\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"))에 등록된 WhatsNewContent 항목이 없으면 아무 일도 일어나지 않습니다. 이 화면이 시트로 떠 있는 경우(아이패드) 먼저 닫힌 뒤 뜹니다.")
            }

            Section {
                if let counts = testDataCounts {
                    Text("형광펜 \(counts.highlight)개 · 관주 \(counts.crossReference)개 · 구절별 메모 \(counts.phraseNote)개")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(role: .destructive) {
                    refreshCounts()
                    isDeleteConfirmationPresented = true
                } label: {
                    Label("형광펜/관주/구절별 메모 전체 삭제", systemImage: "trash")
                }
                if let deleteResultMessage {
                    Text(deleteResultMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("테스트 데이터 삭제", systemImage: "trash")
            } footer: {
                Text("이 기기(및 iCloud로 동기된 다른 기기)의 형광펜·관주·구절별 메모를 전부 지웁니다 — 되돌릴 수 없습니다. 개인 묵상/말씀요약(말씀 노트)은 지우지 않습니다.")
            }

            Section {
                if let counts = documentDataCounts {
                    Text("연구문서 \(counts.document)개 · 구절 언급 \(counts.verseMention)개")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(role: .destructive) {
                    refreshDocumentCounts()
                    isDeleteDocumentsConfirmationPresented = true
                } label: {
                    Label("연구문서 전체 삭제", systemImage: "trash")
                }
                if let deleteDocumentsResultMessage {
                    Text(deleteDocumentsResultMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("연구문서 데이터 삭제", systemImage: "doc.badge.gearshape")
            } footer: {
                Text("사이드바 \"연구문서\"에 등록된 모든 문서(원본 파일 참조·OCR 결과·변환본·본문 텍스트)와 거기서 파생된 성경구절 언급을 전부 지웁니다 — 되돌릴 수 없습니다. 사용자 저장공간의 원본 파일 자체는 지우지 않고, 이 앱의 등록 정보만 지웁니다. \"연구문서\" 기능/화면은 그대로 남아 있어 다시 업로드할 수 있습니다.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshCounts()
            refreshDocumentCounts()
        }
        .fileExporter(
            isPresented: $isExporterPresented,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "OutlineSeed"
        ) { result in
            if case .failure(let error) = result {
                exportError = "저장 실패: \(error.localizedDescription)"
            }
        }
        .confirmationDialog(
            "형광펜, 관주, 구절별 메모를 전부 삭제할까요?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("전체 삭제", role: .destructive) { deleteTestData() }
            Button("취소", role: .cancel) {}
        } message: {
            if let counts = testDataCounts {
                Text("형광펜 \(counts.highlight)개, 관주 \(counts.crossReference)개, 구절별 메모 \(counts.phraseNote)개가 삭제됩니다. 되돌릴 수 없습니다.")
            }
        }
        .confirmationDialog(
            "연구문서를 전부 삭제할까요?",
            isPresented: $isDeleteDocumentsConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("전체 삭제", role: .destructive) { deleteAllDocuments() }
            Button("취소", role: .cancel) {}
        } message: {
            if let counts = documentDataCounts {
                Text("연구문서 \(counts.document)개와 관련 DB자료(구절 언급 \(counts.verseMention)개)가 삭제됩니다. 원본 파일 자체는 지워지지 않습니다. 되돌릴 수 없습니다.")
            }
        }
    }

    private func export() {
        exportError = nil
        do {
            let (data, summary) = try OutlineSeedExporter.exportSeedJSON(context: modelContext)
            exportDocument = OutlineSeedJSONDocument(data: data)
            lastExportSummary = summary
            isExporterPresented = true
        } catch {
            exportError = "내보내기 실패: \(error.localizedDescription)"
        }
    }

    private func refreshCounts() {
        let highlightCount = (try? modelContext.fetchCount(FetchDescriptor<VerseHighlight>())) ?? 0
        let crossReferenceCount = (try? modelContext.fetchCount(FetchDescriptor<VerseCrossReference>())) ?? 0
        let phraseNoteCount = (try? modelContext.fetchCount(FetchDescriptor<VersePhraseNote>())) ?? 0
        testDataCounts = (highlightCount, crossReferenceCount, phraseNoteCount)
    }

    private func deleteTestData() {
        do {
            for item in try modelContext.fetch(FetchDescriptor<VerseHighlight>()) { modelContext.delete(item) }
            for item in try modelContext.fetch(FetchDescriptor<VerseCrossReference>()) { modelContext.delete(item) }
            for item in try modelContext.fetch(FetchDescriptor<VersePhraseNote>()) { modelContext.delete(item) }
            try modelContext.save()
            deleteResultMessage = "삭제 완료 (\(Date.now.formatted(date: .omitted, time: .shortened)))"
        } catch {
            deleteResultMessage = "삭제 실패: \(error.localizedDescription)"
        }
        refreshCounts()
    }

    private func refreshDocumentCounts() {
        // ⚠️ `VerseMention.sourceType`은 String rawValue enum이라 `#Predicate`
        // 등호 비교가 이 SwiftData 버전에서 안전하게 동작하는지 확신할 수
        // 없어(이 파일의 `SourceDocument.indexStatus` 등 다른 곳에서도 같은
        // 이유로 회피해 온 전례) 전체를 가져와 Swift에서 걸렀다.
        let documentCount = (try? modelContext.fetchCount(FetchDescriptor<SourceDocument>())) ?? 0
        let verseMentionCount = ((try? modelContext.fetch(FetchDescriptor<VerseMention>())) ?? [])
            .filter { $0.sourceType == .document }.count
        documentDataCounts = (documentCount, verseMentionCount)
    }

    private func deleteAllDocuments() {
        do {
            // `SourceDocument`를 지우면 cascade 관계로 걸린 DocumentText/
            // ConvertedPDF/OCRResult/DocumentAnchor/DocumentMarkdown은 자동으로
            // 같이 지워진다(Documents.swift 참고) — 여기서 따로 지울 필요 없다.
            // [2026-08-15 추가] 사용자 요청 — "연구문서를 앱에서 삭제하면 파일도
            // 삭제할 것." 여기(전체 삭제 개발자 도구)도 개별 삭제(DocumentsViewModel.
            // delete)와 같은 규칙을 적용 — DB 레코드를 지우기 전에 실제 파일부터
            // 지운다.
            for item in try modelContext.fetch(FetchDescriptor<SourceDocument>()) {
                DocumentUploadService.deleteStoredFile(for: item)
                modelContext.delete(item)
            }
            // 관계가 아니라 원시 문자열 sourceId로만 연결된 "관련 DB자료" — 위
            // `documentDataCounts` 프로퍼티 주석 참고.
            for item in try modelContext.fetch(FetchDescriptor<VerseMention>()) where item.sourceType == .document {
                modelContext.delete(item)
            }
            try modelContext.save()
            deleteDocumentsResultMessage = "삭제 완료 (\(Date.now.formatted(date: .omitted, time: .shortened)))"
        } catch {
            deleteDocumentsResultMessage = "삭제 실패: \(error.localizedDescription)"
        }
        refreshDocumentCounts()
    }
}

/// `fileExporter`가 요구하는 최소 `FileDocument` 래퍼 — 이미 완성된 JSON `Data`를
/// 그대로 감싸기만 한다(편집 기능은 필요 없어 `writableContentTypes`만 채웠다).
private struct OutlineSeedJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
#endif
