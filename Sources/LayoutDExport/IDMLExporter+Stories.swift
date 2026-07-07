import CoreText
import Foundation
import LayoutDCore

extension IDMLExporter {
    func inlineRuns(for frameText: String, from paragraph: Paragraph) -> [InlineRun]? {
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

    func storyXML(
        self id: String,
        styleRef: String,
        vertical: Bool,
        text: String,
        inlineRuns: [InlineRun]? = nil,
        footnotes: [Paragraph] = [],
        footnoteStyleRef: String = "ParagraphStyle/$ID/[No paragraph style]"
    ) -> String {
        let orientation = vertical ? "Vertical" : "Horizontal"
        let direction = vertical ? "RightToLeftDirection" : "LeftToRightDirection"
        let body = paragraphStyleRangeXML(styleRef: styleRef, text: text, inlineRuns: inlineRuns,
                                          footnotes: footnotes, footnoteStyleRef: footnoteStyleRef)
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

    /// FRAME-SPLIT：一条正文串接流（连续纯正文段落）合成一个 Story，`paragraphs`
    /// 按阅读顺序排列。每段一个 ParagraphStyleRange——但 PSR 边界本身不是段落标记，
    /// InDesign 仍会把相邻 PSR 的文字接续渲染成一整段。真正的段落回车是 IDML 的
    /// **`<Br/>` 元素**（放在段落最后，最后一段不带），InDesign 才把它们识别成各自
    /// 独立的段落（各自套段落样式、段后间距 SpaceAfter 生效出空行）。
    /// ⚠️ 段落回车不能用字符：实测 U+000A 被当「强制换行/软回车」（整章并成一段、标题不套
    /// 样式、无空行）；U+2029 被当空格；不加分隔则文字全糊。只有 `<Br/>` 元素是对的
    /// （2026-07-07 用户逐一实机验证 7 种写法，仅 `<Br/>` 通过：标题变大+分段+空行）。
    func chapterStoryXML(self id: String, vertical: Bool, paragraphs: [ChapterParagraph]) -> String {
        let orientation = vertical ? "Vertical" : "Horizontal"
        let direction = vertical ? "RightToLeftDirection" : "LeftToRightDirection"
        let lastIndex = paragraphs.count - 1
        let body = paragraphs.enumerated().map { index, p -> String in
            // 可见文字 → 段落回车 <Br/>（单独一个 CharacterStyleRange，放在本段最后）。
            let textRanges = characterStyleRanges(for: p.text, globalStart: 0, inlineRuns: p.inlineRuns ?? [], footnotes: p.footnotes, footnoteStyleRef: p.footnoteStyleRef, noBreakTail: trailingNoBreakCount(for: p.text))
            let paragraphMark = index == lastIndex ? [] : [Self.paragraphBreakRange]
            let ranges = ([textRanges] + paragraphMark).joined(separator: "\n")
            return """
            \t\t<ParagraphStyleRange AppliedParagraphStyle="\(p.styleRef)">
            \(ranges)
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

    /// IDML 的段落回车：`<Br/>` 元素单独占一个 CharacterStyleRange，放在段落最后。
    /// 不能用字符（U+000A=软回车、U+2029=空格，都会把相邻段落并成一段——见 chapterStoryXML 注释）。
    static let paragraphBreakRange =
        "\t\t\t<CharacterStyleRange AppliedCharacterStyle=\"CharacterStyle/$ID/[No character style]\"><Br/></CharacterStyleRange>"

    /// 一段文本按非空行拆成若干 ParagraphStyleRange（沿用既有折行→段落的规则）。
    /// 段与段之间加 `<Br/>` 段落回车，否则 InDesign 会把它们并成一整段（除末段外）。
    func paragraphStyleRangeXML(
        styleRef: String, text: String, inlineRuns: [InlineRun]?,
        footnotes: [Paragraph], footnoteStyleRef: String
    ) -> String {
        var lineStart = 0
        let lines = text.components(separatedBy: "\n").compactMap { rawLine -> (String, Int)? in
            defer { lineStart += rawLine.count + 1 }
            let leading = rawLine.prefix { $0.isWhitespace }.count
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            return line.isEmpty ? nil : (line, lineStart + leading)
        }
        let effectiveLines = lines.isEmpty ? [(text, 0)] : lines
        let lastIndex = effectiveLines.count - 1
        return effectiveLines.enumerated().map { index, pair in
            let (line, start) = pair
            let mark = index == lastIndex ? "" : "\n" + Self.paragraphBreakRange
            return """
            \t\t<ParagraphStyleRange AppliedParagraphStyle="\(styleRef)">
            \(characterStyleRanges(for: line, globalStart: start, inlineRuns: inlineRuns ?? [], footnotes: footnotes, footnoteStyleRef: footnoteStyleRef))\(mark)
            \t\t</ParagraphStyleRange>
            """
        }.joined(separator: "\n")
    }

    /// 脚注正文需要一个带中文复合字体（CF_*）的段落样式，否则 InDesign 退回拉丁默认字体、
    /// 中文显示为豆腐。优先用 caption（小字号、无首行缩进，最像脚注），退而求其次用 body；
    /// 都没有才用空样式。绝不再写死 [No paragraph style]。
    func footnoteStyleRef(for footnotes: [Paragraph], ctx: BuildContext) -> String {
        guard !footnotes.isEmpty else { return "ParagraphStyle/$ID/[No paragraph style]" }
        let emittedStyleIds = Set(ctx.paragraphStyles.map { $0.id })
        if emittedStyleIds.contains(StyleID.caption.rawValue) {
            return "ParagraphStyle/\(StyleID.caption.rawValue)"
        } else if emittedStyleIds.contains(StyleID.body.rawValue) {
            return "ParagraphStyle/\(StyleID.body.rawValue)"
        } else {
            return "ParagraphStyle/$ID/[No paragraph style]"
        }
    }

    /// 段末孤字防治：算出该段末尾应绑定为「禁止断行」的字符数，使最后一行至少有两个
    /// 实义字（末尾悬挂标点一起绑）。InDesign 没有原生「避免单字尾行」开关，社区通行做法
    /// 就是用 NoBreak 字符属性把末尾几个字锁在一起，宽度放不下时整体换到最后一行。
    func trailingNoBreakCount(for text: String) -> Int {
        let chars = Array(text)
        // 三字以下整段至多一两行、不会出现「上一行满 + 末行单字」的孤字，无需处理。
        guard chars.count >= 3 else { return 0 }
        let hangable = Set<Character>("，。、；：）】〕》〉」』”’.,!?！？")
        var lastReal = chars.count - 1
        while lastReal >= 0 && hangable.contains(chars[lastReal]) { lastReal -= 1 }
        // 全是标点，或只有一个实义字：绑了也凑不出两个实义字，放弃。
        guard lastReal >= 1 else { return 0 }
        // 绑定「倒数第二个实义字 …… 段尾」= 两个实义字 + 尾部悬挂标点。
        return chars.count - (lastReal - 1)
    }

    func characterStyleRanges(
        for text: String,
        globalStart: Int,
        inlineRuns: [InlineRun],
        footnotes: [Paragraph] = [],
        footnoteStyleRef: String = "ParagraphStyle/$ID/[No paragraph style]",
        noBreakTail: Int = 0
    ) -> String {
        guard !footnotes.isEmpty else {
            return styledCharacterRanges(for: text, globalStart: globalStart, inlineRuns: inlineRuns, noBreakTail: noBreakTail)
        }
        // 带脚注的段落走下方拆分路径，段末孤字防治暂不叠加（脚注段本就少见，避免与
        // 脚注锚点拆分逻辑纠缠）。

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
            output += footnoteXML(footnote, styleRef: footnoteStyleRef)
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

    func styledCharacterRanges(for text: String, globalStart: Int, inlineRuns: [InlineRun], noBreakTail: Int = 0) -> String {
        let characters = Array(text)
        guard !characters.isEmpty else { return "" }
        var styles = Array(repeating: Set<InlineEmphasis>(), count: characters.count)
        for run in inlineRuns {
            let start = max(0, run.location - globalStart)
            let end = min(characters.count, run.location + run.length - globalStart)
            guard start < end else { continue }
            for index in start..<end { styles[index].formUnion(run.emphasis) }
        }
        // 段末孤字防治：末尾 noBreakTail 个字符标「禁止断行」，让它们放不下时整体换到
        // 最后一行，避免单字孤零零成行。noBreak 与 emphasis 一样是分段维度，任一变化即断段。
        var noBreak = Array(repeating: false, count: characters.count)
        if noBreakTail > 0 {
            for index in max(0, characters.count - noBreakTail)..<characters.count { noBreak[index] = true }
        }

        var ranges: [(String, Set<InlineEmphasis>, Bool)] = []
        var start = 0
        for index in 1...characters.count
        where index == characters.count || styles[index] != styles[start] || noBreak[index] != noBreak[start] {
            ranges.append((String(characters[start..<index]), styles[start], noBreak[start]))
            start = index
        }
        return ranges.map { content, emphasis, isNoBreak in
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
                // 着重号按中文习惯：实心黑圆点 ● 置于字下方（KentenBlackCircle + BelowLeft）。
                // 经真·InDesign 2026 存盘比对(Desktop/未命名-1.idml kenten golden, 2026-06-23):
                // 真值字符级只写这三个属性, 且 KentenAlignment 是段落级、不写在 CharacterStyleRange 上。
                // 此前用日文习惯(KentenSesameDot 芝麻点 + AboveRight 字上方)——中文书不对。
                attrs += " KentenKind=\"KentenBlackCircle\""
                attrs += " KentenPlacement=\"-1\""
                attrs += " KentenPosition=\"BelowLeft\""
            }
            // NoBreak：InDesign 的「禁止断行」字符属性（DOM 的 noBreak，读写布尔）。
            if isNoBreak { attrs += " NoBreak=\"true\"" }
            return "\t\t\t<CharacterStyleRange AppliedCharacterStyle=\"CharacterStyle/$ID/[No character style]\"\(attrs)><Content>\(esc(content))</Content></CharacterStyleRange>"
        }.joined(separator: "\n")
    }

    func footnoteXML(_ paragraph: Paragraph, styleRef: String) -> String {
        let body = styledCharacterRanges(
            for: paragraph.text,
            globalStart: 0,
            inlineRuns: paragraph.inlineRuns ?? []
        )
        // 脚注也是 CJK 段落，统一用 World-Ready 排版器（与正文一致）：对纯脚注无害，
        // 又能在脚注内出现着重号/避头尾时正确排版。
        return """
        \t\t\t<Footnote>
        \t\t\t\t<ParagraphStyleRange AppliedParagraphStyle="\(styleRef)">
        \(body)
        \t\t\t\t</ParagraphStyleRange>
        \t\t\t</Footnote>
        """
    }

    /// 原生 IDML 表格 Story。InDesign 的 <Table> 子元素顺序固定：先全部 <Column>，
    /// 再全部 <Row>，最后全部 <Cell>（Cell 不嵌在 Row 里，靠 Name="列:行" 定位）。
    /// 第一行视为表头。列宽按框宽均分；单元格四边给 0.5pt 黑边，使其在 InDesign 里
    /// 一眼是真表格。单元格文字复用 styledCharacterRanges，并与正文一样带 World-Ready 排版器。
    func tableStoryXML(self id: String, styleRef: String, cells: [[String]], cellRuns: [[[InlineRun]]]? = nil, frameWidth: Double, cellFillSwatch: String? = nil) -> String {
        let rowCount = cells.count
        let columnCount = cells.map(\.count).max() ?? 0
        guard rowCount > 0, columnCount > 0 else {
            return storyXML(self: id, styleRef: styleRef, vertical: false, text: "")
        }
        let headerRowCount = 1
        let bodyRowCount = rowCount - headerRowCount
        let columnWidth = frameWidth > 0 ? frameWidth / Double(columnCount) : 80
        let rowHeight = 18.0
        let tableSelf = "\(id)_tbl"

        let columns = (0..<columnCount).map { c in
            "\t\t\t\t\t<Column Self=\"\(tableSelf)Col\(c)\" Name=\"\(c)\" SingleColumnWidth=\"\(fmt(columnWidth))\"/>"
        }.joined(separator: "\n")

        let rows = (0..<rowCount).map { r in
            let rowType = r < headerRowCount ? "HeaderRow" : "BodyRow"
            return "\t\t\t\t\t<Row Self=\"\(tableSelf)Row\(r)\" Name=\"\(r)\" SingleRowHeight=\"\(fmt(rowHeight))\" RowType=\"\(rowType)\"/>"
        }.joined(separator: "\n")

        // 四边 0.5pt 黑边 + 2pt 内边距（与 LayoutEngine.estimatedTableHeight 的 cellInset 一致，
        // 否则估高与 InDesign 实际折行不符会溢流）。
        let border = "TopEdgeStrokeWeight=\"0.5\" BottomEdgeStrokeWeight=\"0.5\" LeftEdgeStrokeWeight=\"0.5\" RightEdgeStrokeWeight=\"0.5\" TopEdgeStrokeColor=\"Color/Black\" BottomEdgeStrokeColor=\"Color/Black\" LeftEdgeStrokeColor=\"Color/Black\" RightEdgeStrokeColor=\"Color/Black\" TopInset=\"2\" BottomInset=\"2\" LeftInset=\"2\" RightInset=\"2\""
        // 底色挂在单元格（而非整框）上，使色块正好贴合表格。
        let fillAttr = cellFillSwatch.map { " FillColor=\"\($0)\"" } ?? ""
        var cellsXML: [String] = []
        for r in 0..<rowCount {
            for c in 0..<columnCount {
                let content = c < cells[r].count ? cells[r][c] : ""
                // 该格的行内格式（粗/斜/傍点），偏移针对该格文本；缺则空（纯文字）。
                let runs: [InlineRun] = (cellRuns.flatMap { r < $0.count && c < $0[r].count ? $0[r][c] : nil }) ?? []
                let cellBody = styledCharacterRanges(for: content, globalStart: 0, inlineRuns: runs)
                cellsXML.append("""
                \t\t\t\t\t<Cell Self="\(tableSelf)Cell\(c)_\(r)" Name="\(c):\(r)" RowSpan="1" ColumnSpan="1" AppliedCellStyle="CellStyle/$ID/[None]"\(fillAttr) \(border)>
                \t\t\t\t\t\t<ParagraphStyleRange AppliedParagraphStyle="\(styleRef)" FirstLineIndent="0" Justification="LeftAlign">
                \(cellBody)
                \t\t\t\t\t\t</ParagraphStyleRange>
                \t\t\t\t\t</Cell>
                """)
            }
        }

        let table = """
        \t\t\t\t<Table Self="\(tableSelf)" AppliedTableStyle="TableStyle/$ID/[No table style]" HeaderRowCount="\(headerRowCount)" FooterRowCount="0" BodyRowCount="\(bodyRowCount)" ColumnCount="\(columnCount)">
        \(columns)
        \(rows)
        \(cellsXML.joined(separator: "\n"))
        \t\t\t\t</Table>
        """

        return """
        \(header)
        <idPkg:Story \(pkgNS) DOMVersion="\(dom)">
        \t<Story Self="\(id)" AppliedTOCStyle="n" TrackChanges="false" StoryTitle="$ID/" AppliedNamedGrid="n">
        \t\t<StoryPreference OpticalMarginAlignment="false" OpticalMarginSize="12" FrameType="TextFrameType" StoryOrientation="Horizontal" StoryDirection="LeftToRightDirection"/>
        \t\t<ParagraphStyleRange AppliedParagraphStyle="\(styleRef)">
        \t\t\t<CharacterStyleRange AppliedCharacterStyle="CharacterStyle/$ID/[No character style]">
        \(table)
        \t\t\t\t<Content></Content>
        \t\t\t</CharacterStyleRange>
        \t\t</ParagraphStyleRange>
        \t</Story>
        </idPkg:Story>
        """
    }

    /// 目录 Story：每条是独立段落，标题和页码之间是右对齐 tab（点导引线由对应 TOC
    /// 段落样式/TOCStyle 接管）。AppliedTOCStyle 让 InDesign 的“更新目录”按 heading1/
    /// heading2 重建目录，当前条目仅用于首次打开时的可见版面。
    func tocStoryXML(self id: String, entries: [TableOfContentsEntry], frameWidth: Double) -> String {
        // 制表位（右对齐 + 点导引线）必须用嵌套 <Properties><TabList><ListItem>，
        // 不能用 ParagraphStyleRange 的扁平属性——InDesign 会静默忽略扁平属性，
        // 导致页码不右对齐、无点导引线（属性在、视觉无）。Position 略减 6pt 留切口边距。
        let tabPosition = max(frameWidth - 6.0, 0)
        let tabList = """
        \t\t\t<Properties>
        \t\t\t\t<TabList type="list">
        \t\t\t\t\t<ListItem type="record">
        \t\t\t\t\t\t<Alignment type="enumeration">RightAlign</Alignment>
        \t\t\t\t\t\t<AlignmentCharacter type="string">.</AlignmentCharacter>
        \t\t\t\t\t\t<Leader type="string">.</Leader>
        \t\t\t\t\t\t<Position type="unit">\(fmt(tabPosition))</Position>
        \t\t\t\t\t</ListItem>
        \t\t\t\t</TabList>
        \t\t\t</Properties>
        """
        // 一个 story 里多段并存时，IDML 必须有显式段落回车 <Br/> 元素；否则多个
        // ParagraphStyleRange 会被并成一段、各条目录的 tab/页码串行到同一段里（实测）。
        // 末条不加，避免空段。（U+000A/U+2029 字符不行，见 chapterStoryXML 注释。）
        let body = entries.enumerated().map { index, entry in
            let style = entry.level <= 1 ? "tocLevel1" : "tocLevel2"
            let paragraphBreak = index < entries.count - 1 ? "\n" + Self.paragraphBreakRange : ""
            return """
            \t\t<ParagraphStyleRange AppliedParagraphStyle="ParagraphStyle/\(style)">
            \(tabList)
            \t\t\t<CharacterStyleRange AppliedCharacterStyle="CharacterStyle/$ID/[No character style]"><Content>\(esc(entry.title))\t\(entry.pageNumber)</Content></CharacterStyleRange>\(paragraphBreak)
            \t\t</ParagraphStyleRange>
            """
        }.joined(separator: "\n")
        return """
        \(header)
        <idPkg:Story \(pkgNS) DOMVersion="\(dom)">
        \t<Story Self="\(id)" AppliedTOCStyle="TOCStyle/layoutD_TOC" TrackChanges="false" StoryTitle="$ID/" AppliedNamedGrid="n">
        \t\t<StoryPreference OpticalMarginAlignment="false" OpticalMarginSize="12" FrameType="TextFrameType" StoryOrientation="Horizontal" StoryDirection="LeftToRightDirection"/>
        \(body)
        \t</Story>
        </idPkg:Story>
        """
    }

    func footnoteMarker(for paragraph: Paragraph) -> String? {
        guard case .footnote(let number) = paragraph.kind else { return nil }
        let digits: [Character: Character] = [
            "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
            "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"
        ]
        return String(number).compactMap { digits[$0] }.map(String.init).joined()
    }

    func firstMatch(of needle: [Character], in haystack: [Character], from start: Int) -> Int? {
        guard !needle.isEmpty, start <= haystack.count - needle.count else { return nil }
        for index in start...(haystack.count - needle.count) where Array(haystack[index..<(index + needle.count)]) == needle {
            return index
        }
        return nil
    }
}
