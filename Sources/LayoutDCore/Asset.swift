import Foundation

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
        usage: AssetUsage = .unused
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
    }
}

public enum AssetRole: String, Codable, CaseIterable, Sendable {
    case hero
    case diagram
    case photo
    case chart
    case step
    case comparison
    case decorative
}

public enum AssetUsage: String, Codable, Sendable {
    case unused
    case placed
    case repeated
}
