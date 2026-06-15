import Foundation
import ImageIO
import LayoutDCore

public struct AssetScanner {
    public init() {}

    public func scan(directory: URL) throws -> [Asset] {
        let fileManager = FileManager.default
        let manifest = try loadManifest(directory: directory)
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var assets: [Asset] = []
        for case let fileURL as URL in enumerator {
            guard supportedImageExtensions.contains(fileURL.pathExtension.lowercased()) else {
                continue
            }
            assets.append(readAsset(url: fileURL, root: directory, manifest: manifest))
        }
        return assets.sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
    }

    private func readAsset(url: URL, root: URL, manifest: [String: ManifestEntry]) -> Asset {
        let rootPath = root.resolvingSymlinksInPath().path
        let filePath = url.resolvingSymlinksInPath().path
        let relativePath = filePath.hasPrefix(rootPath + "/")
            ? String(filePath.dropFirst(rootPath.count + 1))
            : url.lastPathComponent
        let properties = imageProperties(url: url)
        let pixelWidth = properties[kCGImagePropertyPixelWidth as String] as? Int ?? 0
        let pixelHeight = properties[kCGImagePropertyPixelHeight as String] as? Int ?? 0
        let dpiWidth = properties[kCGImagePropertyDPIWidth as String] as? Double
        let dpiHeight = properties[kCGImagePropertyDPIHeight as String] as? Double
        let entry = manifest[relativePath.normalizedAssetReference]

        return Asset(
            fileName: relativePath,
            sourcePath: url.path,
            role: entry?.role ?? inferRole(from: url.lastPathComponent),
            caption: entry?.caption,
            credit: entry?.credit,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            dpi: averageDPI(width: dpiWidth, height: dpiHeight)
        )
    }

    private func imageProperties(url: URL) -> [String: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return [:]
        }
        return properties
    }

    private func averageDPI(width: Double?, height: Double?) -> Double? {
        switch (width, height) {
        case let (width?, height?):
            return (width + height) / 2
        case let (width?, nil):
            return width
        case let (nil, height?):
            return height
        case (nil, nil):
            return nil
        }
    }

    private func inferRole(from fileName: String) -> AssetRole {
        let lowered = fileName.lowercased()
        if lowered.contains("hero") || lowered.contains("cover") || lowered.contains("主图") {
            return .hero
        }
        if lowered.contains("chart") || lowered.contains("graph") || lowered.contains("图表") {
            return .chart
        }
        if lowered.contains("step") || lowered.contains("步骤") {
            return .step
        }
        if lowered.contains("compare") || lowered.contains("对比") {
            return .comparison
        }
        if lowered.contains("diagram") || lowered.contains("示意") {
            return .diagram
        }
        return .photo
    }

    private func loadManifest(directory: URL) throws -> [String: ManifestEntry] {
        let fileManager = FileManager.default
        let candidates = ["manifest.csv", "assets.csv", "images.csv"]
            .map { directory.appendingPathComponent($0) }
        guard let manifestURL = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            return [:]
        }

        let csv = try String(contentsOf: manifestURL, encoding: .utf8)
        let rows = parseCSV(csv)
        guard let header = rows.first else {
            return [:]
        }

        let normalizedHeader = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        var entries: [String: ManifestEntry] = [:]

        for row in rows.dropFirst() {
            let pairs: [(String, String)] = normalizedHeader.enumerated().compactMap { index, key in
                guard index < row.count else {
                    return nil
                }
                return (key, row[index].trimmingCharacters(in: .whitespacesAndNewlines))
            }
            let values = Dictionary(uniqueKeysWithValues: pairs)

            let fileName = values["file"] ?? values["filename"] ?? values["path"] ?? values["image"]
            guard let fileName, !fileName.isEmpty else {
                continue
            }

            let placement = values["placement"] ?? values["span"]
            let explicitRole = values["role"].flatMap { AssetRole(rawValue: $0) }
            let role = explicitRole ?? widePlacementRole(placement)
            entries[fileName.normalizedAssetReference] = ManifestEntry(
                caption: emptyToNil(values["caption"] ?? values["title"] ?? values["图注"]),
                role: role,
                credit: emptyToNil(values["credit"] ?? values["source"] ?? values["版权"] ?? values["来源"])
            )
        }

        return entries
    }

    private func parseCSV(_ csv: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var insideQuotes = false
        var iterator = csv.makeIterator()

        while let character = iterator.next() {
            if character == "\"" {
                if insideQuotes, let next = iterator.next() {
                    if next == "\"" {
                        field.append("\"")
                    } else {
                        insideQuotes = false
                        if next == "," {
                            row.append(field)
                            field = ""
                        } else if next == "\n" {
                            row.append(field)
                            rows.append(row)
                            row = []
                            field = ""
                        } else if next != "\r" {
                            field.append(next)
                        }
                    }
                } else {
                    insideQuotes.toggle()
                }
                continue
            }

            if character == ",", !insideQuotes {
                row.append(field)
                field = ""
                continue
            }

            if character == "\n", !insideQuotes {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
                continue
            }

            if character != "\r" {
                field.append(character)
            }
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows.filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    private func widePlacementRole(_ placement: String?) -> AssetRole? {
        guard let placement = placement?.lowercased() else {
            return nil
        }
        if placement == "wide" || placement == "full" || placement == "full-width" {
            return .hero
        }
        return nil
    }

    private func emptyToNil(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private let supportedImageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "tif", "tiff", "heic", "webp"
    ]
}

private struct ManifestEntry {
    var caption: String?
    var role: AssetRole?
    var credit: String?
}
