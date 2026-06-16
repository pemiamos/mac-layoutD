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
}
