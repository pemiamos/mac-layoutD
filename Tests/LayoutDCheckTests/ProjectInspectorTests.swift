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
                Asset(fileName: "demo.png", sourcePath: "/missing/demo.png", role: .photo, pixelWidth: 800, pixelHeight: 600, dpi: 96),
                Asset(fileName: "images/demo.png", role: .photo, pixelWidth: 800, pixelHeight: 600, dpi: 300)
            ]
        )

        let messages = ProjectInspector().inspect(project: project).map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("缺少图注") })
        XCTAssertTrue(messages.contains { $0.contains("分辨率低于 220 DPI") })
        XCTAssertTrue(messages.contains { $0.contains("源文件不存在") })
        XCTAssertTrue(messages.contains { $0.contains("图片文件名重复") })
    }

    func testReportsEmptyProjectStructure() {
        let project = BookProject(metadata: ProjectMetadata(title: "空项目", author: "layoutD"))
        let issues = ProjectInspector().inspect(project: project)
        XCTAssertTrue(issues.contains { $0.message == "项目没有章节" })
        XCTAssertTrue(issues.contains { $0.message == "项目没有正文流" })
        XCTAssertTrue(issues.contains { $0.message == "项目没有正文段落" })
    }
}
