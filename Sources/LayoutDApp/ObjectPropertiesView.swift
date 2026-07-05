import SwiftUI
import LayoutDCore

/// InDesign 式「属性」面板：随画布选择而变化。
/// - 选中某个容器（文本/图片/图注…）→ 显示该对象的属性（变换/外观/文字/图片）。
/// - 未选中任何对象 → 显示文档属性（开本/方向/对页/分栏/边距 + 当前页）。
///
/// 这样「属性」标签不再一成不变地展示全书信息，而是聚焦于当前操作对象——
/// 对象级编辑从冗长的「检查器」中抽离到这里，检查器回归为项目/预检仪表盘。
struct ObjectPropertiesView: View {
    @ObservedObject var state: AppState
    var onPageClick: (Int) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let ctx = selectedFrameContext {
                    selectionSections(ctx)
                } else {
                    documentSections
                }
            }
            .padding(.all, 14)
        }
    }

    // MARK: - Selection resolution

    private struct FrameContext {
        let frame: PageFrame
        let pageNumber: Int
        let isPageLocked: Bool
    }

    private var selectedFrameContext: FrameContext? {
        guard let selectedId = state.selectedFrameId,
              let pageNum = state.findPageNumber(for: selectedId),
              let doc = state.laidOutDocument,
              let targetPage = doc.pages.first(where: { $0.number == pageNum }),
              let frame = targetPage.frames.first(where: { $0.id == selectedId })
        else { return nil }
        return FrameContext(
            frame: frame,
            pageNumber: pageNum,
            isPageLocked: state.project.safeLockedPages.contains(pageNum)
        )
    }

    // MARK: - Selected-object properties

    @ViewBuilder
    private func selectionSections(_ ctx: FrameContext) -> some View {
        let frame = ctx.frame

        // Header: object type + page
        HStack(spacing: 8) {
            Image(systemName: icon(for: frame.kind))
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(kindLabel(for: frame.kind))
                    .font(.headline)
                Text("第 \(ctx.pageNumber) 页")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }

        if ctx.isPageLocked {
            Text("⚠️ 页面已锁定，元素无法移动或改尺寸。")
                .font(.caption)
                .foregroundColor(.orange)
        }

        Divider()

        // Text content (text / caption frames)
        if (frame.kind == .text || frame.kind == .caption),
           case .text(let editableText) = frame.content {
            sectionLabel("文本")
            ObjectTextEditor(
                frameId: frame.id,
                initialText: editableText,
                isPageLocked: ctx.isPageLocked,
                state: state
            )
            .id(frame.id)
            Divider()
        }

        // Transform
        sectionLabel("变换")
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("X")
                Stepper(String(format: "%.0f pt", frame.rect.x), onIncrement: {
                    state.updateSelectedFrameCoordinate(x: frame.rect.x + 5, y: nil, width: nil, height: nil)
                }, onDecrement: {
                    state.updateSelectedFrameCoordinate(x: frame.rect.x - 5, y: nil, width: nil, height: nil)
                })
            }
            GridRow {
                Text("Y")
                Stepper(String(format: "%.0f pt", frame.rect.y), onIncrement: {
                    state.updateSelectedFrameCoordinate(x: nil, y: frame.rect.y + 5, width: nil, height: nil)
                }, onDecrement: {
                    state.updateSelectedFrameCoordinate(x: nil, y: frame.rect.y - 5, width: nil, height: nil)
                })
            }
            GridRow {
                Text("宽")
                Stepper(String(format: "%.0f pt", frame.rect.width), onIncrement: {
                    state.updateSelectedFrameCoordinate(x: nil, y: nil, width: frame.rect.width + 5, height: nil)
                }, onDecrement: {
                    state.updateSelectedFrameCoordinate(x: nil, y: nil, width: frame.rect.width - 5, height: nil)
                })
            }
            GridRow {
                Text("高")
                Stepper(String(format: "%.0f pt", frame.rect.height), onIncrement: {
                    state.updateSelectedFrameCoordinate(x: nil, y: nil, width: nil, height: frame.rect.height + 5)
                }, onDecrement: {
                    state.updateSelectedFrameCoordinate(x: nil, y: nil, width: nil, height: frame.rect.height - 5)
                })
            }
        }
        .disabled(ctx.isPageLocked)

        Divider()

        // Appearance (fill / stroke, plus text color for text frames)
        sectionLabel("外观")
        VStack(alignment: .leading, spacing: 6) {
            // A line has no fill — only a stroke (its colour + weight). Hide 填充 for it.
            if frame.kind != .line {
                HStack {
                    ColorPicker("填充", selection: Binding(
                        get: { colorFromHex(frame.backgroundColorHex) ?? Color.white },
                        set: { state.setSelectedFrameFillColor($0) }
                    ), supportsOpacity: false)
                    multiSpaceButton(title: "填充",
                        current: printColor(frame.backgroundColorHex, fallback: .rgb(r: 255, g: 255, b: 255)),
                        apply: { state.setSelectedFrameFillColor($0) })
                    Spacer()
                    Button("无填充") { state.clearSelectedFrameFillColor() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }

            HStack {
                ColorPicker("描边", selection: Binding(
                    get: { colorFromHex(frame.strokeColorHex) ?? Color.black },
                    set: { state.setSelectedFrameStrokeColor($0) }
                ), supportsOpacity: false)
                multiSpaceButton(title: "描边",
                    current: printColor(frame.strokeColorHex, fallback: .rgb(r: 0, g: 0, b: 0)),
                    apply: { state.setSelectedFrameStrokeColor($0) })
                Spacer()
                Button("无描边") { state.clearSelectedFrameStrokeColor() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }

            // Stroke weight — InDesign-style preset list (0 / 0.25 / 0.5 / 0.75 / 1 …).
            HStack {
                Text("粗细")
                    .frame(width: 40, alignment: .leading)
                Menu {
                    ForEach(strokeWeightOptions, id: \.self) { w in
                        Button {
                            state.setSelectedFrameStrokeWidth(w)
                        } label: {
                            if abs((frame.strokeWidth ?? 0) - w) < 0.001 {
                                Label(strokeWeightLabel(w), systemImage: "checkmark")
                            } else {
                                Text(strokeWeightLabel(w))
                            }
                        }
                    }
                } label: {
                    Text(strokeWeightLabel(frame.strokeWidth ?? 0))
                }
                .frame(width: 96)
                Stepper("", onIncrement: {
                    state.setSelectedFrameStrokeWidth(nextStrokeWeight(above: frame.strokeWidth ?? 0))
                }, onDecrement: {
                    state.setSelectedFrameStrokeWidth(nextStrokeWeight(below: frame.strokeWidth ?? 0))
                })
                .labelsHidden()
                Spacer()
            }

            if frame.kind == .text || frame.kind == .caption {
                HStack {
                    ColorPicker("文字", selection: Binding(
                        get: { colorFromHex(frame.textColorHex) ?? Color.primary },
                        set: { state.setSelectedFrameTextColor($0) }
                    ), supportsOpacity: false)
                    multiSpaceButton(title: "文字",
                        current: printColor(frame.textColorHex, fallback: .rgb(r: 0, g: 0, b: 0)),
                        apply: { state.setSelectedFrameTextColor($0) })
                    Spacer()
                    Button("默认") { state.clearSelectedFrameTextColor() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
        }
        .disabled(ctx.isPageLocked)

        // Image swap (image frames)
        if frame.kind == .image, case .asset(let currentAssetId) = frame.content {
            Divider()
            sectionLabel("图片")
            Picker("更换图片", selection: Binding(
                get: { currentAssetId },
                set: { state.updateSelectedFrameImage(assetId: $0) }
            )) {
                ForEach(state.project.assets) { asset in
                    Text(asset.fileName).tag(asset.id)
                }
            }
            .disabled(ctx.isPageLocked)
        }

        Divider()

        HStack {
            Spacer()
            Button("恢复流式排版") {
                state.clearCustomLayoutForSelectedFramePage()
            }
            .buttonStyle(.bordered)
            .foregroundColor(.red)
            .disabled(ctx.isPageLocked)
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - Document properties (no selection)

    @ViewBuilder
    private var documentSections: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc")
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("未选择对象")
                    .font(.headline)
                Text(state.project.metadata.title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }

        Text("在画布中选择一个对象，这里会显示它的属性。")
            .font(.caption)
            .foregroundColor(.secondary)

        Divider()

        sectionLabel("文档")
        infoRow(label: "开本", value: state.project.pageSetup.pageSize.label)

        HStack {
            Text("方向").foregroundColor(.secondary).font(.caption)
            Spacer()
            Picker("", selection: Binding(
                get: { state.project.pageSetup.layoutDirection },
                set: { value in state.updateProject { $0.pageSetup.layoutDirection = value } }
            )) {
                Text("水平").tag(LayoutDirection.horizontal)
                Text("竖排").tag(LayoutDirection.vertical)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 130)
        }

        Toggle("对页排版", isOn: Binding(
            get: { state.project.pageSetup.facingPages },
            set: { value in state.updateProject { $0.pageSetup.facingPages = value } }
        ))
        .toggleStyle(.checkbox)

        HStack {
            Text("分栏数").foregroundColor(.secondary).font(.caption)
            Spacer()
            Stepper("\(state.project.pageSetup.columns) 栏", value: Binding(
                get: { state.project.pageSetup.columns },
                set: { value in state.updateProject { $0.pageSetup.columns = value } }
            ), in: 1...4)
        }

        Divider()

        sectionLabel("页边距 (mm)")
        let m = state.project.pageSetup.margins
        infoRow(label: "上 / 下", value: String(format: "%.1f / %.1f", pointsToMillimeters(m.top), pointsToMillimeters(m.bottom)))
        infoRow(label: "左 / 右", value: String(format: "%.1f / %.1f", pointsToMillimeters(m.left), pointsToMillimeters(m.right)))
        infoRow(label: "印刷出血", value: String(format: "%.1f mm", state.project.pageSetup.bleedMM ?? 3.0))

        Divider()

        sectionLabel("页面")
        HStack {
            Button {
                let prev = max(1, state.currentPageNumber - 1)
                state.currentPageNumber = prev
                onPageClick(prev)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
            .disabled(state.currentPageNumber <= 1)

            Text("第 \(state.currentPageNumber) / \(state.laidOutDocument?.pages.count ?? 0) 页")
                .font(.caption)
                .frame(maxWidth: .infinity)

            Button {
                let total = state.laidOutDocument?.pages.count ?? 0
                let next = min(total, state.currentPageNumber + 1)
                state.currentPageNumber = next
                onPageClick(next)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
            .disabled(state.currentPageNumber >= (state.laidOutDocument?.pages.count ?? 0))
        }
    }

    // MARK: - Shared bits

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .font(.caption)
            Spacer()
            Text(value)
                .foregroundColor(.primary)
                .font(.caption)
                .fontWeight(.semibold)
        }
    }

    /// Resolves a stored hex color to a SwiftUI Color for picker bindings.
    private func colorFromHex(_ hex: String?) -> Color? {
        guard let hex, let ns = NSColor.fromHex(hex) else { return nil }
        return Color(nsColor: ns)
    }

    /// Resolves a stored color string to a `PrintColor` for the multi-space picker.
    private func printColor(_ hex: String?, fallback: PrintColor) -> PrintColor {
        guard let hex, let color = PrintColor(string: hex) else { return fallback }
        return color
    }

    /// The "多套系" trigger next to a quick ColorPicker: opens the RGB/HSB/CMYK
    /// picker in a floating panel (separate window) so applying a color — and the
    /// full-book relayout it triggers — can't tear the picker down mid-edit.
    private func multiSpaceButton(
        title: String,
        current: PrintColor,
        apply: @escaping (PrintColor) -> Void
    ) -> some View {
        Button {
            MultiSpaceColorPanelController.shared.toggle(
                title: title,
                initial: current,
                state: state,
                apply: apply
            )
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .buttonStyle(.borderless)
        .help("多套系拾色器 (RGB / HSB / CMYK)")
    }

    private func pointsToMillimeters(_ points: Double) -> Double {
        points / 72 * 25.4
    }

    /// InDesign 描边粗细预设（点）。
    private var strokeWeightOptions: [Double] {
        [0, 0.25, 0.5, 0.75, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    }

    private func strokeWeightLabel(_ w: Double) -> String {
        // "%g" 去掉多余的零：0.25 点 / 1 点 / 2.5 点。
        String(format: "%g 点", w)
    }

    /// Stepper 上/下一档：吸附到最接近的预设，越过一格。
    private func nextStrokeWeight(above current: Double) -> Double {
        strokeWeightOptions.first { $0 > current + 0.001 } ?? strokeWeightOptions.last ?? current
    }

    private func nextStrokeWeight(below current: Double) -> Double {
        strokeWeightOptions.last { $0 < current - 0.001 } ?? strokeWeightOptions.first ?? current
    }

    private func icon(for kind: PageFrameKind) -> String {
        switch kind {
        case .text, .footnote, .sideNote, .runningHeader: return "text.alignleft"
        case .caption: return "text.alignleft"
        case .image: return "photo"
        case .callout: return "rectangle.inset.filled"
        case .table: return "tablecells"
        case .footnoteDivider: return "minus"
        case .rectangle: return "rectangle"
        case .line: return "line.diagonal"
        }
    }

    private func kindLabel(for kind: PageFrameKind) -> String {
        switch kind {
        case .text: return "文本框"
        case .caption: return "图注框"
        case .image: return "图片框"
        case .callout: return "边栏呼应框"
        case .table: return "表格数据框"
        case .footnote: return "脚注信息"
        case .footnoteDivider: return "脚注分界线"
        case .sideNote: return "旁注信息"
        case .runningHeader: return "页眉"
        case .rectangle: return "矩形"
        case .line: return "直线"
        }
    }
}

/// Text content editor for a selected text/caption frame. Keeps a local draft so
/// typing doesn't re-layout on every keystroke; commits on "应用文字".
private struct ObjectTextEditor: View {
    let frameId: UUID
    let initialText: String
    let isPageLocked: Bool
    @ObservedObject var state: AppState

    @State private var draftText: String

    init(frameId: UUID, initialText: String, isPageLocked: Bool, state: AppState) {
        self.frameId = frameId
        self.initialText = initialText
        self.isPageLocked = isPageLocked
        self.state = state
        _draftText = State(initialValue: initialText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $draftText)
                .font(.system(size: 12))
                .frame(minHeight: 82)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                .disabled(isPageLocked)

            HStack {
                Button("应用文字") {
                    state.selectedFrameId = frameId
                    state.updateSelectedFrameText(draftText)
                }
                .buttonStyle(.bordered)
                .disabled(isPageLocked || draftText == initialText)

                Button("还原") {
                    draftText = initialText
                }
                .buttonStyle(.bordered)
                .disabled(draftText == initialText)
            }
        }
    }
}
