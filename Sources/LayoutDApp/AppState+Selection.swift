import Foundation
import SwiftUI
import LayoutDCore
import LayoutDEngine

extension AppState {
    /// Shift/⌘-click: add the frame to the selection (becoming the new anchor) or
    /// remove it if already selected.
    func toggleFrameSelection(_ id: UUID) {
        isMutatingSelectionSet = true
        defer { isMutatingSelectionSet = false }
        if selectedFrameIds.contains(id) {
            selectedFrameIds.remove(id)
            if selectedFrameId == id { selectedFrameId = selectedFrameIds.first }
        } else {
            selectedFrameIds.insert(id)
            selectedFrameId = id
        }
    }

    /// Replace the whole selection at once (marquee rubber-band). `anchor` becomes
    /// the primary; defaults to any member.
    func setSelection(_ ids: Set<UUID>, anchor: UUID? = nil) {
        isMutatingSelectionSet = true
        defer { isMutatingSelectionSet = false }
        selectedFrameIds = ids
        selectedFrameId = anchor ?? ids.first
    }

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

    /// Absolute page rects (points) of every frame in the current selection, with
    /// the page each lives on — the input to alignment/distribution. Read from the
    /// laid-out document, whose `PageFrame.rect` is already in absolute page points.
    func selectedAbsoluteRects() -> [(id: UUID, pageNumber: Int, rect: Rect)] {
        guard let doc = laidOutDocument else { return [] }
        var result: [(id: UUID, pageNumber: Int, rect: Rect)] = []
        for page in doc.pages {
            for frame in page.frames where selectedFrameIds.contains(frame.id) {
                result.append((frame.id, page.number, frame.rect))
            }
        }
        return result
    }

    /// Aligns every selected frame. `.selection` snaps each to the shared bounding
    /// box (multi-frame「对齐对象」); `.page` / `.margin` snap each to its own page's
    /// box independently. Reuses the LayoutPlan-override + undo path, so it's
    /// undoable and exports to IDML like any manual coordinate change. Only moves
    /// frames — sizes are preserved.
    func alignSelection(_ alignment: FrameAlignment, reference: AlignmentReference) {
        let items = selectedAbsoluteRects()
        guard !items.isEmpty else { return }

        let selectionBox = boundingBox(of: items.map { $0.rect })
        let pageSize = project.pageSetup.pageSize

        var origins: [UUID: (x: Double, y: Double)] = [:]
        for item in items {
            let region: Rect
            switch reference {
            case .selection: region = selectionBox
            case .page: region = Rect(x: 0, y: 0, width: pageSize.width, height: pageSize.height)
            case .margin: region = marginRegion(pageNum: item.pageNumber)
            }
            origins[item.id] = alignedFrameOrigin(frame: item.rect, region: region, alignment: alignment)
        }
        applyFrameOrigins(origins, note: "手动对齐元素（\(reference.displayName)·\(alignment.displayName)）")
    }

    /// Distributes the selected frames (3+ required). Extremes stay fixed; the rest
    /// are repositioned so the chosen edge/center — or the gaps — become even.
    func distributeSelection(_ mode: DistributionMode) {
        let items = selectedAbsoluteRects()
        guard items.count >= 3 else { return }
        let origins = distributedOrigins(frames: items.map { (id: $0.id, rect: $0.rect) }, mode: mode)
        applyFrameOrigins(origins, note: "手动分布元素（\(mode.displayName)）")
    }

    /// Writes new top-left origins for a batch of frames in one undoable step,
    /// freezing each touched page to a plan as needed. Shared by alignment,
    /// distribution and group-drag.
    func applyFrameOrigins(_ origins: [UUID: (x: Double, y: Double)], note: String) {
        guard !origins.isEmpty else { return }
        let pageSize = project.pageSetup.pageSize

        commitState()
        var currentProject = project
        var plans = currentProject.safeAppliedLayoutPlans

        for (id, origin) in origins {
            guard let pageNum = findPageNumber(for: id) else { continue }
            var plan = plans[pageNum] ?? freezePageToPlan(pageNum: pageNum)
            guard let idx = plan.blocks.firstIndex(where: { $0.id == id }) else { continue }
            var block = plan.blocks[idx]
            block.updateAbsoluteFrame(pageSize: pageSize, x: origin.x, y: origin.y)
            plan.blocks[idx] = block
            plan.notes = [note]
            plans[pageNum] = plan
        }

        currentProject.safeAppliedLayoutPlans = plans
        self.project = currentProject
    }

    /// The (facing-page-aware) margin box of a page in absolute points. Mirrors the
    /// canvas guides: on facing-page spreads the inner/outer margins swap per parity.
    func marginRegion(pageNum: Int) -> Rect {
        let pageSize = project.pageSetup.pageSize
        let margins = project.resolvedMargins(for: pageNum)
        let leftM: Double
        let rightM: Double
        if project.pageSetup.facingPages {
            leftM = pageNum % 2 == 1 ? margins.left : margins.right
            rightM = pageNum % 2 == 1 ? margins.right : margins.left
        } else {
            leftM = margins.left
            rightM = margins.right
        }
        return Rect(
            x: leftM,
            y: margins.top,
            width: max(pageSize.width - leftM - rightM, 0),
            height: max(pageSize.height - margins.top - margins.bottom, 0)
        )
    }

    func updateSelectedFrameImage(assetId: UUID) {
        commitState()
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

    func updateSelectedFrameText(_ text: String) {
        commitState()
        guard let frameId = selectedFrameId,
              let pageNum = findPageNumber(for: frameId) else { return }

        var currentProject = project
        var plans = currentProject.safeAppliedLayoutPlans
        var plan = plans[pageNum] ?? freezePageToPlan(pageNum: pageNum)

        guard let idx = plan.blocks.firstIndex(where: { $0.id == frameId }) else { return }
        guard plan.blocks[idx].kind == .text || plan.blocks[idx].kind == .caption else {
            return
        }

        plan.blocks[idx].contentReference = .generated(text)
        plan.notes = ["手动修改元素文字"]
        plans[pageNum] = plan
        currentProject.safeAppliedLayoutPlans = plans
        self.project = currentProject
    }

    func updateSelectedFrameCoordinate(x: Double?, y: Double?, width: Double?, height: Double?) {
        commitState()
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
}
