import Foundation
import LayoutDCore

public enum PageLayoutTemplate: String, Codable, CaseIterable, Sendable {
    case textLedPage
    case imageLedPage
    case balancedImageText
    case knowledgeCardPage

    public var displayName: String {
        switch self {
        case .textLedPage:
            return "正文优先页"
        case .imageLedPage:
            return "图片主导页"
        case .balancedImageText:
            return "图文均衡页"
        case .knowledgeCardPage:
            return "知识卡片页"
        }
    }

    public var strategy: LayoutStrategy {
        switch self {
        case .textLedPage:
            return .textLed
        case .imageLedPage:
            return .imageLed
        case .balancedImageText:
            return .balanced
        case .knowledgeCardPage:
            return .knowledgeCard
        }
    }

    public var requiresImageAsset: Bool {
        switch self {
        case .imageLedPage, .balancedImageText:
            return true
        case .textLedPage, .knowledgeCardPage:
            return false
        }
    }

    public func makePlan(
        target: LayoutTarget,
        projectTitle: String,
        primaryAsset: Asset? = nil,
        variation: Int = 0
    ) -> LayoutPlan? {
        if requiresImageAsset, primaryAsset == nil {
            return nil
        }

        let fallbackCaption = primaryAsset?.caption ?? "待补充图注"
        let blocks: [LayoutPlanBlock]
        let notes: [String]

        switch self {
        case .textLedPage:
            if variation == 0 {
                blocks = [
                    LayoutPlanBlock(
                        kind: .text,
                        role: "body",
                        frame: Rect(x: 0.10, y: 0.10, width: 0.80, height: 0.72),
                        contentReference: .generated(projectTitle)
                    ),
                    LayoutPlanBlock(
                        kind: .component,
                        role: "knowledgeCard",
                        frame: Rect(x: 0.10, y: 0.84, width: 0.80, height: 0.10),
                        contentReference: .generated("可转化为知识卡片的重点解释")
                    )
                ]
                notes = ["正文阅读优先，适合叙述性强的页面。"]
            } else {
                blocks = [
                    LayoutPlanBlock(
                        kind: .component,
                        role: "knowledgeCard",
                        frame: Rect(x: 0.10, y: 0.10, width: 0.80, height: 0.10),
                        contentReference: .generated("可转化为知识卡片的重点解释")
                    ),
                    LayoutPlanBlock(
                        kind: .text,
                        role: "body",
                        frame: Rect(x: 0.10, y: 0.22, width: 0.80, height: 0.72),
                        contentReference: .generated(projectTitle)
                    )
                ]
                notes = ["正文优先（卡片置顶），适合叙述性强的页面。"]
            }
        case .imageLedPage:
            guard let asset = primaryAsset else { return nil }
            if variation == 0 {
                blocks = [
                    LayoutPlanBlock(
                        kind: .image,
                        role: "hero",
                        frame: Rect(x: 0.08, y: 0.10, width: 0.56, height: 0.46),
                        contentReference: .asset(asset.id)
                    ),
                    LayoutPlanBlock(
                        kind: .caption,
                        role: "caption",
                        frame: Rect(x: 0.08, y: 0.58, width: 0.56, height: 0.08),
                        contentReference: .generated(fallbackCaption)
                    ),
                    LayoutPlanBlock(
                        kind: .text,
                        role: "body",
                        frame: Rect(x: 0.68, y: 0.10, width: 0.24, height: 0.70),
                        contentReference: .generated("正文流入区")
                    )
                ]
                notes = ["图片承担主要解释功能，适合科普概念页或章节开篇页。"]
            } else {
                blocks = [
                    LayoutPlanBlock(
                        kind: .text,
                        role: "body",
                        frame: Rect(x: 0.08, y: 0.10, width: 0.24, height: 0.70),
                        contentReference: .generated("正文流入区")
                    ),
                    LayoutPlanBlock(
                        kind: .image,
                        role: "hero",
                        frame: Rect(x: 0.36, y: 0.10, width: 0.56, height: 0.46),
                        contentReference: .asset(asset.id)
                    ),
                    LayoutPlanBlock(
                        kind: .caption,
                        role: "caption",
                        frame: Rect(x: 0.36, y: 0.58, width: 0.56, height: 0.08),
                        contentReference: .generated(fallbackCaption)
                    )
                ]
                notes = ["图片主导（镜像排布），适合科普概念页。"]
            }
        case .balancedImageText:
            guard let asset = primaryAsset else { return nil }
            if variation == 0 {
                blocks = [
                    LayoutPlanBlock(
                        kind: .text,
                        role: "body",
                        frame: Rect(x: 0.08, y: 0.12, width: 0.40, height: 0.72),
                        contentReference: .generated("正文流入区")
                    ),
                    LayoutPlanBlock(
                        kind: .image,
                        role: "supporting",
                        frame: Rect(x: 0.54, y: 0.16, width: 0.38, height: 0.34),
                        contentReference: .asset(asset.id)
                    ),
                    LayoutPlanBlock(
                        kind: .caption,
                        role: "caption",
                        frame: Rect(x: 0.54, y: 0.52, width: 0.38, height: 0.08),
                        contentReference: .generated(fallbackCaption)
                    )
                ]
                notes = ["正文和图片权重均衡，适合解释密度较高的内页。"]
            } else {
                blocks = [
                    LayoutPlanBlock(
                        kind: .image,
                        role: "supporting",
                        frame: Rect(x: 0.08, y: 0.16, width: 0.38, height: 0.34),
                        contentReference: .asset(asset.id)
                    ),
                    LayoutPlanBlock(
                        kind: .caption,
                        role: "caption",
                        frame: Rect(x: 0.08, y: 0.52, width: 0.38, height: 0.08),
                        contentReference: .generated(fallbackCaption)
                    ),
                    LayoutPlanBlock(
                        kind: .text,
                        role: "body",
                        frame: Rect(x: 0.52, y: 0.12, width: 0.40, height: 0.72),
                        contentReference: .generated("正文流入区")
                    )
                ]
                notes = ["图文均衡（镜像排布），适合解释密度较高的内页。"]
            }
        case .knowledgeCardPage:
            if variation == 0 {
                blocks = [
                    LayoutPlanBlock(
                        kind: .text,
                        role: "concept",
                        frame: Rect(x: 0.12, y: 0.12, width: 0.76, height: 0.38),
                        contentReference: .generated(projectTitle)
                    ),
                    LayoutPlanBlock(
                        kind: .component,
                        role: "knowledgeCard",
                        frame: Rect(x: 0.12, y: 0.56, width: 0.76, height: 0.22),
                        contentReference: .generated("定义、例子、提示三段式知识卡片")
                    ),
                    LayoutPlanBlock(
                        kind: .caption,
                        role: "note",
                        frame: Rect(x: 0.12, y: 0.82, width: 0.76, height: 0.08),
                        contentReference: .generated("适合把章节重点压缩成可复习页面")
                    )
                ]
                notes = ["重点解释优先，适合章节小结、概念定义或复习页。"]
            } else {
                blocks = [
                    LayoutPlanBlock(
                        kind: .text,
                        role: "concept",
                        frame: Rect(x: 0.12, y: 0.12, width: 0.76, height: 0.38),
                        contentReference: .generated(projectTitle)
                    ),
                    LayoutPlanBlock(
                        kind: .caption,
                        role: "note",
                        frame: Rect(x: 0.12, y: 0.52, width: 0.76, height: 0.08),
                        contentReference: .generated("适合把章节重点压缩成可复习页面")
                    ),
                    LayoutPlanBlock(
                        kind: .component,
                        role: "knowledgeCard",
                        frame: Rect(x: 0.12, y: 0.62, width: 0.76, height: 0.22),
                        contentReference: .generated("定义、例子、提示三段式知识卡片")
                    )
                ]
                notes = ["重点解释页（精简布局），适合章节小结。"]
            }
        }

        return LayoutPlan(target: target, strategy: strategy, blocks: blocks, notes: notes)
    }
}

public struct PageLayoutTemplateCatalog: Sendable {
    public var templates: [PageLayoutTemplate]

    public init(templates: [PageLayoutTemplate] = PageLayoutTemplate.allCases) {
        self.templates = templates
    }

    public func plans(for project: BookProject, target: LayoutTarget) -> [LayoutPlan] {
        let primaryAsset = project.assets.first { $0.role != .decorative }
        var result: [LayoutPlan] = []
        for temp in templates {
            if let p0 = temp.makePlan(
                target: target,
                projectTitle: project.metadata.title,
                primaryAsset: primaryAsset,
                variation: 0
            ) {
                result.append(p0)
            }
            if let p1 = temp.makePlan(
                target: target,
                projectTitle: project.metadata.title,
                primaryAsset: primaryAsset,
                variation: 1
            ) {
                result.append(p1)
            }
        }
        return result
    }
}
