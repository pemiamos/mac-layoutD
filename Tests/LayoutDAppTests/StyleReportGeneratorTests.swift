import XCTest
@testable import LayoutDCore
@testable import LayoutDEngine
@testable import LayoutDImport
@testable import LayoutDCheck
@testable import LayoutDApp

final class StyleReportGeneratorTests: XCTestCase {
    func testStyleReportCalculation() throws {
        // 1. Setup design tokens and mock spec pack result
        let tokens = DesignTokens(
            colorModes: ["default"],
            defaultMode: "default",
            colors: [
                ColorTokenSet(id: "ink", hex: "#000000"),
                ColorTokenSet(id: "paper", hex: "#FFFFFF"),
                ColorTokenSet(id: "accent", hex: "#FF0000")
            ],
            scalars: [
                ScalarToken(id: "bodySize", value: 10.0),
                ScalarToken(id: "headingSize", value: 18.0)
            ]
        )
        
        let motifs = SpecPackMotifs(
            chapterNumber: SpecPackChapterNumberMotif(fontAlias: "heading", fontSizePt: 72, color: "accent"),
            sectionNumber: SpecPackSectionNumberMotif(style: "arabic", color: "accent", minDigits: 2),
            header: SpecPackHeaderMotif(fontAlias: "body", fontSizePt: 9, color: "gray"),
            captionTick: SpecPackDecoration(type: "top-tick", color: "accent", widthPt: 2, lengthMM: 6),
            headingRule: SpecPackDecoration(type: "underline", color: "accent", widthPt: 1),
            pullQuoteRule: SpecPackDecoration(type: "left-rule", color: "accent", widthPt: 3)
        )
        
        let specResult = SpecPackImportResult(
            tokens: tokens,
            unsupportedFields: ["unsupportedToken"],
            fontResolutions: [],
            roleColors: ["ink": "ink", "accent": "accent"],
            roleDecorations: [:],
            motifs: motifs,
            layoutGrammar: nil,
            qualityGates: SpecPackQualityGates(maxTemplateRepeat: 2)
        )
        
        // 2. Setup project with styles referencing tokens
        var project = BookProject(
            metadata: ProjectMetadata(title: "Test Book", subtitle: nil, author: "Author", publisher: "Publisher"),
            pageSetup: .scienceBookDefault
        )
        
        // Setup styles using the tokens
        let bodyStyle = ParagraphStyle(
            id: "body",
            displayName: "Body",
            fontName: "Arial",
            fontSize: 10,
            lineHeight: 15,
            firstLineIndent: 0,
            spaceBefore: 0,
            spaceAfter: 0,
            colorToken: "ink",
            fontSizeToken: "bodySize"
        )
        
        let headingStyle = ParagraphStyle(
            id: "heading1",
            displayName: "Heading 1",
            fontName: "Arial",
            fontSize: 18,
            lineHeight: 24,
            firstLineIndent: 0,
            spaceBefore: 12,
            spaceAfter: 6,
            colorToken: "accent",
            fontSizeToken: "headingSize",
            accentRule: ParagraphAccentRule(edge: .bottom, colorToken: "accent", width: 1.5)
        )
        
        let pullQuoteStyle = ParagraphStyle(
            id: "pullQuote",
            displayName: "Pull Quote",
            fontName: "Arial",
            fontSize: 12,
            lineHeight: 18,
            firstLineIndent: 0,
            spaceBefore: 6,
            spaceAfter: 6,
            colorToken: "accent",
            accentRule: ParagraphAccentRule(edge: .left, colorToken: "accent", width: 3.0)
        )
        
        project.styles.paragraphStyles = [bodyStyle, headingStyle, pullQuoteStyle]
        
        let pageSize = project.pageSetup.pageSize
        let pageArea = pageSize.width * pageSize.height
        
        // Page 1
        var page1 = LaidOutPage(number: 1)
        // Add a text frame (heading)
        let frame1 = PageFrame(
            id: UUID(),
            kind: .text,
            rect: Rect(x: 50, y: 50, width: 200, height: 40),
            styleId: "heading1",
            content: .text("Chapter 1")
        )
        page1.frames = [frame1]
        
        // Page 2
        var page2 = LaidOutPage(number: 2)
        // Add text frame and image frame
        let frame2 = PageFrame(
            id: UUID(),
            kind: .text,
            rect: Rect(x: 50, y: 50, width: 200, height: 200),
            styleId: "body",
            content: .text("This is the body text.")
        )
        let frame3 = PageFrame(
            id: UUID(),
            kind: .image,
            rect: Rect(x: 50, y: 300, width: 200, height: 150),
            styleId: nil,
            content: .empty
        )
        page2.frames = [frame2, frame3]
        
        let doc = LaidOutDocument(projectId: project.id, pages: [page1, page2])
        
        // Setup mock preflight report with one layout issue
        let issue = LayoutIssue(
            severity: .warning,
            message: "检测到元素重叠",
            category: .layout,
            pageNumber: 2
        )
        let preflight = PreflightReport(project: project, issues: [issue], document: doc)
        
        // 3. Generate style report
        let report = StyleReportGenerator.generateReport(
            project: project,
            document: doc,
            preflightReport: preflight,
            specResult: specResult
        )
        
        // 4. Assert correctness
        // Token coverage should be evaluated:
        // Ink, Accent, BodySize, HeadingSize used. Paper unused. (4 out of 5 used = 80%)
        XCTAssertEqual(report.tokenCoverage, 0.8)
        
        // Overlaps and overflows
        XCTAssertTrue(report.overlapsCheck)
        XCTAssertFalse(report.overflowsCheck)
        
        // Layout repeat count
        // Both are "auto_frames" with 1 and 2 frames respectively, so repeat count should be 1
        XCTAssertEqual(report.layoutRepeatCount, 1)
        XCTAssertEqual(report.repeatViolationCount, 0)
        
        // Density checks
        XCTAssertEqual(report.densityReport.count, 2)
        let page1Density = report.densityReport[0]
        XCTAssertEqual(page1Density.pageNumber, 1)
        XCTAssertEqual(page1Density.textDensity, (200.0 * 40.0) / pageArea, accuracy: 0.0001)
        XCTAssertEqual(page1Density.imageDensity, 0.0)
        
        let page2Density = report.densityReport[1]
        XCTAssertEqual(page2Density.pageNumber, 2)
        XCTAssertEqual(page2Density.textDensity, (200.0 * 200.0) / pageArea, accuracy: 0.0001)
        XCTAssertEqual(page2Density.imageDensity, (200.0 * 150.0) / pageArea, accuracy: 0.0001)
        
        // Motifs checklist
        // headingRule is present (heading1 has accentRule edge: bottom)
        XCTAssertTrue(report.motifsChecklist["headingRule"] ?? false)
        // pullQuoteRule is present (pullQuote has accentRule edge: left)
        XCTAssertTrue(report.motifsChecklist["pullQuoteRule"] ?? false)
    }
}
