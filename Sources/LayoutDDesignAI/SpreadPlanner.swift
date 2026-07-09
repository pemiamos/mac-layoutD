import Foundation
import LayoutDCore

public struct SpreadPlanner {
    public static func generateFingerprint(
        from project: BookProject,
        linesPerSpread: Int = 64
    ) -> ContentFingerprint {
        var demands: [SpreadDemand] = []
        var currentSpreadIndex = 0
        var currentLines = 0
        var currentImages: [AssetSummary] = []
        var currentPullQuotes = 0
        var currentKnowledgeCards = 0
        var isChapterStart = true
        var isSectionStart = false

        // 线框图面板的「留白比例」把这里调低（每对开装更少行 → 更多留白）；
        // 下限防止极端值把一本书炸成上百对开。默认 64 = 原行为。
        let linesPerSpread = max(16, linesPerSpread)
        
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
            // The first spread of each new section is a chapter start. Section 0
            // is already covered by the initial `isChapterStart = true`. Marking
            // it here (at section START, not end) avoids the trailing partial
            // window inheriting a phantom chapter-start — the previous
            // end-of-section assignment made the LAST spread of a single-section
            // book falsely render as a chapter opener.
            if sectionIndex > 0 {
                isChapterStart = true
                isSectionStart = true
            }
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
                            isChapterStart: isChapterStart,
                            isSectionStart: isSectionStart
                        )
                        demands.append(demand)
                        
                        currentSpreadIndex += 1
                        currentLines = 0
                        currentImages = []
                        currentPullQuotes = 0
                        currentKnowledgeCards = 0
                        isChapterStart = false
                        isSectionStart = false
                    }
                }
            }
            
            // Map project-level assets associated with this section
            if let sectionAssets = assetsBySectionIndex[sectionIndex] {
                for asset in sectionAssets {
                    currentImages.append(AssetSummary(asset: asset))
                }
            }
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
                isChapterStart: isChapterStart,
                isSectionStart: isSectionStart
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
            
            // 1. Force chapter opener (prefer fullbleed-opener when images available)
            if demand.isChapterStart {
                let fullbleedOpener = archetypes.first(where: { $0.id == "fullbleed-opener" })
                let classicOpener = archetypes.first(where: { $0.role == .opener && $0.id != "fullbleed-opener" })
                let opener: SpreadArchetype?
                let imageTier: String
                if demand.imageCount > 0, let fb = fullbleedOpener {
                    opener = fb
                    imageTier = "fullBleed"
                } else if let classic = classicOpener {
                    opener = classic
                    imageTier = "none"
                } else {
                    opener = fullbleedOpener ?? classicOpener
                    imageTier = "none"
                }
                if let opener = opener {
                    let sel = SpreadSelection(
                        spreadIndex: idx,
                        archetypeId: opener.id,
                        mirror: false,
                        imageTier: imageTier,
                        pullQuotePosition: "none"
                    )
                    selections.append(sel)
                    recentFamilies.append(opener.family)
                    if imageTier == "fullBleed" { spreadsSinceBigImage = 0 } else { spreadsSinceBigImage += 1 }
                    continue
                }
            }
            
            // 1.5 Force section opener on section boundaries
            if demand.isSectionStart && !demand.isChapterStart,
               let sectionOpener = archetypes.first(where: { $0.id == "section-opener" }) {
                let sel = SpreadSelection(
                    spreadIndex: idx,
                    archetypeId: sectionOpener.id,
                    mirror: false,
                    imageTier: "none",
                    pullQuotePosition: "none"
                )
                selections.append(sel)
                recentFamilies.append(sectionOpener.family)
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
                        // Slot supply/demand: never assign an image tier when the
                        // spread has no images. Archetypes whose only tiers are
                        // image-bearing (e.g. text-image-balanced) thus produce no
                        // candidate on an image-less spread and fall through to the
                        // workhorse fallback — no phantom empty image frames.
                        if tier != "none" && demand.imageCount == 0 { continue }

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
    
    /// Re-roll a single spread, producing a different selection than the current one.
    /// Uses `rerollCounter + 1` mixed into the seed to guarantee a different PRNG path.
    /// The current archetypeId is heavily penalized (not completely excluded, as it may
    /// be the only viable candidate after hard filtering).
    public static func rerollSpread(
        spreadIndex: Int,
        currentSelections: [SpreadSelection],
        fingerprint: ContentFingerprint,
        archetypes: [SpreadArchetype],
        baseSeed: UInt64 = 42
    ) -> SpreadSelection {
        guard let demandIndex = fingerprint.spreadDemands.firstIndex(where: { $0.spreadIndex == spreadIndex }) else {
            // Spread not found in fingerprint — return current or a default
            if let current = currentSelections.first(where: { $0.spreadIndex == spreadIndex }) {
                return current
            }
            return SpreadSelection(spreadIndex: spreadIndex, archetypeId: archetypes.first?.id ?? "running-text")
        }
        
        let demand = fingerprint.spreadDemands[demandIndex]
        let currentSel = currentSelections.first(where: { $0.spreadIndex == spreadIndex })
        let currentArchetypeId = currentSel?.archetypeId
        let newCounter = (currentSel?.rerollCounter ?? 0) + 1
        
        // Gather neighbor families for monotony check
        var neighborFamilies: [LayoutStrategy] = []
        if spreadIndex > 0, let prev = currentSelections.first(where: { $0.spreadIndex == spreadIndex - 1 }),
           let prevArch = archetypes.first(where: { $0.id == prev.archetypeId }) {
            neighborFamilies.append(prevArch.family)
        }
        if let next = currentSelections.first(where: { $0.spreadIndex == spreadIndex + 1 }),
           let nextArch = archetypes.first(where: { $0.id == next.archetypeId }) {
            neighborFamilies.append(nextArch.family)
        }
        
        // Build candidates with hard filters (same logic as planSpreads)
        var candidates: [(SpreadArchetype, Bool, String, String, Double)] = []
        let allowedArchetypes = demand.isChapterStart ? archetypes : archetypes.filter { $0.role != .opener }
        
        for arch in allowedArchetypes {
            if demand.imageCount > arch.imageSlots { continue }
            if demand.imageCount == 0 && arch.family == .imageLed { continue }
            
            let mirrors = arch.mirror ? [false, true] : [false]
            let tiers = arch.imageTiers.isEmpty ? ["none"] : arch.imageTiers
            let pqPositions = arch.pullQuotePositions.isEmpty ? ["none"] : arch.pullQuotePositions
            
            for mir in mirrors {
                for tier in tiers {
                    if (tier == "large" || tier == "fullBleed") {
                        var dpiOk = true
                        for img in demand.images {
                            let slotInches = 350.0 / 72.0
                            let dpi = Double(img.pixelWidth) / slotInches
                            if dpi < 150.0 {
                                dpiOk = false
                                break
                            }
                        }
                        if !dpiOk { continue }
                    }
                    
                    for pqPos in pqPositions {
                        if demand.pullQuoteCount == 0 && pqPos != "none" { continue }
                        
                        var score = 1.0
                        
                        // Heavy penalty for current archetype to encourage variety
                        if arch.id == currentArchetypeId {
                            score *= 0.1
                        }
                        
                        // Monotony bias against neighbors
                        for nf in neighborFamilies {
                            if arch.family == nf {
                                score -= 0.3
                            }
                        }
                        
                        score *= arch.weight
                        candidates.append((arch, mir, tier, pqPos, max(score, 0.01)))
                    }
                }
            }
        }
        
        // Fallback
        if candidates.isEmpty, let fallback = archetypes.first(where: { $0.role == .workhorse }) {
            candidates.append((fallback, false, "none", "none", 1.0))
        }
        
        // Seeded sampling with reroll counter mixed in
        let sorted = candidates.sorted { $0.4 > $1.4 }
        let topK = Array(sorted.prefix(5)) // Wider top-K for reroll variety
        
        let rerollSeed = baseSeed ^ UInt64(spreadIndex) ^ UInt64(newCounter) &* 2654435761
        var prng = SeededRandom(seed: rerollSeed)
        let chosenIndex = Int(prng.next() % UInt64(topK.count))
        let chosen = topK[chosenIndex]
        
        return SpreadSelection(
            spreadIndex: spreadIndex,
            archetypeId: chosen.0.id,
            mirror: chosen.1,
            imageTier: chosen.2,
            pullQuotePosition: chosen.3,
            rerollCounter: newCounter
        )
    }
}
