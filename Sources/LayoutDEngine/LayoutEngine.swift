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
    private var tableOfContents: [TableOfContentsEntry] = []
    private var figureCounter = 0

    init(project: BookProject) {
        self.project = project
        self.currentPage = LaidOutPage(number: 1)
        self.cursorX = project.pageSetup.margins.left
        self.cursorY = project.pageSetup.margins.top
        self.currentColumnTopY = project.pageSetup.margins.top
    }

    mutating func addRunningHeader(_ title: String) {
        let setup = project.pageSetup
        let rect = Rect(x: setup.margins.left, y: 24, width: contentWidth, height: 16)
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
            if case .figure(let assetId) = paragraph.kind {
                if let asset = project.assets.first(where: { $0.id == assetId }) {
                    addAsset(asset)
                } else {
                    issues.append(
                        LayoutIssue(
                            severity: .warning,
                            message: "书稿引用了不存在的图片素材",
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

        return smartBreakPrefix(of: text, maximumCount: bestCount)
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

    private mutating func addAsset(_ asset: Asset) {
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
                    pageNumber: currentPage.number
                )
            )
        }

        if let effectiveDPI = effectiveDPI(asset: asset, widthPoints: imageRect.width), effectiveDPI < 220 {
            issues.append(
                LayoutIssue(
                    severity: .warning,
                    message: "图片 \(asset.fileName) 预计印刷分辨率低于 220 DPI",
                    pageNumber: currentPage.number
                )
            )
        }

        snapToBaseline()
        if shouldSpanColumns(asset) {
            currentColumnTopY = cursorY
        }
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

        let bottomLimit = project.pageSetup.pageSize.height - project.pageSetup.margins.bottom
        if cursorY + requiredHeight > bottomLimit {
            advanceToNextPage()
        }

        currentColumn = 0
        cursorX = project.pageSetup.margins.left
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
        let bottomLimit = project.pageSetup.pageSize.height - project.pageSetup.margins.bottom
        guard cursorY + requiredHeight > bottomLimit else { return }

        advanceToNextColumnOrPage()
    }

    private mutating func advanceToNextColumnOrPage() {
        if currentColumn + 1 < project.pageSetup.columns {
            currentColumn += 1
            cursorX = project.pageSetup.margins.left + Double(currentColumn) * (columnWidth + project.pageSetup.gutter)
            cursorY = currentColumnTopY
        } else {
            advanceToNextPage()
        }
    }

    private mutating func advanceToNextPage() {
        pages.append(currentPage)
        currentPage = LaidOutPage(number: pages.count + 1)
        currentColumn = 0
        cursorX = project.pageSetup.margins.left
        cursorY = project.pageSetup.margins.top
        currentColumnTopY = project.pageSetup.margins.top
        addRunningHeader(project.metadata.title)
    }

    private mutating func snapToBaseline() {
        let grid = project.pageSetup.baselineGrid
        cursorY = ceil(cursorY / grid) * grid
    }

    private func normalizedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmedForLayout
    }

    private func estimatedTextHeight(text: String, style: ParagraphStyle, width: Double) -> Double {
        let attributedString = CFAttributedStringCreate(
            nil,
            text as CFString,
            textAttributes(style: style)
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString!)
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

    private func textAttributes(style: ParagraphStyle) -> CFDictionary {
        let font = CTFontCreateWithName(style.fontName as CFString, style.fontSize, nil)
        var minimumLineHeight = CGFloat(style.lineHeight)
        var maximumLineHeight = CGFloat(style.lineHeight)
        var firstLineIndent = CGFloat(style.firstLineIndent)
        var lineBreakMode = CTLineBreakMode.byWordWrapping

        return withUnsafePointer(to: &minimumLineHeight) { minimumLineHeightPointer in
            withUnsafePointer(to: &maximumLineHeight) { maximumLineHeightPointer in
                withUnsafePointer(to: &firstLineIndent) { firstLineIndentPointer in
                    withUnsafePointer(to: &lineBreakMode) { lineBreakModePointer in
                        let settings = [
                            CTParagraphStyleSetting(
                                spec: .minimumLineHeight,
                                valueSize: MemoryLayout<CGFloat>.size,
                                value: minimumLineHeightPointer
                            ),
                            CTParagraphStyleSetting(
                                spec: .maximumLineHeight,
                                valueSize: MemoryLayout<CGFloat>.size,
                                value: maximumLineHeightPointer
                            ),
                            CTParagraphStyleSetting(
                                spec: .firstLineHeadIndent,
                                valueSize: MemoryLayout<CGFloat>.size,
                                value: firstLineIndentPointer
                            ),
                            CTParagraphStyleSetting(
                                spec: .lineBreakMode,
                                valueSize: MemoryLayout<CTLineBreakMode>.size,
                                value: lineBreakModePointer
                            )
                        ]
                        let paragraphStyle = CTParagraphStyleCreate(settings, settings.count)

                        return [
                            kCTFontAttributeName: font,
                            kCTParagraphStyleAttributeName: paragraphStyle
                        ] as CFDictionary
                    }
                }
            }
        }
    }

    private func makeCoverPage(number: Int) -> LaidOutPage {
        let setup = project.pageSetup
        let contentWidth = setup.pageSize.width - setup.margins.left - setup.margins.right
        var frames: [PageFrame] = [
            PageFrame(
                kind: .text,
                rect: Rect(x: setup.margins.left, y: 180, width: contentWidth, height: 72),
                styleId: StyleID.heading1.rawValue,
                content: .text(project.metadata.title)
            )
        ]

        if let subtitle = project.metadata.subtitle, !subtitle.isEmpty {
            frames.append(
                PageFrame(
                    kind: .text,
                    rect: Rect(x: setup.margins.left, y: 266, width: contentWidth, height: 36),
                    styleId: StyleID.heading2.rawValue,
                    content: .text(subtitle)
                )
            )
        }

        frames.append(
            PageFrame(
                kind: .text,
                rect: Rect(x: setup.margins.left, y: setup.pageSize.height - 150, width: contentWidth, height: 24),
                styleId: StyleID.caption.rawValue,
                content: .text(project.metadata.author)
            )
        )

        if let publisher = project.metadata.publisher, !publisher.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            frames.append(
                PageFrame(
                    kind: .text,
                    rect: Rect(x: setup.margins.left, y: setup.pageSize.height - 120, width: contentWidth, height: 18),
                    styleId: StyleID.caption.rawValue,
                    content: .text(publisher)
                )
            )
        }

        return LaidOutPage(number: number, frames: frames)
    }

    private func makeContentsPage(number: Int, entries: [TableOfContentsEntry]) -> LaidOutPage {
        let setup = project.pageSetup
        let contentWidth = setup.pageSize.width - setup.margins.left - setup.margins.right
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
                    rect: Rect(x: setup.margins.left, y: setup.margins.top, width: contentWidth, height: 42),
                    styleId: StyleID.heading1.rawValue,
                    content: .text("目录")
                ),
                PageFrame(
                    kind: .text,
                    rect: Rect(x: setup.margins.left, y: setup.margins.top + 72, width: contentWidth, height: 420),
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
            pageNumber: issue.pageNumber.map { $0 + offset },
            frameId: issue.frameId
        )
    }

    private var contentWidth: Double {
        let setup = project.pageSetup
        return setup.pageSize.width - setup.margins.left - setup.margins.right
    }

    private var columnWidth: Double {
        let setup = project.pageSetup
        let totalGutter = Double(max(setup.columns - 1, 0)) * setup.gutter
        return (contentWidth - totalGutter) / Double(max(setup.columns, 1))
    }

    private var columnTextHeight: Double {
        project.pageSetup.pageSize.height
            - project.pageSetup.margins.top
            - project.pageSetup.margins.bottom
    }

    private var remainingColumnHeight: Double {
        project.pageSetup.pageSize.height - project.pageSetup.margins.bottom - cursorY
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
