import CoreText
import Foundation
import LayoutDCore

public struct LayoutDocumentValidator {
    public init() {}

    public func validate(document: LaidOutDocument, project: BookProject) -> [LayoutIssue] {
        var issues: [LayoutIssue] = []
        let assetIds = Set(project.assets.map(\.id))

        issues.append(contentsOf: validatePageSequence(document.pages))

        for page in document.pages {
            issues.append(contentsOf: validateFrames(page.frames, page: page, project: project, assetIds: assetIds))
            issues.append(contentsOf: validateOverlaps(page.frames, page: page))
        }

        return issues
    }

    private func validatePageSequence(_ pages: [LaidOutPage]) -> [LayoutIssue] {
        guard !pages.isEmpty else {
            return [LayoutIssue(severity: .error, message: "文档没有可导出的页面")]
        }

        var issues: [LayoutIssue] = []
        let numbers = pages.map(\.number)
        let duplicateNumbers = Dictionary(grouping: numbers, by: { $0 })
            .filter { $0.value.count > 1 }
            .keys

        for number in duplicateNumbers.sorted() {
            issues.append(
                LayoutIssue(severity: .error, message: "文档存在重复页码：\(number)", pageNumber: number)
            )
        }

        let expectedNumbers = Array(1...pages.count)
        if numbers != expectedNumbers {
            let actualNumbers = numbers.map(String.init).joined(separator: ",")
            issues.append(
                LayoutIssue(
                    severity: .error,
                    message: "文档页码不连续，应为 1...\(pages.count)，实际为 \(actualNumbers)"
                )
            )
        }

        return issues
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
            if let firstCharacter = trimmed.first, forbiddenLineStartCharacters.contains(firstCharacter) {
                issues.append(
                    LayoutIssue(
                        severity: .warning,
                        message: "页面 \(page.number) 存在中文禁则问题：行首出现禁用标点「\(firstCharacter)」",
                        pageNumber: page.number,
                        frameId: frame.id
                    )
                )
            }

            if let lastCharacter = trimmed.last, forbiddenLineEndCharacters.contains(lastCharacter) {
                issues.append(
                    LayoutIssue(
                        severity: .warning,
                        message: "页面 \(page.number) 存在中文禁则问题：行尾出现禁用标点「\(lastCharacter)」",
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

private let forbiddenLineStartCharacters = Set("，。、！？：；）】》」』,.!?:;)]}%")
private let forbiddenLineEndCharacters = Set("（【《「『([{")

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
