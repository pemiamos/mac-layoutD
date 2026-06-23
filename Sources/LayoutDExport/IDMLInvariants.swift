import Foundation
import CoreText

/// 灌版打包前的“不变量断言闸”。
///
/// 背景（见 .ai/DECISIONS.md 2026-06-23）：我们翻过车的三个 CJK 保真 bug——着重号不显示、
/// 脚注变豆腐、CJK 粗/斜体变粉色——名字全都合规范，病根是 InDesign 渲染时**偷偷要求一个
/// “搭档属性”**。任何规范（IDML schema / 脚本 API）都只逐属性校验，不编码这种跨属性前置条件。
/// 所以把这些**只能靠 InDesign 实测踩出来的规则**锁成硬检查，作为回归护栏：以后改代码再撞同样
/// 的坑会在打包前当场报错，而不是等用户在 InDesign 里发现。
///
/// 校验对象是“实际要打包进 IDML 的 XML 字符串”（`files` 字典），而非构建逻辑——确保验证的就是
/// 出厂内容，与产出它的代码路径解耦。Story XML 用 Foundation `XMLParser` 走，正确处理脚注
/// `ParagraphStyleRange` 嵌在正文 `ParagraphStyleRange` 内的情况（正则做不到）。
public struct IDMLInvariantViolation: Equatable, CustomStringConvertible {
    /// 出问题的包内部件路径，如 `Stories/Story_x.xml`。
    public let part: String
    /// 规则名（稳定标识，便于测试/排查）。
    public let rule: String
    /// 人话说明。
    public let detail: String

    public var description: String { "[\(rule)] \(part): \(detail)" }
}

public enum IDMLInvariants {
    /// CJK / World-Ready 段落排版器白名单。着重号、避头尾等 CJK 特性只在这些排版器下渲染。
    /// 经真·InDesign 2026 存盘比对：CJK 排版器真值是 `HL Composer J`（含 "Composer J"）；
    /// `HL Composer Optyca` 其实是**拉丁**段落排版器，故不在白名单。排版器真值挂在段落样式
    /// 定义（Styles.xml）与文档 `<TextDefault>`（Preferences.xml）上，不在 Story 段落内联。
    static let worldReadyComposerTokens = ["Composer J", "Japanese"]

    static let noParagraphStyle = "ParagraphStyle/$ID/[No paragraph style]"

    /// 对组装好的包部件做断言。返回所有违例（空数组 = 通过）。
    /// 纯函数、确定性、无外部依赖——可单测、不引入构建脆性。
    public static func check(files: [String: String]) -> [IDMLInvariantViolation] {
        var violations: [IDMLInvariantViolation] = []
        // 排版器真值挂在段落样式上：先解析出哪些样式是 World-Ready，供 Story 解析时跨部件查。
        let worldReadyStyles = worldReadyParagraphStyles(files: files)
        for (part, xml) in files.sorted(by: { $0.key < $1.key }) {
            if part.hasPrefix("Stories/") || part == "XML/BackingStory.xml" {
                violations += checkStory(part: part, xml: xml, worldReadyStyles: worldReadyStyles)
            }
        }
        violations += checkFontReferences(files: files)
        violations += checkFontWeights(files: files)
        return violations
    }

    // MARK: - 排版器解析（跨部件：Styles.xml + Preferences TextDefault）

    /// 解析 Styles.xml 的每个 `<ParagraphStyle>`，结合 Preferences 的 `<TextDefault Composer=...>`
    /// 文档默认，算出哪些段落样式（按 Self 引用，如 `ParagraphStyle/body`）是 World-Ready。
    /// 样式自带 `Composer` 时以自身为准；没带则继承文档默认。
    static func worldReadyParagraphStyles(files: [String: String]) -> Set<String> {
        let docDefaultWorldReady: Bool = {
            guard let prefs = files["Resources/Preferences.xml"],
                  let textDefault = matches(of: "<TextDefault\\b[^>]*>", in: prefs, group: 0).first,
                  let composer = matches(of: "\\bComposer=\"([^\"]*)\"", in: textDefault, group: 1).first
            else { return false }
            return isWorldReadyComposer(composer)
        }()

        guard let styles = files["Resources/Styles.xml"] else { return [] }
        var result = Set<String>()
        for tag in matches(of: "<ParagraphStyle\\b[^>]*", in: styles, group: 0) {
            guard let self_ = matches(of: "\\bSelf=\"([^\"]*)\"", in: tag, group: 1).first else { continue }
            let ownComposer = matches(of: "\\bComposer=\"([^\"]*)\"", in: tag, group: 1).first
            let worldReady = ownComposer.map(isWorldReadyComposer) ?? docDefaultWorldReady
            if worldReady { result.insert(self_) }
        }
        return result
    }

    static func isWorldReadyComposer(_ composer: String) -> Bool {
        worldReadyComposerTokens.contains { composer.contains($0) }
    }

    // MARK: - Story 级断言（KentenKind / 脚注豆腐 / CJK 粗斜体）

    private static func checkStory(part: String, xml: String, worldReadyStyles: Set<String>) -> [IDMLInvariantViolation] {
        let walker = StoryInvariantWalker(part: part, worldReadyStyles: worldReadyStyles)
        let parser = XMLParser(data: Data(xml.utf8))
        parser.shouldProcessNamespaces = false
        parser.delegate = walker
        parser.parse()
        return walker.violations
    }

    // MARK: - 字体引用完整性

    /// 每个被引用的 `<AppliedFont>` 都必须在 Fonts.xml 里有对应声明（`FontFamily` / `Font` /
    /// `CompositeFont`），否则 InDesign 找不到字体→替代字形→视觉上是粉色/豆腐。
    private static func checkFontReferences(files: [String: String]) -> [IDMLInvariantViolation] {
        guard let fontsXML = files["Resources/Fonts.xml"] else { return [] }

        var declared = Set<String>()
        for tag in ["FontFamily", "Font", "CompositeFont"] {
            for name in attributeValues(of: "Name", inElement: tag, xml: fontsXML) {
                declared.insert(name)
            }
        }

        var violations: [IDMLInvariantViolation] = []
        for (part, xml) in files.sorted(by: { $0.key < $1.key }) {
            for referenced in appliedFontValues(in: xml) where !declared.contains(referenced) {
                violations.append(IDMLInvariantViolation(
                    part: part,
                    rule: "applied-font-undeclared",
                    detail: "AppliedFont=\"\(referenced)\" 未在 Fonts.xml 中声明（FontFamily/Font/CompositeFont），"
                        + "InDesign 会用替代字形→粉色/豆腐。"
                ))
            }
        }
        return violations
    }

    // MARK: - 轻量字符串提取（无嵌套，正则足够稳）

    /// 取 `<AppliedFont type="string">值</AppliedFont>` 中的值。
    private static func appliedFontValues(in xml: String) -> [String] {
        matches(of: "<AppliedFont[^>]*>([^<]*)</AppliedFont>", in: xml, group: 1)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 取某元素某属性的所有值，如 `<FontFamily ... Name="X">` 的 X。
    private static func attributeValues(of attr: String, inElement element: String, xml: String) -> [String] {
        matches(of: "<\(element)\\b[^>]*?\\b\(attr)=\"([^\"]*)\"", in: xml, group: 1)
    }

    private static func matches(of pattern: String, in text: String, group: Int) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap {
            let r = $0.range(at: group)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
    }

    /// 是否含 CJK（统一表意文字 / 假名 / CJK 标点 / 扩展 A / 全角）。
    static func containsCJK(_ s: String) -> Bool {
        s.unicodeScalars.contains { scalar in
            let v = scalar.value
            return (0x3000...0x303F).contains(v)   // CJK 标点
                || (0x3040...0x30FF).contains(v)   // 平/片假名
                || (0x3400...0x4DBF).contains(v)   // 扩展 A
                || (0x4E00...0x9FFF).contains(v)   // 基本区
                || (0xF900...0xFAFF).contains(v)   // 兼容表意
                || (0xFF00...0xFFEF).contains(v)   // 全角/半角
                || (0x20000...0x2A6DF).contains(v) // 扩展 B
        }
    }

    /// 规则⑤：通过 CoreText 动态检查所有物理字体的字重存在性（防范 silent Helvetica fallback 豆腐）。
    private static func checkFontWeights(files: [String: String]) -> [IDMLInvariantViolation] {
        guard let fontsXML = files["Resources/Fonts.xml"] else { return [] }

        struct FontPair: Hashable {
            let family: String
            let style: String
        }
        var fontPairs = Set<FontPair>()

        // 1. 提取物理字体中的 (family, style)
        // 比如：<Font FontFamily="PingFang SC" FontStyleName="Regular" ... />
        let fontPattern = "<Font\\b[^>]*?\\bFontFamily=\"([^\"]*)\"[^>]*?\\bFontStyleName=\"([^\"]*)\""
        if let re = try? NSRegularExpression(pattern: fontPattern, options: [.dotMatchesLineSeparators]) {
            let ns = fontsXML as NSString
            re.enumerateMatches(in: fontsXML, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                guard let m = match else { return }
                let family = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                let style = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !family.isEmpty && !style.isEmpty {
                    fontPairs.insert(FontPair(family: family, style: style))
                }
            }
        }

        // 2. 提取复合字体 Entry 中的 (family, style)
        // 比如：<CompositeFontEntry FontStyle="Regular" ...><Properties><AppliedFont type="string">方正兰亭细黑简体</AppliedFont></Properties></CompositeFontEntry>
        let compositePattern = "<CompositeFontEntry\\b[^>]*?\\bFontStyle=\"([^\"]*)\"[^>]*?>\\s*<Properties>\\s*<AppliedFont[^>]*>([^<]*)</AppliedFont>"
        if let re = try? NSRegularExpression(pattern: compositePattern, options: [.dotMatchesLineSeparators]) {
            let ns = fontsXML as NSString
            re.enumerateMatches(in: fontsXML, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                guard let m = match else { return }
                let style = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                let family = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !family.isEmpty && !style.isEmpty {
                    fontPairs.insert(FontPair(family: family, style: style))
                }
            }
        }

        var violations: [IDMLInvariantViolation] = []
        for pair in fontPairs.sorted(by: { $0.family < $1.family || ($0.family == $1.family && $0.style < $1.style) }) {
            let family = pair.family
            let style = pair.style
            
            // 跳过复合字体（CF_ 开头）以及 InDesign 占位/系统标识（$ID/ 等）
            if family.hasPrefix("CF_") || family.hasPrefix("$ID/") {
                continue
            }

            // 使用 CoreText API 校验字重存在性
            let attrs: [CFString: Any] = [
                kCTFontFamilyNameAttribute: family as CFString,
                kCTFontStyleNameAttribute: style as CFString
            ]
            let desc = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
            let matches = CTFontDescriptorCreateMatchingFontDescriptors(desc, nil) as? [CTFontDescriptor] ?? []

            if matches.isEmpty {
                violations.append(IDMLInvariantViolation(
                    part: "Resources/Fonts.xml",
                    rule: "font-name-needs-valid-weight",
                    detail: "字体 \"\(family)\" 的字重 \"\(style)\" 在系统已安装字体中不存在，CoreText/InDesign 会发生回退至 Helvetica 默认字体的豆腐现象。"
                ))
            }
        }

        return violations
    }
}

/// 走一遍 Story XML，维护 `ParagraphStyleRange` 栈与脚注深度，按规则记违例。
private final class StoryInvariantWalker: NSObject, XMLParserDelegate {
    struct PSRFrame {
        let composer: String?
        let paragraphStyle: String?
        let inFootnote: Bool
        var content: String = ""
    }

    let part: String
    let worldReadyStyles: Set<String>
    var violations: [IDMLInvariantViolation] = []
    private var psrStack: [PSRFrame] = []
    private var footnoteDepth = 0
    private var currentCSRContent: String?      // 非 nil 表示正在 CharacterStyleRange 内
    private var currentCSRFontStyle: String?

    init(part: String, worldReadyStyles: Set<String>) {
        self.part = part
        self.worldReadyStyles = worldReadyStyles
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attrs: [String: String]) {
        switch elementName {
        case "ParagraphStyleRange":
            // 真值属性名是 Composer（旧代码错用 AppliedComposer，InDesign 会忽略）。
            // 段落内联通常没有；排版器主要由 AppliedParagraphStyle 解析（见 worldReadyStyles）。
            psrStack.append(PSRFrame(
                composer: attrs["Composer"],
                paragraphStyle: attrs["AppliedParagraphStyle"],
                inFootnote: footnoteDepth > 0
            ))
        case "Footnote":
            footnoteDepth += 1
        case "CharacterStyleRange":
            currentCSRContent = ""
            currentCSRFontStyle = attrs["FontStyle"]
            // 规则①：着重号必须配 CJK/World-Ready 排版器，否则 KentenKind 被静默忽略。
            // 排版器真值挂在段落样式上：段落自带 Composer 时以其为准；否则看所引样式是否 WR。
            if let kenten = attrs["KentenKind"], !isNoneKenten(kenten) {
                let frame = psrStack.last
                let ownComposerWR = frame?.composer.map(IDMLInvariants.isWorldReadyComposer) ?? false
                let styleWR = frame?.paragraphStyle.map(worldReadyStyles.contains) ?? false
                if !ownComposerWR && !styleWR {
                    violations.append(IDMLInvariantViolation(
                        part: part,
                        rule: "kenten-needs-world-ready-composer",
                        detail: "CharacterStyleRange 带 KentenKind=\"\(kenten)\"，但所在段落样式 "
                            + "\(frame?.paragraphStyle.map { "\"\($0)\"" } ?? "?") 的排版器非 World-Ready"
                            + "（需段落样式 Composer=\"HL Composer J\" 或文档 TextDefault）→着重号不渲染。"
                    ))
                }
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentCSRContent != nil { currentCSRContent! += string }
        if !psrStack.isEmpty { psrStack[psrStack.count - 1].content += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        switch elementName {
        case "CharacterStyleRange":
            // 规则③：CJK 粗/斜体必须走 FauxBold/Skew，不能用 FontStyle="Bold"/"Italic"——
            // 后者要求 Fonts.xml 里真有同名字重资源，CJK 字体通常没有→替代字形（粉色）。
            if let fs = currentCSRFontStyle, isBoldOrItalic(fs),
               let content = currentCSRContent, IDMLInvariants.containsCJK(content) {
                violations.append(IDMLInvariantViolation(
                    part: part,
                    rule: "cjk-faux-not-fontstyle",
                    detail: "CharacterStyleRange 含 CJK 且用 FontStyle=\"\(fs)\"，CJK 字体多无此字重资源→粉色替代字形；"
                        + "应改用 FauxBold/Skew。"
                ))
            }
            currentCSRContent = nil
            currentCSRFontStyle = nil
        case "ParagraphStyleRange":
            let frame = psrStack.removeLast()
            // 规则②：脚注正文段落不能挂 [No paragraph style]——它没有中文复合字体，CJK 变豆腐。
            if frame.inFootnote,
               frame.paragraphStyle == IDMLInvariants.noParagraphStyle,
               IDMLInvariants.containsCJK(frame.content) {
                violations.append(IDMLInvariantViolation(
                    part: part,
                    rule: "footnote-needs-cjk-style",
                    detail: "脚注正文段落用 \(IDMLInvariants.noParagraphStyle) 且含 CJK，该样式无中文复合字体→脚注豆腐。"
                ))
            }
            // 把已结束段落的文本并入父段落（脚注算父正文段的一部分），保证父段 CJK 判定不丢。
            if !psrStack.isEmpty { psrStack[psrStack.count - 1].content += frame.content }
        case "Footnote":
            footnoteDepth -= 1
        default:
            break
        }
    }

    private func isNoneKenten(_ v: String) -> Bool {
        let n = v.lowercased()
        return n == "none" || n == "kentennone" || n.isEmpty
    }

    private func isBoldOrItalic(_ v: String) -> Bool {
        let n = v.lowercased()
        return n.contains("bold") || n.contains("italic") || n.contains("oblique")
    }
}
