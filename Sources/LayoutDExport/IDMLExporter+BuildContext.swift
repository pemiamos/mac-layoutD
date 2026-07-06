import CoreText
import Foundation
import LayoutDCore

extension IDMLExporter {
    // MARK: - 构建上下文（资源注册表）

    struct BuildContext {
        let project: BookProject
        /// When true, RGB swatches are converted to Process CMYK before keying,
        /// so the whole document exports in a single CMYK color space.
        let cmykOutput: Bool
        var colorOrder: [String] = []          // 规范化 hex
        var colorName: [String: String] = [:]  // hex -> Color Self
        var fontOrder: [String] = []           // 字体家族顺序(InDesign 索引用的家族名)
        var fontStyles: [String: [(style: String, ps: String, full: String, type: String)]] = [:]  // 家族 -> [(样式, PostScript名, 全名, FontType)]
        var appliedFamily: [String: String] = [:]  // layoutD 原始字体名 -> InDesign 家族名
        var appliedStyle: [String: String] = [:]   // layoutD 原始字体名 -> InDesign 样式名
        var compositeFontStyleIds: [String] = []   // 有复合字体、需生成 CompositeFont 的样式 id
        var paragraphStyles: [ParagraphStyle] = []

        init(project: BookProject, cmykOutput: Bool = false) {
            self.project = project
            self.cmykOutput = cmykOutput
            // 预置内建黑色。
            colorOrder = ["000000"]
            colorName = ["000000": "Color/Black"]
        }

        mutating func color(_ raw: String) -> String {
            // RGB canonicalizes to the same 6-hex key as the legacy path, so
            // existing RGB swatches keep their exact Self / order. CMYK colors
            // key on their own canonical string and emit a Space="CMYK" swatch.
            // NOTE: keying/Self stay in the color's *stored* space so every frame
            // reference keeps matching; a CMYK output intent only rewrites the
            // emitted Space/Value/Name in `graphic()`, never the Self.
            let parsed = PrintColor(string: raw) ?? .rgb(r: 0, g: 0, b: 0)
            let key = parsed.canonicalString
            if let n = colorName[key] { return n }
            let name = parsed.idmlSwatchSelf
            colorName[key] = name
            // Built-in Black (RGB #000000 or CMYK 0,0,0,100) reuses the seeded
            // Color/Black swatch and is never re-emitted in Graphic.xml.
            if name != "Color/Black" {
                colorOrder.append(key)
            }
            return name
        }

        /// The text fill color to use, applying the CMYK-mode "black text → K100"
        /// rule: under a CMYK output intent a near-black text color collapses to
        /// `#000000` → the built-in `Color/Black` (Space=CMYK 0 0 0 100), so
        /// body/heading text prints as clean single-black instead of a 4-color
        /// rich black. Colored text is left untouched.
        func textColorHex(_ raw: String?) -> String {
            let hex = raw ?? "#000000"
            if cmykOutput, let color = PrintColor(string: hex), color.isNearBlack {
                return "#000000"
            }
            return hex
        }

        mutating func font(_ name: String) {
            let r = Self.idNames(name)
            appliedFamily[name] = r.family
            appliedStyle[name] = r.style
            if fontStyles[r.family] == nil { fontStyles[r.family] = []; fontOrder.append(r.family) }
            if !(fontStyles[r.family]?.contains { $0.style == r.style } ?? false) {
                fontStyles[r.family]?.append((r.style, r.ps, r.full, r.type))
            }
        }

        /// 用 CoreText 在本机把 layoutD 字体名解析成 InDesign 实际索引用的
        /// (本地化家族名, 本地化样式名, 真实 PostScript 名, 全名)。
        /// InDesign 中文版按本地化家族名(如「苹方-简」)+ PostScript 名匹配已装字体，
        /// 给英文家族名或把家族名当 PS 名都会被判缺失。
        static func idNames(_ raw: String) -> (family: String, style: String, ps: String, full: String, type: String) {
            let (eFam, eSty) = splitFont(raw)
            let attrs: [CFString: Any] = [
                kCTFontFamilyNameAttribute: eFam,
                kCTFontStyleNameAttribute: eSty
            ]
            let desc = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
            let font = CTFontCreateWithFontDescriptor(desc, 12, nil)
            let ps = CTFontCopyPostScriptName(font) as String
            guard !ps.isEmpty else {
                let fb = eSty == "Regular" ? eFam : "\(eFam) \(eSty)"
                return (eFam, eSty, fb, fb, "OpenTypeCFF")
            }
            let locFam = (CTFontCopyName(font, kCTFontFamilyNameKey) as String?) ?? eFam
            let locSty = (CTFontCopyName(font, kCTFontStyleNameKey) as String?) ?? eSty
            let full = (CTFontCopyFullName(font) as String?) ?? "\(locFam) \(locSty)"
            return (locFam, locSty, ps, full, fontType(desc))
        }

        /// CoreText 字体格式 → IDML FontType 字符串。系统 CJK 字体(苹方/宋体等)是
        /// OpenType-PostScript(CID)，InDesign 装的就是 OpenTypeCID 变体；填成 CFF 会
        /// 让 InDesign 匹配到不可用的「(OTF)」CFF 变体而判缺失。
        static func fontType(_ desc: CTFontDescriptor) -> String {
            guard let raw = CTFontDescriptorCopyAttribute(desc, kCTFontFormatAttribute) as? NSNumber else {
                return "OpenTypeCFF"
            }
            switch raw.int32Value {
            case 1: return "OpenTypeCID"   // OpenTypePostScript（CID-keyed CJK 系统字体）
            case 2: return "OpenTypeTT"    // OpenTypeTrueType
            case 3: return "TrueType"
            case 4: return "Type1"         // PostScript Type1
            default: return "OpenTypeCFF"
            }
        }

        /// 「家族名 + 样式名」连写拆成 (家族, 样式)——InDesign 按家族名匹配已装字体，
        /// 样式走 FontStyle。只在末词是已知字重/样式词时才拆，"Neue"/"SC" 等家族词不动。
        static func splitFont(_ name: String) -> (String, String) {
            let styleWords: Set<String> = [
                "Thin", "Ultralight", "UltraLight", "Extralight", "ExtraLight", "Light",
                "Regular", "Normal", "Medium", "Semibold", "SemiBold", "Demibold", "DemiBold",
                "Bold", "Heavy", "Black", "Italic", "Oblique"
            ]
            let parts = name.split(separator: " ").map(String.init)
            if parts.count >= 2, let last = parts.last, styleWords.contains(last) {
                return (parts.dropLast().joined(separator: " "), last)
            }
            return (name, "Regular")
        }

        mutating func registerParagraphStyle(_ style: ParagraphStyle) {
            // Project styles are token-resolved by ID. Export-only styles (TOC levels)
            // are already derived from a resolved base and do not exist in the project
            // library; resolving those by ID would silently fall back to `.body`.
            guard !paragraphStyles.contains(where: { $0.id == style.id }) else { return }
            let resolved = project.styles.paragraphStyles.contains(where: { $0.id == style.id })
                ? project.styles.paragraphStyle(id: style.id)
                : style
            paragraphStyles.append(resolved)
            _ = color(textColorHex(project.resolvedColorHex(resolved.colorToken)))
            if let cf = resolved.compositeFont, !cf.isEmpty {
                compositeFontStyleIds.append(resolved.id)
                // 按枚举固定顺序遍历，而非字典自然序——字典迭代顺序非确定，会让
                // Fonts.xml 的家族顺序每次导出都变（golden-file 回归对不上）。
                for cls in CompositeFontClass.allCases {
                    if let m = cf[cls] { font(m.fontName) }
                }
                font(resolved.fontName)
            } else {
                font(resolved.fontName)
            }
        }

        func resolvedStyle(id: String?) -> ParagraphStyle {
            project.styles.paragraphStyle(id: id ?? StyleID.body.rawValue)
        }

        static func normalizeHex(_ hex: String) -> String {
            var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if s.hasPrefix("#") { s.removeFirst() }
            if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
            return s.count == 6 ? s : "000000"
        }
    }

}
