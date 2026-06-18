import Foundation
import LayoutDCore

public enum ImportFormat: String, Sendable {
    case dtcg
    case figma
}

public struct StyleBaselineImporter {
    struct FlatToken {
        let type: String
        let valueString: String
        let valueDict: [String: String]?
    }

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
        } else {
            let tokens = try parseDTCG(jsonObject)
            return (tokens, .dtcg)
        }
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
}
