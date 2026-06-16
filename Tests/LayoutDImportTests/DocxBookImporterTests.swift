import XCTest
import AppKit
@testable import LayoutDCore
@testable import LayoutDImport

final class DocxBookImporterTests: XCTestCase {
    func testDocxBookImporterImportsDocument() throws {
        // 1. Create a mock NSAttributedString without attachments (since native docx exporter doesn't support them)
        let attrString = NSMutableAttributedString()
        
        // Add Heading 1
        let heading1Font = NSFont.boldSystemFont(ofSize: 20)
        let heading1Attr: [NSAttributedString.Key: Any] = [
            .font: heading1Font
        ]
        attrString.append(NSAttributedString(string: "第一章 重新理解图文排版\n", attributes: heading1Attr))
        
        let bodyFont = NSFont.systemFont(ofSize: 11)
        let bodyAttr: [NSAttributedString.Key: Any] = [
            .font: bodyFont
        ]
        attrString.append(NSAttributedString(string: "这是第一章的引言或正文内容。\n", attributes: bodyAttr))
        
        // Add Heading 2
        let heading2Font = NSFont.boldSystemFont(ofSize: 15)
        let heading2Attr: [NSAttributedString.Key: Any] = [
            .font: heading2Font
        ]
        attrString.append(NSAttributedString(string: "图像不只是正文的附件\n", attributes: heading2Attr))
        
        // Add Body Text
        attrString.append(NSAttributedString(string: "中文科普图书的价值，经常来自文字和图片的协作。\n", attributes: bodyAttr))
        
        // 2. Export to a temporary DOCX file
        let docxData = try attrString.data(
            from: NSRange(location: 0, length: attrString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
        )
        
        let tempDir = FileManager.default.temporaryDirectory
        let docxURL = tempDir.appendingPathComponent("test_import.docx")
        try docxData.write(to: docxURL)
        
        defer {
            try? FileManager.default.removeItem(at: docxURL)
        }
        
        // 3. Import the document
        let importer = DocxBookImporter()
        let project = try importer.importDocument(docxURL: docxURL)
        
        // 4. Assert
        XCTAssertEqual(project.metadata.title, "test_import")
        XCTAssertEqual(project.sections.count, 1)
        XCTAssertEqual(project.sections[0].title, "第一章 重新理解图文排版")
        
        let stories = project.sections[0].stories
        XCTAssertEqual(stories.count, 2)
        XCTAssertEqual(stories[0].title, "正文")
        XCTAssertEqual(stories[1].title, "图像不只是正文的附件")
        
        let paragraphs = stories[1].paragraphs
        XCTAssertTrue(paragraphs.contains { $0.text == "中文科普图书的价值，经常来自文字和图片的协作。" })
    }
    
    func testDocxBookImporterParsesAttributedStringWithAttachments() throws {
        // 1. Create a mock NSAttributedString with attachment
        let attrString = NSMutableAttributedString()
        
        let bodyFont = NSFont.systemFont(ofSize: 11)
        let bodyAttr: [NSAttributedString.Key: Any] = [
            .font: bodyFont
        ]
        attrString.append(NSAttributedString(string: "这是正文部分。\n", attributes: bodyAttr))
        
        // Add an image attachment
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.red.set()
        NSRect(x: 0, y: 0, width: 10, height: 10).fill()
        image.unlockFocus()
        
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Failed to create mock image data")
            return
        }
        let fileWrapper = FileWrapper(regularFileWithContents: pngData)
        fileWrapper.preferredFilename = "test_image.png"
        let attachment = NSTextAttachment(fileWrapper: fileWrapper)
        attrString.append(NSAttributedString(attachment: attachment))
        attrString.append(NSAttributedString(string: "\n", attributes: bodyAttr))
        
        let tempDir = FileManager.default.temporaryDirectory
        defer {
            let assetsURL = tempDir.appendingPathComponent(".docx_assets")
            try? FileManager.default.removeItem(at: assetsURL)
        }
        
        // 2. Parse using importAttributedString
        let importer = DocxBookImporter()
        let project = importer.importAttributedString(
            attrString,
            title: "test_mem_import",
            baseDirectoryURL: tempDir
        )
        
        // 3. Assert
        XCTAssertEqual(project.metadata.title, "test_mem_import")
        XCTAssertEqual(project.sections.count, 1)
        
        let stories = project.sections[0].stories
        XCTAssertEqual(stories.count, 1)
        XCTAssertEqual(stories[0].title, "正文")
        
        let paragraphs = stories[0].paragraphs
        XCTAssertTrue(paragraphs.contains { $0.text == "这是正文部分。" })
        XCTAssertTrue(paragraphs.contains {
            if case .figure = $0.kind { return true }
            return false
        })
        
        XCTAssertEqual(project.assets.count, 1)
        XCTAssertTrue(project.assets[0].fileName.hasPrefix(".docx_assets/"))
        
        let expectedWidth = bitmap.pixelsWide
        let expectedHeight = bitmap.pixelsHigh
        XCTAssertEqual(project.assets[0].pixelWidth, expectedWidth)
        XCTAssertEqual(project.assets[0].pixelHeight, expectedHeight)
    }
}
