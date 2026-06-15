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
        XCTAssertEqual(project.assets[0].usage, .placed)

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
        XCTAssertEqual(project.assets[0].usage, .placed)
    }

    func testImportsFrontMatterAndImageMetadata() {
        let markdown = """
        ---
        title: 深海热泉
        subtitle: 黑烟囱里的生态系统
        author: 李四
        publisher: 科学出版社
        isbn: 978-7-115-54608-1
        series: 青少年科学阅读
        keywords: 深海，热泉, 生态系统
        ---

        # 第一章

        ![热泉口照片](vents.png "role=hero; credit=NOAA")
        """

        let project = MarkdownBookImporter(defaultAuthor: "默认作者").importDocument(markdown: markdown)

        XCTAssertEqual(project.metadata.title, "深海热泉")
        XCTAssertEqual(project.metadata.subtitle, "黑烟囱里的生态系统")
        XCTAssertEqual(project.metadata.author, "李四")
        XCTAssertEqual(project.metadata.publisher, "科学出版社")
        XCTAssertEqual(project.metadata.isbn, "978-7-115-54608-1")
        XCTAssertEqual(project.metadata.series, "青少年科学阅读")
        XCTAssertEqual(project.metadata.keywords, ["深海", "热泉", "生态系统"])
        XCTAssertEqual(project.assets[0].role, .hero)
        XCTAssertEqual(project.assets[0].credit, "NOAA")
        XCTAssertEqual(project.assets[0].caption, "热泉口照片")
    }

    func testImageSpanWideActsAsHeroPlacementHint() {
        let markdown = """
        # 细胞里的城市

        ![跨页开场图](opening.png "span=wide; credit=layoutD")
        """

        let project = MarkdownBookImporter().importDocument(markdown: markdown)

        XCTAssertEqual(project.assets[0].role, .hero)
        XCTAssertEqual(project.assets[0].credit, "layoutD")
    }

    func testImportsPageSetupFromFrontMatter() {
        let markdown = """
        ---
        title: 单栏科普册
        columns: 1
        page: 170mm x 240mm
        ---

        # 第一章

        正文。
        """

        let project = MarkdownBookImporter().importDocument(markdown: markdown)

        XCTAssertEqual(project.pageSetup.columns, 1)
        XCTAssertEqual(project.pageSetup.pageSize.label, "170mm x 240mm")
        XCTAssertEqual(project.pageSetup.pageSize.width, 170 / 25.4 * 72, accuracy: 0.01)
        XCTAssertEqual(project.pageSetup.pageSize.height, 240 / 25.4 * 72, accuracy: 0.01)
    }

    func testImportsMarginsGutterAndBaselineFromFrontMatter() {
        let markdown = """
        ---
        title: 版心设置
        margins: 20mm 18mm 24mm 22mm
        gutter_mm: 7
        baseline_grid_pt: 13
        ---

        # 第一章

        正文。
        """

        let project = MarkdownBookImporter().importDocument(markdown: markdown)

        XCTAssertEqual(project.pageSetup.margins.top, 20 / 25.4 * 72, accuracy: 0.01)
        XCTAssertEqual(project.pageSetup.margins.right, 18 / 25.4 * 72, accuracy: 0.01)
        XCTAssertEqual(project.pageSetup.margins.bottom, 24 / 25.4 * 72, accuracy: 0.01)
        XCTAssertEqual(project.pageSetup.margins.left, 22 / 25.4 * 72, accuracy: 0.01)
        XCTAssertEqual(project.pageSetup.gutter, 7 / 25.4 * 72, accuracy: 0.01)
        XCTAssertEqual(project.pageSetup.baselineGrid, 13)
    }

    func testImportsAdmonitionQuotesAsScienceCallouts() {
        let markdown = """
        # 细胞里的城市

        > [!NOTE] 线粒体
        > 它负责把营养物质转化成细胞能直接使用的能量。

        > 普通引文仍然保持 quote 类型。
        """

        let project = MarkdownBookImporter().importDocument(markdown: markdown)
        let paragraphs = project.sections[0].stories[0].paragraphs

        XCTAssertTrue(paragraphs.contains {
            $0.kind == .callout
                && $0.styleId == StyleID.callout.rawValue
                && $0.text == "知识点：线粒体 它负责把营养物质转化成细胞能直接使用的能量。"
        })
        XCTAssertTrue(paragraphs.contains {
            $0.kind == .quote && $0.text == "普通引文仍然保持 quote 类型。"
        })
    }

    func testIgnoresDraftSeparatorsAndComments() {
        let project = MarkdownBookImporter().importDocument(
            markdown: """
            # 草稿清理

            正文前半段。

            ---

            <!-- TODO: 这里后续补图 -->

            正文后半段。
            """
        )

        let bodyTexts = project.sections[0].stories[0].paragraphs
            .filter { $0.kind == .body }
            .map(\.text)

        XCTAssertEqual(bodyTexts, ["正文前半段。", "正文后半段。"])
    }

    func testImportsSimpleMarkdownTables() {
        let project = MarkdownBookImporter().importDocument(
            markdown: """
            # 表格测试

            | 指标 | 数值 |
            | --- | ---: |
            | 细胞数量 | 约 37 万亿 |
            | 平均直径 | 10 微米 |
            """
        )

        let table = project.sections[0].stories[0].paragraphs.first { $0.kind == .table }

        XCTAssertEqual(table?.styleId, StyleID.body.rawValue)
        XCTAssertEqual(table?.text, "指标    数值\n细胞数量    约 37 万亿\n平均直径    10 微米")
    }
}
