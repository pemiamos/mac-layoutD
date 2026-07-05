import Foundation
import LayoutDCore

extension MarkdownParser {
    func normalizeInlineMarkdown(_ text: String) -> String {
        parseInlineMarkdown(text).text
    }

    func makeParagraph(
        kind: ParagraphKind,
        markdown: String,
        styleId: String
    ) -> Paragraph {
        let inline = parseInlineMarkdown(markdown)
        return Paragraph(
            kind: kind,
            text: inline.text,
            styleId: styleId,
            inlineRuns: inline.runs.isEmpty ? nil : inline.runs
        )
    }

    struct ParsedInlineMarkdown {
        var text: String
        var runs: [InlineRun]
    }

    /// Flattens the supported Markdown delimiters while retaining bold/italic/kenten spans.
    /// Code spans remain unstyled and escaped delimiters remain literal.
    func parseInlineMarkdown(_ text: String) -> ParsedInlineMarkdown {
        let source = replacingMarkdownLinks(in: text)
        var output = ""
        var stylesByCharacter: [Set<InlineEmphasis>] = []
        var active: Set<InlineEmphasis> = []
        var codeSpan = false
        var index = source.startIndex

        func hasClosingDelimiter(_ delimiter: String, after start: String.Index) -> Bool {
            firstDelimiterIndex(in: source, delimiter: delimiter, startingAt: start, kind: .closing) != nil
        }

        func isValidDelimiter(_ delimiter: String, at start: String.Index, kind: InlineDelimiterKind) -> Bool {
            guard let end = source.index(start, offsetBy: delimiter.count, limitedBy: source.endIndex) else {
                return false
            }
            return isValidInlineDelimiter(start..<end, in: source, kind: kind)
        }

        while index < source.endIndex {
            if source[index] == "\\" {
                let next = source.index(after: index)
                if next < source.endIndex, "*_`[]\\".contains(source[next]) {
                    output.append(source[next])
                    stylesByCharacter.append(codeSpan ? [] : active)
                    index = source.index(after: next)
                    continue
                }
            }

            let remaining = source[index...]
            if remaining.hasPrefix("`") {
                let next = source.index(after: index)
                let kind: InlineDelimiterKind = codeSpan ? .closing : .opening
                if isValidDelimiter("`", at: index, kind: kind),
                   (codeSpan || hasClosingDelimiter("`", after: next)) {
                    codeSpan.toggle()
                    index = next
                    continue
                }
            }

            if !codeSpan {
                if remaining.hasPrefix("==") {
                    let next = source.index(index, offsetBy: 2)
                    let kind: InlineDelimiterKind = active.contains(.kenten) ? .closing : .opening
                    if isValidDelimiter("==", at: index, kind: kind),
                       (active.contains(.kenten) || hasClosingDelimiter("==", after: next)) {
                        if active.contains(.kenten) { active.remove(.kenten) } else { active.insert(.kenten) }
                        index = next
                        continue
                    }
                }

                let boldDelimiter = remaining.hasPrefix("**") ? "**" : (remaining.hasPrefix("__") ? "__" : nil)
                if let delimiter = boldDelimiter {
                    let next = source.index(index, offsetBy: delimiter.count)
                    let kind: InlineDelimiterKind = active.contains(.bold) ? .closing : .opening
                    if isValidDelimiter(delimiter, at: index, kind: kind),
                       (active.contains(.bold) || hasClosingDelimiter(delimiter, after: next)) {
                        if active.contains(.bold) { active.remove(.bold) } else { active.insert(.bold) }
                        index = next
                        continue
                    }
                }

                let italicDelimiter = remaining.hasPrefix("*") ? "*" : (remaining.hasPrefix("_") ? "_" : nil)
                if let delimiter = italicDelimiter {
                    let next = source.index(after: index)
                    let kind: InlineDelimiterKind = active.contains(.italic) ? .closing : .opening
                    if isValidDelimiter(delimiter, at: index, kind: kind),
                       (active.contains(.italic) || hasClosingDelimiter(delimiter, after: next)) {
                        if active.contains(.italic) { active.remove(.italic) } else { active.insert(.italic) }
                        index = next
                        continue
                    }
                }
            }

            output.append(source[index])
            stylesByCharacter.append(codeSpan ? [] : active)
            index = source.index(after: index)
        }

        var runs: [InlineRun] = []
        var runStart: Int?
        var runStyle: Set<InlineEmphasis> = []
        for offset in 0...stylesByCharacter.count {
            let style = offset < stylesByCharacter.count ? stylesByCharacter[offset] : []
            if style != runStyle {
                if let start = runStart, !runStyle.isEmpty {
                    runs.append(InlineRun(location: start, length: offset - start, emphasis: runStyle))
                }
                runStart = style.isEmpty ? nil : offset
                runStyle = style
            }
        }
        return ParsedInlineMarkdown(text: output, runs: runs)
    }

    func replacingMarkdownLinks(in text: String) -> String {
        var output = ""
        var index = text.startIndex

        while index < text.endIndex {
            guard text[index] == "[",
                  let labelEnd = text[index...].firstIndex(of: "]") else {
                output.append(text[index])
                index = text.index(after: index)
                continue
            }

            let parenStart = text.index(after: labelEnd)
            guard parenStart < text.endIndex,
                  text[parenStart] == "(",
                  let parenEnd = text[parenStart...].firstIndex(of: ")") else {
                output.append(text[index])
                index = text.index(after: index)
                continue
            }

            let labelStart = text.index(after: index)
            output.append(contentsOf: text[labelStart..<labelEnd])
            index = text.index(after: parenEnd)
        }

        return output
    }

    func firstDelimiterIndex(
        in text: String,
        delimiter: String,
        startingAt startIndex: String.Index,
        kind: InlineDelimiterKind
    ) -> String.Index? {
        var searchStart = startIndex
        while searchStart < text.endIndex,
              let range = text.range(of: delimiter, range: searchStart..<text.endIndex) {
            if isValidInlineDelimiter(range, in: text, kind: kind) {
                return range.lowerBound
            }
            searchStart = range.upperBound
        }
        return nil
    }

    func isValidInlineDelimiter(
        _ range: Range<String.Index>,
        in text: String,
        kind: InlineDelimiterKind
    ) -> Bool {
        guard !isEscapedDelimiter(at: range.lowerBound, in: text) else {
            return false
        }

        switch kind {
        case .opening:
            guard range.upperBound < text.endIndex else {
                return false
            }
            let nextCharacter = text[range.upperBound]
            return !nextCharacter.isWhitespace && boundaryBefore(range.lowerBound, in: text)
        case .closing:
            guard range.lowerBound > text.startIndex else {
                return false
            }
            let previousIndex = text.index(before: range.lowerBound)
            let previousCharacter = text[previousIndex]
            return !previousCharacter.isWhitespace
        }
    }

    func isEscapedDelimiter(at index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else {
            return false
        }

        let previousIndex = text.index(before: index)
        return text[previousIndex] == "\\"
    }

    func boundaryBefore(_ index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else {
            return true
        }

        let previousCharacter = text[text.index(before: index)]
        return isInlineDelimiterBoundary(previousCharacter) || isCJKCharacter(previousCharacter)
    }

    func isCJKCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x2E80...0x2FFF, 0x3040...0x30FF, 0x31F0...0x31FF,
                 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF,
                 0xF900...0xFAFF, 0x20000...0x2FA1F:
                return true
            default:
                return false
            }
        }
    }

    func isInlineDelimiterBoundary(_ character: Character) -> Bool {
        if character.isWhitespace {
            return true
        }

        let punctuation = CharacterSet.punctuationCharacters.union(
            CharacterSet(charactersIn: "=，。、；：！？（）【】《》「」『』“”‘’、")
        )
        return character.unicodeScalars.allSatisfy { punctuation.contains($0) }
    }
}

enum InlineDelimiterKind {
    case opening
    case closing
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedQuotes: String {
        var value = trimmed
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value.removeFirst()
            value.removeLast()
        }
        return value
    }
}
