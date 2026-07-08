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
    private var step4View: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("风格已冻结！")
                            .font(.subheadline)
                            .bold()
                    }
                    
                    Text("已成功将当前规范包的字体、角色色和版边距锁定为本项目基线（StyleProfile）。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(6)
            } else {
                Text("定稿会冻结当前的视觉规则与文字基线，完成后方可进行骨架选择与初排。")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Step 5 View: Spread Archetypes
    private var step5View: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            
            if !wizardState.chosenArchetypes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("对开规划完成！")
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(.green)
                    
                    Text("已自动选取以下骨架（Archetypes）：")
                        .font(.caption)
                        .bold()
                    
                    ForEach(wizardState.chosenArchetypes.indices, id: \.self) { idx in
                        Text("Page \(idx + 1): \(wizardState.chosenArchetypes[idx])")
                            .font(.system(size: 10, design: .monospaced))
                    }
                }
                .padding(10)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(6)
            } else {
                Text("运行规划器为各页自动分配合适的对开骨架，支持手工微调。")
                    .font(.callout)
                    .foregroundColor(.secondary)
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
