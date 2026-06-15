import LayoutDCore
import LayoutDEngine
import LayoutDExport
import XCTest

final class PDFExporterTests: XCTestCase {
    func testExportsNonEmptyPDF() throws {
        let project = BookProject.sample
        let document = LayoutEngine().layout(project: project)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-export-test-\(UUID().uuidString)")
            .appendingPathExtension("pdf")

        defer {
            try? FileManager.default.removeItem(at: url)
        }

        try PDFExporter().export(document: document, project: project, to: url)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? NSNumber
        XCTAssertNotNil(fileSize)
        XCTAssertGreaterThan(fileSize?.intValue ?? 0, 1024)
    }

    func testExportsCalloutFramesToPDF() throws {
        let project = BookProject(
            metadata: ProjectMetadata(title: "知识卡片导出", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(
                            title: "第一章",
                            paragraphs: [
                                Paragraph(kind: .callout, text: "知识点：ATP 是细胞内部常用的能量凭证。", styleId: StyleID.callout.rawValue)
                            ]
                        )
                    ]
                )
            ]
        )
        let document = LayoutEngine().layout(project: project)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-callout-export-test-\(UUID().uuidString)")
            .appendingPathExtension("pdf")

        defer {
            try? FileManager.default.removeItem(at: url)
        }

        XCTAssertTrue(document.pages.flatMap(\.frames).contains { $0.kind == .callout })

        try PDFExporter().export(document: document, project: project, to: url)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? NSNumber
        XCTAssertNotNil(fileSize)
        XCTAssertGreaterThan(fileSize?.intValue ?? 0, 1024)
    }
}
