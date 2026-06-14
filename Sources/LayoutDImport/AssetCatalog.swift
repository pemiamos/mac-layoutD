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
        let normalizedReference = reference.normalizedAssetReference
        guard var asset = assets.first(where: { $0.fileName.normalizedAssetReference == normalizedReference }) else {
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
}

extension String {
    var normalizedAssetReference: String {
        URL(fileURLWithPath: self).lastPathComponent.lowercased()
    }
}
