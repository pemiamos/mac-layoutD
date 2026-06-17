import Foundation
import CoreText

public enum ChineseTypesetting {
    public static let openingPunctuation = Set<Character>("（【〔《〈「『“‘")
    public static let closingPunctuation = Set<Character>("）】〕》〉」』”’")
    public static let middleEndingPunctuation = Set<Character>("，。、；：！？")

    public static func makeAttributedString(
        text: String,
        style: ParagraphStyle,
        foregroundColor: CGColor? = nil
    ) -> NSAttributedString {
        let font = CTFontCreateWithName(style.fontName as CFString, style.fontSize, nil)
        var minimumLineHeight = CGFloat(style.lineHeight)
        var maximumLineHeight = CGFloat(style.lineHeight)
        var firstLineIndent = CGFloat(style.firstLineIndent)
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
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle
        ]

        if let foregroundColor = foregroundColor {
            attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = foregroundColor
        }

        let attrString = NSMutableAttributedString(string: text, attributes: attributes)
        applyPunctuationCompression(to: attrString, fontSize: style.fontSize)
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

    public static func estimatedTextWidth(text: String, style: ParagraphStyle) -> Double {
        let attrString = makeAttributedString(text: text, style: style)
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
        hangingWidth: Double = 0.0
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
                let width = estimatedTextWidth(text: prefix, style: style)
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
                            let width = estimatedTextWidth(text: candidatePrefix, style: style)
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
                        let width = estimatedTextWidth(text: candidatePrefix, style: style)
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
}
