import Foundation

public enum ArchetypeRole: String, Codable, CaseIterable, Sendable {
    case opener
    case workhorse
    case breathing
    case feature
    case reference
}

public struct SpreadBlock: Codable, Equatable, Sendable {
    public var role: String
    public var kind: LayoutBlockKind
    public var normalizedFrame: Rect // x, y, width, height (0...1 normalized to page width/height)
    public var bleedAcrossSpine: Bool
    
    public init(role: String, kind: LayoutBlockKind, normalizedFrame: Rect, bleedAcrossSpine: Bool = false) {
        self.role = role
        self.kind = kind
        self.normalizedFrame = normalizedFrame
        self.bleedAcrossSpine = bleedAcrossSpine
    }
}

public struct SpreadArchetype: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    public var family: LayoutStrategy
    public var pages: Int // Always 2
    public var imageSlots: Int
    public var pullQuoteSlots: Int
    public var mirror: Bool
    public var weight: Double
    public var imageTiers: [String]
    public var pullQuotePositions: [String]
    public var carriesMotifs: [String]
    public var role: ArchetypeRole
    
    public var leftPageBlocks: [SpreadBlock]
    public var rightPageBlocks: [SpreadBlock]

    public init(
        id: String,
        displayName: String,
        family: LayoutStrategy,
        pages: Int = 2,
        imageSlots: Int = 0,
        pullQuoteSlots: Int = 0,
        mirror: Bool = true,
        weight: Double = 1.0,
        imageTiers: [String] = [],
        pullQuotePositions: [String] = [],
        carriesMotifs: [String] = [],
        role: ArchetypeRole = .workhorse,
        leftPageBlocks: [SpreadBlock] = [],
        rightPageBlocks: [SpreadBlock] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.family = family
        self.pages = pages
        self.imageSlots = imageSlots
        self.pullQuoteSlots = pullQuoteSlots
        self.mirror = mirror
        self.weight = weight
        self.imageTiers = imageTiers
        self.pullQuotePositions = pullQuotePositions
        self.carriesMotifs = carriesMotifs
        self.role = role
        self.leftPageBlocks = leftPageBlocks
        self.rightPageBlocks = rightPageBlocks
    }
}

extension SpreadArchetype {
    public static let defaults: [SpreadArchetype] = [
        // A1 · Chapter Opener (chapter-opener)
        SpreadArchetype(
            id: "chapter-opener",
            displayName: "章节开篇对开",
            family: .opener,
            pages: 2,
            imageSlots: 0,
            pullQuoteSlots: 0,
            mirror: false,
            weight: 1.0,
            imageTiers: ["none", "small", "medium"],
            pullQuotePositions: ["none"],
            carriesMotifs: ["chapterNumber", "sectionNumber", "header"],
            role: .opener,
            leftPageBlocks: [
                SpreadBlock(role: "chapterNumber", kind: .text, normalizedFrame: Rect(x: 0.1, y: 0.1, width: 0.8, height: 0.35)),
                SpreadBlock(role: "heading1", kind: .text, normalizedFrame: Rect(x: 0.1, y: 0.5, width: 0.8, height: 0.15)),
                SpreadBlock(role: "introduction", kind: .text, normalizedFrame: Rect(x: 0.1, y: 0.7, width: 0.8, height: 0.2))
            ],
            rightPageBlocks: [
                SpreadBlock(role: "header", kind: .component, normalizedFrame: Rect(x: 0.1, y: 0.05, width: 0.8, height: 0.03)),
                SpreadBlock(role: "body", kind: .text, normalizedFrame: Rect(x: 0.1, y: 0.12, width: 0.8, height: 0.78))
            ]
        ),
        
        // A2 · Running Text (running-text)
        SpreadArchetype(
            id: "running-text",
            displayName: "正文流对开",
            family: .textLed,
            pages: 2,
            imageSlots: 0,
            pullQuoteSlots: 1,
            mirror: false,
            weight: 1.5,
            imageTiers: ["none", "small"],
            pullQuotePositions: ["none", "top", "inlineLeft"],
            carriesMotifs: ["header"],
            role: .workhorse,
            leftPageBlocks: [
                SpreadBlock(role: "header", kind: .component, normalizedFrame: Rect(x: 0.1, y: 0.05, width: 0.8, height: 0.03)),
                SpreadBlock(role: "body", kind: .text, normalizedFrame: Rect(x: 0.1, y: 0.12, width: 0.8, height: 0.78))
            ],
            rightPageBlocks: [
                SpreadBlock(role: "header", kind: .component, normalizedFrame: Rect(x: 0.1, y: 0.05, width: 0.8, height: 0.03)),
                SpreadBlock(role: "body", kind: .text, normalizedFrame: Rect(x: 0.1, y: 0.12, width: 0.8, height: 0.78))
            ]
        ),
        
        // A3 · Text-Image Balanced (text-image-balanced)
        SpreadArchetype(
            id: "text-image-balanced",
            displayName: "图文均衡对开",
            family: .balanced,
            pages: 2,
            imageSlots: 1,
            pullQuoteSlots: 0,
            mirror: true,
            weight: 1.2,
            imageTiers: ["medium", "large"],
            pullQuotePositions: ["none", "top"],
            carriesMotifs: ["header", "captionTick"],
            role: .workhorse,
            leftPageBlocks: [
                SpreadBlock(role: "header", kind: .component, normalizedFrame: Rect(x: 0.1, y: 0.05, width: 0.8, height: 0.03)),
                SpreadBlock(role: "body", kind: .text, normalizedFrame: Rect(x: 0.1, y: 0.12, width: 0.8, height: 0.78))
            ],
            rightPageBlocks: [
                SpreadBlock(role: "header", kind: .component, normalizedFrame: Rect(x: 0.1, y: 0.05, width: 0.8, height: 0.03)),
                SpreadBlock(role: "hero", kind: .image, normalizedFrame: Rect(x: 0.1, y: 0.12, width: 0.8, height: 0.45)),
                SpreadBlock(role: "caption", kind: .caption, normalizedFrame: Rect(x: 0.1, y: 0.6, width: 0.8, height: 0.08)),
                SpreadBlock(role: "body", kind: .text, normalizedFrame: Rect(x: 0.1, y: 0.7, width: 0.8, height: 0.2))
            ]
        ),
        
        // A4 · Hero Spread (hero-spread)
        SpreadArchetype(
            id: "hero-spread",
            displayName: "大图气口对开",
            family: .imageLed,
            pages: 2,
            imageSlots: 1,
            pullQuoteSlots: 0,
            mirror: true,
            weight: 0.8,
            imageTiers: ["large", "fullBleed"],
            pullQuotePositions: ["none"],
            carriesMotifs: ["captionTick"],
            role: .breathing,
            leftPageBlocks: [
                SpreadBlock(role: "hero", kind: .image, normalizedFrame: Rect(x: 0.1, y: 0.12, width: 0.9, height: 0.78), bleedAcrossSpine: true)
            ],
            rightPageBlocks: [
                SpreadBlock(role: "hero", kind: .image, normalizedFrame: Rect(x: 0.0, y: 0.12, width: 0.8, height: 0.78), bleedAcrossSpine: true),
                SpreadBlock(role: "caption", kind: .caption, normalizedFrame: Rect(x: 0.1, y: 0.92, width: 0.8, height: 0.05))
            ]
        ),
        
        // A5 · Gallery Grid (gallery-grid)
        SpreadArchetype(
            id: "gallery-grid",
            displayName: "图集并置对开",
            family: .imageLed,
            pages: 2,
            imageSlots: 3,
            pullQuoteSlots: 0,
            mirror: true,
            weight: 0.7,
            imageTiers: ["small"],
            pullQuotePositions: ["none"],
            carriesMotifs: ["captionTick"],
            role: .breathing,
            leftPageBlocks: [
                SpreadBlock(role: "supporting", kind: .image, normalizedFrame: Rect(x: 0.1, y: 0.12, width: 0.8, height: 0.35)),
                SpreadBlock(role: "supporting", kind: .image, normalizedFrame: Rect(x: 0.1, y: 0.52, width: 0.8, height: 0.35))
            ],
            rightPageBlocks: [
                SpreadBlock(role: "supporting", kind: .image, normalizedFrame: Rect(x: 0.1, y: 0.12, width: 0.8, height: 0.35)),
                SpreadBlock(role: "body", kind: .text, normalizedFrame: Rect(x: 0.1, y: 0.52, width: 0.8, height: 0.35))
            ]
        ),
        
        // A6 · PullQuote Feature (pullquote-feature)
        SpreadArchetype(
            id: "pullquote-feature",
            displayName: "抽言强调对开",
            family: .balanced,
            pages: 2,
            imageSlots: 0,
            pullQuoteSlots: 1,
            mirror: true,
            weight: 0.6,
            imageTiers: ["none", "small"],
            pullQuotePositions: ["middle", "top"],
            carriesMotifs: ["pullQuoteRule"],
            role: .feature,
            leftPageBlocks: [
                SpreadBlock(role: "header", kind: .component, normalizedFrame: Rect(x: 0.1, y: 0.05, width: 0.8, height: 0.03)),
                SpreadBlock(role: "body", kind: .text, normalizedFrame: Rect(x: 0.1, y: 0.12, width: 0.8, height: 0.78))
            ],
            rightPageBlocks: [
                SpreadBlock(role: "pullQuote", kind: .text, normalizedFrame: Rect(x: 0.15, y: 0.2, width: 0.7, height: 0.2)),
                SpreadBlock(role: "body", kind: .text, normalizedFrame: Rect(x: 0.1, y: 0.45, width: 0.8, height: 0.45))
            ]
        ),
        
        // A7 · Knowledge Card (knowledge-card)
        SpreadArchetype(
            id: "knowledge-card",
            displayName: "知识卡片对开",
            family: .knowledgeCard,
            pages: 2,
            imageSlots: 0,
            pullQuoteSlots: 0,
            mirror: true,
            weight: 0.5,
            imageTiers: ["none", "small"],
            pullQuotePositions: ["none"],
            carriesMotifs: [],
            role: .reference,
            leftPageBlocks: [
                SpreadBlock(role: "header", kind: .component, normalizedFrame: Rect(x: 0.1, y: 0.05, width: 0.8, height: 0.03)),
                SpreadBlock(role: "body", kind: .text, normalizedFrame: Rect(x: 0.1, y: 0.12, width: 0.8, height: 0.78))
            ],
            rightPageBlocks: [
                SpreadBlock(role: "knowledgeCard", kind: .component, normalizedFrame: Rect(x: 0.1, y: 0.12, width: 0.8, height: 0.78))
            ]
        )
    ]
}
