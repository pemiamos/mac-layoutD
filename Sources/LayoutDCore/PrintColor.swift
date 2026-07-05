import Foundation

/// A color that can be either screen-native RGB or print-native CMYK.
///
/// layoutD stores colors as plain `String` fields throughout the model
/// (`backgroundColorHex`, `ColorToken.hex`, …). Historically those strings were
/// always `#RRGGBB`. `PrintColor` widens that vocabulary *without changing any
/// field types*: a color string may now also be `cmyk(C,M,Y,K)`. Old `.layoutd`
/// files (RGB-only) keep parsing exactly as before, so there is no migration.
///
/// The whole point of the CMYK case is print fidelity: a user-entered
/// `cmyk(0,0,0,100)` must survive as a `Space="CMYK"` swatch all the way into
/// InDesign, instead of being flattened to an approximate RGB grey.
///
/// This type is pure (no AppKit) and Sendable so it can live in Core and be unit
/// tested. AppKit sinks (canvas / PDF / PNG) convert via `displayRGB`; the IDML
/// exporter uses `idmlSpaceValue` / `idmlSwatchSelf`.
public enum PrintColor: Equatable, Sendable {
    /// Components 0…255.
    case rgb(r: Int, g: Int, b: Int)
    /// Components 0…100 (InDesign process-CMYK convention).
    case cmyk(c: Double, m: Double, y: Double, k: Double)

    // MARK: - Parsing

    /// Parses a color string. Accepts:
    /// - `#RRGGBB` / `RRGGBB` / `#RGB` (→ `.rgb`)
    /// - `cmyk(C,M,Y,K)` or `cmyk:C,M,Y,K`, values 0…100 (→ `.cmyk`)
    ///
    /// Returns nil for anything it cannot make sense of.
    public init?(string raw: String) {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }

        let lower = s.lowercased()
        if lower.hasPrefix("cmyk") {
            // Strip the `cmyk` tag and any `(` `)` `:` wrapper, then split.
            var body = lower.dropFirst(4)
            if body.first == ":" { body = body.dropFirst() }
            if body.first == "(" { body = body.dropFirst() }
            if body.last == ")" { body = body.dropLast() }
            let parts = body.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 4 else { return nil }
            var comps: [Double] = []
            for p in parts {
                guard let v = Double(p) else { return nil }
                comps.append(min(100, max(0, v)))
            }
            self = .cmyk(c: comps[0], m: comps[1], y: comps[2], k: comps[3])
            return
        }

        // RGB hex path.
        var hex = s.uppercased()
        if hex.hasPrefix("#") { hex.removeFirst() }
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6, hex.allSatisfy({ $0.isHexDigit }) else { return nil }
        let r = Int(hex.prefix(2), radix: 16) ?? 0
        let g = Int(hex.dropFirst(2).prefix(2), radix: 16) ?? 0
        let b = Int(hex.dropFirst(4).prefix(2), radix: 16) ?? 0
        self = .rgb(r: r, g: g, b: b)
    }

    // MARK: - Canonical string (storage / dedup key)

    /// Round-trippable canonical encoding used both as the value written into the
    /// model and as the dedup key inside the exporter.
    ///
    /// RGB canonicalizes to 6 upper-hex digits **with no `#`** — byte-identical to
    /// the exporter's legacy `normalizeHex`, so existing RGB output never shifts.
    /// CMYK canonicalizes to `cmyk(C,M,Y,K)` with trimmed numbers.
    public var canonicalString: String {
        switch self {
        case let .rgb(r, g, b):
            return String(format: "%02X%02X%02X", clamp8(r), clamp8(g), clamp8(b))
        case let .cmyk(c, m, y, k):
            return "cmyk(\(Self.num(c)),\(Self.num(m)),\(Self.num(y)),\(Self.num(k)))"
        }
    }

    /// The value to store in a model color field (RGB keeps its familiar `#`).
    public var storageString: String {
        switch self {
        case .rgb:
            return "#" + canonicalString
        case .cmyk:
            return canonicalString
        }
    }

    // MARK: - Space conversion

    /// This color as CMYK. RGB is converted with the naive (no-ICC) device
    /// formula — the inverse of `displayRGB`, and the same approximation the
    /// canvas/PDF preview already use — so a document-wide "CMYK 输出" intent can
    /// flatten every swatch to Process CMYK at export without pulling in AppKit.
    /// Pure black stays K100; already-CMYK colors pass through unchanged.
    public var asCMYK: PrintColor {
        switch self {
        case .cmyk:
            return self
        case let .rgb(r, g, b):
            let rf = Double(r) / 255, gf = Double(g) / 255, bf = Double(b) / 255
            let k = 1 - max(rf, gf, bf)
            if k >= 1 - 1e-9 {
                return .cmyk(c: 0, m: 0, y: 0, k: 100)
            }
            let c = (1 - rf - k) / (1 - k)
            let m = (1 - gf - k) / (1 - k)
            let y = (1 - bf - k) / (1 - k)
            return .cmyk(
                c: (c * 100).rounded(),
                m: (m * 100).rounded(),
                y: (y * 100).rounded(),
                k: (k * 100).rounded()
            )
        }
    }

    /// True for a very dark color (any hue). Used by the CMYK output intent to
    /// snap "black" text to a clean K100 single-black instead of a 4-color rich
    /// black — the standard book-printing convention for body/heading type.
    public var isNearBlack: Bool {
        let rgb = displayRGB
        return max(rgb.r, rgb.g, rgb.b) <= 0.25
    }

    // MARK: - Screen display

    /// RGB components in 0…1 for on-screen rendering. CMYK uses the naive
    /// device conversion (no ICC) — good enough for canvas / preview.
    public var displayRGB: (r: Double, g: Double, b: Double) {
        switch self {
        case let .rgb(r, g, b):
            return (Double(r) / 255, Double(g) / 255, Double(b) / 255)
        case let .cmyk(c, m, y, k):
            let cc = c / 100, mm = m / 100, yy = y / 100, kk = k / 100
            return ((1 - cc) * (1 - kk), (1 - mm) * (1 - kk), (1 - yy) * (1 - kk))
        }
    }

    // MARK: - IDML export

    /// `(Space, ColorValue)` for an IDML `<Color>` element.
    public var idmlSpaceValue: (space: String, value: String) {
        switch self {
        case let .rgb(r, g, b):
            return ("RGB", "\(clamp8(r)) \(clamp8(g)) \(clamp8(b))")
        case let .cmyk(c, m, y, k):
            return ("CMYK", "\(Self.num(c)) \(Self.num(m)) \(Self.num(y)) \(Self.num(k))")
        }
    }

    /// The `Self=` / reference name for this color's IDML swatch. Pure black
    /// (either `#000000` or `cmyk(0,0,0,100)`) collapses to the built-in
    /// `Color/Black` so we never emit a duplicate black swatch.
    public var idmlSwatchSelf: String {
        if isBuiltinBlack { return "Color/Black" }
        switch self {
        case .rgb:
            return "Color/C\(canonicalString)"
        case let .cmyk(c, m, y, k):
            return "Color/CMYK_\(Self.num(c))_\(Self.num(m))_\(Self.num(y))_\(Self.num(k))"
        }
    }

    /// Human-readable swatch name (InDesign Swatches panel).
    public var idmlSwatchName: String {
        switch self {
        case .rgb:
            return "C\(canonicalString)"
        case let .cmyk(c, m, y, k):
            return "C=\(Self.num(c)) M=\(Self.num(m)) Y=\(Self.num(y)) K=\(Self.num(k))"
        }
    }

    /// True for a color that should reuse InDesign's built-in Black swatch.
    public var isBuiltinBlack: Bool {
        switch self {
        case let .rgb(r, g, b):
            return r == 0 && g == 0 && b == 0
        case let .cmyk(c, m, y, k):
            return c == 0 && m == 0 && y == 0 && k == 100
        }
    }

    // MARK: - Helpers

    private func clamp8(_ v: Int) -> Int { min(255, max(0, v)) }

    /// Compact number: integers print without a decimal point (`100`, `12.5`).
    private static func num(_ v: Double) -> String {
        if v == v.rounded() { return String(Int(v)) }
        return String(format: "%g", v)
    }
}

/// A user-saved color in the project's swatch library (the "色板" panel). Stores
/// the color as a `PrintColor` storage string so both RGB and CMYK survive.
public struct PrintSwatch: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var colorString: String

    public init(id: UUID = UUID(), name: String, colorString: String) {
        self.id = id
        self.name = name
        self.colorString = colorString
    }

    public init(id: UUID = UUID(), name: String, color: PrintColor) {
        self.init(id: id, name: name, colorString: color.storageString)
    }

    /// The decoded color, or nil if the stored string is malformed.
    public var color: PrintColor? { PrintColor(string: colorString) }
}
