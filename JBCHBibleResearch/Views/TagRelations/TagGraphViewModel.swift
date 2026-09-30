//
//  TagGraphViewModel.swift
//  JBCHBibleResearch
//
//  S10(태그 관계 시각화)의 데이터/시뮬레이션 상태. force-directed 그래프이며 점선(자동 추론)/
//  실선(수동 연결) 엣지를 구분한다.
//
//  ⚠️ 자동 추론 엣지는 메모 동시 등장뿐 아니라, 같은 SourceDocument에 DocumentAnchor(.keyword)로
//  함께 걸린 태그도 포함한다(드릴다운이 문서/OCR도 같은 자격으로 다루는 것과 맞춤).
//
//  ⚠️ 노드는 엣지가 하나라도 있는 태그만 포함한다(고립 태그는 그리지 않음).
//
//  ⚠️ 레이아웃은 직접 구현한 단순 스프링+반발력 모델이다(반발력 ~ 1/거리², 엣지 스프링,
//  약한 구심력, 프레임마다 감쇠). 반발력 계산이 매 프레임 O(n²)라 태그가 수백 개면 느려질 수 있다.
//

import Foundation
import SwiftData
import Observation
import CoreGraphics
import BibleResearchModels

struct TagNode: Identifiable {
    let id: PersistentIdentifier
    let tag: Tag
    var position: CGPoint
    var velocity: CGVector = .zero
    var isDragging: Bool = false
}

struct TagEdge: Identifiable {
    enum Kind { case auto, manual }
    var id: String { "\(tagAID)-\(tagBID)-\(kind == .auto ? "a" : "m")" }
    let tagAID: PersistentIdentifier
    let tagBID: PersistentIdentifier
    let kind: Kind
    var weight: Int = 1
    /// `.manual`일 때만 값이 있다 — 삭제(엣지 클릭 등) 시 이 관계 레코드를 지운다.
    var manualRelationID: PersistentIdentifier?
}

/// 태그 클릭 시 드릴다운에 쓰이는 3분류 결과. S10과 메모·문서의 태그 칩 클릭에서 함께 쓴다.
struct TagDrilldownResult {
    struct MemoItem: Identifiable { let id: PersistentIdentifier; let memo: UserMemo; let label: String }
    struct DocumentItem: Identifiable { let id: PersistentIdentifier; let document: SourceDocument; let anchor: DocumentAnchor }

    var memos: [MemoItem] = []
    var documents: [DocumentItem] = [] // 이미지 아닌 문서(hwp/pdf/doc)
    var ocrImages: [DocumentItem] = [] // 이미지 문서
}

@MainActor
@Observable
final class TagGraphViewModel {
    private(set) var nodes: [TagNode] = []
    private(set) var edges: [TagEdge] = []
    var selectedTag: Tag?
    private(set) var drilldown = TagDrilldownResult()

    private let modelContext: ModelContext
    /// 시뮬레이션 캔버스 크기 — `tick`이 중심 쏠림/경계 클램프 계산에 쓴다.
    var canvasSize: CGSize = CGSize(width: 600, height: 500)

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - 로드 + 그래프 구성

    func loadGraph() {
        let allTags = ((try? modelContext.fetch(FetchDescriptor<Tag>())) ?? []).filter { !$0.isMerged }
        var byID: [PersistentIdentifier: Tag] = [:]
        for tag in allTags { byID[tag.persistentModelID] = tag }

        var autoWeights: [String: (a: PersistentIdentifier, b: PersistentIdentifier, weight: Int)] = [:]
        func addAutoPair(_ a: PersistentIdentifier, _ b: PersistentIdentifier) {
            guard a != b else { return }
            let key = pairKey(a, b)
            if var existing = autoWeights[key] {
                existing.weight += 1
                autoWeights[key] = existing
            } else {
                autoWeights[key] = (a, b, 1)
            }
        }

        // 채널 1 — 메모 동시 등장.
        let memos = (try? modelContext.fetch(FetchDescriptor<UserMemo>())) ?? []
        for memo in memos {
            let tagIDs = (memo.memoTags ?? []).compactMap { $0.tag }.filter { !$0.isMerged }.map(\.persistentModelID)
            for pair in allPairs(of: tagIDs) { addAutoPair(pair.0, pair.1) }
        }

        // 채널 2 — 문서 동시 등장(파일 상단 참고).
        let documents = (try? modelContext.fetch(FetchDescriptor<SourceDocument>())) ?? []
        for document in documents {
            let tagIDs = (document.anchors ?? [])
                .filter { $0.anchorType == .keyword }
                .compactMap(\.linkedTag)
                .filter { !$0.isMerged }
                .map(\.persistentModelID)
            for pair in allPairs(of: Array(Set(tagIDs))) { addAutoPair(pair.0, pair.1) }
        }

        var builtEdges: [TagEdge] = autoWeights.values.map {
            TagEdge(tagAID: $0.a, tagBID: $0.b, kind: .auto, weight: $0.weight)
        }

        // 수동 엣지(TagRelation, 삭제 가능).
        let relations = (try? modelContext.fetch(FetchDescriptor<TagRelation>())) ?? []
        for relation in relations {
            guard let a = relation.tagA?.persistentModelID, let b = relation.tagB?.persistentModelID, a != b else { continue }
            builtEdges.append(TagEdge(tagAID: a, tagBID: b, kind: .manual, manualRelationID: relation.persistentModelID))
        }

        // 노드 = 엣지가 하나라도 있는 태그만(파일 상단 참고).
        var participatingIDs = Set<PersistentIdentifier>()
        for edge in builtEdges {
            participatingIDs.insert(edge.tagAID)
            participatingIDs.insert(edge.tagBID)
        }

        let existingPositions = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.position) })
        let idList = Array(participatingIDs)
        nodes = idList.enumerated().compactMap { index, id in
            guard let tag = byID[id] else { return nil }
            let position = existingPositions[id] ?? initialPosition(index: index, count: idList.count)
            return TagNode(id: id, tag: tag, position: position)
        }
        edges = builtEdges
    }

    private func initialPosition(index: Int, count: Int) -> CGPoint {
        let angle = (2 * Double.pi * Double(index)) / Double(max(count, 1))
        let radius = min(canvasSize.width, canvasSize.height) / 3
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }

    private func pairKey(_ a: PersistentIdentifier, _ b: PersistentIdentifier) -> String {
        // PersistentIdentifier가 Comparable은 아니라 문자열 표현으로 정렬해 순서
        // 무관 키를 만든다(무순서 쌍을 하나의 엣지로 합치기 위함).
        let sa = String(describing: a), sb = String(describing: b)
        return sa < sb ? "\(sa)|\(sb)" : "\(sb)|\(sa)"
    }

    private func allPairs(of ids: [PersistentIdentifier]) -> [(PersistentIdentifier, PersistentIdentifier)] {
        guard ids.count > 1 else { return [] }
        var result: [(PersistentIdentifier, PersistentIdentifier)] = []
        for i in 0..<ids.count {
            for j in (i + 1)..<ids.count {
                result.append((ids[i], ids[j]))
            }
        }
        return result
    }

    // MARK: - 물리 시뮬레이션(위 파일 상단 ⚠️ 참고)

    private let repulsionConstant: CGFloat = 2400
    private let centeringForce: CGFloat = 0.02
    private let damping: CGFloat = 0.85
    private let autoIdealLength: CGFloat = 140
    private let manualIdealLength: CGFloat = 100
    private let autoSpringStrength: CGFloat = 0.01
    private let manualSpringStrength: CGFloat = 0.03

    func tick(deltaTime: CGFloat) {
        guard !nodes.isEmpty else { return }
        var forces: [PersistentIdentifier: CGVector] = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, .zero) })

        func addForce(_ id: PersistentIdentifier, dx: CGFloat, dy: CGFloat) {
            let current = forces[id] ?? .zero
            forces[id] = CGVector(dx: current.dx + dx, dy: current.dy + dy)
        }

        // 반발력(모든 쌍).
        for i in 0..<nodes.count {
            for j in (i + 1)..<nodes.count {
                let a = nodes[i], b = nodes[j]
                let dx = a.position.x - b.position.x
                let dy = a.position.y - b.position.y
                let distanceSquared = max(dx * dx + dy * dy, 1)
                let distance = sqrt(distanceSquared)
                let force = repulsionConstant / distanceSquared
                let fx = (dx / distance) * force
                let fy = (dy / distance) * force
                addForce(a.id, dx: fx, dy: fy)
                addForce(b.id, dx: -fx, dy: -fy)
            }
        }

        // 스프링(엣지).
        let positionByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.position) })
        for edge in edges {
            guard let pa = positionByID[edge.tagAID], let pb = positionByID[edge.tagBID] else { continue }
            let dx = pb.x - pa.x
            let dy = pb.y - pa.y
            let distance = max(sqrt(dx * dx + dy * dy), 1)
            let idealLength = edge.kind == .auto ? autoIdealLength : manualIdealLength
            let strength = edge.kind == .auto ? autoSpringStrength : manualSpringStrength
            let displacement = distance - idealLength
            let fx = (dx / distance) * displacement * strength
            let fy = (dy / distance) * displacement * strength
            addForce(edge.tagAID, dx: fx, dy: fy)
            addForce(edge.tagBID, dx: -fx, dy: -fy)
        }

        // 구심력 + 적분 + 감쇠.
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        for index in nodes.indices {
            guard !nodes[index].isDragging else { continue }
            let id = nodes[index].id
            var force = forces[id] ?? .zero
            force.dx += (center.x - nodes[index].position.x) * centeringForce
            force.dy += (center.y - nodes[index].position.y) * centeringForce

            var velocity = nodes[index].velocity
            velocity.dx = (velocity.dx + force.dx * deltaTime) * damping
            velocity.dy = (velocity.dy + force.dy * deltaTime) * damping
            nodes[index].velocity = velocity

            var position = nodes[index].position
            position.x += velocity.dx * deltaTime
            position.y += velocity.dy * deltaTime
            position.x = min(max(position.x, 20), max(canvasSize.width - 20, 20))
            position.y = min(max(position.y, 20), max(canvasSize.height - 20, 20))
            nodes[index].position = position
        }
    }

    // MARK: - 드래그

    func beginDrag(nodeID: PersistentIdentifier) {
        guard let index = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        nodes[index].isDragging = true
        nodes[index].velocity = .zero
    }

    func updateDrag(nodeID: PersistentIdentifier, position: CGPoint) {
        guard let index = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        nodes[index].position = position
    }

    /// 드래그 종료 — 다른 노드 근처(proximityThreshold 이내)에 놓으면 수동 연결(TagRelation)을 만든다.
    func endDrag(nodeID: PersistentIdentifier, proximityThreshold: CGFloat = 36) {
        guard let index = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        nodes[index].isDragging = false
        let dragged = nodes[index]

        if let target = nodes.first(where: { other in
            guard other.id != nodeID else { return false }
            let dx = other.position.x - dragged.position.x
            let dy = other.position.y - dragged.position.y
            return sqrt(dx * dx + dy * dy) <= proximityThreshold
        }) {
            createManualRelation(between: dragged.tag, and: target.tag)
        }
    }

    private func createManualRelation(between a: Tag, and b: Tag) {
        guard a.persistentModelID != b.persistentModelID else { return }
        let alreadyExists = edges.contains {
            $0.kind == .manual &&
            (($0.tagAID == a.persistentModelID && $0.tagBID == b.persistentModelID) ||
             ($0.tagAID == b.persistentModelID && $0.tagBID == a.persistentModelID))
        }
        guard !alreadyExists else { return }
        let relation = TagRelation(tagA: a, tagB: b)
        modelContext.insert(relation)
        try? modelContext.save()
        loadGraph()
    }

    /// 수동 엣지 삭제(뷰가 제공하는 진입점에서 호출).
    ///
    /// ⚠️ `persistentModelID`는 @Model이 합성한 프로퍼티라 `#Predicate`에서 직접 비교할 수 있는지
    /// 확신할 수 없어, 전체를 가져와 `first(where:)`로 거른다. 관계가 매우 많아지면 비효율적일 수 있다.
    func deleteManualEdge(_ edge: TagEdge) {
        guard edge.kind == .manual, let relationID = edge.manualRelationID else { return }
        let allRelations = (try? modelContext.fetch(FetchDescriptor<TagRelation>())) ?? []
        if let relation = allRelations.first(where: { $0.persistentModelID == relationID }) {
            modelContext.delete(relation)
            try? modelContext.save()
            loadGraph()
        }
    }

    // MARK: - 드릴다운(태그 클릭)

    func selectTag(_ tag: Tag) {
        selectedTag = tag
        drilldown = TagGraphViewModel.loadDrilldown(for: tag, context: modelContext)
    }

    func clearSelection() {
        selectedTag = nil
        drilldown = TagDrilldownResult()
    }

    /// S10과 메모/문서 태그 칩 클릭이 공유하는 조회 로직. 뷰모델 인스턴스가 없는 곳
    /// (예: MemoDetailView)에서도 쓰도록 static이다.
    static func loadDrilldown(for tag: Tag, context: ModelContext) -> TagDrilldownResult {
        var result = TagDrilldownResult()

        let memoTags = (tag.memoTags ?? [])
        for memoTag in memoTags {
            guard let memo = memoTag.memo else { continue }
            let label = "\(memo.bookId)장 메모" // ⚠️ 책 이름 표시는 BooksProvider가 필요한데
            // 이 함수는 정적 유틸이라 화면 레이어 서비스에 의존하지 않게 했다 —
            // 호출부(TagDrilldownView)가 BooksProvider로 다시 라벨링한다.
            result.memos.append(.init(id: memo.persistentModelID, memo: memo, label: label))
        }

        let anchors = (tag.documentAnchors ?? [])
        for anchor in anchors {
            guard let document = anchor.sourceDocument else { continue }
            let item = TagDrilldownResult.DocumentItem(id: anchor.persistentModelID, document: document, anchor: anchor)
            if document.originalFormat == .image {
                result.ocrImages.append(item)
            } else {
                result.documents.append(item)
            }
        }

        return result
    }
}
