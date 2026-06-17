import Foundation
import LayoutDCore

public struct MarkdownBookImporter {
    public var defaultAuthor: String

    public init(defaultAuthor: String = "layoutD Importer") {
        self.defaultAuthor = defaultAuthor
    }

    public func importDocument(
        markdown: String,
        assetCatalog: AssetCatalog = .empty,
        fallbackTitle: String = "未命名科普书稿"
    ) -> BookProject {
        var parser = MarkdownParser(
            markdown: markdown,
            assetCatalog: assetCatalog,
            defaultAuthor: defaultAuthor,
            fallbackTitle: fallbackTitle
        )
        return parser.parse()
    }
}

private struct MarkdownParser {
    let markdown: String
    let assetCatalog: AssetCatalog
    let defaultAuthor: String
    let fallbackTitle: String

    private var title: String?
    private var subtitle: String?
    private var author: String
    private var publisher: String?
    private var isbn: String?
    private var series: String?
    private var keywords: [String] = []
    private var pageSetup: PageSetup = .scienceBookDefault
    private var sections: [BookSection] = []
    private var currentSectionTitle = "正文"
    private var currentParagraphs: [Paragraph] = []
    private var paragraphBuffer: [String] = []
    private var calloutBuffer: [String] = []
    private var tableBuffer: [String] = []
    private var assetsByReference: [String: Asset] = [:]
    private var referenceImageTargets: [String: String] = [:]
    private var isInsideHTMLComment = false
    private var footnoteDefinitions: [String: String] = [:]
    private var sideNoteBuffer: [String] = []
    private var nextFootnoteNumber = 1
    private var footnoteMap: [String: Int] = [:]

    init(markdown: String, assetCatalog: AssetCatalog, defaultAuthor: String, fallbackTitle: String) {
        self.markdown = markdown
        self.assetCatalog = assetCatalog
        self.defaultAuthor = defaultAuthor
        self.fallbackTitle = fallbackTitle
        self.author = defaultAuthor
        self.assetsByReference = assetCatalog.assets.reduce(into: [:]) { indexedAssets, asset in
            let reference = asset.fileName.normalizedAssetPath
            indexedAssets[reference] = indexedAssets[reference] ?? asset
        }
    }

    mutating func parse() -> BookProject {
        var lines = markdown.components(separatedBy: .newlines)
        let frontMatter = extractFrontMatter(from: &lines)
        footnoteDefinitions = collectAndRemoveFootnoteDefinitions(from: &lines)
        referenceImageTargets = collectReferenceImageTargets(from: lines)
        title = frontMatter.title
        subtitle = frontMatter.subtitle
        author = frontMatter.author ?? defaultAuthor
        publisher = frontMatter.publisher
        isbn = frontMatter.isbn
        series = frontMatter.series
        keywords = frontMatter.keywords
        pageSetup = frontMatter.pageSetup ?? .scienceBookDefault

        var shouldSkipLine = false
        for index in lines.indices {
            if shouldSkipLine {
                shouldSkipLine = false
                continue
            }

            let rawLine = lines[index]
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if shouldSkipHTMLCommentLine(line) {
                flushAllBuffers()
                continue
            }

            if line.isEmpty {
                flushAllBuffers()
                continue
            }

            if parseReferenceDefinition(line) != nil {
                flushAllBuffers()
                continue
            }

            let nextLine = lines.index(after: index) < lines.endIndex
                ? lines[lines.index(after: index)].trimmingCharacters(in: .whitespaces)
                : nil
            if let heading = parseSetextHeading(line: line, nextLine: nextLine) {
                flushAllBuffers()
                if heading.level == 1 {
                    flushSection()
                    if title == nil {
                        title = heading.text
                    }
                    currentSectionTitle = heading.text
                } else {
                    currentParagraphs.append(
                        Paragraph(
                            kind: .heading(level: heading.level),
                            text: heading.text,
                            styleId: StyleID.heading2.rawValue
                        )
                    )
                }
                shouldSkipLine = true
                continue
            }

            if isNonContentLine(line) {
                flushAllBuffers()
                continue
            }

            if isTableLine(line) {
                flushParagraphBuffer()
                flushCalloutBuffer()
                flushSideNoteBuffer()
                tableBuffer.append(line)
                continue
            }

            if let image = parseImage(line) {
                flushAllBuffers()
                if image.anchor == .previousParagraph, addAnchoredImage(image) {
                    continue
                }
                addFigure(image)
                continue
            }

            if let heading = parseHeading(line) {
                flushAllBuffers()
                if heading.level == 1 {
                    flushSection()
                    if title == nil {
                        title = heading.text
                    }
                    currentSectionTitle = heading.text
                } else {
                    currentParagraphs.append(
                        Paragraph(
                            kind: .heading(level: heading.level),
                            text: heading.text,
                            styleId: StyleID.heading2.rawValue
                        )
                    )
                }
                continue
            }

            if line.hasPrefix("> ") {
                flushParagraphBuffer()
                flushTableBuffer()
                flushSideNoteBuffer()
                addQuoteLine(String(line.dropFirst(2)).trimmed)
                continue
            }

            if let listItem = parseListItem(line) {
                flushAllBuffers()
                currentParagraphs.append(
                    Paragraph(
                        kind: .listItem,
                        text: listItem,
                        styleId: StyleID.body.rawValue
                    )
                )
                continue
            }

            flushCalloutBuffer()
            flushTableBuffer()
            flushSideNoteBuffer()
            paragraphBuffer.append(line)
        }

        flushAllBuffers()
        flushSection()

        let projectTitle = title ?? fallbackTitle
        let projectSections = sections.isEmpty
            ? [BookSection(title: currentSectionTitle, stories: [Story(title: currentSectionTitle, paragraphs: currentParagraphs)])]
            : sections

        return BookProject(
            metadata: ProjectMetadata(
                title: projectTitle,
                subtitle: subtitle,
                author: author,
                publisher: publisher,
                isbn: isbn,
                series: series,
                keywords: keywords
            ),
            pageSetup: pageSetup,
            sections: projectSections,
            assets: Array(assetsByReference.values).sorted {
                $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
            }
        )
    }

    private mutating func flushParagraphBuffer() {
        guard !paragraphBuffer.isEmpty else {
            return
        }
        let text = normalizeInlineMarkdown(paragraphBuffer.joined(separator: " "))
        currentParagraphs.append(Paragraph(kind: .body, text: text, styleId: StyleID.body.rawValue))
        paragraphBuffer.removeAll(keepingCapacity: true)
    }

    private mutating func flushCalloutBuffer() {
        guard !calloutBuffer.isEmpty else {
            return
        }
        currentParagraphs.append(
            Paragraph(kind: .callout, text: normalizeInlineMarkdown(calloutBuffer.joined(separator: " ")), styleId: StyleID.callout.rawValue)
        )
        calloutBuffer.removeAll(keepingCapacity: true)
    }

    private mutating func flushTableBuffer() {
        guard !tableBuffer.isEmpty else {
            return
        }

        let rows = tableBuffer
            .filter { !isTableSeparatorLine($0) }
            .map(tableCells)
            .filter { !$0.isEmpty }

        if !rows.isEmpty {
            let text = rows.map { $0.joined(separator: "    ") }.joined(separator: "\n")
            currentParagraphs.append(
                Paragraph(kind: .table, text: normalizeInlineMarkdown(text), styleId: StyleID.body.rawValue)
            )
        }

        tableBuffer.removeAll(keepingCapacity: true)
    }

    private mutating func flushSection() {
        flushSideNoteBuffer()
        postProcessFootnotesAndSideNotes()
        guard !currentParagraphs.isEmpty else {
            return
        }
        sections.append(
            BookSection(
                title: currentSectionTitle,
                stories: [
                    Story(title: currentSectionTitle, paragraphs: currentParagraphs)
                ]
            )
        )
        currentParagraphs.removeAll(keepingCapacity: true)
    }

    private mutating func addQuoteLine(_ line: String) {
        let upperLine = line.uppercased()
        if upperLine.hasPrefix("[!SIDE]") {
            flushCalloutBuffer()
            flushSideNoteBuffer()
            let suffix = String(line.dropFirst(7)).trimmed
            var cleanSuffix = suffix
            if cleanSuffix.hasPrefix(":") || cleanSuffix.hasPrefix("：") {
                cleanSuffix = String(cleanSuffix.dropFirst()).trimmed
            }
            sideNoteBuffer.append(cleanSuffix)
            return
        }

        if let calloutStart = parseAdmonitionStart(line) {
            flushCalloutBuffer()
            flushSideNoteBuffer()
            calloutBuffer.append(calloutStart)
            return
        }

        if !sideNoteBuffer.isEmpty {
            sideNoteBuffer.append(normalizeInlineMarkdown(line))
            return
        }

        if !calloutBuffer.isEmpty {
            calloutBuffer.append(normalizeInlineMarkdown(line))
            return
        }

        currentParagraphs.append(
            Paragraph(
                kind: .quote,
                text: normalizeInlineMarkdown(line),
                styleId: StyleID.callout.rawValue
            )
        )
    }

    private mutating func flushSideNoteBuffer() {
        guard !sideNoteBuffer.isEmpty else {
            return
        }
        let text = normalizeInlineMarkdown(sideNoteBuffer.joined(separator: " "))
        let sideNoteParagraph = Paragraph(
            id: UUID(),
            kind: .sideNote,
            text: text,
            styleId: "sideNote"
        )
        
        var targetIndex: Int?
        for i in currentParagraphs.indices.reversed() {
            let p = currentParagraphs[i]
            switch p.kind {
            case .footnote, .sideNote:
                continue
            default:
                targetIndex = i
                break
            }
            if targetIndex != nil { break }
        }
        
        if let idx = targetIndex {
            if currentParagraphs[idx].anchoredSideNoteIds == nil {
                currentParagraphs[idx].anchoredSideNoteIds = []
            }
            currentParagraphs[idx].anchoredSideNoteIds?.append(sideNoteParagraph.id)
            currentParagraphs.append(sideNoteParagraph)
        } else {
            currentParagraphs.append(sideNoteParagraph)
        }
        sideNoteBuffer.removeAll(keepingCapacity: true)
    }

    private func superscriptString(for number: Int) -> String {
        let superscripts = [
            0: "⁰", 1: "¹", 2: "²", 3: "³", 4: "⁴",
            5: "⁵", 6: "⁶", 7: "⁷", 8: "⁸", 9: "⁹"
        ]
        let digits = String(number).compactMap { Int(String($0)) }
        return digits.map { superscripts[$0] ?? "" }.joined()
    }

    private mutating func postProcessFootnotesAndSideNotes() {
        var footnoteParagraphsToAppend: [Paragraph] = []
        
        for i in currentParagraphs.indices {
            let paragraph = currentParagraphs[i]
            switch paragraph.kind {
            case .footnote, .sideNote:
                continue
            default:
                break
            }
            
            let text = paragraph.text
            let pattern = "\\[\\^([^\\]]+)\\]"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            
            let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
            guard !matches.isEmpty else { continue }
            
            var newText = text
            var anchoredIds: [UUID] = []
            
            for match in matches.reversed() {
                guard let idRange = Range(match.range(at: 1), in: text) else { continue }
                let id = String(text[idRange]).trimmed
                
                guard let content = footnoteDefinitions[id] else { continue }
                
                let num: Int
                if let existingNum = footnoteMap[id] {
                    num = existingNum
                } else {
                    num = nextFootnoteNumber
                    footnoteMap[id] = num
                    nextFootnoteNumber += 1
                    
                    let fnPara = Paragraph(
                        id: UUID(),
                        kind: .footnote(number: num),
                        text: content,
                        styleId: "footnote"
                    )
                    footnoteParagraphsToAppend.append(fnPara)
                }
                
                let superscript = superscriptString(for: num)
                
                if let matchRange = Range(match.range(at: 0), in: newText) {
                    newText.replaceSubrange(matchRange, with: superscript)
                }
                
                if let fnPara = footnoteParagraphsToAppend.first(where: {
                    if case .footnote(let n) = $0.kind { return n == num }
                    return false
                }) {
                    anchoredIds.insert(fnPara.id, at: 0)
                }
            }
            
            if !anchoredIds.isEmpty {
                currentParagraphs[i].text = newText
                currentParagraphs[i].anchoredFootnoteIds = anchoredIds
            }
        }
        
        currentParagraphs.append(contentsOf: footnoteParagraphsToAppend)
    }

    private mutating func collectAndRemoveFootnoteDefinitions(from lines: inout [String]) -> [String: String] {
        var footnoteDefs: [String: String] = [:]
        var indicesToRemove = IndexSet()
        var currentFootnoteId: String? = nil
        
        for index in lines.indices {
            let line = lines[index]
            if line.hasPrefix("[^") {
                if let colonIndex = line.firstIndex(of: "]"),
                   line.index(after: colonIndex) < line.endIndex,
                   line[line.index(after: colonIndex)] == ":" {
                    let idStart = line.index(line.startIndex, offsetBy: 2)
                    let id = String(line[idStart..<colonIndex]).trimmed
                    let contentStart = line.index(colonIndex, offsetBy: 2, limitedBy: line.endIndex) ?? line.endIndex
                    let content = contentStart < line.endIndex ? String(line[contentStart...]).trimmed : ""
                    footnoteDefs[id] = content
                    currentFootnoteId = id
                    indicesToRemove.insert(index)
                    continue
                }
            }
            
            if let id = currentFootnoteId {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("    ") || line.hasPrefix("\t") {
                    let existing = footnoteDefs[id] ?? ""
                    footnoteDefs[id] = existing + (existing.isEmpty ? "" : " ") + trimmed
                    indicesToRemove.insert(index)
                    continue
                } else if line.isEmpty {
                    var nextIsIndented = false
                    for nextIndex in (index + 1)..<lines.count {
                        let nextLine = lines[nextIndex]
                        if nextLine.trimmingCharacters(in: .whitespaces).isEmpty {
                            continue
                        }
                        if nextLine.hasPrefix("    ") || nextLine.hasPrefix("\t") {
                            nextIsIndented = true
                        }
                        break
                    }
                    if nextIsIndented {
                        indicesToRemove.insert(index)
                        continue
                    } else {
                        currentFootnoteId = nil
                    }
                } else {
                    currentFootnoteId = nil
                }
            }
        }
        
        lines.remove(atOffsets: indicesToRemove)
        return footnoteDefs
    }

    private mutating func flushAllBuffers() {
        flushParagraphBuffer()
        flushCalloutBuffer()
        flushTableBuffer()
        flushSideNoteBuffer()
    }

    private mutating func addFigure(_ image: MarkdownImage) {
        let asset = placedAsset(for: image)
        currentParagraphs.append(
            Paragraph(
                kind: .figure(assetId: asset.id),
                text: image.caption ?? asset.fileName,
                styleId: StyleID.caption.rawValue
            )
        )
    }

    private mutating func addAnchoredImage(_ image: MarkdownImage) -> Bool {
        guard let paragraphIndex = currentParagraphs.indices.last else {
            return false
        }

        let asset = placedAsset(for: image)
        if !currentParagraphs[paragraphIndex].anchoredAssetIds.contains(asset.id) {
            currentParagraphs[paragraphIndex].anchoredAssetIds.append(asset.id)
        }
        return true
    }

    private mutating func placedAsset(for image: MarkdownImage) -> Asset {
        var asset: Asset
        if let existingAsset = indexedAsset(matching: image.path) {
            asset = existingAsset
            if asset.caption == nil {
                asset.caption = image.caption
            }
            if asset.credit == nil {
                asset.credit = image.credit
            }
            if let role = image.role {
                asset.role = role
            }
        } else if let catalogAsset = assetCatalog.asset(
            matching: image.path,
            caption: image.caption,
            role: image.role,
            credit: image.credit
        ) {
            asset = catalogAsset
        } else {
            asset = Asset(
                fileName: image.path,
                role: image.role ?? .photo,
                caption: image.caption,
                credit: image.credit,
                pixelWidth: 0,
                pixelHeight: 0
            )
        }

        asset.usage = asset.usage == .placed || asset.usage == .repeated ? .repeated : .placed
        assetsByReference[asset.fileName.normalizedAssetPath] = asset
        return asset
    }

    private func indexedAsset(matching reference: String) -> Asset? {
        for path in reference.normalizedAssetLookupPaths {
            if let exactAsset = assetsByReference[path] {
                return exactAsset
            }
        }

        let normalizedReference = reference.normalizedAssetReference
        return assetsByReference.values
            .filter { $0.fileName.normalizedAssetReference == normalizedReference }
            .sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
            .first
    }

    private func parseImage(_ line: String) -> MarkdownImage? {
        guard line.hasPrefix("![") else {
            return nil
        }

        let captionStart = line.index(line.startIndex, offsetBy: 2)
        guard let captionEnd = line[captionStart...].firstIndex(of: "]") else {
            return nil
        }
        let caption = String(line[captionStart..<captionEnd]).trimmed

        let markerStart = line.index(after: captionEnd)
        guard markerStart < line.endIndex else {
            return nil
        }

        let target: String
        if line[markerStart] == "(",
           line.hasSuffix(")") {
            let pathStart = line.index(after: markerStart)
            let pathEnd = line.index(before: line.endIndex)
            target = String(line[pathStart..<pathEnd]).trimmed
        } else if line[markerStart] == "[",
                  line.hasSuffix("]") {
            let labelStart = line.index(after: markerStart)
            let labelEnd = line.index(before: line.endIndex)
            let rawLabel = String(line[labelStart..<labelEnd]).trimmed
            let label = rawLabel.isEmpty ? caption : rawLabel
            guard let referenceTarget = referenceImageTargets[normalizedReferenceLabel(label)] else {
                return nil
            }
            target = referenceTarget
        } else {
            return nil
        }

        let parsedTarget = parseImageTarget(target)
        let path = parsedTarget.path

        guard !path.isEmpty else {
            return nil
        }

        return MarkdownImage(
            caption: caption.isEmpty ? nil : normalizeInlineMarkdown(caption),
            path: path,
            role: parsedTarget.role,
            credit: parsedTarget.credit,
            anchor: parsedTarget.anchor
        )
    }

    private func parseHeading(_ line: String) -> MarkdownHeading? {
        var level = 0
        for character in line {
            if character == "#" {
                level += 1
                continue
            }
            break
        }

        guard (1...6).contains(level) else {
            return nil
        }

        let markerEnd = line.index(line.startIndex, offsetBy: level)
        guard markerEnd < line.endIndex, line[markerEnd] == " " else {
            return nil
        }

        let text = normalizeInlineMarkdown(String(line[line.index(after: markerEnd)...]).trimmed)
        guard !text.isEmpty else {
            return nil
        }

        return MarkdownHeading(level: level, text: text)
    }

    private func parseSetextHeading(line: String, nextLine: String?) -> MarkdownHeading? {
        guard let nextLine,
              !line.isEmpty,
              !line.hasPrefix("> "),
              !isTableLine(line),
              parseImage(line) == nil,
              parseListItem(line) == nil else {
            return nil
        }

        let compactUnderline = nextLine.replacingOccurrences(of: " ", with: "")
        guard compactUnderline.count >= 3 else {
            return nil
        }

        let level: Int
        if compactUnderline.allSatisfy({ $0 == "=" }) {
            level = 1
        } else if compactUnderline.allSatisfy({ $0 == "-" }) {
            level = 2
        } else {
            return nil
        }

        let text = normalizeInlineMarkdown(line)
        guard !text.isEmpty else {
            return nil
        }
        return MarkdownHeading(level: level, text: text)
    }

    private func parseListItem(_ line: String) -> String? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            let text = normalizeInlineMarkdown(String(line.dropFirst(2)).trimmed)
            return text.isEmpty ? nil : text
        }

        var digitCount = 0
        for character in line {
            if character.isNumber {
                digitCount += 1
                continue
            }
            break
        }

        guard digitCount > 0 else {
            return nil
        }

        let markerIndex = line.index(line.startIndex, offsetBy: digitCount)
        guard markerIndex < line.endIndex, line[markerIndex] == "." || line[markerIndex] == ")" else {
            return nil
        }

        let textStart = line.index(after: markerIndex)
        guard textStart < line.endIndex, line[textStart] == " " else {
            return nil
        }

        let marker = String(line[..<textStart]).trimmed
        let text = normalizeInlineMarkdown(String(line[line.index(after: textStart)...]).trimmed)
        guard !text.isEmpty else {
            return nil
        }
        return "\(marker) \(text)"
    }

    private func isNonContentLine(_ line: String) -> Bool {
        let compactLine = line.replacingOccurrences(of: " ", with: "")
        guard compactLine.count >= 3 else {
            return false
        }

        return compactLine.allSatisfy { $0 == "-" }
            || compactLine.allSatisfy { $0 == "*" }
            || compactLine.allSatisfy { $0 == "_" }
    }

    private mutating func shouldSkipHTMLCommentLine(_ line: String) -> Bool {
        if isInsideHTMLComment {
            if line.contains("-->") {
                isInsideHTMLComment = false
            }
            return true
        }

        guard let start = line.range(of: "<!--") else {
            return false
        }

        let afterStart = line[start.upperBound...]
        if !afterStart.contains("-->") {
            isInsideHTMLComment = true
        }
        return true
    }

    private func isTableLine(_ line: String) -> Bool {
        line.hasPrefix("|") && line.hasSuffix("|") && line.dropFirst().dropLast().contains("|")
    }

    private func isTableSeparatorLine(_ line: String) -> Bool {
        let normalized = line
            .replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespaces)
        return normalized.isEmpty
    }

    private func tableCells(_ line: String) -> [String] {
        var trimmedLine = line.trimmed
        if trimmedLine.hasPrefix("|") {
            trimmedLine.removeFirst()
        }
        if trimmedLine.hasSuffix("|") {
            trimmedLine.removeLast()
        }

        return trimmedLine
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { normalizeInlineMarkdown(String($0).trimmed) }
    }

    private func normalizeInlineMarkdown(_ text: String) -> String {
        var result = replacingMarkdownLinks(in: text)
        result = strippingPairedInlineDelimiter("**", from: result)
        result = strippingPairedInlineDelimiter("__", from: result)
        result = strippingPairedInlineDelimiter("*", from: result)
        result = strippingPairedInlineDelimiter("_", from: result)
        result = strippingPairedInlineDelimiter("`", from: result)
        result = result.replacingOccurrences(of: "\\*", with: "*")
        result = result.replacingOccurrences(of: "\\_", with: "_")
        result = result.replacingOccurrences(of: "\\`", with: "`")
        result = result.replacingOccurrences(of: "\\[", with: "[")
        result = result.replacingOccurrences(of: "\\]", with: "]")
        return result
    }

    private func replacingMarkdownLinks(in text: String) -> String {
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

    private func strippingPairedInlineDelimiter(_ delimiter: String, from text: String) -> String {
        var result = text

        while let opening = firstDelimiterIndex(in: result, delimiter: delimiter, startingAt: result.startIndex, kind: .opening),
              let closing = firstDelimiterIndex(
                in: result,
                delimiter: delimiter,
                startingAt: result.index(opening, offsetBy: delimiter.count),
                kind: .closing
              ) {
            let closingEnd = result.index(closing, offsetBy: delimiter.count)
            result.removeSubrange(closing..<closingEnd)

            let openingEnd = result.index(opening, offsetBy: delimiter.count)
            result.removeSubrange(opening..<openingEnd)
        }

        return result
    }

    private func firstDelimiterIndex(
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

    private func isValidInlineDelimiter(
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

    private func isEscapedDelimiter(at index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else {
            return false
        }

        let previousIndex = text.index(before: index)
        return text[previousIndex] == "\\"
    }

    private func boundaryBefore(_ index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else {
            return true
        }

        let previousCharacter = text[text.index(before: index)]
        return isInlineDelimiterBoundary(previousCharacter)
    }

    private func isInlineDelimiterBoundary(_ character: Character) -> Bool {
        if character.isWhitespace {
            return true
        }

        let punctuation = CharacterSet.punctuationCharacters.union(
            CharacterSet(charactersIn: "，。、；：！？（）【】《》「」『』“”‘’、")
        )
        return character.unicodeScalars.allSatisfy { punctuation.contains($0) }
    }

    private func extractFrontMatter(from lines: inout [String]) -> FrontMatter {
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else {
            return FrontMatter()
        }

        var values: [String: String] = [:]
        var endIndex: Int?

        for index in 1..<lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "---" {
                endIndex = index
                break
            }

            guard let separator = line.firstIndex(of: ":") else {
                continue
            }

            let key = String(line[..<separator]).trimmed.lowercased()
            let value = String(line[line.index(after: separator)...]).trimmed.trimmedQuotes
            values[key] = value
        }

        if let endIndex {
            lines.removeSubrange(0...endIndex)
        }

        return FrontMatter(
            title: values["title"],
            subtitle: values["subtitle"],
            author: values["author"],
            publisher: values["publisher"],
            isbn: values["isbn"],
            series: values["series"],
            keywords: parseKeywords(values["keywords"] ?? values["tags"]),
            pageSetup: parsePageSetup(values)
        )
    }

    private func parseKeywords(_ value: String?) -> [String] {
        guard let value else {
            return []
        }

        return value
            .components(separatedBy: CharacterSet(charactersIn: ",;，；"))
            .map(\.trimmed)
            .filter { !$0.isEmpty }
    }

    private func parsePageSetup(_ values: [String: String]) -> PageSetup? {
        let hasPageSetupValues = values["columns"] != nil
            || values["page_width_mm"] != nil
            || values["page_height_mm"] != nil
            || values["page"] != nil
            || values["margins"] != nil
            || values["margin_top_mm"] != nil
            || values["margin_right_mm"] != nil
            || values["margin_bottom_mm"] != nil
            || values["margin_left_mm"] != nil
            || values["gutter_mm"] != nil
            || values["baseline_grid_pt"] != nil
            || values["bleed_mm"] != nil
        guard hasPageSetupValues else {
            return nil
        }

        var setup = PageSetup.scienceBookDefault
        if let columns = values["columns"].flatMap(Int.init), columns > 0 {
            setup.columns = min(columns, 4)
        }

        let pagePair = parsePageSize(values)
        if let pagePair {
            setup.pageSize = PageSize(
                width: pagePair.widthMM.mmToPoints,
                height: pagePair.heightMM.mmToPoints,
                label: "\(formatMM(pagePair.widthMM))mm x \(formatMM(pagePair.heightMM))mm"
            )
        }

        if let margins = parseMargins(values) {
            setup.margins = margins
        }

        if let gutterMM = values["gutter_mm"].flatMap(Double.init), gutterMM >= 0 {
            setup.gutter = gutterMM.mmToPoints
        }

        if let baselineGrid = values["baseline_grid_pt"].flatMap(Double.init), baselineGrid > 0 {
            setup.baselineGrid = baselineGrid
        }

        if let bleedMM = values["bleed_mm"].flatMap(Double.init), bleedMM >= 0 {
            setup.bleedMM = bleedMM
        }

        return setup
    }

    private func parseMargins(_ values: [String: String]) -> PageMargins? {
        let defaultMargins = PageSetup.scienceBookDefault.margins
        var top = values["margin_top_mm"].flatMap(Double.init)?.mmToPoints ?? defaultMargins.top
        var right = values["margin_right_mm"].flatMap(Double.init)?.mmToPoints ?? defaultMargins.right
        var bottom = values["margin_bottom_mm"].flatMap(Double.init)?.mmToPoints ?? defaultMargins.bottom
        var left = values["margin_left_mm"].flatMap(Double.init)?.mmToPoints ?? defaultMargins.left

        if let shorthand = values["margins"] {
            let parts = shorthand
                .lowercased()
                .replacingOccurrences(of: "mm", with: "")
                .replacingOccurrences(of: ",", with: " ")
                .split(separator: " ")
                .compactMap { Double($0) }

            switch parts.count {
            case 1:
                top = parts[0].mmToPoints
                right = top
                bottom = top
                left = top
            case 2:
                top = parts[0].mmToPoints
                bottom = top
                right = parts[1].mmToPoints
                left = right
            case 4:
                top = parts[0].mmToPoints
                right = parts[1].mmToPoints
                bottom = parts[2].mmToPoints
                left = parts[3].mmToPoints
            default:
                break
            }
        }

        guard top >= 0, right >= 0, bottom >= 0, left >= 0 else {
            return nil
        }

        return PageMargins(top: top, right: right, bottom: bottom, left: left)
    }

    private func parsePageSize(_ values: [String: String]) -> (widthMM: Double, heightMM: Double)? {
        if let width = values["page_width_mm"].flatMap(Double.init),
           let height = values["page_height_mm"].flatMap(Double.init),
           width > 0,
           height > 0 {
            return (width, height)
        }

        guard let page = values["page"]?.lowercased() else {
            return nil
        }

        let normalized = page
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "mm", with: "")
            .replacingOccurrences(of: "×", with: "x")
        let parts = normalized.split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else {
            return nil
        }
        return (parts[0], parts[1])
    }

    private func formatMM(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }

    private func parseImageTarget(_ target: String) -> ParsedImageTarget {
        guard let imageTarget = parsedImageTargetMetadata(target) else {
            return ParsedImageTarget(path: normalizedImagePath(target), role: nil, credit: nil, anchor: nil)
        }

        let values = parseMetadata(imageTarget.metadata)
        let role = parsedRole(values)
        let credit = parsedCredit(values)
        let anchor = parsedImageAnchor(values)
        return ParsedImageTarget(path: imageTarget.path, role: role, credit: credit, anchor: anchor)
    }

    private func parsedImageTargetMetadata(_ target: String) -> (path: String, metadata: String)? {
        let trimmedTarget = target.trimmed
        guard let quoteEnd = trimmedTarget.indices.last else {
            return nil
        }

        let quote = trimmedTarget[quoteEnd]
        guard quote == "\"" || quote == "'" else {
            return nil
        }

        var index = quoteEnd
        while index > trimmedTarget.startIndex {
            index = trimmedTarget.index(before: index)
            if trimmedTarget[index] == quote, !isEscapedDelimiter(at: index, in: trimmedTarget) {
                let path = String(trimmedTarget[..<index]).trimmed
                let metadataStart = trimmedTarget.index(after: index)
                let metadata = String(trimmedTarget[metadataStart..<quoteEnd])
                guard !path.isEmpty else {
                    return nil
                }
                return (normalizedImagePath(path), metadata)
            }
        }

        return nil
    }

    private func normalizedImagePath(_ path: String) -> String {
        var path = path.trimmed
        if path.hasPrefix("<"), path.hasSuffix(">"), path.count >= 2 {
            path.removeFirst()
            path.removeLast()
            path = path.trimmed
        }
        return path
    }

    private func collectReferenceImageTargets(from lines: [String]) -> [String: String] {
        lines.reduce(into: [String: String]()) { targets, rawLine in
            guard let definition = parseReferenceDefinition(rawLine.trimmingCharacters(in: .whitespaces)) else {
                return
            }

            targets[definition.label] = definition.target
        }
    }

    private func parseReferenceDefinition(_ line: String) -> (label: String, target: String)? {
        guard line.hasPrefix("["),
              let labelEnd = line.firstIndex(of: "]") else {
            return nil
        }

        let colonIndex = line.index(after: labelEnd)
        guard colonIndex < line.endIndex, line[colonIndex] == ":" else {
            return nil
        }

        let labelStart = line.index(after: line.startIndex)
        let label = normalizedReferenceLabel(String(line[labelStart..<labelEnd]))
        let targetStart = line.index(after: colonIndex)
        let target = String(line[targetStart...]).trimmed
        guard !label.isEmpty, !target.isEmpty else {
            return nil
        }
        return (label, target)
    }

    private func normalizedReferenceLabel(_ label: String) -> String {
        label
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }

    private func parseAdmonitionStart(_ line: String) -> String? {
        guard line.hasPrefix("[!"), let closing = line.firstIndex(of: "]") else {
            return nil
        }

        let markerStart = line.index(line.startIndex, offsetBy: 2)
        let marker = String(line[markerStart..<closing]).uppercased()
        let title = normalizeInlineMarkdown(String(line[line.index(after: closing)...]).trimmed)
        let label = admonitionLabel(marker)
        guard !label.isEmpty else {
            return nil
        }

        return title.isEmpty ? label : "\(label)：\(title)"
    }

    private func admonitionLabel(_ marker: String) -> String {
        switch marker {
        case "NOTE":
            return "知识点"
        case "TIP":
            return "提示"
        case "INFO":
            return "背景"
        case "EXAMPLE":
            return "例子"
        case "WARNING", "CAUTION":
            return "注意"
        default:
            return marker
        }
    }

    private func parsedRole(_ values: [String: String]) -> AssetRole? {
        if let role = values["role"].flatMap({ AssetRole(rawValue: $0) }) {
            return role
        }

        let placement = values["placement"] ?? values["span"]
        if placement == "wide" || placement == "full" || placement == "full-width" {
            return .hero
        }
        if placement == "spread" || placement == "cross-page" {
            return .spread
        }

        return nil
    }

    private func parsedCredit(_ values: [String: String]) -> String? {
        values["credit"] ?? values["source"] ?? values["版权"] ?? values["来源"]
    }

    private func parsedImageAnchor(_ values: [String: String]) -> MarkdownImageAnchor? {
        let explicitAnchor = values["anchor"] ?? values["attach"] ?? values["anchored"]
        if let explicitAnchor, isPreviousParagraphAnchor(explicitAnchor) {
            return .previousParagraph
        }

        if let placement = values["placement"], isPreviousParagraphAnchor(placement) {
            return .previousParagraph
        }

        return nil
    }

    private func isPreviousParagraphAnchor(_ value: String) -> Bool {
        switch value.lowercased() {
        case "previous", "previous-paragraph", "paragraph", "inline", "anchor", "anchored":
            return true
        default:
            return false
        }
    }

    private func parseMetadata(_ metadata: String) -> [String: String] {
        metadata
            .components(separatedBy: CharacterSet(charactersIn: ";,"))
            .reduce(into: [String: String]()) { result, item in
                guard let separator = item.firstIndex(of: "=") else {
                    return
                }
                let key = String(item[..<separator]).trimmed.lowercased()
                let value = String(item[item.index(after: separator)...]).trimmed.trimmedQuotes
                if !key.isEmpty, !value.isEmpty {
                    result[key] = value
                }
            }
    }
}

private struct MarkdownImage {
    var caption: String?
    var path: String
    var role: AssetRole?
    var credit: String?
    var anchor: MarkdownImageAnchor?
}

private enum MarkdownImageAnchor {
    case previousParagraph
}

private enum InlineDelimiterKind {
    case opening
    case closing
}

private struct MarkdownHeading {
    var level: Int
    var text: String
}

private struct FrontMatter {
    var title: String?
    var subtitle: String?
    var author: String?
    var publisher: String?
    var isbn: String?
    var series: String?
    var keywords: [String] = []
    var pageSetup: PageSetup?
}

private struct ParsedImageTarget {
    var path: String
    var role: AssetRole?
    var credit: String?
    var anchor: MarkdownImageAnchor?
}

private extension String {
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

private extension Double {
    var mmToPoints: Double {
        self / 25.4 * 72
    }
}
