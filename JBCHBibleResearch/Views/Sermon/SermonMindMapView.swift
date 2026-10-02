//
//  SermonMindMapView.swift
//  JBCHBibleResearch
//
//  설교별 마인드맵 편집 화면. 노드는 트리 구조(`MindMapNode`,
//  BibleResearchModels/Models/MindMaps.swift)이며 위치는 사용자가 직접 정해 영속화한다.
//  아키텍처는 자유형 그래프 화면 `Views/TagRelations/TagRelationsView.swift`를 따른다:
//  Canvas로 선을 그리고, ForEach로 배치한 노드에 이름 붙은 좌표계 안에서 DragGesture를 붙인다.
//  (TagRelationsView는 물리 시뮬레이션으로 위치를 자동 계산하지만 이 화면은 그렇지 않다.)
//

import SwiftUI
import SwiftData
import BibleResearchModels
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// 마인드맵 창(`WindowGroup(id: "sermon-mindmap", for: SermonMindMapTarget.self)`)의 콘텐츠.
/// `@Query`로 대상 설교를 찾아, 창이 떠 있는 동안 설교가 삭제돼도 죽은 참조 없이 "찾을 수 없음"을 보여준다.
struct SermonMindMapWindowContent: View {
    @Query private var sermons: [Sermon]
    let target: SermonMindMapTarget?
    /// 진짜 `WindowGroup` 창에서는 `@Environment(\.dismiss)`가 효과가 없어 `dismissWindow()`로 창을 닫는다.
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        if let target, let sermon = sermons.first(where: { $0.persistentModelID == target.sermonID }) {
            NavigationStack {
                SermonMindMapView(sermon: sermon, onRequestClose: { dismissWindow() })
            }
        } else {
            sermonNotFoundMessage
        }
    }

    private var sermonNotFoundMessage: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("설교를 찾을 수 없습니다")
                .font(.title3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 마인드맵 편집 화면. 아이폰은 `SermonDetailView.mapButton`의 `NavigationLink`로 기존 `NavigationStack`에 push하고
/// (중첩 스택 방지를 위해 자체 `NavigationStack`을 두지 않는다), 아이패드·맥은 `SermonMindMapWindowContent`가 별도 창으로 연다.
struct SermonMindMapView: View {
    @Bindable var sermon: Sermon
    /// 창(`WindowGroup`) 컨텍스트에서 창을 닫는 클로저. nil이면(아이폰 push) `dismiss()`로 이전 화면으로 돌아간다.
    var onRequestClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment

    /// 캔버스 좌표계 이름 — `TagRelationsView`의 "graph"와 같은 역할.
    private static let canvasSpace = "mindmap-canvas"
    /// 캔버스 고정 크기 — 뷰포트보다 크게 잡아 `ScrollView`로 패닝한다(노드 300개 이하 예상).
    private static let canvasSize = CGSize(width: 2600, height: 1900)
    private static let defaultNodeWidth: Double = 160
    private static let defaultNodeHeight: Double = 60
    /// 확대/축소 배율 한계와 단계.
    private static let minZoom: CGFloat = 0.4
    private static let maxZoom: CGFloat = 2.5
    private static let zoomStep: CGFloat = 0.15
    /// 사이드 패널 폭. macOS 세그먼트 Picker 등은 제안 폭보다 좁아지지 못하므로,
    /// `sidePanel`에서 콘텐츠 폭을 이 값에서 좌우 패딩을 뺀 값으로 고정해 자식이 레이아웃 폭을 흔들지 못하게 한다.
    private static let sidePanelWidth: CGFloat = 320

    /// 선택된 노드 집합. 단일 선택은 원소 1개인 경우로 다룬다(`selectedNode`/`selectedNodes`, `selectSingle(_:)` 참고).
    @State private var selectedNodeIDs: Set<PersistentIdentifier> = []
    @State private var editingNodeID: PersistentIdentifier?
    /// 하단 설명 영역을 편집 중인 노드. `editingNodeID`(제목 편집)와 동시에 하나만 켜진다.
    @State private var editingDescriptionNodeID: PersistentIdentifier?
    /// 캔버스 빈 곳 드래그로 그리는 러버밴드 선택 사각형 — 드래그 중에만 값이 있다.
    /// 배율이 반영된 캔버스 좌표(`Self.canvasSpace`) 기준이라 노드 프레임과 바로 비교할 수 있다.
    @State private var selectionRect: CGRect?
    /// 여러 노드를 함께 드래그할 때 제스처 시작 시점의 각 노드 위치(모델 좌표, 배율 무관).
    /// `DragGesture.Value.translation`이 시작점 기준 누적값이므로 이 위치에 더해 절대 위치를 구한다. 드래그가 끝나면 비운다.
    @State private var multiDragStartPositions: [PersistentIdentifier: (x: Double, y: Double)] = [:]
    // 확대/축소 배율. `MindMapNode`의 위치·크기는 항상 배율 1.0 기준 모델 좌표로 저장하고 그릴 때만 배율을 곱한다.
    // 드래그·리사이즈 제스처가 보고하는 화면 좌표는 배율로 나눠 모델 좌표로 되돌린다(`MindMapNodeShapeView` 참고).
    // `.scaleEffect()`는 이름 붙은 좌표계·제스처 위치 보고와의 상호작용을 검증할 수 없어 쓰지 않고, 좌표·크기 계산에 배율을 직접 곱/나눈다.
    @State private var zoomScale: CGFloat = 1.0
    /// 핀치 시작 시점의 배율·스크롤 원점·손가락(커서) 위치.
    /// `scrollVisibleRect`는 갱신이 한 박자 늦을 수 있어, 시작 시점 값을 기준으로 매번 계산해 확대 중 화면이 밀리지 않게 한다.
    @State private var pinchStart: (scale: CGFloat, origin: CGPoint, anchor: CGPoint)?
    /// 캔버스 `ScrollView`의 현재 가시 영역(배율이 적용된 콘텐츠 좌표계). `onScrollGeometryChange`로 갱신하며
    /// 미니맵의 뷰포트 사각형과 뷰포트 저장에 쓴다.
    @State private var scrollVisibleRect: CGRect = .zero
    /// 프로그램적 스크롤 이동(뷰포트 복원·루트 중앙 정렬) 전용. 사용자가 직접 스크롤하면 값이 `nil`로 리셋되므로,
    /// 현재 위치 읽기(저장용)는 이 값이 아니라 `scrollVisibleRect`로 한다.
    @State private var scrollPosition = ScrollPosition(edge: .top)
    /// 저장된 뷰포트 복원을 한 번만 시도하기 위한 플래그(매번 복원하면 사용자의 스크롤을 덮어쓴다).
    @State private var hasRestoredViewport = false
    /// 방금 만든 루트 노드를 화면 가운데로 옮겨야 한다는 표시. `addRootNode()` 시점엔 `canvasArea`가 없을 수 있어,
    /// 실제 이동은 `canvasArea`가 나타난 뒤 `.task`에서 수행한다.
    @State private var pendingCenterNodeID: PersistentIdentifier?
    /// "설교문 적용" 확인/결과 창 상태 — `requestExport()` 참고.
    @State private var exportPlan: SermonMindMapExporter.Plan?
    @State private var showExportConfirm = false
    @State private var exportResultMessage: String?
    /// 결과 알림 표시 여부. `Binding(get:set:)`을 `body`에 인라인으로 두면 `.alert` 겹침으로 타입 추론이 과도하게 느려져 단순 Bool 상태로 둔다.
    @State private var showExportResult = false
    /// 경로 선을 드래그하는 동안의 상태 — 어느 노드의 선(부모→그 노드)인지, 잡은 자리와 현재 포인터 위치(배율 반영 캔버스 좌표).
    /// `nil`이면 선 드래그 중이 아니다.
    @State private var edgeDrag: EdgeDragState?
    /// 현재 캔버스 드래그의 시작 위치 — 드래그가 "선 잡기"인지 "러버밴드 선택"인지를 시작 순간 한 번 정하기 위해 기억한다.
    @State private var canvasDragStart: CGPoint?
    /// 맥OS: 빈 캔버스를 그냥 끌면 화면 이동(⇧을 누르고 끌면 선택 사각형). 현재 드래그가 화면 이동이면 true.
    /// 아이패드/아이폰은 항상 false — 거기서는 한 손가락이 선택, 두 손가락이 화면 이동(`ScrollViewTwoFingerPan`).
    @State private var isCanvasPanning = false
    /// 화면 이동 드래그를 시작한 순간의 스크롤 위치(콘텐츠 좌표). 드래그가 끝나면 nil.
    @State private var panStartOrigin: CGPoint?
    /// 노드 위·아래 중앙 버튼을 끄는 동안의 상태(어느 노드의 어느 버튼, 현재 포인터 위치 — 캔버스 좌표). `nil`이면 드래그 중이 아니다.
    @State private var linkDrag: LinkDragState?
    /// 우클릭 "스타일 복사"로 담아 둔 스타일 — 같은 창 안에서만 유지된다.
    @State private var copiedStyle: MindMapStyleTemplate?

    private struct LinkDragState {
        let sourceID: PersistentIdentifier
        let handle: MindMapLinkHandle
        var location: CGPoint
    }
    /// 실행취소/다시 실행(Cmd+Z / Shift+Cmd+Z). 창의 `UndoManager`에 변경 내역을 등록한다(`MindMapUndoCoordinator` 참고).
    @Environment(\.undoManager) private var undoManager
    @State private var undoCoordinator = MindMapUndoCoordinator()
    /// Delete 키로 선택 노드를 지우려면 캔버스가 키보드 포커스를 가져야 한다(`canvasArea`의 `.focusable`/`.onKeyPress` 참고).
    @FocusState private var canvasFocused: Bool

    private struct EdgeDragState {
        let childID: PersistentIdentifier
        let startLocation: CGPoint
        var location: CGPoint
    }

    /// 선을 놓았을 때의 결과 — 미리보기(색·강조)와 실제 적용이 같은 판정을 쓴다.
    private enum EdgeDragOutcome {
        case cancel                 // 아무 일도 없음(원위치)
        case attach(MindMapNode)    // 놓은 노드가 선 위쪽 노드의 새 자식(기존 자식은 끊김)
        case blocked                // 놓은 노드에는 연결할 수 없음(규칙 위반) — 아무 일도 없음
        case disconnect             // 연결 해제(선 삭제)
    }

    /// 선 위를 잡았다고 인정하는 거리(화면 pt).
    private static let edgeHitTolerance: CGFloat = 8
    /// 빈 곳에 놓아 연결을 끊으려면 잡은 자리에서 최소한 이만큼(화면 pt) 끌어야
    /// 한다 — 살짝 스친 드래그로 실수로 끊기는 것을 막는 안전장치.
    private static let edgeDragMinDisconnectDistance: CGFloat = 30

    private var settings: UserSettingsStore { .shared }

    private var accent: Color {
        SermonTheme.accent(background: settings.bibleBackgroundColor, environment: environment, fallbackScheme: colorScheme)
    }

    /// `SermonTheme.accent(background:environment:fallbackScheme:)`와 같은 WCAG 상대휘도 공식 — 12색 도형 팔레트의 라이트/다크 변형 선택 기준.
    /// 프로젝트가 여러 파일에 같은 공식을 각자 두는 관례를 따른다.
    private var isDarkSurface: Bool {
        if let background = settings.bibleBackgroundColor {
            let resolved = background.resolve(in: environment)
            let luminance = 0.2126 * Double(resolved.red) + 0.7152 * Double(resolved.green) + 0.0722 * Double(resolved.blue)
            return luminance < 0.5
        }
        return colorScheme == .dark
    }

    private var nodes: [MindMapNode] {
        sermon.mindMapNodes ?? []
    }

    /// 정확히 하나만 선택돼 있을 때만 값을 주며, 여러 개면 `nil`이라 사이드 패널이 `bulkActionsSection`을 보여준다(`sidePanel` 참고).
    private var selectedNode: MindMapNode? {
        guard selectedNodeIDs.count == 1, let id = selectedNodeIDs.first else { return nil }
        return nodes.first { $0.persistentModelID == id }
    }

    /// 현재 선택된 노드 전체(1개든 여러 개든) — 일괄 삭제·일괄 스타일 적용에 쓴다.
    private var selectedNodes: [MindMapNode] {
        nodes.filter { selectedNodeIDs.contains($0.persistentModelID) }
    }

    /// 탭으로 노드 하나만 선택한다. 이미 다중 선택(2개 이상)에 포함된 노드면 선택을 유지한다
    /// (그 노드를 잡고 함께 드래그해도 선택이 깨지지 않게 — `beginBulkDrag(anchor:)` 참고).
    private func selectSingle(_ node: MindMapNode) {
        if selectedNodeIDs.count > 1, selectedNodeIDs.contains(node.persistentModelID) {
            return
        }
        selectedNodeIDs = [node.persistentModelID]
    }

    var body: some View {
        trackedContent
            .navigationTitle(navigationTitleText)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .background(settings.bibleBackgroundColor ?? Color.clear)
    }

    /// 내비게이션 제목. `body`를 `mainContent`/`exportAlertsHost`/`navigationTitleText`로 나눠 수식을 짧게 유지한다(타입 추론 시간 초과 방지).
    private var navigationTitleText: String {
        let name = sermon.title.isEmpty ? "제목 없음" : sermon.title
        return "\(name) — 마인드맵"
    }

    @ViewBuilder
    private var mainContent: some View {
        if nodes.isEmpty {
            emptyState
        } else {
            HStack(spacing: 0) {
                canvasArea
                    .focusable()
                    .focused($canvasFocused)
                    .focusEffectDisabled()
                    .onKeyPress(keys: [.delete, .deleteForward]) { _ in
                        handleDeleteKey()
                    }
                Divider()
                sidePanel
                    .frame(width: Self.sidePanelWidth)
            }
        }
    }

    /// 화면 본체 + 알림 + 변경 추적(실행취소/최근 스타일 기록)/포커스. `body`의 수식
    /// 길이를 줄이려고 층을 나눴다.
    private var trackedContent: some View {
        exportAlertsHost
            .onChange(of: currentSnapshot) { old, new in
                handleSnapshotChange(old: old, new: new)
            }
            .onChange(of: selectedNodeIDs) { _, _ in
                focusCanvasIfIdle()
            }
            // 글자 편집이 끝나면 Delete 키가 다시 캔버스로 오도록 포커스를 되돌린다.
            .onChange(of: editingNodeID) { _, _ in
                focusCanvasIfIdle()
            }
            .onChange(of: editingDescriptionNodeID) { _, _ in
                focusCanvasIfIdle()
            }
            .task {
                await startUndoTracking()
            }
    }

    /// 지금 모든 노드의 값(실행취소가 되돌릴 대상) — 노드가 바뀔 때마다 `onChange`가
    /// 이전/이후를 비교한다.
    private var currentSnapshot: MindMapSnapshot {
        MindMapSnapshot(nodes: nodes)
    }

    private func connectUndoCoordinator() {
        undoCoordinator.undoManager = undoManager
        undoCoordinator.modelContext = modelContext
        undoCoordinator.sermon = sermon
    }

    private func handleSnapshotChange(old: MindMapSnapshot, new: MindMapSnapshot) {
        connectUndoCoordinator()
        let wasRestore = undoCoordinator.snapshotDidChange(old: old, new: new)
        if wasRestore {
            // 되돌리기로 노드가 지워졌다 다시 만들어지면 식별자가 바뀌므로, 없어진 노드의
            // 선택/편집 상태는 정리한다.
            let existing = Set(nodes.map(\.persistentModelID))
            selectedNodeIDs = selectedNodeIDs.filter { existing.contains($0) }
            editingNodeID = nil
            editingDescriptionNodeID = nil
        }
    }

    /// 화면이 뜬 직후: (1) 섞여 있던 경로 종류를 하나로 맞추고, (2) 조금 기다린 뒤
    /// 실행취소 기록을 시작한다 — 처음 데이터가 채워지는 변화나 (1)의 정리가 "실행
    /// 취소할 편집"으로 기록되지 않게 하기 위함.
    private func startUndoTracking() async {
        connectUndoCoordinator()
        setAllPathTypes(currentPathType)
        canvasFocused = true
        try? await Task.sleep(nanoseconds: 800_000_000)
        undoCoordinator.arm()
    }

    private func focusCanvasIfIdle() {
        if editingNodeID == nil && editingDescriptionNodeID == nil {
            canvasFocused = true
        }
    }

    /// Delete(⌫)/Forward Delete 키 — 선택한 노드와 그 노드에 연결된 선을 지운다(삭제
    /// 규칙은 우클릭 "노드 삭제"와 같다: 하위 노드는 남고 연결선만 사라지며, 주
    /// 루트는 지워지지 않는다). 글자를 편집 중이면 키를 텍스트 필드에 맡긴다.
    private func handleDeleteKey() -> KeyPress.Result {
        guard editingNodeID == nil, editingDescriptionNodeID == nil, !selectedNodeIDs.isEmpty else {
            return .ignored
        }
        deleteSelectedNodes()
        return .handled
    }

    /// 설교문 적용의 확인/결과 알림 두 개. 확인 알림의 본문은 `exportPlan`이
    /// 있을 때만 계산한다(`presenting:` 오버로드 대신 단순 `isPresented`).
    private var exportAlertsHost: some View {
        mainContent
            .alert("설교문에 적용", isPresented: $showExportConfirm) {
                Button("추가") { confirmExport() }
                Button("취소", role: .cancel) {}
            } message: {
                Text(exportConfirmText)
            }
            .alert("설교문 적용", isPresented: $showExportResult) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(exportResultMessage ?? "")
            }
    }

    // MARK: - 빈 상태(첫 진입, 노드 없음)

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("아직 마인드맵이 없습니다")
                .font(.title3)
            Text("루트 노드(메인주제)를 추가하면 시작할 수 있습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("루트 노드 추가") { addRootNode() }
                .buttonStyle(SermonPillButtonStyle(isFilled: true, tint: accent))
                .frame(maxWidth: 220)
            // 루트 노드를 만들지 않고 그냥 나간다 — 아무 데이터도 저장하지 않는다.
            Button("닫기") { closeWithoutCreating() }
                .buttonStyle(SermonPillButtonStyle(isFilled: false, tint: accent))
                .frame(maxWidth: 220)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(settings.bibleBackgroundColor ?? Color.clear)
    }

    /// 빈 상태에서 "닫기" — 노드를 만들지 않으므로 저장할 것이 없다. 창이면 창을, 아이폰 push면 이전 화면으로.
    private func closeWithoutCreating() {
        if let onRequestClose {
            onRequestClose()
        } else {
            dismiss()
        }
    }

    // MARK: - 캔버스

    private var canvasArea: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                // 배경 격자를 그리는 `Canvas` — 콘텐츠 크기를 잡는 역할도 겸한다.
                // 격자 간격은 "모델 좌표 고정값 × 배율"이라 확대/축소해도 노드와 같은 비율로 변한다.
                Canvas { context, size in
                    drawGrid(context: context, size: size)
                }
                .frame(width: Self.canvasSize.width * zoomScale, height: Self.canvasSize.height * zoomScale)
                .allowsHitTesting(false)

                Canvas { context, _ in
                    drawEdges(context: context)
                }
                .frame(width: Self.canvasSize.width * zoomScale, height: Self.canvasSize.height * zoomScale)
                // Canvas 레이어가 아래 노드 뷰들 위/사이의 탭 제스처를 가로채지 않도록 히트테스트에서 뺀다.
                .allowsHitTesting(false)

                ForEach(nodes, id: \.persistentModelID) { node in
                    nodeView(node)
                        .position(x: CGFloat(node.positionX) * zoomScale, y: CGFloat(node.positionY) * zoomScale)
                }

                // 러버밴드 선택 사각형 — 드래그 중에만 보인다.
                if let selectionRect {
                    Rectangle()
                        .fill(accent.opacity(0.12))
                        .overlay(Rectangle().stroke(accent, lineWidth: 1))
                        .frame(width: selectionRect.width, height: selectionRect.height)
                        .position(x: selectionRect.midX, y: selectionRect.midY)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: Self.canvasSpace)
            .contentShape(Rectangle())
            // 아이패드/아이폰: 스크롤을 두 손가락 드래그로 바꿔 한 손가락 드래그(선택/노드 이동)와 겹치지 않게 한다.
            #if os(iOS)
            .background(ScrollViewTwoFingerPan())
            #endif
            .onTapGesture {
                selectedNodeIDs.removeAll()
                editingNodeID = nil
                editingDescriptionNodeID = nil
            }
            // 빈 캔버스 드래그로 사각형을 그려 프레임이 겹치는 노드를 전부 선택한다. 노드 위에서 시작한 드래그는
            // 노드 자신의 제스처(`MindMapNodeShapeView`의 `.gesture`)가 먼저 받는다(ZStack에서 나중에 그려진 뷰가 히트테스트 우선).
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.canvasSpace))
                    .onChanged { value in handleCanvasDragChanged(value) }
                    .onEnded { value in handleCanvasDragEnded(value) }
            )
        }
        // 미니맵 뷰포트 사각형용 가시 영역. `ScrollView` 자신에 붙여야 배율이 반영된 콘텐츠 좌표계의 `visibleRect`를 받는다.
        .onScrollGeometryChange(for: CGRect.self) { geometry in
            geometry.visibleRect
        } action: { _, newValue in
            scrollVisibleRect = newValue
        }
        // 뷰포트 읽기는 `scrollVisibleRect`, 복원(쓰기)은 `scrollPosition`으로 한다.
        .scrollPosition($scrollPosition)
        // 맥OS: 빈 캔버스 드래그로 화면 이동. 이동량은 스크롤과 함께 움직이지 않는 `ScrollView` 자신의 좌표계에서 재야
        // (콘텐츠 좌표로 재면 스크롤할수록 이동량이 줄어드는 되먹임이 생긴다) 되먹임 없이 따라간다.
        // 어떤 드래그가 화면 이동인지는 캔버스 제스처(`handleCanvasDragChanged`)가 시작 순간에 정해 `isCanvasPanning`에 둔다.
        #if os(macOS)
        .simultaneousGesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .local)
                .onChanged { value in handleCanvasPanChanged(translation: value.translation) }
                .onEnded { _ in panStartOrigin = nil }
        )
        #endif
        // 핀치 줌 — 돋보기 버튼과 같은 `zoomScale`을 바꾸므로 배율 표시·미니맵·저장 뷰포트가 함께 갱신된다.
        // `simultaneousGesture`라 노드 드래그·러버밴드·스크롤 제스처와 서로 막지 않는다.
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in handlePinch(value) }
                .onEnded { _ in pinchStart = nil }
        )
        // `ScrollView`의 첫 레이아웃 전에 `scrollPosition.scrollTo`를 호출하면 반영되지 않을 수 있어
        // 짧게 기다린 뒤 복원/중앙 정렬한다(지연 시간은 필요 시 조정).
        .task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            restoreViewportIfNeeded()
            centerOnPendingNodeIfNeeded()
        }
        .onDisappear {
            saveViewport()
        }
        .background(canvasBackgroundColor)
        .overlay(alignment: .bottomLeading) { zoomControls }
        .overlay(alignment: .bottomTrailing) { minimapView }
    }

    /// 격자 한 칸의 모델 좌표 크기(배율 1.0 기준 pt). 화면상 간격이 6pt 미만이 되면(`drawGrid`) 너무 촘촘해 격자를 그리지 않는다.
    private static let gridCellSize: CGFloat = 20

    /// 캔버스 배경색. 밝은 화면에서는 흰색을 78% 덮어 거의 흰색으로 하되 앱 배경색 기운을 살짝 남긴다.
    /// 어두운 화면에서는 흰 캔버스가 눈부시고 노드 글자색 대비가 깨지므로 옅은 회색만 덮는다.
    private var canvasBackgroundColor: Color {
        isDarkSurface ? Color.secondary.opacity(0.04) : Color.white.opacity(0.78)
    }

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        let spacing = Self.gridCellSize * zoomScale
        guard spacing >= 6 else { return }
        let lineColor = Color.secondary.opacity(0.12)
        var path = Path()
        var x: CGFloat = 0
        while x <= size.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            x += spacing
        }
        var y: CGFloat = 0
        while y <= size.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }
        context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
    }

    /// 노드 하나의 화면(캔버스 콘텐츠 좌표, 배율 반영) 프레임 — 러버밴드
    /// 선택의 교차 판정, 그 밖에 노드 사각형이 필요한 곳에서 공용으로 쓴다.
    private func nodeFrame(_ node: MindMapNode) -> CGRect {
        CGRect(
            x: CGFloat(node.positionX) * zoomScale - CGFloat(node.width) * zoomScale / 2,
            y: CGFloat(node.positionY) * zoomScale - CGFloat(node.height) * zoomScale / 2,
            width: CGFloat(node.width) * zoomScale,
            height: CGFloat(node.height) * zoomScale
        )
    }

    /// 저장된 뷰포트(스크롤 위치·배율) 복원. `Sermon.mindMapViewportX/Y/Zoom`이 모두 있을 때만 복원하고,
    /// 없으면(과거 설교·처음 여는 맵) 기본 위치(왼쪽 위, 배율 100%)로 시작한다. `hasRestoredViewport`로 한 번만 시도한다.
    private func restoreViewportIfNeeded() {
        guard !hasRestoredViewport else { return }
        hasRestoredViewport = true
        guard let x = sermon.mindMapViewportX,
              let y = sermon.mindMapViewportY,
              let zoom = sermon.mindMapZoom else { return }
        zoomScale = CGFloat(zoom)
        scrollPosition.scrollTo(point: CGPoint(x: x, y: y))
    }

    /// 현재 스크롤 위치·배율을 설교에 저장 — `canvasArea.onDisappear`에서 호출한다.
    /// 계속 갱신되는 실제 가시 영역 `scrollVisibleRect`를 기준으로 한다(`scrollPosition` 선언부 주석 참고).
    private func saveViewport() {
        guard scrollVisibleRect != .zero else { return }
        sermon.mindMapViewportX = Double(scrollVisibleRect.origin.x)
        sermon.mindMapViewportY = Double(scrollVisibleRect.origin.y)
        sermon.mindMapZoom = Double(zoomScale)
    }

    /// `pendingCenterNodeID`가 있으면(방금 루트 노드를 만든 직후) 그 노드를
    /// 화면 가운데로 이동시키고 표시를 지운다 — `addRootNode()`/`canvasArea`
    /// 의 `.task` 참고.
    private func centerOnPendingNodeIfNeeded() {
        guard let id = pendingCenterNodeID else { return }
        pendingCenterNodeID = nil
        guard let node = nodes.first(where: { $0.persistentModelID == id }) else { return }
        centerViewport(on: node)
    }

    /// 특정 노드가 뷰포트 한가운데 오도록 스크롤 위치를 계산해 이동한다. `scrollVisibleRect`가 아직
    /// 갱신 전(`.zero`)이면 흔한 창 크기(700×500)를 기본값으로 대신 쓴다.
    private func centerViewport(on node: MindMapNode) {
        let targetX = CGFloat(node.positionX) * zoomScale
        let targetY = CGFloat(node.positionY) * zoomScale
        let viewportWidth = scrollVisibleRect.width > 0 ? scrollVisibleRect.width : 700
        let viewportHeight = scrollVisibleRect.height > 0 ? scrollVisibleRect.height : 500
        let offsetX = max(0, targetX - viewportWidth / 2)
        let offsetY = max(0, targetY - viewportHeight / 2)
        scrollPosition.scrollTo(point: CGPoint(x: offsetX, y: offsetY))
    }

    // MARK: - 확대/축소 컨트롤 + 미니맵

    /// 돋보기 버튼도 핀치와 같은 규칙(보던 화면 중앙이 유지되도록 스크롤 위치를 함께 보정)으로 배율을 바꾼다.
    /// 배율 한계(`minZoom`/`maxZoom`)는 `clampedZoom`(버튼·핀치 공용)에서만 적용한다.
    private func zoomIn() { setZoom(zoomScale + Self.zoomStep) }
    private func zoomOut() { setZoom(zoomScale - Self.zoomStep) }
    private func resetZoom() { setZoom(1.0) }

    private func clampedZoom(_ scale: CGFloat) -> CGFloat {
        min(Self.maxZoom, max(Self.minZoom, scale))
    }

    /// 버튼용 — 현재 보이는 영역의 중앙을 고정점으로 배율을 바꾼다.
    private func setZoom(_ newScale: CGFloat) {
        let target = clampedZoom(newScale)
        guard abs(target - zoomScale) > 0.0001 else { return }
        let viewportWidth = scrollVisibleRect.width > 0 ? scrollVisibleRect.width : 700
        let viewportHeight = scrollVisibleRect.height > 0 ? scrollVisibleRect.height : 500
        let anchor = CGPoint(x: viewportWidth / 2, y: viewportHeight / 2)
        // 고정점 아래의 모델 좌표(배율과 무관한 값)를 구해 두고, 새 배율에서
        // 같은 모델 좌표가 같은 화면 위치에 오도록 스크롤 원점을 계산한다.
        let modelX = (scrollVisibleRect.origin.x + anchor.x) / zoomScale
        let modelY = (scrollVisibleRect.origin.y + anchor.y) / zoomScale
        zoomScale = target
        scrollPosition.scrollTo(point: CGPoint(
            x: max(0, modelX * target - anchor.x),
            y: max(0, modelY * target - anchor.y)
        ))
    }

    /// 핀치용 — 손가락(커서) 아래 지점을 고정점으로 삼는다. `magnification`은
    /// 핀치 시작 시점 대비 누적 배율이라 시작 배율에 곱한다(프레임마다 현재
    /// 배율에 곱하면 누적 오차로 튄다 — 드래그 이동과 같은 원칙).
    private func handlePinch(_ value: MagnifyGesture.Value) {
        if pinchStart == nil {
            pinchStart = (zoomScale, scrollVisibleRect.origin, value.startLocation)
        }
        guard let start = pinchStart else { return }
        let target = clampedZoom(start.scale * value.magnification)
        let modelX = (start.origin.x + start.anchor.x) / start.scale
        let modelY = (start.origin.y + start.anchor.y) / start.scale
        zoomScale = target
        scrollPosition.scrollTo(point: CGPoint(
            x: max(0, modelX * target - start.anchor.x),
            y: max(0, modelY * target - start.anchor.y)
        ))
    }

    /// 확대/축소 버튼. `overlay`가 `ScrollView` 자신에 붙어 있어 스크롤해도 뷰포트(캔버스 왼쪽 아래)에 고정된다.
    private var zoomControls: some View {
        HStack(spacing: 10) {
            Button { zoomOut() } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .disabled(zoomScale <= Self.minZoom + 0.001)

            Text("\(Int((zoomScale * 100).rounded()))%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 34)

            Button { zoomIn() } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .disabled(zoomScale >= Self.maxZoom - 0.001)

            Divider().frame(height: 14)

            Button { resetZoom() } label: {
                Text("100%").font(.caption2.weight(.semibold))
            }
            .disabled(abs(zoomScale - 1.0) < 0.001)
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
        .padding(10)
    }

    /// 미니맵 자체의 화면 크기 — `minimapView`(그리기)와 `handleMinimapTap`
    /// (탭 → 좌표 역변환)이 같은 값을 써야 어긋나지 않아 공용 상수로 뺐다.
    private static let minimapSize = CGSize(width: 150, height: 110)

    /// 캔버스 전체(모든 노드)를 축소해 보여주는 미니맵. 노드는 `Self.canvasSize`(모델 좌표계) 기준 고정 비율로 그려
    /// 배율과 무관하게 제자리에 있고, 뷰포트 사각형(`scrollVisibleRect`)만 배율에 따라 커지고 작아진다.
    /// 탭 위치는 `SpatialTapGesture`로 얻어 `handleMinimapTap(at:)`으로 넘긴다.
    private var minimapView: some View {
        let mapSize = Self.minimapSize
        let scaleX = mapSize.width / Self.canvasSize.width
        let scaleY = mapSize.height / Self.canvasSize.height
        return Canvas { context, _ in
            for node in nodes {
                let rect = CGRect(
                    x: CGFloat(node.positionX) * scaleX - CGFloat(node.width) * scaleX / 2,
                    y: CGFloat(node.positionY) * scaleY - CGFloat(node.height) * scaleY / 2,
                    width: max(2, CGFloat(node.width) * scaleX),
                    height: max(2, CGFloat(node.height) * scaleY)
                )
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(resolvedColor(node.color)))
            }
            if scrollVisibleRect != .zero, zoomScale > 0 {
                let viewportModelRect = CGRect(
                    x: scrollVisibleRect.origin.x / zoomScale,
                    y: scrollVisibleRect.origin.y / zoomScale,
                    width: scrollVisibleRect.width / zoomScale,
                    height: scrollVisibleRect.height / zoomScale
                )
                let mapRect = CGRect(
                    x: viewportModelRect.origin.x * scaleX,
                    y: viewportModelRect.origin.y * scaleY,
                    width: viewportModelRect.width * scaleX,
                    height: viewportModelRect.height * scaleY
                )
                context.stroke(Path(mapRect), with: .color(accent), style: StrokeStyle(lineWidth: 1.5))
            }
        }
        .frame(width: mapSize.width, height: mapSize.height)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture()
                .onEnded { value in
                    handleMinimapTap(at: value.location)
                }
        )
        .padding(10)
    }

    /// 미니맵의 탭 위치(미니맵 자신의 로컬 좌표, 0~150×0~110)를 캔버스
    /// 모델 좌표로 역변환한 뒤, 그 지점이 뷰포트 가운데 오도록 실제 캔버스를
    /// 이동시킨다 — 위 `minimapView`의 그리기 변환(`scaleX`/`scaleY`)과
    /// 정확히 반대 방향 계산이다.
    private func handleMinimapTap(at location: CGPoint) {
        let mapSize = Self.minimapSize
        let scaleX = mapSize.width / Self.canvasSize.width
        let scaleY = mapSize.height / Self.canvasSize.height
        guard scaleX > 0, scaleY > 0 else { return }
        let modelX = location.x / scaleX
        let modelY = location.y / scaleY
        let targetContentX = modelX * zoomScale
        let targetContentY = modelY * zoomScale
        let viewportWidth = scrollVisibleRect.width > 0 ? scrollVisibleRect.width : 700
        let viewportHeight = scrollVisibleRect.height > 0 ? scrollVisibleRect.height : 500
        let offsetX = max(0, targetContentX - viewportWidth / 2)
        let offsetY = max(0, targetContentY - viewportHeight / 2)
        scrollPosition.scrollTo(point: CGPoint(x: offsetX, y: offsetY))
    }

    @ViewBuilder
    private func nodeView(_ node: MindMapNode) -> some View {
        MindMapNodeShapeView(
            node: node,
            isSelected: selectedNodeIDs.contains(node.persistentModelID),
            isEditing: editingNodeID == node.persistentModelID,
            isEditingDescription: editingDescriptionNodeID == node.persistentModelID,
            fillColor: resolvedColor(node.color),
            borderColor: resolvedColor(node.resolvedBorderColor),
            accent: accent,
            canvasSpace: Self.canvasSpace,
            scale: zoomScale,
            onSelect: {
                selectSingle(node)
                if editingNodeID != node.persistentModelID {
                    editingNodeID = nil
                }
                if editingDescriptionNodeID != node.persistentModelID {
                    editingDescriptionNodeID = nil
                }
            },
            onBeginEdit: {
                selectedNodeIDs = [node.persistentModelID]
                editingDescriptionNodeID = nil
                editingNodeID = node.persistentModelID
            },
            onEndEdit: {
                editingNodeID = nil
                node.updatedAt = .now
            },
            onBeginEditDescription: {
                selectedNodeIDs = [node.persistentModelID]
                editingNodeID = nil
                editingDescriptionNodeID = node.persistentModelID
            },
            onEndEditDescription: {
                editingDescriptionNodeID = nil
                node.updatedAt = .now
            },
            onDragBegin: { beginBulkDrag(anchor: node) },
            onDragChanged: { deltaX, deltaY in applyBulkDrag(deltaX: deltaX, deltaY: deltaY) },
            onDragEnded: { endBulkDrag() },
            showsLinkHandles: selectedNodeIDs.count == 1
                && selectedNodeIDs.contains(node.persistentModelID)
                && editingNodeID != node.persistentModelID
                && editingDescriptionNodeID != node.persistentModelID,
            onLinkDragChanged: { handle, location in handleLinkDragChanged(node, handle: handle, location: location) },
            onLinkDragEnded: { handle, location in handleLinkDragEnded(node, handle: handle, location: location) }
        )
        // 메뉴는 우클릭한 노드 기준으로 동작한다. 다중 선택에 포함된 노드를 우클릭해 삭제하면 선택 전체가 삭제된다
        // (사이드 패널의 "선택 노드 삭제"와 동일 — 루트는 `deleteNode(_:)`가 건너뜀). 설명이 이미 있으면
        // "설명 추가" 대신 "설명 편집"/"설명 삭제"를 보여준다.
        .contextMenu {
            Button {
                addChild(to: node)
            } label: {
                Label("노드 추가", systemImage: "plus.circle")
            }
            Button(role: .destructive) {
                if selectedNodeIDs.count > 1, selectedNodeIDs.contains(node.persistentModelID) {
                    deleteSelectedNodes()
                } else {
                    deleteNode(node)
                }
            } label: {
                Label("노드 삭제", systemImage: "trash")
            }
            .disabled(isMainRoot(node) && !(selectedNodeIDs.count > 1 && selectedNodeIDs.contains(node.persistentModelID)))
            // 복사는 우클릭한 노드의 도형(색·모양)·테두리·선 스타일 전체, 붙여넣기는 이 노드(다중 선택 중 하나를
            // 우클릭했으면 선택 전체)에 그 값을 덮어쓴다.
            Button {
                copiedStyle = MindMapStyleTemplate(node: node)
            } label: {
                Label("스타일 복사", systemImage: "doc.on.doc")
            }
            Button {
                pasteStyle(onto: node)
            } label: {
                Label("스타일 붙여넣기", systemImage: "doc.on.clipboard")
            }
            .disabled(copiedStyle == nil)
            if node.descriptionText == nil {
                Button {
                    addDescription(to: node)
                } label: {
                    Label("설명 추가", systemImage: "text.append")
                }
            } else {
                Button {
                    selectedNodeIDs = [node.persistentModelID]
                    editingNodeID = nil
                    editingDescriptionNodeID = node.persistentModelID
                } label: {
                    Label("설명 편집", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    removeDescription(from: node)
                } label: {
                    Label("설명 삭제", systemImage: "text.badge.minus")
                }
            }
        }
    }

    /// 설명 추가 — 노드 하단에 설명 영역을 만든다. 제목 영역이 원래 크기를 유지하도록 그 높이를 `labelHeight`로 고정하고
    /// 노드 높이를 두 배로 늘린다(중심 좌표는 그대로). 이후 크기 조절은 설명 영역만 늘리고 줄인다.
    /// `removeDescription`이 노드 높이를 `labelHeight`(원래 제목 영역 높이)로 되돌린다.
    /// 설명은 빈 문자열로 시작해 곧바로 편집 모드로 들어간다.
    private func addDescription(to node: MindMapNode) {
        guard node.descriptionText == nil else { return }
        node.descriptionText = ""
        node.labelHeight = node.height
        node.height = node.height * 2
        node.updatedAt = .now
        selectedNodeIDs = [node.persistentModelID]
        editingNodeID = nil
        editingDescriptionNodeID = node.persistentModelID
    }

    private func removeDescription(from node: MindMapNode) {
        guard node.descriptionText != nil else { return }
        node.descriptionText = nil
        node.height = max(40, node.resolvedLabelHeight)
        node.labelHeight = nil
        node.updatedAt = .now
        if editingDescriptionNodeID == node.persistentModelID {
            editingDescriptionNodeID = nil
        }
    }

    /// 여러 노드 함께 드래그 시작. `anchor`가 현재 다중 선택에 포함돼 있으면 선택 노드 전체의 시작 위치를 기억하고,
    /// 아니면 기존 다중 선택을 풀고 이 노드 하나만 단일 드래그로 처리한다(선택과 무관한 노드가 무리에 끼어 움직이는 것을 막는다).
    private func beginBulkDrag(anchor node: MindMapNode) {
        guard multiDragStartPositions.isEmpty else { return }
        let targets: [MindMapNode]
        if selectedNodeIDs.contains(node.persistentModelID), selectedNodeIDs.count > 1 {
            targets = selectedNodes
        } else {
            selectedNodeIDs = [node.persistentModelID]
            targets = [node]
        }
        for target in targets {
            multiDragStartPositions[target.persistentModelID] = (target.positionX, target.positionY)
        }
    }

    /// `DragGesture.Value.translation`(시작점 기준 누적 이동량, 모델 좌표로 이미 나눠 전달됨 — `MindMapNodeShapeView` 참고)을
    /// `beginBulkDrag`가 기억해 둔 시작 위치에 매번 새로 더한다("시작 위치 + 총 이동량"이라 프레임 수와 무관하게 정확).
    private func applyBulkDrag(deltaX: Double, deltaY: Double) {
        for node in nodes {
            guard let start = multiDragStartPositions[node.persistentModelID] else { continue }
            node.positionX = start.x + deltaX
            node.positionY = start.y + deltaY
        }
    }

    private func endBulkDrag() {
        multiDragStartPositions.removeAll()
    }

    // MARK: - 선(엣지) 그리기 — 고정 4방향 소켓 + 베지어/꺾은선

    private enum PortSide {
        case top, bottom, left, right
    }

    private func portPoint(_ node: MindMapNode, side: PortSide) -> CGPoint {
        // 노드가 `zoomScale`만큼 확대/축소되어 그려지므로 선의 끝점도 같은 좌표계(화면 크기 기준)로 계산해야
        // 노드 테두리에 정확히 붙는다.
        let cx = CGFloat(node.positionX) * zoomScale
        let cy = CGFloat(node.positionY) * zoomScale
        let halfWidth = CGFloat(node.width) * zoomScale / 2
        let halfHeight = CGFloat(node.height) * zoomScale / 2
        switch side {
        case .top: return CGPoint(x: cx, y: cy - halfHeight)
        case .bottom: return CGPoint(x: cx, y: cy + halfHeight)
        case .left: return CGPoint(x: cx - halfWidth, y: cy)
        case .right: return CGPoint(x: cx + halfWidth, y: cy)
        }
    }

    /// 두 노드의 상대 위치로 매번 다시 계산하는 포트 선택 — 노드를 옮기면
    /// 자동으로 재계산된다(모델에 저장하지 않는 이유는 `MindMapNode` 타입
    /// 주석 참고). 목업의 `pickPorts` 로직을 그대로 옮겼다.
    private func pickPorts(from a: MindMapNode, to b: MindMapNode) -> (a: CGPoint, b: CGPoint, aSide: PortSide, bSide: PortSide) {
        let dx = b.positionX - a.positionX
        let dy = b.positionY - a.positionY
        let aSide: PortSide
        let bSide: PortSide
        if abs(dx) >= abs(dy) {
            aSide = dx >= 0 ? .right : .left
            bSide = dx >= 0 ? .left : .right
        } else {
            aSide = dy >= 0 ? .bottom : .top
            bSide = dy >= 0 ? .top : .bottom
        }
        return (portPoint(a, side: aSide), portPoint(b, side: bSide), aSide, bSide)
    }

    private func pullVector(_ side: PortSide, magnitude: CGFloat) -> CGVector {
        switch side {
        case .right: return CGVector(dx: magnitude, dy: 0)
        case .left: return CGVector(dx: -magnitude, dy: 0)
        case .bottom: return CGVector(dx: 0, dy: magnitude)
        case .top: return CGVector(dx: 0, dy: -magnitude)
        }
    }

    private func buildPath(from a: CGPoint, to b: CGPoint, kind: MindMapPathType, fromSide: PortSide, toSide: PortSide) -> Path {
        var path = Path()
        switch kind {
        case .elbow:
            // 좌/우 포트는 가로로, 상/하 포트는 세로로 먼저 뻗어야 도형에서 수직으로 빠져나오는 것처럼 보인다.
            path.move(to: a)
            if fromSide == .left || fromSide == .right {
                let midX = (a.x + b.x) / 2
                path.addLine(to: CGPoint(x: midX, y: a.y))
                path.addLine(to: CGPoint(x: midX, y: b.y))
                path.addLine(to: b)
            } else {
                let midY = (a.y + b.y) / 2
                path.addLine(to: CGPoint(x: a.x, y: midY))
                path.addLine(to: CGPoint(x: b.x, y: midY))
                path.addLine(to: b)
            }
        case .bezier:
            let magnitude = max(abs(b.x - a.x), abs(b.y - a.y)) * 0.5
            let pullA = pullVector(fromSide, magnitude: magnitude)
            let pullB = pullVector(toSide, magnitude: magnitude)
            path.move(to: a)
            path.addCurve(
                to: b,
                control1: CGPoint(x: a.x + pullA.dx, y: a.y + pullA.dy),
                control2: CGPoint(x: b.x + pullB.dx, y: b.y + pullB.dy)
            )
        }
        return path
    }

    private func drawEdges(context: GraphicsContext) {
        for node in nodes {
            drawEdge(context: context, node: node)
        }
        drawEdgeDragPreview(context: context)
        drawLinkDragPreview(context: context)
    }

    /// 한 노드의 선(부모 → 이 노드) 하나를 그린다.
    private func drawEdge(context: GraphicsContext, node: MindMapNode) {
        guard let parent = node.parent else { return }
        let ports = pickPorts(from: parent, to: node)
        let path = buildPath(from: ports.a, to: ports.b, kind: node.pathType, fromSide: ports.aSide, toSide: ports.bSide)
        let isSelected = selectedNodeIDs.contains(node.persistentModelID)
        let level = edgeLevel(of: node)
        // 옅어짐은 선 색의 불투명도만 낮춘다. 선을 끌고 있는 동안에는 원래 선을 흐리게 남겨 "어디서 떼어 내는지" 보이게 한다.
        var opacity: Double = node.resolvedLineFadeByDepth ? Self.fadeOpacity(forLevel: level) : 1
        if edgeDrag?.childID == node.persistentModelID {
            opacity *= 0.3
        }
        let strokeColor = resolvedColor(node.resolvedLineColor).opacity(opacity)
        // 선 두께·점 간격·화살표는 확대/축소 배율과 무관하게 항상 같은 절대 굵기/간격으로 그린다(선 굵기는 원래 배율과 무관한 고정값).
        let selectionBoost: CGFloat = isSelected ? 1.4 : 1.0

        if node.resolvedLineStyle == .taper {
            // 굵기가 선 위에서 연속으로 변해 `StrokeStyle`(일정 굵기)로는 그릴 수 없다 —
            // 경로를 잘게 나눈 점들로 양옆 윤곽을 만들어 다각형으로 채운다.
            let widths = taperWidths(for: node, level: level)
            let polygon = taperedPolygon(
                points: flattenedPoints(path),
                startWidth: widths.start * selectionBoost,
                endWidth: widths.end * selectionBoost
            )
            context.fill(polygon, with: .color(strokeColor))
            return
        }

        let baseWidth = CGFloat(node.lineThickness) * selectionBoost
        let dash: [CGFloat]
        switch node.resolvedLineStyle {
        case .solid, .arrow, .taper:
            dash = []
        case .dashed:
            // 점 길이(2pt)는 고정하고 점 사이 간격만 `dashSpacing`으로 조절한다 — `MindMapNode.dashSpacing` 주석 참고.
            dash = [2, CGFloat(node.dashSpacing)]
        }
        context.stroke(
            path,
            with: .color(strokeColor),
            style: StrokeStyle(lineWidth: baseWidth, lineCap: .round, dash: dash)
        )

        if node.resolvedLineStyle == .arrow {
            // 화살표 방향 = 도착 포트(bSide)의 안쪽 방향(`pullVector`가 돌려주는 바깥쪽 벡터의 반대).
            // 포트가 축에 고정돼 있어 bezier/꺾은선 모두 도착 지점의 접선 방향이 이와 같다.
            let outward = pullVector(ports.bSide, magnitude: 1)
            let direction = CGVector(dx: -outward.dx, dy: -outward.dy)
            let arrowSize: CGFloat = isSelected ? 10 : 8
            let arrow = arrowheadPath(at: ports.b, direction: direction, shape: node.resolvedArrowShape, size: arrowSize)
            switch node.resolvedArrowShape {
            case .open:
                context.stroke(arrow, with: .color(strokeColor), style: StrokeStyle(lineWidth: baseWidth, lineCap: .round, lineJoin: .round))
            case .closedTriangle, .diamond, .circle:
                context.fill(arrow, with: .color(strokeColor))
            }
        }
    }

    // MARK: - 선 스타일 "점점 얇게" / 깊이별 옅어짐

    /// 노드의 "선 단계" — 부모로 몇 번 올라가면 루트(부모 없는 노드)인지. 루트 바로
    /// 아래 노드의 선이 1단계다. 순환 참조 방어용으로 상한(200)을 둔다(정상
    /// 트리에서는 일어나지 않는다).
    private func edgeLevel(of node: MindMapNode) -> Int {
        var level = 0
        var current = node
        while let parent = current.parent, level < 200 {
            level += 1
            current = parent
        }
        return level
    }

    /// "점점 얇게"가 실제로 얇아지는 단계 수 — 1~3단계 선은 시작→끝으로 얇아지고, 4단계부터는 굵기가 일정하다.
    private static let taperMaxLevel = 3
    /// 한 단계 안에서 끝 굵기 = 시작 굵기 × 이 비율.
    private static let taperRatio: CGFloat = 0.6
    /// 너무 얇아져 사라지는 것을 막는 하한(pt) — 슬라이더 최소값(1)에서 3단계를
    /// 지나면 0.216pt가 되므로 필요하다.
    private static let taperMinWidth: CGFloat = 0.75
    /// 깊이별 옅어짐의 불투명도 — 1단계 100%, 2단계 75%, 3단계 55%, 4단계 이후 40%.
    private static func fadeOpacity(forLevel level: Int) -> Double {
        let table: [Double] = [1.0, 0.75, 0.55, 0.40]
        let index = min(max(level, 1), table.count) - 1
        return table[index]
    }

    /// 부모의 선도 "점점 얇게"이면 이 노드의 선은 부모 선의 끝 굵기에서 이어 시작한다.
    /// 부모가 루트면 부모→루트 선이 없으므로 이어받을 선이 없다.
    private func taperInheritsParent(_ node: MindMapNode) -> Bool {
        guard let parent = node.parent, parent.parent != nil else { return false }
        return parent.resolvedLineStyle == .taper
    }

    /// 이 노드의 선 시작/끝 굵기(pt, 선택 강조 전). 시작은 (부모 선을 이어받으면 부모
    /// 선의 끝, 아니면 이 노드의 `lineThickness`), 끝은 1~3단계면 시작의 60%(하한
    /// 0.75pt), 4단계부터는 시작과 같다(일정한 실선).
    private func taperWidths(for node: MindMapNode, level: Int, guardDepth: Int = 0) -> (start: CGFloat, end: CGFloat) {
        let start: CGFloat
        if taperInheritsParent(node), let parent = node.parent, guardDepth < 200 {
            start = taperWidths(for: parent, level: level - 1, guardDepth: guardDepth + 1).end
        } else {
            start = CGFloat(node.resolvedTaperThickness)
        }
        let end = level <= Self.taperMaxLevel ? max(start * Self.taperRatio, Self.taperMinWidth) : start
        return (start, min(start, end))
    }

    /// `Path`를 직선 조각들의 점 목록으로 편다 — 베지어 곡선은 잘게 나눠 근사한다
    /// (곡선 32조각/이차 곡선 16조각이면 화면 크기에서 눈에 띄는 각이 없다).
    private func flattenedPoints(_ path: Path) -> [CGPoint] {
        var points: [CGPoint] = []
        var current = CGPoint.zero
        path.forEach { element in
            switch element {
            case .move(to: let p):
                points.append(p)
                current = p
            case .line(to: let p):
                points.append(p)
                current = p
            case .quadCurve(to: let p, control: let c):
                let a = current
                for step in 1...16 {
                    let t = CGFloat(step) / 16
                    let u = 1 - t
                    points.append(CGPoint(
                        x: u * u * a.x + 2 * u * t * c.x + t * t * p.x,
                        y: u * u * a.y + 2 * u * t * c.y + t * t * p.y
                    ))
                }
                current = p
            case .curve(to: let p, control1: let c1, control2: let c2):
                let a = current
                for step in 1...32 {
                    let t = CGFloat(step) / 32
                    let u = 1 - t
                    let b0 = u * u * u
                    let b1 = 3 * u * u * t
                    let b2 = 3 * u * t * t
                    let b3 = t * t * t
                    points.append(CGPoint(
                        x: b0 * a.x + b1 * c1.x + b2 * c2.x + b3 * p.x,
                        y: b0 * a.y + b1 * c1.y + b2 * c2.y + b3 * p.y
                    ))
                }
                current = p
            case .closeSubpath:
                break
            }
        }
        return points
    }

    /// 점 목록을 따라 굵기가 `startWidth`에서 `endWidth`로 (경로 길이에 비례해) 선형으로 변하는 띠 다각형을 만든다.
    /// 꺾이는 점은 두 구간 법선의 이등분선 방향으로 `1/cos(반각)`만큼(miter, 상한 2배) 늘려 모서리에서 굵기가 줄어 보이지 않게 한다.
    /// 양 끝은 각지게(butt) 끝난다 — 시작은 부모, 끝은 자식 노드 테두리 위라 노드가 위에 그려져 가린다.
    private func taperedPolygon(points: [CGPoint], startWidth: CGFloat, endWidth: CGFloat) -> Path {
        var pts: [CGPoint] = []
        for point in points {
            if let last = pts.last, hypot(point.x - last.x, point.y - last.y) < 0.01 { continue }
            pts.append(point)
        }
        guard pts.count >= 2 else { return Path() }

        var cumulative: [CGFloat] = [0]
        for index in 1..<pts.count {
            cumulative.append(cumulative[index - 1] + hypot(pts[index].x - pts[index - 1].x, pts[index].y - pts[index - 1].y))
        }
        let total = max(cumulative[cumulative.count - 1], 0.001)

        func leftNormal(from a: CGPoint, to b: CGPoint) -> CGVector {
            let length = max(hypot(b.x - a.x, b.y - a.y), 0.0001)
            return CGVector(dx: -(b.y - a.y) / length, dy: (b.x - a.x) / length)
        }

        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for index in 0..<pts.count {
            let previous: CGVector? = index > 0 ? leftNormal(from: pts[index - 1], to: pts[index]) : nil
            let next: CGVector? = index < pts.count - 1 ? leftNormal(from: pts[index], to: pts[index + 1]) : nil
            var normal = previous ?? next ?? CGVector(dx: 0, dy: 1)
            var miter: CGFloat = 1
            if let a = previous, let b = next {
                let sum = CGVector(dx: a.dx + b.dx, dy: a.dy + b.dy)
                let length = hypot(sum.dx, sum.dy)
                if length > 0.0001 {
                    normal = CGVector(dx: sum.dx / length, dy: sum.dy / length)
                    let cosHalf = max(0.5, normal.dx * a.dx + normal.dy * a.dy)
                    miter = 1 / cosHalf
                } else {
                    normal = a
                }
            }
            let t = cumulative[index] / total
            let half = (startWidth + (endWidth - startWidth) * t) / 2 * miter
            left.append(CGPoint(x: pts[index].x + normal.dx * half, y: pts[index].y + normal.dy * half))
            right.append(CGPoint(x: pts[index].x - normal.dx * half, y: pts[index].y - normal.dy * half))
        }

        var polygon = Path()
        polygon.move(to: left[0])
        for point in left.dropFirst() {
            polygon.addLine(to: point)
        }
        for point in right.reversed() {
            polygon.addLine(to: point)
        }
        polygon.closeSubpath()
        return polygon
    }

    // MARK: - 선 드래그로 부모 변경 / 연결 해제

    /// 캔버스 배경 드래그의 시작/진행 — 시작 순간 한 번 선을 잡았는지 판정해, 잡았으면 선 드래그(부모 변경/연결 해제), 아니면 러버밴드 선택.
    /// 노드 위에서 시작된 드래그는 노드 자신의 제스처가 먼저 가로채므로 여기에 오지 않는다.
    private func handleCanvasDragChanged(_ value: DragGesture.Value) {
        if canvasDragStart != value.startLocation {
            // 새 드래그의 첫 이벤트 — 비정상 종료로 남았을 수 있는 `edgeDrag`/`selectionRect` 상태를 정리하고 모드를 정한다.
            canvasDragStart = value.startLocation
            selectionRect = nil
            if let child = edgeChild(at: value.startLocation) {
                edgeDrag = EdgeDragState(
                    childID: child.persistentModelID,
                    startLocation: value.startLocation,
                    location: value.location
                )
            } else {
                edgeDrag = nil
            }
            // 맥OS: 선 위에서 시작한 드래그가 아니고 ⇧를 누르지 않았으면 화면 이동. 그 밖(⇧ 선택, 아이패드/아이폰)은 선택 사각형.
            #if os(macOS)
            isCanvasPanning = edgeDrag == nil && !NSEvent.modifierFlags.contains(.shift)
            #else
            isCanvasPanning = false
            #endif
            panStartOrigin = nil
        }
        if edgeDrag != nil {
            edgeDrag?.location = value.location
        } else if isCanvasPanning {
            // 화면 이동은 `handleCanvasPanChanged`가 처리한다 — 선택 사각형은 그리지 않는다.
            selectionRect = nil
        } else {
            selectionRect = CGRect(
                x: min(value.startLocation.x, value.location.x),
                y: min(value.startLocation.y, value.location.y),
                width: abs(value.location.x - value.startLocation.x),
                height: abs(value.location.y - value.startLocation.y)
            )
        }
    }

    private func handleCanvasDragEnded(_ value: DragGesture.Value) {
        if var drag = edgeDrag {
            drag.location = value.location
            finishEdgeDrag(drag)
        } else if let rect = selectionRect {
            let hits = nodes.filter { node in
                nodeFrame(node).intersects(rect)
            }
            selectedNodeIDs = Set(hits.map(\.persistentModelID))
            if !hits.isEmpty {
                editingNodeID = nil
                editingDescriptionNodeID = nil
            }
        }
        selectionRect = nil
        edgeDrag = nil
        canvasDragStart = nil
        isCanvasPanning = false
        panStartOrigin = nil
    }

    /// 맥OS 화면 이동 — 드래그 시작 때의 스크롤 위치에서 손가락(커서) 이동량만큼 반대로 스크롤한다(콘텐츠를 잡아 끄는 느낌).
    /// 캔버스 가장자리를 넘지 않도록 0...(콘텐츠 − 가시 영역)으로 자른다.
    private func handleCanvasPanChanged(translation: CGSize) {
        guard isCanvasPanning else { return }
        if panStartOrigin == nil { panStartOrigin = scrollVisibleRect.origin }
        guard let start = panStartOrigin else { return }
        let maxX = max(0, Self.canvasSize.width * zoomScale - scrollVisibleRect.width)
        let maxY = max(0, Self.canvasSize.height * zoomScale - scrollVisibleRect.height)
        scrollPosition.scrollTo(point: CGPoint(
            x: min(max(0, start.x - translation.width), maxX),
            y: min(max(0, start.y - translation.height), maxY)
        ))
    }

    /// `point`(캔버스 콘텐츠 좌표) 근처(`edgeHitTolerance` 이내)의 선 중 가장 가까운 것의 자식 노드. 없으면 `nil`.
    /// 드래그 시작 순간에만 부르므로 노드 300개 이하(선 최대 300개 × 점 32개 안팎)에서 부담이 없다.
    private func edgeChild(at point: CGPoint) -> MindMapNode? {
        var best: MindMapNode?
        var bestDistance = Self.edgeHitTolerance
        for node in nodes {
            guard let parent = node.parent else { continue }
            let ports = pickPorts(from: parent, to: node)
            let path = buildPath(from: ports.a, to: ports.b, kind: node.pathType, fromSide: ports.aSide, toSide: ports.bSide)
            let distance = distanceFrom(point, toPolyline: flattenedPoints(path))
            if distance <= bestDistance {
                bestDistance = distance
                best = node
            }
        }
        return best
    }

    private func distanceFrom(_ p: CGPoint, toPolyline points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return .greatestFiniteMagnitude }
        var minimum = CGFloat.greatestFiniteMagnitude
        for index in 1..<points.count {
            let a = points[index - 1]
            let b = points[index]
            let abx = b.x - a.x
            let aby = b.y - a.y
            let lengthSquared = abx * abx + aby * aby
            var t: CGFloat = lengthSquared > 0 ? ((p.x - a.x) * abx + (p.y - a.y) * aby) / lengthSquared : 0
            t = max(0, min(1, t))
            let closest = CGPoint(x: a.x + t * abx, y: a.y + t * aby)
            minimum = min(minimum, hypot(p.x - closest.x, p.y - closest.y))
        }
        return minimum
    }

    /// `candidate`가 `ancestor` 자신이거나 그 하위(자손)인지 — 새 부모로 삼으면
    /// 순환(트리가 아닌 고리)이 생기는 경우를 가려낸다.
    private func isSameOrDescendant(_ candidate: MindMapNode, of ancestor: MindMapNode) -> Bool {
        var current: MindMapNode? = candidate
        var steps = 0
        while let node = current, steps < 500 {
            if node.persistentModelID == ancestor.persistentModelID { return true }
            current = node.parent
            steps += 1
        }
        return false
    }

    /// 선을 `location`에 놓았을 때의 결과. 어느 쪽 끝을 잡았든 선의 위쪽 노드(부모)가 놓은 노드와 연결되어
    /// 그 노드가 새 자식이 되고, 옮긴 선의 원래 자식은 연결이 끊긴 채 따로 남는다.
    ///   - 놓은 노드가 규칙(`canConnect`)을 만족하면 `.attach`
    ///   - 규칙 위반(이미 부모가 있음/순환/루트와 끊긴 부모 등)이면 `.blocked`(변화 없음)
    ///   - 자기 자신·원래 자식 위는 `.cancel`(변화 없음)
    ///   - 빈 곳: 잡은 자리에서 `edgeDragMinDisconnectDistance` 이상 끌었으면 연결 해제,
    ///     아니면 원위치(실수 방지)
    private func edgeDragOutcome(child: MindMapNode, parent: MindMapNode, at location: CGPoint, from start: CGPoint) -> EdgeDragOutcome {
        if let target = nodes.last(where: { nodeFrame($0).contains(location) }) {
            if target.persistentModelID == parent.persistentModelID || target.persistentModelID == child.persistentModelID {
                return .cancel
            }
            return canConnect(parent: parent, child: target) ? .attach(target) : .blocked
        }
        let moved = hypot(location.x - start.x, location.y - start.y)
        return moved >= Self.edgeDragMinDisconnectDistance ? .disconnect : .cancel
    }

    private func finishEdgeDrag(_ drag: EdgeDragState) {
        defer { edgeDrag = nil }
        guard let child = nodes.first(where: { $0.persistentModelID == drag.childID }),
              let parent = child.parent else { return }
        switch edgeDragOutcome(child: child, parent: parent, at: drag.location, from: drag.startLocation) {
        case .cancel, .blocked:
            break
        case .attach(let target):
            child.parent = nil
            target.parent = parent
            child.updatedAt = .now
            target.updatedAt = .now
            selectedNodeIDs = [target.persistentModelID]
        case .disconnect:
            child.parent = nil
            child.updatedAt = .now
            selectedNodeIDs = [child.persistentModelID]
        }
    }

    // MARK: - 노드 위·아래 중앙 버튼으로 선 잇기

    /// 버튼을 끌고 있는 동안 — 미리보기 좌표만 갱신한다.
    private func handleLinkDragChanged(_ node: MindMapNode, handle: MindMapLinkHandle, location: CGPoint) {
        linkDrag = LinkDragState(sourceID: node.persistentModelID, handle: handle, location: location)
    }

    /// 버튼을 놓았을 때 — 놓은 자리의 노드와 `canConnect` 규칙을 만족하면 잇는다. 아래 버튼은 "이 노드 → 놓은 노드(자식)",
    /// 위 버튼은 "놓은 노드(부모) → 이 노드".
    private func handleLinkDragEnded(_ node: MindMapNode, handle: MindMapLinkHandle, location: CGPoint) {
        defer { linkDrag = nil }
        guard let target = linkTarget(at: location, excluding: node) else { return }
        let pair = linkPair(source: node, handle: handle, target: target)
        guard canConnect(parent: pair.parent, child: pair.child) else { return }
        pair.child.parent = pair.parent
        pair.child.updatedAt = .now
    }

    private func linkTarget(at location: CGPoint, excluding source: MindMapNode) -> MindMapNode? {
        nodes.last(where: { $0.persistentModelID != source.persistentModelID && nodeFrame($0).contains(location) })
    }

    private func linkPair(source: MindMapNode, handle: MindMapLinkHandle, target: MindMapNode) -> (parent: MindMapNode, child: MindMapNode) {
        switch handle {
        case .bottom: return (source, target)
        case .top: return (target, source)
        }
    }

    /// 버튼을 끄는 동안의 미리보기 — 버튼 위치에서 포인터까지 점선. 노드 위에 있으면 연결
    /// 가능(강조색)/불가(주황)를 색과 대상 테두리로 알려 준다.
    private func drawLinkDragPreview(context: GraphicsContext) {
        guard let drag = linkDrag,
              let source = nodes.first(where: { $0.persistentModelID == drag.sourceID }) else { return }
        var previewColor: Color = .secondary
        if let target = linkTarget(at: drag.location, excluding: source) {
            let pair = linkPair(source: source, handle: drag.handle, target: target)
            previewColor = canConnect(parent: pair.parent, child: pair.child) ? accent : .orange
            let frame = nodeFrame(target).insetBy(dx: -4, dy: -4)
            context.stroke(Path(roundedRect: frame, cornerRadius: 16), with: .color(previewColor), lineWidth: 3)
        }
        let fromSide: PortSide = drag.handle == .bottom ? .bottom : .top
        let start = portPoint(source, side: fromSide)
        let toSide: PortSide = drag.location.y >= start.y ? .top : .bottom
        let path = buildPath(from: start, to: drag.location, kind: currentPathType, fromSide: fromSide, toSide: toSide)
        context.stroke(
            path,
            with: .color(previewColor),
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 4])
        )
    }

    /// 선을 끄는 동안의 미리보기 — 부모 쪽 포트에서 포인터까지 점선. 색으로 결과를
    /// 알려 준다: 강조색 = 그 노드가 위쪽 노드의 새 자식이 됨(대상 노드에도 강조 테두리),
    /// 주황 = 그 노드에는 연결할 수 없음(부모가 이미 있음/순환 등), 빨강 = 놓으면 연결이
    /// 끊김, 회색 = 놓아도 아무 일 없음.
    private func drawEdgeDragPreview(context: GraphicsContext) {
        guard let drag = edgeDrag,
              let child = nodes.first(where: { $0.persistentModelID == drag.childID }),
              let parent = child.parent else { return }
        let previewColor: Color
        switch edgeDragOutcome(child: child, parent: parent, at: drag.location, from: drag.startLocation) {
        case .attach(let target):
            previewColor = accent
            let frame = nodeFrame(target).insetBy(dx: -4, dy: -4)
            context.stroke(Path(roundedRect: frame, cornerRadius: 16), with: .color(accent), lineWidth: 3)
        case .blocked:
            previewColor = .orange
        case .disconnect:
            previewColor = .red
        case .cancel:
            previewColor = .secondary
        }
        let dx = drag.location.x - CGFloat(parent.positionX) * zoomScale
        let dy = drag.location.y - CGFloat(parent.positionY) * zoomScale
        let fromSide: PortSide
        let toSide: PortSide
        if abs(dx) >= abs(dy) {
            fromSide = dx >= 0 ? .right : .left
            toSide = dx >= 0 ? .left : .right
        } else {
            fromSide = dy >= 0 ? .bottom : .top
            toSide = dy >= 0 ? .top : .bottom
        }
        let path = buildPath(
            from: portPoint(parent, side: fromSide),
            to: drag.location,
            kind: child.pathType,
            fromSide: fromSide,
            toSide: toSide
        )
        context.stroke(
            path,
            with: .color(previewColor),
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 4])
        )
    }

    /// 화살표 머리 모양 4종의 도형. `tip`(도착 포트 좌표)과 `direction`(진행 방향 단위벡터)만으로 어느 방향이든
    /// 같은 모양을 그리도록 로컬 좌표를 방향만큼 회전시켜 계산한다.
    private func arrowheadPath(at tip: CGPoint, direction: CGVector, shape: MindMapArrowShape, size: CGFloat) -> Path {
        let angle = atan2(direction.dy, direction.dx)
        func rotated(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
            CGPoint(
                x: tip.x + dx * cos(angle) - dy * sin(angle),
                y: tip.y + dx * sin(angle) + dy * cos(angle)
            )
        }
        var path = Path()
        switch shape {
        case .closedTriangle:
            let back1 = rotated(-size, size * 0.55)
            let back2 = rotated(-size, -size * 0.55)
            path.move(to: tip)
            path.addLine(to: back1)
            path.addLine(to: back2)
            path.closeSubpath()
        case .open:
            let back1 = rotated(-size, size * 0.55)
            let back2 = rotated(-size, -size * 0.55)
            path.move(to: back1)
            path.addLine(to: tip)
            path.addLine(to: back2)
        case .diamond:
            let back = rotated(-size * 1.6, 0)
            let side1 = rotated(-size * 0.8, size * 0.5)
            let side2 = rotated(-size * 0.8, -size * 0.5)
            path.move(to: tip)
            path.addLine(to: side1)
            path.addLine(to: back)
            path.addLine(to: side2)
            path.closeSubpath()
        case .circle:
            let center = rotated(-size * 0.7, 0)
            path.addEllipse(in: CGRect(x: center.x - size * 0.7, y: center.y - size * 0.7, width: size * 1.4, height: size * 1.4))
        }
        return path
    }

    // MARK: - 사이드 패널

    private var sidePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sermonStructureSection
                Divider()
                if selectedNodeIDs.count > 1 {
                    // 2개 이상 선택되면 단일 노드용 섹션 대신 일괄 조작 섹션을 보여준다.
                    bulkActionsSection(selectedNodes)
                } else if let selectedNode {
                    selectionSection(selectedNode)
                    Divider()
                    shapeStyleSection(selectedNode)
                    Divider()
                    fontStyleSection(selectedNode)
                    Divider()
                    borderStyleSection(selectedNode)
                    Divider()
                    lineStyleSection(selectedNode)
                }
            }
            // 콘텐츠 폭을 패널 폭 − 좌우 패딩(16×2)으로 고정 — 위
            // `sidePanelWidth` 주석 참고.
            .frame(width: Self.sidePanelWidth - 32, alignment: .leading)
            .padding(16)
        }
        .background(settings.bibleBackgroundColor ?? Color.clear)
    }

    /// 사이드 패널 상단의 "설교문 적용" 안내(라벨 + 설명 행)와 적용 버튼.
    private var sermonStructureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("설교문 적용")
                .font(.body.weight(.bold))
            Text("마인드맵을 설교문 글로 바꿔 기존 본문 아래에 추가합니다.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                structureRow("설교 제목", "루트(중심) 노드")
                structureRow("문단 구성", "하위 노드 단계별 전개\n(대주제 → 중주제 → 소주제 → 본문)")
                structureRow("전개 순서", "같은 단계는 왼쪽에서 오른쪽 순")
                structureRow("적용 위치", "기존 본문 하단에 이어 붙이기")
            }
            Button("설교문 적용") { requestExport() }
                .buttonStyle(SermonPillButtonStyle(isFilled: true, tint: accent))
        }
    }

    /// 설교문 적용 안내의 한 줄 — 왼쪽 알약형 라벨(폭 고정으로 세로 정렬) + 오른쪽 설명.
    private func structureRow(_ label: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.vertical, 2)
                .frame(width: 58)
                .background(Capsule().fill(accent.opacity(0.22)))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func selectionSection(_ node: MindMapNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("선택된 노드")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                Button {
                    addChild(to: node)
                } label: {
                    Text("하위 노드 추가")
                }
                .buttonStyle(SermonMiniPillButtonStyle(isFilled: false, tint: accent))

                Button(role: .destructive) {
                    deleteNode(node)
                } label: {
                    Text("이 노드 삭제")
                }
                .buttonStyle(SermonMiniPillButtonStyle(isFilled: false, tint: .red))
                // `deleteNode(_:)`도 루트를 막지만, 버튼도 미리 비활성화한다.
                .disabled(isMainRoot(node))
            }
            if isMainRoot(node) {
                Text("루트 노드는 삭제할 수 없습니다 — 마인드맵 전체의 시작점입니다.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 여러 노드가 동시에 선택됐을 때(`selectedNodeIDs.count > 1`)의 사이드 패널 — 일괄 삭제와 도형·테두리·선 스타일 일괄 적용.
    /// 단일 노드용 섹션과 분리해 기존 단일 선택 흐름에 영향을 주지 않는다.
    /// 스와치의 현재 선택 표시는 노드마다 값이 다를 수 있어 첫 번째 노드의 값만 대표로 보여준다.
    private func bulkActionsSection(_ selectedNodes: [MindMapNode]) -> some View {
        // 루트가 선택에 섞여 있어도 스타일은 일괄 적용된다(트리 구조 불변식을 깨지 않음) — 삭제만 `deleteSelectedNodes()`가 루트를 건너뛴다.
        let representative = selectedNodes.first
        return VStack(alignment: .leading, spacing: 12) {
            Text("선택된 노드 \(selectedNodes.count)개")
                .font(.subheadline.weight(.semibold))
            Button(role: .destructive) {
                deleteSelectedNodes()
            } label: {
                Text("선택 노드 삭제")
            }
            .buttonStyle(SermonMiniPillButtonStyle(isFilled: false, tint: .red))
            if selectedNodes.contains(where: { isMainRoot($0) }) {
                Text("선택에 루트 노드가 포함돼 있습니다 — 루트는 삭제되지 않고 나머지만 삭제됩니다.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()
            Text("도형 색상 일괄 적용").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            colorSwatchRow(selected: representative?.color ?? .navy) { color in
                applyToSelection(selectedNodes) { $0.color = color }
            }
            Text("도형 모양 일괄 적용").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 2)
            HStack(spacing: 6) {
                ForEach(MindMapNodeShape.allCases, id: \.self) { shape in
                    Button {
                        applyToSelection(selectedNodes) { $0.shape = shape }
                    } label: {
                        Text(shapeName(shape))
                    }
                    .buttonStyle(SermonMiniPillButtonStyle(isFilled: false, tint: accent))
                }
            }

            Divider()
            Text("글자 크기 일괄 적용").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            if let representative {
                // 대표(첫 번째) 노드의 값을 보여주고, 움직이면 선택 전체에 같은 크기를 적용한다.
                StyleValueSlider(
                    title: "제목",
                    range: 10...40,
                    step: 1,
                    fractionDigits: 0,
                    value: representative.resolvedFontSize
                ) { newValue in
                    applyToSelection(selectedNodes) { $0.setFontSize(newValue) }
                }
                .id(representative.persistentModelID)
            }

            Divider()
            Text("테두리 스타일 일괄 적용").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(MindMapBorderStyle.allCases, id: \.self) { style in
                    Button {
                        applyToSelection(selectedNodes) { $0.borderStyle = style }
                    } label: {
                        Text(borderStyleName(style))
                    }
                    .buttonStyle(SermonMiniPillButtonStyle(isFilled: false, tint: accent))
                }
            }
            Text("테두리 색상 일괄 적용").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 2)
            colorSwatchRow(selected: representative?.resolvedBorderColor ?? .navy) { color in
                applyToSelection(selectedNodes) { $0.borderColor = color }
            }

            Divider()
            Text("선 색상 일괄 적용").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            colorSwatchRow(selected: representative?.resolvedLineColor ?? .navy) { color in
                applyToSelection(selectedNodes) { $0.lineColor = color }
            }
            Text("선 스타일 일괄 적용").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 2)
            HStack(spacing: 6) {
                ForEach(MindMapLineStyle.allCases, id: \.self) { style in
                    Button {
                        applyToSelection(selectedNodes) { $0.lineStyle = style }
                    } label: {
                        Text(lineStyleShortName(style))
                    }
                    .buttonStyle(SermonMiniPillButtonStyle(isFilled: false, tint: accent))
                }
            }
            Text("선 옅어짐 일괄 적용").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 2)
            HStack(spacing: 6) {
                Button {
                    applyToSelection(selectedNodes) { $0.lineFadeByDepth = true }
                } label: {
                    Text("깊이별 옅게")
                }
                .buttonStyle(SermonMiniPillButtonStyle(isFilled: false, tint: accent))
                Button {
                    applyToSelection(selectedNodes) { $0.lineFadeByDepth = false }
                } label: {
                    Text("옅어짐 끄기")
                }
                .buttonStyle(SermonMiniPillButtonStyle(isFilled: false, tint: accent))
            }
            pathTypeControl
        }
    }

    // MARK: - 경로 종류 (마인드맵 전체에 하나)

    /// 마인드맵 전체에 적용되는 경로 종류 설정. 저장은 노드별 `pathType`에 하되 항상 같은 값으로 맞춘다.
    private var pathTypeControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            styleFieldLabel("경로 종류").padding(.top, 6)
            Picker("경로 종류", selection: Binding(
                get: { currentPathType },
                set: { newValue in setAllPathTypes(newValue) }
            )) {
                Text("곡선").tag(MindMapPathType.bezier)
                Text("꺾은선").tag(MindMapPathType.elbow)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            Text("모든 경로에 한꺼번에 적용됩니다(곡선과 꺾은선이 섞이지 않습니다).")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// 지금 마인드맵의 경로 종류. 정상이면 모든 노드가 같은 값이지만, 섞여 있는 데이터는
    /// 선이 있는 노드 중 다수결(동수면 곡선)로 정한다.
    private var currentPathType: MindMapPathType {
        let edgeNodes = nodes.filter { $0.parent != nil }
        let elbowCount = edgeNodes.filter { $0.pathType == .elbow }.count
        return elbowCount * 2 > edgeNodes.count ? .elbow : .bezier
    }

    private func setAllPathTypes(_ type: MindMapPathType) {
        for node in nodes where node.pathType != type {
            node.pathType = type
            node.updatedAt = .now
        }
    }

    /// 선택된 노드 전체에 같은 변경을 적용하는 공용 헬퍼. `updatedAt`도 함께 갱신한다.
    private func applyToSelection(_ targets: [MindMapNode], _ update: (MindMapNode) -> Void) {
        for node in targets {
            update(node)
            node.updatedAt = .now
        }
    }

    /// 도형 스타일 섹션 — 색상(6종)과 모양을 독립적으로 고른다.
    /// `node.color`/`node.shape`만 읽고 쓰며 테두리·선 속성은 참조하지 않는다.
    /// `LazyVGrid` 안에 `ForEach`를 중첩하면 셀이 일부만 렌더링되어, 단일 레벨 `ForEach` 패턴(`colorSwatchRow`)을 쓴다.
    private func shapeStyleSection(_ node: MindMapNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            styleSectionTitle("도형 스타일")
            styleFieldLabel("색상")
            colorSwatchRow(selected: node.color) { color in
                node.color = color
                node.updatedAt = .now
            }
            styleFieldLabel("모양").padding(.top, 2)
            Picker("도형 모양", selection: Binding(
                get: { node.shape },
                set: { newValue in
                    node.shape = newValue
                    node.updatedAt = .now
                }
            )) {
                ForEach(MindMapNodeShape.allCases, id: \.self) { shape in
                    Text(shapeName(shape)).tag(shape)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
        }
    }

    /// 글자 크기 섹션 — 노드 안 제목 글자 크기(10~40pt). 설명 글자는 제목의 약 0.72배로 따라간다.
    /// 설명이 있는 노드는 제목 영역 높이도 비율대로 함께 바뀐다(`MindMapNode.setFontSize`).
    private func fontStyleSection(_ node: MindMapNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            styleSectionTitle("글자 크기")
            StyleValueSlider(
                title: "제목",
                range: 10...40,
                step: 1,
                fractionDigits: 0,
                value: node.resolvedFontSize
            ) { newValue in
                node.setFontSize(newValue)
            }
            .id(node.persistentModelID)
            if node.descriptionText != nil {
                Text("설명 글자: \(Int(node.descriptionFontSize))pt (제목의 약 72%)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if node.fontSize != nil {
                Button {
                    node.resetFontSize()
                } label: {
                    Text("기본 크기로")
                }
                .buttonStyle(SermonMiniPillButtonStyle(isFilled: false, tint: accent))
            }
        }
    }

    // 도형/테두리/선 스타일 섹션이 공유하는 제목·소제목 (색상 → 모양 → 세부 순서로 통일).
    private func styleSectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
    }

    private func styleFieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    /// 테두리 스타일 섹션. `borderStyle`/`borderColor`/`borderThickness`/`borderDashSpacing`만 읽고 쓰며
    /// 도형 색(`node.color`)은 건드리지 않는다. "없음"(`.solid`)이면 색·세부 조절을 흐리게 비활성화한다(레이아웃 유지).
    private func borderStyleSection(_ node: MindMapNode) -> some View {
        let hasBorder = node.borderStyle != .solid
        return VStack(alignment: .leading, spacing: 8) {
            styleSectionTitle("테두리 스타일")
            styleFieldLabel("색상")
            colorSwatchRow(selected: node.resolvedBorderColor) { color in
                node.borderColor = color
                node.updatedAt = .now
            }
            .disabled(!hasBorder)
            .opacity(hasBorder ? 1 : 0.4)
            styleFieldLabel("모양").padding(.top, 2)
            Picker("테두리 모양", selection: Binding(
                get: { node.borderStyle },
                set: { newValue in
                    node.borderStyle = newValue
                    node.updatedAt = .now
                }
            )) {
                Text(borderStyleName(.solid)).tag(MindMapBorderStyle.solid)
                Text(borderStyleName(.outline)).tag(MindMapBorderStyle.outline)
                Text(borderStyleName(.dashed)).tag(MindMapBorderStyle.dashed)
                Text(borderStyleName(.bottomAccent)).tag(MindMapBorderStyle.bottomAccent)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)

            // 스타일별 세부 조절: 실선=두께, 점선=점 간격. 하단 강조는 조절값이 없다(고정 4pt 막대).
            switch node.borderStyle {
            case .outline:
                StyleValueSlider(
                    title: "두께",
                    range: 1...6,
                    step: 0.5,
                    fractionDigits: 1,
                    value: node.resolvedBorderThickness
                ) { newValue in
                    node.borderThickness = newValue
                    node.updatedAt = .now
                }
                .id(node.persistentModelID)
                .padding(.top, 4)
            case .dashed:
                StyleValueSlider(
                    title: "점 간격",
                    range: 2...20,
                    step: 1,
                    fractionDigits: 0,
                    value: node.resolvedBorderDashSpacing
                ) { newValue in
                    node.borderDashSpacing = newValue
                    node.updatedAt = .now
                }
                .id(node.persistentModelID)
                .padding(.top, 4)
            case .solid, .bottomAccent:
                EmptyView()
            }
        }
    }

    /// 6색 팔레트 중 하나를 고르는 공용 스와치 행 — 테두리 색상·선 색상 선택기가 같은 모양을 공유한다.
    @ViewBuilder
    private func colorSwatchRow(selected: MindMapNodeColor, onSelect: @escaping (MindMapNodeColor) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(MindMapNodeColor.allCases, id: \.self) { color in
                Button {
                    onSelect(color)
                } label: {
                    Circle()
                        .fill(resolvedColor(color))
                        .frame(width: 22, height: 22)
                        // 아이보리처럼 밝은 색이 밝은 배경에서 사라져 보이지 않도록 옅은 윤곽.
                        .overlay(Circle().stroke(Color.secondary.opacity(0.35), lineWidth: 0.5))
                        .overlay(Circle().stroke(accent, lineWidth: selected == color ? 2.5 : 0))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 선 스타일 섹션 — 색상(6색)과 스타일(점점 얇게/실선/점선/화살표)을 독립적으로 고른다.
    /// 테두리(`borderStyleSection`)와는 서로 참조하지 않는 별개 축이다.
    private func lineStyleSection(_ node: MindMapNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            styleSectionTitle("선 스타일")
            if node.parent == nil {
                Text("부모로 이어지는 선이 없는 노드입니다(루트 노드이거나 연결이 끊긴 노드).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                styleFieldLabel("색상")
                colorSwatchRow(selected: node.resolvedLineColor) { color in
                    node.lineColor = color
                    node.updatedAt = .now
                }

                styleFieldLabel("모양").padding(.top, 2)
                Picker("선 모양", selection: Binding(
                    get: { node.resolvedLineStyle },
                    set: { newValue in
                        node.lineStyle = newValue
                        node.updatedAt = .now
                    }
                )) {
                    Text("점점 얇게").tag(MindMapLineStyle.taper)
                    Text("실선").tag(MindMapLineStyle.solid)
                    Text("점선").tag(MindMapLineStyle.dashed)
                    Text("화살표").tag(MindMapLineStyle.arrow)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)

                // 스타일별 세부 조절: 실선=두께, 점선=점 간격, 화살표=모양.
                switch node.resolvedLineStyle {
                case .solid:
                    StyleValueSlider(
                        title: "두께",
                        range: 1...6,
                        step: 0.5,
                        fractionDigits: 1,
                        value: node.lineThickness
                    ) { newValue in
                        node.lineThickness = newValue
                        node.updatedAt = .now
                    }
                    .id(node.persistentModelID)
                    .padding(.top, 4)
                case .dashed:
                    StyleValueSlider(
                        title: "점 간격",
                        range: 2...20,
                        step: 1,
                        fractionDigits: 0,
                        value: node.dashSpacing
                    ) { newValue in
                        node.dashSpacing = newValue
                        node.updatedAt = .now
                    }
                    .id(node.persistentModelID)
                    .padding(.top, 4)
                case .arrow:
                    VStack(alignment: .leading, spacing: 6) {
                        Text("화살표 모양")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            ForEach(MindMapArrowShape.allCases, id: \.self) { shape in
                                Button {
                                    node.arrowShape = shape
                                    node.updatedAt = .now
                                } label: {
                                    Text(arrowShapeName(shape))
                                }
                                .buttonStyle(SermonMiniPillButtonStyle(isFilled: node.resolvedArrowShape == shape, tint: accent))
                            }
                        }
                    }
                    .padding(.top, 4)
                case .taper:
                    // 자식 선은 부모 선이 끝난 굵기에서 이어 시작하고, 루트에서 4단계째 선부터는 실선이다.
                    VStack(alignment: .leading, spacing: 6) {
                        if taperInheritsParent(node) {
                            Text("부모 선도 '점점 얇게'라서, 부모 선이 끝난 굵기에서 이어 시작합니다.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            // 실선의 `lineThickness`(1~6pt)와 범위가 달라 별도 값(`taperThickness`, 6~20pt)을 쓴다.
                            StyleValueSlider(
                                title: "시작 두께",
                                range: 6...20,
                                step: 1,
                                fractionDigits: 0,
                                value: node.resolvedTaperThickness
                            ) { newValue in
                                node.taperThickness = newValue
                                node.updatedAt = .now
                            }
                            .id(node.persistentModelID)
                        }
                        Text("선마다 끝이 시작의 60%까지 얇아지고, 루트에서 4단계째 선부터는 굵기가 일정한 실선입니다.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }

                pathTypeControl

                // 모든 선 스타일에서 켜고 끌 수 있다.
                styleFieldLabel("깊이별 옅어짐").padding(.top, 6)
                Toggle("하위로 갈수록 점점 옅게", isOn: Binding(
                    get: { node.resolvedLineFadeByDepth },
                    set: { newValue in
                        node.lineFadeByDepth = newValue
                        node.updatedAt = .now
                    }
                ))
                .font(.caption)
                .toggleStyle(.switch)
                .controlSize(.small)
                Text("1단계 100% · 2단계 75% · 3단계 55% · 4단계 이후 40%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 노드 추가/삭제

    private func addRootNode() {
        let node = MindMapNode(
            text: "메인주제",
            positionX: Double(Self.canvasSize.width / 2),
            positionY: Double(Self.canvasSize.height / 2),
            width: Self.defaultNodeWidth,
            height: Self.defaultNodeHeight,
            color: .navy,
            shape: .rounded,
            lineStyle: .taper,
            sermon: sermon
        )
        // 기본 선 스타일은 "점점 얇게"(시작 12pt) + 깊이별 옅어짐. 루트는 부모 선이 없지만,
        // 나중에 다른 노드의 자식으로 옮겨도 같은 기본값을 쓰도록 맞춰 둔다.
        node.taperThickness = 12
        node.lineFadeByDepth = true
        modelContext.insert(node)
        selectedNodeIDs = [node.persistentModelID]
        // `emptyState`에서 `canvasArea`로 막 전환되는 중이라 `scrollPosition`이 아직 스크롤 뷰에 연결되지 않았을 수 있다.
        // 그래서 바로 이동하지 않고 대상 ID만 남겨, `canvasArea`가 나타난 뒤(`.task`) 이동한다(`centerOnPendingNodeIfNeeded()`).
        pendingCenterNodeID = node.persistentModelID
    }

    /// 새 자식 노드를 부모 오른쪽에, 형제 수에 따라 세로로 어긋나게 배치해 기존 형제와 겹치지 않게 한다.
    /// 정교한 자동 레이아웃(겹침 회피 등)은 없으며 위치는 사용자가 드래그로 조정한다.
    private func addChild(to parent: MindMapNode) {
        let siblingIndex = (parent.children ?? []).count
        let node = MindMapNode(
            text: "새 노드",
            positionX: parent.positionX + 220,
            positionY: parent.positionY + Double(siblingIndex) * 90,
            width: Self.defaultNodeWidth,
            height: Self.defaultNodeHeight,
            color: .gold,
            shape: .rounded,
            sermon: sermon,
            parent: parent
        )
        // 가장 최근에 바꾼 도형·테두리·선 스타일(`MindMapStyleTemplate`)을 새 노드에 입힌다.
        // 경로 종류는 마인드맵 전체 설정이라 현재 값을 따른다.
        MindMapStyleTemplate.load().apply(to: node)
        node.pathType = currentPathType
        modelContext.insert(node)
        selectedNodeIDs = [node.persistentModelID]
        editingNodeID = nil
        editingDescriptionNodeID = nil
    }

    /// 노드 삭제. 자식은 `MindMapNode.children`의 `deleteRule: .nullify`(MindMaps.swift 참고)로 연결만 끊긴 채 남으므로 직접 순회하지 않는다.
    ///
    /// 주 루트 삭제는 여기서 막는다 — 이 화면은 루트가 있다는 전제(뷰포트 중앙 정렬, `depth(of:)`,
    /// `SermonMindMapExporter`의 깊이 계산 등)로 동작한다. `selectionSection`의 버튼 비활성화와 별개로
    /// 다른 경로로 호출돼도 안전하도록 방어한다.
    private func deleteNode(_ node: MindMapNode) {
        guard !isMainRoot(node) else { return }
        selectedNodeIDs.remove(node.persistentModelID)
        if editingNodeID == node.persistentModelID {
            editingNodeID = nil
        }
        if editingDescriptionNodeID == node.persistentModelID {
            editingDescriptionNodeID = nil
        }
        modelContext.delete(node)
    }

    private func pasteStyle(onto node: MindMapNode) {
        guard let style = copiedStyle else { return }
        let targets: [MindMapNode]
        if selectedNodeIDs.count > 1, selectedNodeIDs.contains(node.persistentModelID) {
            targets = selectedNodes
        } else {
            targets = [node]
        }
        applyToSelection(targets) { style.apply(to: $0) }
    }

    /// 삭제가 금지된 "주 루트" — 부모 없는 노드 중 가장 먼저 만든 노드.
    /// 선 끊기로 부모 없는 노드가 여러 개일 수 있어, 보호는 주 루트에만 적용한다.
    /// `SermonMindMapExporter.makePlan`도 같은 기준으로 제목 노드를 고른다.
    private func isMainRoot(_ node: MindMapNode) -> Bool {
        guard node.parent == nil, let main = mainRootNode else { return false }
        return main.persistentModelID == node.persistentModelID
    }

    /// 주 루트 — 부모 없는 노드 중 가장 먼저 만든 노드.
    private var mainRootNode: MindMapNode? {
        nodes.filter { $0.parent == nil }.min(by: { $0.createdAt < $1.createdAt })
    }

    /// 부모를 끝까지 따라 올라간 맨 위 노드(자기 자신이 부모가 없으면 자기 자신).
    /// 순환 참조 방어용 상한(500)을 둔다.
    private func topAncestor(of node: MindMapNode) -> MindMapNode {
        var current = node
        var steps = 0
        while let parent = current.parent, steps < 500 {
            current = parent
            steps += 1
        }
        return current
    }

    /// 주 루트이거나 주 루트에 이어져 있는 노드인지 — 끊겨 나간(고아) 서브트리의 노드는 false.
    private func isRootConnected(_ node: MindMapNode) -> Bool {
        guard let main = mainRootNode else { return false }
        return topAncestor(of: node).persistentModelID == main.persistentModelID
    }

    /// 새 선(부모 → 자식)을 잇는 모든 동작(노드 위·아래 버튼, 선 옮기기)이 공유하는 허용 규칙:
    ///   1) 부모가 될 노드는 주 루트이거나 주 루트와 이어져 있어야 한다.
    ///   2) 자식이 될 노드는 부모가 아직 없어야 한다(주 루트는 부모를 가질 수 없다).
    ///   3) 순환이 생기면 막는다(자기 자신, 또는 자식의 하위를 부모로 삼는 경우).
    private func canConnect(parent: MindMapNode, child: MindMapNode) -> Bool {
        guard parent.persistentModelID != child.persistentModelID else { return false }
        guard child.parent == nil, !isMainRoot(child) else { return false }
        guard isRootConnected(parent) else { return false }
        return !isSameOrDescendant(parent, of: child)
    }

    /// 선택된 노드를 모두 삭제한다. `deleteNode(_:)`를 재사용해, 선택에 주 루트가 섞여 있어도 그것만 조용히 건너뛴다.
    private func deleteSelectedNodes() {
        for node in selectedNodes {
            deleteNode(node)
        }
    }

    // MARK: - 설교문 적용 (마인드맵 → 설교문 본문 끝에 추가)

    /// 마인드맵 트리를 설교문 텍스트로 변환해 본문 끝에 추가할 계획을 만들고 확인을 받는다. 변환 규칙과 저장 포맷은 `SermonMindMapExporter`가 맡는다.
    /// 다시 실행하면 매번 또 추가되는 되돌리기 어려운 작업이라 확인 창을 거친다.
    private func requestExport() {
        let plan = SermonMindMapExporter.makePlan(from: nodes)
        guard plan.title != nil || !plan.paragraphs.isEmpty else {
            exportResultMessage = "설교문으로 옮길 내용이 없습니다. 노드에 텍스트를 입력해 주세요."
            showExportResult = true
            return
        }
        exportPlan = plan
        showExportConfirm = true
    }

    /// 확인 알림 본문 — 계획이 없으면(있을 수 없는 상태) 빈 문자열.
    private var exportConfirmText: String {
        guard let plan = exportPlan else { return "" }
        return exportConfirmMessage(plan)
    }

    /// "추가" 버튼 — 알림이 뜬 시점의 계획을 실행한다(닫힘 애니메이션 중 본문이
    /// 빈 글자로 깜빡이지 않도록 `exportPlan`은 비우지 않는다).
    private func confirmExport() {
        guard let plan = exportPlan else { return }
        performExport(plan)
    }

    private func exportConfirmMessage(_ plan: SermonMindMapExporter.Plan) -> String {
        var lines: [String] = []
        if let title = plan.title {
            lines.append("설교 제목을 “\(title)”(으)로 설정하고,")
        }
        lines.append("\(plan.paragraphs.count)개 문단을 설교문 본문 끝에 추가합니다.")
        lines.append("다시 적용하면 또 추가됩니다.")
        lines.append("이 설교의 편집 화면이 열려 있으면 입력한 내용을 저장한 뒤 자동으로 닫히고, 내 설교 목록에서 이 설교가 선택됩니다.")
        return lines.joined(separator: "\n")
    }

    /// 계획을 본문에 적용한다. 편집기는 닫힐 때 자기가 들고 있던 본문 사본을 저장(`onDisappear → save()`)하므로
    /// 그냥 닫으면 방금 적용한 내용을 옛 본문으로 덮어쓴다. 그래서 순서가 중요하다:
    ///   1) `.sermonContentFlushRequested` — 열린 편집기가 지금 입력한 본문을 즉시 저장(알림은 동기 전달이라 호출이 돌아오기 전에 저장이 끝난다),
    ///   2) 최신 본문 뒤에 마인드맵 문단을 추가하고 저장,
    ///   3) `.sermonContentReplacedExternally` — 편집기는 저장 없이 스스로 닫히고, 내 설교 목록은 이 설교를 선택해 모임 리스트(`SermonDetailView`)를 보인다.
    /// 마인드맵 창은 그대로 둔다.
    private func performExport(_ plan: SermonMindMapExporter.Plan) {
        let sermonID = sermon.persistentModelID
        SermonExternalContentChange.post(.sermonContentFlushRequested, sermonID: sermonID)
        SermonMindMapExporter.apply(plan, to: sermon, settings: settings)
        try? modelContext.save()
        // `SermonEditorView.save()`와 같은 검색/성경구절 재인덱싱.
        BibleReferenceIndexingService.reindexSermon(sermon, context: modelContext)
        SermonExternalContentChange.post(.sermonContentReplacedExternally, sermonID: sermonID)
        exportResultMessage = "설교문에 \(plan.paragraphs.count)개 문단을 추가했습니다."
        showExportResult = true
    }

    // MARK: - 색상/이름 매핑 (표현은 이 화면의 몫 — MindMaps.swift 상단 주석 참고)

    /// 책장 아이보리 #F7F0E2 (`BibleSlideColorTheme`의 "서재 아이보리" 배경과 같은 값).
    private static let shelfIvory = Color(red: 247.0 / 255.0, green: 240.0 / 255.0, blue: 226.0 / 255.0)

    private func resolvedColor(_ color: MindMapNodeColor) -> Color {
        switch color {
        case .navy:
            return isDarkSurface ? JBCHCategoryPalette.navyOnDark : JBCHCategoryPalette.navy
        case .gold:
            // 마인드맵 전용 금색 #D4A017. 앱의 다른 화면 금색(`JBCHCategoryPalette.gold`/`AccentColor`)은 건드리지 않는다.
            // 밝은 색이라 글씨색은 짙은 색을 쓴다(`MindMapNodeShapeView.foregroundColor`). 라이트/다크 배경 공용 단일 값.
            return Color(red: 212.0 / 255.0, green: 160.0 / 255.0, blue: 23.0 / 255.0)
        case .wood:
            return isDarkSurface ? JBCHCategoryPalette.woodOnDark : JBCHCategoryPalette.wood
        case .teal:
            return isDarkSurface ? JBCHCategoryPalette.slateTealOnDark : JBCHCategoryPalette.slateTeal
        case .wine:
            return isDarkSurface ? JBCHCategoryPalette.wineOnDark : JBCHCategoryPalette.wine
        case .slate:
            // 저장 값(rawValue "slate")은 그대로 두고(기존 노드 보존) 화면에 그리는 색만 책장 아이보리로 쓴다.
            // 밝은 색이라 라이트/다크 공용이며 글씨는 짙은 잉크색(`MindMapNodeShapeView.foregroundColor`).
            // 밝은 배경 위에서는 아이보리 "선/테두리"의 대비가 낮아 잘 안 보일 수 있다.
            return Self.shelfIvory
        }
    }

    /// 도형 모양의 표시 이름 — `shapeStyleSection` 참고.
    private func shapeName(_ shape: MindMapNodeShape) -> String {
        switch shape {
        case .rounded: return "라운드"
        case .rect: return "사각형"
        }
    }

    private func borderStyleName(_ style: MindMapBorderStyle) -> String {
        switch style {
        // `solid`는 별도 테두리 선을 그리지 않으므로 "없음"으로 표시한다.
        case .solid: return "없음"
        case .dashed: return "점선"
        case .outline: return "실선"
        case .bottomAccent: return "하단 강조"
        }
    }

    private func arrowShapeName(_ shape: MindMapArrowShape) -> String {
        switch shape {
        case .open: return "열린 화살표"
        case .closedTriangle: return "닫힌 삼각형"
        case .diamond: return "다이아몬드"
        case .circle: return "원"
        }
    }

    /// `bulkActionsSection`의 선 스타일 버튼 라벨 — `lineStyleSection` Picker 안의 문자열과 같은 이름.
    private func lineStyleShortName(_ style: MindMapLineStyle) -> String {
        switch style {
        case .solid: return "실선"
        case .dashed: return "점선"
        case .arrow: return "화살표"
        case .taper: return "점점 얇게"
        }
    }
}

// MARK: - 노드 도형 뷰(드래그 이동/리사이즈/더블탭 텍스트 편집)

/// 노드 위·아래 중앙의 "선 연결 버튼" 종류 — 위 버튼은 이 노드의 부모를, 아래 버튼은 자식을 잇는다.
fileprivate enum MindMapLinkHandle {
    case top
    case bottom
}

private struct MindMapNodeShapeView: View {
    let node: MindMapNode
    let isSelected: Bool
    let isEditing: Bool
    /// 하단 "설명" 영역(우클릭 메뉴 → 설명 추가)을 편집 중인지.
    let isEditingDescription: Bool
    let fillColor: Color
    /// 테두리(점선/외곽선/하단강조) 전용 색 — 도형 색(`fillColor`)과 독립적으로 전달받는다
    /// (`MindMapNode.borderColor`).
    let borderColor: Color
    let accent: Color
    let canvasSpace: String
    /// 현재 확대/축소 배율(`SermonMindMapView.zoomScale`). 도형은 `node.width/height * scale`로 그리고,
    /// 제스처가 보고하는 화면 값은 이 배율로 나눠 모델 좌표(배율 1.0 기준)로 되돌린다.
    let scale: CGFloat
    let onSelect: () -> Void
    let onBeginEdit: () -> Void
    let onEndEdit: () -> Void
    /// 하단 설명 영역 편집 시작/종료 — 더블클릭한 위치가 노드의 아래쪽 절반이고
    /// 설명이 있을 때만 `onBeginEditDescription`이 불린다.
    let onBeginEditDescription: () -> Void
    let onEndEditDescription: () -> Void
    /// 이 뷰는 자기 이동량만 부모에게 보고하고, 몇 개의 노드에 적용할지(단독/다중 선택)는
    /// 부모(`SermonMindMapView`)가 결정한다 — 형제 노드를 몰라도 되게 하기 위함.
    let onDragBegin: () -> Void
    let onDragChanged: (Double, Double) -> Void
    let onDragEnded: () -> Void
    /// 연결 버튼 표시 여부(부모가 "이 노드 하나만 선택됨 + 편집 중 아님"일 때만 true)와 버튼 드래그 중
    /// 위치 보고(캔버스 좌표). 부모/자식 결정과 연결 허용 여부는 부모 뷰의 몫.
    let showsLinkHandles: Bool
    let onLinkDragChanged: (MindMapLinkHandle, CGPoint) -> Void
    let onLinkDragEnded: (MindMapLinkHandle, CGPoint) -> Void

    /// 리사이즈 드래그 시작 시점의 크기 — `DragGesture`의 `translation`은 시작점 기준 누적값이라
    /// 시작 크기에 더해야 한다.
    @State private var resizeStartSize: CGSize?
    /// 이동 제스처가 진행 중인지 — 첫 프레임에만 `onDragBegin()`을 호출하기 위한 표시.
    @State private var isDragging = false
    /// 이번 누름에서 이미 선택을 알렸는지(`nodeGesture` 참고).
    @State private var didSelectOnPress = false
    /// 직전 제자리 클릭이 끝난 시각 — 더블클릭을 직접 판정하기 위한 값.
    @State private var lastTapDate: Date?

    /// 글자색 — 채움은 항상 `fillColor`이고 테두리는 그 위에 덧그리기만 하므로 기본은 흰색.
    /// 밝은 채움은 짙은 색으로 예외 처리한다: 금색(#D4A017, 흰 글씨 대비 약 2.4:1)과 책장 아이보리(`.slate`, #F7F0E2).
    /// 판정 기준은 도형 채움색(`node.color`)이며 테두리 색과 무관하다.
    private var foregroundColor: Color {
        switch node.color {
        case .gold: return Color(white: 28.0 / 255.0)
        case .slate: return Color(red: 36.0 / 255.0, green: 26.0 / 255.0, blue: 16.0 / 255.0)
        case .navy, .wood, .teal, .wine: return .white
        }
    }

    var body: some View {
        ZStack {
            shapeBackground
            contentLayout
        }
        .frame(width: CGFloat(node.width) * scale, height: CGFloat(node.height) * scale)
        .overlay {
            if isSelected {
                selectionRing
            }
        }
        .overlay(alignment: .bottomTrailing) {
            resizeHandle
        }
        // 위·아래 중앙 선 연결 버튼 — 노드 테두리에 걸치도록 반쯤 바깥으로 내민다.
        .overlay(alignment: .top) {
            if showsLinkHandles {
                linkHandle(.top)
                    .offset(y: -9)
            }
        }
        .overlay(alignment: .bottom) {
            if showsLinkHandles {
                linkHandle(.bottom)
                    .offset(y: 9)
            }
        }
        .contentShape(Rectangle())
        // 이동 거리 0인 `DragGesture` 하나로 (1) 누르는 즉시 선택, (2) 3pt 이상 움직이면 이동 시작,
        // (3) 움직임 없이 떼면 클릭으로 보고 직전 클릭과의 간격으로 더블클릭을 직접 판정한다.
        // 제스처를 겹쳐 붙이면 안쪽(자식) 제스처가 우선해 이동이 인식되지 않고, `onTapGesture(count: 2)`는 클릭 지연을 만든다.
        // 편집 중에는 `.subviews` 마스크로 꺼서 TextField의 커서 이동·글자 선택이 가로채이지 않게 한다.
        .gesture(nodeGesture, including: (isEditing || isEditingDescription) ? .subviews : .all)
    }

    private var nodeGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasSpace))
            .onChanged { value in
                if !didSelectOnPress {
                    didSelectOnPress = true
                    onSelect()
                }
                if !isDragging {
                    let moved = hypot(value.translation.width, value.translation.height)
                    guard moved >= 3 else { return }
                    isDragging = true
                    onDragBegin()
                }
                // `translation`은 시작점 기준 누적 이동량(캔버스 좌표, 배율 반영)이라 배율로 나눠 모델 좌표 델타로 보고한다.
                onDragChanged(Double(value.translation.width / scale), Double(value.translation.height / scale))
            }
            .onEnded { value in
                didSelectOnPress = false
                if isDragging {
                    isDragging = false
                    lastTapDate = nil
                    onDragEnded()
                    return
                }
                // 움직임 없이 뗐다 = 클릭. 누름 시점의 선택을 놓쳤어도 여기서 다시 선택한다(멱등).
                onSelect()
                let now = Date()
                if let last = lastTapDate, now.timeIntervalSince(last) < 0.35 {
                    lastTapDate = nil
                    // 더블클릭 위치가 노드 아래쪽 절반이고 설명 영역이 있으면 설명 편집, 아니면 제목 편집.
                    // `value.location`은 캔버스 좌표라 노드 위쪽 가장자리 y를 빼 노드 안 좌표로 바꾼다(클릭이라 노드가 움직이지 않았다).
                    let topEdge = (CGFloat(node.positionY) - CGFloat(node.height) / 2) * scale
                    let localY = value.location.y - topEdge
                    if node.descriptionText != nil, localY > CGFloat(node.resolvedLabelHeight) * scale {
                        onBeginEditDescription()
                    } else {
                        onBeginEdit()
                    }
                } else {
                    lastTapDate = now
                }
            }
    }

    /// 노드 안 내용 — 설명이 없으면 제목만, 있으면 위는 제목·아래는 설명으로 가로 분할.
    @ViewBuilder
    private var contentLayout: some View {
        if let description = node.descriptionText {
            // 제목(라벨) 영역은 고정 높이(`resolvedLabelHeight`)이고 나머지가 전부 설명 영역이다 — 노드 크기를 키우면 설명만 늘어난다.
            VStack(spacing: 0) {
                titleView(lineLimit: 2)
                    .frame(maxWidth: .infinity)
                    .frame(height: CGFloat(node.resolvedLabelHeight) * scale)
                Rectangle()
                    .fill(foregroundColor.opacity(0.45))
                    .frame(height: 1)
                    .padding(.horizontal, 8)
                descriptionView(description)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            titleView(lineLimit: 4)
        }
    }

    /// 제목 글꼴 — 크기를 지정하지 않았으면 예전과 같은 `.title2` 굵게.
    private var titleFont: Font {
        node.fontSize.map { Font.system(size: CGFloat($0), weight: .bold) } ?? Font.title2.weight(.bold)
    }

    /// 설명 글꼴 — 크기를 지정하지 않았으면 예전과 같은 `.callout`, 지정했으면 제목 크기의 0.72배(`MindMapNode.descriptionFontSize`).
    private var descriptionFont: Font {
        node.fontSize.map { _ in Font.system(size: CGFloat(node.descriptionFontSize)) } ?? Font.callout
    }

    /// 설명 영역에 들어가는 줄 수 — 영역이 커지면 더 많은 줄을 보여준다(예전에는 3줄 고정이라 키워도 빈 공간만 늘었다).
    /// 영역 높이 = 노드 높이 − 제목 영역 − 구분선 1pt, 위아래 여백 12pt, 줄 높이는 글자 크기의 약 1.3배.
    private var descriptionLineLimit: Int {
        let area = node.height - node.resolvedLabelHeight - 1 - 12
        return max(1, Int(area / (node.descriptionFontSize * 1.3)))
    }

    /// 노드 제목 — 편집 중이면 TextField, 아니면 Text.
    @ViewBuilder
    private func titleView(lineLimit: Int) -> some View {
        if isEditing {
            TextField(
                "",
                text: Binding(
                    get: { node.text },
                    set: { node.text = $0 }
                ),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(titleFont)
            .foregroundStyle(foregroundColor)
            .padding(8)
            .onSubmit { onEndEdit() }
        } else {
            Text(node.text.isEmpty ? "새 노드" : node.text)
                .font(titleFont)
                .foregroundStyle(foregroundColor)
                .multilineTextAlignment(.center)
                .lineLimit(lineLimit)
                .padding(8)
        }
    }

    /// 하단 설명 — 굵기 없는 일반체.
    @ViewBuilder
    private func descriptionView(_ description: String) -> some View {
        if isEditingDescription {
            TextField(
                "설명",
                text: Binding(
                    get: { node.descriptionText ?? "" },
                    set: { node.descriptionText = $0 }
                ),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(descriptionFont)
            .foregroundStyle(foregroundColor)
            .padding(6)
            .onSubmit { onEndEditDescription() }
        } else {
            Text(description.isEmpty ? "설명" : description)
                .font(descriptionFont)
                .foregroundStyle(foregroundColor.opacity(description.isEmpty ? 0.6 : 1))
                .multilineTextAlignment(.center)
                .lineLimit(descriptionLineLimit)
                .padding(6)
        }
    }

    // 라운드/사각 두 도형은 `styledBackground(_:)`가 제네릭(`S: Shape`) 하나로 공유한다.
    @ViewBuilder
    private var shapeBackground: some View {
        switch node.shape {
        case .rounded: styledBackground(RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .rect: styledBackground(Rectangle())
        }
    }

    /// 도형 채움은 항상 `fillColor`만 쓰고 테두리는 그 위 오버레이(`borderOverlay`)로만 그려,
    /// 테두리 스타일이 도형 색에 영향을 주지 않게 한다.
    private func styledBackground<S: Shape>(_ shape: S) -> some View {
        shape
            .fill(fillColor)
            .overlay { borderOverlay(shape) }
    }

    /// 테두리 오버레이 — 실선=두께, 점선=점 간격, 하단 강조=고정 4pt 막대.
    /// 값이 없는 과거 노드는 `resolvedBorder*`가 기본값(두께 2, 점 간격 4)을 준다.
    @ViewBuilder
    private func borderOverlay<S: Shape>(_ shape: S) -> some View {
        switch node.borderStyle {
        case .solid:
            EmptyView()
        case .outline:
            shape.stroke(borderColor, lineWidth: CGFloat(node.resolvedBorderThickness))
        case .dashed:
            shape.stroke(
                borderColor,
                style: StrokeStyle(
                    lineWidth: CGFloat(node.resolvedBorderThickness),
                    dash: [6, CGFloat(node.resolvedBorderDashSpacing)]
                )
            )
        case .bottomAccent:
            Color.clear
                .overlay(alignment: .bottom) {
                    Rectangle().fill(borderColor).frame(height: 4)
                }
                .clipShape(shape)
        }
    }

    /// 선택 표시 테두리 — 노드 모양(라운드/사각)에 맞춰 같은 모양으로 그린다.
    @ViewBuilder
    private var selectionRing: some View {
        // 선택 링은 노드 바깥으로 밀어 그려 노드 자신의 테두리를 가리지 않는다. 노드 테두리는 가장자리를
        // 중심으로 두께/2씩 그려지므로(실선·점선일 때만 바깥으로 나옴) 링 중심 = 테두리 바깥 끝 + 2pt 간격 + 링 두께/2.
        // 바깥으로 나간 만큼 모서리 반지름도 키워야 라운드 모양이 평행하게 유지된다.
        let ringWidth: CGFloat = 2
        let borderOutset: CGFloat = (node.borderStyle == .outline || node.borderStyle == .dashed)
            ? CGFloat(node.resolvedBorderThickness) / 2
            : 0
        let outset = borderOutset + 2 + ringWidth / 2
        switch node.shape {
        case .rounded:
            RoundedRectangle(cornerRadius: 14 + outset, style: .continuous)
                .stroke(accent, lineWidth: ringWidth)
                .padding(-outset)
        case .rect:
            Rectangle()
                .stroke(accent, lineWidth: ringWidth)
                .padding(-outset)
        }
    }

    /// 선 연결 버튼 — 끌어서 다른 노드 위에 놓으면 연결을 시도한다(허용 여부 판정은 부모
    /// 뷰). 손잡이는 배율에 맞춰 커지지 않는 고정 크기 UI(리사이즈 손잡이와 같은 방침).
    private func linkHandle(_ handle: MindMapLinkHandle) -> some View {
        Image(systemName: handle == .top ? "arrow.up" : "arrow.down")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Circle().fill(accent))
            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1))
            .contentShape(Circle())
            .help(handle == .top ? "끌어서 다른 노드 위에 놓으면 그 노드가 이 노드의 부모가 됩니다" : "끌어서 다른 노드 위에 놓으면 그 노드가 이 노드의 자식이 됩니다")
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named(canvasSpace))
                    .onChanged { value in onLinkDragChanged(handle, value.location) }
                    .onEnded { value in onLinkDragEnded(handle, value.location) }
            )
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .padding(5)
            .background(Circle().fill(accent))
            .offset(x: 8, y: 8)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .local)
                    .onChanged { value in
                        if resizeStartSize == nil {
                            resizeStartSize = CGSize(width: node.width, height: node.height)
                            // 이 필드가 생기기 전에 설명을 붙인 노드는 제목 영역이 "높이의 절반"이었다 — 크기를 바꾸기 시작하는 순간
                            // 지금 값으로 고정해 두어야 이후 높이 변화가 제목 영역으로 번지지 않는다.
                            if node.descriptionText != nil, node.labelHeight == nil {
                                node.labelHeight = node.height / 2
                            }
                        }
                        guard let start = resizeStartSize else { return }
                        // 핸들은 배율에 맞춰 커지지 않는 고정 크기 UI라 `.local` 이동량은 화면 픽셀 그대로다.
                        // 배율 1.0 기준 모델 크기 변화량으로 되돌리려면 배율로 나눈다.
                        node.width = max(80, Double(start.width) + Double(value.translation.width / scale))
                        // 설명이 있으면 제목 영역(고정) + 설명 최소 36pt 아래로는 줄이지 않는다.
                        let minHeight: Double = node.descriptionText != nil ? node.resolvedLabelHeight + 36 : 40
                        node.height = max(minHeight, Double(start.height) + Double(value.translation.height / scale))
                    }
                    .onEnded { _ in
                        resizeStartSize = nil
                        node.updatedAt = .now
                    }
            )
    }
}

/// 두께/점 간격 슬라이더 — 눈금 없는 연속 슬라이더를 로컬 `draft` 값으로 움직이고, 값이 step 단위로
/// 실제 바뀔 때만 모델에 쓴다(`onChange`).
/// - 레이아웃: 라벨 줄(`monospacedDigit`)과 전체 높이를 고정하고 패널 콘텐츠 폭도 `sidePanelWidth`로 고정해 값이 바뀌어도 크기가 변하지 않게 한다.
/// - `Slider(step:)`은 macOS에서 눈금 있는 이산 슬라이더로 그려져 손잡이가 흔들리고, 모델에 직접 바인딩하면 드래그마다 `updatedAt`이 바뀌어 화면 전체가 다시 그려진다.
private struct StyleValueSlider: View {
    let title: String
    let range: ClosedRange<Double>
    let step: Double
    let fractionDigits: Int
    /// 모델의 현재 값(라벨 표시와 "바뀌었는지" 비교의 기준).
    let value: Double
    let onCommit: (Double) -> Void

    @State private var draft: Double
    @State private var isDragging = false

    init(
        title: String,
        range: ClosedRange<Double>,
        step: Double,
        fractionDigits: Int,
        value: Double,
        onCommit: @escaping (Double) -> Void
    ) {
        self.title = title
        self.range = range
        self.step = step
        self.fractionDigits = fractionDigits
        self.value = value
        self.onCommit = onCommit
        // 초기값을 여기서 정해 뷰가 나타날 때 `onChange`가 헛발동해 데이터를
        // 바꿔 쓰는 일(예: 옛 기본값 2.2 → 2.0)이 없게 한다.
        _draft = State(initialValue: value)
    }

    private func snapped(_ raw: Double) -> Double {
        let stepped = (raw / step).rounded() * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title): \(String(format: "%.\(fractionDigits)f", value))pt")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Slider(value: $draft, in: range, onEditingChanged: { editing in
                isDragging = editing
            })
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44, alignment: .top)
        .onChange(of: draft) { _, newDraft in
            let next = snapped(newDraft)
            if abs(next - value) > 0.0001 {
                onCommit(next)
            }
        }
        // 다른 노드를 선택하는 등 밖에서 값이 바뀐 경우에만 손잡이를 맞춘다
        // (드래그 중에는 손잡이를 건드리지 않는다).
        .onChange(of: value) { _, newValue in
            if !isDragging {
                draft = newValue
            }
        }
    }
}


// MARK: - 실행취소/다시 실행 + 최근 스타일 기억

/// 노드 하나의 실행취소용 복사본 — 화면이 바꾸는 모든 저장 값을 담는다(`updatedAt`은
/// 일부러 뺀다: 스타일을 바꿀 때마다 같이 바뀌는 값이라 "변경 감지"를 흐린다).
/// 부모는 `persistentModelID`가 아니라 노드 자신의 `id`(UUID)로 가리킨다 — 지워졌다가
/// 되살려진 노드는 `persistentModelID`가 바뀌지만 `id`는 그대로라서다.
struct MindMapNodeSnapshot: Equatable {
    let id: UUID
    let text: String
    let positionX: Double
    let positionY: Double
    let width: Double
    let height: Double
    let color: MindMapNodeColor
    let shape: MindMapNodeShape
    let borderStyle: MindMapBorderStyle
    let borderColor: MindMapNodeColor?
    let borderThickness: Double?
    let borderDashSpacing: Double?
    let lineColor: MindMapNodeColor?
    let lineStyle: MindMapLineStyle?
    let lineThickness: Double
    let dashSpacing: Double
    let arrowShape: MindMapArrowShape?
    let lineFadeByDepth: Bool?
    let taperThickness: Double?
    let descriptionText: String?
    let fontSize: Double?
    let labelHeight: Double?
    let pathType: MindMapPathType
    let createdAt: Date
    let parentID: UUID?

    init(node: MindMapNode) {
        id = node.id
        text = node.text
        positionX = node.positionX
        positionY = node.positionY
        width = node.width
        height = node.height
        color = node.color
        shape = node.shape
        borderStyle = node.borderStyle
        borderColor = node.borderColor
        borderThickness = node.borderThickness
        borderDashSpacing = node.borderDashSpacing
        lineColor = node.lineColor
        lineStyle = node.lineStyle
        lineThickness = node.lineThickness
        dashSpacing = node.dashSpacing
        arrowShape = node.arrowShape
        lineFadeByDepth = node.lineFadeByDepth
        taperThickness = node.taperThickness
        descriptionText = node.descriptionText
        fontSize = node.fontSize
        labelHeight = node.labelHeight
        pathType = node.pathType
        createdAt = node.createdAt
        parentID = node.parent?.id
    }

    /// 부모 관계를 뺀 모든 값을 노드에 되돌려 쓴다(부모는 모든 노드가 준비된 뒤 따로 연결).
    func apply(to node: MindMapNode) {
        node.text = text
        node.positionX = positionX
        node.positionY = positionY
        node.width = width
        node.height = height
        node.color = color
        node.shape = shape
        node.borderStyle = borderStyle
        node.borderColor = borderColor
        node.borderThickness = borderThickness
        node.borderDashSpacing = borderDashSpacing
        node.lineColor = lineColor
        node.lineStyle = lineStyle
        node.lineThickness = lineThickness
        node.dashSpacing = dashSpacing
        node.arrowShape = arrowShape
        node.lineFadeByDepth = lineFadeByDepth
        node.taperThickness = taperThickness
        node.descriptionText = descriptionText
        node.fontSize = fontSize
        node.labelHeight = labelHeight
        node.pathType = pathType
        node.createdAt = createdAt
    }
}

/// 마인드맵 전체의 복사본 — `id` 순으로 정렬해 노드 배열의 순서가 달라도 같은 상태면
/// 같은 값이 되게 한다.
struct MindMapSnapshot: Equatable {
    let nodes: [MindMapNodeSnapshot]

    init(nodes source: [MindMapNode]) {
        nodes = source
            .map { MindMapNodeSnapshot(node: $0) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }
}

/// 마인드맵 노드 전체의 복사본(`MindMapSnapshot`)이 바뀔 때마다 "바뀌기 전 복사본"을 창의
/// `UndoManager`에 실행취소 항목으로 등록한다. 공유 SwiftData 컨텍스트에 `undoManager`를 붙이면
/// 다른 창(설교 편집기 등)의 변경이 섞일 수 있어, 마인드맵 노드만 대상으로 한다.
///   - 연속 변경(드래그, 글자 입력, 슬라이더)은 0.5초 멈출 때까지 한 번의 실행취소로 묶는다.
///   - 실행취소 중 등록된 항목은 UndoManager가 자동으로 다시 실행 스택에 넣는다.
///   - 복원은 `id`(UUID)로 노드를 맞춰 값 덮어쓰기 / 없는 노드 삭제 / 지워진 노드 재생성 /
///     부모 재연결을 한다.
///   - 화면이 뜬 직후 0.8초(`arm()` 전)는 기록하지 않아, 초기 데이터 채움이 "전부 지우는
///     실행취소"로 등록되는 것을 막는다.
final class MindMapUndoCoordinator {
    var undoManager: UndoManager?
    var modelContext: ModelContext?
    var sermon: Sermon?

    private var isArmed = false
    private var pendingBase: MindMapSnapshot?
    private var debounceTask: Task<Void, Never>?
    private var expectedAfterRestore: MindMapSnapshot?

    @MainActor
    func arm() {
        isArmed = true
    }

    /// 노드 값이 바뀔 때마다 화면이 부른다. 이 변화가 방금 한 실행취소/다시 실행의 결과면
    /// `true`(화면이 선택 상태를 정리하도록).
    @MainActor
    func snapshotDidChange(old: MindMapSnapshot, new: MindMapSnapshot) -> Bool {
        if let expected = expectedAfterRestore, expected == new {
            expectedAfterRestore = nil
            pendingBase = nil
            debounceTask?.cancel()
            return true
        }
        guard isArmed else { return false }
        MindMapStyleTemplate.recordChanges(from: old, to: new)
        if pendingBase == nil {
            pendingBase = old
        }
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.commitPending()
        }
        return false
    }

    @MainActor
    private func commitPending() {
        guard let base = pendingBase else { return }
        pendingBase = nil
        registerUndo(restoring: base)
    }

    @MainActor
    private func registerUndo(restoring snapshot: MindMapSnapshot) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.undoStep(to: snapshot)
            }
        }
        undoManager.setActionName("마인드맵 편집")
    }

    /// 실행취소/다시 실행 한 걸음 — `snapshot` 상태로 되돌리고, 되돌리기 직전 상태를
    /// 반대 방향 항목으로 등록한다.
    @MainActor
    private func undoStep(to snapshot: MindMapSnapshot) {
        debounceTask?.cancel()
        pendingBase = nil
        let before = MindMapSnapshot(nodes: sermon?.mindMapNodes ?? [])
        restore(snapshot)
        expectedAfterRestore = snapshot
        registerUndo(restoring: before)
        // 복원 결과가 이미 같은 상태라 변화 알림이 오지 않는 경우를 대비해 기대값을 비운다.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            self?.expectedAfterRestore = nil
        }
    }

    @MainActor
    private func restore(_ snapshot: MindMapSnapshot) {
        guard let context = modelContext, let sermon else { return }
        let current = sermon.mindMapNodes ?? []
        var byID: [UUID: MindMapNode] = [:]
        for node in current {
            byID[node.id] = node
        }
        let wanted = Set(snapshot.nodes.map(\.id))
        for node in current where !wanted.contains(node.id) {
            context.delete(node)
            byID[node.id] = nil
        }
        for item in snapshot.nodes {
            if let existing = byID[item.id] {
                item.apply(to: existing)
            } else {
                let created = MindMapNode(id: item.id, sermon: sermon)
                item.apply(to: created)
                context.insert(created)
                byID[item.id] = created
            }
        }
        for item in snapshot.nodes {
            guard let node = byID[item.id] else { continue }
            let target = item.parentID.flatMap { byID[$0] }
            if node.parent?.id != target?.id {
                node.parent = target
            }
        }
    }
}

/// "가장 최근에 바꾼 스타일"을 기억했다가 새 노드에 입히는 템플릿. 어느 노드에서든 도형 색·모양,
/// 테두리, 선 스타일의 한 항목을 바꾸면 그 항목만 덮어써 `UserDefaults`에 JSON으로 저장한다
/// (앱 재시작·다른 설교에서도 유지). 경로 종류는 마인드맵 전체 설정이라 포함하지 않는다.
/// 저장된 값이 없으면 기본값 — 금색·라운드·테두리 없음·"점점 얇게" 12pt·옅어짐 켜짐.
struct MindMapStyleTemplate: Codable, Equatable {
    var color: MindMapNodeColor = .gold
    var shape: MindMapNodeShape = .rounded
    var borderStyle: MindMapBorderStyle = .solid
    var borderColor: MindMapNodeColor = .navy
    var borderThickness: Double = 2
    var borderDashSpacing: Double = 4
    var lineColor: MindMapNodeColor = .navy
    var lineStyle: MindMapLineStyle = .taper
    var lineThickness: Double = 2.2
    var dashSpacing: Double = 6
    var arrowShape: MindMapArrowShape = .closedTriangle
    var taperThickness: Double = 12
    var lineFadeByDepth: Bool = true
    /// 노드 글자 크기. 우클릭 "스타일 복사/붙여넣기"에서만 채워지고(`init(node:)`), 마지막 스타일 기억(`recordChanges`)에는 쓰지 않는다 —
    /// 새 노드는 항상 기본 크기로 시작한다. 옵셔널이라 예전에 저장된 JSON도 그대로 읽힌다.
    var fontSize: Double?

    private static let defaultsKey = "JBCH.mindMapLastStyleTemplate.v1"

    static func load() -> MindMapStyleTemplate {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let template = try? JSONDecoder().decode(MindMapStyleTemplate.self, from: data) else {
            return MindMapStyleTemplate()
        }
        return template
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    /// 새 노드에 이 스타일을 입힌다(부모 관계·위치·크기·글자는 건드리지 않는다).
    func apply(to node: MindMapNode) {
        node.color = color
        node.shape = shape
        node.borderStyle = borderStyle
        node.borderColor = borderColor
        node.borderThickness = borderThickness
        node.borderDashSpacing = borderDashSpacing
        node.lineColor = lineColor
        node.lineStyle = lineStyle
        node.lineThickness = lineThickness
        node.dashSpacing = dashSpacing
        node.arrowShape = arrowShape
        node.taperThickness = taperThickness
        node.lineFadeByDepth = lineFadeByDepth
        if let fontSize { node.setFontSize(fontSize) }
    }

    /// 두 복사본을 비교해, 같은 노드에서 스타일 항목이 바뀐 게 있으면 그 항목만 저장된
    /// 값에 덮어쓴다(새로 생긴 노드·글자·위치 변화는 무시). 변화가 없으면 저장소를
    /// 읽지도 쓰지도 않는다(드래그 중 매 프레임 불리므로).
    static func recordChanges(from old: MindMapSnapshot, to new: MindMapSnapshot) {
        var oldByID: [UUID: MindMapNodeSnapshot] = [:]
        for node in old.nodes {
            oldByID[node.id] = node
        }
        var template: MindMapStyleTemplate?
        func update(_ change: (inout MindMapStyleTemplate) -> Void) {
            var value = template ?? MindMapStyleTemplate.load()
            change(&value)
            template = value
        }
        for node in new.nodes {
            guard let before = oldByID[node.id] else { continue }
            if before.color != node.color { update { $0.color = node.color } }
            if before.shape != node.shape { update { $0.shape = node.shape } }
            if before.borderStyle != node.borderStyle { update { $0.borderStyle = node.borderStyle } }
            if before.borderColor != node.borderColor, let value = node.borderColor { update { $0.borderColor = value } }
            if before.borderThickness != node.borderThickness, let value = node.borderThickness { update { $0.borderThickness = value } }
            if before.borderDashSpacing != node.borderDashSpacing, let value = node.borderDashSpacing { update { $0.borderDashSpacing = value } }
            if before.lineColor != node.lineColor, let value = node.lineColor { update { $0.lineColor = value } }
            if before.lineStyle != node.lineStyle, let value = node.lineStyle { update { $0.lineStyle = value } }
            if before.lineThickness != node.lineThickness { update { $0.lineThickness = node.lineThickness } }
            if before.dashSpacing != node.dashSpacing { update { $0.dashSpacing = node.dashSpacing } }
            if before.arrowShape != node.arrowShape, let value = node.arrowShape { update { $0.arrowShape = value } }
            if before.taperThickness != node.taperThickness, let value = node.taperThickness { update { $0.taperThickness = value } }
            if before.lineFadeByDepth != node.lineFadeByDepth, let value = node.lineFadeByDepth { update { $0.lineFadeByDepth = value } }
        }
        template?.save()
    }
}

extension MindMapStyleTemplate {
    /// 노드 하나의 현재 스타일(폴백을 적용한 실제 값) — 우클릭 "스타일 복사"가 쓴다.
    /// (extension에 둔 이유: 구조체 본문에 사용자 정의 `init`을 두면 `MindMapStyleTemplate()`
    /// 기본 생성자가 사라진다.)
    init(node: MindMapNode) {
        self.init()
        color = node.color
        shape = node.shape
        borderStyle = node.borderStyle
        borderColor = node.resolvedBorderColor
        borderThickness = node.resolvedBorderThickness
        borderDashSpacing = node.resolvedBorderDashSpacing
        lineColor = node.resolvedLineColor
        lineStyle = node.resolvedLineStyle
        lineThickness = node.lineThickness
        dashSpacing = node.dashSpacing
        arrowShape = node.resolvedArrowShape
        taperThickness = node.resolvedTaperThickness
        lineFadeByDepth = node.resolvedLineFadeByDepth
        fontSize = node.resolvedFontSize
    }
}

// MARK: - 노드 글자 크기

extension MindMapNode {
    /// 제목 기본 크기 — 예전 `.title2`와 같은 값(플랫폼마다 다르다: iOS 22, macOS 17).
    static var defaultFontSize: Double {
        #if os(macOS)
        return 17
        #else
        return 22
        #endif
    }

    /// 화면에 쓰는 제목 크기(pt).
    var resolvedFontSize: Double { fontSize ?? Self.defaultFontSize }

    /// 글자 크기를 기본값(지정 없음)으로 되돌린다. 설명이 있으면 제목 영역도 기본 크기에 맞게 돌아간다.
    func resetFontSize() {
        setFontSize(Self.defaultFontSize)
        fontSize = nil
        updatedAt = .now
    }

    /// 설명 글자 크기 — 지정 크기가 없으면 예전 `.callout`(iOS 16, macOS 12), 있으면 제목의 0.72배(최소 9pt).
    var descriptionFontSize: Double {
        guard let fontSize else {
            #if os(macOS)
            return 12
            #else
            return 16
            #endif
        }
        return max(9, (fontSize * 0.72).rounded())
    }

    /// 글자 크기를 바꾼다. 설명이 있는 노드는 제목(라벨) 영역도 같은 비율로 키우고 줄여 — 그만큼 노드 높이를 함께 조정해 —
    /// 설명 영역 크기는 그대로 둔다(제목 영역은 크기를 직접 조절하지 못하므로 글자 크기에 맞춰 따라가야 잘리지 않는다).
    func setFontSize(_ newSize: Double) {
        let clamped = min(max(newSize, 9), 60)
        let oldSize = resolvedFontSize
        guard abs(clamped - oldSize) > 0.0001 else { return }
        if descriptionText != nil {
            let oldLabel = resolvedLabelHeight
            let newLabel = max(30, oldLabel * clamped / oldSize)
            height += newLabel - oldLabel
            labelHeight = newLabel
        }
        fontSize = clamped
        updatedAt = .now
    }
}

// MARK: - 설교 본문 외부 변경 알림 (마인드맵 → 편집기/내 설교 목록)

extension Notification.Name {
    /// 마인드맵이 설교 본문을 바꾸기 **직전** — 열려 있는 편집기는 지금 입력한
    /// 내용을 즉시 저장한다.
    static let sermonContentFlushRequested = Notification.Name("JBCH.sermonContentFlushRequested")
    /// 마인드맵이 설교 본문을 바꾸고 저장한 **직후** — 열려 있는 편집기는 저장
    /// 없이 닫히고, 내 설교 목록은 그 설교를 선택한다.
    static let sermonContentReplacedExternally = Notification.Name("JBCH.sermonContentReplacedExternally")
}

/// 위 알림 두 개의 전송/수신 공용 헬퍼. `userInfo`에 대상 설교의
/// `PersistentIdentifier`를 실어, 받는 쪽이 "내 설교인지" 스스로 판별한다.
enum SermonExternalContentChange {
    static let sermonIDKey = "sermonID"

    static func post(_ name: Notification.Name, sermonID: PersistentIdentifier) {
        NotificationCenter.default.post(name: name, object: nil, userInfo: [sermonIDKey: sermonID])
    }
}

/// 두 알림을 받아 클로저로 넘기는 `ViewModifier` — `.onReceive` 두 개를 `body`에 직접 붙이면
/// 수식이 길어져 타입 추론이 느려질 수 있어 한 수정자로 묶었다.
struct SermonExternalContentChangeModifier: ViewModifier {
    let onFlush: ((PersistentIdentifier) -> Void)?
    let onReplaced: ((PersistentIdentifier) -> Void)?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .sermonContentFlushRequested)) { note in
                if let id = note.userInfo?[SermonExternalContentChange.sermonIDKey] as? PersistentIdentifier {
                    onFlush?(id)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .sermonContentReplacedExternally)) { note in
                if let id = note.userInfo?[SermonExternalContentChange.sermonIDKey] as? PersistentIdentifier {
                    onReplaced?(id)
                }
            }
    }
}

extension View {
    func onSermonExternalContentChange(
        onFlush: ((PersistentIdentifier) -> Void)? = nil,
        onReplaced: ((PersistentIdentifier) -> Void)? = nil
    ) -> some View {
        modifier(SermonExternalContentChangeModifier(onFlush: onFlush, onReplaced: onReplaced))
    }
}

// MARK: - 설교문 적용 변환기 (SermonMindMapExporter)
//
// 마인드맵 트리를 설교문 텍스트로 바꿔 기존 본문 **아래에 추가**한다(Map → 설교문 단방향).
//  - 제목 노드(루트) → 설교 제목 필드(`Sermon.title`), 본문에는 넣지 않는다.
//  - 형제 노드 순서 → X좌표 왼쪽 → 오른쪽.
//  - 다시 실행하면 매번 새로 추가한다(덮어쓰지 않는다). 나머지 모든 노드는 문단이 된다.
//  - 깊이별 문단 스타일: 깊이 1 → 대주제, 깊이 2 → (하위 있음) 중주제 / (없음) 본문,
//    깊이 3 → (하위 있음) 소주제 / (없음) 본문, 깊이 4 이상 → 본문.
//
// 저장 포맷: 설교문은 세 필드가 한 세트다(`Sermon.contentHtml`=RTF, `contentText`=순수 텍스트,
// `paragraphStyles`=문단별 스타일 rawValue를 U+001F로 이은 문자열). 그래서 세 필드를 항상 함께
// 갱신한다. 새 문단에는 에디터가 쓰는 `SermonParagraphStyleCodec.applyStyle`로 현재 설정의
// 서식을 입혀, 다음에 에디터가 열 때 계산하는 값과 같게 한다("수동 서식"으로 오인돼 스타일
// 재계산에서 빠지는 일이 없도록).

enum SermonMindMapExporter {
    struct Paragraph {
        let text: String
        let style: SermonParagraphStyle
    }

    struct Plan {
        /// 설교 제목으로 쓸 루트 노드 텍스트(없으면 `nil`).
        let title: String?
        let paragraphs: [Paragraph]
    }

    // MARK: - 트리 → 문단 계획

    /// 형제 정렬 — X좌표 왼쪽 → 오른쪽(같으면 위 → 아래, 그래도 같으면 생성
    /// 순서로 안정적으로).
    private static func sortedSiblings(_ nodes: [MindMapNode]) -> [MindMapNode] {
        nodes.sorted { lhs, rhs in
            if lhs.positionX != rhs.positionX { return lhs.positionX < rhs.positionX }
            if lhs.positionY != rhs.positionY { return lhs.positionY < rhs.positionY }
            return lhs.createdAt < rhs.createdAt
        }
    }

    /// 한 노드/설명 텍스트를 한 문단으로 — 문단 수와 저장된 스타일 개수가
    /// 어긋나면 안 되므로(`paragraphStyles`는 문단 개수와 1:1) 노드 안의 줄바꿈은
    /// 공백으로 바꿔 "노드 하나 = 문단 하나"를 보장한다. 비어 있으면 `nil`.
    private static func cleaned(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let flattened = raw
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: SermonParagraphStyleCodec.delimiter, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return flattened.isEmpty ? nil : flattened
    }

    private static func style(depth: Int, hasChildren: Bool) -> SermonParagraphStyle {
        switch depth {
        case 1: return .mainTheme
        case 2: return hasChildren ? .midTheme : .body
        case 3: return hasChildren ? .subTheme : .body
        default: return .body
        }
    }

    /// 트리를 깊이 우선(부모 → 자식, 자식은 왼쪽 → 오른쪽) 순서로 순회해 문단
    /// 목록과 제목을 만든다. 노드에 설명(`descriptionText`)이 있으면 그 노드
    /// 문단 바로 뒤에 본문 문단으로 함께 넣는다.
    ///
    /// 루트는 원칙적으로 정확히 하나지만(삭제 금지 규칙, `SermonMindMapView.
    /// deleteNode`) 그 규칙이 생기기 전 데이터에는 `parent == nil`인 노드가
    /// 여러 개일 수 있다 — 가장 왼쪽 루트만 제목이 되고, 나머지 루트는 그
    /// 아래 대주제와 같은 깊이(1)로 취급해 내용이 사라지지 않게 한다.
    static func makePlan(from nodes: [MindMapNode]) -> Plan {
        // 제목이 되는 "주 루트"는 부모 없는 노드 중 가장 먼저 만든 노드(`SermonMindMapView.isMainRoot`와
        // 같은 기준) — X좌표가 가장 왼쪽이어도 끊어 낸 노드는 제목이 되지 않는다. 나머지 루트는 왼쪽 → 오른쪽 순.
        let allRoots = nodes.filter { $0.parent == nil }
        var roots: [MindMapNode] = []
        if let mainRoot = allRoots.min(by: { $0.createdAt < $1.createdAt }) {
            roots.append(mainRoot)
            roots.append(contentsOf: sortedSiblings(allRoots.filter { $0.persistentModelID != mainRoot.persistentModelID }))
        }
        var paragraphs: [Paragraph] = []
        var visited = Set<PersistentIdentifier>()

        func walk(_ node: MindMapNode, depth: Int) {
            // 순환 참조 방어(정상 트리에서는 일어나지 않는다).
            guard visited.insert(node.persistentModelID).inserted, depth < 200 else { return }
            let children = sortedSiblings(node.children ?? [])
            if let text = cleaned(node.text) {
                paragraphs.append(Paragraph(text: text, style: style(depth: depth, hasChildren: !children.isEmpty)))
            }
            if let description = cleaned(node.descriptionText) {
                paragraphs.append(Paragraph(text: description, style: .body))
            }
            for child in children {
                walk(child, depth: depth + 1)
            }
        }

        var title: String?
        for (index, root) in roots.enumerated() {
            if index == 0 {
                title = cleaned(root.text)
                if let description = cleaned(root.descriptionText) {
                    paragraphs.append(Paragraph(text: description, style: .body))
                }
                visited.insert(root.persistentModelID)
                for child in sortedSiblings(root.children ?? []) {
                    walk(child, depth: 1)
                }
            } else {
                walk(root, depth: 1)
            }
        }
        return Plan(title: title, paragraphs: paragraphs)
    }

    // MARK: - 설교문에 추가

    /// 새 마인드맵 기본 루트 이름 — 사용자가 아직 안 바꾼 이 기본값으로 기존
    /// 설교 제목을 덮어쓰지 않기 위한 비교용(`SermonMindMapView.addRootNode`).
    static let defaultRootText = "메인주제"

    /// 계획을 설교에 반영한다: 제목 필드 설정 + 본문 끝에 문단 추가(기존 내용·서식은
    /// 그대로 두고 아래에만 붙인다). 저장(`modelContext.save`)과 재인덱싱은 호출부 몫이다.
    @MainActor
    static func apply(_ plan: Plan, to sermon: Sermon, settings: UserSettingsStore) {
        if let title = plan.title {
            let isUntouchedDefault = title == defaultRootText
            if !(isUntouchedDefault && !sermon.title.trimmingCharacters(in: .whitespaces).isEmpty) {
                sermon.title = title
            }
        }
        guard !plan.paragraphs.isEmpty else {
            sermon.updatedAt = .now
            return
        }

        // 1) 기존 본문 읽기 — RTF면 서식 그대로, 아니면(빈 문자열/과거 데이터)
        //    순수 텍스트로. 서식 있는 원본이 비어 있는데 `contentText`만 있는
        //    비정상 데이터도 내용을 잃지 않게 그쪽을 쓴다.
        let stored = sermon.contentHtml.isEmpty ? sermon.contentText : sermon.contentHtml
        let existing = RichTextCodec.decode(stored, defaultAttributes: [:])

        // 2) 기존 문단 수와 스타일 — 에디터와 같은 `.byParagraphs` 순회로 센다.
        let existingString = existing.string as NSString
        var existingParagraphCount = 0
        if existingString.length > 0 {
            existingString.enumerateSubstrings(
                in: NSRange(location: 0, length: existingString.length), options: .byParagraphs
            ) { _, _, _, _ in existingParagraphCount += 1 }
        }
        let storedStyles = sermon.paragraphStyles.isEmpty
            ? []
            : sermon.paragraphStyles.components(separatedBy: SermonParagraphStyleCodec.delimiter)
        var styles: [String] = (0..<existingParagraphCount).map { index in
            index < storedStyles.count ? storedStyles[index] : SermonParagraphStyle.body.rawValue
        }

        // 3) 새 문단을 덧붙이고 각각에 스타일 적용.
        let storage = NSTextStorage(attributedString: existing)
        if storage.length > 0, !storage.string.hasSuffix("\n") {
            storage.append(NSAttributedString(string: "\n"))
        }
        for (index, paragraph) in plan.paragraphs.enumerated() {
            let start = storage.length
            storage.append(NSAttributedString(string: paragraph.text))
            let range = NSRange(location: start, length: (paragraph.text as NSString).length)
            SermonParagraphStyleCodec.applyStyle(paragraph.style, to: range, in: storage, settings: settings)
            styles.append(paragraph.style.rawValue)
            if index < plan.paragraphs.count - 1 {
                storage.append(NSAttributedString(string: "\n"))
            }
        }

        // 4) 세 필드를 항상 함께 갱신.
        let encoded = RichTextCodec.encode(storage)
        sermon.contentHtml = encoded.rtf
        sermon.contentText = encoded.plainText
        sermon.paragraphStyles = styles.joined(separator: SermonParagraphStyleCodec.delimiter)
        sermon.updatedAt = .now
    }
}
