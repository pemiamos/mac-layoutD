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

        context.placeUnusedAssets(project.assets)
        return context.finish()
    }
}

private struct LayoutContext {
    let project: BookProject
    var pages: [LaidOutPage] = []
    var issues: [LayoutIssue] = []

    private var currentPage: LaidOutPage
    private var cursorX: Double
    private var cursorY: Double
    private var currentColumn: Int = 0

    init(project: BookProject) {
        self.project = project
        self.currentPage = LaidOutPage(number: 1)
        self.cursorX = project.pageSetup.margins.left
        self.cursorY = project.pageSetup.margins.top
    }

    mutating func addRunningHeader(_ title: String) {
        let setup = project.pageSetup
        let rect = Rect(x: setup.margins.left, y: 24, width: contentWidth, height: 16)
        currentPage.frames.append(
            PageFrame(kind: .text, rect: rect, styleId: StyleID.caption.rawValue, content: .text(title))
        )
    }

    mutating func addSectionTitle(_ title: String) {
        addText(title, style: .heading1, kind: .text)
    }

    mutating func addStory(_ story: Story) {
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
            let frameKind: PageFrameKind = paragraph.kind == .callout ? .callout : .text
            addText(paragraph.text, style: style, kind: frameKind)

            for assetId in paragraph.anchoredAssetIds {
                if let asset = project.assets.first(where: { $0.id == assetId }) {
                    addAsset(asset)
                }
            }
        }
    }

    mutating func placeUnusedAssets(_ assets: [Asset]) {
        for asset in assets where asset.usage == .unused {
            addAsset(asset)
        }
    }

    mutating func finish() -> LaidOutDocument {
        if !currentPage.frames.isEmpty || pages.isEmpty {
            pages.append(currentPage)
        }
        return LaidOutDocument(projectId: project.id, pages: pages, issues: issues)
    }

    private mutating func addText(_ text: String, style: ParagraphStyle, kind: PageFrameKind) {
        let height = estimatedTextHeight(text: text, style: style, width: columnWidth)
        advanceIfNeeded(height + style.spaceBefore + style.spaceAfter)

        cursorY += style.spaceBefore
        let rect = Rect(x: cursorX, y: cursorY, width: columnWidth, height: height)
        currentPage.frames.append(PageFrame(kind: kind, rect: rect, styleId: style.id, content: .text(text)))
        cursorY += height + style.spaceAfter
        snapToBaseline()
    }

    private mutating func addAsset(_ asset: Asset) {
        let desiredHeight = min(columnWidth * 0.72, 180)
        advanceIfNeeded(desiredHeight + 22)

        let imageRect = Rect(x: cursorX, y: cursorY, width: columnWidth, height: desiredHeight)
        currentPage.frames.append(PageFrame(kind: .image, rect: imageRect, content: .asset(asset.id)))
        cursorY += desiredHeight + 4

        if let caption = asset.caption {
            let captionRect = Rect(x: cursorX, y: cursorY, width: columnWidth, height: 28)
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

        if let dpi = asset.dpi, dpi < 220 {
            issues.append(
                LayoutIssue(
                    severity: .warning,
                    message: "图片 \(asset.fileName) 分辨率低于 220 DPI",
                    pageNumber: currentPage.number
                )
            )
        }

        snapToBaseline()
    }

    private mutating func advanceIfNeeded(_ requiredHeight: Double) {
        let bottomLimit = project.pageSetup.pageSize.height - project.pageSetup.margins.bottom
        guard cursorY + requiredHeight > bottomLimit else { return }

        if currentColumn + 1 < project.pageSetup.columns {
            currentColumn += 1
            cursorX = project.pageSetup.margins.left + Double(currentColumn) * (columnWidth + project.pageSetup.gutter)
            cursorY = project.pageSetup.margins.top
        } else {
            pages.append(currentPage)
            currentPage = LaidOutPage(number: pages.count + 1)
            currentColumn = 0
            cursorX = project.pageSetup.margins.left
            cursorY = project.pageSetup.margins.top
            addRunningHeader(project.metadata.title)
        }
    }

    private mutating func snapToBaseline() {
        let grid = project.pageSetup.baselineGrid
        cursorY = ceil(cursorY / grid) * grid
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

    private var contentWidth: Double {
        let setup = project.pageSetup
        return setup.pageSize.width - setup.margins.left - setup.margins.right
    }

    private var columnWidth: Double {
        let setup = project.pageSetup
        let totalGutter = Double(max(setup.columns - 1, 0)) * setup.gutter
        return (contentWidth - totalGutter) / Double(max(setup.columns, 1))
    }
}
