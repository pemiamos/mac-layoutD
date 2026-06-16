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

    public static let compactStudyGuide = StyleLibrary(
        paragraphStyles: [
            .heading1.with(fontSize: 19, lineHeight: 26, spaceBefore: 14, spaceAfter: 10),
            .heading2.with(fontSize: 13.5, lineHeight: 19, spaceBefore: 8, spaceAfter: 6),
            .body.with(fontSize: 9.5, lineHeight: 14, firstLineIndent: 19, spaceAfter: 3),
            .caption.with(fontSize: 7.8, lineHeight: 10.5, spaceAfter: 6),
            .callout.with(fontSize: 10, lineHeight: 15, spaceBefore: 6, spaceAfter: 6)
        ],
        colors: [
            ColorToken(id: "ink", hex: "#1F2933"),
            ColorToken(id: "paper", hex: "#FAFAF7"),
            ColorToken(id: "accent", hex: "#2F6F9F"),
            ColorToken(id: "warning", hex: "#A15C14")
        ]
    )

    public static let imageRichScience = StyleLibrary(
        paragraphStyles: [
            .heading1.with(fontSize: 24, lineHeight: 32, spaceBefore: 20, spaceAfter: 16),
            .heading2.with(fontSize: 16, lineHeight: 23, spaceBefore: 14, spaceAfter: 10),
            .body.with(fontSize: 10.8, lineHeight: 17, firstLineIndent: 21.6, spaceAfter: 5),
            .caption.with(fontSize: 9, lineHeight: 13, spaceAfter: 9),
            .callout.with(fontSize: 11.5, lineHeight: 18, spaceBefore: 9, spaceAfter: 9)
        ],
        colors: [
            ColorToken(id: "ink", hex: "#111827"),
            ColorToken(id: "paper", hex: "#F5F7F4"),
            ColorToken(id: "accent", hex: "#1F7A5C"),
            ColorToken(id: "warning", hex: "#B04718")
        ]
    )
}

public enum StyleTemplate: String, Codable, CaseIterable, Sendable {
    case chineseScienceDefault
    case compactStudyGuide
    case imageRichScience

    public var displayName: String {
        switch self {
        case .chineseScienceDefault:
            return "中文科普默认"
        case .compactStudyGuide:
            return "紧凑学习手册"
        case .imageRichScience:
            return "图像强化科普"
        }
    }

    public var styleLibrary: StyleLibrary {
        switch self {
        case .chineseScienceDefault:
            return .defaultChineseScience
        case .compactStudyGuide:
            return .compactStudyGuide
        case .imageRichScience:
            return .imageRichScience
        }
    }
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

    public func with(
        fontSize: Double? = nil,
        lineHeight: Double? = nil,
        firstLineIndent: Double? = nil,
        spaceBefore: Double? = nil,
        spaceAfter: Double? = nil,
        colorToken: String? = nil
    ) -> ParagraphStyle {
        ParagraphStyle(
            id: id,
            displayName: displayName,
            fontName: fontName,
            fontSize: fontSize ?? self.fontSize,
            lineHeight: lineHeight ?? self.lineHeight,
            firstLineIndent: firstLineIndent ?? self.firstLineIndent,
            spaceBefore: spaceBefore ?? self.spaceBefore,
            spaceAfter: spaceAfter ?? self.spaceAfter,
            colorToken: colorToken ?? self.colorToken
        )
    }
}

public struct ColorToken: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var hex: String

    public init(id: String, hex: String) {
        self.id = id
        self.hex = hex
    }
}
