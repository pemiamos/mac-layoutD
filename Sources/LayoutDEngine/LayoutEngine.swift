import CoreText
import Foundation
import LayoutDCore

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

    init(project: BookProject) {
        self.project = project
        self.currentPage = LaidOutPage(number: 1)
        let initialPageNumber = 3
        let margins = project.resolvedMargins(for: initialPageNumber)
        let facingPages = project.pageSetup.facingPages
        self.cursorX = facingPages ? (initialPageNumber % 2 == 1 ? margins.left : margins.right) : margins.left
        self.cursorY = margins.top
        self.currentColumnTopY = margins.top
    }

    mutating func addRunningHeader(_ title: String) {
        let actualPageNumber = currentPage.number + 2
        guard project.resolvedShowHeadersFooters(for: actualPageNumber) else {
            return
        }
        let rect = Rect(x: pageLeftMargin(for: actualPageNumber), y: 24, width: contentWidth, height: 16)
        currentPage.frames.append(
            PageFrame(kind: .text, rect: rect, styleId: StyleID.caption.rawValue, content: .text(title))
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

            if case .figure(let assetId) = paragraph.kind {
                if let asset = project.assets.first(where: { $0.id == assetId }) {
                    addAsset(asset)
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

            let style = project.styles.paragraphStyle(id: paragraph.styleId)
            let frameKind = frameKind(for: paragraph.kind)
            addText(paragraph.text, style: style, kind: frameKind)

            for assetId in paragraph.anchoredAssetIds {
                if let asset = project.assets.first(where: { $0.id == assetId }) {
                    addAsset(asset)
                }
            }
        }
    }

    mutating func finish() -> LaidOutDocument {
        if !currentPage.frames.isEmpty || pages.isEmpty {
            pages.append(currentPage)
        }
        return LaidOutDocument(projectId: project.id, pages: pages, issues: issues)
    }

    mutating func finishWithFrontMatter() -> LaidOutDocument {
        let contentDocument = finish()
        let frontMatterPageCount = 2
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

    private mutating func addText(_ text: String, style: ParagraphStyle, kind: PageFrameKind) {
        let text = normalizedText(text)
        let height = estimatedTextHeight(text: text, style: style, width: columnWidth)
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
            addFlowingText(text, style: style, kind: kind)
            return
        }

        placeTextFrame(text, height: height, style: style, kind: kind, spaceBefore: style.spaceBefore)
    }

    private func frameKind(for paragraphKind: ParagraphKind) -> PageFrameKind {
        switch paragraphKind {
        case .callout:
            return .callout
        case .table:
            return .table
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

    private mutating func addFlowingText(_ text: String, style: ParagraphStyle, kind: PageFrameKind) {
        var remainingText = text
        var isFirstSegment = true

        while !remainingText.isEmpty {
            let spaceBefore = isFirstSegment ? style.spaceBefore : 0
            if remainingColumnHeight < style.lineHeight + spaceBefore + style.spaceAfter {
                advanceToNextColumnOrPage()
            }

            let maxSegmentHeight = max(
                style.lineHeight,
                remainingColumnHeight - spaceBefore - style.spaceAfter
            )
            let segment = fittingPrefix(
                of: remainingText,
                style: style,
                maxHeight: maxSegmentHeight
            )
            if segment.isEmpty {
                advanceToNextColumnOrPage()
                continue
            }
            let segmentHeight = estimatedTextHeight(text: segment, style: style, width: columnWidth)
            placeTextFrame(segment, height: segmentHeight, style: style, kind: kind, spaceBefore: spaceBefore)
            remainingText.removeFirst(segment.count)
            remainingText = remainingText.trimmedForLayout
            isFirstSegment = false
        }
    }

    private mutating func placeTextFrame(
        _ text: String,
        height: Double,
        style: ParagraphStyle,
        kind: PageFrameKind,
        spaceBefore: Double
    ) {
        advanceIfNeeded(height + spaceBefore + style.spaceAfter)
        cursorY += spaceBefore
        let rect = Rect(x: cursorX, y: cursorY, width: columnWidth, height: height)
        currentPage.frames.append(PageFrame(kind: kind, rect: rect, styleId: style.id, content: .text(text)))
        cursorY += height + style.spaceAfter
        snapToBaseline()
    }

    private func fittingPrefix(of text: String, style: ParagraphStyle, maxHeight: Double) -> String {
        if estimatedTextHeight(text: text, style: style, width: columnWidth) <= maxHeight {
            return text
        }

        var lowerBound = 1
        var upperBound = text.count
        var bestCount = 1

        while lowerBound <= upperBound {
            let mid = (lowerBound + upperBound) / 2
            let candidate = String(text.prefix(mid)).trimmedForLayout
            let height = estimatedTextHeight(text: candidate, style: style, width: columnWidth)
            if height <= maxHeight {
                bestCount = max(mid, 1)
                lowerBound = mid + 1
            } else {
                upperBound = mid - 1
            }
        }

        let broken = smartBreakPrefix(of: text, maximumCount: bestCount)
        let kinsokuPrefix = applyChineseTypesettingRules(candidatePrefix: broken, fullText: text, style: style, maxHeight: maxHeight)
        return applyWidowOrphanControls(prefix: kinsokuPrefix, fullText: text, style: style, maxHeight: maxHeight)
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
        maxHeight: Double
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
                let height = estimatedTextHeight(text: pulledCandidate, style: style, width: columnWidth)
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
        maxHeight: Double
    ) -> String {
        let prefix = prefix.trimmedForLayout
        guard !prefix.isEmpty else { return "" }
        let remaining = String(fullText.dropFirst(prefix.count)).trimmedForLayout
        guard !remaining.isEmpty else { return prefix }
        
        let prefixHeight = estimatedTextHeight(text: prefix, style: style, width: columnWidth)
        let prefixLines = max(1, Int(round(prefixHeight / style.lineHeight)))
        
        let remainingHeight = estimatedTextHeight(text: String(remaining), style: style, width: columnWidth)
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
                let height = estimatedTextHeight(text: candidate, style: style, width: columnWidth)
                if height <= targetHeight {
                    bestCount = max(mid, 1)
                    lowerBound = mid + 1
                } else {
                    upperBound = mid - 1
                }
            }
            
            let broken = smartBreakPrefix(of: prefix, maximumCount: bestCount)
            return applyChineseTypesettingRules(candidatePrefix: broken, fullText: prefix, style: style, maxHeight: targetHeight)
        }
        
        return prefix
    }

    private mutating func addAsset(_ asset: Asset) {
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
        currentPage.frames.append(PageFrame(kind: .image, rect: imageRect, content: .asset(asset.id)))
        cursorY += desiredHeight + 4

        if let caption = asset.caption {
            let caption = numberedCaption(caption, number: figureCounter)
            let captionRect = Rect(x: cursorX, y: cursorY, width: imageWidth, height: 28)
            currentPage.frames.append(
                PageFrame(kind: .caption, rect: captionRect, styleId: StyleID.caption.rawValue, content: .text(caption))
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
        
        if (currentPage.number + 2) % 2 == 1 {
            advanceToNextPage()
        }
        
        let bottomLimit = setup.pageSize.height - setup.margins.bottom
        if cursorY + requiredHeight > bottomLimit {
            advanceToNextPage()
            advanceToNextPage()
        }
        
        let leftX = pageLeftMargin(for: currentPage.number + 2)
        let leftWidth = pageWidth - leftX
        let leftRect = Rect(x: leftX, y: cursorY, width: leftWidth, height: desiredHeight)
        currentPage.frames.append(PageFrame(
            kind: .image,
            rect: leftRect,
            content: .spreadAsset(assetId: asset.id, isLeftHalf: true)
        ))
        
        let spreadY = cursorY
        
        advanceToNextPage()
        
        let rightWidth = pageWidth - pageRightMargin(for: currentPage.number + 2)
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

        let margins = project.resolvedMargins(for: currentAbsolutePageNumber)
        let bottomLimit = project.pageSetup.pageSize.height - margins.bottom
        if cursorY + requiredHeight > bottomLimit {
            advanceToNextPage()
        }

        currentColumn = 0
        cursorX = pageLeftMargin(for: currentAbsolutePageNumber)
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
        let margins = project.resolvedMargins(for: currentAbsolutePageNumber)
        let bottomLimit = project.pageSetup.pageSize.height - margins.bottom
        guard cursorY + requiredHeight > bottomLimit else { return }

        advanceToNextColumnOrPage()
    }

    private mutating func advanceToNextColumnOrPage() {
        let columns = project.resolvedColumns(for: currentAbsolutePageNumber)
        if currentColumn + 1 < columns {
            currentColumn += 1
            let actualPageNumber = currentPage.number + 2
            cursorX = pageLeftMargin(for: actualPageNumber) + Double(currentColumn) * (columnWidth + project.pageSetup.gutter)
            cursorY = currentColumnTopY
        } else {
            advanceToNextPage()
        }
    }

    private mutating func advanceToNextPage() {
        pages.append(currentPage)
        let newPageNumber = pages.count + 1
        currentPage = LaidOutPage(number: newPageNumber)
        currentColumn = 0
        let absPageNum = newPageNumber + 2
        let margins = project.resolvedMargins(for: absPageNum)
        cursorX = pageLeftMargin(for: absPageNum)
        cursorY = margins.top
        currentColumnTopY = margins.top
        addRunningHeader(project.metadata.title)
        
        applyPlanIfPresent()
    }

    private mutating func snapToBaseline() {
        let grid = project.pageSetup.baselineGrid
        cursorY = ceil(cursorY / grid) * grid
    }

    private func normalizedText(_ text: String) -> String {
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

    private func estimatedTextHeight(text: String, style: ParagraphStyle, width: Double) -> Double {
        let attributedString = ChineseTypesetting.makeAttributedString(text: text, style: style)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let constraint = CGSize(width: width, height: .greatestFiniteMagnitude)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: text.count),
            nil,
            constraint,
            nil
        )
        return max(ceil(size.height), style.lineHeight)
    }



    private func makeCoverPage(number: Int) -> LaidOutPage {
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

    private func makeContentsPage(number: Int, entries: [TableOfContentsEntry]) -> LaidOutPage {
        let setup = project.pageSetup
        let margins = project.resolvedMargins(for: number)
        let contentWidth = setup.pageSize.width - margins.left - margins.right
        let leftMargin = pageLeftMargin(for: number)
        let body = entries.isEmpty
            ? "暂无章节"
            : entries.map { entry in
                let indent = entry.level > 1 ? "    " : ""
                return "\(indent)\(entry.title)  \(entry.pageNumber)"
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
                    content: .text(body)
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
        currentPage.number + 2
    }

    private var contentWidth: Double {
        let setup = project.pageSetup
        let margins = project.resolvedMargins(for: currentAbsolutePageNumber)
        return setup.pageSize.width - margins.left - margins.right
    }

    private var columnWidth: Double {
        let setup = project.pageSetup
        let columns = project.resolvedColumns(for: currentAbsolutePageNumber)
        let totalGutter = Double(max(columns - 1, 0)) * setup.gutter
        return (contentWidth - totalGutter) / Double(max(columns, 1))
    }

    private var columnTextHeight: Double {
        let setup = project.pageSetup
        let margins = project.resolvedMargins(for: currentAbsolutePageNumber)
        return setup.pageSize.height - margins.top - margins.bottom
    }

    private var remainingColumnHeight: Double {
        let setup = project.pageSetup
        let margins = project.resolvedMargins(for: currentAbsolutePageNumber)
        return setup.pageSize.height - margins.bottom - cursorY
    }

    mutating func applyPlanIfPresent() {
        let actualPageNumber = currentPage.number + 2
        guard let plans = project.appliedLayoutPlans,
              let plan = plans[actualPageNumber] else {
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
            }
            
            let content: FrameContent
            switch block.contentReference {
            case .asset(let assetId):
                content = .asset(assetId)
            case .generated(let str):
                content = .text(str)
            case .paragraph(let paragraphId):
                if let paragraph = findParagraph(id: paragraphId) {
                    content = .text(paragraph.text)
                    placedParagraphIds.insert(paragraphId)
                } else {
                    content = .text("")
                }
            case .storyRange(let storyId, let startId, let endId):
                let texts = collectParagraphTexts(storyId: storyId, startId: startId, endId: endId)
                content = .text(texts)
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
            
            currentPage.frames.append(PageFrame(id: block.id, kind: kind, rect: rect, styleId: styleId, content: content))
        }
        
        if !plan.blocks.isEmpty {
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

private struct TableOfContentsEntry: Equatable {
    var level: Int
    var title: String
    var pageNumber: Int
}

private extension String {
    var trimmedForLayout: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
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
