import LayoutDCore
import LayoutDImport
import XCTest

/// FIXTURE-1 回归语料：`Samples/fixture-standard-chapter.md` 是 SAMPLE-1 一键样张的固定输入，
/// 也是「角色标签结构化导入」（IMP-3，layoutD 核心能力）的覆盖回归。
/// 本测试确保：标准样章能被现有 Markdown 导入器读通，且每个角色标签都产出了正确的
/// 段落种类 / 命名样式，标签字面不会漏进正文。
final class FixtureStandardChapterTests: XCTestCase {
    /// 从源文件位置推算仓库内 `Samples/` 路径，避免硬编码绝对路径（CI 上会失效）。
    private func fixtureMarkdown() throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)   // Tests/LayoutDImportTests/FixtureStandardChapterTests.swift
            .deletingLastPathComponent()                 // Tests/LayoutDImportTests
            .deletingLastPathComponent()                 // Tests
            .deletingLastPathComponent()                 // <repo root>
        let fixtureURL = repoRoot
            .appendingPathComponent("Samples")
            .appendingPathComponent("fixture-standard-chapter.md")
        return try String(contentsOf: fixtureURL, encoding: .utf8)
    }

    private func importFixture() throws -> BookProject {
        MarkdownBookImporter().importDocument(markdown: try fixtureMarkdown())
    }

    private func allParagraphs(_ project: BookProject) -> [Paragraph] {
        project.sections.flatMap(\.stories).flatMap(\.paragraphs)
    }

    func testFixtureImportsWithMetadata() throws {
        let project = try importFixture()
        XCTAssertEqual(project.metadata.title, "深海不是黑暗的尽头")
        XCTAssertEqual(project.metadata.author, "layoutD 示例")
        XCTAssertEqual(project.metadata.isbn, "978-7-115-90001-2")
        XCTAssertFalse(allParagraphs(project).isEmpty, "样章导入后应有正文段落")
    }

    /// 覆盖 FIXTURE-1 要求的全部角色：章名/节名/文章名/开节概述/正文/抽言/图注/引文/图片占位（+参考文献）。
    func testEveryRoleTagIsCoveredExactlyByItsStyle() throws {
        let project = try importFixture()
        let paragraphs = allParagraphs(project)

        func hasParagraph(kind kindPredicate: (ParagraphKind) -> Bool, styleId: String) -> Bool {
            paragraphs.contains { kindPredicate($0.kind) && $0.styleId == styleId }
        }

        // 章名 → heading1
        XCTAssertTrue(
            hasParagraph(kind: { $0 == .heading(level: 1) }, styleId: StyleID.heading1.rawValue),
            "缺少 章名(heading1) 段落"
        )
        // 节名 → heading2
        XCTAssertTrue(
            hasParagraph(kind: { $0 == .heading(level: 2) }, styleId: StyleID.heading2.rawValue),
            "缺少 节名(heading2) 段落"
        )
        // 文章名 → heading3
        XCTAssertTrue(
            hasParagraph(kind: { $0 == .heading(level: 3) }, styleId: StyleID.heading3.rawValue),
            "缺少 文章名(heading3) 段落"
        )
        // 开节概述 → introduction（跨段角色，应至少两段）
        let introParas = paragraphs.filter { $0.styleId == StyleID.introduction.rawValue }
        XCTAssertGreaterThanOrEqual(introParas.count, 2, "开节概述(introduction) 应覆盖标签后的多段")
        // 正文 → body
        XCTAssertTrue(
            hasParagraph(kind: { $0 == .body }, styleId: StyleID.body.rawValue),
            "缺少 正文(body) 段落"
        )
        // 抽言 → pullQuote
        XCTAssertTrue(
            hasParagraph(kind: { _ in true }, styleId: StyleID.pullQuote.rawValue),
            "缺少 抽言(pullQuote) 段落"
        )
        // 图注 → figure 段落带 caption 样式与非空图注文字
        let figures = paragraphs.filter {
            if case .figure = $0.kind { return true } else { return false }
        }
        XCTAssertFalse(figures.isEmpty, "缺少 图片占位(figure) 段落")
        XCTAssertTrue(
            figures.contains { $0.styleId == StyleID.caption.rawValue && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty },
            "缺少 图注(caption 文字非空)"
        )
        // 引文 → quote
        XCTAssertTrue(
            hasParagraph(kind: { $0 == .quote }, styleId: StyleID.callout.rawValue),
            "缺少 引文(quote) 段落"
        )
        // 参考文献 → bibliography
        XCTAssertTrue(
            hasParagraph(kind: { _ in true }, styleId: StyleID.bibliography.rawValue),
            "缺少 参考文献(bibliography) 段落"
        )
    }

    /// 角色标签字面（"章名"、"开节概述" 等）必须被导入器消费掉，绝不能漏进正文文本。
    func testRoleTagLiteralsDoNotLeakIntoContent() throws {
        let project = try importFixture()
        let bodyText = allParagraphs(project).map(\.text).joined(separator: "\n")

        for leak in ["一级标题", "二级标题", "三级标题", "章名", "节名", "文章名",
                     "开节概述", "抽言", "参考文献"] {
            XCTAssertFalse(
                bodyText.contains(leak),
                "角色标签字面「\(leak)」漏进了正文内容"
            )
        }
        // front matter 键也不该漏出
        XCTAssertFalse(bodyText.contains("title:"))
        XCTAssertFalse(bodyText.contains("keywords:"))
    }
}
