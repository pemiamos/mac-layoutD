import Foundation
import LayoutDCore

// FRAME-CANVAS-0：把 IDMLExporter 里「连续正文按断流分组、按 (run,页,栏) 合并 unionRect」
// 的逻辑抽成跨模块共享函数（原实现见 FRAME-SPLIT）。IDML 导出器与画布/PDF/PNG 预览
// （FRAME-CANVAS-1）共用同一份分组结果，避免两套断流判定分裂维护、以后改一处忘了改
// 另一处。行为完全不变——只是把计算过程挪到这里。

public struct FlowFrameKey: Hashable, Sendable {
    public let page: Int
    public let frame: Int
    public init(page: Int, frame: Int) {
        self.page = page
        self.frame = frame
    }
}

public struct FlowGroupKey: Hashable, Sendable {
    public let run: Int
    public let page: Int
    public let column: Int
    public init(run: Int, page: Int, column: Int) {
        self.run = run
        self.page = page
        self.column = column
    }
}

public struct FlowChainInfo: Sendable {
    public let selfId: String
    public let previous: String
    public let next: String
}

public struct FlowFrameGroup: Sendable {
    public let key: FlowGroupKey
    public let rect: Rect
    public let chain: FlowChainInfo
    /// 组内原始 frame 在 `pages[key.page].frames`（按 number 排序后）的下标，按出现顺序。
    public let memberFrameIndices: [Int]
}

public struct FlowFrameGrouping: Sendable {
    /// (页下标, frame下标) → 断流后正文流 run 序号；只含被判定为纯正文且非空的文字 frame。
    public let frameRunIndex: [FlowFrameKey: Int]
    /// run 序号 → 该 run 内所有段落（原文顺序，未拆分/未归一化），供 Story 内容使用。
    public let paragraphsForRun: [Int: [Paragraph]]
    /// 页下标 → 该页出现的分组（按遇到顺序）。
    public let groupsByPage: [Int: [FlowFrameGroup]]
    /// run → 该 run 经过的分组（跨页/栏，按顺序）——用于生成 Previous/NextTextFrame 链。
    public let groupsByRun: [Int: [FlowFrameGroup]]
}

/// FRAME-SPLIT（2026-07-07 用户定）：串接文流**只收纯正文**——styleId 必须是 body
/// （一本书正文统一一个段落样式），kind 限 body/listItem。标题/开节概述/抽言/图注/
/// 参考文献等角色段落（kind 可能也是 .body 但 styleId 不同）一律独立框、各套各的
/// 段落样式；表格/脚注/旁注/图片本就独立。文流遇到任何独立框角色即断流。
public func isBodyFlowParagraph(_ paragraph: Paragraph) -> Bool {
    guard paragraph.styleId == StyleID.body.rawValue else { return false }
    switch paragraph.kind {
    case .body, .listItem:
        return true
    default:
        return false
    }
}

private func unionRect(_ a: Rect, _ b: Rect) -> Rect {
    let minX = min(a.x, b.x)
    let minY = min(a.y, b.y)
    let maxX = max(a.x + a.width, b.x + b.width)
    let maxY = max(a.y + a.height, b.y + b.height)
    return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}

/// FRAME-SPLIT 断流分组入口。前置页数（封面恒 1 页，目录仅 `includesTableOfContents`
/// 时 +1）与 `frontMatterPageCount(for:)` 保持一致——前置页天然不参与串接。
public func groupIntoFlowFrames(pages: [LaidOutPage], project: BookProject) -> FlowFrameGrouping {
    let runIndexByParagraphId: [UUID: Int] = {
        var map: [UUID: Int] = [:]
        var run = 0
        var runHasContent = false
        func closeRun() {
            if runHasContent { run += 1; runHasContent = false }
        }
        for section in project.sections {
            closeRun() // 章边界必断流
            for story in section.stories {
                for paragraph in story.paragraphs {
                    if isBodyFlowParagraph(paragraph) {
                        map[paragraph.id] = run
                        runHasContent = true
                    } else {
                        closeRun() // 独立框角色（标题/抽言/图/表…）切断正文流
                    }
                }
            }
        }
        return map
    }()

    var frameRunIndex: [FlowFrameKey: Int] = [:]
    var runsOnPage: [Int: [FlowGroupKey]] = [:]      // pageIndex -> 该页出现的(run,栏)（去重，出现顺序）
    var flowUnitsForRun: [Int: [FlowGroupKey]] = [:] // run -> 该流经过的(页,栏)（去重，出现顺序）
    var rectForRunPage: [FlowGroupKey: Rect] = [:]
    var membersForRunPage: [FlowGroupKey: [Int]] = [:]

    let frontMatterPages = project.pageSetup.includesTableOfContents ? 2 : 1
    let sortedPages = pages.sorted { $0.number < $1.number }
    for (pi, page) in sortedPages.enumerated() where page.number > frontMatterPages {
        for (fi, frame) in page.frames.enumerated() {
            // 只认领纯正文段落的文字框；章名标题（无 sourceParagraphId）与标题/抽言等
            // 角色段落一律独立成框，不进这份分组。
            guard frame.kind == .text, case .text(let raw) = frame.content,
                  !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let pid = frame.sourceParagraphId,
                  let runIndex = runIndexByParagraphId[pid] else { continue }
            frameRunIndex[FlowFrameKey(page: pi, frame: fi)] = runIndex
            let column = Int((frame.rect.x * 4).rounded())
            let key = FlowGroupKey(run: runIndex, page: pi, column: column)
            if let existing = rectForRunPage[key] {
                rectForRunPage[key] = unionRect(existing, frame.rect)
                membersForRunPage[key, default: []].append(fi)
            } else {
                rectForRunPage[key] = frame.rect
                membersForRunPage[key] = [fi]
                runsOnPage[pi, default: []].append(key)
                flowUnitsForRun[runIndex, default: []].append(key)
            }
        }
    }

    var chainForKey: [FlowGroupKey: FlowChainInfo] = [:]
    for (runIndex, units) in flowUnitsForRun {
        for (k, unitKey) in units.enumerated() {
            let selfId = "uFlowTF\(runIndex)_\(k)"
            let previous = k == 0 ? "n" : "uFlowTF\(runIndex)_\(k - 1)"
            let next = k == units.count - 1 ? "n" : "uFlowTF\(runIndex)_\(k + 1)"
            chainForKey[unitKey] = FlowChainInfo(selfId: selfId, previous: previous, next: next)
        }
    }

    func makeGroup(_ key: FlowGroupKey) -> FlowFrameGroup? {
        guard let rect = rectForRunPage[key], let chain = chainForKey[key] else { return nil }
        return FlowFrameGroup(key: key, rect: rect, chain: chain, memberFrameIndices: membersForRunPage[key] ?? [])
    }

    var groupsByPage: [Int: [FlowFrameGroup]] = [:]
    for (pi, keys) in runsOnPage {
        groupsByPage[pi] = keys.compactMap(makeGroup)
    }
    var groupsByRun: [Int: [FlowFrameGroup]] = [:]
    for (run, keys) in flowUnitsForRun {
        groupsByRun[run] = keys.compactMap(makeGroup)
    }

    // 流 Story 的内容直接取 project.sections 的原文（未经 normalizedText 折行），
    // 与 frame 是否被拆分跨页无关——inlineRuns 天然对齐原文，无需二次映射。
    var paragraphsForRun: [Int: [Paragraph]] = [:]
    for section in project.sections {
        for story in section.stories {
            for paragraph in story.paragraphs {
                guard let runIndex = runIndexByParagraphId[paragraph.id] else { continue }
                paragraphsForRun[runIndex, default: []].append(paragraph)
            }
        }
    }

    return FlowFrameGrouping(
        frameRunIndex: frameRunIndex,
        paragraphsForRun: paragraphsForRun,
        groupsByPage: groupsByPage,
        groupsByRun: groupsByRun
    )
}
