import XCTest
@testable import LayoutDCore
@testable import LayoutDApp

final class SpreadArchetypeTests: XCTestCase {
    func testSpreadArchetypeDefaults() {
        let defaults = SpreadArchetype.defaults
        XCTAssertEqual(defaults.count, 10)
        
        // Opener archetype check
        let opener = defaults.first(where: { $0.id == "chapter-opener" })
        XCTAssertNotNil(opener)
        XCTAssertEqual(opener?.family, .opener)
        XCTAssertEqual(opener?.role, .opener)
        XCTAssertFalse(opener?.mirror ?? true)
        
        // Workhorse archetype check
        let workhorse = defaults.first(where: { $0.id == "running-text" })
        XCTAssertNotNil(workhorse)
        XCTAssertEqual(workhorse?.family, .textLed)
        XCTAssertEqual(workhorse?.role, .workhorse)
    }
    
    func testWireframeRenderer() {
        let size = CGSize(width: 240, height: 150)
        for archetype in SpreadArchetype.defaults {
            let image = WireframeRenderer.renderSpread(archetype: archetype, size: size)
            XCTAssertEqual(image.size.width, size.width)
            XCTAssertEqual(image.size.height, size.height)
        }
    }
    
    func testSpreadArchetypeSerialization() throws {
        let defaults = SpreadArchetype.defaults
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(defaults)
        let decoded = try decoder.decode([SpreadArchetype].self, from: data)
        
        XCTAssertEqual(decoded.count, defaults.count)
        XCTAssertEqual(decoded[0].id, defaults[0].id)
        XCTAssertEqual(decoded[0].displayName, defaults[0].displayName)
        XCTAssertEqual(decoded[0].family, defaults[0].family)
    }
}
