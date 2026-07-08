import XCTest
import SwiftUI
import LayoutDCore
import LayoutDDesignAI
import LayoutDEngine
import LayoutDExport
@testable import LayoutDApp

final class AppStateTests: XCTestCase {
    func testPrintColorFromSwiftUIColorPreservesCMYK() {
        // 标准色块通路:系统面板 CMYK 滑块给出的 CMYK 色必须保持 CMYK,不被压回 RGB。
        let cmyk = Color(nsColor: NSColor(deviceCyan: 0.37, magenta: 0.04, yellow: 0.44, black: 0, alpha: 1))
        guard case let .cmyk(c, m, y, k) = AppState.printColor(from: cmyk) else {
            return XCTFail("CMYK Color 应解析为 .cmyk,而非压平为 RGB")
        }
        XCTAssertEqual(c, 37, accuracy: 0.5)
        XCTAssertEqual(m, 4, accuracy: 0.5)
        XCTAssertEqual(y, 44, accuracy: 0.5)
        XCTAssertEqual(k, 0, accuracy: 0.5)
    }

    func testPrintColorFromSwiftUIColorKeepsRGB() {
        let rgb = Color(.sRGB, red: 143.0 / 255, green: 192.0 / 255, blue: 135.0 / 255, opacity: 1)
        guard case let .rgb(r, g, b) = AppState.printColor(from: rgb) else {
            return XCTFail("sRGB Color 应解析为 .rgb")
        }
        XCTAssertEqual(r, 143); XCTAssertEqual(g, 192); XCTAssertEqual(b, 135)
    }

    func testApplyPageLayoutTemplate() {
        let project = BookProject.sample
        let state = AppState(project: project)
        
        // Assert clean starting state
        XCTAssertNil(state.project.safeAppliedLayoutPlans[2])
        
        // Apply a template (e.g. .textLedPage) to page 2
        state.applyPageLayoutTemplate(.textLedPage, toPage: 2)
        
        // Verify the layout plan was applied to page 2
        let plan = state.project.safeAppliedLayoutPlans[2]
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.strategy, .textLed)
        XCTAssertEqual(plan?.blocks.count, 2)
    }

    func testInsertPageShiftsLayoutPlans() {
        let project = BookProject.sample
        let state = AppState(project: project)
        
        // Apply plans to page 2 and 3
        state.applyPageLayoutTemplate(.textLedPage, toPage: 2)
        state.applyPageLayoutTemplate(.knowledgeCardPage, toPage: 3)
        
        XCTAssertEqual(state.project.safeAppliedLayoutPlans[2]?.strategy, .textLed)
        XCTAssertEqual(state.project.safeAppliedLayoutPlans[3]?.strategy, .knowledgeCard)
        
        // Insert a page at page 2
        state.insertPage(at: 2)
        
        // Plans should be shifted to page 3 and 4
        XCTAssertEqual(state.project.safeAppliedLayoutPlans[2]?.blocks.count, 0) // page 2 is blank now
        XCTAssertEqual(state.project.safeAppliedLayoutPlans[3]?.strategy, .textLed) // shifted from 2
        XCTAssertEqual(state.project.safeAppliedLayoutPlans[4]?.strategy, .knowledgeCard) // shifted from 3
    }

    func testFillColorWritesHexAndCoalescesUndo() {
        let state = AppState(project: BookProject.sample)
        guard let doc = state.laidOutDocument,
              let page = doc.pages.first(where: { $0.frames.contains { $0.kind == .text || $0.kind == .image } }),
              let frame = page.frames.first(where: { $0.kind == .text || $0.kind == .image }) else {
            return XCTFail("sample should have a text or image frame")
        }
        state.selectedFrameId = frame.id
        XCTAssertFalse(state.canUndo, "selecting a frame must not create an undo step")

        // Three consecutive picker changes on the same frame = one undo burst.
        state.setSelectedFrameFillColor(.red)
        state.setSelectedFrameFillColor(.green)
        state.setSelectedFrameFillColor(.blue)

        let pageNum = state.currentPageNumber
        let block = state.project.safeAppliedLayoutPlans[pageNum]?.blocks.first { $0.id == frame.id }
        XCTAssertNotNil(block?.backgroundColorHex, "fill color must persist as a plan-block override")
        XCTAssertTrue(state.canUndo)

        // A single undo reverts the whole color burst back to no fill.
        state.undo()
        let reverted = state.project.safeAppliedLayoutPlans[pageNum]?.blocks.first { $0.id == frame.id }
        XCTAssertNil(reverted?.backgroundColorHex)
        XCTAssertFalse(state.canUndo, "the three changes should have collapsed to one undo entry")
    }

    func testCMYKFillKeepsPlanValidSoSelectionSurvives() {
        let state = AppState(project: BookProject.sample)
        // The cover page (front matter) is regenerated every layout unless its
        // frozen plan validates — the exact path the bug struck.
        guard let doc = state.laidOutDocument,
              let cover = doc.pages.first(where: { $0.number == 1 }),
              let frame = cover.frames.first(where: { $0.kind == .text }) else {
            return XCTFail("sample cover page should have a text frame")
        }
        state.selectedFrameId = frame.id

        // Apply a print-native CMYK fill (storage form `cmyk(C,M,Y,K)`).
        state.setSelectedFrameFillColor(PrintColor.cmyk(c: 37, m: 4, y: 44, k: 0))

        let pageNum = state.currentPageNumber
        let block = state.project.safeAppliedLayoutPlans[pageNum]?.blocks.first { $0.id == frame.id }
        XCTAssertEqual(block?.backgroundColorHex, "cmyk(37,4,44,0)",
                       "CMYK fill must persist in its native form, not flatten to RGB")

        // Regression: a `cmyk(...)` value must not fail plan validation. If it did,
        // the engine would discard the frozen plan and regenerate the page with
        // fresh frame ids — silently dropping the selection (and the color). So the
        // selected frame's id must survive the relayout.
        let stillPresent = state.laidOutDocument?.pages.contains {
            $0.frames.contains { $0.id == frame.id }
        } ?? false
        XCTAssertTrue(stillPresent,
                      "selection (frame id) must survive relayout after a CMYK fill")
    }

    func testSelectingFrameSyncsCurrentPage() {
        let state = AppState(project: BookProject.sample)
        state.currentPageNumber = 1

        // Find a frame that lives on a page other than 1.
        guard let doc = state.laidOutDocument,
              let otherPage = doc.pages.first(where: { $0.number > 1 && !$0.frames.isEmpty }),
              let frame = otherPage.frames.first else {
            return XCTFail("sample should have frames on a page beyond page 1")
        }

        state.selectedFrameId = frame.id
        // currentPageNumber must follow the selection so page-scoped controls
        // (lock/unlock, reset, save-as-template) act on the right page.
        XCTAssertEqual(state.currentPageNumber, otherPage.number)

        // Lock/unlock now targets the page the selected frame is actually on.
        state.lockPage(number: state.currentPageNumber)
        XCTAssertTrue(state.project.safeLockedPages.contains(otherPage.number))
        state.unlockPage(number: state.currentPageNumber)
        XCTAssertFalse(state.project.safeLockedPages.contains(otherPage.number))
    }

    func testCreateDrawnTextFrameWritesNormalizedBlock() {
        let state = AppState(project: BookProject.sample)
        let pageSize = state.project.pageSetup.pageSize

        // Draw a text frame at page-local (100,120) sized 200×80 on page 2.
        // Drawing on a page with no explicit plan first freezes the page's existing
        // auto-laid frames into a plan, then appends the new block on top.
        let frozenCount = state.freezePageToPlan(pageNum: 2).blocks.count
        let created = state.createDrawnFrame(
            kind: .text,
            onPage: 2,
            rect: Rect(x: 100, y: 120, width: 200, height: 80)
        )
        XCTAssertTrue(created)

        let plan = state.project.safeAppliedLayoutPlans[2]
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.blocks.count, frozenCount + 1)

        let block = try! XCTUnwrap(plan?.blocks.last)
        XCTAssertEqual(block.kind, .text)
        // Frame is stored normalized to the page size.
        XCTAssertEqual(block.frame.x, 100 / pageSize.width, accuracy: 0.0001)
        XCTAssertEqual(block.frame.y, 120 / pageSize.height, accuracy: 0.0001)
        XCTAssertEqual(block.frame.width, 200 / pageSize.width, accuracy: 0.0001)
        XCTAssertEqual(block.frame.height, 80 / pageSize.height, accuracy: 0.0001)
        // Empty generated content, ready for the inspector's text editor.
        if case .generated(let text) = block.contentReference {
            XCTAssertEqual(text, "")
        } else {
            XCTFail("drawn text frame should carry generated content")
        }
        // The new frame is selected and the action is undoable.
        XCTAssertEqual(state.selectedFrameId, block.id)
        XCTAssertTrue(state.canUndo)
    }

    func testAlignSelectedFrameToPageWritesUndoableOverride() {
        let state = AppState(project: BookProject.sample)
        let pageSize = state.project.pageSetup.pageSize

        // Draw a 200×80 frame somewhere off-edge on page 2, then align it.
        XCTAssertTrue(state.createDrawnFrame(
            kind: .text,
            onPage: 2,
            rect: Rect(x: 100, y: 120, width: 200, height: 80)
        ))
        let frameId = try! XCTUnwrap(state.selectedFrameId)

        // Left → page edge (x = 0).
        state.alignSelection(.left, reference: .page)
        var block = try! XCTUnwrap(state.project.safeAppliedLayoutPlans[2]?.blocks.first(where: { $0.id == frameId }))
        XCTAssertEqual(block.absoluteFrame(pageSize: pageSize).x, 0, accuracy: 0.0001)

        // Horizontal center on the page keeps the 200-wide frame centered.
        state.alignSelection(.horizontalCenter, reference: .page)
        block = try! XCTUnwrap(state.project.safeAppliedLayoutPlans[2]?.blocks.first(where: { $0.id == frameId }))
        XCTAssertEqual(block.absoluteFrame(pageSize: pageSize).x, (pageSize.width - 200) / 2, accuracy: 0.0001)

        // Alignment is undoable (each call commits one undo step).
        XCTAssertTrue(state.canUndo)
    }

    func testAlignSelectedFrameToMarginRespectsFacingPageSide() {
        let state = AppState(project: BookProject.sample)
        let pageSize = state.project.pageSetup.pageSize

        XCTAssertTrue(state.createDrawnFrame(
            kind: .text,
            onPage: 3,
            rect: Rect(x: 300, y: 120, width: 120, height: 60)
        ))
        let frameId = try! XCTUnwrap(state.selectedFrameId)

        state.alignSelection(.left, reference: .margin)
        let block = try! XCTUnwrap(state.project.safeAppliedLayoutPlans[3]?.blocks.first(where: { $0.id == frameId }))

        // Page 3 is odd → on a facing-page spread its left edge is the (inner) left
        // margin, matching the canvas guide.
        let margins = state.project.resolvedMargins(for: 3)
        XCTAssertEqual(block.absoluteFrame(pageSize: pageSize).x, margins.left, accuracy: 0.0001)
    }

    func testToggleAndSetSelectionMaintainAnchorInvariant() {
        let state = AppState(project: BookProject.sample)
        let a = UUID(), b = UUID(), c = UUID()

        // Plain single-select collapses the set to one.
        state.selectedFrameId = a
        XCTAssertEqual(state.selectedFrameIds, [a])

        // Toggle adds and moves the anchor.
        state.toggleFrameSelection(b)
        XCTAssertEqual(state.selectedFrameIds, [a, b])
        XCTAssertEqual(state.selectedFrameId, b)

        // Toggling the anchor off picks a remaining member as the new anchor.
        state.toggleFrameSelection(b)
        XCTAssertEqual(state.selectedFrameIds, [a])
        XCTAssertEqual(state.selectedFrameId, a)

        // setSelection replaces wholesale.
        state.setSelection([a, b, c], anchor: c)
        XCTAssertEqual(state.selectedFrameIds, [a, b, c])
        XCTAssertEqual(state.selectedFrameId, c)

        // Assigning nil clears everything.
        state.selectedFrameId = nil
        XCTAssertTrue(state.selectedFrameIds.isEmpty)
    }

    func testAlignSelectionToSelectionBoundingBox() {
        let state = AppState(project: BookProject.sample)
        let pageSize = state.project.pageSetup.pageSize

        // Two frames on page 2 at different X.
        XCTAssertTrue(state.createDrawnFrame(kind: .text, onPage: 2, rect: Rect(x: 40, y: 60, width: 100, height: 50)))
        let first = try! XCTUnwrap(state.selectedFrameId)
        XCTAssertTrue(state.createDrawnFrame(kind: .text, onPage: 2, rect: Rect(x: 220, y: 300, width: 80, height: 40)))
        let second = try! XCTUnwrap(state.selectedFrameId)

        state.setSelection([first, second])
        // Left-align to the selection box → both share the leftmost X (40).
        state.alignSelection(.left, reference: .selection)

        let plan = try! XCTUnwrap(state.project.safeAppliedLayoutPlans[2])
        let f1 = try! XCTUnwrap(plan.blocks.first { $0.id == first })
        let f2 = try! XCTUnwrap(plan.blocks.first { $0.id == second })
        XCTAssertEqual(f1.absoluteFrame(pageSize: pageSize).x, 40, accuracy: 0.0001)
        XCTAssertEqual(f2.absoluteFrame(pageSize: pageSize).x, 40, accuracy: 0.0001)
        XCTAssertTrue(state.canUndo)
    }

    func testDistributeSelectionRequiresThreeFrames() {
        let state = AppState(project: BookProject.sample)
        let pageSize = state.project.pageSetup.pageSize

        var ids: [UUID] = []
        for x in [0.0, 100.0, 400.0] {
            XCTAssertTrue(state.createDrawnFrame(kind: .text, onPage: 2, rect: Rect(x: x, y: 50, width: 40, height: 30)))
            ids.append(try! XCTUnwrap(state.selectedFrameId))
        }
        state.setSelection(Set(ids))
        state.distributeSelection(.horizontalCenters)

        let plan = try! XCTUnwrap(state.project.safeAppliedLayoutPlans[2])
        let centers = ids.map { id -> Double in
            let r = plan.blocks.first { $0.id == id }!.absoluteFrame(pageSize: pageSize)
            return r.x + r.width / 2
        }.sorted()
        // Three evenly spaced centers: middle gap equals outer gap.
        XCTAssertEqual(centers[1] - centers[0], centers[2] - centers[1], accuracy: 0.0001)
    }

    func testCreateDrawnRectangleCarriesFillAndStroke() {
        let state = AppState(project: BookProject.sample)
        state.isFillActive = true
        XCTAssertTrue(state.createDrawnFrame(
            kind: .rectangle,
            onPage: 2,
            rect: Rect(x: 60, y: 80, width: 150, height: 100)
        ))
        let id = try! XCTUnwrap(state.selectedFrameId)
        let block = try! XCTUnwrap(state.project.safeAppliedLayoutPlans[2]?.blocks.first { $0.id == id })
        XCTAssertEqual(block.kind, .rectangle)
        // A rectangle is visible immediately: it carries fill + stroke, no content.
        XCTAssertNotNil(block.backgroundColorHex)
        XCTAssertNotNil(block.strokeColorHex)
        if case .generated(let text) = block.contentReference {
            XCTAssertEqual(text, "")
        } else {
            XCTFail("rectangle should carry empty generated content")
        }
        XCTAssertTrue(state.canUndo)
    }

    func testCreateDrawnLineFilledWithStrokeColorNoBorder() {
        let state = AppState(project: BookProject.sample)
        XCTAssertTrue(state.createDrawnFrame(
            kind: .line,
            onPage: 2,
            rect: Rect(x: 40, y: 200, width: 220, height: 2)
        ))
        let id = try! XCTUnwrap(state.selectedFrameId)
        let block = try! XCTUnwrap(state.project.safeAppliedLayoutPlans[2]?.blocks.first { $0.id == id })
        XCTAssertEqual(block.kind, .line)
        // A line is a true stroke: its colour/weight live in stroke, no fill.
        XCTAssertNotNil(block.strokeColorHex)
        XCTAssertNotNil(block.strokeWidth)
        XCTAssertNil(block.backgroundColorHex)
    }

    func testSetSelectedFrameStrokeWidthPersistsAsOverride() {
        let state = AppState(project: BookProject.sample)
        XCTAssertTrue(state.createDrawnFrame(
            kind: .rectangle,
            onPage: 2,
            rect: Rect(x: 60, y: 80, width: 150, height: 100)
        ))
        let id = try! XCTUnwrap(state.selectedFrameId)

        state.setSelectedFrameStrokeWidth(3)
        var block = try! XCTUnwrap(state.project.safeAppliedLayoutPlans[2]?.blocks.first { $0.id == id })
        XCTAssertEqual(try XCTUnwrap(block.strokeWidth), 3, accuracy: 0.0001)
        XCTAssertTrue(state.canUndo)

        // 0 pt is a valid weight (hairline off), and negatives are clamped to 0.
        state.setSelectedFrameStrokeWidth(-5)
        block = try! XCTUnwrap(state.project.safeAppliedLayoutPlans[2]?.blocks.first { $0.id == id })
        XCTAssertEqual(try XCTUnwrap(block.strokeWidth), 0, accuracy: 0.0001)
    }

    func testCreateDrawnImageFrameNeedsAsset() {
        // sample project has assets → image frame creates and references one.
        let withAssets = AppState(project: BookProject.sample)
        XCTAssertFalse(withAssets.project.assets.isEmpty, "sample project should ship assets")
        let ok = withAssets.createDrawnFrame(kind: .image, onPage: 2, rect: Rect(x: 10, y: 10, width: 120, height: 90))
        XCTAssertTrue(ok)
        let block = withAssets.project.safeAppliedLayoutPlans[2]?.blocks.last
        XCTAssertEqual(block?.kind, .image)
        if case .asset(let id)? = block?.contentReference {
            XCTAssertTrue(withAssets.project.assets.contains { $0.id == id })
        } else {
            XCTFail("drawn image frame should reference an asset")
        }

        // No assets → refuses, writes nothing.
        var emptyProject = BookProject.sample
        emptyProject.assets = []
        emptyProject.appliedLayoutPlans = nil
        let noAssets = AppState(project: emptyProject)
        let planCountBefore = noAssets.project.safeAppliedLayoutPlans[2]?.blocks.count ?? 0
        let refused = noAssets.createDrawnFrame(kind: .image, onPage: 2, rect: Rect(x: 10, y: 10, width: 120, height: 90))
        XCTAssertFalse(refused)
        XCTAssertEqual(noAssets.project.safeAppliedLayoutPlans[2]?.blocks.count ?? 0, planCountBefore)
    }

    func testDeletePageShiftsLayoutPlans() {
        let project = BookProject.sample
        let state = AppState(project: project)
        
        // Apply plans to page 2 and 3
        state.applyPageLayoutTemplate(.textLedPage, toPage: 2)
        state.applyPageLayoutTemplate(.knowledgeCardPage, toPage: 3)
        
        XCTAssertEqual(state.project.safeAppliedLayoutPlans[2]?.strategy, .textLed)
        XCTAssertEqual(state.project.safeAppliedLayoutPlans[3]?.strategy, .knowledgeCard)
        
        // Delete page 2
        state.deletePage(at: 2)
        
        // Page 2 should now hold what was on page 3 (knowledgeCard)
        XCTAssertEqual(state.project.safeAppliedLayoutPlans[2]?.strategy, .knowledgeCard)
        XCTAssertNil(state.project.safeAppliedLayoutPlans[3]) // page 3 layout plan removed
    }

    func testScreenModeToggle() {
        let project = BookProject.sample
        let state = AppState(project: project)
        XCTAssertEqual(state.activeScreenMode, .normal)
        
        state.activeScreenMode = .preview
        XCTAssertEqual(state.activeScreenMode, .preview)
    }

    func testFormattingTargetToggle() {
        let project = BookProject.sample
        let state = AppState(project: project)
        XCTAssertEqual(state.activeFormattingTarget, .container)
        
        state.activeFormattingTarget = .text
        XCTAssertEqual(state.activeFormattingTarget, .text)
    }

    func testProjectMutationRecalculatesLayoutAndPreflight() {
        let state = AppState(project: .sample)
        let originalTitleFrame = state.laidOutDocument?.pages
            .first(where: { $0.number == 1 })?
            .frames
            .first { frame in
                if case .text(let text) = frame.content {
                    return text == BookProject.sample.metadata.title
                }
                return false
            }

        XCTAssertNotNil(originalTitleFrame)
        XCTAssertFalse(state.report?.issues.contains { $0.message == "项目缺少出版社信息" } ?? true)

        state.updateProject { project in
            project.metadata.title = "刷新后的标题"
            project.metadata.publisher = nil
        }

        let updatedTitleFrame = state.laidOutDocument?.pages
            .first(where: { $0.number == 1 })?
            .frames
            .first { frame in
                if case .text(let text) = frame.content {
                    return text == "刷新后的标题"
                }
                return false
            }

        XCTAssertNotNil(updatedTitleFrame)
        XCTAssertTrue(state.report?.issues.contains { $0.message == "项目缺少出版社信息" } ?? false)
    }

    func testManualParagraphStyleEditClearsScalarTokenBinding() {
        let state = AppState(project: .sample)
        XCTAssertEqual(
            state.project.styles.paragraphStyles.first { $0.id == StyleID.body.rawValue }?.fontSizeToken,
            "paragraph.body.fontSize"
        )

        state.updateParagraphStyle(id: StyleID.body.rawValue, fontSize: 13)

        let storedBody = state.project.styles.paragraphStyles.first { $0.id == StyleID.body.rawValue }
        XCTAssertEqual(storedBody?.fontSize, 13)
        XCTAssertNil(storedBody?.fontSizeToken)
        XCTAssertEqual(state.project.styles.paragraphStyle(id: StyleID.body.rawValue).fontSize, 13)
    }

    func testManualPageSetupEditClearsScalarTokenBinding() {
        let state = AppState(project: .sample)
        XCTAssertEqual(state.project.pageSetup.gutterToken, "page.gutter")
        XCTAssertEqual(state.project.pageSetup.baselineGridToken, "page.baselineGrid")

        state.updateProject { project in
            project.pageSetup.gutter = 21
            project.pageSetup.baselineGrid = 15
        }

        XCTAssertNil(state.project.pageSetup.gutterToken)
        XCTAssertNil(state.project.pageSetup.baselineGridToken)
        XCTAssertEqual(state.project.resolvedGutter(for: 3), 21)
        XCTAssertEqual(state.project.resolvedBaselineGrid, 15)
    }

    func testApplySwatchColorToSelectedFrame() {
        let project = BookProject.sample
        let state = AppState(project: project)
        
        // Mock selecting a frame
        let frameId = UUID()
        state.selectedFrameId = frameId
        
        // Apply container background fill color
        state.activeFormattingTarget = .container
        state.isFillActive = true
        state.applyColorToSelectedFrame(.red)
        
        XCTAssertEqual(state.frameBackgroundColors[frameId], .red)
        XCTAssertNil(state.frameStrokeColors[frameId])
        
        // Apply container stroke color
        state.isFillActive = false
        state.applyColorToSelectedFrame(.blue)
        XCTAssertEqual(state.frameStrokeColors[frameId], .blue)
        
        // Apply text foreground color
        state.activeFormattingTarget = .text
        state.applyColorToSelectedFrame(.green)
        XCTAssertEqual(state.frameTextColors[frameId], .green)
        
        // Remove color
        state.removeColorFromSelectedFrame()
        XCTAssertNil(state.frameTextColors[frameId])
    }

    func testApplySwatchColorPersistsInLayoutPlan() {
        let state = AppState(project: .sample)
        let frame = state.laidOutDocument?.pages
            .first(where: { $0.number == 3 })?
            .frames
            .first { frame in
                if case .text(let text) = frame.content {
                    return text.contains("重新理解图文排版")
                }
                return false
            }
        let frameId = try! XCTUnwrap(frame?.id)

        state.selectedFrameId = frameId
        state.activeFormattingTarget = .container
        state.isFillActive = true
        state.applyColorToSelectedFrame(Color(.sRGB, red: 0.2, green: 0.4, blue: 0.6, opacity: 1))

        var block = state.project.safeAppliedLayoutPlans[3]?.blocks.first { $0.id == frameId }
        XCTAssertEqual(block?.backgroundColorHex, "#336699")

        let updatedFrame = state.laidOutDocument?.pages
            .first(where: { $0.number == 3 })?
            .frames
            .first { $0.id == frameId }
        XCTAssertEqual(updatedFrame?.backgroundColorHex, "#336699")

        state.isFillActive = false
        state.applyColorToSelectedFrame(Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1))

        block = state.project.safeAppliedLayoutPlans[3]?.blocks.first { $0.id == frameId }
        XCTAssertEqual(block?.strokeColorHex, "#FF0000")
        XCTAssertEqual(block?.strokeWidth, 1.5)

        state.activeFormattingTarget = .text
        state.applyColorToSelectedFrame(Color(.sRGB, red: 0, green: 0.5, blue: 0, opacity: 1))

        block = state.project.safeAppliedLayoutPlans[3]?.blocks.first { $0.id == frameId }
        XCTAssertEqual(block?.textColorHex, "#008000")

        state.removeColorFromSelectedFrame()

        block = state.project.safeAppliedLayoutPlans[3]?.blocks.first { $0.id == frameId }
        XCTAssertNil(block?.textColorHex)
    }

    func testPersistedFrameColorsSurviveProjectRoundTrip() throws {
        let state = AppState(project: .sample)
        let frame = state.laidOutDocument?.pages
            .first(where: { $0.number == 3 })?
            .frames
            .first { frame in
                if case .text(let text) = frame.content {
                    return text.contains("重新理解图文排版")
                }
                return false
            }
        let frameId = try XCTUnwrap(frame?.id)

        state.selectedFrameId = frameId
        state.activeFormattingTarget = .container
        state.isFillActive = true
        state.applyColorToSelectedFrame(Color(.sRGB, red: 0.2, green: 0.4, blue: 0.6, opacity: 1))
        state.activeFormattingTarget = .text
        state.applyColorToSelectedFrame(Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1))

        let encoded = try ProjectFile.encode(state.project)
        let decoded = try ProjectFile.decode(encoded)
        let document = LayoutEngine().layout(project: decoded)
        let reloadedFrame = document.pages
            .first(where: { $0.number == 3 })?
            .frames
            .first { $0.id == frameId }

        XCTAssertEqual(reloadedFrame?.backgroundColorHex, "#336699")
        XCTAssertEqual(reloadedFrame?.textColorHex, "#FF0000")
    }

    func testUpdateSelectedFrameTextPersistsAsLayoutPlanOverride() throws {
        let state = AppState(project: .sample)
        let frame = state.laidOutDocument?.pages
            .first(where: { $0.number == 3 })?
            .frames
            .first { frame in
                if case .text(let text) = frame.content {
                    return text.contains("重新理解图文排版")
                }
                return false
            }
        let frameId = try XCTUnwrap(frame?.id)

        state.selectedFrameId = frameId
        state.updateSelectedFrameText("人工校改后的段落")

        let block = state.project.safeAppliedLayoutPlans[3]?.blocks.first { $0.id == frameId }
        XCTAssertEqual(block?.kind, .text)
        if case .generated(let text) = block?.contentReference {
            XCTAssertEqual(text, "人工校改后的段落")
        } else {
            XCTFail("Expected generated text override")
        }

        let updatedFrame = state.laidOutDocument?.pages
            .first(where: { $0.number == 3 })?
            .frames
            .first { $0.id == frameId }
        if case .text(let text) = updatedFrame?.content {
            XCTAssertEqual(text, "人工校改后的段落")
        } else {
            XCTFail("Expected updated text frame")
        }
    }

    func testGenerateBrochurePDF() throws {
        let pageSetup = PageSetup(
            pageSize: PageSize(width: 792, height: 612, label: "US Letter Landscape"),
            margins: PageMargins(top: 36, right: 36, bottom: 36, left: 36),
            columns: 3,
            gutter: 36,
            baselineGrid: 12,
            facingPages: false,
            bleedMM: 3.175
        )
        
        let assetId = UUID()
        let cellAsset = Asset(
            id: assetId,
            fileName: "cell-diagram.png",
            sourcePath: "/Users/amos/Documents/GitHub/mac-layoutD/Samples/images/cell-diagram.png",
            role: .diagram,
            caption: "细胞内部超微结构示意图",
            pixelWidth: 2400,
            pixelHeight: 1800,
            dpi: 300
        )
        
        let styles = StyleLibrary(
            paragraphStyles: [
                ParagraphStyle(id: "title", displayName: "标题", fontName: "PingFang SC Semibold", fontSize: 24, lineHeight: 32, firstLineIndent: 0, spaceBefore: 0, spaceAfter: 0),
                ParagraphStyle(id: "subtitle", displayName: "副标题", fontName: "Songti SC", fontSize: 13, lineHeight: 18, firstLineIndent: 0, spaceBefore: 0, spaceAfter: 0),
                ParagraphStyle(id: "tagline", displayName: "尾注", fontName: "PingFang SC", fontSize: 9, lineHeight: 12, firstLineIndent: 0, spaceBefore: 0, spaceAfter: 0),
                ParagraphStyle(id: "body", displayName: "正文", fontName: "Songti SC", fontSize: 10, lineHeight: 15, firstLineIndent: 0, spaceBefore: 0, spaceAfter: 0),
                ParagraphStyle(id: "heading", displayName: "栏目标题", fontName: "PingFang SC Semibold", fontSize: 15, lineHeight: 22, firstLineIndent: 0, spaceBefore: 0, spaceAfter: 0)
            ],
            colors: []
        )
        
        let project = BookProject(
            metadata: ProjectMetadata(title: "细胞的微观奥秘", author: "LayoutD Design Team"),
            pageSetup: pageSetup,
            styles: styles,
            assets: [cellAsset]
        )
        
        // Page 1 (Outside Panels)
        // Background frames:
        let p1bg1 = PageFrame(kind: .image, rect: Rect(x: 0, y: 0, width: 261, height: 612), content: .empty, backgroundColorHex: "#D2E2DF")
        let p1bg2 = PageFrame(kind: .image, rect: Rect(x: 261, y: 0, width: 265.5, height: 612), content: .empty, backgroundColorHex: "#1C3F3A")
        let p1bg3 = PageFrame(kind: .image, rect: Rect(x: 526.5, y: 0, width: 265.5, height: 612), content: .empty, backgroundColorHex: "#1C3F3A")
        let p1banner = PageFrame(kind: .image, rect: Rect(x: 526.5, y: 0, width: 265.5, height: 20), content: .empty, backgroundColorHex: "#E07A5F")
        
        // Content frames (Outside):
        let p1f1 = PageFrame(kind: .text, rect: Rect(x: 36, y: 50, width: 189, height: 30), styleId: "heading", content: .text("精彩预告"), textColorHex: "#1C3F3A")
        let p1f2 = PageFrame(kind: .text, rect: Rect(x: 36, y: 90, width: 189, height: 400), styleId: "body", content: .text("本手册将带领您进入生命最基本的构建模块——细胞的微观世界。从线粒体这一细胞的‘能量工厂’，到控制一切的细胞核，您将探索它们是如何协同工作，支撑起整个生命体的宏伟秩序的。\n\n探索科学，理解生命的每一层奥秘。"), textColorHex: "#2C3E50")
        
        let p1f3 = PageFrame(kind: .text, rect: Rect(x: 297, y: 200, width: 193.5, height: 200), styleId: "tagline", content: .text("LayoutD 智能排版系统\n\n版本：第一阶段交付作品\n支持多栏网格计算\n专业印刷出血线与裁切标记\n\n官方网站: www.layoutd.org\n联系我们: info@layoutd.org"), textColorHex: "#A3BCB6")
        
        let p1f4 = PageFrame(kind: .text, rect: Rect(x: 562.5, y: 140, width: 193.5, height: 120), styleId: "title", content: .text("细胞的\n微观奥秘"), textColorHex: "#FFFFFF")
        let p1f5 = PageFrame(kind: .text, rect: Rect(x: 562.5, y: 280, width: 193.5, height: 100), styleId: "subtitle", content: .text("探索生命的微观构建基石与能量中心"), textColorHex: "#E07A5F")
        let p1f6 = PageFrame(kind: .text, rect: Rect(x: 562.5, y: 500, width: 193.5, height: 40), styleId: "tagline", content: .text("第 1 阶段交付设计作品\nLayoutD Engine"), textColorHex: "#A3BCB6")
        
        let page1 = LaidOutPage(number: 1, frames: [
            p1bg1, p1bg2, p1bg3, p1banner,
            p1f1, p1f2, p1f3, p1f4, p1f5, p1f6
        ])
        
        // Page 2 (Inside Panels)
        // Background frame:
        let p2bg = PageFrame(kind: .image, rect: Rect(x: 0, y: 0, width: 792, height: 612), content: .empty, backgroundColorHex: "#F4F1EA")
        
        // Content frames (Inside):
        // Panel 1
        let p2f1 = PageFrame(kind: .text, rect: Rect(x: 36, y: 50, width: 193.5, height: 30), styleId: "heading", content: .text("生命之源：细胞"), textColorHex: "#1C3F3A")
        let p2f2 = PageFrame(kind: .text, rect: Rect(x: 36, y: 90, width: 193.5, height: 450), styleId: "body", content: .text("所有已知的生物体都是由细胞组成的。细胞是生命的基本单位，承载着生物体的全部遗传信息与代谢功能。\n\n细胞虽小，却包含着极其精密的内部结构。不同的细胞器各司其职，像一个运转良好的现代化微型城市，进行着高效的协作。"), textColorHex: "#1C3F3A")
        
        // Panel 2
        let p2f3 = PageFrame(kind: .text, rect: Rect(x: 301.5, y: 50, width: 193.5, height: 30), styleId: "heading", content: .text("微观超微结构"), textColorHex: "#1C3F3A")
        let p2f4 = PageFrame(kind: .image, rect: Rect(x: 301.5, y: 90, width: 193.5, height: 145), content: .asset(assetId))
        let p2f5 = PageFrame(kind: .text, rect: Rect(x: 301.5, y: 245, width: 193.5, height: 30), styleId: "tagline", content: .text("图 2-1 细胞超微结构示意图"), textColorHex: "#E07A5F")
        let p2f6 = PageFrame(kind: .text, rect: Rect(x: 301.5, y: 280, width: 193.5, height: 280), styleId: "body", content: .text("如图所示，细胞膜包裹着细胞质。在细胞质内，悬浮着线粒体、内质网、高尔基体等各种细胞器。细胞核位于中心，保存着生命的蓝图——DNA。"), textColorHex: "#1C3F3A")
        
        // Panel 3
        let p2f7 = PageFrame(kind: .text, rect: Rect(x: 567, y: 50, width: 189, height: 30), styleId: "heading", content: .text("能量工厂：线粒体"), textColorHex: "#1C3F3A")
        let p2f8 = PageFrame(kind: .text, rect: Rect(x: 567, y: 90, width: 189, height: 450), styleId: "body", content: .text("线粒体是细胞的有氧呼吸中心，被称为‘能量工厂’。它们通过复杂的化学反应，将我们摄入的营养物质转化为三磷酸腺苷（ATP）。\n\nATP 是生命活动的直接能量来源。无论是肌肉的收缩，还是神经信号的传递，都依赖于线粒体源源不断产生的能量支持。"), textColorHex: "#1C3F3A")
        
        let page2 = LaidOutPage(number: 2, frames: [
            p2bg,
            p2f1, p2f2, p2f3, p2f4, p2f5, p2f6, p2f7, p2f8
        ])
        
        let document = LaidOutDocument(projectId: project.id, pages: [page1, page2])
        
        // 导出到临时目录——不能写死本机绝对路径（曾写死某 AI 的 brain 目录，换机/CI 即失败）。
        let artifactsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-brochure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: artifactsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: artifactsDir) }
        let pdfURL = artifactsDir.appendingPathComponent("brochure.pdf")
        
        try PDFExporter().export(
            document: document,
            project: project,
            to: pdfURL,
            drawCropMarks: true
        )
        
        print("Generated brochure PDF at: \(pdfURL.path)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: pdfURL.path))
        
        let pngUrls = try PNGExporter().export(
            document: document,
            project: project,
            to: artifactsDir,
            scale: 2.0,
            drawCropMarks: true
        )
        
        print("Generated brochure PNGs at: \(pngUrls.map(\.path))")
        XCTAssertEqual(pngUrls.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: pngUrls[0].path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pngUrls[1].path))
    }

    func testUndoRedoStack() {
        let state = AppState(project: .sample)
        
        XCTAssertFalse(state.canUndo)
        XCTAssertFalse(state.canRedo)
        
        let oldTitle = state.project.metadata.title
        state.updateProject { project in
            project.metadata.title = "Undo Title Test"
        }
        
        XCTAssertEqual(state.project.metadata.title, "Undo Title Test")
        XCTAssertTrue(state.canUndo)
        XCTAssertFalse(state.canRedo)
        
        state.undo()
        XCTAssertEqual(state.project.metadata.title, oldTitle)
        XCTAssertFalse(state.canUndo)
        XCTAssertTrue(state.canRedo)
        
        state.redo()
        XCTAssertEqual(state.project.metadata.title, "Undo Title Test")
        XCTAssertTrue(state.canUndo)
        XCTAssertFalse(state.canRedo)
    }

    func testLockAndUnlockPage() {
        let state = AppState(project: .sample)
        let pageNum = 3
        
        XCTAssertFalse(state.project.safeLockedPages.contains(pageNum))
        XCTAssertNil(state.project.safeAppliedLayoutPlans[pageNum])
        
        state.lockPage(number: pageNum)
        XCTAssertTrue(state.project.safeLockedPages.contains(pageNum))
        XCTAssertNotNil(state.project.safeAppliedLayoutPlans[pageNum])
        
        state.unlockPage(number: pageNum)
        XCTAssertFalse(state.project.safeLockedPages.contains(pageNum))
        XCTAssertNotNil(state.project.safeAppliedLayoutPlans[pageNum])
    }

    func testCompositeFontModifications() {
        let state = AppState(project: .sample)
        
        // 1. Verify character classification
        XCTAssertEqual(Character("A").compositeFontClass, .latin)
        XCTAssertEqual(Character("1").compositeFontClass, .digit)
        XCTAssertEqual(Character("中").compositeFontClass, .chinese)
        XCTAssertEqual(Character("，").compositeFontClass, .fullWidthPunctuation)
        
        // 2. Modify composite font mappings for the body style
        let bodyId = StyleID.body.rawValue
        
        state.updateParagraphStyleCompositeFont(
            id: bodyId,
            charClass: .latin,
            fontName: "Georgia",
            sizeMultiplier: 1.2,
            baselineOffset: 1.5
        )
        
        let updatedStyle = state.project.styles.paragraphStyle(id: bodyId)
        let latinMapping = updatedStyle.fontMapping(for: "A")
        XCTAssertEqual(latinMapping.fontName, "Georgia")
        XCTAssertEqual(latinMapping.sizeMultiplier, 1.2)
        XCTAssertEqual(latinMapping.baselineOffset, 1.5)
        
        // Chinese mapping should fallback or remain default
        let chineseMapping = updatedStyle.fontMapping(for: "中")
        XCTAssertEqual(chineseMapping.fontName, "方正兰亭细黑简体")   // 正文 CJK 字体（用户书稿）
        
        // 3. Verify makeAttributedString produces multiple font runs
        let text = "Hello 世界 123"
        let attrString = ChineseTypesetting.makeAttributedString(
            text: text,
            style: updatedStyle,
            zoomScale: 1.0
        )
        
        // We should have distinct fonts for different segments
        var count = 0
        attrString.enumerateAttribute(NSAttributedString.Key(kCTFontAttributeName as String), in: NSRange(location: 0, length: attrString.length), options: []) { value, range, stop in
            if let font = value as? NSFont {
                let name = font.fontName
                if range.location == 0 { // Hello (latin)
                    XCTAssertTrue(name.contains("Georgia") || name.contains("Times"), "Expected Georgia/Times but got \(name)")
                } else if range.location == 6 { // 世界 (chinese)
                    XCTAssertTrue(name.contains("FZL") || name.contains("Lanting"), "Expected 方正兰亭细黑(FZL...) but got \(name)")
                }
            }
            count += 1
        }
        XCTAssertGreaterThan(count, 1)
    }

    func testComplianceGateAndLayoutVariants() throws {
        // 1. Test Compliance Gate - Fonts
        var project = BookProject.sample
        var styles = project.styles.paragraphStyles
        if let idx = styles.firstIndex(where: { $0.id == StyleID.body.rawValue }) {
            styles[idx].fontName = "完全不存在的字体XYZ"   // 未安装→应被合规闸门拒
        }
        project.styles.paragraphStyles = styles
        
        // Add a plan that uses the body style (which has unapproved font)
        let plan = LayoutPlan(
            target: .page(3),
            strategy: .balanced,
            blocks: [
                LayoutPlanBlock(
                    kind: .text,
                    role: "body",
                    frame: Rect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
                    contentReference: .generated("Sample text")
                )
            ]
        )
        project.safeAppliedLayoutPlans[3] = plan
        
        let docWithBadFont = LayoutEngine().layout(project: project)
        let badFontIssues = docWithBadFont.issues.filter { $0.message.contains("版式计划无效") }
        XCTAssertFalse(badFontIssues.isEmpty, "Should reject plan with unapproved font")
        XCTAssertTrue(badFontIssues.first?.message.contains("未安装字体") == true)

        // 2. Test Compliance Gate - Component Roles
        var project2 = BookProject.sample
        let badComponentPlan = LayoutPlan(
            target: .page(3),
            strategy: .balanced,
            blocks: [
                LayoutPlanBlock(
                    kind: .component,
                    role: "unapprovedComponentRole",
                    frame: Rect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
                    contentReference: .generated("Unapproved component")
                )
            ]
        )
        project2.safeAppliedLayoutPlans[3] = badComponentPlan
        
        let docWithBadComponent = LayoutEngine().layout(project: project2)
        let badComponentIssues = docWithBadComponent.issues.filter { $0.message.contains("版式计划无效") }
        XCTAssertFalse(badComponentIssues.isEmpty, "Should reject plan with unapproved component role")
        XCTAssertTrue(badComponentIssues.first?.message.contains("组件角色 unapprovedComponentRole 未在组件样式库中定义") == true)

        // 3. Test Compliance Gate - Color overrides
        var project3 = BookProject.sample
        let badColorPlan = LayoutPlan(
            target: .page(3),
            strategy: .balanced,
            blocks: [
                LayoutPlanBlock(
                    kind: .text,
                    role: "body",
                    frame: Rect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
                    contentReference: .generated("Sample text"),
                    backgroundColorHex: "unapprovedColorToken"
                )
            ]
        )
        project3.safeAppliedLayoutPlans[3] = badColorPlan
        
        let docWithBadColor = LayoutEngine().layout(project: project3)
        let badColorIssues = docWithBadColor.issues.filter { $0.message.contains("版式计划无效") }
        XCTAssertFalse(badColorIssues.isEmpty, "Should reject plan with unapproved color token")
        XCTAssertTrue(badColorIssues.first?.message.contains("背景色引用了未批准的 Token 或无效颜色值") == true)

        // 4. Test Layout Variants (proposePlans from SpreadPlannerBackedAdvisor)
        let state = AppState(project: .sample)
        // SpreadPlannerBackedAdvisor returns plans based on content fingerprint.
        // For the sample project, we should get at least one proposed plan.
        let proposed = state.plans
        XCTAssertFalse(proposed.isEmpty, "Advisor should propose at least one plan")
        
        // All proposed plans should have a valid strategy
        for plan in proposed {
            XCTAssertTrue(LayoutStrategy.allCases.contains(plan.strategy),
                         "Plan strategy \(plan.strategy) should be a valid LayoutStrategy")
        }
    }

    func testQualityMetricsHistory() throws {
        // 1. Initial history entry on creation
        let state = AppState(project: .sample)
        XCTAssertEqual(state.project.safeQualityMetricsHistory.count, 1)
        
        let initialEntry = state.project.safeQualityMetricsHistory[0]
        XCTAssertGreaterThan(initialEntry.pageCount, 0)
        
        // 2. Trigger mutation that changes quality metrics (applied layout plan)
        let plan = LayoutPlan(
            target: .page(3),
            strategy: .balanced,
            blocks: [
                LayoutPlanBlock(
                    kind: .text,
                    role: "body",
                    frame: Rect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
                    contentReference: .generated("Sample text")
                )
            ]
        )
        state.updateProject { project in
            project.safeAppliedLayoutPlans[3] = plan
        }
        
        XCTAssertEqual(state.project.safeQualityMetricsHistory.count, 2)
        
        // 3. Recalculating layout with no changes shouldn't add duplicates
        state.recalculateLayout()
        XCTAssertEqual(state.project.safeQualityMetricsHistory.count, 2)
        
        // 4. Test cap of 30 entries
        var history = state.project.safeQualityMetricsHistory
        for i in 1...35 {
            let mockEntry = QualityHistoryEntry(
                timestamp: Date().addingTimeInterval(Double(i)),
                pageCount: 10 + i, // different pageCount to avoid duplicate prevention
                totalFrames: 20,
                averageFramesPerPage: 2.0,
                planAppliedPages: 2,
                autoLaidOutPages: 8,
                lowResolutionAssets: 0,
                missingCaptionAssets: 0,
                blockingErrors: 0,
                layoutIssues: 0
            )
            history.append(mockEntry)
        }
        state.project.qualityMetricsHistory = history
        // Mutating the project property triggers an immediate synchronous layout recalculation,
        // which runs the history recorder and caps the history array to 30.
        XCTAssertEqual(state.project.safeQualityMetricsHistory.count, 30)
        
        // Now trigger one more recalculation with a different pageCount/metrics
        let plan2 = LayoutPlan(
            target: .page(4),
            strategy: .balanced,
            blocks: [
                LayoutPlanBlock(
                    kind: .text,
                    role: "body",
                    frame: Rect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
                    contentReference: .generated("Sample text 2")
                )
            ]
        )
        state.updateProject { project in
            project.safeAppliedLayoutPlans[4] = plan2
        }
        
        // The recalculation should cap the history to 30
        XCTAssertEqual(state.project.safeQualityMetricsHistory.count, 30)
        
        // 5. Test JSON round-trip serialization of history
        let encoded = try JSONEncoder().encode(state.project)
        let decoded = try JSONDecoder().decode(BookProject.self, from: encoded)
        XCTAssertEqual(decoded.safeQualityMetricsHistory.count, 30)
        XCTAssertEqual(decoded.safeQualityMetricsHistory.last?.pageCount, state.project.safeQualityMetricsHistory.last?.pageCount)
    }

    // PERF-2: the baseline (plans-stripped) document is only re-laid-out when
    // content actually changes; plan-only edits reuse the cached baseline.
    func testBaselineLayoutCacheSkipsPlanOnlyChanges() {
        let state = AppState(project: BookProject.sample)
        XCTAssertEqual(state.baselineLayoutCount, 1)
        XCTAssertNotNil(state.baselineDocument)

        // Applying a layout plan must not trigger a second baseline layout…
        state.applyPageLayoutTemplate(.textLedPage, toPage: 2)
        XCTAssertEqual(state.baselineLayoutCount, 1)
        // …and neither must undo/redo of that plan-only edit.
        state.undo()
        state.redo()
        XCTAssertEqual(state.baselineLayoutCount, 1)

        // A content edit must recompute the baseline.
        state.updateProject { project in
            project.sections[0].stories[0].paragraphs[0].text += "（内容变更）"
        }
        XCTAssertEqual(state.baselineLayoutCount, 2)
    }

    func testAsyncDebouncedLayout() {
        let state = AppState(project: BookProject.sample)
        state.isAsync = true
        
        var layoutCount = 0
        state.onLayoutCompleted = { _, _ in
            layoutCount += 1
        }
        
        // Mutate the project multiple times rapidly
        for i in 1...5 {
            state.updateProject { project in
                project.sections[0].stories[0].paragraphs[0].text = "快速修改 \(i)"
            }
        }
        
        // In async mode, layout should not have completed yet
        XCTAssertEqual(layoutCount, 0)
        
        let expectation = self.expectation(description: "Async layout completes")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            // It should have layouted exactly once (coalesced 5 mutations)
            XCTAssertEqual(layoutCount, 1)
            expectation.fulfill()
        }
        
        self.wait(for: [expectation], timeout: 2.0)
    }
}
