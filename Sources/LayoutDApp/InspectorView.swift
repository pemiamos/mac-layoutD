import SwiftUI
import LayoutDCore
import LayoutDCheck

struct InspectorView: View {
    @ObservedObject var state: AppState
    var onIssueClick: (LayoutIssue) -> Void
    var onApplyPlan: (LayoutPlan) -> Void

    @State private var selectedElement = true
    @State private var selectedMetadata = true
    @State private var selectedSetup = true
    @State private var selectedStyles = true
    @State private var selectedIssues = true
    @State private var selectedAI = true
    @State private var selectedPageControl = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Section 1: Preflight Status Header
                if let report = state.report {
                    preflightHeader(report: report)
                    Divider()
                }

                // Section 1.2: Page Control
                DisclosureGroup("页面控制 (第 \(state.currentPageNumber) 页)", isExpanded: $selectedPageControl) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("锁定当前页版式", isOn: Binding(
                            get: { state.project.safeLockedPages.contains(state.currentPageNumber) },
                            set: { isLocked in
                                if isLocked {
                                    state.lockPage(number: state.currentPageNumber)
                                } else {
                                    state.unlockPage(number: state.currentPageNumber)
                                }
                            }
                        ))
                        .toggleStyle(.checkbox)
                        
                        if state.project.safeLockedPages.contains(state.currentPageNumber) {
                            Text("⚠️ 页面已锁定，元素无法在画布上拖拽或修改尺寸。")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.top, 6)
                }
                Divider()

                // Section 1.5: Selected Frame Editor (Interactive Selection)
                if let selectedId = state.selectedFrameId,
                   let pageNum = state.findPageNumber(for: selectedId),
                   let doc = state.laidOutDocument,
                   let targetPage = doc.pages.first(where: { $0.number == pageNum }),
                   let frame = targetPage.frames.first(where: { $0.id == selectedId }) {
                    
                    let isPageLocked = state.project.safeLockedPages.contains(pageNum)
                    
                    DisclosureGroup("选中元素属性", isExpanded: $selectedElement) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("类型: \(frame.kind.rawValue.capitalized)  (第 \(pageNum) 页)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                                GridRow {
                                    Text("X 坐标:")
                                    Stepper(String(format: "%.0f pt", frame.rect.x), onIncrement: {
                                        state.updateSelectedFrameCoordinate(x: frame.rect.x + 5, y: nil, width: nil, height: nil)
                                    }, onDecrement: {
                                        state.updateSelectedFrameCoordinate(x: frame.rect.x - 5, y: nil, width: nil, height: nil)
                                    })
                                }
                                GridRow {
                                    Text("Y 坐标:")
                                    Stepper(String(format: "%.0f pt", frame.rect.y), onIncrement: {
                                        state.updateSelectedFrameCoordinate(x: nil, y: frame.rect.y + 5, width: nil, height: nil)
                                    }, onDecrement: {
                                        state.updateSelectedFrameCoordinate(x: nil, y: frame.rect.y - 5, width: nil, height: nil)
                                    })
                                }
                                GridRow {
                                    Text("宽度:")
                                    Stepper(String(format: "%.0f pt", frame.rect.width), onIncrement: {
                                        state.updateSelectedFrameCoordinate(x: nil, y: nil, width: frame.rect.width + 5, height: nil)
                                    }, onDecrement: {
                                        state.updateSelectedFrameCoordinate(x: nil, y: nil, width: frame.rect.width - 5, height: nil)
                                    })
                                }
                                GridRow {
                                    Text("高度:")
                                    Stepper(String(format: "%.0f pt", frame.rect.height), onIncrement: {
                                        state.updateSelectedFrameCoordinate(x: nil, y: nil, width: nil, height: frame.rect.height + 5)
                                    }, onDecrement: {
                                        state.updateSelectedFrameCoordinate(x: nil, y: nil, width: nil, height: frame.rect.height - 5)
                                    })
                                }
                            }
                            .disabled(isPageLocked)
                            
                            if frame.kind == .image, case .asset(let currentAssetId) = frame.content {
                                Divider()
                                Picker("更换图片", selection: Binding(
                                    get: { currentAssetId },
                                    set: { state.updateSelectedFrameImage(assetId: $0) }
                                )) {
                                    ForEach(state.project.assets) { asset in
                                        Text(asset.fileName).tag(asset.id)
                                    }
                                }
                                .disabled(isPageLocked)
                            }
                            
                            Divider()
                            
                            HStack {
                                Spacer()
                                Button("恢复流式排版") {
                                    state.clearCustomLayoutForSelectedFramePage()
                                }
                                .buttonStyle(.bordered)
                                .foregroundColor(.red)
                                .disabled(isPageLocked)
                                Spacer()
                            }
                            .padding(.top, 4)
                        }
                        .padding(.top, 6)
                    }
                    Divider()
                }

                // Section 2: Book Metadata
                DisclosureGroup("图书元数据", isExpanded: $selectedMetadata) {
                    VStack(spacing: 8) {
                        HStack {
                            Text("书名").frame(width: 50, alignment: .leading)
                            TextField("书名", text: $state.project.metadata.title)
                        }
                        HStack {
                            Text("副标题").frame(width: 50, alignment: .leading)
                            TextField("副标题", text: Binding(
                                get: { state.project.metadata.subtitle ?? "" },
                                set: { state.project.metadata.subtitle = $0.isEmpty ? nil : $0 }
                            ))
                        }
                        HStack {
                            Text("作者").frame(width: 50, alignment: .leading)
                            TextField("作者", text: $state.project.metadata.author)
                        }
                        HStack {
                            Text("出版社").frame(width: 50, alignment: .leading)
                            TextField("出版社", text: Binding(
                                get: { state.project.metadata.publisher ?? "" },
                                set: { state.project.metadata.publisher = $0.isEmpty ? nil : $0 }
                            ))
                        }
                        HStack {
                            Text("ISBN").frame(width: 50, alignment: .leading)
                            TextField("ISBN", text: Binding(
                                get: { state.project.metadata.isbn ?? "" },
                                set: { state.project.metadata.isbn = $0.isEmpty ? nil : $0 }
                            ))
                        }
                    }
                    .padding(.top, 6)
                    .textFieldStyle(.roundedBorder)
                }

                Divider()

                // Section 3: Page Layout Setup
                DisclosureGroup("版面参数设置", isExpanded: $selectedSetup) {
                    VStack(spacing: 10) {
                        HStack {
                            Text("分栏数")
                            Spacer()
                            Stepper("\(state.project.pageSetup.columns) 栏", value: $state.project.pageSetup.columns, in: 1...4)
                        }
                        
                        HStack {
                            Text("栏间距 (mm)")
                            Spacer()
                            Stepper(String(format: "%.1f mm", state.project.pageSetup.gutter), value: $state.project.pageSetup.gutter, in: 2.0...15.0, step: 0.5)
                        }
                        
                        HStack {
                            Text("基线网格 (pt)")
                            Spacer()
                            Stepper("\(Int(state.project.pageSetup.baselineGrid)) pt", value: $state.project.pageSetup.baselineGrid, in: 8...24, step: 1)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("页边距 (Margins)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Text("上:")
                                Stepper("\(Int(state.project.pageSetup.margins.top))", value: $state.project.pageSetup.margins.top, in: 10...50)
                                Spacer()
                                Text("下:")
                                Stepper("\(Int(state.project.pageSetup.margins.bottom))", value: $state.project.pageSetup.margins.bottom, in: 10...50)
                            }
                            HStack {
                                Text("左:")
                                Stepper("\(Int(state.project.pageSetup.margins.left))", value: $state.project.pageSetup.margins.left, in: 10...50)
                                Spacer()
                                Text("右:")
                                Stepper("\(Int(state.project.pageSetup.margins.right))", value: $state.project.pageSetup.margins.right, in: 10...50)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(.top, 6)
                }

                Divider()

                // Section 4: Styles Editor
                DisclosureGroup("段落样式参数", isExpanded: $selectedStyles) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(state.project.styles.paragraphStyles.indices, id: \.self) { index in
                            styleRow(index: index)
                        }
                    }
                    .padding(.top, 6)
                }

                Divider()

                // Section 5: Preflight Issues
                DisclosureGroup("排版问题检查 (\(state.report?.issues.count ?? 0))", isExpanded: $selectedIssues) {
                    if let report = state.report {
                        if report.issues.isEmpty {
                            Text("无任何排版问题")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(report.issues, id: \.id) { issue in
                                    Button(action: {
                                        onIssueClick(issue)
                                    }) {
                                        HStack(alignment: .top, spacing: 6) {
                                            issueIcon(issue.severity)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(issue.message)
                                                    .font(.subheadline)
                                                    .foregroundColor(.primary)
                                                    .multilineTextAlignment(.leading)
                                                    .lineLimit(2)
                                                if let page = issue.pageNumber {
                                                    Text("第 \(page) 页")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            Spacer()
                                        }
                                        .padding(.all, 8)
                                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 6)
                        }
                    } else {
                        Text("无可用报告")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Section 6: AI Candidates
                DisclosureGroup("AI LayoutPlan 布局候选", isExpanded: $selectedAI) {
                    if state.plans.isEmpty {
                        Text("暂无布局候选")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(state.plans) { plan in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(plan.strategy.rawValue.capitalized)
                                            .font(.headline)
                                            .foregroundColor(Color(nsColor: NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.46, alpha: 1)))
                                        Spacer()
                                        Button(action: {
                                            onApplyPlan(plan)
                                        }) {
                                            Text("应用布局")
                                                .font(.caption)
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(Color(nsColor: NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.46, alpha: 1)))
                                                .cornerRadius(4)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    
                                    Text("\(plan.blocks.count) 个布局块 (Blocks)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    ForEach(plan.notes, id: \.self) { note in
                                        Text("• \(note)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                .padding(.all, 10)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                            }
                        }
                        .padding(.top, 6)
                    }
                }
            }
            .padding(.all, 14)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // Sub-view: Preflight Header
    private func preflightHeader(report: PreflightReport) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("项目状态")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(report.isExportReady ? "可安全导出 PDF" : "存在错误需修复")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(report.isExportReady ? .green : .red)
            }
            Spacer()
            Image(systemName: report.isExportReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(report.isExportReady ? .green : .red)
                .font(.system(size: 28))
        }
        .padding(.horizontal, 4)
    }

    // Sub-view: Style Edit Row
    private func styleRow(index: Int) -> some View {
        let style = state.project.styles.paragraphStyles[index]
        return VStack(alignment: .leading, spacing: 6) {
            Text(style.displayName)
                .font(.subheadline)
                .fontWeight(.medium)
            
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("字号:")
                    Stepper(String(format: "%.1f pt", style.fontSize), value: Binding(
                        get: { style.fontSize },
                        set: { state.updateParagraphStyle(id: style.id, fontSize: $0) }
                    ), in: 8.0...36.0, step: 0.5)
                    
                    Text("行高:")
                    Stepper("\(Int(style.lineHeight)) pt", value: Binding(
                        get: { style.lineHeight },
                        set: { state.updateParagraphStyle(id: style.id, lineHeight: $0) }
                    ), in: 10.0...50.0, step: 1.0)
                }
                
                GridRow {
                    Text("段前:")
                    Stepper("\(Int(style.spaceBefore)) pt", value: Binding(
                        get: { style.spaceBefore },
                        set: { state.updateParagraphStyle(id: style.id, spaceBefore: $0) }
                    ), in: 0.0...40.0, step: 1.0)
                    
                    Text("段后:")
                    Stepper("\(Int(style.spaceAfter)) pt", value: Binding(
                        get: { style.spaceAfter },
                        set: { state.updateParagraphStyle(id: style.id, spaceAfter: $0) }
                    ), in: 0.0...40.0, step: 1.0)
                }
                
                if style.id == StyleID.body.rawValue {
                    GridRow {
                        Text("缩进:")
                        Stepper("\(Int(style.firstLineIndent)) pt", value: Binding(
                            get: { style.firstLineIndent },
                            set: { state.updateParagraphStyle(id: style.id, firstLineIndent: $0) }
                        ), in: 0.0...40.0, step: 1.0)
                    }
                }
            }
            .font(.caption)
        }
        .padding(.all, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(6)
    }

    // Sub-view: Issue Icon
    private func issueIcon(_ severity: IssueSeverity) -> some View {
        let color: Color
        let name: String
        switch severity {
        case .error:
            color = .red
            name = "xmark.circle.fill"
        case .warning:
            color = .orange
            name = "exclamationmark.triangle.fill"
        case .info:
            color = .blue
            name = "info.circle.fill"
        }
        return Image(systemName: name)
            .foregroundColor(color)
            .font(.system(size: 14))
    }
}
