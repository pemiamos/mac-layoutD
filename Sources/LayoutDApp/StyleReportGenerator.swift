import Foundation
import LayoutDCore
import LayoutDEngine
import LayoutDImport
import LayoutDCheck
import LayoutDDesignAI

public struct StyleReportGenerator {
    public static func generateReport(
        project: BookProject,
        document: LaidOutDocument?,
        preflightReport: PreflightReport?,
        specResult: SpecPackImportResult?
    ) -> StyleReport {
        let tokenCoverage = calculateTokenCoverage(project: project, specResult: specResult)
        let motifsChecklist = checkMotifs(project: project, document: document, specResult: specResult)
        let (layoutRepeatCount, repeatViolationCount) = calculateLayoutRepetition(project: project, document: document, specResult: specResult)
        let densityReport = calculateDensities(project: project, document: document)
        
        let overlapsCheck = preflightReport?.issues.contains { issue in
            issue.category == .layout && (issue.message.contains("重叠") || issue.message.lowercased().contains("overlap"))
        } ?? false
        
        let overflowsCheck = preflightReport?.issues.contains { issue in
            issue.category == .layout && (issue.message.contains("溢出") || issue.message.lowercased().contains("overflow"))
        } ?? false
        
        return StyleReport(
            tokenCoverage: tokenCoverage,
            motifsChecklist: motifsChecklist,
            layoutRepeatCount: layoutRepeatCount,
            repeatViolationCount: repeatViolationCount,
            densityReport: densityReport,
            overlapsCheck: overlapsCheck,
            overflowsCheck: overflowsCheck
        )
    }

    private static func calculateTokenCoverage(project: BookProject, specResult: SpecPackImportResult?) -> Double {
        guard let tokens = specResult?.tokens else {
            return 1.0
        }
        
        let colorTokenIDs = tokens.colors.map { $0.id }
        let scalarTokenIDs = tokens.scalars.map { $0.id }
        let allTokenIDs = Set(colorTokenIDs + scalarTokenIDs)
        
        if allTokenIDs.isEmpty {
            return 1.0
        }
        
        var usedTokenIDs = Set<String>()
        
        // Check paragraph styles
        for style in project.styles.paragraphStyles {
            usedTokenIDs.insert(style.colorToken)
            if let fs = style.fontSizeToken { usedTokenIDs.insert(fs) }
            if let lh = style.lineHeightToken { usedTokenIDs.insert(lh) }
            if let fi = style.firstLineIndentToken { usedTokenIDs.insert(fi) }
            if let sb = style.spaceBeforeToken { usedTokenIDs.insert(sb) }
            if let sa = style.spaceAfterToken { usedTokenIDs.insert(sa) }
            
            // Check accent rules
            if let rule = style.accentRule {
                usedTokenIDs.insert(rule.colorToken)
            }
        }
        
        // Check role colors
        if let spec = specResult {
            for (_, val) in spec.roleColors {
                usedTokenIDs.insert(val)
            }
            // Check role decorations
            for (_, decor) in spec.roleDecorations {
                if let c = decor.color { usedTokenIDs.insert(c) }
            }
        }
        
        let intersection = allTokenIDs.intersection(usedTokenIDs)
        return Double(intersection.count) / Double(allTokenIDs.count)
    }

    private static func checkMotifs(
        project: BookProject,
        document: LaidOutDocument?,
        specResult: SpecPackImportResult?
    ) -> [String: Bool] {
        var checklist: [String: Bool] = [:]
        guard let spec = specResult else {
            return checklist
        }
        
        // 1. chapterNumber (ghost motif)
        if spec.motifs.chapterNumber != nil {
            // Check if any frame contains text with style Chapter Title or chapterNumber
            let hasChapter = document?.pages.flatMap(\.frames).contains { frame in
                frame.styleId == "chapterNumber" || frame.styleId == "chapterTitle"
            } ?? false
            checklist["chapterNumber"] = hasChapter
        } else {
            checklist["chapterNumber"] = false
        }
        
        // 2. sectionNumber
        if spec.motifs.sectionNumber != nil {
            let hasSection = document?.pages.flatMap(\.frames).contains { frame in
                frame.styleId == "sectionNumber" || frame.styleId == "heading2"
            } ?? false
            checklist["sectionNumber"] = hasSection
        } else {
            checklist["sectionNumber"] = false
        }
        
        // 3. header
        if spec.motifs.header != nil {
            let hasHeader = document?.pages.flatMap(\.frames).contains { frame in
                frame.kind == .runningHeader
            } ?? false
            checklist["header"] = hasHeader
        } else {
            checklist["header"] = false
        }
        
        // 4. captionTick
        if spec.motifs.captionTick != nil {
            let hasCaption = document?.pages.flatMap(\.frames).contains { frame in
                frame.kind == .caption
            } ?? false
            checklist["captionTick"] = hasCaption
        } else {
            checklist["captionTick"] = false
        }
        
        // 5. headingRule
        if spec.motifs.headingRule != nil {
            let hasHeadingRule = project.styles.paragraphStyles.contains { style in
                (style.id == "heading1" || style.id == "chapterTitle") && style.accentRule?.edge == .bottom
            }
            checklist["headingRule"] = hasHeadingRule
        } else {
            checklist["headingRule"] = false
        }
        
        // 6. pullQuoteRule
        if spec.motifs.pullQuoteRule != nil {
            let hasPullQuoteRule = project.styles.paragraphStyles.contains { style in
                style.id == "pullQuote" && style.accentRule?.edge == .left
            }
            checklist["pullQuoteRule"] = hasPullQuoteRule
        } else {
            checklist["pullQuoteRule"] = false
        }
        
        return checklist
    }

    private static func calculateLayoutRepetition(
        project: BookProject,
        document: LaidOutDocument?,
        specResult: SpecPackImportResult?
    ) -> (maxRepeat: Int, violationCount: Int) {
        guard let doc = document, !doc.pages.isEmpty else {
            return (0, 0)
        }
        
        var strategies: [String] = []
        for page in doc.pages {
            if let plan = project.appliedLayoutPlans?[page.number] {
                strategies.append(plan.strategy.rawValue)
            } else {
                strategies.append("auto_frames_\(page.frames.count)")
            }
        }
        
        var maxRepeat = 0
        var currentRepeat = 0
        var currentStrategy = ""
        
        var repeats: [String: Int] = [:]
        
        for strat in strategies {
            if strat == currentStrategy {
                currentRepeat += 1
            } else {
                if currentRepeat > 0 {
                    maxRepeat = max(maxRepeat, currentRepeat)
                    repeats[currentStrategy] = max(repeats[currentStrategy, default: 0], currentRepeat)
                }
                currentStrategy = strat
                currentRepeat = 1
            }
        }
        if currentRepeat > 0 {
            maxRepeat = max(maxRepeat, currentRepeat)
            repeats[currentStrategy] = max(repeats[currentStrategy, default: 0], currentRepeat)
        }
        
        let limit = specResult?.qualityGates?.maxTemplateRepeat ?? 2
        var violationCount = 0
        for (_, count) in repeats {
            if count > limit {
                violationCount += 1
            }
        }
        
        return (maxRepeat, violationCount)
    }

    private static func calculateDensities(project: BookProject, document: LaidOutDocument?) -> [PageDensity] {
        guard let doc = document else { return [] }
        let pageSize = project.pageSetup.pageSize
        let pageArea = pageSize.width * pageSize.height
        guard pageArea > 0 else { return [] }
        
        var result: [PageDensity] = []
        for page in doc.pages {
            var textArea = 0.0
            var imageArea = 0.0
            
            for frame in page.frames {
                let area = frame.rect.width * frame.rect.height
                if frame.kind == .image {
                    imageArea += area
                } else if frame.kind == .text || frame.kind == .caption || frame.kind == .footnote || frame.kind == .sideNote {
                    textArea += area
                }
            }
            
            let plan = project.appliedLayoutPlans?[page.number]
            let strategy = plan?.strategy.rawValue ?? "auto"
            
            result.append(PageDensity(
                pageNumber: page.number,
                textDensity: min(textArea / pageArea, 1.0),
                imageDensity: min(imageArea / pageArea, 1.0),
                layoutStrategy: strategy
            ))
        }
        
        return result
    }
}
