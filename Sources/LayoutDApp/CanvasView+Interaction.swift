import AppKit
import Foundation
import LayoutDCore

extension CanvasView {
    override var acceptsFirstResponder: Bool { true }

    // MARK: - In-place text editing (double-click)

    func beginInlineEdit(frame: PageFrame, pageRect pRect: CGRect, currentText: String) {
        teardownInlineEditor()
        guard let project else { return }

        let editorRect = CGRect(
            x: pRect.minX + CGFloat(frame.rect.x) * zoomScale,
            y: pRect.minY + CGFloat(frame.rect.y) * zoomScale,
            width: max(CGFloat(frame.rect.width) * zoomScale, 24),
            height: max(CGFloat(frame.rect.height) * zoomScale, 18)
        )

        let editor = InlineTextEditorView(frame: editorRect)
        let style = project.styles.paragraphStyle(id: frame.styleId ?? StyleID.body.rawValue)
        editor.font = NSFont.systemFont(ofSize: max(style.fontSize * zoomScale, 6))
        editor.string = currentText
        editor.textContainerInset = NSSize(width: 2, height: 2)
        editor.isRichText = false
        editor.drawsBackground = true
        editor.backgroundColor = NSColor.white
        editor.textColor = NSColor.black
        editor.wantsLayer = true
        editor.layer?.borderColor = NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.95, alpha: 1).cgColor
        editor.layer?.borderWidth = 1.5

        editor.onCommit = { [weak self] text in
            self?.finishInlineEdit(commit: true, text: text)
        }
        editor.onCancel = { [weak self] in
            self?.finishInlineEdit(commit: false, text: nil)
        }

        addSubview(editor)
        inlineEditor = editor
        inlineEditingFrameId = frame.id
        window?.makeFirstResponder(editor)
        editor.selectAll(nil)
    }

    /// Commits the current inline edit (if any) — used when focus context changes
    /// (tool switch, zoom) so the typed text is preserved rather than dropped.
    func commitInlineEditor() {
        inlineEditor?.commitIfEditing()
    }

    func finishInlineEdit(commit: Bool, text: String?) {
        let frameId = inlineEditingFrameId
        teardownInlineEditor()
        if commit, let frameId, let text {
            onFrameTextEdited?(frameId, text)
        }
    }

    func teardownInlineEditor() {
        guard let editor = inlineEditor else { return }
        inlineEditor = nil
        inlineEditingFrameId = nil
        if editor.window?.firstResponder === editor {
            window?.makeFirstResponder(self)
        }
        editor.removeFromSuperview()
    }

    override func keyDown(with event: NSEvent) {
        guard let chars = event.charactersIgnoringModifiers?.lowercased(),
              let ch = chars.first else {
            super.keyDown(with: event)
            return
        }
        let shift = event.modifierFlags.contains(.shift)
        let hasOtherModifier = event.modifierFlags.intersection([.command, .control, .option]).isEmpty == false

        // Shift+P → page tool (InDesign). All other shortcuts are bare single keys.
        if shift && ch == "p" && !hasOtherModifier {
            onToolShortcut?(.page)
            return
        }
        if !shift && !hasOtherModifier,
           let tool = LayoutTool.allCases.first(where: { $0.shortcutKey == ch }) {
            onToolShortcut?(tool)
            return
        }
        super.keyDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        if activeTool == .hand {
            NSCursor.openHand.set()
            return
        }
        
        if activeTool == .zoom {
            NSCursor.crosshair.set()
            return
        }

        if activeTool == .textFrame || activeTool == .imageFrame {
            NSCursor.crosshair.set()
            return
        }

        if activeTool == .gap {
            detectGap(at: point)
            if let gap = activeGap {
                if gap.isVerticalGap {
                    NSCursor.resizeLeftRight.set()
                } else {
                    NSCursor.resizeUpDown.set()
                }
            } else {
                NSCursor.arrow.set()
            }
            return
        }
        
        NSCursor.arrow.set()
    }

    func detectGap(at point: CGPoint) {
        guard let project, let document else {
            activeGap = nil
            return
        }
        
        let threshold: CGFloat = 30.0 // maximum gap size to detect
        
        for page in document.pages {
            guard let pRect = pageRect(number: page.number) else { continue }
            if pRect.contains(point) {
                let frames = page.frames
                guard frames.count >= 2 else { continue }
                
                for i in 0..<frames.count {
                    for j in 0..<frames.count {
                        if i == j { continue }
                        let frameA = frames[i]
                        let frameB = frames[j]
                        
                        let extraWidthA = (frameA.kind == .text || frameA.kind == .footnote || frameA.kind == .sideNote) ? CGFloat(project.styles.paragraphStyle(id: frameA.styleId ?? StyleID.body.rawValue).fontSize * 0.5) : 0.0
                        let extraWidthB = (frameB.kind == .text || frameB.kind == .footnote || frameB.kind == .sideNote) ? CGFloat(project.styles.paragraphStyle(id: frameB.styleId ?? StyleID.body.rawValue).fontSize * 0.5) : 0.0
                        
                        let rectA = CGRect(
                            x: pRect.minX + CGFloat(frameA.rect.x) * zoomScale,
                            y: pRect.minY + CGFloat(frameA.rect.y) * zoomScale,
                            width: (CGFloat(frameA.rect.width) + extraWidthA) * zoomScale,
                            height: CGFloat(frameA.rect.height) * zoomScale
                        )
                        
                        let rectB = CGRect(
                            x: pRect.minX + CGFloat(frameB.rect.x) * zoomScale,
                            y: pRect.minY + CGFloat(frameB.rect.y) * zoomScale,
                            width: (CGFloat(frameB.rect.width) + extraWidthB) * zoomScale,
                            height: CGFloat(frameB.rect.height) * zoomScale
                        )
                        
                        // Vertical Gap (A left of B)
                        if rectA.maxX < rectB.minX {
                            let gapDist = rectB.minX - rectA.maxX
                            if gapDist > 0 && gapDist < threshold {
                                let overlapYMin = max(rectA.minY, rectB.minY)
                                let overlapYMax = min(rectA.maxY, rectB.maxY)
                                if overlapYMin < overlapYMax {
                                    let gapRect = CGRect(x: rectA.maxX, y: overlapYMin, width: gapDist, height: overlapYMax - overlapYMin)
                                    if gapRect.contains(point) {
                                        activeGap = GapInfo(isVerticalGap: true, rect: gapRect, firstFrameId: frameA.id, secondFrameId: frameB.id)
                                        return
                                    }
                                }
                            }
                        }
                        
                        // Horizontal Gap (A above B)
                        if rectA.maxY < rectB.minY {
                            let gapDist = rectB.minY - rectA.maxY
                            if gapDist > 0 && gapDist < threshold {
                                let overlapXMin = max(rectA.minX, rectB.minX)
                                let overlapXMax = min(rectA.maxX, rectB.maxX)
                                if overlapXMin < overlapXMax {
                                    let gapRect = CGRect(x: overlapXMin, y: rectA.maxY, width: overlapXMax - overlapXMin, height: gapDist)
                                    if gapRect.contains(point) {
                                        activeGap = GapInfo(isVerticalGap: false, rect: gapRect, firstFrameId: frameA.id, secondFrameId: frameB.id)
                                        return
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        activeGap = nil
    }

    override func mouseDown(with event: NSEvent) {
        // A click reaching the canvas means the click was outside the inline editor
        // (clicks inside it are consumed by the editor). Commit any active edit first.
        commitInlineEditor()

        let point = convert(event.locationInWindow, from: nil)
        guard let project, let document else { return }

        // 1. Hand tool
        if activeTool == .hand {
            dragStartPoint = event.locationInWindow
            if let scrollView = enclosingScrollView {
                scrollStartOrigin = scrollView.contentView.bounds.origin
            }
            NSCursor.closedHand.set()
            return
        }

        // 2. Zoom tool
        if activeTool == .zoom {
            let isOption = event.modifierFlags.contains(.option)
            if isOption {
                zoomOut()
            } else {
                zoomIn()
            }
            return
        }

        // Detect clicked page and frame
        var hitFrame: PageFrame? = nil
        var clickedPageNumber: Int? = nil
        var localPoint: CGPoint? = nil

        for page in document.pages {
            guard let pRect = pageRect(number: page.number) else { continue }
            if pRect.contains(point) {
                clickedPageNumber = page.number
                let localX = (point.x - pRect.minX) / zoomScale
                let localY = (point.y - pRect.minY) / zoomScale
                localPoint = CGPoint(x: localX, y: localY)
                
                let nonUnderlays = page.frames.filter { !$0.isUnderlay }
                let underlays = page.frames.filter { $0.isUnderlay }
                let hitTestOrder = nonUnderlays.reversed() + underlays.reversed()

                if let found = hitTestOrder.first(where: { frame in
                    let extraWidth = (frame.kind == .text || frame.kind == .footnote || frame.kind == .sideNote) ? CGFloat(project.styles.paragraphStyle(id: frame.styleId ?? StyleID.body.rawValue).fontSize * 0.5) : 0.0
                    let fRect = CGRect(x: frame.rect.x, y: frame.rect.y, width: frame.rect.width + extraWidth, height: frame.rect.height)
                    return fRect.contains(CGPoint(x: localX, y: localY))
                }) {
                    hitFrame = found
                    break
                }
            }
        }

        // 2.5 Double-click a text/caption frame → edit its text in place (InDesign-style),
        // as long as the page isn't locked. Works with the selection and type tools.
        if event.clickCount == 2,
           (activeTool == .selection || activeTool == .type),
           let frame = hitFrame,
           frame.kind == .text || frame.kind == .caption,
           case .text(let currentText) = frame.content,
           let pageNum = clickedPageNumber,
           !(project.lockedPages ?? []).contains(pageNum),
           let pRect = pageRect(number: pageNum) {
            selectedFrameId = frame.id
            onFrameSelected?(frame.id)
            beginInlineEdit(frame: frame, pageRect: pRect, currentText: currentText)
            return
        }

        // 3. Frame drawing tools: begin a rubber-band rectangle on the clicked page.
        if activeTool == .textFrame || activeTool == .imageFrame
            || activeTool == .rectangle || activeTool == .line {
            if let pageNum = clickedPageNumber, let localPt = localPoint {
                isDrawingFrame = true
                drawFramePageNumber = pageNum
                drawFrameStartLocal = localPt
                drawFrameCurrentRect = Rect(x: localPt.x, y: localPt.y, width: 0, height: 0)
                needsDisplay = true
            }
            return
        }

        // 4. Page tool selection
        if activeTool == .page, let pageNum = clickedPageNumber {
            onPageSelected?(pageNum)
            return
        }

        // 4. Gap tool dragging
        if activeTool == .gap, let gap = activeGap {
            isDraggingGap = true
            onDragStarted?()
            dragStartLocalPoint = point
            
            if let fFrame = findFrame(id: gap.firstFrameId, in: document) {
                dragStartFirstFrameRect = fFrame.frame.rect
            }
            if let sFrame = findFrame(id: gap.secondFrameId, in: document) {
                dragStartSecondFrameRect = sFrame.frame.rect
            }
            return
        }

        // 4.5 Line endpoint drag hit test: grabbing an end of a selected line stretches
        // its length along the axis (the other end stays fixed).
        if activeTool == .selection,
           selectedFrameIds.count <= 1,
           let selId = selectedFrameId,
           let info = findFrame(id: selId, in: document),
           info.frame.kind == .line,
           let pRect = pageRect(number: info.pageNumber) {
            let r = info.frame.rect
            let horizontal = r.width >= r.height
            let cx0 = pRect.minX + CGFloat(r.x) * zoomScale
            let cy0 = pRect.minY + CGFloat(r.y) * zoomScale
            let cw = CGFloat(r.width) * zoomScale
            let ch = CGFloat(r.height) * zoomScale
            let p0 = horizontal ? CGPoint(x: cx0, y: cy0 + ch / 2) : CGPoint(x: cx0 + cw / 2, y: cy0)
            let p1 = horizontal ? CGPoint(x: cx0 + cw, y: cy0 + ch / 2) : CGPoint(x: cx0 + cw / 2, y: cy0 + ch)
            let tol: CGFloat = 8
            func near(_ p: CGPoint) -> Bool { abs(point.x - p.x) <= tol && abs(point.y - p.y) <= tol }
            var hitIndex: Int? = nil
            if near(p0) { hitIndex = 0 } else if near(p1) { hitIndex = 1 }
            if let idx = hitIndex {
                isDraggingLineEndpoint = true
                onDragStarted?()
                lineEndpointFrameId = selId
                lineEndpointHorizontal = horizontal
                lineEndpointOrigRect = r
                if horizontal {
                    lineEndpointFixedCoord = (idx == 0) ? (r.x + r.width) : r.x
                } else {
                    lineEndpointFixedCoord = (idx == 0) ? (r.y + r.height) : r.y
                }
                dragStartLocalPoint = point
                return
            }
        }

        // 5. Selection resize handle hit test (single selection only — group resize
        // isn't supported, matching the handles we draw).
        if activeTool == .selection,
           selectedFrameIds.count <= 1,
           let selId = selectedFrameId,
           let selFrameInfo = findFrame(id: selId, in: document),
           selFrameInfo.frame.kind != .line,
           let pRect = pageRect(number: selFrameInfo.pageNumber) {

            let extraWidth = (selFrameInfo.frame.kind == .text || selFrameInfo.frame.kind == .footnote || selFrameInfo.frame.kind == .sideNote) ? CGFloat(project.styles.paragraphStyle(id: selFrameInfo.frame.styleId ?? StyleID.body.rawValue).fontSize * 0.5) : 0.0
            let rect = CGRect(
                x: pRect.minX + CGFloat(selFrameInfo.frame.rect.x) * zoomScale,
                y: pRect.minY + CGFloat(selFrameInfo.frame.rect.y) * zoomScale,
                width: (CGFloat(selFrameInfo.frame.rect.width) + extraWidth) * zoomScale,
                height: CGFloat(selFrameInfo.frame.rect.height) * zoomScale
            )
            
            let handles = resizeHandles(for: rect)
            if let index = handles.firstIndex(where: { $0.contains(point) }) {
                isResizingFrame = true
                onDragStarted?()
                activeResizeHandleIndex = index
                dragStartFrameRect = selFrameInfo.frame.rect
                dragStartLocalPoint = point
                return
            }
        }

        // 6. Selection or Direct Selection click selection. Direct Selection is
        // intentionally select-only until image crop/focal-point editing exists.
        if activeTool == .selection || activeTool == .directSelection {
            let additive = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)
            if let frame = hitFrame {
                if additive {
                    // Shift/⌘-click: toggle this frame in/out of the selection. No drag.
                    onToggleSelection?(frame.id)
                    return
                }

                if selectedFrameIds.contains(frame.id) && selectedFrameIds.count > 1 {
                    // Plain click on an already multi-selected frame → drag the group,
                    // keeping the selection intact.
                    if activeTool == .selection {
                        beginGroupDrag(anchorPoint: point)
                    }
                    return
                }

                // Plain click → select just this frame.
                selectedFrameId = frame.id
                onFrameSelected?(frame.id)
                if activeTool == .selection {
                    isDraggingFrame = true
                    onDragStarted?()
                    dragStartFrameRect = frame.rect
                    dragStartLocalPoint = point
                }
            } else {
                // Empty canvas → begin a marquee. A plain click with no drag collapses
                // to an empty marquee on mouseUp, which clears the selection as before.
                isMarqueeSelecting = true
                marqueeStartPoint = point
                marqueeRect = CGRect(origin: point, size: .zero)
            }
            return
        }

        // Click on empty canvas to create text/image frames for drawing tools
        if let pageNum = clickedPageNumber, let localPt = localPoint {
            onCanvasClick?(pageNum, localPt)
        }
    }

    /// Captures the start rects of every selected frame so they can be moved
    /// together, and arms the drag state.
    private func beginGroupDrag(anchorPoint: CGPoint) {
        guard let document else { return }
        groupDragStartRects.removeAll()
        for id in selectedFrameIds {
            if let info = findFrame(id: id, in: document) {
                groupDragStartRects[id] = info.frame.rect
            }
        }
        guard !groupDragStartRects.isEmpty else { return }
        isDraggingFrame = true
        // No onDragStarted here: the commit happens once in AppState.applyFrameOrigins
        // (via onFramesDragged). Calling it too would push a redundant undo step.
        dragStartLocalPoint = anchorPoint
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // -1. Marquee (rubber-band) selection: grow the rectangle.
        if isMarqueeSelecting, let start = marqueeStartPoint {
            marqueeRect = CGRect(
                x: min(start.x, point.x),
                y: min(start.y, point.y),
                width: abs(point.x - start.x),
                height: abs(point.y - start.y)
            )
            return
        }

        // Line endpoint drag: move the grabbed end along the axis, other end fixed.
        if isDraggingLineEndpoint, let id = lineEndpointFrameId, let orig = lineEndpointOrigRect,
           let document, let info = findFrame(id: id, in: document),
           let pRect = pageRect(number: info.pageNumber) {
            let localX = Double((point.x - pRect.minX) / zoomScale)
            let localY = Double((point.y - pRect.minY) / zoomScale)
            let fixed = lineEndpointFixedCoord
            let newRect: Rect
            if lineEndpointHorizontal {
                newRect = Rect(x: min(fixed, localX), y: orig.y, width: abs(localX - fixed), height: orig.height)
            } else {
                newRect = Rect(x: orig.x, y: min(fixed, localY), width: orig.width, height: abs(localY - fixed))
            }
            previewFrameRects[id] = newRect
            pendingLineEndpointRect = newRect
            needsDisplay = true
            return
        }

        // 0. Frame drawing tools: grow the rubber-band rectangle (clamped to its page).
        if isDrawingFrame, let start = drawFrameStartLocal, let pageNum = drawFramePageNumber,
           let pRect = pageRect(number: pageNum) {
            let localX = (point.x - pRect.minX) / zoomScale
            let localY = (point.y - pRect.minY) / zoomScale
            if activeTool == .line {
                // Snap the line to whichever axis the drag is longer along, and pin the
                // thin dimension to a fixed rule weight so it reads as a line, not a box.
                let dx = localX - start.x
                let dy = localY - start.y
                let thickness = lineToolThickness
                if abs(dx) >= abs(dy) {
                    drawFrameCurrentRect = Rect(
                        x: Double(min(start.x, localX)), y: Double(start.y),
                        width: Double(abs(dx)), height: thickness
                    )
                } else {
                    drawFrameCurrentRect = Rect(
                        x: Double(start.x), y: Double(min(start.y, localY)),
                        width: thickness, height: Double(abs(dy))
                    )
                }
            } else {
                drawFrameCurrentRect = Rect(
                    x: Double(min(start.x, localX)),
                    y: Double(min(start.y, localY)),
                    width: Double(abs(localX - start.x)),
                    height: Double(abs(localY - start.y))
                )
            }
            needsDisplay = true
            return
        }

        // 1. Hand tool panning
        if activeTool == .hand, let startPt = dragStartPoint, let startOrigin = scrollStartOrigin, let scrollView = enclosingScrollView {
            let dx = event.locationInWindow.x - startPt.x
            let dy = event.locationInWindow.y - startPt.y
            
            var newOrigin = NSPoint(
                x: startOrigin.x - dx,
                y: startOrigin.y - dy
            )
            let maxOriginX = max(0.0, bounds.width - scrollView.contentView.bounds.width)
            let maxOriginY = max(0.0, bounds.height - scrollView.contentView.bounds.height)
            newOrigin.x = min(max(newOrigin.x, 0), maxOriginX)
            newOrigin.y = min(max(newOrigin.y, 0), maxOriginY)
            
            scrollView.contentView.scroll(to: newOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            return
        }

        // 2a. Group move (2+ frames dragged together).
        if isDraggingFrame, !groupDragStartRects.isEmpty, let startPt = dragStartLocalPoint {
            let dx = Double((point.x - startPt.x) / zoomScale)
            let dy = Double((point.y - startPt.y) / zoomScale)
            var updates: [(id: UUID, rect: Rect)] = []
            for (id, startRect) in groupDragStartRects {
                let nextRect = Rect(x: startRect.x + dx, y: startRect.y + dy, width: startRect.width, height: startRect.height)
                previewFrameRects[id] = nextRect
                updates.append((id: id, rect: nextRect))
            }
            pendingGroupDragUpdate = updates
            needsDisplay = true
            return
        }

        // 2. Selection tool moving
        if isDraggingFrame, let selId = selectedFrameId, let startRect = dragStartFrameRect, let startPt = dragStartLocalPoint {
            let dx = Double((point.x - startPt.x) / zoomScale)
            let dy = Double((point.y - startPt.y) / zoomScale)
            let nextRect = Rect(x: startRect.x + dx, y: startRect.y + dy, width: startRect.width, height: startRect.height)
            previewFrameRects[selId] = nextRect
            pendingFrameDragUpdate = (selId, nextRect)
            needsDisplay = true
            return
        }

        // 3. Selection tool resizing
        if isResizingFrame, let selId = selectedFrameId, let startRect = dragStartFrameRect, let startPt = dragStartLocalPoint, let handleIdx = activeResizeHandleIndex {
            let dx = Double((point.x - startPt.x) / zoomScale)
            let dy = Double((point.y - startPt.y) / zoomScale)
            
            var newX = startRect.x
            var newY = startRect.y
            var newW = startRect.width
            var newH = startRect.height
            
            let minW = 10.0
            let minH = 10.0
            
            switch handleIdx {
            case 0: // Top-Left
                let targetW = startRect.width - dx
                let targetH = startRect.height - dy
                if targetW >= minW {
                    newX = startRect.x + dx
                    newW = targetW
                }
                if targetH >= minH {
                    newY = startRect.y + dy
                    newH = targetH
                }
            case 1: // Top-Middle
                let targetH = startRect.height - dy
                if targetH >= minH {
                    newY = startRect.y + dy
                    newH = targetH
                }
            case 2: // Top-Right
                let targetW = startRect.width + dx
                let targetH = startRect.height - dy
                if targetW >= minW {
                    newW = targetW
                }
                if targetH >= minH {
                    newY = startRect.y + dy
                    newH = targetH
                }
            case 3: // Middle-Right
                let targetW = startRect.width + dx
                if targetW >= minW {
                    newW = targetW
                }
            case 4: // Bottom-Right
                let targetW = startRect.width + dx
                let targetH = startRect.height + dy
                if targetW >= minW {
                    newW = targetW
                }
                if targetH >= minH {
                    newH = targetH
                }
            case 5: // Bottom-Middle
                let targetH = startRect.height + dy
                if targetH >= minH {
                    newH = targetH
                }
            case 6: // Bottom-Left
                let targetW = startRect.width - dx
                let targetH = startRect.height + dy
                if targetW >= minW {
                    newX = startRect.x + dx
                    newW = targetW
                }
                if targetH >= minH {
                    newH = targetH
                }
            case 7: // Middle-Left
                let targetW = startRect.width - dx
                if targetW >= minW {
                    newX = startRect.x + dx
                    newW = targetW
                }
            default:
                break
            }
            
            let nextRect = Rect(x: newX, y: newY, width: newW, height: newH)
            previewFrameRects[selId] = nextRect
            pendingFrameDragUpdate = (selId, nextRect)
            needsDisplay = true
            return
        }

        // 4. Gap tool resizing
        if isDraggingGap, let gap = activeGap, let startFirst = dragStartFirstFrameRect, let startSecond = dragStartSecondFrameRect, let startPt = dragStartLocalPoint {
            let dx = Double((point.x - startPt.x) / zoomScale)
            let dy = Double((point.y - startPt.y) / zoomScale)
            
            if gap.isVerticalGap {
                let minW = 10.0
                let targetW1 = startFirst.width + dx
                let targetW2 = startSecond.width - dx
                if targetW1 >= minW && targetW2 >= minW {
                    let firstRect = Rect(x: startFirst.x, y: startFirst.y, width: targetW1, height: startFirst.height)
                    let secondRect = Rect(x: startSecond.x + dx, y: startSecond.y, width: targetW2, height: startSecond.height)
                    previewFrameRects[gap.firstFrameId] = firstRect
                    previewFrameRects[gap.secondFrameId] = secondRect
                    pendingGapDragUpdate = (gap.firstFrameId, firstRect, gap.secondFrameId, secondRect)
                    needsDisplay = true
                }
            } else {
                let minH = 10.0
                let targetH1 = startFirst.height + dy
                let targetH2 = startSecond.height - dy
                if targetH1 >= minH && targetH2 >= minH {
                    let firstRect = Rect(x: startFirst.x, y: startFirst.y, width: startFirst.width, height: targetH1)
                    let secondRect = Rect(x: startSecond.x, y: startSecond.y + dy, width: startSecond.width, height: targetH2)
                    previewFrameRects[gap.firstFrameId] = firstRect
                    previewFrameRects[gap.secondFrameId] = secondRect
                    pendingGapDragUpdate = (gap.firstFrameId, firstRect, gap.secondFrameId, secondRect)
                    needsDisplay = true
                }
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        // Line endpoint drag commit.
        if isDraggingLineEndpoint {
            if let id = lineEndpointFrameId, let rect = pendingLineEndpointRect {
                onLineEndpointDragged?(id, rect)
            }
            isDraggingLineEndpoint = false
            lineEndpointFrameId = nil
            lineEndpointOrigRect = nil
            pendingLineEndpointRect = nil
            previewFrameRects.removeAll()
            dragStartLocalPoint = nil
            needsDisplay = true
            return
        }

        // Frame drawing tools: commit the rubber-band rectangle if it has real size.
        // A line is intentionally thin on one axis, so it only needs real length.
        if isDrawingFrame {
            if let rect = drawFrameCurrentRect, let pageNum = drawFramePageNumber {
                let bigEnough = activeTool == .line
                    ? max(rect.width, rect.height) > 8
                    : (rect.width > 8 && rect.height > 8)
                if bigEnough { onFrameDrawn?(pageNum, rect) }
            }
            isDrawingFrame = false
            drawFrameStartLocal = nil
            drawFramePageNumber = nil
            drawFrameCurrentRect = nil
            needsDisplay = true
            return
        }

        // Marquee selection: select every frame intersecting the rubber-band. A
        // zero-ish rectangle (plain click) resolves to an empty set → clears.
        if isMarqueeSelecting {
            let additive = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)
            let hits = framesIntersecting(marqueeRect)
            if additive {
                onMarqueeSelected?(selectedFrameIds.union(hits))
            } else {
                onMarqueeSelected?(hits)
            }
            isMarqueeSelecting = false
            marqueeStartPoint = nil
            marqueeRect = nil
            needsDisplay = true
            return
        }

        if let group = pendingGroupDragUpdate {
            onFramesDragged?(group)
        } else if let pending = pendingFrameDragUpdate {
            onFrameDragged?(pending.id, pending.rect.x, pending.rect.y, pending.rect.width, pending.rect.height)
        }
        if let pending = pendingGapDragUpdate {
            onGapDragged?(pending.firstId, pending.firstRect, pending.secondId, pending.secondRect)
        }

        groupDragStartRects.removeAll()
        pendingGroupDragUpdate = nil
        isDraggingFrame = false
        isResizingFrame = false
        isDraggingGap = false
        activeResizeHandleIndex = nil
        dragStartFrameRect = nil
        dragStartLocalPoint = nil
        dragStartFirstFrameRect = nil
        dragStartSecondFrameRect = nil
        dragStartPoint = nil
        scrollStartOrigin = nil
        previewFrameRects.removeAll()
        pendingFrameDragUpdate = nil
        pendingGapDragUpdate = nil
        needsDisplay = true
        
        if activeTool == .hand {
            NSCursor.openHand.set()
        }
    }
}

/// A minimal in-place text editor for double-click frame editing. Escape cancels,
/// ⌘Return or clicking away commits, plain Return inserts a newline (frames may hold
/// multi-line paragraph text). Guards against double-firing its callbacks.
final class InlineTextEditorView: NSTextView {
    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?
    private var finished = false

    override func keyDown(with event: NSEvent) {
        // Escape (keyCode 53) → cancel.
        if event.keyCode == 53 {
            finish(commit: false)
            return
        }
        // ⌘Return (keyCode 36) → commit.
        if event.keyCode == 36 && event.modifierFlags.contains(.command) {
            finish(commit: true)
            return
        }
        super.keyDown(with: event)
    }

    override func resignFirstResponder() -> Bool {
        // Clicking away / switching focus commits what was typed.
        finish(commit: true)
        return super.resignFirstResponder()
    }

    /// Commits if still actively editing (used on tool-switch / zoom teardown).
    func commitIfEditing() {
        finish(commit: true)
    }

    private func finish(commit: Bool) {
        guard !finished else { return }
        finished = true
        if commit {
            onCommit?(string)
        } else {
            onCancel?()
        }
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        sqrt(pow(x - other.x, 2) + pow(y - other.y, 2))
    }
}
