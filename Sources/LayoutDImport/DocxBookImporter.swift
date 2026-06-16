import AppKit
import Foundation
import LayoutDCore

public struct DocxBookImporter: Sendable {
    public init() {}

    public func importDocument(docxURL: URL, assetDirectoryURL: URL? = nil) throws -> BookProject {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.officeOpenXML
        ]
        var documentAttributes: NSDictionary?
        let attrString = try NSAttributedString(url: docxURL, options: options, documentAttributes: &documentAttributes)
        
        var title = docxURL.deletingPathExtension().lastPathComponent
        if let docAttrs = documentAttributes as? [NSAttributedString.DocumentAttributeKey: Any],
           let docTitle = docAttrs[.title] as? String, !docTitle.isEmpty {
            title = docTitle
        }
        
        return importAttributedString(
            attrString,
            title: title,
            baseDirectoryURL: docxURL.deletingLastPathComponent(),
            assetDirectoryURL: assetDirectoryURL
        )
    }

    public func importAttributedString(
        _ attrString: NSAttributedString,
        title: String,
        baseDirectoryURL: URL,
        assetDirectoryURL: URL? = nil
    ) -> BookProject {
        let parser = NSAttributedStringParser()
        let result = parser.parse(attrString, baseDirectory: baseDirectoryURL)
        
        var sections: [BookSection] = []
        var currentSectionTitle = title
        var currentStories: [Story] = []
        var currentParagraphs: [Paragraph] = []
        
        var nextStoryTitle = "正文"
        
        for parsedPara in result.paragraphs {
            if parsedPara.isHeading1 {
                if !currentParagraphs.isEmpty || !currentStories.isEmpty {
                    let story = Story(title: nextStoryTitle, paragraphs: currentParagraphs)
                    currentStories.append(story)
                    sections.append(BookSection(title: currentSectionTitle, stories: currentStories))
                    currentParagraphs = []
                    currentStories = []
                }
                currentSectionTitle = parsedPara.text
                nextStoryTitle = "正文"
            } else if parsedPara.isHeading2 {
                if !currentParagraphs.isEmpty {
                    let story = Story(title: nextStoryTitle, paragraphs: currentParagraphs)
                    currentStories.append(story)
                    currentParagraphs = []
                }
                nextStoryTitle = parsedPara.text
            } else {
                currentParagraphs.append(parsedPara.paragraph)
            }
        }
        
        if !currentParagraphs.isEmpty || !currentStories.isEmpty || sections.isEmpty {
            let story = Story(title: nextStoryTitle, paragraphs: currentParagraphs)
            currentStories.append(story)
            sections.append(BookSection(title: currentSectionTitle, stories: currentStories))
        }
        
        var assets = result.assets
        
        if let assetDirectoryURL {
            let scanner = AssetScanner()
            if let scannedAssets = try? scanner.scan(directory: assetDirectoryURL) {
                for scanned in scannedAssets {
                    if !assets.contains(where: { $0.fileName == scanned.fileName }) {
                        assets.append(scanned)
                    }
                }
            }
        }
        
        return BookProject(
            metadata: ProjectMetadata(title: title, author: NSUserName()),
            pageSetup: PageSetup.scienceBookDefault,
            sections: sections,
            assets: assets
        )
    }
}

private final class NSAttributedStringParser {
    struct ParsedParagraph {
        var isHeading1: Bool
        var isHeading2: Bool
        var text: String
        var paragraph: Paragraph
    }
    
    var paragraphs: [ParsedParagraph] = []
    var assets: [Asset] = []
    
    func parse(_ attrString: NSAttributedString, baseDirectory: URL) -> (paragraphs: [ParsedParagraph], assets: [Asset]) {
        let string = attrString.string
        let length = attrString.length
        var index = 0
        
        while index < length {
            let range = (string as NSString).paragraphRange(for: NSRange(location: index, length: 0))
            parseParagraphRange(range, in: attrString, baseDirectory: baseDirectory)
            index = range.location + range.length
        }
        
        return (paragraphs, assets)
    }
    
    private func parseParagraphRange(_ range: NSRange, in attrString: NSAttributedString, baseDirectory: URL) {
        let substring = attrString.attributedSubstring(from: range)
        let rawText = substring.string
        let cleanText = rawText.replacingOccurrences(of: "\u{FFFC}", with: "")
        let text = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || hasAttachment(in: substring) else {
            return
        }
        
        var imageAssetIds: [UUID] = []
        substring.enumerateAttribute(.attachment, in: NSRange(location: 0, length: substring.length), options: []) { value, runRange, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            
            let fileWrapper = attachment.fileWrapper
            let imageData: Data?
            let fileName: String
            
            if let fw = fileWrapper, fw.isRegularFile, let data = fw.regularFileContents {
                imageData = data
                fileName = fw.preferredFilename ?? "image_\(UUID().uuidString.prefix(8)).png"
            } else if let image = attachment.image {
                if let tiffData = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData) {
                    imageData = bitmap.representation(using: .png, properties: [:])
                } else {
                    imageData = nil
                }
                fileName = "image_\(UUID().uuidString.prefix(8)).png"
            } else {
                imageData = nil
                fileName = ""
            }
            
            guard let data = imageData, !fileName.isEmpty else { return }
            
            let tempAssetsDir = baseDirectory.appendingPathComponent(".docx_assets")
            try? FileManager.default.createDirectory(at: tempAssetsDir, withIntermediateDirectories: true)
            let fileURL = tempAssetsDir.appendingPathComponent(fileName)
            try? data.write(to: fileURL)
            
            let id = UUID()
            let asset = Asset(
                id: id,
                fileName: ".docx_assets/\(fileName)",
                sourcePath: fileURL.path,
                role: .diagram,
                caption: nil,
                credit: nil,
                pixelWidth: 0,
                pixelHeight: 0
            )
            
            var updatedAsset = asset
            if let imageRep = NSBitmapImageRep(data: data) {
                updatedAsset.pixelWidth = imageRep.pixelsWide
                updatedAsset.pixelHeight = imageRep.pixelsHigh
            }
            self.assets.append(updatedAsset)
            imageAssetIds.append(id)
        }
        
        if text.isEmpty && !imageAssetIds.isEmpty {
            for id in imageAssetIds {
                paragraphs.append(ParsedParagraph(
                    isHeading1: false,
                    isHeading2: false,
                    text: "",
                    paragraph: Paragraph(kind: .figure(assetId: id), text: "", styleId: StyleID.body.rawValue)
                ))
            }
            return
        }
        
        var font: NSFont?
        substring.enumerateAttribute(.font, in: NSRange(location: 0, length: substring.length), options: []) { value, runRange, stop in
            if let f = value as? NSFont {
                font = f
                stop.pointee = true
            }
        }
        
        var isHeading1 = false
        var isHeading2 = false
        
        if let f = font {
            let size = f.pointSize
            let isBold = f.fontDescriptor.symbolicTraits.contains(.bold) || f.fontName.lowercased().contains("bold") || f.fontName.lowercased().contains("medium")
            if size >= 18.0 && isBold {
                isHeading1 = true
            } else if size >= 13.5 && isBold {
                isHeading2 = true
            }
        }
        
        let styleId = isHeading1 ? StyleID.heading1.rawValue : (isHeading2 ? StyleID.heading2.rawValue : StyleID.body.rawValue)
        let kind: ParagraphKind = isHeading1 ? .heading(level: 1) : (isHeading2 ? .heading(level: 2) : .body)
        
        let paragraph = Paragraph(
            kind: kind,
            text: text,
            styleId: styleId,
            anchoredAssetIds: imageAssetIds
        )
        
        paragraphs.append(ParsedParagraph(
            isHeading1: isHeading1,
            isHeading2: isHeading2,
            text: text,
            paragraph: paragraph
        ))
    }
    
    private func hasAttachment(in substring: NSAttributedString) -> Bool {
        var hasAttachment = false
        substring.enumerateAttribute(.attachment, in: NSRange(location: 0, length: substring.length), options: []) { value, _, stop in
            if value is NSTextAttachment {
                hasAttachment = true
                stop.pointee = true
            }
        }
        return hasAttachment
    }
}
