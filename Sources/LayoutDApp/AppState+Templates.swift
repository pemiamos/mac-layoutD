import Foundation
import SwiftUI
import LayoutDCore
import LayoutDEngine
import LayoutDDesignAI

extension AppState {
    func saveCurrentPageLayoutAsTemplate(name: String) {
        commitState()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let templateName = trimmedName.isEmpty ? "第 \(currentPageNumber) 页版式" : trimmedName
        let plan = freezePageToPlan(pageNum: currentPageNumber)

        var currentProject = project
        var templates = currentProject.safeSavedLayoutTemplates
        templates.append(SavedLayoutTemplate(name: templateName, plan: plan))
        currentProject.safeSavedLayoutTemplates = templates
        self.project = currentProject
    }

    func applySavedLayoutTemplate(id: UUID, toPage pageNum: Int) {
        guard let template = project.safeSavedLayoutTemplates.first(where: { $0.id == id }) else { return }
        applyLayoutPlan(template.makePlan(target: .page(pageNum)))
    }

    func applyPageLayoutTemplate(_ template: PageLayoutTemplate, toPage pageNum: Int) {
        let primaryAsset = project.assets.first { $0.role != .decorative }
        guard let plan = template.makePlan(
            target: .page(pageNum),
            projectTitle: project.metadata.title,
            primaryAsset: primaryAsset
        ) else { return }
        applyLayoutPlan(plan)
    }

    func renameSavedLayoutTemplate(id: UUID, name: String) {
        commitState()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        var currentProject = project
        var templates = currentProject.safeSavedLayoutTemplates
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }

        templates[index].name = trimmedName
        templates[index].modifiedAt = Date()
        currentProject.safeSavedLayoutTemplates = templates
        self.project = currentProject
    }

    func deleteSavedLayoutTemplate(id: UUID) {
        commitState()
        var currentProject = project
        var templates = currentProject.safeSavedLayoutTemplates
        templates.removeAll { $0.id == id }
        currentProject.safeSavedLayoutTemplates = templates
        self.project = currentProject
    }

    func updateSavedLayoutTemplateParameters(
        id: UUID,
        marginOverride: PageMargins?,
        columnsOverride: Int?,
        showHeadersFooters: Bool?
    ) {
        commitState()
        var currentProject = project
        var templates = currentProject.safeSavedLayoutTemplates
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }

        templates[index].plan.marginOverride = marginOverride
        templates[index].plan.columnsOverride = columnsOverride
        templates[index].plan.showHeadersFooters = showHeadersFooters
        templates[index].modifiedAt = Date()
        currentProject.safeSavedLayoutTemplates = templates
        self.project = currentProject
    }

    func applyChapterLayoutTemplate(_ template: ChapterLayoutTemplate, sectionIndex: Int, startPage: Int) -> Int {
        var currentProject = project
        let appliedCount = currentProject.applyChapterLayoutTemplate(
            template,
            sectionIndex: sectionIndex,
            startPage: startPage
        )
        guard appliedCount > 0 else {
            return 0
        }
        self.project = currentProject
        return appliedCount
    }
}
