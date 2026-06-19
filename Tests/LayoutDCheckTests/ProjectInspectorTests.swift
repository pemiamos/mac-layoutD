import Foundation
import LayoutDCheck
import LayoutDCore
import XCTest

final class ProjectInspectorTests: XCTestCase {
    func testReportsAssetProblems() {
        let project = BookProject(
            metadata: ProjectMetadata(title: "检查测试", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .body, text: "正文", styleId: StyleID.body.rawValue)
                            ]
                        )
                    ]
                )
            ],
            assets: [
                Asset(fileName: "demo.png", sourcePath: "/missing/demo.png", role: .photo, pixelWidth: 400, pixelHeight: 300, dpi: 96),
                Asset(fileName: "images/demo.png", role: .photo, pixelWidth: 800, pixelHeight: 600, dpi: 300)
            ]
        )

        let issues = ProjectInspector().inspect(project: project)
        let messages = issues.map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("缺少图注") })
        XCTAssertTrue(messages.contains { $0.contains("分辨率低于 220 DPI") })
        XCTAssertTrue(messages.contains { $0.contains("源文件不存在") })
        XCTAssertTrue(messages.contains { $0.contains("图片文件名重复") })
        XCTAssertTrue(messages.contains { $0.contains("缺少版权或来源信息") })
        XCTAssertTrue(issues.contains {
            $0.message.contains("缺少图注")
                && $0.suggestedFix?.contains("caption") == true
        })
        XCTAssertTrue(issues.contains {
            $0.message.contains("缺少图注")
                && $0.autoFixKind == .fillMissingAssetCaptions
        })
    }

    func testAssetWithCreditDoesNotReportMissingSource() {
        let asset = Asset(
            fileName: "credited.png",
            role: .photo,
            caption: "已有图注",
            credit: "NASA",
            pixelWidth: 1200,
            pixelHeight: 800,
            dpi: 300
        )
        let project = BookProject(
            metadata: ProjectMetadata(title: "来源检查", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .figure(assetId: asset.id), text: "已有图注", styleId: StyleID.caption.rawValue)
                            ]
                        )
                    ]
                )
            ],
            assets: [asset]
        )

        let messages = ProjectInspector().inspect(project: project).map(\.message)

        XCTAssertFalse(messages.contains { $0.contains("缺少版权或来源信息") })
    }

    func testReportsEmptyProjectStructure() {
        let project = BookProject(metadata: ProjectMetadata(title: "空项目", author: "layoutD"))
        let issues = ProjectInspector().inspect(project: project)
        XCTAssertTrue(issues.contains { $0.message == "项目没有章节" })
        XCTAssertTrue(issues.contains { $0.message == "项目没有正文流" })
        XCTAssertTrue(issues.contains { $0.message == "项目没有正文段落" })
        XCTAssertTrue(issues.contains {
            $0.message == "项目没有章节"
                && $0.suggestedFix?.contains("Markdown") == true
        })
    }

    func testReportsMetadataProblems() {
        let invalidISBNProject = BookProject(
            metadata: ProjectMetadata(title: "元数据检查", author: "layoutD", isbn: "9787115546082"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .body, text: "正文", styleId: StyleID.body.rawValue)
                            ]
                        )
                    ]
                )
            ]
        )

        let messages = ProjectInspector().inspect(project: invalidISBNProject).map(\.message)

        XCTAssertTrue(messages.contains("项目缺少出版社信息"))
        XCTAssertTrue(messages.contains("项目缺少关键词"))
        XCTAssertTrue(messages.contains("项目 ISBN-13 校验失败：9787115546082"))
        XCTAssertTrue(ProjectInspector().inspect(project: invalidISBNProject).allSatisfy { $0.category != nil })
    }

    func testPreflightIssuesExposeAutoFixKinds() {
        let project = BookProject(
            metadata: ProjectMetadata(title: "自动修复", author: "layoutD", isbn: "9787115546082"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .body, text: "正文", styleId: StyleID.body.rawValue)
                            ]
                        )
                    ]
                )
            ],
            assets: [
                Asset(
                    fileName: "demo-figure.png",
                    sourcePath: "/missing/demo-figure.png",
                    role: .diagram,
                    pixelWidth: 1200,
                    pixelHeight: 800,
                    dpi: 300
                )
            ]
        )

        let issues = ProjectInspector().inspect(project: project)

        XCTAssertTrue(issues.contains { $0.autoFixKind == .fillMissingPublisher })
        XCTAssertTrue(issues.contains { $0.autoFixKind == .fillMissingKeywords })
        XCTAssertTrue(issues.contains { $0.autoFixKind == .removeInvalidISBN })
        XCTAssertTrue(issues.contains { $0.autoFixKind == .fillMissingAssetCaptions })
        XCTAssertTrue(issues.contains { $0.autoFixKind == .fillMissingAssetCredits })
        XCTAssertTrue(issues.contains { $0.autoFixKind == .clearMissingAssetSourcePaths })
    }

    func testPreflightAutoFixerAppliesConservativeProjectFixes() {
        let asset = Asset(
            fileName: "cell-diagram.png",
            sourcePath: "/missing/cell-diagram.png",
            role: .diagram,
            pixelWidth: 1200,
            pixelHeight: 800,
            dpi: 300
        )
        let project = BookProject(
            metadata: ProjectMetadata(title: "自动修复样章", author: "layoutD", isbn: "9787115546082"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .body, text: "正文", styleId: StyleID.body.rawValue)
                            ]
                        )
                    ]
                )
            ],
            assets: [asset]
        )
        let issues = ProjectInspector().inspect(project: project)

        let result = PreflightAutoFixer().applyAvailableFixes(to: project, issues: issues)
        let fixed = result.project

        XCTAssertTrue(result.appliedFixes.contains(.fillMissingPublisher))
        XCTAssertTrue(result.appliedFixes.contains(.fillMissingKeywords))
        XCTAssertTrue(result.appliedFixes.contains(.removeInvalidISBN))
        XCTAssertTrue(result.appliedFixes.contains(.fillMissingAssetCaptions))
        XCTAssertTrue(result.appliedFixes.contains(.fillMissingAssetCredits))
        XCTAssertTrue(result.appliedFixes.contains(.clearMissingAssetSourcePaths))
        XCTAssertEqual(result.changedAssetIds, [asset.id])
        XCTAssertEqual(fixed.metadata.publisher, "待补充出版社")
        XCTAssertEqual(fixed.metadata.keywords, ["自动修复样章"])
        XCTAssertNil(fixed.metadata.isbn)
        XCTAssertEqual(fixed.assets.first?.caption, "cell diagram")
        XCTAssertEqual(fixed.assets.first?.credit, "待补充来源")
        XCTAssertNil(fixed.assets.first?.sourcePath)
    }

    func testValidBookMetadataDoesNotReportMetadataProblems() {
        let project = BookProject(
            metadata: ProjectMetadata(
                title: "元数据完整",
                author: "layoutD",
                publisher: "科学出版社",
                isbn: "978-7-115-54608-1",
                keywords: ["科普"]
            ),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .body, text: "正文", styleId: StyleID.body.rawValue)
                            ]
                        )
                    ]
                )
            ]
        )

        let messages = ProjectInspector().inspect(project: project).map(\.message)

        XCTAssertFalse(messages.contains("项目缺少出版社信息"))
        XCTAssertFalse(messages.contains("项目缺少关键词"))
        XCTAssertFalse(messages.contains { $0.contains("ISBN-13 校验失败") })
    }

    func testReportsMissingAssetReferencesAsBlockingErrors() {
        let missingAssetId = UUID()
        let project = BookProject(
            metadata: ProjectMetadata(title: "缺图测试", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(
                                    kind: .figure(assetId: missingAssetId),
                                    text: "缺失图片",
                                    styleId: StyleID.caption.rawValue
                                )
                            ]
                        )
                    ]
                )
            ]
        )

        let report = ProjectInspector().preflight(project: project)
        XCTAssertFalse(report.isExportReady)
        XCTAssertFalse(report.exportReady)
        XCTAssertEqual(report.severityCounts[IssueSeverity.error.rawValue], 1)
        XCTAssertTrue(report.issues.contains { $0.message == "段落引用了不存在的图片素材" })
    }

    func testReportsUnreferencedAssetsAsInfoOnly() {
        let referenced = Asset(
            fileName: "referenced.png",
            role: .diagram,
            caption: "已引用图片",
            credit: "layoutD",
            pixelWidth: 1200,
            pixelHeight: 800,
            dpi: 300
        )
        let unreferenced = Asset(
            fileName: "library-only.png",
            role: .diagram,
            caption: "素材库图片",
            credit: "layoutD",
            pixelWidth: 1200,
            pixelHeight: 800,
            dpi: 300
        )
        let project = BookProject(
            metadata: ProjectMetadata(title: "未引用素材", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .figure(assetId: referenced.id), text: "已引用图片", styleId: StyleID.caption.rawValue)
                            ]
                        )
                    ]
                )
            ],
            assets: [referenced, unreferenced]
        )

        let report = ProjectInspector().preflight(project: project)
        XCTAssertTrue(report.isExportReady)
        XCTAssertTrue(report.issues.contains {
            $0.severity == .info && $0.message == "图片 library-only.png 在素材库中但未被正文引用"
        })
        XCTAssertFalse(report.issues.contains { $0.message == "图片 referenced.png 在素材库中但未被正文引用" })
    }

    func testReportsRepeatedAssetUse() {
        let repeated = Asset(
            fileName: "repeat.png",
            role: .diagram,
            caption: "重复图片",
            pixelWidth: 1200,
            pixelHeight: 800,
            dpi: 300,
            usage: .repeated
        )
        let project = BookProject(
            metadata: ProjectMetadata(title: "重复用图", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .figure(assetId: repeated.id), text: "重复图片", styleId: StyleID.caption.rawValue)
                            ]
                        )
                    ]
                )
            ],
            assets: [repeated]
        )

        let report = ProjectInspector().preflight(project: project)

        XCTAssertTrue(report.issues.contains {
            $0.severity == .warning && $0.message == "图片 repeat.png 被重复使用"
        })
        XCTAssertEqual(report.assetSummary.repeatedUse, 1)
    }

    func testPreflightReportSummarizesAssetsAndPages() {
        let asset = Asset(
            fileName: "figure.png",
            role: .diagram,
            caption: nil,
            pixelWidth: 0,
            pixelHeight: 0,
            dpi: 120
        )
        let project = BookProject(
            metadata: ProjectMetadata(title: "预检报告", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .body, text: "正文", styleId: StyleID.body.rawValue)
                            ]
                        )
                    ]
                )
            ],
            assets: [asset]
        )
        let document = LaidOutDocument(projectId: project.id, pages: [LaidOutPage(number: 1)])

        let report = ProjectInspector().preflight(project: project, document: document)
        XCTAssertTrue(report.isExportReady)
        XCTAssertTrue(report.exportReady)
        XCTAssertEqual(report.pageCount, 1)
        XCTAssertEqual(report.assetSummary.total, 1)
        XCTAssertEqual(report.assetSummary.missingCaptions, 1)
        XCTAssertEqual(report.assetSummary.missingCredits, 1)
        XCTAssertEqual(report.assetSummary.lowResolution, 1)
        XCTAssertEqual(report.assetSummary.unknownSize, 1)
        XCTAssertEqual(report.layoutSummary?.totalFrames, 0)
        XCTAssertEqual(report.categoryCounts[PreflightIssueCategory.metadata.rawValue], 3)
        XCTAssertEqual(report.categoryCounts[PreflightIssueCategory.assets.rawValue], 5)
        XCTAssertEqual(report.categoryCounts[PreflightIssueCategory.prepress.rawValue], 1)
        XCTAssertTrue(report.summaryLines.contains("Pages: 1"))
        XCTAssertTrue(report.summaryLines.contains("Frames: 0"))
        XCTAssertTrue(report.summaryLines.contains("Issue categories: 3"))
    }

    func testPreflightReportSummarizesLayoutFrames() {
        let project = BookProject(
            metadata: ProjectMetadata(title: "版面统计", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .body, text: "正文", styleId: StyleID.body.rawValue)
                            ]
                        )
                    ]
                )
            ]
        )
        let page = LaidOutPage(
            number: 1,
            frames: [
                PageFrame(kind: .text, rect: Rect(x: 20, y: 20, width: 80, height: 30), content: .text("正文")),
                PageFrame(kind: .callout, rect: Rect(x: 20, y: 60, width: 80, height: 30), content: .text("知识卡片")),
                PageFrame(kind: .caption, rect: Rect(x: 20, y: 100, width: 80, height: 20), content: .text("图1 图注")),
                PageFrame(kind: .image, rect: Rect(x: 20, y: 130, width: 80, height: 50), content: .empty),
                PageFrame(kind: .table, rect: Rect(x: 20, y: 190, width: 80, height: 40), content: .text("指标    数值"))
            ]
        )

        let report = ProjectInspector().preflight(
            project: project,
            document: LaidOutDocument(projectId: project.id, pages: [page])
        )

        XCTAssertEqual(report.layoutSummary?.totalFrames, 5)
        XCTAssertEqual(report.layoutSummary?.textFrames, 1)
        XCTAssertEqual(report.layoutSummary?.calloutFrames, 1)
        XCTAssertEqual(report.layoutSummary?.captionFrames, 1)
        XCTAssertEqual(report.layoutSummary?.imageFrames, 1)
        XCTAssertEqual(report.layoutSummary?.tableFrames, 1)
        XCTAssertEqual(report.layoutSummary?.emptyFrames, 1)
    }

    func testPreflightReportCountsLayoutIssueCategories() {
        let frameId = UUID()
        let project = BookProject(
            metadata: ProjectMetadata(title: "分类统计", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .body, text: "正文", styleId: StyleID.body.rawValue)
                            ]
                        )
                    ]
                )
            ]
        )
        let page = LaidOutPage(
            number: 1,
            frames: [
                PageFrame(
                    id: frameId,
                    kind: .text,
                    rect: Rect(x: 20, y: 20, width: 0, height: 30),
                    content: .empty
                )
            ]
        )

        let report = ProjectInspector().preflight(
            project: project,
            document: LaidOutDocument(projectId: project.id, pages: [page])
        )

        XCTAssertEqual(report.categoryCounts[PreflightIssueCategory.layout.rawValue], 1)
        XCTAssertTrue(report.issues.contains {
            $0.frameId == frameId && $0.category == .layout
        })
    }

    func testPreflightReportIncludesIssueLocationsForFrameProblems() throws {
        let project = BookProject(
            metadata: ProjectMetadata(title: "问题定位", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .body, text: "正文", styleId: StyleID.body.rawValue)
                            ]
                        )
                    ]
                )
            ]
        )
        let frameId = UUID()
        let frame = PageFrame(
            id: frameId,
            kind: .text,
            rect: Rect(x: 10, y: 20, width: 80, height: 10),
            styleId: StyleID.body.rawValue,
            content: .text("这是一段会溢出小文本框的正文，用于测试预检报告能否导出 frame 定位。")
        )
        let document = LaidOutDocument(projectId: project.id, pages: [LaidOutPage(number: 1, frames: [frame])])

        let report = ProjectInspector().preflight(project: project, document: document)

        let location = try XCTUnwrap(report.issueLocations.first { $0.frameId == frameId })
        XCTAssertEqual(location.pageNumber, 1)
        XCTAssertEqual(location.frameKind, PageFrameKind.text.rawValue)
        XCTAssertEqual(location.rect, frame.rect)
        XCTAssertTrue(location.contentSummary?.contains("这是一段会溢出") == true)
        XCTAssertTrue(report.summaryLines.contains("Located issues: \(report.issueLocations.count)"))
        XCTAssertTrue(report.issues.contains {
            $0.frameId == frameId
                && $0.message.contains("文本溢出")
                && $0.suggestedFix?.contains("增大文本框高度") == true
        })
    }

    func testPreflightReportsLayoutDocumentDefects() {
        let missingAssetId = UUID()
        let project = BookProject(
            metadata: ProjectMetadata(title: "版面缺陷", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .body, text: "正文", styleId: StyleID.body.rawValue)
                            ]
                        )
                    ]
                )
            ]
        )
        let page = LaidOutPage(
            number: 1,
            frames: [
                PageFrame(kind: .text, rect: Rect(x: 10, y: 10, width: 100, height: 40), content: .text("第一段")),
                PageFrame(kind: .text, rect: Rect(x: 20, y: 20, width: 100, height: 40), content: .text("第二段")),
                PageFrame(kind: .text, rect: Rect(x: 10, y: 80, width: 100, height: 30), content: .text("   ")),
                PageFrame(
                    kind: .text,
                    rect: Rect(x: 10, y: 220, width: 80, height: 12),
                    styleId: StyleID.body.rawValue,
                    content: .text("这是一段一定无法放进这个小文本框的中文内容。")
                ),
                PageFrame(kind: .image, rect: Rect(x: 10, y: 120, width: 100, height: 60), content: .asset(missingAssetId)),
                PageFrame(kind: .text, rect: Rect(x: -10, y: 10, width: 30, height: 30), content: .text("越界"))
            ]
        )
        let document = LaidOutDocument(projectId: project.id, pages: [page])

        let report = ProjectInspector().preflight(project: project, document: document)
        let messages = report.issues.map(\.message)

        XCTAssertFalse(report.isExportReady)
        XCTAssertTrue(messages.contains { $0.contains("frame 重叠") })
        XCTAssertTrue(messages.contains { $0.contains("空文本 frame") })
        XCTAssertTrue(messages.contains { $0.contains("缺失图片 frame") })
        XCTAssertTrue(messages.contains { $0.contains("越界 frame") })
        XCTAssertTrue(messages.contains { $0.contains("文本溢出 frame") })
    }

    func testPreflightReportsChineseLineBreakViolations() {
        let project = BookProject(
            metadata: ProjectMetadata(title: "中文禁则", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .body, text: "正文", styleId: StyleID.body.rawValue)
                            ]
                        )
                    ]
                )
            ]
        )
        let page = LaidOutPage(
            number: 1,
            frames: [
                PageFrame(
                    kind: .text,
                    rect: Rect(x: 80, y: 80, width: 180, height: 40),
                    styleId: StyleID.body.rawValue,
                    content: .text("，这一行不能以逗号开始。")
                )
            ]
        )
        let document = LaidOutDocument(projectId: project.id, pages: [page])

        let report = ProjectInspector().preflight(project: project, document: document)

        XCTAssertTrue(report.isExportReady)
        XCTAssertTrue(report.issues.contains {
            $0.severity == .warning && $0.message.contains("中文禁则问题：行首出现禁用标点")
        })
    }

    func testPreflightReportsTableOfContentsPageMismatch() {
        let project = contentsValidationProject()
        let document = LaidOutDocument(
            projectId: project.id,
            pages: [
                LaidOutPage(number: 1),
                LaidOutPage(
                    number: 2,
                    frames: [
                        PageFrame(kind: .text, rect: Rect(x: 40, y: 40, width: 300, height: 80), styleId: StyleID.body.rawValue, content: .text("第一章  4"))
                    ]
                ),
                LaidOutPage(
                    number: 3,
                    frames: [
                        PageFrame(kind: .text, rect: Rect(x: 40, y: 40, width: 300, height: 80), styleId: StyleID.heading1.rawValue, content: .text("第一章"))
                    ]
                ),
                LaidOutPage(number: 4)
            ]
        )

        let report = ProjectInspector().preflight(project: project, document: document)

        XCTAssertTrue(report.isExportReady)
        XCTAssertTrue(report.issues.contains {
            $0.severity == .warning && $0.message.contains("目录页码不一致：第一章 标为第 4 页，实际标题在第 3 页")
        })
    }

    func testPreflightReportsTableOfContentsMissingReferencedPage() {
        let project = contentsValidationProject()
        let document = LaidOutDocument(
            projectId: project.id,
            pages: [
                LaidOutPage(number: 1),
                LaidOutPage(
                    number: 2,
                    frames: [
                        PageFrame(kind: .text, rect: Rect(x: 40, y: 40, width: 300, height: 80), styleId: StyleID.body.rawValue, content: .text("第一章  9"))
                    ]
                ),
                LaidOutPage(
                    number: 3,
                    frames: [
                        PageFrame(kind: .text, rect: Rect(x: 40, y: 40, width: 300, height: 80), styleId: StyleID.heading1.rawValue, content: .text("第一章"))
                    ]
                )
            ]
        )

        let report = ProjectInspector().preflight(project: project, document: document)

        XCTAssertFalse(report.isExportReady)
        XCTAssertTrue(report.issues.contains {
            $0.severity == .error && $0.message.contains("目录引用了不存在的页码：第一章 -> 9")
        })
    }

    func testPreflightReportsMissingTableOfContentsEntryForVisibleTitle() {
        let project = contentsValidationProject()
        let document = LaidOutDocument(
            projectId: project.id,
            pages: [
                LaidOutPage(number: 1),
                LaidOutPage(
                    number: 2,
                    frames: [
                        PageFrame(kind: .text, rect: Rect(x: 40, y: 40, width: 300, height: 80), styleId: StyleID.body.rawValue, content: .text("暂无章节"))
                    ]
                ),
                LaidOutPage(
                    number: 3,
                    frames: [
                        PageFrame(kind: .text, rect: Rect(x: 40, y: 40, width: 300, height: 80), styleId: StyleID.heading1.rawValue, content: .text("第一章"))
                    ]
                )
            ]
        )

        let report = ProjectInspector().preflight(project: project, document: document)

        XCTAssertTrue(report.isExportReady)
        XCTAssertTrue(report.issues.contains {
            $0.severity == .warning && $0.message.contains("目录缺少可见标题：第一章")
        })
    }

    func testPreflightReportsBrokenPageSequence() {
        let project = BookProject(
            metadata: ProjectMetadata(title: "页序检查", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .body, text: "正文", styleId: StyleID.body.rawValue)
                            ]
                        )
                    ]
                )
            ]
        )
        let document = LaidOutDocument(
            projectId: project.id,
            pages: [
                LaidOutPage(number: 1),
                LaidOutPage(number: 3),
                LaidOutPage(number: 3)
            ]
        )

        let report = ProjectInspector().preflight(project: project, document: document)

        XCTAssertFalse(report.isExportReady)
        XCTAssertTrue(report.issues.contains { $0.message == "文档存在重复页码：3" })
        XCTAssertTrue(report.issues.contains { $0.message.contains("文档页码不连续") })
    }

    func testPreflightAutoFixerAppliesNewAndTargetedFixes() {
        let asset1 = Asset(
            id: UUID(),
            fileName: "low_dpi.png",
            role: .hero,
            pixelWidth: 20,
            pixelHeight: 20,
            dpi: 72
        )
        let asset2 = Asset(
            id: UUID(),
            fileName: "normal_dpi.png",
            role: .hero,
            pixelWidth: 2000,
            pixelHeight: 2000,
            dpi: 300
        )
        
        let frameId1 = UUID()
        let frameId2 = UUID()
        let plan = LayoutPlan(
            target: .page(3),
            strategy: .balanced,
            blocks: [
                LayoutPlanBlock(
                    id: frameId1,
                    kind: .text,
                    role: "body",
                    frame: Rect(x: -0.1, y: 1.2, width: 0.5, height: 0.5), // out of bounds
                    contentReference: .generated("") // empty
                ),
                LayoutPlanBlock(
                    id: frameId2,
                    kind: .text,
                    role: "body",
                    frame: Rect(x: 0.1, y: 0.1, width: 0.5, height: 0.5), // inside bounds
                    contentReference: .generated("正文")
                )
            ]
        )
        
        let project = BookProject(
            metadata: ProjectMetadata(title: "新修复测试", subtitle: "", author: ""),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .body, text: "正文", styleId: StyleID.body.rawValue)
                            ]
                        )
                    ]
                )
            ],
            assets: [asset1, asset2],
            appliedLayoutPlans: [3: plan]
        )
        
        // 1. Inspect issues
        let inspector = ProjectInspector()
        let document = LaidOutDocument(
            projectId: project.id,
            pages: [
                LaidOutPage(number: 3, frames: [
                    PageFrame(id: frameId1, kind: .text, rect: Rect(x: -10, y: 300, width: 100, height: 100), content: .text("")),
                    PageFrame(id: frameId2, kind: .text, rect: Rect(x: 20, y: 20, width: 100, height: 100), content: .text("正文"))
                ])
            ]
        )
        let report = inspector.preflight(project: project, document: document)
        let issues = report.issues
        
        XCTAssertTrue(issues.contains { $0.autoFixKind == .fillMissingAuthor })
        XCTAssertTrue(issues.contains { $0.autoFixKind == .fillMissingSubtitle })
        XCTAssertTrue(issues.contains { $0.autoFixKind == .downgradeLowDPIAssetRoles })
        XCTAssertTrue(issues.contains { $0.autoFixKind == .removeEmptyTextFrames })
        XCTAssertTrue(issues.contains { $0.autoFixKind == .constrainOutOfBoundsFrames })
        
        // 2. Test targeted fix: author only
        let fixer = PreflightAutoFixer()
        let resultAuthor = fixer.applyFixes([.fillMissingAuthor], to: project)
        XCTAssertFalse(resultAuthor.project.metadata.author.isEmpty)
        XCTAssertEqual(resultAuthor.project.metadata.subtitle, "") // Subtitle remains unchanged
        
        // 3. Test targeted fix for asset1 low DPI downgrade
        let resultDPI = fixer.applyFixes([.downgradeLowDPIAssetRoles], to: project, targetingAssetId: asset1.id)
        XCTAssertEqual(resultDPI.project.assets.first(where: { $0.id == asset1.id })?.role, .diagram) // hero -> diagram
        XCTAssertEqual(resultDPI.project.assets.first(where: { $0.id == asset2.id })?.role, .hero) // unaffected
        
        // 4. Test targeted fix for out of bounds frame1 snap
        let resultConstrain = fixer.applyFixes([.constrainOutOfBoundsFrames], to: project, targetingFrameId: frameId1)
        let constrainedBlock = resultConstrain.project.appliedLayoutPlans?[3]?.blocks.first { $0.id == frameId1 }
        XCTAssertEqual(constrainedBlock?.frame.x, 0.0)
        XCTAssertEqual(constrainedBlock?.frame.y, 0.5) // constrained y from 1.2 to 1.0 - 0.5 = 0.5
        
        // 5. Test targeted fix for empty text frame1 removal
        let resultRemove = fixer.applyFixes([.removeEmptyTextFrames], to: project, targetingFrameId: frameId1)
        XCTAssertEqual(resultRemove.project.appliedLayoutPlans?[3]?.blocks.count, 1)
        XCTAssertEqual(resultRemove.project.appliedLayoutPlans?[3]?.blocks.first?.id, frameId2)
    }

    private func contentsValidationProject() -> BookProject {
        BookProject(
            metadata: ProjectMetadata(title: "目录检查", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .body, text: "正文", styleId: StyleID.body.rawValue)
                            ]
                        )
                    ]
                )
            ]
        )
    }
}
