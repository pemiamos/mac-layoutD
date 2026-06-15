import LayoutDCore
import LayoutDDesignAI
import LayoutDEngine
import XCTest

final class LayoutDCoreTests: XCTestCase {
    func testSampleProjectEncodesAndDecodes() throws {
        let project = BookProject.sample
        let data = try ProjectFile.encode(project)
        let decoded = try ProjectFile.decode(data)
        XCTAssertEqual(decoded.metadata.title, project.metadata.title)
        XCTAssertEqual(decoded.sections.count, 1)
        XCTAssertEqual(decoded.assets.count, 1)
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
        XCTAssertEqual(plans.count, 3)
        XCTAssertTrue(plans.allSatisfy { !$0.blocks.isEmpty })
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
