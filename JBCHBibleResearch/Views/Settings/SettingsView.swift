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

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("일반", systemImage: "gearshape") }
            TranslationsSettingsTab()
                .tabItem { Label("번역본", systemImage: "character.book.closed") }
            AISettingsTab()
                .tabItem { Label("AI", systemImage: "sparkles") }
            StorageSettingsTab()
                .tabItem { Label("저장공간", systemImage: "externaldrive") }
            AppearanceSettingsTab()
                .tabItem { Label("모양", systemImage: "paintbrush") }
            // [2026-08-08 추가] 사용자 요청 — 성경 구절 클립보드 복사 형식(참조 위치/
            // 괄호 스타일/약어/번역본 위치/줄바꿈/절 번호 스타일)을 위한 탭.
            BibleCopyFormatSettingsTab()
                .tabItem { Label("복사 형식", systemImage: "doc.on.doc") }
            ShortcutsSettingsTab()
                .tabItem { Label("단축키", systemImage: "keyboard") }
            AboutSettingsTab()
                .tabItem { Label("정보", systemImage: "info.circle") }
            // [2026-08-14 복원] 사용자 지적 — "개요 시딩을 리치 에디터로 작성하고
            // 싶어서 임시(배포시 제외) 페이지를 요청했는데 왜 평문 JSON 방식으로
            // 마음대로 바꿨나." 개요 화면(`OutlineBookBulkEditView`) 자체가 이미
            // 리치 에디터 서식을 완전히 지원하므로 새 에디터를 만들 필요는 없고,
            // 그 화면에서 작성한 결과(서식 포함 RTF)를 배포용 시드 파일로 뽑아내는
            // "내보내기" 기능만 개발자 전용으로 복원하면 된다 — OutlineSeedExporter.swift
            // 참고. #if DEBUG로 배포 빌드에서는 이 탭 자체가 빠진다.
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

private struct GeneralSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings = UserSettingsStore.shared
    @State private var translations: [TranslationRegistry] = []

    var body: some View {
        Form {
            Section {
                Toggle("시작 시 마지막으로 보던 화면 열기", isOn: $settings.openLastScreenOnLaunch)
            } header: {
                Label("시작 옵션", systemImage: "power")
            }

            Section {
                Picker("기본 성경 번역본", selection: Binding(
                    get: { settings.defaultTranslationCode ?? translations.first?.code ?? "" },
                    set: { settings.defaultTranslationCode = $0 }
                )) {
                    ForEach(translations, id: \.code) { translation in
                        Text(translation.displayName).tag(translation.code)
                    }
                }
                .disabled(translations.isEmpty)
            } header: {
                Label("성경 조회 기본값", systemImage: "character.book.closed")
            } footer: {
                Text("새 메모 기본 폴더: 없음 — 항상 미분류로 시작합니다.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            translations = (try? modelContext.fetch(FetchDescriptor<TranslationRegistry>(sortBy: [SortDescriptor(\.addedAt)]))) ?? []
        }
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
            Section {
                ForEach(translations, id: \.id) { translation in
                    Toggle(translation.displayName, isOn: displayBinding(for: translation))
                        .disabled(isDisplayToggleDisabled(for: translation))
                }
            } header: {
                Label("성경 조회 기본 표시", systemImage: "eye")
            } footer: {
                Text("최대 3개까지 고를 수 있습니다.")
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

    private func displayBinding(for translation: TranslationRegistry) -> Binding<Bool> {
        Binding(
            get: { settings.defaultDisplayedTranslationCodes.contains(translation.code) },
            set: { isOn in
                var codes = settings.defaultDisplayedTranslationCodes
                if isOn {
                    guard !codes.contains(translation.code) else { return }
                    codes.append(translation.code)
                } else {
                    codes.removeAll { $0 == translation.code }
                }
                settings.defaultDisplayedTranslationCodes = codes
            }
        )
    }

    private func isDisplayToggleDisabled(for translation: TranslationRegistry) -> Bool {
        !settings.defaultDisplayedTranslationCodes.contains(translation.code)
            && settings.defaultDisplayedTranslationCodes.count >= 3
    }

    private func reload() {
        translations = (try? modelContext.fetch(FetchDescriptor<TranslationRegistry>(sortBy: [SortDescriptor(\.addedAt)]))) ?? []
    }

    private func delete(_ translation: TranslationRegistry) {
        // TranslationManagementViewModel.delete(_:)와 동일하게 로컬 캐시 파일도
        // 함께 정리한다(best-effort) — 두 곳에서 삭제 경로가 갈라지면서 한쪽만
        // 정리하면 디스크에 고아 파일이 남는다.
        TranslationFileMaterializer.removeLocalCopy(for: translation)
        modelContext.delete(translation)
        try? modelContext.save()
        reload()
    }
}

// MARK: - AI

private struct AISettingsTab: View {
    @State private var settings = UserSettingsStore.shared
    private var status: ChapterOutlineDraftService.AppleIntelligenceStatus {
        ChapterOutlineDraftService.appleIntelligenceStatus
    }

    var body: some View {
        Form {
            Section {
                statusBadge
            } header: {
                Label("Apple Intelligence 상태", systemImage: "sparkles")
            }

            Section {
                Toggle("장 개요 작성 시 AI 초안 제안 받기", isOn: $settings.isAIChapterDraftEnabled)
                    .disabled(status != .available)
            } header: {
                Label("AI 초안 제안", systemImage: "wand.and.stars")
            } footer: {
                Text("온디바이스에서만 실행되며 인터넷으로 전송되지 않습니다. 비용이 발생하지 않습니다.")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .available:
            Label("사용 가능", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .deviceUnsupported:
            Label("이 기기 미지원", systemImage: "circle.slash").foregroundStyle(.gray)
        case .disabledInSettings:
            Label("설정에서 꺼짐", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}

// MARK: - 저장공간
//
// [2026-08-11 변경] 사용자 요청 — 연구문서 원본/OCR 이미지를 이 경로에 "표시만"
// 하지 말고 실제로 그 위치에 저장하도록 했다. 실제 복사 로직은
// `DocumentUploadService.copyIntoICloudDocuments(sourceURL:subfolder:)` 참고 —
// 여기 표시된 경로 문구가 실제 동작과 어긋나지 않도록 같은 하위 폴더 이름
// ("연구 문서"/"OCR 이미지")을 그대로 썼다. iCloud Drive를 쓸 수 없는 기기/
// 계정에서는 자동으로 기존 방식(원본 위치 참조)으로 폴백한다.
//
// [2026-08-15 추가] 사용자 질문 — "파일을 업로드했는데 파일이 동기화 폴더에
// 저장되지 않는 이유는?" 바로 위 문단이 답이다(iCloud 컨테이너를 못 쓰면
// 조용히 원본 위치 참조로 폴백) — 그런데 예전엔 "그 폴백까지 화면에 실시간
// 반영하려면 별도 상태 조회가 필요해 이번 범위에는 넣지 않았다"고 일부러
// 미뤄 뒀던 부분이라, 사용자가 직접 원인을 확인할 방법이 아예 없었다. 이제
// 그 상태 조회를 실제로 추가했다 — ①iCloud 컨테이너를 지금 이 순간 실제로
// 쓸 수 있는지(`FileManager.url(forUbiquityContainerIdentifier:)`가 nil을
// 돌려주는지), ②이미 업로드된 문서들이 실제로 `storageLocationKind`별로
// 몇 개씩 나뉘어 있는지를 `@Query`로 그대로 보여준다.
private struct StorageSettingsTab: View {
    @Query private var documents: [SourceDocument]

    /// `DocumentUploadService.copyIntoICloudDocuments`가 매 업로드 때마다
    /// 확인하는 것과 정확히 같은 조건 — 여기서도 같은 API를 그대로 호출해서
    /// "지금 이 순간" 상태를 보여준다(캐시하지 않음, 탭을 열 때마다 새로 확인).
    private var isICloudContainerAvailable: Bool {
        FileManager.default.url(
            forUbiquityContainerIdentifier: BibleResearchSchema.defaultCloudKitContainerIdentifier
        ) != nil
    }

    private var icloudStoredCount: Int {
        documents.filter { $0.storageLocationKind == .icloudDrive }.count
    }

    /// `.userFolder`(정상 폴백 — 사용자가 고른 원래 위치)와
    /// `.appManagedFallback`(휴리스틱으로도 못 알아낸 경우) 둘 다 "iCloud
    /// 동기화 폴더로 복사되지 않고 원본 위치를 그대로 참조"라는 결과는 같아서
    /// 하나로 합쳐 보여준다 — `DocumentUploadService.inferStorageLocationKind`
    /// 참고.
    private var referencedInPlaceCount: Int {
        documents.filter { $0.storageLocationKind != .icloudDrive }.count
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("iCloud 컨테이너") {
                    if isICloudContainerAvailable {
                        Label("사용 가능", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("사용 불가", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                Label("iCloud 동기화 상태", systemImage: "icloud")
            } footer: {
                if isICloudContainerAvailable {
                    Text("지금 업로드하는 파일은 이 앱의 iCloud 컨테이너(Documents 폴더)로 복사됩니다.")
                } else {
                    // 이 문구가 사용자 질문에 대한 직접적인 답이다.
                    Text("iCloud 컨테이너를 지금 쓸 수 없습니다 — 그래서 업로드한 파일이 동기화 폴더로 복사되지 않고, 원래 있던 위치를 그대로 가리킵니다. 확인해볼 것: 이 Mac(또는 기기)이 iCloud에 로그인돼 있는지, 시스템 설정 > Apple ID > iCloud Drive가 켜져 있는지, Xcode의 Signing & Capabilities에서 \"iCloud\" > \"iCloud Documents\" 항목이 켜져 있고 프로비저닝 프로파일이 그 상태로 갱신됐는지.")
                }
            }

            if !documents.isEmpty {
                Section {
                    LabeledContent("iCloud 드라이브에 저장됨") {
                        Text("\(icloudStoredCount)개").foregroundStyle(.secondary)
                    }
                    LabeledContent("원본 위치를 그대로 참조") {
                        Text("\(referencedInPlaceCount)개").foregroundStyle(.secondary)
                    }
                } header: {
                    Label("업로드된 연구문서 현황", systemImage: "chart.bar.doc.horizontal")
                } footer: {
                    Text("\"원본 위치를 그대로 참조\"인 문서는 처음 선택했던 파일을 계속 가리킬 뿐, 동기화 폴더로 복사되지 않았습니다 — 그 원본 파일을 나중에 옮기거나 지우면 이 앱에서 더 이상 열 수 없습니다.")
                }
            }

            Section {
                Text("iCloud 컨테이너 / Documents / 연구 문서")
                    .fontDesign(.monospaced)
            } header: {
                Label("연구문서 원본 저장 위치", systemImage: "doc.text")
            } footer: {
                Text("업로드한 원본 파일이 이 경로에 복사되어 기기 간 iCloud로 동기화됩니다. iCloud를 쓸 수 없으면 원본이 있던 위치를 대신 참조합니다.")
            }

            Section {
                Text("iCloud 컨테이너 / Documents / OCR 이미지")
                    .fontDesign(.monospaced)
            } header: {
                Label("OCR 이미지 저장 위치", systemImage: "text.viewfinder")
            } footer: {
                Text("OCR 대상으로 업로드한 이미지 원본이 이 경로에 복사됩니다.")
            }

            Section {
                Text("⚠️ 캐시 용량 표시/비우기는 아직 구현되지 않았습니다.")
                    .foregroundStyle(.secondary)
            } header: {
                Label("캐시", systemImage: "internaldrive")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 모양

private struct AppearanceSettingsTab: View {
    @State private var settings = UserSettingsStore.shared

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

                // ⚠️ [팔레트 제한, 근거] SwiftUI `Color`에서 값을 다시 hex로 뽑아내는
                // 안전한 공개 API가 없다(Color+Hex.swift 상단 주석 참고) — 이 프로젝트가
                // 메모 텍스트 색상(RichTextEditor)에서 이미 같은 이유로 자유
                // 컬러피커 대신 미리 정한 팔레트를 쓰고 있어서, 여기서도 그
                // `Color.memoTextPalette`를 그대로 재사용해 일관성을 맞췄다.
                Picker("본문 색상", selection: $settings.bibleTextColorHex) {
                    Text("시스템 기본").tag("")
                    ForEach(Color.memoTextPalette, id: \.hex) { entry in
                        Text(entry.name).tag(entry.hex)
                    }
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

            Section {
                previewRow
            } header: {
                Label("미리보기", systemImage: "eye")
            }
        }
        .formStyle(.grouped)
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

// MARK: - 정보

private struct AboutSettingsTab: View {
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

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildString: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
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
