import Foundation
import ImageIO
import LayoutDCore

public struct AssetScanner {
    public init() {}

    public func scan(directory: URL) throws -> [Asset] {
        let fileManager = FileManager.default
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
            assets.append(readAsset(url: fileURL, root: directory))
        }
        return assets.sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
    }

    private func readAsset(url: URL, root: URL) -> Asset {
        let relativePath = url.path.replacingOccurrences(of: root.path + "/", with: "")
        let properties = imageProperties(url: url)
        let pixelWidth = properties[kCGImagePropertyPixelWidth as String] as? Int ?? 0
        let pixelHeight = properties[kCGImagePropertyPixelHeight as String] as? Int ?? 0
        let dpiWidth = properties[kCGImagePropertyDPIWidth as String] as? Double
        let dpiHeight = properties[kCGImagePropertyDPIHeight as String] as? Double

        return Asset(
            fileName: relativePath,
            sourcePath: url.path,
            role: inferRole(from: url.lastPathComponent),
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

    private let supportedImageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "tif", "tiff", "heic", "webp"
    ]
}
