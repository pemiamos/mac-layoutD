import CoreText
import Foundation
import LayoutDCore

extension IDMLExporter {
    // MARK: - 包内部件

    func designmap(spreadRefs: [String], storyRefs: [String], storyList: [String]) -> String {
        """
        \(header)
        <?aid style="50" type="document" readerVersion="6.0" featureSet="257" product="16.0(202)" ?>
        <Document \(pkgNS) Self="layoutd_doc" DOMVersion="\(dom)" Name="layoutd-export.indd" StoryList="\(storyList.joined(separator: " "))">
        \t<idPkg:Graphic src="Resources/Graphic.xml"/>
        \t<idPkg:Fonts src="Resources/Fonts.xml"/>
        \t<KinsokuTable Self="\(kinsokuTableSelf)" Name="$ID/kSimpChineseKinsokuName"/>
        \t<MojikumiTable Self="\(mojikumiTableSelf)" Name="$ID/kSimpChineseMojikumiName"/>
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

    func container() -> String {
        """
        \(header)
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
        \t<rootfiles><rootfile full-path="designmap.xml" media-type="text/xml"/></rootfiles>
        </container>
        """
    }

    func metadata() -> String {
        """
        \(header)
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
        \t<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        \t\t<rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:format>application/x-indesign</dc:format></rdf:Description>
        \t</rdf:RDF>
        </x:xmpmeta>
        """
    }

    func graphic(ctx: BuildContext) -> String {
        var colors = ""
        for key in ctx.colorOrder where key != "000000" {
            guard let color = PrintColor(string: key) else { continue }
            // Under a CMYK output intent, emit this swatch as Process CMYK
            // (Space/Value/Name) while keeping its Self keyed on the stored color,
            // so every FillColor/StrokeColor reference still resolves.
            let emitted = ctx.cmykOutput ? color.asCMYK : color
            let (space, value) = emitted.idmlSpaceValue
            colors += "\t<Color Self=\"\(color.idmlSwatchSelf)\" Model=\"Process\" Space=\"\(space)\" ColorValue=\"\(value)\" ColorOverride=\"Normal\" AlternateSpace=\"NoAlternateColor\" AlternateColorValue=\"\" Name=\"\(esc(emitted.idmlSwatchName))\" ColorEditable=\"true\" ColorRemovable=\"true\" Visible=\"true\" SwatchCreatorID=\"7937\"/>\n"
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

    func fonts(ctx: BuildContext) -> String {
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

    func tocParagraphStyle(base: ParagraphStyle, id: String, name: String, indent: Double = 0) -> ParagraphStyle {
        var style = base
        style.id = id
        style.displayName = name
        style.firstLineIndent = indent
        style.spaceBefore = 0
        style.spaceAfter = 2
        return style
    }

    func styles(ctx: BuildContext, includesTOC: Bool) -> String {
        var paras = ""
        for style in ctx.paragraphStyles {
            let colorHex = ctx.textColorHex(ctx.project.resolvedColorHex(style.colorToken))
            let fill = PrintColor(string: colorHex)?.idmlSwatchSelf ?? "Color/Black"
            let isComposite = style.compositeFont?.isEmpty == false
            let famFallback = ctx.appliedFamily[style.fontName] ?? BuildContext.splitFont(style.fontName).0
            let styleFallback = ctx.appliedStyle[style.fontName] ?? BuildContext.splitFont(style.fontName).1
            let applied = isComposite ? "CF_\(xmlSafe(style.id))" : famFallback
            let fontStyleAttr = isComposite ? "" : " FontStyle=\"\(esc(styleFallback))\""
            paras += """
            \t\t<ParagraphStyle Self="ParagraphStyle/\(xmlSafe(style.id))" Imported="false" Name="\(esc(style.displayName))" PointSize="\(fmt(style.fontSize))" Leading="\(fmt(style.lineHeight))" FirstLineIndent="\(fmt(style.firstLineIndent))" SpaceBefore="\(fmt(style.spaceBefore))" SpaceAfter="\(fmt(style.spaceAfter))" FillColor="\(fill)"\(fontStyleAttr) Composer="\(composer)" Justification="LeftAlign" KinsokuType="KinsokuPushInFirst" KinsokuHangType="None" GridAlignment="None" Mojikumi="\(mojikumiTableSelf)">
            \t\t\t<Properties>
            \t\t\t\t<BasedOn type="object">ParagraphStyle/$ID/[No paragraph style]</BasedOn>
            \t\t\t\t<PreviewColor type="enumeration">Nothing</PreviewColor>
            \t\t\t\t<AppliedFont type="string">\(esc(applied))</AppliedFont>
            \t\t\t\t<KinsokuSet type="enumeration">SimplifiedChineseKinsoku</KinsokuSet>
            \t\t\t\t<MojikumiSet type="object">\(mojikumiTableSelf)</MojikumiSet>
            \t\t\t</Properties>
            \t\t</ParagraphStyle>\n
            """
        }
        let tocStyle = includesTOC ? """
        \t\t<TOCStyle Self="TOCStyle/layoutD_TOC" Name="目录" IncludeBookDocuments="false" CreateBookmarks="true" ReplaceExisting="true">
        \t\t\t<TOCStyleEntry Self="TOCStyleEntry/layoutD_TOC_heading1" AppliedParagraphStyle="ParagraphStyle/heading1" TOCEntryStyle="ParagraphStyle/tocLevel1" IncludePageNumber="true" PageNumberPosition="AfterEntry"/>
        \t\t\t<TOCStyleEntry Self="TOCStyleEntry/layoutD_TOC_heading2" AppliedParagraphStyle="ParagraphStyle/heading2" TOCEntryStyle="ParagraphStyle/tocLevel2" IncludePageNumber="true" PageNumberPosition="AfterEntry"/>
        \t\t</TOCStyle>
        """ : ""
        return """
        \(header)
        <idPkg:Styles \(pkgNS) DOMVersion="\(dom)">
        \t<RootCharacterStyleGroup Self="u_rcsg">
        \t\t<CharacterStyle Self="CharacterStyle/$ID/[No character style]" Imported="false" Name="$ID/[No character style]"/>
        \t</RootCharacterStyleGroup>
        \t<RootParagraphStyleGroup Self="u_rpsg">
        \t\t<ParagraphStyle Self="ParagraphStyle/$ID/[No paragraph style]" Imported="false" Name="$ID/[No paragraph style]" Composer="\(composer)"/>
        \(paras)\t</RootParagraphStyleGroup>
        \(tocStyle)
        \t<RootCellStyleGroup Self="u_rcellsg"><CellStyle Self="CellStyle/$ID/[None]" Name="$ID/[None]"/></RootCellStyleGroup>
        \t<RootTableStyleGroup Self="u_rtsg"><TableStyle Self="TableStyle/$ID/[No table style]" Name="$ID/[No table style]"/></RootTableStyleGroup>
        \t<RootObjectStyleGroup Self="u_rosg"><ObjectStyle Self="ObjectStyle/$ID/[None]" Name="$ID/[None]"/></RootObjectStyleGroup>
        </idPkg:Styles>
        """
    }

    func preferences(pageW: Double, pageH: Double, pageCount: Int, facing: Bool) -> String {
        // 逐字段对齐 InDesign 自身导出的「非对开」IDML。关键:PagesPerDocument 是
        // “新建文档默认页数”偏好(InDesign 恒写 1),不是实际页数——填成实际页数会让
        // InDesign 误判、插空白页。实际页数由 spread 数量决定。
        // FacingPages 随导出选项切换：对开时 true（页框已按 verso 左/recto 右放好）。
        """
        \(header)
        <idPkg:Preferences \(pkgNS) DOMVersion="\(dom)">
        \t<DocumentPreference PageHeight="\(fmt(pageH))" PageWidth="\(fmt(pageW))" PagesPerDocument="1" FacingPages="\(facing)" DocumentBleedTopOffset="0" DocumentBleedBottomOffset="0" DocumentBleedInsideOrLeftOffset="0" DocumentBleedOutsideOrRightOffset="0" DocumentBleedUniformSize="true" SlugTopOffset="0" SlugBottomOffset="0" SlugInsideOrLeftOffset="0" SlugRightOrOutsideOffset="0" DocumentSlugUniformSize="false" PreserveLayoutWhenShuffling="true" AllowPageShuffle="true" OverprintBlack="true" PageBinding="LeftToRight" ColumnDirection="Horizontal" SpreadHiddenVisibility="false" Intent="PrintIntent" CreatePrimaryTextFrame="false" ColumnGuideLocked="true" MasterTextFrame="false" SnippetImportUsesOriginalLocation="false"/>
        \t<ViewPreference HorizontalMeasurementUnits="Points" VerticalMeasurementUnits="Points" RulerOrigin="PageOrigin"/>
        \t<TextDefault Composer="\(composer)" AppliedLanguage="$ID/Chinese: Simplified" KinsokuType="KinsokuPushInFirst" GridAlignment="None" Mojikumi="\(mojikumiTableSelf)"/>
        </idPkg:Preferences>
        """
    }

    func tags() -> String {
        """
        \(header)
        <idPkg:Tags \(pkgNS) DOMVersion="\(dom)">
        \t<XMLTag Self="XMLTag/Root" Name="Root"><Properties><TagColor type="enumeration">LightBlue</TagColor></Properties></XMLTag>
        </idPkg:Tags>
        """
    }

    func backingStory() -> String {
        """
        \(header)
        <idPkg:BackingStory \(pkgNS) DOMVersion="\(dom)">
        \t<XmlStory Self="u_backing" AppliedTOCStyle="n" TrackChanges="false" StoryTitle="$ID/" AppliedNamedGrid="n">
        \t\t<StoryPreference OpticalMarginAlignment="false" OpticalMarginSize="12" FrameType="TextFrameType" StoryOrientation="Horizontal" StoryDirection="LeftToRightDirection"/>
        \t</XmlStory>
        </idPkg:BackingStory>
        """
    }

    func masterSpread(pageW: Double, pageH: Double, items: [String] = []) -> String {
        let allItems = items.joined(separator: "\n")
        return """
        \(header)
        <idPkg:MasterSpread \(pkgNS) DOMVersion="\(dom)">
        \t<MasterSpread Self="uMasterA" Name="A-Master" NamePrefix="A" BaseName="主页" ShowMasterItems="true" PageCount="1" OverriddenPageItemProps="">
        \t\t<Page Self="uMasterApage" Name="A" AppliedMaster="n" MasterPageTransform="1 0 0 1 0 0" GeometricBounds="0 0 \(fmt(pageH)) \(fmt(pageW))" ItemTransform="1 0 0 1 \(fmt(-pageW/2)) \(fmt(-pageH/2))"/>
        \(allItems)
        \t</MasterSpread>
        </idPkg:MasterSpread>
        """
    }

    /// MASTER-1：自动页码挂在主页上，正文页应用主页即可自动出正确页码、无需逐页画。
    /// `<?ACE 18?>` 是 InDesign 「当前页码」特殊字符在 IDML 里的字面写法（作为
    /// Content 内的一个处理指令节点，不是普通文本），来自 Adobe 官方约定
    /// （NextPageNumber/PreviousPageNumber 变体靠 PageNumberType 属性区分，省略即当前页码）。
    func masterPageNumberStoryXML(self id: String) -> String {
        """
        \(header)
        <idPkg:Story \(pkgNS) DOMVersion="\(dom)">
        \t<Story Self="\(id)" AppliedTOCStyle="n" TrackChanges="false" StoryTitle="$ID/" AppliedNamedGrid="n">
        \t\t<StoryPreference OpticalMarginAlignment="false" OpticalMarginSize="12" FrameType="TextFrameType" StoryOrientation="Horizontal" StoryDirection="LeftToRightDirection"/>
        \t\t<ParagraphStyleRange AppliedParagraphStyle="ParagraphStyle/\(xmlSafe(StyleID.caption.rawValue))" Justification="CenterAlign">
        \t\t\t<CharacterStyleRange AppliedCharacterStyle="CharacterStyle/$ID/[No character style]"><Content><?ACE 18?></Content></CharacterStyleRange>
        \t\t</ParagraphStyleRange>
        \t</Story>
        </idPkg:Story>
        """
    }

    func spreadXML(self id: String, spreadY: Double, pageW: Double, pageH: Double,
                           pages: [(pageSelf: String, pageName: String, transformX: Double, items: [String])]) -> String {
        // 每个 spread 在粘贴板上纵向错开(spreadY)，对齐 InDesign 自身做法；
        // 全部叠在原点会让 InDesign 重新分页、插空白页。
        // 非对开：1 页/spread，transformX=0（页框居中于书脊原点，与历史一致）。
        // 对开：2 页/spread（verso transformX=-pageW 左、recto transformX=0 右），BindingLocation=1。
        let pageElements = pages.map { p in
            "\t\t<Page Self=\"\(p.pageSelf)\" Name=\"\(p.pageName)\" AppliedMaster=\"uMasterA\" MasterPageTransform=\"1 0 0 1 0 0\" GeometricBounds=\"0 0 \(fmt(pageH)) \(fmt(pageW))\" ItemTransform=\"1 0 0 1 \(fmt(p.transformX)) \(fmt(-pageH / 2))\" LayoutRule=\"UseMaster\" OverrideList=\"\"/>"
        }.joined(separator: "\n")
        let allItems = pages.flatMap(\.items).joined(separator: "\n")
        let bindingLocation = pages.count > 1 ? 1 : 0
        return """
        \(header)
        <idPkg:Spread \(pkgNS) DOMVersion="\(dom)">
        \t<Spread Self="\(id)" PageTransitionType="None" PageTransitionDirection="NotApplicable" PageTransitionDuration="Medium" ShowMasterItems="true" PageCount="\(pages.count)" BindingLocation="\(bindingLocation)" SpreadHidden="false" AllowPageShuffle="true" ItemTransform="1 0 0 1 0 \(fmt(spreadY))" FlattenerOverride="Default">
        \(pageElements)
        \(allItems)
        \t</Spread>
        </idPkg:Spread>
        """
    }

    // MARK: - 打包（纯 Swift ZIP32；mimetype store-first）

    func writePackage(files: [String: String], to outputURL: URL) throws {
        let orderedPaths = ["mimetype"] + files.keys.filter { $0 != "mimetype" }.sorted()
        let entries = orderedPaths.compactMap { path -> ZIPArchiveWriter.Entry? in
            guard let content = files[path] else { return nil }
            return ZIPArchiveWriter.Entry(path: path, data: Data(content.utf8))
        }
        try ZIPArchiveWriter.write(entries: entries, to: outputURL)
    }
}
