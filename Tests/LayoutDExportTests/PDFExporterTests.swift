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

    func testPDFExportWithBleedAndCropMarks() throws {
        let project = BookProject.sample
        let document = LayoutEngine().layout(project: project)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-pdf-crop-test-\(UUID().uuidString)")
            .appendingPathExtension("pdf")

        defer {
            try? FileManager.default.removeItem(at: url)
        }

        try PDFExporter().export(
            document: document,
            project: project,
            to: url,
            pageRange: "3",
            drawCropMarks: true
        )

        let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL))
        XCTAssertEqual(pdf.numberOfPages, 1)
        
        let page = try XCTUnwrap(pdf.page(at: 1))
        let mediaBox = page.getBoxRect(.mediaBox)
        
        // Size should be expanded by 3mm bleed (8.5 pt) + 20 pt crop margin on each side (total 28.5 pt per side, 57 pt total)
        let expectedWidth = project.pageSetup.pageSize.width + 2 * (8.5039 + 20.0)
        let expectedHeight = project.pageSetup.pageSize.height + 2 * (8.5039 + 20.0)
        
        XCTAssertEqual(Double(mediaBox.width), expectedWidth, accuracy: 0.1)
        XCTAssertEqual(Double(mediaBox.height), expectedHeight, accuracy: 0.1)
        
        // Also test PNG export with crop marks
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-png-crop-test-\(UUID().uuidString)")
        
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        
        let outputURLs = try PNGExporter().export(
            document: document,
            project: project,
            to: directoryURL,
            pageRange: "3",
            scale: 1.0,
            drawCropMarks: true
        )
        
        XCTAssertEqual(outputURLs.count, 1)
        let pngImage = try XCTUnwrap(NSImage(contentsOf: outputURLs[0]))
        let pngBitmap = try XCTUnwrap(pngImage.representations.compactMap { $0 as? NSBitmapImageRep }.first)
        XCTAssertEqual(Double(pngBitmap.pixelsWide), expectedWidth, accuracy: 1.0)
        XCTAssertEqual(Double(pngBitmap.pixelsHigh), expectedHeight, accuracy: 1.0)
    }

    func testResourceBundlePackager() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-packager-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create dummy image file
        let dummyImagePath = tempDir.appendingPathComponent("dummy.png").path
        let dummyData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        try dummyData.write(to: URL(fileURLWithPath: dummyImagePath))

        let project = BookProject(
            metadata: ProjectMetadata(title: "打包测试", author: "测试作者", publisher: "测试出版社", isbn: "123456"),
            sections: [
                BookSection(title: "第一章", stories: [
                    Story(title: "故事一", paragraphs: [
                        Paragraph(kind: .body, text: "正文内容", styleId: StyleID.body.rawValue)
                    ])
                ])
            ],
            assets: [
                Asset(
                    fileName: "dummy.png",
                    sourcePath: dummyImagePath,
                    role: .photo,
                    pixelWidth: 100,
                    pixelHeight: 100,
                    dpi: 72
                )
            ]
        )

        let packageZipURL = tempDir.appendingPathComponent("project.layoutd-pack")

        // Package it
        let packager = ResourceBundlePackager()
        try packager.package(project: project, to: packageZipURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: packageZipURL.path))

        // Unzip it
        let unzipDir = tempDir.appendingPathComponent("unzipped")
        try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", packageZipURL.path, "-d", unzipDir.path]
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)

        // Verify structure
        let projectJsonURL = unzipDir.appendingPathComponent("project.layoutd")
        let manifestJsonURL = unzipDir.appendingPathComponent("manifest.json")
        let assetCopyURL = unzipDir.appendingPathComponent("assets").appendingPathComponent("dummy.png")

        XCTAssertTrue(FileManager.default.fileExists(atPath: projectJsonURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifestJsonURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: assetCopyURL.path))

        // Verify Project JSON content
        let unpackedProjectData = try Data(contentsOf: projectJsonURL)
        let unpackedProject = try ProjectFile.decode(unpackedProjectData)
        XCTAssertEqual(unpackedProject.metadata.title, "打包测试")
        XCTAssertEqual(unpackedProject.assets.count, 1)
        XCTAssertEqual(unpackedProject.assets[0].sourcePath, "assets/dummy.png")

        // Verify Manifest JSON content
        let manifestData = try Data(contentsOf: manifestJsonURL)
        let manifestDecoder = JSONDecoder()
        manifestDecoder.dateDecodingStrategy = .iso8601
        let manifest = try manifestDecoder.decode(DistributionManifest.self, from: manifestData)
        XCTAssertEqual(manifest.title, "打包测试")
        XCTAssertEqual(manifest.author, "测试作者")
        XCTAssertEqual(manifest.publisher, "测试出版社")
        XCTAssertEqual(manifest.isbn, "123456")
        XCTAssertEqual(manifest.sectionCount, 1)
        XCTAssertEqual(manifest.assetCount, 1)
        XCTAssertEqual(manifest.assets.count, 1)
        XCTAssertEqual(manifest.assets[0].fileName, "dummy.png")
    }

    func testPDFXExportMetadataAndBoxes() throws {
        let project = BookProject.sample
        let document = LayoutEngine().layout(project: project)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-pdfx-test-\(UUID().uuidString)")
            .appendingPathExtension("pdf")

        defer {
            try? FileManager.default.removeItem(at: url)
        }

        // Export as PDF/X-1a
        try PDFExporter().export(
            document: document,
            project: project,
            to: url,
            pageRange: "1",
            drawCropMarks: true,
            pdfxVersion: .pdfx1a
        )

        let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL))
        XCTAssertEqual(pdf.numberOfPages, 1)

        let page = try XCTUnwrap(pdf.page(at: 1))
        
        // Check TrimBox and BleedBox
        let mediaBox = page.getBoxRect(.mediaBox)
        let trimBox = page.getBoxRect(.trimBox)
        let bleedBox = page.getBoxRect(.bleedBox)
        let cropBox = page.getBoxRect(.cropBox)

        // TrimBox should match pageSize: width and height
        XCTAssertEqual(Double(trimBox.width), project.pageSetup.pageSize.width, accuracy: 0.1)
        XCTAssertEqual(Double(trimBox.height), project.pageSetup.pageSize.height, accuracy: 0.1)

        // BleedBox should match trimBox + 3mm bleed (8.5 pt) on each side
        XCTAssertEqual(Double(bleedBox.width), project.pageSetup.pageSize.width + 2 * 8.5039, accuracy: 0.1)
        XCTAssertEqual(Double(bleedBox.height), project.pageSetup.pageSize.height + 2 * 8.5039, accuracy: 0.1)

        // MediaBox and CropBox should match expanded dimensions including crop margins (20pt)
        let expectedMediaWidth = project.pageSetup.pageSize.width + 2 * (8.5039 + 20.0)
        let expectedMediaHeight = project.pageSetup.pageSize.height + 2 * (8.5039 + 20.0)
        XCTAssertEqual(Double(mediaBox.width), expectedMediaWidth, accuracy: 0.1)
        XCTAssertEqual(Double(mediaBox.height), expectedMediaHeight, accuracy: 0.1)
        XCTAssertEqual(Double(cropBox.width), expectedMediaWidth, accuracy: 0.1)
        XCTAssertEqual(Double(cropBox.height), expectedMediaHeight, accuracy: 0.1)

        // Verify XMP metadata stream inside catalog for PDF/X compliance tags
        let catalog = try XCTUnwrap(pdf.catalog)
        var metadataStream: CGPDFStreamRef? = nil
        XCTAssertTrue(CGPDFDictionaryGetStream(catalog, "Metadata", &metadataStream))
        if let stream = metadataStream {
            var format: CGPDFDataFormat = .raw
            if let dataRef = CGPDFStreamCopyData(stream, &format) {
                let xmlData = dataRef as Data
                if let xmlString = String(data: xmlData, encoding: .utf8) {
                    XCTAssertTrue(xmlString.contains("GTS_PDFXVersion"))
                    XCTAssertTrue(xmlString.contains("PDF/X-1:2001"))
                    XCTAssertTrue(xmlString.contains("GTS_PDFXConformance"))
                    XCTAssertTrue(xmlString.contains("PDF/X-1a:2001"))
                } else {
                    XCTFail("XMP metadata stream could not be converted to String")
                }
            } else {
                XCTFail("Could not copy XMP metadata stream data")
            }
        }

        // Verify OutputIntents in Document Catalog
        var outputIntents: CGPDFArrayRef?
        XCTAssertTrue(CGPDFDictionaryGetArray(catalog, "OutputIntents", &outputIntents))
        XCTAssertGreaterThan(CGPDFArrayGetCount(outputIntents!), 0)
    }
}
