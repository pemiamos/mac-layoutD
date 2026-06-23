import AppKit

let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// 透明背景
ctx.clear(CGRect(x: 0, y: 0, width: S, height: S))

// 圆角方(squircle 近似):内缩留浮起感
let inset: CGFloat = 64
let rect = CGRect(x: inset, y: inset, width: S - inset*2, height: S - inset*2)
let radius: CGFloat = (S - inset*2) * 0.235
let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.saveGState()
ctx.addPath(path); ctx.clip()

// 渐变底:靛蓝 → 深蓝紫(专业/排版气质)
let colors = [
    CGColor(red: 0.36, green: 0.42, blue: 0.95, alpha: 1.0),  // #5C6BF2
    CGColor(red: 0.18, green: 0.16, blue: 0.52, alpha: 1.0)   // #2E2985
] as CFArray
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: inset, y: S-inset), end: CGPoint(x: S-inset, y: inset), options: [])

// 右侧竖排参考线(竖排排版的暗示),低透明
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.14))
ctx.setLineWidth(6)
let gx = S - inset - 150
for i in 0..<3 {
    let x = gx + CGFloat(i)*46
    ctx.move(to: CGPoint(x: x, y: inset + 150))
    ctx.addLine(to: CGPoint(x: x, y: S - inset - 150))
}
ctx.strokePath()
ctx.restoreGState()

// 中央「版」字:白色粗体
let para = NSMutableParagraphStyle(); para.alignment = .center
let font = NSFont(name: "PingFang SC Semibold", size: 560) ?? NSFont(name: "Heiti SC Medium", size: 560) ?? NSFont.boldSystemFont(ofSize: 560)
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
    .paragraphStyle: para
]
let s = "版" as NSString
let sz = s.size(withAttributes: attrs)
s.draw(at: NSPoint(x: (S - sz.width)/2 - 40, y: (S - sz.height)/2 + 6), withAttributes: attrs)

img.unlockFocus()

// 存 PNG
let tiff = img.tiffRepresentation!
let rep = NSBitmapImageRep(data: tiff)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: "/tmp/layoutd-icon.png"))
print("icon written: /tmp/layoutd-icon.png")
