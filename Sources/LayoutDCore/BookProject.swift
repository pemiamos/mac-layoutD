import Foundation

public struct BookProject: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var metadata: ProjectMetadata
    public var pageSetup: PageSetup
    public var styles: StyleLibrary
    public var sections: [BookSection]
    public var assets: [Asset]
    public var appliedLayoutPlans: [Int: LayoutPlan]?
    public var savedLayoutTemplates: [SavedLayoutTemplate]?
    public var lockedPages: Set<Int>?

    public init(
        id: UUID = UUID(),
        metadata: ProjectMetadata,
        pageSetup: PageSetup = .scienceBookDefault,
        styles: StyleLibrary = .defaultChineseScience,
        sections: [BookSection] = [],
        assets: [Asset] = [],
        appliedLayoutPlans: [Int: LayoutPlan]? = nil,
        savedLayoutTemplates: [SavedLayoutTemplate]? = nil,
        lockedPages: Set<Int>? = nil
    ) {
        self.id = id
        self.metadata = metadata
        self.pageSetup = pageSetup
        self.styles = styles
        self.sections = sections
        self.assets = assets
        self.appliedLayoutPlans = appliedLayoutPlans
        self.savedLayoutTemplates = savedLayoutTemplates
        self.lockedPages = lockedPages
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

    public init(
        id: UUID = UUID(),
        kind: ParagraphKind,
        text: String,
        styleId: String,
        anchoredAssetIds: [UUID] = []
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.styleId = styleId
        self.anchoredAssetIds = anchoredAssetIds
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
}
