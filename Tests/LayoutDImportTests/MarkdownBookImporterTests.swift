import LayoutDCore
import LayoutDImport
import XCTest

final class MarkdownBookImporterTests: XCTestCase {
    func testConsumesSubsequentFrontMatterAndUsesTitleAsSectionBoundary() throws {
        let project = MarkdownBookImporter().importDocument(
            markdown: """
            ---
            title: 第一章
            author: 测试作者
            ---

            # 横排内容

            第一段正文。

            ---
            title: 第二章
            layout_direction: vertical
            columns: 1
            ---

            第二段正文。
            """
        )

        XCTAssertEqual(project.metadata.title, "第一章")
        XCTAssertEqual(project.sections.map(\.title), ["横排内容", "第二章"])

        let importedText = project.sections
            .flatMap { $0.stories }
            .flatMap(\.paragraphs)
            .map(\.text)
            .joined(separator: "\n")
        XCTAssertEqual(importedText, "第一段正文。\n第二段正文。")
        XCTAssertFalse(importedText.contains("title:"))
        XCTAssertFalse(importedText.contains("layout_direction:"))
        XCTAssertFalse(importedText.contains("columns:"))
    }

    func testKeepsNonMetadataDraftSeparatorsInExistingFlow() {
        let project = MarkdownBookImporter().importDocument(
            markdown: """
            # 草稿

            正文前半段。

            ---

            这不是元数据。
            """
        )

        let bodyTexts = project.sections[0].stories[0].paragraphs
            .filter { $0.kind == .body }
            .map(\.text)
        XCTAssertEqual(bodyTexts, ["正文前半段。", "这不是元数据。"])
    }

    func testPreservesBoldItalicAndNestedInlineRuns() throws {
        let project = MarkdownBookImporter().importDocument(
            markdown: """
            # 行内格式

            普通 **粗体**、*斜体*、==着重== 与 ***粗斜体***，`代码`不着重。
            """
        )
        let paragraph = try XCTUnwrap(
            project.sections[0].stories[0].paragraphs.first { $0.kind == .body }
        )
        XCTAssertEqual(paragraph.text, "普通 粗体、斜体、着重 与 粗斜体，代码不着重。")
        XCTAssertEqual(paragraph.inlineRuns, [
            InlineRun(location: 3, length: 2, emphasis: [.bold]),
            InlineRun(location: 6, length: 2, emphasis: [.italic]),
            InlineRun(location: 9, length: 2, emphasis: [.kenten]),
            InlineRun(location: 14, length: 3, emphasis: [.bold, .italic])
        ])
    }

    func testPreservesCJKSingleDelimiterItalicRuns() throws {
        let project = MarkdownBookImporter().importDocument(
            markdown: """
            # 中文斜体

            前*单星*后，前_下划线_后，**粗体**与*斜体*相邻。
            """
        )
        let paragraph = try XCTUnwrap(
            project.sections[0].stories[0].paragraphs.first { $0.kind == .body }
        )

        XCTAssertEqual(paragraph.text, "前单星后，前下划线后，粗体与斜体相邻。")
        XCTAssertEqual(paragraph.inlineRuns, [
            InlineRun(location: 1, length: 2, emphasis: [.italic]),
            InlineRun(location: 6, length: 3, emphasis: [.italic]),
            InlineRun(location: 11, length: 2, emphasis: [.bold]),
            InlineRun(location: 14, length: 2, emphasis: [.italic])
        ])
    }

    func testDoesNotTreatASCIIIntrawordDelimitersAsItalic() throws {
        let project = MarkdownBookImporter().importDocument(
            markdown: """
            # ASCII 边界

            foo*bar*与 foo_bar_baz
            """
        )
        let paragraph = try XCTUnwrap(
            project.sections[0].stories[0].paragraphs.first { $0.kind == .body }
        )

        XCTAssertEqual(paragraph.text, "foo*bar*与 foo_bar_baz")
        XCTAssertNil(paragraph.inlineRuns)
    }

    func testPreservesInlineRunsAcrossTextBlockKinds() throws {
        let project = MarkdownBookImporter().importDocument(
            markdown: """
            # 行内格式

            ## **粗**==标题==

            - 列表*斜*==项==

            > 引用**强==调==**

            > [!NOTE] **知识卡**
            > 继续*强==调==*
            """
        )
        let paragraphs = project.sections[0].stories[0].paragraphs

        let heading = try XCTUnwrap(paragraphs.first { $0.kind == .heading(level: 2) })
        XCTAssertEqual(heading.text, "粗标题")
        XCTAssertEqual(heading.inlineRuns, [
            InlineRun(location: 0, length: 1, emphasis: [.bold]),
            InlineRun(location: 1, length: 2, emphasis: [.kenten])
        ])

        let listItem = try XCTUnwrap(paragraphs.first { $0.kind == .listItem })
        XCTAssertEqual(listItem.text, "列表斜项")
        XCTAssertEqual(listItem.inlineRuns, [
            InlineRun(location: 2, length: 1, emphasis: [.italic]),
            InlineRun(location: 3, length: 1, emphasis: [.kenten])
        ])

        let quote = try XCTUnwrap(paragraphs.first { $0.kind == .quote })
        XCTAssertEqual(quote.text, "引用强调")
        XCTAssertEqual(quote.inlineRuns, [
            InlineRun(location: 2, length: 1, emphasis: [.bold]),
            InlineRun(location: 3, length: 1, emphasis: [.bold, .kenten])
        ])

        let callout = try XCTUnwrap(paragraphs.first { $0.kind == .callout })
        XCTAssertEqual(callout.text, "知识点：知识卡 继续强调")
        XCTAssertEqual(callout.inlineRuns, [
            InlineRun(location: 4, length: 3, emphasis: [.bold]),
            InlineRun(location: 10, length: 1, emphasis: [.italic]),
            InlineRun(location: 11, length: 1, emphasis: [.italic, .kenten])
        ])
    }

    func testDoesNotTreatASCIIDoubleEqualsAsKenten() throws {
        let project = MarkdownBookImporter().importDocument(
            markdown: """
            # ASCII 等号

            a==b 与 speed==fast 保持原样。
            """
        )
        let paragraph = try XCTUnwrap(
            project.sections[0].stories[0].paragraphs.first { $0.kind == .body }
        )

        XCTAssertEqual(paragraph.text, "a==b 与 speed==fast 保持原样。")
        XCTAssertNil(paragraph.inlineRuns)
    }

    func testPreservesKentenWhenNestedWithBoldAndItalic() throws {
        let project = MarkdownBookImporter().importDocument(
            markdown: """
            # 嵌套傍点

            一 ==**A**== 二 **==B==** 三 ==*C*== 四 *==D==* 五。
            """
        )
        let paragraph = try XCTUnwrap(
            project.sections[0].stories[0].paragraphs.first { $0.kind == .body }
        )

        XCTAssertEqual(paragraph.text, "一 A 二 B 三 C 四 D 五。")
        XCTAssertEqual(paragraph.inlineRuns, [
            InlineRun(location: 2, length: 1, emphasis: [.bold, .kenten]),
            InlineRun(location: 6, length: 1, emphasis: [.bold, .kenten]),
            InlineRun(location: 10, length: 1, emphasis: [.italic, .kenten]),
            InlineRun(location: 14, length: 1, emphasis: [.italic, .kenten])
        ])
    }

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

    func testImportsOrderedMarkdownLists() {
        let project = MarkdownBookImporter().importDocument(
            markdown: """
            # 实验步骤

            1. 准备烧杯
            2) 加入清水
            10. 记录现象
            3.NoSpace should stay body text
            """
        )

        let paragraphs = project.sections[0].stories[0].paragraphs
        let listItems = paragraphs.filter { $0.kind == .listItem }.map(\.text)
        XCTAssertEqual(listItems, ["1. 准备烧杯", "2) 加入清水", "10. 记录现象"])
        XCTAssertTrue(paragraphs.contains {
            $0.kind == .body && $0.text == "3.NoSpace should stay body text"
        })
    }

    func testStripsCommonInlineMarkdownFromImportedText() {
        let project = MarkdownBookImporter().importDocument(
            markdown: """
            # **细胞**链接

            正文包含 **重点**、`ATP` 和 [能量分子](https://example.com)。

            ## __小节__ `代码`

            - *无序* 列表
            1. 有序 [列表](https://example.com/list)

            > [!NOTE] **知识卡**
            > 这里有 `术语` 和 [链接](https://example.com/note)。

            ![**图片**图注](diagram.png)

            | 指标 | 说明 |
            | --- | --- |
            | **ATP** | [能量](https://example.com/energy) |
            """
        )

        XCTAssertEqual(project.metadata.title, "细胞链接")
        let paragraphs = project.sections[0].stories[0].paragraphs
        XCTAssertTrue(paragraphs.contains {
            $0.kind == .body && $0.text == "正文包含 重点、ATP 和 能量分子。"
        })
        XCTAssertTrue(paragraphs.contains {
            $0.kind == .heading(level: 2) && $0.text == "小节 代码"
        })
        XCTAssertTrue(paragraphs.contains {
            $0.kind == .listItem && $0.text == "无序 列表"
        })
        XCTAssertTrue(paragraphs.contains {
            $0.kind == .listItem && $0.text == "1. 有序 列表"
        })
        XCTAssertTrue(paragraphs.contains {
            $0.kind == .callout && $0.text == "知识点：知识卡 这里有 术语 和 链接。"
        })
        XCTAssertTrue(paragraphs.contains {
            $0.kind == .table && $0.text == "指标    说明\nATP    能量"
        })
        XCTAssertEqual(project.assets.first?.caption, "图片图注")
    }

    func testInlineMarkdownCleanupPreservesLiteralSymbols() {
        let project = MarkdownBookImporter().importDocument(
            markdown: """
            # 公式与术语

            正文保留 snake_case、3 * 4、ATP_synthase 和 \\*字面星号\\*，但清理 **重点**、_术语_ 与 `code_value`。

            - 列表保留 file_name.png 和 2 * 3
            """
        )

        let paragraphs = project.sections[0].stories[0].paragraphs
        XCTAssertTrue(paragraphs.contains {
            $0.kind == .body
                && $0.text == "正文保留 snake_case、3 * 4、ATP_synthase 和 *字面星号*，但清理 重点、术语 与 code_value。"
        })
        XCTAssertTrue(paragraphs.contains {
            $0.kind == .listItem && $0.text == "列表保留 file_name.png 和 2 * 3"
        })
    }

    func testImportsNestedMarkdownHeadings() {
        let project = MarkdownBookImporter().importDocument(
            markdown: """
            # 第一章

            ## 二级小节

            ### 三级小节

            ###### 六级提示

            ####NoSpace should stay body text
            """
        )

        let paragraphs = project.sections[0].stories[0].paragraphs
        XCTAssertTrue(paragraphs.contains {
            $0.kind == .heading(level: 2)
                && $0.text == "二级小节"
                && $0.styleId == StyleID.heading2.rawValue
        })
        XCTAssertTrue(paragraphs.contains {
            $0.kind == .heading(level: 3)
                && $0.text == "三级小节"
                && $0.styleId == StyleID.heading2.rawValue
        })
        XCTAssertTrue(paragraphs.contains {
            $0.kind == .heading(level: 6)
                && $0.text == "六级提示"
                && $0.styleId == StyleID.heading2.rawValue
        })
        XCTAssertTrue(paragraphs.contains {
            $0.kind == .body && $0.text == "####NoSpace should stay body text"
        })
    }

    func testImportsSetextMarkdownHeadings() {
        let project = MarkdownBookImporter().importDocument(
            markdown: """
            细胞里的城市
            ===

            细胞是一座高度组织化的城市。

            能量系统
            ---

            线粒体负责转换能量。
            """
        )

        XCTAssertEqual(project.metadata.title, "细胞里的城市")
        XCTAssertEqual(project.sections.count, 1)
        XCTAssertEqual(project.sections[0].title, "细胞里的城市")

        let paragraphs = project.sections[0].stories[0].paragraphs
        XCTAssertTrue(paragraphs.contains {
            $0.kind == .body && $0.text == "细胞是一座高度组织化的城市。"
        })
        XCTAssertTrue(paragraphs.contains {
            $0.kind == .heading(level: 2) && $0.text == "能量系统"
        })
        XCTAssertTrue(paragraphs.contains {
            $0.kind == .body && $0.text == "线粒体负责转换能量。"
        })
        XCTAssertFalse(paragraphs.contains { $0.text == "===" || $0.text == "---" })
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

    func testMarksRepeatedImageReferences() {
        let project = MarkdownBookImporter().importDocument(
            markdown: """
            # 重复用图

            ![第一次图注](images/cell.png)

            这里继续解释正文。

            ![第二次图注](images/cell.png)
            """
        )

        XCTAssertEqual(project.assets.count, 1)
        XCTAssertEqual(project.assets[0].fileName, "images/cell.png")
        XCTAssertEqual(project.assets[0].usage, .repeated)

        let figures = project.sections[0].stories[0].paragraphs.filter {
            if case .figure = $0.kind {
                return true
            }
            return false
        }
        XCTAssertEqual(figures.count, 2)
    }

    func testDuplicateNestedAssetBasenamesArePreservedDuringImport() {
        let firstAsset = Asset(
            fileName: "chapter-01/figure.png",
            role: .diagram,
            caption: "第一章图片",
            pixelWidth: 1200,
            pixelHeight: 800
        )
        let secondAsset = Asset(
            fileName: "chapter-02/figure.png",
            role: .photo,
            caption: "第二章图片",
            pixelWidth: 1200,
            pixelHeight: 800
        )

        let project = MarkdownBookImporter().importDocument(
            markdown: """
            # 重名素材

            ![](figure.png)
            """,
            assetCatalog: AssetCatalog(assets: [firstAsset, secondAsset])
        )

        XCTAssertEqual(project.assets.count, 2)
        XCTAssertEqual(project.assets.map(\.fileName), ["chapter-01/figure.png", "chapter-02/figure.png"])
        let chapterOneAsset = project.assets.filter { $0.fileName == "chapter-01/figure.png" }.first
        let chapterTwoAsset = project.assets.filter { $0.fileName == "chapter-02/figure.png" }.first
        XCTAssertEqual(chapterOneAsset?.usage, .placed)
        XCTAssertEqual(chapterTwoAsset?.usage, .unused)
    }

    func testNestedAssetReferencesPreferExactRelativePath() {
        let firstAsset = Asset(
            fileName: "chapter-01/figure.png",
            role: .diagram,
            caption: "第一章图片",
            pixelWidth: 1200,
            pixelHeight: 800
        )
        let secondAsset = Asset(
            fileName: "chapter-02/figure.png",
            role: .photo,
            caption: "第二章图片",
            pixelWidth: 1200,
            pixelHeight: 800
        )

        let project = MarkdownBookImporter().importDocument(
            markdown: """
            # 精确路径素材

            ![](chapter-02/figure.png)
            """,
            assetCatalog: AssetCatalog(assets: [firstAsset, secondAsset])
        )

        XCTAssertEqual(project.assets.count, 2)
        let chapterOneAsset = project.assets.filter { $0.fileName == "chapter-01/figure.png" }.first
        let chapterTwoAsset = project.assets.filter { $0.fileName == "chapter-02/figure.png" }.first
        XCTAssertEqual(chapterOneAsset?.usage, .unused)
        XCTAssertEqual(chapterTwoAsset?.usage, .placed)
    }

    func testChapterPackageAssetRootPrefixIsIgnoredForNestedReferences() {
        let firstAsset = Asset(
            fileName: "chapter-01/figure.png",
            role: .diagram,
            caption: "第一章图片",
            pixelWidth: 1200,
            pixelHeight: 800
        )
        let secondAsset = Asset(
            fileName: "chapter-02/figure.png",
            role: .photo,
            caption: "第二章图片",
            pixelWidth: 1200,
            pixelHeight: 800
        )

        let project = MarkdownBookImporter().importDocument(
            markdown: """
            # 章节包路径素材

            ![](../assets/chapter-02/figure.png)
            """,
            assetCatalog: AssetCatalog(assets: [firstAsset, secondAsset])
        )

        let chapterOneAsset = project.assets.filter { $0.fileName == "chapter-01/figure.png" }.first
        let chapterTwoAsset = project.assets.filter { $0.fileName == "chapter-02/figure.png" }.first
        XCTAssertEqual(chapterOneAsset?.usage, .unused)
        XCTAssertEqual(chapterTwoAsset?.usage, .placed)
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

    func testImportsSingleQuotedImageMetadata() {
        let project = MarkdownBookImporter().importDocument(
            markdown: """
            # 单引号图片元数据

            正文说明细胞结构。

            ![细胞结构图](images/cell.png 'role=diagram; credit=layoutD; anchor=previous')
            """
        )

        let asset = project.assets[0]
        let body = project.sections[0].stories[0].paragraphs.first { $0.kind == .body }
        XCTAssertEqual(asset.fileName, "images/cell.png")
        XCTAssertEqual(asset.role, .diagram)
        XCTAssertEqual(asset.credit, "layoutD")
        XCTAssertEqual(asset.caption, "细胞结构图")
        XCTAssertEqual(body?.anchoredAssetIds, [asset.id])
    }

    func testImportsImageSourceMetadataAsCredit() {
        let project = MarkdownBookImporter().importDocument(
            markdown: """
            # 图片来源元数据

            ![显微照片](cell.png "role=photo; source=NASA")
            """
        )

        XCTAssertEqual(project.assets[0].fileName, "cell.png")
        XCTAssertEqual(project.assets[0].role, .photo)
        XCTAssertEqual(project.assets[0].credit, "NASA")
        XCTAssertEqual(project.assets[0].caption, "显微照片")
    }

    func testImportsReferenceStyleMarkdownImage() {
        let knownAsset = Asset(
            fileName: "images/cell detail.png",
            role: .photo,
            pixelWidth: 1200,
            pixelHeight: 800
        )
        let project = MarkdownBookImporter().importDocument(
            markdown: """
            # Reference 图片

            正文说明细胞结构。

            ![细胞结构图][cell-detail]

            [cell-detail]: <images/cell detail.png> 'role=diagram; source=NASA; anchor=previous'
            """,
            assetCatalog: AssetCatalog(assets: [knownAsset])
        )

        let asset = project.assets[0]
        let paragraphs = project.sections[0].stories[0].paragraphs
        let body = paragraphs.first { $0.kind == .body }

        XCTAssertEqual(asset.id, knownAsset.id)
        XCTAssertEqual(asset.fileName, "images/cell detail.png")
        XCTAssertEqual(asset.role, .diagram)
        XCTAssertEqual(asset.credit, "NASA")
        XCTAssertEqual(asset.caption, "细胞结构图")
        XCTAssertEqual(body?.anchoredAssetIds, [knownAsset.id])
        XCTAssertFalse(paragraphs.contains { $0.text.contains("[cell-detail]:") })
    }

    func testImportsShortcutReferenceStyleMarkdownImage() {
        let project = MarkdownBookImporter().importDocument(
            markdown: """
            # Shortcut Reference 图片

            ![细胞结构图][]

            [细胞结构图]: cell.png "role=diagram; credit=layoutD"
            """
        )

        XCTAssertEqual(project.assets[0].fileName, "cell.png")
        XCTAssertEqual(project.assets[0].role, .diagram)
        XCTAssertEqual(project.assets[0].credit, "layoutD")
        XCTAssertEqual(project.assets[0].caption, "细胞结构图")
        XCTAssertTrue(project.sections[0].stories[0].paragraphs.contains {
            if case .figure = $0.kind {
                return true
            }
            return false
        })
    }

    func testImportsAngleBracketImagePath() {
        let knownAsset = Asset(
            fileName: "images/cell detail.png",
            role: .photo,
            pixelWidth: 1200,
            pixelHeight: 800
        )
        let project = MarkdownBookImporter().importDocument(
            markdown: """
            # 尖括号图片路径

            ![细胞局部图](<images/cell detail.png> "role=diagram; credit=layoutD")
            """,
            assetCatalog: AssetCatalog(assets: [knownAsset])
        )

        XCTAssertEqual(project.assets.count, 1)
        XCTAssertEqual(project.assets[0].id, knownAsset.id)
        XCTAssertEqual(project.assets[0].fileName, "images/cell detail.png")
        XCTAssertEqual(project.assets[0].role, .diagram)
        XCTAssertEqual(project.assets[0].credit, "layoutD")
        XCTAssertEqual(project.assets[0].usage, .placed)
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

    func testImageCanAnchorToPreviousParagraph() {
        let knownAsset = Asset(
            fileName: "images/cell-detail.png",
            role: .diagram,
            pixelWidth: 1200,
            pixelHeight: 900
        )
        let project = MarkdownBookImporter().importDocument(
            markdown: """
            # 细胞里的城市

            线粒体是细胞里负责能量转换的重要结构。

            ![线粒体局部结构](images/cell-detail.png "anchor=previous; credit=layoutD")
            """,
            assetCatalog: AssetCatalog(assets: [knownAsset])
        )

        let paragraphs = project.sections[0].stories[0].paragraphs
        let body = paragraphs.first { $0.kind == .body }
        XCTAssertEqual(body?.anchoredAssetIds, [knownAsset.id])
        XCTAssertFalse(paragraphs.contains {
            if case .figure = $0.kind {
                return true
            }
            return false
        })
        XCTAssertEqual(project.assets[0].caption, "线粒体局部结构")
        XCTAssertEqual(project.assets[0].credit, "layoutD")
        XCTAssertEqual(project.assets[0].usage, .placed)
    }

    func testAnchoredImageWithoutPreviousParagraphFallsBackToFigure() {
        let project = MarkdownBookImporter().importDocument(
            markdown: """
            # 细胞里的城市

            ![开场图](opening.png "anchor=previous")
            """
        )

        let paragraphs = project.sections[0].stories[0].paragraphs
        XCTAssertTrue(paragraphs.contains {
            if case .figure = $0.kind {
                return true
            }
            return false
        })
        XCTAssertTrue(paragraphs.allSatisfy { $0.anchoredAssetIds.isEmpty })
        XCTAssertEqual(project.assets[0].usage, .placed)
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

            <!--
            编辑备注：这一段不应进入导入结果。
            图片还需要重新确认。
            -->

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
        // E3-4：结构化行列须保留供原生 IDML <Table> 导出，不再只剩拍平文本。
        XCTAssertEqual(table?.tableCells, [
            ["指标", "数值"],
            ["细胞数量", "约 37 万亿"],
            ["平均直径", "10 微米"],
        ])
    }

    func testTableCellsPreserveInlineFormatting() {
        // E3-4b：单元格内的粗/斜应解析进 tableCellRuns（偏移针对该格剥离后文本），
        // tableCells 仍为剥离文本。
        let project = MarkdownBookImporter().importDocument(
            markdown: """
            # 表格行内

            | 名称 | 说明 |
            | --- | --- |
            | 线粒体 | **产能**中心 |
            | 核糖体 | 合成*蛋白质* |
            """
        )
        let table = project.sections[0].stories[0].paragraphs.first { $0.kind == .table }
        XCTAssertEqual(table?.tableCells?[1], ["线粒体", "产能中心"])  // markdown 已剥离
        let runs = table?.tableCellRuns
        XCTAssertNotNil(runs, "含粗/斜的表格应填充 tableCellRuns")
        // 「**产能**中心」→ 粗体覆盖前两个字符
        XCTAssertEqual(runs?[1][1].first?.emphasis, [.bold])
        XCTAssertEqual(runs?[1][1].first?.location, 0)
        XCTAssertEqual(runs?[1][1].first?.length, 2)
        // 「合成*蛋白质*」→ 斜体覆盖后三个字符
        XCTAssertEqual(runs?[2][1].first?.emphasis, [.italic])
        XCTAssertEqual(runs?[2][1].first?.location, 2)
    }

    func testImportsSpreadImageMetadata() {
        let project = MarkdownBookImporter().importDocument(
            markdown: """
            # 跨页图导入
            
            ![跨页图](spread.png "span=spread; credit=NASA")
            """
        )
        
        let asset = project.assets.first { $0.fileName == "spread.png" }
        XCTAssertNotNil(asset)
        XCTAssertEqual(asset?.role, .spread)
        XCTAssertEqual(asset?.credit, "NASA")
    }
}
