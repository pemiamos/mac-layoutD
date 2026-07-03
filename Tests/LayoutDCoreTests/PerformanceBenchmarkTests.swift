import XCTest
import LayoutDCore
import LayoutDEngine

/// PERF-1 全书规模性能基准：合成一份 200+ 页书稿，测一次全量排版的耗时。
/// 目的是给性能优化（PERF-2/3/4）一个可对比的基线，并防性能悬崖式回归。
/// 断言上限取本机基线的数倍，容忍 CI runner 与本机的速度差；真正的
/// 逐毫秒对比看测试输出里打印的耗时数字（记录在 handoff/简报）。
final class PerformanceBenchmarkTests: XCTestCase {

    /// 生成一份全书规模的合成书稿：12 章 × 200 段正文（含少量标题/引用），
    /// 文本为确定性变化的中英混排（性能与真实书稿同量级，内容可复现）。
    static func makeFullBookProject() -> BookProject {
        var project = BookProject.sample
        var sections: [BookSection] = []
        let sentences = [
            "山谷里的村落沿着溪流铺展，屋舍的坡顶在晨雾中若隐若现，构成一条起伏的天际线。",
            "研究者记录下每一处梯田的走向，These terraces follow the contour lines,与山体的等高线几乎完全一致。",
            "季风带来的降水在此被层层截留，先入林、再入田、最后汇入村口的水塘。",
            "石砌的巷道宽不过两米，却承担了排水、通风与日常交往的多重功能。",
            "村中长者口述的迁徙史与族谱记载相互印证，可以追溯到十四世纪中叶。",
        ]
        for chapter in 1...12 {
            var paragraphs: [Paragraph] = []
            paragraphs.append(Paragraph(kind: .heading(level: 1), text: "第\(chapter)章 山地聚落的空间结构", styleId: "heading1"))
            for i in 0..<200 {
                if i % 40 == 20 {
                    paragraphs.append(Paragraph(kind: .heading(level: 2), text: "第\(chapter).\(i / 40 + 1)节 田野观察", styleId: "heading2"))
                }
                let a = sentences[i % sentences.count]
                let b = sentences[(i + chapter) % sentences.count]
                paragraphs.append(Paragraph(kind: .body, text: a + b, styleId: "body"))
            }
            sections.append(BookSection(title: "第\(chapter)章", stories: [Story(title: "正文", paragraphs: paragraphs)]))
        }
        project.sections = sections
        project.assets = []
        project.appliedLayoutPlans = nil
        return project
    }

    func testFullBookLayoutBenchmark() {
        let project = Self.makeFullBookProject()
        let engine = LayoutEngine()

        // 预热一次（字体缓存等一次性成本不计入基线）
        _ = engine.layout(project: project)

        let start = Date()
        let document = engine.layout(project: project)
        let elapsedMS = Date().timeIntervalSince(start) * 1000

        print("PERF-1 全书基准：\(document.pages.count) 页 / \(String(format: "%.0f", elapsedMS)) ms")

        XCTAssertGreaterThan(document.pages.count, 150, "合成书稿应达到全书规模（150+ 页），否则基准失去意义")
        // 上限 = 本机基线（见 handoff 记录）的 5 倍左右，只拦性能悬崖，不做逐毫秒断言。
        XCTAssertLessThan(elapsedMS, 60_000, "全量排版超过 60s——性能悬崖式回归，先查最近的引擎/测量改动")
    }
}
