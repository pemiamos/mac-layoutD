import LayoutDCore
import LayoutDEngine
import LayoutDExport
import AppKit
import CoreGraphics
import XCTest

final class PDFExporterTests: XCTestCase {
    func testExportsNonEmptyPDF() throws {
        let project = BookProject.sample
        let document = LayoutEngine().layout(project: project)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-export-test-\(UUID().uuidString)")
            .appendingPathExtension("pdf")

        defer {
            try? FileManager.default.removeItem(at: url)
        }

        try PDFExporter().export(document: document, project: project, to: url)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? NSNumber
        XCTAssertNotNil(fileSize)
        XCTAssertGreaterThan(fileSize?.intValue ?? 0, 1024)
    }

    func testExportsCalloutFramesToPDF() throws {
        let project = BookProject(
            metadata: ProjectMetadata(title: "知识卡片导出", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .callout, text: "知识点：ATP 是细胞内部常用的能量凭证。", styleId: StyleID.callout.rawValue)
                            ]
                        )
                    ]
                )
            ]
        )
        let document = LayoutEngine().layout(project: project)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-callout-export-test-\(UUID().uuidString)")
            .appendingPathExtension("pdf")

        defer {
            try? FileManager.default.removeItem(at: url)
        }

        XCTAssertTrue(document.pages.flatMap(\.frames).contains { $0.kind == .callout })

        try PDFExporter().export(document: document, project: project, to: url)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? NSNumber
        XCTAssertNotNil(fileSize)
        XCTAssertGreaterThan(fileSize?.intValue ?? 0, 1024)
    }

    func testExportsPDFPageRange() throws {
        let project = BookProject.sample
        let document = LayoutEngine().layout(project: project)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-pdf-range-test-\(UUID().uuidString)")
            .appendingPathExtension("pdf")

        defer {
            try? FileManager.default.removeItem(at: url)
        }

        try PDFExporter().export(
            document: document,
            project: project,
            to: url,
            pageRange: "1,3",
            drawCropMarks: true,
            drawGridGuides: true
        )

        let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL))
        XCTAssertEqual(pdf.numberOfPages, 2)
    }

    func testExportsPDFIntoMissingParentDirectory() throws {
        let project = BookProject.sample
        let document = LayoutEngine().layout(project: project)
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-pdf-nested-\(UUID().uuidString)")
            .appendingPathComponent("proof")
        let url = directoryURL.appendingPathComponent("sample.pdf")

        defer {
            try? FileManager.default.removeItem(at: directoryURL.deletingLastPathComponent())
        }

        try PDFExporter().export(document: document, project: project, to: url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testExportsPNGPagePreviews() throws {
        let project = BookProject.sample
        let document = LayoutEngine().layout(project: project)
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-png-export-test-\(UUID().uuidString)")

        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let outputURLs = try PNGExporter().export(
            document: document,
            project: project,
            to: directoryURL,
            pageRange: "1",
            scale: 1.0
        )

        XCTAssertEqual(outputURLs.count, 1)
        XCTAssertTrue(outputURLs[0].lastPathComponent.hasSuffix(".png"))

        let attributes = try FileManager.default.attributesOfItem(atPath: outputURLs[0].path)
        let fileSize = attributes[.size] as? NSNumber
        XCTAssertNotNil(fileSize)
        XCTAssertGreaterThan(fileSize?.intValue ?? 0, 1024)
    }

    func testExportsPNGPageRangeAndScale() throws {
        let project = BookProject.sample
        let document = LayoutEngine().layout(project: project)
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-png-range-test-\(UUID().uuidString)")

        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let outputURLs = try PNGExporter().export(
            document: document,
            project: project,
            to: directoryURL,
            pageRange: "1,3",
            scale: 0.5
        )

        XCTAssertEqual(outputURLs.map(\.lastPathComponent), ["page-001.png", "page-003.png"])

        let image = try XCTUnwrap(NSImage(contentsOf: outputURLs[0]))
        let bitmap = try XCTUnwrap(image.representations.compactMap { $0 as? NSBitmapImageRep }.first)
        XCTAssertEqual(bitmap.pixelsWide, Int(ceil(project.pageSetup.pageSize.width * 0.5)))
        XCTAssertEqual(bitmap.pixelsHigh, Int(ceil(project.pageSetup.pageSize.height * 0.5)))
    }
}
