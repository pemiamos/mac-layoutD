import XCTest
@testable import LayoutDCore
@testable import LayoutDDesignAI
@testable import LayoutDApp

final class SpreadPlannerAssignTests: XCTestCase {

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
                    text: String(repeating: "测试拖拽指定骨架段落内容。", count: 4),
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
            metadata: ProjectMetadata(title: "测试拖拽书", author: "Claude"),
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

    func testAssignHonorsExplicitArchetype() {
        let project = makeProject()
        let fp = SpreadPlanner.generateFingerprint(from: project)
        let archetypes = SpreadArchetype.defaults

        let selections = SpreadPlanner.planSpreads(fingerprint: fp, archetypes: archetypes, seed: 42)
        guard selections.count > 1 else {
            XCTFail("Not enough spreads generated")
            return
        }

        // Pick an archetype different from the planner's choice for spread 1
        let targetIndex = 1
        let currentId = selections[targetIndex].archetypeId
        guard let otherId = archetypes.first(where: { $0.id != currentId })?.id else {
            XCTFail("Need at least two archetypes")
            return
        }

        let assigned = SpreadPlanner.assignArchetype(
            spreadIndex: targetIndex,
            archetypeId: otherId,
            currentSelections: selections,
            fingerprint: fp,
            archetypes: archetypes
        )

        XCTAssertNotNil(assigned)
        XCTAssertEqual(assigned?.spreadIndex, targetIndex)
        XCTAssertEqual(assigned?.archetypeId, otherId, "Explicit assignment must win over planner scoring")
    }

    func testAssignUnknownArchetypeReturnsNil() {
        let project = makeProject()
        let fp = SpreadPlanner.generateFingerprint(from: project)

        let assigned = SpreadPlanner.assignArchetype(
            spreadIndex: 0,
            archetypeId: "no-such-archetype",
            currentSelections: [],
            fingerprint: fp,
            archetypes: SpreadArchetype.defaults
        )
        XCTAssertNil(assigned)
    }

    func testAssignPreservesRerollCounter() {
        let project = makeProject()
        let fp = SpreadPlanner.generateFingerprint(from: project)
        let archetypes = SpreadArchetype.defaults

        var selections = SpreadPlanner.planSpreads(fingerprint: fp, archetypes: archetypes, seed: 42)
        guard selections.count > 1 else {
            XCTFail("Not enough spreads generated")
            return
        }
        let targetIndex = 1
        selections[targetIndex] = SpreadPlanner.rerollSpread(
            spreadIndex: targetIndex,
            currentSelections: selections,
            fingerprint: fp,
            archetypes: archetypes,
            baseSeed: 42
        )
        let counterBefore = selections[targetIndex].rerollCounter

        let assigned = SpreadPlanner.assignArchetype(
            spreadIndex: targetIndex,
            archetypeId: archetypes[0].id,
            currentSelections: selections,
            fingerprint: fp,
            archetypes: archetypes
        )
        XCTAssertEqual(assigned?.rerollCounter, counterBefore,
                       "Assignment is not a reroll; the counter must carry over unchanged")
    }

    func testAssignPicksImageTierFromDemand() {
        let project = makeProject()
        let fp = SpreadPlanner.generateFingerprint(from: project)
        let archetypes = SpreadArchetype.defaults

        guard let tieredArchetype = archetypes.first(where: { !$0.imageTiers.isEmpty }) else {
            XCTFail("Need an archetype with image tiers")
            return
        }

        // A spread with images should get a concrete tier; one without gets "none".
        for demand in fp.spreadDemands {
            let assigned = SpreadPlanner.assignArchetype(
                spreadIndex: demand.spreadIndex,
                archetypeId: tieredArchetype.id,
                currentSelections: [],
                fingerprint: fp,
                archetypes: archetypes
            )
            if demand.imageCount == 0 {
                XCTAssertEqual(assigned?.imageTier, "none")
            } else {
                XCTAssertNotEqual(assigned?.imageTier, nil)
            }
        }
    }

    func testAssignedSelectionMaterializes() {
        let project = makeProject()
        let fp = SpreadPlanner.generateFingerprint(from: project)
        let archetypes = SpreadArchetype.defaults

        var selections = SpreadPlanner.planSpreads(fingerprint: fp, archetypes: archetypes, seed: 42)
        guard !selections.isEmpty else {
            XCTFail("Not enough spreads generated")
            return
        }
        let targetIndex = 0
        guard let assigned = SpreadPlanner.assignArchetype(
            spreadIndex: targetIndex,
            archetypeId: archetypes.last!.id,
            currentSelections: selections,
            fingerprint: fp,
            archetypes: archetypes
        ) else {
            XCTFail("Assignment failed")
            return
        }
        if let idx = selections.firstIndex(where: { $0.spreadIndex == targetIndex }) {
            selections[idx] = assigned
        } else {
            selections.append(assigned)
        }

        let plans = SpreadPlanner.materialize(selections: selections, archetypes: archetypes, project: project)
        let leftPage = targetIndex * 2 + 1
        XCTAssertNotNil(plans[leftPage], "Assigned spread must materialize a plan for its left page")
        XCTAssertEqual(plans[leftPage]?.strategy, archetypes.last!.family)
    }
}
