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
    
    let engine = LayoutEngine()
    let inspectorEngine = ProjectInspector()
    let advisor = RuleBasedLayoutAdvisor()
    
    var onLayoutCompleted: ((BookProject, LaidOutDocument) -> Void)?
    
    init(project: BookProject) {
        self.project = project
        recalculateLayout()
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
            }
            
            let ref: ContentReference
            switch frame.content {
            case .asset(let assetId):
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
            
            if let newX = x {
                block.frame.x = newX / pageSize.width
            }
            if let newY = y {
                block.frame.y = newY / pageSize.height
            }
            if let newW = width {
                block.frame.width = newW / pageSize.width
            }
            if let newH = height {
                block.frame.height = newH / pageSize.height
            }
            
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
}
