import Foundation
import CoreText

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
        inlineRuns: [InlineRun]? = nil
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
}
