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

        let messages = ProjectInspector().inspect(project: project).map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("缺少图注") })
        XCTAssertTrue(messages.contains { $0.contains("分辨率低于 220 DPI") })
        XCTAssertTrue(messages.contains { $0.contains("源文件不存在") })
        XCTAssertTrue(messages.contains { $0.contains("图片文件名重复") })
        XCTAssertTrue(messages.contains { $0.contains("缺少版权或来源信息") })
    }

    func testReportsEmptyProjectStructure() {
        let project = BookProject(metadata: ProjectMetadata(title: "空项目", author: "layoutD"))
        let issues = ProjectInspector().inspect(project: project)
        XCTAssertTrue(issues.contains { $0.message == "项目没有章节" })
        XCTAssertTrue(issues.contains { $0.message == "项目没有正文流" })
        XCTAssertTrue(issues.contains { $0.message == "项目没有正文段落" })
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
        XCTAssertTrue(report.summaryLines.contains("Pages: 1"))
        XCTAssertTrue(report.summaryLines.contains("Frames: 0"))
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
}
