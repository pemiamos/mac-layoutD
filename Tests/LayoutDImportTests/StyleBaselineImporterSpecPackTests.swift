import LayoutDImport
import XCTest

final class StyleBaselineImporterSpecPackTests: XCTestCase {
    private let installedFonts: Set<String> = [
        "方正兰亭细黑简体",
        "Heiti SC Medium",
        "JiangChengLvDongSong",
        "Georgia",
        "Songti SC"
    ]

    func testImportsSpecPackFixtureAsTokensAndWarnings() throws {
        let result = try StyleBaselineImporter.parseSpecPack(
            jsonData: validSpecPack.data(using: .utf8)!,
            fontAvailability: { self.installedFonts.contains($0) }
        )

        XCTAssertEqual(result.tokens.colorHex("accent"), "#F5C518")
        XCTAssertEqual(result.tokens.scalar("page.columns"), 2)
        XCTAssertEqual(try XCTUnwrap(result.tokens.scalar("page.gutter")), 8 * 72 / 25.4, accuracy: 0.001)
        XCTAssertEqual(result.tokens.scalar("paragraph.heading1.fontSize"), 34)
        XCTAssertEqual(try XCTUnwrap(result.tokens.scalar("paragraph.heading1.lineHeight")), 44.2, accuracy: 0.001)
        XCTAssertEqual(result.tokens.scalar("paragraph.body.firstLineIndent"), 20)
        XCTAssertEqual(result.tokens.scalar("paragraph.pullQuote.fontSize"), 16)
        XCTAssertFalse(result.unsupportedFields.contains("$.roles.章节序号.treatment"))
        XCTAssertEqual(result.motifs.chapterNumber?.fontAlias, "西文")
        XCTAssertEqual(result.motifs.chapterNumber?.resolvedFontName, "Georgia")
        XCTAssertEqual(result.motifs.chapterNumber?.fontSizePt, 200)
        XCTAssertEqual(result.motifs.chapterNumber?.opacity, 0.06)
        XCTAssertEqual(result.motifs.chapterNumber?.layer, "behind")
        XCTAssertEqual(result.motifs.sectionNumber?.style, "西文序号着accent色")
        XCTAssertEqual(result.motifs.header?.rule, "细线通栏")
        XCTAssertEqual(result.roleColors["章名"], "ink")
        XCTAssertEqual(result.roleDecorations["抽言"], SpecPackDecoration(type: "left-rule", color: "accent", widthPt: 3))
        XCTAssertEqual(result.roleDecorations["图注"], SpecPackDecoration(type: "top-tick", color: "accent", lengthMM: 6))
        XCTAssertTrue(result.fontResolutions.contains {
            $0.requestedName == "黑体-简 Medium" && $0.resolvedName == "Heiti SC Medium"
        })
    }

    func testImportsSpecPackV2MotifsLayoutGrammarAndQualityGates() throws {
        let result = try StyleBaselineImporter.parseSpecPack(
            jsonData: validSpecPackV2.data(using: .utf8)!,
            fontAvailability: { self.installedFonts.contains($0) }
        )

        XCTAssertEqual(result.motifs.chapterNumber?.fontAlias, "西文")
        XCTAssertEqual(result.motifs.chapterNumber?.resolvedFontName, "Georgia")
        XCTAssertEqual(result.motifs.chapterNumber?.fontSizePt, 184)
        XCTAssertEqual(result.motifs.chapterNumber?.color, "grayText")
        XCTAssertEqual(result.motifs.chapterNumber?.opacity, 0.07)
        XCTAssertEqual(result.motifs.chapterNumber?.anchor, "chapterStart.topRight")
        XCTAssertEqual(result.motifs.chapterNumber?.layer, "behind")

        XCTAssertEqual(result.motifs.sectionNumber?.style, "westernAccent")
        XCTAssertEqual(result.motifs.sectionNumber?.color, "accent")
        XCTAssertEqual(result.motifs.sectionNumber?.minDigits, 2)
        XCTAssertEqual(result.motifs.sectionNumber?.suffix, " /")

        XCTAssertEqual(result.motifs.header?.fontAlias, "西文")
        XCTAssertEqual(result.motifs.header?.label, "EXPLORE")
        XCTAssertEqual(result.motifs.header?.showChapterTitle, true)
        XCTAssertEqual(result.motifs.header?.showPageNumber, true)
        XCTAssertEqual(result.motifs.captionTick, SpecPackDecoration(type: "top-tick", color: "accent", widthPt: 2, lengthMM: 6))
        XCTAssertEqual(result.motifs.headingRule, SpecPackDecoration(type: "bottom-rule", color: "accent", widthPt: 2, lengthMM: 20))
        XCTAssertEqual(result.motifs.pullQuoteRule, SpecPackDecoration(type: "left-rule", color: "accent", widthPt: 3))

        let grammar = try XCTUnwrap(result.layoutGrammar)
        XCTAssertEqual(grammar.spreadArchetypes.count, 2)
        XCTAssertEqual(grammar.spreadArchetypes[0].id, "text-image-balanced")
        XCTAssertEqual(grammar.spreadArchetypes[0].pages, 2)
        XCTAssertEqual(grammar.spreadArchetypes[0].imageSlots, 1)
        XCTAssertEqual(grammar.spreadArchetypes[1].family, "text-led")
        XCTAssertEqual(grammar.rhythm?.maxSameFamilyRun, 2)
        XCTAssertEqual(grammar.rhythm?.bigImageEveryMinSpreads, 3)
        XCTAssertEqual(grammar.rhythm?.accentEverySpread, true)
        XCTAssertEqual(grammar.rhythm?.seed, "content-fingerprint-v1")

        let gates = try XCTUnwrap(result.qualityGates)
        XCTAssertEqual(gates.maxTemplateRepeat, 2)
        XCTAssertEqual(gates.minTextDensity, 0.35)
        XCTAssertEqual(gates.maxTextDensity, 0.72)
        XCTAssertEqual(gates.minImageDensity, 0.08)
        XCTAssertEqual(gates.maxImageDensity, 0.42)
        XCTAssertEqual(gates.requireAccentPerSpread, true)
        XCTAssertEqual(gates.maxOverflowRatio, 0.01)

        XCTAssertTrue(result.unsupportedFields.contains("$.motifs.headingRule.renderHint"))
        XCTAssertTrue(result.unsupportedFields.contains("$.layoutGrammar.rhythm.unimplementedHint"))
    }

    func testParsesLegacyChapterNumberRoleAsGhostMotif() throws {
        let json = validSpecPack.replacingOccurrences(
            of: #""章节序号":{"treatment":"ghost","font":"西文","fontSize_pt":200,"color":"ink","opacity":0.06}"#,
            with: #""章节序号":{"treatment":"ghost","font":"西文","fontSize_pt":210,"color":"grayText","opacity":0.08,"position":"chapterStart.bottomRight"}"#
        )

        let result = try StyleBaselineImporter.parseSpecPack(
            jsonData: json.data(using: .utf8)!,
            fontAvailability: { self.installedFonts.contains($0) }
        )

        let motif = try XCTUnwrap(result.motifs.chapterNumber)
        XCTAssertEqual(motif.fontAlias, "西文")
        XCTAssertEqual(motif.resolvedFontName, "Georgia")
        XCTAssertEqual(motif.fontSizePt, 210)
        XCTAssertEqual(motif.color, "grayText")
        XCTAssertEqual(motif.opacity, 0.08)
        XCTAssertEqual(motif.anchor, "chapterStart.bottomRight")
        XCTAssertEqual(motif.layer, "behind")
        XCTAssertFalse(result.unsupportedFields.contains("$.roles.章节序号"))
        XCTAssertFalse(result.unsupportedFields.contains("$.roles.章节序号.treatment"))
        XCTAssertFalse(result.unsupportedFields.contains("$.roles.章节序号.position"))
    }

    func testAutoDetectsSpecPack() throws {
        let installedOnlySpec = validSpecPack
            .replacingOccurrences(of: #""正文":"方正兰亭细黑""#, with: #""正文":"Georgia""#)
            .replacingOccurrences(of: #""标题":"黑体-简 Medium""#, with: #""标题":"Georgia""#)
            .replacingOccurrences(of: #""抽言":"江城律动宋""#, with: #""抽言":"Georgia""#)
        let (tokens, format) = try StyleBaselineImporter.autoDetectAndParse(jsonData: installedOnlySpec.data(using: .utf8)!)

        XCTAssertEqual(format, .specPack)
        XCTAssertEqual(tokens.scalar("paragraph.caption.fontSize"), 7.5)
    }

    func testImportsDesktopSpecPacksWhenPresent() throws {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/layoutD-规范包测试")
        let names = ["方案A-探索黄.json", "方案B-湖山青.json", "方案C-暖砂橙.json"]
        guard names.allSatisfy({ FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }) else {
            throw XCTSkip("Desktop spec pack fixtures are not present on this machine")
        }

        for name in names {
            let data = try Data(contentsOf: directory.appendingPathComponent(name))
            let result = try StyleBaselineImporter.parseSpecPack(jsonData: data)
            XCTAssertNotNil(result.tokens.colorHex("accent"), name)
            XCTAssertNotNil(result.tokens.scalar("paragraph.body.fontSize"), name)
            XCTAssertNotNil(result.tokens.scalar("page.baselineGrid"), name)
            XCTAssertFalse(result.unsupportedFields.isEmpty, name)
        }
    }

    func testRejectsTypicalInvalidSpecPacksWithReadableFieldPaths() throws {
        let cases: [(String, String, String)] = [
            ("missing meta name", #""meta":{"name":"方案A · 探索黄（杂志感）","version":1}"#, "$.meta.name"),
            ("negative page width", #""width":185"#, "$.page.size_mm.width"),
            ("zero baseline grid", #""baselineGrid_pt":15.5"#, "$.page.grid.baselineGrid_pt"),
            ("negative margin", #""inner":20"#, "$.page.margins_mm.inner"),
            ("margins exceed width", #""inner":20, "outer":24"#, "$.page.margins_mm"),
            ("bad color hex", ##""#F5C518""##, "$.colors.tokens.accent.default"),
            ("unknown color mode", ##""accent":{"default":"#F5C518"}"##, "$.colors.tokens.accent"),
            ("missing font alias", #""正文":{"font":"正文""#, "$.roles.正文.font"),
            ("missing installed font", #""正文":"方正兰亭细黑""#, "$.fonts.正文"),
            ("line height without font size", #""fontSize_pt":10, "lineHeight":1.6"#, "$.roles.正文.lineHeight"),
            ("bad chapter opacity", #""opacity":0.06"#, "$.roles.章节序号.opacity")
        ]

        for (label, find, expectedPath) in cases {
            let json = invalidSpecPack(caseFind: find)
            do {
                _ = try StyleBaselineImporter.parseSpecPack(
                    jsonData: json.data(using: .utf8)!,
                    fontAvailability: { font in
                        if label == "missing installed font" {
                            return font != "方正兰亭细黑简体" && self.installedFonts.contains(font)
                        }
                        return self.installedFonts.contains(font)
                    }
                )
                XCTFail("Expected rejection for \(label)")
            } catch {
                XCTAssertTrue(
                    error.localizedDescription.contains(expectedPath),
                    "\(label) should mention \(expectedPath), got: \(error.localizedDescription)"
                )
            }
        }
    }

    private func invalidSpecPack(caseFind: String) -> String {
        switch caseFind {
        case #""meta":{"name":"方案A · 探索黄（杂志感）","version":1}"#:
            return validSpecPack.replacingOccurrences(of: caseFind, with: #""meta":{}"#)
        case #""width":185"#:
            return validSpecPack.replacingOccurrences(of: caseFind, with: #""width":-1"#)
        case #""baselineGrid_pt":15.5"#:
            return validSpecPack.replacingOccurrences(of: caseFind, with: #""baselineGrid_pt":0"#)
        case #""inner":20"#:
            return validSpecPack.replacingOccurrences(of: caseFind, with: #""inner":-1"#)
        case #""inner":20, "outer":24"#:
            return validSpecPack.replacingOccurrences(of: caseFind, with: #""inner":100, "outer":100"#)
        case ##""#F5C518""##:
            return validSpecPack.replacingOccurrences(of: caseFind, with: #""yellow""#)
        case ##""accent":{"default":"#F5C518"}"##:
            return validSpecPack.replacingOccurrences(of: #""modes":["default"]"#, with: #""modes":["print"]"#)
        case #""正文":{"font":"正文""#:
            return validSpecPack.replacingOccurrences(of: caseFind, with: #""正文":{"font":"不存在字体别名""#)
        case #""正文":"方正兰亭细黑""#:
            return validSpecPack
        case #""fontSize_pt":10, "lineHeight":1.6"#:
            return validSpecPack.replacingOccurrences(of: caseFind, with: #""lineHeight":1.6"#)
        case #""opacity":0.06"#:
            return validSpecPack.replacingOccurrences(of: caseFind, with: #""opacity":1.4"#)
        default:
            return validSpecPack
        }
    }

    func testRejectsInvalidSpecPackV2FieldsWithReadableFieldPaths() throws {
        let cases: [(String, String, String)] = [
            ("text density range", #""minTextDensity":0.35,"maxTextDensity":0.72"#, "$.qualityGates.minTextDensity"),
            ("duplicate spread archetype", #""id":"text-led-duo""#, "$.layoutGrammar.spreadArchetypes[1].id"),
            ("invalid rhythm bool", #""accentEverySpread":true"#, "$.layoutGrammar.rhythm.accentEverySpread")
        ]

        for (label, find, expectedPath) in cases {
            let json: String
            switch label {
            case "text density range":
                json = validSpecPackV2.replacingOccurrences(of: find, with: #""minTextDensity":0.9,"maxTextDensity":0.72"#)
            case "duplicate spread archetype":
                json = validSpecPackV2.replacingOccurrences(of: find, with: #""id":"text-image-balanced""#)
            case "invalid rhythm bool":
                json = validSpecPackV2.replacingOccurrences(of: find, with: #""accentEverySpread":"yes""#)
            default:
                json = validSpecPackV2
            }

            do {
                _ = try StyleBaselineImporter.parseSpecPack(
                    jsonData: json.data(using: .utf8)!,
                    fontAvailability: { self.installedFonts.contains($0) }
                )
                XCTFail("Expected rejection for \(label)")
            } catch {
                XCTAssertTrue(
                    error.localizedDescription.contains(expectedPath),
                    "\(label) should mention \(expectedPath), got: \(error.localizedDescription)"
                )
            }
        }
    }

    private var validSpecPack: String {
        """
        {
          "meta":{"name":"方案A · 探索黄（杂志感）","version":1},
          "page":{
            "size_mm":{"width":185,"height":260},
            "margins_mm":{"top":22,"bottom":26,"inner":20, "outer":24},
            "grid":{"columns":2,"gutter_mm":8,"baselineGrid_pt":15.5}
          },
          "fonts":{
            "正文":"方正兰亭细黑",
            "标题":"黑体-简 Medium",
            "抽言":"江城律动宋",
            "西文":"Georgia"
          },
          "colors":{
            "modes":["default"],
            "tokens":{
              "accent":{"default":"#F5C518"},
              "ink":{"default":"#1B1B1B"},
              "grayText":{"default":"#8C8C8C"},
              "paper":{"default":"#FFFFFF"}
            }
          },
          "roles":{
            "章名":{"font":"标题","fontSize_pt":34,"lineHeight":1.3,"tracking_em":0.02,"color":"ink"},
            "章节序号":{"treatment":"ghost","font":"西文","fontSize_pt":200,"color":"ink","opacity":0.06},
            "开节概述":{"font":"正文","fontSize_pt":11,"lineHeight":2.0,"color":"grayText","maxLineWidth_chars":24},
            "节名":{"font":"标题","fontSize_pt":12,"lineHeight":1.5,"numberStyle":"西文序号着accent色","spaceBefore_pt":24,"spaceAfter_pt":10},
            "正文":{"font":"正文","fontSize_pt":10, "lineHeight":1.6,"firstLineIndent_em":2,"alignment":"justify"},
            "抽言":{"font":"抽言","fontSize_pt":16,"lineHeight":1.8,"firstLineIndent_em":0,"decoration":{"type":"left-rule","color":"accent","width_pt":3}},
            "图注":{"font":"正文","fontSize_pt":7.5,"lineHeight":1.5,"color":"grayText","decoration":{"type":"top-tick","color":"accent","length_mm":6}},
            "引文":{"font":"抽言","fontSize_pt":9.5,"lineHeight":1.8,"indent_em":2,"color":"grayText"},
            "页眉页码":{"font":"西文","fontSize_pt":7.5,"color":"grayText","rule":"细线通栏"}
          },
          "vertical":false
        }
        """
    }

    private var validSpecPackV2: String {
        """
        {
          "meta":{"name":"方案A · 探索黄（v2）","version":2},
          "page":{
            "size_mm":{"width":185,"height":260},
            "margins_mm":{"top":22,"bottom":26,"inner":20, "outer":24},
            "grid":{"columns":2,"gutter_mm":8,"baselineGrid_pt":15.5}
          },
          "fonts":{
            "正文":"方正兰亭细黑",
            "标题":"黑体-简 Medium",
            "抽言":"江城律动宋",
            "西文":"Georgia"
          },
          "colors":{
            "modes":["default"],
            "tokens":{
              "accent":{"default":"#F5C518"},
              "ink":{"default":"#1B1B1B"},
              "grayText":{"default":"#8C8C8C"},
              "paper":{"default":"#FFFFFF"}
            }
          },
          "roles":{
            "章名":{"font":"标题","fontSize_pt":34,"lineHeight":1.3,"tracking_em":0.02,"color":"ink"},
            "开节概述":{"font":"正文","fontSize_pt":11,"lineHeight":2.0,"color":"grayText","maxLineWidth_chars":24},
            "节名":{"font":"标题","fontSize_pt":12,"lineHeight":1.5,"spaceBefore_pt":24,"spaceAfter_pt":10},
            "正文":{"font":"正文","fontSize_pt":10, "lineHeight":1.6,"firstLineIndent_em":2,"alignment":"justify"},
            "抽言":{"font":"抽言","fontSize_pt":16,"lineHeight":1.8,"firstLineIndent_em":0},
            "图注":{"font":"正文","fontSize_pt":7.5,"lineHeight":1.5,"color":"grayText"},
            "引文":{"font":"抽言","fontSize_pt":9.5,"lineHeight":1.8,"indent_em":2,"color":"grayText"}
          },
          "motifs":{
            "chapterNumber":{"font":"西文","fontSize_pt":184,"color":"grayText","opacity":0.07,"anchor":"chapterStart.topRight","layer":"behind"},
            "sectionNumber":{"style":"westernAccent","color":"accent","minDigits":2,"suffix":" /"},
            "header":{"font":"西文","fontSize_pt":7.5,"color":"grayText","rule":"thin-full-width","label":"EXPLORE","showChapterTitle":true,"showPageNumber":true},
            "captionTick":{"type":"top-tick","color":"accent","width_pt":2,"length_mm":6},
            "headingRule":{"type":"bottom-rule","color":"accent","width_pt":2,"length_mm":20,"renderHint":"pending renderer"},
            "pullQuoteRule":{"type":"left-rule","color":"accent","width_pt":3}
          },
          "layoutGrammar":{
            "spreadArchetypes":[
              {"id":"text-image-balanced","displayName":"图文均衡对开","family":"balanced","pages":2,"imageSlots":1,"pullQuoteSlots":1,"mirror":true,"weight":1.2},
              {"id":"text-led-duo","displayName":"正文双页","family":"text-led","pages":2,"imageSlots":0,"pullQuoteSlots":0,"mirror":true,"weight":1}
            ],
            "rhythm":{"maxSameFamilyRun":2,"bigImageEveryMinSpreads":3,"accentEverySpread":true,"seed":"content-fingerprint-v1","unimplementedHint":"future scorer"}
          },
          "qualityGates":{
            "maxTemplateRepeat":2,
            "minTextDensity":0.35,"maxTextDensity":0.72,
            "minImageDensity":0.08,"maxImageDensity":0.42,
            "requireAccentPerSpread":true,
            "maxOverflowRatio":0.01
          },
          "vertical":false
        }
        """
    }
}
