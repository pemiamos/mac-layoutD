import SwiftUI
import AppKit
import LayoutDCore

/// A single color property row (填充/描边/文字): a label, a clickable swatch that
/// expands an inline InDesign-style picker in place, and a clear button.
///
/// Replaces the old pairing of a native SwiftUI `ColorPicker` (which pops the
/// system's own color panel window on click) plus a separate "多套系" button that
/// opened a floating picker window. Both are gone — there is exactly one control
/// per color, and clicking it expands the full RGB/HSB/CMYK picker right there in
/// the properties panel, never leaving the app's own window.
struct InlineColorPickerView: View {
    let label: String
    let color: PrintColor
    let clearLabel: String
    let swatches: [PrintSwatch]
    let onChange: (PrintColor) -> Void
    let onClear: () -> Void
    let onAddSwatch: (PrintColor) -> Void
    let onRemoveSwatch: (UUID) -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.caption)
                    .frame(width: 32, alignment: .leading)

                Button {
                    withAnimation(.easeInOut(duration: 0.12)) { isExpanded.toggle() }
                } label: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(previewColor)
                        .frame(width: 32, height: 20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.primary.opacity(0.35), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)

                Spacer()

                Button(clearLabel) { onClear() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }

            if isExpanded {
                ColorFieldPanel(
                    initial: color,
                    swatches: swatches,
                    onChange: onChange,
                    onAddSwatch: onAddSwatch,
                    onRemoveSwatch: onRemoveSwatch
                )
                .padding(.leading, 32)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var previewColor: Color {
        let rgb = color.displayRGB
        return Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: 1)
    }
}

/// The expanded picker: 2D saturation×brightness field + hue strip on top, an
/// RGB/HSB/CMYK segmented control with sliders below, then hex entry and the
/// project's swatch library. Emits a `PrintColor` — CMYK stays CMYK all the way
/// to IDML export, never flattened to RGB.
private struct ColorFieldPanel: View {
    enum Mode: String, CaseIterable, Identifiable {
        case rgb = "RGB"
        case hsb = "HSB"
        case cmyk = "CMYK"
        var id: String { rawValue }
    }

    let swatches: [PrintSwatch]
    let onChange: (PrintColor) -> Void
    let onAddSwatch: (PrintColor) -> Void
    let onRemoveSwatch: (UUID) -> Void

    @State private var mode: Mode

    // 三组通道，任一通道改动即回算其余两组以保持一致。
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
        initial: PrintColor,
        swatches: [PrintSwatch],
        onChange: @escaping (PrintColor) -> Void,
        onAddSwatch: @escaping (PrintColor) -> Void,
        onRemoveSwatch: @escaping (UUID) -> Void
    ) {
        self.swatches = swatches
        self.onChange = onChange
        self.onAddSwatch = onAddSwatch
        self.onRemoveSwatch = onRemoveSwatch

        switch initial {
        case let .rgb(rr, gg, bb):
            _mode = State(initialValue: .rgb)
            _r = State(initialValue: Double(rr))
            _g = State(initialValue: Double(gg))
            _b = State(initialValue: Double(bb))
        case let .cmyk(cc, mm, yy, kk):
            _mode = State(initialValue: .cmyk)
            // Preserve the EXACT CMYK passed in — deriving RGB/HSB from it for the
            // other tabs is fine, but re-deriving C/M/Y/K from RGB on open would
            // silently drift the numbers the user set (the bug this replaced).
            _c = State(initialValue: cc)
            _m = State(initialValue: mm)
            _y = State(initialValue: yy)
            _k = State(initialValue: kk)
            let rgb = Self.cmykToRGB(cc, mm, yy, kk)
            _r = State(initialValue: rgb.0)
            _g = State(initialValue: rgb.1)
            _b = State(initialValue: rgb.2)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                HueSaturationBrightnessField(
                    hue: h, saturation: s, brightness: br,
                    onLiveChange: { newS, newBr in
                        s = newS; br = newBr
                        syncFromHSB(emit: false)
                    },
                    onCommit: { syncFromHSB(emit: true) }
                )
                .frame(width: 150, height: 150)

                HueStrip(
                    hue: h,
                    onLiveChange: { newH in
                        h = newH
                        syncFromHSB(emit: false)
                    },
                    onCommit: { syncFromHSB(emit: true) }
                )
                .frame(width: 18, height: 150)
            }

            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: mode) { syncFromCurrentMode(emit: false) }

            channels

            Divider()
            hexRow

            Divider()
            swatchLibrary
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
        )
        // Sync from whichever channels are authoritative for the initial mode —
        // for a CMYK swatch that derives RGB/HSB from the exact C/M/Y/K, instead
        // of recomputing C/M/Y/K from RGB and drifting them.
        .onAppear { syncFromCurrentMode(emit: false) }
    }

    private func syncFromCurrentMode(emit shouldEmit: Bool = false) {
        switch mode {
        case .rgb: syncFromRGB(emit: shouldEmit)
        case .hsb: syncFromHSB(emit: shouldEmit)
        case .cmyk: syncFromCMYK(emit: shouldEmit)
        }
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

    /// 一路滑块 + 数值框。拖动过程中只本地回算(`live`,不写文档),松手才 `emit()`
    /// 提交一次 —— 避免每帧都触发全书重排。
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
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 6), count: 6), spacing: 6) {
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
            .frame(width: 24, height: 24)
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

/// InDesign-style 2D color field: X = saturation (0 white → 100 full), Y =
/// brightness (100 top → 0 black), tinted by the current hue. Drag or click
/// anywhere to move the crosshair; the standard white→hue / transparent→black
/// gradient overlay is a visual approximation (not colorimetric), same technique
/// used by most color pickers.
private struct HueSaturationBrightnessField: View {
    let hue: Double
    let saturation: Double
    let brightness: Double
    let onLiveChange: (_ saturation: Double, _ brightness: Double) -> Void
    let onCommit: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color(hue: hue / 360, saturation: 1, brightness: 1))
                LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)

                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
                    .background(Circle().strokeBorder(Color.black.opacity(0.4), lineWidth: 1).padding(1))
                    .frame(width: 12, height: 12)
                    .position(
                        x: CGFloat(saturation / 100) * proxy.size.width,
                        y: CGFloat(1 - brightness / 100) * proxy.size.height
                    )
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = min(max(value.location.x, 0), proxy.size.width)
                        let yLoc = min(max(value.location.y, 0), proxy.size.height)
                        let newS = Double(x / proxy.size.width) * 100
                        let newBr = Double(1 - yLoc / proxy.size.height) * 100
                        onLiveChange(newS, newBr)
                    }
                    .onEnded { _ in onCommit() }
            )
        }
    }
}

/// InDesign-style vertical hue strip (0…360° top to bottom). Drag or click to move
/// the indicator.
private struct HueStrip: View {
    let hue: Double
    let onLiveChange: (Double) -> Void
    let onCommit: () -> Void

    private static let stops: [Color] = stride(from: 0.0, through: 360.0, by: 30).map {
        Color(hue: $0 / 360, saturation: 1, brightness: 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                LinearGradient(colors: Self.stops, startPoint: .top, endPoint: .bottom)

                Rectangle()
                    .fill(Color.white)
                    .frame(height: 3)
                    .overlay(Rectangle().stroke(Color.black.opacity(0.4), lineWidth: 1))
                    .offset(y: CGFloat(hue / 360) * proxy.size.height - 1.5)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let yLoc = min(max(value.location.y, 0), proxy.size.height)
                        onLiveChange(Double(yLoc / proxy.size.height) * 360)
                    }
                    .onEnded { _ in onCommit() }
            )
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
