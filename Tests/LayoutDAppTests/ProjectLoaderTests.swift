import LayoutDCore
@testable import LayoutDApp
import XCTest

final class ProjectLoaderTests: XCTestCase {
    func testChapterPackageLoadsRootManuscriptFirst() throws {
        let packageURL = try makeTemporaryPackage()
        defer { try? FileManager.default.removeItem(at: packageURL) }

        try """
        ---
        title: 根目录书稿
        author: layoutD
        ---

        # 根目录章节

        根目录内容。
        """.write(to: packageURL.appendingPathComponent("manuscript.md"), atomically: true, encoding: .utf8)

        let chaptersURL = packageURL.appendingPathComponent("chapters")
        try FileManager.default.createDirectory(at: chaptersURL, withIntermediateDirectories: true)
        try """
        # 子目录章节

        子目录内容不应被导入。
        """.write(to: chaptersURL.appendingPathComponent("01.md"), atomically: true, encoding: .utf8)

        let project = try ProjectLoader().loadProject(inputURL: packageURL)

        XCTAssertEqual(project.metadata.title, "根目录书稿")
        XCTAssertEqual(project.sections.map(\.title), ["根目录章节"])
        XCTAssertFalse(project.sections.contains { $0.title == "子目录章节" })
    }

    func testChapterPackageLoadsChapterFilesInFilenameOrder() throws {
        let packageURL = try makeTemporaryPackage()
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let chaptersURL = packageURL.appendingPathComponent("chapters")
        try FileManager.default.createDirectory(at: chaptersURL, withIntermediateDirectories: true)
        try """
        # 第二章

        第二段。
        """.write(to: chaptersURL.appendingPathComponent("02-body.md"), atomically: true, encoding: .utf8)
        try """
        ---
        title: 多文件章节包
        author: layoutD
        ---

        # 第一章

        第一段。
        """.write(to: chaptersURL.appendingPathComponent("01-intro.md"), atomically: true, encoding: .utf8)

        let project = try ProjectLoader().loadProject(inputURL: packageURL)

        XCTAssertEqual(project.metadata.title, "多文件章节包")
        XCTAssertEqual(project.sections.map(\.title), ["第一章", "第二章"])
        XCTAssertEqual(project.sections.first?.stories.first?.paragraphs.first(where: { $0.kind == .body })?.text, "第一段。")
        XCTAssertEqual(project.sections.last?.stories.first?.paragraphs.first(where: { $0.kind == .body })?.text, "第二段。")
    }

    func testChapterPackageReportsMissingManuscript() throws {
        let packageURL = try makeTemporaryPackage()
        defer { try? FileManager.default.removeItem(at: packageURL) }

        XCTAssertThrowsError(try ProjectLoader().loadProject(inputURL: packageURL)) { error in
            XCTAssertTrue(error.localizedDescription.contains("章节包缺少根目录"))
            XCTAssertTrue(error.localizedDescription.contains("chapters/*.md"))
        }
    }

    func testChapterPackageLoadsExtraConfigs() throws {
        let packageURL = try makeTemporaryPackage()
        defer { try? FileManager.default.removeItem(at: packageURL) }

        // Write manuscript
        try """
        # 第一章
        内容。
        """.write(to: packageURL.appendingPathComponent("manuscript.md"), atomically: true, encoding: .utf8)

        // Write metadata.json
        let metadata = ProjectMetadata(
            title: "配置加载标题",
            subtitle: "配置副标题",
            author: "测试作者",
            publisher: "测试出版社",
            isbn: "9787115546081",
            series: "丛书名",
            keywords: ["关键字1", "关键字2"]
        )
        let metadataData = try JSONEncoder().encode(metadata)
        try metadataData.write(to: packageURL.appendingPathComponent("metadata.json"))

        // Write styles.json
        let styles = StyleLibrary.defaultChineseScience
        let stylesData = try JSONEncoder().encode(styles)
        try stylesData.write(to: packageURL.appendingPathComponent("styles.json"))

        // Write templates.json
        let templates = LayoutTemplateLibrary(templates: [
            SavedLayoutTemplate(name: "测试包模板", plan: LayoutPlan(target: .page(3), strategy: .balanced, blocks: []))
        ])
        let templatesData = try LayoutTemplateLibrary.encode(templates)
        try templatesData.write(to: packageURL.appendingPathComponent("templates.json"))

        let project = try ProjectLoader().loadProject(inputURL: packageURL)

        XCTAssertEqual(project.metadata.title, "配置加载标题")
        XCTAssertEqual(project.metadata.subtitle, "配置副标题")
        XCTAssertEqual(project.metadata.author, "测试作者")
        XCTAssertEqual(project.styles, styles)
        XCTAssertEqual(project.safeSavedLayoutTemplates.count, 1)
        XCTAssertEqual(project.safeSavedLayoutTemplates[0].name, "测试包模板")
    }

    func testLayoutDProjectResolvesRelativeAssetSourcePaths() throws {
        let packageURL = try makeTemporaryPackage()
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let assetsURL = packageURL.appendingPathComponent("assets")
        try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        let imageURL = assetsURL.appendingPathComponent("dummy.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageURL)

        let projectURL = packageURL.appendingPathComponent("project.layoutd")
        let project = BookProject(
            metadata: ProjectMetadata(title: "相对素材项目", author: "layoutD"),
            sections: [
                BookSection(title: "第一章", stories: [
                    Story(title: "故事", paragraphs: [
                        Paragraph(kind: .body, text: "正文。", styleId: StyleID.body.rawValue)
                    ])
                ])
            ],
            assets: [
                Asset(
                    fileName: "dummy.png",
                    sourcePath: "assets/dummy.png",
                    role: .photo,
                    pixelWidth: 100,
                    pixelHeight: 100
                )
            ]
        )
        try ProjectFile.encode(project).write(to: projectURL)

        let loaded = try ProjectLoader().loadProject(inputURL: projectURL)

        XCTAssertEqual(loaded.assets.first?.sourcePath, imageURL.standardizedFileURL.path)
    }

    private func makeTemporaryPackage() throws -> URL {
        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-project-loader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        return packageURL
    }
}
