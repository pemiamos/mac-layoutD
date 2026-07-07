import AppKit
import CoreText
import Foundation
import LayoutDCore

extension CanvasView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let project, let document else { return }

        for page in document.pages {
            draw(page: page, project: project)
        }

        if activeTool == .gap, let gap = activeGap {
            NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.95, alpha: 0.45).setFill()
            let path = NSBezierPath(rect: gap.rect)
            path.fill()

            NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.95, alpha: 0.8).setStroke()
            path.lineWidth = 1.0
            path.stroke()
        }

        drawRubberBandFrameIfNeeded()
        drawMarqueeIfNeeded()
    }

    /// Renders the in-progress marquee (rubber-band selection) rectangle.
    private func drawMarqueeIfNeeded() {
        guard isMarqueeSelecting, let rect = marqueeRect else { return }
        NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.95, alpha: 0.12).setFill()
        rect.fill()
        NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.95, alpha: 0.8).setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1.0
        path.setLineDash([4, 3], count: 2, phase: 0)
        path.stroke()
    }

    /// Renders the in-progress rubber-band rectangle for the frame drawing tools.
    /// Image frames get an InDesign-style diagonal-cross placeholder mark.
    private func drawRubberBandFrameIfNeeded() {
        guard isDrawingFrame,
              let rect = drawFrameCurrentRect,
              let pageNum = drawFramePageNumber,
              let pRect = pageRect(number: pageNum) else { return }

        let screenRect = CGRect(
            x: pRect.minX + CGFloat(rect.x) * zoomScale,
            y: pRect.minY + CGFloat(rect.y) * zoomScale,
            width: CGFloat(rect.width) * zoomScale,
            height: CGFloat(rect.height) * zoomScale
        )
        let color = activeTool == .imageFrame
            ? NSColor(calibratedRed: 0.88, green: 0.38, blue: 0.08, alpha: 1)
            : NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.95, alpha: 1)
        color.setStroke()

        // The line tool previews a dashed segment (anchor → drag point along the
        // snapped axis), not a rectangle.
        if activeTool == .line {
            let path = NSBezierPath()
            if screenRect.width >= screenRect.height {
                path.move(to: CGPoint(x: screenRect.minX, y: screenRect.midY))
                path.line(to: CGPoint(x: screenRect.maxX, y: screenRect.midY))
            } else {
                path.move(to: CGPoint(x: screenRect.midX, y: screenRect.minY))
                path.line(to: CGPoint(x: screenRect.midX, y: screenRect.maxY))
            }
            path.lineWidth = 1.0
            path.setLineDash([4, 3], count: 2, phase: 0)
            path.stroke()
            return
        }

        let path = NSBezierPath(rect: screenRect)
        path.lineWidth = 1.0
        path.setLineDash([4, 3], count: 2, phase: 0)
        path.stroke()

        if activeTool == .imageFrame {
            let cross = NSBezierPath()
            cross.move(to: CGPoint(x: screenRect.minX, y: screenRect.minY))
            cross.line(to: CGPoint(x: screenRect.maxX, y: screenRect.maxY))
            cross.move(to: CGPoint(x: screenRect.maxX, y: screenRect.minY))
            cross.line(to: CGPoint(x: screenRect.minX, y: screenRect.maxY))
            cross.lineWidth = 0.75
            cross.stroke()
        }
    }

    private func draw(page: LaidOutPage, project: BookProject) {
        guard let pageRect = pageRect(number: page.number) else {
            return
        }

        NSColor.white.setFill()
        pageRect.fill()
        NSColor(calibratedWhite: 0.72, alpha: 1).setStroke()
        NSBezierPath(rect: pageRect).stroke()

        // Draw bleed boundary
        if activeScreenMode == .normal {
            let bleedMM = project.pageSetup.bleedMM ?? 3.0
            let bleedPoints = CGFloat(bleedMM * 72.0 / 25.4)
            let bleedOffset = bleedPoints * zoomScale
            let bleedRect = pageRect.insetBy(dx: -bleedOffset, dy: -bleedOffset)
            
            let bleedPath = NSBezierPath(rect: bleedRect)
            bleedPath.lineWidth = 1.0
            let dashedPattern: [CGFloat] = [4.0, 4.0]
            bleedPath.setLineDash(dashedPattern, count: dashedPattern.count, phase: 0.0)
            NSColor.red.setStroke()
            bleedPath.stroke()
        }

        // Draw padlock icon if the page is locked
        if project.safeLockedPages.contains(page.number) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14)
            ]
            "🔒".draw(at: CGPoint(x: pageRect.maxX - 28, y: pageRect.minY + 12), withAttributes: attributes)
        }

        // Draw baseline diff (dashed outlines)
        if activeScreenMode == .normal,
           project.appliedLayoutPlans?[page.number] != nil,
           let baselineDocument,
           let baselinePage = baselineDocument.pages.first(where: { $0.number == page.number }) {
            
            NSColor(calibratedRed: 0.88, green: 0.38, blue: 0.08, alpha: 0.4).setStroke()
            for bFrame in baselinePage.frames {
                if bFrame.kind == .runningHeader {
                    continue
                }
                
                let rect = CGRect(
                    x: pageRect.minX + CGFloat(bFrame.rect.x) * zoomScale,
                    y: pageRect.minY + CGFloat(bFrame.rect.y) * zoomScale,
                    width: CGFloat(bFrame.rect.width) * zoomScale,
                    height: CGFloat(bFrame.rect.height) * zoomScale
                )
                
                let path = NSBezierPath(rect: rect)
                path.lineWidth = 1.0
                let dashedPattern: [CGFloat] = [3.0, 3.0]
                path.setLineDash(dashedPattern, count: dashedPattern.count, phase: 0.0)
                path.stroke()
            }
        }
        
        // Draw override status label
        if activeScreenMode == .normal && project.appliedLayoutPlans?[page.number] != nil {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: NSColor(calibratedRed: 0.88, green: 0.38, blue: 0.08, alpha: 0.8)
            ]
            "已覆写 (Override)".draw(at: CGPoint(x: pageRect.minX + 12, y: pageRect.minY + 12), withAttributes: attributes)
        }

        // Draw spine guide line if facing pages is enabled and it's not the cover page
        if activeScreenMode == .normal && project.pageSetup.facingPages && page.number > 1 {
            NSColor(calibratedWhite: 0.72, alpha: 1).setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.0
            let spineX = page.number % 2 == 0 ? pageRect.maxX : pageRect.minX
            path.move(to: CGPoint(x: spineX, y: pageRect.minY))
            path.line(to: CGPoint(x: spineX, y: pageRect.maxY))
            path.stroke()
        }

        if activeScreenMode == .normal {
            drawGuides(project: project, pageRect: pageRect, pageNumber: page.number)
        }

        let underlayParagraphIds = Set(page.frames.compactMap { frame -> UUID? in
            switch frame.content {
            case .asset(let assetId), .spreadAsset(let assetId, _):
                if let asset = project.assets.first(where: { $0.id == assetId }),
                   asset.effectiveWrapMode == .underlay {
                    return frame.sourceParagraphId
                }
            default:
                break
            }
            return nil
        })

        let isUnderlayFrame = { (frame: PageFrame) -> Bool in
            switch frame.content {
            case .asset(let assetId), .spreadAsset(let assetId, _):
                if let asset = project.assets.first(where: { $0.id == assetId }) {
                    return asset.effectiveWrapMode == .underlay
                }
            default:
                break
            }
            if frame.kind == .caption, let sourceId = frame.sourceParagraphId {
                return underlayParagraphIds.contains(sourceId)
            }
            return false
        }

        // Pass 1: Draw underlay frames
        for frame in page.frames where isUnderlayFrame(frame) {
            draw(frame: frame, project: project, pageRect: pageRect)
        }

        // Pass 2: Draw other frames
        for frame in page.frames where !isUnderlayFrame(frame) {
            draw(frame: frame, project: project, pageRect: pageRect)
        }

        // Draw annotations for this page
        if let annotations = project.annotations {
            let pageAnnotations = annotations.filter { $0.pageNumber == page.number }
            for annotation in pageAnnotations {
                let x = pageRect.minX + CGFloat(annotation.x) * zoomScale
                let y = pageRect.minY + CGFloat(annotation.y) * zoomScale
                
                // Draw a small circle marker
                let markerRadius: CGFloat = 6.0 * zoomScale
                let markerRect = CGRect(x: x - markerRadius, y: y - markerRadius, width: markerRadius * 2, height: markerRadius * 2)
                let path = NSBezierPath(ovalIn: markerRect)
                NSColor.systemOrange.setFill()
                path.fill()
                NSColor.white.setStroke()
                path.lineWidth = 1.5 * zoomScale
                path.stroke()
                
                // Draw a small label box next to it
                let text = annotation.text
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: min(max(8.0 * zoomScale, 7.0), 12.0)),
                    .foregroundColor: NSColor.white
                ]
                let textSize = text.size(withAttributes: attributes)
                
                let labelPadding: CGFloat = 3.0 * zoomScale
                let labelRect = CGRect(
                    x: x + markerRadius + 2.0 * zoomScale,
                    y: y - textSize.height / 2.0,
                    width: textSize.width + labelPadding * 2,
                    height: textSize.height + labelPadding
                )
                
                let labelPath = NSBezierPath(roundedRect: labelRect, xRadius: 3 * zoomScale, yRadius: 3 * zoomScale)
                NSColor.black.withAlphaComponent(0.75).setFill()
                labelPath.fill()
                
                text.draw(at: CGPoint(x: labelRect.minX + labelPadding, y: labelRect.minY + labelPadding / 2.0), withAttributes: attributes)
            }
        }

        drawPageNumber(page.number, project: project, pageRect: pageRect)
    }

    private func drawGuides(project: BookProject, pageRect: CGRect, pageNumber: Int) {
        let setup = project.pageSetup
        let margins = project.resolvedMargins(for: pageNumber)
        let leftMargin: CGFloat
        let rightMargin: CGFloat
        if setup.facingPages {
            leftMargin = CGFloat(pageNumber % 2 == 1 ? margins.left : margins.right)
            rightMargin = CGFloat(pageNumber % 2 == 1 ? margins.right : margins.left)
        } else {
            leftMargin = CGFloat(margins.left)
            rightMargin = CGFloat(margins.right)
        }

        let marginRect = CGRect(
            x: pageRect.minX + leftMargin * zoomScale,
            y: pageRect.minY + CGFloat(margins.top) * zoomScale,
            width: CGFloat(setup.pageSize.width - Double(leftMargin + rightMargin)) * zoomScale,
            height: CGFloat(setup.pageSize.height - margins.top - margins.bottom) * zoomScale
        )
        NSColor(calibratedRed: 0.20, green: 0.48, blue: 0.47, alpha: 0.25).setStroke()
        NSBezierPath(rect: marginRect).stroke()
    }

    private func draw(frame: PageFrame, project: BookProject, pageRect: CGRect) {
        let style: ParagraphStyle
        if frame.kind == .footnote {
            style = ParagraphStyle(
                id: "footnote",
                displayName: "脚注",
                fontName: "Songti SC",
                fontSize: 8.5,
                lineHeight: 11,
                firstLineIndent: 0,
                spaceBefore: 0,
                spaceAfter: 4,
                colorToken: "ink"
            )
        } else if frame.kind == .sideNote {
            style = ParagraphStyle(
                id: "sideNote",
                displayName: "旁注",
                fontName: "Songti SC",
                fontSize: 6.0,
                lineHeight: 8.0,
                firstLineIndent: 0,
                spaceBefore: 0,
                spaceAfter: 2,
                colorToken: "ink"
            )
        } else {
            style = project.styles.paragraphStyle(id: frame.styleId ?? StyleID.body.rawValue)
        }

        let extraWidth = (frame.kind == .text || frame.kind == .footnote || frame.kind == .sideNote || frame.kind == .runningHeader) ? CGFloat(style.fontSize * 0.5) : 0.0

        let effectiveFrameRect = previewFrameRects[frame.id] ?? frame.rect
        let rect = CGRect(
            x: pageRect.minX + CGFloat(effectiveFrameRect.x) * zoomScale,
            y: pageRect.minY + CGFloat(effectiveFrameRect.y) * zoomScale,
            width: (CGFloat(effectiveFrameRect.width) + extraWidth) * zoomScale,
            height: CGFloat(effectiveFrameRect.height) * zoomScale
        )

        // A line is a true stroke, not a filled box: draw a centered segment along its
        // long axis (weight = strokeWidth), and when selected show only two endpoint
        // handles — no bounding rectangle, no 8 resize handles.
        if frame.kind == .line {
            let horizontal = rect.width >= rect.height
            let lineColor = resolvedColor(memoryColor: frameStrokeColors[frame.id], persistedHex: frame.strokeColorHex)
                ?? NSColor.black
            let weightPx = max(CGFloat(frame.strokeWidth ?? 1) * zoomScale, 0.75)
            let p0: CGPoint, p1: CGPoint
            if horizontal {
                p0 = CGPoint(x: rect.minX, y: rect.midY)
                p1 = CGPoint(x: rect.maxX, y: rect.midY)
            } else {
                p0 = CGPoint(x: rect.midX, y: rect.minY)
                p1 = CGPoint(x: rect.midX, y: rect.maxY)
            }
            lineColor.setStroke()
            let path = NSBezierPath()
            path.move(to: p0)
            path.line(to: p1)
            path.lineWidth = weightPx
            path.stroke()

            if activeScreenMode == .normal && selectedFrameIds.contains(frame.id) {
                NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.95, alpha: 1).setStroke()
                let hl = NSBezierPath()
                hl.move(to: p0); hl.line(to: p1)
                hl.lineWidth = 1.0
                hl.stroke()
                if selectedFrameIds.count == 1 {
                    NSColor.white.setFill()
                    for pt in [p0, p1] {
                        let h = CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6)
                        let hp = NSBezierPath(rect: h)
                        hp.fill()
                        hp.stroke()
                    }
                }
            }
            return
        }

        if frame.kind == .footnoteDivider {
            NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.14, alpha: 1).setFill()
            rect.fill()
            return
        }

        // Draw background color override if any
        if let bgColor = resolvedColor(memoryColor: frameBackgroundColors[frame.id], persistedHex: frame.backgroundColorHex) {
            bgColor.setFill()
            let path = maskPath(in: rect, shape: frame.maskShape)
            path.fill()
        }

        switch frame.content {
        case .text(let text):
            let textColor = resolvedColor(memoryColor: frameTextColors[frame.id], persistedHex: frame.textColorHex)
            let hasBg = resolvedColor(memoryColor: frameBackgroundColors[frame.id], persistedHex: frame.backgroundColorHex) != nil
            if let componentStyle = project.styles.componentStyle(for: frame.kind) {
                if !hasBg {
                    drawComponentBackground(componentStyle, project: project, rect: rect)
                }
                let componentTextColor = textColor ?? componentStyle.resolvedTextColorHex(project: project).flatMap(NSColor.fromHex)
                if frame.kind == .table {
                    drawTable(
                        text,
                        style: style,
                        componentStyle: componentStyle,
                        project: project,
                        rect: rect,
                        textColor: componentTextColor
                    )
                } else {
                    drawText(
                        text,
                        styleId: frame.styleId,
                        project: project,
                        rect: rect.insetBy(
                            dx: CGFloat(componentStyle.textInsetX) * zoomScale,
                            dy: CGFloat(componentStyle.textInsetY) * zoomScale
                        ),
                        kind: frame.kind,
                        textColorOverride: componentTextColor,
                        applyDefaultInset: false,
                        sourceParagraphId: frame.sourceParagraphId,
                        tableOfContentsEntries: frame.tableOfContentsEntries,
                        exclusionRects: frame.exclusionRects,
                        frameRect: frame.rect
                    )
                }
            } else {
                drawText(
                    text,
                    styleId: frame.styleId,
                    project: project,
                    rect: rect,
                    kind: frame.kind,
                    textColorOverride: textColor,
                    sourceParagraphId: frame.sourceParagraphId,
                    tableOfContentsEntries: frame.tableOfContentsEntries,
                    exclusionRects: frame.exclusionRects,
                    frameRect: frame.rect
                )
            }
        case .asset(let assetId):
            drawAssetPlaceholder(assetId: assetId, isLeftHalf: nil, project: project, rect: rect, maskShape: frame.maskShape)
        case .spreadAsset(let assetId, let isLeftHalf):
            drawAssetPlaceholder(assetId: assetId, isLeftHalf: isLeftHalf, project: project, rect: rect, maskShape: frame.maskShape)
        case .empty:
            break
        }

        // Draw stroke color override if any
        if let strokeColor = resolvedColor(memoryColor: frameStrokeColors[frame.id], persistedHex: frame.strokeColorHex) {
            strokeColor.setStroke()
            let path = maskPath(in: rect, shape: frame.maskShape)
            path.lineWidth = CGFloat(frame.strokeWidth ?? 1.5)
            path.stroke()
        }

        if activeScreenMode == .normal {
            if frame.id == highlightedFrameId {
                NSColor.red.withAlphaComponent(0.15).setFill()
                rect.fill()
                NSColor.red.setStroke()
                let path = NSBezierPath(rect: rect)
                path.lineWidth = 2.0
                path.stroke()
            }

            if selectedFrameIds.contains(frame.id) {
                NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.95, alpha: 0.15).setFill()
                rect.fill()
                NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.95, alpha: 1).setStroke()
                let path = NSBezierPath(rect: rect)
                path.lineWidth = 2.0
                path.stroke()

                // Resize handles only when a single frame is selected — group resize
                // isn't supported yet, so drawing handles on a multi-selection would
                // imply an action that does nothing.
                if activeTool == .selection && selectedFrameIds.count == 1 {
                    let handles = resizeHandles(for: rect)
                    NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.95, alpha: 1).setStroke()
                    NSColor.white.setFill()
                    for hRect in handles {
                        let hPath = NSBezierPath(rect: hRect)
                        hPath.lineWidth = 1.0
                        hPath.fill()
                        hPath.stroke()
                    }
                }
            }

            if activeTool == .directSelection && frame.id == selectedFrameId && frame.kind == .image {
                if case .asset(let assetId) = frame.content,
                   let asset = project.assets.first(where: { $0.id == assetId }),
                   let image = loadImage(asset: asset) {
                    let imageSize = image.size
                    if imageSize.width > 0 && imageSize.height > 0 {
                        let imageAspect = imageSize.width / imageSize.height
                        let rectAspect = rect.width / rect.height
                        let drawRect: CGRect
                        if imageAspect > rectAspect {
                            let height = rect.width / imageAspect
                            drawRect = CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
                        } else {
                            let width = rect.height * imageAspect
                            drawRect = CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: rect.height)
                        }

                        NSColor.orange.setStroke()
                        let outlinePath = NSBezierPath(rect: drawRect)
                        outlinePath.lineWidth = 1.5
                        outlinePath.stroke()

                        let center = CGPoint(x: drawRect.midX, y: drawRect.midY)
                        let outerRect = CGRect(x: center.x - 12, y: center.y - 12, width: 24, height: 24)
                        let innerRect = CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16)

                        NSColor.orange.withAlphaComponent(0.2).setFill()
                        NSBezierPath(ovalIn: outerRect).fill()

                        NSColor.orange.setStroke()
                        let outerPath = NSBezierPath(ovalIn: outerRect)
                        outerPath.lineWidth = 1.5
                        outerPath.stroke()

                        let innerPath = NSBezierPath(ovalIn: innerRect)
                        innerPath.lineWidth = 1.0
                        innerPath.stroke()
                    }
                }
            }
        }
    }

    private func drawComponentBackground(_ style: ComponentStyle, project: BookProject, rect: CGRect) {
        if let fillHex = style.resolvedFillColorHex(project: project), let fill = NSColor.fromHex(fillHex) {
            fill.setFill()
            rect.fill()
        }
        if let strokeHex = style.resolvedStrokeColorHex(project: project), let stroke = NSColor.fromHex(strokeHex), style.strokeWidth > 0 {
            stroke.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = CGFloat(style.strokeWidth) * zoomScale
            path.stroke()
        }
        if let accentHex = style.resolvedAccentColorHex(project: project), let accent = NSColor.fromHex(accentHex), style.accentWidth > 0 {
            accent.setFill()
            CGRect(
                x: rect.minX,
                y: rect.minY,
                width: CGFloat(style.accentWidth) * zoomScale,
                height: rect.height
            ).fill()
        }
    }

    private func drawTable(
        _ text: String,
        style: ParagraphStyle,
        componentStyle: ComponentStyle,
        project: BookProject,
        rect: CGRect,
        textColor: NSColor?
    ) {
        let tableData = TableLayoutHelper.parseTableText(text)
        let colCount = tableData.columnCount
        let rowCount = tableData.rows.count
        guard colCount > 0, rowCount > 0 else { return }
        
        let strokeColor = resolvedColor(memoryColor: frameStrokeColors[NSUUID() as UUID], persistedHex: componentStyle.strokeColorHex) ?? NSColor.black
        let strokeWidth = CGFloat(componentStyle.strokeWidth) * zoomScale
        
        let colWidths = TableLayoutHelper.allocateColumnWidths(
            tableData: tableData,
            totalWidth: Double(rect.width),
            fontName: style.fontName,
            fontSize: style.fontSize,
            zoomScale: zoomScale
        )
        let rowHeights = TableLayoutHelper.calculateRowHeights(
            tableData: tableData,
            colWidths: colWidths,
            style: style,
            textInsetX: componentStyle.textInsetX,
            textInsetY: componentStyle.textInsetY,
            zoomScale: zoomScale
        )
        
        guard let cgContext = NSGraphicsContext.current?.cgContext else { return }
        
        // Draw backgrounds and text (from top to bottom)
        var currentY = rect.maxY
        for r in 0..<rowCount {
            let rowHeight = CGFloat(rowHeights[r])
            let cells = tableData.rows[r]
            currentY -= rowHeight
            
            var currentX = rect.minX
            for c in 0..<colCount {
                let cellWidth = CGFloat(colWidths[c])
                let cellRect = CGRect(x: currentX, y: currentY, width: cellWidth, height: rowHeight)
                
                cgContext.saveGState()
                if r == 0 {
                    if let accentHex = componentStyle.accentColorHex, let headerColor = NSColor.fromHex(accentHex) {
                        headerColor.withAlphaComponent(0.15).setFill()
                    } else if let fillHex = componentStyle.fillColorHex, let fillColor = NSColor.fromHex(fillHex) {
                        fillColor.withAlphaComponent(0.3).setFill()
                    } else {
                        NSColor(white: 0.9, alpha: 1).setFill()
                    }
                } else {
                    if let fillHex = componentStyle.fillColorHex, let fillColor = NSColor.fromHex(fillHex) {
                        fillColor.setFill()
                    } else {
                        NSColor.white.setFill()
                    }
                }
                cgContext.fill(cellRect)
                cgContext.restoreGState()
                
                let cellText = c < cells.count ? cells[c] : ""
                if !cellText.isEmpty {
                    let insetX = CGFloat(componentStyle.textInsetX) * zoomScale
                    let insetY = CGFloat(componentStyle.textInsetY) * zoomScale
                    let textRect = cellRect.insetBy(dx: insetX, dy: insetY)
                    
                    cgContext.saveGState()
                    cgContext.translateBy(x: textRect.minX, y: textRect.maxY)
                    cgContext.scaleBy(x: 1.0, y: -1.0)
                    
                    let attrString = ChineseTypesetting.makeAttributedString(
                        text: cellText,
                        style: style,
                        foregroundColor: (textColor ?? NSColor.black).cgColor,
                        zoomScale: zoomScale
                    )
                    
                    let path = CGPath(rect: CGRect(x: 0, y: 0, width: textRect.width, height: textRect.height), transform: nil)
                    let framesetter = CTFramesetterCreateWithAttributedString(attrString)
                    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
                    
                    cgContext.textMatrix = .identity
                    CTFrameDraw(frame, cgContext)
                    cgContext.restoreGState()
                }
                
                currentX += cellWidth
            }
        }
        
        // Draw grid lines
        cgContext.saveGState()
        cgContext.setStrokeColor(strokeColor.cgColor)
        cgContext.setLineWidth(strokeWidth)
        
        // Outer border
        cgContext.stroke(rect)
        
        // Horizontal grid lines
        var currentLineY = rect.maxY
        for r in 0..<(rowCount - 1) {
            currentLineY -= CGFloat(rowHeights[r])
            cgContext.move(to: CGPoint(x: rect.minX, y: currentLineY))
            cgContext.addLine(to: CGPoint(x: rect.maxX, y: currentLineY))
            cgContext.strokePath()
        }
        
        // Vertical grid lines
        var currentLineX = rect.minX
        for c in 0..<(colCount - 1) {
            currentLineX += CGFloat(colWidths[c])
            cgContext.move(to: CGPoint(x: currentLineX, y: rect.minY))
            cgContext.addLine(to: CGPoint(x: currentLineX, y: rect.maxY))
            cgContext.strokePath()
        }
        
        cgContext.restoreGState()
    }

    private func drawText(
        _ text: String,
        styleId: String?,
        project: BookProject,
        rect: CGRect,
        kind: PageFrameKind,
        textColorOverride: NSColor? = nil,
        applyDefaultInset: Bool = true,
        sourceParagraphId: UUID? = nil,
        tableOfContentsEntries: [TableOfContentsEntry]? = nil,
        exclusionRects: [Rect]? = nil,
        frameRect: Rect? = nil
    ) {
        let style: ParagraphStyle
        if kind == .footnote {
            style = ParagraphStyle(
                id: "footnote",
                displayName: "脚注",
                fontName: "Songti SC",
                fontSize: 8.5,
                lineHeight: 11,
                firstLineIndent: 0,
                spaceBefore: 0,
                spaceAfter: 4,
                colorToken: "ink"
            )
        } else if kind == .sideNote {
            style = ParagraphStyle(
                id: "sideNote",
                displayName: "旁注",
                fontName: "Songti SC",
                fontSize: 6.0,
                lineHeight: 8.0,
                firstLineIndent: 0,
                spaceBefore: 0,
                spaceAfter: 2,
                colorToken: "ink"
            )
        } else {
            style = project.styles.paragraphStyle(id: styleId ?? StyleID.body.rawValue)
        }

        let tokenColor = project.resolvedColorHex(style.colorToken).flatMap(NSColor.fromHex)
        let rawTextColor = textColorOverride ?? tokenColor ?? NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.14, alpha: 1)
        let textColor = proofedText(rawTextColor) ?? rawTextColor
        
        let drawingRect = applyDefaultInset ? rect.insetBy(dx: 4, dy: 2) : rect
        
        let attrString: NSAttributedString
        if let entries = tableOfContentsEntries, !entries.isEmpty {
            attrString = ChineseTypesetting.makeTOCAttributedString(
                entries: entries,
                project: project,
                containerWidth: Double(drawingRect.width),
                zoomScale: zoomScale,
                foregroundColor: textColor.cgColor
            )
        } else {
            var mappedRuns: [InlineRun]? = nil
            if let sourceParagraphId = sourceParagraphId,
               let paragraph = project.sections.lazy.flatMap(\.stories).flatMap(\.paragraphs).first(where: { $0.id == sourceParagraphId }),
               let runs = paragraph.inlineRuns {
                mappedRuns = InlineRun.mapRuns(runs, from: paragraph.text, to: text)
            }

            attrString = ChineseTypesetting.makeAttributedString(
                text: text,
                style: style,
                foregroundColor: textColor.cgColor,
                zoomScale: zoomScale,
                inlineRuns: mappedRuns
            )
        }
        
        guard let cgContext = NSGraphicsContext.current?.cgContext else { return }
        cgContext.saveGState()
        cgContext.translateBy(x: drawingRect.minX, y: drawingRect.maxY)
        cgContext.scaleBy(x: 1.0, y: -1.0)
        
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: drawingRect.width, height: drawingRect.height), transform: nil)
        let framesetter = CTFramesetterCreateWithAttributedString(attrString)
        
        var frameAttributes: [CFString: Any] = [:]
        if style.layoutDirection == .vertical {
            frameAttributes[kCTFrameProgressionAttributeName] = CTFrameProgression.rightToLeft.rawValue as CFNumber
        }
        
        if let exclusionRects = exclusionRects, !exclusionRects.isEmpty, let frameRect = frameRect {
            let compStyle = project.styles.componentStyle(for: kind)
            let insetX = applyDefaultInset ? 4.0 : (compStyle?.textInsetX ?? 0.0)
            let insetY = applyDefaultInset ? 2.0 : (compStyle?.textInsetY ?? 0.0)
            let extraWidth = (kind == .text || kind == .footnote || kind == .sideNote || kind == .runningHeader) ? (style.fontSize * 0.5) : 0.0
            
            let textRectPageInset = Rect(
                x: frameRect.x + insetX,
                y: frameRect.y + insetY,
                width: max(0, frameRect.width + extraWidth - insetX * 2),
                height: max(0, frameRect.height - insetY * 2)
            )
            
            var exclusionPaths: [CGPath] = []
            for img in exclusionRects {
                let overlap = textRectPageInset.intersection(img)
                guard overlap.width > 0 && overlap.height > 0 else { continue }
                
                let localMinX = overlap.x - textRectPageInset.x
                let localMinY = textRectPageInset.y + textRectPageInset.height - (overlap.y + overlap.height)
                
                let scaledRect = CGRect(
                    x: CGFloat(localMinX) * zoomScale,
                    y: CGFloat(localMinY) * zoomScale,
                    width: CGFloat(overlap.width) * zoomScale,
                    height: CGFloat(overlap.height) * zoomScale
                )
                exclusionPaths.append(CGPath(rect: scaledRect, transform: nil))
            }
            
            if !exclusionPaths.isEmpty {
                let clippingPaths = exclusionPaths.map { [kCTFramePathClippingPathAttributeName: $0] }
                frameAttributes[kCTFrameClippingPathsAttributeName] = clippingPaths
            }
        }
        
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, frameAttributes as CFDictionary)
        
        cgContext.textMatrix = .identity
        CTFrameDraw(frame, cgContext)
        ChineseTypesetting.drawKentenDots(for: frame, in: cgContext, layoutDirection: style.layoutDirection, zoomScale: zoomScale)
        cgContext.restoreGState()
    }

    private func resolvedColor(memoryColor: NSColor?, persistedHex: String?) -> NSColor? {
        proofed(memoryColor ?? persistedHex.flatMap(NSColor.fromHex))
    }

    /// True when the document is in CMYK output mode.
    private var cmykProof: Bool {
        project?.pageSetup.colorSpace == .cmyk
    }

    /// Soft-proof: in CMYK mode, render colors through the ICC CMYK profile so
    /// RGB fills show their duller print appearance and the canvas matches
    /// InDesign instead of showing the vivid RGB. A no-op in RGB mode.
    private func proofed(_ color: NSColor?) -> NSColor? {
        guard cmykProof, let color else { return color }
        return ICCCMYKProof.proof(color)
    }

    /// Text soft-proof. Mirrors the exporter's "near-black text → K100" rule so
    /// the canvas shows body/heading type as the same clean single-black InDesign
    /// will print, rather than a dull rich-black; other text is ICC-CMYK
    /// proofed like everything else.
    private func proofedText(_ color: NSColor?) -> NSColor? {
        guard cmykProof, let color else { return color }
        if let rgb = color.usingColorSpace(.deviceRGB),
           max(rgb.redComponent, rgb.greenComponent, rgb.blueComponent) <= 0.25 {
            return NSColor(deviceCyan: 0, magenta: 0, yellow: 0, black: 1, alpha: 1)
        }
        return ICCCMYKProof.proof(color)
    }

    private func drawAssetPlaceholder(assetId: UUID, isLeftHalf: Bool?, project: BookProject, rect: CGRect, maskShape: ImageMaskShape?) {
        let asset = project.assets.first { $0.id == assetId }
        let path = maskPath(in: rect, shape: maskShape)
        
        if let image = loadImage(asset: asset) {
            drawImage(image, isLeftHalf: isLeftHalf, rect: rect, project: project, maskShape: maskShape)
            let label = asset?.caption ?? (asset?.fileName as NSString?)?.lastPathComponent ?? "Image"
            drawImageLabel(label, in: rect)
            return
        }

        NSColor(calibratedWhite: 0.91, alpha: 1).setFill()
        path.fill()
        NSColor(calibratedWhite: 0.62, alpha: 1).setStroke()
        path.lineWidth = 1.0
        path.stroke()

        let label = asset?.caption ?? (asset?.fileName as NSString?)?.lastPathComponent ?? "Image"
        drawImageLabel(label, in: rect)
    }

    private func loadImage(asset: Asset?) -> NSImage? {
        guard let sourcePath = asset?.sourcePath else {
            return nil
        }
        return NSImage(contentsOfFile: sourcePath)
    }

    private func drawImage(_ image: NSImage, isLeftHalf: Bool?, rect: CGRect, project: BookProject, maskShape: ImageMaskShape?) {
        let path = maskPath(in: rect, shape: maskShape)
        
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        path.fill()

        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return
        }

        NSGraphicsContext.current?.saveGraphicsState()
        path.addClip()

        if let isLeft = isLeftHalf {
            let pageSize = project.pageSetup.pageSize
            let leftMargin = pageLeftMargin(for: 2, project: project)
            let rightMargin = pageRightMargin(for: 3, project: project)
            let leftWidth = CGFloat(pageSize.width - leftMargin) * zoomScale
            let rightWidth = CGFloat(pageSize.width - rightMargin) * zoomScale
            let totalWidth = leftWidth + rightWidth

            let drawRect: CGRect
            if isLeft {
                drawRect = CGRect(x: rect.minX, y: rect.minY, width: totalWidth, height: rect.height)
            } else {
                drawRect = CGRect(x: rect.minX - leftWidth, y: rect.minY, width: totalWidth, height: rect.height)
            }
            image.draw(in: drawRect)
        } else {
            let imageAspect = imageSize.width / imageSize.height
            let rectAspect = rect.width / rect.height
            let drawRect: CGRect
            if imageAspect > rectAspect {
                let height = rect.width / imageAspect
                drawRect = CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
            } else {
                let width = rect.height * imageAspect
                drawRect = CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: rect.height)
            }
            image.draw(in: drawRect)
        }

        NSGraphicsContext.current?.restoreGraphicsState()
        NSColor(calibratedWhite: 0.62, alpha: 1).setStroke()
        path.lineWidth = 1.0
        path.stroke()
    }

    private func maskPath(in rect: CGRect, shape: ImageMaskShape?) -> NSBezierPath {
        let path = NSBezierPath()
        guard let shape else {
            path.appendRect(rect)
            return path
        }
        let points = shape.polygonPoints(in: rect)
        guard !points.isEmpty else {
            path.appendRect(rect)
            return path
        }
        path.move(to: points[0])
        for i in 1..<points.count {
            path.line(to: points[i])
        }
        path.close()
        return path
    }

    private func pageLeftMargin(for pageNumber: Int, project: BookProject) -> Double {
        let setup = project.pageSetup
        let margins = project.resolvedMargins(for: pageNumber)
        if setup.facingPages {
            return pageNumber % 2 == 1 ? margins.left : margins.right
        }
        return margins.left
    }

    private func pageRightMargin(for pageNumber: Int, project: BookProject) -> Double {
        let setup = project.pageSetup
        let margins = project.resolvedMargins(for: pageNumber)
        if setup.facingPages {
            return pageNumber % 2 == 1 ? margins.right : margins.left
        }
        return margins.right
    }

    private func drawImageLabel(_ label: String, in rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.darkGray
        ]
        label.draw(in: rect.insetBy(dx: 10, dy: 10), withAttributes: attributes)
    }

    private func drawPageNumber(_ number: Int, project: BookProject, pageRect: CGRect) {
        guard project.resolvedShowHeadersFooters(for: number) else {
            return
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.gray
        ]
        let numStr = "\(number)"
        let setup = project.pageSetup
        let margins = project.resolvedMargins(for: number)
        
        if setup.facingPages {
            let leftMargin = CGFloat(number % 2 == 1 ? margins.left : margins.right)
            let rightMargin = CGFloat(number % 2 == 1 ? margins.right : margins.left)
            let x: CGFloat
            if number % 2 == 0 {
                // Left page, bottom left
                x = pageRect.minX + leftMargin * zoomScale
            } else {
                // Right page, bottom right
                let numSize = numStr.size(withAttributes: attributes)
                x = pageRect.maxX - rightMargin * zoomScale - numSize.width
            }
            numStr.draw(at: CGPoint(x: x, y: pageRect.maxY - 24), withAttributes: attributes)
        } else {
            numStr.draw(
                at: CGPoint(x: pageRect.midX - 4, y: pageRect.maxY - 24),
                withAttributes: attributes
            )
        }
    }
}
