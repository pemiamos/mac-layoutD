import LayoutDCore
import LayoutDImport
import XCTest

final class MarkdownBookImporterTests: XCTestCase {
    func testImportsHeadingsBodyAndFigures() {
        let knownAsset = Asset(
            fileName: "images/cell-diagram.png",
            role: .diagram,
            pixelWidth: 1800,
            pixelHeight: 1200,
            dpi: 300
        )
        let markdown = """
        # 细胞里的城市

        细胞不是一袋随机漂浮的液体，而是一座有边界、有交通、有能量系统的城市。

        ![线粒体像城市里的发电站](images/cell-diagram.png)

        ## 能量从哪里来

        > 科普页面需要让图和文字互相解释。

        - 线粒体负责能量转换
        - 细胞膜负责边界管理
        """

        let project = MarkdownBookImporter(defaultAuthor: "测试作者").importDocument(
            markdown: markdown,
            assetCatalog: AssetCatalog(assets: [knownAsset])
        )

        XCTAssertEqual(project.metadata.title, "细胞里的城市")
        XCTAssertEqual(project.metadata.author, "测试作者")
        XCTAssertEqual(project.sections.count, 1)
        XCTAssertEqual(project.assets.count, 1)
        XCTAssertEqual(project.assets[0].caption, "线粒体像城市里的发电站")
        XCTAssertNil(project.assets[0].sourcePath)

        let paragraphs = project.sections[0].stories[0].paragraphs
        XCTAssertFalse(paragraphs.contains { $0.kind == .heading(level: 1) && $0.text == "细胞里的城市" })
        XCTAssertTrue(paragraphs.contains { $0.kind == .figure(assetId: knownAsset.id) })
        XCTAssertTrue(paragraphs.contains { $0.kind == .heading(level: 2) && $0.text == "能量从哪里来" })
        XCTAssertTrue(paragraphs.contains { $0.kind == .quote })
        XCTAssertEqual(paragraphs.filter { $0.kind == .listItem }.count, 2)
    }

    func testCreatesPlaceholderAssetForUnscannedImageReference() {
        let project = MarkdownBookImporter().importDocument(
            markdown: """
            # 火山如何喷发

            ![岩浆通道示意图](volcano.png)
            """
        )

        XCTAssertEqual(project.assets.count, 1)
        XCTAssertEqual(project.assets[0].fileName, "volcano.png")
        XCTAssertEqual(project.assets[0].caption, "岩浆通道示意图")
        XCTAssertEqual(project.assets[0].pixelWidth, 0)
    }

    func testImportsFrontMatterAndImageMetadata() {
        let markdown = """
        ---
        title: 深海热泉
        subtitle: 黑烟囱里的生态系统
        author: 李四
        ---

        # 第一章

        ![热泉口照片](vents.png "role=hero; credit=NOAA")
        """

        let project = MarkdownBookImporter(defaultAuthor: "默认作者").importDocument(markdown: markdown)

        XCTAssertEqual(project.metadata.title, "深海热泉")
        XCTAssertEqual(project.metadata.subtitle, "黑烟囱里的生态系统")
        XCTAssertEqual(project.metadata.author, "李四")
        XCTAssertEqual(project.assets[0].role, .hero)
        XCTAssertEqual(project.assets[0].credit, "NOAA")
        XCTAssertEqual(project.assets[0].caption, "热泉口照片")
    }
}
