import CoreText
import Foundation
import LayoutDCore
import LayoutDEngine

/// 阶段 E1：把真实 `BookProject` + 排版结果 `LaidOutDocument` 映射成 IDML，交 InDesign
/// 人工精调 + 印前。结构沿用已在 InDesign 中文版验证通过的 spike(竖排 / 复合字体 /
/// 置入图 / 色板全部 round-trip，见 IDMLSpikeExporter）。
///
/// 最小可用版(MVP)的取舍——已覆盖：每页一个 Spread、文本框→Story(段落样式 + 竖排)、
/// 图片框→Rectangle+Image+Link、颜色 token→RGB 色板、复合字体→Fonts.xml 内 CompositeFont。
/// 暂未覆盖(后续增量，见 development-plan 阶段 E1)：固定美术页→MasterSpread、对开跨页、
/// 非矩形蒙版、字体样式名拆分。
///
/// 颜色按 layoutD 的 RGB 管线导出为 RGB 色板；CMYK 分色 / PDF/X 交 InDesign(印前路线 A)。
public struct IDMLExportOptions: Sendable {
    public var facingPages: Bool
    public var cmykColors: Bool

    public init(facingPages: Bool = false, cmykColors: Bool = false) {
        self.facingPages = facingPages
        self.cmykColors = cmykColors
    }
}

public struct IDMLExporter {
    public init() {}

    public enum ExportError: Error, LocalizedError {
        case zipFailed(String)
        /// 灌版打包前的不变量断言闸发现已知 CJK 保真搭档规则被违反（见 IDMLInvariants）。
        case invariantsFailed([IDMLInvariantViolation])
        public var errorDescription: String? {
            switch self {
            case .zipFailed(let d): return "IDML 打包失败：\(d)"
            case .invariantsFailed(let vs):
                return "IDML 保真断言未通过（\(vs.count) 项）：\n" + vs.map { "  · \($0)" }.joined(separator: "\n")
            }
        }
    }

    let header = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
    let pkgNS = "xmlns:idPkg=\"http://ns.adobe.com/AdobeInDesign/idml/1.0/packaging\""
    let dom = "16.0"
    // 着重号(Kenten)、避头尾等 CJK 排版特性只在 CJK/World-Ready 段落排版器下渲染；
    // 拉丁排版器会静默忽略 KentenKind。
    //
    // 经真·InDesign 2026 存盘比对(Desktop/未命名-1.idml → /tmp/idml-oracle, 2026-06-23):
    // ① 正确属性名是 Composer(不是 AppliedComposer——InDesign 无此属性、会被忽略);
    // ② 正确值是 "HL Composer J"(CJK/World-Ready, 无 $ID/ 前缀)——"HL Composer Optyca"
    //    其实是拉丁段落排版器(此前注释把中西身份搞反了);
    // ③ 真值挂在段落样式定义与文档 <TextDefault> 上, 不逐 Story 段落内联。
    // 故本导出器把 Composer 写进每个 ParagraphStyle + [No paragraph style] + TextDefault,
    // Story 段落不再写(已删除无效的 AppliedComposer)。
    let composer = "HL Composer J"
    let kinsokuTableSelf = "KinsokuTable/$ID/kSimpChineseKinsokuName"
    let mojikumiTableSelf = "MojikumiTable/$ID/kSimpChineseMojikumiName"

    // MARK: - 入口

    public func export(
        document: LaidOutDocument,
        project originalProject: BookProject,
        to url: URL,
        options: IDMLExportOptions = IDMLExportOptions()
    ) throws {
        let project = originalProject.prependingSectionNumbers()
        let pageW = project.pageSetup.pageSize.width
        let pageH = project.pageSetup.pageSize.height
        let pages = document.pages.sorted { $0.number < $1.number }
        let packagedLinks = packagedLinks(for: pages, assets: project.assets)
        let paragraphsByID = Dictionary(
            uniqueKeysWithValues: project.sections
                .flatMap(\.stories)
                .flatMap(\.paragraphs)
                .map { ($0.id, $0) }
        )

        // The global CMYK intent (or the explicit export toggle) flattens every
        // RGB swatch to Process CMYK on emit — non-destructively: stored model
        // values are untouched, only the exported swatches convert.
        let cmykOutput = options.cmykColors || project.pageSetup.colorSpace == .cmyk
        var ctx = BuildContext(project: project, cmykOutput: cmykOutput)
        let includesTOC = pages.contains { page in
            page.frames.contains { !($0.tableOfContentsEntries ?? []).isEmpty }
        }

        // 先扫一遍：注册颜色、字体、复合字体、段落样式所需资源。
        for style in project.styles.paragraphStyles {
            ctx.registerParagraphStyle(style)
        }
        if includesTOC {
            ctx.registerParagraphStyle(tocParagraphStyle(base: ctx.resolvedStyle(id: StyleID.heading2.rawValue), id: "tocLevel1", name: "目录一级"))
            ctx.registerParagraphStyle(tocParagraphStyle(base: ctx.resolvedStyle(id: StyleID.caption.rawValue), id: "tocLevel2", name: "目录二级", indent: 12))
        }
        // 各页 frame 的颜色覆盖也要登记成色板。
        for page in pages {
            for frame in page.frames {
                if let hex = frame.textColorHex { _ = ctx.color(hex) }
                if let hex = frame.backgroundColorHex { _ = ctx.color(hex) }
                if let hex = frame.strokeColorHex { _ = ctx.color(hex) }
                if let component = project.styles.componentStyle(for: frame.kind) {
                    if let hex = component.resolvedFillColorHex(project: project) { _ = ctx.color(hex) }
                    if let hex = component.resolvedStrokeColorHex(project: project) { _ = ctx.color(hex) }
                    if let hex = component.resolvedAccentColorHex(project: project) { _ = ctx.color(hex) }
                }
            }
        }

        // 注册所有 motif 的颜色与字体，防止未被 ParagraphStyle/Frame 包含的 motif 颜色漏掉
        if let motif = project.motifs {
            if let c = motif.chapterNumber?.color { _ = ctx.color(project.resolvedColorHex(c) ?? c) }
            if let f = motif.chapterNumber?.resolvedFontName { ctx.font(f) }
            if let c = motif.sectionNumber?.color { _ = ctx.color(project.resolvedColorHex(c) ?? c) }
            if let c = motif.header?.color { _ = ctx.color(project.resolvedColorHex(c) ?? c) }
            if let f = motif.header?.resolvedFontName { ctx.font(f) }
            if let c = motif.captionTick?.color { _ = ctx.color(project.resolvedColorHex(c) ?? c) }
            if let c = motif.headingRule?.color { _ = ctx.color(project.resolvedColorHex(c) ?? c) }
            if let c = motif.pullQuoteRule?.color { _ = ctx.color(project.resolvedColorHex(c) ?? c) }
        }

        // 注册所有段落 inline runs 中的颜色与字体
        for section in project.sections {
            for story in section.stories {
                for paragraph in story.paragraphs {
                    if let runs = paragraph.inlineRuns {
                        for run in runs {
                            if let colorToken = run.colorTokenRef {
                                let hex = project.resolvedColorHex(colorToken) ?? colorToken
                                _ = ctx.color(hex)
                            }
                        }
                    }
                }
            }
        }

        // 逐页构建 Spread + Story。
        var spreadRefs: [String] = []
        var storyRefs: [String] = []
        var spreadFiles: [String: String] = [:]
        var storyFiles: [String: String] = [:]
        var storyListIds: [String] = []

        // FRAME-SPLIT（2026-07-07 用户定，取代 THREAD-1b「章级串接」）：一个角色一个框——
        // 只有「纯正文」（styleId==body 的 body/listItem 段落）进串接文流；标题/开节概述/
        // 抽言/图注/参考文献/表格等一律独立框、各套各的段落样式，便于 InDesign 后期编辑。
        // 文流遇到任何独立框角色即「断流」：每段连续正文 = 一条独立串接 run（跨栏跨页
        // Previous/NextTextFrame 相连），断流之后的正文另起新 run。
        // 内嵌图锚定（THREAD-1b cut2）同日废除：所有图片一律独立定位框（图注框紧邻其后），
        // 绕排意图由 Asset.wrapMode 表达（wrap=正文避让绕排 / underlay=垫底画在文字下层）。
        // FRAME-CANVAS-0：分组计算本身已抽成跨模块共享函数 groupIntoFlowFrames（供画布/
        // PDF/PNG 的 FRAME-CANVAS-1 复用），此处只消费其结果。
        let grouping = groupIntoFlowFrames(pages: pages, project: project)
        let flowUnitsForRun: [Int: [FlowGroupKey]] = grouping.groupsByRun.mapValues { $0.map(\.key) }

        // 流 Story 的内容直接取 project.sections 的原文（未经 normalizedText 折行），
        // 与 frame 是否被拆分跨页无关——inlineRuns 天然对齐原文，无需二次映射。
        let flowVertical = project.pageSetup.layoutDirection == .vertical
        var flowStorySelf: [Int: String] = [:]
        let paragraphsForRun = grouping.paragraphsForRun
        for runIndex in flowUnitsForRun.keys.sorted() {
            var flowParagraphs: [ChapterParagraph] = []
            for paragraph in paragraphsForRun[runIndex] ?? [] {
                guard !paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let style = ctx.resolvedStyle(id: paragraph.styleId)
                let footnotes = paragraph.safeAnchoredFootnoteIds.compactMap { paragraphsByID[$0] }
                flowParagraphs.append(ChapterParagraph(
                    styleRef: "ParagraphStyle/\(xmlSafe(style.id))",
                    // 保留原文（不 trim），inlineRuns 的偏移量以 paragraph.text 为基准，
                    // trim 掉前导空白会让二者错位。
                    text: paragraph.text, inlineRuns: paragraph.inlineRuns, footnotes: footnotes,
                    footnoteStyleRef: footnoteStyleRef(for: footnotes, ctx: ctx)
                ))
            }
            guard !flowParagraphs.isEmpty else { continue }
            let storySelf = "uStoryFlow\(runIndex)"
            storyFiles["Stories/Story_\(storySelf).xml"] = chapterStoryXML(
                self: storySelf, vertical: flowVertical, paragraphs: flowParagraphs, project: project)
            storyRefs.append("\t<idPkg:Story src=\"Stories/Story_\(storySelf).xml\"/>")
            storyListIds.append(storySelf)
            flowStorySelf[runIndex] = storySelf
        }

        let facing = options.facingPages
        // 对开：首页(pi=0, recto 右)单独成 spread，其后每 2 页一 spread(verso 左 + recto 右)。
        // 每页内容按所在侧水平偏移 dx；非对开时 dx=0、每页独占一个 spread（现状不变）。
        var spreadBuilds: [[(pageSelf: String, pageName: String, transformX: Double, items: [String])]] = []
        for (pi, page) in pages.enumerated() {
            let recto = pi % 2 == 0
            let dx = facing ? (recto ? pageW / 2 : -pageW / 2) : 0
            // 页框 ItemTransform 的 x（绝对）：非对开居中于书脊(-pageW/2)；
            // 对开 recto 右(0, 框[0,pageW])、verso 左(-pageW, 框[-pageW,0])。
            let pageTransformX = facing ? (recto ? 0 : -pageW) : -pageW / 2
            var items: [String] = []
            var underlayItems: [String] = []

            // Page-level background color rectangle (PB-P0a)
            if let bgHex = project.resolvedPageBackgroundHex(for: page) {
                let resolvedHex = project.resolvedColorHex(bgHex) ?? bgHex
                let bgRect = Rect(x: 0, y: 0, width: pageW, height: pageH)
                let bgItem = colorRectangleItem(
                    self: "uPageBg\(pi)",
                    rect: bgRect,
                    fillColor: resolvedHex,
                    pageW: pageW,
                    pageH: pageH,
                    dx: dx
                )
                underlayItems.insert(bgItem, at: 0)
                _ = ctx.color(resolvedHex)
            }

            // Draw ghost chapter number motif if configured
            if let info = project.ghostChapterNumberInfo(for: page) {
                let ghostStoryId = "uStoryGhost\(pi)"
                let ghostStoryContent = motifStoryXML(
                    self: ghostStoryId,
                    text: info.text,
                    fontName: info.fontName,
                    fontSizePt: Double(info.fontSize),
                    fillColorHex: info.colorHex,
                    project: project
                )
                storyFiles["Stories/Story_\(ghostStoryId).xml"] = ghostStoryContent
                storyRefs.append("\t<idPkg:Story src=\"Stories/Story_\(ghostStoryId).xml\"/>")
                storyListIds.append(ghostStoryId)
                
                let ghostRect = Rect(x: info.rect.origin.x, y: info.rect.origin.y, width: info.rect.size.width, height: info.rect.size.height)
                let ghostFrameItem = textFrameItem(
                    self: "uGhostFrame\(pi)",
                    story: ghostStoryId,
                    rect: ghostRect,
                    fillColor: nil,
                    strokeColor: nil,
                    strokeWidth: 0,
                    pageW: pageW,
                    pageH: pageH,
                    dx: dx
                )
                if info.drawBehind {
                    underlayItems.append(ghostFrameItem)
                } else {
                    items.append(ghostFrameItem)
                }
            }

            // Draw custom header motif if configured
            if project.resolvedShowHeadersFooters(for: page.number),
               let header = project.motifs?.header {
                let activeSec = project.activeSection(for: page)
                let headerText = project.resolvedHeaderText(for: page.number, activeSection: activeSec)
                
                let fontName = header.resolvedFontName ?? "Heiti SC Medium"
                let fontSize = header.fontSizePt ?? 9.0
                let colorHex = project.resolvedColorHex(header.color ?? "grayText") ?? "#7F7F7F"
                
                let margins = project.resolvedMargins(for: page.number)
                let setup = project.pageSetup
                
                let leftMargin = margins.left
                let rightMargin = margins.right
                
                let headerY = 24.0
                let headerHeight = 16.0
                
                // Draw Thin line (细线通栏) if configured
                if let rule = header.rule, rule == "细线通栏" {
                    let lineY = headerY + headerHeight
                    let ruleRect = Rect(x: leftMargin, y: lineY, width: pageW - leftMargin - rightMargin, height: 0.5)
                    let ruleItem = graphicLineItem(
                        self: "uHeaderRule\(pi)",
                        rect: ruleRect,
                        strokeColor: colorHex,
                        strokeWidth: 0.5,
                        pageW: pageW,
                        pageH: pageH,
                        dx: dx
                    )
                    items.append(ruleItem)
                }
                
                let labelStr = headerText
                let pageNumStr = "\(page.number)"
                let showPageNum = header.showPageNumber
                
                if setup.facingPages {
                    let isLeftPage = page.number % 2 == 0
                    if isLeftPage {
                        if showPageNum {
                            let pageNumStoryId = "uStoryHeaderPage\(pi)"
                            let pageNumStoryContent = motifStoryXML(self: pageNumStoryId, text: pageNumStr, fontName: fontName, fontSizePt: fontSize, fillColorHex: colorHex, project: project, alignRight: false)
                            storyFiles["Stories/Story_\(pageNumStoryId).xml"] = pageNumStoryContent
                            storyRefs.append("\t<idPkg:Story src=\"Stories/Story_\(pageNumStoryId).xml\"/>")
                            storyListIds.append(pageNumStoryId)
                            
                            let pageNumRect = Rect(x: leftMargin, y: headerY, width: 50, height: headerHeight)
                            items.append(textFrameItem(self: "uHeaderPageFrame\(pi)", story: pageNumStoryId, rect: pageNumRect, fillColor: nil, strokeColor: nil, strokeWidth: 0, pageW: pageW, pageH: pageH, dx: dx))
                        }
                        
                        let textStoryId = "uStoryHeaderLabel\(pi)"
                        let textStoryContent = motifStoryXML(self: textStoryId, text: labelStr, fontName: fontName, fontSizePt: fontSize, fillColorHex: colorHex, project: project, alignRight: true)
                        storyFiles["Stories/Story_\(textStoryId).xml"] = textStoryContent
                        storyRefs.append("\t<idPkg:Story src=\"Stories/Story_\(textStoryId).xml\"/>")
                        storyListIds.append(textStoryId)
                        
                        let textW = pageW - leftMargin - rightMargin - (showPageNum ? 60 : 0)
                        let textX = leftMargin + (showPageNum ? 60 : 0)
                        let textRect = Rect(x: textX, y: headerY, width: textW, height: headerHeight)
                        items.append(textFrameItem(self: "uHeaderLabelFrame\(pi)", story: textStoryId, rect: textRect, fillColor: nil, strokeColor: nil, strokeWidth: 0, pageW: pageW, pageH: pageH, dx: dx))
                    } else {
                        let textStoryId = "uStoryHeaderLabel\(pi)"
                        let textStoryContent = motifStoryXML(self: textStoryId, text: labelStr, fontName: fontName, fontSizePt: fontSize, fillColorHex: colorHex, project: project, alignRight: false)
                        storyFiles["Stories/Story_\(textStoryId).xml"] = textStoryContent
                        storyRefs.append("\t<idPkg:Story src=\"Stories/Story_\(textStoryId).xml\"/>")
                        storyListIds.append(textStoryId)
                        
                        let textW = pageW - leftMargin - rightMargin - (showPageNum ? 60 : 0)
                        let textRect = Rect(x: leftMargin, y: headerY, width: textW, height: headerHeight)
                        items.append(textFrameItem(self: "uHeaderLabelFrame\(pi)", story: textStoryId, rect: textRect, fillColor: nil, strokeColor: nil, strokeWidth: 0, pageW: pageW, pageH: pageH, dx: dx))
                        
                        if showPageNum {
                            let pageNumStoryId = "uStoryHeaderPage\(pi)"
                            let pageNumStoryContent = motifStoryXML(self: pageNumStoryId, text: pageNumStr, fontName: fontName, fontSizePt: fontSize, fillColorHex: colorHex, project: project, alignRight: true)
                            storyFiles["Stories/Story_\(pageNumStoryId).xml"] = pageNumStoryContent
                            storyRefs.append("\t<idPkg:Story src=\"Stories/Story_\(pageNumStoryId).xml\"/>")
                            storyListIds.append(pageNumStoryId)
                            
                            let pageNumRect = Rect(x: pageW - rightMargin - 50, y: headerY, width: 50, height: headerHeight)
                            items.append(textFrameItem(self: "uHeaderPageFrame\(pi)", story: pageNumStoryId, rect: pageNumRect, fillColor: nil, strokeColor: nil, strokeWidth: 0, pageW: pageW, pageH: pageH, dx: dx))
                        }
                    }
                } else {
                    if showPageNum {
                        let pageNumStoryId = "uStoryHeaderPage\(pi)"
                        let pageNumStoryContent = motifStoryXML(self: pageNumStoryId, text: pageNumStr, fontName: fontName, fontSizePt: fontSize, fillColorHex: colorHex, project: project, alignRight: true)
                        storyFiles["Stories/Story_\(pageNumStoryId).xml"] = pageNumStoryContent
                        storyRefs.append("\t<idPkg:Story src=\"Stories/Story_\(pageNumStoryId).xml\"/>")
                        storyListIds.append(pageNumStoryId)
                        
                        let pageNumRect = Rect(x: pageW - rightMargin - 50, y: headerY, width: 50, height: headerHeight)
                        items.append(textFrameItem(self: "uHeaderPageFrame\(pi)", story: pageNumStoryId, rect: pageNumRect, fillColor: nil, strokeColor: nil, strokeWidth: 0, pageW: pageW, pageH: pageH, dx: dx))
                    }
                    let textStoryId = "uStoryHeaderLabel\(pi)"
                    let textStoryContent = motifStoryXML(self: textStoryId, text: labelStr, fontName: fontName, fontSizePt: fontSize, fillColorHex: colorHex, project: project, alignRight: false)
                    storyFiles["Stories/Story_\(textStoryId).xml"] = textStoryContent
                    storyRefs.append("\t<idPkg:Story src=\"Stories/Story_\(textStoryId).xml\"/>")
                    storyListIds.append(textStoryId)
                    
                    let textW = pageW - leftMargin - rightMargin - (showPageNum ? 60 : 0)
                    let textRect = Rect(x: leftMargin, y: headerY, width: textW, height: headerHeight)
                    items.append(textFrameItem(self: "uHeaderLabelFrame\(pi)", story: textStoryId, rect: textRect, fillColor: nil, strokeColor: nil, strokeWidth: 0, pageW: pageW, pageH: pageH, dx: dx))
                }
            }

            for (fi, frame) in page.frames.enumerated() {
                if frame.kind == .runningHeader && project.motifs?.header != nil {
                    continue
                }
                switch frame.content {
                case .text(let raw):
                    // 脚注由锚点 Story 内的原生 <Footnote> 承载。LayoutEngine 仍会
                    // 为 Canvas/PDF/PNG 生成页脚 frame；IDML 不能再把那份 frame 当
                    // 普通正文导出，否则 InDesign 会出现两份脚注内容。
                    guard frame.kind != .footnote else { continue }
                    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if text.isEmpty {
                        // A hand-drawn box: empty text but carrying a fill/stroke.
                        // Emit it as a rectangle so it isn't silently dropped. A
                        // truly empty flow frame (no fill, no stroke) stays skipped
                        // — it would be invisible in InDesign anyway.
                        let boxFill = frame.backgroundColorHex
                        let boxStroke = frame.strokeColorHex
                        if boxFill != nil || boxStroke != nil {
                            let boxStrokeWidth = frame.strokeWidth ?? (boxStroke != nil ? 1 : 0)
                            items.append(drawnBoxItem(self: "uBox\(pi)_\(fi)", rect: frame.rect,
                                                      fillColor: boxFill, strokeColor: boxStroke,
                                                      strokeWidth: boxStrokeWidth,
                                                      pageW: pageW, pageH: pageH, dx: dx))
                        }
                        continue
                    }
                    // 已并入正文串接流；合并后的 TextFrame 在本页 frame 循环结束后统一追加一次。
                    if let runIndex = grouping.frameRunIndex[FlowFrameKey(page: pi, frame: fi)],
                       flowStorySelf[runIndex] != nil {
                        continue
                    }
                    let storySelf = "uStory\(pi)_\(fi)"
                    let style = ctx.resolvedStyle(id: frame.styleId)
                    let styleRef = "ParagraphStyle/\(xmlSafe(style.id))"
                    let vertical = style.layoutDirection == .vertical
                    let component = project.styles.componentStyle(for: frame.kind)
                    let resolvedFillHex = frame.backgroundColorHex ?? component?.resolvedFillColorHex(project: project)
                    // 表格底色挪到单元格上（见下方 tableStoryXML），框本身不填色——否则框比
                    // 表格高时底部会露出一块多余色块。
                    let fillColor = frame.kind == .table ? nil : resolvedFillHex
                    let strokeColor = frame.strokeColorHex ?? component?.resolvedStrokeColorHex(project: project)
                    let strokeWidth = frame.strokeWidth ?? component?.strokeWidth ?? 0

                    // Paragraph accent rule (抽言左侧明黄竖线): the frame has no
                    // component, so shrink the text frame left and place the bar in
                    // the reclaimed strip (matches the PDF/PNG/Canvas preview).
                    var textFrameRect = frame.rect
                    var paragraphAccent: (rect: Rect, color: String)? = nil
                    if let rule = style.accentRule,
                       let ruleHex = project.resolvedColorHex(rule.colorToken),
                       rule.width > 0 {
                        if rule.edge == .left, frame.rect.width > rule.width + rule.gap {
                            let barRect = Rect(x: frame.rect.x, y: frame.rect.y,
                                               width: rule.width, height: frame.rect.height)
                            textFrameRect = Rect(x: frame.rect.x + rule.width + rule.gap, y: frame.rect.y,
                                                 width: frame.rect.width - rule.width - rule.gap,
                                                 height: frame.rect.height)
                            paragraphAccent = (barRect, ruleHex)
                        } else if rule.edge == .top, frame.rect.height > rule.width + rule.gap {
                            let barLength = rule.length ?? frame.rect.width
                            let barRect = Rect(x: frame.rect.x, y: frame.rect.y,
                                               width: min(barLength, frame.rect.width), height: rule.width)
                            textFrameRect = Rect(x: frame.rect.x, y: frame.rect.y + rule.width + rule.gap,
                                                 width: frame.rect.width,
                                                 height: frame.rect.height - rule.width - rule.gap)
                            paragraphAccent = (barRect, ruleHex)
                        } else if rule.edge == .bottom, frame.rect.height > rule.width + rule.gap {
                            let barLength = rule.length ?? frame.rect.width
                            let barRect = Rect(x: frame.rect.x, y: frame.rect.y + frame.rect.height - rule.width,
                                               width: min(barLength, frame.rect.width), height: rule.width)
                            textFrameRect = Rect(x: frame.rect.x, y: frame.rect.y,
                                                 width: frame.rect.width,
                                                 height: frame.rect.height - rule.width - rule.gap)
                            paragraphAccent = (barRect, ruleHex)
                        }
                    }

                    items.append(textFrameItem(self: "uTF\(pi)_\(fi)", story: storySelf,
                                               rect: textFrameRect, fillColor: fillColor,
                                               strokeColor: strokeColor, strokeWidth: strokeWidth,
                                               pageW: pageW, pageH: pageH, dx: dx))
                    // Accent 必须位于有底色的文本框之上，否则会被框架填色遮住。
                    if let accentColor = component?.resolvedAccentColorHex(project: project),
                       let accentWidth = component?.accentWidth, accentWidth > 0 {
                        let accentRect = Rect(x: frame.rect.x, y: frame.rect.y,
                                              width: min(accentWidth, frame.rect.width), height: frame.rect.height)
                        items.append(colorRectangleItem(self: "uAccent\(pi)_\(fi)", rect: accentRect,
                                                        fillColor: accentColor, pageW: pageW, pageH: pageH, dx: dx))
                    }
                    if let pa = paragraphAccent {
                        items.append(colorRectangleItem(self: "uPAccent\(pi)_\(fi)", rect: pa.rect,
                                                        fillColor: pa.color, pageW: pageW, pageH: pageH, dx: dx))
                    }
                    // 原生表格：源段是 .table 且带结构化行列时，Story 内输出 InDesign
                    // <Table>（真行列/可调宽），而非把拍平文本当普通段落画。
                    if frame.kind == .table,
                       let paragraphID = frame.sourceParagraphId,
                       let cells = paragraphsByID[paragraphID]?.tableCells,
                       !cells.isEmpty {
                        let cellFillSwatch = resolvedFillHex.map { ctx.color($0) }
                        storyFiles["Stories/Story_\(storySelf).xml"] = tableStoryXML(
                            self: storySelf, styleRef: styleRef, cells: cells,
                            cellRuns: paragraphsByID[paragraphID]?.tableCellRuns,
                            frameWidth: frame.rect.width, cellFillSwatch: cellFillSwatch,
                            project: project)
                        storyRefs.append("\t<idPkg:Story src=\"Stories/Story_\(storySelf).xml\"/>")
                        storyListIds.append(storySelf)
                        continue
                    }
                    if let entries = frame.tableOfContentsEntries, !entries.isEmpty {
                        storyFiles["Stories/Story_\(storySelf).xml"] = tocStoryXML(
                            self: storySelf,
                            entries: entries,
                            frameWidth: frame.rect.width
                        )
                        storyRefs.append("\t<idPkg:Story src=\"Stories/Story_\(storySelf).xml\"/>")
                        storyListIds.append(storySelf)
                        continue
                    }
                    let frameInlineRuns: [InlineRun]?
                    if let paragraphID = frame.sourceParagraphId,
                       let paragraph = paragraphsByID[paragraphID] {
                        frameInlineRuns = inlineRuns(for: text, from: paragraph)
                    } else {
                        frameInlineRuns = nil
                    }
                    let frameFootnotes: [Paragraph]
                    if let paragraphID = frame.sourceParagraphId,
                       let paragraph = paragraphsByID[paragraphID] {
                        frameFootnotes = paragraph.safeAnchoredFootnoteIds.compactMap { paragraphsByID[$0] }
                    } else {
                        frameFootnotes = []
                    }
                    let storyContent = storyXML(self: storySelf, styleRef: styleRef,
                                                vertical: vertical, text: text, inlineRuns: frameInlineRuns,
                                                footnotes: frameFootnotes,
                                                footnoteStyleRef: footnoteStyleRef(for: frameFootnotes, ctx: ctx),
                                                project: project)
                    storyFiles["Stories/Story_\(storySelf).xml"] = storyContent
                    storyRefs.append("\t<idPkg:Story src=\"Stories/Story_\(storySelf).xml\"/>")
                    storyListIds.append(storySelf)
                case .asset(let id), .spreadAsset(let id, _):
                    guard let asset = project.assets.first(where: { $0.id == id }) else { continue }
                    // 绕排意图：wrap（默认）带 TextWrapPreference 让正文避让；underlay 垫底
                    // ——不绕排且画在本页最底层（文字直接压在图上走）。
                    let underlay = asset.effectiveWrapMode == .underlay
                    let item = imageItem(self: "uRect\(pi)_\(fi)", imageSelf: "uImg\(pi)_\(fi)",
                                         linkSelf: "uLink\(pi)_\(fi)", asset: asset,
                                         packagedFileName: packagedLinks[asset.id]?.fileName,
                                         rect: frame.rect, maskShape: frame.maskShape,
                                         pageW: pageW, pageH: pageH, dx: dx,
                                         textWrap: !underlay)
                    if underlay { underlayItems.append(item) } else { items.append(item) }
                case .empty:
                    // Drawn shapes have no content → export as an Unassigned Rectangle.
                    // Rectangle: fill (+ optional stroke). Line: a centered thin filled
                    // rectangle whose thin dimension is the stroke weight.
                    if frame.kind == .rectangle, let fill = frame.backgroundColorHex {
                        items.append(colorRectangleItem(
                            self: "uShape\(pi)_\(fi)", rect: frame.rect, fillColor: fill,
                            strokeColor: frame.strokeColorHex, strokeWidth: frame.strokeWidth ?? 0,
                            pageW: pageW, pageH: pageH, dx: dx))
                    } else if frame.kind == .line, let color = frame.strokeColorHex {
                        items.append(graphicLineItem(
                            self: "uShape\(pi)_\(fi)", rect: frame.rect,
                            strokeColor: color, strokeWidth: frame.strokeWidth ?? 1,
                            pageW: pageW, pageH: pageH, dx: dx))
                    }
                    continue
                }
            }

            for group in grouping.groupsByPage[pi] ?? [] {
                guard let storySelf = flowStorySelf[group.key.run] else { continue }
                let rect = group.rect
                let chain = group.chain
                items.append(textFrameItem(self: chain.selfId, story: storySelf, rect: rect,
                                           fillColor: nil, strokeColor: nil, strokeWidth: 0,
                                           pageW: pageW, pageH: pageH, dx: dx,
                                           previous: chain.previous, next: chain.next))
            }

            let pageBuild = (pageSelf: "uPage\(pi)", pageName: "\(page.number)", transformX: pageTransformX, items: underlayItems + items)
            let si = facing ? (pi + 1) / 2 : pi
            if si >= spreadBuilds.count { spreadBuilds.append([]) }
            spreadBuilds[si].append(pageBuild)
        }
        for (si, spreadPages) in spreadBuilds.enumerated() {
            let spreadSelf = "uSpread\(si)"
            spreadFiles["Spreads/Spread_\(spreadSelf).xml"] =
                spreadXML(self: spreadSelf, spreadY: Double(si) * pageH * 1.235,
                          pageW: pageW, pageH: pageH, pages: spreadPages)
            spreadRefs.append("\t<idPkg:Spread src=\"Spreads/Spread_\(spreadSelf).xml\"/>")
        }

        // MASTER-1：主页放一个自动页码 TextFrame；正文页 AppliedMaster="uMasterA" 已经
        // 在逐页构建时统一设置，套上主页即自动出正确页码，不用逐页画。位置沿用现有
        // PDF/PNG 页码的靠页面上方居中做法，先不做对开镜像（留给 SPREAD-1 一起做）。
        let masterPageNumberStorySelf = "uMasterPageNumberStory"
        storyFiles["Stories/Story_\(masterPageNumberStorySelf).xml"] = masterPageNumberStoryXML(self: masterPageNumberStorySelf)
        storyRefs.append("\t<idPkg:Story src=\"Stories/Story_\(masterPageNumberStorySelf).xml\"/>")
        storyListIds.append(masterPageNumberStorySelf)
        let masterPageNumberRect = Rect(x: pageW / 2 - 30, y: 20, width: 60, height: 16)
        let masterPageNumberItem = textFrameItem(
            self: "uMasterPageNumberTF", story: masterPageNumberStorySelf, rect: masterPageNumberRect,
            fillColor: nil, strokeColor: nil, strokeWidth: 0, pageW: pageW, pageH: pageH)

        let showMasterPageNumber = !(project.motifs?.header?.showPageNumber ?? false)
        let masterItems = showMasterPageNumber ? [masterPageNumberItem] : []

        // 组装包内所有部件。
        var files: [String: String] = [
            "mimetype": "application/vnd.adobe.indesign-idml-package",
            "META-INF/container.xml": container(),
            "META-INF/metadata.xml": metadata(),
            "Resources/Graphic.xml": graphic(ctx: ctx),
            "Resources/Fonts.xml": fonts(ctx: ctx),
            "Resources/Styles.xml": styles(ctx: ctx, includesTOC: includesTOC),
            "Resources/Preferences.xml": preferences(pageW: pageW, pageH: pageH, pageCount: pages.count, facing: facing),
            "XML/Tags.xml": tags(),
            "XML/BackingStory.xml": backingStory(),
            "MasterSpreads/MasterSpread_uMasterA.xml": masterSpread(pageW: pageW, pageH: pageH, items: masterItems),
            "designmap.xml": designmap(spreadRefs: spreadRefs, storyRefs: storyRefs, storyList: storyListIds)
        ]
        files.merge(spreadFiles) { _, b in b }
        files.merge(storyFiles) { _, b in b }

        // 打包前过一遍不变量断言闸：锁住已知的 CJK 渲染搭档规则，撞回归当场报错而非等 InDesign。
        let violations = IDMLInvariants.check(files: files)
        guard violations.isEmpty else { throw ExportError.invariantsFailed(violations) }

        try writePackage(files: files, to: url)
        try copyPackagedLinks(packagedLinks.values, beside: url)
    }

    func motifStoryXML(
        self id: String,
        text: String,
        fontName: String,
        fontSizePt: Double,
        fillColorHex: String?,
        project: BookProject,
        alignRight: Bool = false
    ) -> String {
        let orientation = "Horizontal"
        let direction = "LeftToRightDirection"
        
        let justification = alignRight ? "RightAlign" : "LeftAlign"
        let colorRefVal: String
        if let hex = fillColorHex {
            colorRefVal = colorRef(hex)
        } else {
            colorRefVal = "Color/Black"
        }
        
        return """
        \(header)
        <idPkg:Story \(pkgNS) DOMVersion="\(dom)">
        \t<Story Self="\(id)" AppliedTOCStyle="n" TrackChanges="false" StoryTitle="$ID/" AppliedNamedGrid="n">
        \t\t<StoryPreference OpticalMarginAlignment="false" OpticalMarginSize="12" FrameType="TextFrameType" StoryOrientation="\(orientation)" StoryDirection="\(direction)"/>
        \t\t<ParagraphStyleRange AppliedParagraphStyle="ParagraphStyle/$ID/[No paragraph style]" Justification="\(justification)">
        \t\t\t<CharacterStyleRange AppliedCharacterStyle="CharacterStyle/$ID/[No character style]" AppliedFont="\(xmlSafe(fontName))" PointSize="\(fmt(fontSizePt))" FillColor="\(colorRefVal)">
        \t\t\t\t<Content>\(xmlSafe(text))</Content>
        \t\t\t</CharacterStyleRange>
        \t\t</ParagraphStyleRange>
        \t</Story>
        </idPkg:Story>
        """
    }

}
