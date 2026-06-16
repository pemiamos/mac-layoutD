import LayoutDCore
@testable import LayoutDApp
import XCTest

final class ProjectLoaderTests: XCTestCase {
    func testChapterPackageLoadsRootManuscriptFirst() throws {
        let packageURL = try makeTemporaryPackage()
        defer { try? FileManager.default.removeItem(at: packageURL) }

        try """
        ---
        title: 根目录书稿
        author: layoutD
        ---

        # 根目录章节

        根目录内容。
        """.write(to: packageURL.appendingPathComponent("manuscript.md"), atomically: true, encoding: .utf8)

        let chaptersURL = packageURL.appendingPathComponent("chapters")
        try FileManager.default.createDirectory(at: chaptersURL, withIntermediateDirectories: true)
        try """
        # 子目录章节

        子目录内容不应被导入。
        """.write(to: chaptersURL.appendingPathComponent("01.md"), atomically: true, encoding: .utf8)

        let project = try ProjectLoader().loadProject(inputURL: packageURL)

        XCTAssertEqual(project.metadata.title, "根目录书稿")
        XCTAssertEqual(project.sections.map(\.title), ["根目录章节"])
        XCTAssertFalse(project.sections.contains { $0.title == "子目录章节" })
    }

    func testChapterPackageLoadsChapterFilesInFilenameOrder() throws {
        let packageURL = try makeTemporaryPackage()
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let chaptersURL = packageURL.appendingPathComponent("chapters")
        try FileManager.default.createDirectory(at: chaptersURL, withIntermediateDirectories: true)
        try """
        # 第二章

        第二段。
        """.write(to: chaptersURL.appendingPathComponent("02-body.md"), atomically: true, encoding: .utf8)
        try """
        ---
        title: 多文件章节包
        author: layoutD
        ---

        # 第一章

        第一段。
        """.write(to: chaptersURL.appendingPathComponent("01-intro.md"), atomically: true, encoding: .utf8)

        let project = try ProjectLoader().loadProject(inputURL: packageURL)

        XCTAssertEqual(project.metadata.title, "多文件章节包")
        XCTAssertEqual(project.sections.map(\.title), ["第一章", "第二章"])
        XCTAssertEqual(project.sections.first?.stories.first?.paragraphs.first(where: { $0.kind == .body })?.text, "第一段。")
        XCTAssertEqual(project.sections.last?.stories.first?.paragraphs.first(where: { $0.kind == .body })?.text, "第二段。")
    }

    func testChapterPackageReportsMissingManuscript() throws {
        let packageURL = try makeTemporaryPackage()
        defer { try? FileManager.default.removeItem(at: packageURL) }

        XCTAssertThrowsError(try ProjectLoader().loadProject(inputURL: packageURL)) { error in
            XCTAssertTrue(error.localizedDescription.contains("章节包缺少根目录"))
            XCTAssertTrue(error.localizedDescription.contains("chapters/*.md"))
        }
    }

    private func makeTemporaryPackage() throws -> URL {
        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-project-loader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        return packageURL
    }
}
