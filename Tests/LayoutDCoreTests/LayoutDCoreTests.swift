import LayoutDCore
import LayoutDDesignAI
import LayoutDEngine
import LayoutDCheck
import LayoutDImport
import XCTest

final class LayoutDCoreTests: XCTestCase {
    func testInlineRunsAttributedStringAndMapping() throws {
        let text = "Hello World"
        let runs = [
            InlineRun(location: 0, length: 5, emphasis: [.bold]),
            InlineRun(location: 6, length: 5, emphasis: [.italic])
        ]
        
        // 1. Test mapRuns to substring
        let mappedSubstring = InlineRun.mapRuns(runs, toSubstringFrom: 6, length: 5)
        XCTAssertEqual(mappedSubstring.count, 1)
        XCTAssertEqual(mappedSubstring[0].location, 0)
        XCTAssertEqual(mappedSubstring[0].length, 5)
        XCTAssertEqual(mappedSubstring[0].emphasis, [.italic])
        
        // 2. Test mapRuns by alignment
        let mappedAligned = InlineRun.mapRuns(runs, from: "Hello World", to: "Hello  World")
        XCTAssertNotNil(mappedAligned)
        XCTAssertEqual(mappedAligned?.count, 2)
        
        // 3. Test makeAttributedString
        let style = ParagraphStyle.body
        let attrString = ChineseTypesetting.makeAttributedString(
            text: text,
            style: style,
            inlineRuns: runs
        )
        
        // Retrieve font at index 0 (should be bold)
        var range = NSRange()
        let font0 = attrString.attribute(NSAttributedString.Key(kCTFontAttributeName as String), at: 0, effectiveRange: &range) as! CTFont
        let traits0 = CTFontGetSymbolicTraits(font0)
        XCTAssertTrue(traits0.contains(.boldTrait))
        
        // Retrieve font at index 6 (should have matrix/skew for italic)
        let font6 = attrString.attribute(NSAttributedString.Key(kCTFontAttributeName as String), at: 6, effectiveRange: &range) as! CTFont
        let matrix = CTFontGetMatrix(font6)
        XCTAssertEqual(matrix.c, CGFloat(tan(12.0 * Double.pi / 180.0)), accuracy: 0.001)
    }

    func testAnnotationsPersistenceAndMapping() throws {
        var project = BookProject(metadata: ProjectMetadata(title: "Test Project", author: "Antigravity"))
        XCTAssertEqual(project.safeAnnotations.count, 0)
        
        let ann = BookAnnotation(pageNumber: 2, x: 100.0, y: 150.0, text: "这里需要修改样式")
        project.safeAnnotations = [ann]
        XCTAssertEqual(project.safeAnnotations.count, 1)
        XCTAssertEqual(project.safeAnnotations[0].text, "这里需要修改样式")
        
        // Test JSON round-trip compatibility
        let data = try ProjectFile.encode(project)
        let decoded = try ProjectFile.decode(data)
        XCTAssertEqual(decoded.safeAnnotations.count, 1)
        XCTAssertEqual(decoded.safeAnnotations[0].pageNumber, 2)
        XCTAssertEqual(decoded.safeAnnotations[0].x, 100.0)
        XCTAssertEqual(decoded.safeAnnotations[0].y, 150.0)
        XCTAssertEqual(decoded.safeAnnotations[0].text, "这里需要修改样式")
        
        // Test legacy JSON decoding without annotations field
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "annotations")
        let legacyData = try JSONSerialization.data(withJSONObject: json)
        let legacyDecoded = try ProjectFile.decode(legacyData)
        XCTAssertEqual(legacyDecoded.safeAnnotations.count, 0)
    }

    func testParagraphInlineRunsRoundTripAndLegacyDecode() throws {
        let paragraph = Paragraph(
            kind: .body,
            text: "普通粗斜",
            styleId: StyleID.body.rawValue,
            inlineRuns: [
                InlineRun(location: 2, length: 1, emphasis: [.bold]),
                InlineRun(location: 3, length: 1, emphasis: [.italic])
            ]
        )
        let data = try JSONEncoder().encode(paragraph)
        XCTAssertEqual(try JSONDecoder().decode(Paragraph.self, from: data), paragraph)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "inlineRuns")
        let legacyData = try JSONSerialization.data(withJSONObject: json)
        XCTAssertNil(try JSONDecoder().decode(Paragraph.self, from: legacyData).inlineRuns)
    }

    func testSampleProjectEncodesAndDecodes() throws {
        let project = BookProject.sample
        let data = try ProjectFile.encode(project)
        let decoded = try ProjectFile.decode(data)
        XCTAssertEqual(decoded.metadata.title, project.metadata.title)
        XCTAssertEqual(decoded.sections.count, 1)
        XCTAssertEqual(decoded.assets.count, 1)
    }

    func testTableParsingAndAllocation() throws {
        let tableText = """
        结构    类比    主要作用
        细胞膜    城墙和门禁    控制物质进出
        线粒体    发电站    提供能量
        """
        
        let tableData = TableLayoutHelper.parseTableText(tableText)
        XCTAssertEqual(tableData.columnCount, 3)
        XCTAssertEqual(tableData.rows.count, 3)
        XCTAssertEqual(tableData.rows[0], ["结构", "类比", "主要作用"])
        XCTAssertEqual(tableData.rows[1], ["细胞膜", "城墙和门禁", "控制物质进出"])
        
        // Test column width allocation
        let style = ParagraphStyle.body
        let colWidths = TableLayoutHelper.allocateColumnWidths(
            tableData: tableData,
            totalWidth: 300.0,
            fontName: style.fontName,
            fontSize: style.fontSize
        )
        XCTAssertEqual(colWidths.count, 3)
        let sumWidths = colWidths.reduce(0, +)
        XCTAssertEqual(sumWidths, 300.0, accuracy: 0.001)
        
        // Assert first column width is less than third column width because of text lengths
        XCTAssertLessThan(colWidths[0], colWidths[2])
    }

    func testProjectMetadataDecodesLegacyFilesWithoutNewBookFields() throws {
        let legacyProject = BookProject(metadata: ProjectMetadata(title: "旧项目", author: "layoutD"))
        let encoded = try ProjectFile.encode(legacyProject)
        var json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        var metadata = json?["metadata"] as? [String: Any]
        metadata?.removeValue(forKey: "publisher")
        metadata?.removeValue(forKey: "isbn")
        metadata?.removeValue(forKey: "series")
        metadata?.removeValue(forKey: "keywords")
        json?["metadata"] = metadata

        let legacyData = try JSONSerialization.data(withJSONObject: json as Any)
        let project = try ProjectFile.decode(legacyData)

        XCTAssertEqual(project.metadata.title, "旧项目")
        XCTAssertNil(project.metadata.publisher)
        XCTAssertNil(project.metadata.isbn)
        XCTAssertNil(project.metadata.series)
        XCTAssertEqual(project.metadata.keywords, [])
    }

    func testStyleTemplatesProvideDistinctProjectLevelStyles() {
        XCTAssertEqual(StyleTemplate.allCases.count, 3)
        XCTAssertEqual(StyleTemplate.chineseScienceDefault.styleLibrary, .defaultChineseScience)

        let defaultBody = StyleTemplate.chineseScienceDefault.styleLibrary.paragraphStyle(id: StyleID.body.rawValue)
        let compactBody = StyleTemplate.compactStudyGuide.styleLibrary.paragraphStyle(id: StyleID.body.rawValue)
        let imageRichHeading = StyleTemplate.imageRichScience.styleLibrary.paragraphStyle(id: StyleID.heading1.rawValue)

        XCTAssertLessThan(compactBody.fontSize, defaultBody.fontSize)
        XCTAssertLessThan(compactBody.lineHeight, defaultBody.lineHeight)
        XCTAssertGreaterThan(imageRichHeading.fontSize, ParagraphStyle.heading1.fontSize)
    }

    func testLayoutEngineCreatesPagesAndFrames() {
        let document = LayoutEngine().layout(project: .sample)
        XCTAssertFalse(document.pages.isEmpty)
        XCTAssertFalse(document.pages[0].frames.isEmpty)
    }

    func testLayoutEngineAddsCoverAndContentsPages() {
        let document = LayoutEngine().layout(project: .sample)
        XCTAssertEqual(document.pages.first?.number, 1)
        XCTAssertEqual(document.pages[safe: 1]?.number, 2)
        XCTAssertTrue(document.pages.first?.frames.contains { $0.content == .text(BookProject.sample.metadata.title) } == true)
        XCTAssertTrue(document.pages[safe: 1]?.frames.contains { $0.content == .text("目录") } == true)
        XCTAssertTrue(document.pages[safe: 1]?.frames.contains { frame in
            if case .text(let text) = frame.content {
                return text.contains("第一章 重新理解图文排版  3")
            }
            return false
        } == true)
    }

    func testLayoutEngineAddsSpacingBetweenChineseAndWesternText() {
        let project = BookProject(
            metadata: ProjectMetadata(title: "中西文空隙", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .body, text: "细胞ATP可以通过3D模型观察", styleId: StyleID.body.rawValue)
                            ]
                        )
                    ]
                )
            ]
        )

        let document = LayoutEngine().layout(project: project)
        let bodyTexts = document.pages.flatMap(\.frames).compactMap { frame -> String? in
            guard frame.styleId == StyleID.body.rawValue, case .text(let text) = frame.content else {
                return nil
            }
            return text
        }

        XCTAssertTrue(bodyTexts.contains("细胞 ATP 可以通过 3D 模型观察"))
    }

    func testLayoutEngineDoesNotPlaceFigureAssetTwice() {
        let asset = Asset(
            fileName: "figure.png",
            role: .diagram,
            caption: "图 1 测试图",
            pixelWidth: 1200,
            pixelHeight: 800,
            dpi: 300
        )
        let project = BookProject(
            metadata: ProjectMetadata(title: "图文测试", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .figure(assetId: asset.id), text: "图 1 测试图", styleId: StyleID.caption.rawValue)
                            ]
                        )
                    ]
                )
            ],
            assets: [asset]
        )

        let document = LayoutEngine().layout(project: project)
        let imageFrames = document.pages.flatMap(\.frames).filter {
            if case .asset(asset.id) = $0.content {
                return true
            }
            return false
        }
        XCTAssertEqual(imageFrames.count, 1)
    }

    func testLayoutEngineDoesNotPlaceUnreferencedAssets() {
        let asset = Asset(
            fileName: "library-only.png",
            role: .diagram,
            caption: "素材库图片",
            pixelWidth: 1200,
            pixelHeight: 800,
            dpi: 300
        )
        let project = BookProject(
            metadata: ProjectMetadata(title: "素材库测试", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .body, text: "正文没有引用素材库图片。", styleId: StyleID.body.rawValue)
                            ]
                        )
                    ]
                )
            ],
            assets: [asset]
        )

        let frames = LayoutEngine().layout(project: project).pages.flatMap(\.frames)
        XCTAssertFalse(frames.contains { $0.content == .asset(asset.id) })
    }

    func testLayoutEnginePlacesAnchoredAssetAfterParagraph() {
        let asset = Asset(
            fileName: "anchored.png",
            role: .diagram,
            caption: "段落配图",
            pixelWidth: 1200,
            pixelHeight: 800,
            dpi: 300
        )
        let project = BookProject(
            metadata: ProjectMetadata(title: "锚定图片布局", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(
                                    kind: .body,
                                    text: "这段正文后面应该紧跟锚定图片。",
                                    styleId: StyleID.body.rawValue,
                                    anchoredAssetIds: [asset.id]
                                )
                            ]
                        )
                    ]
                )
            ],
            assets: [asset]
        )

        let frames = LayoutEngine().layout(project: project).pages.flatMap(\.frames)
        let bodyIndex = frames.firstIndex { frame in
            frame.content == .text("这段正文后面应该紧跟锚定图片。")
        }
        let assetIndex = frames.firstIndex { frame in
            frame.content == .asset(asset.id)
        }
        let captionIndex = frames.firstIndex { frame in
            frame.content == .text("图1 段落配图")
        }

        XCTAssertNotNil(bodyIndex)
        XCTAssertNotNil(assetIndex)
        XCTAssertNotNil(captionIndex)
        XCTAssertLessThan(bodyIndex ?? 0, assetIndex ?? 0)
        XCTAssertLessThan(assetIndex ?? 0, captionIndex ?? 0)
    }

    func testHeroImageGetsMoreVerticalSpaceThanDecorativeImage() {
        let hero = Asset(fileName: "hero.png", role: .hero, caption: "主图", pixelWidth: 1200, pixelHeight: 800, dpi: 300)
        let decorative = Asset(fileName: "decorative.png", role: .decorative, caption: "装饰图", pixelWidth: 1200, pixelHeight: 800, dpi: 300)
        let project = BookProject(
            metadata: ProjectMetadata(title: "图片尺寸测试", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .figure(assetId: hero.id), text: "主图", styleId: StyleID.caption.rawValue),
                                Paragraph(kind: .figure(assetId: decorative.id), text: "装饰图", styleId: StyleID.caption.rawValue)
                            ]
                        )
                    ]
                )
            ],
            assets: [hero, decorative]
        )

        let frames = LayoutEngine().layout(project: project).pages.flatMap(\.frames)
        let heroFrame = frames.first { $0.content == .asset(hero.id) }
        let decorativeFrame = frames.first { $0.content == .asset(decorative.id) }

        XCTAssertNotNil(heroFrame)
        XCTAssertNotNil(decorativeFrame)
        XCTAssertGreaterThan(heroFrame?.rect.height ?? 0, decorativeFrame?.rect.height ?? 0)
    }

    func testHeroImageSpansContentWidthWhileRegularImageUsesColumnWidth() {
        let hero = Asset(fileName: "hero.png", role: .hero, caption: "主图", pixelWidth: 2400, pixelHeight: 1200, dpi: 300)
        let diagram = Asset(fileName: "diagram.png", role: .diagram, caption: "示意图", pixelWidth: 1200, pixelHeight: 800, dpi: 300)
        let project = BookProject(
            metadata: ProjectMetadata(title: "跨栏图片", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .figure(assetId: hero.id), text: "主图", styleId: StyleID.caption.rawValue),
                                Paragraph(kind: .figure(assetId: diagram.id), text: "示意图", styleId: StyleID.caption.rawValue)
                            ]
                        )
                    ]
                )
            ],
            assets: [hero, diagram]
        )

        let frames = LayoutEngine().layout(project: project).pages.flatMap(\.frames)
        let heroFrame = frames.first { $0.content == .asset(hero.id) }
        let diagramFrame = frames.first { $0.content == .asset(diagram.id) }
        let contentWidth = project.pageSetup.pageSize.width
            - project.pageSetup.margins.left
            - project.pageSetup.margins.right
        let columnWidth = (contentWidth - project.pageSetup.gutter) / 2

        XCTAssertNotNil(heroFrame)
        XCTAssertNotNil(diagramFrame)
        XCTAssertEqual(heroFrame?.rect.width ?? 0, contentWidth, accuracy: 0.01)
        XCTAssertEqual(diagramFrame?.rect.width ?? 0, columnWidth, accuracy: 0.01)
        XCTAssertGreaterThan(heroFrame?.rect.width ?? 0, diagramFrame?.rect.width ?? 0)
    }

    func testTextAfterWideImageDoesNotRestartAboveImageInSecondColumn() {
        let hero = Asset(fileName: "hero.png", role: .hero, caption: "主图", pixelWidth: 2400, pixelHeight: 1200, dpi: 300)
        let followingParagraphs = (0..<18).map { index in
            Paragraph(
                kind: .body,
                text: "第\(index)段：这是跨栏图片之后的正文，用来填充左栏并进入右栏，验证右栏起点不会回到跨栏图片上方。",
                styleId: StyleID.body.rawValue
            )
        }
        let project = BookProject(
            metadata: ProjectMetadata(title: "跨栏避让", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .figure(assetId: hero.id), text: "主图", styleId: StyleID.caption.rawValue)
                            ] + followingParagraphs
                        )
                    ]
                )
            ],
            assets: [hero]
        )

        let document = LayoutEngine().layout(project: project)
        let contentWidth = project.pageSetup.pageSize.width
            - project.pageSetup.margins.left
            - project.pageSetup.margins.right
        let page = document.pages.first { page in
            page.frames.contains { $0.content == .asset(hero.id) }
        }
        let heroFrame = page?.frames.first { $0.content == .asset(hero.id) }
        let heroBottom = (heroFrame?.rect.y ?? 0) + (heroFrame?.rect.height ?? 0)
        let rightColumnTextFrames = page?.frames.filter { frame in
            frame.kind == .text
                && frame.styleId == StyleID.body.rawValue
                && frame.rect.x > project.pageSetup.margins.left + contentWidth / 2
        } ?? []

        XCTAssertFalse(rightColumnTextFrames.isEmpty)
        XCTAssertTrue(rightColumnTextFrames.allSatisfy { $0.rect.y >= heroBottom })
    }

    func testLayoutEngineNumbersFigureCaptions() {
        let first = Asset(fileName: "first.png", role: .diagram, caption: "线粒体示意图", pixelWidth: 1200, pixelHeight: 800, dpi: 300)
        let second = Asset(fileName: "second.png", role: .diagram, caption: "图2 已编号图注", pixelWidth: 1200, pixelHeight: 800, dpi: 300)
        let project = BookProject(
            metadata: ProjectMetadata(title: "图注编号", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .figure(assetId: first.id), text: "线粒体示意图", styleId: StyleID.caption.rawValue),
                                Paragraph(kind: .figure(assetId: second.id), text: "图2 已编号图注", styleId: StyleID.caption.rawValue)
                            ]
                        )
                    ]
                )
            ],
            assets: [first, second]
        )

        let captions = LayoutEngine().layout(project: project)
            .pages
            .flatMap(\.frames)
            .compactMap { frame -> String? in
                guard frame.kind == .caption, case .text(let text) = frame.content else {
                    return nil
                }
                return text
            }

        XCTAssertTrue(captions.contains("图1 线粒体示意图"))
        XCTAssertTrue(captions.contains("图2 已编号图注"))
    }

    func testLayoutEngineCreatesTableFrames() {
        let project = BookProject(
            metadata: ProjectMetadata(title: "表格 frame", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .table, text: "指标    数值\n细胞数量    约 37 万亿", styleId: StyleID.body.rawValue)
                            ]
                        )
                    ]
                )
            ]
        )

        let frames = LayoutEngine().layout(project: project).pages.flatMap(\.frames)

        XCTAssertTrue(frames.contains { $0.kind == .table })
    }

    func testLayoutEngineKeepsHeadingsAwayFromColumnBottom() {
        let setup = PageSetup(
            pageSize: PageSize(width: 320, height: 250, label: "test"),
            margins: PageMargins(top: 30, right: 30, bottom: 30, left: 30),
            columns: 1,
            gutter: 0,
            baselineGrid: 10,
            facingPages: false
        )
        let filler = (0..<8).map { index in
            Paragraph(kind: .body, text: "填充段落 \(index)。", styleId: StyleID.body.rawValue)
        }
        let project = BookProject(
            metadata: ProjectMetadata(title: "标题避孤", author: "layoutD"),
            pageSetup: setup,
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: filler + [
                                Paragraph(kind: .heading(level: 2), text: "不应出现在栏底的标题", styleId: StyleID.heading2.rawValue),
                                Paragraph(kind: .body, text: "标题后的正文。", styleId: StyleID.body.rawValue)
                            ]
                        )
                    ]
                )
            ]
        )

        let document = LayoutEngine().layout(project: project)
        let headingFrame = document.pages
            .flatMap(\.frames)
            .first { $0.content == .text("不应出现在栏底的标题") }
        let bottomLimit = setup.pageSize.height - setup.margins.bottom
        let minimumFollowingTextHeight = ParagraphStyle.body.lineHeight * 2

        XCTAssertNotNil(headingFrame)
        XCTAssertLessThanOrEqual(
            (headingFrame?.rect.y ?? 0) + (headingFrame?.rect.height ?? 0) + minimumFollowingTextHeight,
            bottomLimit
        )
    }

    func testVeryLongParagraphReportsOverflowRisk() {
        let longText = String(repeating: "这是一个非常长的中文段落，用来测试单栏高度溢出的检测能力。", count: 180)
        let project = BookProject(
            metadata: ProjectMetadata(title: "长文测试", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .body, text: longText, styleId: StyleID.body.rawValue)
                            ]
                        )
                    ]
                )
            ]
        )

        let document = LayoutEngine().layout(project: project)
        XCTAssertTrue(document.issues.contains { $0.message.contains("文本段落高度超过单栏可用高度") })

        let bodyFrames = document.pages
            .flatMap(\.frames)
            .filter { $0.styleId == StyleID.body.rawValue }
        let maxBodyHeight = project.pageSetup.pageSize.height
            - project.pageSetup.margins.top
            - project.pageSetup.margins.bottom

        XCTAssertGreaterThan(bodyFrames.count, 1)
        XCTAssertTrue(bodyFrames.allSatisfy { $0.rect.height <= maxBodyHeight })
    }

    func testAdvisorReturnsStructuredLayoutPlans() {
        let plans = RuleBasedLayoutAdvisor().proposePlans(for: .sample, target: .page(1))
        XCTAssertEqual(plans.count, 6)
        XCTAssertTrue(plans.allSatisfy { !$0.blocks.isEmpty })
    }

    func testPageLayoutTemplatesProduceValidNormalizedBlocks() {
        for template in PageLayoutTemplate.allCases {
            let plan = template.makePlan(
                target: .page(1),
                projectTitle: BookProject.sample.metadata.title,
                primaryAsset: BookProject.sample.assets.first
            )

            XCTAssertNotNil(plan, template.displayName)
            XCTAssertEqual(plan?.strategy, template.strategy)
            XCTAssertTrue(plan?.blocks.isEmpty == false)

            for block in plan?.blocks ?? [] {
                XCTAssertGreaterThan(block.frame.width, 0)
                XCTAssertGreaterThan(block.frame.height, 0)
                XCTAssertGreaterThanOrEqual(block.frame.x, 0)
                XCTAssertGreaterThanOrEqual(block.frame.y, 0)
                XCTAssertLessThanOrEqual(block.frame.x + block.frame.width, 1)
                XCTAssertLessThanOrEqual(block.frame.y + block.frame.height, 1)
            }
        }
    }

    func testPageLayoutTemplateCatalogSkipsImageTemplatesWithoutAssets() {
        var project = BookProject.sample
        project.assets = []

        let plans = PageLayoutTemplateCatalog().plans(for: project, target: .page(1))

        XCTAssertEqual(plans.map(\.strategy), [.textLed, .textLed, .knowledgeCard, .knowledgeCard])
        XCTAssertFalse(plans.flatMap(\.blocks).contains { block in
            if case .asset = block.contentReference { return true }
            return false
        })
    }

    func testChapterLayoutTemplateCreatesPageKeyedPlanSet() {
        let project = BookProject.sample
        let section = project.sections[0]

        let planSet = ChapterLayoutTemplate.imageRichChapter.makePlanSet(
            for: section,
            in: project,
            startPage: 4
        )

        XCTAssertEqual(planSet.template, .imageRichChapter)
        XCTAssertEqual(planSet.sectionId, section.id)
        XCTAssertEqual(planSet.plansByPage.keys.sorted(), [4, 5, 6])
        XCTAssertEqual(planSet.plansByPage[4]?.target, .page(4))
        XCTAssertEqual(planSet.plansByPage[4]?.strategy, .imageLed)
        XCTAssertTrue(planSet.plansByPage.values.allSatisfy { !$0.blocks.isEmpty })
    }

    func testChapterLayoutTemplateSkipsUnavailableImagePages() {
        var project = BookProject.sample
        project.assets = []
        let section = project.sections[0]

        let planSet = ChapterLayoutTemplate.imageRichChapter.makePlanSet(
            for: section,
            in: project,
            startPage: 8
        )

        XCTAssertEqual(planSet.plansByPage.keys.sorted(), [10])
        XCTAssertEqual(planSet.plansByPage[10]?.strategy, .textLed)
    }

    func testApplyingChapterLayoutTemplateStoresPlansInProject() {
        var project = BookProject.sample

        let appliedCount = project.applyChapterLayoutTemplate(
            .scienceChapter,
            sectionIndex: 0,
            startPage: 5
        )

        XCTAssertEqual(appliedCount, 3)
        XCTAssertEqual(project.safeAppliedLayoutPlans.keys.sorted(), [5, 6, 7])
        XCTAssertEqual(project.safeAppliedLayoutPlans[5]?.strategy, .textLed)
        XCTAssertEqual(project.safeAppliedLayoutPlans[6]?.strategy, .balanced)
        XCTAssertEqual(project.safeAppliedLayoutPlans[7]?.strategy, .knowledgeCard)
    }

    func testApplyingChapterLayoutTemplateSkipsInvalidSectionIndex() {
        var project = BookProject.sample

        let appliedCount = project.applyChapterLayoutTemplate(
            .studyGuideChapter,
            sectionIndex: 99,
            startPage: 3
        )

        XCTAssertEqual(appliedCount, 0)
        XCTAssertTrue(project.safeAppliedLayoutPlans.isEmpty)
    }

    func testLayoutPlanRequestBuildsSemanticContext() {
        let request = LayoutPlanRequest(project: .sample, target: .page(3))

        XCTAssertEqual(request.context.title, BookProject.sample.metadata.title)
        XCTAssertEqual(request.context.sectionSummaries.first?.title, "第一章 重新理解图文排版")
        XCTAssertEqual(request.context.sectionSummaries.first?.storyTitles, ["图像不只是正文的附件"])
        XCTAssertEqual(request.context.sectionSummaries.first?.paragraphCount, 4)
        XCTAssertEqual(request.context.sectionSummaries.first?.calloutCount, 1)
        XCTAssertEqual(request.context.assetSummaries.first?.fileName, "sample-diagram.png")
        XCTAssertEqual(request.context.assetSummaries.first?.role, AssetRole.diagram.rawValue)
    }

    func testProviderBackedAdvisorUsesProviderPlans() {
        let expectedPlan = LayoutPlan(
            target: .page(5),
            strategy: .knowledgeCard,
            blocks: [
                LayoutPlanBlock(
                    kind: .component,
                    role: "knowledge-card",
                    frame: Rect(x: 0.1, y: 0.2, width: 0.8, height: 0.2),
                    contentReference: .generated("模型生成的知识卡片")
                )
            ],
            notes: ["provider"]
        )
        let advisor = ProviderBackedLayoutAdvisor(provider: StaticPlanProvider(plans: [expectedPlan]))

        let plans = advisor.proposePlans(for: .sample, target: .page(5))

        XCTAssertEqual(plans, [expectedPlan])
    }

    func testProviderBackedAdvisorFallsBackWhenProviderFails() {
        let advisor = ProviderBackedLayoutAdvisor(provider: FailingPlanProvider())

        let plans = advisor.proposePlans(for: .sample, target: .page(2))

        XCTAssertEqual(plans.count, 6)
        XCTAssertTrue(plans.contains { $0.strategy == .imageLed })
    }

    func testLayoutPlanAppliedSuccessfully() {
        let planBlock = LayoutPlanBlock(
            kind: .text,
            role: "body",
            frame: Rect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
            contentReference: .generated("被应用的布局内容")
        )
        let plan = LayoutPlan(
            target: .page(3),
            strategy: .textLed,
            blocks: [planBlock],
            notes: ["计划测试"]
        )
        
        var project = BookProject.sample
        project.safeAppliedLayoutPlans = [3: plan]
        
        let document = LayoutEngine().layout(project: project)
        
        XCTAssertTrue(document.pages.count >= 3)
        let page3 = document.pages[2]
        
        let customFrames = page3.frames.filter { frame in
            if case .text(let t) = frame.content {
                return t == "被应用的布局内容"
            }
            return false
        }
        XCTAssertEqual(customFrames.count, 1)
        
        let customFrame = customFrames[0]
        let pageSize = project.pageSetup.pageSize
        XCTAssertEqual(customFrame.rect.x, 0.1 * pageSize.width)
        XCTAssertEqual(customFrame.rect.y, 0.1 * pageSize.height)
        XCTAssertEqual(customFrame.rect.width, 0.8 * pageSize.width)
        XCTAssertEqual(customFrame.rect.height, 0.8 * pageSize.height)
    }

    func testEmptyLayoutPlanReservesPage() {
        var project = BookProject.sample
        project.safeAppliedLayoutPlans = [
            3: LayoutPlan(target: .page(3), strategy: .balanced, blocks: [])
        ]

        let document = LayoutEngine().layout(project: project)
        let page3Text = document.pages
            .first(where: { $0.number == 3 })?
            .frames
            .compactMap { frame -> String? in
                if case .text(let text) = frame.content {
                    return text
                }
                return nil
            }
            .joined(separator: "\n") ?? ""
        let page4Text = document.pages
            .first(where: { $0.number == 4 })?
            .frames
            .compactMap { frame -> String? in
                if case .text(let text) = frame.content {
                    return text
                }
                return nil
            }
            .joined(separator: "\n") ?? ""

        XCTAssertFalse(page3Text.contains("第一章 重新理解图文排版"))
        XCTAssertTrue(page4Text.contains("第一章 重新理解图文排版"))
    }

    func testSavedLayoutTemplateRetargetsPlanAndRegeneratesBlockIDs() {
        let block = LayoutPlanBlock(
            kind: .component,
            role: "knowledge-card",
            frame: Rect(x: 0.12, y: 0.56, width: 0.76, height: 0.22),
            contentReference: .generated("复用模板")
        )
        let plan = LayoutPlan(
            target: .page(2),
            strategy: .knowledgeCard,
            blocks: [block],
            notes: ["saved"]
        )
        let template = SavedLayoutTemplate(name: "章节复习卡", plan: plan)

        let reused = template.makePlan(target: .page(9))

        XCTAssertEqual(reused.target, .page(9))
        XCTAssertEqual(reused.strategy, plan.strategy)
        XCTAssertEqual(reused.blocks.map(\.frame), plan.blocks.map(\.frame))
        XCTAssertNotEqual(reused.blocks.first?.id, block.id)
    }

    func testProjectStoresSavedLayoutTemplates() {
        let plan = PageLayoutTemplate.knowledgeCardPage.makePlan(
            target: .page(1),
            projectTitle: BookProject.sample.metadata.title
        )
        XCTAssertNotNil(plan)

        var project = BookProject.sample
        project.safeSavedLayoutTemplates = [
            SavedLayoutTemplate(name: "知识卡片", plan: plan!)
        ]

        XCTAssertEqual(project.safeSavedLayoutTemplates.count, 1)
        XCTAssertEqual(project.safeSavedLayoutTemplates.first?.name, "知识卡片")
        XCTAssertEqual(project.safeSavedLayoutTemplates.first?.plan.strategy, .knowledgeCard)
    }

    func testLayoutTemplateLibraryRoundTripsSavedTemplates() throws {
        let plan = LayoutPlan(
            target: .page(1),
            strategy: .textLed,
            blocks: [
                LayoutPlanBlock(
                    kind: .text,
                    role: "body",
                    frame: Rect(x: 0.1, y: 0.1, width: 0.8, height: 0.7),
                    contentReference: .generated("模板正文")
                )
            ]
        )
        var project = BookProject.sample
        project.safeSavedLayoutTemplates = [
            SavedLayoutTemplate(name: "正文模板", plan: plan)
        ]

        let data = try LayoutTemplateLibrary.encode(LayoutTemplateLibrary(project: project))
        let decoded = try LayoutTemplateLibrary.decode(data)

        XCTAssertEqual(decoded.formatVersion, 1)
        XCTAssertEqual(decoded.sourceProjectTitle, project.metadata.title)
        XCTAssertEqual(decoded.templates.map(\.name), ["正文模板"])
        XCTAssertEqual(decoded.templates.first?.plan.strategy, .textLed)
    }

    func testImportingLayoutTemplateLibraryAvoidsDuplicateIDsAndNames() {
        let plan = LayoutPlan(target: .page(1), strategy: .knowledgeCard, blocks: [])
        let existing = SavedLayoutTemplate(name: "复习卡", plan: plan)
        let importedDuplicateID = SavedLayoutTemplate(id: existing.id, name: "复习卡", plan: plan)
        let importedNameConflict = SavedLayoutTemplate(name: "复习卡", plan: plan)
        let importedUnique = SavedLayoutTemplate(name: "图文模板", plan: plan)

        var project = BookProject.sample
        project.safeSavedLayoutTemplates = [existing]
        project.importLayoutTemplateLibrary(
            LayoutTemplateLibrary(
                templates: [importedDuplicateID, importedNameConflict, importedUnique]
            )
        )

        XCTAssertEqual(project.safeSavedLayoutTemplates.count, 3)
        XCTAssertEqual(project.safeSavedLayoutTemplates.map(\.name), ["复习卡", "复习卡 2", "图文模板"])
    }

    func testChineseLineBreakTypesetting() {
        let textWithStartViolations = "这是一个非常长的中文测试段落，用来验证排版引擎是否会自动调整行末或行首的避头尾禁则规则。例如：这个位置会发生断行，并且断行后，下一行的第一个字不应该是一个逗号。"
        
        var project = BookProject.sample
        project.sections = [
            BookSection(
                title: "测试禁则",
                stories: [
                    Story(
                        title: "正文",
                        paragraphs: [
                            Paragraph(
                                kind: .body,
                                text: textWithStartViolations,
                                styleId: StyleID.body.rawValue
                            )
                        ]
                    )
                ]
            )
        ]
        
        let document = LayoutEngine().layout(project: project)
        let inspector = ProjectInspector()
        let report = inspector.preflight(project: project, document: document)
        
        let violations = report.issues.filter { $0.message.contains("存在中文禁则问题") }
        XCTAssertEqual(violations.count, 0, "There should be no Chinese line break violations in the preflight report after engine adjustments")
    }

    func testChineseLineBreakRulesCoverCommonQuotesAndBrackets() {
        XCTAssertTrue(ChineseLineBreakRules.forbidsLineStart("”"))
        XCTAssertTrue(ChineseLineBreakRules.forbidsLineStart("’"))
        XCTAssertTrue(ChineseLineBreakRules.forbidsLineStart("〉"))
        XCTAssertTrue(ChineseLineBreakRules.forbidsLineStart("〕"))
        XCTAssertTrue(ChineseLineBreakRules.forbidsLineEnd("“"))
        XCTAssertTrue(ChineseLineBreakRules.forbidsLineEnd("‘"))
        XCTAssertTrue(ChineseLineBreakRules.forbidsLineEnd("〈"))
        XCTAssertTrue(ChineseLineBreakRules.forbidsLineEnd("〔"))
        XCTAssertFalse(ChineseLineBreakRules.forbidsLineStart("中"))
        XCTAssertFalse(ChineseLineBreakRules.forbidsLineEnd("文"))
    }

    func testOrphanLineControlPushesParagraphToNextColumn() {
        var project = BookProject.sample
        project.pageSetup = PageSetup(
            pageSize: PageSize(width: 185, height: 104, label: "Test Size"),
            margins: PageMargins(top: 20, right: 20, bottom: 20, left: 20),
            columns: 1,
            gutter: 7,
            baselineGrid: 16,
            facingPages: false
        )
        
        var bodyStyle = ParagraphStyle.body
        bodyStyle.lineHeight = 16
        bodyStyle.spaceAfter = 0
        bodyStyle.spaceBefore = 0
        project.styles.paragraphStyles = [bodyStyle]
        
        project.sections = [
            BookSection(
                title: "测试孤行",
                stories: [
                    Story(
                        title: "正文",
                        paragraphs: [
                            Paragraph(kind: .body, text: "一二三四五六七八九十一二三四五六七八九十", styleId: StyleID.body.rawValue),
                            Paragraph(kind: .body, text: "这里是第二段的内容，它非常长，会被折成两行排版。一二三四五", styleId: StyleID.body.rawValue)
                        ]
                    )
                ]
            )
        ]
        
        let document = LayoutEngine().layout(project: project)
        
        XCTAssertTrue(document.pages.count >= 5)
        let page4 = document.pages[3]
        let page5 = document.pages[4]
        
        let p1Frames = page4.frames.filter { $0.styleId == StyleID.body.rawValue }
        XCTAssertEqual(p1Frames.count, 1)
        
        let p2Frames = page5.frames.filter { $0.styleId == StyleID.body.rawValue }
        XCTAssertGreaterThan(p2Frames.count, 0)
    }

    func testWidowLineControlPullsLineToNextColumn() {
        var project = BookProject.sample
        project.pageSetup = PageSetup(
            pageSize: PageSize(width: 185, height: 88, label: "Test Size"),
            margins: PageMargins(top: 20, right: 20, bottom: 20, left: 20),
            columns: 1,
            gutter: 7,
            baselineGrid: 16,
            facingPages: false
        )
        
        var bodyStyle = ParagraphStyle.body
        bodyStyle.lineHeight = 16
        bodyStyle.spaceAfter = 0
        bodyStyle.spaceBefore = 0
        project.styles.paragraphStyles = [bodyStyle]
        
        project.sections = [
            BookSection(
                title: "测试寡行",
                stories: [
                    Story(
                        title: "正文",
                        paragraphs: [
                            Paragraph(kind: .body, text: "这里是第一段非常长的正文它一共需要折行成为四行文字来进行排版测试一二三四五六七八", styleId: StyleID.body.rawValue)
                        ]
                    )
                ]
            )
        ]
        
        let document = LayoutEngine().layout(project: project)
        
        XCTAssertTrue(document.pages.count >= 6)
        let page5 = document.pages[4]
        
        let bodyFrames = page5.frames.filter { $0.styleId == StyleID.body.rawValue }
        XCTAssertEqual(bodyFrames.count, 1)
        if bodyFrames.count > 0 {
            XCTAssertEqual(bodyFrames[0].rect.height, 32.0)
        }
    }

    func testFacingPagesMarginAsymmetry() {
        var project = BookProject(
            metadata: ProjectMetadata(title: "对称边距测试", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .body, text: String(repeating: "这是测试对开页左右边距不对称的一段非常长的占位文字，我们需要它足够长以流到下一页。 ", count: 150), styleId: StyleID.body.rawValue)
                            ]
                        )
                    ]
                )
            ]
        )
        project.pageSetup.facingPages = true
        project.pageSetup.margins = PageMargins(top: 20, right: 15, bottom: 20, left: 30)
        
        let document = LayoutEngine().layout(project: project)
        // Check page 3 (odd page) - should have left margin 30
        let page3 = document.pages.first { $0.number == 3 }
        XCTAssertNotNil(page3)
        if let page3 = page3 {
            let bodyFrames = page3.frames.filter { $0.kind == .text && $0.rect.y > 30 }
            for frame in bodyFrames {
                XCTAssertEqual(frame.rect.x, 30.0, accuracy: 0.1)
            }
        }
        
        // Check page 4 (even page) - should have left margin 15
        let page4 = document.pages.first { $0.number == 4 }
        XCTAssertNotNil(page4)
        if let page4 = page4 {
            let bodyFrames = page4.frames.filter { $0.kind == .text && $0.rect.y > 30 }
            for frame in bodyFrames {
                XCTAssertEqual(frame.rect.x, 15.0, accuracy: 0.1)
            }
        }
    }

    func testLockedPageRetainsLayoutPlans() {
        var project = BookProject(
            metadata: ProjectMetadata(title: "锁定测试", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "故事",
                            paragraphs: [
                                Paragraph(kind: .body, text: String(repeating: "这是测试第一段非常长的正文占位符。 ", count: 25), styleId: StyleID.body.rawValue),
                                Paragraph(kind: .body, text: String(repeating: "这是测试第二段非常长的正文占位符。 ", count: 25), styleId: StyleID.body.rawValue),
                                Paragraph(kind: .body, text: String(repeating: "这是测试第三段非常长的正文占位符。 ", count: 25), styleId: StyleID.body.rawValue),
                                Paragraph(kind: .body, text: String(repeating: "这是测试第四段非常长的正文占位符。 ", count: 25), styleId: StyleID.body.rawValue)
                            ]
                        )
                    ]
                )
            ]
        )
        // Lay out once
        let engine = LayoutEngine()
        let doc1 = engine.layout(project: project)
        XCTAssertGreaterThanOrEqual(doc1.pages.count, 4)
        
        let originalPage4Frames = doc1.pages.first { $0.number == 4 }?.frames ?? []
        XCTAssertFalse(originalPage4Frames.isEmpty)
        
        // Manually lock page 4 using a LayoutPlan helper
        let plan = freezePageToPlan(pageNum: 4, project: project, laidOutDocument: doc1)
        var locked = project.lockedPages ?? []
        locked.insert(4)
        project.lockedPages = locked
        
        var plans = project.appliedLayoutPlans ?? [:]
        plans[4] = plan
        project.appliedLayoutPlans = plans
        
        // Now, add a lot of text to the first paragraph (page 3)
        if var section = project.sections.first,
           var story = section.stories.first,
           !story.paragraphs.isEmpty {
            story.paragraphs[0].text = String(repeating: "这是额外插入的非常长的文字，会把原本属于第三页的内容往后挤压。 ", count: 80)
            section.stories[0] = story
            project.sections[0] = section
        }
        
        // Relayout the project with the locked page 4 layout plan
        let doc2 = engine.layout(project: project)
        
        let newPage4Frames = doc2.pages.first { $0.number == 4 }?.frames ?? []
        XCTAssertFalse(newPage4Frames.isEmpty)
        
        // The frames of page 4 must be identical in content and geometry to the original page 4 frames!
        XCTAssertEqual(newPage4Frames.count, originalPage4Frames.count)
        for i in 0..<newPage4Frames.count {
            let f1 = originalPage4Frames[i]
            let f2 = newPage4Frames[i]
            XCTAssertEqual(f1.rect.x, f2.rect.x, accuracy: 0.01)
            XCTAssertEqual(f1.rect.y, f2.rect.y, accuracy: 0.01)
            XCTAssertEqual(f1.rect.width, f2.rect.width, accuracy: 0.01)
            XCTAssertEqual(f1.rect.height, f2.rect.height, accuracy: 0.01)
            XCTAssertEqual(f1.content, f2.content)
        }
    }

    func testLayoutPlanBlockFrameEditingClampsToPageBounds() {
        let pageSize = PageSize(width: 200, height: 300, label: "test")
        var block = LayoutPlanBlock(
            kind: .image,
            role: "image",
            frame: Rect(x: 0.25, y: 0.25, width: 0.25, height: 0.25),
            contentReference: .generated("image")
        )

        block.updateAbsoluteFrame(pageSize: pageSize, x: -40, y: -20, width: 500, height: 500)

        let frame = block.absoluteFrame(pageSize: pageSize)
        XCTAssertEqual(frame.x, 0, accuracy: 0.01)
        XCTAssertEqual(frame.y, 0, accuracy: 0.01)
        XCTAssertEqual(frame.width, 200, accuracy: 0.01)
        XCTAssertEqual(frame.height, 300, accuracy: 0.01)
    }

    func testLayoutPlanBlockFrameEditingPreservesMinimumSize() {
        let pageSize = PageSize(width: 200, height: 300, label: "test")
        var block = LayoutPlanBlock(
            kind: .text,
            role: "text",
            frame: Rect(x: 0.5, y: 0.5, width: 0.25, height: 0.25),
            contentReference: .generated("正文")
        )

        block.updateAbsoluteFrame(pageSize: pageSize, x: 190, y: 290, width: -5, height: 0)

        let frame = block.absoluteFrame(pageSize: pageSize)
        XCTAssertEqual(frame.width, 12, accuracy: 0.01)
        XCTAssertEqual(frame.height, 12, accuracy: 0.01)
        XCTAssertEqual(frame.x, 188, accuracy: 0.01)
        XCTAssertEqual(frame.y, 288, accuracy: 0.01)
    }

    func testLayoutPlanBlockFrameEditingNormalizesNonFiniteValues() {
        let pageSize = PageSize(width: 200, height: 300, label: "test")
        var block = LayoutPlanBlock(
            kind: .text,
            role: "text",
            frame: Rect(x: .infinity, y: .nan, width: .infinity, height: -.infinity),
            contentReference: .generated("正文")
        )

        block.updateAbsoluteFrame(pageSize: pageSize)

        let frame = block.absoluteFrame(pageSize: pageSize)
        XCTAssertEqual(frame.x, 0, accuracy: 0.01)
        XCTAssertEqual(frame.y, 0, accuracy: 0.01)
        XCTAssertEqual(frame.width, 12, accuracy: 0.01)
        XCTAssertEqual(frame.height, 12, accuracy: 0.01)
    }

    private func freezePageToPlan(pageNum: Int, project: BookProject, laidOutDocument: LaidOutDocument) -> LayoutPlan {
        let pageSize = project.pageSetup.pageSize
        let docPages = laidOutDocument.pages
        guard let targetPage = docPages.first(where: { $0.number == pageNum }) else {
            return LayoutPlan(target: .page(pageNum), strategy: .balanced, blocks: [])
        }
        
        var blocks: [LayoutPlanBlock] = []
        
        for frame in targetPage.frames {
            if frame.kind == .runningHeader {
                continue
            }

            let normX = frame.rect.x / pageSize.width
            let normY = frame.rect.y / pageSize.height
            let normW = frame.rect.width / pageSize.width
            let normH = frame.rect.height / pageSize.height
            
            let kind: LayoutBlockKind
            switch frame.kind {
            case .text: kind = .text
            case .image: kind = .image
            case .caption: kind = .caption
            case .callout: kind = .component
            case .table: kind = .component
            case .footnote: kind = .text
            case .footnoteDivider: kind = .component
            case .sideNote: kind = .text
            case .runningHeader: kind = .text
            }

            let ref: ContentReference
            switch frame.content {
            case .asset(let assetId), .spreadAsset(let assetId, _):
                ref = .asset(assetId)
            case .text(let text):
                if let pid = frame.sourceParagraphId {
                    ref = .paragraph(pid)
                } else {
                    var foundId: UUID?
                    for section in project.sections {
                        for story in section.stories {
                            for paragraph in story.paragraphs {
                                if paragraph.text == text {
                                    foundId = paragraph.id
                                    break
                                }
                            }
                            if foundId != nil { break }
                        }
                        if foundId != nil { break }
                    }
                    if let pid = foundId {
                        ref = .paragraph(pid)
                    } else {
                        ref = .generated(text)
                    }
                }
            case .empty:
                ref = .generated("")
            }
            
            let block = LayoutPlanBlock(
                id: frame.id,
                kind: kind,
                role: frame.kind.rawValue,
                frame: Rect(x: normX, y: normY, width: normW, height: normH),
                contentReference: ref
            )
            blocks.append(block)
        }
        
        return LayoutPlan(target: .page(pageNum), strategy: .balanced, blocks: blocks, notes: ["手动自定义版式页"])
    }

    func testChinesePunctuationCompression() {
        let text = "测），试"
        let attrString = NSMutableAttributedString(string: text)
        ChineseTypesetting.applyPunctuationCompression(to: attrString, fontSize: 16.0)

        // Index 1 is the closing parenthesis '）'.
        let attrs = attrString.attributes(at: 1, effectiveRange: nil)
        let kern = attrs[NSAttributedString.Key(kCTKernAttributeName as String)] as? Double
        XCTAssertNotNil(kern)
        XCTAssertEqual(kern!, -8.0)
    }

    func testSpreadImagePlacement() {
        let setup = PageSetup(
            pageSize: PageSize(width: 200, height: 300, label: "test"),
            margins: PageMargins(top: 20, right: 20, bottom: 20, left: 20),
            columns: 1,
            gutter: 0,
            baselineGrid: 10,
            facingPages: true
        )
        let assetId = UUID()
        let asset = Asset(
            id: assetId,
            fileName: "spread.png",
            sourcePath: nil,
            role: .spread,
            caption: "跨页大图图注",
            pixelWidth: 800,
            pixelHeight: 400
        )
        let project = BookProject(
            metadata: ProjectMetadata(title: "跨页测试", author: "layoutD"),
            pageSetup: setup,
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "正文",
                            paragraphs: [
                                Paragraph(kind: .body, text: "正文第一段，先占一部分空间。这是为了测试跨页大图是否能自动翻页到偶数页开始排版。", styleId: StyleID.body.rawValue),
                                Paragraph(kind: .figure(assetId: assetId), text: "", styleId: StyleID.body.rawValue)
                            ]
                        )
                    ]
                )
            ],
            assets: [asset]
        )

        let document = LayoutEngine().layout(project: project)
        let pages = document.pages
        XCTAssertTrue(pages.count >= 2)

        var foundLeft = false
        var foundRight = false
        var leftPageNum = 0
        var rightPageNum = 0

        for page in pages {
            for frame in page.frames {
                if case .spreadAsset(let id, let isLeft) = frame.content, id == assetId {
                    if isLeft {
                        foundLeft = true
                        leftPageNum = page.number
                    } else {
                        foundRight = true
                        rightPageNum = page.number
                    }
                }
            }
        }

        XCTAssertTrue(foundLeft, "Should place left half of spread asset")
        XCTAssertTrue(foundRight, "Should place right half of spread asset")
        XCTAssertEqual(rightPageNum, leftPageNum + 1, "Left and right halves must be on consecutive pages")
        XCTAssertEqual((leftPageNum + 2) % 2, 0, "Left page of the spread must be an even page number")
    }

    func testLayoutPlanOverridesApplyDynamically() {
        let marginOverride = PageMargins(top: 80, right: 90, bottom: 100, left: 110)
        let plan = LayoutPlan(
            target: .page(3),
            strategy: .textLed,
            blocks: [],
            marginOverride: marginOverride,
            columnsOverride: 1,
            showHeadersFooters: false
        )
        
        var project = BookProject.sample
        project.sections = [
            BookSection(
                title: "第一章",
                stories: [
                    Story(
                        title: "故事",
                        paragraphs: [
                            Paragraph(kind: .body, text: "这是一段用来测试自定义页边距和分栏的测试文字。", styleId: StyleID.body.rawValue)
                        ]
                    )
                ]
            )
        ]
        project.safeAppliedLayoutPlans = [3: plan]
        
        let document = LayoutEngine().layout(project: project)
        
        XCTAssertGreaterThanOrEqual(document.pages.count, 3)
        
        let page3 = document.pages[2]
        XCTAssertEqual(page3.number, 3)
        
        let runningHeaders = page3.frames.filter { frame in
            frame.styleId == StyleID.caption.rawValue && frame.rect.y == 24
        }
        XCTAssertTrue(runningHeaders.isEmpty, "Page 3 should not contain a running header when showHeadersFooters is false")
        
        let textFrames = page3.frames.filter { $0.styleId == StyleID.body.rawValue }
        XCTAssertEqual(textFrames.count, 1)
        
        let textFrame = textFrames[0]
        XCTAssertEqual(textFrame.rect.x, 110.0, accuracy: 0.01)
        XCTAssertEqual(textFrame.rect.width, 324.41, accuracy: 0.01)
    }

    func testFootnotesAndMarginalNotesLayout() {
        let markdown = """
        ---
        title: "测试书稿"
        author: "排版引擎"
        ---
        
        # 第一章 测试
        
        这是一段包含脚注的正文。[^fn1] 另外这一段还有一个旁注。
        
        > [!SIDE] 这是一个测试旁注
        > 这是旁注的详细内容，它将被放置在页面的侧边栏。
        
        这是另一段文本，也包含脚注。[^fn2] 脚注是底部的额外说明信息。
        
        [^fn1]: 这是第一个脚注的实际内容。
        [^fn2]: 这是第二个脚注的实际内容，用来测试堆叠。
        """
        
        let importer = MarkdownBookImporter()
        let project = importer.importDocument(markdown: markdown)
        
        XCTAssertEqual(project.metadata.title, "测试书稿")
        
        let section = project.sections.first
        XCTAssertNotNil(section)
        let story = section?.stories.first
        XCTAssertNotNil(story)
        
        let bodyParagraphs = story?.paragraphs.filter { $0.kind == ParagraphKind.body } ?? []
        XCTAssertEqual(bodyParagraphs.count, 2)
        
        let p1 = bodyParagraphs[0]
        XCTAssertTrue(p1.text.contains("¹"))
        XCTAssertEqual(p1.safeAnchoredFootnoteIds.count, 1)
        XCTAssertEqual(p1.safeAnchoredSideNoteIds.count, 1)
        
        let p2 = bodyParagraphs[1]
        XCTAssertTrue(p2.text.contains("²"))
        XCTAssertEqual(p2.safeAnchoredFootnoteIds.count, 1)
        
        let footnoteParagraphs = story?.paragraphs.filter {
            if case .footnote = $0.kind { return true }
            return false
        } ?? []
        XCTAssertEqual(footnoteParagraphs.count, 2)
        
        let sideNoteParagraphs = story?.paragraphs.filter { $0.kind == ParagraphKind.sideNote } ?? []
        XCTAssertEqual(sideNoteParagraphs.count, 1)
        
        let document = LayoutEngine().layout(project: project)
        XCTAssertGreaterThanOrEqual(document.pages.count, 3)
        
        let page = document.pages[2]
        
        let footnoteFrames = page.frames.filter { $0.kind == PageFrameKind.footnote }
        XCTAssertEqual(footnoteFrames.count, 2)
        
        let dividerFrames = page.frames.filter { $0.kind == PageFrameKind.footnoteDivider }
        XCTAssertEqual(dividerFrames.count, 1)
        
        let sideNoteFrames = page.frames.filter { $0.kind == PageFrameKind.sideNote }
        XCTAssertEqual(sideNoteFrames.count, 1)
        
        let f1 = footnoteFrames[0]
        let f2 = footnoteFrames[1]
        XCTAssertLessThan(f1.rect.y, f2.rect.y)
        
        let bodyFrames = page.frames.filter { $0.styleId == StyleID.body.rawValue }
        if let bodyFrame = bodyFrames.first {
            let sideNoteFrame = sideNoteFrames[0]
            XCTAssertEqual(sideNoteFrame.rect.y, bodyFrame.rect.y, accuracy: 0.1)
        }
    }

    func testChineseTypographyHangingAndAvoidKinsoku() {
        let style = ParagraphStyle(
            id: "body",
            displayName: "正文",
            fontName: "Songti SC",
            fontSize: 10,
            lineHeight: 14,
            firstLineIndent: 0,
            spaceBefore: 0,
            spaceAfter: 0,
            colorToken: "ink"
        )
        
        // Let's check a line ending with a comma that is just wider than columnWidth (e.g. 50 pt).
        // Since estimatedTextWidth for "测试文本" is about 40 pt, and "测试文本，" is about 50 pt.
        // We will test if the line breaks correctly and allows the comma to hang.
        let text = "测试文本，后续内容"
        let lines = ChineseTypesetting.breakTextIntoLines(text, style: style, columnWidth: 45.0, hangingWidth: 6.0)
        XCTAssertFalse(lines.isEmpty)
        // If comma hangs, the first line should contain the comma!
        XCTAssertTrue(lines[0].contains("，"))
        
        // Test avoid illegal line start (forbiddenLineStartCharacters)
        let textForbiddenStart = "长文本，测试"
        let linesForbidden = ChineseTypesetting.breakTextIntoLines(textForbiddenStart, style: style, columnWidth: 35.0, hangingWidth: 0.0)
        // Commas are forbidden at line start, so the first line should not end just before the comma and leave the comma at the start of the next line!
        if linesForbidden.count > 1 {
            XCTAssertFalse(linesForbidden[1].hasPrefix("，"))
        }
    }

    func testPreflightImageResolutionAndColorSpaceWarnings() throws {
        // Create a temporary real RGB PNG image
        let cgContext = CGContext(
            data: nil,
            width: 10,
            height: 10,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let bitmapRep = NSBitmapImageRep(cgImage: cgContext.makeImage()!)
        let data = try XCTUnwrap(bitmapRep.representation(using: .png, properties: [:]))
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-test-preflight-asset-\(UUID().uuidString)")
            .appendingPathExtension("png")
        try data.write(to: tempURL)
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        let asset = Asset(
            fileName: "temp-asset.png",
            sourcePath: tempURL.path,
            role: .diagram,
            pixelWidth: 10,
            pixelHeight: 10,
            dpi: 150 // low raw DPI (< 300)
        )
        
        let project = BookProject(
            metadata: ProjectMetadata(title: "预检测试", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(title: "第一章", paragraphs: [Paragraph(kind: .body, text: "内容", styleId: StyleID.body.rawValue)])
                    ]
                )
            ],
            assets: [asset]
        )
        let document = LayoutEngine().layout(project: project)
        let report = ProjectInspector().preflight(project: project, document: document)
        
        // RGB warning should trigger
        let rgbWarning = report.issues.first { $0.message.contains("颜色空间为 RGB") }
        XCTAssertNotNil(rgbWarning)
        
        // Low raw DPI warning should trigger for diagram role
        let lowDPIWarning = report.issues.first { $0.message.contains("原始分辨率") && $0.message.contains("DPI") }
        XCTAssertNotNil(lowDPIWarning)
    }

    func testLayoutEngineTextThreadingFlowsBetweenChainedBlocks() {
        let longText = "这是非常长的测试文本。为了验证文本框串接与流动逻辑，我们需要让这段文字超过第一个文本框的最大高度限制，使其一部分显示在第一个文本框中，另一部分自动流动到第二个文本框中进行显示。这是一个典型的多文本框链式排版场景。"
        let paragraphId = UUID()
        let paragraph = Paragraph(id: paragraphId, kind: .body, text: longText, styleId: StyleID.body.rawValue)
        
        let block1Id = UUID()
        let block2Id = UUID()
        
        let block1 = LayoutPlanBlock(
            id: block1Id,
            kind: .text,
            role: "text",
            frame: Rect(x: 0.1, y: 0.1, width: 0.8, height: 0.05),
            contentReference: .paragraph(paragraphId),
            nextThreadedBlockId: block2Id
        )
        
        let block2 = LayoutPlanBlock(
            id: block2Id,
            kind: .text,
            role: "text",
            frame: Rect(x: 0.1, y: 0.3, width: 0.8, height: 0.4),
            contentReference: .paragraph(paragraphId),
            previousThreadedBlockId: block1Id
        )
        
        let plan = LayoutPlan(
            target: .page(3),
            strategy: .balanced,
            blocks: [block1, block2]
        )
        
        let project = BookProject(
            metadata: ProjectMetadata(title: "串接测试", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(title: "串接故事", paragraphs: [paragraph])
                    ]
                )
            ],
            appliedLayoutPlans: [3: plan]
        )
        
        let document = LayoutEngine().layout(project: project)
        
        XCTAssertGreaterThanOrEqual(document.pages.count, 3)
        let page3 = document.pages[2]
        XCTAssertEqual(page3.number, 3)
        
        let textFrames = page3.frames.filter { $0.kind == .text && ($0.id == block1Id || $0.id == block2Id) }
        XCTAssertEqual(textFrames.count, 2)
        
        guard let frame1 = textFrames.first(where: { $0.id == block1Id }),
              let frame2 = textFrames.first(where: { $0.id == block2Id }) else {
            XCTFail("Missing threaded frames")
            return
        }
        
        if case .text(let t1) = frame1.content, case .text(let t2) = frame2.content {
            XCTAssertFalse(t1.isEmpty)
            XCTAssertFalse(t2.isEmpty)
            XCTAssertTrue(longText.contains(t1))
            XCTAssertTrue(longText.contains(t2))
            XCTAssertEqual(t1 + t2, longText.trimmedForLayout)
        } else {
            XCTFail("Frame content is not text")
        }
    }

    func testInvalidAppliedPlanIsRejectedAndFallsBack() {
        // A block whose normalized frame spills outside the page must not be
        // rendered; the engine rejects the plan and records a warning instead.
        let badBlockId = UUID()
        let badBlock = LayoutPlanBlock(
            id: badBlockId,
            kind: .text,
            role: "text",
            frame: Rect(x: 0.1, y: 0.1, width: 0.8, height: 2.0),
            contentReference: .generated("越界内容")
        )
        let plan = LayoutPlan(target: .page(3), strategy: .balanced, blocks: [badBlock])

        let project = BookProject(
            metadata: ProjectMetadata(title: "校验测试", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(title: "故事", paragraphs: [
                            Paragraph(kind: .body, text: "正文内容。", styleId: StyleID.body.rawValue)
                        ])
                    ]
                )
            ],
            appliedLayoutPlans: [3: plan]
        )

        let document = LayoutEngine().layout(project: project)

        XCTAssertFalse(
            document.pages.flatMap(\.frames).contains { $0.id == badBlockId },
            "Out-of-bounds plan block should not be rendered"
        )
        XCTAssertTrue(
            document.issues.contains { $0.severity == .warning && $0.message.contains("版式计划无效") },
            "Engine should surface a warning when rejecting an invalid plan"
        )
    }

    func testVerticalTypesettingLayoutFlow() {
        var setup = PageSetup.scienceBookDefault
        setup.layoutDirection = .vertical
        setup.columns = 2
        setup.gutter = 12.0
        
        let project = BookProject(
            metadata: ProjectMetadata(title: "竖排测试", author: "layoutD"),
            pageSetup: setup,
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(title: "故事", paragraphs: [
                            Paragraph(kind: .body, text: "自古逢秋悲寂寥，我言秋日胜春朝。晴空一鹤排云上，便引诗情到碧霄。", styleId: StyleID.body.rawValue)
                        ])
                    ]
                )
            ]
        )
        
        let document = LayoutEngine().layout(project: project)
        
        XCTAssertFalse(document.pages.isEmpty)
        
        let contentPages = document.pages.filter { $0.number > 2 }
        XCTAssertFalse(contentPages.isEmpty)
        
        for page in contentPages {
            let bodyFrames = page.frames.filter { $0.kind == PageFrameKind.text && $0.styleId == StyleID.body.rawValue }
            for frame in bodyFrames {
                let rightMargin = project.resolvedMargins(for: page.number).right
                let maxPossibleX = setup.pageSize.width - rightMargin
                XCTAssertLessThanOrEqual(frame.rect.x + frame.rect.width, maxPossibleX)
            }
        }
    }

    func testFixedPageStrategiesSuppressHeadersFootersAndMargins() {
        var project = BookProject.sample
        let assetId = project.assets.first?.id ?? UUID()
        let block1 = LayoutPlanBlock(
            kind: .image,
            role: "hero",
            frame: Rect(x: 0.0, y: 0.0, width: 1.0, height: 1.0),
            contentReference: .asset(assetId),
            maskShape: .fan
        )
        let fullPagePlan = LayoutPlan(
            target: .page(3),
            strategy: .fullPageImage,
            blocks: [block1]
        )
        
        let coverPlan = LayoutPlan(
            target: .page(4),
            strategy: .cover,
            blocks: []
        )
        
        let titlePlan = LayoutPlan(
            target: .page(5),
            strategy: .titlePage,
            blocks: []
        )
        
        project.safeAppliedLayoutPlans = [
            3: fullPagePlan,
            4: coverPlan,
            5: titlePlan
        ]
        
        // 1. Verify margins and showHeadersFooters resolution on project level
        let marginsPage3 = project.resolvedMargins(for: 3)
        XCTAssertEqual(marginsPage3.top, 0.0)
        XCTAssertEqual(marginsPage3.bottom, 0.0)
        XCTAssertEqual(marginsPage3.left, 0.0)
        XCTAssertEqual(marginsPage3.right, 0.0)
        
        XCTAssertFalse(project.resolvedShowHeadersFooters(for: 3))
        XCTAssertFalse(project.resolvedShowHeadersFooters(for: 4))
        XCTAssertFalse(project.resolvedShowHeadersFooters(for: 5))
        
        // 2. Verify propagation of maskShape to laid out document frames
        let document = LayoutEngine().layout(project: project)
        
        XCTAssertTrue(document.pages.count >= 3)
        let page3 = document.pages[2]
        
        // Find the image block from page 3 and check if maskShape is propagated
        let imageFrames = page3.frames.filter { $0.kind == .image }
        XCTAssertFalse(imageFrames.isEmpty)
        XCTAssertEqual(imageFrames[0].maskShape, .fan)
    }
}

private struct StaticPlanProvider: LayoutPlanProvider {
    var plans: [LayoutPlan]

    func proposePlans(request: LayoutPlanRequest) throws -> [LayoutPlan] {
        plans
    }
}

private struct FailingPlanProvider: LayoutPlanProvider {
    enum Failure: Error {
        case unavailable
    }

    func proposePlans(request: LayoutPlanRequest) throws -> [LayoutPlan] {
        throw Failure.unavailable
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
