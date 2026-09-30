import Foundation
import SwiftData

// MindMapNode 등 마인드맵 SwiftData 모델.
// 설교(`Sermon`) 하나에 딸린 트리 구조의 마인드맵(노드 300개 이하 예상)을 저장한다.
// 도형/테두리/선의 스타일은 서로 독립된 축으로 저장하고, 실제 색·그리기는 화면 쪽 몫이다.
//
// 라이트웨이트 마이그레이션 주의: 기존 행에 새로 추가된 `String` rawValue enum 컬럼은
// 코드상의 기본값으로 채워지지 않고 NULL로 남아, non-optional getter가 크래시한다
// (`Double` 같은 스칼라는 기본값으로 채워짐). 그래서 이후 추가된 속성은 Optional로
// 선언하고 화면은 `resolved*` 프로퍼티로만 읽는다.

/// 마인드맵 도형·테두리·선이 공유하는 색상 별칭 6종. 실제 색 매핑은 화면 쪽 몫이다.
/// 이 패키지는 SwiftUI를 링크하지 않는 순수 데이터 레이어라 이름(태그)만 저장한다.
public enum MindMapNodeColor: String, Codable, Sendable, CaseIterable {
    case navy   // 밤빛 남색
    case gold   // 연한 금박
    case wood   // 가죽 표지
    case teal   // 서고 청람
    case wine   // 와인 적갈
    case slate  // 책장 아이보리(#F7F0E2) — 옛 "서가 슬레이트"를 대체(저장 rawValue "slate"는 그대로)
}

/// 도형 종류 2종(라운드 사각형/사각형).
public enum MindMapNodeShape: String, Codable, Sendable, CaseIterable {
    case rounded
    case rect
}

/// 도형 테두리 스타일 4종. 도형 색·모양과 독립된 축이며, `solid`가 기본값(테두리 없음)이다.
/// `dashed`/`outline`/`bottomAccent`의 테두리는 `MindMapNode.borderColor`를 쓴다.
public enum MindMapBorderStyle: String, Codable, Sendable, CaseIterable {
    case solid          // 테두리 없음
    case dashed         // 점선 테두리
    case outline        // 외곽선
    case bottomAccent   // 하단 강조선
}

/// 선(엣지) 스타일 4종. 스타일별로 조절하는 저장 값이 다르다.
///   - `taper`: `taperThickness`(시작 두께)에서 끝으로 갈수록 얇아진다(세부 계산은 화면 쪽).
///   - `solid`: `lineThickness`
///   - `dashed`: `dashSpacing`
///   - `arrow`: `arrowShape` (실선 몸통 위에 그린다)
///
/// 선언 순서(`allCases`)가 선택 UI 순서이며, 저장은 rawValue라 순서를 바꿔도 데이터에 영향 없다.
public enum MindMapLineStyle: String, Codable, Sendable, CaseIterable {
    case taper
    case solid
    case dashed
    case arrow
}

/// 화살표 머리 모양 4종.
public enum MindMapArrowShape: String, Codable, Sendable, CaseIterable {
    case open           // 열린 화살표(스트로크만, 채움 없음)
    case closedTriangle // 닫힌 삼각형(채움)
    case diamond        // 다이아몬드(채움)
    case circle         // 원(채움)
}

/// 선의 경로 종류(베지어/90도 꺾은선).
public enum MindMapPathType: String, Codable, Sendable, CaseIterable {
    case bezier
    case elbow
}

/// 마인드맵의 노드 하나. 자기 참조 `parent`/`children`로 트리를 이룬다.
/// 루트는 `parent == nil`인 노드이며, `Sermon`당 하나라는 불변식은 모델이 아니라 화면/에디터가 지킨다.
///
/// 삭제 규칙: `children`의 `.nullify`로, 노드를 지우면 자식들의 `parent`만 `nil`이 되고
/// 자식 노드(와 그 하위)는 연결이 끊긴 채 남는다.
///
/// 위치(`positionX`/`positionY`)는 도형 중심점, `width`/`height`는 전체 크기로 캔버스 좌표(포인트)다.
/// 데이터 레이어에 SwiftUI/CoreGraphics 타입을 들이지 않으려 `CGFloat` 대신 `Double`을 쓴다.
/// 선이 연결되는 상/하/좌/우 소켓은 두 노드의 상대 위치로 매번 계산되는 파생 값이라 저장하지 않는다.
@Model
public final class MindMapNode {
    public var id: UUID = UUID()
    public var text: String = ""
    public var positionX: Double = 0
    public var positionY: Double = 0
    public var width: Double = 160
    public var height: Double = 60
    public var color: MindMapNodeColor = MindMapNodeColor.navy
    public var shape: MindMapNodeShape = MindMapNodeShape.rounded
    public var borderStyle: MindMapBorderStyle = MindMapBorderStyle.solid
    /// 테두리 전용 색(도형 색과 독립). `borderStyle == .solid`이면 무시된다.
    /// 마이그레이션 NULL 대비 Optional — `resolvedBorderColor`로만 읽는다.
    public var borderColor: MindMapNodeColor?
    /// 부모로 이어지는 선의 색. 루트는 그릴 선이 없어 무시된다.
    /// 마이그레이션 NULL 대비 Optional — `resolvedLineColor`로만 읽는다.
    public var lineColor: MindMapNodeColor?
    /// 선 스타일. 마이그레이션 NULL 대비 Optional — `resolvedLineStyle`로만 읽는다.
    public var lineStyle: MindMapLineStyle?
    /// `.solid` 선의 두께(포인트). `.arrow`의 선 몸통도 이 값을 쓴다.
    public var lineThickness: Double = 2.2
    /// `.dashed` 선의 대시 사이 간격(포인트). 대시 길이는 화면 쪽 고정값이다.
    public var dashSpacing: Double = 6
    /// `.arrow` 선의 화살표 머리 모양. 마이그레이션 NULL 대비 Optional — `resolvedArrowShape`로만 읽는다.
    public var arrowShape: MindMapArrowShape?
    /// 이 노드의 선을 루트로부터의 단계에 따라 옅게 그릴지 여부(모든 선 스타일 공통).
    /// 마이그레이션 NULL 대비 Optional — `resolvedLineFadeByDepth`로만 읽는다.
    public var lineFadeByDepth: Bool?
    /// `.taper` 선의 시작 두께(pt, 6~20). `lineThickness`와 범위가 달라 따로 저장한다.
    /// 마이그레이션 NULL 대비 Optional — `resolvedTaperThickness`로만 읽는다.
    public var taperThickness: Double?
    /// `borderStyle == .outline`의 테두리 두께(포인트).
    /// 마이그레이션 NULL 대비 Optional — `resolvedBorderThickness`로만 읽는다.
    public var borderThickness: Double?
    /// `borderStyle == .dashed`의 대시 사이 간격(포인트).
    /// 마이그레이션 NULL 대비 Optional — `resolvedBorderDashSpacing`으로만 읽는다.
    public var borderDashSpacing: Double?
    /// 노드 하단에 표시하는 설명 텍스트. `nil`이면 설명 없음, `""`이면 설명 영역만 만들고 입력 대기 중인 상태다.
    public var descriptionText: String?
    /// 부모로 이어지는 선의 경로 종류(베지어/꺾은선).
    public var pathType: MindMapPathType = MindMapPathType.bezier
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now

    /// `borderColor`가 없으면 도형 색을 쓴다(과거 노드의 화면 변화 최소화).
    public var resolvedBorderColor: MindMapNodeColor { borderColor ?? color }
    /// `lineColor`가 없으면 도형 색을 쓴다.
    public var resolvedLineColor: MindMapNodeColor { lineColor ?? color }
    /// `arrowShape`가 없으면 `init` 기본값(닫힌 삼각형)과 동일하게 맞춘다.
    public var resolvedArrowShape: MindMapArrowShape { arrowShape ?? .closedTriangle }
    /// `lineFadeByDepth` 폴백 — 옅어짐 없음.
    public var resolvedLineFadeByDepth: Bool { lineFadeByDepth ?? false }
    /// `taperThickness` 폴백 — 기본 시작 두께 12pt.
    public var resolvedTaperThickness: Double { taperThickness ?? 12 }
    /// `lineStyle`이 없으면 `init` 기본값(실선)과 동일하게 맞춘다.
    public var resolvedLineStyle: MindMapLineStyle { lineStyle ?? .solid }
    /// 테두리 두께 폴백 — 기존 하드코딩 값(2pt).
    public var resolvedBorderThickness: Double { borderThickness ?? 2 }
    /// 테두리 점 간격 폴백 — 기존 하드코딩 점선 패턴 `[6, 4]`의 간격(4pt).
    public var resolvedBorderDashSpacing: Double { borderDashSpacing ?? 4 }

    // deleteRule은 배열을 가진 쪽(Sermon.mindMapNodes)에서만 지정한다(패키지 공통 관례).
    public var sermon: Sermon?

    // 자기 참조 트리 — deleteRule은 배열을 가진 `children` 쪽에서만 지정한다.
    public var parent: MindMapNode?

    @Relationship(deleteRule: .nullify, inverse: \MindMapNode.parent)
    public var children: [MindMapNode]? = []

    public init(
        id: UUID = UUID(),
        text: String = "",
        positionX: Double = 0,
        positionY: Double = 0,
        width: Double = 160,
        height: Double = 60,
        color: MindMapNodeColor = .navy,
        shape: MindMapNodeShape = .rounded,
        borderStyle: MindMapBorderStyle = .solid,
        borderColor: MindMapNodeColor = .navy,
        lineColor: MindMapNodeColor = .navy,
        lineStyle: MindMapLineStyle = .solid,
        lineThickness: Double = 2.2,
        dashSpacing: Double = 6,
        arrowShape: MindMapArrowShape = .closedTriangle,
        pathType: MindMapPathType = .bezier,
        sermon: Sermon? = nil,
        parent: MindMapNode? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.text = text
        self.positionX = positionX
        self.positionY = positionY
        self.width = width
        self.height = height
        self.color = color
        self.shape = shape
        self.borderStyle = borderStyle
        self.borderColor = borderColor
        self.lineColor = lineColor
        self.lineStyle = lineStyle
        self.lineThickness = lineThickness
        self.dashSpacing = dashSpacing
        self.arrowShape = arrowShape
        self.pathType = pathType
        self.sermon = sermon
        self.parent = parent
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
