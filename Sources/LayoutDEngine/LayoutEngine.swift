import CoreText
import Foundation
import LayoutDCore

public final class LayoutHeightCache: @unchecked Sendable {
    public static let shared = LayoutHeightCache()
    private init() {}
    
    struct Key: Hashable {
        let text: String
        let fontName: String
        let fontSize: Double
        let lineHeight: Double
        let firstLineIndent: Double
        let layoutDirection: LayoutDirection?
        let width: Double
        let inlineRuns: [InlineRun]?
        let compositeFont: [CompositeFontClass: CompositeFontMapping]?
    }
    
    let lock = NSLock()
    var cache: [Key: Double] = [:]
    
    public func get(text: String, style: ParagraphStyle, width: Double, inlineRuns: [InlineRun]? = nil) -> Double? {
        let key = Key(
            text: text,
            fontName: style.fontName,
            fontSize: style.fontSize,
            lineHeight: style.lineHeight,
            firstLineIndent: style.firstLineIndent,
            layoutDirection: style.layoutDirection,
            width: width,
            inlineRuns: inlineRuns,
            compositeFont: style.compositeFont
        )
        lock.lock()
        defer { lock.unlock() }
        return cache[key]
    }
    
    public func set(text: String, style: ParagraphStyle, width: Double, inlineRuns: [InlineRun]? = nil, height: Double) {
        let key = Key(
            text: text,
            fontName: style.fontName,
            fontSize: style.fontSize,
            lineHeight: style.lineHeight,
            firstLineIndent: style.firstLineIndent,
            layoutDirection: style.layoutDirection,
            width: width,
            inlineRuns: inlineRuns,
            compositeFont: style.compositeFont
        )
        lock.lock()
        defer { lock.unlock() }
        if cache.count >= 5000 {
            cache.removeAll()
        }
        cache[key] = height
    }
    
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }
    
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return cache.count
    }
}


/// Single source of truth for how many front-matter pages (cover, contents)
/// precede the content pages. The content engine numbers pages from 1 and adds
/// this offset to reach the absolute page number used by page setup, plans and
/// preflight. NOTE: this still assumes a fixed front-matter size; multi-page
/// contents or extra front matter would require deriving this from the assembled
/// front matter instead of a constant (see docs/architecture.md known limitations).
/// 前置页数：封面恒 1 页；目录页仅在 `pageSetup.includesTableOfContents` 为真时 +1。
/// 默认不含目录（用户 2026-07-07 定：一章一章排版）。据此推导，不再是固定常量。
func frontMatterPageCount(for project: BookProject) -> Int {
    project.pageSetup.includesTableOfContents ? 2 : 1
}

/// Geometry of the running header, shared by header generation so the value is
/// defined in exactly one place rather than scattered as literals.
let runningHeaderTopY = 24.0
let runningHeaderHeight = 16.0

public protocol LayoutEngineProtocol: Sendable {
    func layout(project: BookProject) -> LaidOutDocument
}

public struct LayoutEngine: LayoutEngineProtocol {
    public init() {}

    public func layout(project: BookProject) -> LaidOutDocument {
        var context = LayoutContext(project: project)
        context.addRunningHeader(project.metadata.title)
        context.applyPlanIfPresent()

        for section in project.sections {
            context.addSectionTitle(section.title)
            for story in section.stories {
                context.addStory(story)
            }
        }

        return context.finishWithFrontMatter()
    }
}
struct LayoutContext {
    let project: BookProject
    var pages: [LaidOutPage] = []
    var issues: [LayoutIssue] = []

    var currentPage: LaidOutPage
    var cursorX: Double
    var cursorY: Double
    var currentColumnTopY: Double
    var currentColumn: Int = 0
    var placedAssetIds = Set<UUID>()
    var placedParagraphIds = Set<UUID>()
    var tableOfContents: [TableOfContentsEntry] = []
    var figureCounter = 0
    
    var currentPageFootnoteParagraphs: [Paragraph] = []
    var currentPageSideNoteParagraphs: [(Paragraph, Double)] = []
    var threadedRemainingText: [UUID: String] = [:]
    var deferredUnderlayFrames: [Int: [PageFrame]] = [:]

    var footnoteStyle: ParagraphStyle {
        ParagraphStyle(
            id: "footnote",
            displayName: "脚注",
            fontName: "Songti SC",
            fontSize: 8.5,
            lineHeight: 11,
            firstLineIndent: 0,
            spaceBefore: 0,
            spaceAfter: 4,
            colorToken: "ink"
        )
    }

    var sideNoteStyle: ParagraphStyle {
        ParagraphStyle(
            id: "sideNote",
            displayName: "旁注",
            fontName: "Songti SC",
            fontSize: 6.0,
            lineHeight: 8.0,
            firstLineIndent: 0,
            spaceBefore: 0,
            spaceAfter: 2,
            colorToken: "ink"
        )
    }

    init(project: BookProject) {
        self.project = project
        self.currentPage = LaidOutPage(number: 1)
        let initialPageNumber = 1 + frontMatterPageCount(for: project)
        let margins = project.resolvedMargins(for: initialPageNumber)
        let setup = project.pageSetup
        
        let leftMargin = setup.facingPages
            ? (initialPageNumber % 2 == 1 ? margins.left : margins.right)
            : margins.left
            
        let rightMargin = setup.facingPages
            ? (initialPageNumber % 2 == 1 ? margins.right : margins.left)
            : margins.right
            
        if setup.layoutDirection == .vertical {
            self.cursorX = setup.pageSize.width - rightMargin
            self.cursorY = margins.top
            self.currentColumnTopY = margins.top
        } else {
            self.cursorX = leftMargin
            self.cursorY = margins.top
            self.currentColumnTopY = margins.top
        }
    }

    mutating func addRunningHeader(_ title: String) {
        let actualPageNumber = currentAbsolutePageNumber
        guard project.resolvedShowHeadersFooters(for: actualPageNumber) else {
            return
        }
        let rect = Rect(
            x: pageLeftMargin(for: actualPageNumber),
            y: runningHeaderTopY,
            width: contentWidth,
            height: runningHeaderHeight
        )
        currentPage.frames.append(
            PageFrame(kind: .runningHeader, rect: rect, styleId: StyleID.caption.rawValue, content: .text(title))
        )
    }

    mutating func addSectionTitle(_ title: String) {
        // 角色标签书稿（DOCX 全部、Markdown 无 `#` 标题时）没有独立于正文的「章节标题」——
        // 真正的标题已经是「一级标题/章名」角色段落本身，会随 addStory 正常画出。
        // section.title 此时是空字符串占位（或 DOCX 侧退化成书名），再画一次就是重复的
        // 空壳标题框（2026-07-07 用户在标准样章画布验收时发现的「正文」孤立框）。
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tableOfContents.append(TableOfContentsEntry(level: 1, title: title, pageNumber: currentPage.number))
        addText(title, style: .heading1, kind: .text)
    }

    mutating func addStory(_ story: Story) {
        if !story.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           tableOfContents.last?.title != story.title {
            tableOfContents.append(TableOfContentsEntry(level: 2, title: story.title, pageNumber: currentPage.number))
        }

        for paragraph in story.paragraphs {
            if placedParagraphIds.contains(paragraph.id) {
                continue
            }

            switch paragraph.kind {
            case .footnote, .sideNote:
                continue
            default:
                break
            }

            if case .figure(let assetId) = paragraph.kind {
                if let asset = project.assets.first(where: { $0.id == assetId }) {
                    addAsset(asset, sourceParagraphId: paragraph.id)
                } else {
                    issues.append(
                        LayoutIssue(
                            severity: .warning,
                            message: "书稿引用了不存在的图片素材",
                            category: .references,
                            pageNumber: currentPage.number
                        )
                    )
                }
                continue
            }

            // 正文里的子标题（H2+）也进目录，否则静态目录只剩书名级 H1、需用户在
            // InDesign 手动「更新目录」才补全。level 1 走 addSectionTitle 不在此重复收集。
            if case .heading(let level) = paragraph.kind, level >= 2 {
                let headingTitle = paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !headingTitle.isEmpty, tableOfContents.last?.title != headingTitle {
                    tableOfContents.append(TableOfContentsEntry(level: level, title: headingTitle, pageNumber: currentPage.number))
                }
            }

            let style = project.styles.paragraphStyle(id: paragraph.styleId)
            let frameKind = frameKind(for: paragraph.kind)

            if project.pageSetup.layoutDirection == .vertical {
                let minReqWidth = style.lineHeight + style.spaceBefore + style.spaceAfter
                let leftLimit = pageLeftMargin(for: currentAbsolutePageNumber)
                if cursorX - minReqWidth < leftLimit {
                    advanceToNextColumnOrPage()
                }
            } else {
                let minReqHeight = style.lineHeight + style.spaceBefore + style.spaceAfter
                if remainingColumnHeight < minReqHeight {
                    advanceToNextColumnOrPage()
                }
            }
            
            for fnId in paragraph.safeAnchoredFootnoteIds {
                if let fnParagraph = story.paragraphs.first(where: { $0.id == fnId }) {
                    if !currentPageFootnoteParagraphs.contains(where: { $0.id == fnId }) {
                        currentPageFootnoteParagraphs.append(fnParagraph)
                    }
                }
            }
            
            addText(paragraph.text, style: style, kind: frameKind, anchoredSideNoteIds: paragraph.safeAnchoredSideNoteIds, sourceParagraphId: paragraph.id)

            for assetId in paragraph.anchoredAssetIds {
                if let asset = project.assets.first(where: { $0.id == assetId }) {
                    addAsset(asset, sourceParagraphId: paragraph.id)
                }
            }
        }
    }

    mutating func finish() -> LaidOutDocument {
        layoutFootnotesAndSideNotesOnCurrentPage()
        if !currentPage.frames.isEmpty || pages.isEmpty {
            pages.append(currentPage)
        }
        
        let maxDeferredPage = deferredUnderlayFrames.keys.max() ?? 0
        while pages.count < maxDeferredPage {
            let nextNum = pages.count + 1
            var emptyPage = LaidOutPage(number: nextNum)
            if let deferred = deferredUnderlayFrames[nextNum] {
                emptyPage.frames.append(contentsOf: deferred)
            }
            pages.append(emptyPage)
        }

        // 手动插入的空白页可能排在所有正文内容之后——正常翻页只在内容溢出时才触发
        // advanceToNextPage()/applyPlanIfPresent()，不会主动去看最后一页之后还有没有
        // 排版计划。这里补一次：只要下一页确实有计划（哪怕只是空白页占位）就继续
        // materialize；命中 reservesBlankPage/有 blocks 的计划，plan 内部的
        // advanceToNextPage() 会自己把该页追加进 pages 并推进到下一页，外层循环接着
        // 检查更后面的页码，从而级联多页插入。不这样补，在文档末尾插入空白页会因为
        // 没有内容触发翻页而悄悄没有反应。
        while project.appliedLayoutPlans?[absolutePageNumber(for: pages.count + 1)] != nil {
            let countBefore = pages.count
            currentPage = LaidOutPage(number: pages.count + 1)
            if let deferred = deferredUnderlayFrames[currentPage.number] {
                currentPage.frames.append(contentsOf: deferred)
            }
            applyPlanIfPresent()
            if pages.count == countBefore {
                // 极端情况下计划命中了但没有触发翻页（既没有 blocks 也不满足
                // reservesBlankPage，比如只带了 marginOverride）——避免死循环，
                // 这页也补上（非空才追加，跟上面的判断一致）后退出。
                if !currentPage.frames.isEmpty {
                    pages.append(currentPage)
                }
                break
            }
        }
        return LaidOutDocument(projectId: project.id, pages: pages, issues: issues)
    }

    mutating func finishWithFrontMatter() -> LaidOutDocument {
        let offset = frontMatterPageCount(for: project)
        let contentDocument = finish()
        let contentPages = contentDocument.pages.map { renumberedPage($0, offset: offset) }
        let shiftedIssues = contentDocument.issues.map { shiftedIssue($0, offset: offset) }
        let shiftedContents = tableOfContents.map {
            TableOfContentsEntry(level: $0.level, title: $0.title, pageNumber: $0.pageNumber + offset)
        }

        // 封面恒有；目录仅在开启时生成（默认关，一章一章排版不加目录）。
        var frontPages: [LaidOutPage] = [makeCoverPage(number: 1)]
        if project.pageSetup.includesTableOfContents {
            frontPages.append(makeContentsPage(number: 2, entries: shiftedContents))
        }

        return LaidOutDocument(
            projectId: project.id,
            pages: frontPages + contentPages,
            issues: shiftedIssues
        )
    }
}
