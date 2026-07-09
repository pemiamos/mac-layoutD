import SwiftUI
import LayoutDCore

struct WizardView: View {
    @ObservedObject var state: AppState
    
    // Callbacks to WorkspaceViewController for file panel and export operations
    var onAddReferenceImage: (@escaping (String?) -> Void) -> Void
    var onImportSpecPack: (@escaping (String?, String?) -> Void) -> Void
    var onGenerateSample: (@escaping (String?) -> Void) -> Void
    var onFreezeStyle: (@escaping (Bool) -> Void) -> Void
    var onRunPlanner: (@escaping ([String]?) -> Void) -> Void
    var onExportIDML: (@escaping (String?) -> Void) -> Void
    var onRerollSpread: (Int, @escaping ([String]?) -> Void) -> Void
    
    @State private var showResetWarning = false
    @State private var targetStep = 1
    
    private var wizardState: WizardState {
        state.project.wizardState ?? WizardState()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            StepBarView(
                currentStep: wizardState.currentStep,
                maxUnlockedStep: wizardState.maxUnlockedStep,
                onStepSelected: { step in
                    handleStepNavigation(to: step)
                }
            )
            .padding(.top, 8)
            
            Divider()
                .padding(.vertical, 8)
            
            // Step Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    stepHeaderView
                    
                    stepContentView
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
            }
            
            Divider()
                .padding(.vertical, 8)
            
            // Bottom navigation
            HStack {
                Button("上一步") {
                    handleStepNavigation(to: wizardState.currentStep - 1)
                }
                .disabled(wizardState.currentStep <= 1)
                
                Spacer()
                
                Button("下一步") {
                    handleStepNavigation(to: wizardState.currentStep + 1)
                }
                .disabled(wizardState.currentStep >= 6 || wizardState.currentStep >= wizardState.maxUnlockedStep)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .alert(isPresented: $showResetWarning) {
            Alert(
                title: Text("确认回退？"),
                message: Text("回退到较早的步骤并修改内容会导致后续步骤的产物重置。"),
                primaryButton: .destructive(Text("确定回退")) {
                    performNavigation(to: targetStep)
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }
    
    private var stepHeaderView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("第 \(wizardState.currentStep) 站：\(stepName(for: wizardState.currentStep))")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(stepDescription(for: wizardState.currentStep))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private var stepContentView: some View {
        switch wizardState.currentStep {
        case 1:
            step1View
        case 2:
            step2View
        case 3:
            step3View
        case 4:
            step4View
        case 5:
            step5View
        case 6:
            step6View
        default:
            EmptyView()
        }
    }
    
    // MARK: - Step 1 View: Reference Images
    private var step1View: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("添加参考图...") {
                onAddReferenceImage { path in
                    if let path {
                        var current = wizardState
                        if !current.referenceImages.contains(path) {
                            current.referenceImages.append(path)
                            if current.maxUnlockedStep < 2 {
                                current.maxUnlockedStep = 2
                            }
                            updateWizardState(current)
                        }
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            
            if wizardState.referenceImages.isEmpty {
                Text("暂无参考图，请先添加参考图以解锁下一步。")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                Text("已选参考图：")
                    .font(.subheadline)
                    .bold()
                
                ForEach(wizardState.referenceImages, id: \.self) { path in
                    HStack {
                        Image(nsImage: NSImage(contentsOfFile: path) ?? NSImage())
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 40, height: 40)
                            .cornerRadius(4)
                            .background(Color.gray.opacity(0.1))
                        
                        VStack(alignment: .leading) {
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .font(.body)
                                .lineLimit(1)
                            Text(path)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            var current = wizardState
                            current.referenceImages.removeAll(where: { $0 == path })
                            if current.referenceImages.isEmpty {
                                current.maxUnlockedStep = 1
                            }
                            updateWizardState(current)
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(6)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(6)
                }
            }
        }
    }
    
    // MARK: - Step 2 View: Spec Pack
    private var step2View: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("导入规范包 JSON...") {
                onImportSpecPack { path, name in
                    if let path, let name {
                        var current = wizardState
                        current.specPackPath = path
                        current.specPackName = name
                        if current.maxUnlockedStep < 3 {
                            current.maxUnlockedStep = 3
                        }
                        updateWizardState(current)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            
            if let specName = wizardState.specPackName, let specPath = wizardState.specPackPath {
                VStack(alignment: .leading, spacing: 8) {
                    Text("当前规范包：")
                        .font(.subheadline)
                        .bold()
                    
                    Text(specName)
                        .font(.body)
                        .bold()
                        .foregroundColor(.accentColor)
                    
                    Text("路径：\(specPath)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Display token summary
                    let setup = state.project.pageSetup
                    Text("页面尺寸：\(Int(setup.pageSize.width)) × \(Int(setup.pageSize.height)) pt")
                        .font(.caption)
                    Text("页栏数：\(setup.columns)")
                        .font(.caption)
                    Text("段落样式数：\(state.project.styles.paragraphStyles.count)")
                        .font(.caption)
                }
                .padding(10)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(6)
            } else {
                Text("未导入规范包。请先导入规范包以解锁下一步。")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Step 3 View: Sample Preview
    private var step3View: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("生成样张 PDF") {
                onGenerateSample { path in
                    if let path {
                        var current = wizardState
                        current.samplePDFPath = path
                        if current.maxUnlockedStep < 4 {
                            current.maxUnlockedStep = 4
                        }
                        updateWizardState(current)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            
            if let samplePath = wizardState.samplePDFPath {
                VStack(alignment: .leading, spacing: 8) {
                    Text("样张已成功生成！")
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(.green)
                    
                    Text("位置：\(samplePath)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("打开样张 PDF") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: samplePath))
                    }
                    .buttonStyle(.bordered)
                }
                .padding(10)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(6)
            } else {
                Text("点击上方按钮生成样张 PDF 以解锁定稿步骤。")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Step 4 View: Freeze Style
    // MARK: - Step 4 View: Freeze Style
    private var step4View: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button(wizardState.isStyleFrozen ? "重新基线定稿" : "基线定稿 (冻结当前风格)") {
                    onFreezeStyle { success in
                        if success {
                            var current = wizardState
                            current.isStyleFrozen = true
                            if current.maxUnlockedStep < 5 {
                                current.maxUnlockedStep = 5
                            }
                            updateWizardState(current)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                
                if wizardState.isStyleFrozen {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("风格已冻结 (StyleProfile)")
                            .font(.subheadline)
                            .bold()
                            .foregroundColor(.green)
                    }
                }
            }
            
            // 1. Spec Pack Support Rate
            if let spec = state.importedSpecResult {
                VStack(alignment: .leading, spacing: 6) {
                    let unsupported = spec.unsupportedFields
                    let fontCount = spec.fontResolutions.count
                    let colorCount = spec.roleColors.count
                    let supportedCount = fontCount + colorCount
                    let totalCount = supportedCount + unsupported.count
                    let rate = totalCount > 0 ? Double(supportedCount) / Double(totalCount) : 1.0
                    
                    HStack {
                        Text("规范包解析与支持率")
                            .font(.caption)
                            .bold()
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.0f%%", rate * 100))
                            .font(.caption)
                            .bold()
                            .foregroundColor(rate > 0.8 ? .green : .orange)
                    }
                    
                    // Simple progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: 6)
                            Rectangle()
                                .fill(rate > 0.8 ? Color.green : Color.orange)
                                .frame(width: geo.size.width * CGFloat(rate), height: 6)
                        }
                        .cornerRadius(3)
                    }
                    .frame(height: 6)
                    
                    Text("包含 \(fontCount) 个字体映射，\(colorCount) 个角色色值。")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    if !unsupported.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("暂不支持的字段 (\(unsupported.count)):")
                                .font(.system(size: 9))
                                .bold()
                                .foregroundColor(.orange)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 4) {
                                    ForEach(unsupported, id: \.self) { field in
                                        Text(field)
                                            .font(.system(size: 8, design: .monospaced))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.orange.opacity(0.1))
                                            .cornerRadius(3)
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(10)
                .background(Color.gray.opacity(0.04))
                .cornerRadius(6)
            }
            
            // 2. Style Report v0
            if let report = state.project.styleReport {
                VStack(alignment: .leading, spacing: 10) {
                    Text("项目风格分析报告 (v0)")
                        .font(.headline)
                        .bold()
                    
                    Divider()
                    
                    // Token Coverage
                    HStack {
                        Text("Token 覆盖率")
                            .font(.subheadline)
                            .bold()
                        Spacer()
                        Text(String(format: "%.0f%%", report.tokenCoverage * 100))
                            .font(.subheadline)
                            .bold()
                            .foregroundColor(report.tokenCoverage > 0.7 ? .green : .orange)
                    }
                    
                    // Motif checklist
                    VStack(alignment: .leading, spacing: 6) {
                        Text("视觉标识 (Motifs) 出现清单:")
                            .font(.caption)
                            .bold()
                            .foregroundColor(.secondary)
                        
                        let sortedMotifs = report.motifsChecklist.sorted(by: { $0.key < $1.key })
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                            ForEach(sortedMotifs, id: \.key) { key, active in
                                HStack {
                                    Image(systemName: active ? "checkmark.square.fill" : "square")
                                        .foregroundColor(active ? .green : .secondary)
                                    Text(key)
                                        .font(.system(size: 11))
                                        .foregroundColor(active ? .primary : .secondary)
                                    Spacer()
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Layout repetition limits
                    HStack {
                        Text("版式最大连续重复数:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(report.layoutRepeatCount) 页")
                            .font(.caption)
                            .bold()
                        
                        if report.repeatViolationCount > 0 {
                            Text("⚠️ 超过限额")
                                .font(.system(size: 10))
                                .bold()
                                .foregroundColor(.red)
                        } else {
                            Text("✅ 合规")
                                .font(.system(size: 10))
                                .bold()
                                .foregroundColor(.green)
                        }
                    }
                    
                    // Overlaps and Overflows
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: report.overlapsCheck ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundColor(report.overlapsCheck ? .orange : .green)
                            Text("重叠框检测")
                                .font(.caption)
                            Spacer()
                        }
                        
                        HStack(spacing: 4) {
                            Image(systemName: report.overflowsCheck ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundColor(report.overflowsCheck ? .orange : .green)
                            Text("文本溢出检测")
                                .font(.caption)
                            Spacer()
                        }
                    }
                    .padding(6)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(4)
                    
                    // Density distribution
                    VStack(alignment: .leading, spacing: 4) {
                        Text("每页图文空间密度:")
                            .font(.caption)
                            .bold()
                            .foregroundColor(.secondary)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(report.densityReport, id: \.pageNumber) { page in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("第 \(page.pageNumber) 页")
                                            .font(.system(size: 9))
                                            .bold()
                                        Text("文流: \(Int(page.textDensity * 100))%")
                                            .font(.system(size: 8))
                                        Text("图片: \(Int(page.imageDensity * 100))%")
                                            .font(.system(size: 8))
                                        Text(page.layoutStrategy)
                                            .font(.system(size: 7))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(6)
                                    .background(Color.gray.opacity(0.08))
                                    .cornerRadius(4)
                                    .frame(width: 80)
                                }
                            }
                        }
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.03))
                .cornerRadius(8)
                .border(Color.gray.opacity(0.1), width: 1)
            }
        }
    }
    
    // MARK: - Step 5 View: Spread Archetypes
    private var hasWorkhorse: Bool {
        isArchetypeEnabled("running-text")
    }
    
    private func roleColor(for role: ArchetypeRole) -> Color {
        switch role {
        case .opener: return .blue
        case .workhorse: return .green
        case .breathing: return .purple
        case .feature: return .orange
        case .reference: return .gray
        }
    }
    
    private func roleDescription(for role: ArchetypeRole) -> String {
        switch role {
        case .opener: return "用于每章第一对开，非对称，左页章节大字+引言，右页正文起"
        case .workhorse: return "主力骨架，两栏对开正文河，挂载页眉与页码"
        case .breathing: return "图文气口对开，一页主图/跨页出血，调整排版节奏"
        case .feature: return "金句与大抽言强调对开，正文围绕"
        case .reference: return "知识卡片与参考边栏对开"
        }
    }

    private var step5View: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("对开骨架选择与控制")
                .font(.headline)
            
            Text("请圈选本书允许使用的对开骨架，并微调权重。")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if !hasWorkhorse {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("⚠️ 必须启用至少一个正文流骨架（正文流对开），以确保正文流正常排版。")
                        .font(.caption)
                        .bold()
                        .foregroundColor(.red)
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            }
            
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(SpreadArchetype.defaults) { archetype in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top) {
                                Toggle("", isOn: Binding(
                                    get: { self.isArchetypeEnabled(archetype.id) },
                                    set: { _ in self.toggleArchetype(archetype.id) }
                                ))
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(archetype.displayName)
                                            .font(.subheadline)
                                            .bold()
                                        
                                        Text(archetype.role.rawValue.uppercased())
                                            .font(.system(size: 8, weight: .bold))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(roleColor(for: archetype.role))
                                            .cornerRadius(3)
                                            .foregroundColor(.white)
                                    }
                                    
                                    Text(roleDescription(for: archetype.role))
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                            
                            // Live rendered wireframe preview
                            Image(nsImage: WireframeRenderer.renderSpread(archetype: archetype))
                                .resizable()
                                .scaledToFit()
                                .frame(height: 120)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                                .opacity(self.isArchetypeEnabled(archetype.id) ? 1.0 : 0.4)
                            
                            if self.isArchetypeEnabled(archetype.id) {
                                HStack(spacing: 8) {
                                    Text("权重 (Weight):")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                    
                                    Slider(value: Binding(
                                        get: { self.getArchetypeWeight(archetype.id) },
                                        set: { val in self.setArchetypeWeight(archetype.id, weight: Double(round(10 * val) / 10)) }
                                    ), in: 0.2...2.0, step: 0.1)
                                    
                                    Text(String(format: "%.1f", self.getArchetypeWeight(archetype.id)))
                                        .font(.system(size: 9, design: .monospaced))
                                        .bold()
                                        .frame(width: 25)
                                }
                                .padding(.top, 4)
                            }
                        }
                        .padding(10)
                        .background(Color.gray.opacity(0.03))
                        .cornerRadius(6)
                    }
                }
            }
            .frame(maxHeight: 400)
            
            Divider()
            
            Button("运行受控变体规划器 (自动配骨架)") {
                onRunPlanner { archetypes in
                    if let archetypes {
                        var current = wizardState
                        current.chosenArchetypes = archetypes
                        if current.maxUnlockedStep < 6 {
                            current.maxUnlockedStep = 6
                        }
                        updateWizardState(current)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasWorkhorse)
            
            if !wizardState.chosenArchetypes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("对开规划完成！")
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(.green)
                    
                    Text("已自动选取以下对开骨架（SpreadArchetypes）：")
                        .font(.caption)
                        .bold()
                    
                    ForEach(wizardState.chosenArchetypes.indices, id: \.self) { idx in
                        let leftPage = idx * 2 + 1
                        let rightPage = leftPage + 1
                        let isLocked = (state.project.lockedPages ?? []).contains(leftPage) ||
                                       (state.project.lockedPages ?? []).contains(rightPage)
                        
                        HStack {
                            Text("Spread \(idx + 1) (Page \(leftPage)-\(rightPage)): \(wizardState.chosenArchetypes[idx])")
                                .font(.system(size: 10, design: .monospaced))
                            
                            if isLocked {
                                Text("🔒 已锁定")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                onRerollSpread(idx) { archetypes in
                                    if let archetypes {
                                        var current = wizardState
                                        current.chosenArchetypes = archetypes
                                        updateWizardState(current)
                                    }
                                }
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 9))
                                    .foregroundColor(isLocked ? .gray : .accentColor)
                            }
                            .buttonStyle(.plain)
                            .disabled(isLocked)
                            .help(isLocked ? "该对开页面已锁定，不可重抽" : "重抽这一页的对开骨架")
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(10)
                .background(Color.green.opacity(0.05))
                .cornerRadius(6)
            }
        }
    }
    
    // MARK: - Step 6 View: Export IDML
    private var step6View: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("导出最终 IDML...") {
                onExportIDML { path in
                    if let path {
                        var current = wizardState
                        current.exportedIDMLPath = path
                        updateWizardState(current)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            
            if let idmlPath = wizardState.exportedIDMLPath {
                VStack(alignment: .leading, spacing: 8) {
                    Text("IDML 导出成功！")
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(.green)
                    
                    Text("路径：\(idmlPath)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("在 Finder 中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: idmlPath)])
                    }
                    .buttonStyle(.bordered)
                }
                .padding(10)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(6)
            } else {
                Text("初排完成，导出 IDML 交 InDesign 做人工精调和印前输出。")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Helper Methods
    private func stepName(for step: Int) -> String {
        switch step {
        case 1: return "输入参考图"
        case 2: return "导入规范包"
        case 3: return "生成预览样张"
        case 4: return "锁定基线定稿"
        case 5: return "分配对开骨架"
        case 6: return "导出 IDML"
        default: return ""
        }
    }
    
    private func stepDescription(for step: Int) -> String {
        switch step {
        case 1: return "收集视觉参考样式图，作为排版风格基准。"
        case 2: return "解析导入 Figma/DTCG JSON 或方案规范包。"
        case 3: return "排版并渲染 PDF 样张，进行视觉检查。"
        case 4: return "冻结当前版面、字阶和颜色作为定稿基线。"
        case 5: return "运行受控变体规划器，自动排定全书对开骨架。"
        case 6: return "完成流水线，导出高质量 IDML 文档交棒 InDesign。"
        default: return ""
        }
    }
    
    private func handleStepNavigation(to step: Int) {
        guard step >= 1 && step <= 6 else { return }
        
        if step < wizardState.currentStep {
            // Warn if going back to a step that would require resetting downstream states
            targetStep = step
            showResetWarning = true
        } else {
            performNavigation(to: step)
        }
    }
    
    private func performNavigation(to step: Int) {
        var current = wizardState
        current.currentStep = step
        
        // Downstream resets if navigating back
        if step < wizardState.currentStep {
            current.maxUnlockedStep = step
            if step < 6 { current.exportedIDMLPath = nil }
            if step < 5 { current.chosenArchetypes = [] }
            if step < 4 { current.isStyleFrozen = false }
            if step < 3 { current.samplePDFPath = nil }
            if step < 2 {
                current.specPackPath = nil
                current.specPackName = nil
            }
            if step < 1 { current.referenceImages = [] }
        }
        
        updateWizardState(current)
    }
    
    private func updateWizardState(_ newState: WizardState) {
        state.updateProject { proj in
            proj.wizardState = newState
        }
    }

    private func isArchetypeEnabled(_ id: String) -> Bool {
        return wizardState.enabledArchetypeIds?.contains(id) ?? true
    }
    
    private func toggleArchetype(_ id: String) {
        var current = wizardState
        var enabled = current.enabledArchetypeIds ?? SpreadArchetype.defaults.map(\.id)
        if enabled.contains(id) {
            enabled.removeAll { $0 == id }
        } else {
            enabled.append(id)
        }
        current.enabledArchetypeIds = enabled
        updateWizardState(current)
    }
    
    private func getArchetypeWeight(_ id: String) -> Double {
        return wizardState.archetypeWeights?[id] ?? (SpreadArchetype.defaults.first(where: { $0.id == id })?.weight ?? 1.0)
    }
    
    private func setArchetypeWeight(_ id: String, weight: Double) {
        var current = wizardState
        var weights = current.archetypeWeights ?? [:]
        weights[id] = weight
        current.archetypeWeights = weights
        updateWizardState(current)
    }
}

// MARK: - StepBarView Component
struct StepBarView: View {
    let currentStep: Int
    let maxUnlockedStep: Int
    let onStepSelected: (Int) -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...6, id: \.self) { step in
                Button(action: {
                    onStepSelected(step)
                }) {
                    VStack(spacing: 4) {
                        Circle()
                            .fill(circleColor(for: step))
                            .frame(width: 20, height: 20)
                            .overlay(
                                Text("\(step)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(textColor(for: step))
                            )
                        Text(stepLabel(for: step))
                            .font(.system(size: 8))
                            .foregroundColor(labelColor(for: step))
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(step > maxUnlockedStep && step != currentStep)
                
                if step < 6 {
                    Rectangle()
                        .fill(step < maxUnlockedStep ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 9)
                }
            }
        }
        .padding(.horizontal, 12)
    }
    
    private func circleColor(for step: Int) -> Color {
        if step == currentStep {
            return .accentColor
        } else if step < currentStep {
            return .accentColor.opacity(0.7)
        } else if step <= maxUnlockedStep {
            return Color.gray.opacity(0.4)
        } else {
            return Color.gray.opacity(0.15)
        }
    }
    
    private func textColor(for step: Int) -> Color {
        if step == currentStep || step < currentStep {
            return .white
        } else {
            return .primary.opacity(0.6)
        }
    }
    
    private func labelColor(for step: Int) -> Color {
        if step == currentStep {
            return .primary
        } else if step < currentStep {
            return .primary.opacity(0.8)
        } else {
            return .secondary.opacity(0.6)
        }
    }
    
    private func stepLabel(for step: Int) -> String {
        switch step {
        case 1: return "参考"
        case 2: return "规范"
        case 3: return "样张"
        case 4: return "定稿"
        case 5: return "骨架"
        case 6: return "IDML"
        default: return ""
        }
    }
}
