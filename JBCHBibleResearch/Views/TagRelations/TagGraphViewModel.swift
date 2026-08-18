//
//  TagGraphViewModel.swift
//  JBCHBibleResearch
//
//  S10(태그 관계 시각화) 데이터/시뮬레이션 상태. screens.md "S10. 태그 관계 시각화"
//  절 근거 — force-directed 그래프, 점선(자동 추론)/실선(수동 연결) 엣지 구분.
//
//  ⚠️ [단순화, 확인 필요] "자동 추론 엣지"는 6.3의 "MemoTag를 조인해 같은 메모에
//  동시 등장한 빈도를 계산"이라는 문구를 문서 쪽으로도 확장 해석했다 — 같은
//  `SourceDocument`에 `DocumentAnchor(anchorType: .keyword)`로 동시에 걸린 태그도
//  같은 방식으로 자동 엣지에 포함시켰다. 원문은 메모 동시 등장만 명시하고 문서
//  동시 등장은 "실시간 계산"이라고만 적어 정확히 문서 채널도 포함하라는 뜻인지
//  확실하지 않지만, S10의 드릴다운이 문서/OCR도 같은 자격으로 다루는 것과 일관되게
//  맞추는 편이 낫다고 판단해 포함했다.
//
//  ⚠️ [노드 필터링] 그래프 노드는 "엣지가 하나라도 있는 태그"만 포함한다 — 아무
//  관계도 없는 고립 태그까지 다 그리면 화면이 무의미하게 복잡해진다는 판단이다.
//  원문에 이 필터링 규칙이 명시돼 있지는 않다.
//
//  ⚠️ [물리 시뮬레이션] force-directed 레이아웃은 SwiftUI/Apple 표준 API가 아니라
//  이 파일이 직접 구현한 단순 스프링+반발력 모델이다(반발력 ~ 1/거리², 엣지는
//  스프링, 중심 쏠림 방지용 약한 구심력, 매 프레임 감쇠). 실제 컴파일/성능은
//  검증되지 않았다 — 노드 수가 많아지면(태그 수백 개) 매 프레임 O(n²) 반발력
//  계산이 느려질 수 있다는 점도 미리 남겨 둔다.
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

/// 태그 클릭 시 드릴다운에 쓰이는 3분류 결과(screens.md S10 "3분류 드릴다운").
/// S10뿐 아니라 메모·문서의 태그 칩 클릭에서도 재사용한다(TagDrilldownView.swift).
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

        // 채널 1 — 메모 동시 등장(6.3 원문 그대로).
        let memos = (try? modelContext.fetch(FetchDescriptor<UserMemo>())) ?? []
        for memo in memos {
            let tagIDs = (memo.memoTags ?? []).compactMap { $0.tag }.filter { !$0.isMerged }.map(\.persistentModelID)
            for pair in allPairs(of: tagIDs) { addAutoPair(pair.0, pair.1) }
        }

        // 채널 2 — 문서 동시 등장(위 파일 상단 ⚠️ 확장 해석).
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

        // 노드 = 엣지가 하나라도 있는 태그만(위 파일 상단 ⚠️ 참고).
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

    /// 드래그 종료 — 다른 노드 위에서 놓으면(근접 판정) 수동 연결(TagRelation)을
    /// 만든다(screens.md "빈 공간에서 태그를 다른 태그 위로 드래그하면 수동 연결 생성").
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

    /// 수동 엣지 삭제(실선 클릭 등 — 뷰가 제공하는 진입점에서 호출).
    ///
    /// ⚠️ `persistentModelID`는 `@Model`이 합성한 프로퍼티라 `#Predicate` 매크로
    /// 안에서 직접 비교할 수 있는지 이 세션에서 확신할 수 없었다(같은 이유로
    /// 이미 여러 번 플래그된 `#Predicate` 옵셔널/합성 프로퍼티 관련 불확실성,
    /// addendum 6장 계열) — 그래서 전체를 가져와 Swift 배열 `first(where:)`로
    /// 안전하게 걸러낸다. 태그 관계 개수가 아주 많아지면 비효율적일 수 있지만,
    /// 이 앱 성격상(개인 연구 태그) 그 정도까지 커질 가능성은 낮다고 판단했다.
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

    /// S10과 메모/문서 태그 칩 클릭이 공유하는 조회 로직(6.3 "하나의 tag_id로 세
    /// 쿼리"). static으로 둬서 이 뷰모델 인스턴스가 없는 곳(예: MemoDetailView)에서도
    /// 바로 쓸 수 있게 했다.
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
