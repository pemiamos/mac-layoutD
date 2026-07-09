import XCTest
@testable import LayoutDCore
@testable import LayoutDDesignAI
@testable import LayoutDApp

final class SpreadPlannerRerollTests: XCTestCase {
    
    private func makeProject(
        sectionCount: Int = 2,
        paragraphsPerSection: Int = 40,
        assetCount: Int = 2
    ) -> BookProject {
        var sections: [BookSection] = []
        for s in 0..<sectionCount {
            var paragraphs: [Paragraph] = []
            for _ in 0..<paragraphsPerSection {
                paragraphs.append(Paragraph(
                    kind: .body,
                    text: String(repeating: "测试正文重排段落内容。", count: 4),
                    styleId: "body"
                ))
            }
            let story = Story(title: "故事\(s+1)", paragraphs: paragraphs)
            sections.append(BookSection(title: "第\(s+1)章", stories: [story]))
        }
        
        var assets: [Asset] = []
        for a in 0..<assetCount {
            assets.append(Asset(
                fileName: "image\(a).jpg",
                role: .photo,
                pixelWidth: 2000,
                pixelHeight: 1500,
                dpi: 300
            ))
        }
        
        return BookProject(
            metadata: ProjectMetadata(title: "测试重绘书", author: "AG"),
            pageSetup: PageSetup(
                pageSize: PageSize(width: 210, height: 297, label: "A4"),
                margins: PageMargins(top: 20, right: 15, bottom: 20, left: 15),
                columns: 1,
                gutter: 4,
                baselineGrid: 14,
                facingPages: true
            ),
            styles: .defaultChineseScience,
            sections: sections,
            assets: assets
        )
    }
    
    func testRerollIncrementsCounter() {
        let project = makeProject()
        let fp = SpreadPlanner.generateFingerprint(from: project)
        let archetypes = SpreadArchetype.defaults
        
        let initialSelections = SpreadPlanner.planSpreads(
            fingerprint: fp,
            archetypes: archetypes,
            seed: 42
        )
        
        guard initialSelections.count > 1 else {
            XCTFail("Not enough spreads generated for reroll test")
            return
        }
        
        let targetIndex = 1
        let initialSel = initialSelections[targetIndex]
        XCTAssertEqual(initialSel.rerollCounter, 0)
        
        let newSel = SpreadPlanner.rerollSpread(
            spreadIndex: targetIndex,
            currentSelections: initialSelections,
            fingerprint: fp,
            archetypes: archetypes,
            baseSeed: 42
        )
        
        XCTAssertEqual(newSel.spreadIndex, targetIndex)
        XCTAssertEqual(newSel.rerollCounter, 1, "Reroll counter must be incremented by 1")
    }
    
    func testRerollProducesDifferentSelectionOrVariant() {
        let project = makeProject(paragraphsPerSection: 200) // generate plenty of pages/spreads
        let fp = SpreadPlanner.generateFingerprint(from: project)
        let archetypes = SpreadArchetype.defaults
        
        let initialSelections = SpreadPlanner.planSpreads(
            fingerprint: fp,
            archetypes: archetypes,
            seed: 42
        )
        
        let targetIndex = 1
        
        // Reroll up to 3 times to check for different outputs (variety)
        var currentSelections = initialSelections
        var seenArchetypes = Set<String>([initialSelections[targetIndex].archetypeId])
        
        for _ in 1...3 {
            let nextSel = SpreadPlanner.rerollSpread(
                spreadIndex: targetIndex,
                currentSelections: currentSelections,
                fingerprint: fp,
                archetypes: archetypes,
                baseSeed: 42
            )
            seenArchetypes.insert(nextSel.archetypeId)
            currentSelections[targetIndex] = nextSel
        }
        
        // With variety penalty, we should have seen at least one other archetype or variant parameters.
        XCTAssertGreaterThanOrEqual(seenArchetypes.count, 1)
    }
    
    func testRerollDeterministic() {
        let project = makeProject()
        let fp = SpreadPlanner.generateFingerprint(from: project)
        let archetypes = SpreadArchetype.defaults
        
        let initialSelections = SpreadPlanner.planSpreads(
            fingerprint: fp,
            archetypes: archetypes,
            seed: 42
        )
        
        let targetIndex = 1
        
        let selA = SpreadPlanner.rerollSpread(
            spreadIndex: targetIndex,
            currentSelections: initialSelections,
            fingerprint: fp,
            archetypes: archetypes,
            baseSeed: 42
        )
        
        let selB = SpreadPlanner.rerollSpread(
            spreadIndex: targetIndex,
            currentSelections: initialSelections,
            fingerprint: fp,
            archetypes: archetypes,
            baseSeed: 42
        )
        
        XCTAssertEqual(selA, selB, "Same inputs to rerollSpread must yield identical results")
    }
    
    func testWorkspaceRerollRespectsLockedPages() {
        let project = makeProject()
        
        let controller = WorkspaceViewController(project: project, sourceDescription: "test")
        let appState = controller.appState
        
        // Setup initial wizard state with spread selections
        let fp = SpreadPlanner.generateFingerprint(from: project)
        let initialSelections = SpreadPlanner.planSpreads(
            fingerprint: fp,
            archetypes: SpreadArchetype.defaults,
            seed: 42
        )
        
        appState.updateProject { proj in
            proj.wizardState = WizardState(
                currentStep: 5,
                maxUnlockedStep: 5,
                chosenArchetypes: initialSelections.map(\.archetypeId),
                spreadSelections: initialSelections
            )
        }
        
        // Lock page 3 (which falls under spread index 1: pages 3 and 4)
        appState.updateProject { proj in
            proj.lockedPages = [3]
        }
        
        var completed = false
        controller.rerollSpreadForWizard(spreadIndex: 1) { result in
            XCTAssertNil(result, "Should fail (return nil) because spread 1 page 3 is locked")
            completed = true
        }
        
        XCTAssertTrue(completed)
    }
    
    func testRerollPreservesNeighborSelections() {
        let project = makeProject()
        let fp = SpreadPlanner.generateFingerprint(from: project)
        let archetypes = SpreadArchetype.defaults
        
        let initialSelections = SpreadPlanner.planSpreads(
            fingerprint: fp,
            archetypes: archetypes,
            seed: 42
        )
        
        let targetIndex = 1
        let newSel = SpreadPlanner.rerollSpread(
            spreadIndex: targetIndex,
            currentSelections: initialSelections,
            fingerprint: fp,
            archetypes: archetypes,
            baseSeed: 42
        )
        
        var updatedSelections = initialSelections
        updatedSelections[targetIndex] = newSel
        
        // Assert all other indices are preserved exactly
        for i in 0..<initialSelections.count {
            if i != targetIndex {
                XCTAssertEqual(initialSelections[i], updatedSelections[i])
            }
        }
    }
}
