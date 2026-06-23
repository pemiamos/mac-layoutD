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

    private func makeDOCX(entries: [String: String]) throws -> URL {
        var local = Data(); var central = Data(); var offset: UInt32 = 0
        for name in entries.keys.sorted() {
            let nameData = Data(name.utf8), payload = Data(entries[name, default: ""].utf8)
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
