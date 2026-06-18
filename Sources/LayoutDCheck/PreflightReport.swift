import Foundation
import LayoutDCore

public struct PreflightReport: Codable, Equatable, Sendable {
    public var projectTitle: String
    public var generatedAt: Date
    public var exportReady: Bool
    public var issues: [LayoutIssue]
    public var severityCounts: [String: Int]
    public var categoryCounts: [String: Int]
    public var assetSummary: AssetPreflightSummary
    public var layoutSummary: LayoutPreflightSummary?
    public var issueLocations: [IssueLocation]
    public var pageCount: Int?
    public var qualityMetrics: QualityMetrics

    public init(
        project: BookProject,
        issues: [LayoutIssue],
        document: LaidOutDocument? = nil,
        generatedAt: Date = Date()
    ) {
        self.projectTitle = project.metadata.title
        self.generatedAt = generatedAt
        self.issues = issues
        let severityCounts = Dictionary(grouping: issues, by: { $0.severity.rawValue }).mapValues(\.count)
        self.severityCounts = severityCounts
        let categoryCounts = Dictionary(grouping: issues.compactMap(\.category), by: { $0.rawValue }).mapValues(\.count)
        self.categoryCounts = categoryCounts
        self.exportReady = severityCounts[IssueSeverity.error.rawValue, default: 0] == 0
        let assetSummary = AssetPreflightSummary(project: project)
        self.assetSummary = assetSummary
        let layoutSummary = document.map(LayoutPreflightSummary.init(document:))
        self.layoutSummary = layoutSummary
        self.issueLocations = document.map { IssueLocation.locations(for: issues, document: $0) } ?? []
        self.pageCount = document?.pages.count
        self.qualityMetrics = QualityMetrics(
            project: project,
            document: document,
            assetSummary: assetSummary,
            layoutSummary: layoutSummary,
            severityCounts: severityCounts,
            categoryCounts: categoryCounts
        )
    }

    public var isExportReady: Bool {
        exportReady
    }

    public var summaryLines: [String] {
        var lines = [
            isExportReady ? "Export ready" : "Export blocked",
            "Errors: \(severityCounts[IssueSeverity.error.rawValue, default: 0])",
            "Warnings: \(severityCounts[IssueSeverity.warning.rawValue, default: 0])",
            "Info: \(severityCounts[IssueSeverity.info.rawValue, default: 0])",
            "Assets: \(assetSummary.total)"
        ]

        if let pageCount {
            lines.append("Pages: \(pageCount)")
        }

        if let layoutSummary {
            lines.append("Frames: \(layoutSummary.totalFrames)")
            lines.append("Images: \(layoutSummary.imageFrames)")
            lines.append("Callouts: \(layoutSummary.calloutFrames)")
            lines.append("Tables: \(layoutSummary.tableFrames)")
        }

        if !issueLocations.isEmpty {
            lines.append("Located issues: \(issueLocations.count)")
        }

        if !categoryCounts.isEmpty {
            lines.append("Issue categories: \(categoryCounts.count)")
        }

        lines.append("Plan-applied pages: \(qualityMetrics.planAppliedPages)")
        lines.append("Auto laid-out pages: \(qualityMetrics.autoLaidOutPages)")
        lines.append("Low-DPI assets: \(qualityMetrics.lowResolutionAssets)")
        lines.append("Missing-caption assets: \(qualityMetrics.missingCaptionAssets)")
        lines.append("Layout issues: \(qualityMetrics.layoutIssues)")

        return lines
    }
}

/// Measurable signals aligned with the PRD success indicators (low-DPI and
/// missing-caption detection, share of pages produced without manual layout,
/// AI/template plan adoption, export stability). These are derived from the same
/// project + document the report already inspects, so the indicators can be
/// tracked over time instead of staying aspirational.
public struct QualityMetrics: Codable, Equatable, Sendable {
    public var pageCount: Int
    public var totalFrames: Int
    public var averageFramesPerPage: Double
    /// Pages whose layout came from an applied AI/template `LayoutPlan` — a proxy
    /// for AI candidate adoption.
    public var planAppliedPages: Int
    /// Pages produced purely by the deterministic flow (no applied plan) — a proxy
    /// for the share of pages that needed no manual layout.
    public var autoLaidOutPages: Int
    public var lowResolutionAssets: Int
    public var missingCaptionAssets: Int
    public var blockingErrors: Int
    public var layoutIssues: Int

    public init(
        project: BookProject,
        document: LaidOutDocument?,
        assetSummary: AssetPreflightSummary,
        layoutSummary: LayoutPreflightSummary?,
        severityCounts: [String: Int],
        categoryCounts: [String: Int]
    ) {
        let pages = document?.pages.count ?? 0
        pageCount = pages
        totalFrames = layoutSummary?.totalFrames ?? 0
        averageFramesPerPage = pages > 0 ? Double(totalFrames) / Double(pages) : 0
        let appliedPlanPageCount = project.appliedLayoutPlans?.count ?? 0
        planAppliedPages = min(appliedPlanPageCount, pages)
        autoLaidOutPages = max(pages - planAppliedPages, 0)
        lowResolutionAssets = assetSummary.lowResolution
        missingCaptionAssets = assetSummary.missingCaptions
        blockingErrors = severityCounts[IssueSeverity.error.rawValue, default: 0]
        layoutIssues = categoryCounts[PreflightIssueCategory.layout.rawValue, default: 0]
    }
}

public struct IssueLocation: Codable, Equatable, Sendable {
    public var issueId: UUID
    public var pageNumber: Int
    public var frameId: UUID
    public var frameKind: String
    public var rect: Rect
    public var contentSummary: String?

    public init(
        issueId: UUID,
        pageNumber: Int,
        frameId: UUID,
        frameKind: String,
        rect: Rect,
        contentSummary: String? = nil
    ) {
        self.issueId = issueId
        self.pageNumber = pageNumber
        self.frameId = frameId
        self.frameKind = frameKind
        self.rect = rect
        self.contentSummary = contentSummary
    }

    static func locations(for issues: [LayoutIssue], document: LaidOutDocument) -> [IssueLocation] {
        let framesById = Dictionary(uniqueKeysWithValues: document.pages.flatMap { page in
            page.frames.map { frame in
                (frame.id, (page.number, frame))
            }
        })

        return issues.compactMap { issue in
            guard let frameId = issue.frameId,
                  let (pageNumber, frame) = framesById[frameId] else {
                return nil
            }

            return IssueLocation(
                issueId: issue.id,
                pageNumber: issue.pageNumber ?? pageNumber,
                frameId: frame.id,
                frameKind: frame.kind.rawValue,
                rect: frame.rect,
                contentSummary: contentSummary(for: frame.content)
            )
        }
    }

    private static func contentSummary(for content: FrameContent) -> String? {
        switch content {
        case .text(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }
            return String(trimmed.prefix(40))
        case .asset(let assetId), .spreadAsset(let assetId, _):
            return "asset:\(assetId.uuidString)"
        case .empty:
            return nil
        }
    }
}

public struct LayoutPreflightSummary: Codable, Equatable, Sendable {
    public var totalFrames: Int
    public var textFrames: Int
    public var imageFrames: Int
    public var captionFrames: Int
    public var calloutFrames: Int
    public var tableFrames: Int
    public var emptyFrames: Int

    public init(document: LaidOutDocument) {
        let frames = document.pages.flatMap(\.frames)
        totalFrames = frames.count
        textFrames = frames.filter { $0.kind == .text }.count
        imageFrames = frames.filter { $0.kind == .image }.count
        captionFrames = frames.filter { $0.kind == .caption }.count
        calloutFrames = frames.filter { $0.kind == .callout }.count
        tableFrames = frames.filter { $0.kind == .table }.count
        emptyFrames = frames.filter { $0.content == .empty }.count
    }
}

public struct AssetPreflightSummary: Codable, Equatable, Sendable {
    public var total: Int
    public var missingCaptions: Int
    public var missingCredits: Int
    public var missingSources: Int
    public var lowResolution: Int
    public var unknownSize: Int
    public var repeatedUse: Int

    public init(project: BookProject) {
        let assets = project.assets
        total = assets.count
        missingCaptions = assets.filter { $0.caption?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false }.count
        missingCredits = assets.filter { $0.role != .decorative && $0.credit?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false }.count
        missingSources = assets.filter { asset in
            guard let sourcePath = asset.sourcePath else {
                return false
            }
            return !FileManager.default.fileExists(atPath: sourcePath)
        }.count
        lowResolution = assets.filter { asset in
            guard let effectiveDPI = asset.effectiveDPI(pageSetup: project.resolvedPageSetup) else {
                return false
            }
            return effectiveDPI < 220
        }.count
        unknownSize = assets.filter { $0.pixelWidth <= 0 || $0.pixelHeight <= 0 }.count
        repeatedUse = assets.filter { $0.usage == .repeated }.count
    }
}

extension Asset {
    func effectiveDPI(pageSetup: PageSetup) -> Double? {
        guard pixelWidth > 0 else {
            return dpi
        }

        let pageContentWidth = pageSetup.pageSize.width - pageSetup.margins.left - pageSetup.margins.right
        let totalGutter = Double(max(pageSetup.columns - 1, 0)) * pageSetup.gutter
        let columnWidth = (pageContentWidth - totalGutter) / Double(max(pageSetup.columns, 1))
        let targetWidth = role == .hero ? pageContentWidth : columnWidth
        guard targetWidth > 0 else {
            return dpi
        }

        return Double(pixelWidth) / (targetWidth / 72)
    }
}
