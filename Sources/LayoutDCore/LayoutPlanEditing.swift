import Foundation

public extension LayoutPlanBlock {
    mutating func updateAbsoluteFrame(
        pageSize: PageSize,
        x: Double? = nil,
        y: Double? = nil,
        width: Double? = nil,
        height: Double? = nil,
        minimumSize: Double = 12
    ) {
        let pageWidth = max(pageSize.width, 1)
        let pageHeight = max(pageSize.height, 1)
        let minWidth = min(max(minimumSize, 1), pageWidth)
        let minHeight = min(max(minimumSize, 1), pageHeight)

        let current = absoluteFrame(pageSize: pageSize)
        let nextWidth = clamp(width ?? current.width, minWidth, pageWidth)
        let nextHeight = clamp(height ?? current.height, minHeight, pageHeight)
        let nextX = clamp(x ?? current.x, 0, pageWidth - nextWidth)
        let nextY = clamp(y ?? current.y, 0, pageHeight - nextHeight)

        frame = Rect(
            x: nextX / pageWidth,
            y: nextY / pageHeight,
            width: nextWidth / pageWidth,
            height: nextHeight / pageHeight
        )
    }

    func absoluteFrame(pageSize: PageSize) -> Rect {
        let pageWidth = max(pageSize.width, 1)
        let pageHeight = max(pageSize.height, 1)
        return Rect(
            x: finite(frame.x) * pageWidth,
            y: finite(frame.y) * pageHeight,
            width: finite(frame.width) * pageWidth,
            height: finite(frame.height) * pageHeight
        )
    }
}

/// Which edge/axis a frame is aligned to. The first three act on the horizontal
/// axis (moving X only), the last three on the vertical axis (moving Y only) —
/// mirroring InDesign's「对齐对象」row. Alignment only moves a frame, never resizes it.
public enum FrameAlignment: String, CaseIterable, Sendable {
    case left
    case horizontalCenter
    case right
    case top
    case verticalCenter
    case bottom

    public var displayName: String {
        switch self {
        case .left: return "左对齐"
        case .horizontalCenter: return "水平居中"
        case .right: return "右对齐"
        case .top: return "顶对齐"
        case .verticalCenter: return "垂直居中"
        case .bottom: return "底对齐"
        }
    }

    /// SF Symbol used for the toolbar button.
    public var iconName: String {
        switch self {
        case .left: return "align.horizontal.left"
        case .horizontalCenter: return "align.horizontal.center"
        case .right: return "align.horizontal.right"
        case .top: return "align.vertical.top"
        case .verticalCenter: return "align.vertical.center"
        case .bottom: return "align.vertical.bottom"
        }
    }
}

/// What frames are aligned relative to — mirrors InDesign's「对齐:」dropdown.
/// `.selection` (align to the bounding box of the current multi-selection) only
/// makes sense with 2+ frames; `.page` / `.margin` work with any count.
public enum AlignmentReference: String, CaseIterable, Sendable {
    case selection
    case page
    case margin

    public var displayName: String {
        switch self {
        case .selection: return "对齐到选区"
        case .page: return "对齐到页面"
        case .margin: return "对齐到页边距"
        }
    }
}

/// InDesign's「分布对象」(equalize a chosen reference point across 3+ frames) plus
/// 「分布间距」(equalize the gaps between them). Distribution keeps the two extreme
/// frames fixed and repositions the ones in between; it needs at least 3 frames.
public enum DistributionMode: String, CaseIterable, Sendable {
    // 分布对象 — vertical axis (moves Y): equalize top edges / vertical centers / bottom edges.
    case topEdges
    case verticalCenters
    case bottomEdges
    // 分布对象 — horizontal axis (moves X): equalize left edges / horizontal centers / right edges.
    case leftEdges
    case horizontalCenters
    case rightEdges
    // 分布间距 — equalize the gaps.
    case verticalSpacing
    case horizontalSpacing

    public var displayName: String {
        switch self {
        case .topEdges: return "按顶分布"
        case .verticalCenters: return "垂直居中分布"
        case .bottomEdges: return "按底分布"
        case .leftEdges: return "按左分布"
        case .horizontalCenters: return "水平居中分布"
        case .rightEdges: return "按右分布"
        case .verticalSpacing: return "垂直等距分布"
        case .horizontalSpacing: return "水平等距分布"
        }
    }

    public var iconName: String {
        switch self {
        case .topEdges: return "distribute.vertical.top"
        case .verticalCenters: return "distribute.vertical.center"
        case .bottomEdges: return "distribute.vertical.bottom"
        case .leftEdges: return "distribute.horizontal.left"
        case .horizontalCenters: return "distribute.horizontal.center"
        case .rightEdges: return "distribute.horizontal.right"
        case .verticalSpacing: return "rectangle.split.1x2"
        case .horizontalSpacing: return "rectangle.split.2x1"
        }
    }

    /// True for the two「分布间距」modes (equalize gaps rather than a reference point).
    public var isSpacing: Bool {
        self == .verticalSpacing || self == .horizontalSpacing
    }
}

/// Smallest rectangle enclosing all given frames (absolute page points). Returns a
/// zero rect for an empty input.
public func boundingBox(of rects: [Rect]) -> Rect {
    guard let first = rects.first else { return Rect(x: 0, y: 0, width: 0, height: 0) }
    var minX = first.x, minY = first.y
    var maxX = first.x + first.width, maxY = first.y + first.height
    for r in rects.dropFirst() {
        minX = min(minX, r.x)
        minY = min(minY, r.y)
        maxX = max(maxX, r.x + r.width)
        maxY = max(maxY, r.y + r.height)
    }
    return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}

/// Pure geometry for「分布对象」/「分布间距」. Given 3+ frames (id + absolute rect),
/// returns each frame's new top-left origin; frames not moved on the relevant axis
/// keep their other coordinate. The two extreme frames stay put. Returns an empty
/// map for fewer than 3 frames. Size is preserved.
public func distributedOrigins(
    frames: [(id: UUID, rect: Rect)],
    mode: DistributionMode
) -> [UUID: (x: Double, y: Double)] {
    guard frames.count >= 3 else { return [:] }
    var result: [UUID: (x: Double, y: Double)] = [:]

    switch mode {
    case .leftEdges, .horizontalCenters, .rightEdges:
        let key: (Rect) -> Double
        switch mode {
        case .horizontalCenters: key = { $0.x + $0.width / 2 }
        case .rightEdges: key = { $0.x + $0.width }
        default: key = { $0.x }
        }
        let sorted = frames.sorted { key($0.rect) < key($1.rect) }
        let firstK = key(sorted.first!.rect)
        let lastK = key(sorted.last!.rect)
        let step = (lastK - firstK) / Double(sorted.count - 1)
        for (i, item) in sorted.enumerated() {
            let targetK = firstK + step * Double(i)
            let newX: Double
            switch mode {
            case .horizontalCenters: newX = targetK - item.rect.width / 2
            case .rightEdges: newX = targetK - item.rect.width
            default: newX = targetK
            }
            result[item.id] = (newX, item.rect.y)
        }

    case .topEdges, .verticalCenters, .bottomEdges:
        let key: (Rect) -> Double
        switch mode {
        case .verticalCenters: key = { $0.y + $0.height / 2 }
        case .bottomEdges: key = { $0.y + $0.height }
        default: key = { $0.y }
        }
        let sorted = frames.sorted { key($0.rect) < key($1.rect) }
        let firstK = key(sorted.first!.rect)
        let lastK = key(sorted.last!.rect)
        let step = (lastK - firstK) / Double(sorted.count - 1)
        for (i, item) in sorted.enumerated() {
            let targetK = firstK + step * Double(i)
            let newY: Double
            switch mode {
            case .verticalCenters: newY = targetK - item.rect.height / 2
            case .bottomEdges: newY = targetK - item.rect.height
            default: newY = targetK
            }
            result[item.id] = (item.rect.x, newY)
        }

    case .horizontalSpacing:
        let sorted = frames.sorted { $0.rect.x < $1.rect.x }
        let span = (sorted.last!.rect.x + sorted.last!.rect.width) - sorted.first!.rect.x
        let totalWidth = sorted.reduce(0) { $0 + $1.rect.width }
        let gap = (span - totalWidth) / Double(sorted.count - 1)
        var cursor = sorted.first!.rect.x
        for item in sorted {
            result[item.id] = (cursor, item.rect.y)
            cursor += item.rect.width + gap
        }

    case .verticalSpacing:
        let sorted = frames.sorted { $0.rect.y < $1.rect.y }
        let span = (sorted.last!.rect.y + sorted.last!.rect.height) - sorted.first!.rect.y
        let totalHeight = sorted.reduce(0) { $0 + $1.rect.height }
        let gap = (span - totalHeight) / Double(sorted.count - 1)
        var cursor = sorted.first!.rect.y
        for item in sorted {
            result[item.id] = (item.rect.x, cursor)
            cursor += item.rect.height + gap
        }
    }

    return result
}

/// Pure geometry for「对齐对象」: given a frame and a reference region (both in
/// absolute page points), returns the frame's new top-left origin so it snaps to
/// the requested edge/center of the region. Size is preserved; only the moved
/// axis changes (the other coordinate is returned unchanged). Kept free of any
/// AppKit/model state so it can be unit-tested directly.
public func alignedFrameOrigin(frame: Rect, region: Rect, alignment: FrameAlignment) -> (x: Double, y: Double) {
    var x = frame.x
    var y = frame.y
    switch alignment {
    case .left:
        x = region.x
    case .horizontalCenter:
        x = region.x + (region.width - frame.width) / 2
    case .right:
        x = region.x + region.width - frame.width
    case .top:
        y = region.y
    case .verticalCenter:
        y = region.y + (region.height - frame.height) / 2
    case .bottom:
        y = region.y + region.height - frame.height
    }
    return (x, y)
}

private func clamp(_ value: Double, _ minimum: Double, _ maximum: Double) -> Double {
    min(max(finite(value), minimum), maximum)
}

private func finite(_ value: Double) -> Double {
    value.isFinite ? value : 0
}
