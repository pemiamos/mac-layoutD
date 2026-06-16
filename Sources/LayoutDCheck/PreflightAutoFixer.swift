import Foundation
import LayoutDCore

public struct PreflightAutoFixResult: Codable, Equatable, Sendable {
    public var project: BookProject
    public var appliedFixes: [PreflightAutoFixKind]
    public var changedAssetIds: [UUID]

    public init(
        project: BookProject,
        appliedFixes: [PreflightAutoFixKind],
        changedAssetIds: [UUID] = []
    ) {
        self.project = project
        self.appliedFixes = appliedFixes
        self.changedAssetIds = changedAssetIds
    }
}

public struct PreflightAutoFixer {
    public init() {}

    public func applyAvailableFixes(
        to project: BookProject,
        issues: [LayoutIssue],
        targetingAssetId: UUID? = nil,
        targetingFrameId: UUID? = nil
    ) -> PreflightAutoFixResult {
        let requestedFixes = Set(issues.compactMap(\.autoFixKind))
        return applyFixes(
            Array(requestedFixes),
            to: project,
            targetingAssetId: targetingAssetId,
            targetingFrameId: targetingFrameId
        )
    }

    public func applyFixes(
        _ fixes: [PreflightAutoFixKind],
        to project: BookProject,
        targetingAssetId: UUID? = nil,
        targetingFrameId: UUID? = nil
    ) -> PreflightAutoFixResult {
        var fixedProject = project
        var appliedFixes: [PreflightAutoFixKind] = []
        var changedAssetIds: Set<UUID> = []

        for fix in fixes.sorted(by: { $0.rawValue < $1.rawValue }) {
            switch fix {
            case .fillMissingPublisher:
                if fixedProject.metadata.publisher?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                    fixedProject.metadata.publisher = "待补充出版社"
                    appliedFixes.append(fix)
                }
            case .fillMissingKeywords:
                if fixedProject.metadata.keywords.isEmpty {
                    fixedProject.metadata.keywords = fallbackKeywords(from: fixedProject.metadata.title)
                    appliedFixes.append(fix)
                }
            case .removeInvalidISBN:
                if let isbn = fixedProject.metadata.isbn?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !isbn.isEmpty,
                   !isValidISBN13ForAutoFix(isbn) {
                    fixedProject.metadata.isbn = nil
                    appliedFixes.append(fix)
                }
            case .fillMissingAssetCaptions:
                var changed = false
                for index in fixedProject.assets.indices {
                    let asset = fixedProject.assets[index]
                    if let targetAssetId = targetingAssetId, asset.id != targetAssetId {
                        continue
                    }
                    if asset.caption?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                        fixedProject.assets[index].caption = fallbackCaption(for: asset)
                        changedAssetIds.insert(asset.id)
                        changed = true
                    }
                }
                if changed {
                    appliedFixes.append(fix)
                }
            case .fillMissingAssetCredits:
                var changed = false
                for index in fixedProject.assets.indices where fixedProject.assets[index].role != .decorative {
                    let asset = fixedProject.assets[index]
                    if let targetAssetId = targetingAssetId, asset.id != targetAssetId {
                        continue
                    }
                    if asset.credit?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                        fixedProject.assets[index].credit = "待补充来源"
                        changedAssetIds.insert(asset.id)
                        changed = true
                    }
                }
                if changed {
                    appliedFixes.append(fix)
                }
            case .clearMissingAssetSourcePaths:
                var changed = false
                for index in fixedProject.assets.indices {
                    let asset = fixedProject.assets[index]
                    if let targetAssetId = targetingAssetId, asset.id != targetAssetId {
                        continue
                    }
                    guard let sourcePath = asset.sourcePath,
                          !FileManager.default.fileExists(atPath: sourcePath) else {
                        continue
                    }
                    fixedProject.assets[index].sourcePath = nil
                    changedAssetIds.insert(asset.id)
                    changed = true
                }
                if changed {
                    appliedFixes.append(fix)
                }
            case .fillMissingAuthor:
                if fixedProject.metadata.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    fixedProject.metadata.author = NSUserName().isEmpty ? "待补充作者" : NSUserName()
                    appliedFixes.append(fix)
                }
            case .fillMissingSubtitle:
                if fixedProject.metadata.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                    fixedProject.metadata.subtitle = "待补充副标题"
                    appliedFixes.append(fix)
                }
            case .removeEmptyTextFrames:
                var planChanged = false
                if let plans = fixedProject.appliedLayoutPlans {
                    var updatedPlans = plans
                    for (pageNum, var plan) in plans {
                        let initialCount = plan.blocks.count
                        if let targetFrameId = targetingFrameId {
                            plan.blocks.removeAll { $0.id == targetFrameId && $0.kind == .text }
                        } else {
                            plan.blocks.removeAll { block in
                                guard block.kind == .text else { return false }
                                switch block.contentReference {
                                case .generated(let text):
                                    return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                case .paragraph(let paraId):
                                    if let para = findParagraph(id: paraId, in: fixedProject) {
                                        return para.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    }
                                    return true
                                case .storyRange(let storyId, let startId, let endId):
                                    let text = collectParagraphTexts(storyId: storyId, startId: startId, endId: endId, in: fixedProject)
                                    return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                default:
                                    return false
                                }
                            }
                        }
                        if plan.blocks.count != initialCount {
                            updatedPlans[pageNum] = plan
                            planChanged = true
                        }
                    }
                    if planChanged {
                        fixedProject.appliedLayoutPlans = updatedPlans
                        appliedFixes.append(fix)
                    }
                }
            case .constrainOutOfBoundsFrames:
                var planChanged = false
                if let plans = fixedProject.appliedLayoutPlans {
                    var updatedPlans = plans
                    for (pageNum, var plan) in plans {
                        var pageChanged = false
                        for idx in plan.blocks.indices {
                            let block = plan.blocks[idx]
                            if let targetFrameId = targetingFrameId, block.id != targetFrameId {
                                continue
                            }
                            
                            var newFrame = block.frame
                            var modified = false
                            
                            if newFrame.width > 1.0 {
                                newFrame.width = 1.0
                                modified = true
                            }
                            if newFrame.height > 1.0 {
                                newFrame.height = 1.0
                                modified = true
                            }
                            if newFrame.x < 0.0 {
                                newFrame.x = 0.0
                                modified = true
                            }
                            if newFrame.y < 0.0 {
                                newFrame.y = 0.0
                                modified = true
                            }
                            if newFrame.x + newFrame.width > 1.0 {
                                newFrame.x = 1.0 - newFrame.width
                                modified = true
                            }
                            if newFrame.y + newFrame.height > 1.0 {
                                newFrame.y = 1.0 - newFrame.height
                                modified = true
                            }
                            
                            if modified {
                                plan.blocks[idx].frame = newFrame
                                pageChanged = true
                            }
                        }
                        if pageChanged {
                            updatedPlans[pageNum] = plan
                            planChanged = true
                        }
                    }
                    if planChanged {
                        fixedProject.appliedLayoutPlans = updatedPlans
                        appliedFixes.append(fix)
                    }
                }
            case .downgradeLowDPIAssetRoles:
                var changed = false
                for index in fixedProject.assets.indices {
                    let asset = fixedProject.assets[index]
                    if let targetAssetId = targetingAssetId, asset.id != targetAssetId {
                        continue
                    }
                    if let effectiveDPI = asset.effectiveDPI(pageSetup: fixedProject.pageSetup), effectiveDPI < 220 {
                        if asset.role == .hero {
                            fixedProject.assets[index].role = .diagram
                            changedAssetIds.insert(asset.id)
                            changed = true
                        } else if asset.role != .decorative {
                            fixedProject.assets[index].role = .decorative
                            changedAssetIds.insert(asset.id)
                            changed = true
                        }
                    }
                }
                if changed {
                    appliedFixes.append(fix)
                }
            }
        }

        if !appliedFixes.isEmpty {
            fixedProject.metadata.modifiedAt = Date()
        }

        return PreflightAutoFixResult(
            project: fixedProject,
            appliedFixes: appliedFixes,
            changedAssetIds: Array(changedAssetIds).sorted { $0.uuidString < $1.uuidString }
        )
    }

    private func fallbackKeywords(from title: String) -> [String] {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? ["待补充关键词"] : [trimmedTitle]
    }

    private func fallbackCaption(for asset: Asset) -> String {
        let stem = URL(fileURLWithPath: asset.fileName).deletingPathExtension().lastPathComponent
        let cleaned = stem
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "待补充图注" : cleaned
    }

    private func findParagraph(id: UUID, in project: BookProject) -> Paragraph? {
        for section in project.sections {
            for story in section.stories {
                if let paragraph = story.paragraphs.first(where: { $0.id == id }) {
                    return paragraph
                }
            }
        }
        return nil
    }

    private func findStory(id: UUID, in project: BookProject) -> Story? {
        for section in project.sections {
            if let story = section.stories.first(where: { $0.id == id }) {
                return story
            }
        }
        return nil
    }

    private func collectParagraphTexts(storyId: UUID, startId: UUID, endId: UUID, in project: BookProject) -> String {
        guard let story = findStory(id: storyId, in: project) else {
            return ""
        }
        var foundStart = false
        var texts: [String] = []
        for paragraph in story.paragraphs {
            if paragraph.id == startId {
                foundStart = true
            }
            if foundStart {
                texts.append(paragraph.text)
            }
            if paragraph.id == endId {
                break
            }
        }
        return texts.joined(separator: "\n")
    }
}

private func isValidISBN13ForAutoFix(_ value: String) -> Bool {
    guard value.allSatisfy({ $0.isNumber || $0 == "-" || $0 == " " }) else {
        return false
    }

    let digits = value.compactMap(\.wholeNumberValue)
    guard digits.count == 13 else {
        return false
    }

    let sum = digits.prefix(12).enumerated().reduce(0) { partial, item in
        partial + item.element * (item.offset.isMultiple(of: 2) ? 1 : 3)
    }
    let checkDigit = (10 - sum % 10) % 10
    return checkDigit == digits[12]
}
