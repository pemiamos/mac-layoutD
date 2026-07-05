import XCTest
@testable import LayoutDCore
@testable import LayoutDEngine

final class LayoutHeightCacheTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        LayoutHeightCache.shared.clear()
    }
    
    func testHeightCacheSavesAndRetrieves() {
        let style = ParagraphStyle(
            id: "testStyle",
            displayName: "Test",
            fontName: "Songti SC",
            fontSize: 10.0,
            lineHeight: 14.0,
            firstLineIndent: 0,
            spaceBefore: 0,
            spaceAfter: 0,
            colorToken: "ink"
        )
        
        let text = "测高测试文本"
        let width = 300.0
        
        // Initially empty
        XCTAssertEqual(LayoutHeightCache.shared.count, 0)
        XCTAssertNil(LayoutHeightCache.shared.get(text: text, style: style, width: width))
        
        // Store
        LayoutHeightCache.shared.set(text: text, style: style, width: width, height: 42.0)
        XCTAssertEqual(LayoutHeightCache.shared.count, 1)
        
        // Retrieve
        let cached = LayoutHeightCache.shared.get(text: text, style: style, width: width)
        XCTAssertEqual(cached, 42.0)
    }
    
    func testCompositeFontDifferenceDoesNotCollision() {
        let mapping1 = [
            CompositeFontClass.chinese: CompositeFontMapping(fontName: "Songti SC", sizeMultiplier: 1.0, baselineOffset: 0.0),
            CompositeFontClass.latin: CompositeFontMapping(fontName: "Georgia", sizeMultiplier: 1.0, baselineOffset: 0.0)
        ]
        
        let mapping2 = [
            CompositeFontClass.chinese: CompositeFontMapping(fontName: "PingFang SC", sizeMultiplier: 1.0, baselineOffset: 0.0),
            CompositeFontClass.latin: CompositeFontMapping(fontName: "Times New Roman", sizeMultiplier: 1.0, baselineOffset: 0.0)
        ]
        
        let style1 = ParagraphStyle(
            id: "style1",
            displayName: "Style 1",
            fontName: "Helvetica",
            fontSize: 12.0,
            lineHeight: 16.0,
            firstLineIndent: 0.0,
            spaceBefore: 0.0,
            spaceAfter: 0.0,
            compositeFont: mapping1
        )
        
        let style2 = ParagraphStyle(
            id: "style2",
            displayName: "Style 2",
            fontName: "Helvetica",
            fontSize: 12.0,
            lineHeight: 16.0,
            firstLineIndent: 0.0,
            spaceBefore: 0.0,
            spaceAfter: 0.0,
            compositeFont: mapping2
        )
        
        let text = "中英混排 Text Test"
        let width = 200.0
        
        // Set height for style1
        LayoutHeightCache.shared.set(text: text, style: style1, width: width, height: 32.0)
        
        // Verify style1 gets cached height
        XCTAssertEqual(LayoutHeightCache.shared.get(text: text, style: style1, width: width), 32.0)
        
        // Verify style2 does NOT hit the cache (since composite font mappings are different)
        XCTAssertNil(LayoutHeightCache.shared.get(text: text, style: style2, width: width))
        
        // Now set height for style2
        LayoutHeightCache.shared.set(text: text, style: style2, width: width, height: 48.0)
        
        // Verify both styles get their respective cached heights without collision
        XCTAssertEqual(LayoutHeightCache.shared.get(text: text, style: style1, width: width), 32.0)
        XCTAssertEqual(LayoutHeightCache.shared.get(text: text, style: style2, width: width), 48.0)
    }
    
    func testCacheExceedsLimitClearsAll() {
        let style = ParagraphStyle(
            id: "test",
            displayName: "Test",
            fontName: "Helvetica",
            fontSize: 10.0,
            lineHeight: 14.0,
            firstLineIndent: 0.0,
            spaceBefore: 0.0,
            spaceAfter: 0.0
        )
        
        // Set 5001 different keys to trigger cache purge
        for i in 1...5001 {
            LayoutHeightCache.shared.set(text: "text \(i)", style: style, width: 100.0, height: Double(i))
        }
        
        // Cache should have purged and ended up with just the 5001st item
        XCTAssertEqual(LayoutHeightCache.shared.count, 1)
        XCTAssertEqual(LayoutHeightCache.shared.get(text: "text 5001", style: style, width: 100.0), 5001.0)
    }
}
