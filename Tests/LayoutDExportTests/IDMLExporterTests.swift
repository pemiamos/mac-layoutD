import LayoutDCore
import LayoutDEngine
import LayoutDExport
import Foundation
import XCTest

/// 阶段 E1：真实 BookProject → IDML 全量映射的容器级验证。
/// 「在 InDesign 中文版能否干净打开 + 版面到位」仍需人工验收。
final class IDMLExporterTests: XCTestCase {
    func testExportsInlineRunsAsCharacterStyleRangesAcrossLines() throws {
        let paragraph = Paragraph(
            kind: .body,
            text: "细胞ATP着重\n斜体粗斜",
            styleId: StyleID.body.rawValue,
            inlineRuns: [
                InlineRun(location: 2, length: 3, emphasis: [.bold]),
                InlineRun(location: 5, length: 2, emphasis: [.kenten]),
                InlineRun(location: 8, length: 2, emphasis: [.italic]),
                InlineRun(location: 10, length: 2, emphasis: [.bold, .italic, .kenten])
            ]
        )
        let project = BookProject(
            metadata: ProjectMetadata(title: "行内格式", author: "layoutD"),
            sections: [BookSection(title: "正文", stories: [Story(title: "正文", paragraphs: [paragraph])])]
        )
        let frame = PageFrame(
            kind: .text,
            rect: Rect(x: 20, y: 20, width: 200, height: 100),
            styleId: StyleID.body.rawValue,
            content: .text("细胞 ATP 着重\n斜体粗斜"),
            sourceParagraphId: paragraph.id
        )
        let document = LaidOutDocument(projectId: project.id, pages: [LaidOutPage(number: 1, frames: [frame])])
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-idml-inline-\(UUID().uuidString).idml")
        defer { try? FileManager.default.removeItem(at: output) }

        try IDMLExporter().export(document: document, project: project, to: output)

        let story = try entry(output, "Stories/Story_uStory0_0.xml")
        XCTAssertTrue(story.contains("FauxBold=\"true\"><Content>ATP</Content>"), "自动插入的中西文空格不应破坏 run 对齐")
        XCTAssertTrue(story.contains("KentenKind=\"KentenSesameDot\" KentenAlignment=\"AlignKentenCenter\" KentenPosition=\"AboveRight\"><Content>着重</Content>"))
        XCTAssertTrue(story.contains("Skew=\"12\"><Content>斜体</Content>"))
        XCTAssertTrue(story.contains("FauxBold=\"true\" Skew=\"12\" KentenKind=\"KentenSesameDot\" KentenAlignment=\"AlignKentenCenter\" KentenPosition=\"AboveRight\"><Content>粗斜</Content>"))
        XCTAssertEqual(matches(in: story, pattern: "(<ParagraphStyleRange\\b)").count, 2)
    }

    func testExportsNestedKentenCombinationRunsWithoutStyleLeakage() throws {
        let paragraph = Paragraph(
            kind: .body,
            text: "一 A 二 B 三 C 四 D 五。",
            styleId: StyleID.body.rawValue,
            inlineRuns: [
                InlineRun(location: 2, length: 1, emphasis: [.bold, .kenten]),
                InlineRun(location: 6, length: 1, emphasis: [.bold, .kenten]),
                InlineRun(location: 10, length: 1, emphasis: [.italic, .kenten]),
                InlineRun(location: 14, length: 1, emphasis: [.italic, .kenten])
            ]
        )
        let project = BookProject(
            metadata: ProjectMetadata(title: "嵌套傍点", author: "layoutD"),
            sections: [BookSection(title: "正文", stories: [Story(title: "正文", paragraphs: [paragraph])])]
        )
        let frame = PageFrame(
            kind: .text,
            rect: Rect(x: 20, y: 20, width: 200, height: 100),
            styleId: StyleID.body.rawValue,
            content: .text(paragraph.text),
            sourceParagraphId: paragraph.id
        )
        let document = LaidOutDocument(projectId: project.id, pages: [LaidOutPage(number: 1, frames: [frame])])
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-idml-nested-kenten-\(UUID().uuidString).idml")
        defer { try? FileManager.default.removeItem(at: output) }

        try IDMLExporter().export(document: document, project: project, to: output)

        let story = try entry(output, "Stories/Story_uStory0_0.xml")
        XCTAssertEqual(matches(in: story, pattern: "(FauxBold=\\\"true\\\" KentenKind=\\\"KentenSesameDot\\\"[^>]*><Content>[AB]</Content>)").count, 2)
        XCTAssertEqual(matches(in: story, pattern: "(Skew=\\\"12\\\" KentenKind=\\\"KentenSesameDot\\\"[^>]*><Content>[CD]</Content>)").count, 2)
        XCTAssertFalse(story.contains("Skew=\"12\"><Content>二</Content>"))
        XCTAssertFalse(story.contains("FauxBold=\"true\"><Content>三</Content>"))
    }

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

    func testExportsComponentFillStrokeAndAccentAsPageItems() throws {
        var project = BookProject.sample
        project.styles.componentStyles = [
            ComponentStyle(
                id: "knowledgeCard",
                displayName: "知识卡片",
                frameKind: .callout,
                fillColorHex: "#E0F5ED",
                strokeColorHex: "#2D7A78",
                accentColorHex: "#E07A5F",
                strokeWidth: 0.8,
                accentWidth: 4
            )
        ]
        let frame = PageFrame(
            kind: .callout,
            rect: Rect(x: 20, y: 30, width: 200, height: 80),
            content: .text("知识卡片")
        )
        let document = LaidOutDocument(
            projectId: project.id,
            pages: [LaidOutPage(number: 1, frames: [frame])]
        )
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-idml-component-\(UUID().uuidString).idml")
        defer { try? FileManager.default.removeItem(at: output) }

        try IDMLExporter().export(document: document, project: project, to: output)

        let graphic = try entry(output, "Resources/Graphic.xml")
        for swatch in ["CE0F5ED", "C2D7A78", "CE07A5F"] {
            XCTAssertTrue(graphic.contains("Self=\"Color/\(swatch)\""), "缺少组件色板 \(swatch)")
        }
        let spreadName = try XCTUnwrap(zipEntries(output).first { $0.hasPrefix("Spreads/Spread_") })
        let spread = try entry(output, spreadName)
        XCTAssertTrue(spread.contains("<TextFrame Self=\"uTF0_0\""))
        XCTAssertTrue(spread.contains("FillColor=\"Color/CE0F5ED\""))
        XCTAssertTrue(spread.contains("StrokeColor=\"Color/C2D7A78\""))
        XCTAssertTrue(spread.contains("StrokeWeight=\"0.800\""))
        XCTAssertTrue(spread.contains("<Rectangle Self=\"uAccent0_0\""))
        XCTAssertTrue(spread.contains("FillColor=\"Color/CE07A5F\""))
        XCTAssertTrue(spread.contains("Anchor=\"-242.205 -338.505\""))
        XCTAssertTrue(spread.contains("Anchor=\"-238.205 -258.505\""), "accent 应为 4pt 宽、与组件等高")
    }

    func testFrameAppearanceOverridesComponentDefaults() throws {
        var project = BookProject.sample
        project.styles.componentStyles = ComponentStyle.defaultChineseScience
        let frame = PageFrame(
            kind: .callout,
            rect: Rect(x: 20, y: 30, width: 200, height: 80),
            content: .text("覆盖样式"),
            backgroundColorHex: "#112233",
            strokeColorHex: "#445566",
            strokeWidth: 2.25
        )
        let document = LaidOutDocument(projectId: project.id, pages: [LaidOutPage(number: 1, frames: [frame])])
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-idml-component-override-\(UUID().uuidString).idml")
        defer { try? FileManager.default.removeItem(at: output) }

        try IDMLExporter().export(document: document, project: project, to: output)

        let spreadName = try XCTUnwrap(zipEntries(output).first { $0.hasPrefix("Spreads/Spread_") })
        let spread = try entry(output, spreadName)
        XCTAssertTrue(spread.contains("FillColor=\"Color/C112233\""))
        XCTAssertTrue(spread.contains("StrokeColor=\"Color/C445566\""))
        XCTAssertTrue(spread.contains("StrokeWeight=\"2.250\""))
    }

    func testExportsChineseKinsokuTableAndBindsParagraphStyles() throws {
        let project = BookProject.sample
        let document = LayoutEngine().layout(project: project)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-idml-kinsoku-\(UUID().uuidString).idml")
        defer { try? FileManager.default.removeItem(at: output) }

        try IDMLExporter().export(document: document, project: project, to: output)

        let designmap = try entry(output, "designmap.xml")
        let tableRef = "KinsokuTable/$ID/kSimpChineseKinsokuName"
        let tables = matches(in: designmap, pattern: "(<KinsokuTable\\b[^>]*/>)")
        XCTAssertEqual(tables.count, 1)
        let table = try XCTUnwrap(tables.first)
        XCTAssertTrue(table.contains("Self=\"\(tableRef)\""))
        XCTAssertTrue(ChineseLineBreakRules.forbiddenLineStartCharacters.contains("，"))
        XCTAssertTrue(ChineseLineBreakRules.forbiddenLineEndCharacters.contains("（"))

        let styles = try entry(output, "Resources/Styles.xml")
        for style in project.styles.paragraphStyles {
            let styleID = NSRegularExpression.escapedPattern(for: style.id)
            let pattern = "(<ParagraphStyle[^>]*Self=\"ParagraphStyle/\(styleID)\"[^>]*KinsokuType=\"KinsokuPushInFirst\"[^>]*>[\\s\\S]*?<KinsokuSet type=\"enumeration\">SimplifiedChineseKinsoku</KinsokuSet>[\\s\\S]*?</ParagraphStyle>)"
            XCTAssertEqual(matches(in: styles, pattern: pattern).count, 1,
                           "段落样式 \(style.id) 未绑定 layoutD 禁则集")
        }
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
