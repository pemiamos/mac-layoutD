import CoreText
import Foundation
import LayoutDCore

extension IDMLExporter {
    // MARK: - 页面项

    func colorRef(_ raw: String?) -> String {
        guard let raw else { return "Swatch/None" }
        guard let color = PrintColor(string: raw) else { return "Color/Black" }
        return color.idmlSwatchSelf
    }

    func textFrameItem(self id: String, story: String, rect: Rect,
                               fillColor: String?, strokeColor: String?, strokeWidth: Double,
                               pageW: Double, pageH: Double, dx: Double = 0,
                               previous: String = "n", next: String = "n") -> String {
        """
        \t\t<TextFrame Self="\(id)" ParentStory="\(story)" PreviousTextFrame="\(previous)" NextTextFrame="\(next)" ContentType="TextType" FillColor="\(colorRef(fillColor))" StrokeColor="\(colorRef(strokeColor))" StrokeWeight="\(fmt(max(strokeWidth, 0)))" ItemTransform="1 0 0 1 0 0">
        \t\t\t\(rectGeometry(rect, pageW: pageW, pageH: pageH, dx: dx))
        \t\t\t<TextFramePreference TextColumnCount="1" TextColumnGutter="12" VerticalJustification="TopAlign"/>
        \t\t</TextFrame>
        """
    }

    func colorRectangleItem(self id: String, rect: Rect, fillColor: String,
                                    strokeColor: String? = nil, strokeWidth: Double = 0,
                                    pageW: Double, pageH: Double, dx: Double = 0) -> String {
        let strokeRef = strokeColor.map { colorRef($0) } ?? "Swatch/None"
        let weight = strokeColor != nil ? max(strokeWidth, 0) : 0
        return """
        \t\t<Rectangle Self="\(id)" ContentType="Unassigned" FillColor="\(colorRef(fillColor))" StrokeColor="\(strokeRef)" StrokeWeight="\(fmt(weight))" ItemTransform="1 0 0 1 0 0">
        \t\t\t\(rectGeometry(rect, pageW: pageW, pageH: pageH, dx: dx))
        \t\t</Rectangle>
        """
    }

    /// A drawn line → a real InDesign `GraphicLine` (open path, two anchor points)
    /// carrying an actual `StrokeWeight`/`StrokeColor`. Emitting it as a thin filled
    /// rectangle (the earlier approach) made InDesign report the stroke as 0pt and
    /// left it uneditable as a line. Lines are axis-aligned: horizontal along the
    /// vertical centre when wider than tall, else vertical.
    func graphicLineItem(self id: String, rect: Rect, strokeColor: String, strokeWidth: Double,
                                 pageW: Double, pageH: Double, dx: Double = 0) -> String {
        let horizontal = rect.width >= rect.height
        let (ax1, ay1, ax2, ay2): (Double, Double, Double, Double) = horizontal
            ? (rect.x, rect.y + rect.height / 2, rect.x + rect.width, rect.y + rect.height / 2)
            : (rect.x + rect.width / 2, rect.y, rect.x + rect.width / 2, rect.y + rect.height)
        func pt(_ x: Double, _ y: Double) -> String {
            let a = "\(fmt(x - pageW / 2 + dx)) \(fmt(y - pageH / 2))"
            return "<PathPointType Anchor=\"\(a)\" LeftDirection=\"\(a)\" RightDirection=\"\(a)\"/>"
        }
        return """
        \t\t<GraphicLine Self="\(id)" ContentType="Unassigned" FillColor="Swatch/None" StrokeColor="\(colorRef(strokeColor))" StrokeWeight="\(fmt(max(strokeWidth, 0)))" ItemTransform="1 0 0 1 0 0">
        \t\t\t<Properties><PathGeometry><GeometryPathType PathOpen="true"><PathPointArray>\(pt(ax1, ay1))\(pt(ax2, ay2))</PathPointArray></GeometryPathType></PathGeometry></Properties>
        \t\t</GraphicLine>
        """
    }

    /// A drawn shape frame (empty text frame carrying only a fill and/or stroke).
    /// Emitted as an unassigned Rectangle so hand-drawn color boxes survive export
    /// instead of being dropped for having no text.
    func drawnBoxItem(self id: String, rect: Rect, fillColor: String?, strokeColor: String?,
                              strokeWidth: Double, pageW: Double, pageH: Double, dx: Double = 0) -> String {
        """
        \t\t<Rectangle Self="\(id)" ContentType="Unassigned" FillColor="\(colorRef(fillColor))" StrokeColor="\(colorRef(strokeColor))" StrokeWeight="\(fmt(max(strokeWidth, 0)))" ItemTransform="1 0 0 1 0 0">
        \t\t\t\(rectGeometry(rect, pageW: pageW, pageH: pageH, dx: dx))
        \t\t</Rectangle>
        """
    }

    func imageItem(self id: String, imageSelf: String, linkSelf: String, asset: Asset, packagedFileName: String?, rect: Rect, maskShape: ImageMaskShape? = nil, pageW: Double, pageH: Double, dx: Double = 0, textWrap: Bool = true) -> String {
        let natW = Double(max(asset.pixelWidth, 1))
        let natH = Double(max(asset.pixelHeight, 1))
        let sx = rect.width / natW, sy = rect.height / natH
        let effX = Int((72.0 / max(sx, 0.0001)).rounded()), effY = Int((72.0 / max(sy, 0.0001)).rounded())
        let left = rect.x - pageW / 2 + dx, top = rect.y - pageH / 2
        let uri = packagedFileName.map { "file:Links/\($0)" } ?? "file:missing-\(asset.fileName)"
        // 垫底图（wrapMode=underlay）不带绕排：文字直接压在图上走，图由调用方置于最底层。
        let wrapXML = textWrap ? textWrapPreference() : "<TextWrapPreference Inverse=\"false\" ApplyToMasterPageOnly=\"false\" TextWrapSide=\"BothSides\" TextWrapMode=\"None\"/>"
        return """
        \t\t<Rectangle Self="\(id)" ContentType="GraphicType" StoryTitle="$ID/" ItemTransform="1 0 0 1 0 0">
        \t\t\t\(maskGeometry(rect, shape: maskShape, pageW: pageW, pageH: pageH, dx: dx))
        \t\t\t\(wrapXML)
        \t\t\t<Image Self="\(imageSelf)" Space="$ID/#Links_RGB" ActualPpi="72 72" EffectivePpi="\(effX) \(effY)" ImageRenderingIntent="UseColorSettings" Visible="true" ItemTransform="\(fmt(sx)) 0 0 \(fmt(sy)) \(fmt(left)) \(fmt(top))">
        \t\t\t\t<Properties>
        \t\t\t\t\t<Profile type="string">$ID/Embedded</Profile>
        \t\t\t\t\t<GraphicBounds Left="0" Top="0" Right="\(fmt(natW))" Bottom="\(fmt(natH))"/>
        \t\t\t\t</Properties>
        \t\t\t\t<Link Self="\(linkSelf)" LinkResourceURI="\(esc(uri))" LinkResourceFormat="$ID/" StoredState="Normal" LinkClientID="257" LinkResourceModificationState="None" LinkObjectModificationState="None" LinkResourceSize="0~0" CanEmbed="true" CanUnembed="true" CanPackage="true" ImportPolicy="NoAutoImport" ShowInUI="true"/>
        \t\t\t</Image>
        \t\t</Rectangle>
        """
    }

    /// B1-IDML：图片框输出原生绕排设置，让 InDesign 里文字自动避开图片矩形范围
    /// （之前只有 layoutD 自己的画布预览会绕排，导出的 IDML 图片和文字互不相让）。
    /// 结构对照过真实 Adobe 导出的 IDML 样本：TextWrapPreference 是 Rectangle 的直接
    /// 子节点、和 Properties 同级，紧跟其后。矩形绕排（BoundingBoxTextWrap）+ 两侧
    /// 都避让，四边留 6pt 呼吸间距。
    func textWrapPreference(offset: Double = 6) -> String {
        """
        <TextWrapPreference Inverse="false" ApplyToMasterPageOnly="false" TextWrapSide="BothSides" TextWrapMode="BoundingBoxTextWrap">
        \t\t\t\t<Properties><TextWrapOffset Top="\(fmt(offset))" Left="\(fmt(offset))" Bottom="\(fmt(offset))" Right="\(fmt(offset))"/></Properties>
        \t\t\t</TextWrapPreference>
        """
    }

    // （THREAD-1b cut2 的锚定对象机制已于 2026-07-07 FRAME-SPLIT 废除：用户定「所有图片
    //  一律独立定位框」，锚定文字拉伸 bug 也就此绕开。历史实现见 git 记录 9ba5b40。）
}
