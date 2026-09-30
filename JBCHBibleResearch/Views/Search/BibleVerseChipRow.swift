import SwiftUI
import BibleResearchModels
#if os(iOS)
import UIKit
#endif

//
//  BibleVerseChipRow.swift
//  JBCHBibleResearch
//
//  "책이름 장:절" 칩을 가로 스크롤로 나열하고, 탭하면 성경 조회 화면으로
//  이동시키는 재사용 컴포넌트.
//
//  아이폰과 맥·아이패드의 이동 분기(성경 탭으로 크로스탭 이동 vs
//  `NavigationLink(value:)`)가 사용처마다 어긋나지 않도록 한 곳에 모았다.
//
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

    /// `TranslationColumnView.crossReferenceTargetLabel`과 같은 "책이름 장:절" 표기.
    private func refLabel(_ ref: BibleVerseRef) -> String {
        let bookName = BooksProvider.shared.book(id: ref.bookId)?.nameKo ?? "책 \(ref.bookId)"
        return "\(bookName) \(ref.chapter):\(ref.verse)"
    }

    /// 아이폰에서는 `.searchable`이 활성인 조상 화면(SearchView)과 `NavigationLink(value:)`가
    /// 얽히는 문제가 있어 "성경" 탭의 `BibleReadingView`로 좌표만 전달하고,
    /// macOS/iPadOS에서는 조상 `NavigationStack`에 등록된 `BibleVerseDestinationRegistration`으로 push한다.
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
