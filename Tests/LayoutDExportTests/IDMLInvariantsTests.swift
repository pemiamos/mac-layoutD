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

    // MARK: - 规则①：着重号需 World-Ready 排版器

    func testKentenWithWorldReadyComposerPasses() {
        let xml = story("""
        <ParagraphStyleRange AppliedParagraphStyle="ParagraphStyle/body" AppliedComposer="$ID/HL Composer Optyca">
        <CharacterStyleRange KentenKind="KentenSesameDot"><Content>着重</Content></CharacterStyleRange>
        </ParagraphStyleRange>
        """)
        XCTAssertTrue(IDMLInvariants.check(files: xml).isEmpty)
    }

    func testKentenWithLatinComposerFails() {
        let xml = story("""
        <ParagraphStyleRange AppliedParagraphStyle="ParagraphStyle/body" AppliedComposer="$ID/HL Composer">
        <CharacterStyleRange KentenKind="KentenSesameDot"><Content>着重</Content></CharacterStyleRange>
        </ParagraphStyleRange>
        """)
        XCTAssertEqual(rules(IDMLInvariants.check(files: xml)), ["kenten-needs-world-ready-composer"])
    }

    func testKentenWithMissingComposerFails() {
        let xml = story("""
        <ParagraphStyleRange AppliedParagraphStyle="ParagraphStyle/body">
        <CharacterStyleRange KentenKind="KentenSesameDot"><Content>着重</Content></CharacterStyleRange>
        </ParagraphStyleRange>
        """)
        XCTAssertEqual(rules(IDMLInvariants.check(files: xml)), ["kenten-needs-world-ready-composer"])
    }

    func testKentenNoneIsNotFlagged() {
        let xml = story("""
        <ParagraphStyleRange AppliedParagraphStyle="ParagraphStyle/body" AppliedComposer="$ID/HL Composer">
        <CharacterStyleRange KentenKind="KentenNone"><Content>普通</Content></CharacterStyleRange>
        </ParagraphStyleRange>
        """)
        XCTAssertTrue(IDMLInvariants.check(files: xml).isEmpty)
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
}
