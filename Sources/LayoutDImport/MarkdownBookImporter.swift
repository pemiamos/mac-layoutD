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

    init(markdown: String, assetCatalog: AssetCatalog, defaultAuthor: String, fallbackTitle: String) {
        self.markdown = markdown
        self.assetCatalog = assetCatalog
        self.defaultAuthor = defaultAuthor
        self.fallbackTitle = fallbackTitle
        self.author = defaultAuthor
        self.assetsByReference = Dictionary(
            uniqueKeysWithValues: assetCatalog.assets.map { ($0.fileName.normalizedAssetReference, $0) }
        )
    }

    mutating func parse() -> BookProject {
        var lines = markdown.components(separatedBy: .newlines)
        let frontMatter = extractFrontMatter(from: &lines)
        title = frontMatter.title
        subtitle = frontMatter.subtitle
        author = frontMatter.author ?? defaultAuthor
        publisher = frontMatter.publisher
        isbn = frontMatter.isbn
        series = frontMatter.series
        keywords = frontMatter.keywords
        pageSetup = frontMatter.pageSetup ?? .scienceBookDefault

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraphBuffer()
                flushCalloutBuffer()
                flushTableBuffer()
                continue
            }

            if isNonContentLine(line) {
                flushParagraphBuffer()
                flushCalloutBuffer()
                flushTableBuffer()
                continue
            }

            if isTableLine(line) {
                flushParagraphBuffer()
                flushCalloutBuffer()
                tableBuffer.append(line)
                continue
            }

            if let image = parseImage(line) {
                flushParagraphBuffer()
                flushCalloutBuffer()
                flushTableBuffer()
                addFigure(image)
                continue
            }

            if line.hasPrefix("# ") {
                flushParagraphBuffer()
                flushCalloutBuffer()
                flushTableBuffer()
                flushSection()
                let heading = String(line.dropFirst(2)).trimmed
                if title == nil {
                    title = heading
                }
                currentSectionTitle = heading
                continue
            }

            if line.hasPrefix("## ") {
                flushParagraphBuffer()
                flushCalloutBuffer()
                flushTableBuffer()
                currentParagraphs.append(
                    Paragraph(
                        kind: .heading(level: 2),
                        text: String(line.dropFirst(3)).trimmed,
                        styleId: StyleID.heading2.rawValue
                    )
                )
                continue
            }

            if line.hasPrefix("> ") {
                flushParagraphBuffer()
                flushTableBuffer()
                addQuoteLine(String(line.dropFirst(2)).trimmed)
                continue
            }

            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraphBuffer()
                flushCalloutBuffer()
                flushTableBuffer()
                currentParagraphs.append(
                    Paragraph(
                        kind: .listItem,
                        text: String(line.dropFirst(2)).trimmed,
                        styleId: StyleID.body.rawValue
                    )
                )
                continue
            }

            flushCalloutBuffer()
            flushTableBuffer()
            paragraphBuffer.append(line)
        }

        flushParagraphBuffer()
        flushCalloutBuffer()
        flushTableBuffer()
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
        let text = paragraphBuffer.joined(separator: " ")
        currentParagraphs.append(Paragraph(kind: .body, text: text, styleId: StyleID.body.rawValue))
        paragraphBuffer.removeAll(keepingCapacity: true)
    }

    private mutating func flushCalloutBuffer() {
        guard !calloutBuffer.isEmpty else {
            return
        }
        currentParagraphs.append(
            Paragraph(kind: .callout, text: calloutBuffer.joined(separator: " "), styleId: StyleID.callout.rawValue)
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
                Paragraph(kind: .table, text: text, styleId: StyleID.body.rawValue)
            )
        }

        tableBuffer.removeAll(keepingCapacity: true)
    }

    private mutating func flushSection() {
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
        if let calloutStart = parseAdmonitionStart(line) {
            flushCalloutBuffer()
            calloutBuffer.append(calloutStart)
            return
        }

        if !calloutBuffer.isEmpty {
            calloutBuffer.append(line)
            return
        }

        currentParagraphs.append(
            Paragraph(
                kind: .quote,
                text: line,
                styleId: StyleID.callout.rawValue
            )
        )
    }

    private mutating func addFigure(_ image: MarkdownImage) {
        var asset: Asset
        if let catalogAsset = assetCatalog.asset(
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

        asset.usage = .placed
        assetsByReference[asset.fileName.normalizedAssetReference] = asset
        currentParagraphs.append(
            Paragraph(
                kind: .figure(assetId: asset.id),
                text: image.caption ?? asset.fileName,
                styleId: StyleID.caption.rawValue
            )
        )
    }

    private func parseImage(_ line: String) -> MarkdownImage? {
        guard line.hasPrefix("!["),
              let captionEnd = line.range(of: "]("),
              line.hasSuffix(")") else {
            return nil
        }

        let captionStart = line.index(line.startIndex, offsetBy: 2)
        let caption = String(line[captionStart..<captionEnd.lowerBound]).trimmed
        let pathStart = captionEnd.upperBound
        let pathEnd = line.index(before: line.endIndex)
        let target = String(line[pathStart..<pathEnd]).trimmed
        let parsedTarget = parseImageTarget(target)
        let path = parsedTarget.path

        guard !path.isEmpty else {
            return nil
        }

        return MarkdownImage(
            caption: caption.isEmpty ? nil : caption,
            path: path,
            role: parsedTarget.role,
            credit: parsedTarget.credit
        )
    }

    private func isNonContentLine(_ line: String) -> Bool {
        if line.hasPrefix("<!--"), line.hasSuffix("-->") {
            return true
        }

        let compactLine = line.replacingOccurrences(of: " ", with: "")
        guard compactLine.count >= 3 else {
            return false
        }

        return compactLine.allSatisfy { $0 == "-" }
            || compactLine.allSatisfy { $0 == "*" }
            || compactLine.allSatisfy { $0 == "_" }
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
            .map { String($0).trimmed }
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
        guard let quoteStart = target.firstIndex(of: "\""),
              let quoteEnd = target.lastIndex(of: "\""),
              quoteStart != quoteEnd else {
            return ParsedImageTarget(path: target.trimmed, role: nil, credit: nil)
        }

        let path = String(target[..<quoteStart]).trimmed
        let metadata = String(target[target.index(after: quoteStart)..<quoteEnd])
        let values = parseMetadata(metadata)
        let role = parsedRole(values)
        let credit = values["credit"]
        return ParsedImageTarget(path: path, role: role, credit: credit)
    }

    private func parseAdmonitionStart(_ line: String) -> String? {
        guard line.hasPrefix("[!"), let closing = line.firstIndex(of: "]") else {
            return nil
        }

        let markerStart = line.index(line.startIndex, offsetBy: 2)
        let marker = String(line[markerStart..<closing]).uppercased()
        let title = String(line[line.index(after: closing)...]).trimmed
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

        return nil
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
