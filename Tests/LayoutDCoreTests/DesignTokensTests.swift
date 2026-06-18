import XCTest
@testable import LayoutDCore

final class DesignTokensTests: XCTestCase {

    func testColorResolutionWithModes() {
        let tokens = DesignTokens(
            colorModes: ["green", "blue"],
            defaultMode: "green",
            colors: [
                ColorTokenSet(id: "accent", valuesByMode: ["green": "#2D7A78", "blue": "#1F5F9F"]),
                ColorTokenSet(id: "ink", hex: "#17202A")
            ]
        )

        XCTAssertEqual(tokens.colorHex("accent"), "#2D7A78", "default mode is green")
        XCTAssertEqual(tokens.colorHex("accent", mode: "blue"), "#1F5F9F")
        // ink only defined in base mode -> falls back regardless of requested mode
        XCTAssertEqual(tokens.colorHex("ink", mode: "blue"), "#17202A")
        XCTAssertNil(tokens.colorHex("missing"))
    }

    func testDefaultModeNormalizedToAvailableMode() {
        // defaultMode not in the list -> normalized to first mode
        let tokens = DesignTokens(colorModes: ["a", "b"], defaultMode: "zzz")
        XCTAssertEqual(tokens.defaultMode, "a")
        // empty modes -> baseMode
        let empty = DesignTokens(colorModes: [])
        XCTAssertEqual(empty.colorModes, [DesignTokens.baseMode])
    }

    func testScalarResolution() {
        let tokens = DesignTokens(scalars: [
            ScalarToken(id: "gutter", value: 7, kind: .spacing),
            ScalarToken(id: "body", value: 10.5, kind: .fontSize)
        ])
        XCTAssertEqual(tokens.scalar("gutter"), 7)
        XCTAssertEqual(tokens.scalar("body"), 10.5)
        XCTAssertNil(tokens.scalar("nope"))
    }

    func testRoundTripCodable() throws {
        let tokens = DesignTokens(
            colorModes: ["green", "blue"],
            defaultMode: "blue",
            colors: [ColorTokenSet(id: "accent", valuesByMode: ["green": "#2D7A78", "blue": "#1F5FF0"])],
            scalars: [ScalarToken(id: "gutter", value: 7, kind: .spacing)]
        )
        let data = try JSONEncoder().encode(tokens)
        let decoded = try JSONDecoder().decode(DesignTokens.self, from: data)
        XCTAssertEqual(decoded, tokens)
    }

    func testDTCGExportShape() throws {
        let tokens = DesignTokens(
            colorModes: ["green", "blue"],
            defaultMode: "green",
            colors: [ColorTokenSet(id: "accent", valuesByMode: ["green": "#2D7A78", "blue": "#1F5FF0"])],
            scalars: [ScalarToken(id: "gutter", value: 7, kind: .spacing)]
        )
        let export = tokens.dtcgExport()
        XCTAssertEqual(export["color/accent"], DTCGToken(type: "color", value: "#2D7A78"))
        XCTAssertEqual(export["color/accent/blue"], DTCGToken(type: "color", value: "#1F5FF0"))
        XCTAssertEqual(export["spacing/gutter"]?.type, "dimension")

        // DTCG leaf encodes with $type / $value keys
        let leaf = try JSONEncoder().encode(DTCGToken(type: "color", value: "#000"))
        let json = String(data: leaf, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("$type"))
        XCTAssertTrue(json.contains("$value"))
    }

    func testStyleLibraryPrefersTokensThenFallsBackToLegacyColors() {
        // No tokens: resolves via legacy colors
        let legacy = StyleLibrary.defaultChineseScience
        XCTAssertEqual(legacy.colorHex("accent"), "#2D7A78")
        XCTAssertNil(legacy.tokens)

        // With tokens: token value wins over legacy colors of the same id
        var withTokens = legacy
        withTokens.tokens = DesignTokens(colors: [ColorTokenSet(id: "accent", hex: "#000000")])
        XCTAssertEqual(withTokens.colorHex("accent"), "#000000")
        // id only in legacy colors still resolves via fallback
        XCTAssertEqual(withTokens.colorHex("warning"), "#B3541E")
    }

    func testEffectiveTokensSynthesizedFromLegacyColors() {
        let lib = StyleLibrary.defaultChineseScience
        let eff = lib.effectiveTokens
        XCTAssertEqual(eff.colorHex("paper"), "#F7F4EE")
    }

    func testProjectColorModeDrivesResolution() {
        var styles = StyleLibrary.defaultChineseScience
        styles.tokens = DesignTokens(
            colorModes: ["green", "blue"],
            defaultMode: "green",
            colors: [ColorTokenSet(id: "accent", valuesByMode: ["green": "#2D7A78", "blue": "#1F5F9F"])]
        )
        var project = BookProject(metadata: ProjectMetadata(title: "模式测试", author: "x"), styles: styles)

        // nil mode -> token set default (green)
        XCTAssertEqual(project.resolvedColorHex("accent"), "#2D7A78")
        // switching project mode flips the resolved color across the whole book
        project.colorMode = "blue"
        XCTAssertEqual(project.resolvedColorHex("accent"), "#1F5F9F")
    }

    func testProjectColorModeBackwardCompatibleDecode() throws {
        // A minimal project JSON without colorMode decodes with nil.
        let project = BookProject(metadata: ProjectMetadata(title: "t", author: "a"))
        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(BookProject.self, from: data)
        XCTAssertNil(decoded.colorMode)
    }

    func testLegacyStyleLibraryJSONWithoutTokensDecodes() throws {
        // Simulates an old .layoutd: StyleLibrary JSON with no "tokens" key.
        let json = """
        {
          "paragraphStyles": [],
          "colors": [{"id": "ink", "hex": "#111111"}]
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(StyleLibrary.self, from: json)
        XCTAssertNil(decoded.tokens)
        XCTAssertEqual(decoded.colorHex("ink"), "#111111")
    }
}
