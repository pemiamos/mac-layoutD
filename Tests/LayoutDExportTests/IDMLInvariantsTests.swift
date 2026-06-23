import XCTest
@testable import LayoutDExport

/// 不变量断言闸（IDMLInvariants）的单测：每条规则都覆盖“好/坏”两面。
/// 直接喂合成 XML 字符串，校验的就是出厂内容，与导出构建逻辑解耦。
final class IDMLInvariantsTests: XCTestCase {

    private func story(_ inner: String) -> [String: String] {
        ["Stories/Story_x.xml": """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <idPkg:Story xmlns:idPkg="http://ns.adobe.com/AdobeInDesign/idml/1.0/packaging" DOMVersion="16.0">
        \t<Story Self="x">
        \(inner)
        \t</Story>
        </idPkg:Story>
        """]
    }

    private func rules(_ vs: [IDMLInvariantViolation]) -> Set<String> { Set(vs.map(\.rule)) }

    /// 着重号 Story（段落引用某样式），可附带 Styles.xml 段落样式与 Preferences TextDefault。
    /// 排版器真值挂在样式上，故 rule① 需跨部件解析。
    private func kentenFiles(styleRef: String = "ParagraphStyle/body",
                             styleComposer: String?? = .some("HL Composer J"),
                             textDefaultComposer: String? = nil,
                             kentenKind: String = "KentenSesameDot") -> [String: String] {
        var files = story("""
        <ParagraphStyleRange AppliedParagraphStyle="\(styleRef)">
        <CharacterStyleRange KentenKind="\(kentenKind)"><Content>着重</Content></CharacterStyleRange>
        </ParagraphStyleRange>
        """)
        // styleComposer: 外层 .none = 不生成该样式；内层 .none = 样式存在但无 Composer 属性。
        if case let .some(composer) = styleComposer {
            let attr = composer.map { " Composer=\"\($0)\"" } ?? ""
            files["Resources/Styles.xml"] = "<idPkg:Styles><RootParagraphStyleGroup>"
                + "<ParagraphStyle Self=\"\(styleRef)\" Name=\"body\"\(attr)/></RootParagraphStyleGroup></idPkg:Styles>"
        }
        if let td = textDefaultComposer {
            files["Resources/Preferences.xml"] = "<idPkg:Preferences><TextDefault Composer=\"\(td)\"/></idPkg:Preferences>"
        }
        return files
    }

    // MARK: - 规则①：着重号需 World-Ready 排版器（真值：挂在段落样式 / TextDefault 上）

    func testKentenWithWorldReadyStylePasses() {
        let files = kentenFiles(styleComposer: .some("HL Composer J"))
        XCTAssertTrue(IDMLInvariants.check(files: files).isEmpty)
    }

    func testKentenWithLatinStyleFails() {
        // "HL Composer Optyca" 是拉丁排版器，不渲染着重号。
        let files = kentenFiles(styleComposer: .some("HL Composer Optyca"))
        XCTAssertEqual(rules(IDMLInvariants.check(files: files)), ["kenten-needs-world-ready-composer"])
    }

    func testKentenStyleInheritingWorldReadyTextDefaultPasses() {
        // 样式自身无 Composer，但文档 TextDefault 是 World-Ready → 继承通过。
        let files = kentenFiles(styleComposer: .some(.none), textDefaultComposer: "HL Composer J")
        XCTAssertTrue(IDMLInvariants.check(files: files).isEmpty)
    }

    func testKentenWithNoComposerAnywhereFails() {
        let files = kentenFiles(styleComposer: .some(.none))
        XCTAssertEqual(rules(IDMLInvariants.check(files: files)), ["kenten-needs-world-ready-composer"])
    }

    func testKentenWithInlineComposerOnPSRPasses() {
        // 段落自带 Composer（罕见，但合法）→ 以自身为准。
        var files = story("""
        <ParagraphStyleRange AppliedParagraphStyle="ParagraphStyle/body" Composer="HL Composer J">
        <CharacterStyleRange KentenKind="KentenSesameDot"><Content>着重</Content></CharacterStyleRange>
        </ParagraphStyleRange>
        """)
        files["Resources/Styles.xml"] = "<idPkg:Styles></idPkg:Styles>"
        XCTAssertTrue(IDMLInvariants.check(files: files).isEmpty)
    }

    func testKentenNoneIsNotFlagged() {
        let files = kentenFiles(styleComposer: .some("HL Composer Optyca"), kentenKind: "KentenNone")
        XCTAssertTrue(IDMLInvariants.check(files: files).isEmpty)
    }

    // MARK: - 规则②：脚注正文需中文复合字体样式（脚注 PSR 嵌在正文 PSR 内）

    func testFootnoteWithNoParagraphStyleAndCJKFails() {
        let xml = story("""
        <ParagraphStyleRange AppliedParagraphStyle="ParagraphStyle/body" AppliedComposer="$ID/HL Composer Optyca">
        <CharacterStyleRange><Content>正文</Content></CharacterStyleRange>
        <Footnote>
        <ParagraphStyleRange AppliedParagraphStyle="ParagraphStyle/$ID/[No paragraph style]" AppliedComposer="$ID/HL Composer Optyca">
        <CharacterStyleRange><Content>脚注内容</Content></CharacterStyleRange>
        </ParagraphStyleRange>
        </Footnote>
        </ParagraphStyleRange>
        """)
        XCTAssertEqual(rules(IDMLInvariants.check(files: xml)), ["footnote-needs-cjk-style"])
    }

    func testFootnoteWithRealStylePasses() {
        let xml = story("""
        <ParagraphStyleRange AppliedParagraphStyle="ParagraphStyle/body" AppliedComposer="$ID/HL Composer Optyca">
        <CharacterStyleRange><Content>正文</Content></CharacterStyleRange>
        <Footnote>
        <ParagraphStyleRange AppliedParagraphStyle="ParagraphStyle/caption" AppliedComposer="$ID/HL Composer Optyca">
        <CharacterStyleRange><Content>脚注内容</Content></CharacterStyleRange>
        </ParagraphStyleRange>
        </Footnote>
        </ParagraphStyleRange>
        """)
        XCTAssertTrue(IDMLInvariants.check(files: xml).isEmpty)
    }

    func testFootnoteNoParagraphStyleButLatinOnlyNotFlagged() {
        // 纯拉丁脚注用 [No paragraph style] 不豆腐，不应误报。
        let xml = story("""
        <ParagraphStyleRange AppliedParagraphStyle="ParagraphStyle/body" AppliedComposer="$ID/HL Composer Optyca">
        <CharacterStyleRange><Content>body</Content></CharacterStyleRange>
        <Footnote>
        <ParagraphStyleRange AppliedParagraphStyle="ParagraphStyle/$ID/[No paragraph style]" AppliedComposer="$ID/HL Composer Optyca">
        <CharacterStyleRange><Content>footnote text</Content></CharacterStyleRange>
        </ParagraphStyleRange>
        </Footnote>
        </ParagraphStyleRange>
        """)
        XCTAssertTrue(IDMLInvariants.check(files: xml).isEmpty)
    }

    // MARK: - 规则③：CJK 粗/斜体走 FauxBold/Skew，不用 FontStyle

    func testCJKWithFontStyleBoldFails() {
        let xml = story("""
        <ParagraphStyleRange AppliedParagraphStyle="ParagraphStyle/body" AppliedComposer="$ID/HL Composer Optyca">
        <CharacterStyleRange FontStyle="Bold"><Content>加粗中文</Content></CharacterStyleRange>
        </ParagraphStyleRange>
        """)
        XCTAssertEqual(rules(IDMLInvariants.check(files: xml)), ["cjk-faux-not-fontstyle"])
    }

    func testLatinWithFontStyleBoldNotFlagged() {
        let xml = story("""
        <ParagraphStyleRange AppliedParagraphStyle="ParagraphStyle/body" AppliedComposer="$ID/HL Composer Optyca">
        <CharacterStyleRange FontStyle="Bold"><Content>BoldLatin</Content></CharacterStyleRange>
        </ParagraphStyleRange>
        """)
        XCTAssertTrue(IDMLInvariants.check(files: xml).isEmpty)
    }

    func testCJKWithFauxBoldPasses() {
        let xml = story("""
        <ParagraphStyleRange AppliedParagraphStyle="ParagraphStyle/body" AppliedComposer="$ID/HL Composer Optyca">
        <CharacterStyleRange FauxBold="true"><Content>加粗中文</Content></CharacterStyleRange>
        </ParagraphStyleRange>
        """)
        XCTAssertTrue(IDMLInvariants.check(files: xml).isEmpty)
    }

    // MARK: - 规则④：AppliedFont 引用完整性

    func testUndeclaredAppliedFontFails() {
        let files: [String: String] = [
            "Resources/Fonts.xml": """
            <Fonts><FontFamily Name="Source Han Serif SC"></FontFamily></Fonts>
            """,
            "Resources/Styles.xml": """
            <Styles><Properties><AppliedFont type="string">Nonexistent Font</AppliedFont></Properties></Styles>
            """
        ]
        XCTAssertEqual(rules(IDMLInvariants.check(files: files)), ["applied-font-undeclared"])
    }

    func testDeclaredAppliedFontPasses() {
        let files: [String: String] = [
            "Resources/Fonts.xml": """
            <Fonts>
            <FontFamily Name="Source Han Serif SC"></FontFamily>
            <CompositeFont Name="CF_body"></CompositeFont>
            </Fonts>
            """,
            "Resources/Styles.xml": """
            <Styles>
            <Properties><AppliedFont type="string">Source Han Serif SC</AppliedFont></Properties>
            <Properties><AppliedFont type="string">CF_body</AppliedFont></Properties>
            </Styles>
            """
        ]
        XCTAssertTrue(IDMLInvariants.check(files: files).isEmpty)
    }

    // MARK: - 整洁通过

    func testCleanStoryHasNoViolations() {
        let xml = story("""
        <ParagraphStyleRange AppliedParagraphStyle="ParagraphStyle/body" AppliedComposer="$ID/HL Composer Optyca">
        <CharacterStyleRange><Content>普通正文</Content></CharacterStyleRange>
        </ParagraphStyleRange>
        """)
        XCTAssertTrue(IDMLInvariants.check(files: xml).isEmpty)
    }

    // MARK: - 规则⑤：通过 CoreText 动态检查字重存在性

    func testInvalidFontWeightFails() {
        let files: [String: String] = [
            "Resources/Fonts.xml": """
            <Fonts>
            <FontFamily Name="Heiti SC">
                <Font FontFamily="Heiti SC" FontStyleName="Regular" PostScriptName="STHeitiSC-Regular" Name="Heiti SC Regular" Status="Installed"/>
            </FontFamily>
            </Fonts>
            """
        ]
        XCTAssertEqual(rules(IDMLInvariants.check(files: files)), ["font-name-needs-valid-weight"])
    }

    func testInvalidCompositeFontWeightFails() {
        let files: [String: String] = [
            "Resources/Fonts.xml": """
            <Fonts>
            <FontFamily Name="Heiti SC"></FontFamily>
            <CompositeFont Name="CF_body">
            <CompositeFontEntry FontStyle="Regular">
                <Properties><AppliedFont type="string">Heiti SC</AppliedFont></Properties>
            </CompositeFontEntry>
            </CompositeFont>
            </Fonts>
            """
        ]
        XCTAssertEqual(rules(IDMLInvariants.check(files: files)), ["font-name-needs-valid-weight"])
    }

    func testValidFontWeightPasses() {
        let files: [String: String] = [
            "Resources/Fonts.xml": """
            <Fonts>
            <FontFamily Name="Heiti SC">
                <Font FontFamily="Heiti SC" FontStyleName="Medium" PostScriptName="STHeitiSC-Medium" Name="Heiti SC Medium" Status="Installed"/>
            </FontFamily>
            <FontFamily Name="PingFang SC">
                <Font FontFamily="PingFang SC" FontStyleName="Regular" PostScriptName="PingFangSC-Regular" Name="PingFang SC Regular" Status="Installed"/>
            </FontFamily>
            <CompositeFont Name="CF_body">
            <CompositeFontEntry FontStyle="Medium">
                <Properties><AppliedFont type="string">Heiti SC</AppliedFont></Properties>
            </CompositeFontEntry>
            <CompositeFontEntry FontStyle="Regular">
                <Properties><AppliedFont type="string">PingFang SC</AppliedFont></Properties>
            </CompositeFontEntry>
            </CompositeFont>
            </Fonts>
            """
        ]
        XCTAssertTrue(IDMLInvariants.check(files: files).isEmpty)
    }
}
