import Foundation

public enum ContentRole: Sendable {
    case heading1, heading2, heading3, introduction, introductionEnglish, pullQuote, bibliography
    public static func tag(in text: String) -> ContentRole? {
        // 标签可能是斜杠合写（"一级标题/章名"）或单独形式（"章名"），按斜杠拆开后任一段命中即可。
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = raw.split(separator: "/").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let keys = parts.isEmpty ? [raw] : parts
        for key in keys {
            switch key {
            case "一级标题", "章名": return .heading1
            case "二级标题", "节名": return .heading2
            case "三级标题", "文章名": return .heading3
            case "开节概述": return .introduction
            case "开节概述英文": return .introductionEnglish
            case "抽言": return .pullQuote
            case "参考文献": return .bibliography
            default: continue
            }
        }
        return nil
    }
    public static func shouldDiscard(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("可视化信息：") }
    public var styleID: String { switch self { case .heading1: return StyleID.heading1.rawValue; case .heading2: return StyleID.heading2.rawValue; case .heading3: return StyleID.heading3.rawValue; case .introduction: return StyleID.introduction.rawValue; case .introductionEnglish: return StyleID.introductionEnglish.rawValue; case .pullQuote: return StyleID.pullQuote.rawValue; case .bibliography: return StyleID.bibliography.rawValue } }
    public var paragraphKind: ParagraphKind { switch self { case .heading1: return .heading(level: 1); case .heading2: return .heading(level: 2); case .heading3: return .heading(level: 3); default: return .body } }
    /// 单段角色（标题/抽言）只作用于标签后紧邻的一段，之后复位为正文；
    /// 跨段角色（概述/英文概述/参考文献）持续到下一个标签。
    public var isSingleParagraph: Bool { switch self { case .heading1, .heading2, .heading3, .pullQuote: return true; case .introduction, .introductionEnglish, .bibliography: return false } }
}

public struct BookProject: Codable, Equatable, Sendable, Identifiable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: UUID
    public var metadata: ProjectMetadata
    public var pageSetup: PageSetup
    public var styles: StyleLibrary
    public var sections: [BookSection]
    public var assets: [Asset]
    public var appliedLayoutPlans: [Int: LayoutPlan]?
    public var savedLayoutTemplates: [SavedLayoutTemplate]?
    public var lockedPages: Set<Int>?
    /// Active color mode for design-token resolution (e.g. a chapter theme group
    /// such as "green"/"blue" in 《何以江南》). nil → the token set's default mode.
    /// Optional & additive: old `.layoutd` files decode with `colorMode == nil`.
    public var colorMode: String?
    /// Historical snapshots of layout quality metrics, captured over time.
    public var qualityMetricsHistory: [QualityHistoryEntry]?
    public var annotations: [BookAnnotation]?
    /// User-saved swatch library (the "色板" panel). Optional & additive: old
    /// `.layoutd` files decode with `customSwatches == nil`.
    public var customSwatches: [PrintSwatch]?
    public var wizardState: WizardState?
    public var styleProfile: StyleProfile?
    public var styleReport: StyleReport?
    public var motifs: SpecPackMotifs?

    public init(
        schemaVersion: Int = BookProject.currentSchemaVersion,
        id: UUID = UUID(),
        metadata: ProjectMetadata,
        pageSetup: PageSetup = .scienceBookDefault,
        styles: StyleLibrary = .defaultChineseScience,
        sections: [BookSection] = [],
        assets: [Asset] = [],
        appliedLayoutPlans: [Int: LayoutPlan]? = nil,
        savedLayoutTemplates: [SavedLayoutTemplate]? = nil,
        lockedPages: Set<Int>? = nil,
        colorMode: String? = nil,
        qualityMetricsHistory: [QualityHistoryEntry]? = nil,
        annotations: [BookAnnotation]? = nil,
        customSwatches: [PrintSwatch]? = nil,
        wizardState: WizardState? = nil,
        styleProfile: StyleProfile? = nil,
        styleReport: StyleReport? = nil,
        motifs: SpecPackMotifs? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.metadata = metadata
        self.pageSetup = pageSetup
        self.styles = styles
        self.sections = sections
        self.assets = assets
        self.appliedLayoutPlans = appliedLayoutPlans
        self.savedLayoutTemplates = savedLayoutTemplates
        self.lockedPages = lockedPages
        self.colorMode = colorMode
        self.qualityMetricsHistory = qualityMetricsHistory
        self.annotations = annotations
        self.customSwatches = customSwatches
        self.wizardState = wizardState
        self.styleProfile = styleProfile
        self.styleReport = styleReport
        self.motifs = motifs
    }

    public var safeAnnotations: [BookAnnotation] {
        get { annotations ?? [] }
        set { annotations = newValue }
    }

    public var safeCustomSwatches: [PrintSwatch] {
        get { customSwatches ?? [] }
        set { customSwatches = newValue }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case metadata
        case pageSetup
        case styles
        case sections
        case assets
        case appliedLayoutPlans
        case savedLayoutTemplates
        case lockedPages
        case colorMode
        case qualityMetricsHistory
        case annotations
        case customSwatches
        case wizardState
        case styleProfile
        case styleReport
        case motifs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? BookProject.currentSchemaVersion
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        metadata = try container.decode(ProjectMetadata.self, forKey: .metadata)
        pageSetup = try container.decodeIfPresent(PageSetup.self, forKey: .pageSetup) ?? .scienceBookDefault
        styles = try container.decodeIfPresent(StyleLibrary.self, forKey: .styles) ?? .defaultChineseScience
        sections = try container.decodeIfPresent([BookSection].self, forKey: .sections) ?? []
        assets = try container.decodeIfPresent([Asset].self, forKey: .assets) ?? []
        appliedLayoutPlans = try container.decodeIfPresent([Int: LayoutPlan].self, forKey: .appliedLayoutPlans)
        savedLayoutTemplates = try container.decodeIfPresent([SavedLayoutTemplate].self, forKey: .savedLayoutTemplates)
        lockedPages = try container.decodeIfPresent(Set<Int>.self, forKey: .lockedPages)
        colorMode = try container.decodeIfPresent(String.self, forKey: .colorMode)
        qualityMetricsHistory = try container.decodeIfPresent([QualityHistoryEntry].self, forKey: .qualityMetricsHistory)
        annotations = try container.decodeIfPresent([BookAnnotation].self, forKey: .annotations)
        customSwatches = try container.decodeIfPresent([PrintSwatch].self, forKey: .customSwatches)
        wizardState = try container.decodeIfPresent(WizardState.self, forKey: .wizardState)
        styleProfile = try container.decodeIfPresent(StyleProfile.self, forKey: .styleProfile)
        styleReport = try container.decodeIfPresent(StyleReport.self, forKey: .styleReport)
        motifs = try container.decodeIfPresent(SpecPackMotifs.self, forKey: .motifs)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(metadata, forKey: .metadata)
        try container.encode(pageSetup, forKey: .pageSetup)
        try container.encode(styles, forKey: .styles)
        try container.encode(sections, forKey: .sections)
        try container.encode(assets, forKey: .assets)
        try container.encodeIfPresent(appliedLayoutPlans, forKey: .appliedLayoutPlans)
        try container.encodeIfPresent(savedLayoutTemplates, forKey: .savedLayoutTemplates)
        try container.encodeIfPresent(lockedPages, forKey: .lockedPages)
        try container.encodeIfPresent(colorMode, forKey: .colorMode)
        try container.encodeIfPresent(qualityMetricsHistory, forKey: .qualityMetricsHistory)
        try container.encodeIfPresent(annotations, forKey: .annotations)
        try container.encodeIfPresent(customSwatches, forKey: .customSwatches)
        try container.encodeIfPresent(wizardState, forKey: .wizardState)
        try container.encodeIfPresent(styleProfile, forKey: .styleProfile)
        try container.encodeIfPresent(styleReport, forKey: .styleReport)
        try container.encodeIfPresent(motifs, forKey: .motifs)
    }

    /// Resolves a color token id to a hex value under the project's active color
    /// mode, via the style library (design tokens preferred, legacy colors as
    /// fallback). Renderers should use this so color modes apply consistently.
    public func resolvedColorHex(_ id: String) -> String? {
        styles.colorHex(id, mode: colorMode)
    }

    public var safeAppliedLayoutPlans: [Int: LayoutPlan] {
        get { appliedLayoutPlans ?? [:] }
        set { appliedLayoutPlans = newValue }
    }

    public var safeSavedLayoutTemplates: [SavedLayoutTemplate] {
        get { savedLayoutTemplates ?? [] }
        set { savedLayoutTemplates = newValue }
    }

    public var safeLockedPages: Set<Int> {
        get { lockedPages ?? [] }
        set { lockedPages = newValue }
    }

    public var safeQualityMetricsHistory: [QualityHistoryEntry] {
        get { qualityMetricsHistory ?? [] }
        set { qualityMetricsHistory = newValue }
    }

    public static let sample = BookProject(
        metadata: ProjectMetadata(
            title: "layoutD 科普样章",
            subtitle: "AI 图文排版系统架构样例",
            author: "layoutD",
            publisher: "layoutD Press",
            isbn: "9787115546081",
            series: "AI 图书排版实验",
            keywords: ["中文排版", "科普图书", "AI"]
        ),
        // 整书 demo：显式开启目录（默认 PageSetup 不含目录，一章一章排版用）。
        pageSetup: .scienceBookDefault.withTableOfContents(),
        sections: [
            BookSection(
                title: "第一章 重新理解图文排版",
                stories: [
                    Story(
                        title: "图像不只是正文的附件",
                        paragraphs: [
                            Paragraph(
                                kind: .heading(level: 1),
                                text: "图像不只是正文的附件",
                                styleId: StyleID.heading1.rawValue
                            ),
                            Paragraph(
                                kind: .body,
                                text: "中文科普图书的价值，经常来自文字、图片、图注、知识卡片和跨页解释之间的协作。layoutD 的目标，是把这些内容转化为结构化对象，再由排版引擎稳定输出。",
                                styleId: StyleID.body.rawValue
                            ),
                            Paragraph(
                                kind: .callout,
                                text: "AI 负责提出版式方案，排版引擎负责确定性分页。",
                                styleId: StyleID.callout.rawValue
                            ),
                            Paragraph(
                                kind: .body,
                                text: "第一版架构先验证文档模型、页面生成、素材管理和 PDF 导出的边界。后续再逐步加入中文禁则、标点压缩、图片主体识别和更复杂的跨页布局。",
                                styleId: StyleID.body.rawValue
                            )
                        ]
                    )
                ]
            )
        ],
        assets: [
            Asset(
                fileName: "sample-diagram.png",
                role: .diagram,
                caption: "图 1-1 图文对象在 layoutD 中的关系",
                pixelWidth: 2400,
                pixelHeight: 1600,
                dpi: 300
            )
        ]
    )
}

public struct ProjectMetadata: Codable, Equatable, Sendable {
    public var title: String
    public var subtitle: String?
    public var author: String
    public var publisher: String?
    public var isbn: String?
    public var series: String?
    public var keywords: [String]
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        title: String,
        subtitle: String? = nil,
        author: String,
        publisher: String? = nil,
        isbn: String? = nil,
        series: String? = nil,
        keywords: [String] = [],
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.title = title
        self.subtitle = subtitle
        self.author = author
        self.publisher = publisher
        self.isbn = isbn
        self.series = series
        self.keywords = keywords
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case subtitle
        case author
        case publisher
        case isbn
        case series
        case keywords
        case createdAt
        case modifiedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        author = try container.decode(String.self, forKey: .author)
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher)
        isbn = try container.decodeIfPresent(String.self, forKey: .isbn)
        series = try container.decodeIfPresent(String.self, forKey: .series)
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(subtitle, forKey: .subtitle)
        try container.encode(author, forKey: .author)
        try container.encodeIfPresent(publisher, forKey: .publisher)
        try container.encodeIfPresent(isbn, forKey: .isbn)
        try container.encodeIfPresent(series, forKey: .series)
        try container.encode(keywords, forKey: .keywords)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(modifiedAt, forKey: .modifiedAt)
    }
}

public struct BookSection: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var stories: [Story]

    public init(id: UUID = UUID(), title: String, stories: [Story] = []) {
        self.id = id
        self.title = title
        self.stories = stories
    }
}

public struct Story: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var paragraphs: [Paragraph]

    public init(id: UUID = UUID(), title: String, paragraphs: [Paragraph] = []) {
        self.id = id
        self.title = title
        self.paragraphs = paragraphs
    }
}

public struct Paragraph: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: ParagraphKind
    public var text: String
    public var styleId: String
    public var anchoredAssetIds: [UUID]
    public var anchoredFootnoteIds: [UUID]?
    public var anchoredSideNoteIds: [UUID]?
    /// Optional character-level formatting. Offsets are measured in Swift `Character`s
    /// within `text`, keeping the flattened string as the backwards-compatible truth.
    public var inlineRuns: [InlineRun]?
    /// Structured table content for `kind == .table`: outer array = rows, inner = cells.
    /// `text` keeps a flattened fallback (cells joined) for layout/preview that don't
    /// understand grids; IDML export uses this to emit a native `<Table>`. The first
    /// row is treated as the header. Optional & additive — old files decode as nil.
    public var tableCells: [[String]]?
    /// Optional per-cell inline formatting, index-aligned with `tableCells`
    /// (outer = rows, middle = cells, inner = runs whose offsets are into that
    /// cell's `tableCells` text). Lets IDML export keep bold/italic/kenten inside
    /// table cells. Optional & additive — old files decode as nil (cells render plain).
    public var tableCellRuns: [[[InlineRun]]]?

    public init(
        id: UUID = UUID(),
        kind: ParagraphKind,
        text: String,
        styleId: String,
        anchoredAssetIds: [UUID] = [],
        anchoredFootnoteIds: [UUID]? = nil,
        anchoredSideNoteIds: [UUID]? = nil,
        inlineRuns: [InlineRun]? = nil,
        tableCells: [[String]]? = nil,
        tableCellRuns: [[[InlineRun]]]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.styleId = styleId
        self.anchoredAssetIds = anchoredAssetIds
        self.anchoredFootnoteIds = anchoredFootnoteIds
        self.anchoredSideNoteIds = anchoredSideNoteIds
        self.inlineRuns = inlineRuns
        self.tableCells = tableCells
        self.tableCellRuns = tableCellRuns
    }

    public var safeAnchoredFootnoteIds: [UUID] {
        get { anchoredFootnoteIds ?? [] }
        set { anchoredFootnoteIds = newValue }
    }

    public var safeAnchoredSideNoteIds: [UUID] {
        get { anchoredSideNoteIds ?? [] }
        set { anchoredSideNoteIds = newValue }
    }
}

public enum InlineEmphasis: String, Codable, Hashable, Sendable {
    case bold
    case italic
    case kenten
}

public struct InlineRun: Codable, Equatable, Hashable, Sendable {
    public var location: Int
    public var length: Int
    public var emphasis: Set<InlineEmphasis>
    public var colorTokenRef: String?

    public init(
        location: Int,
        length: Int,
        emphasis: Set<InlineEmphasis> = [],
        colorTokenRef: String? = nil
    ) {
        self.location = location
        self.length = length
        self.emphasis = emphasis
        self.colorTokenRef = colorTokenRef
    }

    /// Maps runs from a larger string range into a substring range.
    public static func mapRuns(_ runs: [InlineRun], toSubstringFrom startIndex: Int, length: Int) -> [InlineRun] {
        var mapped: [InlineRun] = []
        let subEnd = startIndex + length
        for run in runs {
            let runEnd = run.location + run.length
            let intersectStart = max(run.location, startIndex)
            let intersectEnd = min(runEnd, subEnd)
            let intersectLength = intersectEnd - intersectStart
            if intersectLength > 0 {
                mapped.append(InlineRun(
                    location: intersectStart - startIndex,
                    length: intersectLength,
                    emphasis: run.emphasis,
                    colorTokenRef: run.colorTokenRef
                ))
            }
        }
        return mapped
    }

    /// Maps runs from one string to another by aligning their visible (non-whitespace) characters.
    public static func mapRuns(
        _ paragraphRuns: [InlineRun],
        from sourceText: String,
        to targetText: String
    ) -> [InlineRun]? {
        let sourceCharacters = Array(sourceText)
        let targetCharacters = Array(targetText)
        let sourceVisible = sourceCharacters.enumerated().filter { !$0.element.isWhitespace }
        let targetVisible = targetCharacters.enumerated().filter { !$0.element.isWhitespace }
        guard !targetVisible.isEmpty, targetVisible.count <= sourceVisible.count else { return nil }

        let matchingStart = (0...(sourceVisible.count - targetVisible.count)).first { candidate in
            zip(sourceVisible[candidate...], targetVisible).allSatisfy { pair in
                pair.0.element == pair.1.element
            }
        }
        guard let matchingStart else { return nil }

        var emphasisByTargetCharacter = Array(repeating: Set<InlineEmphasis>(), count: targetCharacters.count)
        for (visibleOffset, targetCharacter) in targetVisible.enumerated() {
            let sourceOffset = sourceVisible[matchingStart + visibleOffset].offset
            for run in paragraphRuns where run.location <= sourceOffset && sourceOffset < run.location + run.length {
                emphasisByTargetCharacter[targetCharacter.offset].formUnion(run.emphasis)
            }
        }

        var runs: [InlineRun] = []
        var start: Int?
        var active = Set<InlineEmphasis>()
        for offset in 0...emphasisByTargetCharacter.count {
            let emphasis = offset < emphasisByTargetCharacter.count ? emphasisByTargetCharacter[offset] : []
            if emphasis != active {
                if let start, !active.isEmpty {
                    runs.append(InlineRun(location: start, length: offset - start, emphasis: active))
                }
                start = emphasis.isEmpty ? nil : offset
                active = emphasis
            }
        }
        return runs.isEmpty ? nil : runs
    }
}

public enum ParagraphKind: Codable, Equatable, Sendable {
    case heading(level: Int)
    case body
    case figure(assetId: UUID)
    case caption(assetId: UUID?)
    case callout
    case table
    case listItem
    case quote
    case footnote(number: Int)
    case sideNote
}

public extension BookProject {
    var resolvedPageSetup: PageSetup {
        pageSetup.resolved(using: styles.effectiveTokens)
    }

    func resolvedMargins(for pageNumber: Int) -> PageMargins {
        if let plans = appliedLayoutPlans,
           let plan = plans[pageNumber] {
            if let marginOverride = plan.marginOverride {
                return marginOverride
            }
            if plan.strategy == .fullPageImage {
                return PageMargins(top: 0, right: 0, bottom: 0, left: 0)
            }
        }
        return resolvedPageSetup.margins
    }

    func resolvedColumns(for pageNumber: Int) -> Int {
        if let plans = appliedLayoutPlans,
           let plan = plans[pageNumber],
           let columnsOverride = plan.columnsOverride {
            return columnsOverride
        }
        return resolvedPageSetup.columns
    }

    func resolvedGutter(for pageNumber: Int) -> Double {
        resolvedPageSetup.gutter
    }

    var resolvedBaselineGrid: Double {
        resolvedPageSetup.baselineGrid
    }

    func resolvedShowHeadersFooters(for pageNumber: Int) -> Bool {
        if let plans = appliedLayoutPlans,
           let plan = plans[pageNumber] {
            if let showOverride = plan.showHeadersFooters {
                return showOverride
            }
            if plan.strategy == .fullPageImage || plan.strategy == .cover || plan.strategy == .titlePage {
                return false
            }
        }
        if pageNumber == 1 {
            return false
        }
        return true
    }
}

public struct QualityHistoryEntry: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var pageCount: Int
    public var totalFrames: Int
    public var averageFramesPerPage: Double
    public var planAppliedPages: Int
    public var autoLaidOutPages: Int
    public var lowResolutionAssets: Int
    public var missingCaptionAssets: Int
    public var blockingErrors: Int
    public var layoutIssues: Int

    public init(
        timestamp: Date = Date(),
        pageCount: Int,
        totalFrames: Int,
        averageFramesPerPage: Double,
        planAppliedPages: Int,
        autoLaidOutPages: Int,
        lowResolutionAssets: Int,
        missingCaptionAssets: Int,
        blockingErrors: Int,
        layoutIssues: Int
    ) {
        self.timestamp = timestamp
        self.pageCount = pageCount
        self.totalFrames = totalFrames
        self.averageFramesPerPage = averageFramesPerPage
        self.planAppliedPages = planAppliedPages
        self.autoLaidOutPages = autoLaidOutPages
        self.lowResolutionAssets = lowResolutionAssets
        self.missingCaptionAssets = missingCaptionAssets
        self.blockingErrors = blockingErrors
        self.layoutIssues = layoutIssues
    }
}

public struct BookAnnotation: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var pageNumber: Int
    public var x: Double       // layout coordinate X
    public var y: Double       // layout coordinate Y
    public var text: String

    public init(id: UUID = UUID(), pageNumber: Int, x: Double, y: Double, text: String) {
        self.id = id
        self.pageNumber = pageNumber
        self.x = x
        self.y = y
        self.text = text
    }
}
