import Foundation
import LayoutDCore

extension MarkdownParser {
    mutating func addFigure(_ image: MarkdownImage) {
        let asset = placedAsset(for: image)
        currentParagraphs.append(
            Paragraph(
                kind: .figure(assetId: asset.id),
                text: image.caption ?? asset.fileName,
                styleId: StyleID.caption.rawValue
            )
        )
    }

    mutating func addAnchoredImage(_ image: MarkdownImage) -> Bool {
        guard let paragraphIndex = currentParagraphs.indices.last else {
            return false
        }

        let asset = placedAsset(for: image)
        if !currentParagraphs[paragraphIndex].anchoredAssetIds.contains(asset.id) {
            currentParagraphs[paragraphIndex].anchoredAssetIds.append(asset.id)
        }
        return true
    }

    mutating func placedAsset(for image: MarkdownImage) -> Asset {
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

    func indexedAsset(matching reference: String) -> Asset? {
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

    func parseImage(_ line: String) -> MarkdownImage? {
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

    func parseImageTarget(_ target: String) -> ParsedImageTarget {
        guard let imageTarget = parsedImageTargetMetadata(target) else {
            return ParsedImageTarget(path: normalizedImagePath(target), role: nil, credit: nil, anchor: nil)
        }

        let values = parseMetadata(imageTarget.metadata)
        let role = parsedRole(values)
        let credit = parsedCredit(values)
        let anchor = parsedImageAnchor(values)
        return ParsedImageTarget(path: imageTarget.path, role: role, credit: credit, anchor: anchor)
    }

    func parsedImageTargetMetadata(_ target: String) -> (path: String, metadata: String)? {
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

    func normalizedImagePath(_ path: String) -> String {
        var path = path.trimmed
        if path.hasPrefix("<"), path.hasSuffix(">"), path.count >= 2 {
            path.removeFirst()
            path.removeLast()
            path = path.trimmed
        }
        return path
    }

    func collectReferenceImageTargets(from lines: [String]) -> [String: String] {
        lines.reduce(into: [String: String]()) { targets, rawLine in
            guard let definition = parseReferenceDefinition(rawLine.trimmingCharacters(in: .whitespaces)) else {
                return
            }

            targets[definition.label] = definition.target
        }
    }

    func parseReferenceDefinition(_ line: String) -> (label: String, target: String)? {
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

    func normalizedReferenceLabel(_ label: String) -> String {
        label
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }

    func parsedRole(_ values: [String: String]) -> AssetRole? {
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

    func parsedCredit(_ values: [String: String]) -> String? {
        values["credit"] ?? values["source"] ?? values["版权"] ?? values["来源"]
    }

    func parsedImageAnchor(_ values: [String: String]) -> MarkdownImageAnchor? {
        let explicitAnchor = values["anchor"] ?? values["attach"] ?? values["anchored"]
        if let explicitAnchor, isPreviousParagraphAnchor(explicitAnchor) {
            return .previousParagraph
        }

        if let placement = values["placement"], isPreviousParagraphAnchor(placement) {
            return .previousParagraph
        }

        return nil
    }

    func isPreviousParagraphAnchor(_ value: String) -> Bool {
        switch value.lowercased() {
        case "previous", "previous-paragraph", "paragraph", "inline", "anchor", "anchored":
            return true
        default:
            return false
        }
    }

    func parseMetadata(_ metadata: String) -> [String: String] {
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

struct MarkdownImage {
    var caption: String?
    var path: String
    var role: AssetRole?
    var credit: String?
    var anchor: MarkdownImageAnchor?
}

enum MarkdownImageAnchor {
    case previousParagraph
}

struct ParsedImageTarget {
    var path: String
    var role: AssetRole?
    var credit: String?
    var anchor: MarkdownImageAnchor?
}
