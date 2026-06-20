import LayoutDCore
import LayoutDEngine
import LayoutDExport
import Foundation
import XCTest

/// 阶段 E1：真实 BookProject → IDML 全量映射的容器级验证。
/// 「在 InDesign 中文版能否干净打开 + 版面到位」仍需人工验收。
final class IDMLExporterTests: XCTestCase {
    func testExportsValidIDMLFromSampleProject() throws {
        let project = BookProject.sample
        let document = LayoutEngine().layout(project: project)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-idml-export-\(UUID().uuidString)")
            .appendingPathExtension("idml")
        defer { try? FileManager.default.removeItem(at: url) }

        try IDMLExporter().export(document: document, project: project, to: url)

        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(size, 1024)

        let entries = try zipEntries(url)
        XCTAssertEqual(entries.first, "mimetype", "mimetype 必须是首个条目")
        for required in ["designmap.xml", "META-INF/container.xml", "Resources/Styles.xml", "Resources/Fonts.xml"] {
            XCTAssertTrue(entries.contains(required), "缺少部件：\(required)")
        }
        // 至少有一个 spread 和一个 story（样例项目非空）。
        XCTAssertTrue(entries.contains { $0.hasPrefix("Spreads/Spread_") })
        XCTAssertTrue(entries.contains { $0.hasPrefix("Stories/Story_") })

        // designmap 引用的所有 idPkg src 都应在包里（无悬挂引用）。
        let designmap = try entry(url, "designmap.xml")
        let srcs = matches(in: designmap, pattern: "src=\"([^\"]+)\"")
        for src in srcs {
            XCTAssertTrue(entries.contains(src), "designmap 引用了不存在的部件：\(src)")
        }

        // 段落样式与复合字体应成对出现（样例项目段落样式都带复合字体）。
        let styles = try entry(url, "Resources/Styles.xml")
        XCTAssertTrue(styles.contains("ParagraphStyle/body"))
        let fonts = try entry(url, "Resources/Fonts.xml")
        XCTAssertTrue(fonts.contains("CompositeFont Self=\"CompositeFont/CF_body\""))
    }

    func testPackagesReferencedImageAndUsesRelativeLinkURI() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-idml-links-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source-image.png")
        let contents = Data("packaged-image".utf8)
        try contents.write(to: source)

        var project = BookProject.sample
        XCTAssertFalse(project.assets.isEmpty)
        project.assets[0].fileName = "cell-diagram.png"
        project.assets[0].sourcePath = source.path
        let imageFrame = PageFrame(
            kind: .image,
            rect: Rect(x: 20, y: 20, width: 200, height: 120),
            content: .asset(project.assets[0].id)
        )
        let document = LaidOutDocument(
            projectId: project.id,
            pages: [LaidOutPage(number: 1, frames: [imageFrame])]
        )
        let output = root.appendingPathComponent("book.idml")

        try IDMLExporter().export(document: document, project: project, to: output)

        let packagedImage = root.appendingPathComponent("Links/cell-diagram.png")
        XCTAssertEqual(try Data(contentsOf: packagedImage), contents)
        let spreads = try zipEntries(output).filter { $0.hasPrefix("Spreads/Spread_") }
        let spreadXML = try spreads.map { try entry(output, $0) }.joined(separator: "\n")
        XCTAssertTrue(spreadXML.contains("LinkResourceURI=\"file:Links/cell-diagram.png\""))
        XCTAssertFalse(spreadXML.contains(source.path))
    }

    // MARK: - helpers

    private func zipEntries(_ url: URL) throws -> [String] {
        try run("/usr/bin/unzip", ["-Z1", url.path]).split(separator: "\n").map(String.init)
    }
    private func entry(_ url: URL, _ name: String) throws -> String {
        try run("/usr/bin/unzip", ["-p", url.path, name])
    }
    private func matches(in s: String, pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1))
        }
    }
    private func run(_ launchPath: String, _ args: [String]) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        try proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
