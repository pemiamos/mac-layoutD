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
        self.assetsByReference = Dictionary(
            uniqueKeysWithValues: assetCatalog.assets.map { ($0.fileName.normalizedAssetReference, $0) }
        )
    }

    mutating func parse() -> BookProject {
        for rawLine in markdown.components(separatedBy: .newlines) {
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
            metadata: ProjectMetadata(title: projectTitle, author: defaultAuthor),
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
        if let catalogAsset = assetCatalog.asset(matching: image.path, caption: image.caption) {
            asset = catalogAsset
        } else {
            asset = Asset(
                fileName: image.path,
                role: .photo,
                caption: image.caption,
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
        let path = String(line[pathStart..<pathEnd]).trimmed

        guard !path.isEmpty else {
            return nil
        }

        return MarkdownImage(caption: caption.isEmpty ? nil : caption, path: path)
    }
}

private struct MarkdownImage {
    var caption: String?
    var path: String
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
