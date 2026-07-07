import CoreText
import Foundation
import LayoutDCore

extension IDMLExporter {
    // MARK: - FRAME-SPLIT 正文串接流辅助类型

    struct FrameKey: Hashable { let page: Int; let frame: Int }
    // `column` 是 frame.rect.x 的四分之一点取整——多栏页面里同一页会有多个不同 x 的栏，
    // 绝不能把它们粗暴并成一个宽框（会产出一个跨两栏的超宽 TextFrame，InDesign 里断行/
    // 对齐全乱）。同页同栏的相邻正文段落才合并成一个 TextFrame。
    // `run` 是断流后的正文流序号（FRAME-SPLIT）：每段连续纯正文一条流。
    struct FlowPageKey: Hashable { let run: Int; let page: Int; let column: Int }
    struct ChainInfo { let selfId: String; let previous: String; let next: String }
    struct ChapterParagraph {
        let styleRef: String
        let text: String
        let inlineRuns: [InlineRun]?
        let footnotes: [Paragraph]
        let footnoteStyleRef: String
    }

    func unionRect(_ a: Rect, _ b: Rect) -> Rect {
        let minX = min(a.x, b.x)
        let minY = min(a.y, b.y)
        let maxX = max(a.x + a.width, b.x + b.width)
        let maxY = max(a.y + a.height, b.y + b.height)
        return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// FRAME-SPLIT（2026-07-07 用户定）：串接文流**只收纯正文**——styleId 必须是 body
    /// （一本书正文统一一个段落样式），kind 限 body/listItem。标题/开节概述/抽言/图注/
    /// 参考文献等角色段落（kind 可能也是 .body 但 styleId 不同）一律独立框、各套各的
    /// 段落样式；表格/脚注/旁注/图片本就独立。文流遇到任何独立框角色即断流。
    func isBodyFlowParagraph(_ paragraph: Paragraph) -> Bool {
        guard paragraph.styleId == StyleID.body.rawValue else { return false }
        switch paragraph.kind {
        case .body, .listItem:
            return true
        default:
            return false
        }
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
