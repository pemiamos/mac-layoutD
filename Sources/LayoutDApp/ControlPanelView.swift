import SwiftUI
import LayoutDCore

/// InDesign 式顶部控制面板：横贯窗口顶部的上下文栏。
/// 选中帧时显示可编辑的 X/Y/宽/高（单位 pt，写入该页 LayoutPlan 覆写，可撤销）；
/// 未选中时显示文档概要与当前工具提示。
struct ControlPanelView: View {
    @ObservedObject var state: AppState

    @State private var xText = ""
    @State private var yText = ""
    @State private var wText = ""
    @State private var hText = ""
    /// What「对齐」snaps the selected frame to. Defaults to the margin box, which is
    /// what book pages are laid out against; toggle to the full page via the menu.
    @State private var alignReference: AlignmentReference = .margin

    private var selectedFrame: PageFrame? {
        guard let id = state.selectedFrameId, let doc = state.laidOutDocument else { return nil }
        for page in doc.pages {
            if let frame = page.frames.first(where: { $0.id == id }) {
                return frame
            }
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 12) {
            if let frame = selectedFrame {
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

        alignmentControls

        if let page = state.findPageNumber(for: frame.id) {
            Divider().frame(height: 18)
            Text("第 \(page) 页")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    /// InDesign 式「对齐对象」：左中右 + 上中下六键，配一个「页面/页边距」参照菜单。
    /// 单选把当前框贴到参照框，写入该页 override，可撤销。多框互相对齐/分布待多选后再做。
    private var alignmentControls: some View {
        HStack(spacing: 4) {
            Menu {
                ForEach(AlignmentReference.allCases, id: \.self) { ref in
                    Button {
                        alignReference = ref
                    } label: {
                        if alignReference == ref {
                            Label(ref.displayName, systemImage: "checkmark")
                        } else {
                            Text(ref.displayName)
                        }
                    }
                }
            } label: {
                Text(alignReference == .margin ? "页边距" : "页面")
                    .font(.system(size: 10))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("对齐参照：页面或页边距")

            ForEach(FrameAlignment.allCases, id: \.self) { alignment in
                alignButton(alignment)
                if alignment == .right {
                    Divider().frame(height: 14)
                }
            }
        }
    }

    private func alignButton(_ alignment: FrameAlignment) -> some View {
        Button {
            state.alignSelectedFrame(alignment, reference: alignReference)
        } label: {
            Image(systemName: alignment.iconName)
                .font(.system(size: 12))
        }
        .buttonStyle(.borderless)
        .help(alignment.displayName)
    }

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
        }
    }
}
