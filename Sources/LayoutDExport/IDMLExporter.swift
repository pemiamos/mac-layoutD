import CoreText
import Foundation
import LayoutDCore

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
        project: BookProject,
        to url: URL,
        options: IDMLExportOptions = IDMLExportOptions()
    ) throws {
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

        // 逐页构建 Spread + Story。
        var spreadRefs: [String] = []
        var storyRefs: [String] = []
        var spreadFiles: [String: String] = [:]
        var storyFiles: [String: String] = [:]
        var storyListIds: [String] = []

        // THREAD-1b 第一刀：把「章名/节名 + 正文」按章合成一条串接 Story，逐页框
        // Previous/NextTextFrame 首尾相连；图片/抽言/表格/脚注/旁注/运行页眉仍走原逐帧
        // 独立 Story（本刀不动，留给后续几刀）。前置页（封面/目录，page.number ≤
        // frontMatterPageCount）天然被排除，不参与串接。
        let sectionIndexByParagraphId: [UUID: Int] = {
            var map: [UUID: Int] = [:]
            for (idx, section) in project.sections.enumerated() {
                for story in section.stories {
                    for paragraph in story.paragraphs {
                        map[paragraph.id] = idx
                    }
                }
            }
            return map
        }()

        var frameSectionIndex: [FrameKey: Int] = [:]
        var sectionsOnPage: [Int: [SectionPageKey]] = [:]   // pageIndex -> 该页出现的(章,栏)（去重，出现顺序）
        var flowUnitsForSection: [Int: [SectionPageKey]] = [:] // sectionIndex -> 该章流经的(页,栏)（去重，出现顺序）
        var rectForSectionPage: [SectionPageKey: Rect] = [:]
        var nextOrphanSectionIndex = 0
        // 前置页数与 LayoutEngine.frontMatterPageCount(for:) 保持一致：封面恒 1 页，
        // 目录仅在 includesTableOfContents 时 +1（默认关）。前置页天然不参与章串接。
        let frontMatterPages = project.pageSetup.includesTableOfContents ? 2 : 1
        for (pi, page) in pages.enumerated() where page.number > frontMatterPages {
            for (fi, frame) in page.frames.enumerated() {
                guard frame.kind == .text, case .text(let raw) = frame.content,
                      !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                // 章名标题（addSectionTitle）没有 sourceParagraphId，但每章只出现一次、且
                // 必定在该章第一个正文段落之前发出——用一个只增计数器即可精确认领，无需回看。
                let sectionIndex: Int
                if let pid = frame.sourceParagraphId, let idx = sectionIndexByParagraphId[pid] {
                    sectionIndex = idx
                } else {
                    sectionIndex = nextOrphanSectionIndex
                    nextOrphanSectionIndex += 1
                }
                frameSectionIndex[FrameKey(page: pi, frame: fi)] = sectionIndex
                let column = Int((frame.rect.x * 4).rounded())
                let key = SectionPageKey(section: sectionIndex, page: pi, column: column)
                if let existing = rectForSectionPage[key] {
                    rectForSectionPage[key] = unionRect(existing, frame.rect)
                } else {
                    rectForSectionPage[key] = frame.rect
                    sectionsOnPage[pi, default: []].append(key)
                    flowUnitsForSection[sectionIndex, default: []].append(key)
                }
            }
        }

        // THREAD-1b cut 2（图片锚定对象，最小可行范围）：只处理挂在正文段落
        // `anchoredAssetIds` 上、且该段落本身在本章串接文流里的图片——转成嵌入所属段落
        // 文流内的锚定对象，随文重排移动。孤立的 `.figure` 段落、抽言（callout）、图注仍
        // 保持独立定位框（本刀范围之外，留给后续迭代）。
        var anchoredAssetsByParagraphId: [UUID: [(asset: Asset, rect: Rect, packagedFileName: String?)]] = [:]
        var anchoredImageFrameKeys: Set<FrameKey> = []
        for (pi, page) in pages.enumerated() where page.number > 2 {
            for (fi, frame) in page.frames.enumerated() {
                // 只吃「挂在正文段落 anchoredAssetIds 上」的图。孤立的 `.figure` 段落自己就是
                // 图的宿主段落、被 isBodyFlowParagraph 排除在文流之外——它的图不能被这里认领，
                // 否则两头都进不去（既不进锚定对象，独立定位框那条路也被跳过），图片直接消失。
                guard frame.kind == .image, case .asset(let assetId) = frame.content,
                      let pid = frame.sourceParagraphId, sectionIndexByParagraphId[pid] != nil,
                      let hostKind = paragraphsByID[pid]?.kind, isBodyFlowParagraph(hostKind),
                      let asset = project.assets.first(where: { $0.id == assetId }) else { continue }
                anchoredAssetsByParagraphId[pid, default: []].append(
                    (asset: asset, rect: frame.rect, packagedFileName: packagedLinks[assetId]?.fileName))
                anchoredImageFrameKeys.insert(FrameKey(page: pi, frame: fi))
            }
        }

        var chainForSectionPage: [SectionPageKey: ChainInfo] = [:]
        for (sectionIndex, units) in flowUnitsForSection {
            for (k, unitKey) in units.enumerated() {
                let selfId = "uChapterTF\(sectionIndex)_\(k)"
                let previous = k == 0 ? "n" : "uChapterTF\(sectionIndex)_\(k - 1)"
                let next = k == units.count - 1 ? "n" : "uChapterTF\(sectionIndex)_\(k + 1)"
                chainForSectionPage[unitKey] = ChainInfo(selfId: selfId, previous: previous, next: next)
            }
        }

        // 章 Story 的内容直接取 project.sections 的原文（未经 normalizedText 折行），
        // 与 frame 是否被拆分跨页无关——inlineRuns 天然对齐原文，无需二次映射。
        let chapterVertical = project.pageSetup.layoutDirection == .vertical
        var chapterStorySelf: [Int: String] = [:]
        for sectionIndex in flowUnitsForSection.keys.sorted() {
            let section = project.sections[sectionIndex]
            var chapterParagraphs: [ChapterParagraph] = []
            let title = section.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                let headingStyle = ctx.resolvedStyle(id: StyleID.heading1.rawValue)
                chapterParagraphs.append(ChapterParagraph(
                    styleRef: "ParagraphStyle/\(xmlSafe(headingStyle.id))",
                    text: title, inlineRuns: nil, footnotes: [],
                    footnoteStyleRef: "ParagraphStyle/$ID/[No paragraph style]"
                ))
            }
            for story in section.stories {
                for paragraph in story.paragraphs {
                    guard isBodyFlowParagraph(paragraph.kind) else { continue }
                    let anchoredAssets = anchoredAssetsByParagraphId[paragraph.id] ?? []
                    // 段落文字可能是空的（比如 DOCX 里专门用来装图的段落）——只要挂了锚定
                    // 对象就不能跳过，否则图片既不进文流也不再独立出框，直接从导出里消失。
                    guard !paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !anchoredAssets.isEmpty else { continue }
                    let style = ctx.resolvedStyle(id: paragraph.styleId)
                    let footnotes = paragraph.safeAnchoredFootnoteIds.compactMap { paragraphsByID[$0] }
                    chapterParagraphs.append(ChapterParagraph(
                        styleRef: "ParagraphStyle/\(xmlSafe(style.id))",
                        // 保留原文（不 trim），inlineRuns 的偏移量以 paragraph.text 为基准，
                        // trim 掉前导空白会让二者错位。
                        text: paragraph.text, inlineRuns: paragraph.inlineRuns, footnotes: footnotes,
                        footnoteStyleRef: footnoteStyleRef(for: footnotes, ctx: ctx),
                        anchoredAssets: anchoredAssets
                    ))
                }
            }
            guard !chapterParagraphs.isEmpty else { continue }
            let storySelf = "uStoryChapter\(sectionIndex)"
            storyFiles["Stories/Story_\(storySelf).xml"] = chapterStoryXML(
                self: storySelf, vertical: chapterVertical, paragraphs: chapterParagraphs)
            storyRefs.append("\t<idPkg:Story src=\"Stories/Story_\(storySelf).xml\"/>")
            storyListIds.append(storySelf)
            chapterStorySelf[sectionIndex] = storySelf
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

            for (fi, frame) in page.frames.enumerated() {
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
                    // 已并入本章串接 Story；合并后的 TextFrame 在本页 frame 循环结束后统一追加一次。
                    if let sectionIndex = frameSectionIndex[FrameKey(page: pi, frame: fi)],
                       chapterStorySelf[sectionIndex] != nil {
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
                    items.append(textFrameItem(self: "uTF\(pi)_\(fi)", story: storySelf,
                                               rect: frame.rect, fillColor: fillColor,
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
                            frameWidth: frame.rect.width, cellFillSwatch: cellFillSwatch)
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
                                                footnoteStyleRef: footnoteStyleRef(for: frameFootnotes, ctx: ctx))
                    storyFiles["Stories/Story_\(storySelf).xml"] = storyContent
                    storyRefs.append("\t<idPkg:Story src=\"Stories/Story_\(storySelf).xml\"/>")
                    storyListIds.append(storySelf)
                case .asset(let id), .spreadAsset(let id, _):
                    // 已转为锚定对象、嵌进所属段落的文流里，这里不再重复画一个独立定位框。
                    if anchoredImageFrameKeys.contains(FrameKey(page: pi, frame: fi)) { continue }
                    guard let asset = project.assets.first(where: { $0.id == id }) else { continue }
                    items.append(imageItem(self: "uRect\(pi)_\(fi)", imageSelf: "uImg\(pi)_\(fi)",
                                           linkSelf: "uLink\(pi)_\(fi)", asset: asset,
                                           packagedFileName: packagedLinks[asset.id]?.fileName,
                                           rect: frame.rect, maskShape: frame.maskShape, pageW: pageW, pageH: pageH, dx: dx))
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

            for unitKey in sectionsOnPage[pi] ?? [] {
                guard let storySelf = chapterStorySelf[unitKey.section],
                      let rect = rectForSectionPage[unitKey],
                      let chain = chainForSectionPage[unitKey] else { continue }
                items.append(textFrameItem(self: chain.selfId, story: storySelf, rect: rect,
                                           fillColor: nil, strokeColor: nil, strokeWidth: 0,
                                           pageW: pageW, pageH: pageH, dx: dx,
                                           previous: chain.previous, next: chain.next))
            }

            let pageBuild = (pageSelf: "uPage\(pi)", pageName: "\(page.number)", transformX: pageTransformX, items: items)
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
            "MasterSpreads/MasterSpread_uMasterA.xml": masterSpread(pageW: pageW, pageH: pageH, items: [masterPageNumberItem]),
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

}
