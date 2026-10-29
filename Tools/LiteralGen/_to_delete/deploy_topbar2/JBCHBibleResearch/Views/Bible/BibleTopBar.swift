//
//  BibleTopBar.swift
//  JBCHBibleResearch
//
//  성경 조회(아이폰/아이패드)의 직접 그린 상단바 (2026-10-21 목업 확정).
//
//  배경: 앱을 나갔다 돌아오면 시스템 내비게이션 바(`isNavigationBarHidden == true`)가 통째로 사라지는 증상이 있었다
//  (`NavigationBarGuard`로 복구했지만 시스템 바 상태에 의존하는 구조 자체가 원인). 그래서 이 화면은 시스템 바를 쓰지 않고
//  (`.toolbar(.hidden, for: .navigationBar)`) 화면 안의 상단 인셋에 이 막대를 직접 그린다.
//
//  구성
//  - 아이폰(1행 52pt, 아래에 장 이동 막대): 왼쪽 = 번역본 이름 + "책 장" 제목, 오른쪽 = 라운드 사각 묶음 5개
//    [책갈피 이동 | 책갈피 설정/해제 | 조회 이력 | 관련 콘텐츠 | 번역본 선택].
//  - 아이패드 기존 두 줄(상단바 60pt + 장 이동 막대, 한 줄도 "아이콘 아래줄"도 안 들어갈 때): 가운데 제목(번역본 줄 + "책 장"), 양끝 배치 —
//    왼쪽 끝 [사이드바 열기(사이드바가 닫혀 있을 때만) | 책갈피 이동 | 책갈피], 오른쪽 끝 [조회 이력 | 관련 콘텐츠(인스펙터)].
//    아래 장 이동 막대(표준/캡슐)는 2026-10-28부터 책 버튼이 없다.
//  - 아이패드 한 줄(폭이 넉넉할 때, `singleRowCenter`를 넘기면): 왼쪽 묶음 + 번역본 칩, 가운데 장 이동 막대(책/장 버튼 포함), 오른쪽 묶음.
//    폭이 모자라면 호출부(`BibleReadingView.topInsetContent`)의 `ViewThatFits`가 두 줄로 되돌린다.
//  - 아이패드 두 줄 "아이콘 아래줄"(2026-10-28, `stackedRowCenter`를 넘기면): 한 줄이 안 들어갈 때 먼저 시도한다. 윗줄(한 줄) =
//    [번역본 칩][제목](제목은 화면 가운데), 아랫줄 = [왼쪽 묶음][장 이동 막대(책 버튼 없음)][오른쪽 묶음]. 이것도 안 들어가면 위의 두 줄 배치.
//  - 2026-10-28: 아이패드 두 줄 배치 둘 다 장 이동 막대의 책 버튼을 뺀다(제목이 같은 팝오버를 연다). 한 줄 배치는 제목이 없어 책 버튼을 남긴다.
//  - 제목("책 장")을 탭하면 책/장 그리드 팝오버가 열린다(`BookChapterGridPopover`). 번역본 선택은 별도 아이콘(아이폰)이거나
//    번역본 이름 줄/칩(아이패드)을 탭한다(활성 번역본이 둘 이상일 때).
//  - 아이콘 모양은 상단 이동 막대와 같은 `BibleBarSegmentGroup` 규격(글자색 10% 채움 + 24% 테두리, 모서리 10pt).
//    활성 상태(책갈피 설정됨, 관련 콘텐츠 열림)는 `BibleBarPalette.strong` 채움 + `strongForeground` 글자.
//    모든 색은 사용자 성경 테마(`bibleBackgroundColor/bibleTextColor`)에서 파생해 라이트/다크/사용자 테마에서 같은 농도로 보인다.
//
//  동작 규칙은 이전 시스템 툴바(2026-10-21 이전 `BibleReadingView.toolbarContent`)와 같다.
//  - 아이패드에서 말씀 요약 편집 중에는 사이드바 열기·책갈피·조회 이력 아이콘을 숨기고, 관련 콘텐츠 자리는 "말씀 요약 닫기"로 바뀐다.
//    (아이폰은 편집기가 시트로 덮으므로 숨기지 않는다.)
//  - 책갈피 설정/해제는 대상 번역본이 없으면(빈 화면) 비활성이다.
//  - 번역본이 하나뿐이면 번역본 선택 UI는 나타나지 않는다.
//
//  막대의 배경·안전영역 확장·구분선은 호출부(`BibleReadingView.topInsetContent`)가 입힌다. iOS 전용.

#if os(iOS)
import BibleResearchModels
import SwiftData
import SwiftUI

struct BibleTopBar: View {
    let viewModel: BibleReadingViewModel
    /// 지금 보고 있는 번역본 이름(아이폰은 스와이프 중인 컬럼). 표시된 번역본이 없으면 빈 문자열.
    let translationDisplayName: String
    /// 책갈피 설정/해제가 대상으로 삼을 번역본 코드. nil이면 책갈피 버튼을 비활성화한다.
    let bookmarkTargetTranslationCode: String?
    /// 말씀 요약 편집기가 인스펙터 자리를 쓰는 중인지.
    let isEditingSummary: Bool
    /// 아이패드 한 줄 배치일 때 가운데에 놓을 장 이동 막대. nil이면 `stackedRowCenter`(아이패드 "아이콘 아래줄")를 보고,
    /// 그것도 nil이면(아이폰, 아이패드 기존 두 줄) 상단바만 그린다.
    var singleRowCenter: AnyView? = nil
    /// 아이패드 두 줄 "아이콘 아래줄" 배치일 때 아랫줄 가운데에 놓을 장 이동 막대(책 버튼 없음). nil이 아니면 윗줄은 [번역본 칩][제목] 한 줄로 두고
    /// 왼쪽/오른쪽 아이콘 묶음을 아랫줄 양끝으로 내린다(2026-10-28). `singleRowCenter`가 함께 주어지면 `singleRowCenter`가 우선한다.
    var stackedRowCenter: AnyView? = nil
    @Binding var isBookmarkListPresented: Bool
    @Binding var isHistoryPresented: Bool
    @Binding var isRelatedContentPresented: Bool
    @Binding var isTranslationPickerPresented: Bool
    /// 말씀 요약 편집 마치기(뒷정리 포함) — 이전 툴바의 "말씀 요약 닫기"와 같은 동작.
    let onCloseWordSummary: () -> Void

    /// 제목 탭으로 여는 책/장 그리드 팝오버. 다른 팝오버와 달리 이 막대만 쓰므로 부모가 아니라 여기서 가진다.
    @State private var isBookPickerPresented = false

    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    private var palette: BibleBarPalette {
        BibleBarPalette(environment: environment, colorScheme: colorScheme)
    }

    /// 아이폰 36pt, 아이패드 40pt(`BibleBarSizing.touch`). 모서리는 둘 다 10pt.
    private var sizing: BibleBarSizing {
        isPhone ? .phoneTopBar : .touch
    }

    /// 아이패드에서 말씀 요약 편집 중 숨기는 아이콘 묶음 판정.
    private var hidesIconsWhileEditingSummary: Bool {
        !isPhone && isEditingSummary
    }

    private var showsTranslationPicker: Bool {
        viewModel.availableTranslations.count > 1 && !hidesIconsWhileEditingSummary
    }

    private var isCurrentPositionBookmarked: Bool {
        guard let code = bookmarkTargetTranslationCode else { return false }
        return viewModel.isCurrentPositionBookmarked(translationCode: code)
    }

    var body: some View {
        Group {
            if isPhone {
                phoneLayout
            } else if let center = singleRowCenter {
                singleRowLayout(center: center)
            } else if let center = stackedRowCenter {
                stackedRowsLayout(center: center)
            } else {
                padLayout
            }
        }
        .environment(\.bibleBarSizing, sizing)
    }

    // MARK: - 레이아웃

    private var phoneLayout: some View {
        HStack(spacing: 8) {
            titleBlock(alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            BibleBarSegmentGroup {
                bookmarkListItem
                BibleBarSegmentDivider()
                bookmarkToggleItem
                BibleBarSegmentDivider()
                historyItem
                BibleBarSegmentDivider()
                relatedItem
                if showsTranslationPicker {
                    BibleBarSegmentDivider()
                    translationIconItem
                }
            }
            .fixedSize()
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(height: 52)
    }

    /// 아이패드 두 줄 배치의 윗줄 — 좌우 묶음이 같은 폭(`maxWidth: .infinity`)을 나눠 가져 제목이 항상 가운데에 온다.
    private var padLayout: some View {
        HStack(spacing: 16) {
            HStack(spacing: 0) {
                padLeftGroup
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            titleBlock(alignment: .center)

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                padRightGroup
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
    }

    /// 아이패드 한 줄 배치 — 왼쪽 묶음 + 번역본 칩, 가운데 장 이동 막대, 오른쪽 묶음. 가운데 막대가 남는 폭을 차지해 두 묶음 사이에 놓인다
    /// (왼쪽이 번역본 칩만큼 더 넓어 정확한 화면 중앙에서는 약간 오른쪽으로 치우친다).
    private func singleRowLayout(center: AnyView) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                padLeftGroup
                translationChip(showsCountWhenMultiple: false)
            }
            .fixedSize()
            center
            padRightGroup
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
    }

    /// 아이패드 두 줄 "아이콘 아래줄" 배치(2026-10-28).
    /// - 윗줄(한 줄, 최소 48pt): [번역본 칩][제목]. 제목은 화면 가운데에 고정하고 칩은 제목 바로 왼쪽에 붙인다 — `padLayout`처럼
    ///   좌우 칸이 같은 폭(`maxWidth: .infinity`)을 나눠 가지고, 왼쪽 칸은 칩을 오른쪽 끝(제목 쪽)에 둔다. 칩 폭(번역본 이름 길이,
    ///   열 개수 표시, 앱 언어)이 바뀌어도 제목 위치가 움직이지 않고, 기존 두 줄 배치(`padLayout`)의 제목과 같은 화면 가운데에 놓인다.
    ///   높이 48 = 칩 40pt(`BibleBarSizing.touch`) + 위아래 4pt. Dynamic Type으로 제목이 커지면 `minHeight`라 줄이 따라 늘어난다.
    /// - 아랫줄: [왼쪽 묶음][장 이동 막대(책 버튼 없음, 검색창이 남는 폭을 채움)][오른쪽 묶음]. 간격 6pt, 좌우 여백 12pt, 위아래 4pt
    ///   (2026-10-29 — 기존 두 줄 배치의 10pt/기본 여백보다 좁다).
    /// 한 줄에 안 들어가면 호출부의 `ViewThatFits`가 기존 두 줄 배치(아이콘 윗줄)로 되돌린다.
    /// "아이콘 아래줄" 배치의 아랫줄 묶음 사이 간격(가운데 장 이동 막대 안 간격 포함, 호출부 `BibleReadingView`도 쓴다).
    static let stackedRowSpacing: CGFloat = 6
    /// "아이콘 아래줄" 배치의 좌우 여백(윗줄·아랫줄 공통).
    static let stackedRowHorizontalPadding: CGFloat = 12

    private func stackedRowsLayout(center: AnyView) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    translationChip(showsCountWhenMultiple: true)
                }
                .frame(maxWidth: .infinity)

                // 폭이 빠듯할 때 제목이 먼저 자기 폭을 받고(칩 쪽 글자가 먼저 잘림), 남는 폭을 좌우 칸이 나눠 가진다.
                bookChapterTitleButton
                    .layoutPriority(1)

                // 오른쪽 빈 칸 — 왼쪽 칸과 같은 폭을 차지해 제목을 화면 가운데에 둔다.
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: 1)
                    .accessibilityHidden(true)
            }
            // 윗줄도 아랫줄과 같은 좌우 여백을 써서 두 줄의 내용 영역 양끝을 맞춘다(제목 가운데 위치는 좌우 대칭이라 여백과 무관).
            .padding(.horizontal, Self.stackedRowHorizontalPadding)
            .padding(.vertical, 4)
            .frame(minHeight: 48)
            // 아랫줄 간격·여백을 기존 두 줄(10pt, 기본 여백)보다 줄였다(2026-10-29) — 사이드바를 나란히 연 11인치 세로(상세 폭 약 580~594pt)에서
            // 이 배치가 `ViewThatFits`에 뽑히게 하려고. 버튼 크기(40pt)는 그대로다. 가운데 막대 안 간격도 호출부가 같은 값을 넘긴다.
            HStack(spacing: Self.stackedRowSpacing) {
                padLeftGroup
                center
                padRightGroup
            }
            .padding(.horizontal, Self.stackedRowHorizontalPadding)
            .padding(.vertical, 4)
        }
    }

    /// 아이패드 왼쪽 묶음: [사이드바 열기 | 책갈피 이동 | 책갈피]. 사이드바 열기는 사이드바가 닫혀 있을 때만.
    @ViewBuilder
    private var padLeftGroup: some View {
        if !hidesIconsWhileEditingSummary {
            BibleBarSegmentGroup {
                if showsSidebarOpenButton {
                    sidebarOpenItem
                    BibleBarSegmentDivider()
                }
                bookmarkListItem
                BibleBarSegmentDivider()
                bookmarkToggleItem
            }
            .fixedSize()
        }
    }

    /// 아이패드 오른쪽 묶음: [조회 이력 | 관련 콘텐츠]. 말씀 요약 편집 중에는 관련 콘텐츠 칸(= 말씀 요약 닫기)만 남는다.
    private var padRightGroup: some View {
        BibleBarSegmentGroup {
            if !hidesIconsWhileEditingSummary {
                historyItem
                BibleBarSegmentDivider()
            }
            relatedItem
        }
        .fixedSize()
    }

    /// 아이패드: 사이드바가 닫혀 있고 말씀 요약 편집 중이 아닐 때만 둔다(이전 툴바와 같은 조건 —
    /// 말씀 요약 편집 중에는 `SidebarVisibilityRequest`의 자동 복원 계약과 사이드바 값을 다투게 되므로 노출하지 않는다).
    private var showsSidebarOpenButton: Bool {
        !isPhone && !isEditingSummary && !IPadSidebarInspectorCoordination.shared.isSidebarVisible
    }

    // MARK: - 제목

    private func titleBlock(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            translationLine
            bookChapterTitleButton
        }
    }

    /// "책 장" 제목 — 탭하면 책/장 그리드 팝오버(장 이동 막대의 책 버튼과 같은 내용)가 열린다.
    private var bookChapterTitleButton: some View {
        Button {
            isBookPickerPresented = true
        } label: {
            // 타이틀 폰트는 국민대학교 성곡 세리프체(`SpecialPurposeFonts.titleSerif`, CC BY-ND — 설정 > 라이센스 탭 고지).
            // `.fontWeight(.semibold)`는 합성 볼드 보정이다(이전 아이패드 타이틀과 동일).
            HStack(spacing: 4) {
                Text("\(viewModel.selectedBook.displayName) \(viewModel.selectedChapter)장")
                    .font(.titleSerif(size: isPhone ? 19 : 21, relativeTo: .title3))
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.text.opacity(0.6))
            }
            .foregroundStyle(palette.text)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("책과 장 고르기")
        // 라벨이 보이는 글자("고린도전서 3장")를 덮으므로, 장 이동 막대에 책 버튼이 없는 아이패드 두 줄 배치(제목이 보이는 아이패드
        // 배치는 둘 다 책 버튼을 뺐다, 2026-10-28)에서는 현재 위치를 값으로 읽어 준다. 아이폰은 장 이동 막대의 검색 칸이 현재 위치("고전3")를
        // 보여 주므로 중복을 피하려고 붙이지 않는다. 글자는 위 `Text`와 같은 현지화 키를 쓴다.
        .modifier(OptionalAccessibilityValue(
            value: isPhone ? nil : Text("\(viewModel.selectedBook.displayName) \(viewModel.selectedChapter)장")
        ))
        // 포인터(트랙패드) 툴팁 — 아이패드 장 이동 막대의 책 버튼에 있던 것과 같은 문구(기존 키 재사용). 포인터가 없는 아이폰에는 붙이지 않는다.
        // `.help` 글자는 VoiceOver 힌트로도 쓰일 수 있어 라벨("책과 장 고르기")과 같은 말을 두 번 읽을 수 있다. 그러나 `.help`와
        // `.accessibilityHint`가 함께 있을 때 어느 쪽이 이기는지, 빈 힌트가 힌트 제거로 동작하는지는 문서화되어 있지 않아 덮어쓰지 않았다
        // (실기기 VoiceOver 확인 항목).
        .modifier(OptionalHelp(text: isPhone ? nil : "책과 장 고르기"))
        .popover(isPresented: $isBookPickerPresented) {
            BookChapterGridPopover(
                books: BooksProvider.shared.books,
                selectedBook: viewModel.selectedBook,
                selectedChapter: viewModel.selectedChapter
            ) { book, chapter in
                viewModel.selectBook(book, chapter: chapter)
                isBookPickerPresented = false
            }
        }
    }

    /// 제목 위 번역본 이름 줄. 활성 번역본이 둘 이상이면 탭해서 번역본 선택을 연다.
    /// 아이폰은 오른쪽 `translationIconItem`이 팝오버(시트)를 맡고 이 줄은 같은 값을 켜기만 한다 — 같은 바인딩에 `.popover`를
    /// 두 곳에 걸면 충돌하므로, 팝오버는 아이패드에서는 이 줄에만, 아이폰에서는 아이콘에만 붙인다.
    @ViewBuilder
    private var translationLine: some View {
        if !translationDisplayName.isEmpty {
            if showsTranslationPicker {
                Button {
                    isTranslationPickerPresented = true
                } label: {
                    HStack(spacing: 3) {
                        Text(translationDisplayName)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.strong)
                    .frame(minHeight: 22)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("번역본 선택")
                .popover(isPresented: isPhone ? .constant(false) : $isTranslationPickerPresented) {
                    translationPopoverContent
                }
            } else {
                Text(translationDisplayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.strong)
                    .lineLimit(1)
                    .frame(minHeight: 22)
            }
        }
    }

    /// 아이패드 번역본 칩 — 장 이동 막대와 같은 라운드 사각 버튼. 번역본이 하나뿐이면 글자만 보인다.
    /// 한 줄 배치(`singleRowLayout`)와 두 줄 "아이콘 아래줄" 배치(`stackedRowsLayout`)가 쓴다.
    /// `showsCountWhenMultiple`(두 줄 "아이콘 아래줄" 배치)이면 열이 2개 이상일 때 맨 왼쪽 열 이름 대신 "번역본 N"을 보인다 —
    /// 이 칩은 여러 번역본을 고르는 팝오버를 여는 자리라, 이름 하나만 보이면 화면 전체가 그 번역본인 것처럼 읽히기 때문이다
    /// (각 열의 이름은 `TranslationColumnView` 열 머리가 보인다).
    @ViewBuilder
    private func translationChip(showsCountWhenMultiple: Bool) -> some View {
        if !translationDisplayName.isEmpty {
            let countText = Text("번역본 \(viewModel.columns.count)")
            let chipText: Text = showsCountWhenMultiple && viewModel.columns.count > 1 ? countText : Text(translationDisplayName)
            // VoiceOver 값(2026-10-28): 라벨 "번역본 선택"이 보이는 글자를 덮으므로, 열이 1개면 번역본 이름, 2개 이상이면 "번역본 N"을
            // 읽어 준다. 한 줄 배치(①)도 같은 규칙이다(보이는 글자는 이름이어도 열이 여럿이면 개수를 읽는다 — 사용자 결정).
            let accessibilityText: Text = viewModel.columns.count > 1 ? countText : Text(translationDisplayName)
            if showsTranslationPicker {
                Button {
                    isTranslationPickerPresented = true
                } label: {
                    HStack(spacing: 4) {
                        chipText
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                }
                .buttonStyle(BibleBarButtonStyle(height: sizing.height, cornerRadius: sizing.radius, fontSize: 13))
                .accessibilityLabel("번역본 선택")
                .accessibilityValue(accessibilityText)
                .popover(isPresented: $isTranslationPickerPresented) {
                    translationPopoverContent
                }
            } else {
                // 버튼이 아닐 때(활성 번역본 1개, 말씀 요약 편집 중)도 같은 값 규칙을 쓴다. 라벨은 기존 키 "번역본"으로 두어
                // 보이는 글자와 값이 겹쳐 두 번 읽히지 않게 한다("번역본, 개역한글" / "번역본, 번역본 2").
                chipText
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.strong)
                    .lineLimit(1)
                    .accessibilityLabel("번역본")
                    .accessibilityValue(accessibilityText)
            }
        }
    }

    // MARK: - 아이콘 칸

    /// 묶음 안의 아이콘 한 칸. 모양(정사각 칸, 올림/눌림/활성 색)은 `BibleTopBarItemStyle`이 입힌다.
    private func item(
        _ systemImage: String, label: LocalizedStringKey, isActive: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: sizing.iconSize, weight: .semibold))
        }
        .buttonStyle(BibleTopBarItemStyle(isActive: isActive))
        .accessibilityLabel(label)
    }

    private var sidebarOpenItem: some View {
        item("sidebar.leading", label: "사이드바 열기") {
            IPadSidebarInspectorCoordination.shared.requestShowSidebar()
        }
    }

    private var bookmarkListItem: some View {
        item("list.star", label: "책갈피 이동") {
            isBookmarkListPresented = true
        }
        .popover(isPresented: $isBookmarkListPresented) {
            BookmarkListPopover(viewModel: viewModel) {
                isBookmarkListPresented = false
            }
        }
    }

    private var bookmarkToggleItem: some View {
        item(
            isCurrentPositionBookmarked ? "bookmark.fill" : "bookmark",
            label: isCurrentPositionBookmarked ? "책갈피 해제" : "책갈피 설정",
            isActive: isCurrentPositionBookmarked
        ) {
            // 대상 번역본이 없으면(빈 화면) 아무것도 하지 않는다. 아래 `.disabled`가 이 경우 버튼을 비활성화한다.
            guard let code = bookmarkTargetTranslationCode else { return }
            viewModel.toggleBookmarkForCurrentPosition(translationCode: code)
        }
        .disabled(bookmarkTargetTranslationCode == nil)
    }

    private var historyItem: some View {
        item("clock", label: "조회 이력") {
            isHistoryPresented = true
        }
        .popover(isPresented: $isHistoryPresented) {
            BibleReadingHistorySheet(viewModel: viewModel) {
                isHistoryPresented = false
            }
        }
    }

    /// 관련 콘텐츠 패널 토글. 말씀 요약 편집기가 이 자리를 빌려 쓰는 동안에는 `isRelatedContentPresented`를 토글해도 인스펙터가 계속
    /// 열려 있으므로(`.inspector`의 `get`이 `wordSummaryBeingEdited`도 봄) 같은 버튼이 "닫기"(뒷정리 포함)로 동작한다.
    private var relatedItem: some View {
        item(
            isEditingSummary ? "xmark.circle" : "sidebar.trailing",
            label: isEditingSummary ? "말씀 요약 닫기" : "관련 콘텐츠",
            isActive: isEditingSummary || isRelatedContentPresented
        ) {
            if isEditingSummary {
                onCloseWordSummary()
            } else {
                isRelatedContentPresented.toggle()
            }
        }
    }

    /// 아이폰 전용 번역본 선택 아이콘(아이패드는 번역본 이름 줄/칩이 대신한다).
    private var translationIconItem: some View {
        item("text.book.closed", label: "번역본 선택") {
            isTranslationPickerPresented = true
        }
        .popover(isPresented: $isTranslationPickerPresented) {
            translationPopoverContent
        }
    }

    private var translationPopoverContent: some View {
        TranslationPickerPopover(
            available: viewModel.availableTranslations,
            selected: viewModel.columns.map(\.registry.persistentModelID),
            maxSelection: viewModel.maxColumns
        ) { selected in
            // `TranslationPickerPopover.selectedIDs`가 선택 순서를 보존하는 배열이라 `Set` 변환 없이 그대로 넘긴다.
            viewModel.setDisplayedTranslations(selected)
            isTranslationPickerPresented = false
        }
    }
}

extension BibleBarSizing {
    /// 아이폰 상단바 아이콘 묶음 — 높이 36pt(다섯 칸이 180pt), 모서리 10pt.
    static let phoneTopBar = BibleBarSizing(height: 36, radius: 10, fontSize: 15, iconSize: 16, fieldFontSize: 15)
}

/// 값이 있을 때만 `accessibilityValue`를 붙인다(nil이면 아무것도 하지 않음).
private struct OptionalAccessibilityValue: ViewModifier {
    let value: Text?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let value {
            content.accessibilityValue(value)
        } else {
            content
        }
    }
}

/// 글자가 있을 때만 `.help`를 붙인다(nil이면 아무것도 하지 않음).
private struct OptionalHelp: ViewModifier {
    let text: LocalizedStringKey?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let text {
            content.help(text)
        } else {
            content
        }
    }
}

/// 상단바 아이콘 칸 스타일 — `BibleBarSegmentItemStyle`과 같은 정사각 칸에, 활성 상태(`isActive`)면 강조색 채움을 더한다.
private struct BibleTopBarItemStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        BibleTopBarItemBody(configuration: configuration, isActive: isActive)
    }
}

private struct BibleTopBarItemBody: View {
    let configuration: ButtonStyleConfiguration
    let isActive: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bibleBarSizing) private var sizing

    var body: some View {
        let palette = BibleBarPalette(environment: environment, colorScheme: colorScheme)
        let pressed = configuration.isPressed
        let fill: Color = isActive
            ? palette.strong.opacity(pressed ? 0.78 : 1)
            : palette.text.opacity(pressed ? BibleBarMetrics.fillOpacity + 0.06 : 0)
        configuration.label
            .foregroundStyle(isActive ? palette.strongForeground : palette.text)
            .frame(width: sizing.height, height: sizing.height)
            .background(fill)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : BibleBarMetrics.disabledOpacity)
    }
}
#endif
