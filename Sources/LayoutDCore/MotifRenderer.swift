import Foundation
import CoreGraphics
import CoreText
import AppKit

public extension NSColor {
    static func from(hex: String) -> NSColor? {
        guard let color = PrintColor(string: hex) else { return nil }
        switch color {
        case let .rgb(r, g, b):
            return NSColor(calibratedRed: CGFloat(r) / 255, green: CGFloat(g) / 255,
                           blue: CGFloat(b) / 255, alpha: 1.0)
        case let .cmyk(c, m, y, k):
            return NSColor(deviceCyan: CGFloat(c) / 100, magenta: CGFloat(m) / 100,
                           yellow: CGFloat(y) / 100, black: CGFloat(k) / 100, alpha: 1.0)
        }
    }
}

public struct GhostChapterNumberRenderInfo: Equatable, Sendable {
    public var text: String
    public var rect: CGRect
    public var fontName: String
    public var fontSize: CGFloat
    public var colorHex: String
    public var opacity: CGFloat
    public var drawBehind: Bool
}

public struct MotifRenderer {
    public static func drawGhostChapterNumber(
        page: LaidOutPage,
        project: BookProject,
        in context: CGContext,
        zoomScale: Double = 1.0,
        pageHeight: Double,
        isPDF: Bool = false
    ) {
        guard let info = project.ghostChapterNumberInfo(for: page) else { return }
        
        let rect: CGRect
        if isPDF {
            rect = CGRect(
                x: info.rect.origin.x * zoomScale,
                y: pageHeight - (info.rect.origin.y + info.rect.size.height) * zoomScale,
                width: info.rect.size.width * zoomScale,
                height: info.rect.size.height * zoomScale
            )
        } else {
            rect = CGRect(
                x: info.rect.origin.x * zoomScale,
                y: info.rect.origin.y * zoomScale,
                width: info.rect.size.width * zoomScale,
                height: info.rect.size.height * zoomScale
            )
        }
        
        context.saveGState()
        context.setAlpha(info.opacity)
        
        let fontSize = info.fontSize * zoomScale
        let font = NSFont(name: info.fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let color = NSColor.from(hex: info.colorHex) ?? NSColor.gray
        
        let attrStr = NSAttributedString(string: info.text, attributes: [
            .font: font,
            .foregroundColor: color.cgColor
        ])
        
        let framesetter = CTFramesetterCreateWithAttributedString(attrStr)
        let path = CGMutablePath()
        path.addRect(rect)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        
        CTFrameDraw(frame, context)
        context.restoreGState()
    }
    
    public static func drawHeaderMotif(
        page: LaidOutPage,
        project: BookProject,
        in context: CGContext,
        zoomScale: Double = 1.0,
        pageHeight: Double,
        isPDF: Bool = false
    ) {
        guard project.resolvedShowHeadersFooters(for: page.number) else { return }
        guard let header = project.motifs?.header else { return }
        
        let activeSec = project.activeSection(for: page)
        let headerText = project.resolvedHeaderText(for: page.number, activeSection: activeSec)
        
        let fontName = header.resolvedFontName ?? "Heiti SC Medium"
        let fontSize = CGFloat(header.fontSizePt ?? 9.0) * zoomScale
        let colorHex = project.resolvedColorHex(header.color ?? "grayText") ?? "#7F7F7F"
        
        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let color = NSColor.from(hex: colorHex) ?? NSColor.gray
        
        let margins = project.resolvedMargins(for: page.number)
        let setup = project.pageSetup
        
        let leftMargin = CGFloat(margins.left)
        let rightMargin = CGFloat(margins.right)
        let pageWidth = CGFloat(setup.pageSize.width)
        
        // Define header positions in layout coordinates
        let headerY: CGFloat = 24.0
        let headerHeight: CGFloat = 16.0
        
        context.saveGState()
        
        // Draw Thin line (细线通栏) if configured
        if let rule = header.rule, rule == "细线通栏" {
            let lineY: CGFloat = headerY + headerHeight
            let p1 = CGPoint(x: leftMargin * zoomScale, y: lineY * zoomScale)
            let p2 = CGPoint(x: (pageWidth - rightMargin) * zoomScale, y: lineY * zoomScale)
            
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(0.5 * zoomScale)
            
            if isPDF {
                context.move(to: CGPoint(x: p1.x, y: CGFloat(pageHeight) - p1.y))
                context.addLine(to: CGPoint(x: p2.x, y: CGFloat(pageHeight) - p2.y))
            } else {
                context.move(to: p1)
                context.addLine(to: p2)
            }
            context.strokePath()
        }
        
        // Render text
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color.cgColor
        ]
        
        let labelStr = headerText
        let pageNumStr = "\(page.number)"
        let showPageNum = header.showPageNumber
        
        if setup.facingPages {
            let isLeftPage = page.number % 2 == 0
            
            if isLeftPage {
                // Page number on the left
                if showPageNum {
                    let pageNumRect = CGRect(x: leftMargin, y: headerY, width: 50, height: headerHeight)
                    drawTextStr(pageNumStr, in: pageNumRect, alignRight: false, zoomScale: zoomScale, pageHeight: pageHeight, isPDF: isPDF, attributes: attributes, context: context)
                }
                // Header text right-aligned
                let textW = pageWidth - leftMargin - rightMargin - (showPageNum ? 60 : 0)
                let textX = leftMargin + (showPageNum ? 60 : 0)
                let textRect = CGRect(x: textX, y: headerY, width: textW, height: headerHeight)
                drawTextStr(labelStr, in: textRect, alignRight: true, zoomScale: zoomScale, pageHeight: pageHeight, isPDF: isPDF, attributes: attributes, context: context)
            } else {
                // Header text left-aligned
                let textW = pageWidth - leftMargin - rightMargin - (showPageNum ? 60 : 0)
                let textRect = CGRect(x: leftMargin, y: headerY, width: textW, height: headerHeight)
                drawTextStr(labelStr, in: textRect, alignRight: false, zoomScale: zoomScale, pageHeight: pageHeight, isPDF: isPDF, attributes: attributes, context: context)
                
                // Page number on the right
                if showPageNum {
                    let pageNumRect = CGRect(x: pageWidth - rightMargin - 50, y: headerY, width: 50, height: headerHeight)
                    drawTextStr(pageNumStr, in: pageNumRect, alignRight: true, zoomScale: zoomScale, pageHeight: pageHeight, isPDF: isPDF, attributes: attributes, context: context)
                }
            }
        } else {
            if showPageNum {
                let pageNumRect = CGRect(x: pageWidth - rightMargin - 50, y: headerY, width: 50, height: headerHeight)
                drawTextStr(pageNumStr, in: pageNumRect, alignRight: true, zoomScale: zoomScale, pageHeight: pageHeight, isPDF: isPDF, attributes: attributes, context: context)
            }
            let textW = pageWidth - leftMargin - rightMargin - (showPageNum ? 60 : 0)
            let textRect = CGRect(x: leftMargin, y: headerY, width: textW, height: headerHeight)
            drawTextStr(labelStr, in: textRect, alignRight: false, zoomScale: zoomScale, pageHeight: pageHeight, isPDF: isPDF, attributes: attributes, context: context)
        }
        
        context.restoreGState()
    }
    
    private static func drawTextStr(
        _ str: String,
        in rect: CGRect,
        alignRight: Bool,
        zoomScale: Double,
        pageHeight: Double,
        isPDF: Bool,
        attributes: [NSAttributedString.Key: Any],
        context: CGContext
    ) {
        let textRect: CGRect
        if isPDF {
            textRect = CGRect(
                x: rect.origin.x * zoomScale,
                y: pageHeight - (rect.origin.y + rect.size.height) * zoomScale,
                width: rect.size.width * zoomScale,
                height: rect.size.height * zoomScale
            )
        } else {
            textRect = CGRect(
                x: rect.origin.x * zoomScale,
                y: rect.origin.y * zoomScale,
                width: rect.size.width * zoomScale,
                height: rect.size.height * zoomScale
            )
        }
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignRight ? .right : .left
        var attrs = attributes
        attrs[.paragraphStyle] = paragraphStyle
        
        let attrStr = NSAttributedString(string: str, attributes: attrs)
        let framesetter = CTFramesetterCreateWithAttributedString(attrStr)
        let path = CGMutablePath()
        path.addRect(textRect)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        CTFrameDraw(frame, context)
    }
}

public extension BookProject {
    func chapterNumber(for page: LaidOutPage) -> Int? {
        for frame in page.frames {
            if frame.styleId == StyleID.heading1.rawValue || frame.styleId == "章名" || frame.styleId == "heading1",
               case .text(let text) = frame.content {
                let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                for (idx, sec) in sections.enumerated() {
                    let secTitle = sec.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleanText.contains(secTitle) || secTitle.contains(cleanText) {
                        return idx + 1
                    }
                    for story in sec.stories {
                        for para in story.paragraphs {
                             if para.kind == .heading(level: 1) && (para.text.contains(cleanText) || cleanText.contains(para.text)) {
                                 return idx + 1
                             }
                        }
                    }
                }
            }
        }
        return nil
    }
    
    func activeSection(for page: LaidOutPage) -> BookSection? {
        for frame in page.frames {
            if let paraId = frame.sourceParagraphId {
                for sec in sections {
                    for story in sec.stories {
                        if story.paragraphs.contains(where: { $0.id == paraId }) {
                            return sec
                        }
                    }
                }
            }
        }
        for frame in page.frames {
            if frame.styleId == StyleID.heading1.rawValue || frame.styleId == "章名" || frame.styleId == "heading1",
               case .text(let text) = frame.content {
                let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                for sec in sections {
                    let secTitle = sec.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleanText.contains(secTitle) || secTitle.contains(cleanText) {
                        return sec
                    }
                }
            }
        }
        return nil
    }
    
    func resolvedHeaderText(for pageNumber: Int, activeSection: BookSection?) -> String {
        guard let header = motifs?.header else {
            return metadata.title
        }
        
        let label = header.label ?? metadata.title
        var parts: [String] = []
        
        if header.showChapterTitle, let sec = activeSection {
            let secTitle = sec.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !secTitle.isEmpty {
                parts.append(secTitle)
            }
        }
        if !label.isEmpty {
            parts.append(label)
        }
        
        return parts.joined(separator: " · ")
    }
    
    func ghostChapterNumberInfo(for page: LaidOutPage) -> GhostChapterNumberRenderInfo? {
        guard let motif = motifs?.chapterNumber else { return nil }
        guard let chapterNum = self.chapterNumber(for: page) else { return nil }
        
        guard let headingFrame = page.frames.first(where: { $0.styleId == StyleID.heading1.rawValue || $0.styleId == "章名" || $0.styleId == "heading1" }) else {
            return nil
        }
        
        let ghostText = String(format: "%02d", chapterNum)
        let fontName = motif.resolvedFontName ?? "Georgia"
        let fontSize = CGFloat(motif.fontSizePt ?? 150.0)
        let rawColor = motif.color ?? "grayText"
        let colorHex = resolvedColorHex(rawColor) ?? "#E5E5E5"
        let opacity = CGFloat(motif.opacity ?? 0.08)
        let drawBehind = (motif.layer ?? "behind") == "behind"
        
        let cgHeadingRect = headingFrame.rect.cgRect
        let ghostWidth = fontSize * 0.65 * CGFloat(ghostText.count)
        let ghostHeight = fontSize * 0.8
        let ghostSize = CGSize(width: ghostWidth, height: ghostHeight)
        
        let x: CGFloat
        let y: CGFloat
        let anchor = motif.anchor ?? "chapterStart.topRight"
        
        if anchor.contains("topRight") {
            x = cgHeadingRect.maxX - ghostSize.width + 10
            y = cgHeadingRect.minY - ghostSize.height * 0.15
        } else if anchor.contains("bottomRight") {
            x = cgHeadingRect.maxX - ghostSize.width + 10
            y = cgHeadingRect.maxY - ghostSize.height * 0.85
        } else if anchor.contains("topLeft") {
            x = cgHeadingRect.minX - 10
            y = cgHeadingRect.minY - ghostSize.height * 0.15
        } else if anchor.contains("bottomLeft") {
            x = cgHeadingRect.minX - 10
            y = cgHeadingRect.maxY - ghostSize.height * 0.85
        } else {
            x = cgHeadingRect.midX - ghostSize.width / 2
            y = cgHeadingRect.midY - ghostSize.height / 2
        }
        
        return GhostChapterNumberRenderInfo(
            text: ghostText,
            rect: CGRect(x: x, y: y, width: ghostSize.width, height: ghostSize.height),
            fontName: fontName,
            fontSize: fontSize,
            colorHex: colorHex,
            opacity: opacity,
            drawBehind: drawBehind
        )
    }
    
    func sectionIndex(for paragraphId: UUID, in section: BookSection) -> Int? {
        var index = 0
        for story in section.stories {
            for para in story.paragraphs {
                if para.kind == .heading(level: 2) || para.styleId == StyleID.heading2.rawValue || para.styleId == "heading2" || para.styleId == "节名" {
                    index += 1
                    if para.id == paragraphId {
                        return index
                    }
                }
            }
        }
        return nil
    }
    
    func prependingSectionNumbers() -> BookProject {
        guard let motif = motifs?.sectionNumber else {
            return self
        }
        
        var updatedSections = sections
        for (secIdx, section) in sections.enumerated() {
            var updatedStories = section.stories
            for (storyIdx, story) in section.stories.enumerated() {
                var updatedParagraphs = story.paragraphs
                for (paraIdx, paragraph) in story.paragraphs.enumerated() {
                    if paragraph.kind == .heading(level: 2) || paragraph.styleId == StyleID.heading2.rawValue || paragraph.styleId == "heading2" || paragraph.styleId == "节名" {
                        if let index = sectionIndex(for: paragraph.id, in: section) {
                            let minDigits = motif.minDigits ?? 2
                            let formattedNum = String(format: "%0\(minDigits)d", index)
                            let prefix = motif.prefix ?? ""
                            let suffix = motif.suffix ?? ""
                            let secNumStr = "\(prefix)\(formattedNum)\(suffix)"
                            
                            var updatedPara = paragraph
                            updatedPara.text = secNumStr + paragraph.text
                            
                            var newRuns = paragraph.inlineRuns ?? []
                            newRuns = newRuns.map { run in
                                var r = run
                                r.location += secNumStr.count
                                return r
                            }
                            
                            let numColor = motif.color ?? "accent"
                            newRuns.insert(InlineRun(location: 0, length: secNumStr.count, emphasis: [], colorTokenRef: numColor), at: 0)
                            updatedPara.inlineRuns = newRuns
                            
                            updatedParagraphs[paraIdx] = updatedPara
                        }
                    }
                }
                updatedStories[storyIdx] = Story(
                    id: story.id,
                    title: story.title,
                    paragraphs: updatedParagraphs
                )
            }
            updatedSections[secIdx] = BookSection(
                title: section.title,
                stories: updatedStories
            )
        }
        
        var copy = self
        copy.sections = updatedSections
        return copy
    }
}
