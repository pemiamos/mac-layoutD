import Cocoa
import LayoutDCore

public struct WireframeRenderer {
    public static func renderSpread(
        archetype: SpreadArchetype,
        size: CGSize = CGSize(width: 240, height: 150)
    ) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        
        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }
        
        // Clear background
        NSColor.white.set()
        context.fill(CGRect(origin: .zero, size: size))
        
        let pageWidth = size.width / 2
        let pageHeight = size.height
        
        let leftPageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let rightPageRect = CGRect(x: pageWidth, y: 0, width: pageWidth, height: pageHeight)
        
        // Draw page borders
        NSColor.lightGray.withAlphaComponent(0.4).set()
        context.stroke(leftPageRect.insetBy(dx: 1, dy: 1), width: 1)
        context.stroke(rightPageRect.insetBy(dx: 1, dy: 1), width: 1)
        
        // Draw left page blocks
        drawBlocks(archetype.leftPageBlocks, in: leftPageRect, context: context)
        
        // Draw right page blocks
        drawBlocks(archetype.rightPageBlocks, in: rightPageRect, context: context)
        
        // Draw spine (dashed line in the center)
        context.saveGState()
        context.setStrokeColor(NSColor.gray.cgColor)
        context.setLineDash(phase: 0, lengths: [4, 4])
        context.strokeLineSegments(between: [
            CGPoint(x: pageWidth, y: 0),
            CGPoint(x: pageWidth, y: pageHeight)
        ])
        context.restoreGState()
        
        image.unlockFocus()
        return image
    }
    
    private static func drawBlocks(_ blocks: [SpreadBlock], in pageRect: CGRect, context: CGContext) {
        // Draw ghostNumber (chapterNumber) in background first
        if let ghost = blocks.first(where: { $0.role == "chapterNumber" }) {
            drawSingleBlock(ghost, in: pageRect, context: context)
        }
        
        // Draw other blocks
        for block in blocks where block.role != "chapterNumber" {
            drawSingleBlock(block, in: pageRect, context: context)
        }
    }
    
    private static func drawSingleBlock(_ block: SpreadBlock, in pageRect: CGRect, context: CGContext) {
        let frame = block.normalizedFrame
        
        // Convert top-left normalized coordinates to bottom-left CoreGraphics coordinates
        let width = frame.width * pageRect.width
        let height = frame.height * pageRect.height
        let x = pageRect.minX + frame.x * pageRect.width
        let y = pageRect.minY + (1.0 - frame.y - frame.height) * pageRect.height
        
        let rect = CGRect(x: x, y: y, width: width, height: height)
        
        context.saveGState()
        defer { context.restoreGState() }
        
        switch block.kind {
        case .text:
            if block.role == "chapterNumber" {
                // Large ghost number "03"
                context.setFillColor(NSColor.lightGray.withAlphaComponent(0.12).cgColor)
                // Draw a round shape or letter block to simulate ghost number
                context.fillEllipse(in: rect.insetBy(dx: rect.width * 0.1, dy: rect.height * 0.1))
            } else if block.role == "pullQuote" {
                // Pull quote frame
                context.setFillColor(NSColor.orange.withAlphaComponent(0.04).cgColor)
                context.fill(rect)
                context.setStrokeColor(NSColor.orange.withAlphaComponent(0.15).cgColor)
                context.stroke(rect, width: 0.5)
                
                // Draw vertical left rule
                context.setFillColor(NSColor.orange.cgColor)
                context.fill(CGRect(x: rect.minX, y: rect.minY, width: 3, height: rect.height))
                
                // Lines
                drawSimulatedLines(in: rect.insetBy(dx: 8, dy: 4), lineSpacing: 5, context: context)
            } else if block.role.contains("heading") {
                // Heading
                context.setFillColor(NSColor.black.withAlphaComponent(0.8).cgColor)
                context.fill(CGRect(x: rect.minX, y: rect.minY + rect.height * 0.2, width: rect.width * 0.8, height: rect.height * 0.5))
                
                // Bottom rule
                context.setFillColor(NSColor.orange.cgColor)
                context.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 1.5))
            } else if block.role == "introduction" {
                // Intro text
                context.setFillColor(NSColor.lightGray.withAlphaComponent(0.1).cgColor)
                context.fill(rect)
                drawSimulatedLines(in: rect.insetBy(dx: 4, dy: 4), lineSpacing: 4, lineThickness: 1.2, color: NSColor.gray, context: context)
            } else {
                // Normal body text
                context.setFillColor(NSColor.lightGray.withAlphaComponent(0.05).cgColor)
                context.fill(rect)
                // Draw multi-column simulation if broad
                if rect.width > 60 {
                    let colWidth = (rect.width - 6) / 2
                    let col1 = CGRect(x: rect.minX, y: rect.minY, width: colWidth, height: rect.height)
                    let col2 = CGRect(x: rect.minX + colWidth + 6, y: rect.minY, width: colWidth, height: rect.height)
                    drawSimulatedLines(in: col1.insetBy(dx: 2, dy: 4), lineSpacing: 4, context: context)
                    drawSimulatedLines(in: col2.insetBy(dx: 2, dy: 4), lineSpacing: 4, context: context)
                } else {
                    drawSimulatedLines(in: rect.insetBy(dx: 2, dy: 4), lineSpacing: 4, context: context)
                }
            }
            
        case .image:
            // Medium grey with crossing lines
            context.setFillColor(NSColor.lightGray.withAlphaComponent(0.3).cgColor)
            context.fill(rect)
            context.setStrokeColor(NSColor.gray.withAlphaComponent(0.6).cgColor)
            context.stroke(rect, width: 1)
            
            // X lines
            context.beginPath()
            context.move(to: CGPoint(x: rect.minX, y: rect.minY))
            context.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            context.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            context.strokePath()
            
        case .caption:
            // Single short line
            context.setStrokeColor(NSColor.gray.cgColor)
            context.strokeLineSegments(between: [
                CGPoint(x: rect.minX, y: rect.midY),
                CGPoint(x: rect.minX + rect.width * 0.6, y: rect.midY)
            ])
            
            // Top tick
            context.setFillColor(NSColor.orange.cgColor)
            context.fill(CGRect(x: rect.minX, y: rect.maxY - 2, width: 8, height: 2))
            
        case .component:
            if block.role == "header" {
                // Header chrome
                context.setFillColor(NSColor.gray.withAlphaComponent(0.5).cgColor)
                context.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 0.5))
                
                context.fill(CGRect(x: rect.minX, y: rect.minY + 2, width: 25, height: 2))
                context.fill(CGRect(x: rect.maxX - 15, y: rect.minY + 2, width: 15, height: 2))
            } else if block.role == "knowledgeCard" {
                // Knowledge card container
                context.setFillColor(NSColor.yellow.withAlphaComponent(0.06).cgColor)
                context.fill(rect)
                context.setStrokeColor(NSColor.yellow.withAlphaComponent(0.3).cgColor)
                context.stroke(rect.insetBy(dx: 1, dy: 1), width: 1.5)
                
                drawSimulatedLines(in: rect.insetBy(dx: 6, dy: 6), lineSpacing: 4.5, context: context)
            } else {
                context.setFillColor(NSColor.lightGray.withAlphaComponent(0.2).cgColor)
                context.fill(rect)
            }
            
        default:
            context.setFillColor(NSColor.lightGray.withAlphaComponent(0.1).cgColor)
            context.fill(rect)
        }
    }
    
    private static func drawSimulatedLines(
        in rect: CGRect,
        lineSpacing: CGFloat,
        lineThickness: CGFloat = 0.8,
        color: NSColor = .lightGray,
        context: CGContext
    ) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineThickness)
        
        var currentY = rect.maxY - 4
        while currentY > rect.minY + 2 {
            context.strokeLineSegments(between: [
                CGPoint(x: rect.minX, y: currentY),
                CGPoint(x: rect.maxX, y: currentY)
            ])
            currentY -= lineSpacing
        }
        context.restoreGState()
    }
}
