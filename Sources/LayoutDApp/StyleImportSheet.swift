import SwiftUI
import LayoutDCore
import LayoutDImport

struct StyleImportSheet: View {
    @ObservedObject var state: AppState
    let tokens: DesignTokens
    let format: ImportFormat
    let onDismiss: () -> Void
    
    @State private var compensateBaselineGrid: Double = 14.0
    
    // Compute binding statistics
    private var bindingStats: (matches: Int, total: Int, rate: Double) {
        var total = 0
        var matches = 0
        
        // Style parameters
        for style in state.project.styles.paragraphStyles {
            total += 5
            if tokens.scalar("paragraph.\(style.id).fontSize") != nil { matches += 1 }
            if tokens.scalar("paragraph.\(style.id).lineHeight") != nil { matches += 1 }
            if tokens.scalar("paragraph.\(style.id).firstLineIndent") != nil { matches += 1 }
            if tokens.scalar("paragraph.\(style.id).spaceBefore") != nil { matches += 1 }
            if tokens.scalar("paragraph.\(style.id).spaceAfter") != nil { matches += 1 }
        }
        
        // Page setup parameters
        total += 7
        if tokens.scalar("page.margin.top") != nil { matches += 1 }
        if tokens.scalar("page.margin.right") != nil { matches += 1 }
        if tokens.scalar("page.margin.bottom") != nil { matches += 1 }
        if tokens.scalar("page.margin.left") != nil { matches += 1 }
        if tokens.scalar("page.columns") != nil { matches += 1 }
        if tokens.scalar("page.gutter") != nil { matches += 1 }
        if tokens.scalar("page.baselineGrid") != nil { matches += 1 }
        
        let rate = total > 0 ? (Double(matches) / Double(total) * 100.0) : 0.0
        return (matches, total, rate)
    }
    
    private var isBaselineGridMissing: Bool {
        tokens.scalar("page.baselineGrid") == nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("导入样式基线")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("从 \(format == .figma ? "Figma Variables" : "DTCG JSON") 成功解析 \(tokens.colors.count) 个颜色，\(tokens.scalars.count) 个数值参数")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                // Format Badge
                Text(format == .figma ? "Figma" : "DTCG")
                    .font(.caption2)
                    .fontWeight(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(format == .figma ? Color.orange.opacity(0.2) : Color.blue.opacity(0.2))
                    .foregroundColor(format == .figma ? .orange : .blue)
                    .cornerRadius(4)
            }
            .padding(.all, 20)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Section 1: Binding Rate Audit
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Token 绑定率体检")
                            .font(.headline)
                        
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 6)
                                    .frame(width: 60, height: 60)
                                Circle()
                                    .trim(from: 0.0, to: CGFloat(bindingStats.rate / 100.0))
                                    .stroke(bindingStats.rate > 70 ? Color.green : (bindingStats.rate > 40 ? Color.orange : Color.red), lineWidth: 6)
                                    .frame(width: 60, height: 60)
                                    .rotationEffect(Angle(degrees: -90))
                                
                                Text(String(format: "%.0f%%", bindingStats.rate))
                                    .font(.system(size: 14, weight: .bold))
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("本项目共有 \(bindingStats.total) 项关键样式参数")
                                    .font(.subheadline)
                                Text("其中已成功在导入的文件中匹配到 \(bindingStats.matches) 个对应 Token ID，将在导入后自动建立响应式绑定。")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.all, 12)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(8)
                    }
                    
                    // Section 2: Lossy Item Warnings (Compensation)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("有损导入项与值补偿")
                            .font(.headline)
                        
                        // Composite Fonts Warning
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 14))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("中西文复合字体设置")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                Text("Figma/DTCG 文件中不含复合字体映射。导入后英数字将自动应用默认复合字体映射（如 Georgia/Helvetica），汉字保持基线对齐。")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.all, 12)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                        
                        // Baseline Grid Warning (if missing)
                        if isBaselineGridMissing {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                    .font(.system(size: 14))
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("缺少基线网格 (page.baselineGrid)")
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                    Text("未检测到基线网格参数。请在此处设置补偿值，导入后该值将被写入 PageSetup：")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    HStack {
                                        Text("网格高度:")
                                            .font(.caption)
                                        Stepper(String(format: "%.1f pt", compensateBaselineGrid), value: $compensateBaselineGrid, in: 8.0...30.0, step: 0.5)
                                    }
                                    .padding(.top, 2)
                                }
                            }
                            .padding(.all, 12)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    
                    // Section 3: Imported Tokens Detail List
                    VStack(alignment: .leading, spacing: 8) {
                        Text("导入的 Token 列表")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 0) {
                            // Header
                            HStack {
                                Text("Token ID")
                                    .fontWeight(.bold)
                                    .frame(width: 200, alignment: .leading)
                                Text("类型")
                                    .fontWeight(.bold)
                                    .frame(width: 80, alignment: .leading)
                                Text("解析值")
                                    .fontWeight(.bold)
                                    .frame(alignment: .leading)
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(Color(NSColor.controlBackgroundColor))
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 0) {
                                // List colors
                                ForEach(tokens.colors, id: \.id) { colorToken in
                                    HStack {
                                        Text(colorToken.id)
                                            .font(.system(.caption, design: .monospaced))
                                            .frame(width: 200, alignment: .leading)
                                        Text("Color")
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                            .frame(width: 80, alignment: .leading)
                                        
                                        // Colored block and value
                                        HStack(spacing: 6) {
                                            if let hex = colorToken.valuesByMode[tokens.defaultMode] ?? colorToken.valuesByMode.first?.value {
                                                RoundedRectangle(cornerRadius: 2)
                                                    .fill(Color(nsColor: NSColor.fromHex(hex) ?? .black))
                                                    .frame(width: 12, height: 12)
                                                Text(hex)
                                                    .font(.caption)
                                            } else {
                                                Text("-")
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    
                                    Divider()
                                }
                                
                                // List scalars
                                ForEach(tokens.scalars, id: \.id) { scalar in
                                    HStack {
                                        Text(scalar.id)
                                            .font(.system(.caption, design: .monospaced))
                                            .frame(width: 200, alignment: .leading)
                                        Text(scalar.kind.rawValue.capitalized)
                                            .font(.caption2)
                                            .foregroundColor(.purple)
                                            .frame(width: 80, alignment: .leading)
                                        Text(String(format: "%.1f", scalar.value))
                                            .font(.caption)
                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    
                                    Divider()
                                }
                            }
                            .font(.caption)
                        }
                        .border(Color(NSColor.separatorColor), width: 0.5)
                        .cornerRadius(4)
                    }
                }
                .padding(.all, 20)
            }
            .frame(height: 380)
            
            Divider()
            
            // Footer Action buttons
            HStack(spacing: 12) {
                Spacer()
                Button("取消") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("确认导入") {
                    state.applyImportedTokens(tokens, baselineGridCompensate: isBaselineGridMissing ? compensateBaselineGrid : nil)
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.all, 16)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 520, height: 520)
        .onAppear {
            compensateBaselineGrid = state.project.pageSetup.baselineGrid
        }
    }
}
