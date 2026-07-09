import Foundation
import LayoutDCore

extension BookProject {
    public mutating func applySpecPack(_ result: SpecPackImportResult, baselineGridCompensate: Double? = nil) {
        let importedTokens = result.tokens
        
        self.styles.tokens = importedTokens
        self.motifs = result.motifs
        
        // 1. Rebuild legacy colors list for backward compatibility
        var legacyColors: [ColorToken] = []
        for colorSet in importedTokens.colors {
            if let hexValue = colorSet.valuesByMode[importedTokens.defaultMode] ?? colorSet.valuesByMode.first?.value {
                legacyColors.append(ColorToken(id: colorSet.id, hex: hexValue))
            }
        }
        self.styles.colors = legacyColors
        
        // Role to StyleID mapping
        let roleStyleIDs: [String: String] = [
            "章名": StyleID.heading1.rawValue,
            "节名": StyleID.heading2.rawValue,
            "正文": StyleID.body.rawValue,
            "抽言": StyleID.pullQuote.rawValue,
            "图注": StyleID.caption.rawValue,
            "开节概述": StyleID.introduction.rawValue,
            "引文": StyleID.bibliography.rawValue
        ]
        
        // 2. Map Paragraph Styles
        var updatedParagraphStyles = self.styles.paragraphStyles
        for idx in updatedParagraphStyles.indices {
            var style = updatedParagraphStyles[idx]
            let styleId = style.id
            
            // 2.1 Standard Design Tokens mapping
            let fsToken = "paragraph.\(styleId).fontSize"
            if let val = importedTokens.scalar(fsToken) {
                style.fontSizeToken = fsToken
                style.fontSize = val
            }
            
            let lhToken = "paragraph.\(styleId).lineHeight"
            if let val = importedTokens.scalar(lhToken) {
                style.lineHeightToken = lhToken
                style.lineHeight = val
            }
            
            let indentToken = "paragraph.\(styleId).firstLineIndent"
            if let val = importedTokens.scalar(indentToken) {
                style.firstLineIndentToken = indentToken
                style.firstLineIndent = val
            }
            
            let beforeToken = "paragraph.\(styleId).spaceBefore"
            if let val = importedTokens.scalar(beforeToken) {
                style.spaceBeforeToken = beforeToken
                style.spaceBefore = val
            }
            
            let afterToken = "paragraph.\(styleId).spaceAfter"
            if let val = importedTokens.scalar(afterToken) {
                style.spaceAfterToken = afterToken
                style.spaceAfter = val
            }
            
            // 2.2 Font mapping via fontResolutions
            // Find role matching this style ID
            if let matchingRole = roleStyleIDs.first(where: { $0.value == styleId })?.key {
                // If there's an explicit font resolution for this role
                let roleFont = result.fontResolutions.first(where: { $0.roleOrAlias == matchingRole })?.resolvedName
                // Or fallback to "正文" font
                let fallbackFont = result.fontResolutions.first(where: { $0.roleOrAlias == "正文" })?.resolvedName
                
                if let resolvedFontName = roleFont ?? fallbackFont {
                    style.fontName = resolvedFontName
                    
                    var compFont = style.compositeFont ?? [:]
                    compFont[.chinese] = CompositeFontMapping(fontName: resolvedFontName, sizeMultiplier: 1.0, baselineOffset: 0.0)
                    
                    if let latinFont = result.fontResolutions.first(where: { $0.roleOrAlias == "西文" })?.resolvedName {
                        compFont[.latin] = CompositeFontMapping(fontName: latinFont, sizeMultiplier: 1.0, baselineOffset: 0.0)
                        compFont[.digit] = CompositeFontMapping(fontName: latinFont, sizeMultiplier: 1.0, baselineOffset: 0.0)
                    }
                    style.compositeFont = compFont
                }
                
                // 2.3 Color mapping
                if let roleColor = result.roleColors[matchingRole] {
                    style.colorToken = roleColor
                }

                // 2.4 Decoration → paragraph accent rule (抽言左侧竖线 / 图注顶部短横 / 标题下划线)
                if let dec = result.roleDecorations[matchingRole], let decColor = dec.color {
                    let mmToPt = 72.0 / 25.4
                    switch dec.type {
                    case "left-rule":
                        style.accentRule = ParagraphAccentRule(
                            edge: .left,
                            colorToken: decColor,
                            width: dec.widthPt ?? 3
                        )
                    case "top-tick", "top-rule", "top-bottom-rules":
                        style.accentRule = ParagraphAccentRule(
                            edge: .top,
                            colorToken: decColor,
                            width: dec.widthPt ?? 2,
                            length: dec.lengthMM.map { $0 * mmToPt }
                        )
                    case "bottom-rule", "underline", "bottom-tick":
                        style.accentRule = ParagraphAccentRule(
                            edge: .bottom,
                            colorToken: decColor,
                            width: dec.widthPt ?? 2,
                            length: dec.lengthMM.map { $0 * mmToPt }
                        )
                    default:
                        break
                    }
                }
            }

            updatedParagraphStyles[idx] = style
        }
        self.styles.paragraphStyles = updatedParagraphStyles
        
        // 3. Map Page Setup
        var setup = self.pageSetup
        var newMargins = setup.margins
        
        let mtToken = "page.margin.top"
        if let val = importedTokens.scalar(mtToken) {
            newMargins.top = val
        }
        let mrToken = "page.margin.right"
        if let val = importedTokens.scalar(mrToken) {
            newMargins.right = val
        }
        let mbToken = "page.margin.bottom"
        if let val = importedTokens.scalar(mbToken) {
            newMargins.bottom = val
        }
        let mlToken = "page.margin.left"
        if let val = importedTokens.scalar(mlToken) {
            newMargins.left = val
        }
        
        setup.margins = newMargins // triggers didSet clearing tokens
        
        // Re-apply tokens
        if importedTokens.scalar(mtToken) != nil { setup.marginTopToken = mtToken }
        if importedTokens.scalar(mrToken) != nil { setup.marginRightToken = mrToken }
        if importedTokens.scalar(mbToken) != nil { setup.marginBottomToken = mbToken }
        if importedTokens.scalar(mlToken) != nil { setup.marginLeftToken = mlToken }
        
        let colsToken = "page.columns"
        if let val = importedTokens.scalar(colsToken) {
            setup.columns = max(1, Int(round(val)))
            setup.columnsToken = colsToken
        }
        
        let gutToken = "page.gutter"
        if let val = importedTokens.scalar(gutToken) {
            setup.gutter = val
            setup.gutterToken = gutToken
        }
        
        let bgToken = "page.baselineGrid"
        if let val = importedTokens.scalar(bgToken) {
            setup.baselineGrid = val
            setup.baselineGridToken = bgToken
        } else if let comp = baselineGridCompensate {
            setup.baselineGrid = comp
            setup.baselineGridToken = nil
        }
        
        // 3.1 Trim size mapping (page.width and page.height)
        let widthToken = "page.width"
        let heightToken = "page.height"
        if let w = importedTokens.scalar(widthToken), let h = importedTokens.scalar(heightToken) {
            let label = "\(Int(round(w / (72.0 / 25.4))))mm x \(Int(round(h / (72.0 / 25.4))))mm"
            setup.pageSize = PageSize(width: w, height: h, label: label)
        }
        
        // 3.2 Layout direction mapping (page.vertical)
        if let vertVal = importedTokens.scalar("page.vertical") {
            setup.layoutDirection = (vertVal == 1.0) ? .vertical : .horizontal
        }

        // 3.3 Page background color
        if importedTokens.colors.contains(where: { $0.id == "paper" }) {
            setup.pageBackgroundColor = "paper"
        }
        
        self.pageSetup = setup
        
        // 4. Map Decorations to ComponentStyle
        var updatedComponentStyles = self.styles.safeComponentStyles
        
        // 4.1 Update .callout (e.g. from "抽言"'s decoration)
        if let calloutDec = result.roleDecorations["抽言"] {
            if let idx = updatedComponentStyles.firstIndex(where: { $0.frameKind == .callout }) {
                var compStyle = updatedComponentStyles[idx]
                if let decColor = calloutDec.color {
                    compStyle.accentColorToken = decColor
                    compStyle.strokeColorToken = decColor
                }
                if calloutDec.type == "left-rule" {
                    compStyle.accentWidth = calloutDec.widthPt ?? 4.0
                    compStyle.strokeWidth = 0.0
                } else if calloutDec.type == "top-bottom-rules" {
                    compStyle.strokeWidth = calloutDec.widthPt ?? 0.8
                    compStyle.accentWidth = 0.0
                }
                updatedComponentStyles[idx] = compStyle
            }
        }
        
        // 4.2 Update .caption (e.g. from "图注"'s decoration)
        if let captionDec = result.roleDecorations["图注"] {
            if let idx = updatedComponentStyles.firstIndex(where: { $0.frameKind == .caption }) {
                var compStyle = updatedComponentStyles[idx]
                if let decColor = captionDec.color {
                    compStyle.accentColorToken = decColor
                    compStyle.strokeColorToken = decColor
                }
                updatedComponentStyles[idx] = compStyle
            }
        }
        
        self.styles.componentStyles = updatedComponentStyles
    }
}
