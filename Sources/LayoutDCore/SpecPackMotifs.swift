import Foundation

public struct SpecPackDecoration: Codable, Equatable, Sendable {
    public var type: String
    public var color: String?
    public var widthPt: Double?
    public var lengthMM: Double?

    public init(type: String, color: String? = nil, widthPt: Double? = nil, lengthMM: Double? = nil) {
        self.type = type
        self.color = color
        self.widthPt = widthPt
        self.lengthMM = lengthMM
    }
}

public struct SpecPackChapterNumberMotif: Codable, Equatable, Sendable {
    public var fontAlias: String?
    public var resolvedFontName: String?
    public var fontSizePt: Double?
    public var color: String?
    public var opacity: Double?
    public var anchor: String?
    public var layer: String?

    public init(
        fontAlias: String? = nil,
        resolvedFontName: String? = nil,
        fontSizePt: Double? = nil,
        color: String? = nil,
        opacity: Double? = nil,
        anchor: String? = nil,
        layer: String? = nil
    ) {
        self.fontAlias = fontAlias
        self.resolvedFontName = resolvedFontName
        self.fontSizePt = fontSizePt
        self.color = color
        self.opacity = opacity
        self.anchor = anchor
        self.layer = layer
    }
}

public struct SpecPackSectionNumberMotif: Codable, Equatable, Sendable {
    public var style: String?
    public var color: String?
    public var minDigits: Int?
    public var prefix: String?
    public var suffix: String?

    public init(style: String? = nil, color: String? = nil, minDigits: Int? = nil, prefix: String? = nil, suffix: String? = nil) {
        self.style = style
        self.color = color
        self.minDigits = minDigits
        self.prefix = prefix
        self.suffix = suffix
    }
}

public struct SpecPackHeaderMotif: Codable, Equatable, Sendable {
    public var fontAlias: String?
    public var resolvedFontName: String?
    public var fontSizePt: Double?
    public var color: String?
    public var rule: String?
    public var label: String?
    public var showChapterTitle: Bool
    public var showPageNumber: Bool

    public init(
        fontAlias: String? = nil,
        resolvedFontName: String? = nil,
        fontSizePt: Double? = nil,
        color: String? = nil,
        rule: String? = nil,
        label: String? = nil,
        showChapterTitle: Bool = true,
        showPageNumber: Bool = true
    ) {
        self.fontAlias = fontAlias
        self.resolvedFontName = resolvedFontName
        self.fontSizePt = fontSizePt
        self.color = color
        self.rule = rule
        self.label = label
        self.showChapterTitle = showChapterTitle
        self.showPageNumber = showPageNumber
    }
}

public struct SpecPackMotifs: Codable, Equatable, Sendable {
    public var chapterNumber: SpecPackChapterNumberMotif?
    public var sectionNumber: SpecPackSectionNumberMotif?
    public var header: SpecPackHeaderMotif?
    public var captionTick: SpecPackDecoration?
    public var headingRule: SpecPackDecoration?
    public var pullQuoteRule: SpecPackDecoration?

    public init(
        chapterNumber: SpecPackChapterNumberMotif? = nil,
        sectionNumber: SpecPackSectionNumberMotif? = nil,
        header: SpecPackHeaderMotif? = nil,
        captionTick: SpecPackDecoration? = nil,
        headingRule: SpecPackDecoration? = nil,
        pullQuoteRule: SpecPackDecoration? = nil
    ) {
        self.chapterNumber = chapterNumber
        self.sectionNumber = sectionNumber
        self.header = header
        self.captionTick = captionTick
        self.headingRule = headingRule
        self.pullQuoteRule = pullQuoteRule
    }
}
