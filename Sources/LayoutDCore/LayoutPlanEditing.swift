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

/// What a single selected frame is aligned relative to. Multi-object
/// (align-to-selection) alignment is intentionally out of scope until the editor
/// grows multi-selection — see the「对齐: 页面▾」dropdown in InDesign's panel.
public enum AlignmentReference: String, CaseIterable, Sendable {
    case page
    case margin

    public var displayName: String {
        switch self {
        case .page: return "对齐到页面"
        case .margin: return "对齐到页边距"
        }
    }
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
