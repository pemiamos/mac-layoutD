import Foundation
import LayoutDCore

public protocol LayoutAdvisor: Sendable {
    func proposePlans(for project: BookProject, target: LayoutTarget) -> [LayoutPlan]
}

public struct RuleBasedLayoutAdvisor: LayoutAdvisor {
    public init() {}

    public func proposePlans(for project: BookProject, target: LayoutTarget) -> [LayoutPlan] {
        let imageAssets = project.assets.filter { $0.role != .decorative }
        guard let firstAsset = imageAssets.first else {
            return [textLedPlan(project: project, target: target)]
        }

        return [
            imageLedPlan(asset: firstAsset, target: target),
            balancedPlan(asset: firstAsset, target: target),
            textLedPlan(project: project, target: target)
        ]
    }

    private func imageLedPlan(asset: Asset, target: LayoutTarget) -> LayoutPlan {
        LayoutPlan(
            target: target,
            strategy: .imageLed,
            blocks: [
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
                    contentReference: .generated(asset.caption ?? "待补充图注")
                ),
                LayoutPlanBlock(
                    kind: .text,
                    role: "body",
                    frame: Rect(x: 0.68, y: 0.10, width: 0.24, height: 0.70),
                    contentReference: .generated("正文流入区")
                )
            ],
            notes: ["图片承担主要解释功能，适合科普概念页或章节开篇页。"]
        )
    }

    private func balancedPlan(asset: Asset, target: LayoutTarget) -> LayoutPlan {
        LayoutPlan(
            target: target,
            strategy: .balanced,
            blocks: [
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
                    contentReference: .generated(asset.caption ?? "待补充图注")
                )
            ],
            notes: ["正文和图片权重均衡，适合解释密度较高的内页。"]
        )
    }

    private func textLedPlan(project: BookProject, target: LayoutTarget) -> LayoutPlan {
        LayoutPlan(
            target: target,
            strategy: .textLed,
            blocks: [
                LayoutPlanBlock(
                    kind: .text,
                    role: "body",
                    frame: Rect(x: 0.10, y: 0.10, width: 0.80, height: 0.72),
                    contentReference: .generated(project.metadata.title)
                ),
                LayoutPlanBlock(
                    kind: .component,
                    role: "knowledge-card",
                    frame: Rect(x: 0.10, y: 0.84, width: 0.80, height: 0.10),
                    contentReference: .generated("可转化为知识卡片的重点解释")
                )
            ],
            notes: ["正文阅读优先，适合叙述性强的页面。"]
        )
    }
}
