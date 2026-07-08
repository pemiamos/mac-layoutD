import XCTest
@testable import LayoutDCore
@testable import LayoutDEngine

/// FRAME-CANVAS-0：groupIntoFlowFrames 断流分组边界回归。抽取自 IDMLExporter 的
/// FRAME-SPLIT 逻辑，此处独立验证标题/抽言等独立框角色能正确打断正文流分组，
/// 供画布/PDF/PNG（FRAME-CANVAS-1）复用时不必再对照 IDML 输出反推正确性。
final class FlowFrameGroupingTests: XCTestCase {

    func testHeadingAndCalloutBreakFlowIntoSeparateRuns() throws {
        let body1 = Paragraph(kind: .body, text: "第一段正文，足够长以生成有效的文字框内容。", styleId: StyleID.body.rawValue)
        let body2 = Paragraph(kind: .body, text: "第二段正文，紧跟第一段，应与其同流。", styleId: StyleID.body.rawValue)
        let body3 = Paragraph(kind: .body, text: "第三段正文，被抽言打断后另起一条新流。", styleId: StyleID.body.rawValue)
        let heading = Paragraph(kind: .heading(level: 1), text: "章标题", styleId: StyleID.heading1.rawValue)
        let callout = Paragraph(kind: .callout, text: "一句抽言", styleId: StyleID.pullQuote.rawValue)

        let project = BookProject(
            metadata: ProjectMetadata(title: "分组测试", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [
                        Story(title: "第一章", paragraphs: [heading, body1, body2, callout, body3])
                    ]
                )
            ]
        )

        let doc = LayoutEngine().layout(project: project)
        let grouping = groupIntoFlowFrames(pages: doc.pages, project: project)

        // 断流后应恰好两条正文流：[body1,body2] 一条，[body3] 另一条。
        XCTAssertEqual(grouping.paragraphsForRun.keys.count, 2)

        let run0 = try XCTUnwrap(grouping.frameRunIndex.first(where: { entry in
            doc.pages[entry.key.page].frames[entry.key.frame].sourceParagraphId == body1.id
        })?.value)
        let run1 = try XCTUnwrap(grouping.frameRunIndex.first(where: { entry in
            doc.pages[entry.key.page].frames[entry.key.frame].sourceParagraphId == body2.id
        })?.value)
        let run2 = try XCTUnwrap(grouping.frameRunIndex.first(where: { entry in
            doc.pages[entry.key.page].frames[entry.key.frame].sourceParagraphId == body3.id
        })?.value)

        // body1/body2 同流，body3 是抽言打断后的新流。
        XCTAssertEqual(run0, run1)
        XCTAssertNotEqual(run0, run2)

        // 标题/抽言段落本身不该出现在任何 run 的分组结果里（它们各自独立成框）。
        XCTAssertFalse(grouping.paragraphsForRun.values.flatMap { $0 }.contains { $0.id == heading.id })
        XCTAssertFalse(grouping.paragraphsForRun.values.flatMap { $0 }.contains { $0.id == callout.id })

        // 同一 run 内相邻正文合并进同一个分组、且带上组内原始 frame 下标（供 FRAME-CANVAS-1
        // 复用：组内文字仍逐段渲染，只是外面加一个合并虚线框）。
        let run0Groups = try XCTUnwrap(grouping.groupsByRun[run0])
        XCTAssertEqual(run0Groups.count, 1, "body1/body2 同页同栏应合并成一个分组")
        XCTAssertGreaterThanOrEqual(run0Groups[0].memberFrameIndices.count, 2)
    }

    func testTableBreaksFlow() throws {
        let body1 = Paragraph(kind: .body, text: "表格前的正文。", styleId: StyleID.body.rawValue)
        let table = Paragraph(kind: .table, text: "单元格", styleId: StyleID.body.rawValue, tableCells: [["A", "B"]])
        let body2 = Paragraph(kind: .body, text: "表格后的正文，应属于新的一条流。", styleId: StyleID.body.rawValue)

        let project = BookProject(
            metadata: ProjectMetadata(title: "表格断流测试", author: "layoutD"),
            sections: [
                BookSection(
                    title: "第一章",
                    stories: [Story(title: "第一章", paragraphs: [body1, table, body2])]
                )
            ]
        )

        let doc = LayoutEngine().layout(project: project)
        let grouping = groupIntoFlowFrames(pages: doc.pages, project: project)

        XCTAssertEqual(grouping.paragraphsForRun.keys.count, 2, "表格应打断正文流，产生两条独立的流")
    }
}
