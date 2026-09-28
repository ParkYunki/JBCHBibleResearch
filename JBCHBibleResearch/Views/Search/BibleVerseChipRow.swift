import SwiftUI
import BibleResearchModels
#if os(iOS)
import UIKit
#endif

//
//  BibleVerseChipRow.swift
//  JBCHBibleResearch
//
//  [2026-09-16 신설] "책이름 장:절" 칩을 가로 스크롤로 나열하고, 탭하면 성경
//  조회 화면으로 이동시키는 재사용 컴포넌트.
//
//  `PersonDetailView`/`ThemeDetailView`가 각각 독립적으로 갖고 있던 동일한
//  verseChipRow/verseRefLabel/verseChipButton 3종 세트를, 통합검색 화면
//  자체를 인물/주제/관계 카드로 전환하는 이번 작업에서 `RelationDetailView`가
//  세 번째로 필요로 하게 되면서 추출했다 — 이 프로젝트의 "세 번째 사용처가
//  생기기 전엔 공통 타입으로 추출하지 않는다" 관례(`SearchViewModel.storeCache`
//  상단 주석, `PersonDetailView.isPhoneIdiom` 주석 등 여러 곳에서 이미 확인된
//  원칙 — 정확히 지금이 그 3번째 시점이다)에 따른 것이다.
//
//  다른 3줄짜리 `isPhoneIdiom` 판정(`TranslationColumnView`/`SearchContentView`
//  등)은 이 프로젝트가 3곳 이상에서도 계속 복제해 온 전례가 있어 그대로
//  두지만, 이 컴포넌트는 아이폰/맥·아이패드 분기 로직(성경 조회로 크로스탭
//  이동 vs `NavigationLink(value:)`)이 여러 곳에서 완전히 동일하게 유지돼야
//  하는 안전 요구가 있다 — 세 번째로 그대로 복제하면 이후 한쪽만 고치고
//  다른 쪽을 놓치는 실수(특정 플랫폼에서만 조용히 다른 동작)가 나기 쉬워,
//  이번엔 통째로 추출하는 편이 더 안전하다고 판단했다.
//
//  ⚠️ [미검증] 이 세션엔 Xcode가 없어 컴파일 확인을 못 했다 — 이 프로젝트의
//  다른 신규 Swift 파일들과 같은 caveat.
//
struct BibleVerseChipRow: View {
    let refs: [BibleVerseRef]

    private var isPhoneIdiom: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(refs.enumerated()), id: \.offset) { _, ref in
                    chipButton(ref)
                }
            }
        }
    }

    /// [2026-09-16] `TranslationColumnView.crossReferenceTargetLabel`과 같은
    /// "책이름 장:절" 표기를 그대로 따른다.
    private func refLabel(_ ref: BibleVerseRef) -> String {
        let bookName = BooksProvider.shared.book(id: ref.bookId)?.nameKo ?? "책 \(ref.bookId)"
        return "\(bookName) \(ref.chapter):\(ref.verse)"
    }

    /// [2026-09-16] `SearchContentView.bibleVerseRow`와 정확히 같은 이유·같은
    /// 분기 — 아이폰에서 `NavigationLink(value:)`를 직접 쓰면 `.searchable`이
    /// 활성인 조상 화면(SearchView)과 얽혀 이미 확인된 문제가 재현될 수 있어,
    /// 아이폰에서는 "성경" 탭에 이미 떠 있는 `BibleReadingView`로 좌표만
    /// 전달하고, macOS/iPadOS에서는 조상 `NavigationStack`에 이미 등록된
    /// `BibleVerseDestinationRegistration`(`SearchContentView` 참고)을 그대로
    /// 이용해 값 기반으로 push한다.
    @ViewBuilder
    private func chipButton(_ ref: BibleVerseRef) -> some View {
        let chipLabel = Text(refLabel(ref))
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
            .foregroundStyle(Color.accentColor)

        if isPhoneIdiom {
            Button {
                AppNavigationRequest.shared.request(.bibleReading)
                BibleVerseNavigationRequest.shared.request(bookId: ref.bookId, chapter: ref.chapter, verse: ref.verse)
            } label: {
                chipLabel
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: BibleVerseDestination(bookId: ref.bookId, chapter: ref.chapter, verse: ref.verse)) {
                chipLabel
            }
        }
    }
}
