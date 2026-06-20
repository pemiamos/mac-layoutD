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
public struct IDMLExporter {
    public init() {}

    public enum ExportError: Error, LocalizedError {
        case zipFailed(String)
        public var errorDescription: String? {
            switch self {
            case .zipFailed(let d): return "IDML 打包失败：\(d)"
            }
        }
    }

    private let header = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
    private let pkgNS = "xmlns:idPkg=\"http://ns.adobe.com/AdobeInDesign/idml/1.0/packaging\""
    private let dom = "16.0"

    // MARK: - 入口

    public func export(document: LaidOutDocument, project: BookProject, to url: URL) throws {
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

        var ctx = BuildContext(project: project)

        // 先扫一遍：注册颜色、字体、复合字体、段落样式所需资源。
        for style in project.styles.paragraphStyles {
            ctx.registerParagraphStyle(style)
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

        for (pi, page) in pages.enumerated() {
            let spreadSelf = "uSpread\(pi)"
            var items: [String] = []

            for (fi, frame) in page.frames.enumerated() {
                switch frame.content {
                case .text(let raw):
                    // 脚注由锚点 Story 内的原生 <Footnote> 承载。LayoutEngine 仍会
                    // 为 Canvas/PDF/PNG 生成页脚 frame；IDML 不能再把那份 frame 当
                    // 普通正文导出，否则 InDesign 会出现两份脚注内容。
                    guard frame.kind != .footnote else { continue }
                    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    let storySelf = "uStory\(pi)_\(fi)"
                    let style = ctx.resolvedStyle(id: frame.styleId)
                    let styleRef = "ParagraphStyle/\(xmlSafe(style.id))"
                    let vertical = style.layoutDirection == .vertical
                    let component = project.styles.componentStyle(for: frame.kind)
                    let fillColor = frame.backgroundColorHex ?? component?.resolvedFillColorHex(project: project)
                    let strokeColor = frame.strokeColorHex ?? component?.resolvedStrokeColorHex(project: project)
                    let strokeWidth = frame.strokeWidth ?? component?.strokeWidth ?? 0
                    items.append(textFrameItem(self: "uTF\(pi)_\(fi)", story: storySelf,
                                               rect: frame.rect, fillColor: fillColor,
                                               strokeColor: strokeColor, strokeWidth: strokeWidth,
                                               pageW: pageW, pageH: pageH))
                    // Accent 必须位于有底色的文本框之上，否则会被框架填色遮住。
                    if let accentColor = component?.resolvedAccentColorHex(project: project),
                       let accentWidth = component?.accentWidth, accentWidth > 0 {
                        let accentRect = Rect(x: frame.rect.x, y: frame.rect.y,
                                              width: min(accentWidth, frame.rect.width), height: frame.rect.height)
                        items.append(colorRectangleItem(self: "uAccent\(pi)_\(fi)", rect: accentRect,
                                                        fillColor: accentColor, pageW: pageW, pageH: pageH))
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
                                                footnotes: frameFootnotes)
                    storyFiles["Stories/Story_\(storySelf).xml"] = storyContent
                    storyRefs.append("\t<idPkg:Story src=\"Stories/Story_\(storySelf).xml\"/>")
                    storyListIds.append(storySelf)
                case .asset(let id), .spreadAsset(let id, _):
                    guard let asset = project.assets.first(where: { $0.id == id }) else { continue }
                    items.append(imageItem(self: "uRect\(pi)_\(fi)", imageSelf: "uImg\(pi)_\(fi)",
                                           linkSelf: "uLink\(pi)_\(fi)", asset: asset,
                                           packagedFileName: packagedLinks[asset.id]?.fileName,
                                           rect: frame.rect, pageW: pageW, pageH: pageH))
                case .empty:
                    continue
                }
            }

            spreadFiles["Spreads/Spread_\(spreadSelf).xml"] =
                spreadXML(self: spreadSelf, pageSelf: "uPage\(pi)", pageName: "\(page.number)",
                          spreadY: Double(pi) * pageH * 1.235, pageW: pageW, pageH: pageH, items: items)
            spreadRefs.append("\t<idPkg:Spread src=\"Spreads/Spread_\(spreadSelf).xml\"/>")
        }

        // 组装包内所有部件。
        var files: [String: String] = [
            "mimetype": "application/vnd.adobe.indesign-idml-package",
            "META-INF/container.xml": container(),
            "META-INF/metadata.xml": metadata(),
            "Resources/Graphic.xml": graphic(ctx: ctx),
            "Resources/Fonts.xml": fonts(ctx: ctx),
            "Resources/Styles.xml": styles(ctx: ctx),
            "Resources/Preferences.xml": preferences(pageW: pageW, pageH: pageH, pageCount: pages.count),
            "XML/Tags.xml": tags(),
            "XML/BackingStory.xml": backingStory(),
            "MasterSpreads/MasterSpread_uMasterA.xml": masterSpread(pageW: pageW, pageH: pageH),
            "designmap.xml": designmap(spreadRefs: spreadRefs, storyRefs: storyRefs, storyList: storyListIds)
        ]
        files.merge(spreadFiles) { _, b in b }
        files.merge(storyFiles) { _, b in b }

        try writePackage(files: files, to: url)
        try copyPackagedLinks(packagedLinks.values, beside: url)
    }

    private struct PackagedLink {
        let sourceURL: URL
        let fileName: String
    }

    /// 只打包实际置入页面且源文件存在的素材。同一素材重复置入时复用链接；不同素材
    /// basename 冲突时保留扩展名并追加序号（figure.png、figure-2.png）。
    private func packagedLinks(for pages: [LaidOutPage], assets: [Asset]) -> [UUID: PackagedLink] {
        let assetsById = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        var result: [UUID: PackagedLink] = [:]
        var usedNames: Set<String> = []

        for page in pages {
            for frame in page.frames {
                let assetId: UUID
                switch frame.content {
                case .asset(let id), .spreadAsset(let id, _): assetId = id
                case .text, .empty: continue
                }
                guard result[assetId] == nil,
                      let asset = assetsById[assetId],
                      let sourcePath = asset.sourcePath,
                      !sourcePath.isEmpty else { continue }

                let sourceURL = URL(fileURLWithPath: sourcePath, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
                    .standardizedFileURL
                guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }

                let requestedName = URL(fileURLWithPath: asset.fileName).lastPathComponent
                let baseName = requestedName.isEmpty ? sourceURL.lastPathComponent : requestedName
                let uniqueName = uniqueLinkName(baseName, usedNames: &usedNames)
                result[assetId] = PackagedLink(sourceURL: sourceURL, fileName: uniqueName)
            }
        }
        return result
    }

    private func uniqueLinkName(_ fileName: String, usedNames: inout Set<String>) -> String {
        if usedNames.insert(fileName).inserted { return fileName }
        let url = URL(fileURLWithPath: fileName)
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        var sequence = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem)-\(sequence)" : "\(stem)-\(sequence).\(ext)"
            if usedNames.insert(candidate).inserted { return candidate }
            sequence += 1
        }
    }

    private func copyPackagedLinks(_ links: Dictionary<UUID, PackagedLink>.Values, beside outputURL: URL) throws {
        guard !links.isEmpty else { return }
        let fm = FileManager.default
        let linksDirectory = outputURL.deletingLastPathComponent().appendingPathComponent("Links", isDirectory: true)
        try fm.createDirectory(at: linksDirectory, withIntermediateDirectories: true)
        for link in links {
            let destination = linksDirectory.appendingPathComponent(link.fileName)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.copyItem(at: link.sourceURL, to: destination)
        }
    }

    // MARK: - 构建上下文（资源注册表）

    private struct BuildContext {
        let project: BookProject
        var colorOrder: [String] = []          // 规范化 hex
        var colorName: [String: String] = [:]  // hex -> Color Self
        var fontOrder: [String] = []           // 字体家族顺序(InDesign 索引用的家族名)
        var fontStyles: [String: [(style: String, ps: String, full: String, type: String)]] = [:]  // 家族 -> [(样式, PostScript名, 全名, FontType)]
        var appliedFamily: [String: String] = [:]  // layoutD 原始字体名 -> InDesign 家族名
        var appliedStyle: [String: String] = [:]   // layoutD 原始字体名 -> InDesign 样式名
        var compositeFontStyleIds: [String] = []   // 有复合字体、需生成 CompositeFont 的样式 id
        var paragraphStyles: [ParagraphStyle] = []

        init(project: BookProject) {
            self.project = project
            // 预置内建黑色。
            colorOrder = ["000000"]
            colorName = ["000000": "Color/Black"]
        }

        mutating func color(_ hex: String) -> String {
            let norm = Self.normalizeHex(hex)
            if let n = colorName[norm] { return n }
            let n = "Color/C\(norm)"
            colorName[norm] = n
            colorOrder.append(norm)
            return n
        }

        mutating func font(_ name: String) {
            let r = Self.idNames(name)
            appliedFamily[name] = r.family
            appliedStyle[name] = r.style
            if fontStyles[r.family] == nil { fontStyles[r.family] = []; fontOrder.append(r.family) }
            if !(fontStyles[r.family]?.contains { $0.style == r.style } ?? false) {
                fontStyles[r.family]?.append((r.style, r.ps, r.full, r.type))
            }
        }

        /// 用 CoreText 在本机把 layoutD 字体名解析成 InDesign 实际索引用的
        /// (本地化家族名, 本地化样式名, 真实 PostScript 名, 全名)。
        /// InDesign 中文版按本地化家族名(如「苹方-简」)+ PostScript 名匹配已装字体，
        /// 给英文家族名或把家族名当 PS 名都会被判缺失。
        static func idNames(_ raw: String) -> (family: String, style: String, ps: String, full: String, type: String) {
            let (eFam, eSty) = splitFont(raw)
            let attrs: [CFString: Any] = [
                kCTFontFamilyNameAttribute: eFam,
                kCTFontStyleNameAttribute: eSty
            ]
            let desc = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
            let font = CTFontCreateWithFontDescriptor(desc, 12, nil)
            let ps = CTFontCopyPostScriptName(font) as String
            guard !ps.isEmpty else {
                let fb = eSty == "Regular" ? eFam : "\(eFam) \(eSty)"
                return (eFam, eSty, fb, fb, "OpenTypeCFF")
            }
            let locFam = (CTFontCopyName(font, kCTFontFamilyNameKey) as String?) ?? eFam
            let locSty = (CTFontCopyName(font, kCTFontStyleNameKey) as String?) ?? eSty
            let full = (CTFontCopyFullName(font) as String?) ?? "\(locFam) \(locSty)"
            return (locFam, locSty, ps, full, fontType(desc))
        }

        /// CoreText 字体格式 → IDML FontType 字符串。系统 CJK 字体(苹方/宋体等)是
        /// OpenType-PostScript(CID)，InDesign 装的就是 OpenTypeCID 变体；填成 CFF 会
        /// 让 InDesign 匹配到不可用的「(OTF)」CFF 变体而判缺失。
        static func fontType(_ desc: CTFontDescriptor) -> String {
            guard let raw = CTFontDescriptorCopyAttribute(desc, kCTFontFormatAttribute) as? NSNumber else {
                return "OpenTypeCFF"
            }
            switch raw.int32Value {
            case 1: return "OpenTypeCID"   // OpenTypePostScript（CID-keyed CJK 系统字体）
            case 2: return "OpenTypeTT"    // OpenTypeTrueType
            case 3: return "TrueType"
            case 4: return "Type1"         // PostScript Type1
            default: return "OpenTypeCFF"
            }
        }

        /// 「家族名 + 样式名」连写拆成 (家族, 样式)——InDesign 按家族名匹配已装字体，
        /// 样式走 FontStyle。只在末词是已知字重/样式词时才拆，"Neue"/"SC" 等家族词不动。
        static func splitFont(_ name: String) -> (String, String) {
            let styleWords: Set<String> = [
                "Thin", "Ultralight", "UltraLight", "Extralight", "ExtraLight", "Light",
                "Regular", "Normal", "Medium", "Semibold", "SemiBold", "Demibold", "DemiBold",
                "Bold", "Heavy", "Black", "Italic", "Oblique"
            ]
            let parts = name.split(separator: " ").map(String.init)
            if parts.count >= 2, let last = parts.last, styleWords.contains(last) {
                return (parts.dropLast().joined(separator: " "), last)
            }
            return (name, "Regular")
        }

        mutating func registerParagraphStyle(_ style: ParagraphStyle) {
            let resolved = project.styles.paragraphStyle(id: style.id)
            paragraphStyles.append(resolved)
            _ = color(project.resolvedColorHex(resolved.colorToken) ?? "#000000")
            if let cf = resolved.compositeFont, !cf.isEmpty {
                compositeFontStyleIds.append(resolved.id)
                for (_, m) in cf { font(m.fontName) }
                font(resolved.fontName)
            } else {
                font(resolved.fontName)
            }
        }

        func resolvedStyle(id: String?) -> ParagraphStyle {
            project.styles.paragraphStyle(id: id ?? StyleID.body.rawValue)
        }

        static func normalizeHex(_ hex: String) -> String {
            var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if s.hasPrefix("#") { s.removeFirst() }
            if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
            return s.count == 6 ? s : "000000"
        }
    }

    private func xmlSafe(_ s: String) -> String {
        s.replacingOccurrences(of: "/", with: "_")
    }

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func fmt(_ d: Double) -> String { String(format: "%.3f", d) }

    // MARK: - 几何

    /// frame.rect(页内左上原点、y 向下）→ 单页 spread 坐标(原点在页中心）。
    private func rectGeometry(_ rect: Rect, pageW: Double, pageH: Double) -> String {
        let left = rect.x - pageW / 2
        let top = rect.y - pageH / 2
        let right = rect.x + rect.width - pageW / 2
        let bottom = rect.y + rect.height - pageH / 2
        func p(_ x: Double, _ y: Double) -> String {
            let a = "\(fmt(x)) \(fmt(y))"
            return "<PathPointType Anchor=\"\(a)\" LeftDirection=\"\(a)\" RightDirection=\"\(a)\"/>"
        }
        return """
        <Properties><PathGeometry><GeometryPathType PathOpen="false"><PathPointArray>\
        \(p(left, top))\(p(right, top))\(p(right, bottom))\(p(left, bottom))\
        </PathPointArray></GeometryPathType></PathGeometry></Properties>
        """
    }

    // MARK: - 页面项

    private func colorRef(_ hex: String?) -> String {
        guard let hex else { return "Swatch/None" }
        let normalized = BuildContext.normalizeHex(hex)
        return normalized == "000000" ? "Color/Black" : "Color/C\(normalized)"
    }

    private func textFrameItem(self id: String, story: String, rect: Rect,
                               fillColor: String?, strokeColor: String?, strokeWidth: Double,
                               pageW: Double, pageH: Double) -> String {
        """
        \t\t<TextFrame Self="\(id)" ParentStory="\(story)" PreviousTextFrame="n" NextTextFrame="n" ContentType="TextType" FillColor="\(colorRef(fillColor))" StrokeColor="\(colorRef(strokeColor))" StrokeWeight="\(fmt(max(strokeWidth, 0)))" ItemTransform="1 0 0 1 0 0">
        \t\t\t\(rectGeometry(rect, pageW: pageW, pageH: pageH))
        \t\t\t<TextFramePreference TextColumnCount="1" TextColumnGutter="12" VerticalJustification="TopAlign"/>
        \t\t</TextFrame>
        """
    }

    private func colorRectangleItem(self id: String, rect: Rect, fillColor: String,
                                    pageW: Double, pageH: Double) -> String {
        """
        \t\t<Rectangle Self="\(id)" ContentType="Unassigned" FillColor="\(colorRef(fillColor))" StrokeColor="Swatch/None" StrokeWeight="0" ItemTransform="1 0 0 1 0 0">
        \t\t\t\(rectGeometry(rect, pageW: pageW, pageH: pageH))
        \t\t</Rectangle>
        """
    }

    private func imageItem(self id: String, imageSelf: String, linkSelf: String, asset: Asset, packagedFileName: String?, rect: Rect, pageW: Double, pageH: Double) -> String {
        let natW = Double(max(asset.pixelWidth, 1))
        let natH = Double(max(asset.pixelHeight, 1))
        let sx = rect.width / natW, sy = rect.height / natH
        let effX = Int((72.0 / max(sx, 0.0001)).rounded()), effY = Int((72.0 / max(sy, 0.0001)).rounded())
        let left = rect.x - pageW / 2, top = rect.y - pageH / 2
        let uri = packagedFileName.map { "file:Links/\($0)" } ?? "file:missing-\(asset.fileName)"
        return """
        \t\t<Rectangle Self="\(id)" ContentType="GraphicType" StoryTitle="$ID/" ItemTransform="1 0 0 1 0 0">
        \t\t\t\(rectGeometry(rect, pageW: pageW, pageH: pageH))
        \t\t\t<Image Self="\(imageSelf)" Space="$ID/#Links_RGB" ActualPpi="72 72" EffectivePpi="\(effX) \(effY)" ImageRenderingIntent="UseColorSettings" Visible="true" ItemTransform="\(fmt(sx)) 0 0 \(fmt(sy)) \(fmt(left)) \(fmt(top))">
        \t\t\t\t<Properties>
        \t\t\t\t\t<Profile type="string">$ID/Embedded</Profile>
        \t\t\t\t\t<GraphicBounds Left="0" Top="0" Right="\(fmt(natW))" Bottom="\(fmt(natH))"/>
        \t\t\t\t</Properties>
        \t\t\t\t<Link Self="\(linkSelf)" LinkResourceURI="\(esc(uri))" LinkResourceFormat="$ID/" StoredState="Normal" LinkClientID="257" LinkResourceModificationState="None" LinkObjectModificationState="None" LinkResourceSize="0~0" CanEmbed="true" CanUnembed="true" CanPackage="true" ImportPolicy="NoAutoImport" ShowInUI="true"/>
        \t\t\t</Image>
        \t\t</Rectangle>
        """
    }

    // MARK: - 包内部件

    private func designmap(spreadRefs: [String], storyRefs: [String], storyList: [String]) -> String {
        """
        \(header)
        <?aid style="50" type="document" readerVersion="6.0" featureSet="257" product="16.0(202)" ?>
        <Document \(pkgNS) Self="layoutd_doc" DOMVersion="\(dom)" Name="layoutd-export.indd" StoryList="\(storyList.joined(separator: " "))">
        \t<idPkg:Graphic src="Resources/Graphic.xml"/>
        \t<idPkg:Fonts src="Resources/Fonts.xml"/>
        \t<KinsokuTable Self="KinsokuTable/$ID/kSimpChineseKinsokuName" Name="$ID/kSimpChineseKinsokuName"/>
        \t<idPkg:Styles src="Resources/Styles.xml"/>
        \t<idPkg:Preferences src="Resources/Preferences.xml"/>
        \t<idPkg:Tags src="XML/Tags.xml"/>
        \t<idPkg:MasterSpread src="MasterSpreads/MasterSpread_uMasterA.xml"/>
        \(spreadRefs.joined(separator: "\n"))
        \t<idPkg:BackingStory src="XML/BackingStory.xml"/>
        \(storyRefs.joined(separator: "\n"))
        </Document>
        """
    }

    private func container() -> String {
        """
        \(header)
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
        \t<rootfiles><rootfile full-path="designmap.xml" media-type="text/xml"/></rootfiles>
        </container>
        """
    }

    private func metadata() -> String {
        """
        \(header)
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
        \t<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        \t\t<rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:format>application/x-indesign</dc:format></rdf:Description>
        \t</rdf:RDF>
        </x:xmpmeta>
        """
    }

    private func graphic(ctx: BuildContext) -> String {
        var colors = ""
        for hex in ctx.colorOrder where hex != "000000" {
            let r = Int(hex.prefix(2), radix: 16) ?? 0
            let g = Int(hex.dropFirst(2).prefix(2), radix: 16) ?? 0
            let b = Int(hex.dropFirst(4).prefix(2), radix: 16) ?? 0
            colors += "\t<Color Self=\"Color/C\(hex)\" Model=\"Process\" Space=\"RGB\" ColorValue=\"\(r) \(g) \(b)\" ColorOverride=\"Normal\" AlternateSpace=\"NoAlternateColor\" AlternateColorValue=\"\" Name=\"C\(hex)\" ColorEditable=\"true\" ColorRemovable=\"true\" Visible=\"true\" SwatchCreatorID=\"7937\"/>\n"
        }
        return """
        \(header)
        <idPkg:Graphic \(pkgNS) DOMVersion="\(dom)">
        \t<Color Self="Color/Paper" Model="Process" Space="CMYK" ColorValue="0 0 0 0" ColorOverride="Specialpaper" AlternateSpace="NoAlternateColor" AlternateColorValue="" Name="Paper" ColorEditable="true" ColorRemovable="false" Visible="true" SwatchCreatorID="7937"/>
        \t<Color Self="Color/Black" Model="Process" Space="CMYK" ColorValue="0 0 0 100" ColorOverride="Specialblack" AlternateSpace="NoAlternateColor" AlternateColorValue="" Name="Black" ColorEditable="false" ColorRemovable="false" Visible="true" SwatchCreatorID="7937"/>
        \t<Color Self="Color/Registration" Model="Registration" Space="CMYK" ColorValue="100 100 100 100" ColorOverride="Specialregistration" AlternateSpace="NoAlternateColor" AlternateColorValue="" Name="Registration" ColorEditable="false" ColorRemovable="false" Visible="true" SwatchCreatorID="7937"/>
        \(colors)\t<Swatch Self="Swatch/None" Name="None" ColorEditable="false" ColorRemovable="false" Visible="true" SwatchCreatorID="7937" SwatchColorGroupReference="n"/>
        \t<Ink Self="Ink/$ID/Process Cyan" Name="$ID/Process Cyan" AngleForSeparation="75" ConvertToProcess="false" Frequency="70" IsProcessInk="true" NeutralDensity="0.61" PrintInk="true" TrapOrder="1" InkAlias=""/>
        \t<Ink Self="Ink/$ID/Process Magenta" Name="$ID/Process Magenta" AngleForSeparation="15" ConvertToProcess="false" Frequency="70" IsProcessInk="true" NeutralDensity="0.76" PrintInk="true" TrapOrder="2" InkAlias=""/>
        \t<Ink Self="Ink/$ID/Process Yellow" Name="$ID/Process Yellow" AngleForSeparation="0" ConvertToProcess="false" Frequency="70" IsProcessInk="true" NeutralDensity="0.16" PrintInk="true" TrapOrder="3" InkAlias=""/>
        \t<Ink Self="Ink/$ID/Process Black" Name="$ID/Process Black" AngleForSeparation="45" ConvertToProcess="false" Frequency="70" IsProcessInk="true" NeutralDensity="1.7" PrintInk="true" TrapOrder="4" InkAlias=""/>
        </idPkg:Graphic>
        """
    }

    private func fonts(ctx: BuildContext) -> String {
        var families = ""
        for (i, family) in ctx.fontOrder.enumerated() {
            var fontChildren = ""
            let styles = ctx.fontStyles[family] ?? [(style: "Regular", ps: family, full: family, type: "OpenTypeCFF")]
            for (j, entry) in styles.enumerated() {
                fontChildren += "\t\t<Font Self=\"dFont\(i)_\(j)\" FontFamily=\"\(esc(family))\" Name=\"\(esc(entry.full))\" PostScriptName=\"\(esc(entry.ps))\" Status=\"Installed\" FontStyleName=\"\(esc(entry.style))\" FontType=\"\(entry.type)\" WritingScript=\"0\" FullName=\"\(esc(entry.full))\" FullNameNative=\"\(esc(entry.full))\" FontStyleNameNative=\"\(esc(entry.style))\" PlatformName=\"$ID/\" Version=\"\" TypekitID=\"$ID/\"/>\n"
            }
            families += "\t<FontFamily Self=\"dFontFamily\(i)\" Name=\"\(esc(family))\">\n\(fontChildren)\t</FontFamily>\n"
        }
        var composites = ""
        for sid in ctx.compositeFontStyleIds {
            guard let style = ctx.paragraphStyles.first(where: { $0.id == sid }), let cf = style.compositeFont else { continue }
            let cjk = cf[.chinese]?.fontName ?? style.fontName
            let latin = cf[.latin]?.fontName ?? style.fontName
            let digit = cf[.digit]?.fontName ?? latin
            let name = "CF_\(xmlSafe(sid))"
            func entry(_ slug: String, _ ename: String, _ font: String) -> String {
                let family = ctx.appliedFamily[font] ?? BuildContext.splitFont(font).0
                let fstyle = ctx.appliedStyle[font] ?? BuildContext.splitFont(font).1
                return """
                \t<CompositeFontEntry Self="CompositeFont/\(name)/\(slug)" Name="\(ename)" FontStyle="\(esc(fstyle))" RelativeSize="100" HorizontalScale="100" VerticalScale="100" BaselineShift="0" Locked="false" ScaleOption="false" CustomCharacters="">
                \t\t<Properties><AppliedFont type="string">\(esc(family))</AppliedFont></Properties>
                \t</CompositeFontEntry>
                """
            }
            composites += """
            \t<CompositeFont Self="CompositeFont/\(name)" Name="\(name)">
            \(entry("漢字", "漢字", cjk))
            \(entry("かな", "かな", cjk))
            \(entry("全角約物", "全角約物", cjk))
            \(entry("全角記号", "全角記号", cjk))
            \(entry("半角欧文", "半角欧文", latin))
            \(entry("半角数字", "半角数字", digit))
            \t</CompositeFont>\n
            """
        }
        return """
        \(header)
        <idPkg:Fonts \(pkgNS) DOMVersion="\(dom)">
        \(families)\(composites)</idPkg:Fonts>
        """
    }

    private func styles(ctx: BuildContext) -> String {
        var paras = ""
        for style in ctx.paragraphStyles {
            let colorHex = ctx.project.resolvedColorHex(style.colorToken) ?? "#000000"
            let norm = BuildContext.normalizeHex(colorHex)
            let fill = norm == "000000" ? "Color/Black" : "Color/C\(norm)"
            let isComposite = style.compositeFont?.isEmpty == false
            let famFallback = ctx.appliedFamily[style.fontName] ?? BuildContext.splitFont(style.fontName).0
            let styleFallback = ctx.appliedStyle[style.fontName] ?? BuildContext.splitFont(style.fontName).1
            let applied = isComposite ? "CF_\(xmlSafe(style.id))" : famFallback
            let fontStyleAttr = isComposite ? "" : " FontStyle=\"\(esc(styleFallback))\""
            paras += """
            \t\t<ParagraphStyle Self="ParagraphStyle/\(xmlSafe(style.id))" Imported="false" Name="\(esc(style.displayName))" PointSize="\(fmt(style.fontSize))" Leading="\(fmt(style.lineHeight))" FirstLineIndent="\(fmt(style.firstLineIndent))" SpaceBefore="\(fmt(style.spaceBefore))" SpaceAfter="\(fmt(style.spaceAfter))" FillColor="\(fill)"\(fontStyleAttr) Justification="LeftJustified" KinsokuType="KinsokuPushInFirst" KinsokuHangType="None">
            \t\t\t<Properties>
            \t\t\t\t<BasedOn type="object">ParagraphStyle/$ID/[No paragraph style]</BasedOn>
            \t\t\t\t<PreviewColor type="enumeration">Nothing</PreviewColor>
            \t\t\t\t<AppliedFont type="string">\(esc(applied))</AppliedFont>
            \t\t\t\t<KinsokuSet type="enumeration">SimplifiedChineseKinsoku</KinsokuSet>
            \t\t\t</Properties>
            \t\t</ParagraphStyle>\n
            """
        }
        return """
        \(header)
        <idPkg:Styles \(pkgNS) DOMVersion="\(dom)">
        \t<RootCharacterStyleGroup Self="u_rcsg">
        \t\t<CharacterStyle Self="CharacterStyle/$ID/[No character style]" Imported="false" Name="$ID/[No character style]"/>
        \t</RootCharacterStyleGroup>
        \t<RootParagraphStyleGroup Self="u_rpsg">
        \t\t<ParagraphStyle Self="ParagraphStyle/$ID/[No paragraph style]" Imported="false" Name="$ID/[No paragraph style]"/>
        \(paras)\t</RootParagraphStyleGroup>
        \t<RootCellStyleGroup Self="u_rcellsg"><CellStyle Self="CellStyle/$ID/[None]" Name="$ID/[None]"/></RootCellStyleGroup>
        \t<RootTableStyleGroup Self="u_rtsg"><TableStyle Self="TableStyle/$ID/[No table style]" Name="$ID/[No table style]"/></RootTableStyleGroup>
        \t<RootObjectStyleGroup Self="u_rosg"><ObjectStyle Self="ObjectStyle/$ID/[None]" Name="$ID/[None]"/></RootObjectStyleGroup>
        </idPkg:Styles>
        """
    }

    private func preferences(pageW: Double, pageH: Double, pageCount: Int) -> String {
        // 逐字段对齐 InDesign 自身导出的「非对开」IDML。关键:PagesPerDocument 是
        // “新建文档默认页数”偏好(InDesign 恒写 1),不是实际页数——填成实际页数会让
        // InDesign 误判、插空白页。实际页数由 spread 数量决定。
        """
        \(header)
        <idPkg:Preferences \(pkgNS) DOMVersion="\(dom)">
        \t<DocumentPreference PageHeight="\(fmt(pageH))" PageWidth="\(fmt(pageW))" PagesPerDocument="1" FacingPages="false" DocumentBleedTopOffset="0" DocumentBleedBottomOffset="0" DocumentBleedInsideOrLeftOffset="0" DocumentBleedOutsideOrRightOffset="0" DocumentBleedUniformSize="true" SlugTopOffset="0" SlugBottomOffset="0" SlugInsideOrLeftOffset="0" SlugRightOrOutsideOffset="0" DocumentSlugUniformSize="false" PreserveLayoutWhenShuffling="true" AllowPageShuffle="true" OverprintBlack="true" PageBinding="LeftToRight" ColumnDirection="Horizontal" SpreadHiddenVisibility="false" Intent="PrintIntent" CreatePrimaryTextFrame="false" ColumnGuideLocked="true" MasterTextFrame="false" SnippetImportUsesOriginalLocation="false"/>
        \t<ViewPreference HorizontalMeasurementUnits="Points" VerticalMeasurementUnits="Points" RulerOrigin="PageOrigin"/>
        </idPkg:Preferences>
        """
    }

    private func tags() -> String {
        """
        \(header)
        <idPkg:Tags \(pkgNS) DOMVersion="\(dom)">
        \t<XMLTag Self="XMLTag/Root" Name="Root"><Properties><TagColor type="enumeration">LightBlue</TagColor></Properties></XMLTag>
        </idPkg:Tags>
        """
    }

    private func backingStory() -> String {
        """
        \(header)
        <idPkg:BackingStory \(pkgNS) DOMVersion="\(dom)">
        \t<XmlStory Self="u_backing" AppliedTOCStyle="n" TrackChanges="false" StoryTitle="$ID/" AppliedNamedGrid="n">
        \t\t<StoryPreference OpticalMarginAlignment="false" OpticalMarginSize="12" FrameType="TextFrameType" StoryOrientation="Horizontal" StoryDirection="LeftToRightDirection"/>
        \t</XmlStory>
        </idPkg:BackingStory>
        """
    }

    private func masterSpread(pageW: Double, pageH: Double) -> String {
        """
        \(header)
        <idPkg:MasterSpread \(pkgNS) DOMVersion="\(dom)">
        \t<MasterSpread Self="uMasterA" Name="A-Master" NamePrefix="A" BaseName="主页" ShowMasterItems="true" PageCount="1" OverriddenPageItemProps="">
        \t\t<Page Self="uMasterApage" Name="A" AppliedMaster="n" MasterPageTransform="1 0 0 1 0 0" GeometricBounds="0 0 \(fmt(pageH)) \(fmt(pageW))" ItemTransform="1 0 0 1 \(fmt(-pageW/2)) \(fmt(-pageH/2))"/>
        \t</MasterSpread>
        </idPkg:MasterSpread>
        """
    }

    private func spreadXML(self id: String, pageSelf: String, pageName: String, spreadY: Double, pageW: Double, pageH: Double, items: [String]) -> String {
        // 每个 spread 在粘贴板上纵向错开(spreadY)，对齐 InDesign 自身做法；
        // 全部叠在原点会让 InDesign 重新分页、插空白页。
        """
        \(header)
        <idPkg:Spread \(pkgNS) DOMVersion="\(dom)">
        \t<Spread Self="\(id)" PageTransitionType="None" PageTransitionDirection="NotApplicable" PageTransitionDuration="Medium" ShowMasterItems="true" PageCount="1" BindingLocation="0" SpreadHidden="false" AllowPageShuffle="true" ItemTransform="1 0 0 1 0 \(fmt(spreadY))" FlattenerOverride="Default">
        \t\t<Page Self="\(pageSelf)" Name="\(pageName)" AppliedMaster="uMasterA" MasterPageTransform="1 0 0 1 0 0" GeometricBounds="0 0 \(fmt(pageH)) \(fmt(pageW))" ItemTransform="1 0 0 1 \(fmt(-pageW/2)) \(fmt(-pageH/2))" LayoutRule="UseMaster" OverrideList=""/>
        \(items.joined(separator: "\n"))
        \t</Spread>
        </idPkg:Spread>
        """
    }

    private func inlineRuns(for frameText: String, from paragraph: Paragraph) -> [InlineRun]? {
        guard let paragraphRuns = paragraph.inlineRuns, !paragraphRuns.isEmpty else { return nil }
        let sourceCharacters = Array(paragraph.text)
        let frameCharacters = Array(frameText)
        let sourceVisible = sourceCharacters.enumerated().filter { !$0.element.isWhitespace }
        let frameVisible = frameCharacters.enumerated().filter { !$0.element.isWhitespace }
        guard !frameVisible.isEmpty, frameVisible.count <= sourceVisible.count else { return nil }

        let matchingStart = (0...(sourceVisible.count - frameVisible.count)).first { candidate in
            zip(sourceVisible[candidate...], frameVisible).allSatisfy { pair in
                pair.0.element == pair.1.element
            }
        }
        guard let matchingStart else { return nil }

        var emphasisByFrameCharacter = Array(repeating: Set<InlineEmphasis>(), count: frameCharacters.count)
        for (visibleOffset, frameCharacter) in frameVisible.enumerated() {
            let sourceOffset = sourceVisible[matchingStart + visibleOffset].offset
            for run in paragraphRuns where run.location <= sourceOffset && sourceOffset < run.location + run.length {
                emphasisByFrameCharacter[frameCharacter.offset].formUnion(run.emphasis)
            }
        }

        var runs: [InlineRun] = []
        var start: Int?
        var active = Set<InlineEmphasis>()
        for offset in 0...emphasisByFrameCharacter.count {
            let emphasis = offset < emphasisByFrameCharacter.count ? emphasisByFrameCharacter[offset] : []
            if emphasis != active {
                if let start, !active.isEmpty {
                    runs.append(InlineRun(location: start, length: offset - start, emphasis: active))
                }
                start = emphasis.isEmpty ? nil : offset
                active = emphasis
            }
        }
        return runs.isEmpty ? nil : runs
    }

    private func storyXML(
        self id: String,
        styleRef: String,
        vertical: Bool,
        text: String,
        inlineRuns: [InlineRun]? = nil,
        footnotes: [Paragraph] = []
    ) -> String {
        let orientation = vertical ? "Vertical" : "Horizontal"
        let direction = vertical ? "RightToLeftDirection" : "LeftToRightDirection"
        // 每个非空行作为一个段落（ParagraphStyleRange）。
        var lineStart = 0
        let paragraphs = text.components(separatedBy: "\n").compactMap { rawLine -> (String, Int)? in
            defer { lineStart += rawLine.count + 1 }
            let leading = rawLine.prefix { $0.isWhitespace }.count
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            return line.isEmpty ? nil : (line, lineStart + leading)
        }
        let effectiveParagraphs = paragraphs.isEmpty ? [(text, 0)] : paragraphs
        let body = effectiveParagraphs.map { line, start in
            """
            \t\t<ParagraphStyleRange AppliedParagraphStyle="\(styleRef)">
            \(characterStyleRanges(for: line, globalStart: start, inlineRuns: inlineRuns ?? [], footnotes: footnotes))
            \t\t</ParagraphStyleRange>
            """
        }.joined(separator: "\n")
        return """
        \(header)
        <idPkg:Story \(pkgNS) DOMVersion="\(dom)">
        \t<Story Self="\(id)" AppliedTOCStyle="n" TrackChanges="false" StoryTitle="$ID/" AppliedNamedGrid="n">
        \t\t<StoryPreference OpticalMarginAlignment="false" OpticalMarginSize="12" FrameType="TextFrameType" StoryOrientation="\(orientation)" StoryDirection="\(direction)"/>
        \(body)
        \t</Story>
        </idPkg:Story>
        """
    }

    private func characterStyleRanges(
        for text: String,
        globalStart: Int,
        inlineRuns: [InlineRun],
        footnotes: [Paragraph] = []
    ) -> String {
        guard !footnotes.isEmpty else {
            return styledCharacterRanges(for: text, globalStart: globalStart, inlineRuns: inlineRuns)
        }

        // Markdown importer 已把 [^id] 替换为对应的 Unicode 上标，并以出现顺序保存
        // anchoredFootnoteIds。将该上标替换成 Footnote，交由 InDesign 的 FootnoteOption
        // 自动绘制编号；未命中的文本仍走既有行内样式导出。
        let characters = Array(text)
        var cursor = 0
        var output = ""
        for footnote in footnotes {
            guard let marker = footnoteMarker(for: footnote), !marker.isEmpty,
                  let markerStart = firstMatch(of: Array(marker), in: characters, from: cursor) else {
                continue
            }
            if markerStart > cursor {
                output += styledCharacterRanges(
                    for: String(characters[cursor..<markerStart]),
                    globalStart: globalStart + cursor,
                    inlineRuns: inlineRuns
                )
            }
            output += footnoteXML(footnote)
            cursor = markerStart + marker.count
        }
        if cursor < characters.count {
            output += styledCharacterRanges(
                for: String(characters[cursor...]),
                globalStart: globalStart + cursor,
                inlineRuns: inlineRuns
            )
        }
        return output
    }

    private func styledCharacterRanges(for text: String, globalStart: Int, inlineRuns: [InlineRun]) -> String {
        let characters = Array(text)
        guard !characters.isEmpty else { return "" }
        var styles = Array(repeating: Set<InlineEmphasis>(), count: characters.count)
        for run in inlineRuns {
            let start = max(0, run.location - globalStart)
            let end = min(characters.count, run.location + run.length - globalStart)
            guard start < end else { continue }
            for index in start..<end { styles[index].formUnion(run.emphasis) }
        }

        var ranges: [(String, Set<InlineEmphasis>)] = []
        var start = 0
        for index in 1...characters.count where index == characters.count || styles[index] != styles[start] {
            ranges.append((String(characters[start..<index]), styles[start]))
            start = index
        }
        return ranges.map { content, emphasis in
            // 粗体用 FauxBold（算法加粗），斜体用 Skew（切变倾斜角）而非 FontStyle 字符串：
            // FontStyle="Bold"/"Italic" 要求 Fonts.xml 里真有同名字重/斜体的字体资源，否则
            // InDesign 找不到，会用替代字形顶上（视觉上是粉色高亮，等于没生效）。
            // 中文宋体等常既没有 Bold 也没有 Italic 变体。
            // 注意：FauxItalic="true" 实测在 InDesign 里对 CJK 不出可见倾斜，必须用 Skew
            //（伪斜体/切变，单位度）才稳定可见；12° 是 InDesign 伪斜体常用值。
            var attrs = ""
            if emphasis.contains(.bold) { attrs += " FauxBold=\"true\"" }
            if emphasis.contains(.italic) { attrs += " Skew=\"12\"" }
            if emphasis.contains(.kenten) {
                attrs += " KentenKind=\"KentenSesameDot\""
                attrs += " KentenAlignment=\"AlignKentenCenter\""
                attrs += " KentenPosition=\"AboveRight\""
            }
            return "\t\t\t<CharacterStyleRange AppliedCharacterStyle=\"CharacterStyle/$ID/[No character style]\"\(attrs)><Content>\(esc(content))</Content></CharacterStyleRange>"
        }.joined(separator: "\n")
    }

    private func footnoteXML(_ paragraph: Paragraph) -> String {
        let body = styledCharacterRanges(
            for: paragraph.text,
            globalStart: 0,
            inlineRuns: paragraph.inlineRuns ?? []
        )
        return """
        \t\t\t<Footnote>
        \t\t\t\t<ParagraphStyleRange AppliedParagraphStyle="ParagraphStyle/$ID/[No paragraph style]">
        \(body)
        \t\t\t\t</ParagraphStyleRange>
        \t\t\t</Footnote>
        """
    }

    private func footnoteMarker(for paragraph: Paragraph) -> String? {
        guard case .footnote(let number) = paragraph.kind else { return nil }
        let digits: [Character: Character] = [
            "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
            "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"
        ]
        return String(number).compactMap { digits[$0] }.map(String.init).joined()
    }

    private func firstMatch(of needle: [Character], in haystack: [Character], from start: Int) -> Int? {
        guard !needle.isEmpty, start <= haystack.count - needle.count else { return nil }
        for index in start...(haystack.count - needle.count) where Array(haystack[index..<(index + needle.count)]) == needle {
            return index
        }
        return nil
    }

    // MARK: - 打包（纯 Swift ZIP32；mimetype store-first）

    private func writePackage(files: [String: String], to outputURL: URL) throws {
        let orderedPaths = ["mimetype"] + files.keys.filter { $0 != "mimetype" }.sorted()
        let entries = orderedPaths.compactMap { path -> ZIPArchiveWriter.Entry? in
            guard let content = files[path] else { return nil }
            return ZIPArchiveWriter.Entry(path: path, data: Data(content.utf8))
        }
        try ZIPArchiveWriter.write(entries: entries, to: outputURL)
    }
}
