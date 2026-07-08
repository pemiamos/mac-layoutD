import Foundation
import SwiftUI
import LayoutDCore
import LayoutDEngine
import LayoutDCheck

extension AppState {
    func recalculateLayout() {
        if isAsync {
            triggerRecalculateLayout(debounced: true)
        } else {
            recalculateLayoutSync()
        }
    }

    func recalculateLayoutSync() {
        guard !isPerformingRecalculation else { return }
        isPerformingRecalculation = true
        defer { isPerformingRecalculation = false }

        // Cancel any pending async layouts and increment version
        pendingLayoutWorkItem?.cancel()
        layoutVersion += 1

        let doc = engine.layout(project: project)
        self.laidOutDocument = doc
        
        var baselineProj = project
        baselineProj.appliedLayoutPlans = nil
        baselineProj.qualityMetricsHistory = nil
        baselineProj.styleReport = nil
        if baselineDocument == nil || baselineSource != baselineProj {
            self.baselineDocument = engine.layout(project: baselineProj)
            baselineSource = baselineProj
            baselineLayoutCount += 1
        }
        
        let report = inspectorEngine.preflight(project: project, document: doc, exportOptions: pdfExportOptions)
        self.report = report
        
        updateAIPlans()
        
        let reportObj = StyleReportGenerator.generateReport(
            project: project,
            document: doc,
            preflightReport: report,
            specResult: importedSpecResult
        )
        
        isUpdatingQualityHistory = true
        project.styleReport = reportObj
        isUpdatingQualityHistory = false
        
        if let report = self.report {
            updateQualityHistorySilently(with: report)
        }
        
        onLayoutCompleted?(project, doc)
    }

    func triggerRecalculateLayout(debounced: Bool) {
        pendingLayoutWorkItem?.cancel()
        layoutVersion += 1
        let currentVersion = layoutVersion
        
        let projectSnapshot = self.project
        let pdfExportOptionsSnapshot = self.pdfExportOptions
        let currentPageNumberSnapshot = self.currentPageNumber
        
        var baselineProj = projectSnapshot
        baselineProj.appliedLayoutPlans = nil
        baselineProj.qualityMetricsHistory = nil
        baselineProj.styleReport = nil
        let needsBaselineLayout = self.baselineDocument == nil || self.baselineSource != baselineProj
        let existingBaselineDocument = self.baselineDocument
        
        var workItem: DispatchWorkItem?
        workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            // 1. Layout primary document on background thread
            let doc = self.engine.layout(project: projectSnapshot)
            
            if workItem?.isCancelled == true { return }
            
            // 2. Layout baseline document on background thread if needed
            let baselineDoc: LaidOutDocument
            if needsBaselineLayout {
                baselineDoc = self.engine.layout(project: baselineProj)
            } else if let existing = existingBaselineDocument {
                baselineDoc = existing
            } else {
                baselineDoc = self.engine.layout(project: baselineProj)
            }
            
            if workItem?.isCancelled == true { return }
            
            // 3. Preflight on background thread
            let report = self.inspectorEngine.preflight(project: projectSnapshot, document: doc, exportOptions: pdfExportOptionsSnapshot)
            
            if workItem?.isCancelled == true { return }
            
            // 4. Propose plans on background thread
            let targetPage = min(max(currentPageNumberSnapshot, 1), max(doc.pages.count, 1))
            let proposedPlans = self.advisor.proposePlans(for: projectSnapshot, target: .page(targetPage))
            
            if workItem?.isCancelled == true { return }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                guard self.layoutVersion == currentVersion else { return }
                
                self.isPerformingRecalculation = true
                defer { self.isPerformingRecalculation = false }
                
                self.laidOutDocument = doc
                self.baselineDocument = baselineDoc
                if needsBaselineLayout {
                    self.baselineSource = baselineProj
                    self.baselineLayoutCount += 1
                }
                self.report = report
                self.plans = proposedPlans
                
                let reportObj = StyleReportGenerator.generateReport(
                    project: self.project,
                    document: doc,
                    preflightReport: report,
                    specResult: self.importedSpecResult
                )
                
                self.isUpdatingQualityHistory = true
                self.project.styleReport = reportObj
                self.isUpdatingQualityHistory = false
                
                self.updateQualityHistorySilently(with: report)
                
                self.onLayoutCompleted?(self.project, doc)
            }
        }
        
        pendingLayoutWorkItem = workItem
        
        if let actualWorkItem = workItem {
            if debounced {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: actualWorkItem)
            } else {
                DispatchQueue.global(qos: .userInitiated).async(execute: actualWorkItem)
            }
        }
    }

    func updateQualityHistorySilently(with report: PreflightReport) {
        let metrics = report.qualityMetrics
        let newEntry = QualityHistoryEntry(
            timestamp: Date(),
            pageCount: metrics.pageCount,
            totalFrames: metrics.totalFrames,
            averageFramesPerPage: metrics.averageFramesPerPage,
            planAppliedPages: metrics.planAppliedPages,
            autoLaidOutPages: metrics.autoLaidOutPages,
            lowResolutionAssets: metrics.lowResolutionAssets,
            missingCaptionAssets: metrics.missingCaptionAssets,
            blockingErrors: metrics.blockingErrors,
            layoutIssues: metrics.layoutIssues
        )
        
        var history = project.safeQualityMetricsHistory
        let shouldAdd: Bool
        if let last = history.last {
            shouldAdd = last.pageCount != newEntry.pageCount ||
                        last.totalFrames != newEntry.totalFrames ||
                        last.averageFramesPerPage != newEntry.averageFramesPerPage ||
                        last.planAppliedPages != newEntry.planAppliedPages ||
                        last.autoLaidOutPages != newEntry.autoLaidOutPages ||
                        last.lowResolutionAssets != newEntry.lowResolutionAssets ||
                        last.missingCaptionAssets != newEntry.missingCaptionAssets ||
                        last.blockingErrors != newEntry.blockingErrors ||
                        last.layoutIssues != newEntry.layoutIssues
        } else {
            shouldAdd = true
        }
        
        if shouldAdd {
            history.append(newEntry)
            if history.count > 30 {
                history = Array(history.suffix(30))
            }
            
            isUpdatingQualityHistory = true
            project.qualityMetricsHistory = history
            isUpdatingQualityHistory = false
        }
    }
    
    func updateAIPlans() {
        guard let doc = laidOutDocument else { return }
        let targetPage = min(max(currentPageNumber, 1), max(doc.pages.count, 1))
        let proposedPlans = advisor.proposePlans(for: project, target: .page(targetPage))
        self.plans = proposedPlans
    }

    func freezePageToPlan(pageNum: Int) -> LayoutPlan {
        let pageSize = project.pageSetup.pageSize
        let docPages = laidOutDocument?.pages ?? []
        guard let targetPage = docPages.first(where: { $0.number == pageNum }) else {
            return LayoutPlan(target: .page(pageNum), strategy: .balanced, blocks: [])
        }
        
        var blocks: [LayoutPlanBlock] = []
        
        for frame in targetPage.frames {
            // The running header is regenerated per page by the engine, so it must
            // not be frozen into a saved plan. It is identified by its semantic
            // kind rather than its on-page geometry.
            if frame.kind == .runningHeader {
                continue
            }

            let normX = frame.rect.x / pageSize.width
            let normY = frame.rect.y / pageSize.height
            let normW = frame.rect.width / pageSize.width
            let normH = frame.rect.height / pageSize.height

            let kind: LayoutBlockKind
            switch frame.kind {
            case .text: kind = .text
            case .image: kind = .image
            case .caption: kind = .caption
            case .callout: kind = .component
            case .table: kind = .component
            case .footnote: kind = .text
            case .footnoteDivider: kind = .component
            case .sideNote: kind = .text
            case .runningHeader: kind = .text
            case .rectangle: kind = .rectangle
            case .line: kind = .line
            }
            
            let ref: ContentReference
            switch frame.content {
            case .asset(let assetId), .spreadAsset(let assetId, _):
                ref = .asset(assetId)
            case .text(let text):
                if let paragraphId = frame.sourceParagraphId {
                    ref = .paragraph(paragraphId)
                } else if let paragraph = findParagraphByText(text) {
                    ref = .paragraph(paragraph.id)
                } else {
                    ref = .generated(text)
                }
            case .empty:
                ref = .generated("")
            }
            
            let block = LayoutPlanBlock(
                id: frame.id,
                kind: kind,
                role: frame.kind.rawValue,
                frame: Rect(x: normX, y: normY, width: normW, height: normH),
                contentReference: ref,
                backgroundColorHex: frame.backgroundColorHex,
                strokeColorHex: frame.strokeColorHex,
                strokeWidth: frame.strokeWidth,
                textColorHex: frame.textColorHex,
                maskShape: frame.maskShape,
                styleId: frame.styleId
            )
            blocks.append(block)
        }
        
        return LayoutPlan(target: .page(pageNum), strategy: .balanced, blocks: blocks, notes: ["手动自定义版式页"])
    }

    /// Creates a new text or image frame from a drawn rectangle. Writes a
    /// LayoutPlan block (structured override) on the target page so the frame is
    /// undoable, coexists with AI plans, and exports to IDML like any other block.
    /// `rect` is in page-local points and gets normalized to the page size.
    /// Image frames reference the first project asset (re-pickable in the
    /// inspector); returns false without creating anything if none exists.
    @discardableResult
    func createDrawnFrame(kind: LayoutBlockKind, onPage pageNum: Int, rect: Rect) -> Bool {
        let pageSize = project.pageSetup.pageSize

        let contentRef: ContentReference
        let role: String
        // Shapes carry the current fill/stroke so they're visible the moment they're
        // drawn (a colorless box would be invisible). A rectangle takes both fill and
        // stroke; a line is a true stroke — no fill, its colour and weight ARE the
        // stroke, drawn as a centered segment (see CanvasView/exporters).
        var backgroundColorHex: String? = nil
        var strokeColorHex: String? = nil
        var strokeWidth: Double? = nil
        switch kind {
        case .image:
            guard let firstAsset = project.assets.first else { return false }
            contentRef = .asset(firstAsset.id)
            role = PageFrameKind.image.rawValue
        case .rectangle:
            contentRef = .generated("")
            role = PageFrameKind.rectangle.rawValue
            if isFillActive { backgroundColorHex = Self.printColor(from: activeFillColor).storageString }
            strokeColorHex = Self.printColor(from: activeStrokeColor).storageString
            strokeWidth = 1.0
        case .line:
            contentRef = .generated("")
            role = PageFrameKind.line.rawValue
            strokeColorHex = Self.printColor(from: activeStrokeColor).storageString
            strokeWidth = 1.0
        default:
            contentRef = .generated("")
            role = PageFrameKind.text.rawValue
        }

        commitState()
        var currentProject = project
        var plans = currentProject.safeAppliedLayoutPlans
        var plan = plans[pageNum] ?? freezePageToPlan(pageNum: pageNum)

        let normRect = Rect(
            x: rect.x / pageSize.width,
            y: rect.y / pageSize.height,
            width: rect.width / pageSize.width,
            height: rect.height / pageSize.height
        )
        let block = LayoutPlanBlock(
            kind: kind,
            role: role,
            frame: normRect,
            contentReference: contentRef,
            backgroundColorHex: backgroundColorHex,
            strokeColorHex: strokeColorHex,
            strokeWidth: strokeWidth
        )
        plan.blocks.append(block)
        let noteName: String
        switch kind {
        case .image: noteName = "手动绘制图像框"
        case .rectangle: noteName = "手动绘制矩形"
        case .line: noteName = "手动绘制直线"
        default: noteName = "手动绘制文本框"
        }
        plan.notes = [noteName]
        plans[pageNum] = plan
        currentProject.safeAppliedLayoutPlans = plans
        self.project = currentProject
        self.selectedFrameId = block.id
        return true
    }

    func clearCustomLayoutForPage(number: Int) {
        commitState()
        var currentProject = project
        var plans = currentProject.safeAppliedLayoutPlans
        plans.removeValue(forKey: number)
        currentProject.safeAppliedLayoutPlans = plans
        
        var locked = currentProject.safeLockedPages
        locked.remove(number)
        currentProject.safeLockedPages = locked
        
        self.selectedFrameId = nil
        self.project = currentProject
    }

    func clearCustomLayoutForSelectedFramePage() {
        guard let frameId = selectedFrameId,
              let pageNum = findPageNumber(for: frameId) else { return }
        clearCustomLayoutForPage(number: pageNum)
    }

    func applyLayoutPlan(_ plan: LayoutPlan) {
        commitState()
        guard case .page(let pageNum) = plan.target else { return }

        var currentProject = project
        var plans = currentProject.safeAppliedLayoutPlans
        plans[pageNum] = plan
        currentProject.safeAppliedLayoutPlans = plans
        self.project = currentProject
    }

    func lockPage(number: Int) {
        commitState()
        var currentProject = project
        var locked = currentProject.safeLockedPages
        locked.insert(number)
        currentProject.safeLockedPages = locked
        
        var plans = currentProject.safeAppliedLayoutPlans
        if plans[number] == nil {
            plans[number] = freezePageToPlan(pageNum: number)
        }
        currentProject.safeAppliedLayoutPlans = plans
        
        self.project = currentProject
    }

    func unlockPage(number: Int) {
        commitState()
        var currentProject = project
        var locked = currentProject.safeLockedPages
        locked.remove(number)
        currentProject.safeLockedPages = locked
        
        self.project = currentProject
    }

    func insertPage(at pageNum: Int) {
        commitState()
        var currentProject = project
        let plans = currentProject.safeAppliedLayoutPlans
        
        var newPlans: [Int: LayoutPlan] = [:]
        for (k, v) in plans {
            if k >= pageNum {
                newPlans[k + 1] = v.retargeted(to: .page(k + 1))
            } else {
                newPlans[k] = v
            }
        }
        newPlans[pageNum] = LayoutPlan(
            target: .page(pageNum),
            strategy: .balanced,
            blocks: [],
            notes: ["手动插入空白页"]
        )
        currentProject.safeAppliedLayoutPlans = newPlans
        
        let locked = currentProject.safeLockedPages
        var newLocked = Set<Int>()
        for k in locked {
            if k >= pageNum {
                newLocked.insert(k + 1)
            } else {
                newLocked.insert(k)
            }
        }
        currentProject.safeLockedPages = newLocked
        
        self.project = currentProject
        self.currentPageNumber = pageNum
    }
    
    func deletePage(at pageNum: Int) {
        commitState()
        var currentProject = project
        var plans = currentProject.safeAppliedLayoutPlans
        plans.removeValue(forKey: pageNum)
        
        var newPlans: [Int: LayoutPlan] = [:]
        for (k, v) in plans {
            if k > pageNum {
                newPlans[k - 1] = v.retargeted(to: .page(k - 1))
            } else {
                newPlans[k] = v
            }
        }
        currentProject.safeAppliedLayoutPlans = newPlans
        
        var locked = currentProject.safeLockedPages
        locked.remove(pageNum)
        var newLocked = Set<Int>()
        for k in locked {
            if k > pageNum {
                newLocked.insert(k - 1)
            } else {
                newLocked.insert(k)
            }
        }
        currentProject.safeLockedPages = newLocked
        
        self.project = currentProject
        self.currentPageNumber = max(1, pageNum - 1)
    }

    func deleteFrame(id: UUID) {
        commitState()
        guard let pageNum = findPageNumber(for: id) else { return }
        var currentProject = project
        var plans = currentProject.safeAppliedLayoutPlans
        var plan = plans[pageNum] ?? freezePageToPlan(pageNum: pageNum)
        
        plan.blocks.removeAll { $0.id == id }
        plans[pageNum] = plan
        currentProject.safeAppliedLayoutPlans = plans
        
        var locked = currentProject.safeLockedPages
        locked.insert(pageNum)
        currentProject.safeLockedPages = locked
        
        self.selectedFrameId = nil
        self.project = currentProject
    }
}
