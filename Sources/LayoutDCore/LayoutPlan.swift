import Foundation

public struct LayoutPlan: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var target: LayoutTarget
    public var strategy: LayoutStrategy
    public var blocks: [LayoutPlanBlock]
    public var notes: [String]
    public var marginOverride: PageMargins?
    public var columnsOverride: Int?
    public var showHeadersFooters: Bool?

    public init(
        id: UUID = UUID(),
        target: LayoutTarget,
        strategy: LayoutStrategy,
        blocks: [LayoutPlanBlock],
        notes: [String] = [],
        marginOverride: PageMargins? = nil,
        columnsOverride: Int? = nil,
        showHeadersFooters: Bool? = nil
    ) {
        self.id = id
        self.target = target
        self.strategy = strategy
        self.blocks = blocks
        self.notes = notes
        self.marginOverride = marginOverride
        self.columnsOverride = columnsOverride
        self.showHeadersFooters = showHeadersFooters
    }
}

public extension LayoutPlan {
    func retargeted(to target: LayoutTarget, regenerateBlockIDs: Bool = true) -> LayoutPlan {
        let mappedBlocks: [LayoutPlanBlock]
        if regenerateBlockIDs {
            var idMap: [UUID: UUID] = [:]
            for block in blocks {
                idMap[block.id] = UUID()
            }
            mappedBlocks = blocks.map { block in
                var copy = block
                if let newId = idMap[block.id] {
                    copy.id = newId
                }
                if let next = copy.nextThreadedBlockId, let newNext = idMap[next] {
                    copy.nextThreadedBlockId = newNext
                }
                if let prev = copy.previousThreadedBlockId, let newPrev = idMap[prev] {
                    copy.previousThreadedBlockId = newPrev
                }
                return copy
            }
        } else {
            mappedBlocks = blocks
        }
        return LayoutPlan(
            id: UUID(),
            target: target,
            strategy: strategy,
            blocks: mappedBlocks,
            notes: notes,
            marginOverride: marginOverride,
            columnsOverride: columnsOverride,
            showHeadersFooters: showHeadersFooters
        )
    }
}

public struct SavedLayoutTemplate: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var plan: LayoutPlan
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        plan: LayoutPlan,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.plan = plan
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    public func makePlan(target: LayoutTarget, regenerateBlockIDs: Bool = true) -> LayoutPlan {
        plan.retargeted(to: target, regenerateBlockIDs: regenerateBlockIDs)
    }
}

public enum LayoutTarget: Codable, Equatable, Sendable {
    case page(Int)
    case spread(Int)
    case section(UUID)
}

public enum LayoutStrategy: String, Codable, CaseIterable, Sendable {
    case textLed
    case imageLed
    case balanced
    case comparison
    case knowledgeCard
}

public struct LayoutPlanBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: LayoutBlockKind
    public var role: String
    public var frame: Rect
    public var contentReference: ContentReference
    public var backgroundColorHex: String?
    public var strokeColorHex: String?
    public var strokeWidth: Double?
    public var textColorHex: String?
    public var nextThreadedBlockId: UUID?
    public var previousThreadedBlockId: UUID?

    public init(
        id: UUID = UUID(),
        kind: LayoutBlockKind,
        role: String,
        frame: Rect,
        contentReference: ContentReference,
        backgroundColorHex: String? = nil,
        strokeColorHex: String? = nil,
        strokeWidth: Double? = nil,
        textColorHex: String? = nil,
        nextThreadedBlockId: UUID? = nil,
        previousThreadedBlockId: UUID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.role = role
        self.frame = frame
        self.contentReference = contentReference
        self.backgroundColorHex = backgroundColorHex
        self.strokeColorHex = strokeColorHex
        self.strokeWidth = strokeWidth
        self.textColorHex = textColorHex
        self.nextThreadedBlockId = nextThreadedBlockId
        self.previousThreadedBlockId = previousThreadedBlockId
    }
}

public enum LayoutBlockKind: String, Codable, Sendable {
    case text
    case image
    case caption
    case component
}

public enum ContentReference: Codable, Equatable, Sendable {
    case paragraph(UUID)
    case asset(UUID)
    case storyRange(storyId: UUID, startParagraphId: UUID, endParagraphId: UUID)
    case generated(String)
}

public enum LayoutTool: String, CaseIterable, Sendable {
    case selection
    case directSelection
    case page
    case gap
    case type
    case line
    case pen
    case pencil
    case rectangularFrame
    case rectangle
    case scissors
    case gradient
    case hand
    case zoom
    
    public var displayName: String {
        switch self {
        case .selection: return "选择工具"
        case .directSelection: return "直接选择工具"
        case .page: return "页面工具"
        case .gap: return "间隔工具"
        case .type: return "文字工具"
        case .line: return "直线工具"
        case .pen: return "钢笔工具"
        case .pencil: return "铅笔工具"
        case .rectangularFrame: return "矩形框架工具"
        case .rectangle: return "矩形工具"
        case .scissors: return "剪刀工具"
        case .gradient: return "渐变工具"
        case .hand: return "手形工具"
        case .zoom: return "缩放工具"
        }
    }
    
    public var iconName: String {
        switch self {
        case .selection: return "arrow.up.left.pointer.fill"
        case .directSelection: return "cursorarrow"
        case .page: return "doc.plaintext"
        case .gap: return "arrow.left.and.right.pattern.ratio"
        case .type: return "textformat"
        case .line: return "line.diagonal"
        case .pen: return "pencil.tip"
        case .pencil: return "pencil"
        case .rectangularFrame: return "square.dashed"
        case .rectangle: return "square"
        case .scissors: return "scissors"
        case .gradient: return "slider.horizontal.3"
        case .hand: return "hand.raised.fill"
        case .zoom: return "magnifyingglass"
        }
    }
}

public enum FormattingTarget: String, CaseIterable, Sendable {
    case container
    case text
    
    public var displayName: String {
        switch self {
        case .container: return "格式化影响容器"
        case .text: return "格式化影响文本"
        }
    }
}

public enum ScreenMode: String, CaseIterable, Sendable {
    case normal
    case preview
    
    public var displayName: String {
        switch self {
        case .normal: return "正常模式"
        case .preview: return "预览模式"
        }
    }
}
