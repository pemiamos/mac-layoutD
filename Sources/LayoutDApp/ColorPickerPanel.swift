import SwiftUI
import AppKit
import LayoutDCore

/// InDesign 式「多套系拾色器」：RGB / HSB / CMYK 三套系切换，数值 + 滑块联动，
/// 实时预览，并能存取项目色板库。提交的是 `PrintColor`——CMYK 会以原生形式
/// 一路保持到 IDML 导出，而非压回 RGB。
///
/// 内部同时维护三组通道(rgb 0–255 / cmyk 0–100 / hsb)，任一通道改动即回算
/// 另两组以保持一致；「确定空间」取当前套系：CMYK 套系提交 `.cmyk`，其余提交
/// `.rgb`。CMYK↔RGB 走 `NSColor` 的 deviceCMYK/deviceRGB 转换，与画布/导出预览
/// 的近似口径一致。
struct ColorPickerPanel: View {
    enum Mode: String, CaseIterable, Identifiable {
        case rgb = "RGB"
        case hsb = "HSB"
        case cmyk = "CMYK"
        var id: String { rawValue }
    }

    let title: String
    let swatches: [PrintSwatch]
    let onChange: (PrintColor) -> Void
    let onAddSwatch: (PrintColor) -> Void
    let onRemoveSwatch: (UUID) -> Void

    @State private var mode: Mode

    // 三组通道
    @State private var r: Double
    @State private var g: Double
    @State private var b: Double
    @State private var c: Double = 0
    @State private var m: Double = 0
    @State private var y: Double = 0
    @State private var k: Double = 0
    @State private var h: Double = 0
    @State private var s: Double = 0
    @State private var br: Double = 0

    init(
        title: String,
        color: PrintColor,
        swatches: [PrintSwatch],
        onChange: @escaping (PrintColor) -> Void,
        onAddSwatch: @escaping (PrintColor) -> Void,
        onRemoveSwatch: @escaping (UUID) -> Void
    ) {
        self.title = title
        self.swatches = swatches
        self.onChange = onChange
        self.onAddSwatch = onAddSwatch
        self.onRemoveSwatch = onRemoveSwatch

        switch color {
        case let .rgb(rr, gg, bb):
            _mode = State(initialValue: .rgb)
            _r = State(initialValue: Double(rr))
            _g = State(initialValue: Double(gg))
            _b = State(initialValue: Double(bb))
        case let .cmyk(cc, mm, yy, kk):
            _mode = State(initialValue: .cmyk)
            let rgb = Self.cmykToRGB(cc, mm, yy, kk)
            _r = State(initialValue: rgb.0)
            _g = State(initialValue: rgb.1)
            _b = State(initialValue: rgb.2)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                previewSwatch
            }

            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: mode) { syncFromRGB(emit: false) }

            channels

            Divider()
            hexRow

            Divider()
            swatchLibrary
        }
        .padding(12)
        .frame(width: 288)
        .onAppear { syncFromRGB(emit: false) }
    }

    // MARK: - Preview

    private var currentRGBColor: Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: 1)
    }

    private var previewSwatch: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(currentRGBColor)
            .frame(width: 56, height: 26)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.4)))
    }

    // MARK: - Channel rows

    @ViewBuilder private var channels: some View {
        switch mode {
        case .rgb:
            channelRow("R", value: $r, range: 0...255, decimals: 0, live: { syncFromRGB(emit: false) })
            channelRow("G", value: $g, range: 0...255, decimals: 0, live: { syncFromRGB(emit: false) })
            channelRow("B", value: $b, range: 0...255, decimals: 0, live: { syncFromRGB(emit: false) })
        case .hsb:
            channelRow("H", value: $h, range: 0...360, decimals: 0, suffix: "°", live: { syncFromHSB(emit: false) })
            channelRow("S", value: $s, range: 0...100, decimals: 0, suffix: "%", live: { syncFromHSB(emit: false) })
            channelRow("B", value: $br, range: 0...100, decimals: 0, suffix: "%", live: { syncFromHSB(emit: false) })
        case .cmyk:
            channelRow("C", value: $c, range: 0...100, decimals: 0, suffix: "%", live: { syncFromCMYK(emit: false) })
            channelRow("M", value: $m, range: 0...100, decimals: 0, suffix: "%", live: { syncFromCMYK(emit: false) })
            channelRow("Y", value: $y, range: 0...100, decimals: 0, suffix: "%", live: { syncFromCMYK(emit: false) })
            channelRow("K", value: $k, range: 0...100, decimals: 0, suffix: "%", live: { syncFromCMYK(emit: false) })
        }
    }

    /// 一路滑块 + 数值框。关键：拖动**过程中**只在本地回算通道与预览(`live`,
    /// 不写文档),只有**拖动结束**(`onEditingChanged == false`)才 `emit()` 一次
    /// 提交到文档。否则每一帧滑动都触发全书重排,把承载本 popover 的按钮子树重建、
    /// 进而顶掉 popover 甚至丢掉画布选择——正是之前「一点滑块就跳掉」的根因。
    private func channelRow(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        decimals: Int,
        suffix: String = "",
        live: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 16, alignment: .leading)
            Slider(value: value, in: range, onEditingChanged: { editing in
                if !editing { emit() }
            })
            .onChange(of: value.wrappedValue) { live() }
            TextField("", value: value, formatter: Self.formatter(decimals: decimals))
                .frame(width: 44)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .onSubmit { live(); emit() }
            Text(suffix).font(.caption2).foregroundColor(.secondary).frame(width: 10, alignment: .leading)
        }
    }

    // MARK: - Hex

    private var hexRow: some View {
        HStack(spacing: 8) {
            Text("#").font(.system(.caption, design: .monospaced)).foregroundColor(.secondary)
            TextField("RRGGBB", text: Binding(
                get: { String(format: "%02X%02X%02X", Int(r.rounded()), Int(g.rounded()), Int(b.rounded())) },
                set: { newValue in
                    if let color = PrintColor(string: newValue), case let .rgb(rr, gg, bb) = color {
                        r = Double(rr); g = Double(gg); b = Double(bb)
                        syncFromRGB()
                    }
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 96)
            Spacer()
            Button {
                onAddSwatch(currentPrintColor)
            } label: {
                Label("加入色板", systemImage: "plus.square.on.square")
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
    }

    // MARK: - Swatch library

    @ViewBuilder private var swatchLibrary: some View {
        if swatches.isEmpty {
            Text("色板库为空——调好颜色后点「加入色板」。")
                .font(.caption2)
                .foregroundColor(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("色板库").font(.caption).foregroundColor(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 6), count: 8), spacing: 6) {
                    ForEach(swatches) { swatch in
                        swatchChip(swatch)
                    }
                }
            }
        }
    }

    private func swatchChip(_ swatch: PrintSwatch) -> some View {
        let rgb = swatch.color?.displayRGB ?? (r: 1, g: 1, b: 1)
        return RoundedRectangle(cornerRadius: 4)
            .fill(Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: 1))
            .frame(width: 26, height: 26)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.35)))
            .help(swatch.name)
            .onTapGesture { apply(swatch) }
            .contextMenu {
                Button("应用") { apply(swatch) }
                Button("删除", role: .destructive) { onRemoveSwatch(swatch.id) }
            }
    }

    private func apply(_ swatch: PrintSwatch) {
        guard let color = swatch.color else { return }
        switch color {
        case let .rgb(rr, gg, bb):
            mode = .rgb
            r = Double(rr); g = Double(gg); b = Double(bb)
            syncFromRGB()
        case let .cmyk(cc, mm, yy, kk):
            mode = .cmyk
            c = cc; m = mm; y = yy; k = kk
            syncFromCMYK()
        }
    }

    // MARK: - Commit

    private var currentPrintColor: PrintColor {
        if mode == .cmyk {
            return .cmyk(c: c.rounded(), m: m.rounded(), y: y.rounded(), k: k.rounded())
        }
        return .rgb(r: Int(r.rounded()), g: Int(g.rounded()), b: Int(b.rounded()))
    }

    private func emit() { onChange(currentPrintColor) }

    // MARK: - Channel sync
    //
    // 每次编辑只改「自己」那组通道，回算其余两组以保持预览与切换一致。

    // `emit` defaults to true for user edits. Mode-switch / onAppear pass
    // `emit: false` — switching tabs must only re-derive the displayed channels,
    // never mutate the document during a view update (that dismisses the popover).

    private func syncFromRGB(emit shouldEmit: Bool = true) {
        clampRGB()
        let cmyk = Self.rgbToCMYK(r, g, b)
        c = cmyk.0; m = cmyk.1; y = cmyk.2; k = cmyk.3
        let hsb = Self.rgbToHSB(r, g, b)
        h = hsb.0; s = hsb.1; br = hsb.2
        if shouldEmit { emit() }
    }

    private func syncFromCMYK(emit shouldEmit: Bool = true) {
        clampCMYK()
        let rgb = Self.cmykToRGB(c, m, y, k)
        r = rgb.0; g = rgb.1; b = rgb.2
        let hsb = Self.rgbToHSB(r, g, b)
        h = hsb.0; s = hsb.1; br = hsb.2
        if shouldEmit { emit() }
    }

    private func syncFromHSB(emit shouldEmit: Bool = true) {
        h = h.clamped(to: 0...360); s = s.clamped(to: 0...100); br = br.clamped(to: 0...100)
        let rgb = Self.hsbToRGB(h, s, br)
        r = rgb.0; g = rgb.1; b = rgb.2
        let cmyk = Self.rgbToCMYK(r, g, b)
        c = cmyk.0; m = cmyk.1; y = cmyk.2; k = cmyk.3
        if shouldEmit { emit() }
    }

    private func clampRGB() {
        r = r.clamped(to: 0...255); g = g.clamped(to: 0...255); b = b.clamped(to: 0...255)
    }
    private func clampCMYK() {
        c = c.clamped(to: 0...100); m = m.clamped(to: 0...100); y = y.clamped(to: 0...100); k = k.clamped(to: 0...100)
    }

    // MARK: - Conversions (NSColor-backed, matching render/export approximation)

    static func rgbToCMYK(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double, Double) {
        let color = NSColor(deviceRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
        guard let cmyk = color.usingColorSpace(.deviceCMYK) else { return (0, 0, 0, 0) }
        return (Double(cmyk.cyanComponent) * 100, Double(cmyk.magentaComponent) * 100,
                Double(cmyk.yellowComponent) * 100, Double(cmyk.blackComponent) * 100)
    }

    static func cmykToRGB(_ c: Double, _ m: Double, _ y: Double, _ k: Double) -> (Double, Double, Double) {
        let color = NSColor(deviceCyan: c / 100, magenta: m / 100, yellow: y / 100, black: k / 100, alpha: 1)
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return (0, 0, 0) }
        return (Double(rgb.redComponent) * 255, Double(rgb.greenComponent) * 255, Double(rgb.blueComponent) * 255)
    }

    static func rgbToHSB(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let color = NSColor(deviceRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
        guard let hsb = color.usingColorSpace(.deviceRGB) else { return (0, 0, 0) }
        return (Double(hsb.hueComponent) * 360, Double(hsb.saturationComponent) * 100, Double(hsb.brightnessComponent) * 100)
    }

    static func hsbToRGB(_ h: Double, _ s: Double, _ br: Double) -> (Double, Double, Double) {
        let color = NSColor(deviceHue: h / 360, saturation: s / 100, brightness: br / 100, alpha: 1)
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return (0, 0, 0) }
        return (Double(rgb.redComponent) * 255, Double(rgb.greenComponent) * 255, Double(rgb.blueComponent) * 255)
    }

    private static func formatter(decimals: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = decimals
        f.usesGroupingSeparator = false
        return f
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
