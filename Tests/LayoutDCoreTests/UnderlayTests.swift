import XCTest
@testable import LayoutDCore
@testable import LayoutDEngine

final class UnderlayTests: XCTestCase {
    
    func testUnderlayAssetDoesNotOccupySpace() throws {
        let underlayAsset = Asset(
            id: UUID(),
            fileName: "underlay.png",
            role: .photo,
            caption: "测试底图",
            pixelWidth: 800,
            pixelHeight: 600,
            dpi: 72,
            wrapMode: .underlay
        )
        
        let project = BookProject(
            metadata: ProjectMetadata(title: "底图测试", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .figure(assetId: underlayAsset.id), text: "", styleId: StyleID.body.rawValue),
                                Paragraph(kind: .body, text: "文字直接压图走", styleId: StyleID.body.rawValue)
                            ]
                        )
                    ]
                )
            ],
            assets: [underlayAsset]
        )
        
        // Disable TOC to keep pages simple (1 cover, 1 content page)
        var setup = project.pageSetup
        setup.includesTableOfContents = false
        setup.facingPages = false
        var testProject = project
        testProject.pageSetup = setup
        
        let document = LayoutEngine().layout(project: testProject)
        
        // There should be a cover page (page 1) and content page (page 2)
        XCTAssertEqual(document.pages.count, 2)
        
        let contentPage = document.pages[1]
        
        // Find frames
        let firstImage: PageFrame? = contentPage.frames.first(where: { $0.kind == PageFrameKind.image })
        let imageFrame = try XCTUnwrap(firstImage)
        
        let firstCaption: PageFrame? = contentPage.frames.first(where: { $0.kind == PageFrameKind.caption })
        let captionFrame = try XCTUnwrap(firstCaption)
        
        let firstText: PageFrame? = contentPage.frames.first(where: { $0.kind == PageFrameKind.text && $0.styleId == StyleID.body.rawValue })
        let textFrame = try XCTUnwrap(firstText)
        
        // Verify image wrap mode is underlay
        if case .asset(let assetId) = imageFrame.content {
            XCTAssertEqual(assetId, underlayAsset.id)
            let asset = try XCTUnwrap(testProject.assets.first { $0.id == assetId })
            XCTAssertEqual(asset.effectiveWrapMode, .underlay)
        } else {
            XCTFail("Image frame content must be asset")
        }
        
        // Verify coordinates: The text frame should start at the same cursor position as the image frame
        // because the underlay image does not advance the cursor.
        XCTAssertEqual(textFrame.rect.y, imageFrame.rect.y, accuracy: 0.001)
        
        // Caption should be placed right below the image frame
        XCTAssertEqual(captionFrame.rect.y, imageFrame.rect.y + imageFrame.rect.height + 4, accuracy: 0.001)
    }
    
    func testWrapAssetOccupiesSpace() throws {
        // Control test: normal wrap asset should occupy space
        let wrapAsset = Asset(
            id: UUID(),
            fileName: "wrap.png",
            role: .photo,
            caption: "测试绕排图",
            pixelWidth: 800,
            pixelHeight: 600,
            dpi: 72,
            wrapMode: .wrap
        )
        
        let project = BookProject(
            metadata: ProjectMetadata(title: "绕排测试", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .figure(assetId: wrapAsset.id), text: "", styleId: StyleID.body.rawValue),
                                Paragraph(kind: .body, text: "文字避让绕排", styleId: StyleID.body.rawValue)
                            ]
                        )
                    ]
                )
            ],
            assets: [wrapAsset]
        )
        
        var setup = project.pageSetup
        setup.includesTableOfContents = false
        setup.facingPages = false
        var testProject = project
        testProject.pageSetup = setup
        
        let document = LayoutEngine().layout(project: testProject)
        
        XCTAssertEqual(document.pages.count, 2)
        let contentPage = document.pages[1]
        
        let firstImage: PageFrame? = contentPage.frames.first(where: { $0.kind == PageFrameKind.image })
        let imageFrame = try XCTUnwrap(firstImage)
        
        let firstCaption: PageFrame? = contentPage.frames.first(where: { $0.kind == PageFrameKind.caption })
        let captionFrame = try XCTUnwrap(firstCaption)
        
        let firstText: PageFrame? = contentPage.frames.first(where: { $0.kind == PageFrameKind.text && $0.styleId == StyleID.body.rawValue })
        let textFrame = try XCTUnwrap(firstText)
        
        // In normal wrap, the text frame should start after the image and caption.
        // So textFrame.rect.y must be greater than captionFrame.rect.y.
        XCTAssertGreaterThan(textFrame.rect.y, captionFrame.rect.y)
    }

    func testUnderlaySpreadAssetDoesNotAdvancePage() throws {
        let spreadAsset = Asset(
            id: UUID(),
            fileName: "spread.png",
            role: .spread,
            caption: "测试对页底图",
            pixelWidth: 1600,
            pixelHeight: 600,
            dpi: 72,
            wrapMode: .underlay
        )
        
        let project = BookProject(
            metadata: ProjectMetadata(title: "对页底图测试", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .figure(assetId: spreadAsset.id), text: "", styleId: StyleID.body.rawValue),
                                Paragraph(kind: .body, text: "正文继续在此页排版", styleId: StyleID.body.rawValue)
                            ]
                        )
                    ]
                )
            ],
            assets: [spreadAsset]
        )
        
        var setup = project.pageSetup
        setup.includesTableOfContents = false
        setup.facingPages = true
        var testProject = project
        testProject.pageSetup = setup
        
        let document = LayoutEngine().layout(project: testProject)
        
        // Page 1 is Cover (frontMatter).
        // Since absolute page number for content starts at 2 (even/verso page),
        // the spread will be scheduled for page 2 and page 3.
        // Let's verify that pages are generated and the text paragraph remains on page 2.
        XCTAssertGreaterThanOrEqual(document.pages.count, 3)
        
        let page2 = document.pages[1] // Page 2 (content page 1)
        let page3 = document.pages[2] // Page 3 (content page 2)
        
        // Check that page 2 has the left half of the spread frame, and the text frame
        let leftSpreadFrameOpt: PageFrame? = page2.frames.first(where: {
            if case .spreadAsset(_, let isLeft) = $0.content { return isLeft }
            return false
        })
        let leftSpreadFrame = try XCTUnwrap(leftSpreadFrameOpt)
        
        let textFrameOpt: PageFrame? = page2.frames.first(where: {
            if case .text(let text) = $0.content { return text.contains("正文继续在此页排版") }
            return false
        })
        let textFrame = try XCTUnwrap(textFrameOpt)
        
        // Text should be on page 2 (meaning it did not advance past the spread)
        XCTAssertEqual(textFrame.rect.y, leftSpreadFrame.rect.y, accuracy: 0.001)
        
        // Check that page 3 has the right half of the spread frame and caption
        let rightSpreadFrameOpt: PageFrame? = page3.frames.first(where: {
            if case .spreadAsset(_, let isLeft) = $0.content { return !isLeft }
            return false
        })
        let rightSpreadFrame = try XCTUnwrap(rightSpreadFrameOpt)
        
        let captionFrameOpt: PageFrame? = page3.frames.first(where: { $0.kind == PageFrameKind.caption })
        let captionFrame = try XCTUnwrap(captionFrameOpt)
        XCTAssertTrue(captionFrame.rect.y > rightSpreadFrame.rect.y)
    }
}
