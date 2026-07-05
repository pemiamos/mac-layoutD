import XCTest
@testable import LayoutDCore

final class PrintColorTests: XCTestCase {
    // MARK: - Parsing

    func testParsesHexForms() {
        XCTAssertEqual(PrintColor(string: "#17202A"), .rgb(r: 23, g: 32, b: 42))
        XCTAssertEqual(PrintColor(string: "17202a"), .rgb(r: 23, g: 32, b: 42))
        XCTAssertEqual(PrintColor(string: "#0f0"), .rgb(r: 0, g: 255, b: 0))
    }

    func testParsesCMYKForms() {
        XCTAssertEqual(PrintColor(string: "cmyk(0,0,0,100)"), .cmyk(c: 0, m: 0, y: 0, k: 100))
        XCTAssertEqual(PrintColor(string: "cmyk:20,0,80,0"), .cmyk(c: 20, m: 0, y: 80, k: 0))
        XCTAssertEqual(PrintColor(string: "CMYK( 12.5 , 0 , 0 , 5 )"), .cmyk(c: 12.5, m: 0, y: 0, k: 5))
    }

    func testCMYKClampsOutOfRange() {
        XCTAssertEqual(PrintColor(string: "cmyk(-5,120,0,0)"), .cmyk(c: 0, m: 100, y: 0, k: 0))
    }

    func testRejectsGarbage() {
        XCTAssertNil(PrintColor(string: ""))
        XCTAssertNil(PrintColor(string: "#12"))
        XCTAssertNil(PrintColor(string: "wxyz12"))
        XCTAssertNil(PrintColor(string: "cmyk(1,2,3)"))
    }

    // MARK: - Canonical string round-trips

    func testCanonicalRGBMatchesLegacyNormalization() {
        // Must equal the exporter's historical 6-upper-hex key so existing RGB
        // swatches never shift.
        XCTAssertEqual(PrintColor(string: "#17202a")?.canonicalString, "17202A")
        XCTAssertEqual(PrintColor(string: "#0f0")?.canonicalString, "00FF00")
    }

    func testCanonicalCMYKRoundTrips() {
        let c = PrintColor(string: "cmyk(20,0,80,0)")!
        XCTAssertEqual(c.canonicalString, "cmyk(20,0,80,0)")
        XCTAssertEqual(PrintColor(string: c.canonicalString), c)
    }

    // MARK: - IDML mapping

    func testIDMLSpaceValueRGB() {
        let (space, value) = PrintColor(string: "#17202A")!.idmlSpaceValue
        XCTAssertEqual(space, "RGB")
        XCTAssertEqual(value, "23 32 42")
    }

    func testIDMLSpaceValueCMYK() {
        let (space, value) = PrintColor(string: "cmyk(20,0,80,0)")!.idmlSpaceValue
        XCTAssertEqual(space, "CMYK")
        XCTAssertEqual(value, "20 0 80 0")
    }

    func testSwatchSelfNames() {
        XCTAssertEqual(PrintColor(string: "#17202A")!.idmlSwatchSelf, "Color/C17202A")
        XCTAssertEqual(PrintColor(string: "cmyk(20,0,80,0)")!.idmlSwatchSelf, "Color/CMYK_20_0_80_0")
    }

    func testBuiltinBlackCollapses() {
        XCTAssertTrue(PrintColor(string: "#000000")!.isBuiltinBlack)
        XCTAssertTrue(PrintColor(string: "cmyk(0,0,0,100)")!.isBuiltinBlack)
        XCTAssertEqual(PrintColor(string: "#000000")!.idmlSwatchSelf, "Color/Black")
        XCTAssertEqual(PrintColor(string: "cmyk(0,0,0,100)")!.idmlSwatchSelf, "Color/Black")
        XCTAssertFalse(PrintColor(string: "cmyk(0,0,0,90)")!.isBuiltinBlack)
    }

    // MARK: - Display conversion

    func testDisplayRGBForPureCMYKBlackIsBlack() {
        let (r, g, b) = PrintColor(string: "cmyk(0,0,0,100)")!.displayRGB
        XCTAssertEqual(r, 0, accuracy: 0.001)
        XCTAssertEqual(g, 0, accuracy: 0.001)
        XCTAssertEqual(b, 0, accuracy: 0.001)
    }
}
