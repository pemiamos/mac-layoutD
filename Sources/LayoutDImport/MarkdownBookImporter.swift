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

struct MarkdownParser {
    let markdown: String
    let assetCatalog: AssetCatalog
    let defaultAuthor: String
    let fallbackTitle: String

    var title: String?
    var subtitle: String?
    var author: String
    var publisher: String?
    var isbn: String?
    var series: String?
    var keywords: [String] = []
    var pageSetup: PageSetup = .scienceBookDefault
    var sections: [BookSection] = []
    // 空字符串 = 无显式章节标题（角色标签书稿靠正文里的「一级标题/章名」段落本身当标题，
    // 不需要 section 再画一次）。只有真遇到 Markdown `#`/`##` 标题时才会被赋成实际文字
    // （见下方两处 currentSectionTitle = headingText）。LayoutEngine.addSectionTitle 和
    // Story 的 TOC 收录都已对空标题短路，不会画出/收入一个空壳「标题」。
    var currentSectionTitle = ""
    var currentParagraphs: [Paragraph] = []
    var paragraphBuffer: [String] = []
    var calloutBuffer: [String] = []
    var tableBuffer: [String] = []
    var assetsByReference: [String: Asset] = [:]
    var referenceImageTargets: [String: String] = [:]
    var isInsideHTMLComment = false
    var footnoteDefinitions: [String: String] = [:]
    var sideNoteBuffer: [String] = []
    var nextFootnoteNumber = 1
    var footnoteMap: [String: Int] = [:]
    var pendingContentRole: ContentRole?

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
        lines = consumingSubsequentFrontMatter(in: lines)
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

            if let role = ContentRole.tag(in: line) {
                flushAllBuffers()
                pendingContentRole = role
                continue
            }
            if ContentRole.shouldDiscard(line) {
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
                let headingText = normalizeInlineMarkdown(heading.text)
                if heading.level == 1 {
                    flushSection()
                    if title == nil {
                        title = headingText
                    }
                    currentSectionTitle = headingText
                } else {
                    currentParagraphs.append(
                        makeParagraph(
                            kind: .heading(level: heading.level),
                            markdown: heading.text,
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
                let headingText = normalizeInlineMarkdown(heading.text)
                if heading.level == 1 {
                    flushSection()
                    if title == nil {
                        title = headingText
                    }
                    currentSectionTitle = headingText
                } else {
                    currentParagraphs.append(
                        makeParagraph(
                            kind: .heading(level: heading.level),
                            markdown: heading.text,
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
                    makeParagraph(
                        kind: .listItem,
                        markdown: listItem,
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

}
