import Foundation

public struct LayoutPlan: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var target: LayoutTarget
    public var strategy: LayoutStrategy
    public var blocks: [LayoutPlanBlock]
    public var notes: [String]

    public init(
        id: UUID = UUID(),
        target: LayoutTarget,
        strategy: LayoutStrategy,
        blocks: [LayoutPlanBlock],
        notes: [String] = []
    ) {
        self.id = id
        self.target = target
        self.strategy = strategy
        self.blocks = blocks
        self.notes = notes
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
