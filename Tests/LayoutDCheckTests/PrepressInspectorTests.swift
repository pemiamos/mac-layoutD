import Foundation
import LayoutDCheck
import LayoutDCore
import XCTest

final class PrepressInspectorTests: XCTestCase {
    private func makeProject(bleedMM: Double?, appliedPlans: [Int: LayoutPlan]? = nil) -> BookProject {
        var setup = PageSetup.scienceBookDefault
        setup.bleedMM = bleedMM
        return BookProject(
            metadata: ProjectMetadata(title: "印前测试", author: "layoutD"),
            pageSetup: setup,
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [Paragraph(kind: .body, text: "正文", styleId: StyleID.body.rawValue)]
                        )
                    ]
                )
            ],
            appliedLayoutPlans: appliedPlans
        )
    }

    // MARK: - PDF/X honesty

    func testPDFXRequestedEmitsHonestyWarning() {
        let project = makeProject(bleedMM: 3.0)
        let issues = PrepressInspector().inspect(
            project: project,
            options: PrepressExportOptions(pdfxRequested: true, pdfxLabel: "PDF/X-1a")
        )
        XCTAssertTrue(issues.contains {
            $0.category == .prepress
                && $0.severity == .warning
                && $0.message.contains("PDF/X-1a")
                && $0.message.contains("并非")
        })
    }

    func testRGBExportEmitsColorSpaceHonestyWarning() {
        let project = makeProject(bleedMM: 3.0)
        let issues = PrepressInspector().inspect(project: project)
        XCTAssertTrue(issues.contains {
            $0.category == .prepress
                && $0.severity == .warning
                && $0.message.contains("导出管线为 RGB")
                && $0.message.contains("不执行 CMYK")
        })
    }

    func testNoPDFXMeansNoHonestyWarning() {
        let project = makeProject(bleedMM: 3.0)
        let issues = PrepressInspector().inspect(project: project, options: PrepressExportOptions(pdfxRequested: false))
        XCTAssertFalse(issues.contains { $0.message.contains("PDF/X") })
    }

    // MARK: - Bleed / crop consistency

    func testCropMarksWithZeroBleedWarns() {
        let project = makeProject(bleedMM: 0)
        let issues = PrepressInspector().inspect(
            project: project,
            options: PrepressExportOptions(drawCropMarks: true)
        )
        XCTAssertTrue(issues.contains {
            $0.category == .prepress
                && $0.severity == .warning
                && $0.message.contains("出血（bleedMM）为 0")
        })
    }

    func testSmallBleedEmitsInfo() {
        let project = makeProject(bleedMM: 1.5)
        let issues = PrepressInspector().inspect(project: project)
        XCTAssertTrue(issues.contains {
            $0.category == .prepress
                && $0.severity == .info
                && $0.message.contains("低于常规印刷出血")
        })
    }

    func testConventionalBleedIsClean() {
        let project = makeProject(bleedMM: 3.0)
        let issues = PrepressInspector().inspect(project: project, options: PrepressExportOptions(drawCropMarks: true))
        XCTAssertFalse(issues.contains { $0.message.contains("出血") })
    }

    // MARK: - Full-bleed coverage

    func testFullBleedPageWithoutCoveringFrameWarns() {
        let coverPlan = LayoutPlan(target: .page(1), strategy: .cover, blocks: [])
        let project = makeProject(bleedMM: 3.0, appliedPlans: [1: coverPlan])
        let width = project.pageSetup.pageSize.width
        let height = project.pageSetup.pageSize.height
        // A small image frame that does NOT cover the page.
        let smallFrame = PageFrame(
            kind: .image,
            rect: Rect(x: 10, y: 10, width: width / 3, height: height / 3),
            content: .asset(UUID())
        )
        let document = LaidOutDocument(projectId: project.id, pages: [LaidOutPage(number: 1, frames: [smallFrame])])

        let issues = PrepressInspector().inspect(project: project, document: document)
        XCTAssertTrue(issues.contains {
            $0.category == .prepress
                && $0.severity == .warning
                && $0.pageNumber == 1
                && $0.message.contains("出血区可能露白")
        })
    }

    func testFullBleedPageWithTrimOnlyCoveringImageWarns() {
        let coverPlan = LayoutPlan(target: .page(1), strategy: .fullPageImage, blocks: [])
        let project = makeProject(bleedMM: 3.0, appliedPlans: [1: coverPlan])
        let width = project.pageSetup.pageSize.width
        let height = project.pageSetup.pageSize.height
        // An image that fills only the TrimBox (no bleed extension) must still warn,
        // because it leaves the BleedBox uncovered.
        let trimOnlyFrame = PageFrame(
            kind: .image,
            rect: Rect(x: 0, y: 0, width: width, height: height),
            content: .asset(UUID())
        )
        let document = LaidOutDocument(projectId: project.id, pages: [LaidOutPage(number: 1, frames: [trimOnlyFrame])])

        let issues = PrepressInspector().inspect(project: project, document: document)
        XCTAssertTrue(issues.contains { $0.message.contains("BleedBox") })
    }

    func testFullBleedPageWithBleedBoxCoveringImageIsClean() {
        let coverPlan = LayoutPlan(target: .page(1), strategy: .fullPageImage, blocks: [])
        let project = makeProject(bleedMM: 3.0, appliedPlans: [1: coverPlan])
        let width = project.pageSetup.pageSize.width
        let height = project.pageSetup.pageSize.height
        let bleed = 3.0 * 72.0 / 25.4
        let fullFrame = PageFrame(
            kind: .image,
            rect: Rect(x: -bleed, y: -bleed, width: width + 2 * bleed, height: height + 2 * bleed),
            content: .asset(UUID())
        )
        let document = LaidOutDocument(projectId: project.id, pages: [LaidOutPage(number: 1, frames: [fullFrame])])

        let issues = PrepressInspector().inspect(project: project, document: document)
        XCTAssertFalse(issues.contains { $0.message.contains("露白") })
    }

    func testFullPageTextFrameDoesNotCountAsBleedCoverage() {
        // A full-page *text* frame must not satisfy bleed coverage — only visual assets bleed.
        let coverPlan = LayoutPlan(target: .page(1), strategy: .cover, blocks: [])
        let project = makeProject(bleedMM: 3.0, appliedPlans: [1: coverPlan])
        let width = project.pageSetup.pageSize.width
        let height = project.pageSetup.pageSize.height
        let textFrame = PageFrame(
            kind: .text,
            rect: Rect(x: 0, y: 0, width: width, height: height),
            content: .text("标题")
        )
        let document = LaidOutDocument(projectId: project.id, pages: [LaidOutPage(number: 1, frames: [textFrame])])

        let issues = PrepressInspector().inspect(project: project, document: document)
        XCTAssertTrue(issues.contains { $0.message.contains("露白") })
    }

    // MARK: - Actual export-size DPI

    func testPlacedAssetDPIUsesActualFrameWidth() {
        let asset = Asset(
            fileName: "wide-photo.png",
            role: .photo,
            caption: "wide",
            credit: "layoutD",
            pixelWidth: 600,
            pixelHeight: 400,
            dpi: 300
        )
        var project = makeProject(bleedMM: 3.0)
        project.assets = [asset]
        let frame = PageFrame(
            kind: .image,
            rect: Rect(x: 0, y: 0, width: 300, height: 200),
            content: .asset(asset.id)
        )
        let document = LaidOutDocument(projectId: project.id, pages: [LaidOutPage(number: 2, frames: [frame])])

        let issues = PrepressInspector().inspect(project: project, document: document)

        XCTAssertTrue(issues.contains {
            $0.category == .prepress
                && $0.pageNumber == 2
                && $0.frameId == frame.id
                && $0.assetId == asset.id
                && $0.message.contains("144 DPI")
                && $0.message.contains("实际导出尺寸")
        })
    }

    // MARK: - Fonts

    func testUnavailableFontWarns() {
        var project = makeProject(bleedMM: 3.0)
        var style = ParagraphStyle.body
        style.fontName = "Definitely Missing LayoutD Test Font 999"
        style.compositeFont = nil
        project.styles = StyleLibrary(paragraphStyles: [style], colors: StyleLibrary.defaultChineseScience.colors)

        let issues = PrepressInspector().inspect(project: project)

        XCTAssertTrue(issues.contains {
            $0.category == .prepress
                && $0.message.contains("Definitely Missing LayoutD Test Font 999")
                && $0.message.contains("不可用")
        })
    }

    // MARK: - Hairline strokes

    func testHairlineStrokeWarns() {
        let project = makeProject(bleedMM: 3.0)
        let hairline = PageFrame(
            kind: .image,
            rect: Rect(x: 10, y: 10, width: 100, height: 100),
            content: .asset(UUID()),
            strokeColorHex: "#000000",
            strokeWidth: 0.1
        )
        let document = LaidOutDocument(projectId: project.id, pages: [LaidOutPage(number: 4, frames: [hairline])])

        let issues = PrepressInspector().inspect(project: project, document: document)
        XCTAssertTrue(issues.contains {
            $0.category == .prepress
                && $0.severity == .warning
                && $0.pageNumber == 4
                && $0.message.contains("发丝线")
                && $0.frameId == hairline.id
        })
    }

    func testNormalStrokeIsClean() {
        let project = makeProject(bleedMM: 3.0)
        let frame = PageFrame(
            kind: .image,
            rect: Rect(x: 10, y: 10, width: 100, height: 100),
            content: .asset(UUID()),
            strokeColorHex: "#000000",
            strokeWidth: 1.0
        )
        let document = LaidOutDocument(projectId: project.id, pages: [LaidOutPage(number: 4, frames: [frame])])

        let issues = PrepressInspector().inspect(project: project, document: document)
        XCTAssertFalse(issues.contains { $0.message.contains("发丝线") })
    }

    // MARK: - Integration via ProjectInspector

    func testPreflightIncludesPrepressIssues() {
        let project = makeProject(bleedMM: 1.0)
        let report = ProjectInspector().preflight(
            project: project,
            document: nil,
            exportOptions: PrepressExportOptions(pdfxRequested: true, pdfxLabel: "PDF/X-3")
        )
        XCTAssertTrue(report.issues.contains { $0.category == .prepress && $0.message.contains("PDF/X-3") })
        XCTAssertTrue(report.issues.contains { $0.category == .prepress && $0.message.contains("低于常规印刷出血") })
    }
}
