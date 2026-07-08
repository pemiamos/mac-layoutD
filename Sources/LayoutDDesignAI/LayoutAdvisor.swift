import Foundation
import LayoutDCore

public protocol LayoutAdvisor: Sendable {
    func proposePlans(for project: BookProject, target: LayoutTarget) -> [LayoutPlan]
}

public protocol LayoutPlanProvider: Sendable {
    func proposePlans(request: LayoutPlanRequest) throws -> [LayoutPlan]
}

public struct LayoutPlanRequest: Sendable {
    public var project: BookProject
    public var target: LayoutTarget
    public var context: LayoutPlanContext

    public init(project: BookProject, target: LayoutTarget, context: LayoutPlanContext? = nil) {
        self.project = project
        self.target = target
        self.context = context ?? LayoutPlanContext(project: project)
    }
}

public struct LayoutPlanContext: Codable, Equatable, Sendable {
    public var title: String
    public var subtitle: String?
    public var keywords: [String]
    public var sectionSummaries: [SectionSummary]
    public var assetSummaries: [AssetSummary]

    public init(project: BookProject) {
        title = project.metadata.title
        subtitle = project.metadata.subtitle
        keywords = project.metadata.keywords
        sectionSummaries = project.sections.map(SectionSummary.init(section:))
        assetSummaries = project.assets.map(AssetSummary.init(asset:))
    }
}

public struct SectionSummary: Codable, Equatable, Sendable {
    public var title: String
    public var storyTitles: [String]
    public var paragraphCount: Int
    public var figureCount: Int
    public var calloutCount: Int
    public var tableCount: Int

    public init(section: BookSection) {
        title = section.title
        storyTitles = section.stories.map(\.title)
        let paragraphs = section.stories.flatMap(\.paragraphs)
        paragraphCount = paragraphs.count
        figureCount = paragraphs.filter {
            if case .figure = $0.kind { return true }
            return false
        }.count
        calloutCount = paragraphs.filter { $0.kind == .callout }.count
        tableCount = paragraphs.filter { $0.kind == .table }.count
    }
}

public struct AssetSummary: Codable, Equatable, Sendable {
    public var fileName: String
    public var role: String
    public var usage: String
    public var caption: String?
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(asset: Asset) {
        fileName = asset.fileName
        role = asset.role.rawValue
        usage = asset.usage.rawValue
        caption = asset.caption
        pixelWidth = asset.pixelWidth
        pixelHeight = asset.pixelHeight
    }
}

public struct ProviderBackedLayoutAdvisor<Provider: LayoutPlanProvider>: LayoutAdvisor {
    public var provider: Provider
    public var fallback: RuleBasedLayoutAdvisor

    public init(provider: Provider, fallback: RuleBasedLayoutAdvisor = RuleBasedLayoutAdvisor()) {
        self.provider = provider
        self.fallback = fallback
    }

    public func proposePlans(for project: BookProject, target: LayoutTarget) -> [LayoutPlan] {
        let request = LayoutPlanRequest(project: project, target: target)
        guard let plans = try? provider.proposePlans(request: request), !plans.isEmpty else {
            return fallback.proposePlans(for: project, target: target)
        }
        return plans
    }
}

public struct RuleBasedLayoutAdvisor: LayoutAdvisor {
    public var catalog: PageLayoutTemplateCatalog

    public init(catalog: PageLayoutTemplateCatalog = PageLayoutTemplateCatalog(
        templates: [.imageLedPage, .balancedImageText, .textLedPage]
    )) {
        self.catalog = catalog
    }

    public func proposePlans(for project: BookProject, target: LayoutTarget) -> [LayoutPlan] {
        catalog.plans(for: project, target: target)
    }
}

/// Advisor that uses SpreadPlanner-generated plans when the project already has
/// `appliedLayoutPlans` (e.g. from the wizard), and falls back to the
/// `RuleBasedLayoutAdvisor` otherwise. This keeps the normal advisor pipeline
/// aware of spread-level decisions without requiring the wizard to have run.
public struct SpreadPlannerBackedAdvisor: LayoutAdvisor {
    public var fallback: RuleBasedLayoutAdvisor
    public var seed: UInt64

    public init(
        fallback: RuleBasedLayoutAdvisor = RuleBasedLayoutAdvisor(),
        seed: UInt64 = 42
    ) {
        self.fallback = fallback
        self.seed = seed
    }

    public func proposePlans(for project: BookProject, target: LayoutTarget) -> [LayoutPlan] {
        // If the project already has applied layout plans from the wizard,
        // return them directly for the requested page.
        if let applied = project.appliedLayoutPlans {
            switch target {
            case .page(let pageNum):
                if let plan = applied[pageNum] {
                    return [plan]
                }
            case .spread(let leftPage):
                var result: [LayoutPlan] = []
                if let left = applied[leftPage] { result.append(left) }
                if let right = applied[leftPage + 1] { result.append(right) }
                if !result.isEmpty { return result }
            case .section:
                // Section-level targeting not supported by SpreadPlanner;
                // fall through to on-the-fly planning or fallback.
                break
            }
        }

        // No wizard plans available — run an on-the-fly fingerprint + plan
        // for the target page and return the result.
        let fingerprint = SpreadPlanner.generateFingerprint(from: project)
        guard !fingerprint.spreadDemands.isEmpty else {
            return fallback.proposePlans(for: project, target: target)
        }

        let enabledIds = project.wizardState?.enabledArchetypeIds ?? SpreadArchetype.defaults.map(\.id)
        var archetypes = SpreadArchetype.defaults.filter { enabledIds.contains($0.id) }
        if archetypes.isEmpty { archetypes = SpreadArchetype.defaults }

        // Apply custom weights
        for i in 0..<archetypes.count {
            if let w = project.wizardState?.archetypeWeights?[archetypes[i].id] {
                archetypes[i].weight = w
            }
        }

        let selections = SpreadPlanner.planSpreads(
            fingerprint: fingerprint,
            archetypes: archetypes,
            seed: seed
        )

        let plans = SpreadPlanner.materialize(
            selections: selections,
            archetypes: SpreadArchetype.defaults,
            project: project
        )

        switch target {
        case .page(let pageNum):
            if let plan = plans[pageNum] { return [plan] }
        case .spread(let leftPage):
            var result: [LayoutPlan] = []
            if let left = plans[leftPage] { result.append(left) }
            if let right = plans[leftPage + 1] { result.append(right) }
            if !result.isEmpty { return result }
        case .section:
            break
        }

        return fallback.proposePlans(for: project, target: target)
    }
}
