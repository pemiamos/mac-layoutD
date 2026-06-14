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
    private var sections: [BookSection] = []
    private var currentSectionTitle = "正文"
    private var currentParagraphs: [Paragraph] = []
    private var paragraphBuffer: [String] = []
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

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraphBuffer()
                continue
            }

            if let image = parseImage(line) {
                flushParagraphBuffer()
                addFigure(image)
                continue
            }

            if line.hasPrefix("# ") {
                flushParagraphBuffer()
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
                currentParagraphs.append(
                    Paragraph(
                        kind: .quote,
                        text: String(line.dropFirst(2)).trimmed,
                        styleId: StyleID.callout.rawValue
                    )
                )
                continue
            }

            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraphBuffer()
                currentParagraphs.append(
                    Paragraph(
                        kind: .listItem,
                        text: String(line.dropFirst(2)).trimmed,
                        styleId: StyleID.body.rawValue
                    )
                )
                continue
            }

            paragraphBuffer.append(line)
        }

        flushParagraphBuffer()
        flushSection()

        let projectTitle = title ?? fallbackTitle
        let projectSections = sections.isEmpty
            ? [BookSection(title: currentSectionTitle, stories: [Story(title: currentSectionTitle, paragraphs: currentParagraphs)])]
            : sections

        return BookProject(
            metadata: ProjectMetadata(title: projectTitle, subtitle: subtitle, author: author),
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

    private mutating func addFigure(_ image: MarkdownImage) {
        let asset: Asset
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
            author: values["author"]
        )
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
        let role = values["role"].flatMap { AssetRole(rawValue: $0) }
        let credit = values["credit"]
        return ParsedImageTarget(path: path, role: role, credit: credit)
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
