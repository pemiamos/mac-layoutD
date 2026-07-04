import SwiftUI
import LayoutDCore

/// InDesign 式底部状态栏：页码导航 + 预检状态灯 + 缩放控制。
struct StatusBarView: View {
    @ObservedObject var state: AppState

    let onGoToPage: (Int) -> Void
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onFitWidth: () -> Void

    @State private var pageText = "1"

    private var pageCount: Int {
        state.laidOutDocument?.pages.count ?? 0
    }

    var body: some View {
        HStack(spacing: 10) {
            pageNavigator

            Divider().frame(height: 14)

            preflightLamp

            Spacer()

            zoomControls
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(Color(NSColor.separatorColor)), alignment: .top)
        .onChange(of: state.currentPageNumber) { _, newValue in
            pageText = String(newValue)
        }
        .onAppear { pageText = String(state.currentPageNumber) }
    }

    private var pageNavigator: some View {
        HStack(spacing: 4) {
            navButton("backward.end.fill") { onGoToPage(1) }
                .help("第一页")
            navButton("chevron.backward") { onGoToPage(state.currentPageNumber - 1) }
                .help("上一页")

            TextField("", text: $pageText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))
                .multilineTextAlignment(.center)
                .frame(width: 36)
                .onSubmit {
                    if let page = Int(pageText.trimmingCharacters(in: .whitespaces)) {
                        onGoToPage(page)
                    } else {
                        pageText = String(state.currentPageNumber)
                    }
                }
            Text("/ \(pageCount)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)

            navButton("chevron.forward") { onGoToPage(state.currentPageNumber + 1) }
                .help("下一页")
            navButton("forward.end.fill") { onGoToPage(pageCount) }
                .help("最后一页")
        }
    }

    private var preflightLamp: some View {
        let errors = state.report?.severityCounts[IssueSeverity.error.rawValue] ?? 0
        let warnings = state.report?.severityCounts[IssueSeverity.warning.rawValue] ?? 0
        return HStack(spacing: 5) {
            Circle()
                .fill(errors == 0 ? Color.green : Color.red)
                .frame(width: 7, height: 7)
            Text(errors == 0
                 ? (warnings == 0 ? "预检：无错误" : "预检：\(warnings) 个警告")
                 : "预检：\(errors) 个错误 · \(warnings) 个警告")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .help("预检详情见右侧「检查器」面板")
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            navButton("minus.magnifyingglass") { onZoomOut() }
                .help("缩小")
            Text("\(state.zoomPercent)%")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 38)
            navButton("plus.magnifyingglass") { onZoomIn() }
                .help("放大")
            navButton("arrow.left.and.right.square") { onFitWidth() }
                .help("适合页宽")
        }
    }

    private func navButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10))
        }
        .buttonStyle(.plain)
    }
}
