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
        XCTAssertTrue(story.contains("KentenKind=\"KentenBlackCircle\" KentenPlacement=\"-1\" KentenPosition=\"BelowLeft\"><Content>着重</Content>"))
        XCTAssertTrue(story.contains("Skew=\"12\"><Content>斜体</Content>"))
        XCTAssertTrue(story.contains("FauxBold=\"true\" Skew=\"12\" KentenKind=\"KentenBlackCircle\" KentenPlacement=\"-1\" KentenPosition=\"BelowLeft\"><Content>粗斜</Content>"))
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
        // 着重号按中文习惯：KentenBlackCircle(实心黑圆点) + BelowLeft(字下方)，对齐真·InDesign golden。
        XCTAssertEqual(matches(in: story, pattern: "(FauxBold=\\\"true\\\" KentenKind=\\\"KentenBlackCircle\\\"[^>]*><Content>[AB]</Content>)").count, 2)
        XCTAssertEqual(matches(in: story, pattern: "(Skew=\\\"12\\\" KentenKind=\\\"KentenBlackCircle\\\"[^>]*><Content>[CD]</Content>)").count, 2)
        XCTAssertFalse(story.contains("Skew=\"12\"><Content>二</Content>"))
        XCTAssertFalse(story.contains("FauxBold=\"true\"><Content>三</Content>"))
        // 着重号只在 CJK/World-Ready 段落排版器下渲染。经真·InDesign 2026 存盘比对：排版器真值
        // 是 Composer="HL Composer J"（挂在段落样式定义上），而非 Story 段落内联 AppliedComposer
        // （InDesign 无此属性、会被忽略）。故 Story 不应再含 AppliedComposer；样式应带 Composer。
        XCTAssertFalse(story.contains("AppliedComposer"))
        let styles = try entry(output, "Resources/Styles.xml")
        XCTAssertTrue(
            styles.contains("Self=\"ParagraphStyle/body\"") && styles.contains("Composer=\"HL Composer J\""),
            "body 段落样式应带 World-Ready 排版器 Composer=\"HL Composer J\""
        )
        // 不变量断言闸应放行（着重号已配 World-Ready 样式）。
        // 反证：若把样式排版器换成拉丁 Optyca，闸门必须报 kenten-needs-world-ready-composer。
        let goodFiles = ["Resources/Styles.xml": styles, "Stories/Story_uStory0_0.xml": story]
        XCTAssertTrue(IDMLInvariants.check(files: goodFiles).isEmpty)
        let latinStyles = styles.replacingOccurrences(of: "Composer=\"HL Composer J\"", with: "Composer=\"HL Composer Optyca\"")
        let badFiles = ["Resources/Styles.xml": latinStyles, "Stories/Story_uStory0_0.xml": story]
        XCTAssertEqual(Set(IDMLInvariants.check(files: badFiles).map(\.rule)), ["kenten-needs-world-ready-composer"])
    }

    func testExportsAnchoredFootnoteAsNativeIDMLWithoutDuplicatePageFooter() throws {
        let footnote = Paragraph(
            kind: .footnote(number: 1),
            text: "这是脚注内容。",
            styleId: "footnote"
        )
        let body = Paragraph(
            kind: .body,
            text: "正文一句话¹。",
            styleId: StyleID.body.rawValue,
            anchoredFootnoteIds: [footnote.id]
        )
        let project = BookProject(
            metadata: ProjectMetadata(title: "脚注", author: "layoutD"),
            sections: [BookSection(title: "正文", stories: [Story(title: "正文", paragraphs: [body, footnote])])]
        )
        let document = LayoutEngine().layout(project: project)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-idml-footnote-\(UUID().uuidString).idml")
        defer { try? FileManager.default.removeItem(at: output) }

        try IDMLExporter().export(document: document, project: project, to: output)

        let stories = try zipEntries(output)
            .filter { $0.hasPrefix("Stories/Story_") }
            .map { try entry(output, $0) }
            .joined(separator: "\n")
        XCTAssertEqual(matches(in: stories, pattern: "(<Footnote>[\\s\\S]*?<Content>这是脚注内容。</Content>[\\s\\S]*?</Footnote>)").count, 1)
        XCTAssertFalse(stories.contains("<Content>¹</Content>"), "脚注锚点应由原生 Footnote 取代，而非保留 Unicode 上标")
        XCTAssertEqual(matches(in: stories, pattern: "(<Content>这是脚注内容。</Content>)").count, 1,
                       "脚注正文只能位于 Footnote 内，不得作为页脚 frame 再导出一次")

        // E3-7v 回归：脚注正文必须挂在带中文复合字体（CF_*）的段落样式上，否则
        // InDesign 退回拉丁默认字体、中文显示为豆腐。绝不能再是 [No paragraph style]。
        let footnoteStyleRefs = matches(
            in: stories,
            pattern: "<Footnote>\\s*<ParagraphStyleRange AppliedParagraphStyle=\"(ParagraphStyle/[^\"]+)\""
        )
        XCTAssertEqual(footnoteStyleRefs.count, 1, "应能取到脚注 ParagraphStyleRange 的样式引用")
        let footnoteStyleRef = footnoteStyleRefs.first ?? ""
        XCTAssertFalse(footnoteStyleRef.contains("[No paragraph style]"),
                       "脚注段落样式不得是空样式（无字体→中文豆腐）")
        // 被引用的样式必须在 Styles.xml 里带 CF_ 复合字体 AppliedFont。
        let stylesXML = try entry(output, "Resources/Styles.xml")
        let refId = footnoteStyleRef.replacingOccurrences(of: "ParagraphStyle/", with: "")
        XCTAssertEqual(
            matches(in: stylesXML,
                    pattern: "<ParagraphStyle Self=\"ParagraphStyle/\(refId)\"[\\s\\S]*?<AppliedFont type=\"string\">(CF_[^<]+)</AppliedFont>").count,
            1,
            "脚注引用的段落样式必须带 CF_ 复合字体，确保中文有字形"
        )
    }

    func testExportsStructuredDynamicTOCWithTabLeaders() throws {
        let project = BookProject.sample
        let document = LayoutEngine().layout(project: project)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-idml-toc-\(UUID().uuidString).idml")
        defer { try? FileManager.default.removeItem(at: output) }

        try IDMLExporter().export(document: document, project: project, to: output)

        let styles = try entry(output, "Resources/Styles.xml")
        XCTAssertTrue(styles.contains("<TOCStyle Self=\"TOCStyle/layoutD_TOC\""))
        XCTAssertTrue(styles.contains("AppliedParagraphStyle=\"ParagraphStyle/heading1\""))
        XCTAssertTrue(styles.contains("AppliedParagraphStyle=\"ParagraphStyle/heading2\""))
        XCTAssertTrue(styles.contains("TOCEntryStyle=\"ParagraphStyle/tocLevel1\""))
        XCTAssertTrue(styles.contains("TOCEntryStyle=\"ParagraphStyle/tocLevel2\""))

        let stories = try zipEntries(output)
            .filter { $0.hasPrefix("Stories/Story_") }
            .map { try entry(output, $0) }
        let tocStory = try XCTUnwrap(stories.first { $0.contains("AppliedTOCStyle=\"TOCStyle/layoutD_TOC\"") })
        // 制表位必须是合法的嵌套 <TabList>，而非会被 InDesign 忽略的扁平属性。
        XCTAssertTrue(tocStory.contains("<TabList type=\"list\">"))
        XCTAssertTrue(tocStory.contains("<Alignment type=\"enumeration\">RightAlign</Alignment>"))
        XCTAssertTrue(tocStory.contains("<Leader type=\"string\">.</Leader>"))
        XCTAssertFalse(tocStory.contains("TabStopAlignment="), "不得用会被 InDesign 忽略的扁平 tab 属性")
        XCTAssertTrue(tocStory.contains("\t"), "目录标题与页码必须由 tab 分隔，而非空格拼接")
        XCTAssertFalse(tocStory.contains("图像不只是正文的附件  3"))
    }

    func testTOCCollectsSubheadingsNotJustTopLevel() throws {
        // 正文里的二级标题也应进静态目录（否则只剩书名级 H1，需在 InDesign 手动更新目录才补全）。
        let project = BookProject(
            metadata: ProjectMetadata(title: "目录层级测试", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "",
                            paragraphs: [
                                Paragraph(kind: .heading(level: 1), text: "第一章", styleId: StyleID.heading1.rawValue),
                                Paragraph(kind: .body, text: "引言段落。", styleId: StyleID.body.rawValue),
                                Paragraph(kind: .heading(level: 2), text: "一级能量", styleId: StyleID.heading2.rawValue),
                                Paragraph(kind: .body, text: "正文一。", styleId: StyleID.body.rawValue),
                                Paragraph(kind: .heading(level: 2), text: "二级图注", styleId: StyleID.heading2.rawValue),
                                Paragraph(kind: .body, text: "正文二。", styleId: StyleID.body.rawValue)
                            ]
                        )
                    ]
                )
            ]
        )
        let document = LayoutEngine().layout(project: project)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-idml-toc2-\(UUID().uuidString).idml")
        defer { try? FileManager.default.removeItem(at: output) }
        try IDMLExporter().export(document: document, project: project, to: output)

        let tocStory = try XCTUnwrap(try zipEntries(output)
            .filter { $0.hasPrefix("Stories/Story_") }
            .map { try entry(output, $0) }
            .first { $0.contains("AppliedTOCStyle=\"TOCStyle/layoutD_TOC\"") })
        // 两个二级标题都要在目录里，且挂二级目录样式 tocLevel2。
        XCTAssertTrue(tocStory.contains("一级能量"), "二级标题 1 应进目录")
        XCTAssertTrue(tocStory.contains("二级图注"), "二级标题 2 应进目录")
        XCTAssertTrue(tocStory.contains("ParagraphStyle/tocLevel2"), "子标题应使用二级目录样式")
    }

    func testExportsTableParagraphAsNativeIDMLTable() throws {
        // E3-4：带结构化行列的 .table 段应导出为原生 <Table>/<Column>/<Row>/<Cell>，
        // 而非拍平成「4 空格拼接」的裸文字。（importer 保留行列的断言见 LayoutDImport 测试。）
        let cells = [["名称", "功能"], ["线粒体", "产能"], ["核糖体", "合成蛋白质"]]
        let table = Paragraph(
            kind: .table,
            text: cells.map { $0.joined(separator: "    ") }.joined(separator: "\n"),
            styleId: StyleID.body.rawValue,
            tableCells: cells
        )
        let project = BookProject(
            metadata: ProjectMetadata(title: "表格", author: "layoutD"),
            sections: [BookSection(title: "正文", stories: [Story(title: "正文", paragraphs: [table])])]
        )
        let document = LayoutEngine().layout(project: project)

        // 布局须按网格给表格分配足够高度（每行 ≥ 最小行高 18pt），否则 InDesign 里整张表
        // 溢流、只显示前几行。这条防止回退到「按拍平文本测高」。
        let tableFrame = document.pages.flatMap(\.frames).first { $0.kind == .table }
        XCTAssertNotNil(tableFrame, "应生成 .table 帧")
        XCTAssertGreaterThanOrEqual(tableFrame?.rect.height ?? 0, Double(cells.count) * 18,
                                    "表格框高度须能容纳所有行")

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-idml-table-\(UUID().uuidString).idml")
        defer { try? FileManager.default.removeItem(at: output) }
        try IDMLExporter().export(document: document, project: project, to: output)

        let stories = try zipEntries(output)
            .filter { $0.hasPrefix("Stories/Story_") }
            .map { try entry(output, $0) }
            .joined(separator: "\n")
        XCTAssertEqual(matches(in: stories, pattern: "(<Table )").count, 1, "应输出 1 个原生 Table")
        XCTAssertEqual(matches(in: stories, pattern: "(<Column )").count, 2, "2 列")
        XCTAssertEqual(matches(in: stories, pattern: "(<Row )").count, 3, "3 行（含表头）")
        XCTAssertEqual(matches(in: stories, pattern: "(<Cell )").count, 6, "2×3=6 单元格")
        XCTAssertTrue(stories.contains("HeaderRowCount=\"1\""), "首行应为表头")
        for cell in ["名称", "功能", "线粒体", "产能", "核糖体", "合成蛋白质"] {
            XCTAssertTrue(stories.contains("<Content>\(cell)</Content>"), "单元格 \(cell) 应归位到 Cell 内")
        }
        XCTAssertFalse(stories.contains("名称    功能"), "不得残留 4 空格拍平的裸文字")
        // 单元格须左对齐且去掉正文首行缩进，否则窄列里文字被推到右边、参差不齐。
        XCTAssertEqual(matches(in: stories, pattern: "(Justification=\"LeftJustified\")").count, 6,
                       "每个单元格段落须左对齐")
        XCTAssertEqual(matches(in: stories, pattern: "(FirstLineIndent=\"0\")").count, 6,
                       "每个单元格段落须去掉首行缩进")
    }

    func testTableCellInlineFormattingExportsToIDML() throws {
        // E3-4b：表格单元格内的粗/斜/傍点（tableCellRuns）应导出为 FauxBold/Skew/Kenten，
        // 而非被写死成空 inlineRuns 丢失。
        let cells = [["名称", "说明"], ["线粒体", "产能中心"], ["核糖体", "合成蛋白质"], ["膜", "重点结构"]]
        let runs: [[[InlineRun]]] = [
            [[], []],                                            // 表头无格式
            [[], [InlineRun(location: 0, length: 2, emphasis: [.bold])]],   // 产能(粗)中心
            [[], [InlineRun(location: 2, length: 3, emphasis: [.italic])]], // 合成蛋白质(斜)
            [[], [InlineRun(location: 0, length: 2, emphasis: [.kenten])]], // 重点(傍点)结构
        ]
        let table = Paragraph(
            kind: .table,
            text: cells.map { $0.joined(separator: "    ") }.joined(separator: "\n"),
            styleId: StyleID.body.rawValue,
            tableCells: cells,
            tableCellRuns: runs
        )
        let project = BookProject(
            metadata: ProjectMetadata(title: "表格行内", author: "layoutD"),
            sections: [BookSection(title: "正文", stories: [Story(title: "正文", paragraphs: [table])])]
        )
        let document = LayoutEngine().layout(project: project)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-idml-tablecell-\(UUID().uuidString).idml")
        defer { try? FileManager.default.removeItem(at: output) }
        try IDMLExporter().export(document: document, project: project, to: output)

        let stories = try zipEntries(output)
            .filter { $0.hasPrefix("Stories/Story_") }
            .map { try entry(output, $0) }
            .joined(separator: "\n")
        XCTAssertTrue(stories.contains("FauxBold=\"true\""), "单元格粗体应出 FauxBold")
        XCTAssertTrue(stories.contains("Skew=\"12\""), "单元格斜体应出 Skew")
        XCTAssertTrue(stories.contains("KentenKind"), "单元格傍点应出 KentenKind")
    }

    func testNonRectangularImageMaskExportsPolygonGeometry() throws {
        // E2-5：maskShape=.octagon/.fan 的图框须输出多边形 PathGeometry（非 4 角矩形），
        // 让 InDesign 把置入图裁成对应形状；图片仍放满 rect。
        func imageFramePointCount(_ shape: ImageMaskShape) throws -> Int {
            var project = BookProject.sample
            let assetId = UUID()
            project.assets.append(Asset(id: assetId, fileName: "art.png", role: .decorative,
                                        pixelWidth: 800, pixelHeight: 600))
            let plan = LayoutPlan(target: .page(3), strategy: .fullPageImage, blocks: [
                LayoutPlanBlock(kind: .image, role: "art",
                                frame: Rect(x: 0.1, y: 0.1, width: 0.6, height: 0.6),
                                contentReference: .asset(assetId), maskShape: shape)
            ])
            project.safeAppliedLayoutPlans[3] = plan
            let document = LayoutEngine().layout(project: project)
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent("layoutd-idml-mask-\(UUID().uuidString).idml")
            defer { try? FileManager.default.removeItem(at: output) }
            try IDMLExporter().export(document: document, project: project, to: output)
            let spread = try XCTUnwrap(try zipEntries(output)
                .filter { $0.hasPrefix("Spreads/Spread_") }
                .map { try entry(output, $0) }
                .first { $0.contains("ContentType=\"GraphicType\"") }, "应有含图的 spread")
            // 图框路径点在 GraphicType Rectangle 开标签与 <Image 之间。
            let afterRect = spread.components(separatedBy: "ContentType=\"GraphicType\"")[1]
            let frameGeom = afterRect.components(separatedBy: "<Image").first ?? ""
            return frameGeom.components(separatedBy: "<PathPointType").count - 1
        }
        XCTAssertEqual(try imageFramePointCount(.octagon), 8, "八角图框应 8 个路径点")
        XCTAssertEqual(try imageFramePointCount(.rect), 4, "矩形图框仍 4 个路径点（无回归）")
        XCTAssertGreaterThanOrEqual(try imageFramePointCount(.fan), 16, "扇面图框应多段弧近似（≥16 点）")
    }

    func testFacingPagesSpreadImposition() throws {
        // E2-4：facingPages 开 → FacingPages=true + 首页单独成 spread、其后每 2 页一 spread；
        //        关 → FacingPages=false + 每页独占 spread（无回归）。
        let project = BookProject.sample
        let document = LayoutEngine().layout(project: project)
        func export(_ facing: Bool) throws -> (prefs: String, spreads: [String]) {
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent("layoutd-idml-facing-\(facing)-\(UUID().uuidString).idml")
            defer { try? FileManager.default.removeItem(at: output) }
            try IDMLExporter().export(document: document, project: project, to: output,
                                      options: IDMLExportOptions(facingPages: facing))
            let prefs = try entry(output, "Resources/Preferences.xml")
            let spreads = try zipEntries(output)
                .filter { $0.hasPrefix("Spreads/Spread_") }.sorted()
                .map { try entry(output, $0) }
            return (prefs, spreads)
        }
        func pageCount(_ spread: String) -> Int { matches(in: spread, pattern: "(<Page )").count }

        // 关：无回归——FacingPages=false，每个 spread 恰 1 页。
        let off = try export(false)
        XCTAssertTrue(off.prefs.contains("FacingPages=\"false\""))
        XCTAssertTrue(off.spreads.allSatisfy { pageCount($0) == 1 }, "非对开每 spread 应恰 1 页")

        // 开：FacingPages=true；首页 spread 1 页，存在 2 页 spread。
        let on = try export(true)
        XCTAssertTrue(on.prefs.contains("FacingPages=\"true\""))
        XCTAssertEqual(pageCount(on.spreads[0]), 1, "首页应单独成 spread（recto）")
        XCTAssertTrue(on.spreads.contains { pageCount($0) == 2 }, "应存在 2 页对开 spread")
        // verso 页框在书脊左（ItemTransform x = -pageW）。
        let twoPageSpread = try XCTUnwrap(on.spreads.first { pageCount($0) == 2 })
        let pageW = project.pageSetup.pageSize.width
        XCTAssertTrue(twoPageSpread.contains("ItemTransform=\"1 0 0 1 \(String(format: "%.3f", -pageW)) "),
                      "verso 页框应在书脊左侧 x=-pageW")
    }

    func testExportIsByteDeterministic() throws {
        // 导出必须确定：同一项目两次导出每个内部文件逐字节一致。
        // （否则 golden-file 回归基线对不上。曾因复合字体字典迭代顺序非确定而漂移。）
        let project = BookProject.sample
        let document = LayoutEngine().layout(project: project)
        func exportEntries() throws -> [String: String] {
            let out = FileManager.default.temporaryDirectory
                .appendingPathComponent("layoutd-idml-determinism-\(UUID().uuidString).idml")
            defer { try? FileManager.default.removeItem(at: out) }
            try IDMLExporter().export(document: document, project: project, to: out)
            var map: [String: String] = [:]
            for name in try zipEntries(out) { map[name] = try entry(out, name) }
            return map
        }
        let a = try exportEntries()
        let b = try exportEntries()
        XCTAssertEqual(a.keys.sorted(), b.keys.sorted(), "两次导出文件清单应一致")
        for key in a.keys.sorted() {
            XCTAssertEqual(a[key], b[key], "导出文件 \(key) 两次应逐字节一致（确定性）")
        }
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
            // `\s` guards against matching `<ParagraphStyleRange>` (or a future
            // style-like element) while inspecting the concrete style definition.
            let pattern = "(<ParagraphStyle\\s+[^>]*Self=\"ParagraphStyle/\(styleID)\"[^>]*KinsokuType=\"KinsokuPushInFirst\"[^>]*>[\\s\\S]*?<KinsokuSet type=\"enumeration\">SimplifiedChineseKinsoku</KinsokuSet>[\\s\\S]*?</ParagraphStyle>)"
            XCTAssertEqual(matches(in: styles, pattern: pattern).count, 1,
                           "段落样式 \(style.id) 未绑定 layoutD 禁则集")
        }
    }

    // MARK: - CMYK swatches (印刷路线 A：CMYK 原生色板)

    func testExportsCMYKBackgroundAsProcessCMYKSwatch() throws {
        let paragraph = Paragraph(kind: .body, text: "颜色", styleId: StyleID.body.rawValue)
        let project = BookProject(
            metadata: ProjectMetadata(title: "CMYK", author: "layoutD"),
            sections: [BookSection(title: "正文", stories: [Story(title: "正文", paragraphs: [paragraph])])]
        )
        let frame = PageFrame(
            kind: .text, rect: Rect(x: 20, y: 20, width: 200, height: 100),
            styleId: StyleID.body.rawValue, content: .text("颜色"),
            backgroundColorHex: "cmyk(20,0,80,0)", sourceParagraphId: paragraph.id
        )
        let document = LaidOutDocument(projectId: project.id, pages: [LaidOutPage(number: 1, frames: [frame])])
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-idml-cmyk-\(UUID().uuidString).idml")
        defer { try? FileManager.default.removeItem(at: output) }

        try IDMLExporter().export(document: document, project: project, to: output)

        let graphic = try entry(output, "Resources/Graphic.xml")
        XCTAssertTrue(graphic.contains("Self=\"Color/CMYK_20_0_80_0\""), "应生成 CMYK 色板 Self")
        XCTAssertTrue(graphic.contains("Space=\"CMYK\" ColorValue=\"20 0 80 0\""),
                      "CMYK 底色应导出为 Process CMYK 20 0 80 0，而非压回 RGB")
        // 页面项应引用这块 CMYK 色板。
        let spreads = try zipEntries(output).filter { $0.hasPrefix("Spreads/") }
            .map { try entry(output, $0) }.joined()
        XCTAssertTrue(spreads.contains("FillColor=\"Color/CMYK_20_0_80_0\""), "文本框应引用 CMYK 色板")
    }

    func testCMYKPureBlackReusesBuiltinBlackSwatch() throws {
        let paragraph = Paragraph(kind: .body, text: "黑", styleId: StyleID.body.rawValue)
        let project = BookProject(
            metadata: ProjectMetadata(title: "K100", author: "layoutD"),
            sections: [BookSection(title: "正文", stories: [Story(title: "正文", paragraphs: [paragraph])])]
        )
        let frame = PageFrame(
            kind: .text, rect: Rect(x: 20, y: 20, width: 200, height: 100),
            styleId: StyleID.body.rawValue, content: .text("黑"),
            backgroundColorHex: "cmyk(0,0,0,100)", sourceParagraphId: paragraph.id
        )
        let document = LaidOutDocument(projectId: project.id, pages: [LaidOutPage(number: 1, frames: [frame])])
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-idml-k100-\(UUID().uuidString).idml")
        defer { try? FileManager.default.removeItem(at: output) }

        try IDMLExporter().export(document: document, project: project, to: output)

        let graphic = try entry(output, "Resources/Graphic.xml")
        XCTAssertFalse(graphic.contains("Color/CMYK_0_0_0_100"), "纯黑 CMYK 应复用内建 Black，不再新建色板")
        let spreads = try zipEntries(output).filter { $0.hasPrefix("Spreads/") }
            .map { try entry(output, $0) }.joined()
        XCTAssertTrue(spreads.contains("FillColor=\"Color/Black\""), "纯黑 CMYK 底色应引用内建 Black")
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
