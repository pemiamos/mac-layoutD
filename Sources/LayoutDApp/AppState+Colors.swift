import Foundation
import SwiftUI
import LayoutDCore
import LayoutDEngine

extension AppState {
    func applyColorToSelectedFrame(_ color: Color) {
        commitState()
        guard let frameId = selectedFrameId else { return }
        let hex = Self.printColor(from: color).storageString
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
        commitState()
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

    func beginColorEditBurst(_ frameId: UUID) {
        if colorEditBurstFrame != frameId {
            commitState()               // resets colorEditBurstFrame to nil
            colorEditBurstFrame = frameId
        }
    }

    /// Converts a SwiftUI `Color` to a `PrintColor`, **preserving CMYK** when the
    /// color still carries a CMYK color space — e.g. picked via the standard
    /// ColorPicker's system panel "CMYK Sliders". SwiftUI↔NSColor bridging keeps
    /// the CMYK space (verified: model stays .cmyk), so the quick color well no
    /// longer silently flattens CMYK to RGB. Falls back to sRGB otherwise.
    static func printColor(from color: Color) -> PrintColor {
        let ns = NSColor(color)
        // `.colorSpace`/component access is only safe on component-based colors.
        if ns.type == .componentBased, ns.colorSpace.colorSpaceModel == .cmyk {
            return .cmyk(c: Double(ns.cyanComponent) * 100, m: Double(ns.magentaComponent) * 100,
                         y: Double(ns.yellowComponent) * 100, k: Double(ns.blackComponent) * 100)
        }
        let rgb = ns.usingColorSpace(.sRGB) ?? ns
        return .rgb(r: Int((Double(rgb.redComponent) * 255).rounded()),
                    g: Int((Double(rgb.greenComponent) * 255).rounded()),
                    b: Int((Double(rgb.blueComponent) * 255).rounded()))
    }

    func setSelectedFrameFillColor(_ color: Color) {
        guard let frameId = selectedFrameId else { return }
        beginColorEditBurst(frameId)
        frameBackgroundColors[frameId] = color
        updateSelectedFrameColors(backgroundColorHex: Self.printColor(from: color).storageString, strokeColorHex: nil, textColorHex: nil, shouldClear: false)
    }

    func clearSelectedFrameFillColor() {
        commitState()
        guard let frameId = selectedFrameId else { return }
        frameBackgroundColors.removeValue(forKey: frameId)
        updateSelectedFrameColors(backgroundColorHex: "", strokeColorHex: nil, textColorHex: nil, shouldClear: true)
    }

    func setSelectedFrameStrokeColor(_ color: Color) {
        guard let frameId = selectedFrameId else { return }
        beginColorEditBurst(frameId)
        frameStrokeColors[frameId] = color
        updateSelectedFrameColors(backgroundColorHex: nil, strokeColorHex: Self.printColor(from: color).storageString, textColorHex: nil, shouldClear: false)
    }

    func clearSelectedFrameStrokeColor() {
        commitState()
        guard let frameId = selectedFrameId else { return }
        frameStrokeColors.removeValue(forKey: frameId)
        updateSelectedFrameColors(backgroundColorHex: nil, strokeColorHex: "", textColorHex: nil, shouldClear: true)
    }

    func setSelectedFrameTextColor(_ color: Color) {
        guard let frameId = selectedFrameId else { return }
        beginColorEditBurst(frameId)
        frameTextColors[frameId] = color
        updateSelectedFrameColors(backgroundColorHex: nil, strokeColorHex: nil, textColorHex: Self.printColor(from: color).storageString, shouldClear: false)
    }

    func clearSelectedFrameTextColor() {
        commitState()
        guard let frameId = selectedFrameId else { return }
        frameTextColors.removeValue(forKey: frameId)
        updateSelectedFrameColors(backgroundColorHex: nil, strokeColorHex: nil, textColorHex: "", shouldClear: true)
    }

    func previewColor(_ pc: PrintColor) -> Color {
        if case let .cmyk(c, m, y, k) = pc {
            return Color(nsColor: ICCCMYKProof.rgb(c: c, m: m, y: y, k: k))
        }
        let c = pc.displayRGB
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1)
    }

    func setSelectedFrameFillColor(_ printColor: PrintColor) {
        guard let frameId = selectedFrameId else { return }
        beginColorEditBurst(frameId)
        frameBackgroundColors[frameId] = previewColor(printColor)
        updateSelectedFrameColors(backgroundColorHex: printColor.storageString, strokeColorHex: nil, textColorHex: nil, shouldClear: false)
    }

    func setSelectedFrameStrokeColor(_ printColor: PrintColor) {
        guard let frameId = selectedFrameId else { return }
        beginColorEditBurst(frameId)
        frameStrokeColors[frameId] = previewColor(printColor)
        updateSelectedFrameColors(backgroundColorHex: nil, strokeColorHex: printColor.storageString, textColorHex: nil, shouldClear: false)
    }

    func setSelectedFrameTextColor(_ printColor: PrintColor) {
        guard let frameId = selectedFrameId else { return }
        beginColorEditBurst(frameId)
        frameTextColors[frameId] = previewColor(printColor)
        updateSelectedFrameColors(backgroundColorHex: nil, strokeColorHex: nil, textColorHex: printColor.storageString, shouldClear: false)
    }

    var customSwatches: [PrintSwatch] { project.customSwatches ?? [] }

    /// 把一个颜色存进项目色板库。重复颜色(相同 storageString)不再新增。
    @discardableResult
    func addCustomSwatch(_ color: PrintColor, name: String? = nil) -> PrintSwatch? {
        var currentProject = project
        var list = currentProject.safeCustomSwatches
        guard !list.contains(where: { $0.colorString == color.storageString }) else { return nil }
        commitState()
        let swatch = PrintSwatch(name: name ?? Self.defaultSwatchName(for: color), color: color)
        list.append(swatch)
        currentProject.safeCustomSwatches = list
        self.project = currentProject
        return swatch
    }

    func removeCustomSwatch(id: UUID) {
        commitState()
        var currentProject = project
        currentProject.safeCustomSwatches.removeAll { $0.id == id }
        self.project = currentProject
    }

    static func defaultSwatchName(for color: PrintColor) -> String {
        switch color {
        case let .rgb(r, g, b):
            return String(format: "R=%d G=%d B=%d", r, g, b)
        case .cmyk:
            return color.idmlSwatchName
        }
    }

    func updateSelectedFrameColors(
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

    /// Sets the selected frame's stroke weight (points), InDesign-style. Writes a
    /// plan-block override, undoable. Note the weight only shows if a stroke colour
    /// is also set — matching InDesign, where weight and colour are independent.
    func setSelectedFrameStrokeWidth(_ width: Double) {
        commitState()
        guard let frameId = selectedFrameId,
              let pageNum = findPageNumber(for: frameId) else { return }
        var currentProject = project
        var plans = currentProject.safeAppliedLayoutPlans
        var plan = plans[pageNum] ?? freezePageToPlan(pageNum: pageNum)
        guard let index = plan.blocks.firstIndex(where: { $0.id == frameId }) else { return }
        plan.blocks[index].strokeWidth = max(width, 0)
        plan.notes = ["手动修改描边粗细"]
        plans[pageNum] = plan
        currentProject.safeAppliedLayoutPlans = plans
        self.project = currentProject
    }

    func updateFrameCoordinate(id: UUID, x: Double?, y: Double?, width: Double?, height: Double?) {
        updateFrameCoordinatesWithoutUndo(id: id, x: x, y: y, width: width, height: height)
    }

    /// Commits a line's new bounding rect from an endpoint drag. Uses a tiny minimum
    /// size (lines are thin by nature) and relies on the drag's begin-grouping for
    /// undo, so it doesn't push its own undo step.
    func updateLineGeometry(id: UUID, rect: Rect) {
        guard let pageNum = findPageNumber(for: id) else { return }
        var currentProject = project
        var plans = currentProject.safeAppliedLayoutPlans
        var plan = plans[pageNum] ?? freezePageToPlan(pageNum: pageNum)
        guard let idx = plan.blocks.firstIndex(where: { $0.id == id }) else { return }
        var block = plan.blocks[idx]
        block.updateAbsoluteFrame(
            pageSize: project.pageSetup.pageSize,
            x: rect.x, y: rect.y, width: rect.width, height: rect.height,
            minimumSize: 1
        )
        plan.blocks[idx] = block
        plan.notes = ["手动调整直线端点"]
        plans[pageNum] = plan
        currentProject.safeAppliedLayoutPlans = plans
        self.project = currentProject
    }

    func updateFrameCoordinatesWithoutUndo(id: UUID, x: Double?, y: Double?, width: Double?, height: Double?) {
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
