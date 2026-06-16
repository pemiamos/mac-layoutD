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
        LayoutPlan(
            id: UUID(),
            target: target,
            strategy: strategy,
            blocks: blocks.map { block in
                if regenerateBlockIDs {
                    var copy = block
                    copy.id = UUID()
                    return copy
                }
                return block
            },
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

    public init(
        id: UUID = UUID(),
        kind: LayoutBlockKind,
        role: String,
        frame: Rect,
        contentReference: ContentReference
    ) {
        self.id = id
        self.kind = kind
        self.role = role
        self.frame = frame
        self.contentReference = contentReference
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
