import XCTest
@testable import LayoutDCore
@testable import LayoutDDesignAI
@testable import LayoutDApp

/// appliedLayoutPlans 同时承载规划器产物与手动编辑（插入空白页/手动冻结版式/锁页）。
/// 规划器写回必须合并而非整本替换，否则手动痕迹会被连带清掉（实机踩过的坑：
/// 手动加的 3 页在拖拽赋骨架后消失）。
final class WizardPlanMergeTests: XCTestCase {

    private func plannerPlan(page: Int) -> LayoutPlan {
        LayoutPlan(target: .page(page), strategy: .balanced, blocks: [])
    }

    private func manualBlankPagePlan(page: Int) -> LayoutPlan {
        LayoutPlan(target: .page(page), strategy: .balanced, blocks: [], notes: ["手动插入空白页"])
    }

    private func manualFrozenPlan(page: Int) -> LayoutPlan {
        LayoutPlan(target: .page(page), strategy: .balanced, blocks: [], notes: ["手动自定义版式页"])
    }

    func testMergeKeepsManualPlansAndReplacesPlannerPlans() {
        let existing: [Int: LayoutPlan] = [
            1: plannerPlan(page: 1),          // old planner output → replaced
            2: plannerPlan(page: 2),          // old planner output, not in new set → dropped
            3: manualBlankPagePlan(page: 3),  // hand-inserted page → must survive
            4: manualFrozenPlan(page: 4),     // hand-frozen layout → must survive
        ]
        let materialized: [Int: LayoutPlan] = [
            1: plannerPlan(page: 1),
            3: plannerPlan(page: 3),          // planner tries to write onto the manual page
        ]

        let merged = WorkspaceViewController.mergePlannerPlans(materialized, into: existing, locked: [])

        XCTAssertEqual(merged[1]?.isManualEdit, false)
        XCTAssertNil(merged[2], "Stale planner output must be cleared on re-plan")
        XCTAssertEqual(merged[3]?.isManualEdit, true, "Manual inserted page must win over planner output")
        XCTAssertEqual(merged[4]?.isManualEdit, true, "Hand-frozen page must survive re-plan")
    }

    func testMergeSkipsLockedPages() {
        let lockedPlan = plannerPlan(page: 5)
        let existing: [Int: LayoutPlan] = [5: lockedPlan]
        let materialized: [Int: LayoutPlan] = [5: plannerPlan(page: 5), 6: plannerPlan(page: 6)]

        let merged = WorkspaceViewController.mergePlannerPlans(materialized, into: existing, locked: [5])

        XCTAssertEqual(merged[5]?.id, lockedPlan.id, "Locked page keeps its existing plan verbatim")
        XCTAssertNotNil(merged[6])
    }

    func testAssignArchetypePreservesOtherPages() {
        // Real controller path: drop an archetype on spread 0; a manual blank page
        // and another spread's plan elsewhere must be untouched.
        var sections: [BookSection] = []
        for s in 0..<2 {
            let paragraphs = (0..<40).map { _ in
                Paragraph(kind: .body, text: String(repeating: "合并语义测试段落。", count: 4), styleId: "body")
            }
            sections.append(BookSection(title: "第\(s+1)章", stories: [Story(title: "故事", paragraphs: paragraphs)]))
        }
        let project = BookProject(
            metadata: ProjectMetadata(title: "测试合并书", author: "Claude"),
            pageSetup: PageSetup(
                pageSize: PageSize(width: 210, height: 297, label: "A4"),
                margins: PageMargins(top: 20, right: 15, bottom: 20, left: 15),
                columns: 1,
                gutter: 4,
                baselineGrid: 14,
                facingPages: true
            ),
            styles: .defaultChineseScience,
            sections: sections
        )

        let controller = WorkspaceViewController(project: project, sourceDescription: "test")
        let appState = controller.appState

        let manualPage = 9
        let otherPlannerPage = 3
        appState.updateProject { proj in
            var plans = proj.safeAppliedLayoutPlans
            plans[manualPage] = self.manualBlankPagePlan(page: manualPage)
            plans[otherPlannerPage] = self.plannerPlan(page: otherPlannerPage)
            proj.safeAppliedLayoutPlans = plans
        }
        let otherPlanId = appState.project.appliedLayoutPlans?[otherPlannerPage]?.id

        let archetypeId = SpreadArchetype.defaults[0].id
        controller.assignArchetypeForWizard(spreadIndex: 0, archetypeId: archetypeId)

        let plans = appState.project.appliedLayoutPlans ?? [:]
        XCTAssertEqual(plans[manualPage]?.isManualEdit, true, "Manual blank page must survive an archetype drop")
        XCTAssertEqual(plans[otherPlannerPage]?.id, otherPlanId, "Untargeted spread's plan must be untouched")
        XCTAssertNotNil(plans[1], "Dropped spread's left page gets the archetype plan")
        XCTAssertNotNil(plans[2], "Dropped spread's right page gets the archetype plan")
        XCTAssertEqual(appState.project.wizardState?.spreadSelections?.first?.archetypeId, archetypeId)
    }
}
