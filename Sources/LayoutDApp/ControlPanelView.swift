import SwiftUI
import LayoutDCore

/// InDesign 式顶部控制面板：横贯窗口顶部的上下文栏。
/// 选中单个帧时显示可编辑的 X/Y/宽/高（单位 pt，写入该页 LayoutPlan 覆写，可撤销）
/// 与「对齐对象」六键；选中多个帧时切换为「N 个对象」+ 对齐 + 分布（≥3 个）工具，
/// 参照可选 选区/页面/页边距。未选中时显示文档概要与当前工具提示。
struct ControlPanelView: View {
    @ObservedObject var state: AppState

    @State private var xText = ""
    @State private var yText = ""
    @State private var wText = ""
    @State private var hText = ""
    /// 对齐/分布的参照框。多选默认「选区」，单选时自动退化为「页边距」（选区对单个框无意义）。
    @State private var alignReference: AlignmentReference = .selection

    private var selectedFrame: PageFrame? {
        guard let id = state.selectedFrameId, let doc = state.laidOutDocument else { return nil }
        for page in doc.pages {
            if let frame = page.frames.first(where: { $0.id == id }) {
                return frame
            }
        }
        return nil
    }

    private var selectionCount: Int { state.selectedFrameIds.count }

    var body: some View {
        HStack(spacing: 12) {
            if selectionCount >= 2 {
                multiSelectionControls
            } else if let frame = selectedFrame {
                selectionControls(frame: frame)
            } else {
                documentSummary
            }
            Spacer()
            Text(state.activeTool.displayName)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(Color(NSColor.separatorColor)), alignment: .bottom)
        .onChange(of: state.selectedFrameId) { syncFields() }
        .onChange(of: selectedFrame?.rect) { syncFields() }
        .onAppear { syncFields() }
    }

    // MARK: - Single selection

    @ViewBuilder
    private func selectionControls(frame: PageFrame) -> some View {
        HStack(spacing: 6) {
            Image(systemName: iconName(for: frame.kind))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text(kindName(frame.kind))
                .font(.system(size: 11, weight: .medium))
        }

        Divider().frame(height: 18)

        geometryField(label: "X", text: $xText) { value in
            state.updateSelectedFrameCoordinate(x: value, y: nil, width: nil, height: nil)
        }
        geometryField(label: "Y", text: $yText) { value in
            state.updateSelectedFrameCoordinate(x: nil, y: value, width: nil, height: nil)
        }

        Divider().frame(height: 18)

        geometryField(label: "宽", text: $wText) { value in
            state.updateSelectedFrameCoordinate(x: nil, y: nil, width: value, height: nil)
        }
        geometryField(label: "高", text: $hText) { value in
            state.updateSelectedFrameCoordinate(x: nil, y: nil, width: nil, height: value)
        }

        Divider().frame(height: 18)

        // 单选：参照只有 页面/页边距（选区对单个框无意义）。
        referenceMenu(allowSelection: false)
        alignRow

        if let page = state.findPageNumber(for: frame.id) {
            Divider().frame(height: 18)
            Text("第 \(page) 页")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Multi selection

    @ViewBuilder
    private var multiSelectionControls: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.on.square.dashed")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text("\(selectionCount) 个对象")
                .font(.system(size: 11, weight: .medium))
        }

        Divider().frame(height: 18)

        referenceMenu(allowSelection: true)
        alignRow

        Divider().frame(height: 18)

        distributeRow
    }

    // MARK: - Shared rows

    /// 对齐参照菜单：选区（仅多选）/页面/页边距。
    private func referenceMenu(allowSelection: Bool) -> some View {
        Menu {
            ForEach(AlignmentReference.allCases, id: \.self) { ref in
                if ref != .selection || allowSelection {
                    Button {
                        alignReference = ref
                    } label: {
                        if effectiveReference(allowSelection: allowSelection) == ref {
                            Label(ref.displayName, systemImage: "checkmark")
                        } else {
                            Text(ref.displayName)
                        }
                    }
                }
            }
        } label: {
            Text(referenceShortName(effectiveReference(allowSelection: allowSelection)))
                .font(.system(size: 10))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("对齐/分布参照")
    }

    /// 「对齐对象」六键：左/中/右 · 上/中/下。
    private var alignRow: some View {
        HStack(spacing: 4) {
            ForEach(FrameAlignment.allCases, id: \.self) { alignment in
                Button {
                    let ref = effectiveReference(allowSelection: selectionCount >= 2)
                    state.alignSelection(alignment, reference: ref)
                } label: {
                    Image(systemName: alignment.iconName)
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help(alignment.displayName)
                if alignment == .right {
                    Divider().frame(height: 14)
                }
            }
        }
    }

    /// 「分布对象」六键 + 「分布间距」两键。需选中 ≥3 个对象才启用。
    private var distributeRow: some View {
        let enabled = selectionCount >= 3
        return HStack(spacing: 4) {
            ForEach(DistributionMode.allCases, id: \.self) { mode in
                Button {
                    state.distributeSelection(mode)
                } label: {
                    Image(systemName: mode.iconName)
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .disabled(!enabled)
                .help(enabled ? mode.displayName : "\(mode.displayName)（需选中 3 个以上对象）")
                if mode == .rightEdges {
                    Divider().frame(height: 14)
                }
            }
        }
    }

    // MARK: - Reference helpers

    /// Collapses `.selection` to `.margin` when it isn't available (single frame),
    /// so a stale menu choice never produces a no-op alignment.
    private func effectiveReference(allowSelection: Bool) -> AlignmentReference {
        if alignReference == .selection && !allowSelection { return .margin }
        return alignReference
    }

    private func referenceShortName(_ ref: AlignmentReference) -> String {
        switch ref {
        case .selection: return "选区"
        case .page: return "页面"
        case .margin: return "页边距"
        }
    }

    // MARK: - Document summary

    private var documentSummary: some View {
        HStack(spacing: 8) {
            Text(state.project.metadata.title)
                .font(.system(size: 11, weight: .medium))
            Divider().frame(height: 18)
            Text(pageSetupSummary)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private var pageSetupSummary: String {
        let size = state.project.pageSetup.pageSize
        let pages = state.laidOutDocument?.pages.count ?? 0
        let facing = state.project.pageSetup.facingPages == true ? "对开" : "单页"
        return String(format: "%.0f × %.0f pt · %d 页 · %@", size.width, size.height, pages, facing)
    }

    private func geometryField(label: String, text: Binding<String>, commit: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 58)
                .onSubmit {
                    if let value = Double(text.wrappedValue.trimmingCharacters(in: .whitespaces)) {
                        commit(value)
                    } else {
                        syncFields()
                    }
                }
        }
    }

    private func syncFields() {
        guard let rect = selectedFrame?.rect else {
            xText = ""; yText = ""; wText = ""; hText = ""
            return
        }
        xText = String(format: "%.1f", rect.x)
        yText = String(format: "%.1f", rect.y)
        wText = String(format: "%.1f", rect.width)
        hText = String(format: "%.1f", rect.height)
    }

    private func kindName(_ kind: PageFrameKind) -> String {
        switch kind {
        case .text: return "文本框"
        case .image: return "图片框"
        case .caption: return "图注"
        case .callout: return "知识卡片"
        case .table: return "表格"
        case .footnote: return "脚注"
        case .footnoteDivider: return "脚注分隔线"
        case .sideNote: return "旁注"
        case .runningHeader: return "页眉"
        case .rectangle: return "矩形"
        case .line: return "直线"
        }
    }

    private func iconName(for kind: PageFrameKind) -> String {
        switch kind {
        case .text: return "text.justify"
        case .image: return "photo"
        case .caption: return "text.below.photo"
        case .callout: return "rectangle.badge.checkmark"
        case .table: return "tablecells"
        case .footnote, .footnoteDivider: return "text.append"
        case .sideNote: return "note.text"
        case .runningHeader: return "textformat.abc"
        case .rectangle: return "rectangle"
        case .line: return "line.diagonal"
        }
    }
}
