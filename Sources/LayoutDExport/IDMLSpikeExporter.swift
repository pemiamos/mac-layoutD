import Foundation

/// 印前路线「灌版 → IDML → InDesign」的**最小验证 spike**（阶段 E0）。
///
/// 它**不**映射真实 `BookProject`，而是写死一份最小 IDML，用来在 InDesign 中文版里
/// 证伪整条路线唯一的高风险点：CJK 排版（尤其竖排）能否干净落进 InDesign。
///
/// v1 覆盖：一个跨页（facing 2 页）+ 一个横排中文段落样式文本框 + 一个竖排文本框
/// （`StoryOrientation=Vertical`）+ 一张置入图（Link）+ 一个 CMYK Swatch（应用到段落色）。
/// v2 再单独压测「复合字体（合成字体）」落 IDML 的保真——v1 故意不造合成字体元素，
/// 以免一个没把握的结构把整包带崩，先证基础包有效性 + 竖排。
///
/// IDML 是 ZIP 包：`mimetype` 必须是第一个且以 store（不压缩）方式写入，其余部分再追加。
/// 这里借 `/usr/bin/zip` 完成（spike 级实现；正式 IDML 导出会改走原生 zip 写入）。
public struct IDMLSpikeExporter {
    public init() {}

    public enum SpikeError: Error, LocalizedError {
        case zipFailed(String)

        public var errorDescription: String? {
            switch self {
            case .zipFailed(let detail): return "IDML 打包失败：\(detail)"
            }
        }
    }

    // A5：148 × 210 mm，单位 pt（1mm = 72/25.4 pt）。
    private let pageW = 148.0 * 72.0 / 25.4   // 419.527559
    private let pageH = 210.0 * 72.0 / 25.4   // 595.275591

    public func export(to outputURL: URL, imagePath: String?) throws {
        let halfH = pageH / 2.0
        let fm = FileManager.default

        // 1. 临时目录里把包内各部分铺开。
        let work = fm.temporaryDirectory.appendingPathComponent("layoutd-idml-spike-\(ProcessInfo.processInfo.globallyUniqueString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        for sub in ["META-INF", "Resources", "MasterSpreads", "Spreads", "Stories", "XML"] {
            try fm.createDirectory(at: work.appendingPathComponent(sub), withIntermediateDirectories: true)
        }

        let imageURI: String = {
            guard let imagePath, !imagePath.isEmpty else { return "file:image-not-linked.png" }
            let abs = (imagePath as NSString).isAbsolutePath
                ? imagePath
                : fm.currentDirectoryPath + "/" + imagePath
            return "file:" + abs
        }()

        let files: [String: String] = [
            "mimetype": "application/vnd.adobe.indesign-idml-package",
            "designmap.xml": designmap(),
            "META-INF/container.xml": container(),
            "META-INF/metadata.xml": metadata(),
            "Resources/Graphic.xml": graphic(),
            "Resources/Fonts.xml": fonts(),
            "Resources/Styles.xml": styles(),
            "Resources/Preferences.xml": preferences(),
            "XML/Tags.xml": tags(),
            "XML/BackingStory.xml": backingStory(),
            "MasterSpreads/MasterSpread_uMaster1.xml": masterSpread(halfH: halfH),
            "Spreads/Spread_uSpread1.xml": spread(halfH: halfH, imageURI: imageURI),
            "Stories/Story_uStoryH.xml": storyHorizontal(),
            "Stories/Story_uStoryV.xml": storyVertical()
        ]

        for (rel, content) in files {
            let dest = work.appendingPathComponent(rel)
            try content.data(using: .utf8)!.write(to: dest, options: .atomic)
        }

        // mimetype 文件不带换行，content(using:) 已无尾换行，OK。

        // 2. 打包：mimetype 先 store，再追加其余。
        if fm.fileExists(atPath: outputURL.path) {
            try fm.removeItem(at: outputURL)
        }
        try createParent(of: outputURL)

        try runZip(["-X", "-0", outputURL.path, "mimetype"], cwd: work)
        try runZip(
            ["-X", "-r", "-9", outputURL.path,
             "designmap.xml", "META-INF", "Resources", "MasterSpreads", "Spreads", "Stories", "XML"],
            cwd: work
        )

        try? fm.removeItem(at: work)
    }

    // MARK: - 打包辅助

    private func runZip(_ args: [String], cwd: URL) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        proc.arguments = args
        proc.currentDirectoryURL = cwd
        let pipe = Pipe()
        proc.standardError = pipe
        proc.standardOutput = pipe
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw SpikeError.zipFailed("zip \(args.joined(separator: " ")) → \(out)")
        }
    }

    private func createParent(of url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func fmt(_ d: Double) -> String { String(format: "%.3f", d) }

    /// 矩形四角（绝对 spread 坐标）→ IDML PathGeometry（顺时针 TL→TR→BR→BL）。
    private func rectGeometry(left: Double, top: Double, right: Double, bottom: Double) -> String {
        func pt(_ x: Double, _ y: Double) -> String {
            let a = "\(fmt(x)) \(fmt(y))"
            return "<PathPointType Anchor=\"\(a)\" LeftDirection=\"\(a)\" RightDirection=\"\(a)\"/>"
        }
        return """
        <Properties><PathGeometry><GeometryPathType PathOpen="false"><PathPointArray>
        \(pt(left, top))
        \(pt(right, top))
        \(pt(right, bottom))
        \(pt(left, bottom))
        </PathPointArray></GeometryPathType></PathGeometry></Properties>
        """
    }

    // MARK: - 包内各部分

    private let header = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
    private let pkgNS = "xmlns:idPkg=\"http://ns.adobe.com/AdobeInDesign/idml/1.0/packaging\""
    private let dom = "16.0"

    private func designmap() -> String {
        """
        \(header)
        <?aid style="50" type="document" readerVersion="6.0" featureSet="257" product="16.0(202)" ?>
        <Document \(pkgNS) Self="layoutd_spike_doc" DOMVersion="\(dom)" Name="layoutd-idml-spike.indd" StoryList="uStoryH uStoryV">
        \t<idPkg:Graphic src="Resources/Graphic.xml"/>
        \t<idPkg:Fonts src="Resources/Fonts.xml"/>
        \t<idPkg:Styles src="Resources/Styles.xml"/>
        \t<idPkg:Preferences src="Resources/Preferences.xml"/>
        \t<idPkg:Tags src="XML/Tags.xml"/>
        \t<idPkg:MasterSpread src="MasterSpreads/MasterSpread_uMaster1.xml"/>
        \t<idPkg:Spread src="Spreads/Spread_uSpread1.xml"/>
        \t<idPkg:BackingStory src="XML/BackingStory.xml"/>
        \t<idPkg:Story src="Stories/Story_uStoryH.xml"/>
        \t<idPkg:Story src="Stories/Story_uStoryV.xml"/>
        </Document>
        """
    }

    /// spike v2：InDesign 合成字体（复合字体）。按字符类映射不同字体——
    /// 汉字/假名/全角约物记号 → 宋体；半角欧文/数字 → Helvetica。
    /// 合成字体内联在 designmap 的 <Document> 下，按名字「正文复合体」被段落样式引用。
    private func compositeFont() -> String {
        func entry(_ slug: String, _ name: String, _ font: String) -> String {
            """
            \t<CompositeFontEntry Self="CompositeFont/正文复合体/\(slug)" Name="\(name)" FontStyle="Regular" RelativeSize="100" HorizontalScale="100" VerticalScale="100" BaselineShift="0" Locked="false" ScaleOption="false" CustomCharacters="">
            \t\t<Properties><AppliedFont type="string">\(font)</AppliedFont></Properties>
            \t</CompositeFontEntry>
            """
        }
        return """
        \t<CompositeFont Self="CompositeFont/正文复合体" Name="正文复合体">
        \(entry("漢字", "漢字", "Songti SC"))
        \(entry("かな", "かな", "Songti SC"))
        \(entry("全角約物", "全角約物", "Songti SC"))
        \(entry("全角記号", "全角記号", "Songti SC"))
        \(entry("半角欧文", "半角欧文", "Helvetica"))
        \(entry("半角数字", "半角数字", "Helvetica"))
        \t</CompositeFont>
        """
    }

    private func container() -> String {
        """
        \(header)
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
        \t<rootfiles>
        \t\t<rootfile full-path="designmap.xml" media-type="text/xml"/>
        \t</rootfiles>
        </container>
        """
    }

    private func metadata() -> String {
        """
        \(header)
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
        \t<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        \t\t<rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/">
        \t\t\t<dc:format>application/x-indesign</dc:format>
        \t\t</rdf:Description>
        \t</rdf:RDF>
        </x:xmpmeta>
        """
    }

    private func graphic() -> String {
        """
        \(header)
        <idPkg:Graphic \(pkgNS) DOMVersion="\(dom)">
        \t<Color Self="Color/Paper" Model="Process" Space="CMYK" ColorValue="0 0 0 0" ColorOverride="Specialpaper" AlternateSpace="NoAlternateColor" AlternateColorValue="" Name="Paper" ColorEditable="true" ColorRemovable="false" Visible="true" SwatchCreatorID="7937"/>
        \t<Color Self="Color/Black" Model="Process" Space="CMYK" ColorValue="0 0 0 100" ColorOverride="Specialblack" AlternateSpace="NoAlternateColor" AlternateColorValue="" Name="Black" ColorEditable="false" ColorRemovable="false" Visible="true" SwatchCreatorID="7937"/>
        \t<Color Self="Color/Registration" Model="Registration" Space="CMYK" ColorValue="100 100 100 100" ColorOverride="Specialregistration" AlternateSpace="NoAlternateColor" AlternateColorValue="" Name="Registration" ColorEditable="false" ColorRemovable="false" Visible="true" SwatchCreatorID="7937"/>
        \t<Color Self="Color/LayoutD Accent" Model="Process" Space="CMYK" ColorValue="0 80 95 0" ColorOverride="Normal" AlternateSpace="NoAlternateColor" AlternateColorValue="" Name="LayoutD Accent" ColorEditable="true" ColorRemovable="true" Visible="true" SwatchCreatorID="7937"/>
        \t<Swatch Self="Swatch/None" Name="None" ColorEditable="false" ColorRemovable="false" Visible="true" SwatchCreatorID="7937" SwatchColorGroupReference="n"/>
        \t<Ink Self="Ink/$ID/Process Cyan" Name="$ID/Process Cyan" AngleForSeparation="75" ConvertToProcess="false" Frequency="70" IsProcessInk="true" NeutralDensity="0.61" PrintInk="true" TrapOrder="1" InkAlias=""/>
        \t<Ink Self="Ink/$ID/Process Magenta" Name="$ID/Process Magenta" AngleForSeparation="15" ConvertToProcess="false" Frequency="70" IsProcessInk="true" NeutralDensity="0.76" PrintInk="true" TrapOrder="2" InkAlias=""/>
        \t<Ink Self="Ink/$ID/Process Yellow" Name="$ID/Process Yellow" AngleForSeparation="0" ConvertToProcess="false" Frequency="70" IsProcessInk="true" NeutralDensity="0.16" PrintInk="true" TrapOrder="3" InkAlias=""/>
        \t<Ink Self="Ink/$ID/Process Black" Name="$ID/Process Black" AngleForSeparation="45" ConvertToProcess="false" Frequency="70" IsProcessInk="true" NeutralDensity="1.7" PrintInk="true" TrapOrder="4" InkAlias=""/>
        </idPkg:Graphic>
        """
    }

    private func fonts() -> String {
        """
        \(header)
        <idPkg:Fonts \(pkgNS) DOMVersion="\(dom)">
        \t<FontFamily Self="dFontFamily0" Name="Songti SC">
        \t\t<Font Self="dFont0" FontFamily="Songti SC" Name="Songti SC Regular" PostScriptName="STSongti-SC-Regular" Status="Installed" FontStyleName="Regular" FontType="OpenTypeCFF" WritingScript="0" FullName="Songti SC Regular" FullNameNative="宋体-简 常规体" FontStyleNameNative="常规体" PlatformName="" Version="" TypekitID=""/>
        \t</FontFamily>
        \t<FontFamily Self="dFontFamily1" Name="Helvetica">
        \t\t<Font Self="dFont1" FontFamily="Helvetica" Name="Helvetica" PostScriptName="Helvetica" Status="Installed" FontStyleName="Regular" FontType="Type1" WritingScript="0" FullName="Helvetica" FullNameNative="Helvetica" FontStyleNameNative="Regular" PlatformName="" Version="" TypekitID=""/>
        \t</FontFamily>
        \(compositeFont())
        </idPkg:Fonts>
        """
    }

    private func styles() -> String {
        """
        \(header)
        <idPkg:Styles \(pkgNS) DOMVersion="\(dom)">
        \t<RootCharacterStyleGroup Self="u_rcsg">
        \t\t<CharacterStyle Self="CharacterStyle/$ID/[No character style]" Imported="false" Name="$ID/[No character style]"/>
        \t</RootCharacterStyleGroup>
        \t<RootParagraphStyleGroup Self="u_rpsg">
        \t\t<ParagraphStyle Self="ParagraphStyle/$ID/[No paragraph style]" Imported="false" Name="$ID/[No paragraph style]"/>
        \t\t<ParagraphStyle Self="ParagraphStyle/正文" Imported="false" Name="正文" PointSize="10.5" Leading="16" FillColor="Color/LayoutD Accent" Justification="LeftJustified">
        \t\t\t<Properties>
        \t\t\t\t<BasedOn type="object">ParagraphStyle/$ID/[No paragraph style]</BasedOn>
        \t\t\t\t<PreviewColor type="enumeration">Nothing</PreviewColor>
        \t\t\t\t<AppliedFont type="string">Songti SC</AppliedFont>
        \t\t\t</Properties>
        \t\t</ParagraphStyle>
        \t\t<ParagraphStyle Self="ParagraphStyle/正文复合体" Imported="false" Name="正文复合体" PointSize="16" Leading="24" FillColor="Color/Black" Justification="LeftJustified">
        \t\t\t<Properties>
        \t\t\t\t<BasedOn type="object">ParagraphStyle/$ID/[No paragraph style]</BasedOn>
        \t\t\t\t<PreviewColor type="enumeration">Nothing</PreviewColor>
        \t\t\t\t<AppliedFont type="string">正文复合体</AppliedFont>
        \t\t\t</Properties>
        \t\t</ParagraphStyle>
        \t</RootParagraphStyleGroup>
        \t<RootCellStyleGroup Self="u_rcellsg">
        \t\t<CellStyle Self="CellStyle/$ID/[None]" Name="$ID/[None]"/>
        \t</RootCellStyleGroup>
        \t<RootTableStyleGroup Self="u_rtsg">
        \t\t<TableStyle Self="TableStyle/$ID/[No table style]" Name="$ID/[No table style]"/>
        \t</RootTableStyleGroup>
        \t<RootObjectStyleGroup Self="u_rosg">
        \t\t<ObjectStyle Self="ObjectStyle/$ID/[None]" Name="$ID/[None]"/>
        \t</RootObjectStyleGroup>
        </idPkg:Styles>
        """
    }

    private func preferences() -> String {
        """
        \(header)
        <idPkg:Preferences \(pkgNS) DOMVersion="\(dom)">
        \t<DocumentPreference PageHeight="\(fmt(pageH))" PageWidth="\(fmt(pageW))" PagesPerDocument="2" FacingPages="true" PageOrientation="Portrait" ColumnDirection="Horizontal"/>
        \t<ViewPreference HorizontalMeasurementUnits="Points" VerticalMeasurementUnits="Points" RulerOrigin="SpreadOrigin"/>
        </idPkg:Preferences>
        """
    }

    private func tags() -> String {
        """
        \(header)
        <idPkg:Tags \(pkgNS) DOMVersion="\(dom)">
        \t<XMLTag Self="XMLTag/Root" Name="Root">
        \t\t<Properties><TagColor type="enumeration">LightBlue</TagColor></Properties>
        \t</XMLTag>
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

    private func masterSpread(halfH: Double) -> String {
        """
        \(header)
        <idPkg:MasterSpread \(pkgNS) DOMVersion="\(dom)">
        \t<MasterSpread Self="uMaster1" Name="A-Master" NamePrefix="A" BaseName="主页" ShowMasterItems="true" PageCount="2" OverriddenPageItemProps="">
        \t\t<Page Self="uMpage1" Name="A" AppliedMaster="n" MasterPageTransform="1 0 0 1 0 0" GeometricBounds="0 0 \(fmt(pageH)) \(fmt(pageW))" ItemTransform="1 0 0 1 \(fmt(-pageW)) \(fmt(-halfH))"/>
        \t\t<Page Self="uMpage2" Name="A" AppliedMaster="n" MasterPageTransform="1 0 0 1 0 0" GeometricBounds="0 0 \(fmt(pageH)) \(fmt(pageW))" ItemTransform="1 0 0 1 0 \(fmt(-halfH))"/>
        \t</MasterSpread>
        </idPkg:MasterSpread>
        """
    }

    private func spread(halfH: Double, imageURI: String) -> String {
        // 右页 = page2，spread 局部偏移 (0, -halfH)；左页 = page1，偏移 (-pageW, -halfH)。
        // 横排文本框（右页）：页内 x 40..379, y 80..260。
        let h = rectGeometry(left: 40, top: 80 - halfH, right: pageW - 40, bottom: 260 - halfH)
        // 置入图（右页）：页内 x 40..379, y 300..520。
        let imgL = 40.0, imgT = 300 - halfH, imgR = pageW - 40, imgB = 520 - halfH
        let imgRect = rectGeometry(left: imgL, top: imgT, right: imgR, bottom: imgB)
        // 竖排文本框（左页）：页内 x 40..379 → spread x (40-pageW)..(379-pageW)，y 80..400。
        let v = rectGeometry(left: 40 - pageW, top: 80 - halfH, right: (pageW - 40) - pageW, bottom: 400 - halfH)

        // 置入图：图片自然尺寸 2400×1600 px（GraphicBounds 以 72ppi 计 = 2400×1600 pt），
        // 用 ItemTransform 缩放铺进图框；EffectivePpi = 72 / scale。
        let natW = 2400.0, natH = 1600.0
        let frameW = imgR - imgL, frameH = imgB - imgT
        let sx = frameW / natW, sy = frameH / natH
        let effX = Int((72.0 / sx).rounded()), effY = Int((72.0 / sy).rounded())
        let imageBlock = """
        <Image Self="uImg1" Space="$ID/#Links_RGB" ActualPpi="72 72" EffectivePpi="\(effX) \(effY)" ImageRenderingIntent="UseColorSettings" Visible="true" ImageTypeName="$ID/Portable Network Graphics (PNG)" ItemTransform="\(fmt(sx)) 0 0 \(fmt(sy)) \(fmt(imgL)) \(fmt(imgT))">
        \t\t\t\t<Properties>
        \t\t\t\t\t<Profile type="string">$ID/Embedded</Profile>
        \t\t\t\t\t<GraphicBounds Left="0" Top="0" Right="\(fmt(natW))" Bottom="\(fmt(natH))"/>
        \t\t\t\t</Properties>
        \t\t\t\t<Link Self="uLink1" AssetURL="$ID/" AssetID="$ID/" LinkResourceURI="\(esc(imageURI))" LinkResourceFormat="$ID/Portable Network Graphics (PNG)" StoredState="Normal" LinkClientID="257" LinkResourceModificationState="None" LinkObjectModificationState="None" LinkResourceSize="0~0" CanEmbed="true" CanUnembed="true" CanPackage="true" ImportPolicy="NoAutoImport" ShowInUI="true"/>
        \t\t\t</Image>
        """

        // 边距分栏文档（非版面网格）：给每页 MarginPreference，去掉 UseMasterGrid/GridStartingPoint，
        // 关页面重排避免 facing-pages 自动补出的幻影首页。
        let margin = "<MarginPreference ColumnCount=\"1\" ColumnGutter=\"12\" Top=\"50\" Bottom=\"50\" Left=\"50\" Right=\"50\" ColumnDirection=\"Horizontal\" ColumnsPositions=\"0 \(fmt(pageW - 100))\"/>"
        return """
        \(header)
        <idPkg:Spread \(pkgNS) DOMVersion="\(dom)">
        \t<Spread Self="uSpread1" PageCount="2" BindingLocation="0" ShowMasterItems="true" PageTransitionType="None" PageTransitionDirection="NotApplicable" PageTransitionDuration="Medium" AllowPageShuffle="false" ItemTransform="1 0 0 1 0 0" FlattenerOverride="Default">
        \t\t<Page Self="uPage1" Name="1" AppliedMaster="uMaster1" MasterPageTransform="1 0 0 1 0 0" GeometricBounds="0 0 \(fmt(pageH)) \(fmt(pageW))" ItemTransform="1 0 0 1 \(fmt(-pageW)) \(fmt(-halfH))" OverrideList="">
        \t\t\t<Properties>\(margin)</Properties>
        \t\t</Page>
        \t\t<Page Self="uPage2" Name="2" AppliedMaster="uMaster1" MasterPageTransform="1 0 0 1 0 0" GeometricBounds="0 0 \(fmt(pageH)) \(fmt(pageW))" ItemTransform="1 0 0 1 0 \(fmt(-halfH))" OverrideList="">
        \t\t\t<Properties>\(margin)</Properties>
        \t\t</Page>
        \t\t<TextFrame Self="uTFH" ParentStory="uStoryH" PreviousTextFrame="n" NextTextFrame="n" ContentType="TextType" ItemTransform="1 0 0 1 0 0">
        \t\t\t\(h)
        \t\t\t<TextFramePreference TextColumnCount="1" TextColumnGutter="12" VerticalJustification="TopAlign"/>
        \t\t</TextFrame>
        \t\t<TextFrame Self="uTFV" ParentStory="uStoryV" PreviousTextFrame="n" NextTextFrame="n" ContentType="TextType" ItemTransform="1 0 0 1 0 0">
        \t\t\t\(v)
        \t\t\t<TextFramePreference TextColumnCount="1" TextColumnGutter="12" VerticalJustification="TopAlign"/>
        \t\t</TextFrame>
        \t\t<Rectangle Self="uRect1" ContentType="GraphicType" StoryTitle="$ID/" ItemTransform="1 0 0 1 0 0">
        \t\t\t\(imgRect)
        \t\t\t\(imageBlock)
        \t\t</Rectangle>
        \t</Spread>
        </idPkg:Spread>
        """
    }

    private func storyHorizontal() -> String {
        // 用合成字体段落样式：汉字应是宋体(衬线)、abc/123 应是 Helvetica(无衬线)——
        // 字形差异肉眼可辨即证明「按字符类切字体」落进了 InDesign。
        story(
            self: "uStoryH",
            orientation: "Horizontal",
            direction: "LeftToRightDirection",
            style: "ParagraphStyle/正文复合体",
            content: "复合字体测试：汉字abc数字123，标点。汉字Songti，欧文Helvetica。"
        )
    }

    private func storyVertical() -> String {
        story(
            self: "uStoryV",
            orientation: "Vertical",
            direction: "RightToLeftDirection",
            style: "ParagraphStyle/正文",
            content: "这是竖排中文样张，行自右向左推进。诗云：白日依山尽，黄河入海流。"
        )
    }

    private func story(self id: String, orientation: String, direction: String, style: String, content: String) -> String {
        """
        \(header)
        <idPkg:Story \(pkgNS) DOMVersion="\(dom)">
        \t<Story Self="\(id)" AppliedTOCStyle="n" TrackChanges="false" StoryTitle="$ID/" AppliedNamedGrid="n">
        \t\t<StoryPreference OpticalMarginAlignment="false" OpticalMarginSize="12" FrameType="TextFrameType" StoryOrientation="\(orientation)" StoryDirection="\(direction)"/>
        \t\t<ParagraphStyleRange AppliedParagraphStyle="\(style)">
        \t\t\t<CharacterStyleRange AppliedCharacterStyle="CharacterStyle/$ID/[No character style]">
        \t\t\t\t<Content>\(esc(content))</Content>
        \t\t\t</CharacterStyleRange>
        \t\t</ParagraphStyleRange>
        \t</Story>
        </idPkg:Story>
        """
    }
}
