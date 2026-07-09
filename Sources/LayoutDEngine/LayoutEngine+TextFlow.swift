import CoreText
import Foundation
import LayoutDCore

extension LayoutContext {
    mutating func addText(_ text: String, style: ParagraphStyle, kind: PageFrameKind, anchoredSideNoteIds: [UUID] = [], sourceParagraphId: UUID? = nil) {
        let text = normalizedText(text, isTable: kind == .table)

        // 原生表格：按网格估高落框，而非用拍平文本测高（否则框太矮，InDesign 里整张表
        // 溢流、只显示前几行）。导出器据 sourceParagraphId 的 tableCells 输出真 <Table>。
        if kind == .table,
           let sourceParagraphId,
           let paragraph = findParagraph(id: sourceParagraphId),
           let cells = paragraph.tableCells, !cells.isEmpty {
            let tableHeight = estimatedTableHeight(cells: cells, style: style)
            placeTextFrame(text, height: tableHeight, style: style, kind: kind,
                           spaceBefore: style.spaceBefore, sourceParagraphId: sourceParagraphId)
            return
        }
        var paragraphRuns: [InlineRun]? = nil
        if let sourceParagraphId = sourceParagraphId,
           let paragraph = findParagraph(id: sourceParagraphId),
           let runs = paragraph.inlineRuns {
            paragraphRuns = InlineRun.mapRuns(runs, from: paragraph.text, to: text)
        }
        
        if isVertical && kind != .runningHeader && kind != .footnote && kind != .sideNote {
            addFlowingVerticalText(text, style: style, kind: kind, anchoredSideNoteIds: anchoredSideNoteIds, sourceParagraphId: sourceParagraphId, inlineRuns: paragraphRuns)
            return
        }
        
        let height: Double
        if kind == .table {
            let componentStyle = project.styles.componentStyle(for: .table)
            let textInsetX = componentStyle?.textInsetX ?? 8.0
            let textInsetY = componentStyle?.textInsetY ?? 6.0
            let tableData = TableLayoutHelper.parseTableText(text)
            let colWidths = TableLayoutHelper.allocateColumnWidths(
                tableData: tableData,
                totalWidth: columnWidth,
                fontName: style.fontName,
                fontSize: style.fontSize
            )
            let heights = TableLayoutHelper.calculateRowHeights(
                tableData: tableData,
                colWidths: colWidths,
                style: style,
                textInsetX: textInsetX,
                textInsetY: textInsetY
            )
            height = heights.reduce(0.0, +)
        } else {
            height = estimatedTextHeightWithExclusions(text: text, style: style, width: columnWidth, x: cursorX, y: cursorY, inlineRuns: paragraphRuns)
        }
        
        if shouldKeepHeadingWithNext(style: style, height: height) {
            advanceToNextColumnOrPage()
        }

        if height > columnTextHeight, style.id == StyleID.body.rawValue || style.id == StyleID.callout.rawValue {
            issues.append(
                LayoutIssue(
                    severity: .info,
                    message: "文本段落高度超过单栏可用高度，已自动跨栏拆分",
                    category: .layout,
                    pageNumber: currentPage.number
                )
            )
            addFlowingText(text, style: style, kind: kind, anchoredSideNoteIds: anchoredSideNoteIds, sourceParagraphId: sourceParagraphId, inlineRuns: paragraphRuns)
            return
        }

        placeTextFrame(text, height: height, style: style, kind: kind, spaceBefore: style.spaceBefore, anchoredSideNoteIds: anchoredSideNoteIds, sourceParagraphId: sourceParagraphId)
    }

    func frameKind(for paragraphKind: ParagraphKind) -> PageFrameKind {
        switch paragraphKind {
        case .callout:
            return .callout
        case .table:
            return .table
        case .footnote:
            return .footnote
        case .sideNote:
            return .sideNote
        default:
            return .text
        }
    }

    func shouldKeepHeadingWithNext(style: ParagraphStyle, height: Double) -> Bool {
        guard style.id == StyleID.heading1.rawValue || style.id == StyleID.heading2.rawValue else {
            return false
        }

        let bodyStyle = project.styles.paragraphStyle(id: StyleID.body.rawValue)
        let minimumFollowingTextHeight = bodyStyle.lineHeight * 2
        let requiredHeight = style.spaceBefore + height + style.spaceAfter + minimumFollowingTextHeight
        return remainingColumnHeight < requiredHeight && remainingColumnHeight < columnTextHeight
    }

    mutating func addFlowingText(_ text: String, style: ParagraphStyle, kind: PageFrameKind, anchoredSideNoteIds: [UUID] = [], sourceParagraphId: UUID? = nil, inlineRuns: [InlineRun]? = nil) {
        let lines = ChineseTypesetting.breakTextIntoLines(
            text,
            style: style,
            columnWidth: columnWidth,
            hangingWidth: style.fontSize * 0.5,
            inlineRuns: inlineRuns
        )
        
        var remainingLines = lines
        var isFirstSegment = true
        
        while !remainingLines.isEmpty {
            let spaceBefore = isFirstSegment ? style.spaceBefore : 0
            if remainingColumnHeight < style.lineHeight + spaceBefore + style.spaceAfter {
                advanceToNextColumnOrPage()
            }
            
            let maxSegmentHeight = max(
                style.lineHeight,
                remainingColumnHeight - spaceBefore - style.spaceAfter
            )
            
            // Find how many lines can fit in maxSegmentHeight
            var linesInSegment: [String] = []
            var currentHeight = 0.0
            
            for line in remainingLines {
                let lineNeed = linesInSegment.isEmpty ? (style.lineHeight + spaceBefore) : style.lineHeight
                if currentHeight + lineNeed <= maxSegmentHeight {
                    linesInSegment.append(line)
                    currentHeight += lineNeed
                } else {
                    break
                }
            }
            
            // Apply widow/orphan controls
            let fittedCount = linesInSegment.count
            let totalCount = remainingLines.count
            let remainingCount = totalCount - fittedCount
            
            var finalFittedCount = fittedCount
            
            if remainingCount > 0 {
                // Orphan control: if only 1 line fits and it's not the top of the column
                if fittedCount == 1 && remainingColumnHeight < columnTextHeight {
                    finalFittedCount = 0
                }
                // Widow control: if only 1 line is left for the next page/column
                else if remainingCount == 1 {
                    if fittedCount >= 3 {
                        // pull one line
                        finalFittedCount = fittedCount - 1
                    } else if fittedCount == 2 && remainingColumnHeight < columnTextHeight {
                        // push all to next page/column
                        finalFittedCount = 0
                    }
                }
            }
            
            if finalFittedCount == 0 {
                advanceToNextColumnOrPage()
                continue
            }
            
            let segmentText = remainingLines.prefix(finalFittedCount).joined(separator: "\n")
            let segmentHeight = Double(finalFittedCount) * style.lineHeight
            
            placeTextFrame(
                segmentText,
                height: segmentHeight,
                style: style,
                kind: kind,
                spaceBefore: spaceBefore,
                anchoredSideNoteIds: isFirstSegment ? anchoredSideNoteIds : [],
                sourceParagraphId: sourceParagraphId
            )
            
            remainingLines.removeFirst(finalFittedCount)
            isFirstSegment = false
        }
    }

    mutating func addFlowingVerticalText(_ text: String, style: ParagraphStyle, kind: PageFrameKind, anchoredSideNoteIds: [UUID] = [], sourceParagraphId: UUID? = nil, inlineRuns: [InlineRun]? = nil) {
        let verticalStyle = style.layoutDirection == nil ? style.with(layoutDirection: .vertical) : style
        let lines = ChineseTypesetting.breakTextIntoLines(
            text,
            style: verticalStyle,
            columnWidth: columnTextHeight,
            hangingWidth: style.fontSize * 0.5,
            inlineRuns: inlineRuns
        )
        
        var remainingLines = lines
        var isFirstSegment = true
        
        while !remainingLines.isEmpty {
            let spaceBefore = isFirstSegment ? style.spaceBefore : 0
            
            // In vertical mode, check if we need to advance column/page
            let leftLimit = pageLeftMargin(for: currentAbsolutePageNumber)
            let minReqWidth = verticalStyle.lineHeight + spaceBefore + style.spaceAfter
            if cursorX - minReqWidth < leftLimit {
                advanceToNextColumnOrPage()
            }
            
            let maxSegmentWidth = cursorX - leftLimit - spaceBefore - style.spaceAfter
            // How many vertical lines can fit in maxSegmentWidth?
            var fitCount = Int(floor(maxSegmentWidth / verticalStyle.lineHeight))
            if fitCount <= 0 {
                advanceToNextColumnOrPage()
                continue
            }
            
            fitCount = min(fitCount, remainingLines.count)
            
            // Widow/orphan controls for vertical lines:
            let totalCount = remainingLines.count
            let remainingCount = totalCount - fitCount
            var finalFitCount = fitCount
            
            if remainingCount > 0 {
                // Orphan: if only 1 line fits, and we are not at the right of the row
                let rowRight = project.pageSetup.pageSize.width - pageRightMargin(for: currentAbsolutePageNumber)
                let isStartOfRow = abs(cursorX - rowRight) < 5.0
                
                if fitCount == 1 && !isStartOfRow {
                    finalFitCount = 0
                }
                // Widow: if only 1 line is left for the next deck/page
                else if remainingCount == 1 {
                    if fitCount >= 3 {
                        finalFitCount = fitCount - 1
                    } else if fitCount == 2 && !isStartOfRow {
                        finalFitCount = 0
                    }
                }
            }
            
            if finalFitCount == 0 {
                advanceToNextColumnOrPage()
                continue
            }
            
            let segmentText = remainingLines.prefix(finalFitCount).joined(separator: "\n")
            let segmentWidth = Double(finalFitCount) * verticalStyle.lineHeight
            
            cursorX -= spaceBefore
            let rectX = cursorX - segmentWidth
            let rectY = cursorY
            
            let rect = Rect(x: rectX, y: rectY, width: segmentWidth, height: columnTextHeight)
            currentPage.frames.append(PageFrame(
                kind: kind,
                rect: rect,
                styleId: style.id,
                content: .text(segmentText),
                sourceParagraphId: sourceParagraphId
            ))
            
            cursorX -= segmentWidth + style.spaceAfter
            
            remainingLines.removeFirst(finalFitCount)
            isFirstSegment = false
        }
    }

    mutating func placeTextFrame(
        _ text: String,
        height: Double,
        style: ParagraphStyle,
        kind: PageFrameKind,
        spaceBefore: Double,
        anchoredSideNoteIds: [UUID] = [],
        sourceParagraphId: UUID? = nil
    ) {
        advanceIfNeeded(height + spaceBefore + style.spaceAfter)
        cursorY += spaceBefore
        let rect = Rect(x: cursorX, y: cursorY, width: columnWidth, height: height)
        let imageRects = getImageRectsOnCurrentPage()
        let overlaps = imageRects.filter { $0.intersects(rect) }
        currentPage.frames.append(PageFrame(
            kind: kind,
            rect: rect,
            styleId: style.id,
            content: .text(text),
            sourceParagraphId: sourceParagraphId,
            exclusionRects: overlaps.isEmpty ? nil : overlaps
        ))
        
        for snId in anchoredSideNoteIds {
            if let snParagraph = findParagraph(id: snId) {
                currentPageSideNoteParagraphs.append((snParagraph, cursorY))
            }
        }
        
        cursorY += height + style.spaceAfter
        snapToBaseline()
    }

    func fittingPrefix(
        of text: String,
        style: ParagraphStyle,
        maxHeight: Double,
        width: Double,
        x: Double,
        y: Double,
        inlineRuns: [InlineRun]? = nil
    ) -> String {
        let imageRects = getImageRectsOnCurrentPage()
        let tentativeRect = Rect(x: x, y: y, width: width, height: maxHeight)
        let overlaps = imageRects.filter { $0.intersects(tentativeRect) }
        
        if overlaps.isEmpty {
            if estimatedTextHeight(text: text, style: style, width: width, inlineRuns: inlineRuns) <= maxHeight {
                return text
            }

            var lowerBound = 1
            var upperBound = text.count
            var bestCount = 1

            while lowerBound <= upperBound {
                let mid = (lowerBound + upperBound) / 2
                let candidate = String(text.prefix(mid)).trimmedForLayout
                let mappedRuns = InlineRun.mapRuns(inlineRuns ?? [], toSubstringFrom: 0, length: mid)
                let height = estimatedTextHeight(text: candidate, style: style, width: width, inlineRuns: mappedRuns)
                if height <= maxHeight {
                    bestCount = max(mid, 1)
                    lowerBound = mid + 1
                } else {
                    upperBound = mid - 1
                }
            }

            let broken = smartBreakPrefix(of: text, maximumCount: bestCount)
            let kinsokuPrefix = applyChineseTypesettingRules(candidatePrefix: broken, fullText: text, style: style, maxHeight: maxHeight, width: width, inlineRuns: inlineRuns)
            return applyWidowOrphanControls(prefix: kinsokuPrefix, fullText: text, style: style, maxHeight: maxHeight, width: width, inlineRuns: inlineRuns)
        }
        
        let attributedString = ChineseTypesetting.makeAttributedString(text: text, style: style, inlineRuns: inlineRuns, project: project)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        
        let path = CGMutablePath()
        path.addRect(CGRect(x: 0, y: 0, width: width, height: maxHeight))
        
        var exclusionPaths: [CGPath] = []
        for img in overlaps {
            let overlap = tentativeRect.intersection(img)
            guard overlap.width > 0 && overlap.height > 0 else { continue }
            
            let localMinX = overlap.x - x
            let localMinY = (y + maxHeight) - (overlap.y + overlap.height)
            let localRect = CGRect(x: localMinX, y: localMinY, width: overlap.width, height: overlap.height)
            exclusionPaths.append(CGPath(rect: localRect, transform: nil))
        }
        
        var frameAttrs: [CFString: Any] = [:]
        if !exclusionPaths.isEmpty {
            let clippingPaths = exclusionPaths.map { [kCTFramePathClippingPathAttributeName: $0] }
            frameAttrs[kCTFrameClippingPathsAttributeName] = clippingPaths
        }
        
        let ctFrame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attributedString.length), path, frameAttrs as CFDictionary)
        let visibleRange = CTFrameGetVisibleStringRange(ctFrame)
        let fitLength = visibleRange.length
        
        if fitLength >= text.count {
            return text
        }
        
        let broken = smartBreakPrefix(of: text, maximumCount: fitLength)
        let kinsokuPrefix = applyChineseTypesettingRules(candidatePrefix: broken, fullText: text, style: style, maxHeight: maxHeight, width: width, inlineRuns: inlineRuns)
        return applyWidowOrphanControls(prefix: kinsokuPrefix, fullText: text, style: style, maxHeight: maxHeight, width: width, inlineRuns: inlineRuns)
    }

    func smartBreakPrefix(of text: String, maximumCount: Int) -> String {
        let maximumCount = max(1, min(maximumCount, text.count))
        let roughPrefix = String(text.prefix(maximumCount))
        let punctuation = CharacterSet(charactersIn: "。！？；;，,、 ")
        let searchStart = max(roughPrefix.count - 28, 0)
        let candidates = Array(roughPrefix.enumerated()).dropFirst(searchStart)

        if let breakPoint = candidates.last(where: { item in
            String(item.element).rangeOfCharacter(from: punctuation) != nil
        }) {
            return String(roughPrefix.prefix(breakPoint.offset + 1)).trimmedForLayout
        }

        return roughPrefix.trimmedForLayout
    }

    func applyChineseTypesettingRules(
        candidatePrefix: String,
        fullText: String,
        style: ParagraphStyle,
        maxHeight: Double,
        width: Double,
        inlineRuns: [InlineRun]? = nil
    ) -> String {
        var prefix = candidatePrefix
        
        for _ in 0..<5 {
            let prefixCount = prefix.count
            guard prefixCount > 0, prefixCount < fullText.count else {
                break
            }
            
            if let lastChar = prefix.last, ChineseLineBreakRules.forbidsLineEnd(lastChar) {
                prefix = String(prefix.dropLast())
                continue
            }
            
            let remainingText = fullText.dropFirst(prefix.count)
            if let nextChar = remainingText.first, ChineseLineBreakRules.forbidsLineStart(nextChar) {
                let pulledCandidate = prefix + String(nextChar)
                let mappedRuns = InlineRun.mapRuns(inlineRuns ?? [], toSubstringFrom: 0, length: pulledCandidate.count)
                let height = estimatedTextHeight(text: pulledCandidate, style: style, width: width, inlineRuns: mappedRuns)
                if height <= maxHeight {
                    prefix = pulledCandidate
                } else {
                    if prefix.count > 1 {
                        prefix = String(prefix.dropLast())
                    } else {
                        break
                    }
                }
                continue
            }
            
            break
        }
        
        return prefix.trimmedForLayout
    }

    func applyWidowOrphanControls(
        prefix: String,
        fullText: String,
        style: ParagraphStyle,
        maxHeight: Double,
        width: Double,
        inlineRuns: [InlineRun]? = nil
    ) -> String {
        let prefix = prefix.trimmedForLayout
        guard !prefix.isEmpty else { return "" }
        let remaining = String(fullText.dropFirst(prefix.count)).trimmedForLayout
        guard !remaining.isEmpty else { return prefix }
        
        let prefixRuns = InlineRun.mapRuns(inlineRuns ?? [], toSubstringFrom: 0, length: prefix.count)
        let prefixHeight = estimatedTextHeight(text: prefix, style: style, width: width, inlineRuns: prefixRuns)
        let prefixLines = max(1, Int(round(prefixHeight / style.lineHeight)))
        
        let remainingRuns = InlineRun.mapRuns(inlineRuns ?? [], toSubstringFrom: prefix.count, length: remaining.count)
        let remainingHeight = estimatedTextHeight(text: String(remaining), style: style, width: width, inlineRuns: remainingRuns)
        let remainingLines = max(1, Int(round(remainingHeight / style.lineHeight)))
        
        // 1. Orphan control: If only 1 line fits on current page/column, push the whole paragraph
        // We only push if we are NOT already at the top of a column/page to prevent infinite loops.
        if prefixLines == 1 && maxHeight < columnTextHeight {
            return ""
        }
        
        // 2. Widow control: If only 1 line flows to the next page/column, pull another line from current page
        if remainingLines == 1 && prefixLines >= 3 {
            let targetHeight = Double(prefixLines - 1) * style.lineHeight
            var lowerBound = 1
            var upperBound = prefix.count
            var bestCount = 1
            
            while lowerBound <= upperBound {
                let mid = (lowerBound + upperBound) / 2
                let candidate = String(prefix.prefix(mid)).trimmedForLayout
                let mappedRuns = InlineRun.mapRuns(prefixRuns, toSubstringFrom: 0, length: candidate.count)
                let height = estimatedTextHeight(text: candidate, style: style, width: width, inlineRuns: mappedRuns)
                if height <= targetHeight {
                    bestCount = max(mid, 1)
                    lowerBound = mid + 1
                } else {
                    upperBound = mid - 1
                }
            }
            
            let broken = smartBreakPrefix(of: prefix, maximumCount: bestCount)
            return applyChineseTypesettingRules(candidatePrefix: broken, fullText: prefix, style: style, maxHeight: targetHeight, width: width)
        }
        
        return prefix
    }
}
