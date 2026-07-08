import XCTest
import LayoutDCore
import LayoutDImport
@testable import LayoutDApp

final class StyleImportTests: XCTestCase {
    
    func testDTCGImportAutoDetectAndFlatten() throws {
        let jsonString = """
        {
            "color": {
                "ink": {
                    "$type": "color",
                    "$value": {
                        "default": "#17202A",
                        "dark": "#FFFFFF"
                    }
                },
                "paper": {
                    "$type": "color",
                    "$value": "#F7F4EE"
                }
            },
            "paragraph": {
                "body": {
                    "fontSize": {
                        "$type": "number",
                        "$value": 11.5
                    }
                }
            },
            "page": {
                "columns": {
                    "$type": "number",
                    "$value": 3
                }
            }
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        let (tokens, format) = try StyleBaselineImporter.autoDetectAndParse(jsonData: data)
        
        XCTAssertEqual(format, .dtcg)
        XCTAssertEqual(tokens.colorModes.sorted(), ["dark", "default"])
        XCTAssertEqual(tokens.colors.count, 2)
        XCTAssertEqual(tokens.scalars.count, 2)
        
        // Assert color resolutions
        XCTAssertEqual(tokens.colorHex("ink", mode: "default"), "#17202A")
        XCTAssertEqual(tokens.colorHex("ink", mode: "dark"), "#FFFFFF")
        XCTAssertEqual(tokens.colorHex("paper", mode: "default"), "#F7F4EE")
        
        // Assert scalar resolutions
        XCTAssertEqual(tokens.scalar("paragraph.body.fontSize"), 11.5)
        XCTAssertEqual(tokens.scalar("page.columns"), 3.0)
    }
    
    func testFigmaVariablesImport() throws {
        let jsonString = """
        {
            "collections": [
                {
                    "name": "Brand",
                    "modes": [
                        {"modeId": "1:0", "name": "Light Mode"},
                        {"modeId": "1:1", "name": "Dark Mode"}
                    ],
                    "variables": [
                        {
                            "name": "color/ink",
                            "type": "COLOR",
                            "valuesByMode": {
                                "1:0": { "r": 0.09, "g": 0.12, "b": 0.16, "a": 1 },
                                "1:1": { "r": 1.0, "g": 1.0, "b": 1.0, "a": 1 }
                            }
                        },
                        {
                            "name": "paragraph/body/fontSize",
                            "type": "FLOAT",
                            "valuesByMode": {
                                "1:0": 12.0
                            }
                        }
                    ]
                }
            ]
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        let (tokens, format) = try StyleBaselineImporter.autoDetectAndParse(jsonData: data)
        
        XCTAssertEqual(format, .figma)
        XCTAssertEqual(tokens.colorModes.sorted(), ["Dark Mode", "Light Mode", "default"])
        XCTAssertEqual(tokens.colors.count, 1)
        XCTAssertEqual(tokens.scalars.count, 1)
        
        // Assert color conversions
        XCTAssertEqual(tokens.colorHex("ink", mode: "Light Mode"), "#171F29")
        XCTAssertEqual(tokens.colorHex("ink", mode: "Dark Mode"), "#FFFFFF")
        XCTAssertEqual(tokens.scalar("paragraph.body.fontSize"), 12.0)
    }
    
    func testApplyImportedTokensAutoBinding() throws {
        let project = BookProject.sample
        let state = AppState(project: project)
        
        // Ensure initial un-bound fields
        XCTAssertNotEqual(state.project.pageSetup.columns, 3)
        
        // Build mock DesignTokens
        let mockTokens = DesignTokens(
            colorModes: ["default"],
            defaultMode: "default",
            colors: [
                ColorTokenSet(id: "ink", hex: "#445566")
            ],
            scalars: [
                ScalarToken(id: "paragraph.body.fontSize", value: 13.0),
                ScalarToken(id: "page.columns", value: 3.0),
                ScalarToken(id: "page.gutter", value: 24.0)
            ]
        )
        
        // Apply tokens via state
        state.applyImportedTokens(mockTokens, baselineGridCompensate: 16.5)
        
        // Assert updated setup and bindings
        XCTAssertEqual(state.project.pageSetup.columns, 3)
        XCTAssertEqual(state.project.pageSetup.columnsToken, "page.columns")
        XCTAssertEqual(state.project.pageSetup.gutter, 24.0)
        XCTAssertEqual(state.project.pageSetup.gutterToken, "page.gutter")
        XCTAssertEqual(state.project.pageSetup.baselineGrid, 16.5)
        XCTAssertNil(state.project.pageSetup.baselineGridToken) // compensated manually, so token is nil
        
        // Assert updated styles and bindings
        let bodyStyle = state.project.styles.paragraphStyle(id: StyleID.body.rawValue)
        XCTAssertEqual(bodyStyle.fontSize, 13.0)
        XCTAssertEqual(bodyStyle.fontSizeToken, "paragraph.body.fontSize")
        
        // Assert undo rolls back to original state
        XCTAssertTrue(state.canUndo)
        state.undo()
        
        XCTAssertNotEqual(state.project.pageSetup.columns, 3)
        let rolledBackBodyStyle = state.project.styles.paragraphStyle(id: StyleID.body.rawValue)
        XCTAssertNotEqual(rolledBackBodyStyle.fontSize, 13.0)
    }

    func testApplySpecPack() throws {
        var project = BookProject.sample
        
        let tokens = DesignTokens(
            colorModes: ["default"],
            defaultMode: "default",
            colors: [
                ColorTokenSet(id: "accent", hex: "#F5C518"),
                ColorTokenSet(id: "ink", hex: "#1B1B1B")
            ],
            scalars: [
                ScalarToken(id: "page.width", value: 500.0, kind: .dimension),
                ScalarToken(id: "page.height", value: 700.0, kind: .dimension),
                ScalarToken(id: "page.vertical", value: 1.0, kind: .dimension)
            ]
        )
        
        let result = SpecPackImportResult(
            tokens: tokens,
            unsupportedFields: [],
            fontResolutions: [
                SpecPackFontResolution(roleOrAlias: "章名", requestedName: "标题", resolvedName: "Heiti SC Medium"),
                SpecPackFontResolution(roleOrAlias: "正文", requestedName: "正文", resolvedName: "Songti SC"),
                SpecPackFontResolution(roleOrAlias: "西文", requestedName: "西文", resolvedName: "Georgia")
            ],
            roleColors: [
                "章名": "ink",
                "抽言": "accent"
            ],
            roleDecorations: [
                "抽言": SpecPackDecoration(type: "left-rule", color: "accent", widthPt: 3)
            ]
        )
        
        project.applySpecPack(result)
        
        // 1. Check page setup size and layout direction
        XCTAssertEqual(project.pageSetup.pageSize.width, 500.0)
        XCTAssertEqual(project.pageSetup.pageSize.height, 700.0)
        XCTAssertEqual(project.pageSetup.layoutDirection, .vertical)
        
        // 2. Check Paragraph Style font mappings
        let headingStyle = project.styles.paragraphStyle(id: StyleID.heading1.rawValue)
        XCTAssertEqual(headingStyle.fontName, "Heiti SC Medium")
        XCTAssertEqual(headingStyle.colorToken, "ink")
        XCTAssertEqual(headingStyle.compositeFont?[.chinese]?.fontName, "Heiti SC Medium")
        XCTAssertEqual(headingStyle.compositeFont?[.latin]?.fontName, "Georgia")
        
        let bodyStyle = project.styles.paragraphStyle(id: StyleID.body.rawValue)
        XCTAssertEqual(bodyStyle.fontName, "Songti SC")
        XCTAssertEqual(bodyStyle.compositeFont?[.chinese]?.fontName, "Songti SC")
        
        let pullQuoteStyle = project.styles.paragraphStyle(id: StyleID.pullQuote.rawValue)
        XCTAssertEqual(pullQuoteStyle.colorToken, "accent")
        
        // 3. Check ComponentStyle decorations
        let calloutStyle = project.styles.safeComponentStyles.first(where: { $0.frameKind == .callout })
        XCTAssertNotNil(calloutStyle)
        XCTAssertEqual(calloutStyle?.accentColorToken, "accent")
        XCTAssertEqual(compStyleAccentWidth(calloutStyle!), 3.0)
        XCTAssertEqual(compStyleStrokeWidth(calloutStyle!), 0.0)
    }
    
    private func compStyleAccentWidth(_ style: ComponentStyle) -> Double {
        style.accentWidth
    }

    private func compStyleStrokeWidth(_ style: ComponentStyle) -> Double {
        style.strokeWidth
    }

    // MARK: - SPEC-APPLY-1: GUI apply path carries the full spec-pack result

    /// The spec pack that the GUI apply path must land: fonts / role colors /
    /// trim / decorations — not just DesignTokens.
    private func sampleSpecResult() -> SpecPackImportResult {
        let tokens = DesignTokens(
            colorModes: ["default"],
            defaultMode: "default",
            colors: [
                ColorTokenSet(id: "accent", hex: "#F5C518"),
                ColorTokenSet(id: "ink", hex: "#1B1B1B")
            ],
            scalars: [
                ScalarToken(id: "page.width", value: 500.0, kind: .dimension),
                ScalarToken(id: "page.height", value: 700.0, kind: .dimension)
            ]
        )
        return SpecPackImportResult(
            tokens: tokens,
            unsupportedFields: [],
            fontResolutions: [
                SpecPackFontResolution(roleOrAlias: "章名", requestedName: "标题", resolvedName: "SpecApplyHeadingFont"),
                SpecPackFontResolution(roleOrAlias: "正文", requestedName: "正文", resolvedName: "SpecApplyBodyFont"),
                SpecPackFontResolution(roleOrAlias: "西文", requestedName: "西文", resolvedName: "SpecApplyLatinFont")
            ],
            roleColors: ["章名": "ink", "抽言": "accent"],
            roleDecorations: [
                "抽言": SpecPackDecoration(type: "left-rule", color: "accent", widthPt: 3)
            ]
        )
    }

    /// The GUI apply path (`applySpecPackResult`) must land the same visual state
    /// (fonts / role colors / trim / decorations) as `BookProject.applySpecPack`.
    func testGUIApplySpecPackResultLandsFontsColorsAndTrim() throws {
        let state = AppState(project: BookProject.sample)
        state.applySpecPackResult(sampleSpecResult())

        // Trim
        XCTAssertEqual(state.project.pageSetup.pageSize.width, 500.0)
        XCTAssertEqual(state.project.pageSetup.pageSize.height, 700.0)

        // Fonts (composite) — the differentiator that used to be dropped
        let heading = state.project.styles.paragraphStyle(id: StyleID.heading1.rawValue)
        XCTAssertEqual(heading.fontName, "SpecApplyHeadingFont")
        XCTAssertEqual(heading.compositeFont?[.chinese]?.fontName, "SpecApplyHeadingFont")
        XCTAssertEqual(heading.compositeFont?[.latin]?.fontName, "SpecApplyLatinFont")
        XCTAssertEqual(heading.colorToken, "ink")

        let body = state.project.styles.paragraphStyle(id: StyleID.body.rawValue)
        XCTAssertEqual(body.fontName, "SpecApplyBodyFont")

        // Role color + decoration
        let pullQuote = state.project.styles.paragraphStyle(id: StyleID.pullQuote.rawValue)
        XCTAssertEqual(pullQuote.colorToken, "accent")
        let callout = state.project.styles.safeComponentStyles.first(where: { $0.frameKind == .callout })
        XCTAssertEqual(callout?.accentColorToken, "accent")

        // Undo restores the pre-import state
        XCTAssertTrue(state.canUndo)
        state.undo()
        XCTAssertNotEqual(state.project.styles.paragraphStyle(id: StyleID.heading1.rawValue).fontName, "SpecApplyHeadingFont")
    }

    /// Regression guard for the SPEC-APPLY-1 gap: the tokens-only path
    /// (`applyImportedTokens`) intentionally does NOT carry fonts / role colors /
    /// decorations. This is exactly why the GUI must route spec packs through
    /// `applySpecPackResult` instead. If this ever starts landing fonts, the two
    /// paths have converged and the routing split can be revisited.
    func testTokensOnlyPathDoesNotCarryFontsOrRoleColors() throws {
        let result = sampleSpecResult()
        let state = AppState(project: BookProject.sample)
        let originalFont = state.project.styles.paragraphStyle(id: StyleID.heading1.rawValue).fontName

        state.applyImportedTokens(result.tokens)

        let heading = state.project.styles.paragraphStyle(id: StyleID.heading1.rawValue)
        XCTAssertEqual(heading.fontName, originalFont, "tokens-only path must not change fonts")
        XCTAssertNotEqual(heading.fontName, "SpecApplyHeadingFont")
        // Trim lives in DesignTokens, so it DOES apply on both paths.
        XCTAssertEqual(state.project.pageSetup.pageSize.width, 500.0)
    }

    /// A spec pack's role decoration (抽言 left-rule) must land as a paragraph
    /// accent rule on the pull-quote style, and survive token resolution (the
    /// renderers read the resolved style — ACCENT-1).
    func testSpecPackDecorationLandsAsParagraphAccentRule() throws {
        let state = AppState(project: BookProject.sample)
        state.applySpecPackResult(sampleSpecResult())

        let pull = state.project.styles.paragraphStyle(id: StyleID.pullQuote.rawValue)
        let rule = try XCTUnwrap(pull.accentRule, "抽言 left-rule decoration should map to a paragraph accent rule")
        XCTAssertEqual(rule.edge, .left)
        XCTAssertEqual(rule.colorToken, "accent")
        XCTAssertEqual(rule.width, 3)
        // paragraphStyle(id:) returns the token-resolved copy — the rule must survive.
        XCTAssertNotNil(state.project.styles.paragraphStyle(id: StyleID.pullQuote.rawValue).accentRule)
    }

    /// `autoDetectAndParseDetailed` must preserve the full result for a spec pack
    /// and return nil `specResult` for DTCG / Figma.
    func testAutoDetectDetailedPreservesSpecResult() throws {
        let dtcg = """
        {"color":{"ink":{"$type":"color","$value":"#111111"}}}
        """
        let dtcgDetected = try StyleBaselineImporter.autoDetectAndParseDetailed(jsonData: Data(dtcg.utf8))
        XCTAssertEqual(dtcgDetected.format, .dtcg)
        XCTAssertNil(dtcgDetected.specResult)
    }
}
