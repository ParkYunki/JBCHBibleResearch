//
//  TagRelationsView.swift
//  JBCHBibleResearch
//
//  S10(태그 관계 시각화, 별도 창). force-directed 그래프로 점선(자동 추론)/
//  실선(수동 연결) 엣지를 구분하고, 태그를 다른 태그 위로 드래그하면 수동 연결을
//  만든다. 고정 캔버스라 경합할 제스처가 없어 롱프레스 없이 바로 드래그를 받는다.
//
//  Canvas로 그린 선은 SwiftUI 히트테스트 대상이 아니므로, 실선(수동 엣지) 탭은
//  탭 위치와 각 선분 사이의 최단 거리를 직접 계산해 처리한다. 자동 추론 엣지는
//  삭제 대상이 아니라 히트테스트에서 제외하며, 오탭 방지를 위해 삭제 전 확인
//  알림을 거친다.
//

import SwiftUI
import SwiftData
import BibleResearchModels

struct TagRelationsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: TagGraphViewModel?
    @State private var drilldownTag: Tag?
    /// 삭제 확인을 받는 중인 수동 엣지 — nil이 아니면 확인 알림이 떠 있다.
    @State private var edgePendingDeletion: TagEdge?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let viewModel {
                    if viewModel.nodes.isEmpty {
                        emptyState
                    } else {
                        Canvas { context, _ in
                            drawEdges(context: context, viewModel: viewModel)
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture(coordinateSpace: .named("graph"))
                                .onEnded { value in
                                    handleEdgeTap(at: value.location, viewModel: viewModel)
                                }
                        )

                        ForEach(viewModel.nodes) { node in
                            TagNodeView(node: node, viewModel: viewModel) { tag in
                                drilldownTag = tag
                            }
                            .position(node.position)
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .coordinateSpace(name: "graph")
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onAppear { setUp(size: proxy.size) }
            .onChange(of: proxy.size) { _, newSize in
                viewModel?.canvasSize = newSize
            }
        }
        .background(simulationDriver)
        .navigationTitle("태그 관계")
        .safeAreaInset(edge: .bottom) {
            legend
        }
        .sheet(item: $drilldownTag) { tag in
            TagDrilldownView(tag: tag)
        }
        .alert("연결 삭제", isPresented: Binding(
            get: { edgePendingDeletion != nil },
            set: { if !$0 { edgePendingDeletion = nil } }
        )) {
            Button("취소", role: .cancel) { edgePendingDeletion = nil }
            Button("삭제", role: .destructive) {
                if let edge = edgePendingDeletion {
                    viewModel?.deleteManualEdge(edge)
                }
                edgePendingDeletion = nil
            }
        } message: {
            Text(edgeDeletionMessage)
        }
    }

    /// 삭제 확인 알림 문구. 노드를 못 찾으면 태그 이름 없는 일반 문구로 대체한다.
    private var edgeDeletionMessage: String {
        guard let edge = edgePendingDeletion, let viewModel else {
            return "이 연결을 삭제할까요?"
        }
        let nameByID = Dictionary(uniqueKeysWithValues: viewModel.nodes.map { ($0.id, $0.tag.name) })
        guard let nameA = nameByID[edge.tagAID], let nameB = nameByID[edge.tagBID] else {
            return "이 연결을 삭제할까요?"
        }
        return "\"\(nameA)\" ↔ \"\(nameB)\" 연결을 삭제할까요? 태그 자체는 지워지지 않습니다."
    }

    /// 탭 위치와 가장 가까운 수동 엣지(실선)를 찾아 삭제 확인을 띄운다.
    /// 자동 추론 엣지(점선)는 히트테스트에서 제외한다.
    private func handleEdgeTap(at point: CGPoint, viewModel: TagGraphViewModel) {
        let positions = Dictionary(uniqueKeysWithValues: viewModel.nodes.map { ($0.id, $0.position) })
        let hitThreshold: CGFloat = 10
        var closestEdge: TagEdge?
        var closestDistance = hitThreshold
        for edge in viewModel.edges where edge.kind == .manual {
            guard let a = positions[edge.tagAID], let b = positions[edge.tagBID] else { continue }
            let distance = Self.distance(from: point, toSegment: a, b)
            if distance < closestDistance {
                closestDistance = distance
                closestEdge = edge
            }
        }
        if let closestEdge {
            edgePendingDeletion = closestEdge
        }
    }

    /// 점 `point`와 선분 `a`-`b` 사이의 최단 거리. 투영 매개변수 t를 0...1로
    /// 클램프해 선분 밖 연장선은 배제한다.
    private static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - a.x, point.y - a.y)
        }
        let t = min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared, 0), 1)
        let projectedX = a.x + t * dx
        let projectedY = a.y + t * dy
        return hypot(point.x - projectedX, point.y - projectedY)
    }

    /// TimelineView가 매 프레임 `viewModel.tick(deltaTime:)`을 호출해 물리
    /// 시뮬레이션을 진행시킨다. 아무것도 그리지 않는 투명 뷰라 `.background`에 둔다.
    private var simulationDriver: some View {
        TimelineView(.animation) { timeline in
            Color.clear
                .onChange(of: timeline.date) { _, _ in
                    viewModel?.tick(deltaTime: 1.0 / 60.0)
                }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "circle.grid.cross")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("아직 서로 연결된 태그가 없습니다.")
                .foregroundStyle(.secondary)
            Text("같은 메모·문서에 태그를 함께 붙이면 자동으로, 태그끼리 드래그해 놓으면 수동으로 연결됩니다.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Rectangle().fill(Color.secondary.opacity(0.5)).frame(width: 16, height: 1)
                Text("자동 추론").font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Rectangle().fill(Color.primary).frame(width: 16, height: 2)
                Text("수동 연결").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text("드래그로 연결 · 실선을 탭하면 삭제")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(8)
        .background(.bar)
    }

    private func drawEdges(context: GraphicsContext, viewModel: TagGraphViewModel) {
        let positions = Dictionary(uniqueKeysWithValues: viewModel.nodes.map { ($0.id, $0.position) })
        for edge in viewModel.edges {
            guard let a = positions[edge.tagAID], let b = positions[edge.tagBID] else { continue }
            var path = Path()
            path.move(to: a)
            path.addLine(to: b)
            switch edge.kind {
            case .auto:
                context.stroke(path, with: .color(.secondary.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            case .manual:
                context.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: 2.5))
            }
        }
    }

    private func setUp(size: CGSize) {
        guard viewModel == nil else { return }
        let vm = TagGraphViewModel(modelContext: modelContext)
        vm.canvasSize = size
        vm.loadGraph()
        viewModel = vm
    }
}

// MARK: - 노드 뷰(원 + 이름표, 드래그 가능)

private struct TagNodeView: View {
    let node: TagNode
    let viewModel: TagGraphViewModel
    let onSelect: (Tag) -> Void

    var body: some View {
        VStack(spacing: 2) {
            Circle()
                .fill(Color("AccentColor").opacity(0.85))
                .frame(width: 14, height: 14)
            Text(node.tag.name)
                .font(.caption2)
                .fixedSize()
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.thinMaterial, in: Capsule())
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectTag(node.tag)
            onSelect(node.tag)
        }
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .named("graph"))
                .onChanged { value in
                    viewModel.beginDrag(nodeID: node.id)
                    viewModel.updateDrag(nodeID: node.id, position: value.location)
                }
                .onEnded { value in
                    viewModel.updateDrag(nodeID: node.id, position: value.location)
                    viewModel.endDrag(nodeID: node.id)
                }
        )
    }
}
