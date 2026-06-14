import LayoutDCore
import LayoutDDesignAI
import LayoutDEngine
import XCTest

final class LayoutDCoreTests: XCTestCase {
    func testSampleProjectEncodesAndDecodes() throws {
        let project = BookProject.sample
        let data = try ProjectFile.encode(project)
        let decoded = try ProjectFile.decode(data)
        XCTAssertEqual(decoded.metadata.title, project.metadata.title)
        XCTAssertEqual(decoded.sections.count, 1)
        XCTAssertEqual(decoded.assets.count, 1)
    }

    func testLayoutEngineCreatesPagesAndFrames() {
        let document = LayoutEngine().layout(project: .sample)
        XCTAssertFalse(document.pages.isEmpty)
        XCTAssertFalse(document.pages[0].frames.isEmpty)
    }

    func testAdvisorReturnsStructuredLayoutPlans() {
        let plans = RuleBasedLayoutAdvisor().proposePlans(for: .sample, target: .page(1))
        XCTAssertEqual(plans.count, 3)
        XCTAssertTrue(plans.allSatisfy { !$0.blocks.isEmpty })
    }
}
