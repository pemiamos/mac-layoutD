import Foundation

public struct ContentFingerprint: Codable, Equatable, Sendable {
    public var spreadDemands: [SpreadDemand]
    
    public init(spreadDemands: [SpreadDemand] = []) {
        self.spreadDemands = spreadDemands
    }
}

public struct SpreadDemand: Codable, Equatable, Sendable {
    public var spreadIndex: Int
    public var bodyLoad: Double // 0...1 estimated text load
    public var imageCount: Int
    public var images: [AssetSummary]
    public var pullQuoteCount: Int
    public var knowledgeCardCount: Int
    public var isChapterStart: Bool
    
    public init(
        spreadIndex: Int,
        bodyLoad: Double = 0.0,
        imageCount: Int = 0,
        images: [AssetSummary] = [],
        pullQuoteCount: Int = 0,
        knowledgeCardCount: Int = 0,
        isChapterStart: Bool = false
    ) {
        self.spreadIndex = spreadIndex
        self.bodyLoad = bodyLoad
        self.imageCount = imageCount
        self.images = images
        self.pullQuoteCount = pullQuoteCount
        self.knowledgeCardCount = knowledgeCardCount
        self.isChapterStart = isChapterStart
    }
}

public struct SpreadSelection: Codable, Equatable, Sendable {
    public var spreadIndex: Int
    public var archetypeId: String
    public var mirror: Bool
    public var imageTier: String // "none", "small", "medium", "large", "fullBleed"
    public var pullQuotePosition: String // "none", "top", "middle", "inlineLeft"
    public var rerollCounter: Int
    
    public init(
        spreadIndex: Int,
        archetypeId: String,
        mirror: Bool = false,
        imageTier: String = "none",
        pullQuotePosition: String = "none",
        rerollCounter: Int = 0
    ) {
        self.spreadIndex = spreadIndex
        self.archetypeId = archetypeId
        self.mirror = mirror
        self.imageTier = imageTier
        self.pullQuotePosition = pullQuotePosition
        self.rerollCounter = rerollCounter
    }
}
