import CoreText
import Foundation
import LayoutDCore

extension LayoutContext {
    /// Validates an advisory layout plan against the rules the renderer relies on.
    /// Returns human-readable failure reasons; an empty array means the plan is
    /// safe to render. Kept pure so it is independently testable.
    func planValidationFailures(_ plan: LayoutPlan) -> [String] {
        var failures: [String] = []
        let epsilon = 0.001
        let blockIds = Set(plan.blocks.map(\.id))

        for (index, block) in plan.blocks.enumerated() {
            let frame = block.frame
            let label = "块 \(index + 1)"

            if frame.width <= 0 || frame.height <= 0 {
                failures.append("\(label) 尺寸非正")
            }
            if frame.x < -epsilon || frame.y < -epsilon
                || frame.x + frame.width > 1 + epsilon
                || frame.y + frame.height > 1 + epsilon {
                failures.append("\(label) 超出页面归一化范围")
            }

            switch block.contentReference {
            case .paragraph(let id):
                if findParagraph(id: id) == nil {
                    failures.append("\(label) 引用了不存在的段落")
                }
            case .asset(let id):
                if !project.assets.contains(where: { $0.id == id }) {
                    failures.append("\(label) 引用了不存在的素材")
                }
            case .storyRange(let storyId, let startId, let endId):
                if let story = findStory(id: storyId) {
                    let ids = Set(story.paragraphs.map(\.id))
                    if !ids.contains(startId) || !ids.contains(endId) {
                        failures.append("\(label) 的文本范围端点不在该 story 内")
                    }
                } else {
                    failures.append("\(label) 引用了不存在的 story")
                }
            case .generated:
                break
            }

            if let next = block.nextThreadedBlockId, !blockIds.contains(next) {
                failures.append("\(label) 的后继线程块不在本计划内")
            }
            if let prev = block.previousThreadedBlockId, !blockIds.contains(prev) {
                failures.append("\(label) 的前驱线程块不在本计划内")
            }
            
            // 2. Check component roles
            if block.kind == .component {
                if !isApprovedComponentRole(block.role) {
                    failures.append("\(label) 的组件角色 \(block.role) 未在组件样式库中定义")
                }
            }
            
            // 3. Check custom color overrides (must be valid hex or approved token ID)
            if let bg = block.backgroundColorHex {
                if !isValidColorValue(bg) {
                    failures.append("\(label) 的背景色引用了未批准的 Token 或无效颜色值 \(bg)")
                }
            }
            if let stroke = block.strokeColorHex {
                if !isValidColorValue(stroke) {
                    failures.append("\(label) 的描边色引用了未批准的 Token 或无效颜色值 \(stroke)")
                }
            }
            if let txt = block.textColorHex {
                if !isValidColorValue(txt) {
                    failures.append("\(label) 的文字颜色引用了未批准的 Token 或无效颜色值 \(txt)")
                }
            }
        }

        // 4. 字体合规：批准 = 本机已装（任何字体形态：family/显示名/PostScript/本地化名）。
        // 用户 2026-06-24 决定不再维护手写白名单——装了的字体就能用，没装的（拼错/缺字体）才拒。
        for style in project.styles.paragraphStyles {
            if !Self.isFontInstalled(style.fontName) {
                failures.append("样式 \(style.displayName) 使用了未安装字体 \(style.fontName)")
            }
            if let cf = style.compositeFont {
                for (cls, mapping) in cf {
                    if !Self.isFontInstalled(mapping.fontName) {
                        failures.append("样式 \(style.displayName) 的 \(cls.rawValue) 分支使用了未安装字体 \(mapping.fontName)")
                    }
                }
            }
        }

        return failures
    }

    /// 本机已装字体的全部名字形态（family / 显示名 / PostScript / 本地化中文名），构建一次。
    static let installedFontNames: Set<String> = {
        var set = Set<String>()
        let collection = CTFontCollectionCreateFromAvailableFonts(nil)
        let descriptors = (CTFontCollectionCreateMatchingFontDescriptors(collection) as? [CTFontDescriptor]) ?? []
        for d in descriptors {
            for key in [kCTFontFamilyNameAttribute, kCTFontDisplayNameAttribute, kCTFontNameAttribute] {
                if let s = CTFontDescriptorCopyAttribute(d, key) as? String { set.insert(s) }
            }
            let font = CTFontCreateWithFontDescriptor(d, 12, nil)
            if let loc = CTFontCopyLocalizedName(font, kCTFontFamilyNameKey, nil) as String? { set.insert(loc) }
        }
        return set
    }()

    /// 字体是否本机已装。接受 family / PostScript / 本地化名等任意形态；
    /// 也接受「家族名+字重」（如 "Heiti SC Medium"）——去掉末尾字重词后家族仍命中即可。
    static func isFontInstalled(_ name: String) -> Bool {
        if installedFontNames.contains(name) { return true }
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            let family = parts.dropLast().joined(separator: " ")
            if installedFontNames.contains(family) { return true }
        }
        return false
    }

    func isValidColorValue(_ val: String) -> Bool {
        let clean = val.trimmingCharacters(in: .whitespacesAndNewlines)
        // Accept any round-trippable PrintColor storage form: `#RRGGBB` / `#RGB` /
        // bare hex, and — crucially — the print-native `cmyk(C,M,Y,K)` form. This
        // is the exact vocabulary the app writes into color fields, so a
        // CMYK-picked color no longer trips validation and gets the whole page's
        // frozen plan discarded (which was silently regenerating frame ids and
        // dropping both the selection and the CMYK color).
        if PrintColor(string: clean) != nil {
            return true
        }
        // Also accept an approved style color token id.
        if project.styles.colorHex(clean) != nil {
            return true
        }
        return false
    }

    func isApprovedComponentRole(_ role: String) -> Bool {
        let cleanRole = role.lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        
        let builtInRoles: Set<String> = [
            "callout", "table", "footnotedivider", "footnote", "sidenote", "caption", "knowledgecard", "datatable", "figurecaption", "runningheader"
        ]
        if builtInRoles.contains(cleanRole) {
            return true
        }
        
        let approvedIds = project.styles.safeComponentStyles.flatMap {
            [$0.id, $0.frameKind.rawValue]
        }.map {
            $0.lowercased()
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: "_", with: "")
        }
        return approvedIds.contains(cleanRole)
    }

    mutating func applyPlanIfPresent() {
        let actualPageNumber = currentAbsolutePageNumber
        guard let plans = project.appliedLayoutPlans,
              let plan = plans[actualPageNumber] else {
            return
        }

        // AI/template plans are advisory: the engine validates them before
        // rendering. An invalid plan is rejected (falling back to deterministic
        // flow on this page) and surfaced as a preflight issue, rather than
        // producing broken frames. This is the "engine decides" guarantee.
        let failures = planValidationFailures(plan)
        guard failures.isEmpty else {
            issues.append(
                LayoutIssue(
                    severity: .warning,
                    message: "第 \(actualPageNumber) 页的版式计划无效，已回退到自动排版：\(failures.joined(separator: "；"))",
                    category: .layout,
                    suggestedFix: "检查该页 LayoutPlan 的块坐标、尺寸和内容引用是否有效。",
                    pageNumber: currentPage.number
                )
            )
            return
        }

        let pageSize = project.pageSetup.pageSize

        for block in plan.blocks {
            let rect = Rect(
                x: block.frame.x * pageSize.width,
                y: block.frame.y * pageSize.height,
                width: block.frame.width * pageSize.width,
                height: block.frame.height * pageSize.height
            )
            
            let kind: PageFrameKind
            switch block.kind {
            case .text: kind = .text
            case .image: kind = .image
            case .caption: kind = .caption
            case .component: kind = .callout
            case .rectangle: kind = .rectangle
            case .line: kind = .line
            }

            let textToPlace: String
            if block.previousThreadedBlockId != nil {
                textToPlace = threadedRemainingText[block.id] ?? ""
                threadedRemainingText.removeValue(forKey: block.id)
            } else {
                switch block.contentReference {
                case .asset(_):
                    textToPlace = ""
                case .generated(let str):
                    textToPlace = str
                case .paragraph(let paragraphId):
                    if let paragraph = findParagraph(id: paragraphId) {
                        textToPlace = paragraph.text
                        placedParagraphIds.insert(paragraphId)
                    } else {
                        textToPlace = ""
                    }
                case .storyRange(let storyId, let startId, let endId):
                    textToPlace = collectParagraphTexts(storyId: storyId, startId: startId, endId: endId)
                }
            }

            let styleId: String?
            if block.kind == .text {
                styleId = StyleID.body.rawValue
            } else if block.kind == .caption {
                styleId = StyleID.caption.rawValue
            } else if block.kind == .component {
                styleId = StyleID.callout.rawValue
            } else {
                styleId = nil
            }
            
            let resolvedStyle = styleId != nil ? project.styles.paragraphStyle(id: styleId!) : ParagraphStyle.body
            let normalizedTextToPlace = normalizedText(textToPlace)

            var sourceParagraphId: UUID? = nil
            var blockRuns: [InlineRun]? = nil
            if case .paragraph(let paragraphId) = block.contentReference {
                sourceParagraphId = paragraphId
                if let paragraph = findParagraph(id: paragraphId),
                   let runs = paragraph.inlineRuns {
                    blockRuns = InlineRun.mapRuns(runs, from: paragraph.text, to: normalizedTextToPlace)
                }
            }

            let content: FrameContent
            if block.kind == .rectangle || block.kind == .line {
                // Shapes carry no text/image; they render from fill/stroke alone.
                content = .empty
            } else if case .asset(let assetId) = block.contentReference {
                content = .asset(assetId)
            } else {
                if block.kind == .text && (block.nextThreadedBlockId != nil || block.previousThreadedBlockId != nil) {
                    let fittedText = fittingPrefix(of: normalizedTextToPlace, style: resolvedStyle, maxHeight: rect.height, width: rect.width, x: rect.x, y: rect.y, inlineRuns: blockRuns)
                    content = .text(fittedText)
                    if let nextId = block.nextThreadedBlockId {
                        let remaining = String(normalizedTextToPlace.dropFirst(fittedText.count)).trimmedForLayout
                        if !remaining.isEmpty {
                            threadedRemainingText[nextId] = remaining
                        }
                    }
                } else {
                    content = .text(normalizedTextToPlace)
                }
            }
            
            let imageRects = getImageRectsOnCurrentPage()
            let overlaps = imageRects.filter { $0.intersects(rect) }
            
            var blockWrapMode: AssetWrapMode? = nil
            if case .asset(let assetId) = block.contentReference,
               let asset = project.assets.first(where: { $0.id == assetId }) {
                blockWrapMode = asset.effectiveWrapMode
            } else if kind == .caption {
                if case .paragraph(let paragraphId) = block.contentReference,
                   let paragraph = findParagraph(id: paragraphId) {
                    for assetId in paragraph.anchoredAssetIds {
                        if let asset = project.assets.first(where: { $0.id == assetId }),
                           asset.effectiveWrapMode == .underlay {
                            blockWrapMode = .underlay
                            break
                        }
                    }
                }
            }

            currentPage.frames.append(PageFrame(
                id: block.id,
                kind: kind,
                rect: rect,
                styleId: styleId,
                content: content,
                backgroundColorHex: block.backgroundColorHex,
                strokeColorHex: block.strokeColorHex,
                strokeWidth: block.strokeWidth,
                textColorHex: block.textColorHex,
                sourceParagraphId: sourceParagraphId,
                maskShape: block.maskShape,
                exclusionRects: overlaps.isEmpty ? nil : overlaps,
                wrapMode: blockWrapMode
            ))
        }
        
        if !plan.blocks.isEmpty || plan.reservesBlankPage {
            advanceToNextPage()
        }
    }

    func findParagraph(id: UUID) -> Paragraph? {
        for section in project.sections {
            for story in section.stories {
                if let paragraph = story.paragraphs.first(where: { $0.id == id }) {
                    return paragraph
                }
            }
        }
        return nil
    }

    func findStory(id: UUID) -> Story? {
        for section in project.sections {
            if let story = section.stories.first(where: { $0.id == id }) {
                return story
            }
        }
        return nil
    }

    mutating func collectParagraphTexts(storyId: UUID, startId: UUID, endId: UUID) -> String {
        guard let story = findStory(id: storyId) else {
            return ""
        }
        
        var collecting = false
        var texts: [String] = []
        
        for paragraph in story.paragraphs {
            if paragraph.id == startId {
                collecting = true
            }
            if collecting {
                texts.append(paragraph.text)
                placedParagraphIds.insert(paragraph.id)
            }
            if paragraph.id == endId {
                break
            }
        }
        
        return texts.joined(separator: "\n")
    }
}

extension LayoutPlan {
    var reservesBlankPage: Bool {
        guard blocks.isEmpty else { return false }
        if notes.contains(where: { $0.contains("空白页") }) {
            return true
        }
        return marginOverride == nil
            && columnsOverride == nil
            && showHeadersFooters == nil
    }
}
