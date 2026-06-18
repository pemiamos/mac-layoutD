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
}
