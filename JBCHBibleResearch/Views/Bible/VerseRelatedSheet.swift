//
//  VerseRelatedSheet.swift
//  JBCHBibleResearch
//
//  성경 조회 절 번호 위 아이콘(`VerseRelatedIconStack`)을 누르면 열리는 "절 관련 내용" 통합 페이지.
//  관주 / 연구문서 / 내 설교 / 말씀 요약 / 구절 메모를 한 장에서 칩으로 오간다.
//  목업: mockup_verse_related_sheet.html
//
//  표시만 담당하며 항목을 눌렀을 때 무엇을 열지는 호출부(`VerseRow`)가 클로저로 결정한다
//  (관주 → 그 책/장으로 이동, 구절 메모 → 메모 시트, 연구문서/설교/말씀 요약 → 기존 `onSelectVerseMention`).
//

import SwiftUI
import BibleResearchModels

// MARK: - 종류

/// 통합 페이지가 담는 5종류. 선언 순서가 칩/아이콘 표시 순서다.
enum VerseRelatedKind: Int, CaseIterable, Identifiable, Hashable {
    case crossReference
    case document
    case sermon
    case wordSummary
    case memo

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .crossReference: return "관주"
        case .document: return "연구문서"
        case .sermon: return "내 설교"
        case .wordSummary: return "말씀 요약"
        case .memo: return "구절 메모"
        }
    }

    /// 종류를 구분하는 색 점 — 밤빛 남색/라이트 배경 모두에서 보이도록 중간 명도로 잡았다.
    /// 2026-10-07: 예전 파랑(#4C78B8)·청록(#2B8A94)·초록(#3F9A6E)이 서로 비슷해 구분이 어려워, 색상환을 따라
    /// 종류마다 색상각이 크게 벌어지도록 다시 골랐다(파랑 220° · 보라 285° · 빨강 5° · 초록 135° · 황금 41°).
    /// 빨강/초록은 색각 이상에서 헷갈릴 수 있어 초록을 밝게, 빨강을 진하게 둬 명도 차도 함께 두었다.
    var color: Color {
        switch self {
        case .crossReference: return Color(hex: "#3D6FD1") ?? .blue
        case .document: return Color(hex: "#8A5CC7") ?? .purple
        case .sermon: return Color(hex: "#C93B3B") ?? .red
        case .wordSummary: return Color(hex: "#47B26B") ?? .green
        case .memo: return Color(hex: "#E5A41C") ?? .orange
        }
    }
}

// MARK: - 내용

/// 한 절에 걸린 관련 내용 묶음. `VerseRow`가 이미 받은 값을 그대로 모은다(새 조회 없음).
struct VerseRelatedContent {
    var crossReferenceTargets: [BibleVerseRef] = []
    var phraseMemos: [UserMemo] = []
    var mentions: [VerseMention] = []

    /// 구절 메모 칩은 "이 절/표현에 단 메모"(`phraseMemos`)와 "메모 본문이 이 절을 언급"(`.memo` 언급)을 함께 담는다.
    private func mentions(of kind: VerseRelatedKind) -> [VerseMention] {
        switch kind {
        case .document: return mentions.filter { $0.sourceType == .document }
        case .sermon: return mentions.filter { $0.sourceType == .sermon }
        case .wordSummary: return mentions.filter { $0.sourceType == .wordSummary }
        case .memo: return mentions.filter { $0.sourceType == .memo }
        case .crossReference: return []
        }
    }

    func count(of kind: VerseRelatedKind) -> Int {
        switch kind {
        case .crossReference: return crossReferenceTargets.count
        case .memo: return phraseMemos.count + mentions(of: .memo).count
        case .document, .sermon, .wordSummary: return mentions(of: kind).count
        }
    }

    /// 0건인 종류는 빠진다.
    var availableKinds: [VerseRelatedKind] {
        VerseRelatedKind.allCases.filter { count(of: $0) > 0 }
    }

    var totalCount: Int {
        availableKinds.reduce(0) { $0 + count(of: $1) }
    }

    func items(of kind: VerseRelatedKind) -> [VerseRelatedItem] {
        switch kind {
        case .crossReference:
            return crossReferenceTargets.enumerated().map { offset, target in
                VerseRelatedItem(id: "link-\(offset)", kind: .crossReference, payload: .target(target))
            }
        case .memo:
            let own = phraseMemos.map {
                VerseRelatedItem(id: "memo-\($0.id)", kind: .memo, payload: .memo($0))
            }
            let mentioned = mentions(of: .memo).map {
                VerseRelatedItem(id: "mention-\($0.id)", kind: .memo, payload: .mention($0))
            }
            return own + mentioned
        case .document, .sermon, .wordSummary:
            return mentions(of: kind).map {
                VerseRelatedItem(id: "mention-\($0.id)", kind: kind, payload: .mention($0))
            }
        }
    }

    var allItems: [VerseRelatedItem] {
        availableKinds.flatMap { items(of: $0) }
    }
}

struct VerseRelatedItem: Identifiable {
    enum Payload {
        case target(BibleVerseRef)
        case memo(UserMemo)
        case mention(VerseMention)
    }

    let id: String
    let kind: VerseRelatedKind
    let payload: Payload
}

// MARK: - 아이콘 스택 (절 번호 위)

/// 절 번호 뱃지 위쪽에 겹쳐 그리는 색 점 스택 — 종류당 점 하나, 3개까지 겹쳐 보이고 나머지는 "+N".
/// 점마다 버튼이라 누른 점의 종류 칩이 먼저 선택된 채 열린다("+N"은 전체).
/// `.overlay`로 얹어 쓰므로 행 높이에는 영향을 주지 않는다.
struct VerseRelatedIconStack: View {
    let kinds: [VerseRelatedKind]
    /// nil이면 "전체" 칩으로 연다.
    let onOpen: (VerseRelatedKind?) -> Void

    private static let maxVisibleDots = 3
    private let dotSize: CGFloat = 13
    /// 점 하나의 좌우 탭 영역 여백(아래 `.padding(.horizontal, 2)`와 같은 값).
    private let hitPadding: CGFloat = 2
    /// 목업대로 이웃한 점이 지름의 50%만큼 겹치게 하는 HStack 간격(음수의 크기).
    /// 점마다 좌우 `hitPadding`이 레이아웃 폭에 포함되므로 그만큼을 더해야 눈에 보이는 원끼리 정확히 절반 겹친다
    /// (예전 `overlap = 5`는 이 여백 4를 빼면 실제로 1pt밖에 안 겹쳤다). 원 중심 간격 = dotSize + 2×hitPadding − overlap = dotSize/2.
    private var overlap: CGFloat { dotSize / 2 + hitPadding * 2 }

    private var settings: UserSettingsStore { .shared }

    /// 점 사이를 가르는 테두리색 — 본문 배경색(사용자 지정)을 우선하고, 없으면 시스템 배경.
    private var ringColor: Color {
        if let background = settings.bibleBackgroundColor { return background }
        #if os(iOS)
        return Color(UIColor.systemBackground)
        #else
        return Color(NSColor.textBackgroundColor)
        #endif
    }

    var body: some View {
        let visible = Array(kinds.prefix(Self.maxVisibleDots))
        let extra = kinds.count - visible.count
        HStack(spacing: -overlap) {
            ForEach(visible) { kind in
                Button {
                    onOpen(kind)
                } label: {
                    Circle()
                        .fill(kind.color)
                        .frame(width: dotSize, height: dotSize)
                        .overlay(Circle().strokeBorder(ringColor, lineWidth: 1.5))
                        // 눈에 보이는 점은 작아도 탭 영역은 넉넉히 둔다.
                        .padding(.horizontal, hitPadding)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(kind.title)
            }
            if extra > 0 {
                Button {
                    onOpen(nil)
                } label: {
                    Text("+\(extra)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.7) ?? Color.secondary)
                        .padding(.leading, overlap + 3)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("관련 내용 전체")
            }
        }
        .fixedSize()
    }
}

// MARK: - 통합 페이지

struct VerseRelatedSheet: View {
    /// 헤더 제목 — 예: "시편 119:7".
    let reference: String
    let content: VerseRelatedContent
    let onClose: () -> Void
    let onSelectTarget: (BibleVerseRef) -> Void
    /// 관주 대상 절의 미리보기 글(현재 번역본 본문). nil이면 "책 장:절"만 보인다.
    let previewProvider: (BibleVerseRef) -> String?
    let onSelectMemo: (UserMemo) -> Void
    let onSelectMention: (VerseMention) -> Void

    private enum Selection: Hashable {
        case all
        case kind(VerseRelatedKind)
    }

    @State private var selection: Selection
    /// 관주 미리보기 글 캐시 — 칩을 바꿀 때마다 본문을 다시 조회하지 않도록 열릴 때 한 번 채운다.
    @State private var previews: [BibleVerseRef: String] = [:]

    private var settings: UserSettingsStore { .shared }

    init(
        reference: String,
        content: VerseRelatedContent,
        initialKind: VerseRelatedKind?,
        onClose: @escaping () -> Void,
        onSelectTarget: @escaping (BibleVerseRef) -> Void,
        previewProvider: @escaping (BibleVerseRef) -> String?,
        onSelectMemo: @escaping (UserMemo) -> Void,
        onSelectMention: @escaping (VerseMention) -> Void
    ) {
        self.reference = reference
        self.content = content
        self.onClose = onClose
        self.onSelectTarget = onSelectTarget
        self.previewProvider = previewProvider
        self.onSelectMemo = onSelectMemo
        self.onSelectMention = onSelectMention

        let kinds = content.availableKinds
        if let initialKind, kinds.contains(initialKind) {
            _selection = State(initialValue: .kind(initialKind))
        } else if kinds.count == 1, let only = kinds.first {
            // 종류가 하나뿐이면 "전체" 칩이 의미가 없어 그 종류를 바로 보여 준다.
            _selection = State(initialValue: .kind(only))
        } else {
            _selection = State(initialValue: .all)
        }
    }

    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    private var textColor: Color { settings.bibleTextColor ?? .primary }
    private var mutedColor: Color { settings.bibleTextColor?.opacity(0.6) ?? Color.secondary }

    private var visibleItems: [VerseRelatedItem] {
        switch selection {
        case .all: return content.allItems
        case .kind(let kind): return content.items(of: kind)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ornamentalDivider
            if content.availableKinds.count > 1 {
                chipRow
            }
            list
        }
        .frame(maxHeight: isPhone ? .infinity : nil, alignment: .top)
        // 아이패드/macOS 팝오버는 칩을 바꿔도 크기가 출렁이지 않게 고정 크기, 아이폰 시트는 detent가 높이를 정한다.
        .modifier(VerseRelatedSheetSizing(isPhone: isPhone))
        .background(settings.bibleBackgroundColor ?? Color.clear)
        .onAppear(perform: loadPreviews)
    }

    // MARK: 헤더

    private var header: some View {
        HStack(spacing: 8) {
            Text(reference)
                .font(.headline)
                .foregroundStyle(textColor)
            Text("관련 내용")
                .font(.caption)
                .foregroundStyle(mutedColor)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(mutedColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("닫기")
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    /// 가로선 - sparkle - 가로선(관주 팝업/책갈피 목록과 같은 장식).
    private var ornamentalDivider: some View {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // MARK: 칩

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(title: "전체", count: content.totalCount, dot: nil, isOn: selection == .all) {
                    selection = .all
                }
                ForEach(content.availableKinds) { kind in
                    chip(
                        title: kind.title, count: content.count(of: kind), dot: kind.color,
                        isOn: selection == .kind(kind)
                    ) {
                        selection = .kind(kind)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func chip(title: String, count: Int, dot: Color?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let dot {
                    Circle().fill(dot).frame(width: 8, height: 8)
                }
                Text(title)
                    .font(.footnote.weight(.bold))
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .opacity(0.65)
            }
            .foregroundStyle(isOn ? Color.white : textColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isOn ? JBCHCategoryPalette.wine : (settings.bibleTextColor?.opacity(0.1) ?? Color.secondary.opacity(0.15)),
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: 목록

    private var list: some View {
        List(visibleItems) { item in
            row(for: item)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(settings.bibleBackgroundColor ?? Color.clear)
        .listRowSeparatorTint(JBCHCategoryPalette.wood.opacity(0.15))
    }

    /// "전체"일 때만 행마다 종류 라벨을 붙인다(한 종류만 볼 때는 칩이 이미 알려 준다).
    private var showsKindLabel: Bool {
        if case .all = selection { return true }
        return false
    }

    @ViewBuilder
    private func row(for item: VerseRelatedItem) -> some View {
        Button {
            select(item)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    if showsKindLabel {
                        HStack(spacing: 5) {
                            Circle().fill(item.kind.color).frame(width: 7, height: 7)
                            Text(item.kind.title)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(mutedColor)
                        }
                    }
                    rowBody(for: item)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.4) ?? Color.secondary.opacity(0.6))
            }
            .padding(.leading, 10)
            // 행 왼쪽 종류색 막대 — 기존 관주 팝업의 "책등" 패턴.
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(item.kind.color)
                    .frame(width: 3)
                    .padding(.vertical, 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .accessibilityLabel(accessibilityText(for: item))
    }

    @ViewBuilder
    private func rowBody(for item: VerseRelatedItem) -> some View {
        switch item.payload {
        case .target(let target):
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(bookName(target))
                        .font(.body.weight(.bold))
                        .foregroundStyle(Color("AccentColor"))
                    Text("\(target.chapter):\(target.verse)")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.7) ?? Color.secondary)
                }
                // 현재 번역본의 해당 절 본문을 두 줄까지 — 눌러 보지 않고도 내용을 알 수 있게 한다.
                if let preview = previews[target] {
                    Text(preview)
                        .font(.callout)
                        .foregroundStyle(textColor.opacity(0.85))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
        case .memo(let memo):
            Text(memoLabel(memo))
                .font(.callout)
                .foregroundStyle(textColor)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        case .mention(let mention):
            Text(mention.snippet.isEmpty ? mention.searchText : mention.snippet)
                .font(.callout)
                .foregroundStyle(textColor)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
    }

    /// 관주 대상 절의 본문을 한 번에 조회해 둔다(대상은 보통 수 개~십수 개).
    private func loadPreviews() {
        guard previews.isEmpty else { return }
        var loaded: [BibleVerseRef: String] = [:]
        for target in content.crossReferenceTargets where loaded[target] == nil {
            if let text = previewProvider(target) { loaded[target] = text }
        }
        previews = loaded
    }

    private func select(_ item: VerseRelatedItem) {
        onClose()
        switch item.payload {
        case .target(let target): onSelectTarget(target)
        case .memo(let memo): onSelectMemo(memo)
        case .mention(let mention): onSelectMention(mention)
        }
    }

    private func bookName(_ target: BibleVerseRef) -> String {
        BooksProvider.shared.book(id: target.bookId)?.nameKo ?? "책 \(target.bookId)"
    }

    private func memoLabel(_ memo: UserMemo) -> String {
        let trimmed = memo.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(내용 없음)" : trimmed
    }

    private func accessibilityText(for item: VerseRelatedItem) -> String {
        switch item.payload {
        case .target(let target):
            let label = "\(item.kind.title) \(bookName(target)) \(target.chapter):\(target.verse)"
            return previews[target].map { "\(label) \($0)" } ?? label
        case .memo(let memo): return "\(item.kind.title) \(memoLabel(memo))"
        case .mention(let mention):
            return "\(item.kind.title) \(mention.snippet.isEmpty ? mention.searchText : mention.snippet)"
        }
    }
}

/// 아이폰(시트)은 중간/큰 두 단계 높이, 아이패드/macOS(팝오버)는 고정 크기.
private struct VerseRelatedSheetSizing: ViewModifier {
    let isPhone: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
        if isPhone {
            content
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        } else {
            content.frame(width: 360, height: 440)
        }
        #else
        content.frame(width: 360, height: 440)
        #endif
    }
}
