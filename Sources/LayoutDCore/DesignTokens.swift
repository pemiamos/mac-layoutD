import Foundation

/// DTCG-aligned design tokens for layoutD's style baseline (roadmap P1).
///
/// Supports multiple color *modes* — e.g. per-chapter theme color groups such as
/// the green vs blue chapters in 《何以江南》 — so one token id resolves to a
/// different value per mode. This is the unified source the rest of the style
/// system (StyleLibrary, PageSetup, components) will progressively reference.
///
/// Additive & backward-compatible: `StyleLibrary` keeps its legacy `colors`
/// array; when `tokens` is present it becomes the source of truth for color
/// resolution. Old `.layoutd` files (no `tokens` key) decode with `tokens == nil`.
public struct DesignTokens: Codable, Equatable, Sendable {
    /// Ordered list of color modes; always contains at least `baseMode`.
    public var colorModes: [String]
    /// Mode used when a caller does not specify one.
    public var defaultMode: String
    public var colors: [ColorTokenSet]
    public var scalars: [ScalarToken]

    public static let baseMode = "default"

    public init(
        colorModes: [String] = [DesignTokens.baseMode],
        defaultMode: String = DesignTokens.baseMode,
        colors: [ColorTokenSet] = [],
        scalars: [ScalarToken] = []
    ) {
        let modes = colorModes.isEmpty ? [DesignTokens.baseMode] : colorModes
        self.colorModes = modes
        self.defaultMode = modes.contains(defaultMode) ? defaultMode : modes[0]
        self.colors = colors
        self.scalars = scalars
    }

    /// Resolves a color token id to a hex string under the given mode (or the
    /// default mode), falling back to the default mode then any defined value.
    public func colorHex(_ id: String, mode: String? = nil) -> String? {
        guard let set = colors.first(where: { $0.id == id }) else { return nil }
        return set.value(mode: mode ?? defaultMode, fallback: defaultMode)
    }

    public func scalar(_ id: String) -> Double? {
        scalars.first(where: { $0.id == id })?.value
    }

    /// Builds tokens from a legacy single-value color list (migration helper).
    public static func from(legacyColors: [ColorToken]) -> DesignTokens {
        DesignTokens(colors: legacyColors.map { ColorTokenSet(id: $0.id, hex: $0.hex) })
    }
}

public struct ColorTokenSet: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    /// mode -> hex value
    public var valuesByMode: [String: String]

    public init(id: String, valuesByMode: [String: String]) {
        self.id = id
        self.valuesByMode = valuesByMode
    }

    /// Single-mode convenience (default mode only).
    public init(id: String, hex: String) {
        self.init(id: id, valuesByMode: [DesignTokens.baseMode: hex])
    }

    public func value(mode: String, fallback: String) -> String? {
        valuesByMode[mode] ?? valuesByMode[fallback] ?? valuesByMode.first?.value
    }
}

public enum ScalarTokenKind: String, Codable, Sendable {
    case spacing
    case fontSize
    case lineHeight
    case dimension
}

public struct ScalarToken: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var value: Double
    public var kind: ScalarTokenKind

    public init(id: String, value: Double, kind: ScalarTokenKind = .dimension) {
        self.id = id
        self.value = value
        self.kind = kind
    }
}

// MARK: - DTCG export

/// A single token rendered in W3C Design Tokens (DTCG) leaf shape: `$type` + `$value`.
public struct DTCGToken: Codable, Equatable, Sendable {
    public let type: String
    public let value: String

    public init(type: String, value: String) {
        self.type = type
        self.value = value
    }

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case value = "$value"
    }
}

public extension DesignTokens {
    static let defaultChineseScience = DesignTokens(
        colors: [
            ColorTokenSet(id: "ink", hex: "#17202A"),
            ColorTokenSet(id: "paper", hex: "#F7F4EE"),
            ColorTokenSet(id: "accent", hex: "#2D7A78"),
            ColorTokenSet(id: "warning", hex: "#B3541E"),
            ColorTokenSet(id: "component.callout.background", hex: "#E0F5ED"),
            ColorTokenSet(id: "component.table.background", hex: "#E0F5ED")
        ],
        scalars: [
            ScalarToken(id: "page.margin.top", value: 56, kind: .spacing),
            ScalarToken(id: "page.margin.right", value: 48, kind: .spacing),
            ScalarToken(id: "page.margin.bottom", value: 62, kind: .spacing),
            ScalarToken(id: "page.margin.left", value: 54, kind: .spacing),
            ScalarToken(id: "page.columns", value: 2, kind: .dimension),
            ScalarToken(id: "page.gutter", value: 18, kind: .spacing),
            ScalarToken(id: "page.baselineGrid", value: 14, kind: .spacing),

            ScalarToken(id: "paragraph.heading1.fontSize", value: 22, kind: .fontSize),
            ScalarToken(id: "paragraph.heading1.lineHeight", value: 30, kind: .lineHeight),
            ScalarToken(id: "paragraph.heading1.spaceBefore", value: 18, kind: .spacing),
            ScalarToken(id: "paragraph.heading1.spaceAfter", value: 14, kind: .spacing),

            ScalarToken(id: "paragraph.heading2.fontSize", value: 15, kind: .fontSize),
            ScalarToken(id: "paragraph.heading2.lineHeight", value: 22, kind: .lineHeight),
            ScalarToken(id: "paragraph.heading2.spaceBefore", value: 12, kind: .spacing),
            ScalarToken(id: "paragraph.heading2.spaceAfter", value: 8, kind: .spacing),

            ScalarToken(id: "paragraph.body.fontSize", value: 10.5, kind: .fontSize),
            ScalarToken(id: "paragraph.body.lineHeight", value: 16, kind: .lineHeight),
            // 默认排书规则（2026-07-07 用户定）：开头不空两格 → 首行缩进 0；
            // 段与段之间空一行 → 段后间距 = 一行高（body lineHeight 16）；默认左对齐见导出器。
            ScalarToken(id: "paragraph.body.firstLineIndent", value: 0, kind: .spacing),
            ScalarToken(id: "paragraph.body.spaceAfter", value: 16, kind: .spacing),

            ScalarToken(id: "paragraph.caption.fontSize", value: 8.5, kind: .fontSize),
            ScalarToken(id: "paragraph.caption.lineHeight", value: 12, kind: .lineHeight),
            ScalarToken(id: "paragraph.caption.spaceBefore", value: 4, kind: .spacing),
            ScalarToken(id: "paragraph.caption.spaceAfter", value: 8, kind: .spacing),

            ScalarToken(id: "paragraph.callout.fontSize", value: 11, kind: .fontSize),
            ScalarToken(id: "paragraph.callout.lineHeight", value: 17, kind: .lineHeight),
            ScalarToken(id: "paragraph.callout.spaceBefore", value: 8, kind: .spacing),
            ScalarToken(id: "paragraph.callout.spaceAfter", value: 8, kind: .spacing)
        ]
    )

    /// Flat DTCG-aligned export keyed by namespaced token name. Colors emit one
    /// entry for the default mode (`color/<id>`) plus per-mode entries
    /// (`color/<id>/<mode>`) when more than one mode is defined. Scalars emit
    /// `<kind>/<id>` with a `dimension`/`number` `$type`.
    func dtcgExport() -> [String: DTCGToken] {
        var out: [String: DTCGToken] = [:]
        for set in colors {
            if let base = set.value(mode: defaultMode, fallback: defaultMode) {
                out["color/\(set.id)"] = DTCGToken(type: "color", value: base)
            }
            if colorModes.count > 1 {
                for mode in colorModes {
                    if let v = set.valuesByMode[mode] {
                        out["color/\(set.id)/\(mode)"] = DTCGToken(type: "color", value: v)
                    }
                }
            }
        }
        for token in scalars {
            let dtcgType = token.kind == .fontSize || token.kind == .lineHeight ? "number" : "dimension"
            out["\(token.kind.rawValue)/\(token.id)"] = DTCGToken(type: dtcgType, value: String(token.value))
        }
        return out
    }
}
