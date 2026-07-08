import CoreText
import Foundation
import LayoutDCore

extension LayoutContext {
    func normalizedText(_ text: String, isTable: Bool = false) -> String {
        if isTable {
            return text.trimmedForLayout
        }
        let collapsed = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmedForLayout
        return normalizedCJKWesternSpacing(collapsed)
    }

    func normalizedCJKWesternSpacing(_ text: String) -> String {
        guard text.count > 1 else { return text }

        var result = ""
        var previous: Character?

        for character in text {
            if let previous, shouldInsertSpaceBetween(previous, character), result.last != " " {
                result.append(" ")
            }
            result.append(character)
            previous = character
        }

        return result
    }

    func shouldInsertSpaceBetween(_ left: Character, _ right: Character) -> Bool {
        (left.isCJKIdeograph && right.isWesternAlphanumeric)
            || (left.isWesternAlphanumeric && right.isCJKIdeograph)
    }

    func getImageRectsOnCurrentPage() -> [Rect] {
        var rects: [Rect] = []
        for frame in currentPage.frames {
            if frame.kind == .image {
                if frame.isUnderlay {
                    continue
                }
                rects.append(frame.rect)
            }
        }
        let actualPageNumber = currentAbsolutePageNumber
        if let plans = project.appliedLayoutPlans,
           let plan = plans[actualPageNumber] {
            let pageSize = project.pageSetup.pageSize
            for block in plan.blocks {
                if block.kind == .image {
                    var isUnderlayBlock = false
                    if case .asset(let assetId) = block.contentReference,
                       let asset = project.assets.first(where: { $0.id == assetId }),
                       asset.effectiveWrapMode == .underlay {
                        isUnderlayBlock = true
                    }
                    if isUnderlayBlock {
                        continue
                    }

                    let rect = Rect(
                        x: block.frame.x * pageSize.width,
                        y: block.frame.y * pageSize.height,
                        width: block.frame.width * pageSize.width,
                        height: block.frame.height * pageSize.height
                    )
                    if !rects.contains(where: { abs($0.x - rect.x) < 0.1 && abs($0.y - rect.y) < 0.1 && abs($0.width - rect.width) < 0.1 && abs($0.height - rect.height) < 0.1 }) {
                        rects.append(rect)
                    }
                }
            }
        }
        return rects
    }

    func estimatedTextHeightWithExclusions(
        text: String,
        style: ParagraphStyle,
        width: Double,
        x: Double,
        y: Double,
        inlineRuns: [InlineRun]? = nil
    ) -> Double {
        let imageRects = getImageRectsOnCurrentPage()
        let maxPossibleHeight = 2000.0
        let tentativeRect = Rect(x: x, y: y, width: width, height: maxPossibleHeight)
        let overlaps = imageRects.filter { $0.intersects(tentativeRect) }
        
        if overlaps.isEmpty {
            return estimatedTextHeight(text: text, style: style, width: width, inlineRuns: inlineRuns)
        }
        
        let attributedString = ChineseTypesetting.makeAttributedString(text: text, style: style, inlineRuns: inlineRuns)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        
        let path = CGMutablePath()
        path.addRect(CGRect(x: 0, y: 0, width: width, height: maxPossibleHeight))
        
        var exclusionPaths: [CGPath] = []
        for img in overlaps {
            let overlap = tentativeRect.intersection(img)
            guard overlap.width > 0 && overlap.height > 0 else { continue }
            
            let localMinX = overlap.x - x
            let localMinY = (y + maxPossibleHeight) - (overlap.y + overlap.height)
            let localRect = CGRect(x: localMinX, y: localMinY, width: overlap.width, height: overlap.height)
            exclusionPaths.append(CGPath(rect: localRect, transform: nil))
        }
        
        var frameAttrs: [CFString: Any] = [:]
        if !exclusionPaths.isEmpty {
            let clippingPaths = exclusionPaths.map { [kCTFramePathClippingPathAttributeName: $0] }
            frameAttrs[kCTFrameClippingPathsAttributeName] = clippingPaths
        }
        
        let ctFrame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attributedString.length), path, frameAttrs as CFDictionary)
        
        let lines = CTFrameGetLines(ctFrame) as! [CTLine]
        guard !lines.isEmpty else { return style.lineHeight }
        
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(ctFrame, CFRange(location: 0, length: 0), &origins)
        
        let lastOriginY = origins.last?.y ?? 0.0
        
        var lastLineAscent: CGFloat = 0
        var lastLineDescent: CGFloat = 0
        var lastLineLeading: CGFloat = 0
        CTLineGetTypographicBounds(lines.last!, &lastLineAscent, &lastLineDescent, &lastLineLeading)
        
        let textHeight = maxPossibleHeight - Double(lastOriginY) + Double(lastLineDescent + lastLineLeading)
        return max(ceil(textHeight), style.lineHeight)
    }

    func estimatedTextHeight(text: String, style: ParagraphStyle, width: Double, inlineRuns: [InlineRun]? = nil) -> Double {
        if let cached = LayoutHeightCache.shared.get(text: text, style: style, width: width, inlineRuns: inlineRuns) {
            return cached
        }
        
        let attributedString = ChineseTypesetting.makeAttributedString(text: text, style: style, inlineRuns: inlineRuns)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let constraint = CGSize(width: width, height: .greatestFiniteMagnitude)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: text.count),
            nil,
            constraint,
            nil
        )
        let result = max(ceil(size.height), style.lineHeight)
        LayoutHeightCache.shared.set(text: text, style: style, width: width, inlineRuns: inlineRuns, height: result)
        return result
    }

    /// 表格按网格估高：每行取其各单元格估高的最大值（单元格在等分列宽内自动折行），
    /// 再对所有行求和。`cellInset` 与 IDML 导出的 Cell inset 保持一致，避免低估折行
    /// 导致 InDesign 溢流。略偏保守（宁高勿矮）以确保整张表落进文本框。
    func estimatedTableHeight(cells: [[String]], style: ParagraphStyle) -> Double {
        let columnCount = cells.map(\.count).max() ?? 0
        guard columnCount > 0 else { return style.lineHeight }
        let cellInset = 2.0
        let cellWidth = columnWidth / Double(columnCount)
        let textWidth = max(10, cellWidth - cellInset * 2)
        let minRowHeight = max(18, style.lineHeight)
        var total = 0.0
        for row in cells {
            var rowHeight = minRowHeight
            for column in 0..<columnCount {
                let cellText = column < row.count ? row[column] : ""
                let height = estimatedTextHeight(text: cellText, style: style, width: textWidth) + cellInset * 2
                rowHeight = max(rowHeight, height)
            }
            total += rowHeight
        }
        return total
    }

    func estimatedFootnoteHeight(_ paragraph: Paragraph) -> Double {
        let text = paragraph.text
        let style = footnoteStyle
        let width = contentWidth
        return estimatedTextHeight(text: text, style: style, width: width, inlineRuns: paragraph.inlineRuns)
    }

    var currentPageFootnoteHeight: Double {
        if currentPageFootnoteParagraphs.isEmpty {
            return 0.0
        }
        return currentPageFootnoteParagraphs.reduce(0.0) { sum, p in
            sum + estimatedFootnoteHeight(p)
        }
    }

    mutating func layoutFootnotesAndSideNotesOnCurrentPage() {
        if !currentPageFootnoteParagraphs.isEmpty {
            let margins = project.resolvedMargins(for: currentAbsolutePageNumber)
            let baseBottomLimit = project.pageSetup.pageSize.height - margins.bottom
            let totalFnHeight = currentPageFootnoteHeight

            let dividerY = baseBottomLimit - totalFnHeight - 24 + 6
            let dividerRect = Rect(
                x: pageLeftMargin(for: currentAbsolutePageNumber),
                y: dividerY,
                width: 60,
                height: 1
            )
            currentPage.frames.append(PageFrame(
                kind: .footnoteDivider,
                rect: dividerRect,
                content: .empty
            ))
            
            var currentY = baseBottomLimit - totalFnHeight
            for fnParagraph in currentPageFootnoteParagraphs {
                let fnHeight = estimatedFootnoteHeight(fnParagraph)
                let fnRect = Rect(
                    x: pageLeftMargin(for: currentAbsolutePageNumber),
                    y: currentY,
                    width: contentWidth,
                    height: fnHeight
                )
                currentPage.frames.append(PageFrame(
                    kind: .footnote,
                    rect: fnRect,
                    styleId: "footnote",
                    content: .text(fnParagraph.text),
                    sourceParagraphId: fnParagraph.id
                ))
                currentY += fnHeight
            }
        }
        
        if !currentPageSideNoteParagraphs.isEmpty {
            let absPageNum = currentAbsolutePageNumber
            let margins = project.resolvedMargins(for: absPageNum)
            let pageSize = project.pageSetup.pageSize
            let facingPages = project.pageSetup.facingPages
            
            let isEvenPage = absPageNum % 2 == 0
            let sideNoteWidth = 42.0
            let gap = 6.0
            
            let x: Double
            if facingPages {
                if isEvenPage {
                    x = margins.left - sideNoteWidth - gap
                } else {
                    x = pageSize.width - margins.right + gap
                }
            } else {
                x = pageSize.width - margins.right + gap
            }
            
            for (snParagraph, refY) in currentPageSideNoteParagraphs {
                let snHeight = estimatedTextHeight(text: snParagraph.text, style: sideNoteStyle, width: sideNoteWidth, inlineRuns: snParagraph.inlineRuns)
                let rect = Rect(x: x, y: refY, width: sideNoteWidth, height: snHeight)
                currentPage.frames.append(PageFrame(
                    kind: .sideNote,
                    rect: rect,
                    styleId: "sideNote",
                    content: .text(snParagraph.text),
                    sourceParagraphId: snParagraph.id
                ))
            }
        }
        
        currentPageFootnoteParagraphs.removeAll()
        currentPageSideNoteParagraphs.removeAll()
    }
}

private extension Character {
    var isCJKIdeograph: Bool {
        unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || (0x20000...0x2A6DF).contains(scalar.value)
                || (0x2A700...0x2B73F).contains(scalar.value)
                || (0x2B740...0x2B81F).contains(scalar.value)
                || (0x2B820...0x2CEAF).contains(scalar.value)
        }
    }

    var isWesternAlphanumeric: Bool {
        unicodeScalars.allSatisfy { scalar in
            (65...90).contains(scalar.value)
                || (97...122).contains(scalar.value)
                || (48...57).contains(scalar.value)
        }
    }
}
