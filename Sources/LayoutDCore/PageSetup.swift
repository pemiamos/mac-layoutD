import Foundation

public struct PageSetup: Codable, Equatable, Sendable {
    public var pageSize: PageSize
    public var margins: PageMargins
    public var columns: Int
    public var gutter: Double
    public var baselineGrid: Double
    public var facingPages: Bool
    public var bleedMM: Double?

    public init(
        pageSize: PageSize,
        margins: PageMargins,
        columns: Int,
        gutter: Double,
        baselineGrid: Double,
        facingPages: Bool,
        bleedMM: Double? = 3.0
    ) {
        self.pageSize = pageSize
        self.margins = margins
        self.columns = columns
        self.gutter = gutter
        self.baselineGrid = baselineGrid
        self.facingPages = facingPages
        self.bleedMM = bleedMM
    }

    enum CodingKeys: String, CodingKey {
        case pageSize, margins, columns, gutter, baselineGrid, facingPages, bleedMM
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.pageSize = try container.decode(PageSize.self, forKey: .pageSize)
        self.margins = try container.decode(PageMargins.self, forKey: .margins)
        self.columns = try container.decode(Int.self, forKey: .columns)
        self.gutter = try container.decode(Double.self, forKey: .gutter)
        self.baselineGrid = try container.decode(Double.self, forKey: .baselineGrid)
        self.facingPages = try container.decode(Bool.self, forKey: .facingPages)
        self.bleedMM = try container.decodeIfPresent(Double.self, forKey: .bleedMM) ?? 3.0
    }

    public static let scienceBookDefault = PageSetup(
        pageSize: PageSize(width: 524.41, height: 737.01, label: "185mm x 260mm"),
        margins: PageMargins(top: 56, right: 48, bottom: 62, left: 54),
        columns: 2,
        gutter: 18,
        baselineGrid: 14,
        facingPages: true,
        bleedMM: 3.0
    )
}

public struct PageSize: Codable, Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var label: String

    public init(width: Double, height: Double, label: String) {
        self.width = width
        self.height = height
        self.label = label
    }
}

public struct PageMargins: Codable, Equatable, Sendable {
    public var top: Double
    public var right: Double
    public var bottom: Double
    public var left: Double

    public init(top: Double, right: Double, bottom: Double, left: Double) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }
}

public struct Rect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public extension String {
    var trimmedForLayout: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
