import Foundation
import LayoutDCore

public struct AssetCatalog: Sendable {
    public var assets: [Asset]

    public init(assets: [Asset] = []) {
        self.assets = assets
    }

    public static let empty = AssetCatalog()

    public func asset(matching reference: String, caption: String?) -> Asset? {
        let normalizedReference = reference.normalizedAssetReference
        guard var asset = assets.first(where: { $0.fileName.normalizedAssetReference == normalizedReference }) else {
            return nil
        }

        if asset.caption == nil {
            asset.caption = caption
        }
        return asset
    }
}

extension String {
    var normalizedAssetReference: String {
        URL(fileURLWithPath: self).lastPathComponent.lowercased()
    }
}
