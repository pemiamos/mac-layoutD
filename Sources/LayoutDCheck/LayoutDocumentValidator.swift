import CoreText
import Foundation
import LayoutDCore

public struct LayoutDocumentValidator {
    public init() {}

    public func validate(document: LaidOutDocument, project: BookProject) -> [LayoutIssue] {
        var issues: [LayoutIssue] = []
        let assetIds = Set(project.assets.map(\.id))

        issues.append(contentsOf: validatePageSequence(document.pages))
        issues.append(contentsOf: validateTableOfContents(document.pages, project: project))

        for page in document.pages {
            issues.append(contentsOf: validateFrames(page.frames, page: page, project: project, assetIds: assetIds))
            issues.append(contentsOf: validateOverlaps(page.frames, page: page))
        }

        return issues
    }

    private func validatePageSequence(_ pages: [LaidOutPage]) -> [LayoutIssue] {
        guard !pages.isEmpty else {
            return [LayoutIssue(severity: .error, message: "文档没有可导出的页面", category: .pagination)]
        }

        var issues: [LayoutIssue] = []
        let numbers = pages.map(\.number)
        let duplicateNumbers = Dictionary(grouping: numbers, by: { $0 })
            .filter { $0.value.count > 1 }
            .keys

        for number in duplicateNumbers.sorted() {
            issues.append(
                LayoutIssue(severity: .error, message: "文档存在重复页码：\(number)", category: .pagination, pageNumber: number)
            )
        }

        let expectedNumbers = Array(1...pages.count)
        if numbers != expectedNumbers {
            let actualNumbers = numbers.map(String.init).joined(separator: ",")
            issues.append(
                LayoutIssue(
                    severity: .error,
                    message: "文档页码不连续，应为 1...\(pages.count)，实际为 \(actualNumbers)",
                    category: .pagination
                )
            )
        }

        return issues
    }

    private func validateTableOfContents(_ pages: [LaidOutPage], project: BookProject) -> [LayoutIssue] {
        guard let contentsPage = pages.first(where: { $0.number == 2 }) else {
            return []
        }

        let entries = contentsEntries(from: contentsPage)
        let expectedTitles = expectedContentsTitles(project: project)
        let visibleTitlePages = visibleTitlePages(in: pages, matching: expectedTitles)
        let pageNumbers = Set(pages.map(\.number))
        var issues: [LayoutIssue] = []

        for entry in entries {
            if !pageNumbers.contains(entry.pageNumber) {
                issues.append(
                    LayoutIssue(
                        severity: .error,
                        message: "目录引用了不存在的页码：\(entry.title) -> \(entry.pageNumber)",
                        category: .tableOfContents,
                        pageNumber: contentsPage.number,
                        frameId: entry.frameId
                    )
                )
                continue
            }

            if let actualPages = visibleTitlePages[entry.title], !actualPages.contains(entry.pageNumber) {
                let actual = actualPages.sorted().map(String.init).joined(separator: ",")
                issues.append(
                    LayoutIssue(
                        severity: .warning,
                        message: "目录页码不一致：\(entry.title) 标为第 \(entry.pageNumber) 页，实际标题在第 \(actual) 页",
                        category: .tableOfContents,
                        pageNumber: contentsPage.number,
                        frameId: entry.frameId
                    )
                )
            }
        }

        let entryTitles = Set(entries.map(\.title))
        for title in visibleTitlePages.keys.sorted() where !entryTitles.contains(title) {
            issues.append(
                LayoutIssue(
                    severity: .warning,
                    message: "目录缺少可见标题：\(title)",
                    category: .tableOfContents,
                    pageNumber: contentsPage.number
                )
            )
        }

        return issues
    }

    private func contentsEntries(from page: LaidOutPage) -> [ContentsEntry] {
        page.frames.flatMap { frame -> [ContentsEntry] in
            guard case .text(let text) = frame.content else {
                return []
            }

            return text
                .split(separator: "\n", omittingEmptySubsequences: true)
                .compactMap { line in
                    contentsEntry(from: String(line), frameId: frame.id)
                }
        }
    }

    private func contentsEntry(from line: String, frameId: UUID) -> ContentsEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != "目录", trimmed != "暂无章节" else {
            return nil
        }

        let pattern = #"^(.+?)\s+(\d+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              match.numberOfRanges == 3,
              let titleRange = Range(match.range(at: 1), in: trimmed),
              let pageRange = Range(match.range(at: 2), in: trimmed),
              let pageNumber = Int(trimmed[pageRange]) else {
            return nil
        }

        let title = String(trimmed[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return nil
        }

        return ContentsEntry(title: title, pageNumber: pageNumber, frameId: frameId)
    }

    private func expectedContentsTitles(project: BookProject) -> Set<String> {
        var titles = Set<String>()
        for section in project.sections {
            let sectionTitle = section.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sectionTitle.isEmpty {
                titles.insert(sectionTitle)
            }

            for story in section.stories {
                let storyTitle = story.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !storyTitle.isEmpty {
                    titles.insert(storyTitle)
                }
            }
        }
        return titles
    }

    private func visibleTitlePages(in pages: [LaidOutPage], matching expectedTitles: Set<String>) -> [String: Set<Int>] {
        var result: [String: Set<Int>] = [:]
        for page in pages where page.number != 2 {
            for frame in page.frames {
                guard case .text(let text) = frame.content else {
                    continue
                }

                let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard expectedTitles.contains(title) else {
                    continue
                }

                result[title, default: []].insert(page.number)
            }
        }
        return result
    }

    private func validateFrames(
        _ frames: [PageFrame],
        page: LaidOutPage,
        project: BookProject,
        assetIds: Set<UUID>
    ) -> [LayoutIssue] {
        var issues: [LayoutIssue] = []
        let pageBounds = Rect(x: 0, y: 0, width: project.pageSetup.pageSize.width, height: project.pageSetup.pageSize.height)

        for frame in frames {
            if frame.rect.width <= 0 || frame.rect.height <= 0 {
                issues.append(
                    LayoutIssue(
                        severity: .error,
                        message: "页面 \(page.number) 存在无效尺寸 frame",
                        category: .layout,
                        suggestedFix: "选中该 frame 后增大宽高，或恢复该页的流式排版。",
                        pageNumber: page.number,
                        frameId: frame.id
                    )
                )
            }

            if !pageBounds.contains(frame.rect) {
                issues.append(
                    LayoutIssue(
                        severity: .error,
                        message: "页面 \(page.number) 存在越界 frame",
                        category: .layout,
                        suggestedFix: "选中该 frame 后调整 x/y/宽高，使其完全落在页面范围内。",
                        pageNumber: page.number,
                        frameId: frame.id
                    )
                )
            }

            switch frame.content {
            case .text(let text):
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append(
                        LayoutIssue(
                            severity: .warning,
                            message: "页面 \(page.number) 存在空文本 frame",
                            category: .layout,
                            pageNumber: page.number,
                            frameId: frame.id
                        )
                    )
                }
                if !textFits(text, in: frame, project: project) {
                    issues.append(
                        LayoutIssue(
                            severity: .error,
                            message: "页面 \(page.number) 存在文本溢出 frame",
                            category: .layout,
                            suggestedFix: "增大文本框高度、降低字号/行高，或恢复流式排版让正文重新分页。",
                            pageNumber: page.number,
                            frameId: frame.id
                        )
                    )
                }
                issues.append(contentsOf: validateChineseLineBreaks(text, in: frame, page: page, project: project))
            case .asset(let assetId):
                if !assetIds.contains(assetId) {
                    issues.append(
                        LayoutIssue(
                            severity: .error,
                            message: "页面 \(page.number) 存在缺失图片 frame",
                            category: .references,
                            suggestedFix: "更换为项目素材库中存在的图片，或重新导入包含该素材的图片目录。",
                            pageNumber: page.number,
                            frameId: frame.id
                        )
                    )
                }
            case .empty:
                break
            }
        }

        return issues
    }

    private func textFits(_ text: String, in frame: PageFrame, project: BookProject) -> Bool {
        guard frame.rect.width > 0, frame.rect.height > 0 else {
            return false
        }

        let attributedString = CFAttributedStringCreate(
            nil,
            text as CFString,
            textAttributes(style: project.styles.paragraphStyle(id: frame.styleId ?? StyleID.body.rawValue))
        )!
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let path = CGMutablePath()
        path.addRect(
            CGRect(
                x: 0,
                y: 0,
                width: CGFloat(frame.rect.width),
                height: CGFloat(frame.rect.height)
            )
        )
        let ctFrame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: CFAttributedStringGetLength(attributedString)),
            path,
            nil
        )
        let visibleRange = CTFrameGetVisibleStringRange(ctFrame)
        return visibleRange.location + visibleRange.length >= CFAttributedStringGetLength(attributedString)
    }

    private func validateChineseLineBreaks(
        _ text: String,
        in frame: PageFrame,
        page: LaidOutPage,
        project: BookProject
    ) -> [LayoutIssue] {
        guard frame.rect.width > 0, frame.rect.height > 0 else {
            return []
        }

        return lineTexts(for: text, in: frame, project: project).flatMap { lineText -> [LayoutIssue] in
            let trimmed = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return []
            }

            var issues: [LayoutIssue] = []
            if let firstCharacter = trimmed.first, ChineseLineBreakRules.forbidsLineStart(firstCharacter) {
                issues.append(
                    LayoutIssue(
                        severity: .warning,
                        message: "页面 \(page.number) 存在中文禁则问题：行首出现禁用标点「\(firstCharacter)」",
                        category: .typography,
                        pageNumber: page.number,
                        frameId: frame.id
                    )
                )
            }

            if let lastCharacter = trimmed.last, ChineseLineBreakRules.forbidsLineEnd(lastCharacter) {
                issues.append(
                    LayoutIssue(
                        severity: .warning,
                        message: "页面 \(page.number) 存在中文禁则问题：行尾出现禁用标点「\(lastCharacter)」",
                        category: .typography,
                        pageNumber: page.number,
                        frameId: frame.id
                    )
                )
            }

            return issues
        }
    }

    private func lineTexts(for text: String, in frame: PageFrame, project: BookProject) -> [String] {
        let attributedString = CFAttributedStringCreate(
            nil,
            text as CFString,
            textAttributes(style: project.styles.paragraphStyle(id: frame.styleId ?? StyleID.body.rawValue))
        )!
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let path = CGMutablePath()
        path.addRect(
            CGRect(
                x: 0,
                y: 0,
                width: CGFloat(frame.rect.width),
                height: CGFloat(frame.rect.height)
            )
        )
        let ctFrame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: CFAttributedStringGetLength(attributedString)),
            path,
            nil
        )
        guard let lines = CTFrameGetLines(ctFrame) as? [CTLine] else {
            return []
        }

        return lines.compactMap { line in
            let range = CTLineGetStringRange(line)
            guard range.location != kCFNotFound, range.length > 0 else {
                return nil
            }

            let nsRange = NSRange(location: range.location, length: range.length)
            guard let range = Range(nsRange, in: text) else {
                return nil
            }
            return String(text[range])
        }
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

    private func validateOverlaps(_ frames: [PageFrame], page: LaidOutPage) -> [LayoutIssue] {
        let materialFrames = frames.filter { frame in
            switch frame.content {
            case .empty:
                return false
            case .text, .asset:
                return frame.rect.width > 0 && frame.rect.height > 0
            }
        }
        var issues: [LayoutIssue] = []

        for firstIndex in materialFrames.indices {
            for secondIndex in materialFrames.indices.dropFirst(firstIndex + 1) {
                let first = materialFrames[firstIndex]
                let second = materialFrames[secondIndex]
                guard first.rect.overlapArea(with: second.rect) > 4 else {
                    continue
                }
                guard !allowedOverlap(first, second) else {
                    continue
                }

                issues.append(
                    LayoutIssue(
                        severity: .error,
                        message: "页面 \(page.number) 存在 frame 重叠",
                        category: .layout,
                        suggestedFix: "选中重叠 frame 后移动或缩小，必要时恢复该页的流式排版。",
                        pageNumber: page.number,
                        frameId: second.id
                    )
                )
            }
        }

        return issues
    }

    private func allowedOverlap(_ first: PageFrame, _ second: PageFrame) -> Bool {
        // Running headers can share vertical bands with page content only when they do not materially intersect.
        first.content == .empty || second.content == .empty
    }
}

private struct ContentsEntry {
    var title: String
    var pageNumber: Int
    var frameId: UUID
}

private extension Rect {
    var maxX: Double { x + width }
    var maxY: Double { y + height }

    func contains(_ other: Rect) -> Bool {
        other.x >= x
            && other.y >= y
            && other.maxX <= maxX
            && other.maxY <= maxY
    }

    func overlapArea(with other: Rect) -> Double {
        let overlapWidth = max(0, min(maxX, other.maxX) - max(x, other.x))
        let overlapHeight = max(0, min(maxY, other.maxY) - max(y, other.y))
        return overlapWidth * overlapHeight
    }
}
