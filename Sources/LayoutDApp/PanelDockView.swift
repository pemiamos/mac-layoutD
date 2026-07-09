import SwiftUI

/// InDesign 式右侧面板坞：把「面板」（页面/属性/图层/资产/色板）与「检查器」
/// （预检/模板/AI 方案/样式）合并为一列，顶部分段切换——画布因此获得更大空间。
struct PanelDockView: View {
    let sidebar: SidebarView
    let inspector: InspectorView
    let wizard: WizardView
    let wireframe: WireframePanelView

    @State private var selectedDock = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedDock) {
                Text("面板").tag(0)
                Text("检查器").tag(1)
                Text("线框图").tag(2)
                Text("向导").tag(3)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            // 多个面板都保持挂载（隐藏而非销毁），切换不丢内部状态。
            ZStack {
                sidebar.opacity(selectedDock == 0 ? 1 : 0)
                    .allowsHitTesting(selectedDock == 0)
                inspector.opacity(selectedDock == 1 ? 1 : 0)
                    .allowsHitTesting(selectedDock == 1)
                wireframe.opacity(selectedDock == 2 ? 1 : 0)
                    .allowsHitTesting(selectedDock == 2)
                wizard.opacity(selectedDock == 3 ? 1 : 0)
                    .allowsHitTesting(selectedDock == 3)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}
