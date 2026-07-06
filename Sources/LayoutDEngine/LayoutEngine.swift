import CoreText
import Foundation
import LayoutDCore

public final class LayoutHeightCache: @unchecked Sendable {
    public static let shared = LayoutHeightCache()
    private init() {}
    
    struct Key: Hashable {
        let text: String
        let fontName: String
        let fontSize: Double
        let lineHeight: Double
        let firstLineIndent: Double
        let layoutDirection: LayoutDirection?
        let width: Double
        let inlineRuns: [InlineRun]?
        let compositeFont: [CompositeFontClass: CompositeFontMapping]?
    }
    
    private let lock = NSLock()
    private var cache: [Key: Double] = [:]
    
    public func get(text: String, style: ParagraphStyle, width: Double, inlineRuns: [InlineRun]? = nil) -> Double? {
        let key = Key(
            text: text,
            fontName: style.fontName,
            fontSize: style.fontSize,
            lineHeight: style.lineHeight,
            firstLineIndent: style.firstLineIndent,
            layoutDirection: style.layoutDirection,
            width: width,
            inlineRuns: inlineRuns,
            compositeFont: style.compositeFont
        )
        lock.lock()
        defer { lock.unlock() }
        return cache[key]
    }
    
    public func set(text: String, style: ParagraphStyle, width: Double, inlineRuns: [InlineRun]? = nil, height: Double) {
        let key = Key(
            text: text,
            fontName: style.fontName,
            fontSize: style.fontSize,
            lineHeight: style.lineHeight,
            firstLineIndent: style.firstLineIndent,
            layoutDirection: style.layoutDirection,
            width: width,
            inlineRuns: inlineRuns,
            compositeFont: style.compositeFont
        )
        lock.lock()
        defer { lock.unlock() }
        if cache.count >= 5000 {
            cache.removeAll()
        }
        cache[key] = height
    }
    
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }
    
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return cache.count
    }
}


/// Single source of truth for how many front-matter pages (cover, contents)
/// precede the content pages. The content engine numbers pages from 1 and adds
/// this offset to reach the absolute page number used by page setup, plans and
/// preflight. NOTE: this still assumes a fixed front-matter size; multi-page
/// contents or extra front matter would require deriving this from the assembled
/// front matter instead of a constant (see docs/architecture.md known limitations).
private let frontMatterPageCount = 2

/// Geometry of the running header, shared by header generation so the value is
/// defined in exactly one place rather than scattered as literals.
private let runningHeaderTopY = 24.0
private let runningHeaderHeight = 16.0

public protocol LayoutEngineProtocol: Sendable {
    func layout(project: BookProject) -> LaidOutDocument
}

public struct LayoutEngine: LayoutEngineProtocol {
    public init() {}

    public func layout(project: BookProject) -> LaidOutDocument {
        var context = LayoutContext(project: project)
        context.addRunningHeader(project.metadata.title)
        context.applyPlanIfPresent()

        for section in project.sections {
            context.addSectionTitle(section.title)
            for story in section.stories {
                context.addStory(story)
            }
        }

        return context.finishWithFrontMatter()
    }
}

private struct LayoutContext {
    let project: BookProject
    var pages: [LaidOutPage] = []
    var issues: [LayoutIssue] = []

    private var currentPage: LaidOutPage
    private var cursorX: Double
    private var cursorY: Double
    private var currentColumnTopY: Double
    private var currentColumn: Int = 0
    private var placedAssetIds = Set<UUID>()
    private var placedParagraphIds = Set<UUID>()
    private var tableOfContents: [TableOfContentsEntry] = []
    private var figureCounter = 0
    
    private var currentPageFootnoteParagraphs: [Paragraph] = []
    private var currentPageSideNoteParagraphs: [(Paragraph, Double)] = []
    private var threadedRemainingText: [UUID: String] = [:]
    
    private var footnoteStyle: ParagraphStyle {
        ParagraphStyle(
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
    }

    private var sideNoteStyle: ParagraphStyle {
        ParagraphStyle(
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
    }

    init(project: BookProject) {
        self.project = project
        self.currentPage = LaidOutPage(number: 1)
        let initialPageNumber = 1 + frontMatterPageCount
        let margins = project.resolvedMargins(for: initialPageNumber)
        let setup = project.pageSetup
        
        let leftMargin = setup.facingPages
            ? (initialPageNumber % 2 == 1 ? margins.left : margins.right)
            : margins.left
            
        let rightMargin = setup.facingPages
            ? (initialPageNumber % 2 == 1 ? margins.right : margins.left)
            : margins.right
            
        if setup.layoutDirection == .vertical {
            self.cursorX = setup.pageSize.width - rightMargin
            self.cursorY = margins.top
            self.currentColumnTopY = margins.top
        } else {
            self.cursorX = leftMargin
            self.cursorY = margins.top
            self.currentColumnTopY = margins.top
        }
    }

    mutating func addRunningHeader(_ title: String) {
        let actualPageNumber = currentAbsolutePageNumber
        guard project.resolvedShowHeadersFooters(for: actualPageNumber) else {
            return
        }
        let rect = Rect(
            x: pageLeftMargin(for: actualPageNumber),
            y: runningHeaderTopY,
            width: contentWidth,
            height: runningHeaderHeight
        )
        currentPage.frames.append(
            PageFrame(kind: .runningHeader, rect: rect, styleId: StyleID.caption.rawValue, content: .text(title))
        )
    }

    mutating func addSectionTitle(_ title: String) {
        tableOfContents.append(TableOfContentsEntry(level: 1, title: title, pageNumber: currentPage.number))
        addText(title, style: .heading1, kind: .text)
    }

    mutating func addStory(_ story: Story) {
        if !story.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           tableOfContents.last?.title != story.title {
            tableOfContents.append(TableOfContentsEntry(level: 2, title: story.title, pageNumber: currentPage.number))
        }

        for paragraph in story.paragraphs {
            if placedParagraphIds.contains(paragraph.id) {
                continue
            }

            switch paragraph.kind {
            case .footnote, .sideNote:
                continue
            default:
                break
            }

            if case .figure(let assetId) = paragraph.kind {
                if let asset = project.assets.first(where: { $0.id == assetId }) {
                    addAsset(asset, sourceParagraphId: paragraph.id)
                } else {
                    issues.append(
                        LayoutIssue(
                            severity: .warning,
                            message: "书稿引用了不存在的图片素材",
                            category: .references,
                            pageNumber: currentPage.number
                        )
                    )
                }
                continue
            }

            // 正文里的子标题（H2+）也进目录，否则静态目录只剩书名级 H1、需用户在
            // InDesign 手动「更新目录」才补全。level 1 走 addSectionTitle 不在此重复收集。
            if case .heading(let level) = paragraph.kind, level >= 2 {
                let headingTitle = paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !headingTitle.isEmpty, tableOfContents.last?.title != headingTitle {
                    tableOfContents.append(TableOfContentsEntry(level: level, title: headingTitle, pageNumber: currentPage.number))
                }
            }

            let style = project.styles.paragraphStyle(id: paragraph.styleId)
            let frameKind = frameKind(for: paragraph.kind)

            if project.pageSetup.layoutDirection == .vertical {
                let minReqWidth = style.lineHeight + style.spaceBefore + style.spaceAfter
                let leftLimit = pageLeftMargin(for: currentAbsolutePageNumber)
                if cursorX - minReqWidth < leftLimit {
                    advanceToNextColumnOrPage()
                }
            } else {
                let minReqHeight = style.lineHeight + style.spaceBefore + style.spaceAfter
                if remainingColumnHeight < minReqHeight {
                    advanceToNextColumnOrPage()
                }
            }
            
            for fnId in paragraph.safeAnchoredFootnoteIds {
                if let fnParagraph = story.paragraphs.first(where: { $0.id == fnId }) {
                    if !currentPageFootnoteParagraphs.contains(where: { $0.id == fnId }) {
                        currentPageFootnoteParagraphs.append(fnParagraph)
                    }
                }
            }
            
            addText(paragraph.text, style: style, kind: frameKind, anchoredSideNoteIds: paragraph.safeAnchoredSideNoteIds, sourceParagraphId: paragraph.id)

            for assetId in paragraph.anchoredAssetIds {
                if let asset = project.assets.first(where: { $0.id == assetId }) {
                    addAsset(asset, sourceParagraphId: paragraph.id)
                }
            }
        }
    }

    mutating func finish() -> LaidOutDocument {
        layoutFootnotesAndSideNotesOnCurrentPage()
        if !currentPage.frames.isEmpty || pages.isEmpty {
            pages.append(currentPage)
        }
        // 手动插入的空白页可能排在所有正文内容之后——正常翻页只在内容溢出时才触发
        // advanceToNextPage()/applyPlanIfPresent()，不会主动去看最后一页之后还有没有
        // 排版计划。这里补一次：只要下一页确实有计划（哪怕只是空白页占位）就继续
        // materialize；命中 reservesBlankPage/有 blocks 的计划，plan 内部的
        // advanceToNextPage() 会自己把该页追加进 pages 并推进到下一页，外层循环接着
        // 检查更后面的页码，从而级联多页插入。不这样补，在文档末尾插入空白页会因为
        // 没有内容触发翻页而悄悄没有反应。
        while project.appliedLayoutPlans?[absolutePageNumber(for: pages.count + 1)] != nil {
            let countBefore = pages.count
            currentPage = LaidOutPage(number: pages.count + 1)
            applyPlanIfPresent()
            if pages.count == countBefore {
                // 极端情况下计划命中了但没有触发翻页（既没有 blocks 也不满足
                // reservesBlankPage，比如只带了 marginOverride）——避免死循环，
                // 这页也补上（非空才追加，跟上面的判断一致）后退出。
                if !currentPage.frames.isEmpty {
                    pages.append(currentPage)
                }
                break
            }
        }
        return LaidOutDocument(projectId: project.id, pages: pages, issues: issues)
    }

    mutating func finishWithFrontMatter() -> LaidOutDocument {
        let contentDocument = finish()
        let contentPages = contentDocument.pages.map { renumberedPage($0, offset: frontMatterPageCount) }
        let shiftedIssues = contentDocument.issues.map { shiftedIssue($0, offset: frontMatterPageCount) }
        let shiftedContents = tableOfContents.map {
            TableOfContentsEntry(level: $0.level, title: $0.title, pageNumber: $0.pageNumber + frontMatterPageCount)
        }

        return LaidOutDocument(
            projectId: project.id,
            pages: [
                makeCoverPage(number: 1),
                makeContentsPage(number: 2, entries: shiftedContents)
            ] + contentPages,
            issues: shiftedIssues
        )
    }

    private mutating func addText(_ text: String, style: ParagraphStyle, kind: PageFrameKind, anchoredSideNoteIds: [UUID] = [], sourceParagraphId: UUID? = nil) {
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

    private func frameKind(for paragraphKind: ParagraphKind) -> PageFrameKind {
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

    private func shouldKeepHeadingWithNext(style: ParagraphStyle, height: Double) -> Bool {
        guard style.id == StyleID.heading1.rawValue || style.id == StyleID.heading2.rawValue else {
            return false
        }

        let bodyStyle = project.styles.paragraphStyle(id: StyleID.body.rawValue)
        let minimumFollowingTextHeight = bodyStyle.lineHeight * 2
        let requiredHeight = style.spaceBefore + height + style.spaceAfter + minimumFollowingTextHeight
        return remainingColumnHeight < requiredHeight && remainingColumnHeight < columnTextHeight
    }

    private mutating func addFlowingText(_ text: String, style: ParagraphStyle, kind: PageFrameKind, anchoredSideNoteIds: [UUID] = [], sourceParagraphId: UUID? = nil, inlineRuns: [InlineRun]? = nil) {
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

    private var isVertical: Bool {
        project.pageSetup.layoutDirection == .vertical
    }

    private var contentHeight: Double {
        let margins = project.resolvedMargins(for: currentAbsolutePageNumber)
        return project.pageSetup.pageSize.height - margins.top - margins.bottom
    }

    private mutating func addFlowingVerticalText(_ text: String, style: ParagraphStyle, kind: PageFrameKind, anchoredSideNoteIds: [UUID] = [], sourceParagraphId: UUID? = nil, inlineRuns: [InlineRun]? = nil) {
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

    private mutating func placeTextFrame(
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

    private func fittingPrefix(
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
        
        let attributedString = ChineseTypesetting.makeAttributedString(text: text, style: style, inlineRuns: inlineRuns)
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

    private func smartBreakPrefix(of text: String, maximumCount: Int) -> String {
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

    private func applyChineseTypesettingRules(
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

    private func applyWidowOrphanControls(
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

    private mutating func addAsset(_ asset: Asset, sourceParagraphId: UUID? = nil) {
        if asset.role == .spread {
            addSpreadAsset(asset)
            return
        }
        placedAssetIds.insert(asset.id)
        figureCounter += 1
        let imageWidth = imageWidth(for: asset)
        let desiredHeight = imageHeight(for: asset, width: imageWidth)
        if shouldSpanColumns(asset) {
            prepareWideAssetPlacement(requiredHeight: desiredHeight + 42)
        } else {
            advanceIfNeeded(desiredHeight + 42)
        }

        let imageRect = Rect(x: cursorX, y: cursorY, width: imageWidth, height: desiredHeight)
        currentPage.frames.append(PageFrame(kind: .image, rect: imageRect, content: .asset(asset.id), sourceParagraphId: sourceParagraphId))
        cursorY += desiredHeight + 4

        if let caption = asset.caption {
            let caption = numberedCaption(caption, number: figureCounter)
            let captionRect = Rect(x: cursorX, y: cursorY, width: imageWidth, height: 28)
            currentPage.frames.append(
                PageFrame(kind: .caption, rect: captionRect, styleId: StyleID.caption.rawValue, content: .text(caption), sourceParagraphId: sourceParagraphId)
            )
            cursorY += 34
        } else {
            issues.append(
                LayoutIssue(
                    severity: .warning,
                    message: "图片 \(asset.fileName) 缺少图注",
                    category: .assets,
                    pageNumber: currentPage.number
                )
            )
        }

        if let effectiveDPI = effectiveDPI(asset: asset, widthPoints: imageRect.width), effectiveDPI < 220 {
            issues.append(
                LayoutIssue(
                    severity: .warning,
                    message: "图片 \(asset.fileName) 预计印刷分辨率低于 220 DPI",
                    category: .assets,
                    pageNumber: currentPage.number
                )
            )
        }

        snapToBaseline()
        if shouldSpanColumns(asset) {
            currentColumnTopY = cursorY
        }
    }

    private mutating func addSpreadAsset(_ asset: Asset) {
        placedAssetIds.insert(asset.id)
        figureCounter += 1
        
        let setup = project.pageSetup
        let pageWidth = setup.pageSize.width
        let leftMargin = pageLeftMargin(for: 2)
        let rightMargin = pageRightMargin(for: 3)
        let totalWidth = (pageWidth - leftMargin) + (pageWidth - rightMargin)
        
        let desiredHeight = imageHeight(for: asset, width: totalWidth)
        let requiredHeight = desiredHeight + 42
        
        if currentAbsolutePageNumber % 2 == 1 {
            advanceToNextPage()
        }

        let bottomLimit = resolvedBottomLimit(for: currentAbsolutePageNumber)
        if cursorY + requiredHeight > bottomLimit {
            advanceToNextPage()
            advanceToNextPage()
        }

        let leftX = pageLeftMargin(for: currentAbsolutePageNumber)
        let leftWidth = pageWidth - leftX
        let leftRect = Rect(x: leftX, y: cursorY, width: leftWidth, height: desiredHeight)
        currentPage.frames.append(PageFrame(
            kind: .image,
            rect: leftRect,
            content: .spreadAsset(assetId: asset.id, isLeftHalf: true)
        ))
        
        let spreadY = cursorY
        
        advanceToNextPage()
        
        let rightWidth = pageWidth - pageRightMargin(for: currentAbsolutePageNumber)
        let rightRect = Rect(x: 0, y: spreadY, width: rightWidth, height: desiredHeight)
        currentPage.frames.append(PageFrame(
            kind: .image,
            rect: rightRect,
            content: .spreadAsset(assetId: asset.id, isLeftHalf: false)
        ))
        
        cursorY = spreadY + desiredHeight + 4
        
        if let caption = asset.caption {
            let captionText = numberedCaption(caption, number: figureCounter)
            let captionRect = Rect(x: 0, y: cursorY, width: rightWidth, height: 28)
            currentPage.frames.append(PageFrame(
                kind: .caption,
                rect: captionRect,
                styleId: StyleID.caption.rawValue,
                content: .text(captionText)
            ))
            cursorY += 34
        } else {
            issues.append(
                LayoutIssue(
                    severity: .warning,
                    message: "图片 \(asset.fileName) 缺少图注",
                    category: .assets,
                    pageNumber: currentPage.number
                )
            )
        }
        
        if let effectiveDPI = effectiveDPI(asset: asset, widthPoints: totalWidth), effectiveDPI < 220 {
            issues.append(
                LayoutIssue(
                    severity: .warning,
                    message: "图片 \(asset.fileName) 预计印刷分辨率低于 220 DPI",
                    category: .assets,
                    pageNumber: currentPage.number
                )
            )
        }
        
        snapToBaseline()
    }

    private func imageWidth(for asset: Asset) -> Double {
        shouldSpanColumns(asset) ? contentWidth : columnWidth
    }

    private func shouldSpanColumns(_ asset: Asset) -> Bool {
        asset.role == .hero || asset.role == .comparison
    }

    private mutating func prepareWideAssetPlacement(requiredHeight: Double) {
        if currentColumn != 0 {
            advanceToNextPage()
        }

        let bottomLimit = resolvedBottomLimit(for: currentAbsolutePageNumber)
        if cursorY + requiredHeight > bottomLimit {
            advanceToNextPage()
        }

        currentColumn = 0
        if isVertical {
            cursorX = project.pageSetup.pageSize.width - pageRightMargin(for: currentAbsolutePageNumber)
        } else {
            cursorX = pageLeftMargin(for: currentAbsolutePageNumber)
        }
    }

    private func imageHeight(for asset: Asset, width: Double) -> Double {
        let aspectRatio = imageAspectRatio(for: asset)
        let naturalHeight = width / aspectRatio
        let roleMultiplier: Double
        let maximumHeight: Double

        switch asset.role {
        case .hero:
            roleMultiplier = 0.90
            maximumHeight = 320
        case .diagram, .chart, .comparison:
            roleMultiplier = asset.role == .comparison ? 0.85 : 1.10
            maximumHeight = asset.role == .comparison ? 300 : 220
        case .step:
            roleMultiplier = 0.95
            maximumHeight = 190
        case .photo:
            roleMultiplier = 1.0
            maximumHeight = 200
        case .decorative:
            roleMultiplier = 0.65
            maximumHeight = 120
        case .spread:
            roleMultiplier = 0.90
            maximumHeight = 320
        }

        return max(86, min(naturalHeight * roleMultiplier, maximumHeight))
    }

    private func imageAspectRatio(for asset: Asset) -> Double {
        guard asset.pixelWidth > 0, asset.pixelHeight > 0 else {
            return 1.5
        }
        return max(Double(asset.pixelWidth) / Double(asset.pixelHeight), 0.2)
    }

    private func effectiveDPI(asset: Asset, widthPoints: Double) -> Double? {
        guard asset.pixelWidth > 0, widthPoints > 0 else {
            return asset.dpi
        }
        return Double(asset.pixelWidth) / (widthPoints / 72)
    }

    private func numberedCaption(_ caption: String, number: Int) -> String {
        let caption = caption.trimmedForLayout
        guard !caption.hasPrefix("图") else {
            return caption
        }
        return "图\(number) \(caption)"
    }

    private mutating func advanceIfNeeded(_ requiredHeight: Double) {
        let bottomLimit = resolvedBottomLimit(for: currentAbsolutePageNumber)
        guard cursorY + requiredHeight > bottomLimit else { return }

        advanceToNextColumnOrPage()
    }

    private mutating func advanceToNextColumnOrPage() {
        let columns = project.resolvedColumns(for: currentAbsolutePageNumber)
        if currentColumn + 1 < columns {
            currentColumn += 1
            let actualPageNumber = currentAbsolutePageNumber
            let margins = project.resolvedMargins(for: actualPageNumber)
            if isVertical {
                let rowHeight = columnTextHeight
                let gutter = project.resolvedGutter(for: actualPageNumber)
                currentColumnTopY = margins.top + Double(currentColumn) * (rowHeight + gutter)
                cursorX = project.pageSetup.pageSize.width - pageRightMargin(for: actualPageNumber)
                cursorY = currentColumnTopY
            } else {
                cursorX = pageLeftMargin(for: actualPageNumber) + Double(currentColumn) * (columnWidth + project.resolvedGutter(for: actualPageNumber))
                cursorY = currentColumnTopY
            }
        } else {
            advanceToNextPage()
        }
    }

    private mutating func advanceToNextPage() {
        layoutFootnotesAndSideNotesOnCurrentPage()
        pages.append(currentPage)
        let newPageNumber = pages.count + 1
        currentPage = LaidOutPage(number: newPageNumber)
        currentColumn = 0
        let absPageNum = absolutePageNumber(for: newPageNumber)
        let margins = project.resolvedMargins(for: absPageNum)
        if isVertical {
            cursorX = project.pageSetup.pageSize.width - pageRightMargin(for: absPageNum)
            cursorY = margins.top
            currentColumnTopY = margins.top
        } else {
            cursorX = pageLeftMargin(for: absPageNum)
            cursorY = margins.top
            currentColumnTopY = margins.top
        }
        addRunningHeader(project.metadata.title)
        
        applyPlanIfPresent()
    }

    private mutating func snapToBaseline() {
        let grid = project.resolvedBaselineGrid
        cursorY = ceil(cursorY / grid) * grid
    }

    private func normalizedText(_ text: String, isTable: Bool = false) -> String {
        if isTable {
            return text.trimmedForLayout
        }
        let collapsed = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmedForLayout
        return normalizedCJKWesternSpacing(collapsed)
    }

    private func normalizedCJKWesternSpacing(_ text: String) -> String {
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

    private func shouldInsertSpaceBetween(_ left: Character, _ right: Character) -> Bool {
        (left.isCJKIdeograph && right.isWesternAlphanumeric)
            || (left.isWesternAlphanumeric && right.isCJKIdeograph)
    }

    private func getImageRectsOnCurrentPage() -> [Rect] {
        var rects: [Rect] = []
        for frame in currentPage.frames {
            if frame.kind == .image {
                rects.append(frame.rect)
            }
        }
        let actualPageNumber = currentAbsolutePageNumber
        if let plans = project.appliedLayoutPlans,
           let plan = plans[actualPageNumber] {
            let pageSize = project.pageSetup.pageSize
            for block in plan.blocks {
                if block.kind == .image {
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

    private func estimatedTextHeightWithExclusions(
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

    private func estimatedTextHeight(text: String, style: ParagraphStyle, width: Double, inlineRuns: [InlineRun]? = nil) -> Double {
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
    private func estimatedTableHeight(cells: [[String]], style: ParagraphStyle) -> Double {
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

    private func estimatedFootnoteHeight(_ paragraph: Paragraph) -> Double {
        let text = paragraph.text
        let style = footnoteStyle
        let width = contentWidth
        return estimatedTextHeight(text: text, style: style, width: width, inlineRuns: paragraph.inlineRuns)
    }

    private var currentPageFootnoteHeight: Double {
        if currentPageFootnoteParagraphs.isEmpty {
            return 0.0
        }
        return currentPageFootnoteParagraphs.reduce(0.0) { sum, p in
            sum + estimatedFootnoteHeight(p)
        }
    }

    private func resolvedBottomLimit(for pageNumber: Int) -> Double {
        let margins = project.resolvedMargins(for: pageNumber)
        let fnHeight = currentPageFootnoteHeight
        let baseBottomLimit = project.pageSetup.pageSize.height - margins.bottom
        if fnHeight > 0 {
            return baseBottomLimit - fnHeight - 24
        }
        return baseBottomLimit
    }

    private mutating func layoutFootnotesAndSideNotesOnCurrentPage() {
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



    /// Renders a front-matter page (cover / contents) from its LayoutPlan when the
    /// user has manually edited it, so color / position / text / style overrides
    /// take effect. These pages are otherwise regenerated every layout and would
    /// silently discard edits. Returns nil when there's no valid plan, letting the
    /// caller fall back to default generation (no behavior change for untouched books).
    private mutating func frontMatterPageFromPlan(number: Int) -> LaidOutPage? {
        guard let plan = project.appliedLayoutPlans?[number],
              !plan.blocks.isEmpty,
              planValidationFailures(plan).isEmpty else {
            return nil
        }
        let pageSize = project.pageSetup.pageSize
        let frames: [PageFrame] = plan.blocks.map { block in
            let rect = Rect(
                x: block.frame.x * pageSize.width,
                y: block.frame.y * pageSize.height,
                width: block.frame.width * pageSize.width,
                height: block.frame.height * pageSize.height
            )
            let kind: PageFrameKind
            switch block.kind {
            case .text: kind = .text
            case .image: kind = .image
            case .caption: kind = .caption
            case .component: kind = .callout
            case .rectangle: kind = .rectangle
            case .line: kind = .line
            }
            let content: FrameContent
            if block.kind == .rectangle || block.kind == .line {
                content = .empty
            } else {
                switch block.contentReference {
                case .generated(let str):
                    content = .text(str)
                case .paragraph(let id):
                    content = .text(findParagraph(id: id)?.text ?? "")
                case .asset(let id):
                    content = .asset(id)
                case .storyRange(let sid, let start, let end):
                    content = .text(collectParagraphTexts(storyId: sid, startId: start, endId: end))
                }
            }
            let styleId = block.styleId ?? defaultStyleId(for: block.kind)
            return PageFrame(
                id: block.id,
                kind: kind,
                rect: rect,
                styleId: styleId,
                content: content,
                backgroundColorHex: block.backgroundColorHex,
                strokeColorHex: block.strokeColorHex,
                strokeWidth: block.strokeWidth,
                textColorHex: block.textColorHex,
                maskShape: block.maskShape
            )
        }
        return LaidOutPage(number: number, frames: frames)
    }

    private func defaultStyleId(for kind: LayoutBlockKind) -> String? {
        switch kind {
        case .text: return StyleID.body.rawValue
        case .caption: return StyleID.caption.rawValue
        case .component: return StyleID.callout.rawValue
        case .image, .rectangle, .line: return nil
        }
    }

    private mutating func makeCoverPage(number: Int) -> LaidOutPage {
        if let planned = frontMatterPageFromPlan(number: number) {
            return planned
        }
        let setup = project.pageSetup
        let margins = project.resolvedMargins(for: number)
        let contentWidth = setup.pageSize.width - margins.left - margins.right
        let leftMargin = pageLeftMargin(for: number)
        var frames: [PageFrame] = [
            PageFrame(
                kind: .text,
                rect: Rect(x: leftMargin, y: 180, width: contentWidth, height: 72),
                styleId: StyleID.heading1.rawValue,
                content: .text(project.metadata.title)
            )
        ]

        if let subtitle = project.metadata.subtitle, !subtitle.isEmpty {
            frames.append(
                PageFrame(
                    kind: .text,
                    rect: Rect(x: leftMargin, y: 266, width: contentWidth, height: 36),
                    styleId: StyleID.heading2.rawValue,
                    content: .text(subtitle)
                )
            )
        }

        frames.append(
            PageFrame(
                kind: .text,
                rect: Rect(x: leftMargin, y: setup.pageSize.height - 150, width: contentWidth, height: 24),
                styleId: StyleID.caption.rawValue,
                content: .text(project.metadata.author)
            )
        )

        if let publisher = project.metadata.publisher, !publisher.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            frames.append(
                PageFrame(
                    kind: .text,
                    rect: Rect(x: leftMargin, y: setup.pageSize.height - 120, width: contentWidth, height: 18),
                    styleId: StyleID.caption.rawValue,
                    content: .text(publisher)
                )
            )
        }

        return LaidOutPage(number: number, frames: frames)
    }

    private mutating func makeContentsPage(number: Int, entries: [TableOfContentsEntry]) -> LaidOutPage {
        if let planned = frontMatterPageFromPlan(number: number) {
            return planned
        }
        let setup = project.pageSetup
        let margins = project.resolvedMargins(for: number)
        let contentWidth = setup.pageSize.width - margins.left - margins.right
        let leftMargin = pageLeftMargin(for: number)
        let body = entries.isEmpty
            ? "暂无章节"
            : entries.map { entry in
                let indent = entry.level > 1 ? "    " : ""
                return "\(indent)\(entry.title)\t\(entry.pageNumber)"
            }.joined(separator: "\n")

        return LaidOutPage(
            number: number,
            frames: [
                PageFrame(
                    kind: .text,
                    rect: Rect(x: leftMargin, y: margins.top, width: contentWidth, height: 42),
                    styleId: StyleID.heading1.rawValue,
                    content: .text("目录")
                ),
                PageFrame(
                    kind: .text,
                    rect: Rect(x: leftMargin, y: margins.top + 72, width: contentWidth, height: 420),
                    styleId: StyleID.body.rawValue,
                    content: .text(body),
                    tableOfContentsEntries: entries
                )
            ]
        )
    }

    private func renumberedPage(_ page: LaidOutPage, offset: Int) -> LaidOutPage {
        LaidOutPage(id: page.id, number: page.number + offset, frames: page.frames)
    }

    private func shiftedIssue(_ issue: LayoutIssue, offset: Int) -> LayoutIssue {
        LayoutIssue(
            id: issue.id,
            severity: issue.severity,
            message: issue.message,
            category: issue.category,
            suggestedFix: issue.suggestedFix,
            autoFixKind: issue.autoFixKind,
            pageNumber: issue.pageNumber.map { $0 + offset },
            frameId: issue.frameId
        )
    }

    private var currentAbsolutePageNumber: Int {
        absolutePageNumber(for: currentPage.number)
    }

    /// Converts a content-relative page number (1-based, content pages only) into
    /// the absolute book page number that page setup, plans, and preflight use.
    private func absolutePageNumber(for contentPageNumber: Int) -> Int {
        contentPageNumber + frontMatterPageCount
    }

    private var contentWidth: Double {
        let setup = project.pageSetup
        let margins = project.resolvedMargins(for: currentAbsolutePageNumber)
        return setup.pageSize.width - margins.left - margins.right
    }

    private var columnWidth: Double {
        if isVertical {
            return contentWidth
        } else {
            let columns = project.resolvedColumns(for: currentAbsolutePageNumber)
            let totalGutter = Double(max(columns - 1, 0)) * project.resolvedGutter(for: currentAbsolutePageNumber)
            return (contentWidth - totalGutter) / Double(max(columns, 1))
        }
    }

    private var columnTextHeight: Double {
        if isVertical {
            let columns = project.resolvedColumns(for: currentAbsolutePageNumber)
            let totalGutter = Double(max(columns - 1, 0)) * project.resolvedGutter(for: currentAbsolutePageNumber)
            return (contentHeight - totalGutter) / Double(max(columns, 1))
        } else {
            let margins = project.resolvedMargins(for: currentAbsolutePageNumber)
            return resolvedBottomLimit(for: currentAbsolutePageNumber) - margins.top
        }
    }

    private var remainingColumnHeight: Double {
        if isVertical {
            let leftLimit = pageLeftMargin(for: currentAbsolutePageNumber)
            return cursorX - leftLimit
        } else {
            return resolvedBottomLimit(for: currentAbsolutePageNumber) - cursorY
        }
    }

    /// Validates an advisory layout plan against the rules the renderer relies on.
    /// Returns human-readable failure reasons; an empty array means the plan is
    /// safe to render. Kept pure so it is independently testable.
    func planValidationFailures(_ plan: LayoutPlan) -> [String] {
        var failures: [String] = []
        let epsilon = 0.001
        let blockIds = Set(plan.blocks.map(\.id))

        for (index, block) in plan.blocks.enumerated() {
            let frame = block.frame
            let label = "块 \(index + 1)"

            if frame.width <= 0 || frame.height <= 0 {
                failures.append("\(label) 尺寸非正")
            }
            if frame.x < -epsilon || frame.y < -epsilon
                || frame.x + frame.width > 1 + epsilon
                || frame.y + frame.height > 1 + epsilon {
                failures.append("\(label) 超出页面归一化范围")
            }

            switch block.contentReference {
            case .paragraph(let id):
                if findParagraph(id: id) == nil {
                    failures.append("\(label) 引用了不存在的段落")
                }
            case .asset(let id):
                if !project.assets.contains(where: { $0.id == id }) {
                    failures.append("\(label) 引用了不存在的素材")
                }
            case .storyRange(let storyId, let startId, let endId):
                if let story = findStory(id: storyId) {
                    let ids = Set(story.paragraphs.map(\.id))
                    if !ids.contains(startId) || !ids.contains(endId) {
                        failures.append("\(label) 的文本范围端点不在该 story 内")
                    }
                } else {
                    failures.append("\(label) 引用了不存在的 story")
                }
            case .generated:
                break
            }

            if let next = block.nextThreadedBlockId, !blockIds.contains(next) {
                failures.append("\(label) 的后继线程块不在本计划内")
            }
            if let prev = block.previousThreadedBlockId, !blockIds.contains(prev) {
                failures.append("\(label) 的前驱线程块不在本计划内")
            }
            
            // 2. Check component roles
            if block.kind == .component {
                if !isApprovedComponentRole(block.role) {
                    failures.append("\(label) 的组件角色 \(block.role) 未在组件样式库中定义")
                }
            }
            
            // 3. Check custom color overrides (must be valid hex or approved token ID)
            if let bg = block.backgroundColorHex {
                if !isValidColorValue(bg) {
                    failures.append("\(label) 的背景色引用了未批准的 Token 或无效颜色值 \(bg)")
                }
            }
            if let stroke = block.strokeColorHex {
                if !isValidColorValue(stroke) {
                    failures.append("\(label) 的描边色引用了未批准的 Token 或无效颜色值 \(stroke)")
                }
            }
            if let txt = block.textColorHex {
                if !isValidColorValue(txt) {
                    failures.append("\(label) 的文字颜色引用了未批准的 Token 或无效颜色值 \(txt)")
                }
            }
        }

        // 4. 字体合规：批准 = 本机已装（任何字体形态：family/显示名/PostScript/本地化名）。
        // 用户 2026-06-24 决定不再维护手写白名单——装了的字体就能用，没装的（拼错/缺字体）才拒。
        for style in project.styles.paragraphStyles {
            if !Self.isFontInstalled(style.fontName) {
                failures.append("样式 \(style.displayName) 使用了未安装字体 \(style.fontName)")
            }
            if let cf = style.compositeFont {
                for (cls, mapping) in cf {
                    if !Self.isFontInstalled(mapping.fontName) {
                        failures.append("样式 \(style.displayName) 的 \(cls.rawValue) 分支使用了未安装字体 \(mapping.fontName)")
                    }
                }
            }
        }

        return failures
    }

    /// 本机已装字体的全部名字形态（family / 显示名 / PostScript / 本地化中文名），构建一次。
    static let installedFontNames: Set<String> = {
        var set = Set<String>()
        let collection = CTFontCollectionCreateFromAvailableFonts(nil)
        let descriptors = (CTFontCollectionCreateMatchingFontDescriptors(collection) as? [CTFontDescriptor]) ?? []
        for d in descriptors {
            for key in [kCTFontFamilyNameAttribute, kCTFontDisplayNameAttribute, kCTFontNameAttribute] {
                if let s = CTFontDescriptorCopyAttribute(d, key) as? String { set.insert(s) }
            }
            let font = CTFontCreateWithFontDescriptor(d, 12, nil)
            if let loc = CTFontCopyLocalizedName(font, kCTFontFamilyNameKey, nil) as String? { set.insert(loc) }
        }
        return set
    }()

    /// 字体是否本机已装。接受 family / PostScript / 本地化名等任意形态；
    /// 也接受「家族名+字重」（如 "Heiti SC Medium"）——去掉末尾字重词后家族仍命中即可。
    static func isFontInstalled(_ name: String) -> Bool {
        if installedFontNames.contains(name) { return true }
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            let family = parts.dropLast().joined(separator: " ")
            if installedFontNames.contains(family) { return true }
        }
        return false
    }

    private func isValidColorValue(_ val: String) -> Bool {
        let clean = val.trimmingCharacters(in: .whitespacesAndNewlines)
        // Accept any round-trippable PrintColor storage form: `#RRGGBB` / `#RGB` /
        // bare hex, and — crucially — the print-native `cmyk(C,M,Y,K)` form. This
        // is the exact vocabulary the app writes into color fields, so a
        // CMYK-picked color no longer trips validation and gets the whole page's
        // frozen plan discarded (which was silently regenerating frame ids and
        // dropping both the selection and the CMYK color).
        if PrintColor(string: clean) != nil {
            return true
        }
        // Also accept an approved style color token id.
        if project.styles.colorHex(clean) != nil {
            return true
        }
        return false
    }

    private func isApprovedComponentRole(_ role: String) -> Bool {
        let cleanRole = role.lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        
        let builtInRoles: Set<String> = [
            "callout", "table", "footnotedivider", "footnote", "sidenote", "caption", "knowledgecard", "datatable", "figurecaption", "runningheader"
        ]
        if builtInRoles.contains(cleanRole) {
            return true
        }
        
        let approvedIds = project.styles.safeComponentStyles.flatMap {
            [$0.id, $0.frameKind.rawValue]
        }.map {
            $0.lowercased()
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: "_", with: "")
        }
        return approvedIds.contains(cleanRole)
    }

    mutating func applyPlanIfPresent() {
        let actualPageNumber = currentAbsolutePageNumber
        guard let plans = project.appliedLayoutPlans,
              let plan = plans[actualPageNumber] else {
            return
        }

        // AI/template plans are advisory: the engine validates them before
        // rendering. An invalid plan is rejected (falling back to deterministic
        // flow on this page) and surfaced as a preflight issue, rather than
        // producing broken frames. This is the "engine decides" guarantee.
        let failures = planValidationFailures(plan)
        guard failures.isEmpty else {
            issues.append(
                LayoutIssue(
                    severity: .warning,
                    message: "第 \(actualPageNumber) 页的版式计划无效，已回退到自动排版：\(failures.joined(separator: "；"))",
                    category: .layout,
                    suggestedFix: "检查该页 LayoutPlan 的块坐标、尺寸和内容引用是否有效。",
                    pageNumber: currentPage.number
                )
            )
            return
        }

        let pageSize = project.pageSetup.pageSize

        for block in plan.blocks {
            let rect = Rect(
                x: block.frame.x * pageSize.width,
                y: block.frame.y * pageSize.height,
                width: block.frame.width * pageSize.width,
                height: block.frame.height * pageSize.height
            )
            
            let kind: PageFrameKind
            switch block.kind {
            case .text: kind = .text
            case .image: kind = .image
            case .caption: kind = .caption
            case .component: kind = .callout
            case .rectangle: kind = .rectangle
            case .line: kind = .line
            }

            let textToPlace: String
            if block.previousThreadedBlockId != nil {
                textToPlace = threadedRemainingText[block.id] ?? ""
                threadedRemainingText.removeValue(forKey: block.id)
            } else {
                switch block.contentReference {
                case .asset(_):
                    textToPlace = ""
                case .generated(let str):
                    textToPlace = str
                case .paragraph(let paragraphId):
                    if let paragraph = findParagraph(id: paragraphId) {
                        textToPlace = paragraph.text
                        placedParagraphIds.insert(paragraphId)
                    } else {
                        textToPlace = ""
                    }
                case .storyRange(let storyId, let startId, let endId):
                    textToPlace = collectParagraphTexts(storyId: storyId, startId: startId, endId: endId)
                }
            }

            let styleId: String?
            if block.kind == .text {
                styleId = StyleID.body.rawValue
            } else if block.kind == .caption {
                styleId = StyleID.caption.rawValue
            } else if block.kind == .component {
                styleId = StyleID.callout.rawValue
            } else {
                styleId = nil
            }
            
            let resolvedStyle = styleId != nil ? project.styles.paragraphStyle(id: styleId!) : ParagraphStyle.body
            let normalizedTextToPlace = normalizedText(textToPlace)

            var sourceParagraphId: UUID? = nil
            var blockRuns: [InlineRun]? = nil
            if case .paragraph(let paragraphId) = block.contentReference {
                sourceParagraphId = paragraphId
                if let paragraph = findParagraph(id: paragraphId),
                   let runs = paragraph.inlineRuns {
                    blockRuns = InlineRun.mapRuns(runs, from: paragraph.text, to: normalizedTextToPlace)
                }
            }

            let content: FrameContent
            if block.kind == .rectangle || block.kind == .line {
                // Shapes carry no text/image; they render from fill/stroke alone.
                content = .empty
            } else if case .asset(let assetId) = block.contentReference {
                content = .asset(assetId)
            } else {
                if block.kind == .text && (block.nextThreadedBlockId != nil || block.previousThreadedBlockId != nil) {
                    let fittedText = fittingPrefix(of: normalizedTextToPlace, style: resolvedStyle, maxHeight: rect.height, width: rect.width, x: rect.x, y: rect.y, inlineRuns: blockRuns)
                    content = .text(fittedText)
                    if let nextId = block.nextThreadedBlockId {
                        let remaining = String(normalizedTextToPlace.dropFirst(fittedText.count)).trimmedForLayout
                        if !remaining.isEmpty {
                            threadedRemainingText[nextId] = remaining
                        }
                    }
                } else {
                    content = .text(normalizedTextToPlace)
                }
            }
            
            let imageRects = getImageRectsOnCurrentPage()
            let overlaps = imageRects.filter { $0.intersects(rect) }
            
            currentPage.frames.append(PageFrame(
                id: block.id,
                kind: kind,
                rect: rect,
                styleId: styleId,
                content: content,
                backgroundColorHex: block.backgroundColorHex,
                strokeColorHex: block.strokeColorHex,
                strokeWidth: block.strokeWidth,
                textColorHex: block.textColorHex,
                sourceParagraphId: sourceParagraphId,
                maskShape: block.maskShape,
                exclusionRects: overlaps.isEmpty ? nil : overlaps
            ))
        }
        
        if !plan.blocks.isEmpty || plan.reservesBlankPage {
            advanceToNextPage()
        }
    }

    private func findParagraph(id: UUID) -> Paragraph? {
        for section in project.sections {
            for story in section.stories {
                if let paragraph = story.paragraphs.first(where: { $0.id == id }) {
                    return paragraph
                }
            }
        }
        return nil
    }

    private func findStory(id: UUID) -> Story? {
        for section in project.sections {
            if let story = section.stories.first(where: { $0.id == id }) {
                return story
            }
        }
        return nil
    }

    private mutating func collectParagraphTexts(storyId: UUID, startId: UUID, endId: UUID) -> String {
        guard let story = findStory(id: storyId) else {
            return ""
        }
        
        var collecting = false
        var texts: [String] = []
        
        for paragraph in story.paragraphs {
            if paragraph.id == startId {
                collecting = true
            }
            if collecting {
                texts.append(paragraph.text)
                placedParagraphIds.insert(paragraph.id)
            }
            if paragraph.id == endId {
                break
            }
        }
        
        return texts.joined(separator: "\n")
    }

    private func pageLeftMargin(for pageNumber: Int) -> Double {
        let setup = project.pageSetup
        let margins = project.resolvedMargins(for: pageNumber)
        if setup.facingPages {
            return pageNumber % 2 == 1 ? margins.left : margins.right
        }
        return margins.left
    }

    private func pageRightMargin(for pageNumber: Int) -> Double {
        let setup = project.pageSetup
        let margins = project.resolvedMargins(for: pageNumber)
        if setup.facingPages {
            return pageNumber % 2 == 1 ? margins.right : margins.left
        }
        return margins.right
    }
}

private extension LayoutPlan {
    var reservesBlankPage: Bool {
        guard blocks.isEmpty else { return false }
        if notes.contains(where: { $0.contains("空白页") }) {
            return true
        }
        return marginOverride == nil
            && columnsOverride == nil
            && showHeadersFooters == nil
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
