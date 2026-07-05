import Foundation

public enum StyleID: String, Codable, Sendable {
    case body
    case heading1
    case heading2
    case heading3, introduction, introductionEnglish, pullQuote, bibliography
    case caption
    case callout
}

public struct StyleLibrary: Codable, Equatable, Sendable {
    public var paragraphStyles: [ParagraphStyle]
    public var colors: [ColorToken]
    public var componentStyles: [ComponentStyle]?
    /// Unified design tokens (P1). Optional & additive: when present it is the
    /// source of truth for color resolution; when nil the legacy `colors` list
    /// is used. Old `.layoutd` files decode with `tokens == nil`.
    public var tokens: DesignTokens?

    public init(
        paragraphStyles: [ParagraphStyle],
        colors: [ColorToken],
        componentStyles: [ComponentStyle]? = nil,
        tokens: DesignTokens? = nil
    ) {
        self.paragraphStyles = paragraphStyles
        self.colors = colors
        self.componentStyles = componentStyles
        self.tokens = tokens
    }

    public func paragraphStyle(id: String) -> ParagraphStyle {
        (paragraphStyles.first { $0.id == id } ?? .body).resolved(using: effectiveTokens)
    }

    public func componentStyle(for frameKind: PageFrameKind) -> ComponentStyle? {
        safeComponentStyles.first { $0.frameKind == frameKind }
    }

    /// Resolves a color token id to a hex value, preferring unified `tokens`
    /// (under the given mode) and falling back to the legacy `colors` list.
    /// Returns nil if the id is unknown in both.
    public func colorHex(_ id: String, mode: String? = nil) -> String? {
        if let tokens, let hex = tokens.colorHex(id, mode: mode) {
            return hex
        }
        return colors.first { $0.id == id }?.hex
    }

    /// The design tokens for this library, synthesizing from legacy `colors`
    /// when no explicit token set has been attached yet.
    public var effectiveTokens: DesignTokens {
        tokens ?? .from(legacyColors: colors)
    }

    public var safeComponentStyles: [ComponentStyle] {
        componentStyles ?? ComponentStyle.defaultChineseScience
    }

    public static let defaultChineseScience = StyleLibrary(
        paragraphStyles: [
            .heading1.withScalarTokens(
                fontSize: "paragraph.heading1.fontSize",
                lineHeight: "paragraph.heading1.lineHeight",
                spaceBefore: "paragraph.heading1.spaceBefore",
                spaceAfter: "paragraph.heading1.spaceAfter"
            ),
            .heading2.withScalarTokens(
                fontSize: "paragraph.heading2.fontSize",
                lineHeight: "paragraph.heading2.lineHeight",
                spaceBefore: "paragraph.heading2.spaceBefore",
                spaceAfter: "paragraph.heading2.spaceAfter"
            ),
            .heading3, .introduction, .introductionEnglish, .pullQuote, .bibliography,
            .body.withScalarTokens(
                fontSize: "paragraph.body.fontSize",
                lineHeight: "paragraph.body.lineHeight",
                firstLineIndent: "paragraph.body.firstLineIndent",
                spaceAfter: "paragraph.body.spaceAfter"
            ),
            .caption.withScalarTokens(
                fontSize: "paragraph.caption.fontSize",
                lineHeight: "paragraph.caption.lineHeight",
                spaceBefore: "paragraph.caption.spaceBefore",
                spaceAfter: "paragraph.caption.spaceAfter"
            ),
            .callout.withScalarTokens(
                fontSize: "paragraph.callout.fontSize",
                lineHeight: "paragraph.callout.lineHeight",
                spaceBefore: "paragraph.callout.spaceBefore",
                spaceAfter: "paragraph.callout.spaceAfter"
            )
        ],
        colors: [
            ColorToken(id: "ink", hex: "#17202A"),
            ColorToken(id: "paper", hex: "#F7F4EE"),
            ColorToken(id: "accent", hex: "#2D7A78"),
            ColorToken(id: "warning", hex: "#B3541E")
        ],
        componentStyles: ComponentStyle.defaultChineseScience,
        tokens: .defaultChineseScience
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

public enum CompositeFontClass: String, Codable, CaseIterable, Sendable, Hashable {
    case chinese
    case fullWidthPunctuation
    case halfWidthPunctuation
    case latin
    case digit
    case symbol
}

public struct CompositeFontMapping: Codable, Equatable, Hashable, Sendable {
    public var fontName: String
    public var sizeMultiplier: Double
    public var baselineOffset: Double

    public init(fontName: String, sizeMultiplier: Double = 1.0, baselineOffset: Double = 0.0) {
        self.fontName = fontName
        self.sizeMultiplier = sizeMultiplier
        self.baselineOffset = baselineOffset
    }
}

public extension Character {
    var compositeFontClass: CompositeFontClass {
        guard let firstScalar = self.unicodeScalars.first else {
            return .symbol
        }
        let val = firstScalar.value
        
        // 1. Digits
        if self.isNumber {
            if val >= 0x30 && val <= 0x39 {
                return .digit
            }
            if val >= 0xFF10 && val <= 0xFF19 {
                return .digit
            }
        }
        
        // 2. Latin Letters
        if self.isLetter {
            if (val >= 0x4E00 && val <= 0x9FFF) ||
                (val >= 0x3400 && val <= 0x4DBF) ||
                (val >= 0xF900 && val <= 0xFAFF) {
                return .chinese
            }
            return .latin
        }
        
        // 3. Chinese Ideographs (non-letter characters that are CJK)
        if (val >= 0x4E00 && val <= 0x9FFF) ||
            (val >= 0x3400 && val <= 0x4DBF) ||
            (val >= 0xF900 && val <= 0xFAFF) {
            return .chinese
        }
        
        // 4. Full-width / CJK Punctuation
        if (val >= 0x3000 && val <= 0x303F) ||
            (val >= 0xFF00 && val <= 0xFFEF) ||
            (val >= 0x2000 && val <= 0x206F) {
            return .fullWidthPunctuation
        }
        
        // 5. Half-width Punctuation / ASCII Symbols
        if (val >= 0x20 && val <= 0x2F) ||
            (val >= 0x3A && val <= 0x40) ||
            (val >= 0x5B && val <= 0x60) ||
            (val >= 0x7B && val <= 0x7E) {
            return .halfWidthPunctuation
        }
        
        return .symbol
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
    public var fontSizeToken: String?
    public var lineHeightToken: String?
    public var firstLineIndentToken: String?
    public var spaceBeforeToken: String?
    public var spaceAfterToken: String?
    public var compositeFont: [CompositeFontClass: CompositeFontMapping]?
    public var layoutDirection: LayoutDirection?

    public init(
        id: String,
        displayName: String,
        fontName: String,
        fontSize: Double,
        lineHeight: Double,
        firstLineIndent: Double,
        spaceBefore: Double,
        spaceAfter: Double,
        colorToken: String = "ink",
        fontSizeToken: String? = nil,
        lineHeightToken: String? = nil,
        firstLineIndentToken: String? = nil,
        spaceBeforeToken: String? = nil,
        spaceAfterToken: String? = nil,
        compositeFont: [CompositeFontClass: CompositeFontMapping]? = nil,
        layoutDirection: LayoutDirection? = nil
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
        self.fontSizeToken = fontSizeToken
        self.lineHeightToken = lineHeightToken
        self.firstLineIndentToken = firstLineIndentToken
        self.spaceBeforeToken = spaceBeforeToken
        self.spaceAfterToken = spaceAfterToken
        self.compositeFont = compositeFont
        self.layoutDirection = layoutDirection
    }

    public static let body = ParagraphStyle(
        id: StyleID.body.rawValue,
        displayName: "正文",
        fontName: "方正兰亭细黑简体",
        fontSize: 10.5,
        lineHeight: 16,
        firstLineIndent: 21,
        spaceBefore: 0,
        spaceAfter: 4,
        compositeFont: [
            .chinese: CompositeFontMapping(fontName: "方正兰亭细黑简体", sizeMultiplier: 1.0, baselineOffset: 0.0),
            .latin: CompositeFontMapping(fontName: "Georgia", sizeMultiplier: 1.05, baselineOffset: 0.0),
            .digit: CompositeFontMapping(fontName: "Helvetica", sizeMultiplier: 1.0, baselineOffset: 0.0)
        ]
    )

    public static let heading1 = ParagraphStyle(
        id: StyleID.heading1.rawValue,
        displayName: "一级标题",
        fontName: "Heiti SC Medium",
        fontSize: 22,
        lineHeight: 30,
        firstLineIndent: 0,
        spaceBefore: 18,
        spaceAfter: 14,
        compositeFont: [
            .chinese: CompositeFontMapping(fontName: "Heiti SC Medium", sizeMultiplier: 1.0, baselineOffset: 0.0),
            .latin: CompositeFontMapping(fontName: "Helvetica Neue", sizeMultiplier: 1.0, baselineOffset: 0.0),
            .digit: CompositeFontMapping(fontName: "Helvetica", sizeMultiplier: 1.0, baselineOffset: 0.0)
        ]
    )

    public static let heading2 = ParagraphStyle(
        id: StyleID.heading2.rawValue,
        displayName: "二级标题",
        fontName: "Heiti SC Medium",
        fontSize: 15,
        lineHeight: 22,
        firstLineIndent: 0,
        spaceBefore: 12,
        spaceAfter: 8,
        compositeFont: [
            .chinese: CompositeFontMapping(fontName: "Heiti SC Medium", sizeMultiplier: 1.0, baselineOffset: 0.0),
            .latin: CompositeFontMapping(fontName: "Helvetica Neue", sizeMultiplier: 1.0, baselineOffset: 0.0),
            .digit: CompositeFontMapping(fontName: "Helvetica", sizeMultiplier: 1.0, baselineOffset: 0.0)
        ]
    )

    // CJK 用「黑体-简」。注意必须带真实存在的字重：Heiti SC 只有 Light/Medium，没有 Regular，
    // 写裸名 "Heiti SC" 会按 family+Regular 查不到→CoreText 回退 Helvetica→InDesign 粉色豆腐。
    // 故用 "Heiti SC Medium"（中黑，适合标题）。与 heading1/2 一致走复合字体。
    public static let heading3 = ParagraphStyle(id: StyleID.heading3.rawValue, displayName: "三级标题", fontName: "Heiti SC Medium", fontSize: 16, lineHeight: 23, firstLineIndent: 0, spaceBefore: 10, spaceAfter: 7, compositeFont: [
        .chinese: CompositeFontMapping(fontName: "Heiti SC Medium", sizeMultiplier: 1.0, baselineOffset: 0.0),
        .latin: CompositeFontMapping(fontName: "Helvetica Neue", sizeMultiplier: 1.0, baselineOffset: 0.0),
        .digit: CompositeFontMapping(fontName: "Helvetica", sizeMultiplier: 1.0, baselineOffset: 0.0)
    ])
    public static let introduction = ParagraphStyle(id: StyleID.introduction.rawValue, displayName: "开节概述", fontName: "方正兰亭细黑简体", fontSize: 11, lineHeight: 17.6, firstLineIndent: 0, spaceBefore: 4, spaceAfter: 8)
    public static let introductionEnglish = ParagraphStyle(id: StyleID.introductionEnglish.rawValue, displayName: "开节概述英文", fontName: "Georgia", fontSize: 10, lineHeight: 16, firstLineIndent: 0, spaceBefore: 0, spaceAfter: 8)
    public static let pullQuote = ParagraphStyle(id: StyleID.pullQuote.rawValue, displayName: "抽言", fontName: "JiangChengLvDongSong", fontSize: 15, lineHeight: 23, firstLineIndent: 0, spaceBefore: 10, spaceAfter: 10)
    public static let bibliography = ParagraphStyle(id: StyleID.bibliography.rawValue, displayName: "参考文献", fontName: "方正兰亭细黑简体", fontSize: 8.5, lineHeight: 13, firstLineIndent: -14, spaceBefore: 0, spaceAfter: 2)

    public static let caption = ParagraphStyle(
        id: StyleID.caption.rawValue,
        displayName: "图注",
        fontName: "PingFang SC",
        fontSize: 8.5,
        lineHeight: 12,
        firstLineIndent: 0,
        spaceBefore: 4,
        spaceAfter: 8,
        compositeFont: [
            .chinese: CompositeFontMapping(fontName: "PingFang SC", sizeMultiplier: 1.0, baselineOffset: 0.0),
            .latin: CompositeFontMapping(fontName: "Helvetica", sizeMultiplier: 1.0, baselineOffset: 0.0),
            .digit: CompositeFontMapping(fontName: "Helvetica", sizeMultiplier: 1.0, baselineOffset: 0.0)
        ]
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
        colorToken: "accent",
        compositeFont: [
            .chinese: CompositeFontMapping(fontName: "PingFang SC Medium", sizeMultiplier: 1.0, baselineOffset: 0.0),
            .latin: CompositeFontMapping(fontName: "Helvetica", sizeMultiplier: 1.0, baselineOffset: 0.0),
            .digit: CompositeFontMapping(fontName: "Helvetica", sizeMultiplier: 1.0, baselineOffset: 0.0)
        ]
    )

    public func with(
        fontSize: Double? = nil,
        lineHeight: Double? = nil,
        firstLineIndent: Double? = nil,
        spaceBefore: Double? = nil,
        spaceAfter: Double? = nil,
        colorToken: String? = nil,
        compositeFont: [CompositeFontClass: CompositeFontMapping]? = nil,
        layoutDirection: LayoutDirection? = nil
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
            colorToken: colorToken ?? self.colorToken,
            fontSizeToken: fontSize == nil ? fontSizeToken : nil,
            lineHeightToken: lineHeight == nil ? lineHeightToken : nil,
            firstLineIndentToken: firstLineIndent == nil ? firstLineIndentToken : nil,
            spaceBeforeToken: spaceBefore == nil ? spaceBeforeToken : nil,
            spaceAfterToken: spaceAfter == nil ? spaceAfterToken : nil,
            compositeFont: compositeFont ?? self.compositeFont,
            layoutDirection: layoutDirection ?? self.layoutDirection
        )
    }

    public func withScalarTokens(
        fontSize: String? = nil,
        lineHeight: String? = nil,
        firstLineIndent: String? = nil,
        spaceBefore: String? = nil,
        spaceAfter: String? = nil
    ) -> ParagraphStyle {
        ParagraphStyle(
            id: id,
            displayName: displayName,
            fontName: fontName,
            fontSize: self.fontSize,
            lineHeight: self.lineHeight,
            firstLineIndent: self.firstLineIndent,
            spaceBefore: self.spaceBefore,
            spaceAfter: self.spaceAfter,
            colorToken: colorToken,
            fontSizeToken: fontSize ?? fontSizeToken,
            lineHeightToken: lineHeight ?? lineHeightToken,
            firstLineIndentToken: firstLineIndent ?? firstLineIndentToken,
            spaceBeforeToken: spaceBefore ?? spaceBeforeToken,
            spaceAfterToken: spaceAfter ?? spaceAfterToken,
            compositeFont: self.compositeFont,
            layoutDirection: self.layoutDirection
        )
    }

    public func resolved(using tokens: DesignTokens) -> ParagraphStyle {
        ParagraphStyle(
            id: id,
            displayName: displayName,
            fontName: fontName,
            fontSize: fontSizeToken.flatMap(tokens.scalar) ?? fontSize,
            lineHeight: lineHeightToken.flatMap(tokens.scalar) ?? lineHeight,
            firstLineIndent: firstLineIndentToken.flatMap(tokens.scalar) ?? firstLineIndent,
            spaceBefore: spaceBeforeToken.flatMap(tokens.scalar) ?? spaceBefore,
            spaceAfter: spaceAfterToken.flatMap(tokens.scalar) ?? spaceAfter,
            colorToken: colorToken,
            fontSizeToken: fontSizeToken,
            lineHeightToken: lineHeightToken,
            firstLineIndentToken: firstLineIndentToken,
            spaceBeforeToken: spaceBeforeToken,
            spaceAfterToken: spaceAfterToken,
            compositeFont: self.compositeFont,
            layoutDirection: self.layoutDirection
        )
    }

    public func fontMapping(for character: Character) -> CompositeFontMapping {
        let cls = character.compositeFontClass
        let targetClass: CompositeFontClass
        switch cls {
        case .chinese, .fullWidthPunctuation:
            targetClass = .chinese
        case .latin, .halfWidthPunctuation:
            targetClass = .latin
        case .digit:
            targetClass = .digit
        case .symbol:
            targetClass = .latin
        }
        
        if let mapping = compositeFont?[targetClass] {
            return mapping
        }
        return CompositeFontMapping(
            fontName: self.fontName,
            sizeMultiplier: 1.0,
            baselineOffset: 0.0
        )
    }
}

public struct ComponentStyle: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    public var frameKind: PageFrameKind
    public var fillColorHex: String?
    public var fillColorToken: String?
    public var strokeColorHex: String?
    public var strokeColorToken: String?
    public var accentColorHex: String?
    public var accentColorToken: String?
    public var textColorToken: String?
    public var strokeWidth: Double
    public var accentWidth: Double
    public var textInsetX: Double
    public var textInsetY: Double

    public init(
        id: String,
        displayName: String,
        frameKind: PageFrameKind,
        fillColorHex: String? = nil,
        fillColorToken: String? = nil,
        strokeColorHex: String? = nil,
        strokeColorToken: String? = nil,
        accentColorHex: String? = nil,
        accentColorToken: String? = nil,
        textColorToken: String? = nil,
        strokeWidth: Double = 0,
        accentWidth: Double = 0,
        textInsetX: Double = 0,
        textInsetY: Double = 0
    ) {
        self.id = id
        self.displayName = displayName
        self.frameKind = frameKind
        self.fillColorHex = fillColorHex
        self.fillColorToken = fillColorToken
        self.strokeColorHex = strokeColorHex
        self.strokeColorToken = strokeColorToken
        self.accentColorHex = accentColorHex
        self.accentColorToken = accentColorToken
        self.textColorToken = textColorToken
        self.strokeWidth = strokeWidth
        self.accentWidth = accentWidth
        self.textInsetX = textInsetX
        self.textInsetY = textInsetY
    }

    public static let defaultChineseScience: [ComponentStyle] = [
        ComponentStyle(
            id: "knowledgeCard",
            displayName: "知识卡片",
            frameKind: .callout,
            fillColorHex: "#E0F5ED",
            fillColorToken: "component.callout.background",
            strokeColorHex: "#2D7A78",
            strokeColorToken: "accent",
            accentColorHex: "#2D7A78",
            accentColorToken: "accent",
            textColorToken: "accent",
            strokeWidth: 0.8,
            accentWidth: 4,
            textInsetX: 8,
            textInsetY: 6
        ),
        ComponentStyle(
            id: "dataTable",
            displayName: "表格",
            frameKind: .table,
            fillColorHex: "#E0F5ED",
            fillColorToken: "component.table.background",
            strokeColorHex: "#2D7A78",
            strokeColorToken: "accent",
            textColorToken: "ink",
            strokeWidth: 0.8,
            textInsetX: 8,
            textInsetY: 6
        ),
        ComponentStyle(
            id: "figureCaption",
            displayName: "图注",
            frameKind: .caption,
            textColorToken: "ink",
            textInsetX: 0,
            textInsetY: 0
        )
    ]
}

public extension ComponentStyle {
    func resolvedFillColorHex(project: BookProject) -> String? {
        fillColorToken.flatMap(project.resolvedColorHex) ?? fillColorHex
    }

    func resolvedStrokeColorHex(project: BookProject) -> String? {
        strokeColorToken.flatMap(project.resolvedColorHex) ?? strokeColorHex
    }

    func resolvedAccentColorHex(project: BookProject) -> String? {
        accentColorToken.flatMap(project.resolvedColorHex) ?? accentColorHex
    }

    func resolvedTextColorHex(project: BookProject) -> String? {
        textColorToken.flatMap(project.resolvedColorHex)
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
