import Foundation
import CoreGraphics

public struct LayoutPlan: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var target: LayoutTarget
    public var strategy: LayoutStrategy
    public var blocks: [LayoutPlanBlock]
    public var notes: [String]
    public var marginOverride: PageMargins?
    public var columnsOverride: Int?
    public var showHeadersFooters: Bool?

    public init(
        id: UUID = UUID(),
        target: LayoutTarget,
        strategy: LayoutStrategy,
        blocks: [LayoutPlanBlock],
        notes: [String] = [],
        marginOverride: PageMargins? = nil,
        columnsOverride: Int? = nil,
        showHeadersFooters: Bool? = nil
    ) {
        self.id = id
        self.target = target
        self.strategy = strategy
        self.blocks = blocks
        self.notes = notes
        self.marginOverride = marginOverride
        self.columnsOverride = columnsOverride
        self.showHeadersFooters = showHeadersFooters
    }
}

public extension LayoutPlan {
    func retargeted(to target: LayoutTarget, regenerateBlockIDs: Bool = true) -> LayoutPlan {
        let mappedBlocks: [LayoutPlanBlock]
        if regenerateBlockIDs {
            var idMap: [UUID: UUID] = [:]
            for block in blocks {
                idMap[block.id] = UUID()
            }
            mappedBlocks = blocks.map { block in
                var copy = block
                if let newId = idMap[block.id] {
                    copy.id = newId
                }
                if let next = copy.nextThreadedBlockId, let newNext = idMap[next] {
                    copy.nextThreadedBlockId = newNext
                }
                if let prev = copy.previousThreadedBlockId, let newPrev = idMap[prev] {
                    copy.previousThreadedBlockId = newPrev
                }
                return copy
            }
        } else {
            mappedBlocks = blocks
        }
        return LayoutPlan(
            id: UUID(),
            target: target,
            strategy: strategy,
            blocks: mappedBlocks,
            notes: notes,
            marginOverride: marginOverride,
            columnsOverride: columnsOverride,
            showHeadersFooters: showHeadersFooters
        )
    }
}

public struct SavedLayoutTemplate: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var plan: LayoutPlan
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        plan: LayoutPlan,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.plan = plan
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    public func makePlan(target: LayoutTarget, regenerateBlockIDs: Bool = true) -> LayoutPlan {
        plan.retargeted(to: target, regenerateBlockIDs: regenerateBlockIDs)
    }
}

public enum LayoutTarget: Codable, Equatable, Sendable {
    case page(Int)
    case spread(Int)
    case section(UUID)
}

public enum LayoutStrategy: String, Codable, CaseIterable, Sendable {
    case textLed
    case imageLed
    case balanced
    case comparison
    case knowledgeCard
    case fullPageImage
    case titlePage
    case cover
}

public enum ImageMaskShape: String, Codable, CaseIterable, Sendable {
    case rect
    case fan
    case octagon
}

public struct LayoutPlanBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: LayoutBlockKind
    public var role: String
    public var frame: Rect
    public var contentReference: ContentReference
    public var backgroundColorHex: String?
    public var strokeColorHex: String?
    public var strokeWidth: Double?
    public var textColorHex: String?
    public var nextThreadedBlockId: UUID?
    public var previousThreadedBlockId: UUID?
    public var maskShape: ImageMaskShape?
    /// Paragraph style to render this block with. Captured when a page is frozen
    /// into a plan so manual edits keep the original heading/caption look instead
    /// of collapsing to body style. Optional & additive — old plans decode as nil
    /// and fall back to the kind-derived default.
    public var styleId: String?

    public init(
        id: UUID = UUID(),
        kind: LayoutBlockKind,
        role: String,
        frame: Rect,
        contentReference: ContentReference,
        backgroundColorHex: String? = nil,
        strokeColorHex: String? = nil,
        strokeWidth: Double? = nil,
        textColorHex: String? = nil,
        nextThreadedBlockId: UUID? = nil,
        previousThreadedBlockId: UUID? = nil,
        maskShape: ImageMaskShape? = nil,
        styleId: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.role = role
        self.frame = frame
        self.contentReference = contentReference
        self.backgroundColorHex = backgroundColorHex
        self.strokeColorHex = strokeColorHex
        self.strokeWidth = strokeWidth
        self.textColorHex = textColorHex
        self.nextThreadedBlockId = nextThreadedBlockId
        self.previousThreadedBlockId = previousThreadedBlockId
        self.maskShape = maskShape
        self.styleId = styleId
    }
}

public enum LayoutBlockKind: String, Codable, Sendable {
    case text
    case image
    case caption
    case component
}

public enum ContentReference: Codable, Equatable, Sendable {
    case paragraph(UUID)
    case asset(UUID)
    case storyRange(storyId: UUID, startParagraphId: UUID, endParagraphId: UUID)
    case generated(String)
}

/// Layout fine-tuning tools. layoutD intentionally does NOT provide free-form
/// vector authoring (pen/pencil/shape/gradient drawing): every manual action
/// operates on the structured model so it can be captured as a LayoutPlan /
/// frame override and re-rendered deterministically. `type` selects an existing
/// text frame for editing rather than drawing a new free text box.
public enum LayoutTool: String, CaseIterable, Sendable {
    case selection
    case directSelection
    case type
    /// Draw a new text frame by dragging a rectangle. Unlike `type` (which selects
    /// an existing structured text frame for editing), this authors a fresh `.text`
    /// LayoutPlan block on the page — still structured, still undoable, no free
    /// vector drawing.
    case textFrame
    /// Draw a new image frame by dragging a rectangle → a `.image` LayoutPlan block
    /// referencing a project asset (re-pickable in the inspector).
    case imageFrame
    case page
    case gap
    case hand
    case zoom
    case annotation

    public var displayName: String {
        switch self {
        case .selection: return "选择工具"
        case .directSelection: return "直接选择工具"
        case .type: return "文字工具"
        case .textFrame: return "文本框工具"
        case .imageFrame: return "图像框工具"
        case .page: return "页面工具"
        case .gap: return "间隔工具"
        case .hand: return "手形工具"
        case .zoom: return "缩放工具"
        case .annotation: return "批注工具"
        }
    }

    public var iconName: String {
        switch self {
        case .selection: return "arrow.up.left.pointer.fill"
        case .directSelection: return "cursorarrow"
        case .type: return "textformat"
        case .textFrame: return "character.textbox"
        case .imageFrame: return "photo.badge.plus"
        case .page: return "doc.plaintext"
        case .gap: return "arrow.left.and.right.pattern.ratio"
        case .hand: return "hand.raised.fill"
        case .zoom: return "magnifyingglass"
        case .annotation: return "bubble.left.fill"
        }
    }

    /// Single-key toolbox shortcut, aligned with InDesign muscle memory. `page`
    /// uses Shift+P (a modifier combo, handled separately). `textFrame` has no
    /// InDesign single-key equivalent and is reached from the toolbox.
    public var shortcutKey: Character? {
        switch self {
        case .selection: return "v"
        case .directSelection: return "a"
        case .type: return "t"
        case .imageFrame: return "f"
        case .gap: return "u"
        case .hand: return "h"
        case .zoom: return "z"
        case .textFrame, .page, .annotation: return nil
        }
    }
}

public enum FormattingTarget: String, CaseIterable, Sendable {
    case container
    case text
    
    public var displayName: String {
        switch self {
        case .container: return "格式化影响容器"
        case .text: return "格式化影响文本"
        }
    }
}

public enum ScreenMode: String, CaseIterable, Sendable {
    case normal
    case preview
    
    public var displayName: String {
        switch self {
        case .normal: return "正常模式"
        case .preview: return "预览模式"
        }
    }
}

extension ImageMaskShape {
    public func polygonPoints(in rect: CGRect) -> [CGPoint] {
        switch self {
        case .rect:
            return [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.maxY)
            ]
        case .octagon:
            let delta = min(rect.width, rect.height) * 0.15
            return [
                CGPoint(x: rect.minX + delta, y: rect.minY),
                CGPoint(x: rect.maxX - delta, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY + delta),
                CGPoint(x: rect.maxX, y: rect.maxY - delta),
                CGPoint(x: rect.maxX - delta, y: rect.maxY),
                CGPoint(x: rect.minX + delta, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.maxY - delta),
                CGPoint(x: rect.minX, y: rect.minY + delta)
            ]
        case .fan:
            let cx = rect.minX + rect.width / 2.0
            let cy = rect.minY + rect.height * 2.5
            let R = rect.height * 2.5
            let r = rect.height * 1.5
            let theta = asin(rect.width / (2.0 * R))
            let startAngle = 1.5 * .pi - theta
            let endAngle = 1.5 * .pi + theta
            
            var points: [CGPoint] = []
            let segments = 16
            
            for i in 0...segments {
                let angle = startAngle + (endAngle - startAngle) * Double(i) / Double(segments)
                points.append(CGPoint(x: cx + R * cos(angle), y: cy + R * sin(angle)))
            }
            
            for i in stride(from: segments, through: 0, by: -1) {
                let angle = startAngle + (endAngle - startAngle) * Double(i) / Double(segments)
                points.append(CGPoint(x: cx + r * cos(angle), y: cy + r * sin(angle)))
            }
            
            return points
        }
    }
}

