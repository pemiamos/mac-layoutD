import SwiftUI
import LayoutDCore

struct ToolbarView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 8) {
            // Group 1: Selection & Pointer tools (V / A)
            VStack(spacing: 4) {
                toolButton(.selection)
                toolButton(.directSelection)
            }

            Divider()
                .padding(.horizontal, 4)

            // Group 2: Type & Frame authoring — edit existing text (T), draw new
            // text / image frames (F). All write structured LayoutPlan blocks.
            VStack(spacing: 4) {
                toolButton(.type)
                toolButton(.textFrame)
                toolButton(.imageFrame)
            }

            Divider()
                .padding(.horizontal, 4)

            // Group 2b: Shape authoring — rectangle (M) and horizontal/vertical rule (\).
            // Structured decorative blocks, still exported to IDML.
            VStack(spacing: 4) {
                toolButton(.rectangle)
                toolButton(.line)
            }

            Divider()
                .padding(.horizontal, 4)

            // Group 3: Layout & Structure tools (Shift+P / U)
            VStack(spacing: 4) {
                toolButton(.page)
                toolButton(.gap)
            }

            Divider()
                .padding(.horizontal, 4)

            // Group 4: Annotations & Proofreading (overlay annotations)
            VStack(spacing: 4) {
                toolButton(.annotation)
            }

            Divider()
                .padding(.horizontal, 4)

            // Group 5: Navigation tools (H / Z)
            VStack(spacing: 4) {
                toolButton(.hand)
                toolButton(.zoom)
            }
            
            Spacer()
            
            // Group 6: Fill & Stroke Indicators (overlapping boxes)
            colorIndicatorSection
            
            Divider()
                .padding(.horizontal, 4)
            
            // Group 7: Formatting Target (Container vs Text)
            formattingTargetSection
            
            // Group 8: Apply Color, Gradient, None
            colorApplySection
                .padding(.bottom, 4)
                
            Divider()
                .padding(.horizontal, 4)
                
            // Group 9: Screen Mode (Normal vs Preview)
            screenModeSection
                .padding(.bottom, 8)
        }
        .padding(.vertical, 8)
        .frame(width: 42)
        .background(Color(NSColor.windowBackgroundColor))
        .border(Color(NSColor.separatorColor), width: 0.5)
    }
    
    private func toolButton(_ tool: LayoutTool) -> some View {
        Button(action: {
            state.activeTool = tool
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(state.activeTool == tool ? Color.accentColor.opacity(0.25) : Color.clear)
                
                Image(systemName: tool.iconName)
                    .font(.system(size: 15))
                    .foregroundColor(state.activeTool == tool ? Color.accentColor : .primary)
            }
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .help(toolHelp(tool))
    }

    private func toolHelp(_ tool: LayoutTool) -> String {
        if tool == .page {
            return "\(tool.displayName) (⇧P)"
        }
        if let key = tool.shortcutKey {
            return "\(tool.displayName) (\(String(key).uppercased()))"
        }
        return tool.displayName
    }
    
    private var colorIndicatorSection: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                // Stroke box
                Button(action: {
                    state.isFillActive = false
                }) {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(state.activeStrokeColor, lineWidth: 3)
                        .background(Color(NSColor.controlBackgroundColor))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .offset(x: 10, y: 10)
                .zIndex(state.isFillActive ? 0 : 1)
                
                // Fill box
                Button(action: {
                    state.isFillActive = true
                }) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(state.activeFillColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Color.primary, lineWidth: 1)
                        )
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .zIndex(state.isFillActive ? 1 : 0)
            }
            .frame(width: 32, height: 32)
            
            // Swap and default buttons
            HStack(spacing: 6) {
                Button(action: {
                    let temp = state.activeFillColor
                    state.activeFillColor = state.activeStrokeColor
                    state.activeStrokeColor = temp
                }) {
                    Image(systemName: "arrow.2.squarepath")
                        .font(.system(size: 8))
                }
                .buttonStyle(.plain)
                .help("互换填色与描边")
                
                Button(action: {
                    state.activeFillColor = Color(nsColor: NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.46, alpha: 1))
                    state.activeStrokeColor = .black
                }) {
                    Image(systemName: "square.on.square")
                        .font(.system(size: 8))
                }
                .buttonStyle(.plain)
                .help("默认颜色")
            }
        }
    }

    private var formattingTargetSection: some View {
        HStack(spacing: 4) {
            Button(action: {
                state.activeFormattingTarget = .container
            }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(state.activeFormattingTarget == .container ? Color.accentColor.opacity(0.25) : Color.clear)
                        .frame(width: 16, height: 16)
                    Image(systemName: "square")
                        .font(.system(size: 10))
                        .foregroundColor(state.activeFormattingTarget == .container ? Color.accentColor : .primary)
                }
            }
            .buttonStyle(.plain)
            .help("格式化影响容器")
            
            Button(action: {
                state.activeFormattingTarget = .text
            }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(state.activeFormattingTarget == .text ? Color.accentColor.opacity(0.25) : Color.clear)
                        .frame(width: 16, height: 16)
                    Text("T")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(state.activeFormattingTarget == .text ? Color.accentColor : .primary)
                }
            }
            .buttonStyle(.plain)
            .help("格式化影响文本")
        }
    }

    private var colorApplySection: some View {
        HStack(spacing: 4) {
            Button(action: {
                let color = state.isFillActive ? state.activeFillColor : state.activeStrokeColor
                state.applyColorToSelectedFrame(color)
            }) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(state.isFillActive ? state.activeFillColor : state.activeStrokeColor)
                    .frame(width: 10, height: 10)
                    .border(Color.primary, width: 0.5)
            }
            .buttonStyle(.plain)
            .help("应用颜色")
            
            Button(action: {
                state.removeColorFromSelectedFrame()
            }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.primary, lineWidth: 0.5)
                        .background(Color(NSColor.controlBackgroundColor))
                        .frame(width: 10, height: 10)
                    
                    lineDiagonalMini
                }
            }
            .buttonStyle(.plain)
            .help("应用[无]色")
        }
    }
    
    private var lineDiagonalMini: some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: CGPoint(x: proxy.size.width, y: 0))
                path.addLine(to: CGPoint(x: 0, y: proxy.size.height))
            }
            .stroke(Color.red, lineWidth: 1.0)
        }
        .frame(width: 10, height: 10)
    }

    private var screenModeSection: some View {
        VStack(spacing: 4) {
            Button(action: {
                state.activeScreenMode = .normal
            }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(state.activeScreenMode == .normal ? Color.accentColor.opacity(0.25) : Color.clear)
                        .frame(width: 30, height: 20)
                    
                    Image(systemName: "rectangle.dashed")
                        .font(.system(size: 11))
                        .foregroundColor(state.activeScreenMode == .normal ? Color.accentColor : .primary)
                }
            }
            .buttonStyle(.plain)
            .help("正常模式")
            
            Button(action: {
                state.activeScreenMode = .preview
            }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(state.activeScreenMode == .preview ? Color.accentColor.opacity(0.25) : Color.clear)
                        .frame(width: 30, height: 20)
                    
                    Image(systemName: "eye.fill")
                        .font(.system(size: 11))
                        .foregroundColor(state.activeScreenMode == .preview ? Color.accentColor : .primary)
                }
            }
            .buttonStyle(.plain)
            .help("预览模式")
        }
    }
}
