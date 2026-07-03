import Foundation

public struct PageSetup: Codable, Equatable, Sendable {
    public var pageSize: PageSize
    public var margins: PageMargins {
        didSet {
            marginTopToken = nil
            marginRightToken = nil
            marginBottomToken = nil
            marginLeftToken = nil
        }
    }
    public var columns: Int {
        didSet { columnsToken = nil }
    }
    public var gutter: Double {
        didSet { gutterToken = nil }
    }
    public var baselineGrid: Double {
        didSet { baselineGridToken = nil }
    }
    public var facingPages: Bool
    public var bleedMM: Double?
    public var layoutDirection: LayoutDirection
    public var marginTopToken: String?
    public var marginRightToken: String?
    public var marginBottomToken: String?
    public var marginLeftToken: String?
    public var columnsToken: String?
    public var gutterToken: String?
    public var baselineGridToken: String?

    public init(
        pageSize: PageSize,
        margins: PageMargins,
        columns: Int,
        gutter: Double,
        baselineGrid: Double,
        facingPages: Bool,
        bleedMM: Double? = 3.0,
        layoutDirection: LayoutDirection = .horizontal,
        marginTopToken: String? = nil,
        marginRightToken: String? = nil,
        marginBottomToken: String? = nil,
        marginLeftToken: String? = nil,
        columnsToken: String? = nil,
        gutterToken: String? = nil,
        baselineGridToken: String? = nil
    ) {
        self.pageSize = pageSize
        self.margins = margins
        self.columns = columns
        self.gutter = gutter
        self.baselineGrid = baselineGrid
        self.facingPages = facingPages
        self.bleedMM = bleedMM
        self.layoutDirection = layoutDirection
        self.marginTopToken = marginTopToken
        self.marginRightToken = marginRightToken
        self.marginBottomToken = marginBottomToken
        self.marginLeftToken = marginLeftToken
        self.columnsToken = columnsToken
        self.gutterToken = gutterToken
        self.baselineGridToken = baselineGridToken
    }

    enum CodingKeys: String, CodingKey {
        case pageSize, margins, columns, gutter, baselineGrid, facingPages, bleedMM, layoutDirection
        case marginTopToken, marginRightToken, marginBottomToken, marginLeftToken
        case columnsToken, gutterToken, baselineGridToken
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
        self.layoutDirection = try container.decodeIfPresent(LayoutDirection.self, forKey: .layoutDirection) ?? .horizontal
        self.marginTopToken = try container.decodeIfPresent(String.self, forKey: .marginTopToken)
        self.marginRightToken = try container.decodeIfPresent(String.self, forKey: .marginRightToken)
        self.marginBottomToken = try container.decodeIfPresent(String.self, forKey: .marginBottomToken)
        self.marginLeftToken = try container.decodeIfPresent(String.self, forKey: .marginLeftToken)
        self.columnsToken = try container.decodeIfPresent(String.self, forKey: .columnsToken)
        self.gutterToken = try container.decodeIfPresent(String.self, forKey: .gutterToken)
        self.baselineGridToken = try container.decodeIfPresent(String.self, forKey: .baselineGridToken)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pageSize, forKey: .pageSize)
        try container.encode(margins, forKey: .margins)
        try container.encode(columns, forKey: .columns)
        try container.encode(gutter, forKey: .gutter)
        try container.encode(baselineGrid, forKey: .baselineGrid)
        try container.encode(facingPages, forKey: .facingPages)
        try container.encodeIfPresent(bleedMM, forKey: .bleedMM)
        try container.encode(layoutDirection, forKey: .layoutDirection)
        try container.encodeIfPresent(marginTopToken, forKey: .marginTopToken)
        try container.encodeIfPresent(marginRightToken, forKey: .marginRightToken)
        try container.encodeIfPresent(marginBottomToken, forKey: .marginBottomToken)
        try container.encodeIfPresent(marginLeftToken, forKey: .marginLeftToken)
        try container.encodeIfPresent(columnsToken, forKey: .columnsToken)
        try container.encodeIfPresent(gutterToken, forKey: .gutterToken)
        try container.encodeIfPresent(baselineGridToken, forKey: .baselineGridToken)
    }

    public static let scienceBookDefault = PageSetup(
        pageSize: PageSize(width: 524.41, height: 737.01, label: "185mm x 260mm"),
        margins: PageMargins(top: 56, right: 48, bottom: 62, left: 54),
        columns: 2,
        gutter: 18,
        baselineGrid: 14,
        facingPages: true,
        bleedMM: 3.0,
        layoutDirection: .horizontal,
        marginTopToken: "page.margin.top",
        marginRightToken: "page.margin.right",
        marginBottomToken: "page.margin.bottom",
        marginLeftToken: "page.margin.left",
        columnsToken: "page.columns",
        gutterToken: "page.gutter",
        baselineGridToken: "page.baselineGrid"
    )

    public func resolved(using tokens: DesignTokens) -> PageSetup {
        PageSetup(
            pageSize: pageSize,
            margins: PageMargins(
                top: marginTopToken.flatMap(tokens.scalar) ?? margins.top,
                right: marginRightToken.flatMap(tokens.scalar) ?? margins.right,
                bottom: marginBottomToken.flatMap(tokens.scalar) ?? margins.bottom,
                left: marginLeftToken.flatMap(tokens.scalar) ?? margins.left
            ),
            columns: max(1, Int(round(columnsToken.flatMap(tokens.scalar) ?? Double(columns)))),
            gutter: gutterToken.flatMap(tokens.scalar) ?? gutter,
            baselineGrid: baselineGridToken.flatMap(tokens.scalar) ?? baselineGrid,
            facingPages: facingPages,
            bleedMM: bleedMM,
            layoutDirection: layoutDirection,
            marginTopToken: marginTopToken,
            marginRightToken: marginRightToken,
            marginBottomToken: marginBottomToken,
            marginLeftToken: marginLeftToken,
            columnsToken: columnsToken,
            gutterToken: gutterToken,
            baselineGridToken: baselineGridToken
        )
    }
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

public extension Rect {
    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
    func intersects(_ other: Rect) -> Bool {
        cgRect.intersects(other.cgRect)
    }
    func intersection(_ other: Rect) -> Rect {
        let intersectionRect = cgRect.intersection(other.cgRect)
        if intersectionRect.isNull {
            return Rect(x: 0, y: 0, width: 0, height: 0)
        }
        return Rect(x: intersectionRect.origin.x, y: intersectionRect.origin.y, width: intersectionRect.size.width, height: intersectionRect.size.height)
    }
}

public extension String {
    var trimmedForLayout: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
