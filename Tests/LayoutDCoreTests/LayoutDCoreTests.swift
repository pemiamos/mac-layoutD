import LayoutDCore
import LayoutDDesignAI
import LayoutDEngine
import XCTest

final class LayoutDCoreTests: XCTestCase {
    func testSampleProjectEncodesAndDecodes() throws {
        let project = BookProject.sample
        let data = try ProjectFile.encode(project)
        let decoded = try ProjectFile.decode(data)
        XCTAssertEqual(decoded.metadata.title, project.metadata.title)
        XCTAssertEqual(decoded.sections.count, 1)
        XCTAssertEqual(decoded.assets.count, 1)
    }

    func testLayoutEngineCreatesPagesAndFrames() {
        let document = LayoutEngine().layout(project: .sample)
        XCTAssertFalse(document.pages.isEmpty)
        XCTAssertFalse(document.pages[0].frames.isEmpty)
    }

    func testLayoutEngineDoesNotPlaceFigureAssetTwice() {
        let asset = Asset(
            fileName: "figure.png",
            role: .diagram,
            caption: "图 1 测试图",
            pixelWidth: 1200,
            pixelHeight: 800,
            dpi: 300
        )
        let project = BookProject(
            metadata: ProjectMetadata(title: "图文测试", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .figure(assetId: asset.id), text: "图 1 测试图", styleId: StyleID.caption.rawValue)
                            ]
                        )
                    ]
                )
            ],
            assets: [asset]
        )

        let document = LayoutEngine().layout(project: project)
        let imageFrames = document.pages.flatMap(\.frames).filter {
            if case .asset(asset.id) = $0.content {
                return true
            }
            return false
        }
        XCTAssertEqual(imageFrames.count, 1)
    }

    func testHeroImageGetsMoreVerticalSpaceThanDecorativeImage() {
        let hero = Asset(fileName: "hero.png", role: .hero, caption: "主图", pixelWidth: 1200, pixelHeight: 800, dpi: 300)
        let decorative = Asset(fileName: "decorative.png", role: .decorative, caption: "装饰图", pixelWidth: 1200, pixelHeight: 800, dpi: 300)
        let project = BookProject(
            metadata: ProjectMetadata(title: "图片尺寸测试", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .figure(assetId: hero.id), text: "主图", styleId: StyleID.caption.rawValue),
                                Paragraph(kind: .figure(assetId: decorative.id), text: "装饰图", styleId: StyleID.caption.rawValue)
                            ]
                        )
                    ]
                )
            ],
            assets: [hero, decorative]
        )

        let frames = LayoutEngine().layout(project: project).pages.flatMap(\.frames)
        let heroFrame = frames.first { $0.content == .asset(hero.id) }
        let decorativeFrame = frames.first { $0.content == .asset(decorative.id) }

        XCTAssertNotNil(heroFrame)
        XCTAssertNotNil(decorativeFrame)
        XCTAssertGreaterThan(heroFrame?.rect.height ?? 0, decorativeFrame?.rect.height ?? 0)
    }

    func testVeryLongParagraphReportsOverflowRisk() {
        let longText = String(repeating: "这是一个非常长的中文段落，用来测试单栏高度溢出的检测能力。", count: 180)
        let project = BookProject(
            metadata: ProjectMetadata(title: "长文测试", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .body, text: longText, styleId: StyleID.body.rawValue)
                            ]
                        )
                    ]
                )
            ]
        )

        let document = LayoutEngine().layout(project: project)
        XCTAssertTrue(document.issues.contains { $0.message.contains("文本段落高度超过单栏可用高度") })
    }

    func testAdvisorReturnsStructuredLayoutPlans() {
        let plans = RuleBasedLayoutAdvisor().proposePlans(for: .sample, target: .page(1))
        XCTAssertEqual(plans.count, 3)
        XCTAssertTrue(plans.allSatisfy { !$0.blocks.isEmpty })
    }
}
