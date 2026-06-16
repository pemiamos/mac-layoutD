import Foundation
import LayoutDCore

public enum ChapterLayoutTemplate: String, Codable, CaseIterable, Sendable {
    case scienceChapter
    case imageRichChapter
    case studyGuideChapter

    public var displayName: String {
        switch self {
        case .scienceChapter:
            return "科普章节"
        case .imageRichChapter:
            return "图像密集章节"
        case .studyGuideChapter:
            return "学习手册章节"
        }
    }

    public var pageTemplates: [PageLayoutTemplate] {
        switch self {
        case .scienceChapter:
            return [.textLedPage, .balancedImageText, .knowledgeCardPage]
        case .imageRichChapter:
            return [.imageLedPage, .balancedImageText, .textLedPage]
        case .studyGuideChapter:
            return [.textLedPage, .knowledgeCardPage]
        }
    }

    public func makePlanSet(
        for section: BookSection,
        in project: BookProject,
        startPage: Int
    ) -> ChapterLayoutPlanSet {
        let asset = primaryAsset(for: section, in: project)
        var plansByPage: [Int: LayoutPlan] = [:]

        for (offset, pageTemplate) in pageTemplates.enumerated() {
            let page = startPage + offset
            if let plan = pageTemplate.makePlan(
                target: .page(page),
                projectTitle: section.title,
                primaryAsset: asset
            ) {
                plansByPage[page] = plan
            }
        }

        return ChapterLayoutPlanSet(
            template: self,
            sectionId: section.id,
            startPage: startPage,
            plansByPage: plansByPage
        )
    }

    private func primaryAsset(for section: BookSection, in project: BookProject) -> Asset? {
        let anchoredAssetIds = section.stories
            .flatMap(\.paragraphs)
            .flatMap(\.anchoredAssetIds)

        for assetId in anchoredAssetIds {
            if let asset = project.assets.first(where: { $0.id == assetId && $0.role != .decorative }) {
                return asset
            }
        }

        return project.assets.first { $0.role != .decorative }
    }
}

public struct ChapterLayoutPlanSet: Codable, Equatable, Sendable {
    public var template: ChapterLayoutTemplate
    public var sectionId: UUID
    public var startPage: Int
    public var plansByPage: [Int: LayoutPlan]

    public init(
        template: ChapterLayoutTemplate,
        sectionId: UUID,
        startPage: Int,
        plansByPage: [Int: LayoutPlan]
    ) {
        self.template = template
        self.sectionId = sectionId
        self.startPage = startPage
        self.plansByPage = plansByPage
    }
}

public struct ChapterLayoutTemplateCatalog: Sendable {
    public var templates: [ChapterLayoutTemplate]

    public init(templates: [ChapterLayoutTemplate] = ChapterLayoutTemplate.allCases) {
        self.templates = templates
    }

    public func planSets(
        for project: BookProject,
        section: BookSection,
        startPage: Int
    ) -> [ChapterLayoutPlanSet] {
        templates.map {
            $0.makePlanSet(for: section, in: project, startPage: startPage)
        }
    }
}

public extension BookProject {
    mutating func applyChapterLayoutTemplate(
        _ template: ChapterLayoutTemplate,
        sectionIndex: Int = 0,
        startPage: Int = 3
    ) -> Int {
        guard sections.indices.contains(sectionIndex) else {
            return 0
        }

        let planSet = template.makePlanSet(
            for: sections[sectionIndex],
            in: self,
            startPage: startPage
        )
        guard !planSet.plansByPage.isEmpty else {
            return 0
        }

        var plans = safeAppliedLayoutPlans
        for (page, plan) in planSet.plansByPage {
            plans[page] = plan
        }
        safeAppliedLayoutPlans = plans
        return planSet.plansByPage.count
    }

    func applyingChapterLayoutTemplate(
        _ template: ChapterLayoutTemplate,
        sectionIndex: Int = 0,
        startPage: Int = 3
    ) -> BookProject {
        var copy = self
        _ = copy.applyChapterLayoutTemplate(
            template,
            sectionIndex: sectionIndex,
            startPage: startPage
        )
        return copy
    }
}
