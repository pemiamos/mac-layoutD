import Foundation
import LayoutDCore
import LayoutDImport
import XCTest

final class DOCXBookImporterTests: XCTestCase {
    func testImportsRealOOXMLParagraphsRunsListsAndTables() throws {
        let documentXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
          <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>第一章</w:t></w:r></w:p>
          <w:p><w:r><w:t>普通</w:t></w:r><w:r><w:rPr><w:b/></w:rPr><w:t>粗体</w:t></w:r><w:r><w:rPr><w:i/></w:rPr><w:t>斜体</w:t></w:r></w:p>
          <w:p><w:pPr><w:numPr><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>列表项</w:t></w:r></w:p>
          <w:tbl><w:tr><w:tc><w:p><w:r><w:t>名称</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>功能</w:t></w:r></w:p></w:tc></w:tr><w:tr><w:tc><w:p><w:r><w:t>线粒体</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>产能</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
        </w:body></w:document>
        """
        let stylesXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="Heading 1"/></w:style></w:styles>
        """
        let url = try makeDOCX(entries: ["word/document.xml": documentXML, "word/styles.xml": stylesXML])
        defer { try? FileManager.default.removeItem(at: url) }

        let project = try DOCXBookImporter(defaultAuthor: "测试作者").importDocument(from: url, fallbackTitle: "DOCX 测试")
        let paragraphs = try XCTUnwrap(project.sections.first?.stories.first?.paragraphs)
        XCTAssertEqual(paragraphs.map(\.kind), [.heading(level: 1), .body, .listItem, .table])
        XCTAssertEqual(paragraphs[0].text, "第一章")
        XCTAssertEqual(paragraphs[1].text, "普通粗体斜体")
        XCTAssertEqual(paragraphs[1].inlineRuns, [
            InlineRun(location: 2, length: 2, emphasis: [.bold]),
            InlineRun(location: 4, length: 2, emphasis: [.italic])
        ])
        XCTAssertEqual(paragraphs[3].tableCells, [["名称", "功能"], ["线粒体", "产能"]])
    }

    func testConsumesRoleTagsAndAppliesRoleStyles() throws {
        let xml = "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body><w:p><w:r><w:t>章名</w:t></w:r></w:p><w:p><w:r><w:t>越山脉</w:t></w:r></w:p><w:p><w:r><w:t>抽言</w:t></w:r></w:p><w:p><w:r><w:t>山高水长</w:t></w:r></w:p><w:p><w:r><w:t>可视化信息：绘图指令</w:t></w:r></w:p><w:p><w:r><w:t>正文</w:t></w:r></w:p></w:body></w:document>"
        let url = try makeDOCX(entries: ["word/document.xml": xml])
        defer { try? FileManager.default.removeItem(at: url) }
        let paragraphs = try XCTUnwrap(try DOCXBookImporter().importDocument(from: url).sections.first?.stories.first?.paragraphs)
        XCTAssertEqual(paragraphs.map(\.text), ["越山脉", "山高水长", "正文"])
        // 抽言是单段角色：只作用于紧邻的"山高水长"，其后的"正文"复位为 body（不再被污染）。
        XCTAssertEqual(paragraphs.map(\.styleId), [StyleID.heading1.rawValue, StyleID.pullQuote.rawValue, StyleID.body.rawValue])
        XCTAssertEqual(paragraphs[0].kind, .heading(level: 1))
        XCTAssertEqual(paragraphs[1].kind, .body)   // 抽言用 body kind（仅样式不同），不是标题
    }

    /// 真实书稿用斜杠合写标签（"一级标题/章名"），须按斜杠拆开识别；否则标签会漏成正文。
    func testRecognizesSlashCombinedRoleTags() throws {
        let xml = "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body><w:p><w:r><w:t>一级标题/章名</w:t></w:r></w:p><w:p><w:r><w:t>越山脉</w:t></w:r></w:p><w:p><w:r><w:t>三级标题/文章名</w:t></w:r></w:p><w:p><w:r><w:t>山·黄山</w:t></w:r></w:p><w:p><w:r><w:t>正文一段</w:t></w:r></w:p></w:body></w:document>"
        let url = try makeDOCX(entries: ["word/document.xml": xml])
        defer { try? FileManager.default.removeItem(at: url) }
        let paragraphs = try XCTUnwrap(try DOCXBookImporter().importDocument(from: url).sections.first?.stories.first?.paragraphs)
        XCTAssertEqual(paragraphs.map(\.text), ["越山脉", "山·黄山", "正文一段"])   // 标签全消费，不漏
        XCTAssertEqual(paragraphs.map(\.styleId), [StyleID.heading1.rawValue, StyleID.heading3.rawValue, StyleID.body.rawValue])
    }

    func testImportsEmbeddedImages() throws {
        let documentXML = """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing">
          <w:body>
            <w:p>
              <w:r><w:t>段落文字</w:t></w:r>
            </w:p>
            <w:p>
              <w:drawing>
                <wp:extent cx="5949315" cy="3245485"/>
                <a:blip r:embed="rId4"/>
              </w:drawing>
            </w:p>
          </w:body>
        </w:document>
        """
        let relsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image1.png"/>
        </Relationships>
        """
        // 1x1 transparent PNG data
        let pngBytes = Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
            0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x60, 0x60, 0x00,
            0x00, 0x00, 0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
            0x44, 0xAE, 0x42, 0x60, 0x82
        ])

        let url = try makeDOCXWithData(entries: [
            "word/document.xml": Data(documentXML.utf8),
            "word/_rels/document.xml.rels": Data(relsXML.utf8),
            "word/media/image1.png": pngBytes
        ])
        defer {
            try? FileManager.default.removeItem(at: url)
            let imagesDirectory = url.deletingLastPathComponent().appendingPathComponent("images")
            try? FileManager.default.removeItem(at: imagesDirectory)
        }

        let project = try DOCXBookImporter().importDocument(from: url)
        XCTAssertEqual(project.assets.count, 1)
        let asset = project.assets[0]
        XCTAssertEqual(asset.fileName, "images/image1.png")
        XCTAssertEqual(asset.pixelWidth, 1)
        XCTAssertEqual(asset.pixelHeight, 1)
        XCTAssertEqual(asset.usage, .placed)

        let paragraphs = try XCTUnwrap(project.sections.first?.stories.first?.paragraphs)
        XCTAssertEqual(paragraphs.count, 2)
        XCTAssertEqual(paragraphs[0].kind, .body)
        XCTAssertEqual(paragraphs[0].text, "段落文字")
        
        XCTAssertEqual(paragraphs[1].kind, .figure(assetId: asset.id))
        XCTAssertEqual(paragraphs[1].text, "images/image1.png")
        XCTAssertEqual(paragraphs[1].styleId, StyleID.caption.rawValue)
    }

    private func makeDOCX(entries: [String: String]) throws -> URL {
        let entriesData = Dictionary(uniqueKeysWithValues: entries.map { ($0, Data($1.utf8)) })
        return try makeDOCXWithData(entries: entriesData)
    }

    private func makeDOCXWithData(entries: [String: Data]) throws -> URL {
        var local = Data(); var central = Data(); var offset: UInt32 = 0
        for name in entries.keys.sorted() {
            let nameData = Data(name.utf8), payload = entries[name, default: Data()]
            local.appendLE(UInt32(0x04034b50)); local.appendLE(UInt16(20)); local.appendLE(UInt16(0)); local.appendLE(UInt16(0))
            local.appendLE(UInt16(0)); local.appendLE(UInt16(0)); local.appendLE(UInt32(0)); local.appendLE(UInt32(payload.count)); local.appendLE(UInt32(payload.count))
            local.appendLE(UInt16(nameData.count)); local.appendLE(UInt16(0)); local.append(nameData); local.append(payload)
            central.appendLE(UInt32(0x02014b50)); central.appendLE(UInt16(20)); central.appendLE(UInt16(20)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0))
            central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt32(0)); central.appendLE(UInt32(payload.count)); central.appendLE(UInt32(payload.count))
            central.appendLE(UInt16(nameData.count)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt32(0)); central.appendLE(offset); central.append(nameData)
            offset += UInt32(30 + nameData.count + payload.count)
        }
        let centralOffset = UInt32(local.count); local.append(central)
        local.appendLE(UInt32(0x06054b50)); local.appendLE(UInt16(0)); local.appendLE(UInt16(0)); local.appendLE(UInt16(entries.count)); local.appendLE(UInt16(entries.count)); local.appendLE(UInt32(central.count)); local.appendLE(centralOffset); local.appendLE(UInt16(0))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("layoutd-docx-\(UUID().uuidString).docx")
        try local.write(to: url)
        return url
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) { append(UInt8(value & 0xff)); append(UInt8(value >> 8)) }
    mutating func appendLE(_ value: UInt32) { appendLE(UInt16(value & 0xffff)); appendLE(UInt16(value >> 16)) }
}
