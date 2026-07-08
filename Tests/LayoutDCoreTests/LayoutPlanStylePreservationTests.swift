import XCTest
@testable import LayoutDCore
@testable import LayoutDEngine

/// 手动微调（在画布里移动任意一个 frame）会把整页冻结成一个 LayoutPlan
/// （`AppState.freezePageToPlan`），冻结时会记录每个 frame 的真实 `styleId`。
/// 此前 materialize 路径无视 `block.styleId`，把所有 `.text` block 一律按 `body`
/// 重排——于是页面一旦被冻结，章名/节名标题的字号会瞬间塌成正文（用户 2026-07-08
/// 画布验收 FRAME-CANVAS-1 时发现：点一下小标题→整页 Override→两个标题都掉样式）。
final class LayoutPlanStylePreservationTests: XCTestCase {

    func testFrozenHeadingBlockKeepsItsStyleAfterMaterialize() {
        var project = BookProject(
            metadata: ProjectMetadata(title: "样式保留", author: "layoutD"),
            sections: [
                BookSection(title: "第一章", stories: [
                    Story(title: "第一章", paragraphs: [
                        Paragraph(kind: .body, text: "正文一段，随便一点内容用于占位。", styleId: StyleID.body.rawValue)
                    ])
                ])
            ]
        )

        // 模拟 freezePageToPlan 冻结出的「标题 block」：kind=.text，但带真实 styleId=heading1。
        let headingBlockId = UUID()
        let headingBlock = LayoutPlanBlock(
            id: headingBlockId,
            kind: .text,
            role: PageFrameKind.text.rawValue,
            frame: Rect(x: 0.1, y: 0.1, width: 0.8, height: 0.1),
            contentReference: .generated("深海不是黑暗的尽头"),
            styleId: StyleID.heading1.rawValue
        )
        let contentPage = 1 + frontMatterPageCount(for: project)
        project.safeAppliedLayoutPlans = [
            contentPage: LayoutPlan(target: .page(contentPage), strategy: .balanced, blocks: [headingBlock])
        ]

        let doc = LayoutEngine().layout(project: project)
        let frame = doc.pages.flatMap(\.frames).first { $0.id == headingBlockId }
        XCTAssertNotNil(frame, "冻结的标题 block 应被 materialize 成一个 frame")
        XCTAssertEqual(frame?.styleId, StyleID.heading1.rawValue,
                       "冻结的标题重排后应保留 heading1 样式，不能被强制降为 body")
    }

    /// AI/模板计划不带 styleId（DesignAI 的 LayoutPlanBlock 均不设 styleId），
    /// 应保持 kind-based 回退（.text → body）不变——本修复不能改动这条老路径。
    func testTextBlockWithoutStyleIdStillDefaultsToBody() {
        var project = BookProject(
            metadata: ProjectMetadata(title: "回退不变", author: "layoutD"),
            sections: [
                BookSection(title: "第一章", stories: [
                    Story(title: "第一章", paragraphs: [
                        Paragraph(kind: .body, text: "正文", styleId: StyleID.body.rawValue)
                    ])
                ])
            ]
        )
        let blockId = UUID()
        let block = LayoutPlanBlock(
            id: blockId,
            kind: .text,
            role: PageFrameKind.text.rawValue,
            frame: Rect(x: 0.1, y: 0.3, width: 0.8, height: 0.1),
            contentReference: .generated("模板正文")
            // 不传 styleId → 应回退到 body
        )
        let contentPage = 1 + frontMatterPageCount(for: project)
        project.safeAppliedLayoutPlans = [
            contentPage: LayoutPlan(target: .page(contentPage), strategy: .balanced, blocks: [block])
        ]

        let doc = LayoutEngine().layout(project: project)
        let frame = doc.pages.flatMap(\.frames).first { $0.id == blockId }
        XCTAssertEqual(frame?.styleId, StyleID.body.rawValue,
                       "不带 styleId 的 .text block 仍按 body 回退")
    }
}
