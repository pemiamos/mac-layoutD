import Combine
import SwiftUI
import LayoutDCore
import LayoutDEngine
import LayoutDDesignAI
import LayoutDCheck

final class AppState: ObservableObject {
    @Published var project: BookProject {
        didSet {
            recalculateLayout()
        }
    }
    @Published var laidOutDocument: LaidOutDocument?
    @Published var report: PreflightReport?
    @Published var plans: [LayoutPlan] = []
    @Published var currentPageNumber: Int = 1 {
        didSet {
            updateAIPlans()
        }
    }
    @Published var selectedFrameId: UUID?
    @Published var activeTool: LayoutTool = .selection
    
    @Published var activeFormattingTarget: FormattingTarget = .container
    @Published var activeScreenMode: ScreenMode = .normal
    @Published var activeFillColor: Color = Color(nsColor: NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.46, alpha: 1))
    @Published var activeStrokeColor: Color = .black
    @Published var isFillActive: Bool = true

    @Published var frameBackgroundColors: [UUID: Color] = [:]
    @Published var frameStrokeColors: [UUID: Color] = [:]
    @Published var frameTextColors: [UUID: Color] = [:]
    
    let engine = LayoutEngine()
    let inspectorEngine = ProjectInspector()
    let advisor = RuleBasedLayoutAdvisor()
    
    var onLayoutCompleted: ((BookProject, LaidOutDocument) -> Void)?
    
    init(project: BookProject) {
        self.project = project
        recalculateLayout()
    }

    func updateProject(_ update: (inout BookProject) -> Void) {
        var currentProject = project
        update(&currentProject)
        self.project = currentProject
    }
    
    func recalculateLayout() {
        let doc = engine.layout(project: project)
        self.laidOutDocument = doc
        
        let report = inspectorEngine.preflight(project: project, document: doc)
        self.report = report
        
        updateAIPlans()
        
        onLayoutCompleted?(project, doc)
    }
    
    private func updateAIPlans() {
        guard let doc = laidOutDocument else { return }
        let targetPage = min(max(currentPageNumber, 1), max(doc.pages.count, 1))
        let proposedPlans = advisor.proposePlans(for: project, target: .page(targetPage))
        self.plans = proposedPlans
    }
    
    // MARK: - Selected Element Editing Support
    
    func findPageNumber(for frameId: UUID) -> Int? {
        guard let doc = laidOutDocument else { return nil }
        for page in doc.pages {
            if page.frames.contains(where: { $0.id == frameId }) {
                return page.number
            }
        }
        return nil
    }

    func findParagraphByText(_ text: String) -> Paragraph? {
        for section in project.sections {
            for story in section.stories {
                for paragraph in story.paragraphs {
                    if paragraph.text == text {
                        return paragraph
                    }
                }
            }
        }
        return nil
    }

    func freezePageToPlan(pageNum: Int) -> LayoutPlan {
        let pageSize = project.pageSetup.pageSize
        let docPages = laidOutDocument?.pages ?? []
        guard let targetPage = docPages.first(where: { $0.number == pageNum }) else {
            return LayoutPlan(target: .page(pageNum), strategy: .balanced, blocks: [])
        }
        
        var blocks: [LayoutPlanBlock] = []
        
        for frame in targetPage.frames {
            if frame.kind == .text && frame.rect.y == 24 && frame.rect.height == 16 {
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
            }
            
            let ref: ContentReference
            switch frame.content {
            case .asset(let assetId), .spreadAsset(let assetId, _):
                ref = .asset(assetId)
            case .text(let text):
                if let paragraph = findParagraphByText(text) {
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
                contentReference: ref
            )
            blocks.append(block)
        }
        
        return LayoutPlan(target: .page(pageNum), strategy: .balanced, blocks: blocks, notes: ["手动自定义版式页"])
    }

    func updateSelectedFrameCoordinate(x: Double?, y: Double?, width: Double?, height: Double?) {
        guard let frameId = selectedFrameId,
              let pageNum = findPageNumber(for: frameId) else { return }
        
        var currentProject = project
        var plans = currentProject.safeAppliedLayoutPlans
        
        var plan = plans[pageNum] ?? freezePageToPlan(pageNum: pageNum)
        
        if let idx = plan.blocks.firstIndex(where: { $0.id == frameId }) {
            let pageSize = project.pageSetup.pageSize
            var block = plan.blocks[idx]
            block.updateAbsoluteFrame(
                pageSize: pageSize,
                x: x,
                y: y,
                width: width,
                height: height
            )
            
            plan.blocks[idx] = block
            plan.notes = ["手动修改元素坐标"]
            plans[pageNum] = plan
            currentProject.safeAppliedLayoutPlans = plans
            self.project = currentProject
        }
    }

    func updateSelectedFrameImage(assetId: UUID) {
        guard let frameId = selectedFrameId,
              let pageNum = findPageNumber(for: frameId) else { return }
        
        var currentProject = project
        var plans = currentProject.safeAppliedLayoutPlans
        
        var plan = plans[pageNum] ?? freezePageToPlan(pageNum: pageNum)
        
        if let idx = plan.blocks.firstIndex(where: { $0.id == frameId }) {
            var block = plan.blocks[idx]
            block.contentReference = .asset(assetId)
            
            plan.blocks[idx] = block
            plan.notes = ["手动修改图片引用"]
            plans[pageNum] = plan
            currentProject.safeAppliedLayoutPlans = plans
            self.project = currentProject
        }
    }

    func clearCustomLayoutForPage(number: Int) {
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
        guard case .page(let pageNum) = plan.target else { return }

        var currentProject = project
        var plans = currentProject.safeAppliedLayoutPlans
        plans[pageNum] = plan
        currentProject.safeAppliedLayoutPlans = plans
        self.project = currentProject
    }

    func saveCurrentPageLayoutAsTemplate(name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let templateName = trimmedName.isEmpty ? "第 \(currentPageNumber) 页版式" : trimmedName
        let plan = freezePageToPlan(pageNum: currentPageNumber)

        var currentProject = project
        var templates = currentProject.safeSavedLayoutTemplates
        templates.append(SavedLayoutTemplate(name: templateName, plan: plan))
        currentProject.safeSavedLayoutTemplates = templates
        self.project = currentProject
    }

    func applySavedLayoutTemplate(id: UUID, toPage pageNum: Int) {
        guard let template = project.safeSavedLayoutTemplates.first(where: { $0.id == id }) else { return }
        applyLayoutPlan(template.makePlan(target: .page(pageNum)))
    }

    func applyPageLayoutTemplate(_ template: PageLayoutTemplate, toPage pageNum: Int) {
        let primaryAsset = project.assets.first { $0.role != .decorative }
        guard let plan = template.makePlan(
            target: .page(pageNum),
            projectTitle: project.metadata.title,
            primaryAsset: primaryAsset
        ) else { return }
        applyLayoutPlan(plan)
    }

    func renameSavedLayoutTemplate(id: UUID, name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        var currentProject = project
        var templates = currentProject.safeSavedLayoutTemplates
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }

        templates[index].name = trimmedName
        templates[index].modifiedAt = Date()
        currentProject.safeSavedLayoutTemplates = templates
        self.project = currentProject
    }

    func deleteSavedLayoutTemplate(id: UUID) {
        var currentProject = project
        var templates = currentProject.safeSavedLayoutTemplates
        templates.removeAll { $0.id == id }
        currentProject.safeSavedLayoutTemplates = templates
        self.project = currentProject
    }

    func updateSavedLayoutTemplateParameters(
        id: UUID,
        marginOverride: PageMargins?,
        columnsOverride: Int?,
        showHeadersFooters: Bool?
    ) {
        var currentProject = project
        var templates = currentProject.safeSavedLayoutTemplates
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }

        templates[index].plan.marginOverride = marginOverride
        templates[index].plan.columnsOverride = columnsOverride
        templates[index].plan.showHeadersFooters = showHeadersFooters
        templates[index].modifiedAt = Date()
        currentProject.safeSavedLayoutTemplates = templates
        self.project = currentProject
    }

    func applyChapterLayoutTemplate(_ template: ChapterLayoutTemplate, sectionIndex: Int, startPage: Int) -> Int {
        var currentProject = project
        let appliedCount = currentProject.applyChapterLayoutTemplate(
            template,
            sectionIndex: sectionIndex,
            startPage: startPage
        )
        guard appliedCount > 0 else {
            return 0
        }
        self.project = currentProject
        return appliedCount
    }

    func lockPage(number: Int) {
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
        var currentProject = project
        var locked = currentProject.safeLockedPages
        locked.remove(number)
        currentProject.safeLockedPages = locked
        
        self.project = currentProject
    }

    func updateParagraphStyle(
        id: String,
        fontSize: Double? = nil,
        lineHeight: Double? = nil,
        firstLineIndent: Double? = nil,
        spaceBefore: Double? = nil,
        spaceAfter: Double? = nil
    ) {
        var currentProject = project
        var styles = currentProject.styles.paragraphStyles
        if let idx = styles.firstIndex(where: { $0.id == id }) {
            var style = styles[idx]
            if let fSize = fontSize {
                style.fontSize = fSize
            }
            if let lHeight = lineHeight {
                style.lineHeight = lHeight
            }
            if let indent = firstLineIndent {
                style.firstLineIndent = indent
            }
            if let before = spaceBefore {
                style.spaceBefore = before
            }
            if let after = spaceAfter {
                style.spaceAfter = after
            }
            styles[idx] = style
            currentProject.styles.paragraphStyles = styles
            self.project = currentProject
        }
    }

    func applyStyleTemplate(_ template: StyleTemplate) {
        var currentProject = project
        currentProject.styles = template.styleLibrary
        self.project = currentProject
    }

    func applyAvailablePreflightFixes() {
        guard let report else { return }
        let result = PreflightAutoFixer().applyAvailableFixes(
            to: project,
            issues: report.issues
        )
        guard !result.appliedFixes.isEmpty else { return }
        self.project = result.project
    }

    func applyPreflightFix(_ fix: PreflightAutoFixKind, targetingAssetId: UUID? = nil, targetingFrameId: UUID? = nil) {
        let result = PreflightAutoFixer().applyFixes(
            [fix],
            to: project,
            targetingAssetId: targetingAssetId,
            targetingFrameId: targetingFrameId
        )
        guard !result.appliedFixes.isEmpty else { return }
        self.project = result.project
    }

    func applyPreflightFixes(in category: PreflightIssueCategory) {
        guard let report else { return }
        let categoryIssues = report.issues.filter { $0.category == category }
        let result = PreflightAutoFixer().applyAvailableFixes(
            to: project,
            issues: categoryIssues
        )
        guard !result.appliedFixes.isEmpty else { return }
        self.project = result.project
    }

    func insertPage(at pageNum: Int) {
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

    func addFrameToPage(pageNum: Int, kind: LayoutBlockKind, frameRect: Rect) {
        var currentProject = project
        var plans = currentProject.safeAppliedLayoutPlans
        var plan = plans[pageNum] ?? freezePageToPlan(pageNum: pageNum)
        
        let blockId = UUID()
        let blockRef: ContentReference
        let roleName: String
        
        switch kind {
        case .text:
            blockRef = .generated("新建文本内容")
            roleName = "body"
        case .image:
            if let asset = project.assets.first {
                blockRef = .asset(asset.id)
            } else {
                blockRef = .generated("")
            }
            roleName = "image"
        case .caption:
            blockRef = .generated("图注")
            roleName = "caption"
        case .component:
            blockRef = .generated("组件内容")
            roleName = "knowledge-card"
        }
        
        let block = LayoutPlanBlock(
            id: blockId,
            kind: kind,
            role: roleName,
            frame: frameRect,
            contentReference: blockRef
        )
        
        plan.blocks.append(block)
        plans[pageNum] = plan
        currentProject.safeAppliedLayoutPlans = plans
        
        var locked = currentProject.safeLockedPages
        locked.insert(pageNum)
        currentProject.safeLockedPages = locked
        
        self.project = currentProject
        self.selectedFrameId = blockId
    }

    func deleteFrame(id: UUID) {
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

    func applyColorToSelectedFrame(_ color: Color) {
        guard let frameId = selectedFrameId else { return }
        let hex = color.hexString
        if activeFormattingTarget == .container {
            if isFillActive {
                frameBackgroundColors[frameId] = color
            } else {
                frameStrokeColors[frameId] = color
            }
        } else {
            frameTextColors[frameId] = color
        }
        updateSelectedFrameColors(
            backgroundColorHex: activeFormattingTarget == .container && isFillActive ? hex : nil,
            strokeColorHex: activeFormattingTarget == .container && !isFillActive ? hex : nil,
            textColorHex: activeFormattingTarget == .text ? hex : nil,
            shouldClear: false
        )
    }
    
    func removeColorFromSelectedFrame() {
        guard let frameId = selectedFrameId else { return }
        if activeFormattingTarget == .container {
            if isFillActive {
                frameBackgroundColors.removeValue(forKey: frameId)
            } else {
                frameStrokeColors.removeValue(forKey: frameId)
            }
        } else {
            frameTextColors.removeValue(forKey: frameId)
        }
        updateSelectedFrameColors(
            backgroundColorHex: activeFormattingTarget == .container && isFillActive ? "" : nil,
            strokeColorHex: activeFormattingTarget == .container && !isFillActive ? "" : nil,
            textColorHex: activeFormattingTarget == .text ? "" : nil,
            shouldClear: true
        )
    }

    private func updateSelectedFrameColors(
        backgroundColorHex: String?,
        strokeColorHex: String?,
        textColorHex: String?,
        shouldClear: Bool
    ) {
        guard let frameId = selectedFrameId,
              let pageNum = findPageNumber(for: frameId) else {
            recalculateLayout()
            return
        }

        var currentProject = project
        var plans = currentProject.safeAppliedLayoutPlans
        var plan = plans[pageNum] ?? freezePageToPlan(pageNum: pageNum)

        guard let index = plan.blocks.firstIndex(where: { $0.id == frameId }) else {
            recalculateLayout()
            return
        }

        if backgroundColorHex != nil {
            plan.blocks[index].backgroundColorHex = shouldClear ? nil : backgroundColorHex
        }
        if strokeColorHex != nil {
            plan.blocks[index].strokeColorHex = shouldClear ? nil : strokeColorHex
            if !shouldClear, plan.blocks[index].strokeWidth == nil {
                plan.blocks[index].strokeWidth = 1.5
            }
        }
        if textColorHex != nil {
            plan.blocks[index].textColorHex = shouldClear ? nil : textColorHex
        }

        plan.notes = ["手动修改元素颜色"]
        plans[pageNum] = plan
        currentProject.safeAppliedLayoutPlans = plans
        self.project = currentProject
    }

    func updateFrameCoordinate(id: UUID, x: Double?, y: Double?, width: Double?, height: Double?) {
        guard let pageNum = findPageNumber(for: id) else { return }
        var currentProject = project
        var plans = currentProject.safeAppliedLayoutPlans
        var plan = plans[pageNum] ?? freezePageToPlan(pageNum: pageNum)
        
        if let idx = plan.blocks.firstIndex(where: { $0.id == id }) {
            let pageSize = project.pageSetup.pageSize
            var block = plan.blocks[idx]
            block.updateAbsoluteFrame(
                pageSize: pageSize,
                x: x,
                y: y,
                width: width,
                height: height
            )
            plan.blocks[idx] = block
            plan.notes = ["手动修改元素坐标"]
            plans[pageNum] = plan
            currentProject.safeAppliedLayoutPlans = plans
            self.project = currentProject
        }
    }

    func updateGapFrames(firstId: UUID, firstRect: Rect, secondId: UUID, secondRect: Rect) {
        guard let pageNum = findPageNumber(for: firstId) else { return }
        var currentProject = project
        var plans = currentProject.safeAppliedLayoutPlans
        var plan = plans[pageNum] ?? freezePageToPlan(pageNum: pageNum)
        
        let pageSize = project.pageSetup.pageSize
        
        if let idx1 = plan.blocks.firstIndex(where: { $0.id == firstId }) {
            var block1 = plan.blocks[idx1]
            block1.updateAbsoluteFrame(
                pageSize: pageSize,
                x: firstRect.x,
                y: firstRect.y,
                width: firstRect.width,
                height: firstRect.height
            )
            plan.blocks[idx1] = block1
        }
        
        if let idx2 = plan.blocks.firstIndex(where: { $0.id == secondId }) {
            var block2 = plan.blocks[idx2]
            block2.updateAbsoluteFrame(
                pageSize: pageSize,
                x: secondRect.x,
                y: secondRect.y,
                width: secondRect.width,
                height: secondRect.height
            )
            plan.blocks[idx2] = block2
        }
        
        plan.notes = ["间距工具调整元素位置"]
        plans[pageNum] = plan
        currentProject.safeAppliedLayoutPlans = plans
        self.project = currentProject
    }
}

private extension Color {
    var hexString: String {
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let red = Int(round(nsColor.redComponent * 255))
        let green = Int(round(nsColor.greenComponent * 255))
        let blue = Int(round(nsColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
