import Foundation
import CoreText
import AppKit

public enum ChineseTypesetting {
    public static let openingPunctuation = Set<Character>("（【〔《〈「『“‘")
    public static let closingPunctuation = Set<Character>("）】〕》〉」』”’")
    public static let middleEndingPunctuation = Set<Character>("，。、；：！？")
    public static let kentenAttributeName = NSAttributedString.Key("LayoutDKenten")

    public static func makeAttributedString(
        text: String,
        style: ParagraphStyle,
        foregroundColor: CGColor? = nil,
        zoomScale: Double = 1.0,
        inlineRuns: [InlineRun]? = nil,
        project: BookProject? = nil
    ) -> NSAttributedString {
        let baseFontSize = style.fontSize * zoomScale
        let baseFont = CTFontCreateWithName(style.fontName as CFString, CGFloat(baseFontSize), nil)
        var minimumLineHeight = CGFloat(style.lineHeight) * CGFloat(zoomScale)
        var maximumLineHeight = CGFloat(style.lineHeight) * CGFloat(zoomScale)
        var firstLineIndent = CGFloat(style.firstLineIndent) * CGFloat(zoomScale)
        var lineBreakMode = CTLineBreakMode.byWordWrapping

        let paragraphStyle = withUnsafePointer(to: &minimumLineHeight) { minimumLineHeightPointer in
            withUnsafePointer(to: &maximumLineHeight) { maximumLineHeightPointer in
                withUnsafePointer(to: &firstLineIndent) { firstLineIndentPointer in
                    withUnsafePointer(to: &lineBreakMode) { lineBreakModePointer in
                        let settings = [
                            CTParagraphStyleSetting(
                                spec: .minimumLineHeight,
                                valueSize: MemoryLayout<CGFloat>.size,
                                value: minimumLineHeightPointer
                            ),
                            CTParagraphStyleSetting(
                                spec: .maximumLineHeight,
                                valueSize: MemoryLayout<CGFloat>.size,
                                value: maximumLineHeightPointer
                            ),
                            CTParagraphStyleSetting(
                                spec: .firstLineHeadIndent,
                                valueSize: MemoryLayout<CGFloat>.size,
                                value: firstLineIndentPointer
                            ),
                            CTParagraphStyleSetting(
                                spec: .lineBreakMode,
                                valueSize: MemoryLayout<CTLineBreakMode>.size,
                                value: lineBreakModePointer
                            )
                        ]
                        return CTParagraphStyleCreate(settings, settings.count)
                    }
                }
            }
        }

        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): baseFont,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle
        ]

        if let foregroundColor = foregroundColor {
            attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = foregroundColor
        }
        
        if style.layoutDirection == .vertical {
            attributes[NSAttributedString.Key(kCTVerticalFormsAttributeName as String)] = true
        }

        let attrString = NSMutableAttributedString(string: text, attributes: attributes)
        
        if !text.isEmpty {
            var runs: [(NSRange, CompositeFontMapping)] = []
            var currentMapping: CompositeFontMapping? = nil
            var runStart = text.startIndex
            
            for idx in text.indices {
                let char = text[idx]
                let mapping = style.fontMapping(for: char)
                if let cur = currentMapping, cur == mapping {
                    // Continue run
                } else {
                    if let cur = currentMapping {
                        let nsRange = NSRange(runStart..<idx, in: text)
                        runs.append((nsRange, cur))
                    }
                    runStart = idx
                    currentMapping = mapping
                }
            }
            if let cur = currentMapping {
                let nsRange = NSRange(runStart..<text.endIndex, in: text)
                runs.append((nsRange, cur))
            }
            
            for (nsRange, mapping) in runs {
                let fs = style.fontSize * mapping.sizeMultiplier * zoomScale
                let font = CTFontCreateWithName(mapping.fontName as CFString, CGFloat(fs), nil)
                attrString.addAttribute(NSAttributedString.Key(kCTFontAttributeName as String), value: font, range: nsRange)
                
                if mapping.baselineOffset != 0 {
                    let scaledOffset = mapping.baselineOffset * zoomScale
                    attrString.addAttribute(NSAttributedString.Key(kCTBaselineOffsetAttributeName as String), value: scaledOffset as CFNumber, range: nsRange)
                }
            }
            
            if let inlineRuns = inlineRuns {
                for run in inlineRuns {
                    let runRange = NSRange(location: run.location, length: run.length)
                    let stringLength = attrString.length
                    let safeLocation = max(0, min(runRange.location, stringLength))
                    let safeLength = max(0, min(runRange.length, stringLength - safeLocation))
                    let safeRange = NSRange(location: safeLocation, length: safeLength)
                    guard safeRange.length > 0 else { continue }
                    
                    if run.emphasis.contains(.kenten) {
                        attrString.addAttribute(ChineseTypesetting.kentenAttributeName, value: true, range: safeRange)
                    }
                    
                    if let colorToken = run.colorTokenRef,
                       let proj = project {
                        let hex = proj.resolvedColorHex(colorToken) ?? colorToken
                        if let color = NSColor.from(hex: hex) {
                            attrString.addAttribute(NSAttributedString.Key(kCTForegroundColorAttributeName as String), value: color.cgColor, range: safeRange)
                        }
                    }
                    
                    attrString.enumerateAttribute(NSAttributedString.Key(kCTFontAttributeName as String), in: safeRange, options: []) { value, range, stop in
                        guard let fontVal = value else { return }
                        let oldFont = fontVal as! CTFont
                        
                        let fontSize = CTFontGetSize(oldFont)
                        var font = oldFont
                        
                        if run.emphasis.contains(.bold) {
                            if let boldFont = CTFontCreateCopyWithSymbolicTraits(font, 0.0, nil, .boldTrait, .boldTrait) {
                                font = boldFont
                            }
                        }
                        
                        if run.emphasis.contains(.italic) {
                            var skewMatrix: CGAffineTransform
                            if style.layoutDirection == .vertical {
                                // Vertical italic: vertical lines stay vertical, horizontal lines tilt.
                                // Shear along the y-axis: y' = y + x * tan(12°)
                                skewMatrix = CGAffineTransform(a: 1.0, b: CGFloat(tan(12.0 * Double.pi / 180.0)), c: 0.0, d: 1.0, tx: 0.0, ty: 0.0)
                            } else {
                                // Horizontal italic: horizontal lines stay horizontal, vertical lines tilt.
                                // Shear along the x-axis: x' = x + y * tan(12°)
                                skewMatrix = CGAffineTransform(a: 1.0, b: 0.0, c: CGFloat(tan(12.0 * Double.pi / 180.0)), d: 1.0, tx: 0.0, ty: 0.0)
                            }
                            font = CTFontCreateCopyWithAttributes(font, fontSize, &skewMatrix, nil)
                        }
                        
                        attrString.addAttribute(NSAttributedString.Key(kCTFontAttributeName as String), value: font, range: range)
                    }
                }
            }
        }
        
        applyPunctuationCompression(to: attrString, fontSize: style.fontSize * zoomScale)
        return attrString
    }

    public static func applyPunctuationCompression(to attributedString: NSMutableAttributedString, fontSize: Double) {
        let string = attributedString.string
        let characters = Array(string)
        guard characters.count > 1 else { return }

        for i in 0..<(characters.count - 1) {
            let current = characters[i]
            let next = characters[i + 1]

            var kernValue: Double? = nil

            // Rule 1: Closing punctuation followed by middle/ending punctuation
            if closingPunctuation.contains(current) && middleEndingPunctuation.contains(next) {
                kernValue = -fontSize * 0.5
            }
            // Rule 2: Closing punctuation followed by another closing punctuation
            else if closingPunctuation.contains(current) && closingPunctuation.contains(next) {
                kernValue = -fontSize * 0.5
            }
            // Rule 3: Opening punctuation followed by another opening punctuation
            else if openingPunctuation.contains(current) && openingPunctuation.contains(next) {
                kernValue = -fontSize * 0.5
            }
            // Rule 4: Middle/ending punctuation followed by opening punctuation
            else if middleEndingPunctuation.contains(current) && openingPunctuation.contains(next) {
                kernValue = -fontSize * 0.5
            }

            if let kern = kernValue {
                let range = NSRange(location: i, length: 1)
                attributedString.addAttribute(
                    NSAttributedString.Key(kCTKernAttributeName as String),
                    value: kern as CFNumber,
                    range: range
                )
            }
        }
    }

    public static func estimatedTextWidth(text: String, style: ParagraphStyle, inlineRuns: [InlineRun]? = nil) -> Double {
        let attrString = makeAttributedString(text: text, style: style, inlineRuns: inlineRuns)
        let line = CTLineCreateWithAttributedString(attrString)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        return Double(width)
    }

    public static func breakTextIntoLines(
        _ text: String,
        style: ParagraphStyle,
        columnWidth: Double,
        hangingWidth: Double = 0.0,
        inlineRuns: [InlineRun]? = nil
    ) -> [String] {
        let trimmedText = text.trimmedForLayout
        guard !trimmedText.isEmpty else { return [] }
        
        let hangableCharacters = Set<Character>("，。、；：）】〕》〉」』”’.,")
        func isHangable(_ char: Character) -> Bool {
            hangableCharacters.contains(char)
        }

        var lines: [String] = []
        var remaining = trimmedText
        
        while !remaining.isEmpty {
            let count = remaining.count
            var k = count
            
            // Find baseline k using binary search
            var low = 1
            var high = count
            var bestK = 1
            
            while low <= high {
                let mid = (low + high) / 2
                let prefix = String(remaining.prefix(mid))
                let startIndexInOriginal = trimmedText.count - remaining.count
                let mappedRuns = InlineRun.mapRuns(inlineRuns ?? [], toSubstringFrom: startIndexInOriginal, length: mid)
                let width = estimatedTextWidth(text: prefix, style: style, inlineRuns: mappedRuns)
                if width <= columnWidth {
                    bestK = mid
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }
            
            k = bestK
            
            // If we didn't consume the whole string, apply hanging and line-breaking rules
            if k < count {
                // 1. Punctuation hanging
                if hangingWidth > 0 {
                    var tempK = k
                    while tempK < count {
                        let nextChar = remaining[remaining.index(remaining.startIndex, offsetBy: tempK)]
                        if isHangable(nextChar) {
                            let candidatePrefix = String(remaining.prefix(tempK + 1))
                            let startIndexInOriginal = trimmedText.count - remaining.count
                            let mappedRuns = InlineRun.mapRuns(inlineRuns ?? [], toSubstringFrom: startIndexInOriginal, length: tempK + 1)
                            let width = estimatedTextWidth(text: candidatePrefix, style: style, inlineRuns: mappedRuns)
                            if width <= columnWidth + hangingWidth {
                                tempK += 1
                                k = tempK
                            } else {
                                break
                            }
                        } else {
                            break
                        }
                    }
                }
                
                // 2. Adjust for forbidden line start/end
                for _ in 0..<5 { // prevent infinite loop
                    guard k > 1 && k < count else { break }
                    
                    let lastChar = remaining[remaining.index(remaining.startIndex, offsetBy: k - 1)]
                    let nextChar = remaining[remaining.index(remaining.startIndex, offsetBy: k)]
                    
                    // If last char of current line is forbidden at end, push it to next line
                    if ChineseLineBreakRules.forbidsLineEnd(lastChar) {
                        k -= 1
                        continue
                    }
                    
                    // If first char of next line is forbidden at start, pull it to current line or push previous char
                    if ChineseLineBreakRules.forbidsLineStart(nextChar) {
                        // Try to pull it
                        let candidatePrefix = String(remaining.prefix(k + 1))
                        let startIndexInOriginal = trimmedText.count - remaining.count
                        let mappedRuns = InlineRun.mapRuns(inlineRuns ?? [], toSubstringFrom: startIndexInOriginal, length: k + 1)
                        let width = estimatedTextWidth(text: candidatePrefix, style: style, inlineRuns: mappedRuns)
                        let maxAllowedWidth = columnWidth + (isHangable(nextChar) ? hangingWidth : 0.0)
                        if width <= maxAllowedWidth {
                            k += 1
                        } else {
                            // Push previous char to next line
                            k -= 1
                        }
                        continue
                    }
                    
                    break
                }
            }
            
            let line = String(remaining.prefix(k)).trimmedForLayout
            if line.isEmpty {
                let firstChar = String(remaining.prefix(1))
                lines.append(firstChar)
                remaining = String(remaining.dropFirst(1)).trimmedForLayout
            } else {
                lines.append(line)
                remaining = String(remaining.dropFirst(k)).trimmedForLayout
            }
        }
        
        return lines
    }

    public static func drawKentenDots(
        for frame: CTFrame,
        in context: CGContext,
        layoutDirection: LayoutDirection?,
        zoomScale: CGFloat
    ) {
        let path = CTFrameGetPath(frame)
        let rect = path.boundingBox
        let origin = rect.origin
        
        let lines = CTFrameGetLines(frame) as! [CTLine]
        let count = lines.count
        guard count > 0 else { return }
        
        var lineOrigins = [CGPoint](repeating: .zero, count: count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &lineOrigins)
        
        context.saveGState()
        
        for i in 0..<count {
            let line = lines[i]
            let lineOrigin = lineOrigins[i]
            
            let runs = CTLineGetGlyphRuns(line) as! [CTRun]
            for run in runs {
                let attributes = CTRunGetAttributes(run) as! [NSAttributedString.Key: Any]
                guard attributes[kentenAttributeName] != nil else { continue }
                
                let glyphCount = CTRunGetGlyphCount(run)
                guard glyphCount > 0 else { continue }
                
                guard let fontVal = attributes[NSAttributedString.Key(kCTFontAttributeName as String)] else { continue }
                let font = fontVal as! CTFont
                let fontSize = CTFontGetSize(font)
                
                let foregroundColor: CGColor
                if let colorVal = attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] {
                    foregroundColor = (colorVal as! CGColor)
                } else {
                    foregroundColor = CGColor(gray: 0, alpha: 1)
                }
                
                var positions = [CGPoint](repeating: .zero, count: glyphCount)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                
                var glyphAdvances = [CGSize](repeating: .zero, count: glyphCount)
                CTRunGetAdvances(run, CFRange(location: 0, length: 0), &glyphAdvances)
                
                let descent = CTFontGetDescent(font)
                
                let dotRadius = fontSize * 0.12
                let gap = fontSize * 0.12
                
                context.setFillColor(foregroundColor)
                
                for g in 0..<glyphCount {
                    let pos = positions[g]
                    let advance = glyphAdvances[g]
                    let glyphWidth = advance.width
                    
                    var dotCenter: CGPoint
                    if layoutDirection == .vertical {
                        // Vertical: to the right of the character
                        let x = origin.x + lineOrigin.x + pos.x + fontSize / 2 + dotRadius + gap
                        let y = origin.y + lineOrigin.y + pos.y
                        dotCenter = CGPoint(x: x, y: y)
                    } else {
                        // Horizontal: under the character
                        let x = origin.x + lineOrigin.x + pos.x + glyphWidth / 2
                        let y = origin.y + lineOrigin.y + pos.y - descent - gap - dotRadius
                        dotCenter = CGPoint(x: x, y: y)
                    }
                    
                    let dotRect = CGRect(
                        x: dotCenter.x - dotRadius,
                        y: dotCenter.y - dotRadius,
                        width: dotRadius * 2,
                        height: dotRadius * 2
                    )
                    context.fillEllipse(in: dotRect)
                }
            }
        }
        
        context.restoreGState()
    }

    public static func makeTOCAttributedString(
        entries: [TableOfContentsEntry],
        project: BookProject,
        containerWidth: Double,
        zoomScale: Double = 1.0,
        foregroundColor: CGColor? = nil
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        
        let tocLevel1Base = project.styles.paragraphStyle(id: StyleID.heading2.rawValue)
        let tocLevel2Base = project.styles.paragraphStyle(id: StyleID.caption.rawValue)
        
        var tocLevel1Style = tocLevel1Base
        tocLevel1Style.id = "tocLevel1"
        tocLevel1Style.displayName = "目录一级"
        tocLevel1Style.firstLineIndent = 0
        tocLevel1Style.spaceBefore = 0
        tocLevel1Style.spaceAfter = 2
        
        var tocLevel2Style = tocLevel2Base
        tocLevel2Style.id = "tocLevel2"
        tocLevel2Style.displayName = "目录二级"
        tocLevel2Style.firstLineIndent = 12
        tocLevel2Style.spaceBefore = 0
        tocLevel2Style.spaceAfter = 2

        for (index, entry) in entries.enumerated() {
            let entryStyle = entry.level <= 1 ? tocLevel1Style : tocLevel2Style
            
            let baseFontSize = entryStyle.fontSize * zoomScale
            let baseFont = CTFontCreateWithName(entryStyle.fontName as CFString, CGFloat(baseFontSize), nil)
            
            var minH = CGFloat(entryStyle.lineHeight) * CGFloat(zoomScale)
            var maxH = CGFloat(entryStyle.lineHeight) * CGFloat(zoomScale)
            var indent = CGFloat(entryStyle.firstLineIndent) * CGFloat(zoomScale)
            var lbm = CTLineBreakMode.byWordWrapping
            
            let tabLocation = CGFloat(containerWidth - 6.0 * zoomScale)
            let tab = CTTextTabCreate(.right, Double(tabLocation), nil)
            var tabList: CFArray = [tab] as CFArray
            
            let paragraphStyle = withUnsafePointer(to: &minH) { minHPointer in
                withUnsafePointer(to: &maxH) { maxHPointer in
                    withUnsafePointer(to: &indent) { indentPointer in
                        withUnsafePointer(to: &lbm) { lbmPointer in
                            withUnsafePointer(to: &tabList) { tabListPointer in
                                let settings = [
                                    CTParagraphStyleSetting(spec: .minimumLineHeight, valueSize: MemoryLayout<CGFloat>.size, value: minHPointer),
                                    CTParagraphStyleSetting(spec: .maximumLineHeight, valueSize: MemoryLayout<CGFloat>.size, value: maxHPointer),
                                    CTParagraphStyleSetting(spec: .firstLineHeadIndent, valueSize: MemoryLayout<CGFloat>.size, value: indentPointer),
                                    CTParagraphStyleSetting(spec: .lineBreakMode, valueSize: MemoryLayout<CTLineBreakMode>.size, value: lbmPointer),
                                    CTParagraphStyleSetting(spec: .tabStops, valueSize: MemoryLayout<CFArray>.size, value: tabListPointer)
                                ]
                                return CTParagraphStyleCreate(settings, settings.count)
                            }
                        }
                    }
                }
            }
            
            var attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): baseFont,
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle
            ]
            
            if let foregroundColor = foregroundColor {
                attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = foregroundColor
            }
            
            let titleAttr = ChineseTypesetting.makeAttributedString(
                text: entry.title,
                style: entryStyle,
                foregroundColor: foregroundColor,
                zoomScale: zoomScale
            )
            
            let pageAttr = ChineseTypesetting.makeAttributedString(
                text: String(entry.pageNumber),
                style: entryStyle,
                foregroundColor: foregroundColor,
                zoomScale: zoomScale
            )
            
            let dotAttr = ChineseTypesetting.makeAttributedString(
                text: ".",
                style: entryStyle,
                foregroundColor: foregroundColor,
                zoomScale: zoomScale
            )
            
            let titleLine = CTLineCreateWithAttributedString(titleAttr)
            let titleWidth = Double(CTLineGetTypographicBounds(titleLine, nil, nil, nil))
            
            let pageLine = CTLineCreateWithAttributedString(pageAttr)
            let pageWidth = Double(CTLineGetTypographicBounds(pageLine, nil, nil, nil))
            
            let dotLine = CTLineCreateWithAttributedString(dotAttr)
            let dotWidth = Double(CTLineGetTypographicBounds(dotLine, nil, nil, nil))
            
            let extraSpacing = 16.0 * zoomScale
            let dotsWidth = containerWidth - Double(indent) - titleWidth - pageWidth - extraSpacing
            
            let dotCount = (dotsWidth > 0 && dotWidth > 0) ? Int(dotsWidth / dotWidth) : 0
            let dotsStr = String(repeating: ".", count: dotCount)
            
            let lineText = "\(entry.title) \(dotsStr)\t\(entry.pageNumber)" + (index < entries.count - 1 ? "\n" : "")
            let lineAttrString = NSMutableAttributedString(string: lineText, attributes: attributes)
            
            if !lineText.isEmpty {
                var runs: [(NSRange, CompositeFontMapping)] = []
                var currentMapping: CompositeFontMapping? = nil
                var runStart = lineText.startIndex
                
                for idx in lineText.indices {
                    let char = lineText[idx]
                    let mapping = entryStyle.fontMapping(for: char)
                    if let cur = currentMapping, cur == mapping {
                        // Continue run
                    } else {
                        if let cur = currentMapping {
                            let nsRange = NSRange(runStart..<idx, in: lineText)
                            runs.append((nsRange, cur))
                        }
                        runStart = idx
                        currentMapping = mapping
                    }
                }
                if let cur = currentMapping {
                    let nsRange = NSRange(runStart..<lineText.endIndex, in: lineText)
                    runs.append((nsRange, cur))
                }
                
                for (nsRange, mapping) in runs {
                    let fs = entryStyle.fontSize * mapping.sizeMultiplier * zoomScale
                    let font = CTFontCreateWithName(mapping.fontName as CFString, CGFloat(fs), nil)
                    lineAttrString.addAttribute(NSAttributedString.Key(kCTFontAttributeName as String), value: font, range: nsRange)
                    
                    if mapping.baselineOffset != 0 {
                        let scaledOffset = mapping.baselineOffset * zoomScale
                        lineAttrString.addAttribute(NSAttributedString.Key(kCTBaselineOffsetAttributeName as String), value: scaledOffset as CFNumber, range: nsRange)
                    }
                }
            }
            
            result.append(lineAttrString)
        }
        
        return result
    }
}

public struct TableLayoutHelper {
    public struct TableData {
        public var rows: [[String]]
        public var columnCount: Int {
            rows.map(\.count).max() ?? 0
        }
    }

    public static func parseTableText(_ text: String) -> TableData {
        let rawRows = text.components(separatedBy: .newlines)
        var parsedRows: [[String]] = []
        for rawRow in rawRows {
            let cells = rawRow.components(separatedBy: "    ")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if !cells.allSatisfy({ $0.isEmpty }) {
                parsedRows.append(cells)
            }
        }
        return TableData(rows: parsedRows)
    }

    public static func allocateColumnWidths(
        tableData: TableData,
        totalWidth: Double,
        fontName: String,
        fontSize: Double,
        zoomScale: Double = 1.0
    ) -> [Double] {
        let colCount = tableData.columnCount
        guard colCount > 0 else { return [] }
        
        var maxCellWidths = [Double](repeating: 0.0, count: colCount)
        let ctFont = CTFontCreateWithName(fontName as CFString, CGFloat(fontSize * zoomScale), nil)
        
        for row in tableData.rows {
            for col in 0..<colCount {
                let cellText = col < row.count ? row[col] : ""
                let attrString = NSAttributedString(
                    string: cellText,
                    attributes: [NSAttributedString.Key(kCTFontAttributeName as String): ctFont]
                )
                let line = CTLineCreateWithAttributedString(attrString)
                let width = CTLineGetTypographicBounds(line, nil, nil, nil)
                maxCellWidths[col] = max(maxCellWidths[col], Double(width))
            }
        }
        
        let sumMeasured = maxCellWidths.reduce(0, +)
        if sumMeasured > 0 {
            let minWidth = totalWidth / Double(colCount) * 0.5
            var widths = [Double](repeating: 0.0, count: colCount)
            for col in 0..<colCount {
                let share = (maxCellWidths[col] / sumMeasured) * totalWidth
                widths[col] = max(minWidth, share)
            }
            let sumWidths = widths.reduce(0, +)
            for col in 0..<colCount {
                widths[col] = (widths[col] / sumWidths) * totalWidth
            }
            return widths
        } else {
            let eqWidth = totalWidth / Double(colCount)
            return [Double](repeating: eqWidth, count: colCount)
        }
    }

    public static func calculateRowHeights(
        tableData: TableData,
        colWidths: [Double],
        style: ParagraphStyle,
        textInsetX: Double,
        textInsetY: Double,
        zoomScale: Double = 1.0
    ) -> [Double] {
        var rowHeights: [Double] = []
        let cellWidths = colWidths
        let cellCount = cellWidths.count
        
        for row in tableData.rows {
            var maxCellHeight = style.lineHeight * zoomScale
            for col in 0..<cellCount {
                let cellText = col < row.count ? row[col] : ""
                if cellText.isEmpty { continue }
                
                let attrString = ChineseTypesetting.makeAttributedString(
                    text: cellText,
                    style: style,
                    zoomScale: zoomScale
                )
                let framesetter = CTFramesetterCreateWithAttributedString(attrString)
                let usableWidth = max(1.0, cellWidths[col] - textInsetX * 2 * zoomScale)
                let constraint = CGSize(width: usableWidth, height: .greatestFiniteMagnitude)
                let size = CTFramesetterSuggestFrameSizeWithConstraints(
                    framesetter,
                    CFRange(location: 0, length: attrString.length),
                    nil,
                    constraint,
                    nil
                )
                let cellHeight = Double(size.height) + textInsetY * 2 * zoomScale
                maxCellHeight = max(maxCellHeight, cellHeight)
            }
            rowHeights.append(maxCellHeight)
        }
        return rowHeights
    }
}
