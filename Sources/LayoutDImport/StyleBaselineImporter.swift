import Foundation
import CoreText
import LayoutDCore

public enum ImportFormat: String, Sendable {
    case dtcg
    case figma
    case specPack
}

public struct SpecPackFontResolution: Equatable, Sendable {
    public var roleOrAlias: String
    public var requestedName: String
    public var resolvedName: String

    public init(roleOrAlias: String, requestedName: String, resolvedName: String) {
        self.roleOrAlias = roleOrAlias
        self.requestedName = requestedName
        self.resolvedName = resolvedName
    }
}

public struct SpecPackDecoration: Equatable, Sendable {
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

public struct SpecPackImportResult: Sendable {
    public var tokens: DesignTokens
    public var unsupportedFields: [String]
    public var fontResolutions: [SpecPackFontResolution]
    public var roleColors: [String: String]
    public var roleDecorations: [String: SpecPackDecoration]

    public init(
        tokens: DesignTokens,
        unsupportedFields: [String],
        fontResolutions: [SpecPackFontResolution],
        roleColors: [String: String] = [:],
        roleDecorations: [String: SpecPackDecoration] = [:]
    ) {
        self.tokens = tokens
        self.unsupportedFields = unsupportedFields
        self.fontResolutions = fontResolutions
        self.roleColors = roleColors
        self.roleDecorations = roleDecorations
    }
}

public struct StyleBaselineImportError: LocalizedError, Equatable {
    public var path: String
    public var message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }

    public var errorDescription: String? {
        "\(path): \(message)"
    }
}

public struct StyleBaselineImporter {
    public typealias FontAvailabilityChecker = (String) -> Bool

    struct FlatToken {
        let type: String
        let valueString: String
        let valueDict: [String: String]?
    }

    private static let pointsPerMillimeter = 72.0 / 25.4

    private static let approvedFontAliases: [String: String] = [
        "方正兰亭细黑": "方正兰亭细黑简体",
        "黑体-简 Medium": "Heiti SC Medium",
        "宋体-简（标题用衬线）": "Songti SC",
        "宋体-简": "Songti SC",
        "江城律动宋": "JiangChengLvDongSong"
    ]

    private static let roleStyleIDs: [String: String] = [
        "章名": StyleID.heading1.rawValue,
        "节名": StyleID.heading2.rawValue,
        "正文": StyleID.body.rawValue,
        "抽言": StyleID.pullQuote.rawValue,
        "图注": StyleID.caption.rawValue,
        "开节概述": StyleID.introduction.rawValue,
        "引文": StyleID.bibliography.rawValue
    ]

    private static let unsupportedSpecPackRoleFields: Set<String> = [
        "alignment", "blockColor", "blockSize_mm", "cornerRadius_mm",
        "format", "maxLineWidth_chars", "numberStyle", "opacity",
        "position", "rule", "span", "textColor", "tracking_em", "treatment"
    ]

    public static func autoDetectAndParse(jsonData: Data) throws -> (tokens: DesignTokens, format: ImportFormat) {
        guard let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
            throw NSError(
                domain: "StyleBaselineImporter",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid JSON structure: top level must be a JSON object"]
            )
        }

        if jsonObject["collections"] != nil {
            let tokens = try parseFigmaVariables(jsonObject)
            return (tokens, .figma)
        } else if isSpecPack(jsonObject) {
            let result = try parseSpecPack(jsonObject)
            return (result.tokens, .specPack)
        } else {
            let tokens = try parseDTCG(jsonObject)
            return (tokens, .dtcg)
        }
    }

    public static func parseSpecPack(
        jsonData: Data,
        fontAvailability: FontAvailabilityChecker? = nil
    ) throws -> SpecPackImportResult {
        guard let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
            throw StyleBaselineImportError(path: "$", message: "top level must be a JSON object")
        }
        return try parseSpecPack(jsonObject, fontAvailability: fontAvailability)
    }

    public static func parseSpecPack(
        _ jsonObject: [String: Any],
        fontAvailability: FontAvailabilityChecker? = nil
    ) throws -> SpecPackImportResult {
        guard isSpecPack(jsonObject) else {
            throw StyleBaselineImportError(path: "$", message: "not a layoutD spec pack; expected meta/page/fonts/colors/roles")
        }

        let meta = try requiredObject(jsonObject, key: "meta", path: "$")
        _ = try requiredString(meta, key: "name", path: "$.meta")

        let page = try requiredObject(jsonObject, key: "page", path: "$")
        let size = try requiredObject(page, key: "size_mm", path: "$.page")
        let widthMM = try positiveNumber(size, key: "width", path: "$.page.size_mm")
        let heightMM = try positiveNumber(size, key: "height", path: "$.page.size_mm")

        let margins = try requiredObject(page, key: "margins_mm", path: "$.page")
        let topMM = try nonNegativeNumber(margins, key: "top", path: "$.page.margins_mm")
        let bottomMM = try nonNegativeNumber(margins, key: "bottom", path: "$.page.margins_mm")
        let innerMM = try nonNegativeNumber(margins, key: "inner", path: "$.page.margins_mm")
        let outerMM = try nonNegativeNumber(margins, key: "outer", path: "$.page.margins_mm")

        let grid = try requiredObject(page, key: "grid", path: "$.page")
        let columns = try positiveNumber(grid, key: "columns", path: "$.page.grid")
        let gutterMM = try nonNegativeNumber(grid, key: "gutter_mm", path: "$.page.grid")
        let baselineGrid = try positiveNumber(grid, key: "baselineGrid_pt", path: "$.page.grid")

        let widthPt = mmToPt(widthMM)
        let heightPt = mmToPt(heightMM)
        let topPt = mmToPt(topMM)
        let bottomPt = mmToPt(bottomMM)
        let innerPt = mmToPt(innerMM)
        let outerPt = mmToPt(outerMM)
        let gutterPt = mmToPt(gutterMM)
        guard widthPt - innerPt - outerPt > 0 else {
            throw StyleBaselineImportError(path: "$.page.margins_mm", message: "inner + outer margins exceed page width")
        }
        guard heightPt - topPt - bottomPt > 0 else {
            throw StyleBaselineImportError(path: "$.page.margins_mm", message: "top + bottom margins exceed page height")
        }

        let fonts = try requiredObject(jsonObject, key: "fonts", path: "$")
        let fontAvailability = fontAvailability ?? isFontAvailable
        var fontResolutions: [SpecPackFontResolution] = []
        var resolvedFontsByAlias: [String: String] = [:]
        for (alias, rawName) in fonts {
            guard let requestedName = rawName as? String, !requestedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw StyleBaselineImportError(path: "$.fonts.\(alias)", message: "font name must be a non-empty string")
            }
            let resolvedName = approvedFontAliases[requestedName] ?? requestedName
            guard fontAvailability(resolvedName) else {
                throw StyleBaselineImportError(path: "$.fonts.\(alias)", message: "font '\(requestedName)' resolved to '\(resolvedName)', but that font is not installed with a real weight")
            }
            resolvedFontsByAlias[alias] = resolvedName
            fontResolutions.append(SpecPackFontResolution(roleOrAlias: alias, requestedName: requestedName, resolvedName: resolvedName))
        }

        let colorRoot = try requiredObject(jsonObject, key: "colors", path: "$")
        let rawModes = (colorRoot["modes"] as? [String]) ?? [DesignTokens.baseMode]
        let colorModes = rawModes.isEmpty ? [DesignTokens.baseMode] : rawModes
        let defaultMode = colorModes.contains(DesignTokens.baseMode) ? DesignTokens.baseMode : colorModes[0]
        let colorTokensObject = try requiredObject(colorRoot, key: "tokens", path: "$.colors")
        var colors: [ColorTokenSet] = []
        for (id, rawToken) in colorTokensObject.sorted(by: { $0.key < $1.key }) {
            guard let values = rawToken as? [String: Any] else {
                throw StyleBaselineImportError(path: "$.colors.tokens.\(id)", message: "color token must be a mode-to-hex object")
            }
            var valuesByMode: [String: String] = [:]
            for mode in colorModes {
                if let rawHex = values[mode] as? String {
                    guard isHexColor(rawHex) else {
                        throw StyleBaselineImportError(path: "$.colors.tokens.\(id).\(mode)", message: "expected #RRGGBB hex color")
                    }
                    valuesByMode[mode] = rawHex.uppercased()
                }
            }
            guard !valuesByMode.isEmpty else {
                throw StyleBaselineImportError(path: "$.colors.tokens.\(id)", message: "color token has no values for declared modes \(colorModes.joined(separator: ", "))")
            }
            colors.append(ColorTokenSet(id: id, valuesByMode: valuesByMode))
        }

        let vertical = (jsonObject["vertical"] as? Bool) ?? false
        var scalars: [ScalarToken] = [
            ScalarToken(id: "page.width", value: widthPt, kind: .dimension),
            ScalarToken(id: "page.height", value: heightPt, kind: .dimension),
            ScalarToken(id: "page.margin.top", value: topPt, kind: .spacing),
            ScalarToken(id: "page.margin.bottom", value: bottomPt, kind: .spacing),
            ScalarToken(id: "page.margin.inner", value: innerPt, kind: .spacing),
            ScalarToken(id: "page.margin.outer", value: outerPt, kind: .spacing),
            ScalarToken(id: "page.margin.left", value: innerPt, kind: .spacing),
            ScalarToken(id: "page.margin.right", value: outerPt, kind: .spacing),
            ScalarToken(id: "page.columns", value: columns, kind: .dimension),
            ScalarToken(id: "page.gutter", value: gutterPt, kind: .spacing),
            ScalarToken(id: "page.baselineGrid", value: baselineGrid, kind: .spacing),
            ScalarToken(id: "page.vertical", value: vertical ? 1 : 0, kind: .dimension)
        ]

        let roles = try requiredObject(jsonObject, key: "roles", path: "$")
        var unsupportedFields: [String] = []
        var roleColors: [String: String] = [:]
        var roleDecorations: [String: SpecPackDecoration] = [:]

        for (role, rawRole) in roles.sorted(by: { $0.key < $1.key }) {
            guard let roleObject = rawRole as? [String: Any] else {
                throw StyleBaselineImportError(path: "$.roles.\(role)", message: "role style must be an object")
            }

            let mappedStyleID = roleStyleIDs[role]
            if mappedStyleID == nil {
                unsupportedFields.append("$.roles.\(role)")
            }

            if let fontAlias = roleObject["font"] as? String {
                guard let resolved = resolvedFontsByAlias[fontAlias] else {
                    throw StyleBaselineImportError(path: "$.roles.\(role).font", message: "unknown font alias '\(fontAlias)'")
                }
                fontResolutions.append(SpecPackFontResolution(roleOrAlias: role, requestedName: fontAlias, resolvedName: resolved))
            }

            if let color = roleObject["color"] as? String {
                roleColors[role] = color
            }

            if let decObj = roleObject["decoration"] as? [String: Any] {
                guard let type = decObj["type"] as? String else {
                    throw StyleBaselineImportError(path: "$.roles.\(role).decoration.type", message: "decoration must have a 'type'")
                }
                let decColor = decObj["color"] as? String
                let widthPt = decObj["width_pt"] as? Double ?? (decObj["width_pt"] as? Int).map(Double.init)
                let lengthMM = decObj["length_mm"] as? Double ?? (decObj["length_mm"] as? Int).map(Double.init)
                roleDecorations[role] = SpecPackDecoration(
                    type: type,
                    color: decColor,
                    widthPt: widthPt,
                    lengthMM: lengthMM
                )
            }

            if let styleID = mappedStyleID {
                if let fontSize = try optionalPositiveNumber(roleObject, key: "fontSize_pt", path: "$.roles.\(role)") {
                    scalars.append(ScalarToken(id: "paragraph.\(styleID).fontSize", value: fontSize, kind: .fontSize))
                    if let lineHeightRaw = try optionalPositiveNumber(roleObject, key: "lineHeight", path: "$.roles.\(role)") {
                        let leading = lineHeightRaw <= 4 ? fontSize * lineHeightRaw : lineHeightRaw
                        scalars.append(ScalarToken(id: "paragraph.\(styleID).lineHeight", value: leading, kind: .lineHeight))
                    }
                    if let indentEm = try optionalNonNegativeNumber(roleObject, key: "firstLineIndent_em", path: "$.roles.\(role)") {
                        scalars.append(ScalarToken(id: "paragraph.\(styleID).firstLineIndent", value: fontSize * indentEm, kind: .spacing))
                    }
                    if let indentEm = try optionalNonNegativeNumber(roleObject, key: "indent_em", path: "$.roles.\(role)") {
                        scalars.append(ScalarToken(id: "paragraph.\(styleID).firstLineIndent", value: fontSize * indentEm, kind: .spacing))
                    }
                } else if roleObject["lineHeight"] != nil {
                    throw StyleBaselineImportError(path: "$.roles.\(role).lineHeight", message: "lineHeight requires fontSize_pt so multiplier can be converted to points")
                }

                if let before = try optionalNonNegativeNumber(roleObject, key: "spaceBefore_pt", path: "$.roles.\(role)") {
                    scalars.append(ScalarToken(id: "paragraph.\(styleID).spaceBefore", value: before, kind: .spacing))
                }
                if let after = try optionalNonNegativeNumber(roleObject, key: "spaceAfter_pt", path: "$.roles.\(role)") {
                    scalars.append(ScalarToken(id: "paragraph.\(styleID).spaceAfter", value: after, kind: .spacing))
                }
            }

            for key in roleObject.keys where unsupportedSpecPackRoleFields.contains(key) {
                unsupportedFields.append("$.roles.\(role).\(key)")
            }
        }

        if let marginColumn = grid["marginColumn"] {
            unsupportedFields.append("$.page.grid.marginColumn")
            if !(marginColumn is String) {
                throw StyleBaselineImportError(path: "$.page.grid.marginColumn", message: "marginColumn must be a string when present")
            }
        }

        let tokens = DesignTokens(
            colorModes: colorModes,
            defaultMode: defaultMode,
            colors: colors,
            scalars: scalars
        )
        return SpecPackImportResult(
            tokens: tokens,
            unsupportedFields: Array(Set(unsupportedFields)).sorted(),
            fontResolutions: fontResolutions.sorted { $0.roleOrAlias < $1.roleOrAlias },
            roleColors: roleColors,
            roleDecorations: roleDecorations
        )
    }

    public static func parseDTCG(_ jsonObject: [String: Any]) throws -> DesignTokens {
        let flat = flattenDTCG(jsonObject)
        
        var colorModes = Set<String>([DesignTokens.baseMode])
        var colorSets: [ColorTokenSet] = []
        var scalars: [ScalarToken] = []
        
        for (_, token) in flat {
            if token.type == "color", let valDict = token.valueDict {
                for mode in valDict.keys {
                    colorModes.insert(mode)
                }
            }
        }
        
        let sortedModes = Array(colorModes).sorted()
        
        for (path, token) in flat {
            let normalizedPath = path.replacingOccurrences(of: "/", with: ".")
            
            if token.type == "color" {
                let tokenId: String
                if normalizedPath.hasPrefix("color.") {
                    tokenId = String(normalizedPath.dropFirst(6))
                } else {
                    tokenId = normalizedPath
                }
                
                if let valDict = token.valueDict {
                    colorSets.append(ColorTokenSet(id: tokenId, valuesByMode: valDict))
                } else {
                    colorSets.append(ColorTokenSet(id: tokenId, hex: token.valueString))
                }
            } else {
                if let valDouble = Double(token.valueString) {
                    let kind: ScalarTokenKind
                    if normalizedPath.contains("fontSize") {
                        kind = .fontSize
                    } else if normalizedPath.contains("lineHeight") {
                        kind = .lineHeight
                    } else if normalizedPath.contains("margin") || normalizedPath.contains("gutter") || normalizedPath.contains("baselineGrid") || normalizedPath.contains("indent") || normalizedPath.contains("space") {
                        kind = .spacing
                    } else {
                        kind = .dimension
                    }
                    
                    scalars.append(ScalarToken(id: normalizedPath, value: valDouble, kind: kind))
                }
            }
        }
        
        return DesignTokens(
            colorModes: sortedModes,
            defaultMode: sortedModes.contains("default") ? "default" : (sortedModes.first ?? DesignTokens.baseMode),
            colors: colorSets,
            scalars: scalars
        )
    }

    public static func parseFigmaVariables(_ jsonObject: [String: Any]) throws -> DesignTokens {
        guard let collections = jsonObject["collections"] as? [[String: Any]] else {
            throw NSError(
                domain: "StyleBaselineImporter",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No variable collections found in Figma JSON"]
            )
        }
        
        var colorModes = Set<String>([DesignTokens.baseMode])
        var colorSets: [ColorTokenSet] = []
        var scalars: [ScalarToken] = []
        
        for coll in collections {
            var modeIdToName: [String: String] = [:]
            if let modes = coll["modes"] as? [[String: Any]] {
                for m in modes {
                    if let id = m["modeId"] as? String, let name = m["name"] as? String {
                        let safeName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        modeIdToName[id] = safeName
                        colorModes.insert(safeName)
                    }
                }
            }
            
            guard let variables = coll["variables"] as? [[String: Any]] else { continue }
            
            for v in variables {
                guard let rawName = v["name"] as? String,
                      let type = v["type"] as? String,
                      let valuesByMode = v["valuesByMode"] as? [String: Any] else { continue }
                
                let normalizedPath = rawName.replacingOccurrences(of: "/", with: ".")
                
                if type == "COLOR" {
                    let tokenId: String
                    if normalizedPath.hasPrefix("color.") {
                        tokenId = String(normalizedPath.dropFirst(6))
                    } else {
                        tokenId = normalizedPath
                    }
                    
                    var values: [String: String] = [:]
                    for (mId, rawVal) in valuesByMode {
                        let modeName = modeIdToName[mId] ?? DesignTokens.baseMode
                        let hex = parseFigmaColor(rawVal)
                        values[modeName] = hex
                    }
                    
                    if !values.isEmpty {
                        colorSets.append(ColorTokenSet(id: tokenId, valuesByMode: values))
                    }
                } else {
                    var scalarVal: Double? = nil
                    if let firstVal = valuesByMode.values.first {
                        scalarVal = parseFigmaFloat(firstVal)
                    }
                    
                    if let valDouble = scalarVal {
                        let kind: ScalarTokenKind
                        if normalizedPath.contains("fontSize") {
                            kind = .fontSize
                        } else if normalizedPath.contains("lineHeight") {
                            kind = .lineHeight
                        } else if normalizedPath.contains("margin") || normalizedPath.contains("gutter") || normalizedPath.contains("baselineGrid") || normalizedPath.contains("indent") || normalizedPath.contains("space") {
                            kind = .spacing
                        } else {
                            kind = .dimension
                        }
                        
                        scalars.append(ScalarToken(id: normalizedPath, value: valDouble, kind: kind))
                    }
                }
            }
        }
        
        let sortedModes = Array(colorModes).sorted()
        return DesignTokens(
            colorModes: sortedModes,
            defaultMode: sortedModes.contains("default") ? "default" : (sortedModes.first ?? DesignTokens.baseMode),
            colors: colorSets,
            scalars: scalars
        )
    }

    private static func flattenDTCG(_ dict: [String: Any], prefix: String = "") -> [String: FlatToken] {
        var flat: [String: FlatToken] = [:]
        
        if let rawValue = dict["$value"] {
            let type = (dict["$type"] as? String) ?? "dimension"
            
            if let valDict = rawValue as? [String: Any] {
                var values: [String: String] = [:]
                for (mode, val) in valDict {
                    values[mode] = String(describing: val)
                }
                flat[prefix] = FlatToken(type: type, valueString: "", valueDict: values)
            } else {
                flat[prefix] = FlatToken(type: type, valueString: String(describing: rawValue), valueDict: nil)
            }
            return flat
        }
        
        for (key, val) in dict {
            if key.hasPrefix("$") { continue }
            let nextPrefix = prefix.isEmpty ? key : "\(prefix)/\(key)"
            if let subDict = val as? [String: Any] {
                flat.merge(flattenDTCG(subDict, prefix: nextPrefix)) { current, _ in current }
            }
        }
        
        return flat
    }

    private static func parseFigmaColor(_ rawValue: Any) -> String {
        if let hex = rawValue as? String {
            if hex.hasPrefix("#") {
                return hex
            }
            return "#" + hex
        }
        if let dict = rawValue as? [String: Any],
           let r = dict["r"] as? Double ?? (dict["r"] as? Int).flatMap(Double.init),
           let g = dict["g"] as? Double ?? (dict["g"] as? Int).flatMap(Double.init),
           let b = dict["b"] as? Double ?? (dict["b"] as? Int).flatMap(Double.init) {
            
            let isScale255 = (r > 1.0 || g > 1.0 || b > 1.0)
            let ri = Int(round(isScale255 ? r : r * 255.0))
            let gi = Int(round(isScale255 ? g : g * 255.0))
            let bi = Int(round(isScale255 ? b : b * 255.0))
            
            let clampedR = max(0, min(255, ri))
            let clampedG = max(0, min(255, gi))
            let clampedB = max(0, min(255, bi))
            
            return String(format: "#%02X%02X%02X", clampedR, clampedG, clampedB)
        }
        return "#000000"
    }

    private static func parseFigmaFloat(_ rawValue: Any) -> Double? {
        if let d = rawValue as? Double { return d }
        if let i = rawValue as? Int { return Double(i) }
        if let s = rawValue as? String { return Double(s) }
        return nil
    }

    private static func isSpecPack(_ jsonObject: [String: Any]) -> Bool {
        jsonObject["meta"] != nil
            && jsonObject["page"] != nil
            && jsonObject["fonts"] != nil
            && jsonObject["colors"] != nil
            && jsonObject["roles"] != nil
    }

    private static func requiredObject(_ object: [String: Any], key: String, path: String) throws -> [String: Any] {
        guard let value = object[key] else {
            throw StyleBaselineImportError(path: "\(path).\(key)", message: "missing required object")
        }
        guard let dict = value as? [String: Any] else {
            throw StyleBaselineImportError(path: "\(path).\(key)", message: "must be an object")
        }
        return dict
    }

    private static func requiredString(_ object: [String: Any], key: String, path: String) throws -> String {
        guard let value = object[key] else {
            throw StyleBaselineImportError(path: "\(path).\(key)", message: "missing required string")
        }
        guard let string = value as? String, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StyleBaselineImportError(path: "\(path).\(key)", message: "must be a non-empty string")
        }
        return string
    }

    private static func positiveNumber(_ object: [String: Any], key: String, path: String) throws -> Double {
        let value = try number(object, key: key, path: path)
        guard value > 0 else {
            throw StyleBaselineImportError(path: "\(path).\(key)", message: "must be greater than 0")
        }
        return value
    }

    private static func nonNegativeNumber(_ object: [String: Any], key: String, path: String) throws -> Double {
        let value = try number(object, key: key, path: path)
        guard value >= 0 else {
            throw StyleBaselineImportError(path: "\(path).\(key)", message: "must be 0 or greater")
        }
        return value
    }

    private static func optionalPositiveNumber(_ object: [String: Any], key: String, path: String) throws -> Double? {
        guard object[key] != nil else { return nil }
        return try positiveNumber(object, key: key, path: path)
    }

    private static func optionalNonNegativeNumber(_ object: [String: Any], key: String, path: String) throws -> Double? {
        guard object[key] != nil else { return nil }
        return try nonNegativeNumber(object, key: key, path: path)
    }

    private static func number(_ object: [String: Any], key: String, path: String) throws -> Double {
        guard let value = object[key] else {
            throw StyleBaselineImportError(path: "\(path).\(key)", message: "missing required number")
        }
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        throw StyleBaselineImportError(path: "\(path).\(key)", message: "must be a number")
    }

    private static func mmToPt(_ value: Double) -> Double {
        value * pointsPerMillimeter
    }

    private static func isHexColor(_ value: String) -> Bool {
        guard value.count == 7, value.first == "#" else { return false }
        return value.dropFirst().allSatisfy { $0.isHexDigit }
    }

    private static func isFontAvailable(_ fontName: String) -> Bool {
        let descriptor = CTFontDescriptorCreateWithNameAndSize(fontName as CFString, 12)
        let matches = CTFontDescriptorCreateMatchingFontDescriptors(descriptor, nil) as? [CTFontDescriptor]
        return matches?.isEmpty == false
    }
}
