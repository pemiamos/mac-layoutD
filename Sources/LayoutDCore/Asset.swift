import Foundation

/// 图片（连同其紧邻图注框）在版面中的绕排意图（2026-07-07 用户定，FRAME-SPLIT 批）：
/// - `wrap`：在文字流中，正文避让绕排（默认）。
/// - `underlay`：垫底/背景图——不参与绕排、画在文字下层，文字直接压在图上走。
public enum AssetWrapMode: String, Codable, Sendable {
    case wrap
    case underlay
}

public struct Asset: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var fileName: String
    public var sourcePath: String?
    public var role: AssetRole
    public var caption: String?
    public var credit: String?
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var dpi: Double?
    public var usage: AssetUsage
    /// 绕排意图。附加字段：旧 `.layoutd` 缺此键解码为 nil → 视同 `.wrap`。
    public var wrapMode: AssetWrapMode?

    public init(
        id: UUID = UUID(),
        fileName: String,
        sourcePath: String? = nil,
        role: AssetRole,
        caption: String? = nil,
        credit: String? = nil,
        pixelWidth: Int,
        pixelHeight: Int,
        dpi: Double? = nil,
        usage: AssetUsage = .unused,
        wrapMode: AssetWrapMode? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.sourcePath = sourcePath
        self.role = role
        self.caption = caption
        self.credit = credit
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.dpi = dpi
        self.usage = usage
        self.wrapMode = wrapMode
    }

    public var effectiveWrapMode: AssetWrapMode { wrapMode ?? .wrap }
}

public enum AssetRole: String, Codable, CaseIterable, Sendable {
    case hero
    case diagram
    case photo
    case chart
    case step
    case comparison
    case decorative
    case spread
}

public enum AssetUsage: String, Codable, Sendable {
    case unused
    case placed
    case repeated
}

import ImageIO
import CoreGraphics

public extension Asset {
    func detectColorModelAndActualDPI() -> (colorModel: String?, dpi: Double?) {
        guard let sourcePath = self.sourcePath,
              FileManager.default.fileExists(atPath: sourcePath) else {
            return (nil, nil)
        }
        let url = URL(fileURLWithPath: sourcePath)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return (nil, nil)
        }
        
        let colorModel = props[kCGImagePropertyColorModel] as? String
        let dpiWidth = props[kCGImagePropertyDPIWidth] as? Double
        return (colorModel, dpiWidth)
    }
}
