//
//  ChurchYouthEasterEgg.swift
//  JBCHBibleResearch
//
//  이스터 에그 — 통합검색에서 의미검색(질문형 검색 토글 켬) 상태로 "대구중부교회 청년회"를 입력해 검색(엔터)하면
//  일반 검색 대신 전체 화면 오버레이가 열린다. 토글이 꺼진 일반 검색에서는 반응하지 않는다.
//  따뜻한 인사말 화면 → "함께 달려볼까요?" → 점프로 걸림돌을 넘는 달리기 게임(탭/스페이스바/↑키).
//
//  - 트리거: `ChurchYouthEasterEgg.matches(_:)` — 공백·줄바꿈·대소문자를 무시한 정확 일치. `SearchViewModel.searchImmediately()`가
//    `isQuestionSearchEnabled`(의미검색) 상태에서만 검색 이력 기록/실제 검색보다 먼저 확인해, 이 검색어는 이력에도 남지 않고
//    결과 목록도 만들지 않는다.
//  - 표시: iOS/iPadOS는 `.fullScreenCover`, macOS는 `fullScreenCover`가 없어 콘텐츠 영역을 덮는 `.overlay`(`ChurchYouthEasterEggPresenter`).
//  - 게임 규칙은 `YouthRunnerGame`(시간 기반 시뮬레이션, 프레임 간격 상한 1/20초), 그림은 `Canvas` 한 장으로 그린다.
//  - 최고 점수는 `UserDefaults`(`@AppStorage`)에 저장한다.
//  - 인사말 화면: 화면 중앙에 사진 썸네일을 2줄(한 줄 5장, 최대 88pt)로(`EasterEggPhotoStrip` — Assets.xcassets의 `EasterEgg01`~`EasterEgg10`
//    이미지 세트 중 존재하는 것만 사용, 하나도 없으면 줄 자체를 숨긴다. 일부러 작게만 보이고 확대/전환 동작은 없다)
//    + 시편 119:32 / 119:33-34 두 구절(`EasterEggVerse` — 앱 번들 성경 DB에서 본문을 읽는다).
//

import SwiftUI
import BibleResearchModels
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - 트리거

enum ChurchYouthEasterEgg {
    /// 공백을 모두 뺀 정규화 형태. 한글 자모 분리(NFD) 입력이 섞여도 같은 문자열이 되도록 아래 `matches`에서 NFC로 맞춘다.
    private static let normalizedKeyword = "대구중부교회청년회"

    static func matches(_ query: String) -> Bool {
        let normalized = query.precomposedStringWithCanonicalMapping
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .lowercased()
        return normalized == normalizedKeyword
    }
}

// MARK: - 표시(플랫폼별)

struct ChurchYouthEasterEggPresenter: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(isPresented: $isPresented) {
            ChurchYouthEasterEggView(onClose: { isPresented = false })
        }
        #else
        content
            .overlay {
                if isPresented {
                    ChurchYouthEasterEggView(onClose: { isPresented = false })
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isPresented)
        #endif
    }
}

// MARK: - 색

private enum EasterEggPalette {
    static let skyTop = Color(red: 0.05, green: 0.09, blue: 0.22)
    static let skyBottom = Color(red: 0.43, green: 0.22, blue: 0.30)
    static let gold = Color(red: 0.96, green: 0.77, blue: 0.43)
    static let ground = Color(red: 0.09, green: 0.11, blue: 0.19)
    static let groundTop = Color(red: 0.22, green: 0.26, blue: 0.37)
    static let rock = Color(red: 0.70, green: 0.66, blue: 0.62)
    static let thorn = Color(red: 0.62, green: 0.38, blue: 0.34)
    static let tear = Color(red: 0.55, green: 0.78, blue: 0.98)
    static let valleyTop = Color(red: 0.03, green: 0.03, blue: 0.08)
    static let valleyDeep = Color.black
}

// MARK: - 전체 화면 (인사말 → 게임)

struct ChurchYouthEasterEggView: View {
    let onClose: () -> Void

    private enum Stage { case greeting, game }
    @State private var stage: Stage = .greeting
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [EasterEggPalette.skyTop, EasterEggPalette.skyBottom],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            StarField()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            switch stage {
            case .greeting:
                greeting
                    .transition(.opacity)
            case .game:
                YouthRunnerGameView()
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) { closeButton }
        .focusable()
        .focused($isFocused)
        #if os(macOS)
        .focusEffectDisabled()
        #endif
        .onAppear { isFocused = true }
        .onKeyPress(keys: [.escape], phases: .down) { _ in
            onClose()
            return .handled
        }
        .animation(.easeInOut(duration: 0.3), value: stage)
        .preferredColorScheme(.dark)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.callout.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.16), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(16)
        .accessibilityLabel("닫기")
    }

    // MARK: 인사말

    @State private var verses = EasterEggVerse.placeholders
    @State private var didLoadVerses = false

    private var greeting: some View {
        GeometryReader { proxy in
            ScrollView {
                greetingText
                    // 세로로 눌리지 않고 내용의 원래 높이를 그대로 쓰게 한다(넘치면 스크롤). 안 그러면 긴 말씀이 "…"로 잘린다.
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)
                    // 위·아래를 같은 크기로 비워 닫기 버튼과 겹치지 않으면서 내용이 세로 가운데에 오게 한다.
                    .padding(.vertical, 56)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear {
            guard !didLoadVerses else { return }
            didLoadVerses = true
            verses = EasterEggVerse.loadAll()
        }
    }

    private var greetingText: some View {
        VStack(spacing: 22) {
            Image(systemName: "sparkles")
                .font(.system(size: 30))
                .foregroundStyle(EasterEggPalette.gold)

            VStack(spacing: 8) {
                Text("대구중부교회 청년회")
                    .font(.custom(SpecialPurposeFonts.titleSerif, size: 32, relativeTo: .largeTitle))
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                Text("숨겨진 문을 찾아오셨네요. 환영합니다.")
                    .font(.headline)
                    .foregroundStyle(EasterEggPalette.gold)
            }

            Text("함께 기도하고, 함께 웃고, 함께 했던 여러분을 대구중부교회 청년형제자매님들을 기억하겠습니다. 이 앱을 여는 날마다 말씀 안에서 작은 기쁨과 힘을 얻으시길 바랍니다.")
                .font(.body)
                .lineSpacing(5)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: 460)

            // 화면 가운데에 5장씩 2줄 — 어떤 사진인지 정도만 보이게 한다.
            if !EasterEggPhotos.availableNames.isEmpty {
                EasterEggPhotoStrip(names: EasterEggPhotos.availableNames)
            }

            // 말씀은 구절마다 따로 카드로 둔다(시편 119:32 / 119:33-34).
            VStack(spacing: 10) {
                ForEach(verses) { verse in
                    VStack(spacing: 6) {
                        if let text = verse.text {
                            Text(text)
                                .font(.callout)
                                .lineSpacing(4)
                                .lineLimit(nil)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white.opacity(0.92))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(verse.reference)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(EasterEggPalette.gold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .frame(maxWidth: 460)

            Button {
                stage = .game
            } label: {
                Label("함께 달려볼까요?", systemImage: "figure.run")
                    .font(.headline)
                    .foregroundStyle(EasterEggPalette.skyTop)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 14)
                    .background(EasterEggPalette.gold, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
    }
}

// MARK: - 말씀 (시편 119:32 / 119:33-34)

private struct EasterEggVerse: Identifiable {
    let id: String
    /// 화면에 보이는 참조 표기 — 예: "시편 119:33-34".
    let reference: String
    /// 앱 번들 성경 DB의 본문. 읽지 못하면 nil(참조만 보인다).
    let text: String?

    private static let chapter = 119
    /// 구절을 분리해서 보여준다: 32절 / 33-34절.
    private static let ranges: [(start: Int, end: Int)] = [(32, 32), (33, 34)]

    private static func label(bookName: String, start: Int, end: Int) -> String {
        start == end ? "\(bookName) \(chapter):\(start)" : "\(bookName) \(chapter):\(start)-\(end)"
    }

    /// DB를 열기 전 첫 화면용 — 참조만 있다.
    static var placeholders: [EasterEggVerse] {
        ranges.map { EasterEggVerse(id: "\($0.start)-\($0.end)", reference: label(bookName: "시편", start: $0.start, end: $0.end), text: nil) }
    }

    /// `ThemeDetailView`/`SermonVerseReferencePicker`와 같은 방식(번들 기본 성경 DB, `versionCode: nil`)으로 본문을 읽는다.
    /// 범위 안의 절 중 하나라도 못 읽으면 일부만 보이는 일이 없도록 그 구절은 참조만 보여준다.
    static func loadAll() -> [EasterEggVerse] {
        let psalms = BooksProvider.shared.books.first { $0.nameKo == "시편" }
        let store = try? BibleReferenceStore(filePath: TranslationBootstrap.resolvedBundledDatabaseURL().path)
        let bookName = psalms?.nameKo ?? "시편"
        return ranges.map { range in
            var text: String?
            if let psalms, let store {
                let contents = (range.start...range.end).compactMap { number in
                    try? store.verse(bookId: psalms.bookId, chapter: chapter, verse: number, versionCode: nil)?.content
                }
                if contents.count == range.end - range.start + 1 {
                    text = contents.joined(separator: " ")
                }
            }
            return EasterEggVerse(
                id: "\(range.start)-\(range.end)",
                reference: label(bookName: bookName, start: range.start, end: range.end),
                text: text
            )
        }
    }
}

// MARK: - 사진 슬라이드

/// 인사말 화면에 넣을 사진. Assets.xcassets에 `EasterEgg01` ~ `EasterEgg10` 이름의 이미지 세트를 추가하면 번호순으로 나온다.
/// 없는 번호는 건너뛰고, 하나도 없으면 사진 영역이 나타나지 않는다(빌드/동작에 영향 없음).
private enum EasterEggPhotos {
    static let maxCount = 10

    /// 앱 실행 중 한 번만 계산한다(에셋은 번들에 고정).
    static let availableNames: [String] = (1...maxCount)
        .map { String(format: "EasterEgg%02d", $0) }
        .filter { exists($0) }

    private static func exists(_ name: String) -> Bool {
        #if os(iOS)
        return UIImage(named: name) != nil
        #else
        return NSImage(named: name) != nil
        #endif
    }
}

/// 정사각 썸네일 격자(한 줄 5장, 2줄). 사진 속 인물이 너무 또렷하게 드러나지 않도록 한 장을 크지 않게(최대 88pt) 보여주고,
/// 화면이 좁으면 칸이 같은 비율로 줄어든다(5칸 × 88 + 간격 4 × 6 = 464pt 미만이면 축소).
/// 탭해서 확대하거나 넘기는 동작은 없다. 사진은 가운데 기준으로 정사각형에 맞게 잘린다(`scaledToFill`).
private struct EasterEggPhotoStrip: View {
    let names: [String]

    private static let columnCount = 5
    private static let maxSide: CGFloat = 88
    private static let spacing: CGFloat = 6

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(maximum: Self.maxSide), spacing: Self.spacing), count: Self.columnCount),
            spacing: Self.spacing
        ) {
            ForEach(names, id: \.self) { name in
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        Image(name)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(EasterEggPalette.gold.opacity(0.45), lineWidth: 1)
                    }
            }
        }
        .frame(maxWidth: CGFloat(Self.columnCount) * Self.maxSide + CGFloat(Self.columnCount - 1) * Self.spacing)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("청년회 사진 \(names.count)장")
    }
}

/// 인사말/게임 뒤에 깔리는 별. 위치는 인덱스로 결정되는 값이라 매번 같고, 한 번만 그린다.
private struct StarField: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<70 {
                let x = Self.hash(index, 1) * size.width
                let y = Self.hash(index, 2) * size.height * 0.62
                let radius = 0.6 + Self.hash(index, 3) * 1.3
                let alpha = 0.25 + Self.hash(index, 4) * 0.55
                let rect = CGRect(x: x, y: y, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
            }
        }
    }

    /// 0..<1 범위의 결정적 의사난수.
    private static func hash(_ index: Int, _ salt: Int) -> CGFloat {
        let value = sin(Double(index * 127 + salt * 311) * 12.9898) * 43758.5453
        return CGFloat(value - value.rounded(.down))
    }
}

// MARK: - 게임 모델

private struct RunnerObstacle {
    /// 걸림돌 네 가지 — 바위(고난), 가시덤불(무시), 눈물방울(눈물), 땅이 갈라진 골짜기(사망의 음침한 골짜기).
    /// 앞의 셋은 위로 뛰어 넘는 장애물이고, 골짜기는 땅이 끊긴 구간이라 공중에 떠서 건너야 한다.
    /// 넘어졌을 때 종류별 위로 문구를 보여준다.
    enum Kind: CaseIterable {
        case rock, thorn, tear, valley

        /// 덩어리(1~3개)로 붙여 놓을 수 있는 지상 장애물. 골짜기는 항상 단독으로 배치한다.
        static let groundKinds: [Kind] = [.rock, .thorn, .tear]

        var label: String {
            switch self {
            case .rock: return "고난"
            case .thorn: return "무시"
            case .tear: return "눈물"
            case .valley: return "사망의 음침한 골짜기"
            }
        }

        var fallTitle: String {
            switch self {
            case .valley: return "골짜기에 빠졌어요"
            default: return "\(label)에 걸려 넘어졌어요"
            }
        }

        var comfort: String {
            switch self {
            case .rock: return "고난은 지나가요. 다시 일어나 함께 달려요"
            case .thorn: return "상처받아도 괜찮아요. 우리는 서로의 편이에요"
            case .tear: return "눈물은 헛되지 않아요. 다시 일어나요"
            case .valley: return "골짜기를 지날 때에도 주님이 함께하세요. 다시 일어나 달려요"
            }
        }
    }
    let id: Int
    var x: CGFloat
    let width: CGFloat
    let height: CGFloat
    let kind: Kind
}

@MainActor
@Observable
private final class YouthRunnerGame {
    enum Phase { case ready, playing, over }

    // 화면 전환(오버레이)에만 쓰는 값은 관찰하고, 프레임마다 바뀌는 값은 관찰에서 뺀다(Canvas가 매 프레임 직접 읽는다).
    private(set) var phase: Phase = .ready
    private(set) var displayScore = 0
    /// 넘어진 원인 — 게임 오버 문구에 쓴다.
    private(set) var lastHitKind: RunnerObstacle.Kind?

    @ObservationIgnored var size: CGSize = .zero
    @ObservationIgnored private(set) var playerLift: CGFloat = 0
    @ObservationIgnored private(set) var obstacles: [RunnerObstacle] = []
    @ObservationIgnored private(set) var distance: CGFloat = 0
    @ObservationIgnored private(set) var scroll: CGFloat = 0
    @ObservationIgnored private(set) var milestoneText: String?
    @ObservationIgnored private(set) var milestoneExpires: Date = .distantPast
    /// 골짜기에 빠졌을 때 아래로 떨어진 깊이(px). 그리기에서 달리는 사람을 이만큼 내려 보낸다.
    @ObservationIgnored private(set) var fallDepth: CGFloat = 0

    @ObservationIgnored private var velocity: CGFloat = 0
    @ObservationIgnored private var speed: CGFloat = YouthRunnerGame.baseSpeed
    @ObservationIgnored private var nextSpawnDistance: CGFloat = 0
    /// 이번 판에서 달린 시간(초). 가속도·장애물 밀도의 난이도 기준이다.
    @ObservationIgnored private var elapsed: CGFloat = 0
    @ObservationIgnored private var scoreExact: Double = 0
    @ObservationIgnored private var obstacleCounter = 0
    /// 직전 배치가 골짜기였는지 — 골짜기가 연달아 나오지 않게 한다.
    @ObservationIgnored private var lastSpawnWasValley = false
    @ObservationIgnored private var nextMilestoneIndex = 0
    @ObservationIgnored private var lastTick: Date?
    @ObservationIgnored private var overAt: Date = .distantPast

    static let playerSize: CGFloat = 46
    static let playerXRatio: CGFloat = 0.18
    private static let baseSpeed: CGFloat = 300
    /// 속도 상한의 절대값. 실제 상한은 화면 너비에 맞춰 더 낮아질 수 있다(`currentMaxSpeed`).
    private static let maxSpeedCeiling: CGFloat = 780
    /// 가속도(px/s²)는 시작 8에서 시간이 지날수록 커진다: 8 + 0.24 × 경과초 (약 38초에 17).
    private static let baseAcceleration: CGFloat = 8
    private static let accelerationGrowth: CGFloat = 0.24
    /// 난이도(0→1)가 최대가 되는 경과 시간(초).
    private static let rampDuration: CGFloat = 70
    /// 골짜기는 시작 후 이 시간(초)이 지나야 나온다 — 처음에는 점프 하나만 익히게 한다.
    private static let valleyStartTime: CGFloat = 12
    /// 골짜기 낙하 연출 속도(px/s)와 최대 깊이(px).
    private static let fallSpeed: CGFloat = 340
    private static let fallMaxDepth: CGFloat = 90
    /// 이 깊이에 닿으면 완전히 투명해진다(그리기에서 사용).
    static let fallFadeDepth: CGFloat = 80
    private static let gravity: CGFloat = 2400
    private static let jumpVelocity: CGFloat = 820
    private static let milestones: [(score: Int, text: String)] = [
        (100, "좋아요!"), (250, "잘 달리고 있어요"), (500, "믿음의 경주, 멋져요!"), (800, "청년회 파이팅!")
    ]

    /// 탭/스페이스바/↑키 공통 입력 — 상태에 따라 시작, 점프, 다시 시작.
    func handleInput() {
        switch phase {
        case .ready:
            start()
        case .playing:
            guard playerLift == 0 else { return }   // 공중에서는 다시 뛰지 않는다.
            velocity = Self.jumpVelocity
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        case .over:
            // 넘어지는 순간의 연타로 바로 재시작되지 않게 잠깐 막는다.
            if Date().timeIntervalSince(overAt) > 0.5 { start() }
        }
    }

    private func start() {
        phase = .playing
        playerLift = 0
        velocity = 0
        obstacles = []
        fallDepth = 0
        lastSpawnWasValley = false
        distance = 0
        speed = Self.baseSpeed
        nextSpawnDistance = 380
        elapsed = 0
        scoreExact = 0
        displayScore = 0
        nextMilestoneIndex = 0
        milestoneText = nil
        lastTick = nil
    }

    /// 프레임마다 호출. 시간 간격은 1/20초로 제한해, 화면이 잠시 멈췄다 돌아와도 장애물을 통과하는 일이 없게 한다.
    func step(now: Date) {
        guard let last = lastTick else {
            lastTick = now
            return
        }
        lastTick = now
        let dt = CGFloat(min(max(now.timeIntervalSince(last), 0), 1.0 / 20.0))
        switch phase {
        case .ready:
            scroll += 40 * dt
        case .over:
            // 골짜기에 빠졌으면 아래로 떨어지는 모습을 잠깐 보여준다.
            if lastHitKind == .valley, fallDepth < Self.fallMaxDepth {
                fallDepth = min(Self.fallMaxDepth, fallDepth + Self.fallSpeed * dt)
            }
        case .playing:
            advance(dt: dt, now: now)
        }
    }

    private func advance(dt: CGFloat, now: Date) {
        elapsed += dt
        // 시간이 지날수록 가속도 자체가 커진다. 상한은 장애물이 나타나서 부딪히기까지 최소 0.45초가 남도록 화면 너비로 제한한다.
        let acceleration = Self.baseAcceleration + Self.accelerationGrowth * elapsed
        speed = min(currentMaxSpeed, speed + acceleration * dt)
        distance += speed * dt
        scroll += speed * dt

        if playerLift > 0 || velocity > 0 {
            velocity -= Self.gravity * dt
            playerLift += velocity * dt
            if playerLift <= 0 {
                playerLift = 0
                velocity = 0
            }
        }

        for index in obstacles.indices { obstacles[index].x -= speed * dt }
        obstacles.removeAll { $0.x + $0.width < -30 }

        if distance >= nextSpawnDistance, size.width > 1 { spawnObstacle() }

        scoreExact += Double(dt) * 12
        let score = Int(scoreExact)
        if score != displayScore {
            displayScore = score
            if nextMilestoneIndex < Self.milestones.count, score >= Self.milestones[nextMilestoneIndex].score {
                milestoneText = Self.milestones[nextMilestoneIndex].text
                milestoneExpires = now.addingTimeInterval(1.8)
                nextMilestoneIndex += 1
            }
        }

        if let hit = hitObstacle() { endGame(hitting: hit) }
    }

    /// 화면 너비 기준 속도 상한 — 오른쪽 끝에서 나타난 장애물이 플레이어에게 닿기까지 최소 0.45초를 보장한다.
    private var currentMaxSpeed: CGFloat {
        guard size.width > 1 else { return Self.baseSpeed + 60 }
        let reactable = size.width * (1 - Self.playerXRatio) / 0.45
        return min(Self.maxSpeedCeiling, max(Self.baseSpeed + 60, reactable))
    }

    /// 0(처음) → 1(70초 이후). 장애물 간격과 연속 배치 확률에 쓴다.
    private var difficulty: CGFloat { min(1, elapsed / Self.rampDuration) }

    private func makeObstacle(x: CGFloat) -> RunnerObstacle {
        let kind = RunnerObstacle.Kind.groundKinds.randomElement() ?? .rock
        let width: CGFloat
        let height: CGFloat
        switch kind {
        case .rock:
            width = CGFloat.random(in: 26...40)
            height = CGFloat.random(in: 30...54)
        case .thorn:
            width = CGFloat.random(in: 28...42)
            height = CGFloat.random(in: 26...40)
        case .tear:
            width = CGFloat.random(in: 22...30)
            height = CGFloat.random(in: 34...50)
        case .valley:
            // groundKinds에는 없어 도달하지 않는다(switch 완결성용).
            width = 60
            height = 0
        }
        obstacleCounter += 1
        return RunnerObstacle(id: obstacleCounter, x: x, width: width, height: height, kind: kind)
    }

    /// 땅이 끊긴 골짜기. 폭은 현재 속도에 비례해 정한다: 판정은 플레이어 중심이 (폭 − 8) 구간을 지나는 동안 공중에 떠 있는지로 하므로,
    /// 건너는 데 필요한 시간 (폭 − 8) / 속도 = 0.20~0.34초이다. 점프 체공은 약 0.68초(2 × 820 / 2400)라 타이밍 여유가 최소 0.34초 남는다.
    /// (속도는 생성 후 도착까지 몇 % 더 오르지만 위 여유 안에 들어간다.) 높이는 쓰지 않아 0이다.
    private func makeValley(x: CGFloat) -> RunnerObstacle {
        let width = 8 + speed * CGFloat.random(in: 0.20...0.34)
        obstacleCounter += 1
        return RunnerObstacle(id: obstacleCounter, x: x, width: width, height: 0, kind: .valley)
    }

    /// 장애물 한 덩어리(1~3개)를 오른쪽 화면 밖에 배치한다.
    /// 덩어리 안의 장애물은 한 번의 점프로 모두 넘을 수 있을 때만 붙인다:
    /// 점프로 가장 큰 장애물(54) 위에 머무는 시간은 약 0.55초이므로, (덩어리 폭 + 플레이어 폭 24) ≤ 속도 × 0.42 로 여유 시간 0.13초를 남긴다.
    private func spawnObstacle() {
        let startX = size.width + 24

        // 골짜기: 일정 시간 뒤부터, 직전에 골짜기가 나오지 않았을 때만, 단독으로 배치한다.
        // 앞 장애물을 넘고 착지한 뒤 다시 뛸 시간을 위해 시작 위치를 속도 × 0.12초만큼 더 뒤로 민다.
        if elapsed > Self.valleyStartTime, !lastSpawnWasValley,
           Double.random(in: 0..<1) < 0.16 + 0.12 * Double(difficulty) {
            let shift = speed * 0.12
            let valley = makeValley(x: startX + shift)
            obstacles.append(valley)
            lastSpawnWasValley = true
            let d = difficulty
            nextSpawnDistance = distance + shift + valley.width + speed * CGFloat.random(in: (0.95 - 0.43 * d)...(1.7 - 0.72 * d))
            return
        }
        lastSpawnWasValley = false

        let first = makeObstacle(x: startX)
        var cluster = [first]
        var extent = first.width      // 덩어리 전체의 가로 길이(첫 장애물 왼쪽 ~ 마지막 오른쪽)

        // 시간이 지날수록 연속 배치 확률이 올라간다. 처음 8초는 한 개씩만 나온다.
        if elapsed > 8 {
            let chance = 0.15 + 0.55 * Double(difficulty)
            var probability = chance
            while cluster.count < 3, Double.random(in: 0..<1) < probability {
                let gap = CGFloat.random(in: 12...26)
                let candidate = makeObstacle(x: startX + extent + gap)
                let candidateExtent = extent + gap + candidate.width
                // 충돌 판정은 장애물 좌우 4px씩 안쪽이므로 8을 뺀다.
                guard candidateExtent - 8 + 24 <= speed * 0.42 else { break }
                cluster.append(candidate)
                extent = candidateExtent
                probability *= 0.6
            }
        }
        obstacles.append(contentsOf: cluster)

        // 덩어리 끝에서 다음 덩어리 시작까지의 시간 간격: 처음 0.95~1.7초 → 70초 뒤 0.52~0.98초.
        // (점프 체공 약 0.68초 + 재점프 반응 여유를 남기는 하한. 도착할 때쯤 속도가 약간 더 빨라지는 것까지 감안해 0.52로 둔다.)
        let d = difficulty
        let low = 0.95 - 0.43 * d
        let high = 1.7 - 0.72 * d
        nextSpawnDistance = distance + extent + speed * CGFloat.random(in: low...high)
    }

    private func hitObstacle() -> RunnerObstacle? {
        let playerX = size.width * Self.playerXRatio
        let left = playerX + 11
        let right = playerX + Self.playerSize - 11
        let center = playerX + Self.playerSize / 2
        for obstacle in obstacles {
            if obstacle.kind == .valley {
                // 골짜기는 발 위치(플레이어 중심)가 끊긴 땅 위에 있고, 땅에서 거의 떠 있지 않을 때 빠진다.
                if center > obstacle.x + 4, center < obstacle.x + obstacle.width - 4, playerLift < 6 { return obstacle }
                continue
            }
            let obstacleLeft = obstacle.x + 4
            let obstacleRight = obstacle.x + obstacle.width - 4
            if right > obstacleLeft, left < obstacleRight, playerLift < obstacle.height - 4 { return obstacle }
        }
        return nil
    }

    private func endGame(hitting obstacle: RunnerObstacle) {
        lastHitKind = obstacle.kind
        phase = .over
        overAt = Date()
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        #endif
    }
}

// MARK: - 게임 화면

private struct YouthRunnerGameView: View {
    @State private var game = YouthRunnerGame()
    @AppStorage("easterEgg.churchYouth.bestScore") private var bestScore = 0
    @State private var isNewRecord = false

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { timeline in
                Canvas { context, canvasSize in
                    draw(&context, size: canvasSize, topInset: proxy.safeAreaInsets.top, now: timeline.date)
                }
                .onChange(of: timeline.date) { _, newDate in
                    game.step(now: newDate)
                }
            }
            .onChange(of: proxy.size, initial: true) { _, newSize in
                game.size = newSize
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { game.handleInput() }
        .onKeyPress(keys: [.space, .upArrow], phases: .down) { _ in
            game.handleInput()
            return .handled
        }
        .overlay { phaseOverlay.allowsHitTesting(false) }
        .onChange(of: game.phase) { _, newPhase in
            guard newPhase == .over else { return }
            if game.displayScore > bestScore {
                bestScore = game.displayScore
                isNewRecord = true
            } else {
                isNewRecord = false
            }
        }
        .accessibilityElement()
        .accessibilityLabel("점프 게임. 두 번 탭하면 점프합니다.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { game.handleInput() }
    }

    // MARK: 오버레이 문구

    @ViewBuilder
    private var phaseOverlay: some View {
        switch game.phase {
        case .ready:
            overlayCard(
                title: "고난 · 무시 · 눈물을 넘어 달려요",
                detail: "화면을 탭하면 점프합니다 (스페이스바, ↑키도 가능)\n땅이 끊긴 '사망의 음침한 골짜기'도 점프로 건너요",
                footer: "탭해서 시작"
            )
        case .over:
            overlayCard(
                title: game.lastHitKind?.fallTitle ?? "넘어져도 괜찮아요",
                detail: (game.lastHitKind.map { $0.comfort + "\n" } ?? "")
                    + (isNewRecord
                        ? "새 기록이에요! 점수 \(game.displayScore)"
                        : "점수 \(game.displayScore) · 최고 \(bestScore)"),
                footer: "탭해서 다시 달리기"
            )
        case .playing:
            EmptyView()
        }
    }

    private func overlayCard(title: String, detail: String, footer: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
            Text(footer)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(EasterEggPalette.gold)
                .padding(.top, 6)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 24)
    }

    // MARK: 그리기

    /// 땅이 끊긴 골짜기: 땅 위에 어두운 사다리꼴(아래로 좁아짐)을 덮고, 위쪽에 옅은 안개를 흘린다.
    private func drawValley(_ context: inout GraphicsContext, obstacle: RunnerObstacle,
                            groundY: CGFloat, bottom: CGFloat, scroll: CGFloat) {
        let left = obstacle.x
        let right = obstacle.x + obstacle.width
        let inset = min(14, obstacle.width * 0.2)
        let depth = bottom - groundY

        // 땅 윗선(3pt)까지 덮어 끊긴 것처럼 보이게 한다.
        var pit = Path()
        pit.move(to: CGPoint(x: left, y: groundY))
        pit.addLine(to: CGPoint(x: right, y: groundY))
        pit.addLine(to: CGPoint(x: right - inset, y: bottom))
        pit.addLine(to: CGPoint(x: left + inset, y: bottom))
        pit.closeSubpath()
        context.fill(
            pit,
            with: .linearGradient(
                Gradient(colors: [EasterEggPalette.valleyTop, EasterEggPalette.valleyDeep]),
                startPoint: CGPoint(x: 0, y: groundY),
                endPoint: CGPoint(x: 0, y: groundY + depth * 0.7)
            )
        )
        // 절벽 가장자리 빛
        var rim = Path()
        rim.move(to: CGPoint(x: left, y: groundY))
        rim.addLine(to: CGPoint(x: left + inset, y: bottom))
        rim.move(to: CGPoint(x: right, y: groundY))
        rim.addLine(to: CGPoint(x: right - inset, y: bottom))
        context.stroke(rim, with: .color(EasterEggPalette.groundTop.opacity(0.55)), lineWidth: 1.5)

        // 아래에서 올라오는 옅은 안개 두 줄 — 위치는 스크롤 값으로 천천히 흔들린다.
        for index in 0..<2 {
            let sway = sin((scroll + CGFloat(index) * 70) / 40) * obstacle.width * 0.12
            let mistWidth = obstacle.width * (0.55 - 0.12 * CGFloat(index))
            let rect = CGRect(
                x: left + (obstacle.width - mistWidth) / 2 + sway,
                y: groundY + 8 + CGFloat(index) * 12,
                width: mistWidth, height: 6
            )
            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.10)))
        }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, topInset: CGFloat, now: Date) {
        let width = size.width
        let height = size.height
        let groundY = height * 0.74
        let scroll = game.scroll

        // 달 + 은은한 빛무리
        let moonCenter = CGPoint(x: width * 0.80, y: height * 0.20)
        context.fill(
            Path(ellipseIn: CGRect(x: moonCenter.x - 46, y: moonCenter.y - 46, width: 92, height: 92)),
            with: .color(.white.opacity(0.10))
        )
        context.fill(
            Path(ellipseIn: CGRect(x: moonCenter.x - 26, y: moonCenter.y - 26, width: 52, height: 52)),
            with: .color(Color(red: 1.0, green: 0.95, blue: 0.82).opacity(0.95))
        )

        // 먼 언덕(느리게)
        var hills = Path()
        hills.move(to: CGPoint(x: 0, y: groundY))
        var hillX: CGFloat = 0
        while hillX <= width + 8 {
            let wave = sin((hillX + scroll * 0.15) / 90) * 22 + sin((hillX + scroll * 0.15) / 37) * 6
            hills.addLine(to: CGPoint(x: hillX, y: groundY - 46 + wave))
            hillX += 8
        }
        hills.addLine(to: CGPoint(x: width, y: groundY))
        hills.closeSubpath()
        context.fill(hills, with: .color(Color(red: 0.14, green: 0.15, blue: 0.30).opacity(0.85)))

        // 구름(조금 빠르게). 화면 폭을 한 바퀴 돌며 다시 나타난다.
        let cloudSpan = width + 240
        for index in 0..<4 {
            let base = CGFloat(index) * (cloudSpan / 4)
            let x = (base - scroll * 0.3).truncatingRemainder(dividingBy: cloudSpan)
            let cloudX = x < -120 ? x + cloudSpan : x
            let cloudY = height * (0.12 + 0.07 * CGFloat(index % 3))
            let cloudRect = CGRect(x: cloudX, y: cloudY, width: 90, height: 20)
            context.fill(Path(roundedRect: cloudRect, cornerRadius: 10), with: .color(.white.opacity(0.14)))
            context.fill(
                Path(roundedRect: cloudRect.insetBy(dx: 16, dy: -8).offsetBy(dx: 6, dy: -4), cornerRadius: 12),
                with: .color(.white.opacity(0.10))
            )
        }

        // 땅
        context.fill(
            Path(CGRect(x: 0, y: groundY, width: width, height: height - groundY)),
            with: .color(EasterEggPalette.ground)
        )
        context.fill(
            Path(CGRect(x: 0, y: groundY, width: width, height: 3)),
            with: .color(EasterEggPalette.groundTop)
        )
        // 땅 무늬(달리는 느낌)
        let tickSpacing: CGFloat = 46
        var tickX = -(scroll.truncatingRemainder(dividingBy: tickSpacing))
        while tickX < width {
            context.fill(
                Path(roundedRect: CGRect(x: tickX, y: groundY + 14, width: 18, height: 3), cornerRadius: 1.5),
                with: .color(EasterEggPalette.groundTop.opacity(0.7))
            )
            tickX += tickSpacing
        }

        // 장애물
        for obstacle in game.obstacles {
            switch obstacle.kind {
            case .rock:
                let rect = CGRect(x: obstacle.x, y: groundY - obstacle.height, width: obstacle.width, height: obstacle.height)
                context.fill(Path(roundedRect: rect, cornerRadius: min(obstacle.width, obstacle.height) * 0.35),
                             with: .color(EasterEggPalette.rock))
                context.fill(
                    Path(roundedRect: CGRect(x: rect.minX + 5, y: rect.minY + 5, width: obstacle.width * 0.35, height: 5), cornerRadius: 2.5),
                    with: .color(.white.opacity(0.35))
                )
            case .thorn:
                let count = max(2, Int(obstacle.width / 13))
                let step = obstacle.width / CGFloat(count)
                var thorns = Path()
                for index in 0..<count {
                    let left = obstacle.x + CGFloat(index) * step
                    thorns.move(to: CGPoint(x: left, y: groundY))
                    thorns.addLine(to: CGPoint(x: left + step / 2, y: groundY - obstacle.height))
                    thorns.addLine(to: CGPoint(x: left + step, y: groundY))
                    thorns.closeSubpath()
                }
                context.fill(thorns, with: .color(EasterEggPalette.thorn))
            case .valley:
                drawValley(&context, obstacle: obstacle, groundY: groundY, bottom: height, scroll: scroll)
            case .tear:
                // 눈물방울 — 위가 뾰족하고 아래가 둥근 모양.
                let radius = obstacle.width / 2
                let centerX = obstacle.x + radius
                let circleCenterY = groundY - radius
                var drop = Path()
                drop.move(to: CGPoint(x: centerX, y: groundY - obstacle.height))
                drop.addLine(to: CGPoint(x: centerX + radius * 0.92, y: circleCenterY - radius * 0.35))
                drop.addArc(
                    center: CGPoint(x: centerX, y: circleCenterY), radius: radius,
                    startAngle: .degrees(-20), endAngle: .degrees(200), clockwise: false
                )
                drop.closeSubpath()
                context.fill(drop, with: .color(EasterEggPalette.tear))
                context.fill(
                    Path(ellipseIn: CGRect(x: centerX - radius * 0.55, y: circleCenterY - radius * 0.2, width: radius * 0.4, height: radius * 0.55)),
                    with: .color(.white.opacity(0.55))
                )
            }
            // 걸림돌 이름표(골짜기는 높이가 없고 이름이 길어 땅 위 12pt에 둔다)
            context.draw(
                Text(obstacle.kind.label)
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(.white.opacity(obstacle.kind == .valley ? 0.7 : 0.85)),
                at: CGPoint(x: obstacle.x + obstacle.width / 2,
                            y: groundY - (obstacle.kind == .valley ? 12 : obstacle.height + 6)),
                anchor: .bottom
            )
        }

        // 달리는 사람 + 그림자
        let playerX = width * YouthRunnerGame.playerXRatio
        let playerSize = YouthRunnerGame.playerSize
        let lift = game.playerLift
        let shadowScale = max(0.4, 1 - lift / 220)
        let fall = game.fallDepth
        if fall == 0 {
            context.fill(
                Path(ellipseIn: CGRect(x: playerX + playerSize / 2 - 16 * shadowScale, y: groundY - 3, width: 32 * shadowScale, height: 6)),
                with: .color(.black.opacity(0.3))
            )
        }
        let bob: CGFloat = (game.phase == .playing && lift == 0) ? sin(game.distance / 14) * 2 : 0
        var runner = context.resolve(Image(systemName: "figure.run").renderingMode(.template))
        runner.shading = .color(EasterEggPalette.gold)
        // 골짜기에 빠지는 동안은 아래로 내려가며 어둠 속으로 사라진다.
        context.opacity = max(0, 1 - fall / YouthRunnerGame.fallFadeDepth)
        context.draw(
            runner,
            in: CGRect(x: playerX, y: groundY - lift - playerSize + bob + fall, width: playerSize, height: playerSize)
        )
        context.opacity = 1

        // 점수/최고 점수/응원 문구
        let hudTop = topInset + 18
        context.draw(
            Text("점수 \(game.displayScore)")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(.white),
            at: CGPoint(x: 20, y: hudTop), anchor: .topLeading
        )
        context.draw(
            Text("최고 \(max(bestScore, game.displayScore))")
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.7)),
            at: CGPoint(x: 20, y: hudTop + 28), anchor: .topLeading
        )
        if let message = game.milestoneText, now < game.milestoneExpires {
            context.draw(
                Text(message)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(EasterEggPalette.gold),
                at: CGPoint(x: width / 2, y: height * 0.30), anchor: .center
            )
        }
    }
}
