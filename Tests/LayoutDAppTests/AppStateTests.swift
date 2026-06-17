import XCTest
import LayoutDCore
import LayoutDDesignAI
@testable import LayoutDApp

final class AppStateTests: XCTestCase {
    func testApplyPageLayoutTemplate() {
        let project = BookProject.sample
        let state = AppState(project: project)
        
        // Assert clean starting state
        XCTAssertNil(state.project.safeAppliedLayoutPlans[2])
        
        // Apply a template (e.g. .textLedPage) to page 2
        state.applyPageLayoutTemplate(.textLedPage, toPage: 2)
        
        // Verify the layout plan was applied to page 2
        let plan = state.project.safeAppliedLayoutPlans[2]
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.strategy, .textLed)
        XCTAssertEqual(plan?.blocks.count, 2)
    }
}
