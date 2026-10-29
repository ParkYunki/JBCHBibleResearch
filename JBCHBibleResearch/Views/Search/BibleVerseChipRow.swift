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
//  아이폰과 맥·아이패드의 이동 분기(성경 탭 전환 vs 성경 새 창, `BibleVerseOpener`)가
//  사용처마다 어긋나지 않도록 한 곳에 모았다.
//
//
struct BibleVerseChipRow: View {
    let refs: [BibleVerseRef]

    /// [relverse1 2026-10-29] 구절 열기(`BibleVerseOpener`) — 맥·아이패드는 그 구절이 열린 성경 새 창, 아이폰과 다중 창을 못 쓰는 환경은
    /// "성경 조회" 섹션 전환. 예전에는 맥·아이패드가 `NavigationLink(value:)` push였는데, 한 `List` 행(장 카드/칩 줄) 안에 링크가 여러 개라
    /// 탭 대상이 불안정했고(`OutlineTreeView`·`SearchView.groupedVerseRow` 주석의 같은 문제), 아이패드에서는 push된 `BibleReadingView`가
    /// 내비게이션 바를 숨겨 뒤로 버튼도 없었다.
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    /// [relverse2] 이 화면이 들어 있는 메인 창 — 새 성경 창의 [메인 창으로]가 이 창을 앞으로 가져온다.
    @Environment(\.mainWindowID) private var mainWindowID

    private var verseOpener: BibleVerseOpener {
        BibleVerseOpener(openWindow: openWindow, supportsMultipleWindows: supportsMultipleWindows, originWindowID: mainWindowID)
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
        let bookName = BooksProvider.shared.book(id: ref.bookId)?.displayName ?? String(localized: "책 \(ref.bookId)")
        return "\(bookName) \(ref.chapter):\(ref.verse)"
    }

    /// 칩마다 독립된 plain `Button`이고, 누르면 `verseOpener`로 연다(맥·아이패드 새 창, 아이폰 성경 탭 전환).
    private func chipButton(_ ref: BibleVerseRef) -> some View {
        let chipLabel = Text(refLabel(ref))
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
            .foregroundStyle(Color.accentColor)

        return Button {
            verseOpener.open(bookId: ref.bookId, chapter: ref.chapter, verse: ref.verse)
        } label: {
            chipLabel
        }
        .buttonStyle(.plain)
    }
}
