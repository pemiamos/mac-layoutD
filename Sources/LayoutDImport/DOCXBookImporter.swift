import Compression
import Foundation
import LayoutDCore

/// Minimal, dependency-free OOXML importer. It deliberately handles the document
/// structures layoutD can model today (paragraphs, basic emphasis, lists and
/// tables) and leaves drawings/media to a later asset-import pass.
public struct DOCXBookImporter {
    public enum ImportError: LocalizedError {
        case missingDocumentXML
        case malformedDocument
        case unsupportedArchive(String)

        public var errorDescription: String? {
            switch self {
            case .missingDocumentXML: return "DOCX 缺少 word/document.xml"
            case .malformedDocument: return "DOCX 正文 XML 无法解析"
            case .unsupportedArchive(let reason): return "DOCX 压缩包不受支持：\(reason)"
            }
        }
    }

    public var defaultAuthor: String

    public init(defaultAuthor: String = "layoutD Importer") {
        self.defaultAuthor = defaultAuthor
    }

    public func importDocument(from url: URL, fallbackTitle: String? = nil) throws -> BookProject {
        let archive = try OOXMLArchive(data: Data(contentsOf: url))
        guard let documentXML = try archive.string(named: "word/document.xml") else {
            throw ImportError.missingDocumentXML
        }
        let styleNames = (try? archive.string(named: "word/styles.xml"))
            .map(DOCXStyles.init(xml:))?.paragraphNames ?? [:]
        let parsed = DOCXDocumentParser(styleNames: styleNames).parse(xml: documentXML)
        guard !parsed.failed else { throw ImportError.malformedDocument }

        let paragraphs = parsed.blocks.compactMap { block -> Paragraph? in
            switch block {
            case .paragraph(let value):
                guard !value.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return Paragraph(kind: kind(for: value, styleNames: styleNames), text: value.text,
                                 styleId: styleID(for: value, styleNames: styleNames), inlineRuns: inlineRuns(for: value))
            case .table(let rows):
                let cells = rows.filter { !$0.isEmpty }
                guard !cells.isEmpty else { return nil }
                return Paragraph(kind: .table, text: cells.map { $0.joined(separator: "    ") }.joined(separator: "\n"),
                                 styleId: StyleID.body.rawValue, tableCells: cells)
            }
        }
        let title = fallbackTitle ?? url.deletingPathExtension().lastPathComponent
        return BookProject(
            metadata: ProjectMetadata(title: title.isEmpty ? "未命名 DOCX 书稿" : title, author: defaultAuthor),
            sections: [BookSection(title: title.isEmpty ? "正文" : title, stories: [Story(title: "正文", paragraphs: paragraphs)])]
        )
    }

    private func kind(for paragraph: DOCXParagraph, styleNames: [String: String]) -> ParagraphKind {
        if paragraph.isList { return .listItem }
        let style = (paragraph.styleID.flatMap { styleNames[$0] } ?? paragraph.styleID ?? "").lowercased()
        if let level = headingLevel(in: style) { return .heading(level: level) }
        if style.contains("quote") || style.contains("引用") { return .quote }
        return .body
    }

    private func styleID(for paragraph: DOCXParagraph, styleNames: [String: String]) -> String {
        switch kind(for: paragraph, styleNames: styleNames) {
        case .heading(let level): return level <= 1 ? StyleID.heading1.rawValue : StyleID.heading2.rawValue
        case .quote: return StyleID.body.rawValue
        case .listItem: return StyleID.body.rawValue
        default: return StyleID.body.rawValue
        }
    }

    private func headingLevel(in style: String) -> Int? {
        let normalized = style.replacingOccurrences(of: " ", with: "")
        for level in 1...6 where normalized.contains("heading\(level)") || normalized.contains("标题\(level)") {
            return level
        }
        return nil
    }

    private func inlineRuns(for paragraph: DOCXParagraph) -> [InlineRun]? {
        var offset = 0
        var runs: [InlineRun] = []
        for run in paragraph.runs {
            let length = run.text.count
            defer { offset += length }
            guard length > 0, !run.emphasis.isEmpty else { continue }
            if var previous = runs.last, previous.location + previous.length == offset, previous.emphasis == run.emphasis {
                previous.length += length
                runs[runs.count - 1] = previous
            } else {
                runs.append(InlineRun(location: offset, length: length, emphasis: run.emphasis))
            }
        }
        return runs.isEmpty ? nil : runs
    }
}

private struct DOCXRun { var text = ""; var emphasis = Set<InlineEmphasis>() }
private struct DOCXParagraph { var text = ""; var runs: [DOCXRun] = []; var styleID: String?; var isList = false }
private enum DOCXBlock { case paragraph(DOCXParagraph), table([[String]]) }
private struct DOCXParseResult { var blocks: [DOCXBlock] = []; var failed = false }

private final class DOCXDocumentParser: NSObject, XMLParserDelegate {
    private let styleNames: [String: String]
    private var result = DOCXParseResult()
    private var paragraph: DOCXParagraph?
    private var run: DOCXRun?
    private var tableRows: [[String]] = []
    private var tableRow: [String] = []
    private var tableCellParagraphs: [String] = []
    private var tableDepth = 0
    private var textTarget: TextTarget?
    private enum TextTarget { case run }

    init(styleNames: [String: String]) { self.styleNames = styleNames }

    func parse(xml: String) -> DOCXParseResult {
        guard let data = xml.data(using: .utf8) else { result.failed = true; return result }
        let parser = XMLParser(data: data)
        parser.delegate = self
        if !parser.parse() { result.failed = true }
        return result
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        switch localName(qName ?? elementName) {
        case "tbl": tableDepth += 1; tableRows = []
        case "tr" where tableDepth > 0: tableRow = []
        case "tc" where tableDepth > 0: tableCellParagraphs = []
        case "p": paragraph = DOCXParagraph()
        case "pStyle": paragraph?.styleID = attributeDict["w:val"] ?? attributeDict["val"]
        case "numPr": paragraph?.isList = true
        case "r": run = DOCXRun()
        case "b": run?.emphasis.insert(.bold)
        case "i": run?.emphasis.insert(.italic)
        case "t": textTarget = .run
        case "tab": run?.text.append("\t")
        case "br", "cr": run?.text.append("\n")
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if textTarget == .run { run?.text.append(string) }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch localName(qName ?? elementName) {
        case "t": textTarget = nil
        case "r":
            if let run { paragraph?.runs.append(run); paragraph?.text += run.text }
            run = nil
        case "p":
            if let paragraph {
                if tableDepth > 0 { tableCellParagraphs.append(paragraph.text) }
                else { result.blocks.append(.paragraph(paragraph)) }
            }
            self.paragraph = nil
        case "tc" where tableDepth > 0: tableRow.append(tableCellParagraphs.joined(separator: "\n"))
        case "tr" where tableDepth > 0: tableRows.append(tableRow)
        case "tbl" where tableDepth > 0:
            result.blocks.append(.table(tableRows)); tableDepth -= 1
        default: break
        }
    }

    private func localName(_ name: String) -> String { name.split(separator: ":").last.map(String.init) ?? name }
}

private final class DOCXStyles: NSObject, XMLParserDelegate {
    var paragraphNames: [String: String] = [:]
    private var styleID: String?
    private var isParagraphStyle = false

    convenience init(xml: String) { self.init(); parse(xml: xml) }
    private func parse(xml: String) {
        guard let data = xml.data(using: .utf8) else { return }
        let parser = XMLParser(data: data); parser.delegate = self; parser.parse()
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        let name = (qName ?? elementName).split(separator: ":").last.map(String.init) ?? elementName
        if name == "style" { isParagraphStyle = (attributeDict["w:type"] ?? attributeDict["type"]) == "paragraph"; styleID = attributeDict["w:styleId"] ?? attributeDict["styleId"] }
        if name == "name", isParagraphStyle, let styleID, let value = attributeDict["w:val"] ?? attributeDict["val"] { paragraphNames[styleID] = value }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = (qName ?? elementName).split(separator: ":").last.map(String.init) ?? elementName
        if name == "style" { styleID = nil; isParagraphStyle = false }
    }
}

private struct OOXMLArchive {
    private let data: Data
    init(data: Data) throws {
        guard data.count >= 22 else { throw DOCXBookImporter.ImportError.unsupportedArchive("文件不是 ZIP") }
        self.data = data
    }

    func string(named name: String) throws -> String? {
        guard let entry = try entry(named: name) else { return nil }
        let bytes = try data(for: entry)
        return String(data: bytes, encoding: .utf8)
    }

    private func entry(named target: String) throws -> (method: UInt16, compressed: Int, uncompressed: Int, offset: Int)? {
        guard let end = endOfCentralDirectory() else { throw DOCXBookImporter.ImportError.unsupportedArchive("缺少 central directory") }
        let count = Int(u16(end + 10)), start = Int(u32(end + 16))
        var cursor = start
        for _ in 0..<count {
            guard u32(cursor) == 0x02014b50 else { throw DOCXBookImporter.ImportError.unsupportedArchive("central directory 损坏") }
            let method = u16(cursor + 10), compressed = Int(u32(cursor + 20)), uncompressed = Int(u32(cursor + 24))
            let nameLength = Int(u16(cursor + 28)), extraLength = Int(u16(cursor + 30)), commentLength = Int(u16(cursor + 32))
            let offset = Int(u32(cursor + 42))
            let name = String(data: data.subdata(in: (cursor + 46)..<(cursor + 46 + nameLength)), encoding: .utf8)
            if name == target { return (method, compressed, uncompressed, offset) }
            cursor += 46 + nameLength + extraLength + commentLength
        }
        return nil
    }

    private func data(for entry: (method: UInt16, compressed: Int, uncompressed: Int, offset: Int)) throws -> Data {
        guard u32(entry.offset) == 0x04034b50 else { throw DOCXBookImporter.ImportError.unsupportedArchive("local header 损坏") }
        let nameLength = Int(u16(entry.offset + 26)), extraLength = Int(u16(entry.offset + 28))
        let start = entry.offset + 30 + nameLength + extraLength
        let payload = data.subdata(in: start..<(start + entry.compressed))
        switch entry.method {
        case 0: return payload
        case 8: return try inflate(payload, size: entry.uncompressed)
        default: throw DOCXBookImporter.ImportError.unsupportedArchive("不支持的压缩方法 \(entry.method)")
        }
    }

    private func inflate(_ input: Data, size: Int) throws -> Data {
        var output = Data(count: max(size, 1))
        let capacity = output.count
        let count = output.withUnsafeMutableBytes { out in input.withUnsafeBytes { source in
            compression_decode_buffer(out.bindMemory(to: UInt8.self).baseAddress!, capacity,
                                      source.bindMemory(to: UInt8.self).baseAddress!, input.count,
                                      nil, COMPRESSION_ZLIB)
        }}
        guard count == size else { throw DOCXBookImporter.ImportError.unsupportedArchive("deflate 解压失败") }
        output.count = count
        return output
    }

    private func endOfCentralDirectory() -> Int? {
        let first = max(0, data.count - 65_557)
        guard data.count >= 4 else { return nil }
        return stride(from: data.count - 4, through: first, by: -1).first { u32($0) == 0x06054b50 }
    }
    private func u16(_ offset: Int) -> UInt16 { UInt16(data[offset]) | UInt16(data[offset + 1]) << 8 }
    private func u32(_ offset: Int) -> UInt32 { UInt32(u16(offset)) | UInt32(u16(offset + 2)) << 16 }
}
