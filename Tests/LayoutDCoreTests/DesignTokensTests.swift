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
        var legacy = StyleLibrary.defaultChineseScience
        legacy.tokens = nil
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
        var lib = StyleLibrary.defaultChineseScience
        lib.tokens = nil
        let eff = lib.effectiveTokens
        XCTAssertEqual(eff.colorHex("paper"), "#F7F4EE")
    }

    func testParagraphStyleScalarTokensDriveResolvedMetrics() {
        var styles = StyleLibrary.defaultChineseScience
        var tokens = try! XCTUnwrap(styles.tokens)
        let scalars = tokens.scalars.map { token in
            guard token.id == "paragraph.body.fontSize" else { return token }
            return ScalarToken(id: token.id, value: 12.25, kind: token.kind)
        }
        tokens.scalars = scalars
        styles.tokens = tokens

        let body = styles.paragraphStyle(id: StyleID.body.rawValue)
        XCTAssertEqual(body.fontSize, 12.25)
        XCTAssertEqual(body.fontSizeToken, "paragraph.body.fontSize")
    }

    func testParagraphStyleFallsBackWhenScalarTokenIsMissing() {
        var styles = StyleLibrary.defaultChineseScience
        styles.tokens?.scalars.removeAll { $0.id == "paragraph.body.lineHeight" }

        let body = styles.paragraphStyle(id: StyleID.body.rawValue)
        XCTAssertEqual(body.lineHeight, ParagraphStyle.body.lineHeight)
    }

    func testPageSetupScalarTokensDriveResolvedMetrics() {
        var styles = StyleLibrary.defaultChineseScience
        var tokens = try! XCTUnwrap(styles.tokens)
        tokens.scalars = tokens.scalars.map { token in
            switch token.id {
            case "page.margin.left":
                return ScalarToken(id: token.id, value: 72, kind: token.kind)
            case "page.columns":
                return ScalarToken(id: token.id, value: 3, kind: token.kind)
            case "page.gutter":
                return ScalarToken(id: token.id, value: 24, kind: token.kind)
            case "page.baselineGrid":
                return ScalarToken(id: token.id, value: 16, kind: token.kind)
            default:
                return token
            }
        }
        styles.tokens = tokens

        let project = BookProject(metadata: ProjectMetadata(title: "页面 token", author: "a"), styles: styles)

        XCTAssertEqual(project.resolvedMargins(for: 3).left, 72)
        XCTAssertEqual(project.resolvedColumns(for: 3), 3)
        XCTAssertEqual(project.resolvedGutter(for: 3), 24)
        XCTAssertEqual(project.resolvedBaselineGrid, 16)
    }

    func testManualPageSetupEditClearsScalarTokenBinding() {
        var setup = PageSetup.scienceBookDefault
        XCTAssertEqual(setup.marginTopToken, "page.margin.top")
        XCTAssertEqual(setup.columnsToken, "page.columns")
        XCTAssertEqual(setup.gutterToken, "page.gutter")
        XCTAssertEqual(setup.baselineGridToken, "page.baselineGrid")

        setup.margins.top = 70
        setup.columns = 1
        setup.gutter = 12
        setup.baselineGrid = 11

        XCTAssertNil(setup.marginTopToken)
        XCTAssertNil(setup.marginRightToken)
        XCTAssertNil(setup.marginBottomToken)
        XCTAssertNil(setup.marginLeftToken)
        XCTAssertNil(setup.columnsToken)
        XCTAssertNil(setup.gutterToken)
        XCTAssertNil(setup.baselineGridToken)
    }

    func testDefaultComponentStylesResolveThroughTokens() {
        var styles = StyleLibrary.defaultChineseScience
        var tokens = try! XCTUnwrap(styles.tokens)
        tokens.colors = tokens.colors.map { token in
            guard token.id == "component.callout.background" else { return token }
            return ColorTokenSet(id: token.id, hex: "#DCEBFF")
        }
        styles.tokens = tokens
        let project = BookProject(metadata: ProjectMetadata(title: "组件 token", author: "a"), styles: styles)

        let callout = try! XCTUnwrap(project.styles.componentStyle(for: .callout))
        XCTAssertEqual(callout.resolvedFillColorHex(project: project), "#DCEBFF")
        XCTAssertEqual(callout.resolvedStrokeColorHex(project: project), "#2D7A78")
        XCTAssertEqual(callout.textInsetX, 8)
        XCTAssertEqual(callout.accentWidth, 4)
    }

    func testComponentStylesFallbackWhenLegacyJSONOmitsField() throws {
        let json = """
        {
          "paragraphStyles": [],
          "colors": [{"id": "ink", "hex": "#111111"}]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(StyleLibrary.self, from: json)
        XCTAssertNil(decoded.componentStyles)
        XCTAssertEqual(decoded.safeComponentStyles.count, ComponentStyle.defaultChineseScience.count)
        XCTAssertEqual(decoded.componentStyle(for: .callout)?.fillColorHex, "#E0F5ED")
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

    func testProjectSchemaVersionEncodesAndLegacyDecodeDefaults() throws {
        let project = BookProject(metadata: ProjectMetadata(title: "t", author: "a"))
        let data = try ProjectFile.encode(project)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"schemaVersion\""))

        let legacyJSON = """
        {
          "metadata": {"title": "旧项目", "author": "a"},
          "pageSetup": {
            "pageSize": {"width": 524.41, "height": 737.01, "label": "185mm x 260mm"},
            "margins": {"top": 56, "right": 48, "bottom": 62, "left": 54},
            "columns": 2,
            "gutter": 18,
            "baselineGrid": 14,
            "facingPages": true
          },
          "styles": {
            "paragraphStyles": [],
            "colors": [{"id": "ink", "hex": "#111111"}]
          },
          "sections": [],
          "assets": []
        }
        """.data(using: .utf8)!

        let decoded = try ProjectFile.decode(legacyJSON)
        XCTAssertEqual(decoded.schemaVersion, BookProject.currentSchemaVersion)
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
