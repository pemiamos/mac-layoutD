import Foundation
import LayoutDCore

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

public struct SpreadPlanner {
    public static func generateFingerprint(from project: BookProject) -> ContentFingerprint {
        var demands: [SpreadDemand] = []
        var currentSpreadIndex = 0
        var currentLines = 0
        var currentImages: [AssetSummary] = []
        var currentPullQuotes = 0
        var currentKnowledgeCards = 0
        var isChapterStart = true
        
        let linesPerSpread = 64
        
        // Build a section-index → [Asset] lookup from project-level assets.
        // Assets carry no explicit section reference, so we distribute them
        // round-robin across sections for fingerprinting purposes.
        var assetsBySectionIndex: [Int: [Asset]] = [:]
        let sectionCount = max(1, project.sections.count)
        for (i, asset) in project.assets.enumerated() {
            let secIdx = i % sectionCount
            assetsBySectionIndex[secIdx, default: []].append(asset)
        }
        
        for (sectionIndex, section) in project.sections.enumerated() {
            for story in section.stories {
                for paragraph in story.paragraphs {
                    // Estimate line count for paragraph (horizontal Chinese layout helper)
                    let chars = paragraph.text.count
                    let estLines = max(1, chars / 35)
                    currentLines += estLines
                    
                    if currentLines >= linesPerSpread {
                        let demand = SpreadDemand(
                            spreadIndex: currentSpreadIndex,
                            bodyLoad: min(Double(currentLines) / Double(linesPerSpread), 1.0),
                            imageCount: currentImages.count,
                            images: currentImages,
                            pullQuoteCount: currentPullQuotes,
                            knowledgeCardCount: currentKnowledgeCards,
                            isChapterStart: isChapterStart
                        )
                        demands.append(demand)
                        
                        currentSpreadIndex += 1
                        currentLines = 0
                        currentImages = []
                        currentPullQuotes = 0
                        currentKnowledgeCards = 0
                        isChapterStart = false
                    }
                }
            }
            
            // Map project-level assets associated with this section
            if let sectionAssets = assetsBySectionIndex[sectionIndex] {
                for asset in sectionAssets {
                    currentImages.append(AssetSummary(asset: asset))
                }
            }
            isChapterStart = true
        }
        
        // Append last window if content remains
        if currentLines > 0 || !currentImages.isEmpty {
            let demand = SpreadDemand(
                spreadIndex: currentSpreadIndex,
                bodyLoad: min(Double(currentLines) / Double(linesPerSpread), 1.0),
                imageCount: currentImages.count,
                images: currentImages,
                pullQuoteCount: currentPullQuotes,
                knowledgeCardCount: currentKnowledgeCards,
                isChapterStart: isChapterStart
            )
            demands.append(demand)
        }
        
        return ContentFingerprint(spreadDemands: demands)
    }
    
    public static func planSpreads(
        fingerprint: ContentFingerprint,
        archetypes: [SpreadArchetype],
        maxSameFamilyRun: Int = 2,
        bigImageEveryMinSpreads: Int = 3,
        minImageDPI: Double = 150.0,
        seed: UInt64 = 42,
        locked: [Int: SpreadSelection] = [:]
    ) -> [SpreadSelection] {
        var selections: [SpreadSelection] = []
        var recentFamilies: [LayoutStrategy] = []
        var spreadsSinceBigImage = 0
        
        for demand in fingerprint.spreadDemands {
            let idx = demand.spreadIndex
            
            // If already locked, adopt selection directly and update rhythm history
            if let lockedSelection = locked[idx] {
                selections.append(lockedSelection)
                if let arch = archetypes.first(where: { $0.id == lockedSelection.archetypeId }) {
                    recentFamilies.append(arch.family)
                    if arch.family == .imageLed || lockedSelection.imageTier == "large" || lockedSelection.imageTier == "fullBleed" {
                        spreadsSinceBigImage = 0
                    } else {
                        spreadsSinceBigImage += 1
                    }
                }
                continue
            }
            
            // 1. Force chapter opener
            if demand.isChapterStart, let opener = archetypes.first(where: { $0.role == .opener }) {
                let sel = SpreadSelection(
                    spreadIndex: idx,
                    archetypeId: opener.id,
                    mirror: false,
                    imageTier: demand.imageCount > 0 ? "small" : "none",
                    pullQuotePosition: "none"
                )
                selections.append(sel)
                recentFamilies.append(opener.family)
                spreadsSinceBigImage += 1
                continue
            }
            
            // 2. Generate candidates & Hard Filters
            var candidates: [(SpreadArchetype, Bool, String, String, Double)] = []
            
            // Determine active/allowed list of archetypes based on family run history
            var allowedArchetypes = archetypes.filter { $0.role != .opener }
            if recentFamilies.count >= maxSameFamilyRun {
                let suffix = recentFamilies.suffix(maxSameFamilyRun)
                if Set(suffix).count == 1, let lastFamily = suffix.last {
                    allowedArchetypes.removeAll { $0.family == lastFamily }
                }
            }
            if allowedArchetypes.isEmpty {
                allowedArchetypes = archetypes.filter { $0.role != .opener }
            }
            
            for arch in allowedArchetypes {
                // Ensure archetype has enough image slots for demand
                if demand.imageCount > arch.imageSlots { continue }
                if demand.imageCount == 0 && arch.family == .imageLed { continue }
                
                let mirrors = arch.mirror ? [false, true] : [false]
                let tiers = arch.imageTiers.isEmpty ? ["none"] : arch.imageTiers
                let pqPositions = arch.pullQuotePositions.isEmpty ? ["none"] : arch.pullQuotePositions
                
                for mir in mirrors {
                    for tier in tiers {
                        // Image DPI filter
                        if (tier == "large" || tier == "fullBleed") {
                            var dpiOk = true
                            for img in demand.images {
                                // Assume target layout size is 350pt wide for large images
                                let slotInches = 350.0 / 72.0
                                let dpi = Double(img.pixelWidth) / slotInches
                                if dpi < minImageDPI {
                                    dpiOk = false
                                    break
                                }
                            }
                            if !dpiOk { continue }
                        }
                        
                        for pqPos in pqPositions {
                            if demand.pullQuoteCount == 0 && pqPos != "none" { continue }
                            
                            // 3. Soft Scoring
                            var score = 1.0
                            
                            // monotony bias
                            if let last = recentFamilies.last, arch.family == last {
                                score -= 0.4
                            }
                            
                            // weight modifier
                            score *= arch.weight
                            
                            candidates.append((arch, mir, tier, pqPos, score))
                        }
                    }
                }
            }
            
            // Fallback if candidates empty
            if candidates.isEmpty, let fallback = archetypes.first(where: { $0.role == .workhorse }) {
                candidates.append((fallback, false, "none", "none", 1.0))
            }
            
            // 4. Seeded top-3 sampling
            let sorted = candidates.sorted { $0.4 > $1.4 }
            let topK = Array(sorted.prefix(3))
            
            let spreadSeed = seed ^ UInt64(idx)
            var prng = SeededRandom(seed: spreadSeed)
            let chosenIndex = Int(prng.next() % UInt64(topK.count))
            let chosen = topK[chosenIndex]
            
            let selection = SpreadSelection(
                spreadIndex: idx,
                archetypeId: chosen.0.id,
                mirror: chosen.1,
                imageTier: chosen.2,
                pullQuotePosition: chosen.3
            )
            selections.append(selection)
            
            // 5. Update history
            recentFamilies.append(chosen.0.family)
            if chosen.0.family == .imageLed || chosen.2 == "large" || chosen.2 == "fullBleed" {
                spreadsSinceBigImage = 0
            } else {
                spreadsSinceBigImage += 1
            }
        }
        
        return selections
    }
    
    public static func materialize(
        selections: [SpreadSelection],
        archetypes: [SpreadArchetype],
        project: BookProject
    ) -> [Int: LayoutPlan] {
        var plans: [Int: LayoutPlan] = [:]
        let setup = project.pageSetup
        
        // Content margins live area
        let contentWidth = setup.pageSize.width - setup.margins.left - setup.margins.right
        let contentHeight = setup.pageSize.height - setup.margins.top - setup.margins.bottom
        
        for selection in selections {
            guard let archetype = archetypes.first(where: { $0.id == selection.archetypeId }) else {
                continue
            }
            
            let leftPageNum = selection.spreadIndex * 2 + 1
            let rightPageNum = leftPageNum + 1
            
            // Build left page blocks
            var leftBlocks: [LayoutPlanBlock] = []
            for block in archetype.leftPageBlocks {
                let frame = block.normalizedFrame
                let rect = Rect(
                    x: setup.margins.left + frame.x * contentWidth,
                    y: setup.margins.top + frame.y * contentHeight,
                    width: frame.width * contentWidth,
                    height: frame.height * contentHeight
                )
                let planBlock = LayoutPlanBlock(
                    id: UUID(),
                    kind: block.kind,
                    role: block.role,
                    frame: rect,
                    contentReference: .generated(block.role)
                )
                leftBlocks.append(planBlock)
            }
            plans[leftPageNum] = LayoutPlan(target: .page(leftPageNum), strategy: archetype.family, blocks: leftBlocks)
            
            // Build right page blocks
            var rightBlocks: [LayoutPlanBlock] = []
            for block in archetype.rightPageBlocks {
                let frame = block.normalizedFrame
                let rect = Rect(
                    x: setup.margins.left + frame.x * contentWidth,
                    y: setup.margins.top + frame.y * contentHeight,
                    width: frame.width * contentWidth,
                    height: frame.height * contentHeight
                )
                let planBlock = LayoutPlanBlock(
                    id: UUID(),
                    kind: block.kind,
                    role: block.role,
                    frame: rect,
                    contentReference: .generated(block.role)
                )
                rightBlocks.append(planBlock)
            }
            plans[rightPageNum] = LayoutPlan(target: .page(rightPageNum), strategy: archetype.family, blocks: rightBlocks)
        }
        
        return plans
    }
}
