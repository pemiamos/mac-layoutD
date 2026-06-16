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

private func clamp(_ value: Double, _ minimum: Double, _ maximum: Double) -> Double {
    min(max(finite(value), minimum), maximum)
}

private func finite(_ value: Double) -> Double {
    value.isFinite ? value : 0
}
