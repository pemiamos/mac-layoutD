import CoreText
import Foundation
import LayoutDCore

extension LayoutContext {
    /// Renders a front-matter page (cover / contents) from its LayoutPlan when the
    /// user has manually edited it, so color / position / text / style overrides
    /// take effect. These pages are otherwise regenerated every layout and would
    /// silently discard edits. Returns nil when there's no valid plan, letting the
    /// caller fall back to default generation (no behavior change for untouched books).
    mutating func frontMatterPageFromPlan(number: Int) -> LaidOutPage? {
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

    func defaultStyleId(for kind: LayoutBlockKind) -> String? {
        switch kind {
        case .text: return StyleID.body.rawValue
        case .caption: return StyleID.caption.rawValue
        case .component: return StyleID.callout.rawValue
        case .image, .rectangle, .line: return nil
        }
    }

    mutating func makeCoverPage(number: Int) -> LaidOutPage {
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

    mutating func makeContentsPage(number: Int, entries: [TableOfContentsEntry]) -> LaidOutPage {
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

    func renumberedPage(_ page: LaidOutPage, offset: Int) -> LaidOutPage {
        LaidOutPage(id: page.id, number: page.number + offset, frames: page.frames)
    }

    func shiftedIssue(_ issue: LayoutIssue, offset: Int) -> LayoutIssue {
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
}
