import CoreText
import Foundation
import LayoutDCore

extension IDMLExporter {
    // MARK: - FRAME-SPLIT 正文串接流辅助类型
    // 分组本身（FrameKey/FlowPageKey/ChainInfo/unionRect/isBodyFlowParagraph）已抽成
    // 跨模块共享函数 groupIntoFlowFrames（见 LayoutDEngine/FlowFrameGrouping.swift，
    // FRAME-CANVAS-0），画布/PDF/PNG 预览复用同一份；此处只留导出专用的辅助类型。

    struct ChapterParagraph {
        let styleRef: String
        let text: String
        let inlineRuns: [InlineRun]?
        let footnotes: [Paragraph]
        let footnoteStyleRef: String
    }

    func xmlSafe(_ s: String) -> String {
        s.replacingOccurrences(of: "/", with: "_")
    }

    func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    func fmt(_ d: Double) -> String { String(format: "%.3f", d) }

    // MARK: - 几何

    /// frame.rect(页内左上原点、y 向下）→ 单页 spread 坐标(原点在页中心）。
    func rectGeometry(_ rect: Rect, pageW: Double, pageH: Double, dx: Double = 0) -> String {
        let left = rect.x - pageW / 2 + dx
        let top = rect.y - pageH / 2
        let right = rect.x + rect.width - pageW / 2 + dx
        let bottom = rect.y + rect.height - pageH / 2
        func p(_ x: Double, _ y: Double) -> String {
            let a = "\(fmt(x)) \(fmt(y))"
            return "<PathPointType Anchor=\"\(a)\" LeftDirection=\"\(a)\" RightDirection=\"\(a)\"/>"
        }
        return """
        <Properties><PathGeometry><GeometryPathType PathOpen="false"><PathPointArray>\
        \(p(left, top))\(p(right, top))\(p(right, bottom))\(p(left, bottom))\
        </PathPointArray></GeometryPathType></PathGeometry></Properties>
        """
    }

    /// 非矩形图框蒙版（E2-5）：把图框路径改成多边形/扇面，图片放满 rect 后被该路径裁切。
    /// `.rect`/nil 回退到矩形。八角=切四角的 8 点；扇面=向上张开的环形扇区（弧线用多段折线近似）。
    func maskGeometry(_ rect: Rect, shape: ImageMaskShape?, pageW: Double, pageH: Double, dx: Double = 0) -> String {
        let left = rect.x - pageW / 2 + dx
        let top = rect.y - pageH / 2
        let right = rect.x + rect.width - pageW / 2 + dx
        let bottom = rect.y + rect.height - pageH / 2
        let w = rect.width, h = rect.height
        var pts: [(Double, Double)] = []
        switch shape {
        case .octagon:
            let c = min(w, h) * 0.30   // 四角各切掉的边长
            pts = [(left + c, top), (right - c, top), (right, top + c), (right, bottom - c),
                   (right - c, bottom), (left + c, bottom), (left, bottom - c), (left, top + c)]
        case .fan:
            let cx = (left + right) / 2
            let half = 35.0 * Double.pi / 180.0           // 扇面半张角
            let ro = w / (2 * sin(half))                  // 外半径：外弧最宽处贴框宽
            let cy = top + ro                             // 圆心在框上方外侧，外弧顶贴框顶
            let ri = max(ro - h, ro * 0.32)               // 内半径：内弧贴框底（过矮则留最小内径）
            let seg = 16
            for i in 0...seg {                            // 外弧 左→右
                let t = -half + 2 * half * Double(i) / Double(seg)
                pts.append((cx + ro * sin(t), cy - ro * cos(t)))
            }
            for i in 0...seg {                            // 内弧 右→左
                let t = half - 2 * half * Double(i) / Double(seg)
                pts.append((cx + ri * sin(t), cy - ri * cos(t)))
            }
        default:
            return rectGeometry(rect, pageW: pageW, pageH: pageH, dx: dx)
        }
        let body = pts.map { x, y -> String in
            let a = "\(fmt(x)) \(fmt(y))"
            return "<PathPointType Anchor=\"\(a)\" LeftDirection=\"\(a)\" RightDirection=\"\(a)\"/>"
        }.joined()
        return "<Properties><PathGeometry><GeometryPathType PathOpen=\"false\"><PathPointArray>\(body)</PathPointArray></GeometryPathType></PathGeometry></Properties>"
    }

}
