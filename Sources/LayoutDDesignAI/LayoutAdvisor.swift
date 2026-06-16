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
