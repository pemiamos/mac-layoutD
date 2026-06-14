import Foundation

public enum StyleID: String, Codable, Sendable {
    case body
    case heading1
    case heading2
    case caption
    case callout
}

public struct StyleLibrary: Codable, Equatable, Sendable {
    public var paragraphStyles: [ParagraphStyle]
    public var colors: [ColorToken]

    public init(paragraphStyles: [ParagraphStyle], colors: [ColorToken]) {
        self.paragraphStyles = paragraphStyles
        self.colors = colors
    }

    public func paragraphStyle(id: String) -> ParagraphStyle {
        paragraphStyles.first { $0.id == id } ?? .body
    }

    public static let defaultChineseScience = StyleLibrary(
        paragraphStyles: [
            .heading1,
            .heading2,
            .body,
            .caption,
            .callout
        ],
        colors: [
            ColorToken(id: "ink", hex: "#17202A"),
            ColorToken(id: "paper", hex: "#F7F4EE"),
            ColorToken(id: "accent", hex: "#2D7A78"),
            ColorToken(id: "warning", hex: "#B3541E")
        ]
    )
}

public struct ParagraphStyle: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    public var fontName: String
    public var fontSize: Double
    public var lineHeight: Double
    public var firstLineIndent: Double
    public var spaceBefore: Double
    public var spaceAfter: Double
    public var colorToken: String

    public init(
        id: String,
        displayName: String,
        fontName: String,
        fontSize: Double,
        lineHeight: Double,
        firstLineIndent: Double,
        spaceBefore: Double,
        spaceAfter: Double,
        colorToken: String = "ink"
    ) {
        self.id = id
        self.displayName = displayName
        self.fontName = fontName
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.firstLineIndent = firstLineIndent
        self.spaceBefore = spaceBefore
        self.spaceAfter = spaceAfter
        self.colorToken = colorToken
    }

    public static let body = ParagraphStyle(
        id: StyleID.body.rawValue,
        displayName: "正文",
        fontName: "Songti SC",
        fontSize: 10.5,
        lineHeight: 16,
        firstLineIndent: 21,
        spaceBefore: 0,
        spaceAfter: 4
    )

    public static let heading1 = ParagraphStyle(
        id: StyleID.heading1.rawValue,
        displayName: "一级标题",
        fontName: "PingFang SC Semibold",
        fontSize: 22,
        lineHeight: 30,
        firstLineIndent: 0,
        spaceBefore: 18,
        spaceAfter: 14
    )

    public static let heading2 = ParagraphStyle(
        id: StyleID.heading2.rawValue,
        displayName: "二级标题",
        fontName: "PingFang SC Semibold",
        fontSize: 15,
        lineHeight: 22,
        firstLineIndent: 0,
        spaceBefore: 12,
        spaceAfter: 8
    )

    public static let caption = ParagraphStyle(
        id: StyleID.caption.rawValue,
        displayName: "图注",
        fontName: "PingFang SC",
        fontSize: 8.5,
        lineHeight: 12,
        firstLineIndent: 0,
        spaceBefore: 4,
        spaceAfter: 8
    )

    public static let callout = ParagraphStyle(
        id: StyleID.callout.rawValue,
        displayName: "知识卡片",
        fontName: "PingFang SC Medium",
        fontSize: 11,
        lineHeight: 17,
        firstLineIndent: 0,
        spaceBefore: 8,
        spaceAfter: 8,
        colorToken: "accent"
    )
}

public struct ColorToken: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var hex: String

    public init(id: String, hex: String) {
        self.id = id
        self.hex = hex
    }
}
