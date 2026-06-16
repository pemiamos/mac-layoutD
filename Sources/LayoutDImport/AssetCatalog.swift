import Foundation
import LayoutDCore

public struct AssetCatalog: Sendable {
    public var assets: [Asset]

    public init(assets: [Asset] = []) {
        self.assets = assets
    }

    public static let empty = AssetCatalog()

    public func asset(matching reference: String, caption: String?) -> Asset? {
        asset(matching: reference, caption: caption, role: nil, credit: nil)
    }

    public func asset(matching reference: String, caption: String?, role: AssetRole?, credit: String?) -> Asset? {
        guard var asset = assetForReference(reference) else {
            return nil
        }

        if asset.caption == nil {
            asset.caption = caption
        }
        if let role {
            asset.role = role
        }
        if asset.credit == nil {
            asset.credit = credit
        }
        return asset
    }

    private func assetForReference(_ reference: String) -> Asset? {
        for path in reference.normalizedAssetLookupPaths {
            if let exactAsset = assets.first(where: { $0.fileName.normalizedAssetPath == path }) {
                return exactAsset
            }
        }

        let normalizedReference = reference.normalizedAssetReference
        return assets.first { $0.fileName.normalizedAssetReference == normalizedReference }
    }
}

extension String {
    var normalizedAssetPath: String {
        split(separator: "/")
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
            .joined(separator: "/")
            .lowercased()
    }

    var normalizedAssetLookupPaths: [String] {
        let path = normalizedAssetPath
        var paths = [path]
        let components = path.split(separator: "/").map(String.init)
        if let assetRootIndex = components.firstIndex(where: { $0 == "assets" || $0 == "images" }),
           assetRootIndex + 1 < components.count {
            paths.append(components[(assetRootIndex + 1)...].joined(separator: "/"))
        }
        return paths.reduce(into: []) { uniquePaths, path in
            if !uniquePaths.contains(path) {
                uniquePaths.append(path)
            }
        }
    }

    var normalizedAssetReference: String {
        URL(fileURLWithPath: self).lastPathComponent.lowercased()
    }
}
