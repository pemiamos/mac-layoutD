import Foundation

public struct LaidOutDocument: Codable, Equatable, Sendable {
    public var projectId: UUID
    public var pages: [LaidOutPage]
    public var issues: [LayoutIssue]

    public init(projectId: UUID, pages: [LaidOutPage], issues: [LayoutIssue] = []) {
        self.projectId = projectId
        self.pages = pages
        self.issues = issues
    }
}

public struct LaidOutPage: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var number: Int
    public var frames: [PageFrame]

    public init(id: UUID = UUID(), number: Int, frames: [PageFrame] = []) {
        self.id = id
        self.number = number
        self.frames = frames
    }
}

public struct PageFrame: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: PageFrameKind
    public var rect: Rect
    public var styleId: String?
    public var content: FrameContent

    public init(
        id: UUID = UUID(),
        kind: PageFrameKind,
        rect: Rect,
        styleId: String? = nil,
        content: FrameContent
    ) {
        self.id = id
        self.kind = kind
        self.rect = rect
        self.styleId = styleId
        self.content = content
    }
}

public enum PageFrameKind: String, Codable, Sendable {
    case text
    case image
    case caption
    case callout
    case table
}

public enum FrameContent: Codable, Equatable, Sendable {
    case text(String)
    case asset(UUID)
    case empty
}

public struct LayoutIssue: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var severity: IssueSeverity
    public var message: String
    public var category: PreflightIssueCategory?
    public var suggestedFix: String?
    public var autoFixKind: PreflightAutoFixKind?
    public var pageNumber: Int?
    public var frameId: UUID?

    public init(
        id: UUID = UUID(),
        severity: IssueSeverity,
        message: String,
        category: PreflightIssueCategory? = nil,
        suggestedFix: String? = nil,
        autoFixKind: PreflightAutoFixKind? = nil,
        pageNumber: Int? = nil,
        frameId: UUID? = nil
    ) {
        self.id = id
        self.severity = severity
        self.message = message
        self.category = category
        self.suggestedFix = suggestedFix
        self.autoFixKind = autoFixKind
        self.pageNumber = pageNumber
        self.frameId = frameId
    }
}

public enum IssueSeverity: String, Codable, Sendable {
    case info
    case warning
    case error
}

public enum PreflightIssueCategory: String, Codable, CaseIterable, Sendable {
    case metadata
    case structure
    case references
    case assets
    case pagination
    case layout
    case typography
    case tableOfContents
}

public enum PreflightAutoFixKind: String, Codable, CaseIterable, Sendable {
    case fillMissingPublisher
    case fillMissingKeywords
    case removeInvalidISBN
    case fillMissingAssetCaptions
    case fillMissingAssetCredits
    case clearMissingAssetSourcePaths
}
